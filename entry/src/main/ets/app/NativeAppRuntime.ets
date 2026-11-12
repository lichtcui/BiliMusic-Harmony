import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  APP_VERSION,
  AuthProfile,
  AppError,
  AudioQuality,
  CatalogCollection,
  CatalogExpansion,
  CatalogFeed,
  CatalogSearchResult,
  DiagnosticsLoginStatus,
  DiagnosticsNetworkStatus,
  DiagnosticsPlayerMode,
  DiagnosticsPlayerStatus,
  DiagnosticsRuntimeState,
  LibrarySnapshot,
  LyricCandidate,
  LyricResult,
  MobileTrack,
  NativeDiagnostics,
  PlaybackErrorContext,
  PlaybackState,
  PlayerMode,
  PlayerSessionSnapshot,
  QrLoginPoll,
  QrLoginStart,
  SavedResult,
  STORAGE_VERSION
} from '../types/MobileTypes';
import {
  errorMessageForCode,
  toAppError,
  NativeError,
  sanitizeErrorCode
} from '../util/Errors';
import { AuthService } from '../services/AuthService';
import { AuthProfileStore } from '../services/AuthProfileStore';
import {
  BiliHttpClient,
  BiliImage,
  HttpRequestConfig
} from '../services/BiliHttpClient';
import { CatalogService } from '../services/CatalogService';
import { DownloadService } from '../services/DownloadService';
import { CookieJar } from '../services/CookieJar';
import { FileImageDiskCache, HttpImageFetcher, ImageCacheService } from '../services/ImageCacheService';
import { LibraryStore } from '../services/LibraryStore';
import { LyricsHttpGateway, LyricsService } from '../services/LyricsService';
import { PlayerEventSink, PlayerService } from '../services/PlayerService';
import { AuthGateway, AuthStore } from '../state/AuthStore';
import {
  CacheManagementGateway,
  CacheSizeStats
} from '../state/CacheManagementStore';
import { LibraryStoreModel } from '../state/LibraryStoreModel';
import { LyricsGateway, LyricsStore } from '../state/LyricsStore';
import { PlayerCommandTarget, PlayerStore } from '../state/PlayerStore';
import { PlayerSessionStore } from '../state/PlayerSessionStore';
import { FavoritesStore } from '../state/FavoritesStore';
import { DownloadStore } from '../state/DownloadStore';
import { RecentPlaybackStore } from '../state/RecentPlaybackStore';
import { SearchGateway } from '../state/SearchStore';
import {
  MobileSettings,
  SettingsPatch,
  SettingsStore,
  ThemeMode,
  SettingsUpdateResult
} from '../state/SettingsStore';

const DOMAIN = 0x424D;
const TAG = 'WispMusicNativeRuntime';

export type NativeRuntimeLifecycle = 'idle' | 'initializing' | 'ready' | 'failed' | 'shutting_down' | 'stopped';

export interface NativeRuntimeSnapshot {
  state: NativeRuntimeLifecycle;
  error: AppError | null;
  warnings: AppError[];
}

interface NativeAppServices {
  cookies: CookieJar;
  http: BiliHttpClient;
  images: ImageCacheService;
  auth: AuthService;
  authStore: AuthStore;
  catalog: CatalogService;
  library: LibraryStore;
  libraryModel: LibraryStoreModel;
  settings: SettingsStore;
  playerStore: PlayerStore;
  playerSessionStore: PlayerSessionStore;
  lyricsStore: LyricsStore;
  favoritesStore: FavoritesStore;
  recentPlaybackStore: RecentPlaybackStore;
  downloads: DownloadService;
  downloadStore: DownloadStore;
  player: PlayerService;
  lyrics: LyricsService;
}

class RuntimeAuthGateway implements AuthGateway {
  private readonly auth: AuthService;

  constructor(auth: AuthService) {
    this.auth = auth;
  }

  startQrLogin(): Promise<QrLoginStart> {
    return this.auth.startQrLogin();
  }

  pollQrLogin(): Promise<QrLoginPoll> {
    return this.auth.pollQrLogin();
  }

  refreshProfile(): Promise<AuthProfile> {
    return this.auth.refreshProfile();
  }

  status(): AuthProfile {
    return this.auth.status();
  }

  hasLoginCredentials(): boolean {
    return this.auth.hasLoginCredentials();
  }

  logout(): Promise<AuthProfile> {
    return this.auth.logout();
  }

  currentQrUrl(): string {
    return this.auth.currentQrUrl();
  }

  cancelQrLogin(): void {
    this.auth.cancelQrLogin();
  }
}

class RuntimePlayerSink implements PlayerEventSink {
  private readonly store: PlayerStore;
  private readonly sessionStore: PlayerSessionStore;
  private captureEnabled: boolean = false;

  constructor(store: PlayerStore, sessionStore: PlayerSessionStore) {
    this.store = store;
    this.sessionStore = sessionStore;
  }

  setCaptureEnabled(enabled: boolean): void {
    this.captureEnabled = enabled;
  }

  onState(state: PlaybackState): void {
    if (this.captureEnabled) {
      this.sessionStore.captureState(state);
    }
    this.store.onState(state);
  }

  onProgress(position: number, duration: number): void {
    if (this.captureEnabled) {
      this.sessionStore.captureProgress(position, duration);
    }
    this.store.onProgress(position, duration);
  }

  onError(error: AppError, context?: PlaybackErrorContext): void {
    this.store.onError(error, context);
  }
}

class RuntimePlayerCommandTarget implements PlayerCommandTarget {
  private readonly player: PlayerService;

  constructor(player: PlayerService) {
    this.player = player;
  }

  loadQueue(params: Record<string, Object>): Promise<PlaybackState> {
    return this.player.loadQueue(params);
  }

  appendToQueue(params: Record<string, Object>): Promise<PlaybackState> {
    return this.player.appendToQueue(params);
  }

  removeFromQueue(params: Record<string, Object>): Promise<PlaybackState> {
    return this.player.removeFromQueue(params);
  }

  clearQueue(): Promise<PlaybackState> {
    return this.player.clearQueue();
  }

  restoreSession(session: PlayerSessionSnapshot): Promise<PlaybackState> {
    return this.player.restoreSession(session);
  }

  play(params: Record<string, Object>): Promise<PlaybackState> {
    return this.player.play(params);
  }

  pause(): Promise<PlaybackState> {
    return this.player.pause();
  }

  seek(params: Record<string, Object>): Promise<PlaybackState> {
    return this.player.seek(params);
  }

  next(): Promise<PlaybackState> {
    return this.player.next();
  }

  previous(): Promise<PlaybackState> {
    return this.player.previous();
  }

  skipPrevious(): Promise<PlaybackState> {
    return this.player.skipPrevious();
  }

  setMode(params: Record<string, Object>): Promise<PlaybackState> {
    return this.player.setMode(params);
  }

  setQuality(params: Record<string, Object>): Promise<PlaybackState> {
    return this.player.setQuality(params);
  }

  snapshot(): PlaybackState {
    return this.player.snapshot();
  }
}

class RuntimeLyricsGateway implements LyricsGateway {
  private readonly lyrics: LyricsService;

  constructor(lyrics: LyricsService) {
    this.lyrics = lyrics;
  }

  resolve(params: Record<string, Object>): Promise<LyricResult | null> {
    return this.lyrics.resolve(params);
  }

  search(query: string): Promise<LyricCandidate[]> {
    const params: Record<string, Object> = {};
    params.query = query;
    return this.lyrics.search(params);
  }

  choose(params: Record<string, Object>): Promise<LyricResult | null> {
    return this.lyrics.choose(params);
  }
}

class RuntimeLyricsHttpGateway implements LyricsHttpGateway {
  private readonly http: BiliHttpClient;

  constructor(http: BiliHttpClient) {
    this.http = http;
  }

  requestJson(targetUrl: string, config: HttpRequestConfig): Promise<Record<string, Object>> {
    return this.http.requestJson(targetUrl, config);
  }
}

export class NativeAppRuntime implements SearchGateway, CacheManagementGateway {
  private readonly context: common.UIAbilityContext;
  private readonly themeModeSink: ((mode: ThemeMode) => void) | null;
  private services: NativeAppServices | null = null;
  private lifecycle: NativeRuntimeLifecycle = 'idle';
  private runtimeError: AppError | null = null;
  private warnings: AppError[] = [];
  private initializePromise: Promise<NativeRuntimeSnapshot> | null = null;
  private shutdownPromise: Promise<void> | null = null;
  private authRefreshPromise: Promise<void> | null = null;
  private playerSink: RuntimePlayerSink | null = null;

  constructor(context: common.UIAbilityContext,
    themeModeSink: ((mode: ThemeMode) => void) | null = null) {
    this.context = context;
    this.themeModeSink = themeModeSink;
    hilog.info(DOMAIN, TAG, 'native runtime created');
  }

  snapshot(): NativeRuntimeSnapshot {
    return {
      state: this.lifecycle,
      error: this.runtimeError,
      warnings: this.warnings.slice()
    };
  }

  async diagnostics(): Promise<NativeDiagnostics> {
    hilog.info(DOMAIN, TAG, 'diagnostics requested state=%{public}s', this.lifecycle);
    let networkStatus: DiagnosticsNetworkStatus = 'unknown';
    try {
      const net = await connection.getDefaultNet();
      networkStatus = net.netId === 0 ? 'unavailable' : 'available';
    } catch (_error) {
      hilog.warn(DOMAIN, TAG, 'network diagnostics unavailable');
    }

    let runtimeState: DiagnosticsRuntimeState = 'unavailable';
    let warningCount: number = 0;
    let runtimeError: AppError | null = null;
    try {
      const runtime = this.snapshot();
      runtimeState = runtime.state;
      warningCount = runtime.warnings.length;
      runtimeError = runtime.error;
    } catch (_error) {
      hilog.warn(DOMAIN, TAG, 'runtime diagnostics unavailable');
    }

    const services = this.services;
    let loginStatus: DiagnosticsLoginStatus = 'unknown';
    let playerStatus: DiagnosticsPlayerStatus = 'unavailable';
    let playerQueueLength = 0;
    let playerMode: DiagnosticsPlayerMode = 'unknown';
    if (services !== null) {
      try {
        loginStatus = services.authStore.read().profile.isLogin ? 'signed-in' : 'signed-out';
      } catch (_error) {
        hilog.warn(DOMAIN, TAG, 'auth diagnostics unavailable');
      }
      try {
        const player = services.playerStore.read();
        playerStatus = player.status;
        playerQueueLength = player.queue.length;
        playerMode = player.mode;
      } catch (_error) {
        hilog.warn(DOMAIN, TAG, 'player diagnostics unavailable');
      }
    }

    let errorCode = '';
    let errorMessage = '';
    if (runtimeError !== null) {
      try {
        errorCode = sanitizeErrorCode(runtimeError.code);
        errorMessage = errorMessageForCode(errorCode, runtimeError.retryable);
      } catch (_error) {
        errorCode = 'native.error';
        errorMessage = errorMessageForCode(errorCode, false);
        hilog.warn(DOMAIN, TAG, 'runtime error diagnostics unavailable');
      }
    }
    return {
      runtimeState: runtimeState,
      appVersion: APP_VERSION,
      storageVersion: STORAGE_VERSION,
      warningCount: warningCount,
      loginStatus: loginStatus,
      networkStatus: networkStatus,
      playerStatus: playerStatus,
      playerQueueLength: playerQueueLength,
      playerMode: playerMode,
      errorCode: errorCode,
      errorMessage: errorMessage
    };
  }

  initialize(): Promise<NativeRuntimeSnapshot> {
    if (this.lifecycle === 'ready' || this.lifecycle === 'failed' || this.lifecycle === 'stopped' ||
      this.lifecycle === 'shutting_down') {
      return Promise.resolve(this.snapshot());
    }
    if (this.initializePromise !== null) {
      return this.initializePromise;
    }
    this.lifecycle = 'initializing';
    this.runtimeError = null;
    this.warnings = [];
    this.initializePromise = this.initializeOnce();
    return this.initializePromise;
  }

  retry(): Promise<NativeRuntimeSnapshot> {
    if (this.lifecycle !== 'failed') {
      return this.initialize();
    }
    this.lifecycle = 'idle';
    this.runtimeError = null;
    this.warnings = [];
    this.initializePromise = null;
    return this.initialize();
  }

  shutdown(): Promise<void> {
    if (this.shutdownPromise !== null) {
      return this.shutdownPromise;
    }
    this.shutdownPromise = this.shutdownOnce();
    return this.shutdownPromise;
  }

  async loadImage(targetUrl: string): Promise<BiliImage | null> {
    try {
      const services = await this.ensureReady();
      const image = await services.images.loadImage(targetUrl);
      if (image === null) {
        return null;
      }
      return {
        mime: image.mime,
        data: image.data
      };
    } catch (error) {
      const appError = toAppError(error as Object);
      hilog.warn(DOMAIN, TAG, 'image request failed code=%{public}s', appError.code);
      return null;
    }
  }

  async imageCacheStats(): Promise<CacheSizeStats> {
    const services = await this.ensureReady();
    const stats = await services.images.stats();
    return {
      bytes: stats.bytes,
      entries: stats.entries
    };
  }

  async lyricsCacheStats(): Promise<CacheSizeStats> {
    const services = await this.ensureReady();
    const stats = await services.lyrics.stats();
    return {
      bytes: stats.bytes,
      entries: stats.entries
    };
  }

  async clearImageCache(): Promise<CacheSizeStats> {
    const services = await this.ensureReady();
    const stats = await services.images.clear();
    return {
      bytes: stats.bytes,
      entries: stats.entries
    };
  }

  async clearLyricsCache(): Promise<CacheSizeStats> {
    const services = await this.ensureReady();
    const stats = await services.lyrics.clear();
    return {
      bytes: stats.bytes,
      entries: stats.entries
    };
  }

  async audioCacheStats(): Promise<CacheSizeStats> {
    const services = await this.ensureReady();
    return services.player.audioCacheStats();
  }

  async clearAudioCache(): Promise<CacheSizeStats> {
    const services = await this.ensureReady();
    return services.player.clearAudioCache();
  }

  async discover(page: number = 1, pageSize: number = 20): Promise<CatalogFeed> {
    const services = await this.ensureReady();
    return services.catalog.discover(page, pageSize);
  }

  async recommend(page: number = 1, pageSize: number = 20): Promise<CatalogFeed> {
    const services = await this.ensureReady();
    return services.catalog.recommend(page, pageSize);
  }

  async search(keyword: string, page: number = 1, pageSize: number = 20): Promise<CatalogSearchResult> {
    const services = await this.ensureReady();
    return services.catalog.search(keyword, page, pageSize);
  }

  async catalogCollection(bvid: string): Promise<CatalogCollection | null> {
    const services = await this.ensureReady();
    return services.catalog.collection(bvid);
  }

  async expandTracks(tracks: MobileTrack[], limit: number = 500): Promise<CatalogExpansion> {
    const services = await this.ensureReady();
    return services.catalog.expandTracks(tracks, limit);
  }

  async catalogDetail(track: MobileTrack, bvid: string = '', aid: number = 0,
    cid: number = 0): Promise<MobileTrack> {
    const services = await this.ensureReady();
    const params: Record<string, Object> = {};
    params.track = track;
    if (bvid.length > 0) {
      params.bvid = bvid;
    }
    if (aid > 0) {
      params.aid = aid;
    }
    if (cid > 0) {
      params.cid = cid;
    }
    return services.catalog.detail(params);
  }

  async startQrLogin(): Promise<QrLoginStart> {
    const services = await this.ensureReady();
    return services.auth.startQrLogin();
  }

  async pollQrLogin(): Promise<QrLoginPoll> {
    const services = await this.ensureReady();
    try {
      return await services.auth.pollQrLogin();
    } catch (error) {
      const appError = toAppError(error as Object);
      hilog.warn(DOMAIN, TAG, 'QR poll failed code=%{public}s', appError.code);
      if (error instanceof NativeError) {
        throw error;
      }
      throw new NativeError(appError.code, appError.message, appError.retryable);
    }
  }

  async cancelQrLogin(): Promise<void> {
    const services = await this.ensureReady();
    services.auth.cancelQrLogin();
  }

  async authStatus(): Promise<AuthProfile> {
    const services = await this.ensureReady();
    return services.auth.status();
  }

  async authStore(): Promise<AuthStore> {
    const services = await this.ensureReady();
    return services.authStore;
  }

  async logout(): Promise<AuthProfile> {
    const services = await this.ensureReady();
    return services.auth.logout();
  }

  async loadQueue(queue: MobileTrack[], startIndex: number = 0,
    autoplay: boolean = true): Promise<PlaybackState> {
    const services = await this.ensureReady();
    await services.playerStore.loadQueue(queue, startIndex, autoplay);
    return services.player.snapshot();
  }

  async play(index: number = -1): Promise<PlaybackState> {
    const services = await this.ensureReady();
    await services.playerStore.play(index);
    return services.player.snapshot();
  }

  async pause(): Promise<PlaybackState> {
    const services = await this.ensureReady();
    await services.playerStore.pause();
    return services.player.snapshot();
  }

  async seek(position: number): Promise<PlaybackState> {
    const services = await this.ensureReady();
    await services.playerStore.seek(position);
    return services.player.snapshot();
  }

  async next(): Promise<PlaybackState> {
    const services = await this.ensureReady();
    await services.playerStore.next();
    return services.player.snapshot();
  }

  async previous(): Promise<PlaybackState> {
    const services = await this.ensureReady();
    await services.playerStore.previous();
    return services.player.snapshot();
  }

  async setMode(mode: PlayerMode): Promise<PlaybackState> {
    const services = await this.ensureReady();
    await services.playerStore.setMode(mode);
    return services.player.snapshot();
  }

  async playerStore(): Promise<PlayerStore> {
    const services = await this.ensureReady();
    return services.playerStore;
  }

  async recentPlaybackStore(): Promise<RecentPlaybackStore> {
    const services = await this.ensureReady();
    return services.recentPlaybackStore;
  }

  async favoritesStore(): Promise<FavoritesStore> {
    const services = await this.ensureReady();
    return services.favoritesStore;
  }

  async downloadStore(): Promise<DownloadStore> {
    const services = await this.ensureReady();
    return services.downloadStore;
  }

  async lyricsStore(): Promise<LyricsStore> {
    const services = await this.ensureReady();
    return services.lyricsStore;
  }

  async playerSnapshot(): Promise<PlaybackState> {
    const services = await this.ensureReady();
    return services.player.snapshot();
  }

  async librarySnapshot(): Promise<LibrarySnapshot> {
    const services = await this.ensureReady();
    return services.libraryModel.read();
  }

  async libraryModel(): Promise<LibraryStoreModel> {
    const services = await this.ensureReady();
    return services.libraryModel;
  }

  async writeLibrary(snapshot: LibrarySnapshot): Promise<SavedResult> {
    const services = await this.ensureReady();
    return services.libraryModel.replace(snapshot);
  }

  async settingsSnapshot(): Promise<MobileSettings> {
    const services = await this.ensureReady();
    return services.settings.read();
  }

  async settingsStore(): Promise<SettingsStore> {
    const services = await this.ensureReady();
    return services.settings;
  }

  async updateSettings(patch: SettingsPatch): Promise<SettingsUpdateResult> {
    const services = await this.ensureReady();
    return services.settings.update(patch);
  }

  async setAudioQuality(quality: AudioQuality): Promise<SettingsUpdateResult> {
    const services = await this.ensureReady();
    const result = await services.settings.update({ audioQuality: quality });
    if (!result.success) {
      return result;
    }
    await services.playerStore.setQuality(quality);
    return result;
  }

  /** 下载品质：只影响之后的新下载，不重载当前曲目，也不动已下载文件。 */
  async setDownloadQuality(quality: AudioQuality): Promise<SettingsUpdateResult> {
    const services = await this.ensureReady();
    return services.settings.update({ downloadQuality: quality });
  }

  /**
   * 下载保留条数：先落盘设置，再让 DownloadService 立即按新上限清理，
   * 最后刷新下载页快照；失败时设置已回滚，下载列表保持原样。
   */
  async setDownloadLimit(limit: number): Promise<SettingsUpdateResult> {
    const services = await this.ensureReady();
    const result = await services.settings.update({ downloadLimit: limit });
    if (!result.success) {
      return result;
    }
    try {
      await services.downloads.applyLimit();
    } catch (error) {
      this.addWarning('download limit trim failed', error as Object);
    }
    services.downloadStore.reload();
    return result;
  }

  async resolveLyrics(track: MobileTrack): Promise<LyricResult | null> {
    const services = await this.ensureReady();
    const params: Record<string, Object> = {};
    params.track = track;
    return services.lyrics.resolve(params);
  }

  async searchLyrics(query: string): Promise<LyricCandidate[]> {
    const services = await this.ensureReady();
    const params: Record<string, Object> = {};
    params.query = query;
    return services.lyrics.search(params);
  }

  async chooseLyrics(track: MobileTrack, candidateId: string): Promise<LyricResult | null> {
    const services = await this.ensureReady();
    const params: Record<string, Object> = {};
    params.track = track;
    params.candidateId = candidateId;
    return services.lyrics.choose(params);
  }

  private async initializeOnce(): Promise<NativeRuntimeSnapshot> {
    let pendingPlayerStore: PlayerStore | null = null;
    let pendingRecentPlaybackStore: RecentPlaybackStore | null = null;
    let pendingFavoritesStore: FavoritesStore | null = null;
    let pendingLibrary: LibraryStore | null = null;
    let pendingPlayer: PlayerService | null = null;
    let pendingLyrics: LyricsService | null = null;
    let pendingLyricsStore: LyricsStore | null = null;
    let pendingImages: ImageCacheService | null = null;
    let pendingAuthStore: AuthStore | null = null;
    let pendingLibraryModel: LibraryStoreModel | null = null;
    let pendingSettings: SettingsStore | null = null;
    let pendingPlayerSessionStore: PlayerSessionStore | null = null;
    try {
      const cookies = new CookieJar(`${this.context.filesDir}/bili-cookies-v1.json`);
      const http = new BiliHttpClient(cookies);
      const images = new ImageCacheService(new HttpImageFetcher(http),
        new FileImageDiskCache(`${this.context.cacheDir}/images-v1`));
      pendingImages = images;
      const auth = new AuthService(http, cookies,
        new AuthProfileStore(`${this.context.filesDir}/auth-profile-v1.json`));
      const authStore = new AuthStore(new RuntimeAuthGateway(auth));
      pendingAuthStore = authStore;
      const catalog = new CatalogService(http);
      // 资料库读盘放到 loadAsync()：与媒体会话初始化并行，不阻塞首帧。
      const library = LibraryStore.deferred(`${this.context.filesDir}/library-v1.json`);
      pendingLibrary = library;
      const settings = new SettingsStore(`${this.context.filesDir}/settings-v1.json`);
      pendingSettings = settings;
      settings.setThemeModeListener((mode: ThemeMode): void => {
        const sink = this.themeModeSink;
        if (sink !== null) {
          sink(mode);
        }
      });
      const playerStore = new PlayerStore();
      pendingPlayerStore = playerStore;
      const playerSessionStore = new PlayerSessionStore(
        `${this.context.filesDir}/player-session-v1.json`);
      pendingPlayerSessionStore = playerSessionStore;
      const playerSink = new RuntimePlayerSink(playerStore, playerSessionStore);
      this.playerSink = playerSink;
      const downloads = DownloadService.fromRuntime(this.context.filesDir, catalog, http,
        (): AudioQuality => settings.read().downloadQuality,
        (): number => settings.read().downloadLimit);
      const player = new PlayerService(this.context, catalog, library, http,
        playerSink, settings.read().audioQuality, downloads);
      playerStore.bind(new RuntimePlayerCommandTarget(player));
      pendingPlayer = player;
      const lyrics = new LyricsService(new RuntimeLyricsHttpGateway(http),
        `${this.context.filesDir}/lyrics-v1.json`);
      pendingLyrics = lyrics;
      // 读盘与媒体会话初始化互不依赖，一起等，冷启动少一次串行耗时。
      const libraryLoad = library.loadAsync().catch((error: Object): void => {
        this.addWarning('library load failed; starting empty', error);
      });
      const playerInit = player.initialize().catch((error: Object): void => {
        this.addWarning('player initialization failed; continuing with runtime errors', error);
      });
      await Promise.all([libraryLoad, playerInit]);
      const libraryModel = new LibraryStoreModel(library);
      pendingLibraryModel = libraryModel;
      const sessionDiagnostics = playerSessionStore.storageDiagnostics();
      if (sessionDiagnostics.recovered && sessionDiagnostics.error !== null) {
        this.addWarning('player session recovery fallback', sessionDiagnostics.error);
      }
      if (settings.read().restorePlayback) {
        const restoredSession = playerSessionStore.restore();
        if (restoredSession !== null) {
          try {
            await playerStore.restoreSession(restoredSession);
          } catch (error) {
            this.addWarning('player session restore failed; starting idle', error as Object);
          }
        }
      }
      const recentPlaybackStore = new RecentPlaybackStore(playerStore, libraryModel);
      pendingRecentPlaybackStore = recentPlaybackStore;
      const favoritesStore = new FavoritesStore(playerStore, libraryModel);
      pendingFavoritesStore = favoritesStore;
      const downloadStore = new DownloadStore(playerStore, downloads);
      const lyricsStore = new LyricsStore(playerStore, new RuntimeLyricsGateway(lyrics));
      pendingLyricsStore = lyricsStore;
      this.services = {
        cookies: cookies,
        http: http,
        images: images,
        auth: auth,
        authStore: authStore,
        catalog: catalog,
        library: library,
        libraryModel: libraryModel,
        settings: settings,
        playerStore: playerStore,
        playerSessionStore: playerSessionStore,
        lyricsStore: lyricsStore,
        favoritesStore: favoritesStore,
        recentPlaybackStore: recentPlaybackStore,
        downloads: downloads,
        downloadStore: downloadStore,
        player: player,
        lyrics: lyrics
      };
      // 初始化与 shutdown 并发时：服务已建好，交给正在收尾的 shutdownOnce 统一 dispose，
      // 这里不再对外报 ready，也不再启动后台刷新（A4）。
      if (this.lifecycle === 'shutting_down' || this.lifecycle === 'stopped') {
        hilog.info(DOMAIN, TAG, 'native runtime initialized during shutdown; deferring cleanup');
        return this.snapshot();
      }
      playerSink.setCaptureEnabled(true);
      this.lifecycle = 'ready';
      hilog.info(DOMAIN, TAG, 'native runtime initialized warningCount=%{public}d', this.warnings.length);
      // /nav 只影响页头资料的新鲜度，不能再阻塞首帧；有缓存时先用缓存，刷新失败保持缓存。
      if (auth.hasLoginCredentials()) {
        this.authRefreshPromise = authStore.refreshProfile()
          .then((): void => {})
          .catch((error: Object): void => {
            this.addWarning('initial auth refresh failed; keeping cached profile', error);
          })
          .finally((): void => {
            this.authRefreshPromise = null;
          });
      }
    } catch (error) {
      const appError = toAppError(error as Object);
      this.runtimeError = appError;
      this.services = null;
      const sink = this.playerSink;
      this.playerSink = null;
      if (sink !== null) {
        sink.setCaptureEnabled(false);
      }
      await this.cleanupPartial(pendingRecentPlaybackStore, pendingFavoritesStore,
        pendingPlayerStore, pendingPlayer,
        pendingLyricsStore, pendingLyrics, pendingLibrary, pendingImages,
        pendingAuthStore, pendingLibraryModel, pendingSettings, pendingPlayerSessionStore);
      this.lifecycle = 'failed';
      hilog.error(DOMAIN, TAG, 'native runtime initialization failed code=%{public}s', appError.code);
    } finally {
      this.initializePromise = null;
    }
    return this.snapshot();
  }

  private async shutdownOnce(): Promise<void> {
    this.lifecycle = 'shutting_down';
    // 先关捕获：player.shutdown() 之后迟到的 onProgress 不会再排队写会话文件（A6）。
    const sink = this.playerSink;
    this.playerSink = null;
    if (sink !== null) {
      sink.setCaptureEnabled(false);
    }
    try {
      if (this.initializePromise !== null) {
        try {
          await this.initializePromise;
        } catch (error) {
          this.logCleanupFailure('initialization', error as Object);
        }
      }
      const authRefresh = this.authRefreshPromise;
      if (authRefresh !== null) {
        try {
          await authRefresh;
        } catch (error) {
          this.logCleanupFailure('auth refresh', error as Object);
        }
      }
      const services = this.services;
      this.services = null;
      if (services !== null) {
        await this.shutdownServices(services);
      }
    } finally {
      // 中段任何一步抛错都不能让 lifecycle 永久停在 shutting_down（A3）。
      this.lifecycle = 'stopped';
      this.runtimeError = null;
      this.warnings = [];
      hilog.info(DOMAIN, TAG, 'native runtime stopped');
    }
  }

  /** 逐项收尾：每一项独立 try/catch，一项失败不跳过后续的 flush（A3）。 */
  private async shutdownServices(services: NativeAppServices): Promise<void> {
    await this.cleanupStep('settings listener', async (): Promise<void> => {
      services.settings.setThemeModeListener(null);
    });
    await this.cleanupStep('player session', async (): Promise<void> => {
      services.playerSessionStore.captureState(services.player.snapshot());
      await services.playerSessionStore.flush();
    });
    await this.cleanupStep('auth store', async (): Promise<void> => {
      services.authStore.dispose();
    });
    await this.cleanupStep('recent playback', async (): Promise<void> => {
      await services.recentPlaybackStore.dispose();
    });
    await this.cleanupStep('downloads', async (): Promise<void> => {
      await services.downloadStore.dispose();
    });
    await this.cleanupStep('favorites', async (): Promise<void> => {
      services.favoritesStore.dispose();
    });
    await this.cleanupStep('lyrics store', async (): Promise<void> => {
      services.lyricsStore.dispose();
    });
    await this.cleanupStep('player store', async (): Promise<void> => {
      services.playerStore.detachTarget();
      services.playerStore.dispose();
    });
    await this.cleanupStep('player', async (): Promise<void> => {
      await services.player.shutdown();
    });
    await this.cleanupStep('images', async (): Promise<void> => {
      await services.images.shutdown();
    });
    await this.cleanupStep('lyrics', async (): Promise<void> => {
      await services.lyrics.shutdown();
    });
    await this.cleanupStep('settings', async (): Promise<void> => {
      await services.settings.flush();
    });
    await this.cleanupStep('library', async (): Promise<void> => {
      await services.libraryModel.flush();
    });
    // 最后冻结会话写链：player.shutdown() 之后不再接受新快照，并等最后一笔写盘完成。
    await this.cleanupStep('player session dispose', async (): Promise<void> => {
      await services.playerSessionStore.dispose();
    });
  }

  private async cleanupStep(label: string, action: () => Promise<void>): Promise<void> {
    try {
      await action();
    } catch (error) {
      this.logCleanupFailure(label, error as Object);
    }
  }

  private async cleanupPartial(recentPlaybackStore: RecentPlaybackStore | null,
    favoritesStore: FavoritesStore | null, playerStore: PlayerStore | null,
    player: PlayerService | null,
    lyricsStore: LyricsStore | null, lyrics: LyricsService | null, library: LibraryStore | null,
    images: ImageCacheService | null, authStore: AuthStore | null,
    libraryModel: LibraryStoreModel | null, settings: SettingsStore | null,
    playerSessionStore: PlayerSessionStore | null): Promise<void> {
    if (recentPlaybackStore !== null) {
      await recentPlaybackStore.dispose();
    }
    if (favoritesStore !== null) {
      favoritesStore.dispose();
    }
    if (lyricsStore !== null) {
      lyricsStore.dispose();
    }
    if (playerStore !== null) {
      playerStore.detachTarget();
      playerStore.dispose();
    }
    if (authStore !== null) {
      authStore.dispose();
    }
    if (settings !== null) {
      settings.setThemeModeListener(null);
      try {
        await settings.flush();
      } catch (error) {
        this.logCleanupFailure('settings', error as Object);
      }
    }
    if (playerSessionStore !== null) {
      try {
        await playerSessionStore.dispose();
      } catch (error) {
        this.logCleanupFailure('player session', error as Object);
      }
    }
    if (libraryModel !== null) {
      try {
        await libraryModel.flush();
      } catch (error) {
        this.logCleanupFailure('library', error as Object);
      }
    }
    if (images !== null) {
      try {
        await images.shutdown();
      } catch (error) {
        this.logCleanupFailure('images', error as Object);
      }
    }
    if (player !== null) {
      try {
        await player.shutdown();
      } catch (error) {
        this.logCleanupFailure('player', error as Object);
      }
    }
    if (lyrics !== null) {
      try {
        await lyrics.shutdown();
      } catch (error) {
        this.logCleanupFailure('lyrics', error as Object);
      }
    }
    if (library !== null) {
      try {
        await library.flush();
      } catch (error) {
        this.logCleanupFailure('library', error as Object);
      }
    }
  }

  private async ensureReady(): Promise<NativeAppServices> {
    const snapshot = await this.initialize();
    if (snapshot.state !== 'ready' || this.services === null) {
      if (snapshot.error !== null) {
        throw new NativeError(snapshot.error.code, snapshot.error.message, snapshot.error.retryable);
      }
      throw new NativeError('app.notReady', `Native runtime is ${snapshot.state}.`, true);
    }
    return this.services;
  }

  private addWarning(message: string, error: Object): void {
    const warning = toAppError(error);
    this.warnings.push(warning);
    hilog.warn(DOMAIN, TAG, '%{public}s code=%{public}s', message, warning.code);
  }

  private logCleanupFailure(service: string, error: Object): void {
    const appError = toAppError(error);
    hilog.warn(DOMAIN, TAG, '%{public}s shutdown failed code=%{public}s', service, appError.code);
  }
}
