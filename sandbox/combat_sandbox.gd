extends Node2D
class_name CombatSandbox

const PROJECTILE_SCENE: PackedScene = preload("res://weapons/projectile.tscn")
const POOL_CAPACITY: int = 96
const ENEMY_POOL_CAPACITY: int = 64
const HIT_SPARK_SCENE: PackedScene = preload("res://combat/hit_spark.tscn")
const HIT_SPARK_CAPACITY: int = 64
const DEATH_SHARD_SCENE: PackedScene = preload("res://combat/death_shard.tscn")
const DEATH_SHARD_CAPACITY: int = 64
const COMBAT_MUSIC_DB: float = -22.0
const UPGRADE_CATALOG: UpgradeCatalog = preload("res://data/upgrade_catalog.tres")
const CHARACTER_CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const REQUIRED_UPGRADE_IDS: PackedStringArray = [
	"max_hp_s", "max_hp_m", "swift", "heavy_round", "cadence",
	"long_shot", "second_skin", "extra_pellets", "steady_rifle", "thick_hide",
]
const GRANT_UPGRADE_ID: StringName = &"max_hp_s"
const MENU_SCENE := "res://ui/main_menu.tscn"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const GUEST_SPAWN := Vector2(80, 0)
const UPGRADE_SKIP_ID := "__skip__"
const OFFER_PHRASE: int = 0
const OFFER_LEVEL: int = 1
const OFFER_SHOP: int = 2
const SNAPSHOT_VERSION: int = 1

## 只有鼠标在窗口内且窗口有焦点时才藏系统光标，避免出窗后桌面丢指针。
var _mouse_inside_window: bool = true
var _enemies: Array[EnemyBase] = []
var _offer_is_phrase: bool = false
var _progress_written: bool = false
var _record_id: String = ""
var _god_mode: bool = false
var _leaving: bool = false
var _reset_frame: int = -1
var _net_role: GameLaunch.NetRole = GameLaunch.NetRole.OFFLINE
var _lan_loadout: Dictionary = {}
var _pawns: Array[Player] = []
var _local_player: Player
var _guest_pawn: Player
var _lan_paused: bool = false
var _last_owned_label: String = ""

@onready var _viewport_container: SubViewportContainer = $ViewportContainer
@onready var _game_viewport: SubViewport = $ViewportContainer/GameViewport
@onready var _walls: Node2D = $ViewportContainer/GameViewport/World/Walls
@onready var _player: Player = $ViewportContainer/GameViewport/World/Player
@onready var _player_camera: PlayerCamera = $ViewportContainer/GameViewport/World/PlayerCamera
@onready var _aim_reticle: AimReticle = $ViewportContainer/GameViewport/World/AimReticle
@onready var _debug_overlay: DebugOverlay = $DebugOverlay
@onready var _hud: Hud = $Hud
@onready var _upgrade_offer: UpgradeOffer = $UpgradeOffer
@onready var _shop_offer: ShopOffer = $ShopOffer
@onready var _winner_page: WinnerPage = $WinnerPage
@onready var _projectiles: ProjectilePool = $ViewportContainer/GameViewport/World/Projectiles
@onready var _enemy_projectiles: ProjectilePool = $ViewportContainer/GameViewport/World/EnemyProjectiles
@onready var _hit_sparks: HitSparkPool = $ViewportContainer/GameViewport/World/HitSparks
@onready var _death_shards: DeathShardPool = $ViewportContainer/GameViewport/World/DeathShards
@onready var _enemies_root: Node2D = $ViewportContainer/GameViewport/World/Enemies
@onready var _sfx_pool: SfxPool = $ViewportContainer/GameViewport/World/SfxPool
@onready var _combat_music: AudioStreamPlayer = $CombatMusic
@onready var _encounter: EncounterPhrases = $EncounterPhrases
@onready var _run_session: RunSession = $RunSession
@onready var _upgrade_applier: UpgradeApplier = $UpgradeApplier
@onready var _pause_overlay: PauseOverlay = $PauseOverlay
@onready var _players_root: Node2D = $ViewportContainer/GameViewport/World/Players
@onready var _net: NetSession = $NetSession

func _ready() -> void:
	GameSettings.load_from_disk()
	GameSettings.apply()
	_start_combat_music()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_apply_wall_layers()
	_bind_runtime()
	_bind_window_cursor()
	_apply_render_scale()
	_sync_system_cursor()

	var gamepad_debug: Node = preload("res://debug/test_gamepad.gd").new()
	add_child(gamepad_debug)

func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if _pause_overlay.is_open() and not _is_lan():
		return
	if _is_guest():
		_sync_lan_pause_overlay()
		_sync_system_cursor()
		return
	if _lan_paused:
		_sync_lan_pause_overlay()
		if _run_session.is_player_dead() or _run_session.is_cleared():
			_show_winner_if_needed()
		return
	if _upgrade_offer.is_open() or _shop_offer.is_open():
		if _all_pawns_defeated():
			if _upgrade_offer.is_open():
				_abort_offer()
			if _shop_offer.is_open():
				_abort_shop()
		elif _run_session.is_player_dead() or _run_session.is_cleared():
			_show_winner_if_needed()
		return
	_tick_god_mode_kills()
	if _run_session.is_playing() and not _upgrade_offer.is_open() and not _shop_offer.is_open() and not _encounter.is_awaiting_offer() and not _run_session.has_pending_level():
		_encounter.tick(delta)
	if _run_session.is_playing() and _encounter.is_awaiting_offer() and not _upgrade_offer.is_open() and not _shop_offer.is_open():
		_open_offer_if_needed()
	elif _run_session.is_playing() and _run_session.has_pending_level() and not _upgrade_offer.is_open() and not _shop_offer.is_open() and not _encounter.is_awaiting_offer() and not _all_pawns_defeated():
		_open_level_offer_if_needed()
	if _upgrade_offer.is_open() and _all_pawns_defeated():
		_abort_offer()
	if _shop_offer.is_open() and _all_pawns_defeated():
		_abort_shop()
	if _run_session.is_playing() and not _all_pawns_defeated() and _encounter.is_done() and not _upgrade_offer.is_open() and not _shop_offer.is_open() and not _run_session.has_pending_level():
		_loop_phrases()
	_run_session.tick(delta)
	if _run_session.is_player_dead() or _run_session.is_cleared():
		_show_winner_if_needed()

func _input(event: InputEvent) -> void:
	if event.is_pressed():
		GameAudio.unlock_driver(self)
		_ensure_combat_music()

func _unhandled_input(event: InputEvent) -> void:
	if _is_pause_toggle(event):
		get_viewport().set_input_as_handled()
		_on_pause_toggle()
		return
	if event.is_action_pressed("sandbox_reset"):
		if _pause_overlay.is_open():
			return
		get_viewport().set_input_as_handled()
		if _is_guest():
			return
		if _winner_page.is_open():
			_on_winner_retry()
			return
		_host_reset_sandbox()
		return
	if event.is_action_pressed("debug_grant_upgrade"):
		if _is_lan() or _pause_overlay.is_open() or _winner_page.is_open():
			return
		_try_debug_grant()
		get_viewport().set_input_as_handled()
		return
	_try_debug_hotkeys(event)

func _park_combat_pools() -> void:
	_projectiles.park_all()
	_enemy_projectiles.park_all()
	_hit_sparks.park_all()
	_death_shards.park_all()

func _bind_projectile_sparks(pool: ProjectilePool) -> void:
	for child: Node in pool.get_children():
		var projectile: Projectile = child as Projectile
		if projectile == null:
			continue
		projectile.bind_spark_pool(_hit_sparks)

func _start_combat_music() -> void:
	var mp3: AudioStreamMP3 = _combat_music.stream as AudioStreamMP3
	if mp3 != null:
		mp3.loop = true
	_combat_music.volume_db = COMBAT_MUSIC_DB
	_ensure_combat_music()

func _ensure_combat_music() -> void:
	if _combat_music.stream != null and not _combat_music.playing:
		_combat_music.play()

func _bind_runtime() -> void:
	_net_role = GameLaunch.take_net_role()
	_lan_loadout = GameLaunch.take_lan_loadout()
	if _is_lan():
		GameLaunch.take_join_address()
		if multiplayer.multiplayer_peer == null:
			_return_to_menu()
			return
	_net.configure(_net_role, self)
	_net.peer_lost.connect(_on_peer_lost)
	_net.input_received.connect(_on_net_input)
	_net.snapshot_received.connect(_on_net_snapshot)
	_net.fire_fx_received.connect(_on_net_fire_fx)
	_net.offer_open_received.connect(_on_net_offer_open)
	_net.offer_close_received.connect(_on_net_offer_close)
	_net.winner_received.connect(_on_net_winner)
	_net.reset_received.connect(_reset_sandbox)
	_net.return_menu_received.connect(_return_to_menu)
	_net.try_pick_received.connect(_on_net_try_pick)
	_net.try_unpause_received.connect(_on_net_try_unpause)
	_net.try_pause_received.connect(_on_net_try_pause)
	_prepare_pawns()
	var player_input: PlayerInput = _local_player.get_player_input()
	_projectiles.setup(_projectiles, PROJECTILE_SCENE, POOL_CAPACITY)
	_enemy_projectiles.setup(_enemy_projectiles, PROJECTILE_SCENE, ENEMY_POOL_CAPACITY)
	_hit_sparks.setup(_hit_sparks, HIT_SPARK_SCENE, HIT_SPARK_CAPACITY)
	_death_shards.setup(_death_shards, DEATH_SHARD_SCENE, DEATH_SHARD_CAPACITY)
	_bind_projectile_sparks(_projectiles)
	_bind_projectile_sparks(_enemy_projectiles)
	for pawn: Player in _pawns:
		pawn.bind_projectile_pool(_projectiles)
		pawn.bind_sfx_pool(_sfx_pool)
		if pawn == _local_player:
			pawn.bind_player_camera(_player_camera)
		if _is_host():
			pawn.shot_fired.connect(_on_pawn_shot_fired.bind(pawn))
	_player_camera.bind_player(_local_player)
	_aim_reticle.bind_player_input(player_input)
	_debug_overlay.bind_player(_local_player)
	_debug_overlay.bind_player_camera(_player_camera)
	_debug_overlay.bind_weapon_host(_local_player.get_weapon_host())
	_debug_overlay.bind_projectile_pool(_projectiles)
	_debug_overlay.bind_enemy_projectile_pool(_enemy_projectiles)
	_debug_overlay.bind_hit_spark_pool(_hit_sparks)
	_debug_overlay.bind_death_shard_pool(_death_shards)
	_enemies = _collect_enemies()
	_bind_enemies(_enemies)
	_encounter.bind_enemies(_enemies)
	_encounter.bind_run_session(_run_session)
	_hold_all_in_reserve()
	_debug_overlay.bind_enemies(_enemies)
	_debug_overlay.bind_encounter(_encounter)
	_hud.bind_player(_local_player)
	_hud.bind_weapon_host(_local_player.get_weapon_host())
	_hud.bind_encounter(_encounter)
	_hud.bind_run_session(_run_session)
	_run_session.bind_players(_pawns)
	_run_session.bind_encounter(_encounter)
	_run_session.bind_catalog(UPGRADE_CATALOG)
	_assert_upgrade_catalog()
	_bind_playable_record()
	if _is_lan():
		_run_session.configure_mode(int(_lan_loadout.get("loop_goal", 0)))
	else:
		_run_session.configure_mode(_read_record_loop_goal())
	_apply_record_character()
	_run_session.restart()
	if not _is_guest():
		_apply_loop_pressure()
		_encounter.restart()
	_upgrade_applier.bind_players(_pawns)
	_upgrade_applier.bind_session(_run_session)
	_upgrade_applier.capture_baseline()
	_upgrade_applier.apply_owned()
	_upgrade_offer.bind_session(_run_session)
	_upgrade_offer.bind_player_input(player_input)
	_upgrade_offer.picked.connect(_on_upgrade_picked)
	_upgrade_offer.cancelled.connect(_return_to_menu)
	_shop_offer.bind_session(_run_session)
	_shop_offer.bind_player_input(player_input)
	_shop_offer.bought.connect(_on_shop_bought)
	_shop_offer.skipped.connect(_on_shop_skipped)
	_shop_offer.cancelled.connect(_return_to_menu)
	_pause_overlay.bind_run_session(_run_session)
	_pause_overlay.bind_encounter(_encounter)
	_pause_overlay.resumed.connect(_on_pause_resumed)
	_pause_overlay.retried.connect(_on_pause_retried)
	_pause_overlay.quit_pressed.connect(_on_pause_quit)
	_winner_page.retry_pressed.connect(_on_winner_retry)
	_winner_page.menu_pressed.connect(_on_winner_menu)
	_debug_overlay.bind_run_session(_run_session)
	_debug_overlay.bind_upgrade_offer(_upgrade_offer)
	_debug_overlay.bind_winner_page(_winner_page)
	_debug_overlay.bind_record_id(_record_id)
	_debug_overlay.bind_net_session(_net)
	_debug_overlay.bind_p2(_guest_pawn)
	_debug_overlay.set_last_grant_id("-")

func _collect_enemies() -> Array[EnemyBase]:
	var enemies: Array[EnemyBase] = []
	for child: Node in _enemies_root.get_children():
		var enemy: EnemyBase = child as EnemyBase
		if enemy != null:
			enemies.append(enemy)
	return enemies

func _bind_enemies(enemies: Array[EnemyBase]) -> void:
	for enemy: EnemyBase in enemies:
		enemy.bind_players(_pawns)
		enemy.set_sim_authority(not _is_guest())
		enemy.bind_sfx_pool(_sfx_pool)
		if _is_host() or not _is_lan():
			enemy.bind_player_camera(_player_camera)
		enemy.bind_shard_pool(_death_shards)
		if not enemy.defeated.is_connected(_on_enemy_defeated):
			enemy.defeated.connect(_on_enemy_defeated.bind(enemy))
		var ranged: RangedEnemy = enemy as RangedEnemy
		if ranged != null:
			ranged.bind_projectile_pool(_enemy_projectiles)
		var boss: BossEnemy = enemy as BossEnemy
		if boss != null:
			boss.bind_projectile_pool(_enemy_projectiles)

func _on_enemy_defeated(_enemy: EnemyBase) -> void:
	if _is_guest():
		return
	if not _run_session.is_playing() or _all_pawns_defeated():
		return
	_run_session.note_kill()
	var reward: int = _enemy.get_xp_reward()
	if reward > 0:
		_run_session.add_xp(reward)
	_run_session.add_gold(_enemy.get_gold_reward())

func _assert_upgrade_catalog() -> void:
	if UPGRADE_CATALOG.get_count() != 10:
		push_error("升级目录条目数应为 10，实际 %d" % UPGRADE_CATALOG.get_count())
	for upgrade_id: String in REQUIRED_UPGRADE_IDS:
		if UPGRADE_CATALOG.get_by_id(StringName(upgrade_id)) == null:
			push_error("升级目录缺少 id: %s" % upgrade_id)

func _hold_all_in_reserve() -> void:
	for enemy: EnemyBase in _enemies:
		enemy.hold_in_reserve()

func _loop_phrases() -> void:
	_park_combat_pools()
	_hold_all_in_reserve()
	var defs: Array[UpgradeDef] = _run_session.draft_offer(3)
	if defs.is_empty():
		_finish_loop_after_shop()
		return
	_set_combat_frozen(true)
	_shop_offer.present(defs, _run_session.get_gold())
	_set_offer_input_lock(true)
	_broadcast_offer_open(OFFER_SHOP, defs, _run_session.get_gold())

func _finish_loop_after_shop() -> void:
	_run_session.notify_phrase_loop()
	if _run_session.get_loop_goal() > 0 and _run_session.get_loop_index() >= _run_session.get_loop_goal():
		_run_session.mark_cleared()
		_park_combat_pools()
		_hold_all_in_reserve()
		_set_offer_input_lock(true)
		_show_winner_if_needed()
		return
	_apply_loop_pressure()
	_encounter.restart()

func _apply_loop_pressure() -> void:
	var loop_index: int = _run_session.get_loop_index()
	for enemy: EnemyBase in _enemies:
		enemy.apply_loop_pressure(loop_index)

func _reset_sandbox() -> void:
	var frame: int = Engine.get_process_frames()
	if _reset_frame == frame:
		return
	_reset_frame = frame
	_lan_paused = false
	if _winner_page.is_open():
		_winner_page.close()
	if _upgrade_offer.is_open():
		_close_offer()
	if _shop_offer.is_open():
		_close_shop()
	if _pause_overlay.is_open():
		_pause_overlay.close(false)
	_park_combat_pools()
	_run_session.restart()
	_upgrade_applier.apply_owned()
	for pawn: Player in _pawns:
		pawn.set_sim_paused(false)
		pawn.reset_for_sandbox()
	_hold_all_in_reserve()
	if not _is_guest():
		_apply_loop_pressure()
		_encounter.restart()
	_debug_overlay.set_last_grant_id("-")
	_progress_written = false
	_last_owned_label = ""
	_set_offer_input_lock(false)

func _try_debug_grant() -> void:
	if _upgrade_offer.is_open() or _shop_offer.is_open() or _pause_overlay.is_open() or _winner_page.is_open():
		return
	if _all_pawns_defeated():
		return
	if not _run_session.try_grant(GRANT_UPGRADE_ID):
		return
	_upgrade_applier.apply_owned()
	_debug_overlay.set_last_grant_id(String(GRANT_UPGRADE_ID))

func _open_offer_if_needed() -> void:
	if not _run_session.is_playing() or _all_pawns_defeated():
		return
	_offer_is_phrase = true
	var defs: Array[UpgradeDef] = _run_session.draft_offer(3)
	if defs.is_empty():
		_encounter.acknowledge_offer()
		return
	_set_combat_frozen(true)
	_upgrade_offer.present(defs)
	_set_offer_input_lock(true)
	_broadcast_offer_open(OFFER_PHRASE, defs, _run_session.get_gold())

func _open_level_offer_if_needed() -> void:
	if not _run_session.is_playing() or _all_pawns_defeated():
		return
	_offer_is_phrase = false
	var defs: Array[UpgradeDef] = _run_session.draft_offer(3)
	if defs.is_empty():
		_run_session.consume_pending_level()
		return
	_set_combat_frozen(true)
	_upgrade_offer.present(defs)
	_set_offer_input_lock(true)
	_broadcast_offer_open(OFFER_LEVEL, defs, _run_session.get_gold())

func _on_upgrade_picked(upgrade_id: StringName) -> void:
	if _is_guest():
		_net.send_try_pick(String(upgrade_id))
		return
	if not _upgrade_offer.is_open():
		return
	if _all_pawns_defeated() or not _run_session.is_playing():
		_abort_offer()
		return
	if not _run_session.try_grant(upgrade_id):
		return
	_upgrade_applier.apply_owned()
	_debug_overlay.set_last_grant_id(String(upgrade_id))
	var was_phrase: bool = _offer_is_phrase
	_close_offer()
	_broadcast_offer_close(String(upgrade_id))
	if was_phrase:
		_encounter.acknowledge_offer()
		return
	_run_session.consume_pending_level()

func _abort_offer() -> void:
	_close_offer()
	while _run_session.consume_pending_level():
		pass

func _close_offer() -> void:
	_upgrade_offer.close()
	_set_offer_input_lock(false)
	_set_combat_frozen(false)

func _on_shop_bought(upgrade_id: StringName) -> void:
	if _is_guest():
		_net.send_try_pick(String(upgrade_id))
		return
	if not _shop_offer.is_open():
		return
	if _all_pawns_defeated() or not _run_session.is_playing():
		_abort_shop()
		return
	var cost: int = _run_session.get_shop_cost(upgrade_id)
	if _run_session.get_gold() < cost:
		return
	if not _run_session.try_grant(upgrade_id):
		return
	if not _run_session.try_spend(cost):
		push_error("商店扣款失败：upgrade=%s cost=%d gold=%d" % [String(upgrade_id), cost, _run_session.get_gold()])
		return
	_upgrade_applier.apply_owned()
	_debug_overlay.set_last_grant_id(String(upgrade_id))
	_close_shop()
	_broadcast_offer_close(String(upgrade_id))
	_finish_loop_after_shop()

func _on_shop_skipped() -> void:
	if _is_guest():
		_net.send_try_pick(UPGRADE_SKIP_ID)
		return
	if not _shop_offer.is_open():
		return
	_close_shop()
	_broadcast_offer_close(UPGRADE_SKIP_ID)
	if _all_pawns_defeated() or not _run_session.is_playing():
		return
	_finish_loop_after_shop()

func _abort_shop() -> void:
	_close_shop()

func _close_shop() -> void:
	_shop_offer.close()
	_set_offer_input_lock(false)
	_set_combat_frozen(false)

func _set_combat_frozen(frozen: bool) -> void:
	if _is_lan():
		if not frozen and _lan_paused:
			return
		for pawn: Player in _pawns:
			if pawn != null:
				pawn.set_sim_paused(frozen)
		for enemy: EnemyBase in _enemies:
			enemy.set_sim_paused(frozen)
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if frozen:
		tree.paused = true
		return
	if _pause_overlay.is_open():
		return
	tree.paused = false

func _set_offer_input_lock(locked: bool) -> void:
	for pawn: Player in _pawns:
		if pawn == null:
			continue
		pawn.get_player_input().set_fire_suppressed(locked)
		pawn.get_player_input().set_dash_suppressed(locked)
		pawn.get_weapon_host().set_switch_suppressed(locked)
	if locked:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_aim_reticle.visible = false
		return
	_sync_system_cursor()

func _bind_window_cursor() -> void:
	var window: Window = get_window()
	window.mouse_entered.connect(_on_window_mouse_entered)
	window.mouse_exited.connect(_on_window_mouse_exited)
	window.focus_entered.connect(_sync_system_cursor)
	window.focus_exited.connect(_sync_system_cursor)
	window.size_changed.connect(_apply_render_scale)
	_mouse_inside_window = true

## Godot 4.6：stretch=true 时禁止手改 SubViewport.size。容器 size 就是像素缓冲，scale 撑满逻辑画布。
func _apply_render_scale() -> void:
	var target_size: Vector2i = get_window().size
	var canvas_size: Vector2 = get_viewport().get_visible_rect().size
	if canvas_size.x < 1.0 or canvas_size.y < 1.0:
		canvas_size = Vector2(1920, 1080)
	var scaled: Vector2i = Vector2i((Vector2(target_size) * GameSettings.get_render_scale()).round())
	scaled.x = maxi(scaled.x, 1)
	scaled.y = maxi(scaled.y, 1)
	_viewport_container.position = Vector2.ZERO
	_viewport_container.size = Vector2(scaled)
	_viewport_container.scale = canvas_size / Vector2(scaled)
	_game_viewport.size_2d_override = Vector2i(canvas_size.round())
	_game_viewport.size_2d_override_stretch = true
	_game_viewport.msaa_2d = get_viewport().msaa_2d

func _on_window_mouse_entered() -> void:
	_mouse_inside_window = true
	_sync_system_cursor()

func _on_window_mouse_exited() -> void:
	_mouse_inside_window = false
	_sync_system_cursor()

func _sync_system_cursor() -> void:
	if _upgrade_offer.is_open() or _shop_offer.is_open() or _pause_overlay.is_open() or _winner_page.is_open() or _run_session.is_player_dead() or _run_session.is_cleared():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_aim_reticle.visible = false
		return
	var hide_cursor: bool = get_window().has_focus() and _mouse_inside_window
	if hide_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_aim_reticle.visible = hide_cursor

func _apply_wall_layers() -> void:
	for child: Node in _walls.get_children():
		var body: StaticBody2D = child as StaticBody2D
		if body == null:
			continue
		body.collision_layer = GameCollisionLayers.MASK_WALL
		body.collision_mask = GameCollisionLayers.MASK_NONE

func _is_pause_toggle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null and joy_button.pressed and joy_button.button_index == JOY_BUTTON_START:
		return true
	return false

func _on_pause_toggle() -> void:
	if _pause_overlay.is_open():
		return
	if _winner_page.is_open() or _all_pawns_defeated() or _run_session.is_cleared() or _upgrade_offer.is_open() or _shop_offer.is_open():
		_return_to_menu()
		return
	if _is_lan():
		if _is_guest():
			_net.send_try_pause()
			return
		_set_lan_paused(true)
		return
	_set_offer_input_lock(true)
	_pause_overlay.open()

func _on_pause_resumed() -> void:
	_apply_render_scale()
	if _is_guest():
		_net.send_try_unpause()
		return
	if _is_lan():
		_set_lan_paused(false)
		return
	_set_offer_input_lock(false)

func _on_pause_retried() -> void:
	if _is_guest():
		return
	if _is_lan():
		if _pause_overlay.is_open():
			_pause_overlay.close(false)
		_lan_paused = false
		_host_reset_sandbox()
		return
	_reset_sandbox()
	_pause_overlay.close()

func _on_pause_quit() -> void:
	_return_to_menu()

func _apply_record_character() -> void:
	if _is_lan():
		_apply_character_id(_pawns[0] if not _pawns.is_empty() else _player, str(_lan_loadout.get("host_character_id", "boar")))
		if _pawns.size() > 1:
			_apply_character_id(_pawns[1], str(_lan_loadout.get("guest_character_id", "boar")))
		return
	var record: GameRecord = GameRecords.get_record(_record_id)
	var character_id: String = "boar"
	if record != null:
		character_id = record.character_id
	_apply_character_id(_player, character_id)

func _apply_character_id(pawn: Player, character_id: String) -> void:
	if pawn == null:
		return
	var def: CharacterDef = CHARACTER_CATALOG.get_by_id(StringName(character_id))
	if def == null:
		def = CHARACTER_CATALOG.get_by_id(&"boar")
	pawn.apply_character(def)

func _bind_playable_record() -> void:
	if _is_lan():
		GameLaunch.take_active_record_id()
		GameLaunch.take_mode()
		_record_id = ""
		return
	GameRecords.load_from_disk()
	_record_id = GameLaunch.take_active_record_id()
	if _record_id.is_empty() or GameRecords.get_record(_record_id) == null:
		var fallback_goal: int = GameLaunch.SOLO_LOOP_GOAL if GameLaunch.take_mode() == GameLaunch.Mode.SOLO else 0
		_record_id = GameRecords.ensure_playable_record("boar", fallback_goal).id

func _read_record_loop_goal() -> int:
	var record: GameRecord = GameRecords.get_record(_record_id)
	if record == null:
		return 0
	return record.loop_goal

func _record_outcome() -> String:
	if _run_session.is_cleared():
		return "cleared"
	if _run_session.is_player_dead():
		return "dead"
	return "quit"

func _show_winner_if_needed() -> void:
	if _winner_page.is_open():
		return
	_winner_page.set_retry_allowed(not _is_guest())
	if _is_lan():
		if _is_host():
			_net.send_winner(
				_record_outcome(),
				_run_session.get_loop_index(),
				_run_session.get_kill_count(),
				_run_session.get_gold(),
				_run_session.get_elapsed_sec()
			)
		_winner_page.present("", _run_session, 0)
		_set_offer_input_lock(true)
		_sync_system_cursor()
		return
	GameRecords.load_from_disk()
	var previous_best: int = 0
	var record: GameRecord = GameRecords.get_record(_record_id)
	if record != null:
		previous_best = record.best_score
	_record_progress_if_needed()
	_winner_page.present(_record_id, _run_session, previous_best)
	_set_offer_input_lock(true)
	_sync_system_cursor()

func _on_winner_retry() -> void:
	if not _winner_page.is_open():
		return
	if _is_guest():
		return
	_winner_page.close()
	_host_reset_sandbox()

func _on_winner_menu() -> void:
	_return_to_menu()

func _record_progress_if_needed() -> void:
	if _is_lan():
		return
	if _progress_written:
		return
	GameProgress.record_run(_run_session)
	GameRecords.append_run_result(_record_id, _run_session, _record_outcome())
	_progress_written = true

func _return_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	if _is_host():
		_net.send_return_menu()
	_record_progress_if_needed()
	if _is_lan():
		_net.close_peer()
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
		tree.change_scene_to_file(MENU_SCENE)

func _try_debug_hotkeys(event: InputEvent) -> void:
	if _is_lan():
		return
	if not OS.is_debug_build():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		_debug_swap_character()
		return
	if key.physical_keycode == KEY_F4:
		get_viewport().set_input_as_handled()
		_toggle_god_mode()
		return
	if key.physical_keycode == KEY_F3:
		get_viewport().set_input_as_handled()
		_debug_jump_final_loop()
		return
	if key.physical_keycode == KEY_F2:
		get_viewport().set_input_as_handled()
		_debug_jump_boss()

func _debug_swap_character() -> void:
	if _pause_overlay.is_open() or _winner_page.is_open() or _upgrade_offer.is_open() or _shop_offer.is_open():
		return
	var next_id: StringName = &"chicken"
	if _player.get_character_id() == "chicken":
		next_id = &"boar"
	var def: CharacterDef = CHARACTER_CATALOG.get_by_id(next_id)
	if def == null:
		return
	_player.apply_character(def)
	_upgrade_applier.capture_baseline()
	_upgrade_applier.apply_owned()
	_player.get_player_health().fill_hp()

func _toggle_god_mode() -> void:
	if _pause_overlay.is_open() or _winner_page.is_open() or _upgrade_offer.is_open() or _shop_offer.is_open():
		return
	_god_mode = not _god_mode
	_player.get_player_health().set_debug_god(_god_mode)

func _debug_jump_final_loop() -> void:
	if _pause_overlay.is_open() or _winner_page.is_open() or _upgrade_offer.is_open() or _shop_offer.is_open():
		return
	if _run_session.get_loop_goal() <= 0 or not _run_session.is_playing() or _run_session.is_cleared():
		return
	if _player.is_defeated():
		return
	_run_session.debug_set_loop_index(_run_session.get_loop_goal() - 1)
	_apply_loop_pressure()
	_park_combat_pools()
	_hold_all_in_reserve()
	_encounter.restart()

func _debug_jump_boss() -> void:
	if _pause_overlay.is_open() or _winner_page.is_open() or _upgrade_offer.is_open() or _shop_offer.is_open():
		return
	if not _run_session.is_playing() or _run_session.is_cleared():
		return
	if _player.is_defeated():
		return
	_park_combat_pools()
	_hold_all_in_reserve()
	_encounter.debug_begin_boss()

func _tick_god_mode_kills() -> void:
	if not _god_mode:
		return
	if not _run_session.is_playing() or _all_pawns_defeated() or _run_session.is_cleared():
		return
	if _upgrade_offer.is_open() or _shop_offer.is_open() or _pause_overlay.is_open() or _winner_page.is_open():
		return
	for enemy: EnemyBase in _enemies:
		if enemy.is_in_reserve() or enemy.is_defeated():
			continue
		enemy.apply_damage(enemy.get_hp(), enemy.global_position, Vector2.RIGHT)

func _prepare_pawns() -> void:
	_pawns.clear()
	_guest_pawn = null
	_player.set_spawn_position(_player.global_position)
	_pawns.append(_player)
	if _is_lan():
		_guest_pawn = PLAYER_SCENE.instantiate() as Player
		_guest_pawn.name = "Player2"
		_players_root.add_child(_guest_pawn)
		_guest_pawn.global_position = GUEST_SPAWN
		_guest_pawn.set_spawn_position(GUEST_SPAWN)
		_pawns.append(_guest_pawn)
	if _is_guest() and _pawns.size() > 1:
		_local_player = _pawns[1]
	else:
		_local_player = _pawns[0]
	for pawn: Player in _pawns:
		if pawn == null:
			continue
		if _is_host() and pawn == _guest_pawn:
			pawn.get_player_input().set_remote_driven(true)
			pawn.set_simulate_combat(true)
			continue
		if _is_guest() and pawn != _local_player:
			pawn.get_player_input().set_remote_driven(true)
			pawn.set_simulate_combat(false)
			continue
		if _is_guest() and pawn == _local_player:
			pawn.get_player_input().set_remote_driven(false)
			pawn.set_simulate_combat(false)
			continue
		pawn.get_player_input().set_remote_driven(false)
		pawn.set_simulate_combat(true)

func _is_lan() -> bool:
	return _net_role != GameLaunch.NetRole.OFFLINE

func _is_host() -> bool:
	return _net_role == GameLaunch.NetRole.HOST

func _is_guest() -> bool:
	return _net_role == GameLaunch.NetRole.GUEST

func _all_pawns_defeated() -> bool:
	if _pawns.is_empty():
		return _player != null and _player.is_defeated()
	for pawn: Player in _pawns:
		if pawn != null and not pawn.is_defeated():
			return false
	return true

func _host_reset_sandbox() -> void:
	_reset_sandbox()
	if _is_host():
		_net.send_reset()

func _set_lan_paused(paused: bool) -> void:
	_lan_paused = paused
	for pawn: Player in _pawns:
		if pawn != null:
			pawn.set_sim_paused(paused)
	for enemy: EnemyBase in _enemies:
		enemy.set_sim_paused(paused)
	if paused:
		if not _pause_overlay.is_open():
			_set_offer_input_lock(true)
			_pause_overlay.open(false)
		return
	if _pause_overlay.is_open():
		_pause_overlay.close(false)
	_set_offer_input_lock(false)

func _sync_lan_pause_overlay() -> void:
	if not _is_lan():
		return
	if _lan_paused:
		if not _pause_overlay.is_open():
			_set_offer_input_lock(true)
			_pause_overlay.open(false)
		return
	if _pause_overlay.is_open():
		_pause_overlay.close(false)
		_set_offer_input_lock(false)

func flush_guest_input() -> void:
	if not _is_guest() or _local_player == null:
		return
	var player_input: PlayerInput = _local_player.get_player_input()
	_net.send_input({
		"mx": player_input.move_vector.x,
		"my": player_input.move_vector.y,
		"ax": player_input.aim_vector.x,
		"ay": player_input.aim_vector.y,
		"fire": player_input.fire_held,
		"dash": player_input.take_pending_dash(),
		"weapon_slot": player_input.take_pending_weapon_slot(),
	})

func flush_net_snapshot() -> void:
	if not _is_host():
		return
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u8(SNAPSHOT_VERSION)
	buf.put_u8(1 if _lan_paused else 0)
	buf.put_u8(_pawns.size())
	for pawn: Player in _pawns:
		var aim: Vector2 = pawn.get_player_input().aim_vector
		var health: PlayerHealth = pawn.get_player_health()
		buf.put_float(pawn.global_position.x)
		buf.put_float(pawn.global_position.y)
		buf.put_float(pawn.velocity.x)
		buf.put_float(pawn.velocity.y)
		buf.put_float(aim.x)
		buf.put_float(aim.y)
		buf.put_u16(clampi(health.get_hp(), 0, 65535))
		buf.put_u16(clampi(health.get_max_hp(), 0, 65535))
		buf.put_u8(1 if pawn.is_defeated() else 0)
		buf.put_u8(pawn.get_weapon_host().get_current_index())
		buf.put_u8(1 if pawn.get_facing_flip() else 0)
	buf.put_u8(_enemies.size())
	for i: int in _enemies.size():
		var enemy: EnemyBase = _enemies[i]
		var flags: int = 0
		if enemy.is_in_reserve():
			flags |= 1
		if enemy.is_defeated():
			flags |= 2
		buf.put_u8(i)
		buf.put_u8(flags)
		buf.put_float(enemy.global_position.x)
		buf.put_float(enemy.global_position.y)
		buf.put_u16(clampi(enemy.get_hp(), 0, 65535))
	buf.put_u16(clampi(_run_session.get_loop_index(), 0, 65535))
	buf.put_u16(clampi(_run_session.get_gold(), 0, 65535))
	buf.put_u16(clampi(_run_session.get_kill_count(), 0, 65535))
	buf.put_u16(clampi(_run_session.get_xp(), 0, 65535))
	buf.put_u16(clampi(_run_session.get_level(), 0, 65535))
	buf.put_u16(clampi(_run_session.get_pending_level_count(), 0, 65535))
	buf.put_u8(int(_run_session.get_outcome()))
	buf.put_float(_run_session.get_elapsed_sec())
	buf.put_u8(_encounter.get_phrase_index())
	buf.put_u8(_encounter.get_state_code())
	buf.put_float(_encounter.get_rest_left())
	var owned: PackedStringArray = _run_session.get_owned_upgrade_ids()
	buf.put_u8(mini(owned.size(), 255))
	var owned_count: int = mini(owned.size(), 255)
	for i: int in owned_count:
		buf.put_utf8_string(owned[i])
	_net.send_snapshot(buf.data_array)

func _on_net_input(move: Vector2, aim: Vector2, fire: bool, dash: bool, weapon_slot: int) -> void:
	if _guest_pawn == null:
		return
	_guest_pawn.get_player_input().apply_remote_frame(move, aim, fire, dash, weapon_slot)

func _on_net_snapshot(data: PackedByteArray) -> void:
	if not _is_guest() or data.is_empty():
		return
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(0)
	if buf.get_u8() != SNAPSHOT_VERSION:
		return
	_lan_paused = buf.get_u8() != 0
	var pawn_count: int = buf.get_u8()
	for i: int in pawn_count:
		var pos := Vector2(buf.get_float(), buf.get_float())
		var vel := Vector2(buf.get_float(), buf.get_float())
		var aim := Vector2(buf.get_float(), buf.get_float())
		var hp: int = buf.get_u16()
		var max_hp: int = buf.get_u16()
		var defeated: bool = buf.get_u8() != 0
		var weapon_index: int = buf.get_u8()
		var facing_flip: bool = buf.get_u8() != 0
		if i >= _pawns.size() or _pawns[i] == null:
			continue
		var local_aim: bool = _pawns[i] != _local_player
		_pawns[i].apply_net_pose(pos, vel, aim, hp, max_hp, defeated, weapon_index, facing_flip, local_aim)
	var enemy_count: int = buf.get_u8()
	for _i: int in enemy_count:
		var index: int = buf.get_u8()
		var flags: int = buf.get_u8()
		var pos := Vector2(buf.get_float(), buf.get_float())
		var hp: int = buf.get_u16()
		if index < 0 or index >= _enemies.size():
			continue
		_enemies[index].apply_net_state(pos, hp, (flags & 2) != 0, (flags & 1) != 0)
	var loop_index: int = buf.get_u16()
	var gold: int = buf.get_u16()
	var kills: int = buf.get_u16()
	var xp: int = buf.get_u16()
	var level: int = buf.get_u16()
	var pending_level: int = buf.get_u16()
	var outcome_code: int = buf.get_u8()
	var elapsed_sec: float = buf.get_float()
	var phrase_index: int = buf.get_u8()
	var phrase_state: int = buf.get_u8()
	var rest_left: float = buf.get_float()
	var owned_count: int = buf.get_u8()
	var owned: PackedStringArray = PackedStringArray()
	for _j: int in owned_count:
		owned.append(buf.get_utf8_string())
	_run_session.apply_net_session(loop_index, gold, kills, xp, level, pending_level, outcome_code, elapsed_sec, owned)
	_encounter.apply_net_view(phrase_index, phrase_state, rest_left)
	var owned_label: String = ",".join(owned)
	if owned_label != _last_owned_label:
		_last_owned_label = owned_label
		_upgrade_applier.apply_owned()
	_sync_lan_pause_overlay()
	if _run_session.is_player_dead() or _run_session.is_cleared():
		_show_winner_if_needed()

func _on_net_fire_fx(seat: int, origin: Vector2, direction: Vector2, weapon_index: int) -> void:
	var pawn: Player = _pawn_for_seat(seat)
	if pawn == null:
		return
	var weapon: Weapon = pawn.get_weapon_host().get_weapon_at(weapon_index)
	if weapon == null:
		weapon = pawn.get_weapon_host().get_current_weapon()
	if weapon == null:
		return
	pawn.play_shot_fx(direction, weapon)
	weapon.spawn_fx_shot(origin, direction)

func _on_net_offer_open(kind: int, id0: String, id1: String, id2: String, gold: int) -> void:
	if not _is_guest():
		return
	var defs: Array[UpgradeDef] = _defs_from_ids(id0, id1, id2)
	if defs.is_empty():
		return
	_set_combat_frozen(true)
	if kind == OFFER_SHOP:
		_shop_offer.present(defs, gold)
	else:
		_offer_is_phrase = kind == OFFER_PHRASE
		_upgrade_offer.present(defs)
	_set_offer_input_lock(true)

func _on_net_offer_close(_picked_id: String) -> void:
	if not _is_guest():
		return
	if _upgrade_offer.is_open():
		_close_offer()
	if _shop_offer.is_open():
		_close_shop()
	_upgrade_applier.apply_owned()

func _on_net_winner(outcome: String, loop_index: int, kills: int, gold: int, time_sec: float) -> void:
	if not _is_guest():
		return
	var outcome_code: int = int(RunSession.Outcome.DEAD)
	if outcome == "cleared":
		outcome_code = int(RunSession.Outcome.CLEARED)
	_run_session.apply_net_session(
		loop_index,
		gold,
		kills,
		_run_session.get_xp(),
		_run_session.get_level(),
		0,
		outcome_code,
		time_sec,
		_run_session.get_owned_upgrade_ids()
	)
	_show_winner_if_needed()

func _on_net_try_pick(upgrade_id: String) -> void:
	if not _is_host():
		return
	if upgrade_id == UPGRADE_SKIP_ID:
		_on_shop_skipped()
		return
	if _upgrade_offer.is_open():
		_on_upgrade_picked(StringName(upgrade_id))
		return
	if _shop_offer.is_open():
		_on_shop_bought(StringName(upgrade_id))

func _on_net_try_unpause() -> void:
	if not _is_host():
		return
	_set_lan_paused(false)

func _on_net_try_pause() -> void:
	if not _is_host():
		return
	if _winner_page.is_open() or _all_pawns_defeated() or _run_session.is_cleared() or _upgrade_offer.is_open() or _shop_offer.is_open():
		return
	_set_lan_paused(true)

func _on_peer_lost() -> void:
	_return_to_menu()

func _on_pawn_shot_fired(aim: Vector2, _weapon: Weapon, pawn: Player) -> void:
	if not _is_host() or pawn == null:
		return
	var seat: int = 1 if pawn == _pawns[0] else 2
	_net.send_fire_fx(seat, pawn.get_muzzle_global_position(), aim, pawn.get_weapon_host().get_current_index())

func _broadcast_offer_open(kind: int, defs: Array[UpgradeDef], gold: int) -> void:
	if not _is_host():
		return
	var id0: String = String(defs[0].id) if defs.size() > 0 else ""
	var id1: String = String(defs[1].id) if defs.size() > 1 else ""
	var id2: String = String(defs[2].id) if defs.size() > 2 else ""
	_net.send_offer_open(kind, id0, id1, id2, gold)

func _broadcast_offer_close(picked_id: String) -> void:
	if not _is_host():
		return
	_net.send_offer_close(picked_id)

func _defs_from_ids(id0: String, id1: String, id2: String) -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	for upgrade_id: String in [id0, id1, id2]:
		if upgrade_id.is_empty() or upgrade_id == UPGRADE_SKIP_ID:
			continue
		var def: UpgradeDef = UPGRADE_CATALOG.get_by_id(StringName(upgrade_id))
		if def != null:
			defs.append(def)
	return defs

func _pawn_for_seat(seat: int) -> Player:
	if seat <= 1:
		if _pawns.is_empty():
			return _player
		return _pawns[0]
	if _pawns.size() > 1:
		return _pawns[1]
	return _guest_pawn
