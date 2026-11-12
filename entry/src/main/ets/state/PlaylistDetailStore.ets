import {
  AppError,
  LibrarySnapshot,
  MobileTrack,
  PlaybackStatus,
  Playlist
} from '../types/MobileTypes';
import { toKeySet, trackKeySet } from './KeySets';
import {
  LibraryStoreModel,
  LibraryStoreModelListener
} from './LibraryStoreModel';
import {
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
} from './PlayerStore';

@Observed
export class PlaylistDetailStore implements PlayerStoreListener, LibraryStoreModelListener {
  @Track playlistName: string = '';
  @Track tracks: MobileTrack[] = [];
  /**
   * Hero 大图的封面。优先使用用户上传的自定义封面（本地 `file://` URI），
   * 与 `PlaylistStore` 的歌单行保持一致；没有自定义封面时取第一首带封面的曲目，
   * 都没有时为空串，由页面回落到 accent-soft 色块 + 首数。
   */
  @Track coverUrl: string = '';
  /** 歌单简介；空串时不显示。 */
  @Track description: string = '';
  /** 全部曲目时长之和（秒）；未知时长按 0 计，页面据此决定是否显示「约 x 小时 y 分」。 */
  @Track totalDuration: number = 0;
  @Track selectedKeys: string[] = [];
  @Track pendingRemoveKey: string = '';
  @Track batchBusy: boolean = false;
  @Track missing: boolean = false;
  @Track error: AppError | null = null;
  @Track currentKey: string = '';
  /** 播放器状态；Hero 播放键据此在「播放全部 / 暂停」之间切换。 */
  @Track playbackStatus: PlaybackStatus = 'idle';
  /** 渲染路径的 O(1) 索引；与 `tracks / selectedKeys` 同源，整份替换。 */
  @Track private playlistKeySet: Set<string> = new Set<string>();
  @Track private selectedKeySet: Set<string> = new Set<string>();

  private readonly libraryModel: LibraryStoreModel;
  private readonly playerStore: PlayerStore;
  private readonly playlistId: string;
  private disposed: boolean = false;

  constructor(libraryModel: LibraryStoreModel, playerStore: PlayerStore, playlistId: string) {
    this.libraryModel = libraryModel;
    this.playerStore = playerStore;
    this.playlistId = cleanPlaylistId(playlistId);
    this.currentKey = playerStore.snapshot.track === null ? '' : playerStore.snapshot.track.key;
    this.playbackStatus = playerStore.snapshot.status;
    this.error = cloneError(libraryModel.error);
    this.refreshFromLibrary();
  }

  /**
   * Subscribes this store to the player and library stores.
   *
   * Must be called after construction and through the observed instance: @Observed wraps the object
   * only after the constructor returns, so subscribing `this` inside the constructor hands the stores
   * the raw target. Their callbacks would then write through the raw object and bypass the proxy,
   * leaving @ObjectLink pages stale. Call attach() once the instance is stored in page
   * state.
   */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.playerStore.subscribe(this);
    this.libraryModel.subscribe(this);
  }

  isBusy(): boolean {
    return this.batchBusy || this.pendingRemoveKey.length > 0;
  }

  isSelected(trackKey: string): boolean {
    return this.selectedKeySet.has(cleanTrackKey(trackKey));
  }

  isPending(trackKey: string): boolean {
    return this.pendingRemoveKey.length > 0 && this.pendingRemoveKey === cleanTrackKey(trackKey);
  }

  /** 当前曲目是否属于本歌单；属于时 Hero 播放键才表现为本歌单的播放 / 暂停。 */
  isCurrentTrackInPlaylist(): boolean {
    return this.currentKey.length > 0 && this.playlistKeySet.has(this.currentKey);
  }

  /** 正在播放且当前曲目属于本歌单：Hero 显示暂停键。 */
  isPlayingThisPlaylist(): boolean {
    return this.playbackStatus === 'playing' && this.isCurrentTrackInPlaylist();
  }

  /**
   * Hero 播放键的统一动作：
   * - 本歌单正在播放 → 暂停；
   * - 本歌单的当前曲目处于暂停 → 续播（不回到第一首）；
   * - 其余情况（包括正在播别的歌单）→ 从本歌单第一首开始播放。
   */
  async togglePlayback(): Promise<void> {
    if (this.disposed || this.tracks.length === 0) {
      return;
    }
    if (this.isPlayingThisPlaylist()) {
      try {
        await this.playerStore.pause();
      } catch (_error) {
        // Playback failures remain owned by PlayerStore.
      }
      return;
    }
    if (this.playbackStatus === 'paused' && this.isCurrentTrackInPlaylist()) {
      try {
        await this.playerStore.play();
      } catch (_error) {
        // Playback failures remain owned by PlayerStore.
      }
      return;
    }
    await this.playAll();
  }

  async playAll(): Promise<void> {
    const playlist = this.latestPlaylist();
    if (playlist === null || playlist.tracks.length === 0) {
      return;
    }
    try {
      await this.playerStore.loadQueue(cloneTracks(playlist.tracks), 0, true);
    } catch (_error) {
      // Playback failures remain owned by PlayerStore.
    }
  }

  /** 播放指定曲目；返回是否真正开始装载队列，供页面决定是否跳转播放页。 */
  async playTrack(trackKey: string): Promise<boolean> {
    const playlist = this.latestPlaylist();
    if (playlist === null) {
      return false;
    }
    const index = findTrackIndex(playlist.tracks, trackKey);
    if (index < 0) {
      return false;
    }
    try {
      await this.playerStore.loadQueue(cloneTracks(playlist.tracks), index, true);
      return true;
    } catch (_error) {
      // Playback failures remain owned by PlayerStore.
      return false;
    }
  }

  async appendTrack(trackKey: string): Promise<boolean> {
    const playlist = this.latestPlaylist();
    if (playlist === null) {
      return false;
    }
    const index = findTrackIndex(playlist.tracks, trackKey);
    if (index < 0) {
      return false;
    }
    try {
      await this.playerStore.appendToQueue([cloneTrack(playlist.tracks[index])]);
      return true;
    } catch (_error) {
      return false;
    }
  }

  async removeTrack(trackKey: string): Promise<boolean> {
    const key = cleanTrackKey(trackKey);
    if (this.disposed || this.missing || key.length === 0 || this.isBusy()) {
      return false;
    }
    const playlist = this.latestPlaylist();
    if (playlist === null || findTrackIndex(playlist.tracks, key) < 0) {
      return false;
    }
    this.pendingRemoveKey = key;
    this.error = null;
    try {
      await this.libraryModel.removeFromPlaylist(this.playlistId, key);
      return true;
    } catch (_error) {
      this.syncLibraryError();
      return false;
    } finally {
      this.pendingRemoveKey = '';
    }
  }

  toggleSelection(trackKey: string): boolean {
    const key = cleanTrackKey(trackKey);
    if (this.disposed || this.missing || key.length === 0 || !this.playlistKeySet.has(key)) {
      return false;
    }
    if (this.selectedKeySet.has(key)) {
      this.setSelectedKeys(this.selectedKeys.filter((item: string): boolean => item !== key));
    } else {
      this.setSelectedKeys([...this.selectedKeys, key]);
    }
    return true;
  }

  selectAll(): void {
    if (this.disposed || this.missing || this.tracks.length === 0) {
      return;
    }
    const keys: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (const track of this.tracks) {
      const key = cleanTrackKey(track.key);
      if (key.length > 0 && !seen.has(key)) {
        seen.add(key);
        keys.push(key);
      }
    }
    this.setSelectedKeys(keys);
  }

  /** 工具栏「全选」按钮的图标 / 文案：全部曲目都已选中时才显示勾选态。 */
  isAllSelected(): boolean {
    return this.tracks.length > 0 && this.selectedKeys.length >= this.tracks.length;
  }

  /** 已选曲目快照（保持歌单顺序）；批量收藏等动作直接消费，不再由页面遍历 key。 */
  selectedTracks(): MobileTrack[] {
    const selected: MobileTrack[] = [];
    for (const track of this.tracks) {
      if (this.isSelected(track.key)) {
        selected.push(cloneTrack(track));
      }
    }
    return selected;
  }

  clearSelection(): void {
    if (this.selectedKeys.length > 0) {
      this.setSelectedKeys([]);
    }
  }

  async removeSelected(): Promise<boolean> {
    if (this.disposed || this.missing || this.isBusy() || this.selectedKeys.length === 0) {
      return false;
    }
    const keys = this.selectedKeys.slice();
    this.batchBusy = true;
    this.error = null;
    try {
      await this.libraryModel.removeTracksFromPlaylist(this.playlistId, keys);
      this.clearSelection();
      return true;
    } catch (_error) {
      this.syncLibraryError();
      return false;
    } finally {
      this.batchBusy = false;
    }
  }

  clearError(): void {
    this.libraryModel.clearError();
    this.error = null;
  }

  onState(snapshot: PlayerViewSnapshot): void {
    if (this.disposed) {
      return;
    }
    const nextKey = snapshot.track === null ? '' : snapshot.track.key;
    if (nextKey !== this.currentKey) {
      this.currentKey = nextKey;
    }
    if (snapshot.status !== this.playbackStatus) {
      this.playbackStatus = snapshot.status;
    }
  }

  onProgress(_progress: PlayerProgressSnapshot): void {
  }

  onError(_error: AppError): void {
  }

  onLibraryChanged(_snapshot: LibrarySnapshot): void {
    if (!this.disposed) {
      this.refreshFromLibrary();
      this.error = null;
    }
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
    this.playerStore.unsubscribe(this);
    this.libraryModel.unsubscribe(this);
  }

  private latestPlaylist(): Playlist | null {
    if (this.disposed || this.missing || this.playlistId.length === 0) {
      return null;
    }
    return this.libraryModel.playlistById(this.playlistId);
  }

  private refreshFromLibrary(): void {
    const playlist = this.playlistId.length === 0 ? null : this.libraryModel.playlistById(this.playlistId);
    if (playlist === null) {
      this.playlistName = '';
      this.tracks = [];
      this.playlistKeySet = new Set<string>();
      this.coverUrl = '';
      this.description = '';
      this.totalDuration = 0;
      this.setSelectedKeys([]);
      this.pendingRemoveKey = '';
      this.missing = true;
      return;
    }
    this.playlistName = playlist.name;
    this.tracks = cloneTracks(playlist.tracks);
    this.playlistKeySet = trackKeySet(this.tracks);
    this.coverUrl = playlistCoverUrl(playlist, this.tracks);
    this.description = playlist.description === undefined ? '' : playlist.description.trim();
    this.totalDuration = sumDurations(this.tracks);
    const kept = this.selectedKeys.filter((key: string): boolean => this.playlistKeySet.has(key));
    if (kept.length !== this.selectedKeys.length) {
      this.setSelectedKeys(kept);
    }
    this.pendingRemoveKey = '';
    this.missing = false;
  }

  private setSelectedKeys(keys: string[]): void {
    this.selectedKeys = keys;
    this.selectedKeySet = toKeySet(keys);
  }

  private syncLibraryError(): void {
    if (this.libraryModel.error !== null) {
      this.error = cloneError(this.libraryModel.error);
    }
  }
}

function cleanPlaylistId(value: string): string {
  return value.trim().slice(0, 80);
}

function cleanTrackKey(value: string): string {
  return value.trim().slice(0, 80);
}

function findTrackIndex(tracks: MobileTrack[], trackKey: string): number {
  const key = cleanTrackKey(trackKey);
  if (key.length === 0) {
    return -1;
  }
  for (let index = 0; index < tracks.length; index++) {
    if (tracks[index].key === key) {
      return index;
    }
  }
  return -1;
}

/** 第一首带封面的曲目；与「我的 · 歌单」行的封面派生口径保持一致。 */
function firstCoverUrl(tracks: MobileTrack[]): string {
  for (const track of tracks) {
    const url = track.coverUrl.trim();
    if (url.length > 0) {
      return url;
    }
  }
  return '';
}

/** 自定义封面优先；没有自定义封面时回落到第一首带封面的曲目。 */
function playlistCoverUrl(playlist: Playlist, tracks: MobileTrack[]): string {
  const custom = playlist.coverUri === undefined ? '' : playlist.coverUri.trim();
  if (custom.length > 0) {
    return custom;
  }
  return firstCoverUrl(tracks);
}

/** 总时长只累加正数，负数 / NaN 视为未知，避免把时长栏显示成负数。 */
function sumDurations(tracks: MobileTrack[]): number {
  let total = 0;
  for (const track of tracks) {
    if (Number.isFinite(track.duration) && track.duration > 0) {
      total += Math.floor(track.duration);
    }
  }
  return total;
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
