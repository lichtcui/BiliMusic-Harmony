import {
  AppError,
  LibrarySnapshot,
  MobileTrack,
  Playlist
} from '../types/MobileTypes';
import {
  LibraryStoreModel,
  LibraryStoreModelListener
} from './LibraryStoreModel';

export const TRACK_ACTION_PLAYLIST_NAME_MAX_LENGTH: number = 60;

export enum TrackActionBusyState {
  None = 0,
  Favorite = 1,
  AddToPlaylist = 2,
  CreateAndAdd = 3,
  FavoriteBatch = 4
}

export enum TrackActionOutcome {
  Success = 0,
  Busy = 1,
  Duplicate = 2,
  PlaylistNotFound = 3,
  InvalidName = 4,
  Failed = 5
}

export enum TrackActionFeedback {
  None = 0,
  FavoriteAdded = 1,
  FavoriteRemoved = 2,
  PlaylistCreated = 3,
  Duplicate = 4,
  PlaylistNotFound = 5,
  InvalidName = 6,
  WriteFailed = 7,
  Capacity = 8,
  Busy = 9,
  Failed = 10,
  FavoriteBatchAdded = 11
}

export interface TrackPlaylistOption {
  id: string;
  name: string;
  trackCount: number;
  containsTrack: boolean;
  /** 列表封面：自定义封面优先，否则首曲封面；空歌单为空串（由界面回落为首字块）。 */
  coverUrl: string;
}

@Observed
export class TrackActionStore implements LibraryStoreModelListener {
  @Track selectedTrack: MobileTrack | null = null;
  @Track selectedTracks: MobileTrack[] = [];
  @Track batchMode: boolean = false;
  @Track contextTitle: string = '';
  @Track suggestedPlaylistName: string = '';
  @Track feedbackCount: number = 0;
  @Track isFavorite: boolean = false;
  /** 多选里尚未收藏的曲目数；批量「加入我喜欢的」只写这些，全部已收藏时该动作为空。 */
  @Track favoriteCandidateCount: number = 0;
  @Track playlists: TrackPlaylistOption[] = [];
  @Track busyAction: TrackActionBusyState = TrackActionBusyState.None;
  @Track busyPlaylistId: string = '';
  @Track feedback: TrackActionFeedback = TrackActionFeedback.None;

  private readonly libraryModel: LibraryStoreModel;
  private sessionGeneration: number = 0;
  @Track private inFlightActions: number = 0;
  private disposed: boolean = false;

  constructor(libraryModel: LibraryStoreModel) {
    this.libraryModel = libraryModel;
  }

  /**
   * Subscribes this store to the library model.
   *
   * Must be called after construction and through the observed instance: @Observed wraps the object
   * only after the constructor returns, so subscribing `this` inside the constructor hands the model
   * the raw target. Model callbacks would then write through the raw object and bypass the proxy,
   * leaving @ObjectLink pages stale. Call attach() once the instance is stored in page
   * state.
   */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.libraryModel.subscribe(this);
  }

  isOpen(): boolean {
    return this.selectedTracks.length > 0;
  }

  isBusy(): boolean {
    return this.inFlightActions > 0;
  }

  /** 批量模式即使只有一首也按多曲处理：隐藏收藏动作，按批量加歌单。 */
  isMulti(): boolean {
    return this.batchMode || this.selectedTracks.length > 1;
  }

  open(track: MobileTrack): boolean {
    if (this.disposed || track.key.trim().length === 0) {
      return false;
    }
    const cloned = cloneTrack(track);
    this.sessionGeneration += 1;
    this.selectedTrack = cloned;
    this.selectedTracks = [cloned];
    this.batchMode = false;
    this.contextTitle = '';
    this.suggestedPlaylistName = '';
    this.feedbackCount = 0;
    this.busyAction = TrackActionBusyState.None;
    this.busyPlaylistId = '';
    this.feedback = TrackActionFeedback.None;
    this.refreshFromLibrary();
    return true;
  }

  openMany(tracks: MobileTrack[], contextTitle: string = '',
    suggestedPlaylistName: string = ''): boolean {
    if (this.disposed) {
      return false;
    }
    const cloned: MobileTrack[] = [];
    const seen: Set<string> = new Set<string>();
    for (const track of tracks) {
      if (track.key.trim().length === 0 || seen.has(track.key)) {
        continue;
      }
      seen.add(track.key);
      cloned.push(cloneTrack(track));
    }
    if (cloned.length === 0) {
      return false;
    }
    this.sessionGeneration += 1;
    this.selectedTrack = null;
    this.selectedTracks = cloned;
    this.batchMode = true;
    this.contextTitle = contextTitle.trim().slice(0, 120);
    this.suggestedPlaylistName = suggestedPlaylistName.trim().slice(0, TRACK_ACTION_PLAYLIST_NAME_MAX_LENGTH);
    this.feedbackCount = 0;
    this.busyAction = TrackActionBusyState.None;
    this.busyPlaylistId = '';
    this.feedback = TrackActionFeedback.None;
    this.refreshFromLibrary();
    return true;
  }

  close(): void {
    if (this.disposed && this.selectedTracks.length === 0) {
      return;
    }
    this.sessionGeneration += 1;
    this.selectedTrack = null;
    this.selectedTracks = [];
    this.batchMode = false;
    this.contextTitle = '';
    this.suggestedPlaylistName = '';
    this.feedbackCount = 0;
    this.isFavorite = false;
    this.favoriteCandidateCount = 0;
    this.playlists = [];
    this.busyAction = TrackActionBusyState.None;
    this.busyPlaylistId = '';
    this.feedback = TrackActionFeedback.None;
  }

  async toggleFavorite(): Promise<TrackActionOutcome> {
    const track = this.selectedTrack;
    if (track === null || this.isMulti()) {
      return TrackActionOutcome.Failed;
    }
    const generation = this.beginAction(TrackActionBusyState.Favorite);
    if (generation < 0) {
      return TrackActionOutcome.Busy;
    }
    try {
      await this.libraryModel.toggleFavorite(track);
      this.refreshFromLibrary();
      this.showFeedback(generation, this.isFavorite ?
        TrackActionFeedback.FavoriteAdded : TrackActionFeedback.FavoriteRemoved);
      return TrackActionOutcome.Success;
    } catch (_error) {
      const feedback = this.failureFeedback();
      this.showFeedback(generation, feedback);
      return TrackActionOutcome.Failed;
    } finally {
      this.endAction(generation);
    }
  }

  /**
   * 批量「加入我喜欢的」：只补写尚未收藏的曲目，已收藏的保持不动。
   * 逐条走 `toggleFavorite` 与 `FavoritesStore.addMany` 的做法一致，避免在资料库模型里
   * 另开一套批量写入路径。
   */
  async addSelectedToFavorites(): Promise<TrackActionOutcome> {
    if (!this.isMulti() || this.selectedTracks.length === 0) {
      return TrackActionOutcome.Failed;
    }
    const candidates: MobileTrack[] = [];
    for (const track of this.selectedTracks) {
      if (!this.libraryModel.isFavorite(track.key)) {
        candidates.push(track);
      }
    }
    if (candidates.length === 0) {
      return TrackActionOutcome.Success;
    }
    const generation = this.beginAction(TrackActionBusyState.FavoriteBatch);
    if (generation < 0) {
      return TrackActionOutcome.Busy;
    }
    try {
      let added = 0;
      for (const track of candidates) {
        // 抽屉会在点击后立即收起，宿主随后会 close() 并推进 generation；
        // 批量写入已经由用户确认，不能因为抽屉关闭而中断，只在中止启动时才停。
        if (this.disposed) {
          break;
        }
        await this.libraryModel.toggleFavorite(track);
        added += 1;
      }
      this.refreshFromLibrary();
      this.showFeedback(generation, TrackActionFeedback.FavoriteBatchAdded, added);
      return TrackActionOutcome.Success;
    } catch (_error) {
      const feedback = this.failureFeedback();
      this.showFeedback(generation, feedback);
      return TrackActionOutcome.Failed;
    } finally {
      this.endAction(generation);
    }
  }

  async addToPlaylist(playlistId: string): Promise<TrackActionOutcome> {
    const tracks = this.selectedTracks;
    if (tracks.length === 0) {
      return TrackActionOutcome.Failed;
    }
    const option = this.playlistOption(playlistId);
    if (option === null) {
      this.feedback = TrackActionFeedback.PlaylistNotFound;
      return TrackActionOutcome.PlaylistNotFound;
    }
    if (option.containsTrack) {
      this.feedback = TrackActionFeedback.Duplicate;
      return TrackActionOutcome.Duplicate;
    }
    const generation = this.beginAction(TrackActionBusyState.AddToPlaylist);
    if (generation < 0) {
      return TrackActionOutcome.Busy;
    }
    this.busyPlaylistId = option.id;
    try {
      const result = await this.libraryModel.addTracksToPlaylist(option.id, tracks);
      this.refreshFromLibrary();
      if (!result.changed) {
        this.showFeedback(generation, TrackActionFeedback.Duplicate);
        return TrackActionOutcome.Duplicate;
      }
      // 成功结果由宿主在抽屉收起后弹出底部 toast；这里不再写成功 feedback，
      // 错误反馈仍走下面的 failureFeedback 分支。
      return TrackActionOutcome.Success;
    } catch (_error) {
      const feedback = this.failureFeedback();
      this.showFeedback(generation, feedback);
      return feedback === TrackActionFeedback.PlaylistNotFound ?
        TrackActionOutcome.PlaylistNotFound : TrackActionOutcome.Failed;
    } finally {
      this.endAction(generation);
    }
  }

  async createPlaylistAndAdd(name: string): Promise<TrackActionOutcome> {
    const tracks = this.selectedTracks;
    if (tracks.length === 0) {
      return TrackActionOutcome.Failed;
    }
    const cleanName = name.trim();
    if (cleanName.length === 0 || cleanName.length > TRACK_ACTION_PLAYLIST_NAME_MAX_LENGTH) {
      this.feedback = TrackActionFeedback.InvalidName;
      return TrackActionOutcome.InvalidName;
    }
    const generation = this.beginAction(TrackActionBusyState.CreateAndAdd);
    if (generation < 0) {
      return TrackActionOutcome.Busy;
    }
    try {
      const created = await this.libraryModel.createPlaylistWithTracks(cleanName, tracks);
      const playlist = created.playlist;
      if (playlist === null) {
        this.showFeedback(generation, TrackActionFeedback.Failed);
        return TrackActionOutcome.Failed;
      }
      this.refreshFromLibrary();
      this.showFeedback(generation, TrackActionFeedback.PlaylistCreated, playlist.tracks.length);
      return TrackActionOutcome.Success;
    } catch (_error) {
      const feedback = this.failureFeedback();
      this.showFeedback(generation, feedback);
      return feedback === TrackActionFeedback.PlaylistNotFound ?
        TrackActionOutcome.PlaylistNotFound : TrackActionOutcome.Failed;
    } finally {
      this.endAction(generation);
    }
  }

  onLibraryChanged(_snapshot: LibrarySnapshot): void {
    if (!this.disposed) {
      this.refreshFromLibrary();
    }
  }

  onLibraryError(_error: AppError): void {
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.close();
    this.disposed = true;
    this.libraryModel.unsubscribe(this);
  }

  private beginAction(action: TrackActionBusyState): number {
    if (this.disposed || this.selectedTracks.length === 0) {
      return -1;
    }
    if (this.inFlightActions > 0) {
      this.feedback = TrackActionFeedback.Busy;
      return -1;
    }
    this.inFlightActions += 1;
    this.busyAction = action;
    this.feedback = TrackActionFeedback.None;
    this.libraryModel.clearError();
    return this.sessionGeneration;
  }

  private endAction(generation: number): void {
    if (this.inFlightActions > 0) {
      this.inFlightActions -= 1;
    }
    if (generation === this.sessionGeneration) {
      this.busyAction = TrackActionBusyState.None;
      this.busyPlaylistId = '';
    }
  }

  private showFeedback(generation: number, feedback: TrackActionFeedback, count: number = 0): void {
    if (!this.disposed && generation === this.sessionGeneration && this.selectedTracks.length > 0) {
      this.feedback = feedback;
      this.feedbackCount = Math.max(0, Math.floor(count));
    }
  }

  private refreshFromLibrary(): void {
    if (this.selectedTracks.length === 0) {
      this.isFavorite = false;
      this.favoriteCandidateCount = 0;
      this.playlists = [];
      return;
    }
    const single = !this.isMulti() && this.selectedTracks.length === 1 ?
      this.selectedTracks[0] : null;
    this.isFavorite = single !== null && this.libraryModel.isFavorite(single.key);
    let candidates = 0;
    for (const track of this.selectedTracks) {
      if (!this.libraryModel.isFavorite(track.key)) {
        candidates += 1;
      }
    }
    this.favoriteCandidateCount = candidates;
    const targetKeys: Set<string> = new Set<string>();
    for (const track of this.selectedTracks) {
      targetKeys.add(track.key);
    }
    const playlists = this.libraryModel.playlistList();
    const options: TrackPlaylistOption[] = [];
    for (const playlist of playlists) {
      options.push(playlistOption(playlist, targetKeys));
    }
    this.playlists = options;
  }

  private playlistOption(playlistId: string): TrackPlaylistOption | null {
    const id = playlistId.trim().slice(0, 80);
    for (const option of this.playlists) {
      if (option.id === id) {
        return option;
      }
    }
    return null;
  }

  private failureFeedback(): TrackActionFeedback {
    const error = this.libraryModel.error;
    if (error === null) {
      return TrackActionFeedback.Failed;
    }
    if (error.code === 'library.playlistNotFound') {
      return TrackActionFeedback.PlaylistNotFound;
    }
    if (error.code === 'library.writeFailed') {
      return TrackActionFeedback.WriteFailed;
    }
    if (error.code === 'library.playlistLimit' || error.code === 'library.playlistFull') {
      return TrackActionFeedback.Capacity;
    }
    return TrackActionFeedback.Failed;
  }
}

function playlistOption(playlist: Playlist, targetKeys: Set<string>): TrackPlaylistOption {
  const playlistKeys: Set<string> = new Set<string>();
  for (const track of playlist.tracks) {
    playlistKeys.add(track.key);
  }
  let containsTrack = true;
  for (const key of targetKeys) {
    if (!playlistKeys.has(key)) {
      containsTrack = false;
      break;
    }
  }
  return {
    id: playlist.id,
    name: playlist.name,
    trackCount: playlist.tracks.length,
    containsTrack: containsTrack,
    coverUrl: playlistCoverUrl(playlist)
  };
}

/** 自定义封面优先；没有自定义封面时回落到首曲封面，空歌单返回空串。 */
function playlistCoverUrl(playlist: Playlist): string {
  const custom = playlist.coverUri === undefined ? '' : playlist.coverUri.trim();
  if (custom.length > 0) {
    return custom;
  }
  if (playlist.tracks.length === 0) {
    return '';
  }
  return playlist.tracks[0].coverUrl.trim();
}

function cloneTrack(track: MobileTrack): MobileTrack {
  const copy: MobileTrack = {
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
  if (track.collectionSize !== undefined) {
    copy.collectionSize = track.collectionSize;
  }
  if (track.collectionTotalDuration !== undefined) {
    copy.collectionTotalDuration = track.collectionTotalDuration;
  }
  return copy;
}
