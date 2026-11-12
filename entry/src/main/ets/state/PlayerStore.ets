import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AppError,
  AudioQuality,
  MobileTrack,
  PlaybackState,
  PlaybackStatus,
  PlaybackErrorContext,
  PlayerMode,
  PlayerSessionSnapshot
} from '../types/MobileTypes';
import { NativeError, toAppError } from '../util/Errors';
import { placeTrackAtQueueHead, PLAYER_QUEUE_LIMIT } from '../services/PlayerQueue';

const DOMAIN = 0x424D;
const TAG = 'WispMusicPlayerStore';
const SAFE_PLAYER_ERROR_MESSAGE = '播放操作失败，请稍后重试。';

export const PLAYER_PROGRESS_INTERVAL_MS: number = 250;

export interface PlayerViewSnapshot {
  status: PlaybackStatus;
  track: MobileTrack | null;
  duration: number;
  mode: PlayerMode;
  queue: MobileTrack[];
  queueIndex: number;
}

export interface PlayerProgressSnapshot {
  position: number;
  duration: number;
}

export interface PlayerQueueRequestSnapshot {
  generation: number;
  trackKey: string;
  startIndex: number;
  queueLength: number;
}

export interface PlayerReadSnapshot extends PlayerViewSnapshot {
  position: number;
  error: AppError | null;
}

export interface PlayerStoreListener {
  onState(snapshot: PlayerViewSnapshot): void;
  onProgress(progress: PlayerProgressSnapshot): void;
  onError(error: AppError, context?: PlaybackErrorContext): void;
}

export interface PlayerProgressScheduler {
  now(): number;
  schedule(callback: () => void, delayMs: number): number;
  cancel(timerId: number): void;
}

export interface PlayerCommandTarget {
  loadQueue(params: Record<string, Object>): Promise<PlaybackState>;
  appendToQueue(params: Record<string, Object>): Promise<PlaybackState>;
  removeFromQueue(params: Record<string, Object>): Promise<PlaybackState>;
  clearQueue(): Promise<PlaybackState>;
  restoreSession(session: PlayerSessionSnapshot): Promise<PlaybackState>;
  play(params: Record<string, Object>): Promise<PlaybackState>;
  pause(): Promise<PlaybackState>;
  seek(params: Record<string, Object>): Promise<PlaybackState>;
  next(): Promise<PlaybackState>;
  previous(): Promise<PlaybackState>;
  skipPrevious(): Promise<PlaybackState>;
  setMode(params: Record<string, Object>): Promise<PlaybackState>;
  setQuality(params: Record<string, Object>): Promise<PlaybackState>;
  snapshot(): PlaybackState;
}

class PlatformPlayerProgressScheduler implements PlayerProgressScheduler {
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

@Observed
export class PlayerStore {
  @Track snapshot: PlayerViewSnapshot = idleSnapshot();
  @Track progress: PlayerProgressSnapshot = idleProgress();
  @Track error: AppError | null = null;
  @Track queueRequest: PlayerQueueRequestSnapshot | null = null;
  @Track retryLoading: boolean = false;

  private readonly scheduler: PlayerProgressScheduler;
  private readonly listeners: PlayerStoreListener[] = [];
  private target: PlayerCommandTarget | null = null;
  private progressTimer: number = -1;
  private pendingProgress: PlayerProgressSnapshot | null = null;
  private lastProgressAt: number = -PLAYER_PROGRESS_INTERVAL_MS;
  private progressGeneration: number = 0;
  private revision: number = 0;
  private disposed: boolean = false;
  private queueRequestGeneration: number = 0;
  private queueRequestPromise: Promise<void> | null = null;
  private pendingQueueKeys: string[] = [];
  private pendingQueueStartIndex: number = -1;
  private pendingQueueAutoplay: boolean = true;
  private pendingQueueRestart: boolean = false;
  private retryGeneration: number = 0;

  constructor(scheduler: PlayerProgressScheduler = new PlatformPlayerProgressScheduler()) {
    this.scheduler = scheduler;
  }

  bind(target: PlayerCommandTarget): void {
    if (this.disposed) {
      throw new NativeError('player.storeDisposed', '播放器状态已关闭。');
    }
    if (this.target !== null) {
      throw new NativeError('player.storeAlreadyBound', '播放器状态已绑定。');
    }
    this.target = target;
    this.onState(target.snapshot());
  }

  read(): PlayerReadSnapshot {
    return {
      status: this.snapshot.status,
      track: cloneTrack(this.snapshot.track),
      position: this.progress.position,
      duration: this.progress.duration,
      mode: this.snapshot.mode,
      queue: cloneQueue(this.snapshot.queue),
      queueIndex: this.snapshot.queueIndex,
      error: cloneError(this.error)
    };
  }

  subscribe(listener: PlayerStoreListener): void {
    if (!this.disposed && this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: PlayerStoreListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  onState(state: PlaybackState): void {
    if (this.disposed) {
      return;
    }
    const previousTrackKey = this.currentTrackKey();
    const nextTrack = cloneTrack(state.track);
    const nextTrackKey = nextTrack === null ? '' : nextTrack.key;
    const preserveRetryError = this.retryLoading && this.error !== null &&
      nextTrackKey.length > 0 && nextTrackKey === previousTrackKey;
    this.revision++;
    this.progressGeneration++;
    this.cancelProgressTimer();
    const queue = cloneQueue(state.queue);
    this.snapshot = {
      status: safeStatus(state.status),
      track: nextTrack,
      duration: safeNumber(state.duration),
      mode: safeMode(state.mode),
      queue: queue,
      queueIndex: safeQueueIndex(state.queueIndex, queue.length)
    };
    this.progress = {
      position: safeNumber(state.position),
      duration: safeNumber(state.duration)
    };
    if (!preserveRetryError) {
      this.error = state.error === undefined ? null : sanitizeError(state.error);
    }
    this.lastProgressAt = this.scheduler.now();
    this.emitState();
  }

  onProgress(position: number, duration: number): void {
    if (this.disposed) {
      return;
    }
    this.revision++;
    const next: PlayerProgressSnapshot = {
      position: safeNumber(position),
      duration: safeNumber(duration)
    };
    if (this.progressTimer >= 0) {
      this.pendingProgress = next;
      return;
    }
    const now = this.scheduler.now();
    const elapsed = Math.max(0, now - this.lastProgressAt);
    if (elapsed >= PLAYER_PROGRESS_INTERVAL_MS) {
      this.publishProgress(next);
      return;
    }
    this.pendingProgress = next;
    const generation = this.progressGeneration;
    this.progressTimer = this.scheduler.schedule((): void => {
      this.progressTimer = -1;
      if (this.disposed || generation !== this.progressGeneration) {
        this.pendingProgress = null;
        return;
      }
      const pending = this.pendingProgress;
      this.pendingProgress = null;
      if (pending !== null) {
        this.publishProgress(pending);
      }
    }, PLAYER_PROGRESS_INTERVAL_MS - elapsed);
  }

  onError(error: AppError, context?: PlaybackErrorContext): boolean {
    if (this.disposed) {
      return false;
    }
    if (context !== undefined && context.trackKey.length > 0 &&
      context.trackKey !== this.currentTrackKey()) {
      return false;
    }
    const safe = sanitizeError(error);
    this.revision++;
    this.progressGeneration++;
    this.cancelProgressTimer();
    this.error = safe;
    if (this.snapshot.status !== 'error') {
      this.snapshot = {
        status: 'error',
        track: cloneTrack(this.snapshot.track),
        duration: this.snapshot.duration,
        mode: this.snapshot.mode,
        queue: cloneQueue(this.snapshot.queue),
        queueIndex: this.snapshot.queueIndex
      };
    }
    this.emitError(safe, context);
    return true;
  }

  loadQueue(queue: MobileTrack[], startIndex: number = 0,
    autoplay: boolean = true): Promise<void> {
    return this.playTracks(queue, startIndex, autoplay);
  }

  async appendToQueue(queue: MobileTrack[]): Promise<void> {
    const copiedQueue = cloneQueue(queue);
    if (copiedQueue.length === 0) {
      return;
    }
    const params: Record<string, Object> = {};
    params.queue = copiedQueue;
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.appendToQueue(params));
  }

  /** 把曲目放到队首并立即播放；队列中的同一曲目会被移动而不是复制。 */
  async playTrackNow(track: MobileTrack): Promise<void> {
    const placement = placeTrackAtQueueHead(this.snapshot.queue, track, PLAYER_QUEUE_LIMIT);
    if (placement.full) {
      const queueError: AppError = {
        code: 'player.queueFull',
        message: '播放队列已满（500 首），请先清理队列。',
        retryable: false
      };
      this.onError(queueError);
      throw new NativeError(queueError.code, queueError.message, queueError.retryable);
    }
    // 点击单曲始终从头播放：忽略该曲遗留的续播进度。
    await this.playTracks(placement.queue, placement.index, true, true);
  }

  async removeFromQueue(index: number): Promise<void> {
    const params: Record<string, Object> = {};
    params.index = index;
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.removeFromQueue(params));
  }

  async clearQueue(): Promise<void> {
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.clearQueue());
  }

  async restoreSession(session: PlayerSessionSnapshot): Promise<void> {
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.restoreSession(session));
  }

  playTracks(queue: MobileTrack[], startIndex: number = 0,
    autoplay: boolean = true, restart: boolean = false): Promise<void> {
    const copiedQueue = cloneQueue(queue);
    if (copiedQueue.length === 0) {
      const queueError: AppError = {
        code: 'player.queueEmpty',
        message: '播放队列为空。',
        retryable: false
      };
      this.onError(queueError);
      return Promise.reject(new NativeError(queueError.code, queueError.message, queueError.retryable));
    }
    const selection = normalizeStartIndex(startIndex, copiedQueue.length);
    if (this.queueRequestPromise !== null &&
      this.isSameQueueRequest(copiedQueue, selection, autoplay, restart)) {
      return this.queueRequestPromise;
    }

    const generation = this.queueRequestGeneration + 1;
    this.queueRequestGeneration = generation;
    this.queueRequest = {
      generation: generation,
      trackKey: copiedQueue[selection].key,
      startIndex: selection,
      queueLength: copiedQueue.length
    };
    this.pendingQueueKeys = copiedQueue.map((track: MobileTrack): string => track.key);
    this.pendingQueueStartIndex = selection;
    this.pendingQueueAutoplay = autoplay;
    this.pendingQueueRestart = restart;
    const operation = this.executeQueueLoad(copiedQueue, selection, autoplay, restart, generation);
    if (this.queueRequest !== null && this.queueRequest.generation === generation) {
      this.queueRequestPromise = operation;
    }
    return operation;
  }

  private async executeQueueLoad(queue: MobileTrack[], startIndex: number,
    autoplay: boolean, restart: boolean, generation: number): Promise<void> {
    const params: Record<string, Object> = {};
    params.queue = queue;
    params.startIndex = startIndex;
    params.autoplay = autoplay;
    params.restart = restart;
    try {
      const target = this.requireTarget();
      await target.loadQueue(params);
    } catch (error) {
      const appError = toAppError(error as Object);
      if (!this.disposed && this.target !== null && generation === this.queueRequestGeneration) {
        this.onError(appError);
      }
      throw new NativeError(appError.code, appError.message, appError.retryable);
    } finally {
      if (generation === this.queueRequestGeneration) {
        this.queueRequest = null;
        this.queueRequestPromise = null;
        this.pendingQueueKeys = [];
        this.pendingQueueStartIndex = -1;
        this.pendingQueueRestart = false;
      }
    }
  }

  async play(index: number = -1): Promise<void> {
    const params: Record<string, Object> = {};
    if (index >= 0) {
      params.index = index;
    }
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.play(params));
  }

  async retryPlayback(): Promise<void> {
    if (this.disposed || this.retryLoading || this.error === null ||
      !this.error.retryable || this.snapshot.track === null) {
      return;
    }
    this.retryGeneration++;
    const generation = this.retryGeneration;
    this.retryLoading = true;
    let succeeded = false;
    try {
      // PlayerService restarts an error-state track from its authoritative queue index and position.
      await this.play();
      succeeded = this.snapshot.status !== 'error';
    } catch (_error) {
      // The service publishes the single sanitized error retained by the store.
    } finally {
      if (generation === this.retryGeneration) {
        this.retryLoading = false;
        if (succeeded && this.error !== null) {
          this.error = null;
          this.emitState();
        }
      }
    }
  }

  async pause(): Promise<void> {
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> => target.pause());
  }

  async seek(position: number): Promise<void> {
    const params: Record<string, Object> = {};
    params.position = position;
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.seek(params));
  }

  async next(): Promise<void> {
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> => target.next());
  }

  async previous(): Promise<void> {
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> => target.previous());
  }

  /** 播放页下拉切歌：跳过“回到本曲开头”的判定，始终切到上一首。 */
  async skipPrevious(): Promise<void> {
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.skipPrevious());
  }

  async setMode(mode: PlayerMode): Promise<void> {
    const params: Record<string, Object> = {};
    params.mode = mode;
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.setMode(params));
  }

  async setQuality(quality: AudioQuality): Promise<void> {
    const params: Record<string, Object> = {};
    params.quality = quality;
    await this.runCommand((target: PlayerCommandTarget): Promise<PlaybackState> =>
      target.setQuality(params));
  }

  detachTarget(): void {
    this.target = null;
    this.revision++;
    this.progressGeneration++;
    this.cancelProgressTimer();
    this.queueRequestGeneration++;
    this.queueRequest = null;
    this.queueRequestPromise = null;
    this.pendingQueueKeys = [];
    this.pendingQueueStartIndex = -1;
    this.pendingQueueRestart = false;
    this.retryGeneration++;
    this.retryLoading = false;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.detachTarget();
    this.listeners.splice(0, this.listeners.length);
  }

  private isSameQueueRequest(queue: MobileTrack[], startIndex: number, autoplay: boolean,
    restart: boolean): boolean {
    if (startIndex !== this.pendingQueueStartIndex || autoplay !== this.pendingQueueAutoplay ||
      restart !== this.pendingQueueRestart || queue.length !== this.pendingQueueKeys.length) {
      return false;
    }
    for (let index = 0; index < queue.length; index++) {
      if (queue[index].key !== this.pendingQueueKeys[index]) {
        return false;
      }
    }
    return true;
  }

  private async runCommand(operation: (target: PlayerCommandTarget) => Promise<PlaybackState>): Promise<void> {
    const target = this.requireTarget();
    const revision = this.revision;
    try {
      const state = await operation(target);
      if (!this.disposed && revision === this.revision) {
        this.onState(state);
      }
    } catch (error) {
      const appError = toAppError(error as Object);
      if (!this.disposed && revision === this.revision) {
        this.onError(appError);
      }
      throw new NativeError(appError.code, appError.message, appError.retryable);
    }
  }

  private requireTarget(): PlayerCommandTarget {
    if (this.disposed) {
      throw new NativeError('player.storeDisposed', '播放器状态已关闭。');
    }
    if (this.target === null) {
      throw new NativeError('player.notReady', '播放器尚未准备好。', true);
    }
    return this.target;
  }

  private publishProgress(progress: PlayerProgressSnapshot): void {
    if (progress.position === this.progress.position && progress.duration === this.progress.duration) {
      return;
    }
    this.progress = progress;
    this.lastProgressAt = this.scheduler.now();
    this.emitProgress(progress);
  }

  private cancelProgressTimer(): void {
    if (this.progressTimer >= 0) {
      this.scheduler.cancel(this.progressTimer);
      this.progressTimer = -1;
    }
    this.pendingProgress = null;
  }

  private emitState(): void {
    const listeners = this.listeners.slice();
    for (const listener of listeners) {
      try {
        listener.onState(cloneViewSnapshot(this.snapshot));
      } catch (error) {
        this.logListenerError(error as Object);
      }
    }
  }

  private emitProgress(progress: PlayerProgressSnapshot): void {
    const listeners = this.listeners.slice();
    for (const listener of listeners) {
      try {
        listener.onProgress(cloneProgress(progress));
      } catch (error) {
        this.logListenerError(error as Object);
      }
    }
  }

  private emitError(error: AppError, context?: PlaybackErrorContext): void {
    const listeners = this.listeners.slice();
    let safeContext: PlaybackErrorContext | undefined = undefined;
    if (context !== undefined) {
      safeContext = {
        trackKey: context.trackKey,
        generation: context.generation
      };
    }
    for (const listener of listeners) {
      try {
        listener.onError(cloneError(error) as AppError, safeContext);
      } catch (listenerError) {
        this.logListenerError(listenerError as Object);
      }
    }
  }

  private currentTrackKey(): string {
    const track = this.snapshot.track;
    return track === null ? '' : track.key;
  }

  private logListenerError(error: Object): void {
    const appError = toAppError(error);
    hilog.warn(DOMAIN, TAG, 'player listener failed code=%{public}s', appError.code);
  }
}

function idleSnapshot(): PlayerViewSnapshot {
  return {
    status: 'idle',
    track: null,
    duration: 0,
    mode: 'sequence',
    queue: [],
    queueIndex: -1
  };
}

function idleProgress(): PlayerProgressSnapshot {
  return {
    position: 0,
    duration: 0
  };
}

function safeStatus(status: PlaybackStatus): PlaybackStatus {
  if (status === 'loading' || status === 'playing' || status === 'paused' || status === 'error') {
    return status;
  }
  return 'idle';
}

function safeMode(mode: PlayerMode): PlayerMode {
  if (mode === 'repeat-one' || mode === 'repeat-all' || mode === 'shuffle') {
    return mode;
  }
  return 'sequence';
}

function safeQueueIndex(index: number, queueLength: number): number {
  if (!Number.isFinite(index) || queueLength <= 0) {
    return -1;
  }
  const safeIndex = Math.floor(index);
  return safeIndex >= 0 && safeIndex < queueLength ? safeIndex : -1;
}

function safeNumber(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0;
}

function normalizeStartIndex(index: number, queueLength: number): number {
  if (queueLength <= 0) {
    return 0;
  }
  const safeIndex = Number.isFinite(index) ? Math.floor(index) : 0;
  return Math.min(Math.max(safeIndex, 0), queueLength - 1);
}

function sanitizeError(error: AppError): AppError {
  const cleanCode = error.code.trim();
  const code = /^[a-zA-Z0-9._-]{1,80}$/u.test(cleanCode) ? cleanCode : 'player.error';
  const message = error.message.trim().slice(0, 240);
  const safeMessage = message.length === 0 || /(https?:\/\/|cookie|authorization|qrcode_key)/iu.test(message)
    ? SAFE_PLAYER_ERROR_MESSAGE
    : message;
  return {
    code: code,
    message: safeMessage,
    retryable: error.retryable
  };
}

function cloneTrack(track: MobileTrack | null): MobileTrack | null {
  if (track === null) {
    return null;
  }
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
  return queue.map((track: MobileTrack): MobileTrack => {
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
  });
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

function cloneViewSnapshot(snapshot: PlayerViewSnapshot): PlayerViewSnapshot {
  return {
    status: snapshot.status,
    track: cloneTrack(snapshot.track),
    duration: snapshot.duration,
    mode: snapshot.mode,
    queue: cloneQueue(snapshot.queue),
    queueIndex: snapshot.queueIndex
  };
}

function cloneProgress(progress: PlayerProgressSnapshot): PlayerProgressSnapshot {
  return {
    position: progress.position,
    duration: progress.duration
  };
}
