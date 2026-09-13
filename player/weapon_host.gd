extends Node
class_name WeaponHost

## 切枪不进输入合同三量；只读 1/2/3/4 或当前手柄十字键，转发给当前武器。
var _weapons: Array[Weapon] = []
var _current_index: int = 0
var _switch_locked: bool = false
var _switch_suppressed: bool = false
var _player_input: PlayerInput
var _weapon_visual: PlayerWeaponVisual

func _ready() -> void:
	_weapon_visual = get_node_or_null("../Visual/Guns") as PlayerWeaponVisual
	_collect_weapons()
	_activate_index(0)

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input
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

func get_shotgun() -> Shotgun:
	for weapon: Weapon in _weapons:
		var shotgun: Shotgun = weapon as Shotgun
		if shotgun != null:
			return shotgun
	return null

func get_rifle() -> Rifle:
	for weapon: Weapon in _weapons:
		var rifle: Rifle = weapon as Rifle
		if rifle != null:
			return rifle
	return null

func get_smg() -> Smg:
	for weapon: Weapon in _weapons:
		var smg: Smg = weapon as Smg
		if smg != null:
			return smg
	return null

func get_weapons() -> Array[Weapon]:
	return _weapons.duplicate()

func set_switch_suppressed(suppressed: bool) -> void:
	_switch_suppressed = suppressed

func deactivate_all() -> void:
	_switch_locked = true
	for weapon: Weapon in _weapons:
		weapon.set_active(false)
	if _weapon_visual != null:
		_weapon_visual.hide_all()

func reset_after_player_revive() -> void:
	_switch_locked = false
	for i: int in _weapons.size():
		_weapons[i].set_active(i == _current_index)
	if _weapon_visual != null:
		_weapon_visual.refresh()

func _process(_delta: float) -> void:
	_poll_weapon_switch()

func _poll_weapon_switch() -> void:
	if _switch_locked:
		return
	if _switch_suppressed:
		return
	if Input.is_action_just_pressed("weapon_pistol"):
		_activate_index(0)
		return
	if Input.is_action_just_pressed("weapon_shotgun"):
		_activate_index(1)
		return
	if Input.is_action_just_pressed("weapon_rifle"):
		_activate_index(2)
		return
	if Input.is_action_just_pressed("weapon_smg"):
		_activate_index(3)
		return
	if _player_input == null:
		return
	var slot: int = _player_input.get_weapon_slot_just_pressed()
	if slot >= 0:
		_activate_index(slot)

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
	if _weapon_visual != null:
		_weapon_visual.refresh()
