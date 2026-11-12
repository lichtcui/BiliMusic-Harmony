import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { CollectionDetailStore, CollectionDetailGateway } from '../../state/CollectionDetailStore';
import { FavoritesStore } from '../../state/FavoritesStore';
import { PlayerStore } from '../../state/PlayerStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { CatalogCollection, MobileTrack } from '../../types/MobileTypes';
import { AppIconKind } from './AppIcon';
import { CoverImage, CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { ListStateKind, ListStateView } from './ListStateView';
import { MusicSelectionBar, MusicTrackRow, MusicTrackToolbar } from './MusicTrackList';
import { MusicPageEmptyState, MusicPageErrorBanner, MusicPageHeader } from './MusicPageTemplate';
import { NativeUiIds } from './NativeUiIds';
import { TRACK_LIST_PAGE_SIZE, nextTrackPage, visibleTrackCount } from './TrackListPaging';
import { RuntimeCoverImageProvider } from './RuntimeCoverImageProvider';

/**
 * 搜索结果里的多 P 合集详情（2026-11）。
 *
 * 版式与「歌单」详情页共用音乐列表模板：自定义顶栏 → Hero（封面 / 标题 / 合集信息）→
 * 吸顶工具条（全部播放 + 多选）→ 56 高曲目列表，多选时底部固定「添加到」。
 * 合集来自 B 站目录，是只读的远端内容，因此没有删除与编辑入口。
 *
 * 点击曲目 / 全部播放都直接进入播放页；多选批量加入歌单或「我喜欢的」走根 Stack 的
 * 多曲抽屉，不在本页自己维护歌单数据。
 */
const PAGE_PADDING_VERTICAL: number = 4;
const HEADER_HEIGHT: number = 56;
const HEADER_ACTION_SIZE: number = 40;
const HEADER_BACK_ICON: number = 22;
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
const STATE_ACTION_MIN_WIDTH: number = 136;

/** ArkTS 不支持结构类型，NativeAppRuntime 通过这个窄适配器注入详情 store。 */
class RuntimeCollectionGateway implements CollectionDetailGateway {
  private readonly runtime: NativeAppRuntime;

  constructor(runtime: NativeAppRuntime) {
    this.runtime = runtime;
  }

  catalogCollection(bvid: string): Promise<CatalogCollection | null> {
    return this.runtime.catalogCollection(bvid);
  }
}

@Component
export struct CollectionDetailPage {
  runtime: NativeAppRuntime | null = null;
  playerStore: PlayerStore | null = null;
  @ObjectLink favoritesStore: FavoritesStore;
  bvid: string = '';
  onClose: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string) => void =
    (_tracks: MobileTrack[], _contextTitle: string): void => {};
  onOpenPlayer: () => void = (): void => {};

  @State private store: CollectionDetailStore | null = null;
  private coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;

  aboutToAppear(): void {
    if (this.runtime !== null) {
      this.coverProvider = new RuntimeCoverImageProvider(this.runtime);
    }
    if (this.runtime !== null && this.playerStore !== null) {
      this.store = new CollectionDetailStore(new RuntimeCollectionGateway(this.runtime), this.playerStore, this.bvid);
      this.store.attach();
      void this.store.load();
    }
  }

  aboutToDisappear(): void {
    this.store?.dispose();
    this.store = null;
  }

  build() {
    if (this.store !== null) {
      CollectionDetailContent({
        store: this.store,
        favoritesStore: this.favoritesStore,
        coverProvider: this.coverProvider,
        onClose: this.onClose,
        onOpenTrackActions: this.onOpenTrackActions,
        onOpenTracksActions: this.onOpenTracksActions,
        onOpenPlayer: this.onOpenPlayer
      })
    } else {
      CollectionUnavailablePage({
        onClose: this.onClose
      })
    }
  }
}

@Component
struct CollectionDetailContent {
  @ObjectLink store: CollectionDetailStore;
  @ObjectLink favoritesStore: FavoritesStore;
  coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;
  onClose: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string) => void =
    (_tracks: MobileTrack[], _contextTitle: string): void => {};
  onOpenPlayer: () => void = (): void => {};

  @State private selectionMode: boolean = false;
  /** 首屏只建一页行；滚到末尾再追加，避免 500 首一次性建满组件树。 */
  @State private visibleCount: number = TRACK_LIST_PAGE_SIZE;
  private scroller: Scroller = new Scroller();
  private destroyed: boolean = false;

  aboutToDisappear(): void {
    this.destroyed = true;
  }

  @Builder
  Header() {
    MusicPageHeader({
      headerId: NativeUiIds.collectionDetailHeader,
      backId: NativeUiIds.collectionDetailHeaderBack,
      backLabel: $r('app.string.collection_detail_back'),
      showTitle: false,
      onBack: (): void => {
        this.onClose();
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
    .id(NativeUiIds.collectionDetailCover)
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
        Text(this.displayTitle())
          .id(NativeUiIds.collectionDetailName)
          .width('100%')
          .fontSize(22)
          .lineHeight(HERO_NAME_LINE_HEIGHT)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.metaLine())
          .id(NativeUiIds.collectionDetailMeta)
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
    .id(NativeUiIds.collectionDetailHero)
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
  FavoriteErrorBanner() {
    MusicPageErrorBanner({
      bannerId: NativeUiIds.collectionDetailFavoriteError,
      dismissId: NativeUiIds.collectionDetailErrorDismiss,
      message: $r('app.string.collection_detail_favorite_error'),
      dismissLabel: $r('app.string.playlist_detail_error_dismiss'),
      onDismiss: (): void => {
        this.favoritesStore.clearError();
      }
    })
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

      if (this.favoritesStore.error !== null) {
        ListItem() {
          this.FavoriteErrorBanner()
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
              rowId: NativeUiIds.collectionDetailRow(index),
              favoriteId: NativeUiIds.collectionDetailFavorite(index),
              moreId: NativeUiIds.collectionDetailMoreAction(index),
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
    .id(NativeUiIds.collectionDetailList)
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

  @Builder
  Toolbar() {
    MusicTrackToolbar({
      toolbarId: NativeUiIds.collectionDetailToolbar,
      playAllId: NativeUiIds.collectionDetailPlayAll,
      selectToggleId: NativeUiIds.collectionDetailSelectToggle,
      selectAllId: NativeUiIds.collectionDetailSelectAll,
      exitSelectId: NativeUiIds.collectionDetailExitSelect,
      trackCount: this.store.tracks.length,
      busy: this.store.status === 'loading',
      selectionMode: this.selectionMode,
      allSelected: this.store.isAllSelected(),
      playAllLabel: $r('app.string.collection_detail_play_all'),
      selectLabel: $r('app.string.collection_detail_select'),
      exitSelectLabel: $r('app.string.collection_detail_exit_select'),
      selectAllLabel: $r('app.string.collection_detail_select_all'),
      onPlayAll: (): void => {
        void this.playAllAndOpenPlayer();
      },
      onSelectToggle: (): void => {
        this.selectionMode = true;
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
      barId: NativeUiIds.collectionDetailBottomBar,
      addId: NativeUiIds.collectionDetailAddSelected,
      addLabel: $r('app.string.collection_detail_add_to'),
      addEnabled: this.store.selectedKeys.length > 0,
      showDelete: false,
      onAdd: (): void => {
        this.addSelected();
      }
    })
  }

  @Builder
  LoadingState() {
    ListStateView({
      viewId: NativeUiIds.collectionDetailLoading,
      state: ListStateKind.Loading,
      title: $r('app.string.collection_detail_loading_title'),
      message: $r('app.string.collection_detail_loading_message')
    })
  }

  @Builder
  LoadErrorState() {
    ListStateView({
      viewId: NativeUiIds.collectionDetailError,
      state: ListStateKind.Error,
      title: $r('app.string.collection_detail_error_title'),
      message: $r('app.string.collection_detail_error_message'),
      actionLabel: $r('app.string.collection_detail_retry'),
      onAction: (): void => {
        void this.store.load();
      }
    })
  }

  @Builder
  EmptyState() {
    MusicPageEmptyState({
      emptyId: NativeUiIds.collectionDetailEmpty,
      iconKind: AppIconKind.Note,
      iconOpacity: 1,
      title: $r('app.string.collection_detail_empty_title'),
      description: $r('app.string.collection_detail_empty_message')
    })
  }

  build() {
    Column() {
      if (this.store.status === 'loading') {
        this.Header()
        this.LoadingState()
      } else if (this.store.status === 'error') {
        this.Header()
        this.LoadErrorState()
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
    .id(NativeUiIds.collectionDetail)
    .width('100%')
    .height('100%')
    .padding({ top: PAGE_PADDING_VERTICAL, bottom: PAGE_PADDING_VERTICAL })
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }

  private displayTitle(): ResourceStr {
    return this.store.title.trim().length > 0 ?
      this.store.title : $r('app.string.collection_detail_default_name');
  }

  private metaLine(): string {
    const parts: string[] = [];
    const artist = this.store.artist.trim();
    if (artist.length > 0) {
      parts.push(artist);
    }
    parts.push(`${this.store.tracks.length} P`);
    return parts.join(' · ');
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

  private async playAllAndOpenPlayer(): Promise<void> {
    if (await this.store.playAll()) {
      if (!this.destroyed) {
        this.onOpenPlayer();
      }
    }
  }

  private exitSelectionMode(): void {
    this.selectionMode = false;
    this.store.clearSelection();
  }

  /** 全选按钮只切换勾选：未全选 → 全选；已全选 → 清空。关闭按钮独立退出多选。 */
  private toggleSelectAll(): void {
    if (this.store.isAllSelected()) {
      this.store.clearSelection();
    } else {
      this.store.selectAll();
    }
  }

  private addSelected(): void {
    if (!this.selectionMode || this.store.selectedKeys.length === 0) {
      return;
    }
    const tracks = this.store.selectedTracks();
    if (tracks.length === 0) {
      return;
    }
    this.onOpenTracksActions(tracks, this.store.title);
  }
}

/** 宿主没有装配 runtime / playerStore 时的兜底页，只保留返回出口。 */
@Component
struct CollectionUnavailablePage {
  onClose: () => void = (): void => {};

  build() {
    Column({ space: ThemeSpacing.md }) {
      Text($r('app.string.collection_detail_unavailable_title'))
        .fontSize(ThemeTypography.emptyTitle)
        .lineHeight(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.collection_detail_unavailable_message'))
        .constraintSize({ maxWidth: 280 })
        .fontSize(ThemeTypography.body)
        .lineHeight(22)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button($r('app.string.collection_detail_back'), { stateEffect: false })
        .id(NativeUiIds.collectionDetailBack)
        .width(STATE_ACTION_MIN_WIDTH)
        .height(40)
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.onAccent)
        .backgroundColor(ThemeColors.accent)
        .borderRadius(ThemeRadius.md)
        .onClick(() => {
          this.onClose();
        })
    }
    .id(NativeUiIds.collectionDetailUnavailable)
    .width('100%')
    .height('100%')
    .padding({ left: ThemeSpacing.xxl, right: ThemeSpacing.xxl })
    .justifyContent(FlexAlign.Center)
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }
}