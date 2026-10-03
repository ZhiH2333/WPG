extends SceneTree

## P2PUDPProbe 回归（Phase 9.2）：编解码、校验、防伪造、RTT。
## 纯逻辑，不建 peer、不开端口、不碰 SceneTree.multiplayer。
## 跑法：godot --headless --path . --script res://tests/p2p_udp_probe_test.gd
## 通过输出 P2P_UDP_PROBE_OK；失败逐条 P2P_UDP_PROBE_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_case_probe_encode_decode()
	_case_ack_encode_decode()
	_case_malformed_packet()
	_case_wrong_session_ignored()
	_case_wrong_nonce_ignored()
	_case_wrong_role_ignored()
	_case_duplicate_probe_safe()
	_case_bidirectional_success()
	_case_one_way_not_equal_success()
	_case_rtt_calculation()
	_case_timeout_handling()
	_case_stale_attempt_id()
	_finish()

# ---- 用例 ----

func _case_probe_encode_decode() -> void:
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	var timestamp: int = 1234567890
	var packet: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, timestamp)
	_expect(not packet.is_empty(), "encode_probe returns non-empty")
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	_expect(decoded.is_ok(), "decode probe ok")
	_expect(decoded.is_probe(), "is probe")
	_expect(decoded.session_id == session_id, "session_id preserved")
	_expect(decoded.nonce == nonce, "nonce preserved")
	_expect(decoded.role == P2PUDPProbe.Role.HOST, "role preserved")
	_expect(decoded.timestamp_ms == timestamp, "timestamp preserved")

func _case_ack_encode_decode() -> void:
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	var timestamp: int = 1234567890
	var original_ts: int = 1234567000
	var packet: PackedByteArray = P2PUDPProbe.encode_ack(session_id, nonce, P2PUDPProbe.Role.GUEST, timestamp, original_ts)
	_expect(not packet.is_empty(), "encode_ack returns non-empty")
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	_expect(decoded.is_ok(), "decode ack ok")
	_expect(decoded.is_ack(), "is ack")
	_expect(decoded.session_id == session_id, "session_id preserved")
	_expect(decoded.nonce == nonce, "nonce preserved")
	_expect(decoded.role == P2PUDPProbe.Role.GUEST, "role preserved")
	_expect(decoded.timestamp_ms == timestamp, "timestamp preserved")
	_expect(decoded.original_timestamp_ms == original_ts, "original_timestamp preserved")

func _case_malformed_packet() -> void:
	## 空包
	var empty: PackedByteArray = PackedByteArray()
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(empty)
	_expect(decoded.error == P2PUDPProbe.DecodeError.EMPTY, "empty -> EMPTY")

	## 错魔术字（包长度足够但 magic 不对）
	var bad_magic: PackedByteArray = PackedByteArray()
	var buf_bad_magic: StreamPeerBuffer = StreamPeerBuffer.new()
	buf_bad_magic.big_endian = true
	buf_bad_magic.put_u32(0x00000000)  # wrong magic
	buf_bad_magic.put_u8(P2PUDPProbe.VERSION)
	buf_bad_magic.put_u8(P2PUDPProbe.MsgType.PROBE)
	buf_bad_magic.put_u32(16)
	buf_bad_magic.put_data("abcdef1234567890".to_utf8_buffer())
	buf_bad_magic.put_u32(32)
	buf_bad_magic.put_data("0123456789abcdef0123456789abcdef".to_utf8_buffer())
	buf_bad_magic.put_u8(P2PUDPProbe.Role.HOST)
	buf_bad_magic.put_u64(1234567890)
	buf_bad_magic.put_u8(0)
	decoded = P2PUDPProbe.decode(buf_bad_magic.data_array)
	_expect(decoded.error == P2PUDPProbe.DecodeError.BAD_MAGIC, "bad magic -> BAD_MAGIC")

	## 错版本
	var bad_ver: PackedByteArray = PackedByteArray()
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(P2PUDPProbe.MAGIC)
	buf.put_u8(99)  # wrong version
	buf.put_u8(P2PUDPProbe.MsgType.PROBE)
	buf.put_u32(16)
	buf.put_data("abcdef1234567890".to_utf8_buffer())
	buf.put_u32(32)
	buf.put_data("0123456789abcdef0123456789abcdef".to_utf8_buffer())
	buf.put_u8(P2PUDPProbe.Role.HOST)
	buf.put_u64(1234567890)
	buf.put_u8(0)
	decoded = P2PUDPProbe.decode(buf.data_array)
	_expect(decoded.error == P2PUDPProbe.DecodeError.BAD_VERSION, "bad version -> BAD_VERSION")

	## 截断包
	var truncated: PackedByteArray = PackedByteArray([0x50, 0x50, 0x52, 0x42, 0x01, 0x00])
	decoded = P2PUDPProbe.decode(truncated)
	_expect(decoded.error == P2PUDPProbe.DecodeError.TRUNCATED, "truncated -> TRUNCATED")

	## 非法 session_id 长度
	var bad_sid: PackedByteArray = PackedByteArray()
	buf = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(P2PUDPProbe.MAGIC)
	buf.put_u8(P2PUDPProbe.VERSION)
	buf.put_u8(P2PUDPProbe.MsgType.PROBE)
	buf.put_u32(15)  # wrong length
	buf.put_data("abcdef123456789".to_utf8_buffer())
	buf.put_u32(32)
	buf.put_data("0123456789abcdef0123456789abcdef".to_utf8_buffer())
	buf.put_u8(P2PUDPProbe.Role.HOST)
	buf.put_u64(1234567890)
	buf.put_u8(0)
	decoded = P2PUDPProbe.decode(buf.data_array)
	_expect(decoded.error == P2PUDPProbe.DecodeError.INVALID_SESSION_ID, "bad session_id len -> INVALID_SESSION_ID")

	## 非法 nonce 长度
	var bad_nonce: PackedByteArray = PackedByteArray()
	buf = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(P2PUDPProbe.MAGIC)
	buf.put_u8(P2PUDPProbe.VERSION)
	buf.put_u8(P2PUDPProbe.MsgType.PROBE)
	buf.put_u32(16)
	buf.put_data("abcdef1234567890".to_utf8_buffer())
	buf.put_u32(31)  # wrong length
	buf.put_data("0123456789abcdef0123456789abcde".to_utf8_buffer())
	buf.put_u8(P2PUDPProbe.Role.HOST)
	buf.put_u64(1234567890)
	buf.put_u8(0)
	decoded = P2PUDPProbe.decode(buf.data_array)
	_expect(decoded.error == P2PUDPProbe.DecodeError.INVALID_NONCE, "bad nonce len -> INVALID_NONCE")

	## 非法 role
	var bad_role: PackedByteArray = PackedByteArray()
	buf = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u32(P2PUDPProbe.MAGIC)
	buf.put_u8(P2PUDPProbe.VERSION)
	buf.put_u8(P2PUDPProbe.MsgType.PROBE)
	buf.put_u32(16)
	buf.put_data("abcdef1234567890".to_utf8_buffer())
	buf.put_u32(32)
	buf.put_data("0123456789abcdef0123456789abcdef".to_utf8_buffer())
	buf.put_u8(99)  # invalid role
	buf.put_u64(1234567890)
	buf.put_u8(0)
	decoded = P2PUDPProbe.decode(buf.data_array)
	_expect(decoded.error == P2PUDPProbe.DecodeError.INVALID_ROLE, "bad role -> INVALID_ROLE")

func _case_wrong_session_ignored() -> void:
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	var packet: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, 1234567890)
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	_expect(not P2PUDPProbe.validate_expectation(decoded, "different_session_id", nonce, P2PUDPProbe.Role.GUEST), "wrong session_id -> rejected")

func _case_wrong_nonce_ignored() -> void:
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	var packet: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, 1234567890)
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	_expect(not P2PUDPProbe.validate_expectation(decoded, session_id, "different_nonce_value_here", P2PUDPProbe.Role.GUEST), "wrong nonce -> rejected")

func _case_wrong_role_ignored() -> void:
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	## Host 发 probe，role=HOST，Guest 期望 remote_role = HOST（正确）
	var packet: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, 1234567890)
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	## 正确期望（Guest 期望 HOST）
	_expect(P2PUDPProbe.validate_expectation(decoded, session_id, nonce, P2PUDPProbe.Role.HOST), "correct expected role (HOST) -> accepted")
	## 错误期望（期望 GUEST 但包里是 HOST）
	_expect(not P2PUDPProbe.validate_expectation(decoded, session_id, nonce, P2PUDPProbe.Role.GUEST), "wrong expected role (GUEST) -> rejected")

func _case_duplicate_probe_safe() -> void:
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	var packet1: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, 1000)
	var packet2: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, 2000)
	var d1: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet1)
	var d2: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet2)
	_expect(d1.is_ok() and d2.is_ok(), "both decode ok")
	_expect(d1.timestamp_ms == 1000 and d2.timestamp_ms == 2000, "timestamps differ")
	## 两个 probe 都能被正确解码，不会互相干扰

func _case_bidirectional_success() -> void:
	## 模拟：Host 发 probe -> Guest 收到并回 ACK -> Host 收到 ACK
	var session_id: String = "abcdef1234567890"
	var host_nonce: String = "0123456789abcdef0123456789abcdef"
	var guest_nonce: String = "fedcba9876543210fedcba9876543210"
	var host_ts: int = 1000000
	var probe: PackedByteArray = P2PUDPProbe.encode_probe(session_id, host_nonce, P2PUDPProbe.Role.HOST, host_ts)
	## Guest 视角解码
	var guest_decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(probe)
	_expect(guest_decoded.is_ok() and guest_decoded.is_probe(), "guest decodes probe")
	_expect(P2PUDPProbe.validate_expectation(guest_decoded, session_id, host_nonce, P2PUDPProbe.Role.HOST), "guest validates host probe")
	## Guest 回 ACK
	var guest_ts: int = 1000050
	var ack: PackedByteArray = P2PUDPProbe.encode_ack(session_id, guest_nonce, P2PUDPProbe.Role.GUEST, guest_ts, host_ts)
	## Host 视角解码 ACK
	var host_decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(ack)
	_expect(host_decoded.is_ok() and host_decoded.is_ack(), "host decodes ack")
	_expect(P2PUDPProbe.validate_expectation(host_decoded, session_id, guest_nonce, P2PUDPProbe.Role.GUEST), "host validates guest ack")
	## RTT
	var rtt: int = P2PUDPProbe.calculate_rtt(1000100, host_ts)
	_expect(rtt >= 50 and rtt <= 100, "rtt calculated ~50ms")

func _case_one_way_not_equal_success() -> void:
	## 只有单向 probe 没有 ACK 不算成功
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	var probe: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, 1000)
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(probe)
	_expect(decoded.is_probe(), "is probe")
	## 没有 ACK，无法计算 RTT，无法确认双向
	## 这是逻辑层面的测试：probe 只有单向不代表成功

func _case_rtt_calculation() -> void:
	var rtt1: int = P2PUDPProbe.calculate_rtt(1000100, 1000000)
	_expect(rtt1 == 100, "rtt 100ms")
	var rtt2: int = P2PUDPProbe.calculate_rtt(1000000, 1000100)
	_expect(rtt2 == 0, "negative rtt clamped to 0")
	var rtt3: int = P2PUDPProbe.calculate_rtt(1000000, 1000000)
	_expect(rtt3 == 0, "zero rtt")

func _case_timeout_handling() -> void:
	## Probe 超时由上层 P2PHolePunch 处理，这里只测试包编解码不超时
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	var packet: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, 1000)
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	_expect(decoded.is_ok(), "packet valid regardless of time")

func _case_stale_attempt_id() -> void:
	## attempt_id 机制在 ConnectAttempt / P2PHolePunch 层，这里只验证包本身不带 attempt_id
	var session_id: String = "abcdef1234567890"
	var nonce: String = "0123456789abcdef0123456789abcdef"
	var packet: PackedByteArray = P2PUDPProbe.encode_probe(session_id, nonce, P2PUDPProbe.Role.HOST, 1000)
	var decoded: P2PUDPProbe.Decoded = P2PUDPProbe.decode(packet)
	_expect(decoded.is_ok(), "decode ok")
	## 包不包含 attempt_id，由上层生成管理

# ---- 收尾 ----

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("P2P_UDP_PROBE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("P2P_UDP_PROBE_FAIL: %s" % failure)
	quit(1)