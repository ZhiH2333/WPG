extends Label
class_name PageHeader

func _ready() -> void:
	theme_type_variation = &"Page"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
