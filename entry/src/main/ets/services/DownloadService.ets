import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AppError,
  AudioQuality,
  MobileTrack
} from '../types/MobileTypes';
import { appError, NativeError, toAppError } from '../util/Errors';
import {
  arrayValue,
  numberValue,
  objectValue,
  stringValue
} from '../util/Json';
import {
  preserveCorruptFile,
  readAtomicText,
  writeAtomicText
} from '../util/AtomicJson';
import {
  AudioCandidate,
  CatalogService
} from './CatalogService';
import { DownloadedAudioLookup, LocalAudioSource } from './DownloadedAudio';
import { BiliHttpClient } from './BiliHttpClient';

const DOMAIN = 0x424D;
const TAG = 'WispMusicDownloads';

export const DOWNLOAD_INDEX_VERSION: number = 1;
export const DOWNLOAD_DIRECTORY: string = 'downloads-v1';
export const DOWNLOAD_INDEX_FILE: string = 'downloads-v1.json';
/** 最多保留的下载条目；超出后按创建时间淘汰最旧的一条（并删除文件）。 */
export const MAX_DOWNLOADS: number = 500;
/** 单曲下载上限，与播放缓存一致。 */
export const MAX_DOWNLOAD_BYTES: number = 64 * 1024 * 1024;
/**
 * 全部下载的总占用预算；条数与字节任一超限都会从最旧开始淘汰。
 * 500 首常规音质大致 1–2 GB，留出余量后取 4 GB，避免占满用户可用空间。
 */
export const MAX_TOTAL_DOWNLOAD_BYTES: number = 4 * 1024 * 1024 * 1024;

export interface DownloadEntry {
  key: string;
  bvid: string;
  aid: number;
  cid: number;
  title: string;
  artist: string;
  coverUrl: string;
  duration: number;
  bytes: number;
  quality: AudioQuality;
  /** 只保存文件名：绝对路径只在播放器内部使用，不进入持久化快照或 UI。 */
  file: string;
  createdAt: number;
}

export interface DownloadSnapshot {
  version: number;
  entries: DownloadEntry[];
}

export interface DownloadStats {
  bytes: number;
  entries: number;
}

export enum DownloadOutcome {
  Added = 0,
  Exists = 1,
  Failed = 2
}

export interface DownloadResult {
  outcome: DownloadOutcome;
  entry: DownloadEntry | null;
  error: AppError | null;
}

/** 下载索引所需的文件系统边界；主机侧单测注入内存实现。 */
export interface DownloadFileStore {
  exists(path: string): boolean;
  size(path: string): number;
  ensureDirectory(path: string): void;
  deleteFile(path: string): void;
  readText(path: string): string | null;
  writeText(path: string, content: string): Promise<void>;
  preserveCorrupt(path: string): void;
}

class PlatformDownloadFileStore implements DownloadFileStore {
  exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  size(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (error) {
      return 0;
    }
  }

  ensureDirectory(path: string): void {
    if (!this.exists(path)) {
      fs.mkdirSync(path, true);
    }
  }

  deleteFile(path: string): void {
    try {
      if (this.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'download file remove failed');
    }
  }

  readText(path: string): string | null {
    return readAtomicText(path);
  }

  async writeText(path: string, content: string): Promise<void> {
    await writeAtomicText(path, content);
  }

  preserveCorrupt(path: string): void {
    preserveCorruptFile(path);
  }
}

/** 曲目源解析与下载的边界；生产实现复用播放器的解析链路。 */
export interface DownloadTransport {
  candidates(track: MobileTrack, quality: AudioQuality): Promise<AudioCandidate[]>;
  progressive(track: MobileTrack): Promise<AudioCandidate[]>;
  /** 下载成功返回实际写入的字节数。 */
  fetch(url: string, destination: string, maxBytes: number): Promise<number>;
}

class CatalogDownloadTransport implements DownloadTransport {
  private readonly catalog: CatalogService;
  private readonly http: BiliHttpClient;

  constructor(catalog: CatalogService, http: BiliHttpClient) {
    this.catalog = catalog;
    this.http = http;
  }

  async candidates(track: MobileTrack, quality: AudioQuality): Promise<AudioCandidate[]> {
    return this.catalog.audioSource(track, quality);
  }

  async progressive(track: MobileTrack): Promise<AudioCandidate[]> {
    return this.catalog.progressiveAudioSource(track);
  }

  async fetch(url: string, destination: string, maxBytes: number): Promise<number> {
    const downloaded = await this.http.downloadMedia(url, destination, maxBytes);
    return downloaded.bytes;
  }
}

/**
 * 用户主动下载的离线音频。
 *
 * 与 `PlayerService` 的 `audio-v1-*` 播放缓存是两回事：这里落在 `filesDir`，
 * 不会被「清理音频缓存」删除；索引单独原子写入，文件缺失时按未下载处理。
 */
export class DownloadService implements DownloadedAudioLookup {
  private readonly directory: string;
  private readonly indexPath: string;
  private readonly transport: DownloadTransport;
  private readonly qualityProvider: () => AudioQuality;
  private readonly files: DownloadFileStore;
  private readonly now: () => number;
  private readonly maxTotalBytes: number;
  private readonly limitProvider: () => number;
  private entriesValue: DownloadEntry[] = [];
  private writeChain: Promise<void> = Promise.resolve();

  constructor(directory: string, indexPath: string, transport: DownloadTransport,
    qualityProvider: () => AudioQuality, files: DownloadFileStore = new PlatformDownloadFileStore(),
    now: () => number = (): number => Date.now(),
    maxTotalBytes: number = MAX_TOTAL_DOWNLOAD_BYTES,
    limitProvider: () => number = (): number => MAX_DOWNLOADS) {
    this.directory = directory;
    this.indexPath = indexPath;
    this.transport = transport;
    this.qualityProvider = qualityProvider;
    this.files = files;
    this.now = now;
    this.maxTotalBytes = maxTotalBytes;
    this.limitProvider = limitProvider;
    try {
      this.files.ensureDirectory(this.directory);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'download directory create failed');
    }
    this.entriesValue = sanitizeDownloadSnapshot(this.loadRaw(), this.maxTotalBytes,
      this.downloadLimit()).entries;
    this.dropMissingFiles();
  }

  static fromRuntime(filesDir: string, catalog: CatalogService, http: BiliHttpClient,
    qualityProvider: () => AudioQuality,
    limitProvider: () => number = (): number => MAX_DOWNLOADS): DownloadService {
    return new DownloadService(
      `${filesDir}/${DOWNLOAD_DIRECTORY}`,
      `${filesDir}/${DOWNLOAD_INDEX_FILE}`,
      new CatalogDownloadTransport(catalog, http),
      qualityProvider,
      new PlatformDownloadFileStore(),
      (): number => Date.now(),
      MAX_TOTAL_DOWNLOAD_BYTES,
      limitProvider
    );
  }

  entries(): DownloadEntry[] {
    return this.entriesValue.slice();
  }

  entryFor(key: string): DownloadEntry | null {
    for (const entry of this.entriesValue) {
      if (entry.key === key) {
        return cloneEntry(entry);
      }
    }
    return null;
  }

  isDownloaded(key: string): boolean {
    return this.local(key) !== null;
  }

  /** 播放器专用：返回可直接打开的文件信息；文件缺失时视为未下载。 */
  local(key: string): LocalAudioSource | null {
    const entry = this.entryFor(key);
    if (entry === null) {
      return null;
    }
    const path = `${this.directory}/${entry.file}`;
    const bytes = this.files.size(path);
    if (!this.files.exists(path) || bytes <= 0) {
      return null;
    }
    if (entry.bytes !== bytes) {
      entry.bytes = bytes;
    }
    return {
      path: path,
      bytes: bytes
    };
  }

  stats(): DownloadStats {
    let bytes = 0;
    for (const entry of this.entriesValue) {
      bytes += entry.bytes;
    }
    return {
      bytes: bytes,
      entries: this.entriesValue.length
    };
  }

  async download(track: MobileTrack): Promise<DownloadResult> {
    const key = track.key.trim();
    if (key.length === 0) {
      return failedResult('download.invalidTrack', true);
    }
    const existing = this.local(key);
    if (existing !== null) {
      return {
        outcome: DownloadOutcome.Exists,
        entry: this.entryFor(key),
        error: null
      };
    }
    const quality = this.qualityProvider();
    const candidates = await this.resolveCandidates(track, quality);
    let lastError: Object | null = null;
    for (const candidate of candidates) {
      const fileName = downloadFileName(key, candidate);
      const path = `${this.directory}/${fileName}`;
      try {
        this.files.ensureDirectory(this.directory);
        const bytes = await this.transport.fetch(candidate.url, path, MAX_DOWNLOAD_BYTES);
        if (bytes <= 0) {
          throw new NativeError('download.writeFailed', '', true);
        }
        const entry = buildEntry(track, bytes, quality, fileName, this.now());
        await this.commit(entry);
        hilog.info(DOMAIN, TAG, 'download added quality=%{public}s bytes=%{public}d',
          quality, bytes);
        return {
          outcome: DownloadOutcome.Added,
          entry: cloneEntry(entry),
          error: null
        };
      } catch (error) {
        lastError = error as Object;
        this.files.deleteFile(path);
      }
    }
    const failure: AppError = lastError === null
      ? appError('player.noAudioStream', '', true)
      : toAppError(lastError);
    hilog.warn(DOMAIN, TAG, 'download failed code=%{public}s', failure.code);
    return {
      outcome: DownloadOutcome.Failed,
      entry: null,
      error: failure
    };
  }

  async remove(keys: string[]): Promise<number> {
    const targets: Set<string> = new Set<string>();
    for (const key of keys) {
      const trimmed = key.trim();
      if (trimmed.length > 0) {
        targets.add(trimmed);
      }
    }
    if (targets.size === 0) {
      return 0;
    }
    let removed = 0;
    const kept: DownloadEntry[] = [];
    for (const entry of this.entriesValue) {
      if (targets.has(entry.key)) {
        this.files.deleteFile(`${this.directory}/${entry.file}`);
        removed++;
      } else {
        kept.push(entry);
      }
    }
    if (removed === 0) {
      return 0;
    }
    this.entriesValue = kept;
    await this.persist();
    hilog.info(DOMAIN, TAG, 'downloads removed count=%{public}d', removed);
    return removed;
  }

  async clear(): Promise<number> {
    const removed = this.entriesValue.length;
    if (removed === 0) {
      return 0;
    }
    for (const entry of this.entriesValue) {
      this.files.deleteFile(`${this.directory}/${entry.file}`);
    }
    this.entriesValue = [];
    await this.persist();
    hilog.info(DOMAIN, TAG, 'downloads cleared count=%{public}d', removed);
    return removed;
  }

  private async resolveCandidates(track: MobileTrack, quality: AudioQuality): Promise<AudioCandidate[]> {
    try {
      const candidates = await this.transport.candidates(track, quality);
      if (candidates.length > 0) {
        return candidates;
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'download source failed code=%{public}s',
        toAppError(error as Object).code);
    }
    try {
      return await this.transport.progressive(track);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'download fallback source failed code=%{public}s',
        toAppError(error as Object).code);
      return [];
    }
  }

  private async commit(entry: DownloadEntry): Promise<void> {
    const next: DownloadEntry[] = [];
    for (const existing of this.entriesValue) {
      if (existing.key !== entry.key) {
        next.push(existing);
        continue;
      }
      if (existing.file !== entry.file) {
        this.files.deleteFile(`${this.directory}/${existing.file}`);
      }
    }
    next.unshift(entry);
    this.evictToLimits(next, true);
    this.entriesValue = next;
    await this.persist();
  }

  /**
   * 设置里调低「最多存储」后由宿主调用：立即按当前条数 / 字节上限清理并落盘，
   * 不等下一次下载才缩容。返回本次删除的条目数。
   */
  async applyLimit(): Promise<number> {
    const kept = this.entriesValue.slice();
    const removed = this.evictToLimits(kept, false);
    if (removed === 0) {
      return 0;
    }
    this.entriesValue = kept;
    await this.persist();
    hilog.info(DOMAIN, TAG, 'downloads trimmed to limit removed=%{public}d', removed);
    return removed;
  }

  /**
   * 条数或总字节任一超限都从最旧淘汰并删除文件。
   * `protectNewest` 为真时保留 `entries[0]`（刚下载成功的条目），避免预算异常时下完即删。
   */
  private evictToLimits(entries: DownloadEntry[], protectNewest: boolean): number {
    const maxEntries = this.downloadLimit();
    let totalBytes = 0;
    for (const kept of entries) {
      totalBytes += kept.bytes;
    }
    let removed = 0;
    while (entries.length > (protectNewest ? 1 : 0) &&
      (entries.length > maxEntries || totalBytes > this.maxTotalBytes)) {
      const evicted = entries.pop();
      if (evicted === undefined) {
        break;
      }
      totalBytes -= evicted.bytes;
      this.files.deleteFile(`${this.directory}/${evicted.file}`);
      removed++;
    }
    return removed;
  }

  /** 下载条数上限由设置层提供；非法值回落到常量默认，保证索引清洗时仍有上限。 */
  private downloadLimit(): number {
    const value = Math.floor(this.limitProvider());
    return value > 0 ? value : MAX_DOWNLOADS;
  }

  private persist(): Promise<void> {
    const snapshot: DownloadSnapshot = {
      version: DOWNLOAD_INDEX_VERSION,
      entries: this.entriesValue.map((entry: DownloadEntry): DownloadEntry => cloneEntry(entry))
    };
    const payload = JSON.stringify(snapshot);
    const run: Promise<void> = this.writeChain.then(async (): Promise<void> => {
      try {
        await this.files.writeText(this.indexPath, payload);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'download index write failed');
        throw new NativeError('download.writeFailed', '', true);
      }
    });
    // 上一次写入失败不能卡死后续写入：链本身吞掉错误，调用方拿到原始 promise。
    this.writeChain = run.catch((): void => {});
    return run;
  }

  private loadRaw(): Record<string, Object> {
    const text = this.files.readText(this.indexPath);
    if (text === null) {
      return {};
    }
    try {
      return objectValue(JSON.parse(text) as Object);
    } catch (error) {
      this.files.preserveCorrupt(this.indexPath);
      hilog.warn(DOMAIN, TAG, 'download index corrupt');
      return {};
    }
  }

  /** 索引里有、磁盘上已经没有的条目直接丢掉，避免下载页出现打不开的行。 */
  private dropMissingFiles(): void {
    const kept: DownloadEntry[] = [];
    let dropped = 0;
    for (const entry of this.entriesValue) {
      const path = `${this.directory}/${entry.file}`;
      if (this.files.exists(path) && this.files.size(path) > 0) {
        kept.push(entry);
      } else {
        dropped++;
      }
    }
    if (dropped === 0) {
      return;
    }
    this.entriesValue = kept;
    hilog.warn(DOMAIN, TAG, 'download entries dropped count=%{public}d', dropped);
    this.persist().catch((): void => {});
  }
}

export function downloadFileName(key: string, candidate: AudioCandidate): string {
  const extension = candidate.source === 'dash' ? 'm4s' : 'mp4';
  return `dl-v1-${safeDownloadKey(key)}-${candidate.id}.${extension}`;
}

function safeDownloadKey(key: string): string {
  const sanitized = key.replace(/[^a-zA-Z0-9-]/g, '-');
  return sanitized.length > 80 ? sanitized.slice(0, 80) : sanitized;
}

function buildEntry(track: MobileTrack, bytes: number, quality: AudioQuality,
  fileName: string, createdAt: number): DownloadEntry {
  return {
    key: track.key,
    bvid: sanitizeText(track.bvid, 64),
    aid: sanitizeInteger(track.aid),
    cid: sanitizeInteger(track.cid),
    title: sanitizeText(track.title, 300),
    artist: sanitizeText(track.artist, 200),
    coverUrl: track.coverUrl.startsWith('https://') ? track.coverUrl.slice(0, 1024) : '',
    duration: sanitizeInteger(track.duration),
    bytes: sanitizeInteger(bytes),
    quality: quality,
    file: fileName,
    createdAt: createdAt
  };
}

function failedResult(code: string, retryable: boolean): DownloadResult {
  const error = toAppError(new NativeError(code, '', retryable));
  return {
    outcome: DownloadOutcome.Failed,
    entry: null,
    error: error
  };
}

function sanitizeText(value: string, maxLength: number): string {
  const trimmed = value.trim();
  return trimmed.length > maxLength ? trimmed.slice(0, maxLength) : trimmed;
}

function sanitizeInteger(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.floor(value);
}

function sanitizeQuality(value: string): AudioQuality {
  if (value === 'high' || value === 'low') {
    return value;
  }
  return 'standard';
}

function cloneEntry(entry: DownloadEntry): DownloadEntry {
  return {
    key: entry.key,
    bvid: entry.bvid,
    aid: entry.aid,
    cid: entry.cid,
    title: entry.title,
    artist: entry.artist,
    coverUrl: entry.coverUrl,
    duration: entry.duration,
    bytes: entry.bytes,
    quality: entry.quality,
    file: entry.file,
    createdAt: entry.createdAt
  };
}

/** 读取索引：版本不符、字段缺失、文件名非法或 key 重复的条目一律丢弃。 */
export function sanitizeDownloadSnapshot(raw: Record<string, Object>,
  maxTotalBytes: number = MAX_TOTAL_DOWNLOAD_BYTES,
  maxEntries: number = MAX_DOWNLOADS): DownloadSnapshot {
  const version = numberValue(raw.version, 0);
  if (version !== DOWNLOAD_INDEX_VERSION) {
    return {
      version: DOWNLOAD_INDEX_VERSION,
      entries: []
    };
  }
  const entries: DownloadEntry[] = [];
  const seen: Set<string> = new Set<string>();
  let totalBytes = 0;
  for (const value of arrayValue(raw.entries)) {
    const record = objectValue(value);
    const key = stringValue(record.key).trim();
    const file = stringValue(record.file).trim();
    if (key.length === 0 || !isSafeFileName(file) || seen.has(key)) {
      continue;
    }
    const bytes = sanitizeInteger(numberValue(record.bytes));
    // 索引按创建时间新到旧排列：触到条数或字节上限时保留新条目、丢弃更旧的。
    if (entries.length >= maxEntries || totalBytes + bytes > maxTotalBytes) {
      break;
    }
    seen.add(key);
    entries.push({
      key: key,
      bvid: sanitizeText(stringValue(record.bvid), 64),
      aid: sanitizeInteger(numberValue(record.aid)),
      cid: sanitizeInteger(numberValue(record.cid)),
      title: sanitizeText(stringValue(record.title), 300),
      artist: sanitizeText(stringValue(record.artist), 200),
      coverUrl: stringValue(record.coverUrl).startsWith('https://')
        ? stringValue(record.coverUrl).slice(0, 1024)
        : '',
      duration: sanitizeInteger(numberValue(record.duration)),
      bytes: bytes,
      quality: sanitizeQuality(stringValue(record.quality)),
      file: file,
      createdAt: sanitizeInteger(numberValue(record.createdAt))
    });
    totalBytes += bytes;
  }
  return {
    version: DOWNLOAD_INDEX_VERSION,
    entries: entries
  };
}

function isSafeFileName(file: string): boolean {
  return file.length > 0 && file.length <= 200 && file.indexOf('/') < 0 &&
    file.indexOf('\\') < 0 && file !== '.' && file !== '..';
}