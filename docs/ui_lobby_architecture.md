# WPG UI / UX / Lobby Architecture Specification

**版本:** 1.1-ui-lobby-arch
**状态:** Phase 1（UI/UX 统一重构）、Phase 2（PlayerProfile）、Phase 3（Lobby domain 离线 mock）、表中 Phase 4/5（移动端输入抽象 + Vertical Slice）、**Phase 6 Ability Framework（DONE，已冻结，不再扩展）**、Phase 7（`LobbyNet` + Ready 网络同步）、旧编号 Phase 5（Multiplayer UX）、Guest Start 换场修复（Lobby → CombatSandbox）以及**表中 Phase 8（`JoinInvite` + `ConnectionPath` + protocol 6 ticket handshake）**均已落地：§3.1–3.6 的 `PlayerProfile` / `LobbyPlayer` / `Room` 在 `ui/player_profile.gd`、`lobby/` 下实现；§4 的 `LobbyManager` 是唯一状态机与命令入口，`LobbyNet` 独占 ENet 与大厅 `@rpc`，`ui/lan_overlay.gd` 已不再持有 `ENetMultiplayerPeer` / `@rpc`（由 `tools/ci/architecture.py` 守卫）。仍未建立：P2P（STUN / TURN / UPnP / rendezvous / NAT 穿透，= Phase 9）。阶段排期以 `roadmap.md` 的「阶段划分」表为准。
**配套:** 根目录 [`roadmap.md`](../roadmap.md)（阶段 / 硬约束）· [`ui_screen_spec.md`](ui_screen_spec.md)（页面布局 / 动效 / 导航栈）

布局、CTA 层级、wireframe、Back 栈以 `ui_screen_spec.md` 为准。本文件管领域模型、职责、网络与换场。冲突时 `roadmap.md` 最高。

这不是换皮文档。目标是：保留 osu!lazer 的导航效率（顶栏、大面积舞台、Overlay 页面、键鼠手柄），做成 WPG 自己的大厅。主页是 Visual Stage 加 Action Rail，不是一颗巨大 PLAY，也不是把 Profile 放在屏幕中央。现有 ENet / 5 座 / 17777+17778 网络以后自然接入，本阶段网络零改。

---

## 0. 仓库事实（不要凭空设计）

当前真实路径（Day 1–85 已完成，Autoload = 0）：

```text
MainMenu（F5 主场景；无 Autoload）
  +- TopBar: [WPG 图标] HOME / PLAY / MULTIPLAYER / PROFILE / SETTINGS / 时钟
  |           （每项带图标；右端只有时钟；PROFILE 文案 = PlayerProfile.display_name）
  +- Home: Stage(spacer) + Name("Player") + Status("Ready to play")
  |        + Action Rail：CONTINUE / SOLO / MULTIPLAYER + Secondary(BEST LOOP / LAST RUN) + Quit
  +- PlayPage              PLAY 页（三条 Rail + Back）
  +- RecordSelector         RECORDS Page（LIST / EDITOR + 删除确认 Modal）
  +- ProfileOverlay         PROFILE Page（就地改昵称 / 头像 / 常用角色）
  +- RecordLeaderboardOverlay  RANKING Page
  +- SettingsOverlay        抽屉（叠在当前页上）
  +- LanOverlay             MULTIPLAYER Page：HOME（Quick join / Create room / LAN rooms / Join invite / Recent）
  |                          / PICK（借档）/ HOST（建房 + 隐私）/ JOIN（LAN 房间列表）/ INVITE / LOBBY（5 行座位 + Ready）
  +- LobbyManager           Lobby domain 唯一入口（Node，不是 Autoload；命令入口 + Room 状态机）
  +- LobbyNet               ENet 建连 / 关连 / 大厅 RPC / NetState（唯一允许碰 multiplayer 的大厅对象）
  +- CreditsOverlay / RoomNotice（战斗侧 Modal 的菜单内对应物）
  start_lan / selected_record
    -> GameLaunch 静态信封（take 一次）
    -> CombatSandbox
         +- RunSession     本局 XP / gold / outcome
         +- NetSession     战斗网络（20Hz 快照 v3；只服务战斗，不建连）
         +- LanBeacon      17778 房间发现（UDP 探针 / 应答）
         +- Hud / WinnerPage / UpgradeOffer / ShopOffer / PauseOverlay / RoomNotice
```

Lobby domain 对象（`lobby/`，全部 `RefCounted`，不碰 ENet、不碰 SceneTree、不碰 UI）：

```text
LobbyManager（Node，MainMenu 子节点）
  -> Room（room_id / host 身份 / 5 个座位 / arena / net_play / loop_goal / privacy / state / invite / borrowed_record_id）
       -> LobbyPlayer（profile_id / display_name / avatar_id / preferred_character_id / peer_id / seat /
                       selected_character_id / ready / connection_state / is_host / path / rtt_ms）
```

UI 只做两件事：向 `LobbyManager` 发命令、读 `get_snapshot()` 画座位行。Start 由 `LobbyManager.start_match()` 写 `GameLaunch` 信封。

（UI 形态：Page / Modal / Drawer 三选一，Page 不套大面板；顶栏 tab 之间是水平翻页。细节见 `ui_screen_spec.md`。）


关键文件体量：

| 文件 | 行数 | 现在实际职责 |
|---|---|---|
| `ui/lan_overlay.gd` | 1282 | JOIN/PICK/HOST 视图、音效、Fit、ENet `create_server`/`create_client`、peer 信号、`rpc_hello`/`hello_ok`/`guest_character`/`assign_seat`/`roster`/`goal`/`arena`/`play_mode`/`begin`、座位数组（RPC 路由缓存）、角色/地图/模式/loop、借档、LanBeacon、5 行座位墙（读 `LobbyManager` 快照）、把 peer 事件转给 `LobbyManager`、Start 走 `LobbyManager.start_match()` |
| `lobby/lobby_manager.gd` | 424 | Lobby domain 唯一入口（Node，MainMenu 子节点）：create / join / leave、pending peer 占位与确认、ready / character / host、can_start、`get_snapshot()`、`start_match()` 写 `GameLaunch` 信封。**不碰 ENet** |
| `lobby/room.gd` | 330 | 房间身份与 5 个座位：seat 分配 / 释放（号不前挪）、pending reservation、上限 5、重复 profile_id / peer_id 拒绝、Host 离房即关房、`can_start()` / `start_block_reason()` |
| `lobby/lobby_player.gd` | 116 | 房间内实例：profile_id / display_name / avatar_id / preferred_character_id / peer_id / seat / selected_character_id / ready / connection_state / is_host / path / rtt_ms + `to_dict()` / `from_dict()` / `copy()` |
| `ui/main_menu.gd` | 547 | 叠层互斥路由、模糊/BGM、换场信封触发、顶栏 PROFILE 项 = `display_name`、把 `LobbyManager` 注入 `LanOverlay` |
| `ui/settings_overlay.gd` | 977 | Settings 抽屉（Audio/Display/Controls/Data） |
| `arena/net_session.gd` | 303 | 沙盒内同步。**不建连**。peer 是大厅挂上 SceneTree 后留下来的 |
| `arena/lan_beacon.gd` | 274 | 17778 发现。Overlay 子节点。房间卡标题目前是 IP |
| `ui/game_launch.gd` | 146 | 换场信封 + 网络常量（`NET_PORT=17777`、`NET_DISCOVER_PORT=17778`、`NET_PROTOCOL=6`、`NET_MAX_SEATS=5`） |
| `ui/profile_overlay.gd` | 163 | 只读成绩与档位，没有昵称/头像编辑 |
| `ui/ui_anim.gd` | 95 | `enter_overlay` 淡入+上浮+卡片错峰；`exit_overlay` 整体 fade |
| `ui/ui_fit.gd` | — | 可见区收缩大面板，禁止再乘 `ui_scale` |
| `ui/game_theme.tres` | 689 | FlatBold 令牌：`FloatingPanel` / `OfferButton` / `OfferTitle` / `Pill*` / `font_bar_bold` |
| `ui/game_progress.gd` | — | `user://progress.cfg` 跨局成绩 |
| `ui/game_records.gd` | — | `user://records.json` 最多 12 档 |
| `ui/game_settings.gd` | — | `user://settings.cfg` 音量/显示/键位 |

顶栏 PROFILE 项文案 = `PlayerProfile.display_name`（Phase 2 已落地，`MainMenu.refresh_profile_label()`）。

仓库里**已有** `ui/player_profile.gd` + `user://profile.json`、`lobby/lobby_player.gd` / `lobby/room.gd` / `lobby/lobby_manager.gd`（MainMenu 下 `LobbyManager` 节点）、`lobby/lobby_net.gd`（`LobbyNet`：ENet 与大厅 `@rpc` 的唯一归属）、Ready / connection_state 枚举（Host 恒 `HOST`，Guest 进房默认 NOT READY）。**没有** `JoinInvite` 的完整形态（只有 `LobbyNet.parse_address()`）、`ConnectionPath`、协议 6 的门票握手、邀请 URI / QR 真连接、公网目录。

`NetSession` **不建连**。`LobbyNet.host_listen()` / `client_connect()` 把 `ENetMultiplayerPeer` 挂到 `SceneTree.multiplayer`；进沙盒后大厅对象销毁，peer 还在。这是正确的换场合同，拆大厅时必须保留。

协议现状：`NET_PROTOCOL = 6`（Phase 8 唯一一次 5 → 6 bump），座位 1–5，满 5 才踢，号不前挪。LAN 不写档。Handshake = **Guest → Host** `rpc_hello(protocol=6, token)`，Host 先验协议再验 ticket，通过后回 `rpc_hello_ok` + `rpc_assign_seat`；失败回 `rpc_join_rejected` 并 disconnect。**peer_connected 立刻占 pending 座，但只有 ticket 通过才 confirm 进 `Room.players`**。

---

## 1. 产品信息架构

保留：

- 顶部菜单栏
- 大面积 Visual Stage（氛围与当前状态，不拿文字填满）
- Action Rail（当前最重要的少数操作）
- Overlay / Page 式页面
- 鼠标、键盘、手柄都能操作
- 留白、明确锚点、有限信息、强层级

不要继续机械模仿 osu!lazer 的紫黑渐变、软阴影、发光胶囊，也不要把它的「中央一颗最大按钮」搬过来。

美术方向与字体以 `ui_screen_spec.md` 的 Typography & Art Direction 为准：Editorial / Graphic / Tactile，品牌字是 Playpen Sans。FlatBold 是排版、剪切、少量表面、留白、轻材质和稀缺强调色。禁止把它做成卡片墙，也禁止回到纯黑底加粉紫发光。本阶段不改 `game_theme.tres`。

### 1.1 核心信息流

```text
Player Profile（自己的 Page，不霸占主页）
  → Main Menu（Visual Stage + 轻量身份 + Action Rail）
    → Play 页 / Rail
      → Continue（最近一档，新开一局，不是中途续打）
      → Solo（RecordSelector，已有）
      → Multiplayer
        → Create Room / Join（邀请）/ LAN Beacon 房间
          → Lobby
            → Combat
```

Profile 是身份层，住在顶栏和 Profile 页。Lobby 是房间与玩家集合层。Network 是连接层。Combat Session 是局内层。四层禁止互相吞并。

### 1.2 主菜单层级（改这里，不是再加按钮）

当前问题：中央 Settings / Play / Quit 与顶栏重复，Solo / Multi 又在 ModeChoice 和顶栏各出现一次，页面被按钮填满。

目标：

> 顶栏负责全局导航。舞台负责氛围。Rail 负责当前操作。像素级排版见 `ui_screen_spec.md`。

```text
顶栏
  WPG / HOME / PLAY / MULTIPLAYER / PROFILE / SETTINGS / 时钟
  右端 [avatar] display_name
  不放 Solo

舞台（页面最大的空区）
  背景 / 场景 / 角色 / 氛围
  不堆统计，不堆卡片

玩家状态（一行）
  DISPLAY NAME
  Ready to play

Action Rail（三条同级，没有一颗更大的 PLAY）
  Continue      Solo           Multiplayer
  最近一档       档位            开房 / 加入

次级信息（一行 caption，可省略）
  BEST LOOP …                         LAST RUN …
```

规则：

- PLAY = 主意图，不是最大物体。顶栏 PLAY 打开 Play 页。Home 的 Rail 是快捷，三条同高，禁止再叠一颗中央 PLAY。
- **顶栏不放 Solo。** Solo 只在 Rail 和 Play 页。MULTIPLAYER 是顶栏里的页面入口，不是第二颗中央巨钮。
- 中央等大 Settings / Play / Quit 三 shear **去掉。** Settings 只在 TopBar。Quit 降为 Home 角落 tertiary（`PillRed` 160×44）。
- 没有中途续打。Continue 只在有档时出现，含义是用该档新开一局。无档则该格不占位。
- 不再使用两张大卡的 ModeChoice Modal。Play 是 Page。
- Profile 不做成主页中央大卡。完整身份、成绩、档位只在 Profile 页。

### 1.3 Overlay 层级

| 种类 | 例子 | 动效意图 |
|---|---|---|
| Page | Play、RecordSelector、Profile、Multiplayer 簇、Lobby、Connecting / Failed / Mismatch | `enter_page` / `exit_page`：24px 位移 + 淡入，退出反向 |
| Drawer | Settings | 侧向滑入滑出，打开 **不关闭** 底下 Page |
| Modal | Credits、离开确认、Host closed | `enter_modal`：缩放 0.96→1 + 淡入，**不上浮** |
| Row | Action Rail、Create/Join/LAN 行、座位行、Beacon 房间行 | 短 punch；进出不是整页重放。不是每人一块带边框的卡片 |
| Status | bind failed、copied | 一行状态色 + 文案。Connecting / Failed / Mismatch 用稀疏状态页，不新开 1680 设置面板 |

`exit_overlay()` 今天只整体 fade。Page 退出必须有空间连续性；Modal 只 fade；Drawer 反向滑。禁止所有页面共用一种进场。位移、时长、wireframe 以 `ui_screen_spec.md` 为准。

---

## 2. Design System（在现有令牌上长，不另起炉灶）

已有、必须复用：

- `UiFit`：按 `visible_rect` 收缩，禁止 `size * ui_scale`
- `UiAnim`：Tween 工具，逻辑 open/close 仍瞬时
- `game_theme.tres`：今天仍是旧 FlatBold StyleBox + `font_bar_bold`。目标字体栈和色哲学见 screen spec，实现前不改文件
- Overlay 架构：Dimmer + Center + Panel + 自管 Hover/Click/Back/Error
- `menu_blur.gdshader` / `menu_shear.gdshader`
- 键盘 / 手柄 Focus（Settings 已能重绑；完整手柄后置）

### 2.1 必须补齐的状态表

每个可交互控件（主 CTA、OfferButton、座位行、导航项）都要有：

| 状态 | 表现 |
|---|---|
| Default | Home Rail 是分隔线之间的文字。实心表面只给座位组和 Start。无阴影 |
| Hover | 字色收到骨白。不铺发光底板，时长 0.12s |
| Focus | 骨白下划线或 shear 标记。键鼠手柄同一套。不用强调色，不描粉边 |
| Pressed / Selected | 字重或一条结构线。不是粉胶囊发光 |
| Disabled | 降 alpha + 不可点；满员房间卡点下去走 Error，不连 |
| Warning | 旁白（Controls 已有 IN USE 句式） |
| Error | ErrorSfx + 短闪，不弹 AcceptDialog |
| Success | 短 punch，不放烟花 |

按钮层级：

1. **Primary intent** — 进入可玩上下文（顶栏 PLAY、Home Rail、Host Start）。权重靠位置和对比，不靠把一颗按钮放到最大
2. **Secondary** — Create / Join / Confirm、Rail 上与主意图并列的另外两条
3. **Tertiary** — 顶栏其余项、Back、一行 caption
4. **Destructive** — Quit、长按删档

### 2.2 Motion Design System

把 `UiAnim` 从「一套 enter_overlay」升级成按意图分发。实现可以仍是同一文件的静态函数，但调用点必须选对意图：

| 意图 | 函数（建议名） | 用法 |
|---|---|---|
| Page enter/exit | `enter_page` / `exit_page` | RecordSelector、Lobby |
| Modal enter/exit | `enter_modal` / `exit_modal` | Credits、离开确认、Host closed |
| Drawer enter/exit | 已有 Settings 侧滑，抽成函数 | Settings |
| Card stagger | 现有 `_append_card_entries` | 卡列表 |
| Focus move | 现有 shear hover | 顶栏 / 中央条 |
| Selection punch | 现有 `punch_scale` | 点选角色/模式 |
| Ready change | 座位行短闪/勾 | 不是页面动画 |
| Connection change | 状态 Label 色 + 文案 | connecting / failed / connected |
| Player joined / left | 座位行 insert/remove | 不是整页 stagger 重放 |
| Success / Error | punch + 对应 SFX | 已有四态音效 |

禁止：每做一个新 Overlay 就复制 `enter_overlay(self, dimmer, panel, [back])`。位移、时长、scale 以 `ui_screen_spec.md` §3–4 为准（Page 24px，Modal 不位移）。

---

## 3. 领域模型

全部 `RefCounted` 或极薄 `Object` 静态仓库。禁止 Autoload。禁止把 `GameProgress` / `GameRecords` / `GameSettings` 合并进 Profile。

### 3.1 `PlayerProfile`（本机身份，本机权威）

建议文件：`ui/player_profile.gd`（static，对齐 `GameProgress`）。

```text
user://profile.json
{
  "version": 1,
  "profile_id": "hex from Crypto.generate_random_bytes",
  "display_name": "Player",
  "avatar_id": "boar",
  "preferred_character_id": "boar"
}
```

| 字段 | 规则 |
|---|---|
| `profile_id` | 首次启动生成，之后不变。不是账号，不用于入房认证 |
| `display_name` | 1–16 可见字符，本地可改。顶栏和大厅都用这个 |
| `avatar_id` | 先复用 `boar` / `chicken` 肖像，不新开美术管线 |
| `preferred_character_id` | 进房默认选角 |
| `version` | 文件格式版本，不是网络协议 |

**禁止写入：** best_loop、kills、gold、owned、history、键位、音量。

上网只发 **PublicProfile**：`profile_id, display_name, avatar_id, selected_character_id`。Host 不信任、不转发 Guest 的进度。

首次运行：无文件则生成，`display_name = "Player"`，头像与常用角色 = `boar`。

### 3.2 三份本地数据继续分离

| 仓库 | 文件 | 含义 |
|---|---|---|
| PlayerProfile | `user://profile.json` | 我是谁 |
| GameProgress | `user://progress.cfg` | 我玩到了什么程度 |
| GameRecords | `user://records.json` | 我最近玩过什么 |
| GameSettings | `user://settings.cfg` | 音量 / 显示 / 键位 |

Profile UI 读三份、写 Profile；统计仍只读 Progress；档位仍只读 Records。借档开房：UI 读 `GameRecords`，把角色 / `loop_goal` / `arena_id` **种子写入 Room**；档本身不上网、联机仍不写盘。

### 3.3 `LobbyPlayer`（房间内实例）

```text
profile_id: String
display_name: String
avatar_id: String
peer_id: int              # ENet id；pending 时可能已有，seat 仍为 0
seat: int                 # 0=未入座；1 Host；2..5 Guest
selected_character_id: String
ready: bool
connection_state: enum
is_host: bool
path: int                 # 0 lan_ipv4 / 1 ipv6 / 2 wan_ipv4；认证后才有
rtt_ms: int               # 1.0 可恒 0
```

PlayerProfile 进房时**复制公开字段**成 LobbyPlayer。退房销毁 LobbyPlayer，Profile 仍在盘上。1.0 一机一房，不做同机两个 Profile。

### 3.4 `Room`（房间身份不是 IP）

```text
room_id: String                 # Host 开房时本地随机，UI / 日志 / 邀请展示
host_profile_id: String
host_display_name: String       # 冗余，供「NIGHTFOX'S ROOM」
players: Array[LobbyPlayer]     # 含 Host，按 seat 升序；pending 不进此数组
max_players: int                # = NET_MAX_SEATS = 5
arena_id: String
net_play: GameLaunch.NetPlay
loop_goal: int
privacy: enum { LAN_VISIBLE, INVITE_ONLY }
room_state: enum
invite: JoinInvite              # 可空；不是 Room 主键
borrowed_record_id: String      # 仅 Host 本地；不广播、不写网
```

LAN Beacon 可以带 `room_id` + `host_display_name`，让卡片写名字而不是只写 IP。1.0 第一刀 Beacon 包可先不加名字（协议未 bump 前），UI 先按 Room 快照画；协议 6 再扩发现包。

### 3.5 `JoinInvite`（连接信息）

```text
wpg://join?v=6&t=TOKEN&lan=...&lp=17777&wan=...&wp=49152&ip6=...
可选: &n=NightFox&r=ROOM_ID     # 展示用，认证不用 n/r
```

短码仍只压 `v + wan + wp + t`。Token 是门票，不是 Profile ID。UI 只调用「生成 / 解析」，禁止自己拼 IP/Port/Token。

1.0 第一刀可以只有 `lan` + port；WAN / IPv6 / token 按 Phase 4 接入，**协议只 bump 一次 5→6**。

### 3.6 四个标识（硬规则）

| 标识 | 是什么 | 不是什么 |
|---|---|---|
| `profile_id` | 本机是谁 | 不能当 token、不能当 seat、不能当 peer |
| session token | 这局房间门票 | 不能当显示名 |
| ENet `peer_id` | 这次套接字 | Host 上恒为 1；重连（1.1）会变 |
| `seat` | 本房站位 1..5 | 掉线可空出；号不前挪（沿用 Day 78） |

---

## 4. 运行时职责（不要叫错名字）

用户口中的 NetworkSession，在 GDScript 里 **不要** `class_name NetworkSession`。仓库已有战斗 `NetSession`。两套 Session 同名会把 CombatSandbox 和大厅 RPC 缠死。

命名与分层是硬约束，抄 `roadmap.md` 的 Architecture Rules：

| 对象 | 类型 / 位置 | 职责 | 禁止 |
|---|---|---|---|
| `PlayerProfile` | `ui/player_profile.gd`，static `Object` | 本机身份（`user://profile.json`）；`get_public_profile()` 只发公开四字段 | 不负责 Network；不能当 Autoload；不写 progress / records / settings |
| `LobbyPlayer` | `RefCounted`（大厅域对象） | 房间内实例：`profile_id / display_name / avatar_id / peer_id / seat / selected_character_id / ready / connection_state / is_host / path / rtt_ms` | 不落盘；不持有 ENet 对象 |
| `Room` | `RefCounted`（大厅域对象） | 房间身份与状态：seats 1–5（Host = seat 1）、room lifecycle、模式 / 地图 / `loop_goal` 种子 | Room **不是** IP；不直接处理 socket |
| `LobbyManager` | `Node`，挂在 MainMenu 下 | 大厅唯一状态机 + 唯一命令入口（create / join / leave / ready / start / invite / privacy）；决定状态 | **不是 Autoload**；不碰 ENet API |
| `LobbyNet` | `Node`（已建立，2026-10-02） | 建连 / 关连 / 大厅 RPC：`host_listen` / `client_connect` / `close` / `hello` / `roster` / `ready` / `start` / connection state；`parse_address()` 是 JoinInvite 的第一刀 | 不决定 UI 状态；不承担战斗流量 |
| `JoinInvite` | static（Phase 8 已落地：`lobby/join_invite.gd`） | `create()` / `parse()` 连接信息（LAN IPv4 / IPv6 / WAN IPv4 + token + 可选展示元数据）；UI 只经 `LobbyManager.create_invite()` / `join_invite()` | UI 禁止自己拼 IP / Port / Token / URI |
| `ConnectAttempt` / `ConnectAttemptRunner` | `RefCounted`（`lobby/connect_attempt*.gd`，Phase 8 hardening） | 单次建连尝试的状态与候选回退驱动器：attempt_id 隔离延迟回调、换候选前 close、区分 CONNECT_TIMEOUT / CONNECTION_FAILED / VERSION_MISMATCH / TICKET_REJECTED / CONNECTED | **不持有 ENet peer**；建连只经注入的 transport（归 `LobbyNet`） |
| `P2PConnectionState` | `RefCounted`（`lobby/p2p_connection_state.gd`，Phase 9.1） | P2P 连接状态机（DISCONNECTED → … → CONNECTED / TIMEOUT / TICKET_REJECTED / VERSION_MISMATCH）；纯状态、纯函数转换表，可 headless 单测 | 不做 socket I/O、不持有 peer、不依赖 SceneTree / UI / Combat |
| `RendezvousContract` | `RefCounted`（`lobby/rendezvous_contract.gd`，Phase 9.1） | rendezvous 的**纯数据** contract：会话身份（room_id / ticket / protocol / role / nonce）、候选（transport / path / port / observed endpoint）、会话状态；含版本化二进制编解码 | 只负责**发现与信息交换**；不是 Relay、不承载游戏流量；不碰 ENet |
| `P2PConnection` | `RefCounted`（`lobby/p2p_connection.gd`，Phase 9.1） | P2P 编排：接受 JoinInvite → rendezvous contract → 远端候选 → DIRECT_CONNECTING → 调用注入的 transport（→ `LobbyNet`）→ 等 connected / failed / timeout → HANDSHAKING / CONNECTED | **不创建 ENet peer**、不发 `@rpc`；不做 STUN / TURN / UPnP / 真打洞 |
| `RendezvousClient` | `RefCounted`（`lobby/rendezvous_client.gd`，Phase 9.2.1） | rendezvous 的 **UDP 客户端**：REGISTER / 收 REGISTERED / PEER_READY / CANDIDATES / ERROR / BYE，转成 `RendezvousContract` 并通知 `P2PConnection` | **不创建** `ENetMultiplayerPeer`、**不改** `SceneTree.multiplayer`；不代替 `LobbyNet` / `ConnectionPath`；不碰 Combat |
| rendezvous service | `tools/p2p/rendezvous/`（Python 标准库，Phase 9.2.1） | 公网发现 / 交换：register / match / candidate exchange / **observed endpoint** / session 生命周期 / idle cleanup | **不是 Relay**、不承载游戏流量、不分配 seat、不拥有 `Room.players`、不是最终准入权威；不访问 Combat |
| `NetSession` | `arena/net_session.gd`（已存在） | 战斗内同步（输入 / 快照 v3 / 局内事件）；复用具 SceneTree 上的 peer | **职责不改**：不建连、不管大厅、不做发现、**不接手 rendezvous** |
| `LanBeacon` | `arena/lan_beacon.gd`（已存在） | 同网发现（17778 UDP）；进战斗停信标 | 不扫网段；不做游戏流量 |
| `GameLaunch` | static 信封 | 换场一次性交接（`take` 一次） | 不进 Autoload；不长期持有大厅对象 |

### 4.1 硬规则（每条都有历史教训）

1. UI 不直接操作 ENet：`ENetMultiplayerPeer.new()` 与大厅 `@rpc` 只允许出现在 `LobbyNet`。`ui/lan_overlay.gd` 的越界点已于 2026-10-02 迁走，并由 `tools/ci/architecture.py` 固化守卫（`lan_overlay.gd` 不得出现 `ENetMultiplayerPeer` / `@rpc`；`lobby_manager.gd` 不得出现 `multiplayer.`）。Phase 9.1 追加：P2P 状态对象 / rendezvous contract / `ConnectAttempt` / `P2PConnection` 一律不得出现 ENet 或 `@rpc`，UI 不得直接接触 `RendezvousContract` / `P2PConnectionState` / `P2PConnection`（必须经 `LobbyManager`）。Phase 9.2.1 追加：`rendezvous_client.gd` 不得出现 `ENetMultiplayerPeer` / `@rpc`，且必须用 `PacketPeerUDP`；UI 不得接触 `RendezvousClient` / `PacketPeerUDP` / rendezvous packet format；rendezvous server 不得访问 Combat / Lobby。
2. Feature 阶段不允许两套 `multiplayer_peer` 同时工作；SceneTree 同一时间一个 peer。
3. 协议因门票握手只 bump 一次 5 → 6；不要为显示名 / 房间名单独 bump。**Ready 同步不走协议 bump**：它是独立可靠 RPC（`rpc_ready` / `rpc_apply_ready`），roster 包格式逐字节不变。
4. 席位 1–5 保持，Host = 1，号不前挪，满员才踢。`ready` 是状态语义不是裸 bool：Host 恒显示 `HOST`（不参与 Start 判定），Guest 进房默认 **NOT READY**（握手完成必须自己按 READY）；Guest 改角色、Host 改 Mode/Arena/Goal 都会让旧的 READY 失效退回 WAITING；Starting 期间冻结 Ready / 角色 / 房间规则。
5. LAN 不写档；Host 借档只把种子写进 `Room`，不广播 `records.json`，`progress.cfg` 同理。
6. 战斗掉线沿用现有 `peer_lost`；1.0 不做重连与 Host 迁移。
7. 无 Autoload：`LobbyManager` 是 MainMenu 子节点；大厅对象随主菜单场景销毁，进沙盒后只剩 `GameLaunch` 快照。
8. 每一刀都必须能 F5 进现有 Solo；拆大厅中途若不能开房，这一刀不算完成。

## 5. 换场与连接信息（Phase 3 / 7 / 8 已落地；P2P = Phase 9）

- 离线 mock（Phase 3，已落地）：`LobbyManager` 自己维护 `Room` + 假 `LobbyPlayer` 进出，`Start` 直接写 `GameLaunch`，可不 bind 17777。
- 接网（Phase 7，已落地 2026-10-02）：UI 发命令 → `LobbyManager` → `LobbyNet` 执行 ENet 与大厅 RPC；pending peer 不进 `Room.players`，认证失败 disconnect 且 occupied 不变；Ready / 房间设置 / 座位快照全部走 Host 权威广播，Guest 只读投影。
- JoinInvite / ConnectionPath / protocol 6（Phase 8，已落地）：`JoinInvite.create()` / `parse()` 是 invite 的唯一入口，产出 `wpg://join?v=6&t=TOKEN&lan=…&lp=…[&wan=…&wp=…][&ip6=…][&n=…][&r=…]`；`token` 由 `Crypto` 随机生成（128 bit hex），**不是** profile_id / room_id / seat / peer_id。`ConnectionPath` 只描述候选顺序 `LAN_IPV4 → IPV6 → WAN_IPV4`，**不持有 peer**；回退时先 `close()` 再试下一个，`SceneTree.multiplayer` 始终只有一个 peer。协议 5 → 6 与 ticket 握手同一天落地，本阶段唯一一次 bump。
- 门票握手（Phase 8）：Guest 连上后 `rpc_hello(protocol, token)` → Host 先验协议（不符 → `VERSION_MISMATCH`）再验 ticket（不符 → `peer_rejected` + `rpc_join_rejected` + disconnect）→ 通过才 `accept_hello_ok()` 确认座位。ticket 不过的 peer **不进 `Room.players`、不占正式 seat**，pending 由 `drop_peer` 释放。
- LanBeacon 协议 6：发现包追加 `room_id` / `host_display_name`，LAN Rooms 主标题显示 `NightFox's Room`、地址退居次级；Beacon 仍然**只是 discovery**，不做认证、不承载游戏流量、不做 P2P relay。
- P2P（表中原 Phase 9）：Host / Guest 各自与 rendezvous 交换连接信息后走 Direct UDP，rendezvous 不承担游戏流量；必须定义连接超时、打洞超时、直连失败与手动连接文案，且**不承诺**所有 NAT 都能直连。

### 5.1 Phase 8 hardening：异步回退与 ticket lifecycle（已落地）

**异步回退语义（修正前是真实 bug）**：`client_connect()` 返回 `true` 只代表**本地 socket 创建成功**，
ENet 对不可达地址同样返回 `OK`。旧实现据此认为「连接成功」并在第一个候选 `return`，
导致 IPv6 / WAN 回退是死代码。正确语义：

```text
candidate[0] -> 建连 -> 等待真实结果
    connected + handshake 成功 => CONNECTED（DONE）
    connection_failed          => close peer -> candidate[1]
    timeout                    => close peer -> candidate[1]
    VERSION_MISMATCH           => 停止（换 IP 也没用）
    TICKET_REJECTED            => 停止（换 IP 也没用）
```

硬约束：

1. **一次只有一个 active peer**；换 candidate 前必须 `close()` 当前 peer。
2. 每次 attempt 有独立 `attempt_id`；**所有 async callback 必须先核对 attempt_id**，
   旧候选的延迟回调不得修改新候选状态（IPv4 #1 的迟到回调不能覆盖 IPv6 #2）。
3. `connect success` 必须等真实 `connected_to_server` **且**握手通过，不能只看 `create_client()` 返回值。
4. 结果明确区分 `CONNECT_TIMEOUT` / `CONNECTION_FAILED` / `VERSION_MISMATCH` / `TICKET_REJECTED` / `CONNECTED`；
   只有前两类（加 `SOCKET_ERROR`）可换路径重试。
5. 由 `ConnectAttempt` + `ConnectAttemptRunner` 承担，不再把逻辑堆在 `LobbyManager.join_invite()`。

**ticket lifecycle（方案 A = 复用）**：

| 概念 | 归属 | 语义 |
|---|---|---|
| room ticket | Host / 房间 | 建房时生成一次，**属于当前房间**；`create_invite()` 复用，复制第二张 invite 不会让第一张失效 |
| guest ticket | Guest / 单次连接 | Guest 本次连接携带的凭据副本，与 room ticket 是两个独立命名 |
| rotation | Host 显式调用 | **只有** `LobbyManager.rotate_room_ticket()` 会生成新 ticket，旧 invite 从那一刻起失效 |

`create_invite()` 不再换票。ticket 绝不是 profile_id / room_id / seat / peer_id。

**三级超时**（集中定义在 `P2PConnectionState` 与 `ConnectAttemptRunner`，两处必须一致）：

| 常量 | 值 | 含义 |
|---|---|---|
| `RENDEZVOUS_TIMEOUT_SEC` | 5.0 | 与 rendezvous 建立 / 注册的预算 |
| `DIRECT_ATTEMPT_TIMEOUT_SEC` | 4.0 | **单次**直连尝试预算 |
| `OVERALL_JOIN_TIMEOUT_SEC` | 12.0 | 整个 join 流程总预算 |

超时必须进入明确 `TIMEOUT` 状态，且**不留 active peer、不触发旧 attempt callback、不偷偷重试**。

### 5.2 Phase 9.1：P2P 状态机与 rendezvous contract（已落地，不含真打洞）

**P2P 状态机** `P2PConnectionState`（纯状态对象）：

```text
DISCONNECTED -> RENDEZVOUS_CONNECTING -> RENDEZVOUS_REGISTERED
             -> CANDIDATES_RECEIVED -> DIRECT_CONNECTING -> HANDSHAKING -> CONNECTED
终态：CONNECTED / FAILED / TIMEOUT / TICKET_REJECTED / VERSION_MISMATCH
事件：begin_rendezvous / rendezvous_registered / candidates_received /
      begin_direct_attempt / direct_connected / direct_failed /
      handshake_ok / ticket_rejected / version_mismatch / timeout / cancel / reset
```

- 状态转换**确定性**（纯函数转换表，同样 `(state, event)` 永远同样结果）；
- 非法转换返回 `false` **且状态不变**；
- 不依赖 SceneTree、不持有 `MultiplayerPeer`、不依赖 UI / Combat，可 headless 单测；
- `direct_failed` 是自环（允许换下一个候选再试），不直接终结；
- `ticket_rejected` 在**任一进行中的阶段**都合法：ticket 有**两个**校验点 ——
  ① 9.2.1 rendezvous 服务端在 `REGISTER` 时按 session ticket 比对；
  ② Host 在 protocol 6 握手时做最终权威校验。二者都进入 `TICKET_REJECTED` 终态。

**Rendezvous contract** `RendezvousContract`：只定义数据 —— 会话身份（`room_id` / `ticket` /
`protocol` / `role` / `nonce`）、候选（`transport` / `path` / `port` / `address` /
**`observed_address` + `observed_port`**）、会话状态（`rendezvous_id` / 本地与远端 nonce /
本地与远端候选表），外加版本化二进制编解码（magic `WPGR` + version + type）。

- rendezvous **只负责发现 / 交换连接信息**，**不承载游戏流量**，**不是 Relay**；
- `NetSession` **不接手** rendezvous；UI **不接触** packet format（`tools/ci/architecture.py` 已守卫）；
- `observed_*` 只能由 **rendezvous 服务端观测** 或 **STUN** 填入，
  **绝不用本地地址 / invite / 客户端自报值伪造**；
- contract 版本（`RendezvousContract.VERSION`）与游戏协议号（`GameLaunch.NET_PROTOCOL`）**分离**，各自演进。

**P2P 编排器** `P2PConnection`：接受 JoinInvite → 与 contract 对接 → 得到远端候选 →
进入 `DIRECT_CONNECTING` → 经 `bind_transport()` 注入的 transport 调用已有 `LobbyNet`
的单 peer 建连能力 → 等 connected / failed / timeout → `HANDSHAKING` / `CONNECTED`。
它**不创建 ENet、不发 `@rpc`**；职责不再放回 `LanOverlay`。

- 为 null 的 rendezvous 客户端 = 9.1 的**本地装配模式**（注册立即完成）；
- 绑定了 `RendezvousClient` 时走**真实公网注册**，状态由回包驱动，绝不假装已注册；
- `poll_rendezvous(delta)` 由上层每帧驱动轮询与超时。

**本阶段明确不做**：真公网 NAT hole punching、TURN、UPnP、Relay、Host migration、
reconnect、Android P2P、修改 `CombatNetSession`、修改 snapshot v3、修改 Ability Framework、
第二套 `MultiplayerPeer`、为 P2P 重写 `LobbyNet`。

`ConnectionPath` 的候选顺序仍是 `LAN_IPV4 → IPV6 → WAN_IPV4`，
但现在只是为未来 Direct P2P 提供**候选描述**。

### 5.3 Phase 9.2.1：公网 Rendezvous + observed endpoint（已落地，不含真打洞）

**最终目标链路**（本阶段只完成到 CANDIDATES，**不打洞**）：

```text
Host  -> Rendezvous Register -> session / observed endpoint -> 等 Guest
Guest -> Rendezvous Register -> 自己的 observed endpoint
      -> Rendezvous 返回双方 candidate
      -> P2PConnection.apply_remote_candidates()
      -> （9.2.2 才做 UDP hole punching）

状态推进：RENDEZVOUS_CONNECTING -> RENDEZVOUS_REGISTERED -> CANDIDATES_RECEIVED
（**不会**直接假装 CONNECTED）
```

**独立于 Godot 的最小服务** `tools/p2p/rendezvous/`（纯 Python 标准库，无第三方框架）：

| 文件 | 职责 |
|---|---|
| `server.py` | UDP rendezvous：register / match / candidate exchange / observed endpoint / session 生命周期 / idle cleanup |
| `protocol.py` | `lobby/rendezvous_contract.gd` 的**逐字节镜像**；wire 改动必须同时改两处 |
| `stun.py` | 最小 RFC 5389 Binding Request 客户端（只拿 NAT 映射端点） |
| `test_server.py` | 13 组服务端回归 |
| `README.md` | 协议 / 安全边界 / 运行 / 测试说明 |

**协议 v2**（9.2.1 把 contract 从 v1 升到 v2）：

```text
u32 magic | u8 version | u8 type | u32 sid_len | session_id | <payload>
```

- 每条消息都带 **`session_id`**（服务端分配，用于把双方关联到同一会话）；
- 新增 `PEER_READY`（对端已就绪）与 `ERROR`（可诊断错误码）；
- `REGISTERED` / `CANDIDATES` 承载**服务端观测到的** observed endpoint；
- v1 包被明确 `BAD_VERSION` 拒绝（**不做静默兼容**）；
- 截断包必须被识别为 `TRUNCATED`，**不能**因为「读不到就返回空串」而被当合法包接受。

**observed endpoint 的唯一来源**：

```python
observed_address, observed_port = addr[0], addr[1]   # recvfrom 的内核源地址
```

服务器看到什么就记什么。严禁从 invite / 本地地址 / hostname / **客户端自报的 observed 字段**伪造。
客户端即使在自己的 `Candidate.observed_address` 里塞假值，服务端一律无视。

**客户端** `lobby/rendezvous_client.gd`：

- 用 **`PacketPeerUDP`**（与 `LanBeacon` 同源）而**不是 ENet** ——
  rendezvous 只交换信息，不该占用 SceneTree 上唯一那个 peer；
- 职责：连接 server / `REGISTER` / 发 local candidates / 收 `REGISTERED` /
  收 `PEER_READY` / 收 `CANDIDATES` / 转成 `RendezvousContract` / 通知 `P2PConnection`；
- **不能**创建 `ENetMultiplayerPeer`、不能改 `SceneTree.multiplayer`、不能代替
  `LobbyNet` / `ConnectionPath`；
- 串台保护：`session_id` 或 `nonce` 不一致的回包**一律丢弃**。

**分层**（保持）：

```text
LobbyManager -> P2PConnection -> RendezvousClient -> RendezvousContract
P2PConnection -> ConnectionPath -> LobbyNet -> ENet
```

**安全边界**：rendezvous 只做最基础的 protocol / 形状 / ticket / nonce / role / 配对校验，
**不是最终游戏权威**。最终能否进 Lobby 仍由 Host 的 protocol 6 ticket handshake 决定。
rendezvous **不拥有** `Room.players`、**不分配** seat、**不碰** `GameLaunch`。

**日志**：只输出 `session_id` / role / nonce 短摘要（前 8 位）/ observed endpoint /
message type / 错误码；**绝不输出完整 ticket 或完整 nonce**。

**超时与清理**：

| 层 | 常量 | 值 |
|---|---|---|
| 客户端注册 | `RendezvousContract.RENDEZVOUS_TIMEOUT_SEC` | 5.0 |
| 客户端整体 | `RendezvousContract.OVERALL_JOIN_TIMEOUT_SEC` | 12.0 |
| 服务端 session | `SESSION_IDLE_TIMEOUT_SEC` | 30.0 |

超时必须进入明确 `TIMEOUT`，**不留 socket、不留 ENet peer、不触发旧回调、不偷偷重试**；
服务端超时只删除那一个 session，**不影响其它 session**。

**local candidate 收集**：本阶段不扫 LAN、不扫端口、不猜公网 IP、不硬编码公网 IP，
只收集本机可用 IPv4 / IPv6 与已有 `JoinInvite` / `ConnectionPath` 能提供的候选，
包装成 `RendezvousContract.Candidate`。

**STUN（最小 subset）**：只实现 Binding Request 构造、magic cookie 校验、
12 字节 transaction id、`XOR-MAPPED-ADDRESS`（回退 `MAPPED-ADDRESS`）解析。
**不引入** 完整 STUN server / ICE / TURN / WebRTC / 第三方 NAT 库。
无应答返回 `None` —— **绝不伪造**。

**本阶段明确不做**（属 9.2.2 / 9.2.3）：UDP simultaneous open、多端口快速探测、
hole punch retry storm、完整 ICE、TURN、Relay、UPnP、Host migration、reconnect。

[Showing lines 1-300 of 578. Use :301 to continue]