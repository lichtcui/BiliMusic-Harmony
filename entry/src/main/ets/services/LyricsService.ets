import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  LyricCandidate,
  LyricLine,
  LyricResult,
  MobileTrack
} from '../types/MobileTypes';
import {
  deleteAtomicFile,
  preserveCorruptFile,
  readAtomicTextAsync,
  writeAtomicText
} from '../util/AtomicJson';
import {
  arrayValue,
  byteLength,
  numberValue,
  objectValue,
  stringValue
} from '../util/Json';
import { NativeError } from '../util/Errors';
import { HttpRequestConfig } from './BiliHttpClient';

const DOMAIN = 0x424D;
const TAG = 'WispMusicLyrics';
const OIAPI_URL = 'https://www.oiapi.net/api/QQMusicLyric';
const CACHE_VERSION = 1;
const CACHE_MISS_TTL = 24 * 60 * 60 * 1000;
const MAX_CACHE_ENTRIES = 120;
const MAX_CANDIDATES = 24;

interface CacheEntry {
  status: string;
  timestamp: number;
  result: LyricResult | null;
}

interface CandidateContext {
  rawTitle: string;
  clean: string;
  duration: number;
  quoted: string[];
}

interface ScoredCandidate {
  candidate: LyricCandidate;
  score: number;
}

export interface LyricsCacheStats {
  bytes: number;
  entries: number;
}

export interface LyricsHttpGateway {
  requestJson(targetUrl: string, config: HttpRequestConfig): Promise<Record<string, Object>>;
}

export interface LyricsCachePersistence {
  readAsync(path: string): Promise<string | null>;
  write(path: string, content: string): Promise<void>;
  delete(path: string): void;
  preserveCorrupt(path: string): void;
}

class AtomicLyricsCachePersistence implements LyricsCachePersistence {
  readAsync(path: string): Promise<string | null> {
    return readAtomicTextAsync(path);
  }

  write(path: string, content: string): Promise<void> {
    return writeAtomicText(path, content);
  }

  delete(path: string): void {
    deleteAtomicFile(path);
  }

  preserveCorrupt(path: string): void {
    preserveCorruptFile(path);
  }
}

const NOISE =
  /(official|lyrics?|audio|video|m\/?v|hd|4k|8k|live|cover|remix|remaster|reimagined|suno|feat\.?|ft\.?|prod\.?|demo|hi-?res|ost|bgm|歌词|动态歌词|高音质|无损|纯享|完整版|官方|现场|翻唱|翻自|改编|原唱|伴奏|钢琴版|弹唱|直播|街唱|试听|修复|重制|超清|字幕|珍藏|节目|片段|合集|歌单|循环|精选|盘点|排行|榜单|小时|分钟|首|教学|讲解)/i;
const CJK_NOISE =
  /(官方版|官方MV|官方音频|官方|现场版|现场|完整版|纯享版|纯享|高音质|无损音质|无损|动态歌词|歌词版|超清|修复版|高清修复|重制版|中日字幕|双语字幕|字幕|试听|伴奏|钢琴版|翻唱|翻自|改编|原唱|纯音乐|直播弹唱|弹唱|街唱|男声|女声|原调|弱混|珍藏|教学|讲解|课程|合集|歌单|循环|精选|盘点|排行榜|榜单|一小时|小时|分钟|首|后台播放|附下载地址|下载地址)/g;
const LATIN_NOISE =
  /\b(official|lyrics?|audio|video|m\/?v|mv|hd|4k|8k|live|cover|remix|remaster(?:ed)?|reimagined|suno|hi-?res|ost|bgm)\b/gi;
const SEP = /[-–—_|/\\·•～~「」『』"'`*:：，,;；]/g;
const EMOJI =
  /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}]/gu;
const CJK_QUOTE = /[《<]([^》>]+)[》>]/g;
const TIME_TAG = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
const META_LINE = /^(ti|ar|al|by|offset|kana|tool|length):/i;

export class LyricsService {
  private readonly http: LyricsHttpGateway;
  private readonly cachePath: string;
  private readonly persistence: LyricsCachePersistence;
  private readonly cache: Map<string, CacheEntry> = new Map<string, CacheEntry>();
  private readonly candidates: Map<string, LyricCandidate> = new Map<string, LyricCandidate>();
  private writeChain: Promise<void> = Promise.resolve();
  private clearPromise: Promise<LyricsCacheStats> | null = null;
  private loadPromise: Promise<void> | null = null;
  private cacheLoaded: boolean = false;
  private generation: number = 0;
  private destroyed: boolean = false;

  constructor(http: LyricsHttpGateway, cachePath: string,
    persistence: LyricsCachePersistence = new AtomicLyricsCachePersistence()) {
    this.http = http;
    this.cachePath = cachePath;
    this.persistence = persistence;
  }

  async resolve(params: Record<string, Object>): Promise<LyricResult | null> {
    if (this.destroyed) {
      return null;
    }
    await this.ensureLoaded();
    const track = sanitizeTrack(params.track);
    if (track === null) {
      return null;
    }
    const generation = this.generation;
    const cached = this.cache.get(track.key);
    if (cached !== undefined) {
      if (cached.status === 'ok' && cached.result !== null) {
        return cloneResult(cached.result);
      }
      if (cached.status === 'miss' && Date.now() - cached.timestamp < CACHE_MISS_TTL) {
        return null;
      }
    }

    const candidate = await this.findBestCandidate(track, generation);
    if (!this.isCurrent(generation)) {
      return null;
    }
    if (candidate === null) {
      this.cacheMiss(track.key, generation);
      return null;
    }
    const result = await this.loadResult(candidate, generation);
    if (!this.isCurrent(generation)) {
      return null;
    }
    if (result === null) {
      this.cacheMiss(track.key, generation);
      return null;
    }
    this.cacheOk(track.key, result, generation);
    return cloneResult(result);
  }

  async search(params: Record<string, Object>): Promise<LyricCandidate[]> {
    if (this.destroyed) {
      return [];
    }
    await this.ensureLoaded();
    const query = cleanTitle(stringValue(params.query).trim());
    if (query.length === 0) {
      return [];
    }
    const generation = this.generation;
    const candidates = await this.searchRemote(query, 20, generation);
    return this.isCurrent(generation) ? candidates : [];
  }

  async choose(params: Record<string, Object>): Promise<LyricResult | null> {
    if (this.destroyed) {
      return null;
    }
    // choose 会写入缓存，必须先合并磁盘上的既有条目，否则持久化会覆盖掉它们。
    await this.ensureLoaded();
    const track = sanitizeTrack(params.track);
    const candidateId = stringValue(params.candidateId).trim();
    if (track === null || candidateId.length === 0) {
      return null;
    }
    const generation = this.generation;
    const candidate = this.candidates.get(candidateId);
    if (candidate === undefined) {
      return null;
    }
    const result = await this.loadResult(candidate, generation);
    if (!this.isCurrent(generation)) {
      return null;
    }
    if (result !== null) {
      this.cacheOk(track.key, result, generation);
    }
    return result === null ? null : cloneResult(result);
  }

  async stats(): Promise<LyricsCacheStats> {
    await this.ensureLoaded();
    try {
      return {
        bytes: this.cache.size === 0 ? 0 : byteLength(this.serializeCache()),
        entries: this.cache.size
      };
    } catch (error) {
      throw cacheFailure('lyrics.cacheStatsFailed', error as Object);
    }
  }

  clear(): Promise<LyricsCacheStats> {
    if (this.clearPromise !== null) {
      return this.clearPromise;
    }
    if (this.destroyed) {
      return Promise.reject(new NativeError('app.notReady', '', true));
    }
    const generation = this.generation + 1;
    this.generation = generation;
    this.cacheLoaded = true;
    this.cache.clear();
    this.candidates.clear();
    const removal: Promise<void> = this.writeChain
      .catch((): void => {})
      .then((): void => {
        if (generation !== this.generation) {
          return;
        }
        this.persistence.delete(this.cachePath);
      });
    this.writeChain = removal.catch((): void => {
      hilog.warn(DOMAIN, TAG, 'lyrics cache removal failed');
    });
    const pending: Promise<LyricsCacheStats> = removal
      .then((): Promise<LyricsCacheStats> => this.stats())
      .catch((error: Object): LyricsCacheStats => {
        throw cacheFailure('lyrics.cacheClearFailed', error);
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
    this.destroyed = true;
    this.generation += 1;
    await this.writeChain.catch((): void => {});
  }

  private async findBestCandidate(track: MobileTrack,
    generation: number): Promise<LyricCandidate | null> {
    const queries = queryCandidates(track.title);
    if (queries.length === 0) {
      return null;
    }
    const seen: Map<string, LyricCandidate> = new Map<string, LyricCandidate>();
    for (const query of queries) {
      if (!this.isCurrent(generation)) {
        return null;
      }
      const rows = await this.searchRemote(query, 10, generation);
      if (!this.isCurrent(generation)) {
        return null;
      }
      for (const row of rows) {
        if (!seen.has(row.id)) {
          seen.set(row.id, row);
        }
      }
      if (seen.size >= MAX_CANDIDATES) {
        break;
      }
    }
    if (seen.size === 0) {
      return null;
    }
    if (!this.isCurrent(generation)) {
      return null;
    }
    const context: CandidateContext = {
      rawTitle: track.title,
      clean: cleanTitle(track.title),
      duration: Math.max(0, track.duration),
      quoted: quotedTitles(track.title)
    };
    let best: ScoredCandidate | null = null;
    seen.forEach((candidate: LyricCandidate): void => {
      const scored: ScoredCandidate = {
        candidate: candidate,
        score: scoreCandidate(candidate, context)
      };
      if (best === null || scored.score > best.score) {
        best = scored;
      }
    });
    if (best === null) {
      return null;
    }
    const selected = best as ScoredCandidate;
    if (selected.score < 120 && !normalizedIncludes(track.title, selected.candidate.trackName)) {
      return null;
    }
    return selected.candidate;
  }

  private async searchRemote(keyword: string, limit: number,
    generation: number): Promise<LyricCandidate[]> {
    if (!this.isCurrent(generation)) {
      return [];
    }
    const target = `${OIAPI_URL}?keyword=${encodeURIComponent(keyword)}&page=1` +
      `&limit=${Math.max(1, Math.min(30, limit))}&type=json`;
    try {
      const response = await this.http.requestJson(target, {
        timeoutMs: 9_000,
        maxBytes: 1024 * 1024,
        followRedirects: true,
        allowedHosts: ['oiapi.net'],
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Referer': 'https://www.oiapi.net/'
        }
      });
      if (!this.isCurrent(generation)) {
        return [];
      }
      const candidates: LyricCandidate[] = [];
      for (const raw of arrayValue(response.data)) {
        const candidate = normalizeCandidate(raw);
        if (candidate !== null) {
          candidates.push(candidate);
        }
      }
      for (const candidate of candidates) {
        this.candidates.set(candidate.id, candidate);
      }
      return candidates;
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return [];
      }
      hilog.warn(DOMAIN, TAG, 'lyrics search unavailable');
      throw new NativeError('lyrics.searchUnavailable', '歌词服务暂时不可用。', true);
    }
  }

  private async loadResult(candidate: LyricCandidate,
    generation: number): Promise<LyricResult | null> {
    const content = await this.fetchLyric(candidate.id, generation);
    if (!this.isCurrent(generation) || content.length === 0) {
      return null;
    }
    const syncedLines = parseLrc(content);
    const lines = syncedLines.length > 0 ? syncedLines : plainToLines(content);
    if (lines.length === 0) {
      return null;
    }
    return {
      lines: lines,
      synced: syncedLines.length > 0,
      trackName: candidate.trackName,
      artistName: candidate.artistName,
      sourceId: candidate.id
    };
  }

  private async fetchLyric(candidateId: string, generation: number): Promise<string> {
    if (!this.isCurrent(generation)) {
      return '';
    }
    const target = `${OIAPI_URL}?id=${encodeURIComponent(candidateId)}&format=lrc&type=json`;
    try {
      const response = await this.http.requestJson(target, {
        timeoutMs: 9_000,
        maxBytes: 4 * 1024 * 1024,
        followRedirects: true,
        allowedHosts: ['oiapi.net'],
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Referer': 'https://www.oiapi.net/'
        }
      });
      if (!this.isCurrent(generation)) {
        return '';
      }
      if (numberValue(response.code) !== 1) {
        return '';
      }
      const data = response.data;
      if (typeof data === 'string') {
        return data;
      }
      const record = objectValue(data);
      const content = stringValue(record.content, stringValue(record.conteng));
      if (content.length > 0) {
        return content;
      }
      const message = stringValue(response.message);
      return message.includes('[') ? message : '';
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return '';
      }
      hilog.warn(DOMAIN, TAG, 'lyrics fetch unavailable');
      throw new NativeError('lyrics.fetchUnavailable', '歌词服务暂时不可用。', true);
    }
  }

  private cacheOk(trackKey: string, result: LyricResult, generation: number): void {
    if (!this.isCurrent(generation)) {
      return;
    }
    this.cache.set(trackKey, {
      status: 'ok',
      timestamp: Date.now(),
      result: cloneResult(result)
    });
    this.trimCache();
    void this.persist(generation).catch((): void => {});
  }

  private cacheMiss(trackKey: string, generation: number): void {
    if (!this.isCurrent(generation)) {
      return;
    }
    this.cache.set(trackKey, {
      status: 'miss',
      timestamp: Date.now(),
      result: null
    });
    this.trimCache();
    void this.persist(generation).catch((): void => {});
  }

  private trimCache(): void {
    if (this.cache.size <= MAX_CACHE_ENTRIES) {
      return;
    }
    let oldestKey = '';
    let oldestTimestamp = Number.MAX_SAFE_INTEGER;
    this.cache.forEach((entry: CacheEntry, key: string): void => {
      if (entry.timestamp < oldestTimestamp) {
        oldestTimestamp = entry.timestamp;
        oldestKey = key;
      }
    });
    if (oldestKey.length > 0) {
      this.cache.delete(oldestKey);
    }
  }

  private persist(generation: number): Promise<void> {
    const pending = this.writeChain
      .catch((): void => {})
      .then((): Promise<void> => {
        if (generation !== this.generation) {
          return Promise.resolve();
        }
        return this.persistence.write(this.cachePath, this.serializeCache());
      });
    this.writeChain = pending.catch((): void => {
      hilog.warn(DOMAIN, TAG, 'lyrics cache persistence failed');
    });
    return pending;
  }

  /**
   * 歌词缓存按需加载：冷启动不再同步读盘，首次取词/换源/统计时才读。
   * 读失败按空缓存处理并记一次日志，避免每次操作都重试读盘。
   */
  private ensureLoaded(): Promise<void> {
    if (this.cacheLoaded || this.destroyed) {
      return Promise.resolve();
    }
    if (this.loadPromise !== null) {
      return this.loadPromise;
    }
    const generation = this.generation;
    const loading: Promise<void> = this.persistence.readAsync(this.cachePath)
      .then((content: string | null): void => {
        if (this.destroyed || generation !== this.generation) {
          return;
        }
        this.applyCache(content);
        this.cacheLoaded = true;
      })
      .catch((): void => {
        hilog.warn(DOMAIN, TAG, 'lyrics cache load failed');
        if (!this.destroyed && generation === this.generation) {
          this.cacheLoaded = true;
        }
      })
      .then((): void => {
        if (this.loadPromise === loading) {
          this.loadPromise = null;
        }
      });
    this.loadPromise = loading;
    return loading;
  }

  private applyCache(content: string | null): void {
    if (content === null) {
      return;
    }
    try {
      const raw = JSON.parse(content) as Record<string, Object>;
      if (numberValue(raw.version) !== CACHE_VERSION) {
        return;
      }
      const entries = objectValue(raw.entries);
      for (const key of Object.keys(entries)) {
        if (key.length === 0 || key.length > 80) {
          continue;
        }
        const value = objectValue(entries[key]);
        const status = stringValue(value.status);
        const result = status === 'ok' ? sanitizeResult(objectValue(value.result)) : null;
        if (status === 'ok' && result === null) {
          continue;
        }
        this.cache.set(key, {
          status: status === 'ok' ? 'ok' : 'miss',
          timestamp: Math.max(0, numberValue(value.timestamp)),
          result: result
        });
        if (this.cache.size >= MAX_CACHE_ENTRIES) {
          break;
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'lyrics cache is corrupt; starting empty');
      this.persistence.preserveCorrupt(this.cachePath);
      this.cache.clear();
    }
  }

  private serializeCache(): string {
    const entries: Record<string, Object> = {};
    this.cache.forEach((entry: CacheEntry, key: string): void => {
      entries[key] = entry;
    });
    return JSON.stringify({
      version: CACHE_VERSION,
      entries: entries
    });
  }

  private isCurrent(generation: number): boolean {
    return !this.destroyed && generation === this.generation;
  }
}

export function cleanTitle(raw: string): string {
  if (raw.length === 0) {
    return '';
  }
  let value = raw.normalize('NFKC');
  value = value.replace(CJK_QUOTE, ' $1 ');
  value = value.replace(/[【[(（]([^】\])）]*)[】\])）]/g, (match: string, inner: string): string => {
    return NOISE.test(inner) ? ' ' : ` ${inner} `;
  });
  const cleaned = cleanSegment(value);
  return cleaned.length > 0 ? cleaned : raw.trim().slice(0, 40);
}

export function parseLrc(content: string): LyricLine[] {
  const lines: LyricLine[] = [];
  for (const rawLine of content.split('\n')) {
    TIME_TAG.lastIndex = 0;
    const times: number[] = [];
    let match: RegExpExecArray | null = TIME_TAG.exec(rawLine);
    while (match !== null) {
      const minutes = parseInt(match[1], 10);
      const seconds = parseInt(match[2], 10);
      const fractionText = match[3] ?? '';
      const fraction = fractionText.length > 0
        ? parseInt(fractionText.padEnd(3, '0').slice(0, 3), 10) / 1000
        : 0;
      times.push(minutes * 60 + seconds + fraction);
      match = TIME_TAG.exec(rawLine);
    }
    if (times.length === 0) {
      continue;
    }
    const text = rawLine.replace(TIME_TAG, '').trim();
    if (text.length === 0 || META_LINE.test(text)) {
      continue;
    }
    for (const time of times) {
      lines.push({
        time: time,
        text: text.slice(0, 1000)
      });
    }
  }
  lines.sort((left: LyricLine, right: LyricLine): number => left.time - right.time);
  return lines.slice(0, 5000);
}

export function queryCandidates(raw: string): string[] {
  const candidates: string[] = [];
  const quotes = quotedTitles(raw);
  const context = cleanSegment(stripQuoted(raw));

  for (const title of quotes) {
    pushUnique(candidates, title);
    if (context.length > 0) {
      pushUnique(candidates, `${title} ${context}`);
    }
  }
  for (const part of compactKeywordParts(raw)) {
    pushUnique(candidates, part);
  }
  const title = cleanTitle(raw);
  pushUnique(candidates, title);
  for (const token of title.split(' ')) {
    if (token.length > 1 && !NOISE.test(token)) {
      pushUnique(candidates, token);
    }
  }
  return candidates
    .filter((candidate: string): boolean => !/^(av|bv)[\da-z]+$/i.test(candidate))
    .slice(0, 8);
}

function normalizeCandidate(raw: Object): LyricCandidate | null {
  const item = objectValue(raw);
  const id = stringValue(item.id).trim();
  const trackName = stringValue(item.name).trim();
  if (id.length === 0 || trackName.length === 0) {
    return null;
  }
  const singers: string[] = [];
  for (const value of arrayValue(item.singer)) {
    const singer = stringValue(value).trim();
    if (singer.length > 0) {
      singers.push(singer);
    }
  }
  return {
    id: id,
    trackName: trackName.slice(0, 300),
    artistName: singers.join(' / ').slice(0, 300),
    albumName: stringValue(item.album).trim().slice(0, 300),
    duration: Math.max(0, numberValue(item.duration)),
    image: safeHttpsUrl(stringValue(item.image))
  };
}

function sanitizeTrack(value: Object | undefined): MobileTrack | null {
  const raw = objectValue(value);
  const bvid = stringValue(raw.bvid).trim().slice(0, 32);
  const aid = Math.max(0, Math.floor(numberValue(raw.aid)));
  const cid = Math.max(0, Math.floor(numberValue(raw.cid)));
  const title = stringValue(raw.title).trim().slice(0, 300);
  if ((bvid.length === 0 && aid <= 0) || cid <= 0 || title.length === 0) {
    return null;
  }
  const keyBase = bvid.length > 0 ? bvid : `av${aid}`;
  return {
    key: `${keyBase}:${cid}`,
    bvid: bvid,
    aid: aid,
    cid: cid,
    title: title,
    artist: stringValue(raw.artist, '未知作者').trim().slice(0, 200),
    coverUrl: safeHttpsUrl(stringValue(raw.coverUrl)),
    duration: Math.max(0, numberValue(raw.duration)),
    playCount: Math.max(0, numberValue(raw.playCount))
  };
}

function sanitizeResult(raw: Record<string, Object>): LyricResult | null {
  const lines: LyricLine[] = [];
  for (const value of arrayValue(raw.lines).slice(0, 5000)) {
    const line = objectValue(value);
    const text = stringValue(line.text).trim().slice(0, 1000);
    if (text.length > 0) {
      lines.push({
        time: numberValue(line.time, -1),
        text: text
      });
    }
  }
  if (lines.length === 0) {
    return null;
  }
  return {
    lines: lines,
    synced: Boolean(raw.synced),
    trackName: stringValue(raw.trackName).trim().slice(0, 300),
    artistName: stringValue(raw.artistName).trim().slice(0, 300),
    sourceId: stringValue(raw.sourceId).trim().slice(0, 80)
  };
}

function cleanSegment(raw: string): string {
  if (raw.length === 0) {
    return '';
  }
  let value = raw.normalize('NFKC');
  value = value.replace(/#[^\s#]+/g, ' ');
  value = value.replace(EMOJI, ' ');
  value = value.replace(/[!！?？.。]+/g, ' ');
  value = value.replace(CJK_NOISE, ' ');
  value = value.replace(LATIN_NOISE, ' ');
  value = value.replace(/\b\d+\s*(?:首|小时|分钟|mins?|hours?)\b/gi, ' ');
  value = value.replace(SEP, ' ');
  return value.replace(/\s+/g, ' ').trim();
}

function quotedTitles(raw: string): string[] {
  const values: string[] = [];
  const normalized = raw.normalize('NFKC');
  const expression = new RegExp(CJK_QUOTE.source, 'g');
  let match: RegExpExecArray | null = expression.exec(normalized);
  while (match !== null) {
    pushUnique(values, cleanSegment(match[1]));
    match = expression.exec(normalized);
  }
  return values;
}

function stripQuoted(raw: string): string {
  return raw.normalize('NFKC').replace(CJK_QUOTE, ' ');
}

function compactKeywordParts(raw: string): string[] {
  const values: string[] = [];
  const normalized = raw.normalize('NFKC')
    .replace(CJK_QUOTE, ' $1 ')
    .split(/[【】[\]()（）]|[-–—_|/\\·•～~「」『』"'`*:：，,;；]/);
  for (const part of normalized) {
    const cleaned = cleanSegment(part);
    if (cleaned.length > 0 && !NOISE.test(cleaned)) {
      pushUnique(values, cleaned);
    }
  }
  return values;
}

function pushUnique(values: string[], raw: string): void {
  const value = raw.replace(/\s+/g, ' ').trim();
  if (value.length < 2) {
    return;
  }
  const normalized = normalizeText(value);
  if (!values.some((item: string): boolean => normalizeText(item) === normalized)) {
    values.push(value);
  }
}

function plainToLines(content: string): LyricLine[] {
  const lines: LyricLine[] = [];
  for (const raw of content.split('\n')) {
    const text = raw.trim();
    if (text.length === 0 || META_LINE.test(text.replace(/^\[[^\]]+]/, ''))) {
      continue;
    }
    lines.push({
      time: -1,
      text: text.slice(0, 1000)
    });
    if (lines.length >= 5000) {
      break;
    }
  }
  return lines;
}

function scoreCandidate(candidate: LyricCandidate, context: CandidateContext): number {
  let quotedScore = 0;
  for (const quoted of context.quoted) {
    quotedScore = Math.max(quotedScore, dice(candidate.trackName, quoted));
  }
  let score = normalizedIncludes(context.rawTitle, candidate.trackName)
    ? 360
    : dice(candidate.trackName, context.clean) * 180;
  if (normalizedIncludes(context.rawTitle, candidate.artistName)) {
    score += 280;
  }
  score += quotedScore * 300;
  if (candidate.albumName.length > 0 && normalizedIncludes(context.rawTitle, candidate.albumName)) {
    score += 40;
  }
  if (context.duration > 0 && candidate.duration > 0) {
    const difference = Math.abs(context.duration - candidate.duration);
    if (difference <= 4) {
      score += 130;
    } else if (difference <= 10) {
      score += 85;
    } else if (difference <= 25) {
      score += 35;
    } else {
      score -= Math.min(difference, 240) * 1.25;
    }
    if (context.duration > 900 && candidate.duration < 600) {
      score -= 360;
    }
  }
  if (/伴奏|karaoke|instrumental/i.test(candidate.trackName) &&
    !/伴奏|karaoke|instrumental/i.test(context.rawTitle)) {
    score -= 120;
  }
  if (/翻唱|cover/i.test(candidate.trackName) && !/翻唱|cover/i.test(context.rawTitle)) {
    score -= 80;
  }
  return score;
}

function normalizeText(value: string): string {
  return value.normalize('NFKC').toLowerCase().replace(/[\s\p{P}\p{S}]/gu, '');
}

function normalizedIncludes(haystack: string, needle: string): boolean {
  const normalizedHaystack = normalizeText(haystack);
  const normalizedNeedle = normalizeText(needle);
  return normalizedNeedle.length >= 2 && normalizedHaystack.includes(normalizedNeedle);
}

function bigrams(value: string): Set<string> {
  const result: Set<string> = new Set<string>();
  if (value.length === 1) {
    result.add(value);
    return result;
  }
  for (let index = 0; index < value.length - 1; index += 1) {
    result.add(value.slice(index, index + 2));
  }
  return result;
}

function dice(left: string, right: string): number {
  const normalizedLeft = normalizeText(left);
  const normalizedRight = normalizeText(right);
  if (normalizedLeft.length === 0 || normalizedRight.length === 0) {
    return 0;
  }
  if (normalizedLeft === normalizedRight) {
    return 1;
  }
  if (normalizedLeft.includes(normalizedRight) || normalizedRight.includes(normalizedLeft)) {
    return 0.86;
  }
  const leftPairs = bigrams(normalizedLeft);
  const rightPairs = bigrams(normalizedRight);
  let intersection = 0;
  leftPairs.forEach((pair: string): void => {
    if (rightPairs.has(pair)) {
      intersection += 1;
    }
  });
  return (2 * intersection) / (leftPairs.size + rightPairs.size);
}

function safeHttpsUrl(value: string): string {
  const clean = value.trim();
  if (clean.startsWith('//')) {
    return `https:${clean}`;
  }
  if (clean.startsWith('http://')) {
    return `https://${clean.slice(7)}`;
  }
  return clean.startsWith('https://') ? clean : '';
}

function cloneResult(value: LyricResult): LyricResult {
  return JSON.parse(JSON.stringify(value)) as LyricResult;
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
