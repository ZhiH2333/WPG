extends HBoxContainer
class_name ValueRow

@export var row_label: String = ""
@export var row_value: String = ""

func _ready() -> void:
	add_theme_constant_override("separation", UiTokens.SPACE_LG)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_child_count() > 0:
		return
	var caption: Label = Label.new()
	caption.theme_type_variation = &"Section"
	caption.text = row_label
	caption.custom_minimum_size = Vector2(120, 0)
	var value: Label = Label.new()
	value.theme_type_variation = &"Numeric"
	value.text = row_value
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(caption)
	add_child(value)
