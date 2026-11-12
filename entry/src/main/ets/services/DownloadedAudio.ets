/**
 * 播放器读取「用户下载」的最小边界。
 *
 * 下载索引、文件目录和持久化都由 `DownloadService` 持有；播放器只认识
 * 「曲目 key → 一个可以直接打开的本地文件」。用独立文件声明，避免
 * `DownloadService` 为了一个类型去依赖整个播放器模块。
 */
export interface LocalAudioSource {
  path: string;
  bytes: number;
}

export interface DownloadedAudioLookup {
  local(trackKey: string): LocalAudioSource | null;
}