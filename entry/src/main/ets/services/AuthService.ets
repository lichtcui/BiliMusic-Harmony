import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  apiCode,
  apiMessage,
  BiliHttpClient,
  HttpTextResponse,
  HttpUrlParser,
  HttpUrlParts,
  PlatformHttpUrlParser
} from './BiliHttpClient';
import { CookieJar } from './CookieJar';
import { AuthProfileStore } from './AuthProfileStore';
import {
  AuthProfile,
  QrLoginPoll,
  QrLoginStart,
  emptyAuthProfile
} from '../types/MobileTypes';
import { errorMessage, NativeError } from '../util/Errors';
import {
  numberValue,
  objectValue,
  stringValue
} from '../util/Json';

const DOMAIN = 0x424D;
const TAG = 'WispMusicAuth';
const PASSPORT_ORIGIN = 'https://passport.bilibili.com';
const QR_TTL_MS = 180_000;

export class AuthService {
  private readonly http: BiliHttpClient;
  private readonly cookies: CookieJar;
  private readonly profileStore: AuthProfileStore | null;
  private readonly urlParser: HttpUrlParser;
  private qrcodeKey: string = '';
  private qrUrl: string = '';
  private expiresAt: number = 0;
  private qrStartPromise: Promise<QrLoginStart> | null = null;
  private lastQrPollStage: string = '';
  private profile: AuthProfile = emptyAuthProfile();

  constructor(http: BiliHttpClient, cookies: CookieJar, profileStore: AuthProfileStore | null = null,
    urlParser: HttpUrlParser = new PlatformHttpUrlParser()) {
    this.http = http;
    this.cookies = cookies;
    this.profileStore = profileStore;
    this.urlParser = urlParser;
    if (profileStore !== null) {
      const cached = profileStore.read();
      this.profile = this.hasLoginCredentials() ? cached : emptyAuthProfile();
      if (cached.isLogin && !this.profile.isLogin) {
        void profileStore.clear();
      }
    }
  }

  /** 只用于页头判断「可能是已登录、资料还在加载」，不读取或输出 Cookie 内容。 */
  hasLoginCredentials(): boolean {
    return this.cookies.loginCredentialPresence().includes('SESSDATA=yes');
  }

  async startQrLogin(): Promise<QrLoginStart> {
    if (this.qrcodeKey.length > 0 && this.qrUrl.length > 0 && Date.now() < this.expiresAt) {
      hilog.info(DOMAIN, TAG, 'QR session reused ttlMs=%{public}d',
        this.expiresAt - Date.now());
      return {
        mode: 'native-overlay',
        expiresAt: this.expiresAt
      };
    }
    if (this.qrStartPromise !== null) {
      hilog.info(DOMAIN, TAG, 'QR session start joined');
      return this.qrStartPromise;
    }
    this.qrStartPromise = this.createQrLogin().finally((): void => {
      this.qrStartPromise = null;
    });
    return this.qrStartPromise;
  }

  private async createQrLogin(): Promise<QrLoginStart> {
    const response = await this.passportJson('/x/passport-login/web/qrcode/generate');
    if (apiCode(response) !== 0) {
      throw new NativeError('auth.qrGenerateFailed', apiMessage(response), true);
    }
    const data = objectValue(response.data);
    const key = stringValue(data.qrcode_key).trim();
    const qrUrl = stringValue(data.url).trim();
    if (key.length === 0 || qrUrl.length === 0) {
      throw new NativeError('auth.qrGenerateFailed', '登录二维码生成失败，请重试。', true);
    }
    this.qrcodeKey = key;
    this.qrUrl = qrUrl;
    this.expiresAt = Date.now() + QR_TTL_MS;
    this.lastQrPollStage = '';
    hilog.info(DOMAIN, TAG, 'QR session created ttlMs=%{public}d', QR_TTL_MS);
    return {
      mode: 'native-overlay',
      expiresAt: this.expiresAt
    };
  }

  async pollQrLogin(): Promise<QrLoginPoll> {
    if (this.qrcodeKey.length === 0 || Date.now() >= this.expiresAt) {
      this.clearQr();
      const expired: QrLoginPoll = {
        status: 'expired'
      };
      return expired;
    }
    const key = encodeURIComponent(this.qrcodeKey);
    const response = await this.passportJson(`/x/passport-login/web/qrcode/poll?qrcode_key=${key}`);
    const outerCode = apiCode(response);
    const data = objectValue(response.data);
    // 缺失/非有限 code 不能折算成 -1：这个接口里 -1 与 86038 一样表示「会话已过期」。
    if (outerCode === 0 &&
      (typeof data.code !== 'number' || !Number.isFinite(data.code as number))) {
      throw new NativeError('auth.qrPollFailed', '登录状态响应不完整，请重试。', true);
    }
    const innerCode = outerCode === 0 ? numberValue(data.code, -1) : outerCode;
    const stage = qrStage(innerCode);
    if (stage !== this.lastQrPollStage) {
      hilog.info(DOMAIN, TAG,
        'QR poll stage changed previous=%{public}s stage=%{public}s outer=%{public}d inner=%{public}d credentials=%{public}s',
        this.lastQrPollStage.length > 0 ? this.lastQrPollStage : 'none',
        stage, outerCode, innerCode, this.cookies.loginCredentialPresence());
      this.lastQrPollStage = stage;
    }

    if (innerCode === 86100 || innerCode === 86101) {
      return {
        status: 'waiting'
      };
    }
    if (innerCode === 86090) {
      return {
        status: 'scanned'
      };
    }
    if (innerCode === 86038 || innerCode === -1) {
      this.clearQr();
      return {
        status: 'expired'
      };
    }
    if (innerCode !== 0) {
      throw new NativeError('auth.qrPollFailed',
        stringValue(data.message, apiMessage(response)), true);
    }

    const profile = await this.completeLogin(data);
    this.clearQr();
    if (!profile.isLogin) {
      throw new NativeError('auth.loginIncomplete', '登录未完成，请重新扫码。', true);
    }
    this.profile = profile;
    hilog.info(DOMAIN, TAG, 'QR login completed');
    return {
      status: 'success',
      profile: profile
    };
  }

  async refreshProfile(): Promise<AuthProfile> {
    try {
      const response = await this.http.biliJson('/x/web-interface/nav');
      const code = apiCode(response);
      const data = objectValue(response.data);
      hilog.info(DOMAIN, TAG, 'nav profile code=%{public}d isLogin=%{public}s credentials=%{public}s',
        code, Boolean(data.isLogin) ? 'yes' : 'no', this.cookies.loginCredentialPresence());
      if (code !== 0) {
        this.profile = emptyAuthProfile();
        this.persistProfile();
        return this.profile;
      }
      if (!Boolean(data.isLogin)) {
        this.profile = emptyAuthProfile();
        this.persistProfile();
        return this.profile;
      }
      const vip = objectValue(data.vipStatus);
      this.profile = {
        isLogin: true,
        mid: Math.max(0, numberValue(data.mid)),
        name: stringValue(data.uname, 'Bilibili 用户').trim(),
        avatarUrl: toHttpsUrl(stringValue(data.face)),
        vip: numberValue(vip.status) === 1 || numberValue(data.vipType) > 0
      };
      this.persistProfile();
      return this.profile;
    } catch (error) {
      if (error instanceof NativeError && error.appError.code === 'auth.required') {
        hilog.warn(DOMAIN, TAG, 'nav profile requires login credentials=%{public}s',
          this.cookies.loginCredentialPresence());
        this.profile = emptyAuthProfile();
        this.persistProfile();
        return this.profile;
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new NativeError('auth.statusFailed', errorMessage(error), true);
    }
  }

  status(): AuthProfile {
    return cloneProfile(this.profile);
  }

  async logout(): Promise<AuthProfile> {
    this.clearQr();
    await this.cookies.clearBilibili();
    try {
      await this.cookies.persist();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'cookie persistence after logout failed');
    }
    this.profile = emptyAuthProfile();
    this.persistProfile();
    return this.status();
  }

  currentQrUrl(): string {
    return this.qrUrl;
  }

  currentExpiresAt(): number {
    return this.expiresAt;
  }

  cancelQrLogin(): void {
    this.clearQr();
  }

  private async passportJson(pathAndQuery: string): Promise<Record<string, Object>> {
    let response: HttpTextResponse;
    try {
      response = await this.http.requestText(`${PASSPORT_ORIGIN}${pathAndQuery}`, {
        timeoutMs: 15_000,
        maxBytes: 1024 * 1024,
        followRedirects: true,
        allowedHosts: ['bilibili.com'],
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Origin': 'https://passport.bilibili.com',
          'Referer': 'https://passport.bilibili.com/login'
        }
      });
    } catch (error) {
      if (error instanceof NativeError) {
        throw error;
      }
      throw new NativeError('auth.networkUnavailable', '登录服务暂时不可用。', true);
    }
    if (response.status < 200 || response.status >= 300) {
      throw new NativeError('auth.httpStatus', `登录服务返回 ${response.status}。`, true);
    }
    try {
      return JSON.parse(response.body) as Record<string, Object>;
    } catch (error) {
      throw new NativeError('auth.invalidResponse', '登录服务返回了无法识别的数据。', true);
    }
  }

  private async completeLogin(data: Record<string, Object>): Promise<AuthProfile> {
    const candidates = loginCookieCandidates(stringValue(data.url).trim(), this.urlParser);
    hilog.info(DOMAIN, TAG, 'QR login candidates=%{public}d credentials=%{public}s',
      candidates.length, this.cookies.loginCredentialPresence());
    for (const candidate of candidates) {
      const count = this.cookies.setDomainCookies('bilibili.com', candidate);
      if (count === 0) {
        continue;
      }
      await this.cookies.persist();
      const profile = await this.refreshProfile();
      if (profile.isLogin) {
        hilog.info(DOMAIN, TAG, 'login cookies stored count=%{public}d', count);
        return profile;
      }
      hilog.warn(DOMAIN, TAG, 'login cookies rejected count=%{public}d', count);
    }
    hilog.info(DOMAIN, TAG, 'QR login using captured cookies credentials=%{public}s',
      this.cookies.loginCredentialPresence());
    return this.refreshProfile();
  }

  private persistProfile(): void {
    const store = this.profileStore;
    if (store === null) {
      return;
    }
    void store.write(this.profile).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'auth profile cache write failed');
    });
  }

  private clearQr(): void {
    this.qrcodeKey = '';
    this.qrUrl = '';
    this.expiresAt = 0;
    this.lastQrPollStage = '';
  }
}

function cloneProfile(value: AuthProfile): AuthProfile {
  return {
    isLogin: value.isLogin,
    mid: value.mid,
    name: value.name,
    avatarUrl: value.avatarUrl,
    vip: value.vip
  };
}

const LOGIN_COOKIE_NAMES: string[] = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5'];

function loginCookieCandidates(loginUrl: string, parser: HttpUrlParser): Record<string, string>[] {
  if (loginUrl.length === 0) {
    return [];
  }
  let parsed: HttpUrlParts;
  try {
    parsed = parser.parse(loginUrl);
  } catch (error) {
    throw new NativeError('auth.redirectInvalid', '登录跳转地址无效。', true);
  }
  const host = parsed.hostname.toLowerCase();
  const allowedHost = host === 'bilibili.com' || host.endsWith('.bilibili.com') ||
    host === 'biligame.com' || host.endsWith('.biligame.com');
  if (parsed.protocol !== 'https:' || !allowedHost) {
    throw new NativeError('auth.redirectBlocked', '登录跳转到了不受信任的地址。', false);
  }
  const raw = queryCookieValues(parsed.search, false);
  if (Object.keys(raw).length === 0) {
    return [];
  }
  const decoded = queryCookieValues(parsed.search, true);
  return sameValues(raw, decoded) ? [raw] : [raw, decoded];
}

function queryCookieValues(search: string, decode: boolean): Record<string, string> {
  const values: Record<string, string> = {};
  const query = search.startsWith('?') ? search.slice(1) : search;
  for (const pair of query.split('&')) {
    const index = pair.indexOf('=');
    if (index <= 0) {
      continue;
    }
    const name = pair.slice(0, index);
    if (LOGIN_COOKIE_NAMES.indexOf(name) < 0) {
      continue;
    }
    const value = pair.slice(index + 1);
    if (value.length === 0) {
      continue;
    }
    values[name] = decode ? decodeValue(value) : value;
  }
  return values;
}

function decodeValue(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    return value;
  }
}

function sameValues(left: Record<string, string>, right: Record<string, string>): boolean {
  const keys = Object.keys(left);
  if (keys.length !== Object.keys(right).length) {
    return false;
  }
  return keys.every((key: string): boolean => left[key] === right[key]);
}

function qrStage(code: number): string {
  if (code === 0) {
    return 'success';
  }
  if (code === 86090) {
    return 'scanned';
  }
  if (code === 86038 || code === -1) {
    return 'expired';
  }
  if (code === 86100 || code === 86101) {
    return 'waiting';
  }
  return 'failure';
}

function toHttpsUrl(value: string): string {
  const clean = value.trim();
  if (clean.startsWith('//')) {
    return `https:${clean}`;
  }
  if (clean.startsWith('http://')) {
    return `https://${clean.slice(7)}`;
  }
  return clean;
}
