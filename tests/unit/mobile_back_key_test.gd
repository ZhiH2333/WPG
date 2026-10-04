extends SceneTree

## 返回键回归：Android 返回键必须逐层返回，并且能在主菜单根页面真正退出应用。
##
## 踩过的坑（这次钉住）：
##   Android 返回键与桌面 Esc 都走 `ui_cancel`，而各叠层对它一律
##   `set_input_as_handled()`。引擎自带的「返回键退出应用」等不到这个事件，
##   于是返回键被当成 Esc 用 —— 退不出应用。判据见 ui/ui_back.gd。
##
## 跑法：godot --headless --path . --script res://tests/mobile_back_key_test.gd --quit
## 通过输出 MOBILE_BACK_KEY_OK；失败逐条 MOBILE_BACK_KEY_FAIL 并返回非 0。

const MENU_SCENE := "res://ui/main_menu.tscn"

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	GameProgress.load_from_disk()
	GameRecords.load_from_disk()

	var scene: PackedScene = load(MENU_SCENE)
	_expect(scene != null, "main_menu.tscn 可加载")
	if scene == null:
		_finish()
		return
	var menu: MainMenu = scene.instantiate() as MainMenu
	root.add_child(menu)
	for _i: int in 6:
		await process_frame

	_case_helper_contract()
	_case_escape_does_not_quit(menu)
	_case_back_closes_settings(menu)

	## 到这里所有「不该退出」的用例都过了。
	if not _failures.is_empty():
		_finish()
		return

	## 最后一按会真的退出应用。`SceneTree.quit()` 是延迟生效的：同帧代码会继续跑完，
	## 但**下一帧不会再调度**（已用探针确认）。所以下面用它当闸门 ——
	## `await process_frame` 若能恢复，就说明那一按根本没退出应用。
	var before: int = UiBack.quit_requests
	_case_root_back_quits_app(menu)
	_expect(UiBack.quit_requests == before + 1, "根页面按 Android 返回键 -> 请求退出应用")
	if not _failures.is_empty():
		_finish()
		return

	print("MOBILE_BACK_KEY_OK")
	await process_frame
	## 闸门：正常情况永远到不了这里（进程已退出）。
	printerr("MOBILE_BACK_KEY_FAIL: 请求了退出但下一帧仍在运行")
	quit(1)

## 判据本身：Esc 只算「返回」，Android 返回键两者都算。
func _case_helper_contract() -> void:
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	_expect(UiBack.is_back(esc), "Esc 算「返回」")
	_expect(not UiBack.is_root_back(esc), "Esc 不算「根页面返回」（不能误退出应用）")

	var back := _android_back_event()
	_expect(UiBack.is_back(back), "Android 返回键算「返回」")
	_expect(UiBack.is_root_back(back), "Android 返回键算「根页面返回」")

	_expect(not UiBack.is_back(null), "null 不算「返回」")
	_expect(not UiBack.is_root_back(null), "null 不算「根页面返回」")

## 桌面 Esc 在根页面不该退出应用（Esc 是键盘玩家的「取消」，不是「退出」）。
func _case_escape_does_not_quit(menu: MainMenu) -> void:
	var before: int = UiBack.quit_requests
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	_send(menu, esc)
	_expect(UiBack.quit_requests == before, "根页面按 Esc 不退出应用")
	_expect(menu._page == MainMenu.PAGE_HOME, "Esc 之后仍停在 Home")

## 叠层开着时，返回键只收叠层，不退出应用。
func _case_back_closes_settings(menu: MainMenu) -> void:
	var overlay: SettingsOverlay = menu._overlay
	overlay.open()
	_expect(overlay.is_open(), "Settings 已打开")

	var before: int = UiBack.quit_requests
	_send(menu, _android_back_event())
	_expect(not overlay.is_open(), "返回键收掉了 Settings 叠层")
	_expect(UiBack.quit_requests == before, "叠层里按返回键不该退出应用")

## 根页面（无叠层）按返回键 -> 真正退出应用。这是本测试的最终断言。
##
## 前置：叠层已由上一条收掉、当前停在 Home，所以主菜单处于「根页面」。
## 返回键必须冒到 `UiBack.quit_app()`；`quit()` 一调，本帧之后就不再调度，
## 因此这里不能 `await`，后续代码也不该被执行（见调用处的守门行）。
func _case_root_back_quits_app(menu: MainMenu) -> void:
	if menu._page != MainMenu.PAGE_HOME or menu._overlay.is_open():
		printerr("MOBILE_BACK_KEY_FAIL: 前置不满足，当前不在根页面")
		quit(1)
		return
	_send(menu, _android_back_event())

## Android 返回键在引擎里合成的是 InputEventAction（不是 InputEventKey）。
func _android_back_event() -> InputEventAction:
	var back := InputEventAction.new()
	back.action = "ui_cancel"
	back.pressed = true
	return back

## 把事件喂给主菜单自己的输入回调。
##
## 不用 `Input.parse_input_event()`：headless 下要靠帧调度才能派发到 `_unhandled_input`，
## 而本测试要断言的是「主菜单这条分支怎么处理返回键」，直接调它的回调最稳、也最贴近语义。
func _send(menu: MainMenu, event: InputEvent) -> void:
	menu._unhandled_input(event)

func _finish() -> void:
	if _failures.is_empty():
		print("MOBILE_BACK_KEY_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("MOBILE_BACK_KEY_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
