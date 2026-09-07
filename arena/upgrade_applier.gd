extends Node
class_name UpgradeApplier

## 从底值重算 owned 合计。禁止在当前值上累加，禁止 UpgradeDef 自己改枪。
const MIN_MAX_HP: int = 1
const MIN_PELLETS: int = 1
const MAX_PELLETS: int = 14
const MIN_FIRE_INTERVAL: float = 0.02
const MIN_MOVE_SPEED: float = 80.0
const MIN_I_FRAME_SEC: float = 0.05

var _player: Player
var _session: RunSession
var _captured: bool = false
var _base_max_hp: int = 0
var _base_i_frame_sec: float = 0.0
var _base_move_speed: float = 0.0
var _base_knockback_impulse: float = 0.0
var _base_weapon_damage: PackedInt32Array = PackedInt32Array()
var _base_weapon_fire_interval: PackedFloat32Array = PackedFloat32Array()
var _base_weapon_projectile_speed: PackedFloat32Array = PackedFloat32Array()
var _base_shotgun_pellets: int = 0
var _base_rifle_max_spread: float = 0.0

func bind_player(player: Player) -> void:
	_player = player

func bind_session(session: RunSession) -> void:
	_session = session

func capture_baseline() -> void:
	if _player == null:
		return
	var health: PlayerHealth = _player.get_player_health()
	_base_max_hp = health.max_hp
	_base_i_frame_sec = health.i_frame_sec
	_base_move_speed = _player.get_player_motor().move_speed
	_base_knockback_impulse = _player.knockback_impulse
	_base_weapon_damage = PackedInt32Array()
	_base_weapon_fire_interval = PackedFloat32Array()
	_base_weapon_projectile_speed = PackedFloat32Array()
	var host: WeaponHost = _player.get_weapon_host()
	for weapon: Weapon in host.get_weapons():
		_base_weapon_damage.append(weapon.damage)
		_base_weapon_fire_interval.append(weapon.fire_interval)
		_base_weapon_projectile_speed.append(weapon.projectile_speed)
	var shotgun: Shotgun = host.get_shotgun()
	if shotgun != null:
		_base_shotgun_pellets = shotgun.pellet_count
	var rifle: Rifle = host.get_rifle()
	if rifle != null:
		_base_rifle_max_spread = rifle.max_spread_deg
	_captured = true

func apply_owned() -> void:
	if _player == null or not _captured:
		return
	var totals: Dictionary = _empty_totals()
	_accumulate_owned(totals)
	_write_runtime(totals)

func _empty_totals() -> Dictionary:
	return {
		"max_hp_flat": 0,
		"move_speed_pct": 0.0,
		"damage_flat": 0,
		"fire_rate_pct": 0.0,
		"projectile_speed_flat": 0.0,
		"i_frame_flat": 0.0,
		"shotgun_pellets_flat": 0,
		"rifle_max_spread_flat": 0.0,
		"knockback_taken_pct": 0.0,
	}

func _accumulate_owned(totals: Dictionary) -> void:
	if _session == null:
		return
	var catalog: UpgradeCatalog = _session.get_catalog()
	if catalog == null:
		return
	for upgrade_id: String in _session.get_owned_upgrade_ids():
		var def: UpgradeDef = catalog.get_by_id(StringName(upgrade_id))
		if def == null:
			continue
		_add_def(def, totals)

func _add_def(def: UpgradeDef, totals: Dictionary) -> void:
	match def.kind:
		UpgradeDef.Kind.MAX_HP_FLAT:
			totals["max_hp_flat"] = int(totals["max_hp_flat"]) + int(round(def.value))
		UpgradeDef.Kind.MOVE_SPEED_PCT:
			totals["move_speed_pct"] = float(totals["move_speed_pct"]) + def.value
		UpgradeDef.Kind.DAMAGE_FLAT:
			totals["damage_flat"] = int(totals["damage_flat"]) + int(round(def.value))
		UpgradeDef.Kind.FIRE_RATE_PCT:
			totals["fire_rate_pct"] = float(totals["fire_rate_pct"]) + def.value
		UpgradeDef.Kind.PROJECTILE_SPEED_FLAT:
			totals["projectile_speed_flat"] = float(totals["projectile_speed_flat"]) + def.value
		UpgradeDef.Kind.I_FRAME_FLAT:
			totals["i_frame_flat"] = float(totals["i_frame_flat"]) + def.value
		UpgradeDef.Kind.SHOTGUN_PELLETS_FLAT:
			totals["shotgun_pellets_flat"] = int(totals["shotgun_pellets_flat"]) + int(round(def.value))
		UpgradeDef.Kind.RIFLE_MAX_SPREAD_FLAT:
			totals["rifle_max_spread_flat"] = float(totals["rifle_max_spread_flat"]) + def.value
		UpgradeDef.Kind.KNOCKBACK_TAKEN_PCT:
			totals["knockback_taken_pct"] = float(totals["knockback_taken_pct"]) + def.value

func _write_runtime(totals: Dictionary) -> void:
	var health: PlayerHealth = _player.get_player_health()
	health.apply_max_hp(maxi(MIN_MAX_HP, _base_max_hp + int(totals["max_hp_flat"])))
	health.i_frame_sec = maxf(MIN_I_FRAME_SEC, _base_i_frame_sec + float(totals["i_frame_flat"]))
	_player.get_player_motor().move_speed = maxf(MIN_MOVE_SPEED, _base_move_speed * (1.0 + float(totals["move_speed_pct"])))
	_player.knockback_impulse = _base_knockback_impulse * (1.0 + float(totals["knockback_taken_pct"]))
	var fire_denom: float = 1.0 + float(totals["fire_rate_pct"])
	if fire_denom <= 0.0:
		fire_denom = 0.0001
	var host: WeaponHost = _player.get_weapon_host()
	var weapons: Array[Weapon] = host.get_weapons()
	for i: int in weapons.size():
		var weapon: Weapon = weapons[i]
		weapon.damage = _base_weapon_damage[i] + int(totals["damage_flat"])
		weapon.fire_interval = maxf(MIN_FIRE_INTERVAL, _base_weapon_fire_interval[i] / fire_denom)
		weapon.projectile_speed = _base_weapon_projectile_speed[i] + float(totals["projectile_speed_flat"])
	var shotgun: Shotgun = host.get_shotgun()
	if shotgun != null:
		shotgun.pellet_count = clampi(_base_shotgun_pellets + int(totals["shotgun_pellets_flat"]), MIN_PELLETS, MAX_PELLETS)
	var rifle: Rifle = host.get_rifle()
	if rifle == null:
		return
	rifle.max_spread_deg = maxf(rifle.min_spread_deg, _base_rifle_max_spread + float(totals["rifle_max_spread_flat"]))
	rifle.clamp_current_spread_to_max()
