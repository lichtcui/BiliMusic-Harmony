export class ThemeColors {
  static readonly bg: Resource = $r('app.color.native_bg');
  /**
   * 系统启动窗口的底色（module.json5 的 `startWindowBackground`）。
   * App 启动页与系统启动页取同一资源，首帧接手时不闪色；它也是唯一允许
   * 不经 `ThemeColors` 门面的资源键，这里显式收进门面，避免页面直接写 `$r`。
   */
  static readonly startWindowBackground: Resource = $r('app.color.start_window_background');
  /** 启动页深底上的进度指示（与 app 图标的奶油色同族，两套主题共用）。 */
  static readonly onSplash: Resource = $r('app.color.native_on_splash');
  /** 播放页画布：与页面底同为微暖白；卡面 / 浮层才用纯白 `surface`（「纸叠纸」）。 */
  static readonly playerCanvas: Resource = $r('app.color.native_player_canvas');
  static readonly surface: Resource = $r('app.color.native_surface');
  /** 登录 / 账号抽屉画布，也是全仓抽屉的统一画布：light 与页面底同为微暖白、dark 用 surface。 */
  static readonly loginSheetSurface: Resource = $r('app.color.native_login_sheet_surface');
  /** 歌词面板上下渐隐：与抽屉画布同色、alpha 0，避免用 Color.Transparent 插值出黑边。 */
  static readonly sheetFade: Resource = $r('app.color.native_sheet_fade');
  static readonly surfaceInset: Resource = $r('app.color.native_surface_inset');
  static readonly textPrimary: Resource = $r('app.color.native_text_primary');
  static readonly textSecondary: Resource = $r('app.color.native_text_secondary');
  static readonly accent: Resource = $r('app.color.native_accent');
  static readonly accentSoft: Resource = $r('app.color.native_accent_soft');
  /**
   * 「正在播放」的标记色与标题色：标记沿用 app 图标音乐发夹的原色（`logoOrange500`），
   * 标题取同色相加深/提亮一档保证可读；当前行不铺底色，靠这两色区分。
   */
  static readonly nowPlayingMark: Resource = $r('app.color.native_now_playing_mark');
  static readonly nowPlaying: Resource = $r('app.color.native_now_playing');
  static readonly chipUnselected: Resource = $r('app.color.native_chip_unselected');
  static readonly line: Resource = $r('app.color.native_line');
  static readonly sheetHandle: Resource = $r('app.color.native_sheet_handle');
  /** 功能页里横贯整宽的分隔线，比通用 `line` 重一档（09 稿）。 */
  static readonly sheetDivider: Resource = $r('app.color.native_sheet_divider');
  static readonly accentAction: Resource = $r('app.color.native_accent_action');
  static readonly onAccentAction: Resource = $r('app.color.native_on_accent_action');
  /** 「我的」页快捷方块：我喜欢的黄底 / 图标，新建歌单虚线框。 */
  static readonly quickLikedSurface: Resource = $r('app.color.native_quick_liked_surface');
  static readonly quickLikedContent: Resource = $r('app.color.native_quick_liked_content');
  static readonly quickCreateOutline: Resource = $r('app.color.native_quick_create_outline');
  /** 功能页五宫格的方块底与图标色（09 稿）。 */
  static readonly actionTile: Resource = $r('app.color.native_action_tile');
  static readonly onActionTile: Resource = $r('app.color.native_on_action_tile');
  /**
   * 扫码登录二维码的纸面与墨色（「我的」页设计稿 v2）。
   * 两个角色随主题各取一组 primitive：light 为微绿纸 + 深墨，dark 为稍暗纸面 + 近黑墨。
   * 深浅两套都保持「浅纸 + 深墨」的高对比，扫码不会因为反色失效。
   */
  static readonly qrPaper: Resource = $r('app.color.native_qr_paper');
  static readonly qrInk: Resource = $r('app.color.native_qr_ink');
  /** 「我的」页新稿：危险动作（退出登录）的文字与描边（描边为 42% 混色）。 */
  static readonly danger: Resource = $r('app.color.native_danger');
  static readonly dangerBorder: Resource = $r('app.color.native_danger_border');
  static readonly iconOnInset: Resource = $r('app.color.native_icon_on_inset');
  /**
   * 分段选择器的选中滑块。新稿改用 accent：选中文字落在滑块上仍是 `onAccent`，
   * 深色下 accent 变浅、onAccent 变深，两种模式都保持可读。
   */
  static readonly segmentThumb: Resource = $r('app.color.native_segment_thumb');
  /** 悬浮 dock（导航胶囊 + 迷你播放器）的唯一阴影色。 */
  static readonly dockShadow: Resource = $r('app.color.native_dock_shadow');
  static readonly progressTrack: Resource = $r('app.color.native_progress_track');
  static readonly controlTrack: Resource = $r('app.color.native_control_track');
  static readonly controlThumb: Resource = $r('app.color.native_control_thumb');
  static readonly onAccent: Resource = $r('app.color.native_on_accent');
  static readonly iconInactive: Resource = $r('app.color.native_icon_inactive');
  static readonly scrim: Resource = $r('app.color.native_scrim');
}

export class ThemeTypography {
  static readonly display: number = 30;
  static readonly pageTitle: number = 28;
  static readonly sectionTitle: number = 24;
  static readonly body: number = 15;
  static readonly caption: number = 14;
  static readonly eyebrow: number = 13;
  /** 悬浮 dock 导航胶囊的标签；旧底栏的 13 号 tab 已随底栏移除。 */
  static readonly dockLabel: number = 11;

  static readonly displayLineHeight: number = 36;
  static readonly pageTitleLineHeight: number = 34;
  static readonly bodyLineHeight: number = 22;

  static readonly playerTitle: number = 28;
  static readonly playerTitleLineHeight: number = 34;
  static readonly playerMeta: number = 14;
  static readonly playerLyric: number = 16;
  static readonly playerLyricLineHeight: number = 26;
  /** 播放页歌词预览：当前行（08 稿 17/29）与下一行（15/26）。 */
  static readonly playerLyricCurrent: number = 17;
  static readonly playerLyricCurrentLineHeight: number = 29;
  static readonly playerLyricNextLine: number = 15;
  static readonly playerLyricNextLineHeight: number = 26;
  static readonly playerLyricNext: number = 13;
  static readonly playerLyricNextLineHeightSmall: number = 22;
  static readonly playerTime: number = 11;
  /** 歌词面板：常规行 17/24、当前行 24/32。 */
  static readonly lyricsLine: number = 17;
  static readonly lyricsLineHeight: number = 24;
  static readonly lyricsLineActive: number = 24;
  static readonly lyricsLineActiveHeight: number = 32;
  /** 歌词面板底部「收起歌词」胶囊：13 / 500。 */
  static readonly lyricsCollapse: number = 13;
  /** 功能页（09 稿）：行副标题与按钮说明 12。 */
  static readonly playerPanelMeta: number = 12;
  /** 设置整页的分组小标题（新稿实测 12 / 500）。 */
  static readonly groupLabel: number = 12;
  /** 整页头部标题（设置页稿件实测 20 / 700；与登录抽屉标题同一档）。 */
  static readonly pageHeaderTitle: number = 20;

  /** 「我的」页新稿：页头昵称 17、分段标题 16、列表行标题 16、行副题 12、导入行 14。 */
  static readonly profileName: number = 17;
  static readonly sectionTab: number = 16;
  static readonly listTitle: number = 16;
  static readonly meta: number = 12;
  static readonly importLabel: number = 14;
  /** 悬浮 dock 迷你播放器：标题 13、作者 11。 */
  static readonly miniPlayerTitle: number = 13;
  static readonly miniPlayerMeta: number = 11;
  /** 下载 / 历史 / 歌单空态标题（设计稿 22/30）。 */
  static readonly emptyTitle: number = 22;
}

export class ThemeSpacing {
  static readonly xs: number = 4;
  static readonly sm: number = 8;
  static readonly md: number = 12;
  static readonly lg: number = 16;
  static readonly xl: number = 20;
  /** 页面左右 24 的通用页边距；新「我的」页的页头、分段与列表共用这条基线。 */
  static readonly gutter: number = 24;
  static readonly xxl: number = 28;
}

export class ThemeRadius {
  static readonly sm: number = 4;
  /** 列表封面 / 「我喜欢的」色块的 6 圆角（10 稿实测 rx=6）。 */
  static readonly tile: number = 6;
  static readonly md: number = 8;
  static readonly lg: number = 12;
  /** 登录卡片等大面积容器的 14 圆角。 */
  static readonly card: number = 14;
  /** 抽屉顶边圆角：2026-11 起对齐 M3 大弹层，16 → 28，展开后不再收敛成方角。 */
  static readonly sheet: number = 28;
  /** 底部弹层顶边圆角（20pt）。 */
  static readonly xl: number = 20;
  /** 描边动作按钮的 10 圆角（设置页重试、登录动作稿件实测）。 */
  static readonly control: number = 10;
}

export class ThemeSize {
  static readonly routeButtonHeight: number = 40;
  /** 每个一级 tab 内容底部为悬浮 dock 预留的高度：56 dock + 20 底距 + 8 余量。 */
  static readonly dockReserve: number = 84;
  static readonly pageTitleBlock: number = 72;
  static readonly listRowHeight: number = 56;
  static readonly coverSize: number = 48;
  static readonly coverCornerRadius: number = ThemeRadius.sm;
  static readonly coverPlaceholderMark: number = 18;
  static readonly coverAspectRatio: number = 1;
  static readonly emptyContentMinHeight: number = 280;
  static readonly loadingIndicator: number = 32;
  /**
   * 启动页 logo：直接复用 app_icon。系统启动窗口的图标实测为 512px（本机 3.375
   * density 下约 152vp）；App 启动页必须同尺寸，否则首帧接手时会看到图标缩放。
   */
  static readonly startupLogo: number = 152;
  static readonly startupLogoRadius: number = 34;
  /** 转圈的固定位置：不参与图标居中，出现时图标不位移。 */
  static readonly startupSpinnerOffsetY: number = 110;
  static readonly startupSpinnerAreaHeight: number = 240;

  /** Player stage uses a single paper column with a fixed 32 vp gutter. */
  static readonly playerGutter: number = 32;
  static readonly playerCoverRadius: number = 4;
  static readonly playerActionHeight: number = 64;
  static readonly playerActionWidth: number = 176;
  static readonly playerActionRadius: number = 24;
  static readonly playerNavIcon: number = 22;
  static readonly playerAddonIcon: number = 24;
  static readonly playerProgressThickness: number = 2;
  static readonly playerProgressBlock: number = 12;
  static readonly playerProgressHeight: number = 28;
  static readonly playerLyricBlockHeight: number = 56;
  static readonly playerSwipeCommitRatio: number = 0.14;
  static readonly playerSwipeVelocity: number = 520;

  /** 歌词面板行高：常规行 40、当前行 48。 */
  static readonly lyricsRowHeight: number = 40;
  static readonly lyricsRowActiveHeight: number = 48;
}
