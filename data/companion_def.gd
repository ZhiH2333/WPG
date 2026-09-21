extends Resource
class_name CompanionDef

## 跟班底值。不是效果，不是主动技能。禁止 skeleton_scene。
enum Kind {
	MELEE,
	RANGED,
}

@export var id: StringName
@export var display_name: String = ""
@export var description: String = ""
@export var kind: Kind = Kind.MELEE
@export var shop_cost: int = 0
@export var base_max_hp: int = 32
@export var base_move_speed: float = 260.0
@export var base_acceleration: float = 1600.0
@export var hurtbox_radius: float = 12.0
@export var body_scale: Vector2 = Vector2(0.042, 0.042)
@export var body_texture: Texture2D
@export var body_modulate: Color = Color(0.45, 0.85, 1, 1)
@export var follow_distance: float = 56.0
@export var aggro_range: float = 280.0
@export var contact_damage: int = 0
@export var fire_interval: float = 0.0
@export var projectile_speed: float = 0.0
@export var projectile_damage: int = 0
@export var i_frame_sec: float = 0.25
