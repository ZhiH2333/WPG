extends Resource
class_name ArenaDef

## 竞技场底值。只有碰撞布局和地板色。禁止 skeleton_scene、敌人列表、BGM 路径。
@export var id: StringName
@export var display_name: String = ""
@export var layout_scene: PackedScene
@export var tile_color: Color = Color(0.17, 0.19, 0.23, 1)
@export var grout_color: Color = Color(0.10, 0.11, 0.13, 1)
