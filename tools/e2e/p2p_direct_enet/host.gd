#!/usr/bin/env godot -s
## Host 进程：创建房间，监听 ENet，启动 rendezvous client，等待 Guest 连接。
##
## 参数：
##   [0] host_enet_port     - ENet 监听端口
##   [1] rendezvous_port    - Rendezvous 服务端端口
##   [2] session_id         - 会话 ID
##   [3] host_nonce         - Host nonce
##   [4] guest_nonce        - Guest nonce（预期）
##   [5] room_id            - 房间 ID
##   [6] ticket             - 房间票据
##   [7] result_file        - 结果文件路径
##   [8] ready_file         - 就绪标记文件
##   [9] go_file            - 启动信号文件

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
var _rendezvous_client: RendezvousClient
var _hole_punch: P2PHolePunch
var _shared_udp: PacketPeerUDP
var _peer_confirmed: bool = false
var _seat_assigned: int = 0
var _state: String = "init"
var _candidates_sent: bool = false
var _observed_address: String = ""
var _observed_port: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerProfile.load_from_disk()
	_parse_args()
	_setup()
	## 等待 go 信号
	while not FileAccess.file_exists(_go_file):
		_process_rendezvous(0.01)
		_process_hole_punch(0.01)
		OS.delay_usec(10000)

	## 开始主循环
	while true:
		_process_rendezvous(0.016)
		_process_hole_punch(0.016)
		if _peer_confirmed:
			break
		if _state == "failed":
			break
		OS.delay_usec(16000)

	_write_result("OK: peer_confirmed seat=%d" % _seat_assigned)
	quit(0)

func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 10:
		printerr("HOST_FAIL: 参数不足 %d" % args.size())
		quit(1)
	_host_enet_port = int(args[0])
	_rendezvous_port = int(args[1])
	_session_id = args[2]
	_host_nonce = args[3]
	_guest_nonce = args[4]
	_room_id = args[5]
	_ticket = args[6]
	_result_file = args[7]
	_ready_file = args[8]
	_go_file = args[9]

func _setup() -> void:
	## 创建 LobbyNet
	_lobby_net = LobbyNet.new()
	root.add_child(_lobby_net)
	_lobby_net.listen_ok.connect(_on_listen_ok)
	_lobby_net.peer_confirmed.connect(_on_peer_confirmed)
	_lobby_net.state_changed.connect(_on_net_state_changed)

	## 创建 LobbyManager
	_lobby_manager = LobbyManager.new()
	root.add_child(_lobby_manager)
	_lobby_manager.bind_net(_lobby_net)

	## 创建房间并监听
	_lobby_manager._room_ticket = _ticket
	if not _lobby_manager.host_room("yard", GameLaunch.NetPlay.COOP, 0):
		_write_result("FAIL: host_room 失败")
		quit(1)

	## 创建共享 UDP socket（供 rendezvous client 与 hole punch 复用）
	_shared_udp = PacketPeerUDP.new()
	var err: Error = _shared_udp.bind(0)
	if err != OK:
		_write_result("FAIL: shared UDP bind 失败")
		quit(1)
	var shared_port: int = _shared_udp.get_local_port()

	## 创建 rendezvous client
	_rendezvous_client = RendezvousClient.new()
	_rendezvous_client.registered.connect(_on_rendezvous_registered)
	_rendezvous_client.candidates_received.connect(_on_rendezvous_candidates)
	_rendezvous_client.server_error.connect(_on_rendezvous_error)
	_rendezvous_client.timed_out.connect(_on_rendezvous_timeout)

	## 本地候选：包含 observed endpoint（由服务端在 REGISTERED 里回填）
	var local_candidates: Array = []
	var cand: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	cand.path = LobbyPlayer.Path.LAN_IPV4
	cand.address = "127.0.0.1"
	cand.port = _host_enet_port
	local_candidates.append(cand)

	## 开始 rendezvous 注册
	if not _rendezvous_client.begin("127.0.0.1", _rendezvous_port,
		RendezvousContract.make_identity(_room_id, _ticket, GameLaunch.NET_PROTOCOL, RendezvousContract.Role.HOST, _host_nonce),
		local_candidates, _shared_udp):
		_write_result("FAIL: rendezvous begin 失败")
		quit(1)

	_state = "rendezvous_registering"
	print("HOST: 等待 rendezvous registered...")

func _on_listen_ok() -> void:
	print("HOST: ENet listen_ok on port %d" % _host_enet_port)

func _on_net_state_changed(state: int) -> void:
	var name: String = LobbyNet.NetState.keys()[state] if state < LobbyNet.NetState.keys().size() else "UNKNOWN"
	print("HOST: NetState -> %s" % name)
	if state == int(LobbyNet.NetState.LOBBY):
		_state = "lobby"

func _on_rendezvous_registered(session_id: String, observed_address: String, observed_port: int) -> void:
	print("HOST: rendezvous registered, session=%s observed=%s:%d" % [session_id, observed_address, observed_port])
	_observed_address = observed_address
	_observed_port = observed_port
	_state = "rendezvous_registered"
	_write_ready()

func _on_rendezvous_candidates(candidates: Array, remote_nonce: String, remote_role: int) -> void:
	print("HOST: rendezvous candidates received, remote_nonce=%s" % remote_nonce)
	for c in candidates:
		print("HOST:   remote candidate: path=%d addr=%s port=%d obs_addr=%s obs_port=%d" % [
			c.path, c.address, c.port, c.observed_address, c.observed_port
		])
	_state = "candidates_received"
	## 直接创建 hole punch（call_deferred 在紧凑循环中不生效）
	_create_hole_punch(candidates)

func _create_hole_punch(candidates: Array) -> void:
	## 创建 hole punch（Host 角色）
	_hole_punch = P2PHolePunch.new()
	_hole_punch.path_established.connect(_on_hole_punch_path_established)
	_hole_punch.path_failed.connect(_on_hole_punch_path_failed)
	_hole_punch.timeout.connect(_on_hole_punch_timeout)
	
	var remote_candidates: Array = []
	for candidate: RendezvousContract.Candidate in candidates:
		remote_candidates.append(candidate)
	
	var local_candidates_for_punch: Array = []
	var local_cand: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	local_cand.path = LobbyPlayer.Path.LAN_IPV4
	local_cand.address = "127.0.0.1"
	## 使用 observed endpoint（共享 UDP socket 的实际端口），而非 ENet 端口
	local_cand.port = _observed_port
	local_cand.observed_address = _observed_address
	local_cand.observed_port = _observed_port
	local_candidates_for_punch.append(local_cand)
	
	print("HOST: local candidate for punch: port=%d obs_port=%d" % [local_cand.port, local_cand.observed_port])
	
	if not _hole_punch.begin(
		_session_id,
		_host_nonce,
		_guest_nonce,
		P2PUDPProbe.Role.HOST,
		local_candidates_for_punch,
		remote_candidates,
		0,
		_shared_udp
	):
		_write_result("FAIL: hole_punch begin 失败")
		quit(1)
	
	_candidates_sent = true
	print("HOST: hole punch started")

func _on_hole_punch_path_established(rtt_ms: int, validated_candidate: Dictionary) -> void:
	print("HOST: hole punch path established rtt=%d validated=%s" % [rtt_ms, validated_candidate])
	## 此时 hole punch 成功，Host 侧只需等待 Guest 发起 ENet 连接
	## LobbyNet 已经在 listen，会自动接受连接

func _on_hole_punch_path_failed(reason: String) -> void:
	print("HOST: hole punch failed: %s" % reason)
	if _hole_punch != null:
		print("HOST: hole punch debug pairs:")
		for pair_state in _hole_punch.debug_pair_states():
			print("HOST:   %s" % pair_state)
	_write_result("FAIL: hole punch failed: %s" % reason)
	quit(1)

func _on_hole_punch_timeout() -> void:
	_write_result("FAIL: hole punch timeout")
	quit(1)

func _on_rendezvous_error(error_code: int, detail: String) -> void:
	_write_result("FAIL: rendezvous error %d: %s" % [error_code, detail])
	quit(1)

func _on_rendezvous_timeout(reason: String) -> void:
	_write_result("FAIL: rendezvous timeout: %s" % reason)
	quit(1)

func _on_peer_confirmed(peer_id: int, seat: int) -> void:
	print("HOST: peer_confirmed peer_id=%d seat=%d" % [peer_id, seat])
	_peer_confirmed = true
	_seat_assigned = seat

func _write_ready() -> void:
	var f = FileAccess.open(_ready_file, FileAccess.WRITE)
	if f:
		f.store_line("ready")
		f.close()

func _process_rendezvous(delta: float) -> void:
	if _rendezvous_client != null:
		## Hole punch 激活时停止 rendezvous poll，避免抢占共享 socket
		if _hole_punch == null or not _hole_punch.is_active():
			_rendezvous_client.poll()
		_rendezvous_client.tick(delta)

func _process_hole_punch(delta: float) -> void:
	if _hole_punch != null and _hole_punch.is_active():
		_hole_punch.tick(int(delta * 1000))

func _write_result(msg: String) -> void:
	var f = FileAccess.open(_result_file, FileAccess.WRITE)
	if f:
		f.store_line(msg)
		f.close()