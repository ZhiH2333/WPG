extends SceneTree

## 临时探针：真实 RecordSelector + 根视口 push_input 走完整输入链，
## 看存档列表的触控拖动到底滚不滚、事件有没有被别的节点先吃掉。

var _failures: PackedStringArray = PackedStringArray()
var _log: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	GameSettings.load_from_disk()
	var menu: PackedScene = load("res://ui/main_menu.tscn")
	var node = menu.instantiate()
	root.add_child(node)
	for _i in range(8):
		await process_frame
	var rs: RecordSelector = node.get_node("RecordSelector")
	_log.append("root.size=%s content_scale_factor=%s final_tf=%s stretch_tf=%s st=%s vp_tf=%s" % [
		root.size, root.content_scale_factor, root.get_final_transform(), root.get_stretch_transform(),
		root.get_screen_transform(), root.get_texture_transform()])
	rs.open()
	await create_timer(0.7).timeout

	## 造内容溢出：往 Rows 里塞高占位，不动真实存档数据。
	for i in range(12):
		var spacer: Control = Control.new()
		spacer.custom_minimum_size = Vector2(0, 160)
		rs._rows.add_child(spacer)
	await process_frame
	await process_frame

	var scroll: ScrollContainer = rs._scroll
	var max_scroll: float = rs._list_drag.max_scroll()
	_log.append("max_scroll=%.0f rows_children=%d scroll_size=%s rows_size=%s" % [
		max_scroll, rs._rows.get_child_count(), scroll.size, rs._rows.size])
	var rect: Rect2 = rs._list_root.get_global_rect()
	_log.append("list_root_rect=%s" % rect)

	var origin: Vector2 = rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5)
	_touch(origin)
	await process_frame
	_log.append("after press: index=%d (private 访问失败就是没进去)" % _drag_field("_index"))
	_log.append("drag_state=%s" % rs._list_drag.is_dragging())

	## 上拖（手指上移 => content_relative.y 为负 => 内容上滚）
	for step in range(1, 7):
		var pos: Vector2 = origin + Vector2(0, -8.0 * step)
		_drag(pos, Vector2(0, -8.0), 0)
		await process_frame
	_log.append("mid drag: dragging=%s scroll_vertical=%d" % [
		rs._list_drag.is_dragging(), scroll.scroll_vertical])
	for _i in range(12):
		rs._list_drag.step(0.05)
		await process_frame
	_log.append("after steps: scroll_vertical=%d" % scroll.scroll_vertical)

	_release(origin + Vector2(0, -48))
	await process_frame
	_log.append("final: scroll_vertical=%d dragging=%s" % [
		scroll.scroll_vertical, rs._list_drag.is_dragging()])

	for line in _log:
		print("PROBE: ", line)
	if scroll.scroll_vertical <= 0 and max_scroll > 0.0:
		printerr("PROBE_FAIL: 触控拖动没有滚动列表")
		quit(1)
		return
	print("PROBE_OK")
	quit(0)

func _drag_field(name: String) -> String:
	if _drag_private == null:
		return "n/a"
	return str(_drag_private.get(name))

var _drag_private = null

func _touch(position: Vector2) -> void:
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = position
	root.push_input(down)
	_drag_private = _find_drag()

func _drag(position: Vector2, relative: Vector2, index: int) -> void:
	var ev: InputEventScreenDrag = InputEventScreenDrag.new()
	ev.index = index
	ev.position = position
	ev.screen_relative = relative
	ev.relative = relative
	root.push_input(ev)

func _release(position: Vector2) -> void:
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = position
	root.push_input(up)

func _find_drag():
	for child in root.get_children():
		if child is RecordSelector:
			return child.get("_list_drag")
	return null
