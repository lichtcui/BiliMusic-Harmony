/**
 * 宿主驱动的覆盖层进出场状态。
 *
 * 为什么由宿主驱动而不是外壳自己动：面板的初始屏外位移必须在**挂载前**就写进 prop，
 * 否则第一帧会先出现在最终位置、再瞬移下去。宿主持有根 Stack 的实测宽 / 高，所以能在
 * 挂载前把 `offset` 设成屏外；包裹层 `onAppear` 之后再滑回 0。退场同理：先滑出、
 * 动画 `onFinish` 后才卸载，只翻 `visible` 会丢掉动画。
 *
 * 设置整页、播放控制整页、登录 / 诊断 / 缓存 / 免责声明 / 定时关闭 / 音质 / 曲目操作 /
 * 新建与编辑歌单抽屉共用这一份状态与世代戳，页面只负责「何时开、何时关」和副作用。
 *
 * 注意：本类用 `@Observed` 且**不给任何字段加 `@Track`**，因此所有字段都可被 UI 读取并
 * 参与刷新（`@Observed` + `@Track` 的类在 build 里读未 `@Track` 字段会抛 140110）。
 * 属性写入必须整体赋值或直接改字段，才能被代理观察到。
 */

/** 宿主注入的动画执行器：第一个参数写目标状态，第二个参数在动画结束后回调。 */
export type OverlayAnimator = (apply: () => void, onFinish?: () => void) => void;

@Observed
export class OverlayMotion {
  /** 是否已挂载；关闭动画结束前保持 true，动画结束才卸载。 */
  visible: boolean = false;
  /** 面板位移（vp）：隐藏时等于屏高 / 屏宽，展示时为 0。 */
  offset: number = 0;
  /** 蒙层不透明度（0–1）；整页覆盖层不使用蒙层，保持 1。 */
  scrimAlpha: number = 1;
  /**
   * 世代戳：关闭动画结束前又被重新打开时，旧动画的 `onFinish` 不允许再卸载组件
   * （否则页面会停在滑出的位置被直接移除）。
   */
  private generation: number = 0;

  /**
   * 打开：已挂载（上一次关闭动画还没播完）时直接滑回；
   * 否则先按隐藏位移挂载，等组件 `onAppear` 再调用 `enter()` 滑入（两步才看得见动画）。
   */
  open(hiddenOffset: number, animate: OverlayAnimator): void {
    this.generation += 1;
    if (this.visible) {
      animate((): void => {
        this.offset = 0;
        this.scrimAlpha = 1;
      });
      return;
    }
    this.offset = hiddenOffset;
    this.scrimAlpha = 0;
    this.visible = true;
  }

  /** 组件首次挂载后的滑入；由包裹层的 `onAppear` 触发。 */
  enter(animate: OverlayAnimator): void {
    if (!this.visible) {
      return;
    }
    animate((): void => {
      this.offset = 0;
      this.scrimAlpha = 1;
    });
  }

  /**
   * 滑出：动画结束后才卸载。`after` 在卸载之后执行（例如取消登录轮询、关闭 store），
   * 保证副作用发生时面板已经不在屏幕上。
   */
  close(hiddenOffset: number, animate: OverlayAnimator, after?: () => void): void {
    if (!this.visible) {
      return;
    }
    const token = this.generation + 1;
    this.generation = token;
    animate((): void => {
      this.offset = hiddenOffset;
      this.scrimAlpha = 0;
    }, (): void => {
      if (this.generation !== token) {
        return;
      }
      this.visible = false;
      this.offset = 0;
      this.scrimAlpha = 1;
      if (after !== undefined) {
        after();
      }
    });
  }

  /** 急停版：不播退场动画直接卸载（被其它覆盖层顶掉、跳路由等场景）。 */
  hideNow(): void {
    this.generation += 1;
    this.visible = false;
    this.offset = 0;
    this.scrimAlpha = 1;
  }
}