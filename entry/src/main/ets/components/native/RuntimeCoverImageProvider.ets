import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import { ImageCacheResult } from '../../services/ImageCacheService';
import { CoverImageProvider } from './CoverImage';

/**
 * Bridges CoverImage to the runtime image cache.
 *
 * Every list that renders covers must inject this provider: the default
 * EMPTY_COVER_PROVIDER resolves every request to null, which makes CoverImage
 * fall back to the "!" placeholder.
 */
export class RuntimeCoverImageProvider implements CoverImageProvider {
  private readonly runtime: NativeAppRuntime;

  constructor(runtime: NativeAppRuntime) {
    this.runtime = runtime;
  }

  async loadImage(targetUrl: string): Promise<ImageCacheResult | null> {
    const image = await this.runtime.loadImage(targetUrl);
    if (image === null) {
      return null;
    }
    return {
      mime: image.mime,
      data: image.data,
      source: 'network'
    };
  }

  cancel(_targetUrl: string): boolean {
    return false;
  }
}
