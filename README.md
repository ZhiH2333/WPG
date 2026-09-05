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

**本阶段不做：** 升级 Resource、三选一弹窗、XP、商店、死亡结算屏。

## 明确不做（直到后续对应日）

- **Day 14 才做**10 个升级 Resource 定义；RunSession 可持有已选 id 列表但本阶段恒空、不改枪/HP。仍无三选一弹窗、无 XP、无商店
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
- 切枪 1/2/3 由 `WeaponHost` 读取，不塞进输入合同三量
- 沙盒重置 `R`（`sandbox_reset`）由 `CombatSandbox` 读取，不塞进输入合同三量

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
weapons/    Weapon 薄基类、Pistol / Shotgun / Rifle、Projectile、本局 ProjectilePool
enemies/    EnemyBase、MeleeEnemy、RangedEnemy；DummyTarget 脚本保留但沙盒不再放置
combat/     碰撞层常量、DamageNumber、HitReaction、MuzzleFlash、HitSpark、SfxPool
audio/      程序生成短 WAV（手枪/霰弹/步枪/命中/击杀/受伤/拒发/敌人弹）
arena/      EncounterPhrases 手写句读（P0–P8）+ 本局节点 RunSession；不是 Autoload RunState / WaveDirector
camera/     PlayerCamera、AimReticle
ui/         Hud + game_theme.tres（左下 HP+武器，顶中句读）；DebugOverlay 仍在 debug/
data/       武器/敌人/升级 Resource（尚未开始）
debug/      DebugOverlay
sandbox/    主场景（Player / PlayerCamera / AimReticle / Projectiles / EnemyProjectiles / SfxPool / Enemies / EncounterPhrases / RunSession / Hud / DebugOverlay）
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

## 下一步：Day 14

**Day 14 = 10 个升级 Resource 定义。** RunSession 可持有已选 id 列表，但本阶段恒空、不改枪/HP。仍无三选一弹窗，无 XP，无商店，无第四把枪。
