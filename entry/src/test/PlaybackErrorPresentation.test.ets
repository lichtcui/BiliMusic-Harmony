import { describe, expect, it } from '@ohos/hypium';
import {
  playbackErrorPresentation,
  PlaybackErrorKind
} from '../main/ets/util/PlaybackErrorPresentation';

interface PlaybackErrorCase {
  code: string;
  retryable: boolean;
  kind: PlaybackErrorKind;
}

export default function playbackErrorPresentationTest(): void {
  describe('PlaybackErrorPresentation', () => {
    it('classifiesPlaybackFailuresIntoUserFacingKinds', 0, () => {
      const cases: PlaybackErrorCase[] = [
        { code: 'player.queueEmpty', retryable: true, kind: 'queue-empty' },
        { code: 'player.prepareFailed', retryable: true, kind: 'source' },
        { code: 'player.noAudioStream', retryable: false, kind: 'media' },
        { code: 'http.unavailable', retryable: true, kind: 'network' },
        { code: 'native.error', retryable: false, kind: 'unknown' }
      ];
      for (const item of cases) {
        const presentation = playbackErrorPresentation({
          code: item.code,
          message: 'raw detail must not be rendered',
          retryable: item.retryable
        });
        expect(presentation.kind).assertEqual(item.kind);
        expect(presentation.retryable).assertEqual(
          item.kind === 'queue-empty' ? false : item.retryable
        );
      }
    });

    it('neverCarriesSensitiveErrorTextIntoThePresentation', 0, () => {
      const presentation = playbackErrorPresentation({
        code: 'player.playUrlFailed',
        message: 'https://example.invalid/audio?cookie=secret Authorization: hidden',
        retryable: true
      });
      const serialized = JSON.stringify(presentation).toLowerCase();

      expect(serialized.includes('http://')).assertFalse();
      expect(serialized.includes('https://')).assertFalse();
      expect(serialized.includes('cookie')).assertFalse();
      expect(serialized.includes('authorization')).assertFalse();
      expect(serialized.includes('header')).assertFalse();
    });
  });
}
