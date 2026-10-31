extends SceneTree

## 主菜单「多人」测试提示：点多人先弹提示，继续测试才进 LanOverlay；取消/关闭不进。
##
## 跑法：godot --headless --path . --script res://tests/unit/multiplayer_test_notice_test.gd
## 通过输出 MULTIPLAYER_TEST_NOTICE_OK；失败逐条 MULTIPLAYER_TEST_NOTICE_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	MultiplayerTestNotice.locale_override = ""
	_case_bilingual_copy()
	await _case_click_multi_shows_notice()
	await _case_continue_enters_multiplayer()
	await _case_cancel_keeps_home()
	await _case_layout_unaffected()
	MultiplayerTestNotice.locale_override = ""
	_finish()

## 中英文文案资源（本基线无完整 i18n 包，走 MultiplayerTestNotice 双语常量）。
func _case_bilingual_copy() -> void:
	for locale: String in MultiplayerTestNotice.supported_locales():
		var message: String = MultiplayerTestNotice.message_for_locale(locale)
		var button: String = MultiplayerTestNotice.continue_label_for_locale(locale)
		_expect(not message.strip_edges().is_empty(), "%s 提示文案非空" % locale)
		_expect(not button.strip_edges().is_empty(), "%s 按钮文案非空" % locale)
	_expect(
		MultiplayerTestNotice.message_for_locale("zh_CN") == "多人联机目前不可用！仅可用于测试。",
		"中文提示文案正确"
	)
	_expect(
		MultiplayerTestNotice.continue_label_for_locale("zh_CN") == "继续测试",
		"中文按钮文案正确"
	)
	_expect(
		MultiplayerTestNotice.message_for_locale("en") == "Online multiplayer is currently unavailable! For testing only.",
		"英文提示文案正确"
	)
	_expect(
		MultiplayerTestNotice.continue_label_for_locale("en") == "Continue testing",
		"英文按钮文案正确"
	)

func _case_click_multi_shows_notice() -> void:
	MultiplayerTestNotice.locale_override = "zh_CN"
	var menu: MainMenu = await _open_menu()
	if menu == null:
		return
	_expect(not menu._multi_notice.is_open(), "初始不弹提示")
	_expect(not menu._lan_overlay.is_open(), "初始不在多人界面")
	menu._multi_button.pressed.emit()
	await process_frame
	_expect(menu._multi_notice.is_open(), "点多人后弹出测试提示")
	_expect(not menu._lan_overlay.is_open(), "弹提示时尚未进入多人界面")
	_expect(
		menu._multi_notice._message.text == "多人联机目前不可用！仅可用于测试。",
		"弹层展示中文提示文案"
	)
	_expect(menu._multi_notice._continue_button.text == "继续测试", "弹层展示「继续测试」")
	menu.queue_free()
	await process_frame

func _case_continue_enters_multiplayer() -> void:
	MultiplayerTestNotice.locale_override = "en"
	var menu: MainMenu = await _open_menu()
	if menu == null:
		return
	menu._top_multi_button.pressed.emit()
	await process_frame
	_expect(menu._multi_notice.is_open(), "顶栏多人也会弹提示")
	menu._multi_notice._continue_button.pressed.emit()
	await process_frame
	_expect(not menu._multi_notice.is_open(), "点继续测试后关闭提示")
	_expect(menu._lan_overlay.is_open(), "继续测试后进入多人测试界面")
	_expect(menu._page == MainMenu.PAGE_MULTIPLAYER, "页面状态为 multiplayer")
	menu.queue_free()
	await process_frame

func _case_cancel_keeps_home() -> void:
	var menu: MainMenu = await _open_menu()
	if menu == null:
		return
	menu._multi_button.pressed.emit()
	await process_frame
	_expect(menu._multi_notice.is_open(), "取消用例：提示已打开")
	menu._multi_notice.cancel()
	await process_frame
	_expect(not menu._multi_notice.is_open(), "取消后提示关闭")
	_expect(not menu._lan_overlay.is_open(), "取消后不进入多人界面")
	_expect(menu._page == MainMenu.PAGE_HOME, "取消后仍停在 Home")

	menu._multi_button.pressed.emit()
	await process_frame
	var esc: InputEventKey = InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._multi_notice._input(esc)
	await process_frame
	_expect(not menu._multi_notice.is_open(), "Esc 关闭提示")
	_expect(not menu._lan_overlay.is_open(), "Esc 关闭后不进入多人界面")
	menu.queue_free()
	await process_frame

func _case_layout_unaffected() -> void:
	var menu: MainMenu = await _open_menu()
	if menu == null:
		return
	menu.sync_content_width_for(1920.0)
	await process_frame
	var margin_right: int = menu._home.get_theme_constant("margin_right")
	_expect(margin_right == 672, "提示接入后 1920 宽 margin_right 仍是 672")
	_expect(menu._solo_button.visible, "单人入口仍可见")
	_expect(menu._multi_button.visible, "多人入口仍可见")
	_expect(menu._top_play_button.visible, "顶栏 PLAY 仍可见")
	_expect(menu._top_settings_button.visible, "顶栏 SETTINGS 仍可见")
	_expect(not menu._multi_notice.is_open(), "未点多人时提示不出现")
	menu._solo_button.pressed.emit()
	await process_frame
	_expect(not menu._multi_notice.is_open(), "点单人不弹多人提示")
	_expect(menu._record_selector.is_open() or menu._page == MainMenu.PAGE_RECORDS, "单人仍进档位流程")
	menu.queue_free()
	await process_frame

func _open_menu() -> MainMenu:
	var scene: PackedScene = load("res://ui/main_menu.tscn") as PackedScene
	_expect(scene != null, "main_menu.tscn 可加载")
	if scene == null:
		return null
	var menu: MainMenu = scene.instantiate() as MainMenu
	_expect(menu != null, "根节点是 MainMenu")
	if menu == null:
		return null
	root.add_child(menu)
	for _i: int in 6:
		await process_frame
	_expect(menu._multi_notice != null, "主菜单挂了 MultiplayerTestNotice")
	return menu

func _finish() -> void:
	if _failures.is_empty():
		print("MULTIPLAYER_TEST_NOTICE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("MULTIPLAYER_TEST_NOTICE_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
