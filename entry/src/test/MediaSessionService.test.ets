import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { BiliHttpClient } from '../main/ets/services/BiliHttpClient';
import { MediaControlCommand, MediaControlHandler } from '../main/ets/services/MediaControlState';
import { MediaSessionService } from '../main/ets/services/MediaSessionService';
import {
  metadataFor,
  normalizeMediaQueue,
  playbackStateFor
} from '../main/ets/services/MediaSessionState';
import { MobileTrack } from '../main/ets/types/MobileTypes';
import { testCookieJar } from './TestHttpSupport';

class MediaTestContext {
  readonly cacheDir: string = '/tmp/wisp-music-media-test';
}

class NoopMediaControls implements MediaControlHandler {
  commands: MediaControlCommand[] = [];

  onCommand(command: MediaControlCommand): void {
    this.commands.push(command);
  }
}

function track(label: string, duration: number = 180): MobileTrack {
  return {
    key: `track:${label}`,
    bvid: `BV${label}`,
    aid: 1,
    cid: 2,
    title: `Title ${label}`,
    artist: `Artist ${label}`,
    coverUrl: `https://i0.hdslb.com/${label}.jpg`,
    duration: duration,
    playCount: 0
  };
}

function mediaContext(): common.UIAbilityContext {
  return new MediaTestContext() as Object as common.UIAbilityContext;
}

export default function mediaSessionServiceTest(): void {
  describe('MediaSessionService', () => {
    it('keepsATrackWithoutAQueueButPublishesNoAdjacency', 0, () => {
      const current = track('orphan');
      const view = normalizeMediaQueue(current, 'paused', [], -1);
      const metadata = metadataFor(view.track, 90, view.queue, view.queueIndex);
      const playback = playbackStateFor('paused', 10, 90, 'sequence', view.queueIndex, 1000);

      expect(view.idle).assertFalse();
      expect(view.track?.key).assertEqual(current.key);
      expect(view.queue.length).assertEqual(0);
      expect(view.queueIndex).assertEqual(-1);
      expect(metadata.assetId).assertEqual(current.key);
      expect(metadata.duration).assertEqual(90000);
      expect(metadata.previousAssetId === undefined).assertTrue();
      expect(metadata.nextAssetId === undefined).assertTrue();
      expect(playback.activeItemId === undefined).assertTrue();
      expect(playback.position?.elapsedTime).assertEqual(10000);
    });

    it('selectsTheFirstDuplicateKeyWhenTheQueueIndexIsInvalid', 0, () => {
      const first = track('duplicate');
      const duplicate = track('duplicate');
      const other = track('other');
      const view = normalizeMediaQueue(duplicate, 'playing', [first, duplicate, other], -1);

      expect(view.queueIndex).assertEqual(0);
      expect(view.queue.length).assertEqual(3);
    });

    it('normalizesNonFiniteDurationsAndPositions', 0, () => {
      const current = track('boundary');
      const metadata = metadataFor(current, Number.NaN, [current], 0);
      const negativeMetadata = metadataFor(current, -5, [current], 0);
      const playback = playbackStateFor('playing', Number.NaN, Number.NaN,
        'sequence', 0, Number.NaN);
      const zeroDuration = playbackStateFor('paused', 5, 0, 'sequence', 0, 1000);

      expect(metadata.duration).assertEqual(0);
      expect(negativeMetadata.duration).assertEqual(0);
      expect(playback.duration).assertEqual(0);
      expect(playback.position?.elapsedTime).assertEqual(0);
      expect(playback.position?.updateTime).assertEqual(0);
      expect(zeroDuration.duration).assertEqual(0);
      expect(zeroDuration.position?.elapsedTime).assertEqual(5000);
    });

    it('skipsPlatformWorkBeforeInitializationAndShutdownIsIdempotent', 0, async () => {
      const controls = new NoopMediaControls();
      const service = new MediaSessionService(mediaContext(), controls,
        new BiliHttpClient(testCookieJar()));
      const current = track('lifecycle');

      await service.sync(current, 'playing', 12, 180, 'repeat-all', [current], 0);
      await service.shutdown();
      await service.shutdown();
      await service.sync(current, 'paused', 20, 180, 'sequence', [current], 0);

      expect(controls.commands.length).assertEqual(0);
    });
  });
}