import { describe, expect, it } from '@ohos/hypium';
import { QueuePageState } from '../main/ets/components/native/QueuePageState';
import {
  clampPlayerPosition,
  isPlayerGenerationCurrent,
  placeTrackAtQueueHead,
  PLAYER_QUEUE_LIMIT,
  queueStartPosition,
  removePlayerQueueTrack,
  selectPlayerTrackIndex,
  shouldRestartForPrevious
} from '../main/ets/services/PlayerQueue';
import {
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore
} from '../main/ets/state/PlayerStore';
import {
  AppError,
  MobileTrack,
  PlaybackState,
  PlaybackStatus,
  PlayerSessionSnapshot,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';

class QueueTestScheduler implements PlayerProgressScheduler {
  now(): number {
    return 1000;
  }

  schedule(_callback: () => void, _delayMs: number): number {
    return 1;
  }

  cancel(_timerId: number): void {
  }
}

class PendingQueueMutation {
  readonly params: Record<string, Object>;
  readonly promise: Promise<PlaybackState>;
  private resolveCallback: ((state: PlaybackState) => void) | null = null;

  constructor(params: Record<string, Object>) {
    this.params = params;
    this.promise = new Promise<PlaybackState>((resolve) => {
      this.resolveCallback = resolve;
    });
  }

  resolve(state: PlaybackState): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    if (callback !== null) {
      callback(cloneState(state));
    }
  }
}

class DeferredQueueTarget implements PlayerCommandTarget {
  state: PlaybackState = emptyPlaybackState();
  readonly removals: PendingQueueMutation[] = [];
  clearCalls: number = 0;
  playCalls: number = 0;

  loadQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  appendToQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  removeFromQueue(params: Record<string, Object>): Promise<PlaybackState> {
    const pending = new PendingQueueMutation(params);
    this.removals.push(pending);
    return pending.promise;
  }

  clearQueue(): Promise<PlaybackState> {
    this.clearCalls++;
    return Promise.resolve(cloneState(this.state));
  }

  restoreSession(_session: PlayerSessionSnapshot): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  play(_params: Record<string, Object>): Promise<PlaybackState> {
    this.playCalls++;
    return Promise.resolve(cloneState(this.state));
  }

  pause(): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  seek(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  next(): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  previous(): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  skipPrevious(): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  setMode(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  setQuality(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(cloneState(this.state));
  }

  snapshot(): PlaybackState {
    return cloneState(this.state);
  }
}

function queueTrack(label: string): MobileTrack {
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

function queueState(queue: MobileTrack[], queueIndex: number, status: PlaybackStatus): PlaybackState {
  const state = emptyPlaybackState();
  state.status = status;
  state.track = queueIndex >= 0 && queueIndex < queue.length ? cloneTrack(queue[queueIndex]) : null;
  state.duration = state.track?.duration ?? 0;
  state.mode = 'sequence';
  state.queue = cloneTracks(queue);
  state.queueIndex = queueIndex;
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

function cloneError(error: AppError | undefined): AppError | undefined {
  if (error === undefined) {
    return undefined;
  }
  return {
    code: error.code,
    message: error.message,
    retryable: error.retryable
  };
}

function trackKeys(tracks: MobileTrack[]): string {
  return tracks.map((track: MobileTrack): string => track.key).join(',');
}

export default function playerQueueTest(): void {
  describe('PlayerQueue', () => {
    it('keepsIndexesStableWhenRemovingBeforeOrAfterTheCurrentTrack', 0, () => {
      const first = queueTrack('first');
      const second = queueTrack('second');
      const third = queueTrack('third');
      const before = removePlayerQueueTrack([first, second, third], 1, 0);
      const after = removePlayerQueueTrack([first, second, third], 1, 2);

      expect(trackKeys(before.queue)).assertEqual('track:second,track:third');
      expect(before.queueIndex).assertEqual(0);
      expect(before.selectedIndex).assertEqual(0);
      expect(before.removedCurrent).assertFalse();
      expect(before.changed).assertTrue();

      expect(trackKeys(after.queue)).assertEqual('track:first,track:second');
      expect(after.queueIndex).assertEqual(1);
      expect(after.selectedIndex).assertEqual(1);
      expect(after.removedCurrent).assertFalse();
    });

    it('selectsNextThenPreviousWhenRemovingTheCurrentTrack', 0, () => {
      const first = queueTrack('first');
      const second = queueTrack('second');
      const third = queueTrack('third');
      const current = removePlayerQueueTrack([first, second, third], 1, 1);
      const tail = removePlayerQueueTrack([first, second, third], 2, 2);

      expect(trackKeys(current.queue)).assertEqual('track:first,track:third');
      expect(current.queueIndex).assertEqual(1);
      expect(current.selectedIndex).assertEqual(1);
      expect(current.removedCurrent).assertTrue();

      expect(trackKeys(tail.queue)).assertEqual('track:first,track:second');
      expect(tail.queueIndex).assertEqual(1);
      expect(tail.selectedIndex).assertEqual(1);
      expect(tail.removedCurrent).assertTrue();
    });

    it('returnsAnEmptySelectionAfterRemovingTheFinalTrack', 0, () => {
      const removal = removePlayerQueueTrack([queueTrack('only')], 0, 0);

      expect(removal.queue.length).assertEqual(0);
      expect(removal.queueIndex).assertEqual(-1);
      expect(removal.selectedIndex).assertEqual(-1);
      expect(removal.removedCurrent).assertTrue();
      expect(removal.changed).assertTrue();
    });

    it('ignoresAnOutOfRangeRemovalWithoutMutatingTheQueue', 0, () => {
      const queue = [queueTrack('first'), queueTrack('second')];
      const removal = removePlayerQueueTrack(queue, 0, 9);

      expect(trackKeys(removal.queue)).assertEqual(trackKeys(queue));
      expect(removal.queueIndex).assertEqual(0);
      expect(removal.changed).assertFalse();
    });

    it('placesTheSelectedTrackAtTheHeadWithoutDuplicatingIt', 0, () => {
      const first = queueTrack('first');
      const second = queueTrack('second');
      const third = queueTrack('third');
      const moved = placeTrackAtQueueHead([first, second, third], third, PLAYER_QUEUE_LIMIT);
      const added = placeTrackAtQueueHead([first, third], second, PLAYER_QUEUE_LIMIT);
      const empty = placeTrackAtQueueHead([], first, PLAYER_QUEUE_LIMIT);

      expect(trackKeys(moved.queue)).assertEqual('track:third,track:first,track:second');
      expect(moved.index).assertEqual(0);
      expect(moved.full).assertFalse();

      expect(trackKeys(added.queue)).assertEqual('track:second,track:first,track:third');
      expect(added.index).assertEqual(0);
      expect(added.full).assertFalse();

      expect(trackKeys(empty.queue)).assertEqual('track:first');
      expect(empty.index).assertEqual(0);
      expect(empty.full).assertFalse();
    });

    it('collapsesDuplicatesWhenMovingATrackToTheHead', 0, () => {
      const first = queueTrack('first');
      const second = queueTrack('second');
      const placement = placeTrackAtQueueHead([first, second, first], second, PLAYER_QUEUE_LIMIT);

      expect(trackKeys(placement.queue)).assertEqual('track:second,track:first');
      expect(placement.index).assertEqual(0);
      expect(placement.full).assertFalse();
    });

    it('rejectsANewTrackAtTheQueueLimitButMovesAnExistingOne', 0, () => {
      const first = queueTrack('first');
      const second = queueTrack('second');
      const full = placeTrackAtQueueHead([first, second], queueTrack('third'), 2);

      expect(full.full).assertTrue();
      expect(full.index).assertEqual(-1);
      expect(trackKeys(full.queue)).assertEqual('track:first,track:second');

      const moved = placeTrackAtQueueHead([first, second], second, 2);
      expect(moved.full).assertFalse();
      expect(moved.index).assertEqual(0);
      expect(trackKeys(moved.queue)).assertEqual('track:second,track:first');

      expect(placeTrackAtQueueHead([first], first, 0).full).assertTrue();
    });

    it('clampsSeekPositionsAndUsesThePreviousRestartThreshold', 0, () => {
      expect(clampPlayerPosition(-4, 180)).assertEqual(0);
      expect(clampPlayerPosition(181, 180)).assertEqual(180);
      expect(clampPlayerPosition(42, 0)).assertEqual(42);
      expect(clampPlayerPosition(Number.NaN, 180)).assertEqual(0);
      expect(shouldRestartForPrevious(5)).assertFalse();
      expect(shouldRestartForPrevious(5.001)).assertTrue();
      expect(shouldRestartForPrevious(Number.NaN)).assertFalse();
    });

    it('resumesOnlyTheLiveTrackAndStartsEverythingElseAtZero', 0, () => {
      expect(queueStartPosition(false, '', 42, 180, 'track:first', 180)).assertEqual(0);
      expect(queueStartPosition(false, 'track:first', 42, 180, 'track:second', 180)).assertEqual(0);
      expect(queueStartPosition(false, 'track:first', 42, 180, 'track:first', 180)).assertEqual(42);
      expect(queueStartPosition(true, 'track:first', 42, 180, 'track:first', 180)).assertEqual(0);
      expect(queueStartPosition(false, 'track:first', 3, 180, 'track:first', 180)).assertEqual(0);
      expect(queueStartPosition(false, 'track:first', 177, 180, 'track:first', 180)).assertEqual(0);
      expect(queueStartPosition(false, 'track:first', 42, 0, 'track:first', 180)).assertEqual(42);
      expect(queueStartPosition(false, 'track:first', Number.NaN, 180, 'track:first', 180))
        .assertEqual(0);
    });

    it('selectsTrackTargetsAtQueueEdgesAndInEveryMode', 0, () => {
      expect(selectPlayerTrackIndex(3, 1, 1, 'sequence', false, 0)).assertEqual(2);
      expect(selectPlayerTrackIndex(3, 1, -1, 'sequence', false, 0)).assertEqual(0);
      expect(selectPlayerTrackIndex(3, 2, 1, 'sequence', false, 0)).assertEqual(-1);
      expect(selectPlayerTrackIndex(3, 2, 1, 'sequence', true, 0)).assertEqual(0);
      expect(selectPlayerTrackIndex(3, 0, -1, 'sequence', true, 0)).assertEqual(2);
      expect(selectPlayerTrackIndex(3, 2, 1, 'repeat-all', false, 0)).assertEqual(0);
      expect(selectPlayerTrackIndex(3, 0, -1, 'repeat-all', false, 0)).assertEqual(2);
      expect(selectPlayerTrackIndex(3, 2, 1, 'repeat-one', true, 0)).assertEqual(0);
      expect(selectPlayerTrackIndex(3, 0, -1, 'repeat-one', true, 0)).assertEqual(2);
      expect(selectPlayerTrackIndex(3, 1, -1, 'shuffle', true, 0)).assertEqual(0);
      expect(selectPlayerTrackIndex(3, 1, 1, 'shuffle', true, 0.5)).assertEqual(2);
      expect(selectPlayerTrackIndex(1, 0, 1, 'shuffle', true, 0.99)).assertEqual(0);
      expect(selectPlayerTrackIndex(0, 0, 1, 'sequence', true, 0)).assertEqual(-1);
    });

    it('acceptsOnlyTheActivePlayerGeneration', 0, () => {
      expect(isPlayerGenerationCurrent(4, 4)).assertTrue();
      expect(isPlayerGenerationCurrent(4, 3)).assertFalse();
    });

    it('blocksDuplicateQueueMutationsWhileOneIsPending', 0, async () => {
      const queue = [queueTrack('first'), queueTrack('second'), queueTrack('third')];
      const target = new DeferredQueueTarget();
      target.state = queueState(queue, 1, 'playing');
      const store = new PlayerStore(new QueueTestScheduler());
      store.bind(target);
      const page = new QueuePageState(store);
      page.attach();

      const pendingRemove = page.removeAt(0);
      expect(page.busyAction).assertEqual('remove');
      expect(target.removals.length).assertEqual(1);
      expect((target.removals[0].params.index as number)).assertEqual(0);

      const duplicateRemove = page.removeAt(1);
      const blockedClear = page.clear();
      const blockedSwitch = page.switchTo(2);
      await Promise.all([duplicateRemove, blockedClear, blockedSwitch]);
      expect(target.removals.length).assertEqual(1);
      expect(target.clearCalls).assertEqual(0);
      expect(target.playCalls).assertEqual(0);

      target.removals[0].resolve(queueState([
        queueTrack('second'),
        queueTrack('third')
      ], 0, 'playing'));
      await pendingRemove;

      expect(page.busyAction).assertEqual('');
      expect(trackKeys(page.queue)).assertEqual('track:second,track:third');
      expect(page.queueIndex).assertEqual(0);
      page.dispose();
    });
  });
}
