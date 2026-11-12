import {
  LyricsCandidateSnapshot,
  LyricsCandidateStatus,
  LyricsStatus,
  LyricsStore,
  LyricsStoreListener,
  LyricsStoreSnapshot
} from '../../state/LyricsStore';
import {
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
} from '../../state/PlayerStore';
import {
  AppError,
  LyricCandidate,
  LyricLine,
  MobileTrack,
  PlaybackErrorContext,
  PlaybackStatus
} from '../../types/MobileTypes';

const ACTIVE_LINE_TOLERANCE_SECONDS: number = 0.05;

export function findActiveLyricIndex(lines: LyricLine[], synced: boolean, position: number): number {
  if (!synced || lines.length === 0 || !Number.isFinite(position)) {
    return -1;
  }
  const target = Math.max(0, position) + ACTIVE_LINE_TOLERANCE_SECONDS;
  let low = 0;
  let high = lines.length - 1;
  let active = -1;
  while (low <= high) {
    const middle = Math.floor((low + high) / 2);
    const lineTime = lines[middle].time;
    if (lineTime <= target) {
      active = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return active;
}

@Observed
export class LyricsPanelState implements LyricsStoreListener, PlayerStoreListener {
  @Track status: LyricsStatus = 'idle';
  @Track trackKey: string = '';
  @Track lines: LyricLine[] = [];
  @Track currentIndex: number = -1;
  @Track followPaused: boolean = false;
  @Track seekLoading: boolean = false;
  @Track contentGeneration: number = 0;
  @Track candidatesOpen: boolean = false;
  @Track candidateStatus: LyricsCandidateStatus = 'idle';
  @Track candidates: LyricCandidate[] = [];
  @Track selectedCandidateId: string = '';
  @Track candidateError: AppError | null = null;

  private lyricsStore: LyricsStore | null = null;
  private playerStore: PlayerStore | null = null;
  /** Mirrored from PlayerStore so the lyrics full page can render a progress/time row in sync. */
  @Track position: number = 0;
  @Track duration: number = 0;
  /** Whether the last error state offers a retry (from LyricsStoreSnapshot.canRetry). */
  @Track canRetry: boolean = false;
  /** Active track title, mirrored for the full-page header. */
  @Track trackTitle: string = '';
  /** Active track, mirrored so the full page can render cover / artist / duration without a second store. */
  @Track track: MobileTrack | null = null;
  /** Playback status and toggle pends mirrored from PlayerStore for the bottom transport pill (04 稿). */
  @Track playbackStatus: PlaybackStatus = 'idle';
  @Track transportBusy: boolean = false;
  private playerTrackKey: string = '';
  private seekGeneration: number = 0;
  /**
   * `canTogglePlayback()` 会在歌词面板 / 播放页的 build() 渲染期被调用，因此这个字段必须 @Track：
   * @Observed 类在 UI 里读未 @Track 的属性会抛 BusinessError 140110 并直接杀进程
   * （真机日志：Illegal usage of not @Track'ed property 'disposed' on UI!）。
   */
  @Track private disposed: boolean = false;

  constructor(lyricsStore: LyricsStore, playerStore: PlayerStore) {
    this.lyricsStore = lyricsStore;
    this.playerStore = playerStore;
    this.applyLyrics(lyricsStore.snapshot);
    this.applyCandidates(lyricsStore.readCandidates());
    this.syncPlayer(playerStore.snapshot);
    this.position = safePosition(playerStore.progress.position);
    this.duration = safePosition(playerStore.progress.duration);
    this.updateCurrentIndex();
  }

  /**
   * Subscribes this instance to both stores. See PlayerPageState#attach for why this cannot
   * happen in the constructor (@Observed proxies the object only after the constructor returns).
   */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.lyricsStore?.subscribe(this);
    this.playerStore?.subscribe(this);
  }

  onLyrics(snapshot: LyricsStoreSnapshot): void {
    if (!this.disposed) {
      this.applyLyrics(snapshot);
    }
  }

  onCandidates(snapshot: LyricsCandidateSnapshot): void {
    if (!this.disposed) {
      this.applyCandidates(snapshot);
    }
  }

  onState(snapshot: PlayerViewSnapshot): void {
    if (!this.disposed) {
      this.syncPlayer(snapshot);
    }
  }

  onProgress(progress: PlayerProgressSnapshot): void {
    if (this.disposed) {
      return;
    }
    this.position = safePosition(progress.position);
    this.duration = safePosition(progress.duration);
    this.updateCurrentIndex();
  }

  onError(_error: AppError, _context?: PlaybackErrorContext): void {
    // Playback failures remain visible in PlayerPage's existing error banner.
  }

  pauseFollow(): void {
    if (!this.disposed) {
      this.followPaused = true;
    }
  }

  resumeFollow(): void {
    if (!this.disposed) {
      this.followPaused = false;
    }
  }

  openCandidateSearch(): void {
    if (this.disposed || this.trackKey.length === 0 || this.candidatesOpen) {
      return;
    }
    this.candidatesOpen = true;
    const store = this.lyricsStore;
    if (store === null) {
      this.candidatesOpen = false;
      return;
    }
    void store.searchCandidates();
  }

  retryCandidateSearch(): void {
    if (this.disposed || !this.candidatesOpen || this.selectedCandidateId.length > 0) {
      return;
    }
    const store = this.lyricsStore;
    if (store === null) {
      return;
    }
    void store.searchCandidates();
  }

  closeCandidateSearch(): void {
    if (this.disposed) {
      return;
    }
    this.candidatesOpen = false;
    this.resetCandidates();
    this.lyricsStore?.cancelCandidateSearch();
  }

  async selectCandidate(candidateId: string): Promise<void> {
    if (this.disposed || !this.candidatesOpen || this.selectedCandidateId.length > 0) {
      return;
    }
    const store = this.lyricsStore;
    if (store === null) {
      return;
    }
    await store.selectCandidate(candidateId);
  }

  canSeek(): boolean {
    return !this.disposed && this.status === 'ready' && !this.seekLoading &&
      this.lines.length > 0;
  }

  /** 底部播放胶囊是否可点：有曲目、非加载/错误态、且没有在途的暂停/播放请求。 */
  canTogglePlayback(): boolean {
    return !this.disposed && this.track !== null && !this.transportBusy &&
      this.playbackStatus !== 'loading' && this.playbackStatus !== 'error';
  }

  /** 底部播放胶囊：直接转发 PlayerStore 的暂停/播放，不改动歌词状态。 */
  async togglePlayback(): Promise<void> {
    const store = this.playerStore;
    if (!this.canTogglePlayback() || store === null) {
      return;
    }
    this.transportBusy = true;
    try {
      if (this.playbackStatus === 'playing') {
        await store.pause();
      } else {
        await store.play();
      }
    } catch (_error) {
      // PlayerStore publishes the sanitized playback error; the lyrics page keeps its state.
    } finally {
      if (!this.disposed) {
        this.transportBusy = false;
      }
    }
  }

  /** Triggers a re-resolution of lyrics for the active track after an error. */
  retry(): void {
    if (this.disposed) {
      return;
    }
    this.lyricsStore?.retry();
  }

  /** Seeks the player to an absolute position (used by the full-page progress row). */
  async seekTo(position: number): Promise<void> {
    const store = this.playerStore;
    if (this.disposed || store === null || !Number.isFinite(position) || position < 0) {
      return;
    }
    await store.seek(position);
  }

  async seekToLine(index: number): Promise<void> {
    if (!this.canSeek() || index < 0 || index >= this.lines.length) {
      return;
    }
    const store = this.playerStore;
    const line = this.lines[index];
    if (store === null || !Number.isFinite(line.time) || line.time < 0) {
      return;
    }
    const targetTrackKey = this.trackKey;
    const generation = this.seekGeneration + 1;
    this.seekGeneration = generation;
    this.seekLoading = true;
    try {
      await store.seek(line.time);
      if (this.isCurrentSeek(generation, targetTrackKey)) {
        this.followPaused = false;
      }
    } catch (_error) {
      // PlayerStore publishes the sanitized playback error and preserves lyrics.
    } finally {
      if (this.isCurrentSeek(generation, targetTrackKey)) {
        this.seekLoading = false;
      }
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.seekGeneration++;
    this.lyricsStore?.cancelCandidateSearch();
    this.lyricsStore?.unsubscribe(this);
    this.playerStore?.unsubscribe(this);
    this.lyricsStore = null;
    this.playerStore = null;
    this.candidatesOpen = false;
    this.resetCandidates();
  }

  private applyLyrics(snapshot: LyricsStoreSnapshot): void {
    const trackChanged = snapshot.trackKey !== this.trackKey;
    this.status = snapshot.status;
    this.trackKey = snapshot.trackKey;
    this.lines = cloneLines(snapshot.lines);
    this.trackTitle = snapshot.trackTitle;
    this.canRetry = snapshot.canRetry;
    this.contentGeneration++;
    if (trackChanged) {
      this.seekGeneration++;
      this.followPaused = false;
      this.seekLoading = false;
      this.currentIndex = -1;
      this.candidatesOpen = false;
      this.resetCandidates();
    }
    this.updateCurrentIndex();
  }

  private applyCandidates(snapshot: LyricsCandidateSnapshot): void {
    if (snapshot.status === 'idle') {
      this.candidatesOpen = false;
      this.resetCandidates();
      return;
    }
    this.candidateStatus = snapshot.status;
    this.candidates = cloneCandidates(snapshot.candidates);
    this.selectedCandidateId = snapshot.selectedCandidateId;
    this.candidateError = cloneError(snapshot.error);
  }

  private resetCandidates(): void {
    this.candidateStatus = 'idle';
    this.candidates = [];
    this.selectedCandidateId = '';
    this.candidateError = null;
  }

  private syncPlayer(snapshot: PlayerViewSnapshot): void {
    const nextTrackKey = snapshot.track === null ? '' : snapshot.track.key;
    if (nextTrackKey !== this.playerTrackKey) {
      this.playerTrackKey = nextTrackKey;
      this.seekGeneration++;
      this.followPaused = false;
      this.seekLoading = false;
      this.transportBusy = false;
      this.currentIndex = -1;
    }
    this.track = snapshot.track;
    this.playbackStatus = snapshot.status;
    const store = this.playerStore;
    if (store !== null) {
      this.position = safePosition(store.progress.position);
      this.duration = safePosition(store.progress.duration);
    }
    this.updateCurrentIndex();
  }

  private updateCurrentIndex(): void {
    const nextIndex = this.status === 'ready' ?
      findActiveLyricIndex(this.lines, true, this.position) : -1;
    if (nextIndex !== this.currentIndex) {
      this.currentIndex = nextIndex;
    }
  }

  private isCurrentSeek(generation: number, trackKey: string): boolean {
    return !this.disposed && generation === this.seekGeneration && trackKey === this.trackKey;
  }
}

function cloneLines(lines: LyricLine[]): LyricLine[] {
  return lines.map((line: LyricLine): LyricLine => {
    return {
      time: line.time,
      text: line.text
    };
  });
}

function cloneCandidates(candidates: LyricCandidate[]): LyricCandidate[] {
  return candidates.map((candidate: LyricCandidate): LyricCandidate => {
    return {
      id: candidate.id,
      trackName: candidate.trackName,
      artistName: candidate.artistName,
      albumName: candidate.albumName,
      duration: candidate.duration,
      image: ''
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

function safePosition(position: number): number {
  return Number.isFinite(position) ? Math.max(0, position) : 0;
}
