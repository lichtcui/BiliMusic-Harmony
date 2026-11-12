import { describe, expect, it } from '@ohos/hypium';
import {
  formatPlayerTime,
  nextPlayerMode,
  PlayerPageState
} from '../main/ets/components/native/PlayerPageState';
import {
  PLAYER_PROGRESS_INTERVAL_MS,
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore
} from '../main/ets/state/PlayerStore';
import {
  AppError,
  MobileTrack,
  PlaybackState,
  PlaybackStatus,
  PlayerMode,
  PlayerSessionSnapshot,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';
import { wait } from '../main/ets/util/Errors';

class PageTestScheduler implements PlayerProgressScheduler {
  nowMs: number = 1000;

  now(): number {
    return this.nowMs;
  }

  schedule(callback: () => void, delayMs: number): number {
    this.nowMs += delayMs;
    callback();
    return 1;
  }

  cancel(_timerId: number): void {
  }

  advance(milliseconds: number): void {
    this.nowMs += milliseconds;
  }
}

class FakePageCommandTarget implements PlayerCommandTarget {
  readonly calls: string[] = [];
  resultState: PlaybackState = emptyPlaybackState();
  requestedMode: PlayerMode | '' = '';
  seekPosition: number = -1;
  seekDelayMs: number = 0;

  loadQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('loadQueue');
    return this.complete();
  }

  appendToQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('appendToQueue');
    return this.complete();
  }

  removeFromQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('removeFromQueue');
    return this.complete();
  }

  clearQueue(): Promise<PlaybackState> {
    this.calls.push('clearQueue');
    return this.complete();
  }

  restoreSession(_session: PlayerSessionSnapshot): Promise<PlaybackState> {
    this.calls.push('restoreSession');
    return this.complete();
  }

  play(_params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('play');
    return this.complete();
  }

  pause(): Promise<PlaybackState> {
    this.calls.push('pause');
    return this.complete();
  }

  async seek(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('seek');
    this.seekPosition = params.position as number;
    if (this.seekDelayMs > 0) {
      await wait(this.seekDelayMs);
    }
    return cloneState(this.resultState);
  }

  next(): Promise<PlaybackState> {
    this.calls.push('next');
    return this.complete();
  }

  previous(): Promise<PlaybackState> {
    this.calls.push('previous');
    return this.complete();
  }

  skipPrevious(): Promise<PlaybackState> {
    this.calls.push('skipPrevious');
    return this.complete();
  }

  setMode(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('setMode');
    this.requestedMode = params.mode as PlayerMode;
    return this.complete();
  }

  setQuality(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  snapshot(): PlaybackState {
    return cloneState(this.resultState);
  }

  private complete(): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.resultState));
  }
}

function playerTrack(label: string, title: string = label, artist: string = 'Artist'): MobileTrack {
  return {
    key: `track:${label}`,
    bvid: `BV${label}`,
    aid: 1,
    cid: 2,
    title: title,
    artist: artist,
    coverUrl: `https://example.invalid/${label}.jpg`,
    duration: 180,
    playCount: 3
  };
}

function playbackState(track: MobileTrack | null, status: PlaybackStatus, position: number,
  duration: number, mode: PlayerMode, queueIndex: number,
  error: AppError | null = null): PlaybackState {
  const state = emptyPlaybackState();
  state.status = status;
  state.track = cloneTrack(track);
  state.position = position;
  state.duration = duration;
  state.mode = mode;
  state.queueIndex = queueIndex;
  if (error !== null) {
    state.error = cloneError(error);
  }
  return state;
}

function cloneState(state: PlaybackState): PlaybackState {
  const result = emptyPlaybackState();
  result.status = state.status;
  result.track = cloneTrack(state.track);
  result.position = state.position;
  result.duration = state.duration;
  result.volume = state.volume;
  result.mode = state.mode;
  result.queue = cloneTracks(state.queue);
  result.queueIndex = state.queueIndex;
  if (state.error !== undefined) {
    result.error = cloneError(state.error);
  }
  return result;
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

function cloneTracks(tracks: MobileTrack[]): MobileTrack[] {
  return tracks.map((track: MobileTrack): MobileTrack => cloneTrack(track) as MobileTrack);
}

function cloneError(error: AppError): AppError {
  return {
    code: error.code,
    message: error.message,
    retryable: error.retryable
  };
}

function emitProgress(store: PlayerStore, scheduler: PageTestScheduler,
  position: number, duration: number): void {
  scheduler.advance(PLAYER_PROGRESS_INTERVAL_MS);
  store.onProgress(position, duration);
}

export default function playerPageStateTest(): void {
  describe('PlayerPageState', () => {
    it('formatsTimesAndCyclesEveryPlaybackMode', 0, () => {
      expect(formatPlayerTime(0)).assertEqual('0:00');
      expect(formatPlayerTime(65)).assertEqual('1:05');
      expect(formatPlayerTime(3661)).assertEqual('1:01:01');
      expect(formatPlayerTime(-1, '--:--')).assertEqual('--:--');
      expect(formatPlayerTime(Number.NaN, '--:--')).assertEqual('--:--');

      expect(nextPlayerMode('sequence')).assertEqual('repeat-all');
      expect(nextPlayerMode('repeat-all')).assertEqual('repeat-one');
      expect(nextPlayerMode('repeat-one')).assertEqual('shuffle');
      expect(nextPlayerMode('shuffle')).assertEqual('sequence');
    });

    it('keepsADragDraftAndPendingSeekAheadOfLateProgress', 0, async () => {
      const scheduler = new PageTestScheduler();
      const store = new PlayerStore(scheduler);
      const target = new FakePageCommandTarget();
      store.bind(target);
      store.onState(playbackState(playerTrack('first'), 'playing', 10, 180, 'sequence', 0));
      target.resultState = playbackState(playerTrack('first'), 'playing', 10, 180, 'sequence', 0);
      const state = new PlayerPageState(store);
      state.attach();
      target.seekDelayMs = 5;

      state.beginSeek(80);
      state.updateSeek(90);
      emitProgress(store, scheduler, 12, 180);
      expect(state.dragging).assertTrue();
      expect(state.displayPosition()).assertEqual(90);

      const pending = state.submitSeek(80);
      expect(state.busyAction).assertEqual('seek');
      expect(state.isSeekPending()).assertTrue();
      expect(state.displayPosition()).assertEqual(80);

      emitProgress(store, scheduler, 12, 180);
      expect(state.displayPosition()).assertEqual(80);

      await pending;
      expect(target.seekPosition).assertEqual(80);
      expect(state.position).assertEqual(80);
      expect(state.isSeekPending()).assertFalse();
      expect(state.busyAction).assertEqual('');
      state.dispose();
    });

    it('routesTransportAndModeCommandsAndAcceptsConfirmedMode', 0, async () => {
      const scheduler = new PageTestScheduler();
      const store = new PlayerStore(scheduler);
      const target = new FakePageCommandTarget();
      store.bind(target);
      store.onState(playbackState(playerTrack('first'), 'paused', 20, 180, 'sequence', 0));
      target.resultState = playbackState(playerTrack('first'), 'paused', 20, 180, 'sequence', 0);
      const state = new PlayerPageState(store);
      state.attach();

      await state.togglePlayback();
      await state.previous();
      await state.skipPrevious();
      await state.next();
      await state.cycleMode();

      expect(target.calls.join(',')).assertEqual('play,previous,skipPrevious,next,setMode');
      expect(target.requestedMode).assertEqual('repeat-all');
      expect(state.mode).assertEqual('sequence');

      store.onState(playbackState(playerTrack('first'), 'playing', 22, 180, 'repeat-all', 0));
      expect(state.mode).assertEqual('repeat-all');
      expect(state.status).assertEqual('playing');
      expect(state.displayPosition()).assertEqual(22);
      state.dispose();
    });

    it('clearsOldSeekAndTrackStateWhenTheTrackChanges', 0, async () => {
      const scheduler = new PageTestScheduler();
      const store = new PlayerStore(scheduler);
      const target = new FakePageCommandTarget();
      store.bind(target);
      store.onState(playbackState(playerTrack('first'), 'playing', 50, 180, 'sequence', 0));
      target.resultState = playbackState(playerTrack('first'), 'playing', 50, 180, 'sequence', 0);
      const state = new PlayerPageState(store);
      state.attach();
      target.seekDelayMs = 5;

      const pending = state.submitSeek(100);
      expect(state.isSeekPending()).assertTrue();
      store.onState(playbackState(playerTrack('second'), 'playing', 4, 240, 'shuffle', 1));
      expect(state.track?.key).assertEqual('track:second');
      expect(state.isSeekPending()).assertFalse();
      expect(state.displayPosition()).assertEqual(4);

      await pending;
      expect(state.track?.key).assertEqual('track:second');
      expect(state.displayPosition()).assertEqual(4);
      state.dispose();
    });

    it('publishesErrorStateAndClearsErrorAfterRecovery', 0, () => {
      const scheduler = new PageTestScheduler();
      const store = new PlayerStore(scheduler);
      store.bind(new FakePageCommandTarget());
      store.onState(playbackState(playerTrack('first'), 'playing', 15, 180, 'sequence', 0));
      const state = new PlayerPageState(store);
      state.attach();

      store.onError({
        code: 'player.playbackFailed',
        message: '播放失败。',
        retryable: true
      });
      expect(state.status).assertEqual('error');
      expect(state.error?.code).assertEqual('player.playbackFailed');
      expect(state.canSeek()).assertFalse();
      expect(state.canTogglePlayback()).assertFalse();

      store.onState(playbackState(playerTrack('first'), 'playing', 16, 180, 'sequence', 0));
      expect(state.status).assertEqual('playing');
      expect(state.error === null).assertTrue();
      expect(state.displayPosition()).assertEqual(16);
      state.dispose();
    });

    it('retriesTheCurrentTrackOnceAndRestoresThePageAfterSuccess', 0, async () => {
      const scheduler = new PageTestScheduler();
      const store = new PlayerStore(scheduler);
      const target = new FakePageCommandTarget();
      store.bind(target);
      const track = playerTrack('first');
      store.onState(playbackState(track, 'error', 30, 180, 'sequence', 0, {
        code: 'player.prepareFailed',
        message: '音频暂时无法播放，请稍后重试。',
        retryable: true
      }));
      target.resultState = playbackState(track, 'playing', 30, 180, 'sequence', 0);
      const state = new PlayerPageState(store);
      state.attach();
      expect(state.canRetryPlayback()).assertTrue();

      const first = state.retryPlayback();
      const second = state.retryPlayback();
      expect(state.retryLoading).assertTrue();
      expect(state.busyAction).assertEqual('retry');

      await Promise.all([first, second]);

      expect(target.calls.join(',')).assertEqual('play');
      expect(state.retryLoading).assertFalse();
      expect(state.busyAction).assertEqual('');
      expect(state.error === null).assertTrue();
      expect(state.status).assertEqual('playing');
      expect(state.canRetryPlayback()).assertFalse();
      state.dispose();
    });
  });
}
