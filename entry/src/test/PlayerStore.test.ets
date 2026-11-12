import { describe, expect, it } from '@ohos/hypium';
import {
  PLAYER_PROGRESS_INTERVAL_MS,
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
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
import { NativeError, wait } from '../main/ets/util/Errors';
import { PLAYER_QUEUE_LIMIT } from '../main/ets/services/PlayerQueue';

class FakePlayerTimer {
  readonly id: number;
  readonly callback: () => void;
  readonly delayMs: number;
  cancelled: boolean = false;
  ran: boolean = false;

  constructor(id: number, callback: () => void, delayMs: number) {
    this.id = id;
    this.callback = callback;
    this.delayMs = delayMs;
  }
}

class FakePlayerScheduler implements PlayerProgressScheduler {
  nowMs: number = 1000;
  readonly timers: FakePlayerTimer[] = [];
  private nextId: number = 1;

  now(): number {
    return this.nowMs;
  }

  schedule(callback: () => void, delayMs: number): number {
    const timer = new FakePlayerTimer(this.nextId++, callback, delayMs);
    this.timers.push(timer);
    return timer.id;
  }

  cancel(timerId: number): void {
    for (const timer of this.timers) {
      if (timer.id === timerId) {
        timer.cancelled = true;
      }
    }
  }

  advance(milliseconds: number): void {
    this.nowMs += milliseconds;
  }

  pendingCount(): number {
    let count = 0;
    for (const timer of this.timers) {
      if (!timer.cancelled && !timer.ran) {
        count++;
      }
    }
    return count;
  }

  runNext(includeCancelled: boolean = false): void {
    for (const timer of this.timers) {
      if (!timer.ran && (includeCancelled || !timer.cancelled)) {
        timer.ran = true;
        timer.callback();
        return;
      }
    }
    throw new Error('No matching player timer');
  }
}

class FakePlayerTarget implements PlayerCommandTarget {
  readonly calls: string[] = [];
  resultState: PlaybackState = emptyPlaybackState();
  failure: Object | null = null;
  queueSize: number = 0;
  loadQueueKeys: string[] = [];
  appendQueueKeys: string[] = [];
  startIndex: number = -1;
  autoplay: boolean = false;
  restart: boolean = false;
  requestedIndex: number = -2;
  seekPosition: number = -1;
  requestedMode: PlayerMode | '' = '';
  removeIndex: number = -2;
  clearCallCount: number = 0;
  restoredSession: PlayerSessionSnapshot | null = null;
  playCallCount: number = 0;
  playDelayMs: number = 0;
  loadQueueDelayMs: number = 0;
  playResultState: PlaybackState | null = null;
  pauseResultState: PlaybackState | null = null;

  async loadQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('loadQueue');
    const queue = params.queue as MobileTrack[];
    this.queueSize = queue.length;
    this.loadQueueKeys = queue.map((track: MobileTrack): string => track.key);
    this.startIndex = params.startIndex as number;
    this.autoplay = params.autoplay as boolean;
    this.restart = params.restart as boolean;
    if (this.loadQueueDelayMs > 0) {
      await wait(this.loadQueueDelayMs);
    }
    return this.complete();
  }

  appendToQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('appendToQueue');
    this.appendQueueKeys = (params.queue as MobileTrack[]).map((track: MobileTrack): string => track.key);
    return this.complete();
  }

  removeFromQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('removeFromQueue');
    this.removeIndex = params.index as number;
    return this.complete();
  }

  clearQueue(): Promise<PlaybackState> {
    this.calls.push('clearQueue');
    this.clearCallCount++;
    return this.complete();
  }

  restoreSession(session: PlayerSessionSnapshot): Promise<PlaybackState> {
    this.calls.push('restoreSession');
    this.restoredSession = session;
    return this.complete();
  }

  async play(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('play');
    this.playCallCount++;
    this.requestedIndex = params.index === undefined ? -1 : params.index as number;
    const resultState = this.playResultState;
    if (this.playDelayMs > 0) {
      await wait(this.playDelayMs);
    }
    return this.complete(resultState);
  }

  pause(): Promise<PlaybackState> {
    this.calls.push('pause');
    return this.complete(this.pauseResultState);
  }

  seek(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('seek');
    this.seekPosition = params.position as number;
    return this.complete();
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

  private complete(resultState: PlaybackState | null = null): Promise<PlaybackState> {
    const failure = this.failure;
    this.failure = null;
    if (failure !== null) {
      return Promise.reject(failure);
    }
    return Promise.resolve(cloneState(resultState ?? this.resultState));
  }
}

class RecordingPlayerListener implements PlayerStoreListener {
  readonly events: string[] = [];
  readonly states: PlayerViewSnapshot[] = [];
  readonly progressValues: PlayerProgressSnapshot[] = [];
  readonly errors: AppError[] = [];

  onState(snapshot: PlayerViewSnapshot): void {
    this.events.push('state');
    this.states.push(cloneView(snapshot));
  }

  onProgress(progress: PlayerProgressSnapshot): void {
    this.events.push('progress');
    this.progressValues.push(cloneProgress(progress));
  }

  onError(error: AppError): void {
    this.events.push('error');
    this.errors.push(cloneError(error));
  }
}

function playerTrack(label: string): MobileTrack {
  return {
    key: `track:${label}`,
    bvid: `BV${label}`,
    aid: 1,
    cid: 2,
    title: label,
    artist: 'Artist',
    coverUrl: `https://example.invalid/${label}.jpg`,
    duration: 180,
    playCount: 3
  };
}

function playbackState(track: MobileTrack | null, status: PlaybackStatus, position: number,
  duration: number, mode: PlayerMode, queueIndex: number,
  queue: MobileTrack[] = [], error: AppError | null = null): PlaybackState {
  const state = emptyPlaybackState();
  state.track = cloneTrack(track);
  state.status = status;
  state.position = position;
  state.duration = duration;
  state.mode = mode;
  state.queueIndex = queueIndex;
  state.queue = cloneTracks(queue);
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

function cloneView(snapshot: PlayerViewSnapshot): PlayerViewSnapshot {
  return {
    status: snapshot.status,
    track: cloneTrack(snapshot.track),
    duration: snapshot.duration,
    mode: snapshot.mode,
    queue: cloneTracks(snapshot.queue),
    queueIndex: snapshot.queueIndex
  };
}

function cloneProgress(progress: PlayerProgressSnapshot): PlayerProgressSnapshot {
  return {
    position: progress.position,
    duration: progress.duration
  };
}

function cloneError(error: AppError): AppError {
  return {
    code: error.code,
    message: error.message,
    retryable: error.retryable
  };
}

export default function playerStoreTest(): void {
  describe('PlayerStore', () => {
    it('mapsStateProgressQueueAndErrorWithoutSecrets', 0, () => {
      const scheduler = new FakePlayerScheduler();
      const target = new FakePlayerTarget();
      const store = new PlayerStore(scheduler);
      const listener = new RecordingPlayerListener();
      store.bind(target);
      store.subscribe(listener);

      const first = playerTrack('first');
      const second = playerTrack('second');
      store.onState(playbackState(first, 'playing', 10, 180, 'shuffle', 1,
        [second, first]));
      store.onProgress(12, 180);
      scheduler.advance(PLAYER_PROGRESS_INTERVAL_MS);
      scheduler.runNext();

      expect(listener.events.length).assertEqual(2);
      expect(listener.events[0]).assertEqual('state');
      expect(listener.events[1]).assertEqual('progress');
      expect(store.snapshot.track?.key).assertEqual('track:first');
      expect(store.snapshot.status).assertEqual('playing');
      expect(store.snapshot.duration).assertEqual(180);
      expect(store.snapshot.mode).assertEqual('shuffle');
      expect(store.snapshot.queue.map((track: MobileTrack): string => track.key).join(','))
        .assertEqual('track:second,track:first');
      expect(store.snapshot.queueIndex).assertEqual(1);
      expect(store.progress.position).assertEqual(12);
      expect(store.read().position).assertEqual(12);

      const serialized = JSON.stringify(store.read()).toLowerCase();
      expect(serialized.includes('"queue"')).assertTrue();
      expect(serialized.includes('track:first')).assertTrue();
      expect(serialized.includes('"volume"')).assertFalse();

      store.onError({
        code: 'player.playbackFailed',
        message: '播放失败。',
        retryable: true
      });
      expect(listener.events[2]).assertEqual('error');
      expect(store.snapshot.status).assertEqual('error');
      expect(store.error?.code).assertEqual('player.playbackFailed');
      expect(listener.states.length).assertEqual(1);
      expect(listener.progressValues.length).assertEqual(1);
      expect(listener.errors.length).assertEqual(1);
    });

    it('clonesAndSanitizesQueueSnapshotsIndependently', 0, () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const listener = new RecordingPlayerListener();
      store.bind(new FakePlayerTarget());
      store.subscribe(listener);

      const first = playerTrack('first');
      const second = playerTrack('second');
      const source = playbackState(first, 'paused', 12, 180, 'sequence', 4,
        [first, second]);
      store.onState(source);

      source.queue[0].title = 'mutated source';
      source.queue.push(playerTrack('third'));
      listener.states[0].queue[0].title = 'mutated listener copy';
      const read = store.read();
      read.queue[1].title = 'mutated read copy';

      expect(store.snapshot.queue.length).assertEqual(2);
      expect(store.snapshot.queue[0].title).assertEqual('first');
      expect(store.snapshot.queue[1].title).assertEqual('second');
      expect(store.snapshot.queueIndex).assertEqual(-1);
    });

    it('throttlesProgressWithoutReplacingTheStateSnapshot', 0, () => {
      const scheduler = new FakePlayerScheduler();
      const store = new PlayerStore(scheduler);
      const listener = new RecordingPlayerListener();
      store.bind(new FakePlayerTarget());
      store.onState(playbackState(playerTrack('first'), 'playing', 0, 180, 'sequence', 0));
      store.subscribe(listener);
      const stateSnapshot = store.snapshot;

      store.onProgress(5, 180);
      expect(scheduler.pendingCount()).assertEqual(1);
      expect(listener.progressValues.length).assertEqual(0);

      scheduler.advance(100);
      store.onProgress(9, 180);
      expect(scheduler.pendingCount()).assertEqual(1);
      expect(listener.progressValues.length).assertEqual(0);

      scheduler.advance(150);
      scheduler.runNext();
      expect(listener.progressValues.length).assertEqual(1);
      expect(listener.progressValues[0].position).assertEqual(9);
      expect(store.progress.position).assertEqual(9);
      expect(store.snapshot === stateSnapshot).assertTrue();
      expect(listener.states.length).assertEqual(0);
    });

    it('dropsAStaleProgressTimerAfterTheTrackStateChanges', 0, () => {
      const scheduler = new FakePlayerScheduler();
      const store = new PlayerStore(scheduler);
      const listener = new RecordingPlayerListener();
      store.bind(new FakePlayerTarget());
      store.subscribe(listener);

      store.onState(playbackState(playerTrack('old'), 'playing', 20, 180, 'sequence', 0));
      store.onProgress(21, 180);
      expect(scheduler.pendingCount()).assertEqual(1);

      scheduler.advance(100);
      store.onState(playbackState(playerTrack('new'), 'playing', 3, 240, 'repeat-all', 1));
      expect(store.snapshot.track?.key).assertEqual('track:new');
      expect(store.progress.position).assertEqual(3);
      expect(scheduler.pendingCount()).assertEqual(0);

      scheduler.runNext(true);
      expect(store.snapshot.track?.key).assertEqual('track:new');
      expect(store.progress.position).assertEqual(3);
      expect(listener.progressValues.length).assertEqual(0);
    });

    it('routesEveryPlayerCommandThroughTheBoundTarget', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      const initial = store.snapshot;
      target.resultState = playbackState(playerTrack('command-result'), 'playing', 0, 180,
        'sequence', 0);

      await store.loadQueue([playerTrack('first'), playerTrack('second')], 1, false);
      await store.appendToQueue([playerTrack('queued'), playerTrack('queued')]);
      await store.removeFromQueue(1);
      await store.clearQueue();
      await store.play(2);
      await store.pause();
      await store.seek(42);
      await store.next();
      await store.previous();
      await store.skipPrevious();
      await store.setMode('shuffle');

      expect(target.calls.join(',')).assertEqual(
        'loadQueue,appendToQueue,removeFromQueue,clearQueue,play,pause,seek,next,previous,skipPrevious,setMode'
      );
      expect(target.queueSize).assertEqual(2);
      expect(target.appendQueueKeys.join(',')).assertEqual('track:queued,track:queued');
      expect(target.startIndex).assertEqual(1);
      expect(target.autoplay).assertFalse();
      expect(target.restart).assertFalse();
      expect(target.requestedIndex).assertEqual(2);
      expect(target.seekPosition).assertEqual(42);
      expect(target.requestedMode).assertEqual('shuffle');
      expect(target.removeIndex).assertEqual(1);
      expect(target.clearCallCount).assertEqual(1);
      expect(store.snapshot === initial).assertFalse();
      expect(store.snapshot.track?.key).assertEqual('track:command-result');
      expect(store.snapshot.queue.length).assertEqual(0);
    });

    it('playsTheSelectedTrackFromTheQueueHead', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      const first = playerTrack('first');
      const second = playerTrack('second');
      store.onState(playbackState(first, 'playing', 10, 180, 'sequence', 0, [first, second]));

      await store.playTrackNow(second);

      expect(target.calls.join(',')).assertEqual('loadQueue');
      expect(target.loadQueueKeys.join(',')).assertEqual('track:second,track:first');
      expect(target.startIndex).assertEqual(0);
      expect(target.autoplay).assertTrue();
      expect(target.restart).assertTrue();
    });

    it('rejectsANewTrackWhenThePlaybackQueueIsFull', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      const queue: MobileTrack[] = [];
      for (let index = 0; index < PLAYER_QUEUE_LIMIT; index++) {
        queue.push(playerTrack(`queued-${index}`));
      }
      store.onState(playbackState(queue[0], 'playing', 0, 180, 'sequence', 0, queue));

      let code = '';
      try {
        await store.playTrackNow(playerTrack('new'));
      } catch (error) {
        code = error instanceof NativeError ? error.appError.code : '';
      }

      expect(code).assertEqual('player.queueFull');
      expect(target.calls.length).assertEqual(0);
      expect(store.error?.code).assertEqual('player.queueFull');
      expect(store.error?.message).assertEqual('播放队列已满（500 首），请先清理队列。');
    });

    it('dropsStaleResultsWhenPlayerCommandsFinishOutOfOrder', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      const track = playerTrack('rapid');
      target.playResultState = playbackState(track, 'playing', 10, 180, 'sequence', 0, [track]);
      target.pauseResultState = playbackState(track, 'paused', 12, 180, 'sequence', 0, [track]);
      target.playDelayMs = 5;

      const stalePlay = store.play();
      await store.pause();
      await stalePlay;

      expect(target.calls.join(',')).assertEqual('play,pause');
      expect(store.snapshot.status).assertEqual('paused');
      expect(store.progress.position).assertEqual(12);
    });

    it('appliesTheAuthoritativeEmptyStateAfterClearingTheQueue', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      store.onState(playbackState(playerTrack('first'), 'playing', 42, 180, 'repeat-all', 0,
        [playerTrack('first'), playerTrack('second')]));
      target.resultState = emptyPlaybackState();
      target.resultState.mode = 'repeat-all';

      await store.clearQueue();

      expect(store.snapshot.status).assertEqual('idle');
      expect(store.snapshot.track === null).assertTrue();
      expect(store.snapshot.queue.length).assertEqual(0);
      expect(store.snapshot.queueIndex).assertEqual(-1);
      expect(store.snapshot.mode).assertEqual('repeat-all');
      expect(store.read().position).assertEqual(0);
    });

    it('restoresPausedStateWithoutIssuingPlayback', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      const first = playerTrack('first');
      const second = playerTrack('second');
      const session: PlayerSessionSnapshot = {
        version: 1,
        queue: [first, second],
        queueIndex: 1,
        mode: 'repeat-all',
        position: 47,
        duration: 180
      };
      target.resultState = playbackState(second, 'paused', 47, 180, 'repeat-all', 1,
        [first, second]);

      await store.restoreSession(session);

      expect(target.calls.join(',')).assertEqual('restoreSession');
      expect(target.restoredSession?.queueIndex).assertEqual(1);
      expect(target.restoredSession?.position).assertEqual(47);
      expect(store.snapshot.status).assertEqual('paused');
      expect(store.snapshot.track?.key).assertEqual('track:second');
      expect(store.snapshot.queueIndex).assertEqual(1);
      expect(store.snapshot.mode).assertEqual('repeat-all');
      expect(store.progress.position).assertEqual(47);
    });

    it('sanitizesCommandFailuresForDisplay', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      target.failure = new Error('https://example.invalid/audio?cookie=secret&qrcode_key=hidden');

      let code = '';
      try {
        await store.loadQueue([playerTrack('first')]);
      } catch (error) {
        code = error instanceof NativeError ? error.appError.code : '';
      }

      expect(code).assertEqual('native.error');
      expect(store.snapshot.status).assertEqual('error');
      expect(store.error?.code).assertEqual('native.error');
      expect(store.read().error?.message.includes('https://')).assertFalse();
      expect(store.read().error?.message.toLowerCase().includes('cookie')).assertFalse();
    });

    it('retriesOnlyOnceAndClearsTheErrorAfterSuccess', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      const track = playerTrack('first');
      store.onState(playbackState(track, 'error', 25, 180, 'sequence', 0, [track], {
        code: 'player.prepareFailed',
        message: '音频暂时无法播放，请稍后重试。',
        retryable: true
      }));
      target.resultState = playbackState(track, 'playing', 25, 180, 'sequence', 0, [track]);
      target.playDelayMs = 5;

      const first = store.retryPlayback();
      const second = store.retryPlayback();
      store.onState(playbackState(track, 'loading', 25, 180, 'sequence', 0, [track]));
      expect(store.retryLoading).assertTrue();
      expect(store.error?.code).assertEqual('player.prepareFailed');

      await Promise.all([first, second]);

      expect(target.playCallCount).assertEqual(1);
      expect(target.requestedIndex).assertEqual(-1);
      expect(store.retryLoading).assertFalse();
      expect(store.error === null).assertTrue();
    });

    it('retainsOneSanitizedErrorAfterAFailedRetry', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      store.bind(target);
      const track = playerTrack('first');
      store.onState(playbackState(track, 'error', 25, 180, 'sequence', 0, [track], {
        code: 'player.prepareFailed',
        message: '音频暂时无法播放，请稍后重试。',
        retryable: true
      }));
      target.failure = new Error('https://example.invalid/audio?cookie=secret');

      await store.retryPlayback();

      expect(target.playCallCount).assertEqual(1);
      expect(store.retryLoading).assertFalse();
      expect(store.snapshot.status).assertEqual('error');
      expect(store.error?.code).assertEqual('native.error');
      expect(store.error?.message.includes('https://')).assertFalse();
      expect(store.error?.message.toLowerCase().includes('cookie')).assertFalse();
    });

    it('ignoresADelayedErrorFromAReplacedTrack', 0, () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const listener = new RecordingPlayerListener();
      store.bind(new FakePlayerTarget());
      store.subscribe(listener);
      const first = playerTrack('first');
      const second = playerTrack('second');
      store.onState(playbackState(first, 'playing', 10, 180, 'sequence', 0, [first, second]));
      store.onError({
        code: 'player.playbackFailed',
        message: '当前曲目播放失败，请稍后重试。',
        retryable: true
      }, {
        trackKey: first.key,
        generation: 1
      });
      store.onState(playbackState(second, 'playing', 4, 180, 'sequence', 1, [first, second]));
      const eventsBeforeStaleError = listener.events.length;

      const accepted = store.onError({
        code: 'player.playbackFailed',
        message: '当前曲目播放失败，请稍后重试。',
        retryable: true
      }, {
        trackKey: first.key,
        generation: 1
      });

      expect(accepted).assertFalse();
      expect(listener.events.length).assertEqual(eventsBeforeStaleError);
      expect(store.error === null).assertTrue();
      expect(store.snapshot.status).assertEqual('playing');
      expect(store.snapshot.track?.key).assertEqual(second.key);
    });

    it('unsubscribesCleanlyAndDisposesOutstandingCallbacks', 0, async () => {
      const scheduler = new FakePlayerScheduler();
      const store = new PlayerStore(scheduler);
      const target = new FakePlayerTarget();
      const listener = new RecordingPlayerListener();
      store.bind(target);
      store.subscribe(listener);
      store.subscribe(listener);
      store.onState(playbackState(playerTrack('first'), 'playing', 0, 180, 'sequence', 0));
      expect(listener.states.length).assertEqual(1);

      store.onProgress(1, 180);
      store.unsubscribe(listener);
      scheduler.advance(PLAYER_PROGRESS_INTERVAL_MS);
      scheduler.runNext();
      expect(listener.progressValues.length).assertEqual(0);

      store.dispose();
      store.onState(playbackState(playerTrack('second'), 'playing', 0, 180, 'sequence', 0));
      expect(listener.states.length).assertEqual(1);

      let code = '';
      try {
        await store.pause();
      } catch (error) {
        code = error instanceof NativeError ? error.appError.code : '';
      }
      expect(code).assertEqual('player.storeDisposed');
    });

    it('detachesWithoutApplyingLateResultsOrAcceptingLaterCommands', 0, async () => {
      const store = new PlayerStore(new FakePlayerScheduler());
      const target = new FakePlayerTarget();
      const listener = new RecordingPlayerListener();
      store.bind(target);
      store.subscribe(listener);
      const track = playerTrack('late');
      target.resultState = playbackState(track, 'playing', 4, 180, 'sequence', 0, [track]);
      target.loadQueueDelayMs = 5;

      const staleLoad = store.loadQueue([track]);
      expect(store.queueRequest !== null).assertTrue();
      store.detachTarget();
      expect(store.queueRequest === null).assertTrue();
      await staleLoad;

      expect(store.snapshot.status).assertEqual('idle');
      expect(store.snapshot.track === null).assertTrue();
      expect(store.snapshot.queue.length).assertEqual(0);
      expect(listener.states.length).assertEqual(0);

      let code = '';
      try {
        await store.play();
      } catch (error) {
        code = error instanceof NativeError ? error.appError.code : '';
      }
      expect(code).assertEqual('player.notReady');
      expect(target.playCallCount).assertEqual(0);

      store.dispose();
      store.dispose();
      expect(store.queueRequest === null).assertTrue();
    });
  });
}
