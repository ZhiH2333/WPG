## 加速度移动 + 瞄准朝向。根节点不旋转；Visual 只跟 aim_vector。相机不写在 Player 里。
extends CharacterBody2D
class_name Player

@onready var _player_input: PlayerInput = $PlayerInput
@onready var _player_motor: PlayerMotor = $PlayerMotor
@onready var _visual: Node2D = $Visual

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = GameCollisionLayers.MASK_PLAYER
	collision_mask = GameCollisionLayers.MASK_WALL

func get_player_input() -> PlayerInput:
	return _player_input

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
