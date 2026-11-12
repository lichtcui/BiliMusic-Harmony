import { DownloadStore } from '../../state/DownloadStore';
import { FavoritesStore } from '../../state/FavoritesStore';
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

/** 与历史整页共用同一套行 / 工具条 / 头部尺寸，只把「添加到」换成纯删除底栏。 */
const DOWNLOADS_PAGE_PADDING_VERTICAL: number = 4;
const DOWNLOADS_HEADER_HEIGHT: number = 64;
const DOWNLOADS_HEADER_ACTION_SIZE: number = 40;
const DOWNLOADS_HEADER_ICON_SIZE: number = 22;
const DOWNLOADS_HEADER_TITLE_GAP: number = 8;
const DOWNLOADS_LIST_BOTTOM_PADDING: number = 20;

/**
 * 「我的 · 下载」整页（从右侧滑入，与历史 / 我喜欢的同构）。
 *
 * 行样式完全复用 `MusicTrackRow`：播放中的曲目染色、行尾收藏 + 竖向更多。
 * 多选底栏只保留「删除」——删除下载本身没有歧义，不需要二次确认；
 * 「添加到（歌单 / 我喜欢的）」走行尾的更多抽屉。
 */
@Component
export struct DownloadsPage {
  @ObjectLink store: DownloadStore;
  @ObjectLink favoritesStore: FavoritesStore;
  onClose: () => void = (): void => {};
  onOpenTrackActions: (track: MobileTrack) => void = (_track: MobileTrack): void => {};
  /** 点击曲目开始播放后进入播放页；由宿主决定路由，页面本身不持有导航栈。 */
  onOpenPlayer: () => void = (): void => {};

  @State private selectionMode: boolean = false;
  @State private visibleCount: number = TRACK_LIST_PAGE_SIZE;
  @State private removeBusy: boolean = false;
  private destroyed: boolean = false;

  @Builder
  Header() {
    MusicPageHeader({
      headerId: NativeUiIds.downloadsHeader,
      backId: NativeUiIds.downloadsHeaderBack,
      backLabel: $r('app.string.favorite_back'),
      title: $r('app.string.mine_section_downloads'),
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
      rowId: NativeUiIds.downloadsRow(index),
      favoriteId: NativeUiIds.downloadsFavorite(index),
      moreId: NativeUiIds.downloadsMore(index),
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
      bannerId: NativeUiIds.downloadsError,
      dismissId: NativeUiIds.downloadsErrorDismiss,
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
      emptyId: NativeUiIds.downloadsEmpty,
      showIcon: false,
      title: $r('app.string.mine_downloads_empty_title'),
      description: $r('app.string.mine_downloads_empty_description'),
      descriptionMaxWidth: 300,
      descriptionLineHeight: ThemeTypography.bodyLineHeight,
      compact: true,
      paddingTop: 0,
      paddingBottom: 0
    })
  }

  @Builder
  Toolbar() {
    MusicTrackToolbar({
      toolbarId: NativeUiIds.downloadsToolbar,
      playAllId: NativeUiIds.downloadsPlayAll,
      selectToggleId: NativeUiIds.downloadsSelect,
      selectAllId: NativeUiIds.downloadsSelectAll,
      exitSelectId: NativeUiIds.downloadsExitSelect,
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
      barId: NativeUiIds.downloadsBottomBar,
      deleteId: NativeUiIds.downloadsRemoveSelected,
      deleteLabel: $r('app.string.recent_delete'),
      deleteEnabled: this.canActOnSelection(),
      showDelete: true,
      showAdd: false,
      onDelete: (): void => {
        void this.removeSelected();
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
        .id(NativeUiIds.downloadsList)
        .width('100%')
        .layoutWeight(1)
        .padding({
          bottom: DOWNLOADS_LIST_BOTTOM_PADDING
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
    .id(NativeUiIds.downloadsPage)
    .width('100%')
    .height('100%')
    .padding({
      top: DOWNLOADS_PAGE_PADDING_VERTICAL,
      bottom: DOWNLOADS_PAGE_PADDING_VERTICAL
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