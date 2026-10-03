extends SceneTree

## Rendezvous E2E —— Host 端真进程（由 tools/ci/rendezvous_e2e.py 拉起，不单独跑）。
##
## 放在 tools/ci/ 而不是 tests/：smoke.py 会把 tests/ 下所有 *.gd 都当测试跑一遍，
## peer helper 脚本被无参调用会直接失败。这里不是独立测试，不该被自动发现。
##
## 本进程只做一件事：用**真实 UDP** 向真实跑着的 rendezvous server 注册 Host，
## 拿到自己的 observed endpoint，然后等 Guest 出现并收到对端候选。
##
## **不要求两个 Godot 进程通过 NAT 直连** —— 本阶段（9.2.1）只证明
## 「公网 rendezvous 可以真实把双方连接信息交换出去」。
##
## 用法：godot --headless --path . --script res://tools/ci/rendezvous_host.gd -- <port> <room_id> <ticket> <result_file>

const TIMEOUT_MS: int = 30000

var _port: int = RendezvousClient.DEFAULT_PORT
var _room_id: String = ""
var _ticket: String = ""
var _result_path: String = ""
var _client: RendezvousClient = null
var _done: bool = false
var _deadline: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		printerr("RV_HOST_FAIL -: 缺少 port / room_id / ticket / result_file")
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
		RendezvousContract.Role.HOST
	)
	## 本端候选：E2E 里用回环地址，证明候选能被真实交换出去。
	var candidates: Array[RendezvousContract.Candidate] = []
	var candidate: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	candidate.path = LobbyPlayer.Path.LAN_IPV4
	candidate.address = "127.0.0.1"
	candidate.port = GameLaunch.NET_PORT
	candidates.append(candidate)

	if not _client.begin("127.0.0.1", _port, identity, candidates):
		_fail("begin 失败（server 未起？）")
		return
	## 注册包已发出：通知编排脚本可以起 Guest 了，避免抢跑。
	_write_marker(_result_path + ".ready")
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
	## 硬断言：必须拿到服务端观测到的本端端点，而不是本地自报地址。
	if not session.has_local_observed_endpoint():
		_fail("没有拿到 server observed endpoint")
		return
	## 硬断言：必须收到 Guest 的真实候选，且**不是**自己那份。
	if session.remote_candidates.is_empty():
		_fail("没有收到 Guest 的候选")
		return
	var remote: RendezvousContract.Candidate = session.remote_candidates[0]
	if remote.address.is_empty() or remote.port < 1:
		_fail("Guest 候选不可用：%s:%d" % [remote.address, remote.port])
		return
	if session.remote_nonce.is_empty():
		_fail("没有收到 Guest 的 nonce")
		return
	## 证据落盘（不含 ticket）。
	_done = true
	_write_result("OK observed=%s:%d remote=%s:%d remote_nonce=%s" % [
		session.local_observed_address,
		session.local_observed_port,
		remote.address,
		remote.port,
		RendezvousContract.nonce_summary(session.remote_nonce),
	])
	print("RV_HOST_OK observed=%s:%d" % [session.local_observed_address, session.local_observed_port])
	_client.close()
	quit(0)

func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_write_result("FAIL: %s" % reason)
	printerr("RV_HOST_FAIL: %s" % reason)
	quit(1)

func _write_result(text: String) -> void:
	var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
	if file == null:
		printerr("RV_HOST_FAIL: 无法写结果文件 %s" % _result_path)
		return
	file.store_string(text)
	file.close()

func _write_marker(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("ready")
	file.close()
