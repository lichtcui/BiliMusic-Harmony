import {
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
import { BottomSheet } from './BottomSheet';
import { NativeUiIds } from './NativeUiIds';
import { SheetSize } from './SheetSizing';

/**
 * 输入框几何（design/playlist-create-sheet.html 的 `.text-input` 实测）：
 * 无标签，52 高、10 圆角，计数压在输入框右下角，右侧留够 52 不让长名称压到计数上。
 */
const FIELD_HEIGHT: number = 52;
const FIELD_RADIUS: number = ThemeRadius.control;
const FIELD_PADDING_LEFT: number = 13;
const FIELD_PADDING_RIGHT: number = 52;
const FIELD_PADDING_TOP: number = 6;
const FIELD_PADDING_BOTTOM: number = 18;
/** 计数 11、距右下 12 / 7；接近上限时换成 accent 提醒。 */
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

const CREATE_ERROR_EMPTY: string = 'empty';
const CREATE_ERROR_TOO_LONG: string = 'tooLong';
const CREATE_ERROR_BUSY: string = 'busy';
const CREATE_ERROR_FAILED: string = 'failed';

/**
 * 「新建歌单」抽屉（「我的」页 + 号）。
 *
 * 内容按 design/playlist-create-sheet.html 的宽松方案重做：只有一个无标签名称输入框，
 * 字数计数贴在输入框右下角，底部一个「创建」按钮；新建态不再放封面上传，
 * 封面留到「编辑歌单」抽屉里设置。外壳复用全仓共用的 `BottomSheet`，
 * 高度走标准档位（小档），不在这里写百分比或固定高度。
 */
@Component
export struct PlaylistCreateSheet {
  @ObjectLink store: PlaylistStore;
  onClose: () => void = (): void => {};
  /** 宿主驱动的滑入 / 滑出位移（vp）：挂载前等于屏高，宿主动画回 0。 */
  @Prop panelOffsetY: number = 0;
  /** 宿主驱动的蒙层不透明度（0–1），与位移同步淡入淡出。 */
  @Prop scrimAlpha: number = 1;

  @State private draftName: string = '';
  @State private submitting: boolean = false;
  @State private nameFocused: boolean = false;
  @State private errorCode: string = '';
  /** 组件是否已卸载；创建请求可能比抽屉动画更晚返回，用它避免在卸载后写 @State。 */
  private destroyed: boolean = false;

  aboutToDisappear(): void {
    this.destroyed = true;
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
        .id(NativeUiIds.playlistCreateNameInput)
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
          top: FIELD_PADDING_TOP,
          bottom: FIELD_PADDING_BOTTOM
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
  ErrorLine() {
    if (this.errorCode.length > 0) {
      Text(this.errorMessage())
        .id(NativeUiIds.playlistCreateError)
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
          this.NameField()
          this.ErrorLine()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Button(this.submitting ? $r('app.string.playlist_create_submitting') :
        $r('app.string.playlist_create_submit'), { stateEffect: false })
        .id(NativeUiIds.playlistCreateConfirm)
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
    .id(NativeUiIds.playlistCreateSheet + '-content')
    .width('100%')
    .height('100%')
    .padding({ top: BODY_TOP })
  }

  build() {
    BottomSheet({
      sheetId: NativeUiIds.playlistCreateSheet,
      title: $r('app.string.playlist_name_create_title'),
      // 稿件里新建态只有一行名称字段（196 高），走最小的标准档；多出的高度由内容区吸收，
      // 不会把输入框和按钮拉开。
      sheetSize: SheetSize.Small,
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

  private canSubmit(): boolean {
    return !this.submitting && !this.store.isBusy() && this.draftName.trim().length > 0;
  }

  private async submit(): Promise<void> {
    if (this.submitting || this.store.isBusy()) {
      return;
    }
    const name = this.draftName.trim();
    if (name.length === 0) {
      this.errorCode = CREATE_ERROR_EMPTY;
      return;
    }
    if (name.length > PLAYLIST_NAME_MAX_LENGTH) {
      this.errorCode = CREATE_ERROR_TOO_LONG;
      return;
    }
    this.submitting = true;
    this.errorCode = '';
    try {
      const result = await this.store.create(name);
      if (result === PlaylistActionResult.Success) {
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
      }
    }
  }

  private clearNameError(): void {
    if (this.errorCode === CREATE_ERROR_EMPTY || this.errorCode === CREATE_ERROR_TOO_LONG) {
      this.errorCode = '';
    }
  }

  private resultErrorCode(result: PlaylistActionResult): string {
    if (result === PlaylistActionResult.InvalidName) {
      return this.draftName.trim().length === 0 ? CREATE_ERROR_EMPTY : CREATE_ERROR_TOO_LONG;
    }
    if (result === PlaylistActionResult.Busy) {
      return CREATE_ERROR_BUSY;
    }
    return CREATE_ERROR_FAILED;
  }

  private errorMessage(): ResourceStr {
    if (this.errorCode === CREATE_ERROR_EMPTY) {
      return $r('app.string.playlist_name_empty_error');
    }
    if (this.errorCode === CREATE_ERROR_TOO_LONG) {
      return $r('app.string.playlist_name_long_error');
    }
    if (this.errorCode === CREATE_ERROR_BUSY) {
      return $r('app.string.playlist_busy_error');
    }
    return $r('app.string.playlist_create_failed');
  }
}