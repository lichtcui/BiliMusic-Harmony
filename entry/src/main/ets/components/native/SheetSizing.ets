/**
 * 抽屉档位与几何计算（纯函数，无 ArkUI 资源依赖，宿主测试可直接覆盖）。
 *
 * 全仓抽屉只有四个档位，档位是**唯一**的高度来源：调用方不再各自写
 * `heightPercent` / `minHeight` / `maxHeight`，避免同一张稿子在两处各调一次。
 * 数值来自 2026-11 的登录抽屉模板与既有稿件的实测值：
 *
 * - 小（Small）：28% / 232–300 —— 登录账号抽屉（稿件 clamp(232, 28%, 260)）
 * - 紧凑（Compact）：48% / 392–440 —— 登录扫码（去掉底部「取消登录」后的内容高度）
 * - 中（Medium）：59% / 480–560 —— 歌词换源、编辑歌单、缓存清理
 * - 大（Large）：78% / 560–720 —— 诊断信息、曲目操作
 *
 * 四档都支持从拖拽条 / 头部上拉展开。展开态不再铺满整屏：面板顶边停在安全区
 * 下方 `SHEET_TOP_RESERVE` 处，配合 28 圆角与蒙层形成悬空弹层的交界效果。
 * 历史上的「全屏」档（100%、方角）已删除——它没有调用方，且与新规则冲突。
 */
export enum SheetSize {
  Small = 0,
  Compact = 1,
  Medium = 2,
  Large = 3
}

export interface SheetSizeSpec {
  /** 折叠态高度占宿主容器高度的百分比。 */
  heightPercent: number;
  /** 折叠态最小高度（vp）；0 表示不限制。 */
  minHeight: number;
  /** 折叠态最大高度（vp）；0 表示不限制。 */
  maxHeight: number;
}

/**
 * 展开态与安全区上沿的留白（vp）。
 *
 * 宿主容器本身就是安全区高度，所以展开高度要再减掉这一条：面板顶边始终停在
 * 状态栏下方，留出一条可见、可点的蒙层缝。数值取 16（与主题的 `lg` 间距一致）。
 */
export const SHEET_TOP_RESERVE: number = 16;

const SMALL_SPEC: SheetSizeSpec = {
  heightPercent: 28,
  minHeight: 232,
  maxHeight: 300
};

const COMPACT_SPEC: SheetSizeSpec = {
  heightPercent: 48,
  minHeight: 392,
  maxHeight: 440
};

const MEDIUM_SPEC: SheetSizeSpec = {
  heightPercent: 59,
  minHeight: 480,
  maxHeight: 560
};

const LARGE_SPEC: SheetSizeSpec = {
  heightPercent: 78,
  minHeight: 560,
  maxHeight: 720
};

/** 档位 → 高度规格。 */
export function sheetSizeSpec(size: SheetSize): SheetSizeSpec {
  if (size === SheetSize.Small) {
    return SMALL_SPEC;
  }
  if (size === SheetSize.Compact) {
    return COMPACT_SPEC;
  }
  if (size === SheetSize.Large) {
    return LARGE_SPEC;
  }
  return MEDIUM_SPEC;
}

/** 档位 → 折叠态高度（vp）；容器尚未测量时为 0。 */
export function collapsedSheetHeight(size: SheetSize, containerHeight: number): number {
  const container = Number.isFinite(containerHeight) ? Math.max(0, containerHeight) : 0;
  if (container <= 0) {
    return 0;
  }
  const spec = sheetSizeSpec(size);
  const byPercent = container * spec.heightPercent / 100;
  const capped = spec.maxHeight > 0 ? Math.min(byPercent, spec.maxHeight) : byPercent;
  const floored = spec.minHeight > 0 ? Math.max(capped, spec.minHeight) : capped;
  return Math.min(floored, container);
}

/**
 * 展开态高度（vp）= 宿主容器高度 − 顶部留白。
 *
 * `containerHeight` 已经是安全区高度（根 Stack 在安全区内），减掉留白后面板顶边
 * 仍停在状态栏下方，不再用 `expandSafeArea` 把底色铺进状态栏。
 */
export function expandedSheetHeight(containerHeight: number): number {
  const container = Number.isFinite(containerHeight) ? Math.max(0, containerHeight) : 0;
  return Math.max(0, container - SHEET_TOP_RESERVE);
}

/** 把数值限制在 [minimum, maximum]；参数写反时以 minimum 兜底。 */
export function clampSheetHeight(value: number, minimum: number, maximum: number): number {
  const low = Number.isFinite(minimum) ? minimum : 0;
  const high = Number.isFinite(maximum) ? Math.max(maximum, low) : low;
  const current = Number.isFinite(value) ? value : low;
  return Math.min(Math.max(current, low), high);
}