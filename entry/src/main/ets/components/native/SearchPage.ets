import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { PlayerStore } from '../../state/PlayerStore';
import { SearchStore, SearchStoreSnapshot } from '../../state/SearchStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { MobileTrack } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { ListStateKind, ListStateView } from './ListStateView';
import {
  PaginationFooter,
  PaginationFooterState
} from './PaginationFooter';
import { NativeUiIds } from './NativeUiIds';
import { CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { RuntimeCoverImageProvider } from './RuntimeCoverImageProvider';
import { CompactTrackRow } from './CompactTrackRow';

const SEARCH_INPUT_MAX_LENGTH: number = 80;
const SEARCH_INPUT_HEIGHT: number = 44;
const SEARCH_BAR_RADIUS: number = SEARCH_INPUT_HEIGHT / 2;
const SEARCH_CLEAR_SIZE: number = 32;
const SEARCH_LOAD_MORE_ERROR_MIN_HEIGHT: number = 72;
const SEARCH_PLAYER_ERROR_MIN_HEIGHT: number = 40;

@Component
export struct SearchPage {
  @ObjectLink store: SearchStore;
  @ObjectLink playerStore: PlayerStore;
  runtime: NativeAppRuntime | null = null;
  onMoreClick: (track: MobileTrack) => void = (_track: MobileTrack): void => {
  };
  /** 点击搜索结果开始播放后进入播放页；由宿主决定路由，页面本身不持有导航栈。 */
  onOpenPlayer: () => void = (): void => {};
  /** 多 P 合集点击后进入合集详情页，不再直接替换队列；由宿主压入路由。 */
  onOpenCollection: (track: MobileTrack) => void = (_track: MobileTrack): void => {};

  @State private draftKeyword: string = '';
  @State private pendingTrackKey: string = '';
  @State private actionError: string = '';
  private coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    this.pendingTrackKey = '';
    this.draftKeyword = this.store.snapshot.keyword;
    if (this.runtime !== null) {
      this.coverProvider = new RuntimeCoverImageProvider(this.runtime);
    }
  }

  aboutToDisappear(): void {
    // 只写普通字段；@State pendingTrackKey 在下次 aboutToAppear 复位。
    this.disposed = true;
  }

  build() {
    Column() {
      this.SearchToolbar()
      if (this.playerStore.error !== null) {
        this.PlayerErrorBar()
      }
      if (this.actionError.length > 0) {
        this.ActionErrorBar()
      }

      if (this.store.snapshot.items.length > 0) {
        this.ResultsContent()
      } else {
        this.SearchStateContent()
      }
    }
    .id(NativeUiIds.discoverPage)
    .width('100%')
    .height('100%')
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }

  @Builder
  PlayerErrorBar() {
    Text(`播放失败：${this.playerErrorText()}`)
      .id('search-player-error')
      .width('100%')
      .constraintSize({ minHeight: SEARCH_PLAYER_ERROR_MIN_HEIGHT })
      .padding({ left: ThemeSpacing.lg, right: ThemeSpacing.lg, top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
      .fontSize(ThemeTypography.caption)
      .fontColor(ThemeColors.textSecondary)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  ActionErrorBar() {
    Text(this.actionError)
      .id('search-action-error')
      .width('100%')
      .constraintSize({ minHeight: SEARCH_PLAYER_ERROR_MIN_HEIGHT })
      .padding({ left: ThemeSpacing.lg, right: ThemeSpacing.lg, top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
      .fontSize(ThemeTypography.caption)
      .fontColor(ThemeColors.textSecondary)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  SearchToolbar() {
    Row() {
      Row({ space: ThemeSpacing.xs }) {
        AppIcon({
          iconKind: AppIconKind.Search,
          iconSize: 18,
          iconColor: ThemeColors.textSecondary
        })
        TextInput({
          text: this.draftKeyword,
          placeholder: $r('app.string.search_input_placeholder')
        })
          .id(NativeUiIds.searchInput)
          .layoutWeight(1)
          .height(SEARCH_INPUT_HEIGHT)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .placeholderColor(ThemeColors.textSecondary)
          .backgroundColor(Color.Transparent)
          .padding({ left: ThemeSpacing.xs, right: ThemeSpacing.xs })
          .maxLength(SEARCH_INPUT_MAX_LENGTH)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string): void => {
            this.draftKeyword = value;
          })
          .onSubmit((_enterKey: EnterKeyType): void => {
            this.submitSearch();
          })
          .accessibilityText('搜索关键词')

        if (this.canClear()) {
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            AppIcon({
              iconKind: AppIconKind.Close,
              iconSize: 16,
              iconColor: ThemeColors.textSecondary
            })
          }
          .id('search-clear')
          .width(SEARCH_CLEAR_SIZE)
          .height(SEARCH_CLEAR_SIZE)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.clearSearch();
          })
          .accessibilityText('清空搜索')
        }
      }
      .layoutWeight(1)
      .height(SEARCH_INPUT_HEIGHT)
      .padding({ left: ThemeSpacing.md, right: ThemeSpacing.xs })
      .backgroundColor(ThemeColors.surfaceInset)
      .borderRadius(SEARCH_BAR_RADIUS)
      .alignItems(VerticalAlign.Center)
    }
    .id('search-toolbar')
    .width('100%')
    .padding({
      left: ThemeSpacing.lg,
      right: ThemeSpacing.lg,
      top: ThemeSpacing.sm,
      bottom: ThemeSpacing.sm
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SearchStateContent() {
    Scroll() {
      Column() {
        if (this.store.snapshot.status === 'searching') {
          ListStateView({
            viewId: NativeUiIds.searchLoadingState,
            state: ListStateKind.Loading,
            title: $r('app.string.search_loading_title'),
            message: $r('app.string.search_loading_message')
          })
        } else if (this.store.snapshot.status === 'empty') {
          ListStateView({
            viewId: NativeUiIds.searchEmptyState,
            state: ListStateKind.Empty,
            title: $r('app.string.search_no_results_title'),
            message: this.emptyMessage(),
            showMark: false
          })
        } else if (this.store.snapshot.status === 'error') {
          ListStateView({
            viewId: NativeUiIds.searchErrorState,
            state: ListStateKind.Error,
            title: $r('app.string.search_error_title'),
            message: this.errorMessage(),
            actionLabel: $r('app.string.search_retry'),
            onAction: (): void => {
              this.retrySearch();
            }
          })
        } else {
          ListStateView({
            viewId: NativeUiIds.searchIdleState,
            state: ListStateKind.Empty,
            title: $r('app.string.search_idle_title'),
            message: $r('app.string.search_idle_message'),
            showMark: false
          })
        }
      }
      .width('100%')
    }
    .id(NativeUiIds.searchState)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  ResultsContent() {
    Column() {
      List() {
        ForEach(this.store.snapshot.items, (track: MobileTrack) => {
          ListItem() {
            CompactTrackRow({
              imageCache: this.coverProvider,
              playerStore: this.playerStore,
              track: track,
              showMoreMenu: !this.isCollection(track),
              loading: this.isTrackLoading(track),
              onTrackClick: (selected: MobileTrack): void => {
                void this.handleTrackClick(selected);
              },
              onMoreClick: (selected: MobileTrack): void => {
                this.onMoreClick(selected);
              }
            })
          }
        }, (track: MobileTrack): string => track.key)

        ListItem() {
          this.ResultFooter(this.store.snapshot)
        }
      }
      .id(NativeUiIds.searchResults)
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: ThemeSpacing.lg,
        right: ThemeSpacing.lg,
        top: ThemeSpacing.xs,
        bottom: ThemeSpacing.sm
      })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  ResultFooter(snapshot: SearchStoreSnapshot) {
    if (snapshot.status === 'error') {
      Row({ space: ThemeSpacing.sm }) {
        Text(this.loadMoreErrorMessage())
          .layoutWeight(1)
          .fontSize(ThemeTypography.caption)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (snapshot.canRetry) {
          Button($r('app.string.search_retry'), { stateEffect: false })
            .id('search-load-more-retry')
            .constraintSize({ minWidth: 72, minHeight: 40 })
            .fontSize(ThemeTypography.caption)
            .fontColor(ThemeColors.textPrimary)
            .backgroundColor(ThemeColors.surfaceInset)
            .borderRadius(ThemeRadius.md)
            .onClick(() => {
              void this.store.retry();
            })
        }
      }
      .id(NativeUiIds.searchLoadMoreError)
      .width('100%')
      .constraintSize({ minHeight: SEARCH_LOAD_MORE_ERROR_MIN_HEIGHT })
      .padding({ left: ThemeSpacing.md, right: ThemeSpacing.md })
      .alignItems(VerticalAlign.Center)
    } else {
      PaginationFooter({
        state: snapshot.hasMore ? PaginationFooterState.HasNext : PaginationFooterState.NoNext,
        loading: snapshot.status === 'loadingMore',
        onLoadMore: (): void => {
          void this.store.loadMore();
        }
      })
    }
  }

  private submitSearch(): void {
    const keyword = this.draftKeyword.trim();
    if (keyword.length === 0) {
      this.clearSearch();
      return;
    }
    this.draftKeyword = keyword;
    void this.store.search(keyword);
  }

  private retrySearch(): void {
    const snapshot = this.store.read();
    if (snapshot.status === 'error' && snapshot.canRetry) {
      void this.store.retry();
      return;
    }
    if (snapshot.keyword.length === 0) {
      return;
    }
    this.draftKeyword = snapshot.keyword;
    this.store.clear();
    void this.store.search(snapshot.keyword);
  }

  private clearSearch(): void {
    this.draftKeyword = '';
    this.store.clear();
  }

  private isCollection(track: MobileTrack): boolean {
    return (track.collectionSize ?? 0) > 1;
  }

  private async handleTrackClick(track: MobileTrack): Promise<void> {
    if (this.disposed) {
      return;
    }
    if (this.isCollection(track)) {
      this.actionError = '';
      this.onOpenCollection(track);
      return;
    }
    if (this.pendingTrackKey.length > 0) {
      return;
    }
    const played = await this.playSingleNow(track);
    if (played && !this.disposed) {
      this.onOpenPlayer();
    }
  }

  /** 单曲放到队首并立即播放；已在队列中的曲目移动到队首，不重复添加。 */
  private async playSingleNow(track: MobileTrack): Promise<boolean> {
    if (this.pendingTrackKey.length > 0 || this.disposed) {
      return false;
    }
    this.actionError = '';
    this.pendingTrackKey = track.key;
    try {
      await this.playerStore.playTrackNow(track);
      return true;
    } catch (_error) {
      if (!this.disposed) {
        this.actionError = this.playerStore.error?.code === 'player.queueFull'
          ? '播放队列已满（500 首），请先清理队列。'
          : '播放失败，请稍后重试。';
      }
      return false;
    } finally {
      if (!this.disposed && this.pendingTrackKey === track.key) {
        this.pendingTrackKey = '';
      }
    }
  }

  private isTrackLoading(track: MobileTrack): boolean {
    return this.pendingTrackKey === track.key ||
      this.playerStore.queueRequest?.trackKey === track.key;
  }

  private playerErrorText(): string {
    return this.playerStore.error?.message ?? '播放操作失败，请稍后重试。';
  }

  private canClear(): boolean {
    return this.draftKeyword.length > 0 || this.store.snapshot.status !== 'idle';
  }

  private emptyMessage(): string {
    const keyword = this.store.snapshot.keyword.trim();
    return keyword.length > 0 ? `没有找到与“${keyword}”相关的音乐。` : '没有找到相关音乐。';
  }

  private errorMessage(): ResourceStr {
    return $r('app.string.search_error_message');
  }

  private loadMoreErrorMessage(): ResourceStr {
    return $r('app.string.search_more_error');
  }
}
