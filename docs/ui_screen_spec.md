# WPG UI Screen Specification

**版本:** 2.0-ui-screen-spec
**状态:** 线框已锁定。UI 2.0 按本文件画完全部玩家界面。不授权 Phase 4。
**上位约束:** [`roadmap.md`](../roadmap.md)（阶段）→ [`ui_art_direction.md`](ui_art_direction.md)（视觉模型）→ [`ui_design_system.md`](ui_design_system.md)（令牌）→ **本文件**（线框 / 焦点 / Back / 动效）

本文件回答「每一页有哪些事实、焦点怎么走、Back 回哪」。字、色、表面和按钮哲学以 art direction 为准。看见冲突时，不把线框画回中央巨钮或全屏卡片墙。

---

## 0. 冲突审查

审查对象是本轮改完后的三份文档。硬约束以 `roadmap.md` 为准，没有被页面稿改掉。

### 0.1 已改写的旧 UI 锁（上一版方案作废）

上一版把「PLAY = 唯一主 CTA」写成「屏幕中央最大的一颗按钮」。该句同时写在 roadmap Phase 1、架构 §1.2 和本文件旧稿里。产品方向已废弃它。三份文档的 **信息架构段落** 已改成下面这句，避免 Phase 1 按旧稿实现：

```text
PLAY = primary user intent
视觉权重 = 位置 + 对比 + 留白 + 字号 + 动效
视觉权重 ≠ 最大按钮
```

| 旧锁 | 现在 |
|---|---|
| 中央一颗 320×80 PLAY，身份块堆在它上面 | Home = Visual Stage → 一行玩家状态 → Action Rail → 一行次级信息 |
| `Solo · Multiplayer` 文字链挂在 PLAY 下 | Rail 三条同级：Continue / Solo / Multiplayer。没有第四颗更大的 PLAY |
| ModeChoice = 两张大 Modal 卡 | Play 是 Page。两张大卡 Modal 删除 |
| 顶栏不放任何多人入口 | 顶栏有 PLAY 与 MULTIPLAYER，都是导航。Solo 不进顶栏 |
| 没有 Continue | Continue 只在有档时出现，含义是 **用该档新开一局**。仍然没有中途续打 |
| Profile 用 96px 头像占主页中央 | 主页只有名字和一行状态。完整 Profile 在自己的 Page。顶栏右端是头像 + 名字 |
| MP Home 两颗大 CTA + 房间卡墙 | 三条紧凑导航行 + 本地最近房间。LAN 列表只来自 Beacon |
| FlatBold = 每个区块一张圆角卡片，或黑底粉紫发光 | FlatBold = 排版、剪切、少量表面、留白、轻材质、稀缺强调色。品牌字是 Playpen Sans |

### 0.2 仍然有效、页面稿必须服从的硬约束

- 无 Autoload，无账号，无 matchmaking，无公网房间目录
- Internet 加入只有 Invite URI、QR、短码、手打地址
- `AVAILABLE / LAN ROOMS` 只等于 LanBeacon 在 17778 上发现的同网房间
- 一个 `multiplayer_peer`，最多 5 座，座位号不前挪
- `NetSession` 只做战斗。`LobbyNet` 才是大厅网。Phase 1 网络零改
- CombatSandbox / RunSession / 快照 v3 本阶段零改
- 每局新开。Continue 不是读档续打
- Settings 是 Drawer，打开不关闭底下 Page
- 不把 `GameProgress` / `GameRecords` / `GameSettings` 写进 Profile 文件

未发现与上表冲突的页面。若以后的稿子把 LAN 行写成「在线房间」或把 PLAY 再画成中央巨钮，以 roadmap 为准，退回本节。

### 0.3 Phase 3 的测试面不是这些页面

Phase 3 完成的是 `LobbyPlayer`、`Room`、`LobbyManager` 和 `tools/ci/lobby_probe.gd`。玩家菜单里的局域网叠层仍是原来的开房工具。曾经放上去又撤掉的 `Offline`、`no bind`、`Add`、`Remove`、`Seed from record`、五行 `EMPTY SEAT`，不是本文件的线框，禁止再排版或换皮。

第 5–18 节是正式页面。UI 2.0 现在把它们画出来，数据仍走现有 `LanOverlay`、mock 和 `GameLaunch`。QR / Short Code 若需要 `JoinInvite` 或协议变更，只留 shell。Phase 4 才实现 `LobbyNet` 与 protocol 6。

---

## 1. 锁定的信息层级

```text
TopBar              = 全局导航（persistent）
Visual Stage        = 主视觉空间。氛围、场景、当前状态。不拿文字填满
Player Context      = 一行身份。不是 Profile 卡
Action Rail         = 当前最重要的操作
Secondary           = 一行次级事实。没有就整行不出现
```

```text
PLAY = primary user intent
```

Home 上这个意图由 **Action Rail** 承担，不由一颗中央 PLAY 承担。顶栏的 PLAY 是去 Play 页的导航。

禁止：

```text
屏幕中央巨大 PLAY
Avatar + Stats + Play 堆在中心
页面被卡片铺满
顶栏一套 SOLO/MULTI 巨钮，舞台上再一套等大巨钮
把 LAN Beacon 画成公网房间目录
```

### 1.1 视觉密度

每一页必须同时有：

```text
大块留白
一个明确锚点
有限的信息
强层级
```

宁可少显示一行，也不要再叠一块面板。锚点用位置和字重建立。实心色块只给座位组、Host 的 Start、Compact Modal。Rail 是字，不是盒子。视觉模型见 art direction。

---

## 视觉

字级、颜色、表面、按钮和面板以 [`ui_art_direction.md`](ui_art_direction.md) 为准。本文件不另定一套皮肤。下面的线框只用那些角色：Display、Navigation、Section、Button、Body、Caption、Numeric、Technical。

实心表面只给座位组、Host 的 Start、Compact Modal。Home 的 Rail 是两条线之间的文字。空座位不是一张卡。

---

## 2. 导航与返回栈

```text
HOME                              基底场景，不销毁
 ├── PLAY                         Page
 │     ├── CONTINUE → 沙盒（最近一档，新开）
 │     ├── SOLO → RECORD SELECTOR Page
 │     │            LIST ↔ EDITOR
 │     └── MULTIPLAYER → MP HOME
 ├── Rail 与顶栏走同一目的地，不另开 Modal
 ├── MP HOME                      Page（MP 簇的根视图）
 │     ├── CREATE STEP 1 → STEP 2 → LOBBY
 │     ├── JOIN
 │     │     ├── CONNECTING
 │     │     ├── 成功 → LOBBY
 │     │     ├── CONNECTION FAILED
 │     │     └── VERSION MISMATCH
 │     └── LAN ROOMS               簇内视图，只列 Beacon
 │           未满 → 带地址进入 JOIN 的 Connecting
 │           满员 → Error，留在 LAN ROOMS
 ├── PROFILE Page
 │     └── RANKING Page
 └── SETTINGS Drawer               不进返回栈
       └── CREDITS Modal
```

MP 簇（Home / Create 1 / Create 2 / Join / LAN Rooms / Connecting / Failed / Mismatch / Lobby）是 **同一个 Page Overlay 的内部视图**。簇内切换只换内容，不叠第二个 Overlay。

### 2.1 Back

| 当前 | Esc / Back / 点空白 | 之后焦点 |
|---|---|---|
| HOME | 不退出。Quit 是角落 tertiary | Rail 第一格 |
| PLAY | → HOME | 顶栏 PLAY |
| RECORD LIST | → 打开它的地方（HOME Rail 或 PLAY） | Solo |
| RECORD EDITOR | → LIST | New Record 或第一档 |
| PROFILE | → HOME | 顶栏 PROFILE |
| RANKING | → PROFILE | Ranking |
| SETTINGS | → 打开前的 Page | 打开它的控件 |
| CREDITS | → SETTINGS | Credits 入口 |
| MP HOME | → HOME | 顶栏 MULTIPLAYER |
| CREATE 1 | → MP HOME | Create 行 |
| CREATE 2 | → CREATE 1 | Next |
| JOIN | → MP HOME | Join 行 |
| LAN ROOMS | → MP HOME | LAN 行 |
| CONNECTING | 取消连接 → MP HOME | Join 行 |
| CONNECTION FAILED | → MP HOME | Join 行 |
| VERSION MISMATCH | → MP HOME | Join 行 |
| LOBBY，尚未 Start | 离开确认 Modal → MP HOME | Create 行 |
| Host closed Modal | OK → HOME | Rail 第一格 |
| 战斗 Pause / Winner | 本文件不管，保持 Day 85 | — |

`ui_cancel` 与 Back 同一条栈。Lobby 里已建连时，顶栏 HOME 也先走离开确认。

### 2.2 Settings

Drawer。从任何菜单页都能开。打开不关闭底下 Page，关掉仍停在原页。Lobby 里可开，不拆房间。Mode 不再有 Modal，因此不再出现「先关 ModeChoice 再开 Settings」。Compact Modal 打开时不能同时开 Settings。战斗暂停不在本文件范围。

### 2.3 同时存在的层

- 1 个 Page（Play / Solo / Profile / Ranking / MP 簇）
- 1 个 Drawer（Settings）
- 1 个 Modal（Credits / 离开确认 / Host closed）

---

## 3. 令牌

空间和动效落在现有 `game_theme.tres`。字体角色以 art direction 为准。本文件不改 `.tres`。

| 令牌 | 值 |
|---|---|
| 画布 | 1920 × 1080 |
| TopBar | 高 60，z 100，Page 打开时仍在 |
| 页边 | 48 |
| 内容最大宽 | 1200。舞台本身可全宽，字和 Rail 不超过 1200 |
| Spacing | 只许 4 / 8 / 12 / 16 / 24 / 36 / 48 |

字号、字重、字距和大小写见 art direction。这里不另定一套。

| 控件 | 尺寸 | 样式 |
|---|---|---|
| Rail | 三列同排，列间距 48，上下各一条结构线 | 文字，不是三张卡片。禁止 320×80 中央巨钮 |
| 导航行 | 高 **64**，内容宽 | 默认只有字。悬停改为 Ink。右侧一行 caption |
| 座位行 | 高 **72** | Lobby 一组共用一块表面，不是五张卡片 |
| TopBar 头像 | 32 | 右端，名字在头像右侧 |
| Quit | 文字，高 44 | Home 右下。不用发光红胶囊 |
| Back | 高 44 | 文字，不抢锚点 |

Focus 为骨白下划线或 shear 标记。不使用粉色描边。

| 运动 | 值 |
|---|---|
| Page | 位移 24px，进 0.32s OutQuint，出反向 + 0.20s InQuint |
| Modal | 无位移，scale 0.96→1，出 fade 0.15s |
| Drawer | 现有 Settings 侧滑 |
| 簇内换视图 | 内容 fade 0.15s，不再整页升降 |
| Hover | 1.02 / 0.12s，只给 Rail、行、座位 |
| 逻辑 open/close | 瞬时 |

旧 `enter_overlay`（升 56px）不再给新调用点使用。

---

## 4. 动效意图

| 意图 | 函数 | 用在 |
|---|---|---|
| Page | `enter_page` / `exit_page` | Play、Profile、Ranking、RecordSelector、MP 簇进出 |
| Modal | `enter_modal` / `exit_modal` | Credits、离开确认、Host closed |
| Drawer | `enter_drawer` / `exit_drawer` | Settings |
| 簇内 | fade 0.15s | Create、Join、LAN、Connecting、Failed、Mismatch、Lobby |
| 行 | punch 0.12s | 座位进出、Beacon 行增删 |
| Ready / Connecting | 行内字色，不播页面动画 | Lobby、Connecting |

Connecting、失败、版本不符是簇内状态页：留白加一句结论。禁止再套一张 1680×920 设置面板。

---

## 5. Screen — Main Menu

**类型：** 基底场景。不是 Overlay。

**目的：** 这是我的游戏空间。先看见舞台，再看见能做什么。

**信息层级：**

1. Visual Stage（最大面积）
2. 玩家名 + `Ready to play`
3. Action Rail
4. 一行 BEST / LAST
5. 角落 Quit

**主操作：** Rail 第一格。有档时是 Continue；无档时 Solo 成为第一格，Continue 不占位。

**次操作：** Rail 其余格。

**密度：** 舞台区不放卡片、不放统计、不放按钮。名字不是 Profile 卡。Rail 是分隔线之间的三列文字。次级信息只有一行，无数据则整行不出现。

**键盘焦点：** Continue（若有）→ Solo → Multiplayer → BEST/LAST 行（若有，整行一项）→ Quit。默认第一格。`ui_up` 进顶栏，顺序 HOME → PLAY → MULTIPLAYER → PROFILE → SETTINGS。时钟和头像不可焦。

**手柄焦点：** 与键盘同一顺序。十字键左右在 Rail 内移动，上下去顶栏或 Quit。A 确认，B 在 Home 无操作。

**Back：** 无。

**确认：** 激活焦点项。无焦点时确认 = Rail 第一格，不打开旧 ModeChoice。

**进场：** 现有菜单进场只动顶栏和舞台。Rail 三项短错峰。不要再给中间巨钮做 pop。

**退场：** 换场仍是 0.45s 音乐淡出后 Loading。

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ WPG   HOME   PLAY   MULTIPLAYER   PROFILE   SETTINGS      [av] Player  │
│                                                                  12:48  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│                                                                         │
│                         VISUAL STAGE                                    │
│                    背景 / 场景 / 角色 / 氛围                              │
│                                                                         │
│                                                                         │
│   PLAYER                                                                │
│   Ready to play                                                         │
│                                                                         │
│   ───────────────────────────────────────────────────────────────────   │
│                                                                         │
│   CONTINUE                  SOLO                    MULTIPLAYER         │
│   Loop 21                   New run                 Play with friends   │
│                                                                         │
│   ───────────────────────────────────────────────────────────────────   │
│                                                                         │
│   BEST 24                                          LAST RUN  18:42      │
│                                                                         │
│                                                              [ quit ]   │
└─────────────────────────────────────────────────────────────────────────┘
```

Continue：`GameRecords` 最近一档，新开一局，读该档 `arena_id`。Caption 用该档 loop 目标。不是战斗中途恢复。

Solo：Record Selector。Multiplayer：MP Home。

BEST 来自 `GameProgress`。LAST RUN 是最近一档的时间，只读。点 BEST 去 Profile。点 LAST 与 Continue 相同。

Phase 1 名字占位 `Player`，头像用 boar。禁止 `best %d`。

---

## 6. Screen — Play

**类型：** Page。

**目的：** 顶栏 PLAY 的落点。把「怎么玩」说清楚。Home Rail 是它的快捷方式，两条路目的地相同。

**信息层级：** 标题 → 一句说明 → 与 Home 相同的三条 Rail。

**主操作：** Continue（无档则 Solo）。

**次操作：** 另外两条。

**密度：** 没有舞台插画墙，也没有两张大卡。标题之下留白，Rail 靠下中。不重复 BEST 行。

**键盘焦点：** Continue → Solo → Multiplayer → Back。打开时焦第一格。`ui_up` 到顶栏，PLAY 为当前项。

**手柄焦点：** 同键盘。A 确认，B = Back。

**Back：** → HOME。

**确认：** Continue 进沙盒；Solo 进档位；Multiplayer 进 MP Home。

**进场 / 退场：** `enter_page` / `exit_page`。

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ WPG   HOME   PLAY   MULTIPLAYER   PROFILE   SETTINGS      [av] Player  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PLAY                                                                   │
│  Choose a run                                                           │
│                                                                         │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  CONTINUE                  SOLO                    MULTIPLAYER          │
│  Loop 21                   Records                 Rooms                │
│                                                                         │
│  ───────────────────────────────────────────────────────────────────    │
│                                                                         │
│  [ back ]                                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

不记上次选择。不出现 Internet 卡。

---

## 7. Screen — Profile

**类型：** Page。

**目的：** 我是谁，以及只读的成绩和档位。不是主页，也不是排行榜首页。

**信息层级：**

1. 名字（可编辑，Phase 2）
2. 头像与常用角色
3. 只读统计
4. 档位列表
5. Ranking

**主操作：** 无进战斗按钮。改名就地生效，没有大 Save。

**次操作：** Ranking。

**密度：** 一列身份，一列事实。不做三张统计卡。空档一行 `NO RECORDS YET`。

**键盘焦点：** Name → 头像 → Boar → Chicken → Ranking → 第一档 → Back。打开时焦 Name。编辑中 Esc 先结束编辑，再按才关页。

**手柄焦点：** 同键盘。虚拟键盘不在本阶段。A 确认，B = Back（编辑中先结束编辑）。

**Back：** → HOME。

**确认：** 焦点在档位行时无进战斗。档位只展示。开局仍走 Solo。

**进场 / 退场：** `enter_page` / `exit_page`。

Phase 1 左列只显示占位名和不可编辑头像。Phase 2 才写 `profile.json`。

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ WPG   HOME   PLAY   MULTIPLAYER   PROFILE   SETTINGS      [av] Player  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PROFILE                                                    [ RANKING ] │
│                                                                         │
│  [av 96]                                                                │
│  Player                                                                 │
│  local profile                                                          │
│                                                                         │
│  CHARACTER                                                              │
│  Boar     Chicken                                                       │
│                                                                         │
│  BEST LOOP 24     LAST LOOP 18     RUNS 12                              │
│                                                                         │
│  RECORDS                                                                │
│  NightFox        Yard     20                                           │
│  PitRun          Pit      Inf                                          │
│                                                                         │
│  [ back ]                                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

统计只读 `GameProgress`。档位只读 `GameRecords`。禁止把 best loop 当成名字。

---

## 8. Screen — Solo / Record Selector

**类型：** Page。合同保持今天的 LIST / EDITOR：点已有档进沙盒；新建选角色、图、loop；长按删档。

**主操作：** 打开的那一档，或 EDITOR 的确认。

**次操作：** New Record。

**密度：** 保持现有档位列表，不在 LIST 上再叠一套 Play。

**键盘 / 手柄：** 现有档位焦点。B：EDITOR → LIST → 来源页。

**进场 / 退场：** `enter_page` / `exit_page`。删档确认保持现有条，不新开大页。

---

## 9. Screen — Multiplayer Home

**类型：** Page。MP 簇根视图。

**目的：** 选择怎么一起玩。不是房间浏览器，更不是公网目录。

**信息层级：**

1. 标题 `MULTIPLAYER` 与一句 `Play together`
2. 三条导航：Create Room、Join Room、LAN Rooms
3. Recent Rooms（本机最近）

**主操作：** Create Room。

**次操作：** Join Room。LAN Rooms 是同级导航，不是主 CTA。

**密度：** 三条是行，不是三张大卡。行与行之间用一条分隔，不每行套边框。Recent 最多 3 行，没有则整段不出现。

**键盘焦点：** Create → Join → LAN → 第一条 Recent → Back。打开时焦 Create。

**手柄焦点：** 同键盘，上下移动。A 进入该行，B = Back。

**Back：** → HOME。Guest 探针若已开，离开簇时 `LanBeacon.stop()`。

**确认：** 进入对应簇内视图。

**进场：** 进入簇时一次 `enter_page`。

**退场：** 离开簇时 `exit_page`。簇内换页只 fade。

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ WPG   HOME   PLAY   MULTIPLAYER   PROFILE   SETTINGS      [av] Player  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  MULTIPLAYER                                                            │
│  Play together                                                          │
│                                                                         │
│  CREATE ROOM                                          HOST A GAME    →  │
│  ─────────────────────────────────────────────────────────────────────  │
│  JOIN ROOM                                            USE INVITE     →  │
│  ─────────────────────────────────────────────────────────────────────  │
│  LAN ROOMS                                            3 ON THIS LAN  →  │
│                                                                         │
│                                                                         │
│  RECENT                                                                 │
│  NightFox's Room      3/5     Co-op     Yard                         →  │
│  Pixel's Room         2/5     Battle    Pit                          →  │
│                                                                         │
│  [ back ]                                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

语义锁死：

| 行 | 是什么 | 不是什么 |
|---|---|---|
| CREATE ROOM | 本机当 Host | 公开到公网目录 |
| JOIN ROOM | URI / QR / 短码 / 手打地址 | 公网房间列表 |
| LAN ROOMS | Beacon 发现的同网房间 | 互联网目录、matchmaking |
| RECENT | 本机记得的最近房间 | 服务器下发的热门房间 |

Recent 的人数和地图来自上次离开时的本地记录。点它若本地还有邀请或地址，进入 Join 并填好；没有则停在 Join 让玩家粘贴。不向任何目录查询。

LAN 行上的数字只统计当前 Beacon 结果。发现口绑定失败时，该行 caption 改为 `discover bind failed`，Join 仍可用。

---

## 10. Screen — LAN Rooms

**类型：** MP 簇内部视图。不是新的 Overlay。

**目的：** 只显示 LanBeacon 发现的房间。

**信息层级：** 标题 `ON THIS LAN` → caption `Beacon. Not an internet directory.` → 房间行。

**主操作：** 第一间未满的房间。

**次操作：** Back。

**密度：** 行列表。空则一行 `No rooms on this LAN`。无搜索框墙。满员行变灰。

**键盘 / 手柄：** 未满房间从上到下 → Back。满员行可聚焦，确认只播 Error，不连接。A 连接，B → MP Home。

**确认：** 把 Beacon 给出的地址送进 Connecting。不经过空的 Join 表单。

**进场 / 退场：** 簇内 fade。

```text
│  ON THIS LAN                                                            │
│  Beacon. Not an internet directory.                                     │
│                                                                         │
│  NightFox's Room     Yard · Co-op · 20                         2/5   →  │
│  Pit Fight           Pit · Battle                              5/5      │
│                                                                         │
│  [ back ]                                                               │
```

主标题是房主显示名。协议还没带名字时，标题用 `Room`，地址只放 caption。IP 不做永久主标题。

---

## 11. Screen — Create Room Step 1

**类型：** MP 簇内部视图。

**目的：** 我是谁、这局什么模式。默认来自 Profile。

**信息层级：** 步骤 `1 · 2` → 只读身份一行 → Character → Mode。

**主操作：** Next。

**次操作：** 无。

**密度：** 两个选择组，不是设置表单墙。身份只读，不在这里改 Profile。

**键盘焦点：** Boar → Chicken → Co-op → Battle → Next → Back。默认焦 Next。

**手柄焦点：** 左右改组内选项，下到 Next。A = Next，B → MP Home。

**Back：** → MP Home。若已有草稿 bind，拆掉并停 Beacon。

**确认：** Next → Step 2。

**进场 / 退场：** 簇内 fade。选中 punch。

```text
│  CREATE ROOM                         1  IDENTITY          2  ROOM       │
│                                                                         │
│  [av] Player                                                            │
│  from profile                                                           │
│                                                                         │
│  CHARACTER                                                              │
│  Boar          Chicken                                                  │
│                                                                         │
│  MODE                                                                   │
│  Co-op         Battle                                                   │
│  Battle: no shop, no phrases, pvp                                       │
│                                                                         │
│  [ back ]                                              [ NEXT ]         │
```

---

## 12. Screen — Create Room Step 2

**类型：** MP 簇内部视图。

**目的：** 房间规则写进 Room，不写进 Profile。

**信息层级：** Arena → Loop → Privacy → 人数 caption。

**主操作：** Create。成功后进 Lobby。

**次操作：** Seed from record。借档锁角色、loop、地图，联机仍不写盘。锁定后对应控件 disabled，caption `locked to record`。

**密度：** 三组选择加一个滑杆。不拆成多张卡片。

**键盘焦点：** Yard → Pit → Keep → Loop → LAN visible → Invite only → Seed → Create → Back。默认焦 Create。

**手柄焦点：** 左右改 Arena / Privacy，Loop 用左右调步进。A = Create，B → Step 1。

**Back：** → Step 1。房还没 Create，不拆连接。已 seed 则清 borrowed id。

**确认：** Create。`bind failed` 写在本页一行 status，停在 Step 2。

**进场 / 退场：** 簇内 fade。

```text
│  CREATE ROOM                         1  IDENTITY          2  ROOM       │
│                                                                         │
│  ARENA                                                                  │
│  Yard          Pit          Keep                                        │
│                                                                         │
│  LOOP                                                                   │
│  0 ────────●──────────── 40          20                                 │
│                                                                         │
│  PRIVACY                                                                │
│  LAN visible        Invite only                                         │
│  max 5                                                                  │
│                                                                         │
│  [ Seed from record ]                                                   │
│                                                                         │
│  [ back ]                                            [ CREATE ]         │
```

`LAN visible` 才发 Beacon。`Invite only` 不出现在 LAN 列表，仍可用邀请和手打地址。没有「发布到公网」选项。人数只读，上限 5。Battle 时滑杆 disabled，标签 `battle`。地图只有 Yard / Pit / Keep。

---

## 13. Screen — Join Room

**类型：** MP 簇内部视图。

**目的：** 用邀请或地址进房。

**信息层级：** 一个输入 → 解析出的房间名（有才显示）→ 角色 → 连接。

**主操作：** Connect。

**次操作：** 展示 QR（本机去扫对方，或展示自己的码）。QR 是邀请的另一种输入，不打开房间目录。

**密度：** 一个输入框。四种输入说明写在 caption 一行，不做成四张卡。

**键盘焦点：** 输入 → Boar → Chicken → Connect → Back。打开时焦输入。

**手柄焦点：** 同键盘。A = Connect，B → MP Home。

**Back：** → MP Home，取消尚未完成的连接。

**确认：** Connect。解析失败：输入下 caption `could not read invite`，不连。

**进场 / 退场：** 簇内 fade。开始连接后换到 Connecting 视图，不在按钮上原地打转。

允许的输入只有：

```text
Invite URI
QR
Short Code
Manual Address
```

```text
│  JOIN                                                                   │
│  Invite, code, or address                                               │
│                                                                         │
│  [ wpg://join  /  code  /  127.0.0.1                              ]     │
│  NightFox's Room · Yard · Co-op                                         │
│                                                                         │
│  CHARACTER                                                              │
│  Boar          Chicken                                                  │
│                                                                         │
│  URI · QR · short code · address. No public room list.                  │
│                                                                         │
│  [ back ]   [ QR ]                                 [ CONNECT ]          │
```

角色默认 `preferred_character_id`。不显示 token。

---

## 14. Screen — Connecting

**类型：** MP 簇内部状态页。

**目的：** 告诉玩家正在进哪一间，并允许取消。

**信息层级：** `CONNECTING` → 房间名或地址 caption → 路径一句（`Direct` / `LAN`）。

**主操作：** 无。连接成功自动进 Lobby。

**次操作：** Cancel。

**密度：** 三行字。没有日志，没有设置，没有转圈装饰层。

**键盘 / 手柄：** 只有 Cancel。A 或 B 都取消。

**Back：** 取消 peer → MP Home。

**确认：** 不重复发起连接。

**进场 / 退场：** 簇内 fade。标题 alpha 在 1.0 与 0.55 之间循环，0.6s。

```text
│                                                                         │
│                         CONNECTING                                      │
│                         NightFox's Room                                 │
│                         Direct                                          │
│                                                                         │
│                         [ CANCEL ]                                      │
│                                                                         │
```

---

## 15. Screen — Connection Failed

**类型：** MP 簇内部状态页。

**目的：** 没连上。留在菜单里，不进 Lobby。

**信息层级：** `CONNECTION FAILED` → 一句原因 → Retry / Back。

**主操作：** Retry。用刚才的邀请或地址再进 Connecting。

**次操作：** Back。

**密度：** 与 Connecting 同一舞台，只换结论。不展开错误码表。

**键盘焦点：** Retry → Back。打开时焦 Retry。

**手柄焦点：** 左右。A 确认，B = Back。

**Back：** → MP Home。

**确认：** Retry → Connecting。

**进场 / 退场：** 簇内 fade。标题用现有 Error 色，播一次 ErrorSfx。

原因句只用现有词：`refused`、`bind failed`、超时则 `could not reach the room`。不新造对话框。

```text
│                                                                         │
│                         CONNECTION FAILED                               │
│                         Could not reach the room.                       │
│                                                                         │
│                    [ BACK ]          [ RETRY ]                          │
│                                                                         │
```

---

## 16. Screen — Version Mismatch

**类型：** MP 簇内部状态页。

**目的：** 协议不一致。Retry 没有意义。

**信息层级：** `VERSION MISMATCH` → 一句说明 → Back。

**主操作：** Back。

**次操作：** 无。

**密度：** 与失败页同一舞台。不显示双方协议号大表；需要时 caption 一行 `local 5 · room 6`。

**键盘 / 手柄：** 只有 Back。A 或 B 都回 MP Home。

**确认：** Back。

**进场 / 退场：** 簇内 fade。ErrorSfx。

```text
│                                                                         │
│                         VERSION MISMATCH                                │
│                         This room uses a different protocol.            │
│                                                                         │
│                            [ BACK ]                                     │
│                                                                         │
```

文案保持现有 `Version mismatch` 可识别。不升协议，不提供强制加入。

---

## 17. Screen — Lobby

**类型：** MP 簇内部视图。进战斗前的最后一屏。

**目的：** 这间房里有谁。结构化可以比 Home 更强，但仍然不是设置面板。

**信息层级：**

1. 玩家行（1–5）
2. 房间事实：模式、地图、目标
3. 连接一句 + 邀请
4. Ready / Start

**主操作：** Host 的 Start。占用 2–5、无 pending、Guest 都 ready 才可点。Guest 不渲染 Start，不放一颗灰钮占位。

**次操作：** Ready。Phase 3 第一刀默认真，按钮可先锁住。Phase 5 再允许切换。

**密度：** 玩家是一组行，组有一块底。房间事实是一行字，不是三张信息卡。IP、端口、协议默认不出现。

**键盘焦点（Host）：** 自己的 Ready → Start → Copy → QR → Leave。可点时默认焦 Start，否则焦 Copy。

**键盘焦点（Guest）：** Ready → Copy → QR → Leave。默认焦 Ready。

**手柄焦点：** 与键盘相同，左右在底栏，上下不进空座位。A 确认，B 打开离开确认。

**Back：** Compact Modal。Host 文案 `Leave and close the room?`，Guest 文案 `Leave this room?`。Leave → MP Home。Cancel 留在 Lobby。

**确认：** Host 在 Start 上确认 = 开战。不可点时 ErrorSfx，留在 Lobby。

**进场 / 退场：** 簇内 fade。座位插入或离开只 punch 该行。Ready 只改该行的字。

**开战：** `handoff_to_combat` → Loading → Combat。大厅对象销毁。本文件到此结束。

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ WPG              NIGHTFOX'S ROOM                              CO-OP     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PLAYERS                                                                │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │ [av]  NIGHTFOX          HOST         BOAR            READY        │ │
│  │ [av]  PLAYER_02         PLAYER       CHICKEN         READY        │ │
│  │ [av]  PLAYER_03         PLAYER       BOAR            CONNECTING   │ │
│  │       EMPTY SEAT                                                  │ │
│  │       EMPTY SEAT                                                  │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ROOM                                                                   │
│  Co-op          Yard          Goal 20                                   │
│                                                                         │
│  CONNECTION                        INVITE                               │
│  ● Direct                          [ COPY ]    [ QR ]                   │
│                                                                         │
│                              [ READY ]              [ START ]           │
└─────────────────────────────────────────────────────────────────────────┘
```

座位从左到右：头像 40、名字、`HOST` 或 `PLAYER`、角色、状态。空位写 `EMPTY SEAT`，不可点，1.0 不换座。状态只用 `READY` / `CONNECTING`。禁止主行出现 peer id、IP、token、协议。

Host 可在 ROOM 行改地图、模式、目标；借档则锁定。Guest 只读。

Copy 成功，旁边 caption `copied` 1.2s。第一刀可以只复制本机 IPv4。URI 随 Phase 4/5。QR 不挡住 Lobby 验收。

连接句：`Direct` 或 `LAN`。技术细节不占这一屏。

---

## 18. Screen — Host Closed

**类型：** Compact Modal。不是 Page。

**目的：** Guest 必须知道房主关了房，然后回 Home。

**信息层级：** 现有两句 → OK。

**主操作：** OK。

**次操作：** 无。

**密度：** 约 720×260，最小 480×180。不解释网络。

**键盘 / 手柄：** 只有 OK。A、B、Esc 都等于 OK。

**Back：** OK → HOME，清 peer。

**确认：** OK。

**进场 / 退场：** `enter_modal` / `exit_modal`。

文案保持现有 `Host closed the room. Returning to the menu.` 禁止改字。

```text
┌──────────────────────────────────────────┐
│  Host closed the room.                   │
│  Returning to the menu.                  │
│                                          │
│                              [  OK  ]    │
└──────────────────────────────────────────┘
```

战斗内 Host closed 仍走 `RoomNotice`，本文件不改 Combat。

离开房间确认用同一 Modal 壳：`[ Cancel ] [ Leave ]`。Cancel 默认焦点。

---

## 19. 顶栏

所有菜单页打开时顶栏仍在、可点。

| 项 | 行为 |
|---|---|
| WPG | 等于 HOME。Lobby 已建连时先离开确认 |
| HOME | 关掉 Page 与 Credits，回舞台。Lobby 已建连时先离开确认 |
| PLAY | 打开 Play 页。已在 Play、Solo 时保持该页并把 PLAY 标为当前。在 MP 簇或 Lobby 时不另叠一页 |
| MULTIPLAYER | 打开 MP Home。已在簇内则回到簇根视图。Lobby 已建连时先离开确认 |
| PROFILE | 打开 Profile。文案是 `display_name`，不是 `best %d` |
| SETTINGS | 开 Drawer，不关当前 Page |
| 头像 + 名字 | 等于 PROFILE。不可单独聚焦，跟在 PROFILE 项上 |
| 时钟 | 只读 `HH:MM:SS` |

当前项用字重或一条 2px 实心，不用发光胶囊。

---

## 20. 文件映射

UI 2.0 重画 View，不改网络。F5 进 Solo、进现有 LAN，开战与回菜单的交接与现在无法分辨。

| 屏幕 | 现在 | Phase 1 | 以后 |
|---|---|---|---|
| Home 三颗 shear | Settings / Play / Quit | 改成舞台 + 一行状态 + Rail + 角落 Quit | — |
| 顶栏 | 无 Solo/Multi；Profile 是 `best %d` | 加上 MULTIPLAYER 导航；名字槽改 `Player` | Phase 2 接真名 |
| ModeChoice 两张卡 | `mode_choice_overlay` | 退出主路径。顶栏 PLAY 与 Rail 直接去 Play 页 / Solo / MP | — |
| Play 页 | 不存在 | 新 Page，三条 Rail | — |
| Profile | 只读大面板 | 改成疏页壳，数据仍只读 | Phase 2 可写 |
| Solo / Ranking | 已有 | 只改 page 动效 | — |
| MP 簇布局 | `lan_overlay` | UI 2.0 按第 9–17 节重排 View | Phase 4 才抽 RPC |
| Settings | Drawer | 保持不关底下 Page，并改用功能字 | — |
| Pause / Winner / Loading / HUD / Shop / Upgrade / Credits | 旧主题 | UI 2.0 同一套字、色、焦点 | — |
| ENet / RPC | Overlay 持有 | 不碰 | Phase 4 |

UI 2.0 不做：抽 `@rpc`、`JoinInvite` 协议、UPnP、主动技能、虚拟摇杆、改战斗。

---

## 21. 明确不做

- 账号、后端、公网房间目录、matchmaking、云 Lobby
- 把 Beacon 列表或 Recent 做成互联网房间
- Autoload、第二个 `multiplayer_peer`、`CombatSession`、`NetworkSession`
- 改战斗职责、快照 v3、战斗 RPC、枪与移速、出生点、physics
- 中央巨大 PLAY、主页 Profile 大卡、卡片墙、osu 紫黑渐变、soft shadow、发光胶囊、纯黑 HUD、粉紫描边
- 中途续打
- 完整手柄重绑、虚拟摇杆
- 为显示名单独 bump 协议

---

## 22. 验收

- Home 最大的区域是空舞台。其下是一行名字和三条同高 Rail。没有中央巨大 PLAY
- 顶栏是 HOME / PLAY / MULTIPLAYER / PROFILE / SETTINGS，右端是头像和名字。名字不是 `best 0`。没有 Solo 项
- Profile 是独立页。主页没有成绩卡
- Play 是 Page，不是两张大卡 Modal
- MP Home 是三条导航行。LAN Rooms 的标题或 caption 写明 Beacon，且没有公网列表
- Join 界面有 Invite、Paste、Address、QR。QR 与短码在 Phase 4 之前只是 shell，不新写协议
- Lobby 主列是人名和 Ready。IP 不在主列
- Connecting、失败、版本不符是留白状态页。Host closed 仍是 Compact Modal
- Continue 只在有档时出现，并且是新开一局
- Settings 打开后底下的 Page 还在
- Autoload = 0。LAN 仍是 17777 / 17778、5 座、不写档

---

## 23. 战斗与其余画面

这些画面共用 design system，不另起一套黑底发光 HUD。

```text
Pause     紧凑叠层。Continue 是唯一主动作。Retry / Quit 是文字动作
Winner    结果页。标题、分数、历史与 Profile / Records 同一栅格
Loading   实色或一张画面加一层遮罩。字用 Page / Caption
HUD       更密，但用 Numeric / Caption / Ink / Error。无厚描边，无发光板
Shop      一块 SurfaceGroup。每一件是 OfferRow：名称、说明、花费、状态
Upgrade   与 Shop 共用 OfferRow
Credits   Modal。不另选背景和字体
```

状态句用 `StatusText`，同时有字：Connecting、Authenticating、Connected、Ready、Failed、Host Closed、Version Mismatch。

## 24. 布局与状态合同

视口至少 1920×1080、1600×900、1280×720。TopBar 不溢出。标题不撞内容。ActionRow 不被挤成不可读。Settings 可滚动。Lobby 玩家行不溢出。技术文本截断时焦点条仍在。立绘不挡住标题、焦点和主动作。

必须能摆下：空档、长玩家名、长房间名、没有 LAN 房间、满员、Connecting、Failed、Host closed、Version mismatch、没有最近一局、没有头像。
