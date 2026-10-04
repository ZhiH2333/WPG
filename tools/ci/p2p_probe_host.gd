extends SceneTree

## P2P UDP Probe E2E —— Host 端真进程（由 tools/ci/p2p_probe_e2e.py 拉起，不单独跑）。
##
## 本进程只做一件事：用真实 UDP bind 端口，发送 probe 到 Guest，
## 接收 Guest 的 ACK，验证双向可达。
##
## 用法：godot --headless --path . --script res://tools/ci/p2p_probe_host.gd -- <local_port> <remote_port> <session_id> <local_nonce> <remote_nonce> <role> <result_file>

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
var _sent_probe: bool = false
var _received_ack: bool = false
var _remote_addr: String = "127.0.0.1"
var _probe_timestamp: int = 0
var _rtt_ms: int = 0
var _sent_probe_count: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 6:
		printerr("HOST_FAIL -: 缺少 local_port / remote_port / session_id / local_nonce / remote_nonce / role / result_file")
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
	print("HOST bound on port %d" % actual_port)
	_socket.set_dest_address(_remote_addr, _remote_port)
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	## 等待 Guest 启动并 bind，发送多次 probe 以防丢包
	_wait_and_probe()

func _wait_and_probe() -> void:
	if _done:
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("等待 Guest 超时")
		return
	_send_probe()
	## 重发 probe 每 200ms，直到收到 ACK 或超时
	var timer = create_timer(0.2)
	timer.timeout.connect(_maybe_resend_probe)
	_poll_loop()

func _maybe_resend_probe() -> void:
	if _done or _received_ack:
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("轮询超时")
		return
	_send_probe()
	var timer = create_timer(0.2)
	timer.timeout.connect(_maybe_resend_probe)

func _send_probe() -> void:
	var now_ms: int = Time.get_ticks_msec()
	_probe_timestamp = now_ms
	var probe_id: int = _sent_probe_count + 1
	_sent_probe_count = probe_id
	var packet: PackedByteArray = P2PUDPProbe.encode_probe(_session_id, _local_nonce, P2PUDPProbe.Role.HOST, now_ms, probe_id)
	_socket.put_packet(packet)
	_sent_probe = true
	print("HOST sent probe ts=%d probe_id=%d" % [now_ms, probe_id])

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
	if _received_ack:
		_finish_ok()
		return
	create_timer(0.01).timeout.connect(_poll_loop)

func _handle_packet(packet: PackedByteArray) -> void:
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	if not decoded.is_ok():
		return
	if not P2PUDPProbe.validate_expectation(decoded, _session_id, _remote_nonce, P2PUDPProbe.Role.GUEST):
		return
	if decoded.is_ack():
		## 验证 probe_id 匹配
		if decoded.probe_id != _sent_probe_count:
			return
		_received_ack = true
		var now_ms: int = Time.get_ticks_msec()
		_rtt_ms = P2PUDPProbe.calculate_rtt(now_ms, decoded.original_timestamp_ms)
		print("HOST received ACK rtt=%dms probe_id=%d" % [_rtt_ms, decoded.probe_id])

func _finish_ok() -> void:
	if _done:
		return
	_done = true
	_write_result("OK bidirectional rtt=%dms" % _rtt_ms)
	print("HOST_OK bidirectional rtt=%dms" % _rtt_ms)
	_socket.close()
	quit(0)

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_result("FAIL: %s" % reason)
	printerr("HOST_FAIL: %s" % reason)
	if _socket != null:
		_socket.close()
	quit(1)

func _write_result(text: String) -> void:
	var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		printerr("HOST_FAIL: 无法写结果文件 %s" % _result_path)
		return
	file.store_string(text)
	file.close()