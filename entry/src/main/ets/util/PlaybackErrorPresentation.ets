import { AppError } from '../types/MobileTypes';

export type PlaybackErrorKind = 'queue-empty' | 'source' | 'media' | 'network' | 'unknown';

export interface PlaybackErrorPresentation {
  kind: PlaybackErrorKind;
  retryable: boolean;
}

const QUEUE_EMPTY_CODES: string[] = [
  'player.queueEmpty'
];

const MEDIA_CODES: string[] = [
  'catalog.notFound',
  'player.noAudioStream',
  'player.noProgressiveStream'
];

const SOURCE_CODES: string[] = [
  'player.playUrlFailed',
  'player.prepareFailed',
  'player.playbackFailed',
  'player.stateFailed',
  'player.stateTimeout',
  'player.invalidTrack',
  'player.invalidMediaUrl',
  'player.mediaDownloadFailed',
  'player.mediaCacheFailed',
  'player.notReady'
];

const NETWORK_CODES: string[] = [
  'http.unavailable',
  'http.status',
  'http.redirectLimit',
  'http.invalidJson'
];

export function playbackErrorPresentation(error: AppError | null): PlaybackErrorPresentation {
  if (error === null) {
    return {
      kind: 'unknown',
      retryable: false
    };
  }
  const code = error.code.trim();
  if (QUEUE_EMPTY_CODES.indexOf(code) >= 0) {
    return {
      kind: 'queue-empty',
      retryable: false
    };
  }
  if (MEDIA_CODES.indexOf(code) >= 0) {
    return {
      kind: 'media',
      retryable: error.retryable
    };
  }
  if (SOURCE_CODES.indexOf(code) >= 0) {
    return {
      kind: 'source',
      retryable: error.retryable
    };
  }
  if (NETWORK_CODES.indexOf(code) >= 0) {
    return {
      kind: 'network',
      retryable: error.retryable
    };
  }
  return {
    kind: 'unknown',
    retryable: error.retryable
  };
}

export function playbackErrorTitle(kind: PlaybackErrorKind): ResourceStr {
  if (kind === 'queue-empty') {
    return $r('app.string.playback_error_queue_title');
  }
  if (kind === 'source') {
    return $r('app.string.playback_error_source_title');
  }
  if (kind === 'media') {
    return $r('app.string.playback_error_media_title');
  }
  if (kind === 'network') {
    return $r('app.string.playback_error_network_title');
  }
  return $r('app.string.playback_error_unknown_title');
}

export function playbackErrorMessage(kind: PlaybackErrorKind): ResourceStr {
  if (kind === 'queue-empty') {
    return $r('app.string.playback_error_queue_message');
  }
  if (kind === 'source') {
    return $r('app.string.playback_error_source_message');
  }
  if (kind === 'media') {
    return $r('app.string.playback_error_media_message');
  }
  if (kind === 'network') {
    return $r('app.string.playback_error_network_message');
  }
  return $r('app.string.playback_error_unknown_message');
}
