extends SceneTree

## NetworkCandidates 回归（Phase 9.2）：本地候选枚举、分类、去重。
## 纯逻辑，不建 peer、不开端口、不碰 SceneTree.multiplayer。
## 跑法：godot --headless --path . --script res://tests/network_candidates_test.gd
## 通过输出 NETWORK_CANDIDATES_OK；失败逐条 NETWORK_CANDIDATES_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_case_ipv4_classification()
	_case_ipv6_classification()
	_case_loopback_classification()
	_case_private_classification()
	_case_public_classification()
	_case_observed_candidate()
	_case_duplicate_removal()
	_case_priority_sorting()
	_case_filter_usable()
	_case_to_rendezvous_candidate()
	_finish()

# ---- 用例 ----

func _case_ipv4_classification() -> void:
	var loopback: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	loopback.address = "127.0.0.1"
	loopback.port = 17777
	var ctype: int = NetworkCandidates._classify_address("127.0.0.1")
	_expect(ctype == NetworkCandidates.CandidateType.LOOPBACK_ONLY_FOR_TEST, "127.0.0.1 -> LOOPBACK")

	var private1: int = NetworkCandidates._classify_address("192.168.1.50")
	_expect(private1 == NetworkCandidates.CandidateType.LOCAL_PRIVATE, "192.168.1.50 -> LOCAL_PRIVATE")

	var private2: int = NetworkCandidates._classify_address("10.0.0.1")
	_expect(private2 == NetworkCandidates.CandidateType.LOCAL_PRIVATE, "10.0.0.1 -> LOCAL_PRIVATE")

	var private3: int = NetworkCandidates._classify_address("172.16.0.1")
	_expect(private3 == NetworkCandidates.CandidateType.LOCAL_PRIVATE, "172.16.0.1 -> LOCAL_PRIVATE")

	var private4: int = NetworkCandidates._classify_address("172.31.255.255")
	_expect(private4 == NetworkCandidates.CandidateType.LOCAL_PRIVATE, "172.31.255.255 -> LOCAL_PRIVATE")

	var link_local: int = NetworkCandidates._classify_address("169.254.1.1")
	_expect(link_local == NetworkCandidates.CandidateType.LOCAL_LINK_LOCAL, "169.254.1.1 -> LINK_LOCAL")

	var public: int = NetworkCandidates._classify_address("203.0.113.10")
	_expect(public == NetworkCandidates.CandidateType.OBSERVED_PUBLIC, "203.0.113.10 -> OBSERVED_PUBLIC")

func _case_ipv6_classification() -> void:
	var loopback: int = NetworkCandidates._classify_address("::1")
	_expect(loopback == NetworkCandidates.CandidateType.LOOPBACK_ONLY_FOR_TEST, "::1 -> LOOPBACK")

	var link_local: int = NetworkCandidates._classify_address("fe80::1")
	_expect(link_local == NetworkCandidates.CandidateType.LOCAL_LINK_LOCAL, "fe80::1 -> LINK_LOCAL")

	var ula: int = NetworkCandidates._classify_address("fd12:3456:789a::1")
	_expect(ula == NetworkCandidates.CandidateType.LOCAL_IPV6, "ULA fd12:: -> LOCAL_IPV6")

	var ula2: int = NetworkCandidates._classify_address("fc00::1")
	_expect(ula2 == NetworkCandidates.CandidateType.LOCAL_IPV6, "ULA fc00:: -> LOCAL_IPV6")

	var global: int = NetworkCandidates._classify_address("2001:db8::1")
	_expect(global == NetworkCandidates.CandidateType.LOCAL_IPV6, "Global 2001:db8:: -> LOCAL_IPV6")

func _case_loopback_classification() -> void:
	var c: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c.candidate_type = NetworkCandidates.CandidateType.LOOPBACK_ONLY_FOR_TEST
	c.address = "127.0.0.1"
	c.port = 17777
	_expect(c.is_usable(), "loopback candidate is usable")

	var c2: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c2.candidate_type = NetworkCandidates.CandidateType.LOOPBACK_ONLY_FOR_TEST
	c2.address = "::1"
	c2.port = 17777
	_expect(c2.is_usable(), "ipv6 loopback candidate is usable")

func _case_private_classification() -> void:
	var addrs: PackedStringArray = ["192.168.1.1", "10.0.0.1", "172.16.0.1", "172.31.255.255"]
	for addr: String in addrs:
		var ctype: int = NetworkCandidates._classify_address(addr)
		_expect(ctype == NetworkCandidates.CandidateType.LOCAL_PRIVATE, "%s -> LOCAL_PRIVATE" % addr)

func _case_public_classification() -> void:
	var addrs: PackedStringArray = ["203.0.113.10", "198.51.100.5", "8.8.8.8"]
	for addr: String in addrs:
		var ctype: int = NetworkCandidates._classify_address(addr)
		_expect(ctype == NetworkCandidates.CandidateType.OBSERVED_PUBLIC, "%s -> OBSERVED_PUBLIC" % addr)

func _case_observed_candidate() -> void:
	var c: NetworkCandidates.Candidate = NetworkCandidates.from_observed_endpoint("203.0.113.10", 49152, "abc123")
	_expect(c.candidate_type == NetworkCandidates.CandidateType.OBSERVED_PUBLIC, "observed type")
	_expect(c.address == "203.0.113.10", "observed address")
	_expect(c.port == 49152, "observed port")
	_expect(c.observed_address == "203.0.113.10", "observed_address field")
	_expect(c.observed_port == 49152, "observed_port field")
	_expect(c.nonce == "abc123", "nonce field")
	_expect(c.has_observed_endpoint(), "has_observed_endpoint true")

func _case_duplicate_removal() -> void:
	var candidates: Array[NetworkCandidates.Candidate] = []
	var c1: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c1.candidate_type = NetworkCandidates.CandidateType.LOCAL_PRIVATE
	c1.address = "192.168.1.50"
	c1.port = 17777
	var c2: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c2.candidate_type = NetworkCandidates.CandidateType.OBSERVED_PUBLIC
	c2.address = "192.168.1.50"
	c2.port = 17777
	var c3: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c3.candidate_type = NetworkCandidates.CandidateType.LOCAL_PRIVATE
	c3.address = "10.0.0.1"
	c3.port = 17777
	candidates.append(c1)
	candidates.append(c2)
	candidates.append(c3)
	var deduped: Array[NetworkCandidates.Candidate] = NetworkCandidates.deduplicate(candidates)
	_expect(deduped.size() == 2, "deduplicate removes same address:port (keeps first)")
	_expect(deduped[0].candidate_type == NetworkCandidates.CandidateType.LOCAL_PRIVATE, "keeps higher priority (LOCAL_PRIVATE)")

func _case_priority_sorting() -> void:
	var candidates: Array[NetworkCandidates.Candidate] = []
	var c_public: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c_public.candidate_type = NetworkCandidates.CandidateType.OBSERVED_PUBLIC
	c_public.address = "203.0.113.10"
	c_public.port = 49152
	var c_private: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c_private.candidate_type = NetworkCandidates.CandidateType.LOCAL_PRIVATE
	c_private.address = "192.168.1.50"
	c_private.port = 17777
	var c_ipv6: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c_ipv6.candidate_type = NetworkCandidates.CandidateType.LOCAL_IPV6
	c_ipv6.address = "2001:db8::1"
	c_ipv6.port = 17777
	var c_link: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c_link.candidate_type = NetworkCandidates.CandidateType.LOCAL_LINK_LOCAL
	c_link.address = "fe80::1"
	c_link.port = 17777
	candidates.append(c_public)
	candidates.append(c_private)
	candidates.append(c_ipv6)
	candidates.append(c_link)
	NetworkCandidates._sort_by_priority(candidates)
	_expect(candidates[0].candidate_type == NetworkCandidates.CandidateType.LOCAL_PRIVATE, "1st = LOCAL_PRIVATE")
	_expect(candidates[1].candidate_type == NetworkCandidates.CandidateType.LOCAL_IPV6, "2nd = LOCAL_IPV6")
	_expect(candidates[2].candidate_type == NetworkCandidates.CandidateType.LOCAL_LINK_LOCAL, "3rd = LINK_LOCAL")
	_expect(candidates[3].candidate_type == NetworkCandidates.CandidateType.OBSERVED_PUBLIC, "4th = OBSERVED_PUBLIC")

func _case_filter_usable() -> void:
	var candidates: Array[NetworkCandidates.Candidate] = []
	var c1: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c1.address = "192.168.1.50"
	c1.port = 17777
	var c2: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c2.address = ""
	c2.port = 17777
	var c3: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c3.address = "192.168.1.50"
	c3.port = 0
	var c4: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c4.address = "192.168.1.50"
	c4.port = 70000
	candidates.append(c1)
	candidates.append(c2)
	candidates.append(c3)
	candidates.append(c4)
	var filtered: Array[NetworkCandidates.Candidate] = NetworkCandidates.filter_usable(candidates)
	_expect(filtered.size() == 1, "filter_usable keeps only valid")
	_expect(filtered[0].address == "192.168.1.50", "kept valid candidate")

func _case_to_rendezvous_candidate() -> void:
	var c: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c.candidate_type = NetworkCandidates.CandidateType.LOCAL_PRIVATE
	c.address = "192.168.1.50"
	c.port = 17777
	var rc: RendezvousContract.Candidate = NetworkCandidates.to_rendezvous_candidate(c)
	_expect(rc.path == LobbyPlayer.Path.LAN_IPV4, "LOCAL_PRIVATE -> LAN_IPV4")
	_expect(rc.address == "192.168.1.50", "address preserved")
	_expect(rc.port == 17777, "port preserved")

	var c2: NetworkCandidates.Candidate = NetworkCandidates.Candidate.new()
	c2.candidate_type = NetworkCandidates.CandidateType.LOCAL_IPV6
	c2.address = "2001:db8::1"
	c2.port = 17777
	var rc2: RendezvousContract.Candidate = NetworkCandidates.to_rendezvous_candidate(c2)
	_expect(rc2.path == LobbyPlayer.Path.IPV6, "LOCAL_IPV6 -> IPV6")

	var c3: NetworkCandidates.Candidate = NetworkCandidates.from_observed_endpoint("203.0.113.10", 49152, "nonce123")
	var rc3: RendezvousContract.Candidate = NetworkCandidates.to_rendezvous_candidate(c3)
	_expect(rc3.path == LobbyPlayer.Path.WAN_IPV4, "OBSERVED_PUBLIC -> WAN_IPV4")
	_expect(rc3.observed_address == "203.0.113.10", "observed_address preserved")
	_expect(rc3.observed_port == 49152, "observed_port preserved")

# ---- 收尾 ----

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("NETWORK_CANDIDATES_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("NETWORK_CANDIDATES_FAIL: %s" % failure)
	quit(1)