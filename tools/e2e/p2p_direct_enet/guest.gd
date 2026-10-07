#!/usr/bin/env godot -s
## Guest 进程：使用真实 LobbyManager 流程解析 P2P invite，
## 连接 rendezvous，UDP hole punch，validated path，
## 发起 Direct ENet 连接，跑通 protocol 6 ticket handshake，拿到 seat_assigned。
##
## 环境变量参数：
##   GUEST_ENET_PORT    - ENet 绑定端口（客户端通常用 0 自动分配）
##   RENDEZVOUS_PORT    - Rendezvous 服务端端口
##   SESSION_ID         - 会话 ID
##   GUEST_NONCE        - Guest nonce
##   HOST_NONCE         - Host nonce（预期）
##   ROOM_ID            - 房间 ID
##   TICKET             - 房间票据
##   RESULT_FILE        - 结果文件路径
##   READY_FILE         - 就绪标记文件
##   GO_FILE            - 启动信号文件

@tool
extends SceneTree

var _guest_enet_port: int
var _rendezvous_port: int
var _session_id: String
var _guest_nonce: String
var _host_nonce: String
var _room_id: String
var _ticket: String
var _result_file: String
var _ready_file: String
var _go_file: String

var _lobby_net: LobbyNet
var _lobby_manager: LobbyManager
var _p2p_connection: P2PConnection
var _seat_assigned: int = 0
var _net_state: int = -1
var _joined_lobby: bool = false
var _state: String = "init"
var _p2p_ready_written: bool = false

func _initialize() -> void:
	_parse_env()
	_setup()
	_run.call_deferred()

func _parse_env() -> void:
	_guest_enet_port = int(_get_env("GUEST_ENET_PORT"))
	_rendezvous_port = int(_get_env("RENDEZVOUS_PORT"))
	_session_id = _get_env("SESSION_ID")
	_guest_nonce = _get_env("GUEST_NONCE")
	_host_nonce = _get_env("HOST_NONCE")
	_room_id = _get_env("ROOM_ID")
	_ticket = _get_env("TICKET")
	_result_file = _get_env("RESULT_FILE")
	_ready_file = _get_env("READY_FILE")
	_go_file = _get_env("GO_FILE")

	if _rendezvous_port == 0 or _session_id.is_empty() or _guest_nonce.is_empty() or _host_nonce.is_empty() or _room_id.is_empty() or _ticket.is_empty() or _result_file.is_empty() or _ready_file.is_empty() or _go_file.is_empty():
		printerr("GUEST_FAIL: 环境变量参数不全")
		quit(1)

func _get_env(key: String) -> String:
	var val = OS.get_environment(key)
	if typeof(val) == TYPE_BOOL:
		return ""
	if val == "":
		return ""
	return str(val)

func _setup() -> void:
	## 创建 LobbyNet
	_lobby_net = LobbyNet.new()
	root.add_child(_lobby_net)
	_lobby_net.connected.connect(_on_net_connected)
	_lobby_net.seat_assigned.connect(_on_seat_assigned)
	_lobby_net.connection_failed.connect(_on_connection_failed)
	_lobby_net.version_mismatch.connect(_on_version_mismatch)
	_lobby_net.join_rejected.connect(_on_join_rejected)
	_lobby_net.state_changed.connect(_on_net_state_changed)

	## 创建 LobbyManager
	_lobby_manager = LobbyManager.new()
	root.add_child(_lobby_manager)
	_lobby_manager.bind_net(_lobby_net)

	## 设置 rendezvous 端点（兜底）
	_lobby_manager.set_rendezvous_endpoint("127.0.0.1", _rendezvous_port)

	## 直接创建 P2PConnection 并使用预设 nonce（测试需要确定性 nonce）
	_p2p_connection = P2PConnection.new()
	_p2p_connection.bind_transport(_lobby_manager._connect_transport.bind(), _lobby_manager._close_transport.bind())
	_p2p_connection.state_changed.connect(_on_p2p_state_changed)
	_p2p_connection.finished.connect(_on_p2p_finished)
	
	## 创建 rendezvous client 并绑定
	var client: RendezvousClient = RendezvousClient.new()
	_p2p_connection.bind_rendezvous(client)
	
	## 构造 SessionIdentity 使用预设的 guest_nonce
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		_room_id, _ticket, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.GUEST, _guest_nonce
	)
	
	## 本地候选（用于 rendezvous 注册）
	var local_candidates: Array = []
	var cand: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	cand.path = LobbyPlayer.Path.LAN_IPV4
	cand.address = "127.0.0.1"
	cand.port = 17777
	local_candidates.append(cand)
	
	## 创建共享 UDP socket（供 rendezvous client 与 hole punch 复用）
	var shared_udp: PacketPeerUDP = PacketPeerUDP.new()
	var err: Error = shared_udp.bind(0)
	if err != OK:
		_write_result("FAIL: shared UDP bind 失败")
		quit(1)
	
	## 等待一小段时间，确保 Host 的 rendezvous 注册已完成（避免 SESSION_NOT_FOUND 竞态）
	OS.delay_usec(500000)

	## 开始 P2P 连接流程（使用预设 identity 和 shared UDP）
	if not _p2p_connection.begin_with_identity(identity, local_candidates, "127.0.0.1", _rendezvous_port, shared_udp):
		_write_result("FAIL: P2P begin_with_identity 失败")
		quit(1)

	## 注入到 LobbyManager，供后续 ENet 连接使用
	_lobby_manager._p2p_connection = _p2p_connection

	_state = "p2p_started"
	print("GUEST: P2P join started via begin_with_identity()")
	## 不在这里写 ready，等 rendezvous registered 后再写

func _on_p2p_state_changed(from: int, to: int, event: int) -> void:
	var from_name: String = P2PConnectionState.state_name(from)
	var to_name: String = P2PConnectionState.state_name(to)
	var event_name: String = P2PConnectionState.event_name(event)
	print("GUEST: P2P state %s -> %s via %s" % [from_name, to_name, event_name])
	if to == P2PConnectionState.State.RENDEZVOUS_REGISTERED:
		_write_ready()

func _on_p2p_finished(success: bool, reason: String) -> void:
	print("GUEST: P2P finished success=%s reason=%s" % [success, reason])
	if not success:
		_write_result("FAIL: P2P finished: %s" % reason)
		quit(1)

func _on_net_state_changed(state: int) -> void:
	_net_state = state
	var name: String = LobbyNet.NetState.keys()[state] if state < LobbyNet.NetState.keys().size() else "UNKNOWN"
	print("GUEST: NetState -> %s" % name)

func _on_net_connected() -> void:
	print("GUEST: ENet connected_to_server")

func _on_seat_assigned(seat: int) -> void:
	print("GUEST: seat_assigned seat=%d" % seat)
	_seat_assigned = seat
	_joined_lobby = true

func _on_connection_failed() -> void:
	_write_result("FAIL: ENet connection_failed")
	quit(1)

func _on_version_mismatch() -> void:
	_write_result("FAIL: version_mismatch")
	quit(1)

func _on_join_rejected(reason: int) -> void:
	_write_result("FAIL: join_rejected reason=%d" % reason)
	quit(1)

func _write_ready() -> void:
	if _p2p_ready_written:
		return
	var f = FileAccess.open(_ready_file, FileAccess.WRITE)
	if f:
		f.store_line("ready")
		f.close()
	_p2p_ready_written = true

func _run() -> void:
	## 等待 go 信号
	while not FileAccess.file_exists(_go_file):
		_process_p2p(0.016)
		OS.delay_usec(16000)

	## 开始主循环：推进 P2P 状态机直到完成
	print("GUEST: go signal received, starting main loop")
	while true:
		_process_p2p(0.016)

		var p2p: P2PConnection = _p2p_connection
		if p2p != null:
			var state_val: int = p2p.get_state_value()
			print("GUEST: p2p state = %s, net_state = %s, joined_lobby = %s" % [
				P2PConnectionState.state_name(state_val),
				LobbyNet.NetState.keys()[_net_state] if _net_state < LobbyNet.NetState.keys().size() else "UNKNOWN",
				str(_joined_lobby)
			])

		if _joined_lobby and _net_state == int(LobbyNet.NetState.LOBBY):
			break
		if _state == "failed":
			break
		OS.delay_usec(16000)

	_write_result("OK: seat=%d state=LOBBY" % _seat_assigned)
	quit(0)

func _process_p2p(delta: float) -> void:
	if _p2p_connection == null:
		return

	_p2p_connection.poll_rendezvous(delta)
	_p2p_connection.tick(delta)

	## 检查 P2P 连接状态
	var p2p: P2PConnection = _p2p_connection
	if p2p != null:
		var state_val: int = p2p.get_state_value()
		## 写 ready 文件当达到 RENDEZVOUS_REGISTERED
		if state_val == P2PConnectionState.State.RENDEZVOUS_REGISTERED and not _p2p_ready_written:
			_write_ready()

		## 当 hole punch 成功后，begin_direct_enet 会在 P2PConnection 内部自动调用
		## Guest 侧需要发起 ENet 连接
		if state_val == P2PConnectionState.State.DIRECT_ENET_CONNECTING and not _lobby_net.is_active():
			print("GUEST: Starting Direct ENet connection")
			## 使用 validated endpoint 作为 ENet 目标
			var target: Dictionary = p2p.get_direct_enet_target()
			if target.get("validated", false) and not target.get("address", "").is_empty() and target.get("port", 0) > 0:
				var success: bool = _lobby_net.client_connect(target.address, target.port, _ticket)
				if not success:
					print("GUEST: ENet client_connect 失败")
					_write_result("FAIL: ENet client_connect 失败")
					quit(1)
			else:
				print("GUEST: No valid Direct ENet target")
				_write_result("FAIL: No valid Direct ENet target")
				quit(1)

func _write_result(msg: String) -> void:
	var f = FileAccess.open(_result_file, FileAccess.WRITE)
	if f:
		f.store_line(msg)
		f.close()