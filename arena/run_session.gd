extends Node
class_name RunSession

## 本局状态：只观察玩家是否死亡、句读是否打完。禁止镜像 HP，禁止暂停场景树。
enum Outcome { PLAYING, DEAD, CLEARED }

var _player: Player
var _encounter: EncounterPhrases
var _catalog: UpgradeCatalog
var _outcome: Outcome = Outcome.PLAYING
var _elapsed_sec: float = 0.0
var _owned_ids: PackedStringArray = PackedStringArray()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func bind_player(player: Player) -> void:
	_player = player

func bind_encounter(encounter: EncounterPhrases) -> void:
	_encounter = encounter

func bind_catalog(catalog: UpgradeCatalog) -> void:
	_catalog = catalog

func try_grant(upgrade_id: StringName) -> bool:
	if _catalog == null:
		return false
	var def: UpgradeDef = _catalog.get_by_id(upgrade_id)
	if def == null:
		return false
	if not def.stackable and has_upgrade(upgrade_id):
		return false
	_owned_ids.append(String(upgrade_id))
	return true

func draft_offer(count: int = 3) -> Array[UpgradeDef]:
	var picked: Array[UpgradeDef] = []
	if _catalog == null or count <= 0:
		return picked
	var pool: Array[UpgradeDef] = []
	for def: UpgradeDef in _catalog.get_all():
		if def == null:
			continue
		if not def.stackable and has_upgrade(def.id):
			continue
		pool.append(def)
	_shuffle_defs(pool)
	var take: int = mini(count, pool.size())
	for i: int in take:
		picked.append(pool[i])
	return picked

func restart() -> void:
	_outcome = Outcome.PLAYING
	_elapsed_sec = 0.0
	_owned_ids.clear()
	_rng.randomize()

func tick(delta: float) -> void:
	if _outcome != Outcome.PLAYING:
		return
	_elapsed_sec += delta
	if _player != null and _player.is_defeated():
		_outcome = Outcome.DEAD
		return
	if _encounter != null and _encounter.is_done():
		_outcome = Outcome.CLEARED

func get_outcome() -> Outcome:
	return _outcome

func is_playing() -> bool:
	return _outcome == Outcome.PLAYING

func is_player_dead() -> bool:
	return _outcome == Outcome.DEAD

func is_cleared() -> bool:
	return _outcome == Outcome.CLEARED

func get_elapsed_sec() -> float:
	return _elapsed_sec

func get_outcome_label() -> String:
	if _outcome == Outcome.DEAD:
		return "dead"
	if _outcome == Outcome.CLEARED:
		return "cleared"
	return "playing"

func get_catalog() -> UpgradeCatalog:
	return _catalog

func get_owned_upgrade_ids() -> PackedStringArray:
	return _owned_ids.duplicate()

func get_owned_count() -> int:
	return _owned_ids.size()

func has_upgrade(upgrade_id: StringName) -> bool:
	return String(upgrade_id) in _owned_ids

func _shuffle_defs(defs: Array[UpgradeDef]) -> void:
	for i: int in range(defs.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: UpgradeDef = defs[i]
		defs[i] = defs[j]
		defs[j] = tmp
