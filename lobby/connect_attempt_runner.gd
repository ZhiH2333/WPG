extends RefCounted
class_name ConnectAttemptRunner

## 候选回退驱动器（Phase 8 hardening）。
##
## 职责：按 `ConnectionPath` 的候选顺序，**串行**推进 attempt；任意时刻至多一个 attempt、
## 至多一个 active peer。它只做编排与分类，**不创建 ENet peer、不做 socket I/O**
## —— 真正的建连由注入的 `transport` 回调执行（生产环境是 LobbyNet，测试是假实现）。
##
## 为什么需要它：`join_invite()` 的关键错误是把 `create_client() == OK` 当成连接成功。
## ENet 对不可达地址也返回 OK，于是「第一个候选就 return」导致 IPv6 / WAN 回退是死代码。
## 这里的正确语义是：
##
##   candidate[0] -> 建连 -> 等**真实结果**
##       connected + handshake 成功 => DONE
##       connection_failed          => close peer -> candidate[1]
##       timeout                    => close peer -> candidate[1]
##       version_mismatch           => 停止（换 IP 也没用）
##       ticket_rejected            => 停止（换 IP 也没用）
##
## 所有结果都必须带着 attempt_id 回来；对不上的延迟回调一律丢弃。

## 超时常量集中定义（F）：三个阶段各有自己的预算，**不允许一个数字覆盖全部**。
const RENDEZVOUS_TIMEOUT_SEC: float = 5.0
const DIRECT_ATTEMPT_TIMEOUT_SEC: float = 4.0
const OVERALL_JOIN_TIMEOUT_SEC: float = 12.0

## 结果回调：一次尝试有了定论。
signal attempt_finished(attempt: ConnectAttempt)
## 整个 join 结束（成功或最终失败）。
signal exhausted(attempt: ConnectAttempt, reason: String)
## 切换到下一个候选，准备建连（诊断 / UI 文案用）。
signal candidate_started(attempt: ConnectAttempt)

var _plan: ConnectionPath = null
var _ticket: String = ""
var _cursor: int = 0
var _attempt: ConnectAttempt = null
var _generation: int = 0
var _finished: bool = false
var _overall_elapsed: float = 0.0
var _final: ConnectAttempt = null
var _final_reason: String = ""
## 注入的传输层。返回 true = 已发起建连（**不等于连上**）。
## 签名: func(address: String, port: int, ticket: String) -> bool
var _connect_fn: Callable = Callable()
## 注入的关闭函数：**换候选前必须调用**，保证 SceneTree 只有一个 peer。
var _close_fn: Callable = Callable()

## —— 生命周期 ——

## plan 为候选顺序；connect_fn / close_fn 由调用方注入（生产 = LobbyManager -> LobbyNet）。
func begin(
	plan: ConnectionPath,
	ticket: String,
	connect_fn: Callable,
	close_fn: Callable
) -> bool:
	if plan == null or plan.is_empty():
		_final_reason = "no_candidates"
		_finished = true
		exhausted.emit(null, _final_reason)
		return false
	if not connect_fn.is_valid() or not close_fn.is_valid():
		_final_reason = "no_transport"
		_finished = true
		exhausted.emit(null, _final_reason)
		return false
	_plan = plan
	_ticket = ticket
	_cursor = 0
	_generation = 0
	_attempt = null
	_finished = false
	_overall_elapsed = 0.0
	_final = null
	_final_reason = ""
	_connect_fn = connect_fn
	_close_fn = close_fn
	return _start_next()

## 当前 attempt（可能为 null）。
func current_attempt() -> ConnectAttempt:
	return _attempt

## 当前 attempt_id（无尝试时 0）。回调方必须拿它来核对。
func current_attempt_id() -> int:
	return _attempt.attempt_id if _attempt != null else 0

func is_finished() -> bool:
	return _finished

func is_success() -> bool:
	return _final != null and _final.is_success()

func final_attempt() -> ConnectAttempt:
	return _final

func final_reason() -> String:
	return _final_reason

## 已尝试过的候选数量。
func attempts_made() -> int:
	return _generation

## —— 结果入口（全部必须带 attempt_id）——

## 传输层真实连上（connected_to_server）。注意：**还没握手，不算成功**。
func notify_transport_connected(attempt_id: int) -> bool:
	if _attempt == null:
		return false
	return _attempt.mark_transport_connected(attempt_id)

## 握手通过。这才是 DONE。
func notify_handshake_ok(attempt_id: int) -> bool:
	if _attempt == null:
		return false
	if not _attempt.mark_handshake_ok(attempt_id):
		return false
	_finish(_attempt, "connected")
	return true

## ENet connection_failed / socket 创建失败 -> 值得换候选。
func notify_connection_failed(attempt_id: int, why: String = "") -> bool:
	return _fail_and_maybe_retry(attempt_id, OutcomeKind.CONNECTION_FAILED, why)

## 协议不符 -> 终态，不换候选。
func notify_version_mismatch(attempt_id: int, why: String = "") -> bool:
	return _fail_and_maybe_retry(attempt_id, OutcomeKind.VERSION_MISMATCH, why)

## ticket 被拒 -> 终态，不换候选。
func notify_ticket_rejected(attempt_id: int, why: String = "") -> bool:
	return _fail_and_maybe_retry(attempt_id, OutcomeKind.TICKET_REJECTED, why)

## 上层取消整个 join：关 peer、终结当前 attempt、不再重试。
func cancel() -> void:
	if _finished:
		return
	_generation += 1
	if _attempt != null:
		_attempt.cancel(_attempt.attempt_id)
	## 取消也要保证不留 active peer。
	_transport_close()
	_finish(_attempt, "cancelled")

## 推进计时（总超时 + 单次尝试超时）。由调用方每帧调用。
func tick(delta_sec: float) -> void:
	if _finished:
		return
	_overall_elapsed += maxf(delta_sec, 0.0)
	if _overall_elapsed >= OVERALL_JOIN_TIMEOUT_SEC:
		_generation += 1
		if _attempt != null:
			_attempt.fail_timeout(_attempt.attempt_id)
		_transport_close()
		_finish(_attempt, "overall_timeout")
		return
	if _attempt == null:
		return
	var id: int = _attempt.attempt_id
	if _attempt.tick(id, delta_sec, DIRECT_ATTEMPT_TIMEOUT_SEC):
		## 单次尝试超时：先关 peer 再换候选，绝不并发两个 peer。
		_transport_close()
		_after_attempt(_attempt)

## —— 内部 ——

## 结果分类（避免直接依赖 ConnectAttempt.Outcome 的枚举顺序）。
enum OutcomeKind { CONNECTION_FAILED, VERSION_MISMATCH, TICKET_REJECTED }

func _fail_and_maybe_retry(attempt_id: int, kind: OutcomeKind, why: String) -> bool:
	if _attempt == null:
		return false
	var accepted: bool = false
	match kind:
		OutcomeKind.CONNECTION_FAILED:
			accepted = _attempt.fail_connection(attempt_id, why)
		OutcomeKind.VERSION_MISMATCH:
			accepted = _attempt.fail_version_mismatch(attempt_id, why)
		OutcomeKind.TICKET_REJECTED:
			accepted = _attempt.fail_ticket_rejected(attempt_id, why)
	if not accepted:
		## 延迟回调 / 旧 attempt：直接丢弃，绝不改状态。
		return false
	## 失败前先确保 peer 已关，避免残留。
	_transport_close()
	_after_attempt(_attempt)
	return true

## 一个 attempt 定论后的统一收口：成功 / 不可重试 / 还能重试。
func _after_attempt(attempt: ConnectAttempt) -> void:
	attempt_finished.emit(attempt)
	if attempt.is_success():
		_finish(attempt, "connected")
		return
	if not attempt.is_retryable():
		## VERSION_MISMATCH / TICKET_REJECTED / CANCELLED：换 IP 也解决不了。
		_finish(attempt, ConnectAttempt.outcome_name(attempt.outcome))
		return
	if not _start_next():
		_finish(attempt, "all_candidates_failed")

## 取下一个候选并建连。返回 false = 没有候选可试了。
func _start_next() -> bool:
	while true:
		var candidate: ConnectionPath.Candidate = _plan.select_next_path(_cursor)
		if candidate == null:
			return false
		_cursor += 1
		_generation += 1
		var attempt: ConnectAttempt = ConnectAttempt.new()
		attempt.begin(_generation, candidate, _cursor - 1, _ticket)
		_attempt = attempt
		candidate_started.emit(attempt)
		## 建连前必须保证没有旧 peer 残留（SceneTree 只允许一个 peer）。
		_transport_close()
		var started: bool = bool(_connect_fn.call(candidate.address, candidate.port, _ticket))
		if started:
			return true
		## create_client 本身失败（地址非法 / 端口占用）：算 SOCKET_ERROR，换下一个候选。
		attempt.fail_socket(attempt.attempt_id, "create_client_failed")
		_transport_close()
		attempt_finished.emit(attempt)
		## 继续循环试下一个候选。
	return false

func _transport_close() -> void:
	if _close_fn.is_valid():
		_close_fn.call()

func _finish(attempt: ConnectAttempt, reason: String) -> void:
	if _finished:
		return
	_finished = true
	_final = attempt
	_final_reason = reason
	## 失败收尾一定不留 active peer。
	if attempt == null or not attempt.is_success():
		_transport_close()
	exhausted.emit(attempt, reason)
