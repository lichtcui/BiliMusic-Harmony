import { AppError } from '../types/MobileTypes';
import { appError, NativeError } from '../util/Errors';

export type CacheClearTarget = 'image' | 'lyrics' | 'audio';
export type CacheManagementTarget = CacheClearTarget | '';
export type CacheManagementAction = 'refresh' | 'image' | 'lyrics' | 'audio';

export interface CacheSizeStats {
  bytes: number;
  entries: number;
}

export interface CacheManagementGateway {
  imageCacheStats(): Promise<CacheSizeStats>;
  lyricsCacheStats(): Promise<CacheSizeStats>;
  audioCacheStats(): Promise<CacheSizeStats>;
  clearImageCache(): Promise<CacheSizeStats>;
  clearLyricsCache(): Promise<CacheSizeStats>;
  clearAudioCache(): Promise<CacheSizeStats>;
}

@Observed
export class CacheManagementStore {
  @Track imageStats: CacheSizeStats = emptyCacheStats();
  @Track lyricsStats: CacheSizeStats = emptyCacheStats();
  @Track audioStats: CacheSizeStats = emptyCacheStats();
  @Track refreshing: boolean = false;
  @Track clearing: CacheManagementTarget = '';
  @Track error: AppError | null = null;
  @Track errorAction: CacheManagementAction = 'refresh';

  private readonly gateway: CacheManagementGateway;
  private generation: number = 0;
  private refreshPromise: Promise<boolean> | null = null;
  private clearPromise: Promise<boolean> | null = null;
  private activeClearTarget: CacheManagementTarget = '';

  constructor(gateway: CacheManagementGateway) {
    this.gateway = gateway;
  }

  isBusy(): boolean {
    return this.refreshing || this.clearing !== '';
  }

  isClearing(target: CacheClearTarget): boolean {
    return this.clearing === target;
  }

  refresh(): Promise<boolean> {
    if (this.refreshPromise !== null) {
      return this.refreshPromise;
    }
    const generation = this.generation;
    this.refreshing = true;
    this.error = null;
    const pending: Promise<boolean> = this.performRefresh(generation)
      .then((): boolean => true, (error: Object): boolean => {
        if (generation === this.generation) {
          this.error = cacheFailure('cache.statsFailed', error);
          this.errorAction = 'refresh';
        }
        return false;
      });
    this.refreshPromise = pending;
    pending.then((): void => {
      if (this.refreshPromise === pending) {
        this.refreshPromise = null;
        this.refreshing = false;
      }
    }, (): void => {
      if (this.refreshPromise === pending) {
        this.refreshPromise = null;
        this.refreshing = false;
      }
    });
    return pending;
  }

  clearImage(): Promise<boolean> {
    return this.clear('image');
  }

  clearLyrics(): Promise<boolean> {
    return this.clear('lyrics');
  }

  clearAudio(): Promise<boolean> {
    return this.clear('audio');
  }

  retry(): Promise<boolean> {
    if (this.errorAction === 'image') {
      return this.clearImage();
    }
    if (this.errorAction === 'lyrics') {
      return this.clearLyrics();
    }
    if (this.errorAction === 'audio') {
      return this.clearAudio();
    }
    return this.refresh();
  }

  private clear(target: CacheClearTarget): Promise<boolean> {
    if (this.clearPromise !== null) {
      return this.activeClearTarget === target ? this.clearPromise : Promise.resolve(false);
    }
    const generation = this.generation + 1;
    this.generation = generation;
    this.activeClearTarget = target;
    this.clearing = target;
    this.error = null;
    const pending: Promise<boolean> = this.performClear(target, generation)
      .then((): boolean => true, (error: Object): boolean => {
        if (generation === this.generation) {
          this.error = cacheFailure(
            target === 'image' ? 'image.cacheClearFailed' :
              target === 'lyrics' ? 'lyrics.cacheClearFailed' : 'player.audioCacheClearFailed',
            error
          );
          this.errorAction = target;
        }
        return false;
      });
    this.clearPromise = pending;
    pending.then((): void => {
      if (this.clearPromise === pending) {
        this.clearPromise = null;
        this.activeClearTarget = '';
        this.clearing = '';
      }
    }, (): void => {
      if (this.clearPromise === pending) {
        this.clearPromise = null;
        this.activeClearTarget = '';
        this.clearing = '';
      }
    });
    return pending;
  }

  private async performRefresh(generation: number): Promise<void> {
    const results = await Promise.all([
      this.gateway.imageCacheStats(),
      this.gateway.lyricsCacheStats(),
      this.gateway.audioCacheStats()
    ]);
    if (generation !== this.generation) {
      return;
    }
    this.imageStats = sanitizeStats(results[0]);
    this.lyricsStats = sanitizeStats(results[1]);
    this.audioStats = sanitizeStats(results[2]);
    this.error = null;
  }

  private async performClear(target: CacheClearTarget,
    generation: number): Promise<void> {
    const stats = target === 'image' ?
      await this.gateway.clearImageCache() :
      target === 'lyrics' ? await this.gateway.clearLyricsCache() :
        await this.gateway.clearAudioCache();
    if (generation !== this.generation) {
      return;
    }
    if (target === 'image') {
      this.imageStats = sanitizeStats(stats);
    } else if (target === 'lyrics') {
      this.lyricsStats = sanitizeStats(stats);
    } else {
      this.audioStats = sanitizeStats(stats);
    }
    this.error = null;
  }
}

function emptyCacheStats(): CacheSizeStats {
  return {
    bytes: 0,
    entries: 0
  };
}

function sanitizeStats(value: CacheSizeStats): CacheSizeStats {
  return {
    bytes: Number.isFinite(value.bytes) && value.bytes > 0 ? Math.floor(value.bytes) : 0,
    entries: Number.isFinite(value.entries) && value.entries > 0 ? Math.floor(value.entries) : 0
  };
}

function cacheFailure(defaultCode: string, error: Object): AppError {
  if (error instanceof NativeError) {
    return {
      code: error.appError.code,
      message: error.appError.message,
      retryable: error.appError.retryable
    };
  }
  return appError(defaultCode, '', true);
}
