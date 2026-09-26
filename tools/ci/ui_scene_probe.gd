extends SceneTree

const SCENES: PackedStringArray = [
	"res://ui/main_menu.tscn",
	"res://ui/play_page.tscn",
	"res://ui/profile_overlay.tscn",
	"res://ui/settings_overlay.tscn",
	"res://ui/record_selector.tscn",
	"res://ui/record_leaderboard_overlay.tscn",
	"res://ui/lan_overlay.tscn",
	"res://ui/credits_overlay.tscn",
	"res://ui/pause_overlay.tscn",
	"res://ui/winner_page.tscn",
	"res://ui/loading_screen.tscn",
	"res://ui/hud.tscn",
	"res://ui/shop_offer.tscn",
	"res://ui/upgrade_offer.tscn",
	"res://ui/room_notice.tscn",
	"res://sandbox/combat_sandbox.tscn",
]

func _initialize() -> void:
	for path: String in SCENES:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			push_error("scene probe failed to load %s" % path)
			quit(1)
			return
		var node: Node = packed.instantiate()
		if node == null:
			push_error("scene probe failed to instance %s" % path)
			quit(1)
			return
		root.add_child(node)
		node.queue_free()
	print("SCENE_PROBE_OK")
	quit(0)
