import {
  AppError,
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
export class RecentPlaybackStore implements PlayerStoreListener, LibraryStoreModelListener {
  @Track tracks: MobileTrack[];
  @Track currentKey: string;
  @Track error: AppError | null;
  /** 多选态：选中的曲目 key，顺序不参与语义，只用于判定 / 批量动作。 */
  @Track selectedKeys: string[] = [];
  @Track batchBusy: boolean = false;
  /** 渲染路径的 O(1) 索引；与 `tracks / selectedKeys` 同源，整份替换。 */
  @Track private recentKeySet: Set<string> = new Set<string>();
  @Track private selectedKeySet: Set<string> = new Set<string>();

  private readonly playerStore: PlayerStore;
  private readonly libraryModel: LibraryStoreModel;
  private lastTrackKey: string = '';
  private pendingRecords: Promise<void> = Promise.resolve();
  private disposed: boolean = false;

  constructor(playerStore: PlayerStore, libraryModel: LibraryStoreModel) {
    this.playerStore = playerStore;
    this.libraryModel = libraryModel;
    this.tracks = libraryModel.recentTracks();
    this.recentKeySet = trackKeySet(this.tracks);
    this.currentKey = playerStore.snapshot.track === null ? '' : playerStore.snapshot.track.key;
    this.lastTrackKey = this.currentKey;
    this.error = libraryModel.error;
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
    if (nextKey === this.lastTrackKey) {
      return;
    }
    this.lastTrackKey = nextKey;
    this.currentKey = nextKey;
    if (nextKey.length > 0 && snapshot.track !== null) {
      this.record(snapshot.track);
    }
  }

  onProgress(_progress: PlayerProgressSnapshot): void {
  }

  onError(_error: AppError): void {
  }

  onLibraryChanged(): void {
    if (this.disposed) {
      return;
    }
    this.tracks = this.libraryModel.recentTracks();
    this.recentKeySet = trackKeySet(this.tracks);
    this.error = null;
    this.pruneSelection();
  }

  onLibraryError(error: AppError): void {
    if (!this.disposed) {
      this.error = cloneError(error);
    }
  }

  /** 播放指定历史曲目；返回是否真正开始装载队列，供页面决定是否跳转播放页。 */
  async playAt(index: number): Promise<boolean> {
    const tracks = this.libraryModel.recentTracks();
    if (index < 0 || index >= tracks.length) {
      return false;
    }
    try {
      await this.playerStore.loadQueue(tracks, index, true);
      return true;
    } catch (_error) {
      // Playback failures stay in PlayerStore; recent history remains intact.
      return false;
    }
  }

  async playAll(): Promise<void> {
    const tracks = this.libraryModel.recentTracks();
    if (tracks.length === 0) {
      return;
    }
    try {
      await this.playerStore.loadQueue(tracks, 0, true);
    } catch (_error) {
      // Playback failures stay in PlayerStore; recent history remains intact.
    }
  }

  async clearRecent(): Promise<void> {
    try {
      await this.libraryModel.clearRecent();
      this.clearSelection();
    } catch (_error) {
      this.error = this.libraryModel.error;
    }
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
    if (!this.recentKeySet.has(trackKey)) {
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

  /** 工具条「全选」按钮的图标：全部历史曲目都已选中时才显示勾选态。 */
  isAllSelected(): boolean {
    return this.tracks.length > 0 && this.selectedKeys.length >= this.tracks.length;
  }

  clearSelection(): void {
    if (this.selectedKeys.length > 0) {
      this.setSelectedKeys([]);
    }
  }

  selectedTracks(): MobileTrack[] {
    return this.tracks.filter((track: MobileTrack): boolean => this.isSelected(track.key));
  }

  /**
   * 移除选中的历史记录。全选时走 `clearRecent`，保留「清空最近播放」的原始语义；
   * 其余情况按 key 精确删除，收藏和歌单不受影响。
   */
  async removeSelected(): Promise<boolean> {
    if (this.disposed || this.batchBusy) {
      return false;
    }
    const keys = [...this.selectedKeys];
    if (keys.length === 0) {
      return false;
    }
    const all = this.libraryModel.recentTracks();
    const removingEverything = keys.length >= all.length;
    this.batchBusy = true;
    try {
      if (removingEverything) {
        await this.libraryModel.clearRecent();
      } else {
        await this.libraryModel.removeRecent(keys);
      }
      this.clearSelection();
      return true;
    } catch (_error) {
      if (!this.disposed) {
        this.error = this.libraryModel.error;
      }
      return false;
    } finally {
      if (!this.disposed) {
        this.batchBusy = false;
      }
    }
  }

  clearError(): void {
    this.libraryModel.clearError();
    this.error = null;
  }

  async flush(): Promise<void> {
    await this.pendingRecords.catch((): void => {});
  }

  async dispose(): Promise<void> {
    if (this.disposed) {
      await this.flush();
      return;
    }
    this.disposed = true;
    this.playerStore.unsubscribe(this);
    this.libraryModel.unsubscribe(this);
    await this.flush();
  }

  /** 列表被外部改写后（播放新歌、清空）把已不存在的选中项剔掉，避免批量动作打空。 */
  private pruneSelection(): void {
    if (this.selectedKeys.length === 0) {
      return;
    }
    const kept = this.selectedKeys.filter((key: string): boolean => this.recentKeySet.has(key));
    if (kept.length !== this.selectedKeys.length) {
      this.setSelectedKeys(kept);
    }
  }

  private setSelectedKeys(keys: string[]): void {
    this.selectedKeys = keys;
    this.selectedKeySet = toKeySet(keys);
  }

  private record(track: MobileTrack): void {
    const operation: Promise<void> = this.libraryModel.recordRecent(track)
      .then((): void => {}, (): void => {
        if (!this.disposed) {
          this.error = this.libraryModel.error;
        }
      });
    const pending: Promise<void> = this.pendingRecords
      .catch((): void => {})
      .then((): Promise<void> => operation);
    this.pendingRecords = pending;
  }
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
