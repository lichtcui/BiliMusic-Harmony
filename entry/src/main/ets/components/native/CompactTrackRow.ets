import { PlayerStore } from '../../state/PlayerStore';
import { MobileTrack } from '../../types/MobileTypes';
import {
  ThemeColors,
  ThemeRadius,
  ThemeTypography
} from '../../theme/NativeTheme';
import { CoverImage, CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { AppIcon, AppIconKind } from './AppIcon';
import { formatTrackDuration, formatTrackPlayCount } from './TrackRow';

const COMPACT_ROW_HEIGHT: number = 56;
const COMPACT_ROW_GAP: number = 12;
const COMPACT_COVER_SIZE: number = 40;
const COMPACT_ACTION_SIZE: number = 36;
const COMPACT_ACTION_ICON: number = 20;
const COMPACT_LOADING_SIZE: number = 20;
const COMPACT_TITLE_LINE_HEIGHT: number = 20;
const COMPACT_TITLE_GAP: number = 6;
const COMPACT_PLAYING_ICON: number = 16;
const COMPACT_TEXT_GAP: number = 1;
const COMPACT_META_HEIGHT: number = 16;
const COMPACT_META_GAP: number = 3;
const COMPACT_BADGE_HEIGHT: number = 14;
const COMPACT_BADGE_FONT: number = 9;
const COMPACT_BADGE_PADDING: number = 3;
const COMPACT_BADGE_INSET: number = 2;
const COMPACT_BADGE_RADIUS: number = 4;

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

/**
 * 发现页搜索结果的紧凑行：与「更多操作」抽屉里的歌单行同构。
 * 单曲不显示封面；合集显示 40×40 封面，并在封面右下角压「N首」徽标，
 * 作者行保留播放量与总时长。正在播放的曲目与歌单详情页保持一致：标题前显示音质图标，
 * 标题染成强调色。
 * 行是独立组件并通过 `@ObjectLink playerStore` 自行订阅播放状态，不依赖父级 ForEach 重建。
 */
@Component
export struct CompactTrackRow {
  imageCache: CoverImageProvider = EMPTY_COVER_PROVIDER;
  @ObjectLink playerStore: PlayerStore;
  @Prop track: MobileTrack = EMPTY_TRACK;
  @Prop showMoreMenu: boolean = true;
  @Prop loading: boolean = false;
  onTrackClick: (track: MobileTrack) => void = (_track: MobileTrack): void => {
  };
  onMoreClick: (track: MobileTrack) => void = (_track: MobileTrack): void => {
  };

  build() {
    Row() {
      Row({ space: COMPACT_ROW_GAP }) {
        if (this.isCollection()) {
          Stack({ alignContent: Alignment.BottomEnd }) {
            CoverImage({
              imageCache: this.imageCache,
              coverUrl: this.track.coverUrl,
              coverSize: COMPACT_COVER_SIZE,
              cornerRadius: ThemeRadius.md
            })
            Text(`${this.track.collectionSize}首`)
              .height(COMPACT_BADGE_HEIGHT)
              .padding({ left: COMPACT_BADGE_PADDING, right: COMPACT_BADGE_PADDING })
              .margin({ right: COMPACT_BADGE_INSET, bottom: COMPACT_BADGE_INSET })
              .fontSize(COMPACT_BADGE_FONT)
              .lineHeight(COMPACT_BADGE_HEIGHT)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeColors.onAccent)
              .backgroundColor(ThemeColors.accent)
              .borderRadius(COMPACT_BADGE_RADIUS)
              .maxLines(1)
          }
          .width(COMPACT_COVER_SIZE)
          .height(COMPACT_COVER_SIZE)
          .borderRadius(ThemeRadius.md)
          .clip(true)
        }
        Column({ space: COMPACT_TEXT_GAP }) {
          Row({ space: COMPACT_TITLE_GAP }) {
            if (this.isCurrent()) {
              AppIcon({
                iconKind: AppIconKind.Quality,
                iconSize: COMPACT_PLAYING_ICON,
                iconColor: ThemeColors.nowPlayingMark
              })
            }
            Text(this.displayTitle())
              .layoutWeight(1)
              .height(COMPACT_TITLE_LINE_HEIGHT)
              .fontSize(ThemeTypography.caption)
              .lineHeight(COMPACT_TITLE_LINE_HEIGHT)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isCurrent() ? ThemeColors.nowPlaying : ThemeColors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Row({ space: COMPACT_META_GAP }) {
            Text(this.displayArtist())
              .layoutWeight(1)
              .fontSize(ThemeTypography.meta)
              .lineHeight(COMPACT_META_HEIGHT)
              .fontColor(ThemeColors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.track.playCount > 0) {
              Text(formatTrackPlayCount(this.track.playCount))
                .fontSize(ThemeTypography.meta)
                .lineHeight(COMPACT_META_HEIGHT)
                .fontColor(ThemeColors.textSecondary)
                .maxLines(1)
            }
            Text(formatTrackDuration(this.displayDuration()))
              .fontSize(ThemeTypography.meta)
              .lineHeight(COMPACT_META_HEIGHT)
              .fontColor(ThemeColors.textSecondary)
              .maxLines(1)
          }
          .width('100%')
          .height(COMPACT_META_HEIGHT)
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .height(COMPACT_ROW_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onTrackClick(this.track))
      .accessibilityText(this.accessibilityLabel())

      if (this.loading) {
        Row() {
          LoadingProgress()
            .width(COMPACT_LOADING_SIZE)
            .height(COMPACT_LOADING_SIZE)
            .color(ThemeColors.accent)
        }
        .width(COMPACT_ACTION_SIZE)
        .height(COMPACT_ACTION_SIZE)
        .justifyContent(FlexAlign.Center)
        .accessibilityText('正在装载播放队列')
      } else if (this.showMoreMenu) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          AppIcon({
            iconKind: AppIconKind.More,
            iconSize: COMPACT_ACTION_ICON,
            iconColor: ThemeColors.textSecondary
          })
        }
        .width(COMPACT_ACTION_SIZE)
        .height(COMPACT_ACTION_SIZE)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.onMoreClick(this.track))
        .accessibilityText('更多操作')
      }
    }
    .width('100%')
    .height(COMPACT_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  private displayTitle(): string {
    const title = this.track.title.trim();
    return title.length > 0 ? title : '未知曲目';
  }

  private displayArtist(): string {
    const artist = this.track.artist.trim();
    return artist.length > 0 ? artist : '未知作者';
  }

  private isCollection(): boolean {
    return (this.track.collectionSize ?? 0) > 1;
  }

  /** 单曲按 `key` 匹配；合集行代表整段视频，任一 P 在播都算本行正在播放。 */
  private isCurrent(): boolean {
    const current = this.playerStore.snapshot.track;
    if (current === null || this.track.key.length === 0) {
      return false;
    }
    if (this.isCollection() && current.bvid.length > 0 && this.track.bvid.length > 0) {
      return current.bvid === this.track.bvid;
    }
    return current.key === this.track.key;
  }

  private displayDuration(): number {
    if (this.isCollection()) {
      return this.track.collectionTotalDuration ?? this.track.duration;
    }
    return this.track.duration;
  }

  private accessibilityLabel(): string {
    const currentLabel = this.isCurrent() ? '，正在播放' : '';
    if (this.isCollection()) {
      return `${this.displayTitle()}，合集 ${this.track.collectionSize} 首，总时长 ` +
        `${formatTrackDuration(this.displayDuration())}${currentLabel}`;
    }
    if (this.isCurrent()) {
      return `${this.displayTitle()}，${this.displayArtist()}${currentLabel}`;
    }
    return `${this.displayTitle()}，${this.displayArtist()}，立即播放`;
  }
}