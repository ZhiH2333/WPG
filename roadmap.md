# WPG Roadmap

正式路线图，不是临时 TODO。领域与网络规格见 [`docs/ui_lobby_architecture.md`](docs/ui_lobby_architecture.md)。页面布局、wireframe、Back 栈、令牌见 [`docs/ui_screen_spec.md`](docs/ui_screen_spec.md)。逐日契约仍按「一天一个可验收交付」开工前另写 prompt；本文件锁定阶段目标、完成条件和不可违反的架构约束。三份冲突时以本文件为准。

---

## Vision

WPG 是俯视射击肉鸽。卖点是打起来有重量，不是功能清单更长。

1.0 桌面大厅的产品形状：

```text
Player Profile  →  Main Menu  →  Play  →  Solo / Multiplayer  →  Lobby  →  Combat
```

- **Profile** 回答「我是谁」。本机身份，无登录，不是网络认证。
- **Lobby** 回答「这间房里有谁、房间处于什么状态」。
- **Network** 只负责把人连上。UI 不直接操作 ENet。
- **Combat** 仍是现有 `CombatSandbox` + `RunSession` + `NetSession`。大厅对象随主菜单场景销毁，冻结成 `GameLaunch` 信封进沙盒。

信息架构参考 osu!lazer 的导航方式：顶栏全局导航、大面积内容空间、主体是视觉舞台、Overlay / Page、键鼠手柄都能走。不机械模仿 osu 的页面构图，也不把 PLAY 做成屏幕中央最大的一颗按钮。

美术方向是 Editorial / Graphic / Tactile：世界负责画面，UI 负责克制的导航。品牌字体是 TypeTogether Playpen Sans。FlatBold 是排版、剪切几何、少量表面、留白、轻材质和稀缺强调色，不是圆角卡片墙，也不是黑底发光 HUD。细则在 [`docs/ui_screen_spec.md`](docs/ui_screen_spec.md) 的 Typography & Art Direction。

旧作 Wild-Pig-Gun 只允许对照设计。禁止移植其 Autoload、UI 缩放器、云存档、账号、图鉴。

---

## Current State

以下全部是仓库里已经存在的事实。没有的东西不要写成已完成。

| 已有 | 证据 |
|---|---|
| Godot 4.6，纯 GDScript，Forward Plus，Autoload = 0 | `project.godot` |
| 主场景 `ui/main_menu.tscn` | 顶栏 + 中央 shear 三钮 + 多个 Overlay |
| Profile Overlay | 只读 `GameProgress` + `GameRecords` |
| 顶栏 Profile 文案 | `"best  %d"`，**不是**玩家名 |
| 本地存档三分 | `progress.cfg` / `records.json` / `settings.cfg` |
| ENet 多人、Host 权威、5 座、协议 5、快照 v3 | `GameLaunch.NET_*`、`LanOverlay`、`NetSession` |
| 游戏口 17777、发现口 17778 | `LanBeacon` Guest 探针 / Host 应答 |
| LAN 房间列表 + 搜索 + 手打 IP | Day 81 |
| Co-op 2–5、Battle FFA 2–5、十字出生、Roster 短血 | Day 78–85 |
| LAN 不写档 | Day 50 起锁死 |
| UI 动画 / 主题 | `UiAnim`、`UiFit`、`game_theme.tres` FlatBold |
| 四态音效 hover/click/back/error | 菜单与商店 |
| 战斗沙盒、句读、商店、跟班、三图 | Day 1–74 内容轨道 |

明确**还没有**：

- `PlayerProfile` / `user://profile.json`
- `LobbyManager` / `Room` / `LobbyPlayer` / `LobbyNet` / `JoinInvite`
- Ready 状态机（今天 handshake 完成就能 Start）
- 邀请 URI / QR / token / UPnP / IPv6 fallback
- 顶栏真实昵称
- 按意图区分的 Motion System（`exit_overlay` 仍是整页 fade）
- Playpen Sans 尚未进 `game_theme.tres`

README 曾写「下一步 Day 86 = 主动技能」。**本路线图取代该指针。** 主动技能仍是战斗内容，排在大厅离线 mock 能跑之后，不插进 Phase 1–3。

---

## Phase 1 — UI / UX Architecture

目标：把主菜单收成「顶栏全局导航 + Visual Stage + 轻量玩家状态 + Action Rail」，并开始按意图用动效，而不是再堆一套皮肤。布局以 [`docs/ui_screen_spec.md`](docs/ui_screen_spec.md) 为准。

PLAY 是主意图（进可玩上下文），不是屏幕上最大的物体。视觉权重靠位置、对比、留白、字号和动效一起建立。

包含：

- Main Menu IA：大面积 Visual Stage；玩家状态只有名字和一行状态；Action Rail 是 Continue / Solo / Multiplayer 三条同级操作。禁止中央巨大 PLAY，禁止把头像、成绩、档位和 Play 堆在中心
- TopBar：HOME / PLAY / MULTIPLAYER / PROFILE / SETTINGS，右端头像 + 显示名。Solo 不进顶栏。顶栏项是导航，不与 Rail 做成第二套等大按钮
- PLAY 打开 Play 页（Page），不是两张大 Modal 卡
- Profile 是自己的 Page。主页不放完整 Profile 卡
- Overlay 分层：Page / Drawer / Modal / Row / Status
- Design System：Playpen Sans 字级、炭黑/骨白/单一强调色、FlatBold 语法（令牌已写进 screen spec；本阶段开工前不改 `.tres`）
- 状态：Default / Hover / Focus / Selected / Disabled / Warning / Error / Success
- Motion：`UiAnim` 增加 page / modal / drawer / ready / connection 意图；Page 退出反向 24px；Modal 不升 56px
- Settings 打开时不关闭底下 Page
- 顶栏名字槽改占位 `Player`，禁止继续写 `best %d`（2026-09-26 该槽整槽移除：右端只留时钟，显示名改由 PROFILE 项承担）
- FlatBold 按新语法执行。禁止 osu 紫黑渐变、霓虹、发光描边、纯黑 HUD、卡片墙
- 实现顺序见 screen spec 末节

**不做：** 改 ENet、改协议、拆 `LanOverlay` 的 RPC（那是 Phase 4）、重排 LAN 内部 JOIN/HOST、`PlayerProfile` 磁盘（Phase 2）、主动技能、虚拟摇杆。

### Definition of Done

- 打开主菜单，最大的区域是空的 Visual Stage；其下是一行玩家状态和一条 Action Rail。没有中央巨大 PLAY，没有居中的 Profile 大卡
- Continue 只表示「用最近一档新开一局」。没有中途续打。无档时该格不占位
- TopBar 有 PLAY 与 MULTIPLAYER 导航，没有 Solo 项，也没有与 Rail 等大的第二套 SOLO / MULTI 巨钮
- PLAY 打开的是 Play 页，动效走 page，不是两张大卡 Modal
- 新/改过的 Overlay 调用了分意图的 `UiAnim`，不再复制升 56px 的 `enter_overlay` + 整页 fade 退出
- Settings 叠在当前 Page 上，关掉后仍在原 Page
- F5 进 Solo 档位、进现有 LAN，行为与 Day 85 无法分辨
- `project.godot` 仍无 Autoload

---

## Phase 2 — Profile

目标：本机真正拥有身份。顶栏不再把最佳成绩伪装成名字。

包含：

- `ui/player_profile.gd`（static Object，对齐 `GameProgress`）
- `user://profile.json`：`profile_id` / `display_name` / `avatar_id` / `preferred_character_id` / `version`
- 首次运行自动生成 UUID-like `profile_id`，显示名默认 `"Player"`，头像与常用角色默认 `boar`
- Profile Overlay：可改昵称（1–16）、头像、常用角色
- 统计列继续只读 `GameProgress`；档位列继续只读 `GameRecords`
- 主菜单顶栏显示 `display_name`（落在 PROFILE 项文案上，右端名字槽已删）

**不做：** 把 records / progress / settings 打进 Profile；登录；用 `profile_id` 当入房 token。

### Definition of Done

- 删掉 `user://profile.json` 再开游戏，会生成一份，且顶栏 PROFILE 项显示 `display_name` 而不是 `"best  0"`
- 改昵称后顶栏与 Profile 页立即一致，重开游戏仍在
- `progress.cfg` 与 `records.json` 字节结构不变
- best / last / runs 仍在 Profile 页统计列
- 无 Autoload、无新 InputMap action

---

## Phase 3 — Lobby

目标：房间是领域对象，不再是 IP。先离线 mock，再接网。

包含：

- `LobbyPlayer` / `Room` / `LobbyManager`（Node，挂 MainMenu 下，不是 Autoload）
- roster、seat 1–5、host、room lifecycle
- `ready` 与 `connection_state` 枚举先落地；第一刀 `ready` 默认 true
- 离线 mock：Create Room → Lobby → 假座位进出 → Start 写 `GameLaunch`（可不 bind 17777）
- `LanOverlay` 改为对 Manager 发命令；本 Phase **仍允许** Overlay 暂时继续持有 ENet，以免 LAN 一天内拆坏
- 借档：UI 读 `GameRecords`，种子写入 `Room`；档不上网

**不做：** 新的 `CombatSession` 类；`class_name NetworkSession`；UPnP；公网目录。

### Definition of Done

- 不插网线也能走完 Create → Lobby 座位墙 → Start（信封字段齐全）
- Room 快照能驱动座位行：Host / Empty / Character，而不是只显示 `127.0.0.1:17777`
- 现有 2 人 LAN 仍能开（允许仍走旧 Overlay RPC，只要 Manager 已是命令入口）
- 无 Autoload；`NetSession` 文件未改职责

---

## Phase 4 — Network Integration

目标：UI 不再直接操作 ENet。大厅 RPC 从 Overlay 迁到 `LobbyNet`。战斗 `NetSession` 零改职责。

包含：

- `LobbyNet`：`host_listen` / `client_connect` / `close` / peer 信号 / 大厅 RPC
- 抽出 `rpc_hello` / `hello_ok` / `guest_character` / `assign_seat` / `roster` / `goal` / `arena` / `play_mode` / `begin`
- pending peer 不进 `Room.players`；认证失败 disconnect，occupied 不变
- `LanBeacon` 改由 Manager 启停；`privacy=LAN_VISIBLE` 才 `start_host`
- `JoinInvite` 解析/生成接口（第一刀可只 lan+port）
- 一个 SceneTree `multiplayer_peer`
- 门票握手落地时协议 **只 bump 一次** 5→6

后续日（仍属本 Phase 轨道，不挤进第一刀）：IPv4/IPv6 顺序 fallback、可选 UPnP、WAN 直连。不为双栈建两个 peer。

**不做：** TURN/STUN、重连、Host 迁移、改快照 v3、改战斗 RPC。

### Definition of Done

- `LanOverlay.gd` 不再出现 `ENetMultiplayerPeer.new()` 与 `@rpc`
- 2 人 Pit Co-op 与 2 人 Yard Battle 回归日条款仍一次过
- 5 人进房、满员踢、号不前挪，与 Day 78/85 相同
- Guest 只在 Host peer 1 掉线时看到 Host closed
- `NetSession.gd` 的信号与 RPC 表未改职责
- Autoload = 0

---

## Phase 5 — Multiplayer UX

目标：玩家看见人、座位、Ready、房间状态，而不是看见 IP。

包含：

- Create Room（身份/角色/模式 → 房间设置 → Lobby）
- Join Room（列表 / 手打 / 邀请）
- Lobby 核心页：玩家列表、房间信息、连接状态、Invite、Ready、Start
- Invite Copy；QR 可同日或次日
- Error / Connecting / Failed / Version mismatch 有自己的反馈，不是再开一个大面板
- 房间卡主标题用 host 显示名；IP 放次级或 Invite Details
- Reconnect / timeout UX **仅当 1.0 最终支持时**；默认不支持，文案走现有 Host closed

**不做：** 匹配服务、房间目录、把 Invite 做成账号好友系统。

### Definition of Done

- MULTI 首页是三条紧凑导航（Create / Join / LAN Rooms）加本地最近房间。LAN Rooms 只是 Beacon 发现。没有三张大卡，没有公网房间目录
- Lobby 能读出：谁是 Host、谁 Connecting、谁 Ready、哪个座位空
- 复制邀请后另一台（或同机第二进程）能进同一房
- 手打 IPv4 仍为主路径之一
- 进沙盒后 HUD / 出生点 / 商店 / FFA 与 Phase 4 无法分辨

---

## Phase 6 — Final UI Polish

目标：动画有层级、有意义；键鼠手柄都能走完大厅；视觉一致。

包含：

- 按 Phase 1 意图把旧 Overlay 逐个换动效（顺手换皮，不强制一天全换）
- 音效：Ready / 进房 / 掉线 与 hover/click 分层
- 焦点环完整：Lobby 座位、Create 步骤、Invite 面板
- 控制器导航（完整手柄仍后置；本 Phase 只保证现有 Focus 合同不回退）
- `UiFit` 覆盖新页面；禁止 `size * ui_scale`
- 视觉一致性：新页面使用同一套 Playpen Sans 字级和 FlatBold 语法

其后另开的内容轨道（不阻塞 1.0 大厅）：

- 主动技能框架（原 README Day 86）
- 虚拟摇杆 + 触屏整包（原 Day 81–84 设想，已后置）
- 导出 Win/macOS/Linux、profiling、自建打洞

### Definition of Done

- 主菜单 → Profile → Play → Solo / Lobby → 回 Home，进出动效可区分 page/modal/drawer
- 无第三套皮肤混进新页面
- 大厅相关 Overlay 仍自管四态音效
- 文档：本文件与 `docs/ui_lobby_architecture.md`、`docs/ui_screen_spec.md`、README 下一步指针一致

---

## Non-Goals

当前阶段（Phase 1–6，1.0 大厅）明确不做：

- 账号系统、登录、云存档、后端、数据库
- 公网房间目录、匹配服务、专用服务器
- TURN / STUN 依赖、第三方云打洞
- Autoload；穿过战斗的 Lobby 单例
- 新的 `CombatSession` 类；`class_name NetworkSession`
- 为 IPv4 / IPv6 建立两个 `multiplayer_peer`
- 把 `GameProgress` / `GameRecords` / `GameSettings` 与 Profile 混成一个文件
- 机械模仿 osu!lazer 视觉
- Cyber / Neon / Glow / HUD，以及用粉紫描边制造层级
- 本阶段主动技能、虚拟摇杆、完整手柄适配
- 断线重连、Host 迁移
- 改战斗数字、四把枪身份、Motor 420、`look_ahead=100`、`COMPANION_CAP=10`
- 改 `physics_ticks_per_second`、`Engine.time_scale`、`reload_current_scene`

---

## Architecture Rules

1. Profile 不负责 Network。`profile_id` 不是 token、不是 seat、不是 peer。
2. UI 不直接操作 ENet。`LanOverlay` 最终只画、只发 `LobbyManager` 命令。
3. Lobby 不直接处理底层 socket。建连/关连/RPC 在 `LobbyNet`。
4. 大厅网络类名是 `LobbyNet`，禁止 `NetworkSession`（仓库已有战斗 `NetSession`）。
5. `GameProgress` / `GameRecords` / `GameSettings` 不与 Profile 混合。
6. 不为 IPv4 / IPv6 建立两个 `multiplayer_peer`。SceneTree 同一时间一个 peer。
7. 5 座上限保持。座位号不前挪。满员才踢。
8. LAN Beacon 仅用于同网发现，禁止扫网段。进战斗后停信标。
9. 无 Autoload。`LobbyManager` 是 MainMenu 子节点；`PlayerProfile` 是 static Object。
10. 换场仍用 `GameLaunch` take 一次。进沙盒后大厅对象销毁。战斗掉线走现有 `peer_lost`。
11. 协议因门票握手只 bump 一次 5→6。不要为显示名单独 bump。
12. LAN 仍不写档。Host 借档只种子 Room，不广播 records.json。
13. 1.0 不引入 `CombatSession`。Combat = `CombatSandbox` + `RunSession` + `NetSession`。
14. 每一刀必须能 F5 进现有 Solo；拆大厅中途不能开房，这一刀就不算完成。

---

## Implementation Sequence

```text
Phase 1  IA + Design System + Motion 意图     网络零改
Phase 2  PlayerProfile + 顶栏真名
Phase 3  Lobby domain + 离线 mock
Phase 4  LobbyNet 接入现有 ENet / 大厅 RPC
Phase 5  Create / Join / Lobby UX + Invite
Phase 6  动效 / 音效 / 焦点 polish
```

不要先把所有 UI 做完再接 Network。也不要先继续写 UPnP。

其它轨道（不写入 Phase 1–6 的 DoD）：

| 轨道 | 何时 |
|---|---|
| 主动技能 | Phase 3 离线 mock 可跑之后 |
| 虚拟摇杆 / 触屏 | 大厅 UX 稳定之后（原后置决定不变） |
| UPnP / IPv6 / WAN 直连 | Phase 4 末或 Phase 5，协议一次 bump |
| 导出 / profiling / 自建打洞 | 大厅 polish 之后 |

---

## Definition of Done（总）

Phase 1–6 全部完成时：

- 玩家有本机身份；顶栏是名字不是 `best 0`
- 多人体验以 Lobby 为核心页面，房间不是 IP
- Overlay 不持有 ENet 与座位权威
- 现有 2–5 人 Co-op / Battle、商店、跟班、三图、句读全部仍能打完
- 无账号、无 Autoload、无第二套 multiplayer_peer
- README「怎么运行」改为描述新 IA，并与本文件一致
