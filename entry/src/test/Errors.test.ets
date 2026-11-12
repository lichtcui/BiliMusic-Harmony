import { describe, expect, it } from '@ohos/hypium';
import {
  appError,
  errorMessage,
  errorMessageForCode,
  toAppError,
  NativeError,
  SAFE_UNKNOWN_FINAL_ERROR_MESSAGE,
  sanitizeErrorCode,
  SAFE_UNKNOWN_ERROR_MESSAGE
} from '../main/ets/util/Errors';

export default function errorsTest(): void {
  describe('Errors', () => {
    it('createsAppError', 0, () => {
      const error = appError('auth.required', 'token=private-value', false);

      expect(error.code).assertEqual('auth.required');
      expect(error.message).assertEqual('登录状态已失效，请重新登录。');
      expect(error.message.includes('private-value')).assertFalse();
      expect(error.retryable).assertFalse();
    });

    it('replacesNativeErrorCopy', 0, () => {
      const nativeError = new NativeError('player.noAudioStream', 'cookie=private-value', true);
      const error = toAppError(nativeError);

      expect(errorMessage(nativeError)).assertEqual('当前曲目没有可播放的音频流。');
      expect(error.code).assertEqual('player.noAudioStream');
      expect(error.message).assertEqual('当前曲目没有可播放的音频流。');
      expect(error.retryable).assertTrue();
    });

    it('mapsAuthenticationRequiredToSafeCopy', 0, () => {
      const error = toAppError(new NativeError('auth.required', 'mid=private-value'));

      expect(error.code).assertEqual('auth.required');
      expect(error.message).assertEqual('登录状态已失效，请重新登录。');
      expect(error.retryable).assertFalse();
    });

    it('mapsRateLimitToSafeCopy', 0, () => {
      const error = toAppError(
        new NativeError('catalog.searchFailed', 'api status=412 private-value', true)
      );

      expect(error.code).assertEqual('catalog.searchFailed');
      expect(error.message).assertEqual('搜索失败，请稍后重试。');
      expect(error.retryable).assertTrue();
    });

    it('mapsTimeoutToSafeCopy', 0, () => {
      const error = toAppError(new NativeError('http.unavailable', 'host=private-value', true));

      expect(error.code).assertEqual('http.unavailable');
      expect(error.message).assertEqual('网络连接失败，请稍后重试。');
      expect(error.retryable).assertTrue();
    });

    it('usesNonRetryableCopyForUnknownErrors', 0, () => {
      const error = toAppError(new Error('socket closed /private/token'));

      expect(error.code).assertEqual('native.error');
      expect(error.message).assertEqual(SAFE_UNKNOWN_FINAL_ERROR_MESSAGE);
      expect(error.message.includes('/private/token')).assertFalse();
      expect(error.retryable).assertFalse();
    });

    it('selectsUnknownFallbackByRetryability', 0, () => {
      const retryable = toAppError(new NativeError('diagnostics.unknown', 'secret', true));
      const finalError = toAppError(new NativeError('diagnostics.unknown', 'secret', false));

      expect(retryable.message).assertEqual(SAFE_UNKNOWN_ERROR_MESSAGE);
      expect(finalError.message).assertEqual(SAFE_UNKNOWN_FINAL_ERROR_MESSAGE);
      expect(retryable.message.includes('secret')).assertFalse();
      expect(finalError.message.includes('secret')).assertFalse();
    });

    it('sanitizesInvalidCodes', 0, () => {
      expect(sanitizeErrorCode(' auth.required ')).assertEqual('auth.required');
      expect(sanitizeErrorCode('bad code /private')).assertEqual('native.error');
      expect(sanitizeErrorCode('x'.repeat(65))).assertEqual('native.error');
      expect(errorMessageForCode('bad code', true)).assertEqual(SAFE_UNKNOWN_ERROR_MESSAGE);
    });

    it('mapsPlaybackSessionFailuresToSafeCopy', 0, () => {
      expect(errorMessageForCode('player.sessionCorrupt', true))
        .assertEqual('播放会话数据已损坏，已恢复为空闲状态。');
      expect(errorMessageForCode('player.sessionInvalid', false))
        .assertEqual('播放会话数据无效，已恢复为空闲状态。');
      expect(errorMessageForCode('player.sessionUnsupportedVersion', false))
        .assertEqual('播放会话版本不受支持，已恢复为空闲状态。');
      expect(errorMessageForCode('player.sessionWriteFailed', true))
        .assertEqual('播放会话保存失败，请稍后重试。');
    });
  });
}
