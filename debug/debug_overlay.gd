extends CanvasLayer
class_name DebugOverlay

const FPS_WINDOW_SEC: float = 2.0
const FPS_SLOT_COUNT: int = 20
const AI_STAGGER_LABEL: String = "off"

var _player: Player
var _player_input: PlayerInput
var _player_camera: PlayerCamera
var _weapon_host: WeaponHost
var _pool: ProjectilePool
var _enemy_pool: ProjectilePool
var _spark_pool: HitSparkPool
var _shard_pool: DeathShardPool
var _enemies: Array[EnemyBase] = []
var _encounter: EncounterPhrases
var _run_session: RunSession
var _upgrade_offer: UpgradeOffer
var _winner_page: WinnerPage
var _last_grant_id: String = "-"
var _record_id: String = ""
var _net_session: NetSession
var _p2: Player
var _fps_slot_min: PackedFloat32Array = PackedFloat32Array()
var _fps_slot_sum: PackedFloat32Array = PackedFloat32Array()
var _fps_slot_count: PackedInt32Array = PackedInt32Array()
var _fps_slot_index: int = 0
var _fps_slot_elapsed: float = 0.0
var _fps_min_2s: float = 0.0
var _fps_avg_2s: float = 0.0

@onready var _label: Label = $Label

func _ready() -> void:
	visible = false
	_fps_slot_min.resize(FPS_SLOT_COUNT)
	_fps_slot_sum.resize(FPS_SLOT_COUNT)
	_fps_slot_count.resize(FPS_SLOT_COUNT)
	_reset_fps_slots()

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode != KEY_F9:
		return
	visible = not visible
	get_viewport().set_input_as_handled()

func bind_player(player: Player) -> void:
	_player = player
	bind_player_input(player.get_player_input())

func bind_player_input(player_input: PlayerInput) -> void:
	_player_input = player_input

func bind_player_camera(player_camera: PlayerCamera) -> void:
	_player_camera = player_camera

func bind_weapon_host(weapon_host: WeaponHost) -> void:
	_weapon_host = weapon_host

func bind_projectile_pool(pool: ProjectilePool) -> void:
	_pool = pool

func bind_enemy_projectile_pool(pool: ProjectilePool) -> void:
	_enemy_pool = pool

func bind_hit_spark_pool(pool: HitSparkPool) -> void:
	_spark_pool = pool

func bind_death_shard_pool(pool: DeathShardPool) -> void:
	_shard_pool = pool

func bind_enemies(enemies: Array[EnemyBase]) -> void:
	_enemies = enemies

func bind_encounter(encounter: EncounterPhrases) -> void:
	_encounter = encounter

func bind_run_session(run_session: RunSession) -> void:
	_run_session = run_session

func bind_upgrade_offer(offer: UpgradeOffer) -> void:
	_upgrade_offer = offer

func bind_winner_page(page: WinnerPage) -> void:
	_winner_page = page

func bind_record_id(record_id: String) -> void:
	_record_id = record_id

func bind_net_session(session: NetSession) -> void:
	_net_session = session

func bind_p2(player: Player) -> void:
	_p2 = player

func set_last_grant_id(upgrade_id: String) -> void:
	_last_grant_id = upgrade_id

func get_fps_min_2s() -> float:
	return _fps_min_2s

func get_fps_avg_2s() -> float:
	return _fps_avg_2s

func _process(delta: float) -> void:
	_tick_fps_window(delta)
	if not visible:
		return
	_refresh_label()

func _refresh_label() -> void:
	if _player_input == null:
		_label.text = "PlayerInput 未绑定"
		return
	_label.text = _compose_status_text()

func _compose_status_text() -> String:
	var fps: int = Engine.get_frames_per_second()
	var velocity: Vector2 = _read_velocity()
	var weapon: Weapon = _read_weapon()
	return "weapon: %s\nmove_vector: %s\naim_vector: %s\nfire_held: %s\ndevice: %s\nfire_cd: %.3f\nspread_deg: %.2f\npellets: %d\nmouse_world: %s\nvelocity: %s\nspeed: %.1f\nlook_target: %s\ncamera_offset: %s\ncamera_pos: %s\nplayer_hp: %d\nplayer_dead: %s\nactive_bullets: %d\npool_free: %d\nenemy_active: %d\nenemy_free: %d\nspark_active: %d\nspark_free: %d\nshard_active: %d\nshard_free: %d\nlast_shot_refused: %d\nenemies_alive: %s\nenemies_dead: %d\nnearest: %s\nnearest_spd: %.1f\nnearest_dmg: %d\nhitstop_ms: %.1f\nknockback_speed: %.1f\nshake_offset: %s\nshake_speed: %.1f\nai_stagger: %s\nrun: %s\nrun_time: %.2f\nloop: %d\nkills: %d\ngold: %d\nlevel: %d\nxp: %d/%d\npending_lv: %d\ncatalog: %d\nupgrades: %d\ngrant: U\ngod: %s\ndash: %s\nlast_grant: %s\noffer: %s\noffer_ids: %s\nphrase: %s\nphrase_alive: %d\nrest_left: %.2f\nrest_sec: %.2f\nrecord: %s hist: %d best: %d goal: %d\nchar: %s\nscore: %d\nwinner: %s\nnet: %s\npeer: %d\nseat: %d\np2_hp: %s\nreset: R\nesc: pause\nfps: %d\nfps_min_2s: %.1f\nfps_avg_2s: %.1f" % [
		_read_weapon_name(weapon),
		_format_vector(_player_input.move_vector),
		_format_vector(_player_input.aim_vector),
		_player_input.fire_held,
		_read_device_label(),
		_read_fire_cooldown(weapon),
		_read_spread(weapon),
		_read_pellets(weapon),
		_format_vector(_player_input.mouse_world_position),
		_format_vector(velocity),
		velocity.length(),
		_format_vector(_read_look_target()),
		_format_vector(_read_camera_offset()),
		_format_vector(_read_camera_position()),
		_read_player_hp(),
		_player != null and _player.is_defeated(),
		_read_active_bullets(),
		_read_pool_free(),
		_read_enemy_active(),
		_read_enemy_free(),
		_read_spark_active(),
		_read_spark_free(),
		_read_shard_active(),
		_read_shard_free(),
		_read_refused(weapon),
		_format_alive_summary(),
		_count_dead_enemies(),
		_format_nearest(),
		_read_nearest_speed(),
		_read_nearest_damage(),
		_read_hitstop_ms(),
		_read_knockback_speed(),
		_format_vector(_read_shake_offset()),
		_read_shake_speed(),
		AI_STAGGER_LABEL,
		_read_run_label(),
		_read_run_time(),
		_read_loop_index(),
		_read_kill_count(),
		_read_gold(),
		_read_level(),
		_read_xp(),
		_read_xp_to_next(),
		_read_pending_level(),
		_read_catalog_count(),
		_read_owned_upgrades(),
		_read_god_label(),
		_read_dash_label(),
		_last_grant_id,
		_read_offer_state(),
		_read_offer_ids(),
		_read_phrase_label(),
		_read_phrase_alive(),
		_read_rest_left(),
		_read_rest_sec(),
		_read_record_id_tail(),
		_read_record_history_count(),
		_read_record_best_score(),
		_read_record_loop_goal(),
		_read_character_id(),
		_read_score(),
		_read_winner_label(),
		_read_net_label(),
		_read_peer_id(),
		_read_seat(),
		_read_p2_hp(),
		fps,
		_fps_min_2s,
		_fps_avg_2s,
	]

func _read_weapon() -> Weapon:
	if _weapon_host == null:
		return null
	return _weapon_host.get_current_weapon()

func _read_weapon_name(weapon: Weapon) -> String:
	if weapon == null:
		return "-"
	return weapon.get_display_name()

func _read_device_label() -> String:
	if _player_input == null:
		return "kbm"
	var id: int = _player_input.get_device_id()
	if id < 0:
		return "kbm"
	return "pad%d" % id

func _read_velocity() -> Vector2:
	if _player == null:
		return Vector2.ZERO
	return _player.velocity

func _read_look_target() -> Vector2:
	if _player_camera == null:
		return Vector2.ZERO
	return _player_camera.get_look_target()

func _read_camera_offset() -> Vector2:
	if _player_camera == null:
		return Vector2.ZERO
	return _player_camera.get_camera_offset()

func _read_camera_position() -> Vector2:
	if _player_camera == null:
		return Vector2.ZERO
	return _player_camera.global_position

func _read_fire_cooldown(weapon: Weapon) -> float:
	if weapon == null:
		return 0.0
	return weapon.get_cooldown_remaining_sec()

func _read_spread(weapon: Weapon) -> float:
	if weapon == null:
		return 0.0
	return weapon.get_current_spread_deg()

func _read_pellets(weapon: Weapon) -> int:
	if weapon == null:
		return 0
	return weapon.get_pellets_per_shot()

func _read_active_bullets() -> int:
	if _pool == null:
		return 0
	return _pool.get_active_count()

func _read_pool_free() -> int:
	if _pool == null:
		return 0
	return _pool.get_free_count()

func _read_enemy_active() -> int:
	if _enemy_pool == null:
		return 0
	return _enemy_pool.get_active_count()

func _read_enemy_free() -> int:
	if _enemy_pool == null:
		return 0
	return _enemy_pool.get_free_count()

func _read_spark_active() -> int:
	if _spark_pool == null:
		return 0
	return _spark_pool.get_active_count()

func _read_spark_free() -> int:
	if _spark_pool == null:
		return 0
	return _spark_pool.get_free_count()

func _read_shard_active() -> int:
	if _shard_pool == null:
		return 0
	return _shard_pool.get_active_count()

func _read_shard_free() -> int:
	if _shard_pool == null:
		return 0
	return _shard_pool.get_free_count()

func _read_refused(weapon: Weapon) -> int:
	if weapon == null:
		return 0
	return weapon.get_refused_count()

func _read_player_hp() -> int:
	if _player == null:
		return 0
	return _player.get_player_health().get_hp()

func _read_run_label() -> String:
	if _run_session == null:
		return "-"
	return _run_session.get_outcome_label()

func _read_run_time() -> float:
	if _run_session == null:
		return 0.0
	return _run_session.get_elapsed_sec()

func _read_loop_index() -> int:
	if _run_session == null:
		return 0
	return _run_session.get_loop_index()

func _read_kill_count() -> int:
	if _run_session == null:
		return 0
	return _run_session.get_kill_count()

func _read_gold() -> int:
	if _run_session == null:
		return 0
	return _run_session.get_gold()

func _read_level() -> int:
	if _run_session == null:
		return 1
	return _run_session.get_level()

func _read_xp() -> int:
	if _run_session == null:
		return 0
	return _run_session.get_xp()

func _read_xp_to_next() -> int:
	if _run_session == null:
		return 30
	return _run_session.get_xp_to_next()

func _read_pending_level() -> int:
	if _run_session == null:
		return 0
	return _run_session.get_pending_level_count()

func _read_catalog_count() -> int:
	if _run_session == null:
		return 0
	var catalog: UpgradeCatalog = _run_session.get_catalog()
	if catalog == null:
		return 0
	return catalog.get_count()

func _read_owned_upgrades() -> int:
	if _run_session == null:
		return 0
	return _run_session.get_owned_count()

func _read_god_label() -> String:
	if _player == null:
		return "off"
	if _player.get_player_health().is_debug_god():
		return "on"
	return "off"

func _read_dash_label() -> String:
	if _player == null:
		return "ready"
	var left: float = _player.get_player_dash().get_cooldown_left()
	if left <= 0.0:
		return "ready"
	return "%.2f" % left

func _read_offer_state() -> String:
	if _upgrade_offer == null or not _upgrade_offer.is_open():
		return "closed"
	return "open"

func _read_offer_ids() -> String:
	if _upgrade_offer == null:
		return "-"
	return _upgrade_offer.get_offer_ids_label()

func _read_phrase_label() -> String:
	if _encounter == null:
		return "-"
	return _encounter.get_phrase_label()

func _read_phrase_alive() -> int:
	if _encounter == null:
		return 0
	return _encounter.get_phrase_alive()

func _read_rest_left() -> float:
	if _encounter == null:
		return 0.0
	return _encounter.get_rest_left()

func _read_rest_sec() -> float:
	if _encounter == null:
		return 0.0
	return _encounter.get_rest_sec()

func _read_bound_record() -> GameRecord:
	if _record_id.is_empty():
		return null
	return GameRecords.get_record(_record_id)

func _read_record_id_tail() -> String:
	if _record_id.is_empty():
		return "-"
	if _record_id.length() <= 6:
		return _record_id
	return _record_id.substr(_record_id.length() - 6, 6)

func _read_record_history_count() -> int:
	var record: GameRecord = _read_bound_record()
	if record == null:
		return 0
	return record.history.size()

func _read_record_best_score() -> int:
	var record: GameRecord = _read_bound_record()
	if record == null:
		return 0
	return record.best_score

func _read_record_loop_goal() -> int:
	var record: GameRecord = _read_bound_record()
	if record == null:
		return 0
	return record.loop_goal

func _read_character_id() -> String:
	if _player == null:
		return "-"
	var character_id: String = _player.get_character_id()
	if character_id.is_empty():
		return "-"
	return character_id

func _read_score() -> int:
	if _run_session == null:
		return 0
	var outcome: String = "quit"
	if _run_session.is_cleared():
		outcome = "cleared"
	elif _run_session.is_player_dead():
		outcome = "dead"
	return GameRecords.compute_score(
		_run_session.get_loop_index(),
		_run_session.get_kill_count(),
		_run_session.get_gold(),
		_run_session.get_elapsed_sec(),
		outcome,
	)

func _read_winner_label() -> String:
	if _winner_page != null and _winner_page.is_open():
		return "on"
	return "off"

func _read_nearest_speed() -> float:
	var nearest: EnemyBase = _find_nearest_enemy()
	if nearest == null:
		return 0.0
	return nearest.move_speed

func _read_nearest_damage() -> int:
	var nearest: EnemyBase = _find_nearest_enemy()
	if nearest == null:
		return 0
	var charger: ChargerEnemy = nearest as ChargerEnemy
	if charger != null:
		if charger.is_charging():
			return charger.charge_damage
		return charger.contact_damage
	var boss: BossEnemy = nearest as BossEnemy
	if boss != null:
		if boss.is_charging():
			return boss.charge_damage
		if boss.is_winding_volley():
			return boss.projectile_damage
		return boss.contact_damage
	var melee: MeleeEnemy = nearest as MeleeEnemy
	if melee != null:
		return melee.contact_damage
	var ranged: RangedEnemy = nearest as RangedEnemy
	if ranged != null:
		return ranged.projectile_damage
	return 0

func _format_alive_summary() -> String:
	var melee_alive: int = 0
	var ranged_alive: int = 0
	var charger_alive: int = 0
	var boss_alive: int = 0
	for enemy: EnemyBase in _enemies:
		if enemy.is_in_reserve() or enemy.is_defeated():
			continue
		if enemy is ChargerEnemy:
			charger_alive += 1
		elif enemy is BossEnemy:
			boss_alive += 1
		elif enemy is MeleeEnemy:
			melee_alive += 1
		else:
			ranged_alive += 1
	return "%dM+%dR+%dC+%dB" % [melee_alive, ranged_alive, charger_alive, boss_alive]

func _count_dead_enemies() -> int:
	var dead: int = 0
	for enemy: EnemyBase in _enemies:
		if enemy.is_in_reserve() or not enemy.is_defeated():
			continue
		dead += 1
	return dead

func _format_nearest() -> String:
	var nearest: EnemyBase = _find_nearest_enemy()
	if nearest == null:
		return "-"
	return "%s %d" % [nearest.get_kind_name(), nearest.get_hp()]

func _read_hitstop_ms() -> float:
	var left_sec: float = 0.0
	for enemy: EnemyBase in _enemies:
		if enemy.is_in_reserve():
			continue
		left_sec = maxf(left_sec, enemy.get_hitstop_left_sec())
	return left_sec * 1000.0

func _read_knockback_speed() -> float:
	var nearest: EnemyBase = _find_nearest_enemy()
	if nearest == null:
		return 0.0
	return nearest.get_knockback_speed()

func _read_shake_offset() -> Vector2:
	if _player_camera == null:
		return Vector2.ZERO
	return _player_camera.get_shake_offset()

func _read_shake_speed() -> float:
	return _read_shake_offset().length()

func _find_nearest_enemy() -> EnemyBase:
	if _enemies.is_empty():
		return null
	var nearest: EnemyBase = null
	var best_dist: float = INF
	for enemy: EnemyBase in _enemies:
		if enemy.is_in_reserve() or enemy.is_defeated():
			continue
		var dist: float = INF
		if _player != null:
			dist = enemy.global_position.distance_squared_to(_player.global_position)
		if dist < best_dist:
			best_dist = dist
			nearest = enemy
	return nearest

func _tick_fps_window(delta: float) -> void:
	if delta <= 0.0:
		return
	var instant_fps: float = 1.0 / delta
	_fps_slot_min[_fps_slot_index] = minf(_fps_slot_min[_fps_slot_index], instant_fps)
	_fps_slot_sum[_fps_slot_index] += instant_fps
	_fps_slot_count[_fps_slot_index] += 1
	_fps_slot_elapsed += delta
	if _fps_slot_elapsed >= FPS_WINDOW_SEC / float(FPS_SLOT_COUNT):
		_fps_slot_elapsed = 0.0
		_fps_slot_index = (_fps_slot_index + 1) % FPS_SLOT_COUNT
		_fps_slot_min[_fps_slot_index] = INF
		_fps_slot_sum[_fps_slot_index] = 0.0
		_fps_slot_count[_fps_slot_index] = 0
	_refresh_fps_stats()

func _refresh_fps_stats() -> void:
	var min_fps: float = INF
	var sum_fps: float = 0.0
	var samples: int = 0
	for i: int in FPS_SLOT_COUNT:
		if _fps_slot_count[i] <= 0:
			continue
		min_fps = minf(min_fps, _fps_slot_min[i])
		sum_fps += _fps_slot_sum[i]
		samples += _fps_slot_count[i]
	_fps_min_2s = 0.0 if min_fps == INF else min_fps
	_fps_avg_2s = 0.0 if samples <= 0 else sum_fps / float(samples)

func _reset_fps_slots() -> void:
	_fps_slot_min.fill(INF)
	_fps_slot_sum.fill(0.0)
	_fps_slot_count.fill(0)
	_fps_slot_index = 0
	_fps_slot_elapsed = 0.0
	_fps_min_2s = 0.0
	_fps_avg_2s = 0.0

func _format_vector(value: Vector2) -> String:
	return "(%.2f, %.2f)" % [value.x, value.y]

func _read_net_label() -> String:
	if _net_session == null or not _net_session.is_online():
		return "off"
	if _net_session.is_host():
		return "host"
	if _net_session.is_guest():
		return "guest"
	return "off"

func _read_peer_id() -> int:
	if _net_session == null:
		return 0
	return _net_session.get_unique_id()

func _read_seat() -> int:
	if _net_session == null:
		return 1
	return _net_session.get_local_seat()

func _read_p2_hp() -> String:
	if _p2 == null:
		return "-"
	return str(_p2.get_player_health().get_hp())
