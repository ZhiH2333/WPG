## 加速度移动 + 瞄准朝向。枪口在 Visual 上；开火由 WeaponHost 当前枪负责。
extends CharacterBody2D
class_name Player

const KNOCKBACK_DAMPING: float = 1800.0

@export var knockback_impulse: float = 180.0
@export var knockback_max_speed: float = 260.0

var _knockback_velocity: Vector2 = Vector2.ZERO
var _hit_reaction: HitReaction

@onready var _player_input: PlayerInput = $PlayerInput
@onready var _player_motor: PlayerMotor = $PlayerMotor
@onready var _player_health: PlayerHealth = $PlayerHealth
@onready var _visual: Node2D = $Visual
@onready var _muzzle: Marker2D = $Visual/Muzzle
@onready var _weapon_host: WeaponHost = $WeaponHost
@onready var _fire_feedback: FireFeedback = $FireFeedback

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = GameCollisionLayers.MASK_PLAYER
	collision_mask = GameCollisionLayers.MASK_WALL
	_weapon_host.bind_player_input(_player_input)
	_bind_hit_reaction()

func get_player_input() -> PlayerInput:
	return _player_input

func get_player_health() -> PlayerHealth:
	return _player_health

func get_weapon_host() -> WeaponHost:
	return _weapon_host

func get_pistol() -> Pistol:
	return _weapon_host.get_pistol()

func get_muzzle_global_position() -> Vector2:
	return _muzzle.global_position

func is_defeated() -> bool:
	return _player_health.is_defeated()

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_weapon_host.bind_projectile_pool(pool)

func bind_sfx_pool(sfx_pool: SfxPool) -> void:
	_fire_feedback.bind_sfx_pool(sfx_pool)

func bind_player_camera(player_camera: PlayerCamera) -> void:
	_fire_feedback.bind_camera(player_camera)

func notify_shot_fired(aim: Vector2, weapon: Weapon) -> void:
	_fire_feedback.play_shot(aim, weapon)

func notify_shot_refused() -> void:
	_fire_feedback.play_refuse()

func notify_hurt(hit_direction: Vector2) -> void:
	_fire_feedback.play_hurt(hit_direction)

func apply_hit_knockback(hit_direction: Vector2) -> void:
	if is_defeated():
		return
	var direction: Vector2 = hit_direction
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	_knockback_velocity += direction * knockback_impulse
	var speed: float = _knockback_velocity.length()
	if speed > knockback_max_speed:
		_knockback_velocity = _knockback_velocity * (knockback_max_speed / speed)

func play_hit_reaction(hit_direction: Vector2) -> void:
	_hit_reaction.play(hit_direction)

func begin_death_pose() -> void:
	_fire_feedback.stop_recoil()
	_hit_reaction.begin_death(false)

func on_defeated() -> void:
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_weapon_host.deactivate_all()

func reset_for_sandbox() -> void:
	global_position = Vector2.ZERO
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_player_health.reset_for_sandbox()
	_hit_reaction.reset()
	_fire_feedback.stop_recoil()
	_weapon_host.reset_after_player_revive()

func _process(_delta: float) -> void:
	if is_defeated():
		return
	_face_aim()

func _physics_process(delta: float) -> void:
	if is_defeated():
		velocity = Vector2.ZERO
		return
	_apply_motor(delta)

func _apply_motor(delta: float) -> void:
	var motor_current: Vector2 = velocity - _knockback_velocity
	var motor_velocity: Vector2 = _player_motor.tick(delta, motor_current, _player_input.move_vector)
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DAMPING * delta)
	velocity = motor_velocity + _knockback_velocity
	move_and_slide()

func _face_aim() -> void:
	var aim: Vector2 = _player_input.aim_vector
	if aim.is_zero_approx():
		return
	_hit_reaction.apply_facing(aim.angle())

func _bind_hit_reaction() -> void:
	_hit_reaction = HitReaction.new()
	_hit_reaction.name = "HitReaction"
	add_child(_hit_reaction)
	_hit_reaction.bind_visual(_visual)
