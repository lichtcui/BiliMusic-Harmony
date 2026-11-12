import { describe, expect, it } from '@ohos/hypium';
import {
  PLAYER_SESSION_VERSION,
  PLAYER_SESSION_WRITE_INTERVAL_MS,
  PlayerSessionPersistence,
  PlayerSessionScheduler,
  PlayerSessionStore
} from '../main/ets/state/PlayerSessionStore';
import {
  MobileTrack,
  PlaybackState,
  PlayerMode,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';
import { PLAYER_QUEUE_LIMIT } from '../main/ets/services/PlayerQueue';
import { wait } from '../main/ets/util/Errors';

class MemorySessionPersistence implements PlayerSessionPersistence {
  content: string | null = null;
  writeCount: number = 0;
  deleteCount: number = 0;
  activeWrites: number = 0;
  maxActiveWrites: number = 0;
  preservedCount: number = 0;
  failWrites: boolean = false;

  constructor(content: string | null = null) {
    this.content = content;
  }

  read(_path: string): string | null {
    return this.content;
  }

  async write(_path: string, content: string): Promise<void> {
    this.writeCount++;
    this.activeWrites++;
    this.maxActiveWrites = Math.max(this.maxActiveWrites, this.activeWrites);
    try {
      await wait(2);
      if (this.failWrites) {
        throw new Error('simulated session write failure');
      }
      this.content = content;
    } finally {
      this.activeWrites--;
    }
  }

  preserveCorrupt(_path: string): void {
    this.preservedCount++;
  }

  delete(_path: string): void {
    this.deleteCount++;
    this.content = null;
  }
}

class FakeSessionTimer {
  readonly id: number;
  readonly callback: () => void;
  readonly delayMs: number;
  cancelled: boolean = false;
  ran: boolean = false;

  constructor(id: number, callback: () => void, delayMs: number) {
    this.id = id;
    this.callback = callback;
    this.delayMs = delayMs;
  }
}

class FakeSessionScheduler implements PlayerSessionScheduler {
  nowMs: number = 1000;
  readonly timers: FakeSessionTimer[] = [];
  private nextId: number = 1;

  now(): number {
    return this.nowMs;
  }

  schedule(callback: () => void, delayMs: number): number {
    const timer = new FakeSessionTimer(this.nextId++, callback, delayMs);
    this.timers.push(timer);
    return timer.id;
  }

  cancel(timerId: number): void {
    for (const timer of this.timers) {
      if (timer.id === timerId) {
        timer.cancelled = true;
      }
    }
  }

  advance(milliseconds: number): void {
    this.nowMs += milliseconds;
  }

  pendingCount(): number {
    let count = 0;
    for (const timer of this.timers) {
      if (!timer.cancelled && !timer.ran) {
        count++;
      }
    }
    return count;
  }

  runNext(): void {
    for (const timer of this.timers) {
      if (!timer.ran && !timer.cancelled) {
        timer.ran = true;
        timer.callback();
        return;
      }
    }
    throw new Error('No matching session timer');
  }
}

function sessionTrack(index: number, title: string = `Track ${index}`): MobileTrack {
  return {
    key: `BV${index}:${100 + index}`,
    bvid: `BV${index}`,
    aid: index,
    cid: 100 + index,
    title: title,
    artist: `Artist ${index}`,
    coverUrl: `https://example.com/${index}.jpg`,
    duration: 180,
    playCount: 10
  };
}

function playbackState(queue: MobileTrack[], queueIndex: number, mode: PlayerMode,
  position: number, duration: number): PlaybackState {
  const state = emptyPlaybackState();
  state.status = 'paused';
  state.track = queue[queueIndex];
  state.position = position;
  state.duration = duration;
  state.mode = mode;
  state.queue = queue;
  state.queueIndex = queueIndex;
  return state;
}

function rawSession(): Record<string, Object> {
  const raw: Record<string, Object> = {};
  raw.version = PLAYER_SESSION_VERSION;
  raw.queue = [sessionTrack(1), sessionTrack(2)];
  raw.queueIndex = 1;
  raw.mode = 'repeat-all';
  raw.position = 47;
  raw.duration = 180;
  return raw;
}

export default function playerSessionStoreTest(): void {
  describe('PlayerSessionStore', () => {
    it('roundTripsSnapshotAcrossRestart', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const scheduler = new FakeSessionScheduler();
      const store = new PlayerSessionStore('memory://session', persistence, scheduler);
      const queue = [sessionTrack(1), sessionTrack(2)];

      store.captureState(playbackState(queue, 1, 'repeat-all', 47, 180));
      await store.flush();

      const restarted = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      const restored = restarted.restore();
      expect(restored?.version).assertEqual(PLAYER_SESSION_VERSION);
      expect(restored?.queue.length).assertEqual(2);
      expect(restored?.queue[1].key).assertEqual('BV2:102');
      expect(restored?.queueIndex).assertEqual(1);
      expect(restored?.mode).assertEqual('repeat-all');
      expect(restored?.position).assertEqual(47);
      expect(restored?.duration).assertEqual(180);
      expect(persistence.maxActiveWrites).assertEqual(1);

      if (restored !== null) {
        restored.queue[0].title = 'mutated outside store';
      }
      expect(restarted.restore()?.queue[0].title).assertEqual('Track 1');
    });

    it('throttlesProgressAndFlushesLatestValueBeforeRestart', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const scheduler = new FakeSessionScheduler();
      const store = new PlayerSessionStore('memory://session', persistence, scheduler);
      const queue = [sessionTrack(1)];
      store.captureState(playbackState(queue, 0, 'sequence', 5, 180));
      await store.flush();

      scheduler.advance(100);
      store.captureProgress(20, 180);
      store.captureProgress(35, 180);
      expect(scheduler.pendingCount()).assertEqual(1);
      expect(scheduler.timers[1].delayMs).assertEqual(PLAYER_SESSION_WRITE_INTERVAL_MS - 100);
      expect(persistence.writeCount).assertEqual(1);

      await store.flush();
      expect(scheduler.pendingCount()).assertEqual(0);
      expect(persistence.writeCount).assertEqual(2);

      const restarted = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      expect(restarted.restore()?.position).assertEqual(35);
      expect(persistence.maxActiveWrites).assertEqual(1);
    });

    it('deletesIdleSessionAndSurvivesRestartAsEmpty', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const store = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      const queue = [sessionTrack(1)];
      store.captureState(playbackState(queue, 0, 'sequence', 15, 180));
      await store.flush();
      expect(store.restore()?.position).assertEqual(15);

      store.captureState(emptyPlaybackState());
      await store.flush();

      expect(store.restore() === null).assertTrue();
      expect(persistence.content === null).assertTrue();
      expect(persistence.deleteCount).assertEqual(1);
      const restarted = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      expect(restarted.restore() === null).assertTrue();
    });

    it('recoversCorruptJsonAndPreservesTheFile', 0, () => {
      const persistence = new MemorySessionPersistence('{bad json');
      const store = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      const diagnostics = store.storageDiagnostics();

      expect(store.restore() === null).assertTrue();
      expect(diagnostics.recovered).assertTrue();
      expect(diagnostics.error?.code).assertEqual('player.sessionCorrupt');
      expect(diagnostics.error?.retryable).assertTrue();
      expect(persistence.preservedCount).assertEqual(1);
    });

    it('rejectsFutureVersionsAndPreservesTheFile', 0, () => {
      const raw = rawSession();
      raw.version = PLAYER_SESSION_VERSION + 1;
      const persistence = new MemorySessionPersistence(JSON.stringify(raw));
      const store = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());

      expect(store.restore() === null).assertTrue();
      expect(store.storageDiagnostics().error?.code)
        .assertEqual('player.sessionUnsupportedVersion');
      expect(store.storageDiagnostics().error?.retryable).assertFalse();
      expect(persistence.preservedCount).assertEqual(1);
    });

    it('rejectsInvalidIndexTrackModeDurationAndOversizedQueue', 0, () => {
      const invalidIndex = rawSession();
      invalidIndex.queueIndex = 2;

      const invalidTrack = rawSession();
      const badTrack: Record<string, Object> = {};
      badTrack.bvid = 'BV1';
      badTrack.aid = 1;
      badTrack.title = 'Missing cid';
      invalidTrack.queue = [badTrack];
      invalidTrack.queueIndex = 0;

      const invalidMode = rawSession();
      invalidMode.mode = 'random';

      const invalidDuration = rawSession();
      invalidDuration.duration = -1;

      const oversizedQueue = rawSession();
      const oversizedValues: Object[] = [];
      for (let index = 0; index < PLAYER_QUEUE_LIMIT + 1; index++) {
        oversizedValues.push(sessionTrack(index + 1));
      }
      oversizedQueue.queue = oversizedValues;
      oversizedQueue.queueIndex = 0;

      const invalidContents: string[] = [
        JSON.stringify(invalidIndex),
        JSON.stringify(invalidTrack),
        JSON.stringify(invalidMode),
        JSON.stringify(invalidDuration),
        JSON.stringify(oversizedQueue)
      ];
      for (const content of invalidContents) {
        const persistence = new MemorySessionPersistence(content);
        const store = new PlayerSessionStore('memory://session', persistence,
          new FakeSessionScheduler());
        expect(store.restore() === null).assertTrue();
        expect(store.storageDiagnostics().error?.code).assertEqual('player.sessionInvalid');
        expect(persistence.preservedCount).assertEqual(1);
      }
    });

    it('serializesForcedWritesAndRecoversAfterWriteFailure', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const scheduler = new FakeSessionScheduler();
      const store = new PlayerSessionStore('memory://session', persistence, scheduler);
      const queue = [sessionTrack(1), sessionTrack(2)];
      persistence.failWrites = true;

      store.captureState(playbackState(queue, 0, 'sequence', 10, 180));
      await store.flush();

      expect(store.restore()?.position).assertEqual(10);
      expect(store.storageDiagnostics().error?.code).assertEqual('player.sessionWriteFailed');
      expect(store.storageDiagnostics().error?.retryable).assertTrue();
      expect(persistence.content === null).assertTrue();

      persistence.failWrites = false;
      store.captureState(playbackState(queue, 1, 'shuffle', 60, 180));
      store.captureState(playbackState(queue, 1, 'repeat-one', 65, 180));
      await store.flush();

      expect(persistence.maxActiveWrites).assertEqual(1);
      expect(store.storageDiagnostics().error === null).assertTrue();
      const restarted = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      expect(restarted.restore()?.queueIndex).assertEqual(1);
      expect(restarted.restore()?.mode).assertEqual('repeat-one');
      expect(restarted.restore()?.position).assertEqual(65);
    });

    it('clampsProgressAndIgnoresOversizedLiveQueues', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const store = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      const queue = [sessionTrack(1)];
      store.captureState(playbackState(queue, 0, 'sequence', 5, 180));
      await store.flush();
      store.captureProgress(500, 180);
      await store.flush();
      expect(store.restore()?.position).assertEqual(180);

      const oversizedValues: MobileTrack[] = [];
      for (let index = 0; index < PLAYER_QUEUE_LIMIT + 1; index++) {
        oversizedValues.push(sessionTrack(index + 1));
      }
      const oversized = playbackState(oversizedValues, 0, 'sequence', 10, 180);
      store.captureState(oversized);
      await store.flush();

      expect(store.restore() === null).assertTrue();
      expect(persistence.content === null).assertTrue();
    });

    it('retriesFlushAfterTransientWriteFailure', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const store = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      const queue = [sessionTrack(1), sessionTrack(2)];

      persistence.failWrites = true;
      store.captureState(playbackState(queue, 1, 'repeat-all', 10, 180));
      await store.flush();
      expect(store.storageDiagnostics().error?.code).assertEqual('player.sessionWriteFailed');
      expect(persistence.content === null).assertTrue();

      // 失败快照已回填，下一次 flush 不需要新的 captureState 也能自愈。
      persistence.failWrites = false;
      await store.flush();
      expect(store.storageDiagnostics().error === null).assertTrue();
      const restarted = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      expect(restarted.restore()?.queueIndex).assertEqual(1);
      expect(restarted.restore()?.position).assertEqual(10);
    });

    it('disposeCancelsThrottleWritesPendingAndIgnoresLateProgress', 0, async () => {
      const persistence = new MemorySessionPersistence();
      const scheduler = new FakeSessionScheduler();
      const store = new PlayerSessionStore('memory://session', persistence, scheduler);
      const queue = [sessionTrack(1)];
      store.captureState(playbackState(queue, 0, 'sequence', 5, 180));
      await store.flush();

      scheduler.advance(100);
      store.captureProgress(30, 180);
      expect(scheduler.pendingCount()).assertEqual(1);

      await store.dispose();
      expect(scheduler.pendingCount()).assertEqual(0);
      const restarted = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      expect(restarted.restore()?.position).assertEqual(30);

      store.captureProgress(60, 180);
      await store.flush();
      const afterLateProgress = new PlayerSessionStore('memory://session', persistence,
        new FakeSessionScheduler());
      expect(afterLateProgress.restore()?.position).assertEqual(30);
    });
  });
}
