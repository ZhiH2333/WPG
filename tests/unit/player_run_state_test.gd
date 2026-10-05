extends SceneTree

## PlayerRunState 回归：round trip / profile_id 是持久身份 / peer_id 永不落盘 /
## stackable 升级不去重 / 物品与跟班占位结构。
## 跑法：godot --headless --path . --script res://tests/unit/player_run_state_test.gd
## 通过输出 PLAYER_RUN_STATE_OK；失败逐条 PLAYER_RUN_STATE_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_round_trip()
	_case_profile_id_preserved()
	_case_peer_id_never_persisted()
	_case_stackable_duplicates_preserved()
	_case_inventory_and_companions_round_trip()
	_case_invalid_data_sanitized()
	_case_is_pure_data()
	if _failures.is_empty():
		print("PLAYER_RUN_STATE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("PLAYER_RUN_STATE_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _full_state() -> PlayerRunState:
	var state: PlayerRunState = PlayerRunState.create("pf-1234567890", "Evan", "chicken", 3)
	state.hp = 55
	state.max_hp = 175
	state.level = 12
	state.xp = 8
	state.pending_level = 1
	state.gold = 999
	state.score = 4321
	state.kill_count = 777
	state.owned_upgrade_ids = ["swift", "swift", "thick_hide"]
	state.alive = true
	state.eliminated = false
	state.pending_decision = "pick_upgrade"
	return state

## 1) PlayerRunState round trip。
func _case_round_trip() -> void:
	var state: PlayerRunState = _full_state()
	var restored: PlayerRunState = PlayerRunState.from_dictionary(state.to_dictionary())
	_expect(restored.profile_id == "pf-1234567890", "profile_id round trip")
	_expect(restored.display_name == "Evan", "display_name round trip")
	_expect(restored.character_id == "chicken", "character_id round trip")
	_expect(restored.seat == 3, "seat round trip")
	_expect(restored.hp == 55 and restored.max_hp == 175, "hp / max_hp round trip")
	_expect(restored.level == 12 and restored.xp == 8, "level / xp round trip")
	_expect(restored.pending_level == 1, "pending_level round trip")
	_expect(restored.gold == 999, "gold round trip")
	_expect(restored.score == 4321, "score round trip")
	_expect(restored.kill_count == 777, "kill_count round trip")
	_expect(restored.alive and not restored.eliminated, "alive / eliminated round trip")
	_expect(restored.pending_decision == "pick_upgrade", "pending_decision round trip")
	_expect(restored.owned_upgrade_ids.size() == 3, "owned_upgrade_ids round trip")

## 11) profile_id 是持久身份：Guest 重连靠它找回旧状态，绝不能丢。
func _case_profile_id_preserved() -> void:
	var state: PlayerRunState = _full_state()
	for _i: int in 3:
		state = PlayerRunState.from_dictionary(state.to_dictionary())
	_expect(state.profile_id == "pf-1234567890", "多轮 round trip 后 profile_id 不变")
	_expect(not state.profile_id.is_empty(), "profile_id 不为空")
	var seat_changed: PlayerRunState = PlayerRunState.from_dictionary(state.to_dictionary())
	seat_changed.seat = 5
	_expect(PlayerRunState.from_dictionary(seat_changed.to_dictionary()).profile_id == state.profile_id, "换 seat 不改 profile_id")

## 12) peer_id 不是稳定身份：序列化里永远不出现。
func _case_peer_id_never_persisted() -> void:
	var state: PlayerRunState = _full_state()
	var payload: Dictionary = state.to_dictionary()
	_expect(not payload.has("peer_id"), "to_dictionary 不含 peer_id")
	var text: String = JSON.stringify(payload)
	_expect(not text.contains("peer_id"), "JSON 文本不含 peer_id")
	var injected: Dictionary = payload.duplicate(true)
	injected["peer_id"] = 424242
	var restored: PlayerRunState = PlayerRunState.from_dictionary(injected)
	_expect(not restored.to_dictionary().has("peer_id"), "读入被注入的 peer_id 后仍不写出 peer_id")
	_expect(JSON.stringify(restored.to_dictionary()).find("peer_id") == -1, "往返后 peer_id 仍不进 JSON")

## 可堆叠升级按出现次数计层，去重会破坏 stack 计数。
func _case_stackable_duplicates_preserved() -> void:
	var state: PlayerRunState = PlayerRunState.create("pf-1", "A", "boar", 1)
	state.add_upgrade("cadence")
	state.add_upgrade("cadence")
	state.add_upgrade("swift")
	_expect(state.owned_upgrade_ids.size() == 3, "add_upgrade 允许重复")
	_expect(state.has_upgrade("cadence"), "has_upgrade 能看到堆叠升级")
	var restored: PlayerRunState = PlayerRunState.from_dictionary(state.to_dictionary())
	_expect(restored.owned_upgrade_ids.size() == 3, "round trip 保留重复升级 id")
	var duplicates: int = 0
	for id: String in restored.owned_upgrade_ids:
		if id == "cadence":
			duplicates += 1
	_expect(duplicates == 2, "cadence 仍是 2 层")

## inventory / companions 本阶段只是结构占位，但必须能原样进出 JSON。
func _case_inventory_and_companions_round_trip() -> void:
	var state: PlayerRunState = _full_state()
	state.inventory.append({"id": "potion", "count": 2})
	state.companions.append({"id": "gunner", "hp": 30})
	var restored: PlayerRunState = PlayerRunState.from_dictionary(state.to_dictionary())
	_expect(restored.inventory.size() == 1, "inventory round trip")
	_expect(restored.companions.size() == 1, "companions round trip")
	if restored.inventory.size() == 1:
		_expect(str(restored.inventory[0].get("id")) == "potion", "inventory 内容 round trip")
		_expect(int(restored.inventory[0].get("count")) == 2, "inventory 数量 round trip")
	if restored.companions.size() == 1:
		_expect(str(restored.companions[0].get("id")) == "gunner", "companions 内容 round trip")

## 6) invalid data sanitization。
func _case_invalid_data_sanitized() -> void:
	var restored: PlayerRunState = PlayerRunState.from_dictionary({
		"profile_id": "pf-x",
		"display_name": "Ev\u0007an\n",
		"character_id": "dragon",
		"seat": 99,
		"hp": 9999,
		"max_hp": 0,
		"level": 0,
		"xp": -5,
		"pending_level": -1,
		"gold": -100,
		"kill_count": -3,
		"owned_upgrade_ids": "not-an-array",
		"inventory": "not-an-array",
		"companions": [1, "x"],
		"eliminated": true,
		"pending_decision": "x".repeat(100),
	})
	_expect(restored.character_id == PlayerRunState.CHARACTER_BOAR, "非法 character 打回 boar")
	_expect(restored.seat == 5, "seat 夹到 1..5")
	_expect(restored.max_hp == 1, "max_hp 至少 1")
	_expect(restored.hp <= restored.max_hp, "hp 不超过 max_hp")
	_expect(restored.level >= 1, "level 至少 1")
	_expect(restored.xp == 0, "负 xp 打回 0")
	_expect(restored.pending_level == 0, "负 pending_level 打回 0")
	_expect(restored.gold == 0, "负 gold 打回 0")
	_expect(restored.kill_count == 0, "负 kills 打回 0")
	_expect(restored.owned_upgrade_ids.is_empty(), "错类型 owned 列表回退空")
	_expect(restored.inventory.is_empty(), "错类型 inventory 回退空")
	_expect(restored.companions.is_empty(), "非字典 companions 被丢弃")
	_expect(restored.eliminated and not restored.alive, "eliminated 强制 alive=false")
	_expect(restored.pending_decision.length() <= 32, "pending_decision 被截断")
	_expect(not restored.display_name.contains("\n"), "display_name 去掉控制字符")

## 纯数据：不依赖 SceneTree / UI。
func _case_is_pure_data() -> void:
	var obj: Variant = _full_state()
	_expect(not (obj is Node), "PlayerRunState 不是 Node")
	_expect(not (obj is SceneTree), "PlayerRunState 不是 SceneTree")
	_expect(obj is RefCounted, "PlayerRunState 是 RefCounted")
