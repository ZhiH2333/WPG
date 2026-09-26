# WPG Art Direction

**版本:** 1.0-art-direction
**状态:** 视觉模型已锁定。本文件不授权改主题、不导入字体、不改场景。
**上位:** [`roadmap.md`](../roadmap.md) 管阶段和硬约束。本文件管「看起来为什么是这样」。页面线框、焦点和 Back 栈在 [`ui_screen_spec.md`](ui_screen_spec.md)。领域和网络在 [`ui_lobby_architecture.md`](ui_lobby_architecture.md)。

视觉冲突时以本文件为准。线框冲突时以 screen spec 为准。阶段是否开工以 roadmap 为准。

Phase 3 的领域层已经完成。玩家菜单里曾经出现过的 `Offline` / `no bind` / `Add` / `Remove` / `Seed from record` / 五行 `EMPTY SEAT`，是测试面，不是本文件的例子，也不是以后界面的底稿。禁止把那块局域网面板换色、加圆角、加阴影之后再叫做正式 Lobby。

---

## 0. 为什么现在的视觉模型不能当最终基础

问题不在「还没打磨」。现在的菜单把 **一块深色浮层** 当成页面本身。信息、操作和调试字段都住进同一只盒子。把它画得更整齐，仍然是同一套模型。

### 0.1 Visual hierarchy

层级现在靠盒子的大小和粉紫按钮的面积。最大的物体是面板，其次是按钮，字是面板里的填充。

WPG 需要的层级是：世界画面先被看见，然后是一句身份，然后是少数操作。主操作靠位置、留白和字号，不靠变成屏幕上最大的矩形。中央一颗 PLAY，或一块几乎全屏的 `FloatingPanel`，都会把舞台吃掉。

### 0.2 Surface language

表面语言现在是「凡是一块内容，就先画一只卡片」。Host、Join、座位、空位、地址、测试按钮共用同一只深色板。空座位因此也变成面板里的一行字，而不是留白。

表面应该少，并且有职责：座位组可以有一块共用的面，离开确认可以有一块小面，Host 的 Start 可以有一块实心。页面本身不是表面。字、线、剪切和空白要能单独站立。

### 0.3 Information density

局域网面板把地址、端口、人数、模式、地图、空座位和测试动作叠在同一视区。密度来自「把调试状态显示出来」，不是来自玩家此刻要做的一个决定。

正式页面一次只回答一个问题。主菜单回答「现在去做什么」。大厅回答「这间房里有谁」。地址、协议、`no bind`、peer，不进入主列。

### 0.4 Typography

现在的字是粗无衬线，靠加粗和全大写制造重量。所有标签看起来同一级。Playpen Sans 如果只是把同一批粗字换成手写粗体，页面会变成一张大声说话的海报，仍然没有层级。

字重必须分工。名字和标题可以重。导航、正文、说明、数字、技术行必须轻下来。手写感只提供人味，不负责把每行都写成标题。

### 0.5 Game identity

WPG 是有重量的俯视射击。画面的主体应该是野猪、鸡、场地和光。黑底加粉紫发光是另一类产品：终端、音游皮肤、或调试器。它不描述这支枪、这只动物、这张地图。

角色图和场景要占视觉重量。界面退到导航。没有新画面时，舞台留空，不用卡片假装那里有一幅画。

### 0.6 Player-facing semantics

`Add`、`Remove`、`Seed from record`、`no bind`、`127.0.0.1` 说的是程序在做什么。玩家要看到的是人：谁是房主，谁在准备，哪张图，什么模式。

测试词一旦成为主视觉，界面就在训练玩家把房间理解成一条命令。正式语义是人、座位、房间事实和少数动作。假人进出留在 `LobbyManager` 和 `tools/ci/lobby_probe.gd`。

---

## 1. Design philosophy

```text
成熟游戏的信息架构
+ Playpen Sans 的人味
+ 平面图形
+ 角色与世界
+ 少量材质
+ 大量留白
```

方向词：

```text
Editorial
Graphic
Tactile
Atmospheric
Handcrafted
Restrained Accent
```

Editorial：像一页排好的编辑，而不是一张后台表。标题、事实、动作分行，不挤在一个框里。

Graphic：形状来自剪切、直线和少量实心块。不来自渐变、外发光和圆角卡片墙。

Tactile：有纸和颜料的触感，但控件仍然是清晰的游戏按钮。能被指到，能被聚焦。

Atmospheric：舞台是房间里的空气。UI 不负责把空气填满。

Handcrafted：字形有人手写过的不均匀。产品气质仍然是成人的、克制的。

Restrained Accent：一屏一种强调，而且必须有含义。强调色不是皮肤。

世界大约占七成视觉重量。界面占三成，并且这三成里大部分是字和空白。

明确不是：

```text
儿童读物
手写笔记软件
纯黑 HUD
紫黑渐变音游皮
发光胶囊
每块信息一张卡
```

信息架构仍然向 osu!lazer 借四件事：顶栏、大块视觉空间、短路径、Page / Overlay。不借它的紫、它的软阴影、它的中央巨钮。

---

## 2. Playpen Sans

品牌字和界面字是 TypeTogether 的 **Playpen Sans**。

来源：[TypeTogether/Playpen-Sans](https://github.com/TypeTogether/Playpen-Sans)。许可 OFL 1.1。可变字重 Thin 到 ExtraBold。每个字符有交替字形。官方把它定义为有机、自发、可信的手写感。

它出自拉丁文手写教学，并带一套给儿童的奖励图形。那些图形 **不进入 WPG**。交替字形不用于按钮、导航、座位名和数字，否则焦点下的字会自己换脸。交替只允许出现在不参与操作的品牌瞬间，例如舞台上的字标。

实现时用一份可变字体加 `FontVariation`，放进主题。不要拆成互不相干的八个家族。现有 `font_bar_bold` 是旧槽。新菜单把它收成下面的角色，不保留第二套科技无衬线当品牌字。

本文件不导入字体，不改 `game_theme.tres`。

---

## 3. Typography

八个角色。界面只用四档字重。

| 角色 | 用途 | 字重 | 轴 | 字号 | 行高 | 字距 | 大小写 |
|---|---|---|---|---|---|---|---|
| Display | 舞台上的短标题、品牌瞬间 | Bold | 700 | 56 | 64 | +2% | 原样。不强制大写 |
| Navigation | 顶栏 | Medium | 500 | 18 | 24 | +4% | 大写短标签 |
| Section | 栏目标题，如 PLAYERS、ROOM | SemiBold | 600 | 14 | 20 | +8% | 大写短标签 |
| Button | Rail、主动作、页内动作 | SemiBold | 600 | 22 | 28 | +2% | 大写短标签 |
| Body | 说明句 | Regular | 400 | 18 | 28 | 0 | 句首大写 |
| Caption | 一行状态、次级事实 | Regular | 400 | 15 | 22 | +1% | 句首大写 |
| Numeric | 圈数、人数、时间 | Medium | 500 | 20 | 24 | 0 | 不改写。`Inf` 保持现有拼法 |
| Technical | 地址、协议、只在次级或邀请细节里出现 | Regular | 400 | 14 | 20 | 0 | 原样 |

舞台上的玩家名用 40 / 48，Bold，不用 Display 56。名字沿用 Profile 的 1–16 个可见字符。

Page 标题用 32 / 40，SemiBold，字距 +1%，最长约 24 字。它不是第九个随便加粗的样式，而是 Section 之上、Display 之下的页面名。

画布 1920×1080。字号不随 `ui_scale` 再乘。收缩仍走 `UiFit`。

用法：

- Display 一屏至多一处。它不是按钮文字。
- Navigation 不和 Button 做成同一字号。顶栏是路标，Rail 才是动作。
- Section 是小标签，永远轻于它下面的名字。
- Button 只给可按的动作。空座位不是按钮，不用这个角色。
- Body 用来写句子。句子不大写，不加字距。
- Caption 用来写「Ready to play」「Beacon. Not an internet directory.」。
- Numeric 和左侧标签分成两列。不换成等宽科技字。比例写成 `2/5`，中间一条普通斜线。
- Technical 不进入主列。IP、端口、协议只有在邀请细节或局域网列表的次级行里才出现。

垂直节奏只用 4 / 8 / 12 / 16 / 24 / 36 / 48。栏目标题和正文相距 12。Rail 和分隔线相距 24。禁止负字距。

禁止：

- Body、Caption、Technical 升到 Bold
- 整页 ExtraBold 或 Thin
- 18px 以下使用 Light
- 用全大写排一整句
- 打开字体自带的奖励图形
- 用外发光补偿字重

### CJK fallback

Playpen Sans 不覆盖中日韩。

```text
1. Playpen Sans
2. 一款以后指定的伙伴黑体，只补缺字
3. 不再落到系统界面字体
```

伙伴黑体本文件不选定、不导入。选定之前，菜单文案保持拉丁文。禁止用 Inter、Segoe UI、PingFang、微软雅黑或思源黑体临时顶上。以后的伙伴黑体要能映射 Regular / Medium / SemiBold / Bold，笔画有人味，不带霓虹，不带圆体。拉丁字母仍由 Playpen Sans 画。

---

## 4. Color philosophy

底不是纯黑。结构色低饱和，偏暖或偏灰绿，让纸和场地有颜色，而不是终端。

| 角色 | 作用 |
|---|---|
| Ground | 深炭或深灰绿。舞台后面的空气 |
| Ink | 骨白、暖白。主要的字 |
| Secondary | 灰米。说明和次级事实 |
| Structure | 比 Ground 略亮的一条线，或一小块实心面 |
| Accent | 一个品牌色。一屏最多一处，并且有含义 |

强调色可以给 Host 的 Start，或舞台上的字标。它不给 Hover，不给 Focus，不给每颗按钮，不给描边。

Focus 是骨白下划线，或一条 shear。键鼠和手柄同一套。不发光。

现有粉紫 `PillPink`、紫黑渐变、焦点粉边，是旧 HUD。新页面不再扩散。精确色值留到真正改主题的那一刀，本文件只锁稀缺规则。

---

## 5. Surface philosophy

页面的容器是空白和舞台，不是卡片。

允许实心表面的地方：

```text
一组座位共用的一块面
Host 的 Start
Compact Modal（离开确认、Host closed）
```

不允许：

```text
每个座位一张卡
每个导航项一张卡
主菜单三张大卡
用空卡片表示 EMPTY SEAT
用面板把 IP 和测试按钮包成一个「大厅」
```

空座位是缺席，用留白和一行 Caption 表示，不给它一只盒子。

导航行默认只有字。悬停把字收到 Ink，不铺发光底板。

---

## 6. Geometry

shear 是结构，不是按钮特效。它用于当前导航的标记、分隔、以及很少的块面边缘。

大多数边缘是剪切或直角。圆角如果出现，保持小，并且少见。没有胶囊，没有发光描边当形状。

几何用来切开空间，不用来给每个控件加一座舞台。

---

## 7. Texture

Ground 上可以有一层很轻的颗粒或纸感。它不盖住字，不动画，不闪。

禁止用粒子、扫描线、光晕、噪点叠在按钮上制造「高级」。材质属于世界和纸，不属于每一只控件。

---

## 8. Illustration / character usage

角色图是身份，不是装饰图标墙。

顶栏用小头像加名字。主菜单的舞台可以放大角色或场地。Profile 可以给肖像空间。Lobby 的座位用小头像，后面是名字。

没有新图时，舞台留空。禁止用色块卡片、发光框或占位面板代替角色。

Playpen Sans 自带的儿童奖励图形不使用。

---

## 9. Negative space

每一页必须有一块不被字和控件碰的区域。主菜单里那一块就是舞台。连接中、失败、版本不符，是舞台上的三行字，不是缩小的设置面板。

留白是层级的一部分。把空白填上说明文字，层级就没了。

---

## 10. UI density

一页一个问题，一个锚点，有限的几行事实。

| 页面问的问题 | 主列允许看见 |
|---|---|
| 主菜单 | 名字、一句状态、三条动作 |
| Profile | 我是谁，以及只读的成绩和档 |
| Play | 继续、单人、多人 |
| 多人首页 | 三条去向，加上本地最近一次 |
| 开房 | 身份、角色、模式，然后房间规则 |
| 加入 | 一种输入，一个角色 |
| 大厅 | 人、房间事实、一句连接、邀请、Ready / Start |
| 连接中 / 失败 / 版本不符 | 一句结论 |

`Add`、`Remove`、`Seed`、`no bind`、peer id 不出现在这些主列里。

---

## 11. Button philosophy

按钮是动作，不是版面的砖。

- 顶栏项是导航，用 Navigation 字级，不做成和第二套 Rail 一样大的块。
- Rail 三条同高。没有第四颗更大的 PLAY。
- 主动作靠位置。Host 的 Start 是少数可以实心的动作。客人没有 Start，也不放一颗灰按钮占位。
- Ready 在正式大厅里是动作。Phase 3 的领域层把它默认为真。正式切换是以后的多人界面，不是现在往测试面板上加一颗更好看的 Ready。
- 危险动作（离开、退出）用文字和确认，不靠发光红胶囊。
- Disabled 是降透明度并且不可点。满员房间被按下时走 Error，不假装连上了。

---

## 12. Panel philosophy

Panel 不是页面的同义词。

正式界面里，Panel 只等于 Compact Modal 和那一块座位组。`FloatingPanel` 作为「把整页功能装进 1680×920 深色板」的做法，到此停用。已经存在的局域网叠层保持原样，直到 Phase 5 按本文件和 screen spec 换掉。在那之前不要美化它。

设置是从侧面进入的 Drawer，不是第二块居中大板。

---

## 13. What not to do

```text
纯黑 + 紫 + 品红 + 外发光 + 全屏 FloatingPanel + 到处是卡
中央巨大 PLAY
把测试词排成主视觉
把 Playpen Sans 全部设成 ExtraBold 就算换了字体
用卡片填满舞台
用 IP 当房间的标题
为 Phase 3 的调试流程再做一版皮肤
```

Phase 3 的完成证明是 `LobbyManager` 和 `tools/ci/lobby_probe.gd`。不是一张更好看的测试板。

---

## 14. Examples

主菜单的结构，不是皮肤稿：

```text
WPG     HOME    PLAY    MULTIPLAYER    PROFILE    SETTINGS          [av] NightFox     12:04:01

                              （舞台：角色 / 场地 / 或留空）


                              NIGHTFOX
                              Ready to play

              ─────────────────────────────────────────────
              CONTINUE              SOLO              MULTIPLAYER
              Loop 21               New run           Create or join
              ─────────────────────────────────────────────

              BEST  24                                           LAST  Yard
```

大厅的语义，留到 Phase 5 才做成界面。这里只锁定它不是测试板：

```text
NIGHTFOX'S ROOM                                          CO-OP

PLAYERS
[av]  NightFox     Host      Boar       Ready
[av]  Ada          Player    Chicken    Ready
      Empty seat

ROOM
Co-op              Yard              Goal 20

CONNECTION                         INVITE
Direct                             Copy      QR

                              Ready              Start
```

下面这张不是例子，是已否决的测试面：

```text
LAN
127.0.0.1
no bind
Add
Remove
Seed from record
EMPTY SEAT
EMPTY SEAT
```

它不进入主题，不进入线框，不再被排版。
