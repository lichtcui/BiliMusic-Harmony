export const STORAGE_VERSION: number = 1;
export const APP_VERSION: string = '1.1.0';

export interface AppError {
  code: string;
  message: string;
  retryable: boolean;
}

export interface PlaybackErrorContext {
  trackKey: string;
  generation: number;
}

export class PlaybackProgress {
  position: number;
  duration: number;

  constructor(position: number, duration: number) {
    this.position = position;
    this.duration = duration;
  }
}

export type DiagnosticsRuntimeState =
  'idle' | 'initializing' | 'ready' | 'failed' | 'shutting_down' | 'stopped' | 'unavailable';
export type DiagnosticsNetworkStatus = 'available' | 'unavailable' | 'unknown';
export type DiagnosticsLoginStatus = 'signed-in' | 'signed-out' | 'unknown';
export type DiagnosticsPlayerStatus =
  'idle' | 'loading' | 'playing' | 'paused' | 'error' | 'unavailable';
export type DiagnosticsPlayerMode =
  'sequence' | 'repeat-one' | 'repeat-all' | 'shuffle' | 'unknown';

export interface NativeDiagnostics {
  runtimeState: DiagnosticsRuntimeState;
  appVersion: string;
  storageVersion: number;
  warningCount: number;
  loginStatus: DiagnosticsLoginStatus;
  networkStatus: DiagnosticsNetworkStatus;
  playerStatus: DiagnosticsPlayerStatus;
  playerQueueLength: number;
  playerMode: DiagnosticsPlayerMode;
  errorCode: string;
  errorMessage: string;
}

export interface MobileTrack {
  key: string;
  bvid: string;
  aid: number;
  cid: number;
  title: string;
  artist: string;
  coverUrl: string;
  duration: number;
  playCount: number;
  /**
   * 目录态字段：大于 1 表示这条记录是多 P 合集入口。
   * 只用于搜索结果展示和队列展开，不写入本地资料库。
   */
  collectionSize?: number;
  /** 目录态字段：合集总时长，仅用于搜索列表展示。 */
  collectionTotalDuration?: number;
}

export interface CatalogCollection {
  bvid: string;
  aid: number;
  title: string;
  artist: string;
  coverUrl: string;
  totalDuration: number;
  parts: MobileTrack[];
}

export interface CatalogExpansion {
  tracks: MobileTrack[];
  truncated: boolean;
}

export interface CatalogFeed {
  items: MobileTrack[];
  page: number;
  hasMore: boolean;
}

export interface CatalogSearchResult {
  items: MobileTrack[];
  page: number;
  hasMore: boolean;
  total: number;
  keyword: string;
}

export interface AuthProfile {
  isLogin: boolean;
  mid: number;
  name: string;
  avatarUrl: string;
  vip: boolean;
}

export interface QrLoginStart {
  mode: string;
  expiresAt: number;
}

export interface QrLoginPoll {
  status: string;
  profile?: AuthProfile;
}

export type PlayerMode = 'sequence' | 'repeat-one' | 'repeat-all' | 'shuffle';
export type AudioQuality = 'high' | 'standard' | 'low';
export type PlaybackStatus = 'idle' | 'loading' | 'playing' | 'paused' | 'error';

export interface PlaybackState {
  status: PlaybackStatus;
  track: MobileTrack | null;
  position: number;
  duration: number;
  volume: number;
  mode: PlayerMode;
  queue: MobileTrack[];
  queueIndex: number;
  error?: AppError;
}

export interface PlayerSessionSnapshot {
  version: number;
  queue: MobileTrack[];
  queueIndex: number;
  mode: PlayerMode;
  position: number;
  duration: number;
}

export interface Playlist {
  id: string;
  name: string;
  tracks: MobileTrack[];
  createdAt: number;
  updatedAt: number;
  /**
   * 用户从相册选择的自定义封面（app 沙箱内的 `file://` URI）。
   * 为空 / 缺省时列表与详情页回落到首曲封面；旧版本资料库没有这个字段，读盘时按空串处理。
   */
  coverUri?: string;
  /** 歌单简介；为空 / 缺省时不显示。旧版本资料库同样没有这个字段。 */
  description?: string;
}

export interface LibrarySnapshot {
  version: number;
  favorites: MobileTrack[];
  playlists: Playlist[];
  recent: MobileTrack[];
  positions: Record<string, number>;
  updatedAt: number;
}

export interface LyricLine {
  time: number;
  text: string;
}

export interface LyricResult {
  lines: LyricLine[];
  synced: boolean;
  trackName: string;
  artistName: string;
  sourceId: string;
}

export interface LyricCandidate {
  id: string;
  trackName: string;
  artistName: string;
  albumName: string;
  duration: number;
  image: string;
}

export interface SavedResult {
  saved: boolean;
  updatedAt: number;
}

export interface CancelResult {
  cancelled: boolean;
}

export function emptyAuthProfile(): AuthProfile {
  return {
    isLogin: false,
    mid: 0,
    name: '',
    avatarUrl: '',
    vip: false
  };
}

export function emptyPlaybackState(): PlaybackState {
  return {
    status: 'idle',
    track: null,
    position: 0,
    duration: 0,
    volume: 1,
    mode: 'sequence',
    queue: [],
    queueIndex: -1
  };
}

export function emptyLibrary(): LibrarySnapshot {
  return {
    version: STORAGE_VERSION,
    favorites: [],
    playlists: [],
    recent: [],
    positions: {},
    updatedAt: 0
  };
}
