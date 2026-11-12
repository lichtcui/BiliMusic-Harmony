import { describe, expect, it } from '@ohos/hypium';
import { AuthService } from '../main/ets/services/AuthService';
import { BiliHttpClient, HttpClientTransportResponse, HttpUrlParser, HttpUrlParts } from '../main/ets/services/BiliHttpClient';
import { CookieJar } from '../main/ets/services/CookieJar';
import { AuthProfile } from '../main/ets/types/MobileTypes';
import { toAppError } from '../main/ets/util/Errors';
import {
  ScriptedHttpTransport,
  TestHttpUrlParser,
  errorCode,
  jsonResponse,
  testCookieJar,
  textResponse
} from './TestHttpSupport';

const GENERATE_BODY =
  '{"code":0,"data":{"qrcode_key":"qr-key","url":"https://passport.bilibili.com/qr"}}';
const WAITING_BODY = '{"code":0,"data":{"code":86100}}';
const SCANNED_BODY = '{"code":0,"data":{"code":86090}}';
const EXPIRED_BODY = '{"code":0,"data":{"code":86038}}';
const LOGIN_SUCCESS_BODY =
  '{"code":0,"data":{"code":0,"url":"https://passport.biligame.com/crossDomain?' +
  'SESSDATA=sess%20value&bili_jct=csrf&DedeUserID=42&DedeUserID__ckMd5=ck"}}';
const NAV_SUCCESS_BODY =
  '{"code":0,"data":{"isLogin":true,"mid":42,"uname":"Tester",' +
  '"face":"//i0.hdslb.com/bfs/face/a.jpg","vipStatus":{"status":1}}}';
const NAV_LOGGED_OUT_BODY = '{"code":0,"data":{"isLogin":false}}';

class ThrowingUrlParser implements HttpUrlParser {
  parse(_rawUrl: string): HttpUrlParts {
    throw new Error('malformed login redirect');
  }
}

function clientFor(transport: ScriptedHttpTransport, jar: CookieJar): BiliHttpClient {
  return new BiliHttpClient(jar, transport, {
    urlParser: new TestHttpUrlParser(),
    retryDelayMs: async (_milliseconds: number): Promise<void> => {
    }
  });
}

function serviceFor(transport: ScriptedHttpTransport, jar: CookieJar,
  parser: HttpUrlParser = new TestHttpUrlParser()): AuthService {
  return new AuthService(clientFor(transport, jar), jar, null, parser);
}

export default function authServiceTest(): void {
  describe('AuthService', () => {
    it('startsQrLoginAndReusesTheActiveSession', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return textResponse(GENERATE_BODY);
      });
      const service = serviceFor(transport, jar);

      const first = await service.startQrLogin();
      const second = await service.startQrLogin();

      expect(first.mode).assertEqual('native-overlay');
      expect(first.expiresAt > Date.now()).assertTrue();
      expect(second.expiresAt).assertEqual(first.expiresAt);
      expect(service.currentQrUrl()).assertEqual('https://passport.bilibili.com/qr');
      expect(service.currentExpiresAt()).assertEqual(first.expiresAt);
      expect(transport.urlsMatching('qrcode/generate').length).assertEqual(1);
    });

    it('joinsConcurrentQrStartRequests', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return textResponse(GENERATE_BODY);
      });
      const service = serviceFor(transport, jar);

      const first = service.startQrLogin();
      const second = service.startQrLogin();
      const results = await Promise.all([first, second]);

      expect(results[0].expiresAt).assertEqual(results[1].expiresAt);
      expect(transport.urlsMatching('qrcode/generate').length).assertEqual(1);
    });

    it('mapsWaitingAndScannedPollStages', 0, async () => {
      const jar = testCookieJar();
      let polls = 0;
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        if (targetUrl.includes('qrcode/generate')) {
          return textResponse(GENERATE_BODY);
        }
        polls++;
        return textResponse(polls === 1 ? WAITING_BODY : SCANNED_BODY);
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();

      const waiting = await service.pollQrLogin();
      const scanned = await service.pollQrLogin();

      expect(waiting.status).assertEqual('waiting');
      expect(scanned.status).assertEqual('scanned');
      expect(service.currentQrUrl()).assertEqual('https://passport.bilibili.com/qr');
    });

    it('treatsACancelledQrSessionAsExpiredWithoutNetwork', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return textResponse(GENERATE_BODY);
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();
      service.cancelQrLogin();

      const poll = await service.pollQrLogin();

      expect(poll.status).assertEqual('expired');
      expect(service.currentQrUrl()).assertEqual('');
      expect(transport.urlsMatching('qrcode/poll').length).assertEqual(0);
    });

    it('expiresTheSessionWhenTheServerReports86038', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        return textResponse(targetUrl.includes('qrcode/generate') ?
          GENERATE_BODY : EXPIRED_BODY);
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();

      const poll = await service.pollQrLogin();

      expect(poll.status).assertEqual('expired');
      expect(service.currentQrUrl()).assertEqual('');
      expect(service.currentExpiresAt()).assertEqual(0);
    });

    it('completesLoginAndStoresProfileAndCookies', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        if (targetUrl.includes('qrcode/generate')) {
          return textResponse(GENERATE_BODY);
        }
        if (targetUrl.includes('qrcode/poll')) {
          return textResponse(LOGIN_SUCCESS_BODY);
        }
        return textResponse(NAV_SUCCESS_BODY);
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();

      const poll = await service.pollQrLogin();
      const profile: AuthProfile | undefined = poll.profile;

      expect(poll.status).assertEqual('success');
      expect(profile !== undefined).assertTrue();
      if (profile === undefined) {
        return;
      }
      expect(profile.isLogin).assertTrue();
      expect(profile.mid).assertEqual(42);
      expect(profile.name).assertEqual('Tester');
      expect(profile.avatarUrl).assertEqual('https://i0.hdslb.com/bfs/face/a.jpg');
      expect(profile.vip).assertTrue();
      expect(service.status().isLogin).assertTrue();
      expect(service.status().name).assertEqual('Tester');
      expect(jar.loginCredentialPresence()).assertEqual(
        'SESSDATA=yes,bili_jct=yes,DedeUserID=yes,DedeUserID__ckMd5=yes');
      expect(service.currentQrUrl()).assertEqual('');
    });

    it('failsLoginWhenTheProfileRemainsLoggedOut', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        if (targetUrl.includes('qrcode/generate')) {
          return textResponse(GENERATE_BODY);
        }
        if (targetUrl.includes('qrcode/poll')) {
          return textResponse(LOGIN_SUCCESS_BODY);
        }
        return textResponse(NAV_LOGGED_OUT_BODY);
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();
      let code = '';

      try {
        await service.pollQrLogin();
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('auth.loginIncomplete');
      expect(service.status().isLogin).assertFalse();
    });

    it('surfacesPollFailuresForUnknownInnerCodes', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        if (targetUrl.includes('qrcode/generate')) {
          return textResponse(GENERATE_BODY);
        }
        return textResponse('{"code":0,"data":{"code":86039,"message":"bad"}}');
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();
      let code = '';

      try {
        await service.pollQrLogin();
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('auth.qrPollFailed');
    });

    it('surfacesPollFailuresForNonZeroOuterCodes', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        if (targetUrl.includes('qrcode/generate')) {
          return textResponse(GENERATE_BODY);
        }
        return textResponse('{"code":-400,"message":"bad request"}');
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();
      let code = '';

      try {
        await service.pollQrLogin();
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('auth.qrPollFailed');
    });

    it('treatsMissingInnerCodeAsRetryableInsteadOfExpired', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        if (targetUrl.includes('qrcode/generate')) {
          return textResponse(GENERATE_BODY);
        }
        return textResponse('{"code":0,"data":{"message":"gateway"}}');
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();
      let code = '';
      let retryable = false;

      try {
        await service.pollQrLogin();
      } catch (error) {
        code = errorCode(error);
        retryable = toAppError(error as Object).retryable;
      }

      expect(code).assertEqual('auth.qrPollFailed');
      expect(retryable).assertTrue();
      // 会话没有被当成 expired 清掉，下一轮仍可继续轮询。
      expect(service.currentQrUrl().length > 0).assertTrue();
      expect(service.currentExpiresAt() > Date.now()).assertTrue();
    });

    it('rejectsQrGenerateFailuresAndIncompletePayloads', 0, async () => {
      const jar = testCookieJar();
      const failing = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return textResponse('{"code":-400,"message":"denied"}');
      });
      const missing = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return textResponse('{"code":0,"data":{"qrcode_key":"","url":""}}');
      });
      let failingCode = '';
      let missingCode = '';

      try {
        await serviceFor(failing, jar).startQrLogin();
      } catch (error) {
        failingCode = errorCode(error);
      }
      try {
        await serviceFor(missing, jar).startQrLogin();
      } catch (error) {
        missingCode = errorCode(error);
      }

      expect(failingCode).assertEqual('auth.qrGenerateFailed');
      expect(missingCode).assertEqual('auth.qrGenerateFailed');
    });

    it('mapsPassportHttpAndParseFailures', 0, async () => {
      const jar = testCookieJar();
      const statusTransport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return textResponse('down', 500);
      });
      const jsonTransport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return textResponse('{not-json');
      });
      let statusCode = '';
      let jsonCode = '';

      try {
        await serviceFor(statusTransport, jar).startQrLogin();
      } catch (error) {
        statusCode = errorCode(error);
      }
      try {
        await serviceFor(jsonTransport, jar).startQrLogin();
      } catch (error) {
        jsonCode = errorCode(error);
      }

      expect(statusCode).assertEqual('auth.httpStatus');
      expect(jsonCode).assertEqual('auth.invalidResponse');
    });

    it('passesNetworkFailuresThroughTheHttpLayer', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        throw new Error('offline');
      });
      let code = '';

      try {
        await serviceFor(transport, jar).startQrLogin();
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('http.unavailable');
    });

    it('blocksLoginRedirectsToUntrustedHosts', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        if (targetUrl.includes('qrcode/generate')) {
          return textResponse(GENERATE_BODY);
        }
        if (targetUrl.includes('qrcode/poll')) {
          return textResponse(
            '{"code":0,"data":{"code":0,"url":"https://evil.example/cb?SESSDATA=x"}}');
        }
        return textResponse(NAV_SUCCESS_BODY);
      });
      const service = serviceFor(transport, jar);
      await service.startQrLogin();
      let code = '';

      try {
        await service.pollQrLogin();
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('auth.redirectBlocked');
    });

    it('mapsUnparseableLoginRedirectsToInvalid', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (targetUrl: string): Promise<HttpClientTransportResponse> => {
        if (targetUrl.includes('qrcode/generate')) {
          return textResponse(GENERATE_BODY);
        }
        return textResponse(LOGIN_SUCCESS_BODY);
      });
      const service = serviceFor(transport, jar, new ThrowingUrlParser());
      await service.startQrLogin();
      let code = '';

      try {
        await service.pollQrLogin();
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('auth.redirectInvalid');
    });

    it('clearsCredentialsAndProfileOnLogout', 0, async () => {
      const jar = testCookieJar();
      const transport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return textResponse(GENERATE_BODY);
      });
      const values: Record<string, string> = {};
      values['SESSDATA'] = 'session';
      values['bili_jct'] = 'csrf';
      values['DedeUserID'] = '42';
      values['DedeUserID__ckMd5'] = 'ck';
      jar.setDomainCookies('bilibili.com', values);
      const service = serviceFor(transport, jar);

      const profile = await service.logout();

      expect(profile.isLogin).assertFalse();
      expect(jar.loginCredentialPresence()).assertEqual(
        'SESSDATA=no,bili_jct=no,DedeUserID=no,DedeUserID__ckMd5=no');
      expect(service.hasLoginCredentials()).assertFalse();
    });
  });
}