import { describe, expect, it } from '@ohos/hypium';
import { MobileTrack } from '../main/ets/types/MobileTypes';
import {
  TRACK_LIST_PAGE_SIZE,
  nextTrackPage,
  queueRowKey,
  queueRowKeys,
  visibleCountForIndex,
  visibleTrackCount
} from '../main/ets/components/native/TrackListPaging';

function track(key: string): MobileTrack {
  return {
    key: key,
    bvid: key,
    aid: 1,
    cid: 1,
    title: key,
    artist: '',
    coverUrl: '',
    duration: 1,
    playCount: 0
  };
}

export default function trackListPagingTest(): void {
  describe('TrackListPaging', () => {
    it('clampsTheVisibleRowCountToTheRealTotal', 0, () => {
      expect(visibleTrackCount(TRACK_LIST_PAGE_SIZE, 500)).assertEqual(TRACK_LIST_PAGE_SIZE);
      expect(visibleTrackCount(250, 120)).assertEqual(120);
      expect(visibleTrackCount(0, 0)).assertEqual(0);
      expect(visibleTrackCount(-10, 30)).assertEqual(0);
      expect(visibleTrackCount(Number.NaN, 30)).assertEqual(0);
      expect(visibleTrackCount(20, -3)).assertEqual(0);
    });

    it('appendsOnePageAtATimeAndStopsAtTheTotal', 0, () => {
      expect(nextTrackPage(TRACK_LIST_PAGE_SIZE, 250)).assertEqual(200);
      expect(nextTrackPage(200, 250)).assertEqual(250);
      expect(nextTrackPage(250, 250)).assertEqual(250);
      expect(nextTrackPage(0, 0)).assertEqual(0);
      // 非法页长退回默认 100，而不是 0 或 NaN。
      expect(nextTrackPage(0, 30, 0)).assertEqual(30);
      expect(nextTrackPage(0, 30, Number.NaN)).assertEqual(30);
    });

    it('rendersEnoughRowsToRevealTheCurrentOne', 0, () => {
      expect(visibleCountForIndex(0, 500)).assertEqual(TRACK_LIST_PAGE_SIZE);
      expect(visibleCountForIndex(99, 500)).assertEqual(TRACK_LIST_PAGE_SIZE);
      expect(visibleCountForIndex(100, 500)).assertEqual(101);
      expect(visibleCountForIndex(250, 500)).assertEqual(251);
      expect(visibleCountForIndex(499, 500)).assertEqual(500);
      expect(visibleCountForIndex(600, 500)).assertEqual(500);
      expect(visibleCountForIndex(-1, 500)).assertEqual(TRACK_LIST_PAGE_SIZE);
      expect(visibleCountForIndex(Number.NaN, 500)).assertEqual(TRACK_LIST_PAGE_SIZE);
      expect(visibleCountForIndex(250, 50)).assertEqual(50);
      expect(visibleCountForIndex(250, 0)).assertEqual(0);
      // 非法页长退回默认一页，而不是返回 0 或 NaN。
      expect(visibleCountForIndex(250, 500, 0)).assertEqual(251);
    });

    it('keepsUniqueKeysAndNumbersOnlyTheDuplicates', 0, () => {
      const queue: MobileTrack[] = [track('a'), track('b'), track('a'), track('c'), track('a')];

      expect(queueRowKey(queue[0], 0, queue)).assertEqual('a');
      expect(queueRowKey(queue[1], 1, queue)).assertEqual('b');
      expect(queueRowKey(queue[2], 2, queue)).assertEqual('a#1');
      expect(queueRowKey(queue[3], 3, queue)).assertEqual('c');
      expect(queueRowKey(queue[4], 4, queue)).assertEqual('a#2');
    });

    it('keepsPrefixKeysStableWhenTheQueueGrowsAtTheTail', 0, () => {
      const before: MobileTrack[] = [track('a'), track('b'), track('a')];
      const after: MobileTrack[] = [track('a'), track('b'), track('a'), track('a'), track('c')];

      for (let index = 0; index < before.length; index++) {
        expect(queueRowKey(before[index], index, before))
          .assertEqual(queueRowKey(after[index], index, after));
      }
      expect(queueRowKey(after[3], 3, after)).assertEqual('a#2');
      expect(queueRowKey(after[4], 4, after)).assertEqual('c');
    });

    // 整表 key 一次性算完（O(n)），必须与逐行版本逐项一致，否则 ForEach 复用会错行。
    it('matchesTheRowKeyOfEveryIndexInOnePass', 0, () => {
      const queues: MobileTrack[][] = [
        [],
        [track('a')],
        [track('a'), track('b'), track('a'), track('c'), track('a')],
        [track('b'), track('b'), track('b')]
      ];

      for (const queue of queues) {
        const keys: string[] = queueRowKeys(queue);
        expect(keys.length).assertEqual(queue.length);
        for (let index = 0; index < queue.length; index++) {
          expect(keys[index]).assertEqual(queueRowKey(queue[index], index, queue));
        }
      }
    });
  });
}