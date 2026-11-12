import {
  CacheManagementStore
} from '../../state/CacheManagementStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { BottomSheet } from './BottomSheet';
import {
  cacheStatsBytes,
  cacheStatsEmpty,
  cacheStatsEntries,
  formatCacheBytes
} from './CacheSizeFormat';
import { NativeUiIds } from './NativeUiIds';
import { SheetSize } from './SheetSizing';

/**
 * 内容顶部留白（vp）：本抽屉不显示标题，拖拽条下方直接是保留口径说明，
 * 与同样无标题的诊断抽屉取同一档 16，避免说明文字贴住拖拽条。
 */
const CACHE_CONTENT_TOP: number = ThemeSpacing.lg;
/** 分类行 56：标题 15 + 「N 项」12/18 + 2 间距，上下各留 13。 */
const CACHE_ROW_HEIGHT: number = 56;
/** 保留口径 12/19，与设置页错误条同一行高。 */
const CACHE_NOTE_LINE_HEIGHT: number = 19;
const CACHE_ERROR_BORDER_WIDTH: number = 2;
const CACHE_RETRY_HEIGHT: number = 32;
const CACHE_RETRY_PADDING: number = ThemeSpacing.md;
/** 底部通栏按钮 46 / 10 圆角，与登录抽屉动作按钮同一档。 */
const CACHE_ACTION_HEIGHT: number = 46;
/** 忙碌时保留可读性，空缓存则压到与设置页禁用项一致的 .42。 */
const CACHE_BUSY_OPACITY: number = 0.6;
const CACHE_DISABLED_OPACITY: number = 0.42;

/**
 * 缓存清理抽屉（设置页「缓存清理」行）。
 *
 * 2026-11 之前点这一行弹的是系统 `showAlertDialog` 二次确认，和全仓抽屉的视觉语言
 * 完全脱节；现在改成和登录 / 诊断 / 歌单抽屉同一套外壳 `BottomSheet`（中档 59%）。
 *
 * 布局沿用共用抽屉的版式：拖拽条 / 圆角 / 安全区由外壳提供；本抽屉不显示标题
 * （外壳头部整块收起），这里只排内容——
 *
 * - 保留口径：拖拽条下方留一档间距，说明清理不动收藏 / 歌单 / 登录 / 队列 / 进度；
 * - 列表：封面图片 / 歌词 / 音频三行，无卡片底色、无行内清理按钮，只显示容量与项数；
 * - 主操作：底部通栏「清理全部缓存」，空缓存或忙碌时禁用；
 * - 失败：列表下方错误条 + 「重试」，按出错的动作调用 store 的 `retry()`。
 *
 * 清理不弹二次确认：缓存本身可重建，抽屉就是确认面。三类缓存串行清理，某一类失败就
 * 停在这里并保留原统计，用户可直接重试。
 */
@Component
export struct CacheSheet {
  @ObjectLink cacheStore: CacheManagementStore;
  onClose: () => void = (): void => {};
  /** 宿主驱动的滑入 / 滑出位移（vp）：挂载前等于屏高，宿主动画回 0。 */
  @Prop panelOffsetY: number = 0;
  /** 宿主驱动的蒙层不透明度（0–1），与位移同步淡入淡出。 */
  @Prop scrimAlpha: number = 1;

  build() {
    BottomSheet({
      sheetId: NativeUiIds.settingsCacheSheet,
      // 不传标题：抽屉外壳的头部整块收起，保留口径说明从下方 16vp 处开始。
      // 内容只有说明 + 三行分类，但小档（232–300）放不下底部通栏按钮；
      // 中档（59%）留出的空白由底部按钮吸底吸收。
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
      Scroll() {
        Column({ space: ThemeSpacing.lg }) {
          Text($r('app.string.settings_cache_retention'))
            .width('100%')
            .fontSize(ThemeTypography.meta)
            .lineHeight(CACHE_NOTE_LINE_HEIGHT)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 无底色列表：行与行之间只用一条细分隔线收口，和设置页的列表语气一致。
          Column() {
            CacheStatRow({
              rowId: NativeUiIds.settingsCacheSheetImages,
              label: $r('app.string.settings_cache_images'),
              bytes: cacheStatsBytes(this.cacheStore.imageStats),
              entries: cacheStatsEntries(this.cacheStore.imageStats)
            })
            Divider()
              .width('100%')
              .strokeWidth(1)
              .color(ThemeColors.line)
            CacheStatRow({
              rowId: NativeUiIds.settingsCacheSheetLyrics,
              label: $r('app.string.settings_cache_lyrics'),
              bytes: cacheStatsBytes(this.cacheStore.lyricsStats),
              entries: cacheStatsEntries(this.cacheStore.lyricsStats)
            })
            Divider()
              .width('100%')
              .strokeWidth(1)
              .color(ThemeColors.line)
            CacheStatRow({
              rowId: NativeUiIds.settingsCacheSheetAudio,
              label: $r('app.string.settings_cache_audio'),
              bytes: cacheStatsBytes(this.cacheStore.audioStats),
              entries: cacheStatsEntries(this.cacheStore.audioStats)
            })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)

      if (this.cacheStore.error !== null) {
        this.ErrorBar()
      }

      this.ClearAllButton()
    }
    .id(NativeUiIds.settingsCacheSheetContent)
    .width('100%')
    .height('100%')
    .padding({ top: CACHE_CONTENT_TOP })
  }

  /** 失败条：左侧 2px 细线 + 行尾「重试」，与设置页的错误条同一套视觉。 */
  @Builder
  ErrorBar() {
    Row({ space: ThemeSpacing.sm }) {
      Text($r('app.string.settings_cache_failed'))
        .id(NativeUiIds.settingsCacheSheetError)
        .layoutWeight(1)
        .fontSize(ThemeTypography.meta)
        .lineHeight(CACHE_NOTE_LINE_HEIGHT)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button(this.retryLabel(), { stateEffect: false })
        .id(NativeUiIds.settingsCacheSheetRetry)
        .height(CACHE_RETRY_HEIGHT)
        .padding({ left: CACHE_RETRY_PADDING, right: CACHE_RETRY_PADDING })
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textPrimary)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: ThemeColors.line, radius: ThemeRadius.control })
        .borderRadius(ThemeRadius.control)
        .enabled(!this.cacheStore.isBusy())
        .opacity(this.cacheStore.isBusy() ? CACHE_BUSY_OPACITY : 1)
        .onClick(() => {
          void this.cacheStore.retry();
        })
    }
    .width('100%')
    .padding({
      left: ThemeSpacing.md,
      top: ThemeSpacing.xs,
      bottom: ThemeSpacing.xs
    })
    .margin({ top: ThemeSpacing.md })
    .border({ width: { left: CACHE_ERROR_BORDER_WIDTH }, color: ThemeColors.line })
    .alignItems(VerticalAlign.Center)
  }

  /** 主操作吸底：空缓存 / 刷新中 / 清理中都禁用，避免重复提交。 */
  @Builder
  ClearAllButton() {
    Button(this.cacheStore.clearing === '' ?
      $r('app.string.settings_cache_clear_all_action') :
      $r('app.string.settings_cache_clearing'), { stateEffect: false })
      .id(NativeUiIds.settingsCacheSheetClearAll)
      .width('100%')
      .height(CACHE_ACTION_HEIGHT)
      .margin({ top: ThemeSpacing.md })
      .fontSize(ThemeTypography.body)
      .fontWeight(FontWeight.Medium)
      .fontColor(ThemeColors.onAccent)
      .backgroundColor(ThemeColors.accent)
      .borderRadius(ThemeRadius.control)
      .enabled(this.canClearAll())
      .opacity(this.clearAllOpacity())
      .onClick(() => {
        void this.clearAll();
      })
  }

  private canClearAll(): boolean {
    return !this.cacheStore.isBusy() && !this.allCachesEmpty();
  }

  private clearAllOpacity(): number {
    if (this.cacheStore.isBusy()) {
      return CACHE_BUSY_OPACITY;
    }
    return this.allCachesEmpty() ? CACHE_DISABLED_OPACITY : 1;
  }

  /** 三类都空时才禁用「清理全部缓存」：单类为空另一类有内容仍可清。 */
  private allCachesEmpty(): boolean {
    return cacheStatsEmpty(this.cacheStore.imageStats) &&
      cacheStatsEmpty(this.cacheStore.lyricsStats) &&
      cacheStatsEmpty(this.cacheStore.audioStats);
  }

  private retryLabel(): ResourceStr {
    return this.cacheStore.isBusy() ?
      $r('app.string.settings_cache_retrying') :
      $r('app.string.settings_cache_retry');
  }

  /**
   * 全部清理：按分类串行调用，某一类失败就停在这里（错误条按 `errorAction` 重试）。
   * 已经空的分类直接跳过，不再制造一次无意义的「清理中」。
   */
  private async clearAll(): Promise<void> {
    if (!this.canClearAll()) {
      return;
    }
    if (!cacheStatsEmpty(this.cacheStore.imageStats)) {
      const imageCleared = await this.cacheStore.clearImage();
      if (!imageCleared) {
        return;
      }
    }
    if (!cacheStatsEmpty(this.cacheStore.lyricsStats)) {
      const lyricsCleared = await this.cacheStore.clearLyrics();
      if (!lyricsCleared) {
        return;
      }
    }
    if (!cacheStatsEmpty(this.cacheStore.audioStats)) {
      await this.cacheStore.clearAudio();
    }
  }
}

/**
 * 分类缓存行：标题 +「N 项」副行，行尾容量；无卡片底色、无行内清理按钮。
 *
 * 独立成 @Component + `@Prop` 数值，不写成带值参数的 @Builder：@Builder 传入两个
 * 以上按值参数后不会再刷新内部 UI，清理完统计变化就不会重绘。标签与 id 是静态的，
 * 用普通成员只设一次。
 */
@Component
struct CacheStatRow {
  rowId: string = '';
  label: ResourceStr = '';
  @Prop bytes: number = 0;
  @Prop entries: number = 0;

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.label)
          .width('100%')
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: ThemeSpacing.xs }) {
          Text(this.entries.toString())
            .fontSize(ThemeTypography.meta)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
          Text($r('app.string.settings_cache_entries_suffix'))
            .fontSize(ThemeTypography.meta)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(formatCacheBytes(this.bytes))
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(1)
    }
    .id(this.rowId)
    .width('100%')
    .height(CACHE_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }
}