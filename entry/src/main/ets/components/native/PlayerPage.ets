import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { AppIcon, AppIconKind } from './AppIcon';
import { LibraryStoreModel } from '../../state/LibraryStoreModel';
import { LyricsStore } from '../../state/LyricsStore';
import { PlayerStore } from '../../state/PlayerStore';
import { SettingsStore } from '../../state/SettingsStore';
import {
  ThemeColors,
  ThemeSize,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { NativeUiIds } from './NativeUiIds';
import {
  playbackErrorMessage,
  playbackErrorPresentation,
  playbackErrorTitle,
  PlaybackErrorKind
} from '../../util/PlaybackErrorPresentation';
import {
  CoverImage,
  CoverImageProvider,
  EMPTY_COVER_PROVIDER
} from './CoverImage';
import { RuntimeCoverImageProvider } from './RuntimeCoverImageProvider';
import { formatPlayerTime, PlayerPageState } from './PlayerPageState';
import { LyricsPanelState } from './LyricsPanelState';
import { PlayerFavoriteState } from './PlayerFavoriteState';
import {
  dampPlayerSwipeOffset,
  playerSwipeEnterOffset,
  PlayerSwipeDirection,
  resolvePlayerSwipe
} from './PlayerSwipeGesture';

/**
 * 08 稿（播放器主页面）的垂直节奏，单位 vp，取自设计稿 402×874 的实测值：
 * 内容顶 44（状态栏）→ 标题墨迹 70..96 → 副标题 110..122 → 封面 162..500 →
 * 歌词 498..540 → 收藏/更多 589..633 → 进度条中心 699 → 进度时间 717..733 →
 * 播放条 767..831。
 * 唯一可伸缩的间隙是歌词块与操作行之间的 `Blank()`，其余按实测固定。
 * 标题块按「行盒」计算：padding 22 + 34 行高后墨迹落在 70；封面靠 36 的间隙对齐 162。
 */
const PLAYER_TITLE_TOP: number = 22;
const PLAYER_HEADING_GAP: number = 8;
const PLAYER_COVER_GAP: number = 36;
const PLAYER_LYRIC_GAP: number = 34;
const PLAYER_ACTION_ROW_HEIGHT: number = 44;
const PLAYER_PROGRESS_GAP: number = 8;
/** 进度条下方的时间行：左「已播放」右「总时长」，长音频（1–3 小时）由 formatPlayerTime 补时位。 */
const PLAYER_TIME_ROW_HEIGHT: number = 16;
const PLAYER_TIME_GAP: number = 4;
const PLAYER_NAV_SLOT: number = 44;
/**
 * 播放条与进度区之间的间距：08 稿实测为 54，新的时间行（16 高 + 4 间距）正好吃掉 20，
 * 这里收到 34，保证底部播放条仍落在设计稿的 767 基线，不被时间行整体顶下去。
 */
const PLAYER_ACTION_BAR_GAP: number = 34;
const PLAYER_BOTTOM_PADDING: number = 12;

@Component
export struct PlayerPage {
  @ObjectLink store: PlayerStore;
  libraryModel: LibraryStoreModel | null = null;
  runtime: NativeAppRuntime | null = null;
  onOpenDiscover: () => void = (): void => {};
  onOpenLibrary: () => void = (): void => {};
  onOpenLyrics: () => void = (): void => {};
  /** 播放页「功能键」整页由 `Index` 的根 Stack 承载（右侧滑入，见 PlayerControlPanel）。 */
  onOpenPlayerPanel: () => void = (): void => {};
  settingsStore: SettingsStore | null = null;
  lyricsStore: LyricsStore | null = null;
  /** Index 持有的共享歌词视图模型：歌词面板与换源弹层使用同一份。 */
  sharedPanelState: LyricsPanelState | null = null;

  @State private pageState: PlayerPageState | null = null;

  aboutToAppear(): void {
    this.pageState = new PlayerPageState(this.store);
    this.pageState?.attach();
  }

  aboutToDisappear(): void {
    this.pageState?.dispose();
    this.pageState = null;
  }

  build() {
    if (this.pageState !== null) {
      PlayerPageContent({
        state: this.pageState,
        playerStore: this.store,
        libraryModel: this.libraryModel,
        runtime: this.runtime,
        onOpenDiscover: this.onOpenDiscover,
        onOpenLibrary: this.onOpenLibrary,
        onOpenLyrics: this.onOpenLyrics,
        onOpenPlayerPanel: this.onOpenPlayerPanel,
        settingsStore: this.settingsStore,
        lyricsStore: this.lyricsStore,
        sharedPanelState: this.sharedPanelState
      })
    } else {
      PlayerEmptyContent()
    }
  }
}

@Component
struct PlayerPageContent {
  @ObjectLink state: PlayerPageState;
  @ObjectLink playerStore: PlayerStore;
  libraryModel: LibraryStoreModel | null = null;
  runtime: NativeAppRuntime | null = null;
  onOpenDiscover: () => void = (): void => {};
  onOpenLibrary: () => void = (): void => {};
  onOpenLyrics: () => void = (): void => {};
  onOpenPlayerPanel: () => void = (): void => {};
  settingsStore: SettingsStore | null = null;
  lyricsStore: LyricsStore | null = null;
  sharedPanelState: LyricsPanelState | null = null;

  private coverProvider: CoverImageProvider = EMPTY_COVER_PROVIDER;
  @State private favoriteState: PlayerFavoriteState | null = null;
  /** 歌词预览：复用 LyricsPanelState 的「当前行」解析，避免再写一份时间轴二分查找。 */
  @State private lyricState: LyricsPanelState | null = null;
  @State private stageWidth: number = 0;
  @State private stageHeight: number = 0;
  @State private swipeOffset: number = 0;

  aboutToAppear(): void {
    if (this.runtime !== null) {
      this.coverProvider = new RuntimeCoverImageProvider(this.runtime);
    }
    if (this.libraryModel !== null) {
      this.favoriteState = new PlayerFavoriteState(this.libraryModel, this.playerStore);
      this.favoriteState?.attach();
    }
    if (this.lyricsStore !== null) {
      this.lyricState = this.sharedPanelState ??
        new LyricsPanelState(this.lyricsStore, this.playerStore);
      this.lyricState.attach();
    } else if (this.sharedPanelState !== null) {
      this.lyricState = this.sharedPanelState;
      this.lyricState.attach();
    }
  }

  aboutToDisappear(): void {
    // dispose() 会 unsubscribe 并读写非 @Track 字段；aboutToDisappear 仍在渲染上下文里，
    // 同步调用会触发 140110。也不要在销毁期间写 @State（不再置 null，重进时由 aboutToAppear 覆盖）。
    const favoriteState = this.favoriteState;
    const lyricState = this.lyricState;
    setTimeout((): void => {
      favoriteState?.dispose();
      lyricState?.dispose();
    }, 0);
  }

  @Builder
  TrackHeading() {
    Column({ space: PLAYER_HEADING_GAP }) {
      Text(this.displayTitle())
        .id(NativeUiIds.playerTitle)
        .width('100%')
        .fontSize(ThemeTypography.playerTitle)
        .lineHeight(ThemeTypography.playerTitleLineHeight)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.displayArtist())
        .id(NativeUiIds.playerArtist)
        .width('100%')
        .fontSize(ThemeTypography.playerMeta)
        .lineHeight(18)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  CoverStage() {
    Column() {
      if (this.stageWidth > 0) {
        CoverImage({
          imageCache: this.coverProvider,
          coverUrl: this.coverUrl(),
          coverSize: this.coverSize(),
          cornerRadius: ThemeSize.playerCoverRadius
        })
      } else {
        Column()
          .width('100%')
          .aspectRatio(ThemeSize.coverAspectRatio)
          .backgroundColor(ThemeColors.surfaceInset)
      }
    }
    .id(NativeUiIds.playerCover)
    .width('100%')
    .margin({ top: PLAYER_COVER_GAP })
  }

  @Builder
  ErrorBlock() {
    Column({ space: ThemeSpacing.sm }) {
      Text(this.errorTitle())
        .id(NativeUiIds.playerErrorTitle)
        .width('100%')
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.errorMessage())
        .id(NativeUiIds.playerErrorMessage)
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .lineHeight(20)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.state.track !== null) {
        Row({ space: ThemeSpacing.xs }) {
          Text(this.displayTitle())
            .id(NativeUiIds.playerErrorTrackTitle)
            .fontSize(ThemeTypography.playerTime)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('·')
            .fontSize(ThemeTypography.playerTime)
            .fontColor(ThemeColors.textSecondary)
          Text(this.displayArtist())
            .id(NativeUiIds.playerErrorTrackArtist)
            .fontSize(ThemeTypography.playerTime)
            .fontColor(ThemeColors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .justifyContent(FlexAlign.Center)
      }
      if (this.state.canRetryPlayback() || this.state.retryLoading) {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Row({ space: ThemeSpacing.xs }) {
            if (this.state.retryLoading) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(ThemeColors.onAccentAction)
            }
            Text(this.state.retryLoading ? $r('app.string.playback_error_retrying') :
              $r('app.string.playback_error_retry'))
              .fontSize(ThemeTypography.caption)
              .fontColor(ThemeColors.onAccentAction)
              .maxLines(1)
          }
          .justifyContent(FlexAlign.Center)
        }
        .id(NativeUiIds.playerErrorRetry)
        .height(36)
        .padding({ left: ThemeSpacing.xl, right: ThemeSpacing.xl })
        .margin({ top: ThemeSpacing.xs })
        .backgroundColor(ThemeColors.accentAction)
        .borderRadius(18)
        .enabled(this.state.canRetryPlayback())
        .opacity(this.state.retryLoading ? 0.7 : 1)
        .onClick(() => {
          void this.state.retryPlayback();
        })
      }
    }
    .id(NativeUiIds.playerError)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  LyricStage() {
    Column() {
      if (this.hasLyricPreview()) {
        Text(this.currentLyricText())
          .id(NativeUiIds.playerLyricCurrent)
          .width('100%')
          .fontSize(ThemeTypography.playerLyricCurrent)
          .lineHeight(ThemeTypography.playerLyricCurrentLineHeight)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.nextLyricText())
          .id(NativeUiIds.playerLyricNext)
          .width('100%')
          .fontSize(ThemeTypography.playerLyricNextLine)
          .lineHeight(ThemeTypography.playerLyricNextLineHeight)
          .fontColor(ThemeColors.textSecondary)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Text($r('app.string.player_lyric_open'))
          .id(NativeUiIds.playerLyricOpen)
          .fontSize(ThemeTypography.playerLyricNext)
          .lineHeight(ThemeTypography.playerLyricNextLineHeightSmall)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: ThemeSize.playerLyricBlockHeight })
    .margin({ top: PLAYER_LYRIC_GAP })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onOpenLyrics();
    })
    .accessibilityText($r('app.string.player_lyric_open'))
  }

  @Builder
  FavoriteIcon() {
    if (this.favoriteOn()) {
      AppIcon({
        iconKind: AppIconKind.HeartFilled,
        iconSize: ThemeSize.playerAddonIcon,
        iconColor: this.favoriteColor()
      })
    } else {
      AppIcon({
        iconKind: AppIconKind.Heart,
        iconSize: ThemeSize.playerAddonIcon,
        iconColor: this.favoriteColor()
      })
    }
  }

  @Builder
  ActionRow() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        this.FavoriteIcon()
      }
      .id(NativeUiIds.playerFavorite)
      .width(PLAYER_ACTION_ROW_HEIGHT)
      .height(PLAYER_ACTION_ROW_HEIGHT)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .enabled(this.state.track !== null && !this.favoritePending())
      .onClick(() => {
        void this.toggleFavorite();
      })
      .accessibilityText(this.favoriteLabel())

      Blank()

      Button({ type: ButtonType.Normal, stateEffect: false }) {
        AppIcon({
          iconKind: AppIconKind.More,
          iconSize: 22,
          iconColor: ThemeColors.textPrimary
        })
      }
      .id(NativeUiIds.playerTrackActions)
      .width(PLAYER_ACTION_ROW_HEIGHT)
      .height(PLAYER_ACTION_ROW_HEIGHT)
      .padding(0)
      .borderRadius(PLAYER_ACTION_ROW_HEIGHT / 2)
      .backgroundColor(Color.Transparent)
      .enabled(this.state.track !== null)
      .onClick(() => {
        if (this.state.track !== null) {
          this.onOpenPlayerPanel();
        }
      })
      .accessibilityText($r('app.string.player_more'))
    }
    .width('100%')
    .height(PLAYER_ACTION_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ProgressStage() {
    Column() {
      Slider({
        value: this.state.displayPosition(),
        min: 0,
        max: this.state.sliderMaximum(),
        step: 1,
        style: SliderStyle.OutSet
      })
        .id(NativeUiIds.playerProgress)
        .width('100%')
        .height(ThemeSize.playerProgressHeight)
        .blockColor(ThemeColors.accentAction)
        .trackColor(ThemeColors.progressTrack)
        .selectedColor(ThemeColors.accentAction)
        .trackThickness(ThemeSize.playerProgressThickness)
        .blockSize({
          width: ThemeSize.playerProgressBlock,
          height: ThemeSize.playerProgressBlock
        })
        .enabled(this.state.canSeek())
        .opacity(this.state.canSeek() ? 1 : 0.55)
        .onChange((value: number, mode: SliderChangeMode): void => {
          if (mode === SliderChangeMode.Begin) {
            this.lyricState?.resumeFollow();
            this.state.beginSeek(value);
          } else if (mode === SliderChangeMode.Moving) {
            this.lyricState?.resumeFollow();
            this.state.updateSeek(value);
          } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            void this.state.submitSeek(value);
          }
        })

      Row() {
        Text(formatPlayerTime(this.state.displayPosition()))
          .id(NativeUiIds.playerPosition)
          .fontSize(ThemeTypography.meta)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)

        Blank()

        Text(formatPlayerTime(this.state.duration))
          .id(NativeUiIds.playerDuration)
          .fontSize(ThemeTypography.meta)
          .fontColor(ThemeColors.textSecondary)
          .maxLines(1)
      }
      .width('100%')
      .height(PLAYER_TIME_ROW_HEIGHT)
      .margin({ top: PLAYER_TIME_GAP })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .margin({ top: PLAYER_PROGRESS_GAP })
  }

  @Builder
  TransportGlyph() {
    if (this.state.status === 'loading' || this.state.busyAction === 'toggle') {
      LoadingProgress()
        .width(24)
        .height(24)
        .color(ThemeColors.onAccentAction)
    } else if (this.state.status === 'playing') {
      AppIcon({
        iconKind: AppIconKind.Pause,
        iconSize: 28,
        iconColor: ThemeColors.onAccentAction
      })
    } else {
      AppIcon({
        iconKind: AppIconKind.Play,
        iconSize: 28,
        iconColor: ThemeColors.onAccentAction
      })
    }
  }

  @Builder
  BottomBar() {
    Row() {
      Stack() {
        AppIcon({
          iconKind: AppIconKind.Discover,
          iconSize: ThemeSize.playerNavIcon,
          iconColor: ThemeColors.textSecondary
        })
      }
      .id(NativeUiIds.playerNavDiscover)
      .width(PLAYER_NAV_SLOT)
      .height(ThemeSize.playerActionHeight)
      .onClick(() => {
        this.onOpenDiscover();
      })
      .accessibilityText($r('app.string.player_nav_discover'))

      Blank()

      Button({ type: ButtonType.Normal, stateEffect: false }) {
        this.TransportGlyph()
      }
      .id(NativeUiIds.playerToggle)
      .width(ThemeSize.playerActionWidth)
      .height(ThemeSize.playerActionHeight)
      .borderRadius(ThemeSize.playerActionRadius)
      .padding(0)
      .backgroundColor(ThemeColors.accentAction)
      .enabled(this.state.canTogglePlayback())
      .opacity(this.state.canTogglePlayback() ? 1 : 0.55)
      .onClick(() => {
        void this.state.togglePlayback();
      })
      .accessibilityText(this.state.status === 'playing' ?
        $r('app.string.player_pause') : $r('app.string.player_play'))

      Blank()

      Stack() {
        AppIcon({
          iconKind: AppIconKind.Person,
          iconSize: ThemeSize.playerNavIcon,
          iconColor: ThemeColors.textSecondary
        })
      }
      .id(NativeUiIds.playerNavLibrary)
      .width(PLAYER_NAV_SLOT)
      .height(ThemeSize.playerActionHeight)
      .onClick(() => {
        this.onOpenLibrary();
      })
      .accessibilityText($r('app.string.player_nav_library'))
    }
    .width('100%')
    .height(ThemeSize.playerActionHeight)
    .margin({ top: PLAYER_ACTION_BAR_GAP })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.state.track === null) {
          PlayerEmptyContent()
        } else {
          Column() {
            this.TrackHeading()

            this.CoverStage()

            if (this.showLyrics()) {
              this.LyricStage()
            }

            Blank()

            this.ActionRow()

            this.ProgressStage()

            this.BottomBar()
          }
          .width('100%')
          .height('100%')
          .translate({ y: this.swipeOffset })
          .gesture(
            PanGesture({ direction: PanDirection.Vertical, distance: 12 })
              .onActionUpdate((event: GestureEvent) => {
                this.onSwipeUpdate(event.offsetY);
              })
              .onActionEnd((event: GestureEvent) => {
                this.onSwipeEnd(event.offsetY, event.velocityY);
              })
              .onActionCancel(() => {
                this.springBack();
              })
          )
        }
      }
      .id(NativeUiIds.playerSwipeStage)
      .width('100%')
      .height('100%')
      .padding({
        left: ThemeSize.playerGutter,
        right: ThemeSize.playerGutter,
        top: PLAYER_TITLE_TOP,
        bottom: PLAYER_BOTTOM_PADDING
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.stageWidth = newValue.width as number;
        this.stageHeight = newValue.height as number;
      })
    }
    .id(NativeUiIds.playerPage)
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.playerCanvas)
    .clip(true)
  }

  private onSwipeUpdate(offsetY: number): void {
    if (!this.state.canSkip()) {
      return;
    }
    this.swipeOffset = dampPlayerSwipeOffset(offsetY, this.stageHeight);
  }

  private onSwipeEnd(offsetY: number, velocityY: number): void {
    if (!this.state.canSkip()) {
      this.springBack();
      return;
    }
    const direction: PlayerSwipeDirection = resolvePlayerSwipe({
      offsetY: offsetY,
      velocityY: velocityY,
      stageHeight: this.stageHeight,
      ratio: ThemeSize.playerSwipeCommitRatio,
      velocityThreshold: ThemeSize.playerSwipeVelocity
    });
    if (direction === '') {
      this.springBack();
      return;
    }
    const exitOffset = direction === 'next' ? -this.stageHeight : this.stageHeight;
    animateTo({
      duration: 200,
      curve: Curve.EaseIn,
      onFinish: (): void => {
        this.finishSwipe(direction);
      }
    }, () => {
      this.swipeOffset = exitOffset;
    });
  }

  private springBack(): void {
    animateTo({ duration: 200, curve: Curve.Friction }, () => {
      this.swipeOffset = 0;
    });
  }

  private finishSwipe(direction: PlayerSwipeDirection): void {
    this.swipeOffset = playerSwipeEnterOffset(direction, this.stageHeight);
    if (direction === 'next') {
      void this.state.next();
    } else if (direction === 'previous') {
      void this.state.skipPrevious();
    }
    animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.swipeOffset = 0;
    });
  }

  private async toggleFavorite(): Promise<void> {
    const favorite = this.favoriteState;
    if (favorite === null) {
      return;
    }
    await favorite.toggle(this.state.track);
  }

  private favoriteOn(): boolean {
    const favorite = this.favoriteState;
    return favorite !== null && favorite.favorited;
  }

  private favoritePending(): boolean {
    const favorite = this.favoriteState;
    return favorite !== null && favorite.pending;
  }

  private favoriteColor(): Resource {
    const favorite = this.favoriteState;
    return favorite !== null && favorite.favorited ? ThemeColors.textPrimary : ThemeColors.iconInactive;
  }

  private favoriteLabel(): Resource {
    const favorite = this.favoriteState;
    return favorite !== null && favorite.favorited ?
      $r('app.string.player_unfavorite') : $r('app.string.player_favorite');
  }

  private coverSize(): number {
    const contentWidth = this.stageWidth - ThemeSize.playerGutter * 2;
    return contentWidth > 0 ? contentWidth : 1;
  }

  private coverUrl(): string {
    const track = this.state.track;
    return track === null ? '' : track.coverUrl;
  }

  private displayTitle(): ResourceStr {
    const track = this.state.track;
    if (track === null || track.title.trim().length === 0) {
      return $r('app.string.player_unknown_track');
    }
    return track.title.trim();
  }

  private displayArtist(): ResourceStr {
    const track = this.state.track;
    if (track === null || track.artist.trim().length === 0) {
      return $r('app.string.player_unknown_artist');
    }
    return track.artist.trim();
  }

  private showLyrics(): boolean {
    return this.settingsStore === null ? true : this.settingsStore.snapshot.showLyrics;
  }

  /**
   * 是否有可预览的歌词：`ready`（带时间轴）与 `unsynced`（只有文本）都显示两行，
   * 其余状态（加载中 / 空 / 出错）回落到「查看完整歌词」入口。
   */
  private hasLyricPreview(): boolean {
    const lyrics = this.lyricState;
    if (lyrics === null || lyrics.lines.length === 0) {
      return false;
    }
    return lyrics.status === 'ready' || lyrics.status === 'unsynced';
  }

  /** 当前显示行的下标；首行之前（或未同步）回落到第一行，避免出现空白块。 */
  private lyricBaseIndex(): number {
    const lyrics = this.lyricState;
    if (lyrics === null || lyrics.lines.length === 0) {
      return -1;
    }
    return lyrics.currentIndex < 0 ? 0 : lyrics.currentIndex;
  }

  private currentLyricText(): string {
    const lyrics = this.lyricState;
    const index = this.lyricBaseIndex();
    if (lyrics === null || index < 0 || index >= lyrics.lines.length) {
      return '';
    }
    return lyrics.lines[index].text.trim();
  }

  private nextLyricText(): string {
    const lyrics = this.lyricState;
    const index = this.lyricBaseIndex();
    if (lyrics === null || index < 0 || index + 1 >= lyrics.lines.length) {
      return '';
    }
    return lyrics.lines[index + 1].text.trim();
  }

  private errorTitle(): ResourceStr {
    return playbackErrorTitle(this.errorKind());
  }

  private errorMessage(): ResourceStr {
    return playbackErrorMessage(this.errorKind());
  }

  private errorKind(): PlaybackErrorKind {
    return playbackErrorPresentation(this.state.error).kind;
  }
}

@Component
struct PlayerEmptyContent {
  build() {
    Column({ space: ThemeSpacing.md }) {
      Stack() {
        AppIcon({
          iconKind: AppIconKind.Play,
          iconSize: 30,
          iconColor: ThemeColors.iconOnInset
        })
      }
      .width(68)
      .height(68)
      .borderRadius(34)
      .backgroundColor(ThemeColors.surfaceInset)

      Text($r('app.string.player_empty_title'))
        .id(NativeUiIds.playerEmptyTitle)
        .fontSize(ThemeTypography.sectionTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text($r('app.string.player_empty_hint'))
        .fontSize(ThemeTypography.body)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(NativeUiIds.playerEmpty)
    .width('100%')
    .height('100%')
    .padding({ left: ThemeSpacing.xl, right: ThemeSpacing.xl })
    .justifyContent(FlexAlign.Center)
  }
}
