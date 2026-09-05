extends Node2D
class_name ProjectilePool

## 本局弹池，挂在 CombatSandbox/Projectiles 上。禁止 Autoload，禁止打满时删天上的弹。
var _capacity: int = 0
var _free: Array[Projectile] = []

func setup(parent: Node, scene: PackedScene, capacity: int) -> void:
	_capacity = capacity
	_free.clear()
	for _i: int in capacity:
		var projectile: Projectile = scene.instantiate() as Projectile
		parent.add_child(projectile)
		projectile.bind_pool(self)
		projectile.park()
		_free.append(projectile)

func acquire() -> Projectile:
	if _free.is_empty():
		return null
	return _free.pop_back()

func release(projectile: Projectile) -> void:
	if projectile == null:
		return
	if _free.has(projectile):
		return
	projectile.park()
	if projectile.get_parent() != self:
		projectile.reparent(self)
	_free.append(projectile)

func get_capacity() -> int:
	return _capacity

func get_free_count() -> int:
	return _free.size()

func get_active_count() -> int:
	return _capacity - _free.size()
