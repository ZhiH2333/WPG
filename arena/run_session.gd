extends Node
class_name RunSession

## 本局状态：只观察玩家是否死亡。禁止镜像 HP，禁止暂停场景树。P8 后仍 playing，由沙盒再开一轮。
##
## 数据归属（V2 Save Architecture）：
##   SharedRunState  -> loop / elapsed / seed / mode / outcome / arena / slot id（所有玩家共享）
##   PlayerRunState  -> 每个玩家自己的 xp / level / gold / kills / upgrades（按 profile_id 索引）
## RunSession 只**导出**这些数据（export_checkpoint / export_result），绝不自己写磁盘、
## 绝不碰 FileAccess / ENet / MultiplayerPeer。持久化唯一入口是 GameSaveStore。
## 旧的 get_gold / get_xp / get_owned_upgrade_ids 等 getter 保留为兼容层，
## 现在读的是本机玩家的 PlayerRunState，不再是 RunSession 的全局字段。
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
	"light_step": 30,
	"beak_shot": 30,
	"feather_frame": 45,
	"quick_peck": 30,
}
const SHOP_COST_FALLBACK: int = 30
## 一局最多这么多只「活着」的跟班。尸体留在 _companions 里但不占额度。
const COMPANION_CAP: int = 30
const DEFAULT_PROFILE_ID: String = "local"

var _player: Player
var _players: Array[Player] = []
var _encounter: EncounterPhrases
var _catalog: UpgradeCatalog
var _companion_catalog: CompanionCatalog
var _consumable_catalog: ConsumableCatalog
var _living_companion_count: int = 0
var _outcome: Outcome = Outcome.PLAYING
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## ---- 新的 authoritative data model ----
var _shared: SharedRunState = SharedRunState.new()
## profile_id -> PlayerRunState。peer_id 不参与索引。
var _player_states: Dictionary = {}
var _local_profile_id: String = DEFAULT_PROFILE_ID
var _local_display_name: String = ""
var _local_seat: int = 1
var _local_state: PlayerRunState

func _init() -> void:
	_reset_player_states()

# ---- 绑定 ----

func bind_player(player: Player) -> void:
	_player = player
	_players.clear()
	if player != null:
		_players.append(player)

func bind_players(players: Array[Player]) -> void:
	_players.clear()
	for pawn: Player in players:
		if pawn == null:
			continue
		_players.append(pawn)
	if _players.is_empty():
		_player = null
		return
	_player = _players[0]

func bind_encounter(encounter: EncounterPhrases) -> void:
	_encounter = encounter

func bind_catalog(catalog: UpgradeCatalog) -> void:
	_catalog = catalog

func bind_companion_catalog(catalog: CompanionCatalog) -> void:
	_companion_catalog = catalog

func bind_consumable_catalog(catalog: ConsumableCatalog) -> void:
	_consumable_catalog = catalog

## 本机持久身份。由 CombatSandbox 从 PlayerProfile 取；不是 peer_id，不是 seat。
func bind_local_profile(profile_id: String, display_name: String, seat: int = 1) -> void:
	var resolved: String = profile_id.strip_edges()
	_local_profile_id = resolved if not resolved.is_empty() else DEFAULT_PROFILE_ID
	_local_display_name = display_name
	_local_seat = clampi(seat, 1, GameLaunch.NET_MAX_SEATS)
	_reset_player_states()

func get_local_profile_id() -> String:
	return _local_profile_id

func get_shared_state() -> SharedRunState:
	return _shared

func get_player_states() -> Array[PlayerRunState]:
	var rows: Array[PlayerRunState] = []
	for key: Variant in _player_states:
		var state: PlayerRunState = _player_states[key] as PlayerRunState
		if state != null:
			rows.append(state)
	rows.sort_custom(_is_seat_earlier)
	return rows

func get_player_state(profile_id: String) -> PlayerRunState:
	if profile_id.is_empty():
		return null
	var state: PlayerRunState = _player_states.get(profile_id, null) as PlayerRunState
	return state

func get_local_player_state() -> PlayerRunState:
	return _local()

## 由 CombatSandbox 在提交检查点前喂入本机跟班清单（只存 id + 武器槽，不存位置 / HP）。
func set_local_companions(rows: Array) -> void:
	var state: PlayerRunState = _local()
	var parsed: Array[Dictionary] = []
	for row: Variant in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		parsed.append((row as Dictionary).duplicate(true))
	state.companions = parsed

func get_local_companions() -> Array[Dictionary]:
	return _local().companions.duplicate(true)

func set_save_slot_id(slot_id: String) -> void:
	_shared.save_slot_id = slot_id

func get_save_slot_id() -> String:
	return _shared.save_slot_id

func set_arena_id(arena_id: String) -> void:
	_shared.arena_id = arena_id

func get_arena_id() -> String:
	return _shared.arena_id

# ---- 本局配置 ----

func set_living_companion_count(count: int) -> void:
	_living_companion_count = clampi(count, 0, COMPANION_CAP)

func get_living_companion_count() -> int:
	return _living_companion_count

func has_living_companion() -> bool:
	return _living_companion_count > 0

func can_buy_companion() -> bool:
	return _living_companion_count < COMPANION_CAP

func configure_mode(loop_goal: int) -> void:
	_shared.loop_goal = maxi(loop_goal, 0)
	_shared.mode = "solo" if _shared.loop_goal > 0 else "infinite"

func get_loop_goal() -> int:
	return _shared.loop_goal

func is_solo() -> bool:
	return _shared.loop_goal > 0

# ---- 升级 / 商店 ----

func try_grant(upgrade_id: StringName) -> bool:
	if _catalog == null:
		return false
	var def: UpgradeDef = _catalog.get_by_id(upgrade_id)
	if def == null:
		return false
	if not def.stackable and has_upgrade(upgrade_id):
		return false
	if not _is_def_for_present(def, _present_character_ids()):
		return false
	_local().add_upgrade(String(upgrade_id))
	return true

func draft_offer(count: int = 3) -> Array[UpgradeDef]:
	var picked: Array[UpgradeDef] = []
	if count <= 0:
		return picked
	var pool: Array[UpgradeDef] = _collect_pool_defs()
	_shuffle_defs(pool)
	var take: int = mini(count, pool.size())
	for i: int in take:
		picked.append(pool[i])
	return picked

func draft_shop_cards(count: int = 3) -> Array[ShopCard]:
	var cards: Array[ShopCard] = []
	if count <= 0:
		return cards
	var gunner: CompanionDef = _find_shop_gunner()
	var include_companion: bool = gunner != null and can_buy_companion()
	var upgrade_count: int = count
	if include_companion:
		upgrade_count = count - 1
	var upgrades: Array[UpgradeDef] = draft_offer(upgrade_count)
	for def: UpgradeDef in upgrades:
		cards.append(ShopCard.for_upgrade(def))
	if include_companion:
		cards.append(ShopCard.for_companion(gunner))
	return cards

func list_shop_catalog() -> Array[ShopCard]:
	var cards: Array[ShopCard] = []
	if _consumable_catalog != null:
		for def: ConsumableDef in _consumable_catalog.get_all():
			if def == null:
				continue
			cards.append(ShopCard.for_consumable(def))
	for def: UpgradeDef in _collect_pool_defs():
		cards.append(ShopCard.for_upgrade(def))
	var gunner: CompanionDef = _find_shop_gunner()
	if gunner != null and can_buy_companion():
		cards.append(ShopCard.for_companion(gunner))
	return cards

func _find_shop_gunner() -> CompanionDef:
	if _companion_catalog == null:
		return null
	return _companion_catalog.get_by_id(&"gunner")

# ---- loop / 经验 / 金币（兼容层，底层读 PlayerRunState / SharedRunState）----

func notify_phrase_loop() -> void:
	_shared.loop_index += 1
	_outcome = Outcome.PLAYING

func get_loop_index() -> int:
	return _shared.loop_index

func debug_set_loop_index(value: int) -> void:
	_shared.loop_index = clampi(value, 0, 99)

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var state: PlayerRunState = _local()
	state.xp += amount
	var need: int = get_xp_to_next()
	while state.xp >= need:
		state.xp -= need
		state.level += 1
		state.pending_level += 1
		need = get_xp_to_next()

func get_level() -> int:
	return _local().level

func get_xp() -> int:
	return _local().xp

func get_xp_to_next() -> int:
	return XP_BASE + (_local().level - 1) * XP_PER_LEVEL

func get_pending_level_count() -> int:
	return _local().pending_level

func has_pending_level() -> bool:
	return _local().pending_level > 0

func consume_pending_level() -> bool:
	if _local().pending_level <= 0:
		return false
	_local().pending_level -= 1
	return true

func note_kill() -> void:
	_local().kill_count += 1

func get_kill_count() -> int:
	return _local().kill_count

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	if _outcome != Outcome.PLAYING:
		return
	_local().gold += amount

func get_gold() -> int:
	return _local().gold

func try_spend(amount: int) -> bool:
	if amount <= 0 or _local().gold < amount:
		return false
	_local().gold -= amount
	return true

func get_shop_cost(upgrade_id: StringName) -> int:
	var key: String = String(upgrade_id)
	if not SHOP_COSTS.has(key):
		return SHOP_COST_FALLBACK
	return int(SHOP_COSTS[key])

## ---- 本局 HP 时间线（只服务结算页的 HP-时间图）----
## 事件式采样：只有 HP 真的变化时才记一个点，长局也不会堆出上千个点。
## 横轴 = 秒，纵轴 = hp/max_hp（0..1）。只在内存里，不落盘、不进网络。
var _hp_timeline: PackedVector2Array = PackedVector2Array()
var _hp_timeline_last_hp: int = -1

## 由 gameplay 每帧喂当前 HP。HP 没变直接返回，不做任何分配。
func record_hp(hp: int, max_hp: int) -> void:
	if hp == _hp_timeline_last_hp:
		return
	_hp_timeline_last_hp = hp
	var ratio: float = 1.0
	if max_hp > 0:
		ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_hp_timeline.append(Vector2(maxf(_shared.elapsed_sec, 0.0), ratio))

func get_hp_timeline() -> PackedVector2Array:
	return _hp_timeline.duplicate()

func clear_hp_timeline() -> void:
	_hp_timeline = PackedVector2Array()
	_hp_timeline_last_hp = -1

# ---- 生命周期 ----

## START_NEW_RUN 专用：换新的 run_id、清空所有 runtime state（升级 / loop / xp / level /
## gold / kills / companions）。**RESUME_RUN 绝对不允许调用它** —— 续跑必须走
## restore_checkpoint()，否则就是「先 reset 再覆盖部分字段」。
func restart() -> void:
	var loop_goal: int = _shared.loop_goal
	var slot_id: String = _shared.save_slot_id
	var arena_id: String = _shared.arena_id
	var mode: String = _shared.mode
	_shared = SharedRunState.new()
	_shared.loop_goal = loop_goal
	_shared.save_slot_id = slot_id
	_shared.arena_id = arena_id
	_shared.mode = mode
	_shared.run_id = _make_run_id()
	_outcome = Outcome.PLAYING
	_reset_player_states()
	_living_companion_count = 0
	clear_hp_timeline()
	_rng.randomize()
	_shared.run_seed = _rng.seed
	_shared.checkpoint_kind = RunCheckpoint.kind_name(RunCheckpoint.Kind.RUN_START)

func tick(delta: float) -> void:
	if _outcome != Outcome.PLAYING:
		return
	_shared.elapsed_sec += delta
	if _are_all_defeated():
		_outcome = Outcome.DEAD
		_local().pending_level = 0

func _are_all_defeated() -> bool:
	if _players.is_empty():
		return _player != null and _player.is_defeated()
	for pawn: Player in _players:
		if pawn != null and not pawn.is_defeated():
			return false
	return true

func apply_net_session(loop_index: int, gold: int, kills: int, xp: int, level: int, pending_level: int, outcome_code: int, elapsed_sec: float, owned_ids: PackedStringArray) -> void:
	_shared.loop_index = loop_index
	_shared.elapsed_sec = elapsed_sec
	var state: PlayerRunState = _local()
	state.gold = gold
	state.kill_count = kills
	state.xp = xp
	state.level = maxi(1, level)
	state.pending_level = maxi(0, pending_level)
	var owned: Array[String] = []
	for id: String in owned_ids:
		owned.append(id)
	state.owned_upgrade_ids = owned
	if outcome_code == int(Outcome.DEAD):
		_outcome = Outcome.DEAD
		return
	if outcome_code == int(Outcome.CLEARED):
		_outcome = Outcome.CLEARED
		return
	_outcome = Outcome.PLAYING

func get_outcome() -> Outcome:
	return _outcome

func is_playing() -> bool:
	return _outcome == Outcome.PLAYING

func is_player_dead() -> bool:
	return _outcome == Outcome.DEAD

func is_cleared() -> bool:
	return _outcome == Outcome.CLEARED

func mark_cleared() -> void:
	if _outcome != Outcome.PLAYING:
		return
	_outcome = Outcome.CLEARED
	_local().pending_level = 0

func mark_battle_over() -> void:
	if _outcome != Outcome.PLAYING:
		return
	_outcome = Outcome.DEAD
	_local().pending_level = 0

func get_elapsed_sec() -> float:
	return _shared.elapsed_sec

func get_outcome_label() -> String:
	if _outcome == Outcome.DEAD:
		return "dead"
	if _outcome == Outcome.CLEARED:
		return "cleared"
	return "playing"

func get_catalog() -> UpgradeCatalog:
	return _catalog

func get_owned_upgrade_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for id: String in _local().owned_upgrade_ids:
		ids.append(id)
	return ids

func get_owned_count() -> int:
	return _local().owned_upgrade_ids.size()

func has_upgrade(upgrade_id: StringName) -> bool:
	return String(upgrade_id) in _local().owned_upgrade_ids

# ---- 导出 / 恢复（RunSession 只 export，SaveStore 才落盘）----

## 把当前 run 打成一个安全检查点。不保存敌人 AI / 弹体 / 动画 / 瞬时 timer。
func export_checkpoint(kind: int, save_slot_id: String = "") -> RunCheckpoint:
	_sync_local_vitals()
	_shared.outcome = get_outcome_label()
	_shared.checkpoint_kind = RunCheckpoint.kind_name(kind)
	if not save_slot_id.is_empty():
		_shared.save_slot_id = save_slot_id
	return RunCheckpoint.create(kind, _shared, get_player_states())

## 把本局结算成 RunResult（含 player score / team score / scoring_version）。
func export_result(save_slot_id: String, outcome: String) -> RunResult:
	_sync_local_vitals()
	var resolved: String = RunResult.sanitize_outcome(outcome)
	var result: RunResult = RunResult.new()
	result.run_id = _shared.run_id
	result.save_slot_id = save_slot_id
	result.outcome = resolved
	result.loop_index = _shared.loop_index
	result.elapsed_sec = _shared.elapsed_sec
	result.scoring_version = RunResult.SCORING_VERSION
	result.timestamp = int(Time.get_unix_time_from_system())
	var team_total: int = 0
	for state: PlayerRunState in get_player_states():
		var score: int = RunResult.compute_score(
			_shared.loop_index, state.kill_count, state.gold, _shared.elapsed_sec, resolved
		)
		state.score = score
		result.player_scores[state.profile_id] = score
		team_total += score
	result.team_score = team_total
	result.score = _local().score
	## history 是**账本**：gold / kills 必须跟着走，否则记分板只剩一个总分，
	## 旧局的「这局攒了多少」直接丢了（RunHistoryEntry.gold/kills 会永远是 0）。
	result.kill_count = _local().kill_count
	result.gold = _local().gold
	return result

## 恢复最近一次已提交的 checkpoint（SAFE CHECKPOINT：只在 loop 边界 / 决策点恢复）。
func restore_checkpoint(checkpoint: RunCheckpoint) -> bool:
	if checkpoint == null:
		return false
	if checkpoint.shared_state != null:
		_shared = checkpoint.shared_state.duplicate_state()
	_shared.run_id = checkpoint.run_id if not checkpoint.run_id.is_empty() else _shared.run_id
	_shared.save_slot_id = checkpoint.save_slot_id if not checkpoint.save_slot_id.is_empty() else _shared.save_slot_id
	_outcome = _outcome_from_label(_shared.outcome)
	_rng.seed = _shared.run_seed
	_reset_player_states()
	if checkpoint.players.size() == 1 and checkpoint.players[0] != null:
		## 单人档：唯一那份 PlayerRunState 就是本机玩家的。
		var only: PlayerRunState = checkpoint.players[0]
		only.profile_id = _local_profile_id
		_player_states[_local_profile_id] = only
		_local_state = only
	else:
		for state: PlayerRunState in checkpoint.players:
			if state == null or state.profile_id.is_empty():
				continue
			_player_states[state.profile_id] = state
			if state.profile_id == _local_profile_id:
				_local_state = state
	_living_companion_count = 0
	return true

## 把 Pawn 上的实时 HP 写回本机 PlayerRunState（checkpoint 导出前调用）。
func _sync_local_vitals() -> void:
	var state: PlayerRunState = _local()
	if _player == null:
		return
	var health: PlayerHealth = _player.get_player_health()
	if health == null:
		return
	state.max_hp = maxi(1, health.get_max_hp())
	state.hp = clampi(health.get_hp(), 0, state.max_hp)
	state.alive = not health.is_defeated()
	if state.alive:
		state.eliminated = false

func _local() -> PlayerRunState:
	if _local_state == null:
		_reset_player_states()
	return _local_state

func _reset_player_states() -> void:
	_player_states.clear()
	var state: PlayerRunState = PlayerRunState.create(
		_local_profile_id, _local_display_name, _character_id_for_state(), _local_seat
	)
	_player_states[state.profile_id] = state
	_local_state = state

func _character_id_for_state() -> String:
	if _player == null:
		return PlayerRunState.CHARACTER_BOAR
	var character_id: String = _player.get_character_id()
	if character_id.is_empty():
		return PlayerRunState.CHARACTER_BOAR
	return character_id

func _make_run_id() -> String:
	return "run%d-%d" % [int(Time.get_unix_time_from_system()), randi()]

func _outcome_from_label(label: String) -> Outcome:
	if label == "dead":
		return Outcome.DEAD
	if label == "cleared":
		return Outcome.CLEARED
	return Outcome.PLAYING

func _is_seat_earlier(left: PlayerRunState, right: PlayerRunState) -> bool:
	if left == null or right == null:
		return right != null
	return left.seat < right.seat

# ---- 沙盒内部复用 ----

func _collect_pool_defs() -> Array[UpgradeDef]:
	var pool: Array[UpgradeDef] = []
	if _catalog == null:
		return pool
	var present: PackedStringArray = _present_character_ids()
	for def: UpgradeDef in _catalog.get_all():
		if def == null:
			continue
		if not _is_def_for_present(def, present):
			continue
		if not def.stackable and has_upgrade(def.id):
			continue
		pool.append(def)
	return pool

func _present_character_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for pawn: Player in _players:
		if pawn == null:
			continue
		var character_id: String = pawn.get_character_id()
		if character_id.is_empty() or character_id in ids:
			continue
		ids.append(character_id)
	if ids.is_empty():
		ids.append("boar")
	return ids

func _is_def_for_present(def: UpgradeDef, present: PackedStringArray) -> bool:
	if def.character_id.is_empty():
		return true
	return def.character_id in present

func _shuffle_defs(defs: Array[UpgradeDef]) -> void:
	for i: int in range(defs.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: UpgradeDef = defs[i]
		defs[i] = defs[j]
		defs[j] = tmp
