export interface MediaCleanupHooks {
  stopProgress(): void;
  drainCommands(): Promise<void>;
  flushPosition(): void;
  stopSession(): Promise<void>;
  releasePlayer(): Promise<void>;
}

export class MediaCleanupSequence {
  private shutdownPromise: Promise<void> | null = null;

  run(hooks: MediaCleanupHooks): Promise<void> {
    if (this.shutdownPromise !== null) {
      return this.shutdownPromise;
    }
    const shutdown = this.runOnce(hooks);
    this.shutdownPromise = shutdown;
    return shutdown;
  }

  private async runOnce(hooks: MediaCleanupHooks): Promise<void> {
    let firstError: Error | null = null;
    try {
      hooks.stopProgress();
    } catch (error) {
      firstError = error instanceof Error ? error : new Error('media cleanup failed');
    }
    try {
      await hooks.drainCommands();
    } catch (error) {
      if (firstError === null) {
        firstError = error instanceof Error ? error : new Error('media cleanup failed');
      }
    }
    try {
      // An in-flight command may restart progress while the queue is draining.
      hooks.stopProgress();
    } catch (error) {
      if (firstError === null) {
        firstError = error instanceof Error ? error : new Error('media cleanup failed');
      }
    }
    try {
      hooks.flushPosition();
    } catch (error) {
      if (firstError === null) {
        firstError = error instanceof Error ? error : new Error('media cleanup failed');
      }
    }
    try {
      await hooks.stopSession();
    } catch (error) {
      if (firstError === null) {
        firstError = error instanceof Error ? error : new Error('media cleanup failed');
      }
    }
    try {
      await hooks.releasePlayer();
    } catch (error) {
      if (firstError === null) {
        firstError = error instanceof Error ? error : new Error('media cleanup failed');
      }
    }
    if (firstError !== null) {
      throw firstError;
    }
  }
}

export interface AudioBackgroundTask {
  start(): Promise<void>;
  stop(): Promise<void>;
}

export class AudioBackgroundLease {
  private readonly task: AudioBackgroundTask;
  private startPromise: Promise<void> | null = null;
  private stopPromise: Promise<void> | null = null;
  private active: boolean = false;
  private stopping: boolean = false;

  constructor(task: AudioBackgroundTask) {
    this.task = task;
  }

  start(): Promise<void> {
    if (this.stopping) {
      return Promise.resolve();
    }
    if (this.startPromise !== null) {
      return this.startPromise;
    }
    if (this.active) {
      return Promise.resolve();
    }
    const starting = this.startOnce();
    this.startPromise = starting;
    return starting;
  }

  stop(): Promise<void> {
    if (this.stopPromise !== null) {
      return this.stopPromise;
    }
    this.stopping = true;
    const stopping = this.stopOnce();
    this.stopPromise = stopping;
    return stopping;
  }

  private async startOnce(): Promise<void> {
    try {
      await this.task.start();
      this.active = true;
    } finally {
      this.startPromise = null;
    }
  }

  private async stopOnce(): Promise<void> {
    const starting = this.startPromise;
    if (starting !== null) {
      try {
        await starting;
      } catch (_error) {
        // A failed start has no background task to stop.
      }
    }
    if (!this.active) {
      return;
    }
    this.active = false;
    await this.task.stop();
  }
}
