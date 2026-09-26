# WPG Design Tokens

实现在 [`ui/menu_type.gd`](../ui/menu_type.gd)。视觉方向以这次纠偏为准：印刷、编辑、图形，不用模糊和多层半透明来分层。

## 两种字体

Playpen Sans 是品牌字。Source Sans 3 是功能字。

| 例子 | 角色 | 字体 | 字重 | 字号 | 行高 | 字距 |
|---|---|---|---|---|---|---|
| NIGHTFOX | Display | Playpen Sans | 740 | 40 | 48 | 0 |
| SETTINGS / AUDIO | Page | Playpen Sans | 680 | 32 | 48 | 0 |
| WPG / MULTIPLAYER / PLAY | Navigation | Playpen Sans | 640 | 18 | 24 | +1px |
| CONTINUE | Button | Playpen Sans | 600 | 22 | 28 | 0 |
| MASTER | Section | Source Sans 3 | 600 | 14 | 20 | +1px |
| Change game settings | Body | Source Sans 3 | 460 | 18 | 28 | 0 |
| version 1.0.0 | Caption | Source Sans 3 | 460 | 15 | 22 | 0 |
| 100 | Numeric | Source Sans 3 | 560 | 20 | 24 | 0 |
| 12:04:01 | Technical | Source Sans 3 | 500 | 14 | 20 | 0 |

海报上这些字用 Paper。Settings 纸面上这些字用 Ink。

## 颜色

| Token | 职责 |
|---|---|
| Paper | 暖纸。Settings 整块不透明底板，也是海报上的字色 |
| Ink | 纸面上的深色字、当前目录标记、悬停短线 |
| Muted | 纸面上的说明，以及海报上较轻的说明 |
| Line | 纸面上的分隔 |
| Accent | 陶土色。只用于键盘焦点 |
| Olive | 备用的颜料绿。这一刀不铺开 |
| Error | 长按删除的填充 |

Hover 不变成 Accent。标题不变成 Accent。

## 表面和背景

主菜单是海报加轻度压暗（一张 16% 的色块，没有 shader）。Settings 是不透明纸，旁边的海报保持清晰，不再模糊。

`menu_blur.gdshader` 还在工程里，主菜单不再每帧驱动它。`menu_wash.gdshader` 不再挂到主菜单上。
