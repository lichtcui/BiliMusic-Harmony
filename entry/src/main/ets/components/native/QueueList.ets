import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { MobileTrack } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { CoverImage, CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { NativeUiIds } from './NativeUiIds';
import { QueuePageState } from './QueuePageState';
import { formatTrackDuration } from './TrackRow';
import {
  TRACK_LIST_PAGE_SIZE,
  nextTrackPage,
  queueRowKeys,
  visibleCountForIndex,
  visibleTrackCount
} from './TrackListPaging';

const QUEUE_ROW_HEIGHT: number = 76;
const QUEUE_INDEX_WIDTH: number = 30;
const QUEUE_DURATION_WIDTH: number = 42;
const QUEUE_ACTION_WIDTH: number = 48;
const QUEUE_ACTION_HEIGHT: number = 36;
const QUEUE_MORE_SIZE: number = 28;

/**
 * 功能页的紧凑行：封面 40、行高 64、当前曲目在曲名前挂一枚音乐符（与歌单详情列表同款），
 * 行尾只有移除图标。
 */
const QUEUE_COMPACT_ROW_HEIGHT: number = 64;
const QUEUE_COMPACT_COVER: number = 40;
const QUEUE_COMPACT_REMOVE_SIZE: number = 28;
/** 与 `MusicTrackList` 的 `TRACK_PLAYING_ICON` 取同一尺寸，两处「正在播放」标记外观一致。 */
const QUEUE_COMPACT_PLAYING_ICON: number = 16;
const QUEUE_COMPACT_TITLE_GAP: number = 6;

/**
 * 队列列表共用组件（T15 抽出）：播放控制面板与 `QueuePage` 共用同一份行渲染，
 * 避免两份列表各自维护、行为漂移。
 *
 * 两种排版：
 * - 默认（整页 `QueuePage`）：序号 + 标题/作者 + 时长 + 「移除」文字按钮；
 * - `compact`（功能页）：封面 + 标题/作者 + 移除图标；当前曲目的音乐符挂在曲名左侧，
 *   与歌单详情列表的「正在播放」标记同一套做法（`MusicTrackRow`）。
 * 数据、忙碌态与移除动作全部走同一个 `QueuePageState`，只有排版分叉。
 *
 * 行 id 由 `NativeUiIds.queueRow/queueRemove` 按序号派生，属于动态 id，
 * 不得进入 `NativeUiIds.all()`（见 `MediaUiSmokeContract` 契约）。
 * 列表根 id 复用 `NativeUiIds.queueList`，两个消费者不会同时出现在屏幕上。
 */
@Component
export struct QueueList {
  @ObjectLink state: QueuePageState;
  @Prop compact: boolean = false;
  /** 首屏只建一页行；滚到末尾再追加，避免 500 首队列一次性建满组件树。 */
  @State private visibleCount: number = TRACK_LIST_PAGE_SIZE;
  /** 紧凑排版的封面加载器；整页排版不解码封面。 */
  imageCache: CoverImageProvider = EMPTY_COVER_PROVIDER;
  /** 整页队列行的更多操作；紧凑面板不展示。 */
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {
  };
  /** 整页队列切歌成功后回到播放页；紧凑面板本身就在播放页里，不触发。 */
  onOpenPlayer: () => void = (): void => {};
  /** 列表卸载后不再把迟到的切歌结果转成路由动作。 */
  private active: boolean = true;
  /** 队列每次打开都定位到当前播放行：`ForEach` 首屏必须覆盖该行，`initialIndex` 再打底。 */
  private readonly scroller: Scroller = new Scroller();
  private initialIndex: number = 0;
  private scrollGeneration: number = 0;
  /** 行 key 缓存：队列数组由 `QueuePageState` 每次发布时整体重建，引用不变即可复用。 */
  private keyCacheSource: MobileTrack[] | null = null;
  private keyCache: string[] = [];

  aboutToAppear(): void {
    this.active = true;
    const index = this.state.queueIndex;
    if (index >= 0 && index < this.state.queue.length) {
      this.initialIndex = index;
      this.visibleCount = visibleCountForIndex(index, this.state.queue.length);
      this.scrollToInitial();
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.scrollGeneration++;
  }

  @Builder
  CompactRow(track: MobileTrack, index: number) {
    Row({ space: ThemeSpacing.md }) {
      CoverImage({
        imageCache: this.imageCache,
        coverUrl: track.coverUrl,
        coverSize: QUEUE_COMPACT_COVER,
        cornerRadius: ThemeRadius.sm
      })

      Column({ space: 3 }) {
        Row({ space: QUEUE_COMPACT_TITLE_GAP }) {
          if (this.state.isCurrent(index)) {
            AppIcon({
              iconKind: AppIconKind.Quality,
              iconSize: QUEUE_COMPACT_PLAYING_ICON,
              iconColor: ThemeColors.nowPlayingMark
            })
          }
          Text(this.displayTitle(track))
            .layoutWeight(1)
            .fontSize(ThemeTypography.body)
            .fontWeight(this.state.isCurrent(index) ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.state.isCurrent(index) ? ThemeColors.nowPlaying : ThemeColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.displayArtist(track))
          .width('100%')
          .fontSize(ThemeTypography.playerPanelMeta)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        if (this.state.isCurrent(index)) {
          return;
        }
        void this.state.switchTo(index);
      })

      if (this.state.busyAction === 'switch' && this.state.busyIndex === index) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(ThemeColors.accent)
      }

      if (this.state.busyAction === 'remove' && this.state.busyIndex === index) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(ThemeColors.textSecondary)
      } else {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          AppIcon({
            iconKind: AppIconKind.Close,
            iconSize: 16,
            iconColor: ThemeColors.textSecondary
          })
        }
        .id(NativeUiIds.queueRemove(index))
        .width(QUEUE_COMPACT_REMOVE_SIZE)
        .height(QUEUE_COMPACT_REMOVE_SIZE)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .enabled(this.state.canRemoveAt(index))
        .opacity(this.state.canRemoveAt(index) ? 1 : 0.5)
        .onClick(() => {
          void this.state.removeAt(index);
        })
        .accessibilityText(this.removeLabel(index))
      }
    }
    .id(NativeUiIds.queueRow(index))
    .width('100%')
    .height(QUEUE_COMPACT_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  QueueRow(track: MobileTrack, index: number) {
    Row({ space: ThemeSpacing.sm }) {
      Text((index + 1).toString())
        .width(QUEUE_INDEX_WIDTH)
        .fontSize(ThemeTypography.caption)
        .fontColor(this.state.isCurrent(index) ? ThemeColors.nowPlaying : ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)

      Column({ space: 2 }) {
        Text(this.displayTitle(track))
          .width('100%')
          .fontSize(ThemeTypography.body)
          .fontWeight(this.state.isCurrent(index) ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.state.isCurrent(index) ? ThemeColors.nowPlaying : ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: ThemeSpacing.sm }) {
          if (this.state.isCurrent(index)) {
            Text($r('app.string.queue_current'))
              .fontSize(ThemeTypography.eyebrow)
              .fontColor(ThemeColors.nowPlaying)
              .maxLines(1)
          }
          Text(this.displayArtist(track))
            .layoutWeight(1)
            .fontSize(ThemeTypography.eyebrow)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        if (this.state.isCurrent(index)) {
          return;
        }
        void this.switchToAndMaybeOpen(index);
      })

      Text(formatTrackDuration(track.duration))
        .width(QUEUE_DURATION_WIDTH)
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.End)
        .maxLines(1)

      Button({ type: ButtonType.Circle, stateEffect: false }) {
        AppIcon({
          iconKind: AppIconKind.MoreVertical,
          iconSize: 18,
          iconColor: ThemeColors.textSecondary
        })
      }
      .id(NativeUiIds.queueMore(index))
      .width(QUEUE_MORE_SIZE)
      .height(QUEUE_MORE_SIZE)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .enabled(!this.state.isBusy())
      .opacity(this.state.isBusy() ? 0.5 : 1)
      .onClick(() => {
        this.onOpenTrackActions(track);
      })
      .accessibilityText($r('app.string.queue_more'))

      Button(this.removeLabel(index), { stateEffect: false })
        .id(NativeUiIds.queueRemove(index))
        .width(QUEUE_ACTION_WIDTH)
        .height(QUEUE_ACTION_HEIGHT)
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textPrimary)
        .backgroundColor(ThemeColors.surfaceInset)
        .borderRadius(ThemeRadius.md)
        .enabled(this.state.canRemoveAt(index))
        .opacity(this.state.canRemoveAt(index) ? 1 : 0.55)
        .onClick(() => {
          void this.state.removeAt(index);
        })

      if (this.state.busyAction === 'switch' && this.state.busyIndex === index) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(ThemeColors.accent)
      }
    }
    .id(NativeUiIds.queueRow(index))
    .width('100%')
    .height(QUEUE_ROW_HEIGHT)
    .padding({ left: ThemeSpacing.md, right: ThemeSpacing.md })
    .backgroundColor(ThemeColors.surface)
    .borderRadius(ThemeRadius.sm)
  }

  build() {
    List({
      space: this.compact ? 0 : ThemeSpacing.xs,
      initialIndex: this.initialIndex,
      scroller: this.scroller
    }) {
      ForEach(this.state.queue.slice(0,
        visibleTrackCount(this.visibleCount, this.state.queue.length)),
      (track: MobileTrack, index: number) => {
        ListItem() {
          if (this.compact) {
            this.CompactRow(track, index)
          } else {
            this.QueueRow(track, index)
          }
        }
      }, (track: MobileTrack, index: number): string => this.rowKeyAt(index))
    }
    .id(NativeUiIds.queueList)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .onReachEnd(() => {
      if (this.visibleCount < this.state.queue.length) {
        this.visibleCount = nextTrackPage(this.visibleCount, this.state.queue.length);
      }
    })
  }

  /**
   * 行 key：按队列引用缓存 `queueRowKeys` 的结果，`ForEach` 每行只做一次数组取值。
   * key 生成器在 build 里同步调用，只写普通私有字段，不触碰被观测状态。
   */
  private rowKeyAt(index: number): string {
    const queue = this.state.queue;
    if (this.keyCacheSource !== queue) {
      this.keyCacheSource = queue;
      this.keyCache = queueRowKeys(queue);
    }
    return index >= 0 && index < this.keyCache.length ? this.keyCache[index] : `${index}`;
  }

  /**
   * 首帧居中当前播放行；`initialIndex` 只能把目标行放在顶部，这里再补一次居中。
   * 与 `LyricsPanel#scrollToCurrent` 同一套写法：推迟一拍等布局完成，并丢弃卸载后的迟到回调。
   * 打开期间曲目自动切换不重新拉回，避免打断用户浏览队列。
   */
  private scrollToInitial(): void {
    const generation = this.scrollGeneration + 1;
    this.scrollGeneration = generation;
    const targetIndex = this.initialIndex;
    setTimeout((): void => {
      if (!this.active || generation !== this.scrollGeneration ||
        targetIndex !== this.initialIndex) {
        return;
      }
      this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.CENTER);
    }, 0);
  }

  private async switchToAndMaybeOpen(index: number): Promise<void> {
    if (await this.state.switchTo(index)) {
      if (this.active) {
        this.onOpenPlayer();
      }
    }
  }

  private displayTitle(track: MobileTrack): ResourceStr {
    return track.title.trim().length > 0 ? track.title : $r('app.string.player_unknown_track');
  }

  private displayArtist(track: MobileTrack): ResourceStr {
    return track.artist.trim().length > 0 ? track.artist : $r('app.string.player_unknown_artist');
  }

  private removeLabel(index: number): Resource {
    if (this.state.busyAction === 'remove' && this.state.busyIndex === index) {
      return $r('app.string.queue_removing');
    }
    return $r('app.string.queue_remove');
  }
}
