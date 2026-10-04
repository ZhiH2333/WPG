extends SceneTree

## HP 时间线 + HP 图回归（结算页的 HP-时间图）。
##
## 锁定：事件式采样（只有 HP 变化才记点）、比例换算、restart 清空、空/单点不画崩。
## 跑法：godot --headless --path . --script res://tests/hp_timeline_test.gd
## 通过输出 HP_TIMELINE_OK；失败逐条 HP_TIMELINE_FAIL 并返回非 0。

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_event_based_sampling()
	_case_ratio_and_clamp()
	_case_restart_clears()
	_case_chart_renders_series()
	if _failures.is_empty():
		print("HP_TIMELINE_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("HP_TIMELINE_FAIL: %s" % failure)
	quit(1)

func _make_session() -> RunSession:
	var session: RunSession = RunSession.new()
	root.add_child(session)
	session.restart()
	return session

## 事件式：同样的 HP 重复喂不产生新点；变了才记。长局不会堆出上千个点。
func _case_event_based_sampling() -> void:
	var session: RunSession = _make_session()
	session.record_hp(100, 100)
	session.tick(1.0)
	session.record_hp(100, 100)
	session.record_hp(100, 100)
	session.tick(1.0)
	session.record_hp(70, 100)
	session.tick(1.0)
	session.record_hp(70, 100)
	session.record_hp(0, 100)
	var points: PackedVector2Array = session.get_hp_timeline()
	_expect(points.size() == 3, "事件式采样应只有 3 个点，实为 %d" % points.size())
	if points.size() == 3:
		_expect(is_equal_approx(points[0].x, 0.0), "第一个点落在 t=0（开局满血）")
		_expect(is_equal_approx(points[1].x, 2.0), "第二个点落在 t=2（第一次掉血）")
		_expect(is_equal_approx(points[2].x, 3.0), "第三个点落在 t=3（第二次掉血）")
	session.queue_free()

## 纵轴是 hp/max_hp，且必须夹在 0..1。
func _case_ratio_and_clamp() -> void:
	var session: RunSession = _make_session()
	session.record_hp(50, 100)
	session.record_hp(25, 50)
	session.record_hp(999, 100)
	session.record_hp(-5, 100)
	var points: PackedVector2Array = session.get_hp_timeline()
	_expect(points.size() == 4, "四次变化四个点，实为 %d" % points.size())
	if points.size() == 4:
		_expect(is_equal_approx(points[0].y, 0.5), "50/100 -> 0.5")
		_expect(is_equal_approx(points[1].y, 0.5), "25/50 -> 0.5")
		_expect(is_equal_approx(points[2].y, 1.0), "超过上限夹到 1.0")
		_expect(is_equal_approx(points[3].y, 0.0), "负血夹到 0.0")
	session.queue_free()

## restart 必须清空，否则上一局的曲线会串到下一局结算。
func _case_restart_clears() -> void:
	var session: RunSession = _make_session()
	session.record_hp(100, 100)
	session.tick(1.0)
	session.record_hp(10, 100)
	_expect(session.get_hp_timeline().size() == 2, "restart 前有两个点")
	session.restart()
	_expect(session.get_hp_timeline().size() == 0, "restart 后时间线必须清空")
	session.record_hp(100, 100)
	_expect(session.get_hp_timeline().size() == 1, "restart 后能重新开始记点")
	session.queue_free()

## HpChart 只读序列：空序列 / 单点不能画崩，多点才算 has_series。
func _case_chart_renders_series() -> void:
	var chart: HpChart = HpChart.new()
	root.add_child(chart)
	chart.size = Vector2(320.0, 120.0)
	chart.set_series(PackedVector2Array(), 0.0)
	_expect(not chart.has_series(), "空序列 has_series = false")
	chart.set_series(PackedVector2Array([Vector2(0.0, 1.0)]), 10.0)
	_expect(not chart.has_series(), "单点不足两个点，has_series = false")
	chart.set_series(PackedVector2Array([Vector2(0.0, 1.0), Vector2(5.0, 0.4)]), 10.0)
	_expect(chart.has_series(), "两点以上 has_series = true")
	_expect(chart.get_point_count() == 2, "点数量正确")
	## 时长为 0（刚开局就死）时不能除零崩掉。
	chart.set_series(PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.0, 0.2)]), 0.0)
	chart.queue_redraw()
	_expect(chart.get_point_count() == 2, "零时长仍能持有序列")
	chart.queue_free()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
