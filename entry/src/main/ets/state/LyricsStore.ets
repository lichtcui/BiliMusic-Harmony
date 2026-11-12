import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AppError,
  LyricCandidate,
  LyricLine,
  LyricResult,
  MobileTrack
} from '../types/MobileTypes';
import { toAppError } from '../util/Errors';
import {
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
} from './PlayerStore';

const DOMAIN = 0x424D;
const TAG = 'WispMusicLyricsStore';
const SAFE_LYRICS_ERROR_MESSAGE = '歌词加载失败，请稍后重试。';
const SAFE_LYRICS_SEARCH_ERROR_MESSAGE = '歌词搜索失败，请稍后重试。';
const SAFE_LYRICS_SELECTION_ERROR_MESSAGE = '所选歌词暂时无法使用，请稍后重试。';
const MAX_CANDIDATES = 20;

export type LyricsStatus = 'idle' | 'loading' | 'ready' | 'unsynced' | 'empty' | 'error';
export type LyricsCandidateStatus = 'idle' | 'loading' | 'ready' | 'empty' | 'error';

export interface LyricsStoreSnapshot {
  status: LyricsStatus;
  trackKey: string;
  trackTitle: string;
  lines: LyricLine[];
  synced: boolean;
  error: AppError | null;
  canRetry: boolean;
}

export interface LyricsStoreListener {
  onLyrics(snapshot: LyricsStoreSnapshot): void;
  onCandidates(snapshot: LyricsCandidateSnapshot): void;
}

export interface LyricsCandidateSnapshot {
  status: LyricsCandidateStatus;
  trackKey: string;
  candidates: LyricCandidate[];
  selectedCandidateId: string;
  error: AppError | null;
}

export interface LyricsGateway {
  resolve(params: Record<string, Object>): Promise<LyricResult | null>;
  search(query: string): Promise<LyricCandidate[]>;
  choose(params: Record<string, Object>): Promise<LyricResult | null>;
}

@Observed
export class LyricsStore implements PlayerStoreListener {
  @Track snapshot: LyricsStoreSnapshot = idleSnapshot();
  @Track candidateSnapshot: LyricsCandidateSnapshot = idleCandidateSnapshot();

  private readonly playerStore: PlayerStore;
  private readonly gateway: LyricsGateway;
  private activeTrack: MobileTrack | null = null;
  private activeTrackKey: string = '';
  private generation: number = 0;
  private candidateGeneration: number = 0;
  private disposed: boolean = false;
  private readonly listeners: LyricsStoreListener[] = [];

  constructor(playerStore: PlayerStore, gateway: LyricsGateway) {
    this.playerStore = playerStore;
    this.gateway = gateway;
    this.syncTrack(this.playerStore.snapshot.track);
  }

  /**
   * Subscribes this store to the player store.
   *
   * Must be called after construction and through the observed instance: @Observed wraps the object
   * only after the constructor returns, so subscribing `this` inside the constructor hands the player
   * store the raw target. Track-change callbacks would then write through the raw object and bypass
   * the proxy, leaving @ObjectLink pages stale. Call attach() once the instance is
   * stored in page state.
   */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.playerStore.subscribe(this);
  }

  read(): LyricsStoreSnapshot {
    return cloneSnapshot(this.snapshot);
  }

  readCandidates(): LyricsCandidateSnapshot {
    return cloneCandidateSnapshot(this.candidateSnapshot);
  }

  subscribe(listener: LyricsStoreListener): void {
    if (!this.disposed && this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: LyricsStoreListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  onState(snapshot: PlayerViewSnapshot): void {
    if (!this.disposed) {
      this.syncTrack(snapshot.track);
    }
  }

  onProgress(_progress: PlayerProgressSnapshot): void {
  }

  onError(_error: AppError): void {
    // Player failures stay in PlayerStore and do not replace lyrics state.
  }

  async searchCandidates(): Promise<void> {
    if (this.disposed || this.activeTrack === null ||
      this.candidateSnapshot.status === 'loading' ||
      this.candidateSnapshot.selectedCandidateId.length > 0) {
      return;
    }
    const track = cloneTrack(this.activeTrack);
    if (track === null) {
      return;
    }
    const generation = this.candidateGeneration + 1;
    this.candidateGeneration = generation;
    this.updateCandidateSnapshot({
      status: 'loading',
      trackKey: track.key,
      candidates: [],
      selectedCandidateId: '',
      error: null
    });
    try {
      const candidates = sanitizeCandidates(await this.gateway.search(lyricsSearchQuery(track)));
      if (!this.isCurrentCandidates(generation, track.key)) {
        return;
      }
      this.updateCandidateSnapshot({
        status: candidates.length > 0 ? 'ready' : 'empty',
        trackKey: track.key,
        candidates: candidates,
        selectedCandidateId: '',
        error: null
      });
    } catch (error) {
      if (!this.isCurrentCandidates(generation, track.key)) {
        return;
      }
      const safe = sanitizeError(toAppError(error as Object),
        SAFE_LYRICS_SEARCH_ERROR_MESSAGE);
      this.updateCandidateSnapshot({
        status: 'error',
        trackKey: track.key,
        candidates: [],
        selectedCandidateId: '',
        error: safe
      });
      hilog.warn(DOMAIN, TAG, 'lyrics candidate search failed code=%{public}s', safe.code);
    }
  }

  async selectCandidate(candidateId: string): Promise<boolean> {
    const id = candidateId.trim();
    if (this.disposed || this.activeTrack === null || id.length === 0 ||
      this.candidateSnapshot.selectedCandidateId.length > 0 ||
      !hasCandidate(this.candidateSnapshot.candidates, id)) {
      return false;
    }
    const track = cloneTrack(this.activeTrack);
    if (track === null) {
      return false;
    }
    const candidateGeneration = this.candidateGeneration;
    const lyricsGeneration = this.generation;
    this.updateCandidateSnapshot({
      status: this.candidateSnapshot.status,
      trackKey: this.candidateSnapshot.trackKey,
      candidates: cloneCandidates(this.candidateSnapshot.candidates),
      selectedCandidateId: id,
      error: null
    });
    const params: Record<string, Object> = {};
    params.track = track;
    params.candidateId = id;
    try {
      const result = await this.gateway.choose(params);
      if (!this.isCurrentSelection(candidateGeneration, lyricsGeneration, track.key)) {
        return false;
      }
      if (result === null || result.lines.length === 0) {
        this.updateCandidateSnapshot({
          status: 'ready',
          trackKey: track.key,
          candidates: cloneCandidates(this.candidateSnapshot.candidates),
          selectedCandidateId: '',
          error: {
            code: 'lyrics.selectionUnavailable',
            message: SAFE_LYRICS_SELECTION_ERROR_MESSAGE,
            retryable: true
          }
        });
        return false;
      }
      const nextGeneration = this.generation + 1;
      this.generation = nextGeneration;
      this.applyResult(result, nextGeneration);
      this.updateCandidateSnapshot(idleCandidateSnapshot());
      return true;
    } catch (error) {
      if (!this.isCurrentSelection(candidateGeneration, lyricsGeneration, track.key)) {
        return false;
      }
      const safe = sanitizeError(toAppError(error as Object),
        SAFE_LYRICS_SELECTION_ERROR_MESSAGE);
      this.updateCandidateSnapshot({
        status: 'ready',
        trackKey: track.key,
        candidates: cloneCandidates(this.candidateSnapshot.candidates),
        selectedCandidateId: '',
        error: safe
      });
      hilog.warn(DOMAIN, TAG, 'lyrics candidate selection failed code=%{public}s', safe.code);
      return false;
    }
  }

  cancelCandidateSearch(): void {
    if (this.disposed) {
      return;
    }
    this.candidateGeneration++;
    this.updateCandidateSnapshot(idleCandidateSnapshot());
  }

  /**
   * Re-attempts lyric resolution for the active track after a load failure.
   *
   * Unlike syncTrack (which fires on track change), this stays on the current track and leaves any
   * open candidate search untouched, so a lyrics error-retry never throws away a pending selection.
   */
  async retry(): Promise<void> {
    if (this.disposed || this.activeTrack === null) {
      return;
    }
    const track = cloneTrack(this.activeTrack);
    if (track === null) {
      return;
    }
    const generation = this.generation + 1;
    this.generation = generation;
    this.updateSnapshot(loadingSnapshot(track));
    await this.load(track, generation);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.generation++;
    this.candidateGeneration++;
    this.playerStore.unsubscribe(this);
    this.activeTrack = null;
    this.activeTrackKey = '';
    this.candidateSnapshot = idleCandidateSnapshot();
    this.listeners.splice(0, this.listeners.length);
    this.updateSnapshot(idleSnapshot());
  }

  private syncTrack(track: MobileTrack | null): void {
    const nextKey = track === null ? '' : track.key;
    if (nextKey === this.activeTrackKey) {
      return;
    }

    this.generation++;
    this.candidateGeneration++;
    this.activeTrack = cloneTrack(track);
    this.activeTrackKey = nextKey;
    this.updateCandidateSnapshot(idleCandidateSnapshot());
    if (track === null) {
      this.updateSnapshot(idleSnapshot());
      return;
    }

    this.updateSnapshot(loadingSnapshot(track));
    const generation = this.generation;
    void this.load(track, generation);
  }

  private async load(track: MobileTrack, generation: number): Promise<void> {
    const params: Record<string, Object> = {};
    params.track = cloneTrack(track) as MobileTrack;
    try {
      const result = await this.gateway.resolve(params);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.applyResult(result, generation);
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      const safe = sanitizeError(toAppError(error as Object));
      this.updateSnapshot({
        status: 'error',
        trackKey: this.activeTrackKey,
        trackTitle: this.activeTrack === null ? '' : this.activeTrack.title,
        lines: [],
        synced: false,
        error: safe,
        canRetry: safe.retryable
      });
      hilog.warn(DOMAIN, TAG, 'lyrics load failed code=%{public}s', safe.code);
    }
  }

  private applyResult(result: LyricResult | null, generation: number): void {
    if (!this.isCurrent(generation)) {
      return;
    }
    const lines = result === null ? [] : cloneLines(result.lines);
    if (lines.length === 0) {
      this.updateSnapshot({
        status: 'empty',
        trackKey: this.activeTrackKey,
        trackTitle: this.activeTrack === null ? '' : this.activeTrack.title,
        lines: [],
        synced: false,
        error: null,
        canRetry: false
      });
      return;
    }
    const synced = result !== null && result.synced;
    this.updateSnapshot({
      status: synced ? 'ready' : 'unsynced',
      trackKey: this.activeTrackKey,
      trackTitle: this.activeTrack === null ? '' : this.activeTrack.title,
      lines: lines,
      synced: synced,
      error: null,
      canRetry: false
    });
  }

  private isCurrent(generation: number): boolean {
    return !this.disposed && generation === this.generation;
  }

  private isCurrentCandidates(generation: number, trackKey: string): boolean {
    return !this.disposed && generation === this.candidateGeneration &&
      this.activeTrackKey === trackKey;
  }

  private isCurrentSelection(generation: number, lyricsGeneration: number,
    trackKey: string): boolean {
    return this.isCurrentCandidates(generation, trackKey) && lyricsGeneration === this.generation;
  }

  private updateSnapshot(snapshot: LyricsStoreSnapshot): void {
    this.snapshot = snapshot;
    if (this.disposed) {
      return;
    }
    const listeners = this.listeners.slice();
    for (const listener of listeners) {
      try {
        listener.onLyrics(cloneSnapshot(snapshot));
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'lyrics listener failed');
      }
    }
  }

  private updateCandidateSnapshot(snapshot: LyricsCandidateSnapshot): void {
    this.candidateSnapshot = snapshot;
    if (this.disposed) {
      return;
    }
    const listeners = this.listeners.slice();
    for (const listener of listeners) {
      try {
        listener.onCandidates(cloneCandidateSnapshot(snapshot));
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'lyrics candidate listener failed');
      }
    }
  }
}

function idleSnapshot(): LyricsStoreSnapshot {
  return {
    status: 'idle',
    trackKey: '',
    trackTitle: '',
    lines: [],
    synced: false,
    error: null,
    canRetry: false
  };
}

function loadingSnapshot(track: MobileTrack): LyricsStoreSnapshot {
  return {
    status: 'loading',
    trackKey: track.key,
    trackTitle: track.title,
    lines: [],
    synced: false,
    error: null,
    canRetry: false
  };
}

function idleCandidateSnapshot(): LyricsCandidateSnapshot {
  return {
    status: 'idle',
    trackKey: '',
    candidates: [],
    selectedCandidateId: '',
    error: null
  };
}

function sanitizeError(error: AppError, fallbackMessage: string = SAFE_LYRICS_ERROR_MESSAGE): AppError {
  const cleanCode = error.code.trim();
  const code = /^[a-zA-Z0-9._-]{1,80}$/u.test(cleanCode) &&
    !/(https?|cookie|authorization|qrcode|access|token|account|mid)/iu.test(cleanCode)
    ? cleanCode
    : 'lyrics.error';
  const message = error.message.trim().slice(0, 240);
  const safeMessage = message.length === 0 ||
    /(https?:\/\/|cookie|authorization|bearer|sessdata|bili_jct|csrf|qrcode[_-]?key|access[_-]?token|refresh[_-]?token|token|account|secret|password|\bmid\s*=)/iu.test(message)
    ? fallbackMessage
    : message;
  return {
    code: code,
    message: safeMessage,
    retryable: error.retryable
  };
}

function cloneSnapshot(snapshot: LyricsStoreSnapshot): LyricsStoreSnapshot {
  return {
    status: snapshot.status,
    trackKey: snapshot.trackKey,
    trackTitle: snapshot.trackTitle,
    lines: cloneLines(snapshot.lines),
    synced: snapshot.synced,
    error: cloneError(snapshot.error),
    canRetry: snapshot.canRetry
  };
}

function cloneCandidateSnapshot(snapshot: LyricsCandidateSnapshot): LyricsCandidateSnapshot {
  return {
    status: snapshot.status,
    trackKey: snapshot.trackKey,
    candidates: cloneCandidates(snapshot.candidates),
    selectedCandidateId: snapshot.selectedCandidateId,
    error: cloneError(snapshot.error)
  };
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

function sanitizeCandidates(candidates: LyricCandidate[]): LyricCandidate[] {
  const result: LyricCandidate[] = [];
  const seen: Set<string> = new Set<string>();
  for (const candidate of candidates) {
    if (result.length >= MAX_CANDIDATES) {
      break;
    }
    const id = candidate.id.trim().slice(0, 80);
    const trackName = candidate.trackName.trim().slice(0, 300);
    if (id.length === 0 || trackName.length === 0 || seen.has(id) ||
      !/^[a-zA-Z0-9._-]{1,80}$/u.test(id) || isUnsafeCandidateText(id) ||
      isUnsafeCandidateText(trackName)) {
      continue;
    }
    seen.add(id);
    result.push({
      id: id,
      trackName: trackName,
      artistName: safeCandidateText(candidate.artistName),
      albumName: safeCandidateText(candidate.albumName),
      duration: Number.isFinite(candidate.duration) ? Math.max(0, candidate.duration) : 0,
      image: ''
    });
  }
  return result;
}

function safeCandidateText(value: string): string {
  const clean = value.trim().slice(0, 300);
  return isUnsafeCandidateText(clean) ? '' : clean;
}

function isUnsafeCandidateText(value: string): boolean {
  return /(https?:\/\/|www\.|cookie|authorization|bearer|sessdata|bili_jct|csrf|access[_-]?token|refresh[_-]?token|qrcode[_-]?key|secret|password|\bmid\s*=)/iu.test(value);
}

function hasCandidate(candidates: LyricCandidate[], candidateId: string): boolean {
  return candidates.some((candidate: LyricCandidate): boolean => candidate.id === candidateId);
}

export function lyricsSearchQuery(track: MobileTrack): string {
  const title = track.title.trim();
  const artist = track.artist.trim();
  return (artist.length > 0 ? `${title} ${artist}` : title).slice(0, 500);
}

function cloneLines(lines: LyricLine[]): LyricLine[] {
  const result: LyricLine[] = [];
  for (const line of lines.slice(0, 5000)) {
    const text = line.text.trim();
    if (text.length === 0) {
      continue;
    }
    result.push({
      time: Number.isFinite(line.time) ? line.time : -1,
      text: text.slice(0, 1000)
    });
  }
  return result;
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
