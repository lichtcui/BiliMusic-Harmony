import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x424D;
const TAG = 'WispMusicSleepTimer';

const SLEEP_TIMER_TICK_MS: number = 1000;
const SECONDS_PER_MINUTE: number = 60;
const MILLISECONDS_PER_MINUTE: number = 60000;

/** 定时关闭的固定档位（分钟）；抽屉与 store 校验共用这一份。 */
export const SLEEP_TIMER_PRESETS: number[] = [15, 30, 45, 60, 90];

export interface SleepTimerScheduler {
  now(): number;
  schedule(callback: () => void, delayMs: number): number;
  cancel(timerId: number): void;
}

class PlatformSleepTimerScheduler implements SleepTimerScheduler {
  now(): number {
    return Date.now();
  }

  schedule(callback: () => void, delayMs: number): number {
    return setTimeout((): void => {
      callback();
    }, delayMs);
  }

  cancel(timerId: number): void {
    clearTimeout(timerId);
  }
}

export function isSleepTimerPreset(minutes: number): boolean {
  return SLEEP_TIMER_PRESETS.indexOf(minutes) >= 0;
}

/**
 * 剩余时间展示：不足一分钟也补成 `0:SS`，与播放页的时间格式保持同一读数习惯。
 * 传入的是整秒（store 每 tick 已经向上取整），这里只负责分秒拆分。
 */
export function formatSleepTimerRemaining(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '0:00';
  }
  const totalSeconds = Math.ceil(seconds);
  const minutes = Math.floor(totalSeconds / SECONDS_PER_MINUTE);
  const remainingSeconds = totalSeconds % SECONDS_PER_MINUTE;
  const paddedSeconds = remainingSeconds < 10 ? `0${remainingSeconds}` : `${remainingSeconds}`;
  return `${minutes}:${paddedSeconds}`;
}

/**
 * 播放中的「定时关闭」状态。
 *
 * 计时按**绝对截止时间**推进：每次 tick 都用 `now()` 重算剩余，避免 setTimeout
 * 在后台 / 卡顿后按次数漂移。宿主（`Index`）持有实例，关闭抽屉、返回播放页都不影响；
 * 到点只调用注入的暂停回调，不退出应用，也不持久化到下次启动。
 */
@Observed
export class SleepTimerStore {
  /** 剩余秒数（向上取整）；未开启时为 0。 */
  @Track remainingSeconds: number = 0;
  /** 当前档位（分钟）；0 表示未开启。 */
  @Track activeMinutes: number = 0;

  private readonly onExpire: () => Promise<void>;
  private readonly scheduler: SleepTimerScheduler;
  private deadlineMilliseconds: number = 0;
  private timerId: number = -1;
  private disposed: boolean = false;

  constructor(onExpire: () => Promise<void>,
    scheduler: SleepTimerScheduler = new PlatformSleepTimerScheduler()) {
    this.onExpire = onExpire;
    this.scheduler = scheduler;
  }

  /** 开始或替换定时；只接受预设档位，非法值直接忽略。 */
  start(minutes: number): void {
    if (this.disposed || !isSleepTimerPreset(minutes)) {
      return;
    }
    this.clearTimer();
    this.activeMinutes = minutes;
    this.deadlineMilliseconds = this.scheduler.now() + minutes * MILLISECONDS_PER_MINUTE;
    this.remainingSeconds = minutes * SECONDS_PER_MINUTE;
    this.scheduleTick();
  }

  cancel(): void {
    this.clearTimer();
    this.activeMinutes = 0;
    this.remainingSeconds = 0;
    this.deadlineMilliseconds = 0;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.clearTimer();
    this.activeMinutes = 0;
    this.remainingSeconds = 0;
    this.deadlineMilliseconds = 0;
  }

  private scheduleTick(): void {
    this.timerId = this.scheduler.schedule((): void => {
      this.handleTick();
    }, SLEEP_TIMER_TICK_MS);
  }

  private handleTick(): void {
    this.timerId = -1;
    if (this.disposed || this.activeMinutes <= 0) {
      return;
    }
    const remainingMilliseconds = this.deadlineMilliseconds - this.scheduler.now();
    if (remainingMilliseconds <= 0) {
      this.expire();
      return;
    }
    this.remainingSeconds = Math.ceil(remainingMilliseconds / 1000);
    this.scheduleTick();
  }

  private expire(): void {
    this.activeMinutes = 0;
    this.remainingSeconds = 0;
    this.deadlineMilliseconds = 0;
    this.clearTimer();
    try {
      this.onExpire().catch((_error: Object): void => {
        // 暂停失败由 PlayerStore 统一发布到错误 UI；这里只留一条不含播放数据的诊断。
        hilog.warn(DOMAIN, TAG, 'sleep timer pause failed');
      });
    } catch (_error) {
      hilog.warn(DOMAIN, TAG, 'sleep timer pause failed');
    }
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      this.scheduler.cancel(this.timerId);
      this.timerId = -1;
    }
  }
}
