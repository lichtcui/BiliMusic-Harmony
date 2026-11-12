import { describe, expect, it } from '@ohos/hypium';
import { SearchGateway, SearchStore } from '../main/ets/state/SearchStore';
import { CatalogSearchResult, MobileTrack } from '../main/ets/types/MobileTypes';
import { NativeError, wait } from '../main/ets/util/Errors';

class PendingSearchCall {
  readonly keyword: string;
  readonly page: number;
  readonly pageSize: number;
  readonly promise: Promise<CatalogSearchResult>;
  private resolveCallback: ((result: CatalogSearchResult) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor(keyword: string, page: number, pageSize: number) {
    this.keyword = keyword;
    this.page = page;
    this.pageSize = pageSize;
    this.promise = new Promise<CatalogSearchResult>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: CatalogSearchResult): void {
    const callback = this.resolveCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(result);
    }
  }

  reject(error: Object): void {
    const callback = this.rejectCallback;
    this.resolveCallback = null;
    this.rejectCallback = null;
    if (callback !== null) {
      callback(error);
    }
  }
}

class QueuedSearchGateway implements SearchGateway {
  readonly requests: PendingSearchCall[] = [];

  search(keyword: string, page: number, pageSize: number): Promise<CatalogSearchResult> {
    const request = new PendingSearchCall(keyword, page, pageSize);
    this.requests.push(request);
    return request.promise;
  }
}

function searchTrack(label: string): MobileTrack {
  return {
    key: `track:${label}`,
    bvid: `BV${label}`,
    aid: 1,
    cid: 1,
    title: label,
    artist: 'Artist',
    coverUrl: '',
    duration: 180,
    playCount: 1
  };
}

function searchResult(keyword: string, page: number, items: MobileTrack[], hasMore: boolean,
  total: number): CatalogSearchResult {
  return {
    items: items,
    page: page,
    hasMore: hasMore,
    total: total,
    keyword: keyword
  };
}

export default function searchStoreTest(): void {
  describe('SearchStore', () => {
    it('loadsFirstPageAndDeduplicatesTheSameRequest', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);

      const blank = store.search('   ');
      await blank;
      expect(gateway.requests.length).assertEqual(0);
      expect(store.snapshot.status).assertEqual('idle');

      const first = store.search('alpha');
      expect(gateway.requests.length).assertEqual(1);
      expect(gateway.requests[0].keyword).assertEqual('alpha');
      expect(gateway.requests[0].page).assertEqual(1);
      expect(gateway.requests[0].pageSize).assertEqual(20);
      expect(store.snapshot.status).assertEqual('searching');

      const duplicate = store.search('alpha');
      expect(gateway.requests.length).assertEqual(1);
      gateway.requests[0].resolve(searchResult('alpha', 1, [searchTrack('a')], true, 2));
      await Promise.all([first, duplicate]);

      expect(store.snapshot.status).assertEqual('success');
      expect(store.snapshot.page).assertEqual(1);
      expect(store.snapshot.items[0].key).assertEqual('track:a');

      await store.search('alpha');
      expect(gateway.requests.length).assertEqual(1);
    });

    it('loadsSecondPageOnceAndAppendsResults', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);
      const first = store.search('alpha');
      gateway.requests[0].resolve(searchResult('alpha', 1, [searchTrack('a')], true, 2));
      await first;

      const second = store.loadMore();
      const duplicate = store.loadMore();
      expect(gateway.requests.length).assertEqual(2);
      expect(gateway.requests[1].page).assertEqual(2);
      expect(store.snapshot.status).assertEqual('loadingMore');

      gateway.requests[1].resolve(searchResult('alpha', 2, [searchTrack('b')], false, 2));
      await Promise.all([second, duplicate]);

      expect(store.snapshot.status).assertEqual('success');
      expect(store.snapshot.page).assertEqual(2);
      expect(store.snapshot.items.length).assertEqual(2);
      expect(store.snapshot.items[1].key).assertEqual('track:b');
      expect(store.snapshot.hasMore).assertFalse();

      await store.loadMore();
      expect(gateway.requests.length).assertEqual(2);
    });

    it('exposesEmptyResultsWithoutTreatingThemAsErrors', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);

      const pending = store.search('missing');
      gateway.requests[0].resolve(searchResult('missing', 1, [], false, 0));
      await pending;

      expect(store.snapshot.status).assertEqual('empty');
      expect(store.snapshot.items.length).assertEqual(0);
      expect(store.snapshot.error === null).assertTrue();
      expect(store.snapshot.page).assertEqual(1);
    });

    it('keepsPageResultsAndRetriesTheFailedPage', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);
      const first = store.search('alpha');
      gateway.requests[0].resolve(searchResult('alpha', 1, [searchTrack('a')], true, 2));
      await first;

      const second = store.loadMore();
      gateway.requests[1].reject(new NativeError('catalog.searchFailed', 'network failed', true));
      await second;

      expect(store.snapshot.status).assertEqual('error');
      expect(store.snapshot.items.length).assertEqual(1);
      expect(store.snapshot.page).assertEqual(1);
      expect(store.snapshot.error?.code).assertEqual('catalog.searchFailed');
      expect(store.snapshot.canRetry).assertTrue();

      const retry = store.retry();
      expect(store.snapshot.status).assertEqual('loadingMore');
      expect(gateway.requests.length).assertEqual(3);
      expect(gateway.requests[2].page).assertEqual(2);
      gateway.requests[2].resolve(searchResult('alpha', 2, [searchTrack('b')], false, 2));
      await retry;

      expect(store.snapshot.status).assertEqual('success');
      expect(store.snapshot.page).assertEqual(2);
      expect(store.snapshot.items.length).assertEqual(2);
      expect(store.snapshot.error === null).assertTrue();
    });

    it('preservesCollectionMetadataWhenCloningResults', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);
      const collection = searchTrack('collection');
      collection.collectionSize = 50;
      collection.collectionTotalDuration = 12345;

      const pending = store.search('alpha');
      gateway.requests[0].resolve(searchResult('alpha', 1, [collection], false, 1));
      await pending;

      expect(store.snapshot.items[0].collectionSize).assertEqual(50);
      expect(store.snapshot.items[0].collectionTotalDuration).assertEqual(12345);
      expect(store.snapshot.items[0].duration).assertEqual(180);
    });

    it('clearsResultsErrorsAndInflightResponses', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);
      const pending = store.search('alpha');

      store.clear();
      gateway.requests[0].resolve(searchResult('alpha', 1, [searchTrack('a')], false, 1));
      await pending;

      expect(store.snapshot.status).assertEqual('idle');
      expect(store.snapshot.keyword).assertEqual('');
      expect(store.snapshot.items.length).assertEqual(0);
      expect(store.snapshot.page).assertEqual(0);
      expect(store.snapshot.error === null).assertTrue();
    });

    it('ignoresAnOlderKeywordResponseAfterANewSubmission', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);
      const oldRequest = store.search('old');
      const oldCall = gateway.requests[0];
      const newRequest = store.search('new');
      const newCall = gateway.requests[1];

      newCall.resolve(searchResult('new', 1, [searchTrack('new')], false, 1));
      await newRequest;
      oldCall.resolve(searchResult('old', 1, [searchTrack('old')], false, 1));
      await oldRequest;
      await wait(0);

      expect(store.snapshot.keyword).assertEqual('new');
      expect(store.snapshot.items.length).assertEqual(1);
      expect(store.snapshot.items[0].key).assertEqual('track:new');
      expect(store.snapshot.status).assertEqual('success');
    });

    it('keepsTheNewResultWhenAnOlderKeywordFails', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);
      const oldRequest = store.search('old');
      const oldCall = gateway.requests[0];
      const newRequest = store.search('new');
      const newCall = gateway.requests[1];

      newCall.resolve(searchResult('new', 1, [searchTrack('new')], false, 1));
      await newRequest;
      oldCall.reject(new NativeError('catalog.searchFailed', 'stale failure', true));
      await oldRequest;

      expect(store.snapshot.keyword).assertEqual('new');
      expect(store.snapshot.status).assertEqual('success');
      expect(store.snapshot.error === null).assertTrue();
      expect(store.snapshot.items[0].key).assertEqual('track:new');
    });

    it('doesNotMixPreviousKeywordResultsIntoANewQueryError', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);
      const first = store.search('old');
      gateway.requests[0].resolve(searchResult('old', 1, [searchTrack('old')], true, 2));
      await first;

      const next = store.search('new');
      expect(store.snapshot.status).assertEqual('searching');
      expect(store.snapshot.keyword).assertEqual('new');
      expect(store.snapshot.items.length).assertEqual(0);
      expect(store.snapshot.page).assertEqual(0);

      gateway.requests[1].reject(new NativeError('catalog.searchFailed', 'network failed', true));
      await next;

      expect(store.snapshot.status).assertEqual('error');
      expect(store.snapshot.keyword).assertEqual('new');
      expect(store.snapshot.items.length).assertEqual(0);
      expect(store.snapshot.page).assertEqual(0);
      expect(store.snapshot.canRetry).assertTrue();
    });

    it('ignoresLateResponsesAndRequestsAfterDisposal', 0, async () => {
      const gateway = new QueuedSearchGateway();
      const store = new SearchStore(gateway);
      const pending = store.search('alpha');
      expect(gateway.requests.length).assertEqual(1);

      store.dispose();
      gateway.requests[0].resolve(searchResult('alpha', 1, [searchTrack('a')], true, 1));
      await pending;

      await store.search('beta');
      await store.loadMore();
      await store.retry();
      store.clear();
      expect(gateway.requests.length).assertEqual(1);
      expect(store.snapshot.status).assertEqual('searching');
      expect(store.snapshot.keyword).assertEqual('alpha');
      expect(store.snapshot.items.length).assertEqual(0);
    });
  });
}
