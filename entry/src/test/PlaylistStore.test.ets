import { describe, expect, it } from '@ohos/hypium';
import { LibraryPersistence, LibraryStore } from '../main/ets/services/LibraryStore';
import { LibraryStoreModel } from '../main/ets/state/LibraryStoreModel';
import {
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore
} from '../main/ets/state/PlayerStore';
import {
  PLAYLIST_DESCRIPTION_MAX_LENGTH,
  PLAYLIST_NAME_MAX_LENGTH,
  PlaylistActionResult,
  PlaylistStore
} from '../main/ets/state/PlaylistStore';
import {
  LibrarySnapshot,
  MobileTrack,
  PlaybackState,
  PlayerSessionSnapshot,
  Playlist,
  STORAGE_VERSION,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';
import { wait } from '../main/ets/util/Errors';

class PlaylistMemoryPersistence implements LibraryPersistence {
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
    await wait(2);
    if (this.failWrites) {
      throw new Error('simulated playlist write failure');
    }
    this.content = content;
  }

  preserveCorrupt(_path: string): void {
  }
}

class PlaylistFakeScheduler implements PlayerProgressScheduler {
  now(): number {
    return 1000;
  }

  schedule(_callback: () => void, _delayMs: number): number {
    return 1;
  }

  cancel(_timerId: number): void {
  }
}

class PlaylistFakePlayerTarget implements PlayerCommandTarget {
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

class PlaylistHarness {
  readonly persistence: PlaylistMemoryPersistence;
  readonly libraryModel: LibraryStoreModel;
  readonly playerStore: PlayerStore;
  readonly playerTarget: PlaylistFakePlayerTarget;
  readonly store: PlaylistStore;

  constructor(playlists: Playlist[] = []) {
    this.persistence = new PlaylistMemoryPersistence(JSON.stringify(playlistLibrary(playlists)));
    this.libraryModel = new LibraryStoreModel(new LibraryStore('memory://playlists', this.persistence));
    this.playerTarget = new PlaylistFakePlayerTarget();
    this.playerStore = new PlayerStore(new PlaylistFakeScheduler());
    this.playerStore.bind(this.playerTarget);
    this.store = new PlaylistStore(this.libraryModel, this.playerStore);
    this.store.attach();
  }
}

function playlistLibrary(playlists: Playlist[]): LibrarySnapshot {
  return {
    version: STORAGE_VERSION,
    favorites: [],
    playlists: playlists,
    recent: [],
    positions: {},
    updatedAt: 1
  };
}

function playlistTrack(id: number): MobileTrack {
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

function playlist(id: string, name: string, tracks: MobileTrack[] = []): Playlist {
  return {
    id: id,
    name: name,
    tracks: tracks,
    createdAt: 1,
    updatedAt: 2
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
  return result;
}

function trackKeys(tracks: MobileTrack[]): string[] {
  return tracks.map((track: MobileTrack): string => track.key);
}

function persistedPlaylists(persistence: PlaylistMemoryPersistence): Playlist[] {
  return (JSON.parse(persistence.content ?? '{}') as LibrarySnapshot).playlists;
}

export default function playlistStoreTest(): void {
  describe('PlaylistStore', () => {
    it('createsTrimmedPlaylistAndPersistsIt', 0, async () => {
      const harness = new PlaylistHarness();

      const result = await harness.store.create('  Road Trip  ');

      expect(result).assertEqual(PlaylistActionResult.Success);
      expect(harness.store.playlists.length).assertEqual(1);
      expect(harness.store.playlists[0].name).assertEqual('Road Trip');
      expect(harness.store.playlists[0].trackCount).assertEqual(0);
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(persistedPlaylists(harness.persistence)[0].name).assertEqual('Road Trip');
      const restarted = new LibraryStore('memory://playlists', harness.persistence);
      expect(restarted.read().playlists[0].name).assertEqual('Road Trip');
    });

    it('persistsTheCustomCoverAndDescriptionWhenCreating', 0, async () => {
      const harness = new PlaylistHarness();

      const result = await harness.store.create('Night Drive', 'file:///data/storage/el2/base/files/cover.img',
        '  深夜开车听  ');

      expect(result).assertEqual(PlaylistActionResult.Success);
      expect(harness.store.playlists[0].coverUrl)
        .assertEqual('file:///data/storage/el2/base/files/cover.img');
      const persisted = persistedPlaylists(harness.persistence)[0];
      expect(persisted.coverUri).assertEqual('file:///data/storage/el2/base/files/cover.img');
      expect(persisted.description).assertEqual('深夜开车听');
    });

    it('dropsNonSandboxCoverUrisAndTruncatesLongDescriptions', 0, async () => {
      const harness = new PlaylistHarness();

      expect(await harness.store.create('Remote Cover', 'https://example.com/cover.jpg', ''))
        .assertEqual(PlaylistActionResult.Success);
      expect(harness.store.playlists[0].coverUrl).assertEqual('');
      expect(persistedPlaylists(harness.persistence)[0].coverUri).assertEqual('');

      const longDescription = 'x'.repeat(PLAYLIST_DESCRIPTION_MAX_LENGTH + 20);
      expect(await harness.store.create('Long Text', '', longDescription))
        .assertEqual(PlaylistActionResult.Success);
      const created = persistedPlaylists(harness.persistence)[0];
      expect(created.description?.length).assertEqual(PLAYLIST_DESCRIPTION_MAX_LENGTH);
    });

    it('rejectsEmptyAndOverlongNamesWithoutWriting', 0, async () => {
      const harness = new PlaylistHarness();
      const tooLong = 'x'.repeat(PLAYLIST_NAME_MAX_LENGTH + 1);

      expect(await harness.store.create('   ')).assertEqual(PlaylistActionResult.InvalidName);
      expect(await harness.store.create(tooLong)).assertEqual(PlaylistActionResult.InvalidName);
      expect(harness.store.playlists.length).assertEqual(0);
      expect(harness.persistence.writeCount).assertEqual(0);

      expect(await harness.store.create('Mix')).assertEqual(PlaylistActionResult.Success);
      const playlistId = harness.store.playlists[0].id;
      const writesAfterCreate = harness.persistence.writeCount;
      expect(await harness.store.rename(playlistId, '  ')).assertEqual(PlaylistActionResult.InvalidName);
      expect(await harness.store.rename(playlistId, tooLong)).assertEqual(PlaylistActionResult.InvalidName);
      expect(harness.persistence.writeCount).assertEqual(writesAfterCreate);
      expect(harness.store.playlists[0].name).assertEqual('Mix');
    });

    it('blocksDuplicateCreateRenameAndDeleteWhileBusy', 0, async () => {
      const existing = playlist('playlist-1', 'Existing');
      const harness = new PlaylistHarness([existing]);

      const creating = harness.store.create('One');
      expect(harness.store.isBusy()).assertTrue();
      expect(await harness.store.create('Two')).assertEqual(PlaylistActionResult.Busy);
      expect(await creating).assertEqual(PlaylistActionResult.Success);

      const renaming = harness.store.rename(existing.id, 'Morning');
      expect(harness.store.isBusy()).assertTrue();
      expect(await harness.store.rename(existing.id, 'Evening')).assertEqual(PlaylistActionResult.Busy);
      expect(await renaming).assertEqual(PlaylistActionResult.Success);

      const deleting = harness.store.delete(existing.id);
      expect(harness.store.isBusy()).assertTrue();
      expect(await harness.store.delete(existing.id)).assertEqual(PlaylistActionResult.Busy);
      expect(await deleting).assertEqual(PlaylistActionResult.Success);
      expect(harness.persistence.writeCount).assertEqual(3);
    });

    it('renamesTheSelectedPlaylistAndRefreshesItsRow', 0, async () => {
      const existing = playlist('playlist-1', 'Old Name', [playlistTrack(1)]);
      const harness = new PlaylistHarness([existing]);
      expect(harness.store.selectPlaylist(existing.id)).assertTrue();

      const result = await harness.store.rename(existing.id, '  New Name  ');

      expect(result).assertEqual(PlaylistActionResult.Success);
      expect(harness.store.playlists.length).assertEqual(1);
      expect(harness.store.playlists[0].name).assertEqual('New Name');
      expect(harness.store.playlists[0].trackCount).assertEqual(1);
      expect(harness.store.selectedPlaylistId).assertEqual(existing.id);
      expect(persistedPlaylists(harness.persistence)[0].name).assertEqual('New Name');
    });

    it('updatesThePlaylistNameDescriptionAndCustomCoverInOneWrite', 0, async () => {
      const existing = playlist('playlist-1', 'Old Name', [playlistTrack(1)]);
      const harness = new PlaylistHarness([existing]);
      const writesBeforeUpdate = harness.persistence.writeCount;

      const result = await harness.store.update(existing.id, '  Night Drive  ',
        'file:///data/storage/el2/base/files/cover.img', '  深夜开车听  ');

      expect(result).assertEqual(PlaylistActionResult.Success);
      expect(harness.store.playlists[0].name).assertEqual('Night Drive');
      expect(harness.store.playlists[0].coverUri)
        .assertEqual('file:///data/storage/el2/base/files/cover.img');
      expect(harness.store.playlists[0].description).assertEqual('深夜开车听');
      expect(harness.store.playlists[0].trackCount).assertEqual(1);
      expect(harness.persistence.writeCount).assertEqual(writesBeforeUpdate + 1);
      const persisted = persistedPlaylists(harness.persistence)[0];
      expect(persisted.name).assertEqual('Night Drive');
      expect(persisted.coverUri).assertEqual('file:///data/storage/el2/base/files/cover.img');
      expect(persisted.description).assertEqual('深夜开车听');

      expect(await harness.store.update(existing.id, '  ')).assertEqual(PlaylistActionResult.InvalidName);
      expect(await harness.store.update('missing-playlist', 'Name')).assertEqual(PlaylistActionResult.NotFound);
    });

    it('keepsRowsAndPersistedNamesAfterWriteFailures', 0, async () => {
      const existing = playlist('playlist-1', 'Stable Name');
      const harness = new PlaylistHarness([existing]);
      harness.persistence.failWrites = true;

      expect(await harness.store.create('Lost Playlist')).assertEqual(PlaylistActionResult.Failed);
      expect(await harness.store.rename(existing.id, 'Lost Rename')).assertEqual(PlaylistActionResult.Failed);
      expect(await harness.store.delete(existing.id)).assertEqual(PlaylistActionResult.Failed);

      expect(harness.store.playlists.length).assertEqual(1);
      expect(harness.store.playlists[0].name).assertEqual('Stable Name');
      expect(harness.store.error?.code).assertEqual('library.writeFailed');
      expect(persistedPlaylists(harness.persistence).length).assertEqual(1);
      expect(persistedPlaylists(harness.persistence)[0].name).assertEqual('Stable Name');
    });

    it('deletesSelectedPlaylistAndClearsSelectionAndPersistence', 0, async () => {
      const first = playlist('playlist-1', 'First');
      const second = playlist('playlist-2', 'Second');
      const harness = new PlaylistHarness([first, second]);
      expect(harness.store.selectPlaylist(first.id)).assertTrue();

      const result = await harness.store.delete(first.id);

      expect(result).assertEqual(PlaylistActionResult.Success);
      expect(harness.store.playlists.length).assertEqual(1);
      expect(harness.store.playlists[0].id).assertEqual(second.id);
      expect(harness.store.selectedPlaylistId).assertEqual('');
      expect(harness.store.playlistById(first.id) === null).assertTrue();
      expect(persistedPlaylists(harness.persistence).length).assertEqual(1);
      expect(persistedPlaylists(harness.persistence)[0].id).assertEqual(second.id);
    });

    it('derivesPlaylistCoverFromTheFirstTrackOnly', 0, () => {
      const withCover = playlist('playlist-cover', 'Cover', [
        playlistTrack(1),
        playlistTrack(2)
      ]);
      const emptyPlaylist = playlist('playlist-empty', 'Empty');
      const harness = new PlaylistHarness([withCover, emptyPlaylist]);

      expect(harness.store.playlists[0].coverUrl).assertEqual('https://example.com/1.jpg');
      expect(harness.store.playlists[0].trackCount).assertEqual(2);
      expect(harness.store.playlists[1].coverUrl).assertEqual('');
      expect(harness.store.playlists[1].trackCount).assertEqual(0);

      const cloned = harness.store.playlistById('playlist-cover');
      expect(cloned === null).assertFalse();
      expect(cloned?.coverUrl).assertEqual('https://example.com/1.jpg');
    });

    it('prefersTheCustomCoverAndExposesTrackKeysForQueueMatching', 0, () => {
      const custom = playlist('playlist-custom', 'Custom', [playlistTrack(1), playlistTrack(2)]);
      custom.coverUri = 'file:///data/storage/el2/base/files/custom.img';
      const harness = new PlaylistHarness([custom]);

      expect(harness.store.playlists[0].coverUrl)
        .assertEqual('file:///data/storage/el2/base/files/custom.img');
      expect(harness.store.playlists[0].trackKeys).assertDeepEquals([
        custom.tracks[0].key,
        custom.tracks[1].key
      ]);
    });

    it('fallsBackToEmptyCoverWhenTheFirstTrackHasNoCover', 0, () => {
      const bare = playlistTrack(3);
      bare.coverUrl = '  ';
      const harness = new PlaylistHarness([playlist('playlist-bare', 'Bare', [bare])]);

      expect(harness.store.playlists[0].coverUrl).assertEqual('');
    });

    it('playsTheTappedPlaylistFromItsFirstTrack', 0, async () => {
      const first = playlist('playlist-play', 'Play Me', [playlistTrack(1), playlistTrack(2)]);
      const other = playlist('playlist-other', 'Other', [playlistTrack(3)]);
      const harness = new PlaylistHarness([first, other]);

      const played = await harness.store.playAll(first.id);

      expect(played).assertTrue();
      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([
        first.tracks[0].key,
        first.tracks[1].key
      ]);
      expect(harness.playerTarget.startIndex).assertEqual(0);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('ignoresEmptyOrUnknownPlaylistsWithoutStartingPlayback', 0, async () => {
      const empty = playlist('playlist-empty', 'Empty');
      const harness = new PlaylistHarness([empty]);

      expect(await harness.store.playAll(empty.id)).assertFalse();
      expect(await harness.store.playAll('missing-playlist')).assertFalse();

      expect(harness.playerTarget.loadQueueCalls).assertEqual(0);
    });
  });
}
