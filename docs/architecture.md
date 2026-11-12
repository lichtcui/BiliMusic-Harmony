# 架构

## 总览

```text
EntryAbility (UIAbility)
  |
  v
pages/Index.ets
  |
  +-- Navigation / NavDestination
  +-- components/native/*  (search, library, player, queue, login, lyrics, settings)
  |
  v
state/*  (AuthStore, SearchStore, PlayerStore, LibraryStoreModel, ...)
  |
  v
app/NativeAppRuntime.ets  (creation, lifecycle, gateways, diagnostics)
  |
  +-- services/BiliHttpClient.ets + CookieJar + WBI
  +-- services/AuthService.ets
  +-- services/CatalogService.ets
  +-- services/PlayerService.ets + AudioFallback + AudioCachePolicy
  +-- services/MediaSessionService.ets + MediaControlState
  +-- services/LibraryStore.ets  /  state/PlayerSessionStore
  +-- services/DownloadService.ets  /  state/DownloadStore
  +-- services/ImageCacheService.ets
  +-- services/LyricsService.ets
```

> 不要引入 ArkWeb 页面层或 Bridge 协议；新增功能一律保持原生 ArkTS 实现。

`EntryAbility` 只负责 UIAbility 生命周期和页面加载。`NativeAppRuntime` 在 Ability 的
`onCreate` 就发起初始化（`Index` 复用同一个 in-flight Promise，不重复初始化），并通过
`AppStorage['nativeAppRuntime']` 暴露给页面；服务初始化完成后，页面使用 store 快照和动作完成交互。
启动页与系统启动窗口共用 `start_window_background` 和 `app_icon`，首帧接手时不闪色、不闪文案。
图标源文件是 `design/app-icon.svg`（1024×1024，底色即 `iconNavy`），改图后重新导出
`AppScope/resources/base/media/app_icon.png` 与 `entry/src/main/resources/base/media/app_icon.png`
两份；`media/` 下不要放同名 SVG，`$media:app_icon` 会在同名 png/svg 之间重复定义。
登录资料先用本地 `auth-profile-v1.json` 快照渲染，`/x/web-interface/nav` 在 runtime ready 后后台刷新，
不阻塞首帧；缓存只存公开资料字段，不存 Cookie。

## 页面层

`pages/Index.ets` 是唯一的 `@Entry` 页面。它持有 `NavPathStack`、底部一级入口和启动状态，
并把播放器、队列、歌词面板、歌单详情等作为 `NavDestination` 或根覆盖层打开；登录抽屉、设置整页、
诊断信息抽屉、缓存清理抽屉、法律与免责声明抽屉、播放设置抽屉、更多操作面板、播放页功能整页、定时关闭抽屉、音质选择抽屉、歌词面板、歌词换源弹层是根 `Stack` 里的覆盖层
（诊断抽屉、缓存清理抽屉、法律与免责声明抽屉、播放设置抽屉都叠在设置整页之上；音质选择抽屉从播放页功能整页打开，
下载品质是叠在设置整页上的三格分段），覆盖层的返回由
`IndexBackNavigation` 先于路由栈处置。底部抽屉
必须挂在这层根 `Stack`：`NavDestination` 里的页面是安全区内的页面层，抽屉外壳的
`expandSafeArea` 会被裁掉，状态栏 / 导航条会露出系统白底。播放页功能整页与设置整页同一形态：
根 `Stack` 上无蒙层、从右侧滑入的整页覆盖（320ms，`cubic-bezier(.32, .72, 0, 1)`）。歌词面板用 `expandSafeArea` 把同底色
画进状态栏（内容仍停在安全区内），展开后与播放页之间没有分割线或阴影；歌词面板与换源弹层因此把视图模型
（`LyricsPanelState`）提升到 `Index` 持有，由播放页与根覆盖层共用。页面组件位于
`components/native/`，通过构造参数接收 store、runtime 或回调。页头、错误条与空态这类「整页版式」
不再由各页面各抄一份：`components/native/MusicPageTemplate.ets` 提供 `MusicPageHeader` /
`MusicPageErrorBanner` / `MusicPageEmptyState` 三个纯展示组件（不持 store、不管多选与路由，
尺寸差异用显式参数表达，如历史 / 下载的 `compact` 窄版），我喜欢的、历史、下载、歌单详情、
合集详情五页共用；新增同类整页优先复用，不要重新发明 64 高页头或 44 高错误条。

界面选择器（`.id(...)`）的唯一真源是 `scripts/ui-ids.json`：`node scripts/ui-ids.mjs --write`
生成 `components/native/NativeUiIds.ets`（文件头标注禁止手改），`--check` 校验生成物同步、
组与字段唯一、派生表达式引用的 id 与动态方法存在、以及源码里没有引用未声明的成员。
`npm test` 在颜色守卫之后自动跑这道守卫；改选择器必须改 JSON 再生成，手改 .ets 会直接失败。
动态 id（如 `NativeUiIds.queueMore(index)`）不进 `all()`，既有契约测试依赖这一点。

根覆盖层的进出场统一走 `components/native/OverlayMotion.ets`：一个 `@Observed` 对象持有
`visible / offset / scrimAlpha` 和过渡代次，`Index` 为每个覆盖层各持有一个实例，
`open / enter / close / hideNow` 负责位移、蒙层与关闭回调的 token 校验，动画曲线由 `Index`
注入（抽屉 340ms、右侧滑入整页 320ms）。新增覆盖层不要再手写 visible / offset / scrim / token
四件套；歌词面板与歌词换源弹层（可见性由 `LyricsPanelState` 驱动）仍单独处理。

播放控制功能页里的「定时关闭」由 `Index` 持有的 `SleepTimerStore` 驱动：抽屉只负责选择
15 / 30 / 45 / 60 / 90 分钟档位并显示剩余时间，计时按绝对截止时间推进，关闭抽屉或退出功能页
都不会取消；到点只调用 `PlayerStore.pause()`，不退出应用，也不跨启动持久化。返回键顺序上，
定时关闭抽屉排在播放页功能整页之前。

播放音质偏好由 `SettingsStore` 持久化（`high` / `standard` / `low`，默认 `low` 即省流），实时选流由
`PlayerService` 持有。DASH 音频 id `30280` / `30232` / `30216` 对应高品质 / 标准 / 省流；只允许向下
降级，曲目没有目标档位时依次尝试更低档，不会向上提升。切换后 `PlayerService` 按当前进度重新装载
当前曲目，播放中继续播放、暂停中保持暂停；没有当前曲目时只更新偏好。设置页把「播放音质 / 自动播放 /
歌词显示」收进根覆盖层的 `PlaybackSettingsSheet` 抽屉：播放音质是三格分段（省流 / 标准 / 高品质），
点击即写偏好并让播放器重载；两个开关分别写 `restorePlayback` 与 `showLyrics`。播放页功能整页的音质格
仍用 `AudioQualitySheet`，界面只展示偏好档位，实际协商到的码率不回传 UI。返回键顺序上，播放设置抽屉
排在音质选择抽屉和设置整页之前。

下载品质由 `SettingsStore.downloadQuality` 单独持久化（`high` / `standard` / `low`，默认 `low`），
与播放音质完全解耦：设置页「下载 › 下载品质」同样是三格分段（省流 / 标准 / 高品质），点击即写
`downloadQuality`，下方另有一行说明文字。改动只影响之后发起的新下载，不重载当前曲目，也不重下已有文件。

### 底部抽屉

所有抽屉共用 `components/native/BottomSheet.ets` 一个外壳，样式只在那里定义一次：
标题 20 粗（左对齐，无右上关闭按钮）、左右 28、顶边 28 圆角、登录抽屉底色、
中央拖拽条，蒙层点击、拖拽条点按与下滑都收敛到 `onClose`。登录抽屉是这套 chrome
的模板，其它抽屉不再传字号 / 底色 / 圆角 / 内边距。

高度只有四个档位，定义在 `components/native/SheetSizing.ets`：

| 档位 | 折叠高度 | 使用方 |
| --- | --- | --- |
| 小 `Small` | 28%，钳制 232–300 | 登录账号抽屉、新建歌单 |
| 紧凑 `Compact` | 48%，钳制 392–440 | 登录扫码（无底部按钮）、音质选择 / 下载品质、播放设置 |
| 中 `Medium` | 59%，钳制 480–560 | 歌词换源、编辑歌单、缓存清理、定时关闭 |
| 大 `Large` | 78%，钳制 560–720 | 诊断信息、更多操作 |

四档都能从拖拽条或头部上拉到展开态，松手按距离或速度吸附；展开态不再铺满整屏，
而是停在安全区下方 16vp，顶边圆角全程保持 28，不会随高度收敛成方角。从折叠态
继续下拉时面板跟手下移，拖过 96vp（或快速下滑）即关闭，否则弹回折叠态。拖拽条
视觉仍是 36×4，热区扩到 64×40 并可点按关闭，作为读屏用户的无障碍入口。

安全区口径：蒙层用 `expandSafeArea` 盖住状态栏 + 导航条；面板只向下扩展绘制到底部
导航条，顶部不再铺进状态栏，因此展开后状态栏仍由蒙层压暗、面板顶边留出一条缝。
底部用 `safeAreaPadding` 把内容留在系统手势区之上。面板高度必须是百分比，固定 vp
高度会让底部的 `expandSafeArea` 失效。

抽屉内容组件的 `aboutToDisappear` 有两条硬约束：

- 不要写 `@State`：ArkUI 不允许在 `aboutToDisappear` 里改变状态变量，销毁期间写状态会让
  已销毁的组件再走一次重建。
- 不要同步 `dispose()`：`aboutToDisappear` 跑在 ArkUI 的 update 流程里，此时 `dispose()` 读
  `@Observed` 对象的非 `@Track` 字段（例如 `PlayerStore.unsubscribe()` 读 `listeners`）会触发
  `140110 Illegal usage of not @Track'ed property`，进程直接被杀。播放页功能整页 2026-11 的
  真机崩溃就是这条。

收尾统一用 `setTimeout(0)` 把释放动作挪出渲染上下文（参考 `PlayerControlPanel`）。根页面
`Index` 2026-11 也改为把 4 个页面级 store 的 `dispose()` 放进 `setTimeout(0)`，并且不再在
`aboutToDisappear` 里把 `@State` store 置 null。路由页（`NavDestination`）的卸载不走 update
流程，同步 dispose 目前没问题，但新增抽屉时按上面写。

### 音乐列表基准

`components/native/MusicTrackList.ets` 是后续所有音乐列表（历史、收藏、歌单、合集详情等）的
基准：`MusicTrackRow` / `MusicTrackToolbar` / `MusicSelectionBar` 三件套只定义一次尺寸与交互，
各页面传入当前播放 / 收藏 / 选中状态和回调。整页滚动 + 吸顶工具条、56 高透明行、标题 13/18
单行省略、副标题 12/16、行尾收藏 + 竖向更多；工具条左侧「全部播放（N）」，非多选时右侧是
多选入口，多选时同时显示「全选」（只切换勾选）与「关闭」（独立退出），行首勾选圈、行尾操作
隐藏，底部固定操作栏（删除 / 添加到；两项都是真实动作）。列表内的离线下载入口只在曲目操作
抽屉里（单曲 / 批量共用一行「下载」），列表底栏不单独加下载按钮；播放页功能整页另有「下载」格
（见「离线下载」）。新列表优先复用这三件套，只按页面
调整 Hero、序号、封面等局部；不要重新发明
行高、操作图标或选择栏。点击曲目行会在开始播放后直接进入播放页（歌单 / 我喜欢的 / 历史 /
合集详情一致；整页队列则切歌后返回已经打开的播放页）；播放装载失败时留在原列表并显示错误，
返回时原列表路由仍保留。

长列表（收藏 / 歌单 / 历史 / 合集 / 整页队列，上限 500 首）不再一次性铺满 `ForEach`：统一走
`components/native/TrackListPaging.ets` 的首屏 100 行 + `onReachEnd` 追加一页；行 key 用稳定的
曲目 key，只有队列里的重复曲目追加 `#序号`（纯 index 会在删行时重建后续所有行）。选中态、
播放态与批量操作仍读 store 快照，分页不改变语义。后续若迁移到 `LazyForEach + IDataSource`，
需先让行组件自持 store 订阅，否则已有的行不会随选中态更新。队列列表（播放功能页的紧凑列表与
整页队列共用 `QueueList`）打开时用 `visibleCountForIndex` 把首屏行数扩到当前播放行，再由
`List.initialIndex` 和一次性 `scrollToIndex` 居中定位；打开期间曲目自动切换不把列表拉回，
避免打断用户浏览。

「我的」（`MinePage`）不再有歌单 / 历史分段：页头下面固定四块 72 的快捷方块
（我喜欢的 / 历史 / 下载 / 新建歌单），间距 8，方块用 `layoutWeight(1) + aspectRatio(1)`
自适应，360vp 屏刚好 72、更宽时封顶 72。方块只有图标，我喜欢的 / 历史 / 下载右下角各有一颗
播放角标，点击即暂停 / 续播 / 从头播放整份列表；三项统一规则：列表为空时不渲染角标，只保留
点按整块进入对应路由页。方块下方直接是歌单列表，不再置顶「我喜欢的」行；「新建歌单」只有加号，
使用 accent-soft 底与虚线框。

「我喜欢的」（`FavoritesPage`）是这套基准的第一个复用方：
行高 / 工具条 / 多选 / 底栏全部照搬，只把页头改成自绘（返回 + 标题）、在列表上方加 Hero。
底栏同样是「删除 / 添加到」，批量收藏从「添加到」抽屉里的「加入我喜欢的」完成。Hero 与歌单详情页同构，但封面固定是
accent-action 黄底爱心，不展示真实曲目封面；空态只保留页头 + 空态，不渲染 Hero 和工具条。
多选删除走 `FavoritesStore.removeSelected`，由 `LibraryStore.removeFavorites` 一次原子写入，
失败时保留选中项，用户可直接重试。

「我的 · 历史」（`RecentPlaybackPage`）是独立整页，从右侧滑入（与「我喜欢的」同一进入方式），
页头是自绘的返回 + 「历史」。内容照搬这套工具条与多选：左侧「全部播放（N）」、
右侧多选入口；进入多选后工具条换成「全选 + 关闭」，行首勾选圈、行尾操作隐藏，底部固定
「删除 / 添加到」操作栏；添加到打开多曲抽屉，批量收藏在抽屉内完成。
行结构去掉序号和「正在播放」文案，当前曲目用标题前的播放态图标 + logo 橙标题色表示
（`nowPlaying` / `nowPlayingMark`，不铺行底色，避免和列表选中态混淆）；
批量删除不弹二次确认，点「删除」即一次原子写入（全选后删除等价于清空历史），
失败时保留选中项与列表，可直接重试。

### 离线下载

下载是「用户明确要求保存在本机」的持久化音频，和播放器的 `audio-v1-*` 临时缓存是两套东西：

- `services/DownloadService.ets` 负责解析音源、落盘和索引。文件写在 `filesDir/downloads-v1/`，
  索引 `filesDir/downloads-v1.json` 原子写入；「清理音频缓存」只动 `cacheDir`，不会删除下载。
  索引里只持久化文件名，绝对路径仅存在于服务内部与播放器打开文件时。
- 音源优先复用播放器的 `CatalogService.audioSource(track, quality)`，失败或为空时回退
  `progressiveAudioSource`；品质取设置里的 `downloadQuality`（与播放音质解耦，默认省流），
  只影响之后的新下载。DASH 候选存 `.m4s`、渐进式存 `.mp4`，单文件上限 64MB，损坏 / 不完整的临时文件立即删除。
- 最多保留 500 条、总占用不超过 4 GB（`MAX_TOTAL_DOWNLOAD_BYTES`）；条数或字节任一超限都按
  创建时间淘汰最旧条目并删除对应文件，刚下载成功的条目不会被立即淘汰。条数上限可在设置页
  「下载 › 最多存储」调整为 100 / 300 / 500 首（默认 500），调低后由
  `NativeAppRuntime.setDownloadLimit` 立即清理并刷新下载页，不等下一次下载。启动时清洗索引（版本不符、
  缺字段、非法文件名、重复 key、磁盘上已不存在）并保留损坏副本，下载页不会出现打不开的行。
- `state/DownloadStore.ets` 串行执行下载队列（避免并发抓多路媒体流），对已下载 / 正在下载 /
  同批重复的曲目跳过；`request()` 同步返回排队数与完成 promise，宿主先用排队数弹提示，
  完成后按成功 / 失败数再提示。页面只读 `tracks / downloadingKeys / selectedKeys`，
  不接触文件路径。
- `PlayerService` 通过 `DownloadedAudioLookup` 在 `openTrack` 前先查本地下载文件，命中即离线
  播放；本地文件打不开时释放 player 并回落到网络，不阻断播放。

「我的 · 下载」（`DownloadsPage`）与历史整页同构：右侧滑入、自绘页头、同样的工具条与 56 高行，
选择态底栏只保留「删除」（`MusicSelectionBar.showAdd = false`），删除即删文件和索引，不弹二次
确认；「添加到」仍走行尾更多抽屉。空态文案说明下载会保存在本机、离线可播。
下载入口有两处：曲目操作抽屉（单曲一行「下载」，多选时「下载所选歌曲」）和播放页
功能整页的「下载」格（只下载当前曲目）；两处都先交给宿主 `Index` 调用 `DownloadStore`
并弹底部 toast，功能整页的说明位直接反映已下载 / 下载中状态。

### 多 P 合集与批量加歌单

B 站多 P 视频在搜索列表里按「合集」展示；点击合集进入只读的合集详情页
（`CollectionDetailPage`），不再直接替换队列。详情页与歌单详情共用同一套音乐列表模板：
顶部 Hero 显示封面 / 标题 / 作者 / P 数，下面「全部播放（N）」+ 多选工具条与 56 高曲目行。
`MusicTrackList.ets` 提供 `MusicTrackRow` / `MusicTrackToolbar` / `MusicSelectionBar` 三个纯展示
组件，歌单详情、我喜欢的、历史、合集详情都从这里取同一份尺寸与交互。

- `CatalogService.search()` 对每条结果强制请求 `/x/web-interface/view`，即使 seed 已带 `cid`，
  避免把多 P 合集误判成单曲；`discover()` / `recommend()` 仍走 seed 直出，不额外发请求。
- view 结果缓存 LRU 48 条、TTL 10 分钟，并对同一 `bvid` 做 in-flight 去重；`pages` 缺失或
  数量少于 `data.videos` 时用 `/x/player/pagelist` 补齐。
- `MobileTrack.collectionSize` / `collectionTotalDuration` 是目录态字段，仅在搜索结果里存在，
  `SearchStore` 的克隆会保留，写入资料库 / 队列时按普通曲目丢弃。发现页搜索结果使用
  `CompactTrackRow`：单曲行不显示封面、保留右侧「更多」；`collectionSize > 1` 时显示 40×40 封面，
  并在封面右下角压「N首」徽标（accent 底 / onAccent 字，随封面 8 圆角裁切），作者行只保留
  作者、播放量与合集总时长。合集行不再渲染「更多」，整行点击直接进入合集详情。
  正在播放的行沿用歌单详情页样式（标题前音质图标 + logo 橙标记与标题色，不铺底色），
  行组件通过 `@ObjectLink playerStore` 自行订阅播放状态，从播放页返回搜索页时无需重建列表。
  搜索结果不提供分类栏，单曲与合集混排，合集行以「N首」徽标区分。
- 点击合集行：`Index.openCollectionRoute(bvid)` 压入 `ROUTE_COLLECTION`；`CollectionDetailStore`
  在页面内调用 `catalogCollection(bvid)` 展开全部 P。加载中显示 loading 态，失败显示错误 + 重试，
  不会自动播放、也不会回退到 P1。点击单个 P 把整份合集装载为队列并从该 P 开始播放，随后进入
  播放页；「全部播放」从第 0 P 开始并直接进入播放页。点击单曲仍把该曲放到队列首位并立即播放：
  队列为空时以该曲起播，队列中已有同一 `key` 时移动而不复制，播放结束后按原队列顺序继续；
  单曲点击始终从 0 开始（清掉该曲遗留进度），不沿用上次退出位置；队列已满 500 首且曲目不在
  队列中时提示清理队列。搜索结果不提供「播放全部」入口。
- 合集详情页支持与歌单相同的多选：全选 / 关闭、行首勾选圈，底栏只保留「添加到」（合集是远端
  只读内容，没有删除与编辑）；批量加入歌单或「我喜欢的」走根 Stack 的多曲抽屉。
- 每个 P 是独立 `MobileTrack`，`key` 为 `bvid:cid`，收藏、歌单、队列更多操作都按 P 独立生效。
  `partTrack` 用分 P 标题 / 时长，作者与封面继承父视频。
- 合集与展开后的队列都截断到 500 首（`MAX_COLLECTION_TRACKS`），徽标、总时长、队列和歌单
  使用同一份截断结果；单曲置顶同样受 `PLAYER_QUEUE_LIMIT` 的 500 首上限约束。
- 搜索结果合集行没有「更多」入口（整行点击已进入详情页）；单曲行的「更多」仍打开多曲抽屉。
  合集详情页加载失败只显示错误与重试，不会退化成单曲抽屉。
- 队列页完整行在「移除」左侧增加更多按钮（`NativeUiIds.queueMore(index)`，动态 id 不加入
  `NativeUiIds.all()`），可对任意 P 收藏 / 加入歌单；播放面板的紧凑行不展示该按钮。

批量加歌单走 `TrackActionStore` 的多曲模式：`openMany(tracks, contextTitle, suggestedName)`
把 `selectedTrack` 置空、填充 `selectedTracks`，`isOpen()` 以 `selectedTracks.length > 0` 为准
（`Index` 依赖它条件挂载抽屉）。`batchMode` 即使只有一首也不走单曲收藏切换，抽屉里改提供
批量「加入我喜欢的」：`addSelectedToFavorites()` 只补写 `favoriteCandidateCount` 计出的未收藏
曲目，已收藏的保持不动，全部已收藏时该行禁用并显示「所选曲目已在喜欢中」。歌单详情页
「全选 → 添加到」调用同一入口，打开后保留多选。

曲目操作抽屉里的收藏 / 取消收藏 / 加入我喜欢的 / 加入歌单在点击后立即收起，写入结果由 `Index`
宿主统一在根 Stack 最后一层自绘底部 toast（深色胶囊反色，浮在 dock 上方），抽屉内不再渲染成功或
错误反馈条。toast 走页面状态而不是系统 `showToast`，因此能稳定盖住抽屉 / 底栏，也能用布局和截图
取证。动作在收起前启动并同步捕获曲目，关闭抽屉不会中断写入；批量收藏在抽屉收起后仍会完成全部
候选曲目。toast 若早于 340ms 收起动画返回，会缓存到抽屉卸载后再显示。

`LibraryStore` 为此新增两个原子 mutation：

- `createPlaylistWithTracks(name, tracks, coverUri?, description?)`：新建与加曲一次写入，
  校验或写盘失败不会留下空歌单。
- `addTracksToPlaylist(playlistId, tracks)`：输入按 `key` 去重、跳过已有曲目，容量按**实际
  新增数**判断，超出 500 整体失败，不产生部分写入。

歌单两个抽屉采用宽松布局，外壳仍是统一的 `BottomSheet`，高度分别走小档（新建）和中档（编辑）：

- 新建歌单：只有一个无标签名称输入框，字数计数贴在输入框右下角，底部一个「创建」；
  新建态不提供封面上传，封面在编辑抽屉里设置。
- 编辑歌单：居中 88 封面（点按更换）+ 名称 + 简介，两个输入框同样无标签、计数内嵌，
  底部「保存修改」。名称 / 简介 / 自定义封面通过 `LibraryStore.updatePlaylist`
  一次写入、只产生一次持久化。

两个抽屉都按统一规范挂在根 Stack 上，不能放进 `NavDestination`（安全区扩展会被裁掉）。

设置页的「缓存清理」也走同一个外壳（中档 59%，`CacheSheet`），不再弹系统 `showAlertDialog`：
顶部是保留口径说明（不动收藏 / 歌单 / 登录 / 队列 / 进度），下面一张**无底色列表**列出
封面图片 / 歌词 / 音频三类的容量与条目——只做展示，不给行内清理按钮；清理只有底部通栏
「清理全部缓存」一个入口，顺序上先图片、后歌词、最后音频，某一类失败即停。
清理不弹二次确认（缓存可重建，抽屉本身就是确认面），空缓存 / 忙碌时按钮禁用；失败在抽屉内
显示错误条，并按出错的那一类调用 `CacheManagementStore.retry()`。容量文案与统计口径由
`CacheSizeFormat.ets` 的纯函数统一，设置行和抽屉不再各算一份。返回顺序里缓存抽屉排在
诊断抽屉之后、设置整页之前（`IndexBackAction.CloseCacheSheet`）。

设置页的「法律与免责声明」同样走统一外壳（大档 78%，`LegalNoticeSheet`），不再弹系统
`showAlertDialog`：**不设标题**，外壳头部整块收起、只剩拖拽条（与缓存清理 / 诊断信息
抽屉一致）；下方是一整段可滚动的免责声明正文，**不设底部动作按钮**——蒙层、
拖拽条、下滑和系统返回都能关闭抽屉。返回顺序里免责声明抽屉与缓存 / 诊断抽屉同一层，
排在诊断、缓存之后与设置整页之前（`IndexBackAction.CloseLegalSheet`）。

### 按压反馈

全应用**不使用按压态视觉反馈**（产品决定）：78 个 `Button` 全部在构造选项里显式写
`stateEffect: false`。ArkUI 的 `stateEffect` 默认是 `true`，省略不会关掉——新增按钮必须跟着写，
否则那个按钮会重新带回系统绘制的半透明按压蒙层（圆形图标按钮上就是一圈灰底）。

`design/*.html` 同步删除了全部 `:hover` / `:active` 规则：触屏没有 hover 态，`:active` 就是
原生端的这层蒙层。不要按「设计稿有 hover / active」去补实现，也不要引入 `.clickEffect()` 缩放
来替代——两者都会让这一约定重新分叉。

页面层负责：渲染加载、空、错误和安全区状态；收集用户输入和导航动作；从 store 读取可观察快照。
反过来的约束（不持有 Cookie/WBI/媒体地址、不复制播放器真相）见 `AGENTS.md` 的架构约定。

## 状态层

`state/` 是页面可消费的边界。`SearchStore`、`PlayerStore`、`LibraryStoreModel`、
`PlaylistStore`、`LyricsStore` 等把异步服务和页面动作收拢成稳定的 observable state。
所有订阅和定时器都要在 `dispose()` 或 `shutdown()` 中释放，避免 Ability 重建后重复回调。

`@Observed` + `@Track` 的 store 有一条硬约束：**build/update 期间会被调用的方法（例如行内
`isFavorite()` / `isPending()`）只能读 `@Track` 字段**。读未加 `@Track` 的私有字段会触发 ArkUI
`140110 Illegal usage of not @Track'ed property`，进程被直接杀掉（表现为点进页面就闪退）。
`disposed` 一类生命周期私有字段只允许出现在异步动作和 `dispose()` 里，不要放进渲染路径。

行内成员判定（`isFavorite()` / `isSelected()` / `isDownloaded()`）不要在数组上 `indexOf`：
`ForEach` 每次构建 / 刷新逐行调用，500 行就是 O(n²)。store 用 `state/KeySets.ets` 维护与数组
同源的 `@Track` `Set`，查询只做 O(1) `has()`。约定是随数组赋值**整份替换** `Set`（原地
`add` / `delete` 不会触发 `@Track` 刷新），列表数组本身也必须整体换新后发布。

子组件入参不会自动跟随父组件：ArkUI 只为带装饰器的成员生成 `updateStateVars()`，**未装饰的
普通成员停留在构造时的值**。所以「同一个组件换图形 / 换色」的入参必须是 `@Prop`——`AppIcon`
的 `iconKind` / `iconSize` / `iconColor` 与 `BottomDock.selectedTab` 都按这条处理。漏掉时界面
不会报错，只是图标停在旧状态，直到组件被销毁重建（退出重进页面）才更新，很容易被误判成
「点击没生效」。

## Runtime 边界

`NativeAppRuntime` 是服务聚合门面，主要职责是：

1. 按顺序创建 Cookie、HTTP、图片缓存、登录、目录、资料库、下载、播放器、媒体会话和歌词服务。
2. 把 service 事件接到 `PlayerStore` 和 `PlayerSessionStore`。
3. 对页面暴露快照和明确动作，而不是底层网络细节。
4. 串行执行 `initialize()`、`retry()` 和 `shutdown()`，收集非致命警告；初始化只等待本地服务，
   登录资料刷新是 ready 后的后台任务。资料库用 `LibraryStore.deferred()` + `loadAsync()`
   与媒体会话初始化并行读盘；歌词缓存首次取词时才异步读盘，二者都不占首帧。
5. 提供诊断信息和缓存清理入口。

服务实例由 runtime 持有。页面销毁时清理页面级 store；Ability 销毁时调用 runtime shutdown，
停止播放器、媒体会话和后台音频租约。

## 数据与文件

应用文件放在 `context.filesDir` 和 `context.cacheDir`：

- Cookie、资料库、设置、账号资料和播放会话使用带版本的 JSON；账号资料缓存不含 Cookie。
- `AtomicJson` 负责原子替换，损坏文件保留 `.corrupt-<timestamp>` 副本后回到默认状态；
  同一文件只保留最近两份副本，避免明文 Cookie 备份随冷启动累积。读盘有同步
  `readAtomicText` 与异步 `readAtomicTextAsync` 两条路径；冷启动优先用异步版，
  写入侧始终走 `AtomicFile` 原子替换。
- 图片缓存位于 `cacheDir/images-v1`，有大小上限和磁盘统计。
- 音频缓存位于 `cacheDir/audio-v1-*`，总量上限 512 MB，按 mtime 淘汰最久未使用的文件；
  命中时刷新 mtime，清理与统计与图片 / 歌词并列。
- 用户下载位于 `filesDir/downloads-v1/`，索引 `filesDir/downloads-v1.json`（默认最多 500 条、总计 4 GB，
  条数可在设置页调整）；
  清理音频缓存不会删除下载，删除只通过下载页的选择态批量删除。
- 播放位置按节奏持久化，且本地只保留当前曲目的一条记录；切歌会丢弃上一首的进度，冷启动由
  播放会话快照恢复。
- 不依赖网页 `localStorage`，避免原生状态和网页状态双写。

## 网络与安全边界

- 普通请求只使用 HTTPS，并限制到 B 站、图片和歌词服务需要的域名；URL authority 额外校验端口
  只能省略或为 `443`、拒绝 userinfo 与尾点主机；媒体主机只放行视频 CDN 与 `upos-*` 子域。
- `entry/src/main/resources/base/profile/network_config.json` 显式关闭明文流量
  （`cleartextTrafficPermitted: false`），与代码层白名单双重兜底。
- Cookie `Domain` 只接受响应主机的父域且拒绝公共后缀（`com`、`co.uk` 等），避免会话 Cookie
  被带到其它白名单域。
- 登录跳转逐跳校验 HTTPS 和允许的域名族，处理每一条 `Set-Cookie`。
- 二维码登录的 `qrcode_key`、Cookie、WBI 中间值和媒体地址只停留在原生层。
- 图片请求补充 Referer、超时、大小上限和图片 MIME 检查，不提供任意 URL 代理。
- 日志只记录脱敏的 host、状态码、错误码和布尔状态，不记录 query、Cookie 或完整媒体 URL。
