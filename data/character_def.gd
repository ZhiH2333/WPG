extends Resource
class_name CharacterDef

## 角色底值。不是效果，不是枪，不是 Dash。禁止 skeleton_scene。
@export var id: StringName
@export var display_name: String = ""
@export var description: String = ""
@export var base_max_hp: int = 100
@export var base_move_speed: float = 420.0
@export var base_acceleration: float = 2400.0
@export var base_deceleration: float = 3200.0
@export var base_friction: float = 1800.0
@export var base_turn_angle_degrees: float = 90.0
@export var base_i_frame_sec: float = 0.45
@export var hurtbox_radius: float = 20.0
@export var body_scale: Vector2 = Vector2(0.065, 0.065)
@export var body_texture: Texture2D
