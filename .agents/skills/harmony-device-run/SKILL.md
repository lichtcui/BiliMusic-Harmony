---
name: harmony-device-run
description: 改完 wisp-music（bundle com.lichtcui.wispmusic）代码后在真机验证的完整闭环：判定改动范围 → 主机测试/构建 → 本机签名切换 → 安装 → force-stop 冷启动 → 按 PID 取证，含 hdc/uitest 无 GUI 验证、输出卫生与「主机侧通过 / 设备侧未验证」的汇报口径。用于本仓库任何代码改动后的验证，或用户反馈「改了没生效 / 设备上跑的是旧版」时。
---

# 真机验证闭环（wisp-music）

> 本文件是**仓库内的真源**：从 `~/Documents/skills.harmony/harmony-device-run` 模板渲染后收进仓库并单独维护。
> 命令就是下面 §2 / §4 里的内容，和 `docs/development.md` 的「命令」一节保持一致；上游模板不会自动同步进来。
> `docs/development.md` 只保留前置条件、命令入口、签名边界和验收口径。

## 1. 判定改动范围

| 改了什么 | 先跑什么 | 后续 |
|---|---|---|
| 只有 `entry/src/main/ets/**`（ArkTS / ArkUI） | 相关 Hypium suite，再 `npm run build` | 装 HAP + `force-stop` + 冷启动 |
| `entry/src/main/resources/**`、`module.json5` | `npm run build` | 同上 |
| 颜色：`scripts/palette.json` / 两份 `color.json` / `.ets` 颜色字面量 | `node scripts/theme.mjs --write` → `--check` | 颜色守卫（规则 0–6）在 `npm test` 之前跑 |
| `services/**`、`player/**`、登录、持久化 | `npm test -- <Suite>` 定向 suite | 至少覆盖相关 suite，再构建 |
| 构建配置 / 页面资源 / 跨层改动 | `npm run verify`（全量测试 + 构建） | `verify` 第一步是 `check:signing`，已 apply 签名时会拒绝 |
| native / Rust | 不需要 | 本仓库没有 native 源码，全部是 ArkTS |

**没有把握时的第一动作：不要先改代码**——先确认「设备上跑的是不是这次构建」，再决定重装还是排查。

## 2. 主机侧

```bash
# 脚本会先找本机 DevEco 默认路径，找不到时再显式指定：
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk

npm test                 # 颜色守卫 + Hypium；结果见 entry/.test/default/intermediates/test/coverage_data/test_result.txt
npm test -- PlayerQueue  # 定向：Suite 或 Suite#case，逗号分隔多目标
npm run build            # 产物 entry/build/default/outputs/default/
npm run verify           # 全量测试 + 构建，不接受 scope
```

两个已知非代码失败：

- **守护进程挂起**：daemon 模式下 hvigor 先预热守护进程，守护进程起不来时客户端会永久等待（预热
  路径 fork 后立刻取消了自己的 10s 兜底定时器，连接器再无超时地等 IPC），停在
  `hvigor client: Starting hvigor daemon.`。最常见触发是环境不允许写 `~/.hvigor`（沙箱/CI）。
  `npm test` / `npm run build` / `npm run verify` 现在默认经 `scripts/hvigorw-no-daemon.mjs` 调
  `hvigorw --no-daemon`，不会进这条路径；仍卡住时先确认 wrapper 生效
  （`node -e "import('./scripts/harmony-tools.mjs').then(m => console.log(m.findHvigor()))"`）与
  执行位，`HVIGOR_BIN` 会绕开 wrapper。**不要** `--stop-daemon-all`。
- **`[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]`**：宿主删除守卫拦下的清理步骤，不是编译错误。
  注入形态不止一种：`NODE_OPTIONS` 的 `--require <shim>.cjs`、`CODEBUDDY_SAFE_DELETE_*` 变量、
  `BASH_ENV` 里的 shim 脚本、以及 PATH 里的 `safe-bin` 目录。`npm test` / `npm run build` /
  `npm run verify` 现在会按名字识别这些注入（`scripts/build-env.mjs`），用清理过的环境重启自身
  并向下传递，默认环境不再需要手工处理。
  仍被拦下时先确认识别结果：
  `node -e "import('./scripts/build-env.mjs').then(m => console.log(m.hasDeleteGuardInjection()))"`
  应为 `false`；为 `true` 说明出现了新的注入形态，把它的名字特征补进 `scripts/build-env.mjs`。
  应急仍可 `env -u NODE_OPTIONS -u BASH_ENV DEVECO_SDK_HOME=... hvigorw ... --no-daemon` 手工重试，
  判据仍是 `test_result.txt` 的 `Tests run: N, Failure: 0` 与 `BUILD SUCCESSFUL`。

## 3. 本机签名（真机构建必需）

仓库里必须保持 `signingConfigs: []`，签名差异只存在仓库外 patch（`~/.ohos/wisp-music-local-signing/`）：

```bash
npm run signing:status
npm run signing:apply     # 真机构建前应用
npm run build
npm run signing:restore   # 构建完立刻还原；不还原 npm run verify 会拒绝
```

凭据、`*.p12`/`*.p7b`/`*.cer`、patch 内容都不得出现在提交、日志或对话里。

## 4. 安装 / 冷启动 / 日志

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
BUNDLE=com.lichtcui.wispmusic

"$HDC" list targets -v      # 必须是 Connected；Offline 多为锁屏/未授权/服务端残留，解锁或 hdc kill 后重试
"$HDC" install -r entry/build/default/outputs/default/entry-default-signed.hap
"$HDC" shell aa force-stop "$BUNDLE"
"$HDC" shell hilog -r
"$HDC" shell aa start -a EntryAbility -b "$BUNDLE"
"$HDC" shell pidof "$BUNDLE"
"$HDC" shell aa dump -l | rg "$BUNDLE|FOREGROUND|BACKGROUND"

PID="$("$HDC" shell pidof "$BUNDLE" | tr -d '\r')"
"$HDC" shell hilog -x | rg " $PID " \
  | rg -i "EntryAbility|native runtime|Index page|media session|crash|fatal|SIGSEGV|SIGABRT|AppFreeze|unhandled|exception|AVSession" \
  | tail -n 240
```

闭环判据：

1. **编译**：命令成功且产物时间戳是新的（不是旧 HAP）。
2. **签名**：`install` 失败先查签名、设备 UDID 与 profile 是否含本机设备，见 `harmonyos-release-signing`。
3. **force-stop**：不 `aa force-stop` 时 `aboutToAppear` 不会重跑，界面看起来「没变化」。
4. **冷启动**：`pidof` 有新 PID、`aa dump -l` 里是 `FOREGROUND`。
5. **取证**：按 PID + 关键词筛日志、dump 布局；只把关键行带回对话。

## 5. 输出卫生（避免刷爆上下文）

- 构建：`npm run build > /tmp/build.log 2>&1`，再 `rg -n "ERROR|error\[|error:|FAILED" /tmp/build.log`；
  完整日志也在 `entry/.test/logs/build.log`、`entry/.test/logs/test.log`。**不要**整份贴回。
- 日志：先 `hilog -r` 清，再按 **PID + 关键词**筛并 `tail -n 240`。不要用 `-T <tag>`（tag 按文件拆，猜错只会拿到空结果），
  不要裸 `hilog -x | rg`（会刷屏）。
- 中间产物留在 `/tmp` 或 `.hvigor/outputs/`（不入库），只把**结论**带回对话。

## 6. 无 DevEco GUI 的 UI 取证

```bash
"$HDC" shell uitest dumpLayout -p /data/local/tmp/wisp-music-layout.json -a
"$HDC" file recv /data/local/tmp/wisp-music-layout.json .hvigor/outputs/device/layout.json
"$HDC" shell "uitest screenCap -p /data/local/tmp/wisp-music.png"
"$HDC" file recv /data/local/tmp/wisp-music.png .hvigor/outputs/device/screen.png
"$HDC" shell "uitest uiInput keyEvent Back"
```

- **每次 `dumpLayout` 都要确认命令成功**：失败时 `/data/local/tmp/*.json` 会留着上一次的内容，看起来像「点了没反应 / 菜单没弹出」。
- **`dumpLayout` 卡死会连累后面所有 dump**（症状：每次都报 `Wait for subscribe uitest.broadcast.command.reply timeout`）：
  设备侧残留进程占着广播，`ps -ef | grep 'uitest dumpLayout'` 取 pid `kill -9` 即恢复；写循环脚本要加看门狗。
- **读瞬时 UI（toast 等）**：`dumpLayout` 不导出系统 toast 窗口，用 `screenCap` 连拍 + 主机 OCR
  （本机 `tesseract` 带 `chi_sim`；必须 `cd` 到图片目录用相对文件名，leptonica 按 cwd 找文件）。
  连拍要在点击**之前**起来，否则只能拍到 toast 消失后的画面。OCR 的入口词按当次要查的文案现选。
- `uitest uiInput` 支持 `click / doubleClick / longClick / swipe / drag / fling / keyEvent(Back|Home|Power) / inputText`；
  长按是 `longClick`（不是 `longPress`），`inputText` 不触发 `onSubmit`（补 `keyEvent 2054`）。

### 视口

视口只按**当次连接设备**的 `hidumper -s DisplayManagerService` 读数（`VirtualWidth` / `VirtualHeight` /
`Density`）记录（历史记录过 `373x842 vp` 与 `420x948 vp`，是同一台机不同 density 档位）。不要跨档位
复用旧读数，也不要用 Previewer 截图或按 density 推算的边界代替真机证据。`412x915` 一类非本机视口不在
验收范围：本机没有 `wm`/`setresolution`，`aa start` 的窗口尺寸和模式选项都被系统拒绝，density 只能走系统设置。

### 返回栈核对（每次 Back 前后重新采集布局与截图）

1. 操作面板打开时，Root 和当前 `NavDestination` 都先关闭面板，路由保持不变。
2. Player 打开操作面板时，第一次 Back 留在 `player-page`，第二次 Back 回 `search-page`。
3. Queue Back 回 Player；Login Back 回 Search；Settings Back 回 Search。
4. Diagnostics 的系统 Back 和标题栏 BackButton 都回 Settings。
5. 非搜索 Tab 的根页 Back 先回 Search；Search 根页 Back 交给系统进入后台，进程不应退出。
6. 面板连续快速触发时至少用 5 轮 `force-stop` 冷启动复核；每轮都重新取 PID 和布局。

## 7. 持久化证据

本仓库不跑 RDB：状态是 `context.filesDir` 下的 JSON——`library-v1.json`、`settings-v1.json`、
`bili-cookies-v1.json`、`auth-profile-v1.json`、`player-session-v1.json`、`lyrics-v1.json`。要核对写入，先确认真实路径：

```bash
"$HDC" shell ls /data/app/el2/100/base/com.lichtcui.wispmusic/haps/entry/files
"$HDC" file recv /data/app/el2/100/base/com.lichtcui.wispmusic/haps/entry/files/settings-v1.json /tmp/
```

路径随版本/设备可能不同，以 `ls` 成功为准。Cookie、二维码登录中间值和签名参数不得打印进对话或日志。

## 8. 验收记录与汇报

验收至少分别记录这 7 项：`npm test` 测试汇总；HAP 构建任务与产物名；安装 + `force-stop` 冷启动 +
首屏和壳层导航；当次视口下的安全区/换行/遮挡；搜索、登录、真实音频播放、暂停、seek、切歌和位置恢复；
AVSession、系统媒体键和后台长播；日志中的崩溃、致命错误和可恢复错误。

汇报格式：`改动文件 → 主机侧（测试汇总 / 构建任务与产物名）→ 真机现象（截图或 ≤3 行关键日志，附当次视口）→ 结论 → 未验证项`。

没有连真机时明确写「**主机侧通过、设备侧未验证**」；壳层导航通过不等于业务路径可用（发布门禁未过，只能声明「实验开发中」）。

## 相关

- 同一仓库 `.agents/skills/` 下还有：`harmony-next`（API / 离线文档）、`harmonyos-build-doctor`（构建环境）、
  `harmonyos-project-audit`（接手基线）、`harmonyos-release-signing` 与 `harmonyos-release-check`（签名与发布门禁）。
  这些是中央库 `~/Documents/skills.harmony` 的实拷贝，随仓库提交；上游更新需要手工同步进仓库，不会自动生效。
- 不要再对已入库的这 6 个目录跑 `setup-codex.sh`：它会把「已存在且不是软链」的目录按冲突跳过，别指望它刷新。