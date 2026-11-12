import { describe, expect, it } from '@ohos/hypium';
import {
  AtomicJsonIo,
  deleteAtomicFile,
  preserveCorruptFile,
  readAtomicText,
  readAtomicTextAsync,
  writeAtomicText
} from '../main/ets/util/AtomicJson';

const DIRECTORY = '/memory/state';
const STATE_PATH = `${DIRECTORY}/state.json`;

class MissingFileError extends Error {
  readonly code: number = 13900002;
}

class MemoryAtomicJsonIo implements AtomicJsonIo {
  files: Map<string, string> = new Map<string, string>();
  failWrite: Error | null = null;
  writeCount: number = 0;
  asyncReadCount: number = 0;

  readText(path: string): string {
    const content = this.files.get(path);
    if (content === undefined) {
      throw new MissingFileError('missing atomic file');
    }
    return content;
  }

  async readTextAsync(path: string): Promise<string> {
    this.asyncReadCount++;
    return this.readText(path);
  }

  async writeText(path: string, content: string): Promise<void> {
    this.writeCount++;
    if (this.failWrite !== null) {
      throw this.failWrite;
    }
    this.files.set(path, content);
  }

  copyFile(source: string, target: string): void {
    const content = this.files.get(source);
    if (content === undefined) {
      throw new MissingFileError('missing source file');
    }
    this.files.set(target, content);
  }

  listFiles(directory: string): string[] {
    const names: string[] = [];
    const prefix = `${directory}/`;
    this.files.forEach((_content: string, path: string): void => {
      if (path.startsWith(prefix)) {
        names.push(path.slice(prefix.length));
      }
    });
    return names;
  }

  deleteFile(path: string): void {
    if (!this.files.has(path)) {
      throw new MissingFileError('missing file to delete');
    }
    this.files.delete(path);
  }

  exists(path: string): boolean {
    return this.files.has(path);
  }
}

function backupNames(io: MemoryAtomicJsonIo): string[] {
  const names: string[] = [];
  for (const name of io.listFiles(DIRECTORY)) {
    if (name.startsWith('state.json.corrupt-')) {
      names.push(name);
    }
  }
  names.sort();
  return names;
}

function nextTimestamp(): void {
  const startedAt = Date.now();
  while (Date.now() === startedAt) {
    // 备份名以毫秒时间戳区分，等下一毫秒避免同名副本互相覆盖。
  }
}

export default function atomicJsonTest(): void {
  describe('AtomicJson', () => {
    it('readsAMissingFileAsNull', 0, () => {
      const io = new MemoryAtomicJsonIo();
      expect(readAtomicText(STATE_PATH, io) === null).assertTrue();
    });

    it('readsTheSameContentAsynchronously', 0, async () => {
      const io = new MemoryAtomicJsonIo();
      await writeAtomicText(STATE_PATH, '{"version":3}', io);
      expect(await readAtomicTextAsync(STATE_PATH, io)).assertEqual('{"version":3}');
      expect(io.asyncReadCount).assertEqual(1);
      expect(await readAtomicTextAsync(`${DIRECTORY}/missing.json`, io) === null).assertTrue();
    });

    it('writesAndReplacesContent', 0, async () => {
      const io = new MemoryAtomicJsonIo();
      await writeAtomicText(STATE_PATH, '{"version":1}', io);
      expect(readAtomicText(STATE_PATH, io)).assertEqual('{"version":1}');
      await writeAtomicText(STATE_PATH, '{"version":2}', io);
      expect(readAtomicText(STATE_PATH, io)).assertEqual('{"version":2}');
      expect(backupNames(io).length).assertEqual(0);
    });

    it('propagatesWriteFailuresWithoutReplacingContent', 0, async () => {
      const io = new MemoryAtomicJsonIo();
      await writeAtomicText(STATE_PATH, '{"version":1}', io);
      io.failWrite = new Error('disk full');

      let message = '';
      try {
        await writeAtomicText(STATE_PATH, '{"version":2}', io);
      } catch (error) {
        message = (error as Error).message;
      }

      expect(message).assertEqual('disk full');
      expect(readAtomicText(STATE_PATH, io)).assertEqual('{"version":1}');
      expect(io.writeCount).assertEqual(2);
    });

    it('deletesTheFileAndIgnoresAMissingTarget', 0, async () => {
      const io = new MemoryAtomicJsonIo();
      await writeAtomicText(STATE_PATH, '{}', io);
      deleteAtomicFile(STATE_PATH, io);
      expect(readAtomicText(STATE_PATH, io) === null).assertTrue();

      let threw = false;
      try {
        deleteAtomicFile(STATE_PATH, io);
      } catch (_error) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('keepsOnlyTheNewestTwoCorruptBackups', 0, async () => {
      const io = new MemoryAtomicJsonIo();
      await writeAtomicText(STATE_PATH, '{"corrupt":0}', io);
      for (let index = 0; index < 4; index++) {
        nextTimestamp();
        io.files.set(STATE_PATH, `{"corrupt":${index}}`);
        preserveCorruptFile(STATE_PATH, io);
        nextTimestamp();
      }

      const names = backupNames(io);
      expect(names.length).assertEqual(2);
      const newest = names[names.length - 1];
      expect(io.files.get(`${DIRECTORY}/${newest}`)).assertEqual('{"corrupt":3}');
      let oldestRemoved = true;
      for (const name of names) {
        if (io.files.get(`${DIRECTORY}/${name}`) === '{"corrupt":0}') {
          oldestRemoved = false;
        }
      }
      expect(oldestRemoved).assertTrue();
    });
  });
}
