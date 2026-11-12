import {
  AuthProfile,
  AppError,
  QrLoginPoll,
  QrLoginStart,
  emptyAuthProfile
} from '../types/MobileTypes';
import { toAppError, NativeError, SAFE_UNKNOWN_ERROR_MESSAGE } from '../util/Errors';

const DEFAULT_POLL_INTERVAL_MS = 2_000;

export type AuthStatus =
  'idle' | 'starting' | 'waiting' | 'scanned' | 'success' | 'expired' | 'cancelled' | 'error';

/**
 * 页头账号区的资料状态：
 * - loading：有登录 Cookie，但本地还没有资料，正在后台请求 /nav；
 * - ready：已有资料（缓存或刚刷新成功）；
 * - loggedOut：确认没有登录凭证；
 * - error：有凭证但刷新失败，且没有可用的缓存资料。
 */
export type AuthProfileState = 'loading' | 'ready' | 'loggedOut' | 'error';

export interface AuthStoreSnapshot {
  status: AuthStatus;
  profile: AuthProfile;
  qrUrl: string;
  expiresAt: number;
  error: AppError | null;
}

export interface AuthGateway {
  startQrLogin(): Promise<QrLoginStart>;
  pollQrLogin(): Promise<QrLoginPoll>;
  refreshProfile(): Promise<AuthProfile>;
  status(): AuthProfile;
  hasLoginCredentials(): boolean;
  logout(): Promise<AuthProfile>;
  currentQrUrl(): string;
  cancelQrLogin(): void;
}

export interface AuthStoreListener {
  onAuthChanged(profile: AuthProfile): void;
}

export interface AuthTimerScheduler {
  schedule(callback: () => Promise<void>, delayMs: number): number;
  cancel(timerId: number): void;
}

class PlatformAuthTimerScheduler implements AuthTimerScheduler {
  schedule(callback: () => Promise<void>, delayMs: number): number {
    return setTimeout((): void => {
      callback().catch((): void => {});
    }, delayMs);
  }

  cancel(timerId: number): void {
    clearTimeout(timerId);
  }
}

@Observed
export class AuthStore {
  @Track snapshot: AuthStoreSnapshot;
  @Track profileState: AuthProfileState;

  private readonly gateway: AuthGateway;
  private readonly timerScheduler: AuthTimerScheduler;
  private readonly pollIntervalMs: number;
  private listener: AuthStoreListener | null = null;
  private generation: number = 0;
  private timerId: number = -1;
  private startPromise: Promise<void> | null = null;
  private activeSession: boolean = false;
  private disposed: boolean = false;

  constructor(gateway: AuthGateway,
    timerScheduler: AuthTimerScheduler = new PlatformAuthTimerScheduler(),
    pollIntervalMs: number = DEFAULT_POLL_INTERVAL_MS) {
    this.gateway = gateway;
    this.timerScheduler = timerScheduler;
    this.pollIntervalMs = Number.isFinite(pollIntervalMs)
      ? Math.max(250, Math.floor(pollIntervalMs))
      : DEFAULT_POLL_INTERVAL_MS;
    const profile = gateway.status();
    this.snapshot = idleSnapshot(profile);
    this.profileState = profile.isLogin ? 'ready' :
      (gateway.hasLoginCredentials() ? 'loading' : 'loggedOut');
  }

  read(): AuthStoreSnapshot {
    return cloneSnapshot(this.snapshot);
  }

  setListener(listener: AuthStoreListener | null): void {
    this.listener = listener;
  }

  startQrLogin(): Promise<void> {
    if (this.disposed) {
      return Promise.resolve();
    }
    if (this.snapshot.status === 'waiting' || this.snapshot.status === 'scanned') {
      return Promise.resolve();
    }
    if (this.startPromise !== null) {
      if (this.snapshot.status === 'starting') {
        return this.startPromise;
      }
      const previous = this.startPromise;
      return previous.then((): Promise<void> => this.startQrLogin());
    }

    this.generation++;
    const generation = this.generation;
    this.stopTimer();
    this.activeSession = true;
    this.snapshot = {
      status: 'starting',
      profile: cloneProfile(this.snapshot.profile),
      qrUrl: '',
      expiresAt: 0,
      error: null
    };

    const operation = this.performStart(generation);
    const tracked = operation.then((): void => {
      this.startPromise = null;
    }, (): void => {
      this.startPromise = null;
    });
    this.startPromise = tracked;
    return tracked;
  }

  cancelQrLogin(): void {
    if (this.disposed) {
      return;
    }
    this.generation++;
    this.activeSession = false;
    this.stopTimer();
    this.cancelGatewaySession();
    this.snapshot = {
      status: 'cancelled',
      profile: cloneProfile(this.snapshot.profile),
      qrUrl: '',
      expiresAt: 0,
      error: null
    };
  }

  async logout(): Promise<AuthProfile> {
    this.generation++;
    this.activeSession = false;
    this.stopTimer();
    this.cancelGatewaySession();
    this.snapshot = idleSnapshot(this.snapshot.profile);
    try {
      const profile = cloneProfile(await this.gateway.logout());
      this.snapshot = idleSnapshot(profile);
      this.profileState = profile.isLogin ? 'ready' : 'loggedOut';
      this.notifyAuthChanged(profile);
      return cloneProfile(profile);
    } catch (error) {
      const appError = safeAuthError(error as Object);
      this.snapshot = {
        status: 'error',
        profile: cloneProfile(gatewayProfile(this.gateway, this.snapshot.profile)),
        qrUrl: '',
        expiresAt: 0,
        error: appError
      };
      this.profileState = this.snapshot.profile.isLogin ? 'ready' : 'loggedOut';
      throw new NativeError(appError.code, appError.message, appError.retryable);
    }
  }

  async refreshProfile(): Promise<AuthProfile> {
    if (!this.disposed && !this.snapshot.profile.isLogin) {
      this.profileState = 'loading';
    }
    try {
      const profile = cloneProfile(await this.gateway.refreshProfile());
      if (!this.disposed) {
        this.snapshot = {
          status: this.snapshot.status,
          profile: profile,
          qrUrl: this.snapshot.qrUrl,
          expiresAt: this.snapshot.expiresAt,
          error: this.snapshot.error
        };
        this.profileState = profile.isLogin ? 'ready' : 'loggedOut';
      }
      return cloneProfile(profile);
    } catch (error) {
      if (!this.disposed) {
        this.profileState = this.snapshot.profile.isLogin ? 'ready' : 'error';
      }
      throw error as Error;
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.generation++;
    this.activeSession = false;
    this.stopTimer();
    this.cancelGatewaySession();
    this.snapshot = {
      status: 'cancelled',
      profile: cloneProfile(this.snapshot.profile),
      qrUrl: '',
      expiresAt: 0,
      error: null
    };
    this.listener = null;
  }

  private async performStart(generation: number): Promise<void> {
    try {
      const start = await this.gateway.startQrLogin();
      if (!this.isCurrent(generation)) {
        this.cancelGatewaySession();
        return;
      }
      if (!this.activeSession || start.expiresAt <= Date.now()) {
        this.finishExpired(generation);
        return;
      }
      this.snapshot = {
        status: 'waiting',
        profile: cloneProfile(this.snapshot.profile),
        qrUrl: this.gateway.currentQrUrl(),
        expiresAt: start.expiresAt,
        error: null
      };
      this.schedulePoll(generation);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.finishError(generation, error as Object);
    }
  }

  private schedulePoll(generation: number): void {
    if (!this.isCurrent(generation) || !this.activeSession) {
      return;
    }
    const remainingMs = this.snapshot.expiresAt - Date.now();
    if (remainingMs <= 0) {
      this.finishExpired(generation);
      return;
    }
    const delayMs = Math.max(1, Math.min(this.pollIntervalMs, remainingMs));
    this.timerId = this.timerScheduler.schedule((): Promise<void> => this.poll(generation), delayMs);
  }

  private async poll(generation: number): Promise<void> {
    this.timerId = -1;
    if (!this.isCurrent(generation) || !this.activeSession) {
      return;
    }
    try {
      const result = await this.gateway.pollQrLogin();
      if (!this.isCurrent(generation) || !this.activeSession) {
        return;
      }
      if (result.status === 'waiting') {
        this.updatePollStage(generation, 'waiting');
        return;
      }
      if (result.status === 'scanned') {
        this.updatePollStage(generation, 'scanned');
        return;
      }
      if (result.status === 'expired') {
        this.finishExpired(generation);
        return;
      }
      if (result.status === 'success') {
        await this.finishSuccess(generation);
        return;
      }
      this.finishError(generation,
        new NativeError('auth.qrPollFailed', '登录状态无法识别，请重试。', true));
    } catch (error) {
      if (!this.isCurrent(generation) || !this.activeSession) {
        return;
      }
      if (toAppError(error as Object).retryable) {
        // 15s 超时或网络抖动不该结束 3 分钟的扫码会话：保留 activeSession，按下一轮继续。
        this.schedulePoll(generation);
        return;
      }
      this.finishError(generation, error as Object);
    }
  }

  private updatePollStage(generation: number, status: AuthStatus): void {
    if (!this.isCurrent(generation) || !this.activeSession) {
      return;
    }
    this.snapshot = {
      status: status,
      profile: cloneProfile(this.snapshot.profile),
      qrUrl: this.snapshot.qrUrl,
      expiresAt: this.snapshot.expiresAt,
      error: null
    };
    this.schedulePoll(generation);
  }

  private async finishSuccess(generation: number): Promise<void> {
    this.activeSession = false;
    this.stopTimer();
    try {
      const profile = cloneProfile(await this.gateway.refreshProfile());
      if (!this.isCurrent(generation)) {
        return;
      }
      if (!profile.isLogin) {
        throw new NativeError('auth.loginIncomplete', '登录未完成，请重新扫码。', true);
      }
      this.cancelGatewaySession();
      this.snapshot = {
        status: 'success',
        profile: profile,
        qrUrl: '',
        expiresAt: 0,
        error: null
      };
      this.profileState = 'ready';
      this.notifyAuthChanged(profile);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.finishError(generation, error as Object);
    }
  }

  private finishExpired(generation: number): void {
    if (!this.isCurrent(generation)) {
      return;
    }
    this.activeSession = false;
    this.stopTimer();
    this.cancelGatewaySession();
    this.snapshot = {
      status: 'expired',
      profile: cloneProfile(this.snapshot.profile),
      qrUrl: '',
      expiresAt: 0,
      error: null
    };
  }

  private finishError(generation: number, error: Object): void {
    if (!this.isCurrent(generation)) {
      return;
    }
    this.activeSession = false;
    this.stopTimer();
    this.cancelGatewaySession();
    this.snapshot = {
      status: 'error',
      profile: cloneProfile(this.snapshot.profile),
      qrUrl: '',
      expiresAt: 0,
      error: safeAuthError(error)
    };
  }

  private stopTimer(): void {
    if (this.timerId < 0) {
      return;
    }
    this.timerScheduler.cancel(this.timerId);
    this.timerId = -1;
  }

  private cancelGatewaySession(): void {
    try {
      this.gateway.cancelQrLogin();
    } catch (error) {
      // Controller state must still terminate when the service is already gone.
    }
  }

  private notifyAuthChanged(profile: AuthProfile): void {
    if (this.listener === null || this.disposed) {
      return;
    }
    try {
      this.listener.onAuthChanged(cloneProfile(profile));
    } catch (error) {
      // A detached listener must not keep login polling alive.
    }
  }

  private isCurrent(generation: number): boolean {
    return !this.disposed && generation === this.generation;
  }
}

function idleSnapshot(profile: AuthProfile): AuthStoreSnapshot {
  return {
    status: 'idle',
    profile: cloneProfile(profile),
    qrUrl: '',
    expiresAt: 0,
    error: null
  };
}

function cloneSnapshot(snapshot: AuthStoreSnapshot): AuthStoreSnapshot {
  return {
    status: snapshot.status,
    profile: cloneProfile(snapshot.profile),
    qrUrl: snapshot.qrUrl,
    expiresAt: snapshot.expiresAt,
    error: cloneError(snapshot.error)
  };
}

function cloneError(error: AppError | null): AppError | null {
  if (error === null) {
    return null;
  }
  return {
    code: error.code,
    message: error.message,
    retryable: error.retryable
  };
}

function cloneProfile(profile: AuthProfile): AuthProfile {
  if (profile === null || profile === undefined) {
    return emptyAuthProfile();
  }
  return {
    isLogin: profile.isLogin,
    mid: profile.mid,
    name: profile.name,
    avatarUrl: profile.avatarUrl,
    vip: profile.vip
  };
}

function gatewayProfile(gateway: AuthGateway, fallback: AuthProfile): AuthProfile {
  try {
    return gateway.status();
  } catch (error) {
    return fallback;
  }
}

function safeAuthError(error: Object): AppError {
  if (!(error instanceof NativeError)) {
    return {
      code: 'native.error',
      message: SAFE_UNKNOWN_ERROR_MESSAGE,
      retryable: false
    };
  }
  const fixed = fixedAuthError(error.appError.code);
  if (fixed !== null) {
    return fixed;
  }
  const converted = toAppError(error);
  return {
    code: converted.code,
    message: SAFE_UNKNOWN_ERROR_MESSAGE,
    retryable: converted.retryable
  };
}

function fixedAuthError(code: string): AppError | null {
  if (code === 'auth.qrGenerateFailed') {
    return {
      code: code,
      message: '登录二维码生成失败，请重试。',
      retryable: true
    };
  }
  if (code === 'auth.qrPollFailed') {
    return {
      code: code,
      message: '登录状态获取失败，请重试。',
      retryable: true
    };
  }
  if (code === 'auth.loginIncomplete') {
    return {
      code: code,
      message: '登录未完成，请重新扫码。',
      retryable: true
    };
  }
  if (code === 'auth.networkUnavailable') {
    return {
      code: code,
      message: '登录服务暂时不可用。',
      retryable: true
    };
  }
  if (code === 'auth.httpStatus') {
    return {
      code: code,
      message: '登录服务暂时不可用。',
      retryable: true
    };
  }
  if (code === 'auth.invalidResponse') {
    return {
      code: code,
      message: '登录服务返回了无法识别的数据。',
      retryable: true
    };
  }
  if (code === 'auth.redirectInvalid') {
    return {
      code: code,
      message: '登录跳转地址无效。',
      retryable: true
    };
  }
  if (code === 'auth.redirectBlocked') {
    return {
      code: code,
      message: '登录跳转到了不受信任的地址。',
      retryable: false
    };
  }
  if (code === 'auth.required') {
    return {
      code: code,
      message: '登录状态已失效，请重新扫码登录。',
      retryable: false
    };
  }
  if (code === 'auth.statusFailed') {
    return {
      code: code,
      message: '登录状态刷新失败，请稍后重试。',
      retryable: true
    };
  }
  if (code === 'auth.logoutFailed') {
    return {
      code: code,
      message: '退出登录失败，请稍后重试。',
      retryable: true
    };
  }
  return null;
}
