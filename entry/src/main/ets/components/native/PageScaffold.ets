import {
  ThemeColors,
  ThemeRadius,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';

export enum PageContentState {
  Empty = 0,
  Loading = 1,
  Ready = 2
}

@Component
export struct PageScaffold {
  @Prop pageId: string = '';
  @Prop eyebrow: ResourceStr;
  @Prop title: ResourceStr;
  @Prop description: ResourceStr;
  @Prop state: PageContentState = PageContentState.Empty;
  @BuilderParam contentBuilder: () => void = this.EmptyContent;

  @Builder
  EmptyContent() {
    Column({ space: ThemeSpacing.md }) {
      Row()
        .width(36)
        .height(4)
        .borderRadius(ThemeRadius.sm)
        .backgroundColor(ThemeColors.accent)
      Text(this.description)
        .width('100%')
        .fontSize(ThemeTypography.body)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(this.pageId)
    .width('100%')
    .constraintSize({ minHeight: ThemeSize.emptyContentMinHeight })
    .padding({ left: ThemeSpacing.xxl, right: ThemeSpacing.xxl })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  LoadingContent() {
    Column({ space: ThemeSpacing.md }) {
      LoadingProgress()
        .width(ThemeSize.loadingIndicator)
        .height(ThemeSize.loadingIndicator)
        .color(ThemeColors.accent)
      Text($r('app.string.common_loading'))
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textSecondary)
    }
    .width('100%')
    .constraintSize({ minHeight: ThemeSize.emptyContentMinHeight })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ReadyContent() {
    this.contentBuilder()
  }

  build() {
    Column() {
      Column({ space: ThemeSpacing.xs }) {
        Text(this.eyebrow)
          .width('100%')
          .fontSize(ThemeTypography.eyebrow)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.title)
          .width('100%')
          .height(ThemeSize.pageTitleBlock)
          .fontSize(ThemeTypography.pageTitle)
          .lineHeight(ThemeTypography.pageTitleLineHeight)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: ThemeSpacing.xl,
        right: ThemeSpacing.xl,
        top: ThemeSpacing.lg,
        bottom: ThemeSpacing.md
      })
      .backgroundColor(ThemeColors.surface)

      Divider()
        .strokeWidth(1)
        .color(ThemeColors.line)

      Scroll() {
        Column() {
          if (this.state === PageContentState.Loading) {
            this.LoadingContent()
          } else if (this.state === PageContentState.Empty) {
            this.EmptyContent()
          } else {
            this.ReadyContent()
          }
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(ThemeColors.bg)
    }
    .width('100%')
    .height('100%')
    .safeAreaPadding({
      top: ThemeSpacing.xs,
      bottom: ThemeSpacing.xs
    })
    .backgroundColor(ThemeColors.bg)
  }
}
