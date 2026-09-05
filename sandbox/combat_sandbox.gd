extends Node2D
class_name CombatSandbox

@onready var _walls: Node2D = $Walls
@onready var _player: Player = $Player
@onready var _debug_overlay: DebugOverlay = $DebugOverlay

func _ready() -> void:
	_apply_wall_layers()
	_debug_overlay.bind_player_input(_player.get_player_input())

func _apply_wall_layers() -> void:
	for child: Node in _walls.get_children():
		var body: StaticBody2D = child as StaticBody2D
		if body == null:
			continue
		body.collision_layer = GameCollisionLayers.MASK_WALL
		body.collision_mask = GameCollisionLayers.MASK_NONE
