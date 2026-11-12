import { MobileTrack, PlayerMode } from '../types/MobileTypes';
import {
  numberValue,
  objectValue,
  stringValue
} from '../util/Json';

export const PLAYER_QUEUE_LIMIT: number = 500;
export const PREVIOUS_RESTART_THRESHOLD_SECONDS: number = 5;

export interface PlayerQueueRemoval {
  queue: MobileTrack[];
  queueIndex: number;
  selectedIndex: number;
  removedCurrent: boolean;
  changed: boolean;
}

export interface PlayerQueueHeadPlacement {
  queue: MobileTrack[];
  index: number;
  full: boolean;
}

/**
 * 把曲目放到队列首位且不产生重复项：已在队列中的同一 key 会被移动而不是再次插入。
 * 队列已满且曲目不在队列中时返回 full，调用方据此提示用户而不会静默丢弃其他曲目。
 */
export function placeTrackAtQueueHead(queue: MobileTrack[], track: MobileTrack,
  maximum: number): PlayerQueueHeadPlacement {
  const limit = Math.max(0, Math.floor(maximum));
  if (limit <= 0) {
    return {
      queue: queue.slice(),
      index: -1,
      full: true
    };
  }
  const seen: Set<string> = new Set<string>();
  const remaining: MobileTrack[] = [];
  let alreadyQueued = false;
  for (const item of queue) {
    if (item.key === track.key) {
      alreadyQueued = true;
      continue;
    }
    if (seen.has(item.key)) {
      continue;
    }
    seen.add(item.key);
    remaining.push(item);
  }
  if (!alreadyQueued && remaining.length >= limit) {
    return {
      queue: queue.slice(),
      index: -1,
      full: true
    };
  }
  const next: MobileTrack[] = [track];
  for (const item of remaining) {
    if (next.length >= limit) {
      break;
    }
    next.push(item);
  }
  return {
    queue: next,
    index: 0,
    full: false
  };
}

export function sanitizePlayerQueue(values: Object[], maximum: number,
  deduplicate: boolean): MobileTrack[] {
  const limit = Math.max(0, Math.floor(maximum));
  const tracks: MobileTrack[] = [];
  const seen: Set<string> = new Set<string>();
  for (const value of values) {
    if (tracks.length >= limit) {
      break;
    }
    const raw = objectValue(value);
    const bvid = stringValue(raw.bvid).trim().slice(0, 32);
    const aid = Math.max(0, Math.floor(numberValue(raw.aid)));
    const cid = Math.max(0, Math.floor(numberValue(raw.cid)));
    const title = stringValue(raw.title).trim().slice(0, 300);
    if ((bvid.length === 0 && aid <= 0) || cid <= 0 || title.length === 0) {
      continue;
    }
    const keyBase = bvid.length > 0 ? bvid : `av${aid}`;
    const key = `${keyBase}:${cid}`;
    if (deduplicate && seen.has(key)) {
      continue;
    }
    seen.add(key);
    tracks.push({
      key: key,
      bvid: bvid,
      aid: aid,
      cid: cid,
      title: title,
      artist: stringValue(raw.artist, '未知作者').trim().slice(0, 200),
      coverUrl: safeHttpsUrl(stringValue(raw.coverUrl)),
      duration: Math.max(0, numberValue(raw.duration)),
      playCount: Math.max(0, numberValue(raw.playCount))
    });
  }
  return tracks;
}

export function removePlayerQueueTrack(queue: MobileTrack[], currentIndex: number,
  removeIndex: number): PlayerQueueRemoval {
  const current = Number.isFinite(currentIndex) ? Math.floor(currentIndex) : -1;
  const target = Number.isFinite(removeIndex) ? Math.floor(removeIndex) : -1;
  if (target < 0 || target >= queue.length) {
    return {
      queue: queue.slice(),
      queueIndex: current,
      selectedIndex: current,
      removedCurrent: false,
      changed: false
    };
  }

  const next = queue.slice();
  next.splice(target, 1);
  const removedCurrent = target === current;
  if (next.length === 0) {
    return {
      queue: next,
      queueIndex: -1,
      selectedIndex: -1,
      removedCurrent: removedCurrent,
      changed: true
    };
  }
  if (removedCurrent) {
    const selectedIndex = Math.min(target, next.length - 1);
    return {
      queue: next,
      queueIndex: selectedIndex,
      selectedIndex: selectedIndex,
      removedCurrent: true,
      changed: true
    };
  }
  const nextIndex = target < current ? current - 1 : current;
  return {
    queue: next,
    queueIndex: nextIndex,
    selectedIndex: nextIndex,
    removedCurrent: false,
    changed: true
  };
}

export function clampPlayerPosition(position: number, duration: number): number {
  if (!Number.isFinite(position)) {
    return 0;
  }
  const safeDuration = Math.max(0, duration);
  const maximum = safeDuration > 0 ? safeDuration : Number.MAX_SAFE_INTEGER;
  return Math.max(0, Math.min(maximum, position));
}

export function shouldRestartForPrevious(position: number): boolean {
  return position > PREVIOUS_RESTART_THRESHOLD_SECONDS;
}

/**
 * 列表点击曲目时的起播位置：只有点击当前正在播放的曲目才沿用实时进度，
 * 其他曲目一律从 0 开始，避免资料库里残留的历史进度被再次续播。
 */
export function queueStartPosition(restart: boolean, currentKey: string,
  currentPosition: number, currentDuration: number, targetKey: string,
  targetDuration: number): number {
  if (restart || currentKey.length === 0 || currentKey !== targetKey) {
    return 0;
  }
  const duration = currentDuration > 0 ? currentDuration : targetDuration;
  return resumablePosition(currentPosition, duration);
}

function resumablePosition(savedSeconds: number, durationSeconds: number): number {
  const saved = Math.max(0, Math.floor(Number(savedSeconds)));
  if (!Number.isFinite(saved) || saved < PREVIOUS_RESTART_THRESHOLD_SECONDS) {
    return 0;
  }
  if (durationSeconds > 0) {
    const remaining = Math.max(0, durationSeconds - saved);
    if (remaining < PREVIOUS_RESTART_THRESHOLD_SECONDS) {
      return 0;
    }
  }
  return saved;
}

export function selectPlayerTrackIndex(length: number, currentIndex: number, offset: number,
  mode: PlayerMode, manual: boolean, randomValue: number): number {
  if (length <= 0) {
    return -1;
  }
  if (mode === 'shuffle' && length > 1) {
    const sample = Number.isFinite(randomValue) ? Math.floor(Math.max(0, randomValue) * length) : 0;
    let selected = Math.min(length - 1, sample);
    if (selected === currentIndex) {
      selected = (selected + 1) % length;
    }
    return selected;
  }
  const target = currentIndex + offset;
  if (target < 0) {
    return mode === 'repeat-all' || manual ? length - 1 : 0;
  }
  if (target >= length) {
    return mode === 'repeat-all' || manual ? 0 : -1;
  }
  return target;
}

export function isPlayerGenerationCurrent(activeGeneration: number,
  expectedGeneration: number): boolean {
  return activeGeneration === expectedGeneration;
}

function safeHttpsUrl(value: string): string {
  const clean = value.trim();
  if (clean.startsWith('//')) {
    return `https:${clean}`;
  }
  if (clean.startsWith('http://')) {
    return `https://${clean.slice(7)}`;
  }
  return clean.startsWith('https://') ? clean : '';
}
