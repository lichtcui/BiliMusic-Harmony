import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { NativeAppRuntime } from '../app/NativeAppRuntime';
import { SettingsStore, ThemeMode } from '../state/SettingsStore';

const DOMAIN = 0x424D;
const TAG = 'WispMusicHarmonyOS';

export default class EntryAbility extends UIAbility {
  private nativeRuntime: NativeAppRuntime | null = null;
  private shutdownStarted: boolean = false;
  private shutdownPromise: Promise<void> | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility created, reason=%{public}d', launchParam.launchReason);
    let themeMode: ThemeMode = 'system';
    try {
      themeMode = new SettingsStore(`${this.context.filesDir}/settings-v1.json`).read().themeMode;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'settings read before first frame failed; following system theme');
    }
    this.applyThemeMode(themeMode);
    const runtime = new NativeAppRuntime(this.context, (mode: ThemeMode): void => {
      this.applyThemeMode(mode);
    });
    this.nativeRuntime = runtime;
    AppStorage.setOrCreate<NativeAppRuntime>('nativeAppRuntime', runtime);
    // 启动的关键路径从「页面首帧之后」提前到进程创建：Index 复用同一个 in-flight
    // Promise（NativeAppRuntime.initialize 自带去重），窗口创建 / 首帧这段时间就已在
    // 加载本地存储与登录态，快速冷启动时不再需要一屏「正在准备音乐」。
    void runtime.initialize().catch((error: Object): void => {
      const message = error instanceof Error ? error.message : 'unknown';
      hilog.error(DOMAIN, TAG, 'early native runtime initialize failed message=%{public}s', message);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 启动页图标要与系统启动窗口一样落在整屏中心；页面内容区会被状态栏/导航条内缩，
    // 不同机型的上下安全区不同，这里把实际 insets 交给 Index 动态计算偏移。
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const systemArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicatorArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topPx = systemArea.topRect.height;
      const bottomPx = Math.max(systemArea.bottomRect.height, indicatorArea.bottomRect.height);
      AppStorage.setOrCreate<number>('startupSafeTopPx', topPx);
      AppStorage.setOrCreate<number>('startupSafeBottomPx', bottomPx);
      hilog.info(DOMAIN, TAG, 'startup safe area top=%{public}d bottom=%{public}d indicator=%{public}d',
        topPx, bottomPx, indicatorArea.bottomRect.height);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'read startup safe area failed; using centered splash');
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed, code=%{public}d message=%{public}s',
          err.code, err.message);
        return;
      }
      hilog.info(DOMAIN, TAG, 'Index page loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Window stage destroyed');
  }

  onDestroy(): void {
    const runtime = this.nativeRuntime;
    AppStorage.delete('nativeAppRuntime');
    this.nativeRuntime = null;
    const shutdown = this.shutdownOnce(runtime);
    void shutdown.catch((error: Object): void => {
      const message = error instanceof Error ? error.message : 'unknown';
      hilog.error(DOMAIN, TAG, 'native runtime shutdown failed message=%{public}s', message);
    });
    hilog.info(DOMAIN, TAG, 'EntryAbility destroyed');
  }

  private applyThemeMode(mode: ThemeMode): void {
    let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === 'light') {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (mode === 'dark') {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    try {
      this.context.getApplicationContext().setColorMode(colorMode);
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'setColorMode unsupported code=%{public}d', businessError.code);
    }
  }

  private shutdownOnce(runtime: NativeAppRuntime | null): Promise<void> {
    if (this.shutdownStarted) {
      return this.shutdownPromise ?? Promise.resolve();
    }
    this.shutdownStarted = true;
    const shutdown = runtime === null ? Promise.resolve() : runtime.shutdown();
    this.shutdownPromise = shutdown;
    return shutdown;
  }
}
