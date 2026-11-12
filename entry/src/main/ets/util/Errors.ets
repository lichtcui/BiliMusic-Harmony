import { AppError } from '../types/MobileTypes';

export const SAFE_UNKNOWN_ERROR_MESSAGE = '操作失败，请稍后重试。';
export const SAFE_UNKNOWN_FINAL_ERROR_MESSAGE = '操作无法完成，请返回后重试。';

const FALLBACK_ERROR_CODE = 'native.error';
const MAX_ERROR_CODE_LENGTH = 64;
const ERROR_CODE_PATTERN = /^[A-Za-z0-9._-]+$/;

const ERROR_MESSAGES: Record<string, string> = {
  'app.notReady': '应用尚未准备好，请稍后重试。',
  'app.initializeFailed': '应用初始化失败，请稍后重试。',
  'app.startupFailed': '应用启动失败，请稍后重试。',
  'app.runtimeUnavailable': '应用服务暂时不可用，请重启后再试。',
  'auth.required': '登录状态已失效，请重新登录。',
  'auth.statusFailed': '无法获取账号状态，请稍后重试。',
  'auth.qrGenerateFailed': '登录二维码生成失败，请稍后重试。',
  'auth.qrPollFailed': '无法获取登录状态，请稍后重试。',
  'auth.loginIncomplete': '登录未完成，请重新扫码。',
  'auth.networkUnavailable': '登录服务暂时不可用，请稍后重试。',
  'auth.httpStatus': '登录服务响应异常，请稍后重试。',
  'auth.invalidResponse': '登录服务返回了无法识别的数据。',
  'auth.redirectInvalid': '登录跳转地址无效。',
  'auth.redirectBlocked': '登录跳转已被安全策略阻止。',
  'cache.clearFailed': '缓存清理失败，请稍后重试。',
  'cache.statsFailed': '无法读取缓存信息，请稍后重试。',
  'catalog.discoverFailed': '暂时无法获取推荐音乐，请稍后重试。',
  'catalog.invalidQuery': '请输入有效的搜索关键词。',
  'catalog.notFound': '曲目不存在或已失效。',
  'catalog.recommendFailed': '暂时无法获取推荐音乐，请稍后重试。',
  'catalog.searchFailed': '搜索失败，请稍后重试。',
  'download.invalidTrack': '曲目信息不完整，无法下载。',
  'download.writeFailed': '下载文件保存失败，请稍后重试。',
  'http.blockedUrl': '已阻止不受信任的网络地址。',
  'http.invalidJson': '服务器返回了无法识别的数据。',
  'http.invalidUrl': '网络地址无效。',
  'http.notImage': '图片地址返回了无效内容。',
  'http.redirectLimit': '网络重定向次数过多。',
  'http.responseTooLarge': '响应数据超过大小限制。',
  'http.status': '网络请求失败，请稍后重试。',
  'http.unavailable': '网络连接失败，请稍后重试。',
  'image.cacheClearFailed': '图片缓存清理失败，请稍后重试。',
  'image.cacheStatsFailed': '无法读取图片缓存信息，请稍后重试。',
  'image.cacheWriteFailed': '图片缓存写入失败，请稍后重试。',
  'image.empty': '图片响应为空，请稍后重试。',
  'image.invalidMime': '图片格式不受支持。',
  'image.invalidResponse': '图片数据无效。',
  'image.tooLarge': '图片超过大小限制。',
  'library.corrupt': '本地资料已损坏，已使用默认数据。',
  'library.invalidTrack': '曲目信息不完整。',
  'library.playlistFull': '歌单曲目已达上限。',
  'library.playlistLimit': '歌单数量已达上限。',
  'library.playlistNotFound': '歌单不存在。',
  'library.unsupportedVersion': '本地资料版本不受支持，已使用默认数据。',
  'library.writeFailed': '本地资料保存失败，请稍后重试。',
  'lyrics.cacheClearFailed': '歌词缓存清理失败，请稍后重试。',
  'lyrics.cacheStatsFailed': '无法读取歌词缓存信息，请稍后重试。',
  'lyrics.fetchUnavailable': '歌词服务暂时不可用，请稍后重试。',
  'lyrics.searchUnavailable': '歌词搜索暂时不可用，请稍后重试。',
  'player.destroyed': '播放器已关闭。',
  'player.audioCacheClearFailed': '音频缓存清理失败，请稍后重试。',
  'player.invalidMediaUrl': '音频地址无效。',
  'player.invalidMode': '播放模式无效。',
  'player.invalidTrack': '曲目信息不完整。',
  'player.mediaCacheFailed': '无法保存音频缓存，请稍后重试。',
  'player.mediaDownloadFailed': '音频下载失败，请稍后重试。',
  'player.noAudioStream': '当前曲目没有可播放的音频流。',
  'player.noProgressiveStream': '当前曲目没有可回退的播放流。',
  'player.notReady': '播放器尚未准备好，请稍后重试。',
  'player.playbackFailed': '当前曲目播放失败，请稍后重试。',
  'player.playUrlFailed': '暂时无法获取播放地址，请稍后重试。',
  'player.prepareFailed': '音频暂时无法播放，请稍后重试。',
  'player.queueEmpty': '播放队列为空。',
  'player.queueFull': '播放队列已满（500 首），请先清理队列。',
  'player.sessionCorrupt': '播放会话数据已损坏，已恢复为空闲状态。',
  'player.sessionInvalid': '播放会话数据无效，已恢复为空闲状态。',
  'player.sessionUnsupportedVersion': '播放会话版本不受支持，已恢复为空闲状态。',
  'player.sessionWriteFailed': '播放会话保存失败，请稍后重试。',
  'player.stateFailed': '播放器状态异常，请稍后重试。',
  'player.stateTimeout': '播放器响应超时，请稍后重试。',
  'player.storeAlreadyBound': '播放器状态已经准备好。',
  'player.storeDisposed': '播放器状态已关闭。',
  'settings.invalidPreference': '设置值无效。',
  'settings.writeFailed': '设置保存失败，请稍后重试。',
  'wbi.keysUnavailable': '搜索服务暂时不可用，请稍后重试。'
};

export function sanitizeErrorCode(value: string): string {
  const code = value.trim();
  if (code.length === 0 || code.length > MAX_ERROR_CODE_LENGTH || !ERROR_CODE_PATTERN.test(code)) {
    return FALLBACK_ERROR_CODE;
  }
  return code;
}

export function errorMessageForCode(code: string, retryable: boolean = false): string {
  const safeCode = sanitizeErrorCode(code);
  const message = ERROR_MESSAGES[safeCode];
  if (message !== undefined) {
    return message;
  }
  return retryable ? SAFE_UNKNOWN_ERROR_MESSAGE : SAFE_UNKNOWN_FINAL_ERROR_MESSAGE;
}

export class NativeError extends Error {
  readonly appError: AppError;

  constructor(code: string, _message: string = '', retryable: boolean = false) {
    const safeCode = sanitizeErrorCode(code);
    super(errorMessageForCode(safeCode, retryable));
    this.name = 'NativeError';
    this.appError = {
      code: safeCode,
      message: errorMessageForCode(safeCode, retryable),
      retryable: retryable
    };
  }
}

export function appError(code: string, _message: string = '', retryable: boolean = false): AppError {
  const safeCode = sanitizeErrorCode(code);
  return {
    code: safeCode,
    message: errorMessageForCode(safeCode, retryable),
    retryable: retryable
  };
}

export function errorMessage(error: Object): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

export function toAppError(error: Object): AppError {
  if (error instanceof NativeError) {
    return appError(
      error.appError.code,
      error.appError.message,
      error.appError.retryable
    );
  }
  return appError(FALLBACK_ERROR_CODE, SAFE_UNKNOWN_FINAL_ERROR_MESSAGE, false);
}

export async function wait(milliseconds: number): Promise<void> {
  await new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, milliseconds);
  });
}
