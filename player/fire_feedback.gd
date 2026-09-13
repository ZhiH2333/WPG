extends Node
class_name FireFeedback

## 开火视觉/听觉转发：枪口闪光、枪身短后坐、镜头踢、枪声。不写进 Player 上帝对象。
const RECOVER_SEC: float = 0.1
const HURT_KICK: float = 6.0

var _camera: PlayerCamera
var _sfx_pool: SfxPool
var _recoil_from: Vector2 = Vector2.ZERO
var _recoil_left_sec: float = 0.0

@onready var _player: Player = get_parent() as Player
@onready var _visual: Node2D = get_parent().get_node("Visual") as Node2D
@onready var _muzzle: Marker2D = get_parent().get_node("Visual/Guns/Muzzle") as Marker2D
@onready var _muzzle_flash: MuzzleFlash = get_parent().get_node("Visual/Guns/Muzzle/MuzzleFlash") as MuzzleFlash

func bind_camera(player_camera: PlayerCamera) -> void:
	_camera = player_camera

func bind_sfx_pool(sfx_pool: SfxPool) -> void:
	_sfx_pool = sfx_pool

func play_shot(aim: Vector2, weapon: Weapon) -> void:
	var direction: Vector2 = _normalize_or_right(aim)
	_muzzle_flash.play(
		weapon.get_muzzle_flash_scale(),
		weapon.get_muzzle_flash_duration_sec(),
		weapon.get_muzzle_flash_color()
	)
	_start_recoil(-direction * weapon.get_recoil_pixels())
	if _camera != null:
		_camera.apply_kick(-direction, weapon.get_camera_kick_amplitude())
	if _sfx_pool != null:
		_sfx_pool.play_weapon(weapon, _muzzle.global_position)

func play_refuse() -> void:
	if _sfx_pool == null:
		return
	_sfx_pool.play_click(_muzzle.global_position)

func play_hurt(hit_direction: Vector2) -> void:
	var direction: Vector2 = _normalize_or_right(hit_direction)
	if _camera != null:
		_camera.apply_kick(direction, HURT_KICK)
	if _sfx_pool != null:
		_sfx_pool.play_hurt(_player.global_position)

func stop_recoil() -> void:
	_recoil_left_sec = 0.0
	_recoil_from = Vector2.ZERO
	if _visual != null:
		_visual.position = Vector2.ZERO
	if _muzzle_flash != null:
		_muzzle_flash.visible = false

func _process(delta: float) -> void:
	_tick_recoil(delta)

func _tick_recoil(delta: float) -> void:
	if _visual == null or _recoil_left_sec <= 0.0:
		return
	_recoil_left_sec = maxf(0.0, _recoil_left_sec - delta)
	var alpha: float = 1.0 - (_recoil_left_sec / RECOVER_SEC)
	_visual.position = _recoil_from.lerp(Vector2.ZERO, alpha)
	if _recoil_left_sec <= 0.0:
		_visual.position = Vector2.ZERO

func _start_recoil(offset: Vector2) -> void:
	_recoil_from = offset
	_recoil_left_sec = RECOVER_SEC
	if _visual != null:
		_visual.position = offset

func _normalize_or_right(direction: Vector2) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.RIGHT
	return direction.normalized()
