import { CacheSizeStats } from '../../state/CacheManagementStore';

const BYTES_PER_KB: number = 1024;
const BYTES_PER_MB: number = 1024 * 1024;
const BYTES_PER_GB: number = 1024 * 1024 * 1024;
/** 与设置页原始口径一致：小于 10 保留一位小数，其余取整（9.4 MB / 12 MB）。 */
const SINGLE_DECIMAL_THRESHOLD: number = 10;

/**
 * 缓存容量与条目的纯函数（无 ArkUI 依赖，宿主测试可直接覆盖）。
 *
 * 设置页的「缓存清理」行与缓存清理抽屉都展示同一份统计：总量、总项数、
 * 单类容量。数字兜底口径只有这一处，避免两处各写一遍格式化后出现
 * 「行上 9.4 MB、抽屉里 9 MB」这种不一致。
 *
 * 负数 / NaN / 小数与 `CacheManagementStore.sanitizeStats` 同口径：一律夹成
 * 非负整数，统计异常时宁可显示 0，也不把总容量算小或显示 `NaN B`。
 */
export function cacheStatsBytes(stats: CacheSizeStats): number {
  return sanitizeCount(stats.bytes);
}

export function cacheStatsEntries(stats: CacheSizeStats): number {
  return sanitizeCount(stats.entries);
}

/** 该缓存既没有容量也没有条目：行内「清理」和「清理全部缓存」都按空缓存禁用。 */
export function cacheStatsEmpty(stats: CacheSizeStats): boolean {
  return cacheStatsBytes(stats) === 0 && cacheStatsEntries(stats) === 0;
}

/** 设置页缓存行上的合计容量（抽屉里只按分类展示，不再给总量）。 */
export function totalCacheBytes(image: CacheSizeStats, lyrics: CacheSizeStats,
  audio: CacheSizeStats): number {
  return cacheStatsBytes(image) + cacheStatsBytes(lyrics) + cacheStatsBytes(audio);
}

/** 容量文案：B / KB / MB / GB；0 显示 `0 B`，不额外造「空」文案。 */
export function formatCacheBytes(rawBytes: number): string {
  const bytes = sanitizeCount(rawBytes);
  if (bytes < BYTES_PER_KB) {
    return `${bytes} B`;
  }
  if (bytes < BYTES_PER_MB) {
    return `${formatCacheUnit(bytes / BYTES_PER_KB)} KB`;
  }
  if (bytes < BYTES_PER_GB) {
    return `${formatCacheUnit(bytes / BYTES_PER_MB)} MB`;
  }
  return `${formatCacheUnit(bytes / BYTES_PER_GB)} GB`;
}

function formatCacheUnit(value: number): string {
  return value >= SINGLE_DECIMAL_THRESHOLD ? value.toFixed(0) : value.toFixed(1);
}

function sanitizeCount(value: number): number {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}