import { describe, expect, it } from '@ohos/hypium';
import {
  DownloadFileStore,
  DownloadOutcome,
  DownloadService,
  DownloadTransport,
  MAX_DOWNLOADS,
  MAX_TOTAL_DOWNLOAD_BYTES,
  downloadFileName,
  sanitizeDownloadSnapshot
} from '../main/ets/services/DownloadService';
import { AudioCandidate } from '../main/ets/services/CatalogService';
import { AudioQuality, MobileTrack } from '../main/ets/types/MobileTypes';
import { parseJsonObject, arrayValue, numberValue, objectValue, stringValue } from '../main/ets/util/Json';

class MemoryDownloadFiles implements DownloadFileStore {
  contents: Map<string, string> = new Map<string, string>();
  sizes: Map<string, number> = new Map<string, number>();
  preservedCount: number = 0;

  exists(path: string): boolean {
    return this.contents.has(path) || this.sizes.has(path);
  }

  size(path: string): number {
    const value = this.sizes.get(path);
    return value === undefined ? 0 : value;
  }

  ensureDirectory(_path: string): void {
  }

  deleteFile(path: string): void {
    this.contents.delete(path);
    this.sizes.delete(path);
  }

  readText(path: string): string | null {
    const value = this.contents.get(path);
    return value === undefined ? null : value;
  }

  async writeText(path: string, content: string): Promise<void> {
    this.contents.set(path, content);
  }

  preserveCorrupt(_path: string): void {
    this.preservedCount++;
  }
}

function candidate(id: number, source: string): AudioCandidate {
  return {
    url: `https://cdn.example.com/${id}.${source === 'dash' ? 'm4s' : 'mp4'}`,
    id: id,
    mimeType: 'audio/mp4',
    codecs: 'mp4a.40.2',
    bandwidth: 128000,
    source: source
  };
}

class FakeDownloadTransport implements DownloadTransport {
  files: MemoryDownloadFiles;
  dash: AudioCandidate[] = [candidate(30280, 'dash')];
  progressiveCandidates: AudioCandidate[] = [candidate(80, 'progressive')];
  failDash: boolean = false;
  failFetch: boolean = false;
  fetchCount: number = 0;
  lastDestination: string = '';
  lastQuality: AudioQuality | null = null;

  constructor(files: MemoryDownloadFiles) {
    this.files = files;
  }

  async candidates(_track: MobileTrack, quality: AudioQuality): Promise<AudioCandidate[]> {
    this.lastQuality = quality;
    if (this.failDash) {
      throw new Error('dash source failed');
    }
    return this.dash;
  }

  async progressive(_track: MobileTrack): Promise<AudioCandidate[]> {
    return this.progressiveCandidates;
  }

  async fetch(_url: string, destination: string, _maxBytes: number): Promise<number> {
    this.fetchCount++;
    if (this.failFetch) {
      throw new Error('fetch failed');
    }
    this.lastDestination = destination;
    this.files.sizes.set(destination, 2048);
    return 2048;
  }
}

function downloadTrack(index: number): MobileTrack {
  return {
    key: `BV${index}:${index + 100}`,
    bvid: `BV${index}`,
    aid: index,
    cid: index + 100,
    title: `Download ${index}`,
    artist: `Artist ${index}`,
    coverUrl: `https://example.com/${index}.jpg`,
    duration: 180,
    playCount: 5
  };
}

class DownloadHarness {
  readonly files: MemoryDownloadFiles = new MemoryDownloadFiles();
  readonly transport: FakeDownloadTransport = new FakeDownloadTransport(this.files);
  readonly service: DownloadService;

  constructor(quality: AudioQuality = 'high',
    maxTotalBytes: number = MAX_TOTAL_DOWNLOAD_BYTES,
    limitProvider: () => number = (): number => MAX_DOWNLOADS) {
    this.service = new DownloadService(
      'memory://downloads-v1',
      'memory://downloads-v1.json',
      this.transport,
      (): AudioQuality => quality,
      this.files,
      (): number => 0,
      maxTotalBytes,
      limitProvider
    );
  }
}

export default function downloadServiceTest(): void {
  describe('DownloadService', () => {
    it('downloadsTrackPersistsIndexAndResolvesLocalFile', 0, async () => {
      const harness = new DownloadHarness('high');
      const track = downloadTrack(1);

      const result = await harness.service.download(track);
      expect(result.outcome).assertEqual(DownloadOutcome.Added);
      expect(result.entry === null).assertFalse();
      const entry = result.entry;
      if (entry === null) {
        return;
      }
      expect(entry.key).assertEqual(track.key);
      expect(entry.quality).assertEqual('high');
      expect(entry.bytes).assertEqual(2048);
      expect(entry.file).assertEqual(downloadFileName(track.key, candidate(30280, 'dash')));

      const local = harness.service.local(track.key);
      expect(local === null).assertFalse();
      if (local !== null) {
        expect(local.path).assertEqual(`memory://downloads-v1/${entry.file}`);
        expect(local.bytes).assertEqual(2048);
      }
      expect(harness.service.stats().entries).assertEqual(1);
      expect(harness.service.stats().bytes).assertEqual(2048);

      const persisted = parseJsonObject(harness.files.contents.get('memory://downloads-v1.json') ?? '{}');
      expect(numberValue(persisted.version, 0)).assertEqual(1);
      expect(arrayValue(persisted.entries).length).assertEqual(1);
      expect(stringValue(objectValue(arrayValue(persisted.entries)[0]).quality))
        .assertEqual('high');
    });

    it('usesTheQualityProviderForDownloadSourceAndIndex', 0, async () => {
      const harness = new DownloadHarness('low');
      const result = await harness.service.download(downloadTrack(9));

      expect(result.outcome).assertEqual(DownloadOutcome.Added);
      expect(harness.transport.lastQuality).assertEqual('low');
      const entry = result.entry;
      expect(entry === null).assertFalse();
      if (entry !== null) {
        expect(entry.quality).assertEqual('low');
      }
    });

    it('skipsFetchWhenTrackAlreadyDownloaded', 0, async () => {
      const harness = new DownloadHarness();
      const track = downloadTrack(2);
      await harness.service.download(track);
      const second = await harness.service.download(track);

      expect(second.outcome).assertEqual(DownloadOutcome.Exists);
      expect(harness.transport.fetchCount).assertEqual(1);
      expect(harness.service.entries().length).assertEqual(1);
    });

    it('fallsBackToProgressiveSourceWhenDashFails', 0, async () => {
      const harness = new DownloadHarness();
      harness.transport.failDash = true;

      const result = await harness.service.download(downloadTrack(3));
      expect(result.outcome).assertEqual(DownloadOutcome.Added);
      const entry = result.entry;
      if (entry !== null) {
        expect(entry.file.endsWith('.mp4')).assertTrue();
      }
    });

    it('removesEntryAndFile', 0, async () => {
      const harness = new DownloadHarness();
      const first = downloadTrack(4);
      const second = downloadTrack(5);
      await harness.service.download(first);
      await harness.service.download(second);

      const removed = await harness.service.remove([first.key]);
      expect(removed).assertEqual(1);
      expect(harness.service.entries().length).assertEqual(1);
      expect(harness.service.local(first.key) === null).assertTrue();
      expect(harness.service.local(second.key) === null).assertFalse();
    });

    it('treatsMissingFileAsNotDownloaded', 0, async () => {
      const harness = new DownloadHarness();
      const track = downloadTrack(6);
      const result = await harness.service.download(track);
      const entry = result.entry;
      if (entry === null) {
        return;
      }
      harness.files.deleteFile(`memory://downloads-v1/${entry.file}`);

      expect(harness.service.local(track.key) === null).assertTrue();
      expect(harness.service.isDownloaded(track.key)).assertFalse();
    });

    it('evictsOldestWhenTotalBytesExceeded', 0, async () => {
      const harness = new DownloadHarness('high', 4096);
      const first = downloadTrack(1);
      const second = downloadTrack(2);
      const third = downloadTrack(3);
      await harness.service.download(first);
      const firstEntry = harness.service.entryFor(first.key);
      expect(firstEntry !== null).assertTrue();
      if (firstEntry === null) {
        return;
      }
      await harness.service.download(second);
      await harness.service.download(third);

      const entries = harness.service.entries();
      expect(entries.length).assertEqual(2);
      expect(entries[0].key).assertEqual(third.key);
      expect(entries[1].key).assertEqual(second.key);
      expect(harness.service.local(first.key) === null).assertTrue();
      expect(harness.files.exists(`memory://downloads-v1/${firstEntry.file}`)).assertFalse();
      expect(harness.service.stats().bytes).assertEqual(4096);
    });

    it('keepsNewestEntryWhenSingleFileExceedsTotalBudget', 0, async () => {
      const harness = new DownloadHarness('high', 1024);
      const track = downloadTrack(1);
      const result = await harness.service.download(track);

      expect(result.outcome).assertEqual(DownloadOutcome.Added);
      expect(harness.service.entries().length).assertEqual(1);
      expect(harness.service.isDownloaded(track.key)).assertTrue();
      expect(harness.service.stats().bytes).assertEqual(2048);
    });

    it('truncatesIndexWhenTotalBytesExceeded', 0, () => {
      const raw = parseJsonObject('{"version":1,"entries":[' +
        '{"key":"a:1","file":"dl-v1-a-1.m4s","bytes":10},' +
        '{"key":"b:2","file":"dl-v1-b-2.m4s","bytes":10},' +
        '{"key":"c:3","file":"dl-v1-c-3.m4s","bytes":10}' +
        ']}');
      const snapshot = sanitizeDownloadSnapshot(raw, 25);

      expect(snapshot.entries.length).assertEqual(2);
      expect(snapshot.entries[0].key).assertEqual('a:1');
      expect(snapshot.entries[1].key).assertEqual('b:2');
    });

    it('evictsOldestWhenConfiguredLimitExceeded', 0, async () => {
      const harness = new DownloadHarness('high', MAX_TOTAL_DOWNLOAD_BYTES,
        (): number => 2);
      const first = downloadTrack(1);
      const second = downloadTrack(2);
      const third = downloadTrack(3);
      await harness.service.download(first);
      await harness.service.download(second);
      await harness.service.download(third);

      const entries = harness.service.entries();
      expect(entries.length).assertEqual(2);
      expect(entries[0].key).assertEqual(third.key);
      expect(entries[1].key).assertEqual(second.key);
      expect(harness.service.local(first.key) === null).assertTrue();
    });

    it('applyLimitTrimsExistingDownloadsAfterLimitIsLowered', 0, async () => {
      let limit = 500;
      const harness = new DownloadHarness('high', MAX_TOTAL_DOWNLOAD_BYTES,
        (): number => limit);
      const first = downloadTrack(1);
      const second = downloadTrack(2);
      const third = downloadTrack(3);
      await harness.service.download(first);
      await harness.service.download(second);
      await harness.service.download(third);

      limit = 2;
      const removed = await harness.service.applyLimit();

      expect(removed).assertEqual(1);
      const entries = harness.service.entries();
      expect(entries.length).assertEqual(2);
      expect(entries[0].key).assertEqual(third.key);
      expect(entries[1].key).assertEqual(second.key);
      expect(harness.service.local(first.key) === null).assertTrue();
      expect(harness.files.exists('memory://downloads-v1/dl-v1-BV1-1-30280.m4s'))
        .assertFalse();
    });

    it('truncatesIndexWhenConfiguredLimitExceeded', 0, () => {
      const raw = parseJsonObject('{"version":1,"entries":[' +
        '{"key":"a:1","file":"dl-v1-a-1.m4s","bytes":10},' +
        '{"key":"b:2","file":"dl-v1-b-2.m4s","bytes":10},' +
        '{"key":"c:3","file":"dl-v1-c-3.m4s","bytes":10}' +
        ']}');
      const snapshot = sanitizeDownloadSnapshot(raw, MAX_TOTAL_DOWNLOAD_BYTES, 2);

      expect(snapshot.entries.length).assertEqual(2);
      expect(snapshot.entries[0].key).assertEqual('a:1');
      expect(snapshot.entries[1].key).assertEqual('b:2');
    });

    it('sanitizesCorruptAndDuplicateIndexEntries', 0, () => {
      const raw = parseJsonObject('{"version":1,"entries":[' +
        '{"key":"a:1","file":"dl-v1-a-1.m4s","quality":"high","bytes":10},' +
        '{"key":"a:1","file":"dl-v1-a-1b.m4s","quality":"high","bytes":10},' +
        '{"key":"b:2","file":"../escape.m4s","quality":"high","bytes":10},' +
        '{"key":"","file":"dl-v1-c-1.m4s","quality":"high","bytes":10},' +
        '{"key":"d:4","file":"dl-v1-d-4.m4s","quality":"ultra","bytes":10}' +
        ']}');
      const snapshot = sanitizeDownloadSnapshot(raw);

      expect(snapshot.version).assertEqual(1);
      expect(snapshot.entries.length).assertEqual(2);
      expect(snapshot.entries[0].key).assertEqual('a:1');
      expect(snapshot.entries[1].quality).assertEqual('standard');
    });

    it('rejectsIndexWithUnknownVersion', 0, () => {
      const raw = parseJsonObject('{"version":2,"entries":[{"key":"a:1","file":"dl-v1-a-1.m4s"}]}');
      expect(sanitizeDownloadSnapshot(raw).entries.length).assertEqual(0);
    });
  });
}