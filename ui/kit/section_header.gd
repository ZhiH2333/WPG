extends Label
class_name SectionHeader

func _ready() -> void:
	theme_type_variation = &"Section"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
