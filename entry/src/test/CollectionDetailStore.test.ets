import { describe, expect, it } from '@ohos/hypium';
import {
  CollectionDetailGateway,
  CollectionDetailStore
} from '../main/ets/state/CollectionDetailStore';
import {
  PlayerCommandTarget,
  PlayerProgressScheduler,
  PlayerStore
} from '../main/ets/state/PlayerStore';
import {
  CatalogCollection,
  MobileTrack,
  PlaybackState,
  PlayerSessionSnapshot,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';

const COLLECTION_BVID: string = 'BV1COLLECTION';

class CollectionFakeScheduler implements PlayerProgressScheduler {
  now(): number {
    return 1000;
  }

  schedule(_callback: () => void, _delayMs: number): number {
    return 1;
  }

  cancel(_timerId: number): void {
  }
}

class CollectionFakePlayerTarget implements PlayerCommandTarget {
  state: PlaybackState = emptyPlaybackState();
  queue: MobileTrack[] = [];
  startIndex: number = -1;
  autoplay: boolean = false;
  loadQueueCalls: number = 0;

  loadQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.loadQueueCalls++;
    this.queue = cloneTracks(params.queue as MobileTrack[]);
    this.startIndex = params.startIndex as number;
    this.autoplay = params.autoplay as boolean;
    return Promise.resolve(clonePlaybackState(this.state));
  }

  appendToQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  removeFromQueue(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  clearQueue(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  restoreSession(_session: PlayerSessionSnapshot): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  play(_params: Record<string, Object>): Promise<PlaybackState> {
    this.state.status = 'playing';
    return Promise.resolve(clonePlaybackState(this.state));
  }

  pause(): Promise<PlaybackState> {
    this.state.status = 'paused';
    return Promise.resolve(clonePlaybackState(this.state));
  }

  seek(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  next(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  previous(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  skipPrevious(): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  setMode(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  setQuality(_params: Record<string, Object>): Promise<PlaybackState> {
    return Promise.resolve(clonePlaybackState(this.state));
  }

  snapshot(): PlaybackState {
    return clonePlaybackState(this.state);
  }
}

class FakeCollectionGateway implements CollectionDetailGateway {
  readonly bvids: string[] = [];
  result: CatalogCollection | null = null;
  failNext: boolean = false;
  failAlways: boolean = false;

  async catalogCollection(bvid: string): Promise<CatalogCollection | null> {
    this.bvids.push(bvid);
    if (this.failNext) {
      this.failNext = false;
      throw new Error('simulated collection failure');
    }
    if (this.failAlways) {
      throw new Error('simulated collection failure');
    }
    return this.result;
  }
}

class CollectionHarness {
  readonly gateway: FakeCollectionGateway = new FakeCollectionGateway();
  readonly playerTarget: CollectionFakePlayerTarget = new CollectionFakePlayerTarget();
  readonly playerStore: PlayerStore = new PlayerStore(new CollectionFakeScheduler());
  readonly store: CollectionDetailStore;

  constructor(collection: CatalogCollection | null) {
    this.playerStore.bind(this.playerTarget);
    this.gateway.result = collection;
    this.store = new CollectionDetailStore(this.gateway, this.playerStore, COLLECTION_BVID);
    this.store.attach();
  }
}

function partTrack(id: number): MobileTrack {
  return {
    key: `${COLLECTION_BVID}:${id}`,
    bvid: COLLECTION_BVID,
    aid: 1,
    cid: id,
    title: `P${id}`,
    artist: 'Uploader',
    coverUrl: 'https://example.com/cover.jpg',
    duration: 120 + id,
    playCount: id
  };
}

function collection(parts: MobileTrack[]): CatalogCollection {
  return {
    bvid: COLLECTION_BVID,
    aid: 1,
    title: 'Fixture Collection',
    artist: 'Uploader',
    coverUrl: 'https://example.com/cover.jpg',
    totalDuration: 600,
    parts: parts
  };
}

function trackKeys(tracks: MobileTrack[]): string[] {
  return tracks.map((track: MobileTrack): string => track.key);
}

function cloneTrack(track: MobileTrack): MobileTrack {
  return {
    key: track.key,
    bvid: track.bvid,
    aid: track.aid,
    cid: track.cid,
    title: track.title,
    artist: track.artist,
    coverUrl: track.coverUrl,
    duration: track.duration,
    playCount: track.playCount
  };
}

function cloneTracks(tracks: MobileTrack[]): MobileTrack[] {
  return tracks.map((track: MobileTrack): MobileTrack => cloneTrack(track));
}

function clonePlaybackState(state: PlaybackState): PlaybackState {
  const result = emptyPlaybackState();
  result.status = state.status;
  result.track = state.track === null ? null : cloneTrack(state.track);
  result.position = state.position;
  result.duration = state.duration;
  result.volume = state.volume;
  result.mode = state.mode;
  result.queue = cloneTracks(state.queue);
  result.queueIndex = state.queueIndex;
  return result;
}

export default function collectionDetailStoreTest(): void {
  describe('CollectionDetailStore', () => {
    it('loadsCollectionPartsIntoTheDetailSnapshot', 0, async () => {
      const first = partTrack(1);
      const second = partTrack(2);
      const harness = new CollectionHarness(collection([first, second]));

      await harness.store.load();

      expect(harness.gateway.bvids).assertDeepEquals([COLLECTION_BVID]);
      expect(harness.store.status).assertEqual('ready');
      expect(harness.store.title).assertEqual('Fixture Collection');
      expect(harness.store.artist).assertEqual('Uploader');
      expect(harness.store.coverUrl).assertEqual('https://example.com/cover.jpg');
      expect(harness.store.totalDuration).assertEqual(600);
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key, second.key]);
      expect(harness.store.error === null).assertTrue();
    });

    it('keepsAnErrorWhenTheCollectionIsUnavailable', 0, async () => {
      const harness = new CollectionHarness(null);

      await harness.store.load();

      expect(harness.store.status).assertEqual('error');
      expect(harness.store.error === null).assertFalse();
      expect(harness.store.tracks.length).assertEqual(0);
    });

    it('retriesAfterAFailedLoad', 0, async () => {
      const first = partTrack(1);
      const harness = new CollectionHarness(collection([first]));
      harness.gateway.failNext = true;

      await harness.store.load();
      expect(harness.store.status).assertEqual('error');

      await harness.store.load();
      expect(harness.store.status).assertEqual('ready');
      expect(trackKeys(harness.store.tracks)).assertDeepEquals([first.key]);
      expect(harness.gateway.bvids.length).assertEqual(2);
    });

    it('playsAllPartsFromTheFirstIndex', 0, async () => {
      const first = partTrack(1);
      const second = partTrack(2);
      const harness = new CollectionHarness(collection([second, first]));
      await harness.store.load();

      expect(await harness.store.playAll()).assertTrue();

      expect(harness.playerTarget.loadQueueCalls).assertEqual(1);
      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([second.key, first.key]);
      expect(harness.playerTarget.startIndex).assertEqual(0);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('playsTheTappedPartAtItsCollectionIndex', 0, async () => {
      const first = partTrack(1);
      const second = partTrack(2);
      const third = partTrack(3);
      const harness = new CollectionHarness(collection([first, second, third]));
      await harness.store.load();

      expect(await harness.store.playTrack(second.key)).assertTrue();

      expect(trackKeys(harness.playerTarget.queue)).assertDeepEquals([first.key, second.key, third.key]);
      expect(harness.playerTarget.startIndex).assertEqual(1);
      expect(harness.playerTarget.autoplay).assertTrue();
    });

    it('refusesToPlayBeforeTheCollectionIsReady', 0, async () => {
      const harness = new CollectionHarness(collection([partTrack(1)]));

      expect(await harness.store.playAll()).assertFalse();
      expect(await harness.store.playTrack(partTrack(1).key)).assertFalse();
      expect(harness.playerTarget.loadQueueCalls).assertEqual(0);
    });

    it('togglesSelectsAllAndReturnsSelectedTracksInOrder', 0, async () => {
      const first = partTrack(1);
      const second = partTrack(2);
      const harness = new CollectionHarness(collection([first, second]));
      await harness.store.load();

      expect(harness.store.toggleSelection(second.key)).assertTrue();
      expect(harness.store.isSelected(second.key)).assertTrue();
      expect(harness.store.toggleSelection(second.key)).assertTrue();
      expect(harness.store.isSelected(second.key)).assertFalse();

      harness.store.selectAll();
      expect(harness.store.isAllSelected()).assertTrue();
      expect(trackKeys(harness.store.selectedTracks())).assertDeepEquals([first.key, second.key]);
      harness.store.clearSelection();
      expect(harness.store.isAllSelected()).assertFalse();
    });

    it('disposesWithoutAcceptingLateResults', 0, async () => {
      const first = partTrack(1);
      const harness = new CollectionHarness(collection([first]));
      harness.store.dispose();

      await harness.store.load();

      expect(harness.store.tracks.length).assertEqual(0);
      expect(harness.gateway.bvids.length).assertEqual(0);
    });
  });
}