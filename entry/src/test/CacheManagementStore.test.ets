import { describe, expect, it } from '@ohos/hypium';
import {
  CacheManagementGateway,
  CacheManagementStore,
  CacheSizeStats
} from '../main/ets/state/CacheManagementStore';
import { NativeError } from '../main/ets/util/Errors';

class PendingCacheStatsCall {
  readonly promise: Promise<CacheSizeStats>;
  private resolveCallback: ((value: CacheSizeStats) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor() {
    this.promise = new Promise<CacheSizeStats>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(value: CacheSizeStats): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(value);
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

class ScenarioCacheManagementGateway implements CacheManagementGateway {
  imageValue: CacheSizeStats = cacheStats(2048, 3);
  lyricsValue: CacheSizeStats = cacheStats(1024, 2);
  audioValue: CacheSizeStats = cacheStats(4096, 4);
  imageStatsCalls: number = 0;
  lyricsStatsCalls: number = 0;
  audioStatsCalls: number = 0;
  imageClearCalls: number = 0;
  lyricsClearCalls: number = 0;
  audioClearCalls: number = 0;
  imageStatsFailure: Error | null = null;
  imageClearFailure: NativeError | null = null;
  lyricsClearFailure: Error | null = null;
  audioClearFailure: NativeError | null = null;
  holdImageClear: boolean = false;
  imageClearPending: PendingCacheStatsCall | null = null;

  librarySentinel: string = 'library-and-playlists';
  cookieSentinel: string = 'login-cookie';
  queueSentinel: string = 'playback-queue';
  positionSentinel: number = 42;

  async imageCacheStats(): Promise<CacheSizeStats> {
    this.imageStatsCalls++;
    if (this.imageStatsFailure !== null) {
      throw this.imageStatsFailure;
    }
    return this.imageValue;
  }

  async lyricsCacheStats(): Promise<CacheSizeStats> {
    this.lyricsStatsCalls++;
    return this.lyricsValue;
  }

  async audioCacheStats(): Promise<CacheSizeStats> {
    this.audioStatsCalls++;
    return this.audioValue;
  }

  async clearImageCache(): Promise<CacheSizeStats> {
    this.imageClearCalls++;
    if (this.holdImageClear) {
      if (this.imageClearPending === null) {
        this.imageClearPending = new PendingCacheStatsCall();
      }
      return this.imageClearPending.promise;
    }
    if (this.imageClearFailure !== null) {
      throw this.imageClearFailure;
    }
    this.imageValue = cacheStats(0, 0);
    return this.imageValue;
  }

  async clearLyricsCache(): Promise<CacheSizeStats> {
    this.lyricsClearCalls++;
    if (this.lyricsClearFailure !== null) {
      throw this.lyricsClearFailure;
    }
    this.lyricsValue = cacheStats(0, 0);
    return this.lyricsValue;
  }

  async clearAudioCache(): Promise<CacheSizeStats> {
    this.audioClearCalls++;
    if (this.audioClearFailure !== null) {
      throw this.audioClearFailure;
    }
    this.audioValue = cacheStats(0, 0);
    return this.audioValue;
  }
}

function cacheStats(bytes: number, entries: number): CacheSizeStats {
  return {
    bytes: bytes,
    entries: entries
  };
}

export default function cacheManagementStoreTest(): void {
  describe('CacheManagementStore', () => {
    it('refreshesAndSanitizesAllCacheStatsOnce', 0, async () => {
      const gateway = new ScenarioCacheManagementGateway();
      gateway.imageValue = cacheStats(2048.9, 3.8);
      gateway.lyricsValue = cacheStats(-10, 2.2);
      gateway.audioValue = cacheStats(4096.4, 4.6);
      const store = new CacheManagementStore(gateway);

      const first = store.refresh();
      const second = store.refresh();
      expect(first === second).assertTrue();
      expect(await first).assertTrue();
      expect(store.refreshing).assertFalse();
      expect(store.imageStats.bytes).assertEqual(2048);
      expect(store.imageStats.entries).assertEqual(3);
      expect(store.lyricsStats.bytes).assertEqual(0);
      expect(store.lyricsStats.entries).assertEqual(2);
      expect(store.audioStats.bytes).assertEqual(4096);
      expect(store.audioStats.entries).assertEqual(4);
      expect(gateway.imageStatsCalls).assertEqual(1);
      expect(gateway.lyricsStatsCalls).assertEqual(1);
      expect(gateway.audioStatsCalls).assertEqual(1);
      expect(store.error === null).assertTrue();
    });

    it('clearsOneTargetUpdatesOnlyItsStatsAndRetriesSafely', 0, async () => {
      const gateway = new ScenarioCacheManagementGateway();
      const store = new CacheManagementStore(gateway);
      await store.refresh();
      gateway.imageClearFailure = new NativeError('image.cacheClearFailed', '', true);

      expect(await store.clearImage()).assertFalse();
      expect(store.error?.code).assertEqual('image.cacheClearFailed');
      expect(store.error?.retryable).assertTrue();
      expect(store.errorAction).assertEqual('image');
      expect(store.imageStats.entries).assertEqual(3);
      expect(gateway.lyricsClearCalls).assertEqual(0);

      gateway.imageClearFailure = null;
      expect(await store.retry()).assertTrue();
      expect(store.imageStats.entries).assertEqual(0);
      expect(store.lyricsStats.entries).assertEqual(2);
      expect(store.error === null).assertTrue();
      expect(gateway.imageClearCalls).assertEqual(2);
      expect(gateway.lyricsClearCalls).assertEqual(0);

      expect(await store.clearLyrics()).assertTrue();
      expect(store.imageStats.entries).assertEqual(0);
      expect(store.lyricsStats.entries).assertEqual(0);
      expect(gateway.librarySentinel).assertEqual('library-and-playlists');
      expect(gateway.cookieSentinel).assertEqual('login-cookie');
      expect(gateway.queueSentinel).assertEqual('playback-queue');
      expect(gateway.positionSentinel).assertEqual(42);
    });

    it('clearsAudioCacheWithItsOwnFailureCode', 0, async () => {
      const gateway = new ScenarioCacheManagementGateway();
      const store = new CacheManagementStore(gateway);
      await store.refresh();
      gateway.audioClearFailure = new NativeError('player.audioCacheClearFailed', '', true);

      expect(await store.clearAudio()).assertFalse();
      expect(store.error?.code).assertEqual('player.audioCacheClearFailed');
      expect(store.errorAction).assertEqual('audio');
      expect(store.audioStats.entries).assertEqual(4);
      expect(gateway.imageClearCalls).assertEqual(0);
      expect(gateway.lyricsClearCalls).assertEqual(0);

      gateway.audioClearFailure = null;
      expect(await store.retry()).assertTrue();
      expect(gateway.audioClearCalls).assertEqual(2);
      expect(store.audioStats.entries).assertEqual(0);
      expect(store.imageStats.entries).assertEqual(3);
      expect(store.lyricsStats.entries).assertEqual(2);
    });

    it('mapsGenericCacheFailuresToSafeRetryableErrors', 0, async () => {
      const gateway = new ScenarioCacheManagementGateway();
      gateway.imageStatsFailure = new Error('https://example.invalid/cache?cookie=secret');
      const store = new CacheManagementStore(gateway);

      expect(await store.refresh()).assertFalse();
      expect(store.error?.code).assertEqual('cache.statsFailed');
      expect(store.error?.retryable).assertTrue();
      expect(store.errorAction).assertEqual('refresh');
      expect(store.error?.message.includes('https://')).assertFalse();
      expect(store.error?.message.toLowerCase().includes('cookie')).assertFalse();

      gateway.imageStatsFailure = null;
      expect(await store.retry()).assertTrue();
      expect(store.imageStats.entries).assertEqual(3);
      expect(store.error === null).assertTrue();

      gateway.lyricsClearFailure = new Error('simulated lyric clear failure');
      expect(await store.clearLyrics()).assertFalse();
      expect(store.error?.code).assertEqual('lyrics.cacheClearFailed');
      expect(store.errorAction).assertEqual('lyrics');
      expect(store.error?.message.includes('simulated')).assertFalse();
    });

    it('deduplicatesTheSameClearAndRejectsAnotherTargetWhileBusy', 0, async () => {
      const gateway = new ScenarioCacheManagementGateway();
      gateway.holdImageClear = true;
      const store = new CacheManagementStore(gateway);

      const first = store.clearImage();
      const second = store.clearImage();
      expect(first === second).assertTrue();
      expect(store.isBusy()).assertTrue();
      expect(store.isClearing('image')).assertTrue();
      expect(await store.clearLyrics()).assertFalse();
      expect(gateway.lyricsClearCalls).assertEqual(0);
      expect(store.clearing).assertEqual('image');

      const pending = gateway.imageClearPending;
      expect(pending === null).assertFalse();
      if (pending !== null) {
        pending.resolve(cacheStats(0, 0));
      }
      const results = await Promise.all([first, second]);
      expect(results[0]).assertTrue();
      expect(results[1]).assertTrue();
      expect(gateway.imageClearCalls).assertEqual(1);
      expect(store.imageStats.entries).assertEqual(0);
      expect(store.isBusy()).assertFalse();

      gateway.holdImageClear = false;
      expect(await store.clearLyrics()).assertTrue();
      expect(gateway.lyricsClearCalls).assertEqual(1);
      expect(store.lyricsStats.entries).assertEqual(0);
    });

    it('retriesClearWithoutTouchingTheOtherCache', 0, async () => {
      const gateway = new ScenarioCacheManagementGateway();
      const store = new CacheManagementStore(gateway);
      await store.refresh();
      gateway.lyricsClearFailure = new Error('simulated lyric clear failure');

      expect(await store.clearLyrics()).assertFalse();
      expect(store.errorAction).assertEqual('lyrics');
      expect(store.lyricsStats.entries).assertEqual(2);
      expect(gateway.imageClearCalls).assertEqual(0);

      gateway.lyricsClearFailure = null;
      expect(await store.retry()).assertTrue();
      expect(gateway.lyricsClearCalls).assertEqual(2);
      expect(gateway.imageClearCalls).assertEqual(0);
      expect(store.lyricsStats.entries).assertEqual(0);
      expect(store.imageStats.entries).assertEqual(3);
      expect(store.error === null).assertTrue();
    });
  });
}
