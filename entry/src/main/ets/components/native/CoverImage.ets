import { image } from '@kit.ImageKit';
import { ImageCacheResult, ImageCacheService } from '../../services/ImageCacheService';
import { ThemeColors, ThemeRadius, ThemeSize } from '../../theme/NativeTheme';
import { CoverImagePhase, CoverLoadReferences, CoverRequestTicket, CoverRequestTracker,
  isLocalCoverUri } from './CoverImageState';

export interface CoverImageProvider {
  loadImage(targetUrl: string): Promise<ImageCacheResult | null>;
  cancel(targetUrl: string): boolean;
}

export class EmptyCoverImageProvider implements CoverImageProvider {
  loadImage(_targetUrl: string): Promise<ImageCacheResult | null> {
    return Promise.resolve(null);
  }

  cancel(_targetUrl: string): boolean {
    return false;
  }
}

export const EMPTY_COVER_PROVIDER: CoverImageProvider = new EmptyCoverImageProvider();

const coverLoadReferences: CoverLoadReferences = new CoverLoadReferences();
const MAX_COVER_DECODE_SCALE: number = 4;

@Component
export struct CoverImage {
  imageCache: CoverImageProvider = EMPTY_COVER_PROVIDER;
  @Prop @Watch('onCoverUrlChanged') coverUrl: string = '';
  @Prop coverSize: number = ThemeSize.coverSize;
  @Prop cornerRadius: number = ThemeSize.coverCornerRadius;

  @State private phase: CoverImagePhase = CoverImagePhase.Loading;
  @State private pixelMap: image.PixelMap | null = null;
  @State private localLoadFailed: boolean = false;
  private readonly requestTracker: CoverRequestTracker = new CoverRequestTracker();
  private openRequestUrl: string = '';
  private visible: boolean = false;

  aboutToAppear(): void {
    this.visible = true;
    this.beginRequest();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.stopRequest();
    // releasePixelMap 会同步写 @State pixelMap；销毁期间写状态会触发重建 / 140110。
    setTimeout((): void => {
      void this.releasePixelMap();
    }, 0);
  }

  build() {
    Stack() {
      if (isLocalCoverUri(this.coverUrl) && !this.localLoadFailed) {
        Image(this.coverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .draggable(false)
          .onError(() => {
            this.localLoadFailed = true;
          })
      } else if (this.phase === CoverImagePhase.Ready && this.pixelMap !== null && !this.localLoadFailed) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
      } else if (this.phase === CoverImagePhase.Failed || this.localLoadFailed) {
        Text('!')
          .fontSize(this.placeholderSize())
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textSecondary)
          .opacity(0.72)
      } else {
        LoadingProgress()
          .width(this.placeholderSize())
          .height(this.placeholderSize())
          .color(ThemeColors.textSecondary)
      }
    }
    .width(this.safeCoverSize())
    .height(this.safeCoverSize())
    .aspectRatio(ThemeSize.coverAspectRatio)
    .borderRadius(this.safeCornerRadius())
    .clip(true)
    .backgroundColor(this.phase === CoverImagePhase.Failed || this.localLoadFailed ?
      ThemeColors.accentSoft : ThemeColors.surfaceInset)
  }

  private onCoverUrlChanged(): void {
    if (!this.visible || this.requestTracker.isActiveUrl(this.coverUrl)) {
      return;
    }
    this.stopRequest();
    void this.releasePixelMap();
    this.beginRequest();
  }

  private beginRequest(): void {
    const targetUrl = this.coverUrl.trim();
    this.localLoadFailed = false;
    if (isLocalCoverUri(targetUrl)) {
      // 本地相册封面由 Image 直接解码，不进入网络图片缓存 / provider。
      this.requestTracker.invalidate();
      void this.releasePixelMap();
      this.phase = CoverImagePhase.Ready;
      return;
    }
    this.phase = CoverImagePhase.Loading;
    if (targetUrl.length === 0) {
      this.requestTracker.invalidate();
      this.phase = CoverImagePhase.Failed;
      return;
    }
    const ticket = this.requestTracker.begin(targetUrl);
    this.openRequestUrl = targetUrl;
    coverLoadReferences.retain(targetUrl);
    void this.loadCover(ticket);
  }

  private async loadCover(ticket: CoverRequestTicket): Promise<void> {
    let source: image.ImageSource | null = null;
    try {
      const result = await this.imageCache.loadImage(ticket.url);
      if (result === null) {
        this.finishRequest(ticket, false);
        return;
      }
      source = image.createImageSource(result.data);
      const decodeSize = this.decodeSize();
      const info = await source.getImageInfo();
      const longest = Math.max(info.size.width, info.size.height);
      const scale = longest > decodeSize ? decodeSize / longest : 1;
      const options: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        }
      };
      const nextPixelMap = await source.createPixelMap(options);
      if (!this.requestTracker.isCurrent(ticket)) {
        await this.releaseImage(nextPixelMap);
        return;
      }
      const previousPixelMap = this.pixelMap;
      this.pixelMap = nextPixelMap;
      this.finishRequest(ticket, true);
      if (previousPixelMap !== null) {
        await this.releaseImage(previousPixelMap);
      }
    } catch (error) {
      this.finishRequest(ticket, false);
    } finally {
      if (source !== null) {
        await this.releaseImageSource(source);
      }
    }
  }

  private finishRequest(ticket: CoverRequestTicket, loaded: boolean): void {
    if (!this.requestTracker.isCurrent(ticket)) {
      return;
    }
    this.closeRequest(ticket.url);
    this.phase = loaded ? CoverImagePhase.Ready : CoverImagePhase.Failed;
  }

  private stopRequest(): void {
    const targetUrl = this.openRequestUrl;
    this.requestTracker.invalidate();
    this.closeRequest(targetUrl);
  }

  private closeRequest(targetUrl: string): void {
    if (targetUrl.length === 0 || targetUrl !== this.openRequestUrl) {
      return;
    }
    this.openRequestUrl = '';
    if (coverLoadReferences.release(targetUrl) === 0) {
      this.imageCache.cancel(targetUrl);
    }
  }

  private async releasePixelMap(): Promise<void> {
    const current = this.pixelMap;
    this.pixelMap = null;
    if (current !== null) {
      await this.releaseImage(current);
    }
  }

  private async releaseImage(pixelMap: image.PixelMap): Promise<void> {
    try {
      await pixelMap.release();
    } catch (error) {
      // PixelMap cleanup is best effort after the visual state has already changed.
    }
  }

  private async releaseImageSource(source: image.ImageSource): Promise<void> {
    try {
      await source.release();
    } catch (error) {
      // ImageSource cleanup is best effort and must not change the cover state.
    }
  }

  private safeCoverSize(): number {
    return Number.isFinite(this.coverSize) ? Math.max(1, this.coverSize) : ThemeSize.coverSize;
  }

  private safeCornerRadius(): number {
    if (!Number.isFinite(this.cornerRadius)) {
      return ThemeRadius.sm;
    }
    return Math.max(0, this.cornerRadius);
  }

  private decodeSize(): number {
    return Math.max(1, Math.ceil(this.safeCoverSize() * MAX_COVER_DECODE_SCALE));
  }

  private placeholderSize(): number {
    return Math.min(ThemeSize.coverPlaceholderMark, this.safeCoverSize() * 0.5);
  }
}
