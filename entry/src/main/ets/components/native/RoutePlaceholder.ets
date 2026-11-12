import {
  ThemeColors,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';

@Component
export struct RoutePlaceholder {
  @Prop message: ResourceStr;
  @Prop hint: ResourceStr;

  build() {
    Column({ space: ThemeSpacing.md }) {
      Text(this.message)
        .width('100%')
        .fontSize(ThemeTypography.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.hint)
        .width('100%')
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textSecondary)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .textAlign(TextAlign.Center)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .padding({ left: ThemeSpacing.xxl, right: ThemeSpacing.xxl })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(ThemeColors.bg)
  }
}
