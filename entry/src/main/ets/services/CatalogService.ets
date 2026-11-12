import { url } from '@kit.ArkTS';
import {
  apiCode,
  apiMessage,
  BiliHttpClient
} from './BiliHttpClient';
import {
  CatalogCollection,
  CatalogExpansion,
  CatalogFeed,
  CatalogSearchResult,
  AudioQuality,
  MobileTrack
} from '../types/MobileTypes';
import { NativeError } from '../util/Errors';
import {
  arrayValue,
  numberValue,
  objectValue,
  stringValue
} from '../util/Json';
import {
  AudioCandidateSource,
  selectDashAudioCandidates
} from './AudioFallback';

const DETAIL_CONCURRENCY = 4;
const MAX_PAGE_SIZE = 30;
const MAX_COLLECTION_TRACKS = 500;
const MAX_VIEW_CACHE = 48;
const VIEW_CACHE_TTL_MS = 10 * 60 * 1000;

interface TrackSeed {
  bvid: string;
  aid: number;
  cid: number;
  title: string;
  artist: string;
  coverUrl: string;
  duration: number;
  playCount: number;
}

export interface VideoPage {
  cid: number;
  page: number;
  title: string;
  duration: number;
}

export interface VideoDetail {
  rootTrack: MobileTrack;
  pages: VideoPage[];
  totalDuration: number;
}

interface CachedVideoDetail {
  detail: VideoDetail;
  expiresAt: number;
}

export type AudioSelection = AudioCandidateSource;

export type AudioCandidate = AudioSelection;

export class CatalogService {
  private readonly http: BiliHttpClient;
  private readonly viewCache: Map<string, CachedVideoDetail> = new Map<string, CachedVideoDetail>();
  private readonly viewCacheOrder: string[] = [];
  private readonly viewInflight: Map<string, Promise<VideoDetail | null>> =
    new Map<string, Promise<VideoDetail | null>>();

  constructor(http: BiliHttpClient) {
    this.http = http;
  }

  async discover(page: number, pageSize: number): Promise<CatalogFeed> {
    const safePage = clampInteger(page, 1, 10_000, 1);
    const safeSize = clampInteger(pageSize, 1, MAX_PAGE_SIZE, 20);
    const response = await this.http.biliJson(
      `/x/centralization/interface/music/comprehensive/web/rank?pn=${safePage}&ps=${safeSize}`
    );
    assertSuccess(response, 'catalog.discoverFailed');
    const data = objectValue(response.data);
    const list = arrayValue(data.list);
    const seeds = list.map((item: Object): TrackSeed => rankSeed(item))
      .filter((seed: TrackSeed): boolean => seed.bvid.length > 0 || seed.aid > 0);
    const items = await this.resolveSeeds(seeds, false);
    return {
      items: items,
      page: safePage,
      hasMore: list.length >= safeSize
    };
  }

  async recommend(page: number, pageSize: number): Promise<CatalogFeed> {
    const safePage = clampInteger(page, 1, 10_000, 1);
    const safeSize = clampInteger(pageSize, 1, MAX_PAGE_SIZE, 12);
    const response = await this.http.biliJson(
      `/x/web-interface/index/top/rcmd?ps=${safeSize}&fresh_idx=${safePage}&fresh_type=4`
    );
    assertSuccess(response, 'catalog.recommendFailed');
    const data = objectValue(response.data);
    const list = arrayValue(data.item).length > 0 ? arrayValue(data.item) : arrayValue(data.list);
    const seeds = list.map((item: Object): TrackSeed => recommendationSeed(item))
      .filter((seed: TrackSeed): boolean => seed.bvid.length > 0 || seed.aid > 0);
    const items = await this.resolveSeeds(seeds, false);
    return {
      items: items,
      page: safePage,
      hasMore: list.length >= safeSize
    };
  }

  async search(keyword: string, page: number, pageSize: number): Promise<CatalogSearchResult> {
    const query = keyword.trim().slice(0, 80);
    if (query.length === 0) {
      throw new NativeError('catalog.invalidQuery', '请输入搜索关键词。');
    }
    const safePage = clampInteger(page, 1, 100, 1);
    const safeSize = clampInteger(pageSize, 1, MAX_PAGE_SIZE, 20);
    const response = await this.http.wbiJson('/x/web-interface/wbi/search/type', {
      searchType: 'video',
      keyword: query,
      page: safePage,
      pageSize: safeSize
    });
    assertSuccess(response, 'catalog.searchFailed');
    const data = objectValue(response.data);
    const rows = arrayValue(data.result);
    const seeds = rows.map((item: Object): TrackSeed => searchSeed(item))
      .filter((seed: TrackSeed): boolean => seed.bvid.length > 0 || seed.aid > 0);
    const items = await this.resolveSeeds(seeds, true);
    const total = numberValue(data.numResults, items.length);
    return {
      items: items,
      page: safePage,
      hasMore: safePage * safeSize < total,
      total: Math.max(0, total),
      keyword: query
    };
  }

  async detail(params: Record<string, Object>): Promise<MobileTrack> {
    const rawTrack = objectValue(params.track);
    const seed: TrackSeed = {
      bvid: stringValue(params.bvid, stringValue(rawTrack.bvid)).trim(),
      aid: numberValue(params.aid, numberValue(rawTrack.aid)),
      cid: numberValue(params.cid, numberValue(rawTrack.cid)),
      title: stringValue(rawTrack.title).trim(),
      artist: stringValue(rawTrack.artist).trim(),
      coverUrl: stringValue(rawTrack.coverUrl),
      duration: numberValue(rawTrack.duration),
      playCount: numberValue(rawTrack.playCount)
    };
    if (seed.bvid.length > 0) {
      const detail = await this.fetchView(seed.bvid);
      if (detail !== null) {
        return withPlayCount(detail.rootTrack, seed.playCount);
      }
    }
    const fallback = trackFromSeed(seed);
    if (fallback === null) {
      throw new NativeError('catalog.notFound', '曲目不存在或已失效。');
    }
    return fallback;
  }

  async audioSource(track: MobileTrack, quality: AudioQuality = 'standard'): Promise<AudioCandidate[]> {
    const response = await this.http.biliJson(this.playUrlQuery(track, 16));
    assertSuccess(response, 'player.playUrlFailed');
    const data = objectValue(response.data);
    const dash = objectValue(data.dash);
    const audio = arrayValue(dash.audio);
    const selected = selectAudioCandidates(audio, quality);
    if (selected.length === 0) {
      throw new NativeError('player.noAudioStream', '当前曲目没有可播放的音频流。', true);
    }
    return selected;
  }

  async progressiveAudioSource(track: MobileTrack): Promise<AudioCandidate[]> {
    const response = await this.http.biliJson(this.playUrlQuery(track, 0));
    assertSuccess(response, 'player.playUrlFailed');
    const data = objectValue(response.data);
    const selected = selectProgressiveCandidates(arrayValue(data.durl));
    if (selected.length === 0) {
      throw new NativeError('player.noProgressiveStream', '当前曲目没有可回退的 MP4 播放流。', true);
    }
    return selected;
  }

  private playUrlQuery(track: MobileTrack, fnval: number): string {
    let query = '';
    if (track.bvid.length > 0) {
      query = `bvid=${encodeURIComponent(track.bvid)}&cid=${track.cid}`;
    } else if (track.aid > 0) {
      query = `avid=${track.aid}&cid=${track.cid}`;
    } else {
      throw new NativeError('player.invalidTrack', '曲目缺少播放标识。');
    }
    return `/x/player/playurl?${query}&qn=0&fnver=0&fnval=${fnval}&fourk=1`;
  }

  /**
   * 读取一个 B 站视频的全部分 P。单 P 视频返回 null，调用方按普通曲目处理。
   */
  async collection(bvid: string): Promise<CatalogCollection | null> {
    const detail = await this.fetchView(bvid);
    if (detail === null || detail.pages.length <= 1) {
      return null;
    }
    const parts: MobileTrack[] = [];
    for (let index = 0; index < detail.pages.length; index++) {
      parts.push(partTrack(detail.rootTrack, detail.pages[index], index));
    }
    return {
      bvid: detail.rootTrack.bvid,
      aid: detail.rootTrack.aid,
      title: detail.rootTrack.title,
      artist: detail.rootTrack.artist,
      coverUrl: detail.rootTrack.coverUrl,
      totalDuration: detail.totalDuration,
      parts: parts
    };
  }

  /**
   * 按搜索顺序展开合集。单个合集失败时回退为根曲目（P1），不阻断整个队列。
   */
  async expandTracks(tracks: MobileTrack[], limit: number = MAX_COLLECTION_TRACKS): Promise<CatalogExpansion> {
    const safeLimit = clampInteger(limit, 1, MAX_COLLECTION_TRACKS, MAX_COLLECTION_TRACKS);
    const expanded: MobileTrack[] = [];
    for (let offset = 0; offset < tracks.length; offset += DETAIL_CONCURRENCY) {
      const chunk = tracks.slice(offset, offset + DETAIL_CONCURRENCY);
      const groups = await Promise.all(chunk.map((track: MobileTrack): Promise<MobileTrack[]> => {
        return this.expandTrack(track);
      }));
      for (const group of groups) {
        for (const track of group) {
          if (expanded.length >= safeLimit) {
            return {
              tracks: expanded,
              truncated: true
            };
          }
          expanded.push(track);
        }
      }
    }
    return {
      tracks: expanded,
      truncated: false
    };
  }

  private async expandTrack(track: MobileTrack): Promise<MobileTrack[]> {
    if ((track.collectionSize ?? 0) <= 1 || track.bvid.length === 0) {
      return [track];
    }
    try {
      const collection = await this.collection(track.bvid);
      return collection !== null && collection.parts.length > 0 ? collection.parts : [track];
    } catch (error) {
      return [track];
    }
  }

  private async resolveSeeds(seeds: TrackSeed[], forceView: boolean): Promise<MobileTrack[]> {
    const items: MobileTrack[] = [];
    for (let offset = 0; offset < seeds.length; offset += DETAIL_CONCURRENCY) {
      const chunk = seeds.slice(offset, offset + DETAIL_CONCURRENCY);
      const resolved = await Promise.all(chunk.map((seed: TrackSeed): Promise<MobileTrack | null> => {
        return this.resolveSeed(seed, forceView);
      }));
      for (const track of resolved) {
        if (track !== null) {
          items.push(track);
        }
      }
    }
    return items;
  }

  private async resolveSeed(seed: TrackSeed, forceView: boolean): Promise<MobileTrack | null> {
    if (!forceView) {
      const direct = trackFromSeed(seed);
      if (direct !== null) {
        return direct;
      }
    }
    if (seed.bvid.length > 0) {
      try {
        const detail = await this.fetchView(seed.bvid);
        if (detail !== null) {
          return withPlayCount(detail.rootTrack, seed.playCount);
        }
      } catch (error) {
        // Fall through to the music-center seed when the archive is unavailable.
      }
    }
    return trackFromSeed(seed);
  }

  private async fetchView(bvid: string): Promise<VideoDetail | null> {
    const key = bvid.trim();
    if (key.length === 0) {
      return null;
    }
    const cached = this.viewCache.get(key);
    if (cached !== undefined) {
      if (cached.expiresAt > Date.now()) {
        this.touchViewCache(key);
        return cached.detail;
      }
      this.viewCache.delete(key);
      this.removeViewCacheOrder(key);
    }
    const inflight = this.viewInflight.get(key);
    if (inflight !== undefined) {
      return inflight;
    }
    const request = this.loadView(key);
    this.viewInflight.set(key, request);
    try {
      const detail = await request;
      if (detail !== null) {
        this.cacheView(key, detail);
      }
      return detail;
    } finally {
      this.viewInflight.delete(key);
    }
  }

  private async loadView(bvid: string): Promise<VideoDetail | null> {
    const response = await this.http.biliJson(
      `/x/web-interface/view?bvid=${encodeURIComponent(bvid)}`
    );
    if (apiCode(response) !== 0) {
      return null;
    }
    const data = objectValue(response.data);
    let pages = parseVideoPages(arrayValue(data.pages));
    const videos = Math.max(0, numberValue(data.videos, pages.length));
    if (pages.length === 0 || videos > pages.length) {
      const extra = await this.fetchPageList(bvid);
      if (extra.length > pages.length) {
        pages = extra;
      }
    }
    return buildVideoDetail(data, bvid, pages);
  }

  private async fetchPageList(bvid: string): Promise<VideoPage[]> {
    const response = await this.http.biliJson(
      `/x/player/pagelist?bvid=${encodeURIComponent(bvid)}`
    );
    if (apiCode(response) !== 0) {
      return [];
    }
    const direct = arrayValue(response.data);
    const list = direct.length > 0 ? direct : arrayValue(objectValue(response.data).list);
    return parseVideoPages(list);
  }

  private cacheView(bvid: string, detail: VideoDetail): void {
    this.viewCache.set(bvid, {
      detail: detail,
      expiresAt: Date.now() + VIEW_CACHE_TTL_MS
    });
    this.touchViewCache(bvid);
    while (this.viewCacheOrder.length > MAX_VIEW_CACHE) {
      const oldest = this.viewCacheOrder.shift();
      if (oldest !== undefined) {
        this.viewCache.delete(oldest);
      }
    }
  }

  private touchViewCache(bvid: string): void {
    const index = this.viewCacheOrder.indexOf(bvid);
    if (index >= 0) {
      this.viewCacheOrder.splice(index, 1);
    }
    this.viewCacheOrder.push(bvid);
  }

  private removeViewCacheOrder(bvid: string): void {
    const index = this.viewCacheOrder.indexOf(bvid);
    if (index >= 0) {
      this.viewCacheOrder.splice(index, 1);
    }
  }
}

export function parseVideoPages(rawPages: Object[]): VideoPage[] {
  const pages: VideoPage[] = [];
  for (let index = 0; index < rawPages.length; index++) {
    const item = objectValue(rawPages[index]);
    const cid = numberValue(item.cid);
    const pageNumber = Math.max(1, numberValue(item.page, index + 1));
    if (cid <= 0) {
      continue;
    }
    const title = stringValue(item.part).trim();
    pages.push({
      cid: cid,
      page: pageNumber,
      title: title.length > 0 ? title : `P${pageNumber}`,
      duration: Math.max(0, numberValue(item.duration))
    });
  }
  return pages;
}

export function buildVideoDetail(
  data: Record<string, Object>,
  bvidFallback: string,
  pageOverride: VideoPage[] = []
): VideoDetail | null {
  const owner = objectValue(data.owner);
  const stat = objectValue(data.stat);
  const title = stringValue(data.title).trim();
  const resolvedBvid = stringValue(data.bvid, bvidFallback).trim();
  const aid = numberValue(data.aid);
  if (title.length === 0 || (resolvedBvid.length === 0 && aid <= 0)) {
    return null;
  }
  let pages = pageOverride.length > 0 ? pageOverride.slice() : parseVideoPages(arrayValue(data.pages));
  if (pages.length === 0) {
    const cid = numberValue(data.cid);
    if (cid > 0) {
      pages = [{
        cid: cid,
        page: 1,
        title: title,
        duration: Math.max(0, numberValue(data.duration))
      }];
    }
  }
  if (pages.length === 0) {
    return null;
  }
  if (pages.length > MAX_COLLECTION_TRACKS) {
    pages = pages.slice(0, MAX_COLLECTION_TRACKS);
  }
  let totalDuration = 0;
  for (const page of pages) {
    totalDuration += Math.max(0, page.duration);
  }
  if (totalDuration <= 0) {
    totalDuration = Math.max(0, numberValue(data.duration));
  }
  const first = pages[0];
  const rootDuration = pages.length > 1 ?
    Math.max(0, first.duration) : Math.max(0, first.duration > 0 ? first.duration : numberValue(data.duration));
  const artist = stringValue(owner.name, '未知作者').trim();
  const rootTrack: MobileTrack = {
    key: `${resolvedBvid.length > 0 ? resolvedBvid : `av${aid}`}:${first.cid}`,
    bvid: resolvedBvid,
    aid: aid,
    cid: first.cid,
    title: title,
    artist: artist.length > 0 ? artist : '未知作者',
    coverUrl: toHttpsUrl(stringValue(data.pic)),
    duration: rootDuration,
    playCount: Math.max(0, numberValue(stat.view))
  };
  if (pages.length > 1) {
    rootTrack.collectionSize = pages.length;
    rootTrack.collectionTotalDuration = totalDuration;
  }
  return {
    rootTrack: rootTrack,
    pages: pages,
    totalDuration: totalDuration
  };
}

function partTrack(root: MobileTrack, page: VideoPage, index: number): MobileTrack {
  const title = page.title.trim();
  const keyBase = root.bvid.length > 0 ? root.bvid : `av${root.aid}`;
  return {
    key: `${keyBase}:${page.cid}`,
    bvid: root.bvid,
    aid: root.aid,
    cid: page.cid,
    title: title.length > 0 ? title : `P${index + 1}`,
    artist: root.artist,
    coverUrl: root.coverUrl,
    duration: Math.max(0, page.duration),
    playCount: 0
  };
}

function withPlayCount(track: MobileTrack, playCount: number): MobileTrack {
  if (playCount <= track.playCount) {
    return track;
  }
  const copy: MobileTrack = {
    key: track.key,
    bvid: track.bvid,
    aid: track.aid,
    cid: track.cid,
    title: track.title,
    artist: track.artist,
    coverUrl: track.coverUrl,
    duration: track.duration,
    playCount: playCount
  };
  if (track.collectionSize !== undefined) {
    copy.collectionSize = track.collectionSize;
  }
  if (track.collectionTotalDuration !== undefined) {
    copy.collectionTotalDuration = track.collectionTotalDuration;
  }
  return copy;
}

export function selectAudioStream(streams: Object[],
  quality: AudioQuality = 'standard'): AudioSelection | null {
  const candidates = selectAudioCandidates(streams, quality);
  return candidates.length > 0 ? candidates[0] : null;
}

export function selectAudioCandidates(streams: Object[],
  quality: AudioQuality = 'standard'): AudioCandidate[] {
  return selectDashAudioCandidates(streams, quality);
}

export function selectProgressiveCandidates(streams: Object[]): AudioCandidate[] {
  if (streams.length === 0) {
    return [];
  }
  const stream = objectValue(streams[0]);
  const candidates: string[] = [];
  const baseUrl = stringValue(stream.url).trim();
  if (baseUrl.length > 0) {
    candidates.push(baseUrl);
  }
  const backupValues = arrayValue(stream.backupUrl).length > 0
    ? arrayValue(stream.backupUrl)
    : arrayValue(stream.backup_url);
  for (const value of backupValues) {
    const item = stringValue(value).trim();
    if (item.length > 0) {
      candidates.push(item);
    }
  }
  const selected: AudioCandidate[] = [];
  for (const candidate of candidates) {
    if (isHttpsUrl(candidate) &&
      !selected.some((item: AudioCandidate): boolean => item.url === candidate)) {
      selected.push({
        url: candidate,
        id: 0,
        mimeType: 'video/mp4',
        codecs: 'aac',
        bandwidth: 0,
        source: 'mp4'
      });
    }
  }
  return selected;
}

export function toHttpsUrl(value: string): string {
  const clean = value.trim();
  if (clean.startsWith('//')) {
    return `https:${clean}`;
  }
  if (clean.startsWith('http://')) {
    return `https://${clean.slice(7)}`;
  }
  return clean;
}

function rankSeed(raw: Object): TrackSeed {
  const item = objectValue(raw);
  const related = objectValue(item.related_archive);
  return {
    bvid: stringValue(related.bvid, stringValue(item.bvid)).trim(),
    aid: numberValue(item.aid, numberValue(related.aid)),
    cid: numberValue(item.cid, numberValue(related.cid)),
    title: stringValue(item.music_title, stringValue(item.title)).trim(),
    artist: stringValue(item.author, '未知作者').trim(),
    coverUrl: toHttpsUrl(stringValue(related.cover, stringValue(item.cover))),
    duration: parseDuration(item.duration),
    playCount: Math.max(0, numberValue(item.total_vv))
  };
}

function recommendationSeed(raw: Object): TrackSeed {
  const item = objectValue(raw);
  const owner = objectValue(item.owner);
  const stat = objectValue(item.stat);
  return {
    bvid: stringValue(item.bvid).trim(),
    aid: numberValue(item.aid, numberValue(item.id)),
    cid: numberValue(item.cid),
    title: stringValue(item.title).trim(),
    artist: stringValue(owner.name, stringValue(item.author, '未知作者')).trim(),
    coverUrl: toHttpsUrl(stringValue(item.pic, stringValue(item.cover))),
    duration: parseDuration(item.duration),
    playCount: Math.max(0, numberValue(stat.view, numberValue(item.play)))
  };
}

function searchSeed(raw: Object): TrackSeed {
  const item = objectValue(raw);
  return {
    bvid: stringValue(item.bvid).trim(),
    aid: numberValue(item.aid, numberValue(item.id)),
    cid: numberValue(item.cid),
    title: stripHtml(stringValue(item.title)).trim(),
    artist: stripHtml(stringValue(item.author, '未知作者')).trim(),
    coverUrl: toHttpsUrl(stringValue(item.pic)),
    duration: parseDuration(item.duration),
    playCount: Math.max(0, numberValue(item.play))
  };
}

function trackFromSeed(seed: TrackSeed): MobileTrack | null {
  if (seed.cid <= 0 || seed.title.length === 0 || (seed.bvid.length === 0 && seed.aid <= 0)) {
    return null;
  }
  const keyBase = seed.bvid.length > 0 ? seed.bvid : `av${seed.aid}`;
  return {
    key: `${keyBase}:${seed.cid}`,
    bvid: seed.bvid,
    aid: seed.aid,
    cid: seed.cid,
    title: seed.title,
    artist: seed.artist.length > 0 ? seed.artist : '未知作者',
    coverUrl: seed.coverUrl,
    duration: seed.duration,
    playCount: seed.playCount
  };
}

function parseDuration(value: Object | undefined): number {
  if (typeof value === 'number') {
    return Math.max(0, value);
  }
  const text = stringValue(value).trim();
  if (text.length === 0) {
    return 0;
  }
  if (/^\d+$/u.test(text)) {
    return Math.max(0, Number(text));
  }
  const parts = text.split(':');
  if (parts.length < 2 || parts.length > 3) {
    return 0;
  }
  let seconds = 0;
  for (const part of parts) {
    const parsed = Number(part);
    if (!Number.isFinite(parsed)) {
      return 0;
    }
    seconds = seconds * 60 + parsed;
  }
  return Math.max(0, seconds);
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]*>/gu, '').replace(/&amp;/gu, '&')
    .replace(/&quot;/gu, '"').replace(/&#39;/gu, '\'')
    .replace(/&lt;/gu, '<').replace(/&gt;/gu, '>');
}

function clampInteger(value: number, minimum: number, maximum: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback;
  }
  return Math.max(minimum, Math.min(maximum, Math.floor(value)));
}

function assertSuccess(response: Record<string, Object>, code: string): void {
  const apiResult = apiCode(response);
  if (apiResult === 0) {
    return;
  }
  const retryable = apiResult === -412 || apiResult === -352 || apiResult === -509;
  throw new NativeError(code, apiMessage(response), retryable);
}

function isHttpsUrl(value: string): boolean {
  try {
    const parsed = url.URL.parseURL(value);
    return parsed.protocol === 'https:' && parsed.hostname.length > 0;
  } catch (error) {
    return false;
  }
}
