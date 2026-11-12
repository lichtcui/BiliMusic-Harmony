import { describe, expect, it } from '@ohos/hypium';
import {
  AuthProfilePersistence,
  AuthProfileStore
} from '../main/ets/services/AuthProfileStore';
import { AuthProfile } from '../main/ets/types/MobileTypes';

class MemoryProfilePersistence implements AuthProfilePersistence {
  readonly files: Map<string, string> = new Map<string, string>();
  readonly corrupt: string[] = [];

  read(path: string): string | null {
    const value = this.files.get(path);
    return value === undefined ? null : value;
  }

  write(path: string, content: string): Promise<void> {
    this.files.set(path, content);
    return Promise.resolve();
  }

  preserveCorrupt(path: string): void {
    this.corrupt.push(path);
  }
}

function loggedInProfile(): AuthProfile {
  return {
    isLogin: true,
    mid: 12345,
    name: '测试用户',
    avatarUrl: 'https://i0.hdslb.com/bfs/face/avatar.jpg',
    vip: true
  };
}

export default function authProfileStoreTest(): void {
  describe('AuthProfileStore', (): void => {
    it('returns empty profile when cache is absent', 0, (): void => {
      const persistence = new MemoryProfilePersistence();
      const store = new AuthProfileStore('/data/profile.json', persistence);
      const profile = store.read();
      expect(profile.isLogin).assertFalse();
      expect(profile.name).assertEqual('');
    });

    it('round-trips a logged-in profile without cookies', 0, async (): Promise<void> => {
      const persistence = new MemoryProfilePersistence();
      const store = new AuthProfileStore('/data/profile.json', persistence);
      await store.write(loggedInProfile());
      const raw = persistence.files.get('/data/profile.json') ?? '';
      expect(raw.includes('SESSDATA')).assertFalse();
      expect(raw.includes('bili_jct')).assertFalse();
      const profile = store.read();
      expect(profile.isLogin).assertTrue();
      expect(profile.mid).assertEqual(12345);
      expect(profile.name).assertEqual('测试用户');
      expect(profile.vip).assertTrue();
    });

    it('falls back to empty profile and preserves corrupt json', 0, (): void => {
      const persistence = new MemoryProfilePersistence();
      persistence.files.set('/data/profile.json', '{not-json');
      const store = new AuthProfileStore('/data/profile.json', persistence);
      const profile = store.read();
      expect(profile.isLogin).assertFalse();
      expect(persistence.corrupt.length).assertEqual(1);
    });

    it('does not expose a logged-out profile as logged-in', 0, async (): Promise<void> => {
      const persistence = new MemoryProfilePersistence();
      const store = new AuthProfileStore('/data/profile.json', persistence);
      await store.write({
        isLogin: false,
        mid: 0,
        name: '',
        avatarUrl: '',
        vip: false
      });
      const profile = store.read();
      expect(profile.isLogin).assertFalse();
    });
  });
}
