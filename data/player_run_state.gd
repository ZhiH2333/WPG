extends RefCounted
class_name PlayerRunState

## 一个玩家在一局里的独立运行状态。以后多人系统的核心数据结构。
## 纯数据：不碰 SceneTree / UI / FileAccess / ENet / MultiplayerPeer，可 headless 单测。
##
## 身份合同（硬约束）：
## - profile_id 是**持久身份**，重连、换座位都必须靠它找回自己那份状态。
## - seat 只是运行中的座位号，会变。
## - peer_id **不得**进入持久化 contract：peer 不是稳定身份，Guest 重连后 peer_id 会变。
##   to_dictionary 从不写 peer_id；from_dictionary 显式忽略任何 peer_id 字段。
const CHARACTER_BOAR := "boar"
const CHARACTER_CHICKEN := "chicken"
const CHARACTER_IDS: PackedStringArray = [CHARACTER_BOAR, CHARACTER_CHICKEN]

var profile_id: String = ""
var display_name: String = ""
var character_id: String = CHARACTER_BOAR
## 运行中的座位（1..NET_MAX_SEATS）。不是身份。
var seat: int = 1
var hp: int = 100
var max_hp: int = 100
var level: int = 1
var xp: int = 0
var pending_level: int = 0
var gold: int = 0
## 最近一次算出来的分数（RunResult 写入）。不是 best_score。
var score: int = 0
var kill_count: int = 0
## 本玩家单独持有的升级 id。不是全局字段。
var owned_upgrade_ids: Array[String] = []
## 未来的物品 / 跟班序列化占位：本阶段只保留结构，不做复杂内容。
var inventory: Array[Dictionary] = []
var companions: Array[Dictionary] = []
var alive: bool = true
var eliminated: bool = false
## 等待该玩家做的决策（"" = 没有挂起决策）。例如 "pick_upgrade" / "shop"。
var pending_decision: String = ""

## 深拷贝（走 JSON 同一条路径，保证「能存就能拷」）。
func duplicate_state() -> PlayerRunState:
	return PlayerRunState.from_dictionary(to_dictionary())

static func create(profile_id: String, display_name: String, character_id: String, seat: int = 1) -> PlayerRunState:
	var state: PlayerRunState = PlayerRunState.new()
	state.profile_id = profile_id
	state.display_name = display_name
	state.character_id = sanitize_character_id(character_id)
	state.seat = clampi(seat, 1, 5)
	return state

func has_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in owned_upgrade_ids

func add_upgrade(upgrade_id: String) -> void:
	## 允许重复：可堆叠升级要靠出现次数算层数，去重会破坏 stack 计数。
	if upgrade_id.is_empty():
		return
	owned_upgrade_ids.append(upgrade_id)

func clear_pending_decision() -> void:
	pending_decision = ""

func to_dictionary() -> Dictionary:
	## 注意：这里**没有** peer_id。它永远不进 JSON。
	return {
		"profile_id": profile_id,
		"display_name": display_name,
		"character_id": character_id,
		"seat": seat,
		"hp": hp,
		"max_hp": max_hp,
		"level": level,
		"xp": xp,
		"pending_level": pending_level,
		"gold": gold,
		"score": score,
		"kill_count": kill_count,
		"owned_upgrade_ids": owned_upgrade_ids.duplicate(),
		"inventory": _duplicate_dicts(inventory),
		"companions": _duplicate_dicts(companions),
		"alive": alive,
		"eliminated": eliminated,
		"pending_decision": pending_decision,
	}

static func from_dictionary(data: Dictionary) -> PlayerRunState:
	var state: PlayerRunState = PlayerRunState.new()
	## peer_id 不是持久身份：即使有人往 JSON 里塞了 peer_id 也绝不采纳。
	state.profile_id = str(data.get("profile_id", ""))
	state.display_name = sanitize_display_name(str(data.get("display_name", "")))
	state.character_id = sanitize_character_id(str(data.get("character_id", CHARACTER_BOAR)))
	state.seat = clampi(int(data.get("seat", 1)), 1, 5)
	state.max_hp = maxi(int(data.get("max_hp", 100)), 1)
	state.hp = clampi(int(data.get("hp", state.max_hp)), 0, state.max_hp)
	state.level = maxi(int(data.get("level", 1)), 1)
	state.xp = maxi(int(data.get("xp", 0)), 0)
	state.pending_level = maxi(int(data.get("pending_level", 0)), 0)
	state.gold = maxi(int(data.get("gold", 0)), 0)
	state.score = maxi(int(data.get("score", 0)), 0)
	state.kill_count = maxi(int(data.get("kill_count", 0)), 0)
	state.owned_upgrade_ids = _parse_ids(data.get("owned_upgrade_ids", []))
	state.inventory = _parse_dicts(data.get("inventory", []))
	state.companions = _parse_dicts(data.get("companions", []))
	state.alive = bool(data.get("alive", true))
	state.eliminated = bool(data.get("eliminated", false))
	if state.eliminated:
		state.alive = false
	state.pending_decision = sanitize_pending_decision(str(data.get("pending_decision", "")))
	return state

static func sanitize_character_id(value: String) -> String:
	if value in CHARACTER_IDS:
		return value
	return CHARACTER_BOAR

static func sanitize_display_name(value: String) -> String:
	var visible: String = ""
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if code < 32 or code == 127:
			continue
		visible += value[index]
	return visible.strip_edges()

static func sanitize_pending_decision(value: String) -> String:
	var cleaned: String = sanitize_display_name(value)
	return cleaned.substr(0, 32)

static func _parse_ids(raw: Variant) -> Array[String]:
	var ids: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return ids
	for item: Variant in raw as Array:
		var text: String = str(item)
		## 保留重复项：stackable 升级按出现次数计层。
		if text.is_empty():
			continue
		ids.append(text)
	return ids

static func _parse_dicts(raw: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return rows
	for item: Variant in raw as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		rows.append((item as Dictionary).duplicate(true))
	return rows

static func _duplicate_dicts(rows: Array[Dictionary]) -> Array:
	var copy: Array = []
	for row: Dictionary in rows:
		copy.append(row.duplicate(true))
	return copy
