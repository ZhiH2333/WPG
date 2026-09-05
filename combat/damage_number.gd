extends Node2D
class_name DamageNumber

@export var duration_sec: float = 0.45
@export var rise_pixels: float = 50.0

var _age_sec: float = 0.0
var _start_position: Vector2 = Vector2.ZERO

@onready var _label: Label = $Label

func play(amount: int, world_position: Vector2) -> void:
	_start_position = world_position + Vector2(0.0, -12.0)
	global_position = _start_position
	_label.text = str(amount)
	_age_sec = 0.0

func _process(delta: float) -> void:
	_age_sec += delta
	var t: float = clampf(_age_sec / duration_sec, 0.0, 1.0)
	global_position = _start_position + Vector2(0.0, -rise_pixels * t)
	modulate.a = 1.0 - t
	if _age_sec >= duration_sec:
		queue_free()
