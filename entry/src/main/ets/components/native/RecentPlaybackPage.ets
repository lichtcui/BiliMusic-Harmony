import { FavoritesStore } from '../../state/FavoritesStore';
import { RecentPlaybackStore } from '../../state/RecentPlaybackStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { MobileTrack } from '../../types/MobileTypes';
import { MusicSelectionBar, MusicTrackRow, MusicTrackToolbar } from './MusicTrackList';
import { MusicPageEmptyState, MusicPageErrorBanner, MusicPageHeader } from './MusicPageTemplate';
import { NativeUiIds } from './NativeUiIds';
import { TRACK_LIST_PAGE_SIZE, nextTrackPage, visibleTrackCount } from './TrackListPaging';

/**
 * 历史行沿用歌单详情页的曲目行基准（design/playlist-page.html）：56 高、无序号/封面、
 * 标题 13/18、作者 12/16、行尾 36 收藏 + 竖向更多；多选时行首换 20 勾选圈。
 */
const RECENT_LIST_BOTTOM_PADDING: number = 20;
/** 工具条：与歌单详情页同一套尺寸（44 高、左右 16、播放键 32）。 */
/** 批量底栏：与歌单详情页 / 「我喜欢的」同一套尺寸。 */
/** 整页头部：与「我喜欢的」同构（64 高、40 圆形返回、20/26 标题）。 */
const RECENT_HEADER_HEIGHT: number = 64;
const RECENT_HEADER_ACTION_SIZE: number = 40;
const RECENT_HEADER_ICON_SIZE: number = 22;
const RECENT_HEADER_TITLE_GAP: number = 8;
const RECENT_PAGE_PADDING_VERTICAL: number = 4;

/**
 * 「我的 · 历史」整页（从右侧滑入，与「我喜欢的」共用同一种进入方式）。
 *
 * 行样式与「歌单详情页」的歌曲列表一致：透明 56 高行、标题/作者、行尾收藏 + 竖向更多，
 * 正在播放的曲目在标题前显示音质图标并染色（不再是独立的大序号和「正在播放」文案）。
 * 工具条 / 多选同样照搬歌单详情页：左「全部播放（N）」，右侧多选入口；进入多选后
 * 入口换成「全选 + 关闭」，行首换成勾选圈，底部固定「删除 / 添加到」，
 * 不再插一条「已选 N 首」动作行。删除不弹二次确认，点一下即批量移除（全选后等价于清空历史）；
 * 添加到打开多曲抽屉，歌单与「加入我喜欢的」都在抽屉里完成。
 * 选中态只用行首勾选圈表示，不给整行铺底色。
 *
 * 收藏按钮直接读写 `FavoritesStore`：未收藏是描边空心、已收藏换成实心爱心，
 * 不再只是换颜色，避免「点了没反应」和「收藏了看不出来」两种误判。
 */
@Component
export struct RecentPlaybackPage {
  @ObjectLink store: RecentPlaybackStore;
  @ObjectLink favoritesStore: FavoritesStore;
  onClose: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  onOpenTracksActions: (tracks: MobileTrack[], contextTitle: string) => void =
    (_tracks: MobileTrack[], _contextTitle: string): void => {};
  /** 点击曲目开始播放后进入播放页；由宿主决定路由，页面本身不持有导航栈。 */
  onOpenPlayer: () => void = (): void => {};

  @State private selectionMode: boolean = false;
  /** 首屏只建一页行；滚到末尾再追加，避免长历史一次性建满组件树。 */
  @State private visibleCount: number = TRACK_LIST_PAGE_SIZE;
  @State private removeBusy: boolean = false;
  /** 页面卸载后不再把迟到的播放结果转成导航，避免返回列表时又被弹回播放页。 */
  private destroyed: boolean = false;

  @Builder
  Header() {
    MusicPageHeader({
      headerId: NativeUiIds.recentHeader,
      backId: NativeUiIds.recentHeaderBack,
      backLabel: $r('app.string.favorite_back'),
      title: $r('app.string.mine_section_history'),
      rightPadding: ThemeSpacing.gutter,
      onBack: (): void => {
        this.onClose();
      }
    })
  }

  @Builder
  TrackRow(track: MobileTrack, index: number) {
    MusicTrackRow({
      track: track,
      index: index,
      selectionMode: this.selectionMode,
      selected: this.store.isSelected(track.key),
      current: this.isCurrent(track),
      favorite: this.favoritesStore.isFavorite(track.key),
      favoritePending: this.favoritesStore.isPending(track.key),
      rowId: NativeUiIds.recentRow(index),
      favoriteId: NativeUiIds.recentFavorite(index),
      moreId: NativeUiIds.recentMore(index),
      onRowTap: (): void => {
        if (this.selectionMode) {
          this.store.toggleSelection(track.key);
          return;
        }
        void this.playAndOpenPlayer(index);
      },
      onFavoriteTap: (): void => {
        void this.favoritesStore.toggle(track);
      },
      onMoreTap: (): void => {
        this.onOpenTrackActions(track);
      }
    })
  }

  @Builder
  ErrorBanner() {
    MusicPageErrorBanner({
      bannerId: NativeUiIds.recentError,
      dismissId: NativeUiIds.recentErrorDismiss,
      message: this.errorMessage(),
      dismissLabel: $r('app.string.recent_error_dismiss'),
      compact: true,
      onDismiss: (): void => {
        this.dismissError();
      }
    })
  }

  @Builder
  EmptyState() {
    MusicPageEmptyState({
      emptyId: NativeUiIds.recentEmpty,
      showIcon: false,
      title: $r('app.string.recent_empty_title'),
      description: $r('app.string.recent_empty_description'),
      descriptionMaxWidth: 300,
      descriptionLineHeight: ThemeTypography.bodyLineHeight,
      compact: true,
      paddingTop: 0,
      paddingBottom: 0
    })
  }

  /** 工具条 / 多选 / 底栏与歌单详情共用同一个音乐列表模板。 */
  @Builder
  Toolbar() {
    MusicTrackToolbar({
      toolbarId: NativeUiIds.recentToolbar,
      playAllId: NativeUiIds.recentPlayAll,
      selectToggleId: NativeUiIds.recentSelect,
      selectAllId: NativeUiIds.recentSelectAll,
      exitSelectId: NativeUiIds.recentExitSelect,
      trackCount: this.store.tracks.length,
      busy: this.batchBusy(),
      selectionMode: this.selectionMode,
      allSelected: this.store.isAllSelected(),
      playAllLabel: $r('app.string.recent_play_all'),
      selectLabel: $r('app.string.recent_select'),
      exitSelectLabel: $r('app.string.recent_select_exit'),
      selectAllLabel: $r('app.string.recent_select_all'),
      onPlayAll: (): void => {
        void this.store.playAll();
      },
      onSelectToggle: (): void => {
        this.enterSelection();
      },
      onExitSelect: (): void => {
        this.exitSelection();
      },
      onSelectAll: (): void => {
        this.toggleSelectAll();
      }
    })
  }

  @Builder
  BottomBar() {
    MusicSelectionBar({
      barId: NativeUiIds.recentBottomBar,
      deleteId: NativeUiIds.recentRemoveSelected,
      addId: NativeUiIds.recentAddSelected,
      deleteLabel: $r('app.string.recent_delete'),
      addLabel: $r('app.string.recent_add_to'),
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

  aboutToDisappear(): void {
    this.destroyed = true;
    // clearSelection() 会写 @Track selectedKeys；销毁期间写状态会触发重建 / 140110。
    const store = this.store;
    setTimeout((): void => {
      store.clearSelection();
    }, 0);
  }

  build() {
    Column() {
      this.Header()

      if (this.hasError()) {
        this.ErrorBanner()
      }

      if (this.store.tracks.length === 0) {
        this.EmptyState()
      } else {
        this.Toolbar()

        List({ space: 0 }) {
          ForEach(this.store.tracks.slice(0,
            visibleTrackCount(this.visibleCount, this.store.tracks.length)),
            (track: MobileTrack, index: number) => {
            ListItem() {
              this.TrackRow(track, index)
            }
          }, (track: MobileTrack): string => track.key)
        }
        .id(NativeUiIds.recentList)
        .width('100%')
        .layoutWeight(1)
        .padding({
          bottom: RECENT_LIST_BOTTOM_PADDING
        })
        .scrollBar(BarState.Off)
        .onReachEnd(() => {
          if (this.visibleCount < this.store.tracks.length) {
            this.visibleCount = nextTrackPage(this.visibleCount, this.store.tracks.length);
          }
        })

        if (this.selectionMode) {
          this.BottomBar()
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: RECENT_PAGE_PADDING_VERTICAL,
      bottom: RECENT_PAGE_PADDING_VERTICAL
    })
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }

  private async playAndOpenPlayer(index: number): Promise<void> {
    if (await this.store.playAt(index)) {
      if (!this.destroyed) {
        this.onOpenPlayer();
      }
    }
  }

  private isCurrent(track: MobileTrack): boolean {
    return track.key.length > 0 && track.key === this.store.currentKey;
  }

  private displayTitle(track: MobileTrack): ResourceStr {
    return track.title.trim().length > 0 ? track.title : $r('app.string.recent_unknown_track');
  }

  private displayArtist(track: MobileTrack): ResourceStr {
    return track.artist.trim().length > 0 ? track.artist : $r('app.string.recent_unknown_artist');
  }

  private hasError(): boolean {
    return this.store.error !== null || this.favoritesStore.error !== null;
  }

  private errorMessage(): Resource {
    return this.favoritesStore.error !== null ?
      $r('app.string.recent_favorite_error') : $r('app.string.recent_error');
  }

  private dismissError(): void {
    this.store.clearError();
    if (this.favoritesStore.error !== null) {
      this.favoritesStore.clearError();
    }
  }

  private batchBusy(): boolean {
    return this.removeBusy || this.store.batchBusy;
  }

  private canActOnSelection(): boolean {
    return !this.batchBusy() && this.store.selectedKeys.length > 0;
  }

  private enterSelection(): void {
    if (this.batchBusy()) {
      return;
    }
    this.selectionMode = true;
  }

  private exitSelection(): void {
    this.selectionMode = false;
    this.store.clearSelection();
  }

  /** 工具条「全选」只切换勾选：未全选 → 全选；已全选 → 清空。关闭按钮独立退出多选。 */
  private toggleSelectAll(): void {
    if (this.batchBusy()) {
      return;
    }
    if (this.store.isAllSelected()) {
      this.store.clearSelection();
    } else {
      this.store.selectAll();
    }
  }

  private addSelected(): void {
    if (!this.canActOnSelection()) {
      return;
    }
    const tracks = this.store.selectedTracks();
    if (tracks.length === 0) {
      return;
    }
    this.onOpenTracksActions(tracks, '');
  }

  private async removeSelected(): Promise<void> {
    if (!this.canActOnSelection()) {
      return;
    }
    this.removeBusy = true;
    try {
      if (await this.store.removeSelected()) {
        this.exitSelection();
      }
    } finally {
      this.removeBusy = false;
    }
  }
}