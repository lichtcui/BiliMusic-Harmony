import { NativeError } from '../main/ets/util/Errors';
import {
  HttpClientTransport,
  HttpClientTransportOptions,
  HttpClientTransportRequest,
  HttpClientTransportResponse,
  HttpUrlParser,
  HttpUrlParts
} from '../main/ets/services/BiliHttpClient';
import {
  CookieJar,
  CookiePersistence,
  CookieUrlParser,
  ParsedUrl
} from '../main/ets/services/CookieJar';

export type TestHttpHandler =
  (targetUrl: string, options: HttpClientTransportOptions) => Promise<HttpClientTransportResponse>;

export class TestCookiePersistence implements CookiePersistence {
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

export class TestCookieUrlParser implements CookieUrlParser {
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

export function testCookieJar(): CookieJar {
  return new CookieJar('memory://cookies', new TestCookiePersistence(), new TestCookieUrlParser());
}

/** 单元测试宿主没有完整的 ArkTS URL 实现，用与生产一致的解析结果替代。 */
export class TestHttpUrlParser implements HttpUrlParser {
  parse(rawUrl: string): HttpUrlParts {
    const schemeEnd = rawUrl.indexOf('://');
    const pathStart = rawUrl.indexOf('/', schemeEnd + 3);
    const hostEnd = pathStart >= 0 ? pathStart : rawUrl.length;
    const pathEnd = rawUrl.indexOf('?', pathStart >= 0 ? pathStart : hostEnd);
    return {
      protocol: schemeEnd >= 0 ? rawUrl.slice(0, schemeEnd + 1) : '',
      hostname: rawUrl.slice(schemeEnd + 3, hostEnd).toLowerCase(),
      pathname: pathStart >= 0 ? rawUrl.slice(pathStart, pathEnd >= 0 ? pathEnd : rawUrl.length) : '/',
      search: pathEnd >= 0 ? rawUrl.slice(pathEnd) : ''
    };
  }
}

export function textResponse(body: string, status: number = 200): HttpClientTransportResponse {
  return {
    status: status,
    result: body,
    headers: {},
    cookies: ''
  };
}

export function jsonResponse(serializedBody: string,
  status: number = 200): HttpClientTransportResponse {
  return textResponse(serializedBody, status);
}

export class DeferredTransportResponse {
  readonly promise: Promise<HttpClientTransportResponse>;
  private resolver: ((value: HttpClientTransportResponse) => void) | null = null;

  constructor() {
    this.promise = new Promise<HttpClientTransportResponse>(
      (resolve: (value: HttpClientTransportResponse) => void): void => {
        this.resolver = resolve;
      });
  }

  resolve(value: HttpClientTransportResponse): void {
    const resolver = this.resolver;
    if (resolver !== null) {
      resolver(value);
    }
  }
}

class ScriptedRequest implements HttpClientTransportRequest {
  private readonly owner: ScriptedHttpTransport;

  constructor(owner: ScriptedHttpTransport) {
    this.owner = owner;
  }

  request(targetUrl: string, options: HttpClientTransportOptions): Promise<HttpClientTransportResponse> {
    return this.owner.dispatch(targetUrl, options);
  }

  destroy(): void {
    this.owner.destroyCount++;
  }
}

export class ScriptedHttpTransport implements HttpClientTransport {
  handler: TestHttpHandler;
  readonly urls: string[] = [];
  created: number = 0;
  destroyCount: number = 0;
  failCreate: boolean = false;

  constructor(handler: TestHttpHandler) {
    this.handler = handler;
  }

  create(): HttpClientTransportRequest {
    if (this.failCreate) {
      throw new Error('simulated createHttp failure');
    }
    this.created++;
    return new ScriptedRequest(this);
  }

  dispatch(targetUrl: string, options: HttpClientTransportOptions): Promise<HttpClientTransportResponse> {
    this.urls.push(targetUrl);
    return this.handler(targetUrl, options);
  }

  urlsMatching(fragment: string): string[] {
    return this.urls.filter((candidate: string): boolean => candidate.includes(fragment));
  }
}

export function errorCode(error: Object): string {
  return error instanceof NativeError ? error.appError.code : '';
}