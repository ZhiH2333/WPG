extends Button
class_name HoldConfirmButton

## 长按确认按钮。松手立刻回零，满格只发一次 confirmed。
signal confirmed

@export var hold_duration_sec: float = 1.5

var _held_sec: float = 0.0
var _holding: bool = false

@onready var _fill: ColorRect = $Fill

func _ready() -> void:
	mouse_exited.connect(_reset_hold)
	focus_exited.connect(_reset_hold)

func _gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT:
		_set_holding(mouse.pressed)
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		_set_holding(touch.pressed)

func _process(delta: float) -> void:
	if not _holding:
		return
	_held_sec += delta
	_fill.anchor_right = clampf(_held_sec / hold_duration_sec, 0.0, 1.0)
	_fill.offset_right = 0.0
	if _held_sec < hold_duration_sec:
		return
	confirmed.emit()
	_holding = false
	_held_sec = 0.0
	_fill.anchor_right = 0.0
	_fill.offset_right = 0.0

func _set_holding(pressed: bool) -> void:
	if pressed:
		_holding = true
		return
	_reset_hold()

func _reset_hold() -> void:
	_holding = false
	_held_sec = 0.0
	_fill.anchor_right = 0.0
	_fill.offset_right = 0.0
