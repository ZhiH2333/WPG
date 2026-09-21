extends CompanionBase
class_name RangedCompanion

## 远程跟班。库存四把枪走玩家弹池，fire_at 不踢镜头。池满这一发打不出。
const FIRE_MIN_PX: float = 90.0
const FIRE_MAX_PX: float = 460.0
const WEAPON_COUNT: int = 4

var _weapons: Array[Weapon] = []
var _weapon_index: int = 0
var _pool: ProjectilePool

@onready var _muzzle: Marker2D = $Visual/Muzzle

func _ready() -> void:
	super._ready()
	_build_weapons()

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool
	for weapon: Weapon in _weapons:
		weapon.bind_projectile_pool(pool)

func apply_weapon(index: int) -> void:
	var clamped: int = index
	if clamped < 0 or clamped >= WEAPON_COUNT:
		clamped = 0
	_weapon_index = clamped

func get_weapon_index() -> int:
	return _weapon_index

func get_weapon_display_name() -> String:
	var weapon: Weapon = _current_weapon()
	if weapon == null:
		return "-"
	return weapon.get_display_name()

func _apply_flip(flip_h: bool) -> void:
	super._apply_flip(flip_h)
	if _muzzle == null:
		return
	_muzzle.position.x = absf(_muzzle.position.x) * (-1.0 if flip_h else 1.0)

func _tick_attack(target: EnemyBase, delta: float) -> void:
	var weapon: Weapon = _current_weapon()
	if weapon == null:
		return
	var fired: bool = false
	if _ai_state == AiState.ENGAGE and target != null:
		fired = _try_weapon_fire(weapon, target)
	if not fired:
		weapon._tick_idle(delta)

func _try_weapon_fire(weapon: Weapon, target: EnemyBase) -> bool:
	if _defeated:
		return false
	var origin: Vector2 = _muzzle_origin()
	if not _can_fire_at(origin, target):
		return false
	var aim: Vector2 = target.global_position - origin
	if aim.is_zero_approx():
		aim = Vector2.RIGHT
	else:
		aim = aim.normalized()
	return weapon.fire_at(origin, aim)

func _can_fire_at(origin: Vector2, target: EnemyBase) -> bool:
	var distance: float = origin.distance_to(target.global_position)
	if distance < FIRE_MIN_PX or distance > FIRE_MAX_PX:
		return false
	if not LOS_CHECK:
		return true
	return not _is_wall_blocking(origin, target.global_position)

func _is_wall_blocking(from: Vector2, to: Vector2) -> bool:
	var world: World2D = get_world_2d()
	if world == null:
		return false
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		from,
		to,
		GameCollisionLayers.MASK_WALL,
		[get_rid()]
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not world.direct_space_state.intersect_ray(query).is_empty()

func _muzzle_origin() -> Vector2:
	if _muzzle == null:
		return global_position
	return _muzzle.global_position

func _current_weapon() -> Weapon:
	if _weapon_index < 0 or _weapon_index >= _weapons.size():
		return null
	return _weapons[_weapon_index]

func _build_weapons() -> void:
	_weapons = [Pistol.new(), Shotgun.new(), Rifle.new(), Smg.new()]
	for weapon: Weapon in _weapons:
		add_child(weapon)
		if _pool != null:
			weapon.bind_projectile_pool(_pool)
		weapon.set_active(false)
