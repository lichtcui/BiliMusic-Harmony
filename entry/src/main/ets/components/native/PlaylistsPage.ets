import {
  PLAYLIST_NAME_MAX_LENGTH,
  PlaylistActionResult,
  PlaylistStore,
  PlaylistSummary
} from '../../state/PlaylistStore';
import { PlayerStore } from '../../state/PlayerStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { CoverImage, CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { AppIcon, AppIconKind } from './AppIcon';
import {
  PlaylistPlaybackAction,
  resolvePlaylistPlaybackAction,
  sanitizeTrackCount
} from './MinePageState';
import { NativeUiIds } from './NativeUiIds';

/** 新稿实测：歌单行 60 高、封面 48、行内左右各留 4 的触摸外扩。 */
const PLAYLIST_ROW_HEIGHT: number = 60;
const PLAYLIST_COVER_SIZE: number = 48;
const PLAYLIST_ROW_INSET: number = 4;
const PLAYLIST_OUTER_GAP: number = 12;
const PLAYLIST_TEXT_GAP: number = 14;
/** 行尾播放键热区；设计稿 40，图标 16。 */
const PLAYLIST_PLAY_SIZE: number = 40;
const TRAILING_ICON_SIZE: number = 16;
const ROW_TEXT_GAP: number = 3;
const PLAYLIST_NAME_INPUT_MAX_LENGTH: number = 80;

const DIALOG_ERROR_EMPTY: string = 'empty';
const DIALOG_ERROR_TOO_LONG: string = 'tooLong';
const DIALOG_ERROR_BUSY: string = 'busy';
const DIALOG_ERROR_NOT_FOUND: string = 'notFound';
const DIALOG_ERROR_FAILED: string = 'failed';

@CustomDialog
@Component
struct PlaylistNameDialog {
  @Link draftName: string;
  @Link errorCode: string;
  @Link submitting: boolean;
  controller?: CustomDialogController;
  onConfirm: () => void = (): void => {};
  onCancel: () => void = (): void => {};

  build() {
    Column({ space: ThemeSpacing.md }) {
      Text($r('app.string.playlist_name_rename_title'))
        .width('100%')
        .fontSize(ThemeTypography.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      TextInput({
        text: this.draftName,
        placeholder: $r('app.string.playlist_name_placeholder')
      })
        .id(NativeUiIds.playlistNameInput)
        .width('100%')
        .height(44)
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textPrimary)
        .placeholderColor(ThemeColors.textSecondary)
        .backgroundColor(ThemeColors.surfaceInset)
        .borderRadius(ThemeRadius.md)
        .padding({ left: ThemeSpacing.md, right: ThemeSpacing.md })
        .maxLength(PLAYLIST_NAME_INPUT_MAX_LENGTH)
        .enabled(!this.submitting)
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string): void => {
          this.draftName = value;
          this.errorCode = '';
        })
        .onSubmit((_enterKey: EnterKeyType): void => {
          this.onConfirm();
        })

      Text($r('app.string.playlist_name_limit'))
        .width('100%')
        .fontSize(ThemeTypography.eyebrow)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(2)

      if (this.errorCode.length > 0) {
        Text(this.errorMessage())
          .id(NativeUiIds.playlistNameError)
          .width('100%')
          .fontSize(ThemeTypography.caption)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Row({ space: ThemeSpacing.sm }) {
        Button($r('app.string.playlist_cancel'), { stateEffect: false })
          .id(NativeUiIds.playlistNameCancel)
          .layoutWeight(1)
          .height(ThemeSize.routeButtonHeight)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .backgroundColor(ThemeColors.surfaceInset)
          .borderRadius(ThemeRadius.md)
          .enabled(!this.submitting)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onCancel();
          })

        Button(this.submitting ? $r('app.string.playlist_saving') :
          $r('app.string.playlist_save'), { stateEffect: false })
          .id(NativeUiIds.playlistNameConfirm)
          .layoutWeight(1)
          .height(ThemeSize.routeButtonHeight)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.onAccent)
          .backgroundColor(ThemeColors.accent)
          .borderRadius(ThemeRadius.md)
          .enabled(!this.submitting)
          .opacity(this.submitting ? 0.65 : 1)
          .onClick(() => {
            this.onConfirm();
          })
      }
      .width('100%')
    }
    .id(NativeUiIds.playlistNameDialog)
    .width('100%')
    .constraintSize({ maxWidth: 360 })
    .padding(ThemeSpacing.xl)
    .backgroundColor(ThemeColors.surface)
    .borderRadius(ThemeRadius.md)
  }

  private errorMessage(): ResourceStr {
    if (this.errorCode === DIALOG_ERROR_EMPTY) {
      return $r('app.string.playlist_name_empty_error');
    }
    if (this.errorCode === DIALOG_ERROR_TOO_LONG) {
      return $r('app.string.playlist_name_long_error');
    }
    if (this.errorCode === DIALOG_ERROR_BUSY) {
      return $r('app.string.playlist_busy_error');
    }
    if (this.errorCode === DIALOG_ERROR_NOT_FOUND) {
      return $r('app.string.playlist_not_found_error');
    }
    return $r('app.string.playlist_save_error');
  }
}

/**
 * 歌单行尾播放键。
 *
 * 它自己通过 `@ObjectLink` 订阅 `PlayerStore` / `PlaylistStore`，所以播放 / 暂停状态变化
 * 只重绘这颗按钮。旧实现把播放态拼进 `ForEach` 的 key，状态一变整行（含 `CoverImage`）
 * 就被销毁重建，封面要重新走一遍 Loading → 解码，视觉上就是封面闪一下。
 */
@Component
struct PlaylistPlayButton {
  @ObjectLink store: PlaylistStore;
  @ObjectLink playerStore: PlayerStore;
  @Prop trackCount: number = 0;
  @Prop trackKeys: string[] = [];
  @Prop rowIndex: number = 0;
  onToggle: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      AppIcon({
        iconKind: this.isPlaying() ? AppIconKind.Pause : AppIconKind.Play,
        iconSize: TRAILING_ICON_SIZE,
        iconColor: ThemeColors.textSecondary
      })
    }
    .id(NativeUiIds.minePlaylistPlay(this.rowIndex))
    .width(PLAYLIST_PLAY_SIZE)
    .height(PLAYLIST_PLAY_SIZE)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(this.canPlay())
    .opacity(this.canPlay() ? 1 : 0.35)
    .onClick(() => {
      this.onToggle();
    })
    .accessibilityText(this.isPlaying() ?
      $r('app.string.player_pause') : $r('app.string.mine_playlist_play'))
  }

  /** 空歌单或歌单操作进行中时禁用。 */
  private canPlay(): boolean {
    return !this.store.isBusy() && sanitizeTrackCount(this.trackCount) > 0;
  }

  /**
   * 只有「播放器队列 = 这个歌单」且正在播放时才显示暂停。
   * 队列快照来自 `PlayerStore`，歌单曲目顺序来自行摘要的 `trackKeys`。
   */
  private isPlaying(): boolean {
    return resolvePlaylistPlaybackAction(this.playerStore.snapshot.status,
      this.playerStore.snapshot.queue, this.trackKeys) === PlaylistPlaybackAction.Pause;
  }
}

/**
 * 「我的 · 歌单」段（设计稿 05/06）。页头、快捷方块与账号区在 `MinePage` 里，
 * 这里只负责歌单内容：歌单行（封面 + 首数 + 行尾播放）与错误条。
 * 「我喜欢的」已上移为快捷方块，不再重复渲染置顶行；「导入收藏夹」没有后端，入口同样隐藏。
 */
@Component
export struct PlaylistsPage {
  @ObjectLink store: PlaylistStore;
  @ObjectLink playerStore: PlayerStore;
  imageCache: CoverImageProvider = EMPTY_COVER_PROVIDER;
  onOpenPlaylist: (playlistId: string) => void = (_playlistId: string): void => {};
  onPlaylistDeleted: (playlistId: string) => void = (_playlistId: string): void => {};

  @State private dialogPlaylistId: string = '';
  @State private dialogDraftName: string = '';
  @State private dialogErrorCode: string = '';
  @State private dialogSubmitting: boolean = false;

  private nameDialogController: CustomDialogController | null = new CustomDialogController({
    builder: PlaylistNameDialog({
      draftName: $dialogDraftName,
      errorCode: $dialogErrorCode,
      submitting: $dialogSubmitting,
      onConfirm: (): void => {
        void this.submitNameDialog();
      },
      onCancel: (): void => {
        this.resetNameDialog();
      }
    }),
    cancel: (): void => {
      this.resetNameDialog();
    },
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: false,
    cornerRadius: ThemeRadius.md,
    keyboardAvoidMode: KeyboardAvoidMode.DEFAULT
  });

  @Builder
  PlaylistCover(playlist: PlaylistSummary, index: number) {
    Stack() {
      if (playlist.coverUrl.length > 0) {
        CoverImage({
          imageCache: this.imageCache,
          coverUrl: playlist.coverUrl,
          coverSize: PLAYLIST_COVER_SIZE,
          cornerRadius: ThemeRadius.tile
        })
      } else {
        Text('♪')
          .fontSize(20)
          .fontColor(ThemeColors.iconOnInset)
      }
    }
    .id(NativeUiIds.minePlaylistCover(index))
    .width(PLAYLIST_COVER_SIZE)
    .height(PLAYLIST_COVER_SIZE)
    .borderRadius(ThemeRadius.tile)
    .backgroundColor(ThemeColors.surfaceInset)
    .clip(true)
    .alignContent(Alignment.Center)
  }

  @Builder
  PlaylistRow(playlist: PlaylistSummary, index: number) {
    Row({ space: PLAYLIST_OUTER_GAP }) {
      Row({ space: PLAYLIST_TEXT_GAP }) {
        this.PlaylistCover(playlist, index)

        Column({ space: ROW_TEXT_GAP }) {
          Text(playlist.name)
            .width('100%')
            .fontSize(ThemeTypography.body)
            .lineHeight(21)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: ThemeSpacing.xs }) {
            Text(sanitizeTrackCount(playlist.trackCount).toString())
              .fontSize(ThemeTypography.meta)
              .lineHeight(17)
              .fontColor(ThemeColors.textSecondary)
            Text($r('app.string.playlist_track_suffix'))
              .fontSize(ThemeTypography.meta)
              .lineHeight(17)
              .fontColor(ThemeColors.textSecondary)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.store.selectPlaylist(playlist.id)) {
          this.onOpenPlaylist(playlist.id);
        }
      })
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.openPlaylistActions(playlist);
          })
      )

      /* 行尾播放键：播放 / 暂停该歌单；空歌单或歌单操作进行中时禁用。 */
      PlaylistPlayButton({
        store: this.store,
        playerStore: this.playerStore,
        trackCount: playlist.trackCount,
        trackKeys: playlist.trackKeys,
        rowIndex: index,
        onToggle: (): void => {
          void this.togglePlaylistPlayback(playlist);
        }
      })
    }
    .id(NativeUiIds.playlistRow(index))
    .width('100%')
    .height(PLAYLIST_ROW_HEIGHT)
    .padding({ left: PLAYLIST_ROW_INSET, right: 0 })
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ErrorBanner() {
    Row({ space: ThemeSpacing.sm }) {
      Text($r('app.string.playlist_error'))
        .layoutWeight(1)
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button($r('app.string.playlist_error_dismiss'), { stateEffect: false })
        .id(NativeUiIds.playlistErrorDismiss)
        .height(32)
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.accent)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.store.clearError();
        })
    }
    .id(NativeUiIds.playlistError)
    .width('100%')
    .padding({ left: ThemeSpacing.md, right: ThemeSpacing.xs, top: ThemeSpacing.xs, bottom: ThemeSpacing.xs })
    .backgroundColor(ThemeColors.surfaceInset)
    .borderRadius(ThemeRadius.sm)
  }

  build() {
    Column() {
      if (this.store.error !== null) {
        this.ErrorBanner()
      }

      List({ space: 0 }) {
        ForEach(this.store.playlists, (playlist: PlaylistSummary, index: number) => {
          ListItem() {
            this.PlaylistRow(playlist, index)
          }
        }, (playlist: PlaylistSummary): string => playlistRowKey(playlist))
      }
      .id(NativeUiIds.playlistList)
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: ThemeSpacing.gutter,
        right: ThemeSpacing.gutter,
        top: ThemeSpacing.xl,
        bottom: ThemeSpacing.lg
      })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bg)
  }

  private async togglePlaylistPlayback(playlist: PlaylistSummary): Promise<void> {
    if (playlist.trackKeys.length === 0 || this.store.isBusy()) {
      return;
    }
    const action = resolvePlaylistPlaybackAction(this.playerStore.snapshot.status,
      this.playerStore.snapshot.queue, playlist.trackKeys);
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
    await this.store.playAll(playlist.id);
  }

  /** 行尾长按：重命名 / 删除 / 取消。 */
  private openPlaylistActions(playlist: PlaylistSummary): void {
    if (this.store.isBusy()) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.mine_playlist_actions_title'),
      message: playlist.name,
      autoCancel: true,
      buttons: [
        {
          value: $r('app.string.playlist_rename'),
          action: (): void => {
            this.openRenameDialog(playlist);
          }
        },
        {
          value: $r('app.string.playlist_delete'),
          action: (): void => {
            this.confirmDelete(playlist);
          }
        },
        {
          value: $r('app.string.playlist_cancel'),
          action: (): void => {
          }
        }
      ]
    });
  }

  private openRenameDialog(playlist: PlaylistSummary): void {
    if (this.store.isBusy()) {
      return;
    }
    this.prepareNameDialog(playlist.id, playlist.name);
  }

  private prepareNameDialog(playlistId: string, name: string): void {
    this.dialogPlaylistId = playlistId;
    this.dialogDraftName = name;
    this.dialogErrorCode = '';
    this.dialogSubmitting = false;
    if (this.nameDialogController !== null) {
      this.nameDialogController.open();
    }
  }

  private async submitNameDialog(): Promise<void> {
    if (this.dialogSubmitting || this.store.isBusy()) {
      return;
    }
    const name = this.dialogDraftName.trim();
    if (name.length === 0) {
      this.dialogErrorCode = DIALOG_ERROR_EMPTY;
      return;
    }
    if (name.length > PLAYLIST_NAME_MAX_LENGTH) {
      this.dialogErrorCode = DIALOG_ERROR_TOO_LONG;
      return;
    }
    this.dialogSubmitting = true;
    this.dialogErrorCode = '';
    try {
      const result = await this.store.rename(this.dialogPlaylistId, name);
      if (result === PlaylistActionResult.Success) {
        this.closeNameDialog();
      } else {
        this.dialogErrorCode = dialogErrorCode(result, name);
      }
    } finally {
      this.dialogSubmitting = false;
    }
  }

  private closeNameDialog(): void {
    if (this.nameDialogController !== null) {
      this.nameDialogController.close();
    }
    this.resetNameDialog();
  }

  private resetNameDialog(): void {
    this.dialogPlaylistId = '';
    this.dialogDraftName = '';
    this.dialogErrorCode = '';
    this.dialogSubmitting = false;
  }

  private confirmDelete(playlist: PlaylistSummary): void {
    if (this.store.isBusy()) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.playlist_delete_title'),
      message: $r('app.string.playlist_delete_message'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.playlist_cancel'),
        defaultFocus: true,
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.playlist_delete_confirm'),
        action: (): void => {
          void this.deletePlaylist(playlist.id);
        }
      }
    });
  }

  private async deletePlaylist(playlistId: string): Promise<void> {
    const result = await this.store.delete(playlistId);
    if (result === PlaylistActionResult.Success) {
      this.onPlaylistDeleted(playlistId);
    }
  }
}

function dialogErrorCode(result: PlaylistActionResult, name: string): string {
  if (result === PlaylistActionResult.InvalidName) {
    return name.length === 0 ? DIALOG_ERROR_EMPTY : DIALOG_ERROR_TOO_LONG;
  }
  if (result === PlaylistActionResult.Busy) {
    return DIALOG_ERROR_BUSY;
  }
  if (result === PlaylistActionResult.NotFound) {
    return DIALOG_ERROR_NOT_FOUND;
  }
  return DIALOG_ERROR_FAILED;
}

/**
 * ArkUI 的 `ForEach` 在 key 不变时复用旧行、不会重新执行 item builder。
 * 歌单行显示的名称 / 首数 / 封面都来自纯对象摘要，key 必须把这几个字段也带上，
 * 否则「加入歌单后首数仍是 0」「重命名后仍是旧名字」这类 stale row 会一直在。
 * key 里**不要**再拼播放 / 暂停状态：那会让播放态一变就整行重建、`CoverImage`
 * 重新加载，封面闪烁。行尾播放键由 `PlaylistPlayButton` 自己订阅 store 更新。
 */
function playlistRowKey(playlist: PlaylistSummary): string {
  return `${playlist.id}|${playlist.name}|${playlist.trackCount}|${playlist.coverUrl}|${playlist.updatedAt}`;
}
