import { describe, expect, it } from '@ohos/hypium';
import {
  clampTabIndex,
  INDEX_DISCOVER_TAB,
  INDEX_ROOT_TAB,
  INDEX_TAB_COUNT,
  IndexBackAction,
  resolveIndexBackAction
} from '../main/ets/pages/IndexBackNavigation';

export default function indexBackNavigationTest(): void {
  describe('IndexBackNavigation', () => {
    it('closesDiagnosticsBeforeEveryOtherBackTarget', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: true,
        settingsPageVisible: true,
        loginSheetVisible: true,
        trackActionsVisible: true,
        playerControlPanelVisible: false,
        routeCount: 2,
        selectedTab: 1
      });

      expect(action).assertEqual(IndexBackAction.CloseDiagnostics);
    });

    it('closesTheCacheSheetBeforeTheSettingsPage', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        cacheSheetVisible: true,
        settingsPageVisible: true,
        loginSheetVisible: true,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseCacheSheet);
    });

    it('closesTheLegalSheetBeforeTheSettingsPage', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        cacheSheetVisible: false,
        legalSheetVisible: true,
        settingsPageVisible: true,
        loginSheetVisible: true,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseLegalSheet);
    });

    it('closesThePlaybackSheetBeforeTheSettingsPage', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        cacheSheetVisible: false,
        legalSheetVisible: false,
        playbackSheetVisible: true,
        audioQualitySheetVisible: false,
        settingsPageVisible: true,
        loginSheetVisible: true,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.ClosePlaybackSheet);
      expect(IndexBackAction.ClosePlaybackSheet).assertEqual(14);
    });

    it('closesTheAudioQualitySheetBeforeTheSettingsPage', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        cacheSheetVisible: false,
        legalSheetVisible: false,
        audioQualitySheetVisible: true,
        settingsPageVisible: true,
        loginSheetVisible: true,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseAudioQuality);
      expect(IndexBackAction.CloseAudioQuality).assertEqual(13);
    });

    it('closesTheAudioQualitySheetBeforeThePlayerControlPanel', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playerControlPanelVisible: true,
        audioQualitySheetVisible: true,
        routeCount: 0,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseAudioQuality);
    });

    it('closesTheSettingsPageBeforeLoginAndTrackActions', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: true,
        loginSheetVisible: true,
        trackActionsVisible: true,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: 1
      });

      expect(action).assertEqual(IndexBackAction.CloseSettingsPage);
    });

    it('closesTrackActionsBeforePoppingRoutes', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: true,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseTrackActions);
    });

    it('closesTheLoginSheetBeforePullingTheRouteStack', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: true,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 2,
        selectedTab: 1
      });

      expect(action).assertEqual(IndexBackAction.CloseLoginSheet);
    });

    it('closesTheLoginSheetBeforeTheTrackActionSheet', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: true,
        trackActionsVisible: true,
        playerControlPanelVisible: false,
        routeCount: 0,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseLoginSheet);
    });

    it('closesThePlayerControlPanelBeforePoppingRoutes', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playerControlPanelVisible: true,
        routeCount: 1,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.ClosePlayerControlPanel);
    });

    it('closesTheTrackActionSheetBeforeThePlayerControlPanel', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: true,
        playerControlPanelVisible: true,
        routeCount: 0,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseTrackActions);
    });

    it('closesThePlaylistCreateSheetBeforeTheRouteStack', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playlistCreateVisible: true,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.ClosePlaylistCreate);
    });

    it('closesThePlaylistEditSheetBeforeTheRouteStack', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playlistEditVisible: true,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.ClosePlaylistEdit);
    });

    it('closesTheSleepTimerSheetBeforeThePlayerControlPanel', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playerControlPanelVisible: true,
        sleepTimerSheetVisible: true,
        routeCount: 0,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseSleepTimer);
    });

    it('closesTheSleepTimerSheetBeforePoppingRoutes', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        sleepTimerSheetVisible: true,
        routeCount: 2,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.CloseSleepTimer);
    });

    it('popsTheTopRouteBeforeChangingTabs', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 1,
        selectedTab: 1
      });

      expect(action).assertEqual(IndexBackAction.PopRoute);
    });

    it('returnsTheDiscoverTabToTheMineRoot', 0, () => {
      const discoverAction = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 0,
        selectedTab: INDEX_DISCOVER_TAB
      });

      expect(discoverAction).assertEqual(IndexBackAction.OpenRootTab);
    });

    it('returnsStaleTabIndexesToTheMineRoot', 0, () => {
      const staleAction = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 0,
        selectedTab: 2
      });

      expect(staleAction).assertEqual(IndexBackAction.OpenRootTab);
    });

    it('allowsSystemExitFromTheMineRoot', 0, () => {
      const action = resolveIndexBackAction({
        diagnosticsVisible: false,
        settingsPageVisible: false,
        loginSheetVisible: false,
        trackActionsVisible: false,
        playerControlPanelVisible: false,
        routeCount: 0,
        selectedTab: INDEX_ROOT_TAB
      });

      expect(action).assertEqual(IndexBackAction.AllowSystemExit);
    });

    it('clampsTabIndexesIntoTheTwoTabRange', 0, () => {
      expect(INDEX_DISCOVER_TAB).assertEqual(0);
      expect(INDEX_ROOT_TAB).assertEqual(1);
      expect(INDEX_TAB_COUNT).assertEqual(2);
      expect(clampTabIndex(-1)).assertEqual(INDEX_DISCOVER_TAB);
      expect(clampTabIndex(0)).assertEqual(INDEX_DISCOVER_TAB);
      expect(clampTabIndex(1)).assertEqual(INDEX_ROOT_TAB);
      expect(clampTabIndex(2)).assertEqual(INDEX_ROOT_TAB);
      expect(clampTabIndex(99)).assertEqual(INDEX_ROOT_TAB);
      expect(clampTabIndex(Number.NaN)).assertEqual(INDEX_ROOT_TAB);
    });
  });
}
