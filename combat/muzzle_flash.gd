extends Node2D
class_name MuzzleFlash

## 玩家枪口上的唯一闪光节点：show/hide + delta 倒数，禁止每发 instantiate。
var _left_sec: float = 0.0

@onready var _visual: Polygon2D = $Visual

func _ready() -> void:
	visible = false
	set_process(false)

func play(flash_scale: Vector2, duration_sec: float, color: Color) -> void:
	scale = flash_scale
	if _visual != null:
		_visual.color = color
	_left_sec = duration_sec
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	if _left_sec <= 0.0:
		_hide_flash()
		return
	_left_sec = maxf(0.0, _left_sec - delta)
	if _visual != null:
		_visual.modulate.a = clampf(_left_sec / 0.05, 0.0, 1.0)
	if _left_sec <= 0.0:
		_hide_flash()

func _hide_flash() -> void:
	visible = false
	_left_sec = 0.0
	if _visual != null:
		_visual.modulate.a = 1.0
	set_process(false)
