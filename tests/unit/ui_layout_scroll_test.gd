extends SceneTree

## 响应式 + 触屏滚动回归（手机 200%：横向 1140x540 / 960x2027）。
##
## 锁四件事：
##   1. RECORDS 列表全宽：Sheet/Column 左右只留 48，不再写死 -672（1920 设计稿）。
##   2. New Record 在 Header 右上角；建档态收起来。
##   3. 建档表单与多人建房页的内容最小宽度必须 <= 可用宽度（否则整块横向溢出被裁）。
##   4. DragScroll：越过 TOUCH_SLOP 才滚、tap 不滚；ScrollContainer 自带拖动在
##      emulate_mouse_from_touch 下失效，所以这条必须由自己接管。
##
## 跑法：godot --headless --path . --script res://tests/ui_layout_scroll_test.gd --quit
## 通过输出 UI_LAYOUT_OK；失败逐条 UI_LAYOUT_FAIL 并返回非 0。

const MARGIN: float = 48.0
const PHONE_W: float = 1140.0
const NARROW_W: float = 960.0
const PORTRAIT_W: float = 540.0

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()

	_case_drag_scroll_helper()
	await _case_records_layout()
	await _case_lan_host_fits()
	await _case_shop_has_drag()

	_finish()

# ---- 1) DragScroll 本体 ----

## 造一个高内容 ScrollContainer，直接喂触摸事件验证手势语义。
func _case_drag_scroll_helper() -> void:
	var host: Control = Control.new()
	host.size = Vector2(400, 200)
	root.add_child(host)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size = Vector2(400, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	var content: Control = Control.new()
	content.custom_minimum_size = Vector2(380, 1200)
	scroll.add_child(content)
	await process_frame

	var drag: DragScroll = DragScroll.attach(scroll, host)
	_expect(drag.max_scroll() > 100.0, "装了高内容后 max_scroll > 100（实际 %.0f）" % drag.max_scroll())

	## 下拖：已经在顶部，内容不应出现负位移
	_press(drag, Vector2(200, 100), 0)
	_drag(drag, Vector2(200, 40), Vector2(0, -60), 0)
	_expect(drag.is_dragging(), "位移 60px > slop 后进入拖动")
	_expect(scroll.scroll_vertical == 0, "已经在顶部时继续下拖不会变成负值")
	_release(drag, Vector2(200, 40), 0)

	## 上拖：内容上滚
	_press(drag, Vector2(200, 100), 1)
	_drag(drag, Vector2(200, 40), Vector2(0, -60), 1)
	_expect(drag.handle_event(_drag_event(Vector2(200, 20), Vector2(0, -20), 1)), "拖动中持续被本层消费")
	for _i: int in 8:
		drag.step(0.05)
	_expect(scroll.scroll_vertical > 0, "上拖 60px 后确实滚下去了（实际 %d）" % scroll.scroll_vertical)
	_release(drag, Vector2(200, 20), 1)
	_expect(not drag.is_dragging(), "抬手后结束拖动")

	## 小位移算 tap：不进入拖动、不吞事件
	_press(drag, Vector2(200, 100), 2)
	var before: int = scroll.scroll_vertical
	_drag(drag, Vector2(200, 104), Vector2(0, 4), 2)
	_expect(not drag.is_dragging(), "4px < slop 不算拖动（tap 交给按钮）")
	_expect(scroll.scroll_vertical == before, "tap 不改变滚动位置")
	_release(drag, Vector2(200, 104), 2)

	host.queue_free()
	await process_frame

func _press(drag: DragScroll, position: Vector2, index: int) -> void:
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = index
	down.pressed = true
	down.position = position
	drag.handle_event(down)

func _drag_event(position: Vector2, screen_relative: Vector2, index: int) -> InputEventScreenDrag:
	var move: InputEventScreenDrag = InputEventScreenDrag.new()
	move.index = index
	move.position = position
	move.screen_relative = screen_relative
	return move

func _drag(drag: DragScroll, position: Vector2, screen_relative: Vector2, index: int) -> void:
	drag.handle_event(_drag_event(position, screen_relative, index))

func _release(drag: DragScroll, position: Vector2, index: int) -> void:
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = index
	up.pressed = false
	up.position = position
	drag.handle_event(up)

# ---- 2) RECORDS ----

func _case_records_layout() -> void:
	var menu: MainMenu = await _menu()
	if menu == null:
		return
	var rs: RecordSelector = menu._record_selector
	rs.open()
	await create_timer(0.6).timeout

	rs.sync_content_width_for(PHONE_W)
	await process_frame
	_expect(is_equal_approx(rs._column.offset_left, MARGIN), "列表左缩进 = 48")
	_expect(is_equal_approx(rs._column.offset_right, -MARGIN), "列表右缩进 = -48（全宽，不是旧 -672）")
	var list_w: float = PHONE_W - MARGIN * 2.0
	_expect(list_w - MARGIN * 2.0 > 0.0, "列表版心为正")

	_expect(rs._new_button.visible, "LIST 态右上角有 + New Record")
	_expect(rs._new_button.get_parent() == rs.get_node("Sheet/Column/Header"), "New Record 挂在 Header 里")

	rs.sync_content_width_for(PHONE_W)
	rs._enter_editor()
	await create_timer(0.4).timeout
	_expect(not rs._new_button.visible, "建档态收起 + New Record")
	## _enter_editor() 会按当前真实视口重算一次（叠层 _ready 早于 UI Scale 应用），
	## 所以这里跟真实视口对齐，而不是强行 1140。
	var want: float = UiFit.content_width_for(rs._logical_viewport_width(), MARGIN, 1200.0)
	_expect(is_equal_approx(rs._editor_column.custom_minimum_size.x, want),
		"建档表单宽度 = 版心 %.0f（实际 %.0f）" % [want, rs._editor_column.custom_minimum_size.x])
	## 表单内容的最小宽度不能超过给它算出来的宽度，否则整块横向溢出被裁。
	var editor_min: float = rs._editor_column.get_combined_minimum_size().x
	_expect(editor_min <= want + 0.5, "建档表单最小宽度 %.0f <= 版心 %.0f" % [editor_min, want])
	_expect(rs._editor_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"建档表单可纵向滚动")
	_expect(rs._list_drag != null and rs._editor_drag != null, "列表与表单都挂了 DragScroll")

	rs.sync_content_width_for(PORTRAIT_W)
	await process_frame
	var narrow_want: float = UiFit.content_width_for(PORTRAIT_W, MARGIN, 1200.0)
	_expect(rs._editor_column.custom_minimum_size.x <= narrow_want + 0.5,
		"540 逻辑宽下表单宽度跟着收（实际 %.0f）" % rs._editor_column.custom_minimum_size.x)
	rs.close()
	menu.queue_free()
	await process_frame

# ---- 3) 多人建房页 ----

func _case_lan_host_fits() -> void:
	var menu: MainMenu = await _menu()
	if menu == null:
		return
	menu._enter_multi_flow()
	await create_timer(0.5).timeout
	var lo: LanOverlay = menu._lan_overlay
	lo.open()
	await create_timer(0.9).timeout
	lo._enter_host()
	await create_timer(0.6).timeout

	## 多人首页：ScrollContainer 里的 Column 必须被拉伸到可用宽度。
	## 这一条是踩过的坑：Column 只有 anchors、没有 SIZE_EXPAND 时会被排成 0 宽 ——
	## 行照样画得出来（文字溢出），但没有任何可点区域，整个页面点不动。
	var home_col: Control = lo.get_node("Sheet/Column/Content/HomeRoot/Scroll/Column") as Control
	_expect(home_col != null and home_col.size.x > 200.0,
		"多人首页 Column 被拉伸到可用宽度（实际 %.0f，0 就是点不动的那个 bug）" % (home_col.size.x if home_col else -1.0))
	if lo._row_create != null:
		var row_rect: Rect2 = lo._row_create.get_global_rect()
		_expect(row_rect.size.x > 200.0,
			"CREATE ROOM 行有可点宽度（实际 %.0f）" % row_rect.size.x)

	var body: Control = lo.get_node("Sheet/Column/Content/HostRoot/Scroll/Body") as Control
	_expect(body != null, "建房页 Body 在 Scroll 里")
	_expect(body != null and body.size.x > 200.0, "建房页 Body 被拉伸到可用宽度")
	var avail: float = PHONE_W - MARGIN * 2.0
	var body_min: float = body.get_combined_minimum_size().x
	_expect(body_min <= avail,
		"建房页两列最小宽度 %.0f <= 可用 %.0f（否则横向溢出被裁）" % [body_min, avail])
	_expect(lo._host_drag != null, "建房页挂了 DragScroll")
	var scroll: ScrollContainer = lo.get_node("Sheet/Column/Content/HostRoot/Scroll") as ScrollContainer
	_expect(scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "建房页可纵向滚动")

	lo.close()
	menu.queue_free()
	await process_frame

# ---- 4) 商店货架 ----

func _case_shop_has_drag() -> void:
	var scene: PackedScene = load("res://ui/shop_offer.tscn")
	_expect(scene != null, "shop_offer.tscn 可加载")
	if scene == null:
		return
	var shop: ShopOffer = scene.instantiate() as ShopOffer
	root.add_child(shop)
	await process_frame
	await process_frame
	_expect(shop._shelf_drag != null, "商店货架挂了 DragScroll")
	shop.queue_free()
	await process_frame

# ---- 工具 ----

func _menu() -> MainMenu:
	var scene: PackedScene = load("res://ui/main_menu.tscn")
	_expect(scene != null, "main_menu.tscn 可加载")
	if scene == null:
		return null
	var menu: MainMenu = scene.instantiate() as MainMenu
	root.add_child(menu)
	for _i: int in 6:
		await process_frame
	return menu

func _finish() -> void:
	if _failures.is_empty():
		print("UI_LAYOUT_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("UI_LAYOUT_FAIL: %s" % failure)
	quit(1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
