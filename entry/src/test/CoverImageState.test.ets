import { describe, expect, it } from '@ohos/hypium';
import {
  CoverLoadReferences,
  CoverRequestTracker,
  isLocalCoverUri
} from '../main/ets/components/native/CoverImageState';

export default function coverImageStateTest(): void {
  describe('CoverImageState', () => {
    it('rejectsStaleRequestsAfterUrlChangeAndDisposal', 0, () => {
      const tracker = new CoverRequestTracker();
      const first = tracker.begin('https://i0.hdslb.com/bfs/first.jpg');
      expect(tracker.isCurrent(first)).assertTrue();

      const second = tracker.begin('https://i0.hdslb.com/bfs/second.jpg');
      expect(tracker.isCurrent(first)).assertFalse();
      expect(tracker.isCurrent(second)).assertTrue();
      expect(tracker.isActiveUrl('https://i0.hdslb.com/bfs/second.jpg')).assertTrue();

      tracker.invalidate();
      expect(tracker.isCurrent(second)).assertFalse();
      expect(tracker.isActiveUrl('https://i0.hdslb.com/bfs/second.jpg')).assertFalse();
    });

    it('cancelsSharedUrlOnlyAfterTheLastCoverReleasesIt', 0, () => {
      const references = new CoverLoadReferences();
      const targetUrl = 'https://i0.hdslb.com/bfs/shared.jpg';

      expect(references.retain(targetUrl)).assertEqual(1);
      expect(references.retain(targetUrl)).assertEqual(2);
      expect(references.release(targetUrl)).assertEqual(1);
      expect(references.release(targetUrl)).assertEqual(0);
      expect(references.release(targetUrl)).assertEqual(0);
      expect(references.retain('https://s1.biliimg.com/other.jpg')).assertEqual(1);
    });

    it('routesSandboxFileCoversAroundTheNetworkCache', 0, () => {
      expect(isLocalCoverUri('file:///data/storage/el2/base/files/cover.img')).assertTrue();
      expect(isLocalCoverUri('  FILE:///data/storage/el2/base/files/cover.img  ')).assertTrue();
      expect(isLocalCoverUri('https://i0.hdslb.com/bfs/cover.jpg')).assertFalse();
      expect(isLocalCoverUri('')).assertFalse();
    });
  });
}
