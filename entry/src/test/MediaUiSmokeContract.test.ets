import { describe, expect, it } from '@ohos/hypium';
import { LyricsPanelState } from '../main/ets/components/native/LyricsPanelState';
import { NativeUiIds } from '../main/ets/components/native/NativeUiIds';
import { PlayerPageState } from '../main/ets/components/native/PlayerPageState';
import { QueuePageState } from '../main/ets/components/native/QueuePageState';
import { LibraryPersistence, LibraryStore } from '../main/ets/services/LibraryStore';
import { FavoritesStore } from '../main/ets/state/FavoritesStore';
import { LibraryStoreModel } from '../main/ets/state/LibraryStoreModel';
import { LyricsGateway, LyricsStore } from '../main/ets/state/LyricsStore';
import { PlaylistDetailStore } from '../main/ets/state/PlaylistDetailStore';
import { PlaylistStore } from '../main/ets/state/PlaylistStore';
import {
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore
} from '../main/ets/state/PlayerStore';
import { RecentPlaybackStore } from '../main/ets/state/RecentPlaybackStore';
import {
  LibrarySnapshot,
  LyricCandidate,
  LyricLine,
  LyricResult,
  MobileTrack,
  PlaybackState,
  PlaybackStatus,
  PlayerMode,
  PlayerSessionSnapshot,
  Playlist,
  STORAGE_VERSION,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';
import { wait } from '../main/ets/util/Errors';

class MediaSmokeScheduler implements PlayerProgressScheduler {
  private time: number = 1000;

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

class MediaSmokePlayerTarget implements PlayerCommandTarget {
  state: PlaybackState = emptyPlaybackState();
  readonly calls: string[] = [];
  seekPosition: number = -1;
  requestedMode: PlayerMode | '' = '';
  playIndex: number = -1;
  deferRemoval: boolean = false;
  private removalResolve: ((state: PlaybackState) => void) | null = null;

  loadQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('loadQueue');
    this.playIndex = params.startIndex as number;
    return this.complete();
  }

  appendToQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('appendToQueue');
    return this.complete();
  }

  removeFromQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('removeFromQueue');
    if (!this.deferRemoval) {
      return this.complete();
    }
    return new Promise<PlaybackState>((resolve) => {
      this.removalResolve = resolve;
    });
  }

  resolveRemoval(state: PlaybackState): void {
    const resolve = this.removalResolve;
    this.removalResolve = null;
    if (resolve !== null) {
      resolve(clonePlayback(state));
    }
  }

  clearQueue(): Promise<PlaybackState> {
    this.calls.push('clearQueue');
    this.state = emptyPlaybackState();
    return this.complete();
  }

  restoreSession(_session: PlayerSessionSnapshot): Promise<PlaybackState> {
    this.calls.push('restoreSession');
    return this.complete();
  }

  play(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('play');
    const index = params.index as number;
    if (index >= 0 && index < this.state.queue.length) {
      this.playIndex = index;
      this.state.queueIndex = index;
      this.state.track = cloneTrack(this.state.queue[index]);
      this.state.status = 'playing';
    }
    return this.complete();
  }

  pause(): Promise<PlaybackState> {
    this.calls.push('pause');
    this.state.status = 'paused';
    return this.complete();
  }

  seek(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('seek');
    this.seekPosition = params.position as number;
    this.state.position = this.seekPosition;
    return this.complete();
  }

  next(): Promise<PlaybackState> {
    this.calls.push('next');
    this.moveSelection(1);
    return this.complete();
  }

  previous(): Promise<PlaybackState> {
    this.calls.push('previous');
    this.moveSelection(-1);
    return this.complete();
  }

  skipPrevious(): Promise<PlaybackState> {
    this.calls.push('skipPrevious');
    this.moveSelection(-1);
    return this.complete();
  }

  setMode(params: Record<string, Object>): Promise<PlaybackState> {
    this.calls.push('setMode');
    this.requestedMode = params.mode as PlayerMode;
    this.state.mode = this.requestedMode;
    return this.complete();
  }

  setQuality(_params: Record<string, Object>): Promise<PlaybackState> {
    return this.complete();
  }

  snapshot(): PlaybackState {
    return clonePlayback(this.state);
  }

  private moveSelection(delta: number): void {
    if (this.state.queue.length === 0) {
      return;
    }
    const next = this.state.queueIndex + delta;
    this.state.queueIndex = (next + this.state.queue.length) % this.state.queue.length;
    this.state.track = cloneTrack(this.state.queue[this.state.queueIndex]);
  }

  private complete(): Promise<PlaybackState> {
    return Promise.resolve(clonePlayback(this.state));
  }
}

class MediaSmokeLyricsGateway implements LyricsGateway {
  result: LyricResult | null = null;
  failResolve: boolean = false;
  searchResults: LyricCandidate[] = [];
  chosenResult: LyricResult | null = null;
  readonly searchQueries: string[] = [];

  resolve(_params: Record<string, Object>): Promise<LyricResult | null> {
    if (this.failResolve) {
      return Promise.reject(new Error('fixture lyrics failure'));
    }
    return Promise.resolve(cloneLyricResult(this.result));
  }

  search(query: string): Promise<LyricCandidate[]> {
    this.searchQueries.push(query);
    return Promise.resolve(cloneCandidates(this.searchResults));
  }

  choose(_params: Record<string, Object>): Promise<LyricResult | null> {
    return Promise.resolve(cloneLyricResult(this.chosenResult));
  }
}

class MediaSmokeLyricsHarness {
  readonly player: PlayerStore;
  readonly gateway: MediaSmokeLyricsGateway;
  readonly panel: LyricsPanelState;

  constructor(gateway: MediaSmokeLyricsGateway) {
    const target = new MediaSmokePlayerTarget();
    target.state = mediaPlayback([mediaTrack('alpha')], 0, 'playing');
    this.player = new PlayerStore(new MediaSmokeScheduler());
    this.player.bind(target);
    this.player.onState(target.state);
    this.gateway = gateway;
    const lyricsStore = new LyricsStore(this.player, gateway);
    lyricsStore.attach();
    this.panel = new LyricsPanelState(lyricsStore, this.player);
    this.panel.attach();
  }
}

class MediaSmokePersistence implements LibraryPersistence {
  content: string | null;

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
    this.content = content;
  }

  preserveCorrupt(_path: string): void {
  }
}

function mediaTrack(label: string): MobileTrack {
  return {
    key: `track:${label}`,
    bvid: `BV${label}`,
    aid: 1,
    cid: 2,
    title: `Song ${label}`,
    artist: `Artist ${label}`,
    coverUrl: '',
    duration: 180,
    playCount: 0
  };
}

function mediaPlayback(queue: MobileTrack[], queueIndex: number, status: PlaybackStatus): PlaybackState {
  const state = emptyPlaybackState();
  state.queue = cloneTracks(queue);
  state.queueIndex = queueIndex;
  state.track = queueIndex >= 0 && queueIndex < queue.length ? cloneTrack(queue[queueIndex]) : null;
  state.duration = state.track === null ? 0 : state.track.duration;
  state.status = status;
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

function clonePlayback(state: PlaybackState): PlaybackState {
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
    result.error = state.error;
  }
  return result;
}

function mediaLyrics(times: number[], texts: string[]): LyricResult {
  const lines: LyricLine[] = texts.map((text: string, index: number): LyricLine => {
    return {
      time: times[index],
      text: text
    };
  });
  return {
    lines: lines,
    synced: true,
    trackName: 'Song alpha',
    artistName: 'Artist alpha',
    sourceId: 'fixture-source'
  };
}

function cloneLyricResult(result: LyricResult | null): LyricResult | null {
  if (result === null) {
    return null;
  }
  const lines: LyricLine[] = result.lines.map((line: LyricLine): LyricLine => {
    return {
      time: line.time,
      text: line.text
    };
  });
  return {
    lines: lines,
    synced: result.synced,
    trackName: result.trackName,
    artistName: result.artistName,
    sourceId: result.sourceId
  };
}

function mediaCandidate(id: string): LyricCandidate {
  return {
    id: id,
    trackName: `Candidate ${id}`,
    artistName: 'Candidate Artist',
    albumName: 'Candidate Album',
    duration: 240,
    image: ''
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
      image: candidate.image
    };
  });
}

function mediaPlaylist(id: string, name: string, tracks: MobileTrack[]): Playlist {
  return {
    id: id,
    name: name,
    tracks: cloneTracks(tracks),
    createdAt: 1,
    updatedAt: 2
  };
}

function mediaLibrary(playlists: Playlist[] = []): string {
  const snapshot: LibrarySnapshot = {
    version: STORAGE_VERSION,
    favorites: [],
    playlists: playlists,
    recent: [],
    positions: {},
    updatedAt: 1
  };
  return JSON.stringify(snapshot);
}

function assertStableSelectors(selectors: string[]): void {
  expect(selectors.length > 0).assertTrue();
  // 逐个 expect 会让 O(n²) 的重复检查额外分配大量 matcher；Set 保持同样语义且更省内存。
  const seen = new Set<string>();
  for (const selector of selectors) {
    expect(selector.length > 0).assertTrue();
    expect(seen.has(selector)).assertFalse();
    seen.add(selector);
  }
}

function assertContains(selectors: string[], expected: string[]): void {
  expected.forEach((value: string): void => {
    expect(selectors.indexOf(value) >= 0).assertTrue();
  });
}

function buildPlaylistDetail(tracks: MobileTrack[], playlistId: string): PlaylistDetailStore {
  const persistence = new MediaSmokePersistence(mediaLibrary([
    mediaPlaylist('fixture-playlist', 'Fixture Mix', tracks)
  ]));
  const model = new LibraryStoreModel(new LibraryStore('memory://media-detail', persistence));
  const player = new PlayerStore(new MediaSmokeScheduler());
  player.bind(new MediaSmokePlayerTarget());
  const store = new PlaylistDetailStore(model, player, playlistId);
  store.attach();
  return store;
}

export default function mediaUiSmokeContractTest(): void {
  describe('MediaUiSmokeContract', () => {
    it('registersUniqueMediaLibrarySelectorsAndDynamicIds', 0, () => {
      assertStableSelectors(NativeUiIds.all());
      assertStableSelectors(NativeUiIds.playerSelectors());
      assertStableSelectors(NativeUiIds.queueSelectors());
      assertStableSelectors(NativeUiIds.librarySelectors());
      assertStableSelectors(NativeUiIds.lyricsSelectors());

      assertContains(NativeUiIds.librarySelectors(), [
        NativeUiIds.mineQuickActions,
        NativeUiIds.mineQuickLiked,
        NativeUiIds.mineQuickHistory,
        NativeUiIds.mineQuickDownloads,
        NativeUiIds.mineQuickCreate,
        NativeUiIds.mineQuickLikedPlay,
        NativeUiIds.mineQuickHistoryPlay,
        NativeUiIds.mineQuickDownloadsPlay,
        NativeUiIds.downloadsPage,
        NativeUiIds.downloadsHeader,
        NativeUiIds.downloadsHeaderBack,
        NativeUiIds.downloadsEmpty,
        NativeUiIds.downloadsToolbar,
        NativeUiIds.downloadsSelect,
        NativeUiIds.downloadsSelectAll,
        NativeUiIds.downloadsExitSelect,
        NativeUiIds.downloadsBottomBar,
        NativeUiIds.downloadsRemoveSelected,
        NativeUiIds.downloadsList,
        NativeUiIds.recentHeader,
        NativeUiIds.recentHeaderBack,
        NativeUiIds.recentEmpty,
        NativeUiIds.recentToolbar,
        NativeUiIds.recentSelect,
        NativeUiIds.recentSelectAll,
        NativeUiIds.recentExitSelect,
        NativeUiIds.recentBottomBar,
        NativeUiIds.recentRemoveSelected,
        NativeUiIds.recentAddSelected,
        NativeUiIds.favoritesEmpty,
        NativeUiIds.favoritesPage,
        NativeUiIds.favoritesHeader,
        NativeUiIds.favoritesHeaderBack,
        NativeUiIds.favoritesHero,
        NativeUiIds.favoritesCover,
        NativeUiIds.favoritesToolbar,
        NativeUiIds.favoritesPlayAll,
        NativeUiIds.favoritesSelectToggle,
        NativeUiIds.favoritesSelectAll,
        NativeUiIds.favoritesExitSelect,
        NativeUiIds.favoritesBottomBar,
        NativeUiIds.favoritesDeleteSelected,
        NativeUiIds.favoritesAddSelected,
        NativeUiIds.playlistDetailHeaderBack,
        NativeUiIds.playlistDetailEdit,
        NativeUiIds.playlistDetailHero,
        NativeUiIds.playlistDetailCover,
        NativeUiIds.playlistDetailToolbar,
        NativeUiIds.playlistDetailToolbarPlayAll,
        NativeUiIds.playlistDetailSelectToggle,
        NativeUiIds.playlistDetailSelectAll,
        NativeUiIds.playlistDetailExitSelect,
        NativeUiIds.playlistDetailBottomBar,
        NativeUiIds.playlistDetailDeleteSelected,
        NativeUiIds.playlistDetailAddSelected,
        NativeUiIds.playlistDetailMissing,
        NativeUiIds.playlistEditSheet,
        NativeUiIds.playlistEditSave
      ]);
      assertContains(NativeUiIds.playerSelectors(), [
        NativeUiIds.miniPlayer,
        NativeUiIds.miniPlayerNext,
        NativeUiIds.playerPage,
        NativeUiIds.playerToggle,
        NativeUiIds.playerFavorite,
        NativeUiIds.playerTrackActions,
        NativeUiIds.playerPanelMode
      ]);
      assertContains(NativeUiIds.queueSelectors(), [
        NativeUiIds.queuePage,
        NativeUiIds.queueList,
        NativeUiIds.queueEmpty
      ]);
      assertContains(NativeUiIds.lyricsSelectors(), [
        NativeUiIds.lyricsSheet,
        NativeUiIds.lyricsSheetTitle,
        NativeUiIds.lyricsSheetArtist,
        NativeUiIds.lyricsSheetPlay,
        NativeUiIds.lyricsCollapse,
        NativeUiIds.lyricsPanel,
        NativeUiIds.lyricsSyncedList,
        NativeUiIds.lyricsUnsyncedList,
        NativeUiIds.lyricsCandidatesList
      ]);

      expect(NativeUiIds.queueRow(0)).assertEqual('queue-row-0');
      expect(NativeUiIds.queueRemove(2)).assertEqual('queue-remove-2');
      expect(NativeUiIds.recentRow(1)).assertEqual('recent-row-1');
      expect(NativeUiIds.recentMore(1)).assertEqual('recent-more-1');
      expect(NativeUiIds.recentFavorite(1)).assertEqual('recent-favorite-1');
      expect(NativeUiIds.favoriteRow(3)).assertEqual('favorite-row-3');
      expect(NativeUiIds.favoriteRemove(3)).assertEqual('favorite-remove-3');
      expect(NativeUiIds.favoriteMore(3)).assertEqual('favorite-more-3');
      expect(NativeUiIds.playlistRow(4)).assertEqual('playlist-row-4');
      expect(NativeUiIds.playlistRename(4)).assertEqual('playlist-rename-4');
      expect(NativeUiIds.playlistDelete(4)).assertEqual('playlist-delete-4');
      expect(NativeUiIds.playlistDetailRow(5)).assertEqual('playlist-detail-row-5');
      expect(NativeUiIds.playlistDetailRemove(5)).assertEqual('playlist-detail-remove-5');
      expect(NativeUiIds.playlistDetailAppend(5)).assertEqual('playlist-detail-append-5');
      expect(NativeUiIds.playlistDetailPlay(5)).assertEqual('playlist-detail-play-5');
      expect(NativeUiIds.playlistDetailFavorite(5)).assertEqual('playlist-detail-favorite-5');
      expect(NativeUiIds.playlistDetailMoreAction(5)).assertEqual('playlist-detail-more-action-5');
      expect(NativeUiIds.lyricsLine(6)).assertEqual('lyrics-line-6');
      expect(NativeUiIds.lyricsCandidate('candidate-7')).assertEqual('lyrics-candidate-candidate-7');
      expect(NativeUiIds.all().indexOf(NativeUiIds.queueRow(0)) < 0).assertTrue();
    });

    it('drivesPlayerTransportSeekAndModeFromFixtureQueue', 0, async () => {
      const queue = [mediaTrack('a'), mediaTrack('b'), mediaTrack('c')];
      const target = new MediaSmokePlayerTarget();
      target.state = mediaPlayback(queue, 0, 'playing');
      const store = new PlayerStore(new MediaSmokeScheduler());
      store.bind(target);
      store.onState(target.state);
      const page = new PlayerPageState(store);
      page.attach();

      await page.togglePlayback();
      expect(target.calls.indexOf('pause') >= 0).assertTrue();
      expect(page.status).assertEqual('paused');

      await page.next();
      expect(page.queueIndex).assertEqual(1);
      expect(page.track?.key).assertEqual('track:b');

      await page.previous();
      expect(page.queueIndex).assertEqual(0);

      await page.skipPrevious();
      expect(target.calls.indexOf('skipPrevious') >= 0).assertTrue();

      await page.submitSeek(90);
      expect(target.seekPosition).assertEqual(90);
      expect(page.position).assertEqual(90);

      await page.cycleMode();
      expect(target.requestedMode).assertEqual('repeat-all');
      expect(page.mode).assertEqual('repeat-all');
      page.dispose();
    });

    it('switchesQueueRowAndAppliesTheRemovalTransition', 0, async () => {
      const queue = [mediaTrack('a'), mediaTrack('b'), mediaTrack('c')];
      const target = new MediaSmokePlayerTarget();
      target.state = mediaPlayback(queue, 1, 'playing');
      const store = new PlayerStore(new MediaSmokeScheduler());
      store.bind(target);
      store.onState(target.state);
      const page = new QueuePageState(store);
      page.attach();

      await page.switchTo(2);
      expect(target.playIndex).assertEqual(2);
      expect(page.queueIndex).assertEqual(2);

      target.deferRemoval = true;
      const removal = page.removeAt(0);
      expect(page.busyAction).assertEqual('remove');
      expect(page.busyIndex).assertEqual(0);
      target.resolveRemoval(mediaPlayback([mediaTrack('b'), mediaTrack('c')], 1, 'playing'));
      await removal;

      expect(page.busyAction).assertEqual('');
      expect(page.queue.length).assertEqual(2);
      expect(page.queueIndex).assertEqual(1);
      page.dispose();
    });

    it('resolvesLyricsContentEmptyErrorAndCandidateSelection', 0, async () => {
      const readyGateway = new MediaSmokeLyricsGateway();
      readyGateway.result = mediaLyrics([0, 5, 10], ['one', 'two', 'three']);
      readyGateway.searchResults = [mediaCandidate('candidate-1')];
      readyGateway.chosenResult = mediaLyrics([1, 5, 10], ['selected one', 'selected two', 'selected three']);
      const harness = new MediaSmokeLyricsHarness(readyGateway);
      await wait(0);

      expect(harness.panel.status).assertEqual('ready');
      expect(harness.panel.lines.length).assertEqual(3);
      harness.player.onProgress(6, 180);
      expect(harness.panel.currentIndex).assertEqual(1);

      harness.panel.openCandidateSearch();
      await wait(0);
      expect(harness.panel.candidateStatus).assertEqual('ready');
      expect(harness.panel.candidates[0].id).assertEqual('candidate-1');
      await harness.panel.selectCandidate('candidate-1');
      await wait(0);
      expect(harness.panel.lines[0].text).assertEqual('selected one');
      harness.panel.dispose();

      const emptyHarness = new MediaSmokeLyricsHarness(new MediaSmokeLyricsGateway());
      await wait(0);
      expect(emptyHarness.panel.status).assertEqual('empty');
      emptyHarness.panel.dispose();

      const errorGateway = new MediaSmokeLyricsGateway();
      errorGateway.failResolve = true;
      const errorHarness = new MediaSmokeLyricsHarness(errorGateway);
      await wait(0);
      expect(errorHarness.panel.status).assertEqual('error');
      errorHarness.panel.dispose();
    });

    it('exposesEmptyLibraryStatesFromFreshMemoryStores', 0, () => {
      const persistence = new MediaSmokePersistence(mediaLibrary());
      const model = new LibraryStoreModel(new LibraryStore('memory://media-library', persistence));
      const player = new PlayerStore(new MediaSmokeScheduler());
      player.bind(new MediaSmokePlayerTarget());
      const favorites = new FavoritesStore(player, model);
      favorites.attach();
      const recent = new RecentPlaybackStore(player, model);
      recent.attach();
      const playlists = new PlaylistStore(model, player);
      playlists.attach();

      expect(favorites.tracks.length).assertEqual(0);
      expect(recent.tracks.length).assertEqual(0);
      expect(playlists.playlists.length).assertEqual(0);
      assertContains(NativeUiIds.librarySelectors(), [
        NativeUiIds.favoritesEmpty,
        NativeUiIds.favoritesEmptySearch,
        NativeUiIds.recentEmpty
      ]);
      favorites.dispose();
      void recent.dispose();
      playlists.dispose();
    });

    it('exposesPlaylistDetailPopulatedEmptyAndMissingStates', 0, () => {
      const populated = buildPlaylistDetail([mediaTrack('one'), mediaTrack('two')], 'fixture-playlist');
      expect(populated.missing).assertFalse();
      expect(populated.playlistName).assertEqual('Fixture Mix');
      expect(populated.tracks.length).assertEqual(2);
      populated.selectAll();
      expect(populated.selectedKeys.length).assertEqual(2);
      populated.dispose();

      const empty = buildPlaylistDetail([], 'fixture-playlist');
      expect(empty.missing).assertFalse();
      expect(empty.tracks.length).assertEqual(0);
      empty.dispose();

      const missing = buildPlaylistDetail([], 'missing-playlist');
      expect(missing.missing).assertTrue();
      expect(missing.tracks.length).assertEqual(0);
      missing.dispose();
    });
  });
}
