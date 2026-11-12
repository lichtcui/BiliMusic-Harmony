import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { AppIcon, AppIconKind } from './AppIcon';

/**
 * 音乐列表整页的公共版式（2026-11 版式）。
 *
 * 「我喜欢的」「历史」「下载」「歌单详情」「合集详情」五个整页共用同一套页头 / 错误条 /
 * 空态，之前每个页面各抄一份（尺寸与文案资源漂移过两次）。这里只放纯展示组件：
 * 不持有 store，也不承担多选、分页或路由，页面仍自己算状态、传回调。
 *
 * 尺寸保持各页现有取值：`compact` 对应历史 / 下载的窄版错误条与无图标空态，
 * 其余页面用默认版；需要更细的差异时显式传 padding / 字号，不要新开一套组件。
 */

const HEADER_HEIGHT: number = 64;
const HEADER_ACTION_SIZE: number = 40;
const HEADER_BACK_ICON: number = 22;
const HEADER_TITLE_GAP: number = 8;
const ERROR_BANNER_MIN_HEIGHT: number = 44;
const ERROR_DISMISS_HEIGHT: number = 32;
const EMPTY_ICON_SIZE: number = 28;
const EMPTY_ACTION_WIDTH: number = 136;
const EMPTY_ACTION_HEIGHT: number = 40;
const EMPTY_ACTION_MARGIN_TOP: number = 4;

/** 整页页头：64 高，左返回、中标题（或留白）、右可选动作。 */
@Component
export struct MusicPageHeader {
  @Prop headerId: string = '';
  @Prop backId: string = '';
  @Prop backLabel: ResourceStr = '';
  @Prop showTitle: boolean = true;
  @Prop title: ResourceStr = '';
  /** 「我喜欢的」标题比返回键多内缩 2vp，其余页面为 0。 */
  @Prop titleIndent: number = 0;
  @Prop rightPadding: number = ThemeSpacing.md;
  /** 右上角动作（如「修改歌单信息」）；空字符串表示不放。 */
  @Prop actionId: string = '';
  @Prop actionLabel: ResourceStr = '';
  @Prop actionIcon: AppIconKind = AppIconKind.Edit;
  @Prop actionEnabled: boolean = true;
  onBack: () => void = (): void => {};
  onAction: () => void = (): void => {};

  /** `accessibilityText` 只有 string / Resource 两个重载，联合类型要显式拆开。 */
  private accessibilityLabel(label: ResourceStr): string {
    if (typeof label === 'string') {
      return label;
    }
    return getContext(this).resourceManager.getStringSync(label.id);
  }

  build() {
    Row({ space: HEADER_TITLE_GAP }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        AppIcon({
          iconKind: AppIconKind.Back,
          iconSize: HEADER_BACK_ICON,
          iconColor: ThemeColors.textPrimary
        })
      }
      .id(this.backId)
      .width(HEADER_ACTION_SIZE)
      .height(HEADER_ACTION_SIZE)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.onBack();
      })
      .accessibilityText(this.accessibilityLabel(this.backLabel))

      if (this.showTitle) {
        Column() {
          Text(this.title)
            .width('100%')
            .fontSize(ThemeTypography.pageHeaderTitle)
            .lineHeight(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: this.titleIndent })
      } else {
        Blank()
      }

      if (this.actionId.length > 0) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          AppIcon({
            iconKind: this.actionIcon,
            iconSize: HEADER_BACK_ICON,
            iconColor: ThemeColors.textPrimary
          })
        }
        .id(this.actionId)
        .width(HEADER_ACTION_SIZE)
        .height(HEADER_ACTION_SIZE)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .enabled(this.actionEnabled)
        .opacity(this.actionEnabled ? 1 : 0.35)
        .onClick(() => {
          this.onAction();
        })
        .accessibilityText(this.accessibilityLabel(this.actionLabel))
      }
    }
    .id(this.headerId)
    .width('100%')
    .height(HEADER_HEIGHT)
    .padding({
      left: ThemeSpacing.sm,
      right: this.rightPadding,
      top: ThemeSpacing.sm,
      bottom: ThemeSpacing.sm
    })
    .alignItems(VerticalAlign.Center)
  }
}

/** 列表页错误条：默认是 44 高 + 内圆角卡片，`compact` 为历史 / 下载的紧凑版。 */
@Component
export struct MusicPageErrorBanner {
  @Prop bannerId: string = '';
  @Prop message: ResourceStr = '';
  @Prop dismissLabel: ResourceStr = '';
  @Prop dismissId: string = '';
  @Prop compact: boolean = false;
  onDismiss: () => void = (): void => {};

  build() {
    Column() {
      if (this.compact) {
        Row({ space: ThemeSpacing.sm }) {
          Text(this.message)
            .layoutWeight(1)
            .fontSize(ThemeTypography.caption)
            .fontColor(ThemeColors.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button(this.dismissLabel, { stateEffect: false })
            .id(this.dismissId)
            .height(ERROR_DISMISS_HEIGHT)
            .fontSize(ThemeTypography.caption)
            .fontColor(ThemeColors.accent)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.onDismiss();
            })
        }
        .id(this.bannerId)
        .width('100%')
        .padding({ left: ThemeSpacing.md, right: ThemeSpacing.xs, top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
        .backgroundColor(ThemeColors.surfaceInset)
        .borderRadius(ThemeRadius.sm)
      } else {
        Row() {
          Row({ space: ThemeSpacing.sm }) {
            Text(this.message)
              .layoutWeight(1)
              .fontSize(ThemeTypography.meta)
              .lineHeight(18)
              .fontColor(ThemeColors.textPrimary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button(this.dismissLabel, { stateEffect: false })
              .id(this.dismissId)
              .height(ERROR_DISMISS_HEIGHT)
              .padding({ left: ThemeSpacing.sm, right: ThemeSpacing.sm })
              .fontSize(ThemeTypography.eyebrow)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeColors.accent)
              .backgroundColor(Color.Transparent)
              .borderRadius(6)
              .onClick(() => {
                this.onDismiss();
              })
          }
          .id(this.bannerId)
          .width('100%')
          .constraintSize({ minHeight: ERROR_BANNER_MIN_HEIGHT })
          .padding({ left: ThemeSpacing.md, right: 6, top: 6, bottom: 6 })
          .backgroundColor(ThemeColors.surfaceInset)
          .borderRadius(ThemeRadius.md)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: ThemeSpacing.gutter, right: ThemeSpacing.gutter, top: ThemeSpacing.sm, bottom: ThemeSpacing.sm })
      }
    }
    .width('100%')
  }
}

/** 列表页空态：可选图标与操作按钮；`compact` 对应无图标、紧凑间距的历史 / 下载。 */
@Component
export struct MusicPageEmptyState {
  @Prop emptyId: string = '';
  @Prop showIcon: boolean = true;
  @Prop iconKind: AppIconKind = AppIconKind.Note;
  @Prop iconOpacity: number = 0.8;
  @Prop title: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop descriptionMaxWidth: number = 280;
  @Prop descriptionLineHeight: number = 22;
  @Prop compact: boolean = false;
  @Prop paddingTop: number = 32;
  @Prop paddingBottom: number = 56;
  @Prop showAction: boolean = false;
  @Prop actionId: string = '';
  @Prop actionLabel: ResourceStr = '';
  onAction: () => void = (): void => {};

  build() {
    Column({ space: this.compact ? ThemeSpacing.sm : ThemeSpacing.md }) {
      if (this.showIcon) {
        Stack() {
          AppIcon({
            iconKind: this.iconKind,
            iconSize: EMPTY_ICON_SIZE,
            iconColor: ThemeColors.textSecondary
          })
        }
        .opacity(this.iconOpacity)
      }

      Text(this.title)
        .fontSize(ThemeTypography.emptyTitle)
        .lineHeight(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.description)
        .constraintSize({ maxWidth: this.descriptionMaxWidth })
        .fontSize(ThemeTypography.body)
        .lineHeight(this.descriptionLineHeight)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.showAction) {
        Button(this.actionLabel, { stateEffect: false })
          .id(this.actionId)
          .width(EMPTY_ACTION_WIDTH)
          .height(EMPTY_ACTION_HEIGHT)
          .margin({ top: EMPTY_ACTION_MARGIN_TOP })
          .fontSize(ThemeTypography.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.onAccent)
          .backgroundColor(ThemeColors.accent)
          .borderRadius(ThemeRadius.md)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .id(this.emptyId)
    .width('100%')
    .layoutWeight(1)
    .padding({
      left: ThemeSpacing.xxl,
      right: ThemeSpacing.xxl,
      top: this.paddingTop,
      bottom: this.paddingBottom
    })
    .justifyContent(FlexAlign.Center)
  }
}