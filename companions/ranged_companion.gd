extends CompanionBase
class_name RangedCompanion

## 远程跟班。库存四把枪走玩家弹池，fire_at 不踢镜头。枪口每帧对准当前目标。
const FIRE_MIN_PX: float = 90.0
const FIRE_MAX_PX: float = 460.0
const WEAPON_COUNT: int = 4

var _weapons: Array[Weapon] = []
var _weapon_index: int = 0
var _pool: ProjectilePool

@onready var _guns: Node2D = $Guns
@onready var _muzzle: Marker2D = $Guns/Muzzle
@onready var _pistol_sprite: Sprite2D = $Guns/PistolSprite
@onready var _shotgun_sprite: Sprite2D = $Guns/ShotgunSprite
@onready var _rifle_sprite: Sprite2D = $Guns/RifleSprite
@onready var _smg_sprite: Sprite2D = $Guns/SmgSprite

func _ready() -> void:
	super._ready()
	_build_weapons()
	_refresh_gun_visual()

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool
	for weapon: Weapon in _weapons:
		weapon.bind_projectile_pool(pool)

func apply_weapon(index: int) -> void:
	var clamped: int = index
	if clamped < 0 or clamped >= WEAPON_COUNT:
		clamped = 0
	_weapon_index = clamped
	_refresh_gun_visual()

func get_weapon_index() -> int:
	return _weapon_index

func get_weapon_display_name() -> String:
	var weapon: Weapon = _current_weapon()
	if weapon == null:
		return "-"
	return weapon.get_display_name()

func _on_defeated() -> void:
	if _guns != null:
		_guns.visible = false

func _tick_attack(target: EnemyBase, delta: float) -> void:
	_aim_gun(target)
	var weapon: Weapon = _current_weapon()
	if weapon == null:
		return
	var fired: bool = false
	if _ai_state == AiState.ENGAGE and target != null:
		fired = _try_weapon_fire(weapon, target)
	if not fired:
		weapon._tick_idle(delta)

func _aim_gun(target: EnemyBase) -> void:
	if _guns == null:
		return
	if _defeated:
		_guns.visible = false
		return
	_guns.visible = true
	var aim: Vector2 = _read_aim_or_left()
	if target != null and is_instance_valid(target) and not target.is_in_reserve() and not target.is_defeated():
		var to_target: Vector2 = target.global_position - _guns.global_position
		if not to_target.is_zero_approx():
			aim = to_target
	_guns.rotation = aim.angle()

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

func _refresh_gun_visual() -> void:
	_hide_gun_sprites()
	var weapon: Weapon = _current_weapon()
	var sprite: Sprite2D = _sprite_for_weapon(weapon)
	if sprite != null:
		sprite.visible = true
	if _muzzle != null and weapon != null:
		_muzzle.position = weapon.get_muzzle_local_offset()

func _hide_gun_sprites() -> void:
	if _pistol_sprite != null:
		_pistol_sprite.visible = false
	if _shotgun_sprite != null:
		_shotgun_sprite.visible = false
	if _rifle_sprite != null:
		_rifle_sprite.visible = false
	if _smg_sprite != null:
		_smg_sprite.visible = false

func _sprite_for_weapon(weapon: Weapon) -> Sprite2D:
	if weapon is Pistol:
		return _pistol_sprite
	if weapon is Shotgun:
		return _shotgun_sprite
	if weapon is Rifle:
		return _rifle_sprite
	if weapon is Smg:
		return _smg_sprite
	return null

func _build_weapons() -> void:
	_weapons = [Pistol.new(), Shotgun.new(), Rifle.new(), Smg.new()]
	for weapon: Weapon in _weapons:
		add_child(weapon)
		if _pool != null:
			weapon.bind_projectile_pool(_pool)
		weapon.set_active(false)
