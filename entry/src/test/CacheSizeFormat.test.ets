import { describe, expect, it } from '@ohos/hypium';
import {
  cacheStatsEmpty,
  formatCacheBytes,
  totalCacheBytes
} from '../main/ets/components/native/CacheSizeFormat';
import { CacheSizeStats } from '../main/ets/state/CacheManagementStore';

function stats(bytes: number, entries: number): CacheSizeStats {
  return {
    bytes: bytes,
    entries: entries
  };
}

export default function cacheSizeFormatTest(): void {
  describe('CacheSizeFormat', () => {
    it('formatsBytesWithTheSettingsUnitThresholds', 0, () => {
      expect(formatCacheBytes(0)).assertEqual('0 B');
      expect(formatCacheBytes(1023)).assertEqual('1023 B');
      expect(formatCacheBytes(1024)).assertEqual('1.0 KB');
      expect(formatCacheBytes(10 * 1024)).assertEqual('10 KB');
      // 9.4 MB：与设置页设计稿 / 原实现的分档一致（<10 保留一位小数）。
      expect(formatCacheBytes(9856614)).assertEqual('9.4 MB');
      expect(formatCacheBytes(12 * 1024 * 1024)).assertEqual('12 MB');
      expect(formatCacheBytes(1536 * 1024 * 1024)).assertEqual('1.5 GB');
    });

    it('clampsInvalidBytesToZero', 0, () => {
      expect(formatCacheBytes(-1)).assertEqual('0 B');
      expect(formatCacheBytes(Number.NaN)).assertEqual('0 B');
      expect(formatCacheBytes(Number.POSITIVE_INFINITY)).assertEqual('0 B');
    });

    it('sumsAllCachesWithSanitizedCounts', 0, () => {
      const image = stats(2048.9, 3.8);
      const lyrics = stats(-10, 2.2);
      const audio = stats(4096.7, 4.1);

      expect(totalCacheBytes(image, lyrics, audio)).assertEqual(6144);
    });

    it('treatsStatsAsEmptyOnlyWhenBothCountsAreZero', 0, () => {
      expect(cacheStatsEmpty(stats(0, 0))).assertTrue();
      expect(cacheStatsEmpty(stats(0, 1))).assertFalse();
      expect(cacheStatsEmpty(stats(1024, 0))).assertFalse();
      expect(cacheStatsEmpty(stats(-1, -1))).assertTrue();
    });
  });
}