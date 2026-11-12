import { describe, expect, it } from '@ohos/hypium';
import { CatalogFeed, MobileTrack } from '../main/ets/types/MobileTypes';
import { describeFeedProbe, describeFeedProbeError } from '../main/ets/util/FeedProbe';
import { NativeError } from '../main/ets/util/Errors';

function fixtureTrack(index: number): MobileTrack {
  return {
    key: `probe-${index}`,
    bvid: `BV${index}`,
    aid: index,
    cid: index,
    title: `Fixture ${index}`,
    artist: 'Probe',
    coverUrl: 'https://example.invalid/cover.jpg',
    duration: 120,
    playCount: 1
  };
}

function fixtureFeed(itemCount: number, page: number, hasMore: boolean): CatalogFeed {
  const items: MobileTrack[] = [];
  for (let index = 0; index < itemCount; index++) {
    items.push(fixtureTrack(index));
  }
  return {
    items: items,
    page: page,
    hasMore: hasMore
  };
}

export default function feedProbeTest(): void {
  describe('FeedProbe', () => {
    it('reportsCountsWithoutLeakingMediaUrls', 0, () => {
      const line = describeFeedProbe('discover', fixtureFeed(20, 1, true));

      expect(line.indexOf('discover:')).assertEqual(0);
      expect(line.indexOf('items=20') >= 0).assertTrue();
      expect(line.indexOf('page=1') >= 0).assertTrue();
      expect(line.indexOf('hasMore=true') >= 0).assertTrue();
      expect(line.indexOf('http') < 0).assertTrue();
      expect(line.indexOf('example.invalid') < 0).assertTrue();
    });

    it('reportsAnEmptyFeedAsOkWithZeroItems', 0, () => {
      const line = describeFeedProbe('recommend', fixtureFeed(0, 1, false));

      expect(line.indexOf('recommend:')).assertEqual(0);
      expect(line.indexOf('items=0') >= 0).assertTrue();
      expect(line.indexOf('hasMore=false') >= 0).assertTrue();
    });

    it('normalizesOutOfRangePageNumbers', 0, () => {
      const line = describeFeedProbe('discover', fixtureFeed(3, 0, false));

      expect(line.indexOf('page=1') >= 0).assertTrue();
    });

    it('reportsTheAppErrorCodeOnFailure', 0, () => {
      const line = describeFeedProbeError('discover', new NativeError('catalog.discoverFailed'));

      expect(line).assertEqual('discover: failed code=catalog.discoverFailed');
    });

    it('fallsBackToTheSharedErrorCodeForUnknownFailures', 0, () => {
      const line = describeFeedProbeError('recommend', new Error('boom'));

      expect(line.indexOf('recommend: failed code=')).assertEqual(0);
      expect(line.indexOf('code=native.error') >= 0).assertTrue();
    });

    it('fallsBackToAStableTokenForBlankKinds', 0, () => {
      const line = describeFeedProbe('   ', fixtureFeed(1, 1, false));

      expect(line.indexOf('feed:') >= 0).assertTrue();
    });
  });
}
