extends Control
class_name SettingsSection

## 设置长文档里的一节。非当前节压暗且不可点，第一次点击只负责滚过来。
signal selected_requested

const INACTIVE_ALPHA: float = 0.8
const HOVER_ALPHA: float = 0.5
const DIM_SEC: float = 0.3

@export var header_text: String = "Section"
@export var search_name: String = ""

var is_current: bool = false
var _hovered: bool = false
var _dim_tween: Tween

@onready var body: VBoxContainer = $Body
@onready var header: Label = $Body/Header
@onready var dim: ColorRect = $Dim

func _ready() -> void:
	header.text = header_text.to_upper()
	if search_name.is_empty():
		search_name = header_text
	dim.mouse_entered.connect(_on_dim_hover.bind(true))
	dim.mouse_exited.connect(_on_dim_hover.bind(false))
	dim.gui_input.connect(_on_dim_gui_input)
	body.minimum_size_changed.connect(_fit)
	resized.connect(_fit)
	_fit()
	_apply_dim(true)

func set_current(value: bool) -> void:
	if is_current == value:
		return
	is_current = value
	_apply_dim(false)

func _fit() -> void:
	var sep: int = body.get_theme_constant("separation")
	var h: float = 0.0
	var vis: int = 0
	for child: Node in body.get_children():
		var item: Control = child as Control
		if item == null or not item.visible:
			continue
		h += item.get_combined_minimum_size().y
		vis += 1
	if vis > 1:
		h += float(sep * (vis - 1))
	if h < 1.0:
		h = 1.0
	custom_minimum_size.y = h
	body.offset_bottom = h

func _on_dim_hover(hovered: bool) -> void:
	_hovered = hovered
	_apply_dim(false)

func _on_dim_gui_input(event: InputEvent) -> void:
	if is_current:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	selected_requested.emit()

func _apply_dim(instant: bool) -> void:
	var alpha: float = 0.0
	if not is_current:
		alpha = HOVER_ALPHA if _hovered else INACTIVE_ALPHA
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_current else Control.MOUSE_FILTER_STOP
	if instant:
		_set_dim_alpha(alpha)
		return
	UiAnim.kill_tween(_dim_tween)
	_dim_tween = create_tween()
	_dim_tween.tween_property(dim, "color:a", alpha, DIM_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _set_dim_alpha(alpha: float) -> void:
	var c: Color = dim.color
	c.a = alpha
	dim.color = c
