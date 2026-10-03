extends RefCounted
class_name ConnectionPath

## 连接候选路径（Phase 8）。描述「可以试哪些路」，不负责「建 peer」。
##
## 硬约束（见 docs/ui_lobby_architecture.md §5.2）：
## - 本对象**不持有** ENetMultiplayerPeer，也不调用 ENet。
## - SceneTree.multiplayer 任何时刻只允许一个 peer；因此候选是**顺序**尝试，
##   失败 -> 关闭 / 清理当前 peer -> 再试下一个。绝不允许 IPv4 与 IPv6 两个 peer 并存。
## - 不做 STUN / TURN / UPnP / 打洞 / rendezvous —— 那些是 Phase 9。
##
## path 枚举复用 LobbyPlayer.Path（唯一定义处），避免出现第二套 path 枚举。

## 默认候选顺序：LAN 最快也最可靠，IPv6 次之，WAN 最后。
const DEFAULT_ORDER: Array[int] = [
	LobbyPlayer.Path.LAN_IPV4,
	LobbyPlayer.Path.IPV6,
	LobbyPlayer.Path.WAN_IPV4,
]

## 一个候选：path 类型 + 可直接喂给 ENet 的地址 + 端口。
class Candidate extends RefCounted:
	var path: int = LobbyPlayer.Path.LAN_IPV4
	var address: String = ""
	var port: int = 0

	func is_usable() -> bool:
		if address.is_empty():
			return false
		if port < 1 or port > 65535:
			return false
		return true

	func key() -> String:
		return "%d|%s|%d" % [path, address, port]

	func to_dict() -> Dictionary:
		return {"path": path, "address": address, "port": port}

var _candidates: Array[Candidate] = []

## 由 JoinInvite 装配候选：只放入 invite 真实提供的路径（缺省的不伪造）。
static func from_invite(invite: JoinInvite) -> ConnectionPath:
	var plan: ConnectionPath = ConnectionPath.new()
	if invite == null:
		return plan
	var lan: Candidate = Candidate.new()
	lan.path = LobbyPlayer.Path.LAN_IPV4
	lan.address = invite.lan_host
	lan.port = invite.lan_port
	if lan.is_usable():
		plan._candidates.append(lan)

	var v6: Candidate = Candidate.new()
	v6.path = LobbyPlayer.Path.IPV6
	v6.address = invite.ipv6
	v6.port = invite.lan_port
	if v6.is_usable():
		plan._candidates.append(v6)

	var wan: Candidate = Candidate.new()
	wan.path = LobbyPlayer.Path.WAN_IPV4
	wan.address = invite.wan_host
	wan.port = invite.wan_port
	if wan.is_usable():
		plan._candidates.append(wan)

	plan._sort_by_default_order()
	return plan

## 从裸地址装配（手动 JOIN / 测试用）：只产出一个 LAN_IPV4 候选。
static func from_address(address: String, port: int = GameLaunch.NET_PORT) -> ConnectionPath:
	var plan: ConnectionPath = ConnectionPath.new()
	var lan: Candidate = Candidate.new()
	lan.path = LobbyPlayer.Path.LAN_IPV4
	lan.address = address.strip_edges()
	lan.port = port
	if lan.is_usable():
		plan._candidates.append(lan)
	return plan

## 候选顺序稳定：先按 DEFAULT_ORDER，再按 key 字典序，保证同样输入永远同样顺序。
func _sort_by_default_order() -> void:
	_candidates.sort_custom(func(a: Candidate, b: Candidate) -> bool:
		var ra: int = DEFAULT_ORDER.find(a.path)
		var rb: int = DEFAULT_ORDER.find(b.path)
		if ra < 0:
			ra = DEFAULT_ORDER.size()
		if rb < 0:
			rb = DEFAULT_ORDER.size()
		if ra != rb:
			return ra < rb
		return a.key() < b.key()
	)

func ordered_candidates() -> Array[Candidate]:
	return _candidates.duplicate()

func size() -> int:
	return _candidates.size()

func is_empty() -> bool:
	return _candidates.is_empty()

## 首选路径（候选为空时返回 LAN_IPV4 作为无害默认，调用方应先用 is_empty 判断）。
func preferred_path() -> int:
	if _candidates.is_empty():
		return LobbyPlayer.Path.LAN_IPV4
	return _candidates[0].path

## 校验一个候选是否真的可用。不做任何网络 I/O —— 只做静态合法性。
func validate_candidate(candidate: Candidate) -> bool:
	if candidate == null:
		return false
	if not candidate.is_usable():
		return false
	if DEFAULT_ORDER.find(candidate.path) < 0:
		return false
	## IPv6 候选的地址必须真含冒号；否则是装配错误，宁可拒绝也不要给 ENet 喂垃圾。
	if candidate.path == LobbyPlayer.Path.IPV6:
		return candidate.address.find(":") >= 0
	return true

## 取下一个可尝试的候选。index 是调用方持有的游标（0 起）。
## 返回 null = 没有更多可试的路径，调用方该放弃了。
func select_next_path(index: int) -> Candidate:
	var i: int = maxi(index, 0)
	while i < _candidates.size():
		var candidate: Candidate = _candidates[i]
		if validate_candidate(candidate):
			return candidate
		i += 1
	return null

## 候选地址列表（诊断 / 测试断言用）。
func address_list() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for candidate: Candidate in _candidates:
		out.append(candidate.address)
	return out

func path_list() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for candidate: Candidate in _candidates:
		out.append(candidate.path)
	return out

## path 枚举 -> 稳定小写名（UI / 日志用）。
static func path_name(path: int) -> String:
	if path == LobbyPlayer.Path.IPV6:
		return "ipv6"
	if path == LobbyPlayer.Path.WAN_IPV4:
		return "wan_ipv4"
	return "lan_ipv4"
