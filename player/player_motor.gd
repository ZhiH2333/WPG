extends Node
class_name PlayerMotor

## 最高移速，像素/秒。desired = move_vector * move_speed，不再二次归一化。
@export var move_speed: float = 420.0
## 有输入且大致同向时，速度靠近目标的加速度，像素/秒²。
@export var acceleration: float = 2400.0
## 转向或反向时先刹车的减速度，像素/秒²。
@export var deceleration: float = 3200.0
## 无输入时滑行摩擦，像素/秒²。
@export var friction: float = 1800.0
## 当前速度与目标速度夹角超过此值时改用 deceleration。
@export var turn_angle_degrees: float = 90.0

## 纯速度积分，不调用 move_and_slide。current_velocity 必须是撞墙滑动后的真实速度。
func tick(delta: float, current_velocity: Vector2, move_vector: Vector2) -> Vector2:
	if move_vector.is_zero_approx():
		return current_velocity.move_toward(Vector2.ZERO, friction * delta)
	return _approach_desired(delta, current_velocity, move_vector * move_speed)

func _approach_desired(delta: float, current_velocity: Vector2, desired_velocity: Vector2) -> Vector2:
	var rate: float = _pick_approach_rate(current_velocity, desired_velocity)
	return current_velocity.move_toward(desired_velocity, rate * delta)

func _pick_approach_rate(current_velocity: Vector2, desired_velocity: Vector2) -> float:
	if current_velocity.is_zero_approx():
		return acceleration
	if abs(current_velocity.angle_to(desired_velocity)) > deg_to_rad(turn_angle_degrees):
		return deceleration
	return acceleration
