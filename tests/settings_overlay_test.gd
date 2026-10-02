extends SceneTree

## 设置抽屉回归：主菜单里的 SettingsOverlay 必须能真正打开。
##
## 踩过的两个坑，这里各钉一条：
##   1. 场景里 `%UniqueName` 解析不到 -> `_ready()` 在 `_msaa_option.clear()` 当场中断，
##      `open()` 再撞 null，网页版/导出版设置菜单整个点不开（见 tests/scene_pack_loss_test.gd）。
##   2. 桌面版 Quit 必须还在；网页版藏掉 Quit 是 `_quit_hidden_by_platform()` 的事，
##      别把桌面一起藏了。
##
## 跑法：godot --headless --path . --script res://tests/settings_overlay_test.gd --quit
## 通过输出 SETTINGS_OVERLAY_OK；失败逐条 SETTINGS_OVERLAY_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	var scene: PackedScene = load("res://ui/main_menu.tscn")
	_expect(scene != null, "main_menu.tscn 可加载")
	if scene == null:
		_finish()
		return
	var menu: MainMenu = scene.instantiate() as MainMenu
	root.add_child(menu)
	for _i: int in 6:
		await process_frame

	var overlay: SettingsOverlay = menu._overlay
	_expect(overlay != null, "主菜单挂了 SettingsOverlay")
	if overlay == null:
		menu.queue_free()
		_finish()
		return

	_case_unique_names_resolve(overlay)
	_case_open_and_close(overlay)
	_case_quit_button_visibility(menu)

	overlay.close()
	menu.queue_free()
	await process_frame
	_finish()

## 每一个 `%Name` 都必须解析出来：null 就说明 `_ready()` 有节点没拿到（导出丢节点 / 改名）。
func _case_unique_names_resolve(overlay: SettingsOverlay) -> void:
	var members: Dictionary = {
		"Dimmer": overlay._dimmer,
		"Drawer": overlay._drawer,
		"Sidebar": overlay._sidebar,
		"Panel": overlay._panel,
		"Content": overlay._content,
		"Search": overlay._search,
		"AudioButton": overlay._audio_nav,
		"DisplayButton": overlay._display_nav,
		"ControlsButton": overlay._controls_nav,
		"DataButton": overlay._data_nav,
		"AudioSection": overlay._audio_section,
		"DisplaySection": overlay._display_section,
		"ControlsSection": overlay._controls_section,
		"DataSection": overlay._data_section,
		"VolumeSlider": overlay._volume_slider,
		"MusicSlider": overlay._music_slider,
		"SfxSlider": overlay._sfx_slider,
		"FullscreenCheck": overlay._fullscreen_check,
		"RenderScaleLabel": overlay._render_scale_label,
		"RenderScaleSlider": overlay._render_scale_slider,
		"UiScaleLabel": overlay._ui_scale_label,
		"UiScaleSlider": overlay._ui_scale_slider,
		"VsyncCheck": overlay._vsync_check,
		"MsaaOption": overlay._msaa_option,
		"DeleteButton": overlay._delete_button,
		"StatusLabel": overlay._status_label,
		"CreditsButton": overlay._credits_button,
		"VersionLabel": overlay._version_label,
	}
	for name: String in members:
		_expect(members[name] != null, "SettingsOverlay.%s 不为 null（%UniqueName 解得到）" % name)

## open() / close() 走一遍：以前 open() 会撞 null 控件，抽屉根本不出现。
func _case_open_and_close(overlay: SettingsOverlay) -> void:
	_expect(not overlay.is_open(), "初始是关的")
	_expect(not overlay.visible, "初始不可见")
	overlay.open()
	_expect(overlay.is_open(), "open() 后 is_open = true")
	_expect(overlay.visible, "open() 后 visible = true")
	_expect(overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "open() 后吃鼠标事件")
	overlay.close()
	_expect(not overlay.is_open(), "close() 后 is_open = false")

## 桌面版 Quit 按钮必须还在且可点；网页版才藏（用 OS.has_feature("web") 判定）。
func _case_quit_button_visibility(menu: MainMenu) -> void:
	var expected_visible: bool = not OS.has_feature("web")
	_expect(menu._quit_button.visible == expected_visible,
		"Quit 可见性 = %s（web 应藏，桌面应留；实际 %s）" % [expected_visible, menu._quit_button.visible])

func _finish() -> void:
	if _failures.is_empty():
		print("SETTINGS_OVERLAY_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SETTINGS_OVERLAY_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
