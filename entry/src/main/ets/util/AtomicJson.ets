import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { errorMessage } from './Errors';

const DOMAIN = 0x424D;
const TAG = 'WispMusicAtomicJson';
/** 损坏副本只用于事后排查；保留最近两份，避免每次冷启动都新增一份明文 Cookie 备份。 */
const MAX_CORRUPT_BACKUPS: number = 2;

/**
 * 原子文件读写的最小边界。生产实现走 fileIo，单测可注入内存实现，
 * 从而在主机侧覆盖原子替换、损坏副本和删除路径。
 */
export interface AtomicJsonIo {
  readText(path: string): string;
  /** 异步读盘：冷启动用它把文件 IO 移出主线程，避免阻塞首帧。 */
  readTextAsync(path: string): Promise<string>;
  writeText(path: string, content: string): Promise<void>;
  copyFile(source: string, target: string): void;
  listFiles(directory: string): string[];
  deleteFile(path: string): void;
  exists(path: string): boolean;
}

class PlatformAtomicJsonIo implements AtomicJsonIo {
  readText(path: string): string {
    const atomic = new fs.AtomicFile(path);
    const buffer = atomic.readFully();
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
  }

  /**
   * 写入侧始终走 AtomicFile，提交后目标文件是被整体替换的，
   * 因此异步读取直接读目标路径即可看到同一份已提交内容。
   */
  async readTextAsync(path: string): Promise<string> {
    const content: string = await fs.readText(path);
    return content;
  }

  async writeText(path: string, content: string): Promise<void> {
    const atomic = new fs.AtomicFile(path);
    const stream = atomic.startWrite();
    try {
      await stream.write(content);
      atomic.finishWrite();
    } catch (error) {
      try {
        stream.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'failed to close atomic stream after write error');
      }
      try {
        atomic.failWrite();
      } catch (rollbackError) {
        hilog.warn(DOMAIN, TAG, 'failed to roll back atomic write');
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(errorMessage(error));
    }
  }

  copyFile(source: string, target: string): void {
    fs.copyFileSync(source, target);
  }

  listFiles(directory: string): string[] {
    return fs.listFileSync(directory);
  }

  deleteFile(path: string): void {
    fs.unlinkSync(path);
  }

  exists(path: string): boolean {
    return fs.accessSync(path);
  }
}

export const atomicJsonIo: AtomicJsonIo = new PlatformAtomicJsonIo();

export function readAtomicText(path: string, io: AtomicJsonIo = atomicJsonIo): string | null {
  try {
    return io.readText(path);
  } catch (error) {
    const businessError = error as BusinessError;
    if (businessError.code !== 13900002) {
      hilog.warn(DOMAIN, TAG, 'failed to read atomic file code=%{public}d', businessError.code);
    }
    return null;
  }
}

export async function readAtomicTextAsync(path: string,
  io: AtomicJsonIo = atomicJsonIo): Promise<string | null> {
  try {
    return await io.readTextAsync(path);
  } catch (error) {
    const businessError = error as BusinessError;
    if (businessError.code !== 13900002) {
      hilog.warn(DOMAIN, TAG, 'failed to read atomic file code=%{public}d', businessError.code);
    }
    return null;
  }
}

export async function writeAtomicText(path: string, content: string,
  io: AtomicJsonIo = atomicJsonIo): Promise<void> {
  await io.writeText(path, content);
}

export function preserveCorruptFile(path: string, io: AtomicJsonIo = atomicJsonIo): void {
  const backup = `${path}.corrupt-${Date.now()}`;
  try {
    io.copyFile(path, backup);
    pruneCorruptBackups(path, io);
    hilog.warn(DOMAIN, TAG, 'preserved corrupt state file');
  } catch (error) {
    const businessError = error as BusinessError;
    hilog.warn(DOMAIN, TAG, 'failed to preserve corrupt state code=%{public}d', businessError.code);
  }
}

/**
 * 同一份状态文件只保留最近 `MAX_CORRUPT_BACKUPS` 份 `.corrupt-<timestamp>` 副本。
 * 备份名里的时间戳定宽，按文件名倒序即按时间倒序，不必逐个 stat。
 */
function pruneCorruptBackups(path: string, io: AtomicJsonIo): void {
  const separator = path.lastIndexOf('/');
  if (separator <= 0) {
    return;
  }
  const directory = path.slice(0, separator);
  const prefix = `${path.slice(separator + 1)}.corrupt-`;
  try {
    const backups: string[] = [];
    for (const name of io.listFiles(directory)) {
      if (name.startsWith(prefix)) {
        backups.push(name);
      }
    }
    if (backups.length <= MAX_CORRUPT_BACKUPS) {
      return;
    }
    backups.sort((left: string, right: string): number => {
      if (left === right) {
        return 0;
      }
      return left < right ? 1 : -1;
    });
    for (let index = MAX_CORRUPT_BACKUPS; index < backups.length; index++) {
      try {
        io.deleteFile(`${directory}/${backups[index]}`);
      } catch (error) {
        const businessError = error as BusinessError;
        hilog.warn(DOMAIN, TAG, 'failed to prune corrupt state code=%{public}d',
          businessError.code);
      }
    }
  } catch (error) {
    const businessError = error as BusinessError;
    hilog.warn(DOMAIN, TAG, 'failed to list corrupt states code=%{public}d', businessError.code);
  }
}

export function deleteAtomicFile(path: string, io: AtomicJsonIo = atomicJsonIo): void {
  try {
    if (!io.exists(path)) {
      return;
    }
    io.deleteFile(path);
  } catch (error) {
    const businessError = error as BusinessError;
    if (businessError.code !== 13900002) {
      hilog.warn(DOMAIN, TAG, 'failed to delete atomic file code=%{public}d', businessError.code);
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(errorMessage(error));
    }
  }
}
