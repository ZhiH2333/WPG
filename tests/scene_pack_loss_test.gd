extends SceneTree

## 导出丢节点回归（godotengine/godot#123208）。
##
## `PackedScene.pack()` 会静默丢掉「放在**非 editable** 实例内部、比实例根更深」的外来节点。
## 导出（把 .tscn 转成二进制 .scn）走的就是 pack()，所以这些节点在正式包里直接消失：
## 编辑器里一切正常，导出后 `%UniqueName` 全部 "Node not found"，脚本 `_ready()` 当场中断。
## 本仓踩过一次：`ui/settings_overlay.tscn` 的四个 settings_section 实例，
## 害得网页版/导出版设置抽屉整个打不开。
##
## 这里不导出，只在本地复刻同一条路径：instantiate() -> PackedScene.pack() ->
## 对比打包前后节点路径集合。少一个节点就是 FAIL。
## 修法二选一：给实例加 `[editable path="..."]`，或者别把节点塞进实例内部。
##
## 跑法：godot --headless --path . --script res://tests/scene_pack_loss_test.gd --quit
## 通过输出 SCENE_PACK_OK；失败逐条 SCENE_PACK_FAIL 并返回非 0。

## 确认必须跳过的场景（目前一个都没有）。带 .tscn 的临时探针不要放进来，直接删。
const SKIP: Array[String] = []

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all()

func _run_all() -> void:
	var scenes: PackedStringArray = _all_scenes("res://")
	scenes.sort()
	var scanned: int = 0
	for path: String in scenes:
		if path in SKIP:
			continue
		scanned += 1
		var lost: PackedStringArray = _lost_nodes(path)
		if lost.is_empty():
			continue
		_expect(false, "%s 打包会丢 %d 个节点（导出后这些节点不存在）：%s" % [
			path, lost.size(), ", ".join(lost.slice(0, mini(lost.size(), 6))),
		])
	_expect(scanned > 0, "至少扫到一个 .tscn（实际 %d）" % scanned)

	if _failures.is_empty():
		## 成功标记必须独占一行、以 _OK 结尾（tools/ci/smoke.py 据此判定），细节另起一行。
		print("SCENE_PACK_OK")
		print("  扫了 %d 个 .tscn，零导出丢节点风险" % scanned)
		quit(0)
		return
	for failure: String in _failures:
		printerr("SCENE_PACK_FAIL: %s" % failure)
	quit(1)

func _all_scenes(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(".tscn"):
			out.append(root.path_join(f))
	for d: String in dir.get_directories():
		## 点目录是导入缓存，不碰。
		if d.begins_with("."):
			continue
		out.append_array(_all_scenes(root.path_join(d)))
	return out

## 返回「实例化后存在、pack() 之后消失」的节点路径。
func _lost_nodes(path: String) -> PackedStringArray:
	var scene: PackedScene = load(path)
	if scene == null:
		return PackedStringArray()
	var instance: Node = scene.instantiate()
	if instance == null:
		return PackedStringArray()
	var packed: PackedScene = PackedScene.new()
	if packed.pack(instance) != OK:
		instance.free()
		return PackedStringArray()
	var repacked: Node = packed.instantiate()
	var after: Dictionary = {}
	for p: String in _paths(repacked):
		after[p] = true
	var lost: PackedStringArray = PackedStringArray()
	for p: String in _paths(instance):
		if not after.has(p):
			lost.append(p)
	instance.free()
	repacked.free()
	return lost

func _paths(node: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_collect(node, node, out)
	return out

func _collect(node: Node, root_node: Node, out: PackedStringArray) -> void:
	if node != root_node:
		out.append(String(root_node.get_path_to(node)))
	for child: Node in node.get_children():
		_collect(child, root_node, out)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
