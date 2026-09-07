extends Node
class_name EncounterPhrases

## 手写战场句读：hold / activate 已有节点。禁止预算、权重随机、WaveDirector。
const REST_SEC: float = 1.5
const PHRASE_TOTAL: int = 8
const P1_NAMES: PackedStringArray = ["MeleeLeft1", "MeleeLeft2", "MeleeLeft3", "MeleeLeft4"]
const P3_NAMES: PackedStringArray = ["RangedRight1", "RangedRight2", "RangedRight3"]
const P5_NAMES: PackedStringArray = [
	"MeleeBottom1", "MeleeBottom2", "MeleeBottom3", "MeleeBottom4", "MeleeBottom5", "MeleeBottom6",
	"RangedTop1", "RangedTop2",
]
const P7_NAMES: PackedStringArray = [
	"MeleeLeft5", "MeleeLeft6", "MeleeLeft7", "MeleeLeft8", "MeleeLeft9", "MeleeLeft10",
	"MeleeBottom7", "MeleeBottom8", "MeleeBottom9", "MeleeBottom10",
	"RangedRight4", "RangedRight5", "RangedRight6",
	"RangedTop3", "RangedTop4",
]

enum State { RESTING, PLAYING, AWAITING_OFFER, DONE }

var _state: State = State.RESTING
var _phrase_index: int = 0
var _rest_left: float = 0.0
var _p3_started: bool = false
var _enemies_by_name: Dictionary = {}
var _wait_names: PackedStringArray = PackedStringArray()
var _run_session: RunSession

func bind_enemies(enemies: Array[EnemyBase]) -> void:
	_enemies_by_name.clear()
	for enemy: EnemyBase in enemies:
		_enemies_by_name[enemy.name] = enemy

func bind_run_session(session: RunSession) -> void:
	_run_session = session

func restart() -> void:
	_p3_started = false
	_wait_names = PackedStringArray()
	_begin_phrase(0)

func tick(delta: float) -> void:
	if _state == State.AWAITING_OFFER:
		return
	if _state == State.RESTING:
		_tick_rest(delta)
		return
	if _state == State.PLAYING:
		_tick_playing()

func is_done() -> bool:
	return _state == State.DONE

func is_resting() -> bool:
	return _state == State.RESTING

func is_awaiting_offer() -> bool:
	return _state == State.AWAITING_OFFER

func acknowledge_offer() -> void:
	if _state != State.AWAITING_OFFER:
		return
	_begin_phrase(_phrase_index + 1)

func get_rest_left() -> float:
	return _rest_left

func get_rest_sec() -> float:
	return _rest_sec()

func get_phrase_alive() -> int:
	return _count_alive(_wait_names)

func get_phrase_label() -> String:
	if _state == State.DONE:
		return "phrases_done"
	if _state == State.AWAITING_OFFER:
		return "offer"
	if _state == State.RESTING:
		if _phrase_index == 0:
			return "0/8"
		return "rest"
	return "%d/%d" % [_phrase_index, PHRASE_TOTAL]

func _begin_phrase(index: int) -> void:
	_phrase_index = index
	if index == 0 or index == 2 or index == 4 or index == 6:
		_begin_rest_or_skip(index)
		return
	if index == 1:
		_start_playing(P1_NAMES, P1_NAMES)
		return
	if index == 3:
		_start_p3()
		return
	if index == 5:
		_start_playing(P5_NAMES, P5_NAMES)
		return
	if index == 7:
		_start_playing(P7_NAMES, PackedStringArray())
		return
	_state = State.DONE
	_rest_left = 0.0
	_wait_names = PackedStringArray()

func _begin_rest_or_skip(index: int) -> void:
	if index == 2 and _p3_started:
		_begin_phrase(3)
		return
	_wait_names = PackedStringArray()
	if index == 0:
		_state = State.RESTING
		_rest_left = _rest_sec()
		return
	_state = State.AWAITING_OFFER
	_rest_left = 0.0

func _start_playing(activate_names: PackedStringArray, wait_names: PackedStringArray) -> void:
	_state = State.PLAYING
	_rest_left = 0.0
	_activate_named(activate_names)
	_wait_names = wait_names

func _start_p3() -> void:
	_state = State.PLAYING
	_rest_left = 0.0
	if not _p3_started:
		_activate_named(P3_NAMES)
		_p3_started = true
	_wait_names = _merged(P1_NAMES, P3_NAMES)

func _tick_rest(delta: float) -> void:
	_rest_left = maxf(0.0, _rest_left - delta)
	if _rest_left > 0.0:
		return
	_begin_phrase(_phrase_index + 1)

func _tick_playing() -> void:
	_try_overlap_p3()
	if _phrase_index == 7:
		if _count_field_alive() > 0:
			return
		_begin_phrase(8)
		return
	if _count_alive(_wait_names) > 0:
		return
	_begin_phrase(_phrase_index + 1)

func _try_overlap_p3() -> void:
	if _phrase_index != 1 or _p3_started:
		return
	var alive_p1: int = _count_alive(P1_NAMES)
	if alive_p1 <= 0 or alive_p1 > 2:
		return
	_activate_named(P3_NAMES)
	_p3_started = true

func _activate_named(names: PackedStringArray) -> void:
	var side_index: Dictionary = {}
	for enemy_name: String in names:
		var enemy: EnemyBase = _resolve(enemy_name)
		if enemy == null:
			push_error("句读找不到节点: %s" % enemy_name)
			continue
		if not enemy.is_in_reserve():
			continue
		enemy.activate_from_reserve()
		var side: String = _side_key_for(enemy.get_spawn_position())
		var index_in_side: int = int(side_index.get(side, 0))
		side_index[side] = index_in_side + 1
		enemy.assign_spawn_stagger(_stagger_for_side(side, index_in_side))

func _count_alive(names: PackedStringArray) -> int:
	var n: int = 0
	for enemy_name: String in names:
		var enemy: EnemyBase = _resolve(enemy_name)
		if enemy == null or enemy.is_in_reserve() or enemy.is_defeated():
			continue
		n += 1
	return n

func _count_field_alive() -> int:
	var n: int = 0
	for enemy_name: String in _enemies_by_name.keys():
		var enemy: EnemyBase = _resolve(enemy_name)
		if enemy == null or enemy.is_in_reserve() or enemy.is_defeated():
			continue
		n += 1
	return n

func _resolve(enemy_name: String) -> EnemyBase:
	if not _enemies_by_name.has(enemy_name):
		return null
	return _enemies_by_name[enemy_name] as EnemyBase

func _merged(left: PackedStringArray, right: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = left.duplicate()
	out.append_array(right)
	return out

func _side_key_for(spawn: Vector2) -> String:
	if spawn.x < -300.0:
		return "left"
	if spawn.y > 300.0:
		return "bottom"
	if spawn.x > 400.0:
		return "right"
	return "top"

func _rest_sec() -> float:
	var loop: int = 0
	if _run_session != null:
		loop = _run_session.get_loop_index()
	return maxf(0.75, REST_SEC - 0.25 * float(mini(loop, 8)))

func _stagger_for_side(side: String, index_in_side: int) -> float:
	var base_sec: float = 0.0
	if side == "bottom":
		base_sec = 0.04
	elif side == "right":
		base_sec = 0.06
	elif side == "top":
		base_sec = 0.08
	return clampf(base_sec + float(index_in_side) * 0.06, 0.0, 0.8)
