# WPG UI / UX / Lobby Architecture Specification

**版本:** 1.0-ui-lobby-arch
**状态:** Phase 1（UI/UX 统一重构）与 Phase 2（PlayerProfile）**已落地**；§3.1 已实现，§4 起（LobbyManager / LobbyNet / JoinInvite / 门票握手 / P2P 预留）为 Phase 3 与 Phase 7–9 的目标，代码尚未建立。阶段排期以 `roadmap.md` 的「阶段划分」表为准。
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
  +- LanOverlay             MULTIPLAYER Page：PICK / HOST / JOIN
  +- CreditsOverlay / RoomNotice（战斗侧 Modal 的菜单内对应物）
  start_lan / selected_record
    -> GameLaunch 静态信封（take 一次）
    -> CombatSandbox
         +- RunSession     本局 XP / gold / outcome
         +- NetSession     战斗网络（20Hz 快照 v3；只服务战斗，不建连）
         +- LanBeacon      17778 房间发现（UDP 探针 / 应答）
         +- Hud / WinnerPage / UpgradeOffer / ShopOffer / PauseOverlay / RoomNotice
```

（UI 形态：Page / Modal / Drawer 三选一，Page 不套大面板；顶栏 tab 之间是水平翻页。细节见 `ui_screen_spec.md`。）


关键文件体量：

| 文件 | 行数 | 现在实际职责 |
|---|---|---|
| `ui/lan_overlay.gd` | 1074 | JOIN/PICK/HOST 视图、音效、Fit、ENet `create_server`/`create_client`、peer 信号、`rpc_hello`/`hello_ok`/`guest_character`/`assign_seat`/`roster`/`goal`/`arena`/`play_mode`/`begin`、座位数组、角色/地图/模式/loop、借档、LanBeacon、写 `GameLaunch` |
| `ui/main_menu.gd` | 351 | 叠层互斥路由、模糊/BGM、换场信封触发、顶栏 `"best  %d"` |
| `ui/settings_overlay.gd` | 977 | Settings 抽屉（Audio/Display/Controls/Data） |
| `arena/net_session.gd` | 303 | 沙盒内同步。**不建连**。peer 是大厅挂上 SceneTree 后留下来的 |
| `arena/lan_beacon.gd` | 274 | 17778 发现。Overlay 子节点。房间卡标题目前是 IP |
| `ui/game_launch.gd` | 143 | 换场信封 + 网络常量（`NET_PORT=17777`、`NET_DISCOVER_PORT=17778`、`NET_PROTOCOL=5`、`NET_MAX_SEATS=5`） |
| `ui/profile_overlay.gd` | 163 | 只读成绩与档位，没有昵称/头像编辑 |
| `ui/ui_anim.gd` | 95 | `enter_overlay` 淡入+上浮+卡片错峰；`exit_overlay` 整体 fade |
| `ui/ui_fit.gd` | — | 可见区收缩大面板，禁止再乘 `ui_scale` |
| `ui/game_theme.tres` | 689 | FlatBold 令牌：`FloatingPanel` / `OfferButton` / `OfferTitle` / `Pill*` / `font_bar_bold` |
| `ui/game_progress.gd` | — | `user://progress.cfg` 跨局成绩 |
| `ui/game_records.gd` | — | `user://records.json` 最多 12 档 |
| `ui/game_settings.gd` | — | `user://settings.cfg` 音量/显示/键位 |

顶栏 Profile 文案是硬编码：

```text
MainMenu._refresh_profile_name()
  _profile_name.text = "best  %d" % GameProgress.get_best_loop()
```

仓库里**没有** `PlayerProfile`、没有 `user://profile.json`、没有 `LobbyManager`、没有 `LobbyNet`、没有 `Room`、没有 Ready 状态、没有邀请 URI。

`NetSession` **不建连**。`LanOverlay._create_server` / `create_client` 把 `ENetMultiplayerPeer` 挂到 `SceneTree.multiplayer`；进沙盒后 overlay 销毁，peer 还在。这是正确的换场合同，拆大厅时必须保留。

协议现状：`NET_PROTOCOL = 5`，快照 v3，座位 1–5，满 5 才踢，号不前挪。LAN 不写档。Handshake = `rpc_hello(protocol)` 后 `rpc_hello_ok`，**peer_connected 立刻占座**。

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
| `LobbyManager` | `Node`，挂在 MainMenu 下 | 大厅唯一状态机 + 唯一命令入口（create / join / leave / ready / start / invite）；决定状态 | **不是 Autoload**；不碰 ENet API |
| `LobbyNet` | `Node`（Phase 7 建立） | 建连 / 关连 / 大厅 RPC：`host_listen` / `client_connect` / `disconnect` / `hello` / `roster` / `ready` / `start` / `invite` / connection state | 不决定 UI 状态；不承担战斗流量 |
| `JoinInvite` | static（Phase 8 建立） | `create()` / `parse()` 连接信息（LAN IPv4 / IPv6 / WAN IPv4）；UI 只调这两个 | UI 禁止自己拼 IP / Port / Token |
| `NetSession` | `arena/net_session.gd`（已存在） | 战斗内同步（输入 / 快照 v3 / 局内事件）；复用具 SceneTree 上的 peer | **职责不改**：不建连、不管大厅、不做发现 |
| `LanBeacon` | `arena/lan_beacon.gd`（已存在） | 同网发现（17778 UDP）；进战斗停信标 | 不扫网段；不做游戏流量 |
| `GameLaunch` | static 信封 | 换场一次性交接（`take` 一次） | 不进 Autoload；不长期持有大厅对象 |

### 4.1 硬规则（每条都有历史教训）

1. UI 不直接操作 ENet：`ENetMultiplayerPeer.new()` 只允许出现在 `LobbyNet`。当前唯一越界点是 `ui/lan_overlay.gd`（Phase 7 迁走）。
2. Feature 阶段不允许两套 `multiplayer_peer` 同时工作；SceneTree 同一时间一个 peer。
3. 协议因门票握手只 bump 一次 5 → 6；不要为显示名 / 房间名单独 bump。
4. 席位 1–5 保持，Host = 1，号不前挪，满员才踢；`ready` 第一刀默认 `true`。
5. LAN 不写档；Host 借档只把种子写进 `Room`，不广播 `records.json`，`progress.cfg` 同理。
6. 战斗掉线沿用现有 `peer_lost`；1.0 不做重连与 Host 迁移。
7. 无 Autoload：`LobbyManager` 是 MainMenu 子节点；大厅对象随主菜单场景销毁，进沙盒后只剩 `GameLaunch` 快照。
8. 每一刀都必须能 F5 进现有 Solo；拆大厅中途若不能开房，这一刀不算完成。

## 5. 换场与连接信息（Phase 3 / 7 / 8 的目标态）

- 离线 mock（Phase 3）：`LobbyManager` 自己维护 `Room` + 假 `LobbyPlayer` 进出，`Start` 直接写 `GameLaunch`，可不 bind 17777。
- 接网（Phase 7）：`LobbyManager` 发命令 → `LobbyNet` 执行 ENet 与大厅 RPC；pending peer 不进 `Room.players`，认证失败 disconnect 且 occupied 不变。
- WAN / P2P 预留（Phase 8）：`JoinInvite.create()` / `parse()` 是 UI 的唯一入口；`ConnectionPath` 枚举 `LAN_IPV4 / IPV6 / WAN_IPV4`；协议 bump 5 → 6 与门票握手同一天落地。
- P2P（Phase 9）：Host / Guest 各自与 rendezvous 交换连接信息后走 Direct UDP，rendezvous 不承担游戏流量；必须定义连接超时、打洞超时、直连失败与手动连接文案，且**不承诺**所有 NAT 都能直连。

[Showing lines 1-300 of 578. Use :301 to continue]