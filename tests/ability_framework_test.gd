extends SceneTree

## Ability Framework 回归（Ability 第一刀）。
##
## 锁定：
##   AbilityDef 数据 / AbilityState 状态机 / AbilityController 生命周期 /
##   AbilityEffect + AbilityContext / cost 最小接口 / edge 语义 / pause 屏蔽 /
##   Keyboard + Touch 两条输入源最终都进 PlayerInput 的同一个 ability slot /
##   以及 data/abilities 下两个真实 .tres（duration 类 + instant 类）。
##
## 跑法：godot --headless --path . --script res://tests/ability_framework_test.gd --quit
## 通过输出 ABILITY_FRAMEWORK_OK；失败逐条 ABILITY_FRAMEWORK_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

# ---- 测试替身 ----

## 记录 apply / remove 次数的最小执行体，用来验证 Controller 的生命周期。
class RecordingEffect extends AbilityEffect:
	var applies: int = 0
	var removes: int = 0
	func apply(_context: AbilityContext) -> void:
		applies += 1
	func remove(_context: AbilityContext) -> void:
		removes += 1

## 最小 Cost 接口替身。
class CostProvider extends RefCounted:
	var available: bool = true
	var paid: int = 0
	func can_pay_ability_cost(_cost_type: int, _value: int) -> bool:
		return available
	func pay_ability_cost(_cost_type: int, _value: int) -> bool:
		if not available:
			return false
		paid += 1
		return true

## 最小 caster 替身：只提供 get_player_motor()（BoostSpeedEffect 的契约）。
class StubCaster extends Node2D:
	var motor: PlayerMotor = null
	func get_player_motor() -> PlayerMotor:
		return motor

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	PlayerProfile.load_from_disk()
	_case_ability_def()
	_case_initial_ready()
	_case_activate_to_active_and_duration()
	_case_cooldown_expiration()
	_case_instant_ability()
	_case_blocked_during_cooldown()
	_case_disabled()
	_case_cost_validation()
	_case_clear_resets()
	_case_cancel()
	_case_pause_suppresses_player_input()
	_case_pause_suppresses_controller()
	_case_touch_edges_are_edges()
	_case_touch_multi_slot_independent()
	_case_ability_data_resources()
	_case_boost_speed_effect_real_data()
	_case_aim_pulse_effect_real_data()
	_case_keyboard_input_map()
	_case_keyboard_edge_reaches_controller()
	_case_player_scene_wiring()

	if _failures.is_empty():
		print("ABILITY_FRAMEWORK_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("ABILITY_FRAMEWORK_FAIL: %s" % failure)
	quit(1)

# ---- 1. AbilityDef 创建 ----

func _case_ability_def() -> void:
	var effect: RecordingEffect = RecordingEffect.new()
	var def: AbilityDef = _make_def(effect, 6.0, 3.0)
	_expect(def.id == &"test_ability", "AbilityDef 保存 id")
	_expect(is_equal_approx(def.cooldown, 6.0), "AbilityDef 保存 cooldown")
	_expect(is_equal_approx(def.duration, 3.0), "AbilityDef 保存 duration")
	_expect(def.effect == effect, "AbilityDef 保存 effect 资源引用")
	_expect(def.target_type == AbilityDef.TargetType.SELF, "AbilityDef 保存 target_type")
	_expect(not def.is_instant(), "duration > 0 不是 instant")
	_expect(not def.has_cost(), "默认没有 cost")
	## AbilityDef 必须能表达 spec 要求的四种 target（只用 int() 断言成员存在）。
	_expect(int(AbilityDef.TargetType.SELF) == 0 and int(AbilityDef.TargetType.DIRECTION) == 1 \
		and int(AbilityDef.TargetType.AREA) == 2 and int(AbilityDef.TargetType.TARGET) == 3,
		"TargetType 预留 SELF/DIRECTION/AREA/TARGET")
	var self_def: AbilityDef = AbilityDef.new()
	self_def.target_type = AbilityDef.TargetType.DIRECTION
	_expect(self_def.target_type == AbilityDef.TargetType.DIRECTION, "target_type 可写")

# ---- 2. 初始 READY ----

func _case_initial_ready() -> void:
	var controller: AbilityController = _make_controller()
	_expect(controller.get_state(0) == AbilityState.DISABLED, "未装备槽位是 DISABLED")
	_expect(not controller.can_activate(0), "未装备不能激活")
	controller.equip(0, _make_def(RecordingEffect.new(), 5.0, 0.0))
	_expect(controller.get_state(0) == AbilityState.READY, "装备后是 READY")
	_expect(controller.can_activate(0), "READY 可激活")
	_expect(is_equal_approx(controller.get_remaining_cooldown(0), 0.0), "初始冷却为 0")
	controller.queue_free()

# ---- 3/4/5. activate -> ACTIVE -> duration ----

func _case_activate_to_active_and_duration() -> void:
	var controller: AbilityController = _make_controller()
	var effect: RecordingEffect = RecordingEffect.new()
	controller.equip(0, _make_def(effect, 6.0, 3.0))
	var activated: Array = []
	controller.ability_activated.connect(func(index: int, _def: Resource) -> void: activated.append(index))

	_expect(controller.try_activate(0), "READY 时 try_activate 成功")
	_expect(effect.applies == 1, "effect.apply 调用一次")
	_expect(activated == [0], "ability_activated 派发一次")
	_expect(controller.get_state(0) == AbilityState.ACTIVE, "有 duration -> ACTIVE")
	_expect(is_equal_approx(controller.get_remaining_duration(0), 3.0), "剩余持续时间 = duration")
	_expect(not controller.can_activate(0), "ACTIVE 期间不能再次激活")

	controller.tick(1.0)
	_expect(controller.get_state(0) == AbilityState.ACTIVE, "duration 未走完仍是 ACTIVE")
	_expect(is_equal_approx(controller.get_remaining_duration(0), 2.0), "剩余持续时间递减")
	_expect(effect.removes == 0, "duration 未走完不 remove")

	controller.tick(2.5)
	_expect(controller.get_state(0) == AbilityState.COOLDOWN, "duration 走完 -> COOLDOWN")
	_expect(effect.removes == 1, "duration 走完 remove 一次（还原现场）")
	_expect(is_equal_approx(controller.get_remaining_duration(0), 0.0), "ACTIVE 结束后剩余 duration 归零")
	_expect(is_equal_approx(controller.get_remaining_cooldown(0), 6.0), "进入冷却后剩余 = cooldown")
	controller.queue_free()

# ---- 6/7. COOLDOWN -> 冷却结束 -> READY ----

func _case_cooldown_expiration() -> void:
	var controller: AbilityController = _make_controller()
	controller.equip(0, _make_def(RecordingEffect.new(), 6.0, 0.0))
	_expect(controller.try_activate(0), "激活进入冷却")
	_expect(is_equal_approx(controller.get_remaining_cooldown(0), 6.0), "冷却 6s")
	controller.tick(2.0)
	_expect(controller.get_state(0) == AbilityState.COOLDOWN, "冷却中")
	_expect(is_equal_approx(controller.get_remaining_cooldown(0), 4.0), "冷却递减")
	controller.tick(4.0)
	_expect(controller.get_state(0) == AbilityState.READY, "冷却结束回 READY")
	_expect(is_equal_approx(controller.get_remaining_cooldown(0), 0.0), "冷却归零")
	_expect(controller.can_activate(0), "冷却结束后可再放")
	controller.queue_free()

# ---- 8. instant ability ----

func _case_instant_ability() -> void:
	var controller: AbilityController = _make_controller()
	var effect: RecordingEffect = RecordingEffect.new()
	controller.equip(0, _make_def(effect, 4.0, 0.0))
	_expect(controller.get_def(0).is_instant(), "duration 0 = instant")
	_expect(controller.try_activate(0), "instant 激活成功")
	_expect(effect.applies == 1, "instant apply 一次")
	_expect(controller.get_state(0) == AbilityState.COOLDOWN, "instant 不经过 ACTIVE，直接 COOLDOWN")
	_expect(is_equal_approx(controller.get_remaining_cooldown(0), 4.0), "instant 冷却生效")
	_expect(effect.removes == 0, "instant 没有 remove 回调")
	controller.queue_free()

# ---- 9. blocked during cooldown ----

func _case_blocked_during_cooldown() -> void:
	var controller: AbilityController = _make_controller()
	var effect: RecordingEffect = RecordingEffect.new()
	controller.equip(0, _make_def(effect, 6.0, 0.0))
	controller.try_activate(0)
	_expect(not controller.can_activate(0), "冷却中 can_activate = false")
	_expect(not controller.try_activate(0), "冷却中再次激活被拒")
	_expect(effect.applies == 1, "被拒时不会重复 apply")
	controller.queue_free()

# ---- 10. disabled ----

func _case_disabled() -> void:
	var controller: AbilityController = _make_controller()
	controller.equip(0, _make_def(RecordingEffect.new(), 6.0, 0.0))
	controller.set_disabled(0, true)
	_expect(controller.get_state(0) == AbilityState.DISABLED, "set_disabled -> DISABLED")
	_expect(not controller.can_activate(0), "DISABLED 不能激活")
	_expect(not controller.try_activate(0), "DISABLED 激活被拒")
	controller.set_disabled(0, false)
	_expect(controller.get_state(0) == AbilityState.READY, "解除禁用回 READY")
	_expect(controller.can_activate(0), "解除后可以激活")
	## ACTIVE 中被禁用：立刻收尾效果，不能继续放。
	var active_effect: RecordingEffect = RecordingEffect.new()
	controller.equip(0, _make_def(active_effect, 0.0, 3.0))
	controller.try_activate(0)
	_expect(controller.get_state(0) == AbilityState.ACTIVE, "再次激活进入 ACTIVE")
	controller.set_disabled(0, true)
	_expect(controller.get_state(0) == AbilityState.DISABLED, "ACTIVE 中被禁用 -> DISABLED")
	_expect(active_effect.removes == 1, "禁用会收尾在施放的效果")
	controller.queue_free()

# ---- 11. cost validation ----

func _case_cost_validation() -> void:
	var controller: AbilityController = _make_controller()
	var def: AbilityDef = _make_def(RecordingEffect.new(), 1.0, 0.0)
	def.cost_type = AbilityDef.CostType.HP
	def.cost_value = 10
	controller.equip(0, def)
	_expect(def.has_cost(), "带 cost 的技能 has_cost")
	## 没绑 provider：fail closed，不能放（避免"免费放技能"）。
	_expect(not controller.can_activate(0), "没绑 cost provider 时非零 cost 被拒")
	_expect(not controller.try_activate(0), "没绑 provider 激活被拒")

	var provider: CostProvider = CostProvider.new()
	controller.bind_cost_provider(provider)
	_expect(controller.can_activate(0), "provider 可支付时可以激活")
	_expect(controller.try_activate(0), "带 cost 激活成功")
	_expect(provider.paid == 1, "cost 被真正扣除一次")

	## 资源不足：拒绝。
	controller.clear()
	controller.equip(0, def)
	provider.available = false
	_expect(not controller.can_activate(0), "资源不足时不能激活")
	_expect(not controller.try_activate(0), "资源不足激活被拒")
	_expect(provider.paid == 1, "被拒时不会扣费")
	controller.queue_free()

# ---- 16. clear resets state ----

func _case_clear_resets() -> void:
	var controller: AbilityController = _make_controller()
	var effect: RecordingEffect = RecordingEffect.new()
	controller.equip(0, _make_def(effect, 6.0, 3.0))
	controller.equip(1, _make_def(RecordingEffect.new(), 4.0, 0.0))
	controller.try_activate(0)
	controller.try_activate(1)
	_expect(controller.get_state(0) == AbilityState.ACTIVE, "清空前后台有 ACTIVE")
	_expect(controller.get_state(1) == AbilityState.COOLDOWN, "清空前后台有 COOLDOWN")

	controller.clear()
	_expect(controller.get_state(0) == AbilityState.READY, "clear 后 ACTIVE 槽回 READY")
	_expect(controller.get_state(1) == AbilityState.READY, "clear 后 COOLDOWN 槽回 READY")
	_expect(is_equal_approx(controller.get_remaining_cooldown(1), 0.0), "clear 清掉冷却")
	_expect(is_equal_approx(controller.get_remaining_duration(0), 0.0), "clear 清掉持续时间")
	_expect(effect.removes == 1, "clear 会收尾在施放的效果")
	_expect(controller.can_activate(0) and controller.can_activate(1), "clear 后都能放")
	controller.queue_free()

# ---- cancel ----

func _case_cancel() -> void:
	var controller: AbilityController = _make_controller()
	var effect: RecordingEffect = RecordingEffect.new()
	controller.equip(0, _make_def(effect, 6.0, 3.0))
	controller.try_activate(0)
	controller.cancel(0)
	_expect(controller.get_state(0) == AbilityState.READY, "cancel 回 READY")
	_expect(is_equal_approx(controller.get_remaining_cooldown(0), 0.0), "cancel 不给冷却")
	_expect(effect.removes == 1, "cancel 收尾效果")
	controller.queue_free()

# ---- 15. pause / modal 屏蔽 ----

func _case_pause_suppresses_player_input() -> void:
	var player_input: PlayerInput = PlayerInput.new()
	root.add_child(player_input)
	player_input.set_touch_active(true)

	player_input.queue_touch_ability(0)
	player_input._update_ability_edges()
	_expect(player_input.ability_0_just_pressed, "触屏 A0 产生一次边沿")

	player_input.set_abilities_suppressed(true)
	_expect(not player_input.ability_0_just_pressed, "屏蔽瞬间清掉边沿")
	player_input.queue_touch_ability(0)
	player_input._update_ability_edges()
	_expect(not player_input.ability_0_just_pressed, "暂停期间排队也不会产出边沿")
	_expect(player_input.is_abilities_suppressed(), "屏蔽状态可读")

	player_input.set_abilities_suppressed(false)
	player_input._update_ability_edges()
	_expect(not player_input.ability_0_just_pressed, "解锁当帧不会补放暂停期间按下的技能")
	player_input.queue_free()

func _case_pause_suppresses_controller() -> void:
	var player_input: PlayerInput = PlayerInput.new()
	root.add_child(player_input)
	var controller: AbilityController = _make_controller()
	controller.bind_input(player_input)
	var effect: RecordingEffect = RecordingEffect.new()
	controller.equip(0, _make_def(effect, 6.0, 0.0))

	controller.set_suppressed(true)
	_expect(not controller.can_activate(0), "suppressed 时 can_activate = false")
	_expect(not controller.try_activate(0), "suppressed 时激活被拒")
	_expect(effect.applies == 0, "suppressed 时不会 apply")
	controller.set_suppressed(false)
	_expect(controller.try_activate(0), "解除屏蔽后可以激活")
	controller.queue_free()
	player_input.queue_free()

# ---- 12/13/14. edge 语义（Touch 源，确定性最强）----

func _case_touch_edges_are_edges() -> void:
	var player_input: PlayerInput = PlayerInput.new()
	root.add_child(player_input)
	player_input.set_touch_active(true)

	## 按一下：一次边沿。
	player_input.queue_touch_ability(0)
	player_input._update_ability_edges()
	_expect(player_input.ability_0_just_pressed, "A0 tap -> 一次边沿")

	## 按住不放（不再 queue）：后续帧没有边沿，不会重复触发。
	for _i: int in 3:
		player_input._update_ability_edges()
		_expect(not player_input.ability_0_just_pressed, "按住不重复产出边沿")

	## 松开后再按：又是新的一次边沿。
	player_input.queue_touch_ability(0)
	player_input._update_ability_edges()
	_expect(player_input.ability_0_just_pressed, "松开后再按 -> 新边沿")
	player_input.queue_free()

func _case_touch_multi_slot_independent() -> void:
	var player_input: PlayerInput = PlayerInput.new()
	root.add_child(player_input)
	player_input.set_touch_active(true)

	player_input.queue_touch_ability(1)
	player_input._update_ability_edges()
	_expect(player_input.ability_1_just_pressed, "A1 tap -> ability_1 边沿")
	_expect(not player_input.ability_0_just_pressed, "A1 不影响 ability_0")

	player_input.queue_touch_ability(0)
	player_input._update_ability_edges()
	_expect(player_input.ability_0_just_pressed, "A0 tap -> ability_0 边沿")
	_expect(not player_input.ability_1_just_pressed, "两个槽位互不串台")

	## 越界槽位被安全忽略。
	player_input.queue_touch_ability(5)
	player_input._update_ability_edges()
	_expect(not player_input.ability_0_just_pressed and not player_input.ability_1_just_pressed, "越界槽位被忽略")
	player_input.queue_free()

# ---- 真实数据资源 ----

func _case_ability_data_resources() -> void:
	var slot0: AbilityDef = load("res://data/abilities/ability_0.tres") as AbilityDef
	var slot1: AbilityDef = load("res://data/abilities/ability_1.tres") as AbilityDef
	_expect(slot0 != null, "ability_0.tres 能加载为 AbilityDef")
	_expect(slot1 != null, "ability_1.tres 能加载为 AbilityDef")
	if slot0 == null or slot1 == null:
		return
	_expect(slot0.id == &"surge" and not slot0.display_name.is_empty(), "ability_0 有 id/名字")
	_expect(slot0.duration > 0.0 and slot0.cooldown > 0.0, "ability_0 是 duration 类且有冷却")
	_expect(slot0.effect is BoostSpeedEffect, "ability_0 挂 BoostSpeedEffect")
	_expect(slot0.target_type == AbilityDef.TargetType.SELF, "ability_0 是 SELF")
	_expect(slot1.is_instant(), "ability_1 是 instant")
	_expect(slot1.cooldown > 0.0, "ability_1 有冷却")
	_expect(slot1.effect is AimPulseEffect, "ability_1 挂 AimPulseEffect")
	_expect(slot1.target_type == AbilityDef.TargetType.DIRECTION, "ability_1 是 DIRECTION")
	_expect(not slot0.has_cost() and not slot1.has_cost(), "两个测试技能都不带 cost")

## ability_0：SELF + duration，真的改到 PlayerMotor.move_speed，并在 duration 后还原。
func _case_boost_speed_effect_real_data() -> void:
	var caster: StubCaster = StubCaster.new()
	caster.motor = PlayerMotor.new()
	root.add_child(caster)
	var base_speed: float = caster.motor.move_speed

	var def: AbilityDef = load("res://data/abilities/ability_0.tres") as AbilityDef
	var controller: AbilityController = _make_controller(null, caster)
	controller.equip(0, def)
	_expect(controller.try_activate(0), "ability_0 激活成功")
	_expect(caster.motor.move_speed > base_speed, "duration 期间移速被提升")

	controller.tick(def.duration + 0.1)
	_expect(controller.get_state(0) == AbilityState.COOLDOWN, "duration 结束进冷却")
	_expect(is_equal_approx(caster.motor.move_speed, base_speed), "duration 结束后移速还原（不写回 AbilityDef）")
	_expect(is_equal_approx(float(def.parameters.get("base_move_speed", -1.0)), -1.0), "绝没有把运行时状态写进 AbilityDef.parameters")
	controller.queue_free()
	caster.queue_free()

## ability_1：DIRECTION + instant，在瞄准方向生成一个 AbilityPulse。
func _case_aim_pulse_effect_real_data() -> void:
	var caster: StubCaster = StubCaster.new()
	caster.motor = PlayerMotor.new()
	caster.global_position = Vector2(100.0, 50.0)
	root.add_child(caster)

	var player_input: PlayerInput = PlayerInput.new()
	root.add_child(player_input)
	player_input.aim_vector = Vector2.RIGHT

	var def: AbilityDef = load("res://data/abilities/ability_1.tres") as AbilityDef
	var controller: AbilityController = _make_controller(player_input, caster)
	controller.equip(0, def)
	var before: int = caster.get_parent().get_child_count()
	_expect(controller.try_activate(0), "ability_1 激活成功")
	_expect(controller.get_state(0) == AbilityState.COOLDOWN, "instant 技能直接进冷却")

	var pulse: AbilityPulse = null
	for child: Node in caster.get_parent().get_children():
		if child is AbilityPulse:
			pulse = child
			break
	_expect(caster.get_parent().get_child_count() == before + 1, "aim 方向生成了一个脉冲节点")
	_expect(pulse != null, "脉冲是 AbilityPulse")
	if pulse != null:
		_expect(pulse.global_position.x > caster.global_position.x, "脉冲落在瞄准方向而不是脚下")
	controller.queue_free()
	player_input.queue_free()
	caster.queue_free()

# ---- Keyboard / Gamepad：InputMap + 真的走到 Controller ----

func _case_keyboard_input_map() -> void:
	_expect(InputMap.has_action("ability_0"), "InputMap 有 ability_0")
	_expect(InputMap.has_action("ability_1"), "InputMap 有 ability_1")
	_expect(_action_has_key("ability_0", KEY_Q), "ability_0 默认绑 Q")
	_expect(_action_has_key("ability_1", KEY_E), "ability_1 默认绑 E")
	_expect(_action_has_joy_button("ability_0"), "ability_0 绑了手柄钮")
	_expect(_action_has_joy_button("ability_1"), "ability_1 绑了手柄钮")
	## 技能 action 绝不能和现有关卡动作撞名 / 撞键。
	_expect(not _action_has_key("dash", KEY_Q) and not _action_has_key("dash", KEY_E), "技能键不与 dash 冲突")

func _action_has_key(action: String, physical_keycode: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null and key.physical_keycode == physical_keycode:
			return true
	return false

func _action_has_joy_button(action: String) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return true
	return false

## 键盘 / 手柄链条：InputMap(ability_0 <- Q) -> PlayerInput 边沿字段 -> AbilityController -> Effect。
##
## 这里全程同步，不 await 帧：CI 的 --quit 只跑第一帧就退出，任何跨帧等待的测试都不会产出
## *_OK 标记（现有 multiplayer_page_test 因为 await create_timer 也有同样问题）。
## 真实按键注入（parse_input_event）已经单独验证过可以走通整条链，但那需要等 Godot 把事件
## flush 到后面几帧，不适合放在这个必须同步收尾的回归里。
## 所以：键位绑定由 _case_keyboard_input_map 断言，边沿消费由这里断言。
func _case_keyboard_edge_reaches_controller() -> void:
	_expect(PlayerInput.ABILITY_ACTIONS == ["ability_0", "ability_1"],
		"PlayerInput 的键鼠/手柄分支读的就是 ability_0 / ability_1")
	var player_input: PlayerInput = PlayerInput.new()
	root.add_child(player_input)
	var controller: AbilityController = _make_controller()
	controller.bind_input(player_input)
	var effect: RecordingEffect = RecordingEffect.new()
	controller.equip(0, _make_def(effect, 6.0, 0.0))

	## PlayerInput 每帧重算边沿；这里直接给出「本帧刚按下」的状态。
	player_input.ability_0_just_pressed = true
	controller._physics_process(0.016)
	_expect(effect.applies == 1, "ability_0 边沿被 Controller 消费并执行 Effect")
	_expect(controller.get_state(0) == AbilityState.COOLDOWN, "键盘激活后进入冷却")

	## 按住不放：下一帧边沿归零，不会重复触发。
	player_input.ability_0_just_pressed = false
	for _i: int in 5:
		controller._physics_process(0.016)
	_expect(effect.applies == 1, "按住不会重复触发技能")

	controller.queue_free()
	player_input.queue_free()

# ---- 工具 ----

func _make_def(effect: AbilityEffect, cooldown: float, duration: float) -> AbilityDef:
	var def: AbilityDef = AbilityDef.new()
	def.id = &"test_ability"
	def.display_name = "Test"
	def.cooldown = cooldown
	def.duration = duration
	def.effect = effect
	return def

func _make_controller(player_input: PlayerInput = null, caster: Node2D = null) -> AbilityController:
	var controller: AbilityController = AbilityController.new()
	root.add_child(controller)
	if player_input != null:
		controller.bind_input(player_input)
	if caster != null:
		controller.bind_actor(caster)
	return controller

## 真实 player.tscn 的接线：AbilityController 是 Player 的兄弟节点（不在 WeaponHost 里），
## 拿到 PlayerInput 与 caster 引用，并且两个 .tres 真的装备上了。
func _case_player_scene_wiring() -> void:
	var packed: PackedScene = load("res://player/player.tscn") as PackedScene
	_expect(packed != null, "player.tscn 能加载")
	if packed == null:
		return
	var player: Player = packed.instantiate() as Player
	root.add_child(player)

	var controller: AbilityController = player.get_ability_controller()
	_expect(controller != null, "Player 场景里有 AbilityController 节点")
	if controller == null:
		player.queue_free()
		return

	## 结构：Player{PlayerInput, WeaponHost, AbilityController}，技能绝不塞进 WeaponHost。
	_expect(player.get_node_or_null("PlayerInput") != null, "Player 下有 PlayerInput")
	_expect(player.get_node_or_null("WeaponHost") != null, "Player 下有 WeaponHost")
	_expect(player.get_node_or_null("AbilityController") != null, "AbilityController 挂在 Player 下")
	_expect(player.get_weapon_host().get_node_or_null("AbilityController") == null, "AbilityController 不在 WeaponHost 下")

	_expect(controller.get_def(0) != null and controller.get_def(1) != null, "两个技能槽都装备了 AbilityDef")
	_expect(controller.get_state(0) == AbilityState.READY, "ability_0 初始 READY")
	_expect(controller.get_state(1) == AbilityState.READY, "ability_1 初始 READY")
	_expect(controller.get_def(0).id == &"surge", "槽位 0 装备 surge")
	_expect(controller.get_def(1).id == &"pulse", "槽位 1 装备 pulse")

	## 端到端（真实 Player + 真实 .tres + 真实 PlayerMotor）：
	## PlayerInput 边沿 -> Controller -> BoostSpeedEffect -> PlayerMotor.move_speed。
	var motor: PlayerMotor = player.get_player_motor()
	var base_speed: float = motor.move_speed
	player.get_player_input().ability_0_just_pressed = true
	controller._physics_process(0.016)
	_expect(controller.get_state(0) == AbilityState.ACTIVE, "真实 Player 上 ability_0 -> ACTIVE")
	_expect(motor.move_speed > base_speed, "真实 Player 移速被 Surge 提升")
	controller.tick(controller.get_def(0).duration + 0.1)
	_expect(is_equal_approx(motor.move_speed, base_speed), "duration 结束后真实 Player 移速还原")

	player.queue_free()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
