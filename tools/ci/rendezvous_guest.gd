extends SceneTree

## Rendezvous E2E —— Guest 端真进程（由 tools/ci/rendezvous_e2e.py 拉起，不单独跑）。
##
## 与 rendezvous_host.gd 配对。Guest 必须在 Host 已注册之后再注册，
## 否则服务端会回 SESSION_NOT_FOUND（编排脚本用 .ready marker 保证顺序）。
##
## 本进程用**真实 UDP** 注册 Guest，拿到自己的 observed endpoint 与 Host 的候选。
## **不要求 NAT 打洞成功** —— 9.2.1 只证明连接信息能真实交换。
##
## 用法：godot --headless --path . --script res://tools/ci/rendezvous_guest.gd -- <port> <room_id> <ticket> <result_file>

const TIMEOUT_MS: int = 30000

var _port: int = RendezvousClient.DEFAULT_PORT
var _room_id: String = ""
var _ticket: String = ""
var _result_path: String = ""
var _client: RendezvousClient = null
var _done: bool = false
var _deadline: int = 0
var _attempts: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		printerr("RV_GUEST_FAIL -: 缺少 port / room_id / ticket / result_file")
		quit(1)
		return
	_port = int(args[0])
	_room_id = args[1]
	_ticket = args[2]
	_result_path = args[3]
	_run.call_deferred()

func _run() -> void:
	_client = RendezvousClient.new()
	var identity: RendezvousContract.SessionIdentity = RendezvousContract.make_identity(
		_room_id,
		_ticket,
		GameLaunch.NET_PROTOCOL,
		RendezvousContract.Role.GUEST
	)
	## Guest 的候选：与 Host 不同的地址，便于断言「收到的不是自己那份」。
	var candidates: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.LAN_IPV4
	candidate.address = "127.0.0.1"
	candidate.port = RendezvousClient.DEFAULT_PORT
	candidates.append(candidate)

	if not _client.begin("127.0.0.1", _port, identity, candidates):
		_fail("begin 失败（server 未起？）")
		return
	_wait()

func _wait() -> void:
	if _done:
		return
	if _deadline == 0:
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	_client.poll()
	_client.tick(0.05)

	if _client.get_state() == RendezvousClient.State.FAILED:
		_fail("客户端进入 FAILED（error=%s detail=%s）" % [
			RendezvousContract.error_name(_client.last_error()), _client.last_detail()
		])
		return
	if _client.get_state() == RendezvousClient.State.TIMEOUT:
		_fail("客户端超时")
		return
	if _client.get_state() == RendezvousClient.State.CANDIDATES:
		_finish_ok()
		return
	if Time.get_ticks_msec() > _deadline:
		_fail("超时（state=%d）" % int(_client.get_state()))
		return
	create_timer(0.05).timeout.connect(_wait)

func _finish_ok() -> void:
	var session: RendezvousContract.SessionState = _client.get_session()
	if session == null:
		_fail("session 为空")
		return
	if not session.has_local_observed_endpoint():
		_fail("没有拿到 server observed endpoint")
		return
	if session.remote_candidates.is_empty():
		_fail("没有收到 Host 的候选")
		return
	var remote: RendezvousContract.Candidate = session.remote_candidates[0]
	if remote.address.is_empty() or remote.port < 1:
		_fail("Host 候选不可用：%s:%d" % [remote.address, remote.port])
		return
	if session.remote_nonce.is_empty():
		_fail("没有收到 Host 的 nonce")
		return
	_done = true
	_write_result("OK observed=%s:%d remote=%s:%d remote_nonce=%s" % [
		session.local_observed_address,
		session.local_observed_port,
		remote.address,
		remote.port,
		RendezvousContract.nonce_summary(session.remote_nonce),
	])
	print("RV_GUEST_OK observed=%s:%d" % [session.local_observed_address, session.local_observed_port])
	_client.close()
	quit(0)

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_result("FAIL: %s" % reason)
	printerr("RV_GUEST_FAIL: %s" % reason)
	quit(1)

func _write_result(text: String) -> void:
	var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		printerr("RV_GUEST_FAIL: 无法写结果文件 %s" % _result_path)
		return
	file.store_string(text)
	file.close()
