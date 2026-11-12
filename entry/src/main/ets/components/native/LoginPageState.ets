import { AuthStatus, AuthStore } from '../../state/AuthStore';

export function shouldAutoStartLogin(status: AuthStatus): boolean {
  return status === 'idle' ||
    status === 'cancelled' ||
    status === 'expired' ||
    status === 'error';
}

export function shouldStartLoginOnAppear(status: AuthStatus,
  autoStartQrLoginOnAppear: boolean = true): boolean {
  return autoStartQrLoginOnAppear && shouldAutoStartLogin(status);
}

export function hasActiveQrLogin(status: AuthStatus): boolean {
  return status === 'starting' ||
    status === 'waiting' ||
    status === 'scanned';
}

/**
 * 扫码登录成功后抽屉是否应当自己收起。
 *
 * 只认「这次打开抽屉时是未登录」：已登录再打开账号抽屉（看账号 / 退出登录）
 * 不能被自动关掉。收起动作本身走宿主动画，确认后不再切换成账号抽屉内容。
 */
export function shouldDismissLoginSheetOnSignIn(startedSignedOut: boolean,
  isLoggedIn: boolean): boolean {
  return startedSignedOut && isLoggedIn;
}

/**
 * 关闭登录抽屉（08）时的唯一收尾动作：正在跑的二维码轮询必须**显式**取消。
 *
 * 不能依赖条件渲染下的 `aboutToDisappear`——触发时机未实测，漏掉就会出现
 * "抽屉关了、2s 轮询还在跑"（抽屉关闭的实现约束）。幂等：
 * 状态不活跃时返回 `false` 且不触碰 `AuthStore`。
 */
export function closeLoginSheetSession(store: AuthStore): boolean {
  if (!hasActiveQrLogin(store.snapshot.status)) {
    return false;
  }
  store.cancelQrLogin();
  return true;
}

export function normalizedAccountName(name: string, fallback: string = 'Bilibili'): string {
  const normalized = name.trim();
  return normalized.length > 0 ? normalized : fallback;
}

export function accountAvatarInitial(name: string, fallback: string = 'B'): string {
  const normalized = name.trim();
  return normalized.length > 0 ? normalized.slice(0, 1).toUpperCase() : fallback;
}
