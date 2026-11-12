import {
  ThemeColors,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { BottomSheet } from './BottomSheet';
import { NativeUiIds } from './NativeUiIds';
import { SheetSize } from './SheetSizing';

/** 正文行高：免责声明是成段文字，比列表说明（12/19）再松一档，长段落更好读。 */
const LEGAL_BODY_LINE_HEIGHT: number = 22;

/**
 * 法律与免责声明抽屉（设置页「关于」组入口）。
 *
 * 2026-11 之前点「法律与免责声明」弹的是系统 `showAlertDialog`：长正文被系统
 * 对话框的行数与宽度裁切，底部还必须摆一个「知道了」才能关闭。现在改成与
 * 缓存清理 / 诊断信息同一套外壳 `BottomSheet`（大档 78%）：
 *
 * - 头部：不设标题，外壳的头部整块收起，只剩拖拽条；圆角 / 安全区由外壳统一负责；
 * - 正文：整段免责声明放进 `Scroll`，长文本自己滚，不截断、不省略；
 * - 不做底部动作按钮：蒙层、拖拽条、下滑与系统返回都能收起抽屉，抽屉本身就是
 *   一个可关闭的说明面，不再保留「知道了」。
 *
 * 与其它抽屉一样挂在根 `Stack` 上：外壳的 `expandSafeArea` 需要铺到状态栏 /
 * 导航条，放进设置整页或 `NavDestination` 会被裁切。
 */
@Component
export struct LegalNoticeSheet {
  /** 宿主驱动的滑入 / 滑出位移（vp）：挂载前等于屏高，宿主动画回 0。 */
  @Prop panelOffsetY: number = 0;
  /** 宿主驱动的蒙层不透明度（0–1），与位移同步淡入淡出。 */
  @Prop scrimAlpha: number = 1;
  onClose: () => void = (): void => {};

  build() {
    BottomSheet({
      sheetId: NativeUiIds.settingsLegalSheet,
      // 不传标题：外壳头部整块收起，只剩拖拽条（与缓存 / 诊断抽屉一致）。
      // 免责声明正文分成两段、约 20 行：大档给足一屏阅读高度，超出部分在正文里滚动。
      sheetSize: SheetSize.Large,
      panelOffsetY: this.panelOffsetY,
      scrimAlpha: this.scrimAlpha,
      onClose: this.onClose
    }) {
      this.SheetContent()
    }
  }

  @Builder
  SheetContent() {
    Scroll() {
      Text($r('app.string.settings_legal_body'))
        .id(NativeUiIds.settingsLegalSheetContent)
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .lineHeight(LEGAL_BODY_LINE_HEIGHT)
        .fontColor(ThemeColors.textSecondary)
    }
    .width('100%')
    .layoutWeight(1)
    // 无标题抽屉的正文从拖拽条下方 16vp 起（与缓存抽屉一致），底部留一档收口。
    .padding({ top: ThemeSpacing.lg, bottom: ThemeSpacing.md })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }
}
