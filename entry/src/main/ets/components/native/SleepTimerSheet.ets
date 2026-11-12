import {
  SleepTimerStore,
  formatSleepTimerRemaining
} from '../../state/SleepTimerStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { AppIcon, AppIconKind } from './AppIcon';
import { BottomSheet } from './BottomSheet';
import { NativeUiIds } from './NativeUiIds';
import { SheetSize } from './SheetSizing';

const TIMER_OPTION_HEIGHT: number = 52;
const TIMER_CANCEL_HEIGHT: number = 48;
const TIMER_OPTION_ICON: number = 20;

/**
 * 「定时关闭」抽屉：从播放控制功能页的定时格弹出。
 *
 * 只做分钟档：点任一档位立即开始 / 替换定时并收起抽屉；已开启时底部提供「关闭定时」。
 * 倒计时状态由宿主持有的 `SleepTimerStore` 驱动，关掉抽屉或退回播放页都不会停；
 * 到点只暂停播放，不退出应用。
 */
@Component
export struct SleepTimerSheet {
  @ObjectLink timerStore: SleepTimerStore;
  /**
   * 进出场位移 / 蒙层透明度必须用 `@Prop`：宿主的 `onAppear` 动画会在挂载后把这两个值
   * 从「屏外 / 透明」改成「0 / 1」。普通成员变量只在首次构造时取值，之后父组件更新
   * 不会同步，抽屉会永远停在屏外——表现就是「点了定时关闭但没有抽屉弹出」。
   */
  @Prop panelOffsetY: number = 0;
  @Prop scrimAlpha: number = 1;
  onClose: () => void = (): void => {};

  build() {
    BottomSheet({
      sheetId: NativeUiIds.sleepTimerSheet,
      title: $r('app.string.player_panel_timer'),
      subtitle: this.subtitle(),
      sheetSize: SheetSize.Medium,
      panelOffsetY: this.panelOffsetY,
      scrimAlpha: this.scrimAlpha,
      onClose: this.onClose
    }) {
      this.SheetContent()
    }
  }

  @Builder
  SheetContent() {
    Column() {
      Text($r('app.string.sleep_timer_pause_hint'))
        .width('100%')
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textSecondary)

      Column() {
        this.OptionRow(15)
        this.OptionRow(30)
        this.OptionRow(45)
        this.OptionRow(60)
        this.OptionRow(90)
      }
      .width('100%')
      .margin({ top: ThemeSpacing.sm })

      Blank()

      if (this.timerStore.activeMinutes > 0) {
        Row() {
          Text($r('app.string.sleep_timer_cancel'))
            .fontSize(ThemeTypography.body)
            .fontColor(ThemeColors.danger)
            .maxLines(1)
        }
        .id(NativeUiIds.sleepTimerCancel)
        .width('100%')
        .height(TIMER_CANCEL_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeColors.surfaceInset)
        .borderRadius(ThemeRadius.md)
        .margin({ top: ThemeSpacing.sm })
        .onClick((): void => {
          this.timerStore.cancel();
          this.onClose();
        })
        .accessibilityText($r('app.string.sleep_timer_cancel'))
      }

      Text($r('app.string.sleep_timer_footer'))
        .width('100%')
        .fontSize(ThemeTypography.playerPanelMeta)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ top: ThemeSpacing.md })
    }
    .id(NativeUiIds.sleepTimerContent)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: ThemeSpacing.sm })
  }

  /**
   * 档位行单独成 Builder：选中态直接读 `timerStore`，不把 `active` 当参数传进来，
   * 避免 @Builder 按值传参后 store 更新而这一行不重绘（与功能页 ModeTile 同一个坑）。
   */
  @Builder
  OptionRow(minutes: number) {
    Row() {
      Text(`${minutes} 分钟`)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)

      Blank()

      if (this.timerStore.activeMinutes === minutes) {
        AppIcon({
          iconKind: AppIconKind.Check,
          iconSize: TIMER_OPTION_ICON,
          iconColor: ThemeColors.accent
        })
      }
    }
    .id(NativeUiIds.sleepTimerOption(minutes))
    .width('100%')
    .height(TIMER_OPTION_HEIGHT)
    .padding({
      left: ThemeSpacing.md,
      right: ThemeSpacing.md
    })
    .borderRadius(ThemeRadius.md)
    .backgroundColor(this.timerStore.activeMinutes === minutes ?
      ThemeColors.accentSoft : Color.Transparent)
    .onClick((): void => {
      this.timerStore.start(minutes);
      this.onClose();
    })
    .accessibilityText(`${minutes} 分钟`)
  }

  private subtitle(): string {
    if (this.timerStore.activeMinutes <= 0) {
      return '';
    }
    return `剩余 ${formatSleepTimerRemaining(this.timerStore.remainingSeconds)}`;
  }
}
