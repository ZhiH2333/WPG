extends Node2D
class_name AimReticle

## 世界准星。统一接口：桌面钉鼠标世界坐标；Touch 用 player + direction * 固定距离。
## Touch 距离是游戏常量，不来自手指位移；松手（AimPad inactive）时准星回到玩家中心。
## 桌面（鼠标/手柄）当帧直接钉住目标，不做任何平滑：平滑会让准星落后鼠标，手感发黏。
## 只有 Touch 走指数平滑（非线性、帧率无关），避免 140px 目标跳变造成准星瞬移；到位后吸附消除漂移。
const TOUCH_AIM_DISTANCE: float = 140.0
## 仅 Touch 生效。越大越跟手。alpha = 1 - exp(-follow_speed * delta)，保证不同帧率手感一致。
@export var follow_speed: float = 18.0
## 仅 Touch 生效。距目标小于该像素即吸附，避免无限逼近造成的亚像素抖动。
@export var snap_distance: float = 0.75

var _player_input: PlayerInput
var _has_position: bool = false

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input
	_has_position = false
	_follow(0.0)

func _process(delta: float) -> void:
	_follow(delta)

func _follow(delta: float) -> void:
	if _player_input == null:
		return
	if not _player_input.is_touch_active():
		## 桌面：与旧版一致，当帧钉住鼠标世界坐标，不平滑。
		global_position = _player_input.mouse_world_position
		_has_position = true
		return
	var target: Vector2 = _get_touch_target_position()
	if not _has_position or delta <= 0.0:
		global_position = target
		_has_position = true
		return
	var alpha: float = 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(target, alpha)
	if global_position.distance_to(target) <= snap_distance:
		global_position = target

func _get_touch_target_position() -> Vector2:
	var host: Node2D = _player_input.get_parent() as Node2D
	if host == null:
		return global_position
	## Touch Aim inactive -> aim ZERO -> 准星回到玩家中心。
	return host.global_position + _player_input.aim_vector * TOUCH_AIM_DISTANCE
