import {
  ThemeColors,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';

const PAGINATION_FOOTER_HEIGHT: number = 64;
const PAGINATION_ACTION_HEIGHT: number = 48;
const PAGINATION_ACTION_MIN_WIDTH: number = 152;
const PAGINATION_INDICATOR_SIZE: number = 18;

export enum PaginationFooterState {
  HasNext = 0,
  NoNext = 1
}

@Component
export struct PaginationFooter {
  @Prop state: PaginationFooterState = PaginationFooterState.NoNext;
  @Prop loading: boolean = false;
  @Prop moreLabel: ResourceStr = '加载更多';
  @Prop loadingLabel: ResourceStr = '正在加载';
  @Prop endLabel: ResourceStr = '没有更多了';
  onLoadMore: () => void = (): void => {
  };

  build() {
    Row() {
      if (this.state === PaginationFooterState.HasNext) {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Row({ space: ThemeSpacing.sm }) {
            if (this.loading) {
              LoadingProgress()
                .width(PAGINATION_INDICATOR_SIZE)
                .height(PAGINATION_INDICATOR_SIZE)
                .color(ThemeColors.accent)
            }
            Text(this.loading ? this.loadingLabel : this.moreLabel)
              .fontSize(ThemeTypography.caption)
              .fontColor(ThemeColors.textPrimary)
              .maxLines(1)
          }
          .justifyContent(FlexAlign.Center)
        }
        .constraintSize({
          minWidth: PAGINATION_ACTION_MIN_WIDTH,
          minHeight: PAGINATION_ACTION_HEIGHT
        })
        .padding({ left: ThemeSpacing.lg, right: ThemeSpacing.lg })
        .backgroundColor(ThemeColors.surfaceInset)
        .enabled(!this.loading)
        .onClick(() => this.onLoadMore())
      } else {
        Text(this.endLabel)
          .fontSize(ThemeTypography.eyebrow)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)
      }
    }
    .width('100%')
    .height(PAGINATION_FOOTER_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }
}
