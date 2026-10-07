#!/usr/bin/env godot -s
## Host 进程：使用真实 LobbyManager 流程创建房间并监听 ENet，启动 rendezvous client，等待 Guest 连接。
##
## 环境变量参数：
##   HOST_ENET_PORT     - ENet 监听端口
##   RENDEZVOUS_PORT    - Rendezvous 服务端端口
##   SESSION_ID         - 会话 ID
##   HOST_NONCE         - Host nonce
##   GUEST_NONCE        - Guest nonce（预期）
##   ROOM_ID            - 房间 ID
##   TICKET             - 房间票据
##   RESULT_FILE        - 结果文件路径
##   READY_FILE         - 就绪标记文件
##   GO_FILE            - 启动信号文件

@tool
extends SceneTree

var _host_enet_port: int
var _rendezvous_port: int
var _session_id: String
var _host_nonce: String
var _guest_nonce: String
var _room_id: String
var _ticket: String
var _result_file: String
var _ready_file: String
var _go_file: String

var _lobby_net: LobbyNet
var _lobby_manager: LobbyManager
var _p2p_connection: P2PConnection
var _peer_confirmed: bool = false
var _seat_assigned: int = 0
var _state: String = "init"
var _got_candidates: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerProfile.load_from_disk()
	_parse_env()
	_setup()
	## 等待 go 信号
	print("HOST: Entering wait loop for go file")
	while not FileAccess.file_exists(_go_file):
		print("HOST: Wait loop iteration, go_file exists = %s" % str(FileAccess.file_exists(_go_file)))
		_process_p2p(0.01)
		OS.delay_usec(10000)

	## 开始主循环
	while true:
		_process_p2p(0.016)
		if _peer_confirmed:
			break
		if _state == "failed":
			break
		OS.delay_usec(16000)

	_write_result("OK: peer_confirmed seat=%d" % _seat_assigned)
	quit(0)

func _parse_env() -> void:
	_host_enet_port = int(_get_env("HOST_ENET_PORT"))
	_rendezvous_port = int(_get_env("RENDEZVOUS_PORT"))
	_session_id = _get_env("SESSION_ID")
	_host_nonce = _get_env("HOST_NONCE")
	_guest_nonce = _get_env("GUEST_NONCE")
	_room_id = _get_env("ROOM_ID")
	_ticket = _get_env("TICKET")
	_result_file = _get_env("RESULT_FILE")
	_ready_file = _get_env("READY_FILE")
	_go_file = _get_env("GO_FILE")

	if _host_enet_port == 0 or _rendezvous_port == 0 or _session_id.is_empty() or _host_nonce.is_empty() or _guest_nonce.is_empty() or _room_id.is_empty() or _ticket.is_empty() or _result_file.is_empty() or _ready_file.is_empty() or _go_file.is_empty():
		printerr("HOST_FAIL: 环境变量参数不全")
		quit(1)

func _get_env(key: String) -> String:
	var val = OS.get_environment(key)
	## OS.get_environment returns false (bool) if not set, or the string value
	## Use typeof to check before auto-conversion
	if typeof(val) == TYPE_BOOL:
		return ""
	if val == "":
		return ""
	return str(val)

func _setup() -> void:
	## 创建 LobbyNet
	_lobby_net = LobbyNet.new()
	root.add_child(_lobby_net)
	_lobby_net.listen_ok.connect(_on_listen_ok)
	_lobby_net.peer_joined.connect(_on_peer_joined)
	_lobby_net.peer_confirmed.connect(_on_peer_confirmed)
	_lobby_net.state_changed.connect(_on_net_state_changed)

	## 创建 LobbyManager
	_lobby_manager = LobbyManager.new()
	root.add_child(_lobby_manager)
	_lobby_manager.bind_net(_lobby_net)

	## 设置 rendezvous 端点（用于 P2P invite）
	_lobby_manager.set_rendezvous_endpoint("127.0.0.1", _rendezvous_port)

	## 创建房间并监听 ENet
	## 使用预设的 ticket，确保与 Guest 一致
	_lobby_manager._room_ticket = _ticket
	if not _lobby_manager.host_room("yard", GameLaunch.NetPlay.COOP, 0):
		_write_result("FAIL: host_room 失败")
		quit(1)

	## 创建 P2P invite（包含 rendezvous 端点）
	var invite: JoinInvite = _lobby_manager.create_p2p_invite("127.0.0.1")
	if invite == null or not invite.is_valid():
		_write_result("FAIL: create_p2p_invite 失败")
		quit(1)

	## 开始 P2P join（Host 侧作为 HOST 角色注册到 rendezvous）
	_p2p_connection = _lobby_manager._get_or_create_p2p_connection()
	var client: RendezvousClient = RendezvousClient.new()
	_p2p_connection.bind_rendezvous(client)

	## 构造 SessionIdentity（使用预设 nonce）
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		_room_id, _ticket, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.HOST, _host_nonce
	)

	## 本地候选：ENet listen 端点
	var local_candidates: Array = []
	var cand: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	cand.path = LobbyPlayer.Path.LAN_IPV4
	cand.address = "127.0.0.1"
	cand.port = _host_enet_port
	local_candidates.append(cand)

	## 创建共享 UDP socket（供 rendezvous client 与 hole punch 复用）
	var shared_udp: PacketPeerUDP = PacketPeerUDP.new()
	var err: Error = shared_udp.bind(0)
	if err != OK:
		_write_result("FAIL: shared UDP bind 失败")
		quit(1)

## 开始 rendezvous 注册（使用预设 identity 和 shared UDP）
	printerr("HOST: Before begin_with_identity, shared_udp valid = %s" % str(shared_udp != null))
	if not _p2p_connection.begin_with_identity(identity, local_candidates, "127.0.0.1", _rendezvous_port, shared_udp):
		_write_result("FAIL: P2P begin_with_identity 失败")
		quit(1)
	printerr("HOST: After begin_with_identity, client udp = %s" % str(_p2p_connection.get_rendezvous_client().get_udp() != null))

	_state = "rendezvous_registering"
	print("HOST: P2P join started, waiting for rendezvous...")

func _on_listen_ok() -> void:
	print("HOST: ENet listen_ok on port %d" % _host_enet_port)

func _on_net_state_changed(state: int) -> void:
	var name: String = LobbyNet.NetState.keys()[state] if state < LobbyNet.NetState.keys().size() else "UNKNOWN"
	print("HOST: NetState -> %s" % name)
	if state == int(LobbyNet.NetState.LOBBY):
		_state = "lobby"

func _on_peer_joined(peer_id: int, seat: int) -> void:
	print("HOST: peer_joined peer_id=%d seat=%d" % [peer_id, seat])

func _on_peer_confirmed(peer_id: int, seat: int) -> void:
	print("HOST: peer_confirmed peer_id=%d seat=%d" % [peer_id, seat])
	_peer_confirmed = true
	_seat_assigned = seat

func _write_ready() -> void:
	var f = FileAccess.open(_ready_file, FileAccess.WRITE)
	if f:
		f.store_line("ready")
		f.close()

func _process_p2p(delta: float) -> void:
	if _p2p_connection == null:
		return

	_p2p_connection.poll_rendezvous(delta)
	_p2p_connection.tick(delta)

	## 检查 rendezvous 状态
	var p2p: P2PConnection = _p2p_connection
	var state_val: int = p2p.get_state_value()

	if state_val == P2PConnectionState.State.RENDEZVOUS_REGISTERED and _state == "rendezvous_registering":
		print("HOST: Rendezvous registered")
		_state = "rendezvous_registered"
		_write_ready()

	if state_val == P2PConnectionState.State.CANDIDATES_RECEIVED and not _got_candidates:
		print("HOST: Received candidates from rendezvous")
		_got_candidates = true
		_state = "candidates_received"

	## 当 hole punch 成功后，_on_p2p_direct_path_established 会在 LobbyManager 里自动调用 begin_direct_enet
	## Host 侧只需等待 ENet 连接

var _last_client_state: int = -1

func _write_result(msg: String) -> void:
	var f = FileAccess.open(_result_file, FileAccess.WRITE)
	if f:
		f.store_line(msg)
		f.close()