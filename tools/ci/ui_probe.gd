extends SceneTree

const GALLERY := preload("res://tools/ui_gallery.gd")

func _initialize() -> void:
	var theme: Theme = load("res://ui/game_theme.tres") as Theme
	if theme == null:
		push_error("ui probe: theme failed to load")
		quit(1)
		return
	var playpen: Font = theme.get_font(&"font", &"Display")
	var sans: Font = theme.get_font(&"font", &"Body")
	if playpen == null or sans == null:
		push_error("ui probe: font roles missing")
		quit(1)
		return
	var gallery = GALLERY.new()
	root.add_child(gallery)
	var failures: PackedStringArray = gallery.run_probe()
	if not failures.is_empty():
		for line: String in failures:
			push_error(line)
		quit(1)
		return
	print("UI_PROBE_OK")
	quit(0)
