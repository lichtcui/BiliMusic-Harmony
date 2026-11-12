import { describe, expect, it } from '@ohos/hypium';
import {
  MobileSettings,
  SettingsPersistence,
  SettingsStore,
  ThemeMode,
  defaultSettings
} from '../main/ets/state/SettingsStore';
import { wait } from '../main/ets/util/Errors';

class MemorySettingsPersistence implements SettingsPersistence {
  content: string | null = null;
  activeWrites: number = 0;
  maxActiveWrites: number = 0;
  writeCount: number = 0;
  preservedCount: number = 0;
  failWrites: boolean = false;

  constructor(content: string | null = null) {
    this.content = content;
  }

  read(_path: string): string | null {
    return this.content;
  }

  async write(_path: string, content: string): Promise<void> {
    this.writeCount++;
    this.activeWrites++;
    this.maxActiveWrites = Math.max(this.maxActiveWrites, this.activeWrites);
    try {
      await wait(2);
      if (this.failWrites) {
        throw new Error('simulated settings write failure');
      }
      this.content = content;
    } finally {
      this.activeWrites--;
    }
  }

  preserveCorrupt(_path: string): void {
    this.preservedCount++;
  }
}

function persistedSettings(persistence: MemorySettingsPersistence): MobileSettings {
  return JSON.parse(persistence.content ?? '{}') as MobileSettings;
}

export default function settingsStoreTest(): void {
  describe('SettingsStore', () => {
    it('usesDefaultsWithoutBlockingStartup', 0, () => {
      const store = new SettingsStore('memory://settings', new MemorySettingsPersistence());
      expect(store.read()).assertDeepEquals(defaultSettings());
      expect(store.read().themeMode).assertEqual('system');
      expect(store.read().audioQuality).assertEqual('low');
      expect(store.read().downloadQuality).assertEqual('low');
      expect(store.read().downloadLimit).assertEqual(500);
      expect(store.error === null).assertTrue();
    });

    it('fallsBackToLowAudioQualityForOlderAndInvalidValues', 0, () => {
      const older = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({ version: 1, showLyrics: true, restorePlayback: true, themeMode: 'system' })
      ));
      const invalid = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({
          version: 1,
          showLyrics: true,
          restorePlayback: true,
          themeMode: 'system',
          audioQuality: 'auto'
        })
      ));

      expect(older.read().audioQuality).assertEqual('low');
      expect(invalid.read().audioQuality).assertEqual('low');
    });

    it('fallsBackToSystemThemeForOlderAndInvalidValues', 0, () => {
      const older = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({ version: 1, showLyrics: true, restorePlayback: true })
      ));
      const invalid = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({ version: 1, showLyrics: true, restorePlayback: true, themeMode: 'sepia' })
      ));

      expect(older.read().themeMode).assertEqual('system');
      expect(invalid.read().themeMode).assertEqual('system');
    });

    it('acceptsOlderPartialValuesAndFallsBackPerField', 0, () => {
      const persistence = new MemorySettingsPersistence(
        JSON.stringify({ version: 1, showLyrics: false, restorePlayback: 'invalid' })
      );
      const store = new SettingsStore('memory://settings', persistence);

      expect(store.read().showLyrics).assertFalse();
      expect(store.read().restorePlayback).assertTrue();
      expect(store.read().themeMode).assertEqual('system');
      expect(persistence.preservedCount).assertEqual(0);
    });

    it('persistsUpdatesAndReadsThemAfterRestart', 0, async () => {
      const persistence = new MemorySettingsPersistence();
      const store = new SettingsStore('memory://settings', persistence);

      const result = await store.update({
        showLyrics: false,
        restorePlayback: false
      });

      expect(result.success).assertTrue();
      expect(result.error === null).assertTrue();
      expect(result.settings.showLyrics).assertFalse();

      const restarted = new SettingsStore('memory://settings', persistence);
      expect(restarted.read()).assertDeepEquals(result.settings);
    });

    it('persistsAudioQualityAcrossRestart', 0, async () => {
      const persistence = new MemorySettingsPersistence();
      const store = new SettingsStore('memory://settings', persistence);

      const result = await store.update({ audioQuality: 'high' });

      expect(result.success).assertTrue();
      expect(result.settings.audioQuality).assertEqual('high');
      expect(persistedSettings(persistence).audioQuality).assertEqual('high');

      const restarted = new SettingsStore('memory://settings', persistence);
      expect(restarted.read().audioQuality).assertEqual('high');
    });

    it('fallsBackToDefaultDownloadQualityForOlderAndInvalidValues', 0, () => {
      const older = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({ version: 1, showLyrics: true, restorePlayback: true })
      ));
      const invalid = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({
          version: 1,
          showLyrics: true,
          restorePlayback: true,
          downloadQuality: 'lossless'
        })
      ));
      const wrongType = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({ version: 1, downloadQuality: 128 })
      ));

      expect(older.read().downloadQuality).assertEqual('low');
      expect(invalid.read().downloadQuality).assertEqual('low');
      expect(wrongType.read().downloadQuality).assertEqual('low');
    });

    it('persistsDownloadQualityIndependentlyFromAudioQuality', 0, async () => {
      const persistence = new MemorySettingsPersistence();
      const store = new SettingsStore('memory://settings', persistence);

      const result = await store.update({ downloadQuality: 'high' });
      expect(result.success).assertTrue();
      expect(result.settings.downloadQuality).assertEqual('high');
      expect(result.settings.audioQuality).assertEqual('low');
      expect(persistedSettings(persistence).downloadQuality).assertEqual('high');

      const restarted = new SettingsStore('memory://settings', persistence);
      expect(restarted.read().downloadQuality).assertEqual('high');
      expect(restarted.read().audioQuality).assertEqual('low');
    });

    it('fallsBackToDefaultDownloadLimitForOlderAndInvalidValues', 0, () => {
      const older = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({ version: 1, showLyrics: true, restorePlayback: true })
      ));
      const invalid = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({ version: 1, downloadLimit: 42 })
      ));
      const wrongType = new SettingsStore('memory://settings', new MemorySettingsPersistence(
        JSON.stringify({ version: 1, downloadLimit: '500' })
      ));

      expect(older.read().downloadLimit).assertEqual(500);
      expect(invalid.read().downloadLimit).assertEqual(500);
      expect(wrongType.read().downloadLimit).assertEqual(500);
    });

    it('persistsDownloadLimitAndIgnoresOptionsOutsidePresets', 0, async () => {
      const persistence = new MemorySettingsPersistence();
      const store = new SettingsStore('memory://settings', persistence);

      const result = await store.update({ downloadLimit: 300 });
      expect(result.success).assertTrue();
      expect(result.settings.downloadLimit).assertEqual(300);
      expect(persistedSettings(persistence).downloadLimit).assertEqual(300);

      const ignored = await store.update({ downloadLimit: 42 });
      expect(ignored.success).assertTrue();
      expect(store.read().downloadLimit).assertEqual(300);

      const restarted = new SettingsStore('memory://settings', persistence);
      expect(restarted.read().downloadLimit).assertEqual(300);
    });

    it('serializesConcurrentUpdatesWithoutLosingFields', 0, async () => {
      const persistence = new MemorySettingsPersistence();
      const store = new SettingsStore('memory://settings', persistence);

      const pending = [
        store.update({ showLyrics: false }),
        store.update({ restorePlayback: false }),
        store.update({ showLyrics: true })
      ];
      const results = await Promise.all(pending);
      await store.flush();

      expect(persistence.maxActiveWrites).assertEqual(1);
      expect(persistence.writeCount).assertEqual(3);
      expect(results[results.length - 1].success).assertTrue();
      expect(store.read().showLyrics).assertTrue();
      expect(store.read().restorePlayback).assertFalse();
      expect(persistedSettings(persistence)).assertDeepEquals(store.read());
    });

    it('persistsThemeModeAndNotifiesOnceOnChange', 0, async () => {
      const persistence = new MemorySettingsPersistence();
      const store = new SettingsStore('memory://settings', persistence);
      const notified: ThemeMode[] = [];
      store.setThemeModeListener((mode: ThemeMode): void => {
        notified.push(mode);
      });

      const first = await store.update({ themeMode: 'dark' });
      const second = await store.update({ themeMode: 'dark' });
      const third = await store.update({ themeMode: 'light' });

      expect(first.success).assertTrue();
      expect(second.success).assertTrue();
      expect(third.success).assertTrue();
      expect(store.read().themeMode).assertEqual('light');
      expect(notified.length).assertEqual(2);
      expect(notified[0]).assertEqual('dark');
      expect(notified[1]).assertEqual('light');
      expect(persistedSettings(persistence).themeMode).assertEqual('light');
    });

    it('doesNotNotifyThemeWhenWriteFails', 0, async () => {
      const persistence = new MemorySettingsPersistence(JSON.stringify(defaultSettings()));
      const store = new SettingsStore('memory://settings', persistence);
      const notified: ThemeMode[] = [];
      store.setThemeModeListener((mode: ThemeMode): void => {
        notified.push(mode);
      });
      persistence.failWrites = true;

      const failed = await store.update({ themeMode: 'dark' });

      expect(failed.success).assertFalse();
      expect(store.read().themeMode).assertEqual('system');
      expect(notified.length).assertEqual(0);
    });

    it('keepsOldMemoryStateWhenWriteFails', 0, async () => {
      const initial = defaultSettings();
      const persistence = new MemorySettingsPersistence(JSON.stringify(initial));
      const store = new SettingsStore('memory://settings', persistence);
      persistence.failWrites = true;

      const failed = await store.update({ showLyrics: false });

      expect(failed.success).assertFalse();
      expect(failed.error?.code).assertEqual('settings.writeFailed');
      expect(store.read()).assertDeepEquals(initial);
      expect(persistedSettings(persistence)).assertDeepEquals(initial);
      expect(store.error?.code).assertEqual('settings.writeFailed');

      persistence.failWrites = false;
      const retried = await store.update({ showLyrics: false });
      expect(retried.success).assertTrue();
      expect(store.error === null).assertTrue();
      expect(store.read().showLyrics).assertFalse();
    });

    it('publishesOptimisticallyThenRollsBackFailedWrite', 0, async () => {
      const initial = defaultSettings();
      const persistence = new MemorySettingsPersistence(JSON.stringify(initial));
      const store = new SettingsStore('memory://settings', persistence);
      persistence.failWrites = true;

      const pending = store.update({ showLyrics: false });
      await wait(1);

      expect(persistence.activeWrites).assertEqual(1);
      expect(store.read().showLyrics).assertFalse();

      const failed = await pending;
      expect(failed.success).assertFalse();
      expect(store.read()).assertDeepEquals(initial);
      expect(persistedSettings(persistence)).assertDeepEquals(initial);
    });

    it('recoversCorruptAndUnsupportedFilesWithDefaults', 0, () => {
      const corruptPersistence = new MemorySettingsPersistence('{bad json');
      const corrupt = new SettingsStore('memory://settings', corruptPersistence);
      expect(corrupt.read()).assertDeepEquals(defaultSettings());
      expect(corruptPersistence.preservedCount).assertEqual(1);

      const futurePersistence = new MemorySettingsPersistence(
        JSON.stringify({ version: 2, showLyrics: false, restorePlayback: false })
      );
      const future = new SettingsStore('memory://settings', futurePersistence);
      expect(future.read()).assertDeepEquals(defaultSettings());
      expect(futurePersistence.preservedCount).assertEqual(1);
    });
  });
}
