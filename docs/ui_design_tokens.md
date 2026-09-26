# WPG Design Tokens

实现在 [`ui/menu_type.gd`](../ui/menu_type.gd)。视觉理由在 [`ui_art_direction.md`](ui_art_direction.md)。线框在 [`ui_screen_spec.md`](ui_screen_spec.md)。

本文件只记录已经写进代码的值。Phase 1B 不改 `game_theme.tres`。主菜单和 Settings 抽屉读这些 token。其余界面仍走旧主题。

## Typography

Playpen Sans，字重一律 800。这是主菜单验收后的决定。层级靠字号。

| 角色 | 字号 | 行高 | 字距 | 大小写 | 用在 |
|---|---|---|---|---|---|
| Display | 40 | 48 | 0 | 原样 | 舞台上的名字 |
| Page | 32 | 48 | 0 | 大写短标题 | Settings 节标题 |
| Navigation | 18 | 24 | +1px | 大写 | 顶栏、设置目录 |
| Section | 14 | 20 | +1px | 大写 | Master、Music、键名 |
| Button | 22 | 28 | 0 | 场景里已是大写 | 操作 |
| Body | 18 | 28 | 0 | 句首大写 | 句子、搜索 |
| Caption | 15 | 22 | 0 | 句首大写 | 说明、版本 |
| Numeric | 20 | 24 | 0 | 不改 | 圈数、人数 |
| Technical | 14 | 20 | 0 | 原样 | 时钟 |

## Color

| Token | 值 | 用在 |
|---|---|---|
| Base | `0.08, 0.06, 0.05` | 抽屉目录底 |
| Surface | `0.14, 0.11, 0.09` | 抽屉正文底。不是页面容器 |
| Ink | `0.96, 0.93, 0.88` | 主要的字、滑杆、当前导航标记 |
| Ink soft | `0.82, 0.76, 0.68` | 未悬停的操作 |
| Muted | `0.72, 0.66, 0.58` | 说明、未选目录 |
| Line | 骨白 0.28 | 分隔 |
| Accent | `0.72, 0.38, 0.24` | 只有键盘焦点的短线，和搜索框焦点边 |
| Error | `0.86, 0.22, 0.2` | 长按删除的填充，不是 Accent |

Hover 用骨白。Focus 用陶土色。Selected 导航用骨白标记。按钮默认没有 Accent。

## Spacing

`4 / 8 / 12 / 16 / 24 / 48`。顶栏高 60。页边 48。内容最宽 1200。节距 24。行距 12。按钮高 44。

## Surface

页面本身没有 Surface。Settings 正文区有一块 Surface，因为那是一组长文档，不是整页卡片墙。确认删除用一小块错误色填充。技术说明不放进卡片。

## Motion

`UiAnim.enter_page` 位移 24px。`enter_modal` 只缩放，不位移。`enter_drawer` / `exit_drawer` 侧滑。Focus 不缩放。
