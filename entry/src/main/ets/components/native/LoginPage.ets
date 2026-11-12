import { AuthStatus, AuthStore } from '../../state/AuthStore';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { BottomSheet } from './BottomSheet';
import {
  accountAvatarInitial,
  closeLoginSheetSession,
  normalizedAccountName,
  shouldDismissLoginSheetOnSignIn,
  shouldStartLoginOnAppear
} from './LoginPageState';
import { NativeUiIds } from './NativeUiIds';
import { SheetSize } from './SheetSizing';

/** 稿件二维码模块区 174（卡 218 - 两侧 22 内边距）。 */
const LOGIN_QR_SIZE: number = 174;
/** 二维码中性纸面卡的内边距（稿件 218 - 174）。 */
const LOGIN_QR_CARD_PADDING: number = 22;
const LOGIN_ACTION_HEIGHT: number = 50;
const LOGIN_ACTION_FONT: number = 16;
/** 稿件动作按钮圆角 10（与导入行同一档）。 */
const LOGIN_ACTION_RADIUS: number = 10;
/** 带标题的账号抽屉：正文上边距 16。 */
const LOGIN_BODY_PADDING_TOP: number = ThemeSpacing.lg;
/**
 * 无标题的扫码抽屉：头部整块不渲染，正文直接从拖拽条下方开始。
 * 多留一段上边距（28），避免提示语贴着拖拽条显得局促。
 */
const LOGIN_BODY_PADDING_TOP_NO_TITLE: number = ThemeSpacing.xxl;
/** 账号卡：头像 48（1 描边）、名称 16、副题 12、横向间距 14。 */
const ACCOUNT_AVATAR_SIZE: number = 48;
const ACCOUNT_AVATAR_BORDER: number = 1;
const ACCOUNT_AVATAR_IMAGE_SIZE: number = ACCOUNT_AVATAR_SIZE - ACCOUNT_AVATAR_BORDER * 2;
const ACCOUNT_AVATAR_FONT: number = 18;
const ACCOUNT_GAP: number = 14;
const ACCOUNT_NAME_LINE_HEIGHT: number = 22;
const ACCOUNT_DESC_LINE_HEIGHT: number = 17;

/**
 * 扫码登录 / 账号抽屉（2026-11 按「我的」页新稿重排）。
 *
 * 形态是底部抽屉：根容器是共用外壳 `BottomSheet`。未登录时展示二维码，
 * 内部状态机（starting / waiting / scanned / success / error / expired / cancelled）
 * 与 `AuthStore` 调用完全沿用。**扫码成功后抽屉直接收起**（不切换成账号内容）；
 * 只有「打开时已经登录」才展示账号卡 + 危险样式的「退出登录」。
 * 抽屉的关闭有四条路径（蒙层 / 拖拽条点按 / 下滑 / 系统 Back），全部收敛到 `close()`——
 * 轮询由宿主在滑出动画结束后显式取消，不能只依赖条件渲染下的 `aboutToDisappear`。
 *
 * 新稿的排版（373 宽基准实测）：左右 28、居中提示 14、
 * 中性纸面二维码卡 218（内边距 22，二维码 174）。未登录抽屉不显示
 * 头部标题（只留拖拽条），正文与拖拽条之间留 28 的上边距；底部不再放「取消登录」按钮，
 * 关闭只走蒙层 / 拖拽条 / 下滑 / 系统 Back。这套头部 / 圆角 / 底色就是
 * 2026-11 全仓抽屉的统一模板，其它抽屉不再各自覆盖。
 * 高度由 `SheetSizing` 的档位统一定义：未登录紧凑档（48%，钳制 392–440），
 * 已登录小档（28%，钳制 232–300）——后者刚好容纳账号卡 + 退出按钮，不再留大片空白。
 * 两档都可以从头部上拉到安全区下方，顶角圆角全程保持 28。
 * 二维码墨色仍是纯黑（`qrInk`）——真机识别率优先，纸面与墨色都不随深色主题反色。
 */
@Component
export struct LoginPage {
  /**
   * `@Watch` 监听的是 `AuthStore` 的 `snapshot` 赋值：扫码确认后 AuthStore 会把
   * `profile.isLogin` 翻成 true，这里据此主动收起抽屉（见 `onAuthSnapshotChanged`）。
   */
  @ObjectLink @Watch('onAuthSnapshotChanged') authStore: AuthStore;
  @Prop autoStartQrLoginOnAppear: boolean = true;
  /** 宿主驱动的底部滑入位移（vp）；0 表示完全展开。 */
  @Prop sheetOffsetY: number = 0;
  /** 宿主驱动的蒙层不透明度（0–1）。 */
  @Prop scrimAlpha: number = 1;
  onClose: () => void = (): void => {};

  @State private logoutBusy: boolean = false;
  @State private failedAvatarUrl: string = '';
  /**
   * 打开抽屉时的登录态：决定这一实例是「扫码抽屉」还是「账号抽屉」。
   * 扫码成功只收起抽屉，不在同一个实例里换成账号内容——否则滑出动画会先
   * 闪一版账号卡，并把面板高度从 59% 跳到 28%。
   */
  private startedSignedOut: boolean = false;
  /** 扫码成功后的自动收起只触发一次。 */
  private dismissRequested: boolean = false;
  /**
   * 账号抽屉打开瞬间的账号文案与头像。
   * 退出登录成功后 AuthStore 会先清空 profile 再通知宿主，而抽屉还要滑出 340ms；
   * 若继续读实时快照，这段动画会闪回「Bilibili」兜底文案并丢掉头像。
   * 未登录时这两项不会参与渲染（账号抽屉只在打开时已登录才出现）。
   */
  private openingAccountName: string = '';
  private openingAccountAvatarUrl: string = '';

  aboutToAppear(): void {
    const snapshot = this.authStore.read();
    this.startedSignedOut = !snapshot.profile.isLogin;
    if (!this.startedSignedOut) {
      this.openingAccountName = normalizedAccountName(snapshot.profile.name);
      this.openingAccountAvatarUrl = snapshot.profile.avatarUrl.trim();
    }
    if (this.startedSignedOut &&
      shouldStartLoginOnAppear(snapshot.status, this.autoStartQrLoginOnAppear)) {
      void this.authStore.startQrLogin();
    }
  }

  /**
   * 扫码登录成功后自动合上抽屉：收起动画交给宿主（`onClose`），
   * 轮询收尾也由宿主在动画结束后统一做。
   * 已登录时打开的账号抽屉不会命中（`startedSignedOut` 为 false）。
   */
  onAuthSnapshotChanged(): void {
    if (this.dismissRequested || !this.isLoginJustSucceeded()) {
      return;
    }
    this.dismissRequested = true;
    this.close();
  }

  /**
   * 兜底：正常路径都走 `close()`；这里只处理非用户操作导致的卸载。
   *
   * 不能同步调用：`cancelQrLogin()` 会读 `AuthStore` 的非 @Track `disposed` 字段，
   * 在 aboutToDisappear 的渲染上下文里读它会触发 140110 并杀进程。推迟一个任务再收尾。
   */
  aboutToDisappear(): void {
    const authStore = this.authStore;
    setTimeout((): void => {
      closeLoginSheetSession(authStore);
    }, 0);
  }

  build() {
    BottomSheet({
      sheetId: NativeUiIds.loginSheet,
      title: this.sheetTitle(),
      // 未登录走紧凑档（48%），已登录的账号卡走小档（28%）——档位由共用外壳统一定义。
      sheetSize: this.isAccountSheet() ? SheetSize.Small : SheetSize.Compact,
      panelOffsetY: this.sheetOffsetY,
      scrimAlpha: this.scrimAlpha,
      onClose: (): void => {
        this.close();
      }
    }) {
      Column() {
        if (this.isAccountSheet()) {
          this.AccountContent()
        } else if (this.isLoginJustSucceeded()) {
          this.SignInSuccessContent()
        } else if (this.isQrContentVisible()) {
          this.QrContent()
        } else {
          Scroll() {
            Column({ space: ThemeSpacing.lg }) {
              if (this.isQrStatusWithoutCode()) {
                this.MessageContent(
                  NativeUiIds.loginQrUnavailable,
                  $r('app.string.login_error_title'),
                  $r('app.string.login_qr_unavailable'),
                  $r('app.string.login_retry')
                )
              } else if (this.authStore.snapshot.status === 'expired') {
                this.MessageContent(
                  NativeUiIds.loginExpired,
                  $r('app.string.login_expired_title'),
                  $r('app.string.login_expired_description'),
                  $r('app.string.login_restart')
                )
              } else if (this.authStore.snapshot.status === 'error') {
                this.MessageContent(
                  NativeUiIds.loginError,
                  $r('app.string.login_error_title'),
                  this.loginErrorMessage(),
                  $r('app.string.login_retry')
                )
              } else if (this.authStore.snapshot.status === 'cancelled') {
                this.MessageContent(
                  NativeUiIds.loginCancelled,
                  $r('app.string.login_cancelled_title'),
                  $r('app.string.login_cancelled_description'),
                  $r('app.string.login_restart')
                )
              } else {
                this.MessageContent(
                  NativeUiIds.loginIdle,
                  $r('app.string.login_signed_out_title'),
                  $r('app.string.login_signed_out_description'),
                  $r('app.string.login_open')
                )
              }
            }
            .id(NativeUiIds.loginContent)
            .width('100%')
            .padding({ top: ThemeSpacing.gutter, bottom: ThemeSpacing.md })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .align(Alignment.Top)
        }
      }
      .id(NativeUiIds.loginPage)
      .width('100%')
      .height('100%')
      .padding({ top: this.isAccountSheet() ?
        LOGIN_BODY_PADDING_TOP :
        LOGIN_BODY_PADDING_TOP_NO_TITLE })
    }
  }

  /**
   * 已登录账号卡（稿件）：48 描边头像 + 名称/「bilibili 账号 · 已连接」，
   * 下方用可伸缩留白把「退出登录」压到抽屉底部。
   */
  @Builder
  AccountContent() {
    Column() {
      Row({ space: ACCOUNT_GAP }) {
        Stack() {
          Text(accountAvatarInitial(this.accountName()))
            .fontSize(ACCOUNT_AVATAR_FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)

          if (this.shouldShowAvatar()) {
            Image(this.avatarUrl())
              .width(ACCOUNT_AVATAR_IMAGE_SIZE)
              .height(ACCOUNT_AVATAR_IMAGE_SIZE)
              .objectFit(ImageFit.Cover)
              .borderRadius(ACCOUNT_AVATAR_IMAGE_SIZE / 2)
              .onError(() => {
                this.failedAvatarUrl = this.avatarUrl();
              })
          }
        }
        .width(ACCOUNT_AVATAR_SIZE)
        .height(ACCOUNT_AVATAR_SIZE)
        .borderWidth(ACCOUNT_AVATAR_BORDER)
        .borderColor(ThemeColors.line)
        .borderRadius(ACCOUNT_AVATAR_SIZE / 2)
        .alignContent(Alignment.Center)

        Column({ space: 3 }) {
          Text(this.accountName())
            .id(NativeUiIds.loginAccountName)
            .width('100%')
            .fontSize(ThemeTypography.listTitle)
            .lineHeight(ACCOUNT_NAME_LINE_HEIGHT)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text($r('app.string.login_account_sheet_description'))
            .width('100%')
            .fontSize(ThemeTypography.meta)
            .lineHeight(ACCOUNT_DESC_LINE_HEIGHT)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .id(NativeUiIds.loginAccountCard)
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Blank()

      Button(this.logoutBusy ?
        $r('app.string.login_logout_busy') :
        $r('app.string.login_logout'), { stateEffect: false })
        .id(NativeUiIds.loginLogout)
        .width('100%')
        .height(LOGIN_ACTION_HEIGHT)
        .fontSize(LOGIN_ACTION_FONT)
        .fontColor(ThemeColors.danger)
        .backgroundColor(Color.Transparent)
        .borderWidth(1)
        .borderColor(ThemeColors.dangerBorder)
        .borderRadius(LOGIN_ACTION_RADIUS)
        .enabled(!this.logoutBusy)
        .opacity(this.logoutBusy ? 0.6 : 1)
        .margin({ bottom: ThemeSpacing.md })
        .onClick(() => {
          void this.logout();
        })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 二维码生成中的占位：尺寸与二维码严格一致（174×174），只在纸面卡内部换内容，
   * 不影响抽屉布局。抽屉已不显示头部标题，这里也不再重复标题文案，只留转圈。
   */
  @Builder
  QrPlaceholder() {
    Column({ space: ThemeSpacing.sm }) {
      LoadingProgress()
        .width(ThemeSize.loadingIndicator)
        .height(ThemeSize.loadingIndicator)
        .color(ThemeColors.textSecondary)
    }
    .id(NativeUiIds.loginStarting)
    .width(LOGIN_QR_SIZE)
    .height(LOGIN_QR_SIZE)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 扫码态（新稿）：提示 + 中性纸面二维码卡，内容靠上排列。
   * 生成中（`starting`）也复用这一版式，只把二维码换成同尺寸占位，
   * 因此二维码出现前后抽屉的排版与高度完全一致。
   * 不再提供底部「取消登录」按钮——点蒙层 / 拖拽条 / 下滑 / 系统 Back 都能收起抽屉。
   * 高度走紧凑档（`SheetSize.Compact`），刚好容纳提示 + 二维码卡 + 提示语，
   * 不再在内容下方留大片空白。
   */
  @Builder
  QrContent() {
    Column() {
      Column({ space: ThemeSpacing.xl }) {
        Text(this.qrHint())
          .id('login-qr-hint')
          .width('100%')
          .fontSize(ThemeTypography.caption)
          .lineHeight(ThemeTypography.bodyLineHeight)
          .fontColor(ThemeColors.textSecondary)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Column() {
          if (this.isShowingQrCode()) {
            QRCode(this.authStore.snapshot.qrUrl)
              .id(NativeUiIds.loginQrCode)
              .width(LOGIN_QR_SIZE)
              .height(LOGIN_QR_SIZE)
              // 墨色/纸面是「模式无关」角色：永不随深色主题反色，否则真机扫不出来。
              .color(ThemeColors.qrInk)
              .backgroundColor(ThemeColors.qrPaper)
          } else {
            this.QrPlaceholder()
          }
        }
        .id('login-qr-card')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(LOGIN_QR_CARD_PADDING)
        .backgroundColor(ThemeColors.qrPaper)
        .borderRadius(ThemeRadius.card)

        Text($r('app.string.login_qr_notice'))
          .id('login-qr-notice')
          .width('100%')
          .fontSize(ThemeTypography.eyebrow)
          .lineHeight(18)
          .fontColor(ThemeColors.textSecondary)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .id(NativeUiIds.loginQrContent)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 扫码成功后的过渡画面：抽屉已交给宿主播放滑出动画，这里只在动画期间保持
   * 与扫码页一致的版式（同尺寸纸面卡 + 勾选），避免先闪一帧账号卡。
   * 纸面是「模式无关」的浅底，勾选固定用 `qrInk`，深色主题下也不会变成浅色图标。
   */
  @Builder
  SignInSuccessContent() {
    Column({ space: ThemeSpacing.xl }) {
      Column() {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(64)
          .fontColor([ThemeColors.qrInk])
      }
      .id('login-success')
      .width(LOGIN_QR_SIZE + LOGIN_QR_CARD_PADDING * 2)
      .height(LOGIN_QR_SIZE + LOGIN_QR_CARD_PADDING * 2)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeColors.qrPaper)
      .borderRadius(ThemeRadius.card)

      Text($r('app.string.login_signed_in'))
        .id('login-success-label')
        .width('100%')
        .fontSize(ThemeTypography.body)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  MessageContent(id: string, title: ResourceStr, description: ResourceStr,
    actionLabel: ResourceStr) {
    Column({ space: ThemeSpacing.md }) {
      Text(title)
        .id(NativeUiIds.loginMessageStatus)
        .width('100%')
        .fontSize(ThemeTypography.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
      Text(description)
        .width('100%')
        .fontSize(ThemeTypography.body)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
      Button(actionLabel, { stateEffect: false })
        .id(NativeUiIds.loginRestart)
        .width('100%')
        .height(LOGIN_ACTION_HEIGHT)
        .fontSize(LOGIN_ACTION_FONT)
        .fontColor(ThemeColors.onAccent)
        .backgroundColor(ThemeColors.accent)
        .borderRadius(ThemeRadius.lg)
        .onClick(() => {
          void this.authStore.startQrLogin();
        })
    }
    .id(id)
    .width('100%')
    .padding({ top: ThemeSpacing.xxl, bottom: ThemeSpacing.xxl })
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 四条关闭路径的唯一实现：通知宿主收起抽屉。
   * 这里**不**立即 `cancelQrLogin`——宿主会在滑出动画结束后显式取消
   * （`Index.closeLoginSheet`）；若在此刻就取消，抽屉会在滑出的 340ms 里
   * 先闪成「登录已取消」。`aboutToDisappear` 仍保留兜底取消。
   */
  private close(): void {
    this.onClose();
  }

  private isLoggedIn(): boolean {
    return this.authStore.snapshot.profile.isLogin;
  }

  /**
   * 抽屉内容在打开时就定下来：扫码抽屉 / 账号抽屉各自一套。
   * 收起动画期间不跟着登录态换内容，避免「扫码成功闪账号卡」或「退出登录闪成未登录」。
   */
  private isAccountSheet(): boolean {
    return !this.startedSignedOut;
  }

  /** 本次打开是未登录、且现在已经登录：展示成功过渡并收起抽屉。 */
  private isLoginJustSucceeded(): boolean {
    return shouldDismissLoginSheetOnSignIn(this.startedSignedOut, this.isLoggedIn());
  }

  private accountName(): string {
    const profile = this.authStore.snapshot.profile;
    return normalizedAccountName(profile.isLogin ? profile.name : this.openingAccountName);
  }

  private avatarUrl(): string {
    const profile = this.authStore.snapshot.profile;
    return profile.isLogin ? profile.avatarUrl.trim() : this.openingAccountAvatarUrl;
  }

  private shouldShowAvatar(): boolean {
    const url = this.avatarUrl();
    return url.length > 0 && url !== this.failedAvatarUrl;
  }

  private isQrStatusWithoutCode(): boolean {
    const status: AuthStatus = this.authStore.snapshot.status;
    return (status === 'waiting' || status === 'scanned') &&
      this.authStore.snapshot.qrUrl.trim().length === 0;
  }

  private isShowingQrCode(): boolean {
    const status: AuthStatus = this.authStore.snapshot.status;
    return (status === 'waiting' || status === 'scanned') &&
      this.authStore.snapshot.qrUrl.trim().length > 0;
  }

  /** 生成中 / 已出码：都渲染扫码版式，避免先闪一版「正在生成二维码」再换布局。 */
  private isQrContentVisible(): boolean {
    return this.authStore.snapshot.status === 'starting' || this.isShowingQrCode();
  }

  /**
   * 头部标题：已登录显示「账号」；未登录（扫码抽屉）不显示标题——头部整块收起，
   * 只保留拖拽条，提示语本身就是正文的第一行。具体状态仍由正文表达。
   */
  private sheetTitle(): ResourceStr {
    return this.isAccountSheet() ?
      $r('app.string.login_account_sheet_title') :
      '';
  }

  private qrHint(): ResourceStr {
    return this.authStore.snapshot.status === 'scanned' ?
      $r('app.string.login_scanned_description') :
      $r('app.string.login_qr_hint');
  }

  private loginErrorMessage(): ResourceStr {
    const error = this.authStore.snapshot.error;
    return error === null ? $r('app.string.login_error_description') : error.message;
  }

  /**
   * 退出登录：成功后按设计稿直接收起抽屉，回到未登录的「我的」页；
   * 失败则留在账号抽屉并用系统对话框提示，不把「退出了」的假象留给用户。
   */
  private async logout(): Promise<void> {
    if (this.logoutBusy) {
      return;
    }
    this.logoutBusy = true;
    try {
      await this.authStore.logout();
    } catch (error) {
      this.logoutBusy = false;
      this.showLogoutFailure();
      return;
    }
    this.logoutBusy = false;
    this.close();
  }

  /** 失败不占抽屉高度（账号抽屉按稿件只有 232–260），用系统对话框提示。 */
  private showLogoutFailure(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.login_logout'),
      message: $r('app.string.login_logout_failed'),
      autoCancel: true,
      confirm: {
        value: $r('app.string.sheet_close'),
        action: (): void => {}
      }
    });
  }
}