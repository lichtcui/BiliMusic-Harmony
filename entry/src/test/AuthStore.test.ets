import { describe, expect, it } from '@ohos/hypium';
import {
  AuthGateway,
  AuthStore,
  AuthStoreListener,
  AuthStoreSnapshot,
  AuthTimerScheduler
} from '../main/ets/state/AuthStore';
import {
  AuthProfile,
  QrLoginPoll,
  QrLoginStart,
  emptyAuthProfile
} from '../main/ets/types/MobileTypes';
import { NativeError, SAFE_UNKNOWN_ERROR_MESSAGE, wait } from '../main/ets/util/Errors';
import { closeLoginSheetSession } from '../main/ets/components/native/LoginPageState';

class PendingStart {
  readonly promise: Promise<QrLoginStart>;
  private resolveCallback: ((result: QrLoginStart) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor() {
    this.promise = new Promise<QrLoginStart>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: QrLoginStart): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }

  reject(error: Object): void {
    const callback = this.rejectCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

class PendingPoll {
  readonly promise: Promise<QrLoginPoll>;
  private resolveCallback: ((result: QrLoginPoll) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor() {
    this.promise = new Promise<QrLoginPoll>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: QrLoginPoll): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }

  reject(error: Object): void {
    const callback = this.rejectCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

class PendingProfile {
  readonly promise: Promise<AuthProfile>;
  private resolveCallback: ((result: AuthProfile) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor() {
    this.promise = new Promise<AuthProfile>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: AuthProfile): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }

  reject(error: Object): void {
    const callback = this.rejectCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

class PendingLogout {
  readonly promise: Promise<AuthProfile>;
  private resolveCallback: ((result: AuthProfile) => void) | null = null;

  constructor() {
    this.promise = new Promise<AuthProfile>((resolve) => {
      this.resolveCallback = resolve;
    });
  }

  resolve(result: AuthProfile): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }
}

class FakeAuthTimer {
  readonly id: number;
  readonly callback: () => Promise<void>;
  readonly delayMs: number;
  cancelled: boolean = false;
  ran: boolean = false;

  constructor(id: number, callback: () => Promise<void>, delayMs: number) {
    this.id = id;
    this.callback = callback;
    this.delayMs = delayMs;
  }
}

class FakeAuthTimerScheduler implements AuthTimerScheduler {
  readonly timers: FakeAuthTimer[] = [];
  readonly cancelledIds: number[] = [];
  scheduleCalls: number = 0;
  private nextId: number = 1;

  schedule(callback: () => Promise<void>, delayMs: number): number {
    const timer = new FakeAuthTimer(this.nextId++, callback, delayMs);
    this.timers.push(timer);
    this.scheduleCalls++;
    return timer.id;
  }

  cancel(timerId: number): void {
    this.cancelledIds.push(timerId);
    for (const timer of this.timers) {
      if (timer.id === timerId) {
        timer.cancelled = true;
      }
    }
  }

  pendingCount(): number {
    let count = 0;
    for (const timer of this.timers) {
      if (!timer.cancelled && !timer.ran) {
        count++;
      }
    }
    return count;
  }

  async runNext(): Promise<void> {
    for (const timer of this.timers) {
      if (!timer.cancelled && !timer.ran) {
        timer.ran = true;
        await timer.callback();
        return;
      }
    }
    throw new Error('No pending auth timer');
  }
}

class FakeAuthGateway implements AuthGateway {
  readonly starts: PendingStart[] = [];
  readonly polls: PendingPoll[] = [];
  readonly profiles: PendingProfile[] = [];
  readonly logouts: PendingLogout[] = [];
  cancelCalls: number = 0;
  qrUrl: string = '';
  credentialsPresent: boolean = false;
  private currentProfile: AuthProfile;

  constructor(profile: AuthProfile = emptyAuthProfile()) {
    this.currentProfile = profile;
  }

  startQrLogin(): Promise<QrLoginStart> {
    const pending = new PendingStart();
    this.starts.push(pending);
    return pending.promise;
  }

  pollQrLogin(): Promise<QrLoginPoll> {
    const pending = new PendingPoll();
    this.polls.push(pending);
    return pending.promise;
  }

  refreshProfile(): Promise<AuthProfile> {
    const pending = new PendingProfile();
    this.profiles.push(pending);
    return pending.promise;
  }

  status(): AuthProfile {
    return cloneProfile(this.currentProfile);
  }

  hasLoginCredentials(): boolean {
    return this.credentialsPresent;
  }

  logout(): Promise<AuthProfile> {
    const pending = new PendingLogout();
    this.logouts.push(pending);
    return pending.promise;
  }

  currentQrUrl(): string {
    return this.qrUrl;
  }

  cancelQrLogin(): void {
    this.cancelCalls++;
    this.qrUrl = '';
  }
}

class RecordingAuthListener implements AuthStoreListener {
  readonly profiles: AuthProfile[] = [];

  onAuthChanged(profile: AuthProfile): void {
    this.profiles.push(cloneProfile(profile));
  }
}

function loginProfile(): AuthProfile {
  return {
    isLogin: true,
    mid: 42,
    name: 'Listener',
    avatarUrl: 'https://example.invalid/avatar.jpg',
    vip: false
  };
}

async function startWaiting(store: AuthStore, gateway: FakeAuthGateway,
  scheduler: FakeAuthTimerScheduler): Promise<void> {
  const pending = store.startQrLogin();
  expect(gateway.starts.length).assertEqual(1);
  gateway.qrUrl = 'https://example.invalid/qr';
  gateway.starts[0].resolve({
    mode: 'native-overlay',
    expiresAt: Date.now() + 60_000
  });
  await pending;
  expect(store.read().status).assertEqual('waiting');
  expect(scheduler.pendingCount()).assertEqual(1);
}

function assertNoSensitiveValue(snapshot: AuthStoreSnapshot): void {
  const errorText = snapshot.error === null ? '' : snapshot.error.message;
  expect(snapshot.qrUrl.length).assertEqual(0);
  expect(errorText.includes('qrcode_key')).assertFalse();
  expect(errorText.toLowerCase().includes('cookie')).assertFalse();
  expect(errorText.includes('https://example.invalid/qr')).assertFalse();
}

export default function authStoreTest(): void {
  describe('AuthStore', () => {
    it('deduplicatesStartsAndMovesFromWaitingToScanned', 0, async () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const store = new AuthStore(gateway, scheduler, 10);

      const first = store.startQrLogin();
      const duplicate = store.startQrLogin();
      expect(gateway.starts.length).assertEqual(1);
      expect(store.read().status).assertEqual('starting');

      gateway.qrUrl = 'https://example.invalid/qr';
      gateway.starts[0].resolve({
        mode: 'native-overlay',
        expiresAt: Date.now() + 60_000
      });
      await Promise.all([first, duplicate]);

      expect(store.read().status).assertEqual('waiting');
      expect(store.read().qrUrl).assertEqual('https://example.invalid/qr');
      expect(scheduler.pendingCount()).assertEqual(1);

      const poll = scheduler.runNext();
      expect(gateway.polls.length).assertEqual(1);
      gateway.polls[0].resolve({ status: 'scanned' });
      await poll;

      expect(store.read().status).assertEqual('scanned');
      expect(scheduler.pendingCount()).assertEqual(1);
      expect(scheduler.scheduleCalls).assertEqual(2);
    });

    it('keepsTheQrSessionAliveAcrossRetryablePollFailures', 0, async () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const store = new AuthStore(gateway, scheduler, 10);
      await startWaiting(store, gateway, scheduler);

      const failedPoll = scheduler.runNext();
      gateway.polls[0].reject(new NativeError('auth.qrPollTimeout', 'timeout', true));
      await failedPoll;

      expect(store.read().status).assertEqual('waiting');
      expect(store.read().error === null).assertTrue();
      expect(gateway.cancelCalls).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(1);

      const retry = scheduler.runNext();
      gateway.polls[1].resolve({ status: 'scanned' });
      await retry;
      expect(store.read().status).assertEqual('scanned');
    });

    it('refreshesTheProfileAndNotifiesAfterSuccess', 0, async () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const listener = new RecordingAuthListener();
      const store = new AuthStore(gateway, scheduler, 10);
      store.setListener(listener);
      await startWaiting(store, gateway, scheduler);

      const poll = scheduler.runNext();
      gateway.polls[0].resolve({ status: 'success' });
      await wait(0);
      expect(gateway.profiles.length).assertEqual(1);
      gateway.profiles[0].resolve(loginProfile());
      await poll;

      expect(store.read().status).assertEqual('success');
      expect(store.read().profile.name).assertEqual('Listener');
      expect(store.read().qrUrl.length).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(0);
      expect(gateway.cancelCalls).assertEqual(1);
      expect(listener.profiles.length).assertEqual(1);
      expect(listener.profiles[0].mid).assertEqual(42);
    });

    it('derivesProfileStateFromCacheAndCredentials', 0, () => {
      const noCredentials = new FakeAuthGateway();
      const noCredentialsStore = new AuthStore(noCredentials, new FakeAuthTimerScheduler(), 10);
      expect(noCredentialsStore.profileState).assertEqual('loggedOut');
      noCredentialsStore.dispose();

      const credentials = new FakeAuthGateway();
      credentials.credentialsPresent = true;
      const credentialsStore = new AuthStore(credentials, new FakeAuthTimerScheduler(), 10);
      expect(credentialsStore.profileState).assertEqual('loading');
      credentialsStore.dispose();

      const cached = new FakeAuthGateway(loginProfile());
      const cachedStore = new AuthStore(cached, new FakeAuthTimerScheduler(), 10);
      expect(cachedStore.profileState).assertEqual('ready');
      cachedStore.dispose();
    });

    it('movesProfileStateToReadyAfterRefreshSuccess', 0, async () => {
      const gateway = new FakeAuthGateway();
      gateway.credentialsPresent = true;
      const store = new AuthStore(gateway, new FakeAuthTimerScheduler(), 10);
      const refresh = store.refreshProfile();
      gateway.profiles[0].resolve(loginProfile());
      await refresh;

      expect(store.profileState).assertEqual('ready');
      expect(store.read().profile.name).assertEqual('Listener');
      store.dispose();
    });

    it('movesProfileStateToErrorAfterRefreshFailureWithoutCache', 0, async () => {
      const gateway = new FakeAuthGateway();
      gateway.credentialsPresent = true;
      const store = new AuthStore(gateway, new FakeAuthTimerScheduler(), 10);
      const refresh = store.refreshProfile();
      gateway.profiles[0].reject(new NativeError('network.timeout', 'timeout', true));
      let code = '';
      try {
        await refresh;
      } catch (error) {
        code = error instanceof NativeError ? error.appError.code : '';
      }

      expect(code).assertEqual('network.timeout');
      expect(store.profileState).assertEqual('error');
      store.dispose();
    });

    it('notifiesAfterLogoutAndClearsTheActiveSession', 0, async () => {
      const gateway = new FakeAuthGateway(loginProfile());
      const scheduler = new FakeAuthTimerScheduler();
      const listener = new RecordingAuthListener();
      const store = new AuthStore(gateway, scheduler, 10);
      store.setListener(listener);

      const logout = store.logout();
      expect(gateway.logouts.length).assertEqual(1);
      expect(gateway.cancelCalls).assertEqual(1);
      gateway.logouts[0].resolve(emptyAuthProfile());
      await logout;

      expect(store.read().status).assertEqual('idle');
      expect(store.read().profile.isLogin).assertFalse();
      expect(store.profileState).assertEqual('loggedOut');
      expect(listener.profiles.length).assertEqual(1);
      expect(listener.profiles[0].isLogin).assertFalse();
      expect(scheduler.pendingCount()).assertEqual(0);
    });

    it('stopsPollingWhenTheQrCodeExpires', 0, async () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const store = new AuthStore(gateway, scheduler, 10);
      await startWaiting(store, gateway, scheduler);

      const poll = scheduler.runNext();
      gateway.polls[0].resolve({ status: 'expired' });
      await poll;

      expect(store.read().status).assertEqual('expired');
      expect(store.read().qrUrl.length).assertEqual(0);
      expect(gateway.cancelCalls).assertEqual(1);
      expect(gateway.polls.length).assertEqual(1);
      expect(scheduler.pendingCount()).assertEqual(0);
    });

    it('stopsTheQrPollWhenTheLoginSheetCloses', 0, async () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const store = new AuthStore(gateway, scheduler, 10);
      await startWaiting(store, gateway, scheduler);

      // 08 登录抽屉的 #D9 契约：关闭抽屉必须显式取消轮询（不能依赖 aboutToDisappear）
      expect(closeLoginSheetSession(store)).assertTrue();
      expect(store.read().status).assertEqual('cancelled');
      expect(store.read().qrUrl.length).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(0);
      expect(gateway.cancelCalls).assertEqual(1);

      // 幂等：已经不在活跃状态时不再重复取消
      expect(closeLoginSheetSession(store)).assertFalse();
      expect(gateway.cancelCalls).assertEqual(1);
    });

    it('ignoresAnInFlightPollAfterCancellation', 0, async () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const store = new AuthStore(gateway, scheduler, 10);
      await startWaiting(store, gateway, scheduler);

      const poll = scheduler.runNext();
      store.cancelQrLogin();
      expect(store.read().status).assertEqual('cancelled');
      expect(gateway.cancelCalls).assertEqual(1);

      gateway.polls[0].resolve({ status: 'scanned' });
      await poll;

      expect(store.read().status).assertEqual('cancelled');
      expect(store.read().qrUrl.length).assertEqual(0);
      expect(gateway.polls.length).assertEqual(1);
      expect(scheduler.pendingCount()).assertEqual(0);
    });

    it('sanitizesPollFailuresWithoutLeakingCredentials', 0, async () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const store = new AuthStore(gateway, scheduler, 10);
      await startWaiting(store, gateway, scheduler);

      const poll = scheduler.runNext();
      gateway.polls[0].reject(new NativeError(
        'auth.qrPollFailed',
        'qrcode_key=secret Cookie=SESSDATA%3Dsecret https://example.invalid/qr',
        false
      ));
      await poll;

      expect(store.read().status).assertEqual('error');
      expect(store.read().error?.code).assertEqual('auth.qrPollFailed');
      expect(store.read().error?.message).assertEqual('登录状态获取失败，请重试。');
      assertNoSensitiveValue(store.read());
      expect(scheduler.pendingCount()).assertEqual(0);
    });

    it('usesSafeCopyForUnknownPollErrors', 0, async () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const store = new AuthStore(gateway, scheduler, 10);
      await startWaiting(store, gateway, scheduler);

      const poll = scheduler.runNext();
      gateway.polls[0].reject(new Error('socket closed /private/cookie/qrcode_key'));
      await poll;

      expect(store.read().status).assertEqual('error');
      expect(store.read().error?.code).assertEqual('native.error');
      expect(store.read().error?.message).assertEqual(SAFE_UNKNOWN_ERROR_MESSAGE);
      assertNoSensitiveValue(store.read());
    });

    it('cancelsAScheduledPollWhenDisposed', 0, () => {
      const gateway = new FakeAuthGateway();
      const scheduler = new FakeAuthTimerScheduler();
      const store = new AuthStore(gateway, scheduler, 10);
      const start = store.startQrLogin();
      gateway.qrUrl = 'https://example.invalid/qr';
      gateway.starts[0].resolve({
        mode: 'native-overlay',
        expiresAt: Date.now() + 60_000
      });

      return start.then((): void => {
        expect(scheduler.pendingCount()).assertEqual(1);
        store.dispose();

        expect(store.read().status).assertEqual('cancelled');
        expect(store.read().qrUrl.length).assertEqual(0);
        expect(scheduler.pendingCount()).assertEqual(0);
        expect(scheduler.cancelledIds.length).assertEqual(1);
        expect(gateway.cancelCalls).assertEqual(1);
        expect(gateway.polls.length).assertEqual(0);
      });
    });
  });
}

function cloneProfile(profile: AuthProfile): AuthProfile {
  return {
    isLogin: profile.isLogin,
    mid: profile.mid,
    name: profile.name,
    avatarUrl: profile.avatarUrl,
    vip: profile.vip
  };
}
