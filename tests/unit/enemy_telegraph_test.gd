extends SceneTree

## Enemy Telegraph 回归（Phase 2.3.x）。
##
## 锁定：
##   预警数据生命周期 / 远程瞄准与开火方向一致 / 死亡与目标失效清理 /
##   冲锋预警与冲锋方向一致 / 权威端 telegraph 网络字段往返一致 /
##   房间离开与敌人销毁不残留状态。
##
## 跑法：godot --headless --path . --script res://tests/unit/enemy_telegraph_test.gd
## 通过输出 ENEMY_TELEGRAPH_OK。

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const RANGED_SCENE: PackedScene = preload("res://enemies/ranged_enemy.tscn")
const CHARGER_SCENE: PackedScene = preload("res://enemies/charger_enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://enemies/boss_enemy.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://weapons/projectile.tscn")

var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run_all.call_deferred()

func _run_all() -> void:
	_case_telegraph_data_lifecycle()
	await _case_ranged_telegraph_then_fire_direction()
	await _case_ranged_clears_on_death()
	await _case_ranged_cancels_when_target_lost()
	await _case_charger_windup_matches_charge_dir()
	await _case_boss_charge_and_fan_telegraph()
	await _case_net_telegraph_roundtrip_authority()
	await _case_destroy_and_reserve_leave_no_residue()

	if _failures.is_empty():
		print("ENEMY_TELEGRAPH_OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("ENEMY_TELEGRAPH_FAIL: %s" % failure)
	quit(1)

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _case_telegraph_data_lifecycle() -> void:
	var tg: EnemyTelegraph = EnemyTelegraph.new()
	_expect(not tg.is_active(), "fresh telegraph inactive")
	tg.begin_aim_line(0.6, 280.0, true)
	_expect(tg.is_active(), "aim line active after begin")
	_expect(tg.kind == EnemyTelegraph.Kind.AIM_LINE, "kind aim line")
	_expect(is_equal_approx(tg.duration, 0.6), "duration 0.6")
	_expect(is_equal_approx(tg.remaining, 0.6), "remaining starts full")
	_expect(is_equal_approx(tg.progress(), 0.0), "progress starts 0")
	tg.set_direction(Vector2(3, 4))
	_expect(tg.direction.is_equal_approx(Vector2(0.6, 0.8)), "direction normalized")
	var finished_mid: bool = tg.tick(0.3)
	_expect(not finished_mid, "not finished at half")
	_expect(is_equal_approx(tg.progress(), 0.5), "progress half")
	var alpha: float = tg.aim_alpha()
	_expect(alpha > 0.4 and alpha < 1.01, "aim alpha ramps with progress")
	var finished: bool = tg.tick(0.3)
	_expect(finished, "finished after full duration")
	_expect(not tg.is_active(), "inactive when remaining 0")
	tg.clear()
	_expect(tg.kind == EnemyTelegraph.Kind.NONE, "cleared kind")

func _case_ranged_telegraph_then_fire_direction() -> void:
	# preferred 280 ± 70 → 开火带 [210, 350]
	var env: Dictionary = _make_combat_env(Vector2.ZERO, Vector2(280, 0))
	var enemy: RangedEnemy = env["ranged"]
	var player: Player = env["player"]
	var pool: ProjectilePool = env["pool"]
	enemy._next_fire_at_msec = 0
	enemy._tick_fire(0.0)
	_expect(enemy.is_fire_telegraphing(), "ranged enters telegraph")
	_expect(enemy.is_attack_telegraphing(), "ranged attack telegraph active")
	_expect(enemy.get_attack_telegraph().kind == EnemyTelegraph.Kind.AIM_LINE, "ranged aim line kind")
	_expect(enemy.get_attack_telegraph_direction().x > 0.9, "telegraph aims toward player +x")
	player.global_position = Vector2(240, 180)
	enemy.refresh_attack_telegraph_aim()
	var tracked: Vector2 = enemy.get_attack_telegraph_direction()
	_expect(tracked.y > 0.4 and tracked.x > 0.4, "telegraph live-tracks player")
	enemy._pending_fire_dir = tracked
	var steps: int = 0
	while enemy.is_fire_telegraphing() and steps < 40:
		enemy._tick_fire(0.05)
		steps += 1
	_expect(not enemy.is_fire_telegraphing(), "telegraph ends")
	_expect(not enemy.is_attack_telegraphing(), "telegraph cleared after fire")
	_expect(pool.get_active_count() >= 1, "projectile fired")
	var shot: Projectile = _first_active_projectile(pool)
	_expect(shot != null, "active projectile found")
	if shot != null:
		var shot_dir: Vector2 = shot._velocity.normalized()
		_expect(shot_dir.dot(tracked) > 0.99, "fire direction matches last telegraph aim")
	await _free_env(env)

func _case_ranged_clears_on_death() -> void:
	var env: Dictionary = _make_combat_env(Vector2.ZERO, Vector2(280, 0))
	var enemy: RangedEnemy = env["ranged"]
	enemy._next_fire_at_msec = 0
	enemy._tick_fire(0.0)
	_expect(enemy.is_attack_telegraphing(), "telegraph before death")
	enemy.apply_damage(999, enemy.global_position, Vector2.RIGHT)
	_expect(enemy.is_defeated(), "enemy defeated")
	_expect(not enemy.is_attack_telegraphing(), "telegraph cleared on death")
	_expect(not enemy.is_fire_telegraphing(), "fire telegraph cleared on death")
	await _free_env(env)

func _case_ranged_cancels_when_target_lost() -> void:
	var env: Dictionary = _make_combat_env(Vector2.ZERO, Vector2(280, 0))
	var enemy: RangedEnemy = env["ranged"]
	enemy._next_fire_at_msec = 0
	enemy._tick_fire(0.0)
	_expect(enemy.is_attack_telegraphing(), "telegraph before target lost")
	enemy.bind_players([] as Array[Player])
	enemy._tick_fire(0.05)
	_expect(not enemy.is_attack_telegraphing(), "telegraph cancelled when target lost")
	await _free_env(env)

func _case_charger_windup_matches_charge_dir() -> void:
	var env: Dictionary = _make_combat_env(Vector2.ZERO, Vector2(300, 0), false)
	var player: Player = env["player"]
	var enemy: ChargerEnemy = CHARGER_SCENE.instantiate() as ChargerEnemy
	env["world"].add_child(enemy)
	enemy.global_position = Vector2.ZERO
	enemy.bind_players([player] as Array[Player])
	enemy.set_sim_authority(true)
	enemy.reset_for_sandbox(Vector2.ZERO)
	enemy._enter_windup()
	_expect(enemy.is_attack_telegraphing(), "charger windup telegraph")
	_expect(enemy.get_attack_telegraph().kind == EnemyTelegraph.Kind.CHARGE_PATH, "charger path kind")
	player.global_position = Vector2(0, 300)
	enemy._tick_windup(0.01)
	var windup_dir: Vector2 = enemy.get_attack_telegraph_direction()
	_expect(windup_dir.y > 0.9, "charger telegraph tracks before charge")
	var guard: int = 0
	while enemy._charge_state == ChargerEnemy.ChargeState.WINDUP and guard < 80:
		enemy._tick_windup(0.05)
		guard += 1
	_expect(enemy._charge_state == ChargerEnemy.ChargeState.CHARGE, "entered charge")
	_expect(not enemy.is_attack_telegraphing(), "telegraph cleared at charge start")
	_expect(enemy._charge_dir.dot(windup_dir) > 0.99, "charge dir matches telegraph")
	await _free_env(env)

func _case_boss_charge_and_fan_telegraph() -> void:
	var env: Dictionary = _make_combat_env(Vector2.ZERO, Vector2(250, 0), false)
	var player: Player = env["player"]
	var pool: ProjectilePool = env["pool"]
	var enemy: BossEnemy = BOSS_SCENE.instantiate() as BossEnemy
	env["world"].add_child(enemy)
	enemy.global_position = Vector2.ZERO
	enemy.bind_players([player] as Array[Player])
	enemy.set_sim_authority(true)
	enemy.bind_projectile_pool(pool)
	enemy.reset_for_sandbox(Vector2.ZERO)
	enemy._enter_windup_charge()
	_expect(enemy.get_attack_telegraph().kind == EnemyTelegraph.Kind.CHARGE_PATH, "boss charge telegraph")
	var charge_dir: Vector2 = enemy.get_attack_telegraph_direction()
	enemy._enter_charge()
	_expect(enemy._charge_dir.dot(charge_dir) > 0.99, "boss charge uses telegraph dir")
	_expect(not enemy.is_attack_telegraphing(), "boss charge telegraph cleared")
	enemy._enter_windup_volley()
	_expect(enemy.get_attack_telegraph().kind == EnemyTelegraph.Kind.FAN_VOLLEY, "boss fan telegraph")
	_expect(enemy.get_attack_telegraph().fan_count == enemy.volley_count, "fan count matches volley")
	var fan_dir: Vector2 = enemy.get_attack_telegraph_direction()
	enemy._fire_volley()
	_expect(not enemy.is_attack_telegraphing(), "fan telegraph cleared after volley")
	_expect(fan_dir.x > 0.9, "fan aimed at player")
	await _free_env(env)

func _case_net_telegraph_roundtrip_authority() -> void:
	var host_tg: EnemyTelegraph = EnemyTelegraph.new()
	host_tg.begin_aim_line(0.6, 220.0, true, Vector2(10, 0))
	host_tg.set_direction(Vector2(1, 0))
	host_tg.remaining = 0.42
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	host_tg.write_net(buf)
	buf.seek(0)
	var guest_tg: EnemyTelegraph = EnemyTelegraph.new()
	guest_tg.read_net(buf)
	_expect(guest_tg.is_active(), "guest telegraph active")
	_expect(guest_tg.kind == EnemyTelegraph.Kind.AIM_LINE, "guest kind")
	_expect(is_equal_approx(guest_tg.remaining, 0.42), "guest remaining")
	_expect(guest_tg.direction.is_equal_approx(Vector2.RIGHT), "guest direction from host")
	_expect(not guest_tg.track_live, "guest must not live-track locally")
	var env: Dictionary = _make_combat_env(Vector2.ZERO, Vector2(0, 400))
	var enemy: RangedEnemy = env["ranged"]
	enemy.set_sim_authority(false)
	var apply_buf: StreamPeerBuffer = StreamPeerBuffer.new()
	host_tg.write_net(apply_buf)
	apply_buf.seek(0)
	enemy.apply_telegraph_net(apply_buf)
	_expect(enemy.is_attack_telegraphing(), "guest enemy shows host telegraph")
	enemy.refresh_attack_telegraph_aim()
	_expect(enemy.get_attack_telegraph_direction().is_equal_approx(Vector2.RIGHT), "guest keeps host aim, ignores local player")
	await _free_env(env)

func _case_destroy_and_reserve_leave_no_residue() -> void:
	var env: Dictionary = _make_combat_env(Vector2.ZERO, Vector2(280, 0))
	var enemy: RangedEnemy = env["ranged"]
	var world: Node2D = env["world"]
	enemy._next_fire_at_msec = 0
	enemy._tick_fire(0.0)
	_expect(enemy.is_attack_telegraphing(), "active before reserve")
	enemy.hold_in_reserve()
	_expect(not enemy.is_attack_telegraphing(), "cleared in reserve")
	enemy.reset_for_sandbox(Vector2.ZERO)
	enemy._next_fire_at_msec = 0
	enemy._tick_fire(0.0)
	_expect(enemy.is_attack_telegraphing(), "active before free")
	enemy.queue_free()
	await process_frame
	await process_frame
	_expect(not is_instance_valid(enemy), "enemy freed")
	_expect(world.get_child_count() <= 2, "no leftover enemy node under world")
	await _free_env(env)

func _make_combat_env(enemy_pos: Vector2, player_pos: Vector2, with_ranged: bool = true) -> Dictionary:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	player.global_position = player_pos
	var pool: ProjectilePool = ProjectilePool.new()
	world.add_child(pool)
	pool.setup(pool, PROJECTILE_SCENE, 8)
	var ranged: RangedEnemy = null
	if with_ranged:
		ranged = RANGED_SCENE.instantiate() as RangedEnemy
		world.add_child(ranged)
		ranged.global_position = enemy_pos
		ranged.bind_players([player] as Array[Player])
		ranged.set_sim_authority(true)
		ranged.bind_projectile_pool(pool)
		ranged.reset_for_sandbox(enemy_pos)
	return {
		"world": world,
		"player": player,
		"pool": pool,
		"ranged": ranged,
	}

func _free_env(env: Dictionary) -> void:
	var world: Node2D = env["world"]
	if is_instance_valid(world):
		world.queue_free()
	await process_frame

func _first_active_projectile(pool: ProjectilePool) -> Projectile:
	for child: Node in pool.get_children():
		var projectile: Projectile = child as Projectile
		if projectile != null and not projectile.is_parked():
			return projectile
	return null
