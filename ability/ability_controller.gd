extends Node
class_name AbilityController

## 玩家技能运行时管理器。只有两个槽位：ability_0 / ability_1。
##
## 职责（只做这些）：
##   装备 AbilityDef、维护 READY/ACTIVE/COOLDOWN/DISABLED、冷却与持续时间、
##   消费 PlayerInput 的技能边沿、构造 AbilityContext、驱动 AbilityEffect。
##
## 明确不做：
##   键盘 / 鼠标 / Touch（归 PlayerInput）、UI、Lobby、NetSession、Combat 数值。
##   它只回答一件事：「这个玩家现在能不能放这个技能，放完处于什么状态。」
##
## 多人兼容缝（本阶段不接网络）：
##   request_activate() 是输入/本地调用的入口；activate_authoritative() 是真正执行。
##   将来接 NetSession 时，request_activate() 改成发请求，由权威端调 activate_authoritative()。
##   冷却 / 持续时间全部按 tick(delta) 累积，不读本地 wall clock —— 将来把 delta 换成
##   权威端的 delta 即可，不需要改 Effect 或 UI。

const SLOT_COUNT: int = 2

signal ability_activated(index: int, def: Resource)
signal ability_state_changed(index: int, state: int)
signal ability_finished(index: int, def: Resource)

@export var ability_0: AbilityDef = null
@export var ability_1: AbilityDef = null

var _defs: Array[AbilityDef] = [null, null]
var _states: PackedInt32Array = PackedInt32Array([AbilityState.DISABLED, AbilityState.DISABLED])
var _remaining_cooldown: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _remaining_duration: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _active_contexts: Array[AbilityContext] = [null, null]
var _input: PlayerInput = null
var _actor: Node2D = null
var _cost_provider: Object = null
var _suppressed: bool = false

func _ready() -> void:
	equip(0, ability_0)
	equip(1, ability_1)

func _physics_process(delta: float) -> void:
	if _input != null and not _suppressed:
		## 技能键是 edge：PlayerInput 只在按下当帧置位，按住不会重复触发。
		if _input.ability_0_just_pressed:
			request_activate(0)
		if _input.ability_1_just_pressed:
			request_activate(1)
	tick(delta)

## ---- 绑定 ----

## 只绑定输入合同，不接管输入设备。
func bind_input(player_input: PlayerInput) -> void:
	_input = player_input

func bind_actor(actor: Node2D) -> void:
	_actor = actor

## 最小 Cost 接口。provider 需实现：
##   can_pay_ability_cost(cost_type: int, value: int) -> bool
##   pay_ability_cost(cost_type: int, value: int) -> bool
## 不绑定 provider 时，任何非零 cost 的技能都不能激活（fail closed）。
func bind_cost_provider(provider: Object) -> void:
	_cost_provider = provider

## Pause / Modal：屏蔽激活。已在冷却 / 持续中的技能不因此重置，只是不能再放。
func set_suppressed(suppressed: bool) -> void:
	_suppressed = suppressed

func is_suppressed() -> bool:
	return _suppressed

## ---- 装备 ----

func equip(index: int, def: AbilityDef) -> void:
	if not _is_valid_slot(index):
		return
	_remove_active_effect(index)
	_defs[index] = def
	_remaining_cooldown[index] = 0.0
	_remaining_duration[index] = 0.0
	_set_state(index, AbilityState.READY if def != null else AbilityState.DISABLED)

func get_def(index: int) -> AbilityDef:
	if not _is_valid_slot(index):
		return null
	return _defs[index]

func get_slot_count() -> int:
	return SLOT_COUNT

## ---- 查询（UI 只读这些，不许自管一份状态）----

func get_state(index: int) -> int:
	if not _is_valid_slot(index):
		return AbilityState.DISABLED
	return _states[index]

func get_remaining_cooldown(index: int) -> float:
	if not _is_valid_slot(index):
		return 0.0
	return _remaining_cooldown[index]

func get_remaining_duration(index: int) -> float:
	if not _is_valid_slot(index):
		return 0.0
	return _remaining_duration[index]

func is_active(index: int) -> bool:
	return get_state(index) == AbilityState.ACTIVE

func can_activate(index: int) -> bool:
	if not _is_valid_slot(index):
		return false
	if _suppressed:
		return false
	var def: AbilityDef = _defs[index]
	if def == null:
		return false
	if _states[index] != AbilityState.READY:
		return false
	if def.has_cost() and not _can_pay_cost(def):
		return false
	return true

## ---- 激活 ----

## 输入 / 本地调用的入口。将来这里改成「向权威端发请求」。
func request_activate(index: int) -> bool:
	return activate_authoritative(index)

## 规范里写的 try_activate(index)。保留这个名字，语义等同 request_activate。
func try_activate(index: int) -> bool:
	return request_activate(index)

## 真正执行。只有权威端应该直接调它（本阶段权威端就是本地）。
func activate_authoritative(index: int) -> bool:
	if not can_activate(index):
		return false
	var def: AbilityDef = _defs[index]
	if def.has_cost() and not _pay_cost(def):
		return false
	var context: AbilityContext = _build_context(index, def)
	if def.effect != null:
		def.effect.apply(context)
	ability_activated.emit(index, def)
	if def.is_instant():
		## instant 没有持续时间，也就没有 remove 回调：context 不再保留。
		_begin_cooldown(index)
		return true
	_active_contexts[index] = context
	_remaining_duration[index] = def.duration
	_set_state(index, AbilityState.ACTIVE)
	return true

## 取消：立刻收尾并回 READY（不给冷却）。用于 clear / 显式打断。
func cancel(index: int) -> void:
	if not _is_valid_slot(index):
		return
	_remove_active_effect(index)
	_remaining_duration[index] = 0.0
	_remaining_cooldown[index] = 0.0
	_set_state(index, AbilityState.READY if _defs[index] != null else AbilityState.DISABLED)

## 清运行时状态：收尾在施放的效果、冷却与持续时间归零。装备不丢。
func clear() -> void:
	for index: int in SLOT_COUNT:
		_remove_active_effect(index)
		_remaining_duration[index] = 0.0
		_remaining_cooldown[index] = 0.0
		_set_state(index, AbilityState.READY if _defs[index] != null else AbilityState.DISABLED)

## 显式禁用 / 恢复一个槽位。
func set_disabled(index: int, disabled: bool) -> void:
	if not _is_valid_slot(index):
		return
	if disabled:
		_remove_active_effect(index)
		_remaining_duration[index] = 0.0
		_set_state(index, AbilityState.DISABLED)
		return
	_set_state(index, AbilityState.READY if _defs[index] != null else AbilityState.DISABLED)

## ---- 时间推进 ----
## 冷却 / 持续时间都由 gameplay runtime 的 delta 驱动，不读 wall clock。

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for index: int in SLOT_COUNT:
		match _states[index]:
			AbilityState.ACTIVE:
				_remaining_duration[index] = maxf(_remaining_duration[index] - delta, 0.0)
				if _remaining_duration[index] <= 0.0:
					_finish_duration(index)
			AbilityState.COOLDOWN:
				_remaining_cooldown[index] = maxf(_remaining_cooldown[index] - delta, 0.0)
				if _remaining_cooldown[index] <= 0.0:
					_remaining_cooldown[index] = 0.0
					_set_state(index, AbilityState.READY)

# ---- 内部 ----

func _finish_duration(index: int) -> void:
	_remove_active_effect(index)
	_remaining_duration[index] = 0.0
	ability_finished.emit(index, _defs[index])
	_begin_cooldown(index)

func _begin_cooldown(index: int) -> void:
	var def: AbilityDef = _defs[index]
	var seconds: float = def.cooldown if def != null else 0.0
	if seconds > 0.0:
		_remaining_cooldown[index] = seconds
		_set_state(index, AbilityState.COOLDOWN)
		return
	_remaining_cooldown[index] = 0.0
	_set_state(index, AbilityState.READY)

func _remove_active_effect(index: int) -> void:
	var context: AbilityContext = _active_contexts[index]
	if context == null:
		return
	_active_contexts[index] = null
	var def: AbilityDef = _defs[index]
	if def != null and def.effect != null:
		def.effect.remove(context)

func _build_context(index: int, def: AbilityDef) -> AbilityContext:
	var context: AbilityContext = AbilityContext.new()
	context.ability = def
	context.slot = index
	context.caster = _actor
	context.origin = _actor.global_position if _actor != null else Vector2.ZERO
	context.direction = _resolve_direction()
	context.target = null
	context.delta = 0.0
	## 复制一份：Effect 永远不许改到共用的 AbilityDef 资源。
	context.parameters = def.parameters.duplicate(true)
	return context

func _resolve_direction() -> Vector2:
	if _input != null and not _input.aim_vector.is_zero_approx():
		return _input.aim_vector.normalized()
	return Vector2.RIGHT

func _can_pay_cost(def: AbilityDef) -> bool:
	if not def.has_cost():
		return true
	if _cost_provider == null:
		return false
	if not _cost_provider.has_method("can_pay_ability_cost"):
		return false
	return bool(_cost_provider.can_pay_ability_cost(int(def.cost_type), def.cost_value))

func _pay_cost(def: AbilityDef) -> bool:
	if not def.has_cost():
		return true
	if _cost_provider == null:
		return false
	if not _cost_provider.has_method("pay_ability_cost"):
		return false
	return bool(_cost_provider.pay_ability_cost(int(def.cost_type), def.cost_value))

func _set_state(index: int, state: int) -> void:
	if _states[index] == state:
		return
	_states[index] = state
	ability_state_changed.emit(index, state)

func _is_valid_slot(index: int) -> bool:
	return index >= 0 and index < SLOT_COUNT
