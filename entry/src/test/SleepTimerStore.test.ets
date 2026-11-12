import { describe, expect, it } from '@ohos/hypium';
import {
  formatSleepTimerRemaining,
  isSleepTimerPreset,
  SleepTimerScheduler,
  SleepTimerStore,
  SLEEP_TIMER_PRESETS
} from '../main/ets/state/SleepTimerStore';

class FakeSleepTimer {
  readonly id: number;
  readonly callback: () => void;
  readonly delayMs: number;
  cancelled: boolean = false;
  ran: boolean = false;

  constructor(id: number, callback: () => void, delayMs: number) {
    this.id = id;
    this.callback = callback;
    this.delayMs = delayMs;
  }
}

class FakeSleepTimerScheduler implements SleepTimerScheduler {
  nowMs: number = 1000;
  readonly timers: FakeSleepTimer[] = [];
  private nextId: number = 1;

  now(): number {
    return this.nowMs;
  }

  schedule(callback: () => void, delayMs: number): number {
    const timer = new FakeSleepTimer(this.nextId++, callback, delayMs);
    this.timers.push(timer);
    return timer.id;
  }

  cancel(timerId: number): void {
    for (const timer of this.timers) {
      if (timer.id === timerId) {
        timer.cancelled = true;
      }
    }
  }

  advance(milliseconds: number): void {
    this.nowMs += milliseconds;
  }

  pendingCount(): number {
    let count = 0;
    for (const timer of this.timers) {
      if (!timer.cancelled && !timer.ran) {
        count++;
      }
    }
    return count;
  }

  runNext(): void {
    for (const timer of this.timers) {
      if (!timer.ran && !timer.cancelled) {
        timer.ran = true;
        timer.callback();
        return;
      }
    }
    throw new Error('No matching sleep timer');
  }
}

export default function sleepTimerStoreTest(): void {
  describe('SleepTimerStore', () => {
    it('startsAPresetWithAFullRemainingWindow', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      let pauseCalls = 0;
      const store = new SleepTimerStore((): Promise<void> => {
        pauseCalls += 1;
        return Promise.resolve();
      }, scheduler);

      store.start(30);

      expect(store.activeMinutes).assertEqual(30);
      expect(store.remainingSeconds).assertEqual(30 * 60);
      expect(scheduler.pendingCount()).assertEqual(1);
      expect(scheduler.timers[0].delayMs).assertEqual(1000);
      expect(pauseCalls).assertEqual(0);
      store.dispose();
    });

    it('recomputesRemainingFromTheDeadlineOnEachTick', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      const store = new SleepTimerStore((): Promise<void> => Promise.resolve(), scheduler);
      store.start(15);

      scheduler.advance(1000);
      scheduler.runNext();

      // 15 分钟 - 已过 1 秒；剩余按秒向上取整。
      expect(store.remainingSeconds).assertEqual(15 * 60 - 1);
      expect(store.activeMinutes).assertEqual(15);
      expect(scheduler.pendingCount()).assertEqual(1);
      store.dispose();
    });

    it('replacesAnActiveTimerWithTheNewPreset', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      const store = new SleepTimerStore((): Promise<void> => Promise.resolve(), scheduler);
      store.start(15);
      store.start(90);

      expect(store.activeMinutes).assertEqual(90);
      expect(store.remainingSeconds).assertEqual(90 * 60);
      expect(scheduler.pendingCount()).assertEqual(1);
      expect(scheduler.timers[0].cancelled).assertTrue();
      store.dispose();
    });

    it('cancelsWithoutPausingPlayback', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      let pauseCalls = 0;
      const store = new SleepTimerStore((): Promise<void> => {
        pauseCalls += 1;
        return Promise.resolve();
      }, scheduler);
      store.start(15);
      store.cancel();

      expect(store.activeMinutes).assertEqual(0);
      expect(store.remainingSeconds).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(0);
      expect(pauseCalls).assertEqual(0);
      store.dispose();
    });

    it('pausesExactlyOnceWhenTheDeadlineArrives', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      let pauseCalls = 0;
      const store = new SleepTimerStore((): Promise<void> => {
        pauseCalls += 1;
        return Promise.resolve();
      }, scheduler);
      store.start(15);

      scheduler.advance(15 * 60000);
      scheduler.runNext();

      expect(pauseCalls).assertEqual(1);
      expect(store.activeMinutes).assertEqual(0);
      expect(store.remainingSeconds).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(0);
      store.dispose();
    });

    it('doesNotPauseWhenCancelledBeforeTheDeadline', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      let pauseCalls = 0;
      const store = new SleepTimerStore((): Promise<void> => {
        pauseCalls += 1;
        return Promise.resolve();
      }, scheduler);
      store.start(15);
      store.cancel();

      scheduler.advance(15 * 60000);
      // 已取消的 timer 不会再被调度；即使伪造触发也不该pause。
      expect(scheduler.pendingCount()).assertEqual(0);
      expect(pauseCalls).assertEqual(0);
      store.dispose();
    });

    it('disposesTimersAndIgnoresLaterStarts', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      const store = new SleepTimerStore((): Promise<void> => Promise.resolve(), scheduler);
      store.start(45);
      store.dispose();

      expect(store.activeMinutes).assertEqual(0);
      expect(store.remainingSeconds).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(0);

      store.start(15);
      expect(store.activeMinutes).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(0);
    });

    it('rejectsDurationsOutsideThePresetList', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      const store = new SleepTimerStore((): Promise<void> => Promise.resolve(), scheduler);

      store.start(20);

      expect(store.activeMinutes).assertEqual(0);
      expect(store.remainingSeconds).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(0);
      store.dispose();
    });

    it('exposesTheAgreedPresets', 0, () => {
      expect(SLEEP_TIMER_PRESETS.length).assertEqual(5);
      expect(isSleepTimerPreset(15)).assertTrue();
      expect(isSleepTimerPreset(90)).assertTrue();
      expect(isSleepTimerPreset(20)).assertFalse();
    });

    it('formatsRemainingTimeAsMinutesAndSeconds', 0, () => {
      expect(formatSleepTimerRemaining(0)).assertEqual('0:00');
      expect(formatSleepTimerRemaining(59)).assertEqual('0:59');
      expect(formatSleepTimerRemaining(60)).assertEqual('1:00');
      expect(formatSleepTimerRemaining(599)).assertEqual('9:59');
      expect(formatSleepTimerRemaining(3600)).assertEqual('60:00');
      expect(formatSleepTimerRemaining(Number.NaN)).assertEqual('0:00');
    });

    it('swallowsPauseFailuresAfterExpiry', 0, () => {
      const scheduler = new FakeSleepTimerScheduler();
      const store = new SleepTimerStore((): Promise<void> => Promise.reject(new Error('pause failed')), scheduler);
      store.start(15);

      scheduler.advance(15 * 60000);
      scheduler.runNext();

      expect(store.activeMinutes).assertEqual(0);
      expect(store.remainingSeconds).assertEqual(0);
      store.dispose();
    });
  });
}
