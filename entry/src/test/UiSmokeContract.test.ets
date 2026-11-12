import { describe, expect, it } from '@ohos/hypium';
import { NativeUiIds } from '../main/ets/components/native/NativeUiIds';
import { SearchGateway, SearchStore } from '../main/ets/state/SearchStore';
import { CatalogSearchResult, MobileTrack } from '../main/ets/types/MobileTypes';
import { NativeError } from '../main/ets/util/Errors';

class PendingUiSmokeSearch {
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

class FixtureSearchGateway implements SearchGateway {
  readonly requests: PendingUiSmokeSearch[] = [];

  search(keyword: string, page: number, pageSize: number): Promise<CatalogSearchResult> {
    const request = new PendingUiSmokeSearch(keyword, page, pageSize);
    this.requests.push(request);
    return request.promise;
  }
}

function fixtureTrack(keyword: string): MobileTrack {
  return {
    key: `fixture:${keyword}`,
    bvid: 'BV1FIXTURE',
    aid: 1,
    cid: 1,
    title: `Fixture ${keyword}`,
    artist: 'UI Smoke',
    coverUrl: '',
    duration: 120,
    playCount: 1
  };
}

function fixtureResult(keyword: string, items: MobileTrack[]): CatalogSearchResult {
  return {
    items: items,
    page: 1,
    hasMore: false,
    total: items.length,
    keyword: keyword
  };
}

function assertContains(selectors: string[], expected: string[]): void {
  expected.forEach((value: string): void => {
    expect(selectors.indexOf(value) >= 0).assertTrue();
  });
}

function assertStableSelectors(selectors: string[]): void {
  expect(selectors.length > 0).assertTrue();
  // 用 Set 做唯一性检查：`all()` 已有数百个选择器，两两比较会产生几十万次断言，
  // 曾把测试进程顶到 OOM（hypium 的 expect 每次都会分配包装对象）。
  const seen: Set<string> = new Set<string>();
  for (let index = 0; index < selectors.length; index++) {
    const selector = selectors[index];
    expect(selector.length > 0).assertTrue();
    expect(seen.has(selector)).assertFalse();
    seen.add(selector);
  }
}

export default function uiSmokeContractTest(): void {
  describe('UiSmokeContract', () => {
    it('definesUniqueShellDiscoverSearchAndLoginSelectors', 0, () => {
      const all = NativeUiIds.all();
      assertStableSelectors(all);
      assertStableSelectors(NativeUiIds.shellSelectors());
      assertStableSelectors(NativeUiIds.discoverSelectors());
      assertStableSelectors(NativeUiIds.searchSelectors());
      assertStableSelectors(NativeUiIds.loginSelectors());
      assertStableSelectors(NativeUiIds.settingsSelectors());

      assertContains(NativeUiIds.shellSelectors(), [
        NativeUiIds.shellRoot,
        NativeUiIds.shellHeaderActions,
        NativeUiIds.shellSettingsAction,
        NativeUiIds.navDiscover,
        NativeUiIds.navMine,
        NativeUiIds.bottomDock,
        NativeUiIds.navPill,
        NativeUiIds.discoverTabContent,
        NativeUiIds.libraryTabContent
      ]);
      assertContains(NativeUiIds.discoverSelectors(), [
        NativeUiIds.discoverPage
      ]);
      assertContains(NativeUiIds.searchSelectors(), [
        NativeUiIds.searchInput,
        NativeUiIds.searchLoadingState,
        NativeUiIds.searchResults,
        NativeUiIds.searchEmptyState,
        NativeUiIds.searchErrorState
      ]);
      assertContains(NativeUiIds.settingsSelectors(), [
        NativeUiIds.settingsPage,
        NativeUiIds.settingsBack,
        NativeUiIds.settingsContent,
        NativeUiIds.settingsGeneralSection,
        NativeUiIds.settingsThemeMode,
        NativeUiIds.settingsThemeLight,
        NativeUiIds.settingsThemeDark,
        NativeUiIds.settingsThemeSystem,
        NativeUiIds.settingsDataSection,
        NativeUiIds.settingsDownloadSection,
        NativeUiIds.settingsDownloadQuality,
        NativeUiIds.settingsDownloadQualityLow,
        NativeUiIds.settingsDownloadQualityStandard,
        NativeUiIds.settingsDownloadQualityHigh,
        NativeUiIds.settingsDownloadQualityNote,
        NativeUiIds.settingsPlaybackSection,
        NativeUiIds.settingsAudioQuality,
        NativeUiIds.settingsAudioQualityLow,
        NativeUiIds.settingsAudioQualityStandard,
        NativeUiIds.settingsAudioQualityHigh,
        NativeUiIds.settingsAudioQualityNote,
        NativeUiIds.settingsAutoPlay,
        NativeUiIds.settingsShowLyrics,
        NativeUiIds.settingsPlaybackSheet,
        NativeUiIds.sheetScrim(NativeUiIds.settingsPlaybackSheet),
        NativeUiIds.sheetHandle(NativeUiIds.settingsPlaybackSheet),
        NativeUiIds.settingsPlaybackSheetContent,
        NativeUiIds.settingsPlaybackSheetError,
        NativeUiIds.settingsCacheClear,
        NativeUiIds.settingsCacheError,
        NativeUiIds.settingsCacheRetry,
        NativeUiIds.settingsCacheSheet,
        NativeUiIds.sheetScrim(NativeUiIds.settingsCacheSheet),
        NativeUiIds.sheetHandle(NativeUiIds.settingsCacheSheet),
        NativeUiIds.settingsCacheSheetContent,
        NativeUiIds.settingsCacheSheetImages,
        NativeUiIds.settingsCacheSheetLyrics,
        NativeUiIds.settingsCacheSheetAudio,
        NativeUiIds.settingsCacheSheetClearAll,
        NativeUiIds.settingsCacheSheetError,
        NativeUiIds.settingsCacheSheetRetry,
        NativeUiIds.settingsWriteError,
        NativeUiIds.settingsOpenDiagnostics,
        NativeUiIds.settingsAboutSection,
        NativeUiIds.settingsAppVersion,
        NativeUiIds.settingsAuthor,
        NativeUiIds.settingsGithub,
        NativeUiIds.settingsLegal,
        NativeUiIds.settingsLegalSheet,
        NativeUiIds.sheetScrim(NativeUiIds.settingsLegalSheet),
        NativeUiIds.sheetHandle(NativeUiIds.settingsLegalSheet),
        NativeUiIds.settingsLegalSheetContent,
        NativeUiIds.diagnosticsSheet,
        NativeUiIds.sheetScrim(NativeUiIds.diagnosticsSheet),
        NativeUiIds.sheetHandle(NativeUiIds.diagnosticsSheet)
      ]);
      assertContains(NativeUiIds.loginSelectors(), [
        NativeUiIds.loginSheet,
        NativeUiIds.loginPage,
        NativeUiIds.loginContent,
        NativeUiIds.loginQrCode,
        NativeUiIds.loginQrUnavailable,
        NativeUiIds.loginError,
        NativeUiIds.loginMessageStatus,
        NativeUiIds.loginAccountCard,
        NativeUiIds.loginAccountName,
        NativeUiIds.loginLogout
      ]);
    });

    it('derivesTheSharedSheetSelectorsFromOneId', 0, () => {
      expect(NativeUiIds.loginSheet).assertEqual('login-sheet');
      expect(NativeUiIds.sheetScrim('login-sheet')).assertEqual('login-sheet-scrim');
      expect(NativeUiIds.sheetHandle('login-sheet')).assertEqual('login-sheet-handle');

      const loginSelectors = NativeUiIds.loginSelectors();
      const derived: string[] = [
        NativeUiIds.sheetScrim(NativeUiIds.loginSheet),
        NativeUiIds.sheetHandle(NativeUiIds.loginSheet)
      ];
      derived.forEach((selector: string): void => {
        expect(loginSelectors.indexOf(selector) >= 0).assertTrue();
      });

      // 设置页不再复用 BottomSheet：根 / 返回是独立 id，不再派生 scrim / handle / close。
      expect(NativeUiIds.settingsPage).assertEqual('settings-page');
      expect(NativeUiIds.settingsBack).assertEqual('settings-back');
      const settingsSelectors = NativeUiIds.settingsSelectors();
      const settingsRequired: string[] = [
        NativeUiIds.settingsPage,
        NativeUiIds.settingsBack
      ];
      settingsRequired.forEach((selector: string): void => {
        expect(settingsSelectors.indexOf(selector) >= 0).assertTrue();
      });

      // 缓存清理抽屉走共用外壳：id 只声明面板本体，蒙层 / 拖拽条统一派生。
      expect(NativeUiIds.settingsCacheSheet).assertEqual('settings-cache-sheet');
      const cacheSheetDerived: string[] = [
        NativeUiIds.sheetScrim(NativeUiIds.settingsCacheSheet),
        NativeUiIds.sheetHandle(NativeUiIds.settingsCacheSheet)
      ];
      cacheSheetDerived.forEach((selector: string): void => {
        expect(settingsSelectors.indexOf(selector) >= 0).assertTrue();
      });

      // 法律与免责声明抽屉同样走共用外壳：只声明面板本体，蒙层 / 拖拽条统一派生。
      expect(NativeUiIds.settingsLegalSheet).assertEqual('settings-legal-sheet');
      expect(NativeUiIds.settingsLegalSheetContent).assertEqual('settings-legal-sheet-content');
      const legalSheetDerived: string[] = [
        NativeUiIds.sheetScrim(NativeUiIds.settingsLegalSheet),
        NativeUiIds.sheetHandle(NativeUiIds.settingsLegalSheet)
      ];
      legalSheetDerived.forEach((selector: string): void => {
        expect(settingsSelectors.indexOf(selector) >= 0).assertTrue();
      });

      // 播放设置抽屉同层共用外壳：面板本体 + 内容 + 错误行，蒙层 / 拖拽条统一派生。
      expect(NativeUiIds.settingsPlaybackSheet).assertEqual('settings-playback-sheet');
      expect(NativeUiIds.settingsPlaybackSheetContent).assertEqual('settings-playback-sheet-content');
      expect(NativeUiIds.settingsPlaybackSheetError).assertEqual('settings-playback-sheet-error');
      const playbackSheetDerived: string[] = [
        NativeUiIds.sheetScrim(NativeUiIds.settingsPlaybackSheet),
        NativeUiIds.sheetHandle(NativeUiIds.settingsPlaybackSheet)
      ];
      playbackSheetDerived.forEach((selector: string): void => {
        expect(settingsSelectors.indexOf(selector) >= 0).assertTrue();
      });

      // 曲目操作抽屉 2026-11 起并入共用外壳：不再有手写的 track-action-scrim。
      expect(NativeUiIds.trackActionSheet).assertEqual('track-action-sheet');
      expect(NativeUiIds.trackActionToast).assertEqual('track-action-toast');
      assertStableSelectors(NativeUiIds.trackActionSelectors());
      assertContains(NativeUiIds.trackActionSelectors(), [
        NativeUiIds.trackActionSheet,
        NativeUiIds.sheetScrim(NativeUiIds.trackActionSheet),
        NativeUiIds.sheetHandle(NativeUiIds.trackActionSheet),
        NativeUiIds.trackActionContent,
        NativeUiIds.trackActionToast,
        NativeUiIds.trackActionDownload
      ]);
    });

    it('drivesSearchSmokeStatesWithDeterministicFixture', 0, async () => {
      const gateway = new FixtureSearchGateway();
      const store = new SearchStore(gateway);

      const successRequest = store.search('fixture-success');
      expect(store.snapshot.status).assertEqual('searching');
      expect(gateway.requests.length).assertEqual(1);
      gateway.requests[0].resolve(fixtureResult('fixture-success', [fixtureTrack('success')]));
      await successRequest;
      expect(store.snapshot.status).assertEqual('success');
      expect(store.snapshot.items[0].key).assertEqual('fixture:success');

      const emptyRequest = store.search('fixture-empty');
      expect(store.snapshot.status).assertEqual('searching');
      gateway.requests[1].resolve(fixtureResult('fixture-empty', []));
      await emptyRequest;
      expect(store.snapshot.status).assertEqual('empty');
      expect(store.snapshot.items.length).assertEqual(0);

      const errorRequest = store.search('fixture-error');
      expect(store.snapshot.status).assertEqual('searching');
      gateway.requests[2].reject(new NativeError('catalog.searchFailed', 'fixture failure', true));
      await errorRequest;
      expect(store.snapshot.status).assertEqual('error');
      expect(store.snapshot.canRetry).assertTrue();

      const retryRequest = store.retry();
      expect(store.snapshot.status).assertEqual('searching');
      gateway.requests[3].resolve(fixtureResult('fixture-error', [fixtureTrack('retry')]));
      await retryRequest;
      expect(store.snapshot.status).assertEqual('success');
      expect(store.snapshot.items[0].key).assertEqual('fixture:retry');

      const nextRequest = store.search('fixture-next');
      expect(store.snapshot.status).assertEqual('searching');
      gateway.requests[4].resolve(fixtureResult('fixture-next', [fixtureTrack('next')]));
      await nextRequest;
      expect(store.snapshot.status).assertEqual('success');
      expect(store.snapshot.keyword).assertEqual('fixture-next');
    });

    it('definesTheSleepTimerSheetSelectors', 0, () => {
      const selectors = NativeUiIds.sleepTimerSelectors();
      assertStableSelectors(selectors);
      assertContains(selectors, [
        NativeUiIds.sleepTimerSheet,
        NativeUiIds.sheetScrim(NativeUiIds.sleepTimerSheet),
        NativeUiIds.sheetHandle(NativeUiIds.sleepTimerSheet),
        NativeUiIds.sleepTimerContent,
        NativeUiIds.sleepTimerOption(15),
        NativeUiIds.sleepTimerOption(90),
        NativeUiIds.sleepTimerCancel
      ]);
      expect(NativeUiIds.sleepTimerOption(15)).assertEqual('sleep-timer-option-15');
    });

    it('definesTheAudioQualitySheetSelectors', 0, () => {
      const selectors = NativeUiIds.audioQualitySelectors();
      assertStableSelectors(selectors);
      assertContains(selectors, [
        NativeUiIds.audioQualitySheet,
        NativeUiIds.sheetScrim(NativeUiIds.audioQualitySheet),
        NativeUiIds.sheetHandle(NativeUiIds.audioQualitySheet),
        NativeUiIds.audioQualityContent,
        NativeUiIds.audioQualityOption('high'),
        NativeUiIds.audioQualityOption('standard'),
        NativeUiIds.audioQualityOption('low'),
        NativeUiIds.audioQualitySaveError,
        NativeUiIds.audioQualityFooter
      ]);
      expect(NativeUiIds.audioQualityOption('high')).assertEqual('audio-quality-option-high');
      expect(NativeUiIds.all().indexOf(NativeUiIds.audioQualitySheet) >= 0).assertTrue();
    });

    it('definesTheDownloadQualitySheetSelectors', 0, () => {
      const selectors = NativeUiIds.downloadQualitySelectors();
      assertStableSelectors(selectors);
      assertContains(selectors, [
        NativeUiIds.downloadQualitySheet,
        NativeUiIds.sheetScrim(NativeUiIds.downloadQualitySheet),
        NativeUiIds.sheetHandle(NativeUiIds.downloadQualitySheet),
        NativeUiIds.downloadQualityContent,
        NativeUiIds.downloadQualityOption('high'),
        NativeUiIds.downloadQualityOption('standard'),
        NativeUiIds.downloadQualityOption('low'),
        NativeUiIds.downloadQualitySaveError,
        NativeUiIds.downloadQualityFooter
      ]);
      expect(NativeUiIds.downloadQualityOption('high')).assertEqual('download-quality-option-high');
      expect(NativeUiIds.downloadQualitySheet).assertEqual('download-quality-sheet');
      expect(NativeUiIds.all().indexOf(NativeUiIds.downloadQualitySheet) >= 0).assertTrue();
    });

    it('treatsThePlayerPanelAsAPageInsteadOfASheet', 0, () => {
      // 播放页功能整页 2026-11 从底部抽屉改成右侧整页：根 id 保留，
      // 不再派生 scrim / handle / close，头部只留返回按钮。
      const playerSelectors = NativeUiIds.playerSelectors();
      assertStableSelectors(playerSelectors);
      expect(playerSelectors.indexOf(NativeUiIds.playerPanelBack) >= 0).assertTrue();
      expect(playerSelectors.indexOf(NativeUiIds.sheetScrim(NativeUiIds.playerControlPanel)))
        .assertEqual(-1);
      expect(playerSelectors.indexOf(NativeUiIds.sheetHandle(NativeUiIds.playerControlPanel)))
        .assertEqual(-1);
    });

    it('definesTheCollectionDetailSelectors', 0, () => {
      const selectors = NativeUiIds.collectionSelectors();
      assertStableSelectors(selectors);
      assertContains(selectors, [
        NativeUiIds.collectionDetail,
        NativeUiIds.collectionDetailHeaderBack,
        NativeUiIds.collectionDetailHero,
        NativeUiIds.collectionDetailPlayAll,
        NativeUiIds.collectionDetailSelectToggle,
        NativeUiIds.collectionDetailSelectAll,
        NativeUiIds.collectionDetailExitSelect,
        NativeUiIds.collectionDetailAddSelected,
        NativeUiIds.collectionDetailLoading,
        NativeUiIds.collectionDetailError,
        NativeUiIds.collectionDetailList,
        NativeUiIds.collectionDetailBack
      ]);
      expect(NativeUiIds.collectionDetailRow(2)).assertEqual('collection-detail-row-2');
      expect(NativeUiIds.collectionDetailFavorite(2)).assertEqual('collection-detail-favorite-2');
      expect(NativeUiIds.collectionDetailMoreAction(2)).assertEqual('collection-detail-more-action-2');
      expect(NativeUiIds.all().indexOf(NativeUiIds.collectionDetail) >= 0).assertTrue();
      expect(NativeUiIds.all().indexOf(NativeUiIds.collectionDetailRow(2)) >= 0).assertFalse();
    });
  });
}
