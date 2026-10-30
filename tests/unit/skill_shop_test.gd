extends SceneTree

## Pulse / Dash / 商店图标回归。
## 跑法：Godot --headless --path . --script res://tests/unit/skill_shop_test.gd --quit

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/melee_enemy.tscn")
const UPGRADE_CATALOG: UpgradeCatalog = preload("res://data/upgrade_catalog.tres")
const CONSUMABLE_CATALOG: ConsumableCatalog = preload("res://data/consumable_catalog.tres")
const COMPANION_CATALOG: CompanionCatalog = preload("res://data/companion_catalog.tres")
const SHOP_SCENE: PackedScene = preload("res://ui/shop_offer.tscn")

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	PlayerProfile.load_from_disk()
	await _case_pulse_range_once_and_authority()
	await _case_dash_distance_cooldown_and_collision()
	await _case_shop_icons_and_layout()
	if _failures.is_empty():
		print("SKILL_SHOP_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("SKILL_SHOP_FAIL: %s" % failure)
	quit(1)

func _case_pulse_range_once_and_authority() -> void:
	var caster := Node2D.new()
	root.add_child(caster)
	caster.global_position = Vector2(100.0, 100.0)
	var inside: EnemyBase = ENEMY_SCENE.instantiate() as EnemyBase
	var outside: EnemyBase = ENEMY_SCENE.instantiate() as EnemyBase
	root.add_child(inside)
	root.add_child(outside)
	inside.global_position = caster.global_position + Vector2(80.0, 0.0)
	outside.global_position = caster.global_position + Vector2(220.0, 0.0)
	await process_frame

	var effect: AimPulseEffect = load("res://data/abilities/effects/aim_pulse.tres") as AimPulseEffect
	var context := AbilityContext.new()
	context.caster = caster
	context.origin = caster.global_position
	context.direction = Vector2.RIGHT
	context.authoritative = true
	var pulse_targets: Array[EnemyBase] = [inside, outside, inside]
	context.targets = pulse_targets
	var inside_before: int = inside.get_hp()
	var outside_before: int = outside.get_hp()
	effect.apply(context)
	_expect(inside.get_hp() == inside_before - effect.damage, "Pulse 范围内敌人只结算一次")
	_expect(outside.get_hp() == outside_before, "Pulse 范围外敌人不受影响")
	_expect(int(context.scratch.get("hit_count", -1)) == 1, "Pulse 去重后的命中数为 1")
	var pulse: AbilityPulse = context.scratch.get("pulse") as AbilityPulse
	_expect(pulse != null and pulse.global_position.is_equal_approx(caster.global_position), "Pulse 表现以玩家为中心")

	outside.global_position = caster.global_position + Vector2(90.0, 0.0)
	var controller := AbilityController.new()
	root.add_child(controller)
	controller.bind_actor(caster)
	var remote_targets: Array[EnemyBase] = [outside]
	controller.bind_combat_targets(remote_targets)
	controller.set_authoritative(false)
	controller.equip(0, load("res://data/abilities/ability_1.tres") as AbilityDef)
	var remote_before: int = outside.get_hp()
	var fx_before: int = _count_pulses()
	controller.apply_net_state(0, AbilityState.COOLDOWN, 5.0, 0.0)
	_expect(outside.get_hp() == remote_before, "非权威端 Pulse 不重复结算伤害")
	_expect(_count_pulses() == fx_before + 1, "非权威端按权威状态播放一次 Pulse 表现")
	controller.apply_net_state(0, AbilityState.COOLDOWN, 4.9, 0.0)
	_expect(_count_pulses() == fx_before + 1, "重复快照不会重复播放 Pulse")

	controller.queue_free()
	caster.queue_free()
	inside.queue_free()
	outside.queue_free()
	await process_frame

func _case_dash_distance_cooldown_and_collision() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await process_frame
	player.set_physics_process(false)
	var input: PlayerInput = player.get_player_input()
	var dash: PlayerDash = player.get_player_dash()

	player.global_position = Vector2.ZERO
	input.move_vector = Vector2.RIGHT
	input.dash_just_pressed = true
	_expect(dash.try_dash(), "Dash 输入可触发")
	var hp_before: int = player.get_player_health().get_hp()
	player.get_player_health().apply_damage(10, player.global_position, Vector2.LEFT)
	_expect(player.get_player_health().get_hp() == hp_before, "Dash 期间受击保护生效")
	_drive_dash(player, dash)
	var expected_distance: float = _expected_dash_distance()
	_expect(absf(player.global_position.x - expected_distance) < 2.0, "Dash 无障碍位移符合设定距离")
	_expect(absf(player.global_position.y) < 0.1, "Dash 方向与输入一致")

	input.dash_just_pressed = true
	_expect(not dash.try_dash(), "Dash 冷却中不能连续触发")
	dash.tick(PlayerDash.DASH_COOLDOWN_SEC, Vector2.ZERO)
	input.dash_just_pressed = true
	_expect(dash.try_dash(), "Dash 冷却结束后可再次触发")
	dash.reset_for_sandbox()

	var wall := StaticBody2D.new()
	wall.collision_layer = GameCollisionLayers.MASK_WALL
	wall.collision_mask = GameCollisionLayers.MASK_NONE
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10.0, 600.0)
	collision.shape = shape
	wall.add_child(collision)
	wall.global_position = Vector2(130.0, 0.0)
	root.add_child(wall)
	await physics_frame

	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	input.move_vector = Vector2.RIGHT
	input.dash_just_pressed = true
	_expect(dash.try_dash(), "Dash 碰撞用例可触发")
	_drive_dash(player, dash)
	_expect(player.global_position.x > 0.0 and player.global_position.x <= 105.5, "Dash 被墙体阻挡且不会穿墙")

	dash.reset_for_sandbox()
	input.move_vector = Vector2.ZERO
	input.aim_vector = Vector2.UP
	input.dash_just_pressed = true
	_expect(dash.try_dash() and dash.get_direction().is_equal_approx(Vector2.UP), "无移动输入时 Dash 使用瞄准方向")

	player.queue_free()
	wall.queue_free()
	await process_frame

func _drive_dash(player: Player, dash: PlayerDash) -> void:
	var delta: float = _physics_delta()
	var steps: int = 0
	while dash.is_dashing() and steps < 40:
		var velocity: Vector2 = dash.tick(delta, player.velocity)
		player.velocity = velocity
		player.move_and_collide(velocity * delta)
		steps += 1
	_expect(steps < 40, "Dash 在有限时间内结束")

func _physics_delta() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)

func _expected_dash_distance() -> float:
	var delta: float = _physics_delta()
	var steps: int = int(ceil(PlayerDash.DASH_DURATION_SEC / delta))
	return (PlayerDash.DASH_DISTANCE / PlayerDash.DASH_DURATION_SEC) * delta * float(steps)

func _case_shop_icons_and_layout() -> void:
	var cards: Array[ShopCard] = []
	var paths: Dictionary = {}
	var hashes: Dictionary = {}
	for def: UpgradeDef in UPGRADE_CATALOG.get_all():
		_check_icon(def.id, def.icon, paths, hashes)
		cards.append(ShopCard.for_upgrade(def))
	for def: ConsumableDef in CONSUMABLE_CATALOG.get_all():
		_check_icon(def.id, def.icon, paths, hashes)
		cards.append(ShopCard.for_consumable(def))
	for def: CompanionDef in COMPANION_CATALOG.get_all():
		_check_icon(def.id, def.icon, paths, hashes)
		cards.append(ShopCard.for_companion(def))
	_expect(cards.size() == 18, "商店实际目录共有 18 件商品")
	_expect(paths.size() == cards.size(), "每件商品绑定独立图标路径")
	_expect(hashes.size() == cards.size(), "每件商品图标内容互不重复")

	var shop: ShopOffer = SHOP_SCENE.instantiate() as ShopOffer
	root.add_child(shop)
	await process_frame
	shop.present(cards, 9999)
	await process_frame
	_expect(shop._cards.size() == cards.size(), "商店可同时渲染完整商品目录")
	for button: Button in shop._cards:
		var icon: TextureRect = button.get_node_or_null("Content/Icon") as TextureRect
		_expect(icon != null and icon.texture != null, "商店卡片图标加载成功")
		_expect(button.custom_minimum_size.is_equal_approx(ShopOffer.ITEM_CARD_SIZE), "商店卡片保持货架尺寸")
	var h_sep: int = int(shop._grid.get_theme_constant("h_separation"))
	var grid_width: float = ShopOffer.ITEM_CARD_SIZE.x * float(shop._grid.columns) + float(h_sep) * float(maxi(shop._grid.columns - 1, 0))
	## 1120 面板 - FloatingPanel 边距 28*2 - Content 边距 24*2 - Status 280 - Body 间距 24
	var shelf_budget: float = UiFit.SHOP_PANEL_MAX.x - 56.0 - 48.0 - 280.0 - 24.0
	_expect(grid_width <= shelf_budget + 0.5, "三列卡片总宽不超过标准货架预算")
	shop.queue_free()
	await process_frame

func _check_icon(item_id: StringName, icon: Texture2D, paths: Dictionary, hashes: Dictionary) -> void:
	_expect(icon != null, "%s 已绑定图标" % String(item_id))
	if icon == null:
		return
	var path: String = icon.resource_path
	_expect(not path.is_empty() and FileAccess.file_exists(path), "%s 图标资源路径有效" % String(item_id))
	_expect(not paths.has(path), "%s 未与其他商品共用图标路径" % String(item_id))
	paths[path] = true
	var content_hash: String = FileAccess.get_md5(path)
	_expect(not content_hash.is_empty() and not hashes.has(content_hash), "%s 图标内容不是重复文件" % String(item_id))
	hashes[content_hash] = true
	var image: Image = icon.get_image()
	_expect(image != null and image.get_width() == 256 and image.get_height() == 256, "%s 图标为 256×256" % String(item_id))
	if image != null:
		_expect(image.get_pixel(0, 0).a < 0.05, "%s 图标背景透明" % String(item_id))

func _count_pulses() -> int:
	var count: int = 0
	for child: Node in root.get_children():
		if child is AbilityPulse:
			count += 1
	return count

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
