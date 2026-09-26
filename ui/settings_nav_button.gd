extends Button
class_name SettingsNavButton

## 设置目录项：左侧圆角方条指示器 + 图标 + 粗体标题。
const FADE_SEC: float = 0.5
const INDICATOR_ACTIVE: float = 22.0
const INDICATOR_INACTIVE: float = 4.0
const HOVER_ALPHA: float = 0.08
const MENU_TYPE := preload("res://ui/menu_type.gd")
const COLOR_SELECTED := Color(0.18, 0.14, 0.11, 1)
const COLOR_HOVER := Color(0.18, 0.14, 0.11, 1)
const COLOR_IDLE := Color(0.42, 0.37, 0.32, 1)

@export var tab_icon: Texture2D
@export var caption: String = "Audio"

var selected: bool = false:
	set(value):
		if selected == value:
			return
		selected = value
		if is_node_ready():
			_apply_state(false)

var _state_tween: Tween

@onready var _indicator: Control = $Indicator
@onready var _hover: ColorRect = $Hover
@onready var _icon: TextureRect = $Row/Icon
@onready var _caption: Label = $Row/Caption

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	if tab_icon != null:
		_icon.texture = tab_icon
	_caption.text = caption.to_upper()
	MENU_TYPE.apply_label(_caption, &"navigation", true)
	_caption.add_theme_color_override("font_color", Color.WHITE)
	var bone: StyleBoxFlat = StyleBoxFlat.new()
	bone.bg_color = MENU_TYPE.INK
	bone.set_corner_radius_all(0)
	_indicator.add_theme_stylebox_override("panel", bone)
	mouse_entered.connect(_on_hover_changed)
	mouse_exited.connect(_on_hover_changed)
	_apply_state(true)

func _on_hover_changed() -> void:
	_apply_state(false)

func _apply_state(instant: bool) -> void:
	var indicator_h: float = INDICATOR_ACTIVE if selected else INDICATOR_INACTIVE
	var indicator_a: float = 1.0 if selected else 0.0
	var hover_a: float = 0.0
	var text_color: Color = COLOR_SELECTED if selected else (COLOR_HOVER if is_hovered() else COLOR_IDLE)
	if instant:
		_indicator.offset_top = -indicator_h * 0.5
		_indicator.offset_bottom = indicator_h * 0.5
		_indicator.modulate.a = indicator_a
		_set_hover_alpha(hover_a)
		_icon.modulate = text_color
		_caption.modulate = text_color
		return
	UiAnim.kill_tween(_state_tween)
	_state_tween = create_tween().set_parallel(true)
	var indicator_trans: int = Tween.TRANS_BACK if selected else Tween.TRANS_QUINT
	_state_tween.tween_property(_indicator, "offset_top", -indicator_h * 0.5, FADE_SEC).set_trans(indicator_trans).set_ease(Tween.EASE_OUT)
	_state_tween.tween_property(_indicator, "offset_bottom", indicator_h * 0.5, FADE_SEC).set_trans(indicator_trans).set_ease(Tween.EASE_OUT)
	_state_tween.tween_property(_indicator, "modulate:a", indicator_a, FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_state_tween.tween_property(_hover, "color:a", hover_a, FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_state_tween.tween_property(_icon, "modulate", text_color, FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_state_tween.tween_property(_caption, "modulate", text_color, FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _set_hover_alpha(alpha: float) -> void:
	var c: Color = _hover.color
	c.a = alpha
	_hover.color = c
