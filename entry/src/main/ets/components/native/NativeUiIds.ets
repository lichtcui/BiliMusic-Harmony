/**
 * 本文件由 scripts/ui-ids.mjs 生成，请勿手改。
 *
 * 唯一真源是 scripts/ui-ids.json：改 id 或分组后运行
 *   node scripts/ui-ids.mjs --write
 * `npm test` 会先跑 --check，校验生成物、选择器唯一性与代码里的引用完整性。
 */
export class NativeUiIds {
  static readonly shellRoot: string = 'native-shell';
  static readonly shellHeaderActions: string = 'native-shell-header-actions';
  static readonly shellSettingsAction: string = 'native-shell-settings';
  static readonly navDiscover: string = 'nav-discover';
  static readonly navMine: string = 'nav-mine';
  /**
   * 新悬浮 dock：根容器与左侧导航胶囊。
   *
   * `navDiscover` / `navMine` 现在标识单颗导航胶囊里的“目的地标签”（在「我的」显示
   * 「发现」、在「发现」显示「我的」），同一时刻只渲染一个；点击即切换一级 tab。
   */
  static readonly bottomDock: string = 'bottom-dock';
  static readonly navPill: string = 'nav-pill';
  /** 阶段 1d：tab0 从「搜索」变成「发现」（搜索是它的一个分支），契约 id 随之改名。 */
  static readonly discoverTabContent: string = 'discover-tab-content';
  static readonly libraryTabContent: string = 'library-tab-content';

  static readonly minePage: string = 'mine-page';
  static readonly mineHeader: string = 'mine-header';
  static readonly mineAccountCard: string = 'mine-account-card';
  static readonly mineAccountName: string = 'mine-account-name';
  static readonly mineAccountAction: string = 'mine-account-action';
  static readonly minePlaylistsContent: string = 'mine-playlists-content';
  /** 「我的」页四块快捷方块：容器 / 我喜欢的 / 历史 / 下载 / 新建歌单 / 播放角标。 */
  static readonly mineQuickActions: string = 'mine-quick-actions';
  static readonly mineQuickLiked: string = 'mine-quick-liked';
  static readonly mineQuickHistory: string = 'mine-quick-history';
  static readonly mineQuickDownloads: string = 'mine-quick-downloads';
  static readonly mineQuickCreate: string = 'mine-quick-create';
  static readonly mineQuickLikedPlay: string = 'mine-quick-liked-play';
  static readonly mineQuickHistoryPlay: string = 'mine-quick-history-play';
  static readonly mineQuickDownloadsPlay: string = 'mine-quick-downloads-play';

  /** 「发现」页根容器：`SearchPage` 组件保留原名（它是搜索的宿主），页面语义已是「发现」。 */
  static readonly discoverPage: string = 'native-discover-page';

  static readonly searchInput: string = 'search-input';
  static readonly searchState: string = 'search-state';
  static readonly searchIdleState: string = 'search-idle-state';
  static readonly searchLoadingState: string = 'search-loading-state';
  static readonly searchEmptyState: string = 'search-empty-state';
  static readonly searchErrorState: string = 'search-error-state';
  static readonly searchResults: string = 'search-results';
  static readonly searchLoadMoreError: string = 'search-load-more-error';

  static readonly loginPage: string = 'login-page';
  static readonly loginContent: string = 'login-content';
  static readonly loginIdle: string = 'login-idle';
  static readonly loginStarting: string = 'login-starting';
  static readonly loginQrContent: string = 'login-qr-content';
  static readonly loginQrCode: string = 'login-qr-code';
  static readonly loginQrUnavailable: string = 'login-qr-unavailable';
  static readonly loginExpired: string = 'login-expired';
  static readonly loginError: string = 'login-error';
  static readonly loginCancelled: string = 'login-cancelled';
  static readonly loginMessageStatus: string = 'login-message-status';
  static readonly loginRestart: string = 'login-restart';
  /** 「我的」页新稿账号抽屉：账号卡 / 名称 / 危险退出按钮 / 失败提示。 */
  static readonly loginAccountCard: string = 'login-account-card';
  static readonly loginAccountName: string = 'login-account-name';
  static readonly loginLogout: string = 'login-logout';
  /** 08 登录抽屉：面板本体；蒙层/拖拽条的选择器由 `sheetScrim` 等派生。 */
  static readonly loginSheet: string = 'login-sheet';

  /** 07 设置整页：根 / 返回 / 内容 / 分组 / 行 id（T16）。 */
  static readonly settingsPage: string = 'settings-page';
  static readonly settingsBack: string = 'settings-back';
  static readonly settingsContent: string = 'settings-content';
  static readonly settingsGeneralSection: string = 'settings-general-section';
  static readonly settingsThemeMode: string = 'settings-theme-mode';
  static readonly settingsThemeLight: string = 'settings-theme-light';
  static readonly settingsThemeDark: string = 'settings-theme-dark';
  static readonly settingsThemeSystem: string = 'settings-theme-system';
  /** 「数据」组：缓存清理。 */
  static readonly settingsDataSection: string = 'settings-data-section';
  /** 「下载」组：下载品质行（三格分段，写 `downloadQuality`）。 */
  static readonly settingsDownloadQuality: string = 'settings-download-quality';
  static readonly settingsDownloadQualityLow: string = 'settings-download-quality-low';
  static readonly settingsDownloadQualityStandard: string = 'settings-download-quality-standard';
  static readonly settingsDownloadQualityHigh: string = 'settings-download-quality-high';
  /** 「下载」组：下载品质三态下方的说明文字。 */
  static readonly settingsDownloadQualityNote: string = 'settings-download-quality-note';
  /** 「下载」组：最多保留条数（100 / 300 / 500 首）。 */
  static readonly settingsDownloadSection: string = 'settings-download-section';
  static readonly settingsDownloadLimit: string = 'settings-download-limit';
  /** 「常规」组：播放设置入口行，点击打开播放设置抽屉。 */
  static readonly settingsPlaybackSection: string = 'settings-playback-section';
  static readonly settingsAudioQuality: string = 'settings-audio-quality';
  static readonly settingsAudioQualityLow: string = 'settings-audio-quality-low';
  static readonly settingsAudioQualityStandard: string = 'settings-audio-quality-standard';
  static readonly settingsAudioQualityHigh: string = 'settings-audio-quality-high';
  /** 播放设置抽屉：播放音质三态下方的说明文字。 */
  static readonly settingsAudioQualityNote: string = 'settings-audio-quality-note';
  static readonly settingsAutoPlay: string = 'settings-auto-play';
  static readonly settingsShowLyrics: string = 'settings-show-lyrics';
  /**
   * 「播放设置」抽屉：设置页「常规 › 播放设置」行弹出，叠在设置整页之上；
   * 播放音质 / 自动播放 / 歌词显示都在这里维护。蒙层 / 拖拽条由 `sheetScrim` 等派生。
   */
  static readonly settingsPlaybackSheet: string = 'settings-playback-sheet';
  static readonly settingsPlaybackSheetContent: string = 'settings-playback-sheet-content';
  /** 播放设置抽屉：设置写入失败的提示（设置页同文案的提示在抽屉背后不可见）。 */
  static readonly settingsPlaybackSheetError: string = 'settings-playback-sheet-error';
  static readonly settingsCacheClear: string = 'settings-cache-clear';
  static readonly settingsCacheError: string = 'settings-cache-error';
  static readonly settingsCacheRetry: string = 'settings-cache-retry';
  /**
   * 缓存清理抽屉：设置页「缓存清理」行弹出，叠在设置整页之上（与诊断抽屉同一层）。
   * 蒙层 / 拖拽条由 `sheetScrim` 等从 `settingsCacheSheet` 派生。
   */
  static readonly settingsCacheSheet: string = 'settings-cache-sheet';
  static readonly settingsCacheSheetContent: string = 'settings-cache-sheet-content';
  static readonly settingsCacheSheetImages: string = 'settings-cache-sheet-images';
  static readonly settingsCacheSheetLyrics: string = 'settings-cache-sheet-lyrics';
  static readonly settingsCacheSheetAudio: string = 'settings-cache-sheet-audio';
  static readonly settingsCacheSheetClearAll: string = 'settings-cache-sheet-clear-all';
  static readonly settingsCacheSheetError: string = 'settings-cache-sheet-error';
  static readonly settingsCacheSheetRetry: string = 'settings-cache-sheet-retry';
  static readonly settingsWriteError: string = 'settings-write-error';
  /** 「关于」组：打开诊断信息抽屉。 */
  static readonly settingsOpenDiagnostics: string = 'settings-open-diagnostics';
  /** 「关于」组：应用版本 / 作者 / GitHub / 诊断信息 / 法律与免责声明。 */
  static readonly settingsAboutSection: string = 'settings-about-section';
  static readonly settingsAppVersion: string = 'settings-app-version';
  static readonly settingsAuthor: string = 'settings-author';
  static readonly settingsGithub: string = 'settings-github';
  static readonly settingsLegal: string = 'settings-legal';
  /**
   * 法律与免责声明抽屉：设置页「关于」组入口，叠在设置整页之上。
   * 蒙层 / 拖拽条由 `sheetScrim` 等从 `settingsLegalSheet` 派生。
   */
  static readonly settingsLegalSheet: string = 'settings-legal-sheet';
  static readonly settingsLegalSheetContent: string = 'settings-legal-sheet-content';
  /**
   * 诊断信息抽屉：从设置页「打开诊断信息」弹出，盖在设置页之上（2026-11 从右侧整页
   * 路由改成自下而上的抽屉）。蒙层 / 拖拽条由 `sheetScrim` 等派生。
   */
  static readonly diagnosticsSheet: string = 'settings-diagnostics-sheet';

  static readonly miniPlayer: string = 'mini-player';
  static readonly miniPlayerTitle: string = 'mini-player-title';
  static readonly miniPlayerArtist: string = 'mini-player-artist';
  static readonly miniPlayerExpand: string = 'mini-player-expand';
  static readonly miniPlayerToggle: string = 'mini-player-toggle';
  static readonly miniPlayerNext: string = 'mini-player-next';
  static readonly miniPlayerError: string = 'mini-player-error';
  static readonly miniPlayerErrorTrack: string = 'mini-player-error-track';
  static readonly miniPlayerRetry: string = 'mini-player-retry';
  static readonly playerPage: string = 'player-page';
  static readonly playerCover: string = 'player-cover';
  static readonly playerTitle: string = 'player-title';
  static readonly playerArtist: string = 'player-artist';
  /** 08 稿歌词预览：播放页只显示「当前行 + 下一行」，整页歌词仍走 `player-lyric-open` 跳转。 */
  static readonly playerLyricCurrent: string = 'player-lyric-current';
  static readonly playerLyricNext: string = 'player-lyric-next';
  static readonly playerLyricOpen: string = 'player-lyric-open';
  static readonly playerProgress: string = 'player-progress';
  static readonly playerPosition: string = 'player-position';
  static readonly playerDuration: string = 'player-duration';
  /** 播放页 2026-11 改为滑动切歌 + 功能整页；旧的独立状态/上一首/下一首/模式/队列/更多 id 已移除。 */
  static readonly playerToggle: string = 'player-toggle';
  static readonly playerTrackActions: string = 'player-track-actions';
  static readonly playerFavorite: string = 'player-favorite';
  static readonly playerNavDiscover: string = 'player-nav-discover';
  static readonly playerNavLibrary: string = 'player-nav-library';
  static readonly playerSwipeStage: string = 'player-swipe-stage';
  static readonly playerError: string = 'player-error';
  static readonly playerErrorTitle: string = 'player-error-title';
  static readonly playerErrorMessage: string = 'player-error-message';
  static readonly playerErrorTrackTitle: string = 'player-error-track-title';
  static readonly playerErrorTrackArtist: string = 'player-error-track-artist';
  static readonly playerErrorRetry: string = 'player-error-retry';
  static readonly playerEmpty: string = 'player-empty';
  static readonly playerEmptyTitle: string = 'player-empty-title';
  /** T15 播放控制面板：2026-11 从底部抽屉改成右侧滑入的整页，根容器保留原 id。 */
  static readonly playerControlPanel: string = 'player-control-panel';
  /** 功能整页头部的返回按钮（与设置整页同构；不再有抽屉的 scrim / handle / close）。 */
  static readonly playerPanelBack: string = 'player-panel-back';
  static readonly playerPanelAdd: string = 'player-panel-add';
  static readonly playerPanelMode: string = 'player-panel-mode';
  static readonly playerPanelTimer: string = 'player-panel-timer';
  static readonly playerPanelDownload: string = 'player-panel-download';
  static readonly playerPanelQuality: string = 'player-panel-quality';

  /**
   * 「定时关闭」抽屉：从播放控制功能页的定时格弹出，叠在功能整页之上。
   * 蒙层 / 拖拽条同样由 `sheetScrim` 等从 `sleepTimerSheet` 派生。
   */
  static readonly sleepTimerSheet: string = 'sleep-timer-sheet';
  static readonly sleepTimerContent: string = 'sleep-timer-content';
  static readonly sleepTimerCancel: string = 'sleep-timer-cancel';

  /**
   * 「音质选择」抽屉：从播放控制功能页的音质格或设置页的播放音质行弹出。
   * 蒙层 / 拖拽条同样由 `sheetScrim` 等从 `audioQualitySheet` 派生。
   */
  static readonly audioQualitySheet: string = 'audio-quality-sheet';
  static readonly audioQualityContent: string = 'audio-quality-content';
  static readonly audioQualitySaveError: string = 'audio-quality-save-error';
  static readonly audioQualityFooter: string = 'audio-quality-footer';

  /**
   * 「下载品质」抽屉：与音质抽屉共用 `AudioQualitySheet`（`target` 区分读写字段），
   * id 仍独立一套，避免两个入口在 uitest 里不可区分；蒙层 / 拖拽条同样从
   * `downloadQualitySheet` 派生。
   */
  static readonly downloadQualitySheet: string = 'download-quality-sheet';
  static readonly downloadQualityContent: string = 'download-quality-content';
  static readonly downloadQualitySaveError: string = 'download-quality-save-error';
  static readonly downloadQualityFooter: string = 'download-quality-footer';

  /**
   * 曲目操作抽屉：2026-11 起并到共用外壳 `BottomSheet`，
   * 蒙层 / 拖拽条同样由 `sheetScrim` 等派生（不再手写 scrim / handle 字面量）。
   */
  static readonly trackActionSheet: string = 'track-action-sheet';
  static readonly trackActionContent: string = 'track-action-content';
  /** 曲目动作结果的自绘底部 toast；只在结果出现时短暂挂载。 */
  static readonly trackActionToast: string = 'track-action-toast';
  /** 曲目操作抽屉里的「下载」行（单曲与批量共用）。 */
  static readonly trackActionDownload: string = 'track-action-download';

  static readonly queuePage: string = 'queue-page';
  static readonly queueList: string = 'queue-list';
  static readonly queueError: string = 'queue-error';
  static readonly queueClear: string = 'queue-clear';
  static readonly queueEmpty: string = 'queue-empty';
  static readonly queueEmptyTitle: string = 'queue-empty-title';
  static readonly queueEmptyBack: string = 'queue-empty-back';
  static readonly queueEmptySearch: string = 'queue-empty-search';

  /** 历史整页头部（返回 +「历史」），与「我喜欢的」同构。 */
  static readonly recentHeader: string = 'recent-header';
  static readonly recentHeaderBack: string = 'recent-header-back';
  static readonly recentError: string = 'recent-error';
  static readonly recentErrorDismiss: string = 'recent-error-dismiss';
  static readonly recentEmpty: string = 'recent-empty';
  static readonly recentPlayAll: string = 'recent-play-all';
  /** 历史工具条 / 批量底栏：与歌单详情页同构，多选不再插一条独立动作行。 */
  static readonly recentToolbar: string = 'recent-toolbar';
  /** 历史上的「多选」入口：只负责进入多选态，退出由独立的关闭按钮承担。 */
  static readonly recentSelect: string = 'recent-select';
  static readonly recentSelectAll: string = 'recent-select-all';
  static readonly recentExitSelect: string = 'recent-exit-select';
  static readonly recentBottomBar: string = 'recent-bottom-bar';
  static readonly recentRemoveSelected: string = 'recent-remove-selected';
  static readonly recentAddSelected: string = 'recent-add-selected';
  static readonly recentList: string = 'recent-list';
  /** 下载整页：与历史同构（页头 / 空态 / 工具条 / 列表 / 仅删除的批量底栏）。 */
  static readonly downloadsPage: string = 'downloads-page';
  static readonly downloadsHeader: string = 'downloads-header';
  static readonly downloadsHeaderBack: string = 'downloads-header-back';
  static readonly downloadsError: string = 'downloads-error';
  static readonly downloadsErrorDismiss: string = 'downloads-error-dismiss';
  static readonly downloadsEmpty: string = 'downloads-empty';
  static readonly downloadsPlayAll: string = 'downloads-play-all';
  static readonly downloadsToolbar: string = 'downloads-toolbar';
  static readonly downloadsSelect: string = 'downloads-select';
  static readonly downloadsSelectAll: string = 'downloads-select-all';
  static readonly downloadsExitSelect: string = 'downloads-exit-select';
  static readonly downloadsBottomBar: string = 'downloads-bottom-bar';
  static readonly downloadsRemoveSelected: string = 'downloads-remove-selected';
  static readonly downloadsList: string = 'downloads-list';
  static readonly favoritesError: string = 'favorites-error';
  static readonly favoritesErrorDismiss: string = 'favorites-error-dismiss';
  static readonly favoritesEmpty: string = 'favorites-empty';
  static readonly favoritesEmptySearch: string = 'favorites-empty-search';
  /** 「我喜欢的」整页：页头 / Hero / 吸顶工具条 / 曲目列表（版式与歌单详情页共用）。 */
  static readonly favoritesPage: string = 'favorites-page';
  static readonly favoritesHeader: string = 'favorites-header';
  static readonly favoritesHeaderBack: string = 'favorites-header-back';
  static readonly favoritesHero: string = 'favorites-hero';
  static readonly favoritesCover: string = 'favorites-cover';
  static readonly favoritesToolbar: string = 'favorites-toolbar';
  static readonly favoritesPlayAll: string = 'favorites-play-all';
  static readonly favoritesSelectToggle: string = 'favorites-select-toggle';
  static readonly favoritesSelectAll: string = 'favorites-select-all';
  static readonly favoritesExitSelect: string = 'favorites-exit-select';
  static readonly favoritesList: string = 'favorites-list';
  /** 多选态底部操作栏（删除 / 添加到）。 */
  static readonly favoritesBottomBar: string = 'favorites-bottom-bar';
  static readonly favoritesDeleteSelected: string = 'favorites-delete-selected';
  static readonly favoritesAddSelected: string = 'favorites-add-selected';
  static readonly playlistNameDialog: string = 'playlist-name-dialog';
  static readonly playlistNameInput: string = 'playlist-name-input';
  static readonly playlistNameError: string = 'playlist-name-error';
  static readonly playlistNameCancel: string = 'playlist-name-cancel';
  static readonly playlistNameConfirm: string = 'playlist-name-confirm';
  static readonly playlistError: string = 'playlist-error';
  static readonly playlistErrorDismiss: string = 'playlist-error-dismiss';
  /** 「新建歌单」抽屉（+ 号入口）：面板本体；蒙层 / 拖拽条由 `sheetScrim` 等派生。 */
  static readonly playlistCreateSheet: string = 'playlist-create-sheet';
  static readonly playlistCreateNameInput: string = 'playlist-create-name-input';
  static readonly playlistCreateError: string = 'playlist-create-error';
  static readonly playlistCreateConfirm: string = 'playlist-create-confirm';
  static readonly playlistList: string = 'playlist-list';
  static readonly playlistDetail: string = 'playlist-detail';
  static readonly playlistDetailHeader: string = 'playlist-detail-header';
  static readonly playlistDetailHeaderBack: string = 'playlist-detail-header-back';
  /** 顶栏右侧「修改歌单信息」入口（打开编辑抽屉）。 */
  static readonly playlistDetailEdit: string = 'playlist-detail-edit';
  static readonly playlistDetailHero: string = 'playlist-detail-hero';
  static readonly playlistDetailCover: string = 'playlist-detail-cover';
  static readonly playlistDetailName: string = 'playlist-detail-name';
  static readonly playlistDetailDescription: string = 'playlist-detail-description';
  /** 列表顶栏：全部播放 + 多选 / 全选 / 关闭。 */
  static readonly playlistDetailToolbar: string = 'playlist-detail-toolbar';
  static readonly playlistDetailToolbarPlayAll: string = 'playlist-detail-toolbar-play-all';
  static readonly playlistDetailSelectToggle: string = 'playlist-detail-select-toggle';
  static readonly playlistDetailSelectAll: string = 'playlist-detail-select-all';
  static readonly playlistDetailExitSelect: string = 'playlist-detail-exit-select';
  /** 多选态底部操作栏（删除 / 添加到）。 */
  static readonly playlistDetailBottomBar: string = 'playlist-detail-bottom-bar';
  static readonly playlistDetailDeleteSelected: string = 'playlist-detail-delete-selected';
  static readonly playlistDetailAddSelected: string = 'playlist-detail-add-selected';
  static readonly playlistDetailError: string = 'playlist-detail-error';
  static readonly playlistDetailErrorDismiss: string = 'playlist-detail-error-dismiss';
  static readonly playlistDetailEmpty: string = 'playlist-detail-empty';
  static readonly playlistDetailList: string = 'playlist-detail-list';
  static readonly playlistDetailMissing: string = 'playlist-detail-missing';
  static readonly playlistDetailBack: string = 'playlist-detail-back';

  /** 搜索结果多 P 合集详情：与歌单详情共用音乐列表模板，只读远端合集不含删除 / 编辑。 */
  static readonly collectionDetail: string = 'collection-detail';
  static readonly collectionDetailHeader: string = 'collection-detail-header';
  static readonly collectionDetailHeaderBack: string = 'collection-detail-header-back';
  static readonly collectionDetailHero: string = 'collection-detail-hero';
  static readonly collectionDetailCover: string = 'collection-detail-cover';
  static readonly collectionDetailName: string = 'collection-detail-name';
  static readonly collectionDetailMeta: string = 'collection-detail-meta';
  static readonly collectionDetailToolbar: string = 'collection-detail-toolbar';
  static readonly collectionDetailPlayAll: string = 'collection-detail-play-all';
  static readonly collectionDetailSelectToggle: string = 'collection-detail-select-toggle';
  static readonly collectionDetailSelectAll: string = 'collection-detail-select-all';
  static readonly collectionDetailExitSelect: string = 'collection-detail-exit-select';
  static readonly collectionDetailBottomBar: string = 'collection-detail-bottom-bar';
  static readonly collectionDetailAddSelected: string = 'collection-detail-add-selected';
  static readonly collectionDetailErrorDismiss: string = 'collection-detail-error-dismiss';
  static readonly collectionDetailFavoriteError: string = 'collection-detail-favorite-error';
  static readonly collectionDetailLoading: string = 'collection-detail-loading';
  static readonly collectionDetailError: string = 'collection-detail-error';
  static readonly collectionDetailEmpty: string = 'collection-detail-empty';
  static readonly collectionDetailList: string = 'collection-detail-list';
  static readonly collectionDetailUnavailable: string = 'collection-detail-unavailable';
  static readonly collectionDetailBack: string = 'collection-detail-back';

  /** 「修改歌单信息」抽屉：面板本体；蒙层 / 拖拽条由 `sheetScrim` 等派生。 */
  static readonly playlistEditSheet: string = 'playlist-edit-sheet';
  static readonly playlistEditCover: string = 'playlist-edit-cover';
  static readonly playlistEditNameInput: string = 'playlist-edit-name-input';
  static readonly playlistEditDescriptionInput: string = 'playlist-edit-description-input';
  static readonly playlistEditError: string = 'playlist-edit-error';
  static readonly playlistEditSave: string = 'playlist-edit-save';

  static readonly lyricsPanel: string = 'lyrics-panel';
  /** 歌词面板（design/lyrics-page.html）：从状态栏下沿盖到进度条上方。 */
  static readonly lyricsSheet: string = 'lyrics-sheet';
  static readonly lyricsSheetTitle: string = 'lyrics-sheet-title';
  static readonly lyricsSheetArtist: string = 'lyrics-sheet-artist';
  static readonly lyricsSheetPlay: string = 'lyrics-sheet-play';
  static readonly lyricsCollapse: string = 'lyrics-collapse';
  static readonly lyricsLoading: string = 'lyrics-loading';
  static readonly lyricsEmpty: string = 'lyrics-empty';
  static readonly lyricsError: string = 'lyrics-error';
  static readonly lyricsCandidatesLoading: string = 'lyrics-candidates-loading';
  static readonly lyricsCandidatesEmpty: string = 'lyrics-candidates-empty';
  static readonly lyricsCandidatesEmptyRetry: string = 'lyrics-candidates-empty-retry';
  static readonly lyricsCandidatesError: string = 'lyrics-candidates-error';
  static readonly lyricsCandidatesRetry: string = 'lyrics-candidates-retry';
  static readonly lyricsCandidatesList: string = 'lyrics-candidates-list';
  static readonly lyricsCandidateSelectionError: string = 'lyrics-candidate-selection-error';
  static readonly lyricsSyncedList: string = 'lyrics-synced-list';
  static readonly lyricsUnsyncedList: string = 'lyrics-unsynced-list';
  static readonly lyricsUnsyncedLabel: string = 'lyrics-unsynced-label';
  static readonly lyricsErrorRetry: string = 'lyrics-error-retry';
  static readonly lyricsCandidatesSheet: string = 'lyrics-candidates-sheet';

  static shellSelectors(): string[] {
    return [
      NativeUiIds.shellRoot,
      NativeUiIds.shellHeaderActions,
      NativeUiIds.shellSettingsAction,
      NativeUiIds.navDiscover,
      NativeUiIds.navMine,
      NativeUiIds.bottomDock,
      NativeUiIds.navPill,
      NativeUiIds.discoverTabContent,
      NativeUiIds.libraryTabContent
    ];
  }

  static discoverSelectors(): string[] {
    return [
      NativeUiIds.discoverPage
    ];
  }

  static searchSelectors(): string[] {
    return [
      NativeUiIds.searchInput,
      NativeUiIds.searchState,
      NativeUiIds.searchIdleState,
      NativeUiIds.searchLoadingState,
      NativeUiIds.searchEmptyState,
      NativeUiIds.searchErrorState,
      NativeUiIds.searchResults,
      NativeUiIds.searchLoadMoreError
    ];
  }

  static collectionSelectors(): string[] {
    return [
      NativeUiIds.collectionDetail,
      NativeUiIds.collectionDetailHeader,
      NativeUiIds.collectionDetailHeaderBack,
      NativeUiIds.collectionDetailHero,
      NativeUiIds.collectionDetailCover,
      NativeUiIds.collectionDetailName,
      NativeUiIds.collectionDetailMeta,
      NativeUiIds.collectionDetailToolbar,
      NativeUiIds.collectionDetailPlayAll,
      NativeUiIds.collectionDetailSelectToggle,
      NativeUiIds.collectionDetailSelectAll,
      NativeUiIds.collectionDetailExitSelect,
      NativeUiIds.collectionDetailBottomBar,
      NativeUiIds.collectionDetailAddSelected,
      NativeUiIds.collectionDetailErrorDismiss,
      NativeUiIds.collectionDetailFavoriteError,
      NativeUiIds.collectionDetailLoading,
      NativeUiIds.collectionDetailError,
      NativeUiIds.collectionDetailEmpty,
      NativeUiIds.collectionDetailList,
      NativeUiIds.collectionDetailUnavailable,
      NativeUiIds.collectionDetailBack
    ];
  }

  static loginSelectors(): string[] {
    return [
      NativeUiIds.loginPage,
      NativeUiIds.loginContent,
      NativeUiIds.loginIdle,
      NativeUiIds.loginStarting,
      NativeUiIds.loginQrContent,
      NativeUiIds.loginQrCode,
      NativeUiIds.loginQrUnavailable,
      NativeUiIds.loginExpired,
      NativeUiIds.loginError,
      NativeUiIds.loginCancelled,
      NativeUiIds.loginMessageStatus,
      NativeUiIds.loginRestart,
      NativeUiIds.loginAccountCard,
      NativeUiIds.loginAccountName,
      NativeUiIds.loginLogout,
      NativeUiIds.loginSheet,
      NativeUiIds.sheetScrim(NativeUiIds.loginSheet),
      NativeUiIds.sheetHandle(NativeUiIds.loginSheet)
    ];
  }

  static settingsSelectors(): string[] {
    return [
      NativeUiIds.settingsPage,
      NativeUiIds.settingsBack,
      NativeUiIds.settingsContent,
      NativeUiIds.settingsGeneralSection,
      NativeUiIds.settingsThemeMode,
      NativeUiIds.settingsThemeLight,
      NativeUiIds.settingsThemeDark,
      NativeUiIds.settingsThemeSystem,
      NativeUiIds.settingsDataSection,
      NativeUiIds.settingsDownloadQuality,
      NativeUiIds.settingsDownloadQualityLow,
      NativeUiIds.settingsDownloadQualityStandard,
      NativeUiIds.settingsDownloadQualityHigh,
      NativeUiIds.settingsDownloadQualityNote,
      NativeUiIds.settingsDownloadSection,
      NativeUiIds.settingsDownloadLimit,
      NativeUiIds.settingsPlaybackSection,
      NativeUiIds.settingsAudioQuality,
      NativeUiIds.settingsAudioQualityLow,
      NativeUiIds.settingsAudioQualityStandard,
      NativeUiIds.settingsAudioQualityHigh,
      NativeUiIds.settingsAudioQualityNote,
      NativeUiIds.settingsAutoPlay,
      NativeUiIds.settingsShowLyrics,
      NativeUiIds.settingsPlaybackSheet,
      NativeUiIds.settingsPlaybackSheetContent,
      NativeUiIds.settingsPlaybackSheetError,
      NativeUiIds.settingsCacheClear,
      NativeUiIds.settingsCacheError,
      NativeUiIds.settingsCacheRetry,
      NativeUiIds.settingsCacheSheet,
      NativeUiIds.settingsCacheSheetContent,
      NativeUiIds.settingsCacheSheetImages,
      NativeUiIds.settingsCacheSheetLyrics,
      NativeUiIds.settingsCacheSheetAudio,
      NativeUiIds.settingsCacheSheetClearAll,
      NativeUiIds.settingsCacheSheetError,
      NativeUiIds.settingsCacheSheetRetry,
      NativeUiIds.settingsWriteError,
      NativeUiIds.settingsOpenDiagnostics,
      NativeUiIds.settingsAboutSection,
      NativeUiIds.settingsAppVersion,
      NativeUiIds.settingsAuthor,
      NativeUiIds.settingsGithub,
      NativeUiIds.settingsLegal,
      NativeUiIds.settingsLegalSheet,
      NativeUiIds.settingsLegalSheetContent,
      NativeUiIds.diagnosticsSheet,
      NativeUiIds.settingsDownloadLimitOption(100),
      NativeUiIds.settingsDownloadLimitOption(300),
      NativeUiIds.settingsDownloadLimitOption(500),
      NativeUiIds.sheetScrim(NativeUiIds.settingsCacheSheet),
      NativeUiIds.sheetHandle(NativeUiIds.settingsCacheSheet),
      NativeUiIds.sheetScrim(NativeUiIds.settingsPlaybackSheet),
      NativeUiIds.sheetHandle(NativeUiIds.settingsPlaybackSheet),
      NativeUiIds.sheetScrim(NativeUiIds.settingsLegalSheet),
      NativeUiIds.sheetHandle(NativeUiIds.settingsLegalSheet),
      NativeUiIds.sheetScrim(NativeUiIds.diagnosticsSheet),
      NativeUiIds.sheetHandle(NativeUiIds.diagnosticsSheet)
    ];
  }

  static playerSelectors(): string[] {
    return [
      NativeUiIds.miniPlayer,
      NativeUiIds.miniPlayerTitle,
      NativeUiIds.miniPlayerArtist,
      NativeUiIds.miniPlayerExpand,
      NativeUiIds.miniPlayerToggle,
      NativeUiIds.miniPlayerNext,
      NativeUiIds.miniPlayerError,
      NativeUiIds.miniPlayerErrorTrack,
      NativeUiIds.miniPlayerRetry,
      NativeUiIds.playerPage,
      NativeUiIds.playerCover,
      NativeUiIds.playerTitle,
      NativeUiIds.playerArtist,
      NativeUiIds.playerLyricCurrent,
      NativeUiIds.playerLyricNext,
      NativeUiIds.playerLyricOpen,
      NativeUiIds.playerProgress,
      NativeUiIds.playerPosition,
      NativeUiIds.playerDuration,
      NativeUiIds.playerToggle,
      NativeUiIds.playerTrackActions,
      NativeUiIds.playerFavorite,
      NativeUiIds.playerNavDiscover,
      NativeUiIds.playerNavLibrary,
      NativeUiIds.playerSwipeStage,
      NativeUiIds.playerError,
      NativeUiIds.playerErrorTitle,
      NativeUiIds.playerErrorMessage,
      NativeUiIds.playerErrorTrackTitle,
      NativeUiIds.playerErrorTrackArtist,
      NativeUiIds.playerErrorRetry,
      NativeUiIds.playerEmpty,
      NativeUiIds.playerEmptyTitle,
      NativeUiIds.playerControlPanel,
      NativeUiIds.playerPanelBack,
      NativeUiIds.playerPanelAdd,
      NativeUiIds.playerPanelMode,
      NativeUiIds.playerPanelTimer,
      NativeUiIds.playerPanelDownload,
      NativeUiIds.playerPanelQuality
    ];
  }

  static sleepTimerSelectors(): string[] {
    return [
      NativeUiIds.sleepTimerSheet,
      NativeUiIds.sleepTimerContent,
      NativeUiIds.sleepTimerCancel,
      NativeUiIds.sheetScrim(NativeUiIds.sleepTimerSheet),
      NativeUiIds.sheetHandle(NativeUiIds.sleepTimerSheet),
      NativeUiIds.sleepTimerOption(15),
      NativeUiIds.sleepTimerOption(30),
      NativeUiIds.sleepTimerOption(45),
      NativeUiIds.sleepTimerOption(60),
      NativeUiIds.sleepTimerOption(90)
    ];
  }

  static audioQualitySelectors(): string[] {
    return [
      NativeUiIds.audioQualitySheet,
      NativeUiIds.audioQualityContent,
      NativeUiIds.audioQualitySaveError,
      NativeUiIds.audioQualityFooter,
      NativeUiIds.sheetScrim(NativeUiIds.audioQualitySheet),
      NativeUiIds.sheetHandle(NativeUiIds.audioQualitySheet),
      NativeUiIds.audioQualityOption('high'),
      NativeUiIds.audioQualityOption('standard'),
      NativeUiIds.audioQualityOption('low')
    ];
  }

  static downloadQualitySelectors(): string[] {
    return [
      NativeUiIds.downloadQualitySheet,
      NativeUiIds.downloadQualityContent,
      NativeUiIds.downloadQualitySaveError,
      NativeUiIds.downloadQualityFooter,
      NativeUiIds.sheetScrim(NativeUiIds.downloadQualitySheet),
      NativeUiIds.sheetHandle(NativeUiIds.downloadQualitySheet),
      NativeUiIds.downloadQualityOption('high'),
      NativeUiIds.downloadQualityOption('standard'),
      NativeUiIds.downloadQualityOption('low')
    ];
  }

  static trackActionSelectors(): string[] {
    return [
      NativeUiIds.trackActionSheet,
      NativeUiIds.trackActionContent,
      NativeUiIds.trackActionToast,
      NativeUiIds.trackActionDownload,
      NativeUiIds.sheetScrim(NativeUiIds.trackActionSheet),
      NativeUiIds.sheetHandle(NativeUiIds.trackActionSheet)
    ];
  }

  static queueSelectors(): string[] {
    return [
      NativeUiIds.queuePage,
      NativeUiIds.queueList,
      NativeUiIds.queueError,
      NativeUiIds.queueClear,
      NativeUiIds.queueEmpty,
      NativeUiIds.queueEmptyTitle,
      NativeUiIds.queueEmptyBack,
      NativeUiIds.queueEmptySearch
    ];
  }

  static librarySelectors(): string[] {
    return [
      NativeUiIds.minePage,
      NativeUiIds.mineHeader,
      NativeUiIds.mineAccountCard,
      NativeUiIds.mineAccountName,
      NativeUiIds.mineAccountAction,
      NativeUiIds.minePlaylistsContent,
      NativeUiIds.mineQuickActions,
      NativeUiIds.mineQuickLiked,
      NativeUiIds.mineQuickHistory,
      NativeUiIds.mineQuickDownloads,
      NativeUiIds.mineQuickCreate,
      NativeUiIds.mineQuickLikedPlay,
      NativeUiIds.mineQuickHistoryPlay,
      NativeUiIds.mineQuickDownloadsPlay,
      NativeUiIds.recentHeader,
      NativeUiIds.recentHeaderBack,
      NativeUiIds.recentError,
      NativeUiIds.recentErrorDismiss,
      NativeUiIds.recentEmpty,
      NativeUiIds.recentPlayAll,
      NativeUiIds.recentToolbar,
      NativeUiIds.recentSelect,
      NativeUiIds.recentSelectAll,
      NativeUiIds.recentExitSelect,
      NativeUiIds.recentBottomBar,
      NativeUiIds.recentRemoveSelected,
      NativeUiIds.recentAddSelected,
      NativeUiIds.recentList,
      NativeUiIds.downloadsPage,
      NativeUiIds.downloadsHeader,
      NativeUiIds.downloadsHeaderBack,
      NativeUiIds.downloadsError,
      NativeUiIds.downloadsErrorDismiss,
      NativeUiIds.downloadsEmpty,
      NativeUiIds.downloadsPlayAll,
      NativeUiIds.downloadsToolbar,
      NativeUiIds.downloadsSelect,
      NativeUiIds.downloadsSelectAll,
      NativeUiIds.downloadsExitSelect,
      NativeUiIds.downloadsBottomBar,
      NativeUiIds.downloadsRemoveSelected,
      NativeUiIds.downloadsList,
      NativeUiIds.favoritesError,
      NativeUiIds.favoritesErrorDismiss,
      NativeUiIds.favoritesEmpty,
      NativeUiIds.favoritesEmptySearch,
      NativeUiIds.favoritesPage,
      NativeUiIds.favoritesHeader,
      NativeUiIds.favoritesHeaderBack,
      NativeUiIds.favoritesHero,
      NativeUiIds.favoritesCover,
      NativeUiIds.favoritesToolbar,
      NativeUiIds.favoritesPlayAll,
      NativeUiIds.favoritesSelectToggle,
      NativeUiIds.favoritesSelectAll,
      NativeUiIds.favoritesExitSelect,
      NativeUiIds.favoritesList,
      NativeUiIds.favoritesBottomBar,
      NativeUiIds.favoritesDeleteSelected,
      NativeUiIds.favoritesAddSelected,
      NativeUiIds.playlistNameDialog,
      NativeUiIds.playlistNameInput,
      NativeUiIds.playlistNameError,
      NativeUiIds.playlistNameCancel,
      NativeUiIds.playlistNameConfirm,
      NativeUiIds.playlistError,
      NativeUiIds.playlistErrorDismiss,
      NativeUiIds.playlistCreateSheet,
      NativeUiIds.playlistCreateNameInput,
      NativeUiIds.playlistCreateError,
      NativeUiIds.playlistCreateConfirm,
      NativeUiIds.playlistList,
      NativeUiIds.playlistDetail,
      NativeUiIds.playlistDetailHeader,
      NativeUiIds.playlistDetailHeaderBack,
      NativeUiIds.playlistDetailEdit,
      NativeUiIds.playlistDetailHero,
      NativeUiIds.playlistDetailCover,
      NativeUiIds.playlistDetailName,
      NativeUiIds.playlistDetailDescription,
      NativeUiIds.playlistDetailToolbar,
      NativeUiIds.playlistDetailToolbarPlayAll,
      NativeUiIds.playlistDetailSelectToggle,
      NativeUiIds.playlistDetailSelectAll,
      NativeUiIds.playlistDetailExitSelect,
      NativeUiIds.playlistDetailBottomBar,
      NativeUiIds.playlistDetailDeleteSelected,
      NativeUiIds.playlistDetailAddSelected,
      NativeUiIds.playlistDetailError,
      NativeUiIds.playlistDetailErrorDismiss,
      NativeUiIds.playlistDetailEmpty,
      NativeUiIds.playlistDetailList,
      NativeUiIds.playlistDetailMissing,
      NativeUiIds.playlistDetailBack,
      NativeUiIds.playlistEditSheet,
      NativeUiIds.playlistEditCover,
      NativeUiIds.playlistEditNameInput,
      NativeUiIds.playlistEditDescriptionInput,
      NativeUiIds.playlistEditError,
      NativeUiIds.playlistEditSave,
      NativeUiIds.sheetScrim(NativeUiIds.playlistCreateSheet),
      NativeUiIds.sheetHandle(NativeUiIds.playlistCreateSheet),
      NativeUiIds.sheetScrim(NativeUiIds.playlistEditSheet),
      NativeUiIds.sheetHandle(NativeUiIds.playlistEditSheet)
    ];
  }

  static lyricsSelectors(): string[] {
    return [
      NativeUiIds.lyricsPanel,
      NativeUiIds.lyricsSheet,
      NativeUiIds.lyricsSheetTitle,
      NativeUiIds.lyricsSheetArtist,
      NativeUiIds.lyricsSheetPlay,
      NativeUiIds.lyricsCollapse,
      NativeUiIds.lyricsLoading,
      NativeUiIds.lyricsEmpty,
      NativeUiIds.lyricsError,
      NativeUiIds.lyricsCandidatesLoading,
      NativeUiIds.lyricsCandidatesEmpty,
      NativeUiIds.lyricsCandidatesEmptyRetry,
      NativeUiIds.lyricsCandidatesError,
      NativeUiIds.lyricsCandidatesRetry,
      NativeUiIds.lyricsCandidatesList,
      NativeUiIds.lyricsCandidateSelectionError,
      NativeUiIds.lyricsSyncedList,
      NativeUiIds.lyricsUnsyncedList,
      NativeUiIds.lyricsUnsyncedLabel,
      NativeUiIds.lyricsErrorRetry,
      NativeUiIds.lyricsCandidatesSheet,
      NativeUiIds.sheetScrim(NativeUiIds.lyricsCandidatesSheet),
      NativeUiIds.sheetHandle(NativeUiIds.lyricsCandidatesSheet)
    ];
  }

  /** 曲目操作抽屉：面板 / 蒙层 / 拖拽条 + 内容根。 */
  static queueRow(index: number): string {
    return `queue-row-${index}`;
  }

  /**
   * 共用底部弹层（`BottomSheet`）的选择器派生规则：面板本体用 `sheetId`，
   * 蒙层 / 拖拽条分别是 `-scrim` / `-handle`。
   * 写成函数而不是再声明一堆字面量：所有抽屉（登录 / 曲目操作 / 诊断 /
   * 歌词换源）共用同一个外壳，选择器只在这一处派生。
   */
  static sheetScrim(sheetId: string): string {
    return `${sheetId}-scrim`;
  }

  static sheetHandle(sheetId: string): string {
    return `${sheetId}-handle`;
  }

  /** 定时关闭抽屉里的分钟档位行：`sleep-timer-option-15`。 */
  static sleepTimerOption(minutes: number): string {
    return `sleep-timer-option-${minutes}`;
  }

  /** 音质抽屉里的档位行：`audio-quality-option-high`。 */
  static audioQualityOption(quality: string): string {
    return `audio-quality-option-${quality}`;
  }

  /** 下载品质抽屉里的档位行：`download-quality-option-high`。 */
  static downloadQualityOption(quality: string): string {
    return `download-quality-option-${quality}`;
  }

  /** 设置页下载上限的分段格：`settings-download-limit-500`。 */
  static settingsDownloadLimitOption(limit: number): string {
    return `settings-download-limit-${limit}`;
  }

  static queueRemove(index: number): string {
    return `queue-remove-${index}`;
  }

  /** 动态 id：队列行更多操作，不进入 `all()`。 */
  static queueMore(index: number): string {
    return `queue-more-${index}`;
  }

  static recentRow(index: number): string {
    return `recent-row-${index}`;
  }

  static recentMore(index: number): string {
    return `recent-more-${index}`;
  }

  /** 历史行右侧的收藏按钮：点击即加入 / 移出「我喜欢的」。 */
  static recentFavorite(index: number): string {
    return `recent-favorite-${index}`;
  }

  static downloadsRow(index: number): string {
    return `downloads-row-${index}`;
  }

  static downloadsMore(index: number): string {
    return `downloads-more-${index}`;
  }

  static downloadsFavorite(index: number): string {
    return `downloads-favorite-${index}`;
  }

  static favoriteRow(index: number): string {
    return `favorite-row-${index}`;
  }

  static favoriteRemove(index: number): string {
    return `favorite-remove-${index}`;
  }

  static favoriteMore(index: number): string {
    return `favorite-more-${index}`;
  }

  static playlistRow(index: number): string {
    return `playlist-row-${index}`;
  }

  static minePlaylistCover(index: number): string {
    return `mine-playlist-cover-${index}`;
  }

  static minePlaylistPlay(index: number): string {
    return `mine-playlist-play-${index}`;
  }

  static playlistRename(index: number): string {
    return `playlist-rename-${index}`;
  }

  static playlistDelete(index: number): string {
    return `playlist-delete-${index}`;
  }

  static playlistDetailRow(index: number): string {
    return `playlist-detail-row-${index}`;
  }

  static playlistDetailRemove(index: number): string {
    return `playlist-detail-remove-${index}`;
  }

  static playlistDetailAppend(index: number): string {
    return `playlist-detail-append-${index}`;
  }

  static playlistDetailPlay(index: number): string {
    return `playlist-detail-play-${index}`;
  }

  /** 曲目行右侧收藏键：空心 / 实心爱心直接反映是否已收藏。 */
  static playlistDetailFavorite(index: number): string {
    return `playlist-detail-favorite-${index}`;
  }

  /** 曲目行右侧更多键：打开曲目操作抽屉。 */
  static playlistDetailMoreAction(index: number): string {
    return `playlist-detail-more-action-${index}`;
  }

  /** 合集详情行：`collection-detail-row-0`。 */
  static collectionDetailRow(index: number): string {
    return `collection-detail-row-${index}`;
  }

  static collectionDetailFavorite(index: number): string {
    return `collection-detail-favorite-${index}`;
  }

  static collectionDetailMoreAction(index: number): string {
    return `collection-detail-more-action-${index}`;
  }

  static lyricsLine(index: number): string {
    return `lyrics-line-${index}`;
  }

  static lyricsCandidate(id: string): string {
    return `lyrics-candidate-${id}`;
  }

  static all(): string[] {
    return NativeUiIds.shellSelectors()
      .concat(NativeUiIds.discoverSelectors())
      .concat(NativeUiIds.searchSelectors())
      .concat(NativeUiIds.collectionSelectors())
      .concat(NativeUiIds.loginSelectors())
      .concat(NativeUiIds.settingsSelectors())
      .concat(NativeUiIds.playerSelectors())
      .concat(NativeUiIds.sleepTimerSelectors())
      .concat(NativeUiIds.audioQualitySelectors())
      .concat(NativeUiIds.downloadQualitySelectors())
      .concat(NativeUiIds.trackActionSelectors())
      .concat(NativeUiIds.queueSelectors())
      .concat(NativeUiIds.librarySelectors())
      .concat(NativeUiIds.lyricsSelectors())
  }
}
