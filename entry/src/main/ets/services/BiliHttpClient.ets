import { http } from '@kit.NetworkKit';
import { url } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CookieJar } from './CookieJar';
import { biliMediaHost } from './BiliUrl';
import { NativeError, toAppError, wait } from '../util/Errors';
import { objectValue, stringValue } from '../util/Json';
import { WbiParams, parseWbiKeys, wbiQuery } from './Wbi';

const DOMAIN = 0x424D;
const TAG = 'WispMusicHttp';
const API_ORIGIN = 'https://api.bilibili.com';
const PASSPORT_ORIGIN = 'https://passport.bilibili.com';
const MAX_REDIRECTS = 6;
const MAX_CONCURRENT_REQUESTS = 16;
/** 排队等待空闲槽位的上限；避免槽位耗尽后请求永久悬挂。 */
const ACQUIRE_TIMEOUT_MS = 30_000;
const WBI_KEY_TTL = 6 * 60 * 60 * 1000;
const USER_AGENT =
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36 wisp-music/1.1.0';
// https://*.bilivideo.com 会拒绝移动端（Android/HarmonyOS）UA 的 DASH 音频请求并返回 403，
// 桌面 UA 才能拿到 206；接口请求仍使用 USER_AGENT。
const MEDIA_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

export interface HttpRequestConfig {
  timeoutMs: number;
  maxBytes: number;
  followRedirects: boolean;
  allowedHosts: string[];
  headers?: Record<string, string>;
  usingCache?: boolean;
}

export interface HttpTextResponse {
  status: number;
  finalUrl: string;
  body: string;
  headers: Record<string, Object>;
}

export interface BiliImage {
  mime: string;
  data: ArrayBuffer;
}

export interface MediaDownload {
  path: string;
  bytes: number;
  mimeType: string;
}

/** 单次传输请求参数；平台实现把它翻译成 `http.request` 选项。 */
export interface HttpClientTransportOptions {
  headers: Record<string, string>;
  timeoutMs: number;
  maxBytes: number;
  usingCache: boolean;
  expectString: boolean;
}

/** 单次传输结果；测试注入的 fake 只实现这一层，不依赖 NetworkKit。 */
export interface HttpClientTransportResponse {
  status: number;
  result: string | ArrayBuffer;
  headers: Record<string, Object>;
  cookies: string;
}

export interface HttpClientTransportRequest {
  request(targetUrl: string, options: HttpClientTransportOptions): Promise<HttpClientTransportResponse>;
  destroy(): void;
}

export interface HttpClientTransport {
  create(): HttpClientTransportRequest;
}

/** 只在测试里覆盖：压缩并发槽位、排队超时和 412 退避等待。 */
export interface HttpClientOptions {
  maxConcurrent?: number;
  acquireTimeoutMs?: number;
  retryDelayMs?: (milliseconds: number) => Promise<void>;
  urlParser?: HttpUrlParser;
}

export interface HttpUrlParts {
  protocol: string;
  hostname: string;
  pathname: string;
  search: string;
}

export interface HttpUrlParser {
  parse(rawUrl: string): HttpUrlParts;
}

export class PlatformHttpUrlParser implements HttpUrlParser {
  parse(rawUrl: string): HttpUrlParts {
    const parsed = url.URL.parseURL(rawUrl);
    return {
      protocol: parsed.protocol,
      hostname: parsed.hostname,
      pathname: parsed.pathname,
      search: parsed.search
    };
  }
}

class PlatformHttpTransportRequest implements HttpClientTransportRequest {
  private readonly client: http.HttpRequest;

  constructor() {
    this.client = http.createHttp();
  }

  async request(targetUrl: string,
    options: HttpClientTransportOptions): Promise<HttpClientTransportResponse> {
    const response = await this.client.request(targetUrl, {
      method: http.RequestMethod.GET,
      header: options.headers,
      connectTimeout: Math.min(options.timeoutMs, 10_000),
      readTimeout: options.timeoutMs,
      usingCache: options.usingCache,
      maxLimit: options.maxBytes,
      maxRedirects: 0,
      expectDataType: options.expectString ?
        http.HttpDataType.STRING : http.HttpDataType.ARRAY_BUFFER
    });
    return {
      status: Number(response.responseCode),
      result: options.expectString ?
        stringValue(response.result as Object, '') : response.result as ArrayBuffer,
      headers: response.header as Record<string, Object>,
      cookies: response.cookies
    };
  }

  destroy(): void {
    this.client.destroy();
  }
}

class PlatformHttpTransport implements HttpClientTransport {
  create(): HttpClientTransportRequest {
    return new PlatformHttpTransportRequest();
  }
}

export class HttpStatusError extends NativeError {
  readonly status: number;

  constructor(code: string, message: string, status: number, retryable: boolean) {
    super(code, message, retryable);
    this.status = status;
  }
}

interface HttpBinaryResponse {
  status: number;
  finalUrl: string;
  data: ArrayBuffer;
  headers: Record<string, Object>;
}

interface WbiKeys {
  imgKey: string;
  subKey: string;
  loadedAt: number;
}

export class BiliHttpClient {
  private readonly cookies: CookieJar;
  private readonly transport: HttpClientTransport;
  private readonly maxConcurrent: number;
  private readonly acquireTimeoutMs: number;
  private readonly retryDelay: (milliseconds: number) => Promise<void>;
  private readonly urlParser: HttpUrlParser;
  private wbiKeys: WbiKeys | null = null;
  private wbiLoading: Promise<WbiKeys> | null = null;
  private wbiLoadingForce: boolean = false;
  private wbiGeneration: number = 0;
  private availableSlots: number;
  private waiters: Array<() => void> = [];

  constructor(cookies: CookieJar, transport?: HttpClientTransport, options?: HttpClientOptions) {
    this.cookies = cookies;
    this.transport = transport ?? new PlatformHttpTransport();
    this.maxConcurrent = Math.max(1,
      Math.floor(options !== undefined && options.maxConcurrent !== undefined ?
        options.maxConcurrent : MAX_CONCURRENT_REQUESTS));
    this.acquireTimeoutMs = Math.max(1,
      Math.floor(options !== undefined && options.acquireTimeoutMs !== undefined ?
        options.acquireTimeoutMs : ACQUIRE_TIMEOUT_MS));
    this.retryDelay = options !== undefined && options.retryDelayMs !== undefined ?
      options.retryDelayMs : wait;
    this.urlParser = options !== undefined && options.urlParser !== undefined ?
      options.urlParser : new PlatformHttpUrlParser();
    this.availableSlots = this.maxConcurrent;
  }

  async requestText(targetUrl: string, config: HttpRequestConfig): Promise<HttpTextResponse> {
    this.assertAllowedUrl(targetUrl, config.allowedHosts);
    // Redirects are handled below so cookies from every hop remain visible.
    return this.requestOnce(targetUrl, config);
  }

  async requestJson(targetUrl: string, config: HttpRequestConfig): Promise<Record<string, Object>> {
    const response = await this.requestText(targetUrl, config);
    if (response.status < 200 || response.status >= 300) {
      hilog.warn(DOMAIN, TAG, 'Bilibili request rejected status=%{public}d path=%{public}s',
        response.status, requestPath(targetUrl));
      throw new HttpStatusError('http.status', `网络请求失败（${response.status}）。`,
        response.status, response.status >= 500);
    }
    try {
      return JSON.parse(response.body) as Record<string, Object>;
    } catch (error) {
      throw new NativeError('http.invalidJson', '服务器返回了无法识别的数据。', true);
    }
  }

  async biliJson(pathAndQuery: string): Promise<Record<string, Object>> {
    return this.withRiskRetry(`${API_ORIGIN}${pathAndQuery}`, false);
  }

  async wbiJson(path: string, params: WbiParams): Promise<Record<string, Object>> {
    let keys = await this.getWbiKeys(false);
    let response = await this.withRiskRetry(this.signedUrl(path, params, keys), false);
    // -352 表示签名过期：强制刷新一次密钥后最多再重签一次，避免无限循环。
    for (let attempt = 1; attempt < 2 && apiCode(response) === -352; attempt += 1) {
      await this.retryDelay(400 * attempt);
      keys = await this.getWbiKeys(true);
      response = await this.withRiskRetry(this.signedUrl(path, params, keys), false);
    }
    return response;
  }

  async passportText(pathAndQuery: string, timeoutMs: number): Promise<HttpTextResponse> {
    return this.requestText(`${PASSPORT_ORIGIN}${pathAndQuery}`, {
      timeoutMs: timeoutMs,
      maxBytes: 1024 * 1024,
      followRedirects: false,
      allowedHosts: ['bilibili.com'],
      headers: biliHeaders()
    });
  }

  mediaHeaders(targetUrl: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': '*/*',
      'Origin': 'https://www.bilibili.com',
      'Referer': 'https://www.bilibili.com/',
      'User-Agent': MEDIA_USER_AGENT
    };
    const cookie = this.cookies.headerFor(targetUrl);
    if (cookie.length > 0) {
      headers['Cookie'] = cookie;
    }
    hilog.info(DOMAIN, TAG, 'media headers host=%{public}s cookie present=%{public}s',
      requestHost(targetUrl), cookie.length > 0 ? 'yes' : 'no');
    return headers;
  }

  async requestImage(targetUrl: string): Promise<BiliImage> {
    const config: HttpRequestConfig = {
      timeoutMs: 10_000,
      maxBytes: 8 * 1024 * 1024,
      followRedirects: false,
      allowedHosts: ['hdslb.com', 'biliimg.com'],
      headers: {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Origin': 'https://www.bilibili.com',
        'Referer': 'https://www.bilibili.com/',
        'User-Agent': USER_AGENT
      }
    };
    let currentUrl = targetUrl;
    let redirects = 0;
    let response = await this.requestBinaryOnce(currentUrl, config);
    while (isRedirect(response.status)) {
      const location = headerValue(response.headers, 'location');
      if (location.length === 0) {
        break;
      }
      if (redirects >= 2) {
        throw new NativeError('http.redirectLimit', '图片重定向次数过多。', true);
      }
      currentUrl = url.URL.parseURL(location, currentUrl).toString();
      this.assertAllowedUrl(currentUrl, config.allowedHosts);
      redirects += 1;
      response = await this.requestBinaryOnce(currentUrl, config);
    }
    if (response.status < 200 || response.status >= 300) {
      throw new HttpStatusError('http.status', `图片请求失败（${response.status}）。`,
        response.status, response.status >= 500);
    }
    const mime = headerValue(response.headers, 'content-type').split(';')[0].trim().toLowerCase();
    if (!mime.startsWith('image/')) {
      throw new NativeError('http.notImage', '图片地址返回了非图片内容。', false);
    }
    return {
      mime: mime,
      data: response.data
    };
  }

  async downloadMedia(targetUrl: string, destination: string, maxBytes: number): Promise<MediaDownload> {
    const mediaHost = biliMediaHost(targetUrl);
    if (mediaHost.length === 0) {
      throw new NativeError('player.invalidMediaUrl', '音频地址无效。');
    }
    const response = await this.requestBinaryOnce(targetUrl, {
      timeoutMs: 60_000,
      maxBytes: maxBytes,
      followRedirects: false,
      allowedHosts: [mediaHost],
      usingCache: false,
      headers: this.mediaHeaders(targetUrl)
    });
    if ((response.status < 200 || response.status >= 300) || response.data.byteLength === 0) {
      hilog.warn(DOMAIN, TAG, 'media request rejected host=%{public}s status=%{public}d',
        requestHost(targetUrl), response.status);
      throw new HttpStatusError('player.mediaDownloadFailed', `音频下载失败（${response.status}）。`,
        response.status, true);
    }
    try {
      const bytes = await writeFileAtomically(destination, response.data);
      return {
        path: destination,
        bytes: bytes,
        mimeType: headerValue(response.headers, 'content-type').split(';')[0].trim().toLowerCase()
      };
    } catch (error) {
      if (error instanceof NativeError) {
        throw error;
      }
      const businessError = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'media cache write failed code=%{public}d', businessError.code);
      throw new NativeError('player.mediaCacheFailed', '无法保存音频缓存。', true);
    }
  }

  private async withRiskRetry(targetUrl: string, retryAfterWbiRefresh: boolean): Promise<Record<string, Object>> {
    let last: Record<string, Object> = {};
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        last = await this.requestJson(targetUrl, {
          timeoutMs: 20_000,
          maxBytes: 4 * 1024 * 1024,
          followRedirects: true,
          allowedHosts: ['bilibili.com'],
          headers: biliHeaders()
        });
        const code = apiCode(last);
        if (!Number.isFinite(code)) {
          throw new NativeError('http.invalidJson', '服务器返回了无法识别的数据。', true);
        }
        if (code === -412 && attempt < 2) {
          hilog.warn(DOMAIN, TAG, 'Bilibili rate limited path=%{public}s attempt=%{public}d',
            requestPath(targetUrl), attempt + 1);
          await this.retryDelay(900 * (attempt + 1));
          continue;
        }
        if (code === -352 && retryAfterWbiRefresh) {
          continue;
        }
        if (code === -101) {
          throw new NativeError('auth.required', '登录状态已失效，请重新扫码登录。');
        }
        return last;
      } catch (error) {
        const appError = toAppError(error as Object);
        if (!appError.retryable || attempt >= 2) {
          throw new NativeError(appError.code, appError.message, appError.retryable);
        }
        hilog.warn(DOMAIN, TAG,
          'Bilibili request failed code=%{public}s path=%{public}s attempt=%{public}d; retrying',
          appError.code, requestPath(targetUrl), attempt + 1);
        await this.retryDelay(400 * (attempt + 1));
      }
    }
    return last;
  }

  private async requestOnce(targetUrl: string, config: HttpRequestConfig): Promise<HttpTextResponse> {
    if (!await this.acquire()) {
      throw new NativeError('http.busy', '请求排队超时，请稍后重试。', true);
    }
    let currentUrl = targetUrl;
    let redirects = 0;
    let request: HttpClientTransportRequest | null = null;
    try {
      request = this.transport.create();
      while (true) {
        this.assertAllowedUrl(currentUrl, config.allowedHosts);
        const headers: Record<string, string> = biliHeaders();
        if (config.headers !== undefined) {
          const extras = config.headers;
          for (const key of Object.keys(extras)) {
            headers[key] = extras[key];
          }
        }
        const cookie = this.cookies.headerFor(currentUrl);
        if (cookie.length > 0) {
          headers['Cookie'] = cookie;
        }
        const response = await request.request(currentUrl, {
          headers: headers,
          timeoutMs: config.timeoutMs,
          maxBytes: config.maxBytes,
          usingCache: false,
          expectString: true
        });
        const responseHeaders = response.headers;
        const cookieChanged = await this.cookies.setCookieHeaders(responseHeaders, currentUrl, response.cookies);
        if (cookieChanged) {
          hilog.info(DOMAIN, TAG, 'response cookies updated host=%{public}s path=%{public}s credentials=%{public}s',
            requestHost(currentUrl), requestPath(currentUrl), this.cookies.loginCredentialPresence());
        }
        const body = stringValue(response.result as Object, '');
        const status = response.status;
        if (config.followRedirects && isRedirect(status)) {
          const location = headerValue(responseHeaders, 'location');
          if (location.length === 0) {
            return {
              status: status,
              finalUrl: currentUrl,
              body: body,
              headers: responseHeaders
            };
          }
          if (redirects >= MAX_REDIRECTS) {
            throw new NativeError('http.redirectLimit', '网络重定向次数过多。', true);
          }
          currentUrl = url.URL.parseURL(location, currentUrl).toString();
          this.assertAllowedUrl(currentUrl, config.allowedHosts);
          redirects += 1;
          hilog.info(DOMAIN, TAG,
            'redirect hop=%{public}d status=%{public}d host=%{public}s path=%{public}s',
            redirects, status, requestHost(currentUrl), requestPath(currentUrl));
          continue;
        }
        return {
          status: status,
          finalUrl: currentUrl,
          body: body,
          headers: responseHeaders
        };
      }
    } catch (error) {
      if (error instanceof NativeError) {
        throw error;
      }
      const businessError = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'network request failed code=%{public}d path=%{public}s',
        businessError.code, requestPath(currentUrl));
      if (businessError.code === 2300047) {
        throw new NativeError('http.redirectLimit', '网络重定向次数过多。', true);
      }
      throw new NativeError('http.unavailable', '网络连接失败，请稍后重试。', true);
    } finally {
      if (request !== null) {
        request.destroy();
      }
      this.release();
    }
  }

  private async requestBinaryOnce(targetUrl: string, config: HttpRequestConfig): Promise<HttpBinaryResponse> {
    this.assertAllowedUrl(targetUrl, config.allowedHosts);
    if (!await this.acquire()) {
      throw new NativeError('http.busy', '请求排队超时，请稍后重试。', true);
    }
    let request: HttpClientTransportRequest | null = null;
    try {
      request = this.transport.create();
      const headers: Record<string, string> = {
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6'
      };
      if (config.headers !== undefined) {
        const extras = config.headers;
        for (const key of Object.keys(extras)) {
          headers[key] = extras[key];
        }
      }
      const cookie = this.cookies.headerFor(targetUrl);
      if (cookie.length > 0) {
        headers['Cookie'] = cookie;
      }
      const response = await request.request(targetUrl, {
        headers: headers,
        timeoutMs: config.timeoutMs,
        maxBytes: config.maxBytes,
        usingCache: config.usingCache ?? true,
        expectString: false
      });
      const status = response.status;
      const result = response.result;
      const data = result instanceof ArrayBuffer ? result : new ArrayBuffer(0);
      const responseHeaders = response.headers;
      const cookieChanged = await this.cookies.setCookieHeaders(responseHeaders, targetUrl, response.cookies);
      if (cookieChanged) {
        hilog.info(DOMAIN, TAG, 'binary response cookies updated host=%{public}s path=%{public}s credentials=%{public}s',
          requestHost(targetUrl), requestPath(targetUrl), this.cookies.loginCredentialPresence());
      }
      if (data.byteLength > config.maxBytes) {
        throw new NativeError('http.responseTooLarge', '响应数据超过大小限制。', false);
      }
      return {
        status: status,
        finalUrl: targetUrl,
        data: data,
        headers: responseHeaders
      };
    } catch (error) {
      if (error instanceof NativeError) {
        throw error;
      }
      const businessError = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'binary request failed code=%{public}d path=%{public}s',
        businessError.code, requestPath(targetUrl));
      if (businessError.code === 2300047) {
        throw new NativeError('http.redirectLimit', '网络重定向次数过多。', true);
      }
      throw new NativeError('http.unavailable', '网络请求失败，请稍后重试。', true);
    } finally {
      if (request !== null) {
        request.destroy();
      }
      this.release();
    }
  }

  private async getWbiKeys(force: boolean): Promise<WbiKeys> {
    const cached = this.wbiKeys;
    if (!force && cached !== null && Date.now() - cached.loadedAt < WBI_KEY_TTL) {
      return cached;
    }
    if (!force && this.wbiLoading !== null) {
      return this.wbiLoading;
    }
    // 强制刷新只能合并同样由强制触发的请求：复用 TTL 到期前的普通请求可能拿回旧密钥。
    if (this.wbiLoading !== null && this.wbiLoadingForce) {
      return this.wbiLoading;
    }
    const generation = this.wbiGeneration + 1;
    this.wbiGeneration = generation;
    this.wbiLoadingForce = force;
    const started = this.loadWbiKeys(generation);
    this.wbiLoading = started.finally((): void => {
      if (this.wbiGeneration === generation) {
        this.wbiLoading = null;
        this.wbiLoadingForce = false;
      }
    });
    return this.wbiLoading;
  }

  private async loadWbiKeys(generation: number): Promise<WbiKeys> {
    const response = await this.requestJson(`${API_ORIGIN}/x/web-interface/nav`, {
      timeoutMs: 20_000,
      maxBytes: 1024 * 1024,
      followRedirects: true,
      allowedHosts: ['bilibili.com'],
      headers: biliHeaders()
    });
    const data = objectValue(response.data);
    const wbi = objectValue(data.wbi_img);
    const keys = parseWbiKeys(stringValue(wbi.img_url), stringValue(wbi.sub_url));
    if (keys.length !== 2) {
      throw new NativeError('wbi.keysUnavailable', '暂时无法准备搜索签名。', true);
    }
    const next: WbiKeys = {
      imgKey: keys[0],
      subKey: keys[1],
      loadedAt: Date.now()
    };
    // 迟到的旧代次响应不能覆盖已经刷新的密钥。
    if (generation === this.wbiGeneration) {
      this.wbiKeys = next;
    }
    return next;
  }

  private signedUrl(path: string, params: WbiParams, keys: WbiKeys): string {
    const timestamp = Math.floor(Date.now() / 1000);
    return `${API_ORIGIN}${path}?${wbiQuery(params, timestamp, keys.imgKey, keys.subKey)}`;
  }

  private assertAllowedUrl(targetUrl: string, allowedHosts: string[]): void {
    let parsed: HttpUrlParts;
    try {
      parsed = this.urlParser.parse(targetUrl);
    } catch (error) {
      throw new NativeError('http.invalidUrl', '网络地址无效。');
    }
    const host = parsed.hostname.toLowerCase();
    // 平台 URL 解析会丢弃 port / userinfo，必须用原始 authority 再核对一次。
    let allowed = parsed.protocol === 'https:' && host.length > 0 &&
      safeAuthorityHost(targetUrl) === host;
    if (allowed) {
      allowed = allowedHosts.some((domain: string): boolean => {
        const clean = domain.toLowerCase();
        return host === clean || host.endsWith(`.${clean}`);
      });
    }
    if (!allowed) {
      throw new NativeError('http.blockedUrl', '已阻止不受信任的网络地址。');
    }
  }

  private acquire(): Promise<boolean> {
    if (this.availableSlots > 0) {
      this.availableSlots -= 1;
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve: (acquired: boolean) => void) => {
      let settled = false;
      let timer: number = 0;
      const waiter = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve(true);
      };
      timer = setTimeout((): void => {
        if (settled) {
          return;
        }
        settled = true;
        const index = this.waiters.indexOf(waiter);
        if (index >= 0) {
          this.waiters.splice(index, 1);
        }
        resolve(false);
      }, this.acquireTimeoutMs);
      this.waiters.push(waiter);
    });
  }

  private release(): void {
    const next = this.waiters.shift();
    if (next !== undefined) {
      next();
      return;
    }
    this.availableSlots = Math.min(this.maxConcurrent, this.availableSlots + 1);
  }
}

/**
 * 从原始 URL 提取 authority 并核对端口/userinfo。
 * 平台 URL 解析会规范化掉这些信息，只有原串能区分 `:8443` 与 `@`。
 */
function safeAuthorityHost(targetUrl: string): string {
  if (targetUrl.length === 0 || targetUrl !== targetUrl.trim()) {
    return '';
  }
  const match = targetUrl.match(/^https:\/\/([^/?#]*)(?:[/?#]|$)/iu);
  if (match === null) {
    return '';
  }
  const authority = match[1];
  if (authority.length === 0 || authority.indexOf('@') >= 0 ||
    authority.indexOf('\\') >= 0 || authority.startsWith('[')) {
    return '';
  }
  const firstColon = authority.indexOf(':');
  const lastColon = authority.lastIndexOf(':');
  let rawHost = authority;
  if (firstColon >= 0) {
    if (firstColon !== lastColon || authority.slice(lastColon + 1) !== '443') {
      return '';
    }
    rawHost = authority.slice(0, firstColon);
  }
  const host = rawHost.toLowerCase();
  if (host.length === 0 || !/^[a-z0-9.-]+$/u.test(host) ||
    host.startsWith('.') || host.endsWith('.') || host.indexOf('..') >= 0) {
    return '';
  }
  return host;
}

function requestPath(targetUrl: string): string {
  try {
    return url.URL.parseURL(targetUrl).pathname;
  } catch (error) {
    return '';
  }
}

function requestHost(targetUrl: string): string {
  try {
    return url.URL.parseURL(targetUrl).hostname.toLowerCase();
  } catch (error) {
    return '';
  }
}

export function apiCode(response: Record<string, Object>): number {
  const raw = response.code;
  if (raw === undefined || raw === null) {
    // 缺失 code 不是成功：风控页/网关错误页也可能返回 200 + JSON，必须让调用方显式失败。
    return Number.NaN;
  }
  const value = Number(raw);
  return Number.isFinite(value) ? value : Number.NaN;
}

export function apiMessage(response: Record<string, Object>): string {
  const value = response.message;
  return typeof value === 'string' && value.length > 0 ? value : 'Bilibili 接口请求失败。';
}

function biliHeaders(): Record<string, string> {
  return {
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6',
    'Origin': 'https://www.bilibili.com',
    'Referer': 'https://www.bilibili.com/',
    'User-Agent': USER_AGENT
  };
}

function isRedirect(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

function headerValue(headers: Record<string, Object>, name: string): string {
  const direct = headers[name];
  if (typeof direct === 'string') {
    return direct;
  }
  const lower = name.toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === lower) {
      const value = headers[key];
      if (typeof value === 'string') {
        return value;
      }
      if (Array.isArray(value) && value.length > 0) {
        return stringValue(value[0], '');
      }
    }
  }
  return '';
}

export function httpStatusFromError(error: Object): number {
  return error instanceof HttpStatusError ? error.status : 0;
}

async function writeFileAtomically(path: string, data: ArrayBuffer): Promise<number> {
  const temporary = `${path}.part`;
  let file: fs.File | null = null;
  let writtenBytes = 0;
  try {
    if (fs.accessSync(temporary)) {
      fs.unlinkSync(temporary);
    }
    file = await fs.open(temporary, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    while (writtenBytes < data.byteLength) {
      const chunk = writtenBytes === 0 ? data : data.slice(writtenBytes);
      const written = await fs.write(file.fd, chunk);
      if (written <= 0) {
        throw new NativeError('player.mediaCacheFailed', '音频缓存写入不完整。', true);
      }
      writtenBytes += written;
    }
    await fs.fsync(file.fd);
  } finally {
    if (file !== null) {
      fs.closeSync(file);
    }
  }
  if (fs.accessSync(path)) {
    fs.unlinkSync(path);
  }
  fs.renameSync(temporary, path);
  return writtenBytes;
}
