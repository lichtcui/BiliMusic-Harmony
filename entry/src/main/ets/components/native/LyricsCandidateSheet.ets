import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { LyricCandidate } from '../../types/MobileTypes';
import { BottomSheet } from './BottomSheet';
import { NativeUiIds } from './NativeUiIds';
import { LyricsPanelState } from './LyricsPanelState';
import { SheetSize } from './SheetSizing';
import { formatTrackDuration } from './TrackRow';

/**
 * 换源弹层：design/lyrics-page.html 的歌词面板没有换源入口，这里保留候选列表与弹层，
 * 等后续设计补入口时复用（同一个 LyricsPanelState 驱动）。
 * 由 `pages/Index.ets` 挂在根 Stack 上渲染（`LyricsPanelState` 也提升到那里持有）：
 * 挂在播放页里会被 NavDestination 的页面层裁掉，安全区露白。
 */
@Component
export struct LyricsCandidateSheet {
  @ObjectLink state: LyricsPanelState;
  onClose: () => void = (): void => {};
  /** 宿主驱动的滑入 / 滑出位移（vp）：挂载前等于屏高，宿主动画回 0。 */
  @Prop panelOffsetY: number = 0;
  /** 宿主驱动的蒙层不透明度（0–1），与位移同步淡入淡出。 */
  @Prop scrimAlpha: number = 1;

  @Builder
  Sheet() {
    BottomSheet({
      sheetId: NativeUiIds.lyricsCandidatesSheet,
      title: $r('app.string.lyrics_candidates_title'),
      // 换源列表固定中档，和其他抽屉共用同一套头部 / 关闭按钮 / 上拉展开。
      sheetSize: SheetSize.Medium,
      panelOffsetY: this.panelOffsetY,
      scrimAlpha: this.scrimAlpha,
      onClose: () => {
        this.onClose();
      }
    }) {
      // @BuilderParam 必须走尾随闭包捕获本组件的 this，
      // 直接传 `this.SheetContent` 会让内部 `this.CandidateLoading()` 等调用丢绑定。
      this.SheetContent()
    }
  }

  @Builder
  SheetContent() {
    Column({ space: ThemeSpacing.xs }) {
      if (this.state.candidateError !== null) {
        Text($r('app.string.lyrics_candidate_selection_error'))
          .id(NativeUiIds.lyricsCandidateSelectionError)
          .width('100%')
          .fontSize(ThemeTypography.eyebrow)
          .fontColor(ThemeColors.accent)
          .maxLines(2)
      }
      if (this.state.candidateStatus === 'idle' || this.state.candidateStatus === 'loading') {
        this.CandidateLoading()
      } else if (this.state.candidateStatus === 'empty') {
        this.CandidateEmpty()
      } else if (this.state.candidateStatus === 'error') {
        this.CandidateError()
      } else {
        this.CandidateList()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  CandidateLoading() {
    Column({ space: ThemeSpacing.md }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(ThemeColors.accent)
      Text($r('app.string.lyrics_candidates_loading'))
        .id(NativeUiIds.lyricsCandidatesLoading)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  CandidateEmpty() {
    Column({ space: ThemeSpacing.sm }) {
      Text($r('app.string.lyrics_candidates_empty_title'))
        .id(NativeUiIds.lyricsCandidatesEmpty)
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(2)
        .textAlign(TextAlign.Center)
      Button($r('app.string.lyrics_candidates_retry'), { stateEffect: false })
        .id(NativeUiIds.lyricsCandidatesEmptyRetry)
        .height(36)
        .padding({ left: ThemeSpacing.lg, right: ThemeSpacing.lg })
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .backgroundColor(ThemeColors.surface)
        .borderRadius(ThemeRadius.sm)
        .onClick(() => {
          this.state.retryCandidateSearch();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  CandidateError() {
    Column({ space: ThemeSpacing.sm }) {
      Text($r('app.string.lyrics_candidates_error_title'))
        .id(NativeUiIds.lyricsCandidatesError)
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(2)
        .textAlign(TextAlign.Center)
      Text($r('app.string.lyrics_candidates_error_hint'))
        .fontSize(ThemeTypography.eyebrow)
        .lineHeight(20)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(2)
        .textAlign(TextAlign.Center)
      Button($r('app.string.lyrics_candidates_retry'), { stateEffect: false })
        .id(NativeUiIds.lyricsCandidatesRetry)
        .height(36)
        .padding({ left: ThemeSpacing.lg, right: ThemeSpacing.lg })
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .backgroundColor(ThemeColors.surface)
        .borderRadius(ThemeRadius.sm)
        .onClick(() => {
          this.state.retryCandidateSearch();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: ThemeSpacing.lg, right: ThemeSpacing.lg })
  }

  @Builder
  CandidateRow(candidate: LyricCandidate) {
    Row({ space: ThemeSpacing.sm }) {
      Column({ space: 2 }) {
        Text(candidate.trackName)
          .width('100%')
          .fontSize(ThemeTypography.body)
          .lineHeight(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.candidateArtist(candidate))
          .width('100%')
          .fontSize(ThemeTypography.eyebrow)
          .lineHeight(18)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: ThemeSpacing.xs }) {
          Text(this.candidateAlbum(candidate))
            .layoutWeight(1)
            .fontSize(ThemeTypography.eyebrow)
            .lineHeight(18)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(formatTrackDuration(candidate.duration))
            .fontSize(ThemeTypography.eyebrow)
            .lineHeight(18)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
        }
        .width('100%')
        .height(18)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.state.selectedCandidateId === candidate.id) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(ThemeColors.accent)
          .accessibilityText($r('app.string.lyrics_candidates_selecting'))
      }
    }
    .id(NativeUiIds.lyricsCandidate(candidate.id))
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({
      left: ThemeSpacing.md,
      right: ThemeSpacing.md,
      top: ThemeSpacing.sm,
      bottom: ThemeSpacing.sm
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.state.selectedCandidateId === candidate.id ?
      ThemeColors.accentSoft : ThemeColors.surface)
    .borderRadius(ThemeRadius.sm)
    .enabled(this.state.selectedCandidateId.length === 0)
    .opacity(this.state.selectedCandidateId.length === 0 ||
      this.state.selectedCandidateId === candidate.id ? 1 : 0.6)
    .onClick(() => {
      void this.state.selectCandidate(candidate.id);
    })
  }

  @Builder
  CandidateList() {
    List({ space: ThemeSpacing.xs }) {
      ForEach(this.state.candidates, (candidate: LyricCandidate) => {
        ListItem() {
          this.CandidateRow(candidate)
        }
      }, (candidate: LyricCandidate): string => candidate.id)
    }
    .id(NativeUiIds.lyricsCandidatesList)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      this.Sheet()
    }
    .width('100%')
    .height('100%')
  }

  private candidateArtist(candidate: LyricCandidate): ResourceStr {
    const artist = candidate.artistName.trim();
    return artist.length > 0 ? artist : $r('app.string.player_unknown_artist');
  }

  private candidateAlbum(candidate: LyricCandidate): ResourceStr {
    const album = candidate.albumName.trim();
    return album.length > 0 ? album : $r('app.string.lyrics_candidate_unknown_album');
  }
}
