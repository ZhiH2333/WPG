## 加速度移动 + 瞄准朝向。枪口在 Visual 上；开火逻辑在 Pistol，不写在本脚本。
extends CharacterBody2D
class_name Player

@onready var _player_input: PlayerInput = $PlayerInput
@onready var _player_motor: PlayerMotor = $PlayerMotor
@onready var _visual: Node2D = $Visual
@onready var _muzzle: Marker2D = $Visual/Muzzle
@onready var _pistol: Pistol = $Pistol

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = GameCollisionLayers.MASK_PLAYER
	collision_mask = GameCollisionLayers.MASK_WALL
	_pistol.bind_player_input(_player_input)

func get_player_input() -> PlayerInput:
	return _player_input

func get_pistol() -> Pistol:
	return _pistol

func get_muzzle_global_position() -> Vector2:
	return _muzzle.global_position

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pistol.bind_projectile_pool(pool)

func _process(_delta: float) -> void:
	_face_aim()

func _physics_process(delta: float) -> void:
	_apply_motor(delta)

func _apply_motor(delta: float) -> void:
	velocity = _player_motor.tick(delta, velocity, _player_input.move_vector)
	move_and_slide()

func _face_aim() -> void:
	var aim: Vector2 = _player_input.aim_vector
	if aim.is_zero_approx():
		return
	_visual.rotation = aim.angle()
