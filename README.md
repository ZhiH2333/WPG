# WPG

这是一次**架构重写**，不是把旧作 Wild-Pig-Gun 再抄一遍。

保留俯视射击肉鸽的设计方向（波次、构筑、商店），但战斗运行时、输入、反馈和 UI 全部重写。卖点是**打起来有重量**：瞄准、走位、后坐、打空、换弹节拍。不要功能清单比旧作更长。

**玩家是持枪野猪。** 橙灰盒 Player 就是这头猪，枪的幻想是「猪拿枪乱打」，不是猎人进场打野猪。敌人仍是近战/远程两种体型（红三角 / 紫远程），不要改成「猎人」、不要把敌人改名成 pig。注释和文档禁止写成「猎人」「打猪」。

当前仓库从空白 Godot 4.6 工程起步。旧作只允许对照设计，禁止移植其 Autoload、UI 缩放器、自动锁敌开火、云存档、账号、图鉴。

## 怎么运行

用 Godot **4.6** 打开本仓库，按 F5。主场景是 `ui/main_menu.tscn`：全屏背景图 + 主题音乐，中央上方是 `images/logo.png` 字标，下方 Settings / Play / Exit 三颗平行四边形按钮并排。点 Logo 或 Play 弹出 SOLO / MULTI 两张卡（ModeChoiceOverlay，不记上次选择）。SOLO 进档位大面板；MULTI 进局域网大面板。顶栏 Home 右边成对放 SOLO / MULTI，跳过 Mode Choice 直达。空档时只有 “+ New Record”；点已有档直接进沙盒（读该档 arena_id，不再弹选图）；新建档时选野猪/野鸡、Yard/Pit/Keep 和 loop 目标（滑杆 0=Inf，默认 Yard / 20）。Host Custom 可选图；借档锁定角色、loop_goal 和地图，联机不写盘；Join 仍自选角色、不能选图，端口 17777，协议 4。Host 在 Arenas 与 LoopRow 之间选 Co-op / Battle；Battle 关句读/商店/跟班，玩家弹打得到对方，联机仍不写档。任何叠层打开时背景模糊压暗、音乐衰减。Esc 在编辑态先回列表，列表再关叠层。点顶栏头像弹出 PROFILE（best / last / runs）。沙盒里活着且没有三选一/商店时 Esc 打开暂停（Continue / Retry / Quit）；死了或通关弹出 WinnerPage（分数拆解逐行滚出 + 本档 Top 10 + Retry / Menu），Esc / Menu 回主菜单。点已有档进沙盒或结算/暂停 Quit 回菜单时，当前曲先 0.45s 淡出再切场景，进场曲再淡入；Retry 不停 war.mp3。关掉游戏还记得 `user://progress.cfg` 里的 best loop；局末还会往 `user://records.json` 记档位 history，但 Profile 仍只读 progress.cfg。每局永远新开，不续打。`settings.cfg` 仍只有音量/全屏。不插手柄时 WASD + 鼠标瞄准开火，空格短冲刺；插一把手柄则左杆走、右杆瞄、扳机开火、A 冲刺。

- 平台：Desktop 为主（同一套战斗规则；**手机触控整包后置到内容/壳/美术/局域网都做完之后**，现在不要做双摇杆）
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
- 命中火花：接触点沿 `-hit` 微喷，当时 0.08s `queue_free`（Day 44 改为本局池 64）。墙和肉都可以。不是 GPUParticles。
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
- **Gated 修复（当时一项都没做）。** 禁止「顺便」上 AI 分频。当时未做火花/数字池、未做偶数/奇数物理帧跳过 `_tick_ai`、未建 EnemyManager、未改 `physics_ticks_per_second`、未改 `time_scale`。火花池化挪到 Day 44。尸体仍 `set_physics_process(false)` 留场。R 重置同一批 30 个节点，禁止 `reload_current_scene()`。

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

**当时不做：** 商店、WaveDirector、玩家剪影重画、暂停框、第五块 ROUND、五格枪架、多人、局域网房间。

## Day 29（已完成）：P5 近战精英

一局里多一个高潮目标。仍手写节点名，不是商店，不是剪影日，不是第三种 AI。玩家野猪保持橙三角，美术后置；三角形一直留到接 sprite。敌人仍是红三角近战 / 紫远程，精英也仍是**放大的红三角**，不要画成猎人。

`enemies/elite_melee.gd`，`class_name EliteMelee`，**extends MeleeEnemy**（复用接触伤 / ContactArea）。场景结构抄近战：CharacterBody2D + CollisionShape2D + Visual Polygon2D + ContactArea。沙盒节点名 **EliteBottom1**，`parent=Enemies`，`position=Vector2(0, 400)`（下侧，y=400 > 300 走 bottom；距玩家 ≥400）。不要运行时 `instantiate`。

仍是三角形，只放大、换色：polygon 与近战相同；`Visual.scale = Vector2(1.75, 1.75)`；`Visual.color = Color(0.62, 0.08, 0.10, 1)`；身体半径 28，接触半径 44。禁止 Sprite2D、禁止第二层耳朵。

身份在 `super._ready()` **之后**重写并回写 base（近战 `_ready` 那三行 36/175/1400 不改）：`max_hp=90`、`move_speed=120`、`acceleration=1000`、`knockback_impulse=140`、`contact_damage=14`，然后 `_base_max_hp` / `_base_move_speed` / `_base_contact_damage` / `_hp` 写回。`get_kind_name()="Elite"`，`get_xp_reward()=25`，`get_hp_per_loop()=12`，`get_contact_damage_per_loop()=3`。

加压沿用 `apply_loop_pressure`：loop0 HP90 / 速120 / 接触14；loop1 102 / 129.6 / 17；loop2 114 / 139.2 / 20。

句读：`P5_NAMES` 与 `P5_NAMES_DENSE` **末尾**加 `EliteBottom1`。P1/P3/P7 瘦表和 DENSE 一字不改。`PHRASE_TOTAL` 仍 8。P2/P4/P6 仍三选一。不要把精英放进 P7。人数：loop0 P5=9（6 近战 + 2 远程 + 1 精英）；loop≥1 P5=12。并发仍 ≤12。第一轮 P1 仍 4 只普通近战。

HUD 不加 Boss 条。顶中仍 `L0  5/8`。Overlay 不新字段；靠近精英 `Elite 90`；alive summary 把精英算进 M。预备役 / R / `_loop_phrases` 走同一套 hold。玩家多边形、四把枪 `_ready`、10 张卡都没改。

**当时不做：** 商店、金币、WaveDirector、设置页、暂停框、Boss 条、五格枪架、玩家剪影、多人、局域网房间。

## Day 30（已完成）：主菜单 Settings 叠层

菜单能调 **Master 音量** 和 **全屏**，写到磁盘，战斗场景启动时套用。不是商店，不是顶栏，不是暂停框。战斗 HUD 锚点未改。

`ui/game_settings.gd`，`class_name GameSettings`，`extends Object`，全是 static。不是 Autoload，不要 Node、不要 signal、不要 `get_tree()`。路径 `user://settings.cfg`（ConfigFile）：节 `[audio]` 键 `volume` float 0.0–1.0，默认 **1.0**；节 `[display]` 键 `fullscreen` bool，默认 **false**。缺文件或缺键用默认，不 `push_error`。

接口：`load_from_disk` / `save_to_disk` / `apply` / `get_volume` / `set_volume`（clamp 0..1，不自动 save）/ `is_fullscreen` / `set_fullscreen`。`apply`：`bus = AudioServer.get_bus_index("Master")`；volume≤0.001 则 mute，否则 unmute + `linear_to_db`。全屏 `WINDOW_MODE_FULLSCREEN`，关则 `WINDOW_MODE_WINDOWED`。不要 EXCLUSIVE、不要改 viewport / stretch。不要改 SfxPool 每发 `volume_db`，Master 缩放全部 SFX。

`ui/settings_overlay.tscn` 是 MainMenu 子 Control，与 Center 平级盖在上面。不是独立主场景，不是战斗 CanvasLayer。Play 仍 `change_scene_to_file(SANDBOX_SCENE)`。Dimmer `Color(0,0,0,0.55)`；左侧栏宽 72，A / D 两钮（OfferButton）；右侧 Audio 页 Volume + HSlider（0..1 step 0.01）；Display 页 CheckBox `Fullscreen`；底左 Back。切 A/D 只换右页。visible 开关，禁止 Tween / AnimationPlayer。

滑条 `value_changed` 立刻 `set_volume` + apply 音量（可不 save）；`drag_ended` 或勾选时 `save_to_disk`。全屏勾选立刻 apply + save。预览：叠层上一个 `AudioStreamPlayer`，`drag_ended` 且 volume>0 时播 `res://audio/click.wav`（FileAccess 切片，学 SfxPool）。禁止每帧 play、禁止 new 播放器。

主菜单按钮顺序：Play → **Settings** → Quit。Settings 仍 `MainMenuButton`，`custom_minimum_size=Vector2(280, 56)`。叠层打开：`ui_accept` 不触发 Play；`ui_cancel` 关叠层、Play.grab_focus()。叠层关着 Esc 仍不 quit。战斗里 Esc 仍卸回菜单，不弹设置。MainMenu 与 CombatSandbox 的 `_ready` 都 `load_from_disk` + `apply`（F6 直进沙盒也生效）。

Theme 新增 `SettingsHeader`（font_size=22，HudPhrase 同系颜色）。不要脚本 `StyleBoxFlat.new()`。不要顶栏、不要键位页、不要 BGM 滑条。不要 C 页、不要 `virtual_sticks`。

**当时不做：** 商店、金币、WaveDirector、顶栏、暂停框、Boss 条、五格枪架、玩家剪影、多人、局域网房间、osu Tween、手柄层。

## Day 31（已完成）：手柄按 device_id 拆开

仍单人。左杆走、右杆瞄、扳机/RB 开火、十字键切枪。输入合同未改。不是 2P，不是触控，不是 Autoload，没把手柄写进 InputMap。没把手柄时键鼠和 Day 30 完全一样。

`PlayerInput` 用 `device_id`：`-1` = 键鼠，`>=0` = `Input.get_connected_joypads()` 里的 id。禁止把 Joypad 事件加进 `move_left` / `fire` / `weapon_*`。手柄只走 `get_joy_axis` / `is_joy_button_pressed`。`set_device_id` 留给 Day 34 钉死 P2；Day 31 不钉死，每帧自动认领。

后动者接管：WASD/方向键按下，或鼠标相对上一帧移动 ≥2px → 立刻键鼠。否则扫已连接手柄：左杆/右杆长度 ≥ 0.25，或右扳机 ≥ 0.45，或 RB/十字键按下 → 该 id 接管（多个同时动取列表里后出现的）。拔掉当前手柄：下一帧回到键鼠，`move_vector` 清零，aim 保持上一帧。

键鼠路径一字不改：`get_vector("move_left"... )`、鼠标世界坐标 aim、`fire` action、`_fire_suppressed` / `_need_fire_release`。手柄路径独占三量：左杆径向死区 0.25；右杆过死区才改 `aim_vector`（否则保持上一帧，零则 RIGHT）；`mouse_world_position = 玩家 + aim * 140`；开火 = 右扳机映射到 0..1 ≥ 0.45 或 `JOY_BUTTON_RIGHT_SHOULDER`。关卡时若扳机/RB 仍按着，必须 `_need_fire_release`。

切枪：键盘 1/2/3/4 仍由 `WeaponHost` 读现有 action。十字键只认当前 `_device_id`：左=手枪、上=霰弹、右=步枪、下=Smg。`get_weapon_slot_just_pressed()` 自己做边沿，0..3 否则 -1。`_switch_suppressed` / `_switch_locked` 仍生效。

三选一：键盘 1/2/3 不改。`UpgradeOffer.bind_player_input`；打开时槽 0/1/2 选卡，**下键（3）不选卡**。扳机在 offer lock 期间被 suppressed。

Start 与 Esc 相同回菜单。B 走引擎默认 `ui_cancel`。R / U 仍只认键盘。Overlay 多一行 `device: kbm` 或 `device: pad%d`。HUD 锚点未改。设置仍只有 A 音量 / D 全屏。`settings.cfg` 仍只有 audio.volume 与 display.fullscreen。禁止 TouchStick、禁止 Virtual Sticks、禁止设置 C 页。

**已知问题修复（2026-09-08 12:17）**：
1. **手柄无法移动 + 鼠标进窗口乱射**：鼠标窃取逻辑改为先检查 WASD，再检查鼠标真实移动（第一次进入窗口不触发）。设备切换时强制清空 `fire_held` 和 `_need_fire_release`，避免射击状态遗留
2. **corrupt.wav 导入错误**：在 `DesignReference/.gdignore` 标记该目录不被 Godot 导入
3. **调试工具**：战斗中按 **G** 显示手柄原始输入（摇杆、扳机、十字键、死区阈值）

**已知问题修复（2026-09-08 12:27）**：
1. **RT 短按/长按不分**：`_joy_wants_fire` 之前把扳机轴按摇杆的 `-1~1` 重新映射成 `(trigger+1)*0.5`，但 Godot 的 `JOY_AXIS_TRIGGER_RIGHT` 本身就是 `0`（松开）～`1`（扣到底）。松开时旧公式算出 `0.5`，已经超过 `FIRE_TRIGGER=0.45` 阈值，等于扳机常年“半按着”，短按/长按测不出来。现在直接读原始轴值，不再重新映射
2. **右摇杆瞄准瞬间掉头**：`_read_aim_stick` 之前直接把摇杆方向 `normalized()` 写进 `aim_vector`，方向反打时准星瞬间从一侧闪到另一侧。新增 `_turn_aim_toward`，用与相机跟随同一手法的指数缓动（`alpha = 1 - exp(-AIM_TURN_SMOOTHING * delta)`，`AIM_TURN_SMOOTHING=14`）把 `aim_vector` 的角度平滑转过去，而不是瞬间赋值。鼠标瞄准不受影响，仍然 1:1 跟手

**本阶段不做：** 商店、金币、顶栏、暂停框、Boss 条、五格枪架、玩家剪影、多人、分屏、局域网、osu Tween、触控、Virtual Sticks。


## Day 32（已完成）：本局金币 + P8 后商店

不是刷新店，不是 Autoload 钱包，不是掉落物。玩家打死人会攒钱，轮与轮之间能花掉。P2/P4/P6 三选一仍免费，不扣 gold。设置仍只有音量/全屏。金币不进 `settings.cfg`。

金币只活在 `RunSession`，和 XP 一样。`add_gold` 仅 playing 且 amount>0。`try_spend`：amount≤0 或不够则 false。`restart()` 把 `_gold` 清零。价格表只活在 `RunSession.SHOP_COSTS`：max_hp_s 25、max_hp_m 50、swift 30、heavy_round 30、cadence 30、long_shot 25、second_skin 45、extra_pellets 30、steady_rifle 30、thick_hide 30；找不到 id 则 30。不要改 10 个 `.tres` 的 value。

击杀：`CombatSandbox._on_enemy_defeated` 在 note_kill / add_xp **之后** `add_gold(enemy.get_gold_reward())`。XP 公式一字不改。`get_gold_reward`：EnemyBase 0、近战 3、远程 4、精英 **8**（EliteMelee 必须 override，否则会变成 3）。不要按 loop 加钱。没有金币实体、没有磁铁。

商店时机：改 `_loop_phrases`，**不要**立刻 `notify_phrase_loop`。顺序：park 两套弹 → hold 预备役 → **打开商店**（loop_index 仍是刚打完的那一轮）→ 买一张或 Skip → 关店 → 现有 `notify_phrase_loop` → `_apply_loop_pressure` → `encounter.restart`。0 张可上架则不弹窗，立刻走后面三步。上架复用 `draft_offer(3)`。每次最多买 1 张或 Skip。禁止刷新、禁止连买三张、禁止第三扇窗。

买：`get_gold()>=cost` → `try_grant` → `try_spend`；spend 失败 `push_error` 且不关店。Skip 不 grant、不 spend，关店并开下一轮。店开时走现有 `_set_offer_input_lock(true)`。U 在商店打开时无效。死亡则关店、不买、不 `notify_phrase_loop`。商店与 UpgradeOffer 互斥。

`ui/shop_offer.tscn`：Dimmer + 三张卡 + 标题 `SHOP` + `gold  %d` + Skip。layer=20。买不起的卡 `disabled=true`；1/2/3 或十字键 0/1/2 忽略该 index。Skip：鼠标、键盘 4、十字键下。不要 Tween。

HUD：BottomLeft 最下面 `GoldLabel`（`HudWeapon`，`gold  %d`）。`offset_top` -140 → **-176**。PhraseLabel 锚点一字不改。结算条 Kills 与 Owned 之间加 `gold  %d`，Panel 高 208 → 232。Overlay 加 `gold: %d`。主菜单不要商店钮。

`PlayerInput.set_fire_suppressed(false)`：若键鼠 fire 仍按下，或手柄 `_joy_wants_fire`，则 `_need_fire_release=true` 且 `fire_held=false`，关店不走火。device_id / 摇杆平滑未改。

**本阶段不做：** 刷新商店、第三扇窗、金币掉落、WAVE COMPLETE、顶栏、模式窗、暂停框、Boss 条、五格枪架、玩家剪影、多人、局域网、osu Tween、Virtual Sticks。

## Day 33（已完成）：点 Play 出模式窗

不是局域网周，不是 2P，不是顶栏。点 Play 不再立刻开打：标题还在，上面盖一层半透明，中央三张卡。Solo 与 Infinite 进入**同一个** `res://sandbox/combat_sandbox.tscn`（现有无限 loop 局）。Infinite 只是给这局一个名字，不要第二张地图、不要第二套刷怪、不要 loop 上限。Multi 看得见但 `disabled`，点不了，不要房间、不要「连接失败」。

`ui/mode_overlay.tscn` 是 MainMenu 子 Control，与 SettingsOverlay 平级、后声明盖在上面。不是独立主场景，不是战斗 CanvasLayer。禁止 Autoload，禁止 `LaunchIntent` / GameMode 静态单例，本阶段不传 mode 参数。

`ModeOverlay`：`is_open` / `open`（visible=true，Solo.grab_focus）/ `close`；信号只有 `selected_solo` 与 `selected_infinite`，没有 `selected_multi`。Dimmer `Color(0,0,0,0.55)`，`mouse_filter=STOP`。中央 HBox 三张 `OfferButton`，`custom_minimum_size=Vector2(240, 200)`，间距 24。文案锁死：Solo `The run you already know`；Infinite `Same loop. No extra map`；Multi `Coming later`（disabled，无 tooltip）。底左 Back。visible 开关，禁止 Tween / AnimationPlayer / 平行四边形。

MainMenu：`_on_play_pressed` 若 Settings 开着则 return，否则 `_mode_overlay.open()`。Solo / Infinite 都走 `_enter_sandbox()` → 现有 `change_scene_to_file(SANDBOX_SCENE)`。`ui_accept`：Settings 开着忽略；模式开着让按钮自己吃；两者都关才打开模式窗，**不要**直接进沙盒。`ui_cancel`：先关 Settings，否则关模式窗并 Play.grab_focus()；都关则不 quit。键盘 1=Solo、2=Infinite、3 忽略。十字键左/右只在 Solo 与 Infinite 之间换焦点（跳过 Multi）；A 确认；B / Start / Esc 关叠层。

CombatSandbox **未改**。HUD / 结算条 / 三选一 / 商店 / 四把枪 / 句读 / 加压 / gold 全部不动。没有顶栏、没有底栏三 icon。

Theme 新增 `ModeTitle`（font_size=26，HudPhrase 同系）。不要脚本 `StyleBoxFlat.new()`。

**本阶段不做：** 2P、房间、ENet、顶栏、底栏三 icon、osu Tween、每日挑战、Playlists、排行榜、LaunchIntent、Virtual Sticks。

## Day 34（已完成）：osu 式菜单壳 + 叠层非线性缓动

玩家打开游戏的第一眼开始像 osu：顶部一条瘦顶栏（Home / Settings）从上滑入，底部一条底栏（Play / Settings / Quit）从下滑入，中央 Title 与 Play 错峰淡入。点 Play，三张模式卡不再瞬间蹦出来，而是带 0.06s 错峰、OutBack 微缩放地「长」出来；打开 Settings，整块面板从左侧 OutQuint 滑入（520px，0.45s），Esc 关掉时滑回去。战斗里：升级三选一和商店的卡片同样错峰进场、快速淡出；血条和 XP 条不再瞬跳，而是指数缓动追目标；死亡结算面板缩放弹出。

新增 `ui/ui_anim.gd`（`UiAnim`，static 工具类，同 `GameSettings` 模式，非 Autoload）：进场 OutQuint / OutBack、退场 InQuint，透明度时长约为位移一半，错峰 0.06s——这三条就是 osu!lazer 的动效骨架。**动效只改装饰（modulate / scale / offset），`is_open()` 等逻辑开关仍瞬时生效**，输入锁、关店走火防抖、句间流程全部不受动画时长影响。每个叠层持有自己的 `_anim_tween`，重复开关先 `kill_tween` 再起新的，不会叠加。

菜单壳：`main_menu.tscn` 中央 Column 只剩 Title + Play；新增 `TopBar`（44px，Home / Settings）与 `BottomBar`（64px，Play / Settings / Quit），都是 `BarPanel` + `BarButton`（Theme 新增，styleboxes 全在 .tres，禁止脚本 `StyleBoxFlat.new()`）。Home 关掉一切叠层回到 Play 焦点。顶栏只在主菜单场景，**不进沙盒**；战斗 HUD 锚点一根没动，只有条值缓动。

卡片容器子级不能 tween `position`（HBox 会重排回去），所以卡片用 `modulate` + `scale`（pivot 取 `custom_minimum_size` 一半）；Settings Shell 是普通 Control 子级，滑动改 `offset_left/right`，布局安全。

**本阶段不做：** 2P、房间、ENet、Wiki/Chat/Profile、五格枪架、重排血条、每日挑战、排行榜、Virtual Sticks、手机触控。

## Day 35（已完成）：osu 式主题回炉

整套 Theme 回炉重做：所有 StyleBox 圆角化（卡片 16px、面板 18px、药丸按钮 27px），配色从橙灰换成 osu 粉紫系（主粉 `#FF66AB`、深梅紫底、蓝色 XP 条），卡片 hover 带粉色描边 + 粉色柔光阴影。主菜单彻底重排：底栏删掉，`images/mainmenu.png` 全屏铺满做背景，中央一颗 240px 粉色圆形 `wpg!` Logo（白描边 + 粉光晕，进场 OutBack 弹出），随后改成字标 `images/logo.png` 在上、Settings / Play / Exit 三颗平行四边形按钮并排在下。顶栏改成 osu toolbar：左设置/主页图标，右 Profile + 实时时钟。

`audio/main.mp3` 作为主题音乐循环播放；打开任何叠层时音乐从 -6dB 缓动衰减到 -16dB，同时 `ui/menu_blur.gdshader`（screen texture mip LOD 模糊 + 压暗，指数平滑追目标）把背景和 Logo 一起糊掉，叠层自身保持清晰，关掉后平滑恢复。osu 仓库里没有可用的 UI 音效（在独立的 osu-resources 包里），所以用脚本合成了三个同风格短音：`ui_hover.wav`（轻 tick）、`ui_click.wav`（软 pop，1500→850Hz 下滑）、`ui_back.wav`（低 pop），主菜单树里所有按钮统一接线：hover/focus 出 tick，确认出 click，Back / Home / Quit 出低 pop。

技术上仍守规矩：styleboxes 全在 `game_theme.tres`（新增 `LogoButton` / `PillPink` / `PillNeutral` / `PillRed` 变体与默认 `Button` 圆角样式），禁止脚本 `StyleBoxFlat.new()`；音乐衰减与模糊在 `_process` 里指数平滑，不依赖动画时长；`is_open()` 等逻辑开关仍瞬时生效，输入锁不受动画影响；无 Autoload，无暂停树。战斗侧只吃到主题红利（圆角血条 / 圆角卡片），HUD 锚点与玩法零改动。

**本阶段不做：** 正式战斗 sprite、字体替换、Logo 呼吸/节拍动画、视差背景、2P、房间、ENet、每日挑战、排行榜、Virtual Sticks、手机触控。

## 明确不做（直到后续对应日）

- **Day 42/43（已完成）= 接美术**：英文改名 + 朝向合同 + 主角/四枪/敌人换 sprite。**Day 44（已完成）= 地板 / 火花池 / 死亡碎裂 / 战斗 BGM**。**Day 45（已完成）= GameRecords / records.json**。**Day 46（已完成）= CharacterDef / 猪鸡底值**。**Day 47（已完成）= RecordSelector**。**Day 48（已完成）= WinnerPage v2**。**Day 49（已完成）= 局域网 2 客户端**。**Day 50（已完成）= 用现有档开 LAN**。同机分屏明确不做。下一步才是 Day 51 Profile + 可视化排行；5 人 / 房间浏览器仍后置。手机触控整包仍后置。仍无 4 张新卡、无 Boss 条、无五格枪架、无 Virtual Sticks、无 WaveDirector、无钱包、无中途续打
- GPUParticles2D 死亡粒子海、掉落物、敌人对象池、EnemyManager
- Arena 波次、中途续打、永久钱包
- 虚拟摇杆、触控、顶栏 Toolbar、键位重绑
- Web 导出妥协、C#、外部 ECS、任何 Autoload

## Day 36（已完成）：战斗暂停叠层

活着且三选一/商店都关着时，Esc（引擎默认 `ui_cancel`）或手柄 Start 打开 `PauseOverlay`（`ui/pause_overlay.tscn`，CanvasLayer layer=25，`PROCESS_MODE_ALWAYS`）。这是仓库里**唯一**允许 `get_tree().paused = true` 的地方。Continue / 再按 Esc / Start = 继续；Retry = `_reset_sandbox`（与 R 同一条路）然后关掉暂停；Quit = 先把 `paused` 解开再 `change_scene_to_file(MENU_SCENE)`。已死、三选一开着、商店开着时 Esc 仍立刻回菜单，本局丢弃，不走暂停。

三条平行四边形按钮沿用主菜单 shear：绿 Continue、橙 Retry、红 Quit。标题 `PAUSED`，底下 `loop / gold / kills`。进场 `UiAnim.enter_overlay(..., ignore_pause=true)`，退场 0.15s；逻辑上 open/close 仍瞬时生效。点击空白不继续。不要 AcceptDialog / ConfirmationDialog。不要把 `ui_cancel` / `ui_accept` 写入 `project.godot` `[input]`。暂停开着时 R / U 无效。开火和切枪被 `set_fire_suppressed` / `set_switch_suppressed` 锁住。离开沙盒时 `_exit_tree` 必须把 `paused` 解开，避免主菜单冻住。

禁止 `Engine.time_scale`。禁止第二个暂停壳。禁止暂停时句读/商店/升级继续推进。

**当时不做：** 存档、暂停里改设置、WaveDirector、Boss 条、五格枪架、玩家剪影、Virtual Sticks、接美术。

## Day 37（已完成）：跨局成绩

`ui/game_progress.gd`（`class_name GameProgress`，`extends Object`，全是 static）把成绩写到 `user://progress.cfg`。不是 Autoload，不是 Node，禁止 `get_tree()`，禁止信号总线。不要把进度塞进 `RunSession`（那是本局节点）。不要写进 `settings.cfg`。

节与键锁死：`[stats]` 的 `best_loop` / `best_kills` / `runs_played`；`[last]` 的 `loop` / `kills` / `gold` / `time_sec` / `owned`（升级 id 逗号拼接，空则 `""`）。缺文件或缺键用默认 0 / 0.0 / `""`，不 `push_error`。

`record_run(session)` 开头必须 `load_from_disk()`，避免 F6 直进沙盒时内存默认 0 把磁盘 best 盖掉。best 取 max，`runs_played += 1`（进了沙盒又 Quit 也算一局），last 全部覆盖成这一局。不要按 gold 比大小。不要存 HP、句读、device_id、音量、Outcome。

写盘时机只在 `CombatSandbox`：死亡后 `_run_session.tick` 之后写一次（`_progress_written` 防重入，死亡条停着看不会每帧 +1）；暂停 Quit、死了 Esc、商店/三选一开着 Esc 回菜单前若尚未 written 则 record。Continue / Retry / R 不写；R 与 Retry 把 `_progress_written` 清回 false。`_exit_tree` 只负责 `paused=false` + 鼠标可见，不悄悄 record。

主菜单 `_ready` 在 `GameSettings.load_from_disk` 旁边 `GameProgress.load_from_disk()`。顶栏 Profile 改成 `EmptyButton`，Name 文案 `best  %d`。点头像弹出 `ProfileOverlay`（与 Settings / Mode 平级，后声明盖在上面）：全屏 Dimmer + 中央 `PROFILE` 小卡，五行 Body + last owned，底左 Back。Esc / Back 关掉，焦点回 Play，音乐/模糊恢复。死亡条 Owned 与 Hint 之间加 `best  %d`，Panel 高 256。战斗 HUD 与暂停 stats 不加 best。

禁止槽位列表、禁止「继续上次」、禁止钱包、禁止登录、禁止中途续打。

**当时不做：** Solo 终点（CLEARED）、接美术、槽位、钱包、WaveDirector、Boss 条、五格枪架、玩家剪影、2P、Virtual Sticks、换三角。

## Day 38（已完成）：Solo 20 轮终点

`ui/game_launch.gd`（`class_name GameLaunch`，`extends Object`，全是 static）把模式一次性带进沙盒。不是 Autoload，不是 Node，禁止 `get_tree()`。不要写进 `progress.cfg` / `settings.cfg`。

接口锁死：`enum Mode { SOLO, INFINITE }`，`SOLO_LOOP_GOAL = 20`（硬锁 20，不是 loop 2，不要 export）。内部默认 Infinite。菜单点 Solo 先 `set_mode(SOLO)` 再切场景；点 Infinite 先 `set_mode(INFINITE)`。两张卡不再共用一个 `_enter_sandbox`。沙盒 `_ready` 调一次 `take_mode()` 交给 `RunSession.configure_mode`，Launch 立刻打回 Infinite。F6 / 下一次没点卡的进入都是 Infinite。Retry / R 不再 take；本局 mode 活在 `RunSession._solo` 上，`restart()` 不清 mode。

Solo：打完 20 轮（L0 到 L19 各一轮 P0–P8，第 20 轮的 P8 商店买完或 Skip）后，通关判定只活在 `CombatSandbox._finish_loop_after_shop()`：先 `notify_phrase_loop()`（19→20，best 才能记到 20），再 `mark_cleared()`。两套弹 `park_all`，敌人预备役，`_set_offer_input_lock(true)`，人还活着但不能开枪。不要 `get_tree().paused`，不要新场景。Infinite 的 `is_solo()` 为 false，loop 20/21/… 照旧加压（内部仍 cap 8）+ `encounter.restart()`，永远没有 CLEARED。

结算条：`is_player_dead() or is_cleared()` 才显示。标题脚本写 `CLEARED`（Theme `ClearedTitle`，绿字 `Color(0.55, 0.78, 0.22, 1)`）或 `DEAD`（仍 `RunSummaryTitle`）。数字行照旧 time/loop/kills/gold/owned/best。Hint 仍是 R to restart + Esc menu。Panel 高 256 不加。禁止按钮、禁止全屏 Dimmer、禁止 paused。

HUD：Solo `L%d/%d  %s`（分母 `GameLaunch.SOLO_LOOP_GOAL`）；Infinite 仍 `L%d  %s`。PhraseLabel 锚点、左下枪/血/XP/gold 一个像素都不要挪。Esc / Start 在 CLEARED 上与死亡同等：回菜单并写盘，不要 PAUSED。活着打到一半仍开暂停。R 重开仍是同一 mode；若 F4 之前是开的，R 之后仍无敌。

写盘：`_process` 里 `is_player_dead() or is_cleared()` 都走 `_record_progress_if_needed()`。Quit / 死了 Esc / 店开着 Esc 仍走 `_return_to_menu()`。Continue / Retry / R 不写；R 与 Retry 把 `_progress_written = false`。`_exit_tree` 仍不写盘。不要新增 `progress.cfg` 键（没有 `solo_clears`）。

模式卡文案：Solo `20 loops. Then CLEARED`；Infinite `No finish line`；Multi 仍 `Coming later`。

开发者调试（不是玩家功能，仅 `OS.is_debug_build()`，不写入 `[input]`）：
- F4（`KEY_F4`）切换无敌秒杀：`PlayerHealth.set_debug_god`；`apply_damage` 在 i-frame 判断里再挡 `_debug_god`，不掉血、不闪白。秒杀只打场上「不在预备役、未死亡」的敌人，走现有击杀链（XP/gold）。三选一和商店仍要手点。再按 F4 关掉。暂停 / 三选一 / 商店开着时无效。
- F3（`KEY_F3`）仅 Solo 且 playing 且没 CLEARED：跳到第 20 轮开头（`debug_set_loop_index(19)`），顶中 `L19/20`。Infinite / 已死 / 已通关无效。
- DebugOverlay 在 `grant: U` 旁加 `god: on` / `god: off`。不要战斗顶中写 GOD。

**当时不做：** 槽位、钱包、Dash、新敌人、Boss、第五把枪、换三角、2P、WaveDirector、把 CLEARED 做成新场景。

## Day 39（已完成）：Dash

`player/player_dash.gd`（`class_name PlayerDash`，`extends Node`）挂在 `player.tscn` 上，与 Motor / Health 平级。不要把冲刺写进 `player.gd` 上帝对象，不要写进 Motor。

数字锁死：210px / 0.12s / 冷却 0.90s（从起冲那一帧起算，含冲刺本身）/ 镜头踢 3。方向：`move_vector` 非零用它，否则 `aim_vector`（至少 `RIGHT`）。穿怪（mask 仍是 wall），不穿墙。冲刺全程 `PlayerHealth.apply_damage` 再挡 `is_dashing()`，不改 `is_invincible()` 语义。不 hitstop，不用 `Engine.time_scale`。

输入：`project.godot` `[input] dash` 只绑键盘 Space。手柄 `device_id >= 0` 读 A（`JOY_BUTTON_A`）边沿，不要写进 InputMap。`PlayerInput.dash_just_pressed` 每帧开头清 false，不进三量。`set_dash_suppressed` 与开火/切枪一起锁。三选一 / 商店 / 暂停 / 已死 / CLEARED 空格不冲。冲的时候仍能瞄准、仍能开枪。

表现：Visual `modulate = Color(1.35, 1.35, 1.45, 1)`，结束恢复 WHITE。不要 tween scale。SfxPool `play_dash` 复用 `_stream_click`（pitch 0.62，volume -8）。DebugOverlay `god:` 旁 `dash: ready` / `dash: 0.42`。战斗 HUD 不加 Dash 条。R / Retry 清冲刺与冷却。F4 无敌与 Dash 独立。

**当时不做：** 冲锋敌人、4 张新卡、Boss、第五把枪、Dash 冷却条、换三角、2P、WaveDirector。

## Day 40（已完成）：冲锋敌人

`enemies/charger_enemy.gd`（`class_name ChargerEnemy`，`extends EnemyBase`，不要 `extends MeleeEnemy`）+ `charger_enemy.tscn`。黄三角直线撞，逼你用 Dash。不要 4 张新卡，不要 Boss，不要换三角。

沙盒 `Enemies` 下预放 `ChargerRight1 (500, 220)` / `ChargerRight2 (540, 280)`，开局 `hold_in_reserve`，禁止运行时 instantiate。x>400 走现有右侧 stagger。

句读只改两处：`P5_NAMES` 末尾加 `ChargerRight1`（loop0 P5 = 6 近战 + 2 远程 + 1 精英 + 1 冲锋 = 10）；`P7_NAMES_DENSE` 末尾加两只（loop≥1 leftover 9+2=11）。`P1` / `P3` / `P5_NAMES_DENSE`（仍 12）/ `P7_NAMES` 一字不改。第一波仍是教学用普通近战。

数字锁死：max_hp 44、SEEK 160、acceleration 1600、knockback 200、贴脸 8、冲撞 16、charge 520px/s / 380px、windup 0.45s、recover 0.55s、冷却 1.60s（从 RECOVER 结束起算）、射程 [180, 520]、XP 16、gold 5。加压只加 HP（+8/loop）和两种伤害（+2/loop），cap 仍 8。charge_speed / windup / distance 不随 loop 变。

AI 只活在本脚本：`SEEK` → 距离在带内且冷却好了进 `WINDUP`（顿住对准，scale `(1.25, 0.85)`）→ 结束那一帧锁方向进 `CHARGE`（`velocity = dir * 520`，不 steer、不分离、忽略击退；hitstop 仍能打断）→ 走满 380px / 撞墙 / 打到玩家一次 → `RECOVER` 摩擦停下再 SEEK。玩家已死任何状态都 steer 到 0。Visual：WINDUP `Color(1.6, 1.45, 0.7, 1)`，CHARGE `Color(1.55, 1.35, 0.45, 1)`。起冲 `SfxPool.play_charge` 复用 click（pitch 0.48，-6dB）；命中才 `apply_kick(dir, 5)`，起冲不踢。

DebugOverlay 活着摘要改成 `%dM+%dR+%dC`（Elite 仍算 M）。战斗 HUD 不加 CHARGER。空格 / F4 / F3 / R 行为不变；冲锋怪吃 F4 秒杀。

**当时不做：** 4 张新卡、Boss、第五把枪、换三角、2P、WaveDirector、新 wav、Dash 条。

## Day 41（已完成）：一只 Boss 句

`enemies/boss_enemy.gd`（`class_name BossEnemy`，`extends EnemyBase`，不要 `extends MeleeEnemy` / Charger / Elite）+ `boss_enemy.tscn`。P7 leftover 清场之后、商店之前，场上只剩一只大紫三角。无血条、无召唤、无阶段。不要 4 张新卡，不要换三角。

沙盒 `Enemies` 下预放 `BossCenter1 (0, -360)`，开局 `hold_in_reserve`，禁止运行时 instantiate。x=0、y=-360 走现有 top stagger（0.08 底）。

句读：`PHRASE_TOTAL = 9`。index 8 = `_start_playing(["BossCenter1"], ["BossCenter1"])`；P7 清完仍 `_begin_phrase(8)`，现在 8 是 Boss 不是 DONE。打死走 index 9 → DONE → 现有商店。`P1` / `P3` / `P5` / `P7` 名字表一字不改。每一轮都出 Boss（含 loop 0）。顶中分母 9；Boss 在场 `get_phrase_label()` 返回 `boss`，不是 `8/9`。P0 显示 `0/9`。

数字锁死：max_hp 220、SEEK 110、acceleration 900、knockback 90、贴脸 16、冲撞 26、charge 480px/s / 400px、windup 0.70s、recover 0.70s、扇形 windup 0.40s / 5 发 / ±18°、弹速 400、弹伤 10、寿命 1.3、视觉 1.6、射程 [160, 560]、XP 60、gold 18。加压只加 HP（+24/loop）和接触/冲撞（+3）与弹伤（+2），cap 仍 8。charge_speed / windup / distance / volley_count 不随 loop 变。

AI 只活在本脚本：`SEEK` → `WINDUP_CHARGE`（顿住对准，scale 2.2×(1.18, 0.88)）→ 结束那一帧锁方向 `CHARGE`（`velocity = dir * 480`，不 steer、不分离、忽略击退；hitstop 仍能打断）→ 走满 400px / 撞墙 / 打到玩家一次 → `RECOVER` → `WINDUP_VOLLEY` → 同一帧 5 发扇形弹（中间对准玩家）→ SEEK。玩家已死任何状态都 steer 到 0。起冲 `play_charge`；命中才 `apply_kick(dir, 7)`；扇形弹 `play_enemy_shot` 一次，不踢镜头。敌人弹池走现有 `bind_projectile_pool`。

DebugOverlay 活着摘要 `%dM+%dR+%dC+%dB`（判定顺序 Charger → Boss → Melee → 其余 R；Elite 仍算 M）。战斗 HUD 不加 Boss 条。F2（debug，`KEY_F2`，不写入 `[input]`）跳到 Boss 句，不改 loop_index。F3 仍跳 L19 并从 P0 重来。F4 仍秒杀含 Boss。Solo 第 20 轮仍是 Boss → 商店 → CLEARED。

**当时不做：** 4 张新卡、Boss 条、召唤小兵、换三角、2P、WaveDirector、新 wav、五格枪架。

## Day 42（已完成）：英文改名 + 朝向合同 + 主角/四枪换图

`images/` 改名（文件系统改名，不拷贝、不重绘）：`wpc.PNG → player.png`、`近战.png → melee.png`、`远程.png → ranged.png`、`冲锋.png → charger.png`；删掉旧 `wpc.PNG.import` 让 Godot 重新生成。`logo.png` / `mainmenu.png` / `boss.png` 不动。`images/` 里不再有中文文件名，代码和 `.tscn` 里也没有中文贴图路径。

`player/facing_contract.gd`（`class_name FacingContract`，`extends Object`，全是 const，不 `get_tree()`，不是 Autoload）锁死朝向合同：玩家是 **SPIN**（`Body.rotation` 预旋转抵消原图鼻子偏移，再让整根 `Visual.rotation = aim.angle()`）；近战/远程/冲锋/Boss 四张图是 **FLIP**（只用 `Sprite2D.flip_h`，禁止 `Visual.scale.x = -1`）。今天只有 `player.gd` 读 `PLAYER_*`；四条敌人路径和 `*_NATIVE_FACES_RIGHT` 先写好常量，`enemies/**` 一行没改，留给 Day 43。

`player/player.tscn`：`Visual` 从 `Polygon2D` 改成 `Node2D`，是面向 / 后坐 / squash / Dash modulate / 死亡塌缩唯一根，节点名锁死不变。子节点：`Body`（`Sprite2D`，`texture` / `rotation` / `scale` 由 `player.gd` 的 `_setup_body_visual()` 从 `FacingContract` 读出赋值，不在 `.tscn` 里存第二份数字：`texture = PLAYER_TEXTURE`、`rotation = deg_to_rad(-PLAYER_FACE_OFFSET_DEG)` 即 -40°、`scale = PLAYER_BODY_SCALE` 即 `(0.05, 0.05)`）；`Guns`（`Node2D`，本地坐标 `Vector2(4, 2)`，挂 `player/player_weapon_visual.gd` 的 `PlayerWeaponVisual`）下挂四个 `Sprite2D`：`PistolSprite` / `ShotgunSprite`（初始 `visible=false`）/ `RifleSprite`（`visible=false`）/ `SmgSprite`（`visible=false`），缩放分别 `0.36` / `0.40` / `0.44` / `0.36`；`Muzzle` 仍是 `Visual` 的直接子节点（不是 `Guns` 的子节点），`FireFeedback` / `Weapon._try_fire` 的路径一行没改。`CollisionShape2D` 半径仍 20。

四把枪贴图是本地程序生成的透明 PNG（`images/weapons/pistol.png` / `shotgun.png` / `rifle.png` / `smg.png`，枪管朝纹理 +X，不是网图、不是 Polygon2D/ColorRect 冒充）。`PlayerWeaponVisual` 不读 Input，只问 `WeaponHost.get_current_weapon()`：`refresh()` 只显示当前枪的 `Sprite2D`、其余三把 `visible=false`，并把 `Visual/Muzzle.position` 写成当前枪的 `get_muzzle_local_offset()`；`hide_all()` 把四把全部藏起来。`WeaponHost._activate_index` 末尾、`reset_after_player_revive` 末尾各调一次 `refresh()`，`deactivate_all()` 调 `hide_all()`（都走 `get_node`，不是信号总线、不是 Autoload）。`weapons/weapon.gd` 基类新增 `get_muzzle_local_offset()`（默认手枪 `(59, 13)`），四把枪各自覆盖：`Pistol (59, 13)` / `Shotgun (77, 15)` / `Rifle (91, 12)` / `Smg (65, 13)`；四枪 `_ready()` 里的射速/伤害/弹速一个数字没动，`Weapon._try_fire` 的出弹公式一行没改（仍从 `_player.get_muzzle_global_position()` 出弹）。

`player/player_health.gd` 的 `_visual` 类型改成 `Node2D`，删掉所有 `Polygon2D.color` 读写（`Sprite2D` / `Node2D` 没有 `color`）。受击闪白仍 `modulate = Color(2.2, 2.2, 2.2, 1)`；Dash 中 `_restore_color()` 早退不盖 Dash 的 modulate；死亡改成 `modulate = DEAD_COLOR`（灰），不再写 `.color`；`reset_for_sandbox` 只恢复 `modulate = Color.WHITE`。`HitReaction` / `FireFeedback` / `PlayerDash` 一行没改，仍绑同一个 `Visual` 节点，squash 数字、Dash 210px/0.12s/0.90s、后坐像素全部不变。

敌人这天已接上贴图：`melee_enemy.tscn` / `elite_melee.tscn` / `ranged_enemy.tscn` / `charger_enemy.tscn` / `boss_enemy.tscn` 的 `Visual` 全部改成 `Sprite2D`，走 `FacingContract` 的 FLIP 合同（见下方修复说明）。

**当时不做：** Boss 条、4 张新卡、第五把枪、五格枪架、HUD 枪图标、走路循环/AnimationPlayer 状态机、地板、火花池、死亡碎裂、战斗 BGM、2P、ENet、触控、Virtual Sticks、WaveDirector。

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
- 沙盒重置 `R`（`sandbox_reset`）由 `CombatSandbox` 读取，不塞进输入合同三量；不要手柄映射
- 沙盒 Esc（`ui_cancel`，引擎默认，不写入 `project.godot`）由 `CombatSandbox` 读取：活着且三选一/商店都关着时打开 `PauseOverlay`；已死、已通关、三选一开着或商店开着时立刻卸回主菜单。手柄 Start 同样。暂停开着时 Esc / Start 走 Continue。不塞进输入合同三量
- 调试授予 `U`（`debug_grant_upgrade`）由 `CombatSandbox` 读取，不塞进输入合同三量；只授 `max_hp_s`
- Dash `dash`（键盘 Space）由 `PlayerInput.dash_just_pressed` 产出，不进三量。手柄 A（`JOY_BUTTON_A`）边沿自读，不要写进 InputMap。弹窗 / 商店锁 `set_dash_suppressed`
- 开发者 F4 / F3 / F2 / F1 用 `InputEventKey.physical_keycode`（`KEY_F4` / `KEY_F3` / `KEY_F2` / `KEY_F1`），不写入 `[input]`。仅 debug 构建；暂停 / 三选一 / 商店开着时无效。F2 跳到当前 loop 的 Boss 句，不改 loop_index。F1 在 boar / chicken 底值之间切换，不改 `_record_id`、不写 `records.json`

手柄（`device_id >= 0`）独占合同三量：左杆走、右杆瞄、右扳机/RB 开火；十字键切 1/2/3/4。左杆仍是 `STICK_DEADZONE=0.25` + 径向缩放模拟走速；右杆走 `map_aim_stick`（`AIM_STICK_DEADZONE=0.12`）：回中 keep last，出圈当帧单位向量，无转向平滑。Y 轴不自己取负。没手柄时走上面键鼠路径。禁止把 Joy 写进 InputMap。不要做 Input Autoload。输入组件挂在玩家节点上。

手机触控（双摇杆、设置里 Virtual Sticks）整包后置到内容 / 壳 / 美术 / 局域网都做完之后再调。禁止加 `TouchStick` / 触摸层 / 设置 C 页。

## 禁止事项（旧作不要带进新仓库）

- 自动锁最近敌人；没目标就 `return`；PC 自动开火；手机「自动射击」开关；桌面虚拟摇杆；把 Joypad 写进 `move_left` 让所有手柄一起推 P1
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
player/     玩家场景、PlayerInput（键鼠或单把手柄 device_id）、PlayerMotor、PlayerHealth、PlayerDash（空格 / 手柄 A 短冲刺）、Muzzle、WeaponHost、FireFeedback
weapons/    Weapon 薄基类、Pistol / Shotgun / Rifle / Smg、Projectile、本局 ProjectilePool
enemies/    EnemyBase、MeleeEnemy、RangedEnemy、EliteMelee、ChargerEnemy（黄三角直线冲锋）、BossEnemy（P7 后大紫三角，无血条无召唤）；DummyTarget 脚本保留但沙盒不再放置
combat/     碰撞层常量、DamageNumber、HitReaction、MuzzleFlash、HitSpark、HitSparkPool、DeathShard、DeathShardPool、SfxPool
audio/      程序生成短 WAV（手枪/霰弹/步枪/命中/击杀/受伤/拒发/敌人弹）+ 菜单 main.mp3 + 战斗 war.mp3
arena/      EncounterPhrases 手写句读（P0–P7 + Boss，PHRASE_TOTAL=9）+ 本局节点 RunSession + UpgradeApplier；不是 Autoload RunState / WaveDirector
camera/     PlayerCamera、AimReticle
ui/         MainMenu（F5 主场景，Play / Settings / Quit）+ ModeChoiceOverlay（Play 后 SOLO / MULTI 小卡）+ RecordSelector（大面板 FloatingPanel + Header + LIST 2 列网格）+ LanOverlay（大面板 FloatingPanel + Header + PICK 2 列网格）+ SettingsOverlay + ProfileOverlay（大面板 FloatingPanel + Header，best/last/runs，仍只读 progress.cfg）+ GameSettings（user://settings.cfg 仅 audio/display）+ GameLaunch（一次性 mode / record id 交接，不是 Autoload；进沙盒只传 id）+ GameProgress（user://progress.cfg，跨局成绩，不是 Autoload）+ GameRecord / GameRecords（user://records.json，上限 12，可写 boar/chicken，不是 Autoload）+ Hud + UpgradeOffer + ShopOffer + WinnerPage（layer=22，DEAD/CLEARED，分数拆解 + 本档 Top 10 + Retry/Menu）+ PauseOverlay（layer=25，活着 Esc 暂停，唯一允许 `get_tree().paused`）+ game_theme.tres（左下 HP+武器+XP+`gold  0`，顶中 `loop_goal>0` 时 `L0/5  0/9`，否则 `L0  0/9`；句间/升级三选一 layer=20；P8 后商店 layer=20 买一张或 Skip；死亡/通关 WinnerPage layer=22 含拆解与本档历史；暂停 PAUSED layer=25）；DebugOverlay 仍在 debug/
data/       UpgradeDef + UpgradeCatalog.tres + data/upgrades/ 10 条；CharacterDef + CharacterCatalog.tres + data/characters/ 野猪/野鸡底值；升级从角色底值重算
debug/      DebugOverlay
sandbox/    CombatSandbox（有档用 `record.loop_goal`；F6 缺档走 Infinite 隐式 boar；Floor 平铺地砖 / Player / PlayerCamera / AimReticle / Projectiles / EnemyProjectiles / HitSparks / DeathShards / CombatMusic / SfxPool / Enemies / EncounterPhrases / RunSession / UpgradeApplier / Hud / UpgradeOffer / ShopOffer / WinnerPage / PauseOverlay / DebugOverlay）
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

## 剩余顺序

手机触控已放弃本周实现，**整包挪到最后**。Day 31 手柄已按 `device_id` 拆开（仍单人）。Day 32 本局金币 + P8 后商店已落地。Day 33 点 Play 出模式窗已落地。Day 35 osu 式主题回炉已落地（圆角粉紫 Theme、背景图 + 主题音乐 + 模糊衰减、合成点击音效）。局域网 2 客户端和「用现有档开 Host」已落地。同机分屏明确不做。5 人 / 房间浏览器后置。

| 顺序 | 仓库里做什么 | 玩家会感到什么 | 先不要做 |
|---|---|---|---|
| **31（已完成）** | 输入按 `device_id` 拆开 | 插手柄也能单人打 | 分屏、2P、**任何触控 / 虚拟摇杆** |
| **32（已完成）** | 本局金币 + P8 后商店买一张已有升级或 Skip | 打死人攒钱，轮与轮之间能花掉 | 刷新、第三扇窗、掉落硬币 |
| **33（已完成）** | 点 Play 出模式窗；Solo / Infinite 进同一 CombatSandbox；Multi 灰掉预留 | 有「无限」这个名字；点进去还是现在这局 | 每日挑战、排行榜、2P、房间 |
| **34（已完成）** | osu 式菜单壳：底栏三 icon、瘦顶栏（设置/Home）、叠层非线性缓动（`UiAnim`） | 标题/设置开始像 osu；开关窗有呼吸感；血条会滑 | Wiki/Chat/Profile、五格枪架、重排血条、2P |
| **35（已完成）** | osu 式主题回炉 | 标题/设置开始像 osu | Wiki/Chat/Profile、五格枪架、2P |
| **36（已完成）** | 战斗暂停叠层：Esc 开 PAUSED，Continue / Retry / Quit | 活着能停；死了或弹窗开着仍回菜单 | 存档、暂停里改设置 |
| **37（已完成）** | 跨局成绩 `user://progress.cfg`（best / last / runs）；死亡或回菜单写一次；顶栏 Profile 叠层 | 关掉再开还记得打到第几轮；死亡条有 best | 中途续打、槽位、钱包、Autoload |
| **38（已完成）** | Solo 20 轮终点（`SOLO_LOOP_GOAL = 20`）出 CLEARED；Infinite 仍无限；F4 无敌秒杀、F3 跳最后一轮 | Solo 打完能停；顶中有 `/20` | 改 Infinite、loop 2、换三角 |
| **39（已完成）** | Dash：空格 / 手柄 A，210px / 0.12s / 冷却 0.9s；穿怪不穿墙 | 贴脸能闪一下 | Dash 条、冲刺伤害、穿墙 |
| **40（已完成）** | 冲锋敌人：黄三角直线撞，逼你用 Dash | 贴脸必须侧闪 | 4 张新卡、换三角 |
| **41（已完成）** | 一只 Boss 句：P7 后大紫三角，无血条、无召唤 | 一轮有一次必须认真打的高潮 | 五格枪架、4 张新卡、换三角 |
| **42（已完成）** | 接美术第一步：英文改名 + 朝向合同 + 主角换成 player.png + 自生成四把枪外观 | 终于是猪了，枪也换了样子 | 为了图改手感 |
| **43（已完成）** | 敌人换 sprite：melee / ranged / charger / boss（FLIP，精英复用 melee 放大）；顺带修正枪跟鼠标转、猪身体不转 | 敌人也不再是三角，猪身体不再乱转 | 为了图改 AI、新怪、换三角改数字 |
| **44（已完成）** | 地板 / 火花池 / 死亡碎裂 / 战斗 BGM | 场景不再是空气墙，打击更有存在感 | 波次表、商店、精英/Boss 数值改动、新怪 |
| **45（已完成）** | Arc A `GameRecords`：`user://records.json`，上限 12，每局新开只记结果 | 档位数据立住；菜单仍是 Solo / Infinite 三选一；Profile 仍读 progress.cfg | RecordSelector UI、野鸡数值、WinnerPage、2P |
| **46（已完成）** | Arc B `CharacterDef`：野猪 / 野鸡底值 | 两套身份数字，卡池仍共用；菜单仍三选一、隐式档仍 boar | 骨骼、专属卡池、2P |
| **47（已完成）** | Arc C RecordSelector 取代 ModeOverlay；`loop_goal` 滑杆 | Play 进档位列表；选已有档直接开打；建档可选猪/鸡 | 中途续档、Multi 进 Record |
| **48（已完成）** | Arc D WinnerPage v2：独立结算 + 本档历史对比 | 死 / 通关有分数拆解和本档 Top 10 | 云同步、成就 |
| **49（已完成）** | 局域网 2 客户端（ENet 17777 / protocol 1） | 同网两台一起打，不写档 | 5 人、房间浏览器、同机分屏 |
| **50（已完成）** | 用现有档开 LAN：PICK 预填并锁定角色 + loop_goal | Host 借档开房，Guest 仍自选；联机不写盘 | 5 人、房间浏览器 |
| **51（已完成）** | Play 分岔 Solo/Multi、顶栏直达、大面板弹层 | 点 Play 先选 Solo / Multi；顶栏也能直达；档位/联机/资料是大面板 | Profile 新内容、Settings 大面板 |
| **52（已完成）** | Profile 概览 + 可视化排行 | 顶栏成绩更好读；本档 Top 10 可视化 | 云同步、跨档总榜 |
| **53（已完成）** | Settings osu 式抽屉：音量/全屏/VSync/MSAA/UI Scale/键盘重绑/长按删档 | 设置能改、能搜、能滚 | 手柄重绑、Settings 抽屉换皮 |
| **54（已完成）** | 渲染分辨率接 SubViewport | 战斗世界跟着 render_scale 走，HUD 仍清晰 | 逐帧动态分辨率 |
| **55（已完成）** | FlatBold 令牌 + OfferButton 换皮 | 模式卡/商店卡变成小圆角纯色块 | FloatingPanel / 胶囊 CTA |
| **56（已完成）** | 大面板 + 胶囊 CTA FlatBold | 1680×920 面板不透明去阴影；Host/Join/Retry 是方钮加粗 | Settings 抽屉换皮、TopBar/LogoButton |
| **57（已完成）** | 右摇杆即时瞄准：回中 keep last，出 0.12 当帧对准，无转向平滑；`map_aim_stick` 合同 | 拨哪指哪，松开停在最后朝向 | 虚拟摇杆 UI、手柄重绑、右杆开火 |
| **58（已完成）** | Settings 抽屉换皮 FlatBold | 侧栏深灰、近白粗体、洋红方条 | Joypad 重绑、虚拟摇杆 |
| **59（已完成）** | 可见区 fit：大面板/卡片随 `visible_rect` 收缩 | ui_scale 130% 两列仍完整可见，不双倍放大 | 商店深化、跟班、TopBar |
| **61（已完成）** | 两种跟班上场：CompanionDef + F8 debug，上限 1 | 身侧青色近战/远程能打能死；商店仍只卖升级 | 商店接线、主动技能、LAN 同步跟班 |
| **62（已完成）** | 厚血远程跟班：买时选枪，AI 绕圈/LOS，删近战 | P8 可出 Gunner 70，选枪上场；战斗绕圈不站桩 | 跟班 HUD、主动技能、LAN 同步、消耗品 |
| **63** | 商店其它可购项（消耗品）或跟班死亡再买的手感收尾 | 局内还能买一次性道具 | 手柄、地图、主动技能 |
| **更后面** | 5 人 / 房间浏览器 | — | Steam、互联网匹配、Mods |
| **做完之后** | 手机双摇杆 + 设置里 Virtual Sticks（电脑调试） | 手机上也能打；电脑勾上才能拖盘调试 | 不要提前做；触控有 bug 就整包后置 |

## Day 44（已完成）：地板 / 火花池 / 死亡碎裂 / 战斗 BGM

场景不再是空气墙，打击更有存在感。不改 AI、不改四把枪/敌人 `_ready` 身份、不改 Motor / 相机 / 击退 / hitstop / XP / gold / 加压、不改 HUD 锚点。Autoload 仍为 0。

- **地板**：`sandbox/arena_floor.gd`（`class_name ArenaFloor`）挂在节点名仍叫 `Floor` 的 `Sprite2D` 上，`z_index = -10`，`centered` 覆盖 `Rect2(-800,-450,1600,900)`。运行时生成一次 64×64 可平铺 `ImageTexture`（冷色勾缝石砖：缝 `Color(0.10, 0.11, 0.13)`、砖 `Color(0.17, 0.19, 0.23)`，`TEXTURE_FILTER_NEAREST`），`texture_repeat` + `region` 覆盖 1600×900，不要 1000 个 Sprite 拼地砖，不要 `NoiseTexture2D`，不要 `images/floor.png`。墙碰撞尺寸未改，不是 TileMap 导航。
- **火花池 64**：`combat/hit_spark_pool.gd`（`class_name HitSparkPool`）挂在 `CombatSandbox/HitSparks`。合同抄 `ProjectilePool`：`setup` / `acquire` / `release` / `park_all`。`HitSpark.play()` 重置 age/alpha/scale/位置/方向；寿命仍 `LIFE_SEC=0.08`、`SPRAY_SPEED=140`，到点 `pool.release(self)`，禁止 `queue_free`。池满这一发不出火花，禁止删天上正在飞的火花。`CombatSandbox._bind_runtime` 在两套弹池 `setup` 之后遍历子节点 `Projectile.bind_spark_pool`，禁止每发 `get_node` / group 扫描。
- **死亡碎裂 6 片 / 池 64**：`combat/death_shard.gd` + `death_shard.tscn` + `death_shard_pool.gd`。3 顶点 Polygon2D（约 8～12px），棕 `Color(0.62, 0.46, 0.34, 1)`，沿飞出方向平移 + 自旋，0.28s 淡出后 release。不碰撞、不 mask、不是 GPUParticles2D。`EnemyBase._defeat` 仍变灰 + `HitReaction.begin_death(true)` + 留场，然后 `_spawn_death_shards()` 从池里喷最多 6 片；池不够就有几片出几片，禁止为了凑 6 再 `instantiate`。预备役/未击败不喷。玩家 `PlayerHealth` / `HitReaction` 玩家路径一字不改：被打死仍只轻微压扁，不碎。Boss/精英不必换色。
- **park**：`_loop_phrases`、`_finish_loop_after_shop` 的 CLEARED 分支、`_reset_sandbox`（以及 F2/F3）都走 `_park_combat_pools()`，两套弹 + 火花 + 碎片一起收回，避免下一句读场上残留特效。
- **战斗 BGM**：`CombatSandbox/CombatMusic` 是 `AudioStreamPlayer`（不是 2D），流 `res://audio/war.mp3`（不要 `combat.mp3`）。脚本里 `stream.loop = true`，`volume_db = -22.0`（床底，比枪声低约 10dB，避免和子弹糊在一起）。`process_mode` 默认 INHERIT，暂停树就停曲，Continue 后续播。`_ready` 里 `play()`。不要 `PROCESS_MODE_ALWAYS`，不要 Autoload 音乐管理器，不要在三选一/商店时淡出，死亡/CLEARED 不停曲。Esc 回菜单靠卸场景停；主菜单继续播 `main.mp3`，两首不会叠。Master 音量仍只走 `GameSettings` 总线，不要第二套滑条。
- **Overlay**：增补 `spark_active` / `spark_free` / `shard_active` / `shard_free`。R 之后两池 `active=0`。不要 Theme/缩放器，不要第五块 HUD。

**当时不做：** 同机 2P、局域网/ENet、房间浏览器、4 张新卡、Boss 血条、五格枪架、伤害数字池、金币掉落物、键位重绑、Music/SFX 分轨滑条、任何 Autoload、WaveDirector、触控、`GPUParticles2D`、敌人 `queue_free`。

## Day 45（已完成）：档位数据层 GameRecords

档位数据立住，菜单外观不变。Play 仍打开 ModeOverlay 三选一；没有 RecordSelector、没有选人、没有删除按钮。Profile 仍只读 `user://progress.cfg`。每局永远新开，history 只记结果字典，不写 HP / 句读 / 弹池 / 升级过程。Autoload 仍为 0。`settings.cfg` 一字不改。

- `ui/game_record.gd`（`class_name GameRecord`，`extends RefCounted`）：`to_dictionary` / `from_dictionary`。非法 `character_id` 打回 `boar`，只接受 `boar` / `chicken`。`loop_goal < 0` 打回 0。history 最多 10 条。不是 Resource，没有 `.tres`。
- `ui/game_records.gd`（`class_name GameRecords`，`extends Object`，全 static）：`user://records.json`，`save_version=1`。上限 `MAX_RECORDS=12`。`create_record` 满员返回 `null`，禁止删旧档腾位。`delete_record` 必须写盘，本阶段无按钮调用。原子写：先 `records.json.tmp`，flush/close 后 `DirAccess.rename`。损坏或缺文件 → 空列表，不 `push_error`。
- 算分只活在 `GameRecords.compute_score`：`loop * 1000 + kills * 5 + gold * 2 + floor(time_sec) + (cleared ? 5000 : 0)`。quit / dead 没有 +5000。history 按 score 降序，最多 10 条；`best_score` 是该档见过的最大分（被裁掉的低分不影响 best）。
- 隐式档：没有 RecordSelector 时 Solo → `loop_goal=20` 的 boar 档，Infinite → `loop_goal=0`。同一 `character_id` + 同一 loop_goal 桶复用 `created_at` 最早的一条。本阶段 create / ensure 只写 `character_id=boar`。沙盒 CLEARED 仍读 `GameLaunch.SOLO_LOOP_GOAL`，不读 `record.loop_goal`。
- `GameLaunch` 增补一次性 `active_record_id`（`set` / `take`，take 后打回 `""`）。本阶段 MainMenu 不 set，留给 Arc C。只传 id，不塞 Record 对象。
- `CombatSandbox`：`take_mode` 之后 `take_active_record_id`；空或找不到则 `ensure_playable_record`。R / Retry 不换档、不 take Launch。`_record_progress_if_needed` 先 `GameProgress.record_run` 再 `GameRecords.append_run_result`。Continue / Retry / R 两套都不写；`_progress_written` 挡住死亡条停着看时每帧 append。`_exit_tree` 仍不写盘。
- F6 直进沙盒走 Infinite 隐式档；`append_run_result` / `ensure` 开头 `load_from_disk`，不会用内存空档盖掉已有 Solo history。
- `DebugOverlay` 增补 `record` 末 6 位、`hist`、`best`、`goal`。不要 Theme/缩放器，不要第五块 HUD。
- 第一次进沙盒后 `user://records.json` 存在。再打同一模式只往同一档 history 追加，不新增 records 条数。

**当时不做：** RecordSelector / New Record Editor、CharacterDef / 野鸡数值 / 换玩家贴图、WinnerPage v2、独立结算全屏、本地化 `tr()`、同机 2P、局域网、中途续打、任何 Autoload。

## Day 46（已完成）：角色底值 CharacterDef

角色底值是数据，升级从角色底值重算。菜单仍是 Solo / Infinite / Multi 三选一，没有选人页。隐式档 `WRITE_CHARACTER_ID` 仍只写出 `boar`，所以正常 Play 仍是野猪手感。鸡贴图走 `res://images/chik.png`，没有骨骼、没有第二套场景。Dash 仍是 210px / 0.12s / 0.90s。Autoload 仍为 0。10 张升级仍共用 `UpgradeCatalog`，不按角色过滤。

- `data/character_def.gd`（`class_name CharacterDef`，`extends Resource`）：HP / 移速 / 加速度组 / i-frame / hurtbox / body_scale / `body_texture`。禁止枪伤害、Dash 数字、knockback_impulse、skeleton_scene。
- `data/character_catalog.gd`（`class_name CharacterCatalog`，`extends Resource`）：`get_count` / `get_all` / `get_by_id`。重复 id `push_error` 并跳过后到的；空 id 返回 null。
- `data/characters/boar.tres`：HP 100、速 420、半径 20、`body_scale=(0.065,0.065)`、贴图 `player.png`，现有基线原样迁移。
- `data/characters/chicken.tres`：HP 80、速 480、半径 16、`body_scale=(0.052,0.052)`（0.065×16/20）、贴图 `images/chik.png`。
- `data/character_catalog.tres`：entries 只有这两条。
- `Player.apply_character`：写 HP/i-frame/Motor 底值、运行时覆盖 `CircleShape2D.radius`、`Visual/Body.scale` 和 `Body.texture`。换身份满血，不走 `apply_max_hp` 差值治疗。`reset_for_sandbox` 不把半径/移速/贴图打回场景导出值。Player 不 preload 某一份 `.tres`。
- `UpgradeApplier.capture_baseline()` 仍从 Player 运行时读取。顺序锁死：`apply_character` → `capture_baseline` → `apply_owned`。swift 乘在该角色自己的 `base_move_speed` 上。
- `CombatSandbox`：`_bind_playable_record` 之后、`capture_baseline` 之前 `_apply_record_character()`。R / Retry 不重新 `apply_character`。debug 构建 F1 在 boar/chicken 之间切换本局角色，已有升级保留在新底值上，不改档、不写盘。
- `DebugOverlay` 增补 `char: boar` / `char: chicken`。不要第五块 HUD。

**当时不做：** RecordSelector / New Record Editor、WinnerPage v2、Skeleton2D 走路循环、鸡专属卡池 / 主动技能 / 二段跳、同机 2P、局域网、中途续打、任何 Autoload。

## Day 47（已完成）：RecordSelector 取代 ModeOverlay

Play 进档位列表，不再弹出 Solo / Infinite / Multi 三张卡。点已有档用该身份和 `loop_goal` 新开一局；`+ New Record` 在同一叠层里选角色和终点。Multi 仍不进这套 UI。每局永远新开，history 只在局末 append，不写 HP / 句读 / 弹池。WinnerPage 是 Day 48。Autoload 仍为 0。`settings.cfg` 一字不改。Profile 仍只读 `progress.cfg`。

- `ui/record_selector.gd`（`class_name RecordSelector`）+ `ui/record_selector.tscn`：一个叠层两个状态 `LIST` / `EDITOR`。`open()` 永远进 LIST 并 refresh。信号只有 `selected_record(id)`。Dimmer `Color(0,0,0,0.35)`，`mouse_filter` 开时 STOP、关时 IGNORE，`UiAnim.enter_overlay` / `exit_overlay`。底左 Back `120×44` OfferButton。不要 AcceptDialog。
- LIST：已有档按 `created_at` 升序 + 末尾 “+ New Record”。每行 HBox：主卡 `Vector2(520, 96)` OfferButton（头像 / 名字 / 角色名 + `%d loops` 或 `Inf` / best score）+ 右侧删除 `44×44` “×”。超过约 4 张走 ScrollContainer。满 12 张时 New Record `disabled` 且 `focus_mode=NONE`，禁止删旧档腾位。
- 删除：本叠层确认条 “Delete this record?” Yes / No。Yes 才 `delete_record` 再 refresh。删除不进沙盒。
- EDITOR：Boar / Chicken 两张 OfferButton 横排（贴图 `body_texture`，默认 boar；键盘 1/2 沿用 `weapon_pistol` / `weapon_shotgun`）。`HSlider` min=0 max=50 step=5，默认 20，0 显示 `Inf`。名称 LineEdit placeholder `Name (optional)`，留空走自动名。Confirm 是 PillPink：`create_record` 成功才 `selected_record.emit(id)`，满员留在 EDITOR。Back / Esc 回 LIST，不关叠层。
- 自动名：鸡 `"Chicken · %d loops"` / `"Chicken · Inf"`，其它 `"Boar · …"`。用户填了名称则 `strip_edges` 后原样保存。
- `GameRecords`：删掉 `WRITE_CHARACTER_ID`。`_character_id_for_write` 只接受 `boar` / `chicken`，其它打回 `boar`。`ensure_playable_record` 现在允许 chicken 桶。上限 12、history Top 10、算分、原子写不改语义。
- `GameLaunch`：保留 `Mode` 与 `SOLO_LOOP_GOAL=20`（滑杆默认 / 缺档 Solo 隐式档，不是运行时硬锁终点）。MainMenu 进沙盒只 `set_active_record_id(id)`，禁止 `set_mode`。`take_mode()` 仍给 F6 / 没点卡：缺档时 Infinite → `loop_goal=0` 隐式 boar，不会盖掉已有鸡档。
- `RunSession.configure_mode(loop_goal)`：`<0` 打回 0。`is_solo()` = `loop_goal>0`。`restart()` 不准清 `_loop_goal`。
- `CombatSandbox._bind_runtime`：先 `_bind_playable_record`，再 `configure_mode(档内 loop_goal)`，再 `_apply_record_character`，再 capture_baseline / apply_owned。CLEARED 与 HUD 分母读本局 `get_loop_goal()`，禁止再读 `GameLaunch.SOLO_LOOP_GOAL`。F3 跳到 `loop_goal-1`。R / Retry 不换档、不 take Launch、不重新 configure_mode。F1 仍只换本局角色。
- HUD：`loop_goal>0` → `L%d/%d  %s`，否则 `L%d  %s`。PhraseLabel 锚点不动。
- 已删除 `ui/mode_overlay.gd` / `ui/mode_overlay.tscn`。场景树没有 ModeOverlay。

**当时不做：** WinnerPage v2、独立结算全屏、中途续打、同机 2P、局域网、骨骼走路、鸡专属卡池、第二份 player 场景、任何 Autoload。

## Day 48（已完成）：WinnerPage v2

死了或通关不再是一条只读小条。`WinnerPage` 是独立 tscn，以 CanvasLayer layer=22 叠在沙盒上，不 `change_scene` 到结算页，不卸沙盒。碎块还在飞。Retry 走 `_reset_sandbox()`。仓库里唯一 `get_tree().paused = true` 仍是 PauseOverlay。Autoload 仍为 0。算分公式未改。Profile 仍只读 `progress.cfg`。已删除 `RunSummary`。

- `ui/winner_page.gd`（`class_name WinnerPage`）+ `ui/winner_page.tscn`：信号 `retry_pressed` / `menu_pressed`。`present(record_id, session, previous_best)` 一次填死所有 Label，禁止 `_process` 轮询分数。Dimmer `Color(0,0,0,0.45)`。进场 `UiAnim.enter_overlay`，逻辑开关瞬时。PROCESS_MODE_INHERIT。
- 只在 DEAD / CLEARED 弹出。活着暂停 Quit → `_record_progress_if_needed()`（outcome=quit）→ 主菜单，不 present。
- 沙盒先读 `previous_best`，再 `GameProgress.record_run` + `GameRecords.append_run_result`，再 present。NEW BEST 用 `this_score > previous_best`，不要用写盘后的 `record.best_score`。
- 分数只调 `GameRecords.compute_score`：`loop*1000 + kills*5 + gold*2 + floori(time_sec) + (cleared?5000:0)`。WinnerPage 不再写一份。
- 左列：CLEARED / DEAD、档名、大分、可选 NEW BEST、四行拆解、通关才 `cleared  +5000`、汇总 loop/kills/gold/time/owned。
- 右列 THIS RECORD：本档 history 最多 10 行 `#N  score   Lloop  DEAD|CLEARED|QUIT  time`；用 timestamp+score 高亮本局（并列取第一条匹配）；`rank  %d / %d`。不跨档、不读 progress.cfg。
- 底排 Retry（PillPink，默认焦点）/ Menu（PillNeutral）。R = Retry；Esc / Start = Menu。hover/click 复用现有 wav。
- R / Retry 不换档、不 take Launch、不重新 configure_mode。Esc 在 Winner 开着回菜单，不开暂停。
- DebugOverlay 增补 `score` / `winner: on|off`。战斗 HUD 不加结算数字。
- 已删除 `ui/run_summary.gd` / `ui/run_summary.tscn`。Theme 的 RunSummary* / ClearedTitle 保留给 WinnerPage 用。

**当时不做：** 同机 2P、局域网、云同步、成就、排行榜、截图分享、中途续打、Autoload、分数滚动动画、全屏 HTML 结算、独立 BGM、`tr()`。

## Day 49（已完成）：局域网 2 客户端联机试水

两台进程、Host + Guest、同一沙盒、同一波次、每人自己的相机。不是分屏，不是 5 人，不是 Steam。Play / RecordSelector 单机路径与 Day 48 相同。局域网不写 `records.json` / `progress.cfg`。

- 入口是主菜单顶栏 `IconBarButton` 文案 `LAN`（Home 旁边），不是第四颗平行四边形。叠层互斥与 Settings / Profile / RecordSelector 相同。
- `ui/lan_overlay.gd`（`class_name LanOverlay`）：HOME / HOST / JOIN。Dimmer `Color(0,0,0,0.35)`，`UiAnim.enter_overlay` / `exit_overlay`。Host/Join 卡片 PillPink / PillNeutral。角色卡抄 RecordSelector EDITOR（`body_texture`，键盘 1/2）。滑杆 0–50 step 5 默认 20，0 显示 `Inf`。Guest LineEdit 默认 `127.0.0.1`。握手成功且 Host 按 Start 才 `start_lan`。Back / Esc 关掉 peer。
- ENet 端口 **17777**，`NET_PROTOCOL = 1`，最多 Host + 1 Guest；第三人立刻 `disconnect_peer`。发现只靠手打 IPv4。禁止 UDP 广播、房间浏览器、NAT、Steam、UPnP。
- Peer 活在 SceneTree 上，不活在 `GameLaunch`。进沙盒前不要 `peer.close()`。`NetSession._ready` 不负责建连；沙盒发现 `multiplayer_peer == null` 才回菜单。
- `arena/net_session.gd`（`class_name NetSession`）挂在 CombatSandbox 上，不是 Autoload。禁止 `MultiplayerSynchronizer` / `MultiplayerSpawner`。Guest→Host 不可靠 20Hz 输入；Host→Guest 不可靠 20Hz 快照（pawn / 敌人 / session / `_lan_paused`，不要 NodePath）。可靠通道：开火特效、offer 开关、winner、reset、回菜单。
- 只有一份 `player/player.tscn`。座位 2 运行时 `instantiate()`，出生 `(80, 0)`。每人只读本地输入；外端 pawn `set_remote_driven(true)`。`PlayerCamera.bind_player(local)`。HUD 左下 HP/枪是本地 pawn。共享一份 `RunSession` owned 与金币。
- Host 权威。Guest 不跑 Encounter / 敌人 AI / `RunSession.tick`。敌人 `bind_players`，追最近活着的人；两个都倒下才 DEAD。Guest 子弹只播 `rpc_fire_fx`（`collision_layer/mask = NONE`）。
- LAN 暂停禁止 `get_tree().paused = true`（会冻住 Guest RPC）。只用沙盒 `_lan_paused` + 暂停壳 `open(false)`。单机 PauseOverlay 仍是仓库里唯一允许暂停场景树的地方。
- LAN WinnerPage 可以 `present("", session, 0)`：档名 `LAN`，history `-`，NEW BEST 永远隐藏。`_record_progress_if_needed` 联机立刻 return。Guest 的 R 无效；Host Retry 才 `rpc_reset`。掉线回菜单不写盘。
- F1 / F2 / F3 / F4 / U 联机全禁用（含 Host）。DebugOverlay 增补 `net: off|host|guest` / `peer` / `seat` / `p2_hp`。
- **同机分屏明确不做**：不要第二份 keymap、不要 SubViewport、不要 `player_p2.tscn`。

**当时不做：** 房间浏览器、5 人、Steam、NAT/UPnP、按玩家分背包、云同步、Autoload。

## Day 50（已完成）：用现有档开 Host

Host 可以借一条本地档的角色和 `loop_goal` 开房。联机只借配置，不写 `records.json` / `progress.cfg`。Guest 仍自己选猪/鸡，看不见 Host 的档。Play / RecordSelector 单机路径与 Day 48/49 相同。`set_lan_loadout` 仍只传两个 `character_id` + `loop_goal`，不传 `record_id`。Autoload 仍为 0。

- `ui/record_card.gd`（`class_name RecordCard`，`extends Object`，全 static）：`make_main_card` / `format_loop_badge` / `resolve_body_texture`。LIST 与 LAN PICK 共用主卡。不含删除钮，不含 `pressed` 连接，禁止 `get_tree()`。
- `RecordSelector._make_main_card` 改调工厂后再自己 `connect` / 加删除钮。LIST / EDITOR / 删除确认 / 进沙盒语义不变。
- `LanOverlay` 四个状态：`HOME` / `PICK` / `HOST` / `JOIN`。仍一个叠层，不要第二个场景、不要 AcceptDialog。`open()` 永远进 HOME 并清掉选用中的档。
- HOME 点 Host：有档先 `USE RECORD`；空档列表跳过 PICK，直接 Custom HOST。不要在 HOME 铺 12 张档卡。
- PICK：`GameRecords.list_records()`（`created_at` 升序）。点卡选用该档。末尾 `+ Custom` / `Pick live, skip save`（不要 New Record 文案）。无删除按钮。超过约 4 张滚动。进场对可见主卡 `UiAnim` 错峰，不 tween 卡片 position。
- HOST 来自档位：角色两卡 `disabled` + `focus_mode=NONE`，滑杆 `editable=false`，标题下 OfferDesc 显示档名。角色只接受 `boar` / `chicken`，其它打回 `boar`。`loop_goal>50` 夹到 50，`<0` 打回 0。滑杆范围仍 0–50 step 5。
- Custom（`+ Custom` 或空档直进）：`_picked_record_id=""`，`_reset_character()`，滑杆默认 20，可改角色和终点，手感与 Day 49 相同，仍不写档。
- JOIN 不变：Guest 自选角色，只读显示 Host 的 goal。Guest 不选 Host 的档，也不读 `records.json`。
- Back / Esc：HOST 或 JOIN 关 peer 后回 HOME；来自档位的 HOST 回 PICK；PICK 回 HOME；HOME 才 `close()`。
- Start / `rpc_begin` / `set_lan_loadout` 仍三个标量。沙盒 `_is_lan()` → `_record_id=""`，Winner 档名 `LAN`，NEW BEST 永不亮，history 条数与 `best_score` 不变。

**当时不做：** 5 人、UDP 房间广播、房间浏览器、NAT/UPnP/Steam、同机分屏、把 LAN 局写入 records.json / progress.cfg、每人独立升级背包、WinnerPage 联机历史、Profile 升级。

## Day 51（已完成）：Play 分岔 Solo/Multi + 顶栏直达 + 大面板弹层

Play 先问 SOLO / MULTI。顶栏也能各自直达。档位列表 / 联机房 / 资料页换成接近全屏的 FloatingPanel，从下方弹起。LIST / PICK 改 2 列卡片网格。内部状态机、握手、写档规则与 Day 50 相同。Autoload 仍为 0。

- `UiAnim.enter_overlay`：content 先记下 `position.y` 为 `base_y`，放到 `base_y + 56`，再 `PANEL_MOVE_SEC` + `TRANS_BACK` / `EASE_OUT` tween 回去，和 modulate 淡入并行。ProfileOverlay / WinnerPage / PauseOverlay 已经把自己的 Panel/Column 当 content 传入，自动获得弹起。不要为了只改新叠层拆第二个函数。
- `ui/mode_choice_overlay.gd`（`class_name ModeChoiceOverlay`）：路由器，不套大面板。两张 OfferButton `240×200` 横排，文案 SOLO / MULTI。Dimmer `Color(0,0,0,0.35)`。信号只有 `solo_pressed` / `multi_pressed`。不要 AcceptDialog，不要记住上次选择。
- 顶栏：原 `LanButton` 改名 `MultiButton` 文案 MULTI；旁边新增 `SoloButton` 文案 SOLO，Home 右边成对出现。两者跳过 Mode Choice，直接 `_enter_solo_flow` / `_enter_multi_flow`。
- MainMenu 路由收拢：`_enter_solo_flow()` 关其它叠层后 `_record_selector.open()`；`_enter_multi_flow()` 关其它叠层后 `_lan_overlay.open()`。Play / Logo / `ui_accept` 打开 Mode Choice。`_any_overlay_open()` 含 Mode Choice；Esc 关掉它。
- RecordSelector / LanOverlay / ProfileOverlay 统一外壳：Dimmer + CenterContainer + FloatingPanel `1680×920` + Header（Title FloatingHeader + spacer + Back 120×44 OfferButton）+ Content（四边 margin 24）。原各视图的独立 CenterContainer 删除；表单类视图内部仍居中窄列；LIST / PICK 铺满的 2 列 GridContainer。卡片约 `780×140`，`+ New Record` / `+ Custom` 占一格。Back 仍是原来的 `_handle_back()`，只是挪到 Header。
- Theme：`FloatingPanel`（`sb_panel` 放大版，圆角 18、阴影同、content_margin 28）、`FloatingHeader`（字号 28，颜色同 ModeTitle）。styleboxes 走 `.tres`。
- Profile 只放大间距，6 个 Label 原样，2 列排。不要 Records Overview。SettingsOverlay 仍钉左边缘。

**当时不做：** Profile 新内容、Settings 大面板化、跨档总榜、5 人/房间浏览器、记住上次 Mode Choice、FloatingPage 场景类、改 Winner/Pause 业务逻辑。

## Day 52（已完成）：Profile 概览 + 可视化排行

ProfileOverlay 套上 Day 51 的 FloatingPanel `1680×920` 统一外壳，内容分两列：左 Stats（best loop / last loop / last kills / last gold / runs / last owned，原 6 个 Label 不改字段），右 RecordsColumn 用 `GameRecords.list_records()` 按 `best_score` 降序铺概览行。Header 新增 `RankButton`，点开单独的 `RecordLeaderboardOverlay`（同款 FloatingPanel 外壳）把全部档位画成 Top→Bottom 排行条。两个叠层都只读 `progress.cfg` / `records.json`，不写盘，不做跨设备排行。

- `ui/record_card.gd`（`class_name RecordCard`，全 static）新增 `make_overview_row`（Profile 用，名字+角色+loop badge+best score，无头像无删除）与 `make_rank_row`（排行用，rank 数字 + `RankBar` 进度条 + 名字 + 分数）。`make_main_card` 不变，三处调用点共用同一份布局逻辑。
- `ui/record_leaderboard_overlay.gd`（`class_name RecordLeaderboardOverlay`）+ `.tscn`：`_rebuild_rows()` 用第一名的 `best_score` 归一化所有 `RankBar` 宽度；空档显示 `NO RECORDS YET`。Rank 1/2/3 按 Gold/Silver/Bronze 上色，其余用默认色。
- Theme 新增 `RankBar`（ProgressBar variant）与 Gold/Silver/Bronze 三个颜色常量，走 `game_theme.tres`。
- `MainMenu`：`_profile_overlay.view_ranking_pressed` 连到 `_enter_leaderboard()`；`_leaderboard_overlay` 并入 `_any_overlay_open()` / `_any_menu_overlay_open()` / 所有互斥关闭链，行为与其余叠层一致（Esc 关、背景模糊压暗、音乐衰减）。

**当时不做：** 跨设备/云端排行、按角色筛选、导出分享、Profile 新增字段、Settings 大面板化（是 Day 53）。

## Day 53（已完成）：Settings 改版为 osu 式抽屉 + 渲染/UI/按键/删档选项

`SettingsOverlay` 从居中小面板改成钉左边缘的抽屉（`932px` 宽：左 `274px` Sidebar 图标导航 + 右侧一篇可滚动长文档），抄 osu! 的 `ScrollContainer` 惯性滚动（`DistanceDecayScroll`/`DistanceDecayJump` 指数阻尼）与搜索过滤。新增渲染分辨率、UI 缩放、垂直同步、抗锯齿、按键绑定、长按删除全部数据。Autoload 仍为 0，`records.json` / `progress.cfg` 结构不变。

- `GameSettings` 新增字段与持久化：`render_scale`（0.1–1.0，`user://settings.cfg` 落盘，渲染管线接线是 Day 54）、`ui_scale`（0.8–1.3，`apply()` 里直接写 `root.content_scale_factor`）、`vsync_mode`（`DisplayServer.window_set_vsync_mode`）、`msaa_index`（0–3 挡，写 `root.msaa_2d`）、`key_overrides`（8 个可重绑动作，默认值 + 方向键兜底，`_apply_key_bindings()` 整段重写 `InputMap`）。
- `ui/settings_section.gd`（`class_name SettingsSection`）：长文档里的一节，非当前节压暗到 0.8 alpha、hover 到 0.5，点击只负责把自己滚到视窗，不会立刻变亮（要等滚动稳定）。
- `ui/settings_nav_button.gd`（`class_name SettingsNavButton`）：左侧胶囊指示器随选中状态伸缩（`TRANS_BACK`），图标 + 文字随选中变色。四个图标 `ui/icons/{speaker,monitor,keyboard,database}.png`。
- `ui/hold_confirm_button.gd`（`class_name HoldConfirmButton`）+ `.tscn`：通用长按确认钮，`Fill` ColorRect 按住渐满，默认 `1.5s`，松手/失焦/鼠标移出立刻回零，只在满格瞬间发一次 `confirmed`，鼠标和触屏都吃。Data 分区用它做「HOLD TO DELETE ALL DATA」：确认后删 `progress.cfg` + `records.json`（`settings.cfg` 不动），`GameProgress.load_from_disk()` / `GameRecords.load_from_disk()` 立即重载。
- Controls 分区按 `GameSettings.REBINDABLE_ACTIONS` 动态铺一行一动作，点击进入监听态（文案变 `...`），按键冲突时短暂闪 `IN USE` 再还原，`Esc` 取消监听。
- 顶部搜索框按 `settings_search` meta 关键字过滤整节/整行，命中节的其余控件仍全部可见；未命中的 nav 图标压到 `alpha 0.28`。
- 渲染分辨率滑杆当前只落盘、只改 Label 文案（`RenderScaleHint` 明确写「Takes effect in a future update」），真正接 `SubViewport` 是下一步 Day 54。

**当时不做：** 渲染分辨率真正生效（SubViewport 管线）、手柄按键重绑、多组按键预设、UI 缩放之外的排版自适应、Settings 之外叠层跟进抽屉风格。

## Day 54（已完成）：渲染分辨率落地 SubViewport

`GameSettings.render_scale` 接到战斗渲染管线。`CombatSandbox` 根节点仍是 `Node2D`。世界进 `SubViewport`，UI / 纯逻辑留在主视口，避免 HUD 和暂停菜单被降采样。

场景层级：

```text
CombatSandbox (Node2D)
  ViewportContainer (SubViewportContainer, stretch=true)
    GameViewport (SubViewport)
      World (Node2D，无脚本)
        Floor, Walls, Enemies, Projectiles, EnemyProjectiles,
        SfxPool, HitSparks, DeathShards, Players, Player,
        PlayerCamera, AimReticle
  CombatMusic, EncounterPhrases, RunSession, UpgradeApplier, NetSession
  Hud, WinnerPage, UpgradeOffer, ShopOffer, DebugOverlay, PauseOverlay
```

`_apply_render_scale()` 时机（不广播、不新增 Autoload，直接读 `GameSettings.get_render_scale()`）：

1. `_ready()`：`GameSettings.apply()` 之后、`size_changed` 已连接
2. `Window.size_changed`（拖窗口 / 切全屏）
3. `PauseOverlay.resumed`（暂停菜单里拖完滑杆，Continue 关闭时生效；不逐帧跟滑杆）

尺寸合同：

- Godot 4.6：`SubViewportContainer.stretch = true` 时禁止手改 `SubViewport.size`。所以把容器 `.size` 设成 `Window.size * render_scale`（真像素缓冲），再用 `.scale` 撑到根视口 `get_visible_rect().size`（`canvas_items` + `expand` 的逻辑画布，含 UI scale）。直接把容器设成 `Window.size` 会黑边。
- `GameViewport.size` 由 stretch 自动等于容器 size。50% 就是像素变少、画面变糊。
- `size_2d_override` = 同一份逻辑画布、`size_2d_override_stretch = true`。SubViewport 没有 Window 的 content_scale；不重写 2D 尺寸的话，降分辨率会变成拉近而不是变糊。`player_camera.gd` / `player_input.gd` / `aim_reticle.gd` 不动。
- `GameViewport.msaa_2d` 抄根视口，Day 53 抗锯齿仍打在世界上。
- 联机 Host/Guest 各用本地 `render_scale`，不进快照。
- `DebugOverlay` 默认隐藏；debug 构建按 **F9** 切换显示（联机也可用，不进 `[input]`）。隐藏时不刷新文案。

**当时不做：** 逐帧动态分辨率、分辨率过渡动画、每个 UI 面板单独可调分辨率、3D 相关字段、移动端专属预设。抗锯齿 / UI 缩放 / 垂直同步 / 按键绑定仍走 Day 53 的 `GameSettings.apply()`，本 Day 不改它们的设置项。

## Day 55（已完成）：FlatBold 主题令牌 + OfferButton 换皮

只改 `ui/game_theme.tres`。不改任何 `.tscn` 节点结构、不改任何 `.gd` 交互逻辑，不碰 `TopBar` 的 `menu_shear.gdshader`。

新增 4 个 `StyleBoxFlat`：`sb_flat_card_normal` / `sb_flat_card_hover` / `sb_flat_card_pressed` / `sb_flat_card_disabled`。规格：圆角统一 `6`（对齐顶栏「方正」感，卡片大面积不用直角）、不透明纯色、无 `shadow_*`、无 `border_width_*`。四态底色分别来自旧 `sb_card_*` 把 alpha 拉到 `1`（hover/pressed 的描边改由色块本身的色差承担）。`sb_focus_card` 原样保留（键盘/手柄焦点框是功能反馈）。`OfferTitle/fonts/font` 指向已有的 `font_bar_bold`（`SystemFont` weight 700，TopBar 同款）；`OfferDesc` 字重不动。`OfferButton` 四态切到 `sb_flat_card_*`，`font_color` 不变。旧 `sb_card_normal/hover/pressed/disabled` 留在文件里，`FloatingPanel` / 胶囊按钮继续间接用同一套旧色调。

一次换皮辐射所有挂了 `OfferButton` 的卡片：ModeChoiceOverlay / LanOverlay / ProfileOverlay / RecordLeaderboardOverlay / RecordSelector / SettingsOverlay / ShopOffer / UpgradeOffer。

**当时不做：** 不碰 `FloatingPanel` / `sb_panel` 背景、不碰 `PillPink` / `PillNeutral` / `PillRed`、不给 `OfferButton` 加 shear（卡片段落多，切变只留在 TopBar 短文案按钮上）、不改叠层 hover/press 动画时长或 `UiAnim` 缓动、不改 HUD / PauseOverlay 的 TopBar 自身样式、不新增 Autoload。

## Day 56（已完成）：大面板 + 胶囊 CTA 换成 FlatBold

只改 `ui/game_theme.tres` 与本 README。不改任何 `.tscn` 节点树、不改任何 `.gd` 交互、不改按钮尺寸/文案/信号。`sb_flat_card_*` 颜色/圆角/margin 不改。禁止脚本 `StyleBoxFlat.new()`。

新增 `sb_flat_panel`：`content_margin` 四边 28（抄 `sb_floating_panel`），`bg_color = Color(0.13, 0.11, 0.155, 1)`（旧面板 RGB，alpha 从 0.97 拉到 1），圆角 6，无 `shadow_*`、无 `border_width_*`。`FloatingPanel` 与 `RunSummaryPanel` 共用这一份，避免两套背景。Winner 的 20 边距会跟着变成 28，可接受。

新增 9 个 `sb_flat_pill_*`（pink / neutral / red × normal / hover / pressed）+ `sb_flat_pill_disabled`。左右 margin 34、上下 12；底色一字不改抄旧 `sb_pill_*` 不透明色；圆角 6，无发光阴影。disabled 底色抄 `sb_card_disabled` 但不透明。`PillPink` / `PillNeutral` / `PillRed` / `MainMenuButton` 四态切到新皮，`styles/focus` 仍 `sb_focus_pill`。四者 `fonts/font = font_bar_bold`，字号仍 22，`font_color` 不变。`FloatingHeader` / `ModeTitle` 指向 `font_bar_bold`（字号/描边不动）。`OfferTitle` 已在 Day 55 加粗，不再改。`WinnerScore` / `OfferDesc` / `RunSummaryBody` 字重不动。

旧 `sb_panel` / `sb_floating_panel` / `sb_pill_*` / `sb_card_disabled` 留在文件里对照。`sb_focus_card` / `sb_focus_pill` 原样保留（焦点框是功能，不是装饰）。

辐射面（禁止为它们改 tscn，theme variation 自动跟上）：

- FloatingPanel：RecordSelector / LanOverlay / ProfileOverlay / RecordLeaderboardOverlay
- RunSummaryPanel：WinnerPage 主面板、RecordSelector 删除确认条
- PillPink：RecordSelector Confirm、LanOverlay Host/Start/Connect、WinnerPage Retry
- PillNeutral：LanOverlay Join、WinnerPage Menu
- MainMenuButton：主菜单 Settings / Play / Exit 三颗（若场景挂了这个 variation）
- PillRed：本仓库 tscn 可能还没实例，variation 已换，避免以后用到仍是旧胶囊

ModeChoice 两张卡与删除确认 Yes/No 仍是 OfferButton（Day 55 皮）。主菜单 Logo「PLAY」是 LogoButton，不是 Pill。Settings 抽屉外观与 Day 53 相同。TopBar 不动。

**当时不做：** 手柄/Joypad 按键重绑、Settings 抽屉换皮、OfferButton 再调颜色/圆角、TopBar / LogoButton / `menu_shear`、动态行 UI 缩放（RecordCard / 设置行）、新 InputMap action、改 GameSettings / `settings.cfg`。

## Day 57（已完成）：右摇杆即时瞄准

回中 keep last，出 0.12 当帧对准，无转向平滑。左摇杆仍是模拟走速（死区 0.25 + 径向缩放）。键鼠瞄准仍是鼠标世界坐标，一个公式都没改。Autoload 仍为 0。不改 `player.gd` / `player_camera.gd` / `aim_reticle.gd` / `player_motor.gd`，不改四把枪/敌人身份、Motor、look_ahead、theme.tres、GameSettings、`settings.cfg`。

- `STICK_DEADZONE=0.25` 只给左摇杆走速和 `_joy_wants_control` 的左杆判定。
- 新增 `AIM_STICK_DEADZONE=0.12`：只滤右摇杆静止漂移。「动一点」必须出这圈。瞄准没有半行程：出死区就是单位向量，模长不参与瞄准。
- 删除 `AIM_TURN_SMOOTHING` 与 `_turn_aim_toward`。禁止 `lerp_angle` / 任何转向平滑。不是八向吸附：360° 连续方向，拨哪指哪。
- `static func map_aim_stick(raw) -> Vector2`：模长 < 0.12 → `Vector2.ZERO`；否则 `raw.normalized()`。这是 Day 81+ 虚拟摇杆的合同：把「指尖相对基座 / 基座半径」（建议已 clamp 到长度≤1）丢进本函数，ZERO 则 keep last，非零则当帧朝向。本 Day 不写触屏、不建 `touch_input_driver.gd`。
- `_read_aim_stick` 只 `_read_stick` 再 `return map_aim_stick(raw)`。
- `_joy_wants_control` 右杆判定改为 `raw.length() >= AIM_STICK_DEADZONE`，与瞄准同一圈，避免 0.12～0.25 之间已经在瞄准却认不成手柄。
- `_update_from_joy`：aim 为零 → `_keep_last_aim()`（准星/朝向停住，不弹回世界右方，不清零 `aim_vector`）；否则 `aim_vector = aim`（已是单位向量）。`mouse_world_position` 仍 = 玩家 + aim * 140。
- 右摇杆偏转绝不置 `fire_held`。开火仍只认 RT≥0.45 或 RB。Dash 仍是 A，切枪仍是十字键。
- `apply_remote_frame`：Guest 本地已产出单位 `aim_vector`；Host 傀儡继续 `aim.normalized()` / 零则 keep last，远端不再套一层平滑。20Hz 跳可以接受。
- DebugOverlay（仅 debug 构建，F9）：手柄占用时在 `char:` 附近加 `aim: rest` / `aim: live`（`map_aim_stick` 结果是否为零）。键鼠不显示这行。不画摇杆圆。

**当时不做：** 虚拟摇杆 UI / TouchControls / 触屏 CanvasLayer、手柄按键重绑 Settings 页、新 InputMap action、改 GameSettings / `settings.cfg`、右杆开火。

## Day 58（已完成）：Settings 抽屉换成 FlatBold

侧栏 / 面板底色 / SettingsHeader / 导航选中条对齐顶栏纯色 + 粗体。抽屉仍从左侧滑入，仍是长文档 + 左侧锚点，不是 Day 51 那种居中 FloatingPanel。滚动、搜索、键盘重绑、长按删档逻辑不动。Autoload 仍为 0。禁止脚本 `StyleBoxFlat.new()`。

- `SettingsHeader`：`font_color = Color(0.97, 0.94, 0.96, 1)`（不再粉），`fonts/font = font_bar_bold`，字号仍 22，描边仍 2 / `Color(0, 0, 0, 0.4)`。
- 侧栏 `Sidebar` / `HeaderBg`：`Color(0.1, 0.1, 0.1, 1)`，对齐 `sb_bar_panel`。正文 `Fill`：`Color(0.13, 0.11, 0.155, 1)`，对齐 `sb_flat_panel`。`HeaderBg.modulate.a` 仍由开合动画控制。
- 导航指示器：保留内嵌 `StyleBoxFlat`（不新建 `SettingsNavIndicator` variation），`bg_color` 仍洋红 `Color(1, 0.4, 0.67, 1)`，圆角 6、宽 6px。高度动画 `INDICATOR_ACTIVE=22` / `INACTIVE=4` 保留。不是细胶囊。
- `SettingsNavButton`：`COLOR_HOVER = Color(0.9, 0.9, 0.9, 1)`；Hover ColorRect 静止 `Color(1, 1, 1, 0)`，hover `alpha=0.08`。Caption 去掉 `theme_override` 色，走 `SettingsNavCaption`（`font_bar_bold` 字号 22，字色交给脚本 `modulate`）。
- `SettingsSection`：Separator `Color(0.2, 0.18, 0.22, 1)`；Dim `Color(0.1, 0.1, 0.1, 0.8)`。ExpandableHeader/Title 仍是 `FloatingHeader` + `font_size=40`。

**当时不做：** Joypad / 手柄按键重绑、虚拟摇杆 / TouchControls、改滚动惯性 / 搜索过滤 / 键盘重绑监听、改 HoldConfirmButton 时长、TopBar / LogoButton / `menu_shear`、改 GameSettings / `settings.cfg`、新 InputMap action。

## Day 59（已完成）：可见区 fit，大面板和动态行完整可见

`ui_scale` 仍只写 `root.content_scale_factor`（0.8–1.3）。可见逻辑尺寸变小时，大面板和两列卡片按 `get_visible_rect()` 收缩，禁止再乘 `ui_scale`（那会双倍放大）。`ui_scale=1.0` 且窗口够大时，面板仍约 1680×920、卡片仍约 780×140。Autoload 仍为 0。不改 `GameSettings.apply()` 的缩放语义，不克隆 theme 去改 `font_sizes`。

- 新增 `ui/ui_fit.gd`（`class_name UiFit`，`extends Object`，全 static，抄 `UiAnim`）：`visible_size` / `panel_size` / `card_size` / `portrait_px`。`panel_size` 上限 preferred、下限 640×480，四边留 48。卡片列宽 = `(panel_w - 104 - 16*(columns-1)) / columns`，高度按 140/780 钳在 96～160。头像 `96 * (card.x / 780)`，钳在 64～96。
- `RecordSelector` / `LanOverlay` / `ProfileOverlay` / `RecordLeaderboardOverlay` 的 `open()` 写 `_panel.custom_minimum_size = UiFit.panel_size(self)`。tscn 里 1680×920 / 780×140 留作 1.0 默认。
- `RecordCard.make_main_card(record, card_size, portrait_px)` 必须由调用方传入尺寸，工厂里不再写死、不 `get_viewport()`。`make_overview_row` / `make_rank_row` 不设死宽；`RANK_WIDTH` / `RANK_BAR_HEIGHT` 保留。删除钮仍 64。
- 网格默认 2 列。只有两列列宽会小于 **360** 才临时改 1 列（`panel_w < 840` 才会触发）。1920×1080 上 `ui_scale` 0.8–1.3 仍是 2 列。
- `SettingsOverlay._on_ui_scale_changed` 在 `apply()` 与改 Label 之后立刻 `_apply_drawer_layout()` / `_fit_sections()` / `_layout_scroll()`。抽屉仍按 `SIDEBAR_RATIO` / `PANEL_OF_REMAINDER` 占左半，不是 FloatingPanel。绑键行仍 `160×44`。
- 其它叠层只在 `open()` 按当时可见区算一次，不监听滑杆。

**当时不做：** Joypad / 手柄按键重绑、虚拟摇杆 / TouchControls、商店深化、跟班、TopBar / LogoButton / `menu_shear`、改 `GameSettings` / `settings.cfg`、新 InputMap action、WinnerPage / Pause 业务。

## Day 61（已完成）：两种跟班上场，F8 debug，上限 1

跟班能在单机沙盒里生成、跟随、自动攻击、被打死。商店仍只卖 10 张 `UpgradeDef`。`ShopOffer` 不出现跟班卡。跟班不写入 `owned_ids` / `records.json` / `progress.cfg`。Autoload 仍为 0。没有第 6 物理层，没有 `companion.png`，没有技能栏，没有主动技能，没有 LAN 同步跟班，没有跟班 HUD 血条。

- **数据**：`data/companion_def.gd`（`class_name CompanionDef`）。`kind` 只有 `MELEE` / `RANGED`。字段含 `shop_cost`（本阶段不扣钱，留给 Day 62）、`base_max_hp` / 移速 / 加速度 / hurtbox / `body_scale` / `body_texture` / `body_modulate` / 跟随距离 / 仇恨范围 / 接触伤 / 射速 / 弹速 / 弹伤 / `i_frame_sec`。禁止 `skeleton_scene`，禁止主动技能字段。
- **目录**：`data/companion_catalog.gd` + `companion_catalog.tres`，抄 `CharacterCatalog`：`get_count` / `get_all` / `get_by_id`；重复 id `push_error` 并跳过后到的；找不到返回 `null`。不是 Autoload，禁止 `get_tree()`。
- **两条 .tres**：`data/companions/guard.tres`（近战，贴图 `images/melee.png`，青染 `Color(0.45, 0.85, 1, 1)`，HP 48，接触伤 6，`shop_cost=40`）；`data/companions/gunner.tres`（远程，贴图 `images/ranged.png`，同色，HP 32，`fire_interval=0.70`，弹伤 4，`shop_cost=50`）。`body_scale=(0.042, 0.042)`。
- **场景**：新目录 `companions/`。`CompanionBase` 是 `CharacterBody2D`，**禁止** `extends EnemyBase`（否则玩家弹会打中、死亡会给金币/XP、句读会当敌人清场）。`collision_layer = MASK_PLAYER`，`collision_mask = MASK_WALL`。朝向只 FLIP，抄 `FacingContract` 的 MELEE/RANGED native 标志，不要 SPIN。
- **跟随 / 索敌**：没有可打目标时站在玩家 `aim_vector` 身后 `follow_distance`（aim 为零则 `Vector2.LEFT`）。有存活且非 reserve/defeated/entering 的敌人、且该敌人离玩家 `< aggro_range` 则 seek：近战贴到接触，远程保持约 180px。敌人仍只 `bind_players`，不追跟班。敌人列表由沙盒传入，禁止 `get_nodes_in_group`。
- **攻击**：`MeleeCompanion` 的 `ContactArea` layer=`NONE` mask=`ENEMY`，碰到 `EnemyBase` 造成 `contact_damage`，不打 Player。`RangedCompanion` 朝目标开火，`reset(..., is_player_shot=true)`，走现有玩家弹池；池满打不出，不删飞行中的弹。不要第二套弹池。
- **受击 / 死亡**：`HitReaction` 塌缩 + 变灰留场，不 `queue_free`、不给 XP/gold、不喷 `DeathShard`。i-frame 用 `def.i_frame_sec`。死亡 `set_physics_process(false)`、ContactArea `monitoring=false`、碰撞层 `MASK_NONE`。敌人弹 `_damage_player_side`：`as Player` 走现有；否则 `has_method("apply_damage")` 且 `is CompanionBase` 才 `apply_damage`。近战接触伤（含冲锋/Boss 的 Player 检测路径）同样能打到跟班。玩家弹 mask 仍是 ENEMY|WALL，打不中跟班。
- **沙盒**：`World` 下空节点 `Companions`。实例进这里，不要挂 CombatSandbox 根（会逃出 SubViewport）。`var _companion: CompanionBase = null`。一局最多 1 只。debug 构建、非 LAN、playing、未暂停/未开商店/三选一/Winner 时 **F8** 循环：无 → 近战 → 远程 → 清掉 → 近战…。已有一只时换成另一种先 `queue_free` 旧的。出生点 = 玩家位置 + `Vector2(-48, 24)`，与墙重叠则 `Vector2(48, 24)`。LAN / Guest 不实例跟班。F8 仍走 `_try_debug_hotkeys` 开头的 `_is_lan()` return，不为跟班开 LAN 口。
- **清理**：R / Retry / `_reset_sandbox` / 回菜单必须 `_clear_companion()`。玩家死亡不必立刻杀跟班。句读换场 `hold_in_reserve` 时跟班不停（它不是句读单位）；不要把跟班放进 `_enemies`。
- **Overlay**：仅 debug、F9 显示。增补 `companion: off|guard|gunner` 和 `companion_hp: n/m`（没有则 `-`）。不要第五块 HUD，不要战斗 HUD 血条。

**当时不做：** 商店卖跟班 / 改 `ShopOffer` 信号类型 / 改 `draft_offer`、主动技能 / 技能栏 / 冷却 UI、第三种跟班、跟班 HUD 血条、新物理层、新 PNG、Joypad 重绑、虚拟摇杆、LAN 快照同步跟班、Autoload、`Engine.time_scale`、`reload_current_scene`、改四把枪/敌人 `_ready` 身份数字、Motor / 相机 / 击退公式 / hitstop / XP / gold / 加压公式、HUD 锚点、算分公式、`records.json`、10 张卡 `value`、TopBar / LogoButton。

## Day 62（已完成）：厚血远程、买时选枪、AI 绕圈/LOS，删近战

跟班只留远程 Gunner，比玩家更厚更快。P8 商店可出跟班卡，点了先进选枪再扣 70 生成。跟班用四把库存真枪的 `fire_at`，不踢玩家镜头。AI 三态：拴绳归队 / 侧翼跟随 / 绕圈射击，墙后不开火。LAN 仍不出跟班卡、不 spawn 跟班。Autoload 仍为 0。没有跟班 HUD、没有主动技能、没有 LAN 同步跟班、跟班不吃玩家升级。

- **删近战**：去掉 `MeleeCompanion` / `guard.tres` 及目录条目。场景树不再出现 Guard。
- **Gunner 锁死数字**：HP 140、移速 520、加速度 3000、hurtbox 14、`body_scale=(0.048, 0.048)`、跟随 72、仇恨 480、`shop_cost=70`、接触伤/射速/弹速/弹伤全 0、i-frame 0.35。开火数字全部来自所选 Weapon。
- **持枪**：`RangedCompanion` 动态 `new` 四把枪脚本，`bind_projectile_pool` 玩家弹池，`set_active(false)` 永不走 `WeaponHost` / `_process`。`apply_weapon(0..3)`：Pistol / Shotgun / Rifle / Smg。非法打回 0。`Weapon.fire_at(origin, aim)` 抄取弹/散布/弹速/伤害，不读 `PlayerInput`，不 `notify_shot_fired`。池不够返回 false，不删飞行中的弹。
- **AI**：`CATCH_UP` / `FOLLOW` / `ENGAGE`。离玩家 > 240px 丢战斗全速归槽；槽位在玩家身后 56 且 `aim.orthogonal()` 侧 52，不到枪口正前方。ENGAGE 径向保持 190±40，切向永远 `STRAFE_SPEED=220`，禁止速度清零。撞墙或每 1.1s 翻侧移。目标粘性：aim 方向优先，离玩家 > aggro+80 才丢。多只 Gunner 优先锁定还没人打的敌人；人比怪多才叠火。开火仅 ENGAGE、距离 90～460、LOS 打墙则本帧不打。朝向只 FLIP。
- **商店**：`ShopCard` 分 `UPGRADE` / `COMPANION`。`draft_offer` 语义不变，只给句读三选一。新增 `draft_shop_cards`：离线且没有活跟班时第三张固定 Gunner，否则三张升级。LAN 调用方仍 `draft_offer` 包成升级卡。`ShopOffer` 两态 `BROWSE` / `PICK_GUN`，不要 `AcceptDialog`。跟班卡钱不够 disabled；点开四把枪，Esc/Back 回三张卡金币不变。选枪后信号 `picked_companion`，沙盒扣 70 再 spawn，不 `try_grant`、不写 `owned_ids`。
- **上限 10**：活着的 Gunner `< 10` 才出跟班卡。留尸不占名额，可再买补满。Pack L（restore all HP）同时回满所有活着的 Gunner，不复活尸体。
- **F8**：活着 < 10 再刷一只手枪 Gunner；满 10 后循环最后一只的 Pistol→Shotgun→Rifle→Smg，再按清掉全部。暂停/商店/三选一/Winner 无效。Overlay：`companion: off|n/10`，`gun` 为第一只活着的枪名。

**当时不做：** 跟班 HUD 血条 / 主动技能 / 技能栏 / 冷却 UI、LAN 快照同步跟班、跟班吃玩家 UpgradeApplier、第三只跟班、消耗品、Joypad 重绑、虚拟摇杆、Autoload、`Engine.time_scale`、`reload_current_scene`、改四把枪/敌人 `_ready` 身份数字、Motor / 相机 / 击退公式 / hitstop / XP / gold / 加压公式、HUD 锚点、算分公式、`records.json`、10 张卡 `value`、TopBar / LogoButton。

## Day 63（已完成）：目录商店 + 消耗品 + 连买

P8 从抽 3 买 1 改成目录商店。`ShopOffer` 换成 `FloatingPanel`：左状态栏、右 3 列货架。离线金币够就连买，点 Continue 才关店进下一轮。LAN 可以换这层皮，协议仍是 3 张升级买 1 张即关。Autoload 仍为 0。消耗品不写 `owned_ids` / `records.json` / `progress.cfg`。

- **消耗品**：`ConsumableDef`（`HEAL_FLAT` / `HEAL_FULL` / `I_FRAME`）+ `ConsumableCatalog`，抄跟班目录。三条 `.tres`：Pack S 20 回 40 HP、Pack L 45 回满、Stim 35 给 1.5s 无敌且本店只能买一次。价格在 def 上，不进 `SHOP_COSTS`。
- **ShopCard**：`Kind` 增加 `CONSUMABLE`；`for_consumable`；`get_cost` 读 `def.shop_cost`。
- **RunSession**：`draft_offer` 语义不变，句读三选一仍只吃 `UpgradeDef`。`draft_shop_cards` 留给 LAN 包装。离线 P8 走 `list_shop_catalog()`：消耗品（目录顺序）→ 未拥有或 stackable 的升级（目录原序）→ 活着的 Gunner `< 10` 时最后一张 Gunner。`bind_consumable_catalog`；`restart` 不清目录引用。
- **PlayerHealth**：`heal(amount)` 返回实际回复；`apply_bonus_i_frame(sec)` 只抬 `_i_frame_left_sec`，不改 `i_frame_sec` 底值、不闪白。Pack L 走玩家 `fill_hp()`，同时回满所有活着的 Gunner，不复活尸体。
- **ShopOffer**：`Root/Dimmer` + `Center/Panel`（`FloatingPanel`）。`UiFit.shop_panel_size` 在 `panel_size` 后再钳到 1480×820。禁止 `CARD_SIZE * ui_scale`，禁止脚本 `StyleBoxFlat.new()`。货卡从 `shop_item_card.tscn` instantiate，不要写死 Card0/1/2。BROWSE 点卡购买，1/2/3/4 不再选货。PICK_GUN 仍店内四把枪，Continue 改 Back，Esc/Start/Back 回货架不扣款。钱不够 / Pack S 玩家满血 / Pack L 玩家和活着的 Gunner 都满血 / 本店已买 Stim 的卡 disabled。第一次 `present` 仍 `UiAnim.enter_overlay`（dimmer+panel，不对货卡错峰 scale）；买完 `refresh_stock` 无进场动画。信号新增 `picked_consumable`。
- **沙盒**：离线买升级/药/跟班后 `_refresh_open_shop()`，不关店。Continue / Skip 仍关店 + `_finish_loop_after_shop`。Esc 仍 `cancelled` → 暂停，不关店。LAN `_draft_shop_cards_for_loop` 仍 `draft_offer(3)`，无药无 Gunner；买一张或 Continue 两边关店。Guest 仍 `send_try_pick`。选枪成功扣 70 spawn，不 `try_grant`，回到 BROWSE 继续逛。
- **Overlay**：debug 增补 `shop: catalog|lan3|closed`。不要第五块 HUD，不要战斗跟班血条。

**当时不做：** 主动技能 / 技能栏 / 冷却 UI、战斗 HUD 跟班血条、LAN 同步药和跟班、新贴图、Joypad 重绑、虚拟摇杆、第三只跟班、跟班吃玩家 UpgradeApplier、改 Gunner 140/520/70、改四把枪/敌人身份数字、Motor / 相机 / 击退 / hitstop / XP / gold / 加压、HUD 锚点、算分公式、`records.json`、10 张卡 `value`、TopBar / LogoButton、改 UpgradeOffer 三张卡合同、Autoload、`Engine.time_scale`、`reload_current_scene`。

## Day 64（已完成）：目录商店手感——错峰、复用、金币滚动、四态音效

目录商店摸起来像已经做好的菜单。连买 / 关店 / LAN 三张买一张即关 / PICK_GUN 选枪 / Esc→暂停全部保持 Day 63。Autoload 仍为 0。没有新 wav、没有脚本 `StyleBoxFlat.new()`、没有新 Theme 色。

- **进场错峰**：`present` 仍 `UiAnim.enter_overlay(dimmer, panel)`；货卡另做 `0.9→1` 弹出，`delay = min(index, 5) * 0.04`，超过 6 张不再加长。`refresh_stock` 禁止重放进场、禁止整排错峰。
- **货架复用**：卡身份 `kind + id`（`set_meta`，按下不再 `bind(i)`）。还在的卡原地 `_fill_item_card`；刚买仍在架上的（Pack S/L、stackable、已买 Stim）punch `1.06→1.0`；下架先 `CARD_OUT`（scale 0.9 + alpha 0，格子占位到 tween 结束）再 `queue_free`。禁止「张数不同就清空重建」。
- **金币 / 条**：`RunSession.get_gold()` 仍瞬时扣。ShopOffer 另存 `_displayed_gold`，进场 snap，买成功 OutQuint 滚 0.28s，文案 `gold  %d` 取 `roundi`。HP/XP 数字仍瞬时；ProgressBar 开店期间 `BAR_SMOOTHING=10` approach，进场那一帧 snap，低血阈值仍 20。
- **四态音效**（现有 wav）：未灰的卡/枪/Continue hover=`ui_hover.wav` + scale 1.02；成功买/选枪/Continue click=`ui_click.wav`；PICK_GUN Back/Esc 以及 BROWSE Esc back=`ui_back.wav`；买不起/满血药/已买 Stim error=`click.wav`。同一帧同一种最多 1 次。灰卡不 hover、不放大，`Button.disabled` 不用，点下去出 error。
- **PICK_GUN**：逻辑 `_view` 仍瞬时；货架 0.12s 淡出（mouse_filter 当帧关），GunRow 0.18s 淡入 + 四把枪 0.04 错峰。货架和枪行叠在同一格，避免 HBox 对半分。Back 反向。Continue 先 Click 再 `skipped`。
- **UiAnim**：新增 static `punch_scale` / `fade_modulate`。`CARD_STAGGER_SEC=0.06` 不动（UpgradeOffer 三张卡）。Tween 一律 `TWEEN_PAUSE_PROCESS`。

**当时不做：** 主动技能 / 技能栏 / 冷却 UI、战斗 HUD 跟班血条、LAN 同步药和跟班、新 wav、UpgradeOffer 音效、Joypad 重绑、虚拟摇杆、改 `list_shop_catalog` / 价格 / Pack / Stim / Gunner 数字、改四把枪/敌人身份、Motor / 相机 / 击退 / hitstop / XP / gold / 加压、HUD 锚点、算分公式、`records.json`、10 张卡 `value`、TopBar / LogoButton、Autoload、`Engine.time_scale`、`reload_current_scene`、WinnerPage 分数滚动。


## Day 65（已完成）：句读三选一 hover/click/back

UpgradeOffer 三张卡摸起来像 Day 64 商店卡。布局、抽卡、LAN 协议不变。仍是居中三张 + 底栏 `1 / 2 / 3`，进场 `UiAnim.CARD_STAGGER_SEC=0.06` 错峰 `0.9→1`。Autoload 仍为 0。没有新 wav、没有脚本 `StyleBoxFlat.new()`、没有 Skip、没有目录化、ShopOffer 未改。

- **三态音效**（现有 wav）：未点选的卡 `mouse_entered` / `focus_entered` hover=`ui_hover.wav`；点选一张（鼠标、1/2/3、十字左/上/右）click=`ui_click.wav`；Esc / Start back=`ui_back.wav` 再 `cancelled`（现有暂停，不关卡、不当 Skip）。同一帧同一种最多 1 次（`Engine.get_process_frames()` 门闩，抄 ShopOffer）。没有 Error，三张永远可点，不用 `Button.disabled`、不变暗。
- **动效**：hover scale `1.02` / `0.12s`；点选 punch `1.06` / `0.12s`（`UiAnim.punch_scale`）。`pivot_offset = custom_minimum_size * 0.5`。禁止 tween position。punch 只装饰：Click → 选中卡 punch → 立刻 `picked.emit`，不等 punch 结束再 grant。另外两张不自己 fade（整层 `exit_overlay` 0.15s 一起淡）。hover 进行中若开始 punch，杀掉该卡 hover tween。
- **present**：开卡把三张卡 scale 收到 1、清 hover/punch tween，避免上次的 1.02 残留；然后仍走 `enter_overlay(dimmer, center, _cards)`。
- **场景**：`upgrade_offer.tscn` 加 `HoverSfx` / `ClickSfx` / `BackSfx` 三个 `AudioStreamPlayer`，`GameAudio.load_wav`，不要 Autoload 音效总线。Card0/1/2 仍 `280×180`，Hint 仍 `1 / 2 / 3`。

**当时不做：** FloatingPanel 换皮、Skip/金币/消耗品、目录化、新 wav、ShopOffer 再改、主动技能 / 技能栏 / 冷却 UI、战斗 HUD 跟班血条、LAN 扩协议、改 `draft_offer` / `try_grant` / 句读 acknowledge / `pending_level` / `rpc_offer_open` 三元组、改四把枪/敌人身份、Motor / 相机 / 击退 / hitstop / XP / gold / 加压、HUD 锚点、算分公式、`records.json`、10 张卡 `value`、TopBar / LogoButton、Autoload、`Engine.time_scale`、`reload_current_scene`、WinnerPage 分数滚动。

## Day 66（已完成）：句读三选一收成 FloatingPanel 小面板

UpgradeOffer 换成和商店 / Profile 同一族的 `FloatingPanel` 小面板。句间与升级共用同一块面板、同一个标题 `PICK ONE`。抽卡、点选、LAN 协议、Day 65 音效/hover/punch 全部保留。Autoload 仍为 0。没有新 wav、没有脚本 `StyleBoxFlat.new()`、没有 Skip、没有目录化、ShopOffer 未改。

- **场景**：`Root/Dimmer` + `Center/Panel`（`FloatingPanel`，`custom_minimum_size=1040×380`）。`Column` 顶栏 `FloatingHeader` 文案 `PICK ONE`，其下三张 `OfferButton` 仍 `280×180` 居中，底栏 Hint 仍 `1 / 2 / 3`。不要状态栏、不要金币、不要 Continue、不要第四张卡。`HoverSfx` / `ClickSfx` / `BackSfx` 仍挂在 CanvasLayer 根上。
- **UiFit**：新增 `OFFER_PANEL_MAX=1040×380`、`OFFER_PANEL_MIN=920×300`、`offer_panel_size`（leftover 减 `PANEL_MARGIN` 后各自 `clampf` 到 MIN/MAX，**禁止**走 `_fit_in`，否则 `MIN_PANEL_HEIGHT=480` 会把小面板撑成竖条空商店）。`apply_floating_panel` 增加可选 `min_size`，默认仍 `640×480`；Shop / Profile 调用语义不变。
- **进场**：`present` 先 `_fit_panel` 再 `_refresh_cards` / `_reset_card_motion`，然后 `UiAnim.enter_overlay(self, _dimmer, _panel, _cards, true)`。不要再对全屏 `_center` 做进场。`close` 仍 `exit_overlay` 0.15s。三张卡错峰仍 `CARD_STAGGER_SEC=0.06`。视口 `size_changed` / `Root.resized` 走 `UiFit.connect_refit`。
- **输入 / 信号**：1/2/3、十字左/上/右、Esc / Start、`picked` / `cancelled` 一字不改。点选仍瞬时 emit；punch 只装饰。三张永远可点，不要 Error、不要 `Button.disabled`、不要金币。

**当时不做：** 第二张地图、主动技能 / 技能栏 / 冷却 UI、LAN 同步跟班/药、Skip / 金币 / 消耗品 / 第四张卡、目录化、新 wav、改 ShopOffer / `list_shop_catalog` / Pack / Stim / Gunner 数字、改 `draft_offer` / `try_grant` / 句读 acknowledge / `pending_level` / `rpc_offer_open` 三元组、Joypad 重绑、虚拟摇杆、Autoload、`Engine.time_scale`、`reload_current_scene`、WinnerPage 分数滚动。

## Day 67（已完成）：同一沙盒两套碰撞布局 Yard / Pit

同一份 CombatSandbox 能换第二套碰撞：Yard 空场（现状）+ Pit 四柱掩体 + 地板换色。菜单外观一字不改。Play / 隐式档 / LAN 默认仍是 Yard。Autoload 仍为 0。没有菜单选图、没有 `records.json` 的 `arena_id`、没有第三张图、不改句读/敌人数字、不扩 LAN rpc。

- **数据**：`ArenaDef`（`id` / `display_name` / `layout_scene` / `tile_color` / `grout_color`）。禁止 `skeleton_scene`、禁止敌人列表、禁止 BGM 路径。
- **目录**：`ArenaCatalog` 抄 `CharacterCatalog`。`DEFAULT_ID="yard"`，合法 id 只有 `yard` / `pit`；`get_by_id` 找不到返回 `null`；`sanitize` 非法打回 `yard`。重复 id `push_error` 并跳过后到的。不是 Node，不是 Autoload，禁止 `get_tree()`。
- **两份 layout**：`maps/yard_layout.tscn` 空 Node2D；`maps/pit_layout.tscn` 四根 `ArenaBlock`：PillarNW / NE / SW / SE 中心 `(±280, ±180)`，一律 96×96。躲开玩家 `(0,0)`、Guest `(80,0)`、跟班相对 `(±48, 24)`、现有敌人出生点与中轴。
- **ArenaBlock**：`StaticBody2D`，layer=`MASK_WALL`，mask=`NONE`。视觉抄外墙三块 Polygon2D。`_ready` 按 `block_size` 重建 polygon，不每帧 `queue_redraw`。禁止新贴图。
- **地板**：`ArenaFloor.apply_palette(tile, grout)` 记下颜色、重建 ImageTexture。`_ready` 仍默认冷色。`TILE_PX` / `GROUT_PX` / `BEVEL_PX` / `FLOOR_SIZE` 不动。Pit 暖灰褐 `Color(0.20, 0.18, 0.16)` / `Color(0.12, 0.11, 0.10)`。
- **沙盒**：World 下空节点 `Obstacles`（与 Walls 平级）。外墙四块留在 `combat_sandbox.tscn`，尺寸位置不动。`_apply_arena` 清 Obstacles、换色、instantiate layout、子树再赋 WALL layer。敌人节点不搬家。
- **GameLaunch**：`set_arena_id` / `take_arena_id`，take 后打回 `yard`，非法打回 `yard`。只传 id。本阶段 MainMenu / RecordSelector / LanOverlay 不调用。Retry / R / Winner Retry 不准 take，不换 `_arena_id`。
- **F7**：debug 单机循环 yard→pit→yard，立刻 `_apply_arena` + `_host_reset_sandbox`。暂停 / 三选一 / 商店 / 结算忽略。LAN 忽略。无新 InputMap action，`physical_keycode` 抄 F8。
- **Overlay**：`bind_arena_id`，状态行 `arena: yard|pit`。不要第五块 HUD。

**当时不做：** RecordSelector / New Record / LanOverlay 选图 UI、`records.json` 加 `arena_id`、第三张地图、改句读名字/P0–P8 人数、改敌人 `_ready` 身份数字、扩 rpc 加 map 字段。


## Day 68（已完成）：建档和开 LAN 能选 Yard / Pit，点已有档按档进图

菜单能选图了。`GameRecord.arena_id` 落盘；New Record / LAN Host 各两枚 Yard/Pit 钮；点已有档 `MainMenu._enter_record` 写 `GameLaunch.set_arena_id`，沙盒 `take` 后进对应碰撞。Autoload 仍为 0。没有第三张图、没有 Edit Record、不改碰撞/句读、F7 仍是 debug 单机切图不写回档。

- **档**：`GameRecord.arena_id` 默认 `"yard"`。`to_dictionary` / `from_dictionary` 读写 `"arena_id"`。非法 / 空 / 缺字段 → `"yard"`（只接受 `yard` / `pit`）。history 条目不写地图。`save_version` 仍为 1，不做迁移工具。
- **匹配桶**：`create_record(name, character_id, loop_goal, arena_id="yard")` 写出前 sanitize。`ensure_playable_record` 同样三参，默认 yard。`_find_earliest_match` 三键相等（loop 桶规则不变：`<=0` 算同一无限档）。自动名仍 `"Boar · 20 loops"` / `"Boar · Inf"`，不把 Yard 塞进默认名。
- **列表**：主卡 / Profile 概览 meta 文案 `"%s  %s  ·  %s"`（角色、loop 徽标、`ArenaCatalog.display_name`）。排行行不要地图。
- **New Record**：Characters 行下 `Arenas` HBox，Yard / Pit 两枚 `OfferButton`，`toggle_mode`、同一 ButtonGroup，`200×56`，只要文字。默认 Yard；`_reset_editor` 打回 yard。Confirm 把 `_selected_arena_id` 写入新档。不要第三枚、不要下拉、不要预览小地图。选图不绑 1/2/3（1/2 仍是猪/鸡）。
- **点已有档**：`_enter_record` 读档 `set_arena_id`，不要 `take_arena_id`，不要第二层选图。已有档不能改 `arena_id`。
- **隐式档 / F6**：`ensure_playable_record("boar", fallback_goal)` 默认 yard，不会误拿到 Pit 档。Retry / R / Winner Retry 仍留当前 `_arena_id`，不准 take Launch。
- **LAN**：HostRoot 同样两钮。Custom 可点，默认 yard，只进 `GameLaunch`，不建档。借档：地图跟档走，按钮 disabled + `focus_none`，与角色/loop 同一把锁。Guest 不能选图；`GoalLabel` 下 `MapLabel`（默认 hidden），文案 `"map  Yard"` / `"map  Pit"`。Host 改图立刻 `rpc_arena`；握手成功后立刻推一次 loop + arena。
- **协议**：`NET_PROTOCOL=2`。`rpc_begin(host, guest, loop_goal, arena_id)`。旧 Guest 协议 1 必须 Version mismatch。LAN 仍不写 `records.json`。
- **F7**：仍是 debug 单机 yard↔pit，立刻换碰撞，不写回 `Record.arena_id`。

**当时不做：** 第三张地图、改 Pit 柱坐标/尺寸、改句读名字/P0–P8 人数、改敌人 `_ready` 身份、给已有档做「编辑地图」、房间浏览器、新 wav / 新 PNG、改 ShopOffer / Pack / Stim / Gunner、改 Motor 420 / `look_ahead=100`、HUD 锚点、算分公式、UpgradeOffer 再改、Autoload、`Engine.time_scale`、`reload_current_scene`、WinnerPage 分数滚动。

## Day 69（已完成）：第三套碰撞 Keep + 选图第三枚钮

同一份 CombatSandbox 能换第三套碰撞：Keep 北墙缺口 + 西南/东南碉堡 + 绿灰砖。New Record / LAN Host 第三枚 Keep 钮；点 Keep 档进 Keep。Autoload 仍为 0。没有第四张图、没有 Battle、不改句读/敌人数字、不改 Pit、不扩协议。

- **目录**：`data/arenas/keep.tres`：`id="keep"`，`display_name="Keep"`，`tile_color=Color(0.15, 0.19, 0.17)`，`grout_color=Color(0.08, 0.11, 0.10)`，`layout=maps/keep_layout.tscn`。仍是 64px 勾缝砖、最近邻、无噪声、无暗角。`arena_catalog.tres` 顺序 yard, pit, keep。
- **layout**：四块 `ArenaBlock`。WallNorthL `(-200, -120)` 240×48；WallNorthR `(200, -120)` 240×48；BunkerSW `(-200, 120)` 48×160；BunkerSE `(200, 120)` 48×160。北墙在 x∈(-80,80) 断开。不要第五块，不要斜放，不要改外墙。躲开玩家 `(0,0)`、Guest `(80,0)`、跟班相对 `(±48, 24)`、MeleeLeft / MeleeBottom / EliteBottom / RangedRight / RangedTop / ChargerRight / BossCenter。y=0 中轴在 |x|<176 内可穿过。
- **sanitize**：`ArenaCatalog.sanitize(requested)`：`get_by_id` 非 null 则返回 requested，否则 `DEFAULT_ID "yard"`。不再写死两元素白名单。`GameLaunch._sanitize_arena_id` / `GameRecord._sanitize_arena_id` preload 目录调 `sanitize`。`GameRecords._arena_id_for_write` 走同一份。旧 JSON 无/非法 `arena_id` 仍当 yard。`save_version` 仍为 1。隐式档 / `ensure_playable_record` 默认仍 yard。
- **选图 UI**：RecordSelector EDITOR Arenas HBox 第三枚 Keep，与 Yard/Pit 同一 ButtonGroup、`OfferButton`、toggle、`200×56`、只要文字。`_select_arena` 三钮 pressed 对齐；`_reset_editor` 仍 yard；`_on_keep_pressed` → `_select_arena("keep")`。LanOverlay HostRoot 同样第三枚；`_select_arena` 推 `rpc_arena`；借档若 `arena_id==keep` 则三钮全锁、Keep 显示按下。Guest MapLabel `"map  Keep"`（走 `RecordCard.format_arena_name`）。不要下拉、不要预览小地图、不要绑 1/2/3。
- **F7**：目录顺序 yard, pit, keep，debug 单机三循环，立刻换碰撞，不写回 `Record.arena_id`。暂停 / 三选一 / 商店 / 结算 / LAN 忽略。Retry / R / Winner Retry 不准 take Launch，不准换 `_arena_id`。
- **协议**：`NET_PROTOCOL` 仍为 2。`arena_id` 已是字符串，不 bump。

**当时不做：** 第四张地图、Battle / 友军伤害、改 Pit 柱、改句读名字/P0–P8 人数、改敌人 `_ready` 身份、给已有档做 Edit Record、房间浏览器、不扩协议、新 wav / 新 PNG、改 ShopOffer / Pack / Stim / Gunner、改 Motor 420 / `look_ahead=100`、HUD 锚点、算分公式、UpgradeOffer 再改、Autoload、`Engine.time_scale`、`reload_current_scene`、WinnerPage 分数滚动。


## Day 70（已完成）：第一轮就密 + 鸡专属 4 卡

loop 0 也走已有 DENSE 名单；鸡能抽到 4 张专属卡，猪永远只能抽 10 张共享。Autoload 仍为 0。LAN 协议仍为 2，`rpc_offer_open` 仍三个 upgrade id，仍一份 owned。鸡卡进共享 owned 后，只给 `character_id==chicken` 的 pawn 生效。

- **句读**：删掉稀疏 `P1_NAMES` / `P3_NAMES` / `P5_NAMES` / `P7_NAMES`。`_p1_names` / `_p3_names` / `_p5_names` / `_p7_names` 永远返回对应 `*_DENSE`。`_p3_overlap_max` 永远 3。DENSE 名单一字不改（P1 左 6 近战，P3 右 4 远程，P5 下 8 近战 + 上 3 远程 + EliteBottom1，P7 左 7–10 + 下 9–10 + 右 5–6 + 上 4 + ChargerRight1/2）。hold / activate / 节点名引用不变。P7 仍等场上非预备役清光再进 Boss。不改 P0 rest、P2/P4/P6 三选一、P8 商店、Boss 句、`REST_SEC`、`_rest_sec` 加压、stagger 公式。
- **UpgradeDef**：`@export var character_id: String = ""`。空 = 全角色可抽；只允许 `""` / `"boar"` / `"chicken"`，其它写盘或资源值打回 `""`。现有 10 张不填。不新增 Kind。
- **鸡 4 张**（`upgrade_catalog.tres` 末尾，共享 10 张在前）：`light_step` Light Step 移速 +10% `MOVE_SPEED_PCT` 0.10 可叠 shop 30；`beak_shot` Beak Shot 伤害 +4 `DAMAGE_FLAT` 4.0 可叠 shop 30；`feather_frame` Feather Frame 无敌 +0.12s `I_FRAME_FLAT` 0.12 不可叠 shop 45；`quick_peck` Quick Peck 射速 +12% `FIRE_RATE_PCT` 0.12 可叠 shop 30。`character_id` 一律 `"chicken"`。
- **抽卡 / 商店**：`RunSession` 从已 bind 的 `_players` 收集角色，空列表当只有 `"boar"`。LAN Host+Guest 都算在场。单机读当前 `get_character_id()`（F8 切鸡后下一窗可抽鸡卡）。def 可入池：`character_id` 为空，或等于某个在场角色。`draft_offer(count)` 签名不变：先角色过滤，再滤非 stackable 已有，再 shuffle。`list_shop_catalog` 升级段同一过滤；消耗品 / Gunner 货位不动。LAN P8 仍 `draft_offer(3)` 三张升级即关。`try_grant`：鸡卡在没有任何 chicken pawn 时返回 false，不写 owned。池空仍走 acknowledge / 跳过，不 `push_error`。
- **生效**：`UpgradeApplier._add_def` 之前，若 `def.character_id` 非空且 != 当前 pawn `get_character_id()` 则跳过。空 `character_id` 两人仍都吃。不改 `capture_baseline` / 底值重算 / `MIN_*`。鸡卡走现有 `MOVE_SPEED_PCT` / `DAMAGE_FLAT` / `I_FRAME_FLAT` / `FIRE_RATE_PCT` 分支，不新 totals 键。
- **Overlay**：F9 增补 `chicken_pool: 4|0`（在场有鸡则 4，否则 0；后数为 owned 里鸡卡个数）。不要 Theme、不要第五块 HUD。

**当时不做：** WinnerPage 分数滚动、菜单↔战斗 BGM 交叉淡、跟班 LAN 同步、Battle / 友军伤害、新 Kind、新敌人。

## Day 71（已完成）：Winner 滚动 + 换场 BGM 淡

结算数字会滚，换场音乐会淡。场景无法真·重叠，所以是先淡出再切、进场再淡入。Autoload 仍为 0。没有新 wav/mp3、没有新 AudioBus、没有 Credits、没有版本号 UI、没有 Battle。

- **WinnerPage 滚动**：`SCORE_STAGGER_SEC=0.08`、`SCORE_ROLL_SEC=0.32`、`SCORE_TOTAL_SEC=0.40`、`SCORE_FADE_SEC=0.18`，TRANS_QUINT EASE_OUT。Title / RecordName 跟现有 `enter_overlay` 一起出现。LoopBreak / KillsBreak / GoldBreak / TimeBreak 错峰淡入，右侧点数从 0 滚到 `loop*1000` / `kills*5` / `gold*2` / `floori(time)`；Time 左侧仍是 `time  %.1fs  →  %d`。CLEARED 才出现 `cleared  +5000` 行（5000 不滚）。Score 从 `score  0` 滚到 `GameRecords.compute_score` 返回值，禁止拆解行再加一遍。NEW BEST 在总分到位前 hidden，到位后若本局分 > previous_best 再显示；LAN 永不显示。Summary 跟总分同一拍淡入（owned 不逐字滚）。右侧 history 在总分开始滚时按 `SCORE_STAGGER_SEC` 错峰淡入，文案仍 `#%d  %d   L%d  %s  %.1fs`，hist 分数不再 count-up。Retry / Menu 的 `enter_overlay` 错峰保留，开窗即可点。
- **snap**：已打开时点 Retry / Menu / Esc / Start，若滚动没完先 kill tween、写成最终文案、NEW BEST 按最终条件显示，再走现有 close/emit。点 Retry / Menu 逻辑仍瞬时 emit，不等滚动结束。`close()` 必须 kill 滚动 tween。`present()` 开头把拆解行 `modulate.a` 收成 0、Score 写成 `score  0`、NEW BEST hidden。
- **BGM 淡**：`SILENCE_DB=-80`、`BGM_FADE_SEC=0.45`。淡出 TRANS_QUINT EASE_IN，淡入 TRANS_QUINT EASE_OUT。Tween 一律 `TWEEN_PAUSE_PROCESS`。禁止新 Autoload、禁止 `get_tree().root.add_child` 常驻播放器、禁止把 `AudioStreamPlayer` 从将卸掉的场景 reparent 出去。
- **MainMenu**：`_music_fade`（0=静音，1=满）。`_process`：`overlay_db = lerpf(MUSIC_DB_NORMAL, MUSIC_DB_DIMMED, _focus_amount)`，`volume_db = lerpf(SILENCE_DB, overlay_db, _music_fade)`。进场 `_music_fade` 0→1。点已有档 / LAN 走 `_leave_to_sandbox()`：`_leaving` 闸，淡出后再 `change_scene_to_file`。Exit / quit 仍瞬间退。叠层打开时 -6→-16 的 dim 保留，不要改 `BLUR_MAX` / `DIM_MAX` / `FOCUS_SMOOTH`。
- **CombatSandbox**：进场 `war.mp3` 从静音淡到 `COMBAT_MUSIC_DB=-22`。`_ensure_combat_music` 没在播才 play，已在播不 `seek(0)`、不把音量打回满。`_return_to_menu` 先清跟班 / 写盘 / 关 peer，再 `tree.paused=false`，CombatMusic 临时 `ALWAYS`，淡出后再切菜单。Retry / R / `_host_reset_sandbox` / F7 / F8 一律不动 CombatMusic。F6 直进沙盒只做战斗曲淡入。暂停仍冻树，平时仍 INHERIT（暂停即静音），Continue 从同一位置续播、不要淡。Winner 打开时 war.mp3 继续 -22，不再衰减一层。
- **LAN**：Winner 同样滚数字；history 仍空。Guest Retry 仍禁用。`NET_PROTOCOL` 仍为 2，不扩 rpc。

**当时不做：** Credits 叠层、Settings 版本号、跟班 LAN 同步、Battle / 友军伤害、Autoload 音乐、Music/SFX 分轨滑条、新 AudioBus、新 mp3 / wav / PNG。

## Day 72（已完成）：剩余叠层四态音效 + Credits + 版本 1.0.0

各菜单叠层自己管 hover/click/back；Settings 显示 `version  1.0.0`；Credits 小面板挂在 Settings 下。Autoload 仍为 0。没有新 wav、没有新 Autoload、没有跟班 LAN、没有 Battle、没有分轨滑条。

- **音效**：RecordSelector / LanOverlay / Profile / Leaderboard / ModeChoice / Settings / Credits 各自挂 `AudioStreamPlayer`，`GameAudio.load_wav` 现有 `ui_hover.wav` / `ui_click.wav` / `ui_back.wav`。RecordSelector 满 12 点 `+ New Record` 与 LAN `_create_server` 失败走 Error（现有 `click.wav`，与商店 ErrorSfx 同一文件）。同一帧同一种最多 1 次（`Engine.get_process_frames()` 门闩）。`MainMenu._wire_button_sounds` 跳过这些叠层子孙。动态档卡由叠层自己 wire。
- **Pause / Winner**：Continue / Esc / Quit / Menu = Back；Retry / Settings = Click。
- **版本**：`project.godot` `config/version="1.0.0"`；`GameSettings.VERSION` / `get_version()`；Settings 副标题下 VersionLabel `version  1.0.0`。标题仍是 Settings，副标题仍是 `Change game settings`。
- **Credits**：Settings Data 节 CREDITS 钮打开 FloatingPanel 960×720；名单锁死；`github.com/ZhiH2333` → `OS.shell_open("https://github.com/ZhiH2333")`；Esc 先关 Credits。`Settings.close` 若 Credits 开着先关 Credits。Credits 打开时菜单 dim 走现有 -6→-16。

**当时不做：** 跟班 LAN 同步、Battle / 友军伤害、Music/SFX 分轨滑条、新 wav、新 Autoload。

## 过渡加载界面（已完成）

菜单进档 / LAN 进沙盒、Pause Quit / Winner Menu 回菜单时盖一层 LOADING，避免换场黑一下或卡在旧画面。Autoload 仍为 0。Retry / R / `_host_reset_sandbox` 不盖。BGM 仍先淡 0.45s 再切。没有新 wav / PNG / 字体。

- **LoadingScreen**：`CanvasLayer` layer 80，挂在树根上贯穿全程，不是 Autoload。底图复用 `images/mainmenu.png`，`loading_blur.gdshader` 高 LOD 超级模糊并压暗。标题 `LOADING` 96px；720×18 滑块 0.42s 单向、余弦对称往返（左右同速），前缘跟相位、尾部按速度 smoothstep 拉长最多 88px；下方 `loading  <资源名>` 轮播依赖项，结束显示 `ready`。不播 BGM。
- **离场**：`present_on` 盖住当前场并 `load_threaded_request`。BGM 淡完 `switch_current` 只通知这张盖可以换场，不再 `change_scene` 到第二张加载页。
- **交接**：最少停 0.35s 且资源就绪后，在盖下面 `change_scene_to_packed`，再淡出盖。目标空则回主菜单。
- **GameLaunch**：`set_next_scene` / `peek_next_scene` / `take_next_scene`，仍禁止 `get_tree()`。`NET_PROTOCOL` 仍为 2。

**当时不做：** 跟班 LAN 同步、Battle、分轨滑条、新 Autoload、把 Retry 也改成换场加载。

## Day 73（已完成）：LAN 同步跟班和药

LAN P8 和离线同一套目录商店；药、跟班、升级由 Host 权威结算；Guest 跟班是傀儡。Autoload 仍为 0。没有 Battle、没有 5 人房、不改数字、不写档。

- **协议**：`GameLaunch.NET_PROTOCOL = 3`。握手仍 `rpc_hello(protocol)`；协议 2 的旧 Guest 必须 Version mismatch。`rpc_begin` 签名不改。
- **快照**：`SNAPSHOT_VERSION = 2`。enemy 块之后、session 块之前写 companions：`u8 count`（0～10，含尸体）；每条 `u8 slot` / `u8 owner_seat`（1 Host / 2 Guest）/ `u8 weapon_index` / `u8 flags`（bit0 defeated）/ `float x,y` / `float aim_x,aim_y` / `u16 hp,max_hp`。version≠2 的包 Guest 丢弃。
- **商店 RPC**：Host `send_shop_stock(data, gold, stim_bought)`；Guest `send_try_shop(kind, id, extra)`。kind：0 升级 / 1 消耗品 / 2 跟班（extra=weapon_index）。Continue / Skip 仍 `send_try_pick("__skip__")`。库存包只写 `u8 n` + 每张 `u8 kind` + utf8 id，价格走现有 `get_cost`。句读三选一仍 `rpc_offer_open` 三元组，ShopCard 不进 UpgradeOffer。
- **LAN P8**：删掉 `draft_offer(3)` 三张升级大卡。Host/离线一律 `list_shop_catalog()`。金币够就连买，Continue 才关店 + `_finish_loop_after_shop`。Guest 点卡/选枪/Continue 只上报，不 spend、不 spawn、不 heal。Host 扣金后对买家 pawn 生效（seat 1 Host / seat 2 Guest）；Pack L 仍 fill 买家 + 所有活跟班。Stim 本店只能买一次，只护买家。
- **跟班**：Host 模拟 AI + `fire_at`；Guest `set_remote_puppet(true)`，禁止再跑 AI / 再 `fire_at`。`bind_owner` 跟买家。开火 `shot_fired` 后 Host `send_fire_fx(10+slot, ...)`，Guest 用当前枪 `spawn_fx_shot`。活跟班仍 `COMPANION_CAP=10`，满员货架不出 Gunner；尸体留场不 `queue_free`。
- **冻结**：LAN 开店 / 暂停对 `_companions` 调 `set_sim_paused`。`ShopOffer.bind_player(_local_player)`，Guest 状态栏是自己的血。F1–F8 只在 debug 单机有效，联机和生产包都不是 runner。LAN 仍不写 `records.json`。
- **关房**：Host 关房，Guest 居中弹出英文框 “Host closed the room. Returning to the menu.”（白边框，从下方弹入；dimmer 让出顶栏 60px，顶栏 CanvasLayer 50 盖在弹窗层 40 之上）。点 OK 才回菜单，不自动关。Guest 退出，Host 右上角英文 toast “Guest left the room. Switched to solo.”，本局继续单机、仍不写档。

**当时不做：** Battle / 友军伤害、房间浏览器、3～5 人、P2P、断线重连、改 Gunner 140/520/70、改 Pack/Stim 数字、改 COMPANION_CAP=10、改四把枪/敌人身份、Motor 420 / `look_ahead=100`、HUD 锚点、算分公式、`records.json`、10+4 张卡 value、UpgradeOffer 再改、第三张图以外的地图、Autoload、`Engine.time_scale`、`reload_current_scene`、新 PNG、新 wav、手柄重绑、主动技能、战斗 HUD 跟班条。

## Day 74（已完成）：LAN Battle 2 人

LAN 2 人 Battle：Host 选模式，无句读无商店，玩家弹打得到对方，先倒下的输。Co-op 路径与 Day 73 相同。Autoload 仍为 0。不写 `records.json`。

- **协议**：`GameLaunch.NET_PROTOCOL = 4`。`enum NetPlay { COOP, BATTLE }`；`set_net_play` / `take_net_play()`，take 后打回 COOP。`rpc_begin(..., arena_id, net_play)` 第五参 0=Co-op / 1=Battle。Host 改选立刻 `rpc_play_mode`。协议 3 旧 Guest：Version mismatch。NetPlay 不进 records.json。
- **LanOverlay**：HostRoot 在 Arenas 与 LoopRow 之间加 Modes（Co-op / Battle，OfferButton，200×56）。默认 Co-op；`_reset` 打回 Co-op。Battle 时 Loop 滑杆 disabled，标签 `battle`，不改 loop_goal。借档仍锁角色/地图/loop，Modes 可点。Guest `ModeLabel`：`mode  Co-op` / `mode  Battle`。
- **Battle 战场**：`_is_battle()` 时敌人全部 `hold_in_reserve` + `set_sim_paused(true)`；不 `encounter.restart()` / tick；不开 UpgradeOffer / ShopOffer；不 spawn 跟班；金币/XP 保持 0。Co-op 仍目录店、仍同步药和 Gunner、仍句读。
- **友军伤害**：仅 Battle 玩家枪 `hit_players=true`，mask 加 `MASK_PLAYER`。`reset(..., owner, hit_players)`；owner 存活且 `hit == owner` 则忽略（不火花、不回收、不伤自己）。打到对方 Player 走 `PlayerHealth.apply_damage`。Co-op / 跟班弹仍不得打队友和跟班。禁止新物理层。
- **胜负**：Host 一人倒下即结算，禁止走 `_all_pawns_defeated`。双方同帧 defeated → DRAW（`winner_seat=0`）；仅 Host 倒 → 2；仅 Guest 倒 → 1。`rpc_winner` 末尾加 `winner_seat`。`RunSession.mark_battle_over()` 把 outcome 设 DEAD。Guest 以 Host 包为准。Retry：Host 重置两人体力/位置/枪，仍是 Battle，不 take Launch；Guest 不能点 Retry。
- **Winner**：Battle 标题 DRAW / KO（赢方 ClearedTitle，输方 RunSummaryTitle）；`record_name = "BATTLE"`；隐藏 loop/kills/gold/cleared bonus；score 文案 `time  %.1fs`；NewBest 永不出现；右侧 history 仍空。
- **Hud**：Battle 右上 `RivalRow`（200×12 + `rival  n/m`）；Phrase `BATTLE`；XP/gold 行隐藏。左下锚点不改。Debug Overlay lan 行加 `play: coop|battle`。

**当时不做：** 房间浏览器、3～5 人 FFA、P2P、断线重连、Joypad 重绑、虚拟摇杆、主动技能、战斗 HUD 跟班条、改 Gunner 140/520/70、改 Pack/Stim 数字、改 COMPANION_CAP=10、改四把枪/敌人身份、Motor 420 / `look_ahead=100`、HUD 左下锚点、算分公式、records.json 字段、10+4 张卡 value、UpgradeOffer 再改、第四张图、Autoload、`Engine.time_scale`、`reload_current_scene`、新 PNG、新 wav、玩家身体互撞、近战拳头互殴、Battle 里刷怪/跟班/商店。

## 剩余表


**Day 49 = 局域网 2 客户端（已完成）**：ENet 17777、protocol 1、Host 权威、共享升级池、不写档、暂停不冻树、一份 `player.tscn`。同机分屏不做。

**Day 50 = 用现有档开 LAN（已完成）**：Host 借档预填并锁定角色 + `loop_goal`；Guest 仍自选；空档走 Custom；联机不写盘。5 人 / 房间浏览器是后续日。

**Day 51 = Play 分岔 Solo/Multi（已完成）**：Mode Choice 路由、顶栏直达、三个叠层大面板 + 2 列网格、`enter_overlay` 弹起。Profile 新内容和 Settings 大面板化是后续日。

**Day 52 = Profile 概览 + 可视化排行（已完成）**：RecordCard 新增两种只读行、RecordLeaderboardOverlay 排行条、RankBar/Gold/Silver/Bronze 主题。

**Day 53 = Settings osu 式抽屉（已完成）**：渲染分辨率/UI 缩放/垂直同步/抗锯齿/按键绑定/长按删档六项新设置落盘，抽屉式导航 + 搜索 + 惯性滚动。渲染分辨率仍是占位。

**Day 54 = 渲染分辨率落地 SubViewport（已完成）**：战斗世界进 SubViewport，HUD 留主视口。

**Day 55 = FlatBold 令牌 + OfferButton（已完成）**：卡片圆角 6、不透明、无阴影；`OfferTitle` 加粗。

**Day 56 = 大面板 + 胶囊 CTA FlatBold（已完成）**：`FloatingPanel` / `RunSummaryPanel` / 三色胶囊去阴影、圆角 6、不透明；Header / ModeTitle / Pill 加 `font_bar_bold`。

**Day 57 = 右摇杆即时瞄准（已完成）**：回中 keep last，出 0.12 当帧对准，无转向平滑；左摇杆仍模拟走速；`map_aim_stick` 是虚拟摇杆合同。

**Day 58 = Settings 抽屉换皮（已完成）**：侧栏 / 面板底色 / SettingsHeader / 导航选中指示对齐顶栏纯色粗体。滚动、搜索、键盘重绑、长按删档逻辑不动。

**Day 59 = 可见区 fit（已完成）**：大面板 / RecordCard / NewRecord / Custom 按 `visible_rect` 收缩；1.0 仍是 1680/780；禁止 `CARD_SIZE * ui_scale`。Settings 滑杆拖动中重排抽屉。

**Day 61 = 两种跟班上场（已完成）**：F8 debug 循环近战 Guard / 远程 Gunner，上限 1，商店仍只卖升级。死亡留灰尸不给钱。

**Day 62 = 厚血远程跟班（已完成）**：删近战；Gunner HP140 / 速520；P8 买时选枪扣 70；一局最多 10 只活着的 Gunner；AI 绕圈+LOS；LAN 仍不出跟班。

**Day 63 = 目录商店（已完成）**：FloatingPanel 左状态右货架；Pack S/L/Stim；Pack L 同时回满活着的 Gunner；离线连买不关店；LAN 协议仍是 3 张升级买 1 张即关。

**Day 64 = 商店手感（已完成）**：货卡错峰、按身份复用、金币滚动、HP/XP 条 smoothing、四态音效；灰卡可点 error。UpgradeOffer 仍无音效。

**Day 65 = 句读三选一 hover/click/back（已完成）**：三态音效 + hover 1.02 + 点选 punch；Esc/Start 仍 cancelled。布局/抽卡/LAN 不变。

**Day 66 = 句读三选一 FloatingPanel 小面板（已完成）**：标题 PICK ONE、三张卡仍居中；61–66 收束。

**Day 60 不开工**：视觉统一到 Day 59 收束。

**Day 67 = 同一沙盒两套碰撞（已完成）**：Yard 空场 + Pit 四柱 `(±280, ±180)` 96²、地板两色、F7、`GameLaunch.arena_id`。菜单不选图。

**Day 68 = 选图进档 / LAN（已完成）**：Record 增 `arena_id`；New Record / Host 两枚 Yard/Pit 钮；点已有档按档进图；协议 2；借档锁定地图。没有第三张图，没有 Edit Record。

**Day 69 = 第三套碰撞 Keep（已完成）**：Keep 北墙缺口 + 西南/东南碉堡、绿灰砖、第三枚钮、sanitize 改目录判定。没有第四张图，没有 Battle，不改 Pit，不扩协议。

**Day 70 = 第一轮就密 + 鸡 4 卡（已完成）**：loop 0 走 DENSE；鸡专属 4 张按在场角色过滤；Applier 只给鸡生效。协议仍 2。

**Day 71 = Winner 滚动 + 换场 BGM 淡（已完成）**：WinnerPage 拆解错峰滚出 + snap；菜单↔沙盒先淡出再切、进场淡入。Retry 不停曲。Autoload 仍为 0。

**Day 72 = 剩余叠层四态音效 + Credits + 版本 1.0.0（已完成）**：叠层自管 hover/click/back；动态档卡有声；Pause Continue/Esc/Quit 与 Winner Menu/Esc 走 Back；Settings `version  1.0.0`；Credits 小面板。Autoload 仍为 0。

**过渡加载界面（已完成）**：进档 / 退战斗盖 LOADING；BGM 仍淡 0.45s；Retry 不盖。Autoload 仍为 0。

**Day 73 = LAN 同步跟班和药（已完成）**：协议 3、快照 v2、LAN P8 目录连买；药/跟班/升级 Host 权威；Guest 傀儡 Gunner + fire_fx。没有 Battle、没有 5 人房、不改数字、不写档。

**Day 74 = Battle 2 人（已完成）**：协议 4、Host 选 Co-op/Battle、无句读无商店、玩家弹打得到对方、先倒的输、不写档。

**下一步 Day 75 = 导出 Win/macOS/Linux + Pit/Keep/Co-op/Battle profiling。**

**完整手柄适配后置（已拍板）**：不在 54–60 做 Joypad 按键重绑、手柄专属 Settings、虚拟摇杆布局编辑。Day 57 的右摇杆 `map_aim_stick` 保留，不再扩展。手柄/触屏整包跟 Day 81+ 或更后的 Virtual Sticks 一起做。

> **视觉方向决定（自 Day 54 起生效）：** 后续所有新叠层/新控件改用「纯色块 + 粗体字」的顶栏语言（`TopBar` 平行四边形按钮那一套：实心色底、无渐变、无软阴影、字重加粗），逐步淘汰 Day 34/35 引入的 osu 紫黑渐变 + 细描边风格。旧叠层不强制推倒重做，但每次 touch 到的叠层顺手换皮。Day 55 已完成第一刀：FlatBold 令牌 + `OfferButton`。Day 56 已完成第二刀：`FloatingPanel` / `RunSummaryPanel` / 三色胶囊 CTA。Day 58 已完成第三刀：Settings 抽屉。TopBar、LogoButton 仍用旧皮。

## 完整 roadmap 展望（Day 54 → Day 100，生产级里程碑）

按五个阶段推进，每个阶段仍按“一天一个可验收交付”的节奏拆解，具体某天的详细契约在开工前用一份新 prompt 敲定，不在这里一次性写死：

1. **Day 54–60　渲染与视觉统一**：Day 54 已把 `SubViewport` 接到渲染分辨率滑杆；Day 55 已落地 FlatBold 令牌并换掉 `OfferButton`；Day 56 已把大面板和胶囊 CTA 换成圆角 6、无阴影、不透明 + `font_bar_bold`；Day 57 已落地右摇杆即时瞄准（回中 keep last，出 0.12 当帧对准，`map_aim_stick` 合同）；Day 58 已把 Settings 抽屉换成 FlatBold；Day 59 已按可见区收缩大面板和动态行，视觉统一到此收束。Day 60 不开工。**完整手柄适配（Joypad 重绑 / 手柄 Settings / 虚拟摇杆）后置**，不插在 54–60。
2. **Day 61–66　商店深化 + 跟班系统**：Day 61 已让跟班在单机沙盒上场。Day 62 已把跟班收成厚血远程 Gunner：P8 买时选枪、AI 绕圈+LOS、删近战 Guard；LAN 仍不出跟班。Day 63 已把 P8 改成目录商店（状态栏 + 货架 + Pack S/L/Stim，离线连买，LAN 协议不变）。Day 64 已把目录商店做成菜单手感（错峰 / 复用 / 金币滚动 / 四态音效）。Day 65 已给句读三选一补同一套 hover/click/back。Day 66 已把 UpgradeOffer 收成 FloatingPanel 小面板（标题 PICK ONE、三张卡仍居中），61–66 收束。仍是**局内临时**；**主动技能先跳过**，不做技能栏/冷却 UI、不做跟班 HUD。LAN 同步药和跟班已在 Day 73 落地。
3. **Day 67–80　内容与地图广度**：Day 67 已让同一沙盒换 Yard/Pit 两套碰撞（四柱 `(±280, ±180)` 96²、地板两色、F7、`GameLaunch.arena_id`）。Day 68 已把选图接进 New Record / LAN Host（Record 增 `arena_id`，协议 2，点已有档按档进图）。Day 69 已加第三套碰撞 Keep（北墙缺口 + 碉堡、绿灰砖、第三枚钮、sanitize 改目录判定）。Day 70 已让 loop 0 走 DENSE，并补齐鸡 4 张专属卡（按在场角色过滤，Applier 只给鸡生效）。Day 71 已做 Winner 分数滚动 + 换场 BGM 淡。Day 72 已做剩余叠层四态音效、Credits、版本 1.0.0。进档/退战斗已盖 LOADING。Day 73 已做 LAN 同步跟班和药（协议 3、快照 v2、LAN 目录连买）。Day 74 已做 Battle 2 人（协议 4、关句读/商店、友军伤害、先倒即结算）。下一步 Day 75 导出 Win/macOS/Linux + Pit/Keep/Co-op/Battle profiling。后续波次/Boss 词表扩充。
4. **Day 81–92　UI 动效与音效精修（osu 参考）**：菜单/叠层交互音效分层（hover/click/back/error 四态，参考 osu! 的 sample set）；数字滚动、combo/连击类反馈的非线性缓动；Day 71 已做 WinnerPage 分数拆解逐行滚出和换场 BGM 淡，后续是随强度过渡的分层淡。**完整手柄适配 + 虚拟摇杆**排在本阶段或之后，与触屏同一套 `map_aim_stick` 合同，不提前做 Joypad 重绑。
5. **Day 93–100　联机加固与发布收尾**：局域网之外补一条「自建中转」的 P2P 直连路径（见下方 E2E 打洞方案，不接第三方云服务）；断线重连与掉线容错；导出流程（Windows/macOS/Linux 桌面为主）与首次运行引导；发布前性能/内存过一轮 profiling；`ROADMAP.md`/`README.md` 最终校对，锁定 1.0 范围。

**验收口径（每一天通用）**：本 Day README 里列出的「当时不做」清单之外的行为不应出现改动；新增/变更的脚本、场景、theme 项都要在 README 对应 Day 小节里落字，agent 交付前必须自查 README 是否已同步——这正是本次修的问题（Day 52/53 曾漏更新）。
