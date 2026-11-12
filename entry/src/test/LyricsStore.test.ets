import { describe, expect, it } from '@ohos/hypium';
import { LyricsGateway, LyricsStore } from '../main/ets/state/LyricsStore';
import { PlayerStore } from '../main/ets/state/PlayerStore';
import {
  LyricCandidate,
  LyricLine,
  LyricResult,
  MobileTrack,
  PlaybackState,
  emptyPlaybackState
} from '../main/ets/types/MobileTypes';
import { NativeError, wait } from '../main/ets/util/Errors';

class PendingLyricsCall {
  readonly params: Record<string, Object>;
  readonly promise: Promise<LyricResult | null>;
  private resolveCallback: ((result: LyricResult | null) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor(params: Record<string, Object>) {
    this.params = params;
    this.promise = new Promise<LyricResult | null>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: LyricResult | null): void {
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

class PendingCandidateSearchCall {
  readonly query: string;
  readonly promise: Promise<LyricCandidate[]>;
  private resolveCallback: ((result: LyricCandidate[]) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor(query: string) {
    this.query = query;
    this.promise = new Promise<LyricCandidate[]>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: LyricCandidate[]): void {
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

class PendingCandidateChoiceCall {
  readonly params: Record<string, Object>;
  readonly promise: Promise<LyricResult | null>;
  private resolveCallback: ((result: LyricResult | null) => void) | null = null;
  private rejectCallback: ((error: Object) => void) | null = null;

  constructor(params: Record<string, Object>) {
    this.params = params;
    this.promise = new Promise<LyricResult | null>((resolve, reject) => {
      this.resolveCallback = resolve;
      this.rejectCallback = reject;
    });
  }

  resolve(result: LyricResult | null): void {
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

class QueuedLyricsGateway implements LyricsGateway {
  readonly resolveRequests: PendingLyricsCall[] = [];
  readonly searchRequests: PendingCandidateSearchCall[] = [];
  readonly chooseRequests: PendingCandidateChoiceCall[] = [];

  resolve(params: Record<string, Object>): Promise<LyricResult | null> {
    const request = new PendingLyricsCall(params);
    this.resolveRequests.push(request);
    return request.promise;
  }

  search(query: string): Promise<LyricCandidate[]> {
    const request = new PendingCandidateSearchCall(query);
    this.searchRequests.push(request);
    return request.promise;
  }

  choose(params: Record<string, Object>): Promise<LyricResult | null> {
    const request = new PendingCandidateChoiceCall(params);
    this.chooseRequests.push(request);
    return request.promise;
  }
}

function lyricsTrack(label: string): MobileTrack {
  return {
    key: `track:${label}`,
    bvid: `BV${label}`,
    aid: 1,
    cid: 2,
    title: `Song ${label}`,
    artist: 'Artist',
    coverUrl: '',
    duration: 180,
    playCount: 0
  };
}

function playbackState(track: MobileTrack): PlaybackState {
  const state = emptyPlaybackState();
  state.status = 'playing';
  state.track = track;
  state.duration = track.duration;
  return state;
}

function lyricsResult(trackName: string, synced: boolean, labels: string[]): LyricResult {
  const lines: LyricLine[] = labels.map((label: string, index: number): LyricLine => {
    return {
      time: synced ? index + 1 : -1,
      text: label
    };
  });
  return {
    lines: lines,
    synced: synced,
    trackName: trackName,
    artistName: 'Artist',
    sourceId: `source:${trackName}`
  };
}

function lyricCandidate(id: string, trackName: string = `Candidate ${id}`): LyricCandidate {
  return {
    id: id,
    trackName: trackName,
    artistName: 'Candidate Artist',
    albumName: 'Candidate Album',
    duration: 201,
    image: 'https://example.invalid/private-cover.jpg?token=secret'
  };
}

export default function lyricsStoreTest(): void {
  describe('LyricsStore', () => {
    it('loadsSyncedLyricsForTheCurrentTrack', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      const track = lyricsTrack('ready');

      player.onState(playbackState(track));

      expect(gateway.resolveRequests.length).assertEqual(1);
      expect((gateway.resolveRequests[0].params.track as MobileTrack).key).assertEqual(track.key);
      expect(store.snapshot.status).assertEqual('loading');
      expect(store.snapshot.trackKey).assertEqual(track.key);
      expect(store.snapshot.lines.length).assertEqual(0);

      gateway.resolveRequests[0].resolve(lyricsResult('Song ready', true, ['first', 'second']));
      await gateway.resolveRequests[0].promise;
      await wait(0);

      expect(store.snapshot.status).assertEqual('ready');
      expect(store.snapshot.synced).assertTrue();
      expect(store.snapshot.lines.length).assertEqual(2);
      expect(store.snapshot.lines[1].text).assertEqual('second');
      expect(store.snapshot.error === null).assertTrue();
    });

    it('exposesUnsyncedLyricsWithoutBlockingPlayback', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      const track = lyricsTrack('unsynced');

      player.onState(playbackState(track));
      gateway.resolveRequests[0].resolve(lyricsResult('Song unsynced', false, ['plain lyric']));
      await gateway.resolveRequests[0].promise;
      await wait(0);

      expect(store.snapshot.status).assertEqual('unsynced');
      expect(store.snapshot.synced).assertFalse();
      expect(store.snapshot.lines[0].time).assertEqual(-1);
      expect(player.snapshot.status).assertEqual('playing');
      expect(player.snapshot.track?.key).assertEqual(track.key);
    });

    it('mapsNoLyricsToAnEmptyState', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();

      player.onState(playbackState(lyricsTrack('empty')));
      gateway.resolveRequests[0].resolve(null);
      await gateway.resolveRequests[0].promise;
      await wait(0);

      expect(store.snapshot.status).assertEqual('empty');
      expect(store.snapshot.lines.length).assertEqual(0);
      expect(store.snapshot.error === null).assertTrue();
    });

    it('sanitizesFailuresAndLeavesPlaybackUntouched', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();

      player.onState(playbackState(lyricsTrack('failure')));
      gateway.resolveRequests[0].reject(new NativeError('lyrics.fetchFailed',
        'https://example.invalid/lyrics?cookie=secret&mid=42', true));
      await wait(0);

      expect(store.snapshot.status).assertEqual('error');
      expect(store.snapshot.error?.code).assertEqual('lyrics.fetchFailed');
      expect(store.snapshot.error?.message.includes('https://')).assertFalse();
      expect(store.snapshot.error?.message.toLowerCase().includes('cookie')).assertFalse();
      expect(store.snapshot.canRetry).assertTrue();
      expect(player.snapshot.status).assertEqual('playing');

      const serialized = JSON.stringify(store.read()).toLowerCase();
      expect(serialized.includes('cookie=secret')).assertFalse();
      expect(serialized.includes('mid=42')).assertFalse();
    });

    it('doesNotReloadTheSameTrackOrExposeDuplicateRequests', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      const track = lyricsTrack('cache');

      player.onState(playbackState(track));
      player.onState(playbackState(track));
      expect(gateway.resolveRequests.length).assertEqual(1);

      gateway.resolveRequests[0].resolve(lyricsResult('Song cache', true, ['cached']));
      await gateway.resolveRequests[0].promise;
      await wait(0);
      player.onState(playbackState(track));

      expect(gateway.resolveRequests.length).assertEqual(1);
      expect(store.snapshot.status).assertEqual('ready');
      expect(store.snapshot.lines[0].text).assertEqual('cached');
    });

    it('dropsAnOlderTrackResponseAfterRapidTrackChanges', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      const oldTrack = lyricsTrack('old');
      const newTrack = lyricsTrack('new');

      player.onState(playbackState(oldTrack));
      const oldCall = gateway.resolveRequests[0];
      player.onState(playbackState(newTrack));
      const newCall = gateway.resolveRequests[1];

      newCall.resolve(lyricsResult('Song new', true, ['new lyric']));
      await newCall.promise;
      await wait(0);
      oldCall.resolve(lyricsResult('Song old', true, ['stale lyric']));
      await oldCall.promise;
      await wait(0);

      expect(gateway.resolveRequests.length).assertEqual(2);
      expect(store.snapshot.status).assertEqual('ready');
      expect(store.snapshot.trackKey).assertEqual(newTrack.key);
      expect(store.snapshot.lines.length).assertEqual(1);
      expect(store.snapshot.lines[0].text).assertEqual('new lyric');
    });

    it('searchesWithTitleAndArtistAndOmitsCandidateImageUrls', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      const track = lyricsTrack('manual');
      track.title = 'Song manual';
      track.artist = 'Singer manual';

      player.onState(playbackState(track));
      const pending = store.searchCandidates();

      expect(gateway.searchRequests.length).assertEqual(1);
      expect(gateway.searchRequests[0].query).assertEqual('Song manual Singer manual');
      expect(store.candidateSnapshot.status).assertEqual('loading');
      expect(store.candidateSnapshot.trackKey).assertEqual(track.key);

      gateway.searchRequests[0].resolve([lyricCandidate('candidate-1')]);
      await pending;
      await wait(0);

      expect(store.candidateSnapshot.status).assertEqual('ready');
      expect(store.candidateSnapshot.candidates.length).assertEqual(1);
      expect(store.candidateSnapshot.candidates[0].trackName).assertEqual('Candidate candidate-1');
      expect(store.candidateSnapshot.candidates[0].artistName).assertEqual('Candidate Artist');
      expect(store.candidateSnapshot.candidates[0].albumName).assertEqual('Candidate Album');
      expect(store.candidateSnapshot.candidates[0].duration).assertEqual(201);
      expect(store.candidateSnapshot.candidates[0].image).assertEqual('');

      const serialized = JSON.stringify(store.readCandidates()).toLowerCase();
      expect(serialized.includes('https://')).assertFalse();
      expect(serialized.includes('private-cover')).assertFalse();
      expect(serialized.includes('token=secret')).assertFalse();
    });

    it('filtersInvalidCandidatesDeduplicatesIdsAndCapsTheList', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      player.onState(playbackState(lyricsTrack('filtered')));

      const pending = store.searchCandidates();
      const rows: LyricCandidate[] = [
        lyricCandidate('duplicate'),
        lyricCandidate('duplicate'),
        lyricCandidate('https://example.invalid/private'),
        lyricCandidate('unsafe-title', 'https://example.invalid/title?cookie=secret')
      ];
      for (let index = 0; index < 24; index++) {
        rows.push(lyricCandidate(`candidate-${index}`));
      }
      gateway.searchRequests[0].resolve(rows);
      await pending;
      await wait(0);

      expect(store.candidateSnapshot.status).assertEqual('ready');
      expect(store.candidateSnapshot.candidates.length).assertEqual(20);
      expect(store.candidateSnapshot.candidates[0].id).assertEqual('duplicate');
      expect(store.candidateSnapshot.candidates[19].id).assertEqual('candidate-18');
      expect(store.candidateSnapshot.candidates[19].image).assertEqual('');
    });

    it('mapsEmptyCandidateSearchesToAStableEmptyState', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      player.onState(playbackState(lyricsTrack('no-candidates')));

      const pending = store.searchCandidates();
      gateway.searchRequests[0].resolve([]);
      await pending;
      await wait(0);

      expect(store.candidateSnapshot.status).assertEqual('empty');
      expect(store.candidateSnapshot.candidates.length).assertEqual(0);
      expect(store.candidateSnapshot.error === null).assertTrue();
    });

    it('sanitizesCandidateSearchFailuresAndKeepsExistingLyrics', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      player.onState(playbackState(lyricsTrack('search-failure')));
      gateway.resolveRequests[0].resolve(lyricsResult('Song existing', true, ['existing lyric']));
      await gateway.resolveRequests[0].promise;
      await wait(0);

      const pending = store.searchCandidates();
      gateway.searchRequests[0].reject(new NativeError('lyrics.searchFailed',
        'https://example.invalid/lyrics?cookie=secret&mid=42&sessdata=secret&bili_jct=secret&csrf=secret',
        true));
      await pending;
      await wait(0);

      expect(store.candidateSnapshot.status).assertEqual('error');
      expect(store.candidateSnapshot.error?.code).assertEqual('lyrics.searchFailed');
      expect(store.candidateSnapshot.error?.message.includes('https://')).assertFalse();
      expect(store.candidateSnapshot.error?.message.toLowerCase().includes('cookie')).assertFalse();
      expect(store.snapshot.status).assertEqual('ready');
      expect(store.snapshot.lines[0].text).assertEqual('existing lyric');

      const serialized = JSON.stringify(store.readCandidates()).toLowerCase();
      expect(serialized.includes('cookie=secret')).assertFalse();
      expect(serialized.includes('mid=42')).assertFalse();
      expect(serialized.includes('sessdata')).assertFalse();
      expect(serialized.includes('bili_jct')).assertFalse();
      expect(serialized.includes('csrf')).assertFalse();
    });

    it('submitsOneCandidateSearchAndOneSelectionForDuplicateClicks', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      const track = lyricsTrack('selection');
      player.onState(playbackState(track));

      const firstSearch = store.searchCandidates();
      const duplicateSearch = store.searchCandidates();
      expect(gateway.searchRequests.length).assertEqual(1);
      gateway.searchRequests[0].resolve([lyricCandidate('candidate-1')]);
      await Promise.all([firstSearch, duplicateSearch]);
      await wait(0);

      const firstSelection = store.selectCandidate('candidate-1');
      const duplicateSelection = store.selectCandidate('candidate-1');
      expect(gateway.chooseRequests.length).assertEqual(1);
      expect(store.candidateSnapshot.selectedCandidateId).assertEqual('candidate-1');
      expect((gateway.chooseRequests[0].params.track as MobileTrack).key).assertEqual(track.key);
      expect(gateway.chooseRequests[0].params.candidateId as string).assertEqual('candidate-1');

      gateway.chooseRequests[0].resolve(lyricsResult('Chosen song', true,
        ['chosen first', 'chosen second']));
      await Promise.all([firstSelection, duplicateSelection]);
      await wait(0);

      expect(store.snapshot.status).assertEqual('ready');
      expect(store.snapshot.lines.length).assertEqual(2);
      expect(store.snapshot.lines[0].text).assertEqual('chosen first');
      expect(store.candidateSnapshot.status).assertEqual('idle');
      expect(store.candidateSnapshot.selectedCandidateId).assertEqual('');
    });

    it('keepsCandidatesAvailableAfterSelectionFailureAndAllowsRetry', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      const track = lyricsTrack('selection-retry');
      player.onState(playbackState(track));
      gateway.resolveRequests[0].resolve(lyricsResult('Song existing', true, ['existing lyric']));
      await gateway.resolveRequests[0].promise;
      await wait(0);

      const search = store.searchCandidates();
      gateway.searchRequests[0].resolve([lyricCandidate('candidate-retry')]);
      await search;
      await wait(0);

      const failedSelection = store.selectCandidate('candidate-retry');
      expect(store.candidateSnapshot.selectedCandidateId).assertEqual('candidate-retry');
      gateway.chooseRequests[0].reject(new NativeError('lyrics.selectionFailed',
        'https://example.invalid/lyrics?cookie=secret&mid=42&sessdata=secret&bili_jct=secret&csrf=secret',
        true));
      expect(await failedSelection).assertFalse();
      await wait(0);

      expect(store.snapshot.status).assertEqual('ready');
      expect(store.snapshot.lines[0].text).assertEqual('existing lyric');
      expect(store.candidateSnapshot.status).assertEqual('ready');
      expect(store.candidateSnapshot.candidates.length).assertEqual(1);
      expect(store.candidateSnapshot.candidates[0].id).assertEqual('candidate-retry');
      expect(store.candidateSnapshot.selectedCandidateId).assertEqual('');
      expect(store.candidateSnapshot.error?.code).assertEqual('lyrics.selectionFailed');
      expect(store.candidateSnapshot.error?.message.includes('https://')).assertFalse();
      expect(store.candidateSnapshot.error?.message.toLowerCase().includes('cookie')).assertFalse();
      expect(store.candidateSnapshot.error?.message.toLowerCase().includes('sessdata')).assertFalse();
      expect(store.candidateSnapshot.error?.message.toLowerCase().includes('bili_jct')).assertFalse();
      expect(store.candidateSnapshot.error?.message.toLowerCase().includes('csrf')).assertFalse();

      const retrySelection = store.selectCandidate('candidate-retry');
      expect(gateway.chooseRequests.length).assertEqual(2);
      expect(store.candidateSnapshot.selectedCandidateId).assertEqual('candidate-retry');
      gateway.chooseRequests[1].resolve(lyricsResult('Chosen after retry', true,
        ['retry lyric']));
      expect(await retrySelection).assertTrue();
      await wait(0);

      expect(store.snapshot.status).assertEqual('ready');
      expect(store.snapshot.lines[0].text).assertEqual('retry lyric');
      expect(store.candidateSnapshot.status).assertEqual('idle');
      expect(store.candidateSnapshot.selectedCandidateId).assertEqual('');
    });

    it('dropsStaleCandidateSearchesAndSelectionsAfterTrackChanges', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      const oldTrack = lyricsTrack('old-search');
      const newTrack = lyricsTrack('new-search');

      player.onState(playbackState(oldTrack));
      const oldSearch = store.searchCandidates();
      player.onState(playbackState(newTrack));
      const newSearch = store.searchCandidates();

      gateway.searchRequests[0].resolve([lyricCandidate('old-candidate')]);
      await oldSearch;
      await wait(0);
      expect(store.candidateSnapshot.status).assertEqual('loading');
      expect(store.candidateSnapshot.trackKey).assertEqual(newTrack.key);

      gateway.searchRequests[1].resolve([lyricCandidate('new-candidate')]);
      await newSearch;
      await wait(0);
      expect(store.candidateSnapshot.status).assertEqual('ready');
      expect(store.candidateSnapshot.candidates[0].id).assertEqual('new-candidate');

      const selection = store.selectCandidate('new-candidate');
      expect(gateway.chooseRequests.length).assertEqual(1);
      player.onState(playbackState(lyricsTrack('latest')));
      gateway.chooseRequests[0].resolve(lyricsResult('Stale chosen song', true,
        ['stale chosen lyric']));
      await selection;
      await wait(0);

      expect(store.snapshot.status).assertEqual('loading');
      expect(store.snapshot.trackKey).assertEqual('track:latest');
      expect(store.snapshot.lines.length).assertEqual(0);
      expect(store.candidateSnapshot.status).assertEqual('idle');
    });

    it('cancelsAndDisposesPendingCandidateSearchesWithoutApplyingResponses', 0, async () => {
      const player = new PlayerStore();
      const gateway = new QueuedLyricsGateway();
      const store = new LyricsStore(player, gateway);
      store.attach();
      player.onState(playbackState(lyricsTrack('cancel')));

      const cancelled = store.searchCandidates();
      store.cancelCandidateSearch();
      gateway.searchRequests[0].resolve([lyricCandidate('cancelled-candidate')]);
      await cancelled;
      expect(store.candidateSnapshot.status).assertEqual('idle');
      expect(store.candidateSnapshot.candidates.length).assertEqual(0);

      const disposed = store.searchCandidates();
      store.dispose();
      gateway.searchRequests[1].resolve([lyricCandidate('disposed-candidate')]);
      await disposed;
      expect(store.candidateSnapshot.status).assertEqual('idle');
      expect(store.snapshot.status).assertEqual('idle');
    });
  });
}
