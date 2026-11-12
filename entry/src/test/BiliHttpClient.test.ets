import { describe, expect, it } from '@ohos/hypium';
import {
  BiliHttpClient,
  HttpClientTransportResponse,
  HttpRequestConfig
} from '../main/ets/services/BiliHttpClient';
import { NativeError, wait } from '../main/ets/util/Errors';
import {
  DeferredTransportResponse,
  ScriptedHttpTransport,
  errorCode,
  jsonResponse,
  testCookieJar,
  textResponse,
  TestHttpUrlParser
} from './TestHttpSupport';

const TEXT_CONFIG: HttpRequestConfig = {
  timeoutMs: 1000,
  maxBytes: 1024 * 1024,
  followRedirects: false,
  allowedHosts: ['bilibili.com']
};

const API_URL = 'https://api.bilibili.com/x/test';

function clientWith(transport: ScriptedHttpTransport, delays: number[],
  maxConcurrent: number = 16, acquireTimeoutMs: number = 1000): BiliHttpClient {
  return new BiliHttpClient(testCookieJar(), transport, {
    maxConcurrent: maxConcurrent,
    acquireTimeoutMs: acquireTimeoutMs,
    urlParser: new TestHttpUrlParser(),
    retryDelayMs: async (milliseconds: number): Promise<void> => {
      delays.push(milliseconds);
    }
  });
}

export default function biliHttpClientTest(): void {
  describe('BiliHttpClient', () => {
    it('retries412WithLinearBackoffAndReturnsTheRecoveredBody', 0, async () => {
      const delays: number[] = [];
      let calls = 0;
      const transport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        calls++;
        return jsonResponse(
          `{"code":${calls < 3 ? -412 : 0},"data":{"call":${calls}}}`);
      });
      const client = clientWith(transport, delays);

      const response = await client.biliJson('/x/test');

      expect(Number(response.code)).assertEqual(0);
      expect(calls).assertEqual(3);
      expect(delays.join(',')).assertEqual('900,1800');
      expect(transport.created).assertEqual(3);
      expect(transport.destroyCount).assertEqual(3);
    });

    it('returnsTheLast412BodyAfterExhaustingRetries', 0, async () => {
      const delays: number[] = [];
      const transport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        return jsonResponse(JSON.stringify({ code: -412 }));
      });
      const client = clientWith(transport, delays);

      const response = await client.biliJson('/x/test');

      expect(Number(response.code)).assertEqual(-412);
      expect(delays.join(',')).assertEqual('900,1800');
      expect(transport.urls.length).assertEqual(3);
    });

    it('mapsMinus101ToAuthenticationRequiredWithoutRetrying', 0, async () => {
      const delays: number[] = [];
      let calls = 0;
      const transport = new ScriptedHttpTransport(async (): Promise<HttpClientTransportResponse> => {
        calls++;
        return jsonResponse(JSON.stringify({ code: -101 }));
      });
      const client = clientWith(transport, delays);
      let code = '';

      try {
        await client.biliJson('/x/test');
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('auth.required');
      expect(calls).assertEqual(1);
      expect(delays.length).assertEqual(0);
    });

    it('rejectsSuccessfulBodiesWithoutANumericApiCode', 0, async () => {
      const delays: number[] = [];
      const transport = new ScriptedHttpTransport(
        async (): Promise<HttpClientTransportResponse> => {
          return jsonResponse('{"data":{"list":[]}}');
        });
      const client = clientWith(transport, delays);
      let code = '';

      try {
        await client.biliJson('/x/test');
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('http.invalidJson');
      expect(transport.urls.length).assertEqual(3);
      expect(delays.join(',')).assertEqual('400,800');
    });

    it('retriesRetryableTransportFailuresWithLinearBackoff', 0, async () => {
      const delays: number[] = [];
      let calls = 0;
      const transport = new ScriptedHttpTransport(
        async (): Promise<HttpClientTransportResponse> => {
          calls++;
          if (calls === 1) {
            return textResponse('upstream unavailable', 503);
          }
          return jsonResponse('{"code":0,"data":{"call":2}}');
        });
      const client = clientWith(transport, delays);

      const response = await client.biliJson('/x/test');

      expect(Number(response.code)).assertEqual(0);
      expect(calls).assertEqual(2);
      expect(delays.join(',')).assertEqual('400');
    });

    it('refreshesWbiKeysAndResignsAfterMinus352', 0, async () => {
      const delays: number[] = [];
      const keyA =
        'https://i0.hdslb.com/bfs/wbi/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png';
      const keyB =
        'https://i0.hdslb.com/bfs/wbi/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png';
      let navCalls = 0;
      let targetCalls = 0;
      const transport = new ScriptedHttpTransport(
        async (targetUrl: string): Promise<HttpClientTransportResponse> => {
          if (targetUrl.includes('/x/web-interface/nav')) {
            navCalls++;
            return jsonResponse(
              `{"code":0,"data":{"wbi_img":{"img_url":"${navCalls === 1 ? keyA : keyB}",` +
              `"sub_url":"${navCalls === 1 ? keyA : keyB}"}}}`);
          }
          targetCalls++;
          return jsonResponse(JSON.stringify({ code: targetCalls === 1 ? -352 : 0 }));
        });
      const client = clientWith(transport, delays);

      const response = await client.wbiJson('/x/search', {
        searchType: 'video',
        keyword: 'music',
        page: 1,
        pageSize: 20
      });

      expect(Number(response.code)).assertEqual(0);
      expect(navCalls).assertEqual(2);
      expect(targetCalls).assertEqual(2);
      const targetUrls = transport.urlsMatching('/x/search');
      expect(targetUrls.length).assertEqual(2);
      expect(targetUrls[0] === targetUrls[1]).assertFalse();
      expect(targetUrls[0].includes('w_rid=')).assertTrue();
      expect(targetUrls[1].includes('w_rid=')).assertTrue();
    });

    it('deduplicatesForcedWbiRefreshesAndBoundsResigning', 0, async () => {
      const delays: number[] = [];
      const keyA =
        'https://i0.hdslb.com/bfs/wbi/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png';
      const keyB =
        'https://i0.hdslb.com/bfs/wbi/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png';
      let navCalls = 0;
      let targetCalls = 0;
      const pendingNav = new DeferredTransportResponse();
      const transport = new ScriptedHttpTransport(
        async (targetUrl: string): Promise<HttpClientTransportResponse> => {
          if (targetUrl.includes('/x/web-interface/nav')) {
            navCalls++;
            if (navCalls === 1) {
              return jsonResponse(
                `{"code":0,"data":{"wbi_img":{"img_url":"${keyA}","sub_url":"${keyA}"}}}`);
            }
            return pendingNav.promise;
          }
          targetCalls++;
          return jsonResponse(JSON.stringify({ code: targetCalls <= 2 ? -352 : 0 }));
        });
      const client = clientWith(transport, delays);

      const first = client.wbiJson('/x/search', {
        searchType: 'video',
        keyword: 'music',
        page: 1,
        pageSize: 20
      });
      const second = client.wbiJson('/x/search', {
        searchType: 'video',
        keyword: 'music',
        page: 1,
        pageSize: 20
      });
      let spins = 0;
      while ((navCalls < 2 || targetCalls < 2) && spins < 5000) {
        await wait(1);
        spins++;
      }
      expect(navCalls).assertEqual(2);
      pendingNav.resolve(jsonResponse(
        `{"code":0,"data":{"wbi_img":{"img_url":"${keyB}","sub_url":"${keyB}"}}}`));
      const responses = await Promise.all([first, second]);

      expect(Number(responses[0].code)).assertEqual(0);
      expect(Number(responses[1].code)).assertEqual(0);
      expect(navCalls).assertEqual(2);
      expect(targetCalls).assertEqual(4);
      expect(delays.join(',')).assertEqual('400,400');
    });

    it('timesOutQueuedRequestsAndReleasesTheSlotAfterCompletion', 0, async () => {
      const delays: number[] = [];
      const pending: DeferredTransportResponse[] = [];
      let calls = 0;
      const transport = new ScriptedHttpTransport(
        async (): Promise<HttpClientTransportResponse> => {
          calls++;
          if (calls === 1) {
            const deferred = new DeferredTransportResponse();
            pending.push(deferred);
            return deferred.promise;
          }
          return textResponse('ok');
        });
      const client = clientWith(transport, delays, 1, 30);

      const first = client.requestText(API_URL, TEXT_CONFIG);
      let spins = 0;
      while (pending.length === 0 && spins < 5000) {
        await wait(1);
        spins++;
      }
      expect(pending.length).assertEqual(1);
      let busyCode = '';
      try {
        await client.requestText(API_URL, TEXT_CONFIG);
      } catch (error) {
        busyCode = errorCode(error);
      }
      expect(busyCode).assertEqual('http.busy');

      pending[0].resolve(textResponse('first'));
      const firstResponse = await first;
      expect(firstResponse.body).assertEqual('first');

      const third = await client.requestText(API_URL, TEXT_CONFIG);
      expect(third.body).assertEqual('ok');
      expect(transport.created).assertEqual(2);
      expect(transport.destroyCount).assertEqual(2);
    });

    it('releasesTheSlotWhenCreatingTheTransportThrows', 0, async () => {
      const delays: number[] = [];
      const transport = new ScriptedHttpTransport(
        async (): Promise<HttpClientTransportResponse> => textResponse('ok'));
      transport.failCreate = true;
      const client = clientWith(transport, delays, 1, 1000);
      let code = '';

      try {
        await client.requestText(API_URL, TEXT_CONFIG);
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('http.unavailable');
      expect(transport.created).assertEqual(0);
      expect(transport.destroyCount).assertEqual(0);

      transport.failCreate = false;
      const response = await client.requestText(API_URL, TEXT_CONFIG);
      expect(response.body).assertEqual('ok');
      expect(transport.created).assertEqual(1);
      expect(transport.destroyCount).assertEqual(1);
    });

    it('blocksNonWhitelistedHostsBeforeCreatingARequest', 0, async () => {
      const delays: number[] = [];
      const transport = new ScriptedHttpTransport(
        async (): Promise<HttpClientTransportResponse> => textResponse('should not run'));
      const client = clientWith(transport, delays);
      let code = '';

      try {
        await client.requestText('https://evil.example/x', TEXT_CONFIG);
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('http.blockedUrl');
      expect(transport.created).assertEqual(0);
      expect(transport.urls.length).assertEqual(0);
    });

    it('blocksAuthoritiesWithPortsUserinfoOrTrailingDots', 0, async () => {
      const delays: number[] = [];
      const transport = new ScriptedHttpTransport(
        async (): Promise<HttpClientTransportResponse> => textResponse('should not run'));
      const client = clientWith(transport, delays);
      const targets: string[] = [
        'https://api.bilibili.com:8443/x',
        'https://user:pass@api.bilibili.com/x',
        'https://api.bilibili.com./x'
      ];

      for (const target of targets) {
        let code = '';
        try {
          await client.requestText(target, TEXT_CONFIG);
        } catch (error) {
          code = errorCode(error);
        }
        expect(code).assertEqual('http.blockedUrl');
      }
      expect(transport.created).assertEqual(0);
    });

    it('rejectsMediaDownloadsForHostsOutsideTheMediaWhitelist', 0, async () => {
      const delays: number[] = [];
      const transport = new ScriptedHttpTransport(
        async (): Promise<HttpClientTransportResponse> => textResponse('should not run'));
      const client = clientWith(transport, delays);
      let code = '';

      try {
        await client.downloadMedia('https://evil.example/audio.m4s', '/tmp/audio.m4s', 1024);
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('player.invalidMediaUrl');
      expect(transport.created).assertEqual(0);
    });

    it('rejectsBinaryResponsesLargerThanTheConfiguredLimit', 0, async () => {
      const delays: number[] = [];
      const transport = new ScriptedHttpTransport(
        async (): Promise<HttpClientTransportResponse> => {
          return {
            status: 200,
            result: new ArrayBuffer(16),
            headers: {},
            cookies: ''
          };
        });
      const client = clientWith(transport, delays);
      let code = '';

      try {
        await client.downloadMedia(
          'https://upos-sz.bilivideo.com/audio.m4s', '/tmp/audio.m4s', 4);
      } catch (error) {
        code = errorCode(error);
      }

      expect(code).assertEqual('http.responseTooLarge');
      expect(transport.destroyCount).assertEqual(1);
    });

    it('surfacesAuthenticationRequirementFromNativeErrors', 0, () => {
      const error = new NativeError('auth.required', 'login');
      expect(errorCode(error)).assertEqual('auth.required');
    });
  });
}