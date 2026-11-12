import { bundleManager, common } from '@kit.AbilityKit';
import { CacheManagementStore } from '../../state/CacheManagementStore';
import {
  SettingsPatch,
  SettingsStore,
  ThemeMode
} from '../../state/SettingsStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { APP_VERSION, AudioQuality } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { formatCacheBytes, totalCacheBytes } from './CacheSizeFormat';
import { NativeUiIds } from './NativeUiIds';

/**
 * 设置整页的实测几何（373 稿 1:1 换算成 vp，`design/mine-page.html` 的
 * `.settings-page` ~ `.settings-retry` 是唯一依据）。
 *
 * 头部 8 + 40 + 8 = 56；返回圆钮 40 / 图标 22 / 标题间距 4 / 右内边距 12。
 * 滚动区 上 4、左右 24（`ThemeSpacing.gutter`）、下 32；组间距 24；内容顶部 8。
 * 组标题下 6、左右缩进 2；行高 52、行内 gap 8、行图标 18、右箭头 16。
 * 分段轨 200×34（内衬 3、格间 3、格 28、格圆角 6）；开关 40×24。
 * 错误条上 10、左边框 2、文字左内缩 12；重试通栏 44、上 10、1px 描边、圆角 10。
 */
const SETTINGS_HEADER_HEIGHT: number = 56;
const SETTINGS_HEADER_SIDE_PADDING: number = ThemeSpacing.sm;
const SETTINGS_HEADER_RIGHT_PADDING: number = ThemeSpacing.md;
const SETTINGS_HEADER_GAP: number = ThemeSpacing.xs;
const SETTINGS_BACK_SIZE: number = 40;
const SETTINGS_BACK_ICON_SIZE: number = 22;

const SETTINGS_SCROLL_TOP: number = ThemeSpacing.xs;
const SETTINGS_SCROLL_BOTTOM: number = 32;
const SETTINGS_CONTENT_TOP: number = ThemeSpacing.sm;
const SETTINGS_GROUP_GAP: number = ThemeSpacing.gutter;
const SETTINGS_LABEL_GAP: number = 6;
const SETTINGS_LABEL_INSET: number = 2;

const SETTINGS_ROW_HEIGHT: number = 52;
const SETTINGS_ROW_GAP: number = ThemeSpacing.sm;
const SETTINGS_ICON_SIZE: number = 18;
const SETTINGS_CHEVRON_SIZE: number = 16;
const SETTINGS_DIVIDER_WIDTH: number = 1;
const SETTINGS_FULL_OPACITY: number = 1;

const SETTINGS_SEGMENT_WIDTH: number = 200;
const SETTINGS_SEGMENT_HEIGHT: number = 34;
const SETTINGS_SEGMENT_PADDING: number = 3;
const SETTINGS_SEGMENT_GAP: number = 3;
const SETTINGS_SEGMENT_CELL_HEIGHT: number = 28;

const SETTINGS_SWITCH_WIDTH: number = 40;
const SETTINGS_SWITCH_HEIGHT: number = 24;

/** 缓存行忙碌时保留可读性，只压到 .6。 */
const SETTINGS_CACHE_BUSY_OPACITY: number = 0.6;

const SETTINGS_ERROR_GAP: number = 10;
const SETTINGS_ERROR_BORDER_WIDTH: number = 2;
const SETTINGS_ERROR_INSET: number = ThemeSpacing.md;
const SETTINGS_ERROR_PADDING_Y: number = 2;
/** 稿件 12/1.6。 */
const SETTINGS_ERROR_LINE_HEIGHT: number = 19.2;

const SETTINGS_RETRY_HEIGHT: number = 44;
const SETTINGS_RETRY_GAP: number = 10;
const SETTINGS_RETRY_BORDER_WIDTH: number = 1;
const SETTINGS_RETRY_DISABLED_OPACITY: number = 0.5;

/** 「关于」组的 GitHub 地址；点击后用系统浏览器打开，不在应用内加载网页。 */
const ABOUT_GITHUB_URL: string = 'https://github.com/lichtcui/wisp-music';

/**
 * 设置整页（T16，2026-11 从底部抽屉改成整页右滑）。
 *
 * 形态：根是 `Column { 头部; Scroll { 各组 } }`，不带蒙层、不带卡片底、不再复用
 * `BottomSheet`；进入 / 退出动画由 `Index` 的覆盖层负责（320ms 从右滑入）。
 * 分组：常规（主题模式 / 播放设置入口）→ 下载（下载品质 / 最多保留条数）→ 数据（缓存清理）
 * → 关于（版本 / 作者 / GitHub / 诊断信息 / 法律与免责声明），内容全部打平到页面底色上。
 * 「播放设置」原本平铺播放音质 / 自动播放 / 歌词显示三行，超过一屏内的舒适上限后收起为一个
 * 入口行，三项偏好在共用抽屉 `PlaybackSettingsSheet` 里维护。诊断信息只有一行，不再单独占
 * 一个「支持与诊断」分组。
 *
 * 无后端的项（导入/导出歌单）已从页面移除，不再渲染禁用行。
 *
 * 状态刷新：ArkTS 的 `@Builder` 一旦传入两个及以上按值参数，就不会再触发其内部 UI
 * 刷新（见官方 @Builder 限制条件）。所以凡是「值会变」的控件（主题三态、播放音质三态、
 * 两个开关）都不走带值参数的 @Builder，而是拆成独立 @Component + `@ObjectLink`
 * 直接读 store：只有这样才能在 themeMode / showLyrics / restorePlayback /
 * audioQuality 变化后把选中态刷出来。
 *
 * 业务语义、持久化与主题下发链路都与抽屉版完全一致，本文件只负责外壳与版式。
 */
@Component
export struct SettingsPage {
  @ObjectLink settingsStore: SettingsStore;
  @ObjectLink cacheStore: CacheManagementStore;
  onClose: () => void = (): void => {};
  onOpenDiagnostics: () => void = (): void => {};
  /** 播放设置入口行：打开根 Stack 上的播放设置抽屉（音质 / 自动播放 / 歌词显示）。 */
  onOpenPlaybackSheet: () => void = (): void => {};
  /** 下载品质三态：写 `downloadQuality`，只影响之后发起的新下载。 */
  onSelectDownloadQuality: (quality: AudioQuality) => Promise<boolean> =
    (_quality: AudioQuality): Promise<boolean> => Promise.resolve(false);
  /** 下载上限分段：写设置后由宿主立即清理超限下载；返回是否保存成功。 */
  onSelectDownloadLimit: (limit: number) => Promise<boolean> =
    (_limit: number): Promise<boolean> => Promise.resolve(false);
  /** 缓存清理行：打开根 Stack 上的缓存清理抽屉（不再弹系统 modal）。 */
  onOpenCacheSheet: () => void = (): void => {};
  /** 法律与免责声明行：打开根 Stack 上的免责声明抽屉（不再弹系统 modal）。 */
  onOpenLegalSheet: () => void = (): void => {};
  /** 只在页面挂载时读一次包信息；读不到时退回编译期常量，不阻塞设置页。 */
  @State private appVersion: string = APP_VERSION;

  aboutToAppear(): void {
    this.appVersion = readAppVersion();
  }

  @Builder
  Header() {
    Row({ space: SETTINGS_HEADER_GAP }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        AppIcon({
          iconKind: AppIconKind.Back,
          iconSize: SETTINGS_BACK_ICON_SIZE,
          iconColor: ThemeColors.textPrimary
        })
      }
      .id(NativeUiIds.settingsBack)
      .width(SETTINGS_BACK_SIZE)
      .height(SETTINGS_BACK_SIZE)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.settings_back'))
      .onClick(() => {
        this.onClose();
      })

      Text($r('app.string.nav_settings'))
        .layoutWeight(1)
        .fontSize(ThemeTypography.pageHeaderTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(SETTINGS_HEADER_HEIGHT)
    .padding({
      left: SETTINGS_HEADER_SIDE_PADDING,
      right: SETTINGS_HEADER_RIGHT_PADDING,
      top: SETTINGS_HEADER_SIDE_PADDING,
      bottom: SETTINGS_HEADER_SIDE_PADDING
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  GroupLabel(label: ResourceStr) {
    Text(label)
      .width('100%')
      .fontSize(ThemeTypography.groupLabel)
      .fontWeight(FontWeight.Medium)
      .fontColor(ThemeColors.textSecondary)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: SETTINGS_LABEL_INSET, right: SETTINGS_LABEL_INSET })
      .margin({ bottom: SETTINGS_LABEL_GAP })
  }

  /** 同组相邻行之间的 1px 分隔线；首行与组尾不画。 */
  @Builder
  RowDivider() {
    Divider()
      .width('100%')
      .strokeWidth(SETTINGS_DIVIDER_WIDTH)
      .color(ThemeColors.line)
  }

  /** 错误条：无底色，只留左侧 2px 细线与 12 的正文缩进（稿件实测）。 */
  @Builder
  ErrorBar(id: string, message: ResourceStr) {
    Row() {
      Text(message)
        .id(id)
        .layoutWeight(1)
        .fontSize(ThemeTypography.meta)
        .lineHeight(SETTINGS_ERROR_LINE_HEIGHT)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({
      left: SETTINGS_ERROR_INSET,
      top: SETTINGS_ERROR_PADDING_Y,
      bottom: SETTINGS_ERROR_PADDING_Y
    })
    .margin({ top: SETTINGS_ERROR_GAP })
    .border({ width: { left: SETTINGS_ERROR_BORDER_WIDTH }, color: ThemeColors.line })
  }

  /** 重试：透明底 + 1px 描边，与登录抽屉的描边动作按钮同一档圆角。 */
  @Builder
  RetryButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Text(this.retryCacheLabel())
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)
    }
    .id(NativeUiIds.settingsCacheRetry)
    .width('100%')
    .height(SETTINGS_RETRY_HEIGHT)
    .margin({ top: SETTINGS_RETRY_GAP })
    .padding(0)
    .backgroundColor(Color.Transparent)
    .border({ width: SETTINGS_RETRY_BORDER_WIDTH, color: ThemeColors.line, radius: ThemeRadius.control })
    .borderRadius(ThemeRadius.control)
    .enabled(!this.cacheStore.isBusy())
    .opacity(this.cacheStore.isBusy() ? SETTINGS_RETRY_DISABLED_OPACITY : SETTINGS_FULL_OPACITY)
    .onClick(() => {
      void this.cacheStore.retry();
    })
  }

  /** 主题三态：三格各自订阅 store，选中态随 `snapshot.themeMode` 单独刷新。 */
  @Builder
  ThemeModeSegment() {
    Row({ space: SETTINGS_SEGMENT_GAP }) {
      SettingsThemeCell({
        settingsStore: this.settingsStore,
        cellId: NativeUiIds.settingsThemeLight,
        label: $r('app.string.settings_theme_light'),
        mode: 'light'
      })
      SettingsThemeCell({
        settingsStore: this.settingsStore,
        cellId: NativeUiIds.settingsThemeDark,
        label: $r('app.string.settings_theme_dark'),
        mode: 'dark'
      })
      SettingsThemeCell({
        settingsStore: this.settingsStore,
        cellId: NativeUiIds.settingsThemeSystem,
        label: $r('app.string.settings_theme_system'),
        mode: 'system'
      })
    }
    .width(SETTINGS_SEGMENT_WIDTH)
    .height(SETTINGS_SEGMENT_HEIGHT)
    .padding(SETTINGS_SEGMENT_PADDING)
    .backgroundColor(ThemeColors.chipUnselected)
    .borderRadius(ThemeRadius.md)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ThemeModeRow() {
    Row({ space: SETTINGS_ROW_GAP }) {
      Row({ space: SETTINGS_ROW_GAP }) {
        AppIcon({
          iconKind: AppIconKind.Night,
          iconSize: SETTINGS_ICON_SIZE,
          iconColor: ThemeColors.textSecondary
        })
        Text($r('app.string.settings_theme_mode'))
          .id(NativeUiIds.settingsThemeMode)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      this.ThemeModeSegment()
    }
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  GeneralGroup() {
    Column() {
      this.GroupLabel($r('app.string.settings_general_section'))
      Column() {
        this.ThemeModeRow()
        this.RowDivider()
        this.PlaybackEntryRow()
      }
      .width('100%')

      if (this.settingsStore.error !== null) {
        this.ErrorBar(
          NativeUiIds.settingsWriteError,
          $r('app.string.settings_write_failed')
        )
      }
    }
    .id(NativeUiIds.settingsGeneralSection)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 「播放设置」入口：三项播放偏好已移入共用抽屉，这里只留一行可点入口。 */
  @Builder
  PlaybackEntryRow() {
    Row({ space: SETTINGS_ROW_GAP }) {
      AppIcon({
        iconKind: AppIconKind.Note,
        iconSize: SETTINGS_ICON_SIZE,
        iconColor: ThemeColors.textSecondary
      })
      Text($r('app.string.settings_playback_section'))
        .layoutWeight(1)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      AppIcon({
        iconKind: AppIconKind.ChevronRight,
        iconSize: SETTINGS_CHEVRON_SIZE,
        iconColor: ThemeColors.textSecondary
      })
    }
    .id(NativeUiIds.settingsPlaybackSection)
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onOpenPlaybackSheet();
    })
  }

  /**
   * 数据：缓存清理。
   * 缓存行沿用整行可点 + 右侧容量 + 箭头的样式，与诊断行同一套；点击后由 `Index`
   * 在根 Stack 上弹出缓存清理抽屉（`CacheSheet`），行内不再弹系统确认框。
   */
  @Builder
  DataGroup() {
    Column() {
      this.GroupLabel($r('app.string.settings_data_section'))
      Column() {
        this.CacheRow()
      }
      .width('100%')

      if (this.cacheStore.error !== null) {
        this.ErrorBar(
          NativeUiIds.settingsCacheError,
          $r('app.string.settings_cache_failed')
        )
        this.RetryButton()
      }
    }
    .id(NativeUiIds.settingsDataSection)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 下载：下载品质 + 最多保留条数。
   *
   * 品质与播放音质同构，是三格分段（省流 / 标准 / 高品质），写 `downloadQuality`，
   * 只影响之后的新下载；条数是用户可见的存储口径，选中后先写设置再由宿主立即清理超限的
   * 最旧下载；总字节另有 4 GB 内部上限，作为单一文件过大时的兜底，不在 UI 里单独暴露。
   */
  @Builder
  DownloadGroup() {
    Column() {
      this.GroupLabel($r('app.string.settings_download_section'))
      Column() {
        this.DownloadQualityRow()
        Text($r('app.string.settings_download_quality_note'))
          .id(NativeUiIds.settingsDownloadQualityNote)
          .width('100%')
          .fontSize(ThemeTypography.meta)
          .fontColor(ThemeColors.textSecondary)
          .padding({ left: SETTINGS_LABEL_INSET, right: SETTINGS_LABEL_INSET })
          .margin({ bottom: SETTINGS_LABEL_GAP })
        this.RowDivider()
        this.DownloadLimitRow()
      }
      .width('100%')

      Text($r('app.string.settings_download_limit_note'))
        .width('100%')
        .fontSize(ThemeTypography.meta)
        .fontColor(ThemeColors.textSecondary)
        .padding({ left: SETTINGS_LABEL_INSET, right: SETTINGS_LABEL_INSET })
        .margin({ top: SETTINGS_LABEL_GAP })
    }
    .id(NativeUiIds.settingsDownloadSection)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DownloadQualityRow() {
    Row({ space: SETTINGS_ROW_GAP }) {
      Row({ space: SETTINGS_ROW_GAP }) {
        AppIcon({
          iconKind: AppIconKind.Quality,
          iconSize: SETTINGS_ICON_SIZE,
          iconColor: ThemeColors.textSecondary
        })
        Text($r('app.string.settings_download_quality'))
          .id(NativeUiIds.settingsDownloadQuality)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      Row({ space: SETTINGS_SEGMENT_GAP }) {
        SettingsQualityCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsDownloadQualityLow,
          label: $r('app.string.audio_quality_low'),
          quality: 'low',
          field: 'downloadQuality',
          onSelect: this.onSelectDownloadQuality
        })
        SettingsQualityCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsDownloadQualityStandard,
          label: $r('app.string.audio_quality_standard'),
          quality: 'standard',
          field: 'downloadQuality',
          onSelect: this.onSelectDownloadQuality
        })
        SettingsQualityCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsDownloadQualityHigh,
          label: $r('app.string.audio_quality_high'),
          quality: 'high',
          field: 'downloadQuality',
          onSelect: this.onSelectDownloadQuality
        })
      }
      .width(SETTINGS_SEGMENT_WIDTH)
      .height(SETTINGS_SEGMENT_HEIGHT)
      .padding(SETTINGS_SEGMENT_PADDING)
      .backgroundColor(ThemeColors.chipUnselected)
      .borderRadius(ThemeRadius.md)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  DownloadLimitRow() {
    Row({ space: SETTINGS_ROW_GAP }) {
      Row({ space: SETTINGS_ROW_GAP }) {
        AppIcon({
          iconKind: AppIconKind.Download,
          iconSize: SETTINGS_ICON_SIZE,
          iconColor: ThemeColors.textSecondary
        })
        Text($r('app.string.settings_download_limit'))
          .id(NativeUiIds.settingsDownloadLimit)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      Row({ space: SETTINGS_SEGMENT_GAP }) {
        SettingsDownloadLimitCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsDownloadLimitOption(100),
          label: $r('app.string.settings_download_limit_100'),
          limit: 100,
          onSelect: this.onSelectDownloadLimit
        })
        SettingsDownloadLimitCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsDownloadLimitOption(300),
          label: $r('app.string.settings_download_limit_300'),
          limit: 300,
          onSelect: this.onSelectDownloadLimit
        })
        SettingsDownloadLimitCell({
          settingsStore: this.settingsStore,
          cellId: NativeUiIds.settingsDownloadLimitOption(500),
          label: $r('app.string.settings_download_limit_500'),
          limit: 500,
          onSelect: this.onSelectDownloadLimit
        })
      }
      .width(SETTINGS_SEGMENT_WIDTH)
      .height(SETTINGS_SEGMENT_HEIGHT)
      .padding(SETTINGS_SEGMENT_PADDING)
      .backgroundColor(ThemeColors.chipUnselected)
      .borderRadius(ThemeRadius.md)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  CacheRow() {
    Row({ space: SETTINGS_ROW_GAP }) {
      AppIcon({
        iconKind: AppIconKind.Brush,
        iconSize: SETTINGS_ICON_SIZE,
        iconColor: ThemeColors.textSecondary
      })
      Text($r('app.string.settings_cache_clear_label'))
        .layoutWeight(1)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(formatCacheBytes(
        totalCacheBytes(this.cacheStore.imageStats, this.cacheStore.lyricsStats,
          this.cacheStore.audioStats)
      ))
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(1)
      AppIcon({
        iconKind: AppIconKind.ChevronRight,
        iconSize: SETTINGS_CHEVRON_SIZE,
        iconColor: ThemeColors.textSecondary
      })
    }
    .id(NativeUiIds.settingsCacheClear)
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .enabled(!this.cacheStore.isBusy())
    .opacity(this.cacheStore.isBusy() ? SETTINGS_CACHE_BUSY_OPACITY : SETTINGS_FULL_OPACITY)
    .onClick(() => {
      this.onOpenCacheSheet();
    })
  }

  /** 只读值行：左侧标题、右侧值，不带箭头（应用版本 / 作者）。 */
  @Builder
  AboutValueRow(id: string, label: ResourceStr, value: ResourceStr) {
    Row({ space: SETTINGS_ROW_GAP }) {
      Text(label)
        .layoutWeight(1)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(id)
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  /** 带值的可点行：GitHub 这类「右侧显示仓库名、点击跳转」的条目。 */
  @Builder
  AboutLinkValueRow(id: string, label: ResourceStr, value: ResourceStr, onTap: () => void) {
    Row({ space: SETTINGS_ROW_GAP }) {
      Text(label)
        .layoutWeight(1)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      AppIcon({
        iconKind: AppIconKind.ChevronRight,
        iconSize: SETTINGS_CHEVRON_SIZE,
        iconColor: ThemeColors.textSecondary
      })
    }
    .id(id)
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  /** 纯动作行：诊断信息 / 法律与免责声明。 */
  @Builder
  AboutActionRow(id: string, label: ResourceStr, onTap: () => void) {
    Row({ space: SETTINGS_ROW_GAP }) {
      Text(label)
        .layoutWeight(1)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      AppIcon({
        iconKind: AppIconKind.ChevronRight,
        iconSize: SETTINGS_CHEVRON_SIZE,
        iconColor: ThemeColors.textSecondary
      })
    }
    .id(id)
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  /**
   * 关于：应用版本 / 作者 / GitHub / 诊断信息 / 法律与免责声明。
   *
   * 版本与作者是只读信息，不画箭头；GitHub 缺少可用的应用内网页容器，交给系统浏览器；
   * 诊断信息打开设置页之上的诊断抽屉，法律与免责声明打开底部抽屉（`LegalNoticeSheet`），
   * 长正文可滚动，不再弹系统对话框。诊断信息只有一行，并入本组后不再单独占一个分组。
   */
  @Builder
  AboutGroup() {
    Column() {
      this.GroupLabel($r('app.string.settings_about_section'))
      Column() {
        this.AboutValueRow(
          NativeUiIds.settingsAppVersion,
          $r('app.string.settings_app_version'),
          this.appVersion
        )
        this.RowDivider()
        this.AboutValueRow(
          NativeUiIds.settingsAuthor,
          $r('app.string.settings_author'),
          $r('app.string.settings_author_value')
        )
        this.RowDivider()
        this.AboutLinkValueRow(
          NativeUiIds.settingsGithub,
          $r('app.string.settings_github'),
          $r('app.string.settings_github_value'),
          (): void => {
            this.openGithub();
          }
        )
        this.RowDivider()
        this.AboutActionRow(
          NativeUiIds.settingsOpenDiagnostics,
          $r('app.string.settings_open_diagnostics'),
          (): void => {
            this.onOpenDiagnostics();
          }
        )
        this.RowDivider()
        this.AboutActionRow(
          NativeUiIds.settingsLegal,
          $r('app.string.settings_legal'),
          (): void => {
            this.onOpenLegalSheet();
          }
        )
      }
      .width('100%')
    }
    .id(NativeUiIds.settingsAboutSection)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      this.Header()

      Scroll() {
        Column({ space: SETTINGS_GROUP_GAP }) {
          this.GeneralGroup()
          this.DownloadGroup()
          this.DataGroup()
          this.AboutGroup()
        }
        .id(NativeUiIds.settingsContent)
        .width('100%')
        .padding({ top: SETTINGS_CONTENT_TOP })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: ThemeSpacing.gutter,
        right: ThemeSpacing.gutter,
        top: SETTINGS_SCROLL_TOP,
        bottom: SETTINGS_SCROLL_BOTTOM
      })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .id(NativeUiIds.settingsPage)
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bg)
  }

  private hostContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
  }

  /** 交给系统浏览器；没有可用浏览器或拉起失败时退回一个可读的地址对话框。 */
  private openGithub(): void {
    const context = this.hostContext();
    if (context === undefined) {
      this.showGithubFallback();
      return;
    }
    void context.openLink(ABOUT_GITHUB_URL).catch((): void => {
      this.showGithubFallback();
    });
  }

  private showGithubFallback(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.settings_github'),
      message: ABOUT_GITHUB_URL,
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.settings_about_ok'),
        defaultFocus: true,
        action: (): void => {}
      }
    });
  }

  private retryCacheLabel(): ResourceStr {
    return this.cacheStore.isBusy() ?
      $r('app.string.settings_cache_retrying') :
      $r('app.string.settings_cache_retry');
  }
}

/**
 * 主题三态的其中一格。
 *
 * 独立成 @Component 而不是 `SegmentCell(...)` 那样的 @Builder：`@Builder` 传入两个及以上
 * 按值参数后不再刷新内部 UI，选中态会永远停在首次渲染的「系统」；这里用 `@ObjectLink`
 * 订阅 store，`snapshot.themeMode` 一变本组件就重建，选中滑块才会跟着走。
 */
@Component
struct SettingsThemeCell {
  @ObjectLink settingsStore: SettingsStore;
  cellId: string = '';
  label: ResourceStr = '';
  mode: ThemeMode = 'system';
  @State private busy: boolean = false;

  build() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Text(this.label)
        .fontSize(ThemeTypography.eyebrow)
        .fontWeight(this.selected() ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected() ? ThemeColors.onAccent : ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(this.cellId)
    .layoutWeight(1)
    .height(SETTINGS_SEGMENT_CELL_HEIGHT)
    .padding(0)
    .backgroundColor(this.selected() ? ThemeColors.segmentThumb : Color.Transparent)
    .borderRadius(ThemeRadius.tile)
    .enabled(!this.busy)
    .onClick(() => {
      void this.select();
    })
  }

  private selected(): boolean {
    return this.settingsStore.snapshot.themeMode === this.mode;
  }

  private async select(): Promise<void> {
    if (this.busy || this.selected()) {
      return;
    }
    this.busy = true;
    const patch: SettingsPatch = { themeMode: this.mode };
    try {
      await this.settingsStore.update(patch);
    } catch (error) {
    } finally {
      this.busy = false;
    }
  }
}

/**
 * 音质偏好的字段名；播放音质与下载品质共用同一套三档格。
 */
type SettingsQualityField = 'audioQuality' | 'downloadQuality';

/**
 * 播放音质 / 下载品质三态共用的其中一格。
 *
 * 与主题三态同构：选中态由 `@ObjectLink` 直接读 store，避免 @Builder 按值传参后
 * 保存失败回滚时滑块停在点下去的位置。点击后交给宿主持久化；
 * 播放音质还会让播放器按当前进度重载当前曲目。
 */
@Component
export struct SettingsQualityCell {
  @ObjectLink settingsStore: SettingsStore;
  cellId: string = '';
  label: Resource = $r('app.string.audio_quality_low');
  quality: AudioQuality = 'low';
  /** 读写哪一项偏好：播放音质或下载品质。 */
  field: SettingsQualityField = 'audioQuality';
  onSelect: (quality: AudioQuality) => Promise<boolean> =
    (_quality: AudioQuality): Promise<boolean> => Promise.resolve(false);
  @State private busy: boolean = false;

  build() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Text(this.label)
        .fontSize(ThemeTypography.eyebrow)
        .fontWeight(this.selected() ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected() ? ThemeColors.onAccent : ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(this.cellId)
    .layoutWeight(1)
    .height(SETTINGS_SEGMENT_CELL_HEIGHT)
    .padding(0)
    .backgroundColor(this.selected() ? ThemeColors.segmentThumb : Color.Transparent)
    .borderRadius(ThemeRadius.tile)
    .enabled(!this.busy)
    .onClick(() => {
      void this.select();
    })
    .accessibilityText(this.label)
  }

  private selected(): boolean {
    const snapshot = this.settingsStore.snapshot;
    const current = this.field === 'downloadQuality' ?
      snapshot.downloadQuality : snapshot.audioQuality;
    return current === this.quality;
  }

  private async select(): Promise<void> {
    if (this.busy || this.selected()) {
      return;
    }
    this.busy = true;
    try {
      await this.onSelect(this.quality);
    } catch (error) {
    } finally {
      this.busy = false;
    }
  }
}

/**
 * 下载上限的其中一格。
 *
 * 与主题三态同构：选中态由 `@ObjectLink` 直接读 store，避免 @Builder 按值传参后
 * 保存失败回滚时滑块停在点下去的位置。点击后交给宿主写设置并立即清理超限下载。
 */
@Component
struct SettingsDownloadLimitCell {
  @ObjectLink settingsStore: SettingsStore;
  cellId: string = '';
  label: Resource = $r('app.string.settings_download_limit');
  limit: number = 500;
  onSelect: (limit: number) => Promise<boolean> =
    (_limit: number): Promise<boolean> => Promise.resolve(false);
  @State private busy: boolean = false;

  build() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Text(this.label)
        .fontSize(ThemeTypography.eyebrow)
        .fontWeight(this.selected() ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected() ? ThemeColors.onAccent : ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(this.cellId)
    .layoutWeight(1)
    .height(SETTINGS_SEGMENT_CELL_HEIGHT)
    .padding(0)
    .backgroundColor(this.selected() ? ThemeColors.segmentThumb : Color.Transparent)
    .borderRadius(ThemeRadius.tile)
    .enabled(!this.busy)
    .onClick(() => {
      void this.select();
    })
    .accessibilityText(this.label)
  }

  private selected(): boolean {
    return this.settingsStore.snapshot.downloadLimit === this.limit;
  }

  private async select(): Promise<void> {
    if (this.busy || this.selected()) {
      return;
    }
    this.busy = true;
    try {
      await this.onSelect(this.limit);
    } catch (error) {
    } finally {
      this.busy = false;
    }
  }
}

/** 设置里的开关字段；两个开关共用同一个组件，只是读写不同的设置项。 */
type SettingsSwitchField = 'restorePlayback' | 'showLyrics';

/**
 * 自动播放 / 歌词显示开关。
 *
 * 与 `SettingsThemeCell` 同理：`isOn` 由本组件直接读 `snapshot`，不走 @Builder 的
 * 按值参数，否则写入失败回滚时开关会停在点下去的位置、与真实设置不一致。
 */
@Component
export struct SettingsSwitchRow {
  @ObjectLink settingsStore: SettingsStore;
  rowId: string = '';
  field: SettingsSwitchField = 'restorePlayback';
  label: ResourceStr = '';
  @State private busy: boolean = false;

  build() {
    Row({ space: SETTINGS_ROW_GAP }) {
      Text(this.label)
        .layoutWeight(1)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick(() => {
          void this.apply(!this.currentValue());
        })
      Toggle({
        type: ToggleType.Switch,
        isOn: this.currentValue()
      })
        .id(this.rowId)
        .width(SETTINGS_SWITCH_WIDTH)
        .height(SETTINGS_SWITCH_HEIGHT)
        /* 稿件：开 = accent 轨道 + 白色拇指；两个角色都从主题令牌取，深色不另加特例。 */
        .selectedColor(ThemeColors.controlTrack)
        .switchPointColor(ThemeColors.controlThumb)
        .switchStyle({ unselectedColor: ThemeColors.surfaceInset })
        .enabled(!this.busy)
        .onChange((value: boolean) => {
          void this.apply(value);
        })
    }
    .width('100%')
    .height(SETTINGS_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  private currentValue(): boolean {
    return this.field === 'showLyrics' ?
      this.settingsStore.snapshot.showLyrics :
      this.settingsStore.snapshot.restorePlayback;
  }

  private async apply(value: boolean): Promise<void> {
    if (this.busy || value === this.currentValue()) {
      return;
    }
    this.busy = true;
    const patch: SettingsPatch = this.field === 'showLyrics' ?
      { showLyrics: value } : { restorePlayback: value };
    try {
      await this.settingsStore.update(patch);
    } catch (error) {
    } finally {
      this.busy = false;
    }
  }
}

/**
 * 应用版本以安装包为准；`bundleManager` 查询失败（例如未来在非 Ability 环境预览）时
 * 退回 `APP_VERSION`，保证「关于」行始终有值。
 */
function readAppVersion(): string {
  try {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return info.versionName.length > 0 ? info.versionName : APP_VERSION;
  } catch (error) {
    return APP_VERSION;
  }
}