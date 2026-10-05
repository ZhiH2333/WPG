extends SceneTree

## 跟班上限回归：一局最多 30 只「活着」的 Gunner。
## 覆盖 RunSession 的三条出口（计数钳制 / can_buy_companion 边界 / 货架跟班卡出现时机），
## 再实例化真实 CombatSandbox 验证沙盒的 `_spawn_companion` 闸门确实放到 30。
##
## 跑法：godot --headless --path . --script res://tests/companion_cap_test.gd --quit
## 通过输出 COMPANION_CAP_OK；失败逐条 COMPANION_CAP_FAIL 并返回非 0。

const COMPANION_CATALOG_TRES: String = "res://data/companion_catalog.tres"
const SANDBOX_SCENE: String = "res://sandbox/combat_sandbox.tscn"
## 用户定的数字，故意写死：改这里就说明上限又被调了。
const EXPECTED_CAP: int = 30
## 沙盒 _ready 会真实写 records.json（ensure_playable_slot + RUN_START 检查点），
## 测试跑完必须把用户真档原样放回去。
const SAVE_NAMES: Array[String] = [
	"records.json",
	"records.json.tmp",
	"records.json.bak",
	"records.json.corrupt",
]

var _failures: PackedStringArray = PackedStringArray()
var _save_snapshot: Dictionary = {}

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	_snapshot_saves()

	_case_expected_cap_value()
	_case_count_clamps_to_cap()
	_case_buy_boundary()
	_case_shop_card_until_full()
	await _case_sandbox_allows_cap_living_companions()

	_restore_saves()
	if _failures.is_empty():
		print("COMPANION_CAP_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("COMPANION_CAP_FAIL: %s" % failure)
	quit(1)

## 只把字节抄进内存，绝不删用户文件。
func _snapshot_saves() -> void:
	_save_snapshot.clear()
	for name: String in SAVE_NAMES:
		var path: String = "user://%s" % name
		_save_snapshot[name] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else null

## 把字节写回；测试开始前不存在的文件才删除（只删自己造出来的）。
func _restore_saves() -> void:
	for name: String in _save_snapshot:
		var path: String = "user://%s" % name
		var stored: Variant = _save_snapshot[name]
		if stored == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(str(stored))
		file.flush()
		file.close()
	_save_snapshot.clear()
	GameSaveStore.load_from_disk()

## 常量本身 = 30。
func _case_expected_cap_value() -> void:
	_expect(RunSession.COMPANION_CAP == EXPECTED_CAP, "COMPANION_CAP == %d" % EXPECTED_CAP)

## set_living_companion_count 钳到 [0, cap]，不是直接存原值。
func _case_count_clamps_to_cap() -> void:
	var session: RunSession = RunSession.new()
	session.set_living_companion_count(EXPECTED_CAP)
	_expect(session.get_living_companion_count() == EXPECTED_CAP, "满员计数 = %d" % EXPECTED_CAP)
	session.set_living_companion_count(EXPECTED_CAP + 1)
	_expect(session.get_living_companion_count() == EXPECTED_CAP, "超上限被钳回 %d" % EXPECTED_CAP)
	session.set_living_companion_count(9999)
	_expect(session.get_living_companion_count() == EXPECTED_CAP, "离谱值也钳回 %d" % EXPECTED_CAP)
	session.set_living_companion_count(-5)
	_expect(session.get_living_companion_count() == 0, "负数钳到 0")
	session.free()

## 买跟班的闸门：29 只还能买，满 30 只不能买；0 只时 has_living_companion 为 false。
func _case_buy_boundary() -> void:
	var session: RunSession = RunSession.new()
	session.set_living_companion_count(0)
	_expect(not session.has_living_companion(), "0 只时 has_living_companion = false")
	_expect(session.can_buy_companion(), "0 只时可以买")
	session.set_living_companion_count(EXPECTED_CAP - 1)
	_expect(session.can_buy_companion(), "%d 只时仍可买" % (EXPECTED_CAP - 1))
	session.set_living_companion_count(EXPECTED_CAP)
	_expect(session.has_living_companion(), "满员时 has_living_companion = true")
	_expect(not session.can_buy_companion(), "满 %d 只时不能再买" % EXPECTED_CAP)
	session.free()

## 货架：没满才出 Gunner 跟班卡；满员后那张卡消失。
func _case_shop_card_until_full() -> void:
	var session: RunSession = RunSession.new()
	var catalog: CompanionCatalog = load(COMPANION_CATALOG_TRES) as CompanionCatalog
	_expect(catalog != null, "companion_catalog.tres 可加载")
	session.bind_companion_catalog(catalog)

	session.set_living_companion_count(EXPECTED_CAP - 1)
	_expect(_count_companion_cards(session.list_shop_catalog()) == 1, "%d 只时货架有 Gunner 卡" % (EXPECTED_CAP - 1))

	session.set_living_companion_count(EXPECTED_CAP)
	_expect(_count_companion_cards(session.list_shop_catalog()) == 0, "满 %d 只时货架没有 Gunner 卡" % EXPECTED_CAP)

	## draft_shop_cards 的跟班位同理：满员只出升级，不出跟班。
	session.set_living_companion_count(EXPECTED_CAP - 1)
	_expect(_count_companion_cards(session.draft_shop_cards(3)) == 1, "未满时 draft_shop_cards 含跟班卡")
	session.set_living_companion_count(EXPECTED_CAP)
	_expect(_count_companion_cards(session.draft_shop_cards(3)) == 0, "满员时 draft_shop_cards 不含跟班卡")
	session.free()

## 真实沙盒：连刷 30 只都进得来，第 31 只被闸门拒绝，货架跟班卡随之消失。
func _case_sandbox_allows_cap_living_companions() -> void:
	var scene: PackedScene = load(SANDBOX_SCENE)
	_expect(scene != null, "combat_sandbox.tscn 可加载")
	if scene == null:
		return
	var sandbox: CombatSandbox = scene.instantiate() as CombatSandbox
	_expect(sandbox != null, "CombatSandbox 可实例化")
	if sandbox == null:
		return
	root.add_child(sandbox)
	for _i: int in 3:
		await process_frame

	_expect(sandbox._count_living_companions() == 0, "进场时 0 只跟班")
	for _n: int in EXPECTED_CAP:
		sandbox._spawn_companion(&"gunner", 0)
	await process_frame

	_expect(sandbox._companions.size() == EXPECTED_CAP, "连刷 %d 只都进得来" % EXPECTED_CAP)
	_expect(sandbox._count_living_companions() == EXPECTED_CAP, "活着计数 = %d" % EXPECTED_CAP)
	_expect(not sandbox._run_session.can_buy_companion(), "满员后沙盒不能再买跟班")
	_expect(_count_companion_cards(sandbox._run_session.list_shop_catalog()) == 0, "满员后沙盒货架没有 Gunner 卡")

	## 第 31 只必须被 `_spawn_companion` 自己挡住，不靠调用方自觉。
	sandbox._spawn_companion(&"gunner", 0)
	await process_frame
	_expect(sandbox._companions.size() == EXPECTED_CAP, "第 %d 只被拒绝" % (EXPECTED_CAP + 1))

	sandbox.queue_free()
	await process_frame

func _count_companion_cards(cards: Array[ShopCard]) -> int:
	var n: int = 0
	for card: ShopCard in cards:
		if card != null and card.kind == ShopCard.Kind.COMPANION:
			n += 1
	return n

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
