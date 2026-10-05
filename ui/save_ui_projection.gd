extends RefCounted
class_name SaveUiProjection

## 存档 -> 界面的唯一投影（Save Management UX / §15）。
##
## MainMenu、PlayPage、RecordSelector **全部**走这一条路：
##   `SaveUiProjection.load_*()` -> `GameSaveStore.load_from_disk()` -> 读 `SaveSlot` -> 建投影。
## 界面自己不读 records.json、不用 history 长度猜状态、不判断「有没有 active run」——
## 状态只来自 `SaveSlot.status`，进行中的进度只来自 `SaveSlot.active_run`。
##
## 分数也不是这里发明的：一律转调 `RunResult.compute_score`（唯一算法真源）。

const CHARACTER_CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")

const STATUS_NEW := "NEW"
const STATUS_IN_PROGRESS := "IN_PROGRESS"
const STATUS_CLEARED := "CLEARED"
const STATUS_FAILED := "FAILED"

## 界面上的状态**文字**。色觉不敏感用户靠它，不靠颜色（§3：不能只用颜色区分）。
const STATUS_TEXT: Dictionary = {
	STATUS_NEW: "NEW",
	STATUS_IN_PROGRESS: "IN PROGRESS",
	STATUS_CLEARED: "COMPLETED",
	STATUS_FAILED: "FAILED",
}

## rail 标题 = 「这个存档现在该干什么」。
const RAIL_TEXT: Dictionary = {
	STATUS_NEW: "NEW SAVE",
	STATUS_IN_PROGRESS: "CONTINUE",
	STATUS_CLEARED: "COMPLETED",
	STATUS_FAILED: "RETRY",
}

## rail 标题下面那行 = 跟 SOLO「New run」、MULTIPLAYER「Play with friends」一样的一句话，
## **不放具体数字**（Loop / Score / Best 这些去档位列表那一排和详情浮层里看）。
const RAIL_CAPTION: Dictionary = {
	STATUS_NEW: "New run",
	STATUS_IN_PROGRESS: "Resume run",
	STATUS_CLEARED: "Start over",
	STATUS_FAILED: "Try again",
}

const RESULT_TEXT: Dictionary = {
	RunResult.OUTCOME_CLEARED: "CLEARED",
	RunResult.OUTCOME_DEAD: "DEAD",
	RunResult.OUTCOME_QUIT: "QUIT",
}

var slot_id: String = ""
var index: int = 0
var status: String = STATUS_NEW
var display_name: String = ""
var character_id: String = SaveSlot.CHARACTER_BOAR
var character_label: String = ""
var arena_id: String = "yard"
var arena_label: String = ""
var loop_goal: int = 0
var has_active_run: bool = false
var run_id: String = ""
var loop_index: int = 0
var elapsed_sec: float = 0.0
var level: int = 1
var xp: int = 0
var xp_to_next: int = 30
var gold: int = 0
var kills: int = 0
var score: int = 0
var best_score: int = 0
var history_count: int = 0
var last_result: String = ""
var last_history_at: int = 0
var last_saved_at: int = 0
var updated_at: int = 0
var created_at: int = 0


# ---- 读 ----

static func from_slot(slot: SaveSlot, index: int = 0) -> SaveUiProjection:
	var row: SaveUiProjection = SaveUiProjection.new()
	if slot == null:
		return row
	row.slot_id = slot.slot_id
	row.index = index
	row.status = SaveSlot.status_name(slot.status)
	row.display_name = slot.name
	row.character_id = slot.character_id
	row.character_label = _label_for_character(slot.character_id)
	row.arena_id = slot.arena_id
	row.arena_label = _label_for_arena(slot.arena_id)
	row.loop_goal = slot.loop_goal
	row.best_score = slot.best_score
	row.created_at = slot.created_at
	row.updated_at = slot.updated_at
	row.history_count = slot.history.size()
	## history 按分数降序排，所以「最近一次」要按时间挑，别拿 history[0] 当最新。
	var latest: RunHistoryEntry = null
	for entry: RunHistoryEntry in slot.history:
		if entry == null:
			continue
		if latest == null or entry.timestamp > latest.timestamp:
			latest = entry
	if latest != null:
		row.last_result = String(latest.outcome)
		row.last_history_at = latest.timestamp
		row.score = latest.score
		row.loop_index = maxi(latest.loop, 0)
	## active_run 才是「这一局现在到哪了」。没有就保持默认值，不猜。
	if slot.has_active_run() and slot.active_run != null:
		var checkpoint: RunCheckpoint = slot.active_run
		var shared: SharedRunState = checkpoint.shared_state
		row.has_active_run = true
		row.run_id = checkpoint.run_id
		row.last_saved_at = checkpoint.saved_at
		if shared != null:
			row.loop_index = shared.loop_index
			row.elapsed_sec = shared.elapsed_sec
			if shared.loop_goal > 0:
				row.loop_goal = shared.loop_goal
			if not shared.arena_id.is_empty():
				row.arena_id = shared.arena_id
				row.arena_label = _label_for_arena(shared.arena_id)
		var player: PlayerRunState = checkpoint.get_first_player()
		if player != null:
			row.level = maxi(player.level, 1)
			row.xp = maxi(player.xp, 0)
			row.gold = maxi(player.gold, 0)
			row.kills = maxi(player.kill_count, 0)
			if not player.character_id.is_empty():
				row.character_id = player.character_id
				row.character_label = _label_for_character(player.character_id)
		row.xp_to_next = xp_needed_for_level(row.level)
		row.score = RunResult.compute_score(row.loop_index, row.kills, row.gold, row.elapsed_sec, RunResult.OUTCOME_QUIT)
	else:
		row.xp_to_next = xp_needed_for_level(row.level)
	return row


static func load_all() -> Array[SaveUiProjection]:
	GameSaveStore.load_from_disk()
	var slots: Array[SaveSlot] = GameSaveStore.list_slots()
	slots.sort_custom(_is_recent_first)
	var rows: Array[SaveUiProjection] = []
	for i: int in slots.size():
		rows.append(from_slot(slots[i], i + 1))
	return rows


static func load_for(slot_id: String) -> SaveUiProjection:
	GameSaveStore.load_from_disk()
	var slot: SaveSlot = GameSaveStore.get_slot(slot_id)
	## 档不在了就返回 null，别回一张空投影：调用方全靠「null = 这档没了」做判断。
	if slot == null:
		return null
	return from_slot(slot, 0)


## Home 的 Continue、Play 的 Continue、选中态，全部来自这一个函数。
static func load_continue() -> SaveUiProjection:
	GameSaveStore.load_from_disk()
	var active: SaveSlot = GameSaveStore.get_latest_active_slot()
	if active != null:
		return from_slot(active, 0)
	var latest: SaveSlot = GameSaveStore.get_latest_updated_slot()
	if latest == null:
		return null
	return from_slot(latest, 0)


static func has_any_save() -> bool:
	return not load_all().is_empty()


static func xp_needed_for_level(level: int) -> int:
	return RunSession.XP_BASE + (maxi(level, 1) - 1) * RunSession.XP_PER_LEVEL


static func status_label(value: String) -> String:
	if STATUS_TEXT.has(value):
		return String(STATUS_TEXT[value])
	return String(STATUS_TEXT[STATUS_NEW])


static func format_score(value: int) -> String:
	var text: String = str(maxi(value, 0))
	var out: String = ""
	var count: int = 0
	for i: int in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


# ---- 界面文本 ----

func status_label_text() -> String:
	return SaveUiProjection.status_label(status)


func identity_line() -> String:
	return "%s  ·  %s" % [character_label, arena_label]


func loop_goal_text() -> String:
	if loop_goal <= 0:
		return "Inf"
	return str(loop_goal)


## 进行中那一轮显示到哪了。第 0 行永远是主进度行（窄屏只留它）。
func progress_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	match status:
		STATUS_IN_PROGRESS:
			lines.append(_active_loop_line())
			lines.append("Level %d  ·  XP %d / %d" % [level, xp, xp_to_next])
			lines.append("Gold %d" % gold)
			lines.append("Score %s" % format_score(score))
		STATUS_CLEARED:
			lines.append(_cleared_loop_line())
			lines.append("Best Score %s" % format_score(best_score))
		STATUS_FAILED:
			lines.append("Failed at loop %d" % loop_index)
			lines.append("Best Score %s" % format_score(best_score))
		_:
			lines.append("Not started")
			lines.append("Loop goal %s" % loop_goal_text())
	return lines


func time_label() -> String:
	match status:
		STATUS_IN_PROGRESS:
			return "Updated %s" % _relative_time(updated_at)
		STATUS_CLEARED:
			return "Completed %s" % _relative_time(last_history_at if last_history_at > 0 else updated_at)
		STATUS_FAILED:
			return "Failed %s" % _relative_time(last_history_at if last_history_at > 0 else updated_at)
		_:
			return "Created %s" % _relative_time(created_at)


func rail_title() -> String:
	if RAIL_TEXT.has(status):
		return String(RAIL_TEXT[status])
	return String(RAIL_TEXT[STATUS_NEW])


## Home / Play 的 Continue 指标区第二行：一句简单描述，跟 SOLO / MULTIPLAYER 同款，
## 不带 Loop / Score / Best 这些具体数字（§6）。
func rail_caption() -> String:
	if RAIL_CAPTION.has(status):
		return String(RAIL_CAPTION[status])
	return String(RAIL_CAPTION[STATUS_NEW])


## 点开 ACTIVE 存档后的详情（§4）。
func detail_rows() -> Array[Dictionary]:
	return [
		{"label": "SAVE NAME", "value": display_name},
		{"label": "STATUS", "value": status_label_text()},
		{"label": "ARENA", "value": arena_label},
		{"label": "CHARACTER", "value": character_label},
		{"label": "LOOP", "value": loop_cell()},
		{"label": "LEVEL", "value": str(level)},
		{"label": "XP", "value": "%d / %d" % [xp, xp_to_next]},
		{"label": "GOLD", "value": str(gold)},
		{"label": "SCORE", "value": format_score(score)},
		{"label": "LAST SAVED", "value": last_saved_label()},
		{"label": "BEST SCORE", "value": format_score(best_score)},
		{"label": "LAST RESULT", "value": last_result_label()},
	]


func delete_progress_line() -> String:
	return "  ·  ".join(progress_lines())


func delete_history_line() -> String:
	if history_count <= 0:
		return "No runs yet"
	return "%d run%s  ·  Best %s" % [history_count, "" if history_count == 1 else "s", format_score(best_score)]


func last_result_label() -> String:
	if last_result.is_empty():
		return "—"
	if RESULT_TEXT.has(last_result):
		return String(RESULT_TEXT[last_result])
	return last_result.to_upper()


func cleared_loop() -> int:
	return maxi(loop_index, loop_goal)


func loop_cell() -> String:
	if loop_goal > 0:
		return "%d / %d" % [loop_index, loop_goal]
	return str(loop_index)


func is_same_run(other: SaveUiProjection) -> bool:
	if other == null:
		return false
	return slot_id == other.slot_id and status == other.status


# ---- 内部 ----

func _active_loop_line() -> String:
	if loop_goal > 0:
		return "Loop %d / %d" % [loop_index, loop_goal]
	return "Loop %d" % loop_index


func _cleared_loop_line() -> String:
	if loop_goal > 0:
		var cleared: int = cleared_loop()
		return "%d / %d loops" % [cleared, cleared]
	return "Cleared loop %d" % loop_index


func last_saved_label() -> String:
	if last_saved_at <= 0:
		return "—"
	return _relative_time(last_saved_at)


static func _relative_time(at: int) -> String:
	if at <= 0:
		return "just now"
	var now: int = int(Time.get_unix_time_from_system())
	var delta: int = now - at
	if delta < 0:
		delta = 0
	if delta < 60:
		return "just now"
	if delta < 3600:
		return "%dm ago" % (delta / 60)
	if delta < 86400:
		return "%dh ago" % (delta / 3600)
	return "%dd ago" % (delta / 86400)


static func _is_recent_first(left: SaveSlot, right: SaveSlot) -> bool:
	if left == null:
		return false
	if right == null:
		return true
	if left.updated_at == right.updated_at:
		return left.created_at > right.created_at
	return left.updated_at > right.updated_at


static func _label_for_character(character_id: String) -> String:
	var def: CharacterDef = CHARACTER_CATALOG.get_by_id(StringName(character_id))
	if def != null and not def.display_name.is_empty():
		return def.display_name
	return character_id


static func _label_for_arena(arena_id: String) -> String:
	var def: ArenaDef = ARENA_CATALOG.get_by_id(StringName(arena_id))
	if def != null and not def.display_name.is_empty():
		return def.display_name
	return arena_id
