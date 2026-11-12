import { describe, expect, it } from '@ohos/hypium';
import { BiliImage } from '../main/ets/services/BiliHttpClient';
import {
  DEFAULT_IMAGE_MAX_BYTES,
  ImageCacheResult,
  ImageCacheService,
  ImageDiskCache,
  ImageDiskEntry,
  ImageDiskStats,
  ImageFetcher,
  MemoryImageDiskCache,
  imageCacheKey,
  isAllowedBiliImageUrl,
  sha256Hex
} from '../main/ets/services/ImageCacheService';
import { NativeError, wait } from '../main/ets/util/Errors';

class ScenarioImageFetcher implements ImageFetcher {
  requests: string[] = [];
  active: number = 0;
  maxActive: number = 0;
  mime: string = 'image/jpeg';
  byteLength: number = 4;
  delayMs: number = 0;
  fail: boolean = false;

  async requestImage(targetUrl: string): Promise<BiliImage> {
    this.requests.push(targetUrl);
    this.active += 1;
    this.maxActive = Math.max(this.maxActive, this.active);
    try {
      if (this.delayMs > 0) {
        await wait(this.delayMs);
      }
      if (this.fail) {
        throw new Error('simulated network failure');
      }
      return {
        mime: this.mime,
        data: new ArrayBuffer(this.byteLength)
      };
    } finally {
      this.active -= 1;
    }
  }
}

class FailingWriteDiskCache implements ImageDiskCache {
  private readonly inner: MemoryImageDiskCache = new MemoryImageDiskCache();

  async read(key: string): Promise<ImageDiskEntry | null> {
    return this.inner.read(key);
  }

  async write(_key: string, _mime: string, _data: ArrayBuffer): Promise<void> {
    throw new Error('simulated disk write failure');
  }

  async remove(key: string): Promise<void> {
    return this.inner.remove(key);
  }

  async clear(): Promise<void> {
    return this.inner.clear();
  }

  async stats(): Promise<ImageDiskStats> {
    return this.inner.stats();
  }
}

class ControllableDiskCache implements ImageDiskCache {
  readonly inner: MemoryImageDiskCache = new MemoryImageDiskCache();
  failStats: boolean = false;
  failClear: boolean = false;
  clearDelayMs: number = 0;
  clearCalls: number = 0;
  statsCalls: number = 0;

  async read(key: string): Promise<ImageDiskEntry | null> {
    return this.inner.read(key);
  }

  async write(key: string, mime: string, data: ArrayBuffer): Promise<void> {
    return this.inner.write(key, mime, data);
  }

  async remove(key: string): Promise<void> {
    return this.inner.remove(key);
  }

  async clear(): Promise<void> {
    this.clearCalls++;
    if (this.clearDelayMs > 0) {
      await wait(this.clearDelayMs);
    }
    if (this.failClear) {
      throw new Error('simulated disk clear failure');
    }
    return this.inner.clear();
  }

  async stats(): Promise<ImageDiskStats> {
    this.statsCalls++;
    if (this.failStats) {
      throw new Error('simulated disk stats failure');
    }
    return this.inner.stats();
  }
}

export default function imageCacheServiceTest(): void {
  describe('ImageCacheService', () => {
    it('validatesAllowedBiliImageUrls', 0, () => {
      expect(isAllowedBiliImageUrl('https://i0.hdslb.com/bfs/test.jpg')).assertTrue();
      expect(isAllowedBiliImageUrl('https://s1.biliimg.com/cover.jpg')).assertTrue();
      expect(isAllowedBiliImageUrl('https://hdslb.com/image.webp')).assertTrue();
      expect(isAllowedBiliImageUrl('https://i0.hdslb.com:443/image.webp')).assertTrue();

      expect(isAllowedBiliImageUrl('http://i0.hdslb.com/image.jpg')).assertFalse();
      expect(isAllowedBiliImageUrl('https://example.com/image.jpg')).assertFalse();
      expect(isAllowedBiliImageUrl('https://i0.hdslb.com.evil.example/image.jpg')).assertFalse();
      expect(isAllowedBiliImageUrl('https://127.0.0.1/image.jpg')).assertFalse();
      expect(isAllowedBiliImageUrl('https://[::1]/image.jpg')).assertFalse();
      expect(isAllowedBiliImageUrl('https://user:pass@i0.hdslb.com/image.jpg')).assertFalse();
      expect(isAllowedBiliImageUrl('https://i0.hdslb.com:8443/image.jpg')).assertFalse();
      expect(isAllowedBiliImageUrl('https://i0.hdslb.com\n.evil/image.jpg')).assertFalse();
      expect(isAllowedBiliImageUrl('file:///tmp/image.jpg')).assertFalse();
    });

    it('createsStableOpaqueSha256CacheKeys', 0, () => {
      const targetUrl = 'https://i0.hdslb.com/bfs/test.jpg';
      const key = imageCacheKey(targetUrl);

      expect(sha256Hex('abc')).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(key).assertEqual(
        'image-v1-430b1ef82a68f823025621ec4f2fee1ff443d417cc64bce6c1605ea4a13fe799'
      );
      expect(imageCacheKey(targetUrl)).assertEqual(key);
      expect(imageCacheKey(`${targetUrl}?token=secret`) === key).assertFalse();
      expect(key.indexOf('hdslb')).assertEqual(-1);
      expect(key.indexOf(targetUrl)).assertEqual(-1);
    });

    it('rejectsDisallowedUrlsBeforeNetwork', 0, async () => {
      const fetcher = new ScenarioImageFetcher();
      const service = new ImageCacheService(fetcher, new MemoryImageDiskCache());
      const rejected: string[] = [
        'http://i0.hdslb.com/image.jpg',
        'https://example.com/image.jpg',
        'https://127.0.0.1/image.jpg',
        'https://user:pass@i0.hdslb.com/image.jpg',
        'https://i0.hdslb.com:8443/image.jpg',
        'https://sub.hdslb.com.evil.example/image.jpg'
      ];

      for (const targetUrl of rejected) {
        const result = await service.loadImage(targetUrl);
        expect(result === null).assertTrue();
      }
      expect(fetcher.requests.length).assertEqual(0);
      await service.shutdown();
    });

    it('deduplicatesInflightAndServesMemoryCache', 0, async () => {
      const fetcher = new ScenarioImageFetcher();
      fetcher.delayMs = 10;
      const service = new ImageCacheService(fetcher, new MemoryImageDiskCache());
      const targetUrl = 'https://i0.hdslb.com/bfs/deduplicate.jpg';

      const pending: Promise<ImageCacheResult | null>[] = [
        service.loadImage(targetUrl),
        service.loadImage(targetUrl)
      ];
      const results = await Promise.all(pending);
      expect(fetcher.requests.length).assertEqual(1);
      expect(results[0]?.source).assertEqual('network');
      expect(results[1]?.source).assertEqual('network');

      const cached = await service.loadImage(targetUrl);
      expect(cached?.source).assertEqual('memory');
      expect(fetcher.requests.length).assertEqual(1);
      await service.shutdown();
    });

    it('usesDiskCacheAndRefetchesAfterClear', 0, async () => {
      const fetcher = new ScenarioImageFetcher();
      const disk = new MemoryImageDiskCache();
      const service = new ImageCacheService(fetcher, disk, 0);
      const targetUrl = 'https://i0.hdslb.com/bfs/disk.jpg';

      const first = await service.loadImage(targetUrl);
      const second = await service.loadImage(targetUrl);
      expect(first?.source).assertEqual('network');
      expect(second?.source).assertEqual('disk');
      expect(fetcher.requests.length).assertEqual(1);

      const cleared = await service.clear();
      expect(cleared.bytes).assertEqual(0);
      expect(cleared.entries).assertEqual(0);
      const third = await service.loadImage(targetUrl);
      expect(third?.source).assertEqual('network');
      expect(fetcher.requests.length).assertEqual(2);
      await service.shutdown();
    });

    it('reportsCombinedStatsAndMapsControlFailures', 0, async () => {
      const fetcher = new ScenarioImageFetcher();
      fetcher.byteLength = 6;
      const disk = new ControllableDiskCache();
      const service = new ImageCacheService(fetcher, disk);
      await service.loadImage('https://i0.hdslb.com/bfs/stats-one.jpg');
      await service.loadImage('https://i0.hdslb.com/bfs/stats-two.jpg');

      const stats = await service.stats();
      expect(stats.bytes).assertEqual(12);
      expect(stats.entries).assertEqual(2);
      expect(stats.memoryBytes).assertEqual(12);
      expect(stats.memoryEntries).assertEqual(2);

      disk.failStats = true;
      let statsFailure: NativeError | null = null;
      try {
        await service.stats();
      } catch (error) {
        statsFailure = error as NativeError;
      }
      expect(statsFailure?.appError.code).assertEqual('image.cacheStatsFailed');
      expect(statsFailure?.appError.retryable).assertTrue();

      disk.failStats = false;
      disk.failClear = true;
      let clearFailure: NativeError | null = null;
      try {
        await service.clear();
      } catch (error) {
        clearFailure = error as NativeError;
      }
      expect(clearFailure?.appError.code).assertEqual('image.cacheClearFailed');
      expect(clearFailure?.appError.retryable).assertTrue();
      const afterFailure = await service.stats();
      expect(afterFailure.memoryBytes).assertEqual(0);
      expect(afterFailure.entries).assertEqual(2);

      disk.failClear = false;
      const retried = await service.clear();
      expect(retried.bytes).assertEqual(0);
      expect(retried.entries).assertEqual(0);
      expect(retried.memoryBytes).assertEqual(0);
      await service.shutdown();
    });

    it('deduplicatesConcurrentClearCalls', 0, async () => {
      const fetcher = new ScenarioImageFetcher();
      const disk = new ControllableDiskCache();
      disk.clearDelayMs = 10;
      const service = new ImageCacheService(fetcher, disk);
      await service.loadImage('https://i0.hdslb.com/bfs/clear-once.jpg');

      const first = service.clear();
      const second = service.clear();
      expect(first === second).assertTrue();
      const results = await Promise.all([first, second]);
      expect(disk.clearCalls).assertEqual(1);
      expect(results[0].bytes).assertEqual(0);
      expect(results[1].entries).assertEqual(0);
      await service.shutdown();
    });

    it('doesNotRepopulateAfterClearAndRefetchesOnDemand', 0, async () => {
      const fetcher = new ScenarioImageFetcher();
      fetcher.delayMs = 20;
      const disk = new ControllableDiskCache();
      const service = new ImageCacheService(fetcher, disk);
      const targetUrl = 'https://i0.hdslb.com/bfs/inflight-clear.jpg';

      const pending = service.loadImage(targetUrl);
      await wait(2);
      const cleared = await service.clear();
      expect(cleared.bytes).assertEqual(0);
      const staleLoad = await pending;
      expect(staleLoad === null).assertTrue();
      await wait(30);
      const afterStaleLoad = await service.stats();
      expect(afterStaleLoad.memoryEntries).assertEqual(0);
      expect(afterStaleLoad.entries).assertEqual(0);

      const refetched = await service.loadImage(targetUrl);
      expect(refetched?.source).assertEqual('network');
      expect(fetcher.requests.length).assertEqual(2);
      const finalStats = await service.stats();
      expect(finalStats.entries).assertEqual(1);
      expect(finalStats.memoryEntries).assertEqual(1);
      await service.shutdown();
    });

    it('returnsNullForEmptyOversizeMimeAndNetworkFailures', 0, async () => {
      const cases: ScenarioImageFetcher[] = [];
      const empty = new ScenarioImageFetcher();
      empty.byteLength = 0;
      cases.push(empty);
      const oversize = new ScenarioImageFetcher();
      oversize.byteLength = DEFAULT_IMAGE_MAX_BYTES + 1;
      cases.push(oversize);
      const wrongMime = new ScenarioImageFetcher();
      wrongMime.mime = 'text/html';
      cases.push(wrongMime);
      const networkFailure = new ScenarioImageFetcher();
      networkFailure.fail = true;
      cases.push(networkFailure);

      for (let index = 0; index < cases.length; index++) {
        const service = new ImageCacheService(cases[index], new MemoryImageDiskCache());
        const result = await service.loadImage(`https://i0.hdslb.com/bfs/failure-${index}.jpg`);
        expect(result === null).assertTrue();
        const stats = await service.stats();
        expect(stats.memoryEntries).assertEqual(0);
        expect(stats.entries).assertEqual(0);
        await service.shutdown();
      }
    });

    it('keepsSuccessfulImageWhenDiskWriteFails', 0, async () => {
      const fetcher = new ScenarioImageFetcher();
      const service = new ImageCacheService(fetcher, new FailingWriteDiskCache());
      const result = await service.loadImage('https://i0.hdslb.com/bfs/disk-write.jpg');

      expect(result?.source).assertEqual('network');
      expect(result?.mime).assertEqual('image/jpeg');
      expect(result?.data.byteLength).assertEqual(4);
      expect(fetcher.requests.length).assertEqual(1);
      await service.shutdown();
    });

    it('enforcesConcurrencyAndMemoryLimits', 0, async () => {
      const fetcher = new ScenarioImageFetcher();
      fetcher.byteLength = 8;
      fetcher.delayMs = 10;
      const disk = new MemoryImageDiskCache(12);
      const service = new ImageCacheService(fetcher, disk, 12, 2);
      const pending: Promise<ImageCacheResult | null>[] = [];
      for (let index = 0; index < 4; index++) {
        pending.push(service.loadImage(`https://i0.hdslb.com/bfs/concurrent-${index}.jpg`));
      }

      const results = await Promise.all(pending);
      expect(fetcher.requests.length).assertEqual(4);
      expect(fetcher.maxActive).assertEqual(2);
      expect(results.length).assertEqual(4);
      const cacheStats = await service.stats();
      expect(cacheStats.memoryBytes <= 12).assertTrue();
      expect(cacheStats.memoryEntries <= 1).assertTrue();
      expect(cacheStats.bytes <= 12).assertTrue();
      expect(cacheStats.entries <= 1).assertTrue();
      await service.shutdown();
    });

    it('boundsTimeoutsAndCancellation', 0, async () => {
      const timeoutFetcher = new ScenarioImageFetcher();
      timeoutFetcher.delayMs = 60;
      const timeoutService = new ImageCacheService(timeoutFetcher, new MemoryImageDiskCache());
      const timedOut = await timeoutService.loadImage('https://i0.hdslb.com/bfs/timeout.jpg', 5);
      expect(timedOut === null).assertTrue();
      await wait(80);
      const timeoutStats = await timeoutService.stats();
      expect(timeoutStats.memoryEntries).assertEqual(0);
      expect(timeoutStats.entries).assertEqual(0);
      await timeoutService.shutdown();

      const cancelFetcher = new ScenarioImageFetcher();
      cancelFetcher.delayMs = 60;
      const cancelService = new ImageCacheService(cancelFetcher, new MemoryImageDiskCache());
      const targetUrl = 'https://i0.hdslb.com/bfs/cancel.jpg';
      const pending = cancelService.loadImage(targetUrl);
      await wait(1);
      expect(cancelService.cancel(targetUrl)).assertTrue();
      const cancelled = await pending;
      expect(cancelled === null).assertTrue();
      expect(cancelService.cancel(targetUrl)).assertFalse();
      await wait(80);
      const cancelStats = await cancelService.stats();
      expect(cancelStats.memoryEntries).assertEqual(0);
      expect(cancelStats.entries).assertEqual(0);
      await cancelService.shutdown();
    });
  });
}
