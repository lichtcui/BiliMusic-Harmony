import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AppError,
  MobileTrack,
  PlaybackState,
  PlayerMode,
  PlayerSessionSnapshot
} from '../types/MobileTypes';
import {
  deleteAtomicFile,
  preserveCorruptFile,
  readAtomicText,
  writeAtomicText
} from '../util/AtomicJson';
import { appError } from '../util/Errors';
import {
  arrayValue,
  numberValue,
  objectValue
} from '../util/Json';
import {
  PLAYER_QUEUE_LIMIT,
  sanitizePlayerQueue
} from '../services/PlayerQueue';

const DOMAIN = 0x424D;
const TAG = 'WispMusicPlayerSession';

export const PLAYER_SESSION_VERSION: number = 1;
export const PLAYER_SESSION_WRITE_INTERVAL_MS: number = 1000;

export interface PlayerSessionDiagnostics {
  recovered: boolean;
  error: AppError | null;
}

export interface PlayerSessionPersistence {
  read(path: string): string | null;
  write(path: string, content: string): Promise<void>;
  preserveCorrupt(path: string): void;
  delete(path: string): void;
}

export interface PlayerSessionScheduler {
  now(): number;
  schedule(callback: () => void, delayMs: number): number;
  cancel(timerId: number): void;
}

class AtomicPlayerSessionPersistence implements PlayerSessionPersistence {
  read(path: string): string | null {
    return readAtomicText(path);
  }

  write(path: string, content: string): Promise<void> {
    return writeAtomicText(path, content);
  }

  preserveCorrupt(path: string): void {
    preserveCorruptFile(path);
  }

  delete(path: string): void {
    deleteAtomicFile(path);
  }
}

class PlatformPlayerSessionScheduler implements PlayerSessionScheduler {
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

/**
 * Versioned writer for the last resumable playback snapshot.
 *
 * PlayerService remains the owner of live media. This store only serializes the
 * queue state needed to rebuild a paused player after a cold start.
 */
export class PlayerSessionStore {
  private readonly path: string;
  private readonly persistence: PlayerSessionPersistence;
  private readonly scheduler: PlayerSessionScheduler;
  private session: PlayerSessionSnapshot | null = null;
  private pendingSession: PlayerSessionSnapshot | null = null;
  private pendingDelete: boolean = false;
  private throttleTimer: number = -1;
  private lastWriteAt: number;
  private writeChain: Promise<void> = Promise.resolve();
  /** 每次 queueWrite/queueDelete 递增；用于判断写入失败后能否安全回填 pending。 */
  private queuedSequence: number = 0;
  private pendingSequence: number = 0;
  private disposed: boolean = false;
  private diagnostic: PlayerSessionDiagnostics = {
    recovered: false,
    error: null
  };

  constructor(path: string, persistence: PlayerSessionPersistence = new AtomicPlayerSessionPersistence(),
    scheduler: PlayerSessionScheduler = new PlatformPlayerSessionScheduler()) {
    this.path = path;
    this.persistence = persistence;
    this.scheduler = scheduler;
    this.lastWriteAt = scheduler.now() - PLAYER_SESSION_WRITE_INTERVAL_MS;
    this.session = this.load();
  }

  restore(): PlayerSessionSnapshot | null {
    return cloneSession(this.session);
  }

  storageDiagnostics(): PlayerSessionDiagnostics {
    return {
      recovered: this.diagnostic.recovered,
      error: cloneAppError(this.diagnostic.error)
    };
  }

  captureState(state: PlaybackState): void {
    if (this.disposed) {
      return;
    }
    const next = sessionFromPlayback(state);
    this.session = next;
    if (next === null) {
      this.queueDelete();
      return;
    }
    this.queueWrite(next, true);
  }

  captureProgress(position: number, duration: number): void {
    if (this.disposed) {
      return;
    }
    const current = this.session;
    if (current === null) {
      return;
    }
    const safeDuration = finiteNonNegative(duration);
    const next = cloneSession(current);
    if (next === null) {
      return;
    }
    next.duration = safeDuration === null ? next.duration : safeDuration;
    next.position = clampedPosition(position, next.duration);
    if (next.position === current.position && next.duration === current.duration) {
      return;
    }
    this.session = next;
    this.queueWrite(next, false);
  }

  async flush(): Promise<void> {
    await this.drainPending();
    // 第一次写失败会把快照回填到 pendingSession（见 enqueuePendingWrite 的 catch）；
    // 关闭/切后台路径再补一次，避免一次瞬时 I/O 失败导致冷启动回到旧进度。
    if (this.pendingDelete || this.pendingSession !== null) {
      await this.drainPending();
    }
  }

  /**
   * 停止接受新快照并落盘最后一份。runtime 在 player.shutdown() 之前先 flush 一次，
   * 这里再等写链收尾，防止尾随 onProgress 在会话文件已停写后继续挂定时器。
   */
  async dispose(): Promise<void> {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.cancelThrottle();
    await this.flush();
  }

  private async drainPending(): Promise<void> {
    if (this.pendingDelete) {
      this.enqueueDelete();
    } else if (this.pendingSession !== null) {
      this.enqueuePendingWrite();
    }
    await this.writeChain.catch((): void => {});
  }

  private queueWrite(snapshot: PlayerSessionSnapshot, force: boolean): void {
    this.pendingSession = cloneSession(snapshot);
    this.pendingDelete = false;
    this.queuedSequence += 1;
    this.pendingSequence = this.queuedSequence;
    this.cancelThrottle();
    const elapsed = Math.max(0, this.scheduler.now() - this.lastWriteAt);
    const delay = Math.max(0, PLAYER_SESSION_WRITE_INTERVAL_MS - elapsed);
    if (force || delay === 0) {
      this.enqueuePendingWrite();
      return;
    }
    this.throttleTimer = this.scheduler.schedule((): void => {
      this.throttleTimer = -1;
      this.enqueuePendingWrite();
    }, delay);
  }

  private queueDelete(): void {
    this.cancelThrottle();
    this.pendingSession = null;
    this.pendingDelete = true;
    this.queuedSequence += 1;
    this.pendingSequence = this.queuedSequence;
    this.enqueueDelete();
  }

  private enqueuePendingWrite(): void {
    this.cancelThrottle();
    const snapshot = this.pendingSession;
    const sequence = this.pendingSequence;
    this.pendingSession = null;
    this.pendingDelete = false;
    if (snapshot === null) {
      return;
    }
    const operation = this.writeChain
      .catch((): void => {})
      .then(async (): Promise<void> => {
        try {
          await this.persistence.write(this.path, JSON.stringify(snapshot));
          this.lastWriteAt = this.scheduler.now();
          if (this.diagnostic.error?.code === 'player.sessionWriteFailed') {
            this.diagnostic.error = null;
          }
        } catch (error) {
          this.recordWriteFailure();
          // 只有失败期间没有更新的快照/删除时才回填，避免用旧数据覆盖新状态。
          if (sequence === this.queuedSequence) {
            this.pendingSession = snapshot;
          }
        }
      });
    this.writeChain = operation.then((): void => {}, (): void => {});
  }

  private enqueueDelete(): void {
    if (!this.pendingDelete) {
      return;
    }
    const sequence = this.pendingSequence;
    this.pendingDelete = false;
    const operation = this.writeChain
      .catch((): void => {})
      .then(async (): Promise<void> => {
        try {
          this.persistence.delete(this.path);
          this.lastWriteAt = this.scheduler.now();
          if (this.diagnostic.error?.code === 'player.sessionWriteFailed') {
            this.diagnostic.error = null;
          }
        } catch (error) {
          this.recordWriteFailure();
          if (sequence === this.queuedSequence) {
            this.pendingDelete = true;
          }
        }
      });
    this.writeChain = operation.then((): void => {}, (): void => {});
  }

  private recordWriteFailure(): void {
    const failure = appError('player.sessionWriteFailed', '播放会话保存失败。', true);
    this.diagnostic.error = failure;
    hilog.warn(DOMAIN, TAG, 'session persistence failed code=%{public}s', failure.code);
  }

  private cancelThrottle(): void {
    if (this.throttleTimer >= 0) {
      this.scheduler.cancel(this.throttleTimer);
      this.throttleTimer = -1;
    }
  }

  private load(): PlayerSessionSnapshot | null {
    const content = this.persistence.read(this.path);
    if (content === null) {
      return null;
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(content) as Object;
    } catch (error) {
      return this.recoverInvalid('player.sessionCorrupt', true);
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return this.recoverInvalid('player.sessionInvalid', false);
    }
    const raw = objectValue(parsed);
    if (numberValue(raw.version, -1) !== PLAYER_SESSION_VERSION) {
      return this.recoverInvalid('player.sessionUnsupportedVersion', false);
    }
    const queueValues = arrayValue(raw.queue);
    if (!Array.isArray(raw.queue) || queueValues.length === 0 ||
      queueValues.length > PLAYER_QUEUE_LIMIT) {
      return this.recoverInvalid('player.sessionInvalid', false);
    }
    const queue = sanitizePlayerQueue(queueValues, PLAYER_QUEUE_LIMIT + 1, true);
    if (queue.length !== queueValues.length || queue.length > PLAYER_QUEUE_LIMIT) {
      return this.recoverInvalid('player.sessionInvalid', false);
    }
    const queueIndex = strictInteger(raw.queueIndex);
    if (queueIndex === null || queueIndex < 0 || queueIndex >= queue.length) {
      return this.recoverInvalid('player.sessionInvalid', false);
    }
    const mode = strictMode(raw.mode);
    if (mode === null) {
      return this.recoverInvalid('player.sessionInvalid', false);
    }
    const position = finiteNonNegative(raw.position);
    const duration = finiteNonNegative(raw.duration);
    if (position === null || duration === null || (duration > 0 && position > duration)) {
      return this.recoverInvalid('player.sessionInvalid', false);
    }
    return {
      version: PLAYER_SESSION_VERSION,
      queue: queue,
      queueIndex: queueIndex,
      mode: mode,
      position: position,
      duration: duration
    };
  }

  private recoverInvalid(code: string, retryable: boolean): null {
    const failure = appError(code, '播放会话无法恢复。', retryable);
    this.persistence.preserveCorrupt(this.path);
    this.diagnostic = {
      recovered: true,
      error: failure
    };
    hilog.warn(DOMAIN, TAG, 'session recovery code=%{public}s', failure.code);
    return null;
  }
}

function sessionFromPlayback(state: PlaybackState): PlayerSessionSnapshot | null {
  const track = state.track;
  if (state.status === 'idle' || track === null || state.queue.length === 0) {
    return null;
  }
  const queue = sanitizePlayerQueue(state.queue, PLAYER_QUEUE_LIMIT, false);
  if (queue.length !== state.queue.length) {
    return null;
  }
  const index = strictInteger(state.queueIndex);
  if (index === null || index < 0 || index >= queue.length || queue[index].key !== track.key) {
    return null;
  }
  const mode = strictMode(state.mode);
  const savedDuration = finiteNonNegative(state.duration);
  const duration = savedDuration === null ? track.duration : savedDuration;
  return {
    version: PLAYER_SESSION_VERSION,
    queue: queue,
    queueIndex: index,
    mode: mode ?? 'sequence',
    position: clampedPosition(state.position, duration),
    duration: duration
  };
}

function strictInteger(value: Object | undefined): number | null {
  if (typeof value !== 'number') {
    return null;
  }
  const numberValue = value as number;
  return Number.isInteger(numberValue) ? numberValue : null;
}

function finiteNonNegative(value: Object | undefined): number | null {
  if (typeof value !== 'number') {
    return null;
  }
  const numberValue = value as number;
  return Number.isFinite(numberValue) && numberValue >= 0 ? numberValue : null;
}

function strictMode(value: Object | undefined): PlayerMode | null {
  if (value === 'sequence' || value === 'repeat-one' || value === 'repeat-all' ||
    value === 'shuffle') {
    return value as PlayerMode;
  }
  return null;
}

function clampedPosition(position: number, duration: number): number {
  const safe = finiteNonNegative(position) ?? 0;
  return duration > 0 ? Math.min(safe, duration) : safe;
}

function cloneSession(value: PlayerSessionSnapshot | null): PlayerSessionSnapshot | null {
  if (value === null) {
    return null;
  }
  return {
    version: value.version,
    queue: value.queue.map((track: MobileTrack): MobileTrack => cloneTrack(track)),
    queueIndex: value.queueIndex,
    mode: value.mode,
    position: value.position,
    duration: value.duration
  };
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

function cloneAppError(value: AppError | null): AppError | null {
  if (value === null) {
    return null;
  }
  return {
    code: value.code,
    message: value.message,
    retryable: value.retryable
  };
}
