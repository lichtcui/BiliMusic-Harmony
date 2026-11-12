import { describe, expect, it } from '@ohos/hypium';
import {
  hasSameTrackSet,
  PlaylistPlaybackAction,
  resolvePlaylistPlaybackAction,
  sanitizeTrackCount
} from '../main/ets/components/native/MinePageState';
import { NativeUiIds } from '../main/ets/components/native/NativeUiIds';
import { MobileTrack } from '../main/ets/types/MobileTypes';

function mineTrack(key: string): MobileTrack {
  return {
    key: key,
    bvid: key,
    aid: 1,
    cid: 1,
    title: key,
    artist: '',
    coverUrl: '',
    duration: 0,
    playCount: 0
  };
}

export default function minePageStateTest(): void {
  describe('MinePageState', () => {
    it('sanitizesTrackCountsBeforeTheyReachTheRowSubtitle', 0, () => {
      expect(sanitizeTrackCount(0)).assertEqual(0);
      expect(sanitizeTrackCount(24)).assertEqual(24);
      expect(sanitizeTrackCount(24.9)).assertEqual(24);
      expect(sanitizeTrackCount(-3)).assertEqual(0);
      expect(sanitizeTrackCount(Number.NaN)).assertEqual(0);
      expect(sanitizeTrackCount(Number.POSITIVE_INFINITY)).assertEqual(0);
    });

    it('recognizesTheSamePlaybackSetRegardlessOfOrder', 0, () => {
      const first = mineTrack('a');
      const second = mineTrack('b');
      const keys = [first.key, second.key];
      expect(hasSameTrackSet([first, second], keys)).assertTrue();
      expect(hasSameTrackSet([second, first], keys)).assertTrue();
      expect(hasSameTrackSet([first], keys)).assertFalse();
      expect(hasSameTrackSet([first, second, mineTrack('c')], keys)).assertFalse();
      expect(hasSameTrackSet([], [])).assertFalse();
    });

    it('ignoresDuplicateKeysWhenComparingSets', 0, () => {
      const first = mineTrack('a');
      const second = mineTrack('b');
      const queue = [first, second, second];
      const keys = [first.key, second.key];
      expect(hasSameTrackSet(queue, keys)).assertTrue();
      expect(resolvePlaylistPlaybackAction('playing', queue, keys))
        .assertEqual(PlaylistPlaybackAction.Pause);
    });

    it('resolvesPlayAllPauseAndResumeForMusicListRows', 0, () => {
      const first = mineTrack('a');
      const second = mineTrack('b');
      const queue = [first, second];
      const keys = [first.key, second.key];
      expect(resolvePlaylistPlaybackAction('playing', queue, keys))
        .assertEqual(PlaylistPlaybackAction.Pause);
      expect(resolvePlaylistPlaybackAction('paused', queue, keys))
        .assertEqual(PlaylistPlaybackAction.Resume);
      expect(resolvePlaylistPlaybackAction('idle', queue, keys))
        .assertEqual(PlaylistPlaybackAction.PlayAll);
      expect(resolvePlaylistPlaybackAction('playing', [second], keys))
        .assertEqual(PlaylistPlaybackAction.PlayAll);
    });

    it('exposesStableMineSelectorsForTheSmokeContract', 0, () => {
      const selectors = NativeUiIds.librarySelectors();
      const expected: string[] = [
        NativeUiIds.minePage,
        NativeUiIds.mineHeader,
        NativeUiIds.mineAccountCard,
        NativeUiIds.mineAccountName,
        NativeUiIds.mineAccountAction,
        NativeUiIds.minePlaylistsContent,
        NativeUiIds.mineQuickActions,
        NativeUiIds.mineQuickLiked,
        NativeUiIds.mineQuickHistory,
        NativeUiIds.mineQuickDownloads,
        NativeUiIds.mineQuickCreate,
        NativeUiIds.mineQuickLikedPlay,
        NativeUiIds.mineQuickHistoryPlay,
        NativeUiIds.mineQuickDownloadsPlay,
        NativeUiIds.recentHeader,
        NativeUiIds.recentHeaderBack
      ];
      expected.forEach((selector: string): void => {
        expect(selectors.indexOf(selector) >= 0).assertTrue();
        expect(NativeUiIds.all().indexOf(selector) >= 0).assertTrue();
      });
      expect(NativeUiIds.minePlaylistCover(2)).assertEqual('mine-playlist-cover-2');
      expect(NativeUiIds.minePlaylistPlay(2)).assertEqual('mine-playlist-play-2');
    });
  });
}
