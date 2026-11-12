# 开发与验证

本文介绍仓库级口径：前置条件、命令入口、签名边界和验收标准。定向 suite、颜色守卫的副作用、
Hvigor 守护进程与 `safe-delete` 排查、签名切换步骤、真机安装/冷启动/日志、`uitest` 取证、视口与
返回栈核对、持久化证据，全部在 [`.agents/skills/harmony-device-run/SKILL.md`](../.agents/skills/harmony-device-run/SKILL.md)
（随仓库提交）。

## 前置条件

- macOS 与 DevEco Studio；HarmonyOS SDK（工程配置 API 26）；Node.js `20.19+`；可用的 Hypium 与 Hvigor
- 脚本先读环境变量，再找本机默认的 DevEco 路径；路径不同的时候设置：

```bash
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export HVIGOR_BIN=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw
export OHPM_BIN=/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm
```

`HVIGOR_BIN` 是可选的应急口子：设置了它就不会经过默认的 `--no-daemon` 包装器。

## 命令

```bash
npm test        # 颜色守卫 + 选择器守卫 + Hypium；结果 entry/.test/default/intermediates/test/coverage_data/test_result.txt
npm run build   # HAP；产物 entry/build/default/outputs/default/
npm run verify  # 全量测试 + 构建，不接受 scope
```

定向用法、日志位置，以及两类**不是代码错误**的构建失败（守护进程挂起、`safe-delete` 删除守卫——
后者已由 `scripts/build-env.mjs` 自动识别并清理）见 skill 的 §1–§5。

选择器（`.id(...)`）只有一条路径：`scripts/ui-ids.json` → `node scripts/ui-ids.mjs --write`
（生成 `components/native/NativeUiIds.ets`）→ `node scripts/ui-ids.mjs --check`。单独诊断用
`npm run check:ui-ids`；`npm test` 已把它排在颜色守卫之后，手改生成物会在这里失败。
颜色同理：`scripts/palette.json` → `node scripts/theme.mjs --write` → `--check`
（`npm run check:theme`）。

三个命令都经 `scripts/hvigorw-no-daemon.mjs` 调 `hvigorw --no-daemon`。原因不是任务慢（任务只有
十几秒），而是 daemon 模式在守护进程起不来时会永久挂起：预热路径 fork 完立刻取消自己的 10s 兜底
定时器，连接器随后无超时地等待守护进程的 IPC 消息，于是构建停在 `Starting hvigor daemon.` 不报错
也不返回。守护进程起不来的常见原因是宿主沙箱不允许写 `~/.hvigor`（守护进程日志、注册表、缓存都在
那里，守护进程启动第一件事就是写日志），或同机其它鸿蒙工程占着它。`--no-daemon` 不进这条路径，
代价是每次多约 3 秒引导时间。

## 签名边界

- 仓库里的 `build-profile.json5` 必须保持 `signingConfigs: []`，product 不绑定 `signingConfig`。
- 本机签名只存在仓库外：`~/.ohos/wisp-music-local-signing/build-profile-signing.patch`（可用
  `WISP_MUSIC_SIGNING_PATCH` 覆盖）。真机构建前 `npm run signing:apply`，构建后立刻
  `npm run signing:restore`。
- `.p12` / `.p7b` / `.cer`、密码和 patch 内容不得入库、不得进日志。`npm run verify` 会先运行
  签名边界脚本（等价于 `npm run check:signing`），已 apply 时会拒绝——这是预期行为。

## 验收标准

主机编译成功不等于运行时可用。两侧分开记录，缺哪侧就写明缺哪侧：

- 主机侧：`npm test` 的测试汇总、`npm run build` 的构建任务与产物名。
- 设备侧：安装、`force-stop` 冷启动、壳层导航、当次视口布局、业务路径和日志；逐项清单见 skill 的 §8。
- 没有设备时明确写「主机侧通过、设备侧未验证」。
- 发布门禁：当前 UI 的设备侧结论需重新采集；发布前保持「实验开发中」，壳层导航通过不等于
  手机端可用。
