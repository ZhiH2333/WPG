extends SceneTree

## 测试版提示页回归（网页版的进游戏前必经页）。
##
## 这条页面只在 Web 出现，CI 跑的是桌面版 —— 也就是「平时根本没人跑它」。这个文件用
## `GameSettings.set_web_override()` 把平台判定掰成网页版，在桌面上把整条路走一遍：
##
##   1. 场景能加载、每个 `%UniqueName` 都解得到（导出丢节点 = 整页空白）
##   2. 平台闸门：桌面版不出现，网页版出现，勾过「不再提示」之后不再出现
##   3. 网页版自动勾上 Fullscreen（点「开始游玩」时才真的申请全屏，那需要用户手势）
##   4. Touch Controls = OFF 时 Manual Fire 行必须一起消失
##   5. 200% UI Scale / 540 逻辑宽下内容列不能顶出视口（中文 autowrap 要真的生效）
##   6. 开屏接得上：dev 版 boot_screen 里出现的必须是提示页，点「开始游玩」才换场
##
## 跑法：godot --headless --path . --script res://tests/test_build_notice_test.gd
## 通过输出 TEST_BUILD_NOTICE_OK；失败逐条 TEST_BUILD_NOTICE_FAIL 并返回非 0。

const NOTICE_SCENE := "res://ui/test_build_notice.tscn"
const BOOT_SCENE := "res://ui/boot_screen.tscn"

var _failures: PackedStringArray = PackedStringArray()
var _original_fullscreen: bool = false
var _original_touch_mode: GameSettings.TouchControlsMode = GameSettings.TouchControlsMode.AUTO
var _original_manual_fire: bool = false
var _original_muted: bool = false

func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	await process_frame
	GameSettings.load_from_disk()
	_remember_settings()
	await _case_platform_gate()
	await _case_scene_and_auto_fullscreen()
	await _case_touch_gate()
	await _case_narrow_viewport()
	await _case_boot_screen_handoff()
	_restore_settings()
	_finish()


func _remember_settings() -> void:
	_original_fullscreen = GameSettings.is_fullscreen()
	_original_touch_mode = GameSettings.get_touch_controls_mode()
	_original_manual_fire = GameSettings.is_touch_manual_fire()
	_original_muted = GameSettings.is_test_build_notice_muted()


func _restore_settings() -> void:
	GameSettings.set_web_override(GameSettings.WebOverride.AUTO)
	GameSettings.set_fullscreen(_original_fullscreen)
	GameSettings.set_touch_controls_mode(_original_touch_mode)
	GameSettings.set_touch_manual_fire(_original_manual_fire)
	GameSettings.set_test_build_notice_muted(_original_muted)
	GameSettings.save_to_disk()


## 2) 平台闸门。
func _case_platform_gate() -> void:
	GameSettings.set_test_build_notice_muted(false)
	GameSettings.set_web_override(GameSettings.WebOverride.DESKTOP)
	_expect(not TestBuildNotice.should_show(), "桌面版不出现测试版提示")
	GameSettings.set_web_override(GameSettings.WebOverride.WEB)
	_expect(TestBuildNotice.should_show(), "网页版出现测试版提示")
	GameSettings.set_test_build_notice_muted(true)
	_expect(not TestBuildNotice.should_show(), "勾过「不再提示」之后不再出现")
	GameSettings.set_test_build_notice_muted(false)


## 1) + 3) 场景装配与「网页版自动勾全屏」。
func _case_scene_and_auto_fullscreen() -> void:
	GameSettings.set_web_override(GameSettings.WebOverride.WEB)
	GameSettings.set_fullscreen(false)
	var notice: TestBuildNotice = _open_notice()
	if notice == null:
		return
	for _i: int in 2:
		await process_frame
	var members: Dictionary = {
		"Column": notice._column,
		"FullscreenCheck": notice._fullscreen_check,
		"RenderScaleLabel": notice._render_label,
		"RenderScaleSlider": notice._render_slider,
		"UiScaleLabel": notice._ui_label,
		"UiScaleSlider": notice._ui_slider,
		"TouchOption": notice._touch_option,
		"TouchHint": notice._touch_hint,
		"ManualFireRow": notice._manual_fire_row,
		"ManualFireOption": notice._manual_fire_option,
		"MuteCheck": notice._mute_check,
		"StartButton": notice._start_button,
	}
	for name: String in members:
		_expect(members[name] != null, "TestBuildNotice.%s 不为 null（%UniqueName 解得到）" % name)
	_expect(notice._start_button.text == "开始游玩", "按钮文案是「开始游玩」")
	_expect(notice._mute_check.button_pressed == false, "「不再提示」默认不勾")
	_expect(GameSettings.is_fullscreen(), "网页版自动把 Fullscreen 打开")
	_expect(notice._fullscreen_check.button_pressed, "复选框也跟着勾上")
	_expect(notice.mouse_filter == Control.MOUSE_FILTER_STOP, "整页吃掉鼠标事件")
	notice.queue_free()
	await process_frame

	# 桌面版不许自动开全屏。
	GameSettings.set_web_override(GameSettings.WebOverride.DESKTOP)
	GameSettings.set_fullscreen(false)
	var desktop: TestBuildNotice = _open_notice()
	if desktop != null:
		_expect(not GameSettings.is_fullscreen(), "桌面版不动 Fullscreen")
		_expect(not desktop._fullscreen_check.button_pressed, "桌面版复选框保持关闭")
		desktop.queue_free()
		await process_frame
	GameSettings.set_web_override(GameSettings.WebOverride.WEB)


## 4) Manual Fire 只在 Touch Controls = AUTO / ON 时有意义。
func _case_touch_gate() -> void:
	var notice: TestBuildNotice = _open_notice()
	if notice == null:
		return
	await process_frame
	GameSettings.set_touch_controls_mode(GameSettings.TouchControlsMode.OFF)
	notice._sync_touch_visibility()
	_expect(not notice._manual_fire_row.visible, "Touch OFF -> Manual Fire 行隐藏")
	_expect(not notice._touch_hint.visible, "Touch OFF -> 提示也隐藏")
	notice._touch_option.select(int(GameSettings.TouchControlsMode.AUTO))
	notice._on_touch_controls_selected(int(GameSettings.TouchControlsMode.AUTO))
	_expect(notice._manual_fire_row.visible, "Touch AUTO -> Manual Fire 行显示")
	_expect(GameSettings.get_touch_controls_mode() == GameSettings.TouchControlsMode.AUTO,
		"下拉选 AUTO -> 写进 GameSettings")
	notice.queue_free()
	await process_frame


## 5) 窄视口 / 200% UI Scale：内容列不能被顶出屏幕，长句必须真的换行。
func _case_narrow_viewport() -> void:
	for width: float in [1920.0, 960.0, 540.0]:
		var notice: TestBuildNotice = _open_notice()
		if notice == null:
			continue
		await process_frame
		notice.sync_content_width_for(width)
		await process_frame
		var column_w: float = notice._column.custom_minimum_size.x
		_expect(column_w <= width, "视口 %.0f：内容列（%.0f）不宽于视口" % [width, column_w])
		_expect(notice.get_combined_minimum_size().x <= width + 0.5,
			"视口 %.0f：整页最小宽度 %.0f 不超视口" % [width, notice.get_combined_minimum_size().x])
		# 中文 Label 的 autowrap 必须真的生效：一行放不下就必须多于一行。
		var text_w: float = _lead_width(notice)
		if text_w > column_w + 0.5:
			_expect(notice._lead.get_line_count() > 1,
				"视口 %.0f：正文宽 %.0f > 列宽 %.0f，必须换成多行（实际 %d 行）"
				% [width, text_w, column_w, notice._lead.get_line_count()])
		notice.queue_free()
		await process_frame


func _lead_width(notice: TestBuildNotice) -> float:
	var font: Font = notice._lead.get_theme_font("font")
	var font_size: int = notice._lead.get_theme_font_size("font_size")
	return font.get_string_size(
		notice._lead.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x


## 6) 开屏 → 提示页 → 点「开始游玩」→ 主菜单。
func _case_boot_screen_handoff() -> void:
	GameSettings.set_web_override(GameSettings.WebOverride.WEB)
	var packed: PackedScene = load(BOOT_SCENE) as PackedScene
	_expect(packed != null, "boot_screen.tscn 可加载")
	if packed == null:
		return
	var boot: Control = packed.instantiate() as Control
	root.add_child(boot)
	await process_frame
	var notice: TestBuildNotice = boot.get("_notice") as TestBuildNotice
	_expect(notice != null, "网页版开屏挂上了测试版提示页")
	if notice == null:
		boot.queue_free()
		return
	_expect(not (boot.get("_logo") as TextureRect).visible, "提示页出现时字标已藏掉")
	var started_count: Array[int] = [0]
	notice.started.connect(func() -> void: started_count[0] += 1)
	notice._start_button.emit_signal("pressed")
	await process_frame
	_expect(notice.has_started(), "点「开始游玩」后 has_started = true")
	_expect(started_count[0] == 1, "started 信号只发一次")
	# 头几帧进度条还没走满：直接把开屏的计时顶过去，别在测试里等 0.6s 真实时间。
	boot.set("_elapsed", 10.0)
	boot.set("_ratio", 1.0)
	var frames: int = 0
	while frames < 240 and current_scene == null:
		await process_frame
		frames += 1
	_expect(current_scene != null and current_scene.name == "MainMenu",
		"加载 + 点击之后换到主菜单（%s 帧）" % frames)
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	if is_instance_valid(boot):
		boot.queue_free()
	await process_frame


func _open_notice() -> TestBuildNotice:
	var packed: PackedScene = load(NOTICE_SCENE) as PackedScene
	_expect(packed != null, "%s 可加载" % NOTICE_SCENE)
	if packed == null:
		return null
	var notice: TestBuildNotice = packed.instantiate() as TestBuildNotice
	_expect(notice != null, "%s 根节点挂了 TestBuildNotice 脚本" % NOTICE_SCENE)
	if notice == null:
		return null
	root.add_child(notice)
	return notice


func _finish() -> void:
	if _failures.is_empty():
		print("TEST_BUILD_NOTICE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("TEST_BUILD_NOTICE_FAIL: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
