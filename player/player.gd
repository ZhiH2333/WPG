## 加速度移动 + 瞄准朝向。枪口在 Visual 上；开火由 WeaponHost 当前枪负责。
extends CharacterBody2D
class_name Player

const KNOCKBACK_DAMPING: float = 1800.0

@export var knockback_impulse: float = 180.0
@export var knockback_max_speed: float = 260.0

var _knockback_velocity: Vector2 = Vector2.ZERO
var _character_id: String = "boar"
var _hit_reaction: HitReaction
var _spawn_position: Vector2 = Vector2.ZERO
var _simulate_combat: bool = true
var _sim_paused: bool = false

signal shot_fired(aim: Vector2, weapon: Weapon)

@onready var _player_input: PlayerInput = $PlayerInput
@onready var _player_motor: PlayerMotor = $PlayerMotor
@onready var _player_health: PlayerHealth = $PlayerHealth
@onready var _player_dash: PlayerDash = $PlayerDash
@onready var _visual: Node2D = $Visual
@onready var _body: Sprite2D = $Visual/Body
@onready var _guns: Node2D = $Visual/Guns
@onready var _muzzle: Marker2D = $Visual/Guns/Muzzle
@onready var _weapon_host: WeaponHost = $WeaponHost
@onready var _fire_feedback: FireFeedback = $FireFeedback
@onready var _hurtbox: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = GameCollisionLayers.MASK_PLAYER
	collision_mask = GameCollisionLayers.MASK_WALL
	_spawn_position = global_position
	_setup_body_visual()
	_weapon_host.bind_player_input(_player_input)
	_player_dash.bind_player_input(_player_input)
	_bind_hit_reaction()

func _setup_body_visual() -> void:
	_body.texture = load(FacingContract.PLAYER_TEXTURE) as Texture2D
	_body.centered = true
	_body.rotation = 0.0
	_body.scale = FacingContract.PLAYER_BODY_SCALE

func get_player_input() -> PlayerInput:
	return _player_input

func get_player_health() -> PlayerHealth:
	return _player_health

func get_player_motor() -> PlayerMotor:
	return _player_motor

func get_player_dash() -> PlayerDash:
	return _player_dash

func get_weapon_host() -> WeaponHost:
	return _weapon_host

func get_character_id() -> String:
	return _character_id

func get_facing_flip() -> bool:
	return _body.flip_h

func apply_character(def: CharacterDef) -> void:
	if def == null:
		return
	_character_id = String(def.id)
	_player_health.set_full_max_hp(def.base_max_hp)
	_player_health.i_frame_sec = def.base_i_frame_sec
	_player_motor.move_speed = def.base_move_speed
	_player_motor.acceleration = def.base_acceleration
	_player_motor.deceleration = def.base_deceleration
	_player_motor.friction = def.base_friction
	_player_motor.turn_angle_degrees = def.base_turn_angle_degrees
	_apply_hurtbox_radius(def.hurtbox_radius)
	_apply_body_visual(def)

func get_pistol() -> Pistol:
	return _weapon_host.get_pistol()

func get_muzzle_global_position() -> Vector2:
	return _muzzle.global_position

func is_defeated() -> bool:
	return _player_health.is_defeated()

func is_dashing() -> bool:
	return _player_dash.is_dashing()

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_weapon_host.bind_projectile_pool(pool)

func bind_sfx_pool(sfx_pool: SfxPool) -> void:
	_fire_feedback.bind_sfx_pool(sfx_pool)
	_player_dash.bind_sfx_pool(sfx_pool)

func bind_player_camera(player_camera: PlayerCamera) -> void:
	_fire_feedback.bind_camera(player_camera)
	_player_dash.bind_player_camera(player_camera)

func notify_shot_fired(aim: Vector2, weapon: Weapon) -> void:
	_fire_feedback.play_shot(aim, weapon)
	shot_fired.emit(aim, weapon)

func play_shot_fx(aim: Vector2, weapon: Weapon) -> void:
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

func clear_knockback() -> void:
	_knockback_velocity = Vector2.ZERO

func play_hit_reaction(hit_direction: Vector2) -> void:
	_hit_reaction.play(hit_direction)

func begin_death_pose() -> void:
	_fire_feedback.stop_recoil()
	_hit_reaction.begin_death(false)

func on_defeated() -> void:
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_weapon_host.deactivate_all()
	_player_dash.reset_for_sandbox()

func can_simulate_combat() -> bool:
	return _simulate_combat and not _sim_paused

func set_simulate_combat(enabled: bool) -> void:
	_simulate_combat = enabled

func set_sim_paused(paused: bool) -> void:
	_sim_paused = paused

func set_spawn_position(pos: Vector2) -> void:
	_spawn_position = pos

func get_spawn_position() -> Vector2:
	return _spawn_position

func apply_net_pose(pos: Vector2, vel: Vector2, aim: Vector2, hp: int, max_hp: int, defeated: bool, weapon_index: int, facing_flip: bool = false, apply_aim: bool = true) -> void:
	global_position = pos
	velocity = vel
	var player_input: PlayerInput = get_player_input()
	if apply_aim and not aim.is_zero_approx():
		player_input.aim_vector = aim
		_face_aim()
	_body.flip_h = facing_flip
	get_weapon_host().force_index(weapon_index)
	get_player_health().apply_net_state(hp, max_hp, defeated)

func reset_for_sandbox() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_player_health.reset_for_sandbox()
	_player_dash.reset_for_sandbox()
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
	if _sim_paused:
		velocity = Vector2.ZERO
		return
	if not _simulate_combat:
		_face_aim()
		return
	_player_dash.try_dash()
	_apply_motor(delta)

func _apply_motor(delta: float) -> void:
	var was_dashing: bool = _player_dash.is_dashing()
	var dash_velocity: Vector2 = _player_dash.tick(delta, velocity)
	if was_dashing:
		velocity = dash_velocity
		move_and_slide()
		return
	var motor_current: Vector2 = velocity - _knockback_velocity
	var motor_velocity: Vector2 = _player_motor.tick(delta, motor_current, _player_input.move_vector)
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DAMPING * delta)
	velocity = motor_velocity + _knockback_velocity
	move_and_slide()

func _face_aim() -> void:
	var aim: Vector2 = _player_input.aim_vector
	if aim.is_zero_approx():
		return
	_guns.rotation = aim.angle()

func _bind_hit_reaction() -> void:
	_hit_reaction = HitReaction.new()
	_hit_reaction.name = "HitReaction"
	add_child(_hit_reaction)
	_hit_reaction.bind_visual(_visual)

func _apply_hurtbox_radius(radius: float) -> void:
	var circle: CircleShape2D = _hurtbox.shape as CircleShape2D
	if circle == null:
		return
	circle.radius = radius

func _apply_body_visual(def: CharacterDef) -> void:
	var texture: Texture2D = def.body_texture
	if texture == null:
		texture = load(FacingContract.PLAYER_TEXTURE) as Texture2D
	_body.texture = texture
	_body.scale = def.body_scale
