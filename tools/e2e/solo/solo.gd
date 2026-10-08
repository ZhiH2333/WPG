extends SceneTree

## Solo 冒烟 E2E —— 单进程真场景（由 tools/e2e/solo/run.py 拉起）。
##
## 覆盖「F5 进 Solo」这条最小闭环：
##   离线建房（LobbyManager.create_room，不 bind 任何端口）-> start_match() 写离线信封
##   -> MainMenu._leave_to_sandbox() 真换场 -> CombatSandbox（role = OFFLINE、无网络 peer）
##   -> _return_to_menu() 退回主菜单 -> 仍无网络 peer。
##
## 用法：godot --headless --path . --script res://tools/e2e/solo/solo.gd -- <result_file>

const TIMEOUT_MS: int = 40000
const SANDBOX_MARKER: String = "CombatSandbox"
const MENU_MARKER: String = "MainMenu"
const SETTLE_MS: int = 800

var _result_path: String = ""
var _menu: Node = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _phase: int = 0
var _sandbox_at: int = -1

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		printerr("SOLO_E2E_FAIL: 缺少 result_file")
		quit(1)
		return
	_result_path = args[0]
	_run.call_deferred()

func _run() -> void:
	PlayerProfile.load_from_disk()
	var packed: PackedScene = load("res://ui/main_menu.tscn") as PackedScene
	if packed == null:
		_fail("main_menu.tscn 加载失败")
		return
	_menu = packed.instantiate()
	root.add_child(_menu)
	current_scene = _menu
	_manager = _menu.get_node_or_null("LobbyManager") as LobbyManager
	if _manager == null:
		_fail("主菜单缺 LobbyManager")
		return
	if _has_live_peer():
		_fail("主菜单打开时就有活的网络 peer")
		return
	## 离线建房：不 bind 端口、不建 peer。
	var room: Room = _manager.create_room("yard", GameLaunch.NetPlay.COOP, 20)
	if room == null:
		_fail("离线建房失败")
		return
	if _manager.get_snapshot().get("networked", false):
		_fail("离线房被标记为 networked")
		return
	if _has_live_peer():
		_fail("离线建房后出现活的网络 peer")
		return
	if not _manager.start_match():
		_fail("离线 start_match 失败")
		return
	if _has_live_peer():
		_fail("离线 start_match 后出现活的网络 peer")
		return
	## 真换场：等价于点 SOLO / CONTINUE 后进沙盒。
	_menu.call("_leave_to_sandbox")
	_wait()

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_done = true
			_write_result("OK offline=1 scene=MainMenu role=OFFLINE no_peer=1 cleanup=ok")
			print("SOLO_E2E_OK")
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（phase=%d scene=%s）" % [_phase, _scene_name()])
		return
	create_timer(0.05).timeout.connect(_wait)

func _tick() -> bool:
	match _phase:
		0:
			return _tick_sandbox()
		1:
			return _tick_cleanup()
	return false

## phase 0：真换场到 CombatSandbox，role = OFFLINE，且没有网络 peer。
func _tick_sandbox() -> bool:
	if _scene_name() != SANDBOX_MARKER:
		if _scene_name() == MENU_MARKER:
			return false
		return false
	if _sandbox_at < 0:
		_sandbox_at = Time.get_ticks_msec()
		return false
	if Time.get_ticks_msec() - _sandbox_at < SETTLE_MS:
		return false
	var sandbox: Node = current_scene
	if int(sandbox.get("_net_role")) != int(GameLaunch.NetRole.OFFLINE):
		_fail("Solo 进沙盒后 role 不是 OFFLINE（%s）" % str(sandbox.get("_net_role")))
		return false
	if _has_live_peer():
		_fail("Solo 进沙盒后出现活的网络 peer")
		return false
	sandbox.call("_return_to_menu")
	_phase = 1
	return false

## phase 1：退回主菜单，且仍然没有网络 peer。
func _tick_cleanup() -> bool:
	if _scene_name() != MENU_MARKER:
		return false
	if _has_live_peer():
		_fail("Solo 退回菜单后仍有活的网络 peer")
		return false
	return true

## Godot 启动时 multiplayer_peer 默认是 OfflineMultiplayerPeer（非 null）；
## Host 关服后 ENet peer 对象也还在。只有 CONNECTED 才算「活的网络 peer」。
func _has_live_peer() -> bool:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	if peer is ENetMultiplayerPeer:
		return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	return true

func _scene_name() -> String:
	var scene: Node = current_scene
	if scene == null:
		return ""
	return scene.name

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_result("FAIL: %s" % reason)
	printerr("SOLO_E2E_FAIL: %s" % reason)
	quit(1)

func _write_result(text: String) -> void:
	var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		printerr("SOLO_E2E_FAIL: 无法写 %s" % _result_path)
		return
	file.store_string(text)
	file.close()
