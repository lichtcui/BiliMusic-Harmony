import { PlayerStore } from '../../state/PlayerStore';
import { MobileTrack } from '../../types/MobileTypes';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { NativeUiIds } from './NativeUiIds';
import { QueuePageState } from './QueuePageState';
import { QueueList } from './QueueList';

@Component
export struct QueuePage {
  @ObjectLink store: PlayerStore;
  onBrowseSearch: () => void = (): void => {};
  onClose: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {
  };
  /** 整页队列切歌成功后回到播放页；由宿主决定路由。 */
  onOpenPlayer: () => void = (): void => {};

  @State private pageState: QueuePageState | null = null;

  aboutToAppear(): void {
    this.pageState = new QueuePageState(this.store);
    this.pageState?.attach();
  }

  aboutToDisappear(): void {
    this.pageState?.dispose();
    this.pageState = null;
  }

  build() {
    if (this.pageState !== null) {
      QueuePageContent({
        state: this.pageState,
        onBrowseSearch: this.onBrowseSearch,
        onClose: this.onClose,
        onOpenTrackActions: this.onOpenTrackActions,
        onOpenPlayer: this.onOpenPlayer
      })
    }
  }
}

@Component
struct QueuePageContent {
  @ObjectLink state: QueuePageState;
  onBrowseSearch: () => void = (): void => {};
  onClose: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {
  };
  onOpenPlayer: () => void = (): void => {};

  @Builder
  ErrorBanner() {
    Row({ space: ThemeSpacing.sm }) {
      Text($r('app.string.player_error_message'))
        .id(NativeUiIds.queueError)
        .layoutWeight(1)
        .fontSize(ThemeTypography.caption)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(ThemeSpacing.md)
    .backgroundColor(ThemeColors.surfaceInset)
    .borderRadius(ThemeRadius.md)
  }

  @Builder
  EmptyState() {
    Column({ space: ThemeSpacing.md }) {
      Text($r('app.string.queue_empty_title'))
        .id(NativeUiIds.queueEmptyTitle)
        .fontSize(ThemeTypography.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Text($r('app.string.queue_empty_description'))
        .fontSize(ThemeTypography.body)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: ThemeSpacing.sm }) {
        Button($r('app.string.queue_empty_back'), { stateEffect: false })
          .id(NativeUiIds.queueEmptyBack)
          .layoutWeight(1)
          .height(ThemeSize.routeButtonHeight)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .backgroundColor(ThemeColors.surfaceInset)
          .borderRadius(ThemeRadius.md)
          .onClick(() => {
            this.onClose();
          })
        Button($r('app.string.queue_empty_search'), { stateEffect: false })
          .id(NativeUiIds.queueEmptySearch)
          .layoutWeight(1)
          .height(ThemeSize.routeButtonHeight)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.onAccent)
          .backgroundColor(ThemeColors.accent)
          .borderRadius(ThemeRadius.md)
          .onClick(() => {
            this.onBrowseSearch();
          })
      }
      .width('100%')
      .constraintSize({ maxWidth: 320 })
    }
    .id(NativeUiIds.queueEmpty)
    .width('100%')
    .layoutWeight(1)
    .padding({ left: ThemeSpacing.xxl, right: ThemeSpacing.xxl })
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Row({ space: ThemeSpacing.md }) {
        Column({ space: 2 }) {
          Text($r('app.string.route_queue_title'))
            .fontSize(ThemeTypography.pageTitle)
            .lineHeight(ThemeTypography.pageTitleLineHeight)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary)
            .maxLines(1)
          Row({ space: ThemeSpacing.xs }) {
            Text(this.state.queue.length.toString())
              .fontSize(ThemeTypography.caption)
              .fontColor(ThemeColors.accent)
            Text($r('app.string.queue_count_suffix'))
              .fontSize(ThemeTypography.caption)
              .fontColor(ThemeColors.textSecondary)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.state.isBusy()) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color(ThemeColors.accent)
        }

        Button(this.clearLabel(), { stateEffect: false })
          .id(NativeUiIds.queueClear)
          .width(76)
          .height(ThemeSize.routeButtonHeight)
          .fontSize(ThemeTypography.caption)
          .fontColor(ThemeColors.textPrimary)
          .backgroundColor(ThemeColors.surfaceInset)
          .borderRadius(ThemeRadius.md)
          .enabled(this.state.canClear())
          .opacity(this.state.canClear() ? 1 : 0.55)
          .onClick(() => {
            this.confirmClear();
          })
      }
      .width('100%')
      .padding({
        left: ThemeSpacing.xl,
        right: ThemeSpacing.xl,
        top: ThemeSpacing.lg,
        bottom: ThemeSpacing.md
      })

      if (this.state.error !== null) {
        this.ErrorBanner()
      }

      if (this.state.queue.length === 0) {
        this.EmptyState()
      } else {
        QueueList({
          state: this.state,
          onOpenTrackActions: this.onOpenTrackActions,
          onOpenPlayer: this.onOpenPlayer
        })
      }
    }
    .id(NativeUiIds.queuePage)
    .width('100%')
    .height('100%')
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }

  private clearLabel(): ResourceStr {
    return this.state.busyAction === 'clear' ? $r('app.string.queue_clearing') :
      $r('app.string.queue_clear');
  }

  private confirmClear(): void {
    if (!this.state.canClear()) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.queue_clear_title'),
      message: $r('app.string.queue_clear_message'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.queue_clear_cancel'),
        defaultFocus: true,
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.queue_clear_confirm'),
        action: (): void => {
          void this.state.clear();
        }
      }
    });
  }
}
