import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  LibraryMutationResult,
  LibraryStore
} from '../services/LibraryStore';
import {
  AppError,
  LibrarySnapshot,
  MobileTrack,
  Playlist,
  SavedResult
} from '../types/MobileTypes';
import { trackKeySet } from './KeySets';
import { toAppError, NativeError } from '../util/Errors';

const DOMAIN = 0x424D;
const TAG = 'WispMusicLibraryModel';

export interface LibraryStoreModelListener {
  onLibraryChanged(snapshot: LibrarySnapshot): void;
  onLibraryError(error: AppError): void;
}

@Observed
export class LibraryStoreModel {
  @Track snapshot: LibrarySnapshot;
  @Track error: AppError | null = null;
  /** 收藏 key 的 O(1) 索引；与 `snapshot.favorites` 同源，随快照整份替换。 */
  @Track private favoriteKeySet: Set<string> = new Set<string>();

  private readonly store: LibraryStore;
  private mutationChain: Promise<void> = Promise.resolve();
  private readonly listeners: LibraryStoreModelListener[] = [];

  constructor(store: LibraryStore) {
    this.store = store;
    this.snapshot = store.read();
    this.favoriteKeySet = trackKeySet(this.snapshot.favorites);
  }

  read(): LibrarySnapshot {
    return cloneLibrary(this.snapshot);
  }

  isFavorite(trackKey: string): boolean {
    const key = cleanKey(trackKey);
    return key.length > 0 && this.favoriteKeySet.has(key);
  }

  favoriteTracks(): MobileTrack[] {
    return cloneTracks(this.snapshot.favorites);
  }

  recentTracks(): MobileTrack[] {
    return cloneTracks(this.snapshot.recent);
  }

  playlistList(): Playlist[] {
    return clonePlaylists(this.snapshot.playlists);
  }

  playlistById(playlistId: string): Playlist | null {
    const index = this.playlistIndex(playlistId);
    return index < 0 ? null : clonePlaylist(this.snapshot.playlists[index]);
  }

  playlistIndex(playlistId: string): number {
    const id = cleanKey(playlistId);
    if (id.length === 0) {
      return -1;
    }
    for (let index = 0; index < this.snapshot.playlists.length; index++) {
      if (this.snapshot.playlists[index].id === id) {
        return index;
      }
    }
    return -1;
  }

  position(trackKey: string): number {
    return this.store.position(cleanKey(trackKey));
  }

  subscribe(listener: LibraryStoreModelListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: LibraryStoreModelListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  clearError(): void {
    if (this.error !== null) {
      this.error = null;
    }
  }

  toggleFavorite(track: MobileTrack): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.toggleFavorite(track));
  }

  removeFavorites(trackKeys: string[]): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.removeFavorites(trackKeys));
  }

  recordRecent(track: MobileTrack): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.recordRecent(track));
  }

  clearRecent(): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.clearRecent());
  }

  removeRecent(trackKeys: string[]): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.removeRecent(trackKeys));
  }

  createPlaylist(name: string, coverUri: string = '', description: string = ''): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> =>
      this.store.createPlaylist(name, coverUri, description));
  }

  createPlaylistWithTracks(name: string, tracks: MobileTrack[], coverUri: string = '',
    description: string = ''): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> =>
      this.store.createPlaylistWithTracks(name, tracks, coverUri, description));
  }

  renamePlaylist(playlistId: string, name: string): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.renamePlaylist(playlistId, name));
  }

  updatePlaylist(playlistId: string, name: string, coverUri: string = '',
    description: string = ''): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> =>
      this.store.updatePlaylist(playlistId, name, coverUri, description));
  }

  deletePlaylist(playlistId: string): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.deletePlaylist(playlistId));
  }

  addToPlaylist(playlistId: string, track: MobileTrack): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.addToPlaylist(playlistId, track));
  }

  addTracksToPlaylist(playlistId: string, tracks: MobileTrack[]): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> =>
      this.store.addTracksToPlaylist(playlistId, tracks));
  }

  removeFromPlaylist(playlistId: string, trackKey: string): Promise<LibraryMutationResult> {
    return this.runMutation((): Promise<LibraryMutationResult> => this.store.removeFromPlaylist(playlistId, trackKey));
  }

  removeTracksFromPlaylist(playlistId: string, trackKeys: string[]): Promise<LibraryMutationResult> {
    return this.runMutation(
      (): Promise<LibraryMutationResult> => this.store.removeTracksFromPlaylist(playlistId, trackKeys)
    );
  }

  async replace(snapshot: LibrarySnapshot): Promise<SavedResult> {
    const result = await this.runMutation(async (): Promise<LibraryMutationResult> => {
      const saved = await this.store.write(snapshot);
      return {
        changed: saved.saved,
        snapshot: this.store.read(),
        playlist: null
      };
    });
    return {
      saved: result.changed,
      updatedAt: result.snapshot.updatedAt
    };
  }

  async flush(): Promise<void> {
    await this.mutationChain.catch((): void => {});
    await this.store.flush();
  }

  private runMutation(operation: () => Promise<LibraryMutationResult>): Promise<LibraryMutationResult> {
    const pending: Promise<LibraryMutationResult> = this.mutationChain
      .catch((): void => {})
      .then((): Promise<LibraryMutationResult> => this.applyMutation(operation));
    this.mutationChain = pending.then((): void => {}, (): void => {});
    return pending;
  }

  private async applyMutation(operation: () => Promise<LibraryMutationResult>): Promise<LibraryMutationResult> {
    try {
      const result = await operation();
      this.snapshot = cloneLibrary(result.snapshot);
      this.favoriteKeySet = trackKeySet(this.snapshot.favorites);
      this.error = null;
      this.emitChanged(this.snapshot);
      return {
        changed: result.changed,
        snapshot: cloneLibrary(result.snapshot),
        playlist: result.playlist === null ? null : clonePlaylist(result.playlist)
      };
    } catch (error) {
      const appFailure = toAppError(error as Object);
      this.error = appFailure;
      this.emitError(appFailure);
      throw new NativeError(appFailure.code, appFailure.message, appFailure.retryable);
    }
  }

  private emitChanged(snapshot: LibrarySnapshot): void {
    const owned = cloneLibrary(snapshot);
    // 遍历快照：listener 在回调里 dispose 另一个 listener 时不能漏通知后续监听者。
    for (const listener of this.listeners.slice()) {
      try {
        listener.onLibraryChanged(cloneLibrary(owned));
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'library listener failed: %{public}s', toAppError(error as Object).code);
      }
    }
  }

  private emitError(error: AppError): void {
    for (const listener of this.listeners.slice()) {
      try {
        listener.onLibraryError(error);
      } catch (listenerError) {
        hilog.warn(DOMAIN, TAG, 'library error listener failed: %{public}s',
          toAppError(listenerError as Object).code);
      }
    }
  }
}

function cleanKey(value: string): string {
  return value.trim().slice(0, 80);
}

function cloneTracks(tracks: MobileTrack[]): MobileTrack[] {
  return JSON.parse(JSON.stringify(tracks)) as MobileTrack[];
}

function clonePlaylists(playlists: Playlist[]): Playlist[] {
  return JSON.parse(JSON.stringify(playlists)) as Playlist[];
}

function clonePlaylist(playlist: Playlist): Playlist {
  return JSON.parse(JSON.stringify(playlist)) as Playlist;
}

function cloneLibrary(snapshot: LibrarySnapshot): LibrarySnapshot {
  return JSON.parse(JSON.stringify(snapshot)) as LibrarySnapshot;
}
