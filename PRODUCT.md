# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

- 主用户：在鸿蒙手机上听哔哩哔哩音频内容（音乐、多 P 合集、收藏/歌单里的曲目）的听众。用户已
  确认产品面向「其他 B 站音频听众」，不是只给作者自用的工具。
- 使用场景：通勤、桌面或后台连续收听；边在「发现」里搜索/浏览内容边逐首开播；登自己的 B 站账号
  取收藏、歌单与历史；把常听的曲目下载到本机后断网播放。
- 当前事实：真正在用的人仍以工程作者为主——发布门禁（真机安装、`force-stop` 冷启动、逐页布局与
  业务验收）尚未通过，产品对外口径只能是「实验开发中」。

## Product Purpose

在 HarmonyOS 上做一个纯原生的 B 站音频/音乐客户端：搜索并播放真实内容，把喜欢的收进本地资料库，
需要时下载到本机离线听，并让播放走系统媒体会话（锁屏、通知、后台音频）。

成功的样子是设备侧证据，而不是编译通过：当前源码构建的 HAP 在 API 26 真机安装、冷启动、壳层导航、
当次视口布局、登录、网络、真实播放与媒体控制、业务持久化逐项验收通过。

## Positioning

与网页壳方案（Electron/ArkWeb）和官方客户端都不同：页面、网络、登录、播放器、媒体会话、
歌词、资料库、下载全部是原生 ArkTS 服务，业务真相只在原生层，页面只读 store 快照并发出动作；不是
把网页塞进容器，也没有跨语言 Bridge。

用户确认必须长期保留的三条机制：

1. **原生 ArkUI，不加载网页**——不引入 ArkWeb 页面层或 Bridge 协议。
2. **本地优先**——收藏、歌单、历史、播放进度、设置、下载都落在本机，原子写入、损坏可回滚、`force-stop`
   后可恢复，下载命中时离线也能播。
3. **系统级播放体验**——AVPlayer + AVSession：锁屏播控、后台音频任务、音质档位只向下协商、歌词面板。

## Operating Context

- 目标设备：HarmonyOS 7 / API 26 手机，单一竖屏视口（本机约 411 宽；`412x915` 等非本机视口不在
  验收范围）。平板、2in1、HarmonyOS 5 / API 12 未验证。
- 开发环境：macOS + DevEco Studio + HarmonyOS SDK API 26 + Node.js 20.19+；命令入口 `npm test` /
  `npm run build` / `npm run verify`（verify 恒为全量测试 + 构建）。
- 签名：仓库保持 `signingConfigs: []`，本机签名只存在于仓库外 `~/.ohos/wisp-music-local-signing/`；
  签名材料、证书、patch 与密码不得入库或进日志。
- 验收：主机侧（测试汇总、HAP 产物）与设备侧（安装、冷启动、导航、视口布局、业务路径、日志）分开
  记录，缺哪侧写哪侧；真机取证流程在 `.agents/skills/harmony-device-run/SKILL.md`。
- 当前界面阶段：UI 按全新设计实现，`pages/` 与 `components/native/` 是唯一实现，正在逐页做
  设备侧验收与细节调整。
- 设计取向（用户 2026-11-12 指定）：贴近 iOS 的原生壳习惯；枚举里没有 HarmonyOS，`## Platform` 的
  `ios` 只是工具占位，不套用 iOS API 或代码，实现一律 ArkUI。

## Capabilities and Constraints

已实现（原生层）：

- 目录：真实搜索、分页、推荐/发现数据链路；多 P 视频按合集展示，进入只读合集详情展开全部 P。
- 登录：B 站扫码登录、Cookie 持久化、登录态请求；账号资料本地快照先行渲染、后台刷新。
- 播放：AVPlayer 播放/暂停/seek/切歌、500 首队列、播放位置恢复、音质档位（高品质/标准/省流，只向下
  降级）；播放页、整页队列、歌词面板与歌词换源。
- 媒体会话：AVSession 推送、锁屏播控、后台音频任务；定时关闭（15–90 分钟，按绝对截止时间）。
- 资料库：我喜欢的、历史、歌单（新建/编辑/封面）、批量加歌单、多选与批量删除；统一 `MusicTrackList`
  基准与 100 行分页。
- 离线下载：`filesDir/downloads-v1/` + 原子索引，单文件 64MB、最多 500 条 / 4GB，可配 100/300/500；
  清理音频缓存不动下载。
- 设置与维护：播放音质、自动播放、歌词显示、下载品质、缓存清理（图片/歌词/音频）、诊断信息、
  法律与免责声明。
- 主题：`scripts/palette.json` 是颜色唯一真源，生成两份 `color.json`；light/dark 双主题。

技术与安全边界（改动不得破坏）：

- 只允许 HTTPS 与白名单域名，URL 校验拒绝非常规端口、userinfo 与尾点主机；关闭明文流量。
- Cookie / WBI 中间值 / 媒体地址 / 二维码登录中间值只停留在原生层，日志只记脱敏 host、状态码与布尔。
- 单一 `@Entry` 页面（`pages/Index.ets`）+ `NavPathStack`；分层 `pages → components/native → state →
  NativeAppRuntime → services`，页面不得持有第二份业务真相。
- `@Observed` store 的渲染路径只读 `@Track` 字段；销毁期不写 `@State`、不同步 `dispose()`。
- 全应用不使用按压态视觉反馈；抽屉统一外壳与四档高度；长列表上限 500 首并分页。

未决与已知缺口：

- 发布门禁未通过，设备侧结论需按当前 UI 重新采集。
- 界面文案与 `accessibilityText` 大量硬编码中文，未统一走 `string.json`。
- 平板/折叠屏/横屏与大字体（`fontSizeMaxScale: 1.3`）没有断点回归。
- 是否公开分发、以什么渠道分发，尚未决定；在决定前不得对可用性或稳定性作超出「实验开发中」的承诺。

## Brand Commitments

- 名称 **wisp-music**（`app_name`），bundle name 固定 `com.lichtcui.wispmusic`，临时包名只允许出现在
  明确标注的本地测试记录里。
- 图标源文件 `design/app-icon.svg`（1024×1024）：iconNavy 底 + 幽灵图标 + logo 橙音乐发夹，改图后需重新
  导出两份 `app_icon.png`。
- 视觉体系：暖纸白/微绿灰中性色为底，「纸叠纸」层级；logo 橙只用于「正在播放」标记；界面语言为中文。
- 声音与立场：第三方非官方客户端，应用不内置、不存储、不提供内容；仅供个人学习与技术交流，不用于
  商业用途（应用内《法律与免责声明》原文即为此立场）。
- 交互承诺：无按压态反馈；返回键按固定层级关闭覆盖层；抽屉统一标题、圆角与拖拽条。

## Evidence on Hand

- 可运行的源码与服务：95 个左右的 `.ets` 文件、分层架构与真实 B 站数据链路（扫码登录、搜索、合集、
  DASH/渐进式音源）。
- 主机侧证据：`npm test`（颜色守卫 + 选择器守卫 + Hypium）、`npm run build`（未签名 HAP）可复现；
  具体数量以当次命令输出为准，不引用历史快照。
- 文档：`docs/architecture.md`（边界与实现约定）、`docs/development.md`（命令、签名与验收口径）、
  `.agents/skills/harmony-device-run/SKILL.md`（真机取证清单）。
- 素材：`design/app-icon.svg`；调色源 `scripts/palette.json`。
- **缺失**：设备侧截图/录屏/日志证据、发布证书与 profile、用户量/评测/媒体报道。未来工作
  不得编造设备通过结论、成功率、用户数据或第三方评价。

## Product Principles

1. **原生优先**：任何功能都在 ArkUI/ArkTS 服务层实现，不引入网页层、WebView 内容或跨语言 Bridge。
2. **本地是唯一真相**：状态由原生 store/runtime 拥有并原子持久化；页面只读快照、只发动作；写失败
   必须可重试、可恢复，不留半份数据。
3. **真实内容，显式状态**：只展示接口真实返回；加载、空、错误三态显式可见，不用占位内容冒充结果。
4. **跟系统一体**：安全区、返回键、媒体会话、后台音频与系统预期一致，不劫持系统手势或通知。
5. **证据说话**：主机侧通过不等于可用；说法随设备侧证据升级，缺证据就写「未验证」。

## Accessibility & Inclusion

- 跟随系统字体缩放，`fontSizeMaxScale: 1.3`；大字体下的布局回归尚未系统采集。
- 抽屉拖拽条有 64×40 热区并支持点按关闭，作为读屏用户的关闭入口；部分控件的 `accessibilityText`
  已提供但未全面覆盖。
- 未确立对外承诺的无障碍标准（如 WCAG / HarmonyOS 无障碍规范）；新增界面至少保持触控目标与读屏
  标签可用。