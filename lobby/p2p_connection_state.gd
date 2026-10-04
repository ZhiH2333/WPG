extends RefCounted
class_name P2PConnectionState

## P2P 连接状态机（Phase 9.1）。
##
## 职责边界（严格）：
## - **只描述状态**。不创建 ENet、不做 socket I/O、不持有 MultiplayerPeer。
## - 不依赖 SceneTree、不依赖 UI、不依赖 Combat。
## - 可在单进程 headless 下单测（本文件没有任何引擎副作用）。
##
## 它回答的问题只有：「这次 P2P 连接现在处于哪个阶段，能不能接受这个事件」。
## 真正的建连 / 打洞 / 握手由上层（P2PConnection -> LobbyNet）执行。
##
## 本阶段（9.1）**不实现 NAT hole punching**：DIRECT_CONNECTING 只是表达
## 「正在尝试把 ENet 接到直连路径」，不代表打洞已经能穿过 NAT。

## 状态。终态 = CONNECTED / FAILED / TIMEOUT / TICKET_REJECTED / VERSION_MISMATCH / DIRECT_ENET_FAILED / DIRECT_PATH_FAILED。
## Phase 9.2 新增：
##   DIRECT_PROBING           - UDP hole punch 探测中
##   DIRECT_PATH_ESTABLISHED  - 双向 UDP probe 成功，已有 validated direct path
##   DIRECT_ENET_CONNECTING   - 在 validated path 上发起 ENet 连接
##   DIRECT_ENET_FAILED       - ENet 连接失败（UDP path 可用但 ENet 握手失败）
## Phase 9.1 兼容（保留）：
##   DIRECT_CONNECTING        - 直接 ENet 直连尝试中（不做 hole punch）
##   DIRECT_PATH_FAILED       - hole punch 失败 / 无可用路径
enum State {
	DISCONNECTED,
	RENDEZVOUS_CONNECTING,
	RENDEZVOUS_REGISTERED,
	CANDIDATES_RECEIVED,
	DIRECT_PROBING,
	DIRECT_PATH_ESTABLISHED,
	DIRECT_ENET_CONNECTING,
	DIRECT_ENET_FAILED,
	DIRECT_CONNECTING,
	HANDSHAKING,
	CONNECTED,
	FAILED,
	TIMEOUT,
	TICKET_REJECTED,
	VERSION_MISMATCH,
	DIRECT_PATH_FAILED,
}

## 事件。非法事件 -> transition 返回 false，且**状态不变**。
## Phase 9.2 新增：
##   BEGIN_DIRECT_PROBING    - 开始 UDP hole punch
##   DIRECT_PATH_OK          - 双向 probe 成功
##   DIRECT_PATH_FAILED      - hole punch 失败
##   BEGIN_DIRECT_ENET       - 在 validated path 上发起 ENet
##   DIRECT_ENET_CONNECTED   - ENet connected_to_server
##   DIRECT_ENET_FAILED      - ENet connection_failed
## Phase 9.1 兼容（保留）：
##   BEGIN_DIRECT_ATTEMPT    - 直接进入 ENet 直连（不做 hole punch）
enum Event {
	BEGIN_RENDEZVOUS,
	RENDEZVOUS_REGISTERED,
	CANDIDATES_RECEIVED,
	BEGIN_DIRECT_PROBING,
	DIRECT_PATH_OK,
	DIRECT_PATH_FAILED,
	BEGIN_DIRECT_ENET,
	DIRECT_ENET_CONNECTED,
	DIRECT_ENET_FAILED,
	BEGIN_DIRECT_ATTEMPT,
	DIRECT_CONNECTED,
	DIRECT_FAILED,
	HANDSHAKE_OK,
	TICKET_REJECTED,
	VERSION_MISMATCH,
	TIMEOUT,
	CANCEL,
	RESET,
}

## 明确的四级超时（F）：各阶段独立预算，不是一个数字覆盖全部。
const RENDEZVOUS_TIMEOUT_SEC: float = 5.0
const DIRECT_PROBE_TIMEOUT_SEC: float = 4.0
const DIRECT_ENET_TIMEOUT_SEC: float = 4.0
const OVERALL_JOIN_TIMEOUT_SEC: float = 12.0

## 状态变化：from -> to，附带触发事件（UI / 日志只读）。
signal state_changed(from: int, to: int, event: int)

var _state: State = State.DISCONNECTED
## 触发当前状态的事件（诊断用）。
var _last_event: int = Event.RESET
## 已收到 / 已发出的候选数量快照（只读统计，不持有候选内容本身）。
var _local_candidate_count: int = 0
var _remote_candidate_count: int = 0
## 直连尝试次数（attempt generation 语义与 ConnectAttempt 对齐）。
var _direct_attempts: int = 0
## Hole punch probe 尝试次数。
var _direct_probe_attempts: int = 0

# ---- 查询 ----

func get_state() -> State:
	return _state

func last_event() -> int:
	return _last_event

func is_terminal() -> bool:
	match _state:
		State.CONNECTED, State.FAILED, State.TIMEOUT, State.TICKET_REJECTED, State.VERSION_MISMATCH, State.DIRECT_PATH_FAILED, State.DIRECT_ENET_FAILED:
			return true
		_:
			return false

## 是否已建立连接。
## 注意：不能叫 is_connected() —— Object 已有同名方法（信号连接查询），
## 重名会让调用方在静态类型下解析失败。
func is_connection_established() -> bool:
	return _state == State.CONNECTED

## 是否正在进行中（未终结且已离开 DISCONNECTED）。
func is_active() -> bool:
	return _state != State.DISCONNECTED and not is_terminal()

func direct_attempts() -> int:
	return _direct_attempts

## Hole punch 探测尝试次数（每次 BEGIN_DIRECT_PROBING 累加一次）。
func direct_probe_attempts() -> int:
	return _direct_probe_attempts

func remote_candidate_count() -> int:
	return _remote_candidate_count

func local_candidate_count() -> int:
	return _local_candidate_count

## —— 事件入口 ——

## 唯一的状态推进入口。非法转换返回 false 且**不改状态**（确定性的关键）。
func transition(event: Event) -> bool:
	var next: int = _next_state(_state, event)
	if next < 0:
		return false
	var from: State = _state
	_state = next as State
	_last_event = event
	_apply_side_effects(event)
	state_changed.emit(int(from), int(_state), int(event))
	return true

## 便捷封装：本机候选已就绪。
func set_local_candidate_count(count: int) -> void:
	_local_candidate_count = maxi(count, 0)

## 便捷封装：收到对端候选。
func set_remote_candidate_count(count: int) -> void:
	_remote_candidate_count = maxi(count, 0)

## 重置回初始状态（可重新发起一次 join）。
func reset() -> void:
	var from: State = _state
	_state = State.DISCONNECTED
	_last_event = Event.RESET
	_local_candidate_count = 0
	_remote_candidate_count = 0
	_direct_attempts = 0
	_direct_probe_attempts = 0
	if from != State.DISCONNECTED:
		state_changed.emit(int(from), int(_state), int(Event.RESET))

# ---- 转换表 ----

## 纯函数转换表：返回 -1 = 非法转换。
## 确定性：同样的 (state, event) 永远得到同样的结果，不读时钟、不读环境。
func _next_state(state: int, event: int) -> int:
	## RESET 任意状态可用。
	if event == Event.RESET:
		return State.DISCONNECTED
	## CANCEL 只在「进行中」有意义（终态 / DISCONNECTED 上取消是非法）。
	match event:
		Event.CANCEL:
			if state == State.DISCONNECTED or _is_terminal_state(state):
				return -1
			return State.FAILED
		Event.TIMEOUT:
			if state == State.DISCONNECTED or _is_terminal_state(state):
				return -1
			return State.TIMEOUT
		Event.VERSION_MISMATCH:
			if state == State.DISCONNECTED or _is_terminal_state(state):
				return -1
			return State.VERSION_MISMATCH
		Event.TICKET_REJECTED:
			## ticket 有**两个**校验点，所以任一进行中的阶段都可能被拒：
			##   1) Phase 9.2.1：rendezvous 服务端在 REGISTER 时按 session ticket 比对；
			##   2) Phase 8/9：Host 在 protocol 6 握手时做最终权威校验。
			## 只要不是 DISCONNECTED / 终态，都可能收到 TICKET_REJECTED。
			if state == State.DISCONNECTED or _is_terminal_state(state):
				return -1
			return State.TICKET_REJECTED

	match state:
		State.DISCONNECTED:
			if event == Event.BEGIN_RENDEZVOUS:
				return State.RENDEZVOUS_CONNECTING
		State.RENDEZVOUS_CONNECTING:
			if event == Event.RENDEZVOUS_REGISTERED:
				return State.RENDEZVOUS_REGISTERED
		State.RENDEZVOUS_REGISTERED:
			if event == Event.CANDIDATES_RECEIVED:
				return State.CANDIDATES_RECEIVED
		State.CANDIDATES_RECEIVED:
			## Phase 9.1 兼容：BEGIN_DIRECT_ATTEMPT 直接进 ENet 直连（不做 hole punch）
			if event == Event.BEGIN_DIRECT_ATTEMPT:
				return State.DIRECT_CONNECTING
			## Phase 9.2：开始 hole punch
			if event == Event.BEGIN_DIRECT_PROBING:
				return State.DIRECT_PROBING
		State.DIRECT_PROBING:
			if event == Event.DIRECT_PATH_OK:
				return State.DIRECT_PATH_ESTABLISHED
			if event == Event.DIRECT_PATH_FAILED:
				return State.DIRECT_PATH_FAILED
			if event == Event.TIMEOUT:
				return State.TIMEOUT
		State.DIRECT_PATH_ESTABLISHED:
			if event == Event.BEGIN_DIRECT_ENET:
				return State.DIRECT_ENET_CONNECTING
			if event == Event.DIRECT_PATH_FAILED:
				return State.DIRECT_PATH_FAILED
		State.DIRECT_ENET_CONNECTING:
			if event == Event.DIRECT_ENET_CONNECTED:
				return State.HANDSHAKING
			if event == Event.DIRECT_ENET_FAILED:
				return State.DIRECT_ENET_FAILED
			if event == Event.TIMEOUT:
				return State.TIMEOUT
		State.DIRECT_ENET_FAILED:
			## ENet 直连失败可重试 hole punch（换候选）或终结
			if event == Event.BEGIN_DIRECT_PROBING:
				return State.DIRECT_PROBING
			if event == Event.DIRECT_PATH_FAILED:
				return State.DIRECT_PATH_FAILED
			if event == Event.TIMEOUT:
				return State.TIMEOUT
		State.DIRECT_CONNECTING:
			if event == Event.DIRECT_CONNECTED:
				return State.HANDSHAKING
			if event == Event.DIRECT_FAILED:
				## 直连失败允许**再次尝试**（下一个候选）；不直接终结，
				## 由上层决定是重试还是 TIMEOUT / CANCEL。
				return State.DIRECT_CONNECTING
			if event == Event.BEGIN_DIRECT_ATTEMPT:
				## 换下一个候选再试：留在 DIRECT_CONNECTING，只累加尝试计数。
				return State.DIRECT_CONNECTING
		State.HANDSHAKING:
			if event == Event.HANDSHAKE_OK:
				return State.CONNECTED
		_:
			pass
	return -1

func _apply_side_effects(event: int) -> void:
	if event == Event.BEGIN_DIRECT_ATTEMPT:
		_direct_attempts += 1
	if event == Event.BEGIN_DIRECT_PROBING:
		_direct_probe_attempts += 1

func _is_terminal_state(state: int) -> bool:
	match state:
		State.CONNECTED, State.FAILED, State.TIMEOUT, State.TICKET_REJECTED, State.VERSION_MISMATCH, State.DIRECT_PATH_FAILED, State.DIRECT_ENET_FAILED:
			return true
		_:
			return false

# ---- 命名（UI / 日志 / 测试断言用）----

static func state_name(value: int) -> String:
	match value:
		State.RENDEZVOUS_CONNECTING:
			return "rendezvous_connecting"
		State.RENDEZVOUS_REGISTERED:
			return "rendezvous_registered"
		State.CANDIDATES_RECEIVED:
			return "candidates_received"
		State.DIRECT_PROBING:
			return "direct_probing"
		State.DIRECT_PATH_ESTABLISHED:
			return "direct_path_established"
		State.DIRECT_ENET_CONNECTING:
			return "direct_enet_connecting"
		State.DIRECT_ENET_FAILED:
			return "direct_enet_failed"
		State.DIRECT_CONNECTING:
			return "direct_connecting"
		State.HANDSHAKING:
			return "handshaking"
		State.CONNECTED:
			return "connected"
		State.FAILED:
			return "failed"
		State.TIMEOUT:
			return "timeout"
		State.TICKET_REJECTED:
			return "ticket_rejected"
		State.VERSION_MISMATCH:
			return "version_mismatch"
		_:
			return "disconnected"

static func event_name(value: int) -> String:
	match value:
		Event.BEGIN_RENDEZVOUS:
			return "begin_rendezvous"
		Event.RENDEZVOUS_REGISTERED:
			return "rendezvous_registered"
		Event.CANDIDATES_RECEIVED:
			return "candidates_received"
		Event.BEGIN_DIRECT_PROBING:
			return "begin_direct_probing"
		Event.DIRECT_PATH_OK:
			return "direct_path_ok"
		Event.DIRECT_PATH_FAILED:
			return "direct_path_failed"
		Event.BEGIN_DIRECT_ENET:
			return "begin_direct_enet"
		Event.DIRECT_ENET_CONNECTED:
			return "direct_enet_connected"
		Event.DIRECT_ENET_FAILED:
			return "direct_enet_failed"
		Event.BEGIN_DIRECT_ATTEMPT:
			return "begin_direct_attempt"
		Event.DIRECT_CONNECTED:
			return "direct_connected"
		Event.DIRECT_FAILED:
			return "direct_failed"
		Event.HANDSHAKE_OK:
			return "handshake_ok"
		Event.TICKET_REJECTED:
			return "ticket_rejected"
		Event.VERSION_MISMATCH:
			return "version_mismatch"
		Event.TIMEOUT:
			return "timeout"
		Event.CANCEL:
			return "cancel"
		_:
			return "reset"
