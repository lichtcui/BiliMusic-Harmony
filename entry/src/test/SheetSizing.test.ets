import { describe, expect, it } from '@ohos/hypium';
import {
  SHEET_TOP_RESERVE,
  SheetSize,
  clampSheetHeight,
  collapsedSheetHeight,
  expandedSheetHeight,
  sheetSizeSpec
} from '../main/ets/components/native/SheetSizing';

const SCREEN_HEIGHT: number = 874;

function near(actual: number, expected: number): boolean {
  return Math.abs(actual - expected) < 0.001;
}

export default function sheetSizingTest(): void {
  describe('SheetSizing', () => {
    it('definesTheSharedSheetTiers', 0, () => {
      const small = sheetSizeSpec(SheetSize.Small);
      expect(small.heightPercent).assertEqual(28);
      expect(small.minHeight).assertEqual(232);
      expect(small.maxHeight).assertEqual(300);

      const compact = sheetSizeSpec(SheetSize.Compact);
      expect(compact.heightPercent).assertEqual(48);
      expect(compact.minHeight).assertEqual(392);
      expect(compact.maxHeight).assertEqual(440);

      const medium = sheetSizeSpec(SheetSize.Medium);
      expect(medium.heightPercent).assertEqual(59);
      expect(medium.minHeight).assertEqual(480);
      expect(medium.maxHeight).assertEqual(560);

      const large = sheetSizeSpec(SheetSize.Large);
      expect(large.heightPercent).assertEqual(78);
      expect(large.minHeight).assertEqual(560);
      expect(large.maxHeight).assertEqual(720);
    });

    it('keepsTheLoginTemplateGeometryOnAPhoneViewport', 0, () => {
      // 登录扫码抽屉（紧凑档）在 402×874 稿上是 48%，账号抽屉（小档）仍是 28%。
      expect(near(collapsedSheetHeight(SheetSize.Compact, SCREEN_HEIGHT), SCREEN_HEIGHT * 0.48)).assertTrue();
      expect(near(collapsedSheetHeight(SheetSize.Small, SCREEN_HEIGHT), SCREEN_HEIGHT * 0.28)).assertTrue();
      expect(near(collapsedSheetHeight(SheetSize.Medium, SCREEN_HEIGHT), SCREEN_HEIGHT * 0.59)).assertTrue();
      expect(near(collapsedSheetHeight(SheetSize.Large, SCREEN_HEIGHT), SCREEN_HEIGHT * 0.78)).assertTrue();
    });

    it('clampsTierHeightsToTheirDesignRange', 0, () => {
      // 高屏：中档被 560 上限截断；矮屏：中档被 480 下限抬起。
      expect(collapsedSheetHeight(SheetSize.Medium, 1200)).assertEqual(560);
      expect(collapsedSheetHeight(SheetSize.Medium, 600)).assertEqual(480);
      // 紧凑档：高屏封顶 440，矮屏抬到 392（仍然容得下扫码内容）。
      expect(collapsedSheetHeight(SheetSize.Compact, 1200)).assertEqual(440);
      expect(collapsedSheetHeight(SheetSize.Compact, 600)).assertEqual(392);
      expect(collapsedSheetHeight(SheetSize.Small, 1200)).assertEqual(300);
      expect(collapsedSheetHeight(SheetSize.Large, 1200)).assertEqual(720);
      // 容器比下限还矮时不允许溢出容器。
      expect(collapsedSheetHeight(SheetSize.Medium, 300)).assertEqual(300);
      expect(collapsedSheetHeight(SheetSize.Medium, 0)).assertEqual(0);
    });

    it('expandsToTheSafeAreaMinusTheTopReserve', 0, () => {
      // 展开态停在安全区下方：容器高度已经是安全区高度，再减去 16vp 留缝。
      expect(SHEET_TOP_RESERVE).assertEqual(16);
      expect(expandedSheetHeight(SCREEN_HEIGHT)).assertEqual(SCREEN_HEIGHT - SHEET_TOP_RESERVE);
      expect(expandedSheetHeight(-1)).assertEqual(0);
      expect(expandedSheetHeight(0)).assertEqual(0);
      // 容器比留白还矮时收敛到 0，不出现负高度。
      expect(expandedSheetHeight(10)).assertEqual(0);
    });

    it('clampsDragHeightsIntoTheTierRange', 0, () => {
      const expanded = expandedSheetHeight(SCREEN_HEIGHT);
      expect(clampSheetHeight(9999, 480, expanded)).assertEqual(expanded);
      expect(clampSheetHeight(0, 480, expanded)).assertEqual(480);
      expect(clampSheetHeight(600, 480, expanded)).assertEqual(600);
      // 参数写反时以 minimum 兜底，避免把 NaN 传给布局。
      expect(clampSheetHeight(Number.NaN, 100, 200)).assertEqual(100);
      expect(clampSheetHeight(150, 200, 100)).assertEqual(200);
    });
  });
}