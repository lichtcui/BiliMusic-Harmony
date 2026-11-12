import { curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NativeAppRuntime, NativeRuntimeSnapshot } from '../app/NativeAppRuntime';
import { BottomDock } from '../components/native/BottomDock';
import { BottomSheet } from '../components/native/BottomSheet';
import { CacheSheet } from '../components/native/CacheSheet';
import { CollectionDetailPage } from '../components/native/CollectionDetailPage';
import { DiagnosticsPage } from '../components/native/DiagnosticsPage';
import { DownloadsPage } from '../components/native/DownloadsPage';
import { FavoritesPage } from '../components/native/FavoritesPage';
import { LegalNoticeSheet } from '../components/native/LegalNoticeSheet';
import { LoginPage } from '../components/native/LoginPage';
import { LyricsCandidateSheet } from '../components/native/LyricsCandidateSheet';
import { LyricsPanelState } from '../components/native/LyricsPanelState';
import { closeLoginSheetSession } from '../components/native/LoginPageState';
import { MinePage } from '../components/native/MinePage';
import { NativeUiIds } from '../components/native/NativeUiIds';
import { OverlayAnimator, OverlayMotion } from '../components/native/OverlayMotion';
import { PlaybackSettingsSheet } from '../components/native/PlaybackSettingsSheet';
import { PlaylistCreateSheet } from '../components/native/PlaylistCreateSheet';
import { PlaylistDetailPage } from '../components/native/PlaylistDetailPage';
import { PlaylistEditSheet } from '../components/native/PlaylistEditSheet';
import { PlayerControlPanel } from '../components/native/PlayerControlPanel';
import { PlayerLyricsSheet } from '../components/native/PlayerLyricsSheet';
import { PlayerPage } from '../components/native/PlayerPage';
import { PrimaryPlaceholder } from '../components/native/PrimaryPlaceholder';
import { QueuePage } from '../components/native/QueuePage';
import { RecentPlaybackPage } from '../components/native/RecentPlaybackPage';
import { RoutePlaceholder } from '../components/native/RoutePlaceholder';
import { SearchPage } from '../components/native/SearchPage';
import { SettingsPage } from '../components/native/SettingsPage';
import { SheetSize } from '../components/native/SheetSizing';
import { SleepTimerSheet } from '../components/native/SleepTimerSheet';
import { TrackActionSheet } from '../components/native/TrackActionSheet';
import { AudioQualitySheet, QualitySheetTarget } from '../components/native/AudioQualitySheet';
import { AuthStore } from '../state/AuthStore';
import { CacheManagementStore } from '../state/CacheManagementStore';
import { DownloadStore } from '../state/DownloadStore';
import { FavoritesStore } from '../state/FavoritesStore';
import { LibraryStoreModel } from '../state/LibraryStoreModel';
import { LyricsStore } from '../state/LyricsStore';
import { PlaylistStore } from '../state/PlaylistStore';
import { PlayerStore } from '../state/PlayerStore';
import { RecentPlaybackStore } from '../state/RecentPlaybackStore';
import { SearchStore } from '../state/SearchStore';
import { SettingsStore } from '../state/SettingsStore';
import { SleepTimerStore } from '../state/SleepTimerStore';
import { TrackActionStore } from '../state/TrackActionStore';
import {
  clampTabIndex,
  INDEX_DISCOVER_TAB,
  INDEX_ROOT_TAB,
  IndexBackAction,
  IndexBackContext,
  resolveIndexBackAction
} from './IndexBackNavigation';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../theme/NativeTheme';
import { AudioQuality, MobileTrack } from '../types/MobileTypes';

const ROUTE_PLAYER = 'player';
const ROUTE_QUEUE = 'queue';
const ROUTE_PLAYLIST = 'playlist';
const ROUTE_FAVORITES = 'favorites';
const ROUTE_HISTORY = 'history';
const ROUTE_DOWNLOADS = 'downloads';
const ROUTE_COLLECTION = 'collection';

const DOMAIN = 0x424D;
const TAG = 'WispMusicHarmonyOS';

/**
 * 启动页先只显示 logo，超过这个时长仍未初始化完成才补一个转圈。
 * 快速冷启动通常 300ms 内就绪，避免多出一帧「加载中」的观感。
 */
const STARTUP_SPINNER_DELAY_MS: number = 500;

/** 07 设置整页：稿件 320ms cubic-bezier(.32, .72, 0, 1) 右侧滑入 / 反向滑出。 */
const SETTINGS_PAGE_ANIMATION_DURATION: number = 320;
const SETTINGS_PAGE_CURVE_X1: number = 0.32;
const SETTINGS_PAGE_CURVE_Y1: number = 0.72;
const SETTINGS_PAGE_CURVE_X2: number = 0;
const SETTINGS_PAGE_CURVE_Y2: number = 1;

/**
 * 所有底部抽屉共用一套进出场：340ms cubic-bezier(.32, .72, 0, 1)，面板自下而上滑入、
 * 反向滑出，蒙层同步淡入淡出。登录、诊断、曲目操作、歌词换源都走这一档，
 * 新增抽屉直接复用，不要再各写一份时长/曲线。
 * （播放页「功能键」2026-11 起改为右侧整页，走下面的设置页曲线。）
 */
const SHEET_ANIMATION_DURATION: number = 340;
const SHEET_CURVE_X1: number = 0.32;
const SHEET_CURVE_Y1: number = 0.72;
const SHEET_CURVE_X2: number = 0;
const SHEET_CURVE_Y2: number = 1;
/** 歌词面板展开 / 收起：design/lyrics-page.html 的 .42s。 */
const LYRICS_SHEET_ANIMATION_DURATION: number = 420;

/** 曲目操作结果 toast：浮在 dock（56 高 + 20 底距）上方，避免压住列表和底栏。 */
const TRACK_ACTION_TOAST_BOTTOM: number = 120;
const TRACK_ACTION_TOAST_DURATION: number = 1800;
const TRACK_ACTION_TOAST_FADE_IN_DURATION: number = 160;
const TRACK_ACTION_TOAST_FADE_OUT_DURATION: number = 180;
const TRACK_ACTION_TOAST_MAX_WIDTH: number = 320;

enum StartupViewState {
  Loading = 0,
  Ready = 1,
  Error = 2
}

@Entry
@Component
struct Index {
  private pathStack: NavPathStack = new NavPathStack();
  private tabsController: TabsController = new TabsController();
  private runtime: NativeAppRuntime | null = null;
  private startupGeneration: number = 0;
  private startupInFlight: boolean = false;
  @StorageProp('startupSafeTopPx') private startupSafeTopPx: number = 0;
  @StorageProp('startupSafeBottomPx') private startupSafeBottomPx: number = 0;
  @State private startupState: StartupViewState = StartupViewState.Loading;
  @State private startupErrorCode: string = '';
  /** 启动页的转圈：延迟出现，快速冷启动时用户只看到 logo。 */
  @State private startupSpinnerVisible: boolean = false;
  private startupSpinnerTimer: number = -1;
  @State private showStartupDiagnostics: boolean = false;
  /**
   * 当前一级页签。初值必须是「我的」：`Tabs` 首次只构建当前页签，默认落在「发现」
   * 会让首屏直接触发发现页的数据拉取；改成「我的」后拉取推迟到用户主动切过去。
   */
  @State private selectedTab: number = INDEX_ROOT_TAB;
  /**
   * 播放页「功能键」整页：Stack 覆盖层（不是路由），与设置整页同一层。
   * 不能挂在 `PlayerPage`（NavDestination）内部——那里是被安全区裁切的页面层，
   * 整页覆盖会漏掉状态栏 / 导航条。
   * 水平位移：挂载前等于窗口宽度（屏外），`onAppear` 后滑入；关闭时滑出再卸载。
   */
  @State private playerPanelMotion: OverlayMotion = new OverlayMotion();
  /**
   * 「定时关闭」抽屉：从播放控制功能页弹出，叠在功能整页之上。
   * 计时器由本页持有，关闭抽屉 / 退出功能页都不影响；到点只暂停播放。
   */
  @State private sleepTimerMotion: OverlayMotion = new OverlayMotion();
  /**
   * 「播放设置」抽屉：从设置页「常规 › 播放设置」入口弹出，叠在设置页之上。
   * 播放音质 / 自动播放 / 歌词显示都在这里维护；与缓存 / 诊断 / 免责声明同一层，
   * 打开其中一个时会收起其它抽屉。
   */
  @State private playbackSheetMotion: OverlayMotion = new OverlayMotion();
  /**
   * 「音质选择」抽屉：播放控制功能页的音质格入口。
   * 挂载在设置页之后；返回时优先关闭。
   */
  @State private audioQualityMotion: OverlayMotion = new OverlayMotion();
  /** 音质抽屉当前目标：播放控制页写 audioQuality；保留 download 目标给共用组件。 */
  @State private qualitySheetTarget: QualitySheetTarget = 'playback';
  /** 08 登录抽屉：Stack 覆盖层（不是路由），由返回契约优先关闭。 */
  @State private loginSheetMotion: OverlayMotion = new OverlayMotion();
  /** 07 设置整页：Stack 覆盖层（阶段 3 从临时路由改成覆盖层，2026-11 从底部抽屉改成整页右滑）。 */
  @State private settingsMotion: OverlayMotion = new OverlayMotion();
  /**
   * 诊断信息抽屉：从设置页「打开诊断信息」自下而上弹出，盖在设置页之上。
   * 2026-11 之前是右侧滑入的整页路由（会先关设置、露出「我的」页），改成抽屉后
   * 设置页保持在原地，返回时只关抽屉。
   */
  @State private diagnosticsMotion: OverlayMotion = new OverlayMotion();
  /**
   * 缓存清理抽屉：从设置页「缓存清理」行弹出，叠在设置页之上。
   * 与诊断抽屉同一层、同一套宿主驱动的进出场；两个入口都在设置页，且互相打开时会
   * 立刻收起另一个（见 `openCacheSheet` / `openDiagnosticsSheet`），不会叠两层抽屉。
   */
  @State private cacheSheetMotion: OverlayMotion = new OverlayMotion();
  /**
   * 法律与免责声明抽屉：从设置页「关于」组打开，叠在设置页之上。
   * 与缓存 / 诊断抽屉同一层、同一套宿主驱动的进出场；三个入口都在设置页，
   * 互相打开时会立刻收起另外两个（见 `openLegalSheet`），不会叠多层抽屉。
   */
  @State private legalSheetMotion: OverlayMotion = new OverlayMotion();
  /** 根 Stack 实测宽度，作为设置页 / 播放控制整页滑入、滑出的位移量（窄窗口 / 折叠屏不写死屏宽）。 */
  @State private settingsViewportWidth: number = 0;
  /** 根 Stack 实测高度，作为底部抽屉的滑入、滑出位移量。 */
  @State private shellViewportHeight: number = 0;
  @State private favoritesStore: FavoritesStore | null = null;
  @State private recentStore: RecentPlaybackStore | null = null;
  @State private downloadStore: DownloadStore | null = null;
  @State private libraryModel: LibraryStoreModel | null = null;
  @State private playlistStore: PlaylistStore | null = null;
  @State private searchStore: SearchStore | null = null;
  @State private playerStore: PlayerStore | null = null;
  @State private sleepTimerStore: SleepTimerStore | null = null;
  @State private lyricsStore: LyricsStore | null = null;
  @State private settingsStore: SettingsStore | null = null;
  @State private authStore: AuthStore | null = null;
  @State private cacheManagementStore: CacheManagementStore | null = null;
  @State private trackActionStore: TrackActionStore | null = null;
  /**
   * 歌词面板的视图模型：Index 持有，播放页通过 `sharedPanelState` 借用。
   * 面板本身也挂在根 Stack 上（`PlayerLyricsSheet`），换源弹层（`LyricsCandidateSheet`）
   * 因此能和它共用同一份数据，并盖住状态栏 / 导航条——`NavDestination` 会裁掉安全区。
   * 生命周期：每次打开播放页路由新建一份，播放页卸载时 dispose（见 `PlayerPage`）。
   */
  @State private lyricsPanelState: LyricsPanelState | null = null;
  /** design/lyrics-page.html 的歌词面板：挂在根 Stack，视觉上从屏幕顶部盖到进度条上方。 */
  @State private playerLyricsSheetVisible: boolean = false;
  /** 面板展开进度（0–1）：0 完全收起，1 完全展开；进出场由宿主动画。 */
  @State private playerLyricsSheetReveal: number = 0;
  private playerLyricsSheetTransitionToken: number = 0;
  /** 歌词换源弹层的位移 / 蒙层：与其它抽屉同一套宿主驱动（挂载前屏外，onAppear 滑入）。 */
  @State private lyricsCandidatesOffset: number = 0;
  @State private lyricsCandidatesScrimAlpha: number = 1;
  private lyricsCandidatesTransitionToken: number = 0;
  /** 曲目操作弹层的位移 / 蒙层：同上；关闭时滑出动画结束后才关 store（卸载）。 */
  @State private trackActionMotion: OverlayMotion = new OverlayMotion();
  /**
   * 曲目动作结果 toast：动作结束后抽屉通常还在滑出，先缓存到关闭动画结束、
   * store.close() 之后再现，避免提示压在下滑中的面板上。
   */
  private trackActionClosing: boolean = false;
  private hasPendingTrackActionToast: boolean = false;
  private pendingTrackActionToast: ResourceStr = '';
  /**
   * 宿主级 toast 本体。走根 Stack 内的自绘层而不是系统 `showToast`：
   * 系统 toast 在这个页面没有稳定显示，自绘层还能跟随主题、参与截图 / 布局取证。
   */
  @State private trackActionToastVisible: boolean = false;
  @State private trackActionToastMessage: ResourceStr = '';
  @State private trackActionToastOpacity: number = 0;
  @State private trackActionToastTranslateY: number = 12;
  private trackActionToastSequence: number = 0;
  private trackActionToastTimer: number = -1;
  /** 「新建歌单」抽屉：从「我的」页 + 号打开，挂在根 Stack 上以盖住整窗安全区。 */
  @State private playlistCreateMotion: OverlayMotion = new OverlayMotion();
  /**
   * 「修改歌单信息」抽屉：歌单详情页右上角打开。
   * 与新建歌单同样挂在根 Stack（`NavDestination` 会裁掉 `BottomSheet` 的安全区扩展）。
   */
  @State private playlistEditMotion: OverlayMotion = new OverlayMotion();
  @State private playlistEditId: string = '';

  aboutToAppear(): void {
    this.runtime = AppStorage.get<NativeAppRuntime>('nativeAppRuntime') ?? null;
    if (this.runtime === null) {
      this.showStartupError('app.runtimeUnavailable');
      return;
    }
    void this.runStartup(false);
  }

  onBackPress(): boolean {
    return this.handlePageBack();
  }

  /** 首帧上屏的取证锚点：与 EntryAbility 的 created 日志一起量冷启动时延。 */
  onPageShow(): void {
    hilog.info(DOMAIN, TAG, 'Index page shown');
  }

  aboutToDisappear(): void {
    this.startupGeneration += 1;
    this.startupInFlight = false;
    this.clearStartupSpinner();
    this.clearTrackActionToastTimer();
    // 销毁期不能同步 dispose，也不能写 @State（否则真机 140110）：
    // 延到下一拍只断开 store 的监听，页面此时已不可达，不再置空 @State。
    const searchStore = this.searchStore;
    const playlistStore = this.playlistStore;
    const trackActionStore = this.trackActionStore;
    const sleepTimerStore = this.sleepTimerStore;
    setTimeout((): void => {
      searchStore?.dispose();
      playlistStore?.dispose();
      trackActionStore?.dispose();
      sleepTimerStore?.dispose();
    }, 0);
  }

  @Builder
  routeBuilder(name: string, param: Object) {
    if (name === ROUTE_PLAYER) {
      NavDestination() {
        if (this.playerStore !== null && this.settingsStore !== null) {
          PlayerPage({
            store: this.playerStore,
            libraryModel: this.libraryModel,
            runtime: this.runtime,
            onOpenPlayerPanel: (): void => {
              this.openPlayerPanel();
            },
            onOpenDiscover: (): void => {
              this.openTab(INDEX_DISCOVER_TAB);
            },
            onOpenLibrary: (): void => {
              this.openTab(INDEX_ROOT_TAB);
            },
            onOpenLyrics: (): void => {
              this.openPlayerLyricsSheet();
            },
            settingsStore: this.settingsStore,
            lyricsStore: this.lyricsStore,
            sharedPanelState: this.lyricsPanelState
          })
        } else {
          RoutePlaceholder({
            message: $r('app.string.route_player_empty'),
            hint: $r('app.string.route_player_hint')
          })
        }
      }
      .hideTitleBar(true)
      // 路由页自身也要铺满整窗（含状态栏/底部手势条的安全区），否则系统默认白底会从
      // NavDestination 背后透出来，形成上下白条。播放页画布是独立的近白色。
      .backgroundColor(ThemeColors.playerCanvas)
      .onBackPressed(() => this.handleRouteBack())
    } else if (name === ROUTE_QUEUE) {
      NavDestination() {
        if (this.playerStore !== null) {
          QueuePage({
            store: this.playerStore,
            onBrowseSearch: (): void => {
              this.pathStack.pop();
              this.openDiscoverTab();
            },
            onClose: (): void => {
              this.pathStack.pop();
            },
            onOpenTrackActions: (track: MobileTrack): void => {
              this.openTrackActions(track);
            },
            onOpenPlayer: (): void => {
              this.pathStack.pop();
            }
          })
        } else {
          RoutePlaceholder({
            message: $r('app.string.route_queue_empty'),
            hint: $r('app.string.route_queue_hint')
          })
        }
      }
      .title($r('app.string.route_queue_title'), { backgroundColor: ThemeColors.surface })
      .backgroundColor(ThemeColors.bg)
      .onBackPressed(() => this.handleRouteBack())
    } else if (name === ROUTE_PLAYLIST) {
      NavDestination() {
        if (this.libraryModel !== null && this.playerStore !== null && this.favoritesStore !== null) {
          PlaylistDetailPage({
            libraryModel: this.libraryModel,
            playerStore: this.playerStore,
            favoritesStore: this.favoritesStore,
            runtime: this.runtime,
            playlistId: routePlaylistId(param),
            onClose: (): void => {
              this.pathStack.pop();
            },
            onOpenTrackActions: (track: MobileTrack): void => {
              this.openTrackActions(track);
            },
            onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string): void => {
              this.openTracksActions(tracks, contextTitle);
            },
            onOpenPlayer: (): void => {
              this.openPlayerRoute();
            },
            onEditPlaylist: (): void => {
              this.openPlaylistEditSheet(routePlaylistId(param));
            }
          })
        } else {
          RoutePlaceholder({
            message: $r('app.string.route_playlist_empty'),
            hint: $r('app.string.route_playlist_hint')
          })
        }
      }
      // 顶栏是页面自绘的（返回 / 歌单 / 更多），隐藏系统标题栏；系统 Back 仍由 onBackPressed 接管。
      .hideTitleBar(true)
      .backgroundColor(ThemeColors.bg)
      .onBackPressed(() => this.handleRouteBack())
    } else if (name === ROUTE_FAVORITES) {
      NavDestination() {
        if (this.favoritesStore !== null) {
          FavoritesPage({
            store: this.favoritesStore,
            onClose: (): void => {
              this.pathStack.pop();
            },
            onBrowseSearch: (): void => {
              this.pathStack.pop();
              this.openDiscoverTab();
            },
            onOpenTrackActions: (track: MobileTrack): void => {
              this.openTrackActions(track);
            },
            onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string): void => {
              this.openTracksActions(tracks, contextTitle);
            },
            onOpenPlayer: (): void => {
              this.openPlayerRoute();
            }
          })
        } else {
          RoutePlaceholder({
            message: $r('app.string.favorite_empty_title'),
            hint: $r('app.string.favorite_empty_description')
          })
        }
      }
      // 页头由页面自绘（返回 +「我喜欢的」），隐藏系统标题栏；系统 Back 仍由 onBackPressed 接管。
      .hideTitleBar(true)
      .backgroundColor(ThemeColors.bg)
      .onBackPressed(() => this.handleRouteBack())
    } else if (name === ROUTE_HISTORY) {
      NavDestination() {
        if (this.recentStore !== null && this.favoritesStore !== null) {
          RecentPlaybackPage({
            store: this.recentStore,
            favoritesStore: this.favoritesStore,
            onClose: (): void => {
              this.pathStack.pop();
            },
            onOpenTrackActions: (track: MobileTrack): void => {
              this.openTrackActions(track);
            },
            onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string): void => {
              this.openTracksActions(tracks, contextTitle);
            },
            onOpenPlayer: (): void => {
              this.openPlayerRoute();
            }
          })
        } else {
          RoutePlaceholder({
            message: $r('app.string.recent_empty_title'),
            hint: $r('app.string.recent_empty_description')
          })
        }
      }
      // 页头由页面自绘（返回 +「历史」），隐藏系统标题栏；系统 Back 仍由 onBackPressed 接管。
      .hideTitleBar(true)
      .backgroundColor(ThemeColors.bg)
      .onBackPressed(() => this.handleRouteBack())
    } else if (name === ROUTE_DOWNLOADS) {
      NavDestination() {
        if (this.downloadStore !== null && this.favoritesStore !== null) {
          DownloadsPage({
            store: this.downloadStore,
            favoritesStore: this.favoritesStore,
            onClose: (): void => {
              this.pathStack.pop();
            },
            onOpenTrackActions: (track: MobileTrack): void => {
              this.openTrackActions(track);
            },
            onOpenPlayer: (): void => {
              this.openPlayerRoute();
            }
          })
        } else {
          RoutePlaceholder({
            message: $r('app.string.mine_downloads_empty_title'),
            hint: $r('app.string.mine_downloads_empty_description')
          })
        }
      }
      // 页头由页面自绘（返回 +「下载」），隐藏系统标题栏；系统 Back 仍由 onBackPressed 接管。
      .hideTitleBar(true)
      .backgroundColor(ThemeColors.bg)
      .onBackPressed(() => this.handleRouteBack())
    } else if (name === ROUTE_COLLECTION) {
      NavDestination() {
        if (this.runtime !== null && this.playerStore !== null && this.favoritesStore !== null) {
          CollectionDetailPage({
            runtime: this.runtime,
            playerStore: this.playerStore,
            favoritesStore: this.favoritesStore,
            bvid: routeCollectionBvid(param),
            onClose: (): void => {
              this.pathStack.pop();
            },
            onOpenTrackActions: (track: MobileTrack): void => {
              this.openTrackActions(track);
            },
            onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string): void => {
              this.openTracksActions(tracks, contextTitle);
            },
            onOpenPlayer: (): void => {
              this.openPlayerRoute();
            }
          })
        } else {
          RoutePlaceholder({
            message: $r('app.string.collection_detail_unavailable_title'),
            hint: $r('app.string.collection_detail_unavailable_message')
          })
        }
      }
      // 合集详情同样是自绘顶栏（返回 + Hero），隐藏系统标题栏。
      .hideTitleBar(true)
      .backgroundColor(ThemeColors.bg)
      .onBackPressed(() => this.handleRouteBack())
    }
  }

  @Builder
  StartupDiagnosticsButton(id: string) {
    Button($r('app.string.diagnostics_open'), { stateEffect: false })
      .id(id)
      .width(160)
      .height(ThemeSize.routeButtonHeight)
      .fontSize(ThemeTypography.body)
      .fontColor(ThemeColors.textPrimary)
      .backgroundColor(ThemeColors.surfaceInset)
      .borderRadius(ThemeRadius.md)
      .onClick(() => {
        this.showStartupDiagnostics = true;
      })
  }

  /** 系统启动窗口按整屏居中；页面内容区被安全区内缩，偏移量按上下 insets 动态算。 */
  private startupLogoOffsetY(): number {
    return -(px2vp(this.startupSafeTopPx) - px2vp(this.startupSafeBottomPx)) / 2;
  }

  /**
   * 启动页：与系统启动窗口同一张底（`start_window_background`）和同一个 `app_icon`。
   * 系统启动页撤下、本页接手时视觉不变，只是从「系统静态图标」变成「App 内的同一张图」。
   * logo 长按可打开诊断信息——启动卡住时仍保留一条排查入口，但正常启动不显示任何文案。
   */
  @Builder
  StartupLoading() {
    Column() {
      // 用 Stack 让转圈叠在图标下方，而不是参与 Column 居中；否则转圈出现时图标会被顶上去。
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.app_icon'))
          .width(ThemeSize.startupLogo)
          .height(ThemeSize.startupLogo)
          .borderRadius(ThemeSize.startupLogoRadius)
          .clip(true)
          .objectFit(ImageFit.Cover)
          .accessibilityText($r('app.string.startup_loading_title'))
          .gesture(LongPressGesture().onAction((): void => {
            this.showStartupDiagnostics = true;
          }))
        if (this.startupSpinnerVisible) {
          LoadingProgress()
            .width(ThemeSize.loadingIndicator)
            .height(ThemeSize.loadingIndicator)
            .color(ThemeColors.onSplash)
            .offset({ y: ThemeSize.startupSpinnerOffsetY })
        }
      }
      .width('100%')
      .height(ThemeSize.startupSpinnerAreaHeight)
      // 页面内容区被状态栏 / 导航条内缩，居中点比系统启动窗口低约 5vp；上移对齐。
      .offset({ y: this.startupLogoOffsetY() })
    }
    .id('startup-loading')
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(ThemeColors.startWindowBackground)
    // 与系统启动窗口一致，深色底要盖住状态栏 / 导航条，不能上下露白。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  StartupError() {
    Column({ space: ThemeSpacing.lg }) {
      Text($r('app.string.startup_error_title'))
        .fontSize(ThemeTypography.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
      Text($r('app.string.startup_error_description'))
        .fontSize(ThemeTypography.body)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
      Row({ space: ThemeSpacing.sm }) {
        Text($r('app.string.startup_error_code_label'))
          .fontSize(ThemeTypography.caption)
          .fontColor(ThemeColors.textSecondary)
        Text(this.startupErrorCode)
          .id('startup-error-code')
          .fontSize(ThemeTypography.caption)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Button($r('app.string.startup_retry'), { stateEffect: false })
        .id('startup-retry')
        .width(160)
        .height(ThemeSize.routeButtonHeight)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.onAccent)
        .backgroundColor(ThemeColors.accent)
        .borderRadius(ThemeRadius.md)
        .onClick(() => {
          void this.runStartup(true);
        })
      this.StartupDiagnosticsButton('startup-error-diagnostics')
    }
    .id('startup-error')
    .width('100%')
    .height('100%')
    .padding(ThemeSpacing.xxl)
    .justifyContent(FlexAlign.Center)
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }

  @Builder
  DockReserve(id: string) {
    Row()
      .id(id)
      .width('100%')
      .height(ThemeSize.dockReserve)
      .backgroundColor(ThemeColors.bg)
  }

  @Builder
  MainNavigation() {
    Navigation(this.pathStack) {
      Column() {
        Stack({ alignContent: Alignment.Bottom }) {
          Tabs({
            barPosition: BarPosition.End,
            index: this.selectedTab,
            controller: this.tabsController
          }) {
            TabContent() {
              Column() {
                Column() {
                  if (this.searchStore !== null && this.playerStore !== null) {
                    SearchPage({
                      store: this.searchStore,
                      playerStore: this.playerStore,
                      runtime: this.runtime,
                      onMoreClick: (track: MobileTrack): void => {
                        this.openTrackActions(track);
                      },
                      onOpenPlayer: (): void => {
                        this.openPlayerRoute();
                      },
                      onOpenCollection: (track: MobileTrack): void => {
                        this.openCollectionRoute(track.bvid);
                      }
                    })
                  } else {
                    PrimaryPlaceholder({
                      eyebrow: $r('app.string.search_eyebrow'),
                      title: $r('app.string.search_empty_title'),
                      description: $r('app.string.search_empty_description')
                    })
                  }
                }
                .width('100%')
                .layoutWeight(1)

                this.DockReserve('search-dock-reserve')
              }
              .width('100%')
              .height('100%')
            }
            .id(NativeUiIds.discoverTabContent)

            TabContent() {
              Column() {
                Column() {
                  if (this.authStore !== null && this.playlistStore !== null &&
                    this.favoritesStore !== null && this.playerStore !== null &&
                    this.recentStore !== null && this.downloadStore !== null) {
                    MinePage({
                      authStore: this.authStore,
                      playlistStore: this.playlistStore,
                      favoritesStore: this.favoritesStore,
                      playerStore: this.playerStore,
                      recentStore: this.recentStore,
                      downloadStore: this.downloadStore,
                      runtime: this.runtime,
                      onOpenSettings: (): void => {
                        this.openSettings();
                      },
                      onOpenLogin: (): void => {
                        this.openLoginSheet();
                      },
                      onOpenLiked: (): void => {
                        this.pathStack.pushPath({ name: ROUTE_FAVORITES });
                      },
                      onOpenHistory: (): void => {
                        this.pathStack.pushPath({ name: ROUTE_HISTORY });
                      },
                      onOpenDownloads: (): void => {
                        this.pathStack.pushPath({ name: ROUTE_DOWNLOADS });
                      },
                      onCreatePlaylist: (): void => {
                        this.openPlaylistCreateSheet();
                      },
                      onOpenPlaylist: (playlistId: string): void => {
                        this.pathStack.pushPath({
                          name: ROUTE_PLAYLIST,
                          param: playlistId
                        });
                      },
                      onPlaylistDeleted: (playlistId: string): void => {
                        this.removePlaylistRoutes(playlistId);
                      }
                    })
                  } else {
                    PrimaryPlaceholder({
                      eyebrow: $r('app.string.library_eyebrow'),
                      title: $r('app.string.library_empty_title'),
                      description: $r('app.string.library_empty_description')
                    })
                  }
                }
                .width('100%')
                .layoutWeight(1)

                this.DockReserve('library-dock-reserve')
              }
              .width('100%')
              .height('100%')
            }
            .id(NativeUiIds.libraryTabContent)
          }
          .barMode(BarMode.Fixed)
          /* 新设计不再有底栏：一级切换由悬浮 dock 的单按钮导航胶囊承担。 */
          .barHeight(0)
          /* 禁用左右滑动切页签：横向手势留给页面内的业务手势，一级切换只走 dock。 */
          .scrollable(false)
          .barBackgroundColor(ThemeColors.bg)
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeColors.bg)
          .onChange((index: number): void => {
            this.selectedTab = clampTabIndex(index);
          })

          if (this.playerStore !== null) {
            BottomDock({
              playerStore: this.playerStore,
              selectedTab: this.selectedTab,
              runtime: this.runtime,
              onSwitchTab: (index: number): void => {
                this.selectedTab = clampTabIndex(index);
                this.tabsController.changeIndex(this.selectedTab);
              },
              onExpandPlayer: (): void => {
                this.openPlayerRoute();
              }
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(ThemeColors.bg)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeColors.bg)
    }
    .id(NativeUiIds.shellRoot)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.routeBuilder)
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bg)
  }

  build() {
    Stack() {
      if (this.showStartupDiagnostics) {
        DiagnosticsPage({
          runtime: this.runtime,
          onClose: (): void => {
            this.showStartupDiagnostics = false;
          }
        })
      } else if (this.startupState === StartupViewState.Loading) {
        this.StartupLoading()
      } else if (this.startupState === StartupViewState.Error) {
        this.StartupError()
      } else {
        this.MainNavigation()
      }

      if (this.trackActionStore !== null && this.trackActionStore.isOpen()) {
        // 包裹层只为拿 `onAppear`：挂载瞬间面板在屏外，下一帧由宿主动画滑入。
        Stack() {
          TrackActionSheet({
            store: this.trackActionStore,
            runtime: this.runtime,
            panelOffsetY: this.trackActionMotion.offset,
            scrimAlpha: this.trackActionMotion.scrimAlpha,
            onClose: (): void => {
              this.closeTrackActions();
            },
            onToast: (message: ResourceStr): void => {
              this.showTrackActionToast(message);
            },
            onDownload: (tracks: MobileTrack[]): void => {
              this.downloadTracks(tracks);
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playTrackActionEnter();
        })
      }

      // 「新建歌单」抽屉：+ 号入口，和登录 / 曲目操作抽屉一样挂在根 Stack 上，
      // 这样蒙层、面板底和安全区都能铺满整窗。
      if (this.playlistCreateMotion.visible && this.playlistStore !== null) {
        Stack() {
          PlaylistCreateSheet({
            store: this.playlistStore,
            panelOffsetY: this.playlistCreateMotion.offset,
            scrimAlpha: this.playlistCreateMotion.scrimAlpha,
            onClose: (): void => {
              this.closePlaylistCreateSheet();
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playPlaylistCreateSheetEnter();
        })
      }

      // 「修改歌单信息」抽屉：歌单详情页右上角入口，同样挂在根 Stack 上。
      if (this.playlistEditMotion.visible && this.playlistStore !== null && this.playlistEditId.length > 0) {
        Stack() {
          PlaylistEditSheet({
            store: this.playlistStore,
            playlistId: this.playlistEditId,
            panelOffsetY: this.playlistEditMotion.offset,
            scrimAlpha: this.playlistEditMotion.scrimAlpha,
            onClose: (): void => {
              this.closePlaylistEditSheet();
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playPlaylistEditSheetEnter();
        })
      }

      // 歌词面板：从播放页的歌词预览打开，挂在根 Stack 上，底色一直铺到屏幕顶部，
      // 遮住标题 / 封面 / 操作行，但让出底部 158vp 给进度条与播放条。
      // 打开 / 收起只驱动 reveal，不切路由。
      if (this.playerLyricsSheetVisible && this.lyricsPanelState !== null) {
        Stack() {
          PlayerLyricsSheet({
            state: this.lyricsPanelState,
            reveal: this.playerLyricsSheetReveal,
            onClose: (): void => {
              this.closePlayerLyricsSheet();
            }
          })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .onAppear((): void => {
          this.playPlayerLyricsSheetEnter();
        })
      }

      // 歌词换源弹层：与曲目弹层同一层（根 Stack），叠在歌词面板之上。
      // `NavDestination` 会裁掉抽屉外壳的 expandSafeArea，因此不能挂在播放页内部。
      if (this.lyricsPanelState !== null && this.lyricsPanelState.candidatesOpen) {
        Stack() {
          LyricsCandidateSheet({
            state: this.lyricsPanelState,
            panelOffsetY: this.lyricsCandidatesOffset,
            scrimAlpha: this.lyricsCandidatesScrimAlpha,
            onClose: (): void => {
              this.closeLyricsCandidates();
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playLyricsCandidatesEnter();
        })
      }

      // 播放页「功能键」整页：与设置整页同一层，从右侧滑入 / 滑出。
      // 挂在 `PlayerPage` 里时会被 NavDestination 的页面层裁掉安全区，因此由根 Stack 承载。
      if (this.playerPanelMotion.visible && this.playerStore !== null && this.sleepTimerStore !== null &&
        this.settingsStore !== null && this.downloadStore !== null) {
        Stack() {
          PlayerControlPanel({
            store: this.playerStore,
            sleepTimerStore: this.sleepTimerStore,
            settingsStore: this.settingsStore,
            downloadStore: this.downloadStore,
            runtime: this.runtime,
            onClose: (): void => {
              this.closePlayerPanel();
            },
            onAddToPlaylist: (track: MobileTrack): void => {
              this.hidePlayerPanelImmediately();
              this.openTrackActions(track);
            },
            onDownload: (track: MobileTrack): void => {
              this.downloadTracks([track]);
            },
            onOpenSleepTimer: (): void => {
              this.openSleepTimerSheet();
            },
            onOpenAudioQuality: (): void => {
              this.openAudioQualitySheet('playback');
            }
          })
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.playerPanelMotion.offset })
        .onAppear((): void => {
          this.playPlayerPanelEnter();
        })
      }

      // 「定时关闭」抽屉：挂在播放控制功能整页之后，才能盖在整页之上。
      // 计时状态由 Index 持有，抽屉只是设置面；关闭抽屉不会取消定时。
      if (this.sleepTimerMotion.visible && this.sleepTimerStore !== null) {
        Stack() {
          SleepTimerSheet({
            timerStore: this.sleepTimerStore,
            panelOffsetY: this.sleepTimerMotion.offset,
            scrimAlpha: this.sleepTimerMotion.scrimAlpha,
            onClose: (): void => {
              this.closeSleepTimerSheet();
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playSleepTimerSheetEnter();
        })
      }

      // 08 登录抽屉：与曲目弹层同为 Stack 覆盖层，但挂在其后（视觉在上），
      // 因此返回契约里也先关它（见 IndexBackNavigation 的处置顺序）。
      // 位移 / 蒙层动画由本层驱动：挂载前放到屏外、onAppear 后滑入，关闭时动画结束再卸载。
      if (this.loginSheetMotion.visible && this.authStore !== null) {
        Stack() {
          LoginPage({
            authStore: this.authStore,
            sheetOffsetY: this.loginSheetMotion.offset,
            scrimAlpha: this.loginSheetMotion.scrimAlpha,
            onClose: (): void => {
              this.closeLoginSheet();
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playLoginSheetEnter();
        })
      }

      // 07 设置整页：同样是 Stack 覆盖层，后挂以盖住登录抽屉 / 曲目操作面板。
      // 无蒙层：整页底就是 `bg`，滑入时背后的页面不变暗、不缩放。
      // 位移挂在包裹层而不是页面本身，关闭时先滑出、动画结束再卸载（见 closeSettings）。
      if (this.settingsMotion.visible && this.settingsStore !== null &&
        this.cacheManagementStore !== null) {
        Stack() {
          SettingsPage({
            settingsStore: this.settingsStore,
            cacheStore: this.cacheManagementStore,
            onClose: (): void => {
              this.closeSettings();
            },
            onOpenDiagnostics: (): void => {
              this.openDiagnosticsSheet();
            },
            onOpenPlaybackSheet: (): void => {
              this.openPlaybackSheet();
            },
            onSelectDownloadQuality: (quality: AudioQuality): Promise<boolean> => {
              return this.selectDownloadQuality(quality);
            },
            onSelectDownloadLimit: (limit: number): Promise<boolean> => {
              return this.selectDownloadLimit(limit);
            },
            onOpenCacheSheet: (): void => {
              this.openCacheSheet();
            },
            onOpenLegalSheet: (): void => {
              this.openLegalSheet();
            }
          })
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.settingsMotion.offset })
        .onAppear((): void => {
          this.playSettingsEnter();
        })
      }

      // 「播放设置」抽屉：设置页「常规 › 播放设置」入口弹出，叠在设置整页之上；
      // 与缓存 / 诊断 / 免责声明同一层、同一套宿主驱动（挂载前屏外 + 蒙层透明，
      // onAppear 滑入；关闭动画结束再卸载）。
      if (this.playbackSheetMotion.visible && this.settingsStore !== null) {
        Stack() {
          PlaybackSettingsSheet({
            settingsStore: this.settingsStore,
            panelOffsetY: this.playbackSheetMotion.offset,
            scrimAlpha: this.playbackSheetMotion.scrimAlpha,
            onClose: (): void => {
              this.closePlaybackSheet();
            },
            onSelectAudioQuality: (quality: AudioQuality): Promise<boolean> => {
              return this.selectAudioQuality(quality);
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playPlaybackSheetEnter();
        })
      }

      // 「音质选择」抽屉：从播放控制功能页的音质格打开，挂在设置整页之后，
      // 因此叠在播放功能页之上；返回键先于设置页 / 播放功能页关闭。
      if (this.audioQualityMotion.visible && this.settingsStore !== null) {
        Stack() {
          AudioQualitySheet({
            settingsStore: this.settingsStore,
            target: this.qualitySheetTarget,
            panelOffsetY: this.audioQualityMotion.offset,
            scrimAlpha: this.audioQualityMotion.scrimAlpha,
            onClose: (): void => {
              this.closeAudioQualitySheet();
            },
            onSelect: (quality: AudioQuality): Promise<boolean> =>
              this.qualitySheetTarget === 'download' ?
                this.selectDownloadQuality(quality) :
                this.selectAudioQuality(quality)
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playAudioQualitySheetEnter();
        })
      }

      // 缓存清理抽屉：设置页「缓存清理」行弹出，叠在设置整页之上；与诊断抽屉同一层、
      // 同一套宿主驱动（挂载前屏外 + 蒙层透明，onAppear 滑入；关闭动画结束再卸载）。
      // 挂在根 Stack 而不是设置页内部：抽屉外壳的 expandSafeArea 需要铺到状态栏 / 导航条。
      if (this.cacheSheetMotion.visible && this.cacheManagementStore !== null) {
        Stack() {
          CacheSheet({
            cacheStore: this.cacheManagementStore,
            panelOffsetY: this.cacheSheetMotion.offset,
            scrimAlpha: this.cacheSheetMotion.scrimAlpha,
            onClose: (): void => {
              this.closeCacheSheet();
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playCacheSheetEnter();
        })
      }

      // 法律与免责声明抽屉：设置页「关于」组弹出，叠在设置整页之上；与缓存 / 诊断抽屉
      // 同一层、同一套宿主驱动。正文是一整段长文，走共用外壳的大档，满了在正文里滚。
      if (this.legalSheetMotion.visible) {
        Stack() {
          LegalNoticeSheet({
            panelOffsetY: this.legalSheetMotion.offset,
            scrimAlpha: this.legalSheetMotion.scrimAlpha,
            onClose: (): void => {
              this.closeLegalSheet();
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playLegalSheetEnter();
        })
      }

      // 诊断信息抽屉：挂在设置页之后（视觉在其上），自下而上的底部弹层，
      // 复用 08/03/09 的共用外壳 `BottomSheet`；关闭只收抽屉，设置页留在原地。
      // 位移 / 蒙层与登录抽屉同一套宿主驱动：挂载前放到屏外、onAppear 后滑入。
      if (this.diagnosticsMotion.visible) {
        Stack() {
          BottomSheet({
            sheetId: NativeUiIds.diagnosticsSheet,
            // 不传标题：抽屉外壳的头部整块收起，只剩拖拽条。
            // 诊断条目多，走共用外壳的大档（78%）；从头部上拉可展开到安全区下方。
            sheetSize: SheetSize.Large,
            panelOffsetY: this.diagnosticsMotion.offset,
            scrimAlpha: this.diagnosticsMotion.scrimAlpha,
            onClose: (): void => {
              this.closeDiagnosticsSheet();
            }
          }) {
            DiagnosticsPage({
              runtime: this.runtime,
              embedded: true,
              onClose: (): void => {
                this.closeDiagnosticsSheet();
              }
            })
          }
        }
        .width('100%')
        .height('100%')
        .onAppear((): void => {
          this.playDiagnosticsSheetEnter();
        })
      }

      // 曲目动作结果 toast：挂在根 Stack 最后一层，盖住抽屉 / 底栏；整层不吃触摸。
      if (this.trackActionToastVisible) {
        Column() {
          Text(this.trackActionToastMessage)
            .id(NativeUiIds.trackActionToast)
            .fontSize(ThemeTypography.caption)
            .fontColor(ThemeColors.onAccent)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({
              left: ThemeSpacing.lg,
              right: ThemeSpacing.lg,
              top: ThemeSpacing.sm,
              bottom: ThemeSpacing.sm
            })
            .constraintSize({ maxWidth: TRACK_ACTION_TOAST_MAX_WIDTH })
            .backgroundColor(ThemeColors.textPrimary)
            .borderRadius(ThemeRadius.xl)
            .opacity(this.trackActionToastOpacity)
            .translate({ y: this.trackActionToastTranslateY })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: TRACK_ACTION_TOAST_BOTTOM })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bg)
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      const width = newValue.width as number;
      if (Number.isFinite(width) && width > 0) {
        this.settingsViewportWidth = width;
      }
      const height = newValue.height as number;
      if (Number.isFinite(height) && height > 0) {
        this.shellViewportHeight = height;
      }
    })
  }

  private handlePageBack(): boolean {
    return this.dispatchBackAction(false);
  }

  private handleRouteBack(): boolean {
    // NavDestination 内不消费 PopRoute：让路由栈自己弹栈，覆盖层仍按同一顺序先关。
    return this.dispatchBackAction(true);
  }

  /**
   * 根页面与路由页共用同一套返回顺序（A7）：歌词浮层优先，其余覆盖层统一交给
   * `resolveIndexBackAction` 裁决，避免两处实现再次分叉。
   */
  private dispatchBackAction(fromRoute: boolean): boolean {
    // 歌词换源弹层 / 歌词面板挂在根 Stack 上，优先于路由与其它抽屉关闭。
    if (this.lyricsPanelState !== null && this.lyricsPanelState.candidatesOpen) {
      this.closeLyricsCandidates();
      return true;
    }
    if (this.playerLyricsSheetVisible) {
      this.closePlayerLyricsSheet();
      return true;
    }
    const action = resolveIndexBackAction(this.buildBackContext());
    if (action === IndexBackAction.CloseDiagnostics) {
      this.showStartupDiagnostics = false;
      this.closeDiagnosticsSheet();
      return true;
    }
    if (action === IndexBackAction.CloseCacheSheet) {
      this.closeCacheSheet();
      return true;
    }
    if (action === IndexBackAction.CloseLegalSheet) {
      this.closeLegalSheet();
      return true;
    }
    if (action === IndexBackAction.ClosePlaybackSheet) {
      this.closePlaybackSheet();
      return true;
    }
    if (action === IndexBackAction.CloseAudioQuality) {
      this.closeAudioQualitySheet();
      return true;
    }
    if (action === IndexBackAction.CloseSettingsPage) {
      this.closeSettings();
      return true;
    }
    if (action === IndexBackAction.CloseLoginSheet) {
      this.closeLoginSheet();
      return true;
    }
    if (action === IndexBackAction.CloseTrackActions) {
      this.closeTrackActions();
      return true;
    }
    if (action === IndexBackAction.ClosePlaylistCreate) {
      this.closePlaylistCreateSheet();
      return true;
    }
    if (action === IndexBackAction.ClosePlaylistEdit) {
      this.closePlaylistEditSheet();
      return true;
    }
    if (action === IndexBackAction.CloseSleepTimer) {
      this.closeSleepTimerSheet();
      return true;
    }
    if (action === IndexBackAction.ClosePlayerControlPanel) {
      this.closePlayerPanel();
      return true;
    }
    if (action === IndexBackAction.PopRoute) {
      if (fromRoute) {
        return false;
      }
      this.pathStack.pop();
      return true;
    }
    if (action === IndexBackAction.OpenRootTab) {
      this.openRootTab();
      return true;
    }
    return false;
  }

  private buildBackContext(): IndexBackContext {
    return {
      // 诊断覆盖层有两处：启动失败时的整页诊断，和设置页弹出的诊断抽屉。
      diagnosticsVisible: this.showStartupDiagnostics || this.diagnosticsMotion.visible,
      cacheSheetVisible: this.cacheSheetMotion.visible,
      legalSheetVisible: this.legalSheetMotion.visible,
      playbackSheetVisible: this.playbackSheetMotion.visible,
      audioQualitySheetVisible: this.audioQualityMotion.visible,
      settingsPageVisible: this.settingsMotion.visible,
      loginSheetVisible: this.loginSheetMotion.visible,
      trackActionsVisible: this.trackActionStore !== null && this.trackActionStore.isOpen(),
      playlistCreateVisible: this.playlistCreateMotion.visible,
      playlistEditVisible: this.playlistEditMotion.visible,
      sleepTimerSheetVisible: this.sleepTimerMotion.visible,
      playerControlPanelVisible: this.playerPanelMotion.visible,
      routeCount: this.pathStack.size(),
      selectedTab: this.selectedTab
    };
  }

  private scheduleStartupSpinner(): void {
    this.clearStartupSpinner();
    this.startupSpinnerVisible = false;
    this.startupSpinnerTimer = setTimeout((): void => {
      this.startupSpinnerTimer = -1;
      if (this.startupState === StartupViewState.Loading) {
        this.startupSpinnerVisible = true;
      }
    }, STARTUP_SPINNER_DELAY_MS);
  }

  private clearStartupSpinner(): void {
    if (this.startupSpinnerTimer !== -1) {
      clearTimeout(this.startupSpinnerTimer);
      this.startupSpinnerTimer = -1;
    }
  }

  private async runStartup(retry: boolean): Promise<void> {
    if (this.startupInFlight) {
      return;
    }
    const runtime = this.runtime;
    if (runtime === null) {
      this.showStartupError('app.runtimeUnavailable');
      return;
    }
    this.startupInFlight = true;
    this.startupState = StartupViewState.Loading;
    this.startupErrorCode = '';
    this.scheduleStartupSpinner();
    const generation = this.startupGeneration + 1;
    this.startupGeneration = generation;
    try {
      const snapshot = retry ? await runtime.retry() : await runtime.initialize();
      if (generation !== this.startupGeneration) {
        return;
      }
      if (snapshot.state === 'ready') {
        const recentStore = await runtime.recentPlaybackStore();
        const favoritesStore = await runtime.favoritesStore();
        const downloadStore = await runtime.downloadStore();
        const settingsStore = await runtime.settingsStore();
        const authStore = await runtime.authStore();
        const playerStore = await runtime.playerStore();
        const lyricsStore = await runtime.lyricsStore();
        const libraryModel = await runtime.libraryModel();
        const playlistStore = new PlaylistStore(libraryModel, playerStore);
        const trackActionStore = new TrackActionStore(libraryModel);
        if (generation !== this.startupGeneration) {
          playlistStore.dispose();
          trackActionStore.dispose();
          return;
        }
        this.recentStore = recentStore;
        this.recentStore?.attach();
        this.favoritesStore = favoritesStore;
        this.favoritesStore?.attach();
        this.downloadStore = downloadStore;
        this.downloadStore?.attach();
        this.libraryModel = libraryModel;
        this.playlistStore?.dispose();
        this.playlistStore = playlistStore;
        this.playlistStore?.attach();
        this.trackActionStore?.dispose();
        this.trackActionStore = trackActionStore;
        this.trackActionStore?.attach();
        this.searchStore = this.searchStore ?? new SearchStore(runtime);
        this.playerStore = playerStore;
        this.sleepTimerStore?.dispose();
        this.sleepTimerStore = new SleepTimerStore((): Promise<void> => playerStore.pause());
        this.lyricsStore = lyricsStore;
        this.lyricsStore?.attach();
        this.settingsStore = settingsStore;
        this.authStore = authStore;
        this.cacheManagementStore = this.cacheManagementStore ?? new CacheManagementStore(runtime);
      }
      this.applyStartupSnapshot(snapshot);
    } catch (error) {
      if (generation === this.startupGeneration) {
        this.showStartupError('app.initializeFailed');
      }
    } finally {
      if (generation === this.startupGeneration) {
        this.startupInFlight = false;
      }
    }
  }

  private applyStartupSnapshot(snapshot: NativeRuntimeSnapshot): void {
    if (snapshot.state === 'ready') {
      this.clearStartupSpinner();
      this.startupSpinnerVisible = false;
      this.startupState = StartupViewState.Ready;
      this.startupErrorCode = '';
      hilog.info(DOMAIN, TAG, 'startup ready');
      return;
    }
    const code = snapshot.error === null ? `app.${snapshot.state}` : snapshot.error.code;
    this.showStartupError(code);
  }

  private showStartupError(code: string): void {
    this.startupInFlight = false;
    this.clearStartupSpinner();
    this.startupSpinnerVisible = false;
    this.startupErrorCode = safeStartupErrorCode(code);
    this.startupState = StartupViewState.Error;
  }

  /** 回到根 tab（「我的」），不清路由栈；系统 Back 在非根 tab 上走这里。 */
  private openRootTab(): void {
    this.selectedTab = INDEX_ROOT_TAB;
    this.tabsController.changeIndex(INDEX_ROOT_TAB);
  }

  /** 切到「发现」页签，不清路由栈；由「去搜索 / 浏览搜索」空态入口共用。 */
  private openDiscoverTab(): void {
    this.selectedTab = INDEX_DISCOVER_TAB;
    this.tabsController.changeIndex(INDEX_DISCOVER_TAB);
  }

  /** Leaves the pushed routes and focuses one of the root tabs. */
  private openTab(index: number): void {
    const target = clampTabIndex(index);
    this.hidePlayerLyricsSheetImmediately();
    if (this.pathStack.size() > 0) {
      this.pathStack.clear();
    }
    this.selectedTab = target;
    this.tabsController.changeIndex(target);
  }

  /** 07 设置整页入口：先收曲目弹层，再刷新缓存统计，然后从右侧滑入。 */
  private openSettings(): void {
    this.hideTrackActionsImmediately();
    this.hideDiagnosticsSheetImmediately();
    this.hideCacheSheetImmediately();
    this.hideLegalSheetImmediately();
    this.hidePlaybackSheetImmediately();
    this.hideAudioQualitySheetImmediately();
    if (this.cacheManagementStore !== null) {
      void this.cacheManagementStore.refresh();
    }
    this.settingsMotion.open(this.pageHiddenOffset(), this.pageAnimator);
  }

  /** 设置页「打开诊断信息」：不关设置页，直接叠一层自下而上的诊断抽屉。 */
  private openDiagnosticsSheet(): void {
    // 诊断、缓存清理、免责声明、播放设置是同一层的抽屉，同一时刻只保留一个。
    this.hideCacheSheetImmediately();
    this.hideLegalSheetImmediately();
    this.hidePlaybackSheetImmediately();
    this.hideAudioQualitySheetImmediately();
    this.diagnosticsMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private closeDiagnosticsSheet(): void {
    this.diagnosticsMotion.close(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  /** 组件首次挂载后的滑入；由抽屉包裹层的 onAppear 触发。 */
  private playDiagnosticsSheetEnter(): void {
    this.diagnosticsMotion.enter(this.sheetAnimator);
  }

  /** 急停版：不播退场动画直接卸载（设置页滑出，或设置页被重新打开时用）。 */
  private hideDiagnosticsSheetImmediately(): void {
    this.diagnosticsMotion.hideNow();
  }

  /**
   * 设置页「缓存清理」：不关设置页，直接叠一层自下而上的缓存清理抽屉。
   * 每次打开都重新取一次统计——设置页可能已经开了很久，行上的容量会过期。
   */
  private openCacheSheet(): void {
    const store = this.cacheManagementStore;
    if (store === null) {
      return;
    }
    // 诊断、缓存清理、免责声明、播放设置是同一层的抽屉，同一时刻只保留一个。
    this.hideDiagnosticsSheetImmediately();
    this.hideLegalSheetImmediately();
    this.hidePlaybackSheetImmediately();
    this.hideAudioQualitySheetImmediately();
    void store.refresh();
    this.cacheSheetMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private closeCacheSheet(): void {
    this.cacheSheetMotion.close(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  /** 组件首次挂载后的滑入；由抽屉包裹层的 onAppear 触发。 */
  private playCacheSheetEnter(): void {
    this.cacheSheetMotion.enter(this.sheetAnimator);
  }

  /** 急停版：不播退场动画直接卸载（设置页收起时用）。 */
  private hideCacheSheetImmediately(): void {
    this.cacheSheetMotion.hideNow();
  }

  /**
   * 设置页「法律与免责声明」：不关设置页，直接叠一层自下而上的声明抽屉。
   * 与缓存 / 诊断抽屉同一层，打开前先收起另外三个。
   */
  private openLegalSheet(): void {
    this.hideDiagnosticsSheetImmediately();
    this.hideCacheSheetImmediately();
    this.hidePlaybackSheetImmediately();
    this.hideAudioQualitySheetImmediately();
    this.legalSheetMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private closeLegalSheet(): void {
    this.legalSheetMotion.close(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  /** 组件首次挂载后的滑入；由抽屉包裹层的 onAppear 触发。 */
  private playLegalSheetEnter(): void {
    this.legalSheetMotion.enter(this.sheetAnimator);
  }

  /**
   * 设置页「常规 › 播放设置」：不关设置页，直接叠一层自下而上的播放设置抽屉。
   * 与诊断 / 缓存 / 免责声明同一层，打开前先收起另外三个。
   */
  private openPlaybackSheet(): void {
    this.hideDiagnosticsSheetImmediately();
    this.hideCacheSheetImmediately();
    this.hideLegalSheetImmediately();
    this.hideAudioQualitySheetImmediately();
    this.playbackSheetMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private closePlaybackSheet(): void {
    this.playbackSheetMotion.close(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  /** 组件首次挂载后的滑入；由抽屉包裹层的 onAppear 触发。 */
  private playPlaybackSheetEnter(): void {
    this.playbackSheetMotion.enter(this.sheetAnimator);
  }

  /** 急停版：不播退场动画直接卸载（设置页收起 / 打开其它抽屉时用）。 */
  private hidePlaybackSheetImmediately(): void {
    this.playbackSheetMotion.hideNow();
  }

  /** 急停版：不播退场动画直接卸载（设置页收起 / 打开其它抽屉时用）。 */
  private hideLegalSheetImmediately(): void {
    this.legalSheetMotion.hideNow();
  }

  private closeSettings(): void {
    if (!this.settingsMotion.visible) {
      return;
    }
    // 诊断 / 缓存 / 免责声明 / 播放设置抽屉都是叠在设置页之上的，设置页收起时它们不能留在壳层上方。
    this.hideDiagnosticsSheetImmediately();
    this.hideCacheSheetImmediately();
    this.hideLegalSheetImmediately();
    this.hidePlaybackSheetImmediately();
    this.hideAudioQualitySheetImmediately();
    this.settingsMotion.close(this.pageHiddenOffset(), this.pageAnimator);
  }

  /** 组件首次挂载后的滑入；由覆盖层包裹层的 onAppear 触发。 */
  private playSettingsEnter(): void {
    this.settingsMotion.enter(this.pageAnimator);
  }

  /** 屏外位移取根 Stack 的实测宽度；宽度还没量到时退回 0（直接出现，不做错误位移）。 */
  private pageHiddenOffset(): number {
    return this.settingsViewportWidth > 0 ? this.settingsViewportWidth : 0;
  }

  /** 屏外位移取根 Stack 的实测高度；还没量到时退回 0（直接出现，不做错误位移）。 */
  private sheetHiddenOffset(): number {
    return this.shellViewportHeight > 0 ? this.shellViewportHeight : 0;
  }

  /** 08 登录抽屉：三（四）处入口共用；先收曲目弹层，避免两个覆盖层叠在一起。 */
  private openLoginSheet(): void {
    this.hideTrackActionsImmediately();
    this.loginSheetMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  /**
   * 收起登录抽屉。**必须显式取消二维码轮询**（与 `LoginPage` 的 `close()` 同一实现），
   * 只翻 visible 会留下"抽屉关了、轮询还在跑"。
   * 取消放在滑出动画结束后：若在动画开始时取消，抽屉会在下滑的 340ms 里
   * 先闪成「登录已取消」。不可见时调用则直接收尾（幂等）。
   */
  private closeLoginSheet(): void {
    const store = this.authStore;
    if (!this.loginSheetMotion.visible) {
      if (store !== null) {
        closeLoginSheetSession(store);
      }
      return;
    }
    this.loginSheetMotion.close(this.sheetHiddenOffset(), this.sheetAnimator, (): void => {
      if (store !== null) {
        closeLoginSheetSession(store);
      }
    });
  }

  /** 组件首次挂载后的滑入；由覆盖层包裹层的 onAppear 触发。 */
  private playLoginSheetEnter(): void {
    this.loginSheetMotion.enter(this.sheetAnimator);
  }

  /**
   * 抽屉统一的进出场动画执行器（底部抽屉 340ms）。交给 `OverlayMotion` 调用，
   * 屏幕外的初始位移由宿主持有，所以挂载前就能写进 prop。
   */
  private readonly sheetAnimator: OverlayAnimator = (apply: () => void, onFinish?: () => void): void => {
    this.animateSheetMotion(apply, onFinish);
  };

  /** 整页覆盖层（设置 / 播放控制）共用的右侧滑入滑出执行器（320ms）。 */
  private readonly pageAnimator: OverlayAnimator = (apply: () => void, onFinish?: () => void): void => {
    this.getUIContext().animateTo({
      duration: SETTINGS_PAGE_ANIMATION_DURATION,
      curve: curves.cubicBezierCurve(
        SETTINGS_PAGE_CURVE_X1,
        SETTINGS_PAGE_CURVE_Y1,
        SETTINGS_PAGE_CURVE_X2,
        SETTINGS_PAGE_CURVE_Y2
      ),
      onFinish: onFinish
    }, apply);
  };

  private animateSheetMotion(apply: () => void, onFinish?: () => void): void {
    this.getUIContext().animateTo({
      duration: SHEET_ANIMATION_DURATION,
      curve: curves.cubicBezierCurve(
        SHEET_CURVE_X1,
        SHEET_CURVE_Y1,
        SHEET_CURVE_X2,
        SHEET_CURVE_Y2
      ),
      onFinish: onFinish
    }, apply);
  }

  /** 播放页「功能键」入口：整页挂在根 Stack 上，缺 store 时直接忽略（启动未完成）。 */
  private openPlayerPanel(): void {
    if (this.playerStore === null) {
      return;
    }
    this.playerPanelMotion.open(this.pageHiddenOffset(), this.pageAnimator);
  }

  /** 滑出动画结束再卸载；令牌防止连续开关时旧回调误关。 */
  private closePlayerPanel(): void {
    if (!this.playerPanelMotion.visible) {
      return;
    }
    // 定时 / 音质抽屉叠在功能页之上，功能页收起时不能把它们留在壳层上方。
    this.hideSleepTimerSheetImmediately();
    this.hideAudioQualitySheetImmediately();
    this.playerPanelMotion.close(this.pageHiddenOffset(), this.pageAnimator);
  }

  /** 组件首次挂载后的滑入；由包裹层的 onAppear 触发。 */
  private playPlayerPanelEnter(): void {
    this.playerPanelMotion.enter(this.pageAnimator);
  }

  /** 急停版：不播退场动画直接卸载（跳队列 / 打开曲目弹层等需要立刻让位的场景）。 */
  private hidePlayerPanelImmediately(): void {
    this.hideSleepTimerSheetImmediately();
    this.hideAudioQualitySheetImmediately();
    this.playerPanelMotion.hideNow();
  }

  /** 播放控制功能页的「定时关闭」格：在功能页之上再叠一层底部抽屉。 */
  private openSleepTimerSheet(): void {
    if (this.sleepTimerStore === null) {
      return;
    }
    this.sleepTimerMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private closeSleepTimerSheet(): void {
    this.sleepTimerMotion.close(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  /** 组件首次挂载后的滑入；由抽屉包裹层的 onAppear 触发。 */
  private playSleepTimerSheetEnter(): void {
    this.sleepTimerMotion.enter(this.sheetAnimator);
  }

  /** 急停版：不播退场动画直接卸载（功能页收起时用）。 */
  private hideSleepTimerSheetImmediately(): void {
    this.sleepTimerMotion.hideNow();
  }

  /**
   * 音质抽屉：播放控制功能页的音质格、设置页「播放音质」与「下载品质」行共用，
   * 由 `target` 决定读写哪个设置项。
   * 与其它底部抽屉一致，挂载前放到屏外 + 蒙层透明，`onAppear` 后再滑入。
   */
  private openAudioQualitySheet(target: QualitySheetTarget): void {
    if (this.settingsStore === null) {
      return;
    }
    this.qualitySheetTarget = target;
    this.audioQualityMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private closeAudioQualitySheet(): void {
    this.audioQualityMotion.close(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  /** 组件首次挂载后的滑入；由抽屉包裹层的 onAppear 触发。 */
  private playAudioQualitySheetEnter(): void {
    this.audioQualityMotion.enter(this.sheetAnimator);
  }

  /** 急停版：不播退场动画直接卸载（设置页 / 功能页收起时用）。 */
  private hideAudioQualitySheetImmediately(): void {
    this.audioQualityMotion.hideNow();
  }

  /**
   * 先持久化偏好，再让播放器按当前进度重载；任一环节失败都留在抽屉里提示。
   * 成功返回 true，由抽屉自己收起。
   */
  private async selectAudioQuality(quality: AudioQuality): Promise<boolean> {
    const runtime = this.runtime;
    if (runtime === null) {
      return false;
    }
    try {
      const result = await runtime.setAudioQuality(quality);
      return result.success;
    } catch (error) {
      return false;
    }
  }

  /**
   * 下载品质：只写设置，不重载当前曲目、不动已下载文件；之后发起的新下载才按新档位取源。
   */
  private async selectDownloadQuality(quality: AudioQuality): Promise<boolean> {
    const runtime = this.runtime;
    if (runtime === null) {
      return false;
    }
    try {
      const result = await runtime.setDownloadQuality(quality);
      return result.success;
    } catch (error) {
      return false;
    }
  }

  /**
   * 下载上限：写入设置后由 runtime 立即清理超限的最旧下载并刷新下载列表。
   * 保存失败时设置与下载列表都保持原样，分段格回到原选中态。
   */
  private async selectDownloadLimit(limit: number): Promise<boolean> {
    const runtime = this.runtime;
    if (runtime === null) {
      return false;
    }
    try {
      const result = await runtime.setDownloadLimit(limit);
      return result.success;
    } catch (error) {
      return false;
    }
  }

  private openTrackActions(track: MobileTrack): void {
    const store = this.trackActionStore;
    if (store === null) {
      return;
    }
    this.trackActionClosing = false;
    this.resetTrackActionToast();
    // 可见性由 store 决定：先按隐藏位移挂载（若尚未打开），store.open 后同一帧渲染。
    this.trackActionMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
    if (!store.isOpen()) {
      store.open(track);
    }
  }

  private openTracksActions(tracks: MobileTrack[], contextTitle: string = '',
    suggestedName: string = ''): void {
    const store = this.trackActionStore;
    if (store === null || tracks.length === 0) {
      return;
    }
    this.trackActionClosing = false;
    this.resetTrackActionToast();
    const wasOpen = store.isOpen();
    this.trackActionMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
    if (!store.openMany(tracks, contextTitle, suggestedName)) {
      if (!wasOpen) {
        this.trackActionMotion.hideNow();
      }
      return;
    }
  }

  private downloadTracks(tracks: MobileTrack[]): void {
    const store = this.downloadStore;
    if (store === null || tracks.length === 0) {
      return;
    }
    const request = store.request(tracks);
    if (request.queued === 0) {
      this.showTrackActionToast('所选歌曲已下载或正在下载');
      return;
    }
    this.showTrackActionToast(`已开始下载 ${request.queued} 首`);
    request.completion.then((result): void => {
      if (result.failed > 0) {
        this.showTrackActionToast(`有 ${result.failed} 首下载失败，请稍后重试`);
        return;
      }
      if (result.added > 0) {
        this.showTrackActionToast(`已下载 ${result.added} 首`);
      }
    });
  }

  private closeTrackActions(): void {
    const store = this.trackActionStore;
    if (store === null || !store.isOpen()) {
      return;
    }
    this.trackActionClosing = true;
    this.trackActionMotion.close(this.sheetHiddenOffset(), this.sheetAnimator, (): void => {
      // 动画结束后才关 store（卸载），副作用同样延后：
      // 延迟 toast 要等面板真的不在了才冒出来，否则会浮在正在下滑的面板上。
      store.close();
      this.trackActionClosing = false;
      this.flushPendingTrackActionToast();
    });
  }

  private playTrackActionEnter(): void {
    const store = this.trackActionStore;
    if (store === null || !store.isOpen()) {
      return;
    }
    this.trackActionMotion.enter(this.sheetAnimator);
  }

  /** 急停版：打开其它覆盖层前立刻收掉曲目弹层，避免两个抽屉一起播动画。 */
  private hideTrackActionsImmediately(): void {
    this.trackActionMotion.hideNow();
    this.trackActionStore?.close();
    this.trackActionClosing = false;
    this.resetTrackActionToast();
  }

  /**
   * 曲目动作结果的宿主级提示。
   *
   * 动作在抽屉滑出前就已启动，通常会在 340ms 动画内返回；此时先缓存，
   * 等 closeTrackActions 的 onFinish 完成卸载后再显示。慢写入晚于动画返回时直接显示。
   */
  private showTrackActionToast(message: ResourceStr): void {
    if (this.trackActionClosing) {
      this.pendingTrackActionToast = message;
      this.hasPendingTrackActionToast = true;
      return;
    }
    this.presentTrackActionToast(message);
  }

  private flushPendingTrackActionToast(): void {
    if (!this.hasPendingTrackActionToast) {
      return;
    }
    const message = this.pendingTrackActionToast;
    this.clearPendingTrackActionToast();
    this.presentTrackActionToast(message);
  }

  private clearPendingTrackActionToast(): void {
    this.hasPendingTrackActionToast = false;
    this.pendingTrackActionToast = '';
  }

  /** 打开 / 急停抽屉时清掉旧 toast，避免上一条结果压在新面板上。 */
  private resetTrackActionToast(): void {
    this.clearPendingTrackActionToast();
    this.clearTrackActionToastTimer();
    this.trackActionToastSequence += 1;
    this.trackActionToastVisible = false;
    this.trackActionToastOpacity = 0;
    this.trackActionToastTranslateY = 12;
  }

  private clearTrackActionToastTimer(): void {
    if (this.trackActionToastTimer !== -1) {
      clearTimeout(this.trackActionToastTimer);
      this.trackActionToastTimer = -1;
    }
  }

  /** 深色胶囊反色：浅色主题近黑底浅字，深色主题反过来。 */
  private presentTrackActionToast(message: ResourceStr): void {
    this.clearTrackActionToastTimer();
    const sequence = this.trackActionToastSequence + 1;
    this.trackActionToastSequence = sequence;
    this.trackActionToastMessage = message;
    if (!this.trackActionToastVisible) {
      this.trackActionToastOpacity = 0;
      this.trackActionToastTranslateY = 12;
      this.trackActionToastVisible = true;
    }
    this.getUIContext().animateTo({
      duration: TRACK_ACTION_TOAST_FADE_IN_DURATION,
      curve: Curve.EaseOut
    }, (): void => {
      this.trackActionToastOpacity = 1;
      this.trackActionToastTranslateY = 0;
    });
    this.trackActionToastTimer = setTimeout((): void => {
      this.trackActionToastTimer = -1;
      this.dismissTrackActionToast(sequence);
    }, TRACK_ACTION_TOAST_DURATION);
    hilog.info(DOMAIN, TAG, 'Track action toast shown');
  }

  private dismissTrackActionToast(sequence: number): void {
    if (sequence !== this.trackActionToastSequence) {
      return;
    }
    this.getUIContext().animateTo({
      duration: TRACK_ACTION_TOAST_FADE_OUT_DURATION,
      curve: Curve.EaseIn,
      onFinish: (): void => {
        if (sequence !== this.trackActionToastSequence) {
          return;
        }
        this.trackActionToastVisible = false;
        this.trackActionToastOpacity = 0;
        this.trackActionToastTranslateY = 12;
      }
    }, (): void => {
      this.trackActionToastOpacity = 0;
      this.trackActionToastTranslateY = 8;
    });
  }

  /** 「我的」页 + 号：从底部滑入新建歌单抽屉。 */
  private openPlaylistCreateSheet(): void {
    if (this.playlistStore === null) {
      return;
    }
    this.hideTrackActionsImmediately();
    this.playlistCreateMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private closePlaylistCreateSheet(): void {
    this.playlistCreateMotion.close(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private playPlaylistCreateSheetEnter(): void {
    this.playlistCreateMotion.enter(this.sheetAnimator);
  }

  /** 歌单详情页右上角：从底部滑入「修改歌单信息」抽屉。 */
  private openPlaylistEditSheet(playlistId: string): void {
    if (this.playlistStore === null || playlistId.length === 0) {
      return;
    }
    this.hideTrackActionsImmediately();
    // 目标歌单必须早于 visible 写入：抽屉挂载时会立刻读它。
    this.playlistEditId = playlistId;
    this.playlistEditMotion.open(this.sheetHiddenOffset(), this.sheetAnimator);
  }

  private closePlaylistEditSheet(): void {
    this.playlistEditMotion.close(this.sheetHiddenOffset(), this.sheetAnimator, (): void => {
      // 卸载后才清空目标 id，避免下滑动画里名称先变空。
      this.playlistEditId = '';
    });
  }

  private playPlaylistEditSheetEnter(): void {
    this.playlistEditMotion.enter(this.sheetAnimator);
  }

  /** 歌词换源弹层（当前歌词面板未暴露入口，先保留宿主驱动能力）：先放到屏外再打开，等挂载后滑入。 */
  private openLyricsCandidates(): void {
    const state = this.lyricsPanelState;
    if (state === null) {
      return;
    }
    this.lyricsCandidatesTransitionToken += 1;
    if (state.candidatesOpen) {
      this.animateSheetMotion((): void => {
        this.lyricsCandidatesOffset = 0;
        this.lyricsCandidatesScrimAlpha = 1;
      });
      return;
    }
    this.lyricsCandidatesOffset = this.sheetHiddenOffset();
    this.lyricsCandidatesScrimAlpha = 0;
    state.openCandidateSearch();
  }

  private closeLyricsCandidates(): void {
    const state = this.lyricsPanelState;
    if (state === null || !state.candidatesOpen) {
      return;
    }
    const token = this.lyricsCandidatesTransitionToken + 1;
    this.lyricsCandidatesTransitionToken = token;
    this.animateSheetMotion((): void => {
      this.lyricsCandidatesOffset = this.sheetHiddenOffset();
      this.lyricsCandidatesScrimAlpha = 0;
    }, (): void => {
      if (this.lyricsCandidatesTransitionToken !== token) {
        return;
      }
      state.closeCandidateSearch();
      this.lyricsCandidatesOffset = 0;
      this.lyricsCandidatesScrimAlpha = 1;
    });
  }

  private playLyricsCandidatesEnter(): void {
    const state = this.lyricsPanelState;
    if (state === null || !state.candidatesOpen) {
      return;
    }
    this.animateSheetMotion((): void => {
      this.lyricsCandidatesOffset = 0;
      this.lyricsCandidatesScrimAlpha = 1;
    });
  }

  /**
   * 打开播放页：歌词面板与换源弹层共用一份 `LyricsPanelState`，每次入栈前重建。
   * 播放页卸载时会 dispose 它（自建 / 借用一致），所以返回后重进必须换新实例。
   */
  /** 搜索结果点击多 P 合集：压入只读合集详情，已经在同一合集页时不重复入栈。 */
  private openCollectionRoute(bvid: string): void {
    const cleanId = bvid.trim().slice(0, 32);
    if (cleanId.length === 0) {
      return;
    }
    const routeNames = this.pathStack.getAllPathName();
    if (routeNames.length > 0 && routeNames[routeNames.length - 1] === ROUTE_COLLECTION) {
      return;
    }
    this.pathStack.pushPath({ name: ROUTE_COLLECTION, param: cleanId });
  }

  private openPlayerRoute(): void {
    // 已经开始播放入场时防止连点重复入栈；播放页已经在前台时也不重复压栈。
    const routeNames = this.pathStack.getAllPathName();
    if (routeNames.length > 0 && routeNames[routeNames.length - 1] === ROUTE_PLAYER) {
      return;
    }
    this.hidePlayerLyricsSheetImmediately();
    if (this.lyricsStore !== null && this.playerStore !== null) {
      this.lyricsPanelState = new LyricsPanelState(this.lyricsStore, this.playerStore);
    } else {
      this.lyricsPanelState = null;
    }
    this.pathStack.pushPath({ name: ROUTE_PLAYER });
  }

  /** 点击播放页歌词预览：挂载面板后再播展开动画（clip 式上推 + 淡入，420ms）。 */
  private openPlayerLyricsSheet(): void {
    if (this.lyricsPanelState === null) {
      return;
    }
    this.playerLyricsSheetTransitionToken += 1;
    this.playerLyricsSheetReveal = 0;
    this.playerLyricsSheetVisible = true;
  }

  private playPlayerLyricsSheetEnter(): void {
    if (!this.playerLyricsSheetVisible) {
      return;
    }
    this.animatePlayerLyricsSheet(1);
  }

  private closePlayerLyricsSheet(): void {
    if (!this.playerLyricsSheetVisible) {
      return;
    }
    const token = this.playerLyricsSheetTransitionToken + 1;
    this.playerLyricsSheetTransitionToken = token;
    this.getUIContext().animateTo({
      duration: LYRICS_SHEET_ANIMATION_DURATION,
      curve: curves.cubicBezierCurve(
        SHEET_CURVE_X1,
        SHEET_CURVE_Y1,
        SHEET_CURVE_X2,
        SHEET_CURVE_Y2
      ),
      onFinish: (): void => {
        if (this.playerLyricsSheetTransitionToken !== token) {
          return;
        }
        this.playerLyricsSheetVisible = false;
        this.playerLyricsSheetReveal = 0;
      }
    }, () => {
      this.playerLyricsSheetReveal = 0;
    });
  }

  private animatePlayerLyricsSheet(reveal: number): void {
    this.getUIContext().animateTo({
      duration: LYRICS_SHEET_ANIMATION_DURATION,
      curve: curves.cubicBezierCurve(
        SHEET_CURVE_X1,
        SHEET_CURVE_Y1,
        SHEET_CURVE_X2,
        SHEET_CURVE_Y2
      )
    }, () => {
      this.playerLyricsSheetReveal = reveal;
    });
  }

  /** 切页 / 重新进播放页时不等动画，直接卸载歌词面板。 */
  private hidePlayerLyricsSheetImmediately(): void {
    this.playerLyricsSheetTransitionToken += 1;
    this.playerLyricsSheetVisible = false;
    this.playerLyricsSheetReveal = 0;
  }

  private removePlaylistRoutes(playlistId: string): void {
    const names = this.pathStack.getAllPathName();
    const indexes: number[] = [];
    for (let index = 0; index < names.length; index++) {
      if (names[index] !== ROUTE_PLAYLIST) {
        continue;
      }
      if ((this.pathStack.getParamByIndex(index) as string) === playlistId) {
        indexes.push(index);
      }
    }
    if (indexes.length > 0) {
      this.pathStack.removeByIndexes(indexes);
    }
  }
}

function safeStartupErrorCode(value: string): string {
  if (value.length > 0 && value.length <= 64 && /^[A-Za-z0-9._-]+$/.test(value)) {
    return value;
  }
  return 'app.startupFailed';
}

function routePlaylistId(param: Object): string {
  if (typeof param !== 'string') {
    return '';
  }
  return param.trim().slice(0, 80);
}

function routeCollectionBvid(param: Object): string {
  if (typeof param !== 'string') {
    return '';
  }
  return param.trim().slice(0, 32);
}
