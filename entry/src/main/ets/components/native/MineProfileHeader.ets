import { AuthStore } from '../../state/AuthStore';
import {
  ThemeColors,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { AppIcon, AppIconKind } from './AppIcon';
import {
  accountAvatarInitial,
  normalizedAccountName
} from './LoginPageState';
import { NativeUiIds } from './NativeUiIds';

/** 新稿页头实测：头像 44、设置热区 40/图标 24、左右 24、上下 16。 */
const HEADER_PADDING_H: number = ThemeSpacing.gutter;
const HEADER_PADDING_V: number = ThemeSpacing.lg;
const HEADER_GAP: number = ThemeSpacing.md;
const ACCOUNT_GAP: number = ThemeSpacing.md;
const AVATAR_SIZE: number = 44;
const AVATAR_BORDER: number = 1;
const AVATAR_IMAGE_SIZE: number = AVATAR_SIZE - AVATAR_BORDER * 2;
const AVATAR_IMAGE_RADIUS: number = AVATAR_IMAGE_SIZE / 2;
const AVATAR_ICON_SIZE: number = 20;
const AVATAR_RADIUS: number = AVATAR_SIZE / 2;
const HEADER_ACTION_SIZE: number = 40;
const HEADER_ACTION_ICON: number = 24;
const NAME_LINE_HEIGHT: number = 24;
const DESC_LINE_HEIGHT: number = 17;
/** 资料未返回时的骨架条：宽度/高度按页头文字行实测，避免资料到达时布局跳动。 */
const SKELETON_NAME_WIDTH: number = 96;
const SKELETON_NAME_HEIGHT: number = 14;
const SKELETON_DESC_WIDTH: number = 64;
const SKELETON_DESC_HEIGHT: number = 10;
const SKELETON_RADIUS: number = 7;

/**
 * 「我的」页新页头：头像 + 昵称/副题 + 设置入口，替代旧的 88 高账号卡。
 *
 * 账号区整体可点：未登录打开扫码登录抽屉，已登录打开账号抽屉（退出登录在抽屉里完成，
 * 成功后再收起抽屉）。`mineAccountCard` / `mineAccountName` / `mineAccountAction` 三个
 * smoke selector 继续挂在对应元素上。
 *
 * 头像按新稿改成「无底色 + 1px line 描边」；头像图片内缩 1px，描边不会被盖住。
 */
@Component
export struct MineProfileHeader {
  @ObjectLink authStore: AuthStore;
  onOpenSettings: () => void = (): void => {};
  onOpenLogin: () => void = (): void => {};

  @State private failedAvatarUrl: string = '';
  @State private skeletonOpacity: number = 0.45;

  aboutToAppear(): void {
    this.skeletonOpacity = 0.35;
    animateTo({
      duration: 800,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, (): void => {
      this.skeletonOpacity = 0.85;
    });
  }

  @Builder
  ProfileSkeleton() {
    Column({ space: 2 }) {
      Row() {
        Row()
          .width(SKELETON_NAME_WIDTH)
          .height(SKELETON_NAME_HEIGHT)
          .borderRadius(SKELETON_RADIUS)
          .backgroundColor(ThemeColors.surfaceInset)
          .opacity(this.skeletonOpacity)
      }
      .height(NAME_LINE_HEIGHT)
      .alignItems(VerticalAlign.Center)

      Row() {
        Row()
          .width(SKELETON_DESC_WIDTH)
          .height(SKELETON_DESC_HEIGHT)
          .borderRadius(SKELETON_RADIUS)
          .backgroundColor(ThemeColors.surfaceInset)
          .opacity(this.skeletonOpacity)
      }
      .height(DESC_LINE_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .accessibilityText($r('app.string.mine_profile_loading'))
  }

  build() {
    Row({ space: HEADER_GAP }) {
      Row({ space: ACCOUNT_GAP }) {
        Stack() {
          if (this.isLoggedIn()) {
            Text(accountAvatarInitial(this.accountName()))
              .fontSize(ThemeTypography.profileName)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeColors.textSecondary)
              .maxLines(1)

            if (this.shouldShowAvatar()) {
              Image(this.avatarUrl())
                .width(AVATAR_IMAGE_SIZE)
                .height(AVATAR_IMAGE_SIZE)
                .objectFit(ImageFit.Cover)
                .borderRadius(AVATAR_IMAGE_RADIUS)
                .onError(() => {
                  this.failedAvatarUrl = this.avatarUrl();
                })
            }
          } else {
            AppIcon({
              iconKind: AppIconKind.Person,
              iconSize: AVATAR_ICON_SIZE,
              iconColor: ThemeColors.textPrimary
            })
          }
        }
        .id(NativeUiIds.mineAccountAction)
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderWidth(AVATAR_BORDER)
        .borderColor(ThemeColors.line)
        .borderRadius(AVATAR_RADIUS)
        .alignContent(Alignment.Center)

        Column({ space: 2 }) {
          if (this.isProfileLoading()) {
            this.ProfileSkeleton()
          } else {
            Text(this.accountTitle())
              .id(NativeUiIds.mineAccountName)
              .width('100%')
              .fontSize(ThemeTypography.profileName)
              .lineHeight(NAME_LINE_HEIGHT)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeColors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.accountDescription())
              .width('100%')
              .fontSize(ThemeTypography.meta)
              .lineHeight(DESC_LINE_HEIGHT)
              .fontColor(ThemeColors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .id(NativeUiIds.mineAccountCard)
      .layoutWeight(1)
      .height(AVATAR_SIZE)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.handleAccountTap();
      })
      .accessibilityText(this.isProfileLoading() ?
        $r('app.string.mine_profile_loading') :
        (this.isProfileError() ? $r('app.string.mine_profile_load_failed') :
          (this.isLoggedIn() ?
            $r('app.string.login_account_sheet_title') : $r('app.string.settings_login'))))

      Row() {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          AppIcon({
            iconKind: AppIconKind.Settings,
            iconSize: HEADER_ACTION_ICON,
            iconColor: ThemeColors.textPrimary
          })
        }
        .id(NativeUiIds.shellSettingsAction)
        .width(HEADER_ACTION_SIZE)
        .height(HEADER_ACTION_SIZE)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onOpenSettings();
        })
        .accessibilityText($r('app.string.nav_settings'))
      }
      .id(NativeUiIds.shellHeaderActions)
      .flexShrink(0)
    }
    .id(NativeUiIds.mineHeader)
    .width('100%')
    .padding({
      left: HEADER_PADDING_H,
      right: HEADER_PADDING_H,
      top: HEADER_PADDING_V,
      bottom: HEADER_PADDING_V
    })
    .alignItems(VerticalAlign.Center)
  }

  private isLoggedIn(): boolean {
    return this.authStore.snapshot.profile.isLogin;
  }

  private accountName(): string {
    return normalizedAccountName(this.authStore.snapshot.profile.name);
  }

  private avatarUrl(): string {
    return this.authStore.snapshot.profile.avatarUrl.trim();
  }

  private shouldShowAvatar(): boolean {
    const url = this.avatarUrl();
    return this.isLoggedIn() && url.length > 0 && url !== this.failedAvatarUrl;
  }

  private isProfileLoading(): boolean {
    return this.authStore.profileState === 'loading' && !this.isLoggedIn();
  }

  private isProfileError(): boolean {
    return this.authStore.profileState === 'error' && !this.isLoggedIn();
  }

  private accountTitle(): ResourceStr {
    if (this.isProfileError()) {
      return $r('app.string.mine_profile_load_failed');
    }
    return this.isLoggedIn() ? this.accountName() : $r('app.string.login_signed_out_title');
  }

  private accountDescription(): ResourceStr {
    if (this.isProfileError()) {
      return $r('app.string.mine_profile_retry');
    }
    return this.isLoggedIn() ?
      $r('app.string.mine_account_signed_in') :
      $r('app.string.mine_account_signed_out_description');
  }

  /** 未登录 / 已登录都打开同一个抽屉；加载中不弹扫码，失败时先重试刷新。 */
  private handleAccountTap(): void {
    if (this.isProfileLoading()) {
      return;
    }
    if (this.isProfileError()) {
      void this.authStore.refreshProfile().catch((): void => {});
      return;
    }
    this.onOpenLogin();
  }
}