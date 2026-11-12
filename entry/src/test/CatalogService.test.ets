import { describe, expect, it } from '@ohos/hypium';
import {
  buildVideoDetail,
  parseVideoPages
} from '../main/ets/services/CatalogService';

function pageObject(cid: number, part: string, duration: number,
  page: number = 1): Record<string, Object> {
  return {
    'cid': cid,
    'part': part,
    'page': page,
    'duration': duration
  };
}

function videoData(pages: Object[], duration: number): Record<string, Object> {
  return {
    'bvid': 'BV1collection',
    'aid': 42,
    'title': '【周杰伦】50首精选合集',
    'cid': 101,
    'duration': duration,
    'pic': 'http://i0.hdslb.com/cover.jpg',
    'owner': {
      'name': '音乐UP'
    } as Record<string, Object>,
    'stat': {
      'view': 123456
    } as Record<string, Object>,
    'pages': pages
  };
}

export default function catalogServiceTest(): void {
  describe('CatalogService', () => {
    it('mapsMultiPageVideoToCollectionRootAndParts', 0, () => {
      const data = videoData([
        pageObject(101, '晴天', 240, 1),
        pageObject(102, '七里香', 360, 2)
      ], 600);

      const detail = buildVideoDetail(data, 'BV1collection');

      expect(detail === null).assertFalse();
      if (detail === null) {
        return;
      }
      expect(detail.rootTrack.cid).assertEqual(101);
      expect(detail.rootTrack.duration).assertEqual(240);
      expect(detail.rootTrack.collectionSize).assertEqual(2);
      expect(detail.rootTrack.collectionTotalDuration).assertEqual(600);
      expect(detail.totalDuration).assertEqual(600);
      expect(detail.pages.length).assertEqual(2);
      expect(detail.pages[1].title).assertEqual('七里香');
      expect(detail.rootTrack.coverUrl.startsWith('https://')).assertTrue();
    });

    it('usesSinglePageDurationAndSkipsCollectionMetadata', 0, () => {
      const data = videoData([pageObject(101, '', 180)], 180);

      const detail = buildVideoDetail(data, 'BV1collection');

      expect(detail === null).assertFalse();
      if (detail === null) {
        return;
      }
      expect(detail.rootTrack.duration).assertEqual(180);
      expect(detail.rootTrack.collectionSize === undefined).assertTrue();
      expect(detail.rootTrack.collectionTotalDuration === undefined).assertTrue();
      expect(detail.pages[0].title).assertEqual('P1');
    });

    it('fallsBackToSinglePageWhenPagesAreMissing', 0, () => {
      const data: Record<string, Object> = {
        'bvid': 'BV1single',
        'aid': 7,
        'title': '长视频',
        'cid': 301,
        'duration': 900,
        'owner': {} as Record<string, Object>,
        'stat': {} as Record<string, Object>
      };

      const detail = buildVideoDetail(data, 'BV1single');

      expect(detail === null).assertFalse();
      if (detail === null) {
        return;
      }
      expect(detail.rootTrack.cid).assertEqual(301);
      expect(detail.rootTrack.duration).assertEqual(900);
      expect(detail.rootTrack.artist).assertEqual('未知作者');
      expect(detail.pages.length).assertEqual(1);
    });

    it('skipsInvalidPagesAndFallsBackToPositionTitles', 0, () => {
      const pages = parseVideoPages([
        pageObject(0, '无效', 100, 1),
        pageObject(202, '', 120, 2)
      ]);

      expect(pages.length).assertEqual(1);
      expect(pages[0].cid).assertEqual(202);
      expect(pages[0].title).assertEqual('P2');
      expect(pages[0].duration).assertEqual(120);
    });

    it('capsCollectionPagesAtQueueLimit', 0, () => {
      const pages: Object[] = [];
      for (let index = 1; index <= 520; index++) {
        pages.push(pageObject(1000 + index, `P${index}`, 60));
      }

      const detail = buildVideoDetail(videoData(pages, 31200), 'BV1collection');

      expect(detail?.pages.length).assertEqual(500);
      expect(detail?.rootTrack.collectionSize).assertEqual(500);
      expect(detail?.rootTrack.collectionTotalDuration).assertEqual(30000);
    });
  });
}
