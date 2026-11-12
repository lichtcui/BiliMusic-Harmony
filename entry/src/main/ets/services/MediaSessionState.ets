import { avSession } from '@kit.AVSessionKit';
import {
  MobileTrack,
  PlaybackStatus,
  PlayerMode
} from '../types/MobileTypes';
import { PLAYER_QUEUE_LIMIT } from './PlayerQueue';
import { isBiliImageUrl } from './BiliUrl';

export const MEDIA_SESSION_QUEUE_ID: string = 'wisp-music-player-queue';
export const MEDIA_SESSION_IDLE_ASSET_ID: string = 'wisp-music-idle';

export interface MediaQueueView {
  track: MobileTrack | null;
  idle: boolean;
  queue: MobileTrack[];
  queueIndex: number;
}

export function normalizeMediaQueue(track: MobileTrack | null, status: PlaybackStatus,
  queue: MobileTrack[], queueIndex: number): MediaQueueView {
  if (track === null || status === 'idle') {
    return {
      track: null,
      idle: true,
      queue: [],
      queueIndex: -1
    };
  }
  const limited = queue.slice(0, PLAYER_QUEUE_LIMIT);
  let index = -1;
  if (Number.isInteger(queueIndex) && queueIndex >= 0 && queueIndex < limited.length &&
    limited[queueIndex].key === track.key) {
    index = queueIndex;
  } else {
    for (let candidate = 0; candidate < limited.length; candidate++) {
      if (limited[candidate].key === track.key) {
        index = candidate;
        break;
      }
    }
  }
  return {
    track: track,
    idle: false,
    queue: limited,
    queueIndex: index
  };
}

export function metadataFor(track: MobileTrack | null, durationSeconds: number,
  queue: MobileTrack[], queueIndex: number): avSession.AVMetadata {
  if (track === null) {
    return {
      assetId: MEDIA_SESSION_IDLE_ASSET_ID,
      title: 'wisp-music',
      artist: '暂无播放',
      duration: 0,
      avQueueId: MEDIA_SESSION_QUEUE_ID
    };
  }
  const metadata: avSession.AVMetadata = {
    assetId: track.key,
    title: track.title,
    artist: track.artist,
    duration: secondsToMilliseconds(durationSeconds),
    avQueueId: MEDIA_SESSION_QUEUE_ID
  };
  if (queueIndex > 0 && queueIndex < queue.length) {
    metadata.previousAssetId = queue[queueIndex - 1].key;
  }
  if (queueIndex >= 0 && queueIndex + 1 < queue.length) {
    metadata.nextAssetId = queue[queueIndex + 1].key;
  }
  return metadata;
}

export function metadataSignatureFor(metadata: avSession.AVMetadata, coverRevision: number): string {
  return [
    metadata.assetId,
    metadata.title ?? '',
    metadata.artist ?? '',
    String(metadata.duration ?? 0),
    metadata.avQueueId ?? '',
    metadata.previousAssetId ?? '',
    metadata.nextAssetId ?? '',
    String(coverRevision)
  ].join('|');
}

export function playbackStateFor(status: PlaybackStatus, positionSeconds: number,
  durationSeconds: number, mode: PlayerMode, queueIndex: number,
  nowMs: number): avSession.AVPlaybackState {
  const idle = status === 'idle';
  const safeDuration = idle ? 0 : secondsToMilliseconds(durationSeconds);
  const state: avSession.AVPlaybackState = {
    state: mediaState(status),
    position: {
      elapsedTime: idle ? 0 : clampedMilliseconds(positionSeconds, safeDuration),
      updateTime: safeTimestamp(nowMs)
    },
    loopMode: mediaLoopMode(mode),
    duration: safeDuration
  };
  if (!idle && queueIndex >= 0) {
    state.activeItemId = queueIndex;
  }
  return state;
}

export function queueItemsFor(queue: MobileTrack[]): avSession.AVQueueItem[] {
  return queue.slice(0, PLAYER_QUEUE_LIMIT).map((track: MobileTrack,
    index: number): avSession.AVQueueItem => {
    const description: avSession.AVMediaDescription = {
      assetId: track.key,
      title: track.title,
      artist: track.artist,
      duration: secondsToMilliseconds(track.duration)
    };
    if (isBiliImageUrl(track.coverUrl)) {
      description.mediaImage = track.coverUrl;
    }
    return {
      itemId: index,
      description: description
    };
  });
}

export function queueSignatureFor(trackKey: string, queue: MobileTrack[]): string {
  const parts: string[] = [trackKey, String(queue.length)];
  for (const track of queue.slice(0, PLAYER_QUEUE_LIMIT)) {
    parts.push([
      track.key,
      track.title,
      track.artist,
      String(track.duration),
      track.coverUrl
    ].join(','));
  }
  return parts.join('|');
}

export function mediaState(status: PlaybackStatus): avSession.PlaybackState {
  if (status === 'playing') {
    return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
  }
  if (status === 'paused') {
    return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
  }
  if (status === 'loading') {
    return avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
  }
  if (status === 'error') {
    return avSession.PlaybackState.PLAYBACK_STATE_STOP;
  }
  return avSession.PlaybackState.PLAYBACK_STATE_IDLE;
}

export function mediaLoopMode(mode: PlayerMode): avSession.LoopMode {
  if (mode === 'repeat-one') {
    return avSession.LoopMode.LOOP_MODE_SINGLE;
  }
  if (mode === 'repeat-all') {
    return avSession.LoopMode.LOOP_MODE_LIST;
  }
  if (mode === 'shuffle') {
    return avSession.LoopMode.LOOP_MODE_SHUFFLE;
  }
  return avSession.LoopMode.LOOP_MODE_SEQUENCE;
}

export function modeFromMedia(mode: avSession.LoopMode): PlayerMode {
  if (mode === avSession.LoopMode.LOOP_MODE_SINGLE) {
    return 'repeat-one';
  }
  if (mode === avSession.LoopMode.LOOP_MODE_LIST) {
    return 'repeat-all';
  }
  if (mode === avSession.LoopMode.LOOP_MODE_SHUFFLE) {
    return 'shuffle';
  }
  return 'sequence';
}

export function secondsToMilliseconds(value: number): number {
  return Math.max(0, Math.round(Number.isFinite(value) ? value * 1000 : 0));
}

function clampedMilliseconds(positionSeconds: number, durationMs: number): number {
  const positionMs = secondsToMilliseconds(positionSeconds);
  return durationMs > 0 ? Math.min(positionMs, durationMs) : positionMs;
}

function safeTimestamp(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
}
