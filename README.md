# wisp-music

wisp-music 是一个 HarmonyOS 原生手机客户端。工程使用 ArkUI、ArkTS 和
HarmonyOS 原生服务实现页面、网络、登录、播放器、媒体会话和本地资料库，不加载
React 页面，也不运行 Electron 或 ArkWeb Bridge。

当前状态：**实验开发中，尚未达到可发布状态**。UI 已按全新设计实现：
`pages/` 与 `components/native/` 下的页面是当前实现，仍在逐页做设备侧验收与细节调整；
服务层（网络、登录、播放器、媒体会话、本地持久化）保持稳定。主机侧 `npm test` /
`npm run build` / `npm run verify` 可运行，测试数量与颜色守卫基线以命令输出为准；
设备侧的布局、交互和业务结论仍需按页采集，因此不能把当前版本描述为手机端可用。

## 已有实现

以下能力已有原生实现，设备侧结论按当前设计逐项验收：

- 网络与目录：真实搜索、分页、推荐/发现数据链路
- 登录：B 站扫码登录、Cookie 持久化、登录态请求
- 播放：原生 AVPlayer 播放/暂停/seek/切歌、播放队列、播放位置恢复
- 媒体会话：AVSession 推送、锁屏播控、后台音频任务
- 持久化：播放位置、最近播放、收藏、歌单、设置的本地 JSON 原子写入与 force-stop 恢复
- 缓存：封面图片缓存、歌词匹配与显示

当前只面向 HarmonyOS 7 / API 26 手机（平板、2in1 和 HarmonyOS 5 / API 12 未验证，`412x915` 等
非本机视口不在验收范围）。发布条件是当前源码构建的 HAP 在 API 26 真机完成安装、`force-stop`
冷启动、新 UI 壳层导航与当次设备视口布局，并通过登录、网络、真实播放与媒体控制、业务持久化
验收；逐项判据见 [设备验证 skill](.agents/skills/harmony-device-run/SKILL.md) 与[开发与验证](docs/development.md)。

## 快速开始

前置条件：macOS、DevEco Studio、HarmonyOS SDK API 26、Node.js 20.19+。命令、结果路径和环境变量
覆盖见[开发与验证](docs/development.md)；真机安装需要本机签名，签名材料不得提交到仓库。

## 项目结构

分层与目录职责见[架构说明](docs/architecture.md)。要点：服务由 `NativeAppRuntime` 统一创建和
持有；页面只通过 store 和 runtime 读写状态、发出动作，不直接拼接 B 站请求，也不持有第二份业务真相。

## 文档

入口是 [docs/index.md](docs/index.md)；正文只有两篇：架构边界、开发与验证口径。

## 许可证

MIT License，见 [LICENSE](LICENSE)。
