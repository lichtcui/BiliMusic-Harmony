import { ThemeColors } from '../../theme/NativeTheme';

/**
 * 全应用统一的线性图标集（2026-11 替换版）。
 *
 * 图形来自 SVG Repo（https://www.svgrepo.com/），按语义落成 `resources/base/media/*.svg`，
 * 由 `Image` 载入后用 `colorFilter` 染成调用方给的主题角色色：
 * - 播放 / 暂停：实心三角 / 双竖条，对齐 design/mine-page.html 的 #i-play、#i-pause
 * - 爱心：532468/heart-alt（描边 1.8，对齐设计稿）；`HeartFilled` 是同路径的实心版，
 *   只用于「已收藏」状态，让收藏与否在形状上也能区分，而不只是换颜色
 * - 更多：422492/dot-menu-more-2
 * - 编辑：SVG Repo edit（方框 + 铅笔），歌单详情顶栏「修改歌单信息」专用；填充型，走 fillColor
 * - 发现：圆环 + 四角星，对齐 design/mine-page.html 的 #i-discover
 * - 我的：描边头像，对齐 design/mine-page.html 的 #i-person
 * - 返回：494008/back
 * - 关闭：紧凑 × 用于列表内的收起（如反馈条）；所有底部抽屉的右上关闭按钮统一用
 *   design/mine-page.html 的 #i-close 通栏 ×（`CloseLarge`，由 `BottomSheet` 固定）
 * - 搜索：532555/search
 * - 加歌单：348548/add-to-list
 * - 夜晚：487620/night
 * - 下载：实心箭头 + 托盘，走 fillColor
 * - 音质：506325/sound-2
 * - 设置：520937/setting-gear（描边 1.8，对齐设计稿）
 * - 新建歌单 / 加入歌单的加号：对齐 design/mine-page.html 的 #i-add，两者共用同一份资源
 * - 向右：522644/right-2
 * - 导入 / 导出：376118/list-indent、376122/list-outdent
 * - 登录 / 登出：507769/login、507772/logout
 * - 下一首 / 竖向更多：新「我的」页 dock 与历史行使用（HTML 内联路径）
 * - 多选：对齐 design/mine-page.html 的 #i-list-check
 * - 历史：对齐 design/mine-page.html 的 #i-clock（时钟 + 回环箭头；描边 + 填充混合，走 colorFilter）
 * - 相机：编辑歌单抽屉的更换封面徽标（design/playlist-create-sheet.html cover-badge）
 *
 * 染色口径：填充型图标（fill）走 `Image.fillColor`，描边型图标（stroke）走
 * `Image.colorFilter`。这是 ArkUI 的两条稳定路径：描边图用 `fillColor` 没反应，填充图用
 * `colorFilter` 在未开 `supportSvg2` 时不保证生效；不打开 `supportSvg2` 可以避免 SVG2
 * 解析口径改变图标外观。两条路径都接受 `ResourceColor`，因此颜色只从 `ThemeColors`
 * 角色传入，换色 / 深色模式不需要再复制一套深色资源。
 */
export enum AppIconKind {
  Play = 0,
  Pause = 1,
  Heart = 2,
  More = 3,
  Discover = 4,
  Person = 5,
  Back = 6,
  Close = 7,
  Search = 8,
  PlaylistAdd = 9,
  Night = 10,
  Download = 11,
  Quality = 12,
  Settings = 13,
  CreatePlaylist = 14,
  ChevronRight = 15,
  Import = 16,
  Export = 17,
  Login = 18,
  Logout = 19,
  Brush = 20,
  Next = 21,
  MoreVertical = 22,
  ListCheck = 23,
  CloseLarge = 24,
  HeartFilled = 25,
  /** 歌单空态的音乐符（design/playlist-page.html #i-note，描边 1.8）。 */
  Note = 26,
  /** 多选态的勾选标记（design/playlist-page.html #i-check，描边 2.6）。 */
  Check = 27,
  /** 多选入口：列表 + 圆点（design/playlist-page.html #i-select-list）。 */
  SelectList = 28,
  /** 「全选」未勾选 / 已勾选（design/playlist-page.html #i-checkbox-*）。 */
  CheckboxUnchecked = 29,
  CheckboxChecked = 30,
  /** 多选底栏「删除」（design/playlist-page.html #i-trash）。 */
  Trash = 31,
  /** 多选底栏「添加到」（design/playlist-page.html #i-add-square）。 */
  AddSquare = 32,
  /** 编辑歌单抽屉里封面右下角的「更换封面」相机徽标（design/playlist-create-sheet.html cover-badge）。 */
  Camera = 33,
  /** 歌词面板底部「收起歌词」的下箭头（design/lyrics-page.html #i-chevron-down）。 */
  ChevronDown = 34,
  /** 加号：复用「新建歌单」的同一份加号资源（design/track-action-sheet.html #i-plus）。 */
  Plus = 35,
  /** 「历史」快捷方块：时钟 + 回环箭头（design/mine-page.html #i-clock，描边 + 填充混合）。 */
  Clock = 36,
  /** 歌单详情顶栏「修改歌单信息」：SVG Repo edit（design/playlist-page.html #i-edit，填充型）。 */
  Edit = 37
}

function iconResource(kind: AppIconKind): Resource {
  if (kind === AppIconKind.Pause) {
    return $r('app.media.ic_pause');
  }
  if (kind === AppIconKind.Heart) {
    return $r('app.media.ic_heart');
  }
  if (kind === AppIconKind.HeartFilled) {
    return $r('app.media.ic_heart_filled');
  }
  if (kind === AppIconKind.More) {
    return $r('app.media.ic_more');
  }
  if (kind === AppIconKind.Edit) {
    return $r('app.media.ic_edit');
  }
  if (kind === AppIconKind.Discover) {
    return $r('app.media.ic_discover');
  }
  if (kind === AppIconKind.Person) {
    return $r('app.media.ic_person');
  }
  if (kind === AppIconKind.Back) {
    return $r('app.media.ic_back');
  }
  if (kind === AppIconKind.Close) {
    return $r('app.media.ic_close');
  }
  if (kind === AppIconKind.Search) {
    return $r('app.media.ic_search');
  }
  if (kind === AppIconKind.PlaylistAdd) {
    return $r('app.media.ic_playlist_add');
  }
  if (kind === AppIconKind.Night) {
    return $r('app.media.ic_night');
  }
  if (kind === AppIconKind.Download) {
    return $r('app.media.ic_download');
  }
  if (kind === AppIconKind.Quality) {
    return $r('app.media.ic_quality');
  }
  if (kind === AppIconKind.Settings) {
    return $r('app.media.ic_settings');
  }
  if (kind === AppIconKind.CreatePlaylist) {
    return $r('app.media.ic_create_playlist');
  }
  if (kind === AppIconKind.Plus) {
    return $r('app.media.ic_create_playlist');
  }
  if (kind === AppIconKind.ChevronRight) {
    return $r('app.media.ic_chevron_right');
  }
  if (kind === AppIconKind.ChevronDown) {
    return $r('app.media.ic_chevron_down');
  }
  if (kind === AppIconKind.Import) {
    return $r('app.media.ic_import');
  }
  if (kind === AppIconKind.Export) {
    return $r('app.media.ic_export');
  }
  if (kind === AppIconKind.Login) {
    return $r('app.media.ic_login');
  }
  if (kind === AppIconKind.Logout) {
    return $r('app.media.ic_logout');
  }
  if (kind === AppIconKind.Brush) {
    return $r('app.media.ic_brush');
  }
  if (kind === AppIconKind.Next) {
    return $r('app.media.ic_next');
  }
  if (kind === AppIconKind.MoreVertical) {
    return $r('app.media.ic_more_vertical');
  }
  if (kind === AppIconKind.ListCheck) {
    return $r('app.media.ic_list_check');
  }
  if (kind === AppIconKind.CloseLarge) {
    return $r('app.media.ic_close_large');
  }
  if (kind === AppIconKind.Note) {
    return $r('app.media.ic_note');
  }
  if (kind === AppIconKind.Check) {
    return $r('app.media.ic_check');
  }
  if (kind === AppIconKind.SelectList) {
    return $r('app.media.ic_select_list');
  }
  if (kind === AppIconKind.CheckboxUnchecked) {
    return $r('app.media.ic_checkbox_unchecked');
  }
  if (kind === AppIconKind.CheckboxChecked) {
    return $r('app.media.ic_checkbox_checked');
  }
  if (kind === AppIconKind.Trash) {
    return $r('app.media.ic_trash');
  }
  if (kind === AppIconKind.AddSquare) {
    return $r('app.media.ic_add_square');
  }
  if (kind === AppIconKind.Camera) {
    return $r('app.media.ic_camera');
  }
  if (kind === AppIconKind.Clock) {
    return $r('app.media.ic_clock');
  }
  return $r('app.media.ic_play');
}

/** 该图标的图形是填充（fill）还是描边（stroke），决定走哪条染色 API。 */
function isFilledArtwork(kind: AppIconKind): boolean {
  return kind === AppIconKind.Play ||
    kind === AppIconKind.Pause ||
    kind === AppIconKind.HeartFilled ||
    kind === AppIconKind.More ||
    kind === AppIconKind.Edit ||
    kind === AppIconKind.MoreVertical ||
    kind === AppIconKind.Next ||
    kind === AppIconKind.Back ||
    kind === AppIconKind.Night ||
    kind === AppIconKind.Import ||
    kind === AppIconKind.Export ||
    kind === AppIconKind.Download;
}

/**
 * 一枚图标：`iconSize` 是外框边长（vp），`iconColor` 必须是主题角色（或由状态推导的角色），
 * 不要在调用方写十六进制色值。
 */
@Component
export struct AppIcon {
  /*
   * 三个入参必须是 @Prop：未装饰的普通成员只在构造时赋值，编译器生成的 `updateStateVars()`
   * 是空函数，父组件重绘时新值传不进子组件。爱心、播放/暂停这类「同一组件换图形」的调用点
   * 会因此停在旧图标上，直到行被销毁重建（退出重进页面）才更新。
   */
  @Prop iconKind: AppIconKind = AppIconKind.Play;
  @Prop iconSize: number = 20;
  @Prop iconColor: ResourceColor = ThemeColors.textPrimary;

  build() {
    if (isFilledArtwork(this.iconKind)) {
      Image(iconResource(this.iconKind))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .fillColor(this.iconColor)
        .draggable(false)
    } else {
      Image(iconResource(this.iconKind))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .colorFilter(this.iconColor)
        .draggable(false)
    }
  }
}