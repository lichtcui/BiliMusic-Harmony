import { describe, expect, it } from '@ohos/hypium';
import { LibraryPersistence, LibraryStore } from '../main/ets/services/LibraryStore';
import { LibraryStoreModel } from '../main/ets/state/LibraryStoreModel';
import {
  TrackActionBusyState,
  TrackActionFeedback,
  TrackActionOutcome,
  TrackActionStore
} from '../main/ets/state/TrackActionStore';
import {
  LibrarySnapshot,
  MobileTrack,
  Playlist,
  STORAGE_VERSION
} from '../main/ets/types/MobileTypes';
import { wait } from '../main/ets/util/Errors';

class TrackActionMemoryPersistence implements LibraryPersistence {
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
      throw new Error('simulated track action write failure');
    }
    this.content = content;
  }

  preserveCorrupt(_path: string): void {
  }
}

class TrackActionHarness {
  readonly persistence: TrackActionMemoryPersistence;
  readonly libraryModel: LibraryStoreModel;
  readonly store: TrackActionStore;
  readonly track: MobileTrack;

  constructor(favorites: MobileTrack[] = [], playlists: Playlist[] = []) {
    this.track = actionTrack(1);
    this.persistence = new TrackActionMemoryPersistence(JSON.stringify(actionLibrary(favorites, playlists)));
    this.libraryModel = new LibraryStoreModel(new LibraryStore('memory://track-actions', this.persistence));
    this.store = new TrackActionStore(this.libraryModel);
    this.store.attach();
    this.store.open(this.track);
  }
}

function actionLibrary(favorites: MobileTrack[], playlists: Playlist[]): LibrarySnapshot {
  return {
    version: STORAGE_VERSION,
    favorites: favorites,
    playlists: playlists,
    recent: [],
    positions: {},
    updatedAt: 1
  };
}

function actionTrack(id: number): MobileTrack {
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

function actionPlaylist(id: string, name: string, tracks: MobileTrack[] = []): Playlist {
  return {
    id: id,
    name: name,
    tracks: tracks,
    createdAt: 1,
    updatedAt: 2
  };
}

function persistedActionLibrary(persistence: TrackActionMemoryPersistence): LibrarySnapshot {
  return JSON.parse(persistence.content ?? '{}') as LibrarySnapshot;
}

export default function trackActionStoreTest(): void {
  describe('TrackActionStore', () => {
    it('updatesFavoriteOnlyAfterSuccessfulPersistence', 0, async () => {
      const harness = new TrackActionHarness();

      const pending = harness.store.toggleFavorite();
      expect(harness.store.isFavorite).assertFalse();
      expect(harness.store.busyAction).assertEqual(TrackActionBusyState.Favorite);

      expect(await pending).assertEqual(TrackActionOutcome.Success);
      expect(harness.store.isFavorite).assertTrue();
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.FavoriteAdded);
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(persistedActionLibrary(harness.persistence).favorites.length).assertEqual(1);
    });

    it('keepsFavoriteStateWhenPersistenceFails', 0, async () => {
      const track = actionTrack(1);
      const harness = new TrackActionHarness([track]);
      harness.persistence.failWrites = true;

      expect(await harness.store.toggleFavorite()).assertEqual(TrackActionOutcome.Failed);
      expect(harness.store.isFavorite).assertTrue();
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.WriteFailed);
      expect(harness.libraryModel.isFavorite(track.key)).assertTrue();
      expect(persistedActionLibrary(harness.persistence).favorites.length).assertEqual(1);
    });

    it('addsToExistingPlaylistAndPersistsTheTrack', 0, async () => {
      const playlist = actionPlaylist('playlist-1', 'Daily Mix');
      const harness = new TrackActionHarness([], [playlist]);

      const pending = harness.store.addToPlaylist(playlist.id);
      expect(harness.store.busyAction).assertEqual(TrackActionBusyState.AddToPlaylist);
      expect(harness.store.busyPlaylistId).assertEqual(playlist.id);

      expect(await pending).assertEqual(TrackActionOutcome.Success);
      // 加入成功后不再弹反馈条：状态由歌单行的对勾表达。
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.None);
      expect(harness.store.busyPlaylistId).assertEqual('');
      expect(harness.store.playlists[0].containsTrack).assertTrue();
      expect(harness.store.playlists[0].trackCount).assertEqual(1);
      expect(persistedActionLibrary(harness.persistence).playlists[0].tracks[0].key)
        .assertEqual(harness.track.key);
    });

    it('resolvesPlaylistCoverFromCustomUriFirst', 0, async () => {
      const playlist = actionPlaylist('playlist-1', 'Daily Mix', [actionTrack(2)]);
      playlist.coverUri = 'file://custom-cover.jpg';
      const harness = new TrackActionHarness([], [playlist]);

      expect(harness.store.playlists[0].coverUrl).assertEqual('file://custom-cover.jpg');
    });

    it('fallsBackToFirstTrackCoverWhenNoCustomCover', 0, async () => {
      const first = actionTrack(2);
      const playlist = actionPlaylist('playlist-1', 'Daily Mix', [first, actionTrack(3)]);
      const harness = new TrackActionHarness([], [playlist]);

      expect(harness.store.playlists[0].coverUrl).assertEqual(first.coverUrl);
    });

    it('leavesEmptyPlaylistCoverEmpty', 0, async () => {
      const playlist = actionPlaylist('playlist-1', 'Daily Mix');
      const harness = new TrackActionHarness([], [playlist]);

      expect(harness.store.playlists[0].coverUrl).assertEqual('');
    });

    it('keepsPlaylistStateWhenAddWriteFails', 0, async () => {
      const playlist = actionPlaylist('playlist-1', 'Daily Mix');
      const harness = new TrackActionHarness([], [playlist]);
      harness.persistence.failWrites = true;

      expect(await harness.store.addToPlaylist(playlist.id)).assertEqual(TrackActionOutcome.Failed);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.WriteFailed);
      expect(harness.store.playlists[0].containsTrack).assertFalse();
      expect(harness.store.playlists[0].trackCount).assertEqual(0);
      expect(harness.libraryModel.playlistList()[0].tracks.length).assertEqual(0);
      expect(persistedActionLibrary(harness.persistence).playlists[0].tracks.length).assertEqual(0);
    });

    it('doesNotWriteWhenTrackIsAlreadyInPlaylist', 0, async () => {
      const track = actionTrack(1);
      const playlist = actionPlaylist('playlist-1', 'Daily Mix', [track]);
      const harness = new TrackActionHarness([], [playlist]);

      expect(await harness.store.addToPlaylist(playlist.id)).assertEqual(TrackActionOutcome.Duplicate);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.Duplicate);
      expect(harness.persistence.writeCount).assertEqual(0);
    });

    it('reportsDeletedPlaylistWithoutWriting', 0, async () => {
      const playlist = actionPlaylist('playlist-1', 'Daily Mix');
      const harness = new TrackActionHarness([], [playlist]);
      await harness.libraryModel.deletePlaylist(playlist.id);
      const writesAfterDelete = harness.persistence.writeCount;

      expect(await harness.store.addToPlaylist(playlist.id)).assertEqual(TrackActionOutcome.PlaylistNotFound);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.PlaylistNotFound);
      expect(harness.persistence.writeCount).assertEqual(writesAfterDelete);
    });

    it('createsPlaylistAndAddsCurrentTrack', 0, async () => {
      const harness = new TrackActionHarness();

      expect(await harness.store.createPlaylistAndAdd('  Road Trip  ')).assertEqual(TrackActionOutcome.Success);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.PlaylistCreated);
      expect(harness.libraryModel.playlistList().length).assertEqual(1);
      expect(harness.libraryModel.playlistList()[0].name).assertEqual('Road Trip');
      expect(harness.libraryModel.playlistList()[0].tracks[0].key).assertEqual(harness.track.key);
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(persistedActionLibrary(harness.persistence).playlists[0].tracks.length).assertEqual(1);
    });

    it('blocksRapidRepeatedWrites', 0, async () => {
      const playlist = actionPlaylist('playlist-1', 'Daily Mix');
      const harness = new TrackActionHarness([], [playlist]);

      const favorite = harness.store.toggleFavorite();
      const repeatedFavorite = harness.store.toggleFavorite();
      expect(await repeatedFavorite).assertEqual(TrackActionOutcome.Busy);
      expect(await favorite).assertEqual(TrackActionOutcome.Success);

      const add = harness.store.addToPlaylist(playlist.id);
      const repeatedAdd = harness.store.addToPlaylist(playlist.id);
      expect(await repeatedAdd).assertEqual(TrackActionOutcome.Busy);
      expect(await add).assertEqual(TrackActionOutcome.Success);

      const create = harness.store.createPlaylistAndAdd('Road Trip');
      const repeatedCreate = harness.store.createPlaylistAndAdd('Road Trip');
      expect(await repeatedCreate).assertEqual(TrackActionOutcome.Busy);
      expect(await create).assertEqual(TrackActionOutcome.Success);

      expect(harness.libraryModel.favoriteTracks().length).assertEqual(1);
      expect(harness.libraryModel.playlistList().length).assertEqual(2);
      expect(harness.libraryModel.playlistById(playlist.id)?.tracks.length).assertEqual(1);
      expect(harness.persistence.writeCount).assertEqual(3);
    });

    it('batchesMultipleTracksIntoExistingPlaylist', 0, async () => {
      const playlist = actionPlaylist('playlist-1', 'Daily Mix');
      const harness = new TrackActionHarness([], [playlist]);
      const tracks = [actionTrack(1), actionTrack(2), actionTrack(3)];
      expect(harness.store.openMany(tracks, '精选合集', '精选合集')).assertTrue();
      expect(harness.store.isMulti()).assertTrue();
      expect(harness.store.selectedTracks.length).assertEqual(3);
      expect(harness.store.isFavorite).assertFalse();

      expect(await harness.store.addToPlaylist(playlist.id)).assertEqual(TrackActionOutcome.Success);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.None);
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(harness.libraryModel.playlistById(playlist.id)?.tracks.length).assertEqual(3);
    });

    it('batchSkipsDuplicateTracks', 0, async () => {
      const first = actionTrack(1);
      const second = actionTrack(2);
      const playlist = actionPlaylist('playlist-1', 'Daily Mix', [first]);
      const harness = new TrackActionHarness([], [playlist]);
      harness.store.openMany([first, second, second], '合集', '');

      expect(await harness.store.addToPlaylist(playlist.id)).assertEqual(TrackActionOutcome.Success);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.None);
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(harness.libraryModel.playlistById(playlist.id)?.tracks.length).assertEqual(2);
    });

    it('batchTreatsAllPresentAsDuplicateWithoutWriting', 0, async () => {
      const first = actionTrack(1);
      const second = actionTrack(2);
      const playlist = actionPlaylist('playlist-1', 'Daily Mix', [first, second]);
      const harness = new TrackActionHarness([], [playlist]);
      harness.store.openMany([first, second], '合集', '');

      expect(await harness.store.addToPlaylist(playlist.id)).assertEqual(TrackActionOutcome.Duplicate);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.Duplicate);
      expect(harness.persistence.writeCount).assertEqual(0);
    });

    it('batchCreatesPlaylistWithTracksInOneWrite', 0, async () => {
      const harness = new TrackActionHarness();
      harness.store.openMany([actionTrack(1), actionTrack(2)], '合集', '合集歌单');

      expect(await harness.store.createPlaylistAndAdd('合集歌单')).assertEqual(TrackActionOutcome.Success);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.PlaylistCreated);
      expect(harness.store.feedbackCount).assertEqual(2);
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(harness.libraryModel.playlistList()[0].tracks.length).assertEqual(2);
    });

    it('batchWithSingleTrackStillHidesFavorite', 0, async () => {
      const harness = new TrackActionHarness();
      harness.store.openMany([actionTrack(1)], '合集', '');

      expect(harness.store.isMulti()).assertTrue();
      expect(await harness.store.toggleFavorite()).assertEqual(TrackActionOutcome.Failed);
      expect(harness.store.favoriteCandidateCount).assertEqual(1);
      expect(await harness.store.addSelectedToFavorites()).assertEqual(TrackActionOutcome.Success);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.FavoriteBatchAdded);
      expect(harness.store.feedbackCount).assertEqual(1);
      expect(harness.persistence.writeCount).assertEqual(1);
    });

    it('batchAddsOnlyFavoriteCandidatesAndReportsCount', 0, async () => {
      const first = actionTrack(1);
      const second = actionTrack(2);
      const third = actionTrack(3);
      const harness = new TrackActionHarness([first]);
      harness.store.openMany([first, second, third], '合集', '');

      expect(harness.store.favoriteCandidateCount).assertEqual(2);
      expect(await harness.store.addSelectedToFavorites()).assertEqual(TrackActionOutcome.Success);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.FavoriteBatchAdded);
      expect(harness.store.feedbackCount).assertEqual(2);
      expect(harness.store.favoriteCandidateCount).assertEqual(0);
      expect(harness.libraryModel.favoriteTracks().length).assertEqual(3);
      expect(harness.persistence.writeCount).assertEqual(2);

      const writesBeforeRepeat = harness.persistence.writeCount;
      expect(await harness.store.addSelectedToFavorites()).assertEqual(TrackActionOutcome.Success);
      expect(harness.persistence.writeCount).assertEqual(writesBeforeRepeat);
    });

    it('batchFavoriteCompletesAfterDrawerCloses', 0, async () => {
      const harness = new TrackActionHarness();
      const tracks = [actionTrack(1), actionTrack(2), actionTrack(3)];
      harness.store.openMany(tracks, '合集', '');

      const pending = harness.store.addSelectedToFavorites();
      // 抽屉点击后立即收起：宿主会在滑出动画结束时 close()，批量写入不能中断。
      harness.store.close();

      expect(await pending).assertEqual(TrackActionOutcome.Success);
      expect(harness.libraryModel.favoriteTracks().length).assertEqual(3);
      expect(harness.persistence.writeCount).assertEqual(3);
    });

    it('batchFavoriteWriteFailureKeepsCandidates', 0, async () => {
      const first = actionTrack(1);
      const second = actionTrack(2);
      const harness = new TrackActionHarness();
      harness.store.openMany([first, second], '合集', '');
      harness.persistence.failWrites = true;

      expect(await harness.store.addSelectedToFavorites()).assertEqual(TrackActionOutcome.Failed);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.WriteFailed);
      expect(harness.store.favoriteCandidateCount).assertEqual(2);
      expect(harness.libraryModel.favoriteTracks().length).assertEqual(0);
    });

    it('closesAndClearsTemporaryActionState', 0, async () => {
      const track = actionTrack(1);
      const playlist = actionPlaylist('playlist-1', 'Daily Mix', [track]);
      const harness = new TrackActionHarness([], [playlist]);
      expect(await harness.store.addToPlaylist(playlist.id)).assertEqual(TrackActionOutcome.Duplicate);
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.Duplicate);

      harness.store.close();

      expect(harness.store.isOpen()).assertFalse();
      expect(harness.store.selectedTrack === null).assertTrue();
      expect(harness.store.isFavorite).assertFalse();
      expect(harness.store.playlists.length).assertEqual(0);
      expect(harness.store.busyAction).assertEqual(TrackActionBusyState.None);
      expect(harness.store.busyPlaylistId).assertEqual('');
      expect(harness.store.feedback).assertEqual(TrackActionFeedback.None);
    });
  });
}
