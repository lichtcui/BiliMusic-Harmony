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
import { PlayerStore } from './PlayerStore';

export const PLAYLIST_NAME_MAX_LENGTH: number = 60;
/** 与 `LibraryStore` 的 `MAX_PLAYLIST_DESCRIPTION` 保持一致。 */
export const PLAYLIST_DESCRIPTION_MAX_LENGTH: number = 200;

export enum PlaylistActionResult {
  Success = 0,
  InvalidName = 1,
  Busy = 2,
  NotFound = 3,
  Failed = 4
}

export interface PlaylistSummary {
  id: string;
  name: string;
  trackCount: number;
  /**
   * 歌单封面。优先使用用户上传的自定义封面（本地 `file://` URI）；
   * 没有自定义封面时派生自首曲封面，空歌单或首曲无封面时为空串，由列表渲染占位块。
   */
  coverUrl: string;
  /** 用户上传的自定义封面（仅 `file://`）；没有时为空串。「修改歌单信息」用它回填。 */
  coverUri: string;
  /** 歌单简介；空串表示未填写。 */
  description: string;
  /** 曲目 key 顺序快照。页面用它和播放器队列做「当前播放的就是这个歌单」的判定。 */
  trackKeys: string[];
  updatedAt: number;
}

@Observed
export class PlaylistStore implements LibraryStoreModelListener {
  @Track playlists: PlaylistSummary[];
  @Track selectedPlaylistId: string;
  @Track creating: boolean = false;
  @Track renamingPlaylistId: string = '';
  @Track updatingPlaylistId: string = '';
  @Track deletingPlaylistId: string = '';
  @Track error: AppError | null;

  private readonly libraryModel: LibraryStoreModel;
  private readonly playerStore: PlayerStore;
  private disposed: boolean = false;

  constructor(libraryModel: LibraryStoreModel, playerStore: PlayerStore) {
    this.libraryModel = libraryModel;
    this.playerStore = playerStore;
    this.playlists = summarizePlaylists(libraryModel.playlistList());
    this.selectedPlaylistId = '';
    this.error = cloneError(libraryModel.error);
  }

  /**
   * Subscribes this store to the library model.
   *
   * Must be called after construction and through the observed instance: @Observed wraps the object
   * only after the constructor returns, so subscribing `this` inside the constructor hands the model
   * the raw target. Model callbacks would then write through the raw object and bypass the proxy,
   * leaving @ObjectLink pages stale (a new playlist is written to disk but the list never refreshes).
   * Call attach() once the instance is stored in page state.
   */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.libraryModel.subscribe(this);
  }

  isBusy(): boolean {
    return this.creating || this.renamingPlaylistId.length > 0 ||
      this.updatingPlaylistId.length > 0 || this.deletingPlaylistId.length > 0;
  }

  playlistById(playlistId: string): PlaylistSummary | null {
    const index = this.playlistIndex(playlistId);
    if (index < 0) {
      return null;
    }
    return cloneSummary(this.playlists[index]);
  }

  selectPlaylist(playlistId: string): boolean {
    const index = this.playlistIndex(playlistId);
    if (index < 0) {
      return false;
    }
    this.selectedPlaylistId = this.playlists[index].id;
    return true;
  }

  clearSelectedPlaylist(playlistId: string = ''): void {
    if (playlistId.length === 0 || this.selectedPlaylistId === cleanPlaylistId(playlistId)) {
      this.selectedPlaylistId = '';
    }
  }

  /**
   * 「我的 · 歌单」行尾播放键：把该歌单的曲目整队交给播放器，从第一首开始。
   *
   * 曲目列表每次从资料库模型重新读取（`playlistById` 返回副本），所以重命名、
   * 删除、曲目变动之后不存在行摘要与真实队列不一致的问题。空歌单或找不到歌单
   * 时不打扰播放器，返回 false；播放失败由 PlayerStore 自己的错误状态承担。
   */
  async playAll(playlistId: string): Promise<boolean> {
    if (this.disposed) {
      return false;
    }
    const playlist = this.libraryModel.playlistById(cleanPlaylistId(playlistId));
    if (playlist === null || playlist.tracks.length === 0) {
      return false;
    }
    try {
      await this.playerStore.loadQueue(playlist.tracks, 0, true);
      return true;
    } catch (_error) {
      // Playback failures stay owned by PlayerStore; the playlist list is unchanged.
      return false;
    }
  }

  async create(name: string, coverUri: string = '', description: string = ''): Promise<PlaylistActionResult> {
    if (this.disposed) {
      return PlaylistActionResult.Failed;
    }
    if (this.isBusy()) {
      return PlaylistActionResult.Busy;
    }
    const cleanName = cleanPlaylistName(name);
    if (!isValidPlaylistName(cleanName)) {
      return PlaylistActionResult.InvalidName;
    }
    this.creating = true;
    this.error = null;
    try {
      const result = await this.libraryModel.createPlaylist(cleanName, coverUri, description);
      return result.playlist === null ? PlaylistActionResult.Failed : PlaylistActionResult.Success;
    } catch (_error) {
      this.syncError();
      return PlaylistActionResult.Failed;
    } finally {
      this.creating = false;
    }
  }

  async rename(playlistId: string, name: string): Promise<PlaylistActionResult> {
    if (this.disposed) {
      return PlaylistActionResult.Failed;
    }
    if (this.isBusy()) {
      return PlaylistActionResult.Busy;
    }
    const id = cleanPlaylistId(playlistId);
    if (this.playlistIndex(id) < 0) {
      return PlaylistActionResult.NotFound;
    }
    const cleanName = cleanPlaylistName(name);
    if (!isValidPlaylistName(cleanName)) {
      return PlaylistActionResult.InvalidName;
    }
    this.renamingPlaylistId = id;
    this.error = null;
    try {
      await this.libraryModel.renamePlaylist(id, cleanName);
      return PlaylistActionResult.Success;
    } catch (_error) {
      this.syncError();
      return PlaylistActionResult.Failed;
    } finally {
      this.renamingPlaylistId = '';
    }
  }

  /**
   * 「修改歌单信息」：名称 / 简介 / 自定义封面一次提交。
   * 与创建、重命名共用同一条校验和忙状态：空名或超长名不写入，写盘失败保留原行。
   */
  async update(playlistId: string, name: string, coverUri: string = '',
    description: string = ''): Promise<PlaylistActionResult> {
    if (this.disposed) {
      return PlaylistActionResult.Failed;
    }
    if (this.isBusy()) {
      return PlaylistActionResult.Busy;
    }
    const id = cleanPlaylistId(playlistId);
    if (this.playlistIndex(id) < 0) {
      return PlaylistActionResult.NotFound;
    }
    const cleanName = cleanPlaylistName(name);
    if (!isValidPlaylistName(cleanName)) {
      return PlaylistActionResult.InvalidName;
    }
    this.updatingPlaylistId = id;
    this.error = null;
    try {
      await this.libraryModel.updatePlaylist(id, cleanName, coverUri, description);
      return PlaylistActionResult.Success;
    } catch (_error) {
      this.syncError();
      return PlaylistActionResult.Failed;
    } finally {
      this.updatingPlaylistId = '';
    }
  }

  async delete(playlistId: string): Promise<PlaylistActionResult> {
    if (this.disposed) {
      return PlaylistActionResult.Failed;
    }
    if (this.isBusy()) {
      return PlaylistActionResult.Busy;
    }
    const id = cleanPlaylistId(playlistId);
    if (this.playlistIndex(id) < 0) {
      return PlaylistActionResult.NotFound;
    }
    this.deletingPlaylistId = id;
    this.error = null;
    try {
      await this.libraryModel.deletePlaylist(id);
      if (this.selectedPlaylistId === id) {
        this.selectedPlaylistId = '';
      }
      return PlaylistActionResult.Success;
    } catch (_error) {
      this.syncError();
      return PlaylistActionResult.Failed;
    } finally {
      this.deletingPlaylistId = '';
    }
  }

  clearError(): void {
    this.libraryModel.clearError();
    this.error = null;
  }

  onLibraryChanged(snapshot: LibrarySnapshot): void {
    if (this.disposed) {
      return;
    }
    this.playlists = summarizePlaylists(snapshot.playlists);
    if (this.selectedPlaylistId.length > 0 && this.playlistIndex(this.selectedPlaylistId) < 0) {
      this.selectedPlaylistId = '';
    }
    this.error = null;
  }

  onLibraryError(error: AppError): void {
    if (!this.disposed) {
      this.error = cloneError(error);
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.libraryModel.unsubscribe(this);
  }

  private playlistIndex(playlistId: string): number {
    const id = cleanPlaylistId(playlistId);
    if (id.length === 0) {
      return -1;
    }
    for (let index = 0; index < this.playlists.length; index++) {
      if (this.playlists[index].id === id) {
        return index;
      }
    }
    return -1;
  }

  private syncError(): void {
    if (this.libraryModel.error !== null) {
      this.error = cloneError(this.libraryModel.error);
    }
  }
}

function cleanPlaylistName(value: string): string {
  return value.trim();
}

function isValidPlaylistName(value: string): boolean {
  return value.length > 0 && value.length <= PLAYLIST_NAME_MAX_LENGTH;
}

function cleanPlaylistId(value: string): string {
  return value.trim().slice(0, 80);
}

function summarizePlaylists(playlists: Playlist[]): PlaylistSummary[] {
  const summaries: PlaylistSummary[] = [];
  for (const playlist of playlists) {
    summaries.push({
      id: playlist.id,
      name: playlist.name,
      trackCount: playlist.tracks.length,
      coverUrl: playlistCoverUrl(playlist),
      coverUri: playlist.coverUri === undefined ? '' : playlist.coverUri.trim(),
      description: playlist.description === undefined ? '' : playlist.description.trim(),
      trackKeys: playlist.tracks.map((track: MobileTrack): string => track.key),
      updatedAt: playlist.updatedAt
    });
  }
  return summaries;
}

/** 自定义封面优先；没有自定义封面时回落到首曲封面。 */
function playlistCoverUrl(playlist: Playlist): string {
  const custom = playlist.coverUri === undefined ? '' : playlist.coverUri.trim();
  if (custom.length > 0) {
    return custom;
  }
  return firstTrackCoverUrl(playlist);
}

/** 首曲封面；歌单为空或首曲没有封面时返回空串（渲染层用占位块）。 */
function firstTrackCoverUrl(playlist: Playlist): string {
  if (playlist.tracks.length === 0) {
    return '';
  }
  return playlist.tracks[0].coverUrl.trim();
}

function cloneSummary(summary: PlaylistSummary): PlaylistSummary {
  return {
    id: summary.id,
    name: summary.name,
    trackCount: summary.trackCount,
    coverUrl: summary.coverUrl,
    coverUri: summary.coverUri,
    description: summary.description,
    trackKeys: summary.trackKeys.slice(),
    updatedAt: summary.updatedAt
  };
}

function cloneError(error: AppError | null): AppError | null {
  if (error === null) {
    return null;
  }
  return {
    code: error.code,
    message: error.message,
    retryable: error.retryable
  };
}
