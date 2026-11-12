import { describe, expect, it } from '@ohos/hypium';
import {
  AUDIO_CACHE_MAX_BYTES,
  AudioCacheFile,
  audioCacheEvictions
} from '../main/ets/services/AudioCachePolicy';

function file(path: string, bytes: number, modifiedAt: number): AudioCacheFile {
  return {
    path: path,
    bytes: bytes,
    modifiedAt: modifiedAt
  };
}

export default function audioCachePolicyTest(): void {
  describe('AudioCachePolicy', () => {
    it('keepsEveryFileWhenTheTotalIsWithinTheLimit', 0, () => {
      const files = [
        file('/cache/audio-v1-a.m4s', 400, 1),
        file('/cache/audio-v1-b.m4s', 200, 2)
      ];

      expect(audioCacheEvictions(files, 600).length).assertEqual(0);
    });

    it('evictsOldestFilesFirstUntilTheTotalFits', 0, () => {
      const files = [
        file('/cache/audio-v1-new.m4s', 300, 30),
        file('/cache/audio-v1-old.m4s', 400, 10),
        file('/cache/audio-v1-mid.m4s', 300, 20)
      ];

      const evictions = audioCacheEvictions(files, 500);

      expect(evictions.length).assertEqual(2);
      expect(evictions[0]).assertEqual('/cache/audio-v1-old.m4s');
      expect(evictions[1]).assertEqual('/cache/audio-v1-mid.m4s');
    });

    it('neverEvictsTheFileThatWasJustWritten', 0, () => {
      const keep = '/cache/audio-v1-keep.m4s';
      const files = [
        file(keep, 500, 1),
        file('/cache/audio-v1-other.m4s', 200, 2),
        file('/cache/audio-v1-third.m4s', 100, 3)
      ];

      const evictions = audioCacheEvictions(files, 400, keep);

      expect(evictions.length).assertEqual(2);
      expect(evictions[0]).assertEqual('/cache/audio-v1-other.m4s');
      expect(evictions[1]).assertEqual('/cache/audio-v1-third.m4s');
    });

    it('clampsInvalidSizesInsteadOfOverEvicting', 0, () => {
      const files = [
        file('/cache/audio-v1-negative.m4s', -100, Number.NaN),
        file('/cache/audio-v1-good.m4s', 5, 2)
      ];

      expect(audioCacheEvictions(files, 10).length).assertEqual(0);
      expect(AUDIO_CACHE_MAX_BYTES).assertEqual(512 * 1024 * 1024);
    });
  });
}