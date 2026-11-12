import { describe, expect, it } from '@ohos/hypium';
import { AuthStatus } from '../main/ets/state/AuthStore';
import {
  accountAvatarInitial,
  hasActiveQrLogin,
  normalizedAccountName,
  shouldAutoStartLogin,
  shouldDismissLoginSheetOnSignIn,
  shouldStartLoginOnAppear
} from '../main/ets/components/native/LoginPageState';

export default function loginPageStateTest(): void {
  describe('LoginPageState', () => {
    it('autoStartsOnlyFromRecoverableSignedOutStates', 0, () => {
      expect(shouldAutoStartLogin('idle')).assertTrue();
      expect(shouldAutoStartLogin('cancelled')).assertTrue();
      expect(shouldAutoStartLogin('expired')).assertTrue();
      expect(shouldAutoStartLogin('error')).assertTrue();
      expect(shouldAutoStartLogin('starting')).assertFalse();
      expect(shouldAutoStartLogin('waiting')).assertFalse();
      expect(shouldAutoStartLogin('scanned')).assertFalse();
      expect(shouldAutoStartLogin('success')).assertFalse();
    });

    it('cleansUpOnlyActiveQrStates', 0, () => {
      const activeStates: AuthStatus[] = ['starting', 'waiting', 'scanned'];
      const inactiveStates: AuthStatus[] = [
        'idle', 'success', 'expired', 'cancelled', 'error'
      ];
      activeStates.forEach((status: AuthStatus): void => {
        expect(hasActiveQrLogin(status)).assertTrue();
      });
      inactiveStates.forEach((status: AuthStatus): void => {
        expect(hasActiveQrLogin(status)).assertFalse();
      });
    });

    it('gatesAutomaticQrStartForSmokeFixtures', 0, () => {
      const statuses: AuthStatus[] = [
        'idle', 'starting', 'waiting', 'scanned', 'success', 'expired', 'cancelled', 'error'
      ];
      statuses.forEach((status: AuthStatus): void => {
        expect(shouldStartLoginOnAppear(status)).assertEqual(shouldAutoStartLogin(status));
        expect(shouldStartLoginOnAppear(status, true)).assertEqual(shouldAutoStartLogin(status));
        expect(shouldStartLoginOnAppear(status, false)).assertFalse();
      });
    });

    it('dismissesOnlyAfterScanSignIn', 0, () => {
      // 未登录打开 -> 扫码成功：收起抽屉。
      expect(shouldDismissLoginSheetOnSignIn(true, true)).assertTrue();
      // 未登录打开、仍在扫码：不收起。
      expect(shouldDismissLoginSheetOnSignIn(true, false)).assertFalse();
      // 已登录打开账号抽屉（看账号 / 退出登录）：不能被自动收起。
      expect(shouldDismissLoginSheetOnSignIn(false, true)).assertFalse();
      expect(shouldDismissLoginSheetOnSignIn(false, false)).assertFalse();
    });

    it('normalizesAccountIdentityForDisplay', 0, () => {
      expect(normalizedAccountName('  Alice  ')).assertEqual('Alice');
      expect(normalizedAccountName('   ')).assertEqual('Bilibili');
      expect(normalizedAccountName('', 'User')).assertEqual('User');
      expect(accountAvatarInitial(' alice ')).assertEqual('A');
      expect(accountAvatarInitial('')).assertEqual('B');
      expect(accountAvatarInitial('', 'U')).assertEqual('U');
    });
  });
}
