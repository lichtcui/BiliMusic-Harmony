import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NativeAppRuntime } from '../../app/NativeAppRuntime';
import {
  APP_VERSION,
  DiagnosticsLoginStatus,
  DiagnosticsNetworkStatus,
  DiagnosticsPlayerMode,
  DiagnosticsPlayerStatus,
  DiagnosticsRuntimeState,
  NativeDiagnostics,
  STORAGE_VERSION
} from '../../types/MobileTypes';
import { errorMessageForCode } from '../../util/Errors';
import { describeFeedProbe, describeFeedProbeError } from '../../util/FeedProbe';
import {
  ThemeColors,
  ThemeRadius,
  ThemeSpacing,
  ThemeTypography
} from '../../theme/NativeTheme';
import { PageContentState, PageScaffold } from './PageScaffold';

/**
 * 抽屉内容的实测几何（`design/diagnostics-sheet.html` 的 `.diag-*` 是唯一依据）。
 *
 * 信息行打平到抽屉底色：行内 8/0、行高≥48、行间 1px `native_line`；行文字 14/22，
 * 值列右对齐、最多 3 行且不超过 62%。分组标签 14/20/500 且用主文字色（与行值同黑，
 * 但加粗区分层级），下距 8；组间距 20。
 * 加载条只留 20 转圈与次文字色文案；探针按钮 / 结果条 44 高、8 圆角。
 */
const DIAGNOSTICS_ACTION_HEIGHT: number = 44;
const DIAGNOSTICS_ROW_MIN_HEIGHT: number = 48;
const DIAGNOSTICS_ROW_GAP: number = ThemeSpacing.md;
const DIAGNOSTICS_ROW_PADDING_Y: number = ThemeSpacing.sm;
const DIAGNOSTICS_VALUE_MAX_WIDTH: string = '62%';
const DIAGNOSTICS_LABEL_LINE_HEIGHT: number = 20;
const DIAGNOSTICS_GROUP_GAP: number = ThemeSpacing.xl;
const DIAGNOSTICS_LABEL_GAP: number = ThemeSpacing.sm;
const DIAGNOSTICS_PROBE_ACTION_GAP: number = ThemeSpacing.sm;
const DIAGNOSTICS_PROBE_ACTION_TOP: number = ThemeSpacing.md;
const DIAGNOSTICS_NOTE_TOP: number = ThemeSpacing.md;
const DIAGNOSTICS_NOTE_PADDING: number = ThemeSpacing.md;
const DIAGNOSTICS_LOADING_GAP: number = 10;
const DIAGNOSTICS_SPINNER_SIZE: number = 20;
const DIAGNOSTICS_DIVIDER_WIDTH: number = 1;
const DIAGNOSTICS_CONTENT_TOP: number = ThemeSpacing.lg;
const DIAGNOSTICS_CONTENT_BOTTOM: number = ThemeSpacing.xl;
/** 抽屉底部动作区与滚动内容之间的间距。 */
const DIAGNOSTICS_ACTIONS_TOP: number = ThemeSpacing.md;
/** 复制反馈文字与复制按钮之间的间距。 */
const DIAGNOSTICS_STATUS_GAP: number = ThemeSpacing.sm;
/** 复制反馈出现 / 消失的过渡时长（ms）。 */
const DIAGNOSTICS_COPY_FEEDBACK_DURATION: number = 180;
const FEED_PROBE_PAGE: number = 1;
const FEED_PROBE_PAGE_SIZE: number = 20;
const DOMAIN = 0x424D;
const TAG = 'WispMusicDiagnostics';

enum DiagnosticsCopyState {
  Idle = 0,
  Success = 1,
  Failed = 2
}

@Component
export struct DiagnosticsPage {
  runtime: NativeAppRuntime | null = null;
  onClose: () => void = (): void => {};
  /**
   * 抽屉模式：只渲染可滚动的内容列，不再套 `PageScaffold` 的整页页头与底部「关闭」按钮。
   * 设置页的「诊断信息」把本页塞进 `BottomSheet`，抽屉外壳不显示标题（只有拖拽条）；
   * 启动失败时的整页诊断仍用默认值 `false`。
   */
  @Prop embedded: boolean = false;

  @State private loading: boolean = true;
  @State private copyState: DiagnosticsCopyState = DiagnosticsCopyState.Idle;
  @State private data: NativeDiagnostics = unavailableDiagnostics('app.initializeFailed');
  @State private probeRunning: boolean = false;
  @State private probeLine: string = '';
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    void this.loadDiagnostics();
  }

  aboutToDisappear(): void {
    this.loadGeneration += 1;
  }

  @Builder
  SectionLabel(label: ResourceStr) {
    Text(label)
      .width('100%')
      .fontSize(ThemeTypography.caption)
      .lineHeight(DIAGNOSTICS_LABEL_LINE_HEIGHT)
      .fontWeight(FontWeight.Medium)
      .fontColor(ThemeColors.textPrimary)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .margin({ bottom: DIAGNOSTICS_LABEL_GAP })
  }

  /** 同组相邻行之间的 1px 分隔线；首行与组尾不画。 */
  @Builder
  RowDivider() {
    Divider()
      .width('100%')
      .strokeWidth(DIAGNOSTICS_DIVIDER_WIDTH)
      .color(ThemeColors.line)
  }

  @Builder
  InfoRow(id: string, label: ResourceStr, value: () => ResourceStr) {
    Row({ space: DIAGNOSTICS_ROW_GAP }) {
      Text(label)
        .layoutWeight(1)
        .fontSize(ThemeTypography.caption)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textSecondary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value())
        .constraintSize({ maxWidth: DIAGNOSTICS_VALUE_MAX_WIDTH })
        .fontSize(ThemeTypography.caption)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textPrimary)
        .textAlign(TextAlign.End)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .id(id)
    .width('100%')
    .constraintSize({ minHeight: DIAGNOSTICS_ROW_MIN_HEIGHT })
    .padding({ top: DIAGNOSTICS_ROW_PADDING_Y, bottom: DIAGNOSTICS_ROW_PADDING_Y })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  DiagnosticsContent() {
    Column({ space: DIAGNOSTICS_GROUP_GAP }) {
      if (this.loading) {
        Row({ space: DIAGNOSTICS_LOADING_GAP }) {
          LoadingProgress()
            .width(DIAGNOSTICS_SPINNER_SIZE)
            .height(DIAGNOSTICS_SPINNER_SIZE)
            .color(ThemeColors.accent)
          Text($r('app.string.diagnostics_loading'))
            .fontSize(ThemeTypography.caption)
            .lineHeight(ThemeTypography.bodyLineHeight)
            .fontColor(ThemeColors.textSecondary)
        }
        .id('diagnostics-loading')
        .width('100%')
        .padding({ top: 2, bottom: 2 })
      }

      Column() {
        this.SectionLabel($r('app.string.diagnostics_runtime_section'))
        this.InfoRow(
          'diagnostics-runtime-status',
          $r('app.string.diagnostics_runtime_label'),
          (): ResourceStr => this.runtimeStateText()
        )
        this.RowDivider()
        this.InfoRow(
          'diagnostics-warning-count',
          $r('app.string.diagnostics_warning_count_label'),
          (): ResourceStr => String(this.data.warningCount)
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column() {
        this.SectionLabel($r('app.string.diagnostics_version_section'))
        this.InfoRow(
          'diagnostics-app-version',
          $r('app.string.diagnostics_app_version_label'),
          (): ResourceStr => this.data.appVersion
        )
        this.RowDivider()
        this.InfoRow(
          'diagnostics-storage-version',
          $r('app.string.diagnostics_storage_version_label'),
          (): ResourceStr => String(this.data.storageVersion)
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column() {
        this.SectionLabel($r('app.string.diagnostics_account_section'))
        this.InfoRow(
          'diagnostics-login-status',
          $r('app.string.diagnostics_login_label'),
          (): ResourceStr => this.loginStatusText()
        )
        this.RowDivider()
        this.InfoRow(
          'diagnostics-network-status',
          $r('app.string.diagnostics_network_label'),
          (): ResourceStr => this.networkStatusText()
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column() {
        this.SectionLabel($r('app.string.diagnostics_player_section'))
        this.InfoRow(
          'diagnostics-player-status',
          $r('app.string.diagnostics_player_status_label'),
          (): ResourceStr => this.playerStatusText()
        )
        this.RowDivider()
        this.InfoRow(
          'diagnostics-player-queue',
          $r('app.string.diagnostics_player_queue_label'),
          (): ResourceStr => String(this.data.playerQueueLength)
        )
        this.RowDivider()
        this.InfoRow(
          'diagnostics-player-mode',
          $r('app.string.diagnostics_player_mode_label'),
          (): ResourceStr => this.playerModeText()
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column() {
        this.SectionLabel($r('app.string.diagnostics_probe_section'))
        Text($r('app.string.diagnostics_probe_hint'))
          .id('diagnostics-probe-hint')
          .width('100%')
          .fontSize(ThemeTypography.caption)
          .lineHeight(ThemeTypography.bodyLineHeight)
          .fontColor(ThemeColors.textSecondary)
        Row({ space: DIAGNOSTICS_PROBE_ACTION_GAP }) {
          Button($r('app.string.diagnostics_probe_discover'), { stateEffect: false })
            .id('diagnostics-probe-discover')
            .layoutWeight(1)
            .height(DIAGNOSTICS_ACTION_HEIGHT)
            .fontSize(ThemeTypography.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary)
            .backgroundColor(ThemeColors.surfaceInset)
            .borderRadius(ThemeRadius.md)
            .enabled(!this.probeRunning)
            .onClick(() => {
              void this.runFeedProbe('discover');
            })
          Button($r('app.string.diagnostics_probe_recommend'), { stateEffect: false })
            .id('diagnostics-probe-recommend')
            .layoutWeight(1)
            .height(DIAGNOSTICS_ACTION_HEIGHT)
            .fontSize(ThemeTypography.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary)
            .backgroundColor(ThemeColors.surfaceInset)
            .borderRadius(ThemeRadius.md)
            .enabled(!this.probeRunning)
            .onClick(() => {
              void this.runFeedProbe('recommend');
            })
        }
        .width('100%')
        .margin({ top: DIAGNOSTICS_PROBE_ACTION_TOP })

        if (this.probeLine.length > 0) {
          Text(this.probeLine)
            .id('diagnostics-probe-result')
            .width('100%')
            .fontSize(ThemeTypography.caption)
            .lineHeight(ThemeTypography.bodyLineHeight)
            .fontColor(ThemeColors.textPrimary)
            .padding(DIAGNOSTICS_NOTE_PADDING)
            .margin({ top: DIAGNOSTICS_NOTE_TOP })
            .backgroundColor(ThemeColors.surfaceInset)
            .borderRadius(ThemeRadius.md)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column() {
        this.SectionLabel($r('app.string.diagnostics_error_section'))
        this.InfoRow(
          'diagnostics-error-code',
          $r('app.string.diagnostics_error_code_label'),
          (): ResourceStr => this.errorCodeText()
        )
        this.RowDivider()
        this.InfoRow(
          'diagnostics-error-message',
          $r('app.string.diagnostics_error_message_label'),
          (): ResourceStr => this.errorMessageText()
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Text($r('app.string.diagnostics_privacy_summary'))
        .id('diagnostics-privacy')
        .width('100%')
        .fontSize(ThemeTypography.caption)
        .lineHeight(ThemeTypography.bodyLineHeight)
        .fontColor(ThemeColors.textSecondary)
    }
    .id('diagnostics-content')
    .width('100%')
    .padding({
      /* 抽屉模式由 BottomSheet 的 gutter 提供左右边距，这里不再叠加一层。 */
      left: this.embedded ? 0 : ThemeSpacing.xl,
      right: this.embedded ? 0 : ThemeSpacing.xl,
      top: DIAGNOSTICS_CONTENT_TOP,
      bottom: DIAGNOSTICS_CONTENT_BOTTOM
    })
  }

  /**
   * 底部动作区：复制按钮 + 按钮上方的纯文字反馈。
   *
   * 抽屉模式把它钉在滚动区下方，点按后反馈始终就在按钮上方可见——不再像旧版那样
   * 追加到滚动内容末尾，需要用户自己往下滚才能看到。反馈不带底色 / 圆角，只是
   * 一行说明文字；出现与消失都走 `animateTo` + `TransitionEffect.OPACITY`，让动作区
   * 高度变化和淡入淡出一起过渡，不会突然跳一下。
   */
  @Builder
  DiagnosticsActions() {
    Column() {
      if (this.copyState !== DiagnosticsCopyState.Idle) {
        Text(this.copyStateText())
          .id('diagnostics-copy-status')
          .width('100%')
          .fontSize(ThemeTypography.caption)
          .lineHeight(ThemeTypography.bodyLineHeight)
          .fontColor(this.copyState === DiagnosticsCopyState.Success ?
            ThemeColors.accent : ThemeColors.danger)
          .margin({ bottom: DIAGNOSTICS_STATUS_GAP })
          .transition(TransitionEffect.OPACITY.animation({
            duration: DIAGNOSTICS_COPY_FEEDBACK_DURATION,
            curve: Curve.EaseOut
          }))
      }

      Button($r('app.string.diagnostics_copy'), { stateEffect: false })
        .id('diagnostics-copy')
        .width('100%')
        .height(DIAGNOSTICS_ACTION_HEIGHT)
        .fontSize(ThemeTypography.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeColors.onAccent)
        .backgroundColor(ThemeColors.accent)
        .borderRadius(ThemeRadius.md)
        .enabled(!this.loading)
        .onClick(() => {
          void this.copyDiagnostics();
        })

      if (!this.embedded) {
        Button($r('app.string.diagnostics_close'), { stateEffect: false })
          .id('diagnostics-close')
          .width('100%')
          .height(DIAGNOSTICS_ACTION_HEIGHT)
          .fontSize(ThemeTypography.body)
          .fontColor(ThemeColors.textPrimary)
          .backgroundColor(ThemeColors.surfaceInset)
          .borderRadius(ThemeRadius.md)
          .margin({ top: DIAGNOSTICS_NOTE_TOP })
          .onClick(() => {
            this.onClose();
          })
      }
    }
    .id('diagnostics-actions')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      /* 抽屉模式由 BottomSheet 的 gutter 提供左右边距，这里不再叠加一层。 */
      left: this.embedded ? 0 : ThemeSpacing.xl,
      right: this.embedded ? 0 : ThemeSpacing.xl,
      top: DIAGNOSTICS_ACTIONS_TOP
    })
  }

  build() {
    if (this.embedded) {
      Column() {
        Scroll() {
          this.DiagnosticsContent()
        }
        .id('diagnostics-sheet-scroll')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)

        this.DiagnosticsActions()
      }
      .width('100%')
      .height('100%')
    } else {
      PageScaffold({
        eyebrow: $r('app.string.diagnostics_eyebrow'),
        title: $r('app.string.diagnostics_title'),
        description: $r('app.string.diagnostics_description'),
        state: PageContentState.Ready
      }) {
        this.DiagnosticsContent()
        this.DiagnosticsActions()
      }
    }
  }

  private async loadDiagnostics(): Promise<void> {
    const generation = this.loadGeneration + 1;
    this.loadGeneration = generation;
    this.loading = true;
    this.copyState = DiagnosticsCopyState.Idle;
    const runtime = this.resolveRuntime();
    if (runtime === null) {
      this.data = unavailableDiagnostics('app.runtimeUnavailable');
      this.loading = false;
      return;
    }
    try {
      const data = await runtime.diagnostics();
      if (generation === this.loadGeneration) {
        this.data = data;
        this.loading = false;
        hilog.info(DOMAIN, TAG, 'diagnostics loaded state=%{public}s warnings=%{public}d',
          data.runtimeState, data.warningCount);
      }
    } catch (error) {
      if (generation === this.loadGeneration) {
        this.data = unavailableDiagnostics('app.initializeFailed');
        this.loading = false;
        hilog.warn(DOMAIN, TAG, 'diagnostics load failed');
      }
    }
  }

  /**
   * `discover()` / `recommend()` 的临时探针（T10 附带采集）。
   * 结果只含条数 / 页码 / 错误码，用于判定这两个零消费接口在真机上是否可达。
   */
  private async runFeedProbe(kind: string): Promise<void> {
    this.probeRunning = true;
    try {
      const runtime = this.resolveRuntime();
      if (runtime === null) {
        this.probeLine = describeFeedProbeError(kind, new Error('app.runtimeUnavailable'));
        return;
      }
      const feed = kind === 'discover' ?
        await runtime.discover(FEED_PROBE_PAGE, FEED_PROBE_PAGE_SIZE) :
        await runtime.recommend(FEED_PROBE_PAGE, FEED_PROBE_PAGE_SIZE);
      this.probeLine = describeFeedProbe(kind, feed);
      hilog.info(DOMAIN, TAG, 'feed probe %{public}s ok items=%{public}d',
        kind, feed.items.length);
    } catch (error) {
      this.probeLine = describeFeedProbeError(kind, error);
      hilog.warn(DOMAIN, TAG, 'feed probe %{public}s failed', kind);
    } finally {
      this.probeRunning = false;
    }
  }

  private resolveRuntime(): NativeAppRuntime | null {
    const injected = this.runtime;
    if (injected !== null) {
      hilog.info(DOMAIN, TAG, 'diagnostics runtime injected');
      return injected;
    }
    const stored = AppStorage.get<NativeAppRuntime>('nativeAppRuntime') ?? null;
    if (stored === null) {
      hilog.error(DOMAIN, TAG, 'diagnostics runtime missing');
    } else {
      hilog.info(DOMAIN, TAG, 'diagnostics runtime restored from storage');
    }
    return stored;
  }

  private async copyDiagnostics(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.copyText());
      await pasteboard.getSystemPasteboard().setData(data);
      this.applyCopyState(DiagnosticsCopyState.Success);
    } catch (error) {
      this.applyCopyState(DiagnosticsCopyState.Failed);
    }
  }

  /** 反馈文案出现 / 切换时和动作区高度一起过渡，避免点完按钮内容突然往上顶。 */
  private applyCopyState(state: DiagnosticsCopyState): void {
    this.getUIContext().animateTo({
      duration: DIAGNOSTICS_COPY_FEEDBACK_DURATION,
      curve: Curve.EaseOut
    }, () => {
      this.copyState = state;
    });
  }

  private copyText(): string {
    const lines: string[] = [];
    lines.push(this.resourceText($r('app.string.diagnostics_copy_header')));
    lines.push(this.copyLine($r('app.string.diagnostics_runtime_label'), this.runtimeStateText()));
    lines.push(this.copyLine(
      $r('app.string.diagnostics_warning_count_label'),
      String(this.data.warningCount)
    ));
    lines.push(this.copyLine($r('app.string.diagnostics_app_version_label'), this.data.appVersion));
    lines.push(this.copyLine(
      $r('app.string.diagnostics_storage_version_label'),
      String(this.data.storageVersion)
    ));
    lines.push(this.copyLine($r('app.string.diagnostics_login_label'), this.loginStatusText()));
    lines.push(this.copyLine($r('app.string.diagnostics_network_label'), this.networkStatusText()));
    lines.push(this.copyLine(
      $r('app.string.diagnostics_player_status_label'),
      this.playerStatusText()
    ));
    lines.push(this.copyLine(
      $r('app.string.diagnostics_player_queue_label'),
      String(this.data.playerQueueLength)
    ));
    lines.push(this.copyLine($r('app.string.diagnostics_player_mode_label'), this.playerModeText()));
    lines.push(this.copyLine($r('app.string.diagnostics_error_code_label'), this.errorCodeText()));
    lines.push(this.copyLine($r('app.string.diagnostics_error_message_label'), this.errorMessageText()));
    if (this.probeLine.length > 0) {
      lines.push(this.copyLine($r('app.string.diagnostics_probe_label'), this.probeLine));
    }
    lines.push(this.resourceText($r('app.string.diagnostics_privacy_copy')));
    return lines.join('\n');
  }

  private copyLine(label: Resource, value: string): string {
    return `${this.resourceText(label)}: ${value}`;
  }

  private resourceText(resource: Resource): string {
    return getContext(this).resourceManager.getStringSync(resource.id);
  }

  private runtimeStateText(): string {
    const state: DiagnosticsRuntimeState = this.data.runtimeState;
    if (state === 'ready') {
      return this.resourceText($r('app.string.diagnostics_runtime_ready'));
    }
    if (state === 'initializing') {
      return this.resourceText($r('app.string.diagnostics_runtime_initializing'));
    }
    if (state === 'failed') {
      return this.resourceText($r('app.string.diagnostics_runtime_failed'));
    }
    if (state === 'shutting_down') {
      return this.resourceText($r('app.string.diagnostics_runtime_shutting_down'));
    }
    if (state === 'stopped') {
      return this.resourceText($r('app.string.diagnostics_runtime_stopped'));
    }
    if (state === 'unavailable') {
      return this.resourceText($r('app.string.diagnostics_runtime_unavailable'));
    }
    return this.resourceText($r('app.string.diagnostics_runtime_idle'));
  }

  private loginStatusText(): string {
    const status: DiagnosticsLoginStatus = this.data.loginStatus;
    if (status === 'signed-in') {
      return this.resourceText($r('app.string.diagnostics_login_signed_in'));
    }
    if (status === 'signed-out') {
      return this.resourceText($r('app.string.diagnostics_login_signed_out'));
    }
    return this.resourceText($r('app.string.diagnostics_unknown'));
  }

  private networkStatusText(): string {
    const status: DiagnosticsNetworkStatus = this.data.networkStatus;
    if (status === 'available') {
      return this.resourceText($r('app.string.diagnostics_network_available'));
    }
    if (status === 'unavailable') {
      return this.resourceText($r('app.string.diagnostics_network_unavailable'));
    }
    return this.resourceText($r('app.string.diagnostics_unknown'));
  }

  private playerStatusText(): string {
    const status: DiagnosticsPlayerStatus = this.data.playerStatus;
    if (status === 'playing') {
      return this.resourceText($r('app.string.diagnostics_player_playing'));
    }
    if (status === 'loading') {
      return this.resourceText($r('app.string.diagnostics_player_loading'));
    }
    if (status === 'paused') {
      return this.resourceText($r('app.string.diagnostics_player_paused'));
    }
    if (status === 'error') {
      return this.resourceText($r('app.string.diagnostics_player_error'));
    }
    if (status === 'idle') {
      return this.resourceText($r('app.string.diagnostics_player_idle'));
    }
    return this.resourceText($r('app.string.diagnostics_unknown'));
  }

  private playerModeText(): string {
    const mode: DiagnosticsPlayerMode = this.data.playerMode;
    if (mode === 'sequence') {
      return this.resourceText($r('app.string.diagnostics_mode_sequence'));
    }
    if (mode === 'repeat-one') {
      return this.resourceText($r('app.string.diagnostics_mode_repeat_one'));
    }
    if (mode === 'repeat-all') {
      return this.resourceText($r('app.string.diagnostics_mode_repeat_all'));
    }
    if (mode === 'shuffle') {
      return this.resourceText($r('app.string.diagnostics_mode_shuffle'));
    }
    return this.resourceText($r('app.string.diagnostics_unknown'));
  }

  private errorCodeText(): string {
    return this.data.errorCode.length > 0 ?
      this.data.errorCode : this.resourceText($r('app.string.diagnostics_no_error'));
  }

  private errorMessageText(): string {
    return this.data.errorMessage.length > 0 ?
      this.data.errorMessage : this.resourceText($r('app.string.diagnostics_no_error'));
  }

  private copyStateText(): string {
    return this.copyState === DiagnosticsCopyState.Success ?
      this.resourceText($r('app.string.diagnostics_copy_success')) :
      this.resourceText($r('app.string.diagnostics_copy_failed'));
  }
}

function unavailableDiagnostics(errorCode: string): NativeDiagnostics {
  return {
    runtimeState: 'unavailable',
    appVersion: APP_VERSION,
    storageVersion: STORAGE_VERSION,
    warningCount: 0,
    loginStatus: 'unknown',
    networkStatus: 'unknown',
    playerStatus: 'unavailable',
    playerQueueLength: 0,
    playerMode: 'unknown',
    errorCode: errorCode,
    errorMessage: errorMessageForCode(errorCode, false)
  };
}
