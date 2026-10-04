#!/usr/bin/env godot -s
## Guest 进程：解析 P2P invite，连接 rendezvous，UDP hole punch，validated path，
## 发起 Direct ENet 连接，跑通 protocol 6 ticket handshake，拿到 seat_assigned。
##
## 参数：
##   [0] guest_enet_port    - ENet 绑定端口（客户端通常用 0 自动分配）
##   [1] rendezvous_port    - Rendezvous 服务端端口
##   [2] session_id         - 会话 ID
##   [3] guest_nonce        - Guest nonce
##   [4] host_nonce         - Host nonce（预期）
##   [5] room_id            - 房间 ID
##   [6] ticket             - 房间票据
##   [7] result_file        - 结果文件路径
##   [8] ready_file         - 就绪标记文件
##   [9] go_file            - 启动信号文件

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

func _initialize() -> void:
	_parse_args()
	_setup()
	_run.call_deferred()

func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 10:
		printerr("GUEST_FAIL: 参数不足 %d" % args.size())
		quit(1)
	_guest_enet_port = int(args[0])
	_rendezvous_port = int(args[1])
	_session_id = args[2]
	_guest_nonce = args[3]
	_host_nonce = args[4]
	_room_id = args[5]
	_ticket = args[6]
	_result_file = args[7]
	_ready_file = args[8]
	_go_file = args[9]

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

	## 构造 P2P invite
	var invite: JoinInvite = JoinInvite.create(
		"127.0.0.1", 17777, _ticket, _room_id, "Host",
		"", "", JoinInvite.DEFAULT_WAN_PORT,
		true, "127.0.0.1", _rendezvous_port
	)

	## 开始 P2P join
	var joined: JoinInvite = _lobby_manager.join_invite(invite.to_uri())
	if joined.error != JoinInvite.InvalidReason.OK:
		_write_result("FAIL: join_invite 失败: %d" % joined.error)
		quit(1)

	_p2p_connection = _lobby_manager._p2p_connection
	if _p2p_connection == null:
		_write_result("FAIL: 未创建 P2PConnection")
		quit(1)

	## 监听 P2P 状态
	_p2p_connection.state_changed.connect(_on_p2p_state_changed)
	_p2p_connection.finished.connect(_on_p2p_finished)

	_state = "p2p_started"
	print("GUEST: P2P join started")
	_write_ready()

func _on_p2p_state_changed(from: int, to: int, event: int) -> void:
	var from_name: String = P2PConnectionState.state_name(from)
	var to_name: String = P2PConnectionState.state_name(to)
	var event_name: String = P2PConnectionState.event_name(event)
	print("GUEST: P2P state %s -> %s via %s" % [from_name, to_name, event_name])

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
	var f = FileAccess.open(_ready_file, FileAccess.WRITE)
	if f:
		f.store_line("ready")
		f.close()

func _run() -> void:
	## 等待 go 信号
	while not FileAccess.file_exists(_go_file):
		_p2p_connection.tick(0.016)
		OS.delay_usec(16000)

	## 开始主循环：推进 P2P 状态机直到完成
	print("GUEST: go signal received, starting main loop")
	while true:
		_p2p_connection.tick(0.016)
		print("GUEST: p2p state = ", _p2p_connection.get_state_value(), " net_state = ", _net_state)
		if _joined_lobby and _net_state == int(LobbyNet.NetState.LOBBY):
			break
		if _state == "failed":
			break
		OS.delay_usec(16000)

	_write_result("OK: seat=%d state=LOBBY" % _seat_assigned)
	quit(0)

func _write_result(msg: String) -> void:
	var f = FileAccess.open(_result_file, FileAccess.WRITE)
	if f:
		f.store_line(msg)
		f.close()