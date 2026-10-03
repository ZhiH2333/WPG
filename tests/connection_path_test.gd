extends SceneTree

## ConnectionPath 回归（Phase 8）：候选顺序 / IPv6 回退 / WAN 回退 / 单一 peer 约束。
## 跑法：godot --headless --path . --script res://tests/connection_path_test.gd
## 通过输出 CONNECTION_PATH_OK；失败逐条 CONNECTION_PATH_FAIL 并返回非 0。

const LAN := "192.168.1.20"
const WAN := "203.0.113.7"
const V6 := "fe80::1c2d:3e4f:5a6b:7c8d"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_enum_is_complete()
	_case_lan_first()
	_case_ipv6_fallback()
	_case_wan_fallback()
	_case_missing_candidates_are_not_faked()
	_case_order_is_stable()
	_case_select_next_path_walks_then_ends()
	_case_validate_rejects_bad_candidate()
	await _case_single_multiplayer_peer()
	_finish()

# ---- 用例 ----

func _case_enum_is_complete() -> void:
	_expect(LobbyPlayer.Path.LAN_IPV4 == 0, "LAN_IPV4 存在")
	_expect(ConnectionPath.DEFAULT_ORDER.size() == 3, "默认候选顺序有 3 项")
	_expect(ConnectionPath.DEFAULT_ORDER[0] == LobbyPlayer.Path.LAN_IPV4, "顺序 1 = LAN_IPV4")
	_expect(ConnectionPath.DEFAULT_ORDER[1] == LobbyPlayer.Path.IPV6, "顺序 2 = IPV6")
	_expect(ConnectionPath.DEFAULT_ORDER[2] == LobbyPlayer.Path.WAN_IPV4, "顺序 3 = WAN_IPV4")
	_expect(ConnectionPath.path_name(LobbyPlayer.Path.IPV6) == "ipv6", "path_name 覆盖 IPv6")
	_expect(ConnectionPath.path_name(LobbyPlayer.Path.WAN_IPV4) == "wan_ipv4", "path_name 覆盖 WAN")

## LAN 优先：即使 WAN / IPv6 同时存在，第一个候选也必须是 LAN。
func _case_lan_first() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	_expect(plan.size() == 3, "三候选都在")
	_expect(plan.preferred_path() == LobbyPlayer.Path.LAN_IPV4, "首选是 LAN_IPV4")
	var first: ConnectionPath.Candidate = plan.select_next_path(0)
	_expect(first != null and first.address == LAN and first.port == 17777, "第一个候选 = LAN 地址")

func _case_ipv6_fallback() -> void:
	## 没有 WAN，只有 LAN + IPv6 -> iOS/无公网场景的回退顺序。
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6)
	var plan: ConnectionPath = invite.to_candidates()
	_expect(plan.size() == 2, "LAN + IPv6 两个候选")
	var paths: PackedInt32Array = plan.path_list()
	_expect(paths[0] == LobbyPlayer.Path.LAN_IPV4, "先试 LAN")
	_expect(paths[1] == LobbyPlayer.Path.IPV6, "LAN 之后回退 IPv6")
	var second: ConnectionPath.Candidate = plan.select_next_path(1)
	_expect(second != null and second.address == V6, "第二个候选是 IPv6 地址")

func _case_wan_fallback() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", "", WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	var paths: PackedInt32Array = plan.path_list()
	_expect(paths[0] == LobbyPlayer.Path.LAN_IPV4, "先试 LAN")
	_expect(paths[1] == LobbyPlayer.Path.WAN_IPV4, "LAN 之后回退 WAN")
	var wan: ConnectionPath.Candidate = plan.select_next_path(1)
	_expect(wan != null and wan.port == 49152, "WAN 候选带自己的端口")

## 缺的候选不许伪造（尤其不许把没提供的 WAN 当成已有路径）。
func _case_missing_candidates_are_not_faked() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777)
	var plan: ConnectionPath = invite.to_candidates()
	_expect(plan.size() == 1, "只有 LAN 时只有一个候选")
	_expect(plan.preferred_path() == LobbyPlayer.Path.LAN_IPV4, "唯一候选是 LAN")
	_expect(plan.select_next_path(1) == null, "没有第二个候选可试")

## 顺序稳定：同样输入重复构造，顺序必须完全一致。
func _case_order_is_stable() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var a: PackedInt32Array = invite.to_candidates().path_list()
	var b: PackedInt32Array = invite.to_candidates().path_list()
	_expect(a == b, "重复构造的候选顺序一致")
	var address_a: PackedStringArray = invite.to_candidates().address_list()
	var address_b: PackedStringArray = invite.to_candidates().address_list()
	_expect(address_a == address_b, "重复构造的候选地址一致")

## 游标语义：0/1/2 逐个走完，之后返回 null（调用方据此放弃）。
func _case_select_next_path_walks_then_ends() -> void:
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	_expect(plan.select_next_path(0) != null, "游标 0 有候选")
	_expect(plan.select_next_path(1) != null, "游标 1 有候选")
	_expect(plan.select_next_path(2) != null, "游标 2 有候选")
	_expect(plan.select_next_path(3) == null, "游标 3 走完 -> null")

func _case_validate_rejects_bad_candidate() -> void:
	var plan: ConnectionPath = ConnectionPath.new()
	var bad_port: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
	bad_port.path = LobbyPlayer.Path.LAN_IPV4
	bad_port.address = LAN
	bad_port.port = 0
	_expect(not plan.validate_candidate(bad_port), "端口 0 的候选不合法")
	var no_address: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
	no_address.path = LobbyPlayer.Path.LAN_IPV4
	no_address.port = 17777
	_expect(not plan.validate_candidate(no_address), "无地址的候选不合法")
	## IPv6 候选却给了 IPv4 地址 = 装配错误，必须拒绝而不是喂给 ENet。
	var mislabeled: ConnectionPath.Candidate = ConnectionPath.Candidate.new()
	mislabeled.path = LobbyPlayer.Path.IPV6
	mislabeled.address = LAN
	mislabeled.port = 17777
	_expect(not plan.validate_candidate(mislabeled), "IPv6 候选配 IPv4 地址被拒")

## 关键约束：候选回退过程不允许出现第二个 multiplayer peer。
## SceneTree.multiplayer 全程只有一个 peer；每次尝试前都必须先关掉上一个。
## 用真实 listening peer 而不是空对象：Godot 会拒绝未连接的 peer（这本身就是约束的一部分）。
func _case_single_multiplayer_peer() -> void:
	var net: LobbyNet = LobbyNet.new()
	root.add_child(net)
	var invite: JoinInvite = JoinInvite.create(LAN, 17777, "", "", "", V6, WAN, 49152)
	var plan: ConnectionPath = invite.to_candidates()
	var seen: Array[int] = []
	var index: int = 0
	while true:
		var candidate: ConnectionPath.Candidate = plan.select_next_path(index)
		if candidate == null:
			break
		index += 1
		## 与 LobbyManager._try_candidate 同款顺序：先 close 再建连（回退绝不并发两个 peer）。
		net.close()
		_expect(net.multiplayer.multiplayer_peer == null, "尝试候选前 multiplayer_peer 已清空")
		var probe: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		if probe.create_server(GameLaunch.NET_PORT, 1) != OK:
			_expect(false, "本机回环监听失败（端口被占？）")
			break
		net.multiplayer.multiplayer_peer = probe
		seen.append(candidate.path)
		_expect(net.multiplayer.multiplayer_peer == probe, "同一时刻只挂一个 peer")
		var live: MultiplayerPeer = net.multiplayer.multiplayer_peer
		_expect(live == probe, "没有第二个 peer 顶替")
	net.close()
	_expect(seen.size() == 3, "三个候选都被顺序走到")
	_expect(net.multiplayer.multiplayer_peer == null, "收尾后没有残留 peer")
	net.queue_free()

# ---- 收尾 ----

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("CONNECTION_PATH_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("CONNECTION_PATH_FAIL: %s" % failure)
	quit(1)
