import { MobileTrack } from '../types/MobileTypes';

/**
 * 列表行的成员查询索引。
 *
 * `ForEach` 每次构建 / 刷新都会逐行调用 `isSelected` / `isFavorite` / `isDownloaded` 这类判定，
 * 在数组里 `indexOf` 会让整表退化成 O(n²)（500 首队列 ≈ 12.5 万次字符串比较）。state 层因此
 * 维护一份与数组同源的 `Set`，行内查询只做 O(1) `has`。
 *
 * 约定：`Set` 不原地修改，数组变化的同一处必须整份替换对应 `Set`。页面依赖落在 `@Track`
 * 字段上才会刷新，所以 `Set` 字段也要加 `@Track`；原地 `add` / `delete` 不会触发更新。
 */
export function toKeySet(keys: string[]): Set<string> {
  const set: Set<string> = new Set<string>();
  for (const key of keys) {
    set.add(key);
  }
  return set;
}

export function trackKeySet(tracks: MobileTrack[]): Set<string> {
  const set: Set<string> = new Set<string>();
  for (const track of tracks) {
    set.add(track.key);
  }
  return set;
}