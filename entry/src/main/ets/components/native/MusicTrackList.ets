import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { MobileTrack } from '../../types/MobileTypes';
import { AppIcon, AppIconKind } from './AppIcon';
import { SelectionBarButton } from './SelectionBarButton';

/**
 * 音乐列表模板（design/playlist-page.html 2026-11 版式）。
 *
 * 歌单详情、我喜欢的、历史、合集详情共用同一套：56 高透明行、标题 13/18、副标题 12/16、
 * 行尾收藏 + 竖向更多；吸顶工具条「全部播放（N）」+ 多选 / 全选 / 关闭；多选底栏删除 / 添加到。
 *
 * 这里只放纯展示组件，不持有 store：由页面把当前播放、收藏、选中状态算好后传入。
 * 这样做是为了让四种列表共用同一份尺寸和交互，而不是各自复制一套。
 */
const TOOLBAR_HEIGHT: number = 44;
const TOOLBAR_SIDE_PADDING: number = 16;
const TOOLBAR_PLAY_HEIGHT: number = 32;
const TOOLBAR_PLAY_GAP: number = 6;
const TOOLBAR_ACTION_SIZE: number = 32;
const TOOLBAR_ACTION_GAP: number = 4;
const TOOLBAR_PLAY_ICON: number = 16;
const TOOLBAR_ACTION_ICON: number = 18;
const TOOLBAR_TEXT_SIZE: number = 13;
const TRACK_ROW_HEIGHT: number = 56;
const TRACK_ROW_SIDE_PADDING: number = 16;
const TRACK_ACTION_SIZE: number = 36;
const TRACK_ACTION_ICON: number = 16;
const TRACK_MAIN_GAP: number = 10;
const TRACK_TEXT_GAP: number = 1;
const TRACK_TITLE_GAP: number = 6;
const TRACK_TITLE_SIZE: number = 13;
const TRACK_TITLE_LINE_HEIGHT: number = 18;
const TRACK_META_LINE_HEIGHT: number = 16;
const TRACK_PLAYING_ICON: number = 16;
const TRACK_SELECT_MARK_SIZE: number = 20;
const TRACK_SELECT_CHECK_ICON: number = 12;
const BOTTOM_BAR_OUTER_PADDING: number = 6;

/** `@Prop track` 必须有初值；真实行数据由列表逐项传入。 */
const EMPTY_TRACK: MobileTrack = {
  key: '',
  bvid: '',
  aid: 0,
  cid: 0,
  title: '',
  artist: '',
  coverUrl: '',
  duration: 0,
  playCount: 0
};

@Component
export struct MusicTrackRow {
  @Prop track: MobileTrack = EMPTY_TRACK;
  @Prop index: number = 0;
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  @Prop current: boolean = false;
  @Prop favorite: boolean = false;
  @Prop favoritePending: boolean = false;
  /** 「我喜欢的」列表的爱心永远是实心，点按即取消收藏。 */
  @Prop favoritePinned: boolean = false;
  @Prop rowId: string = '';
  @Prop favoriteId: string = '';
  @Prop moreId: string = '';
  onRowTap: () => void = (): void => {};
  onFavoriteTap: () => void = (): void => {};
  onMoreTap: () => void = (): void => {};

  @Builder
  SelectionMark() {
    Stack() {
      if (this.selected) {
        AppIcon({
          iconKind: AppIconKind.Check,
          iconSize: TRACK_SELECT_CHECK_ICON,
          iconColor: ThemeColors.onAccent
        })
      }
    }
    .width(TRACK_SELECT_MARK_SIZE)
    .height(TRACK_SELECT_MARK_SIZE)
    .borderRadius(TRACK_SELECT_MARK_SIZE / 2)
    .backgroundColor(this.selected ? ThemeColors.accent : Color.Transparent)
    .border({
      width: 1.5,
      color: this.selected ? ThemeColors.accent : ThemeColors.line
    })
    .alignContent(Alignment.Center)
  }

  @Builder
  FavoriteButton() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      AppIcon({
        iconKind: this.favoriteActive() ? AppIconKind.HeartFilled : AppIconKind.Heart,
        iconSize: TRACK_ACTION_ICON,
        iconColor: this.favoriteActive() ? ThemeColors.accent : ThemeColors.textSecondary
      })
    }
    .id(this.favoriteId)
    .width(TRACK_ACTION_SIZE)
    .height(TRACK_ACTION_SIZE)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.favoritePending)
    .opacity(this.favoritePending ? 0.4 : 1)
    .onClick(() => {
      this.onFavoriteTap();
    })
    .accessibilityText(this.favoriteActive() ?
      $r('app.string.player_unfavorite') : $r('app.string.player_favorite'))
  }

  @Builder
  MoreButton() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      AppIcon({
        iconKind: AppIconKind.MoreVertical,
        iconSize: TRACK_ACTION_ICON,
        iconColor: ThemeColors.textSecondary
      })
    }
    .id(this.moreId)
    .width(TRACK_ACTION_SIZE)
    .height(TRACK_ACTION_SIZE)
    .padding(0)
    .margin({ right: 2 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      this.onMoreTap();
    })
    .accessibilityText($r('app.string.track_action_more'))
  }

  build() {
    Row() {
      Row({ space: TRACK_MAIN_GAP }) {
        if (this.selectionMode) {
          this.SelectionMark()
        }

        Column({ space: TRACK_TEXT_GAP }) {
          Row({ space: TRACK_TITLE_GAP }) {
            if (this.current) {
              AppIcon({
                iconKind: AppIconKind.Quality,
                iconSize: TRACK_PLAYING_ICON,
                iconColor: ThemeColors.nowPlayingMark
              })
            }
            Text(this.displayTitle())
              .layoutWeight(1)
              .fontSize(TRACK_TITLE_SIZE)
              .lineHeight(TRACK_TITLE_LINE_HEIGHT)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.current ? ThemeColors.nowPlaying : ThemeColors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.displayArtist())
            .width('100%')
            .fontSize(ThemeTypography.meta)
            .lineHeight(TRACK_META_LINE_HEIGHT)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: ThemeSpacing.sm, right: ThemeSpacing.xs })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onRowTap();
      })

      if (!this.selectionMode) {
        this.FavoriteButton()
        this.MoreButton()
      }
    }
    .id(this.rowId)
    .width('100%')
    .height(TRACK_ROW_HEIGHT)
    .padding({ left: TRACK_ROW_SIDE_PADDING, right: TRACK_ROW_SIDE_PADDING })
    .alignItems(VerticalAlign.Center)
  }

  private favoriteActive(): boolean {
    return this.favoritePinned || this.favorite;
  }

  private displayTitle(): ResourceStr {
    return this.track.title.trim().length > 0 ?
      this.track.title : $r('app.string.playlist_detail_unknown_track');
  }

  private displayArtist(): ResourceStr {
    return this.track.artist.trim().length > 0 ?
      this.track.artist : $r('app.string.playlist_detail_unknown_artist');
  }
}

@Component
export struct MusicTrackToolbar {
  @Prop toolbarId: string = '';
  @Prop playAllId: string = '';
  @Prop selectToggleId: string = '';
  @Prop selectAllId: string = '';
  @Prop exitSelectId: string = '';
  @Prop trackCount: number = 0;
  @Prop busy: boolean = false;
  @Prop selectionMode: boolean = false;
  @Prop allSelected: boolean = false;
  @Prop playAllLabel: ResourceStr = '';
  @Prop selectLabel: ResourceStr = '';
  @Prop exitSelectLabel: ResourceStr = '';
  @Prop selectAllLabel: ResourceStr = '';
  onPlayAll: () => void = (): void => {};
  onSelectToggle: () => void = (): void => {};
  onExitSelect: () => void = (): void => {};
  onSelectAll: () => void = (): void => {};

  @Builder
  PlayAllButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: TOOLBAR_PLAY_GAP }) {
        AppIcon({
          iconKind: AppIconKind.Play,
          iconSize: TOOLBAR_PLAY_ICON,
          iconColor: ThemeColors.textPrimary
        })
        Text(this.playAllLabel)
          .fontSize(TOOLBAR_TEXT_SIZE)
          .lineHeight(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
        Text(`（${this.trackCount}）`)
          .fontSize(TOOLBAR_TEXT_SIZE)
          .lineHeight(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
      }
      .alignItems(VerticalAlign.Center)
    }
    .id(this.playAllId)
    .height(TOOLBAR_PLAY_HEIGHT)
    .padding({ left: 6, right: ThemeSpacing.sm })
    .borderRadius(ThemeRadius.md)
    .backgroundColor(Color.Transparent)
    .enabled(!this.busy)
    .opacity(this.busy ? 0.4 : 1)
    .onClick(() => {
      this.onPlayAll();
    })
    .accessibilityText($r('app.string.playlist_detail_play_all'))
  }

  @Builder
  SelectAllButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 6 }) {
        AppIcon({
          iconKind: this.allSelected ? AppIconKind.CheckboxChecked : AppIconKind.CheckboxUnchecked,
          iconSize: TOOLBAR_ACTION_ICON,
          iconColor: ThemeColors.textPrimary
        })
        Text(this.selectAllLabel)
          .fontSize(TOOLBAR_TEXT_SIZE)
          .lineHeight(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
      }
      .alignItems(VerticalAlign.Center)
    }
    .id(this.selectAllId)
    .height(TOOLBAR_ACTION_SIZE)
    .padding({ left: ThemeSpacing.sm, right: ThemeSpacing.sm })
    .borderRadius(ThemeRadius.md)
    .backgroundColor(Color.Transparent)
    .enabled(!this.busy)
    .opacity(this.busy ? 0.4 : 1)
    .onClick(() => {
      this.onSelectAll();
    })
    .accessibilityText($r('app.string.playlist_detail_select_all'))
  }

  @Builder
  ToolbarAction(id: string, iconKind: AppIconKind, accessibility: Resource, onTap: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      AppIcon({
        iconKind: iconKind,
        iconSize: TOOLBAR_ACTION_ICON,
        iconColor: ThemeColors.textPrimary
      })
    }
    .id(id)
    .width(TOOLBAR_ACTION_SIZE)
    .height(TOOLBAR_ACTION_SIZE)
    .padding(0)
    .borderRadius(ThemeRadius.md)
    .backgroundColor(Color.Transparent)
    .enabled(!this.busy)
    .opacity(this.busy ? 0.4 : 1)
    .onClick(onTap)
    .accessibilityText(accessibility)
  }

  build() {
    Row() {
      this.PlayAllButton()

      Blank()

      Row({ space: TOOLBAR_ACTION_GAP }) {
        if (this.selectionMode) {
          this.SelectAllButton()
          this.ToolbarAction(
            this.exitSelectId,
            AppIconKind.CloseLarge,
            $r('app.string.playlist_detail_exit_select'),
            (): void => {
              this.onExitSelect();
            }
          )
        } else {
          this.ToolbarAction(
            this.selectToggleId,
            AppIconKind.SelectList,
            $r('app.string.playlist_detail_select'),
            (): void => {
              this.onSelectToggle();
            }
          )
        }
      }
      .alignItems(VerticalAlign.Center)
    }
    .id(this.toolbarId)
    .width('100%')
    .height(TOOLBAR_HEIGHT)
    .padding({ left: TOOLBAR_SIDE_PADDING, right: TOOLBAR_SIDE_PADDING })
    .backgroundColor(ThemeColors.bg)
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct MusicSelectionBar {
  @Prop barId: string = '';
  @Prop deleteId: string = '';
  @Prop addId: string = '';
  @Prop deleteLabel: ResourceStr = '';
  @Prop addLabel: ResourceStr = '';
  @Prop deleteEnabled: boolean = false;
  @Prop addEnabled: boolean = false;
  @Prop showDelete: boolean = true;
  /** 下载列表只做删除，不显示「添加到」；默认保留给其它列表使用。 */
  @Prop showAdd: boolean = true;
  onDelete: () => void = (): void => {};
  onAdd: () => void = (): void => {};

  build() {
    Row() {
      if (this.showDelete) {
        SelectionBarButton({
          selectorId: this.deleteId,
          iconKind: AppIconKind.Trash,
          label: this.deleteLabel,
          enabledFlag: this.deleteEnabled,
          onTap: (): void => {
            this.onDelete();
          }
        })
      }
      if (this.showAdd) {
        SelectionBarButton({
          selectorId: this.addId,
          iconKind: AppIconKind.AddSquare,
          label: this.addLabel,
          enabledFlag: this.addEnabled,
          onTap: (): void => {
            this.onAdd();
          }
        })
      }
    }
    .id(this.barId)
    .width('100%')
    .padding({
      left: ThemeSpacing.sm,
      right: ThemeSpacing.sm,
      top: BOTTOM_BAR_OUTER_PADDING,
      bottom: BOTTOM_BAR_OUTER_PADDING
    })
    .backgroundColor(ThemeColors.surface)
    .border({ width: { top: 1 }, color: ThemeColors.line })
    .alignItems(VerticalAlign.Center)
  }
}