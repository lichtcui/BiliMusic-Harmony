import {
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
} from '../../state/PlayerStore';
import {
  AppError,
  MobileTrack,
  PlaybackStatus,
  PlayerMode
} from '../../types/MobileTypes';
import { playbackErrorPresentation } from '../../util/PlaybackErrorPresentation';

export type PlayerPageBusyAction =
  '' | 'toggle' | 'previous' | 'next' | 'mode' | 'seek' | 'retry';

const SEEK_CONFIRM_TOLERANCE_SECONDS: number = 1.5;
const SEEK_NOOP_TOLERANCE_SECONDS: number = 0.25;

export function nextPlayerMode(mode: PlayerMode): PlayerMode {
  if (mode === 'sequence') {
    return 'repeat-all';
  }
  if (mode === 'repeat-all') {
    return 'repeat-one';
  }
  if (mode === 'repeat-one') {
    return 'shuffle';
  }
  return 'sequence';
}

export function formatPlayerTime(seconds: number, fallback: string = '0:00'): string {
  if (!Number.isFinite(seconds) || seconds < 0) {
    return fallback;
  }
  const totalSeconds = Math.floor(seconds);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const remainingSeconds = totalSeconds % 60;
  const paddedSeconds = remainingSeconds < 10 ? `0${remainingSeconds}` : `${remainingSeconds}`;
  if (hours > 0) {
    const paddedMinutes = minutes < 10 ? `0${minutes}` : `${minutes}`;
    return `${hours}:${paddedMinutes}:${paddedSeconds}`;
  }
  return `${minutes}:${paddedSeconds}`;
}

@Observed
export class PlayerPageState implements PlayerStoreListener {
  @Track status: PlaybackStatus = 'idle';
  @Track track: MobileTrack | null = null;
  @Track position: number = 0;
  @Track duration: number = 0;
  @Track mode: PlayerMode = 'sequence';
  @Track queueIndex: number = -1;
  @Track error: AppError | null = null;
  @Track dragging: boolean = false;
  @Track draftPosition: number = 0;
  @Track pendingSeekPosition: number = -1;
  @Track busyAction: PlayerPageBusyAction = '';
  @Track retryLoading: boolean = false;

  private store: PlayerStore | null = null;
  private pendingSeekTrackKey: string = '';
  private seekGeneration: number = 0;
  private disposed: boolean = false;

  constructor(store: PlayerStore) {
    this.store = store;
    this.applyState(store.snapshot);
    this.applyProgress(store.progress);
    this.error = cloneError(store.error);
    this.retryLoading = store.retryLoading;
  }

  /**
   * Subscribes this instance to the player store.
   *
   * Must be called after construction and through the observed instance: @Observed wraps the
   * object only after the constructor returns, so subscribing `this` inside the constructor
   * hands the store the raw target. Store callbacks would then write through the raw object and
   * bypass the proxy, leaving every @ObjectLink binding stale (page text frozen while the track
   * keeps playing).
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
      this.applyProgress(store.progress);
      this.error = cloneError(store.error);
      this.retryLoading = store.retryLoading;
    }
  }

  onProgress(progress: PlayerProgressSnapshot): void {
    if (this.disposed) {
      return;
    }
    this.applyProgress(progress);
  }

  onError(error: AppError): void {
    if (this.disposed) {
      return;
    }
    const store = this.store;
    if (store !== null) {
      this.applyState(store.snapshot);
      this.applyProgress(store.progress);
    }
    this.error = cloneError(error) as AppError;
    this.retryLoading = store === null ? false : store.retryLoading;
    this.dragging = false;
    this.clearPendingSeek();
  }

  beginSeek(value: number): void {
    if (!this.canSeek()) {
      return;
    }
    this.dragging = true;
    this.draftPosition = clampPosition(value, this.duration);
  }

  updateSeek(value: number): void {
    if (!this.dragging || this.duration <= 0) {
      return;
    }
    this.draftPosition = clampPosition(value, this.duration);
  }

  async submitSeek(value: number): Promise<void> {
    if (this.store === null || this.track === null || this.duration <= 0 ||
      this.status === 'loading' || this.status === 'error' || this.busyAction !== '') {
      this.dragging = false;
      return;
    }
    const target = clampPosition(value, this.duration);
    this.dragging = false;
    this.draftPosition = target;
    if (Math.abs(target - this.position) <= SEEK_NOOP_TOLERANCE_SECONDS) {
      this.clearPendingSeek();
      return;
    }
    if (this.pendingSeekPosition >= 0 &&
      Math.abs(target - this.pendingSeekPosition) <= SEEK_NOOP_TOLERANCE_SECONDS) {
      return;
    }

    const generation = this.seekGeneration + 1;
    this.seekGeneration = generation;
    this.pendingSeekPosition = target;
    this.pendingSeekTrackKey = this.trackKey();
    this.busyAction = 'seek';
    try {
      await this.store.seek(target);
      if (generation === this.seekGeneration && this.pendingSeekTrackKey === this.trackKey()) {
        this.position = target;
        this.clearPendingSeek();
      }
    } catch (error) {
      if (generation === this.seekGeneration) {
        this.clearPendingSeek();
        this.draftPosition = this.position;
      }
    } finally {
      if (this.busyAction === 'seek') {
        this.busyAction = '';
      }
    }
  }

  async togglePlayback(): Promise<void> {
    if (!this.canTogglePlayback()) {
      return;
    }
    const store = this.store;
    if (store === null) {
      return;
    }
    this.busyAction = 'toggle';
    try {
      if (this.status === 'playing') {
        await store.pause();
      } else {
        await store.play();
      }
    } catch (error) {
      // PlayerStore publishes the sanitized error state rendered by the page.
    } finally {
      if (this.busyAction === 'toggle') {
        this.busyAction = '';
      }
    }
  }

  async previous(): Promise<void> {
    await this.runTransport('previous', (store: PlayerStore): Promise<void> => store.previous());
  }

  /** 播放页下拉切歌：始终切到上一首，不因当前进度过半而重播本曲。 */
  async skipPrevious(): Promise<void> {
    await this.runTransport('previous', (store: PlayerStore): Promise<void> => store.skipPrevious());
  }

  async next(): Promise<void> {
    await this.runTransport('next', (store: PlayerStore): Promise<void> => store.next());
  }

  async cycleMode(): Promise<void> {
    if (!this.canCycleMode()) {
      return;
    }
    const store = this.store;
    if (store === null) {
      return;
    }
    const targetMode = nextPlayerMode(this.mode);
    this.busyAction = 'mode';
    try {
      await store.setMode(targetMode);
    } catch (error) {
      // PlayerStore keeps the last confirmed mode and publishes the error.
    } finally {
      if (this.busyAction === 'mode') {
        this.busyAction = '';
      }
    }
  }

  displayPosition(): number {
    if (this.dragging) {
      return clampPosition(this.draftPosition, this.duration);
    }
    if (this.isSeekPending()) {
      return clampPosition(this.pendingSeekPosition, this.duration);
    }
    return clampPosition(this.position, this.duration);
  }

  sliderMaximum(): number {
    return this.duration > 0 ? this.duration : 1;
  }

  canSeek(): boolean {
    return this.track !== null && this.duration > 0 &&
      this.status !== 'loading' && this.status !== 'error' && this.busyAction === '';
  }

  canTogglePlayback(): boolean {
    return this.track !== null && this.status !== 'loading' && this.status !== 'error' &&
      this.busyAction === '';
  }

  canSkip(): boolean {
    return this.track !== null && this.status !== 'loading' && this.status !== 'error' &&
      this.busyAction === '';
  }

  canCycleMode(): boolean {
    return this.track !== null && this.status !== 'loading' && this.status !== 'error' &&
      this.busyAction === '';
  }

  canRetryPlayback(): boolean {
    return this.error !== null && this.track !== null &&
      playbackErrorPresentation(this.error).retryable &&
      this.busyAction === '' && !this.retryLoading;
  }

  async retryPlayback(): Promise<void> {
    if (!this.canRetryPlayback()) {
      return;
    }
    const store = this.store;
    if (store === null) {
      return;
    }
    this.busyAction = 'retry';
    this.retryLoading = true;
    try {
      await store.retryPlayback();
    } catch (error) {
      // PlayerStore retains the sanitized error when a retry fails.
    } finally {
      this.busyAction = '';
      this.retryLoading = store.retryLoading;
      this.applyState(store.snapshot);
      this.applyProgress(store.progress);
      this.error = cloneError(store.error);
    }
  }

  isBusy(): boolean {
    return this.busyAction !== '';
  }

  isSeekPending(): boolean {
    return this.pendingSeekPosition >= 0 && this.pendingSeekTrackKey === this.trackKey();
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.store?.unsubscribe(this);
    this.store = null;
    this.clearPendingSeek();
  }

  private async runTransport(action: 'previous' | 'next',
    operation: (store: PlayerStore) => Promise<void>): Promise<void> {
    if (!this.canSkip()) {
      return;
    }
    const store = this.store;
    if (store === null) {
      return;
    }
    this.busyAction = action;
    try {
      await operation(store);
    } catch (error) {
      // PlayerStore publishes transport failures and preserves the current track.
    } finally {
      if (this.busyAction === action) {
        this.busyAction = '';
      }
    }
  }

  private applyState(snapshot: PlayerViewSnapshot): void {
    const nextTrackKey = snapshot.track === null ? '' : snapshot.track.key;
    const trackChanged = nextTrackKey !== this.trackKey();
    if (trackChanged) {
      this.dragging = false;
      this.clearPendingSeek();
    }
    this.status = snapshot.status;
    this.track = cloneTrack(snapshot.track);
    this.duration = safeNumber(snapshot.duration);
    this.mode = snapshot.mode;
    this.queueIndex = safeInteger(snapshot.queueIndex, -1);
    if (trackChanged) {
      this.draftPosition = 0;
    }
  }

  private applyProgress(progress: PlayerProgressSnapshot): void {
    const nextDuration = safeNumber(progress.duration);
    const nextPosition = clampPosition(progress.position, nextDuration);
    this.duration = nextDuration;
    this.position = nextPosition;
    if (this.isSeekPending() &&
      Math.abs(nextPosition - this.pendingSeekPosition) <= SEEK_CONFIRM_TOLERANCE_SECONDS) {
      this.clearPendingSeek();
    }
  }

  private clearPendingSeek(): void {
    this.seekGeneration += 1;
    this.pendingSeekPosition = -1;
    this.pendingSeekTrackKey = '';
  }

  private trackKey(): string {
    return this.track === null ? '' : this.track.key;
  }
}

function clampPosition(value: number, duration: number): number {
  const safe = safeNumber(value);
  const maximum = safeNumber(duration);
  return maximum > 0 ? Math.min(safe, maximum) : safe;
}

function safeNumber(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0;
}

function safeInteger(value: number, fallback: number): number {
  return Number.isFinite(value) ? Math.floor(value) : fallback;
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
