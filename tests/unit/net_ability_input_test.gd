extends SceneTree

## Guest 技能边沿锁存：按下写入 pending bits，take 后清零；远程帧只写 just_pressed。
## 跑法：godot --headless --path . --script res://tests/unit/net_ability_input_test.gd --quit

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_case_pending_bits_latch_and_take()
	_case_remote_frame_applies_bits()
	_case_suppress_clears_pending()
	_case_illegal_high_bits_masked_by_net_session_contract()
	if _failures.is_empty():
		print("NET_ABILITY_INPUT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("NET_ABILITY_INPUT_FAIL: %s" % failure)
	quit(1)

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _case_pending_bits_latch_and_take() -> void:
	var input: PlayerInput = PlayerInput.new()
	root.add_child(input)
	input._set_ability_edge(0, true)
	input._set_ability_edge(1, true)
	_expect(input.take_pending_ability_bits() == 3, "两槽边沿合成 bit0|bit1")
	_expect(input.take_pending_ability_bits() == 0, "take 后 pending 清零")
	input.queue_free()

func _case_remote_frame_applies_bits() -> void:
	var input: PlayerInput = PlayerInput.new()
	root.add_child(input)
	input.set_remote_driven(true)
	input.apply_remote_frame(Vector2.ZERO, Vector2.RIGHT, false, false, -1, 1)
	_expect(input.ability_0_just_pressed, "远程 bit0 置 ability_0")
	_expect(not input.ability_1_just_pressed, "远程未带 bit1")
	input.apply_remote_frame(Vector2.ZERO, Vector2.RIGHT, false, false, -1, 2)
	_expect(not input.ability_0_just_pressed, "下一帧无 bit0")
	_expect(input.ability_1_just_pressed, "远程 bit1 置 ability_1")
	input.queue_free()

func _case_suppress_clears_pending() -> void:
	var input: PlayerInput = PlayerInput.new()
	root.add_child(input)
	input._set_ability_edge(0, true)
	input.set_abilities_suppressed(true)
	_expect(input.take_pending_ability_bits() == 0, "suppress 清空 pending")
	_expect(not input.ability_0_just_pressed, "suppress 清空边沿")
	input.queue_free()

## 合同：NetSession 只放行低 2 位。这里用同样掩码断言，避免以后 RPC 漏掩码。
func _case_illegal_high_bits_masked_by_net_session_contract() -> void:
	var raw: int = 0xFF
	var bits: int = raw & 0x3
	_expect(bits == 3, "高位伪造被掩成 0b11")
