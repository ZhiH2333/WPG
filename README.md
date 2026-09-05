# WPG

这是一次**架构重写**，不是把旧作 Wild-Pig-Gun 再抄一遍。

保留俯视射击肉鸽的设计方向（波次、构筑、商店），但战斗运行时、输入、反馈和 UI 全部重写。卖点是**打起来有重量**：瞄准、走位、后坐、打空、换弹节拍。不要功能清单比旧作更长。

当前仓库从空白 Godot 4.6 工程起步。旧作只允许对照设计，禁止移植其 Autoload、UI 缩放器、自动锁敌开火、云存档、账号、图鉴。

## 怎么运行

用 Godot **4.6** 打开本仓库，按 F5。主场景是 `sandbox/combat_sandbox.tscn`。

- 平台：Desktop 为主（同一套战斗规则，手机输入后置）
- 引擎：Godot 4.6，纯 GDScript，静态类型
- 渲染：桌面 **Forward Plus**（不要用 Web / GL Compatibility 主导架构）
- 显示：1920×1080，`canvas_items` + `expand`，`content_scale_factor = 1`

## Day 1 范围（当前已完成）

只搭可运行的 Combat Sandbox 骨架与输入层：

- 项目设置、功能内聚目录、2D 碰撞层命名
- 输入映射与 `PlayerInput`（只读三个量）
- 灰盒沙盒：地板、墙、玩家占位、相机简单跟随
- `DebugOverlay` 显示输入与 FPS
- Autoload **0** 个

**本阶段明确不做：**

- 玩家加速度移动（也不做 `velocity = input * speed`，也不做瞬移凑合）
- 相机鼠标偏移 / 平滑 / 震屏
- 武器、子弹、对象池、开火
- 敌人、伤害、动画状态机
- Arena 波次、升级、商店、存档
- 主菜单 / 设置 / HUD 壳、虚拟摇杆
- Web 导出妥协、C#、外部 ECS

按 WASD，人物**不会移动**；`move_vector` 只会反映在 DebugOverlay 上。这是验收项，不是漏做。

## 输入合同（全项目唯一，后续沿用）

只产出三个量，全游戏共用：

```text
move_vector    Vector2   移动方向
aim_vector     Vector2   瞄准方向（可与移动不同）
fire_held      bool      是否按住开火
```

桌面（Day 1）：

- WASD（可加方向键）→ `move_vector`
- 鼠标世界坐标相对玩家 → `aim_vector`（归一化；与玩家重合时保持上一帧或 `Vector2.RIGHT`，禁止 NaN）
- 按住鼠标左键 → `fire_held`
- 没有 `aim` action；瞄准用鼠标位置，不锁最近敌人

`fire_held` 本阶段只读出并显示，不接到武器。场景中不得出现子弹。

手机双摇杆是后续阶段；不要做 Input Autoload。输入组件挂在玩家节点上。

## 禁止事项（旧作不要带进新仓库）

- 自动锁最近敌人；PC 自动开火；手机「自动射击」开关；桌面虚拟摇杆
- `RunState` / `ProjectilePool` / `GameFlow` / `UiCanvasScaler` 以及任何全局单例（本阶段 Autoload = 0；全程建议 ≤ 2）
- 用 `Control.scale` 当 UI 缩放；像素坐标硬编码 HUD；脚本里 `StyleBoxFlat.new()`
- `Engine.time_scale` 做 hitstop；Autoload 或任意脚本改 `physics_ticks_per_second`
- 云 API、账号、社区、图鉴、emoji HUD
- 把 `scripts/player` 和 `scenes/player` 切开

## 目录（功能内聚）

场景和脚本放在同一功能目录，不要按「脚本仓库 / 场景仓库」切开：

```text
player/     玩家场景、占位、PlayerInput（后续 Motor / Aim / Health / AnimState）
weapons/    三把枪 + 弹道 + 池（尚未开始）
enemies/    敌人（尚未开始）
combat/     碰撞层常量；后续 CombatWorld、伤害、HitFeedback
arena/      灰盒图、WaveDirector（尚未开始）
camera/     相机手感（Day 1 仅玩家身上的简单跟随）
ui/         仅 Slice 四个界面 + Theme（尚未开始）
data/       武器/敌人/升级 Resource（尚未开始）
debug/      DebugOverlay
sandbox/    Day 1 主场景
```

## 碰撞层（仅建层，不实现弹道）

| 层 | 名称 |
|---|---|
| 1 | player |
| 2 | enemy |
| 3 | player_bullet |
| 4 | enemy_bullet |
| 5 | wall |

脚本一律走 `GameCollisionLayers`，禁止写裸数字 `1/2/4/8`。

## 下一步：Day 2

**Day 2 才做加速度移动。** Motor：加速度 / 减速度 / 摩擦 → `velocity`。禁止 `velocity = input * speed`。

再往后才是瞄准相机偏移、手枪与对象池、三把枪身份差、受击链、波次和升级。先写成一把能瞄准、能打空、有后坐的枪，再叠肉鸽内容。
