import { describe, expect, it } from '@ohos/hypium';
import {
  LibraryMutationResult,
  LibraryPersistence,
  LibraryStore,
  sanitizeLibrary
} from '../main/ets/services/LibraryStore';
import {
  LibrarySnapshot,
  MobileTrack,
  STORAGE_VERSION
} from '../main/ets/types/MobileTypes';
import { NativeError, wait } from '../main/ets/util/Errors';

class MemoryLibraryPersistence implements LibraryPersistence {
  content: string | null = null;
  writeCount: number = 0;
  activeWrites: number = 0;
  maxActiveWrites: number = 0;
  failWrites: boolean = false;
  preservedCount: number = 0;
  asyncReadCount: number = 0;

  constructor(content: string | null = null) {
    this.content = content;
  }

  read(_path: string): string | null {
    return this.content;
  }

  async readAsync(_path: string): Promise<string | null> {
    this.asyncReadCount++;
    return this.content;
  }

  async write(_path: string, content: string): Promise<void> {
    this.writeCount++;
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
    this.preservedCount++;
  }
}

function memoryTrack(index: number): MobileTrack {
  return {
    key: `stale-key-${index}`,
    bvid: `BV${index}`,
    aid: index,
    cid: index + 100,
    title: `Track ${index}`,
    artist: `Artist ${index}`,
    coverUrl: `https://example.com/${index}.jpg`,
    duration: 120,
    playCount: 10
  };
}

function persistedSnapshot(persistence: MemoryLibraryPersistence): LibrarySnapshot {
  return JSON.parse(persistence.content ?? '{}') as LibrarySnapshot;
}

export default function libraryStoreTest(): void {
  describe('LibraryStore', () => {
    it('togglesFavorites', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      const track = memoryTrack(1);

      const added = await store.toggleFavorite(track);
      expect(added.changed).assertTrue();
      expect(added.snapshot.favorites.length).assertEqual(1);
      expect(added.snapshot.favorites[0].key).assertEqual('BV1:101');
      expect(persistence.writeCount).assertEqual(1);

      const duplicate = await store.toggleFavorite(track);
      expect(duplicate.changed).assertTrue();
      expect(duplicate.snapshot.favorites.length).assertEqual(0);
      expect(store.read().favorites.length).assertEqual(0);
    });

    it('removesFavoriteKeysInOnePersistedMutation', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      for (let index = 1; index <= 4; index++) {
        await store.toggleFavorite(memoryTrack(index));
      }
      const writesBeforeRemoval = persistence.writeCount;

      const removed = await store.removeFavorites([
        ' BV1:101 ',
        'BV3:103',
        'BV1:101',
        '',
        'missing:key'
      ]);

      expect(removed.changed).assertTrue();
      expect(removed.snapshot.favorites.map((entry: MobileTrack): string => entry.bvid))
        .assertDeepEquals(['BV4', 'BV2']);
      expect(persistence.writeCount).assertEqual(writesBeforeRemoval + 1);
      expect(persistedSnapshot(persistence).favorites.length).assertEqual(2);

      const unchanged = await store.removeFavorites(['missing:key', ' ']);
      expect(unchanged.changed).assertFalse();
      expect(persistence.writeCount).assertEqual(writesBeforeRemoval + 1);
    });

    it('keepsFavoritesWhenBatchRemovalCannotBePersisted', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      await store.toggleFavorite(memoryTrack(1));
      await store.toggleFavorite(memoryTrack(2));
      const persistedBeforeFailure = persistence.content;
      persistence.failWrites = true;

      let failure: NativeError | null = null;
      try {
        await store.removeFavorites(['BV1:101', 'BV2:102']);
      } catch (error) {
        failure = error as NativeError;
      }

      expect(failure?.appError.code).assertEqual('library.writeFailed');
      expect(store.read().favorites.length).assertEqual(2);
      expect(persistence.content).assertEqual(persistedBeforeFailure);
    });

    it('deduplicatesAndLimitsRecent', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);

      await store.recordRecent(memoryTrack(1));
      await store.recordRecent(memoryTrack(2));
      const moved = await store.recordRecent(memoryTrack(1));
      expect(moved.snapshot.recent.length).assertEqual(2);
      expect(moved.snapshot.recent[0].key).assertEqual('BV1:101');
      expect(moved.snapshot.recent[1].key).assertEqual('BV2:102');

      for (let index = 0; index < 32; index++) {
        await store.recordRecent(memoryTrack(100 + index));
      }
      const capped = store.read();
      expect(capped.recent.length).assertEqual(30);
      expect(capped.recent[0].bvid).assertEqual('BV131');
      expect(capped.recent[29].bvid).assertEqual('BV102');

      const unchanged = await store.recordRecent(memoryTrack(131));
      expect(unchanged.changed).assertFalse();
      const cleared = await store.clearRecent();
      expect(cleared.changed).assertTrue();
      expect(cleared.snapshot.recent.length).assertEqual(0);
    });

    it('removesOnlyTheRequestedRecentKeys', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      await store.recordRecent(memoryTrack(1));
      await store.recordRecent(memoryTrack(2));
      await store.recordRecent(memoryTrack(3));

      const removed = await store.removeRecent(['BV2:102']);
      expect(removed.changed).assertTrue();
      expect(removed.snapshot.recent.map((track: MobileTrack): string => track.bvid))
        .assertDeepEquals(['BV3', 'BV1']);
      expect(removed.snapshot.favorites.length).assertEqual(0);

      const missing = await store.removeRecent(['BV9:109']);
      expect(missing.changed).assertFalse();
      expect(missing.snapshot.recent.length).assertEqual(2);
      const persisted = persistedSnapshot(persistence);
      expect(persisted.recent.length).assertEqual(2);
    });

    it('mutatesPlaylistAndTracks', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);

      const created = await store.createPlaylist('Mix');
      expect(created.changed).assertTrue();
      expect(created.playlist === null).assertFalse();
      const playlistId = created.playlist?.id ?? '';
      expect(playlistId.length > 0).assertTrue();
      expect(created.snapshot.playlists.length).assertEqual(1);

      const renamed = await store.renamePlaylist(playlistId, 'Favorites Mix');
      expect(renamed.playlist?.name).assertEqual('Favorites Mix');
      const updated = await store.updatePlaylist(playlistId, 'Night Mix',
        'file:///data/storage/el2/base/files/cover.img', '  late night  ');
      expect(updated.changed).assertTrue();
      expect(updated.playlist?.name).assertEqual('Night Mix');
      expect(updated.playlist?.coverUri).assertEqual('file:///data/storage/el2/base/files/cover.img');
      expect(updated.playlist?.description).assertEqual('late night');
      const sameUpdate = await store.updatePlaylist(playlistId, 'Night Mix',
        'file:///data/storage/el2/base/files/cover.img', 'late night');
      expect(sameUpdate.changed).assertFalse();
      const added = await store.addToPlaylist(playlistId, memoryTrack(5));
      expect(added.playlist?.tracks.length).assertEqual(1);
      const duplicate = await store.addToPlaylist(playlistId, memoryTrack(5));
      expect(duplicate.changed).assertFalse();
      expect(duplicate.playlist?.tracks.length).assertEqual(1);
      const removed = await store.removeFromPlaylist(playlistId, 'BV5:105');
      expect(removed.changed).assertTrue();
      expect(removed.playlist?.tracks.length).assertEqual(0);

      const deleted = await store.deletePlaylist(playlistId);
      expect(deleted.changed).assertTrue();
      expect(deleted.snapshot.playlists.length).assertEqual(0);

      let missingCode = '';
      try {
        await store.deletePlaylist(playlistId);
      } catch (error) {
        missingCode = (error as Error).message;
      }
      expect(missingCode).assertEqual('歌单不存在。');
      expect(persistedSnapshot(persistence).playlists.length).assertEqual(0);
    });

    it('removesPlaylistTracksInOnePersistedMutation', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      const created = await store.createPlaylist('Batch');
      const playlistId = created.playlist?.id ?? '';
      for (let index = 1; index <= 4; index++) {
        await store.addToPlaylist(playlistId, memoryTrack(index));
      }
      const writesBeforeRemoval = persistence.writeCount;

      const removed = await store.removeTracksFromPlaylist(playlistId, [
        ' BV1:101 ',
        'BV3:103',
        'BV1:101',
        '',
        'missing:key'
      ]);

      expect(removed.changed).assertTrue();
      expect(removed.playlist?.tracks.length).assertEqual(2);
      expect(removed.playlist?.tracks[0].key).assertEqual('BV2:102');
      expect(removed.playlist?.tracks[1].key).assertEqual('BV4:104');
      expect(persistence.writeCount).assertEqual(writesBeforeRemoval + 1);
      expect(persistedSnapshot(persistence).playlists[0].tracks.length).assertEqual(2);

      const unchanged = await store.removeTracksFromPlaylist(playlistId, ['missing:key', ' ']);
      expect(unchanged.changed).assertFalse();
      expect(persistence.writeCount).assertEqual(writesBeforeRemoval + 1);
    });

    it('batchAddsPlaylistTracksInOneMutationAndSkipsDuplicates', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      const created = await store.createPlaylist('Batch');
      const playlistId = created.playlist?.id ?? '';
      await store.addToPlaylist(playlistId, memoryTrack(1));
      const writesBeforeBatch = persistence.writeCount;

      const added = await store.addTracksToPlaylist(playlistId, [
        memoryTrack(1),
        memoryTrack(2),
        memoryTrack(2),
        memoryTrack(3)
      ]);

      expect(added.changed).assertTrue();
      expect(added.playlist?.tracks.length).assertEqual(3);
      expect(added.playlist?.tracks[0].key).assertEqual('BV1:101');
      expect(added.playlist?.tracks[1].key).assertEqual('BV2:102');
      expect(added.playlist?.tracks[2].key).assertEqual('BV3:103');
      expect(persistence.writeCount).assertEqual(writesBeforeBatch + 1);
      expect(persistedSnapshot(persistence).playlists[0].tracks.length).assertEqual(3);
    });

    it('batchAddFailsAtomicallyWhenPlaylistCapacityWouldOverflow', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      const tracks: MobileTrack[] = [];
      for (let index = 1; index <= 499; index++) {
        tracks.push(memoryTrack(index));
      }
      const seeded = await store.createPlaylistWithTracks('Full', tracks);
      const playlistId = seeded.playlist?.id ?? '';
      const contentBeforeFailure = persistence.content;

      let failure: NativeError | null = null;
      try {
        await store.addTracksToPlaylist(playlistId, [memoryTrack(500), memoryTrack(501)]);
      } catch (error) {
        failure = error as NativeError;
      }

      expect(failure?.appError.code).assertEqual('library.playlistFull');
      expect(store.read().playlists[0].tracks.length).assertEqual(499);
      expect(persistence.content).assertEqual(contentBeforeFailure);
    });

    it('createsPlaylistWithTracksInOneAtomicWrite', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);

      const created = await store.createPlaylistWithTracks('Collection', [
        memoryTrack(1),
        memoryTrack(2)
      ]);

      expect(created.changed).assertTrue();
      expect(created.playlist?.tracks.length).assertEqual(2);
      expect(persistence.writeCount).assertEqual(1);
      expect(persistedSnapshot(persistence).playlists[0].tracks.length).assertEqual(2);
    });

    it('doesNotLeaveEmptyPlaylistWhenCreateWithTracksFailsToPersist', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      persistence.failWrites = true;

      let failure: NativeError | null = null;
      try {
        await store.createPlaylistWithTracks('Broken', [memoryTrack(1)]);
      } catch (error) {
        failure = error as NativeError;
      }

      expect(failure?.appError.code).assertEqual('library.writeFailed');
      expect(store.read().playlists.length).assertEqual(0);
      expect(persistence.content === null).assertTrue();
    });

    it('keepsPlaylistTracksWhenBatchRemovalCannotBePersisted', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      const created = await store.createPlaylist('Stable');
      const playlistId = created.playlist?.id ?? '';
      await store.addToPlaylist(playlistId, memoryTrack(1));
      await store.addToPlaylist(playlistId, memoryTrack(2));
      const persistedBeforeFailure = persistence.content;
      persistence.failWrites = true;

      let failure: NativeError | null = null;
      try {
        await store.removeTracksFromPlaylist(playlistId, ['BV1:101', 'BV2:102']);
      } catch (error) {
        failure = error as NativeError;
      }

      expect(failure?.appError.code).assertEqual('library.writeFailed');
      expect(store.read().playlists[0].tracks.length).assertEqual(2);
      expect(persistence.content).assertEqual(persistedBeforeFailure);
    });

    it('serializesRapidMutationsWithoutLostUpdates', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);
      const pending: Promise<LibraryMutationResult>[] = [];

      pending.push(store.createPlaylist('One'));
      pending.push(store.createPlaylist('Two'));
      pending.push(store.toggleFavorite(memoryTrack(1)));
      pending.push(store.recordRecent(memoryTrack(2)));
      pending.push(store.recordRecent(memoryTrack(3)));
      await Promise.all(pending);
      await store.flush();

      expect(persistence.maxActiveWrites).assertEqual(1);
      expect(store.read().playlists.length).assertEqual(2);
      expect(store.read().favorites.length).assertEqual(1);
      expect(store.read().recent.length).assertEqual(2);
      expect(persistedSnapshot(persistence)).assertDeepEquals(store.read());

      const restored = new LibraryStore('memory://library', persistence);
      expect(restored.read()).assertDeepEquals(store.read());
    });

    it('loadsLegacyStateAndKeepsNativePositions', 0, async () => {
      const legacy: LibrarySnapshot = {
        version: STORAGE_VERSION,
        favorites: [memoryTrack(1)],
        playlists: [],
        recent: [],
        positions: {
          'BV1:101': 42
        },
        updatedAt: 5
      };
      const persistence = new MemoryLibraryPersistence(JSON.stringify(legacy));
      const store = new LibraryStore('memory://library', persistence);
      expect(store.position('BV1:101')).assertEqual(42);

      store.updatePosition('BV1:101', 60, true);
      await store.flush();
      expect(store.position('BV1:101')).assertEqual(60);

      const incomingPositions: Record<string, number> = {};
      incomingPositions['BV1:101'] = 1;
      const incoming: Record<string, Object> = {};
      incoming.version = STORAGE_VERSION;
      incoming.favorites = [memoryTrack(2)];
      incoming.playlists = [];
      incoming.recent = [];
      incoming.positions = incomingPositions;
      incoming.updatedAt = 1;
      const saved = await store.write(incoming);
      expect(saved.saved).assertTrue();
      expect(store.position('BV1:101')).assertEqual(60);
      expect(store.read().favorites[0].key).assertEqual('BV2:102');
      expect(persistedSnapshot(persistence).positions['BV1:101']).assertEqual(60);
    });

    it('acceptsCurrentVersionWithMissingOptionalFields', 0, () => {
      const raw: Record<string, Object> = {};
      raw.version = STORAGE_VERSION;
      const persistence = new MemoryLibraryPersistence(JSON.stringify(raw));
      const store = new LibraryStore('memory://library', persistence);

      expect(store.read().favorites.length).assertEqual(0);
      expect(store.read().playlists.length).assertEqual(0);
      expect(store.read().recent.length).assertEqual(0);
      expect(Object.keys(store.read().positions).length).assertEqual(0);
      expect(store.storageDiagnostics().recovered).assertFalse();
      expect(store.storageDiagnostics().error === null).assertTrue();
      expect(persistence.preservedCount).assertEqual(0);
    });

    it('recoversCorruptAndUnsupportedVersionsWithStructuredCodes', 0, () => {
      const corruptPersistence = new MemoryLibraryPersistence('{bad json');
      const corrupt = new LibraryStore('memory://library', corruptPersistence);
      expect(corrupt.read()).assertDeepEquals(
        new LibraryStore('memory://empty', new MemoryLibraryPersistence()).read()
      );
      expect(corrupt.storageDiagnostics().recovered).assertTrue();
      expect(corrupt.storageDiagnostics().error?.code).assertEqual('library.corrupt');
      expect(corruptPersistence.preservedCount).assertEqual(1);

      const futureRaw: Record<string, Object> = {};
      futureRaw.version = STORAGE_VERSION + 1;
      futureRaw.favorites = [memoryTrack(1)];
      const futurePersistence = new MemoryLibraryPersistence(JSON.stringify(futureRaw));
      const future = new LibraryStore('memory://library', futurePersistence);
      expect(future.read().favorites.length).assertEqual(0);
      expect(future.storageDiagnostics().recovered).assertTrue();
      expect(future.storageDiagnostics().error?.code).assertEqual('library.unsupportedVersion');
      expect(futurePersistence.preservedCount).assertEqual(1);
    });

    it('loadsADeferredStoreOffTheMainThread', 0, async () => {
      const seedPersistence = new MemoryLibraryPersistence();
      const seed = new LibraryStore('memory://library', seedPersistence);
      await seed.toggleFavorite(memoryTrack(7));
      const content = seedPersistence.content;
      expect(content === null).assertFalse();

      const persistence = new MemoryLibraryPersistence(content);
      const store = LibraryStore.deferred('memory://library', persistence);
      // 构造阶段不读盘：快照保持为空，等 loadAsync() 再解析。
      expect(store.read().favorites.length).assertEqual(0);
      expect(persistence.asyncReadCount).assertEqual(0);

      await store.loadAsync();
      expect(store.read().favorites.length).assertEqual(1);
      expect(store.read().favorites[0].key).assertEqual('BV7:107');

      await store.loadAsync();
      expect(persistence.asyncReadCount).assertEqual(1);
    });

    it('keepsSnapshotWhenPersistenceFails', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      persistence.failWrites = true;
      const store = new LibraryStore('memory://library', persistence);

      let failure: NativeError | null = null;
      try {
        await store.toggleFavorite(memoryTrack(1));
      } catch (error) {
        failure = error as NativeError;
      }
      expect(failure?.appError.code).assertEqual('library.writeFailed');
      expect(failure?.appError.retryable).assertTrue();
      expect(store.read().favorites.length).assertEqual(0);
      expect(store.storageDiagnostics().error?.code).assertEqual('library.writeFailed');
      expect(persistence.content === null).assertTrue();

      persistence.failWrites = false;
      const retried = await store.toggleFavorite(memoryTrack(1));
      expect(retried.changed).assertTrue();
      expect(store.storageDiagnostics().error === null).assertTrue();
    });

    it('throttlesPositionWritesAndFlushesTheLatestForcedValue', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);

      store.updatePosition('BV1:101', 10);
      store.updatePosition('BV1:101', 20);
      await store.flush();
      expect(store.position('BV1:101')).assertEqual(10);
      expect(persistedSnapshot(persistence).positions['BV1:101']).assertEqual(10);

      store.updatePosition('BV1:101', 30, true);
      await store.flush();
      expect(store.position('BV1:101')).assertEqual(30);
      expect(persistedSnapshot(persistence).positions['BV1:101']).assertEqual(30);
      expect(persistence.maxActiveWrites).assertEqual(1);

      const restarted = new LibraryStore('memory://library', persistence);
      expect(restarted.position('BV1:101')).assertEqual(30);
    });

    it('keepsOnlyTheCurrentTrackPosition', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      const store = new LibraryStore('memory://library', persistence);

      store.updatePosition('BV1:101', 30, true);
      store.updatePosition('BV2:102', 45, true);
      await store.flush();

      expect(store.position('BV1:101')).assertEqual(0);
      expect(store.position('BV2:102')).assertEqual(45);
      expect(Object.keys(store.read().positions).length).assertEqual(1);
      expect(Object.keys(persistedSnapshot(persistence).positions).length).assertEqual(1);

      store.updatePosition('BV1:101', 12, true);
      await store.flush();

      expect(store.position('BV1:101')).assertEqual(12);
      expect(store.position('BV2:102')).assertEqual(0);
      expect(store.read().positions['BV1:101']).assertEqual(12);
      expect(Object.keys(store.read().positions).length).assertEqual(1);
    });

    it('collapsesLegacyPositionsToTheCurrentTrackOnWrite', 0, async () => {
      const legacy: LibrarySnapshot = {
        version: STORAGE_VERSION,
        favorites: [],
        playlists: [],
        recent: [],
        positions: {
          'BV1:101': 20,
          'BV2:102': 30
        },
        updatedAt: 5
      };
      const persistence = new MemoryLibraryPersistence(JSON.stringify(legacy));
      const store = new LibraryStore('memory://library', persistence);
      expect(Object.keys(store.read().positions).length).assertEqual(2);

      store.updatePosition('BV2:102', 45, true);
      await store.flush();

      expect(store.position('BV1:101')).assertEqual(0);
      expect(store.position('BV2:102')).assertEqual(45);
      expect(Object.keys(store.read().positions).length).assertEqual(1);
      expect(Object.keys(persistedSnapshot(persistence).positions).length).assertEqual(1);
    });

    it('recordsPositionWriteFailureWithoutChangingMemory', 0, async () => {
      const persistence = new MemoryLibraryPersistence();
      persistence.failWrites = true;
      const store = new LibraryStore('memory://library', persistence);

      store.updatePosition('BV1:101', 15);
      await store.flush();

      expect(store.position('BV1:101')).assertEqual(0);
      expect(store.storageDiagnostics().error?.code).assertEqual('library.writeFailed');
      expect(persistence.content === null).assertTrue();
    });

    it('sanitizesWholeSnapshotInputs', 0, () => {
      const raw: Record<string, Object> = {};
      raw.version = STORAGE_VERSION;
      raw.favorites = [memoryTrack(1), memoryTrack(1)];
      raw.playlists = [];
      raw.recent = [];
      const positions: Record<string, number> = {};
      raw.positions = positions;
      raw.updatedAt = 1;
      const snapshot = sanitizeLibrary(raw);

      expect(snapshot.favorites.length).assertEqual(1);
      expect(snapshot.version).assertEqual(STORAGE_VERSION);
    });
  });
}
