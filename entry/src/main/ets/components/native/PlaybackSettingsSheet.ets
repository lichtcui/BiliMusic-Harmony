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
import { SettingsQualityCell, SettingsSwitchRow } from './SettingsPage';
import { SheetSize } from './SheetSizing';

const PLAYBACK_ROW_HEIGHT: number = 52;
const PLAYBACK_ROW_GAP: number = ThemeSpacing.sm;
const PLAYBACK_ICON_SIZE: number = 18;
const PLAYBACK_DIVIDER_WIDTH: number = 1;

const PLAYBACK_SEGMENT_WIDTH: number = 200;
const PLAYBACK_SEGMENT_HEIGHT: number = 34;
const PLAYBACK_SEGMENT_PADDING: number = 3;
const PLAYBACK_SEGMENT_GAP: number = 3;

const PLAYBACK_LABEL_INSET: number = 2;
const PLAYBACK_LABEL_GAP: number = 6;

/**
 * 「播放设置」抽屉：设置页「常规 › 播放设置」行弹出的共用底部抽屉。
 *
 * 设置页原本平铺「播放音质 / 自动播放 / 歌词显示」三行，行数已经超过一屏内的舒适上限，
 * 因此收起为一个入口行；三项偏好改在抽屉里维护：
 * - 播放音质三态直接写 `audioQuality`，由宿主持久化后让播放器按当前进度重载；
 * - 自动播放（`restorePlayback`）与歌词显示（`showLyrics`）各是一个开关。
 *
 * 三组控件都沿用设置页的 `SettingsQualityCell` / `SettingsSwitchRow`：选中态直接读
 * `settingsStore`，写入失败回滚时不会停在点下去的位置。外壳是全仓共用的 `BottomSheet`，
 * 与缓存清理 / 诊断 / 免责声明抽屉同一套 chrome。
 */
@Component
export struct PlaybackSettingsSheet {
  @ObjectLink settingsStore: SettingsStore;
  @Prop panelOffsetY: number = 0;
  @Prop scrimAlpha: number = 1;
  onClose: () => void = (): void => {};
  /** 播放音质三态：写 `audioQuality`，由宿主持久化后让播放器按当前进度重载。 */
  onSelectAudioQuality: (quality: AudioQuality) => Promise<boolean> =
    (_quality: AudioQuality): Promise<boolean> => Promise.resolve(false);

  build() {
    BottomSheet({
      sheetId: NativeUiIds.settingsPlaybackSheet,
      title: $r('app.string.settings_playback_section'),
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
      this.AudioQualityRow()
      Text($r('app.string.settings_audio_quality_note'))
        .id(NativeUiIds.settingsAudioQualityNote)
        .width('100%')
        .fontSize(ThemeTypography.meta)
        .fontColor(ThemeColors.textSecondary)
        .padding({ left: PLAYBACK_LABEL_INSET, right: PLAYBACK_LABEL_INSET })
        .margin({ bottom: PLAYBACK_LABEL_GAP })

      this.RowDivider()
      SettingsSwitchRow({
        settingsStore: this.settingsStore,
        rowId: NativeUiIds.settingsAutoPlay,
        field: 'restorePlayback',
        label: $r('app.string.settings_restore_playback')
      })
      this.RowDivider()
      SettingsSwitchRow({
        settingsStore: this.settingsStore,
        rowId: NativeUiIds.settingsShowLyrics,
        field: 'showLyrics',
        label: $r('app.string.settings_show_lyrics')
      })

      if (this.settingsStore.error !== null) {
        Text($r('app.string.settings_write_failed'))
          .id(NativeUiIds.settingsPlaybackSheetError)
          .width('100%')
          .fontSize(ThemeTypography.meta)
          .fontColor(ThemeColors.textSecondary)
          .margin({ top: PLAYBACK_LABEL_GAP })
      }
    }
    .id(NativeUiIds.settingsPlaybackSheetContent)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AudioQualityRow() {
    Row({ space: PLAYBACK_ROW_GAP }) {
      Row({ space: PLAYBACK_ROW_GAP }) {
        AppIcon({
          iconKind: AppIconKind.Quality,
          iconSize: PLAYBACK_ICON_SIZE,
          iconColor: ThemeColors.textSecondary
        })
        Text($r('app.string.settings_audio_quality'))
          .id(NativeUiIds.settingsAudioQuality)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Row({ space: PLAYBACK_SEGMENT_GAP }) {
        SettingsQualityCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsAudioQualityLow,
          label: $r('app.string.audio_quality_low'),
          quality: 'low',
          field: 'audioQuality',
          onSelect: this.onSelectAudioQuality
        })
        SettingsQualityCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsAudioQualityStandard,
          label: $r('app.string.audio_quality_standard'),
          quality: 'standard',
          field: 'audioQuality',
          onSelect: this.onSelectAudioQuality
        })
        SettingsQualityCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsAudioQualityHigh,
          label: $r('app.string.audio_quality_high'),
          quality: 'high',
          field: 'audioQuality',
          onSelect: this.onSelectAudioQuality
        })
      }
      .width(PLAYBACK_SEGMENT_WIDTH)
      .height(PLAYBACK_SEGMENT_HEIGHT)
      .padding(PLAYBACK_SEGMENT_PADDING)
      .backgroundColor(ThemeColors.chipUnselected)
      .borderRadius(ThemeRadius.md)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(PLAYBACK_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  RowDivider() {
    Divider()
      .width('100%')
      .strokeWidth(PLAYBACK_DIVIDER_WIDTH)
      .color(ThemeColors.line)
  }
}