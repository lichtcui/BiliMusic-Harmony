import { CatalogFeed } from '../types/MobileTypes';
import { toAppError } from './Errors';

/**
 * `discover()` / `recommend()` 的一次性探针输出。
 * 只保留条数 / 页码 / 是否有更多 / 错误码，**不输出媒体地址、封面地址或 Cookie**，
 * 因此可以安全地进诊断页文本与粘贴板。
 */
export function describeFeedProbe(kind: string, feed: CatalogFeed): string {
  const items = Math.max(0, Math.trunc(feed.items.length));
  const page = Math.max(1, Math.trunc(feed.page));
  return `${probeToken(kind)}: ok items=${items} page=${page} hasMore=${feed.hasMore ? 'true' : 'false'}`;
}

export function describeFeedProbeError(kind: string, error: Object): string {
  return `${probeToken(kind)}: failed code=${toAppError(error).code}`;
}

function probeToken(kind: string): string {
  const trimmed = kind.trim().slice(0, 16);
  return trimmed.length > 0 ? trimmed : 'feed';
}
