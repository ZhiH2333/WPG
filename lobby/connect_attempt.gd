extends RefCounted
class_name ConnectAttempt

## 单次「连一个 Host」的尝试状态对象（Phase 8 hardening）。
##
## 为什么单独存在：`join_invite()` 过去把候选循环、peer 生命周期、失败分类三件事
## 堆在 LobbyManager 里，导致 `client_connect()` 返回 true 就被当成「连接成功」。
## 那只是**本地 socket 创建成功**，不代表对端可达 —— ENet 对不可达地址同样返回 OK。
##
## 本对象只回答一件事：**这一次尝试（attempt）现在到哪一步了**。
## 因此它必须做到：
## - 只描述状态，**不持有 ENet peer**，不做 socket I/O，不依赖 SceneTree；
## - 所有 async 回调（connected / connection_failed / hello_ok / rejected / timeout）
##   都必须先出示 attempt_id；对不上的一律丢弃，绝不修改当前状态；
## - 换候选前由调用方保证旧 peer 已 close()，本对象只校验「当前是否还允许建连」。
##
## 典型竞态（必须被挡住）：
##   IPv4 attempt #1 -> IPv6 attempt #2 -> IPv4 #1 的延迟 callback 到达
##   若没有 attempt_id，就会把 #2 的状态改成 #1 的结果。

## 一次尝试的终态 / 中间态。调用方只按 Outcome 分支，不再自己 if 网络细节。
enum Outcome {
	## 还在进行中（未定论）。
	PENDING,
	## 真实连上并且握手通过 —— 唯一算成功的结果。
	CONNECTED,
	## 本次尝试超时（由调用方的计时器驱动 fail(TIMEOUT)）。
	CONNECT_TIMEOUT,
	## ENet 明确回报 connection_failed。
	CONNECTION_FAILED,
	## 本地 socket 创建失败（地址非法 / 端口被占）—— 同样是 CONNECTION_FAILED 语义，
	## 但保留独立原因码便于诊断。
	SOCKET_ERROR,
	## 协议号不符：**不换路径重试**。
	VERSION_MISMATCH,
	## ticket 被 Host 拒绝：**不换路径重试**。
	TICKET_REJECTED,
	## 用户 / 上层取消。
	CANCELLED,
}

## 会终止本次尝试的结果（含成功）。
const TERMINAL: Array[int] = [
	Outcome.CONNECTED,
	Outcome.CONNECT_TIMEOUT,
	Outcome.CONNECTION_FAILED,
	Outcome.SOCKET_ERROR,
	Outcome.VERSION_MISMATCH,
	Outcome.TICKET_REJECTED,
	Outcome.CANCELLED,
]

## 值得换下一个候选重试的结果。协议 / ticket 问题不在其中：同一间房换 IP 也没用。
const RETRYABLE: Array[int] = [
	Outcome.CONNECT_TIMEOUT,
	Outcome.CONNECTION_FAILED,
	Outcome.SOCKET_ERROR,
]

## attempt 的序号（1 起）。第一次尝试 = 1。所有回调必须核对这个值。
var attempt_id: int = 0
## 本 attempt 用的候选（ConnectionPath.Candidate）。可为 null（尚未绑定候选）。
var candidate: ConnectionPath.Candidate = null
## 候选在 plan 中的下标，供调用方推算「还有没有下一个」。
var candidate_index: int = -1
## 本次尝试携带的 guest ticket（Guest 侧凭据，不是 room ticket）。
var guest_ticket: String = ""
## 当前结果。
var outcome: int = Outcome.PENDING
## 详细失败原因（TicketReject 值 / 诊断文本），仅诊断用，调用方不应据此分支。
var detail: String = ""
## 已过秒数（由调用方 tick 累加，本对象不自己读时钟）。
var elapsed_sec: float = 0.0
## peer 是否已真实建连（收到 connected_to_server），但握手可能还没过。
var transport_connected: bool = false
## 握手是否已通过（hello_ok）。只有它为 true 且 transport_connected 才算 CONNECTED。
var handshake_ok: bool = false

## —— 建立 ——

func begin(
	id: int,
	target: ConnectionPath.Candidate,
	index: int,
	ticket: String
) -> void:
	attempt_id = id
	candidate = target
	candidate_index = index
	guest_ticket = ticket
	outcome = Outcome.PENDING
	detail = ""
	elapsed_sec = 0.0
	transport_connected = false
	handshake_ok = false

## —— 查询 ——

func is_pending() -> bool:
	return outcome == Outcome.PENDING

func is_terminal() -> bool:
	return TERMINAL.has(outcome)

func is_success() -> bool:
	return outcome == Outcome.CONNECTED

## 这个结果是否值得换下一个候选再试。
func is_retryable() -> bool:
	return RETRYABLE.has(outcome)

## 回调门禁：**每个 async callback 的第一行都必须调用它**。
## 返回 false = 这是旧 attempt 的延迟回调（或 attempt 已终结），调用方必须立刻 return。
func accepts(id: int) -> bool:
	if id != attempt_id:
		return false
	return outcome == Outcome.PENDING

## —— 事件（全部带 attempt_id 校验）——

## ENet 回报 connected_to_server。这只说明传输层通了，**不代表握手通过**。
func mark_transport_connected(id: int) -> bool:
	if not accepts(id):
		return false
	transport_connected = true
	return true

## 握手通过（rpc_hello_ok / seat_assigned）。这才是真正的 CONNECTED。
func mark_handshake_ok(id: int) -> bool:
	if not accepts(id):
		return false
	handshake_ok = true
	transport_connected = true
	outcome = Outcome.CONNECTED
	return true

## 本地 socket 创建失败。
func fail_socket(id: int, why: String = "") -> bool:
	return _fail(id, Outcome.SOCKET_ERROR, why)

## ENet 明确 connection_failed。
func fail_connection(id: int, why: String = "") -> bool:
	return _fail(id, Outcome.CONNECTION_FAILED, why)

## 超时（由调用方计时驱动）。
func fail_timeout(id: int) -> bool:
	return _fail(id, Outcome.CONNECT_TIMEOUT, "timeout")

## 协议不符 —— 终态且不可重试。
func fail_version_mismatch(id: int, why: String = "") -> bool:
	return _fail(id, Outcome.VERSION_MISMATCH, why)

## ticket 被拒 —— 终态且不可重试。
func fail_ticket_rejected(id: int, why: String = "") -> bool:
	return _fail(id, Outcome.TICKET_REJECTED, why)

## 上层取消。
func cancel(id: int) -> bool:
	return _fail(id, Outcome.CANCELLED, "cancelled")

## 推进计时。返回 true = 本次调用触发了超时（调用方据此 close peer 并换候选）。
func tick(id: int, delta_sec: float, timeout_sec: float) -> bool:
	if not accepts(id):
		return false
	elapsed_sec += maxf(delta_sec, 0.0)
	if timeout_sec > 0.0 and elapsed_sec >= timeout_sec:
		fail_timeout(id)
		return true
	return false

func _fail(id: int, result: int, why: String) -> bool:
	if not accepts(id):
		return false
	outcome = result
	detail = why
	return true

## 诊断用一行摘要（不含 ticket —— 凭据不进日志）。
func describe() -> String:
	var where: String = "no-candidate"
	if candidate != null:
		where = "%s:%d (%s)" % [
			candidate.address,
			candidate.port,
			ConnectionPath.path_name(candidate.path),
		]
	return "#%d %s -> %s%s" % [
		attempt_id,
		where,
		outcome_name(outcome),
		(" [%s]" % detail) if not detail.is_empty() else "",
	]

## Outcome -> 稳定小写名（日志 / 未来 UI 文案用）。
static func outcome_name(value: int) -> String:
	match value:
		Outcome.CONNECTED:
			return "connected"
		Outcome.CONNECT_TIMEOUT:
			return "connect_timeout"
		Outcome.CONNECTION_FAILED:
			return "connection_failed"
		Outcome.SOCKET_ERROR:
			return "socket_error"
		Outcome.VERSION_MISMATCH:
			return "version_mismatch"
		Outcome.TICKET_REJECTED:
			return "ticket_rejected"
		Outcome.CANCELLED:
			return "cancelled"
		_:
			return "pending"
