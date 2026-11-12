import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import {
  TrackActionBusyState,
  TrackActionFeedback,
  TrackActionOutcome,
  TrackActionStore,
  TrackPlaylistOption
} from '../../state/TrackActionStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { MobileTrack } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { BottomSheet } from './BottomSheet';
import { CoverImage, CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { NativeUiIds } from './NativeUiIds';
import { RuntimeCoverImageProvider } from './RuntimeCoverImageProvider';
import { SheetSize } from './SheetSizing';

const ACTION_ROW_HEIGHT: number = 56;
const ACTION_COVER_SIZE: number = 40;
const ACTION_ADD_SIZE: number = 36;
const ACTION_ADD_ICON: number = 20;
const ACTION_SPINNER_SMALL: number = 16;

/**
 * 「更多操作」抽屉（收藏 / 加入我喜欢的 / 加入歌单）。
 *
 * 2026-11 起不再手写抽屉外壳：蒙层、拖拽条、标题、圆角、安全区与上拉展开
 * 全部由共用外壳 `BottomSheet` 提供（大档 78%），和其它抽屉保持同一套 chrome。
 * 这里只保留内容：收藏动作、歌单段标题与歌单列表。
 *
 * 所有动作点击后立即收起抽屉，结果交给宿主在底部弹 toast；抽屉内不再渲染反馈条。
 *
 * 行样式与设计稿一致地打平：收藏行和歌单行都不再使用卡片底色，靠图标、文字与留白分层；
 * 关闭路径只有蒙层点击、拖拽条点按 / 下滑和系统返回，不再提供底部「取消」。
 */
@Component
export struct TrackActionSheet {
  @ObjectLink store: TrackActionStore;
  /** 宿主 runtime：歌单行封面复用图片缓存；为空时回落为空列表封面（首字块）。 */
  runtime: NativeAppRuntime | null = null;
  onClose: () => void = (): void => {};
  /** 动作结果交给宿主统一弹底部提示；抽屉本身不再展示反馈条。 */
  onToast: (message: ResourceStr) => void = (_message: ResourceStr): void => {};
  /** 下载当前曲目（多选时为所选曲目）；真正的下载由宿主持有的 DownloadStore 执行。 */
  onDownload: (tracks: MobileTrack[]) => void = (_tracks: MobileTrack[]): void => {};
  /** 宿主驱动的滑入 / 滑出位移（vp）：挂载前等于屏高，宿主动画回 0。 */
  @Prop panelOffsetY: number = 0;
  /** 宿主驱动的蒙层不透明度（0–1），与位移同步淡入淡出。 */
  @Prop scrimAlpha: number = 1;

  private coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;

  aboutToAppear(): void {
    if (this.runtime !== null) {
      this.coverProvider = new RuntimeCoverImageProvider(this.runtime);
    }
  }

  @Builder
  FavoriteAction() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: ThemeSpacing.md }) {
        if (this.store.busyAction === TrackActionBusyState.Favorite) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(ThemeColors.accent)
        } else {
          if (this.store.isFavorite) {
            AppIcon({
              iconKind: AppIconKind.HeartFilled,
              iconSize: 22,
              iconColor: ThemeColors.accent
            })
          } else {
            AppIcon({
              iconKind: AppIconKind.Heart,
              iconSize: 22,
              iconColor: ThemeColors.textPrimary
            })
          }
        }
        Text(this.store.isFavorite ? $r('app.string.track_action_favorite_remove') :
          $r('app.string.track_action_favorite_add'))
          .layoutWeight(1)
          .fontSize(ThemeTypography.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.store.busyAction === TrackActionBusyState.Favorite) {
          Text($r('app.string.track_action_working'))
            .fontSize(ThemeTypography.eyebrow)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
    }
    .id('track-action-favorite')
    .width('100%')
    .height(ACTION_ROW_HEIGHT)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.store.isBusy())
    .opacity(this.store.isBusy() && this.store.busyAction !== TrackActionBusyState.Favorite ? 0.55 : 1)
    .onClick(() => {
      void this.commitFavorite();
    })
  }

  /**
   * 多选模式的「加入我喜欢的」：单曲模式仍走 `FavoriteAction` 的收藏/取消收藏切换，
   * 批量模式只补写尚未收藏的曲目，已收藏的保持不动。
   */
  @Builder
  BatchFavoriteAction() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: ThemeSpacing.md }) {
        if (this.store.busyAction === TrackActionBusyState.FavoriteBatch) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(ThemeColors.accent)
        } else {
          AppIcon({
            iconKind: this.store.favoriteCandidateCount > 0 ? AppIconKind.Heart : AppIconKind.HeartFilled,
            iconSize: 22,
            iconColor: this.store.favoriteCandidateCount > 0 ? ThemeColors.textPrimary : ThemeColors.textSecondary
          })
        }
        Text(this.store.favoriteCandidateCount > 0 ? $r('app.string.track_action_favorite_batch') :
          $r('app.string.track_action_favorite_batch_all'))
          .layoutWeight(1)
          .fontSize(ThemeTypography.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.store.favoriteCandidateCount > 0 ? ThemeColors.textPrimary : ThemeColors.textSecondary)
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.store.busyAction === TrackActionBusyState.FavoriteBatch) {
          Text($r('app.string.track_action_working'))
            .fontSize(ThemeTypography.eyebrow)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
    }
    .id('track-action-favorite-batch')
    .width('100%')
    .height(ACTION_ROW_HEIGHT)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.store.isBusy() && this.store.favoriteCandidateCount > 0)
    .opacity(this.batchFavoriteOpacity())
    .onClick(() => {
      void this.commitBatchFavorite();
    })
  }

  @Builder
  DownloadAction() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: ThemeSpacing.md }) {
        AppIcon({
          iconKind: AppIconKind.Download,
          iconSize: 22,
          iconColor: ThemeColors.textPrimary
        })
        Text(this.store.isMulti() ? $r('app.string.track_action_download_batch') :
          $r('app.string.track_action_download'))
          .layoutWeight(1)
          .fontSize(ThemeTypography.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
    }
    .id(NativeUiIds.trackActionDownload)
    .width('100%')
    .height(ACTION_ROW_HEIGHT)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.store.isBusy())
    .opacity(this.store.isBusy() ? 0.55 : 1)
    .onClick(() => {
      this.commitDownload();
    })
    .accessibilityText(this.store.isMulti() ? $r('app.string.track_action_download_batch') :
      $r('app.string.track_action_download'))
  }

  @Builder
  PlaylistHeading() {
    Row() {
      Text($r('app.string.track_action_playlist_section'))
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  PlaylistRow(option: TrackPlaylistOption, index: number) {
    Row({ space: ThemeSpacing.md }) {
      if (option.coverUrl.length > 0) {
        CoverImage({
          imageCache: this.coverProvider,
          coverUrl: option.coverUrl,
          coverSize: ACTION_COVER_SIZE,
          cornerRadius: ThemeRadius.md
        })
      } else {
        Stack() {
          Text(this.playlistInitial(option.name))
            .fontSize(ThemeTypography.body)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
        }
        .width(ACTION_COVER_SIZE)
        .height(ACTION_COVER_SIZE)
        .borderRadius(ThemeRadius.md)
        .backgroundColor(ThemeColors.surfaceInset)
      }

      Column({ space: 1 }) {
        Text(option.name)
          .width('100%')
          .fontSize(ThemeTypography.caption)
          .lineHeight(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 3 }) {
          Text(option.trackCount.toString())
            .fontSize(ThemeTypography.meta)
            .lineHeight(16)
            .fontColor(ThemeColors.textSecondary)
          Text($r('app.string.playlist_track_suffix'))
            .fontSize(ThemeTypography.meta)
            .lineHeight(16)
            .fontColor(ThemeColors.textSecondary)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button({ type: ButtonType.Circle, stateEffect: false }) {
        if (this.store.busyPlaylistId === option.id) {
          LoadingProgress()
            .width(ACTION_SPINNER_SMALL)
            .height(ACTION_SPINNER_SMALL)
            .color(ThemeColors.accent)
        } else if (option.containsTrack) {
          AppIcon({
            iconKind: AppIconKind.Check,
            iconSize: ACTION_ADD_ICON,
            iconColor: ThemeColors.textSecondary
          })
        } else {
          AppIcon({
            iconKind: AppIconKind.Plus,
            iconSize: ACTION_ADD_ICON,
            iconColor: ThemeColors.accent
          })
        }
      }
      .id(`track-action-playlist-${index}`)
      .width(ACTION_ADD_SIZE)
      .height(ACTION_ADD_SIZE)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .enabled(!this.store.isBusy() && !option.containsTrack)
      .onClick(() => {
        void this.commitAddToPlaylist(option);
      })
      .accessibilityText(this.playlistAddAccessibilityText(option))
    }
    .width('100%')
    .height(ACTION_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .opacity(this.store.isBusy() && this.store.busyPlaylistId !== option.id ? 0.55 : 1)
  }

  build() {
    BottomSheet({
      sheetId: NativeUiIds.trackActionSheet,
      title: this.store.isMulti() ? $r('app.string.track_action_batch_title') :
        $r('app.string.track_action_title'),
      // 单曲模式不再显示副标题（头部走共用外壳的单行 36）；批量模式保留合集名与曲目数。
      subtitle: this.store.isMulti() ? this.subtitleText() : '',
      // 歌单列表可能很长，走大档（78%）；从头部上拉可展开到安全区下方。
      sheetSize: SheetSize.Large,
      panelOffsetY: this.panelOffsetY,
      scrimAlpha: this.scrimAlpha,
      onClose: this.onClose
    }) {
      this.SheetContent()
    }
  }

  @Builder
  SheetContent() {
    Column({ space: ThemeSpacing.sm }) {
      if (this.store.isMulti()) {
        this.BatchFavoriteAction()
      } else {
        this.FavoriteAction()
      }
      this.DownloadAction()
      this.PlaylistHeading()

      if (this.store.playlists.length === 0) {
        Column() {
          Text(this.store.isMulti() ? $r('app.string.track_action_batch_no_playlists') :
            $r('app.string.track_action_no_playlists'))
            .width('100%')
            .fontSize(ThemeTypography.caption)
            .lineHeight(20)
            .fontColor(ThemeColors.textSecondary)
            .textAlign(TextAlign.Center)
            .maxLines(2)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: ThemeSpacing.lg, right: ThemeSpacing.lg })
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.store.playlists, (option: TrackPlaylistOption, index: number) => {
            ListItem() {
              this.PlaylistRow(option, index)
            }
          }, (option: TrackPlaylistOption): string =>
            `${option.id}|${option.trackCount}|${option.containsTrack}|${option.coverUrl}`)
        }
        .id('track-action-playlists')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .id(NativeUiIds.trackActionContent)
    .width('100%')
    .height('100%')
    .padding({ top: ThemeSpacing.sm })
  }

  /**
   * 批量模式的头部副标题：合集名 · N 首。外壳的副标题是纯文本，
   * 合集信息缺失时不硬编码多余文案，只用「已选择 N 首」兜底。
   */
  private subtitleText(): string {
    const count = this.store.selectedTracks.length;
    const context = this.store.contextTitle.trim();
    return context.length > 0 ? `${context} · ${count} 首` : `已选择 ${count} 首`;
  }

  private batchFavoriteOpacity(): number {
    if (this.store.isBusy()) {
      return this.store.busyAction === TrackActionBusyState.FavoriteBatch ? 1 : 0.55;
    }
    return this.store.favoriteCandidateCount > 0 ? 1 : 0.6;
  }

  /** 无封面时的首字块；空名歌单回落到音符，避免出现空白方块。 */
  private playlistInitial(name: string): string {
    const clean = name.trim();
    return clean.length > 0 ? clean.slice(0, 1) : '♪';
  }

  private playlistAddAccessibilityText(option: TrackPlaylistOption): Resource {
    if (option.containsTrack) {
      return $r('app.string.track_action_added_playlist');
    }
    if (this.store.busyPlaylistId === option.id) {
      return $r('app.string.track_action_adding');
    }
    return $r('app.string.track_action_add_playlist');
  }

  /**
   * 下载：曲目在收起抽屉前捕获，避免宿主动画结束后清空选择态。
   * 实际下载由宿主持有的 `DownloadStore` 执行，抽屉本身不等待网络。
   */
  private commitDownload(): void {
    if (this.store.isBusy()) {
      return;
    }
    const tracks: MobileTrack[] = this.store.isMulti() ? this.store.selectedTracks.slice() :
      (this.store.selectedTrack === null ? [] : [this.store.selectedTrack]);
    if (tracks.length === 0) {
      return;
    }
    this.onClose();
    this.onDownload(tracks);
  }

  /**
   * 收藏 / 取消收藏：先启动写入（同步捕获当前曲目），再立即收起抽屉，写入结果走底部 toast。
   * 先启动而不是先关闭，保证宿主在动画结束后清空 selectedTracks 也不影响这次 mutation。
   */
  private async commitFavorite(): Promise<void> {
    const notify = this.onToast;
    const wasFavorite = this.store.isFavorite;
    const pending = this.store.toggleFavorite();
    this.onClose();
    const outcome = await pending;
    if (outcome === TrackActionOutcome.Success) {
      notify(wasFavorite ? $r('app.string.track_action_favorite_removed') :
        $r('app.string.track_action_favorite_added'));
      return;
    }
    notify(this.toastMessage(this.store.feedback, outcome, false));
  }

  /** 批量「加入我喜欢的」：候选数在关闭前读取，关闭后仍按实际候选数提示。 */
  private async commitBatchFavorite(): Promise<void> {
    const notify = this.onToast;
    const candidates = this.store.favoriteCandidateCount;
    if (candidates === 0) {
      this.onClose();
      notify($r('app.string.track_action_favorite_batch_all'));
      return;
    }
    const pending = this.store.addSelectedToFavorites();
    this.onClose();
    const outcome = await pending;
    if (outcome === TrackActionOutcome.Success) {
      const feedback = this.store.feedback;
      const added = feedback === TrackActionFeedback.FavoriteBatchAdded && this.store.feedbackCount > 0 ?
        this.store.feedbackCount : candidates;
      notify(`已将 ${added} 首加入我喜欢的`);
      return;
    }
    notify(this.toastMessage(this.store.feedback, outcome, true));
  }

  /** 加入歌单：歌单名在关闭前捕获，成功后用「已添加到「歌单名」」提示。 */
  private async commitAddToPlaylist(option: TrackPlaylistOption): Promise<void> {
    const notify = this.onToast;
    const multi = this.store.isMulti();
    const pending = this.store.addToPlaylist(option.id);
    this.onClose();
    const outcome = await pending;
    if (outcome === TrackActionOutcome.Success) {
      notify(`已添加到「${option.name}」`);
      return;
    }
    notify(this.toastMessage(this.store.feedback, outcome, multi));
  }

  /**
   * 失败提示统一映射。抽屉已经收起时 store.close() 会清空 feedback，
   * 因此这里再用 TrackActionOutcome 兜底，保证任何失败都有可读文案。
   */
  private toastMessage(feedback: TrackActionFeedback, outcome: TrackActionOutcome,
    multi: boolean): ResourceStr {
    if (feedback === TrackActionFeedback.FavoriteBatchAdded) {
      if (this.store.feedbackCount > 0) {
        return `已将 ${this.store.feedbackCount} 首加入我喜欢的`;
      }
      return $r('app.string.track_action_favorite_batch_all');
    }
    if (feedback === TrackActionFeedback.PlaylistCreated) {
      if (multi && this.store.feedbackCount > 0) {
        return `已新建歌单并加入 ${this.store.feedbackCount} 首曲目`;
      }
      return $r('app.string.track_action_playlist_created');
    }
    if (feedback === TrackActionFeedback.Duplicate) {
      return multi ? '该歌单已包含全部所选曲目。' : $r('app.string.track_action_duplicate');
    }
    if (feedback === TrackActionFeedback.PlaylistNotFound) {
      return $r('app.string.track_action_playlist_missing');
    }
    if (feedback === TrackActionFeedback.InvalidName) {
      return $r('app.string.track_action_invalid_name');
    }
    if (feedback === TrackActionFeedback.WriteFailed) {
      return $r('app.string.track_action_write_failed');
    }
    if (feedback === TrackActionFeedback.Capacity) {
      return $r('app.string.track_action_capacity');
    }
    if (feedback === TrackActionFeedback.Busy) {
      return $r('app.string.track_action_busy');
    }
    if (feedback === TrackActionFeedback.FavoriteAdded) {
      return $r('app.string.track_action_favorite_added');
    }
    if (feedback === TrackActionFeedback.FavoriteRemoved) {
      return $r('app.string.track_action_favorite_removed');
    }
    if (feedback === TrackActionFeedback.Failed) {
      return $r('app.string.track_action_failed');
    }
    if (outcome === TrackActionOutcome.Duplicate) {
      return multi ? '该歌单已包含全部所选曲目。' : $r('app.string.track_action_duplicate');
    }
    if (outcome === TrackActionOutcome.PlaylistNotFound) {
      return $r('app.string.track_action_playlist_missing');
    }
    if (outcome === TrackActionOutcome.InvalidName) {
      return $r('app.string.track_action_invalid_name');
    }
    if (outcome === TrackActionOutcome.Busy) {
      return $r('app.string.track_action_busy');
    }
    return $r('app.string.track_action_failed');
  }
}
