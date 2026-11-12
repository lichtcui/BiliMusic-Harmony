import {
  AppError,
  CatalogSearchResult,
  MobileTrack
} from '../types/MobileTypes';
import { toAppError } from '../util/Errors';

const DEFAULT_PAGE_SIZE = 20;
const MAX_KEYWORD_LENGTH = 80;

export type SearchStatus = 'idle' | 'searching' | 'loadingMore' | 'success' | 'empty' | 'error';

export interface SearchStoreSnapshot {
  status: SearchStatus;
  keyword: string;
  items: MobileTrack[];
  page: number;
  hasMore: boolean;
  total: number;
  error: AppError | null;
  canRetry: boolean;
}

export interface SearchGateway {
  search(keyword: string, page: number, pageSize: number): Promise<CatalogSearchResult>;
}

@Observed
export class SearchStore {
  @Track snapshot: SearchStoreSnapshot = idleSnapshot();

  private readonly gateway: SearchGateway;
  private generation: number = 0;
  private attemptedKeyword: string = '';
  private attemptedPages: number[] = [];
  private activeKeyword: string = '';
  private activePage: number = 0;
  private activePromise: Promise<void> | null = null;
  private retryPage: number = 0;
  private disposed: boolean = false;

  constructor(gateway: SearchGateway) {
    this.gateway = gateway;
  }

  read(): SearchStoreSnapshot {
    return cloneSnapshot(this.snapshot);
  }

  search(keyword: string): Promise<void> {
    if (this.disposed) {
      return Promise.resolve();
    }
    const query = normalizeKeyword(keyword);
    if (query.length === 0) {
      this.clear();
      return Promise.resolve();
    }
    if (this.activePromise !== null && this.activeKeyword === query && this.activePage === 1) {
      return this.activePromise;
    }
    if (this.attemptedKeyword === query && this.attemptedPages.indexOf(1) >= 0) {
      return Promise.resolve();
    }

    this.generation++;
    this.attemptedKeyword = query;
    this.attemptedPages = [];
    this.retryPage = 0;
    return this.requestPage(query, 1, 'searching', true);
  }

  loadMore(): Promise<void> {
    if (this.disposed) {
      return Promise.resolve();
    }
    const current = this.snapshot;
    if (current.status !== 'success' || !current.hasMore || current.keyword.length === 0) {
      return Promise.resolve();
    }
    const targetPage = current.page + 1;
    if (this.attemptedPages.indexOf(targetPage) >= 0) {
      return Promise.resolve();
    }
    return this.requestPage(current.keyword, targetPage, 'loadingMore');
  }

  retry(): Promise<void> {
    if (this.disposed) {
      return Promise.resolve();
    }
    const current = this.snapshot;
    if (current.status !== 'error' || !current.canRetry || this.retryPage < 1) {
      return Promise.resolve();
    }
    this.generation++;
    const status: SearchStatus = this.retryPage > current.page && current.page > 0
      ? 'loadingMore'
      : 'searching';
    return this.requestPage(current.keyword, this.retryPage, status);
  }

  clear(): void {
    if (this.disposed) {
      return;
    }
    this.generation++;
    this.attemptedKeyword = '';
    this.attemptedPages = [];
    this.activeKeyword = '';
    this.activePage = 0;
    this.activePromise = null;
    this.retryPage = 0;
    this.snapshot = idleSnapshot();
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.generation++;
    this.attemptedKeyword = '';
    this.attemptedPages = [];
    this.activeKeyword = '';
    this.activePage = 0;
    this.activePromise = null;
    this.retryPage = 0;
  }

  private requestPage(keyword: string, page: number, status: SearchStatus,
    resetResults: boolean = false): Promise<void> {
    if (this.disposed) {
      return Promise.resolve();
    }
    this.markAttempted(page);
    const items = resetResults ? [] : cloneTracks(this.snapshot.items);
    this.snapshot = {
      status: status,
      keyword: keyword,
      items: items,
      page: resetResults ? 0 : this.snapshot.page,
      hasMore: resetResults ? false : this.snapshot.hasMore,
      total: resetResults ? 0 : this.snapshot.total,
      error: null,
      canRetry: false
    };

    const generation = this.generation;
    const pending = this.executeRequest(keyword, page, generation);
    this.activeKeyword = keyword;
    this.activePage = page;
    this.activePromise = pending;
    return pending;
  }

  private async executeRequest(keyword: string, page: number, generation: number): Promise<void> {
    try {
      const result = await this.gateway.search(keyword, page, DEFAULT_PAGE_SIZE);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.applyResult(keyword, page, result);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.applyError(page, toAppError(error as Object));
    } finally {
      if (this.isCurrent(generation) && this.activePage === page) {
        this.activeKeyword = '';
        this.activePage = 0;
        this.activePromise = null;
      }
    }
  }

  private applyResult(keyword: string, requestedPage: number, result: CatalogSearchResult): void {
    const current = this.snapshot;
    const resolvedPage = normalizePage(result.page, requestedPage);
    const incoming = cloneTracks(result.items);
    const items = requestedPage > 1 ? mergeTracks(current.items, incoming) : incoming;
    this.snapshot = {
      status: items.length === 0 ? 'empty' : 'success',
      keyword: keyword,
      items: items,
      page: resolvedPage,
      hasMore: result.hasMore,
      total: Math.max(0, result.total),
      error: null,
      canRetry: false
    };
    this.retryPage = 0;
  }

  private applyError(page: number, error: AppError): void {
    this.retryPage = error.retryable ? page : 0;
    this.snapshot = {
      status: 'error',
      keyword: this.snapshot.keyword,
      items: cloneTracks(this.snapshot.items),
      page: this.snapshot.page,
      hasMore: this.snapshot.hasMore,
      total: this.snapshot.total,
      error: error,
      canRetry: error.retryable
    };
  }

  private markAttempted(page: number): void {
    if (this.attemptedPages.indexOf(page) < 0) {
      this.attemptedPages.push(page);
    }
  }

  private isCurrent(generation: number): boolean {
    return !this.disposed && generation === this.generation;
  }
}

function idleSnapshot(): SearchStoreSnapshot {
  return {
    status: 'idle',
    keyword: '',
    items: [],
    page: 0,
    hasMore: false,
    total: 0,
    error: null,
    canRetry: false
  };
}

function normalizeKeyword(keyword: string): string {
  return keyword.trim().slice(0, MAX_KEYWORD_LENGTH);
}

function normalizePage(page: number, fallback: number): number {
  return Number.isFinite(page) ? Math.max(1, Math.floor(page)) : fallback;
}

function mergeTracks(existing: MobileTrack[], incoming: MobileTrack[]): MobileTrack[] {
  const result = cloneTracks(existing);
  for (const track of incoming) {
    if (!result.some((item: MobileTrack): boolean => item.key === track.key)) {
      result.push(cloneTrack(track));
    }
  }
  return result;
}

function cloneSnapshot(snapshot: SearchStoreSnapshot): SearchStoreSnapshot {
  return {
    status: snapshot.status,
    keyword: snapshot.keyword,
    items: cloneTracks(snapshot.items),
    page: snapshot.page,
    hasMore: snapshot.hasMore,
    total: snapshot.total,
    error: snapshot.error === null ? null : {
      code: snapshot.error.code,
      message: snapshot.error.message,
      retryable: snapshot.error.retryable
    },
    canRetry: snapshot.canRetry
  };
}

function cloneTracks(tracks: MobileTrack[]): MobileTrack[] {
  return tracks.map((track: MobileTrack): MobileTrack => cloneTrack(track));
}

function cloneTrack(track: MobileTrack): MobileTrack {
  const copy: MobileTrack = {
    key: track.key,
    bvid: track.bvid,
    aid: track.aid,
    cid: track.cid,
    title: track.title,
    artist: track.artist,
    coverUrl: track.coverUrl,
    duration: track.duration,
    playCount: track.playCount
  };
  if (track.collectionSize !== undefined) {
    copy.collectionSize = track.collectionSize;
  }
  if (track.collectionTotalDuration !== undefined) {
    copy.collectionTotalDuration = track.collectionTotalDuration;
  }
  return copy;
}
