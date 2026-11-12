import { describe, expect, it } from '@ohos/hypium';
import { LibraryMutationResult, LibraryPersistence, LibraryStore } from '../main/ets/services/LibraryStore';
import { LibraryStoreModel, LibraryStoreModelListener } from '../main/ets/state/LibraryStoreModel';
import {
  AppError,
  LibrarySnapshot,
  MobileTrack,
  Playlist,
  STORAGE_VERSION
} from '../main/ets/types/MobileTypes';
import { NativeError, wait } from '../main/ets/util/Errors';

class MemoryLibraryModelPersistence implements LibraryPersistence {
  content: string | null = null;
  failWrites: boolean = false;
  activeWrites: number = 0;
  maxActiveWrites: number = 0;

  constructor(content: string | null = null) {
    this.content = content;
  }

  read(_path: string): string | null {
    return this.content;
  }

  readAsync(path: string): Promise<string | null> {
    return Promise.resolve(this.read(path));
  }

  async write(_path: string, content: string): Promise<void> {
    this.activeWrites++;
    this.maxActiveWrites = Math.max(this.maxActiveWrites, this.activeWrites);
    try {
      await wait(2);
      if (this.failWrites) {
        throw new Error('simulated write failure');
      }
      this.content = content;
    } finally {
      this.activeWrites--;
    }
  }

  preserveCorrupt(_path: string): void {
  }
}

class RecordingLibraryModelListener implements LibraryStoreModelListener {
  snapshots: LibrarySnapshot[] = [];
  errors: AppError[] = [];

  onLibraryChanged(snapshot: LibrarySnapshot): void {
    this.snapshots.push(snapshot);
  }

  onLibraryError(error: AppError): void {
    this.errors.push(error);
  }
}

class UnsubscribingLibraryModelListener implements LibraryStoreModelListener {
  snapshots: LibrarySnapshot[] = [];
  errors: AppError[] = [];
  private readonly model: LibraryStoreModel;
  private readonly target: LibraryStoreModelListener;
  private unsubscribed: boolean = false;

  constructor(model: LibraryStoreModel, target: LibraryStoreModelListener) {
    this.model = model;
    this.target = target;
  }

  onLibraryChanged(snapshot: LibrarySnapshot): void {
    this.snapshots.push(snapshot);
    if (!this.unsubscribed) {
      this.unsubscribed = true;
      this.model.unsubscribe(this.target);
    }
  }

  onLibraryError(error: AppError): void {
    this.errors.push(error);
  }
}

function modelTrack(index: number): MobileTrack {
  return {
    key: `untrusted-${index}`,
    bvid: `BV${index}`,
    aid: index,
    cid: index + 200,
    title: `Track ${index}`,
    artist: `Artist ${index}`,
    coverUrl: `https://example.com/${index}.jpg`,
    duration: 180,
    playCount: 20
  };
}

function modelSnapshot(favorites: MobileTrack[], playlists: Playlist[], recent: MobileTrack[]): LibrarySnapshot {
  const positions: Record<string, number> = {};
  positions['BV1:201'] = 45;
  return {
    version: STORAGE_VERSION,
    favorites: favorites,
    playlists: playlists,
    recent: recent,
    positions: positions,
    updatedAt: 10
  };
}

function persistedModelSnapshot(persistence: MemoryLibraryModelPersistence): LibrarySnapshot {
  return JSON.parse(persistence.content ?? '{}') as LibrarySnapshot;
}

export default function libraryStoreModelTest(): void {
  describe('LibraryStoreModel', () => {
    it('initializesSnapshotAndQueries', 0, () => {
      const track = modelTrack(1);
      const playlist: Playlist = {
        id: 'playlist-1',
        name: 'Daily Mix',
        tracks: [track],
        createdAt: 1,
        updatedAt: 2
      };
      const persistence = new MemoryLibraryModelPersistence(JSON.stringify(
        modelSnapshot([track], [playlist], [track])
      ));
      const model = new LibraryStoreModel(new LibraryStore('memory://model', persistence));

      expect(model.isFavorite('BV1:201')).assertTrue();
      expect(model.isFavorite('missing')).assertFalse();
      expect(model.recentTracks().length).assertEqual(1);
      expect(model.playlistList().length).assertEqual(1);
      expect(model.playlistById('playlist-1')?.name).assertEqual('Daily Mix');
      expect(model.playlistIndex('playlist-1')).assertEqual(0);
      expect(model.position('BV1:201')).assertEqual(45);

      model.playlistById('playlist-1')?.tracks.splice(0, 1);
      expect(model.playlistById('playlist-1')?.tracks.length).assertEqual(1);
    });

    it('updatesSnapshotAndNotifiesAllPages', 0, async () => {
      const persistence = new MemoryLibraryModelPersistence();
      const model = new LibraryStoreModel(new LibraryStore('memory://model', persistence));
      const firstPage = new RecordingLibraryModelListener();
      const secondPage = new RecordingLibraryModelListener();
      model.subscribe(firstPage);
      model.subscribe(secondPage);

      const result = await model.toggleFavorite(modelTrack(2));
      expect(result.changed).assertTrue();
      expect(model.isFavorite('BV2:202')).assertTrue();
      expect(firstPage.snapshots.length).assertEqual(1);
      expect(secondPage.snapshots.length).assertEqual(1);
      expect(firstPage.snapshots[0]).assertDeepEquals(model.read());
      expect(secondPage.snapshots[0]).assertDeepEquals(model.read());

      model.unsubscribe(secondPage);
      await model.recordRecent(modelTrack(3));
      expect(firstPage.snapshots.length).assertEqual(2);
      expect(secondPage.snapshots.length).assertEqual(1);
    });

    it('notifiesTheRemainingListenersWhenACallbackUnsubscribesAnother', 0, async () => {
      const persistence = new MemoryLibraryModelPersistence();
      const model = new LibraryStoreModel(new LibraryStore('memory://model', persistence));
      const second = new RecordingLibraryModelListener();
      const first = new UnsubscribingLibraryModelListener(model, second);
      model.subscribe(first);
      model.subscribe(second);

      await model.toggleFavorite(modelTrack(2));

      expect(first.snapshots.length).assertEqual(1);
      // 遍历快照：回调里 unsubscribe 不能截断同一轮剩余监听者。
      expect(second.snapshots.length).assertEqual(1);

      await model.recordRecent(modelTrack(3));
      expect(first.snapshots.length).assertEqual(2);
      expect(second.snapshots.length).assertEqual(1);
    });

    it('keepsOldSnapshotAndExposesWriteFailure', 0, async () => {
      const track = modelTrack(4);
      const persistence = new MemoryLibraryModelPersistence(JSON.stringify(modelSnapshot([track], [], [])));
      const model = new LibraryStoreModel(new LibraryStore('memory://model', persistence));
      const listener = new RecordingLibraryModelListener();
      model.subscribe(listener);
      persistence.failWrites = true;

      let code = '';
      try {
        await model.toggleFavorite(track);
      } catch (error) {
        code = error instanceof NativeError ? error.appError.code : '';
      }

      expect(code).assertEqual('library.writeFailed');
      expect(model.isFavorite('BV4:204')).assertTrue();
      expect(model.read().favorites.length).assertEqual(1);
      expect(listener.snapshots.length).assertEqual(0);
      expect(listener.errors.length).assertEqual(1);
      expect(listener.errors[0].code).assertEqual('library.writeFailed');

      persistence.failWrites = false;
      await model.clearRecent();
      expect(model.error === null).assertTrue();
    });

    it('publishesOnlyTheFinalBatchRemovalSnapshot', 0, async () => {
      const first = modelTrack(1);
      const second = modelTrack(2);
      const third = modelTrack(3);
      const playlist: Playlist = {
        id: 'playlist-batch',
        name: 'Batch',
        tracks: [first, second, third],
        createdAt: 1,
        updatedAt: 2
      };
      const persistence = new MemoryLibraryModelPersistence(JSON.stringify(
        modelSnapshot([], [playlist], [])
      ));
      const model = new LibraryStoreModel(new LibraryStore('memory://model', persistence));
      const listener = new RecordingLibraryModelListener();
      model.subscribe(listener);

      const result = await model.removeTracksFromPlaylist(
        'playlist-batch',
        ['BV1:201', 'BV3:203', 'BV1:201']
      );

      expect(result.changed).assertTrue();
      expect(model.playlistById('playlist-batch')?.tracks.length).assertEqual(1);
      expect(model.playlistById('playlist-batch')?.tracks[0].key).assertEqual('BV2:202');
      expect(listener.snapshots.length).assertEqual(1);
      expect(persistedModelSnapshot(persistence).playlists[0].tracks.length).assertEqual(1);

      persistence.failWrites = true;
      let code = '';
      try {
        await model.removeTracksFromPlaylist('playlist-batch', ['BV2:202']);
      } catch (error) {
        code = error instanceof NativeError ? error.appError.code : '';
      }
      expect(code).assertEqual('library.writeFailed');
      expect(model.playlistById('playlist-batch')?.tracks.length).assertEqual(1);
      expect(listener.snapshots.length).assertEqual(1);
      expect(listener.errors[listener.errors.length - 1].code).assertEqual('library.writeFailed');
    });

    it('serializesRapidCommandsAndPublishesFinalSnapshot', 0, async () => {
      const persistence = new MemoryLibraryModelPersistence();
      const model = new LibraryStoreModel(new LibraryStore('memory://model', persistence));
      const listener = new RecordingLibraryModelListener();
      model.subscribe(listener);
      const pending: Promise<LibraryMutationResult>[] = [];

      for (let index = 0; index < 8; index++) {
        pending.push(model.createPlaylist(`Playlist ${index}`));
        pending.push(model.recordRecent(modelTrack(100 + index)));
      }
      await Promise.all(pending);
      await model.flush();

      expect(persistence.maxActiveWrites).assertEqual(1);
      expect(model.playlistList().length).assertEqual(8);
      expect(model.recentTracks().length).assertEqual(8);
      expect(model.playlistList()[0].name).assertEqual('Playlist 7');
      expect(listener.snapshots[listener.snapshots.length - 1]).assertDeepEquals(model.read());
      expect(persistedModelSnapshot(persistence)).assertDeepEquals(model.read());
    });

    it('routesLegacySnapshotReplacementThroughModel', 0, async () => {
      const persistence = new MemoryLibraryModelPersistence(JSON.stringify(
        modelSnapshot([modelTrack(1)], [], [])
      ));
      const model = new LibraryStoreModel(new LibraryStore('memory://model', persistence));
      const replacement = modelSnapshot([modelTrack(8)], [], [modelTrack(9)]);
      expect(model.position('BV1:201')).assertEqual(45);

      const saved = await model.replace(replacement);

      expect(saved.saved).assertTrue();
      expect(model.isFavorite('BV8:208')).assertTrue();
      expect(model.recentTracks()[0].bvid).assertEqual('BV9');
      expect(model.read().positions['BV1:201']).assertEqual(45);
      expect(persistedModelSnapshot(persistence).positions['BV1:201']).assertEqual(45);
      expect(model.position('BV1:201')).assertEqual(45);
    });
  });
}
