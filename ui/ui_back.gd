extends Object
class_name UiBack

## 返回键策略（2026-10-03 定）。
##
## 背景：Android 返回键**不是** Esc。引擎收到返回键（`NOTIFICATION_WM_GO_BACK_REQUEST`）后，
## 会按 `application/config/quit_on_go_back`（默认 true）自己退出应用。但本项目的界面在
## `_unhandled_input` 里对 `ui_cancel` 一律 `set_input_as_handled()`（要拦住 Esc 关叠层、
## 要拦住暂停切换），而 Android 返回键恰好也走 `ui_cancel` 这一路 —— 合成事件在到达引擎的
## 退出分支之前就被吃掉了。所以返回键退不出应用，只能在界面里当 Esc 用。
##
## 判据（已用 `tests/mobile_back_key_test.gd` 钉住）：
##   - 桌面 Esc：真实的 `InputEventKey`，键码 = KEY_ESCAPE。
##   - Android 返回键：引擎合成的 `InputEventAction`，**不是** `InputEventKey`。
## 因此「只认返回键、不认 Esc」= `is_action_pressed("ui_cancel")` 且不是 `InputEventKey`。
##
## 用法：
##   逐层返回（Esc 与返回键都算）：`if UiBack.is_back(event):`
##   最外层退出应用（只认返回键）：`if UiBack.is_root_back(event):`

## 逐层返回上一层：桌面 Esc 与 Android 返回键都算。
static func is_back(event: InputEvent) -> bool:
	if event == null:
		return false
	return event.is_action_pressed("ui_cancel")

## 最外层界面的返回：只认 Android 返回键，不认桌面 Esc。
##
## 这样桌面玩家按 Esc 不会误退出游戏，而 Android 玩家在主菜单根页面按返回键能真正退出。
## 手柄（B / Circle）不在此列：手柄在界面里只关叠层，不该退出应用。
static func is_root_back(event: InputEvent) -> bool:
	if not is_back(event):
		return false
	## Android 返回键合成的是 `InputEventAction`；真实键盘（Esc）是 `InputEventKey`。
	## 这里必须判「不是 InputEventKey」而不是「是 InputEventAction」——手柄 / 宏也可能合成
	## action 事件，用排除法只把真实的键盘按键挡在外面。
	return not (event is InputEventKey)

## 退出请求的计数。测试用它断言「确实请求了退出」而不必真的把进程杀掉
## （headless 下 `SceneTree.quit()` 是延迟生效的，拦不住也观察不到）。
static var quit_requests: int = 0

## 真正退出应用。所有「退出」都走这里，方便测试观察 / 日后加存档钩子。
static func quit_app(host: Node) -> void:
	if host == null:
		return
	var tree: SceneTree = host.get_tree()
	if tree == null:
		return
	quit_requests += 1
	tree.quit()
