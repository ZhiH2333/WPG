extends EnemyBase
class_name RangedEnemy

## 与玩家保持距离带；带内先红色瞄准线预警，再朝玩家当前位置开枪（实时追踪，不预判）。
@export var preferred_distance: float = 280.0
@export var distance_band: float = 70.0
@export var fire_interval: float = 0.9
@export var telegraph_sec: float = 0.6
@export var projectile_speed: float = 420.0
@export var projectile_damage: int = 6
@export var projectile_lifetime: float = 1.4

var _pool: ProjectilePool
var _next_fire_at_msec: int = 0
var _strafe_sign: float = 1.0
var _base_projectile_damage: int = 0
var _fire_telegraph_left_sec: float = 0.0
var _pending_fire_dir: Vector2 = Vector2.RIGHT

@onready var _muzzle: Marker2D = $Visual/Muzzle

func _ready() -> void:
	max_hp = 28
	move_speed = 140.0
	acceleration = 1200.0
	super._ready()
	_base_projectile_damage = projectile_damage
	_refresh_strafe_sign()

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool

func get_kind_name() -> String:
	return "Ranged"

func _native_faces_right() -> bool:
	return FacingContract.RANGED_NATIVE_FACES_RIGHT

func _base_visual_scale() -> Vector2:
	return FacingContract.RANGED_BASE_SCALE

func _setup_visual() -> void:
	_visual.texture = load(FacingContract.RANGED_TEXTURE) as Texture2D
	_visual.centered = true
	_visual.scale = FacingContract.RANGED_BASE_SCALE

func _apply_flip(flip_h: bool) -> void:
	super._apply_flip(flip_h)
	if _muzzle != null:
		_muzzle.position.x = absf(_muzzle.position.x) * (-1.0 if flip_h else 1.0)

func get_xp_reward() -> int:
	return 12

func get_gold_reward() -> int:
	return 4

func get_hp_per_loop() -> int:
	return 6

func get_projectile_damage_per_loop() -> int:
	return 1

func is_fire_telegraphing() -> bool:
	return _fire_telegraph_left_sec > 0.0

func get_pending_fire_direction() -> Vector2:
	return _pending_fire_dir

func _apply_damage_pressure(pressure: int) -> void:
	projectile_damage = _base_projectile_damage + pressure * get_projectile_damage_per_loop()

func _process(delta: float) -> void:
	super._process(delta)
	if not _sim_authority:
		return
	if is_in_reserve() or _defeated or is_in_hitstop() or is_entering():
		return
	_face_player()
	_tick_fire(delta)

func _tick_ai(delta: float) -> void:
	if is_in_reserve() or is_in_hitstop() or _defeated or is_entering():
		return
	if not _player_alive():
		_cancel_fire_telegraph()
		_steer_toward(delta, Vector2.ZERO)
		return
	_steer_toward(delta, _band_desired_velocity())

func _band_desired_velocity() -> Vector2:
	var to_player: Vector2 = _to_player()
	var distance: float = to_player.length()
	var inner: float = preferred_distance - distance_band
	var outer: float = preferred_distance + distance_band
	if distance < inner:
		return -to_player.normalized() * move_speed
	if distance > outer:
		return to_player.normalized() * move_speed
	return to_player.normalized().orthogonal() * _strafe_sign * move_speed * 0.45

func _tick_fire(delta: float) -> void:
	if is_in_reserve() or _defeated or is_in_hitstop() or is_entering() or not _player_alive() or _pool == null:
		_cancel_fire_telegraph()
		return
	if _fire_telegraph_left_sec > 0.0:
		_tick_fire_telegraph(delta)
		return
	if not _is_in_fire_band():
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < _next_fire_at_msec:
		return
	_begin_fire_telegraph()

func _tick_fire_telegraph(delta: float) -> void:
	if not _is_in_fire_band() or not _player_alive():
		_cancel_fire_telegraph()
		return
	refresh_attack_telegraph_aim()
	_pending_fire_dir = get_attack_telegraph_direction()
	var finished: bool = _telegraph.tick(delta)
	_fire_telegraph_left_sec = _telegraph.remaining
	_refresh_telegraph_drawer()
	if not finished:
		return
	var fire_dir: Vector2 = _pending_fire_dir
	_fire_telegraph_left_sec = 0.0
	clear_attack_telegraph()
	if not _try_fire_with_dir(fire_dir):
		_next_fire_at_msec = Time.get_ticks_msec()
		return
	_next_fire_at_msec = Time.get_ticks_msec() + _get_fire_interval_msec()

func _begin_fire_telegraph() -> void:
	var to_player: Vector2 = _to_player()
	var path_len: float = to_player.length() if not to_player.is_zero_approx() else preferred_distance
	var local_origin: Vector2 = Vector2.ZERO
	if _muzzle != null:
		local_origin = to_local(_muzzle.global_position)
	begin_attack_telegraph_aim(telegraph_sec, path_len, local_origin)
	_fire_telegraph_left_sec = telegraph_sec
	_pending_fire_dir = get_attack_telegraph_direction()

func _cancel_fire_telegraph() -> void:
	_fire_telegraph_left_sec = 0.0
	clear_attack_telegraph()

func _is_in_fire_band() -> bool:
	var distance: float = _to_player().length()
	var inner: float = preferred_distance - distance_band
	var outer: float = preferred_distance + distance_band
	return distance >= inner and distance <= outer

func _try_fire() -> bool:
	return _try_fire_with_dir(_to_player())

func _try_fire_with_dir(raw_dir: Vector2) -> bool:
	var projectile: Projectile = _pool.acquire()
	if projectile == null:
		return false
	var direction: Vector2 = raw_dir
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	_pending_fire_dir = direction
	projectile.reset(
		_muzzle.global_position,
		direction * projectile_speed,
		projectile_damage,
		projectile_lifetime,
		2.0,
		false
	)
	if _sfx_pool != null:
		_sfx_pool.play_enemy_shot(_muzzle.global_position)
	return true

func _get_fire_interval_msec() -> int:
	return maxi(1, int(round(fire_interval * 1000.0)))

func _on_hold_in_reserve() -> void:
	_next_fire_at_msec = 0
	_cancel_fire_telegraph()

func _on_reset_for_sandbox() -> void:
	_next_fire_at_msec = 0
	_cancel_fire_telegraph()
	_refresh_strafe_sign()

func _on_defeated() -> void:
	_cancel_fire_telegraph()

func _refresh_strafe_sign() -> void:
	_strafe_sign = 1.0 if global_position.x > 200.0 else -1.0
