import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { PlayerStore } from '../../state/PlayerStore';
import {
  ThemeColors,
  ThemeTypography
} from '../../theme/NativeTheme';
import { AppIcon, AppIconKind } from './AppIcon';
import { MiniPlayer } from './MiniPlayer';
import { NativeUiIds } from './NativeUiIds';

/** 新「我的」页 dock 实测：最大宽 411（Pura X Max 折叠态 459 − 48 gutter）、高 56、底距 20。 */
const DOCK_MAX_WIDTH: number = 411;
const DOCK_GUTTER: number = 24;
const DOCK_BOTTOM: number = 20;
const DOCK_GAP: number = 8;
const DOCK_HEIGHT: number = 56;
const NAV_PILL_PADDING: number = 3;
const NAV_ITEM_WIDTH: number = 68;
const NAV_ITEM_HEIGHT: number = 48;
const NAV_ICON_SIZE: number = 20;
const DOCK_SHADOW_RADIUS: number = 24;
const DOCK_SHADOW_OFFSET_Y: number = 10;

/**
 * 壳层底部悬浮 dock：左侧导航胶囊 + 右侧迷你播放器。
 *
 * 设计稿里导航是一颗单按钮胶囊：在「我的」显示「发现」，在「发现」显示「我的」，
 * 点击即切换一级 tab。迷你播放器可见时胶囊靠左、播放器填满剩余宽度；不可见时胶囊居中。
 * 播放器自身负责错误态、重试和标题省略。
 */
@Component
export struct BottomDock {
  @ObjectLink playerStore: PlayerStore;
  /** 必须是 @Prop：普通成员只在构造时赋值，切 tab 后胶囊里的图标 / 文案会停在旧目的地。 */
  @Prop selectedTab: number = 0;
  runtime: NativeAppRuntime | null = null;
  onSwitchTab: (index: number) => void = (_index: number): void => {};
  onExpandPlayer: () => void = (): void => {};

  build() {
    Row() {
      Row({ space: DOCK_GAP }) {
        this.NavPill()

        if (this.hasMiniPlayer()) {
          Row() {
            MiniPlayer({
              store: this.playerStore,
              runtime: this.runtime,
              onExpand: (): void => {
                this.onExpandPlayer();
              }
            })
          }
          .layoutWeight(1)
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: DOCK_MAX_WIDTH })
      .justifyContent(this.hasMiniPlayer() ? FlexAlign.Start : FlexAlign.Center)
    }
    .id(NativeUiIds.bottomDock)
    .width('100%')
    .padding({ left: DOCK_GUTTER, right: DOCK_GUTTER, bottom: DOCK_BOTTOM })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Bottom)
  }

  @Builder
  NavPill() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 2 }) {
        AppIcon({
          iconKind: this.destinationIcon(),
          iconSize: NAV_ICON_SIZE,
          iconColor: ThemeColors.textPrimary
        })
        Text(this.destinationLabel())
          .id(this.destinationId())
          .width('100%')
          .fontSize(ThemeTypography.dockLabel)
          .lineHeight(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
      .width(NAV_ITEM_WIDTH)
      .height(NAV_ITEM_HEIGHT)
      .justifyContent(FlexAlign.Center)
    }
    .id(NativeUiIds.navPill)
    .height(DOCK_HEIGHT)
    .padding(NAV_PILL_PADDING)
    .backgroundColor(ThemeColors.surface)
    .border({ width: 1, color: ThemeColors.line })
    .borderRadius(DOCK_HEIGHT / 2)
    .shadow({
      radius: DOCK_SHADOW_RADIUS,
      color: ThemeColors.dockShadow,
      offsetX: 0,
      offsetY: DOCK_SHADOW_OFFSET_Y
    })
    .onClick(() => {
      this.onSwitchTab(this.selectedTab === 0 ? 1 : 0);
    })
    .accessibilityText(this.destinationLabel())
  }

  private hasMiniPlayer(): boolean {
    return this.playerStore.error !== null || this.playerStore.snapshot.track !== null;
  }

  private destinationLabel(): Resource {
    return this.selectedTab === 0 ? $r('app.string.nav_mine') : $r('app.string.nav_discover');
  }

  private destinationId(): string {
    return this.selectedTab === 0 ? NativeUiIds.navMine : NativeUiIds.navDiscover;
  }

  private destinationIcon(): AppIconKind {
    return this.selectedTab === 0 ? AppIconKind.Person : AppIconKind.Discover;
  }
}