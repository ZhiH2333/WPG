# WPG UI Design System

**版本:** 2.0
**状态:** 全游戏唯一视觉来源。画面实现以本文件为准。
**上位:** [`roadmap.md`](../roadmap.md) → [`ui_art_direction.md`](ui_art_direction.md) → **本文件** → [`ui_screen_spec.md`](ui_screen_spec.md)

实现：[`ui/ui_tokens.gd`](../ui/ui_tokens.gd)、[`ui/game_theme.tres`](../ui/game_theme.tres)、[`ui/ui_style.gd`](../ui/ui_style.gd)、[`ui/kit/`](../ui/kit/)。

完成标准同时是：视觉统一、可读、可操作、低成本、不破坏现有 Contract。Editorial 不得牺牲可读性。

## 可读性

每一屏必须让玩家在 1 秒内看懂：当前页、当前焦点、当前主动作、当前状态。

禁止：

- Body 使用 Display 字体
- 密文使用过重 Playpen
- 技术信息使用 Display 样式
- 重要信息只靠颜色
- 焦点只靠微弱色差
- 整句正文全大写
- 为了艺术感压缩正文行高
- 为了统一把对比度洗掉

## 字体

| 职责 | 文件 | 用途 |
|---|---|---|
| 品牌 | `ui/fonts/PlaypenSans-Variable.ttf` | Brand、Display、Page Title、Player Name、Major Navigation、Major Action |
| 功能 | `ui/fonts/SourceSans3-Variable.ttf` | Body、Caption、Numeric、Technical、Settings、Dense metadata、Section |
| 缺字 | `ui/fonts/NotoSansSC-Regular.otf` | 仅 CJK fallback。不画拉丁正文 |

禁止系统字体栈（Inter、Segoe、PingFang、微软雅黑）。缺字只落到随包的 Noto Sans SC。交替字形只允许舞台上的 WPG 字标。

| 角色 | 字体 | 字重 | 字号 | 行高 |
|---|---|---|---|---|
| Display | Playpen | 700 | 56 | 64 |
| Page | Playpen | 600 | 32 | 40 |
| Navigation | Playpen | 500 | 18 | 24 |
| Button | Playpen | 600 | 22 | 28 |
| PlayerName | Playpen | 700 | 40 | 48 |
| Section | Source Sans 3 | 600 | 14 | 20 |
| Body | Source Sans 3 | 400 | 18 | 28 |
| Caption | Source Sans 3 | 400 | 15 | 22 |
| Numeric | Source Sans 3 | 500 | 20 | 24 |
| Technical | Source Sans 3 | 400 | 14 | 20 |

舞台上的字用 Paper。纸面上的字用 Ink。Theme variation 带 `Ink` 前缀表示纸面上的同一角色。

## 颜色

层级靠颜色、布局、字重、线和实体 Surface。

禁止叠在一起：Blur、Wash、Vignette、多层 alpha、半透明 Surface。

允许：一层职责明确的遮罩；一层实体 Surface。

| Token | 值 | 职责 |
|---|---|---|
| Background | `#241F1B` | 没有画面时的暖炭底 |
| Surface | `#F0E6D6` | 实体暖纸 |
| Ink | `#2E241C` | 纸面上的字 |
| Paper | `#F0E6D6` | 舞台上的字 |
| Secondary | `#6B5E52` | 纸面上的次级字 |
| MutedPaper | `#C9BBA8` | 舞台上的次级字 |
| Line | `#C9BBA8` | 1px 分隔 |
| Accent | `#B35C38` | 主焦点、唯一主动作，或舞台字标 |
| Success | `#5C6642` | 成功，必须同时有字 |
| Warning | `#A67C32` | 警告，必须同时有字 |
| Error | `#B83D2E` | 错误，必须同时有字 |
| Scrim | `#241F1B` 55% | 唯一遮罩。不与 Wash / Vignette / Blur 共存 |

Hover 不变成 Accent，也不发光。

## 表面

圆角 0。无阴影。无发光描边。

- Page：舞台 + 字 + 留白。`OpenSheet` 没有底板
- Section：小标题 + 1px 线
- Group：一块 `SurfaceGroup`
- Drawer / Modal：一块实体 Surface，可加唯一 Scrim
- Row：线、间距、持久标记

间距只用 4 / 8 / 12 / 16 / 24 / 48。布局走 `UiFit`。禁止 `size * ui_scale`。

## 焦点

键盘、鼠标、手柄同一套。所有状态的 content margin 与 border 宽度相同，避免布局跳动。

- Primary Focus：4px Accent 条 + 字从次级提到主色
- Secondary Focus：1px 下划线或标记
- Selected：Accent 条留下，焦点移走仍然在
- Pressed：不改 layout，不缩放，不 glow
- Disabled：对比明显下降，仍能读出不可用
- Hover：1px Ink 下划线

必须看得见焦点的控件：Slider、CheckBox、LineEdit、Character selector、Record row、Player row、Lobby row、Top navigation。

## 动效

- Page：160ms 交叉淡化，不位移、不缩放
- Drawer：左滑
- Modal：只淡入
- Row / Focus：只移动标记
- Status：换字，不脉冲

## 组件

`ui/kit/` 与 Theme variation 同名：`AppTopBar`、`PageHeader`、`SectionHeader`、`NavItem`、`ActionRow`、`PrimaryAction`、`SecondaryAction`、`TextAction`、`IconAction`、`PlayerIdentity`、`PlayerRow`、`RoomRow`、`RecordRow`、`StatusBadge`、`StatusText`、`ValueRow`、`Divider`、`SurfaceGroup`、`ModalFrame`、`DrawerFrame`、`ToastLine`、`ConfirmDialog`、`OfferRow`、`CharacterChoice`。

画面使用 `theme_type_variation`。`UiStyle.present` 清掉遗留的逐控件字号和字色覆盖。

## 回归面

[`tools/ui_gallery.tscn`](../tools/ui_gallery.tscn) 不进主菜单。18 个画面各有 Idle、Focus、关键状态。视口 1920×1080、1600×900、1280×720。并覆盖空档、长名字、长房间名、没有 LAN 房间、满员、Connecting、Failed、Host closed、Version mismatch、没有最近一局、没有头像。
