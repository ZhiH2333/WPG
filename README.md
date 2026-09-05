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

## Day 1（已完成）：骨架与输入

- 项目设置、功能内聚目录、2D 碰撞层命名
- 输入映射与 `PlayerInput`（只产出 `move_vector` / `aim_vector` / `fire_held`）
- 灰盒沙盒：地板、墙、玩家占位、相机简单跟随（无平滑、无偏移、无震动）
- `DebugOverlay` 显示输入与 FPS
- Autoload **0** 个

Day 1 当时人物不移动，只验证输入可读。那是当时的验收，不是现在的行为。

## Day 2（已完成）：加速度移动

`PlayerMotor` 把 `move_vector` 积成有惯性的 `velocity`，`Player` 在 `_physics_process` 里写入后 `move_and_slide()`。禁止 `velocity = move_vector * speed` 直接贴地瞬移。

移动合同：

```text
move_vector
  → desired_velocity = move_vector * move_speed
  → 有输入且大致同向：acceleration 靠近 desired
  → 有输入但夹角大（转向/反向）：deceleration 先刹，禁止瞬间翻转
  → 无输入：friction 靠近 Vector2.ZERO
  → Player.velocity = Motor 结果
  → move_and_slide()
```

参数（集中在 Motor 的 `@export`，单位像素/秒、像素/秒²）：

| 参数 | 初值 | 含义 |
|---|---|---|
| `move_speed` | 420 | 最高移速。`get_vector` 已限长，不再二次归一化 |
| `acceleration` | 2400 | 同向加速，静止到全速约 0.18s |
| `deceleration` | 3200 | 转向/反向刹车 |
| `friction` | 1800 | 松手滑行，全速到停约 0.23s |
| `turn_angle_degrees` | 90 | 超过此夹角改用 deceleration |

其它约束：

- `CharacterBody2D.motion_mode = MOTION_MODE_FLOATING`（俯视，无重力、无地板吸附）
- 朝向只转 `Visual`，跟 `aim_vector`；位移跟 `move_vector`。必须能 strafing
- 撞墙靠 `move_and_slide` 沿墙滑，不写射线绕墙
- `fire_held` 仍只显示，不生成子弹
- 相机仍是 Day 1：无平滑、无鼠标偏移、无震动
- Autoload 仍为 0

按住 WASD，人物会移动；松开会滑行一小段再停。`DebugOverlay` 增补 `velocity` 与 `speed`。

## 明确不做（直到后续对应日）

- **Day 3 才做**瞄准相机偏移 / 平滑 / 震屏
- 武器、子弹、对象池、开火消费 `fire_held`
- 敌人、伤害、AnimationTree / 完整动画状态机、Dash
- Arena 波次、升级、商店、存档
- 主菜单 / 设置 / HUD 壳、虚拟摇杆
- Web 导出妥协、C#、外部 ECS、任何 Autoload

## 输入合同（全项目唯一，后续沿用）

只产出三个量，全游戏共用：

```text
move_vector    Vector2   移动方向
aim_vector     Vector2   瞄准方向（可与移动不同）
fire_held      bool      是否按住开火
```

桌面：

- WASD（可加方向键）→ `move_vector`
- 鼠标世界坐标相对玩家 → `aim_vector`（归一化；与玩家重合时保持上一帧或 `Vector2.RIGHT`，禁止 NaN）
- 按住鼠标左键 → `fire_held`
- 没有 `aim` action；瞄准用鼠标位置，不锁最近敌人
- Motor **只读** `PlayerInput.move_vector`，禁止自己读 WASD

`fire_held` 本阶段只读出并显示，不接到武器。场景中不得出现子弹。

手机双摇杆是后续阶段；不要做 Input Autoload。输入组件挂在玩家节点上。

## 禁止事项（旧作不要带进新仓库）

- 自动锁最近敌人；PC 自动开火；手机「自动射击」开关；桌面虚拟摇杆
- `RunState` / `ProjectilePool` / `GameFlow` / `UiCanvasScaler` 以及任何全局单例（本阶段 Autoload = 0；全程建议 ≤ 2）
- 用 `Control.scale` 当 UI 缩放；像素坐标硬编码 HUD；脚本里 `StyleBoxFlat.new()`
- `Engine.time_scale` 做 hitstop；Autoload 或任意脚本改 `physics_ticks_per_second`
- `velocity = move_vector * speed` 作为唯一移动式（desired 可以用乘法，禁止把 desired 直接赋给 velocity）
- Tween / 直接改 `position` 当移动；先瞬移凑合
- 云 API、账号、社区、图鉴、emoji HUD
- 把 `scripts/player` 和 `scenes/player` 切开

## 目录（功能内聚）

场景和脚本放在同一功能目录，不要按「脚本仓库 / 场景仓库」切开：

```text
player/     玩家场景、占位、PlayerInput、PlayerMotor
weapons/    三把枪 + 弹道 + 池（尚未开始）
enemies/    敌人（尚未开始）
combat/     碰撞层常量；后续 CombatWorld、伤害、HitFeedback
arena/      灰盒图、WaveDirector（尚未开始）
camera/     相机手感（Day 1 仅玩家身上的简单跟随；Day 3 才做偏移）
ui/         仅 Slice 四个界面 + Theme（尚未开始）
data/       武器/敌人/升级 Resource（尚未开始）
debug/      DebugOverlay
sandbox/    主场景
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

## 下一步：Day 3

**Day 3 才做瞄准相机偏移。** 跟随玩家 + 向鼠标/准星偏移 80～120px。不要提前做震屏和武器。
