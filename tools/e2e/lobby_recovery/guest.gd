extends SceneTree

## 失败清理 / 重建 Lobby 真进程 E2E —— Guest 端（由 tools/e2e/lobby_recovery/run.py 拉起）。
##
## 同一个 Guest 进程先做两件事：
##   1. 用**被篡改 ticket** 的 invite 去连 Host -> 必须被拒、必须把 peer 清干净；
##   2. Host 重建 Lobby 后，用**正确** invite 再连 -> 落座 seat 2 -> READY -> 进 Battle。
## 这样才证明「一次失败之后还能重新加入」，而不是把失败残骸留在进程里。
##
## 用法：godot --headless --path . --script res://tools/e2e/lobby_recovery/guest.gd -- <result_file>

const TIMEOUT_MS: int = 50000
const SANDBOX_MARKER: String = "CombatSandbox"
const MENU_MARKER: String = "MainMenu"
const SETTLE_MS: int = 1200

var _result_path: String = ""
var _menu: Node = null
var _overlay: LanOverlay = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _phase: int = 0
var _saw_failure: bool = false
var _failure_reason: String = ""
var _saw_starting: bool = false
var _sandbox_at: int = -1

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		printerr("RECOVERY_GUEST_FAIL: 缺少 result_file")
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
	_overlay = _menu.get_node_or_null("LanOverlay") as LanOverlay
	if _manager == null or _overlay == null:
		_fail("主菜单缺 LobbyManager / LanOverlay")
		return
	## 失败必须经由 UI 可观测的通道报告（network_failed），不依赖内部 latch：
	## 「错误 ticket」在生产里可能表现为 ticket rejected，也可能（Host 先踢连接再送 RPC）
	## 表现为 host closed —— 两者都必须让 UI 收到失败，否则就是「吞了错误状态」。
	_manager.network_failed.connect(_on_network_failed)
	var real: String = _read_marker(_result_path.replace("guest.result", "host.result") + ".invite")
	if real.is_empty():
		_fail("读不到 Host invite")
		return
	var tampered: String = _tamper(real)
	if tampered == real or tampered.is_empty():
		_fail("无法篡改 ticket（本用例前提）")
		return
	## 失败尝试：错误 ticket。走真 UI JOIN 路径。
	_overlay.open()
	_overlay._enter_join()
	_overlay._join_edit.text = tampered
	_overlay._connect_button.pressed.emit()
	_wait()

## 只改 ticket 的第一个字符：长度不变、内容不同，必然是 BAD_TOKEN。
func _tamper(uri: String) -> String:
	var invite: JoinInvite = JoinInvite.parse(uri)
	if invite == null or invite.token.is_empty():
		return ""
	var token: String = invite.token
	var first: String = token.substr(0, 1)
	var replacement: String = "0" if first != "0" else "1"
	invite.token = replacement + token.substr(1)
	return invite.to_uri()

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_done = true
			_write_result("OK failed_clean=1 rejoined=1 scene=%s peer=released seat=2 cleanup=ok" % SANDBOX_MARKER)
			print("RECOVERY_GUEST_OK")
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（phase=%d failure=%s scene=%s starting=%s）" % [
			_phase, _saw_failure, _scene_name(), _saw_starting
		])
		return
	create_timer(0.05).timeout.connect(_wait)

func _tick() -> bool:
	match _phase:
		0:
			return _tick_wait_failure()
		1:
			return _tick_rejoin()
		2:
			return _tick_ready()
		3:
			return _tick_wait_start()
		4:
			return _tick_lan_preserved()
		5:
			return _tick_cleanup()
	return false

## phase 0：等被拒 -> 断言 peer 已清干净 -> 标记 bad_done，等 Host 重建后的新 invite。
func _tick_wait_failure() -> bool:
	if not is_instance_valid(_manager):
		return false
	if not _saw_failure:
		return false
	if _has_live_peer():
		_fail("被拒后仍有活的 multiplayer peer（失败未清理）")
		return false
	if _manager.get_p2p_connection() != null:
		_fail("被拒后仍持有 P2PConnection")
		return false
	_write_marker(_result_path + ".bad_done", "rejected=%s" % _failure_reason)
	_phase = 1
	return false

func _on_network_failed(reason: String) -> void:
	if _saw_failure:
		return
	_saw_failure = true
	_failure_reason = reason

## phase 1：读 Host 重建 Lobby 后的新 invite，再次走真 UI 连接。
func _tick_rejoin() -> bool:
	if not is_instance_valid(_manager) or not is_instance_valid(_overlay):
		return false
	var real2: String = _try_read_marker(_result_path.replace("guest.result", "host.result") + ".invite2")
	if real2.is_empty():
		return false
	_overlay._enter_join()
	_overlay._join_edit.text = real2
	_overlay._connect_button.pressed.emit()
	_phase = 2
	return false

func _tick_ready() -> bool:
	if not is_instance_valid(_manager) or not is_instance_valid(_overlay):
		return false
	var room: Room = _manager.get_room()
	if room == null or _manager.get_local_seat() <= 1:
		return false
	if not _overlay.is_open() or _overlay._view != LanOverlay.View.LOBBY:
		return false
	_overlay._on_lobby_ready_pressed()
	_phase = 3
	return false

func _tick_wait_start() -> bool:
	if _scene_name() == SANDBOX_MARKER:
		_phase = 4
		return false
	if not is_instance_valid(_manager):
		return false
	var room: Room = _manager.get_room()
	if room != null and room.room_state == Room.RoomState.STARTING:
		_saw_starting = true
	return false

func _tick_lan_preserved() -> bool:
	if _scene_name() != SANDBOX_MARKER:
		return false
	if _sandbox_at < 0:
		_sandbox_at = Time.get_ticks_msec()
		return false
	if Time.get_ticks_msec() - _sandbox_at < SETTLE_MS:
		return false
	if not FileAccess.file_exists(_host_battle_marker()):
		return false
	var sandbox: Node = current_scene
	if not _has_live_peer():
		_fail("重建后进 CombatSandbox 没有活的 multiplayer_peer")
		return false
	if int(sandbox.get("_local_seat")) != 2:
		_fail("重建后 Guest 座位不是 2（%s）" % str(sandbox.get("_local_seat")))
		return false
	_write_marker(_result_path + ".battle", "OK")
	sandbox.call("_return_to_menu")
	_phase = 5
	return false

func _tick_cleanup() -> bool:
	if _scene_name() != MENU_MARKER:
		return false
	if not _has_no_network_peer():
		_fail("退回菜单后仍有活的 multiplayer peer")
		return false
	return true

func _host_battle_marker() -> String:
	return _result_path.replace("guest.result", "host.result") + ".battle"

## Godot 启动时 multiplayer_peer 默认是 OfflineMultiplayerPeer（非 null）。
func _has_live_peer() -> bool:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	## ENet 的「对象还在」不等于「连接还活着」：Host 关服后 Guest 手里的
	## ENetMultiplayerPeer 还在，但状态已经不是 CONNECTED。必须按连接状态判定。
	if peer is ENetMultiplayerPeer:
		return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	return true

func _has_no_network_peer() -> bool:
	return not _has_live_peer()

## 非阻塞读：文件还没就绪就返回 ""，由调用方下一帧再试（不要卡住主循环）。
func _try_read_marker(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text().strip_edges()
	file.close()
	return text

## 轮询读取一个标记文件（Host 写、Guest 读）。
func _read_marker(path: String) -> String:
	for _attempt: int in 200:
		if FileAccess.file_exists(path):
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				var text: String = file.get_as_text().strip_edges()
				file.close()
				if not text.is_empty():
					return text
		if _done:
			return ""
		OS.delay_msec(50)
	return ""

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
	printerr("RECOVERY_GUEST_FAIL: %s" % reason)
	quit(1)

func _write_result(text: String) -> void:
	_write_marker(_result_path, text)

func _write_marker(path: String, text: String = "ready") -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("RECOVERY_GUEST_FAIL: 无法写 %s" % path)
		return
	file.store_string(text)
	file.close()
