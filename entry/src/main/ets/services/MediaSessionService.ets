import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  MobileTrack,
  PlaybackStatus,
  PlayerMode
} from '../types/MobileTypes';
import { BiliHttpClient } from './BiliHttpClient';
import { isBiliImageUrl } from './BiliUrl';
import {
  MediaControlCommand,
  MediaControlDispatcher,
  MediaControlHandler
} from './MediaControlState';
import {
  metadataFor,
  metadataSignatureFor,
  modeFromMedia,
  normalizeMediaQueue,
  playbackStateFor,
  queueItemsFor,
  queueSignatureFor
} from './MediaSessionState';
import {
  AudioBackgroundLease,
  AudioBackgroundTask
} from './MediaLifecycleState';

const DOMAIN = 0x424D;
const TAG = 'WispMusicMediaSession';
const SESSION_TAG = 'wisp-music';
const ABILITY_NAME = 'EntryAbility';
const QUEUE_TITLE = 'wisp-music 播放队列';
const POSITION_SYNC_INTERVAL_MS = 5000;
const POSITION_JUMP_THRESHOLD_SECONDS = 2;

interface MediaSyncRequest {
  track: MobileTrack | null;
  status: PlaybackStatus;
  positionSeconds: number;
  durationSeconds: number;
  mode: PlayerMode;
  queue: MobileTrack[];
  queueIndex: number;
}

class SessionAudioBackgroundTask implements AudioBackgroundTask {
  private readonly service: MediaSessionService;

  constructor(service: MediaSessionService) {
    this.service = service;
  }

  start(): Promise<void> {
    return this.service.startBackgroundTask();
  }

  stop(): Promise<void> {
    return this.service.stopBackgroundTask();
  }
}

export class MediaSessionService {
  private readonly context: common.UIAbilityContext;
  private readonly commandDispatcher: MediaControlDispatcher;
  private readonly http: BiliHttpClient;
  private readonly background: AudioBackgroundLease;
  private session: avSession.AVSession | null = null;
  private initializePromise: Promise<void> | null = null;
  private shutdownPromise: Promise<void> | null = null;
  private pumpPromise: Promise<void> | null = null;
  private launchAgent: WantAgent | null = null;
  private cover: image.PixelMap | null = null;
  private coverGeneration: number = 0;
  private destroying: boolean = false;
  private listenersBound: boolean = false;
  private lastTrackKey: string = '';
  private lastCoverUrl: string = '';
  private lastMetadataSignature: string = '';
  private currentMetadata: avSession.AVMetadata | null = null;
  private lastQueueSignature: string = '';
  private pendingSync: MediaSyncRequest | null = null;
  private latestSyncRequest: MediaSyncRequest | null = null;
  private syncing: boolean = false;
  private lastStateSignature: string = '';
  private lastPlaybackPushAt: number = 0;
  private lastPushedPositionSeconds: number = 0;
  private coverRevision: number = 0;

  constructor(context: common.UIAbilityContext, controls: MediaControlHandler, http: BiliHttpClient) {
    this.context = context;
    this.commandDispatcher = new MediaControlDispatcher(controls);
    this.http = http;
    this.background = new AudioBackgroundLease(new SessionAudioBackgroundTask(this));
  }

  initialize(): Promise<void> {
    if (this.session !== null || this.destroying) {
      return Promise.resolve();
    }
    if (this.initializePromise !== null) {
      return this.initializePromise;
    }
    const initializing = this.initializeOnce();
    this.initializePromise = initializing;
    return initializing;
  }

  private async initializeOnce(): Promise<void> {
    let session: avSession.AVSession | null = null;
    try {
      session = await avSession.createAVSession(this.context, SESSION_TAG, 'audio');
      await this.bindCommands(session);
      this.launchAgent = await this.createLaunchAgent();
      if (this.launchAgent !== null) {
        try {
          await session.setLaunchAbility(this.launchAgent);
        } catch (error) {
          logSessionError('set launch ability', error);
        }
      }
      await session.activate();
      if (this.destroying) {
        await this.destroySession(session);
        return;
      }
      this.session = session;
      hilog.info(DOMAIN, TAG, 'media session ready');
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'media session unavailable code=%{public}d', businessError.code);
      if (session !== null) {
        await this.destroySession(session);
      }
    } finally {
      this.initializePromise = null;
    }
  }

  sync(track: MobileTrack | null, status: PlaybackStatus, positionSeconds: number,
    durationSeconds: number, mode: PlayerMode, queue: MobileTrack[], queueIndex: number): Promise<void> {
    if (this.session === null || this.destroying) {
      return Promise.resolve();
    }
    return this.enqueueSync({
      track: track,
      status: status,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      mode: mode,
      queue: queue,
      queueIndex: queueIndex
    });
  }

  private enqueueSync(request: MediaSyncRequest): Promise<void> {
    if (this.session === null || this.destroying) {
      return Promise.resolve();
    }
    this.latestSyncRequest = request;
    this.pendingSync = request;
    if (this.syncing) {
      return Promise.resolve();
    }
    this.syncing = true;
    const pumping = this.pumpSync();
    this.pumpPromise = pumping;
    return pumping;
  }

  private async pumpSync(): Promise<void> {
    try {
      while (!this.destroying) {
        const request = this.pendingSync;
        if (request === null) {
          break;
        }
        this.pendingSync = null;
        await this.applySync(request);
      }
    } finally {
      this.syncing = false;
      this.pumpPromise = null;
    }
  }

  private async applySync(request: MediaSyncRequest): Promise<void> {
    const session = this.session;
    if (session === null || this.destroying) {
      return;
    }
    try {
      const view = normalizeMediaQueue(request.track, request.status, request.queue, request.queueIndex);
      const track = view.track;
      const nextTrackKey = track === null ? '' : track.key;
      const trackChanged = nextTrackKey !== this.lastTrackKey;
      if (trackChanged) {
        this.coverGeneration += 1;
        this.lastCoverUrl = '';
        this.coverRevision += 1;
      }
      const metadata = metadataFor(track, request.durationSeconds, view.queue, view.queueIndex);
      const metadataSignature = metadataSignatureFor(metadata, this.coverRevision);
      if (metadataSignature !== this.lastMetadataSignature) {
        if (this.cover !== null && track !== null && this.lastTrackKey === nextTrackKey) {
          metadata.mediaImage = this.cover;
        }
        await session.setAVMetadata(metadata);
        this.currentMetadata = metadata;
        this.lastMetadataSignature = metadataSignature;
        this.lastTrackKey = nextTrackKey;
      }
      if (trackChanged) {
        await this.releaseCover();
      }
      if (track !== null && track.coverUrl !== this.lastCoverUrl && isBiliImageUrl(track.coverUrl)) {
        this.lastCoverUrl = track.coverUrl;
        this.coverGeneration += 1;
        void this.refreshCover(track.key, track.coverUrl, this.coverGeneration);
      }
      const queueSignature = queueSignatureFor(nextTrackKey, view.queue);
      if (queueSignature !== this.lastQueueSignature) {
        await session.setAVQueueItems(queueItemsFor(view.queue));
        await session.setAVQueueTitle(QUEUE_TITLE);
        this.lastQueueSignature = queueSignature;
      }
      const effectiveStatus: PlaybackStatus = view.idle ? 'idle' : request.status;
      const effectiveDuration = effectiveStatus === 'idle' ? 0 : request.durationSeconds;
      // System UI extrapolates progress from updateTime, so only periodic
      // position refreshes are needed; state, seek, queue and track changes
      // still push immediately to avoid stale media controls.
      const stateSignature = [
        nextTrackKey,
        effectiveStatus,
        String(effectiveDuration),
        request.mode,
        String(view.queueIndex),
        queueSignature
      ].join('|');
      const now = Date.now();
      const sameState = stateSignature === this.lastStateSignature;
      const sinceLastPush = now - this.lastPlaybackPushAt;
      const expectedPosition = this.lastPushedPositionSeconds +
        (request.status === 'playing' ? sinceLastPush / 1000 : 0);
      const jumped = Math.abs(request.positionSeconds - expectedPosition) > POSITION_JUMP_THRESHOLD_SECONDS;
      if (sameState && !jumped && sinceLastPush < POSITION_SYNC_INTERVAL_MS) {
        return;
      }
      const playbackState = playbackStateFor(effectiveStatus, request.positionSeconds,
        effectiveDuration, request.mode, view.queueIndex, now);
      await session.setAVPlaybackState(playbackState);
      this.lastStateSignature = stateSignature;
      this.lastPlaybackPushAt = now;
      this.lastPushedPositionSeconds = request.positionSeconds;
      if (effectiveStatus === 'playing') {
        await this.startBackground();
      }
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'media state sync failed code=%{public}d', businessError.code);
    }
  }

  async shutdown(): Promise<void> {
    if (this.shutdownPromise !== null) {
      return this.shutdownPromise;
    }
    const shuttingDown = this.shutdownOnce();
    this.shutdownPromise = shuttingDown;
    return shuttingDown;
  }

  private async shutdownOnce(): Promise<void> {
    this.destroying = true;
    this.commandDispatcher.shutdown();
    this.pendingSync = null;
    this.latestSyncRequest = null;
    this.coverGeneration += 1;
    this.coverRevision += 1;
    const stoppingBackground = this.stopBackground();
    const initializing = this.initializePromise;
    if (initializing !== null) {
      try {
        await initializing;
      } catch (error) {
        logSessionError('await initialization', error);
      }
    }
    const pumping = this.pumpPromise;
    if (pumping !== null) {
      try {
        await pumping;
      } catch (error) {
        logSessionError('await media sync', error);
      }
    }
    try {
      await stoppingBackground;
    } catch (error) {
      logSessionError('stop background', error);
    }
    await this.releaseCover();
    const session = this.session;
    this.session = null;
    this.currentMetadata = null;
    this.lastMetadataSignature = '';
    this.lastQueueSignature = '';
    this.lastTrackKey = '';
    this.lastCoverUrl = '';
    this.lastStateSignature = '';
    this.lastPlaybackPushAt = 0;
    this.lastPushedPositionSeconds = 0;
    if (session === null) {
      return;
    }
    await this.destroySession(session);
  }

  private async bindCommands(session: avSession.AVSession): Promise<void> {
    this.listenersBound = true;
    session.on('play', (): void => {
      this.dispatchCommand(session, { type: 'play' });
    });
    session.on('pause', (): void => {
      this.dispatchCommand(session, { type: 'pause' });
    });
    session.on('stop', (): void => {
      this.dispatchCommand(session, { type: 'stop' });
    });
    session.on('playNext', (): void => {
      this.dispatchCommand(session, { type: 'next' });
    });
    session.on('playPrevious', (): void => {
      this.dispatchCommand(session, { type: 'previous' });
    });
    session.on('seek', (positionMs: number): void => {
      const safePositionMs = Number.isFinite(positionMs) ? Math.max(0, positionMs) : 0;
      this.dispatchCommand(session, {
        type: 'seek',
        positionSeconds: safePositionMs / 1000
      });
    });
    session.on('setLoopMode', (mode: avSession.LoopMode): void => {
      this.dispatchCommand(session, {
        type: 'mode-change',
        mode: modeFromMedia(mode)
      });
    });
  }

  private dispatchCommand(session: avSession.AVSession, command: MediaControlCommand): void {
    if (this.destroying || this.session !== session) {
      return;
    }
    this.commandDispatcher.dispatch(command);
  }

  private unbindCommands(session: avSession.AVSession): void {
    if (!this.listenersBound) {
      return;
    }
    this.listenersBound = false;
    try {
      session.off('play');
    } catch (error) {
      logSessionError('off play', error);
    }
    try {
      session.off('pause');
    } catch (error) {
      logSessionError('off pause', error);
    }
    try {
      session.off('stop');
    } catch (error) {
      logSessionError('off stop', error);
    }
    try {
      session.off('playNext');
    } catch (error) {
      logSessionError('off playNext', error);
    }
    try {
      session.off('playPrevious');
    } catch (error) {
      logSessionError('off playPrevious', error);
    }
    try {
      session.off('seek');
    } catch (error) {
      logSessionError('off seek', error);
    }
    try {
      session.off('setLoopMode');
    } catch (error) {
      logSessionError('off setLoopMode', error);
    }
  }

  private async destroySession(session: avSession.AVSession): Promise<void> {
    this.unbindCommands(session);
    try {
      await session.deactivate();
    } catch (error) {
      logSessionError('deactivate', error);
    }
    try {
      await session.destroy();
    } catch (error) {
      logSessionError('destroy', error);
    }
  }

  private async createLaunchAgent(): Promise<WantAgent | null> {
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: this.context.applicationInfo.name,
          abilityName: ABILITY_NAME
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 1,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (error) {
      logSessionError('launch agent', error);
      return null;
    }
  }

  private async startBackground(): Promise<void> {
    try {
      await this.background.start();
    } catch (error) {
      logSessionError('start background', error);
    }
  }

  private async stopBackground(): Promise<void> {
    await this.background.stop();
  }

  async startBackgroundTask(): Promise<void> {
    if (this.destroying) {
      return;
    }
    const agent = this.launchAgent ?? await this.createLaunchAgent();
    if (agent === null || this.destroying) {
      return;
    }
    this.launchAgent = agent;
    await backgroundTaskManager.startBackgroundRunning(this.context, ['audioPlayback'], agent);
    hilog.info(DOMAIN, TAG, 'audio background task started');
  }

  async stopBackgroundTask(): Promise<void> {
    await backgroundTaskManager.stopBackgroundRunning(this.context);
    hilog.info(DOMAIN, TAG, 'audio background task stopped');
  }

  private async refreshCover(trackKey: string, coverUrl: string, generation: number): Promise<void> {
    if (!isBiliImageUrl(coverUrl)) {
      return;
    }
    let source: image.ImageSource | null = null;
    try {
      const response = await this.http.requestImage(coverUrl);
      source = image.createImageSource(response.data);
      const info = await source.getImageInfo();
      const longest = Math.max(info.size.width, info.size.height);
      const scale = longest > 512 ? 512 / longest : 1;
      const options: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        }
      };
      const pixelMap = await source.createPixelMap(options);
      if (this.destroying || generation !== this.coverGeneration || this.lastTrackKey !== trackKey) {
        await pixelMap.release();
        return;
      }
      await this.releaseCover();
      this.cover = pixelMap;
      this.coverRevision += 1;
      this.resyncLatest();
    } catch (error) {
      logSessionError('cover load', error);
    } finally {
      if (source !== null) {
        await source.release();
      }
    }
  }

  private resyncLatest(): void {
    const latest = this.latestSyncRequest;
    if (latest === null || this.destroying) {
      return;
    }
    void this.enqueueSync({
      track: latest.track,
      status: latest.status,
      positionSeconds: latest.positionSeconds,
      durationSeconds: latest.durationSeconds,
      mode: latest.mode,
      queue: latest.queue.slice(),
      queueIndex: latest.queueIndex
    });
  }

  private async releaseCover(): Promise<void> {
    const cover = this.cover;
    this.cover = null;
    if (cover !== null) {
      try {
        await cover.release();
      } catch (error) {
        logSessionError('cover release', error);
      }
    }
  }
}

function logSessionError(action: string, error: Object): void {
  const businessError = error as BusinessError;
  hilog.warn(DOMAIN, TAG, '%{public}s failed code=%{public}d', action, businessError.code);
}
