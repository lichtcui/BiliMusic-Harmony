import {
  ThemeColors,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';

const LIST_STATE_ACTION_HEIGHT: number = 48;
const LIST_STATE_ACTION_MIN_WIDTH: number = 120;
const LIST_STATE_MARK_SIZE: number = 40;
const LIST_STATE_TITLE_HEIGHT: number = 26;
const LIST_STATE_MESSAGE_HEIGHT: number = 44;

export enum ListStateKind {
  Loading = 0,
  Empty = 1,
  Error = 2
}

@Component
export struct ListStateView {
  @Prop viewId: string = '';
  @Prop state: ListStateKind = ListStateKind.Empty;
  @Prop title: ResourceStr = '';
  @Prop message: ResourceStr = '';
  /** 纯文字空态 / 引导态可关掉左侧状态标记；默认保留（加载、错误态等既有调用方不受影响）。 */
  @Prop showMark: boolean = true;
  @Prop actionLabel: ResourceStr = '';
  onAction: () => void = (): void => {
  };

  build() {
    Column({ space: ThemeSpacing.md }) {
      if (this.state === ListStateKind.Loading) {
        LoadingProgress()
          .width(ThemeSize.loadingIndicator)
          .height(ThemeSize.loadingIndicator)
          .color(ThemeColors.accent)
      } else if (this.showMark) {
        Text(this.state === ListStateKind.Error ? '!' : '—')
          .width(LIST_STATE_MARK_SIZE)
          .height(LIST_STATE_MARK_SIZE)
          .fontSize(ThemeTypography.sectionTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.state === ListStateKind.Error ? ThemeColors.accent : ThemeColors.textSecondary)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.state === ListStateKind.Error ? ThemeColors.accentSoft : ThemeColors.surfaceInset)
          .borderRadius(LIST_STATE_MARK_SIZE / 2)
      }
      Text(this.effectiveTitle())
        .width('100%')
        .height(LIST_STATE_TITLE_HEIGHT)
        .fontSize(ThemeTypography.body)
        .lineHeight(LIST_STATE_TITLE_HEIGHT)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.effectiveMessage())
        .width('100%')
        .height(LIST_STATE_MESSAGE_HEIGHT)
        .fontSize(ThemeTypography.caption)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.actionLabel !== '') {
        Button(this.actionLabel, { type: ButtonType.Normal, stateEffect: false })
          .constraintSize({
            minWidth: LIST_STATE_ACTION_MIN_WIDTH,
            minHeight: LIST_STATE_ACTION_HEIGHT
          })
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .backgroundColor(ThemeColors.surfaceInset)
          .onClick(() => this.onAction())
      }
    }
    .id(this.viewId)
    .width('100%')
    .height(ThemeSize.emptyContentMinHeight)
    .padding({
      left: ThemeSpacing.xl,
      right: ThemeSpacing.xl,
      top: ThemeSpacing.md,
      bottom: ThemeSpacing.md
    })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(ThemeColors.bg)
  }

  private effectiveTitle(): ResourceStr {
    if (this.title !== '') {
      return this.title;
    }
    if (this.state === ListStateKind.Loading) {
      return $r('app.string.common_loading');
    }
    if (this.state === ListStateKind.Error) {
      return $r('app.string.common_load_failed');
    }
    return $r('app.string.common_empty_title');
  }

  private effectiveMessage(): ResourceStr {
    if (this.message !== '') {
      return this.message;
    }
    if (this.state === ListStateKind.Loading) {
      return $r('app.string.common_loading_message');
    }
    if (this.state === ListStateKind.Error) {
      return $r('app.string.common_error_message');
    }
    return $r('app.string.common_empty_message');
  }
}
