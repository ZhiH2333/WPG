extends StaticBody2D
class_name DummyTarget

const FLASH_DURATION_SEC: float = 0.1
const ALIVE_COLOR: Color = Color(0.86, 0.22, 0.2, 1)
const DEAD_COLOR: Color = Color(0.42, 0.42, 0.44, 1)

@export var max_hp: int = 80

var _hp: int = 80
var _defeated: bool = false
var _flash_left_sec: float = 0.0

@onready var _visual: Polygon2D = $Visual

func _ready() -> void:
	collision_layer = GameCollisionLayers.MASK_ENEMY
	collision_mask = GameCollisionLayers.MASK_NONE
	_hp = max_hp
	_visual.color = ALIVE_COLOR

func get_hp() -> int:
	return _hp

func is_defeated() -> bool:
	return _defeated

func apply_damage(amount: int, hit_position: Vector2, _hit_direction: Vector2 = Vector2.ZERO) -> void:
	if _defeated:
		return
	_hp = maxi(0, _hp - amount)
	_spawn_damage_number(amount, hit_position)
	_start_flash()
	if _hp <= 0:
		_defeat()

func _process(delta: float) -> void:
	if _flash_left_sec <= 0.0:
		return
	_flash_left_sec -= delta
	if _flash_left_sec <= 0.0:
		_restore_color()

func _start_flash() -> void:
	_flash_left_sec = FLASH_DURATION_SEC
	_visual.modulate = Color(2.2, 2.2, 2.2, 1)

func _restore_color() -> void:
	_visual.modulate = Color.WHITE
	if _defeated:
		_visual.color = DEAD_COLOR

func _defeat() -> void:
	_defeated = true
	collision_layer = GameCollisionLayers.MASK_NONE

func _spawn_damage_number(amount: int, hit_position: Vector2) -> void:
	DamageNumber.spawn(self, amount, hit_position)
