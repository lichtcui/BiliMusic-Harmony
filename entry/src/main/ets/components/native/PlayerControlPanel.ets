import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { DownloadStore } from '../../state/DownloadStore';
import { PlayerStore } from '../../state/PlayerStore';
import { SettingsStore } from '../../state/SettingsStore';
import { SleepTimerStore } from '../../state/SleepTimerStore';
import { MobileTrack } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { NativeUiIds } from './NativeUiIds';
import { RuntimeCoverImageProvider } from './RuntimeCoverImageProvider';
import { PlayerPageState } from './PlayerPageState';
import { QueueList } from './QueueList';
import { QueuePageState } from './QueuePageState';
import {
  ThemeColors,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';

/** 整页头部与设置页同构：返回 40 / 图标 22 / 标题 20 粗 / 左右 8·12 / 高 56。 */
const PANEL_HEADER_HEIGHT: number = 56;
const PANEL_HEADER_SIDE_PADDING: number = ThemeSpacing.sm;
const PANEL_HEADER_RIGHT_PADDING: number = ThemeSpacing.md;
const PANEL_HEADER_GAP: number = ThemeSpacing.xs;
const PANEL_BACK_SIZE: number = 40;
const PANEL_BACK_ICON: number = 22;
const PANEL_TITLE_LINE_HEIGHT: number = 24;
const PANEL_SUBTITLE_LINE_HEIGHT: number = 16;

const PANEL_ACTION_TILE: number = 44;
const PANEL_ACTION_TILE_RADIUS: number = 14;
const PANEL_ACTION_ICON: number = 22;
/** 09 稿实测：方块顶 405、主标签 460、说明 482、分隔线 501（402×874 稿的纵坐标）。 */
const PANEL_ACTION_LABEL_GAP: number = 10;
const PANEL_ACTION_HINT_GAP: number = 3;
const PANEL_DIVIDER_GAP: number = 16;
const PANEL_TILE_DISABLED_OPACITY: number = 0.45;

/**
 * 播放器「功能页」（09 稿内容，2026-11 从底部抽屉改成整页右滑）。
 *
 * 形态：根是 `Column { 头部; 内容 }`，不再复用 `BottomSheet`——没有蒙层、拖拽条、
 * 底部圆角和安全区扩展。进入 / 退出动画由 `Index` 的覆盖层负责（320ms 从右滑入，
 * 与「我的」里的设置整页同一条曲线），所以这里不持有位移参数。
 *
 * 仍然**挂在 `Index` 的根 Stack 上**（与登录抽屉 / 曲目弹层同一层），不挂在
 * `PlayerPage` 内部：`NavDestination` 是安全区内的页面层，全页覆盖会漏掉状态栏。
 *
 * 结构与 09 稿一致：
 * - 头部：返回按钮 + 曲名 + 作者，与设置整页的页头同构；
 * - 五宫格：加歌单 / 播放模式 / 定时关闭 / 下载 / 音质选择，方块 44×44、圆角 14，
 *   下方两行分别是主标签与状态说明；
 * - 分隔线；
 * - 列表：`QueueList` 的紧凑排版（封面 40、行高 64；当前曲目的音乐符挂在曲名左侧，
 *   与歌单详情列表一致；行尾是移除图标）。
 *
 * 列表就是完整队列，不再有「播放列表」标题行：这一页已经铺满整份队列，标题行的
 * 「进整页队列」跳转和右侧模式切换都是重复入口（模式切换在五宫格里已有）。
 *
 * 能力边界：加歌单、播放模式、定时关闭、下载与音质选择都可用。下载格只负责把
 * 当前曲目交给宿主的 `DownloadStore`（与曲目操作抽屉共用同一条链路），格内说明
 * 直接读 store 的已下载 / 下载中状态，不在这里持有文件或网络。
 */
@Component
export struct PlayerControlPanel {
  @ObjectLink store: PlayerStore;
  @ObjectLink settingsStore: SettingsStore;
  /** 当前曲目的下载状态与动作都来自这个 store：格子只读快照，真正下载由宿主触发。 */
  @ObjectLink downloadStore: DownloadStore;
  /** 定时状态由 `Index` 持有：功能页只读剩余时间并打开抽屉，不自己起计时器。 */
  @ObjectLink sleepTimerStore: SleepTimerStore;
  /**
   * 功能页已不在播放页的组件树里，不能复用播放页那份 `PlayerPageState`；
   * 这里按页面生命周期自建一份视图模型（只读曲名 / 作者 / 模式，切模式仍走
   * `cycleMode()`，结果由 `PlayerStore` 同时通知播放页与功能页）。
   */
  @State private pageState: PlayerPageState | null = null;
  /** 列表封面解码器：与其它页面一致，在功能页自己的生命周期里从 runtime 建。 */
  runtime: NativeAppRuntime | null = null;
  private coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;
  onClose: () => void = (): void => {};
  onAddToPlaylist: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  onDownload: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  onOpenSleepTimer: () => void = (): void => {};
  onOpenAudioQuality: () => void = (): void => {};

  @State private queueState: QueuePageState | null = null;

  aboutToAppear(): void {
    if (this.runtime !== null) {
      this.coverProvider = new RuntimeCoverImageProvider(this.runtime);
    }
    this.pageState = new PlayerPageState(this.store);
    this.pageState?.attach();
    this.queueState = new QueuePageState(this.store);
    this.queueState.attach();
  }

  /**
   * 收尾要同时满足两条约束（2026-11 真机崩溃后确认）：
   *
   * 1. 不写 `@State`：ArkUI 不允许在 aboutToDisappear 里改状态变量，销毁期间写状态会让
   *    已销毁的组件再走一次重建。
   * 2. `dispose()` 不能同步调用：aboutToDisappear 跑在 ArkUI 的 update 流程里，
   *    `QueuePageState.dispose()` → `PlayerStore.unsubscribe()` 会读 `listeners`
   *    （非 @Track 私有字段），在渲染上下文里读它直接触发
   *    `140110 Illegal usage of not @Track'ed property`，进程被杀。推迟一个任务，
   *    离开渲染上下文后再释放监听。
   */
  aboutToDisappear(): void {
    const queueState = this.queueState;
    const pageState = this.pageState;
    setTimeout((): void => {
      queueState?.dispose();
      pageState?.dispose();
    }, 0);
  }

  @Builder
  Header() {
    Row({ space: PANEL_HEADER_GAP }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        AppIcon({
          iconKind: AppIconKind.Back,
          iconSize: PANEL_BACK_ICON,
          iconColor: ThemeColors.textPrimary
        })
      }
      .id(NativeUiIds.playerPanelBack)
      .width(PANEL_BACK_SIZE)
      .height(PANEL_BACK_SIZE)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.player_panel_back'))
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Text(this.panelTitle())
          .width('100%')
          .fontSize(ThemeTypography.pageHeaderTitle)
          .lineHeight(PANEL_TITLE_LINE_HEIGHT)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.panelSubtitle() !== '') {
          Text(this.panelSubtitle())
            .width('100%')
            .fontSize(ThemeTypography.eyebrow)
            .lineHeight(PANEL_SUBTITLE_LINE_HEIGHT)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(PANEL_HEADER_HEIGHT)
    .padding({
      left: PANEL_HEADER_SIDE_PADDING,
      right: PANEL_HEADER_RIGHT_PADDING,
      top: PANEL_HEADER_SIDE_PADDING,
      bottom: PANEL_HEADER_SIDE_PADDING
    })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      this.Header()

      Column() {
        this.PanelContent()
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: ThemeSpacing.gutter,
        right: ThemeSpacing.gutter,
        bottom: ThemeSpacing.md
      })
    }
    .id(NativeUiIds.playerControlPanel)
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bg)
  }

  @Builder
  PanelContent() {
    Column() {
      this.ActionArea()

      Row()
        .width('100%')
        .height(1)
        .backgroundColor(ThemeColors.sheetDivider)
        .margin({ top: PANEL_DIVIDER_GAP })

      this.PlaylistArea()
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ top: ThemeSpacing.sm })
  }

  @Builder
  ActionArea() {
    Row() {
      this.IconActionTile(
        NativeUiIds.playerPanelAdd,
        $r('app.string.player_panel_add'),
        $r('app.string.player_panel_add_hint'),
        AppIconKind.PlaylistAdd,
        true,
        (): void => {
          const track = this.pageState?.track ?? null;
          if (track !== null) {
            this.onAddToPlaylist(track);
          }
        }
      )
      this.ModeTile()
      this.TimerTile()
      this.DownloadTile()
      this.QualityTile()
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /**
   * 播放模式格单独成 Builder：@Builder 的参数按值传递，把 `this.modeLabel()` /
   * `this.modeIcon()` 当参数塞进 ActionTile，切换模式后方块里的文字与图标不会刷新
   * （真机验证过：右侧 inline 行变了、方块没变）。这里直接读 @State 状态，
   * 才能建立依赖让这一格跟着重绘。
   */
  @Builder
  ModeTile() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph(this.modeIcon())
          .fontSize(PANEL_ACTION_ICON)
          .fontColor([ThemeColors.onActionTile])
      }
      .id(NativeUiIds.playerPanelMode)
      .width(PANEL_ACTION_TILE)
      .height(PANEL_ACTION_TILE)
      .padding(0)
      .borderRadius(PANEL_ACTION_TILE_RADIUS)
      .backgroundColor(ThemeColors.actionTile)
      .onClick((): void => {
        this.cycleMode();
      })
      .accessibilityText(this.modeLabel())

      Text(this.modeLabel())
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_LABEL_GAP })

      Text($r('app.string.player_panel_mode_hint'))
        .width('100%')
        .fontSize(ThemeTypography.playerPanelMeta)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_HINT_GAP })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  IconActionTile(id: string, label: Resource, hint: ResourceStr, iconKind: AppIconKind,
    enabledFlag: boolean, onClick: () => void) {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        AppIcon({
          iconKind: iconKind,
          iconSize: PANEL_ACTION_ICON,
          iconColor: ThemeColors.onActionTile
        })
      }
      .id(id)
      .width(PANEL_ACTION_TILE)
      .height(PANEL_ACTION_TILE)
      .padding(0)
      .borderRadius(PANEL_ACTION_TILE_RADIUS)
      .backgroundColor(ThemeColors.actionTile)
      .enabled(enabledFlag)
      .opacity(enabledFlag ? 1 : PANEL_TILE_DISABLED_OPACITY)
      .onClick(onClick)
      .accessibilityText(label)

      Text(label)
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_LABEL_GAP })

      Text(hint)
        .width('100%')
        .fontSize(ThemeTypography.playerPanelMeta)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_HINT_GAP })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 定时关闭格与 ModeTile 同理：剩余时间必须直接读 store，不能通过 @Builder 参数传值，
   * 否则倒计时更新后这一格不会重绘。
   */
  @Builder
  TimerTile() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.timer'))
          .fontSize(PANEL_ACTION_ICON)
          .fontColor([ThemeColors.onActionTile])
      }
      .id(NativeUiIds.playerPanelTimer)
      .width(PANEL_ACTION_TILE)
      .height(PANEL_ACTION_TILE)
      .padding(0)
      .borderRadius(PANEL_ACTION_TILE_RADIUS)
      .backgroundColor(ThemeColors.actionTile)
      .onClick((): void => {
        this.onOpenSleepTimer();
      })
      .accessibilityText($r('app.string.player_panel_timer'))

      Text($r('app.string.player_panel_timer'))
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_LABEL_GAP })

      Text(this.timerHint())
        .width('100%')
        .fontSize(ThemeTypography.playerPanelMeta)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_HINT_GAP })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 下载格与 ModeTile / TimerTile 同理：已下载 / 下载中状态直接读 `DownloadStore`，
   * 不通过 @Builder 参数传值，下载完成后这里才能立即刷新。
   * 已下载时仍可点击，重复请求由 store 跳过并由宿主 toast 说明，不静默。
   */
  @Builder
  DownloadTile() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        AppIcon({
          iconKind: AppIconKind.Download,
          iconSize: PANEL_ACTION_ICON,
          iconColor: ThemeColors.onActionTile
        })
      }
      .id(NativeUiIds.playerPanelDownload)
      .width(PANEL_ACTION_TILE)
      .height(PANEL_ACTION_TILE)
      .padding(0)
      .borderRadius(PANEL_ACTION_TILE_RADIUS)
      .backgroundColor(ThemeColors.actionTile)
      .onClick((): void => {
        const track = this.pageState?.track ?? null;
        if (track !== null) {
          this.onDownload(track);
        }
      })
      .accessibilityText($r('app.string.player_panel_download'))

      Text($r('app.string.player_panel_download'))
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_LABEL_GAP })

      Text(this.downloadHint())
        .width('100%')
        .fontSize(ThemeTypography.playerPanelMeta)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_HINT_GAP })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 音质格与 ModeTile / TimerTile 同理：状态文案直接读 SettingsStore，
   * 不通过 @Builder 参数传值，切换音质后这里才能立即刷新。
   */
  @Builder
  QualityTile() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        AppIcon({
          iconKind: AppIconKind.Quality,
          iconSize: PANEL_ACTION_ICON,
          iconColor: ThemeColors.onActionTile
        })
      }
      .id(NativeUiIds.playerPanelQuality)
      .width(PANEL_ACTION_TILE)
      .height(PANEL_ACTION_TILE)
      .padding(0)
      .borderRadius(PANEL_ACTION_TILE_RADIUS)
      .backgroundColor(ThemeColors.actionTile)
      .onClick((): void => {
        this.onOpenAudioQuality();
      })
      .accessibilityText($r('app.string.player_panel_quality'))

      Text($r('app.string.player_panel_quality'))
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_LABEL_GAP })

      Text(this.qualityHint())
        .width('100%')
        .fontSize(ThemeTypography.playerPanelMeta)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: PANEL_ACTION_HINT_GAP })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  PlaylistArea() {
    Column() {
      if (this.queueState !== null && this.queueState.queue.length > 0) {
        QueueList({
          state: this.queueState,
          compact: true,
          imageCache: this.coverProvider
        })
      } else {
        Text($r('app.string.queue_empty_description'))
          .width('100%')
          .fontSize(ThemeTypography.body)
          .lineHeight(ThemeTypography.bodyLineHeight)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(2)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ top: ThemeSpacing.sm })
  }

  private panelTitle(): ResourceStr {
    const track = this.pageState?.track ?? null;
    if (track !== null && track.title.trim().length > 0) {
      return track.title;
    }
    return $r('app.string.player_control_title');
  }

  private panelSubtitle(): string {
    const track = this.pageState?.track ?? null;
    if (track === null) {
      return '';
    }
    return track.artist.trim();
  }

  /** 切模式走播放页同一套 `PlayerPageState`，成功后由 store 回灌本页与播放页。 */
  private cycleMode(): void {
    const state = this.pageState;
    if (state !== null) {
      void state.cycleMode();
    }
  }

  private modeLabel(): Resource {
    const mode = this.pageState?.mode ?? 'sequence';
    if (mode === 'repeat-all') {
      return $r('app.string.player_mode_repeat_all');
    }
    if (mode === 'repeat-one') {
      return $r('app.string.player_mode_repeat_one');
    }
    if (mode === 'shuffle') {
      return $r('app.string.player_mode_shuffle');
    }
    return $r('app.string.player_mode_sequence');
  }

  private modeIcon(): Resource {
    if (this.pageState?.mode === 'shuffle') {
      return $r('sys.symbol.shuffle');
    }
    return $r('sys.symbol.repeat');
  }

  /** 档位说明位太窄，开启后只显示「剩余N分」，精确到秒的读数放在抽屉里。 */
  private timerHint(): ResourceStr {
    if (this.sleepTimerStore.activeMinutes <= 0) {
      return $r('app.string.sleep_timer_set');
    }
    const remainingMinutes = Math.max(1, Math.ceil(this.sleepTimerStore.remainingSeconds / 60));
    return `剩余${remainingMinutes}分`;
  }

  /** 下载格说明位：优先展示已下载 / 下载中，否则引导保存到本机。 */
  private downloadHint(): ResourceStr {
    const track = this.pageState?.track ?? null;
    if (track === null) {
      return $r('app.string.player_panel_download_hint');
    }
    if (this.downloadStore.isDownloaded(track.key)) {
      return $r('app.string.player_panel_downloaded');
    }
    if (this.downloadStore.isDownloading(track.key)) {
      return $r('app.string.player_panel_downloading');
    }
    return $r('app.string.player_panel_download_hint');
  }

  private qualityHint(): ResourceStr {
    const quality = this.settingsStore.snapshot.audioQuality;
    if (quality === 'high') {
      return $r('app.string.audio_quality_high');
    }
    if (quality === 'low') {
      return $r('app.string.audio_quality_low');
    }
    return $r('app.string.audio_quality_standard');
  }
}
