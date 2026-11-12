import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { NativeAppRuntime } from '../main/ets/app/NativeAppRuntime';
import { NativeError } from '../main/ets/util/Errors';

class FakeRuntimeContext {
  readonly filesDir: string = '/tmp/wisp-music-runtime-test/files';
  readonly cacheDir: string = '/tmp/wisp-music-runtime-test/cache';
}

function newRuntime(): NativeAppRuntime {
  const context = new FakeRuntimeContext() as Object as common.UIAbilityContext;
  return new NativeAppRuntime(context);
}

export default function nativeAppRuntimeTest(): void {
  describe('NativeAppRuntime', () => {
    it('startsIdleAndStopsWithoutEverInitializing', 0, async () => {
      const runtime = newRuntime();

      const initial = runtime.snapshot();
      expect(initial.state).assertEqual('idle');
      expect(initial.error === null).assertTrue();
      expect(initial.warnings.length).assertEqual(0);

      await runtime.shutdown();

      const stopped = runtime.snapshot();
      expect(stopped.state).assertEqual('stopped');
      expect(stopped.error === null).assertTrue();
      expect(stopped.warnings.length).assertEqual(0);
    });

    it('keepsARetiredRuntimeRetiredWhenAskedToInitializeAgain', 0, async () => {
      const runtime = newRuntime();
      await runtime.shutdown();

      const snapshot = await runtime.initialize();
      expect(snapshot.state).assertEqual('stopped');
      const retried = await runtime.retry();
      expect(retried.state).assertEqual('stopped');
    });

    it('rejectsBusinessCallsWithNotReadyAfterShutdown', 0, async () => {
      const runtime = newRuntime();
      await runtime.shutdown();

      let code = '';
      try {
        await runtime.search('keyword');
      } catch (error) {
        code = error instanceof NativeError ? error.appError.code : '';
      }
      expect(code).assertEqual('app.notReady');

      const image = await runtime.loadImage('https://i0.hdslb.com/bfs/face/a.jpg');
      expect(image === null).assertTrue();
    });
  });
}
