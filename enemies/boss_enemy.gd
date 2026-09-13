extends EnemyBase
class_name BossEnemy

## 一轮一次高潮：先冲再喷扇形弹。无阶段、无召唤。状态只活在本脚本。
enum BossState { SEEK, WINDUP_CHARGE, CHARGE, RECOVER, WINDUP_VOLLEY }

const WINDUP_CHARGE_STRETCH := Vector2(1.18, 0.88)
const WINDUP_CHARGE_MODULATE := Color(1.45, 0.85, 1.7, 1)
const CHARGE_MODULATE := Color(1.35, 0.55, 1.55, 1)
const VOLLEY_MODULATE := Color(0.85, 0.35, 1.15, 1)
const CHARGE_KICK: float = 7.0

@export var contact_damage: int = 16
@export var charge_damage: int = 26
@export var charge_speed: float = 480.0
@export var charge_distance: float = 400.0
@export var charge_windup_sec: float = 0.70
@export var recover_sec: float = 0.70
@export var volley_windup_sec: float = 0.40
@export var volley_count: int = 5
@export var volley_spread_deg: float = 18.0
@export var projectile_speed: float = 400.0
@export var projectile_damage: int = 10
@export var projectile_lifetime: float = 1.3
@export var projectile_visual_scale: float = 1.6
@export var min_charge_range: float = 160.0
@export var max_charge_range: float = 560.0

var _base_contact_damage: int = 0
var _base_charge_damage: int = 0
var _base_projectile_damage: int = 0
var _boss_state: BossState = BossState.SEEK
var _charge_dir: Vector2 = Vector2.RIGHT
var _windup_charge_left_sec: float = 0.0
var _recover_left_sec: float = 0.0
var _volley_windup_left_sec: float = 0.0
var _charge_traveled: float = 0.0
var _pool: ProjectilePool

@onready var _contact_area: Area2D = $ContactArea
@onready var _muzzle: Marker2D = $Visual/Muzzle

func _ready() -> void:
	max_hp = 220
	move_speed = 110.0
	acceleration = 900.0
	knockback_impulse = 90.0
	super._ready()
	_base_contact_damage = contact_damage
	_base_charge_damage = charge_damage
	_base_projectile_damage = projectile_damage
	_bind_contact_area()
	_restore_visual_scale()

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool

func get_kind_name() -> String:
	return "Boss"

func _native_faces_right() -> bool:
	return FacingContract.BOSS_NATIVE_FACES_RIGHT

func _base_visual_scale() -> Vector2:
	return FacingContract.BOSS_BASE_SCALE

func _setup_visual() -> void:
	_visual.texture = load(FacingContract.BOSS_TEXTURE) as Texture2D
	_visual.centered = true
	_visual.scale = FacingContract.BOSS_BASE_SCALE

func _apply_flip(flip_h: bool) -> void:
	super._apply_flip(flip_h)
	if _muzzle != null:
		_muzzle.position.x = absf(_muzzle.position.x) * (-1.0 if flip_h else 1.0)

func get_xp_reward() -> int:
	return 60

func get_gold_reward() -> int:
	return 18

func get_hp_per_loop() -> int:
	return 24

func get_contact_damage_per_loop() -> int:
	return 3

func get_projectile_damage_per_loop() -> int:
	return 2

func is_charging() -> bool:
	return _boss_state == BossState.CHARGE

func is_winding_volley() -> bool:
	return _boss_state == BossState.WINDUP_VOLLEY

func _apply_damage_pressure(pressure: int) -> void:
	contact_damage = _base_contact_damage + pressure * get_contact_damage_per_loop()
	charge_damage = _base_charge_damage + pressure * get_contact_damage_per_loop()
	projectile_damage = _base_projectile_damage + pressure * get_projectile_damage_per_loop()

func _bind_contact_area() -> void:
	_contact_area.collision_layer = GameCollisionLayers.MASK_NONE
	_contact_area.collision_mask = GameCollisionLayers.MASK_PLAYER
	_contact_area.monitorable = false
	_contact_area.monitoring = true
	_contact_area.body_entered.connect(_on_contact_body_entered)

func _process(delta: float) -> void:
	super._process(delta)
	_refresh_boss_visual()

func _tick_ai(delta: float) -> void:
	if is_in_reserve() or is_in_hitstop() or _defeated or is_entering():
		return
	if not _player_alive():
		_interrupt_boss()
		_steer_toward(delta, Vector2.ZERO)
		return
	match _boss_state:
		BossState.SEEK:
			_tick_seek(delta)
		BossState.WINDUP_CHARGE:
			_tick_windup_charge(delta)
		BossState.CHARGE:
			_tick_charge(delta)
		BossState.RECOVER:
			_tick_recover(delta)
		BossState.WINDUP_VOLLEY:
			_tick_windup_volley(delta)

func _tick_seek(delta: float) -> void:
	_steer_toward(delta, _separated_seek_velocity())
	_try_contact_damage()
	if not _player_alive():
		return
	var distance: float = _to_player().length()
	if distance >= min_charge_range and distance <= max_charge_range:
		_enter_windup_charge()

func _tick_windup_charge(delta: float) -> void:
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_windup_charge_left_sec = maxf(0.0, _windup_charge_left_sec - delta)
	if _windup_charge_left_sec > 0.0:
		return
	_enter_charge()

func _tick_charge(delta: float) -> void:
	_knockback_velocity = Vector2.ZERO
	velocity = _charge_dir * charge_speed
	_charge_traveled += charge_speed * delta
	_try_contact_damage()
	if _boss_state != BossState.CHARGE:
		return
	if _charge_traveled >= charge_distance or is_on_wall():
		_enter_recover()

func _tick_recover(delta: float) -> void:
	_steer_toward(delta, Vector2.ZERO)
	_try_contact_damage()
	_recover_left_sec = maxf(0.0, _recover_left_sec - delta)
	if _recover_left_sec > 0.0:
		return
	_enter_windup_volley()

func _tick_windup_volley(delta: float) -> void:
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_volley_windup_left_sec = maxf(0.0, _volley_windup_left_sec - delta)
	if _volley_windup_left_sec > 0.0:
		return
	_fire_volley()

func _enter_windup_charge() -> void:
	_boss_state = BossState.WINDUP_CHARGE
	_windup_charge_left_sec = charge_windup_sec
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_refresh_boss_visual()

func _enter_charge() -> void:
	_boss_state = BossState.CHARGE
	_charge_dir = _lock_charge_dir()
	_charge_traveled = 0.0
	_knockback_velocity = Vector2.ZERO
	velocity = _charge_dir * charge_speed
	_refresh_boss_visual()
	if _sfx_pool != null:
		_sfx_pool.play_charge(global_position)

func _enter_recover() -> void:
	_boss_state = BossState.RECOVER
	_recover_left_sec = recover_sec
	_knockback_velocity = Vector2.ZERO
	_refresh_boss_visual()

func _enter_windup_volley() -> void:
	_boss_state = BossState.WINDUP_VOLLEY
	_volley_windup_left_sec = volley_windup_sec
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_refresh_boss_visual()

func _enter_seek() -> void:
	_boss_state = BossState.SEEK
	_charge_traveled = 0.0
	_refresh_boss_visual()

func _interrupt_boss() -> void:
	_boss_state = BossState.SEEK
	_windup_charge_left_sec = 0.0
	_recover_left_sec = 0.0
	_volley_windup_left_sec = 0.0
	_charge_traveled = 0.0
	_refresh_boss_visual()

func _lock_charge_dir() -> Vector2:
	var to_player: Vector2 = _to_player()
	if to_player.is_finite() and not to_player.is_zero_approx():
		return to_player.normalized()
	return Vector2.RIGHT

func _fire_volley() -> void:
	var aim: Vector2 = _to_player()
	if not aim.is_finite() or aim.is_zero_approx():
		aim = Vector2.RIGHT
	else:
		aim = aim.normalized()
	var half: int = volley_count / 2
	if _pool != null and _muzzle != null:
		for i: int in volley_count:
			var offset: int = i - half
			var dir: Vector2 = aim.rotated(deg_to_rad(float(offset) * volley_spread_deg))
			var projectile: Projectile = _pool.acquire()
			if projectile == null:
				continue
			projectile.reset(
				_muzzle.global_position,
				dir * projectile_speed,
				projectile_damage,
				projectile_lifetime,
				projectile_visual_scale,
				false
			)
	if _sfx_pool != null:
		_sfx_pool.play_enemy_shot(_muzzle.global_position if _muzzle != null else global_position)
	_enter_seek()

func _face_player() -> void:
	if _boss_state == BossState.CHARGE:
		_update_facing(_charge_dir.x)
		return
	super._face_player()

func _apply_knockback(direction: Vector2) -> void:
	if _boss_state == BossState.CHARGE:
		return
	super._apply_knockback(direction)

func _on_contact_body_entered(body: Node) -> void:
	_try_hit_player(body)

func _try_contact_damage() -> void:
	if is_in_reserve() or not _contact_area.monitoring or is_entering() or _defeated:
		return
	if _boss_state == BossState.WINDUP_CHARGE or _boss_state == BossState.WINDUP_VOLLEY:
		return
	for body: Node2D in _contact_area.get_overlapping_bodies():
		var was_charging: bool = _boss_state == BossState.CHARGE
		_try_hit_player(body)
		if was_charging and _boss_state == BossState.RECOVER:
			return

func _try_hit_player(body: Node) -> void:
	if is_in_reserve() or not _player_alive() or is_in_hitstop() or _defeated or is_entering():
		return
	if _boss_state == BossState.WINDUP_CHARGE or _boss_state == BossState.WINDUP_VOLLEY:
		return
	var player: Player = body as Player
	if player == null:
		return
	var direction: Vector2 = player.global_position - global_position
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	var amount: int = charge_damage if _boss_state == BossState.CHARGE else contact_damage
	var health: PlayerHealth = player.get_player_health()
	var hp_before: int = health.get_hp()
	health.apply_damage(amount, global_position, direction)
	if _boss_state != BossState.CHARGE:
		return
	if health.get_hp() >= hp_before:
		return
	if _player_camera != null:
		_player_camera.apply_kick(direction, CHARGE_KICK)
	_enter_recover()

func _refresh_boss_visual() -> void:
	if _visual == null or _defeated or is_in_reserve() or is_entering():
		return
	if _flash_left_sec > 0.0:
		return
	if _boss_state == BossState.WINDUP_CHARGE:
		_visual.modulate = WINDUP_CHARGE_MODULATE
		_visual.scale = _base_visual_scale() * WINDUP_CHARGE_STRETCH
		return
	if _boss_state == BossState.CHARGE:
		_visual.modulate = CHARGE_MODULATE
		_visual.scale = _base_visual_scale()
		return
	if _boss_state == BossState.WINDUP_VOLLEY:
		_visual.modulate = VOLLEY_MODULATE
		_visual.scale = _base_visual_scale()
		return
	_visual.modulate = Color.WHITE
	_visual.scale = _base_visual_scale()

func _reset_boss_logic() -> void:
	_boss_state = BossState.SEEK
	_charge_dir = Vector2.RIGHT
	_windup_charge_left_sec = 0.0
	_recover_left_sec = 0.0
	_volley_windup_left_sec = 0.0
	_charge_traveled = 0.0

func _restore_visual_scale() -> void:
	if _visual == null or _defeated:
		return
	_visual.scale = _base_visual_scale()
	_visual.modulate = Color.WHITE

func _begin_enter() -> void:
	super._begin_enter()
	if _spawn_stagger_left_sec <= 0.0:
		_restore_visual_scale()
		return
	_visual.scale = _base_visual_scale() * ENTER_SCALE_FROM

func _finish_entering() -> void:
	super._finish_entering()
	_restore_visual_scale()

func _update_enter_scale() -> void:
	if _defeated or _spawn_stagger_duration_sec <= 0.0 or _spawn_stagger_left_sec <= 0.0:
		return
	var t: float = 1.0 - (_spawn_stagger_left_sec / _spawn_stagger_duration_sec)
	_visual.scale = (_base_visual_scale() * ENTER_SCALE_FROM).lerp(_base_visual_scale(), clampf(t, 0.0, 1.0))

func _on_defeated() -> void:
	_reset_boss_logic()
	_contact_area.set_deferred("monitoring", false)

func _on_hold_in_reserve() -> void:
	_reset_boss_logic()
	_contact_area.monitoring = false
	_contact_area.set_deferred("monitoring", false)
	_restore_visual_scale()

func _on_reset_for_sandbox() -> void:
	_reset_boss_logic()
	_contact_area.monitoring = true
	_contact_area.set_deferred("monitoring", true)
	if is_entering():
		_visual.scale = _base_visual_scale() * ENTER_SCALE_FROM
		return
	_restore_visual_scale()
