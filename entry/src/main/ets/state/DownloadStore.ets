import {
  AppError,
  MobileTrack
} from '../types/MobileTypes';
import {
  DownloadEntry,
  DownloadOutcome,
  DownloadResult,
  DownloadService
} from '../services/DownloadService';
import { toAppError } from '../util/Errors';
import { toKeySet, trackKeySet } from './KeySets';
import {
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
} from './PlayerStore';

/** 一次下载请求的同步回执：`queued` 用于立即提示，`completion` 用于收尾提示。 */
export interface DownloadRequest {
  queued: number;
  skipped: number;
  completion: Promise<DownloadBatchResult>;
}

export interface DownloadBatchResult {
  added: number;
  skipped: number;
  failed: number;
  error: AppError | null;
}

/**
 * 下载列表的状态与动作。
 *
 * 页面只读 `tracks / downloadingKeys / selectedKeys` 这些快照，不接触文件路径；
 * 真正的文件读写和索引持久化都在 `DownloadService`。和 `RecentPlaybackStore` 一样，
 * `attach()` 必须在构造完成、实例进入页面状态之后调用，否则订阅到的是未被 @Observed
 * 代理的原始对象，页面不会刷新。
 */
@Observed
export class DownloadStore implements PlayerStoreListener {
  @Track tracks: MobileTrack[];
  @Track currentKey: string;
  @Track error: AppError | null;
  /** 正在排队或正在写入的曲目 key；同一首歌不会重复入队。 */
  @Track downloadingKeys: string[] = [];
  @Track selectedKeys: string[] = [];
  @Track batchBusy: boolean = false;
  /** 渲染路径的 O(1) 索引；与 `tracks / downloadingKeys / selectedKeys` 同源，整份替换。 */
  @Track private downloadedKeySet: Set<string> = new Set<string>();
  @Track private downloadingKeySet: Set<string> = new Set<string>();
  @Track private selectedKeySet: Set<string> = new Set<string>();

  private readonly playerStore: PlayerStore;
  private readonly downloads: DownloadService;
  private lastTrackKey: string = '';
  private queueChain: Promise<void> = Promise.resolve();
  private disposed: boolean = false;

  constructor(playerStore: PlayerStore, downloads: DownloadService) {
    this.playerStore = playerStore;
    this.downloads = downloads;
    this.tracks = tracksFromEntries(downloads.entries());
    this.downloadedKeySet = trackKeySet(this.tracks);
    this.currentKey = playerStore.snapshot.track === null ? '' : playerStore.snapshot.track.key;
    this.lastTrackKey = this.currentKey;
    this.error = null;
  }

  /** 与其它页面 store 同一套约定：构造后再订阅，且订阅的是被代理的实例。 */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.playerStore.subscribe(this);
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
  }

  onProgress(_progress: PlayerProgressSnapshot): void {
  }

  onError(_error: AppError): void {
  }

  isDownloaded(trackKey: string): boolean {
    return this.downloadedKeySet.has(trackKey);
  }

  isDownloading(trackKey: string): boolean {
    return this.downloadingKeySet.has(trackKey);
  }

  /**
   * 把曲目加入下载队列，立即返回排队数量和完成 promise。
   *
   * 已下载、正在下载以及同一批里重复的曲目会被跳过；真正的下载串行执行，
   * 避免同时抓取多路媒体流。`completion` 永远 resolve，失败数放在结果里。
   */
  request(tracks: MobileTrack[]): DownloadRequest {
    const pending: MobileTrack[] = [];
    const seen: Set<string> = new Set<string>();
    let skipped = 0;
    for (const track of tracks) {
      const key = track.key.trim();
      if (key.length === 0 || seen.has(key) || this.isDownloaded(key) || this.isDownloading(key)) {
        skipped++;
        continue;
      }
      seen.add(key);
      pending.push(track);
    }
    if (pending.length === 0) {
      return {
        queued: 0,
        skipped: skipped,
        completion: Promise.resolve(emptyBatch())
      };
    }
    this.setDownloadingKeys([...this.downloadingKeys, ...pending.map((track: MobileTrack): string => track.key)]);
    const completion: Promise<DownloadBatchResult> = this.queueChain
      .then((): Promise<DownloadBatchResult> => this.runBatch(pending));
    this.queueChain = completion.then((): void => {}, (): void => {});
    return {
      queued: pending.length,
      skipped: skipped,
      completion: completion
    };
  }

  /** 播放下载列表中的某一首；返回是否真正开始装载队列。 */
  async playAt(index: number): Promise<boolean> {
    const tracks = this.tracks.slice();
    if (index < 0 || index >= tracks.length) {
      return false;
    }
    try {
      await this.playerStore.loadQueue(tracks, index, true);
      return true;
    } catch (_error) {
      return false;
    }
  }

  async playAll(): Promise<void> {
    const tracks = this.tracks.slice();
    if (tracks.length === 0) {
      return;
    }
    try {
      await this.playerStore.loadQueue(tracks, 0, true);
    } catch (_error) {
      // 播放失败由 PlayerStore 统一呈现，下载列表保持不变。
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
    if (!this.downloadedKeySet.has(trackKey)) {
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

  /** 删除选中的下载（文件 + 索引）。返回是否确实删掉了内容。 */
  async removeSelected(): Promise<boolean> {
    if (this.disposed || this.batchBusy) {
      return false;
    }
    const keys = this.selectedKeys.slice();
    if (keys.length === 0) {
      return false;
    }
    this.batchBusy = true;
    try {
      const removed = await this.downloads.remove(keys);
      this.clearSelection();
      this.refresh();
      if (!this.disposed) {
        this.error = null;
      }
      return removed > 0;
    } catch (error) {
      if (!this.disposed) {
        this.error = toAppError(error as Object);
      }
      return false;
    } finally {
      if (!this.disposed) {
        this.batchBusy = false;
      }
    }
  }

  clearError(): void {
    this.error = null;
  }

  async dispose(): Promise<void> {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.playerStore.unsubscribe(this);
    await this.queueChain.catch((): void => {});
  }

  private async runBatch(pending: MobileTrack[]): Promise<DownloadBatchResult> {
    let added = 0;
    let skipped = 0;
    let failed = 0;
    let lastError: AppError | null = null;
    for (const track of pending) {
      const key = track.key;
      try {
        const result: DownloadResult = await this.downloads.download(track);
        if (result.outcome === DownloadOutcome.Added) {
          added++;
        } else if (result.outcome === DownloadOutcome.Exists) {
          skipped++;
        } else {
          failed++;
          lastError = result.error;
        }
      } catch (error) {
        failed++;
        lastError = toAppError(error as Object);
      }
      this.removeDownloadingKey(key);
      this.refresh();
      if (lastError !== null && !this.disposed) {
        this.error = lastError;
      }
    }
    return {
      added: added,
      skipped: skipped,
      failed: failed,
      error: lastError
    };
  }

  private removeDownloadingKey(trackKey: string): void {
    if (!this.downloadingKeySet.has(trackKey)) {
      return;
    }
    this.setDownloadingKeys(this.downloadingKeys.filter((key: string): boolean => key !== trackKey));
  }

  /** 设置调整下载上限后由宿主刷新列表（复用内部刷新与选中项裁剪）。 */
  reload(): void {
    this.refresh();
  }

  private refresh(): void {
    if (this.disposed) {
      return;
    }
    this.tracks = tracksFromEntries(this.downloads.entries());
    this.downloadedKeySet = trackKeySet(this.tracks);
    this.pruneSelection();
  }

  private pruneSelection(): void {
    if (this.selectedKeys.length === 0) {
      return;
    }
    const kept = this.selectedKeys.filter((key: string): boolean => this.downloadedKeySet.has(key));
    if (kept.length !== this.selectedKeys.length) {
      this.setSelectedKeys(kept);
    }
  }

  private setDownloadingKeys(keys: string[]): void {
    this.downloadingKeys = keys;
    this.downloadingKeySet = toKeySet(keys);
  }

  private setSelectedKeys(keys: string[]): void {
    this.selectedKeys = keys;
    this.selectedKeySet = toKeySet(keys);
  }
}

function tracksFromEntries(entries: DownloadEntry[]): MobileTrack[] {
  return entries.map((entry: DownloadEntry): MobileTrack => ({
    key: entry.key,
    bvid: entry.bvid,
    aid: entry.aid,
    cid: entry.cid,
    title: entry.title,
    artist: entry.artist,
    coverUrl: entry.coverUrl,
    duration: entry.duration,
    playCount: 0
  }));
}

function emptyBatch(): DownloadBatchResult {
  return {
    added: 0,
    skipped: 0,
    failed: 0,
    error: null
  };
}