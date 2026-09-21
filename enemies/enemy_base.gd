extends CharacterBody2D
class_name EnemyBase

## 廉价 seek 移动 + 受击链（闪白 / 击退 / squash / 局部 hitstop / 死亡塌缩）。
## 禁止 NavigationAgent、每帧 group 扫描、queue_redraw、Engine.time_scale。
signal defeated
const FLASH_DURATION_SEC: float = 0.1
const DEAD_COLOR: Color = Color(0.42, 0.42, 0.44, 0.38)
const DEATH_SLIDE_STOP_SPEED: float = 12.0
const ENTER_SCALE_FROM := Vector2(0.4, 0.4)
const SEPARATION_PIXELS: float = 40.0
const FACE_DEADZONE_PX: float = 2.0
const DEATH_SHARD_COUNT: int = 6

@export var max_hp: int = 36
@export var move_speed: float = 175.0
@export var acceleration: float = 1400.0
@export var knockback_impulse: float = 260.0
@export var knockback_max_speed: float = 420.0
@export var knockback_damping: float = 1800.0
@export var hitstop_sec: float = 0.012
@export var spawn_stagger_sec: float = 0.0

var _hp: int = 36
var _defeated: bool = false
var _in_reserve: bool = false
var _flash_left_sec: float = 0.0
var _player: Player
var _players: Array[Player] = []
var _sim_authority: bool = true
var _sim_paused: bool = false
var _knockback_velocity: Vector2 = Vector2.ZERO
var _hitstop_left_sec: float = 0.0
var _was_in_hitstop: bool = false
var _hit_reaction: HitReaction
var _sfx_pool: SfxPool
var _player_camera: PlayerCamera
var _shard_pool: DeathShardPool
var _spawn_position: Vector2 = Vector2.ZERO
var _spawn_stagger_left_sec: float = 0.0
var _spawn_stagger_duration_sec: float = 0.0
var _separation_sign: float = 1.0
var _base_max_hp: int = 0
var _base_move_speed: float = 0.0
var _flip_h: bool = false
var _hp_bar: WorldHpBar

@onready var _visual: Sprite2D = $Visual

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = GameCollisionLayers.MASK_ENEMY
	collision_mask = GameCollisionLayers.MASK_WALL
	_hp = max_hp
	_spawn_position = global_position
	_separation_sign = 1.0 if (get_index() % 2 == 0) else -1.0
	_setup_visual()
	_bind_hit_reaction()
	_bind_hp_bar()
	_layout_hp_bar()
	_refresh_hp_bar()
	_base_max_hp = max_hp
	_base_move_speed = move_speed

func bind_player(player: Player) -> void:
	_player = player
	_players.clear()
	if player != null:
		_players.append(player)

func bind_players(players: Array[Player]) -> void:
	_players = players.duplicate()
	if players.is_empty():
		_player = null
		return
	_player = players[0]

func set_sim_authority(enabled: bool) -> void:
	_sim_authority = enabled

func set_sim_paused(paused: bool) -> void:
	_sim_paused = paused

func is_sim_authority() -> bool:
	return _sim_authority

func bind_sfx_pool(sfx_pool: SfxPool) -> void:
	_sfx_pool = sfx_pool

func bind_player_camera(player_camera: PlayerCamera) -> void:
	_player_camera = player_camera

func bind_shard_pool(pool: DeathShardPool) -> void:
	_shard_pool = pool

func get_hp() -> int:
	return _hp

func get_spawn_position() -> Vector2:
	return _spawn_position

func is_defeated() -> bool:
	return _defeated

func is_in_reserve() -> bool:
	return _in_reserve

func is_in_hitstop() -> bool:
	return _hitstop_left_sec > 0.0

func is_entering() -> bool:
	return not _in_reserve and _spawn_stagger_left_sec > 0.0

func get_hitstop_left_sec() -> float:
	return _hitstop_left_sec

func get_knockback_speed() -> float:
	return _knockback_velocity.length()

func get_kind_name() -> String:
	return "Enemy"

func _native_faces_right() -> bool:
	return true

func _base_visual_scale() -> Vector2:
	return Vector2.ONE

func _setup_visual() -> void:
	pass

func _apply_flip(flip_h: bool) -> void:
	if _visual != null:
		_visual.flip_h = flip_h

func get_xp_reward() -> int:
	return 0

func get_gold_reward() -> int:
	return 0

func get_hp_per_loop() -> int:
	return 0

func apply_loop_pressure(loop_index: int) -> void:
	var pressure: int = clampi(loop_index, 0, 8)
	max_hp = _base_max_hp + pressure * get_hp_per_loop()
	move_speed = _base_move_speed * (1.0 + 0.08 * float(pressure))
	_apply_damage_pressure(pressure)

func _apply_damage_pressure(_pressure: int) -> void:
	pass

func hold_in_reserve() -> void:
	_in_reserve = true
	_defeated = false
	_flash_left_sec = 0.0
	_knockback_velocity = Vector2.ZERO
	_hitstop_left_sec = 0.0
	_was_in_hitstop = false
	_spawn_stagger_left_sec = 0.0
	_spawn_stagger_duration_sec = 0.0
	spawn_stagger_sec = 0.0
	velocity = Vector2.ZERO
	global_position = _spawn_position
	collision_layer = GameCollisionLayers.MASK_NONE
	collision_mask = GameCollisionLayers.MASK_NONE
	visible = false
	_visual.modulate = Color.WHITE
	_visual.scale = _base_visual_scale()
	if _hit_reaction != null:
		_hit_reaction.reset()
	if _hp_bar != null:
		_hp_bar.set_shown(false)
	set_physics_process(false)
	set_process(false)
	_on_hold_in_reserve()

func activate_from_reserve() -> void:
	_in_reserve = false
	visible = true
	set_process(true)
	reset_for_sandbox(_spawn_position)

func reset_for_sandbox(spawn_position: Vector2) -> void:
	_in_reserve = false
	_spawn_position = spawn_position
	_hp = max_hp
	_defeated = false
	_flash_left_sec = 0.0
	_knockback_velocity = Vector2.ZERO
	_hitstop_left_sec = 0.0
	_was_in_hitstop = false
	spawn_stagger_sec = 0.0
	velocity = Vector2.ZERO
	global_position = spawn_position
	collision_layer = GameCollisionLayers.MASK_ENEMY
	collision_mask = GameCollisionLayers.MASK_WALL
	visible = true
	_visual.modulate = Color.WHITE
	_hit_reaction.reset()
	_layout_hp_bar()
	_refresh_hp_bar()
	_begin_enter()
	set_physics_process(true)
	set_process(true)
	_on_reset_for_sandbox()

func assign_spawn_stagger(stagger_sec: float) -> void:
	spawn_stagger_sec = clampf(stagger_sec, 0.0, 0.8)
	_spawn_stagger_duration_sec = spawn_stagger_sec
	_spawn_stagger_left_sec = spawn_stagger_sec
	_begin_enter()

func apply_damage(amount: int, hit_position: Vector2, hit_direction: Vector2 = Vector2.ZERO) -> void:
	if not _sim_authority:
		return
	if _in_reserve or _defeated or amount <= 0:
		return
	if is_entering():
		_finish_entering()
	var direction: Vector2 = _resolve_hit_direction(hit_direction)
	var was_alive: bool = _hp > 0
	_hp = maxi(0, _hp - amount)
	_refresh_hp_bar()
	_spawn_damage_number(amount, hit_position)
	_start_flash()
	_apply_knockback(direction)
	_start_hitstop()
	_hit_reaction.play(direction)
	_play_hit_feedback(hit_position, direction, was_alive and _hp <= 0)
	if _hp <= 0:
		_defeat()

func _physics_process(delta: float) -> void:
	if _in_reserve:
		return
	if not _sim_authority or _sim_paused:
		return
	if _defeated:
		_tick_death_slide(delta)
		return
	_tick_spawn_stagger(delta)
	if is_entering():
		return
	if _hitstop_left_sec > 0.0:
		_hitstop_left_sec = maxf(0.0, _hitstop_left_sec - delta)
		_was_in_hitstop = true
		return
	_apply_post_hitstop_velocity()
	_tick_ai(delta)
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, knockback_damping * delta)
	move_and_slide()
	_face_player()

func _process(delta: float) -> void:
	if _in_reserve:
		return
	_tick_flash(delta)
	_update_enter_scale()

func _tick_ai(_delta: float) -> void:
	pass

func _on_reset_for_sandbox() -> void:
	pass

func _on_hold_in_reserve() -> void:
	pass

func _steer_toward(delta: float, desired_velocity: Vector2) -> void:
	velocity = velocity.move_toward(desired_velocity, acceleration * delta)

func _desired_velocity_to_player() -> Vector2:
	var to_player: Vector2 = _to_player()
	if to_player.is_zero_approx():
		return Vector2.ZERO
	return to_player.normalized() * move_speed

func _separated_seek_velocity() -> Vector2:
	var desired: Vector2 = _desired_velocity_to_player()
	var to_player: Vector2 = _to_player()
	if to_player.is_zero_approx():
		return desired
	return desired + to_player.normalized().orthogonal() * _separation_sign * SEPARATION_PIXELS

func _player_alive() -> bool:
	return _find_target() != null

func _find_target() -> Player:
	var best: Player = null
	var best_d: float = INF
	for pawn: Player in _players:
		if pawn == null or pawn.is_defeated():
			continue
		var d: float = global_position.distance_squared_to(pawn.global_position)
		if d < best_d:
			best_d = d
			best = pawn
	if best != null:
		return best
	if _player != null and not _player.is_defeated():
		return _player
	return null

func _to_player() -> Vector2:
	var target: Player = _find_target()
	if target == null:
		return Vector2.ZERO
	return target.global_position - global_position


func apply_net_state(pos: Vector2, hp: int, defeated: bool, in_reserve: bool) -> void:
	if in_reserve:
		if not _in_reserve:
			hold_in_reserve()
		return
	if _in_reserve:
		_in_reserve = false
		visible = true
		set_process(true)
		set_physics_process(true)
		collision_layer = GameCollisionLayers.MASK_ENEMY
		collision_mask = GameCollisionLayers.MASK_WALL
	global_position = pos
	_hp = maxi(0, hp)
	_refresh_hp_bar()
	if defeated:
		if not _defeated:
			_defeat()
		return
	if _defeated:
		_defeated = false
		_visual.modulate = Color.WHITE
		_hit_reaction.reset()

func _face_player() -> void:
	var to_player: Vector2 = _to_player()
	_update_facing(to_player.x)

func _update_facing(dx: float) -> void:
	if absf(dx) > FACE_DEADZONE_PX:
		_flip_h = (dx > 0.0) != _native_faces_right()
	_apply_flip(_flip_h)

func _tick_flash(delta: float) -> void:
	if _flash_left_sec <= 0.0:
		return
	_flash_left_sec -= delta
	if _flash_left_sec <= 0.0:
		_restore_color()

func _start_flash() -> void:
	_flash_left_sec = FLASH_DURATION_SEC
	_visual.modulate = Color(2.2, 2.2, 2.2, 1)

func _restore_color() -> void:
	_visual.modulate = DEAD_COLOR if _defeated else Color.WHITE

func _defeat() -> void:
	_defeated = true
	_spawn_stagger_left_sec = 0.0
	collision_layer = GameCollisionLayers.MASK_NONE
	collision_mask = GameCollisionLayers.MASK_NONE
	_visual.modulate = DEAD_COLOR
	_hit_reaction.begin_death(true)
	_refresh_hp_bar()
	_spawn_death_shards()
	_on_defeated()
	defeated.emit()

func _on_defeated() -> void:
	pass

func _spawn_death_shards() -> void:
	if _in_reserve or not _defeated:
		return
	if _shard_pool == null:
		return
	var origin: Vector2 = global_position
	var base_angle: float = 0.0
	if not _knockback_velocity.is_zero_approx():
		base_angle = _knockback_velocity.angle()
	for i: int in DEATH_SHARD_COUNT:
		var shard: DeathShard = _shard_pool.acquire()
		if shard == null:
			return
		var angle: float = base_angle + float(i) * TAU / float(DEATH_SHARD_COUNT)
		shard.play(origin, Vector2.from_angle(angle))

func _spawn_damage_number(amount: int, hit_position: Vector2) -> void:
	DamageNumber.spawn(self, amount, hit_position)

func _bind_hit_reaction() -> void:
	_hit_reaction = HitReaction.new()
	_hit_reaction.name = "HitReaction"
	add_child(_hit_reaction)
	_hit_reaction.bind_visual(_visual)

func _bind_hp_bar() -> void:
	_hp_bar = WorldHpBar.new()
	_hp_bar.name = "HpBar"
	add_child(_hp_bar)

func _layout_hp_bar() -> void:
	if _hp_bar == null:
		return
	var texture: Texture2D = null
	if _visual != null:
		texture = _visual.texture
	var body_scale: Vector2 = _base_visual_scale()
	_hp_bar.configure(
		WorldHpBar.FILL_ENEMY,
		WorldHpBar.y_for_sprite(texture, body_scale),
		WorldHpBar.width_for_sprite(texture, body_scale)
	)

func _refresh_hp_bar() -> void:
	if _hp_bar == null:
		return
	_hp_bar.bind_hp(_hp, max_hp)
	_hp_bar.set_shown(not _in_reserve and not _defeated)

func _resolve_hit_direction(hit_direction: Vector2) -> Vector2:
	if not hit_direction.is_zero_approx():
		return hit_direction.normalized()
	var away: Vector2 = -_to_player()
	if away.is_zero_approx():
		return Vector2.RIGHT
	return away.normalized()

func _apply_knockback(direction: Vector2) -> void:
	_knockback_velocity += direction * knockback_impulse
	var speed: float = _knockback_velocity.length()
	if speed > knockback_max_speed:
		_knockback_velocity = _knockback_velocity * (knockback_max_speed / speed)

func _start_hitstop() -> void:
	_hitstop_left_sec = maxf(_hitstop_left_sec, hitstop_sec)

func _play_hit_feedback(hit_position: Vector2, direction: Vector2, killed: bool) -> void:
	if _sfx_pool != null:
		_sfx_pool.play_hit(hit_position)
		if killed:
			_sfx_pool.play_kill(hit_position)
	if _player_camera == null:
		return
	_player_camera.apply_kick(direction, 4.0 if killed else 2.0)

func _apply_post_hitstop_velocity() -> void:
	if not _was_in_hitstop:
		return
	velocity = _knockback_velocity
	_was_in_hitstop = false

func _tick_death_slide(delta: float) -> void:
	if _hitstop_left_sec > 0.0:
		_hitstop_left_sec = maxf(0.0, _hitstop_left_sec - delta)
		_was_in_hitstop = true
		return
	_apply_post_hitstop_velocity()
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, knockback_damping * delta)
	if _knockback_velocity.length() < DEATH_SLIDE_STOP_SPEED:
		velocity = Vector2.ZERO
		_knockback_velocity = Vector2.ZERO
		set_physics_process(false)
		return
	velocity = _knockback_velocity
	move_and_slide()

func _begin_enter() -> void:
	_spawn_stagger_duration_sec = spawn_stagger_sec
	_spawn_stagger_left_sec = spawn_stagger_sec
	if _spawn_stagger_left_sec <= 0.0:
		_visual.scale = _base_visual_scale()
		return
	_visual.scale = _base_visual_scale() * ENTER_SCALE_FROM

func _finish_entering() -> void:
	_spawn_stagger_left_sec = 0.0
	if _visual != null and not _defeated:
		_visual.scale = _base_visual_scale()

func _tick_spawn_stagger(delta: float) -> void:
	if _spawn_stagger_left_sec <= 0.0:
		return
	_spawn_stagger_left_sec = maxf(0.0, _spawn_stagger_left_sec - delta)
	if _spawn_stagger_left_sec <= 0.0:
		_finish_entering()

func _update_enter_scale() -> void:
	if _defeated or _spawn_stagger_duration_sec <= 0.0 or _spawn_stagger_left_sec <= 0.0:
		return
	var t: float = 1.0 - (_spawn_stagger_left_sec / _spawn_stagger_duration_sec)
	_visual.scale = (_base_visual_scale() * ENTER_SCALE_FROM).lerp(_base_visual_scale(), clampf(t, 0.0, 1.0))
