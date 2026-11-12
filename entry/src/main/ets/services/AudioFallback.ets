import { AudioQuality } from '../types/MobileTypes';
import {
  arrayValue,
  numberValue,
  objectValue,
  stringValue
} from '../util/Json';

export const AUDIO_PRIORITY: number[] = [30280, 30232, 30216];

const STANDARD_AUDIO_PRIORITY: number[] = [30232, 30216];
const LOW_AUDIO_PRIORITY: number[] = [30216];

export function audioPriorityFor(quality: AudioQuality): number[] {
  if (quality === 'high') {
    return AUDIO_PRIORITY;
  }
  if (quality === 'low') {
    return LOW_AUDIO_PRIORITY;
  }
  return STANDARD_AUDIO_PRIORITY;
}

export interface AudioCandidateSource {
  url: string;
  id: number;
  mimeType: string;
  codecs: string;
  bandwidth: number;
  source: string;
}

export interface AudioCandidateSelection {
  index: number;
  candidate: AudioCandidateSource;
}

export interface AudioRecoveryDecision {
  action: 'refresh' | 'fail';
  position: number;
}

export function selectDashAudioCandidates(streams: Object[],
  quality: AudioQuality = 'standard'): AudioCandidateSource[] {
  const selected: AudioCandidateSource[] = [];
  for (const id of audioPriorityFor(quality)) {
    for (const raw of streams) {
      const stream = objectValue(raw);
      if (numberValue(stream.id) !== id) {
        continue;
      }
      const candidates: string[] = [];
      const baseUrl = stringValue(stream.baseUrl, stringValue(stream.base_url)).trim();
      if (baseUrl.length > 0) {
        candidates.push(baseUrl);
      }
      const backupValues = arrayValue(stream.backupUrl).length > 0
        ? arrayValue(stream.backupUrl)
        : arrayValue(stream.backup_url);
      for (const value of backupValues) {
        const item = stringValue(value).trim();
        if (item.length > 0) {
          candidates.push(item);
        }
      }
      for (const candidate of candidates) {
        if (isHttpsUrl(candidate) &&
          !selected.some((item: AudioCandidateSource): boolean => item.url === candidate)) {
          selected.push({
            url: candidate,
            id: id,
            mimeType: stringValue(stream.mimeType, stringValue(stream.mime_type, 'audio/mp4')),
            codecs: stringValue(stream.codecs, 'unknown'),
            bandwidth: Math.max(0, numberValue(stream.bandwidth)),
            source: 'dash'
          });
        }
      }
    }
  }
  return selected;
}

export async function tryAudioCandidates(candidates: AudioCandidateSource[],
  canContinue: () => boolean,
  attempt: (candidate: AudioCandidateSource, index: number) => Promise<void>):
  Promise<AudioCandidateSelection | null> {
  let lastError: Error | null = null;
  for (let index = 0; index < candidates.length; index += 1) {
    if (!canContinue()) {
      return null;
    }
    const candidate = candidates[index];
    try {
      await attempt(candidate, index);
      return {
        index: index,
        candidate: candidate
      };
    } catch (error) {
      lastError = error as Error;
    }
  }
  if (lastError !== null) {
    throw lastError;
  }
  throw new Error('No audio candidates available.');
}

export function decideAudioRecovery(urlRetried: boolean, hasTrack: boolean,
  position: number): AudioRecoveryDecision {
  if (!hasTrack || urlRetried || !Number.isFinite(position) || position < 0) {
    return {
      action: 'fail',
      position: 0
    };
  }
  return {
    action: 'refresh',
    position: position
  };
}

function isHttpsUrl(value: string): boolean {
  return /^https:\/\/[^/?#]+/u.test(value);
}
