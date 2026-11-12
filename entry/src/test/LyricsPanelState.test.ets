import { describe, expect, it } from '@ohos/hypium';
import {
  findActiveLyricIndex,
  LyricsPanelState
} from '../main/ets/components/native/LyricsPanelState';
import { LyricsGateway, LyricsStore } from '../main/ets/state/LyricsStore';
import {
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore
} from '../main/ets/state/PlayerStore';
import {
  LyricCandidate,
  LyricLine,
  LyricResult,
  MobileTrack,
  PlaybackState,
  PlayerMode,
  PlayerSessionSnapshot,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';
import { wait } from '../main/ets/util/Errors';

class ImmediatePanelScheduler implements PlayerProgressScheduler {
  private time: number = 0;

  now(): number {
    return this.time;
  }

  schedule(callback: () => void, delayMs: number): number {
    this.time += delayMs;
    callback();
    return 1;
  }

  cancel(_timerId: number): void {
  }
}

class PanelLyricsCall {
  readonly promise: Promise<LyricResult | null>;
  private resolveCallback: ((result: LyricResult | null) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor() {
    this.promise = new Promise<LyricResult | null>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: LyricResult | null): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }

  reject(error: Object): void {
    const callback = this.rejectCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

class PanelCandidateSearchCall {
  readonly query: string;
  readonly promise: Promise<LyricCandidate[]>;
  private resolveCallback: ((result: LyricCandidate[]) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor(query: string) {
    this.query = query;
    this.promise = new Promise<LyricCandidate[]>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: LyricCandidate[]): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }

  reject(error: Object): void {
    const callback = this.rejectCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

class PanelCandidateChoiceCall {
  readonly params: Record<string, Object>;
  readonly promise: Promise<LyricResult | null>;
  private resolveCallback: ((result: LyricResult | null) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor(params: Record<string, Object>) {
    this.params = params;
    this.promise = new Promise<LyricResult | null>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: LyricResult | null): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }

  reject(error: Object): void {
    const callback = this.rejectCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

class PanellyricsGateway implements LyricsGateway {
  readonly resolveRequests: PanelLyricsCall[] = [];
  readonly searchRequests: PanelCandidateSearchCall[] = [];
  readonly chooseRequests: PanelCandidateChoiceCall[] = [];

  resolve(_params: Record<string, Object>): Promise<LyricResult | null> {
    const call = new PanelLyricsCall();
    this.resolveRequests.push(call);
    return call.promise;
  }

  search(query: string): Promise<LyricCandidate[]> {
    const call = new PanelCandidateSearchCall(query);
    this.searchRequests.push(call);
    return call.promise;
  }

  choose(params: Record<string, Object>): Promise<LyricResult | null> {
    const call = new PanelCandidateChoiceCall(params);
    this.chooseRequests.push(call);
    return call.promise;
  }
}

class PanelPlayerTarget implements PlayerCommandTarget {
  state: PlaybackState = emptyPlaybackState();
  seekPosition: number = -1;

  loadQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  appendToQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  removeFromQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  clearQueue(): Promise<PlaybackState> {
    return this.complete();
  }

  restoreSession(_session: PlayerSessionSnapshot): Promise<PlaybackState> {
    return this.complete();
  }

  play(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  pause(): Promise<PlaybackState> {
    return this.complete();
  }

  seek(params: Record<string, Object>): Promise<PlaybackState> {
    this.seekPosition = params.position as number;
    this.state.position = this.seekPosition;
    return this.complete();
  }

  next(): Promise<PlaybackState> {
    return this.complete();
  }

  previous(): Promise<PlaybackState> {
    return this.complete();
  }

  skipPrevious(): Promise<PlaybackState> {
    return this.complete();
  }

  setMode(params: Record<string, Object>): Promise<PlaybackState> {
    this.state.mode = params.mode as PlayerMode;
    return this.complete();
  }

  setQuality(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  snapshot(): PlaybackState {
    return cloneState(this.state);
  }

  private complete(): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }
}

function panelTrack(label: string): MobileTrack {
  return {
    key: `track:${label}`,
    bvid: `BV${label}`,
    aid: 1,
    cid: 2,
    title: `Song ${label}`,
    artist: 'Artist',
    coverUrl: '',
    duration: 180,
    playCount: 0
  };
}

function panelPlayback(track: MobileTrack, status: 'playing' | 'paused', position: number): PlaybackState {
  const state = emptyPlaybackState();
  state.status = status;
  state.track = track;
  state.position = position;
  state.duration = track.duration;
  return state;
}

function panelLyrics(times: number[], texts: string[], synced: boolean = true): LyricResult {
  const lines: LyricLine[] = texts.map((text: string, index: number): LyricLine => {
    return {
      time: synced ? times[index] : -1,
      text: text
    };
  });
  return {
    lines: lines,
    synced: synced,
    trackName: 'Song',
    artistName: 'Artist',
    sourceId: 'source'
  };
}

function panelCandidate(id: string): LyricCandidate {
  return {
    id: id,
    trackName: `Candidate ${id}`,
    artistName: 'Candidate Artist',
    albumName: 'Candidate Album',
    duration: 240,
    image: 'https://example.invalid/cover.jpg?token=secret'
  };
}

function cloneState(state: PlaybackState): PlaybackState {
  const result = emptyPlaybackState();
  result.status = state.status;
  result.track = state.track === null ? null : {
    key: state.track.key,
    bvid: state.track.bvid,
    aid: state.track.aid,
    cid: state.track.cid,
    title: state.track.title,
    artist: state.track.artist,
    coverUrl: state.track.coverUrl,
    duration: state.track.duration,
    playCount: state.track.playCount
  };
  result.position = state.position;
  result.duration = state.duration;
  result.volume = state.volume;
  result.mode = state.mode;
  result.queue = [];
  result.queueIndex = state.queueIndex;
  if (state.error !== undefined) {
    result.error = state.error;
  }
  return result;
}

function buildReadyPanel(): LyricsStoreHarness {
  const player = new PlayerStore(new ImmediatePanelScheduler());
  const target = new PanelPlayerTarget();
  const track = panelTrack('alpha');
  target.state = panelPlayback(track, 'playing', 0);
  player.bind(target);
  const gateway = new PanellyricsGateway();
  const lyricsStore = new LyricsStore(player, gateway);
  lyricsStore.attach();
  const panel = new LyricsPanelState(lyricsStore, player);
  panel.attach();
  return {
    player: player,
    target: target,
    gateway: gateway,
    lyricsStore: lyricsStore,
    panel: panel,
    track: track
  };
}

interface LyricsStoreHarness {
  player: PlayerStore;
  target: PanelPlayerTarget;
  gateway: PanellyricsGateway;
  lyricsStore: LyricsStore;
  panel: LyricsPanelState;
  track: MobileTrack;
}

export default function lyricsPanelStateTest(): void {
  describe('LyricsPanelState', () => {
    it('findsTheCurrentLineAcrossPlayPauseSeekAndResume', 0, async () => {
      const harness = buildReadyPanel();
      harness.gateway.resolveRequests[0].resolve(panelLyrics([1, 5, 10], ['one', 'two', 'three']));
      await harness.gateway.resolveRequests[0].promise;
      await wait(0);

      expect(harness.panel.status).assertEqual('ready');
      expect(harness.panel.currentIndex).assertEqual(-1);

      harness.player.onProgress(6, 180);
      expect(harness.panel.currentIndex).assertEqual(1);

      harness.player.onState(panelPlayback(harness.track, 'paused', 6));
      expect(harness.panel.currentIndex).assertEqual(1);

      await harness.panel.seekToLine(2);
      expect(harness.target.seekPosition).assertEqual(10);
      expect(harness.panel.currentIndex).assertEqual(2);
      expect(harness.panel.seekLoading).assertFalse();

      harness.player.onState(panelPlayback(harness.track, 'playing', 10));
      harness.player.onProgress(11, 180);
      expect(harness.panel.currentIndex).assertEqual(2);
    });

    it('pausesFollowingAfterManualBrowsingAndResumesExplicitly', 0, async () => {
      const harness = buildReadyPanel();
      harness.gateway.resolveRequests[0].resolve(panelLyrics([0, 5, 10], ['one', 'two', 'three']));
      await harness.gateway.resolveRequests[0].promise;
      await wait(0);

      harness.panel.pauseFollow();
      harness.player.onProgress(11, 180);
      expect(harness.panel.followPaused).assertTrue();
      expect(harness.panel.currentIndex).assertEqual(2);

      harness.panel.resumeFollow();
      expect(harness.panel.followPaused).assertFalse();
    });

    it('seeksThroughPlayerStoreAndRejectsUnsyncedLines', 0, async () => {
      const harness = buildReadyPanel();
      harness.gateway.resolveRequests[0].resolve(panelLyrics([0, 5], ['one', 'two']));
      await harness.gateway.resolveRequests[0].promise;
      await wait(0);

      await harness.panel.seekToLine(1);
      expect(harness.target.seekPosition).assertEqual(5);

      harness.player.onState(panelPlayback(panelTrack('plain'), 'playing', 0));
      harness.gateway.resolveRequests[1].resolve(panelLyrics([0, 0], ['plain one', 'plain two'], false));
      await harness.gateway.resolveRequests[1].promise;
      await wait(0);
      expect(harness.panel.status).assertEqual('unsynced');
      expect(harness.panel.currentIndex).assertEqual(-1);
      expect(harness.panel.canSeek()).assertFalse();
    });

    it('resetsHighlightAndFollowingWhenTheTrackChanges', 0, async () => {
      const harness = buildReadyPanel();
      harness.gateway.resolveRequests[0].resolve(panelLyrics([0, 5, 10], ['one', 'two', 'three']));
      await harness.gateway.resolveRequests[0].promise;
      await wait(0);
      harness.player.onProgress(6, 180);
      harness.panel.pauseFollow();

      harness.player.onState(panelPlayback(panelTrack('beta'), 'playing', 0));
      expect(harness.panel.status).assertEqual('loading');
      expect(harness.panel.currentIndex).assertEqual(-1);
      expect(harness.panel.followPaused).assertFalse();

      harness.gateway.resolveRequests[1].resolve(panelLyrics([2, 8], ['beta one', 'beta two']));
      await harness.gateway.resolveRequests[1].promise;
      await wait(0);
      expect(harness.panel.trackKey).assertEqual('track:beta');
      expect(harness.panel.lines[0].text).assertEqual('beta one');
    });

    it('keepsEmptyAndErrorStatesIndependentFromPlayback', 0, async () => {
      const emptyHarness = buildReadyPanel();
      emptyHarness.gateway.resolveRequests[0].resolve(null);
      await emptyHarness.gateway.resolveRequests[0].promise;
      await wait(0);
      expect(emptyHarness.panel.status).assertEqual('empty');
      expect(emptyHarness.player.snapshot.status).assertEqual('playing');

      const errorHarness = buildReadyPanel();
      errorHarness.gateway.resolveRequests[0].reject(new Error('lyrics unavailable'));
      await wait(0);
      expect(errorHarness.panel.status).assertEqual('error');
      expect(errorHarness.panel.canSeek()).assertFalse();
      expect(errorHarness.player.snapshot.status).assertEqual('playing');
    });

    it('opensCandidateSearchRetriesFailuresAndCancelsOnClose', 0, async () => {
      const harness = buildReadyPanel();
      harness.gateway.resolveRequests[0].resolve(panelLyrics([0, 5], ['one', 'two']));
      await harness.gateway.resolveRequests[0].promise;
      await wait(0);

      harness.panel.openCandidateSearch();
      expect(harness.panel.candidatesOpen).assertTrue();
      expect(harness.panel.candidateStatus).assertEqual('loading');
      expect(harness.gateway.searchRequests.length).assertEqual(1);
      expect(harness.gateway.searchRequests[0].query).assertEqual('Song alpha Artist');

      harness.gateway.searchRequests[0].reject(new Error('search failed'));
      await wait(0);
      expect(harness.panel.candidateStatus).assertEqual('error');

      harness.panel.retryCandidateSearch();
      expect(harness.gateway.searchRequests.length).assertEqual(2);
      harness.gateway.searchRequests[1].resolve([]);
      await wait(0);
      expect(harness.panel.candidateStatus).assertEqual('empty');

      harness.panel.closeCandidateSearch();
      expect(harness.panel.candidatesOpen).assertFalse();
      expect(harness.panel.candidateStatus).assertEqual('idle');
      expect(harness.lyricsStore.candidateSnapshot.status).assertEqual('idle');
    });

    it('appliesTheSelectedCandidateOnceAndFollowsCurrentPlaybackTime', 0, async () => {
      const harness = buildReadyPanel();
      harness.gateway.resolveRequests[0].resolve(panelLyrics([0, 4], ['old one', 'old two']));
      await harness.gateway.resolveRequests[0].promise;
      await wait(0);
      harness.panel.onProgress({ position: 6, duration: 180 });

      harness.panel.openCandidateSearch();
      harness.gateway.searchRequests[0].resolve([panelCandidate('candidate-1')]);
      await wait(0);

      expect(harness.panel.candidateStatus).assertEqual('ready');
      expect(harness.panel.candidates[0].trackName).assertEqual('Candidate candidate-1');
      expect(harness.panel.candidates[0].artistName).assertEqual('Candidate Artist');
      expect(harness.panel.candidates[0].albumName).assertEqual('Candidate Album');
      expect(harness.panel.candidates[0].duration).assertEqual(240);
      expect(harness.panel.candidates[0].image).assertEqual('');

      const firstSelection = harness.panel.selectCandidate('candidate-1');
      const duplicateSelection = harness.panel.selectCandidate('candidate-1');
      expect(harness.gateway.chooseRequests.length).assertEqual(1);
      expect(harness.panel.selectedCandidateId).assertEqual('candidate-1');

      harness.gateway.chooseRequests[0].resolve(panelLyrics([1, 5, 10],
        ['selected one', 'selected two', 'selected three']));
      await Promise.all([firstSelection, duplicateSelection]);
      await wait(0);

      expect(harness.panel.candidatesOpen).assertFalse();
      expect(harness.panel.status).assertEqual('ready');
      expect(harness.panel.lines[0].text).assertEqual('selected one');
      expect(harness.panel.currentIndex).assertEqual(1);
      harness.panel.onProgress({ position: 11, duration: 180 });
      expect(harness.panel.currentIndex).assertEqual(2);
    });

    it('closesAndInvalidatesCandidatesWhenTheTrackChanges', 0, async () => {
      const harness = buildReadyPanel();
      harness.gateway.resolveRequests[0].resolve(panelLyrics([0, 5], ['one', 'two']));
      await harness.gateway.resolveRequests[0].promise;
      await wait(0);

      harness.panel.openCandidateSearch();
      expect(harness.gateway.searchRequests.length).assertEqual(1);
      harness.player.onState(panelPlayback(panelTrack('changed'), 'playing', 0));

      expect(harness.panel.candidatesOpen).assertFalse();
      expect(harness.panel.candidateStatus).assertEqual('idle');

      harness.gateway.searchRequests[0].resolve([panelCandidate('stale-candidate')]);
      await wait(0);
      expect(harness.panel.candidateStatus).assertEqual('idle');
      expect(harness.panel.candidates.length).assertEqual(0);
      expect(harness.panel.trackKey).assertEqual('track:changed');
    });

    it('disposeCancelsPendingCandidateSearchWithoutLateUiUpdates', 0, async () => {
      const harness = buildReadyPanel();
      harness.gateway.resolveRequests[0].resolve(panelLyrics([0, 5], ['one', 'two']));
      await harness.gateway.resolveRequests[0].promise;
      await wait(0);

      harness.panel.openCandidateSearch();
      harness.panel.dispose();
      harness.gateway.searchRequests[0].resolve([panelCandidate('late-candidate')]);
      await wait(0);

      expect(harness.panel.candidatesOpen).assertFalse();
      expect(harness.panel.candidateStatus).assertEqual('idle');
      expect(harness.panel.candidates.length).assertEqual(0);
    });

    it('usesTheLastLineAtTheSameTimestamp', 0, () => {
      const lines: LyricLine[] = [
        { time: 0, text: 'first' },
        { time: 5, text: 'second' },
        { time: 5, text: 'second duplicate' },
        { time: 9, text: 'third' }
      ];
      expect(findActiveLyricIndex(lines, true, -1)).assertEqual(0);
      expect(findActiveLyricIndex(lines, true, 5)).assertEqual(2);
      expect(findActiveLyricIndex(lines, true, 8)).assertEqual(2);
      expect(findActiveLyricIndex(lines, false, 8)).assertEqual(-1);
    });
  });
}
