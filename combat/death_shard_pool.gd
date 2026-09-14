extends Node2D
class_name DeathShardPool

## 本局死亡碎片池，挂在 CombatSandbox/DeathShards 上。禁止 Autoload，禁止打满时删天上的碎片。
var _capacity: int = 0
var _free: Array[DeathShard] = []

func setup(parent: Node, scene: PackedScene, capacity: int) -> void:
	_capacity = capacity
	_free.clear()
	for _i: int in capacity:
		var shard: DeathShard = scene.instantiate() as DeathShard
		parent.add_child(shard)
		shard.bind_pool(self)
		shard.park()
		_free.append(shard)

func acquire() -> DeathShard:
	if _free.is_empty():
		return null
	return _free.pop_back()

func release(shard: DeathShard) -> void:
	if shard == null:
		return
	if _free.has(shard):
		return
	shard.park()
	if shard.get_parent() != self:
		shard.reparent(self)
	_free.append(shard)

func get_capacity() -> int:
	return _capacity

func get_free_count() -> int:
	return _free.size()

func get_active_count() -> int:
	return _capacity - _free.size()

func park_all() -> void:
	for child: Node in get_children():
		var shard: DeathShard = child as DeathShard
		if shard == null:
			continue
		release(shard)
