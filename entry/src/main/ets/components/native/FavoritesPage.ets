import { FavoritesStore } from '../../state/FavoritesStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { MobileTrack } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { MusicSelectionBar, MusicTrackRow, MusicTrackToolbar } from './MusicTrackList';
import { MusicPageEmptyState, MusicPageErrorBanner, MusicPageHeader } from './MusicPageTemplate';
import { NativeUiIds } from './NativeUiIds';
import { TRACK_LIST_PAGE_SIZE, nextTrackPage, visibleTrackCount } from './TrackListPaging';

/**
 * 「我喜欢的」页（design/favorites-page.html 2026-11 更新版）。
 *
 * 版式：自定义页头（返回 + 标题）→ Hero（160 黄色爱心封面 + 名称 / 简介）→ 错误条 →
 * 曲目列表工具条 → 56 高曲目列表，多选时底部固定操作栏。
 *
 * - 页头只保留返回与标题，不再显示「46 首 · 总有一首，懂此刻」这类描述；
 * - Hero 与「歌单」详情页同构：160 封面居中、名称 22/700、简介 12.5/18 两行，
 *   下边框作为与列表的分割线；封面底色固定用「我喜欢的」的 accent-action 黄色 + 爱心，
 *   不展示真实曲目封面；
 * - 曲目列表直接复用「歌单」详情页的基准（见 docs/architecture.md「音乐列表基准」）：
 *   工具条左侧「全部播放（N）」，非多选时右侧是多选入口，多选时同时显示「全选」（只切换
 *   勾选）与「关闭」（独立退出多选）；56 高透明行、标题 13/18、副题 12/16、行尾收藏 +
 *   竖向更多；当前曲目无底色，标题 accent 且在标题前显示播放指示；
 * - 选中态只用行首勾选圈表示，不给整行铺底色；
 * - 底部操作栏：删除 / 添加到。删除走 `FavoritesStore.removeSelected` 一次原子写入；添加到
 *   打开根 Stack 上的多曲抽屉，可批量加入歌单或加入我喜欢的。下载入口只在曲目操作抽屉里。
 * - 空态不显示 Hero / 工具条，只保留页头 + 空态（与设计稿一致）。
 */
const PAGE_PADDING_VERTICAL: number = 4;
const HERO_ART_SIZE: number = 160;
const HERO_ART_RADIUS: number = 16;
const HERO_ICON_SIZE: number = 68;
const HERO_GAP: number = 16;
const HERO_TOP_PADDING: number = 12;
const HERO_BOTTOM_PADDING: number = 16;
const HERO_TEXT_GAP: number = 4;
const HERO_NAME_LINE_HEIGHT: number = 28;
const HERO_DESC_LINE_HEIGHT: number = 18;
const HERO_DESC_MAX_LINES: number = 2;
const LIST_BOTTOM_PADDING: number = 20;

@Component
export struct FavoritesPage {
  @ObjectLink store: FavoritesStore;
  onClose: () => void = (): void => {};
  onBrowseSearch: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string) => void =
    (_tracks: MobileTrack[], _contextTitle: string): void => {};
  /** 点击曲目开始播放后进入播放页；由宿主决定路由，页面本身不持有导航栈。 */
  onOpenPlayer: () => void = (): void => {};

  @State private selectionMode: boolean = false;
  /** 首屏只建一页行；滚到末尾再追加，避免 500 首一次性建满组件树。 */
  @State private visibleCount: number = TRACK_LIST_PAGE_SIZE;
  private scroller: Scroller = new Scroller();
  /** 只用于拦住卸载后才回来的批量结果；普通字段，不在 aboutToDisappear 里写 @State。 */
  private destroyed: boolean = false;

  aboutToDisappear(): void {
    this.destroyed = true;
  }

  @Builder
  Header() {
    MusicPageHeader({
      headerId: NativeUiIds.favoritesHeader,
      backId: NativeUiIds.favoritesHeaderBack,
      backLabel: $r('app.string.favorite_back'),
      title: $r('app.string.favorite_title'),
      titleIndent: 2,
      onBack: (): void => {
        this.onClose();
      }
    })
  }

  @Builder
  HeroArt() {
    Stack() {
      AppIcon({
        iconKind: AppIconKind.Heart,
        iconSize: HERO_ICON_SIZE,
        iconColor: ThemeColors.onAccentAction
      })
    }
    .id(NativeUiIds.favoritesCover)
    .width(HERO_ART_SIZE)
    .height(HERO_ART_SIZE)
    .borderRadius(HERO_ART_RADIUS)
    .backgroundColor(ThemeColors.accentAction)
    .alignContent(Alignment.Center)
  }

  @Builder
  Hero() {
    Column({ space: HERO_GAP }) {
      this.HeroArt()

      Column({ space: HERO_TEXT_GAP }) {
        Text($r('app.string.favorite_title'))
          .width('100%')
          .fontSize(22)
          .lineHeight(HERO_NAME_LINE_HEIGHT)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text($r('app.string.favorite_hero_description'))
          .width('100%')
          .fontSize(12.5)
          .lineHeight(HERO_DESC_LINE_HEIGHT)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(HERO_DESC_MAX_LINES)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .id(NativeUiIds.favoritesHero)
    .width('100%')
    .padding({
      left: ThemeSpacing.gutter,
      right: ThemeSpacing.gutter,
      top: HERO_TOP_PADDING,
      bottom: HERO_BOTTOM_PADDING
    })
    .alignItems(HorizontalAlign.Center)
    .border({ width: { bottom: 1 }, color: ThemeColors.line })
  }

  @Builder
  ErrorBanner() {
    MusicPageErrorBanner({
      bannerId: NativeUiIds.favoritesError,
      dismissId: NativeUiIds.favoritesErrorDismiss,
      message: $r('app.string.favorite_error'),
      dismissLabel: $r('app.string.favorite_error_dismiss'),
      onDismiss: (): void => {
        this.store.clearError();
      }
    })
  }

  @Builder
  Toolbar() {
    MusicTrackToolbar({
      toolbarId: NativeUiIds.favoritesToolbar,
      playAllId: NativeUiIds.favoritesPlayAll,
      selectToggleId: NativeUiIds.favoritesSelectToggle,
      selectAllId: NativeUiIds.favoritesSelectAll,
      exitSelectId: NativeUiIds.favoritesExitSelect,
      trackCount: this.store.tracks.length,
      busy: this.store.batchBusy,
      selectionMode: this.selectionMode,
      allSelected: this.store.isAllSelected(),
      playAllLabel: $r('app.string.favorite_play_all'),
      selectLabel: $r('app.string.favorite_select'),
      exitSelectLabel: $r('app.string.favorite_exit_select'),
      selectAllLabel: $r('app.string.favorite_select_all'),
      onPlayAll: (): void => {
        void this.store.playAll();
        this.scroller.scrollEdge(Edge.Top);
      },
      onSelectToggle: (): void => {
        this.enterSelectionMode();
      },
      onExitSelect: (): void => {
        this.exitSelectionMode();
      },
      onSelectAll: (): void => {
        this.toggleSelectAll();
      }
    })
  }

  @Builder
  BottomBar() {
    MusicSelectionBar({
      barId: NativeUiIds.favoritesBottomBar,
      deleteId: NativeUiIds.favoritesDeleteSelected,
      addId: NativeUiIds.favoritesAddSelected,
      deleteLabel: $r('app.string.favorite_delete'),
      addLabel: $r('app.string.favorite_add_to'),
      deleteEnabled: this.canActOnSelection(),
      addEnabled: this.canActOnSelection(),
      showDelete: true,
      onDelete: (): void => {
        void this.removeSelected();
      },
      onAdd: (): void => {
        this.addSelected();
      }
    })
  }

  @Builder
  EmptyState() {
    MusicPageEmptyState({
      emptyId: NativeUiIds.favoritesEmpty,
      iconKind: AppIconKind.Heart,
      title: $r('app.string.favorite_empty_title'),
      description: $r('app.string.favorite_empty_description'),
      paddingTop: 0,
      showAction: true,
      actionId: NativeUiIds.favoritesEmptySearch,
      actionLabel: $r('app.string.favorite_empty_action'),
      onAction: (): void => {
        this.onBrowseSearch();
      }
    })
  }

  @Builder
  TrackList() {
    List({ scroller: this.scroller, space: 0 }) {
      ForEach(this.store.tracks.slice(0,
        visibleTrackCount(this.visibleCount, this.store.tracks.length)),
      (track: MobileTrack, index: number) => {
        ListItem() {
          MusicTrackRow({
            track: track,
            index: index,
            selectionMode: this.selectionMode,
            selected: this.store.isSelected(track.key),
            current: track.key.length > 0 && track.key === this.store.currentKey,
            favorite: true,
            favoritePinned: true,
            favoritePending: this.store.isPending(track.key),
            rowId: NativeUiIds.favoriteRow(index),
            favoriteId: NativeUiIds.favoriteRemove(index),
            moreId: NativeUiIds.favoriteMore(index),
            onRowTap: (): void => {
              this.handleTrackTap(track);
            },
            onFavoriteTap: (): void => {
              void this.store.toggle(track);
            },
            onMoreTap: (): void => {
              this.onOpenTrackActions(track);
            }
          })
        }
      }, (track: MobileTrack): string => track.key)
    }
    .id(NativeUiIds.favoritesList)
    .width('100%')
    .layoutWeight(1)
    .padding({ bottom: LIST_BOTTOM_PADDING })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onReachEnd(() => {
      if (this.visibleCount < this.store.tracks.length) {
        this.visibleCount = nextTrackPage(this.visibleCount, this.store.tracks.length);
      }
    })
  }

  build() {
    Column() {
      this.Header()

      if (this.store.tracks.length === 0) {
        this.EmptyState()
      } else {
        this.Hero()

        if (this.store.error !== null) {
          this.ErrorBanner()
        }

        this.Toolbar()
        this.TrackList()

        if (this.selectionMode) {
          this.BottomBar()
        }
      }
    }
    .id(NativeUiIds.favoritesPage)
    .width('100%')
    .height('100%')
    .padding({ top: PAGE_PADDING_VERTICAL, bottom: PAGE_PADDING_VERTICAL })
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }

  private handleTrackTap(track: MobileTrack): void {
    if (this.selectionMode) {
      this.store.toggleSelection(track.key);
      return;
    }
    void this.playAndOpenPlayer(track.key);
  }

  private async playAndOpenPlayer(trackKey: string): Promise<void> {
    if (await this.store.playTrack(trackKey)) {
      if (!this.destroyed) {
        this.onOpenPlayer();
      }
    }
  }

  private enterSelectionMode(): void {
    if (this.store.batchBusy) {
      return;
    }
    this.store.clearSelection();
    this.selectionMode = true;
  }

  private exitSelectionMode(): void {
    this.selectionMode = false;
    this.store.clearSelection();
  }

  /** 全选按钮只切换勾选：未全选 → 全选；已全选 → 清空。关闭按钮独立退出多选。 */
  private toggleSelectAll(): void {
    if (this.store.batchBusy) {
      return;
    }
    if (this.store.isAllSelected()) {
      this.store.clearSelection();
    } else {
      this.store.selectAll();
    }
  }

  private canActOnSelection(): boolean {
    return !this.store.batchBusy && this.store.selectedKeys.length > 0;
  }

  private addSelected(): void {
    if (!this.selectionMode || !this.canActOnSelection()) {
      return;
    }
    const tracks = this.store.selectedTracks();
    if (tracks.length === 0) {
      return;
    }
    this.onOpenTracksActions(tracks, '');
  }

  private async removeSelected(): Promise<void> {
    if (!this.selectionMode || !this.canActOnSelection()) {
      return;
    }
    if (await this.store.removeSelected()) {
      if (!this.destroyed) {
        this.exitSelectionMode();
      }
    }
  }
}
