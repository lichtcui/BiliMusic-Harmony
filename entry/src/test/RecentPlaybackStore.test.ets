import { describe, expect, it } from '@ohos/hypium';
import {
  LibraryPersistence,
  LibraryStore
} from '../main/ets/services/LibraryStore';
import {
  LibraryStoreModel
} from '../main/ets/state/LibraryStoreModel';
import {
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore
} from '../main/ets/state/PlayerStore';
import { RecentPlaybackStore } from '../main/ets/state/RecentPlaybackStore';
import {
  AppError,
  LibrarySnapshot,
  MobileTrack,
  PlaybackState,
  PlaybackStatus,
  PlayerSessionSnapshot,
  STORAGE_VERSION,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';
import { wait } from '../main/ets/util/Errors';

class RecentFakeScheduler implements PlayerProgressScheduler {
  nowMs: number = 1000;

  now(): number {
    return this.nowMs;
  }

  schedule(_callback: () => void, _delayMs: number): number {
    return 1;
  }

  cancel(_timerId: number): void {
  }
}

class RecentFakePlayerTarget implements PlayerCommandTarget {
  state: PlaybackState = emptyPlaybackState();
  failure: Object | null = null;
  queue: MobileTrack[] = [];
  startIndex: number = -1;
  autoplay: boolean = false;
  loadQueueCalls: number = 0;

  loadQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.loadQueueCalls++;
    this.queue = cloneTracks(params.queue as MobileTrack[]);
    this.startIndex = params.startIndex as number;
    this.autoplay = params.autoplay as boolean;
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

  seek(_params: Record<string, Object>): Promise<PlaybackState> {
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

  setMode(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  setQuality(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  snapshot(): PlaybackState {
    return clonePlaybackState(this.state);
  }

  private complete(): Promise<PlaybackState> {
    const failure = this.failure;
    this.failure = null;
    if (failure !== null) {
      return Promise.reject(failure);
    }
    return Promise.resolve(clonePlaybackState(this.state));
  }
}

class RecentMemoryPersistence implements LibraryPersistence {
  content: string | null = null;
  failWrites: boolean = false;
  writeCount: number = 0;

  constructor(content: string | null = null) {
    this.content = content;
  }

  read(_path: string): string | null {
    return this.content;
  }

  readAsync(path: string): Promise<string | null> {
    return Promise.resolve(this.read(path));
  }

  async write(_path: string, content: string): Promise<void> {
    this.writeCount++;
    await wait(1);
    if (this.failWrites) {
      throw new Error('simulated recent write failure');
    }
    this.content = content;
  }

  preserveCorrupt(_path: string): void {
  }
}

class RecentHarness {
  readonly scheduler: RecentFakeScheduler;
  readonly playerTarget: RecentFakePlayerTarget;
  readonly playerStore: PlayerStore;
  readonly persistence: RecentMemoryPersistence;
  readonly libraryStore: LibraryStore;
  readonly libraryModel: LibraryStoreModel;
  readonly store: RecentPlaybackStore;

  constructor(initialTracks: MobileTrack[] = []) {
    this.scheduler = new RecentFakeScheduler();
    this.playerTarget = new RecentFakePlayerTarget();
    this.playerStore = new PlayerStore(this.scheduler);
    this.playerStore.bind(this.playerTarget);
    this.persistence = new RecentMemoryPersistence(JSON.stringify(librarySnapshot(initialTracks)));
    this.libraryStore = new LibraryStore('memory://recent', this.persistence);
    this.libraryModel = new LibraryStoreModel(this.libraryStore);
    this.store = new RecentPlaybackStore(this.playerStore, this.libraryModel);
    this.store.attach();
  }
}

function librarySnapshot(recent: MobileTrack[]): LibrarySnapshot {
  return {
    version: STORAGE_VERSION,
    favorites: [],
    playlists: [],
    recent: cloneTracks(recent),
    positions: {},
    updatedAt: 1
  };
}

function recentTrack(id: number): MobileTrack {
  return {
    key: `BV${id}:${id + 100}`,
    bvid: `BV${id}`,
    aid: id,
    cid: id + 100,
    title: `Track ${id}`,
    artist: `Artist ${id}`,
    coverUrl: `https://example.com/${id}.jpg`,
    duration: 180,
    playCount: id
  };
}

function playbackState(track: MobileTrack | null, status: PlaybackStatus): PlaybackState {
  const state = emptyPlaybackState();
  state.track = cloneTrack(track);
  state.status = status;
  state.position = 12;
  state.duration = track === null ? 0 : track.duration;
  state.queue = track === null ? [] : [cloneTrack(track) as MobileTrack];
  state.queueIndex = track === null ? -1 : 0;
  return state;
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

function clonePlaybackState(state: PlaybackState): PlaybackState {
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

function cloneError(error: AppError): AppError {
  return {
    code: error.code,
    message: error.message,
    retryable: error.retryable
  };
}

function trackKeys(tracks: MobileTrack[]): string[] {
  return tracks.map((track: MobileTrack): string => track.key);
}

export default function recentPlaybackStoreTest(): void {
  describe('RecentPlaybackStore', () => {
    it('recordsTheFirstCurrentTrackOnlyOnce', 0, async () => {
      const harness = new RecentHarness();
      const first = recentTrack(1);

      harness.playerStore.onState(playbackState(first, 'playing'));
      await harness.store.flush();

      expect(harness.persistence.writeCount).assertEqual(1);
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key]);
      expect(harness.store.currentKey).assertEqual(first.key);
    });

    it('doesNotRecordPauseResumeOrRepeatedStateSnapshots', 0, async () => {
      const harness = new RecentHarness();
      const first = recentTrack(1);

      harness.playerStore.onState(playbackState(first, 'playing'));
      await harness.store.flush();
      harness.playerStore.onState(playbackState(first, 'paused'));
      harness.playerStore.onState(playbackState(first, 'playing'));
      harness.playerStore.onState(playbackState(first, 'playing'));
      await harness.store.flush();

      expect(harness.persistence.writeCount).assertEqual(1);
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key]);
    });

    it('movesAnOlderTrackToFrontWithoutDuplicatingIt', 0, async () => {
      const harness = new RecentHarness();
      const first = recentTrack(1);
      const second = recentTrack(2);

      harness.playerStore.onState(playbackState(first, 'playing'));
      await harness.store.flush();
      harness.playerStore.onState(playbackState(second, 'playing'));
      await harness.store.flush();
      harness.playerStore.onState(playbackState(first, 'playing'));
      await harness.store.flush();

      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key, second.key]);
      expect(harness.store.tracks.length).assertEqual(2);
      expect(harness.persistence.writeCount).assertEqual(3);
    });

    it('keepsThirtyTracksAndEvictsTheOldestOne', 0, async () => {
      const harness = new RecentHarness();

      for (let id = 1; id <= 31; id++) {
        harness.playerStore.onState(playbackState(recentTrack(id), 'playing'));
      }
      await harness.store.flush();

      expect(harness.store.tracks.length).assertEqual(30);
      expect(harness.store.tracks[0].key).assertEqual(recentTrack(31).key);
      expect(harness.store.tracks[29].key).assertEqual(recentTrack(2).key);
      expect(trackKeys(harness.store.tracks).indexOf(recentTrack(1).key)).assertEqual(-1);
    });

    it('playsTheClickedRecentTrackAtTheClickedQueueIndex', 0, async () => {
      const first = recentTrack(1);
      const second = recentTrack(2);
      const third = recentTrack(3);
      const harness = new RecentHarness([third, second, first]);

      expect(await harness.store.playAt(1)).assertTrue();

      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([third.key, second.key, first.key]);
      expect(harness.playerTarget.startIndex).assertEqual(1);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('playsAllRecentTracksFromTheFirstQueueIndex', 0, async () => {
      const first = recentTrack(1);
      const second = recentTrack(2);
      const harness = new RecentHarness([second, first]);

      await harness.store.playAll();

      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([second.key, first.key]);
      expect(harness.playerTarget.startIndex).assertEqual(0);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('clearsRecentHistoryAndPersistsTheEmptyState', 0, async () => {
      const first = recentTrack(1);
      const harness = new RecentHarness([first]);

      await harness.store.clearRecent();

      expect(harness.store.tracks.length).assertEqual(0);
      const persisted = JSON.parse(harness.persistence.content ?? '{}') as LibrarySnapshot;
      expect(persisted.recent.length).assertEqual(0);
      const restored = new LibraryStore('memory://recent', harness.persistence);
      expect(restored.read().recent.length).assertEqual(0);
    });

    it('tracksMultiSelectionWithoutPlaying', 0, async () => {
      const first = recentTrack(1);
      const second = recentTrack(2);
      const third = recentTrack(3);
      const harness = new RecentHarness([third, second, first]);

      harness.store.toggleSelection(second.key);
      expect(harness.store.isSelected(second.key)).assertTrue();
      expect(harness.store.isAllSelected()).assertFalse();
      expect(harness.store.selectedTracks().map((track: MobileTrack): string => track.key))
        .assertDeepEquals([second.key]);

      harness.store.toggleSelection(second.key);
      expect(harness.store.selectedKeys.length).assertEqual(0);

      harness.store.toggleSelection('missing-key');
      expect(harness.store.selectedKeys.length).assertEqual(0);

      harness.store.selectAll();
      expect(harness.store.selectedKeys.length).assertEqual(3);
      expect(harness.store.isAllSelected()).assertTrue();
      harness.store.clearSelection();
      expect(harness.store.selectedKeys.length).assertEqual(0);
      expect(harness.store.isAllSelected()).assertFalse();
      expect(harness.playerTarget.loadQueueCalls).assertEqual(0);
    });

    it('removesOnlyTheSelectedHistoryEntries', 0, async () => {
      const first = recentTrack(1);
      const second = recentTrack(2);
      const third = recentTrack(3);
      const harness = new RecentHarness([third, second, first]);

      harness.store.toggleSelection(second.key);
      const removed = await harness.store.removeSelected();

      expect(removed).assertTrue();
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([third.key, first.key]);
      expect(harness.store.selectedKeys.length).assertEqual(0);
      const persisted = JSON.parse(harness.persistence.content ?? '{}') as LibrarySnapshot;
      expect(trackKeys(persisted.recent)).assertDeepEquals([third.key, first.key]);
    });

    it('clearsEverythingWhenTheWholeHistoryIsSelected', 0, async () => {
      const first = recentTrack(1);
      const second = recentTrack(2);
      const harness = new RecentHarness([second, first]);

      harness.store.selectAll();
      const removed = await harness.store.removeSelected();

      expect(removed).assertTrue();
      expect(harness.store.tracks.length).assertEqual(0);
      const persisted = JSON.parse(harness.persistence.content ?? '{}') as LibrarySnapshot;
      expect(persisted.recent.length).assertEqual(0);
    });

    it('keepsVisibleHistoryWhenTheRecordWriteFails', 0, async () => {
      const first = recentTrack(1);
      const second = recentTrack(2);
      const harness = new RecentHarness([first]);
      harness.persistence.failWrites = true;

      harness.playerStore.onState(playbackState(second, 'playing'));
      await harness.store.flush();

      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key]);
      expect(harness.store.error?.code).assertEqual('library.writeFailed');

      harness.persistence.failWrites = false;
      harness.store.clearError();
      expect(harness.store.error === null).assertTrue();
    });

    it('doesNotClearHistoryWhenPlaybackFails', 0, async () => {
      const first = recentTrack(1);
      const second = recentTrack(2);
      const harness = new RecentHarness([first]);
      harness.playerStore.onState(playbackState(second, 'playing'));
      await harness.store.flush();
      harness.playerTarget.failure = new Error('simulated playback failure');

      expect(await harness.store.playAt(0)).assertFalse();

      expect(trackKeys(harness.store.tracks)).assertDeepEquals([second.key, first.key]);
      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
    });
  });
}
