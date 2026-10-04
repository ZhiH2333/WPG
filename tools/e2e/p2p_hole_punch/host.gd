extends SceneTree

## P2P Hole Punch E2E —— Host 端真进程（由 tools/e2e/p2p_hole_punch/run.py 拉起，不单独跑）。
##
## **必须使用 production P2PHolePunch**，不允许用 PacketPeerUDP 手写 probe/ACK 协议。
## 本进程只负责：
##   - 用 P2PHolePunch 绑定固定 UDP 端口
##   - 等 Python 协调文件出现后开始 tick（双方同时开始探测）
##   - 打洞成功后记录 validated endpoint
##
## 用法：
##   godot --headless --path . --script res://tools/e2e/p2p_hole_punch/host.gd -- \
##     <local_port> <remote_port> <session_id> <local_nonce> <remote_nonce> <role> <result_file> <go_file>

const TIMEOUT_MS: int = 20000

var _local_port: int = 0
var _remote_port: int = 0
var _session_id: String = ""
var _local_nonce: String = ""
var _remote_nonce: String = ""
var _result_path: String = ""
var _go_path: String = ""
var _punch: P2PHolePunch = null
var _done: bool = false
var _deadline: int = 0
var _last_tick_ms: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 8:
		printerr("HOST_FAIL -: 需要 local_port remote_port session_id local_nonce remote_nonce role result_file go_file")
		quit(1)
		return
	_local_port = int(args[0])
	_remote_port = int(args[1])
	_session_id = args[2]
	_local_nonce = args[3]
	_remote_nonce = args[4]
	_result_path = args[6]
	_go_path = args[7]
	_run.call_deferred()

func _run() -> void:
	_punch = P2PHolePunch.new()
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	## 本地候选：本端真实绑定端点。远端候选：advertised 故意给不可达地址，
	## 真正的打洞目标只能是 observed（127.0.0.1:_remote_port）。
	var local_candidates: Array = [_candidate(LobbyPlayer.Path.LAN_IPV4, "127.0.0.1", _local_port)]
	var remote_candidates: Array = [
		_candidate(LobbyPlayer.Path.WAN_IPV4, "10.255.255.9", 1, "127.0.0.1", _remote_port)
	]
	var ok: bool = _punch.begin(
		_session_id, _local_nonce, _remote_nonce, P2PUDPProbe.Role.HOST,
		local_candidates, remote_candidates, _local_port
	)
	if not ok:
		_fail("hole punch begin 失败")
		return
	## 先发一轮 probe（让 pending probe_id 存在），再等 Python 的 go：
	## 这样 stale ACK 注入能真正考验 probe_id correlation，而不是「还没发过 probe」。
	_punch.tick(0)
	print("HOST bound on port %d" % _local_port)
	_write_text(_result_path + ".bound", "1")
	_wait_for_go()

func _wait_for_go() -> void:
	if _done:
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("等待 go 文件超时")
		return
	if FileAccess.file_exists(_go_path):
		_last_tick_ms = Time.get_ticks_msec()
		_poll_loop()
		return
	create_timer(0.02).timeout.connect(_wait_for_go)

func _poll_loop() -> void:
	if _done:
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("打洞超时")
		return
	var now_ms: int = Time.get_ticks_msec()
	var delta_ms: int = maxi(now_ms - _last_tick_ms, 0)
	_last_tick_ms = now_ms
	_punch.tick(delta_ms)
	if _punch.is_success():
		_finish_ok()
		return
	if _punch.is_terminal():
		_fail("打洞失败 state=%d" % _punch.get_state())
		return
	create_timer(0.02).timeout.connect(_poll_loop)

func _finish_ok() -> void:
	if _done:
		return
	_done = true
	var validated: Dictionary = _punch.get_validated_endpoint()
	var candidate: Dictionary = _punch.get_validated_candidate()
	var target: Dictionary = candidate.get("probe_target", {})
	var text: String = "OK bidirectional rtt=%dms validated=%s:%d target=%s:%d owns=%d" % [
		_punch.get_validated_rtt_ms(),
		str(validated.get("address", "")), int(validated.get("port", 0)),
		str(target.get("address", "")), int(target.get("port", 0)),
		1 if _punch.owns_socket() else 0,
	]
	_write_text(_result_path, text)
	print("HOST_OK %s" % text)
	quit(0)

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_text(_result_path, "FAIL: %s" % reason)
	printerr("HOST_FAIL: %s" % reason)
	quit(1)

func _candidate(path: int, address: String, port: int, observed_address: String = "", observed_port: int = 0) -> RendezvousContract.Candidate:
	var c: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	c.path = path
	c.address = address
	c.port = port
	c.observed_address = observed_address
	c.observed_port = observed_port
	return c

func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("HOST_FAIL: 无法写 %s" % path)
		return
	file.store_string(text)
	file.close()
