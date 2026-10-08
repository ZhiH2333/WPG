extends SceneTree

## 失败清理 / 重建 Lobby 真进程 E2E —— Host 端（由 tools/e2e/lobby_recovery/run.py 拉起）。
##
## 复现并验证：错误 ticket 的 Guest 被拒后，Host 不残留半连接状态，
## 可以 close_network() 后**重新建房**（换新 invite），并正常接受正确的 Guest 进 Battle。
##
## 用法：godot --headless --path . --script res://tools/e2e/lobby_recovery/host.gd -- <result_file>

const TIMEOUT_MS: int = 50000
const SANDBOX_MARKER: String = "CombatSandbox"
const MENU_MARKER: String = "MainMenu"
const SETTLE_MS: int = 1200

var _result_path: String = ""
var _menu: Node = null
var _overlay: LanOverlay = null
var _manager: LobbyManager = null
var _net: LobbyNet = null
var _done: bool = false
var _deadline: int = 0
var _phase: int = 0
var _saw_reject: bool = false
var _recreated: bool = false
var _started: bool = false
var _sandbox_at: int = -1

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		printerr("RECOVERY_HOST_FAIL: 缺少 result_file")
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
	_net = _menu.get_node_or_null("LobbyNet") as LobbyNet
	if _manager == null or _overlay == null or _net == null:
		_fail("主菜单缺 LobbyManager / LanOverlay / LobbyNet")
		return
	_net.peer_rejected.connect(_on_peer_rejected)
	_overlay.open()
	overlay_host()
	_write_marker(_result_path + ".invite", _make_invite_uri())
	_write_marker(_result_path + ".ready", "ready")
	_wait()

func overlay_host() -> void:
	if not _manager.host_room("yard", GameLaunch.NetPlay.COOP, 20):
		_fail("host_room 失败（17777 被占？）")
		return

func _make_invite_uri() -> String:
	return _manager.create_invite("127.0.0.1", GameLaunch.NET_PORT).to_uri()

func _on_peer_rejected(_peer_id: int, _reason: int) -> void:
	_saw_reject = true

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_done = true
			_write_result("OK rejected=1 recreated=1 scene=%s peer=released seat=1 cleanup=ok" % SANDBOX_MARKER)
			print("RECOVERY_HOST_OK")
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（phase=%d reject=%s recreated=%s started=%s scene=%s）" % [
			_phase, _saw_reject, _recreated, _started, _scene_name()
		])
		return
	create_timer(0.05).timeout.connect(_wait)

func _tick() -> bool:
	match _phase:
		0:
			return _tick_wait_reject()
		1:
			return _tick_wait_guest()
		2:
			return _tick_lan_preserved()
		3:
			return _tick_wait_guest_ready()
		4:
			return _tick_cleanup()
	return false

## phase 0：等错误 ticket 的 Guest 被拒 -> Host 必须能干净重建 Lobby。
func _tick_wait_reject() -> bool:
	if not _saw_reject:
		return false
	## 拒绝后 Host 仍端着 ENet server（拒绝一个坏 Guest 不影响房间）。
	if not _has_live_peer():
		_fail("拒绝坏 Guest 后 Host 的 ENet server 掉了")
		return false
	_manager.close_network()
	if _has_live_peer():
		_fail("close_network 后仍有活的 multiplayer peer")
		return false
	## 重建 Lobby：换新房间（新 room_id / invite），必须成功、无端口残留。
	if not _manager.host_room("yard", GameLaunch.NetPlay.COOP, 20):
		_fail("重建 Lobby 失败（端口/状态残留？）")
		return false
	if not _has_live_peer():
		_fail("重建 Lobby 后没有活的 ENet server")
		return false
	_recreated = true
	_write_marker(_result_path + ".invite2", _make_invite_uri())
	_write_marker(_result_path + ".recreated", "ready")
	_phase = 1
	return false

## phase 1：等正确 Guest 进房 READY，然后 START。
func _tick_wait_guest() -> bool:
	var room: Room = _manager.get_room()
	if room == null or room.player_count() != 2:
		return false
	var guest: LobbyPlayer = room.get_player_in_seat(2)
	if guest == null or not guest.ready:
		return false
	if not _manager.can_start():
		return false
	_started = true
	_overlay._on_start_pressed()
	_phase = 2
	return false

## phase 2：换场后 peer 必须活着（交接合同）。
func _tick_lan_preserved() -> bool:
	if _scene_name() != SANDBOX_MARKER:
		return false
	if _sandbox_at < 0:
		_sandbox_at = Time.get_ticks_msec()
		return false
	if Time.get_ticks_msec() - _sandbox_at < SETTLE_MS:
		return false
	var sandbox: Node = current_scene
	if not _has_live_peer():
		_fail("进 CombatSandbox 后没有活的 multiplayer_peer")
		return false
	if int(sandbox.get("_local_seat")) != Room.HOST_SEAT:
		_fail("Host 座位不是 1（%s）" % str(sandbox.get("_local_seat")))
		return false
	_write_marker(_result_path + ".battle", "OK")
	_phase = 3
	return false

func _tick_wait_guest_ready() -> bool:
	if not FileAccess.file_exists(_guest_battle_marker()):
		return false
	var sandbox: Node = current_scene
	if sandbox != null and sandbox.name == SANDBOX_MARKER:
		sandbox.call("_return_to_menu")
	_phase = 4
	return false

func _tick_cleanup() -> bool:
	if _scene_name() != MENU_MARKER:
		return false
	if not _has_no_network_peer():
		_fail("退回菜单后仍有活的 multiplayer peer")
		return false
	return true

func _guest_battle_marker() -> String:
	return _result_path.replace("host.result", "guest.result") + ".battle"

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
	printerr("RECOVERY_HOST_FAIL: %s" % reason)
	quit(1)

func _write_result(text: String) -> void:
	_write_marker(_result_path, text)

func _write_marker(path: String, text: String = "ready") -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("RECOVERY_HOST_FAIL: 无法写 %s" % path)
		return
	file.store_string(text)
	file.close()
