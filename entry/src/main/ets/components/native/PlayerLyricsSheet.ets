import {
  ThemeColors,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { AppIcon, AppIconKind } from './AppIcon';
import { LyricsPanel } from './LyricsPanel';
import { LyricsPanelState } from './LyricsPanelState';
import { NativeUiIds } from './NativeUiIds';

/** 歌词面板底边到内容区底边的距离：底部播放条 64 + 间距 34 + 时间行 16 + 间距 4 + 进度 28 + 页底 12。 */
const SHEET_REST: number = 158;
const SHEET_HEADER_PLAY_SIZE: number = 44;
const SHEET_PLAY_ICON_SIZE: number = 24;
const SHEET_FADE_HEIGHT: number = 36;
const SHEET_COLLAPSE_HEIGHT: number = 40;

/**
 * design/lyrics-page.html 的歌词面板。
 *
 * 面板从屏幕最顶部（含状态栏）铺到进度条上方 158vp 处，盖住播放页的标题、封面、
 * 歌词预览与操作行；进度条、时间行和底部播放条仍留在面板外，可继续拖动 / 播放。
 * 表面与播放页同底色、无阴影、无顶部圆角，`expandSafeArea` 只把底色画进状态栏，
 * 内容仍停在安全区内，因此展开后看不出与播放页的分层边界。
 * 外层由 `Index` 挂在根 Stack 上，避免 `NavDestination` 裁掉安全区；进出场只驱动 `reveal`（0–1）。
 */
@Component
export struct PlayerLyricsSheet {
  @ObjectLink state: LyricsPanelState;
  /** 0 = 完全收起（面板移出所在区域并透明），1 = 完全展开。 */
  @Prop reveal: number = 1;
  onClose: () => void = (): void => {};

  @State private regionHeight: number = 0;

  @Builder
  SheetHeader() {
    Row({ space: ThemeSpacing.md }) {
      Column() {
        Text(this.displayTitle())
          .id(NativeUiIds.lyricsSheetTitle)
          .width('100%')
          .fontSize(ThemeTypography.playerTitle)
          .lineHeight(ThemeTypography.playerTitleLineHeight)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.displayArtist())
          .id(NativeUiIds.lyricsSheetArtist)
          .width('100%')
          .fontSize(ThemeTypography.playerMeta)
          .lineHeight(18)
          .fontColor(ThemeColors.textSecondary)
          .margin({ top: ThemeSpacing.sm })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button({ type: ButtonType.Circle, stateEffect: false }) {
        if (this.state.transportBusy || this.state.playbackStatus === 'loading') {
          LoadingProgress()
            .width(SHEET_PLAY_ICON_SIZE)
            .height(SHEET_PLAY_ICON_SIZE)
            .color(ThemeColors.textPrimary)
        } else {
          AppIcon({
            iconKind: this.state.playbackStatus === 'playing' ? AppIconKind.Pause : AppIconKind.Play,
            iconSize: SHEET_PLAY_ICON_SIZE,
            iconColor: ThemeColors.textPrimary
          })
        }
      }
      .id(NativeUiIds.lyricsSheetPlay)
      .width(SHEET_HEADER_PLAY_SIZE)
      .height(SHEET_HEADER_PLAY_SIZE)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .enabled(this.state.canTogglePlayback())
      .opacity(this.state.canTogglePlayback() ? 1 : 0.55)
      .onClick(() => {
        void this.state.togglePlayback();
      })
      .accessibilityText(this.state.playbackStatus === 'playing' ?
        $r('app.string.player_pause') : $r('app.string.player_play'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({
      top: ThemeSpacing.xl,
      left: ThemeSize.playerGutter,
      right: ThemeSize.playerGutter,
      bottom: ThemeSpacing.md
    })
  }

  @Builder
  SheetBody() {
    Stack({ alignContent: Alignment.Top }) {
      LyricsPanel({
        state: this.state,
        currentIndex: this.state.currentIndex,
        contentGeneration: this.state.contentGeneration
      })
        .width('100%')
        .height('100%')

      // 顶部 / 底部 36vp 渐隐，让滚出面板的歌词融进底色而不是被硬边裁断。
      Column()
        .width('100%')
        .height(SHEET_FADE_HEIGHT)
        .linearGradient({
          angle: 180,
          colors: [[ThemeColors.loginSheetSurface, 0], [ThemeColors.sheetFade, 1]]
        })
        .hitTestBehavior(HitTestMode.None)

      Column() {
        Column()
          .width('100%')
          .height(SHEET_FADE_HEIGHT)
          .linearGradient({
            angle: 0,
            colors: [[ThemeColors.loginSheetSurface, 0], [ThemeColors.sheetFade, 1]]
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: ThemeSize.playerGutter, right: ThemeSize.playerGutter })
  }

  @Builder
  SheetFooter() {
    Row() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Row({ space: 6 }) {
          Text($r('app.string.lyrics_collapse'))
            .fontSize(ThemeTypography.lyricsCollapse)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
          AppIcon({
            iconKind: AppIconKind.ChevronDown,
            iconSize: 16,
            iconColor: ThemeColors.textSecondary
          })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .id(NativeUiIds.lyricsCollapse)
      .height(SHEET_COLLAPSE_HEIGHT)
      .padding({ left: 18, right: 18 })
      .borderRadius(SHEET_COLLAPSE_HEIGHT / 2)
      .backgroundColor(ThemeColors.surfaceInset)
      .onClick(() => {
        this.onClose();
      })
      .accessibilityText($r('app.string.lyrics_collapse'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({
      top: ThemeSpacing.sm,
      left: ThemeSize.playerGutter,
      right: ThemeSize.playerGutter,
      bottom: 18
    })
  }

  build() {
    Column() {
      // 固定高度的面板区域：内层裁切窗口从 0 长到满高（等价于设计稿的 clip-path: inset(100% 0 0 0) → inset(0)），
      // 面板本体只做 24vp 上移与淡入；裁切窗口本身贴底，展开时由下往上露出。
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.Bottom }) {
          Column() {
            this.SheetHeader()
            this.SheetBody()
            this.SheetFooter()
          }
          .width('100%')
          .height(this.regionHeight)
          // 与播放页同底色、无描边 / 圆角 / 阴影：面板展开后顶边不再出现分层线。
          .backgroundColor(ThemeColors.loginSheetSurface)
          // 只把底色画进状态栏（固定高度只支持 TOP 方向），内容仍停在安全区内；
          // 这样面板视觉上一直铺到屏幕顶部，状态栏区域也不会露出播放页的底色差。
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
          .translate({ y: (1 - this.reveal) * 24 })
          .opacity(this.reveal <= 0 ? 0 : 0.4 + 0.6 * this.reveal)
          // Default 才能让面板内的播放 / 收起 / 歌词行收到点击；Block 会连子节点一起挡掉。
          .hitTestBehavior(HitTestMode.Default)
        }
        .width('100%')
        .height(this.regionHeight * this.reveal)
        .clip(this.reveal < 1)
      }
      .width('100%')
      .layoutWeight(1)
      .onAreaChange((_oldValue: Area, newValue: Area): void => {
        const height = newValue.height as number;
        this.regionHeight = Number.isFinite(height) && height > 0 ? height : 0;
      })

      // 底部 158vp 是留给进度条 / 时间行 / 播放条的操作区，面板本身不占这一块。
      Column()
        .width('100%')
        .height(SHEET_REST)
        .hitTestBehavior(HitTestMode.None)
    }
    .id(NativeUiIds.lyricsSheet)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    // 自身不接事件，让上面的面板区域与底部的空操作区分别决定是否拦截。
    // 不能用 Transparent：它会把同一坐标的播放页也一起命中，导致面板按钮点穿。
    .hitTestBehavior(HitTestMode.None)
  }

  private displayTitle(): ResourceStr {
    const track = this.state.track;
    if (track === null || track.title.trim().length === 0) {
      return $r('app.string.player_unknown_track');
    }
    return track.title.trim();
  }

  private displayArtist(): ResourceStr {
    const track = this.state.track;
    if (track === null || track.artist.trim().length === 0) {
      return $r('app.string.player_unknown_artist');
    }
    return track.artist.trim();
  }
}