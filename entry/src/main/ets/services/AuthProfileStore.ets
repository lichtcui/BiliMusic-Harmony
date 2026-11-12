import { hilog } from '@kit.PerformanceAnalysisKit';
import { AuthProfile, emptyAuthProfile } from '../types/MobileTypes';
import { preserveCorruptFile, readAtomicText, writeAtomicText } from '../util/AtomicJson';

const DOMAIN = 0x424D;
const TAG = 'WispMusicAuthProfile';
const PROFILE_STORAGE_VERSION = 1;

/**
 * 账号资料的本地快照：只存页头需要的公开字段，不存 Cookie、二维码中间值或签名参数。
 * 启动时先用它渲染「我的」页头，`/x/web-interface/nav` 再在后台刷新。
 */
export interface AuthProfilePersistence {
  read(path: string): string | null;
  write(path: string, content: string): Promise<void>;
  preserveCorrupt(path: string): void;
}

class AtomicAuthProfilePersistence implements AuthProfilePersistence {
  read(path: string): string | null {
    return readAtomicText(path);
  }

  write(path: string, content: string): Promise<void> {
    return writeAtomicText(path, content);
  }

  preserveCorrupt(path: string): void {
    preserveCorruptFile(path);
  }
}

export class AuthProfileStore {
  private readonly path: string;
  private readonly persistence: AuthProfilePersistence;

  constructor(path: string, persistence: AuthProfilePersistence = new AtomicAuthProfilePersistence()) {
    this.path = path;
    this.persistence = persistence;
  }

  read(): AuthProfile {
    const text = this.persistence.read(this.path);
    if (text === null) {
      return emptyAuthProfile();
    }
    try {
      const parsed = JSON.parse(text) as Record<string, Object>;
      if (numberValue(parsed.version) !== PROFILE_STORAGE_VERSION) {
        return emptyAuthProfile();
      }
      return normalizeProfile(parsed.profile);
    } catch (error) {
      this.persistence.preserveCorrupt(this.path);
      hilog.warn(DOMAIN, TAG, 'auth profile cache is not valid JSON; falling back to empty profile');
      return emptyAuthProfile();
    }
  }

  write(profile: AuthProfile): Promise<void> {
    const payload = JSON.stringify({
      version: PROFILE_STORAGE_VERSION,
      profile: normalizeProfile(profile)
    });
    return this.persistence.write(this.path, payload).catch((error: Object): void => {
      hilog.warn(DOMAIN, TAG, 'auth profile cache write failed');
    });
  }

  clear(): Promise<void> {
    return this.write(emptyAuthProfile());
  }
}

function normalizeProfile(value: Object): AuthProfile {
  if (value === null || value === undefined) {
    return emptyAuthProfile();
  }
  const record = value as Record<string, Object>;
  if (record.isLogin !== true) {
    return emptyAuthProfile();
  }
  return {
    isLogin: true,
    mid: Math.max(0, Math.floor(numberValue(record.mid))),
    name: stringValue(record.name).trim(),
    avatarUrl: stringValue(record.avatarUrl).trim(),
    vip: record.vip === true
  };
}

function numberValue(value: Object | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return 0;
  }
  return value;
}

function stringValue(value: Object | undefined): string {
  return typeof value === 'string' ? value : '';
}
