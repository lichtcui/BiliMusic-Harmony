import { describe, expect, it } from '@ohos/hypium';
import { HttpRequestConfig } from '../main/ets/services/BiliHttpClient';
import {
  LyricsCachePersistence,
  LyricsHttpGateway,
  LyricsService
} from '../main/ets/services/LyricsService';
import { LyricCandidate, LyricResult, MobileTrack } from '../main/ets/types/MobileTypes';
import { NativeError, wait } from '../main/ets/util/Errors';

class PendingJsonCall {
  readonly targetUrl: string;
  readonly promise: Promise<Record<string, Object>>;
  private resolveCallback: ((result: Record<string, Object>) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor(targetUrl: string) {
    this.targetUrl = targetUrl;
    this.promise = new Promise<Record<string, Object>>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: Record<string, Object>): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }

  reject(error: Object): void {
    const callback = this.rejectCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

class QueuedLyricsHttpGateway implements LyricsHttpGateway {
  readonly calls: PendingJsonCall[] = [];

  requestJson(targetUrl: string, _config: HttpRequestConfig): Promise<Record<string, Object>> {
    const call = new PendingJsonCall(targetUrl);
    this.calls.push(call);
    return call.promise;
  }
}

class MemoryLyricsCachePersistence implements LyricsCachePersistence {
  content: string | null = null;
  deletedPaths: string[] = [];
  preservedCount: number = 0;
  writeCount: number = 0;
  readCount: number = 0;
  failDelete: boolean = false;
  holdWrites: boolean = false;
  pendingWrite: boolean = false;
  private resolveWrite: (() => void) | null = null;

  constructor(content: string | null = null) {
    this.content = content;
  }

  async readAsync(_path: string): Promise<string | null> {
    this.readCount++;
    return this.content;
  }

  async write(_path: string, content: string): Promise<void> {
    this.writeCount++;
    if (this.holdWrites) {
      this.pendingWrite = true;
      await new Promise<void>((resolve) => {
        this.resolveWrite = resolve;
      });
      this.pendingWrite = false;
    }
    this.content = content;
  }

  delete(path: string): void {
    this.deletedPaths.push(path);
    if (this.failDelete) {
      throw new Error('simulated lyrics cache delete failure');
    }
    this.content = null;
  }

  preserveCorrupt(_path: string): void {
    this.preservedCount++;
  }

  releaseWrite(): void {
    const callback = this.resolveWrite;
    this.resolveWrite = null;
    if (callback !== null) {
      callback();
    }
  }
}

function lyricsTrack(): MobileTrack {
  return {
    key: 'BV1CACHE:2201',
    bvid: 'BV1CACHE',
    aid: 1001,
    cid: 2201,
    title: 'Song Alpha',
    artist: 'Artist Alpha',
    coverUrl: 'https://i0.hdslb.com/bfs/cache.jpg',
    duration: 180,
    playCount: 0
  };
}

function trackParams(): Record<string, Object> {
  const params: Record<string, Object> = {};
  params.track = lyricsTrack();
  return params;
}

function searchParams(): Record<string, Object> {
  const params: Record<string, Object> = {};
  params.query = 'Song Alpha';
  return params;
}

function chooseParams(candidateId: string): Record<string, Object> {
  const params = trackParams();
  params.candidateId = candidateId;
  return params;
}

function searchResponse(id: string = 'candidate-alpha'): Record<string, Object> {
  const candidate: Record<string, Object> = {};
  candidate.id = id;
  candidate.name = 'Song Alpha';
  candidate.album = 'Album Alpha';
  candidate.duration = 181;
  candidate.image = 'https://i0.hdslb.com/bfs/lyrics.jpg';
  const singers: Object[] = ['Artist Alpha'];
  candidate.singer = singers;
  const data: Object[] = [candidate];
  const response: Record<string, Object> = {};
  response.data = data;
  return response;
}

function lyricResponse(content: string = '[00:01.00]First line\n[00:02.00]Second line'):
  Record<string, Object> {
  const response: Record<string, Object> = {};
  response.code = 1;
  response.data = content;
  return response;
}

async function cacheOneResult(service: LyricsService,
  gateway: QueuedLyricsHttpGateway): Promise<void> {
  const search = service.search(searchParams());
  // 歌词缓存按需异步加载，首次请求要等一个事件循环才会落到网关。
  await wait(0);
  const searchCall = gateway.calls[gateway.calls.length - 1];
  searchCall.resolve(searchResponse());
  const candidates: LyricCandidate[] = await search;
  expect(candidates.length).assertEqual(1);

  const choose = service.choose(chooseParams(candidates[0].id));
  await wait(0);
  const fetchCall = gateway.calls[gateway.calls.length - 1];
  fetchCall.resolve(lyricResponse());
  const result: LyricResult | null = await choose;
  expect(result === null).assertFalse();
}

export default function lyricsServiceTest(): void {
  describe('LyricsService', () => {
    it('reportsPersistsAndRestoresCacheStats', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence();
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      await cacheOneResult(service, gateway);

      const stats = await service.stats();
      expect(stats.entries).assertEqual(1);
      expect(stats.bytes > 0).assertTrue();
      await service.shutdown();
      expect(persistence.writeCount > 0).assertTrue();
      expect(persistence.content === null).assertFalse();

      const restarted = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      const restoredStats = await restarted.stats();
      expect(restoredStats.entries).assertEqual(1);
      const restored: LyricResult | null = await restarted.resolve(trackParams());
      expect(restored?.lines.length).assertEqual(2);
      expect(restored?.sourceId).assertEqual('candidate-alpha');
      expect(gateway.calls.length).assertEqual(2);
      await restarted.shutdown();
    });

    it('clearsOnlyItsCacheAndDeduplicatesConcurrentCalls', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence();
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      await cacheOneResult(service, gateway);

      const first = service.clear();
      const second = service.clear();
      expect(first === second).assertTrue();
      const stats = await first;
      expect(stats.entries).assertEqual(0);
      expect(stats.bytes).assertEqual(0);
      expect(persistence.content === null).assertTrue();
      expect(persistence.deletedPaths.length).assertEqual(1);
      expect(persistence.deletedPaths[0]).assertEqual('memory://lyrics-cache');
      await service.shutdown();
    });

    it('mapsClearFailureAndRecoversOnRetry', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence();
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      await cacheOneResult(service, gateway);
      persistence.failDelete = true;

      let failure: NativeError | null = null;
      try {
        await service.clear();
      } catch (error) {
        failure = error as NativeError;
      }
      expect(failure?.appError.code).assertEqual('lyrics.cacheClearFailed');
      expect(failure?.appError.retryable).assertTrue();
      expect(failure?.appError.message.includes('simulated')).assertFalse();

      persistence.failDelete = false;
      await wait(0);
      const retried = await service.clear();
      expect(retried.entries).assertEqual(0);
      expect(persistence.content === null).assertTrue();
      await service.shutdown();
    });

    it('mapsRemoteFailuresWithoutLeakingRequestDetails', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence();
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      const search = service.search(searchParams());
      await wait(0);
      gateway.calls[0].reject(new Error('https://oiapi.net/?cookie=secret'));

      let searchFailure: NativeError | null = null;
      try {
        await search;
      } catch (error) {
        searchFailure = error as NativeError;
      }
      expect(searchFailure?.appError.code).assertEqual('lyrics.searchUnavailable');
      expect(searchFailure?.appError.message.toLowerCase().includes('cookie')).assertFalse();
      expect(searchFailure?.appError.message.includes('https://')).assertFalse();

      const secondSearch = service.search(searchParams());
      await wait(0);
      gateway.calls[1].resolve(searchResponse());
      await secondSearch;
      const choose = service.choose(chooseParams('candidate-alpha'));
      await wait(0);
      gateway.calls[2].reject(new Error('https://oiapi.net/?sessdata=secret'));

      let fetchFailure: NativeError | null = null;
      try {
        await choose;
      } catch (error) {
        fetchFailure = error as NativeError;
      }
      expect(fetchFailure?.appError.code).assertEqual('lyrics.fetchUnavailable');
      expect((await service.stats()).entries).assertEqual(0);
      await service.shutdown();
    });

    it('ignoresInFlightSearchAfterClear', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence();
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      const search = service.search(searchParams());
      await wait(0);
      const searchCall = gateway.calls[0];

      await service.clear();
      searchCall.resolve(searchResponse());
      const candidates = await search;
      expect(candidates.length).assertEqual(0);

      const staleChoice = await service.choose(chooseParams('candidate-alpha'));
      expect(staleChoice === null).assertTrue();
      expect(gateway.calls.length).assertEqual(1);
      expect((await service.stats()).entries).assertEqual(0);
      await service.shutdown();
    });

    it('ignoresInFlightFetchAfterClearAndRefetchesOnDemand', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence();
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      const initialSearch = service.search(searchParams());
      await wait(0);
      gateway.calls[0].resolve(searchResponse());
      await initialSearch;

      const staleChoose = service.choose(chooseParams('candidate-alpha'));
      await wait(0);
      const staleFetch = gateway.calls[1];
      await service.clear();
      staleFetch.resolve(lyricResponse('[00:01.00]Stale line'));
      expect((await staleChoose) === null).assertTrue();
      expect((await service.stats()).entries).assertEqual(0);
      expect(persistence.content === null).assertTrue();

      const nextSearch = service.search(searchParams());
      await wait(0);
      gateway.calls[2].resolve(searchResponse());
      await nextSearch;
      const nextChoose = service.choose(chooseParams('candidate-alpha'));
      await wait(0);
      gateway.calls[3].resolve(lyricResponse('[00:03.00]Fresh line'));
      const fresh = await nextChoose;
      expect(fresh?.lines[0].text).assertEqual('Fresh line');
      expect((await service.stats()).entries).assertEqual(1);
      await service.shutdown();
    });

    it('doesNotRestoreAStaleWriteCompletedDuringClear', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence();
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      const search = service.search(searchParams());
      await wait(0);
      gateway.calls[0].resolve(searchResponse());
      await search;
      persistence.holdWrites = true;
      const choose = service.choose(chooseParams('candidate-alpha'));
      await wait(0);
      gateway.calls[1].resolve(lyricResponse());
      await choose;
      await wait(1);
      expect(persistence.pendingWrite).assertTrue();

      const clear = service.clear();
      persistence.releaseWrite();
      const cleared = await clear;
      expect(cleared.entries).assertEqual(0);
      expect(persistence.content === null).assertTrue();

      const restarted = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      expect((await restarted.stats()).entries).assertEqual(0);
      await restarted.shutdown();
      await service.shutdown();
    });

    it('dropsCorruptPersistedCache', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence('{broken json');
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      // 损坏缓存按需加载：首次统计时才读盘并保留副本。
      expect((await service.stats()).entries).assertEqual(0);
      expect(persistence.preservedCount).assertEqual(1);
      await service.shutdown();
    });

    it('defersCacheReadUntilFirstUse', 0, async () => {
      const gateway = new QueuedLyricsHttpGateway();
      const persistence = new MemoryLyricsCachePersistence();
      const service = new LyricsService(gateway, 'memory://lyrics-cache', persistence);
      expect(persistence.readCount).assertEqual(0);

      await cacheOneResult(service, gateway);
      expect(persistence.readCount).assertEqual(1);
      const cached: LyricResult | null = await service.resolve(trackParams());
      expect(persistence.readCount).assertEqual(1);
      expect(cached?.sourceId).assertEqual('candidate-alpha');
      await service.shutdown();
    });
  });
}
