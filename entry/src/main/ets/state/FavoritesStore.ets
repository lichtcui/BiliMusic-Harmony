import {
  AppError,
  LibrarySnapshot,
  MobileTrack
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
export class FavoritesStore implements PlayerStoreListener, LibraryStoreModelListener {
  @Track tracks: MobileTrack[];
  @Track currentKey: string;
  @Track error: AppError | null;
  @Track pendingKeys: string[] = [];
  /** 多选态：选中的曲目 key，顺序不参与语义，只用于判定 / 批量动作。 */
  @Track selectedKeys: string[] = [];
  @Track batchBusy: boolean = false;
  /** 渲染路径的 O(1) 索引；与上面三个数组同源，只在数组赋值处整份替换。 */
  @Track private favoriteKeySet: Set<string> = new Set<string>();
  @Track private pendingKeySet: Set<string> = new Set<string>();
  @Track private selectedKeySet: Set<string> = new Set<string>();

  private readonly playerStore: PlayerStore;
  private readonly libraryModel: LibraryStoreModel;
  private lastCurrentKey: string = '';
  private disposed: boolean = false;

  constructor(playerStore: PlayerStore, libraryModel: LibraryStoreModel) {
    this.playerStore = playerStore;
    this.libraryModel = libraryModel;
    this.tracks = libraryModel.favoriteTracks();
    this.favoriteKeySet = trackKeySet(this.tracks);
    this.currentKey = playerStore.snapshot.track === null ? '' : playerStore.snapshot.track.key;
    this.lastCurrentKey = this.currentKey;
    this.error = cloneError(libraryModel.error);
  }

  /**
   * Subscribes this store to the player and library stores.
   *
   * Must be called after construction and through the observed instance: @Observed wraps the object
   * only after the constructor returns, so subscribing `this` inside the constructor hands the stores
   * the raw target. Their callbacks would then write through the raw object and bypass the proxy,
   * leaving @ObjectLink pages stale. Call attach() once the instance is stored in page state.
   */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.playerStore.subscribe(this);
    this.libraryModel.subscribe(this);
  }

  onState(snapshot: PlayerViewSnapshot): void {
    if (this.disposed) {
      return;
    }
    const nextKey = snapshot.track === null ? '' : snapshot.track.key;
    if (nextKey !== this.lastCurrentKey) {
      this.lastCurrentKey = nextKey;
      this.currentKey = nextKey;
    }
  }

  onProgress(_progress: PlayerProgressSnapshot): void {
  }

  onError(_error: AppError): void {
  }

  onLibraryChanged(_snapshot: LibrarySnapshot): void {
    if (this.disposed) {
      return;
    }
    this.tracks = this.libraryModel.favoriteTracks();
    this.favoriteKeySet = trackKeySet(this.tracks);
    this.error = null;
    this.pruneSelection();
  }

  onLibraryError(error: AppError): void {
    if (!this.disposed) {
      this.error = cloneError(error);
    }
  }

  isPending(trackKey: string): boolean {
    return this.pendingKeySet.has(trackKey);
  }

  /**
   * 收藏状态查询：历史行等多列表复用，避免各页面自己遍历 `tracks`。
   *
   * 刻意读 `favoriteKeySet` 这个 @Track 字段而不是 `libraryModel` / `tracks`：页面在 `if` /
   * 图标里调用它时，依赖必须落在本 store 的观测字段上，否则收藏后行内图标不会重绘。
   *
   * **只能读 @Track 字段**：本方法在 `RecentPlaybackPage.FavoriteButton` 的渲染路径里被调用，
   * 而 `@Observed` + `@Track` 的类在 UI 上下文（build/update）里读未加 `@Track` 的字段会抛
   * ArkUI 140110「Illegal usage of not @Track'ed property」，进程被直接杀掉。
   * `disposed` 是普通私有字段，不能在这里做兜底；页面销毁后组件已不存在，无需再判。
   */
  isFavorite(trackKey: string): boolean {
    return this.favoriteKeySet.has(trackKey);
  }

  /**
   * 收藏 / 取消收藏。与「我喜欢的」页的 `remove` 共用同一份 `pendingKeys`，
   * 同一首歌在写入期间不会被重复提交。
   */
  async toggle(track: MobileTrack): Promise<boolean> {
    if (this.disposed || track.key.length === 0 || this.isPending(track.key)) {
      return false;
    }
    this.setPendingKeys([...this.pendingKeys, track.key]);
    try {
      await this.libraryModel.toggleFavorite(track);
      return true;
    } catch (_error) {
      if (!this.disposed && this.libraryModel.error !== null) {
        this.error = cloneError(this.libraryModel.error);
      }
      return false;
    } finally {
      this.removePending(track.key);
    }
  }

  /**
   * 批量加入收藏（「历史 · 多选」用）。已经是收藏的曲目跳过，
   * 返回本次新增的条数；一条失败不会中断其余曲目。
   */
  async addMany(tracks: MobileTrack[]): Promise<number> {
    if (this.disposed) {
      return 0;
    }
    const targets: MobileTrack[] = [];
    for (const track of tracks) {
      if (track.key.length === 0 || this.isFavorite(track.key) || this.isPending(track.key)) {
        continue;
      }
      if (findTrackIndex(targets, track.key) >= 0) {
        continue;
      }
      targets.push(track);
    }
    if (targets.length === 0) {
      return 0;
    }
    this.setPendingKeys(this.pendingKeys.concat(targets.map((track: MobileTrack): string => track.key)));
    let added = 0;
    try {
      for (const track of targets) {
        if (this.disposed) {
          break;
        }
        if (this.isFavorite(track.key)) {
          continue;
        }
        try {
          await this.libraryModel.toggleFavorite(track);
          added++;
        } catch (_error) {
          if (!this.disposed && this.libraryModel.error !== null) {
            this.error = cloneError(this.libraryModel.error);
          }
        }
      }
      return added;
    } finally {
      this.removePendings(targets.map((track: MobileTrack): string => track.key));
    }
  }

  /** 播放指定收藏曲目；返回是否真正开始装载队列，供页面决定是否跳转播放页。 */
  async playTrack(trackKey: string): Promise<boolean> {
    const tracks = this.libraryModel.favoriteTracks();
    const index = findTrackIndex(tracks, trackKey);
    if (index < 0) {
      return false;
    }
    try {
      await this.playerStore.loadQueue(tracks, index, true);
      return true;
    } catch (_error) {
      // Playback failures stay in PlayerStore; favorites remain unchanged.
      return false;
    }
  }

  async playAll(): Promise<void> {
    const tracks = this.libraryModel.favoriteTracks();
    if (tracks.length === 0) {
      return;
    }
    try {
      await this.playerStore.loadQueue(tracks, 0, true);
    } catch (_error) {
      // Playback failures stay in PlayerStore; favorites remain unchanged.
    }
  }

  async remove(trackKey: string): Promise<boolean> {
    if (this.disposed || trackKey.length === 0 || this.isPending(trackKey)) {
      return false;
    }
    const tracks = this.libraryModel.favoriteTracks();
    const index = findTrackIndex(tracks, trackKey);
    if (index < 0) {
      return false;
    }
    this.setPendingKeys([...this.pendingKeys, trackKey]);
    try {
      await this.libraryModel.toggleFavorite(tracks[index]);
      return true;
    } catch (_error) {
      if (!this.disposed && this.libraryModel.error !== null) {
        this.error = cloneError(this.libraryModel.error);
      }
      return false;
    } finally {
      this.removePending(trackKey);
    }
  }

  clearError(): void {
    this.libraryModel.clearError();
    this.error = null;
  }

  isSelected(trackKey: string): boolean {
    return this.selectedKeySet.has(trackKey);
  }

  toggleSelection(trackKey: string): void {
    if (this.disposed || this.batchBusy || trackKey.length === 0) {
      return;
    }
    if (this.selectedKeySet.has(trackKey)) {
      this.setSelectedKeys(this.selectedKeys.filter((key: string): boolean => key !== trackKey));
      return;
    }
    if (!this.favoriteKeySet.has(trackKey)) {
      return;
    }
    this.setSelectedKeys([...this.selectedKeys, trackKey]);
  }

  selectAll(): void {
    if (this.disposed || this.batchBusy) {
      return;
    }
    this.setSelectedKeys(this.tracks.map((track: MobileTrack): string => track.key));
  }

  /** 工具栏「全选」按钮的图标：全部曲目都已选中时才显示勾选态。 */
  isAllSelected(): boolean {
    return this.tracks.length > 0 && this.selectedKeys.length >= this.tracks.length;
  }

  clearSelection(): void {
    if (this.selectedKeys.length > 0) {
      this.setSelectedKeys([]);
    }
  }

  /** 多选批量动作的输入：按列表顺序返回当前选中的曲目，顺序与勾选先后无关。 */
  selectedTracks(): MobileTrack[] {
    return this.tracks.filter((track: MobileTrack): boolean => this.isSelected(track.key));
  }

  /**
   * 多选态批量取消收藏：单次原子写入，不是逐条 toggle。
   * 失败时保留选中项，用户可以直接重试。
   */
  async removeSelected(): Promise<boolean> {
    if (this.disposed || this.batchBusy || this.selectedKeys.length === 0) {
      return false;
    }
    const keys = [...this.selectedKeys];
    this.batchBusy = true;
    try {
      await this.libraryModel.removeFavorites(keys);
      this.clearSelection();
      return true;
    } catch (_error) {
      if (!this.disposed && this.libraryModel.error !== null) {
        this.error = cloneError(this.libraryModel.error);
      }
      return false;
    } finally {
      if (!this.disposed) {
        this.batchBusy = false;
      }
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

  private removePending(trackKey: string): void {
    if (!this.pendingKeySet.has(trackKey)) {
      return;
    }
    this.setPendingKeys(this.pendingKeys.filter((key: string): boolean => key !== trackKey));
  }

  private removePendings(trackKeys: string[]): void {
    if (trackKeys.length === 0) {
      return;
    }
    this.setPendingKeys(this.pendingKeys.filter((key: string): boolean => trackKeys.indexOf(key) < 0));
  }

  private setPendingKeys(keys: string[]): void {
    this.pendingKeys = keys;
    this.pendingKeySet = toKeySet(keys);
  }

  private setSelectedKeys(keys: string[]): void {
    this.selectedKeys = keys;
    this.selectedKeySet = toKeySet(keys);
  }

  /** 收藏列表被外部改写后（单条取消收藏、批量移除）剔掉已不存在的选中项。 */
  private pruneSelection(): void {
    if (this.selectedKeys.length === 0) {
      return;
    }
    const kept = this.selectedKeys.filter((key: string): boolean => this.favoriteKeySet.has(key));
    if (kept.length !== this.selectedKeys.length) {
      this.setSelectedKeys(kept);
    }
  }
}

function findTrackIndex(tracks: MobileTrack[], trackKey: string): number {
  for (let index = 0; index < tracks.length; index++) {
    if (tracks[index].key === trackKey) {
      return index;
    }
  }
  return -1;
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
