extends Node
class_name PlayerInput

## 鼠标与玩家过近时不重新归一化，避免 aim_vector 出现 NaN。
const AIM_DEADZONE_SQ: float = 0.0001

## 全项目唯一输入合同：只产出。Motor / 相机 / 准星只读，不自己读键鼠。
var move_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.RIGHT
var fire_held: bool = false
var mouse_world_position: Vector2 = Vector2.ZERO

func _enter_tree() -> void:
	## 小于 0 更早处理，让同一帧的朝向、相机、准星读到本帧输入。
	process_priority = -100

func _process(_delta: float) -> void:
	update_input()

func update_input() -> void:
	_update_move_vector()
	_update_aim_vector()
	_update_fire_held()

func _update_move_vector() -> void:
	move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _update_aim_vector() -> void:
	var host: Node2D = get_parent() as Node2D
	if host == null:
		return
	mouse_world_position = host.get_global_mouse_position()
	var to_mouse: Vector2 = mouse_world_position - host.global_position
	if to_mouse.length_squared() < AIM_DEADZONE_SQ:
		_keep_last_aim()
		return
	aim_vector = to_mouse.normalized()

func _keep_last_aim() -> void:
	if aim_vector.is_zero_approx():
		aim_vector = Vector2.RIGHT

func _update_fire_held() -> void:
	fire_held = Input.is_action_pressed("fire")
