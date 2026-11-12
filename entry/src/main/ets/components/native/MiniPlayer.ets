import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { AppIcon, AppIconKind } from './AppIcon';
import { PlayerStore } from '../../state/PlayerStore';
import { NativeUiIds } from './NativeUiIds';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import {
  playbackErrorMessage,
  playbackErrorPresentation,
  PlaybackErrorKind
} from '../../util/PlaybackErrorPresentation';
import {
  CoverImage,
  CoverImageProvider,
  EMPTY_COVER_PROVIDER
} from './CoverImage';
import { RuntimeCoverImageProvider } from './RuntimeCoverImageProvider';

/** 新 dock 实测：胶囊 56 高、封面 40、操作 32、左右内边距 12/8。 */
const MINI_PLAYER_HEIGHT: number = 56;
const MINI_PLAYER_PADDING_LEFT: number = 12;
const MINI_PLAYER_PADDING_RIGHT: number = 8;
const MINI_PLAYER_PADDING_VERTICAL: number = 8;
const MINI_PLAYER_COVER_SIZE: number = 40;
const MINI_PLAYER_ACTION_SIZE: number = 32;
const MINI_PLAYER_ICON_SIZE: number = 16;
const MINI_PLAYER_ERROR_ICON_SIZE: number = 20;
const MINI_PLAYER_RADIUS: number = MINI_PLAYER_HEIGHT / 2;
const MINI_PLAYER_SHADOW_RADIUS: number = 24;
const MINI_PLAYER_SHADOW_OFFSET_Y: number = 10;

/**
 * 悬浮 dock 右侧的迷你播放器胶囊。
 *
 * 与旧版（整宽 64 高、带进度条、右侧展开箭头）的区别：变成 56 高的圆角胶囊，
 * 封面 40 作为展开入口，右侧是暂停/播放与下一首；进度只在播放页展示。
 * 错误态保留：警告图标 + 错误文案 + 曲目上下文 + 重试，文案区域仍可点开播放页。
 */
@Component
export struct MiniPlayer {
  @ObjectLink store: PlayerStore;
  runtime: NativeAppRuntime | null = null;
  onExpand: () => void = (): void => {};

  @State private commandBusy: boolean = false;
  private coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;

  aboutToAppear(): void {
    if (this.runtime !== null) {
      this.coverProvider = new RuntimeCoverImageProvider(this.runtime);
    }
  }

  build() {
    Column() {
      if (this.store.error !== null) {
        this.ErrorContent()
      } else {
        this.TrackContent()
      }
    }
    .id(NativeUiIds.miniPlayer)
    .width('100%')
    .height(MINI_PLAYER_HEIGHT)
    .padding({
      left: MINI_PLAYER_PADDING_LEFT,
      right: MINI_PLAYER_PADDING_RIGHT,
      top: MINI_PLAYER_PADDING_VERTICAL,
      bottom: MINI_PLAYER_PADDING_VERTICAL
    })
    .backgroundColor(ThemeColors.surface)
    .border({ width: 1, color: ThemeColors.line })
    .borderRadius(MINI_PLAYER_RADIUS)
    .shadow({
      radius: MINI_PLAYER_SHADOW_RADIUS,
      color: ThemeColors.dockShadow,
      offsetX: 0,
      offsetY: MINI_PLAYER_SHADOW_OFFSET_Y
    })
  }

  @Builder
  TrackContent() {
    Row({ space: ThemeSpacing.sm }) {
      Stack() {
        if (this.currentCoverUrl().length > 0) {
          CoverImage({
            imageCache: this.coverProvider,
            coverUrl: this.currentCoverUrl(),
            coverSize: MINI_PLAYER_COVER_SIZE,
            cornerRadius: ThemeRadius.md
          })
        } else {
          Text('♪')
            .fontSize(18)
            .lineHeight(20)
            .fontColor(ThemeColors.iconOnInset)
        }
      }
      .id(NativeUiIds.miniPlayerExpand)
      .width(MINI_PLAYER_COVER_SIZE)
      .height(MINI_PLAYER_COVER_SIZE)
      .backgroundColor(ThemeColors.surfaceInset)
      .borderRadius(ThemeRadius.md)
      .clip(true)
      .alignContent(Alignment.Center)
      .onClick(() => {
        this.onExpand();
      })
      .accessibilityText($r('app.string.mini_player_expand'))

      Column({ space: 1 }) {
        Text(this.displayTitle())
          .id(NativeUiIds.miniPlayerTitle)
          .width('100%')
          .fontSize(ThemeTypography.miniPlayerTitle)
          .lineHeight(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.displayArtist())
          .id(NativeUiIds.miniPlayerArtist)
          .width('100%')
          .fontSize(ThemeTypography.miniPlayerMeta)
          .lineHeight(15)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.onExpand();
      })
      .accessibilityText($r('app.string.mini_player_expand'))

      Row() {
        this.PlaybackButton()

        Button({ type: ButtonType.Circle, stateEffect: false }) {
          AppIcon({
            iconKind: AppIconKind.Next,
            iconSize: MINI_PLAYER_ICON_SIZE,
            iconColor: ThemeColors.textPrimary
          })
        }
        .id(NativeUiIds.miniPlayerNext)
        .width(MINI_PLAYER_ACTION_SIZE)
        .height(MINI_PLAYER_ACTION_SIZE)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .enabled(!this.commandBusy)
        .opacity(this.commandBusy ? 0.65 : 1)
        .onClick(() => {
          void this.playNext();
        })
        .accessibilityText($r('app.string.player_next'))
      }
      .flexShrink(0)
    }
    .width('100%')
    .height(MINI_PLAYER_COVER_SIZE)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  PlaybackButton() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      if (this.store.snapshot.status === 'loading' || this.commandBusy) {
        LoadingProgress()
          .width(MINI_PLAYER_ICON_SIZE)
          .height(MINI_PLAYER_ICON_SIZE)
          .color(ThemeColors.textPrimary)
      } else if (this.store.snapshot.status === 'playing') {
        AppIcon({
          iconKind: AppIconKind.Pause,
          iconSize: MINI_PLAYER_ICON_SIZE,
          iconColor: ThemeColors.textPrimary
        })
      } else {
        AppIcon({
          iconKind: AppIconKind.Play,
          iconSize: MINI_PLAYER_ICON_SIZE,
          iconColor: ThemeColors.textPrimary
        })
      }
    }
    .id(NativeUiIds.miniPlayerToggle)
    .width(MINI_PLAYER_ACTION_SIZE)
    .height(MINI_PLAYER_ACTION_SIZE)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.commandBusy && this.store.snapshot.status !== 'loading')
    .opacity(this.commandBusy ? 0.65 : 1)
    .onClick(() => {
      void this.togglePlayback();
    })
    .accessibilityText(this.store.snapshot.status === 'playing' ?
      $r('app.string.mini_player_pause') : $r('app.string.mini_player_play'))
  }

  @Builder
  ErrorContent() {
    Row({ space: ThemeSpacing.sm }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(MINI_PLAYER_ERROR_ICON_SIZE)
        .fontColor([ThemeColors.textSecondary])

      Column({ space: 1 }) {
        Text(this.errorMessage())
          .id(NativeUiIds.miniPlayerError)
          .width('100%')
          .fontSize(ThemeTypography.miniPlayerTitle)
          .lineHeight(18)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.trackContext())
          .id(NativeUiIds.miniPlayerErrorTrack)
          .width('100%')
          .fontSize(ThemeTypography.miniPlayerMeta)
          .lineHeight(15)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.onExpand();
      })
      .accessibilityText($r('app.string.mini_player_expand'))
      .id(NativeUiIds.miniPlayerExpand)

      if (this.canRetryPlayback() || this.store.retryLoading) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          if (this.store.retryLoading) {
            LoadingProgress()
              .width(MINI_PLAYER_ICON_SIZE)
              .height(MINI_PLAYER_ICON_SIZE)
              .color(ThemeColors.textPrimary)
          } else {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(MINI_PLAYER_ICON_SIZE)
              .fontColor([ThemeColors.textPrimary])
          }
        }
        .id(NativeUiIds.miniPlayerRetry)
        .width(MINI_PLAYER_ACTION_SIZE)
        .height(MINI_PLAYER_ACTION_SIZE)
        .padding(0)
        .backgroundColor(ThemeColors.accentSoft)
        .enabled(this.canRetryPlayback())
        .opacity(this.store.retryLoading ? 0.7 : 1)
        .onClick(() => {
          void this.retryPlayback();
        })
        .accessibilityText(this.store.retryLoading ?
          $r('app.string.playback_error_retrying') : $r('app.string.playback_error_retry'))
      }
    }
    .width('100%')
    .height(MINI_PLAYER_COVER_SIZE)
    .alignItems(VerticalAlign.Center)
  }

  private async togglePlayback(): Promise<void> {
    if (this.commandBusy || this.store.snapshot.status === 'loading') {
      return;
    }
    this.commandBusy = true;
    try {
      if (this.store.snapshot.status === 'playing') {
        await this.store.pause();
      } else {
        await this.store.play();
      }
    } catch (error) {
      // PlayerStore publishes the sanitized error state rendered by this component.
    } finally {
      this.commandBusy = false;
    }
  }

  private async playNext(): Promise<void> {
    if (this.commandBusy) {
      return;
    }
    this.commandBusy = true;
    try {
      await this.store.next();
    } catch (error) {
      // Playback failures remain owned by PlayerStore.
    } finally {
      this.commandBusy = false;
    }
  }

  private async retryPlayback(): Promise<void> {
    if (!this.canRetryPlayback()) {
      return;
    }
    await this.store.retryPlayback();
  }

  private canRetryPlayback(): boolean {
    return this.store.error !== null && this.store.snapshot.track !== null &&
      !this.store.retryLoading &&
      playbackErrorPresentation(this.store.error).retryable;
  }

  private errorKind(): PlaybackErrorKind {
    return playbackErrorPresentation(this.store.error).kind;
  }

  private errorMessage(): ResourceStr {
    return playbackErrorMessage(this.errorKind());
  }

  private trackContext(): string {
    return `${this.displayTitle()} · ${this.displayArtist()}`;
  }

  private currentCoverUrl(): string {
    const track = this.store.snapshot.track;
    return track === null ? '' : track.coverUrl.trim();
  }

  private displayTitle(): string {
    const track = this.store.snapshot.track;
    if (track === null || track.title.trim().length === 0) {
      return '未知曲目';
    }
    return track.title;
  }

  private displayArtist(): string {
    const track = this.store.snapshot.track;
    if (track === null || track.artist.trim().length === 0) {
      return '未知作者';
    }
    return track.artist;
  }
}