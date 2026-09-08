extends Node

## 手柄调试工具：运行 combat_sandbox 后按 G 切换显示。
var _enabled: bool = false
var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(400, 20)
	add_child(_label)
	_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and key.keycode == KEY_G:
			_enabled = not _enabled
			_label.visible = _enabled
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not _enabled:
		return
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		_label.text = "没有连接手柄"
		return
	var id: int = pads[0]
	var left_x: float = Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
	var left_y: float = Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
	var right_x: float = Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
	var right_y: float = Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)
	var trigger_r: float = (Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) + 1.0) * 0.5
	var rb: bool = Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)
	var dpad_l: bool = Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT)
	var dpad_u: bool = Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP)
	var dpad_r: bool = Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT)
	var dpad_d: bool = Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN)
	_label.text = """手柄 %d（按 G 隐藏）
左摇杆: (%.2f, %.2f) len=%.2f
右摇杆: (%.2f, %.2f) len=%.2f
右扳机: %.2f  RB: %s
十字键: L=%s U=%s R=%s D=%s
死区阈值 0.25，扳机阈值 0.45""" % [
		id,
		left_x, left_y, Vector2(left_x, left_y).length(),
		right_x, right_y, Vector2(right_x, right_y).length(),
		trigger_r, rb,
		dpad_l, dpad_u, dpad_r, dpad_d,
	]
