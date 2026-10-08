extends SceneTree

## WAN / P2P 完整闭环 E2E —— Guest 端真进程（由 tools/e2e/p2p_wan_battle/run.py 拉起）。
##
## Guest 的唯一生产入口是 LobbyManager.join_invite(raw_uri)（经 LanOverlay 的 JOIN 页）。
## 它必须真实经过 rendezvous -> hole punch -> direct ENet -> protocol 6 -> seat=2，
## 然后 READY -> Host START -> 进 Battle -> 退回菜单无残留。
##
## 用法：godot --headless --path . --script res://tools/e2e/p2p_wan_battle/guest.gd
##       环境变量：INVITE_FILE / RESULT_FILE / READY_FILE（READY_FILE 只是 Guest 自检用）

const TIMEOUT_MS: int = 50000
const SANDBOX_MARKER: String = "CombatSandbox"
const MENU_MARKER: String = "MainMenu"
const SETTLE_MS: int = 1200

var _invite_file: String = ""
var _result_file: String = ""
var _ready_file: String = ""

var _menu: Node = null
var _overlay: LanOverlay = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _phase: int = 0
var _saw_starting: bool = false
var _sandbox_at: int = -1

func _initialize() -> void:
	_invite_file = _env("INVITE_FILE", "")
	_result_file = _env("RESULT_FILE", "")
	_ready_file = _env("READY_FILE", "")
	if _invite_file.is_empty() or _result_file.is_empty():
		printerr("WAN_GUEST_FAIL: 缺少环境变量")
		quit(1)
		return
	_run.call_deferred()

func _env(name: String, fallback: String) -> String:
	var value: String = OS.get_environment(name)
	return fallback if value.is_empty() else value

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
	if not _overlay.start_lan.is_connected(_menu._enter_lan):
		_fail("MainMenu 没把 start_lan 接到 _enter_lan")
		return
	if not _manager.match_started.is_connected(_overlay._on_lobby_match_started):
		_fail("LanOverlay 没把 match_started 接到 _on_lobby_match_started")
		return
	var uri: String = _wait_for_invite()
	if uri.is_empty():
		_fail("读不到 Host P2P invite")
		return
	if not JoinInvite.parse(uri).is_p2p():
		_fail("Host invite 不是 P2P")
		return
	## 唯一生产入口：JOIN 页粘 URI -> CONNECT -> LobbyManager.join_invite(raw)。
	_overlay.open()
	_overlay._enter_join()
	_overlay._join_edit.text = uri
	_overlay._connect_button.pressed.emit()
	_wait()

## Host 写、Guest 读的 P2P invite 文件。
func _wait_for_invite() -> String:
	for _attempt: int in 200:
		if FileAccess.file_exists(_invite_file):
			var file: FileAccess = FileAccess.open(_invite_file, FileAccess.READ)
			if file != null:
				var text: String = file.get_as_text().strip_edges()
				file.close()
				if not text.is_empty():
					return text
		OS.delay_msec(50)
	return ""

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_done = true
			_write_result("OK scene=%s peer=released seat=2 cleanup=ok" % SANDBOX_MARKER)
			print("WAN_GUEST_OK")
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（phase=%d scene=%s starting=%s | %s）" % [_phase, _scene_name(), _saw_starting, _diag()])
		return
	create_timer(0.05).timeout.connect(_wait)

func _diag() -> String:
	if not is_instance_valid(_manager):
		return "manager=gone"
	var p2p: P2PConnection = _manager.get_p2p_connection()
	var p2p_state: String = "null" if p2p == null else P2PConnectionState.state_name(p2p.get_state_value())
	var room: Room = _manager.get_room()
	var room_state: String = "null" if room == null else str(room.room_state)
	var seat: int = -1 if not is_instance_valid(_manager) else _manager.get_local_seat()
	return "p2p=%s net=%s room=%s seat=%d term=%s" % [
		p2p_state, str(_manager.is_networked()), room_state, seat, _manager.get_terminal_failure()
	]

func _tick() -> bool:
	match _phase:
		0:
			return _tick_join()
		1:
			return _tick_ready()
		2:
			return _tick_wait_start()
		3:
			return _tick_lan_preserved()
		4:
			return _tick_cleanup()
	return false

func _lobby_alive() -> bool:
	return is_instance_valid(_manager) and is_instance_valid(_overlay)

func _tick_join() -> bool:
	if not _lobby_alive():
		return false
	var room: Room = _manager.get_room()
	## P2P 全程：rendezvous 注册 -> candidates -> hole punch -> direct ENet -> seat 2。
	if room == null or _manager.get_local_seat() <= 1:
		return false
	if not _overlay.is_open() or _overlay._view != LanOverlay.View.LOBBY:
		return false
	_phase = 1
	return false

func _tick_ready() -> bool:
	if not _lobby_alive():
		return false
	_overlay._on_lobby_ready_pressed()
	_phase = 2
	return false

func _tick_wait_start() -> bool:
	if _scene_name() == SANDBOX_MARKER:
		_phase = 3
		return false
	if not _lobby_alive():
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
	## 等 Host 先宣布「已在 Battle 站稳」（host.result.battle）。Host 只要还有活跃 peer
	## 就仍持有房；Guest 先退会触发 Host 的 _on_peer_lost -> 降级 Solo（peer 被清空）。
	if not FileAccess.file_exists(_host_battle_marker()):
		return false
	var sandbox: Node = current_scene
	if not _has_live_peer():
		_fail("进 CombatSandbox 后没有活的 multiplayer_peer（换场把 P2P 连接掐断了）")
		return false
	if int(sandbox.get("_net_role")) != int(GameLaunch.NetRole.GUEST):
		_fail("Guest 换场后 role 不是 GUEST（%s）" % str(sandbox.get("_net_role")))
		return false
	if int(sandbox.get("_local_seat")) != 2:
		_fail("Guest 换场后座位不是 2（%s）" % str(sandbox.get("_local_seat")))
		return false
	## 通知 Host：Guest 已在 Battle 站稳，可以开始退回菜单（避免 Host 先关 peer）。
	_write_result("OK scene=%s peer=live seat=2" % SANDBOX_MARKER, ".battle")
	sandbox.call("_return_to_menu")
	_phase = 4
	return false

func _tick_cleanup() -> bool:
	if _scene_name() != MENU_MARKER:
		return false
	if not _has_no_network_peer():
		_fail("退回菜单后仍有活的 multiplayer_peer（残留 peer）")
		return false
	return true

## Godot 启动时 multiplayer_peer 默认是 OfflineMultiplayerPeer（非 null）。
## 「有没有真正的网络 peer」必须排除它。
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

## Host 写、Guest 读的「Host 已在 Battle 站稳」标记。
func _host_battle_marker() -> String:
	return _result_file.replace("guest.result", "host.result") + ".battle"

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
	printerr("WAN_GUEST_FAIL: %s" % reason)
	quit(1)

func _write_result(text: String, suffix: String = "") -> void:
	var file: FileAccess = FileAccess.open(_result_file + suffix, FileAccess.WRITE)
	if file == null:
		printerr("WAN_GUEST_FAIL: 无法写结果文件 %s" % _result_file)
		return
	file.store_string(text)
	file.close()
