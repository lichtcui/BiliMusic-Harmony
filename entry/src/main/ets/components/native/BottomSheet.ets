import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { NativeUiIds } from './NativeUiIds';
import {
  SheetSize,
  clampSheetHeight,
  collapsedSheetHeight,
  expandedSheetHeight,
  sheetSizeSpec
} from './SheetSizing';

const SHEET_MAX_WIDTH: number = 520;
/** 未测量到宿主高度前的高度上限：只用于避免第一帧被旧上限截断，测量后立刻改成展开高度。 */
const SHEET_UNBOUNDED: number = 4096;

/* --------------------------------------------------------------------------
 * chrome：全仓抽屉只认这一套（模板 = 登录抽屉，2026-11「我的」页新稿）
 * ------------------------------------------------------------------------ */
const SHEET_HANDLE_WIDTH: number = 36;
const SHEET_HANDLE_HEIGHT: number = 4;
/** 拖拽条的无障碍点按热区（视觉仍是 36×4；热区扩到 64×40 后点按即关闭）。 */
const SHEET_HANDLE_TOUCH_WIDTH: number = 64;
const SHEET_HANDLE_TOUCH_HEIGHT: number = 40;
const SHEET_TITLE_SIZE: number = 20;
const SHEET_HEADER_HEIGHT: number = 36;
const SHEET_HEADER_WITH_SUBTITLE_HEIGHT: number = 56;
const SHEET_HEADER_GAP: number = ThemeSpacing.md;
/** 左右内边距：402 宽稿件实测 28。 */
const SHEET_GUTTER: number = ThemeSpacing.xxl;
const SHEET_TOP_RADIUS: number = ThemeRadius.sheet;

/** 上拉展开的吸附动画时长与跟手距离（vp）；速度阈值用于「快速一甩」也能展开 / 收起。 */
const SHEET_EXPAND_DURATION: number = 220;
const SHEET_DRAG_DISTANCE: number = 8;
const SHEET_EXPAND_VELOCITY: number = 420;
/** 下滑关闭：拖过折叠高度后的跟手距离 / 松手速度阈值（vp、vp/s）。 */
const SHEET_DISMISS_DISTANCE: number = 96;
const SHEET_DISMISS_VELOCITY: number = 1000;

/**
 * 全仓唯一的底部抽屉外壳。
 *
 * 2026-11 起所有抽屉（登录 / 曲目操作 / 诊断信息 / 歌词换源等）都走这一层，
 * 样式只在这里定义一次，调用方不再传字号、底色、圆角、内边距这些逐稿参数：
 *
 * - 头部：标题 20 粗（左对齐，无右上关闭按钮）、头部高 36、左右 28；
 *   `title` 与 `subtitle` 都为空时头部整块不渲染（只剩拖拽条），用于无标题抽屉；
 * - 外壳：顶边 28 圆角、登录抽屉底色、中央拖拽条；蒙层点击、拖拽条点按与下滑
 *   都收敛到 `onClose`；
 * - 档位：`sheetSize` 取 `SheetSize` 四档（小 / 紧凑 / 中 / 大），高度只由 `SheetSizing` 决定；
 * - 上拉：四档都能从拖拽条 / 头部上拉，松手按距离或速度吸附到展开态；
 *   展开态停在安全区下方 16vp，圆角全程保持 28，不再收敛成方角；
 * - 下滑：从折叠态继续下拉会跟手位移，松手时拖过阈值或快速下滑即关闭；
 * - 安全区：蒙层绘制扩到状态栏 + 导航条；面板只向下扩展绘制到底部导航条，
 *   顶部不再铺进状态栏，因此顶部始终露出一条蒙层缝，底部按钮也不会压进系统手势区。
 *
 * 承载方式走 Stack 覆盖而不是 `bindSheet`：`bindSheet` 是系统半模态，`expandSafeArea`
 * 对它不生效，安全区会露白。拖拽区只放在拖拽条 + 头部，避免和抽屉内的列表滚动抢手势。
 *
 * 调用方必须用**尾随闭包**给 `contentBuilder` 传值（`BottomSheet({...}) { this.Content() }`），
 * 不要用 `contentBuilder: this.Content`：函数引用在子组件里执行时 this 会变成 BottomSheet
 * 实例，Content 内部再调其它 @Builder 就变成 undefined.bind(...) → TypeError → 应用退出。
 */
@Component
export struct BottomSheet {
  @Prop sheetId: string;
  /** 标题；空串表示这个抽屉不显示标题（头部整块收起，只剩拖拽条）。 */
  @Prop title: ResourceStr = '';
  /** 标题下方的副标题（如合集名 / 曲目数）；空串表示单行头部。 */
  @Prop subtitle: string = '';
  /** 高度档位：小 / 紧凑 / 中 / 大。默认中档。属性名不能叫 `size`：会和通用属性 `size()` 冲突。 */
  @Prop sheetSize: SheetSize = SheetSize.Medium;
  /**
   * 面板垂直位移（vp）：宿主在挂载前设成屏高、挂载后动画回 0，即从底部滑入。
   * 默认 0，未驱动进出场的抽屉保持原来的瞬时出现。
   */
  @Prop panelOffsetY: number = 0;
  /** 蒙层不透明度（0–1）；与 `panelOffsetY` 一起做进出场，默认 1 保持旧行为。 */
  @Prop scrimAlpha: number = 1;
  onClose: () => void = (): void => {};
  @BuilderParam contentBuilder: () => void = this.EmptyContent;

  /** 宿主 Stack 的实测高度，用于把百分比高度换算成可跟手的数值高度。 */
  @State private containerHeight: number = 0;
  /** 拖拽中的实时高度（vp）。 */
  @State private dragHeight: number = 0;
  /** 当前是否停在展开态。 */
  @State private expanded: boolean = false;
  @State private dragging: boolean = false;
  /** 本次拖拽开始时的高度，用来把手指位移换算成绝对高度。 */
  private dragOriginHeight: number = 0;
  /** 折叠态以下的下拉位移（vp）：跟手预览关闭，松手后归零或触发 `onClose`。 */
  @State private dismissOffset: number = 0;

  @Builder
  EmptyContent() {
    Column()
      .width('100%')
      .layoutWeight(1)
  }

  @Builder
  SheetHeader() {
    // 标题与副标题都为空时整块头部不渲染：不留空白高度，也不留头部上边距。
    if (this.title !== '' || this.subtitle !== '') {
      Row() {
        Column({ space: 2 }) {
          if (this.title !== '') {
            Text(this.title)
              .width('100%')
              .fontSize(SHEET_TITLE_SIZE)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeColors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.subtitle !== '') {
            Text(this.subtitle)
              .width('100%')
              .fontSize(ThemeTypography.eyebrow)
              .fontColor(ThemeColors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(this.subtitle !== '' ? SHEET_HEADER_WITH_SUBTITLE_HEIGHT : SHEET_HEADER_HEIGHT)
      .margin({ top: SHEET_HEADER_GAP })
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .id(NativeUiIds.sheetScrim(this.sheetId))
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeColors.scrim)
        .opacity(this.scrimAlpha)
        // 蒙层必须盖住状态栏 / 导航条：这两个区域默认在页面安全区之外，
        // 不扩展的话抽屉打开时上、下会各露一条系统背景。
        // expandSafeArea 只扩展绘制范围、不改变布局，因此不动抽屉内容的坐标。
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          this.onClose();
        })

      Column() {
        Column() {
          Row()
            .id(NativeUiIds.sheetHandle(this.sheetId))
            .width(SHEET_HANDLE_WIDTH)
            .height(SHEET_HANDLE_HEIGHT)
            .borderRadius(SHEET_HANDLE_HEIGHT / 2)
            .backgroundColor(ThemeColors.sheetHandle)
            .margin({ top: ThemeSpacing.sm, bottom: ThemeSpacing.xs })
            // 视觉仍是 36×4 的拖拽条；热区扩到 64×40，点按即关闭。
            // 这里是无障碍兜底：删掉右上角 × 之后，读屏用户需要一个可聚焦的关闭入口。
            .responseRegion({
              x: -(SHEET_HANDLE_TOUCH_WIDTH - SHEET_HANDLE_WIDTH) / 2,
              y: -(SHEET_HANDLE_TOUCH_HEIGHT - SHEET_HANDLE_HEIGHT) / 2,
              width: SHEET_HANDLE_TOUCH_WIDTH,
              height: SHEET_HANDLE_TOUCH_HEIGHT
            })
            .onClick(() => {
              this.onClose();
            })
            .accessibilityText($r('app.string.sheet_close'))
            .accessibilityLevel('yes')

          this.SheetHeader()
        }
        .width('100%')
        // 只把拖拽区放在拖拽条 + 头部：抽屉里的列表还要自己上下滚，
        // 若把 PanGesture 挂到整块面板，展开手势会和列表滚动抢事件。
        .gesture(
          PanGesture({ direction: PanDirection.Vertical, distance: SHEET_DRAG_DISTANCE })
            .onActionStart(() => {
              this.beginExpandDrag();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.updateExpandDrag(event.offsetY);
            })
            .onActionEnd((event: GestureEvent) => {
              this.endExpandDrag(event.offsetY, event.velocityY);
            })
            .onActionCancel(() => {
              this.cancelExpandDrag();
            })
        )

        Column() {
          this.contentBuilder()
        }
        .width('100%')
        .layoutWeight(1)
      }
      .id(this.sheetId)
      .width('100%')
      .height(this.resolvedHeight())
      .constraintSize({
        minHeight: this.panelMinHeight(),
        maxWidth: SHEET_MAX_WIDTH,
        maxHeight: this.panelMaxHeight()
      })
      .padding({
        left: SHEET_GUTTER,
        right: SHEET_GUTTER,
        top: ThemeSpacing.xs,
        bottom: ThemeSpacing.md
      })
      .safeAreaPadding({ bottom: ThemeSpacing.sm })
      .backgroundColor(ThemeColors.loginSheetSurface)
      // 顶部圆角全程保持 28（M3 大弹层口径）：展开态也停在安全区下方，不再收敛成方角。
      .borderRadius({ topLeft: SHEET_TOP_RADIUS, topRight: SHEET_TOP_RADIUS })
      .translate({ y: this.panelOffsetY + this.dismissOffset })
      // 面板底色只延伸进底部导航条（Home 指示条）：只扩展绘制，内容仍停在安全区内，
      // 与 `safeAreaPadding` 配合时不会把按钮压到系统手势区。
      // 顶部不再向状态栏扩展——面板顶边停在安全区下方，留出一条蒙层缝。
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .zIndex(10)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.containerHeight = newValue.height as number;
    })
  }

  /**
   * 折叠 / 展开 / 拖拽中的实际高度。
   *
   * 这里**必须输出百分比**，不能把算好的 vp 数值直接交给 `.height()`：
   * `expandSafeArea` 对固定尺寸（数值 / auto）只支持 TOP / START 两个方向，
   * 固定高度会让面板底的 `expandSafeArea([BOTTOM])` 失效——展开后高度是算出来的数值，
   * 底部导航条区域就盖不住，面板下方会露一条蒙层灰。
   */
  private resolvedHeight(): Length {
    if (this.containerHeight <= 0) {
      return `${sheetSizeSpec(this.sheetSize).heightPercent}%`;
    }
    const height = this.dragging ? this.dragHeight
      : (this.expanded ? this.maxExpandedHeight() : this.collapsedHeight());
    return `${height / this.containerHeight * 100}%`;
  }

  /** 折叠态高度（vp）：档位百分比 + 档位钳制，不超过容器。 */
  private collapsedHeight(): number {
    return collapsedSheetHeight(this.sheetSize, this.containerHeight);
  }

  private maxExpandedHeight(): number {
    return expandedSheetHeight(this.containerHeight);
  }

  /** 测量完成前不设上限，避免第一帧被档位的折叠上限截断。 */
  private panelMaxHeight(): number {
    if (this.containerHeight > 0) {
      return this.maxExpandedHeight();
    }
    return SHEET_UNBOUNDED;
  }

  /** 档位下限；容器比下限还矮（横屏 / 小窗）时以容器为准，避免面板顶出屏幕。 */
  private panelMinHeight(): number {
    const minimum = sheetSizeSpec(this.sheetSize).minHeight;
    if (this.containerHeight > 0 && minimum > this.containerHeight) {
      return this.containerHeight;
    }
    return minimum;
  }

  private beginExpandDrag(): void {
    if (this.containerHeight <= 0) {
      return;
    }
    this.dragOriginHeight = this.expanded ? this.maxExpandedHeight() : this.collapsedHeight();
    this.dragHeight = this.dragOriginHeight;
    this.dragging = true;
  }

  private updateExpandDrag(offsetY: number): void {
    if (!this.dragging) {
      return;
    }
    const minimum = this.collapsedHeight();
    const raw = this.dragOriginHeight - offsetY;
    this.dragHeight = clampSheetHeight(raw, minimum, this.maxExpandedHeight());
    // 折叠态以下不再缩高度（档位下限不允许），改成把整块面板往下挪，跟手预览关闭。
    this.dismissOffset = Math.max(0, minimum - raw);
  }

  private endExpandDrag(offsetY: number, velocityY: number): void {
    if (!this.dragging) {
      return;
    }
    const minimum = this.collapsedHeight();
    const maximum = this.maxExpandedHeight();
    const raw = this.dragOriginHeight - offsetY;
    const height = clampSheetHeight(raw, minimum, maximum);
    const overshoot = Math.max(0, minimum - raw);
    // 拖过折叠高度足够远，或在已经拖过折叠高度后快速下滑：直接关闭；
    // 面板停在当前位置，交给宿主的收起动画。快速下滑若仍停在折叠档以上，只吸附收起。
    if (overshoot > SHEET_DISMISS_DISTANCE ||
      (overshoot > 0 && velocityY > SHEET_DISMISS_VELOCITY)) {
      // 收起时把展开标记复位：否则高度会先跳回展开档，再跟宿主一起滑出。
      this.dragging = false;
      this.expanded = false;
      this.onClose();
      return;
    }
    let expand = height >= (minimum + maximum) / 2;
    if (velocityY < -SHEET_EXPAND_VELOCITY) {
      expand = true;
    } else if (velocityY > SHEET_EXPAND_VELOCITY) {
      expand = false;
    }
    this.settleExpandDrag(expand);
  }

  private cancelExpandDrag(): void {
    if (!this.dragging) {
      return;
    }
    this.settleExpandDrag(this.expanded);
  }

  private settleExpandDrag(expand: boolean): void {
    this.getUIContext().animateTo({ duration: SHEET_EXPAND_DURATION, curve: Curve.EaseOut }, () => {
      this.dragging = false;
      this.expanded = expand;
      this.dismissOffset = 0;
    });
  }
}