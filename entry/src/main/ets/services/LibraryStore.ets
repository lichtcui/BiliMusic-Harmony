import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AppError,
  LibrarySnapshot,
  MobileTrack,
  Playlist,
  SavedResult,
  STORAGE_VERSION,
  emptyLibrary
} from '../types/MobileTypes';
import {
  preserveCorruptFile,
  readAtomicText,
  readAtomicTextAsync,
  writeAtomicText
} from '../util/AtomicJson';
import { NativeError, toAppError } from '../util/Errors';
import {
  arrayValue,
  numberValue,
  objectValue,
  stringValue
} from '../util/Json';

const DOMAIN = 0x424D;
const TAG = 'WispMusicLibrary';
const MAX_FAVORITES = 500;
const MAX_RECENT = 30;
const MAX_PLAYLISTS = 100;
const MAX_PLAYLIST_TRACKS = 500;
const MAX_POSITIONS = 1000;
/** 与 `PlaylistStore` 的 `PLAYLIST_DESCRIPTION_MAX_LENGTH` 保持一致。 */
const MAX_PLAYLIST_DESCRIPTION = 200;
/** 自定义封面只接受 app 沙箱内的 `file://` URI，路径再长也不会超过这个上限。 */
const MAX_PLAYLIST_COVER_URI = 1024;
const DEFAULT_PLAYLIST_NAME = '未命名歌单';

export interface LibraryMutationResult {
  changed: boolean;
  snapshot: LibrarySnapshot;
  playlist: Playlist | null;
}

export interface LibraryStorageDiagnostics {
  recovered: boolean;
  error: AppError | null;
}

export interface LibraryPersistence {
  read(path: string): string | null;
  readAsync(path: string): Promise<string | null>;
  write(path: string, content: string): Promise<void>;
  preserveCorrupt(path: string): void;
}

class AtomicLibraryPersistence implements LibraryPersistence {
  read(path: string): string | null {
    return readAtomicText(path);
  }

  readAsync(path: string): Promise<string | null> {
    return readAtomicTextAsync(path);
  }

  write(path: string, content: string): Promise<void> {
    return writeAtomicText(path, content);
  }

  preserveCorrupt(path: string): void {
    preserveCorruptFile(path);
  }
}

type LibraryMutationKind =
  'replace' |
  'toggleFavorite' |
  'removeFavorites' |
  'recordRecent' |
  'clearRecent' |
  'removeRecent' |
  'createPlaylist' |
  'createPlaylistWithTracks' |
  'renamePlaylist' |
  'updatePlaylist' |
  'deletePlaylist' |
  'addToPlaylist' |
  'addTracksToPlaylist' |
  'removeFromPlaylist' |
  'removeTracksFromPlaylist' |
  'setPosition';

interface LibraryMutationCommand {
  kind: LibraryMutationKind;
  track?: MobileTrack;
  tracks?: MobileTrack[];
  trackKey?: string;
  trackKeys?: string[];
  playlistId?: string;
  name?: string;
  coverUri?: string;
  description?: string;
  seconds?: number;
  snapshot?: LibrarySnapshot;
}

export class LibraryStore {
  private readonly path: string;
  private readonly persistence: LibraryPersistence;
  private snapshot: LibrarySnapshot = emptyLibrary();
  private mutationChain: Promise<void> = Promise.resolve();
  private loaded: boolean = false;
  private readonly positionThrottle: Map<string, number> = new Map<string, number>();
  private storageDiagnosticsValue: LibraryStorageDiagnostics = {
    recovered: false,
    error: null
  };

  constructor(path: string, persistence: LibraryPersistence = new AtomicLibraryPersistence(),
    deferLoad: boolean = false) {
    this.path = path;
    this.persistence = persistence;
    if (!deferLoad) {
      this.snapshot = this.load();
      this.loaded = true;
    }
  }

  /**
   * 冷启动专用：先返回空快照实例，再由调用方 `await loadAsync()`。
   * 这样读盘可以和媒体会话初始化并行，首帧不必等资料库解析完 JSON。
   */
  static deferred(path: string,
    persistence: LibraryPersistence = new AtomicLibraryPersistence()): LibraryStore {
    return new LibraryStore(path, persistence, true);
  }

  /**
   * 异步加载资料库。调用方必须在 `createPlaylist`/`toggleFavorite` 等写操作
   * 之前 await 它，否则会覆盖磁盘上尚未读入的快照。
   */
  async loadAsync(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const content = await this.persistence.readAsync(this.path);
    if (this.loaded) {
      return;
    }
    this.snapshot = this.parseContent(content);
    this.loaded = true;
  }

  read(): LibrarySnapshot {
    return cloneLibrary(this.snapshot);
  }

  position(trackKey: string): number {
    const value = this.snapshot.positions[trackKey];
    return value !== undefined && Number.isFinite(value) && value >= 0 ? value : 0;
  }

  storageDiagnostics(): LibraryStorageDiagnostics {
    return {
      recovered: this.storageDiagnosticsValue.recovered,
      error: cloneAppError(this.storageDiagnosticsValue.error)
    };
  }

  async write(raw: Object): Promise<SavedResult> {
    const result = await this.mutate({
      kind: 'replace',
      snapshot: sanitizeLibrary(objectValue(raw))
    });
    return {
      saved: result.changed,
      updatedAt: result.snapshot.updatedAt
    };
  }

  toggleFavorite(track: MobileTrack): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'toggleFavorite',
      track: track
    });
  }

  /** 「我喜欢的 · 多选」移除：一次写入删掉多个收藏，不走逐条 toggle。 */
  removeFavorites(trackKeys: string[]): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'removeFavorites',
      trackKeys: trackKeys
    });
  }

  recordRecent(track: MobileTrack): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'recordRecent',
      track: track
    });
  }

  clearRecent(): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'clearRecent'
    });
  }

  /** 「历史 · 多选」移除：只删最近播放记录，不动收藏和歌单。 */
  removeRecent(trackKeys: string[]): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'removeRecent',
      trackKeys: trackKeys
    });
  }

  createPlaylist(name: string, coverUri: string = '', description: string = ''): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'createPlaylist',
      name: name,
      coverUri: coverUri,
      description: description
    });
  }

  /**
   * 新建歌单并一次性写入曲目：创建与加曲在同一个 mutation 内完成，
   * 容量 / 曲目校验失败不会留下空歌单。
   */
  createPlaylistWithTracks(name: string, tracks: MobileTrack[], coverUri: string = '',
    description: string = ''): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'createPlaylistWithTracks',
      name: name,
      tracks: tracks,
      coverUri: coverUri,
      description: description
    });
  }

  renamePlaylist(playlistId: string, name: string): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'renamePlaylist',
      playlistId: playlistId,
      name: name
    });
  }

  /**
   * 「修改歌单信息」：名称 / 简介 / 自定义封面一次性写入，只产生一次持久化。
   * 名称由状态层先校验；这里沿用小写清洗（空名回落到默认名），与创建 / 重命名同口径。
   */
  updatePlaylist(playlistId: string, name: string, coverUri: string = '',
    description: string = ''): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'updatePlaylist',
      playlistId: playlistId,
      name: name,
      coverUri: coverUri,
      description: description
    });
  }

  deletePlaylist(playlistId: string): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'deletePlaylist',
      playlistId: playlistId
    });
  }

  addToPlaylist(playlistId: string, track: MobileTrack): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'addToPlaylist',
      playlistId: playlistId,
      track: track
    });
  }

  /** 批量加入歌单：输入去重、跳过已有曲目，容量不足时整体失败。 */
  addTracksToPlaylist(playlistId: string, tracks: MobileTrack[]): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'addTracksToPlaylist',
      playlistId: playlistId,
      tracks: tracks
    });
  }

  removeFromPlaylist(playlistId: string, trackKey: string): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'removeFromPlaylist',
      playlistId: playlistId,
      trackKey: trackKey
    });
  }

  removeTracksFromPlaylist(playlistId: string, trackKeys: string[]): Promise<LibraryMutationResult> {
    return this.mutate({
      kind: 'removeTracksFromPlaylist',
      playlistId: playlistId,
      trackKeys: trackKeys
    });
  }

  /**
   * 记录当前播放位置。整个资料库只保留这一条位置记录：
   * 切换曲目后上一首的进度不再保留，避免以后被当作续播位置。
   */
  updatePosition(trackKey: string, seconds: number, force: boolean = false): void {
    const key = cleanPositionKey(trackKey);
    const position = Math.max(0, Math.floor(Number(seconds)));
    if (key.length === 0 || !Number.isFinite(position)) {
      return;
    }
    const now = Date.now();
    const last = this.positionThrottle.get(key) ?? 0;
    if (!force && now - last < 5_000) {
      return;
    }
    if (!this.positionThrottle.has(key) && this.positionThrottle.size >= MAX_POSITIONS) {
      for (const oldestKey of this.positionThrottle.keys()) {
        this.positionThrottle.delete(oldestKey);
        break;
      }
    }
    this.positionThrottle.set(key, now);
    void this.mutate({
      kind: 'setPosition',
      trackKey: key,
      seconds: position
    }).catch((error: Object): void => {
      const appFailure = toAppError(error);
      this.storageDiagnosticsValue.error = appFailure;
      hilog.warn(DOMAIN, TAG, 'position persistence failed code=%{public}s', appFailure.code);
    });
  }

  async flush(): Promise<void> {
    await this.mutationChain.catch((): void => {});
  }

  private mutate(command: LibraryMutationCommand): Promise<LibraryMutationResult> {
    const pending: Promise<LibraryMutationResult> = this.mutationChain
      .catch((): void => {})
      .then((): Promise<LibraryMutationResult> => this.applyMutation(command));
    this.mutationChain = pending.then((): void => {}, (): void => {});
    return pending;
  }

  private async applyMutation(command: LibraryMutationCommand): Promise<LibraryMutationResult> {
    const current = this.snapshot;
    const next = cloneLibrary(current);
    let changed = false;
    let resultPlaylist: Playlist | null = null;

    if (command.kind === 'replace') {
      const replacement = cloneLibrary(command.snapshot ?? emptyLibrary());
      replacement.positions = clonePositions(current.positions);
      next.favorites = replacement.favorites;
      next.playlists = replacement.playlists;
      next.recent = replacement.recent;
      next.positions = replacement.positions;
      next.updatedAt = Math.max(Date.now(), replacement.updatedAt, current.updatedAt + 1);
      changed = true;
    } else if (command.kind === 'toggleFavorite') {
      const track = normalizedMutationTrack(command.track);
      const index = findFavoriteIndex(next.favorites, track.key);
      if (index >= 0) {
        next.favorites.splice(index, 1);
      } else {
        next.favorites.unshift(track);
        next.favorites = next.favorites.slice(0, MAX_FAVORITES);
      }
      changed = true;
    } else if (command.kind === 'removeFavorites') {
      const keys = cleanTrackKeys(command.trackKeys);
      if (keys.size > 0) {
        const previousLength = next.favorites.length;
        next.favorites = next.favorites.filter((track: MobileTrack): boolean => !keys.has(track.key));
        if (next.favorites.length !== previousLength) {
          changed = true;
        }
      }
    } else if (command.kind === 'recordRecent') {
      const track = normalizedMutationTrack(command.track);
      if (next.recent.length === 0 || next.recent[0].key !== track.key) {
        next.recent = [track, ...next.recent.filter((item: MobileTrack): boolean => item.key !== track.key)]
          .slice(0, MAX_RECENT);
        changed = true;
      }
    } else if (command.kind === 'clearRecent') {
      if (next.recent.length > 0) {
        next.recent = [];
        changed = true;
      }
    } else if (command.kind === 'removeRecent') {
      const keys = cleanTrackKeys(command.trackKeys);
      if (keys.size > 0) {
        const previousLength = next.recent.length;
        next.recent = next.recent.filter((track: MobileTrack): boolean => !keys.has(track.key));
        if (next.recent.length !== previousLength) {
          changed = true;
        }
      }
    } else if (command.kind === 'createPlaylist') {
      if (next.playlists.length >= MAX_PLAYLISTS) {
        throw new NativeError('library.playlistLimit', '歌单数量已达上限。');
      }
      const timestamp = nextUpdateTime(current);
      resultPlaylist = {
        id: nextPlaylistId(next.playlists),
        name: cleanPlaylistName(command.name),
        tracks: [],
        createdAt: timestamp,
        updatedAt: timestamp,
        coverUri: cleanPlaylistCoverUri(command.coverUri),
        description: cleanPlaylistDescription(command.description)
      };
      next.playlists.unshift(resultPlaylist);
      changed = true;
    } else if (command.kind === 'createPlaylistWithTracks') {
      if (next.playlists.length >= MAX_PLAYLISTS) {
        throw new NativeError('library.playlistLimit', '歌单数量已达上限。');
      }
      const tracks = normalizedMutationTracks(command.tracks);
      if (tracks.length > MAX_PLAYLIST_TRACKS) {
        throw new NativeError('library.playlistFull', '歌单曲目已达上限。');
      }
      const timestamp = nextUpdateTime(current);
      resultPlaylist = {
        id: nextPlaylistId(next.playlists),
        name: cleanPlaylistName(command.name),
        tracks: tracks,
        createdAt: timestamp,
        updatedAt: timestamp,
        coverUri: cleanPlaylistCoverUri(command.coverUri),
        description: cleanPlaylistDescription(command.description)
      };
      next.playlists.unshift(resultPlaylist);
      changed = true;
    } else if (command.kind === 'renamePlaylist') {
      const index = requiredPlaylistIndex(next.playlists, command.playlistId);
      const playlist = next.playlists[index];
      const name = cleanPlaylistName(command.name);
      if (playlist.name !== name) {
        playlist.name = name;
        playlist.updatedAt = nextUpdateTime(current);
        changed = true;
      }
      resultPlaylist = playlist;
    } else if (command.kind === 'updatePlaylist') {
      const index = requiredPlaylistIndex(next.playlists, command.playlistId);
      const playlist = next.playlists[index];
      const name = cleanPlaylistName(command.name);
      const coverUri = cleanPlaylistCoverUri(command.coverUri);
      const description = cleanPlaylistDescription(command.description);
      if (playlist.name !== name || playlist.coverUri !== coverUri ||
        playlist.description !== description) {
        playlist.name = name;
        playlist.coverUri = coverUri;
        playlist.description = description;
        playlist.updatedAt = nextUpdateTime(current);
        changed = true;
      }
      resultPlaylist = playlist;
    } else if (command.kind === 'deletePlaylist') {
      const index = requiredPlaylistIndex(next.playlists, command.playlistId);
      next.playlists.splice(index, 1);
      changed = true;
    } else if (command.kind === 'addToPlaylist') {
      const index = requiredPlaylistIndex(next.playlists, command.playlistId);
      const playlist = next.playlists[index];
      const track = normalizedMutationTrack(command.track);
      if (findTrackIndex(playlist.tracks, track.key) < 0) {
        if (playlist.tracks.length >= MAX_PLAYLIST_TRACKS) {
          throw new NativeError('library.playlistFull', '歌单曲目已达上限。');
        }
        playlist.tracks.push(track);
        playlist.updatedAt = nextUpdateTime(current);
        changed = true;
      }
      resultPlaylist = playlist;
    } else if (command.kind === 'addTracksToPlaylist') {
      const index = requiredPlaylistIndex(next.playlists, command.playlistId);
      const playlist = next.playlists[index];
      const existing: Set<string> = new Set<string>();
      for (const track of playlist.tracks) {
        existing.add(track.key);
      }
      const missing: MobileTrack[] = [];
      for (const track of normalizedMutationTracks(command.tracks)) {
        if (!existing.has(track.key)) {
          existing.add(track.key);
          missing.push(track);
        }
      }
      if (playlist.tracks.length + missing.length > MAX_PLAYLIST_TRACKS) {
        throw new NativeError('library.playlistFull', '歌单曲目已达上限。');
      }
      if (missing.length > 0) {
        for (const track of missing) {
          playlist.tracks.push(track);
        }
        playlist.updatedAt = nextUpdateTime(current);
        changed = true;
      }
      resultPlaylist = playlist;
    } else if (command.kind === 'removeFromPlaylist') {
      const index = requiredPlaylistIndex(next.playlists, command.playlistId);
      const playlist = next.playlists[index];
      const trackIndex = findTrackIndex(playlist.tracks, cleanPositionKey(command.trackKey));
      if (trackIndex >= 0) {
        playlist.tracks.splice(trackIndex, 1);
        playlist.updatedAt = nextUpdateTime(current);
        changed = true;
      }
      resultPlaylist = playlist;
    } else if (command.kind === 'removeTracksFromPlaylist') {
      const index = requiredPlaylistIndex(next.playlists, command.playlistId);
      const playlist = next.playlists[index];
      const keys = cleanTrackKeys(command.trackKeys);
      const previousLength = playlist.tracks.length;
      if (keys.size > 0) {
        playlist.tracks = playlist.tracks.filter((track: MobileTrack): boolean => !keys.has(track.key));
      }
      if (playlist.tracks.length !== previousLength) {
        playlist.updatedAt = nextUpdateTime(current);
        changed = true;
      }
      resultPlaylist = playlist;
    } else if (command.kind === 'setPosition') {
      const key = cleanPositionKey(command.trackKey);
      const seconds = Math.max(0, Math.floor(command.seconds ?? 0));
      if (key.length === 0 || !Number.isFinite(seconds)) {
        return unchangedResult(current);
      }
      const keys = Object.keys(next.positions);
      if (next.positions[key] !== seconds || keys.length !== 1) {
        // 只为当前播放曲目保留一条位置：切歌时立即丢弃上一首的进度。
        next.positions = {};
        next.positions[key] = seconds;
        changed = true;
      }
    }

    if (!changed) {
      return {
        changed: false,
        snapshot: cloneLibrary(current),
        playlist: resultPlaylist === null ? null : clonePlaylist(resultPlaylist)
      };
    }
    if (command.kind !== 'replace') {
      next.updatedAt = nextUpdateTime(current);
    }
    try {
      await this.persistence.write(this.path, JSON.stringify(next));
    } catch (error) {
      const failure = new NativeError('library.writeFailed', '本地资料保存失败，请稍后重试。', true);
      hilog.error(DOMAIN, TAG, 'library write failed code=%{public}s', failure.appError.code);
      this.storageDiagnosticsValue.error = failure.appError;
      throw failure;
    }
    this.storageDiagnosticsValue.error = null;
    this.snapshot = next;
    return {
      changed: true,
      snapshot: cloneLibrary(next),
      playlist: resultPlaylist === null ? null : clonePlaylist(resultPlaylist)
    };
  }

  private load(): LibrarySnapshot {
    return this.parseContent(this.persistence.read(this.path));
  }

  private parseContent(content: string | null): LibrarySnapshot {
    if (content === null) {
      return emptyLibrary();
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(content) as Object;
    } catch (error) {
      return this.recoverFromInvalidState(
        new NativeError('library.corrupt', '本地资料已损坏，已使用默认数据。', true)
      );
    }
    const raw = objectValue(parsed);
    if (numberValue(raw.version) !== STORAGE_VERSION) {
      return this.recoverFromInvalidState(
        new NativeError('library.unsupportedVersion', '本地资料版本不受支持，已使用默认数据。')
      );
    }
    return sanitizeLibrary(raw);
  }

  private recoverFromInvalidState(failure: NativeError): LibrarySnapshot {
    hilog.warn(DOMAIN, TAG, 'library recovery code=%{public}s', failure.appError.code);
    this.persistence.preserveCorrupt(this.path);
    this.storageDiagnosticsValue = {
      recovered: true,
      error: failure.appError
    };
    return emptyLibrary();
  }
}

export function sanitizeLibrary(raw: Record<string, Object>): LibrarySnapshot {
  const favorites = cleanTracks(arrayValue(raw.favorites)).slice(0, MAX_FAVORITES);
  const recent = cleanTracks(arrayValue(raw.recent)).slice(0, MAX_RECENT);
  const playlists = cleanPlaylists(arrayValue(raw.playlists));
  const positions = cleanPositions(raw.positions);
  return {
    version: STORAGE_VERSION,
    favorites: favorites,
    playlists: playlists,
    recent: recent,
    positions: positions,
    updatedAt: Math.max(0, numberValue(raw.updatedAt))
  };
}

function unchangedResult(current: LibrarySnapshot): LibraryMutationResult {
  return {
    changed: false,
    snapshot: cloneLibrary(current),
    playlist: null
  };
}

function normalizedMutationTrack(track: MobileTrack | undefined): MobileTrack {
  if (track === undefined) {
    throw new NativeError('library.invalidTrack', '曲目信息不完整。');
  }
  const cleaned = cleanTrackFields(
    track.bvid,
    track.aid,
    track.cid,
    track.title,
    track.artist,
    track.coverUrl,
    track.duration,
    track.playCount
  );
  if (cleaned === null) {
    throw new NativeError('library.invalidTrack', '曲目信息不完整。');
  }
  return cleaned;
}

function normalizedMutationTracks(tracks: MobileTrack[] | undefined): MobileTrack[] {
  const normalized: MobileTrack[] = [];
  const seen: Set<string> = new Set<string>();
  if (tracks === undefined) {
    return normalized;
  }
  for (const track of tracks) {
    const cleaned = normalizedMutationTrack(track);
    if (!seen.has(cleaned.key)) {
      seen.add(cleaned.key);
      normalized.push(cleaned);
    }
  }
  return normalized;
}

function findFavoriteIndex(tracks: MobileTrack[], key: string): number {
  for (let index = 0; index < tracks.length; index++) {
    if (tracks[index].key === key) {
      return index;
    }
  }
  return -1;
}

function findTrackIndex(tracks: MobileTrack[], key: string): number {
  for (let index = 0; index < tracks.length; index++) {
    if (tracks[index].key === key) {
      return index;
    }
  }
  return -1;
}

function requiredPlaylistIndex(playlists: Playlist[], value: string | undefined): number {
  const id = value === undefined ? '' : value.trim().slice(0, 80);
  for (let index = 0; index < playlists.length; index++) {
    if (playlists[index].id === id) {
      return index;
    }
  }
  throw new NativeError('library.playlistNotFound', '歌单不存在。');
}

function cleanPlaylistName(value: string | undefined): string {
  const name = value === undefined ? '' : value.trim().slice(0, 60);
  return name.length > 0 ? name : DEFAULT_PLAYLIST_NAME;
}

/**
 * 自定义封面只保留 app 沙箱内的 `file://` URI。
 * 旧资料库 / 手工改坏的 JSON 里的其它协议、超长路径一律视为没有自定义封面，
 * 由列表回落到首曲封面，而不是把任意字符串交给 Image 去解析。
 */
function cleanPlaylistCoverUri(value: string | undefined): string {
  const raw = value === undefined ? '' : value.trim().slice(0, MAX_PLAYLIST_COVER_URI);
  if (raw.length === 0 || !raw.toLowerCase().startsWith('file://')) {
    return '';
  }
  return raw;
}

/** 简介保留内部换行，只裁首尾空白并截断到 200 字。 */
function cleanPlaylistDescription(value: string | undefined): string {
  const text = value === undefined ? '' : value.trim().slice(0, MAX_PLAYLIST_DESCRIPTION);
  return text;
}

function nextPlaylistId(playlists: Playlist[]): string {
  const existing: Set<string> = new Set<string>();
  for (const playlist of playlists) {
    existing.add(playlist.id);
  }
  let id = '';
  do {
    id = `pl-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
  } while (existing.has(id));
  return id;
}

function nextUpdateTime(current: LibrarySnapshot): number {
  return Math.max(Date.now(), current.updatedAt + 1);
}

function cleanTracks(values: Object[]): MobileTrack[] {
  const tracks: MobileTrack[] = [];
  const seen: Set<string> = new Set<string>();
  for (const value of values) {
    const track = cleanTrack(objectValue(value));
    if (track === null || seen.has(track.key)) {
      continue;
    }
    seen.add(track.key);
    tracks.push(track);
  }
  return tracks;
}

function cleanTrack(raw: Record<string, Object>): MobileTrack | null {
  return cleanTrackFields(
    stringValue(raw.bvid),
    numberValue(raw.aid),
    numberValue(raw.cid),
    stringValue(raw.title),
    stringValue(raw.artist, '未知作者'),
    stringValue(raw.coverUrl),
    numberValue(raw.duration),
    numberValue(raw.playCount)
  );
}

function cleanTrackFields(bvidValue: string, aidValue: number, cidValue: number, titleValue: string,
  artistValue: string, coverUrlValue: string, durationValue: number,
  playCountValue: number): MobileTrack | null {
  const bvid = bvidValue.trim().slice(0, 32);
  const aid = Math.max(0, Math.floor(aidValue));
  const cid = Math.max(0, Math.floor(cidValue));
  const title = titleValue.trim().slice(0, 300);
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
    artist: artistValue.trim().slice(0, 200),
    coverUrl: cleanCover(coverUrlValue),
    duration: Math.max(0, durationValue),
    playCount: Math.max(0, playCountValue)
  };
}

function cleanPlaylists(values: Object[]): Playlist[] {
  const playlists: Playlist[] = [];
  const seen: Set<string> = new Set<string>();
  for (const value of values) {
    const raw = objectValue(value);
    const id = stringValue(raw.id).trim().slice(0, 80);
    if (id.length === 0 || seen.has(id)) {
      continue;
    }
    seen.add(id);
    const now = Date.now();
    playlists.push({
      id: id,
      name: stringValue(raw.name, DEFAULT_PLAYLIST_NAME).trim().slice(0, 60),
      tracks: cleanTracks(arrayValue(raw.tracks)).slice(0, MAX_PLAYLIST_TRACKS),
      createdAt: Math.max(0, numberValue(raw.createdAt, now)),
      updatedAt: Math.max(0, numberValue(raw.updatedAt, now)),
      coverUri: cleanPlaylistCoverUri(stringValue(raw.coverUri)),
      description: cleanPlaylistDescription(stringValue(raw.description))
    });
    if (playlists.length >= MAX_PLAYLISTS) {
      break;
    }
  }
  return playlists;
}

function cleanPositions(value: Object | undefined): Record<string, number> {
  const raw = objectValue(value);
  const positions: Record<string, number> = {};
  const keys = Object.keys(raw);
  for (const key of keys) {
    if (Object.keys(positions).length >= MAX_POSITIONS) {
      break;
    }
    const cleanKey = cleanPositionKey(key);
    const position = numberValue(raw[key], -1);
    if (cleanKey.length > 0 && position >= 0) {
      positions[cleanKey] = Math.floor(position);
    }
  }
  return positions;
}

function cleanPositionKey(value: string | undefined): string {
  return value === undefined ? '' : value.trim().slice(0, 80);
}

function cleanTrackKeys(values: string[] | undefined): Set<string> {
  const keys: Set<string> = new Set<string>();
  if (values === undefined) {
    return keys;
  }
  for (const value of values) {
    const key = cleanPositionKey(value);
    if (key.length > 0) {
      keys.add(key);
    }
  }
  return keys;
}

function cleanCover(value: string): string {
  const clean = value.trim();
  if (clean.startsWith('//')) {
    return `https:${clean}`;
  }
  if (clean.startsWith('http://')) {
    return `https://${clean.slice(7)}`;
  }
  return clean.startsWith('https://') ? clean : '';
}

function clonePositions(value: Record<string, number>): Record<string, number> {
  const positions: Record<string, number> = {};
  for (const key of Object.keys(value)) {
    positions[key] = value[key];
  }
  return positions;
}

function clonePlaylist(value: Playlist): Playlist {
  return JSON.parse(JSON.stringify(value)) as Playlist;
}

function cloneLibrary(value: LibrarySnapshot): LibrarySnapshot {
  return JSON.parse(JSON.stringify(value)) as LibrarySnapshot;
}

function cloneAppError(value: AppError | null): AppError | null {
  if (value === null) {
    return null;
  }
  return {
    code: value.code,
    message: value.message,
    retryable: value.retryable
  };
}
