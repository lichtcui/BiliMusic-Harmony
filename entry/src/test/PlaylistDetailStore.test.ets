import { describe, expect, it } from '@ohos/hypium';
import { LibraryPersistence, LibraryStore } from '../main/ets/services/LibraryStore';
import {
  LibraryStoreModel,
  LibraryStoreModelListener
} from '../main/ets/state/LibraryStoreModel';
import { PlaylistDetailStore } from '../main/ets/state/PlaylistDetailStore';
import {
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore,
  PlayerViewSnapshot
} from '../main/ets/state/PlayerStore';
import {
  AppError,
  LibrarySnapshot,
  MobileTrack,
  PlaybackState,
  PlaybackStatus,
  PlayerSessionSnapshot,
  Playlist,
  STORAGE_VERSION,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';
import { wait } from '../main/ets/util/Errors';

const PLAYLIST_ID: string = 'playlist-detail';

class DetailFakeScheduler implements PlayerProgressScheduler {
  now(): number {
    return 1000;
  }

  schedule(_callback: () => void, _delayMs: number): number {
    return 1;
  }

  cancel(_timerId: number): void {
  }
}

class DetailFakePlayerTarget implements PlayerCommandTarget {
  state: PlaybackState = emptyPlaybackState();
  queue: MobileTrack[] = [];
  appended: MobileTrack[] = [];
  startIndex: number = -1;
  autoplay: boolean = false;
  loadQueueCalls: number = 0;
  appendCalls: number = 0;
  playCalls: number = 0;
  pauseCalls: number = 0;

  loadQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.loadQueueCalls++;
    this.queue = cloneTracks(params.queue as MobileTrack[]);
    this.startIndex = params.startIndex as number;
    this.autoplay = params.autoplay as boolean;
    return Promise.resolve(clonePlaybackState(this.state));
  }

  appendToQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.appendCalls++;
    this.appended = this.appended.concat(cloneTracks(params.queue as MobileTrack[]));
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
    this.playCalls++;
    this.state.status = 'playing';
    return Promise.resolve(clonePlaybackState(this.state));
  }

  pause(): Promise<PlaybackState> {
    this.pauseCalls++;
    this.state.status = 'paused';
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

class DetailMemoryPersistence implements LibraryPersistence {
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
      throw new Error('simulated playlist detail write failure');
    }
    this.content = content;
  }

  preserveCorrupt(_path: string): void {
  }
}

class DetailLibraryListener implements LibraryStoreModelListener {
  snapshots: LibrarySnapshot[] = [];
  errors: AppError[] = [];

  onLibraryChanged(snapshot: LibrarySnapshot): void {
    this.snapshots.push(snapshot);
  }

  onLibraryError(error: AppError): void {
    this.errors.push(error);
  }
}

class PlaylistDetailHarness {
  readonly playerTarget: DetailFakePlayerTarget;
  readonly playerStore: PlayerStore;
  readonly persistence: DetailMemoryPersistence;
  readonly libraryModel: LibraryStoreModel;
  readonly store: PlaylistDetailStore;
  readonly listener: DetailLibraryListener;

  constructor(tracks: MobileTrack[] = []) {
    this.playerTarget = new DetailFakePlayerTarget();
    this.playerStore = new PlayerStore(new DetailFakeScheduler());
    this.playerStore.bind(this.playerTarget);
    this.persistence = new DetailMemoryPersistence(JSON.stringify(
      playlistLibrary(playlist(PLAYLIST_ID, 'Road Trip', tracks))
    ));
    this.libraryModel = new LibraryStoreModel(new LibraryStore('memory://playlist-detail', this.persistence));
    this.store = new PlaylistDetailStore(this.libraryModel, this.playerStore, PLAYLIST_ID);
    this.store.attach();
    this.listener = new DetailLibraryListener();
    this.libraryModel.subscribe(this.listener);
  }
}

function playlistLibrary(value: Playlist): LibrarySnapshot {
  return {
    version: STORAGE_VERSION,
    favorites: [],
    playlists: [value],
    recent: [],
    positions: {},
    updatedAt: 1
  };
}

function playlist(id: string, name: string, tracks: MobileTrack[]): Playlist {
  return {
    id: id,
    name: name,
    tracks: cloneTracks(tracks),
    createdAt: 1,
    updatedAt: 2
  };
}

function detailTrack(id: number): MobileTrack {
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

function trackKeys(tracks: MobileTrack[]): string[] {
  return tracks.map((track: MobileTrack): string => track.key);
}

function cloneTrack(track: MobileTrack): MobileTrack {
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
  return tracks.map((track: MobileTrack): MobileTrack => cloneTrack(track));
}

function clonePlaybackState(state: PlaybackState): PlaybackState {
  const result = emptyPlaybackState();
  result.status = state.status;
  result.track = state.track === null ? null : cloneTrack(state.track);
  result.position = state.position;
  result.duration = state.duration;
  result.volume = state.volume;
  result.mode = state.mode;
  result.queue = cloneTracks(state.queue);
  result.queueIndex = state.queueIndex;
  if (state.error !== undefined) {
    result.error = {
      code: state.error.code,
      message: state.error.message,
      retryable: state.error.retryable
    };
  }
  return result;
}

function viewSnapshot(status: PlaybackStatus, track: MobileTrack | null,
  queue: MobileTrack[], queueIndex: number): PlayerViewSnapshot {
  return {
    status: status,
    track: track,
    duration: track === null ? 0 : track.duration,
    mode: 'sequence',
    queue: queue,
    queueIndex: queueIndex
  };
}

export default function playlistDetailStoreTest(): void {
  describe('PlaylistDetailStore', () => {
    it('playsAllTracksFromTheFirstQueueIndex', 0, async () => {
      const first = detailTrack(1);
      const second = detailTrack(2);
      const harness = new PlaylistDetailHarness([second, first]);

      await harness.store.playAll();

      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([second.key, first.key]);
      expect(harness.playerTarget.startIndex).assertEqual(0);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('playsASelectedTrackAtItsPlaylistIndex', 0, async () => {
      const first = detailTrack(1);
      const second = detailTrack(2);
      const third = detailTrack(3);
      const harness = new PlaylistDetailHarness([third, second, first]);

      expect(await harness.store.playTrack(second.key)).assertTrue();

      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([third.key, second.key, first.key]);
      expect(harness.playerTarget.startIndex).assertEqual(1);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('appendsTheSelectedTrackWithoutDeduplicatingTheQueue', 0, async () => {
      const first = detailTrack(1);
      const harness = new PlaylistDetailHarness([first]);

      expect(await harness.store.appendTrack(first.key)).assertTrue();
      expect(await harness.store.appendTrack(first.key)).assertTrue();

      expect(harness.playerTarget.appendCalls).assertEqual(2);
      expect(trackKeys(harness.playerTarget.appended)).assertDeepEquals([first.key, first.key]);
    });

    it('togglesSelectsAllAndClearsTrackSelection', 0, () => {
      const first = detailTrack(1);
      const second = detailTrack(2);
      const harness = new PlaylistDetailHarness([first, second]);

      expect(harness.store.toggleSelection(first.key)).assertTrue();
      expect(harness.store.isSelected(first.key)).assertTrue();
      expect(harness.store.toggleSelection(first.key)).assertTrue();
      expect(harness.store.isSelected(first.key)).assertFalse();

      harness.store.selectAll();
      expect(harness.store.selectedKeys).assertDeepEquals([first.key, second.key]);
      expect(harness.store.isAllSelected()).assertTrue();
      expect(trackKeys(harness.store.selectedTracks())).assertDeepEquals([first.key, second.key]);
      harness.store.clearSelection();
      expect(harness.store.selectedKeys.length).assertEqual(0);
      expect(harness.store.isAllSelected()).assertFalse();
    });

    it('treatsAllSelectedOnlyWhenEveryTrackIsChecked', 0, () => {
      const first = detailTrack(1);
      const second = detailTrack(2);
      const harness = new PlaylistDetailHarness([first, second]);

      expect(harness.store.isAllSelected()).assertFalse();
      harness.store.toggleSelection(first.key);
      expect(harness.store.isAllSelected()).assertFalse();
      harness.store.toggleSelection(second.key);
      expect(harness.store.isAllSelected()).assertTrue();
      expect(trackKeys(harness.store.selectedTracks())).assertDeepEquals([first.key, second.key]);
      harness.store.toggleSelection(second.key);
      expect(harness.store.isAllSelected()).assertFalse();
      expect(trackKeys(harness.store.selectedTracks())).assertDeepEquals([first.key]);
    });

    it('removesSelectedTracksWithOneFinalSnapshotAndClearsSelection', 0, async () => {
      const first = detailTrack(1);
      const second = detailTrack(2);
      const third = detailTrack(3);
      const harness = new PlaylistDetailHarness([first, second, third]);
      harness.store.toggleSelection(first.key);
      harness.store.toggleSelection(third.key);

      expect(await harness.store.removeSelected()).assertTrue();

      expect(trackKeys(harness.store.tracks)).assertDeepEquals([second.key]);
      expect(harness.store.selectedKeys.length).assertEqual(0);
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(harness.listener.snapshots.length).assertEqual(1);
      expect(trackKeys(harness.listener.snapshots[0].playlists[0].tracks)).assertDeepEquals([second.key]);
    });

    it('keepsTracksAndSelectionWhenBatchRemovalFails', 0, async () => {
      const first = detailTrack(1);
      const second = detailTrack(2);
      const third = detailTrack(3);
      const harness = new PlaylistDetailHarness([first, second, third]);
      harness.store.toggleSelection(first.key);
      harness.store.toggleSelection(third.key);
      harness.persistence.failWrites = true;

      expect(await harness.store.removeSelected()).assertFalse();

      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key, second.key, third.key]);
      expect(harness.store.selectedKeys).assertDeepEquals([first.key, third.key]);
      expect(harness.store.error?.code).assertEqual('library.writeFailed');
      expect(harness.persistence.writeCount).assertEqual(1);
      expect(harness.listener.snapshots.length).assertEqual(0);
    });

    it('derivesHeroCoverAndTotalDurationFromTracks', 0, () => {
      const first = detailTrack(1);
      first.coverUrl = '';
      first.duration = 0;
      const second = detailTrack(2);
      second.coverUrl = 'https://example.com/second.jpg';
      second.duration = 125;
      const harness = new PlaylistDetailHarness([first, second]);

      // 第一首没有封面时取后一首；未知时长（0）不参与求和。
      expect(harness.store.coverUrl).assertEqual('https://example.com/second.jpg');
      expect(harness.store.totalDuration).assertEqual(125);
    });

    it('prefersTheCustomCoverAndDescriptionOfThePlaylist', 0, () => {
      const first = detailTrack(1);
      const value = playlist(PLAYLIST_ID, 'Road Trip', [first]);
      value.coverUri = 'file:///data/storage/el2/base/files/custom.img';
      value.description = '  深夜开车听  ';
      const persistence = new DetailMemoryPersistence(JSON.stringify(playlistLibrary(value)));
      const libraryModel = new LibraryStoreModel(new LibraryStore('memory://detail-meta', persistence));
      const playerStore = new PlayerStore(new DetailFakeScheduler());
      const store = new PlaylistDetailStore(libraryModel, playerStore, PLAYLIST_ID);

      expect(store.coverUrl).assertEqual('file:///data/storage/el2/base/files/custom.img');
      expect(store.description).assertEqual('深夜开车听');
    });

    it('togglesHeroPlaybackBetweenPauseAndResumeForThisPlaylist', 0, async () => {
      const first = detailTrack(1);
      const second = detailTrack(2);
      const harness = new PlaylistDetailHarness([first, second]);
      const playing = emptyPlaybackState();
      playing.status = 'playing';
      playing.track = cloneTrack(first);
      playing.duration = first.duration;
      playing.queue = cloneTracks([first, second]);
      harness.playerTarget.state = playing;
      harness.store.onState(viewSnapshot('playing', first, [first, second], 0));

      expect(harness.store.isPlayingThisPlaylist()).assertTrue();
      await harness.store.togglePlayback();
      expect(harness.playerTarget.pauseCalls).assertEqual(1);
      expect(harness.store.playbackStatus).assertEqual('paused');
      expect(harness.store.isPlayingThisPlaylist()).assertFalse();

      await harness.store.togglePlayback();
      expect(harness.playerTarget.playCalls).assertEqual(1);
      expect(harness.store.playbackStatus).assertEqual('playing');
      expect(harness.store.isPlayingThisPlaylist()).assertTrue();
    });

    it('startsThisPlaylistWhenAnotherPlaylistIsPlaying', 0, async () => {
      const first = detailTrack(1);
      const other = detailTrack(9);
      const harness = new PlaylistDetailHarness([first]);
      const playingOther = emptyPlaybackState();
      playingOther.status = 'playing';
      playingOther.track = cloneTrack(other);
      playingOther.duration = other.duration;
      playingOther.queue = cloneTracks([other]);
      harness.playerTarget.state = playingOther;
      harness.store.onState(viewSnapshot('playing', other, [other], 0));

      expect(harness.store.isPlayingThisPlaylist()).assertFalse();
      await harness.store.togglePlayback();
      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([first.key]);
      expect(harness.playerTarget.startIndex).assertEqual(0);
    });

    it('marksTheDetailMissingWhenThePlaylistIsDeletedExternally', 0, async () => {
      const harness = new PlaylistDetailHarness([detailTrack(1)]);

      await harness.libraryModel.deletePlaylist(PLAYLIST_ID);
      await harness.store.playAll();

      expect(harness.store.missing).assertTrue();
      expect(harness.store.tracks.length).assertEqual(0);
      expect(harness.store.selectedKeys.length).assertEqual(0);
      expect(harness.store.coverUrl).assertEqual('');
      expect(harness.store.totalDuration).assertEqual(0);
      expect(harness.playerTarget.loadQueueCalls).assertEqual(0);
    });
  });
}
