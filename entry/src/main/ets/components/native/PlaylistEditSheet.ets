import { common } from '@kit.AbilityKit';
import {
  PLAYLIST_DESCRIPTION_MAX_LENGTH,
  PLAYLIST_NAME_MAX_LENGTH,
  PlaylistActionResult,
  PlaylistStore
} from '../../state/PlaylistStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { AppIcon, AppIconKind } from './AppIcon';
import { BottomSheet } from './BottomSheet';
import { NativeUiIds } from './NativeUiIds';
import { CoverPickResult, CoverPickStatus, PlaylistCoverDraft } from './PlaylistCoverDraft';
import { SheetSize } from './SheetSizing';

/**
 * 几何口径（design/playlist-create-sheet.html 的宽松方案）：
 * 封面 88 居中、右下 24 相机徽标；名称 / 简介都是无标签输入框，计数压在右下角。
 */
const COVER_SIZE: number = 88;
const COVER_RADIUS: number = ThemeRadius.card;
const COVER_ICON: number = 22;
const COVER_BADGE_SIZE: number = 24;
const COVER_BADGE_ICON: number = 13;
const COVER_BADGE_INSET: number = 5;

const FIELD_HEIGHT: number = 52;
const DESCRIPTION_HEIGHT: number = 104;
const FIELD_RADIUS: number = ThemeRadius.control;
const FIELD_PADDING_LEFT: number = 13;
const FIELD_PADDING_RIGHT: number = 52;
const NAME_PADDING_TOP: number = 6;
const NAME_PADDING_BOTTOM: number = 18;
const DESCRIPTION_PADDING_TOP: number = 11;
const DESCRIPTION_PADDING_BOTTOM: number = 26;
const COUNTER_SIZE: number = 11;
const COUNTER_RIGHT: number = 12;
const COUNTER_BOTTOM: number = 7;
const COUNTER_NEAR_RATIO: number = 0.9;

const SUBMIT_HEIGHT: number = 46;
/** 头部下方留白 8，字段之间 16，字段与底部按钮之间 12（稿件 sheet__body / sheet__scroll / sheet__footer）。 */
const BODY_TOP: number = ThemeSpacing.sm;
const FIELD_GAP: number = ThemeSpacing.lg;
const FOOTER_TOP: number = ThemeSpacing.md;
const DISABLED_OPACITY: number = 0.42;

const EDIT_ERROR_EMPTY: string = 'empty';
const EDIT_ERROR_TOO_LONG: string = 'tooLong';
const EDIT_ERROR_BUSY: string = 'busy';
const EDIT_ERROR_COVER: string = 'cover';
const EDIT_ERROR_NOT_FOUND: string = 'notFound';
const EDIT_ERROR_FAILED: string = 'failed';

/**
 * 「编辑歌单」抽屉（歌单详情页右上角入口）。
 *
 * 外壳复用全仓统一的 `BottomSheet`（蒙层 / 拖拽条 / 标题 / 右上关闭 / 安全区），高度走标准中档。
 * 内容按 design/playlist-create-sheet.html 的编辑态重做：居中封面（点按更换）+ 无标签名称 /
 * 简介输入（计数内嵌右下角）+ 底部「保存修改」。
 *
 * 抽屉挂在根 Stack 上（见 `Index`），这样 `BottomSheet` 的 `expandSafeArea` 不会被
 * `NavDestination` 裁掉。
 */
@Component
export struct PlaylistEditSheet {
  @ObjectLink store: PlaylistStore;
  playlistId: string = '';
  onClose: () => void = (): void => {};
  /** 宿主驱动的滑入 / 滑出位移（vp）：挂载前等于屏高，宿主动画回 0。 */
  @Prop panelOffsetY: number = 0;
  /** 宿主驱动的蒙层不透明度（0–1），与位移同步淡入淡出。 */
  @Prop scrimAlpha: number = 1;

  @State private draftName: string = '';
  @State private draftDescription: string = '';
  @State private coverUri: string = '';
  @State private coverBusy: boolean = false;
  @State private submitting: boolean = false;
  @State private nameFocused: boolean = false;
  @State private descriptionFocused: boolean = false;
  @State private errorCode: string = '';
  private coverDraft: PlaylistCoverDraft = new PlaylistCoverDraft();
  private destroyed: boolean = false;

  aboutToAppear(): void {
    const playlist = this.store.playlistById(this.playlistId);
    if (playlist === null) {
      this.errorCode = EDIT_ERROR_NOT_FOUND;
      return;
    }
    this.draftName = playlist.name;
    this.draftDescription = playlist.description;
    this.coverUri = playlist.coverUri;
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    // 保存请求进行中时保留即将入库的封面；失败清理由 submit() 收尾。
    // dispose() 会同步删临时文件（fs.unlinkSync），不能放在销毁流程里。
    const coverDraft = this.coverDraft;
    const keepPending = this.submitting;
    setTimeout((): void => {
      coverDraft.dispose(keepPending);
    }, 0);
  }

  @Builder
  CoverField() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.coverUri.length > 0) {
          Image(this.coverUri)
            .width(COVER_SIZE)
            .height(COVER_SIZE)
            .objectFit(ImageFit.Cover)
            .borderRadius(COVER_RADIUS)
            .draggable(false)
        } else {
          Column({ space: ThemeSpacing.xs }) {
            AppIcon({
              iconKind: AppIconKind.CreatePlaylist,
              iconSize: COVER_ICON,
              iconColor: ThemeColors.textSecondary
            })
            Text($r('app.string.playlist_create_cover_add'))
              .fontSize(ThemeTypography.meta)
              .lineHeight(16)
              .fontColor(ThemeColors.textSecondary)
              .maxLines(1)
          }
          .width(COVER_SIZE)
          .height(COVER_SIZE)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(ThemeColors.surfaceInset)
          .borderRadius(COVER_RADIUS)
        }

        if (this.coverUri.length > 0 && !this.coverBusy) {
          Stack({ alignContent: Alignment.Center }) {
            // 徽标底在深浅两套主题下都是半透明黑，图标因此取模式无关的浅色（与启动页同角色），
            // 不能用会随主题翻转的 `onAccent`。
            AppIcon({
              iconKind: AppIconKind.Camera,
              iconSize: COVER_BADGE_ICON,
              iconColor: ThemeColors.onSplash
            })
          }
          .width(COVER_BADGE_SIZE)
          .height(COVER_BADGE_SIZE)
          .borderRadius(COVER_BADGE_SIZE / 2)
          .backgroundColor(ThemeColors.scrim)
          .margin({ right: COVER_BADGE_INSET, bottom: COVER_BADGE_INSET })
        }

        if (this.coverBusy) {
          Column() {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(ThemeColors.textPrimary)
          }
          .width(COVER_SIZE)
          .height(COVER_SIZE)
          .backgroundColor(ThemeColors.scrim)
          .borderRadius(COVER_RADIUS)
          .justifyContent(FlexAlign.Center)
        }
      }
      .id(NativeUiIds.playlistEditCover)
      .width(COVER_SIZE)
      .height(COVER_SIZE)
      .borderRadius(COVER_RADIUS)
      .clip(true)
      .enabled(!this.submitting && !this.coverBusy)
      .onClick(() => {
        void this.pickCover();
      })
      .accessibilityText(this.coverUri.length > 0 ?
        $r('app.string.playlist_create_cover_change') : $r('app.string.playlist_create_cover_add'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  NameField() {
    // 底色与焦点描边画在外层 Stack 上，输入框自己保持透明：描边写在 TextInput 上时，
    // 聚焦后左侧那一条会整段丢失（输入框内部绘制不跟手），交给普通容器绘制才稳定。
    Stack({ alignContent: Alignment.BottomEnd }) {
      TextInput({
        text: this.draftName,
        placeholder: $r('app.string.playlist_create_name_placeholder')
      })
        .id(NativeUiIds.playlistEditNameInput)
        .width('100%')
        .height(FIELD_HEIGHT)
        .fontSize(ThemeTypography.caption)
        .fontColor(ThemeColors.textPrimary)
        .placeholderColor(ThemeColors.textSecondary)
        .placeholderFont({ size: ThemeTypography.eyebrow })
        .backgroundColor(Color.Transparent)
        // 圆角留在外层容器；输入框自己取 0，避免圆角裁掉光标。
        .borderRadius(0)
        .padding({
          left: FIELD_PADDING_LEFT,
          right: FIELD_PADDING_RIGHT,
          top: NAME_PADDING_TOP,
          bottom: NAME_PADDING_BOTTOM
        })
        .caretColor(ThemeColors.accent)
        .maxLength(PLAYLIST_NAME_MAX_LENGTH)
        .enabled(!this.submitting)
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string): void => {
          this.draftName = value;
          this.clearNameError();
        })
        .onFocus(() => {
          this.nameFocused = true;
        })
        .onBlur(() => {
          this.nameFocused = false;
        })

      Text(`${this.draftName.length}/${PLAYLIST_NAME_MAX_LENGTH}`)
        .fontSize(COUNTER_SIZE)
        .fontColor(this.nameCounterNearLimit() ? ThemeColors.accent : ThemeColors.textSecondary)
        .maxLines(1)
        .margin({ right: COUNTER_RIGHT, bottom: COUNTER_BOTTOM })
        // 计数只是一层提示，不能挡住输入框的点击 / 光标定位。
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(FIELD_HEIGHT)
    .backgroundColor(this.nameFocused ? ThemeColors.surface : ThemeColors.surfaceInset)
    .borderRadius(FIELD_RADIUS)
    // 两种状态都用颜色资源（不用 Color.Transparent），避免资源 / 枚举混用时的重绘异常；
    // 未聚焦时描边与底色同色，视觉上等于没有描边。
    .border({
      width: 1,
      color: this.nameFocused ? ThemeColors.accent : ThemeColors.surfaceInset
    })
  }

  @Builder
  DescriptionField() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      TextArea({
        text: this.draftDescription,
        placeholder: $r('app.string.playlist_create_description_placeholder')
      })
        .id(NativeUiIds.playlistEditDescriptionInput)
        .width('100%')
        .height(DESCRIPTION_HEIGHT)
        .fontSize(ThemeTypography.caption)
        .lineHeight(20)
        .fontColor(ThemeColors.textPrimary)
        .placeholderColor(ThemeColors.textSecondary)
        .placeholderFont({ size: ThemeTypography.eyebrow })
        .backgroundColor(Color.Transparent)
        // 圆角留在外层容器；输入框自己取 0，避免圆角裁掉光标。
        .borderRadius(0)
        .padding({
          left: FIELD_PADDING_LEFT,
          right: FIELD_PADDING_RIGHT,
          top: DESCRIPTION_PADDING_TOP,
          bottom: DESCRIPTION_PADDING_BOTTOM
        })
        .caretColor(ThemeColors.accent)
        .maxLength(PLAYLIST_DESCRIPTION_MAX_LENGTH)
        .enabled(!this.submitting)
        .onChange((value: string): void => {
          this.draftDescription = value;
        })
        .onFocus(() => {
          this.descriptionFocused = true;
        })
        .onBlur(() => {
          this.descriptionFocused = false;
        })

      Text(`${this.draftDescription.length}/${PLAYLIST_DESCRIPTION_MAX_LENGTH}`)
        .fontSize(COUNTER_SIZE)
        .fontColor(this.descriptionCounterNearLimit() ?
          ThemeColors.accent : ThemeColors.textSecondary)
        .maxLines(1)
        .margin({ right: COUNTER_RIGHT, bottom: COUNTER_BOTTOM })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(DESCRIPTION_HEIGHT)
    .backgroundColor(this.descriptionFocused ? ThemeColors.surface : ThemeColors.surfaceInset)
    .borderRadius(FIELD_RADIUS)
    // 两种状态都用颜色资源（不用 Color.Transparent），避免资源 / 枚举混用时的重绘异常；
    // 未聚焦时描边与底色同色，视觉上等于没有描边。
    .border({
      width: 1,
      color: this.descriptionFocused ? ThemeColors.accent : ThemeColors.surfaceInset
    })
  }

  @Builder
  ErrorLine() {
    if (this.errorCode.length > 0) {
      Text(this.errorMessage())
        .id(NativeUiIds.playlistEditError)
        .width('100%')
        .fontSize(ThemeTypography.meta)
        .lineHeight(18)
        .fontColor(ThemeColors.accent)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  SheetContent() {
    Column({ space: FOOTER_TOP }) {
      Scroll() {
        Column({ space: FIELD_GAP }) {
          this.CoverField()
          this.NameField()
          this.DescriptionField()
          this.ErrorLine()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Button(this.submitting ? $r('app.string.playlist_edit_saving') :
        $r('app.string.playlist_edit_save'), { stateEffect: false })
        .id(NativeUiIds.playlistEditSave)
        .width('100%')
        .height(SUBMIT_HEIGHT)
        .fontSize(ThemeTypography.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.onAccent)
        .backgroundColor(ThemeColors.accent)
        .borderRadius(FIELD_RADIUS)
        .enabled(this.canSubmit())
        .opacity(this.canSubmit() ? 1 : DISABLED_OPACITY)
        .onClick(() => {
          void this.submit();
        })
    }
    .id(NativeUiIds.playlistEditSheet + '-content')
    .width('100%')
    .height('100%')
    .padding({ top: BODY_TOP })
  }

  build() {
    BottomSheet({
      sheetId: NativeUiIds.playlistEditSheet,
      title: $r('app.string.playlist_edit_title'),
      sheetSize: SheetSize.Medium,
      panelOffsetY: this.panelOffsetY,
      scrimAlpha: this.scrimAlpha,
      onClose: this.onClose
    }) {
      this.SheetContent()
    }
  }

  private nameCounterNearLimit(): boolean {
    return this.draftName.length >= Math.floor(PLAYLIST_NAME_MAX_LENGTH * COUNTER_NEAR_RATIO);
  }

  private descriptionCounterNearLimit(): boolean {
    return this.draftDescription.length >=
      Math.floor(PLAYLIST_DESCRIPTION_MAX_LENGTH * COUNTER_NEAR_RATIO);
  }

  private canSubmit(): boolean {
    return !this.submitting && !this.coverBusy && !this.store.isBusy() &&
      this.draftName.trim().length > 0 && this.errorCode !== EDIT_ERROR_NOT_FOUND;
  }

  private async submit(): Promise<void> {
    if (this.submitting || this.coverBusy || this.store.isBusy()) {
      return;
    }
    const name = this.draftName.trim();
    if (name.length === 0) {
      this.errorCode = EDIT_ERROR_EMPTY;
      return;
    }
    if (name.length > PLAYLIST_NAME_MAX_LENGTH) {
      this.errorCode = EDIT_ERROR_TOO_LONG;
      return;
    }
    this.submitting = true;
    this.errorCode = '';
    let saved = false;
    try {
      const result = await this.store.update(this.playlistId, name, this.coverUri, this.draftDescription);
      if (result === PlaylistActionResult.Success) {
        saved = true;
        this.coverDraft.commit();
        if (!this.destroyed) {
          this.onClose();
        }
        return;
      }
      if (!this.destroyed) {
        this.errorCode = this.resultErrorCode(result);
      }
    } finally {
      if (!this.destroyed) {
        this.submitting = false;
      } else if (!saved) {
        this.coverDraft.discard();
      }
    }
  }

  private async pickCover(): Promise<void> {
    if (this.coverBusy || this.submitting || this.errorCode === EDIT_ERROR_NOT_FOUND) {
      return;
    }
    this.coverBusy = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      const result: CoverPickResult = await this.coverDraft.pick(context);
      if (this.destroyed) {
        return;
      }
      if (result.status === CoverPickStatus.Picked) {
        this.coverUri = result.uri;
        if (this.errorCode === EDIT_ERROR_COVER || this.errorCode === EDIT_ERROR_FAILED) {
          this.errorCode = '';
        }
      } else if (result.status === CoverPickStatus.Failed) {
        this.errorCode = EDIT_ERROR_COVER;
      }
    } finally {
      if (!this.destroyed) {
        this.coverBusy = false;
      }
    }
  }

  private clearNameError(): void {
    if (this.errorCode === EDIT_ERROR_EMPTY || this.errorCode === EDIT_ERROR_TOO_LONG) {
      this.errorCode = '';
    }
  }

  private resultErrorCode(result: PlaylistActionResult): string {
    if (result === PlaylistActionResult.InvalidName) {
      return this.draftName.trim().length === 0 ? EDIT_ERROR_EMPTY : EDIT_ERROR_TOO_LONG;
    }
    if (result === PlaylistActionResult.Busy) {
      return EDIT_ERROR_BUSY;
    }
    if (result === PlaylistActionResult.NotFound) {
      return EDIT_ERROR_NOT_FOUND;
    }
    return EDIT_ERROR_FAILED;
  }

  private errorMessage(): ResourceStr {
    if (this.errorCode === EDIT_ERROR_EMPTY) {
      return $r('app.string.playlist_name_empty_error');
    }
    if (this.errorCode === EDIT_ERROR_TOO_LONG) {
      return $r('app.string.playlist_name_long_error');
    }
    if (this.errorCode === EDIT_ERROR_BUSY) {
      return $r('app.string.playlist_busy_error');
    }
    if (this.errorCode === EDIT_ERROR_NOT_FOUND) {
      return $r('app.string.playlist_not_found_error');
    }
    if (this.errorCode === EDIT_ERROR_COVER) {
      return $r('app.string.playlist_create_cover_failed');
    }
    return $r('app.string.playlist_save_error');
  }
}