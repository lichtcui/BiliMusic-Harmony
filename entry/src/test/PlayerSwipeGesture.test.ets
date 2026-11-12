import { describe, expect, it } from '@ohos/hypium';
import {
  dampPlayerSwipeOffset,
  playerSwipeEnterOffset,
  resolvePlayerSwipe
} from '../main/ets/components/native/PlayerSwipeGesture';

const RATIO: number = 0.14;
const VELOCITY: number = 520;
const HEIGHT: number = 800;

export default function playerSwipeGestureTest(): void {
  describe('PlayerSwipeGesture', () => {
    it('swipesUpToTheNextTrack', 0, () => {
      const direction = resolvePlayerSwipe({
        offsetY: -160,
        velocityY: 0,
        stageHeight: HEIGHT,
        ratio: RATIO,
        velocityThreshold: VELOCITY
      });

      expect(direction).assertEqual('next');
    });

    it('swipesDownToThePreviousTrack', 0, () => {
      const direction = resolvePlayerSwipe({
        offsetY: 160,
        velocityY: 0,
        stageHeight: HEIGHT,
        ratio: RATIO,
        velocityThreshold: VELOCITY
      });

      expect(direction).assertEqual('previous');
    });

    it('springsBackBelowTheDistanceThreshold', 0, () => {
      const direction = resolvePlayerSwipe({
        offsetY: -40,
        velocityY: 0,
        stageHeight: HEIGHT,
        ratio: RATIO,
        velocityThreshold: VELOCITY
      });

      expect(direction).assertEqual('');
    });

    it('commitsOnAFastFlickEvenWhenShort', 0, () => {
      const direction = resolvePlayerSwipe({
        offsetY: -40,
        velocityY: -900,
        stageHeight: HEIGHT,
        ratio: RATIO,
        velocityThreshold: VELOCITY
      });

      expect(direction).assertEqual('next');
    });

    it('ignoresTinyJitter', 0, () => {
      const direction = resolvePlayerSwipe({
        offsetY: -3,
        velocityY: -1200,
        stageHeight: HEIGHT,
        ratio: RATIO,
        velocityThreshold: VELOCITY
      });

      expect(direction).assertEqual('');
    });

    it('neverSwipesWithoutAMeasuredStage', 0, () => {
      const direction = resolvePlayerSwipe({
        offsetY: -600,
        velocityY: -2000,
        stageHeight: 0,
        ratio: RATIO,
        velocityThreshold: VELOCITY
      });

      expect(direction).assertEqual('');
    });

    it('dampsTheOffsetPastTheDragLimit', 0, () => {
      const withinLimit = dampPlayerSwipeOffset(-100, HEIGHT);
      const pastLimit = dampPlayerSwipeOffset(-800, HEIGHT);

      expect(withinLimit).assertEqual(-100);
      expect(pastLimit < 0).assertTrue();
      expect(Math.abs(pastLimit) < 800).assertTrue();
      expect(Math.abs(pastLimit) > HEIGHT * 0.35).assertTrue();
    });

    it('entersFromTheSideItsDirectionCameFrom', 0, () => {
      expect(playerSwipeEnterOffset('next', HEIGHT)).assertEqual(HEIGHT);
      expect(playerSwipeEnterOffset('previous', HEIGHT)).assertEqual(-HEIGHT);
      expect(playerSwipeEnterOffset('', HEIGHT)).assertEqual(0);
    });
  });
}
