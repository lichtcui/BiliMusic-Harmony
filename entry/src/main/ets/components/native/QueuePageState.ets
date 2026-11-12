import {
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
} from '../../state/PlayerStore';
import {
  AppError,
  MobileTrack,
  PlaybackStatus
} from '../../types/MobileTypes';

export type QueuePageBusyAction = '' | 'switch' | 'remove' | 'clear';

@Observed
export class QueuePageState implements PlayerStoreListener {
  @Track queue: MobileTrack[] = [];
  @Track queueIndex: number = -1;
  @Track status: PlaybackStatus = 'idle';
  @Track error: AppError | null = null;
  @Track busyAction: QueuePageBusyAction = '';
  @Track busyIndex: number = -1;

  private store: PlayerStore | null = null;
  private disposed: boolean = false;

  constructor(store: PlayerStore) {
    this.store = store;
    this.applyState(store.snapshot);
    this.error = cloneError(store.error);
  }

  /**
   * Subscribes this instance to the player store. See PlayerPageState#attach for why this cannot
   * happen in the constructor (@Observed proxies the object only after the constructor returns).
   */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.store?.subscribe(this);
  }

  onState(snapshot: PlayerViewSnapshot): void {
    if (this.disposed) {
      return;
    }
    this.applyState(snapshot);
    const store = this.store;
    if (store !== null) {
      this.error = cloneError(store.error);
    }
  }

  onProgress(_progress: PlayerProgressSnapshot): void {
  }

  onError(error: AppError): void {
    if (this.disposed) {
      return;
    }
    const store = this.store;
    if (store !== null) {
      this.applyState(store.snapshot);
    }
    this.error = cloneError(error) as AppError;
  }

  /** 切到指定队列项；返回是否切换成功，供整页队列决定是否回到播放页。 */
  async switchTo(index: number): Promise<boolean> {
    if (!this.canSwitchTo(index)) {
      return false;
    }
    const store = this.store;
    if (store === null) {
      return false;
    }
    this.busyAction = 'switch';
    this.busyIndex = index;
    try {
      await store.play(index);
      return true;
    } catch (error) {
      // PlayerStore publishes the sanitized failure state used by the page.
      return false;
    } finally {
      this.finishMutation('switch');
    }
  }

  async removeAt(index: number): Promise<void> {
    if (!this.canRemoveAt(index)) {
      return;
    }
    const store = this.store;
    if (store === null) {
      return;
    }
    this.busyAction = 'remove';
    this.busyIndex = index;
    try {
      await store.removeFromQueue(index);
    } catch (error) {
      // PlayerStore publishes the sanitized failure state used by the page.
    } finally {
      this.finishMutation('remove');
    }
  }

  async clear(): Promise<void> {
    if (!this.canClear()) {
      return;
    }
    const store = this.store;
    if (store === null) {
      return;
    }
    this.busyAction = 'clear';
    this.busyIndex = -1;
    try {
      await store.clearQueue();
    } catch (error) {
      // PlayerStore publishes the sanitized failure state used by the page.
    } finally {
      this.finishMutation('clear');
    }
  }

  isCurrent(index: number): boolean {
    return index >= 0 && index === this.queueIndex;
  }

  isBusy(): boolean {
    return this.busyAction !== '';
  }

  canSwitchTo(index: number): boolean {
    return !this.isBusy() && index >= 0 && index < this.queue.length && index !== this.queueIndex;
  }

  canRemoveAt(index: number): boolean {
    return !this.isBusy() && index >= 0 && index < this.queue.length;
  }

  canClear(): boolean {
    return !this.isBusy() && this.queue.length > 0;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.store?.unsubscribe(this);
    this.store = null;
  }

  private finishMutation(action: QueuePageBusyAction): void {
    if (this.busyAction === action) {
      this.busyAction = '';
      this.busyIndex = -1;
    }
  }

  private applyState(snapshot: PlayerViewSnapshot): void {
    const queue = cloneQueue(snapshot.queue);
    const queueIndex = safeInteger(snapshot.queueIndex, -1);
    this.queue = queue;
    this.queueIndex = queueIndex >= 0 && queueIndex < queue.length ? queueIndex : -1;
    this.status = snapshot.status;
  }
}

function safeInteger(value: number, fallback: number): number {
  return Number.isFinite(value) ? Math.floor(value) : fallback;
}

function cloneTrack(track: MobileTrack): MobileTrack {
  return {
    key: track.key,
    bvid: track.bvid,
    aid: track.aid,
    cid: track.cid,
    title: track.title,
    artist: track.artist,
    coverUrl: track.coverUrl,
    duration: track.duration,
    playCount: track.playCount
  };
}

function cloneQueue(queue: MobileTrack[]): MobileTrack[] {
  return queue.map((track: MobileTrack): MobileTrack => cloneTrack(track));
}

function cloneError(error: AppError | null): AppError | null {
  if (error === null) {
    return null;
  }
  return {
    code: error.code,
    message: error.message,
    retryable: error.retryable
  };
}
