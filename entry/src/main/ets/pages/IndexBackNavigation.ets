export enum IndexBackAction {
  CloseDiagnostics = 0,
  CloseLoginSheet = 1,
  CloseTrackActions = 2,
  PopRoute = 3,
  OpenRootTab = 4,
  AllowSystemExit = 5,
  CloseSettingsPage = 6,
  /** 播放页「功能键」整页（根 Stack 覆盖层，2026-11 从底部抽屉改成右侧滑入）。 */
  ClosePlayerControlPanel = 7,
  /** 「新建歌单」抽屉（根 Stack 覆盖层，+ 号入口）。 */
  ClosePlaylistCreate = 8,
  /** 「修改歌单信息」抽屉（根 Stack 覆盖层，歌单详情页右上角入口）。 */
  ClosePlaylistEdit = 9,
  /** 缓存清理抽屉（设置页「缓存清理」行入口，叠在设置整页之上）。 */
  CloseCacheSheet = 10,
  /** 法律与免责声明抽屉（设置页「关于」组入口，同样叠在设置整页之上）。 */
  CloseLegalSheet = 11,
  /** 「定时关闭」抽屉（播放控制功能页入口，叠在功能整页之上）。 */
  CloseSleepTimer = 12,
  /** 「音质选择」抽屉（播放控制功能页 / 设置页入口，叠在对应页面之上）。 */
  CloseAudioQuality = 13,
  /** 「播放设置」抽屉（设置页「常规 › 播放设置」入口，叠在设置整页之上）。 */
  ClosePlaybackSheet = 14
}

/**
 * 根 tab（「我的」）在 Tabs 中的索引；系统 Back 从其余 tab 回到这里。
 *
 * 首页是「我的」而不是「发现」：Tabs 首次只构建当前页签，默认落在「我的」可以让
 * 发现页的数据拉取完全推迟到用户主动切过去（见 `Index.selectedTab` 的初值）。
 */
export const INDEX_ROOT_TAB: number = 1;
/** 「发现」页签的索引；它不再是默认页，只由 dock 胶囊 / 显式跳转进入。 */
export const INDEX_DISCOVER_TAB: number = 0;
/** 阶段 1a 的根 tab 数量：发现 / 我的。中央胶囊是叠加层，不占 tab。 */
export const INDEX_TAB_COUNT: number = 2;

export interface IndexBackContext {
  /**
   * 诊断覆盖层：启动失败时的整页诊断，或设置页「打开诊断信息」弹出的诊断抽屉。
   * 两者都叠在最上层，合用一个开关按"先关闭"处理。
   */
  diagnosticsVisible: boolean;
  /**
   * 缓存清理抽屉：由设置整页的「缓存清理」行弹出，叠在设置页之上；
   * 与诊断抽屉同一层，所以也先于设置页关闭。
   */
  cacheSheetVisible?: boolean;
  /**
   * 法律与免责声明抽屉：由设置整页「关于」组弹出，叠在设置页之上；
   * 与诊断 / 缓存抽屉同一层，所以也先于设置页关闭。
   */
  legalSheetVisible?: boolean;
  /**
   * 播放设置抽屉：由设置整页「常规 › 播放设置」行弹出，叠在设置页之上；
   * 与诊断 / 缓存 / 免责声明抽屉同一层，所以也先于设置页关闭。
   */
  playbackSheetVisible?: boolean;
  /**
   * 音质选择抽屉：播放控制功能页 / 设置页共用，叠在对应页面之上；
   * 必须先于设置页和播放控制功能页关闭。
   */
  audioQualitySheetVisible?: boolean;
  /** 07 设置整页（Stack 覆盖层，2026-11 从底部抽屉改成整页右滑）。 */
  settingsPageVisible: boolean;
  /** 08 登录抽屉（阶段 1c 起是 Stack 覆盖层，不再是路由）。 */
  loginSheetVisible: boolean;
  trackActionsVisible: boolean;
  /** 播放页「功能键」整页；与曲目弹层同为根 Stack 覆盖层，关闭顺序在路由之前。 */
  playerControlPanelVisible: boolean;
  /** 「定时关闭」抽屉：从播放控制功能页弹出，必须比功能页更先关闭。 */
  sleepTimerSheetVisible?: boolean;
  /** 「新建歌单」抽屉（+ 号入口）；与其它抽屉一样先关覆盖层。 */
  playlistCreateVisible?: boolean;
  /** 「修改歌单信息」抽屉（歌单详情页入口）；同样先关覆盖层再退路由。 */
  playlistEditVisible?: boolean;
  routeCount: number;
  selectedTab: number;
}

/**
 * 系统 Back 的处置顺序：诊断（整页 / 抽屉）→ 缓存清理抽屉 → 免责声明抽屉 → 播放设置抽屉 →
 * 音质选择抽屉 → 设置整页 → 登录抽屉 → 曲目操作弹层 → 新建歌单抽屉 → 修改歌单抽屉 → 定时关闭抽屉 →
 * 播放页功能整页 → 路由栈 → 根 tab。
 *
 * 前十一个都是覆盖层，按「后出现的先关」处理：诊断 / 缓存清理 / 免责声明 / 播放设置四个抽屉
 * 都装在设置整页之上，所以先关它们；音质抽屉可由设置页或播放控制页打开，必须先于两者关闭；
 * 设置整页又挂在登录抽屉之后（视觉在上），所以先关设置；登录抽屉又先于曲目弹层；
 * 新建 / 修改歌单抽屉只由资料库页面打开，排在曲目弹层之后、路由之前。
 */
export function resolveIndexBackAction(context: IndexBackContext): IndexBackAction {
  if (context.diagnosticsVisible) {
    return IndexBackAction.CloseDiagnostics;
  }
  if (context.cacheSheetVisible === true) {
    return IndexBackAction.CloseCacheSheet;
  }
  if (context.legalSheetVisible === true) {
    return IndexBackAction.CloseLegalSheet;
  }
  if (context.playbackSheetVisible === true) {
    return IndexBackAction.ClosePlaybackSheet;
  }
  if (context.audioQualitySheetVisible === true) {
    return IndexBackAction.CloseAudioQuality;
  }
  if (context.settingsPageVisible) {
    return IndexBackAction.CloseSettingsPage;
  }
  if (context.loginSheetVisible) {
    return IndexBackAction.CloseLoginSheet;
  }
  if (context.trackActionsVisible) {
    return IndexBackAction.CloseTrackActions;
  }
  if (context.playlistCreateVisible === true) {
    return IndexBackAction.ClosePlaylistCreate;
  }
  if (context.playlistEditVisible === true) {
    return IndexBackAction.ClosePlaylistEdit;
  }
  if (context.sleepTimerSheetVisible === true) {
    return IndexBackAction.CloseSleepTimer;
  }
  if (context.playerControlPanelVisible) {
    return IndexBackAction.ClosePlayerControlPanel;
  }
  if (context.routeCount > 0) {
    return IndexBackAction.PopRoute;
  }
  if (context.selectedTab !== INDEX_ROOT_TAB) {
    return IndexBackAction.OpenRootTab;
  }
  return IndexBackAction.AllowSystemExit;
}

/**
 * Tabs 的索引只允许落在 0..INDEX_TAB_COUNT-1：越界数值夹到最近的合法页签，
 * NaN 这种无法判断方向的非法值回到根 tab（「我的」）。
 * 下界必须用 `INDEX_DISCOVER_TAB` 而不是 `INDEX_ROOT_TAB`——根 tab 现在是 1，
 * 拿它当下界会把「发现」（0）一起判成越界，dock 胶囊就再也切不过去了。
 */
export function clampTabIndex(index: number): number {
  if (Number.isNaN(index)) {
    return INDEX_ROOT_TAB;
  }
  const truncated = Math.trunc(index);
  if (truncated < INDEX_DISCOVER_TAB) {
    return INDEX_DISCOVER_TAB;
  }
  if (truncated > INDEX_TAB_COUNT - 1) {
    return INDEX_TAB_COUNT - 1;
  }
  return truncated;
}
