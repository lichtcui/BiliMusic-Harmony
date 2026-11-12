import { MobileTrack } from '../../types/MobileTypes';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { CoverImage, CoverImageProvider, EMPTY_COVER_PROVIDER } from './CoverImage';
import { AppIcon, AppIconKind } from './AppIcon';

const TRACK_ROW_MIN_HEIGHT: number = 84;
const TRACK_ROW_ACCENT_WIDTH: number = 4;
const TRACK_ROW_ACCENT_HEIGHT: number = 44;
const TRACK_ROW_COVER_SIZE: number = 56;
const TRACK_ROW_TITLE_HEIGHT: number = 44;
const TRACK_ROW_META_HEIGHT: number = 20;
const TRACK_ROW_ACTION_SIZE: number = 48;
const TRACK_ROW_TITLE_LINE_HEIGHT: number = 22;

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

export function formatTrackDuration(durationSeconds: number): string {
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    return '--:--';
  }
  const totalSeconds = Math.floor(durationSeconds);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const paddedSeconds = seconds < 10 ? `0${seconds}` : `${seconds}`;
  if (hours > 0) {
    const paddedMinutes = minutes < 10 ? `0${minutes}` : `${minutes}`;
    return `${hours}:${paddedMinutes}:${paddedSeconds}`;
  }
  return `${minutes}:${paddedSeconds}`;
}

export function formatTrackPlayCount(playCount: number): string {
  if (!Number.isFinite(playCount) || playCount <= 0) {
    return '';
  }
  const safeCount = Math.floor(playCount);
  if (safeCount >= 100000000) {
    return `${Math.floor(safeCount / 10000000) / 10}亿播放`;
  }
  if (safeCount >= 10000) {
    return `${Math.floor(safeCount / 1000) / 10}万播放`;
  }
  return `${safeCount} 播放`;
}

@Component
export struct TrackRow {
  imageCache: CoverImageProvider = EMPTY_COVER_PROVIDER;
  @Prop track: MobileTrack = EMPTY_TRACK;
  @Prop isCurrent: boolean = false;
  @Prop showPlayCount: boolean = false;
  @Prop showMoreMenu: boolean = true;
  onTrackClick: (track: MobileTrack) => void = (_track: MobileTrack): void => {
  };
  onMoreClick: (track: MobileTrack) => void = (_track: MobileTrack): void => {
  };

  build() {
    Row() {
      Row({ space: ThemeSpacing.sm }) {
        Row()
          .width(TRACK_ROW_ACCENT_WIDTH)
          .height(TRACK_ROW_ACCENT_HEIGHT)
          .borderRadius(ThemeRadius.sm)
          .backgroundColor(this.isCurrent ? ThemeColors.nowPlayingMark : Color.Transparent)
        CoverImage({
          imageCache: this.imageCache,
          coverUrl: this.track.coverUrl,
          coverSize: TRACK_ROW_COVER_SIZE,
          cornerRadius: ThemeRadius.sm
        })
        Column({ space: ThemeSpacing.xs }) {
          Text(this.displayTitle())
            .width('100%')
            .height(TRACK_ROW_TITLE_HEIGHT)
            .fontSize(ThemeTypography.body)
            .lineHeight(TRACK_ROW_TITLE_LINE_HEIGHT)
            .fontWeight(this.isCurrent ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.isCurrent ? ThemeColors.nowPlaying : ThemeColors.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: ThemeSpacing.xs }) {
            Text(this.displayArtist())
              .layoutWeight(1)
              .height(TRACK_ROW_META_HEIGHT)
              .fontSize(ThemeTypography.eyebrow)
              .lineHeight(TRACK_ROW_META_HEIGHT)
              .fontColor(ThemeColors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.isCollection()) {
              Text(`合集 · ${this.track.collectionSize}P`)
                .height(18)
                .padding({ left: 4, right: 4 })
                .fontSize(ThemeTypography.eyebrow)
                .lineHeight(18)
                .fontColor(ThemeColors.accent)
                .backgroundColor(ThemeColors.accentSoft)
                .borderRadius(ThemeRadius.sm)
                .maxLines(1)
            }
            if (this.showPlayCount && !this.isCollection() && this.track.playCount > 0) {
              Text(formatTrackPlayCount(this.track.playCount))
                .height(TRACK_ROW_META_HEIGHT)
                .fontSize(ThemeTypography.eyebrow)
                .lineHeight(TRACK_ROW_META_HEIGHT)
                .fontColor(ThemeColors.textSecondary)
                .maxLines(1)
            }
            Text(formatTrackDuration(this.displayDuration()))
              .height(TRACK_ROW_META_HEIGHT)
              .fontSize(ThemeTypography.eyebrow)
              .lineHeight(TRACK_ROW_META_HEIGHT)
              .fontColor(ThemeColors.textSecondary)
              .maxLines(1)
          }
          .width('100%')
          .height(TRACK_ROW_META_HEIGHT)
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: TRACK_ROW_MIN_HEIGHT })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onTrackClick(this.track))
      .accessibilityText(this.accessibilityLabel())

      if (this.showMoreMenu) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          AppIcon({
            iconKind: AppIconKind.More,
            iconSize: 20,
            iconColor: ThemeColors.textSecondary
          })
        }
        .width(TRACK_ROW_ACTION_SIZE)
        .height(TRACK_ROW_ACTION_SIZE)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.onMoreClick(this.track))
        .accessibilityText('更多操作')
      }
    }
    .width('100%')
    .constraintSize({ minHeight: TRACK_ROW_MIN_HEIGHT })
    .padding({
      left: ThemeSpacing.md,
      right: ThemeSpacing.xs,
      top: 0,
      bottom: 0
    })
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

  private displayDuration(): number {
    if (this.isCollection()) {
      return this.track.collectionTotalDuration ?? this.track.duration;
    }
    return this.track.duration;
  }

  private accessibilityLabel(): string {
    const currentLabel = this.isCurrent ? '，正在播放' : '';
    if (this.isCollection()) {
      return `${this.displayTitle()}，合集，${this.track.collectionSize} 个分P，总时长 ` +
        `${formatTrackDuration(this.displayDuration())}${currentLabel}`;
    }
    return `${this.displayTitle()}，${this.displayArtist()}${currentLabel}`;
  }
}
