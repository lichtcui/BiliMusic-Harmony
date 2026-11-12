import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AppError,
  AudioQuality
} from '../types/MobileTypes';
import {
  preserveCorruptFile,
  readAtomicText,
  writeAtomicText
} from '../util/AtomicJson';
import { appError } from '../util/Errors';

const DOMAIN = 0x424D;
const TAG = 'WispMusicSettings';
const SETTINGS_STORAGE_VERSION = 1;

export type ThemeMode = 'light' | 'dark' | 'system';

/** 下载保留条数档位；默认取最高档，降低档位会立即清理最旧的下载。 */
export const DOWNLOAD_LIMIT_OPTIONS: number[] = [100, 300, 500];
export const DEFAULT_DOWNLOAD_LIMIT: number = 500;

export interface MobileSettings {
  version: number;
  showLyrics: boolean;
  restorePlayback: boolean;
  themeMode: ThemeMode;
  audioQuality: AudioQuality;
  /** 下载取源品质，与播放音质解耦；默认最低档，只影响之后的新下载。 */
  downloadQuality: AudioQuality;
  downloadLimit: number;
}

export interface SettingsPatch {
  showLyrics?: boolean;
  restorePlayback?: boolean;
  themeMode?: ThemeMode;
  audioQuality?: AudioQuality;
  downloadQuality?: AudioQuality;
  downloadLimit?: number;
}

export interface SettingsUpdateResult {
  success: boolean;
  settings: MobileSettings;
  error: AppError | null;
}

export interface SettingsPersistence {
  read(path: string): string | null;
  write(path: string, content: string): Promise<void>;
  preserveCorrupt(path: string): void;
}

class AtomicSettingsPersistence implements SettingsPersistence {
  read(path: string): string | null {
    return readAtomicText(path);
  }

  write(path: string, content: string): Promise<void> {
    return writeAtomicText(path, content);
  }

  preserveCorrupt(path: string): void {
    preserveCorruptFile(path);
  }
}

export function defaultSettings(): MobileSettings {
  return {
    version: SETTINGS_STORAGE_VERSION,
    showLyrics: true,
    restorePlayback: true,
    themeMode: 'system',
    audioQuality: 'low',
    downloadQuality: 'low',
    downloadLimit: DEFAULT_DOWNLOAD_LIMIT
  };
}

/**
 * Sole writer for the versioned settings file.
 *
 * PlayerService and LyricsService remain the owners of live playback and lyric
 * content state. This store only owns user preferences used to configure those
 * services, so updates never copy live state back into settings.
 */
@Observed
export class SettingsStore {
  @Track snapshot: MobileSettings;
  @Track error: AppError | null = null;

  private readonly path: string;
  private readonly persistence: SettingsPersistence;
  private mutationChain: Promise<void> = Promise.resolve();
  private themeModeListener: ((mode: ThemeMode) => void) | null = null;

  constructor(path: string, persistence: SettingsPersistence = new AtomicSettingsPersistence()) {
    this.path = path;
    this.persistence = persistence;
    this.snapshot = this.load();
  }

  read(): MobileSettings {
    return cloneSettings(this.snapshot);
  }

  /**
   * 主题模式只影响 Application 层配色，不应让页面直接持有 AbilityContext；
   * 由 EntryAbility 在运行时注册监听，成功写入后即时应用。
   */
  setThemeModeListener(listener: ((mode: ThemeMode) => void) | null): void {
    this.themeModeListener = listener;
  }

  update(patch: SettingsPatch): Promise<SettingsUpdateResult> {
    const pending: Promise<SettingsUpdateResult> = this.mutationChain
      .catch((): void => {})
      .then((): Promise<SettingsUpdateResult> => this.applyUpdate(patch));
    this.mutationChain = pending.then((): void => {}, (): void => {});
    return pending;
  }

  async flush(): Promise<void> {
    await this.mutationChain.catch((): void => {});
  }

  private async applyUpdate(patch: SettingsPatch): Promise<SettingsUpdateResult> {
    const current = this.snapshot;
    const next = cloneSettings(current);
    if (patch.showLyrics !== undefined) {
      next.showLyrics = patch.showLyrics;
    }
    if (patch.restorePlayback !== undefined) {
      next.restorePlayback = patch.restorePlayback;
    }
    if (patch.themeMode !== undefined) {
      next.themeMode = patch.themeMode;
    }
    if (patch.audioQuality !== undefined) {
      next.audioQuality = patch.audioQuality;
    }
    if (patch.downloadQuality !== undefined) {
      next.downloadQuality = audioQualityOr(patch.downloadQuality, current.downloadQuality);
    }
    if (patch.downloadLimit !== undefined) {
      next.downloadLimit = downloadLimitOr(patch.downloadLimit, current.downloadLimit);
    }
    if (settingsEqual(current, next)) {
      this.error = null;
      return {
        success: true,
        settings: cloneSettings(current),
        error: null
      };
    }
    this.snapshot = next;
    this.error = null;
    try {
      await this.persistence.write(this.path, JSON.stringify(next));
    } catch (error) {
      const failure = appError('settings.writeFailed', '设置保存失败，请稍后重试。', true);
      this.snapshot = current;
      this.error = failure;
      hilog.warn(DOMAIN, TAG, 'settings write failed');
      return {
        success: false,
        settings: cloneSettings(current),
        error: failure
      };
    }
    if (next.themeMode !== current.themeMode) {
      this.notifyThemeMode(next.themeMode);
    }
    return {
      success: true,
      settings: cloneSettings(next),
      error: null
    };
  }

  private notifyThemeMode(mode: ThemeMode): void {
    const listener = this.themeModeListener;
    if (listener === null) {
      return;
    }
    try {
      listener(mode);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'theme mode listener failed code=%{public}s',
        error instanceof Error ? error.message : 'unknown');
    }
  }

  private load(): MobileSettings {
    const content = this.persistence.read(this.path);
    if (content === null) {
      return defaultSettings();
    }
    try {
      const parsed = JSON.parse(content) as Record<string, Object>;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed) ||
        Number(parsed.version) !== SETTINGS_STORAGE_VERSION) {
        throw new Error('Unsupported settings storage version.');
      }
      return sanitizeSettings(parsed);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'settings state is corrupt or unsupported; starting with defaults');
      this.persistence.preserveCorrupt(this.path);
      return defaultSettings();
    }
  }
}

export function sanitizeSettings(raw: Record<string, Object>): MobileSettings {
  return {
    version: SETTINGS_STORAGE_VERSION,
    showLyrics: booleanOr(raw.showLyrics, true),
    restorePlayback: booleanOr(raw.restorePlayback, true),
    themeMode: themeModeOr(raw.themeMode, 'system'),
    audioQuality: audioQualityOr(raw.audioQuality, 'low'),
    downloadQuality: audioQualityOr(raw.downloadQuality, 'low'),
    downloadLimit: downloadLimitOr(raw.downloadLimit, DEFAULT_DOWNLOAD_LIMIT)
  };
}

function booleanOr(value: Object | undefined, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value as boolean : fallback;
}

function themeModeOr(value: Object | undefined, fallback: ThemeMode): ThemeMode {
  if (value === 'light' || value === 'dark' || value === 'system') {
    return value as ThemeMode;
  }
  return fallback;
}

function audioQualityOr(value: Object | undefined, fallback: AudioQuality): AudioQuality {
  if (value === 'high' || value === 'standard' || value === 'low') {
    return value as AudioQuality;
  }
  return fallback;
}

/**
 * 只接受预设档位：升级后若档位表变化，旧值回落到默认档，而不是留下无法在 UI 中选中的数。
 */
function downloadLimitOr(value: Object | undefined, fallback: number): number {
  if (typeof value === 'number' && DOWNLOAD_LIMIT_OPTIONS.indexOf(value as number) >= 0) {
    return value as number;
  }
  return fallback;
}

function settingsEqual(left: MobileSettings, right: MobileSettings): boolean {
  return left.version === right.version &&
    left.showLyrics === right.showLyrics &&
    left.restorePlayback === right.restorePlayback &&
    left.themeMode === right.themeMode &&
    left.audioQuality === right.audioQuality &&
    left.downloadQuality === right.downloadQuality &&
    left.downloadLimit === right.downloadLimit;
}

function cloneSettings(settings: MobileSettings): MobileSettings {
  return {
    version: settings.version,
    showLyrics: settings.showLyrics,
    restorePlayback: settings.restorePlayback,
    themeMode: settings.themeMode,
    audioQuality: settings.audioQuality,
    downloadQuality: settings.downloadQuality,
    downloadLimit: settings.downloadLimit
  };
}
