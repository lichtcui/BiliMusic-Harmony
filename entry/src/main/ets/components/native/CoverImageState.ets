export enum CoverImagePhase {
  Loading = 0,
  Ready = 1,
  Failed = 2
}

/**
 * 本地封面（用户从相册选择后复制到 app 沙箱）用 `file://` URI。
 * 这类图片不需要走网络图片缓存，直接交给 `Image` 解码；网络封面仍然走 provider。
 */
export function isLocalCoverUri(value: string): boolean {
  return value.trim().toLowerCase().startsWith('file://');
}

export class CoverRequestTicket {
  readonly url: string;
  readonly generation: number;

  constructor(url: string, generation: number) {
    this.url = url;
    this.generation = generation;
  }
}

export class CoverRequestTracker {
  private generation: number = 0;
  private currentUrl: string = '';

  begin(url: string): CoverRequestTicket {
    this.generation += 1;
    this.currentUrl = url.trim();
    return new CoverRequestTicket(this.currentUrl, this.generation);
  }

  isActiveUrl(url: string): boolean {
    const normalized = url.trim();
    return normalized.length > 0 && normalized === this.currentUrl;
  }

  isCurrent(ticket: CoverRequestTicket): boolean {
    return ticket.generation === this.generation && ticket.url === this.currentUrl;
  }

  invalidate(): void {
    this.generation += 1;
    this.currentUrl = '';
  }
}

export class CoverLoadReferences {
  private readonly counts: Map<string, number> = new Map<string, number>();

  retain(url: string): number {
    const key = url.trim();
    const count = (this.counts.get(key) ?? 0) + 1;
    this.counts.set(key, count);
    return count;
  }

  release(url: string): number {
    const key = url.trim();
    const count = this.counts.get(key) ?? 0;
    if (count <= 1) {
      this.counts.delete(key);
      return 0;
    }
    const remaining = count - 1;
    this.counts.set(key, remaining);
    return remaining;
  }
}
