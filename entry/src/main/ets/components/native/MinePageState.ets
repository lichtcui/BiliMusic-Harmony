/**
 * 「我的」页的纯状态与播放队列判定。
 *
 * 快捷方块（我喜欢的 / 历史）与歌单行尾共用一个播放动作口径：
 * 队列是同一批曲目且正在播放 → 暂停；同一批且已暂停 → 续播；否则从头播放。
 */

import { MobileTrack, PlaybackStatus } from '../../types/MobileTypes';

/** 歌单行副标只有首数；负数/NaN/小数统一收敛成非负整数。 */
export function sanitizeTrackCount(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.floor(value);
}

/** 「我喜欢的」/ 歌单行尾播放键的三种动作。 */
export enum PlaylistPlaybackAction {
  PlayAll = 0,
  Pause = 1,
  Resume = 2
}

/**
 * 判断播放器队列与目标曲目 key 列表是否为同一批曲目（只比成员，不比顺序）。
 *
 * 顺序不参与判定有两个刚性理由：
 * 1. 历史起播后 `recordRecent` 会把当前曲目挪到列表首位，而队列仍是装载那一刻的顺序；
 * 2. 队列装载时会按 key 去重，资料库快照里可能存在同一 key 的重复项。
 * 任何一条都会让「顺序 + 长度完全一致」永久不成立，角标也就永远停在播放键。
 *
 * 但仍然要求两边成员完全一致，而不是「当前曲目属于列表」：否则多个包含同一首歌的
 * 歌单会同时出现暂停键，也和「当前播放的就是这个列表」的语义不符。
 */
export function hasSameTrackSet(queue: MobileTrack[], targetKeys: string[]): boolean {
  if (queue.length === 0 || targetKeys.length === 0) {
    return false;
  }
  const queueKeys: Set<string> = new Set<string>();
  for (const track of queue) {
    if (track.key.length > 0) {
      queueKeys.add(track.key);
    }
  }
  const targetSet: Set<string> = new Set<string>();
  for (const key of targetKeys) {
    if (key.length > 0) {
      targetSet.add(key);
    }
  }
  if (queueKeys.size === 0 || queueKeys.size !== targetSet.size) {
    return false;
  }
  for (const key of targetSet) {
    if (!queueKeys.has(key)) {
      return false;
    }
  }
  return true;
}

/**
 * 行尾播放键点击后的动作：
 * - 队列就是目标列表且正在播放 → 暂停；
 * - 队列就是目标列表且已暂停 → 续播（不回到第一首）；
 * - 其它情况（含正在播别的队列 / 加载中 / 出错）→ 从第一首重新播放。
 */
export function resolvePlaylistPlaybackAction(status: PlaybackStatus,
  queue: MobileTrack[], targetKeys: string[]): PlaylistPlaybackAction {
  if (!hasSameTrackSet(queue, targetKeys)) {
    return PlaylistPlaybackAction.PlayAll;
  }
  if (status === 'playing') {
    return PlaylistPlaybackAction.Pause;
  }
  if (status === 'paused') {
    return PlaylistPlaybackAction.Resume;
  }
  return PlaylistPlaybackAction.PlayAll;
}
