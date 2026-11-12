import { describe, expect, it } from '@ohos/hypium';
import {
  CookieJar,
  CookiePersistence,
  CookieUrlParser,
  ParsedUrl
} from '../main/ets/services/CookieJar';

class MemoryCookiePersistence implements CookiePersistence {
  content: string | null = null;
  writeCount: number = 0;
  preserveCount: number = 0;

  read(_path: string): string | null {
    return this.content;
  }

  async write(_path: string, content: string): Promise<void> {
    this.writeCount++;
    this.content = content;
  }

  preserveCorrupt(_path: string): void {
    this.preserveCount++;
  }
}

class TestCookieUrlParser implements CookieUrlParser {
  parse(rawUrl: string): ParsedUrl {
    const schemeEnd = rawUrl.indexOf('://');
    const pathStart = rawUrl.indexOf('/', schemeEnd + 3);
    const hostEnd = pathStart >= 0 ? pathStart : rawUrl.length;
    const pathEnd = rawUrl.indexOf('?', pathStart >= 0 ? pathStart : hostEnd);
    return {
      protocol: schemeEnd >= 0 ? rawUrl.slice(0, schemeEnd + 1) : '',
      hostname: rawUrl.slice(schemeEnd + 3, hostEnd).toLowerCase(),
      pathname: pathStart >= 0 ? rawUrl.slice(pathStart, pathEnd >= 0 ? pathEnd : rawUrl.length) : '/'
    };
  }
}

function jarWith(persistence: MemoryCookiePersistence): CookieJar {
  return new CookieJar('memory://cookies', persistence, new TestCookieUrlParser());
}

export default function cookieJarTest(): void {
  describe('CookieJar', () => {
    it('parsesMultipleSetCookieHeadersWithHttpOnly', 0, async () => {
      const persistence = new MemoryCookiePersistence();
      const jar = jarWith(persistence);
      const headers: Record<string, Object> = {};
      headers['set-cookie'] = [
        'SESSDATA=session-token; Path=/; Secure; HttpOnly',
        'bili_jct=csrf-token; Path=/; HttpOnly'
      ];

      const changed = await jar.setCookieHeaders(headers, 'https://api.bilibili.com/x/test');

      expect(changed).assertTrue();
      expect(persistence.writeCount).assertEqual(1);
      expect(jar.headerFor('https://api.bilibili.com/x/test')).assertEqual(
        'SESSDATA=session-token; bili_jct=csrf-token'
      );
      expect(jar.headerFor('http://api.bilibili.com/x/test')).assertEqual('bili_jct=csrf-token');
      expect(jar.loginCredentialPresence()).assertEqual(
        'SESSDATA=yes,bili_jct=yes,DedeUserID=no,DedeUserID__ckMd5=no'
      );
    });

    it('keepsExpiresCommasInCombinedSetCookieHeader', 0, async () => {
      const persistence = new MemoryCookiePersistence();
      const jar = jarWith(persistence);
      const headers: Record<string, Object> = {};
      headers['Set-Cookie'] =
        'SESSDATA=future; Path=/; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Secure; HttpOnly, ' +
        'theme=dark; Path=/';

      expect(await jar.setCookieHeaders(headers, 'https://api.bilibili.com/x/test')).assertTrue();
      expect(jar.headerFor('https://api.bilibili.com/x/test')).assertEqual('SESSDATA=future; theme=dark');
      expect(jar.headerFor('http://api.bilibili.com/x/test')).assertEqual('theme=dark');
    });

    it('removesExpiredCookies', 0, async () => {
      const persistence = new MemoryCookiePersistence();
      const jar = jarWith(persistence);
      const initial: Record<string, Object> = {};
      initial['set-cookie'] = 'SESSDATA=future; Path=/; Max-Age=3600';
      await jar.setCookieHeaders(initial, 'https://api.bilibili.com/x/test');

      const expired: Record<string, Object> = {};
      expired['set-cookie'] = 'SESSDATA=deleted; Path=/; Max-Age=0';
      await jar.setCookieHeaders(expired, 'https://api.bilibili.com/x/test');

      expect(jar.headerFor('https://api.bilibili.com/x/test')).assertEqual('');
      expect(jar.loginCredentialPresence()).assertEqual(
        'SESSDATA=no,bili_jct=no,DedeUserID=no,DedeUserID__ckMd5=no'
      );
    });

    it('clearsBilibiliDomainFamiliesOnly', 0, async () => {
      const persistence = new MemoryCookiePersistence();
      const jar = jarWith(persistence);
      const bilibiliHeaders: Record<string, Object> = {};
      bilibiliHeaders['set-cookie'] = 'api_cookie=one; Domain=.bilibili.com; Path=/';
      await jar.setCookieHeaders(bilibiliHeaders, 'https://api.bilibili.com/x/test');
      const biligameHeaders: Record<string, Object> = {};
      biligameHeaders['set-cookie'] = 'game_cookie=two; Domain=.biligame.com; Path=/';
      await jar.setCookieHeaders(biligameHeaders, 'https://www.biligame.com/x/test');
      const unrelatedHeaders: Record<string, Object> = {};
      unrelatedHeaders['set-cookie'] = 'unrelated=three; Path=/';
      await jar.setCookieHeaders(unrelatedHeaders, 'https://example.com/x/test');

      await jar.clearBilibili();

      expect(jar.headerFor('https://api.bilibili.com/x/test')).assertEqual('');
      expect(jar.headerFor('https://www.biligame.com/x/test')).assertEqual('');
      expect(jar.headerFor('https://example.com/x/test')).assertEqual('unrelated=three');
    });

    it('rejectsPublicSuffixDomainAttributes', 0, async () => {
      const persistence = new MemoryCookiePersistence();
      const jar = jarWith(persistence);
      const headers: Record<string, Object> = {};
      headers['set-cookie'] = 'evil=one; Domain=com; Path=/';
      expect(await jar.setCookieHeaders(headers, 'https://api.bilibili.com/x/test')).assertFalse();

      const foreign: Record<string, Object> = {};
      foreign['set-cookie'] = 'evil=two; Domain=example.com; Path=/';
      expect(await jar.setCookieHeaders(foreign, 'https://api.bilibili.com/x/test')).assertFalse();

      expect(jar.headerFor('https://api.bilibili.com/x/test')).assertEqual('');
      expect(persistence.writeCount).assertEqual(0);
    });

    it('restoresPersistedHttpOnlyCookies', 0, async () => {
      const persistence = new MemoryCookiePersistence();
      const jar = jarWith(persistence);
      const headers: Record<string, Object> = {};
      headers['set-cookie'] = 'DedeUserID=12345; Path=/; HttpOnly';
      await jar.setCookieHeaders(headers, 'https://api.bilibili.com/x/test');

      const restored = jarWith(persistence);
      expect(restored.headerFor('https://api.bilibili.com/x/test')).assertEqual('DedeUserID=12345');
      expect(restored.loginCredentialPresence()).assertEqual(
        'SESSDATA=no,bili_jct=no,DedeUserID=yes,DedeUserID__ckMd5=no'
      );
      expect(persistence.preserveCount).assertEqual(0);
    });
  });
}
