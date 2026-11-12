import { common } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AppError,
  AudioQuality,
  MobileTrack,
  PlaybackErrorContext,
  PlaybackState,
  PlayerMode,
  PlayerSessionSnapshot,
  emptyPlaybackState
} from '../types/MobileTypes';
import { NativeError, toAppError } from '../util/Errors';
import {
  arrayValue,
  numberValue,
  stringValue
} from '../util/Json';
import {
  AudioCandidate,
  CatalogService
} from './CatalogService';
import {
  AUDIO_CACHE_MAX_BYTES,
  AUDIO_CACHE_PREFIX,
  AudioCacheFile,
  AudioCacheStats,
  audioCacheEvictions
} from './AudioCachePolicy';
import {
  decideAudioRecovery,
  tryAudioCandidates
} from './AudioFallback';
import {
  BiliHttpClient,
  httpStatusFromError
} from './BiliHttpClient';
import { isBiliMediaUrl } from './BiliUrl';
import { LibraryStore } from './LibraryStore';
import {
  MediaSessionService
} from './MediaSessionService';
import {
  MediaCleanupHooks,
  MediaCleanupSequence
} from './MediaLifecycleState';
import {
  DownloadedAudioLookup,
  LocalAudioSource
} from './DownloadedAudio';
import {
  AudioInterruptSignal,
  audioOutputChangeAction,
  audioOutputChangeReason,
  MediaControlCommand,
  MediaControlHandler,
  MediaInterruptionState
} from './MediaControlState';
import {
  PLAYER_QUEUE_LIMIT,
  clampPlayerPosition,
  isPlayerGenerationCurrent,
  queueStartPosition,
  removePlayerQueueTrack,
  sanitizePlayerQueue,
  selectPlayerTrackIndex,
  shouldRestartForPrevious
} from './PlayerQueue';

const DOMAIN = 0x424D;
const TAG = 'WispMusicPlayer';
const PLAYER_STATE_TIMEOUT_MS = 15000;

export interface PlayerEventSink {
  onState(state: PlaybackState): void;
  onProgress(position: number, duration: number): void;
  onError(error: AppError, context?: PlaybackErrorContext): void;
}

class PlayerMediaCleanupHooks implements MediaCleanupHooks {
  private readonly stopProgressCallback: () => void;
  private readonly drainCommandsCallback: () => Promise<void>;
  private readonly flushPositionCallback: () => void;
  private readonly stopSessionCallback: () => Promise<void>;
  private readonly releasePlayerCallback: () => Promise<void>;

  constructor(stopProgressCallback: () => void, drainCommandsCallback: () => Promise<void>,
    flushPositionCallback: () => void, stopSessionCallback: () => Promise<void>,
    releasePlayerCallback: () => Promise<void>) {
    this.stopProgressCallback = stopProgressCallback;
    this.drainCommandsCallback = drainCommandsCallback;
    this.flushPositionCallback = flushPositionCallback;
    this.stopSessionCallback = stopSessionCallback;
    this.releasePlayerCallback = releasePlayerCallback;
  }

  stopProgress(): void {
    this.stopProgressCallback();
  }

  drainCommands(): Promise<void> {
    return this.drainCommandsCallback();
  }

  flushPosition(): void {
    this.flushPositionCallback();
  }

  stopSession(): Promise<void> {
    return this.stopSessionCallback();
  }

  releasePlayer(): Promise<void> {
    return this.releasePlayerCallback();
  }
}

export class PlayerService implements MediaControlHandler {
  private readonly catalog: CatalogService;
  private readonly library: LibraryStore;
  private readonly sink: PlayerEventSink;
  private readonly session: MediaSessionService;
  private readonly http: BiliHttpClient;
  private readonly cacheDir: string;
  private readonly downloads: DownloadedAudioLookup | null;
  private readonly controlState: MediaInterruptionState = new MediaInterruptionState();
  private readonly cleanup: MediaCleanupSequence = new MediaCleanupSequence();
  private state: PlaybackState = emptyPlaybackState();
  private player: media.AVPlayer | null = null;
  private localFile: fs.File | null = null;
  private generation: number = 0;
  private commandChain: Promise<void> = Promise.resolve();
  private progressTimer: number = -1;
  private urlRetried: boolean = false;
  private preparing: boolean = false;
  private playerErrorCode: number = 0;
  private recovering: boolean = false;
  private destroyed: boolean = false;
  private shutdownPromise: Promise<void> | null = null;
  private quality: AudioQuality;

  constructor(context: common.UIAbilityContext, catalog: CatalogService, library: LibraryStore,
    http: BiliHttpClient, sink: PlayerEventSink, initialQuality: AudioQuality = 'standard',
    downloads: DownloadedAudioLookup | null = null) {
    this.catalog = catalog;
    this.library = library;
    this.sink = sink;
    this.http = http;
    this.cacheDir = context.cacheDir;
    this.quality = initialQuality;
    this.downloads = downloads;
    this.session = new MediaSessionService(context, this, http);
  }

  async initialize(): Promise<void> {
    await this.session.initialize();
  }

  async loadQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      const queue = sanitizePlayerQueue(arrayValue(params.queue), PLAYER_QUEUE_LIMIT, true);
      if (queue.length === 0) {
        throw new NativeError('player.queueEmpty', '播放队列为空。');
      }
      const startIndex = clampInteger(numberValue(params.startIndex), 0, queue.length - 1, 0);
      const autoplay = params.autoplay === undefined ? true : Boolean(params.autoplay);
      // 只有点击当前正在播放的曲目才沿用实时进度；其他曲目一律从 0 开始。
      // 搜索页单曲点击通过 restart 明确要求从头播放。
      const restart = Boolean(params.restart);
      const current = this.state.track;
      const startPosition = queueStartPosition(restart, current?.key ?? '',
        this.state.position, this.state.duration, queue[startIndex].key,
        queue[startIndex].duration);
      this.state.queue = queue;
      this.state.queueIndex = startIndex;
      this.urlRetried = false;
      await this.openTrack(startIndex, startPosition, autoplay);
      return this.snapshot();
    });
  }

  async appendToQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      const available = Math.max(0, PLAYER_QUEUE_LIMIT - this.state.queue.length);
      if (available === 0) {
        return this.snapshot();
      }
      const appended = sanitizePlayerQueue(arrayValue(params.queue), available, false);
      if (appended.length === 0) {
        return this.snapshot();
      }
      this.state.queue = [...this.state.queue, ...appended];
      this.publishState();
      this.syncMediaSession();
      return this.snapshot();
    });
  }

  async removeFromQueue(params: Record<string, Object>): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      if (this.state.queue.length === 0) {
        return this.snapshot();
      }
      const removeIndex = clampInteger(numberValue(params.index),
        0, this.state.queue.length - 1, -1);
      const removal = removePlayerQueueTrack(this.state.queue, this.state.queueIndex, removeIndex);
      if (!removal.changed) {
        return this.snapshot();
      }
      const autoplay = this.state.status === 'playing' || this.state.status === 'loading';
      this.state.queue = removal.queue;
      this.state.queueIndex = removal.queueIndex;
      if (removal.queue.length === 0) {
        await this.resetToIdle();
        return this.snapshot();
      }
      if (removal.removedCurrent) {
        this.urlRetried = false;
        await this.openTrack(removal.selectedIndex, 0, autoplay);
      } else {
        this.publishState();
        this.syncMediaSession();
      }
      return this.snapshot();
    });
  }

  async clearQueue(): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      if (this.state.queue.length === 0 && this.state.track === null) {
        return this.snapshot();
      }
      await this.resetToIdle();
      return this.snapshot();
    });
  }

  async restoreSession(session: PlayerSessionSnapshot): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      if (this.destroyed) {
        throw new NativeError('player.destroyed', '播放器已关闭。');
      }
      const queue = sanitizePlayerQueue(session.queue, PLAYER_QUEUE_LIMIT, true);
      const index = Number.isInteger(session.queueIndex) ? session.queueIndex : -1;
      if (queue.length !== session.queue.length || index < 0 || index >= queue.length) {
        throw new NativeError('player.sessionInvalid', '播放会话数据无效。');
      }
      const duration = Number.isFinite(session.duration) && session.duration > 0 ?
        session.duration : 0;
      const position = clampNumber(session.position, 0,
        duration > 0 ? duration : Number.MAX_SAFE_INTEGER, 0);
      this.generation += 1;
      this.stopTicker();
      await this.releasePlayer();
      const volume = this.state.volume;
      this.state = emptyPlaybackState();
      this.state.status = 'paused';
      this.state.track = queue[index];
      this.state.position = position;
      this.state.duration = duration;
      this.state.volume = volume;
      this.state.mode = parseMode(session.mode);
      this.state.queue = queue;
      this.state.queueIndex = index;
      this.urlRetried = false;
      this.playerErrorCode = 0;
      // 冷启动恢复后，让本地唯一的位置记录与会话快照保持一致。
      this.library.updatePosition(queue[index].key, position, true);
      this.publishState();
      this.syncMediaSession();
      return this.snapshot();
    });
  }

  async play(params: Record<string, Object> = {}): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.playInternal(params);
  }

  private playInternal(params: Record<string, Object> = {}): Promise<PlaybackState> {
    return this.playInternalForRevision(params, -1);
  }

  private playInternalForRevision(params: Record<string, Object>,
    revision: number): Promise<PlaybackState> {
    return this.enqueue(async (): Promise<PlaybackState> => {
      if (revision >= 0 && !this.controlState.isRevisionCurrent(revision)) {
        return this.snapshot();
      }
      const requestedIndex = params.index;
      if (typeof requestedIndex === 'number' && Number.isInteger(requestedIndex)) {
        if (this.state.queue.length === 0) {
          throw new NativeError('player.queueEmpty', '播放队列为空。');
        }
        const index = clampInteger(requestedIndex, 0, this.state.queue.length - 1, 0);
        this.urlRetried = false;
        await this.openTrack(index, 0, true);
        return this.snapshot();
      }
      const track = this.state.track;
      if (track === null || this.state.queueIndex < 0) {
        if (this.state.queue.length > 0) {
          await this.openTrack(0, 0, true);
          return this.snapshot();
        }
        return this.snapshot();
      }
      const player = this.player;
      if (player === null || this.state.status === 'error') {
        this.urlRetried = false;
        await this.openTrack(this.state.queueIndex, this.state.position, true);
        return this.snapshot();
      }
      if (player.state === 'completed') {
        player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
      }
      if (player.state === 'prepared' || player.state === 'paused' || player.state === 'completed') {
        await player.play();
        this.state.status = 'playing';
        this.state.error = undefined;
        this.startTicker();
        this.publishState();
        this.syncMediaSession();
      } else if (player.state === 'playing') {
        this.state.status = 'playing';
        this.startTicker();
        this.publishState();
        this.syncMediaSession();
      }
      return this.snapshot();
    });
  }

  async pause(): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.pauseInternal();
  }

  private pauseInternal(): Promise<PlaybackState> {
    return this.pauseInternalForRevision(-1);
  }

  private pauseInternalForRevision(revision: number): Promise<PlaybackState> {
    return this.enqueue(async (): Promise<PlaybackState> => {
      if (revision >= 0 && !this.controlState.isRevisionCurrent(revision)) {
        return this.snapshot();
      }
      const player = this.player;
      if (player !== null && (player.state === 'playing' || player.state === 'prepared')) {
        await player.pause();
      }
      if (this.state.status !== 'idle' && this.state.status !== 'error') {
        this.state.status = 'paused';
      }
      this.stopTicker();
      this.persistPosition(true);
      this.publishState();
      this.syncMediaSession();
      return this.snapshot();
    });
  }

  async seek(params: Record<string, Object>): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.seekTo(numberValue(params.position));
  }

  private async seekTo(requested: number): Promise<PlaybackState> {
    return this.enqueue(async (): Promise<PlaybackState> => {
      const position = clampPlayerPosition(requested, this.state.duration);
      this.state.position = position;
      const player = this.player;
      if (player !== null &&
        (player.state === 'prepared' || player.state === 'playing' || player.state === 'paused' ||
          player.state === 'completed')) {
        player.seek(Math.round(position * 1000), media.SeekMode.SEEK_PREV_SYNC);
      }
      this.library.updatePosition(this.state.track?.key ?? '', position, false);
      this.publishState();
      this.sink.onProgress(position, this.state.duration);
      this.syncMediaSession();
      return this.snapshot();
    });
  }

  async next(): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      await this.advance(1, true);
      return this.snapshot();
    });
  }

  async previous(): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      if (shouldRestartForPrevious(this.state.position)) {
        const player = this.player;
        if (player !== null) {
          player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
        }
        this.state.position = 0;
        this.library.updatePosition(this.state.track?.key ?? '', 0, true);
        this.publishState();
        this.syncMediaSession();
        return this.snapshot();
      }
      await this.advance(-1, true);
      return this.snapshot();
    });
  }

  /**
   * 播放页“下拉切上一首”的专用入口：无论当前进度是否超过回退阈值都切歌。
   * 系统媒体控制仍走 `previous()`，保留“超过 5 秒先回到本曲开头”的通用语义。
   */
  async skipPrevious(): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      await this.advance(-1, true);
      return this.snapshot();
    });
  }

  async setMode(params: Record<string, Object>): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.setModeValue(parseMode(stringValue(params.mode)));
  }

  async setQuality(params: Record<string, Object>): Promise<PlaybackState> {
    this.beginExternalCommand();
    return this.enqueue(async (): Promise<PlaybackState> => {
      const quality = parseAudioQuality(stringValue(params.quality));
      if (this.quality === quality) {
        return this.snapshot();
      }
      this.quality = quality;
      const status = this.state.status;
      if (this.state.track === null || this.state.queueIndex < 0 ||
        (status !== 'playing' && status !== 'paused')) {
        this.publishState();
        return this.snapshot();
      }
      const position = this.state.position;
      this.urlRetried = false;
      await this.openTrack(this.state.queueIndex, position, status === 'playing');
      return this.snapshot();
    });
  }

  private async setModeValue(mode: PlayerMode): Promise<PlaybackState> {
    return this.enqueue(async (): Promise<PlaybackState> => {
      this.state.mode = mode;
      this.publishState();
      this.syncMediaSession();
      return this.snapshot();
    });
  }

  snapshot(): PlaybackState {
    return cloneState(this.state);
  }

  shutdown(): Promise<void> {
    if (this.shutdownPromise !== null) {
      return this.shutdownPromise;
    }
    this.destroyed = true;
    this.controlState.destroy();
    this.generation += 1;
    this.shutdownPromise = this.shutdownOnce();
    return this.shutdownPromise;
  }

  private async shutdownOnce(): Promise<void> {
    const hooks = new PlayerMediaCleanupHooks(
      (): void => {
        this.stopTicker();
      },
      (): Promise<void> => this.commandChain.catch((): void => {}),
      (): void => {
        this.persistPosition(true);
      },
      (): Promise<void> => this.session.shutdown(),
      (): Promise<void> => this.releasePlayer()
    );
    try {
      await this.cleanup.run(hooks);
    } finally {
      this.state = emptyPlaybackState();
    }
  }

  onCommand(command: MediaControlCommand): void {
    if (this.destroyed) {
      return;
    }
    if (command.type === 'play') {
      this.runSystemCommand(this.play());
    } else if (command.type === 'pause' || command.type === 'stop') {
      this.runSystemCommand(this.pause());
    } else if (command.type === 'next') {
      this.runSystemCommand(this.next());
    } else if (command.type === 'previous') {
      this.runSystemCommand(this.previous());
    } else if (command.type === 'seek') {
      const params: Record<string, Object> = {};
      params.position = command.positionSeconds ?? 0;
      this.runSystemCommand(this.seek(params));
    } else if (command.type === 'mode-change' && command.mode !== undefined) {
      const params: Record<string, Object> = {};
      params.mode = command.mode;
      this.runSystemCommand(this.setMode(params));
    }
  }

  private async openTrack(index: number, position: number, autoplay: boolean,
    recoveryOnly: boolean = false): Promise<void> {
    if (this.destroyed) {
      throw new NativeError('player.destroyed', '播放器已关闭。');
    }
    const track = this.state.queue[index];
    if (track === undefined) {
      throw new NativeError('player.invalidTrack', '曲目不存在。');
    }
    this.generation += 1;
    const generation = this.generation;
    await this.releasePlayer();
    this.state.queueIndex = index;
    this.state.track = track;
    this.state.status = 'loading';
    this.state.position = Math.max(0, position);
    this.state.duration = Math.max(0, track.duration);
    this.state.error = undefined;
    // 切歌时用新曲替换唯一的位置记录，上一首的进度立即丢弃。
    this.library.updatePosition(track.key, this.state.position, true);
    this.publishState();
    this.syncMediaSession();
    let lastError: Error | null = null;
    // 已下载的曲目优先离线播放；本地文件打不开时仍回落到网络，不阻断播放。
    if (this.downloads !== null) {
      const localSource = this.downloads.local(track.key);
      if (localSource !== null) {
        try {
          await this.prepareCandidate(null, generation, position, autoplay, localSource);
          return;
        } catch (error) {
          lastError = error as Error;
          await this.releasePlayer();
          if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
            return;
          }
        }
      }
    }
    try {
      const candidates = await this.catalog.audioSource(track, this.quality);
      if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
        return;
      }
      try {
        await this.prepareCandidates(candidates, track.key, generation, position, autoplay);
        return;
      } catch (error) {
        lastError = error as Error;
      }
      if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
        return;
      }
      await this.prepareCandidates(candidates, track.key, generation, position, autoplay, true);
      return;
    } catch (error) {
      lastError = error as Error;
    }
    if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
      return;
    }
    const finalError: Error = lastError ??
      new NativeError('player.prepareFailed', '音频地址暂时不可用。', true);
    hilog.warn(DOMAIN, TAG,
      'audio candidate set failed track=%{public}s id=0 host=api.bilibili.com ' +
      'status=%{public}d playerCode=%{public}d',
      track.key, httpStatusFromError(finalError), this.playerErrorCode);
    if (!recoveryOnly) {
      try {
        const fallback = await this.catalog.progressiveAudioSource(track);
        if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
          return;
        }
        await this.prepareCandidates(fallback, track.key, generation, position, autoplay, true);
        return;
      } catch (error) {
        lastError = error as Error;
      }
    }
    if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
      return;
    }
    this.failPlayback(finalError);
    throw finalError;
  }

  private async prepareCandidates(candidates: AudioCandidate[], trackKey: string, generation: number,
    position: number, autoplay: boolean, localOnly: boolean = false): Promise<void> {
    await tryAudioCandidates(candidates,
      (): boolean => isPlayerGenerationCurrent(this.generation, generation) && !this.destroyed,
      async (candidate: AudioCandidate): Promise<void> => {
        this.playerErrorCode = 0;
        hilog.info(DOMAIN, TAG,
          'audio candidate start track=%{public}s id=%{public}d host=%{public}s ' +
          'status=%{public}d playerCode=%{public}d',
          trackKey, candidate.id, safeHost(candidate.url), 0, 0);
        try {
          const localSource = localOnly ? await this.downloadAudioCandidate(candidate) : null;
          await this.prepareCandidate(candidate, generation, position, autoplay, localSource);
        } catch (error) {
          hilog.warn(DOMAIN, TAG,
            'audio candidate failed track=%{public}s id=%{public}d host=%{public}s ' +
            'status=%{public}d playerCode=%{public}d',
            trackKey, candidate.id, safeHost(candidate.url),
            httpStatusFromError(error), this.playerErrorCode);
          await this.releasePlayer();
          if (error instanceof Error) {
            throw error;
          }
          throw new NativeError('player.prepareFailed', '音频地址暂时不可用。', true);
        }
      });
  }

  private async prepareCandidate(candidate: AudioCandidate | null, generation: number,
    position: number, autoplay: boolean, localSource: LocalAudioSource | null = null): Promise<void> {
    this.playerErrorCode = 0;
    this.preparing = true;
    let player: media.AVPlayer | null = null;
    try {
      player = await media.createAVPlayer();
      if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
        await this.releasePlayer();
        return;
      }
      this.player = player;
      this.bindPlayerEvents(player, generation);
      if (localSource === null) {
        if (candidate === null) {
          throw new NativeError('player.prepareFailed', '音频地址暂时不可用。', true);
        }
        if (!isBiliMediaUrl(candidate.url)) {
          throw new NativeError('player.invalidMediaUrl', '音频地址无效。');
        }
        const source = media.createMediaSourceWithUrl(candidate.url, this.http.mediaHeaders(candidate.url));
        await player.setMediaSource(source);
      } else {
        const file = fs.openSync(localSource.path, fs.OpenMode.READ_ONLY);
        this.localFile = file;
        player.fdSrc = {
          fd: file.fd,
          offset: 0,
          length: localSource.bytes
        };
      }
      await waitForPlayerState(player, 'initialized', PLAYER_STATE_TIMEOUT_MS);
      if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
        await this.releasePlayer();
        return;
      }
      player.audioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      await player.prepare();
      await waitForPlayerState(player, 'prepared', PLAYER_STATE_TIMEOUT_MS);
      if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
        await this.releasePlayer();
        return;
      }
      player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
      player.setVolume(this.state.volume);
      if (position > 0) {
        player.seek(Math.round(position * 1000), media.SeekMode.SEEK_PREV_SYNC);
      }
      if (autoplay) {
        await player.play();
      }
      if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
        await this.releasePlayer();
        return;
      }
      this.state.status = autoplay ? 'playing' : 'paused';
      this.state.position = Math.max(0, position);
      const duration = player.duration;
      this.state.duration = Number.isFinite(duration) && duration > 0
        ? duration / 1000
        : Math.max(this.state.duration, this.state.track?.duration ?? 0);
      this.startTicker();
      this.publishState();
      this.syncMediaSession();
    } finally {
      this.preparing = false;
    }
  }

  private async downloadAudioCandidate(candidate: AudioCandidate): Promise<LocalAudioSource> {
    const track = this.state.track;
    if (track === null) {
      throw new NativeError('player.invalidTrack', '曲目不存在。');
    }
    const extension = candidate.source === 'dash' ? 'm4s' : 'mp4';
    const path = `${this.cacheDir}/audio-v1-${safeCacheKey(track.key)}-${candidate.id}.${extension}`;
    if (fs.accessSync(path)) {
      const bytes = fs.statSync(path).size;
      if (bytes > 0) {
        hilog.info(DOMAIN, TAG, 'audio cache hit source=%{public}s id=%{public}d bytes=%{public}d',
          candidate.source, candidate.id, bytes);
        this.touchAudioCache(path);
        return {
          path: path,
          bytes: bytes
        };
      }
      fs.unlinkSync(path);
    }
    const downloaded = await this.http.downloadMedia(candidate.url, path, 64 * 1024 * 1024);
    hilog.info(DOMAIN, TAG,
      'audio downloaded source=%{public}s id=%{public}d bytes=%{public}d mime=%{public}s',
      candidate.source, candidate.id, downloaded.bytes, downloaded.mimeType);
    this.pruneAudioCache(downloaded.path);
    return {
      path: downloaded.path,
      bytes: downloaded.bytes
    };
  }

  async audioCacheStats(): Promise<AudioCacheStats> {
    const files = this.audioCacheFiles();
    let bytes = 0;
    for (const file of files) {
      bytes += file.bytes;
    }
    return {
      bytes: bytes,
      entries: files.length
    };
  }

  async clearAudioCache(): Promise<AudioCacheStats> {
    const files = this.audioCacheFiles();
    let removed = 0;
    for (const file of files) {
      try {
        fs.unlinkSync(file.path);
        removed++;
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'audio cache remove failed');
      }
    }
    if (removed > 0) {
      hilog.info(DOMAIN, TAG, 'audio cache cleared count=%{public}d', removed);
    }
    return this.audioCacheStats();
  }

  private audioCacheFiles(): AudioCacheFile[] {
    const files: AudioCacheFile[] = [];
    try {
      const names = fs.listFileSync(this.cacheDir);
      for (const name of names) {
        if (!name.startsWith(AUDIO_CACHE_PREFIX)) {
          continue;
        }
        const path = `${this.cacheDir}/${name}`;
        try {
          const stat = fs.statSync(path);
          files.push({
            path: path,
            bytes: stat.size,
            modifiedAt: stat.mtime
          });
        } catch (error) {
          // 列表与 stat 之间被删掉的文件直接忽略。
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'audio cache list failed code=%{public}s',
        toAppError(error as Object).code);
    }
    return files;
  }

  /** 命中缓存即刷新 mtime，让淘汰策略按「最久未使用」而不是「最早下载」生效。 */
  private touchAudioCache(path: string): void {
    try {
      fs.utimes(path, Date.now());
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'audio cache touch failed code=%{public}s',
        toAppError(error as Object).code);
    }
  }

  /** 下载完成后收敛总量；淘汰失败只记日志，不能让可播放的缓存变成播放失败。 */
  private pruneAudioCache(keepPath: string): void {
    const evictions = audioCacheEvictions(
      this.audioCacheFiles(), AUDIO_CACHE_MAX_BYTES, keepPath);
    if (evictions.length === 0) {
      return;
    }
    let removed = 0;
    for (const path of evictions) {
      try {
        fs.unlinkSync(path);
        removed++;
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'audio cache evict failed');
      }
    }
    if (removed > 0) {
      hilog.info(DOMAIN, TAG, 'audio cache pruned count=%{public}d', removed);
    }
  }

  private bindPlayerEvents(player: media.AVPlayer, generation: number): void {
    player.on('stateChange', (state: media.AVPlayerState): void => {
      if (!isPlayerGenerationCurrent(this.generation, generation)) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'player state=%{public}s', state);
      if (state === 'playing' && this.state.status === 'loading') {
        this.state.status = 'playing';
        this.publishState();
      }
    });
    player.on('error', (error: BusinessError): void => {
      if (!isPlayerGenerationCurrent(this.generation, generation)) {
        return;
      }
      hilog.error(DOMAIN, TAG, 'player error code=%{public}d preparing=%{public}s',
        error.code, this.preparing ? 'yes' : 'no');
      if (this.preparing) {
        this.playerErrorCode = error.code;
        return;
      }
      void this.enqueue(async (): Promise<PlaybackState> => {
        await this.recoverAfterError(generation);
        return this.snapshot();
      });
    });
    player.on('timeUpdate', (timeMs: number): void => {
      if (!isPlayerGenerationCurrent(this.generation, generation)) {
        return;
      }
      this.state.position = clampNumber(timeMs / 1000, 0,
        this.state.duration > 0 ? this.state.duration : Number.MAX_SAFE_INTEGER, 0);
    });
    player.on('durationUpdate', (durationMs: number): void => {
      if (!isPlayerGenerationCurrent(this.generation, generation) || durationMs <= 0) {
        return;
      }
      this.state.duration = durationMs / 1000;
      this.syncMediaSession();
    });
    player.on('seekDone', (timeMs: number): void => {
      if (!isPlayerGenerationCurrent(this.generation, generation)) {
        return;
      }
      this.state.position = Math.max(0, timeMs / 1000);
      this.sink.onProgress(this.state.position, this.state.duration);
      this.syncMediaSession();
    });
    player.on('endOfStream', (): void => {
      if (!isPlayerGenerationCurrent(this.generation, generation)) {
        return;
      }
      void this.enqueue(async (): Promise<PlaybackState> => {
        await this.handleEndOfStream(generation);
        return this.snapshot();
      });
    });
    player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (!isPlayerGenerationCurrent(this.generation, generation)) {
        return;
      }
      const decision = this.controlState.handleInterrupt(
        audioInterruptSignal(event.hintType),
        this.state.status
      );
      hilog.info(DOMAIN, TAG, 'audio interrupt hint=%{public}d action=%{public}s revision=%{public}d',
        event.hintType, decision.action, decision.revision);
      if (decision.action === 'pause') {
        this.runSystemCommand(this.pauseInternalForRevision(decision.revision));
      } else if (decision.action === 'resume') {
        this.runSystemCommand(this.playInternalForRevision({}, decision.revision));
      }
    });
    player.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo): void => {
      if (!isPlayerGenerationCurrent(this.generation, generation)) {
        return;
      }
      const reason = audioOutputChangeReason(info.changeReason);
      const action = audioOutputChangeAction(reason);
      hilog.info(DOMAIN, TAG, 'audio output device changed reason=%{public}s action=%{public}s',
        reason, action);
      if (action === 'pause') {
        const revision = this.beginExternalCommand();
        if (revision < 0) {
          return;
        }
        this.runSystemCommand(this.pauseInternalForRevision(revision));
      } else {
        this.syncMediaSession();
      }
    });
  }

  private async recoverAfterError(failedGeneration: number): Promise<void> {
    if (!isPlayerGenerationCurrent(this.generation, failedGeneration) || this.destroyed) {
      return;
    }
    if (this.recovering) {
      return;
    }
    this.recovering = true;
    try {
      const index = this.state.queueIndex;
      const decision = decideAudioRecovery(this.urlRetried, this.state.track !== null,
        this.state.position);
      if (decision.action === 'fail') {
        this.failPlayback(new NativeError('player.playbackFailed', '当前曲目播放失败。', true),
          failedGeneration);
        return;
      }
      this.urlRetried = true;
      hilog.info(DOMAIN, TAG,
        'audio play URL refresh track=%{public}s id=0 host=api.bilibili.com ' +
        'status=0 playerCode=0',
        this.state.track?.key ?? '');
      await this.openTrack(index, decision.position, true, true);
    } catch (error) {
      // openTrack already publishes the single terminal error state.
    } finally {
      this.recovering = false;
    }
  }

  private async handleEndOfStream(generation: number): Promise<void> {
    if (!isPlayerGenerationCurrent(this.generation, generation) || this.destroyed) {
      return;
    }
    this.persistPosition(true);
    if (this.state.mode === 'repeat-one') {
      const player = this.player;
      if (player !== null) {
        player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
        await player.play();
        this.state.position = 0;
        this.state.status = 'playing';
        this.startTicker();
        this.publishState();
        this.syncMediaSession();
      }
      return;
    }
    const changed = await this.advance(1, false);
    if (!changed) {
      this.stopTicker();
      this.state.status = 'paused';
      this.state.position = this.state.duration;
      this.publishState();
      this.syncMediaSession();
    }
  }

  private async advance(offset: number, manual: boolean): Promise<boolean> {
    const length = this.state.queue.length;
    const target = selectPlayerTrackIndex(length, this.state.queueIndex, offset, this.state.mode,
      manual, Math.random());
    if (target < 0) {
      return false;
    }
    this.urlRetried = false;
    await this.openTrack(target, 0, true);
    return true;
  }

  private failPlayback(error: Object, generation: number = this.generation): void {
    const appError = toAppError(error);
    const track = this.state.track;
    const context: PlaybackErrorContext = {
      trackKey: track === null ? '' : track.key,
      generation: generation
    };
    this.stopTicker();
    this.state.status = 'error';
    this.state.error = appError;
    this.persistPosition(true);
    this.publishState();
    this.sink.onError(appError, context);
    this.syncMediaSession();
  }

  private async resetToIdle(): Promise<void> {
    const mode = this.state.mode;
    const volume = this.state.volume;
    this.generation += 1;
    this.stopTicker();
    this.persistPosition(true);
    await this.releasePlayer();
    this.state = emptyPlaybackState();
    this.state.mode = mode;
    this.state.volume = volume;
    this.publishState();
    this.syncMediaSession();
  }

  private startTicker(): void {
    if (this.progressTimer >= 0) {
      return;
    }
    this.progressTimer = setInterval((): void => {
      if (this.state.status !== 'playing') {
        return;
      }
      this.sink.onProgress(this.state.position, this.state.duration);
      this.persistPosition(false);
      this.syncMediaSession();
    }, 1000);
  }

  private stopTicker(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private persistPosition(force: boolean): void {
    const track = this.state.track;
    if (track === null) {
      return;
    }
    this.library.updatePosition(track.key, this.state.position, force);
  }

  private publishState(): void {
    this.sink.onState(this.snapshot());
  }

  private syncMediaSession(): void {
    void this.session.sync(
      this.state.track,
      this.state.status,
      this.state.position,
      this.state.duration,
      this.state.mode,
      this.state.queue,
      this.state.queueIndex
    );
  }

  private beginExternalCommand(): number {
    return this.controlState.beginExternalCommand();
  }

  private runSystemCommand(operation: Promise<PlaybackState>): void {
    void operation.catch((): void => {});
  }

  private async releasePlayer(): Promise<void> {
    const player = this.player;
    this.player = null;
    if (player !== null) {
      await releaseSafely(player);
    }
    const file = this.localFile;
    this.localFile = null;
    if (file !== null) {
      try {
        fs.closeSync(file);
      } catch (error) {
        const businessError = error as BusinessError;
        hilog.warn(DOMAIN, TAG, 'local media close failed code=%{public}d', businessError.code);
      }
    }
  }

  private enqueue(action: () => Promise<PlaybackState>): Promise<PlaybackState> {
    const run = (): Promise<PlaybackState> => {
      if (this.destroyed) {
        return Promise.resolve(this.snapshot());
      }
      return action();
    };
    const result = this.commandChain.then(run, run);
    this.commandChain = result.then((): void => {}, (): void => {});
    return result;
  }
}

function parseMode(value: string): PlayerMode {
  if (value === 'repeat-one' || value === 'repeat-all' || value === 'shuffle' ||
    value === 'sequence') {
    return value;
  }
  throw new NativeError('player.invalidMode', '播放模式无效。');
}

function parseAudioQuality(value: string): AudioQuality {
  if (value === 'high' || value === 'standard' || value === 'low') {
    return value;
  }
  throw new NativeError('player.invalidQuality', '音质设置无效。');
}

function safeHost(value: string): string {
  const match = /^https:\/\/([^/?#]+)/u.exec(value);
  return match !== null ? match[1] : 'unknown';
}

function safeCacheKey(value: string): string {
  const normalized = value.replace(/[^a-zA-Z0-9-]/gu, '-');
  return normalized.length > 0 ? normalized.slice(0, 80) : 'track';
}

function audioInterruptSignal(hint: audio.InterruptHint): AudioInterruptSignal {
  if (hint === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
    return 'resume';
  }
  if (hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
    return 'pause';
  }
  if (hint === audio.InterruptHint.INTERRUPT_HINT_STOP) {
    return 'stop';
  }
  if (hint === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
    return 'duck';
  }
  if (hint === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
    return 'unduck';
  }
  if (hint === audio.InterruptHint.INTERRUPT_HINT_MUTE) {
    return 'mute';
  }
  if (hint === audio.InterruptHint.INTERRUPT_HINT_UNMUTE) {
    return 'unmute';
  }
  return 'none';
}

function clampInteger(value: number, minimum: number, maximum: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback;
  }
  return Math.max(minimum, Math.min(maximum, Math.floor(value)));
}

function clampNumber(value: number, minimum: number, maximum: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback;
  }
  return Math.max(minimum, Math.min(maximum, value));
}

function cloneState(value: PlaybackState): PlaybackState {
  return JSON.parse(JSON.stringify(value)) as PlaybackState;
}

async function releaseSafely(player: media.AVPlayer): Promise<void> {
  try {
    await player.release();
  } catch (error) {
    const businessError = error as BusinessError;
    hilog.warn(DOMAIN, TAG, 'player release failed code=%{public}d', businessError.code);
  }
}

async function waitForPlayerState(player: media.AVPlayer, expected: media.AVPlayerState,
  timeoutMs: number): Promise<void> {
  if (player.state === expected) {
    return;
  }
  await new Promise<void>((resolve: () => void, reject: (reason: Object) => void) => {
    let settled = false;
    const cleanup = (): void => {
      clearTimeout(timer);
      player.off('stateChange', onStateChange);
    };
    const onStateChange = (state: media.AVPlayerState): void => {
      if (settled) {
        return;
      }
      if (state === expected) {
        settled = true;
        cleanup();
        resolve();
        return;
      }
      if (state === 'error' || state === 'released') {
        settled = true;
        cleanup();
        reject(new NativeError('player.stateFailed', `播放器无法进入 ${expected} 状态。`, true));
      }
    };
    const timer = setTimeout((): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      hilog.warn(DOMAIN, TAG, 'player state timeout expected=%{public}s actual=%{public}s',
        expected, player.state);
      reject(new NativeError('player.stateTimeout', '播放器响应超时。', true));
    }, timeoutMs);
    player.on('stateChange', onStateChange);
    if (player.state === expected) {
      settled = true;
      cleanup();
      resolve();
    }
  });
}
