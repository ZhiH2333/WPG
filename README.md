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
- 灰盒沙盒：地板、墙、玩家占位
- `DebugOverlay` 显示输入与 FPS
- Autoload **0** 个

Day 1 当时人物不移动、相机是玩家身上的裸 `Camera2D`。那是当时的验收，不是现在的行为。

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
- Autoload 仍为 0

## Day 3（已完成）：独立相机 + 瞄准重量

相机不再是 Player 的装饰子节点。`player.tscn` 里没有 `Camera2D`。`PlayerCamera` 与 `AimReticle` 作为 `CombatSandbox` 里和 Player **平级** 的节点。

相机合同：

```text
look_target = player.global_position + aim_vector * look_ahead
global_position = lerp(look_target, 1.0 - exp(-follow_smoothing * delta))
```

- 前探只用**归一化** `aim_vector * look_ahead`，不用鼠标离玩家的距离比例（避免跟 `get_global_mouse_position` 正反馈漂走）
- 只用脚本指数平滑；`position_smoothing_enabled`、`drag_margin` 全关。禁止双重平滑
- 不旋转相机，`zoom` 保持 `(1, 1)`
- 世界准星：`AimReticle.global_position = mouse_world_position`（浅青十字），不是 CanvasLayer HUD
- 仅窗口内且有焦点时藏系统光标；鼠标移出窗口或失焦立刻恢复，避免桌面丢指针；退出场景后一定恢复

参数（集中在 `PlayerCamera` 的 `@export`）：

| 参数 | 初值 | 含义 |
|---|---|---|
| `look_ahead` | 100 | 前探像素，锁在 80～120 |
| `follow_smoothing` | 8 | 越大越跟手；快甩鼠标会落后再追上 |

`DebugOverlay` 有 `look_target`、`camera_offset`、`camera_pos`。开火时镜头不抖、不后坐、不缩放。

## Day 4（已完成）：手枪 + 本局弹池 + 假人

按住开火能打出池化手枪弹，能打空，能打到假人掉血并跳出数字。

开火合同（时间戳，**不用 Timer 节点**）：

```text
fire_held 且 now >= next_fire_at → 开火，next_fire_at = now + 180ms
fire_held 为假 → next_fire_at = mini(next_fire_at, now)（松开后立刻可点射）
在 _process 里判开火（PlayerInput process_priority=-100 已先更新），按下当帧出第一发
```

出膛：

- 子弹从 `Visual/Muzzle`（本地约 `(28, 0)`）飞出，不从身体中心冒出
- 方向 = `aim_vector`，不锁最近敌人；没敌人也能对空地连射
- 本阶段散布 = 0

池（挂在本局 `CombatSandbox/Projectiles`，**不是 Autoload**）：

```text
Acquire → 飞 → 命中假人 / 撞墙 / 出界 / 寿命到 → Release
capacity = 64，预实例化。禁止每发 instantiate/queue_free
池满时这一发打不出并记 refused，禁止删天上正在飞的弹
```

假人：3 个静止红块，max_hp=40。命中扣血、闪白 ≤0.1s、世界伤害数字向上漂约 0.45s。HP≤0 变灰并关掉受伤，留在场上，不 `queue_free`、不掉落。

手枪参数（集中在 `Pistol` 的 `@export`）：

| 参数 | 初值 | 含义 |
|---|---|---|
| `fire_interval` | 0.18 | 连发间隔（秒） |
| `projectile_speed` | 980 | 弹速 |
| `damage` | 8 | 单发伤害 |
| `lifetime` | 0.9 | 子弹最长存活 |

`DebugOverlay` 增补 `fire_cd`、`active_bullets`、`pool_free`、`last_shot_refused`、`dummy_hp`。

**本阶段不做：** 霰弹/步枪、换弹 UI、相机后坐/震屏、Hitstop、敌人 AI/波次、死亡碎裂。

## 明确不做（直到后续对应日）

- **Day 5 才做**霰弹 + 步枪身份差
- 震屏 / 受击踢镜 / 开火后坐 / 换弹进度弧
- 敌人行走、还击、死亡碎裂、掉落
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

另有只读辅助量 `mouse_world_position`，给世界准星用。

桌面：

- WASD（可加方向键）→ `move_vector`
- 鼠标世界坐标相对玩家 → `aim_vector`（归一化；与玩家重合时保持上一帧或 `Vector2.RIGHT`，禁止 NaN）
- 按住鼠标左键 → `fire_held`
- 没有 `aim` action；瞄准用鼠标位置，不锁最近敌人
- Motor **只读** `move_vector`；相机 / 准星 **只读** `aim_vector` 与 `mouse_world_position`；Pistol **只读** `fire_held` 与 `aim_vector`。禁止武器自己 `is_action_pressed("fire")`

手机双摇杆是后续阶段；不要做 Input Autoload。输入组件挂在玩家节点上。

## 禁止事项（旧作不要带进新仓库）

- 自动锁最近敌人；没目标就 `return`；PC 自动开火；手机「自动射击」开关；桌面虚拟摇杆
- 子弹从身体/武器节点中心出，而不是枪口
- 用 Timer 节点做射速；等下一个 timeout 才出第一发
- 把弹池做成 Autoload；每发 `instantiate`/`queue_free`；池满删天上的弹
- 把 `Camera2D` 死挂在 Player 上，再用 Tween 随机 `offset` 当震动
- 引擎 `position_smoothing` 和脚本 lerp 同时开（双重平滑）
- 用鼠标离玩家的距离拉镜头（正反馈漂走）
- `RunState` / `GameFlow` / `UiCanvasScaler` 以及任何全局单例（Autoload = 0；全程建议 ≤ 2）。本局节点可以有 `ProjectilePool`
- 用 `Control.scale` 当 UI 缩放；像素坐标硬编码 HUD；脚本里 `StyleBoxFlat.new()`
- `Engine.time_scale` 做 hitstop；Autoload 或任意脚本改 `physics_ticks_per_second`
- `velocity = move_vector * speed` 作为唯一移动式（desired 可以用乘法，禁止把 desired 直接赋给 velocity）
- Tween / 直接改 `position` 当移动；先瞬移凑合
- 云 API、账号、社区、图鉴、emoji HUD
- 把 `scripts/player` 和 `scenes/player` 切开

## 目录（功能内聚）

场景和脚本放在同一功能目录，不要按「脚本仓库 / 场景仓库」切开：

```text
player/     玩家场景、PlayerInput、PlayerMotor、Muzzle；Pistol 挂在玩家上
weapons/    Pistol、Projectile、ProjectilePool（本局节点）
enemies/    DummyTarget（静止假人）
combat/     碰撞层常量、DamageNumber
arena/      灰盒图、WaveDirector（尚未开始）
camera/     PlayerCamera、AimReticle
ui/         仅 Slice 四个界面 + Theme（尚未开始）
data/       武器/敌人/升级 Resource（尚未开始）
debug/      DebugOverlay
sandbox/    主场景（Player / PlayerCamera / AimReticle / Projectiles / DummyTargets）
```

## 碰撞层

| 层 | 名称 | Day 4 用法 |
|---|---|---|
| 1 | player | 玩家只撞墙 |
| 2 | enemy | 假人；不挡玩家移动 |
| 3 | player_bullet | 手枪弹；mask = enemy + wall |
| 4 | enemy_bullet | 预留 |
| 5 | wall | 灰盒围墙 |

脚本一律走 `GameCollisionLayers`，禁止写裸数字 `1/2/4/8`。

## 下一步：Day 5

**Day 5 = 霰弹 + 步枪身份差。** 三把枪 30 秒可辨：手枪准而快、霰弹走近再扣、步枪按住喷且连续散布变大。不要提前做换弹 UI 或镜头后坐。
