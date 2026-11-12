import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { url } from '@kit.ArkTS';
import { readAtomicText, preserveCorruptFile, writeAtomicText } from '../util/AtomicJson';

const DOMAIN = 0x424D;
const TAG = 'WispMusicCookieJar';
const COOKIE_VERSION = 1;
const LOGIN_COOKIE_NAMES: string[] = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5'];

interface StoredCookie {
  name: string;
  value: string;
  domain: string;
  path: string;
  secure: boolean;
  httpOnly: boolean;
  hostOnly: boolean;
  expiresAt: number;
  createdAt: number;
}

interface StoredCookieFile {
  version: number;
  cookies: StoredCookie[];
}

interface ParsedSetCookie {
  cookie: StoredCookie | null;
  clearHost: boolean;
}

export interface CookiePersistence {
  read(path: string): string | null;
  write(path: string, content: string): Promise<void>;
  preserveCorrupt(path: string): void;
}

export interface ParsedUrl {
  hostname: string;
  pathname: string;
  protocol: string;
}

export interface CookieUrlParser {
  parse(rawUrl: string): ParsedUrl;
}

class PlatformCookieUrlParser implements CookieUrlParser {
  parse(rawUrl: string): ParsedUrl {
    const parsed = url.URL.parseURL(rawUrl);
    return {
      hostname: parsed.hostname,
      pathname: parsed.pathname,
      protocol: parsed.protocol
    };
  }
}

class AtomicCookiePersistence implements CookiePersistence {
  read(path: string): string | null {
    return readAtomicText(path);
  }

  write(path: string, content: string): Promise<void> {
    return writeAtomicText(path, content);
  }

  preserveCorrupt(path: string): void {
    preserveCorruptFile(path);
  }
}

export class CookieJar {
  private readonly path: string;
  private readonly persistence: CookiePersistence;
  private readonly urlParser: CookieUrlParser;
  private cookies: StoredCookie[] = [];
  private writeChain: Promise<void> = Promise.resolve();

  constructor(path: string, persistence: CookiePersistence = new AtomicCookiePersistence(),
    urlParser: CookieUrlParser = new PlatformCookieUrlParser()) {
    this.path = path;
    this.persistence = persistence;
    this.urlParser = urlParser;
    this.load();
  }

  headerFor(rawUrl: string): string {
    this.purgeExpired();
    const parsed = this.urlParser.parse(rawUrl);
    const host = parsed.hostname.toLowerCase();
    const path = parsed.pathname || '/';
    const secure = parsed.protocol === 'https:';
    const values: string[] = [];
    for (const cookie of this.cookies) {
      if (cookie.secure && !secure) {
        continue;
      }
      if (!matchesDomain(host, cookie) || !pathMatches(path, cookie.path)) {
        continue;
      }
      values.push(`${cookie.name}=${cookie.value}`);
    }
    return values.join('; ');
  }

  loginCredentialPresence(): string {
    this.purgeExpired();
    return LOGIN_COOKIE_NAMES.map((name: string): string => {
      const present = this.cookies.some((cookie: StoredCookie): boolean => cookie.name === name);
      return `${name}=${present ? 'yes' : 'no'}`;
    }).join(',');
  }

  async setCookieHeaders(headers: Record<string, Object>, responseUrl: string,
    fallbackCookies: string = ''): Promise<boolean> {
    let changed = false;
    const rawValues: string[] = setCookieValues(headers);
    if (rawValues.length === 0 && fallbackCookies.length > 0) {
      rawValues.push(...fallbackCookieValues(fallbackCookies));
    }
    for (const raw of rawValues) {
      const parsed = parseSetCookie(raw, responseUrl, this.urlParser);
      if (parsed.clearHost) {
        this.clearHost(this.urlParser.parse(responseUrl).hostname);
        changed = true;
      }
      const cookie = parsed.cookie;
      if (cookie === null) {
        continue;
      }
      this.removeMatching(cookie);
      if (cookie.expiresAt < 0 || cookie.expiresAt > Date.now()) {
        this.cookies.push(cookie);
      }
      changed = true;
    }
    if (changed) {
      await this.persist();
    }
    return changed;
  }

  setDomainCookies(domain: string, values: Record<string, string>): number {
    const cleanDomain = domain.toLowerCase().replace(/^\./u, '');
    if (cleanDomain.length === 0) {
      return 0;
    }
    let stored = 0;
    for (const name of Object.keys(values)) {
      const value = values[name];
      if (name.length === 0 || name.length > 256 || value.length === 0 || value.length > 8192) {
        continue;
      }
      const next: StoredCookie = {
        name: name,
        value: value,
        domain: cleanDomain,
        path: '/',
        secure: true,
        httpOnly: true,
        hostOnly: false,
        expiresAt: -1,
        createdAt: Date.now()
      };
      this.removeMatching(next);
      this.cookies.push(next);
      stored += 1;
    }
    return stored;
  }

  async clearBilibili(): Promise<void> {
    this.cookies = this.cookies.filter((cookie: StoredCookie): boolean => {
      const domain = cookie.domain.toLowerCase();
      return !matchesAnyDomain(domain, ['bilibili.com', 'biligame.com']);
    });
    await this.persist();
  }

  async clearAll(): Promise<void> {
    this.cookies = [];
    await this.persist();
  }

  persist(): Promise<void> {
    const snapshot: StoredCookieFile = {
      version: COOKIE_VERSION,
      cookies: this.cookies
    };
    const content = JSON.stringify(snapshot);
    // Cookie 落盘是网络请求的附属效果：写盘失败只记录，不能把已经成功的请求
    // 误报成 `http.unavailable` 并触发上层重试。内存中的 Cookie 仍然有效。
    const next = this.writeChain
      .catch((): void => {})
      .then((): Promise<void> => this.persistence.write(this.path, content))
      .catch((error: Object): void => {
        const businessError = error as BusinessError;
        hilog.error(DOMAIN, TAG, 'failed to persist cookies code=%{public}d', businessError.code);
      });
    this.writeChain = next;
    return next;
  }

  private load(): void {
    const content = this.persistence.read(this.path);
    if (content === null) {
      return;
    }
    try {
      const parsed = JSON.parse(content) as StoredCookieFile;
      if (parsed.version !== COOKIE_VERSION || !Array.isArray(parsed.cookies)) {
        throw new Error('Unsupported cookie store version.');
      }
      this.cookies = parsed.cookies.filter((cookie: StoredCookie): boolean => {
        return typeof cookie.name === 'string' && typeof cookie.value === 'string' &&
          typeof cookie.domain === 'string' && cookie.domain.length > 0 &&
          typeof cookie.path === 'string' && cookie.path.startsWith('/');
      }).map((cookie: StoredCookie): StoredCookie => {
        return {
          name: cookie.name.slice(0, 256),
          value: String(cookie.value).slice(0, 8192),
          domain: cookie.domain.toLowerCase(),
          path: cookie.path,
          secure: Boolean(cookie.secure),
          httpOnly: Boolean(cookie.httpOnly),
          hostOnly: Boolean(cookie.hostOnly),
          expiresAt: Number.isFinite(Number(cookie.expiresAt)) ? Number(cookie.expiresAt) : -1,
          createdAt: Number.isFinite(Number(cookie.createdAt)) ? Number(cookie.createdAt) : Date.now()
        };
      }).slice(0, 500);
      this.purgeExpired();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'cookie store is corrupt; starting empty');
      this.persistence.preserveCorrupt(this.path);
      this.cookies = [];
    }
  }

  private purgeExpired(): void {
    const now = Date.now();
    this.cookies = this.cookies.filter((cookie: StoredCookie): boolean => {
      return cookie.expiresAt < 0 || cookie.expiresAt > now;
    });
  }

  private removeMatching(next: StoredCookie): void {
    this.cookies = this.cookies.filter((cookie: StoredCookie): boolean => {
      return cookie.name !== next.name || cookie.domain !== next.domain || cookie.path !== next.path;
    });
  }

  private clearHost(host: string): void {
    this.cookies = this.cookies.filter((cookie: StoredCookie): boolean => {
      return !matchesDomain(host, cookie);
    });
  }
}

function setCookieValues(headers: Record<string, Object>): string[] {
  let value: Object | undefined = headers['set-cookie'];
  if (value === undefined) {
    value = headers['Set-Cookie'];
  }
  if (typeof value === 'string') {
    return splitCombinedSetCookies(value);
  }
  if (Array.isArray(value)) {
    const values: string[] = [];
    for (const item of value as Object[]) {
      if (typeof item === 'string') {
        values.push(...splitCombinedSetCookies(String(item)));
      }
    }
    return values;
  }
  return [];
}

function fallbackCookieValues(raw: string): string[] {
  const combined = splitCombinedSetCookies(raw);
  if (combined.length > 1) {
    return combined;
  }
  const pairs = raw.split(';')
    .map((item: string): string => item.trim())
    .filter((item: string): boolean => isCookiePair(item) && !isCookieAttribute(item));
  return pairs.length > 0 ? [`${pairs.join('; ')}; Path=/`] : [];
}

function parseSetCookie(raw: string, responseUrl: string, urlParser: CookieUrlParser): ParsedSetCookie {
  const parts = raw.split(';').map((item: string): string => item.trim());
  const pair = parts.shift() ?? '';
  const separator = pair.indexOf('=');
  if (separator <= 0) {
    return { cookie: null, clearHost: false };
  }
  const response = urlParser.parse(responseUrl);
  const name = pair.slice(0, separator).trim();
  const value = pair.slice(separator + 1).trim();
  if (name.length === 0 || name.length > 256 || isCookieAttribute(`${name}=${value}`)) {
    return { cookie: null, clearHost: false };
  }
  let domain = response.hostname.toLowerCase();
  let hostOnly = true;
  let cookiePath = defaultPath(response.pathname);
  let secure = false;
  let httpOnly = false;
  let expiresAt = -1;
  let clearHost = false;

  for (const part of parts) {
    const index = part.indexOf('=');
    const key = (index >= 0 ? part.slice(0, index) : part).trim().toLowerCase();
    const option = index >= 0 ? part.slice(index + 1).trim() : '';
    if (key === 'domain' && option.length > 0) {
      const candidate = option.replace(/^\./u, '').toLowerCase();
      // 拒绝 `Domain=com` / `Domain=co.uk` 这类公共后缀，避免一张 Cookie 覆盖整个 TLD。
      if (isPublicSuffix(candidate)) {
        return { cookie: null, clearHost: false };
      }
      if (!domainMatches(response.hostname.toLowerCase(), candidate)) {
        return { cookie: null, clearHost: false };
      }
      domain = candidate;
      hostOnly = false;
    } else if (key === 'path' && option.startsWith('/')) {
      cookiePath = option;
    } else if (key === 'max-age') {
      const seconds = Number(option);
      if (Number.isFinite(seconds)) {
        expiresAt = Date.now() + seconds * 1000;
        clearHost = name === 'buvid3' && seconds <= 0;
      }
    } else if (key === 'expires') {
      const parsed = Date.parse(option);
      if (Number.isFinite(parsed)) {
        expiresAt = parsed;
      }
    } else if (key === 'secure') {
      secure = true;
    } else if (key === 'httponly') {
      httpOnly = true;
    }
  }

  return {
    cookie: {
      name: name,
      value: value,
      domain: domain,
      path: cookiePath,
      secure: secure,
      httpOnly: httpOnly,
      hostOnly: hostOnly,
      expiresAt: expiresAt,
      createdAt: Date.now()
    },
    clearHost: clearHost
  };
}

function defaultPath(pathname: string): string {
  if (!pathname.startsWith('/')) {
    return '/';
  }
  const index = pathname.lastIndexOf('/');
  return index <= 0 ? '/' : pathname.slice(0, index);
}

function matchesDomain(host: string, cookie: StoredCookie): boolean {
  if (cookie.hostOnly) {
    return host === cookie.domain;
  }
  return host === cookie.domain || host.endsWith(`.${cookie.domain}`);
}

function domainMatches(host: string, domain: string): boolean {
  return host === domain || host.endsWith(`.${domain}`);
}

/** 只阻止最常见的多级公共后缀；单标签域名本身就是公共后缀（com、localhost）。 */
const PUBLIC_SUFFIXES: string[] = [
  'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn', 'ac.cn',
  'co.uk', 'org.uk', 'ac.uk', 'gov.uk',
  'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'go.jp',
  'com.au', 'net.au', 'org.au', 'co.nz',
  'com.br', 'com.tw', 'com.hk', 'com.sg'
];

function isPublicSuffix(domain: string): boolean {
  const labels = domain.split('.');
  if (labels.length < 2) {
    return true;
  }
  if (PUBLIC_SUFFIXES.indexOf(domain) >= 0) {
    return true;
  }
  return labels.some((label: string): boolean =>
    label.length === 0 || !/^[a-z0-9-]+$/u.test(label) ||
    label.startsWith('-') || label.endsWith('-'));
}

function matchesAnyDomain(host: string, domains: string[]): boolean {
  return domains.some((domain: string): boolean => {
    return domainMatches(host, domain);
  });
}

function pathMatches(requestPath: string, cookiePath: string): boolean {
  if (requestPath === cookiePath) {
    return true;
  }
  if (cookiePath === '/') {
    return true;
  }
  return requestPath.startsWith(cookiePath.endsWith('/') ? cookiePath : `${cookiePath}/`);
}

function splitCombinedSetCookies(raw: string): string[] {
  const values: string[] = [];
  let start = 0;
  for (let index = 1; index < raw.length; index += 1) {
    if (raw[index] !== ',') {
      continue;
    }
    const rest = raw.slice(index + 1).trimStart();
    const pairEnd = rest.indexOf('=');
    const optionEnd = rest.indexOf(';');
    if (pairEnd > 0 && (optionEnd < 0 || pairEnd < optionEnd) && !/^expires\s*=/i.test(rest)) {
      values.push(raw.slice(start, index).trim());
      start = index + 1;
    }
  }
  values.push(raw.slice(start).trim());
  return values.filter((item: string): boolean => item.length > 0);
}

function isCookiePair(value: string): boolean {
  const separator = value.indexOf('=');
  return separator > 0 && separator < value.length - 1;
}

function isCookieAttribute(value: string): boolean {
  const separator = value.indexOf('=');
  const key = (separator >= 0 ? value.slice(0, separator) : value).trim().toLowerCase();
  return key === 'path' || key === 'domain' || key === 'expires' || key === 'max-age' ||
    key === 'samesite' || key === 'secure' || key === 'httponly' || key === 'priority';
}
