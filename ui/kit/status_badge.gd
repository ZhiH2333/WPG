extends Label
class_name StatusBadge

func _ready() -> void:
	theme_type_variation = &"Section"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_status(kind: StringName) -> void:
	match kind:
		&"success", &"ready", &"connected":
			theme_type_variation = &"StatusSuccess"
		&"warning", &"connecting", &"authenticating":
			theme_type_variation = &"StatusWarning"
		&"error", &"failed", &"host_closed", &"version_mismatch":
			theme_type_variation = &"StatusError"
		_:
			theme_type_variation = &"Caption"
