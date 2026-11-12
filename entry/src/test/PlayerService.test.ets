import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { PlayerEventSink, PlayerService } from '../main/ets/services/PlayerService';
import { AudioCandidate, CatalogService } from '../main/ets/services/CatalogService';
import { LibraryPersistence, LibraryStore } from '../main/ets/services/LibraryStore';
import { BiliHttpClient, HttpClientTransportResponse } from '../main/ets/services/BiliHttpClient';
import { AppError, AudioQuality, MobileTrack, PlaybackState } from '../main/ets/types/MobileTypes';
import { NativeError } from '../main/ets/util/Errors';
import {
  ScriptedHttpTransport,
  TestHttpUrlParser,
  errorCode,
  testCookieJar
} from './TestHttpSupport';

class MemoryLibraryPersistence implements LibraryPersistence {
  content: string | null = null;
  writeCount: number = 0;

  read(_path: string): string | null {
    return this.content;
  }

  readAsync(path: string): Promise<string | null> {
    return Promise.resolve(this.read(path));
  }

  async write(_path: string, content: string): Promise<void> {
    this.writeCount++;
    this.content = content;
  }

  preserveCorrupt(_path: string): void {
  }
}

class PlayerTestContext {
  readonly cacheDir: string = '/tmp/wisp-music-player-test';
}

class FailingCatalog extends CatalogService {
  audioCode: string = 'player.noAudioStream';
  progressiveCode: string = 'player.noProgressiveStream';
  audioCalls: number = 0;
  progressiveCalls: number = 0;

  constructor(http: BiliHttpClient) {
    super(http);
  }

  async audioSource(_track: MobileTrack, _quality?: AudioQuality): Promise<AudioCandidate[]> {
    this.audioCalls++;
    throw new NativeError(this.audioCode, 'simulated audio failure', true);
  }

  async progressiveAudioSource(_track: MobileTrack): Promise<AudioCandidate[]> {
    this.progressiveCalls++;
    throw new NativeError(this.progressiveCode, 'simulated progressive failure', true);
  }
}

class TestPlayerSink implements PlayerEventSink {
  states: PlaybackState[] = [];
  errors: AppError[] = [];
  positions: number[] = [];
  durations: number[] = [];

  onState(state: PlaybackState): void {
    this.states.push(state);
  }

  onProgress(position: number, duration: number): void {
    this.positions.push(position);
    this.durations.push(duration);
  }

  onError(error: AppError): void {
    this.errors.push(error);
  }
}

function track(index: number): MobileTrack {
  return {
    key: `BV${index}:${100 + index}`,
    bvid: `BV${index}`,
    aid: index,
    cid: 100 + index,
    title: `Track ${index}`,
    artist: `Artist ${index}`,
    coverUrl: `https://i0.hdslb.com/bfs/cover/${index}.jpg`,
    duration: 120,
    playCount: 1
  };
}

function paramsWith(key: string, value: Object): Record<string, Object> {
  const params: Record<string, Object> = {};
  params[key] = value;
  return params;
}

function newHttp(): BiliHttpClient {
  return new BiliHttpClient(testCookieJar(),
    new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
      return {
        status: 200,
        result: '{}',
        headers: {},
        cookies: ''
      };
    }), {
      urlParser: new TestHttpUrlParser(),
      retryDelayMs: async (_milliseconds: number): Promise<void> => {
      }
    });
}

class PlayerHarness {
  readonly catalog: FailingCatalog;
  readonly library: LibraryStore;
  readonly sink: TestPlayerSink;
  readonly player: PlayerService;

  constructor() {
    const http = newHttp();
    this.catalog = new FailingCatalog(http);
    this.library = new LibraryStore('memory://library', new MemoryLibraryPersistence());
    this.sink = new TestPlayerSink();
    const context = new PlayerTestContext() as Object as common.UIAbilityContext;
    this.player = new PlayerService(context, this.catalog, this.library, http, this.sink);
  }
}

export default function playerServiceTest(): void {
  describe('PlayerService', () => {
    it('rejectsAnEmptyQueueBeforeTouchingTheCatalog', 0, async () => {
      const harness = new PlayerHarness();
      let code = '';

      try {
        await harness.player.loadQueue(paramsWith('queue', []));
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('player.queueEmpty');
      expect(harness.catalog.audioCalls).assertEqual(0);
      expect(harness.player.snapshot().status).assertEqual('idle');
    });

    it('mapsCatalogFailuresToAPlaybackErrorState', 0, async () => {
      const harness = new PlayerHarness();
      const queue: MobileTrack[] = [track(1)];
      let code = '';

      try {
        await harness.player.loadQueue(paramsWith('queue', queue));
      } catch (error) {
        code = errorCode(error);
      }

      const snapshot = harness.player.snapshot();
      expect(code).assertEqual('player.noAudioStream');
      expect(snapshot.status).assertEqual('error');
      expect(snapshot.track?.key).assertEqual('BV1:101');
      expect(snapshot.error?.code).assertEqual('player.noAudioStream');
      expect(harness.sink.errors.length).assertEqual(1);
      expect(harness.sink.errors[0].code).assertEqual('player.noAudioStream');
      expect(harness.catalog.audioCalls).assertEqual(1);
      expect(harness.catalog.progressiveCalls).assertEqual(1);
    });

    it('clampsAnOutOfRangeStartIndexToTheLastTrack', 0, async () => {
      const harness = new PlayerHarness();
      const queue: MobileTrack[] = [track(1), track(2)];
      const params = paramsWith('queue', queue);
      params.startIndex = 99;

      try {
        await harness.player.loadQueue(params);
      } catch (error) {
        // The fake catalog always fails; queue/index clamping happens first.
      }

      const snapshot = harness.player.snapshot();
      expect(snapshot.queue.length).assertEqual(2);
      expect(snapshot.queueIndex).assertEqual(1);
      expect(snapshot.track?.key).assertEqual('BV2:102');
    });

    it('appendsSanitizedTracksWithoutOpeningThePlayer', 0, async () => {
      const harness = new PlayerHarness();
      const appended: MobileTrack[] = [track(3), track(4)];

      const state = await harness.player.appendToQueue(paramsWith('queue', appended));

      expect(state.queue.length).assertEqual(2);
      expect(state.queueIndex).assertEqual(-1);
      expect(state.track === null).assertTrue();
      expect(state.queue[0].key).assertEqual('BV3:103');
      expect(state.queue[1].key).assertEqual('BV4:104');
      expect(harness.catalog.audioCalls).assertEqual(0);
    });

    it('removesNonCurrentTracksWithoutReloadingThePlayer', 0, async () => {
      const harness = new PlayerHarness();
      const queue: MobileTrack[] = [track(1), track(2), track(3)];
      const loadParams = paramsWith('queue', queue);
      loadParams.startIndex = 1;
      try {
        await harness.player.loadQueue(loadParams);
      } catch (error) {
        // keep the failed loading state; the queue remains populated.
      }
      const callsBefore = harness.catalog.audioCalls;

      const state = await harness.player.removeFromQueue(paramsWith('index', 2));

      expect(state.queue.length).assertEqual(2);
      expect(state.queueIndex).assertEqual(1);
      expect(state.track?.key).assertEqual('BV2:102');
      expect(harness.catalog.audioCalls).assertEqual(callsBefore);
    });

    it('reopensTheNextTrackWhenRemovingTheCurrentOne', 0, async () => {
      const harness = new PlayerHarness();
      const queue: MobileTrack[] = [track(1), track(2)];
      const loadParams = paramsWith('queue', queue);
      loadParams.startIndex = 1;
      try {
        await harness.player.loadQueue(loadParams);
      } catch (error) {
        // state remains usable for queue mutation.
      }
      let code = '';

      try {
        await harness.player.removeFromQueue(paramsWith('index', 1));
      } catch (error) {
        code = errorCode(error);
      }

      const snapshot = harness.player.snapshot();
      expect(code).assertEqual('player.noAudioStream');
      expect(snapshot.queue.length).assertEqual(1);
      expect(snapshot.queueIndex).assertEqual(0);
      expect(snapshot.track?.key).assertEqual('BV1:101');
    });

    it('clearsTheQueueBackToIdle', 0, async () => {
      const harness = new PlayerHarness();
      try {
        await harness.player.loadQueue(paramsWith('queue', [track(1)]));
      } catch (error) {
        // ignore simulated playback failure.
      }

      const state = await harness.player.clearQueue();

      expect(state.status).assertEqual('idle');
      expect(state.queue.length).assertEqual(0);
      expect(state.queueIndex).assertEqual(-1);
      expect(state.track === null).assertTrue();
      expect(state.error === undefined).assertTrue();
    });

    it('clampsSeekToTheKnownDurationAndEmitsProgress', 0, async () => {
      const harness = new PlayerHarness();
      try {
        await harness.player.loadQueue(paramsWith('queue', [track(1)]));
      } catch (error) {
        // ignore simulated playback failure.
      }

      const high = await harness.player.seek(paramsWith('position', 999));
      const low = await harness.player.seek(paramsWith('position', -5));

      expect(high.position).assertEqual(120);
      expect(low.position).assertEqual(0);
      expect(harness.sink.positions[harness.sink.positions.length - 1]).assertEqual(0);
      expect(harness.sink.durations[harness.sink.durations.length - 1]).assertEqual(120);
    });

    it('validatesPlaybackModes', 0, async () => {
      const harness = new PlayerHarness();
      let code = '';

      const changed = await harness.player.setMode(paramsWith('mode', 'shuffle'));
      try {
        await harness.player.setMode(paramsWith('mode', 'random'));
      } catch (error) {
        code = errorCode(error);
      }

      expect(changed.mode).assertEqual('shuffle');
      expect(code).assertEqual('player.invalidMode');
    });

    it('refusesMediaDownloadsForNonWhitelistedHosts', 0, async () => {
      const http = newHttp();
      let code = '';

      try {
        await http.downloadMedia('https://evil.example/audio.m4s', '/tmp/a.m4s', 1024);
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('player.invalidMediaUrl');
    });
  });
}