extends StaticBody2D
class_name ArenaBlock

## 场内墙柱。视觉抄外墙三块 Polygon2D。_ready 按 block_size 重建，不每帧 queue_redraw。
const EDGE_PX: float = 6.0
const VISUAL_COLOR := Color(0.11, 0.12, 0.15, 1)
const SHADOW_COLOR := Color(0.06, 0.07, 0.09, 1)
const HIGHLIGHT_COLOR := Color(0.22, 0.24, 0.28, 1)

@export var block_size: Vector2 = Vector2(96, 96)

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _visual: Polygon2D = $Visual
@onready var _edge_shadow: Polygon2D = $EdgeShadow
@onready var _edge_highlight: Polygon2D = $EdgeHighlight

func _ready() -> void:
	collision_layer = GameCollisionLayers.MASK_WALL
	collision_mask = GameCollisionLayers.MASK_NONE
	_rebuild_block()

func _rebuild_block() -> void:
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = block_size
	_collision.shape = rect
	var half: Vector2 = block_size * 0.5
	var hw: float = half.x
	var hh: float = half.y
	var edge: float = EDGE_PX
	_visual.color = VISUAL_COLOR
	_visual.polygon = PackedVector2Array([
		Vector2(-hw, -hh),
		Vector2(hw, -hh),
		Vector2(hw, hh),
		Vector2(-hw, hh),
	])
	_edge_shadow.color = SHADOW_COLOR
	_edge_shadow.polygon = PackedVector2Array([
		Vector2(-hw, hh - edge),
		Vector2(hw - edge, hh - edge),
		Vector2(hw - edge, -hh),
		Vector2(hw, -hh),
		Vector2(hw, hh),
		Vector2(-hw, hh),
	])
	_edge_highlight.color = HIGHLIGHT_COLOR
	_edge_highlight.polygon = PackedVector2Array([
		Vector2(-hw, -hh),
		Vector2(hw, -hh),
		Vector2(hw, -hh + edge),
		Vector2(-hw + edge, -hh + edge),
		Vector2(-hw + edge, hh),
		Vector2(-hw, hh),
	])
