extends CanvasLayer
class_name DebugOverlay

var _player: Player
var _player_input: PlayerInput
var _player_camera: PlayerCamera
var _weapon_host: WeaponHost
var _pool: ProjectilePool
var _dummies: Array[DummyTarget] = []

@onready var _label: Label = $Label

func bind_player(player: Player) -> void:
	_player = player
	bind_player_input(player.get_player_input())

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func bind_player_camera(player_camera: PlayerCamera) -> void:
	_player_camera = player_camera

func bind_weapon_host(weapon_host: WeaponHost) -> void:
	_weapon_host = weapon_host

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool

func bind_dummies(dummies: Array[DummyTarget]) -> void:
	_dummies = dummies

func _process(_delta: float) -> void:
	_refresh_label()

func _refresh_label() -> void:
	if _player_input == null:
		_label.text = "PlayerInput 未绑定"
		return
	_label.text = _compose_status_text()

func _compose_status_text() -> String:
	var fps: int = Engine.get_frames_per_second()
	var velocity: Vector2 = _read_velocity()
	var weapon: Weapon = _read_weapon()
	return "weapon: %s\nmove_vector: %s\naim_vector: %s\nfire_held: %s\nfire_cd: %.3f\nspread_deg: %.2f\npellets: %d\nmouse_world: %s\nvelocity: %s\nspeed: %.1f\nlook_target: %s\ncamera_offset: %s\ncamera_pos: %s\nactive_bullets: %d\npool_free: %d\nlast_shot_refused: %d\ndummy_hp: %s\nFPS: %d" % [
		_read_weapon_name(weapon),
		_format_vector(_player_input.move_vector),
		_format_vector(_player_input.aim_vector),
		_player_input.fire_held,
		_read_fire_cooldown(weapon),
		_read_spread(weapon),
		_read_pellets(weapon),
		_format_vector(_player_input.mouse_world_position),
		_format_vector(velocity),
		velocity.length(),
		_format_vector(_read_look_target()),
		_format_vector(_read_camera_offset()),
		_format_vector(_read_camera_position()),
		_read_active_bullets(),
		_read_pool_free(),
		_read_refused(weapon),
		_format_dummy_hp(),
		fps,
	]

func _read_weapon() -> Weapon:
	if _weapon_host == null:
		return null
	return _weapon_host.get_current_weapon()

func _read_weapon_name(weapon: Weapon) -> String:
	if weapon == null:
		return "-"
	return weapon.get_display_name()

func _read_velocity() -> Vector2:
	if _player == null:
		return Vector2.ZERO
	return _player.velocity

func _read_look_target() -> Vector2:
	if _player_camera == null:
		return Vector2.ZERO
	return _player_camera.get_look_target()

func _read_camera_offset() -> Vector2:
	if _player_camera == null:
		return Vector2.ZERO
	return _player_camera.get_camera_offset()

func _read_camera_position() -> Vector2:
	if _player_camera == null:
		return Vector2.ZERO
	return _player_camera.global_position

func _read_fire_cooldown(weapon: Weapon) -> float:
	if weapon == null:
		return 0.0
	return weapon.get_cooldown_remaining_sec()

func _read_spread(weapon: Weapon) -> float:
	if weapon == null:
		return 0.0
	return weapon.get_current_spread_deg()

func _read_pellets(weapon: Weapon) -> int:
	if weapon == null:
		return 0
	return weapon.get_pellets_per_shot()

func _read_active_bullets() -> int:
	if _pool == null:
		return 0
	return _pool.get_active_count()

func _read_pool_free() -> int:
	if _pool == null:
		return 0
	return _pool.get_free_count()

func _read_refused(weapon: Weapon) -> int:
	if weapon == null:
		return 0
	return weapon.get_refused_count()

func _format_dummy_hp() -> String:
	if _dummies.is_empty():
		return "-"
	var parts: PackedStringArray = PackedStringArray()
	for dummy: DummyTarget in _dummies:
		parts.append(str(dummy.get_hp()))
	return ", ".join(parts)

func _format_vector(value: Vector2) -> String:
	return "(%.2f, %.2f)" % [value.x, value.y]
