extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://ui/main_menu.tscn") as PackedScene
	if packed == null:
		push_error("smoke: main scene failed to load")
		quit(1)
		return
	var node: Node = packed.instantiate()
	if node == null:
		push_error("smoke: main scene failed to instantiate")
		quit(1)
		return
	root.add_child(node)
	print("SMOKE_OK")
	quit(0)
