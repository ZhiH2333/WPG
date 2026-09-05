extends Node
class_name WeaponHost

## 切枪不进输入合同三量；只读 1/2/3，转发给当前武器。
var _weapons: Array[Weapon] = []
var _current_index: int = 0
var _switch_locked: bool = false

func _ready() -> void:
	_collect_weapons()
	_activate_index(0)

func bind_player_input(player_input: PlayerInput) -> void:
	for weapon: Weapon in _weapons:
		weapon.bind_player_input(player_input)

func bind_projectile_pool(pool: ProjectilePool) -> void:
	for weapon: Weapon in _weapons:
		weapon.bind_projectile_pool(pool)

func get_current_weapon() -> Weapon:
	if _weapons.is_empty():
		return null
	return _weapons[_current_index]

func get_pistol() -> Pistol:
	for weapon: Weapon in _weapons:
		var pistol: Pistol = weapon as Pistol
		if pistol != null:
			return pistol
	return null

func deactivate_all() -> void:
	_switch_locked = true
	for weapon: Weapon in _weapons:
		weapon.set_active(false)

func reset_after_player_revive() -> void:
	_switch_locked = false
	for i: int in _weapons.size():
		_weapons[i].set_active(i == _current_index)

func _process(_delta: float) -> void:
	_poll_weapon_switch()

func _poll_weapon_switch() -> void:
	if _switch_locked:
		return
	if Input.is_action_just_pressed("weapon_pistol"):
		_activate_index(0)
		return
	if Input.is_action_just_pressed("weapon_shotgun"):
		_activate_index(1)
		return
	if Input.is_action_just_pressed("weapon_rifle"):
		_activate_index(2)

func _collect_weapons() -> void:
	_weapons.clear()
	for child: Node in get_children():
		var weapon: Weapon = child as Weapon
		if weapon != null:
			_weapons.append(weapon)

func _activate_index(index: int) -> void:
	if index < 0 or index >= _weapons.size():
		return
	if index == _current_index and _weapons[index].is_active():
		return
	_current_index = index
	for i: int in _weapons.size():
		_weapons[i].set_active(i == index)
