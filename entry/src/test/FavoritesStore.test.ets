import { describe, expect, it } from '@ohos/hypium';
import {
  LibraryPersistence,
  LibraryStore
} from '../main/ets/services/LibraryStore';
import { FavoritesStore } from '../main/ets/state/FavoritesStore';
import { LibraryStoreModel } from '../main/ets/state/LibraryStoreModel';
import {
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore
} from '../main/ets/state/PlayerStore';
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

class FavoriteFakeScheduler implements PlayerProgressScheduler {
  now(): number {
    return 1000;
  }

  schedule(_callback: () => void, _delayMs: number): number {
    return 1;
  }

  cancel(_timerId: number): void {
  }
}

class FavoriteFakePlayerTarget implements PlayerCommandTarget {
  state: PlaybackState = emptyPlaybackState();
  queue: MobileTrack[] = [];
  startIndex: number = -1;
  autoplay: boolean = false;
  loadQueueCalls: number = 0;

  loadQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.loadQueueCalls++;
    this.queue = cloneTracks(params.queue as MobileTrack[]);
    this.startIndex = params.startIndex as number;
    this.autoplay = params.autoplay as boolean;
    return Promise.resolve(clonePlaybackState(this.state));
  }

  appendToQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  removeFromQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  clearQueue(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  restoreSession(_session: PlayerSessionSnapshot): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  play(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  pause(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  seek(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  next(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  previous(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  skipPrevious(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  setMode(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  setQuality(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  snapshot(): PlaybackState {
    return clonePlaybackState(this.state);
  }
}

class FavoriteMemoryPersistence implements LibraryPersistence {
  content: string | null;
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
    await wait(2);
    if (this.failWrites) {
      throw new Error('simulated favorite write failure');
    }
    this.content = content;
  }

  preserveCorrupt(_path: string): void {
  }
}

class FavoritesHarness {
  readonly playerTarget: FavoriteFakePlayerTarget;
  readonly playerStore: PlayerStore;
  readonly persistence: FavoriteMemoryPersistence;
  readonly libraryStore: LibraryStore;
  readonly libraryModel: LibraryStoreModel;
  readonly store: FavoritesStore;

  constructor(favorites: MobileTrack[] = []) {
    this.playerTarget = new FavoriteFakePlayerTarget();
    this.playerStore = new PlayerStore(new FavoriteFakeScheduler());
    this.playerStore.bind(this.playerTarget);
    this.persistence = new FavoriteMemoryPersistence(JSON.stringify(librarySnapshot(favorites)));
    this.libraryStore = new LibraryStore('memory://favorites', this.persistence);
    this.libraryModel = new LibraryStoreModel(this.libraryStore);
    this.store = new FavoritesStore(this.playerStore, this.libraryModel);
    this.store.attach();
  }
}

function librarySnapshot(favorites: MobileTrack[]): LibrarySnapshot {
  return {
    version: STORAGE_VERSION,
    favorites: cloneTracks(favorites),
    playlists: [],
    recent: [],
    positions: {},
    updatedAt: 1
  };
}

function favoriteTrack(id: number): MobileTrack {
  return {
    key: `BV${id}:${id + 100}`,
    bvid: `BV${id}`,
    aid: id,
    cid: id + 100,
    title: `Favorite ${id}`,
    artist: `Artist ${id}`,
    coverUrl: `https://example.com/${id}.jpg`,
    duration: 180,
    playCount: id
  };
}

function playbackState(track: MobileTrack, status: PlaybackStatus): PlaybackState {
  const state = emptyPlaybackState();
  state.track = cloneTrack(track);
  state.status = status;
  state.position = 12;
  state.duration = track.duration;
  state.queue = [cloneTrack(track) as MobileTrack];
  state.queueIndex = 0;
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

export default function favoritesStoreTest(): void {
  describe('FavoritesStore', () => {
    it('exposesFavoritesInLibraryOrderAndHighlightsCurrentTrack', 0, () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const harness = new FavoritesHarness([second, first]);

      harness.playerStore.onState(playbackState(first, 'playing'));

      expect(trackKeys(harness.store.tracks)).assertDeepEquals([second.key, first.key]);
      expect(harness.store.currentKey).assertEqual(first.key);
    });

    it('playsTheSelectedFavoriteAtItsCurrentQueueIndex', 0, async () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const third = favoriteTrack(3);
      const harness = new FavoritesHarness([third, second, first]);

      expect(await harness.store.playTrack(second.key)).assertTrue();

      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([third.key, second.key, first.key]);
      expect(harness.playerTarget.startIndex).assertEqual(1);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('playsAllFavoritesFromTheFirstQueueIndex', 0, async () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const harness = new FavoritesHarness([second, first]);

      await harness.store.playAll();

      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([second.key, first.key]);
      expect(harness.playerTarget.startIndex).assertEqual(0);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('addsAFavoriteThroughToggleAndReportsTheNewState', 0, async () => {
      const first = favoriteTrack(1);
      const harness = new FavoritesHarness([]);

      expect(harness.store.isFavorite(first.key)).assertFalse();
      const added = await harness.store.toggle(first);

      expect(added).assertTrue();
      expect(harness.store.isFavorite(first.key)).assertTrue();
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key]);
      expect(harness.store.pendingKeys.length).assertEqual(0);

      const removed = await harness.store.toggle(first);
      expect(removed).assertTrue();
      expect(harness.store.isFavorite(first.key)).assertFalse();
      expect(harness.store.tracks.length).assertEqual(0);
    });

    it('ignoresDuplicateToggleWhileTheFirstWriteIsPending', 0, async () => {
      const first = favoriteTrack(1);
      const harness = new FavoritesHarness([]);

      const firstAttempt = harness.store.toggle(first);
      const secondAttempt = harness.store.toggle(first);
      expect(harness.store.isPending(first.key)).assertTrue();
      const results = await Promise.all([firstAttempt, secondAttempt]);

      expect(results[0]).assertTrue();
      expect(results[1]).assertFalse();
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(harness.store.tracks.length).assertEqual(1);
    });

    it('batchAddsOnlyMissingFavoritesForHistoryMultiSelect', 0, async () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const third = favoriteTrack(3);
      const harness = new FavoritesHarness([second]);

      const added = await harness.store.addMany([first, second, third, first]);

      expect(added).assertEqual(2);
      expect(trackKeys(harness.store.tracks).sort())
        .assertDeepEquals([first.key, second.key, third.key].sort());
      expect(harness.store.pendingKeys.length).assertEqual(0);

      const again = await harness.store.addMany([first, third]);
      expect(again).assertEqual(0);
    });

    it('removesAFavoriteOnlyAfterTheWriteSucceeds', 0, async () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const harness = new FavoritesHarness([first, second]);

      const removed = await harness.store.remove(first.key);

      expect(removed).assertTrue();
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([second.key]);
      expect(harness.persistence.writeCount).assertEqual(1);
      const persisted = JSON.parse(harness.persistence.content ?? '{}') as LibrarySnapshot;
      expect(trackKeys(persisted.favorites)).assertDeepEquals([second.key]);
      const restored = new LibraryStore('memory://favorites', harness.persistence);
      expect(trackKeys(restored.read().favorites)).assertDeepEquals([second.key]);
    });

    it('keepsAFavoriteVisibleAfterWriteFailureAndAllowsRetry', 0, async () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const harness = new FavoritesHarness([first, second]);
      harness.persistence.failWrites = true;

      const removed = await harness.store.remove(first.key);

      expect(removed).assertFalse();
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key, second.key]);
      expect(harness.store.error?.code).assertEqual('library.writeFailed');
      expect(harness.store.pendingKeys.length).assertEqual(0);

      harness.store.clearError();
      harness.persistence.failWrites = false;
      const retried = await harness.store.remove(first.key);

      expect(retried).assertTrue();
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([second.key]);
      expect(harness.store.error === null).assertTrue();
    });

    it('ignoresDuplicateRemovalWhileTheFirstWriteIsPending', 0, async () => {
      const first = favoriteTrack(1);
      const harness = new FavoritesHarness([first]);

      const firstAttempt = harness.store.remove(first.key);
      const secondAttempt = harness.store.remove(first.key);
      expect(harness.store.isPending(first.key)).assertTrue();
      const results = await Promise.all([firstAttempt, secondAttempt]);

      expect(results[0]).assertTrue();
      expect(results[1]).assertFalse();
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(harness.store.tracks.length).assertEqual(0);
    });

    it('emitsOneWriteFailureForDuplicateRemovalTaps', 0, async () => {
      const first = favoriteTrack(1);
      const harness = new FavoritesHarness([first]);
      harness.persistence.failWrites = true;

      const results = await Promise.all([
        harness.store.remove(first.key),
        harness.store.remove(first.key)
      ]);

      expect(results[0]).assertFalse();
      expect(results[1]).assertFalse();
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(harness.store.tracks.length).assertEqual(1);
      expect(harness.store.error?.code).assertEqual('library.writeFailed');
    });

    it('tracksSelectionTogglesAndSelectAllForTheFavoritesToolbar', 0, () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const third = favoriteTrack(3);
      const harness = new FavoritesHarness([first, second, third]);

      expect(harness.store.isAllSelected()).assertFalse();
      harness.store.toggleSelection(first.key);
      harness.store.toggleSelection(third.key);
      expect(harness.store.selectedKeys).assertDeepEquals([first.key, third.key]);
      expect(harness.store.isSelected(third.key)).assertTrue();
      expect(harness.store.isAllSelected()).assertFalse();

      harness.store.toggleSelection(third.key);
      expect(harness.store.selectedKeys).assertDeepEquals([first.key]);

      harness.store.selectAll();
      expect(harness.store.selectedKeys.length).assertEqual(3);
      expect(harness.store.isAllSelected()).assertTrue();
      expect(trackKeys(harness.store.selectedTracks())).assertDeepEquals([
        first.key,
        second.key,
        third.key
      ]);

      harness.store.clearSelection();
      expect(harness.store.selectedKeys.length).assertEqual(0);
      expect(harness.store.isAllSelected()).assertFalse();
    });

    it('batchRemovesSelectedFavoritesInOneWrite', 0, async () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const third = favoriteTrack(3);
      const harness = new FavoritesHarness([first, second, third]);

      harness.store.toggleSelection(first.key);
      harness.store.toggleSelection(third.key);
      const writesBeforeRemoval = harness.persistence.writeCount;

      const removed = await harness.store.removeSelected();

      expect(removed).assertTrue();
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([second.key]);
      expect(harness.store.selectedKeys.length).assertEqual(0);
      expect(harness.store.batchBusy).assertFalse();
      expect(harness.persistence.writeCount).assertEqual(writesBeforeRemoval + 1);
      const persisted = JSON.parse(harness.persistence.content ?? '{}') as LibrarySnapshot;
      expect(trackKeys(persisted.favorites)).assertDeepEquals([second.key]);
    });

    it('keepsSelectionWhenBatchRemovalFails', 0, async () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const harness = new FavoritesHarness([first, second]);
      harness.store.toggleSelection(first.key);
      harness.persistence.failWrites = true;

      const removed = await harness.store.removeSelected();

      expect(removed).assertFalse();
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key, second.key]);
      expect(harness.store.selectedKeys).assertDeepEquals([first.key]);
      expect(harness.store.batchBusy).assertFalse();
      expect(harness.store.error?.code).assertEqual('library.writeFailed');

      harness.store.clearError();
      harness.persistence.failWrites = false;
      const retried = await harness.store.removeSelected();
      expect(retried).assertTrue();
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([second.key]);
    });

    it('dropsSelectionWhenTheFavoriteDisappearsFromTheList', 0, async () => {
      const first = favoriteTrack(1);
      const second = favoriteTrack(2);
      const harness = new FavoritesHarness([first, second]);
      harness.store.toggleSelection(first.key);

      await harness.store.remove(first.key);

      expect(harness.store.selectedKeys.length).assertEqual(0);
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([second.key]);
    });
  });
}
