import { describe, expect, it } from '@ohos/hypium';
import { avSession } from '@kit.AVSessionKit';
import {
  MEDIA_SESSION_IDLE_ASSET_ID,
  MEDIA_SESSION_QUEUE_ID,
  mediaLoopMode,
  mediaState,
  metadataFor,
  metadataSignatureFor,
  modeFromMedia,
  normalizeMediaQueue,
  playbackStateFor,
  queueItemsFor,
  queueSignatureFor,
  secondsToMilliseconds
} from '../main/ets/services/MediaSessionState';
import { MobileTrack, PlayerMode } from '../main/ets/types/MobileTypes';

function mediaTrack(label: string, title: string = label,
  coverUrl: string = `https://i0.hdslb.com/${label}.jpg`): MobileTrack {
  return {
    key: `track:${label}`,
    bvid: `BV${label}`,
    aid: 1,
    cid: 2,
    title: title,
    artist: `Artist ${label}`,
    coverUrl: coverUrl,
    duration: 180,
    playCount: 3
  };
}

export default function mediaSessionStateTest(): void {
  describe('MediaSessionState', () => {
    it('clearsTrackQueueProgressAndActiveItemWhenIdle', 0, () => {
      const track = mediaTrack('first');
      const view = normalizeMediaQueue(track, 'idle', [track], 0);
      const metadata = metadataFor(view.track, 90, view.queue, view.queueIndex);
      const playback = playbackStateFor('idle', 42, 180, 'repeat-all', 0, 1200);

      expect(view.idle).assertTrue();
      expect(view.track === null).assertTrue();
      expect(view.queue.length).assertEqual(0);
      expect(view.queueIndex).assertEqual(-1);
      expect(metadata.assetId).assertEqual(MEDIA_SESSION_IDLE_ASSET_ID);
      expect(metadata.duration).assertEqual(0);
      expect(metadata.previousAssetId === undefined).assertTrue();
      expect(metadata.nextAssetId === undefined).assertTrue();
      expect(playback.state).assertEqual(avSession.PlaybackState.PLAYBACK_STATE_IDLE);
      expect(playback.duration).assertEqual(0);
      expect(playback.position?.elapsedTime).assertEqual(0);
      expect(playback.position?.updateTime).assertEqual(1200);
      expect(playback.activeItemId === undefined).assertTrue();
      expect(queueItemsFor(view.queue).length).assertEqual(0);
    });

    it('repairsInvalidQueueIndexesByTrackKeyOrReturnsNoSelection', 0, () => {
      const first = mediaTrack('first');
      const second = mediaTrack('second');
      const third = mediaTrack('third');
      const mismatched = normalizeMediaQueue(second, 'paused', [first, second, third], 0);
      const fractional = normalizeMediaQueue(second, 'paused', [first, second, third], 1.5);
      const outOfRange = normalizeMediaQueue(second, 'paused', [first, second, third], 99);
      const missing = normalizeMediaQueue(mediaTrack('missing'), 'paused',
        [first, second, third], 0);

      expect(mismatched.queueIndex).assertEqual(1);
      expect(fractional.queueIndex).assertEqual(1);
      expect(outOfRange.queueIndex).assertEqual(1);
      expect(missing.queueIndex).assertEqual(-1);
    });

    it('capsNormalizedAndPublishedQueuesAtFiveHundredItems', 0, () => {
      const queue: MobileTrack[] = [];
      for (let index = 0; index < 505; index++) {
        queue.push(mediaTrack(`track-${index}`));
      }

      const view = normalizeMediaQueue(queue[499], 'playing', queue, 499);
      const excluded = normalizeMediaQueue(queue[504], 'playing', queue, 504);

      expect(view.queue.length).assertEqual(500);
      expect(view.queueIndex).assertEqual(499);
      expect(queueItemsFor(view.queue).length).assertEqual(500);
      expect(excluded.queue.length).assertEqual(500);
      expect(excluded.queueIndex).assertEqual(-1);
    });

    it('changesSignaturesWhenTrackMetadataOrCoverChanges', 0, () => {
      const first = mediaTrack('first');
      const second = mediaTrack('second');
      const renamed = mediaTrack('first', 'Renamed', first.coverUrl);
      const recovered = mediaTrack('first', first.title, 'https://i0.hdslb.com/recovered.jpg');
      const baseQueueSignature = queueSignatureFor(first.key, [first, second]);
      const metadata = metadataFor(first, 180, [first, second], 0);
      const baseMetadataSignature = metadataSignatureFor(metadata, 0);

      expect(queueSignatureFor(first.key, [renamed, second]) === baseQueueSignature).assertFalse();
      expect(queueSignatureFor(first.key, [recovered, second]) === baseQueueSignature).assertFalse();
      expect(metadataSignatureFor(metadataFor(renamed, 180, [first, second], 0), 0) ===
        baseMetadataSignature).assertFalse();
      expect(metadataSignatureFor(metadata, 1) === baseMetadataSignature).assertFalse();
    });

    it('publishesAdjacentAssetIdsAndMillisecondMetadata', 0, () => {
      const first = mediaTrack('first');
      const second = mediaTrack('second');
      const third = mediaTrack('third');
      const current = metadataFor(second, 181.25, [first, second, third], 1);
      const head = metadataFor(first, 180, [first, second, third], 0);
      const tail = metadataFor(third, 180, [first, second, third], 2);
      const invalid = metadataFor(second, 180, [first, second, third], 99);

      expect(current.assetId).assertEqual(second.key);
      expect(current.title).assertEqual(second.title);
      expect(current.artist).assertEqual(second.artist);
      expect(current.duration).assertEqual(181250);
      expect(current.avQueueId).assertEqual(MEDIA_SESSION_QUEUE_ID);
      expect(current.previousAssetId).assertEqual(first.key);
      expect(current.nextAssetId).assertEqual(third.key);
      expect(head.previousAssetId === undefined).assertTrue();
      expect(head.nextAssetId).assertEqual(second.key);
      expect(tail.previousAssetId).assertEqual(second.key);
      expect(tail.nextAssetId === undefined).assertTrue();
      expect(invalid.previousAssetId === undefined).assertTrue();
      expect(invalid.nextAssetId === undefined).assertTrue();
    });

    it('publishesMillisecondPlaybackStateAndClampsPosition', 0, () => {
      const playing = playbackStateFor('playing', 12.3456, 180, 'shuffle', 2, 1234.6);
      const beyondEnd = playbackStateFor('paused', 240, 180, 'sequence', 0, 5000);
      const negative = playbackStateFor('loading', -3, 180, 'repeat-one', -1, 5000);

      expect(playing.state).assertEqual(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      expect(playing.position?.elapsedTime).assertEqual(12346);
      expect(playing.position?.updateTime).assertEqual(1235);
      expect(playing.duration).assertEqual(180000);
      expect(playing.activeItemId).assertEqual(2);
      expect(playing.loopMode).assertEqual(avSession.LoopMode.LOOP_MODE_SHUFFLE);
      expect(beyondEnd.state).assertEqual(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
      expect(beyondEnd.position?.elapsedTime).assertEqual(180000);
      expect(negative.position?.elapsedTime).assertEqual(0);
      expect(negative.activeItemId === undefined).assertTrue();
      expect(secondsToMilliseconds(1.2345)).assertEqual(1235);
    });

    it('onlyPublishesWhitelistedHttpsCoverImages', 0, () => {
      const allowed = mediaTrack('allowed', 'Allowed', 'https://i0.hdslb.com/allowed.jpg');
      const nonBili = mediaTrack('evil', 'Evil', 'https://evil.example/cover.jpg');
      const insecure = mediaTrack('http', 'Http', 'http://i0.hdslb.com/cover.jpg');
      const items = queueItemsFor([allowed, nonBili, insecure]);

      expect(items[0].description?.mediaImage).assertEqual(allowed.coverUrl);
      expect(items[1].description?.mediaImage === undefined).assertTrue();
      expect(items[2].description?.mediaImage === undefined).assertTrue();
    });

    it('mapsPlaybackStatesAndRoundTripsLoopModes', 0, () => {
      const modes: PlayerMode[] = ['sequence', 'repeat-one', 'repeat-all', 'shuffle'];

      expect(mediaState('playing')).assertEqual(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      expect(mediaState('paused')).assertEqual(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
      expect(mediaState('loading')).assertEqual(avSession.PlaybackState.PLAYBACK_STATE_PREPARE);
      expect(mediaState('error')).assertEqual(avSession.PlaybackState.PLAYBACK_STATE_STOP);
      expect(mediaState('idle')).assertEqual(avSession.PlaybackState.PLAYBACK_STATE_IDLE);
      for (const mode of modes) {
        expect(modeFromMedia(mediaLoopMode(mode))).assertEqual(mode);
      }
      expect(modeFromMedia(avSession.LoopMode.LOOP_MODE_CUSTOM)).assertEqual('sequence');
    });
  });
}
