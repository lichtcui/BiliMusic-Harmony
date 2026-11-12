import { SettingsStore } from '../../state/SettingsStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { AudioQuality } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { BottomSheet } from './BottomSheet';
import { NativeUiIds } from './NativeUiIds';
import { SheetSize } from './SheetSizing';

const QUALITY_OPTION_HEIGHT: number = 52;
const QUALITY_OPTION_ICON: number = 20;

/**
 * 「音质选择」抽屉：播放控制页的音质格、设置页的「播放音质」行与「下载品质」行共用。
 * 目标由 `target` 区分：`playback` 读写 `audioQuality`，`download` 读写 `downloadQuality`。
 *
 * 只展示用户偏好档位，不显示服务端实际协商到的码率；曲目缺少目标档位时由
 * `AudioFallback` 向下逐级降级。选中后由宿主先持久化偏好：播放目标再让播放器按当前
 * 进度重载，下载目标只影响之后的新下载；保存失败时留在抽屉内提示，不静默关闭。
 */
export type QualitySheetTarget = 'playback' | 'download';

@Component
export struct AudioQualitySheet {
  @ObjectLink settingsStore: SettingsStore;
  /** 抽屉目标：播放音质写 `audioQuality`，下载品质写 `downloadQuality`。 */
  target: QualitySheetTarget = 'playback';
  /**
   * 进出场位移 / 蒙层透明度必须用 `@Prop`：宿主的 `onAppear` 动画会在挂载后把这两个值
   * 从「屏外 / 透明」改成「0 / 1」。普通成员变量只在首次构造时取值，之后父组件更新
   * 不会同步，抽屉会永远停在屏外。
   */
  @Prop panelOffsetY: number = 0;
  @Prop scrimAlpha: number = 1;
  onClose: () => void = (): void => {};
  onSelect: (quality: AudioQuality) => Promise<boolean> =
    (_quality: AudioQuality): Promise<boolean> => Promise.resolve(false);

  @State private busy: boolean = false;
  @State private failed: boolean = false;
  /**
   * 保存期间用户仍可点蒙层关闭；卸载后不能再写 `@State`，否则会在销毁流程里触发重建。
   * 普通成员位不受 `aboutToDisappear` 的状态写入限制。
   */
  private disposed: boolean = false;

  aboutToDisappear(): void {
    this.disposed = true;
  }

  build() {
    BottomSheet({
      sheetId: this.sheetId(),
      title: this.sheetTitle(),
      subtitle: this.subtitle(),
      sheetSize: SheetSize.Compact,
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
      Column() {
        this.OptionRow('high', $r('app.string.audio_quality_high'), '192K')
        this.OptionRow('standard', $r('app.string.audio_quality_standard'), '132K')
        this.OptionRow('low', $r('app.string.audio_quality_low'), '64K')
      }
      .width('100%')

      if (this.failed) {
        Text($r('app.string.audio_quality_save_failed'))
          .id(this.saveErrorId())
          .width('100%')
          .fontSize(ThemeTypography.eyebrow)
          .fontColor(ThemeColors.danger)
          .margin({ top: ThemeSpacing.sm })
      }

      Blank()

      Text(this.footerText())
        .id(this.footerId())
        .width('100%')
        .fontSize(ThemeTypography.playerPanelMeta)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ top: ThemeSpacing.md })
    }
    .id(this.contentId())
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: ThemeSpacing.sm })
  }

  /**
   * 档位行单独成 Builder：选中态直接读 `settingsStore`，不把 `selected` 当参数传进来，
   * 避免 @Builder 按值传参后 store 更新而这一行不重绘（与功能页 ModeTile 同一个坑）。
   */
  @Builder
  OptionRow(quality: AudioQuality, label: ResourceStr, bitrate: string) {
    Row() {
      Text(label)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)

      Text(bitrate)
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textSecondary)
        .margin({ left: ThemeSpacing.xs })

      Blank()

      if (this.currentQuality() === quality) {
        AppIcon({
          iconKind: AppIconKind.Check,
          iconSize: QUALITY_OPTION_ICON,
          iconColor: ThemeColors.accent
        })
      }
    }
    .id(this.optionId(quality))
    .width('100%')
    .height(QUALITY_OPTION_HEIGHT)
    .padding({
      left: ThemeSpacing.md,
      right: ThemeSpacing.md
    })
    .borderRadius(ThemeRadius.md)
    .backgroundColor(this.currentQuality() === quality ?
      ThemeColors.accentSoft : Color.Transparent)
    .enabled(!this.busy)
    .opacity(this.busy ? 0.6 : 1)
    .onClick((): void => {
      void this.choose(quality);
    })
    .accessibilityText(this.qualityResource(quality))
  }

  /**
   * 三档名称统一走 `string.json`：可见标签（`OptionRow`）、副标题与无障碍朗读共用同一份资源，
   * 避免「高品质 / 省流 / 标准」在两处方法里各写一遍。
   */
  private qualityResource(quality: AudioQuality): Resource {
    if (quality === 'high') {
      return $r('app.string.audio_quality_high');
    }
    if (quality === 'low') {
      return $r('app.string.audio_quality_low');
    }
    return $r('app.string.audio_quality_standard');
  }

  private subtitle(): string {
    const name = this.resourceText(this.qualityResource(this.currentQuality()));
    return getContext(this).resourceManager.getStringSync(
      $r('app.string.audio_quality_current').id, name);
  }

  private currentQuality(): AudioQuality {
    return this.target === 'download' ?
      this.settingsStore.snapshot.downloadQuality :
      this.settingsStore.snapshot.audioQuality;
  }

  private sheetId(): string {
    return this.target === 'download' ?
      NativeUiIds.downloadQualitySheet : NativeUiIds.audioQualitySheet;
  }

  private contentId(): string {
    return this.target === 'download' ?
      NativeUiIds.downloadQualityContent : NativeUiIds.audioQualityContent;
  }

  private saveErrorId(): string {
    return this.target === 'download' ?
      NativeUiIds.downloadQualitySaveError : NativeUiIds.audioQualitySaveError;
  }

  private footerId(): string {
    return this.target === 'download' ?
      NativeUiIds.downloadQualityFooter : NativeUiIds.audioQualityFooter;
  }

  private optionId(quality: AudioQuality): string {
    return this.target === 'download' ?
      NativeUiIds.downloadQualityOption(quality) :
      NativeUiIds.audioQualityOption(quality);
  }

  private sheetTitle(): ResourceStr {
    return this.target === 'download' ?
      $r('app.string.settings_download_quality') :
      $r('app.string.player_panel_quality');
  }

  private footerText(): Resource {
    return this.target === 'download' ?
      $r('app.string.download_quality_footer') :
      $r('app.string.audio_quality_footer');
  }

  private resourceText(resource: Resource): string {
    return getContext(this).resourceManager.getStringSync(resource.id);
  }

  private async choose(quality: AudioQuality): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.failed = false;
    try {
      const success = await this.onSelect(quality);
      if (this.disposed) {
        return;
      }
      if (success) {
        this.onClose();
      } else {
        this.failed = true;
      }
    } catch (error) {
      if (!this.disposed) {
        this.failed = true;
      }
    } finally {
      if (!this.disposed) {
        this.busy = false;
      }
    }
  }
}