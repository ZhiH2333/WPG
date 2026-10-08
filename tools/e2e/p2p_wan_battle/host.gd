extends SceneTree

## WAN / P2P 完整闭环 E2E —— Host 端真进程（由 tools/e2e/p2p_wan_battle/run.py 拉起）。
##
## 在 9.2.3 真多进程 E2E 基础上继续往后跑：那边只断言到 Guest seat=2 / CONNECTED，
## 这里要证明「Host 建房 -> 真 invite -> rendezvous -> hole punch -> direct ENet ->
## protocol 6 -> seat=2 -> Ready -> Host Start -> **双方进 Battle** -> 退回菜单无残留」。
##
## 走的是真 UI 路径：MainMenu + LanOverlay 的 HOST OVER INTERNET 行，不是直调 LobbyManager。
## Host 绝不 begin_direct_enet()：它保持 host_listen() 的 ENet server 等 Guest 连。
##
## 用法：godot --headless --path . --script res://tools/e2e/p2p_wan_battle/host.gd
##       环境变量：RV_HOST / RV_PORT / INVITE_FILE / RESULT_FILE / READY_FILE

const TIMEOUT_MS: int = 50000
const SANDBOX_MARKER: String = "CombatSandbox"
const MENU_MARKER: String = "MainMenu"
const SETTLE_MS: int = 1200

var _rv_host: String = ""
var _rv_port: int = 0
var _invite_file: String = ""
var _result_file: String = ""
var _ready_file: String = ""

var _menu: Node = null
var _overlay: LanOverlay = null
var _manager: LobbyManager = null
var _done: bool = false
var _deadline: int = 0
var _phase: int = 0
var _started: bool = false
var _sandbox_at: int = -1

func _initialize() -> void:
	_rv_host = _env("RV_HOST", "127.0.0.1")
	_rv_port = int(_env("RV_PORT", "0"))
	_invite_file = _env("INVITE_FILE", "")
	_result_file = _env("RESULT_FILE", "")
	_ready_file = _env("READY_FILE", "")
	if _rv_port < 1 or _invite_file.is_empty() or _result_file.is_empty() or _ready_file.is_empty():
		printerr("WAN_HOST_FAIL: 缺少环境变量")
		_quit_fail()
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
	## 生产里 rendezvous 端点来自项目设置；E2E 用真服务端地址覆盖（公开 API）。
	_manager.set_rendezvous_endpoint(_rv_host, _rv_port)
	## Host 侧生产命令序列（与 LanOverlay 的 HOST OVER INTERNET 完全同一条：
	## host_room -> create_p2p_invite -> start_p2p_hosting）。见
	## tests/unit/lan_overlay_wan_host_test.gd 对 UI 接线本身的断言。
	##
	## 这里直接把 advertised 地址钉成回环：本机有多张网卡，_primary_address() 在
	## sandbox / CI 里不一定回环可达，而 Guest 侧 begin_direct_enet() 的 remote_advertised
	## 直接取自 Host 经 rendezvous 交换出去的候选（= invite 的 lan_host）。
	if not _manager.host_room("yard", GameLaunch.NetPlay.COOP, 20):
		_fail("host_room 失败（17777 被占？）")
		return
	var loop_invite: JoinInvite = _manager.create_p2p_invite("127.0.0.1")
	if loop_invite == null or not loop_invite.is_valid():
		_fail("create_p2p_invite 失败")
		return
	## 真 invite：必须带 p2p=1 + rendezvous 端点 + 协议 6。
	if not loop_invite.is_p2p():
		_fail("P2P invite 没有 p2p 标记")
		return
	if loop_invite.version != GameLaunch.NET_PROTOCOL:
		_fail("invite 协议号不是 %d（%d）" % [GameLaunch.NET_PROTOCOL, loop_invite.version])
		return
	if loop_invite.rendezvous_host != _rv_host or loop_invite.rendezvous_port != _rv_port:
		_fail("invite 没带正确 rendezvous 端点（%s:%d）" % [loop_invite.rendezvous_host, loop_invite.rendezvous_port])
		return
	## 换场合同硬规则：Host 只注册 rendezvous + 打洞（start_p2p_hosting），绝不发起
	## Direct ENet —— Host 保持 host_listen() 的 ENet server 等 Guest 连。
	if not _manager.start_p2p_hosting():
		_fail("start_p2p_hosting 失败")
		return
	var p2p: P2PConnection = _manager.get_p2p_connection()
	if p2p == null or not p2p.is_host_role():
		_fail("start_p2p_hosting 后不是 Host 角色（不得是 Guest / begin_direct_enet）")
		return
	_write_marker(_invite_file, loop_invite.to_uri())
	_write_marker(_ready_file, "ready")
	_wait()

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if _tick():
		if not _done:
			_done = true
			_write_result("OK scene=%s peer=released seat=1 cleanup=ok" % SANDBOX_MARKER)
			print("WAN_HOST_OK")
			quit(0)
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（phase=%d started=%s scene=%s | %s）" % [_phase, _started, _scene_name(), _diag()])
		return
	create_timer(0.05).timeout.connect(_wait)

func _diag() -> String:
	if not is_instance_valid(_manager):
		return "manager=gone"
	var p2p: P2PConnection = _manager.get_p2p_connection()
	var p2p_state: String = "null" if p2p == null else P2PConnectionState.state_name(p2p.get_state_value())
	var room: Room = _manager.get_room()
	var room_state: String = "null" if room == null else str(room.room_state)
	var players: int = -1 if room == null else room.player_count()
	return "p2p=%s net=%s room=%s players=%d term=%s" % [
		p2p_state, str(_manager.is_networked()), room_state, players, _manager.get_terminal_failure()
	]

func _tick() -> bool:
	match _phase:
		0:
			return _tick_lobby()
		1:
			return _tick_lan_preserved()
		2:
			return _tick_wait_guest_ready()
		3:
			return _tick_cleanup()
	return false

## phase 0：等 Guest 经 rendezvous + hole punch + direct ENet 落座、READY，再 START。
func _tick_lobby() -> bool:
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
	## 交接必须发生在换场前（start_match 内同步完成）：开战后 Host 不再持有
	## P2PConnection（rendezvous / 共享 UDP 已释放）。换场后 _manager 会被释放，
	## 所以这个断言只能在这里做。
	if _manager.get_p2p_connection() != null:
		_fail("开战后 Host 仍持有 P2PConnection（rendezvous 未清理）")
		return false
	_phase = 1
	return false

## phase 1：真 · 换场判据 —— current_scene 变成 CombatSandbox，且 peer 活着、座位正确。
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
		_fail("进 CombatSandbox 后没有活的 multiplayer_peer（换场把 P2P 连接掐断了）")
		return false
	if int(sandbox.get("_net_role")) != int(GameLaunch.NetRole.HOST):
		_fail("Host 换场后 role 不是 HOST（%s）" % str(sandbox.get("_net_role")))
		return false
	if int(sandbox.get("_local_seat")) != Room.HOST_SEAT:
		_fail("Host 换场后座位不是 1（%s）" % str(sandbox.get("_local_seat")))
		return false
	## 通知 Guest：Host 已在 Battle 站稳（peer 活着）。Guest 据此才准许退回菜单，
	## 否则 Guest 先关连接会让 Host 的 _on_peer_lost 把房降级成 Solo（peer 被清空）。
	_write_marker(_result_file + ".battle", "OK scene=%s peer=live seat=1" % SANDBOX_MARKER)
	_phase = 2
	return false

func _tick_wait_guest_ready() -> bool:
	if not FileAccess.file_exists(_guest_battle_marker()):
		return false
	var sandbox: Node = current_scene
	if sandbox != null and sandbox.name == SANDBOX_MARKER:
		sandbox.call("_return_to_menu")
	_phase = 3
	return false

func _tick_cleanup() -> bool:
	if _scene_name() != MENU_MARKER:
		return false
	if not _has_no_network_peer():
		_fail("退回菜单后仍有活的 multiplayer_peer（残留 peer）")
		return false
	return true

func _guest_battle_marker() -> String:
	return _result_file.replace("host.result", "guest.result") + ".battle"

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
	printerr("WAN_HOST_FAIL: %s" % reason)
	_quit_fail()

func _quit_fail() -> void:
	quit(1)

func _write_result(text: String) -> void:
	_write_marker(_result_file, text)

func _write_marker(path: String, text: String = "ready") -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("WAN_HOST_FAIL: 无法写 %s" % path)
		return
	file.store_string(text)
	file.close()
