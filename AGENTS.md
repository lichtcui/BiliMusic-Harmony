# AGENTS.md

## 项目定位

这是 wisp-music 的独立 HarmonyOS 手机客户端。工程只维护一套原生 ArkUI/ArkTS 页面和
服务，不加载 React 页面，不运行 Electron，也不使用 ArkWeb Bridge。

- 正式 bundle name：`com.lichtcui.wispmusic`
- HAP 模块：`entry`
- 入口 Ability：`entry/src/main/ets/entryability/EntryAbility.ets`
- 服务门面：`entry/src/main/ets/app/NativeAppRuntime.ets`
- 当前目标：HarmonyOS 7 / API 26 手机
- 当前阶段：UI 按全新设计实现，`pages/` 与 `components/native/` 是当前实现，仍在
  逐页做设备侧验收与细节调整；服务层与 state/runtime 边界保持不变。
- 支持声明：实验开发中，发布门禁未通过；只能声明“实验开发中”，不能声明“手机端可用”。
  壳层导航通过不等于业务可用。

## 架构约定

分层：`pages/Index.ets` → `components/native/*` → `state/*` → `app/NativeAppRuntime.ets`（服务门面）
→ `services/*`；完整边界与文件清单见 `docs/architecture.md`。

- 页面只读取 store/runtime 的快照并调用动作，不直接使用 Cookie、WBI、媒体 URL 或原始接口响应。
- 业务状态由原生层拥有；不要在页面中复制播放器、资料库或登录状态的真相。
- 原生页面状态通过 ArkUI observable state 传播，不要引入 MessagePort 或新的 Bridge 协议。
- 网络只允许 HTTPS 和白名单域名。媒体 URL、Cookie、二维码登录中间值和签名参数不得写入日志或公开 UI 状态。
- 新增服务或状态时沿用现有 store、runtime gateway 和 atomic persistence 模式，避免页面直接持有底层服务。

## 构建与验证

在项目根目录运行 `npm test`、`npm run build`、`npm run verify`（`verify` 始终全量测试 + 构建）。
操作细则（定向 suite、工具路径、颜色守卫副作用、构建/签名/真机取证）见
`.agents/skills/harmony-device-run/SKILL.md`（随仓库提交，真机验证前先加载）；命令入口、签名边界
与验收标准见 `docs/development.md`。

改颜色只有一条路径：`scripts/palette.json` → `node scripts/theme.mjs --write`（生成两份
`color.json`）→ `node scripts/theme.mjs --check`。`npm test` 会先跑这道守卫，所以改色期间定向
suite 一起失败是预期行为，先看守卫报告，别误判成用例挂了。

改界面选择器同样只有一条路径：`scripts/ui-ids.json` → `node scripts/ui-ids.mjs --write`
（生成 `components/native/NativeUiIds.ets`）→ `node scripts/ui-ids.mjs --check`。手改生成物
会被 `npm test` 的选择器守卫拦下。

修改服务、播放器、登录、持久化或页面状态后至少跑相关 Hypium 测试；改了构建配置或页面资源要跑
HAP 构建。没连真机时明确记录“主机侧通过、设备侧未验证”，编译成功不等于运行时验收。真机签名
只用仓库外的本机工作区，签名材料不入库、不进日志。

## 代码与仓库卫生

- 搜索用 `rg`；改文件用编辑器或编辑工具（Codex 上是 `apply_patch`），不要 `sed -i` 就地改。
- 不提交 `entry/build/`、`entry/.test/`、`.hvigor/`、`oh_modules/`、HAP、证书、profile 或密码。
- 不修改本机签名配置来绕过构建；使用仓库外的本地签名工作区。
- 保持 bundle name 为 `com.lichtcui.wispmusic`，临时包名只允许出现在明确标注的本地测试记录中。
- 不删除或回滚与本任务无关的用户改动。
- 提交前运行 `git diff --check`、`git status --short`，并检查 diff 中没有凭据和生成产物。

## 文档维护

- 项目文档在 `docs/`，入口是 `docs/index.md`，随代码一起更新：架构和边界放 `architecture.md`，
  构建、签名与验收口径放 `development.md`；操作流程写在 `.agents/skills/` 下的 skill 里。
