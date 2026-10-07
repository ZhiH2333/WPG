extends RefCounted
class_name RendezvousClient

## Rendezvous 客户端（Phase 9.2.2）。
##
## 职责：
## - 连接 rendezvous server（**UDP，非 ENet**）
## - REGISTER 并发送 local candidates
## - 接收 REGISTERED（自己的 observed endpoint）
## - 接收 PEER_READY / CANDIDATES（对端候选 + 对端 observed endpoint）
## - 转换为 RendezvousContract，通知 P2PConnection
##
## 严格禁止：
## - 创建 ENetMultiplayerPeer
## - 改 SceneTree.multiplayer
## - 直接控制 Combat
## - 代替 LobbyNet / ConnectionPath
##
## 分层保持：
##   LobbyManager -> P2PConnection -> RendezvousClient -> RendezvousContract
##   P2PConnection -> ConnectionPath -> LobbyNet -> ENet
##
## 用 PacketPeerUDP（与 LanBeacon 同源）而不是 ENet：rendezvous 只交换信息，
## 不承载游戏流量，也不该占用 SceneTree 上唯一那个 peer。
##
## 关键架构变更（9.2.2）：**不再自建 UDP socket**。改为接收外部传入的共享 PacketPeerUDP，
## 与 P2PHolePunch 复用同一个端点，保证 server observed endpoint 就是 hole punch 真实使用的端点。

## 注册成功，拿到自己的 observed endpoint（可能为空 = 服务端没观测到）。
signal registered(session_id: String, observed_address: String, observed_port: int)
## 对端已就绪（候选可能还没到）。
signal peer_ready(remote_nonce: String, remote_role: int)
## 收到对端候选与 observed endpoint。
signal candidates_received(candidates: Array, remote_nonce: String, remote_role: int)
## 服务端返回的可诊断错误。
signal server_error(error_code: int, detail: String)
## 本地超时（注册 / 整体）。
signal timed_out(reason: String)

enum State { IDLE, REGISTERING, REGISTERED, CANDIDATES, FAILED, TIMEOUT }

## 默认 rendezvous 端口。与 17777（游戏）/ 17778（LAN beacon）分开，避免打架。
const DEFAULT_PORT: int = 17779

var _udp: PacketPeerUDP = null
var _state: State = State.IDLE
var _host: String = ""
var _port: int = DEFAULT_PORT
var _identity: RendezvousContract.SessionIdentity = null
var _local_candidates: Array[RendezvousContract.Candidate] = []
var _session: RendezvousContract.SessionState = null
var _elapsed_sec: float = 0.0
var _last_error: int = RendezvousContract.ErrorCode.NONE
var _last_detail: String = ""
var _owns_udp: bool = false  ## 是否拥有 UDP 生命周期（外部传入则为 false）
var _paused: bool = false  ## hole punch 期间暂停 poll，避免抢占共享 socket

# ---- 查询 ----

func get_state() -> State:
	return _state

func get_session() -> RendezvousContract.SessionState:
	return _session

func get_identity() -> RendezvousContract.SessionIdentity:
	return _identity

func last_error() -> int:
	return _last_error

func last_detail() -> String:
	return _last_detail

func is_active() -> bool:
	return _state == State.REGISTERING or _state == State.REGISTERED

func is_failed() -> bool:
	return _state == State.FAILED or _state == State.TIMEOUT

## 是否已拿到服务端观测到的本端端点。
func has_observed_endpoint() -> bool:
	return _session != null and _session.has_local_observed_endpoint()

## 获取底层 UDP socket（用于共享 transport 模式）。
func get_udp() -> PacketPeerUDP:
	return _udp

## 本对象是否拥有底层 UDP socket 的生命周期。
## false = 外部共享（由 P2PConnection 拥有），close()/reset() 绝不关闭它。
func owns_udp() -> bool:
	return _owns_udp

## 设置外部 UDP socket（必须在 begin() 前调用，或 begin() 时通过参数传入）。
func set_udp(udp: PacketPeerUDP) -> bool:
	if _udp != null or _state != State.IDLE:
		return false
	_udp = udp
	_owns_udp = false
	return true

# ---- 生命周期 ----

## 开始注册。identity 携带 room_id / ticket / protocol / role / nonce。
##
## 注意：ticket 由上层（LobbyManager）给出，**不由本对象生成或验证**；
## 本对象只负责把它放进 REGISTER 包，且绝不写进日志。
##
## 参数 shared_udp：外部传入的**共享** PacketPeerUDP（由 P2PConnection 拥有）。
## 如果提供，将复用该 socket，且 `owns_udp()` 为 false —— close()/reset() 绝不关闭它。
## 这是 9.2.2 共享 transport 模式的关键：server observed 端点必须与打洞端点相同。
func begin(
	host: String,
	port: int,
	identity: RendezvousContract.SessionIdentity,
	local_candidates: Array,
	shared_udp: PacketPeerUDP = null
) -> bool:
	if identity == null or not identity.is_valid():
		return false
	if host.strip_edges().is_empty():
		return false
	## 复用来源：显式传入的共享 socket，或先前 set_udp() 注入的共享 socket。
	var reuse_shared: PacketPeerUDP = shared_udp
	if reuse_shared == null and _udp != null and not _owns_udp:
		reuse_shared = _udp
	## 收起上一次的 socket：BYE 尽力而为；只有自己拥有的才 close()。
	if _udp != null:
		if _session != null and not _session.rendezvous_id.is_empty():
			_udp.put_packet(RendezvousContract.encode_bye(_session.rendezvous_id))
		if _owns_udp:
			_udp.close()
	_udp = null
	_owns_udp = false
	_host = host.strip_edges()
	_port = port if port >= 1 and port <= 65535 else DEFAULT_PORT
	_identity = identity
	_local_candidates = _clone_candidates(local_candidates)
	_session = RendezvousContract.SessionState.new()
	_session.local_nonce = identity.nonce
	_session.local_candidates = _clone_candidates(local_candidates)
	_elapsed_sec = 0.0
	_last_error = RendezvousContract.ErrorCode.NONE
	_last_detail = ""

	if reuse_shared != null:
		_udp = reuse_shared
		_owns_udp = false
	else:
		_udp = PacketPeerUDP.new()
		_owns_udp = true
		## 绑定到任意本地端口；服务端看到的是这个 socket 经 NAT 映射后的端点。
		var err: Error = _udp.bind(0)
		if err != OK:
			_state = State.FAILED
			_last_detail = "bind_failed"
			return false

	_udp.set_dest_address(_host, _port)
	_state = State.REGISTERING
	return _send_register()

func _send_register() -> bool:
	if _udp == null or _identity == null:
		return false
	var payload: PackedByteArray = RendezvousContract.encode_register(
		_session.rendezvous_id, _identity, _local_candidates
	)
	if payload.is_empty():
		return false
	_udp.put_packet(payload)
	return true

## 每帧轮询。由上层驱动（P2PConnection.tick / MainMenu）。
func poll() -> void:
	if _udp == null or _paused:
		return
	while _udp.get_available_packet_count() > 0:
		var packet: PackedByteArray = _udp.get_packet()
		if not packet.is_empty():
			_handle_packet(packet)

## 设置暂停/恢复 poll（hole punch 期间暂停，避免抢占共享 socket）。
func set_paused(paused: bool) -> void:
	_paused = paused

## 推进超时。RENDEZVOUS_TIMEOUT 是注册阶段预算，由调用方的整体预算兜底。
func tick(delta_sec: float, timeout_sec: float = RendezvousContract.RENDEZVOUS_TIMEOUT_SEC) -> bool:
	if _state == State.IDLE or is_failed() or _state == State.CANDIDATES:
		return false
	_elapsed_sec += maxf(delta_sec, 0.0)
	if timeout_sec > 0.0 and _elapsed_sec >= timeout_sec:
		_state = State.TIMEOUT
		_last_detail = "rendezvous_timeout"
		close_socket()
		timed_out.emit("rendezvous_timeout")
		return true
	return false

## 主动离场（尽力而为）+ 关 socket。不留下任何 socket 资源。
func close() -> void:
	if _udp != null and _session != null and not _session.rendezvous_id.is_empty():
		_udp.put_packet(RendezvousContract.encode_bye(_session.rendezvous_id))
	close_socket()

func close_socket() -> void:
	if _udp != null and _owns_udp:
		_udp.close()
	if _owns_udp:
		_udp = null
	_owns_udp = false

## 重置到 IDLE（可重新 begin）。
func reset() -> void:
	close()
	_state = State.IDLE
	_identity = null
	_local_candidates.clear()
	_session = null
	_elapsed_sec = 0.0
	_last_error = RendezvousContract.ErrorCode.NONE
	_last_detail = ""
	_owns_udp = false

# ---- 收包 ----

func _handle_packet(packet: PackedByteArray) -> void:
	var decoded: RendezvousContract.Decoded = RendezvousContract.decode(packet)
	if not decoded.is_ok():
		## 坏包不改状态：可能是扫描流量或版本不符。
		return
	## session_id 一旦被服务端分配，后续包必须一致（防串台）。
	if not decoded.session_id.is_empty():
		if _session.rendezvous_id.is_empty():
			_session.rendezvous_id = decoded.session_id
		elif _session.rendezvous_id != decoded.session_id:
			return
	match decoded.msg_type:
		RendezvousContract.MsgType.REGISTERED:
			_apply_registered(decoded)
		RendezvousContract.MsgType.PEER_READY:
			_apply_peer_ready(decoded)
		RendezvousContract.MsgType.CANDIDATES:
			_apply_candidates(decoded)
		RendezvousContract.MsgType.ERROR:
			_apply_error(decoded)
		_:
			pass

## REGISTERED：记录**服务端观测到的**本端端点。绝不自己填。
func _apply_registered(decoded: RendezvousContract.Decoded) -> void:
	if _state == State.FAILED or _state == State.TIMEOUT:
		return
	## nonce 必须回显自己，否则是串台的包。
	if decoded.identity != null and decoded.identity.nonce != _session.local_nonce:
		return
	_session.local_observed_address = decoded.observed_address
	_session.local_observed_port = decoded.observed_port
	if _state == State.REGISTERING:
		_state = State.REGISTERED
	registered.emit(decoded.session_id, decoded.observed_address, decoded.observed_port)

func _apply_peer_ready(decoded: RendezvousContract.Decoded) -> void:
	if _state == State.FAILED or _state == State.TIMEOUT:
		return
	_session.remote_nonce = decoded.remote_nonce
	if decoded.observed_address != "":
		_session.remote_observed_address = decoded.observed_address
		_session.remote_observed_port = decoded.observed_port
	peer_ready.emit(decoded.remote_nonce, decoded.remote_role)

## CANDIDATES：对端候选 + 对端 observed endpoint。
## 端点的 observed 字段由服务端填；本地候选的 observed 由服务端在 REGISTERED 里给。
func _apply_candidates(decoded: RendezvousContract.Decoded) -> void:
	if _state == State.FAILED or _state == State.TIMEOUT:
		return
	_session.remote_nonce = decoded.remote_nonce
	_session.remote_observed_address = decoded.observed_address
	_session.remote_observed_port = decoded.observed_port
	_session.remote_candidates.clear()
	for candidate: RendezvousContract.Candidate in decoded.candidates:
		_session.remote_candidates.append(candidate)
	_state = State.CANDIDATES
	candidates_received.emit(
		_session.remote_candidates, decoded.remote_nonce, decoded.remote_role
	)

func _apply_error(decoded: RendezvousContract.Decoded) -> void:
	_last_error = decoded.error_code
	_last_detail = decoded.detail
	## TIMEOUT 是服务端侧的 session 回收，本地按超时处理。
	if decoded.error_code == RendezvousContract.ErrorCode.TIMEOUT:
		_state = State.TIMEOUT
		close_socket()
		timed_out.emit("server_timeout")
		return
	_state = State.FAILED
	close_socket()
	server_error.emit(decoded.error_code, decoded.detail)

# ---- 辅助 ----

func _clone_candidates(source: Array) -> Array[RendezvousContract.Candidate]:
	var out: Array[RendezvousContract.Candidate] = []
	for candidate: RendezvousContract.Candidate in source:
		var copy: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
		copy.transport = candidate.transport
		copy.path = candidate.path
		copy.address = candidate.address
		copy.port = candidate.port
		## 本端候选的 observed 一律留空 —— 只有服务端 / STUN 能填。
		copy.observed_address = ""
		copy.observed_port = 0
		out.append(copy)
	return out

## 日志安全一行摘要（绝不含 ticket）。
func describe() -> String:
	var sid: String = _session.rendezvous_id if _session != null else ""
	return RendezvousContract.safe_summary(
		RendezvousContract.MsgType.REGISTER,
		sid,
		_identity.role if _identity != null else RendezvousContract.Role.GUEST,
		_session.local_nonce if _session != null else "",
		_session.local_observed_address if _session != null else "",
		_session.local_observed_port if _session != null else 0,
		_last_error
	)
