extends Node2D
class_name PlayerWeaponVisual

## 挂在 Visual/Guns 上。只显示当前武器的 Sprite，把 Muzzle 挪到它的枪口。不读 Input，只问 WeaponHost。

@onready var _pistol_sprite: Sprite2D = $PistolSprite
@onready var _shotgun_sprite: Sprite2D = $ShotgunSprite
@onready var _rifle_sprite: Sprite2D = $RifleSprite
@onready var _smg_sprite: Sprite2D = $SmgSprite
@onready var _muzzle: Marker2D = get_node("Muzzle") as Marker2D
@onready var _weapon_host: WeaponHost = get_parent().get_parent().get_node("WeaponHost") as WeaponHost

func refresh() -> void:
	hide_all()
	if _weapon_host == null:
		return
	var weapon: Weapon = _weapon_host.get_current_weapon()
	if weapon == null:
		return
	var sprite: Sprite2D = _sprite_for_weapon(weapon)
	if sprite != null:
		sprite.visible = true
	if _muzzle != null:
		_muzzle.position = weapon.get_muzzle_local_offset()

func hide_all() -> void:
	_pistol_sprite.visible = false
	_shotgun_sprite.visible = false
	_rifle_sprite.visible = false
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
