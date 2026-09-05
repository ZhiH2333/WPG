## Day 1 占位：碰撞 + 朝向瞄准。不做 Motor，不写 velocity。
extends CharacterBody2D
class_name Player

@onready var _player_input: PlayerInput = $PlayerInput
@onready var _visual: Node2D = $Visual

func _ready() -> void:
	collision_layer = GameCollisionLayers.MASK_PLAYER
	collision_mask = GameCollisionLayers.MASK_WALL

func get_player_input() -> PlayerInput:
	return _player_input

func _process(_delta: float) -> void:
	_face_aim()

func _face_aim() -> void:
	var aim: Vector2 = _player_input.aim_vector
	if aim.is_zero_approx():
		return
	_visual.rotation = aim.angle()
