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

func bind_player(player: Player) -> void:
	_player = player

func bind_encounter(encounter: EncounterPhrases) -> void:
	_encounter = encounter

func bind_catalog(catalog: UpgradeCatalog) -> void:
	_catalog = catalog

func restart() -> void:
	_outcome = Outcome.PLAYING
	_elapsed_sec = 0.0
	_owned_ids.clear()

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
