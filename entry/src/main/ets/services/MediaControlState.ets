import { PlaybackStatus, PlayerMode } from '../types/MobileTypes';

export type MediaControlCommandType =
  'play' | 'pause' | 'stop' | 'next' | 'previous' | 'seek' | 'mode-change';

export interface MediaControlCommand {
  type: MediaControlCommandType;
  positionSeconds?: number;
  mode?: PlayerMode;
}

export interface MediaControlHandler {
  onCommand(command: MediaControlCommand): void;
}

export class MediaControlDispatcher {
  private handler: MediaControlHandler | null;

  constructor(handler: MediaControlHandler) {
    this.handler = handler;
  }

  dispatch(command: MediaControlCommand): boolean {
    const handler = this.handler;
    if (handler === null) {
      return false;
    }
    handler.onCommand(command);
    return true;
  }

  shutdown(): void {
    this.handler = null;
  }
}

export type AudioInterruptSignal =
  'none' | 'resume' | 'pause' | 'stop' | 'duck' | 'unduck' | 'mute' | 'unmute';

export type AudioInterruptionAction = 'none' | 'pause' | 'resume';

export interface AudioInterruptionDecision {
  action: AudioInterruptionAction;
  revision: number;
}

export class MediaInterruptionState {
  private revision: number = 0;
  private interrupted: boolean = false;
  private resumeAllowed: boolean = false;
  private destroyed: boolean = false;

  isRevisionCurrent(revision: number): boolean {
    return !this.destroyed && revision >= 0 && revision === this.revision;
  }

  beginExternalCommand(): number {
    if (this.destroyed) {
      return -1;
    }
    this.revision += 1;
    this.clearInterruption();
    return this.revision;
  }

  handleInterrupt(signal: AudioInterruptSignal,
    status: PlaybackStatus): AudioInterruptionDecision {
    if (this.destroyed) {
      return noInterruptionDecision();
    }
    if (signal === 'pause') {
      if (this.interrupted || status !== 'playing') {
        return noInterruptionDecision();
      }
      this.interrupted = true;
      this.resumeAllowed = true;
      this.revision += 1;
      return {
        action: 'pause',
        revision: this.revision
      };
    }
    if (signal === 'stop') {
      const shouldPause = !this.interrupted && status === 'playing';
      this.interrupted = true;
      this.resumeAllowed = false;
      if (!shouldPause) {
        return noInterruptionDecision();
      }
      this.revision += 1;
      return {
        action: 'pause',
        revision: this.revision
      };
    }
    if (signal === 'resume' && this.interrupted && this.resumeAllowed) {
      this.clearInterruption();
      this.revision += 1;
      return {
        action: 'resume',
        revision: this.revision
      };
    }
    return noInterruptionDecision();
  }

  destroy(): void {
    this.destroyed = true;
    this.clearInterruption();
  }

  private clearInterruption(): void {
    this.interrupted = false;
    this.resumeAllowed = false;
  }
}

export type AudioOutputChangeReason =
  'none' | 'unknown' | 'new-device' | 'old-device-unavailable' | 'overridden' |
    'session-activated' | 'stream-priority-changed';

export type AudioOutputChangeAction = 'none' | 'pause';

export function audioOutputChangeReason(value: number): AudioOutputChangeReason {
  if (value === 1) {
    return 'new-device';
  }
  if (value === 2) {
    return 'old-device-unavailable';
  }
  if (value === 3) {
    return 'overridden';
  }
  if (value === 4) {
    return 'session-activated';
  }
  if (value === 5) {
    return 'stream-priority-changed';
  }
  return 'unknown';
}

export function audioOutputChangeAction(reason: AudioOutputChangeReason): AudioOutputChangeAction {
  // Device changes preserve the current AVPlayer and position. Only removal of
  // the active endpoint pauses, matching the platform recommendation.
  return reason === 'old-device-unavailable' ? 'pause' : 'none';
}

function noInterruptionDecision(): AudioInterruptionDecision {
  return {
    action: 'none',
    revision: -1
  };
}
