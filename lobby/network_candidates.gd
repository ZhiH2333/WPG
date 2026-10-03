extends RefCounted
class_name NetworkCandidates

## 本地网络候选枚举与分类（Phase 9.2）。
##
## 职责：
## - 枚举本机 IPv4 / IPv6 接口
## - 将每个地址分类：LOOPBACK / PRIVATE / LINK_LOCAL / PUBLIC / OBSERVED
## - 只做静态分类，**不做** STUN、不猜公网 IP、不扫端口、不扫局域网
## - 供 P2PHolePunch / P2PConnection 收集 local candidates 使用
##
## 分类定义（与 RendezvousContract.Candidate.path 语义对齐，但更细）：
## - LOOPBACK_ONLY_FOR_TEST：127.0.0.1 / ::1 —— 仅本机测试可用
## - LOCAL_PRIVATE：RFC 1918 私有地址（10/8, 172.16/12, 192.168/16）—— 局域网直连首选
## - LOCAL_IPV6：IPv6 全球单播 / ULA —— 次选
## - LOCAL_LINK_LOCAL：fe80::/10 —— 仅同链路
## - OBSERVED_PUBLIC：由 STUN / rendezvous 观测到的公网端点 —— 打洞用
##
## 严格禁止：
## - 猜公网 IP（hostname 解析、外部 API、UPnP）
## - 端口扫描
## - 整个局域网扫描

enum CandidateType {
	LOOPBACK_ONLY_FOR_TEST,
	LOCAL_PRIVATE,
	LOCAL_IPV6,
	LOCAL_LINK_LOCAL,
	OBSERVED_PUBLIC,
}

static func type_name(value: int) -> String:
	match value:
		CandidateType.LOOPBACK_ONLY_FOR_TEST:
			return "loopback"
		CandidateType.LOCAL_PRIVATE:
			return "local_private"
		CandidateType.LOCAL_IPV6:
			return "local_ipv6"
		CandidateType.LOCAL_LINK_LOCAL:
			return "local_link_local"
		CandidateType.OBSERVED_PUBLIC:
			return "observed_public"
		_:
			return "unknown"

## 一个带类型标记的候选端点。
class Candidate extends RefCounted:
	var candidate_type: int = CandidateType.LOCAL_PRIVATE
	var address: String = ""
	var port: int = 0
	## 仅 OBSERVED_PUBLIC 使用：由 STUN / rendezvous 填入的公网观测端点。
	var observed_address: String = ""
	var observed_port: int = 0
	## 仅 OBSERVED_PUBLIC 使用：关联到 rendezvous 的 nonce。
	var nonce: String = ""

	func is_usable() -> bool:
		if address.is_empty():
			return false
		if port < 1 or port > 65535:
			return false
		return true

	func has_observed_endpoint() -> bool:
		return not observed_address.is_empty() and observed_port >= 1 and observed_port <= 65535

	func to_dict() -> Dictionary:
		return {
			"type": NetworkCandidates.type_name(candidate_type),
			"address": address,
			"port": port,
			"observed_address": observed_address,
			"observed_port": observed_port,
			"nonce": nonce,
		}

## 核心入口：枚举本机所有可用候选（含 IPv4 / IPv6）。
##
## 返回按优先级排序的候选列表：
## 1. LOCAL_PRIVATE (IPv4)
## 2. LOCAL_IPV6 (global/ULA)
## 3. LOCAL_LINK_LOCAL (IPv6 link-local)
## 4. LOOPBACK_ONLY_FOR_TEST (仅当 allow_loopback=true)
##
## observed candidates 由上层（STUN / rendezvous 回包）单独追加，不在此产生。
static func enumerate_local(port: int = 0, allow_loopback: bool = false) -> Array[Candidate]:
	var out: Array[Candidate] = []
	var interfaces: Array[Dictionary] = IP.get_local_interfaces()
	for iface: Dictionary in interfaces:
		var addresses: Array = iface.get("addresses", [])
		for addr_dict: Dictionary in addresses:
			var address: String = str(addr_dict.get("address", ""))
			if address.is_empty():
				continue
			var ctype: int = _classify_address(address)
			if ctype == CandidateType.LOOPBACK_ONLY_FOR_TEST and not allow_loopback:
				continue
			var candidate: Candidate = Candidate.new()
			candidate.candidate_type = ctype
			candidate.address = address
			candidate.port = port if port > 0 else GameLaunch.NET_PORT
			out.append(candidate)
	_sort_by_priority(out)
	return out

## 分类单个地址字符串。
static func _classify_address(address: String) -> int:
	var clean: String = address.strip_edges()
	# IPv4
	if clean.find(".") >= 0 and clean.find(":") < 0:
		if _is_loopback_ipv4(clean):
			return CandidateType.LOOPBACK_ONLY_FOR_TEST
		if _is_private_ipv4(clean):
			return CandidateType.LOCAL_PRIVATE
		if _is_link_local_ipv4(clean):
			return CandidateType.LOCAL_LINK_LOCAL
		return CandidateType.OBSERVED_PUBLIC
	# IPv6
	if clean.find(":") >= 0:
		if clean == "::1" or clean.begins_with("::1%"):
			return CandidateType.LOOPBACK_ONLY_FOR_TEST
		if clean.begins_with("fe80:") or clean.begins_with("fe80%"):
			return CandidateType.LOCAL_LINK_LOCAL
		if _is_ula_ipv6(clean):
			return CandidateType.LOCAL_IPV6
		return CandidateType.LOCAL_IPV6
	return CandidateType.OBSERVED_PUBLIC

static func _is_loopback_ipv4(addr: String) -> bool:
	return addr == "127.0.0.1" or addr.begins_with("127.")

static func _is_private_ipv4(addr: String) -> bool:
	var parts: PackedStringArray = addr.split(".", true)
	if parts.size() != 4:
		return false
	var a: int = int(parts[0])
	var b: int = int(parts[1])
	# 10.0.0.0/8
	if a == 10:
		return true
	# 172.16.0.0/12
	if a == 172 and b >= 16 and b <= 31:
		return true
	# 192.168.0.0/16
	if a == 192 and b == 168:
		return true
	return false

static func _is_link_local_ipv4(addr: String) -> bool:
	var parts: PackedStringArray = addr.split(".", true)
	if parts.size() != 4:
		return false
	var a: int = int(parts[0])
	var b: int = int(parts[1])
	return a == 169 and b == 254

static func _is_ula_ipv6(addr: String) -> bool:
	# ULA: fc00::/7 (fc00::/8 + fd00::/8)
	return addr.begins_with("fc") or addr.begins_with("fd") or addr.begins_with("FC") or addr.begins_with("FD")

## 从 RendezvousContract.SessionState 取出 observed endpoint，生成 OBSERVED_PUBLIC 候选。
##
## 这是打洞阶段**唯一**的公网端点来源 —— 绝不自己猜、不自己查 hostname。
static func from_observed_endpoint(
	observed_address: String,
	observed_port: int,
	nonce: String = ""
) -> Candidate:
	var candidate: Candidate = Candidate.new()
	candidate.candidate_type = CandidateType.OBSERVED_PUBLIC
	candidate.address = observed_address
	candidate.port = observed_port
	candidate.observed_address = observed_address
	candidate.observed_port = observed_port
	candidate.nonce = nonce
	return candidate

## 将 NetworkCandidates.Candidate 转为 RendezvousContract.Candidate（用于注册）。
static func to_rendezvous_candidate(candidate: Candidate) -> RendezvousContract.Candidate:
	var out: RendezvousContract.Candidate = RendezvousContract.Candidate.new()
	out.transport = RendezvousContract.Transport.UDP
	out.path = _candidate_type_to_path(candidate.candidate_type)
	out.address = candidate.address
	out.port = candidate.port
	out.observed_address = candidate.observed_address
	out.observed_port = candidate.observed_port
	return out

static func _candidate_type_to_path(ctype: int) -> int:
	match ctype:
		CandidateType.LOOPBACK_ONLY_FOR_TEST:
			return LobbyPlayer.Path.LAN_IPV4
		CandidateType.LOCAL_PRIVATE:
			return LobbyPlayer.Path.LAN_IPV4
		CandidateType.LOCAL_IPV6:
			return LobbyPlayer.Path.IPV6
		CandidateType.LOCAL_LINK_LOCAL:
			return LobbyPlayer.Path.IPV6
		CandidateType.OBSERVED_PUBLIC:
			return LobbyPlayer.Path.WAN_IPV4
		_:
			return LobbyPlayer.Path.LAN_IPV4

## 按优先级排序：LOCAL_PRIVATE > LOCAL_IPV6 > LOCAL_LINK_LOCAL > LOOPBACK
static func _sort_by_priority(candidates: Array[Candidate]) -> void:
	candidates.sort_custom(func(a: Candidate, b: Candidate) -> bool:
		var pa: int = _priority(a.candidate_type)
		var pb: int = _priority(b.candidate_type)
		if pa != pb:
			return pa < pb
		return a.address < b.address
	)

static func _priority(ctype: int) -> int:
	match ctype:
		CandidateType.LOCAL_PRIVATE:
			return 0
		CandidateType.LOCAL_IPV6:
			return 1
		CandidateType.LOCAL_LINK_LOCAL:
			return 2
		CandidateType.LOOPBACK_ONLY_FOR_TEST:
			return 3
		CandidateType.OBSERVED_PUBLIC:
			return 4
		_:
			return 99

## 去重：同 address+port 只保留优先级最高的（第一个）。
static func deduplicate(candidates: Array[Candidate]) -> Array[Candidate]:
	var seen: Dictionary = {}
	var out: Array[Candidate] = []
	for candidate: Candidate in candidates:
		var key: String = "%s:%d" % [candidate.address, candidate.port]
		if not seen.has(key):
			seen[key] = true
			out.append(candidate)
	return out

## 仅保留可用候选。
static func filter_usable(candidates: Array[Candidate]) -> Array[Candidate]:
	var out: Array[Candidate] = []
	for candidate: Candidate in candidates:
		if candidate.is_usable():
			out.append(candidate)
	return out