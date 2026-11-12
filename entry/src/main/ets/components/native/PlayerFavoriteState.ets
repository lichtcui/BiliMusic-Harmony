import {
  LibraryStoreModel,
  LibraryStoreModelListener
} from '../../state/LibraryStoreModel';
import {
  PlayerProgressSnapshot,
  PlayerStore,
  PlayerStoreListener,
  PlayerViewSnapshot
} from '../../state/PlayerStore';
import { AppError, LibrarySnapshot, MobileTrack } from '../../types/MobileTypes';

/**
 * Exposes the favourite state of the track that is currently playing.
 *
 * The player page only knows the player and lyrics stores, so this adapter keeps the library
 * dependency out of the page and follows the same observed-state pattern as PlayerPageState.
 */
@Observed
export class PlayerFavoriteState implements LibraryStoreModelListener, PlayerStoreListener {
  @Track favorited: boolean = false;
  @Track pending: boolean = false;
  @Track error: AppError | null = null;

  private model: LibraryStoreModel | null = null;
  private playerStore: PlayerStore | null = null;
  private trackKey: string = '';
  private disposed: boolean = false;

  constructor(model: LibraryStoreModel, playerStore: PlayerStore) {
    this.model = model;
    this.playerStore = playerStore;
    this.trackKey = trackKeyOf(playerStore.snapshot);
    this.refresh();
  }

  attach(): void {
    if (this.disposed) {
      return;
    }
    this.model?.subscribe(this);
    this.playerStore?.subscribe(this);
  }

  onState(snapshot: PlayerViewSnapshot): void {
    if (this.disposed) {
      return;
    }
    const nextKey = trackKeyOf(snapshot);
    if (nextKey === this.trackKey) {
      return;
    }
    this.trackKey = nextKey;
    this.error = null;
    this.refresh();
  }

  onProgress(_progress: PlayerProgressSnapshot): void {
  }

  onError(_error: AppError): void {
  }

  onLibraryChanged(_snapshot: LibrarySnapshot): void {
    if (this.disposed) {
      return;
    }
    this.refresh();
  }

  onLibraryError(error: AppError): void {
    if (this.disposed) {
      return;
    }
    this.error = cloneError(error);
  }

  async toggle(track: MobileTrack | null): Promise<void> {
    const model = this.model;
    if (this.disposed || model === null || track === null || this.pending) {
      return;
    }
    if (track.key.length === 0) {
      return;
    }
    this.pending = true;
    this.error = null;
    try {
      await model.toggleFavorite(track);
      this.refresh();
    } catch (_error) {
      this.error = cloneError(model.error);
    } finally {
      if (!this.disposed) {
        this.pending = false;
      }
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.model?.unsubscribe(this);
    this.playerStore?.unsubscribe(this);
    this.model = null;
    this.playerStore = null;
  }

  private refresh(): void {
    const model = this.model;
    this.favorited = model !== null && this.trackKey.length > 0 && model.isFavorite(this.trackKey);
  }
}

function trackKeyOf(snapshot: PlayerViewSnapshot): string {
  return snapshot.track === null ? '' : snapshot.track.key;
}

function cloneError(error: AppError | null): AppError | null {
  if (error === null) {
    return null;
  }
  return {
    code: error.code,
    message: error.message,
    retryable: error.retryable
  };
}
