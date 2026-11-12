import { describe, expect, it } from '@ohos/hypium';
import {
  AudioBackgroundLease,
  AudioBackgroundTask,
  MediaCleanupHooks,
  MediaCleanupSequence
} from '../main/ets/services/MediaLifecycleState';

class RecordingCleanupHooks implements MediaCleanupHooks {
  readonly calls: string[] = [];
  failProgress: boolean = false;
  failSession: boolean = false;
  failRelease: boolean = false;
  restartProgressDuringDrain: boolean = false;
  progressActive: boolean = false;

  stopProgress(): void {
    this.calls.push('stopProgress');
    this.progressActive = false;
    if (this.failProgress) {
      throw new Error('stop-progress');
    }
  }

  drainCommands(): Promise<void> {
    this.calls.push('drainCommands');
    if (this.restartProgressDuringDrain) {
      this.progressActive = true;
    }
    return Promise.resolve();
  }

  flushPosition(): void {
    this.calls.push('flushPosition');
  }

  stopSession(): Promise<void> {
    this.calls.push('stopSession');
    if (this.failSession) {
      return Promise.reject(new Error('stop-session'));
    }
    return Promise.resolve();
  }

  releasePlayer(): Promise<void> {
    this.calls.push('releasePlayer');
    if (this.failRelease) {
      return Promise.reject(new Error('release-player'));
    }
    return Promise.resolve();
  }
}

class ControlledAudioBackgroundTask implements AudioBackgroundTask {
  startCount: number = 0;
  stopCount: number = 0;
  private resolveStartCallback: (() => void) | null = null;
  private rejectStartCallback: ((error: Object) => void) | null = null;

  start(): Promise<void> {
    this.startCount++;
    return new Promise<void>((resolve, reject) => {
      this.resolveStartCallback = resolve;
      this.rejectStartCallback = reject;
    });
  }

  stop(): Promise<void> {
    this.stopCount++;
    return Promise.resolve();
  }

  finishStart(): void {
    const callback = this.resolveStartCallback;
    this.resolveStartCallback = null;
    this.rejectStartCallback = null;
    if (callback !== null) {
      callback();
    }
  }

  failStart(error: Object): void {
    const callback = this.rejectStartCallback;
    this.resolveStartCallback = null;
    this.rejectStartCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

export default function mediaLifecycleStateTest(): void {
  describe('MediaLifecycleState', () => {
    it('runsCleanupInLifecycleOrderAndReusesTheShutdownPromise', 0, async () => {
      const cleanup = new MediaCleanupSequence();
      const hooks = new RecordingCleanupHooks();

      const first = cleanup.run(hooks);
      const second = cleanup.run(hooks);
      expect(first === second).assertTrue();
      await Promise.all([first, second]);

      expect(hooks.calls.join(',')).assertEqual(
        'stopProgress,drainCommands,stopProgress,flushPosition,stopSession,releasePlayer');
    });

    it('continuesCleanupAfterFailuresAndRethrowsTheFirstError', 0, async () => {
      const cleanup = new MediaCleanupSequence();
      const hooks = new RecordingCleanupHooks();
      hooks.failProgress = true;
      hooks.failSession = true;
      hooks.failRelease = true;
      let failure = '';

      try {
        await cleanup.run(hooks);
      } catch (error) {
        failure = (error as Error).message;
      }

      expect(failure).assertEqual('stop-progress');
      expect(hooks.calls.join(',')).assertEqual(
        'stopProgress,drainCommands,stopProgress,flushPosition,stopSession,releasePlayer');
    });

    it('stopsProgressAgainAfterACommandRestartsItDuringDrain', 0, async () => {
      const cleanup = new MediaCleanupSequence();
      const hooks = new RecordingCleanupHooks();
      hooks.restartProgressDuringDrain = true;

      await cleanup.run(hooks);

      expect(hooks.progressActive).assertFalse();
      expect(hooks.calls.join(',')).assertEqual(
        'stopProgress,drainCommands,stopProgress,flushPosition,stopSession,releasePlayer');
    });

    it('serializesBackgroundStartsAndStopsDuringAnActiveStart', 0, async () => {
      const task = new ControlledAudioBackgroundTask();
      const lease = new AudioBackgroundLease(task);

      const firstStart = lease.start();
      const duplicateStart = lease.start();
      expect(firstStart === duplicateStart).assertTrue();
      expect(task.startCount).assertEqual(1);

      const firstStop = lease.stop();
      const duplicateStop = lease.stop();
      expect(firstStop === duplicateStop).assertTrue();
      expect(task.stopCount).assertEqual(0);

      task.finishStart();
      await Promise.all([firstStart, duplicateStart, firstStop, duplicateStop]);
      expect(task.startCount).assertEqual(1);
      expect(task.stopCount).assertEqual(1);

      await lease.stop();
      await lease.start();
      expect(task.startCount).assertEqual(1);
      expect(task.stopCount).assertEqual(1);
    });
  });
}
