# WPG UI Screen Specification

**版本:** 1.0-ui-screen-spec
**状态:** 最终布局已锁定，尚未按本文件大规模改代码
**上位约束:** [`roadmap.md`](../roadmap.md)（最高）→ [`ui_lobby_architecture.md`](ui_lobby_architecture.md)（领域 / 网络 / 职责）→ **本文件**（页面布局 / 动效 / 令牌 / 导航栈）

本文件回答「每个页面长什么样、焦点怎么走、Back 回哪」。它不改核心架构，也不授权实现者自行发明第三套皮肤或公网房间目录。

实现者（含另一个 AI）应能不看源码、只凭本文件 + 两份上位文档，做出基本一致的布局。

---

## 0. 文档关系与冲突审查

| 文件 | 管什么 | 不管什么 |
|---|---|---|
| `roadmap.md` | 阶段、DoD、硬禁令、实现顺序 | 像素级排版 |
| `docs/ui_lobby_architecture.md` | Profile / Room / LobbyManager / LobbyNet、换场信封、状态机 | 每个按钮放哪 |
| `docs/ui_screen_spec.md`（本文件） | 页面目的、wireframe、CTA 层级、焦点、Back、动效、令牌 | 战斗数值、ENet RPC 表 |

审查时发现的张力，全部按 **roadmap 硬约束** 收口，不另起架构：

| 张力 | 出处 | 裁定 |
|---|---|---|
| 中央 Settings / Play / Quit 三颗等大 shear vs 「唯一主 CTA = PLAY」 | 架构 §1.2「中央 Settings/Quit 可以保留」是许可不是要求；roadmap Phase 1 DoD「一眼看到一颗 PLAY」 | **去掉中央等大三钮。** Settings 只在 TopBar。Quit 降为 Home 右下 tertiary。PLAY 是中央唯一大钮 |
| 顶栏 Solo / Multi 快捷 vs 「不要三套抢注意力」 | 架构 §1.2「若保留则降为 IconBarButton」；roadmap「Solo/Multi 不再与 PLAY 同等大小同时出现在中央和顶栏」 | **TopBar 不再放 Solo / Multi 文案或图标。** 跳过 ModeChoice 的快捷只留 Home 中央 PLAY 下方的 `Solo · Multiplayer` 文字链 |
| CONTINUE 大钮 vs 「每局永远新开，不续打」 | 架构 §1.2 的 Continue；产品合同不中途续打 | **没有 Continue 主 CTA。** Home 只在有档时显示一条 Last activity 文字链，点了进该档 Solo（新开一局） |
| Guest 连上后停在 JOIN 等待文案 vs Lobby 是多人核心页 | 现状 `LanOverlay` JOIN 等待；架构 §8 / roadmap Phase 5 | **Guest 握手成功后进入 Lobby 页。** JOIN 只负责发现 / 粘贴邀请 / 手打 IP |
| Host closed 用大 Overlay vs 优先 Status/Toast/Compact Modal | 架构把 Host closed 列为 Modal；现有 `RoomNotice` | **保持 Compact Modal**（阻断、必须点 OK 回菜单）。不是 FloatingPanel 大页 |
| Phase 1 顶栏仍是 `best %d` vs 「顶栏必须是 display_name」 | roadmap Phase 1 允许占位名；Phase 2 才有 `profile.json` | **最终 UI 顶栏是 display_name。** Phase 1 先把该槽改成占位 `"Player"`，禁止继续写 `best %d`。Phase 2 接磁盘 |

未发现与下列硬约束冲突：无 Autoload、无账号、无公网目录、无 matchmaking、一个 `multiplayer_peer`、最多 5 座、`NetSession` 只做战斗、`LobbyNet` 才是大厅网、CombatSandbox / RunSession / 快照 v3 本阶段零改。

---

## 1. 锁定的信息层级

```text
TopBar     = 全局导航（persistent）
Center     = 主操作
PLAY       = 唯一 Primary CTA
Solo / Multiplayer = PLAY 的玩法分支（Secondary）
Profile    = 玩家身份
Settings   = 全局设置（Drawer，不进导航栈）
```

禁止再出现：

```text
中央 PLAY
+ 中央 SOLO / MULTI 两颗大卡（作为 Home 常驻）
+ 顶栏再标一套 Solo / Multi
```

ModeChoice 仍然存在，但是 **PLAY 打开的 Modal**，不是 Home 的第三套主按钮。

---

## 2. 导航图与返回栈

```text
HOME                         (Main Menu, 基底，不销毁)
 ├── PLAY  ──Modal──► MODE CHOICE
 │                      ├── SOLO ──────► RECORD SELECTOR (Page)
 │                      │                  ├── LIST
 │                      │                  └── EDITOR (New Record)
 │                      │                         Back → LIST
 │                      └── MULTIPLAYER ► MP HOME (Page)
 │                                           ├── CREATE ROOM
 │                                           │     Step 1 → Step 2 → LOBBY
 │                                           ├── JOIN ROOM
 │                                           │     成功 → LOBBY
 │                                           └── AVAILABLE LAN ROOM CARD
 │                                                 未满 → JOIN 流程 → LOBBY
 │                                                 满员 → Error，停在 MP HOME
 ├── PROFILE  (Page)
 │     └── RANKING  (Page)     Back → PROFILE
 └── SETTINGS (Drawer, 叠在当前 Page 上，不 pop)
       └── CREDITS (Modal)     Back → SETTINGS
```

### 2.1 Back 合同（禁止各 Overlay 私自决定）

| 当前 | Esc / Back / 点 Dimmer | 之后焦点 |
|---|---|---|
| HOME | 无（不退出游戏）。Quit 是显式 tertiary | PLAY |
| MODE CHOICE | → HOME | PLAY |
| RECORD SELECTOR LIST | → HOME | PLAY |
| RECORD SELECTOR EDITOR | → LIST | New Record 或第一张档卡 |
| PROFILE | → HOME | PROFILE 顶栏钮 |
| RANKING | → PROFILE | Rank 钮 |
| SETTINGS | → 打开它之前的 Page（Home / Profile / Solo / MP） | 打开 Settings 的那个控件 |
| CREDITS | → SETTINGS | Settings 里 Credits 入口 |
| MP HOME | → HOME | PLAY |
| CREATE STEP 1 | → MP HOME | CREATE ROOM |
| CREATE STEP 2 | → STEP 1 | NEXT |
| JOIN ROOM | → MP HOME | JOIN ROOM |
| LOBBY（本地还没 Start） | → 离开房间确认（Compact Modal）→ MP HOME | CREATE ROOM |
| LOBBY Guest Connecting | Esc = 取消连接 → MP HOME | JOIN ROOM |
| Compact Modal（Host closed / 删档确认） | 先关 Modal，按该 Modal 自己的确认合同 | 见各状态节 |
| 战斗 Pause / Winner | **本文件不管。** 保持 Day 85 | — |

`ui_cancel` 与面板 Back 钮同一条栈。禁止「这个 Overlay close 回 Play，那个 Overlay close 回 Home」。

### 2.2 Settings 与页面

Settings 是 **Drawer**，从 TopBar 任何菜单页都能开。

- 打开 Settings **不关闭** 底下的 Page（Phase 1 起改掉今天「开 Settings 就关 LAN/Profile」的互斥）。
- 关 Settings 仍停在原 Page。
- Lobby 内也可开 Settings；不中断房间。
- 战斗里的暂停 Settings 仍走 PauseOverlay，本文件不改战斗。

### 2.3 互斥规则

同一时间最多：

- 1 个 Page（Solo / Profile / Ranking / MP 簇）
- 1 个 Drawer（Settings）
- 1 个 Modal（ModeChoice / Credits / Compact 确认 / Host closed）

MP 簇（Home / Create1 / Create2 / Join / Lobby）是 **同一个 Page Overlay 的内部视图**，不是五个叠加的 Overlay。内部用本文件的返回栈切视图。

---

## 3. Design Tokens（全页共用，禁止页面私自改数）

全部落在现有 `game_theme.tres` FlatBold 上。禁止新的 osu 紫黑渐变、大面积 soft shadow、发光胶囊、第二套圆角体系。

### 3.1 空间

| 令牌 | 值 | 来源 |
|---|---|---|
| Design canvas | 1920 × 1080 | `UiFit.DESIGN` |
| TopBar 高度 | **60** | `MainMenu.TOP_BAR_HEIGHT` |
| Overlay 顶偏移 | 60（TopBar 始终露出来） | 现有 `offset_top=60` |
| Page 面板首选 | **1680 × 920** | `UiFit.PREFERRED_PANEL` |
| Page 边距 | **48** | `UiFit.PANEL_MARGIN` |
| 内容最大宽度 | 1680；Home 中央列 **720**（与现 Logo 宽对齐） | Logo `720×162` |
| 面板最小 | 640 × 480 | `UiFit` |
| 商店/句读面板 | 不在本文件范围 | 已有 `SHOP_PANEL_MAX` / `OFFER_PANEL_MAX` |

**Spacing scale（只许用这些）：** 4 / 8 / 12 / 16 / 24 / 36 / 48

| 用途 | 值 |
|---|---|
| 控件内边距 | 8 / 12 / 16 |
| 行内分离 | 12 / 16 |
| 区块分离 | 24 / 36 |
| Home 中央列分离 | 36 |
| 卡片网格水平缝 | 16（`CARD_H_SEP`） |

禁止 `size * ui_scale`。收缩一律 `UiFit`。

### 3.2 字体（theme_type_variation，不要每个 Label 手写 size）

| 角色 | Variation | px | 字重 |
|---|---|---|---|
| Home 玩家名 | `MenuTitle` | 48 | bar bold |
| Page 标题 | `FloatingHeader` | 28 | bar bold |
| 区块标题 | `OfferTitle` / `SettingsHeader` | 22 | bar bold |
| 主按钮字 | `MainMenuButton` / `Pill*` | 22 | bar bold |
| Body | `RunSummaryBody` / default | 18 | regular |
| TopBar | `IconBarButton` / `ProfileName` / `ClockLabel` | 18 | bar bold |
| Caption | `OfferDesc` / `RunSummaryHint` | 16 | regular |

颜色：主字 `Color(0.97, 0.94, 0.96)`；caption `Color(0.8, 0.75, 0.81)`；不要新开第三套粉紫字色，除非 Destructive / Success 已有 ClearedTitle 绿、PillRed、ProfileHeader 粉。

### 3.3 控件尺寸

| 控件 | 尺寸 | 样式 |
|---|---|---|
| Primary CTA（PLAY / CREATE ROOM / START） | **320 × 80**，字体 22 | 中央 PLAY 可继续用现有紫 shear 单颗（`fill_color (0.62, 0.3, 0.74)`），大厅内 Primary 用 `PillPink` 实心，圆角 6，无阴影 |
| Secondary（JOIN / NEXT / CONFIRM / CONNECT） | **高度 56**，最小宽 240 | `PillNeutral` 或 `OfferButton` |
| Tertiary（Back、Quit、文字链） | 高度 44；Quit **160 × 44** | Back = `OfferButton`/`PillNeutral`；Quit = `PillRed` |
| TopBar 项 | 高度 60 内垂直居中；图标最大 32 | `IconBarButton` |
| 房间卡 / 座位行 | 高度 **72**，全宽 | `OfferButton` |
| 档位主卡 | `UiFit.card_size`，高钳 96–160 | 已有 RecordCard |
| 头像 | Home **96**；TopBar / 座位行 **40**；Profile 编辑 **96** | 复用 boar/chicken 肖像 |
| LineEdit | 高 44 | 已有 `sb_line_edit` |

圆角：**6** 全站。Focus 描边：现有 2px `Color(1, 0.55, 0.76, 0.8)`。不要发光环。

### 3.4 叠层与运动时长

| 令牌 | 值 |
|---|---|
| Overlay dimmer | `Color(0.03, 0.02, 0.05, 0.55)` 实色；Home 背景另用现有 blur |
| Home 被 Page 压住时 | 现有 `BLUR_MAX 2.6` + `DIM_MAX 0.35`（MainMenu shader） |
| Page enter 位移 | **24px** 上浮（不再用 56px） |
| Modal enter | 无位移，scale **0.96 → 1.0** |
| Drawer | 现有 Settings 侧滑 0.6s，方向不变 |
| Hover | 1.02 scale / 提亮，**0.12s** |
| Punch / Ready | 1.06，**0.12s** |
| Dimmer fade | 0.20s |
| Content fade | 0.25s |
| Page move | 0.32s OutQuint（短于今天 0.45s，避免所有页都像弹抽屉） |
| Page exit | 反向 24px + fade 0.20s InQuint |
| Modal exit | fade 0.15s，可略缩到 0.98 |
| Overlay 整页 fade（旧 `exit_overlay`） | **禁止再当 Page 退场** |

缓动：进 OutQuint / OutBack（卡）；出 InQuint。逻辑 open/close 仍瞬时。

---

## 4. Motion System（按意图，不准一套动画走天下）

`UiAnim` 只许按意图调用。旧 `enter_overlay`（fade + 升 56px + 卡 0.9→1）降为 **deprecated Page 别名**，新调用点必须写新名。

| 意图 | 函数 | 做什么 | 用在 |
|---|---|---|---|
| Page enter | `enter_page(host, dimmer, panel)` | dimmer fade；panel 从 +24y 到位 + fade | RecordSelector、Profile、Ranking、MP 簇 |
| Page exit | `exit_page(host, dimmer, panel)` | panel +24y 下沉 + fade；dimmer fade out | 同上 |
| Modal enter | `enter_modal(host, dimmer, content)` | dimmer fade；content scale 0.96→1 + fade，**不位移** | ModeChoice、Credits、Compact 确认、Host closed |
| Modal exit | `exit_modal(host, dimmer, content)` | fade（可 0.98 scale） | 同上 |
| Drawer enter/exit | `enter_drawer` / `exit_drawer` | 现 Settings 侧滑抽出来 | Settings |
| Card stagger | 现 `_append_card_entries` | 只卡列表，0.06s 错峰，scale 0.9→1 | 档卡、房间卡 |
| Card insert/remove | 短 punch + modulate | 座位进出、新房间卡 | Lobby / Available |
| Focus | 现 shear hover / StyleBox focus | 顶栏与中央 | 全站 |
| Selection | `punch_scale` 1.06 / 0.12s | 角色、模式、地图 | Create / Profile |
| Ready | 座位行 caption 变 READY + 1 帧提亮，不是整页 | Lobby |
| Connection | 状态色 + 文案；Connecting 用 caption 闪（alpha 1.0↔0.55，0.6s 循环），禁止转圈 GIF | Join / Lobby 行 |
| Success | punch + ClickSfx | 复制邀请、改名保存 |
| Error | 短闪 + ErrorSfx，不弹 AcceptDialog | 满员、mismatch、bind failed |

硬禁：新 Overlay 复制 `enter_overlay(self, dimmer, panel, [back])`；Page 用 Modal 缩放；Ready 用 Page 进场；连接失败再开一张大面板。

---

## 5. 交互状态（控件 + 房间）

可交互控件必须能画出：

| 状态 | 表现 | 音效 |
|---|---|---|
| Default | 不透明纯色，圆角 6，无阴影 | — |
| Hover | 提亮 + 可选 1.02，0.12s | HoverSfx，同帧去重 |
| Focus | 2px 粉描边，键鼠手柄同一套 | 进入时 HoverSfx |
| Pressed | 略更亮的 pressed StyleBox | ClickSfx（破坏性走 BackSfx） |
| Selected | 实心选中条 / 加粗，不是发光胶囊 | punch |
| Disabled | alpha 0.45，不可点 | 满员卡点下去仍收 ErrorSfx，不连 |
| Warning | 旁白句，Controls 已有 IN USE 句式 | ErrorSfx |
| Error | 控件或 status 行短闪 | ErrorSfx |
| Success | 短 punch | ClickSfx |

房间 / 玩家状态（主要画在座位行和 Join status，**不是新 Overlay**）：

| 状态 | 画在哪 | 文案（英文，与现 LAN 一致） |
|---|---|---|
| Connecting | Join 主按钮区 **或** 自己的座位行 | `connecting` |
| Authenticating | 座位行 | `connecting`（玩家不看 auth 词） |
| Connected | 座位行 | `connected`（若 Ready 默认 true 则直接 `ready`） |
| Ready | 座位行右侧 | `ready` |
| Error | Join status 行 / Compact Modal | `refused` / `bind failed` / `Version mismatch` |
| Success | 复制邀请后 status 短暂 | `copied` |
| Host Closed | Compact Modal | `Host closed the room. Returning to the menu.`（现句，禁止改） |
| Version Mismatch | Join **inline** | `Version mismatch` |
| Full Room | 房间卡 disabled + 点卡 Error | 不连 |

Connecting / Error / Mismatch **禁止**新开 1680×920 Page。

---

## 6. Persistent chrome：TopBar

所有菜单 Page 打开时 TopBar **仍在、可点**。z_index 100，高 60。

```text
┌──────────────────────────────────────────────────────────────────────┐
│  WPG    HOME    PLAY              [avatar] NAME     SETTINGS   12:48 │
└──────────────────────────────────────────────────────────────────────┘
```

| 项 | 层级 | 行为 |
|---|---|---|
| WPG 字标 | Tertiary / brand | 等于 HOME |
| HOME | Global nav | 关 ModeChoice / Page / Drawer 下的 Credits；回到 Home 中央。若在 Lobby 且已建连：先走离开房间确认 |
| PLAY | Global nav | 等于中央 PLAY：打开 ModeChoice Modal（已在 Solo/MP 内则不再叠一个 ModeChoice，而是保持当前 Page） |
| PROFILE | Global nav | 打开 Profile Page。文案 = `display_name`，左侧 40px 头像。**禁止 `best %d`** |
| SETTINGS | Global nav | 开 Drawer，不关当前 Page |
| CLOCK | 只读 | `HH:MM:SS`，现逻辑 |

**TopBar 不放 Solo / Multi。**

Persistent：TopBar、全屏背景图、BGM、BlurLayer。
Context-specific：中央列、各 Page / Modal / Drawer。

Focus 进 TopBar：从当前 Page 用 `ui_up` 可到 TopBar；TopBar 内左→右 HOME, PLAY, PROFILE, SETTINGS。Clock 不可焦。

---

## 7. Screen 01 — Main Menu (HOME)

**目的：** 告诉玩家「我是谁」并让他按一颗 PLAY。不是功能面板墙。

**层级：** Base scene。不是 Overlay。

**Header / TopBar：** §6。HOME 为当前。

**Primary CTA：** PLAY（320×80 或现 shear 单颗 320×124，紫，居中）

**Secondary：** 文字链 `Solo · Multiplayer`（18px caption，PLAY 下方 16px）。Solo 直达 RecordSelector；Multiplayer 直达 MP HOME。跳过 ModeChoice。

**Tertiary：** 右下 `quit` 160×44 PillRed。Logo 点击 = PLAY。

**内容区（上到下，中央列宽 720，spacing 36）：**

1. Logo 720×162（品牌，不是第三颗 CTA）
2. 头像 96 + `display_name`（MenuTitle 48）。Phase 1 占位 `Player` / boar
3. PLAY
4. `Solo · Multiplayer`
5. Last activity：仅当 `GameRecords` 非空。一行 caption：`last  {record.name}  ·  {arena}  ·  {loop badge}`。整行可点，进该档 Solo。无档则 **整块不占位**

**信息优先级：** 1 身份 → 2 PLAY → 3 玩法分支 → 4 最近活动 → 5 Quit。

**Keyboard / Controller focus：** PLAY → Solo 链 → Multi 链 → Last activity（若有）→ Quit。默认焦 PLAY。`ui_accept` 无 overlay 时 = PLAY（打开 ModeChoice）。`ui_cancel` 无操作。

**Enter / Confirm：** 焦 PLAY 或无焦时打开 ModeChoice。

**Back：** 无。

**动画：** 现有进场：TopBar 落下、Logo pop、**只 PLAY** 错峰。不要再给 Settings/Quit 做大卡错峰。退场：换场仍 0.45s BGM 淡 + Loading。

**Persistent：** 背景、TopBar、BGM。
**Context：** 身份块、PLAY、Last activity。

### Wireframe

```text
┌──────────────────────────────────────────────────────────────────────┐
│ WPG     HOME     PLAY              [◆] Player     SETTINGS    12:48 │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│                         [  WPG LOGO  ]                               │
│                                                                      │
│                            [◆ 96]                                    │
│                            Player                                    │
│                                                                      │
│                         ┌──────────┐                                 │
│                         │   PLAY   │                                 │
│                         └──────────┘                                 │
│                                                                      │
│                         Solo · Multiplayer                           │
│                                                                      │
│                    last  NightFox  ·  Yard  ·  20                    │
│                                                                      │
│                                                              [quit]  │
└──────────────────────────────────────────────────────────────────────┘
```

无档时删掉 `last ...` 那一行，Quit 仍在右下。

---

## 8. Screen 02 — Mode Choice (PLAY 分岔)

**目的：** 点 PLAY 之后问一次 Solo 还是 Multi。不记上次选择。

**层级：** Modal。不是大面板 Page。

**TopBar：** 仍在。HOME 关掉本 Modal。

**Primary：** 无单颗。两张卡是并列 Secondary，视觉低于 Home PLAY。

**Tertiary：** Back。

**内容：** 居中两张卡，宽各 360、高 220，间距 36。左 SOLO caption `local records`；右 MULTI caption `lan lobby`。不要第三张 Internet。

**Focus：** Solo → Multi → Back。打开时焦 Solo。

**Back / Dimmer / Esc：** → HOME，焦 PLAY。

**Confirm：** 焦的那张卡。

**动画：** `enter_modal` / `exit_modal`。禁止升 56px。

**Persistent：** TopBar、背景模糊。
**Context：** 两张卡。

```text
┌──────────────────────────────────────────────────────────────────────┐
│ WPG     HOME     PLAY              [◆] Player     SETTINGS    12:48 │
├──────────────────────────────────────────────────────────────────────┤
│                          dim 0.55                                    │
│          ┌────────────┐           ┌────────────┐                     │
│          │    SOLO    │           │    MULTI   │                     │
│          │ local rec. │           │ lan lobby  │                     │
│          └────────────┘           └────────────┘                     │
│                              [ back ]                                │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 9. Screen 03 — Profile

**目的：** 先回答「我是谁」，再展示成绩与档位。不是排行榜首页。

**层级：** Page Overlay。

**TopBar：** PROFILE 为当前。

**Primary：** 无进战斗 CTA。身份保存是就地（改完即时写盘，无大 Save 钮）。

**Secondary：** `RANKING`（现 Rank 钮）打开排行 Page。

**Tertiary：** Back → HOME。

**内容：左右两列，左窄右宽。**

左 IDENTITY（先画）：

- 头像 96，可点循环 `boar` / `chicken`（不新开美术）
- `display_name` LineEdit，1–16 可见字符
- Preferred character：两枚 96 肖像钮，选中实心条，默认与头像可不同（头像是形象，常用角色是进房默认选角）
- caption：`local profile  ·  not an account`

右 STATS + RECORDS（后画）：

- Stats 只读 `GameProgress`：best loop / last loop / last kills / last gold / runs / owned hint
- Records 只读 `GameRecords` 概览行（现 Profile 行）。空则 `NO RECORDS YET`
- 禁止把 best loop 写进左列当名字

**优先级：** 1 名字与头像 → 2 常用角色 → 3 统计 → 4 档位历史。

**Focus：** Name 输入 → 头像 → Boar → Chicken → Ranking → 第一档行 → Back。打开时焦 Name。

**Back：** → HOME。Esc 同。编辑 Name 时 Esc 先失焦，第二次才关 Page。

**动画：** `enter_page` / `exit_page`。

**Persistent：** TopBar。
**Context：** 身份表单、统计、档位列。

Phase 1：左列可先放占位名 + 不可编辑头像，右列保持今天只读。Phase 2 接通写盘。

```text
┌──────────────────────────────────────────────────────────────────────┐
│ WPG     HOME     PLAY              [◆] Player     SETTINGS    12:48 │
├──────────────────────────────────────────────────────────────────────┤
│ ┌ PROFILE ────────────────────────────────────────────── [RANKING]─┐ │
│ │  IDENTITY              │  STATS                                  │ │
│ │  [◆ 96]                │  best loop   4                          │ │
│ │  Name [ Player       ] │  last loop   2                          │ │
│ │  character             │  last kills  31                         │ │
│ │  [boar] [chicken]      │  runs        12                         │ │
│ │  local profile         │  RECORDS                                │ │
│ │                        │  NightFox   Yard  20          1840      │ │
│ │                        │  PitRun     Pit   Inf          900      │ │
│ │                                                [ back ]          │ │
│ └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 10. Screen 04 — Solo / Record Selector

保持现有 LIST / EDITOR 合同（点已有档进沙盒；新建选角色 / 图 / loop；长按删档）。本文件只锁它是 **Page**，动效走 `enter_page`，Back：EDITOR→LIST→HOME。不要在 LIST 上再叠一套 Play CTA。

---

## 11. Screen 05 — Multiplayer Home

**目的：** 开房、加入、看同网房间。玩家看见 **房间**，不是 IP 浏览器。

**层级：** Page。MP 簇的根视图。

**TopBar：** PLAY 可视为当前。HOME 离开簇。

**Primary：** CREATE ROOM（320×80 PillPink）

**Secondary：** JOIN ROOM（高 56 PillNeutral）→ Join 视图

**Tertiary：** Back → HOME

**内容：**

```text
CREATE ROOM     = 本地当 Host，进 Step 1
JOIN ROOM       = 邀请 / URI / 短码 / 手打地址（不是公网列表）
AVAILABLE ROOMS = 仅 LAN Beacon 发现
INTERNET ROOM   = 不存在。无公网目录、无 matchmaking、无云 Lobby
```

上区两个 CTA 横排（左 Primary 右 Secondary），下区 Available Rooms：

- Search LineEdit（现搜索语义：address / 地图 / coop / battle / `3/5`）
- 空：caption `no rooms`；discover bind failed：`discover bind failed`，手打仍走 JOIN ROOM
- 房间卡高 72：
  - 主标题：**host_display_name 的房间**；协议未带名字的过渡期用 `Room` + 短 address caption，**不要把 IP 当主标题永久方案**
  - 次行：`{Arena}  ·  Co-op|Battle  ·  {loop|battle}`
  - 右徽标：`n/5` 字符串，不是货币
  - 满员 disabled，点 ErrorSfx 不连

点未满卡：把地址交给 Join 流程并立即 connecting（可跳过空 Join 表单，等价今天点卡填 IP 再 Connect）。

**优先级：** 1 CREATE → 2 JOIN → 3 房间卡名字与人数 → 4 地图/模式 → 5 IP（caption / 折叠）

**Focus：** CREATE → JOIN → Search → 第一张未满卡 → Back。打开焦 CREATE。

**Back：** → HOME。若 Guest 探针已开，关页时 `LanBeacon.stop()`（现合同）。

**动画：** 进 MP 簇用一次 `enter_page`。簇内切视图：内容 fade 0.15s，不再整页升降。房间卡 stagger 仅首次进入 Home。

**Persistent：** TopBar、面板壳、Back。
**Context：** CTA、搜索、房间卡。

```text
┌──────────────────────────────────────────────────────────────────────┐
│ WPG     HOME     PLAY              [◆] Player     SETTINGS    12:48 │
├──────────────────────────────────────────────────────────────────────┤
│ ┌ MULTIPLAYER ──────────────────────────────────────────── [ back ]─┐ │
│ │                                                                    │ │
│ │   ┌─────────────────┐     ┌─────────────────┐                     │ │
│ │   │  CREATE ROOM    │     │   JOIN ROOM     │                     │ │
│ │   └─────────────────┘     └─────────────────┘                     │ │
│ │                                                                    │ │
│ │   AVAILABLE ROOMS                              [ search        ]  │ │
│ │   ┌────────────────────────────────────────────────────────────┐  │ │
│ │   │ NightFox's Room          Yard · Co-op · 20           2/5   │  │ │
│ │   │ 192.168.1.20                                               │  │ │
│ │   ├────────────────────────────────────────────────────────────┤  │ │
│ │   │ Pit Fight                Pit · Battle · battle       5/5   │  │ │
│ │   │ full                                                       │  │ │
│ │   └────────────────────────────────────────────────────────────┘  │ │
│ │   no rooms / discover bind failed 时出现一行 caption               │ │
│ └────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

满员卡主标题仍是名字，人数徽标 `5/5`，整卡灰。IP 永远第二行、caption 色。

---

## 12. Screen 06 — Create Room Step 1

**目的：** 先定「我是谁、这局什么玩法」，再谈地图。默认来自 Profile。

**层级：** MP 簇内部视图（仍是同一个 Page Overlay）。

**Primary：** NEXT（高 56，右下）

**Secondary：** 无。

**Tertiary：** Back → MP HOME（若已 bind 17777 的草稿房，Back 拆掉草稿，Beacon 停）

**内容：**

- 标题 `CREATE ROOM`
- 步骤点 `1 Identity    2 Room`，当前 1
- 只读身份条：头像 40 + display_name + caption `from profile`
- Character：Boar / Chicken 两枚，默认 `preferred_character_id`
- Mode：Co-op / Battle 两枚。Battle caption：`no shop · no phrases · pvp`

**Focus：** Boar → Chicken → Co-op → Battle → NEXT → Back。默认焦 NEXT（身份已有默认）。

**Confirm：** NEXT → Step 2。

**动画：** 簇内 fade。选角色 punch。

**Persistent：** 面板壳、步骤点、Back。
**Context：** 角色、模式。

```text
┌──────────────────────────────────────────────────────────────────────┐
│ ┌ CREATE ROOM          1 Identity    2 Room               [ back ]─┐ │
│ │  [◆] Player                                                      │ │
│ │  from profile                                                    │ │
│ │                                                                  │ │
│ │  CHARACTER                                                       │ │
│ │  ┌────────┐  ┌────────┐                                          │ │
│ │  │  BOAR  │  │ CHICKEN│                                          │ │
│ │  └────────┘  └────────┘                                          │ │
│ │                                                                  │ │
│ │  MODE                                                            │ │
│ │  ┌────────┐  ┌────────┐                                          │ │
│ │  │ CO-OP  │  │ BATTLE │                                          │ │
│ │  └────────┘  └────────┘                                          │ │
│ │                                                    [  NEXT  ]    │ │
│ └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 13. Screen 07 — Create Room Step 2

**目的：** 房间设置。写进 Room，不写进 Profile。

**层级：** MP 簇内部视图。

**Primary：** CREATE（高 80 PillPink）→ 真正 `create_room` / bind → LOBBY

**Secondary：** `Seed from record` 打开现有 PICK 列表（借档：锁角色 / loop / 地图，联机仍不写盘）。借档后本页对应控件 disabled + caption `locked to record`。

**Tertiary：** Back → Step 1（不拆房，因房还未 CREATE；若已 seed 则清 borrowed id）

**内容：**

- Arena：Yard / Pit / Keep 三枚（已有三图，不要第四）
- Loop 滑杆 0=Inf，默认 20；Battle 时滑杆 disabled，标签 `battle`
- Privacy：`LAN visible` / `Invite only`。LAN visible 才 Beacon。Invite only 仍能手打 IP / 日后 URI
- 人数只读 caption `max 5`

**Focus：** Yard → Pit → Keep → Loop → LAN visible → Invite only → Seed → CREATE → Back。默认焦 CREATE。

**Confirm：** CREATE。bind 失败：本页 status 行 `bind failed` + ErrorSfx，停在 Step 2，不要关簇。

**动画：** 簇内 fade。

```text
┌──────────────────────────────────────────────────────────────────────┐
│ ┌ CREATE ROOM          1 Identity    2 Room               [ back ]─┐ │
│ │  ARENA                                                           │ │
│ │  [ Yard ]  [ Pit ]  [ Keep ]                                     │ │
│ │                                                                  │ │
│ │  LOOP                                                            │ │
│ │  0 --------●-------------- 40     20                             │ │
│ │                                                                  │ │
│ │  PRIVACY                                                         │ │
│ │  [ LAN visible ]  [ Invite only ]                                │ │
│ │  max 5                                                           │ │
│ │                                                                  │ │
│ │  [ Seed from record ]                            [  CREATE  ]    │ │
│ └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 14. Screen 08 — Join Room

**目的：** 用邀请或手打地址进房。**不是** 公网浏览器。

**层级：** MP 簇内部视图。

**Primary：** CONNECT（高 56）

**Secondary：** 无。Paste 邀请时 LineEdit 即解析。

**Tertiary：** Back → MP HOME（取消 connecting）

**内容：**

- 标题 `JOIN ROOM`
- 一个 LineEdit，placeholder：`invite / 127.0.0.1`
- 解析成功后只读摘要：`NightFox's Room` / map / mode（没有则省略，不显示 token）
- Character：Boar / Chicken，默认 Profile
- Status 行：空 / `connecting` / `refused` / `Version mismatch`
- caption：`LAN list is on the previous page. There is no internet directory.`

**Connecting：** CONNECT 变 disabled，文案改 `connecting`。不要换页。失败：按钮恢复，status 错误。成功：切 Lobby。

**Focus：** LineEdit → Boar → Chicken → CONNECT → Back。默认焦 LineEdit。

**Back：** 取消 peer / 探针保持 MP HOME 的 Guest 发现。

```text
┌──────────────────────────────────────────────────────────────────────┐
│ ┌ JOIN ROOM                                               [ back ]─┐ │
│ │  [ invite / 127.0.0.1                                      ]     │ │
│ │  NightFox's Room · Yard · Co-op                                  │ │
│ │                                                                  │ │
│ │  CHARACTER                                                       │ │
│ │  [boar] [chicken]                                                │ │
│ │                                                                  │ │
│ │  connecting / refused / Version mismatch                         │ │
│ │                                                  [ CONNECT ]     │ │
│ │  LAN list is on the previous page.                               │ │
│ └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

### Connecting 专用（同一视图，不是新 Overlay）

```text
│  [ invite / 192.168.1.20                                 ]         │
│  connecting                                                        │
│                                                  [ CONNECT ]       │  ← disabled
```

### Connection Failed / Version Mismatch（同一视图）

```text
│  Version mismatch                                                  │  ← Error 色
│                                                  [ CONNECT ]       │  ← 可再点
```

---

## 15. Screen 09 — Lobby

**目的：** 多人体验的核心页。看见 **人、座位、Ready、房间状态**。

**层级：** MP 簇内部视图。进战斗前最后一屏。

**TopBar：** HOME 触发离开房间确认。Settings 可开。PLAY 不另开 ModeChoice。

**Primary：** START（仅 Host，占用 2–5 且无 pending 且 Guest ready 才可点）。Guest 看不到 START。

**Secondary：** READY（切换自己的 ready）。Phase 3 第一刀默认 ready=true，此钮可先隐藏或锁在 ready；Phase 5 再露。

**Tertiary：** Leave / Back → Compact Modal 确认离开 → MP HOME（Host 离开 = 关房，Guest 收到 Host closed）。

**内容优先级（必须按此视觉顺序，上到下或左主右次）：**

1. **Players** 座位 1–5
2. **Room info** 模式 / 地图 / loop
3. **Ready / connection** 画在座位行上
4. **Invite** Copy（QR Phase 5 可同日或次日）
5. **Technical details** 默认折叠：IP / port / protocol。一键展开

座位行高 72，从左到右：

```text
[avatar 40]  DISPLAY_NAME     role     character     state
```

- role：`HOST` / `PLAYER` / 空位 `EMPTY SEAT`
- state：`ready` / `connecting` / 空位无 state
- 空位不可点（1.0 不换座）
- 禁止主行出现 peer id、IP、token、protocol

Host 改地图 / 模式 / loop：Lobby 右栏可编辑（借档则锁）。Guest 只读。

Invite：`Copy invite`。成功 status `copied`。1.0 第一刀可 Copy 本机 IPv4；URI 随 Phase 4/5。QR 不挡 Lobby 验收。

**Focus Host：** Ready（若有）→ START → Copy invite → 地图钮 → Leave。默认焦 START（可点时）否则 Copy。
**Focus Guest：** Ready → Copy → Leave。默认焦 Ready。

**Confirm：** Host 焦 START 且可点 = 开战。不可点时 ErrorSfx，START 保持灰。

**离开确认 Compact Modal：** `Leave this room?`  [Cancel] [Leave]。Host 文案 `Leave and close the room?`

**开战：** `handoff_to_combat` → Loading → Combat。大厅对象销毁。本文件到此结束。

**动画：** 进 Lobby 不整页重放 stagger。座位 insert/remove 短 punch。Ready 行内闪。Connecting 行内闪。

**Persistent：** 面板壳、座位墙骨架 5 行、Back。
**Context：** 人名、状态、地图模式、邀请。

```text
┌──────────────────────────────────────────────────────────────────────┐
│ ┌ NIGHTFOX'S ROOM                                         [ leave ]─┐ │
│ │                                                                    │ │
│ │  PLAYERS                      ROOM                                 │ │
│ │  ┌─────────────────────────┐  Co-op · Yard · 20                    │ │
│ │  │ [◆] NightFox  HOST  boar    ready                               │ │
│ │  │ [◆] Pixel     PLAYER chicken ready                              │ │
│ │  │ [◆] Ash       PLAYER boar    connecting                         │ │
│ │  │     EMPTY SEAT                                                  │ │
│ │  │     EMPTY SEAT                                                  │ │
│ │  └─────────────────────────┘                                       │ │
│ │                           INVITE                                   │ │
│ │                           [ Copy invite ]  copied                  │ │
│ │                           ▸ Connection details                     │ │
│ │                             192.168.1.20:17777 · v5                │ │
│ │                                                                    │ │
│ │                           [ READY ]     [  START  ]                │ │
│ └────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

Connection details 默认收起。展开才见 IP / 端口 / 协议。Token 永不做主标题。

Guest 的 START 位空着，不放灰钮占 Primacy。

---

## 16. Screen 10–12 — 阻断状态（Compact Modal / Toast / Inline）

### 16.1 Compact Modal 壳

尺寸：`UiFit` 720×260 首选，最小 480×180（现 `RoomNotice.MODAL_*`）。动效 `enter_modal`。Dimmer 从 TopBar 下沿开始，TopBar 可点 HOME。

```text
┌──────────────────────────────────────────┐
│  Host closed the room.                   │
│  Returning to the menu.                  │
│                                          │
│                              [  OK  ]    │
└──────────────────────────────────────────┘
```

| 事件 | 形式 | 文案 | 之后 |
|---|---|---|---|
| Host closed（Guest） | Compact Modal | 现 `TEXT_HOST_CLOSED` | OK → HOME |
| Guest left，Host 转单机（战斗） | Toast 2.8s | 现 `TEXT_GUEST_LEFT` | 战斗继续；菜单阶段用不到 |
| Leave room 确认 | Compact Modal | `Leave this room?` | Leave → MP HOME |
| 长按删档 | 现 RecordSelector 确认条 | 不动 | 留在 LIST |
| bind failed | **Inline** 在 Step 2 | `bind failed` | 留在 Step 2 |
| Version mismatch | **Inline** 在 Join | `Version mismatch` | 留在 Join |
| refused / connecting | **Inline** 在 Join | 现词 | 留在 Join |
| Full room | 卡 disabled + ErrorSfx | 无 Modal | 留在 MP HOME |
| copied | Invite 旁 caption 1.2s | `copied` | 留在 Lobby |

**禁止** 为 mismatch / refused / connecting / full 再开 1680 大页。

### 16.2 Host Closed wireframe

见上。焦 OK。Esc = OK。ClickSfx 不走。关闭后清 peer。

### 16.3 战斗内 Host closed

保持 `RoomNotice`，本文件不改 Combat。

---

## 17. Settings 与这些页面

| 从哪开 | 开 Settings 时底下 | 关 Settings |
|---|---|---|
| HOME | Home 中央 | Home |
| PROFILE / SOLO / MP 任意视图 / LOBBY | 该 Page 仍 open | 该 Page |
| MODE CHOICE | 先关 Modal 再开 Drawer（避免双浮层抢焦） | HOME |
| Compact Modal | 不允许同时开 Settings | — |
| 战斗 Pause | 现 Pause 合同 | 不在范围 |

Credits 仍是 Settings 的 Modal 子层。

Settings 本身视觉已是 Day 58 FlatBold 抽屉。本文件不重画 Audio/Display/Controls/Data。动效抽成 `enter_drawer`。

---

## 18. 现有文件 → 新 UI 映射

| 屏幕 | 现在 | 去向 | 动作 |
|---|---|---|---|
| Home 中央三 shear | `main_menu.tscn` Settings/Play/Quit 280×124 | 单颗 PLAY + 身份块 + 文字链 + 右下 Quit | Phase 1 改布局 |
| TopBar Solo/Multi | `SoloButton` / `MultiButton` | **移除** | Phase 1 |
| TopBar Profile 文案 | `"best  %d"` | `display_name`（Phase 1 占位 `Player`） | Phase 1 槽，Phase 2 数据 |
| ModeChoice | `mode_choice_overlay` 现走 `enter_overlay` | 改 `enter_modal`；卡尺寸降到 360×220 | Phase 1 |
| Profile | `profile_overlay` 只读成绩 | 左身份右统计；Phase 2 可写 | Phase 1 壳 / Phase 2 数据 |
| Solo | `record_selector` | 保留；动效改 page | Phase 1 动效 |
| Ranking | `record_leaderboard_overlay` | 保留；Back 仍回 Profile | Phase 1 动效 |
| MP 簇 | `lan_overlay.gd` 1074 行 JOIN/PICK/HOST | 同一场景内部视图：Home/Create1/Create2/Join/Lobby | Phase 3 视图，Phase 4 抽 RPC |
| 房间卡 IP 主标题 | `_make_room_title_label(address)` | 名字主标题，IP caption | Phase 5（协议 6 带名字）；过渡期 `Room` + IP caption |
| 座位权威 / @rpc / ENet | Overlay | `Room` + `LobbyNet` | Phase 4 |
| Beacon | Overlay `_ensure_beacon` | LobbyManager | Phase 4 |
| Settings | `settings_overlay` | 抽 drawer 动效；**不再关闭底下 Page** | Phase 1 路由 |
| Host closed | `room_notice.gd` | 保持 Compact Modal | 不改文案 |
| 换场信封 | `GameLaunch` | 保留；可加公开 Profile 数组 | Phase 4/5 |
| 战斗 | `combat_sandbox` / `run_session` / `net_session` | **零改职责** | 禁 |

不要新建第二套 `main_menu.tscn`。不要 `class_name NetworkSession`。不要 Autoload。

---

## 19. Phase 1 具体实现顺序

遵守 roadmap：网络零改。F5 Solo 与现有 2 人 LAN 行为与 Day 85 无法分辨。

1. **令牌落文档即可，theme 不新开皮肤。** 需要的话只加缺的 `UiAnim` 函数，不改 StyleBox 圆角。
2. **`UiAnim`：** 增加 `enter_page` / `exit_page` / `enter_modal` / `exit_modal` / `enter_drawer` / `exit_drawer`。`enter_overlay` 变成 `enter_page` 的 deprecated 别名（位移改为 24px）。禁止继续对 Modal 升 56px。
3. **ModeChoice** 改走 modal 动效。
4. **MainMenu IA：** 去掉中央 Settings shear 与等大 Quit shear；单颗 PLAY；身份块占位；`Solo · Multiplayer` 文字链；右下 Quit；TopBar 去掉 Solo/Multi；Profile 槽改显示 `Player`。Logo 仍 = PLAY。
5. **Settings 路由：** 打开时不关 Profile / Solo / LAN。Credits 仍挡。
6. **已有 Page**（RecordSelector / Profile / Ranking / LanOverlay）的 open/close 改 `enter_page` / `exit_page`。Lan 内部 JOIN/HOST **本阶段不重排**。
7. **README / 本文件指针：** Phase 1 做完后按日记录；不要提前宣称 Lobby 重做完成。

Phase 1 **不做：** `PlayerProfile` 磁盘（那是 Phase 2）、`LobbyManager`、抽 `@rpc`、Create/Join/Lobby 新布局、UPnP、主动技能、虚拟摇杆、改战斗。

---

## 20. 明确不做

- 账号、后端、公网房间目录、matchmaking、云 Lobby、Internet 房间列表
- Autoload、第二 `multiplayer_peer`、`CombatSession`、`NetworkSession`
- 改 CombatSandbox / RunSession / NetSession 战斗职责、快照 v3、战斗 RPC、枪与移速数字、出生点、physics
- osu 紫黑渐变、soft shadow、发光胶囊、新圆角体系
- 把 Progress / Records 写进 Profile 文件
- 完整手柄重绑、虚拟摇杆
- 为显示名单独 bump 协议（门票握手时一次 5→6）

---

## 21. 验收口径（布局锁）

另一名实现者交付后，应无需对原作者口播就能核对：

- Home 一眼是身份 + 一颗 PLAY；没有三颗等大 shear；顶栏没有 Solo/Multi 文案
- 顶栏名字位不是 `best 0`
- PLAY 开的是 Modal 两张卡，不是大面板
- MULTI 首页是 CREATE / JOIN / AVAILABLE LAN ROOMS，没有 Internet 列表
- Lobby 主列是人名和 Ready，IP 在折叠的 Connection details
- Connecting / mismatch / refused 都在 Join 的 status 行
- Host closed 是 Compact Modal
- 所有新动效能说出是 page / modal / drawer / card / ready / connection 哪一种
- Settings 打开后底下 Page 还在
- Autoload = 0；LAN 仍 17777/17778、5 座、不写档
