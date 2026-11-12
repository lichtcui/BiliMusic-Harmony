import { describe, expect, it } from '@ohos/hypium';
import {
  OverlayAnimator,
  OverlayMotion
} from '../main/ets/components/native/OverlayMotion';

/** 立即执行 apply 与 onFinish 的动画器，用来断言动画结束后的最终状态。 */
function immediateAnimator(): OverlayAnimator {
  return (apply: () => void, onFinish?: () => void): void => {
    apply();
    if (onFinish !== undefined) {
      onFinish();
    }
  };
}

/** 只记录 onFinish 的动画器，用来模拟「关闭动画还没播完」的中间态。 */
function deferredAnimator(pending: Array<() => void>): OverlayAnimator {
  return (apply: () => void, onFinish?: () => void): void => {
    apply();
    if (onFinish !== undefined) {
      pending.push(onFinish);
    }
  };
}

export default function overlayMotionTest(): void {
  describe('OverlayMotion', () => {
    it('mountsOffscreenThenSlidesInOnEnter', 0, () => {
      const motion = new OverlayMotion();
      const animate = immediateAnimator();

      motion.open(800, animate);
      expect(motion.visible).assertTrue();
      expect(motion.offset).assertEqual(800);
      expect(motion.scrimAlpha).assertEqual(0);

      motion.enter(animate);
      expect(motion.visible).assertTrue();
      expect(motion.offset).assertEqual(0);
      expect(motion.scrimAlpha).assertEqual(1);
    });

    it('staysMountedUntilTheCloseAnimationFinishes', 0, () => {
      const motion = new OverlayMotion();
      const pending: Array<() => void> = [];
      const animate = deferredAnimator(pending);
      motion.open(800, immediateAnimator());
      motion.enter(immediateAnimator());

      motion.close(800, animate);
      // 动画进行中：面板已滑出但还没卸载。
      expect(motion.visible).assertTrue();
      expect(motion.offset).assertEqual(800);
      expect(motion.scrimAlpha).assertEqual(0);

      pending[0]();
      expect(motion.visible).assertFalse();
      expect(motion.offset).assertEqual(0);
      expect(motion.scrimAlpha).assertEqual(1);
    });

    it('runsTheCloseSideEffectOnlyAfterUnmounting', 0, () => {
      const motion = new OverlayMotion();
      const pending: Array<() => void> = [];
      const animate = deferredAnimator(pending);
      motion.open(800, immediateAnimator());
      motion.enter(immediateAnimator());

      let closed = 0;
      motion.close(800, animate, (): void => {
        closed += 1;
        expect(motion.visible).assertFalse();
      });
      expect(closed).assertEqual(0);
      pending[0]();
      expect(closed).assertEqual(1);
    });

    it('dropsStaleCloseCallbacksWhenReopenedMidAnimation', 0, () => {
      const motion = new OverlayMotion();
      const pending: Array<() => void> = [];
      const animate = deferredAnimator(pending);
      motion.open(800, immediateAnimator());
      motion.enter(immediateAnimator());

      motion.close(800, animate);
      // 关闭动画还没结束就重新打开：不能重新挂载，直接把面板滑回来。
      motion.open(800, immediateAnimator());
      expect(motion.visible).assertTrue();
      expect(motion.offset).assertEqual(0);

      // 旧关闭动画此时才结束，世代戳已变，不允许卸载。
      pending[0]();
      expect(motion.visible).assertTrue();
      expect(motion.offset).assertEqual(0);

      motion.close(800, animate);
      pending[1]();
      expect(motion.visible).assertFalse();
    });

    it('enterIsIgnoredWhileUnmounted', 0, () => {
      const motion = new OverlayMotion();
      let applied = 0;
      motion.enter((): void => {
        applied += 1;
      });
      expect(applied).assertEqual(0);
      expect(motion.visible).assertFalse();
    });

    it('hideNowUnmountsWithoutAnimating', 0, () => {
      const motion = new OverlayMotion();
      motion.open(800, immediateAnimator());
      motion.enter(immediateAnimator());

      let applied = 0;
      motion.hideNow();
      expect(motion.visible).assertFalse();
      expect(motion.offset).assertEqual(0);
      expect(motion.scrimAlpha).assertEqual(1);
      expect(applied).assertEqual(0);
    });
  });
}