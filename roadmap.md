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
| 主场景 `ui/main_menu.tscn` | 顶栏（WPG 图标 + HOME/PLAY/MULTIPLAYER/PROFILE/SETTINGS + 时钟）+ Home 舞台块（Stage / Name / Status / Action Rail / Secondary / Quit）+ 6 层叠层 |
| Profile 页（Page 形态，`PAGE_PROFILE`） | 只读 `GameProgress` + `GameRecords`；昵称/头像/常用角色已就地读写 `PlayerProfile` |
| 顶栏 | 右端只有时钟，五个 tab 无名字/头像槽；PROFILE 项文案 = `PlayerProfile.display_name` |
| 本地存档三分 | `progress.cfg` / `records.json` / `settings.cfg` |
| 本机身份 | `ui/player_profile.gd` + `user://profile.json`（Phase 2）；顶栏 PROFILE 项文案 = `display_name` |
| Lobby domain（离线 mock） | `lobby/lobby_player.gd` / `lobby/room.gd` / `lobby/lobby_manager.gd`；MainMenu 下 `LobbyManager` 节点；LanOverlay 座位墙读 Room 快照 |
| `LobbyNet`（大厅网络层） | `lobby/lobby_net.gd`：唯一持有 `ENetMultiplayerPeer` 与大厅 `@rpc` 的文件；`NetState` 状态机、座位缓存、roster 编解码、`parse_address()` |
| Ready 状态机 | Host 恒 `HOST`（不参与 Start）；Guest 进房默认 NOT READY；改角色 / 改 Mode·Arena·Goal → 旧 READY 失效；Ready 走独立 RPC（`rpc_ready` / `rpc_apply_ready`，协议仍 5） |
| MULTIPLAYER 首页 + Lobby 核心页 | `LanOverlay` 的 HOME / LAN Rooms / Join invite / Create Room（含隐私）/ Lobby；Starting 冻结；掉线先播 `PLAYERxx LEFT` 再画回 EMPTY SEAT |
| 移动端触控输入 | `ui/mobile/`（`virtual_stick` / `touch_aim_pad` / `touch_action_button` / `touch_input` / `safe_area_root` / `mobile_hud_scaler`）+ Touch API（`PlayerInput.set_touch_*` / `queue_touch_*`） |
| ENet 多人、Host 权威、5 座、协议 5、快照 v3 | `GameLaunch.NET_*`、`LanOverlay`、`NetSession` |
| 游戏口 17777、发现口 17778 | `LanBeacon` Guest 探针 / Host 应答 |
| LAN 房间列表 + 搜索 + 手打 IP | Day 81 |
| Co-op 2–5、Battle FFA 2–5、十字出生、Roster 短血 | Day 78–85 |
| LAN 不写档 | Day 50 起锁死 |
| UI 动画 / 主题 | `UiAnim`、`UiFit`、`game_theme.tres` FlatBold |
| 四态音效 hover/click/back/error | 菜单与商店 |
| 战斗沙盒、句读、商店、跟班、三图 | Day 1–74 内容轨道 |

明确**还没有**：

- `JoinInvite` 的完整形态（当前只有 `LobbyNet.parse_address()` 这一刀的 LAN IPv4 解析）与邀请 URI / QR 真连接 / token
- 协议 6 的门票握手（协议仍 5，`rpc_hello` 只带协议号）
- Guest 侧看到别人的身份：协议 5 的 roster 包只带座位角色，不带 profile_id / 昵称（Guest 的 Lobby 投影只有 Host + 自己）
- `ConnectionPath`（IPv6 / WAN 直连）、UPnP、P2P 打洞
- 断线重连、Host 迁移（1.0 明确不做）
- 移动端 P2P 与 Android 真机发布链路（表中原 Phase 5 只做 Vertical Slice 的桌面验证）
- `AbilityDef` / `AbilityController` 主动技能框架（表中原 Phase 6）
- Playpen Sans 尚未进 `game_theme.tres`（仓库无任何 `.ttf/.otf`，主题仍是 system 回落 Inter/Segoe UI/Noto Sans/Arial）
- 战斗侧 4 个 overlay 仍用 `enter_overlay/exit_overlay`（`pause_overlay` / `shop_offer` / `upgrade_offer` / `room_notice`），归最终 polish
- 无 Warning / Success 语义令牌

README 曾写「下一步 Day 86 = 主动技能」。**本路线图取代该指针。**
README 曾写「下一步 Day 86 = 主动技能」。**本路线图取代该指针。** 主动技能仍是战斗内容，排在大厅离线 mock 能跑之后，不插进 Phase 1–3。

---

## 阶段划分（2026-09-26 起，当前有效）

下面 Phase 1–6 是上一轮编号，其 **Non-Goals / Architecture Rules / 各段「不做」清单继续是硬约束**；阶段排期与验收以下表为准（内容吸收旧的 Phase 3–6）。

| # | 阶段 | 状态 | 核心交付 | 不做 |
|---|---|---|---|---|
| 1 | 文档同步 | 已完成 | 四份文档与 dev 代码一致；删掉「UI 尚未实现 / 顶栏 best 0」类旧状态 | 不为文档同步改游戏逻辑 |
| 2 | PlayerProfile | 已完成 | `ui/player_profile.gd` + `user://profile.json`；Profile 页就地改名/头像/常用角色；顶栏 PROFILE 项 = `display_name` | 不进 progress/records/settings；`profile_id` 不当 token / seat / peer_id；无 Autoload |
| 3 | Lobby domain（离线 mock） | 已完成 (2026-09-27) | `LobbyPlayer` / `Room` / `LobbyManager`（挂 MainMenu 下）；Create → Lobby → 假座位进出 → Ready → Start → `GameLaunch` | 不碰 `NetSession`；不做 WAN / P2P；不 bump 协议 |
| 4 | 移动端输入抽象 | 已完成 (2026-10-01) | `VirtualStick` / `TouchActionButton` / 轻量 TouchInput 适配层；左摇杆移动、右摇杆瞄准、主射击、Dash、技能预留按钮 | 不写 `TouchPlayerInput` / `TouchPlayer` / `TouchCombat`；不复制战斗逻辑 |
| 5 | 移动端 Vertical Slice | 已完成 (2026-10-02) | Android → MainMenu → Solo → Combat → Pause → Winner；export preset、renderer 可行性、Safe Area / UiFit / 触控命中 / 性能 | 移动端 P2P；直接套用 Desktop Forward+ 假设 |
| 6 | Ability Framework | 已完成（已冻结，不再扩展） | `AbilityDef` / `AbilityController` / `AbilityState` / `AbilityEffect` + cooldown / duration / cost；输入只给 `ability_0/1` → `try_activate(index)` | 不绑键盘/鼠标/Pad/触屏按键；不先堆技能数量；冻结后不因联网「顺手」改技能 |
| 7 | LobbyNet | 已完成 (2026-10-02) | `LobbyNet`（host_listen / client_connect / hello / roster / ready / start / connection state）；`LanOverlay` 最终只发 Manager 命令 | UI 不得建 `ENetMultiplayerPeer`；`NetSession` 职责不变 |
| 8 | JoinInvite / ConnectionPath / protocol 6 | 已完成 (2026-10-02) | `lobby/join_invite.gd`（create / parse / 严格校验）+ `lobby/connection_path.gd`（LAN_IPV4 → IPV6 → WAN_IPV4 候选排序，不持有 peer）+ 协议 5→6 ticket handshake（`hello(protocol, token)`，Host 权威校验）+ LanBeacon 带 room_id / host_display_name | UI 不拼 IP / Port / Token；不直接做复杂打洞；不做 STUN / TURN / UPnP / rendezvous |
| 8.5 | Phase 8 hardening | 已完成 | `ConnectAttempt` + `ConnectAttemptRunner`：`create_client()` 返回 true **不等于**连接成功，必须等真实 `connected_to_server` + 握手；attempt_id 隔离延迟回调；换候选前必 `close()`（任意时刻一个 active peer）；结果分类 CONNECT_TIMEOUT / CONNECTION_FAILED / SOCKET_ERROR / VERSION_MISMATCH / TICKET_REJECTED / CONNECTED；协议/ticket 问题不换路径重试；三级超时集中定义；ticket lifecycle 定为**方案 A（复用 room ticket）**，仅 `rotate_room_ticket()` 换票 | 不为「安全」自行加复杂机制；不许 profile_id / room_id / seat / peer_id 当 ticket；不引入第二套 peer |
| 9.1 | P2P state machine + rendezvous contract | 已完成 | `lobby/p2p_connection_state.gd`（纯状态机：DISCONNECTED → RENDEZVOUS_* → CANDIDATES_RECEIVED → DIRECT_CONNECTING → HANDSHAKING → CONNECTED，终态含 FAILED / TIMEOUT / TICKET_REJECTED / VERSION_MISMATCH；非法转换返回 false 且状态不变；不依赖 SceneTree / 不持有 peer）+ `lobby/rendezvous_contract.gd`（纯数据 contract：会话身份 / 候选 / 会话状态 + 版本化编解码，`observed_*` 为 NAT 穿透预留且不伪造）+ `lobby/p2p_connection.gd`（编排器，经 `bind_transport()` 复用 LobbyNet 单 peer 建连） | **不实现真 NAT hole punching**；不做 STUN / TURN / UPnP / Relay / Host migration / reconnect；rendezvous 不承载游戏流量；`NetSession` 不接手 rendezvous；UI 不接触 packet format；不改 CombatNetSession / snapshot v3 / Ability Framework |
| 9.2.1 | Rendezvous + observed endpoint | 已完成 | `tools/p2p/rendezvous/`（纯标准库 Python 服务端：register / match / candidate exchange / observed endpoint / session 生命周期 / idle cleanup；`server.py` / `protocol.py` / `stun.py` / `test_server.py` / README）+ `lobby/rendezvous_client.gd`（**PacketPeerUDP，非 ENet**，不占 SceneTree peer；REGISTER / REGISTERED / PEER_READY / CANDIDATES / ERROR / BYE）+ `RendezvousContract` **升 wire v2**（每条消息带 `session_id`，新增 `PEER_READY` / `ERROR`，observed endpoint 承载；v1 包明确 `BAD_VERSION`）+ 最小 RFC 5389 STUN Binding Request 客户端（`XOR-MAPPED-ADDRESS` 解析，只为拿 NAT 映射端点）+ `P2PConnection.bind_rendezvous()` / `poll_rendezvous()` 接缝（状态真实走 RENDEZVOUS_CONNECTING → RENDEZVOUS_REGISTERED → CANDIDATES_RECEIVED，**不直接假装 CONNECTED**） | **不做真 NAT hole punching**；不做 UDP simultaneous open / 多端口快速探测 / ICE / TURN / Relay / UPnP / Host migration / reconnect；rendezvous **不是 Relay**、不承载游戏流量、不分配 seat、不拥有 `Room.players`、不是最终准入权威（最终仍由 Host protocol 6 ticket handshake 决定）；observed endpoint 只能由服务端 / STUN 写入，严禁用本地地址或客户端自报值伪造；server 不访问 Combat |
| 9.2.2 | NAT hole punching | 已完成 | `lobby/p2p_hole_punch.gd` / `lobby/p2p_udp_probe.gd`：UDP simultaneous open、多端口快速探测、probe_id correlation、source address/port 验证、shared PacketPeerUDP、rendezvous observed endpoint 复用、bounded real-frame pumping、cancel/reset 清理；`tests/integration/p2p_hole_punch_integration_test.gd` 真 loopback 回归 | 不做 TURN / Relay；不承诺所有 NAT 都能直连（对称 NAT 需 Relay，属后续） |
| 9.2.3 | Direct ENet validation | 已完成（真多进程 E2E 验证） | 只有 **Guest** 在 validated path 上 `begin_direct_enet()` → `LobbyNet.client_connect()` → 真实 `connected_to_server` → protocol 6 `rpc_hello(protocol, ticket)` → Host 权威校验 → `rpc_hello_ok` + `rpc_assign_seat(seat=2)` → `peer_confirmed` → `CONNECTED`；Host 侧 `start_p2p_hosting()` 只注册 rendezvous 并**保持自己的 ENet server**，绝不 client_connect；负向路径（坏 ticket / 坏协议号）走完 rendezvous → hole punch → Direct ENet → protocol 6 → Host `check_ticket()` 判 BAD_TOKEN / BAD_PROTOCOL → `rpc_join_rejected` → 踢人，Guest 终态 TICKET_REJECTED / VERSION_MISMATCH 且不占座（ENet 连上 ≠ 大厅连上）；真多进程 E2E：success 20/20、wrong ticket 5/5、wrong protocol 5/5（`tools/p2p/e2e_direct_enet_test.py`，产物只在临时目录）；9.2.2 打洞回归 20/20；`tests/integration/p2p_production_flow_test.gd` + `tests/integration/p2p_hole_punch_integration_test.gd` 回归覆盖 | 不改战斗 snapshot v3；不同时两个 peer；不做 TURN / Relay / UPnP / Host migration / reconnect |
| 10.1 | 桌面端最终集成（Solo / LAN / WAN-P2P） | 已完成（真多进程 E2E 验证） | 把桌面入口 → Lobby → Ready → Start → Battle → 退回/退出收成一条产品闭环：Solo（无 peer）、LAN Host/Guest、WAN(P2P) Host/Guest 全部走同一套 `MainMenu` + `LobbyManager` + `LanOverlay`。核心交付：换场交接合同（`LobbyNet.release_peer_for_handoff()` 把 SceneTree peer 保留给战斗层、`LobbyNet.force_close_peer()` 负责明确断网，避免 MainMenu 换场释放时把战斗网络掐断）；Guest 开局信封补 `GameLaunch.set_local_seat()`；`HOST OVER INTERNET` 走 `host_room` + `create_p2p_invite` + `start_p2p_hosting`（Host 绝不 `begin_direct_enet`），Guest 一律 `join_invite()` 生产入口。真多进程 E2E：LAN UI（建房 → 加入/READY → START → 双方 Battle → 退回清场）、WAN P2P（invite → join_invite → rendezvous → 打洞 → Direct ENet → protocol 6 → seat 2 → Battle → 清场）、失败清理（错 ticket 被拒 → Host `close_network()` 重启房 → Guest 重连 seat 2 → Battle → 无残留 peer）；单测 `tests/unit/lobby_peer_handoff_test.gd` 覆盖交接/清理/取消/Solo 无 peer/主菜单无 peer | 不改战斗 snapshot v3；不加第二个 `SceneTree.multiplayer_peer`；协议号保持 6；不动 Ability Framework；不做 Android / Skill multiplayer |
| 10.2 | Android + Skill multiplayer + 收尾 | 进行中（拆成 10.2.x） | Android Solo/LAN/WAN；Skill multiplayer 同步；reconnect / timeout 打磨；profiling / release | 不为 P2P 改战斗快照结构（除非规格明确要求） |
| 10.2.1 | Android 网络接入 + 正式 APK + 真机 LAN 联调 | 部分完成（APK / 权限 / 静态与桌面回归 DONE；真机 Solo / 双向 LAN / discovery 为 **VERIFICATION PENDING**） | 修正 Android preset `permissions/internet=false` → `true`，并**核对编译进 APK 的 manifest**而非只看配置：新增 `tools/build/axml.py`（纯标准库 AXML 读取）+ `tools/build/verify_package.py` 的 INTERNET 断言（否则该 flag 再次被改回也没人发现）+ `tools/test/test_axml.py`；用现有 Godot 4.6.2 Gradle 工具链导出 arm64 debug APK，`aapt2` / 新校验器均确认 `android.permission.INTERNET` 在包内且**只有这一个**权限；审计确认硬约束未回退（LobbyNet 仍是 Lobby ENet 唯一生产 owner、LobbyManager 不碰 ENet、UI 不建 peer、Solo 无 peer、`GameLaunch`→`NetSession` 换场合同不变）；桌面回归跑通 validate / architecture / unit(32/36) / integration(3/5) / 7 套 LAN-P2P E2E 全绿。模拟器补充：APK 在 API 37 安装并启动、INTERNET `granted=true`、主菜单态 App **不持有任何 UDP socket** | 不批量打开无关权限（相机 / 定位 / 存储）；不动 Windows/macOS/Linux/Web/iOS preset；不改 Ability Framework / Combat snapshot v3 / protocol 6；不复制 Android 专用 Lobby 或 Combat；不把回环 E2E 当公网验收 |

阶段 3 起每阶的硬性验收（沿用 Architecture Rules）：能 F5 进 Solo、无 Autoload、`NetSession` 只服务战斗、Lobby 网络全归 `LobbyNet`、UI 不碰 ENet、Touch 不复制 Combat、Skill 不绑设备、四份存档继续分离、LAN 不写档、每阶完成同步 roadmap / README。

**已完成的阶段与旧编号的对应**：旧编号 `Phase 4 — Network Integration` = 表中阶段 7（2026-10-02 完成）；旧编号 `Phase 5 — Multiplayer UX` = 表中阶段 5 之外的 Multiplayer 簇（MULTIPLAYER 首页 / Create / LAN Rooms / Join invite / Lobby 核心页 / Starting），同样 2026-10-02 完成。表中原阶段 4/5（移动端）已于 2026-10-01 / 10-02 完成，文档同步落后过一轮，本次补齐。


---

## Phase 1（已完成 2026-09-26）— UI / UX Architecture

目标：把主菜单收成「顶栏全局导航 + Visual Stage + 轻量玩家状态 + Action Rail」，并开始按意图用动效，而不是再堆一套皮肤。布局以 [`docs/ui_screen_spec.md`](docs/ui_screen_spec.md) 为准。

PLAY 是主意图（进可玩上下文），不是屏幕上最大的物体。视觉权重靠位置、对比、留白、字号和动效一起建立。

包含：

- Main Menu IA：大面积 Visual Stage；玩家状态只有名字和一行状态；Action Rail 是 Continue / Solo / Multiplayer 三条同级操作。禁止中央巨大 PLAY，禁止把头像、成绩、档位和 Play 堆在中心
- TopBar：WPG 图标 + HOME / PLAY / MULTIPLAYER / PROFILE / SETTINGS（每项带图标），右端**只有时钟** —— 头像 + 显示名槽已于 2026-09-26 整槽移除。Solo 不进顶栏。顶栏项是导航，不与 Rail 做成第二套等大按钮
- PLAY 打开 Play 页（Page），不是两张大 Modal 卡
- Profile 是自己的 Page。主页不放完整 Profile 卡
- Overlay 分层：Page / Drawer / Modal / Row / Status
- Design System：Playpen Sans 字级、炭黑/骨白/单一强调色、FlatBold 语法（令牌已在 `ui/game_theme.tres` 落地并成为唯一来源：全 `sb_flat_*`、圆角统一 6、无阴影、focus 下划线、脚本禁止 `StyleBoxFlat.new()`）
- 状态：已落地 Default / Hover / Pressed / Disabled / Focus 五态 + 危险色 `sb_flat_pill_red`；**仍缺** Warning / Success / Selected 令牌，状态反馈暂由 `UiAnim.flash_error/flash_ready/pulse_connection` 承担
- Motion（已完成）：`UiAnim` 的 page / modal / drawer / ready / error / connection 意图；`PAGE_RISE_PX = 24`；Modal 只有 fade + scale 不进位上浮；顶栏 tab 是水平翻页（`PAGE_SLIDE_SEC 0.32` / `TRANS_CUBIC` / `EASE_OUT`，刚性纸带）
- Settings 打开时不关闭底下 Page
- 顶栏无名字槽（2026-09-26 整槽移除，右端只留时钟）；Home 的 Name/Status 显示占位 `Player` / `Ready to play`（`main_menu.gd` PLACEHOLDER_NAME）；PROFILE 项文案在 Phase 2 接 `display_name`
- FlatBold 按新语法执行。禁止 osu 紫黑渐变、霓虹、发光描边、纯黑 HUD、卡片墙
- 实现顺序见 screen spec 末节

**不做：** 改 ENet、改协议、拆 `LanOverlay` 的 RPC（那是 Phase 4）、重排 LAN 内部 JOIN/HOST、`PlayerProfile` 磁盘（Phase 2）、主动技能、虚拟摇杆。

### Definition of Done

**状态：已完成（2026-09-26）。** 未清尾项：① Playpen Sans 未接；② 战斗侧 4 个 overlay 仍 `enter_overlay/exit_overlay`（Phase 6）；③ 无 Warning/Success 令牌。

- 打开主菜单，最大的区域是空的 Visual Stage；其下是一行玩家状态和一条 Action Rail。没有中央巨大 PLAY，没有居中的 Profile 大卡
- Continue 只表示「用最近一档新开一局」。没有中途续打。无档时该格不占位
- TopBar 有 PLAY 与 MULTIPLAYER 导航，没有 Solo 项，也没有与 Rail 等大的第二套 SOLO / MULTI 巨钮
- PLAY 打开的是 Play 页，动效走 page，不是两张大卡 Modal
- 新/改过的 Overlay 调用了分意图的 `UiAnim`，不再复制升 56px 的 `enter_overlay` + 整页 fade 退出
- Settings 叠在当前 Page 上，关掉后仍在原 Page
- F5 进 Solo 档位、进现有 LAN，行为与 Day 85 无法分辨
- `project.godot` 仍无 Autoload

---

## Phase 2（已完成 2026-09-26）— Profile

目标：本机真正拥有身份。顶栏不再把最佳成绩伪装成名字。

包含：

- `ui/player_profile.gd`（static Object，对齐 `GameProgress`）
- `user://profile.json`：`profile_id` / `display_name` / `avatar_id` / `preferred_character_id` / `version`
- 首次运行自动生成 UUID-like `profile_id`，显示名默认 `"Player"`，头像与常用角色默认 `boar`
- Profile Overlay：可改昵称（1–16）、头像、常用角色
- 统计列继续只读 `GameProgress`；档位列继续只读 `GameRecords`
- 主菜单顶栏显示 `display_name`（落在 PROFILE 项文案上，右端名字槽已删；已落地）

**不做：** 把 records / progress / settings 打进 Profile；登录；用 `profile_id` 当入房 token。

### Definition of Done

**状态：已完成（2026-09-26）。** `ui/player_profile.gd`（static Object，原子写 `.tmp → rename`）+ Profile 页就地改名/换头像/选常用角色 + 顶栏 PROFILE 项 = `display_name`；实测首启生成、夹 16 字符、空名回默认、控制字符清理、`progress.cfg`/`records.json`/`settings.cfg` 字节未变。

- 删掉 `user://profile.json` 再开游戏，会生成一份，且顶栏 PROFILE 项从固定字面 `PROFILE` 变成 `display_name`（Home 的 `BEST LOOP` 格读数与顶栏无关）
- 改昵称后顶栏与 Profile 页立即一致，重开游戏仍在
- `progress.cfg` 与 `records.json` 字节结构不变
- best / last / runs 仍在 Profile 页统计列
- 无 Autoload、无新 InputMap action

---

## Phase 3（已完成 2026-09-27）— Lobby

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

**状态：已完成（2026-09-27）。** 落地：`lobby/lobby_player.gd` / `lobby/room.gd` / `lobby/lobby_manager.gd` + MainMenu 下 `LobbyManager` 节点 + LanOverlay 座位墙（读 Room 快照）+ `tests/lobby_domain_test.gd` + `tools/ci/architecture.py` 的 Lobby 域守卫。未做（留给旧编号 Phase 4/7 轨道）：`LobbyNet`、`JoinInvite`、`LobbyNet` 接管 `@rpc`、Guest 侧 Room 同步（协议 5 不回传身份，Guest 仍是旧 Overlay RPC 路径）。

- 不插网线也能走完 Create → Lobby 座位墙 → Start（信封字段齐全）：实测 HOST 视图 5 行座位 + 状态行 + Start 门槛；离线房间 Start 走 `OFFLINE` 信封（`active_record_id` / `arena_id` / `mode` / local seat 齐），真房间走 `HOST` 信封（roster 角色 + peer 齐）
- Room 快照能驱动座位行：Host / Empty / Character，而不是只显示 `127.0.0.1:17777`
- 现有 2 人 LAN 仍能开（允许仍走旧 Overlay RPC，只要 Manager 已是命令入口）：两进程实测 Host 座位墙出现真实 Guest（`Player 02`，CONNECTED），`peers=[1, <guest>]`、Guest 侧 `seat  2` + roster 到位
- 无 Autoload；`NetSession` 文件未改职责

---

## Phase 4（已完成 2026-10-02）— Network Integration

**状态：已完成（2026-10-02）。** 落地：`lobby/lobby_net.gd`（唯一 `ENetMultiplayerPeer` / 大厅 `@rpc` 归属）+ `LobbyManager` 网络命令与信号接线 + `LanOverlay` 去除 ENet / RPC + `tests/lobby_net_test.gd` + `tools/ci/architecture.py` 守卫固化。协议仍 **5**（Ready 同步是独立可靠 RPC，不动 roster 包、不 bump 协议）；`NetSession` 未改职责。未做（留给表中原阶段 8/9）：`JoinInvite.create()` 完整形态、`ConnectionPath`、IPv6/WAN 顺序 fallback、UPnP。

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

## Phase 5（已完成 2026-10-02）— Multiplayer UX

**状态：已完成（2026-10-02）。** 落地：MULTIPLAYER 首页（Quick join / Create room / LAN rooms / Join invite / RECENT）+ Create Room 同页（Mode / Arena / Goal / Privacy）+ LAN Rooms 紧凑行（JOIN / FULL）+ JOIN INVITE（`LobbyNet.parse_address()` + Copy invite / Show QR shell）+ Lobby 核心页（5 行座位 / Ready / Starting 冻结 / `PLAYERxx LEFT`）+ 连接失败 · 协议不符 · Host closed 的页内状态文案；`tests/multiplayer_page_test.gd` 固化 UI 契约。未做（留给表中原阶段 8/9 与后续 polish）：真 QR / token、房间卡主标题用 Host 显示名（发现包未扩）、reconnect / timeout UX（1.0 默认不支持）。

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
- 焦点策略：**任何界面打开都不自动聚焦**（2026-10-02 起全界面生效，见 `ui/ui_focus.gd` 与 screen spec §2.0）；键盘 / 手柄第一次按导航键才建立焦点，鼠标玩家全程无焦点环。禁止再写「打开就 `grab_focus()`」
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
AI + Design System + Motion 意图        网络零改   ← 已完成 2026-09-26
PlayerProfile + 顶栏真名                       ← 已完成 2026-09-26
Lobby domain + 离线 mock                       ← 已完成 2026-09-27
移动端输入抽象 + Vertical Slice                ← 已完成 2026-10-01 / 10-02
Ability Framework                              ← 已完成（已冻结，不再扩展）
LobbyNet 接入 ENet / 大厅 RPC + Ready 同步      ← 已完成 2026-10-02
Multiplayer UX（Create / Join / Lobby / Invite） ← 已完成 2026-10-02
Guest Start 换场（Lobby -> CombatSandbox）      ← 已完成（fix: guest enters combat after lobby start）
JoinInvite / ConnectionPath / protocol 6        ← 已完成 2026-10-02
Phase 8 hardening（异步回退 + ticket lifecycle） ← 已完成
Phase 9.1 P2P state machine + rendezvous 契约   ← 已完成（不含真 NAT 打洞）
Phase 9.2.1 公网 rendezvous + observed endpoint   ← 已完成（真实 UDP 交换已跑通）
Phase 9.2.2 NAT hole punching                     ← 已完成（UDP simultaneous open / probe_id correlation / shared UDP / bounded pumping / cancel-reset）
Phase 9.2.3 Direct ENet validation                 ← 已完成（真多进程 E2E：success 20/20 / wrong ticket 5/5 / wrong protocol 5/5；只有 Guest 发起 Direct ENet，Host 保持自己的 ENet server）
Phase 10.1 桌面端 Solo/LAN/WAN-P2P 最终集成        ← 已完成（真多进程 E2E：LAN UI / WAN P2P / 失败清理；换场 peer 交接合同）
Phase 10.2.1 Android 网络接入 + 正式 APK + 真机 LAN  ← 部分完成：APK/权限/静态与桌面回归 DONE；真机 Solo/双向 LAN/discovery VERIFICATION PENDING（无真机）
```

不要先把所有 UI 做完再接 Network。也不要先继续写 UPnP。

当前实际状态口径（三份文档必须一致）：
**Ability Framework = DONE（已冻结）**，**LobbyNet = DONE**，**Multiplayer UX = DONE**，
**Guest Start transition = DONE**，**Phase 8 = JoinInvite / ConnectionPath / protocol 6 ticket handshake = DONE**，
**Phase 8 hardening = DONE（ConnectAttempt / 三级超时 / ticket 复用）**，
**Phase 9.1 = P2P state machine + rendezvous contract = DONE（不含真打洞）**，
**Phase 9.2.1 = 公网 rendezvous service + Guest/Host 注册与候选交换 + observed endpoint = DONE**，
**Phase 9.2.2 = 真 NAT 穿透 = DONE**，**Phase 9.2.3 = Direct ENet validation = DONE**（判定依据是真多进程 E2E，不是 `startswith("OK")`：success 20/20、wrong ticket 5/5、wrong protocol 5/5，逐条校验 Guest 走的是 `LobbyManager.join_invite()` 生产入口、rendezvous 注册 → 候选交换 → hole punch → Direct ENet → protocol 6 握手 → seat=2 的真实状态轨迹；坏 ticket / 坏协议号必须在 Host 侧被 `check_ticket()` 判死并踢人，且不占正式座位）。
**Phase 10.1 = 桌面端 Solo / LAN / WAN-P2P 最终集成 = DONE**（判定依据是真多进程 E2E：LAN UI、WAN P2P、失败清理三套全绿，且 9.2.2 / 9.2.3 无回归；Solo / 主菜单无网络 peer 由单测覆盖。**Android 与 Skill multiplayer 未开始，归 Phase 10.2**）。
**Phase 10.2.1 = Android 网络接入 + 正式 APK + 真机 LAN 联调 = 部分完成（未 DONE）**：Android `permissions/internet` 已修正且编译后 APK manifest 经 `aapt2` + 新校验器双确认含 `android.permission.INTERNET`；桌面全量回归绿（save / `user://` 沙箱失败已单独归类）。**真机 Android Solo、Android↔Desktop LAN（双向）、LAN discovery 与手动地址均未在真机验证，标记 VERIFICATION PENDING**——模拟器不能替代真机结果，故本阶段**不得标 DONE**。Skill multiplayer / WAN 正式验收 / 重连 / 发布流程不在本阶段。

**Phase 10.2.1 遗留（已审计、待真机或后续子阶段）**：
- Wi-Fi LAN Rooms 自动发现走 UDP **broadcast**（`arena/lan_beacon.gd:129`，255.255.255.255:17778），不是 multicast；Android Wi-Fi 省电态对广播/组播帧有过滤，是否需要在 `export_presets.cfg` 打开 `permissions/change_wifi_multicast_state` 并获取 `MulticastLock`，**必须由真机 discovery 证据决定**，本次按"不推测、不预设"原则保持关闭；手动地址加入不依赖广播，若真机出现"手动能连、自动发现为空"，即为该路径问题。
- `ACCESS_NETWORK_STATE` / `ACCESS_WIFI_STATE`：现有代码（ENet unicast、`PacketPeerUDP`、`IP.get_local_interfaces`）均不需要，保持关闭。
- WAN 公网真实性未验证：邀请只带私网 `lan=` + 17777，`wan_host` 在生产路径恒为空；打洞 socket 是 `bind(0)` 临时端口、与 ENet 监听 17777 **不是同一端口**，`remote_observed`（服务端/STUN 观测）不能假定等于 ENet 端口；`remote_advertised`（对端自报）当前被优先用于 Guest 的 ENet 目标，公网下会打到私网地址；无 UPnP/PMP/Relay/TURN，STUN 未接入 GDScript。现有 `p2p_wan_battle` / `p2p_direct_enet` E2E 全部 127.0.0.1 回环，**不得据此宣称公网验收通过**；Direct ENet 的 NAT 穿透重设计作为后续独立任务。

其它轨道（不写入上述阶段的 DoD）：

| 轨道 | 何时 |
|---|---|
| 主动技能 | 已完成并冻结；网络技能同步留到最终集成 |
| 虚拟摇杆 / 触屏 | 已完成（移动端 Vertical Slice 一并通过） |
| P2P / NAT 穿透（STUN / TURN / UPnP / rendezvous 服务） | Phase 9.2.2 / 9.2.3 |
| 导出 / profiling | 最终集成阶段 |

---

## Definition of Done（总）

Phase 1–6 全部完成时：

- 玩家有本机身份；顶栏 PROFILE 项显示本机 `display_name`（`best` 只在 Home 的 BEST LOOP 格）
- 多人体验以 Lobby 为核心页面，房间不是 IP
- Overlay 不持有 ENet 与座位权威
- 现有 2–5 人 Co-op / Battle、商店、跟班、三图、句读全部仍能打完
- 无账号、无 Autoload、无第二套 multiplayer_peer
- README「怎么运行」改为描述新 IA，并与本文件一致
