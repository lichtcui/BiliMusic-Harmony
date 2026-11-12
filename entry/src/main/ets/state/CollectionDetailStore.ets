import {
  AppError,
  CatalogCollection,
  MobileTrack
} from '../types/MobileTypes';
import { toKeySet, trackKeySet } from './KeySets';
import {
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
} from './PlayerStore';

/** 合集详情只需要目录服务的一个能力，方便主机测试注入假网关。 */
export interface CollectionDetailGateway {
  catalogCollection(bvid: string): Promise<CatalogCollection | null>;
}

export type CollectionLoadStatus = 'loading' | 'ready' | 'error';

const COLLECTION_UNAVAILABLE_MESSAGE: string = '合集信息不完整，请稍后重试。';
const COLLECTION_LOAD_FAILED_MESSAGE: string = '合集加载失败，请稍后重试。';

@Observed
export class CollectionDetailStore implements PlayerStoreListener {
  @Track bvid: string = '';
  @Track title: string = '';
  @Track artist: string = '';
  @Track coverUrl: string = '';
  @Track totalDuration: number = 0;
  @Track tracks: MobileTrack[] = [];
  @Track status: CollectionLoadStatus = 'loading';
  @Track error: AppError | null = null;
  @Track selectedKeys: string[] = [];
  @Track currentKey: string = '';
  /** 渲染路径的 O(1) 索引；与 `tracks / selectedKeys` 同源，整份替换。 */
  @Track private collectionKeySet: Set<string> = new Set<string>();
  @Track private selectedKeySet: Set<string> = new Set<string>();

  private readonly gateway: CollectionDetailGateway;
  private readonly playerStore: PlayerStore;
  private loadToken: number = 0;
  private disposed: boolean = false;

  constructor(gateway: CollectionDetailGateway, playerStore: PlayerStore, bvid: string) {
    this.gateway = gateway;
    this.playerStore = playerStore;
    this.bvid = cleanBvid(bvid);
    this.currentKey = playerStore.snapshot.track === null ? '' : playerStore.snapshot.track.key;
  }

  /**
   * 构造完成后通过 @Observed 代理实例订阅；与其它详情 store 一样，不能在 constructor 里订阅。
   */
  attach(): void {
    if (this.disposed) {
      return;
    }
    this.playerStore.subscribe(this);
  }

  /** 首次进入与失败重试共用同一条加载路径；旧请求的结果会被 token 丢弃。 */
  async load(): Promise<void> {
    if (this.disposed || this.bvid.length === 0) {
      this.status = 'error';
      this.error = {
        code: 'collection.invalidBvid',
        message: COLLECTION_UNAVAILABLE_MESSAGE,
        retryable: false
      };
      return;
    }
    const token = this.loadToken + 1;
    this.loadToken = token;
    this.status = 'loading';
    this.error = null;
    try {
      const collection = await this.gateway.catalogCollection(this.bvid);
      if (this.disposed || token !== this.loadToken) {
        return;
      }
      if (collection === null || collection.parts.length === 0) {
        this.status = 'error';
        this.error = {
          code: 'collection.unavailable',
          message: COLLECTION_UNAVAILABLE_MESSAGE,
          retryable: true
        };
        return;
      }
      this.applyCollection(collection);
    } catch (_error) {
      if (this.disposed || token !== this.loadToken) {
        return;
      }
      this.status = 'error';
      this.error = {
        code: 'collection.loadFailed',
        message: COLLECTION_LOAD_FAILED_MESSAGE,
        retryable: true
      };
    }
  }

  /** 全部播放：装载队列后返回是否成功，页面据此决定是否进入播放页。 */
  async playAll(): Promise<boolean> {
    if (this.disposed || this.status !== 'ready' || this.tracks.length === 0) {
      return false;
    }
    try {
      await this.playerStore.loadQueue(cloneTracks(this.tracks), 0, true);
      return true;
    } catch (_error) {
      // 播放错误由 PlayerStore 自己的 error 通道呈现。
      return false;
    }
  }

  /** 播放指定 P；返回是否真正开始装载队列，供页面决定是否跳转播放页。 */
  async playTrack(trackKey: string): Promise<boolean> {
    if (this.disposed || this.status !== 'ready') {
      return false;
    }
    const index = findTrackIndex(this.tracks, cleanTrackKey(trackKey));
    if (index < 0) {
      return false;
    }
    try {
      await this.playerStore.loadQueue(cloneTracks(this.tracks), index, true);
      return true;
    } catch (_error) {
      return false;
    }
  }

  isSelected(trackKey: string): boolean {
    return this.selectedKeySet.has(cleanTrackKey(trackKey));
  }

  toggleSelection(trackKey: string): boolean {
    if (this.disposed || this.status !== 'ready') {
      return false;
    }
    const key = cleanTrackKey(trackKey);
    if (key.length === 0 || !this.collectionKeySet.has(key)) {
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
    if (this.disposed || this.status !== 'ready' || this.tracks.length === 0) {
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
    return this.tracks
      .filter((track: MobileTrack): boolean => this.isSelected(track.key))
      .map((track: MobileTrack): MobileTrack => cloneTrack(track));
  }

  onState(snapshot: PlayerViewSnapshot): void {
    if (this.disposed) {
      return;
    }
    const nextKey = snapshot.track === null ? '' : snapshot.track.key;
    if (nextKey !== this.currentKey) {
      this.currentKey = nextKey;
    }
  }

  onProgress(_progress: PlayerProgressSnapshot): void {
  }

  onError(_error: AppError): void {
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.loadToken += 1;
    this.playerStore.unsubscribe(this);
  }

  private applyCollection(collection: CatalogCollection): void {
    this.title = collection.title;
    this.artist = collection.artist;
    this.coverUrl = collection.coverUrl;
    this.totalDuration = collection.totalDuration;
    this.tracks = cloneTracks(collection.parts);
    this.collectionKeySet = trackKeySet(this.tracks);
    const kept = this.selectedKeys.filter((key: string): boolean => this.collectionKeySet.has(key));
    if (kept.length !== this.selectedKeys.length) {
      this.setSelectedKeys(kept);
    }
    this.status = 'ready';
    this.error = null;
  }

  private setSelectedKeys(keys: string[]): void {
    this.selectedKeys = keys;
    this.selectedKeySet = toKeySet(keys);
  }
}

function cleanBvid(value: string): string {
  return value.trim().slice(0, 32);
}

function cleanTrackKey(value: string): string {
  return value.trim().slice(0, 80);
}

function findTrackIndex(tracks: MobileTrack[], trackKey: string): number {
  if (trackKey.length === 0) {
    return -1;
  }
  for (let index = 0; index < tracks.length; index++) {
    if (tracks[index].key === trackKey) {
      return index;
    }
  }
  return -1;
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