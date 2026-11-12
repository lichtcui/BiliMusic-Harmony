import { describe, expect, it } from '@ohos/hypium';
import {
  DownloadFileStore,
  DownloadService,
  DownloadTransport
} from '../main/ets/services/DownloadService';
import { AudioCandidate } from '../main/ets/services/CatalogService';
import { DownloadStore } from '../main/ets/state/DownloadStore';
import { PlayerProgressScheduler, PlayerStore } from '../main/ets/state/PlayerStore';
import { AudioQuality, MobileTrack } from '../main/ets/types/MobileTypes';

class StoreFakeScheduler implements PlayerProgressScheduler {
  now(): number {
    return 0;
  }

  schedule(_callback: () => void, _delayMs: number): number {
    return 1;
  }

  cancel(_timerId: number): void {
  }
}

class StoreDownloadFiles implements DownloadFileStore {
  sizes: Map<string, number> = new Map<string, number>();
  indexContent: string | null = null;

  exists(path: string): boolean {
    return this.sizes.has(path) || path === 'memory://store-index.json';
  }

  size(path: string): number {
    const value = this.sizes.get(path);
    return value === undefined ? 0 : value;
  }

  ensureDirectory(_path: string): void {
  }

  deleteFile(path: string): void {
    this.sizes.delete(path);
  }

  readText(_path: string): string | null {
    return this.indexContent;
  }

  async writeText(_path: string, content: string): Promise<void> {
    this.indexContent = content;
  }

  preserveCorrupt(_path: string): void {
  }
}

class StoreFakeTransport implements DownloadTransport {
  files: StoreDownloadFiles;
  fetchCount: number = 0;

  constructor(files: StoreDownloadFiles) {
    this.files = files;
  }

  async candidates(_track: MobileTrack, _quality: AudioQuality): Promise<AudioCandidate[]> {
    return [{
      url: 'https://cdn.example.com/audio.m4s',
      id: 30280,
      mimeType: 'audio/mp4',
      codecs: 'mp4a.40.2',
      bandwidth: 128000,
      source: 'dash'
    }];
  }

  async progressive(_track: MobileTrack): Promise<AudioCandidate[]> {
    return [];
  }

  async fetch(_url: string, destination: string, _maxBytes: number): Promise<number> {
    this.fetchCount++;
    this.files.sizes.set(destination, 1024);
    return 1024;
  }
}

function storeTrack(index: number): MobileTrack {
  return {
    key: `BV${index}:${index + 100}`,
    bvid: `BV${index}`,
    aid: index,
    cid: index + 100,
    title: `Store ${index}`,
    artist: `Artist ${index}`,
    coverUrl: `https://example.com/${index}.jpg`,
    duration: 120,
    playCount: 0
  };
}

class StoreHarness {
  readonly files: StoreDownloadFiles = new StoreDownloadFiles();
  readonly transport: StoreFakeTransport = new StoreFakeTransport(this.files);
  readonly service: DownloadService;
  readonly player: PlayerStore = new PlayerStore(new StoreFakeScheduler());
  readonly store: DownloadStore;

  constructor() {
    this.service = new DownloadService(
      'memory://store-downloads',
      'memory://store-index.json',
      this.transport,
      (): AudioQuality => 'standard',
      this.files
    );
    this.store = new DownloadStore(this.player, this.service);
    this.store.attach();
  }
}

export default function downloadStoreTest(): void {
  describe('DownloadStore', () => {
    it('queuesUniqueTracksSeriallyAndRefreshesTracks', 0, async () => {
      const harness = new StoreHarness();
      const first = storeTrack(1);
      const second = storeTrack(2);

      const request = harness.store.request([first, second, first]);
      expect(request.queued).assertEqual(2);
      expect(request.skipped).assertEqual(1);
      expect(harness.store.downloadingKeys.length).assertEqual(2);

      const result = await request.completion;
      expect(result.added).assertEqual(2);
      expect(result.failed).assertEqual(0);
      expect(harness.store.downloadingKeys.length).assertEqual(0);
      expect(harness.store.tracks.length).assertEqual(2);
      expect(harness.store.isDownloaded(first.key)).assertTrue();
      expect(harness.store.isDownloading(first.key)).assertFalse();

      await harness.store.dispose();
    });

    it('skipsAlreadyDownloadedTracks', 0, async () => {
      const harness = new StoreHarness();
      const track = storeTrack(3);
      await harness.store.request([track]).completion;

      const request = harness.store.request([track]);
      expect(request.queued).assertEqual(0);
      expect(request.skipped).assertEqual(1);
      const result = await request.completion;
      expect(result.added).assertEqual(0);
      expect(harness.transport.fetchCount).assertEqual(1);

      await harness.store.dispose();
    });

    it('removesSelectedDownloadsAndClearsSelection', 0, async () => {
      const harness = new StoreHarness();
      const first = storeTrack(4);
      const second = storeTrack(5);
      await harness.store.request([first, second]).completion;

      harness.store.selectAll();
      expect(harness.store.isAllSelected()).assertTrue();
      expect(harness.store.selectedTracks().length).assertEqual(2);

      const removed = await harness.store.removeSelected();
      expect(removed).assertTrue();
      expect(harness.store.selectedKeys.length).assertEqual(0);
      expect(harness.store.tracks.length).assertEqual(0);

      await harness.store.dispose();
    });

    it('togglesSelectionOnlyForExistingDownloads', 0, async () => {
      const harness = new StoreHarness();
      const track = storeTrack(6);
      await harness.store.request([track]).completion;

      harness.store.toggleSelection('missing:0');
      expect(harness.store.selectedKeys.length).assertEqual(0);

      harness.store.toggleSelection(track.key);
      expect(harness.store.isSelected(track.key)).assertTrue();
      harness.store.toggleSelection(track.key);
      expect(harness.store.isSelected(track.key)).assertFalse();

      await harness.store.dispose();
    });
  });
}