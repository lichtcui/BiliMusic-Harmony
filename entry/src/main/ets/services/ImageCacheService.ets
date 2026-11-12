import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { url } from '@kit.ArkTS';
import { BiliHttpClient, BiliImage } from './BiliHttpClient';
import { readAtomicText, writeAtomicText } from '../util/AtomicJson';
import { NativeError, toAppError } from '../util/Errors';

const DOMAIN = 0x424D;
const TAG = 'WispMusicImageCache';
const IMAGE_HOSTS: string[] = ['hdslb.com', 'biliimg.com'];

export const DEFAULT_IMAGE_MAX_BYTES = 8 * 1024 * 1024;
export const DEFAULT_IMAGE_MEMORY_MAX_BYTES = 24 * 1024 * 1024;
export const DEFAULT_IMAGE_DISK_MAX_BYTES = 128 * 1024 * 1024;
export const DEFAULT_IMAGE_MAX_CONCURRENT = 4;
export const DEFAULT_IMAGE_TIMEOUT_MS = 10_000;

export interface ImageFetcher {
  requestImage(targetUrl: string): Promise<BiliImage>;
}

export class HttpImageFetcher implements ImageFetcher {
  private readonly http: BiliHttpClient;

  constructor(http: BiliHttpClient) {
    this.http = http;
  }

  requestImage(targetUrl: string): Promise<BiliImage> {
    return this.http.requestImage(targetUrl);
  }
}

export interface ImageDiskEntry {
  mime: string;
  data: ArrayBuffer;
}

export interface ImageDiskStats {
  bytes: number;
  entries: number;
}

export interface ImageDiskCache {
  read(key: string): Promise<ImageDiskEntry | null>;
  write(key: string, mime: string, data: ArrayBuffer): Promise<void>;
  remove(key: string): Promise<void>;
  clear(): Promise<void>;
  stats(): Promise<ImageDiskStats>;
}

export interface ImageCacheStats extends ImageDiskStats {
  memoryBytes: number;
  memoryEntries: number;
}

export interface ImageCacheResult {
  mime: string;
  data: ArrayBuffer;
  source: 'memory' | 'disk' | 'network';
}

interface MemoryImageEntry {
  mime: string;
  data: ArrayBuffer;
}

interface DiskImageMetadata {
  mime: string;
  bytes: number;
}

interface DiskImageFile {
  key: string;
  size: number;
  mtime: number;
}

interface SlotWaiter {
  task: ImageLoadTask;
  resolve: (granted: boolean) => void;
}

class ImageLoadTask {
  readonly key: string;
  cancelled: boolean = false;
  private cancelCallback: (() => void) | null = null;

  constructor(key: string) {
    this.key = key;
  }

  setCancelCallback(callback: (() => void) | null): void {
    this.cancelCallback = callback;
  }

  cancel(): void {
    this.cancelled = true;
    if (this.cancelCallback !== null) {
      this.cancelCallback();
    }
  }
}

export class MemoryImageDiskCache implements ImageDiskCache {
  private readonly entries: Map<string, ImageDiskEntry> = new Map<string, ImageDiskEntry>();
  private readonly maxBytes: number;

  constructor(maxBytes: number = DEFAULT_IMAGE_DISK_MAX_BYTES) {
    this.maxBytes = Math.max(0, maxBytes);
  }

  async read(key: string): Promise<ImageDiskEntry | null> {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return null;
    }
    return {
      mime: entry.mime,
      data: entry.data.slice(0)
    };
  }

  async write(key: string, mime: string, data: ArrayBuffer): Promise<void> {
    this.entries.delete(key);
    this.entries.set(key, {
      mime: mime,
      data: data.slice(0)
    });
    while (this.entries.size > 0) {
      let bytes = 0;
      this.entries.forEach((entry: ImageDiskEntry): void => {
        bytes += entry.data.byteLength;
      });
      if (bytes <= this.maxBytes) {
        break;
      }
      let oldestKey = '';
      for (const candidate of this.entries.keys()) {
        oldestKey = candidate;
        break;
      }
      this.entries.delete(oldestKey);
    }
  }

  async remove(key: string): Promise<void> {
    this.entries.delete(key);
  }

  async clear(): Promise<void> {
    this.entries.clear();
  }

  async stats(): Promise<ImageDiskStats> {
    let bytes = 0;
    this.entries.forEach((entry: ImageDiskEntry): void => {
      bytes += entry.data.byteLength;
    });
    return {
      bytes: bytes,
      entries: this.entries.size
    };
  }
}

export class FileImageDiskCache implements ImageDiskCache {
  private readonly directory: string;
  private readonly maxBytes: number;
  /**
   * 估算的当前占用（图片 + sidecar 字节）。-1 表示还没量过：
   * 首次写入时扫描一次目录初始化，之后每写一张只做加减，超限才真正扫描淘汰。
   * 这样常规命中缓存时不再「写一张 → 全目录 stat 两遍」。
   */
  private trackedBytes: number = -1;

  constructor(directory: string, maxBytes: number = DEFAULT_IMAGE_DISK_MAX_BYTES) {
    this.directory = directory;
    this.maxBytes = Math.max(DEFAULT_IMAGE_MAX_BYTES, maxBytes);
  }

  async read(key: string): Promise<ImageDiskEntry | null> {
    const metadataPath = this.metadataPath(key);
    const imagePath = this.imagePath(key);
    try {
      const raw = readAtomicText(metadataPath);
      if (raw === null) {
        return null;
      }
      const metadata = parseMetadata(raw);
      if (metadata === null || !isSupportedImageMime(metadata.mime) || metadata.bytes <= 0 ||
        metadata.bytes > DEFAULT_IMAGE_MAX_BYTES) {
        return null;
      }
      const stat = fs.statSync(imagePath);
      if (stat.size !== metadata.bytes || stat.size > DEFAULT_IMAGE_MAX_BYTES) {
        return null;
      }
      const file = fs.openSync(imagePath, fs.OpenMode.READ_ONLY);
      try {
        const data = new ArrayBuffer(stat.size);
        const read = fs.readSync(file.fd, data);
        if (read !== stat.size) {
          return null;
        }
        return {
          mime: metadata.mime,
          data: data
        };
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'disk read failed code=%{public}s', toAppError(error as Object).code);
      return null;
    }
  }

  async write(key: string, mime: string, data: ArrayBuffer): Promise<void> {
    if (!isSupportedImageMime(mime) || data.byteLength <= 0 || data.byteLength > DEFAULT_IMAGE_MAX_BYTES) {
      throw new NativeError('image.invalidResponse', '图片数据不符合缓存要求。');
    }
    this.ensureDirectory();
    const imagePath = this.imagePath(key);
    const metadataPath = this.metadataPath(key);
    const metadata: DiskImageMetadata = {
      mime: mime,
      bytes: data.byteLength
    };
    const metadataJson = JSON.stringify(metadata);
    try {
      await writeBytesAtomically(imagePath, data);
      await writeAtomicText(metadataPath, metadataJson);
      // 只在估算超限时才做全目录扫描 + 淘汰；写入本身不再顺带 prune。
      // 同一 key 覆盖写会让估算偏高（旧文件已计入），最多提前一次淘汰，不会漏淘汰。
      if (this.trackedBytes < 0) {
        // 首次写入（或清理过）：此时新文件已落盘，直接量一次总量即可。
        this.trackedBytes = this.measureTotal();
      } else {
        this.trackedBytes += data.byteLength + metadataJson.length;
      }
      if (this.trackedBytes > this.maxBytes) {
        this.prune();
      }
    } catch (error) {
      this.removeQuietly(imagePath);
      this.removeQuietly(metadataPath);
      this.removeQuietly(`${imagePath}.part`);
      if (error instanceof Error) {
        throw error;
      }
      throw new NativeError('image.cacheWriteFailed', '图片缓存写入失败。', true);
    }
  }

  async remove(key: string): Promise<void> {
    this.removeQuietly(this.imagePath(key));
    this.removeQuietly(this.metadataPath(key));
    // 被删掉的字节数未知，标记估算失效，下次写入时重新量。
    this.trackedBytes = -1;
  }

  async clear(): Promise<void> {
    this.trackedBytes = -1;
    try {
      if (!fs.accessSync(this.directory)) {
        return;
      }
      const names = fs.listFileSync(this.directory);
      for (const name of names) {
        if (name.indexOf('.img') >= 0 || name.indexOf('.json') >= 0 || name.indexOf('.part') >= 0) {
          this.removeStrict(`${this.directory}/${name}`);
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'disk clear failed code=%{public}s', toAppError(error as Object).code);
      if (error instanceof NativeError) {
        throw error;
      }
      throw new NativeError('image.cacheClearFailed', '图片缓存清理失败。', true);
    }
  }

  async stats(): Promise<ImageDiskStats> {
    try {
      if (!fs.accessSync(this.directory)) {
        return {
          bytes: 0,
          entries: 0
        };
      }
      const files = this.imageFiles(true);
      let bytes = 0;
      for (const file of files) {
        bytes += file.size + this.metadataBytes(file.key);
      }
      // 统计顺便校准估算值：下一次写入不必再全目录扫描。
      this.trackedBytes = bytes;
      return {
        bytes: bytes,
        entries: files.length
      };
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'disk stats failed');
      if (error instanceof NativeError) {
        throw error;
      }
      throw new NativeError('image.cacheStatsFailed', '无法读取图片缓存信息。', true);
    }
  }

  /** 全目录统计图片 + sidecar 的总字节数（只在估算失效或需要淘汰时调用）。 */
  private measureTotal(): number {
    const files = this.imageFiles();
    let total = 0;
    for (const file of files) {
      total += file.size + this.metadataBytes(file.key);
    }
    return total;
  }

  private prune(): void {
    const files = this.imageFiles();
    let total = 0;
    for (const file of files) {
      total += file.size + this.metadataBytes(file.key);
    }
    files.sort((left: DiskImageFile, right: DiskImageFile): number => left.mtime - right.mtime);
    while (total > this.maxBytes && files.length > 0) {
      const oldest = files.shift();
      if (oldest === undefined) {
        break;
      }
      // stats() 把 sidecar 也算进 total，删除时必须一并扣减，否则会多淘汰文件。
      const sidecarBytes = this.metadataBytes(oldest.key);
      this.removeQuietly(this.imagePath(oldest.key));
      this.removeQuietly(this.metadataPath(oldest.key));
      total -= oldest.size + sidecarBytes;
    }
    this.trackedBytes = total;
  }

  private metadataBytes(key: string): number {
    try {
      return fs.statSync(this.metadataPath(key)).size;
    } catch (error) {
      // The image remains usable even when its sidecar is missing.
      return 0;
    }
  }

  private imageFiles(strict: boolean = false): DiskImageFile[] {
    const result: DiskImageFile[] = [];
    try {
      const names = fs.listFileSync(this.directory);
      for (const name of names) {
        if (!name.endsWith('.img')) {
          continue;
        }
        const key = name.slice(0, -4);
        try {
          const stat = fs.statSync(`${this.directory}/${name}`);
          result.push({
            key: key,
            size: stat.size,
            mtime: stat.mtime
          });
        } catch (error) {
          // A file that disappears during a listing is simply not cached.
        }
      }
    } catch (error) {
      if (strict) {
        throw cacheFailure('image.cacheStatsFailed', error as Object);
      }
      return result;
    }
    return result;
  }

  private ensureDirectory(): void {
    if (!fs.accessSync(this.directory)) {
      fs.mkdirSync(this.directory, true);
    }
  }

  private imagePath(key: string): string {
    return `${this.directory}/${key}.img`;
  }

  private metadataPath(key: string): string {
    return `${this.directory}/${key}.json`;
  }

  private removeQuietly(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'disk remove failed');
    }
  }

  private removeStrict(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      fs.unlinkSync(path);
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code === 13900002) {
        return;
      }
      throw cacheFailure('image.cacheClearFailed', error as Object);
    }
  }
}

export class ImageCacheService {
  private readonly fetcher: ImageFetcher;
  private readonly disk: ImageDiskCache;
  private readonly memoryMaxBytes: number;
  private readonly maxConcurrent: number;
  private readonly memory: Map<string, MemoryImageEntry> = new Map<string, MemoryImageEntry>();
  private readonly pending: Map<string, Promise<ImageCacheResult | null>> =
    new Map<string, Promise<ImageCacheResult | null>>();
  private readonly pendingTasks: Map<string, ImageLoadTask> = new Map<string, ImageLoadTask>();
  private readonly waiters: SlotWaiter[] = [];
  private availableSlots: number;
  private memoryBytes: number = 0;
  private generation: number = 0;
  private diskChain: Promise<void> = Promise.resolve();
  private clearPromise: Promise<ImageCacheStats> | null = null;
  private closed: boolean = false;

  constructor(fetcher: ImageFetcher, disk: ImageDiskCache,
    memoryMaxBytes: number = DEFAULT_IMAGE_MEMORY_MAX_BYTES,
    maxConcurrent: number = DEFAULT_IMAGE_MAX_CONCURRENT) {
    this.fetcher = fetcher;
    this.disk = disk;
    this.memoryMaxBytes = Math.max(0, memoryMaxBytes);
    this.maxConcurrent = Math.max(1, Math.floor(maxConcurrent));
    this.availableSlots = this.maxConcurrent;
  }

  loadImage(targetUrl: string, timeoutMs: number = DEFAULT_IMAGE_TIMEOUT_MS): Promise<ImageCacheResult | null> {
    if (this.closed || !isAllowedBiliImageUrl(targetUrl)) {
      return Promise.resolve(null);
    }
    let key = '';
    try {
      key = imageCacheKey(targetUrl);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'cache key failed code=%{public}s', toAppError(error as Object).code);
      return Promise.resolve(null);
    }
    const existing = this.pending.get(key);
    if (existing !== undefined) {
      return existing;
    }
    const task = new ImageLoadTask(key);
    const pending = this.loadWithDeadline(targetUrl, key, task, timeoutMs);
    this.pending.set(key, pending);
    this.pendingTasks.set(key, task);
    pending.then((): void => {
      this.removePending(key, pending, task);
    }, (): void => {
      this.removePending(key, pending, task);
    });
    return pending;
  }

  cancel(targetUrl: string): boolean {
    if (!isAllowedBiliImageUrl(targetUrl)) {
      return false;
    }
    let key = '';
    try {
      key = imageCacheKey(targetUrl);
    } catch (error) {
      return false;
    }
    const task = this.pendingTasks.get(key);
    if (task === undefined) {
      return false;
    }
    task.cancel();
    return true;
  }

  cancelAll(): void {
    this.pendingTasks.forEach((task: ImageLoadTask): void => {
      task.cancel();
    });
  }

  async stats(): Promise<ImageCacheStats> {
    let disk: ImageDiskStats = { bytes: 0, entries: 0 };
    try {
      disk = await this.disk.stats();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'cache stats failed code=%{public}s', toAppError(error as Object).code);
      throw cacheFailure('image.cacheStatsFailed', error);
    }
    return {
      bytes: disk.bytes,
      entries: disk.entries,
      memoryBytes: this.memoryBytes,
      memoryEntries: this.memory.size
    };
  }

  clear(): Promise<ImageCacheStats> {
    if (this.clearPromise !== null) {
      return this.clearPromise;
    }
    this.generation += 1;
    this.cancelAll();
    this.clearMemory();
    const clear = this.diskChain.catch((): void => {}).then((): Promise<void> => this.disk.clear());
    this.diskChain = clear.catch((): void => {});
    const pending: Promise<ImageCacheStats> = clear
      .then((): Promise<ImageCacheStats> => this.stats())
      .catch((error: Object): ImageCacheStats => {
        hilog.warn(DOMAIN, TAG, 'cache clear failed code=%{public}s', toAppError(error).code);
        throw cacheFailure('image.cacheClearFailed', error);
      });
    this.clearPromise = pending;
    pending.then((): void => {
      if (this.clearPromise === pending) {
        this.clearPromise = null;
      }
    }, (): void => {
      if (this.clearPromise === pending) {
        this.clearPromise = null;
      }
    });
    return pending;
  }

  async shutdown(): Promise<void> {
    this.closed = true;
    this.generation += 1;
    this.cancelAll();
    this.clearMemory();
    try {
      await this.diskChain;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'disk writes did not finish during shutdown');
    }
  }

  private loadWithDeadline(targetUrl: string, key: string, task: ImageLoadTask,
    timeoutMs: number): Promise<ImageCacheResult | null> {
    return new Promise<ImageCacheResult | null>((resolve: (value: ImageCacheResult | null) => void): void => {
      let settled = false;
      let timer = 0;
      const finish = (value: ImageCacheResult | null): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        task.setCancelCallback(null);
        resolve(value);
      };
      task.setCancelCallback((): void => {
        finish(null);
      });
      const safeTimeout = Number.isFinite(timeoutMs) ? Math.max(1, Math.floor(timeoutMs)) : DEFAULT_IMAGE_TIMEOUT_MS;
      timer = setTimeout((): void => {
        if (!settled) {
          task.cancelled = true;
          hilog.warn(DOMAIN, TAG, 'image load timed out key=%{public}s', key.slice(0, 16));
          finish(null);
        }
      }, safeTimeout);
      void this.loadNetwork(targetUrl, key, task, this.generation).then((value: ImageCacheResult | null): void => {
        finish(task.cancelled ? null : value);
      }, (error: Object): void => {
        hilog.warn(DOMAIN, TAG, 'image load failed code=%{public}s', toAppError(error).code);
        finish(null);
      });
    });
  }

  private async loadNetwork(targetUrl: string, key: string, task: ImageLoadTask,
    generation: number): Promise<ImageCacheResult | null> {
    const memory = this.takeMemory(key);
    if (memory !== null) {
      return {
        mime: memory.mime,
        data: memory.data.slice(0),
        source: 'memory'
      };
    }
    const disk = await this.readDisk(key);
    if (task.cancelled || generation !== this.generation) {
      return null;
    }
    if (disk !== null) {
      this.putMemory(key, disk.mime, disk.data);
      return {
        mime: disk.mime,
        data: disk.data.slice(0),
        source: 'disk'
      };
    }
    const acquired = await this.acquire(task);
    if (!acquired || task.cancelled) {
      if (acquired) {
        this.release();
      }
      return null;
    }
    try {
      if (task.cancelled || generation !== this.generation) {
        return null;
      }
      const image = await this.fetcher.requestImage(targetUrl);
      if (task.cancelled || generation !== this.generation) {
        return null;
      }
      if (image.data.byteLength <= 0) {
        throw new NativeError('image.empty', '图片响应为空。', true);
      }
      if (image.data.byteLength > DEFAULT_IMAGE_MAX_BYTES) {
        throw new NativeError('image.tooLarge', '图片超过大小限制。', false);
      }
      const mime = image.mime.toLowerCase();
      if (!isSupportedImageMime(mime)) {
        throw new NativeError('image.invalidMime', '图片格式不受支持。', false);
      }
      const data = image.data.slice(0);
      this.putMemory(key, mime, data);
      try {
        await this.writeDisk(key, mime, data, generation);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'disk write failed code=%{public}s', toAppError(error as Object).code);
      }
      return {
        mime: mime,
        data: data.slice(0),
        source: 'network'
      };
    } finally {
      this.release();
    }
  }

  private async readDisk(key: string): Promise<ImageDiskEntry | null> {
    try {
      return await this.disk.read(key);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'disk lookup failed code=%{public}s', toAppError(error as Object).code);
      return null;
    }
  }

  private writeDisk(key: string, mime: string, data: ArrayBuffer, generation: number): Promise<void> {
    const write = this.diskChain.catch((): void => {}).then(async (): Promise<void> => {
      if (generation !== this.generation) {
        return;
      }
      await this.disk.write(key, mime, data);
    });
    this.diskChain = write.catch((): void => {});
    return write;
  }

  private takeMemory(key: string): MemoryImageEntry | null {
    const entry = this.memory.get(key);
    if (entry === undefined) {
      return null;
    }
    this.memory.delete(key);
    this.memory.set(key, entry);
    return entry;
  }

  private putMemory(key: string, mime: string, data: ArrayBuffer): void {
    if (data.byteLength <= 0 || data.byteLength > this.memoryMaxBytes) {
      return;
    }
    const previous = this.memory.get(key);
    if (previous !== undefined) {
      this.memoryBytes -= previous.data.byteLength;
    }
    this.memory.set(key, {
      mime: mime,
      data: data.slice(0)
    });
    this.memoryBytes += data.byteLength;
    while (this.memoryBytes > this.memoryMaxBytes && this.memory.size > 0) {
      let oldestKey = '';
      for (const candidate of this.memory.keys()) {
        oldestKey = candidate;
        break;
      }
      if (oldestKey.length === 0) {
        return;
      }
      const oldest = this.memory.get(oldestKey);
      if (oldest !== undefined) {
        this.memoryBytes -= oldest.data.byteLength;
      }
      this.memory.delete(oldestKey);
    }
  }

  private clearMemory(): void {
    this.memory.clear();
    this.memoryBytes = 0;
  }

  private acquire(task: ImageLoadTask): Promise<boolean> {
    if (task.cancelled) {
      return Promise.resolve(false);
    }
    if (this.availableSlots > 0) {
      this.availableSlots -= 1;
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve: (granted: boolean) => void): void => {
      this.waiters.push({
        task: task,
        resolve: resolve
      });
    });
  }

  private release(): void {
    while (this.waiters.length > 0) {
      const waiter = this.waiters.shift();
      if (waiter === undefined) {
        break;
      }
      if (waiter.task.cancelled) {
        waiter.resolve(false);
        continue;
      }
      waiter.resolve(true);
      return;
    }
    this.availableSlots = Math.min(this.maxConcurrent, this.availableSlots + 1);
  }

  private removePending(key: string, pending: Promise<ImageCacheResult | null>, task: ImageLoadTask): void {
    if (this.pending.get(key) === pending) {
      this.pending.delete(key);
    }
    if (this.pendingTasks.get(key) === task) {
      this.pendingTasks.delete(key);
    }
  }
}

export function isAllowedBiliImageUrl(targetUrl: string): boolean {
  const value = targetUrl.trim();
  if (value.length === 0 || value.length > 4096) {
    return false;
  }
  try {
    const parsed = url.URL.parseURL(value);
    if (typeof parsed.protocol === 'string' && typeof parsed.hostname === 'string' &&
      typeof parsed.username === 'string' && typeof parsed.password === 'string' &&
      typeof parsed.port === 'string') {
      return isAllowedParsedImageUrl(parsed.protocol, parsed.username, parsed.password, parsed.port,
        parsed.hostname);
    }
  } catch (error) {
    // Host-side tests do not provide the platform URL service; use the strict fallback below.
  }
  return isAllowedImageUrlWithoutPlatform(value);
}

export function imageCacheKey(targetUrl: string): string {
  const bytes = utf8Bytes(targetUrl.trim());
  const nativeDigest = nativeSha256Hex(bytes);
  return `image-v1-${nativeDigest ?? sha256BytesHex(bytes)}`;
}

export function sha256Hex(input: string): string {
  return sha256BytesHex(utf8Bytes(input));
}

export function isSupportedImageMime(rawMime: string): boolean {
  const mime = rawMime.toLowerCase().split(';')[0].trim();
  return mime.length > 'image/'.length && mime.startsWith('image/') && mime.indexOf(' ') < 0 && mime !== 'image/*';
}

function isPrivateOrLocalHost(host: string): boolean {
  if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) {
    return true;
  }
  if (host.indexOf(':') >= 0 || host.startsWith('[')) {
    return true;
  }
  return /^\d{1,3}(\.\d{1,3}){3}$/u.test(host);
}

function isAllowedParsedImageUrl(protocol: string, username: string, password: string, port: string,
  rawHost: string): boolean {
  if (protocol !== 'https:' || username.length > 0 || password.length > 0 ||
    (port.length > 0 && port !== '443')) {
    return false;
  }
  return isAllowedImageHost(rawHost);
}

function isAllowedImageUrlWithoutPlatform(value: string): boolean {
  const match = value.match(/^https:\/\/([^/?#]+)(?:[/?#]|$)/iu);
  if (match === null) {
    return false;
  }
  const authority = match[1];
  if (authority.length === 0 || authority.indexOf('@') >= 0 || authority.indexOf('\\') >= 0 ||
    authority.startsWith('[')) {
    return false;
  }
  const firstColon = authority.indexOf(':');
  const lastColon = authority.lastIndexOf(':');
  let host = authority;
  if (firstColon >= 0) {
    if (firstColon !== lastColon) {
      return false;
    }
    host = authority.slice(0, firstColon);
    const port = authority.slice(lastColon + 1);
    if (port !== '443') {
      return false;
    }
  }
  return isAllowedImageHost(host);
}

function isAllowedImageHost(rawHost: string): boolean {
  const host = rawHost.toLowerCase();
  if (host.length === 0 || !/^[a-z0-9.-]+$/u.test(host) || isPrivateOrLocalHost(host)) {
    return false;
  }
  return IMAGE_HOSTS.some((domain: string): boolean => host === domain || host.endsWith(`.${domain}`));
}

function utf8Bytes(input: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < input.length; index++) {
    let codePoint = input.charCodeAt(index);
    if (codePoint >= 0xD800 && codePoint <= 0xDBFF) {
      const next = index + 1 < input.length ? input.charCodeAt(index + 1) : 0;
      if (next >= 0xDC00 && next <= 0xDFFF) {
        codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + (next - 0xDC00);
        index += 1;
      } else {
        codePoint = 0xFFFD;
      }
    } else if (codePoint >= 0xDC00 && codePoint <= 0xDFFF) {
      codePoint = 0xFFFD;
    }
    if (codePoint <= 0x7F) {
      bytes.push(codePoint);
    } else if (codePoint <= 0x7FF) {
      bytes.push(0xC0 | (codePoint >>> 6), 0x80 | (codePoint & 0x3F));
    } else if (codePoint <= 0xFFFF) {
      bytes.push(0xE0 | (codePoint >>> 12), 0x80 | ((codePoint >>> 6) & 0x3F),
        0x80 | (codePoint & 0x3F));
    } else {
      bytes.push(0xF0 | (codePoint >>> 18), 0x80 | ((codePoint >>> 12) & 0x3F),
        0x80 | ((codePoint >>> 6) & 0x3F), 0x80 | (codePoint & 0x3F));
    }
  }
  const result = new Uint8Array(bytes.length);
  for (let index = 0; index < bytes.length; index++) {
    result[index] = bytes[index];
  }
  return result;
}

function nativeSha256Hex(bytes: Uint8Array): string | null {
  try {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: bytes });
    const output = digest.digestSync().data;
    if (output.length !== 32) {
      return null;
    }
    return bytesToHex(output);
  } catch (error) {
    return null;
  }
}

function sha256BytesHex(input: Uint8Array): string {
  const constants: number[] = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
  ];
  let h0 = 0x6A09E667;
  let h1 = 0xBB67AE85;
  let h2 = 0x3C6EF372;
  let h3 = 0xA54FF53A;
  let h4 = 0x510E527F;
  let h5 = 0x9B05688C;
  let h6 = 0x1F83D9AB;
  let h7 = 0x5BE0CD19;
  const bitLength = input.length * 8;
  const paddedLength = Math.ceil((input.length + 9) / 64) * 64;
  const padded = new Uint8Array(paddedLength);
  padded.set(input);
  padded[input.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(paddedLength - 8, Math.floor(bitLength / 0x100000000), false);
  view.setUint32(paddedLength - 4, bitLength >>> 0, false);
  const words: number[] = [];
  for (let index = 0; index < 64; index++) {
    words.push(0);
  }
  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let index = 0; index < 16; index++) {
      const position = offset + index * 4;
      words[index] = ((padded[position] << 24) | (padded[position + 1] << 16) |
        (padded[position + 2] << 8) | padded[position + 3]) >>> 0;
    }
    for (let index = 16; index < 64; index++) {
      const previous15 = words[index - 15];
      const previous2 = words[index - 2];
      const sigma0 = rotateRight(previous15, 7) ^ rotateRight(previous15, 18) ^ (previous15 >>> 3);
      const sigma1 = rotateRight(previous2, 17) ^ rotateRight(previous2, 19) ^ (previous2 >>> 10);
      words[index] = (words[index - 16] + sigma0 + words[index - 7] + sigma1) >>> 0;
    }
    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;
    let f = h5;
    let g = h6;
    let h = h7;
    for (let index = 0; index < 64; index++) {
      const sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
      const choice = (e & f) ^ (~e & g);
      const temp1 = (h + sum1 + choice + constants[index] + words[index]) >>> 0;
      const sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
      const majority = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (sum0 + majority) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }
    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
    h5 = (h5 + f) >>> 0;
    h6 = (h6 + g) >>> 0;
    h7 = (h7 + h) >>> 0;
  }
  const result = new Uint8Array(32);
  writeUint32(result, 0, h0);
  writeUint32(result, 4, h1);
  writeUint32(result, 8, h2);
  writeUint32(result, 12, h3);
  writeUint32(result, 16, h4);
  writeUint32(result, 20, h5);
  writeUint32(result, 24, h6);
  writeUint32(result, 28, h7);
  return bytesToHex(result);
}

function rotateRight(value: number, bits: number): number {
  return (value >>> bits) | (value << (32 - bits));
}

function writeUint32(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 24) & 0xFF;
  target[offset + 1] = (value >>> 16) & 0xFF;
  target[offset + 2] = (value >>> 8) & 0xFF;
  target[offset + 3] = value & 0xFF;
}

function bytesToHex(bytes: Uint8Array): string {
  const output: string[] = [];
  for (const value of bytes) {
    output.push(value.toString(16).padStart(2, '0'));
  }
  return output.join('');
}

function cacheFailure(defaultCode: string, error: Object): NativeError {
  if (error instanceof NativeError) {
    return new NativeError(
      error.appError.code,
      error.appError.message,
      error.appError.retryable
    );
  }
  return new NativeError(defaultCode, '', true);
}

function parseMetadata(raw: string): DiskImageMetadata | null {
  try {
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const mime = parsed.mime;
    const bytes = parsed.bytes;
    if (typeof mime !== 'string' || typeof bytes !== 'number' || !Number.isFinite(bytes)) {
      return null;
    }
    return {
      mime: mime.toLowerCase(),
      bytes: Math.floor(bytes)
    };
  } catch (error) {
    return null;
  }
}

async function writeBytesAtomically(path: string, data: ArrayBuffer): Promise<void> {
  const temporary = `${path}.part`;
  let file: fs.File | null = null;
  try {
    if (fs.accessSync(temporary)) {
      fs.unlinkSync(temporary);
    }
    file = await fs.open(temporary, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let written = 0;
    while (written < data.byteLength) {
      const chunk = written === 0 ? data : data.slice(written);
      const count = await fs.write(file.fd, chunk);
      if (count <= 0) {
        throw new NativeError('image.cacheWriteFailed', '图片缓存写入不完整。', true);
      }
      written += count;
    }
    await fs.fsync(file.fd);
  } finally {
    if (file !== null) {
      fs.closeSync(file);
    }
  }
  if (fs.accessSync(path)) {
    fs.unlinkSync(path);
  }
  fs.renameSync(temporary, path);
}
