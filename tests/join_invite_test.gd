extends SceneTree

## JoinInvite 回归（Phase 8）：URI <-> 强类型结构的 create / parse / 校验。
## 纯逻辑，不建 peer、不开端口、不碰 SceneTree.multiplayer。
## 跑法：godot --headless --path . --script res://tests/join_invite_test.gd
## 通过输出 JOIN_INVITE_OK；失败逐条 JOIN_INVITE_FAIL 并返回非 0。

const LAN := "192.168.1.20"
const WAN := "203.0.113.7"
const V6 := "fe80::1c2d:3e4f:5a6b:7c8d"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_case_protocol_is_six()
	_case_round_trip()
	_case_token_is_random_not_identity()
	_case_token_not_room_id()
	_case_lan_candidate()
	_case_ipv6_candidate()
	_case_wan_candidate()
	_case_optional_metadata()
	_case_minimal_lan_invite()
	_case_invalid_scheme()
	_case_invalid_version()
	_case_invalid_ipv4()
	_case_invalid_port()
	_case_missing_token()
	_case_token_not_leaked_in_label()
	_case_rejects_non_hex_token()
	_case_display_metadata_sanitized()
	_finish()

# ---- 用例 ----

## URI 语法里的 v 必须和 GameLaunch.NET_PROTOCOL 一致，防止只改一处。
func _case_protocol_is_six() -> void:
	_expect(GameLaunch.NET_PROTOCOL == 6, "GameLaunch.NET_PROTOCOL == 6")
	_expect(JoinInvite.VERSION == 6, "JoinInvite.VERSION == 6")
	_expect(JoinInvite.VERSION == GameLaunch.NET_PROTOCOL, "invite 版本与协议号一致")

func _case_round_trip() -> void:
	var made: JoinInvite = JoinInvite.create(LAN, 17777, "", "a1b2c3d4", "NightFox")
	_expect(made.is_valid(), "create() 产出有效 invite")
	var uri: String = made.to_uri()
	_expect(uri.begins_with("wpg://join?"), "URI 前缀是 wpg://join?")
	var back: JoinInvite = JoinInvite.parse(uri)
	_expect(back.is_valid(), "create -> parse 往返有效")
	_expect(back.token == made.token, "往返保留 token")
	_expect(back.lan_host == LAN, "往返保留 lan_host")
	_expect(back.lan_port == 17777, "往返保留 lan_port")
	_expect(back.room_id == "a1b2c3d4", "往返保留 room_id")
	_expect(back.host_name == "NightFox", "往返保留 host_name")
	_expect(back.to_uri() == uri, "to_uri -> parse -> to_uri 幂等")

## token 必须是随机、非空，且绝不能等于 profile_id。
func _case_token_is_random_not_identity() -> void:
	PlayerProfile.load_from_disk()
	var first: JoinInvite = JoinInvite.create(LAN)
	var second: JoinInvite = JoinInvite.create(LAN)
	_expect(not first.token.is_empty(), "token 非空")
	_expect(first.token != second.token, "两次 create 的 token 不同（真随机）")
	_expect(first.token.length() == 32, "token 是 128bit hex（32 字符）")
	var profile_id: String = PlayerProfile.get_profile_id()
	if not profile_id.is_empty():
		_expect(first.token != profile_id, "token != profile_id")

## token 不能直接等于 room_id（即使调用方传了同一个值也必须是独立随机）。
func _case_token_not_room_id() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "deadbeef")
	_expect(invite.token != invite.room_id, "token != room_id")
	_expect(invite.token != "deadbeef", "token 不复用传入的 room_id 字面量")

func _case_lan_candidate() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777)
	_expect(invite.lan_host == LAN and invite.lan_port == 17777, "LAN 候选就位")
	var uri: String = invite.to_uri()
	_expect(uri.find("lan=%s" % LAN) >= 0, "URI 带 lan=")
	_expect(uri.find("lp=17777") >= 0, "URI 带 lp=")

func _case_ipv6_candidate() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6)
	_expect(invite.is_valid(), "带 IPv6 的 invite 有效")
	_expect(invite.ipv6 == V6, "IPv6 被接受")
	var back: JoinInvite = JoinInvite.parse(invite.to_uri())
	_expect(back.is_valid() and back.ipv6 == V6, "IPv6 往返保留")

func _case_wan_candidate() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", "", WAN, 49152)
	_expect(invite.is_valid(), "带 WAN 的 invite 有效")
	var back: JoinInvite = JoinInvite.parse(invite.to_uri())
	_expect(back.is_valid(), "WAN 往返有效")
	_expect(back.wan_host == WAN and back.wan_port == 49152, "WAN host / port 往返保留")

func _case_optional_metadata() -> void:
	var with_meta: JoinInvite = JoinInvite.create(LAN, 17777, "", "r0om1d", "NightFox")
	_expect(with_meta.room_id == "r0om1d" and with_meta.host_name == "NightFox", "可选元数据被保留")
	var without_meta: JoinInvite = JoinInvite.create(LAN, 17777)
	_expect(without_meta.is_valid(), "缺可选字段不影响有效性")
	_expect(without_meta.to_uri().find("&n=") < 0, "没 host_name 就不写 n=")
	_expect(without_meta.to_uri().find("&r=") < 0, "没 room_id 就不写 r=")

## 最小可用 invite：只有 v / t / lan（+ 隐含默认端口）。这是 LAN 手动输入的底线。
func _case_minimal_lan_invite() -> void:
	var token: String = JoinInvite.generate_token()
	var minimal: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=%s&lan=%s" % [token, LAN])
	_expect(minimal.is_valid(), "最小 LAN invite 有效")
	_expect(minimal.lan_port == JoinInvite.DEFAULT_LAN_PORT, "缺 lp 时回落到默认端口")
	_expect(minimal.ipv6.is_empty() and minimal.wan_host.is_empty(), "缺可选候选时不伪造")
	_expect(minimal.host_name.is_empty() and minimal.room_id.is_empty(), "缺元数据时为空")

func _case_invalid_scheme() -> void:
	var bad: JoinInvite = JoinInvite.parse("http://join?v=6&t=deadbeefdeadbeef&lan=%s" % LAN)
	_expect(not bad.is_valid(), "非 wpg scheme 无效")
	_expect(bad.error == JoinInvite.InvalidReason.BAD_SCHEME, "error = BAD_SCHEME")
	var no_scheme: JoinInvite = JoinInvite.parse("192.168.1.20")
	_expect(no_scheme.error == JoinInvite.InvalidReason.BAD_SCHEME, "裸 IP 不是 invite")
	var empty: JoinInvite = JoinInvite.parse("")
	_expect(empty.error == JoinInvite.InvalidReason.EMPTY, "空串 -> EMPTY")

func _case_invalid_version() -> void:
	var old: JoinInvite = JoinInvite.parse("wpg://join?v=5&t=deadbeefdeadbeef&lan=%s" % LAN)
	_expect(old.error == JoinInvite.InvalidReason.BAD_VERSION, "v=5 被判 BAD_VERSION（协议门）")
	var newer: JoinInvite = JoinInvite.parse("wpg://join?v=7&t=deadbeefdeadbeef&lan=%s" % LAN)
	_expect(newer.error == JoinInvite.InvalidReason.BAD_VERSION, "v=7 被判 BAD_VERSION")
	var missing: JoinInvite = JoinInvite.parse("wpg://join?t=deadbeefdeadbeef&lan=%s" % LAN)
	_expect(missing.error == JoinInvite.InvalidReason.BAD_VERSION, "缺 v 被判 BAD_VERSION")

func _case_invalid_ipv4() -> void:
	var out_of_range: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=deadbeefdeadbeef&lan=999.1.1.1")
	_expect(out_of_range.error == JoinInvite.InvalidReason.BAD_LAN_HOST, "越界 IPv4 -> BAD_LAN_HOST")
	var too_few: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=deadbeefdeadbeef&lan=192.168.1")
	_expect(too_few.error == JoinInvite.InvalidReason.BAD_LAN_HOST, "缺段 IPv4 -> BAD_LAN_HOST")
	var letters: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=deadbeefdeadbeef&lan=abc.def.ghi.jkl")
	_expect(letters.error == JoinInvite.InvalidReason.BAD_LAN_HOST, "非数字 IPv4 -> BAD_LAN_HOST")

func _case_invalid_port() -> void:
	var too_big: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=deadbeefdeadbeef&lan=%s&lp=70000" % LAN)
	_expect(too_big.error == JoinInvite.InvalidReason.BAD_LAN_PORT, "lp=70000 -> BAD_LAN_PORT")
	var zero: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=deadbeefdeadbeef&lan=%s&lp=0" % LAN)
	_expect(zero.error == JoinInvite.InvalidReason.BAD_LAN_PORT, "lp=0 -> BAD_LAN_PORT")
	var garbage: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=deadbeefdeadbeef&lan=%s&lp=abc" % LAN)
	_expect(garbage.error == JoinInvite.InvalidReason.BAD_LAN_PORT, "lp=abc -> BAD_LAN_PORT")

func _case_missing_token() -> void:
	var no_token: JoinInvite = JoinInvite.parse("wpg://join?v=6&lan=%s" % LAN)
	_expect(no_token.error == JoinInvite.InvalidReason.MISSING_TOKEN, "缺 t -> MISSING_TOKEN")
	var empty_token: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=&lan=%s" % LAN)
	_expect(empty_token.error == JoinInvite.InvalidReason.MISSING_TOKEN, "t= 空 -> MISSING_TOKEN")
	_expect(not no_token.is_valid(), "缺 token 的 invite 不可用")

## token 是门票，不该出现在展示文案里（避免截图 / 日志泄露）。
func _case_token_not_leaked_in_label() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "NightFox")
	var label: String = invite.display_label()
	_expect(label.find(invite.token) < 0, "display_label 不含 token")
	_expect(label.find("NightFox") >= 0, "display_label 含 Host 名")

## token 不是随便一个字符串：非 hex（例如 profile_id / 名字）必须被拒。
func _case_rejects_non_hex_token() -> void:
	var named: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=NightFox&lan=%s" % LAN)
	_expect(named.error == JoinInvite.InvalidReason.BAD_TOKEN, "非 hex token -> BAD_TOKEN")
	var seated: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=3&lan=%s" % LAN)
	_expect(seated.error == JoinInvite.InvalidReason.BAD_TOKEN, "短 token（像 seat）-> BAD_TOKEN")
	var too_long: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=%s&lan=%s" % ["a".repeat(80), LAN])
	_expect(too_long.error == JoinInvite.InvalidReason.BAD_TOKEN, "超长 token -> BAD_TOKEN")

## 元数据只允许安全字符，防止 URI 注入到 n= / r=。
func _case_display_metadata_sanitized() -> void:
	var injected: JoinInvite = JoinInvite.parse("wpg://join?v=6&t=deadbeefdeadbeef&lan=%s&n=Evil&r=x" % LAN)
	_expect(injected.is_valid(), "元数据里带 & 不会让 invite 失效")
	_expect(injected.host_name.find("&") < 0, "host_name 被清洗掉 &")
	_expect(injected.host_name.find("=") < 0, "host_name 被清洗掉 =")

# ---- 收尾 ----

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("JOIN_INVITE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("JOIN_INVITE_FAIL: %s" % failure)
	quit(1)
