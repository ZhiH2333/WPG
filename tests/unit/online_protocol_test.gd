extends SceneTree

## OnlineProtocol 常量与快照编解码回归（Phase 2A）。
## 跑法：godot --headless --path . --script res://tests/unit/online_protocol_test.gd

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_case_constants_separated_from_lan()
	_case_snapshot_roundtrip()
	_case_snapshot_rejects_bad_payload()
	_case_clamp_display_name()
	_finish()


func _case_constants_separated_from_lan() -> void:
	_expect(OnlineProtocol.PROTOCOL_VERSION == 1, "ONLINE protocol == 1")
	_expect(OnlineProtocol.MAX_PLAYERS == 4, "ONLINE max players == 4")
	_expect(OnlineProtocol.DEFAULT_PORT == 24567, "ONLINE port == 24567")
	_expect(GameLaunch.NET_MAX_SEATS == 5, "LAN seats remain 5")
	_expect(GameLaunch.NET_PORT == 17777, "LAN port remains 17777")
	_expect(GameLaunch.NET_PROTOCOL == 6, "LAN protocol remains 6")
	_expect(OnlineProtocol.DEFAULT_PORT != GameLaunch.NET_PORT, "Online/LAN ports differ")


func _case_snapshot_roundtrip() -> void:
	var p1 := DsPlayerState.new(1, 2, "a")
	p1.position = Vector2(10.5, -3.25)
	var p2 := DsPlayerState.new(2, 3, "b")
	p2.position = Vector2(0, 80)
	var data: PackedByteArray = OnlineProtocol.encode_snapshot(42, [p1, p2])
	var decoded: Dictionary = OnlineProtocol.decode_snapshot(data)
	_expect(bool(decoded["ok"]), "snapshot decode ok")
	_expect(int(decoded["tick"]) == 42, "snapshot tick")
	_expect((decoded["players"] as Array).size() == 2, "snapshot player count")
	var first: Dictionary = (decoded["players"] as Array)[0]
	_expect(int(first["seat"]) == 1, "seat 1 preserved")
	_expect(is_equal_approx((first["position"] as Vector2).x, 10.5), "pos x")
	_expect(is_equal_approx((first["position"] as Vector2).y, -3.25), "pos y")


func _case_snapshot_rejects_bad_payload() -> void:
	_expect(not bool(OnlineProtocol.decode_snapshot(PackedByteArray())["ok"]), "empty rejected")
	var bad := PackedByteArray([9, 0, 0, 0, 0, 1])
	_expect(not bool(OnlineProtocol.decode_snapshot(bad)["ok"]), "bad version rejected")


func _case_clamp_display_name() -> void:
	_expect(OnlineProtocol.clamp_display_name("  ") == "player", "empty -> player")
	_expect(OnlineProtocol.clamp_display_name("abc").length() == 3, "short kept")
	var long_name := ""
	for _i in 40:
		long_name += "x"
	_expect(OnlineProtocol.clamp_display_name(long_name).length() == OnlineProtocol.MAX_DISPLAY_NAME_LEN, "truncated")


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("ONLINE_PROTOCOL_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("ONLINE_PROTOCOL_FAIL: %s" % failure)
	quit(1)
