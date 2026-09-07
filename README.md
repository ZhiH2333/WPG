# WPG

这是一次**架构重写**，不是把旧作 Wild-Pig-Gun 再抄一遍。

保留俯视射击肉鸽的设计方向（波次、构筑、商店），但战斗运行时、输入、反馈和 UI 全部重写。卖点是**打起来有重量**：瞄准、走位、后坐、打空、换弹节拍。不要功能清单比旧作更长。

**玩家是持枪野猪。** 橙灰盒 Player 就是这头猪，枪的幻想是「猪拿枪乱打」，不是猎人进场打野猪。敌人仍是近战/远程两种体型（红三角 / 紫远程），不要改成「猎人」、不要把敌人改名成 pig。注释和文档禁止写成「猎人」「打猪」。

当前仓库从空白 Godot 4.6 工程起步。旧作只允许对照设计，禁止移植其 Autoload、UI 缩放器、自动锁敌开火、云存档、账号、图鉴。

## 怎么运行

用 Godot **4.6** 打开本仓库，按 F5。主场景是 `ui/main_menu.tscn`：先看到居中 `WPG` / Play / Quit。点 Play（或 Enter）才进 `sandbox/combat_sandbox.tscn`。

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
Day 4 当时 capacity = 64。Day 5 提到 96。禁止每发 instantiate/queue_free
池满时这一枪打不出并记 refused，禁止删天上正在飞的弹
```

假人：3 个静止红块。Day 4 为 max_hp=40；Day 5 提到 80 方便试步枪。命中扣血、闪白 ≤0.1s、世界伤害数字向上漂约 0.45s。HP≤0 变灰并关掉受伤，留在场上，不 `queue_free`、不掉落。

手枪参数（集中在 `Pistol` 的 `@export`）：

| 参数 | 初值 | 含义 |
|---|---|---|
| `fire_interval` | 0.18 | 连发间隔（秒） |
| `projectile_speed` | 980 | 弹速 |
| `damage` | 8 | 单发伤害 |
| `lifetime` | 0.9 | 子弹最长存活 |

`DebugOverlay` 当时增补 `fire_cd`、`active_bullets`、`pool_free`、`last_shot_refused`、`dummy_hp`。

## Day 5（已完成）：三把枪身份差

同一套瞄准 + 按住开火合同，只换节奏。键盘 **1 / 2 / 3** 切手枪 / 霰弹 / 步枪。切枪立刻换当前武器、不走火；切走步枪时散布清零。切枪不进入 `move/aim/fire_held` 三量合同。

开火合同差异（时间戳，**不用 Timer**）：

```text
三把都是：fire_held 且 now >= next_fire_at → 开火，next_fire_at = now + interval
手枪：松开 → next_fire_at = mini(next_fire_at, now)（可立刻点射）
霰弹：松开 → 不改 next_fire_at（泵必须走完，禁止连点刷爆发）
步枪：松开 → next_fire_at = mini(next_fire_at, now)；未开火时每帧收回散布
```

身份（30 秒可辨，禁止只改 damage）：

| 枪 | 节奏 | 弹道 |
|---|---|---|
| 手枪 | 0.18s，松开可点 | 单弹、散布 0、细而准 |
| 霰弹 | 0.62s 泵，松开不复位 | 同一枪口均匀扇形 8 粒（±1° 微抖），每粒伤害 6 |
| 步枪 | 0.09s 连发，松开可点 | 第一发准；每发 +0.9° 散布至 11°；停火 18°/s 收回 |

霰弹一扳机需要 8 发空闲弹；不够则整枪拒发（`refused++`），禁止打出残散弹。池 **capacity = 96**，仍是本局节点、同一 `projectile.tscn`。

`WeaponHost` 包住三把枪；`Weapon` 只抽重复合同。`DebugOverlay` 读 Host：`weapon`、`spread_deg`、`pellets`。

**当时不做：** 换弹弧、弹药数字 HUD、镜头后坐/震屏、Hitstop、敌人 AI。

## Day 6（已完成）：打得动、死得掉

沙盒不再放静止假人。2 近战（左/下约 350px）+ 2 远程（右/上约 420px）。`CombatSandbox` 在 `_ready` 把 `Player` 引用 bind 给每个敌人，禁止每帧 `get_nodes_in_group("player")`。

- 近战：廉价 seek 走向玩家（`desired = to_player.normalized() * speed`，再 `move_toward`），`Area2D` 接触伤害 8。不射击。
- 远程：保持 280±70 距离带（过近后退、过远靠近、带内 strafing）；带内朝玩家**当前位置**开枪，不预判。时间戳 0.9s，无 Timer。弹从 `Visual/Muzzle` 出。
- 玩家 `PlayerHealth`：max_hp=100，i-frame 0.45s。扣血、闪白、伤害数字。HP≤0 停 Motor、`WeaponHost.deactivate_all()`、变灰留场，不弹菜单、不重载场景。
- 敌人 0 血：停 AI / 物理、关碰撞、变灰留场。禁止 `queue_free`、禁止掉落。
- 敌人弹：本局 `CombatSandbox/EnemyProjectiles` 池 **32**，更大更慢深红弹。玩家弹池仍 **96**。同一 `projectile.tscn`，`reset(..., is_player_shot)` 切碰撞与颜色。
- 命中：玩家弹打 `EnemyBase`（`DummyTarget` 脚本仍可被打以免留着报错）；敌人弹打 `PlayerHealth`。不误伤己方。墙/出界/寿命到 → Release。池满打不出，不删天上的弹。
- Overlay：`player_hp` / `player_dead` / `enemy_hp`（类型+hp），以及两套池的 active/free。

接触重叠时由 i-frame 卡住，无敌结束再判一次，禁止每物理帧刮光。

**当时不做：** squash、击退位移、局部 hitstop、死亡碎裂、镜头后坐。

## Day 7（已完成）：打中有肉、死得能读

命中闭环同一拍发生：停弹回池 → 扣 HP + 数字 + 闪白（保留）→ 沿弹方向击退 → Visual squash/微转 → 该敌人局部 hitstop → 0 血塌缩留场。

- `HitReaction`（`combat/hit_reaction.gd`）只改 Visual：沿 hit 本地轴压到 ~0.82、垂直微胀 ~1.12，额外 tilt ±4.5°（符号跟 hit.x），约 0.1s 弹回 `scale=1` / tilt=0。不改 CollisionShape、不改根节点朝向、不用 Tween 改 position。
- 敌人击退走 `knockback_velocity` + `move_and_slide`：impulse 260，length 钳到 420，damping 1800。禁止 Tween `global_position`。撞墙沿墙滑。
- 局部 hitstop **只冻被打中的那只**：`_hitstop_left_sec = maxf(旧值, 0.012)`，刷新不叠加。期间不 AI、不转向、不开火、不接触伤害、不 `move_and_slide`。不改 `Engine.time_scale`，不冻玩家 / 相机 / 其它敌人 / 弹池。
- 霰弹 8 粒同一帧：8 段数字可以跳；击退累加后钳 max_speed；hitstop 仍是一次 12ms；squash 重开一次。禁止 8×12ms 冻成一次泵枪。
- 步枪 0.09s 连发：被打的敌人一顿一顿后仰，玩家移动/开火仍跟手。
- 玩家受击：闪白 + 数字 + 轻击退（impulse 180 / max 260 / damping 1800）+ 轻 squash。**不要玩家 hitstop**（那是输入延迟）。HP / i-frame 0.45s 与 Day 6 相同。
- 死亡可读（无粒子）：敌人变灰、scale → (1.15, 0.55)、tilt → 80° 倒地，0.15s 到位后冻结；停 AI / 转向 / 开火；关碰撞；可再滑一点击退后清零；不 `queue_free`。玩家只轻微压扁、不倒地 90°，停走停枪，不弹菜单。
- Overlay 增补 `hitstop_ms`（场上敌人剩余 hitstop 的最大值）和最近敌人的 `knockback_speed`。

三把枪身份参数、Motor / 相机 `@export` 初值、敌人 max_hp / 移速 / 射速未改。击退参数是另加的 `@export`。

**当时不做：** 音效、镜头后坐/震屏/zoom、开火枪身踢、死亡碎裂粒子、掉落物、换弹 UI。

## Day 8（已完成）：闭眼能分辨开火/受击

方向性反馈，不是随机抖。跟手公式仍是 Day 3：`look_target = player + aim * look_ahead`，指数平滑不变。shake 是**额外偏移**，加在 lerp 结果上。

- 相机 `apply_kick(direction, amplitude)`：`_shake_offset += dir * amplitude`，length 钳到 `shake_max=12`；每帧 `move_toward(ZERO, shake_decay=90 * delta)`。禁止随机 `Vector2`、禁止 Tween `Camera2D.offset`、禁止 zoom/旋转相机、禁止 `Engine.time_scale`。
- 开火踢 `-aim`：手枪 5、步枪 3、霰弹 9。**霰弹一扳机只踢一次、闪一次、响一声**（`Weapon._try_fire` 在 8 粒循环之外 `notify_shot_fired` 一次）。步枪连发每发轻踢，靠 max 12 + 快衰减，停火后很快回 0。
- 受击踢沿 `hit_direction`：敌人 2、击杀 4、玩家 6。玩家无 hitstop，移动仍跟手。局部 hitstop 仍只冻被打中的那只敌人。
- 枪口闪光：`Visual/Muzzle/MuzzleFlash` 唯一节点 show/hide，手枪 ~50ms，霰弹更大 ~70ms，步枪更短更窄 ~35ms。禁止每发 instantiate 闪光。
- 枪身短后坐：只平移 Visual.position（`-aim * 4/6/3 px`），0.1s 弹回。不改碰撞、不用 `HitReaction.play` 冒充后坐。
- 命中火花：接触点沿 `-hit` 微喷，0.08s `queue_free`。墙和肉都可以。不是 GPUParticles。
- `SfxPool` 挂在 `CombatSandbox` 上，**不是 Autoload**。8 个 `AudioStreamPlayer2D` 轮询，全忙抢最老。程序生成短 WAV（手枪短促、霰弹低沉一爆、步枪连点、敌人弹更闷、拒发咔）。池满拒发走 click，不当枪声。

Overlay 增补 `shake_offset` / `shake_speed`。三把枪身份、Motor 420、`look_ahead=100`、`follow_smoothing=8`、击退/hitstop 初值未改。

**当时不做：** 换弹 UI、弹药 HUD、AnimationTree、locomotion 状态机、死亡碎裂粒子海、掉落物、商店、10 人以上沙盒。

## Day 9（已完成）：13 人分侧沙盒，R 重置同一批节点

场上 **8 近战 + 5 远程 = 13**，不是均匀圆包围，不是四边下雨。玩家仍在原点。距玩家都 ≥ ~280px，开局不会刷在脸上秒伤。

- 近战：左侧一撮 4 只（x≈-520～-380，y 错开），下侧一撮 4 只（y≈380～430，x 错开）。廉价 seek + 正交偏置 `to_player.orthogonal() * ±40`（节点 index 奇偶定符号）。禁止每敌探查其它敌人、禁止 NavigationAgent。
- 远程：右侧 3 只（x≈500～615），上侧 2 只（y≈-410～-440）。距离带 / 枪口出膛 / 深红大弹与 Day 6 相同。
- 入场 stagger 0.0～0.8s，**同一侧同一小波**错开。倒完之前：Visual 从 scale 0.4 收到 1.0，近战不造成接触伤害，远程不开火。无预警圈 UI。
- 尸体变灰塌缩留场，不 `queue_free`。3 分钟循环靠 **R 原地重置同一批节点**，禁止 `reload_current_scene()`，禁止边死边 instantiate 新敌人，禁止 EnemyManager / WaveDirector。
- 重置合同：两套弹 `park_all`（玩家池仍 96，敌人池 **48**）→ 每个敌人 `reset_for_sandbox(spawn)` 满血站回两侧出生点（HitReaction.reset 清 `_dead`）→ 玩家原点满血、清 i-frame、解开 `WeaponHost` 并 activate **当前枪**（不强制切回手枪）→ Overlay 立刻反映人数。
- Overlay：`enemies_alive: 8M+5R`、`enemies_dead`、`nearest`、`reset: R`。不刷 13 条 HP。FPS 保留。13 人仍各自 `_physics_process`，不做 AI 分频。

三把枪身份、Motor / 相机 shake / 击退 / hitstop 初值未改。

**当时不做：** 30 人压测、波次表、商店、精英/Boss、掉落物、AnimationTree。

## Day 10（已完成）：30 人分侧压测，先量后改

场上正好 **20 近战 + 10 远程 = 30**。左 10 / 下 10 近战成撮，右 6 / 上 4 远程拉距。玩家原点。距玩家都 ≥ ~280px。同侧 stagger `index * 0.06` 钳在 0.0～0.8s，不会把一撮拉成 3 秒才入场。

- 敌人弹池 **48 → 64**（10 远程慢弹）。玩家池仍 **96**：步枪扫 22 秒 `last_shot_refused=0`，没有明显拒发，所以不上 128。
- Overlay：`enemies_alive` 动态摘要（开局 `20M+10R`）、`fps` / **`fps_min_2s` / `fps_avg_2s`**（2 秒滚动窗，20 个 0.1s 桶累加，不每帧推 1000 个样本）、`ai_stagger: off`、`reset: R`。不刷 30 条 HP。
- 压测方法：开局 30 人全活，步枪对人群扫 **22 秒**（允许被打、允许死、可按 R 再测）。读 Overlay 的 `fps_min_2s` / `fps_avg_2s`，不用感觉当结论。关 vsync 以外的额外 cap（测试脚本关 vsync；工程未设 `Engine.max_fps`）。
- **结论（headless / vsync off / 22s 步枪扫）：`fps_min_2s = 145`，`fps_avg_2s = 145`。门槛是 `fps_min_2s ≥ 55`，达标。**
- **Gated 修复：一项都没做。** 禁止「顺便」上 AI 分频。未做火花/数字池、未做偶数/奇数物理帧跳过 `_tick_ai`、未建 EnemyManager、未改 `physics_ticks_per_second`、未改 `time_scale`。命中火花仍是每发 instantiate / 0.08s `queue_free`。尸体仍 `set_physics_process(false)` 留场。R 重置同一批 30 个节点，禁止 `reload_current_scene()`。

三把枪身份、Motor 420、`look_ahead=100`、`follow_smoothing=8`、shake、击退/hitstop 初值未改。

**当时不做：** 波次表、商店、精英/Boss、掉落物、AnimationTree、第四把枪。

## Day 11（已完成）：手写句读，不是 30 人同时压

30 个预放节点改成 **预备役 → 按句读激活**。开局全部 `hold_in_reserve`，先 **P0 rest 1.5s**（场上 0 活），不要立刻 P1。活着的那一撮仍各自 `_physics_process` + 廉价 seek。尸体变灰留场；未出场的预备役隐藏并关物理。不要 instantiate 新敌人。

手写短语表在 `arena/encounter_phrases.gd`（`EncounterPhrases`），用**节点名**引用沙盒实例。禁止 SpawnBudget、禁止 WaveDirector、禁止权重随机填满。`CombatSandbox` 拥有该节点，不是 Autoload。

- **P0** rest 1.5s
- **P1** 左侧 4 近战 `MeleeLeft1..4`，同侧 stagger；等这 4 只全部 defeated（不是半场）
- **P3 重叠：** P1 还剩 1～2 只活着时提前激活右侧 3 远程 `RangedRight1..3`。若 P1 已清完才进 P3，也合法，**rest 仍走 P2**
- **P2 / P4 / P6** rest 1.5s（重叠已开 P3 则跳过 P2）
- **P5** 下侧 6 近战 + 上侧 2 远程同时压；等这 8 只全部 defeated
- **P7** dump 剩余未用节点（左 5–10、下 7–10、右 4–6、上 3–4）分侧激活
- **P8** `phrases_done`：空场 + 尸体。玩家仍可走可打空。不弹窗。按 R 从头

R 重置：两套弹 `park_all` → 玩家 `reset_for_sandbox` → 30 人全部 `hold_in_reserve`（不 `reset_for_sandbox` 再 stagger 全上）→ `EncounterPhrases.restart()` 回 P0。禁止 `reload_current_scene()`。

Overlay：`phrase`（P0=`0/8` / 句中=`1/8` / 结束=`phrases_done`）、`phrase_alive`、`rest_left`。`enemies_alive` / `enemies_dead` **只数非预备役**。句中并发约 4～12，不是一开局 `20M+10R`。

句间 rest 用 delta 倒数，不用 Timer 节点，不冻玩家、不用 `time_scale`。Day 10 已达标，**没有**火花池 / AI 分频 / EnemyManager。

三把枪身份、Motor 420、`look_ahead=100`、shake、击退/hitstop 初值未改。

**当时不做：** 升级弹窗、三选一、XP、商店、WAVE COMPLETE 大字、最小 HUD 壳。

## Day 12（已完成）：最小战斗 HUD

玩家不看 Overlay 也能读懂状态。`ui/hud.tscn` 是 `CanvasLayer` **layer=10**（低于 DebugOverlay 的 100）。`CombatSandbox` 拥有 Hud，`_bind_runtime` 在 Overlay bind 之后调用 `bind_player` / `bind_weapon_host` / `bind_encounter`。不是 Autoload，没有 `UiCanvasScaler`。

三块信息，只读已有 getter，HUD 不自己减 HP、不扫 group、不 tick 句读：

- **左下** HP：`PlayerHealth.get_hp()` / `get_max_hp()`，文字 `当前/最大` + `ProgressBar`（`custom_minimum_size = Vector2(280, 16)`）。填充色走 Theme（玩家灰盒橙 `Color(1.0, 0.62, 0.18)`）；**HP≤20** 把 type variation 切到红 `Color(0.86, 0.22, 0.20)`，禁止全屏闪红。扣血瞬时跳变，没有缓动。
- **左下** 当前武器：`WeaponHost.get_current_weapon().get_display_name()` → `Pistol` / `Shotgun` / `Rifle`。不要中文名，不要 6 个武器槽。切枪 1/2/3 同一帧换字。
- **顶中** 句读：直接显示 `EncounterPhrases.get_phrase_label()`（P0=`0/8`，句中=`1/8`…`7/8`，句间=`rest`，结束=`phrases_done`）。不要第二套编号。

布局：锚点 + VBox / HBox。左下 margin 左 32 / 下 32；顶中 margin 顶 24、pivot 居中。禁止 `Control.scale`、禁止 `position = Vector2(16, 16)` 当自适应、禁止脚本 `_ready` 里 `StyleBoxFlat.new()`。颜色/字号在 `ui/game_theme.tres`。所有 HUD 控件 `mouse_filter = IGNORE`，点 HUD 所占区域仍能改 `aim_vector`。

DebugOverlay 仍在左上：`fps_min_2s` / `phrase_alive` / `rest_left` / 池。禁止把 Overlay 删掉或把 FPS 搬进 HUD。

玩家死亡：HUD 仍在，HP 显示 `0/100`。没有 YOU DIED、没有死亡结算屏。R：HUD 立刻 `100/100`、枪名保持重置前那把、句读回 `0/8`。禁止 `reload_current_scene()`。

句读表 P0–P8、三把枪身份、Motor 420、`look_ahead=100`、shake、击退/hitstop、敌人数值、Day 10 gated 修复都没动。

**当时不做：** XP 条/等级、三选一、商店、材料/金币、WAVE COMPLETE、死亡屏、主菜单、设置、弹药数字、换弹弧。

## Day 13（已完成）：本局节点 RunSession

`arena/run_session.gd`（`class_name RunSession`）是 **CombatSandbox 的子节点**，与 `EncounterPhrases` 平级。不是 Autoload，不要旧名 `RunState` / `GameFlow`。只观察，不抄血：HP 仍只在 `PlayerHealth`，句读表仍只在 `EncounterPhrases`。禁止再存一份 `player_current_hp` / phrase 数组。禁止 `get_tree().paused`、禁止 `Engine.time_scale`、禁止信号总线。

三件事：

- **playing**：这局还在打。只有 playing 才累加 `elapsed_sec`，才调用 `EncounterPhrases.tick`
- **dead**：玩家死了。停止推进下一句（rest 倒完也不开下一句，P1 重叠 P3 也不再触发）。已经在场的非预备役敌人继续走/打。HUD 仍是 `0/100` + 当前枪 + 当时的 phrase。没有 YOU DIED、不锁镜头
- **cleared**：句读打完且人还活着。玩家仍可走、可打空（Day 11 P8）。`run_time` 冻结。不要弹「通关」
- **同一帧既死又 phrases_done → dead**

R 五步：两套弹 `park_all` → 玩家 `reset_for_sandbox` → 30 人 `hold_in_reserve` → `EncounterPhrases.restart()` → `RunSession.restart()`（playing，elapsed=0）。禁止 `reload_current_scene()`。

Overlay 增补：`run: playing|dead|cleared`、`run_time`。HUD 不 bind RunSession，不显示 run 字段，三块布局不变。

本阶段列表为空：不要 `upgrade_ids`、不要 xp、不要 gold、不要 wave_index。句读表 P0–P8、三把枪身份、Motor 420、`look_ahead=100`、shake、击退/hitstop、敌人数值、Day 10 gated 修复都没动。

**当时不做：** 升级 Resource、三选一弹窗、XP、商店、死亡结算屏。

## Day 14（已完成）：10 条升级 Resource，owned 恒空

升级是**数据，不是效果**。`data/upgrade_def.gd`（`UpgradeDef`）+ `data/upgrade_catalog.gd`（`UpgradeCatalog`）+ `data/upgrade_catalog.tres` 引用 `data/upgrades/` 下 10 个 `.tres`。禁止 `upgrades.json`、禁止 `FileAccess` 读 JSON、禁止 `BuildCatalog`、禁止稀有度权重 / luck / emoji。

10 个 id 锁死，映射到现有 `@export`（给 Day 15 应用层用）。本阶段**没有任何脚本**读取 catalog 后改 `PlayerHealth.max_hp` / `Weapon.damage` / `fire_interval` / `PlayerMotor.move_speed` / `Shotgun.pellet_count` / `Rifle.max_spread_deg` / `i_frame_sec`。

| id | title | kind | value | stackable |
|---|---|---|---|---|
| max_hp_s | Vitality I | MAX_HP_FLAT | 20 | false |
| max_hp_m | Vitality II | MAX_HP_FLAT | 40 | false |
| swift | Swift | MOVE_SPEED_PCT | 0.10 | true |
| heavy_round | Heavy Round | DAMAGE_FLAT | 2 | true |
| cadence | Cadence | FIRE_RATE_PCT | 0.12 | true |
| long_shot | Long Shot | PROJECTILE_SPEED_FLAT | 80 | true |
| second_skin | Second Skin | I_FRAME_FLAT | 0.10 | false |
| extra_pellets | Extra Pellets | SHOTGUN_PELLETS_FLAT | 2 | false |
| steady_rifle | Steady Rifle | RIFLE_MAX_SPREAD_FLAT | -2.0 | false |
| thick_hide | Thick Hide | KNOCKBACK_TAKEN_PCT | -0.20 | false |

`CombatSandbox` `preload` 目录并 `_run_session.bind_catalog`。启动断言 `get_count()==10`，10 个 id 各查一次，缺了才 `push_error`。`get_by_id` 找不到返回 null，不刷屏。重复 id 记错误并跳过后到的。

`RunSession` 持有 `PackedStringArray` 已选 id。`restart()` 必须 `clear`。本阶段没有按键/UI `push`。`get_owned_upgrade_ids()` 返回副本。**没有** `add_upgrade` / `apply` / `grant`。

Overlay：`catalog: 10`、`upgrades: 0`。HUD 不显示升级，三块布局不变。R 之后 upgrades 仍是 0。手感与 Day 13 相同：HP 100、Pistol 0.18/8、霰弹 8 粒、步枪 max_spread 11、移速 420、i-frame 0.45、玩家击退 impulse 180。

句读表 P0–P8、三把枪身份、Motor、相机、击退/hitstop、敌人数值、Day 10 gated 修复都没动。

**当时不做：** 运行时应用层、三选一弹窗、XP、商店。

## Day 15（已完成）：底值重算应用层

升级仍是数据；真正改手感的是 `arena/upgrade_applier.gd`（`UpgradeApplier`），CombatSandbox 子节点 `$UpgradeApplier`。禁止 `UpgradeDef` 自己改枪，禁止在当前值上 `+=`。公式：`runtime = baseline + owned 合计`。

底值在 Player 子节点 `_ready` 之后采集一次（手枪 `_ready` 已写下 `fire_interval=0.18`）。禁止把 0.18/8/420 写成第二份魔法数。10 个 kind 全部 match：MAX_HP_FLAT / MOVE_SPEED_PCT / DAMAGE_FLAT / FIRE_RATE_PCT / PROJECTILE_SPEED_FLAT / I_FRAME_FLAT / SHOTGUN_PELLETS_FLAT / RIFLE_MAX_SPREAD_FLAT / KNOCKBACK_TAKEN_PCT。

钳制：max_hp ≥ 1；pellet_count ≥ 1；fire_interval ≥ 0.02；move_speed ≥ 80；i_frame_sec ≥ 0.05；步枪 max_spread ≥ min_spread，apply 后当前散布钳进新 max。HP 合同：`apply_max_hp` 提高时当前 HP 加同一 delta（满血 100 + Vitality I → **120/120**）；降低时 `_hp = mini(_hp, new_max)`。

`RunSession.try_grant`：目录没有 → false；非 stackable 已有 → false；否则 append。`restart()` 仍 `clear`。RunSession 不管 HP/枪。

调试授予正好 1 条：action `debug_grant_upgrade`，物理键 **U**，不进 move/aim/fire_held。id=`max_hp_s`。第二次 U 忽略。玩家已死 U 无效。不要 10 个热键。

开局：bind/assert/restart 之后 `capture_baseline()` → `apply_owned()`（owned 空，等于写回底值）。

R 六步：两套弹 `park_all` → `RunSession.restart()`（owned 清空）→ `UpgradeApplier.apply_owned()`（回到底值）→ `Player.reset_for_sandbox()` → 30 人 `hold_in_reserve` → `EncounterPhrases.restart()`。禁止 `reload_current_scene()`。禁止 `get_tree().paused`。

Overlay：`grant: U`、`last_grant: max_hp_s|-`（R 清成 `-`），仍保留 `catalog` / `upgrades` / `player_hp` / `pellets` / `speed` / `fps_min_2s`。HUD 仍三块，HP 数字/条跟上新 max，不显示升级名。

句读表 P0–P8、10 张卡 id/kind/value、三把枪 `_ready` 身份赋值、Motor/相机/击退/hitstop 初值都没改。

**当时不做：** 三选一弹窗、XP、商店。

## Day 16（已完成）：句间三选一，替换 P2 / P4 / P6 rest

`ui/upgrade_offer.tscn`（`UpgradeOffer`，CanvasLayer **layer=20**）与 Hud 平级。用弹窗**替换** P2 / P4 / P6 的 1.5s rest。P0 开场 rest 1.5s 保留，不弹卡。P8 `phrases_done` 不弹第四次。本局最多 3 次；P2 被 P3 重叠跳过则少一次。

弹出时：停止 `EncounterPhrases.tick`（`AWAITING_OFFER` 直接 return）。禁止 `get_tree().paused`、禁止 `Engine.time_scale`、禁止 `PROCESS_MODE_ALWAYS`。`RunSession` 仍是 playing，elapsed 继续走。玩家可 WASD；`PlayerInput.set_fire_suppressed` 禁止开火（关窗后需松开左键才再打，避免点卡走火）；`WeaponHost.set_switch_suppressed` 禁止切枪，与死亡 `_switch_locked` 分开。弹窗打开时 1/2/3 选左/中/右卡。显示系统光标；关窗后走 `_sync_system_cursor`。

三张必须不同 id。`RunSession.draft_offer`：catalog 去掉「非 stackable 且已 owned」，洗牌取最多 3 张。stackable 已拥有仍可出现。不够 3 张就有几张出几张；0 张：不弹窗，立刻 `acknowledge_offer`。必须点一张（或键盘 1/2/3）才继续。没有跳过、没有刷新、没有「继续」。

选中：`try_grant` → `apply_owned` → 关窗 → `EncounterPhrases.acknowledge_offer()` 立刻 `_begin_phrase(index+1)`，不再跑 1.5s rest。HUD 跟上新 max（Vitality I → 120/120）；不在 HUD 上列已选卡。

U 在弹窗打开时无效。R 先关窗、解锁输入，再走现有六步。残留弹打死玩家：立刻关窗、不授予、不 acknowledge。

Theme 增补 `OfferTitle` / `OfferDesc` / `OfferButton`。禁止脚本里 `StyleBoxFlat.new()`。禁止 `Control.scale`。Dimmer `Color(0,0,0,0.55)` + 按钮挡住世界点击。

Overlay：`offer: open|closed`、`offer_ids: a,b,c|-`。HUD 仍三块，顶中 `get_phrase_label()` 在等待选卡时为 `offer`。

句读节点名 P0–P8、10 张卡 id/kind/value、三把枪 `_ready` 身份、Motor/相机/击退/hitstop 初值、UpgradeApplier 公式都没改。

**当时不做：** XP / 等级条、商店、刷新三选一。

## Day 17（已完成）：P8 后同一局再开一轮句读

打完 P8 且人还活着时，**同一局继续**：30 个节点 `hold` 回预备役，句读从 P0 再走一遍。不是新一场 `RunSession`，不是商店波。禁止 `reload_current_scene()`。

`RunSession.tick` **不再**因 `encounter.is_done()` 设 `CLEARED`。`Outcome.CLEARED` 枚举保留，本阶段活着打完不赋值。只有玩家死亡才 `DEAD`。playing 时 `elapsed` 跨轮连续加。

`CombatSandbox._loop_phrases`（在 `_run_session.tick` 之前调用）：

1. 两套弹 `park_all`（P7 dump 残留弹不许在轮间 rest 里继续打人）
2. 30 人 `hold_in_reserve`（尸体藏回出生点，不 `queue_free`、不 `instantiate`）
3. `EncounterPhrases.restart()` → P0 rest 1.5s（`_p3_started` 清零，重叠规则下一轮照旧）
4. `RunSession.notify_phrase_loop()` → `loop_index += 1`，outcome 保持 playing

禁止：`RunSession.restart()`（会清 owned、elapsed=0）；`UpgradeApplier.apply_owned` / `capture_baseline`；`Player.reset_for_sandbox()`。玩家留在当场坐标；当前 HP 不变（47/120 仍是 47/120）；当前枪不变；owned 不变。

时机：P7 清光 → `_begin_phrase(8)` 进 DONE 的同一帧或下一帧立刻 loop。HUD 允许闪 1 帧 `phrases_done`。P0 那 1.5s 就是轮间空窗。不要 WAVE COMPLETE、不要「继续」按钮。开局 `loop_index=0`；第一次 P8 后再开 → 1。无限直到死或 R，不要 cap。

第二轮起：P2/P4/P6 仍弹三选一；`draft_offer` 继续过滤非 stackable 已有。卡池空则 `acknowledge` 跳过。死亡仍 dead，不再 loop；已激活敌人继续动。没有 YOU DIED。R 仍是整局重置（owned=0、loop=0、HP 回底值满血、原点、P0）。

Overlay：`loop: %d`（在 `run` / `run_time` 附近）。HUD 顶中仍只显示 `get_phrase_label()`（下一轮 P0 又是 `0/8`）。不要第四块「ROUND 2」。

句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、UpgradeApplier 公式、Hud 三块锚点都没改。

**当时不做：** XP / 等级条、商店。

## Day 18（已完成）：击杀 XP，满条复用 UpgradeOffer

打死敌人才加 XP。XP 只活在 `RunSession`，不镜像进 `PlayerHealth`，不是 Autoload。禁止 `get_tree().paused`、禁止 `Engine.time_scale`、禁止 `PROCESS_MODE_ALWAYS`、禁止第二套 `LevelUpOverlay`。

击杀奖励：近战 **10**，远程 **12**。`DummyTarget` 不在沙盒、不给 XP。`hold_in_reserve` / R / 轮循环不算击杀。`EnemyBase.defeated` 在 `_on_defeated()` 之后 emit 一次；`CombatSandbox` 在 `_bind_enemies` 连接。

需求：`xp_to_next = 30 + (level - 1) * 15`。开局 level=1、xp=0、need=30。3 只近战 = 30，第一次升级在 P1 中段。`add_xp` 用 while 扣满，一次击杀可连升两级（`pending` 累加）。每级单独弹一次三选一。

与句间 offer **互斥排队**（同一时刻只能有一个 UpgradeOffer）：

1. 弹窗已开 → 不再开第二扇；XP 只进 pending
2. Encounter 处于 `AWAITING_OFFER` → 句间优先
3. 不在 awaiting、弹窗关着、pending_level > 0 → 开升级三选一（`draft_offer` 同一套过滤）
4. 升级弹窗选完：`try_grant` → `apply_owned` → close → `consume_pending_level`；**禁止** `acknowledge_offer`
5. 句间弹窗选完：保持 `acknowledge_offer`

升级弹窗打开时：停 `EncounterPhrases.tick`；玩家可走、不可开火、1/2/3 选卡；显示系统光标。**敌人 AI 不停**。HUD 顶中仍显示当前句（例如 `1/8`），`offer` 只给 `AWAITING_OFFER`。

若最后一击同时满 XP 且 P7 清光：先弹升级，禁止同一帧 `_loop_phrases`。选完若仍 `is_done()` 再 loop。pending 或弹窗开着时不要 loop。轮循环 **不清 XP / level / owned / HP**。

死亡：关窗、不授予、pending 丢弃；不再开升级窗。没有 YOU DIED。R：xp=0、level=1、pending=0，其余仍走现有六步。U 仍只授 `max_hp_s`。不要灌满 XP 热键。不要 XP 掉落物、不要世界飘「+10 XP」。

HUD 左下 HP 条下面一条 XP 灰盒：`ProgressBarXp` + `Lv.%d  %d/%d`。Overlay：`level` / `xp: a/b` / `pending_lv`。不要第四块 ROUND。

句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、UpgradeApplier 公式都没改。

**当时不做：** 商店、死亡结算屏、主菜单。

## Day 19（已完成）：死亡结算条

玩家死后弹出 **一条结算条**（`ui/run_summary.tscn`，`RunSummary`，CanvasLayer **layer=15**）：本局时长、击杀数、已选升级 id。按 R 关掉并整局重置。不是主菜单，不是商店，不是通关屏。禁止 `get_tree().paused`、禁止 `Engine.time_scale`、禁止 `PROCESS_MODE_ALWAYS`、禁止全屏 Dimmer、禁止 Button、禁止剪贴板、禁止 `change_scene` / `reload_current_scene()`。没有 YOU DIED 大字。

居中 `PanelContainer`（`custom_minimum_size=Vector2(640, 156)`），全部 `mouse_filter=IGNORE`。文案：`DEAD` / `time  %.1fs` / `kills  %d` / `owned  %s` / `R to restart`。owned 空则为 `-`。不显示 loop / level / HP / 当前枪。Theme：`RunSummaryTitle` / `RunSummaryBody` / `RunSummaryHint` / `RunSummaryPanel`。禁止脚本 `StyleBoxFlat.new()`。

出现：`RunSession.is_player_dead()` 为 true 的那一帧或下一帧。弹窗若开着，现有 `_abort_offer` 先关窗清 pending，然后才显示。禁止等按键才弹出。消失：只有 R 走现有 `_reset_sandbox` 之后 hide。活着 playing 时必须 hidden。不锁镜头；已激活敌人继续走/打；结算条不再额外 `set_fire_suppressed`。

击杀计数只活在 `RunSession`（`note_kill` / `get_kill_count`）。`CombatSandbox._on_enemy_defeated` 在 playing 且玩家未死的闸之后立刻 `note_kill()`，再 `add_xp`。`reward<=0` 也计击杀。`hold_in_reserve` / R / `_loop_phrases` 不算击杀。玩家已死后场上再死人：不 +kill、不加 XP。轮循环 **不清** kills / xp / level / owned。R：kills 随 `restart()` 归 0，条自己藏。U 不增加 kills。不要 CLEARED 结算。

HUD 仍四块（武器 / HP / XP / 句读），不要第五块 DEAD。Overlay 增补 `kills: %d`（在 loop 附近）。句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、UpgradeApplier、XP 公式都没改。

**当时不做：** 商店、主菜单、设置页。

## Day 20（已完成）：极简主菜单

启动先到 **极简主菜单**（`ui/main_menu.tscn`，`MainMenu`，根节点 `Control`，不是 CanvasLayer）。点 Play 才进现有 `sandbox/combat_sandbox.tscn`。死亡仍用 Day 19 结算条。R 仍是沙盒内整局重置，**不是**回菜单。禁止 `get_tree().paused`、禁止 `PROCESS_MODE_ALWAYS`、禁止 Autoload 传开局参数、禁止背景图 / sway / emoji、禁止把 CombatSandbox 做成菜单子节点。

居中 VBox：Title `WPG`、Play、Quit。Play / Quit 是 Button（`custom_minimum_size=Vector2(280, 56)`，`mouse_filter=STOP`）。空背景 `mouse_filter=IGNORE`。背景一块 `ColorRect` `Color(0.10, 0.10, 0.12, 1)`。Play → `change_scene_to_file("res://sandbox/combat_sandbox.tscn")`。Quit → `get_tree().quit()`。`_ready` 里 `Play.grab_focus()`，`Input.mouse_mode = MOUSE_MODE_VISIBLE`。键盘走引擎默认 `ui_accept`（Enter/Space）= 点 Play；不要把 `ui_accept` / `ui_cancel` 写进 `project.godot` `[input]`。Theme：`MenuTitle` / `MainMenuButton`（复用 OfferButton 的 styles；Godot 内置 `MenuButton` 控件，不能当 type variation）。禁止脚本 `StyleBoxFlat.new()`。

`project.godot` 主场景改成 `res://ui/main_menu.tscn`。Autoload 仍是 0。菜单没有 DebugOverlay / HUD / 30 个敌人。

从战斗回菜单（当时只允许 **死后**）：`CombatSandbox` 在 `ui_cancel`（Esc）且 `is_player_dead()` 时 `change_scene_to_file(MENU_SCENE)`。playing / 弹窗开着 / 人还活着时 Esc 当时什么都不做。回菜单不要先 `park_all`。R 路径禁止 `change_scene`，仍走 `_reset_sandbox`。结算条 Hint 两行：`R to restart` / `Esc menu`。Play 进沙盒后行为与以前 F5 直进相同（`_bind_runtime` 里已有 `restart`）。

**当时不做：** 商店、设置页、活着按 Esc 回菜单。

## Day 21（已完成）：活着按 Esc 也回菜单

沙盒内按 **Esc**（引擎默认 `ui_cancel`），**无论活着还是已死**，立刻 `change_scene_to_file(MENU_SCENE)` 回主菜单。本局丢弃。不要暂停确认框。禁止 `get_tree().paused`、禁止 `Engine.time_scale`、禁止 `PROCESS_MODE_ALWAYS`、禁止新 CanvasLayer 暂停壳、禁止 AcceptDialog / ConfirmationDialog。不要把 `ui_cancel` / `ui_accept` 写入 `project.godot` `[input]`。

离场合同：

1. playing（含 P0 rest、句中、P8 后 loop 空窗）→ Esc 回菜单
2. 三选一开着（句间或升级）→ Esc 回菜单；**不** `try_grant`、**不** `acknowledge_offer`、**不** `consume_pending_level`。卸场景即可
3. 已死、结算条可见 → Esc 回菜单（Day 20 已有，本阶段删掉 `is_player_dead()` 闸）
4. 回菜单不要先 `park_all` / `hold_in_reserve` / `RunSession.restart`；卸场景即可。`_exit_tree` 已把鼠标设回 VISIBLE

`CombatSandbox._unhandled_input` 顺序锁死：`ui_cancel` → `sandbox_reset` → `debug_grant_upgrade`。Esc 前不要 `close_offer` / `_abort_offer`。R 仍走 `_reset_sandbox`，禁止 `change_scene`。Esc 与 R 不是同一条路。UpgradeOffer 不监听 `ui_cancel`（冒泡到沙盒）。HUD 仍四块，不加第五块。活着时中央不加提示。结算条 Hint 仍两行。Overlay：`reset: R` 下一行 `esc: menu`。菜单本身不改：Esc 不退出进程，点 Quit 才退出。再 Play 是新的一局（新加载 CombatSandbox，`_bind_runtime` 里已有 `restart`）。

句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、XP 公式、MainMenu 布局、`MenuTitle` / `MainMenuButton` 都没改。

**当时不做：** 商店、设置页、暂停确认框、轮循环加压。

## Day 22（已完成）：轮循环加压

P8 后再开一轮时，**同一批 30 节点**按 `loop_index` 变厚：更高 HP、更快移速、更短 P0 rest。不是新敌人，不是商店波，不是 SpawnBudget。禁止改近战/远程 `_ready` 身份赋值行（36/175/28/140 仍是唯一底值源）。禁止在当前 `max_hp` 上 `+=`。加压只打敌人耐久、走近速度、轮间空窗。不要改 contact_damage / projectile_damage / fire_interval / knockback / XP 奖励（仍 10/12）/ 玩家 Motor / 枪 / HP。

加压公式（`pressure = mini(get_loop_index(), 8)`）：

| | loop0 | loop1 | loop2 |
|---|---|---|---|
| 近战 max_hp | 36 | 44 | 52 |
| 远程 max_hp | 28 | 34 | 40 |
| 近战 move_speed | 175 | 189 | 203 |
| 远程 move_speed | 140 | 151.2 | 162.4 |
| P0 rest | 1.50 | 1.25 | 1.00（loop3 起钳 0.75） |

`EnemyBase._ready` 在子类写好身份并 `super._ready()` 之后采集 `_base_max_hp` / `_base_move_speed`。`apply_loop_pressure` 用底值重算。`MeleeEnemy.get_hp_per_loop()` 返回 8，`RangedEnemy` 返回 6。预备役里不改 `_hp`；入场 `reset_for_sandbox` 把 `_hp` 灌到新 `max_hp`。

调度顺序锁死：

1. `_loop_phrases`：`park_all` 两池 → `hold_all_in_reserve` → `notify_phrase_loop()`（先 +1）→ `_apply_loop_pressure()` → `EncounterPhrases.restart()`
2. `_reset_sandbox`：`RunSession.restart()` 已把 loop 清 0 之后、hold 之后、`encounter.restart` 之前，再 `_apply_loop_pressure()`
3. `_bind_runtime` 开局：`restart` + hold 之后同样 apply 一次（pressure=0，写回底值）

`EncounterPhrases.bind_run_session`；`REST_SEC` 保持 1.5；index==0 的 rest 用 `_rest_sec()` = `maxf(0.75, 1.5 - 0.25 * pressure)`。P2/P4/P6 仍是 `AWAITING_OFFER`，不缩短。HUD 仍四块，顶中仍是 `get_phrase_label()`。Overlay：`rest_sec` / `nearest_spd`。Esc / R 合同不改；轮循环仍不清 owned / HP / XP / kills。

句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、近战远程 `_ready` 身份行、XP 公式、MainMenu、RunSummary 文案都没改。

**当时不做：** 商店、SpawnBudget、HUD 第五块 LOOP、暂停框。

## Day 23（已完成）：顶中 phrase 旁显示 loop

玩家不看 Overlay 也能知道自己在第几轮。HUD **顶中** 同一块 `PhraseLabel` 拼上 loop：`L%d  %s` % [`RunSession.get_loop_index()`, `EncounterPhrases.get_phrase_label()`]。loop 与 Overlay `loop: %d` 同一套，**0 起**。禁止改 `get_phrase_label()` 的返回字符串。不要新 Label、不要第五信息区、不要 ROUND 横幅、不要 WAVE COMPLETE。

显示合同：

- 开局：`L0  0/8`
- P1：`L0  1/8`
- 句间三选一：`L0  offer`（`get_phrase_label` 仍是 `offer`）
- P8 闪帧：`L0  phrases_done`
- 第一次 `_loop_phrases` 后的 P0：`L1  0/8`
- 第二轮 P1：`L1  1/8`

`PhraseLabel` 加宽到 `offset_left=-280` / `offset_right=280`，`pivot_offset=Vector2(280, 20)`，锚点仍顶中 preset 5，`mouse_filter` 仍 IGNORE。左下三行（武器 / HP / XP）不动。Overlay `loop: %d` 保留。RunSummary 本阶段不加 loop 行。R：立刻 `L0  0/8`。Esc 回菜单再 Play：新局 `L0  0/8`。死后顶中仍显示当时的 `L%d  %s`。

句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、近战远程 `_ready` 身份行、XP 公式、加压公式、MainMenu、RunSummary 文案都没改。

**当时不做：** 商店、SpawnBudget、结算条 loop 行、暂停框。

## Day 24（已完成）：结算条补一行 loop

死后结算条在 `time` 和 `kills` 之间补一行 **`loop  %d`**，与 Overlay / HUD 顶中同一套 `RunSession.get_loop_index()`，**0 起**。禁止写成 `L%d`（那是 HUD 顶中格式）。节点名 `LoopLabel`，`theme_type_variation` 仍 `RunSummaryBody`，`mouse_filter=IGNORE`。场景顺序：Title → TimeLabel → LoopLabel → KillsLabel → OwnedLabel → Hint → MenuHint。Panel `custom_minimum_size=Vector2(640, 208)`。不要全屏、不要 Dimmer、不要 Button。Hint 两行文案不变。

第一轮内死亡：`loop  0`。打完一遍 P8 进入 L1 再死：`loop  1`。活着 playing 时条仍 hidden。R：`restart` 把 loop 清 0，条因未死自己藏。Esc 回菜单再 Play：新局 loop 0。

HUD 信息架构到此冻结：左下武器/HP/XP，顶中 `L%d  %s`，layer 15 结算含 loop，layer 20 三选一。Overlay `loop: %d` 保留。不要给结算条加 level / HP / 当前枪。

句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、近战远程 `_ready` 身份行、XP 公式、加压 HP/移速/rest、HUD 顶中格式都没改。

**当时不做：** 商店、SpawnBudget、加压补伤害、暂停框、第五块 ROUND。

## Day 25（已完成）：加压补伤害

第二轮起近战贴脸更疼、远程弹更疼。同一批 30 节点，同一套 `pressure = clampi(get_loop_index(), 0, 8)`。不是新敌人，不是 SpawnBudget，不是改射速。禁止改近战/远程 `_ready` 身份赋值行。禁止在当前伤害值上 `+=`。`_base_contact_damage` / `_base_projectile_damage` 在 `_ready` 里从导出默认采集（8 和 6）。

| | loop0 | loop1 | loop2 | loop8 |
|---|---|---|---|---|
| 近战 contact_damage | 8 | 10 | 12 | 24 |
| 远程 projectile_damage | 6 | 7 | 8 | 14 |

近战：`contact_damage = _base_contact_damage + pressure * 2`（`get_contact_damage_per_loop()` 返回 2）。
远程：`projectile_damage = _base_projectile_damage + pressure * 1`（`get_projectile_damage_per_loop()` 返回 1）。

`EnemyBase.apply_loop_pressure` 在 HP/移速两行之后调用 `_apply_damage_pressure(pressure)`；基类空实现。预备役里只改字段、不造成伤害。入场 `reset_for_sandbox` 不重置伤害字段。`_try_hit_player` 仍读 `contact_damage`；`_try_fire` 仍把 `projectile_damage` 传进 `projectile.reset`。

Overlay：`nearest_spd` 旁加 `nearest_dmg: %d`（近战读 `contact_damage`，远程读 `projectile_damage`，没有 nearest 则 0）。不要改 loop/kills 格式。HUD / 结算条 / 顶中 `L%d  %s` 不动。不要第五块 DMG。

R：loop 0，伤害回 8/6。Esc 回菜单再 Play：新局 8/6。HP/移速/rest 仍走 Day 22 公式（近战 loop1：44 HP、175*1.08）。`fire_interval=0.9`、`projectile_speed=420`、knockback、XP 10/12、玩家 `i_frame_sec=0.45` 都没改。

调度顺序未动：`_loop_phrases` 仍是 park → hold → `notify_phrase_loop()`（先 +1）→ `_apply_loop_pressure()` → `EncounterPhrases.restart()`。

句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、近战远程 `_ready` 身份行、XP 公式、加压 HP/移速/rest、HUD 顶中/结算条都没改。

**当时不做：** 商店、SpawnBudget、句读加厚、暂停框、第五块 ROUND、多人、模式选择。

## Day 26（已完成）：句读加厚

第二轮起场上更密。仍是同一批 30 个预放节点、仍 P0–P8、仍按节点名 `activate`。不是新敌人，不是 SpawnBudget，不是改伤害。密度两档：`loop == 0` 瘦表一字不改；`loop >= 1` 走 `_DENSE`。禁止第三套 `loop≥2` 表。`PHRASE_TOTAL` 仍是 8。`get_phrase_label()` 返回字符串一个字都没改。顶中仍 `L0  1/8` / `L1  1/8`。

| | loop0 | loop≥1 |
|---|---|---|
| P1 | Left1..4（4） | Left1..6（6） |
| P3 | Right1..3（3） | Right1..4（4） |
| P5 | Bottom1..6 + Top1..2（8） | Bottom1..8 + Top1..3（11） |
| P7 | Left5-10 + Bottom7-10 + Right4-6 + Top3-4（15） | Left7-10 + Bottom9-10 + Right5-6 + Top4（9） |
| P3 重叠 | P1 活着 ≤2 且 >0 | P1 活着 ≤3 且 >0 |

调度仍走 `_begin_phrase`：0/2/4/6 rest 或 offer；1 用 `_p1_names()`；3 用 `_start_p3`；5 用 `_p5_names()`；7 用 `_p7_names()` 且 wait 空数组、清场靠 `_count_field_alive()`；8 DONE。`_start_playing` / `_start_p3` / `_try_overlap_p3` 全部读 getter，不再直接写 `P1_NAMES`。`_p3_overlap_max()`：loop==0 返回 2，否则返回 3。密度每次读 `RunSession.get_loop_index()`，不缓存一份 loop。

禁止用密度跳过更多三选一。P2/P4/P6 仍是 `AWAITING_OFFER`（P2 仅当 `_p3_started` 才跳过）。不要 P5 重叠进 P3，不要 P7 重叠进 P5。并发上限仍靠手写表：loop≥1 峰值大约 P5=11 或 P1 重叠 P3=3+4=7，不是开局 20M+10R。

HUD / 结算条 / Overlay 格式不动。`phrase_alive` 会自然变大（P1：loop0 起 4，loop≥1 起 6），不要新字段、不要第五块 WAVE。R：restart 回 P0，loop 0，用瘦表。Esc 回菜单再 Play：新局瘦表。`_loop_phrases` 已先 notify 再 `encounter.restart()`，第二轮第一句就会走 DENSE。节点名和坐标没改，不 `instantiate`、不 `queue_free`。

句读节点名 P0–P8、10 张卡、三把枪 `_ready` 身份、Motor/相机/击退/hitstop、近战远程 `_ready` 身份行、XP 公式、加压 HP/移速/rest/伤害、HUD 顶中/结算条都没改。

**当时不做：** 商店、WaveDirector、10 张卡改手感、暂停框、第五块 ROUND、多人、模式选择。

## Day 27（已完成）：10 张卡补手感

无限轮打下去时卡还值得拿。id / Kind / title 全部锁死，catalog 仍 10 条。禁止新 `.tres`、禁止删卡、禁止改 `UpgradeDef` enum。同一扇 UpgradeOffer，不要刷新、不要权重。

| id | 改什么 |
|---|---|
| max_hp_s | stackable **true**（value 仍 20，description 仍 "Max HP +20"） |
| extra_pellets | stackable **true**（value 仍 2，description 仍 "Shotgun pellets +2"） |
| swift | value **0.12**，description **"Move speed +12%"** |
| heavy_round | value **3**，description **"Damage +3"** |
| cadence | value **0.15**，description **"Fire rate +15%"** |
| long_shot | 不动（80 / stackable） |
| max_hp_m | 不动（40 / unique） |
| second_skin | 不动（0.10 / unique，禁止改成 stackable） |
| steady_rifle | 不动（-2.0 / unique） |
| thick_hide | 不动（-0.20 / unique） |

可叠 6 张：`max_hp_s` / `swift` / `heavy_round` / `cadence` / `long_shot` / `extra_pellets`。unique 仍 4 张。`UpgradeApplier.MAX_PELLETS = 14`；霰弹 `pellet_count = clampi(base + flat, MIN_PELLETS, MAX_PELLETS)`。底值 8，叠三次到 14，第四次 `extra_pellets` 仍可进三选一但粒数停在 14。不要从 `draft_offer` 里按叠次过滤。

U 仍只授 `max_hp_s`，现在可叠，连按会多次 +20。三把枪 `_ready` 底值没改。重算公式除霰弹钳上限外不动。HUD / 结算条 / Overlay `catalog: 10` 不动。owned 出现重复 id 是对的。R：owned 清空，底值写回，粒数回 8。Esc 回菜单再 Play：新局空 owned。

句读节点名 P0–P8、加压 HP/移速/rest/伤害、Motor/相机/击退/hitstop、近战远程 `_ready` 身份行、XP 公式、HUD 顶中/结算条都没改。

**当时不做：** 商店、WaveDirector、第四把枪、暂停框、第五块 ROUND、多人、模式选择。

## Day 28（已完成）：第四把枪 Smg

一局里多一种开火手感。HUD 仍一行枪名。玩家是持枪野猪，不是猎人。橙三角剪影本阶段不重画。

`weapons/smg.gd`，`class_name Smg`，节点名 `Smg`，挂在 `player.tscn` 的 WeaponHost 下、Rifle 后面（index 3）。`get_display_name()` 返回 **"Smg"**。

`_ready` 身份（唯一底值源，tscn 不覆盖这四项）：`fire_interval = 0.07`、`projectile_speed = 880.0`、`damage = 4`、`lifetime = 0.65`。1 粒；固定散布 9°（`_spread_deg_for_this_shot` 返回 9.0，不要步枪那套 current_spread 累积）；`_should_reset_cooldown_on_release()` 返回 false（按住连扫，松开不复位）。镜头踢 4 / 后坐 3 / 枪口闪光 0.04s。禁止第 5 把、弹药、换弹、过热条。

切枪：`project.godot` 只加 `weapon_smg`，物理键 **4**。`WeaponHost._poll_weapon_switch` 在 rifle 之后 `_activate_index(3)`。切枪仍不进 `move/aim/fire_held`。不要滚轮、不要 Q/E。三选一 `UpgradeOffer._input` **不读** `weapon_smg`；1/2/3 选卡合同一字不改。弹窗开着时 4 不会选第四张（没有第四张）。

HUD 仍 `get_current_weapon().get_display_name()`。切到 Smg 左下显示 `Smg`。不要第二行、不要 4 个槽。Overlay `weapon` / `spread_deg≈9` / `pellets=1` 自然跟着走。

`SfxPool.play_weapon`：Rifle 判断之后、默认手枪之前走 `play_smg`。复用已有 `_stream_rifle`，pitch `1.12~1.22`，volume_db **-11.0**。禁止新 wav。

`UpgradeApplier` 不为 Smg 加专属合计。`get_weapons()` 顺序变成 4 把，`capture_baseline` 多采一行。Heavy Round / Cadence / Long Shot 通用伤/射速/弹速 Smg 也吃；Extra Pellets / Steady Rifle 仍只打霰弹/步枪。玩家弹池仍 96。

R：仍 activate 当前 index（包括 3）。Esc 回菜单再 Play：WeaponHost 仍从 0 手枪起。橙灰盒 Polygon2D 顶点/颜色没改。

三把枪 `_ready` 身份底值没改。句读、加压、10 张卡、HUD 顶中/结算条都没改。

**本阶段不做：** 商店、WaveDirector、玩家剪影重画、暂停框、第五块 ROUND、五格枪架、多人、局域网房间。

## 明确不做（直到后续对应日）

- **Day 29 才做** 商店先不做具体货架，除非明确缺「构筑变厚」；若还不缺商店，则 Day 29 改成 **玩家野猪灰盒剪影**（耳朵/鼻子比例，仍不是原画）。仍无商店刷新、无 WaveDirector、无暂停框、无五格枪架、无多人、无局域网房间
- 死亡碎裂粒子、掉落物、精英/Boss、敌人对象池、EnemyManager
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
- Motor **只读** `move_vector`；相机 / 准星 **只读** `aim_vector` 与 `mouse_world_position`；当前武器 **只读** `fire_held` 与 `aim_vector`。禁止武器自己 `is_action_pressed("fire")`
- 切枪 1/2/3/4 由 `WeaponHost` 读取，不塞进输入合同三量；弹窗打开时 1/2/3 改语义为选左/中/右卡，4 不选卡
- 沙盒重置 `R`（`sandbox_reset`）由 `CombatSandbox` 读取，不塞进输入合同三量
- 沙盒 Esc（`ui_cancel`，引擎默认，不写入 `project.godot`）由 `CombatSandbox` 读取，无论死活都卸场景回菜单；不塞进输入合同三量
- 调试授予 `U`（`debug_grant_upgrade`）由 `CombatSandbox` 读取，不塞进输入合同三量；只授 `max_hp_s`

手机双摇杆是后续阶段；不要做 Input Autoload。输入组件挂在玩家节点上。

## 禁止事项（旧作不要带进新仓库）

- 自动锁最近敌人；没目标就 `return`；PC 自动开火；手机「自动射击」开关；桌面虚拟摇杆
- 子弹从身体/武器节点中心出，而不是枪口
- 用 Timer 节点做射速；等下一个 timeout 才出第一发
- 把弹池做成 Autoload；每发 `instantiate`/`queue_free`；池满删天上的弹
- 每帧 `get_tree().get_nodes_in_group("player")`；每敌 NavigationAgent / raycast / `queue_redraw`；满员删最老敌人
- `reload_current_scene()` 当沙盒重置；WaveDirector / EnemyManager；四边随机下雨刷怪
- 把 `Camera2D` 死挂在 Player 上，再用 Tween 随机 `offset` 当震动
- 随机 `Vector2(rand, rand)` 当镜头震动；用 `Engine.time_scale` 给震屏配慢动作
- Autoload 音频栈 / 每发 `new AudioStreamPlayer`
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
player/     玩家场景、PlayerInput、PlayerMotor、PlayerHealth、Muzzle、WeaponHost、FireFeedback
weapons/    Weapon 薄基类、Pistol / Shotgun / Rifle / Smg、Projectile、本局 ProjectilePool
enemies/    EnemyBase、MeleeEnemy、RangedEnemy；DummyTarget 脚本保留但沙盒不再放置
combat/     碰撞层常量、DamageNumber、HitReaction、MuzzleFlash、HitSpark、SfxPool
audio/      程序生成短 WAV（手枪/霰弹/步枪/命中/击杀/受伤/拒发/敌人弹）
arena/      EncounterPhrases 手写句读（P0–P8）+ 本局节点 RunSession + UpgradeApplier；不是 Autoload RunState / WaveDirector
camera/     PlayerCamera、AimReticle
ui/         MainMenu（F5 主场景）+ Hud + UpgradeOffer + RunSummary + game_theme.tres（左下 HP+武器+XP，顶中 `L0  0/8`；句间/升级三选一 layer=20；死亡结算条 layer=15 含 loop）；DebugOverlay 仍在 debug/
data/       UpgradeDef + UpgradeCatalog.tres + data/upgrades/ 10 条；升级是数据不是效果
debug/      DebugOverlay
sandbox/    CombatSandbox（Play 后进入；Player / PlayerCamera / AimReticle / Projectiles / EnemyProjectiles / SfxPool / Enemies / EncounterPhrases / RunSession / UpgradeApplier / Hud / UpgradeOffer / RunSummary / DebugOverlay）
```

## 碰撞层

| 层 | 名称 | Day 6–11 用法 |
|---|---|---|
| 1 | player | 玩家只撞墙，不跟敌人刚体互推 |
| 2 | enemy | 近战/远程；mask = wall；不挡玩家移动 |
| 3 | player_bullet | 玩家弹；mask = enemy + wall |
| 4 | enemy_bullet | 敌人弹；mask = player + wall |
| 5 | wall | 灰盒围墙 |

脚本一律走 `GameCollisionLayers`，禁止写裸数字 `1/2/4/8`。

## 下一步：Day 29

**Day 29 = 商店先不做具体货架，除非明确缺「构筑变厚」；若还不缺商店，则改成玩家野猪灰盒剪影**（耳朵/鼻子比例，仍不是原画）。仍无商店刷新、无 WaveDirector、无暂停框、无五格枪架、无多人、无局域网房间。
