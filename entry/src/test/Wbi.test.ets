import { describe, expect, it } from '@ohos/hypium';
import {
  canonicalWbiQuery,
  md5Hex,
  mixinKeyFromKeys,
  parseWbiKeys,
  wbiQuery,
  WbiParams
} from '../main/ets/services/Wbi';

const IMG_KEY = '7cd084941338484aae1ad9425b84077c';
const SUB_KEY = '4932caff0ff746eab6f01bf08b70ac45';
const PARAMS: WbiParams = {
  searchType: 'video',
  keyword: '夜航星 !()*',
  page: 2,
  pageSize: 20
};
const TIMESTAMP = 1_700_000_000;
const CANONICAL_QUERY =
  'keyword=%E5%A4%9C%E8%88%AA%E6%98%9F%20&page=2&page_size=20&search_type=video&wts=1700000000';

export default function wbiTest(): void {
  describe('Wbi', () => {
    it('buildsFixedMixinKeyVector', 0, () => {
      expect(mixinKeyFromKeys(IMG_KEY, SUB_KEY)).assertEqual('ea1db124af3c7062474693fa704f4ff8');
    });

    it('buildsFixedCanonicalQueryVector', 0, () => {
      expect(canonicalWbiQuery(PARAMS, TIMESTAMP)).assertEqual(CANONICAL_QUERY);
    });

    it('hashesAndSignsWithFixedVectors', 0, () => {
      expect(md5Hex('abc')).assertEqual('900150983cd24fb0d6963f7d28e17f72');
      expect(md5Hex('中文')).assertEqual('a7bac2239fcdcb3a067903d8077c4a07');
      expect(wbiQuery(PARAMS, TIMESTAMP, IMG_KEY, SUB_KEY)).assertEqual(
        `${CANONICAL_QUERY}&w_rid=ccbbfae653036819e0c4b881cec8e313`
      );
    });

    it('extractsAndRejectsWbiKeys', 0, () => {
      const keys = parseWbiKeys(
        'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
        'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png?source=test'
      );

      expect(keys.length).assertEqual(2);
      expect(keys[0]).assertEqual(IMG_KEY);
      expect(keys[1]).assertEqual(SUB_KEY);
      expect(parseWbiKeys('', SUB_KEY).length).assertEqual(0);
    });
  });
}
