extends RefCounted
class_name JoinInvite

## 邀请票据（Phase 8）。LAN / IPv6 / WAN 三种连接候选的统一载体。
##
## 职责边界（严格）：
## - 只做 URI <-> 强类型结构的转换与校验。**不理解 ENet，不持有 peer，不选路径执行**。
## - UI 禁止自己拼 "wpg://" 或 "ip:port"；一律经 LobbyManager.create_invite() / join_invite()。
##
## token 语义（见 docs/ui_lobby_architecture.md §3.4）：
##   token = 「我持有这间房的门票」，由 Host 建房时随机生成（Crypto，128 bit）。
##   绝不等于 profile_id / room_id / seat / peer_id —— 那四个各自回答不同问题：
##     profile_id = 我是谁；peer_id = 这次套接字；seat = 房内站位；room_id = 哪间房。
##   token 只证明「持有 ticket」，不证明「我是谁」；认证权威始终在 Host。
##
## URI 形态：
##   wpg://join?v=6&t=TOKEN&lan=192.168.1.20&lp=17777[&wan=h&wp=p][&ip6=...][&n=Name][&r=ROOMID]

const SCHEME: String = "wpg"
const ACTION_JOIN: String = "join"
## 与 GameLaunch.NET_PROTOCOL 同步。这里写死字面量是为了让 URI 语法可独立测试，
## 并由 join_invite_test 断言两者相等（防止只改一处）。
const VERSION: int = 6
const PREFIX: String = "wpg://join?"

const DEFAULT_LAN_PORT: int = 17777
const DEFAULT_WAN_PORT: int = 49152

## 解析失败原因码。UI 只显示，不解析字符串。
enum InvalidReason {
	OK,
	EMPTY,
	BAD_SCHEME,
	BAD_ACTION,
	BAD_VERSION,
	MISSING_TOKEN,
	BAD_TOKEN,
	BAD_LAN_HOST,
	BAD_LAN_PORT,
	BAD_WAN_HOST,
	BAD_WAN_PORT,
	BAD_IPV6,
}

var token: String = ""
var lan_host: String = ""
var lan_port: int = DEFAULT_LAN_PORT
var ipv6: String = ""
var wan_host: String = ""
var wan_port: int = DEFAULT_WAN_PORT
## 以下两个只是显示用元数据，不参与鉴权、不参与连接。
var room_id: String = ""
var host_name: String = ""
var version: int = VERSION
var error: InvalidReason = InvalidReason.OK

func is_valid() -> bool:
	return error == InvalidReason.OK and not token.is_empty() and not lan_host.is_empty()

## 本机是否至少有一个可尝试的连接候选（LAN / IPv6 / WAN）。
func has_any_candidate() -> bool:
	return not lan_host.is_empty() or not ipv6.is_empty() or not wan_host.is_empty()

## 把本 invite 交给 ConnectionPath 决策用。只描述候选，不含任何「已连接」断言。
func to_candidates() -> ConnectionPath:
	return ConnectionPath.from_invite(self)

## —— 生成 ——

## Host 建房后生成门票。token 每次都重新随机，绝不复用 room_id / profile_id。
static func create(
	lan_host: String,
	lan_port: int = DEFAULT_LAN_PORT,
	token: String = "",
	room_id: String = "",
	host_name: String = "",
	ipv6: String = "",
	wan_host: String = "",
	wan_port: int = DEFAULT_WAN_PORT
) -> JoinInvite:
	var invite: JoinInvite = JoinInvite.new()
	invite.version = VERSION
	invite.lan_host = _sanitize_host(lan_host)
	invite.lan_port = lan_port
	invite.token = token if not token.is_empty() else generate_token()
	invite.room_id = _sanitize_metadata(room_id, 32)
	invite.host_name = _sanitize_metadata(host_name, 24)
	invite.ipv6 = _sanitize_ipv6(ipv6)
	invite.wan_host = _sanitize_host(wan_host)
	invite.wan_port = wan_port
	invite.error = invite._validate_fields()
	return invite

## 128 bit 随机门票。Crypto 与 Room._make_room_id 同源；这里取 16 字节（room_id 只取 4）。
static func generate_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

## —— 解析 ——

## 严格解析。任何不合法都返回带 error 的实例（error != OK），绝不抛异常、绝不半信半疑地接受。
static func parse(raw: String) -> JoinInvite:
	var invite: JoinInvite = JoinInvite.new()
	var text: String = raw.strip_edges()
	if text.is_empty():
		invite.error = InvalidReason.EMPTY
		return invite
	var lower: String = text.to_lower()
	if not lower.begins_with("%s://" % SCHEME):
		invite.error = InvalidReason.BAD_SCHEME
		return invite
	var rest: String = text.substr(SCHEME.length() + 3)
	var mark: int = rest.find("?")
	if mark < 0:
		invite.error = InvalidReason.BAD_ACTION
		return invite
	var action: String = rest.substr(0, mark).to_lower()
	if action != ACTION_JOIN:
		invite.error = InvalidReason.BAD_ACTION
		return invite
	var query: String = rest.substr(mark + 1)
	if query.is_empty():
		invite.error = InvalidReason.BAD_ACTION
		return invite
	invite._apply_query(query)
	return invite

## 便捷包装：测试与 UI 用同一份语义。
static func try_parse(raw: String) -> JoinInvite:
	return parse(raw)

func _apply_query(query: String) -> void:
	var fields: Dictionary = {}
	for pair: String in query.split("&", false):
		var eq: int = pair.find("=")
		if eq <= 0:
			continue
		var key: String = pair.substr(0, eq)
		var value: String = pair.substr(eq + 1)
		fields[key] = value

	if not fields.has("v"):
		error = InvalidReason.BAD_VERSION
		return
	var raw_version: String = str(fields["v"])
	if not raw_version.is_valid_int() or int(raw_version) != VERSION:
		error = InvalidReason.BAD_VERSION
		return
	version = VERSION

	## 缺 token / token 为空都不成立：ticket 是 v6 的入场券。
	if not fields.has("t"):
		error = InvalidReason.MISSING_TOKEN
		return
	## token 是凭据：超长 / 非法一律拒绝，绝不截断后再接受（截断会掩盖伪造尝试）。
	token = str(fields["t"])
	if token.is_empty():
		error = InvalidReason.MISSING_TOKEN
		return
	if not _is_hex_token(token):
		error = InvalidReason.BAD_TOKEN
		return

	## LAN 是 1.0 的唯一真实路径，缺它整张 invite 就不可用于连接。
	if not fields.has("lan"):
		error = InvalidReason.BAD_LAN_HOST
		return
	lan_host = _sanitize_host(str(fields["lan"]))
	if lan_host.is_empty():
		error = InvalidReason.BAD_LAN_HOST
		return

	if fields.has("lp"):
		var raw_lp: String = str(fields["lp"])
		if not raw_lp.is_valid_int() or not _is_valid_port(int(raw_lp)):
			error = InvalidReason.BAD_LAN_PORT
			return
		lan_port = int(raw_lp)
	else:
		lan_port = DEFAULT_LAN_PORT

	## 可选字段：缺失或非法都不该让一张有效 LAN invite 失效 —— 直接忽略该候选。
	if fields.has("ip6"):
		ipv6 = _sanitize_ipv6(str(fields["ip6"]))
	if fields.has("wan"):
		var candidate_wan: String = _sanitize_host(str(fields["wan"]))
		if not candidate_wan.is_empty():
			wan_host = candidate_wan
			if fields.has("wp"):
				var raw_wp: String = str(fields["wp"])
				if raw_wp.is_valid_int() and _is_valid_port(int(raw_wp)):
					wan_port = int(raw_wp)
			else:
				wan_port = DEFAULT_WAN_PORT
	if fields.has("n"):
		host_name = _sanitize_metadata(str(fields["n"]), 24)
	if fields.has("r"):
		room_id = _sanitize_metadata(str(fields["r"]), 32)

	error = _validate_fields()

func _validate_fields() -> InvalidReason:
	if token.is_empty():
		return InvalidReason.MISSING_TOKEN
	if not _is_hex_token(token):
		return InvalidReason.BAD_TOKEN
	if lan_host.is_empty() and ipv6.is_empty() and wan_host.is_empty():
		return InvalidReason.BAD_LAN_HOST
	if not lan_host.is_empty() and not _is_valid_port(lan_port):
		return InvalidReason.BAD_LAN_PORT
	if not wan_host.is_empty() and not _is_valid_port(wan_port):
		return InvalidReason.BAD_WAN_PORT
	return InvalidReason.OK

## 稳定 URI。字段顺序固定，方便「create -> parse -> to_uri」幂等断言。
func to_uri() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("v=%d" % version)
	parts.append("t=%s" % token)
	if not lan_host.is_empty():
		parts.append("lan=%s" % lan_host)
		parts.append("lp=%d" % lan_port)
	if not wan_host.is_empty():
		parts.append("wan=%s" % wan_host)
		parts.append("wp=%d" % wan_port)
	if not ipv6.is_empty():
		parts.append("ip6=%s" % ipv6)
	if not host_name.is_empty():
		parts.append("n=%s" % host_name)
	if not room_id.is_empty():
		parts.append("r=%s" % room_id)
	return PREFIX + "&".join(parts)

## 给 UI 显示用的一行摘要（不含 token：门票不进日志、不进截图）。
func display_label() -> String:
	var who: String = host_name if not host_name.is_empty() else "LAN HOST"
	return "%s @ %s:%d" % [who, lan_host, lan_port]

## —— 校验辅助 ——

## token 必须是十六进制串（Host 只用 generate_token 生成）。挡掉把 profile_id / seat
## / room_id 直接当 token 塞进来的实现。
static func _is_hex_token(value: String) -> bool:
	if value.length() < 8 or value.length() > 64:
		return false
	for i: int in value.length():
		var c: int = value.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_lower: bool = c >= 97 and c <= 102
		var is_upper: bool = c >= 65 and c <= 70
		if not (is_digit or is_lower or is_upper):
			return false
	return true

## IPv4（或主机名）校验。拒绝空、拒绝带冒号的 IPv6、拒绝越界段。
static func _sanitize_host(value: String) -> String:
	var host: String = value.strip_edges()
	if host.is_empty() or host.length() > 64:
		return ""
	if host.find(":") >= 0 or host.find("/") >= 0 or host.find(" ") >= 0:
		return ""
	if not _is_ipv4(host):
		return ""
	return host

## 严格 IPv4 点分十进制：四段、每段 0..255、不允许多余前导零以外的花样。
static func _is_ipv4(host: String) -> bool:
	var segments: PackedStringArray = host.split(".", true)
	if segments.size() != 4:
		return false
	for segment: String in segments:
		if segment.is_empty() or segment.length() > 3:
			return false
		if not segment.is_valid_int():
			return false
		var value: int = int(segment)
		if value < 0 or value > 255:
			return false
		if segment.length() > 1 and segment.begins_with("0"):
			return false
	return true

## IPv6 必须是「含冒号且字符集合法」。1.0 不做地址规范化，只保证能喂给 ENet。
static func _sanitize_ipv6(value: String) -> String:
	var addr: String = value.strip_edges()
	if addr.is_empty() or addr.length() > 45:
		return ""
	if addr.find(":") < 0:
		return ""
	for i: int in addr.length():
		var c: int = addr.unicode_at(i)
		var is_hex: bool = (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70)
		if not (is_hex or c == 58 or c == 46):
			return ""
	return addr

static func _is_valid_port(value: int) -> bool:
	return value >= 1 and value <= 65535

## 元数据字段（n / r）：只允许安全字符，避免 URI 注入与显示污染。
static func _sanitize_metadata(value: String, limit: int) -> String:
	var text: String = value.strip_edges()
	if text.length() > limit:
		text = text.substr(0, limit)
	var out: String = ""
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		var is_digit: bool = c >= 48 and c <= 57
		var is_lower: bool = c >= 97 and c <= 122
		var is_upper: bool = c >= 65 and c <= 90
		if is_digit or is_lower or is_upper or c == 45 or c == 95:
			out += char(c)
	return out
