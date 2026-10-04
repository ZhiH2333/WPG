extends SceneTree

## LAN E2E 编排（Multiplayer 冻结前的真双进程回归）。
##
## 已有 lobby 测试全是单进程直接打状态机（tests/integration/lobby_net_test.gd 顶部写明：单进程里
## 不跑两个 peer，也不靠 RPC 真发包）。本测试补上唯一缺失的一环：拉起**两个真实
## Godot 进程**（Host / Guest），走真实 ENet + 真实 RPC，覆盖：
##   full        —— 握手落座 / 未 READY 不允许开局 / Ready / Guest 改角色清 Ready /
##                  Host 改 Arena 清 Guest Ready / Start -> STARTING
##   disconnect  —— Guest 断线，Host 释放座位
##   host_closed —— Host 关服，Guest 收到 host closed
##
## 跑法：godot --headless --path . --script res://tools/e2e/lan/run.gd --quit
## 通过输出 LAN_E2E_OK；失败逐条 LAN_E2E_FAIL 并返回非 0。
##
## 为什么读文件而不是抓 stdout：两个 peer 必须并发运行，阻塞式 OS.execute 做不到；
## 所以 peer 把结论写进 result 文件，编排方轮询进程退出后再读。

## 超时留足余量，但三个 step 的最坏情况必须明显小于 smoke.py 给单个测试的 180s 上限：
## peer 自己 30s 就会写 FAIL 退出，这里 35s 只是兜底「进程崩了没写结果」。
const PEER_TIMEOUT_MS: int = 35000
const BOOT_TIMEOUT_MS: int = 15000
const STEPS := ["full", "disconnect", "host_closed"]
const HOST_SCRIPT: String = "tools/e2e/lan/host.gd"
const GUEST_SCRIPT: String = "tools/e2e/lan/guest.gd"

var _failures: PackedStringArray = PackedStringArray()
var _godot: String = ""
var _root: String = ""
var _out_dir: String = ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_godot = OS.get_executable_path()
	_root = ProjectSettings.globalize_path("res://")
	_out_dir = ProjectSettings.globalize_path("res://build/logs/e2e/lan_e2e")
	DirAccess.make_dir_recursive_absolute(_out_dir)

	for step: String in STEPS:
		await _run_step(step)

	if _failures.is_empty():
		print("LAN_E2E_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("LAN_E2E_FAIL: %s" % failure)
	quit(1)

## 一个 step：先起 Host，等它写出 .ready（监听已建立）再起 Guest，避免抢跑。
func _run_step(step: String) -> void:
	var host_result: String = _out_dir.path_join("%s_host.result" % step)
	var guest_result: String = _out_dir.path_join("%s_guest.result" % step)
	var host_ready: String = host_result + ".ready"
	## 协议 6：Host 还会写出 invite（含 ticket），Guest 必须先读到它才能进房。
	var host_invite: String = host_result + ".invite"
	_remove(host_result)
	_remove(guest_result)
	_remove(host_ready)
	_remove(host_invite)

	var host_pid: int = _spawn(HOST_SCRIPT, step, host_result, "%s_host" % step)
	if host_pid <= 0:
		_failures.append("%s: 无法启动 Host 进程" % step)
		return

	if not await _wait_for_file(host_ready, BOOT_TIMEOUT_MS):
		_terminate(host_pid)
		_failures.append("%s: Host 未在 %dms 内就绪（bind 失败？）" % [step, BOOT_TIMEOUT_MS])
		return

	var guest_pid: int = _spawn(GUEST_SCRIPT, step, guest_result, "%s_guest" % step)
	if guest_pid <= 0:
		_terminate(host_pid)
		_failures.append("%s: 无法启动 Guest 进程" % step)
		return

	await _wait_for_processes([host_pid, guest_pid], PEER_TIMEOUT_MS)

	_check("host", step, host_result)
	_check("guest", step, guest_result)

func _check(role: String, step: String, result_path: String) -> void:
	var text: String = _read(result_path)
	if text == "OK":
		return
	if text.is_empty():
		_failures.append("%s %s: 没有结果（进程超时 / 崩溃，日志见 build/logs/lan_e2e/）" % [step, role])
		return
	_failures.append("%s %s: %s" % [step, role, text])

# ---- 进程 ----

func _spawn(rel_script: String, step: String, result_path: String, tag: String) -> int:
	var script_path: String = _root.path_join(rel_script)
	if not FileAccess.file_exists(script_path):
		return -1
	var log_path: String = _out_dir.path_join("%s.log" % tag)
	## --log-file 必须给绝对路径：Godot 默认写 user://logs，在受限沙箱里日志轮转会
	## 直接 segfault（见 tools/wpg_common.py 的 godot_log_args 说明）。
	var args: PackedStringArray = PackedStringArray([
		"--headless",
		"--path", _root,
		"--log-file", log_path,
		"--script", script_path,
		"--", step, result_path,
	])
	return OS.create_process(_godot, args)

func _wait_for_processes(pids: Array, timeout_ms: int) -> void:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while true:
		var running: bool = false
		for pid: int in pids:
			if OS.is_process_running(pid):
				running = true
				break
		if not running:
			return
		if Time.get_ticks_msec() > deadline:
			for pid: int in pids:
				_terminate(pid)
			return
		await create_timer(0.1).timeout

func _wait_for_file(path: String, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() <= deadline:
		if FileAccess.file_exists(path):
			return true
		await create_timer(0.05).timeout
	return false

func _terminate(pid: int) -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)

# ---- 文件 ----

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text().strip_edges()
	file.close()
	return text

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
