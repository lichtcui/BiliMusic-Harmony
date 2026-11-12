import { MobileTrack } from '../../types/MobileTypes';

/**
 * 长曲目列表的首屏分页：先渲染一页，滚动到末尾再按页追加。
 *
 * 队列/歌单/合集上限 500 首，`ForEach` 会一次性建满所有行（封面、按钮、无障碍节点），
 * 首帧与内存峰值不可控。在真正迁移到 `LazyForEach + IDataSource` 之前，用「首屏 100 行 +
 * onReachEnd 追加」把首帧成本限定在一页内，同时保持 `ForEach` 的选中态/播放态响应式行为。
 */
export const TRACK_LIST_PAGE_SIZE: number = 100;

/** 当前应渲染的行数：不超过总量，至少一页（总量更小时就是总量）。 */
export function visibleTrackCount(visibleCount: number, total: number): number {
  const safeTotal = Number.isFinite(total) ? Math.max(0, Math.floor(total)) : 0;
  const safeVisible = Number.isFinite(visibleCount) ? Math.max(0, Math.floor(visibleCount)) : 0;
  return Math.min(safeTotal, safeVisible);
}

/**
 * 打开列表时要渲染的行数：至少一页，并且必须覆盖当前播放行。
 * `ForEach` 只建 `visibleCount` 行，目标行不在数据里时 `scrollToIndex` 无法定位。
 */
export function visibleCountForIndex(currentIndex: number, total: number,
  pageSize: number = TRACK_LIST_PAGE_SIZE): number {
  const safeTotal = Number.isFinite(total) ? Math.max(0, Math.floor(total)) : 0;
  const safePage = Number.isFinite(pageSize) && pageSize > 0
    ? Math.floor(pageSize) : TRACK_LIST_PAGE_SIZE;
  const base = Math.min(safeTotal, safePage);
  if (!Number.isFinite(currentIndex)) {
    return base;
  }
  const index = Math.floor(currentIndex);
  if (index < 0) {
    return base;
  }
  return Math.min(safeTotal, Math.max(base, index + 1));
}

/** 滚到末尾后追加一页；已到总量时保持不变。 */
export function nextTrackPage(visibleCount: number, total: number,
  pageSize: number = TRACK_LIST_PAGE_SIZE): number {
  const safeTotal = Number.isFinite(total) ? Math.max(0, Math.floor(total)) : 0;
  const safeVisible = visibleTrackCount(visibleCount, safeTotal);
  const safePage = Number.isFinite(pageSize) && pageSize > 0
    ? Math.floor(pageSize) : TRACK_LIST_PAGE_SIZE;
  return Math.min(safeTotal, safeVisible + safePage);
}

/**
 * 队列行的稳定 key：同一首歌允许重复入队（例如连续点两次「下一首播放」），
 * 纯 `track.key` 会撞 key，纯 index 又会在删行/切歌时让后续所有行重建。
 * 这里只给重复项追加「同类第几次出现」的序号，单曲仍用原始 key。
 */
export function queueRowKey(track: MobileTrack, index: number, queue: MobileTrack[]): string {
  const limit = Math.min(Math.max(0, index), queue.length);
  let ordinal = 0;
  for (let cursor = 0; cursor < limit; cursor++) {
    if (queue[cursor].key === track.key) {
      ordinal += 1;
    }
  }
  return ordinal === 0 ? track.key : `${track.key}#${ordinal}`;
}

/**
 * 整份队列的行 key，一次 O(n) 扫完。
 *
 * `ForEach` 每次构建/刷新都要为每一行生成 key；逐行调用 `queueRowKey` 是 O(n²)
 * （500 首队列 ≈ 12.5 万次 key 比较）。列表组件因此按队列数组的引用缓存这份结果，
 * 只在队列真正变化时重算。语义与 `queueRowKey` 完全一致（见 TrackListPaging.test）。
 */
export function queueRowKeys(queue: MobileTrack[]): string[] {
  const seen: Map<string, number> = new Map<string, number>();
  const keys: string[] = [];
  for (const track of queue) {
    const ordinal: number = seen.has(track.key) ? seen.get(track.key) as number : 0;
    seen.set(track.key, ordinal + 1);
    keys.push(ordinal === 0 ? track.key : `${track.key}#${ordinal}`);
  }
  return keys;
}