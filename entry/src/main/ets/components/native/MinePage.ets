import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { AuthStore } from '../../state/AuthStore';
import { DownloadStore } from '../../state/DownloadStore';
import { FavoritesStore } from '../../state/FavoritesStore';
import { PlaylistStore } from '../../state/PlaylistStore';
import { PlayerStore } from '../../state/PlayerStore';
import { RecentPlaybackStore } from '../../state/RecentPlaybackStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing
} from '../../theme/NativeTheme';
import { MobileTrack } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { MineProfileHeader } from './MineProfileHeader';
import { PlaylistPlaybackAction, resolvePlaylistPlaybackAction } from './MinePageState';
import { NativeUiIds } from './NativeUiIds';
import { PlaylistsPage } from './PlaylistsPage';
import { RuntimeCoverImageProvider } from './RuntimeCoverImageProvider';

/**
 * 新稿实测：四个方块一行居中、间距 8、上方留 16；方块内图标 24、圆角 12。
 * 方块用 `layoutWeight(1)` 自适应：360vp 屏（24 边距 + 3×8 间距）刚好 72，宽屏最多也是 72。
 * 播放角标图标 12，外圈 32 的按钮把触控热区撑开。
 */
const MINE_QUICK_CARD_SIZE: number = 72;
const MINE_QUICK_CARD_GAP: number = 8;
const MINE_QUICK_ICON_SIZE: number = 24;
const MINE_QUICK_BADGE_ICON: number = 12;
const MINE_QUICK_BADGE_ACTION_SIZE: number = 32;

/**
 * 快捷方块右下角的播放 / 暂停角标。
 *
 * 与歌单行尾播放键同构：自己用 `@ObjectLink` 订阅 `PlayerStore`，播放态变化只重绘这颗
 * 按钮。若把 `playing` 当 `@Builder` 参数传进来，参数按值捕获，点完播放后不会跟着切换。
 * 图标颜色也与歌单行尾一致，不加圆底。
 *
 * 目标列表的 key 用回调**实时**取（`provideTrackKeys`），不落在 `@Prop` 数组快照上：
 * 资料库是 deferred + 异步读盘，列表在角标创建后还可能整体换新；角标每次重绘都重新读，
 * 避免拿旧快照和播放器队列比对。
 */
@Component
struct QuickPlayBadge {
  @ObjectLink playerStore: PlayerStore;
  provideTrackKeys: () => string[] = (): string[] => [];
  playId: string = '';
  playAccessibility: Resource = $r('app.string.mine_liked_play');
  onToggle: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      AppIcon({
        iconKind: this.isPlaying() ? AppIconKind.Pause : AppIconKind.Play,
        iconSize: MINE_QUICK_BADGE_ICON,
        iconColor: ThemeColors.textSecondary
      })
    }
    .id(this.playId)
    .width(MINE_QUICK_BADGE_ACTION_SIZE)
    .height(MINE_QUICK_BADGE_ACTION_SIZE)
    .padding(0)
    .margin({ right: 1, bottom: 1 })
    .backgroundColor(Color.Transparent)
    .onClick((): void => {
      this.onToggle();
    })
    .accessibilityText(this.isPlaying() ? $r('app.string.player_pause') : this.playAccessibility)
  }

  private isPlaying(): boolean {
    return resolvePlaylistPlaybackAction(this.playerStore.snapshot.status,
      this.playerStore.snapshot.queue, this.provideTrackKeys()) === PlaylistPlaybackAction.Pause;
  }
}

/**
 * 「我的」页（新稿）。
 *
 * 结构：页头（44 头像 + 昵称/副题 + 设置）→ 四块快捷方块（我喜欢的 / 历史 / 下载 / 新建歌单）
 * → 歌单列表。页头与方块固定，只有歌单列表滚动。
 *
 * 方块只有图标，没有可见文字；「我喜欢的」「历史」「下载」右下角的播放角标可点，
 * 播放 / 暂停整个列表，状态图标与歌单行尾一致；列表为空时不显示角标（行为三块统一）。
 * 历史与下载都走右侧滑入的路由页（`RecentPlaybackPage` / `DownloadsPage`），
 * 与「我喜欢的」保持同一种进入方式。
 */
@Component
export struct MinePage {
  @ObjectLink authStore: AuthStore;
  @ObjectLink playlistStore: PlaylistStore;
  @ObjectLink favoritesStore: FavoritesStore;
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink recentStore: RecentPlaybackStore;
  @ObjectLink downloadStore: DownloadStore;
  runtime: NativeAppRuntime | null = null;
  onOpenSettings: () => void = (): void => {};
  onOpenLogin: () => void = (): void => {};
  onOpenLiked: () => void = (): void => {};
  onOpenHistory: () => void = (): void => {};
  onOpenDownloads: () => void = (): void => {};
  /** 新建歌单：抽屉挂在根 Stack 上（与其它抽屉同一层），这里只负责发请求。 */
  onCreatePlaylist: () => void = (): void => {};
  onOpenPlaylist: (playlistId: string) => void = (_playlistId: string): void => {};
  onPlaylistDeleted: (playlistId: string) => void = (_playlistId: string): void => {};

  private coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;

  aboutToAppear(): void {
    if (this.runtime !== null) {
      this.coverProvider = new RuntimeCoverImageProvider(this.runtime);
    }
  }

  @Builder
  QuickPlayableCard(cardId: string, playId: string, iconKind: AppIconKind,
    cardColor: Resource, contentColor: Resource, accessibility: Resource,
    playAccessibility: Resource, provideTrackKeys: () => string[], canPlay: boolean,
    onOpen: () => void, onToggle: () => void) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        AppIcon({
          iconKind: iconKind,
          iconSize: MINE_QUICK_ICON_SIZE,
          iconColor: contentColor
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick((): void => {
        onOpen();
      })
      .accessibilityText(accessibility)

      /* 独立热区的播放角标：与卡片本体是兄弟节点，避免点击叠套；播放态由子组件自己订阅。
         列表为空时不渲染角标，和「没有歌就没有播放入口」保持一致；三块快捷方块同一条规则。 */
      if (canPlay) {
        QuickPlayBadge({
          playerStore: this.playerStore,
          provideTrackKeys: provideTrackKeys,
          playId: playId,
          playAccessibility: playAccessibility,
          onToggle: onToggle
        })
      }
    }
    .id(cardId)
    .layoutWeight(1)
    .aspectRatio(1)
    .constraintSize({ maxWidth: MINE_QUICK_CARD_SIZE })
    .borderRadius(ThemeRadius.lg)
    .backgroundColor(cardColor)
  }

  @Builder
  QuickCreateCard() {
    Column() {
      AppIcon({
        iconKind: AppIconKind.Plus,
        iconSize: MINE_QUICK_ICON_SIZE,
        iconColor: ThemeColors.accent
      })
    }
    .id(NativeUiIds.mineQuickCreate)
    .layoutWeight(1)
    .aspectRatio(1)
    .constraintSize({ maxWidth: MINE_QUICK_CARD_SIZE })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(ThemeColors.accentSoft)
    .borderRadius(ThemeRadius.lg)
    .border({
      width: 1,
      color: ThemeColors.quickCreateOutline,
      style: BorderStyle.Dashed
    })
    .enabled(!this.playlistStore.isBusy())
    .opacity(this.playlistStore.isBusy() ? 0.5 : 1)
    .onClick((): void => {
      this.onCreatePlaylist();
    })
    .accessibilityText($r('app.string.mine_create_playlist'))
  }

  @Builder
  QuickActionsRow() {
    Row({ space: MINE_QUICK_CARD_GAP }) {
      this.QuickPlayableCard(
        NativeUiIds.mineQuickLiked,
        NativeUiIds.mineQuickLikedPlay,
        AppIconKind.Heart,
        ThemeColors.quickLikedSurface,
        ThemeColors.quickLikedContent,
        $r('app.string.mine_liked_title'),
        $r('app.string.mine_liked_play'),
        (): string[] => this.likedTrackKeys(),
        this.likedTrackKeys().length > 0,
        (): void => {
          this.onOpenLiked();
        },
        (): void => {
          void this.toggleLikedPlayback();
        }
      )

      this.QuickPlayableCard(
        NativeUiIds.mineQuickHistory,
        NativeUiIds.mineQuickHistoryPlay,
        AppIconKind.Clock,
        ThemeColors.surfaceInset,
        ThemeColors.textPrimary,
        $r('app.string.mine_section_history'),
        $r('app.string.mine_history_play'),
        (): string[] => this.recentTrackKeys(),
        this.recentTrackKeys().length > 0,
        (): void => {
          this.onOpenHistory();
        },
        (): void => {
          void this.toggleHistoryPlayback();
        }
      )

      this.QuickPlayableCard(
        NativeUiIds.mineQuickDownloads,
        NativeUiIds.mineQuickDownloadsPlay,
        AppIconKind.Download,
        ThemeColors.surfaceInset,
        ThemeColors.textPrimary,
        $r('app.string.mine_section_downloads'),
        $r('app.string.mine_downloads_play'),
        (): string[] => this.downloadTrackKeys(),
        this.downloadTrackKeys().length > 0,
        (): void => {
          this.onOpenDownloads();
        },
        (): void => {
          void this.toggleDownloadsPlayback();
        }
      )

      this.QuickCreateCard()
    }
    .id(NativeUiIds.mineQuickActions)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({
      left: ThemeSpacing.gutter,
      right: ThemeSpacing.gutter,
      top: ThemeSpacing.lg
    })
  }

  build() {
    Column() {
      MineProfileHeader({
        authStore: this.authStore,
        onOpenSettings: (): void => {
          this.onOpenSettings();
        },
        onOpenLogin: (): void => {
          this.onOpenLogin();
        }
      })

      this.QuickActionsRow()

      Column() {
        PlaylistsPage({
          store: this.playlistStore,
          playerStore: this.playerStore,
          imageCache: this.coverProvider,
          onOpenPlaylist: (playlistId: string): void => {
            this.onOpenPlaylist(playlistId);
          },
          onPlaylistDeleted: (playlistId: string): void => {
            this.onPlaylistDeleted(playlistId);
          }
        })
      }
      .id(NativeUiIds.minePlaylistsContent)
      .width('100%')
      .layoutWeight(1)
    }
    .id(NativeUiIds.minePage)
    .width('100%')
    .height('100%')
    .safeAreaPadding({ top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.bg)
  }

  private likedTrackKeys(): string[] {
    return this.favoritesStore.tracks.map((track: MobileTrack): string => track.key);
  }

  private recentTrackKeys(): string[] {
    return this.recentStore.tracks.map((track: MobileTrack): string => track.key);
  }

  private downloadTrackKeys(): string[] {
    return this.downloadStore.tracks.map((track: MobileTrack): string => track.key);
  }

  /** 快捷角标：暂停 / 续播 / 从头播放，口径与歌单行尾播放键完全一致。 */
  private async toggleLikedPlayback(): Promise<void> {
    const keys = this.likedTrackKeys();
    if (keys.length === 0) {
      return;
    }
    const action = resolvePlaylistPlaybackAction(this.playerStore.snapshot.status,
      this.playerStore.snapshot.queue, keys);
    if (action === PlaylistPlaybackAction.Pause) {
      try {
        await this.playerStore.pause();
      } catch (_error) {
        // Playback failures stay owned by PlayerStore.
      }
      return;
    }
    if (action === PlaylistPlaybackAction.Resume) {
      try {
        await this.playerStore.play();
      } catch (_error) {
        // Playback failures stay owned by PlayerStore.
      }
      return;
    }
    await this.favoritesStore.playAll();
  }

  private async toggleHistoryPlayback(): Promise<void> {
    const keys = this.recentTrackKeys();
    if (keys.length === 0) {
      return;
    }
    const action = resolvePlaylistPlaybackAction(this.playerStore.snapshot.status,
      this.playerStore.snapshot.queue, keys);
    if (action === PlaylistPlaybackAction.Pause) {
      try {
        await this.playerStore.pause();
      } catch (_error) {
        // Playback failures stay owned by PlayerStore.
      }
      return;
    }
    if (action === PlaylistPlaybackAction.Resume) {
      try {
        await this.playerStore.play();
      } catch (_error) {
        // Playback failures stay owned by PlayerStore.
      }
      return;
    }
    await this.recentStore.playAll();
  }

  private async toggleDownloadsPlayback(): Promise<void> {
    const keys = this.downloadTrackKeys();
    if (keys.length === 0) {
      return;
    }
    const action = resolvePlaylistPlaybackAction(this.playerStore.snapshot.status,
      this.playerStore.snapshot.queue, keys);
    if (action === PlaylistPlaybackAction.Pause) {
      try {
        await this.playerStore.pause();
      } catch (_error) {
        // Playback failures stay owned by PlayerStore.
      }
      return;
    }
    if (action === PlaylistPlaybackAction.Resume) {
      try {
        await this.playerStore.play();
      } catch (_error) {
        // Playback failures stay owned by PlayerStore.
      }
      return;
    }
    await this.downloadStore.playAll();
  }
}