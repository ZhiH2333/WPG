extends Node
class_name UpgradeApplier

## 从底值重算 owned 合计。禁止在当前值上累加，禁止 UpgradeDef 自己改枪。LAN 两人共用同一份 session owned，各自按自己的角色底值重算。
const MIN_MAX_HP: int = 1
const MIN_PELLETS: int = 1
const MAX_PELLETS: int = 14
const MIN_FIRE_INTERVAL: float = 0.02
const MIN_MOVE_SPEED: float = 80.0
const MIN_I_FRAME_SEC: float = 0.05

var _player: Player
var _pawns: Array[Player] = []
var _session: RunSession
var _captured: bool = false
var _pawn_bases: Array[Dictionary] = []

func bind_player(player: Player) -> void:
	_player = player
	_pawns.clear()
	if player != null:
		_pawns.append(player)

func bind_players(players: Array[Player]) -> void:
	_pawns = players.duplicate()
	if players.is_empty():
		_player = null
		return
	_player = players[0]

func bind_session(session: RunSession) -> void:
	_session = session

func capture_baseline() -> void:
	_pawn_bases.clear()
	for pawn: Player in _pawns:
		if pawn == null:
			continue
		_pawn_bases.append(_capture_pawn(pawn))
	_captured = not _pawn_bases.is_empty()
	if not _pawns.is_empty():
		_player = _pawns[0]

func apply_owned() -> void:
	if not _captured:
		return
	var count: int = mini(_pawns.size(), _pawn_bases.size())
	for i: int in count:
		_apply_pawn(_pawns[i], _pawn_bases[i])

func _capture_pawn(pawn: Player) -> Dictionary:
	var health: PlayerHealth = pawn.get_player_health()
	var host: WeaponHost = pawn.get_weapon_host()
	var damage: PackedInt32Array = PackedInt32Array()
	var fire_interval: PackedFloat32Array = PackedFloat32Array()
	var projectile_speed: PackedFloat32Array = PackedFloat32Array()
	for weapon: Weapon in host.get_weapons():
		damage.append(weapon.damage)
		fire_interval.append(weapon.fire_interval)
		projectile_speed.append(weapon.projectile_speed)
	var shotgun_pellets: int = 0
	var shotgun: Shotgun = host.get_shotgun()
	if shotgun != null:
		shotgun_pellets = shotgun.pellet_count
	var rifle_max_spread: float = 0.0
	var rifle: Rifle = host.get_rifle()
	if rifle != null:
		rifle_max_spread = rifle.max_spread_deg
	return {
		"max_hp": health.max_hp,
		"i_frame_sec": health.i_frame_sec,
		"move_speed": pawn.get_player_motor().move_speed,
		"knockback_impulse": pawn.knockback_impulse,
		"weapon_damage": damage,
		"weapon_fire_interval": fire_interval,
		"weapon_projectile_speed": projectile_speed,
		"shotgun_pellets": shotgun_pellets,
		"rifle_max_spread": rifle_max_spread,
	}

func _apply_pawn(pawn: Player, baseline: Dictionary) -> void:
	if pawn == null:
		return
	var totals: Dictionary = _empty_totals()
	_accumulate_owned(pawn, totals)
	var health: PlayerHealth = pawn.get_player_health()
	health.apply_max_hp(maxi(MIN_MAX_HP, int(baseline["max_hp"]) + int(totals["max_hp_flat"])))
	health.i_frame_sec = maxf(MIN_I_FRAME_SEC, float(baseline["i_frame_sec"]) + float(totals["i_frame_flat"]))
	pawn.get_player_motor().move_speed = maxf(MIN_MOVE_SPEED, float(baseline["move_speed"]) * (1.0 + float(totals["move_speed_pct"])))
	pawn.knockback_impulse = float(baseline["knockback_impulse"]) * (1.0 + float(totals["knockback_taken_pct"]))
	var fire_denom: float = 1.0 + float(totals["fire_rate_pct"])
	if fire_denom <= 0.0:
		fire_denom = 0.0001
	var host: WeaponHost = pawn.get_weapon_host()
	var weapons: Array[Weapon] = host.get_weapons()
	var damage: PackedInt32Array = baseline["weapon_damage"]
	var fire_interval: PackedFloat32Array = baseline["weapon_fire_interval"]
	var projectile_speed: PackedFloat32Array = baseline["weapon_projectile_speed"]
	for i: int in weapons.size():
		var weapon: Weapon = weapons[i]
		weapon.damage = int(damage[i]) + int(totals["damage_flat"])
		weapon.fire_interval = maxf(MIN_FIRE_INTERVAL, float(fire_interval[i]) / fire_denom)
		weapon.projectile_speed = float(projectile_speed[i]) + float(totals["projectile_speed_flat"])
	var shotgun: Shotgun = host.get_shotgun()
	if shotgun != null:
		shotgun.pellet_count = clampi(int(baseline["shotgun_pellets"]) + int(totals["shotgun_pellets_flat"]), MIN_PELLETS, MAX_PELLETS)
	var rifle: Rifle = host.get_rifle()
	if rifle == null:
		return
	rifle.max_spread_deg = maxf(rifle.min_spread_deg, float(baseline["rifle_max_spread"]) + float(totals["rifle_max_spread_flat"]))
	rifle.clamp_current_spread_to_max()

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

func _accumulate_owned(pawn: Player, totals: Dictionary) -> void:
	if _session == null or pawn == null:
		return
	var catalog: UpgradeCatalog = _session.get_catalog()
	if catalog == null:
		return
	for upgrade_id: String in _session.get_owned_upgrade_ids():
		var def: UpgradeDef = catalog.get_by_id(StringName(upgrade_id))
		if def == null:
			continue
		if not def.character_id.is_empty() and pawn.get_character_id() != def.character_id:
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
