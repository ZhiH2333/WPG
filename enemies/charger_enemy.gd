extends EnemyBase
class_name ChargerEnemy

## 直线冲锋：先对准再撞。SEEK 贴脸用接触伤害；冲锋必须侧闪。状态只活在本脚本。
enum ChargeState { SEEK, WINDUP, CHARGE, RECOVER }

const WINDUP_MODULATE := Color(1.6, 1.45, 0.7, 1)
const CHARGE_MODULATE := Color(1.55, 1.35, 0.45, 1)
const WINDUP_SCALE := Vector2(1.25, 0.85)
const CHARGE_KICK: float = 5.0

@export var contact_damage: int = 8
@export var charge_damage: int = 16
@export var charge_speed: float = 520.0
@export var charge_distance: float = 380.0
@export var windup_sec: float = 0.45
@export var recover_sec: float = 0.55
@export var charge_cooldown_sec: float = 1.60
@export var min_charge_range: float = 180.0
@export var max_charge_range: float = 520.0

var _base_contact_damage: int = 0
var _base_charge_damage: int = 0
var _charge_state: ChargeState = ChargeState.SEEK
var _charge_dir: Vector2 = Vector2.RIGHT
var _windup_left_sec: float = 0.0
var _recover_left_sec: float = 0.0
var _charge_cooldown_left_sec: float = 0.0
var _charge_traveled: float = 0.0

@onready var _contact_area: Area2D = $ContactArea

func _ready() -> void:
	max_hp = 44
	move_speed = 160.0
	acceleration = 1600.0
	knockback_impulse = 200.0
	super._ready()
	_base_contact_damage = contact_damage
	_base_charge_damage = charge_damage
	_bind_contact_area()

func get_kind_name() -> String:
	return "Charger"

func get_xp_reward() -> int:
	return 16

func get_gold_reward() -> int:
	return 5

func get_hp_per_loop() -> int:
	return 8

func get_contact_damage_per_loop() -> int:
	return 2

func is_charging() -> bool:
	return _charge_state == ChargeState.CHARGE

func _apply_damage_pressure(pressure: int) -> void:
	contact_damage = _base_contact_damage + pressure * get_contact_damage_per_loop()
	charge_damage = _base_charge_damage + pressure * get_contact_damage_per_loop()

func _bind_contact_area() -> void:
	_contact_area.collision_layer = GameCollisionLayers.MASK_NONE
	_contact_area.collision_mask = GameCollisionLayers.MASK_PLAYER
	_contact_area.monitorable = false
	_contact_area.monitoring = true
	_contact_area.body_entered.connect(_on_contact_body_entered)

func _process(delta: float) -> void:
	super._process(delta)
	_refresh_charge_visual()

func _tick_ai(delta: float) -> void:
	if is_in_reserve() or is_in_hitstop() or _defeated or is_entering():
		return
	if not _player_alive():
		_interrupt_charge()
		_steer_toward(delta, Vector2.ZERO)
		return
	match _charge_state:
		ChargeState.SEEK:
			_tick_seek(delta)
		ChargeState.WINDUP:
			_tick_windup(delta)
		ChargeState.CHARGE:
			_tick_charge(delta)
		ChargeState.RECOVER:
			_tick_recover(delta)

func _tick_seek(delta: float) -> void:
	if _charge_cooldown_left_sec > 0.0:
		_charge_cooldown_left_sec = maxf(0.0, _charge_cooldown_left_sec - delta)
	_steer_toward(delta, _separated_seek_velocity())
	_try_contact_damage()
	if _charge_cooldown_left_sec > 0.0 or not _player_alive():
		return
	var distance: float = _to_player().length()
	if distance >= min_charge_range and distance <= max_charge_range:
		_enter_windup()

func _tick_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_windup_left_sec = maxf(0.0, _windup_left_sec - delta)
	if _windup_left_sec > 0.0:
		return
	_enter_charge()

func _tick_charge(delta: float) -> void:
	_knockback_velocity = Vector2.ZERO
	velocity = _charge_dir * charge_speed
	_charge_traveled += charge_speed * delta
	_try_contact_damage()
	if _charge_state != ChargeState.CHARGE:
		return
	if _charge_traveled >= charge_distance or is_on_wall():
		_enter_recover()

func _tick_recover(delta: float) -> void:
	_steer_toward(delta, Vector2.ZERO)
	_try_contact_damage()
	_recover_left_sec = maxf(0.0, _recover_left_sec - delta)
	if _recover_left_sec > 0.0:
		return
	_enter_seek()

func _enter_windup() -> void:
	_charge_state = ChargeState.WINDUP
	_windup_left_sec = windup_sec
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_refresh_charge_visual()

func _enter_charge() -> void:
	_charge_state = ChargeState.CHARGE
	_charge_dir = _lock_charge_dir()
	_charge_traveled = 0.0
	_knockback_velocity = Vector2.ZERO
	velocity = _charge_dir * charge_speed
	_refresh_charge_visual()
	if _sfx_pool != null:
		_sfx_pool.play_charge(global_position)

func _enter_recover() -> void:
	_charge_state = ChargeState.RECOVER
	_recover_left_sec = recover_sec
	_knockback_velocity = Vector2.ZERO
	_refresh_charge_visual()

func _enter_seek() -> void:
	_charge_state = ChargeState.SEEK
	_charge_cooldown_left_sec = charge_cooldown_sec
	_charge_traveled = 0.0
	_refresh_charge_visual()

func _interrupt_charge() -> void:
	_charge_state = ChargeState.SEEK
	_windup_left_sec = 0.0
	_recover_left_sec = 0.0
	_charge_traveled = 0.0
	_refresh_charge_visual()

func _lock_charge_dir() -> Vector2:
	var to_player: Vector2 = _to_player()
	if to_player.is_finite() and not to_player.is_zero_approx():
		return to_player.normalized()
	return Vector2.RIGHT

func _face_player() -> void:
	if _charge_state == ChargeState.CHARGE:
		if _charge_dir.is_zero_approx():
			return
		_hit_reaction.apply_facing(_charge_dir.angle())
		return
	super._face_player()

func _apply_knockback(direction: Vector2) -> void:
	if _charge_state == ChargeState.CHARGE:
		return
	super._apply_knockback(direction)

func _on_contact_body_entered(body: Node) -> void:
	_try_hit_player(body)

func _try_contact_damage() -> void:
	if is_in_reserve() or not _contact_area.monitoring or is_entering() or _defeated:
		return
	if _charge_state == ChargeState.WINDUP:
		return
	for body: Node2D in _contact_area.get_overlapping_bodies():
		var was_charging: bool = _charge_state == ChargeState.CHARGE
		_try_hit_player(body)
		if was_charging and _charge_state == ChargeState.RECOVER:
			return

func _try_hit_player(body: Node) -> void:
	if is_in_reserve() or not _player_alive() or is_in_hitstop() or _defeated or is_entering():
		return
	if _charge_state == ChargeState.WINDUP:
		return
	var player: Player = body as Player
	if player == null:
		return
	var direction: Vector2 = player.global_position - global_position
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	var amount: int = charge_damage if _charge_state == ChargeState.CHARGE else contact_damage
	var health: PlayerHealth = player.get_player_health()
	var hp_before: int = health.get_hp()
	health.apply_damage(amount, global_position, direction)
	if _charge_state != ChargeState.CHARGE:
		return
	if health.get_hp() >= hp_before:
		return
	if _player_camera != null:
		_player_camera.apply_kick(direction, CHARGE_KICK)
	_enter_recover()

func _refresh_charge_visual() -> void:
	if _visual == null or _defeated or is_in_reserve() or is_entering():
		return
	if _flash_left_sec > 0.0:
		return
	if _charge_state == ChargeState.WINDUP:
		_visual.modulate = WINDUP_MODULATE
		_visual.scale = WINDUP_SCALE
		return
	if _charge_state == ChargeState.CHARGE:
		_visual.modulate = CHARGE_MODULATE
		_visual.scale = Vector2.ONE
		return
	_visual.modulate = Color.WHITE
	_visual.scale = Vector2.ONE

func _reset_charge_logic() -> void:
	_charge_state = ChargeState.SEEK
	_charge_dir = Vector2.RIGHT
	_windup_left_sec = 0.0
	_recover_left_sec = 0.0
	_charge_cooldown_left_sec = 0.0
	_charge_traveled = 0.0

func _on_defeated() -> void:
	_reset_charge_logic()
	_contact_area.set_deferred("monitoring", false)

func _on_hold_in_reserve() -> void:
	_reset_charge_logic()
	_contact_area.monitoring = false
	_contact_area.set_deferred("monitoring", false)

func _on_reset_for_sandbox() -> void:
	_reset_charge_logic()
	_contact_area.monitoring = true
	_contact_area.set_deferred("monitoring", true)
