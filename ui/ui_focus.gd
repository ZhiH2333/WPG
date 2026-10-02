extends Object
class_name UiFocus

## 统一的焦点策略（2026-10-02 定，全界面生效）。
##
## 1) 任何界面打开时都**不再**自动 `grab_focus()`。以前一打开就有一个按钮停在 focus 观感上
##    （骨白下划线 + caption 提亮），看起来就是「永远 hover 着」，鼠标玩家尤其困惑。
## 2) 键盘 / 手柄玩家第一次按导航键（方向键 / Tab / 回车 / 手柄方向键 / 摇杆）时，
##    焦点才交给界面里的首选控件（或第一个可聚焦控件）。所以 Focus 合同不回退：
##    键鼠与手柄仍能走完全部界面，鼠标玩家全程看不到焦点环。
## 3) 确认类弹窗把「安全项」放进 `preferred`（例如删除确认先聚焦「取消」），
##    保留原来的安全默认。
##
## 用法（在界面的 `_input` / `_unhandled_input` 最前面）：
##     if UiFocus.handle_first_pad_input(self, event, [first_control]):
##         get_viewport().set_input_as_handled()
##         return

## 需要建立焦点就返回 true（调用方应吃掉这次事件，避免同一下按又被当成控件输入）。
static func handle_first_pad_input(host: Control, event: InputEvent, preferred: Array = []) -> bool:
	if host == null or not host.is_visible_in_tree():
		return false
	var viewport: Viewport = host.get_viewport()
	if viewport == null:
		return false
	if viewport.gui_get_focus_owner() != null:
		return false
	if not wants_focus(event):
		return false
	var target: Control = pick(preferred)
	if target == null:
		target = first_focusable(host)
	if target == null:
		return false
	target.grab_focus()
	return true

## 只认键盘 / 手柄的导航与确认键：鼠标移动 / 点击不建立焦点。
static func wants_focus(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) > 0.5
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if not key.pressed or key.echo:
			return false
		return key.physical_keycode in [
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE,
		]
	return false

## 从候选里挑第一个真的能聚焦的控件。
static func pick(preferred: Array) -> Control:
	for entry: Variant in preferred:
		var control: Control = entry as Control
		if is_focusable(control):
			return control
	return null

## 界面里第一个可聚焦控件（按节点树顺序，跳过隐藏 / 禁用 / 不接焦点的）。
static func first_focusable(root: Node) -> Control:
	for child: Node in root.get_children():
		if child is Control and is_focusable(child as Control):
			return child as Control
		var found: Control = first_focusable(child)
		if found != null:
			return found
	return null

static func is_focusable(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	var button: BaseButton = control as BaseButton
	if button != null and button.disabled:
		return false
	return true

## 清掉当前焦点（换页 / 关页时用；不会自动把焦点交给别人）。
static func release(host: Control) -> void:
	if host == null or host.get_viewport() == null:
		return
	var owner: Control = host.get_viewport().gui_get_focus_owner()
	if owner != null:
		owner.release_focus()
