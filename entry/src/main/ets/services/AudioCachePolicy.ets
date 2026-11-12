/**
 * 音频缓存（`audio-v1-*`）的命名与容量策略。
 *
 * 单曲文件上限由下载接口按 64 MB 兜底；这里管的是整个缓存目录的总量。
 * 淘汰按 mtime 升序（最久未使用的先删），命中缓存时 PlayerService 会刷新
 * mtime，因此不需要额外维护 LRU 索引。
 */
export const AUDIO_CACHE_PREFIX: string = 'audio-v1-';
export const AUDIO_CACHE_MAX_BYTES: number = 512 * 1024 * 1024;

export interface AudioCacheFile {
  path: string;
  bytes: number;
  modifiedAt: number;
}

export interface AudioCacheStats {
  bytes: number;
  entries: number;
}

/**
 * 返回需要删除的文件路径（按 mtime 升序，够用即停）。
 *
 * - `keepPath` 是刚写入/正在播放的文件，永远不会被本次淘汰选中；
 * - 统计口径与 `audioCacheStats()` 一致：只计算 `audio-v1-*` 文件本身；
 * - 负数 / NaN 一律按 0 处理，避免异常统计值触发过度删除。
 */
export function audioCacheEvictions(files: AudioCacheFile[],
  maxBytes: number = AUDIO_CACHE_MAX_BYTES, keepPath: string = ''): string[] {
  const limit = sanitizeBytes(maxBytes);
  let total = 0;
  const candidates: AudioCacheFile[] = [];
  for (const file of files) {
    const bytes = sanitizeBytes(file.bytes);
    total += bytes;
    candidates.push({
      path: file.path,
      bytes: bytes,
      modifiedAt: Number.isFinite(file.modifiedAt) ? file.modifiedAt : 0
    });
  }
  if (total <= limit) {
    return [];
  }
  candidates.sort((left: AudioCacheFile, right: AudioCacheFile): number =>
    left.modifiedAt - right.modifiedAt);
  const evictions: string[] = [];
  for (const file of candidates) {
    if (total <= limit) {
      break;
    }
    if (file.path === keepPath) {
      continue;
    }
    evictions.push(file.path);
    total -= file.bytes;
  }
  return evictions;
}

function sanitizeBytes(value: number): number {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}