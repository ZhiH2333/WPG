extends SceneTree

## P2P UDP Probe E2E —— Guest 端真进程（由 tools/ci/p2p_probe_e2e.py 拉起，不单独跑）。
##
## 本进程 bind UDP 端口，接收 Host 的 probe，回复 ACK。
##
## 用法：godot --headless --path . --script res://tools/ci/p2p_probe_guest.gd -- <local_port> <remote_port> <session_id> <local_nonce> <remote_nonce> <role> <result_file>

const TIMEOUT_MS: int = 15000

var _port: int = 0
var _remote_port: int = 0
var _session_id: String = ""
var _local_nonce: String = ""
var _remote_nonce: String = ""
var _role: String = ""
var _result_path: String = ""
var _socket: PacketPeerUDP = null
var _done: bool = false
var _deadline: int = 0
var _received_probe: bool = false
var _sent_ack: bool = false
var _probe_timestamp: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		printerr("GUEST_FAIL -: 缺少 local_port / remote_port / session_id / local_nonce / remote_nonce / role / result_file")
		quit(1)
		return
	_port = int(args[0])
	_remote_port = int(args[1])
	_session_id = args[2]
	_local_nonce = args[3]
	_remote_nonce = args[4]
	_role = args[5]
	_result_path = args[6]
	_run.call_deferred()

func _run() -> void:
	_socket = PacketPeerUDP.new()
	var err: Error = _socket.bind(_port)
	if err != OK:
		_fail("bind 失败: %s" % err)
		return
	var actual_port: int = _socket.get_local_port()
	print("GUEST bound on port %d" % actual_port)
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	_poll_loop()

func _poll_loop() -> void:
	if _done:
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("轮询超时")
		return
	while _socket.get_available_packet_count() > 0:
		var packet: PackedByteArray = _socket.get_packet()
		if not packet.is_empty():
			_handle_packet(packet)
	if _sent_ack:
		_finish_ok()
		return
	create_timer(0.01).timeout.connect(_poll_loop)

func _handle_packet(packet: PackedByteArray) -> void:
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	if not decoded.is_ok():
		return
	if not P2PUDPProbe.validate_expectation(decoded, _session_id, _remote_nonce, P2PUDPProbe.Role.HOST):
		return
	if decoded.is_probe():
		_received_probe = true
		_probe_timestamp = decoded.timestamp_ms
		## 回复 ACK - 需要先设置目标地址为 Host
		_socket.set_dest_address("127.0.0.1", _remote_port)
		var now_ms: int = Time.get_ticks_msec()
		var ack: PackedByteArray = P2PUDPProbe.encode_ack(_session_id, _local_nonce, P2PUDPProbe.Role.GUEST, now_ms, _probe_timestamp)
		_socket.put_packet(ack)
		_sent_ack = true

func _finish_ok() -> void:
	if _done:
		return
	_done = true
	_write_result("OK replied")
	print("GUEST_OK replied")
	_socket.close()
	quit(0)

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_result("FAIL: %s" % reason)
	printerr("GUEST_FAIL: %s" % reason)
	if _socket != null:
		_socket.close()
	quit(1)

func _write_result(text: String) -> void:
	var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		printerr("GUEST_FAIL: 无法写结果文件 %s" % _result_path)
		return
	file.store_string(text)
	file.close()