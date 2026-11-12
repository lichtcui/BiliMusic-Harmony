import {
  ThemeColors,
  ThemeRadius,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { LyricLine } from '../../types/MobileTypes';
import { NativeUiIds } from './NativeUiIds';
import { LyricsPanelState } from './LyricsPanelState';

/**
 * 歌词面板的歌词区（design/lyrics-page.html）。
 *
 * 通栏左对齐：当前行 24 加粗、下一行保持正文深色、更远的行逐级变淡；
 * 点击行 seek、手指按下暂停跟随，滚动静止后跟随当前行回中。
 */
@Component
export struct LyricsPanel {
  @ObjectLink state: LyricsPanelState;
  @Prop @Watch('onScrollTargetChanged') currentIndex: number = -1;
  @Prop @Watch('onScrollTargetChanged') contentGeneration: number = 0;

  private readonly scroller: Scroller = new Scroller();
  private scrollGeneration: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void {
    // 面板每次打开都先居中当前行（等价于设计稿 openLyrics() 的 scrollToActive(true)），
    // 即使用户上次浏览时暂停过跟随。
    this.scrollToCurrent(true, true);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.scrollGeneration++;
  }

  @Builder
  LoadingPlaceholder() {
    Column({ space: ThemeSpacing.md }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(ThemeColors.accent)
      Text($r('app.string.lyrics_loading'))
        .id(NativeUiIds.lyricsLoading)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  EmptyPlaceholder() {
    Column({ space: ThemeSpacing.sm }) {
      Text($r('app.string.lyrics_empty_title'))
        .id(NativeUiIds.lyricsEmpty)
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(2)
        .textAlign(TextAlign.Center)
      Text($r('app.string.lyrics_empty_hint'))
        .fontSize(ThemeTypography.eyebrow)
        .lineHeight(20)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(3)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ErrorPlaceholder() {
    Column({ space: ThemeSpacing.sm }) {
      Text($r('app.string.lyrics_error_title'))
        .id(NativeUiIds.lyricsError)
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(2)
        .textAlign(TextAlign.Center)
      Text($r('app.string.lyrics_error_hint'))
        .fontSize(ThemeTypography.eyebrow)
        .lineHeight(20)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(3)
        .textAlign(TextAlign.Center)
      if (this.state.canRetry) {
        Button($r('app.string.lyrics_error_retry'), { stateEffect: false })
          .id(NativeUiIds.lyricsErrorRetry)
          .height(36)
          .padding({ left: ThemeSpacing.lg, right: ThemeSpacing.lg })
          .fontSize(ThemeTypography.caption)
          .fontColor(ThemeColors.textPrimary)
          .backgroundColor(ThemeColors.surface)
          .borderRadius(ThemeRadius.sm)
          .margin({ top: ThemeSpacing.xs })
          .onClick(() => {
            this.state.retry();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  LyricRows(allowHighlight: boolean) {
    List({ space: 0, scroller: this.scroller }) {
      ForEach(this.state.lines, (line: LyricLine, index: number) => {
        ListItem() {
          Row() {
            Text(line.text)
              .id(NativeUiIds.lyricsLine(index))
              .width('100%')
              .fontSize(this.rowFontSize(allowHighlight, index))
              .lineHeight(this.rowLineHeight(allowHighlight, index))
              .fontWeight(this.rowWeight(allowHighlight, index))
              .fontColor(this.rowColor(allowHighlight, index))
              .opacity(this.rowOpacity(allowHighlight, index))
              .textAlign(TextAlign.Start)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ top: ThemeSpacing.sm, bottom: ThemeSpacing.sm })
          .constraintSize({ minHeight: this.rowHeight(allowHighlight, index) })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            if (allowHighlight && this.state.canSeek()) {
              void this.state.seekToLine(index);
            }
          })
        }
      }, (line: LyricLine, index: number): string => {
        return `${this.state.trackKey}:${index}:${line.time}`;
      })
    }
    .id(allowHighlight ? NativeUiIds.lyricsSyncedList : NativeUiIds.lyricsUnsyncedList)
    .width('100%')
    .height('100%')
    .padding({ top: ThemeSpacing.sm, bottom: ThemeSpacing.sm })
    .scrollBar(BarState.Off)
    .onTouch((event?: TouchEvent): void => {
      if (event !== undefined && event.type === TouchType.Down) {
        this.scrollGeneration++;
        this.state.pauseFollow();
      }
    })
    .onScrollStop((): void => {
      if (!this.disposed && !this.state.followPaused) {
        this.scrollToCurrent(true);
      }
    })
  }

  build() {
    Column() {
      if (this.state.status === 'idle' || this.state.status === 'loading') {
        this.LoadingPlaceholder()
      } else if (this.state.status === 'empty') {
        this.EmptyPlaceholder()
      } else if (this.state.status === 'error') {
        this.ErrorPlaceholder()
      } else if (this.state.status === 'unsynced') {
        Text($r('app.string.lyrics_unsynced_label'))
          .id(NativeUiIds.lyricsUnsyncedLabel)
          .width('100%')
          .fontSize(ThemeTypography.eyebrow)
          .fontColor(ThemeColors.textSecondary)
          .opacity(0.72)
          .maxLines(1)
        this.LyricRows(false)
      } else {
        this.LyricRows(true)
      }
    }
    .id(NativeUiIds.lyricsPanel)
    .width('100%')
    // 伸缩交给调用点（`LyricsPanel(...).layoutWeight(1)`）：写在自定义组件内部时
    // 只作用于外壳里的根节点，宿主的 Column 仍按内容高度排，会把下面的操作行 / 进度条 / 底栏顶出屏幕。
    .height('100%')
  }

  private onScrollTargetChanged(): void {
    this.scrollToCurrent(true);
  }

  private isActive(allowHighlight: boolean, index: number): boolean {
    return allowHighlight && index === this.currentIndex;
  }

  private rowFontSize(allowHighlight: boolean, index: number): number {
    return this.isActive(allowHighlight, index) ?
      ThemeTypography.lyricsLineActive : ThemeTypography.lyricsLine;
  }

  private rowLineHeight(allowHighlight: boolean, index: number): number {
    return this.isActive(allowHighlight, index) ?
      ThemeTypography.lyricsLineActiveHeight : ThemeTypography.lyricsLineHeight;
  }

  private rowWeight(allowHighlight: boolean, index: number): FontWeight {
    return this.isActive(allowHighlight, index) ? FontWeight.Bold : FontWeight.Normal;
  }

  private rowHeight(allowHighlight: boolean, index: number): number {
    return this.isActive(allowHighlight, index) ?
      ThemeSize.lyricsRowActiveHeight : ThemeSize.lyricsRowHeight;
  }

  /** 当前行与下一行用正文深色，其余用次要色（04 稿实测：下一行仍是正文色，没有降级）。 */
  private rowColor(allowHighlight: boolean, index: number): Resource {
    if (allowHighlight && this.currentIndex >= 0 &&
      (index === this.currentIndex || index === this.currentIndex + 1)) {
      return ThemeColors.textPrimary;
    }
    return ThemeColors.textSecondary;
  }

  /** 离当前行 3 行以外的歌词再淡一档：稿件实测约为次要色的五成不透明度叠在近白画布上。 */
  private rowOpacity(allowHighlight: boolean, index: number): number {
    if (!allowHighlight || this.currentIndex < 0) {
      return 1;
    }
    return Math.abs(index - this.currentIndex) >= 3 ? 0.55 : 1;
  }

  private scrollToCurrent(smooth: boolean, force: boolean = false): void {
    if (this.disposed || (!force && this.state.followPaused) || this.currentIndex < 0 ||
      this.currentIndex >= this.state.lines.length) {
      return;
    }
    const generation = this.scrollGeneration + 1;
    this.scrollGeneration = generation;
    const targetIndex = this.currentIndex;
    setTimeout((): void => {
      if (this.disposed || generation !== this.scrollGeneration ||
        (!force && this.state.followPaused) ||
        targetIndex !== this.currentIndex || targetIndex >= this.state.lines.length) {
        return;
      }
      this.scroller.scrollToIndex(targetIndex, smooth, ScrollAlign.CENTER);
    }, 0);
  }
}
