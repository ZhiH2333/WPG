extends Node
class_name RunSession

## 本局状态：只观察玩家是否死亡。禁止镜像 HP，禁止暂停场景树。P8 后仍 playing，由沙盒再开一轮。XP 与 gold 只活在本节点。
enum Outcome { PLAYING, DEAD, CLEARED }

const XP_BASE: int = 30
const XP_PER_LEVEL: int = 15
const SHOP_COSTS: Dictionary = {
	"max_hp_s": 25,
	"max_hp_m": 50,
	"swift": 30,
	"heavy_round": 30,
	"cadence": 30,
	"long_shot": 25,
	"second_skin": 45,
	"extra_pellets": 30,
	"steady_rifle": 30,
	"thick_hide": 30,
}
const SHOP_COST_FALLBACK: int = 30

var _player: Player
var _encounter: EncounterPhrases
var _catalog: UpgradeCatalog
var _outcome: Outcome = Outcome.PLAYING
var _elapsed_sec: float = 0.0
var _owned_ids: PackedStringArray = PackedStringArray()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _loop_index: int = 0
var _level: int = 1
var _xp: int = 0
var _pending_level: int = 0
var _kill_count: int = 0
var _gold: int = 0

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

func notify_phrase_loop() -> void:
	_loop_index += 1
	_outcome = Outcome.PLAYING

func get_loop_index() -> int:
	return _loop_index

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	_xp += amount
	var need: int = get_xp_to_next()
	while _xp >= need:
		_xp -= need
		_level += 1
		_pending_level += 1
		need = get_xp_to_next()

func get_level() -> int:
	return _level

func get_xp() -> int:
	return _xp

func get_xp_to_next() -> int:
	return XP_BASE + (_level - 1) * XP_PER_LEVEL

func get_pending_level_count() -> int:
	return _pending_level

func has_pending_level() -> bool:
	return _pending_level > 0

func consume_pending_level() -> bool:
	if _pending_level <= 0:
		return false
	_pending_level -= 1
	return true

func note_kill() -> void:
	_kill_count += 1

func get_kill_count() -> int:
	return _kill_count

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	if _outcome != Outcome.PLAYING:
		return
	_gold += amount

func get_gold() -> int:
	return _gold

func try_spend(amount: int) -> bool:
	if amount <= 0 or _gold < amount:
		return false
	_gold -= amount
	return true

func get_shop_cost(upgrade_id: StringName) -> int:
	var key: String = String(upgrade_id)
	if not SHOP_COSTS.has(key):
		return SHOP_COST_FALLBACK
	return int(SHOP_COSTS[key])

func restart() -> void:
	_outcome = Outcome.PLAYING
	_elapsed_sec = 0.0
	_owned_ids.clear()
	_loop_index = 0
	_level = 1
	_xp = 0
	_pending_level = 0
	_kill_count = 0
	_gold = 0
	_rng.randomize()

func tick(delta: float) -> void:
	if _outcome != Outcome.PLAYING:
		return
	_elapsed_sec += delta
	if _player != null and _player.is_defeated():
		_outcome = Outcome.DEAD
		_pending_level = 0

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
