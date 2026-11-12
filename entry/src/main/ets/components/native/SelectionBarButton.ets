import { ThemeColors, ThemeRadius } from '../../theme/NativeTheme';
import { AppIcon, AppIconKind } from './AppIcon';

/** 批量操作栏按钮：22 图标 + 10.5/14 文案，与歌单详情 / 历史 / 我喜欢的保持同一套尺寸。 */
const SELECTION_BAR_ICON: number = 22;
const SELECTION_BAR_LABEL_SIZE: number = 10.5;
const SELECTION_BAR_LABEL_LINE_HEIGHT: number = 14;
const SELECTION_BAR_ITEM_GAP: number = 3;
const SELECTION_BAR_ITEM_PADDING: number = 4;

/**
 * 多选底栏的单个动作。
 *
 * `enabledFlag` 必须是 `@Prop`：如果把 `canActOnSelection()` 按值传给 `@Builder`，ArkUI
 * 只会在首次渲染时取一次值，之后勾选状态变化不会刷新按钮，表现为整条底栏一直灰着。
 * 颜色也在这里按可用态切换，避免按钮可用但图标仍是 `textSecondary` 的误判。
 *
 * 入参名用 `selectorId`：`id` 是 `CustomComponent` 自带的属性方法，同名字段会编译失败。
 */
@Component
export struct SelectionBarButton {
  @Prop selectorId: string = '';
  @Prop iconKind: AppIconKind = AppIconKind.Play;
  @Prop label: ResourceStr = '';
  @Prop enabledFlag: boolean = false;
  onTap: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: SELECTION_BAR_ITEM_GAP }) {
        AppIcon({
          iconKind: this.iconKind,
          iconSize: SELECTION_BAR_ICON,
          iconColor: this.enabledFlag ? ThemeColors.textPrimary : ThemeColors.textSecondary
        })
        Text(this.label)
          .fontSize(SELECTION_BAR_LABEL_SIZE)
          .lineHeight(SELECTION_BAR_LABEL_LINE_HEIGHT)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.enabledFlag ? ThemeColors.textPrimary : ThemeColors.textSecondary)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .id(this.selectorId)
    .layoutWeight(1)
    .padding({
      top: SELECTION_BAR_ITEM_PADDING,
      bottom: SELECTION_BAR_ITEM_PADDING,
      left: 2,
      right: 2
    })
    .borderRadius(ThemeRadius.md)
    .backgroundColor(Color.Transparent)
    .enabled(this.enabledFlag)
    .opacity(this.enabledFlag ? 1 : 0.35)
    .onClick(() => {
      this.onTap();
    })
  }
}