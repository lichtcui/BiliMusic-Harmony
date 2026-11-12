/**
 * 纯函数 URL 白名单：不依赖平台 NetworkKit / URL 服务，主机侧测试也能直接跑。
 *
 * 图片只允许 B 站图床；媒体只允许 B 站已知 CDN 族。新增域名必须同时补测试，
 * 避免再次出现 `allowedHosts: [parsed.hostname]` 这种自证式校验。
 */
export const BILI_IMAGE_HOSTS: string[] = ['hdslb.com', 'biliimg.com'];

/** 媒体允许的 B 站自有 CDN 域；`bilibili.com` / `akamaized.net` 只放行 `upos-*` 主机。 */
export const BILI_MEDIA_HOSTS: string[] = ['bilivideo.com', 'bilivideo.cn', 'szbdyd.com'];

const MEDIA_UPOS_HOST = /^upos-[a-z0-9-]+\.(?:bilibili\.com|akamaized\.net)$/u;

export function isBiliImageUrl(targetUrl: string): boolean {
  const host = httpsHost(targetUrl);
  return host !== null && hostMatches(host, BILI_IMAGE_HOSTS);
}

export function isBiliMediaUrl(targetUrl: string): boolean {
  return biliMediaHost(targetUrl).length > 0;
}

/**
 * 返回通过严格媒体规则的主机名，未通过时返回空串。
 * 调用方用它构造精确的 `allowedHosts: [host]`，避免再退回整族后缀放行。
 */
export function biliMediaHost(targetUrl: string): string {
  const host = httpsHost(targetUrl);
  if (host === null) {
    return '';
  }
  if (hostMatches(host, BILI_MEDIA_HOSTS) || MEDIA_UPOS_HOST.test(host)) {
    return host;
  }
  return '';
}

function hostMatches(host: string, domains: string[]): boolean {
  return domains.some((domain: string): boolean =>
    host === domain || host.endsWith(`.${domain}`));
}

function httpsHost(value: string): string | null {
  const match = value.trim().match(/^https:\/\/([^/?#]+)(?:[/?#]|$)/iu);
  if (match === null) {
    return null;
  }
  const authority = match[1];
  if (authority.length === 0 || authority.indexOf('@') >= 0 ||
    authority.indexOf('\\') >= 0 || authority.startsWith('[')) {
    return null;
  }
  const firstColon = authority.indexOf(':');
  const lastColon = authority.lastIndexOf(':');
  let host = authority;
  if (firstColon >= 0) {
    if (firstColon !== lastColon) {
      return null;
    }
    host = authority.slice(0, firstColon);
    if (authority.slice(lastColon + 1) !== '443') {
      return null;
    }
  }
  host = host.toLowerCase();
  if (host.length === 0 || !/^[a-z0-9.-]+$/u.test(host) ||
    host.startsWith('.') || host.endsWith('.') || host.indexOf('..') >= 0) {
    return null;
  }
  return host;
}