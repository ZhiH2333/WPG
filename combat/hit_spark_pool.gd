extends Node2D
class_name HitSparkPool

## 本局命中火花池，挂在 CombatSandbox/HitSparks 上。禁止 Autoload，禁止打满时删天上的火花。
var _capacity: int = 0
var _free: Array[HitSpark] = []

func setup(parent: Node, scene: PackedScene, capacity: int) -> void:
	_capacity = capacity
	_free.clear()
	for _i: int in capacity:
		var spark: HitSpark = scene.instantiate() as HitSpark
		parent.add_child(spark)
		spark.bind_pool(self)
		spark.park()
		_free.append(spark)

func acquire() -> HitSpark:
	if _free.is_empty():
		return null
	return _free.pop_back()

func release(spark: HitSpark) -> void:
	if spark == null:
		return
	if _free.has(spark):
		return
	spark.park()
	if spark.get_parent() != self:
		spark.reparent(self)
	_free.append(spark)

func get_capacity() -> int:
	return _capacity

func get_free_count() -> int:
	return _free.size()

func get_active_count() -> int:
	return _capacity - _free.size()

func park_all() -> void:
	for child: Node in get_children():
		var spark: HitSpark = child as HitSpark
		if spark == null:
			continue
		release(spark)
