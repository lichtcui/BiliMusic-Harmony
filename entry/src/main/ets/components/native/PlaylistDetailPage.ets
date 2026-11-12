import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { FavoritesStore } from '../../state/FavoritesStore';
import { LibraryStoreModel } from '../../state/LibraryStoreModel';
import { PlaylistDetailStore } from '../../state/PlaylistDetailStore';
import { PlayerStore } from '../../state/PlayerStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { MobileTrack } from '../../types/MobileTypes';
import { AppIconKind } from './AppIcon';
import { CoverImage, CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { MusicSelectionBar, MusicTrackRow, MusicTrackToolbar } from './MusicTrackList';
import { MusicPageEmptyState, MusicPageErrorBanner, MusicPageHeader } from './MusicPageTemplate';
import { NativeUiIds } from './NativeUiIds';
import { TRACK_LIST_PAGE_SIZE, nextTrackPage, visibleTrackCount } from './TrackListPaging';
import { RuntimeCoverImageProvider } from './RuntimeCoverImageProvider';

/**
 * 「歌单」详情页（design/playlist-page.html 2026-11 更新版）。
 *
 * 版式：整页滚动（自定义顶栏 → Hero → 错误条 → 吸顶工具条 → 曲目列表），多选时底部
 * 固定操作栏；顶栏右侧打开「修改歌单信息」抽屉。
 *
 * - Hero：160 封面居中，名称 + 简介在下方整宽排列，底边线作为与列表的分割线；
 * - 工具条：左侧「全部播放（N）」；非多选时右侧只有多选入口，多选时同时显示
 *   「全选」（勾选框 + 文字，只切换勾选）和「关闭」（独立退出多选）；
 * - 曲目行 56 高：标题 13/18、副标题 12/16，行尾收藏 + 竖向更多，多选时隐藏行尾动作；
 *   选中态只靠行首勾选圆圈表示，不再给整行铺底色；
 * - 底部操作栏：删除 / 添加到。删除直接批量移除；添加到打开多曲抽屉，歌单与「加入我喜欢的」
 *   都在抽屉里完成。下载入口只在曲目操作抽屉里，底栏不单独出现。
 *
 * **后续所有音乐列表（历史、收藏、搜索、队列等）优先复用这套歌曲列表设计**：56 高透明行、
 * 标题 13/18 单行省略、副标题 12/16、行尾收藏 + 竖向更多、吸顶工具条播放全部 + 多选。
 */
const PAGE_PADDING_VERTICAL: number = 4;
const HEADER_HEIGHT: number = 56;
const HEADER_ACTION_SIZE: number = 40;
const HEADER_BACK_ICON: number = 22;
const HEADER_EDIT_ICON: number = 20;
const HERO_ART_SIZE: number = 160;
const HERO_ART_RADIUS: number = 16;
const HERO_ART_COUNT_FONT: number = 48;
const HERO_GAP: number = 16;
const HERO_TOP_PADDING: number = 12;
const HERO_BOTTOM_PADDING: number = 16;
const HERO_TEXT_GAP: number = 4;
const HERO_NAME_LINE_HEIGHT: number = 28;
const HERO_DESC_LINE_HEIGHT: number = 18;
const HERO_DESC_MAX_LINES: number = 2;
const LIST_BOTTOM_PADDING: number = 20;
const ERROR_BANNER_MIN_HEIGHT: number = 44;
const ERROR_DISMISS_HEIGHT: number = 32;
const MISSING_ACTION_WIDTH: number = 136;
const MISSING_ACTION_HEIGHT: number = 40;
const EMPTY_STATE_ICON: number = 28;

@Component
export struct PlaylistDetailPage {
  libraryModel: LibraryStoreModel | null = null;
  playerStore: PlayerStore | null = null;
  /**
   * 收藏状态由宿主持有：与「我喜欢的」「历史」共用同一份 store，行尾爱心不需要本页再维护副本。
   * 用 @ObjectLink 接收（而不是普通成员）才能把同一份 @Observed 对象继续交给内容组件的 @ObjectLink。
   */
  @ObjectLink favoritesStore: FavoritesStore;
  runtime: NativeAppRuntime | null = null;
  playlistId: string = '';
  onClose: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string) => void =
    (_tracks: MobileTrack[], _contextTitle: string): void => {};
  /** 点击曲目开始播放后进入播放页；由宿主决定路由，页面本身不持有导航栈。 */
  onOpenPlayer: () => void = (): void => {};
  /** 顶栏右上角「修改歌单信息」：抽屉由根 Stack 承载，不在 NavDestination 里打开。 */
  onEditPlaylist: () => void = (): void => {};

  @State private store: PlaylistDetailStore | null = null;
  private coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;

  aboutToAppear(): void {
    if (this.runtime !== null) {
      this.coverProvider = new RuntimeCoverImageProvider(this.runtime);
    }
    if (this.libraryModel !== null && this.playerStore !== null) {
      this.store = new PlaylistDetailStore(this.libraryModel, this.playerStore, this.playlistId);
      this.store?.attach();
    }
  }

  aboutToDisappear(): void {
    this.store?.dispose();
    this.store = null;
  }

  build() {
    if (this.store !== null) {
      PlaylistDetailContent({
        store: this.store,
        favoritesStore: this.favoritesStore,
        coverProvider: this.coverProvider,
        onClose: this.onClose,
        onOpenTrackActions: this.onOpenTrackActions,
        onOpenTracksActions: this.onOpenTracksActions,
        onOpenPlayer: this.onOpenPlayer,
        onEditPlaylist: this.onEditPlaylist
      })
    } else {
      PlaylistUnavailablePage({
        onClose: this.onClose
      })
    }
  }
}

@Component
struct PlaylistDetailContent {
  @ObjectLink store: PlaylistDetailStore;
  @ObjectLink favoritesStore: FavoritesStore;
  coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;
  onClose: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string) => void =
    (_tracks: MobileTrack[], _contextTitle: string): void => {};
  onOpenPlayer: () => void = (): void => {};
  onEditPlaylist: () => void = (): void => {};

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
      headerId: NativeUiIds.playlistDetailHeader,
      backId: NativeUiIds.playlistDetailHeaderBack,
      backLabel: $r('app.string.playlist_detail_back'),
      showTitle: false,
      // 右上角直接是「修改歌单信息」，用编辑图标表达语义，多选入口已经迁到列表顶栏。
      actionId: NativeUiIds.playlistDetailEdit,
      actionLabel: $r('app.string.playlist_detail_edit'),
      actionIcon: AppIconKind.Edit,
      actionEnabled: !this.store.missing,
      onBack: (): void => {
        this.onClose();
      },
      onAction: (): void => {
        this.onEditPlaylist();
      }
    })
  }

  @Builder
  HeroArt() {
    Stack() {
      if (this.store.coverUrl.length > 0) {
        CoverImage({
          imageCache: this.coverProvider,
          coverUrl: this.store.coverUrl,
          coverSize: HERO_ART_SIZE,
          cornerRadius: HERO_ART_RADIUS
        })
      } else {
        Text(this.store.tracks.length.toString())
          .fontSize(HERO_ART_COUNT_FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.accent)
          .maxLines(1)
      }
    }
    .id(NativeUiIds.playlistDetailCover)
    .width(HERO_ART_SIZE)
    .height(HERO_ART_SIZE)
    .borderRadius(HERO_ART_RADIUS)
    .backgroundColor(ThemeColors.accentSoft)
    .clip(true)
    .alignContent(Alignment.Center)
  }

  @Builder
  Hero() {
    Column({ space: HERO_GAP }) {
      this.HeroArt()

      Column({ space: HERO_TEXT_GAP }) {
        Text(this.displayPlaylistName())
          .id(NativeUiIds.playlistDetailName)
          .width('100%')
          .fontSize(22)
          .lineHeight(HERO_NAME_LINE_HEIGHT)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.store.description.length > 0) {
          Text(this.store.description)
            .id(NativeUiIds.playlistDetailDescription)
            .width('100%')
            .fontSize(12.5)
            .lineHeight(HERO_DESC_LINE_HEIGHT)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(HERO_DESC_MAX_LINES)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .id(NativeUiIds.playlistDetailHero)
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
      bannerId: NativeUiIds.playlistDetailError,
      dismissId: NativeUiIds.playlistDetailErrorDismiss,
      message: $r('app.string.playlist_detail_error'),
      dismissLabel: $r('app.string.playlist_detail_error_dismiss'),
      onDismiss: (): void => {
        this.dismissError();
      }
    })
  }

  @Builder
  Toolbar() {
    MusicTrackToolbar({
      toolbarId: NativeUiIds.playlistDetailToolbar,
      playAllId: NativeUiIds.playlistDetailToolbarPlayAll,
      selectToggleId: NativeUiIds.playlistDetailSelectToggle,
      selectAllId: NativeUiIds.playlistDetailSelectAll,
      exitSelectId: NativeUiIds.playlistDetailExitSelect,
      trackCount: this.store.tracks.length,
      busy: this.store.isBusy(),
      selectionMode: this.selectionMode,
      allSelected: this.store.isAllSelected(),
      playAllLabel: $r('app.string.playlist_detail_play_all'),
      selectLabel: $r('app.string.playlist_detail_select'),
      exitSelectLabel: $r('app.string.playlist_detail_exit_select'),
      selectAllLabel: $r('app.string.playlist_detail_select_all'),
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
      barId: NativeUiIds.playlistDetailBottomBar,
      deleteId: NativeUiIds.playlistDetailDeleteSelected,
      addId: NativeUiIds.playlistDetailAddSelected,
      deleteLabel: $r('app.string.playlist_detail_delete'),
      addLabel: $r('app.string.playlist_detail_add_to'),
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
      emptyId: NativeUiIds.playlistDetailEmpty,
      iconKind: AppIconKind.Note,
      title: $r('app.string.playlist_detail_empty_title'),
      description: $r('app.string.playlist_detail_empty_description')
    })
  }

  @Builder
  MissingState() {
    Column({ space: ThemeSpacing.md }) {
      Text($r('app.string.playlist_detail_missing_title'))
        .fontSize(ThemeTypography.emptyTitle)
        .lineHeight(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.playlist_detail_missing_description'))
        .constraintSize({ maxWidth: 280 })
        .fontSize(ThemeTypography.body)
        .lineHeight(22)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button($r('app.string.playlist_detail_back'), { stateEffect: false })
        .id(NativeUiIds.playlistDetailBack)
        .width(MISSING_ACTION_WIDTH)
        .height(MISSING_ACTION_HEIGHT)
        .margin({ top: ThemeSpacing.xs })
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.onAccent)
        .backgroundColor(ThemeColors.accent)
        .borderRadius(ThemeRadius.md)
        .onClick(() => {
          this.onClose();
        })
    }
    .id(NativeUiIds.playlistDetailMissing)
    .width('100%')
    .layoutWeight(1)
    .padding({ left: ThemeSpacing.xxl, right: ThemeSpacing.xxl, top: 32, bottom: 56 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  TrackList() {
    List({ scroller: this.scroller, space: 0 }) {
      ListItem() {
        this.Header()
      }

      ListItem() {
        this.Hero()
      }

      if (this.store.error !== null || this.favoritesStore.error !== null) {
        ListItem() {
          this.ErrorBanner()
        }
      }

      ListItemGroup({ header: this.Toolbar }) {
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
              favorite: this.favoritesStore.isFavorite(track.key),
              favoritePending: this.favoritesStore.isPending(track.key),
              rowId: NativeUiIds.playlistDetailRow(index),
              favoriteId: NativeUiIds.playlistDetailFavorite(index),
              moreId: NativeUiIds.playlistDetailMoreAction(index),
              onRowTap: (): void => {
                this.handleTrackTap(track);
              },
              onFavoriteTap: (): void => {
                void this.favoritesStore.toggle(track);
              },
              onMoreTap: (): void => {
                this.onOpenTrackActions(track);
              }
            })
          }
        }, (track: MobileTrack): string => track.key)
      }

      ListItem() {
        Row()
          .width('100%')
          .height(LIST_BOTTOM_PADDING)
      }
    }
    .id(NativeUiIds.playlistDetailList)
    .width('100%')
    .layoutWeight(1)
    .sticky(StickyStyle.Header)
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
      if (this.store.missing) {
        this.Header()
        this.MissingState()
      } else if (this.store.tracks.length === 0) {
        this.Header()
        this.EmptyState()
      } else {
        this.TrackList()
        if (this.selectionMode) {
          this.BottomBar()
        }
      }
    }
    .id(NativeUiIds.playlistDetail)
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
    if (this.store.isBusy()) {
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

  private displayPlaylistName(): ResourceStr {
    return this.store.playlistName.trim().length > 0 ?
      this.store.playlistName : $r('app.string.playlist_detail_default_name');
  }

  private enterSelectionMode(): void {
    if (this.store.isBusy()) {
      return;
    }
    this.selectionMode = true;
  }

  private exitSelectionMode(): void {
    this.selectionMode = false;
    this.store.clearSelection();
  }

  /** 全选按钮只切换勾选：未全选 → 全选；已全选 → 清空。关闭按钮独立退出多选。 */
  private toggleSelectAll(): void {
    if (this.store.isBusy()) {
      return;
    }
    if (this.store.isAllSelected()) {
      this.store.clearSelection();
    } else {
      this.store.selectAll();
    }
  }

  private canActOnSelection(): boolean {
    return !this.batchBusy() && this.store.selectedKeys.length > 0;
  }

  private batchBusy(): boolean {
    return this.store.batchBusy;
  }

  private dismissError(): void {
    this.store.clearError();
    if (this.favoritesStore.error !== null) {
      this.favoritesStore.clearError();
    }
  }

  private addSelected(): void {
    if (!this.selectionMode || this.batchBusy() || this.store.selectedKeys.length === 0) {
      return;
    }
    const tracks = this.store.selectedTracks();
    if (tracks.length === 0) {
      return;
    }
    this.onOpenTracksActions(tracks, '');
  }

  private async removeSelected(): Promise<void> {
    if (!this.selectionMode || this.batchBusy() || this.store.selectedKeys.length === 0) {
      return;
    }
    if (await this.store.removeSelected()) {
      if (!this.destroyed) {
        this.exitSelectionMode();
      }
    }
  }
}

/**
 * 资料库 / 播放器还没就绪时的兜底页：不持有歌单数据，只保留「返回」出口。
 * 正常路由下 `PlaylistDetailPage` 一定拿得到三个 store，这个分支只防宿主装配错误。
 */
@Component
struct PlaylistUnavailablePage {
  onClose: () => void = (): void => {};

  build() {
    Column({ space: ThemeSpacing.md }) {
      Text($r('app.string.playlist_detail_missing_title'))
        .fontSize(ThemeTypography.emptyTitle)
        .lineHeight(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.playlist_detail_missing_description'))
        .constraintSize({ maxWidth: 280 })
        .fontSize(ThemeTypography.body)
        .lineHeight(22)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button($r('app.string.playlist_detail_back'), { stateEffect: false })
        .id(NativeUiIds.playlistDetailBack)
        .width(MISSING_ACTION_WIDTH)
        .height(MISSING_ACTION_HEIGHT)
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.onAccent)
        .backgroundColor(ThemeColors.accent)
        .borderRadius(ThemeRadius.md)
        .onClick(() => {
          this.onClose();
        })
    }
    .id(NativeUiIds.playlistDetailMissing)
    .width('100%')
    .height('100%')
    .padding({ left: ThemeSpacing.xxl, right: ThemeSpacing.xxl })
    .justifyContent(FlexAlign.Center)
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }
}