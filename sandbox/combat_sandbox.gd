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
const SILENCE_DB: float = -80.0
const BGM_FADE_SEC: float = 0.45
const LOADING_SCREEN_SCRIPT := preload("res://ui/loading_screen.gd")
const UPGRADE_CATALOG: UpgradeCatalog = preload("res://data/upgrade_catalog.tres")
const CHARACTER_CATALOG: CharacterCatalog = preload("res://data/character_catalog.tres")
const COMPANION_CATALOG: CompanionCatalog = preload("res://data/companion_catalog.tres")
const CONSUMABLE_CATALOG: ConsumableCatalog = preload("res://data/consumable_catalog.tres")
const ARENA_CATALOG: ArenaCatalog = preload("res://data/arena_catalog.tres")
const RANGED_COMPANION_SCENE: PackedScene = preload("res://companions/ranged_companion.tscn")
const COMPANION_SPAWN_LEFT: Vector2 = Vector2(-48, 24)
const COMPANION_SPAWN_RIGHT: Vector2 = Vector2(48, 24)
const REQUIRED_UPGRADE_IDS: PackedStringArray = [
	"max_hp_s", "max_hp_m", "swift", "heavy_round", "cadence",
	"long_shot", "second_skin", "extra_pellets", "steady_rifle", "thick_hide",
]
const GRANT_UPGRADE_ID: StringName = &"max_hp_s"
const MENU_SCENE := "res://ui/main_menu.tscn"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
## seat 2 别名；seat 3～5 禁止再用。
const GUEST_SPAWN := Vector2(80, 0)
const SEAT_SPAWNS: Array[Vector2] = [
	Vector2(0, 0), ## seat 1 场景 Player 原点
	GUEST_SPAWN, ## seat 2 现有 Guest
	Vector2(-80, 0), ## seat 3
	Vector2(0, 80), ## seat 4
	Vector2(0, -80), ## seat 5
]
const UPGRADE_SKIP_ID := "__skip__"
const OFFER_PHRASE: int = 0
const OFFER_LEVEL: int = 1
const OFFER_SHOP: int = 2
const SNAPSHOT_VERSION: int = 3

## 只有鼠标在窗口内且窗口有焦点时才藏系统光标，避免出窗后桌面丢指针。
var _mouse_inside_window: bool = true
var _enemies: Array[EnemyBase] = []
var _offer_is_phrase: bool = false
var _progress_written: bool = false
var _record_id: String = ""
var _god_mode: bool = false
var _leaving: bool = false
var _music_tween: Tween
var _reset_frame: int = -1
var _net_role: GameLaunch.NetRole = GameLaunch.NetRole.OFFLINE
var _lan_character_ids: PackedStringArray = PackedStringArray()
var _lan_peer_ids: PackedInt32Array = PackedInt32Array()
var _lan_loop_goal: int = 0
var _local_seat: int = 1
var _pawns: Array[Player] = []
var _synced_pawns: Array[Player] = []
var _local_player: Player
var _lan_paused: bool = false
var _last_owned_label: String = ""
var _companions: Array[CompanionBase] = []
var _shop_stim_bought: bool = false
var _started_as_lan: bool = false
var _arena_id: String = "yard"
var _net_play: GameLaunch.NetPlay = GameLaunch.NetPlay.COOP
var _battle_winner_seat: int = 0

@onready var _viewport_container: SubViewportContainer = $ViewportContainer
@onready var _game_viewport: SubViewport = $ViewportContainer/GameViewport
@onready var _floor: ArenaFloor = $ViewportContainer/GameViewport/World/Floor
@onready var _walls: Node2D = $ViewportContainer/GameViewport/World/Walls
@onready var _obstacles: Node2D = $ViewportContainer/GameViewport/World/Obstacles
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
@onready var _companions_root: Node2D = $ViewportContainer/GameViewport/World/Companions
@onready var _sfx_pool: SfxPool = $ViewportContainer/GameViewport/World/SfxPool
@onready var _combat_music: AudioStreamPlayer = $CombatMusic
@onready var _encounter: EncounterPhrases = $EncounterPhrases
@onready var _run_session: RunSession = $RunSession
@onready var _upgrade_applier: UpgradeApplier = $UpgradeApplier
@onready var _pause_overlay: PauseOverlay = $PauseOverlay
@onready var _players_root: Node2D = $ViewportContainer/GameViewport/World/Players
@onready var _net: NetSession = $NetSession
@onready var _room_notice: RoomNotice = $RoomNotice

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
	if _leaving:
		return
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
	if _is_battle():
		_resolve_battle_if_needed()
	else:
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
	if _leaving:
		return
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
	_combat_music.volume_db = SILENCE_DB
	_ensure_combat_music()
	UiAnim.kill_tween(_music_tween)
	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(_combat_music, "volume_db", COMBAT_MUSIC_DB, BGM_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _ensure_combat_music() -> void:
	if _combat_music.stream != null and not _combat_music.playing:
		_combat_music.play()

func _bind_runtime() -> void:
	_net_role = GameLaunch.take_net_role()
	_local_seat = GameLaunch.take_local_seat()
	var roster: Dictionary = GameLaunch.take_lan_roster()
	_lan_character_ids = roster.get("character_ids", PackedStringArray())
	_lan_peer_ids = roster.get("peer_ids", PackedInt32Array())
	_lan_loop_goal = int(roster.get("loop_goal", 0))
	_net_play = GameLaunch.take_net_play()
	_started_as_lan = _is_lan()
	if _is_lan():
		GameLaunch.take_join_address()
		if multiplayer.multiplayer_peer == null:
			_return_to_menu()
			return
	_net.configure(_net_role, self)
	_net.bind_roster(_local_seat, _lan_peer_ids)
	_net.peer_lost.connect(_on_peer_lost)
	_net.input_received.connect(_on_net_input)
	_net.snapshot_received.connect(_on_net_snapshot)
	_net.fire_fx_received.connect(_on_net_fire_fx)
	_net.offer_open_received.connect(_on_net_offer_open)
	_net.offer_close_received.connect(_on_net_offer_close)
	_net.winner_received.connect(_on_net_winner)
	_net.reset_received.connect(_reset_sandbox)
	_net.return_menu_received.connect(_on_net_return_menu)
	_room_notice.dismissed.connect(_on_room_notice_dismissed)
	_net.try_pick_received.connect(_on_net_try_pick)
	_net.try_unpause_received.connect(_on_net_try_unpause)
	_net.try_pause_received.connect(_on_net_try_pause)
	_net.shop_stock_received.connect(_on_net_shop_stock)
	_net.try_shop_received.connect(_on_net_try_shop)
	_prepare_pawns()
	var player_input: PlayerInput = _local_player.get_player_input()
	_projectiles.setup(_projectiles, PROJECTILE_SCENE, POOL_CAPACITY)
	_enemy_projectiles.setup(_enemy_projectiles, PROJECTILE_SCENE, ENEMY_POOL_CAPACITY)
	_hit_sparks.setup(_hit_sparks, HIT_SPARK_SCENE, HIT_SPARK_CAPACITY)
	_death_shards.setup(_death_shards, DEATH_SHARD_SCENE, DEATH_SHARD_CAPACITY)
	_bind_projectile_sparks(_projectiles)
	_bind_projectile_sparks(_enemy_projectiles)
	for pawn: Player in _pawns:
		if pawn == null:
			continue
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
	_bind_battle_hud()
	_bind_weapon_hit_players()
	_run_session.bind_players(_synced_pawns)
	_run_session.bind_encounter(_encounter)
	_run_session.bind_catalog(UPGRADE_CATALOG)
	_run_session.bind_companion_catalog(COMPANION_CATALOG)
	_run_session.bind_consumable_catalog(CONSUMABLE_CATALOG)
	_assert_upgrade_catalog()
	_bind_playable_record()
	_arena_id = GameLaunch.take_arena_id()
	if ARENA_CATALOG.get_by_id(StringName(_arena_id)) == null:
		_arena_id = "yard"
	_apply_arena(_arena_id)
	if _is_lan():
		_run_session.configure_mode(_lan_loop_goal)
	else:
		_run_session.configure_mode(_read_record_loop_goal())
	_apply_record_character()
	_run_session.restart()
	if _is_battle():
		_pause_battle_world()
	elif not _is_guest():
		_apply_loop_pressure()
		_encounter.restart()
	_upgrade_applier.bind_players(_synced_pawns)
	_upgrade_applier.bind_session(_run_session)
	_upgrade_applier.capture_baseline()
	_upgrade_applier.apply_owned()
	_upgrade_offer.bind_session(_run_session)
	_upgrade_offer.bind_player_input(player_input)
	_upgrade_offer.picked.connect(_on_upgrade_picked)
	_upgrade_offer.cancelled.connect(_on_pause_toggle)
	_shop_offer.bind_session(_run_session)
	_shop_offer.bind_player(_local_player)
	_shop_offer.bind_player_input(player_input)
	_shop_offer.bought.connect(_on_shop_bought)
	_shop_offer.picked_companion.connect(_on_shop_companion_picked)
	_shop_offer.picked_consumable.connect(_on_shop_consumable_picked)
	_shop_offer.skipped.connect(_on_shop_skipped)
	_shop_offer.cancelled.connect(_on_pause_toggle)
	_pause_overlay.bind_run_session(_run_session)
	_pause_overlay.bind_encounter(_encounter)
	_pause_overlay.resumed.connect(_on_pause_resumed)
	_pause_overlay.retried.connect(_on_pause_retried)
	_pause_overlay.quit_pressed.connect(_on_pause_quit)
	_winner_page.retry_pressed.connect(_on_winner_retry)
	_winner_page.menu_pressed.connect(_on_winner_menu)
	_debug_overlay.bind_run_session(_run_session)
	_debug_overlay.bind_upgrade_offer(_upgrade_offer)
	_debug_overlay.bind_shop_offer(_shop_offer)
	_debug_overlay.bind_winner_page(_winner_page)
	_debug_overlay.bind_record_id(_record_id)
	_debug_overlay.bind_arena_id(_arena_id)
	_debug_overlay.bind_net_session(_net)
	_debug_overlay.bind_p2(_pawn_for_seat(2))
	_debug_overlay.bind_p3(_pawn_for_seat(3))
	_debug_overlay.bind_seats(_occupied_seats(), _local_seat)
	_debug_overlay.bind_net_play(_net_play)
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
		enemy.bind_players(_synced_pawns)
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
	if UPGRADE_CATALOG.get_count() != 14:
		push_error("升级目录条目数应为 14，实际 %d" % UPGRADE_CATALOG.get_count())
	for upgrade_id: String in REQUIRED_UPGRADE_IDS:
		if UPGRADE_CATALOG.get_by_id(StringName(upgrade_id)) == null:
			push_error("升级目录缺少 id: %s" % upgrade_id)

func _hold_all_in_reserve() -> void:
	for enemy: EnemyBase in _enemies:
		enemy.hold_in_reserve()

func _loop_phrases() -> void:
	_park_combat_pools()
	_hold_all_in_reserve()
	_shop_offer.bind_companions(_companions)
	var cards: Array[ShopCard] = _draft_shop_cards_for_loop()
	if cards.is_empty():
		_finish_loop_after_shop()
		return
	_shop_stim_bought = false
	_set_combat_frozen(true)
	_shop_offer.present(cards, _run_session.get_gold(), false)
	_set_offer_input_lock(true)
	if _is_host():
		_broadcast_shop_stock(cards)

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
	if _pause_overlay.is_open():
		_pause_overlay.close(false)
	_set_offer_picks_enabled(true)
	if _upgrade_offer.is_open():
		_close_offer()
	if _shop_offer.is_open():
		_close_shop()
	_park_combat_pools()
	_apply_arena(_arena_id)
	_shop_stim_bought = false
	_clear_companion()
	_run_session.restart()
	_upgrade_applier.apply_owned()
	for pawn: Player in _pawns:
		if pawn == null:
			continue
		pawn.set_sim_paused(false)
		pawn.reset_for_sandbox()
	_hold_all_in_reserve()
	if _is_battle():
		_pause_battle_world()
	elif not _is_guest():
		_apply_loop_pressure()
		_encounter.restart()
	_debug_overlay.set_last_grant_id("-")
	_battle_winner_seat = 0
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
		_net.send_try_shop(NetSession.SHOP_KIND_UPGRADE, String(upgrade_id), 0)
		return
	_host_buy_upgrade(upgrade_id)

func _on_shop_companion_picked(companion_id: StringName, weapon_index: int) -> void:
	if _is_guest():
		_net.send_try_shop(NetSession.SHOP_KIND_COMPANION, String(companion_id), weapon_index)
		return
	_host_buy_companion(companion_id, weapon_index, _host_buyer())

func _on_shop_consumable_picked(consumable_id: StringName) -> void:
	if _is_guest():
		_net.send_try_shop(NetSession.SHOP_KIND_CONSUMABLE, String(consumable_id), 0)
		return
	_host_buy_consumable(consumable_id, _host_buyer())

func _host_buy_upgrade(upgrade_id: StringName) -> void:
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
	_refresh_open_shop()

func _host_buy_companion(companion_id: StringName, weapon_index: int, owner: Player) -> void:
	if not _shop_offer.is_open():
		return
	if _all_pawns_defeated() or not _run_session.is_playing():
		_abort_shop()
		return
	var def: CompanionDef = COMPANION_CATALOG.get_by_id(companion_id)
	if def == null:
		return
	_run_session.set_living_companion_count(_count_living_companions())
	if not _run_session.can_buy_companion():
		return
	var cost: int = def.shop_cost
	if _run_session.get_gold() < cost:
		return
	if not _run_session.try_spend(cost):
		push_error("商店扣款失败：companion=%s cost=%d gold=%d" % [String(companion_id), cost, _run_session.get_gold()])
		return
	_spawn_companion(companion_id, weapon_index, owner)
	_refresh_open_shop()

func _host_buy_consumable(consumable_id: StringName, buyer: Player) -> void:
	if not _shop_offer.is_open():
		return
	if _all_pawns_defeated() or not _run_session.is_playing():
		_abort_shop()
		return
	if buyer == null:
		return
	var def: ConsumableDef = CONSUMABLE_CATALOG.get_by_id(consumable_id)
	if def == null:
		return
	if not _can_buy_consumable(def, buyer):
		return
	var cost: int = def.shop_cost
	if _run_session.get_gold() < cost:
		return
	if not _run_session.try_spend(cost):
		push_error("商店扣款失败：consumable=%s cost=%d gold=%d" % [String(consumable_id), cost, _run_session.get_gold()])
		return
	_apply_consumable(def, buyer)
	_refresh_open_shop()

func _apply_consumable(def: ConsumableDef, buyer: Player = null) -> void:
	var pawn: Player = buyer if buyer != null else _host_buyer()
	if pawn == null:
		return
	var health: PlayerHealth = pawn.get_player_health()
	if def.kind == ConsumableDef.Kind.HEAL_FULL:
		health.fill_hp()
		_fill_companion_hp()
		return
	if def.kind == ConsumableDef.Kind.I_FRAME:
		health.apply_bonus_i_frame(def.value)
		_shop_stim_bought = true
		return
	health.heal(int(def.value))

func _refresh_open_shop() -> void:
	if not _shop_offer.is_open():
		return
	_run_session.set_living_companion_count(_count_living_companions())
	_shop_offer.bind_companions(_companions)
	var cards: Array[ShopCard] = _run_session.list_shop_catalog()
	_shop_offer.refresh_stock(cards, _shop_stim_bought)
	if _is_host():
		_broadcast_shop_stock(cards)

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
	_shop_stim_bought = false
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
			enemy.set_sim_paused(true if _is_battle() else frozen)
		_pause_companions(frozen)
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

func _set_offer_picks_enabled(enabled: bool) -> void:
	var mode: Node.ProcessMode = Node.PROCESS_MODE_ALWAYS if enabled else Node.PROCESS_MODE_DISABLED
	_upgrade_offer.process_mode = mode
	_shop_offer.process_mode = mode

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

func _apply_arena(id: String) -> void:
	_clear_obstacles()
	var def: ArenaDef = ARENA_CATALOG.get_by_id(StringName(id))
	if def == null:
		def = ARENA_CATALOG.get_by_id(&"yard")
	if def == null:
		return
	_floor.apply_palette(def.tile_color, def.grout_color)
	if def.layout_scene != null:
		var layout: Node = def.layout_scene.instantiate()
		_obstacles.add_child(layout)
	_apply_obstacle_layers(_obstacles)
	_debug_overlay.bind_arena_id(String(def.id))

func _clear_obstacles() -> void:
	var leftovers: Array[Node] = []
	for child: Node in _obstacles.get_children():
		leftovers.append(child)
	for child: Node in leftovers:
		_obstacles.remove_child(child)
		child.queue_free()

func _apply_obstacle_layers(root: Node) -> void:
	var body: StaticBody2D = root as StaticBody2D
	if body != null:
		body.collision_layer = GameCollisionLayers.MASK_WALL
		body.collision_mask = GameCollisionLayers.MASK_NONE
	for child: Node in root.get_children():
		_apply_obstacle_layers(child)

func _debug_cycle_arena() -> void:
	if _pause_overlay.is_open() or _winner_page.is_open() or _upgrade_offer.is_open() or _shop_offer.is_open():
		return
	var arenas: Array[ArenaDef] = ARENA_CATALOG.get_all()
	if arenas.is_empty():
		return
	var next_index: int = 0
	for i: int in arenas.size():
		if String(arenas[i].id) == _arena_id:
			next_index = (i + 1) % arenas.size()
			break
	_arena_id = String(arenas[next_index].id)
	if ARENA_CATALOG.get_by_id(StringName(_arena_id)) == null:
		_arena_id = "yard"
	_apply_arena(_arena_id)
	_host_reset_sandbox()

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
	if _winner_page.is_open() or _all_pawns_defeated() or _run_session.is_cleared():
		_return_to_menu()
		return
	if _upgrade_offer.is_open() or _shop_offer.is_open():
		_set_offer_picks_enabled(false)
		_pause_overlay.open(false)
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
	if _leaving:
		return
	_apply_render_scale()
	_set_offer_picks_enabled(true)
	if _upgrade_offer.is_open() or _shop_offer.is_open():
		_set_offer_input_lock(true)
		_set_combat_frozen(true)
		return
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
		for seat: int in range(1, GameLaunch.NET_MAX_SEATS + 1):
			var pawn: Player = _pawn_for_seat(seat)
			if pawn == null:
				continue
			var character_id: String = _character_id_for_seat(seat)
			_apply_character_id(pawn, character_id if not character_id.is_empty() else "boar")
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
	if _is_lan() or _started_as_lan:
		if _is_host() and _is_lan():
			_net.send_winner(
				_record_outcome(),
				_run_session.get_loop_index(),
				_run_session.get_kill_count(),
				_run_session.get_gold(),
				_run_session.get_elapsed_sec(),
				_battle_winner_seat if _is_battle() else 0
			)
		if _is_battle():
			_winner_page.present("", _run_session, 0, _battle_winner_seat, _net.get_local_seat(), true)
		else:
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
	if _leaving:
		return
	if not _winner_page.is_open():
		return
	if _is_guest():
		return
	_winner_page.close()
	_host_reset_sandbox()

func _on_winner_menu() -> void:
	_return_to_menu()

func _record_progress_if_needed() -> void:
	if _is_lan() or _started_as_lan:
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
	_clear_companion()
	if _is_host():
		_net.send_return_menu()
	_record_progress_if_needed()
	if _is_lan():
		_net.close_peer()
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	_combat_music.process_mode = Node.PROCESS_MODE_ALWAYS
	LOADING_SCREEN_SCRIPT.present_on(self, MENU_SCENE)
	UiAnim.kill_tween(_music_tween)
	_music_tween = create_tween()
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(_combat_music, "volume_db", SILENCE_DB, BGM_FADE_SEC).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	_music_tween.finished.connect(_finish_return_to_menu)

func _finish_return_to_menu() -> void:
	LOADING_SCREEN_SCRIPT.switch_current(get_tree())

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
	if key.physical_keycode == KEY_F7:
		get_viewport().set_input_as_handled()
		_debug_cycle_arena()
		return
	if key.physical_keycode == KEY_F8:
		get_viewport().set_input_as_handled()
		_debug_cycle_companion()
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

func _debug_cycle_companion() -> void:
	if _pause_overlay.is_open() or _winner_page.is_open() or _upgrade_offer.is_open() or _shop_offer.is_open():
		return
	if not _run_session.is_playing() or _run_session.is_cleared():
		return
	if _count_living_companions() < RunSession.COMPANION_CAP:
		_spawn_companion(&"gunner", 0)
		return
	var ranged: RangedCompanion = _last_living_ranged()
	if ranged == null:
		_spawn_companion(&"gunner", 0)
		return
	var next_index: int = ranged.get_weapon_index() + 1
	if next_index > 3:
		_clear_companion()
		return
	ranged.apply_weapon(next_index)

func _spawn_companion(companion_id: StringName, weapon_index: int, owner: Player = null) -> void:
	if _is_battle():
		return
	if _is_guest():
		return
	if _count_living_companions() >= RunSession.COMPANION_CAP:
		return
	var owner_pawn: Player = owner if owner != null else _player
	var def: CompanionDef = COMPANION_CATALOG.get_by_id(companion_id)
	if def == null:
		return
	var companion: CompanionBase = RANGED_COMPANION_SCENE.instantiate() as CompanionBase
	if companion == null:
		return
	_companions_root.add_child(companion)
	companion.apply_def(def)
	companion.global_position = _pick_companion_spawn(def.hurtbox_radius, _count_living_companions(), owner_pawn)
	companion.bind_owner(owner_pawn)
	companion.bind_enemies(_enemies)
	companion.bind_allies(_companions)
	companion.bind_sfx_pool(_sfx_pool)
	companion.bind_projectile_pool(_projectiles)
	var ranged: RangedCompanion = companion as RangedCompanion
	if ranged != null:
		ranged.apply_weapon(weapon_index)
		ranged.shot_fired.connect(_on_companion_shot_fired.bind(ranged))
	if _is_lan() and (_shop_offer.is_open() or _upgrade_offer.is_open() or _lan_paused):
		companion.set_sim_paused(true)
	_companions.append(companion)
	_reindex_companion_slots()
	_sync_companion_bindings()

func _pick_companion_spawn(radius: float, slot: int, owner: Player = null) -> Vector2:
	var origin_pawn: Player = owner if owner != null else _player
	var origin: Vector2 = origin_pawn.global_position if origin_pawn != null else Vector2.ZERO
	var aim: Vector2 = Vector2.LEFT
	if origin_pawn != null:
		var raw: Vector2 = origin_pawn.get_player_input().aim_vector
		if not raw.is_zero_approx():
			aim = raw.normalized()
	var pair: int = int(slot / 2)
	var side_sign: float = -1.0 if (slot % 2) == 1 else 1.0
	var back: float = 48.0 + float(pair) * 20.0
	var side: float = 24.0 + float(pair) * 16.0
	var pos: Vector2 = origin - aim * back + aim.orthogonal() * side * side_sign
	if _companion_spawn_hits_wall(pos, radius):
		return origin + COMPANION_SPAWN_RIGHT * side_sign
	return pos

func _companion_spawn_hits_wall(pos: Vector2, radius: float) -> bool:
	var world: World2D = _game_viewport.find_world_2d()
	if world == null:
		return false
	var space: PhysicsDirectSpaceState2D = world.direct_space_state
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.transform = Transform2D(0.0, pos)
	params.collision_mask = GameCollisionLayers.MASK_WALL
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return not space.intersect_shape(params, 1).is_empty()

func _clear_companion() -> void:
	for companion: CompanionBase in _companions:
		if companion != null and is_instance_valid(companion):
			companion.queue_free()
	_companions.clear()
	_sync_companion_bindings()

func _is_companion_alive() -> bool:
	return _count_living_companions() > 0

func _count_living_companions() -> int:
	var n: int = 0
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion) or companion.is_defeated():
			continue
		n += 1
	return n

func _last_living_ranged() -> RangedCompanion:
	var last: RangedCompanion = null
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion) or companion.is_defeated():
			continue
		last = companion as RangedCompanion
	return last

func _reindex_companion_slots() -> void:
	var slot: int = 0
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion) or companion.is_defeated():
			continue
		companion.set_slot_index(slot)
		slot += 1

func _sync_companion_bindings() -> void:
	if _run_session != null:
		_run_session.set_living_companion_count(_count_living_companions())
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion):
			continue
		companion.bind_allies(_companions)
	_debug_overlay.bind_companions(_companions)
	_shop_offer.bind_companions(_companions)

func _fill_companion_hp() -> void:
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion):
			continue
		companion.fill_hp()

func _draft_shop_cards_for_loop() -> Array[ShopCard]:
	_run_session.set_living_companion_count(_count_living_companions())
	return _run_session.list_shop_catalog()

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
	_synced_pawns.clear()
	var host_spawn: Vector2 = _spawn_for_seat(1)
	_player.global_position = host_spawn
	_player.set_spawn_position(host_spawn)
	if not _is_lan():
		_pawns.append(_player)
		_synced_pawns.append(_player)
		_local_player = _player
		_apply_pawn_drive(_player, false, true)
		return
	var max_seat: int = 1
	for seat: int in range(1, GameLaunch.NET_MAX_SEATS + 1):
		if _is_roster_seat_occupied(seat):
			max_seat = seat
	for _i: int in max_seat:
		_pawns.append(null)
	_pawns[0] = _player
	for seat: int in range(2, GameLaunch.NET_MAX_SEATS + 1):
		if not _is_roster_seat_occupied(seat):
			continue
		var spawn: Vector2 = _spawn_for_seat(seat)
		var guest: Player = PLAYER_SCENE.instantiate() as Player
		guest.name = "Player%d" % seat
		_players_root.add_child(guest)
		guest.global_position = spawn
		guest.set_spawn_position(spawn)
		_pawns[seat - 1] = guest
	_local_player = _pawn_for_seat(_local_seat)
	if _local_player == null:
		_local_player = _player
	for i: int in _pawns.size():
		var pawn: Player = _pawns[i]
		if pawn == null:
			continue
		var is_local: bool = pawn == _local_player
		if _is_host():
			_apply_pawn_drive(pawn, not is_local, true)
			continue
		_apply_pawn_drive(pawn, not is_local, false)
	_rebuild_synced_pawns()

func _is_lan() -> bool:
	return _net_role != GameLaunch.NetRole.OFFLINE

func _is_battle() -> bool:
	return _is_lan() and _net_play == GameLaunch.NetPlay.BATTLE

func _is_host() -> bool:
	return _net_role == GameLaunch.NetRole.HOST

func _is_guest() -> bool:
	return _net_role == GameLaunch.NetRole.GUEST

func _pause_battle_world() -> void:
	_hold_all_in_reserve()
	for enemy: EnemyBase in _enemies:
		enemy.set_sim_paused(true)

func _bind_weapon_hit_players() -> void:
	var hit_players: bool = _is_battle()
	for pawn: Player in _pawns:
		if pawn == null:
			continue
		for weapon: Weapon in pawn.get_weapon_host().get_weapons():
			weapon.bind_hit_players(hit_players)

func _bind_battle_hud() -> void:
	_hud.set_battle(_is_battle())
	_hud.bind_rival(_find_rival_pawn())
	_debug_overlay.bind_net_play(_net_play)

func _find_rival_pawn() -> Player:
	for pawn: Player in _pawns:
		if pawn != null and pawn != _local_player:
			return pawn
	return null

func _resolve_battle_if_needed() -> void:
	if not _is_battle() or not _is_host():
		return
	if _winner_page.is_open() or not _run_session.is_playing():
		return
	if _occupied_seat_count() != 2:
		return
	var first: Player = null
	var second: Player = null
	var first_seat: int = 0
	var second_seat: int = 0
	for i: int in _pawns.size():
		if _pawns[i] == null:
			continue
		if first == null:
			first = _pawns[i]
			first_seat = i + 1
			continue
		second = _pawns[i]
		second_seat = i + 1
	if first == null or second == null:
		return
	var first_dead: bool = first.is_defeated()
	var second_dead: bool = second.is_defeated()
	if not first_dead and not second_dead:
		return
	if first_dead and second_dead:
		_battle_winner_seat = 0
	elif first_dead:
		_battle_winner_seat = second_seat
	else:
		_battle_winner_seat = first_seat
	_run_session.mark_battle_over()

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
		enemy.set_sim_paused(true if _is_battle() else paused)
	_pause_companions(paused)
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
	buf.put_u8(_occupied_seat_count())
	for i: int in _pawns.size():
		var pawn: Player = _pawns[i]
		if pawn == null:
			continue
		var aim: Vector2 = pawn.get_player_input().aim_vector
		var health: PlayerHealth = pawn.get_player_health()
		buf.put_u8(i + 1)
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
	_write_companion_snapshot(buf)
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

func _on_net_input(seat: int, move: Vector2, aim: Vector2, fire: bool, dash: bool, weapon_slot: int) -> void:
	var pawn: Player = _pawn_for_seat(seat)
	if pawn == null:
		return
	pawn.get_player_input().apply_remote_frame(move, aim, fire, dash, weapon_slot)

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
	var seen: Dictionary = {}
	for _i: int in pawn_count:
		var seat: int = buf.get_u8()
		var pos := Vector2(buf.get_float(), buf.get_float())
		var vel := Vector2(buf.get_float(), buf.get_float())
		var aim := Vector2(buf.get_float(), buf.get_float())
		var hp: int = buf.get_u16()
		var max_hp: int = buf.get_u16()
		var defeated: bool = buf.get_u8() != 0
		var weapon_index: int = buf.get_u8()
		var facing_flip: bool = buf.get_u8() != 0
		seen[seat] = true
		var pawn: Player = _ensure_guest_pawn(seat)
		if pawn == null:
			continue
		var local_aim: bool = pawn != _local_player
		pawn.apply_net_pose(pos, vel, aim, hp, max_hp, defeated, weapon_index, facing_flip, local_aim)
	_free_unseen_guest_pawns(seen)
	var enemy_count: int = buf.get_u8()
	for _i: int in enemy_count:
		var index: int = buf.get_u8()
		var flags: int = buf.get_u8()
		var pos := Vector2(buf.get_float(), buf.get_float())
		var hp: int = buf.get_u16()
		if index < 0 or index >= _enemies.size():
			continue
		_enemies[index].apply_net_state(pos, hp, (flags & 2) != 0, (flags & 1) != 0)
	_read_companion_snapshot(buf)
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
	if not _is_battle() and (_run_session.is_player_dead() or _run_session.is_cleared()):
		_show_winner_if_needed()

func _on_net_fire_fx(seat: int, origin: Vector2, direction: Vector2, weapon_index: int) -> void:
	if seat >= NetSession.COMPANION_FIRE_SEAT_BASE:
		_play_companion_fire_fx(seat - NetSession.COMPANION_FIRE_SEAT_BASE, origin, direction, weapon_index)
		return
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
	if kind == OFFER_SHOP:
		return
	var defs: Array[UpgradeDef] = _defs_from_ids(id0, id1, id2)
	if defs.is_empty():
		return
	_set_combat_frozen(true)
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

func _on_net_winner(outcome: String, loop_index: int, kills: int, gold: int, time_sec: float, winner_seat: int = 0) -> void:
	if not _is_guest():
		return
	var outcome_code: int = int(RunSession.Outcome.DEAD)
	if outcome == "cleared":
		outcome_code = int(RunSession.Outcome.CLEARED)
	_battle_winner_seat = winner_seat
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

func _on_peer_lost(peer_id: int) -> void:
	if _leaving:
		return
	if _is_guest():
		_present_host_closed()
		return
	if not _is_host():
		return
	var seat: int = _net.seat_for_peer(peer_id)
	_net.release_peer(peer_id)
	if not _net.has_remote_seats():
		_convert_lan_host_to_solo()
		return
	_remove_seat_pawn(seat)
	_rebind_after_pawn_change()

func _on_pawn_shot_fired(aim: Vector2, _weapon: Weapon, pawn: Player) -> void:
	if not _is_host() or pawn == null:
		return
	var seat: int = _seat_for_owner(pawn)
	if seat < 1 or seat > GameLaunch.NET_MAX_SEATS:
		return
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

## 座位 clamp 1～5，取 SEAT_SPAWNS；1/2 仍是 (0,0)/(80,0)。
func _spawn_for_seat(seat: int) -> Vector2:
	var index: int = clampi(seat, 1, 5) - 1
	return SEAT_SPAWNS[index]

func _pawn_for_seat(seat: int) -> Player:
	if seat < 1 or seat > GameLaunch.NET_MAX_SEATS:
		return null
	var index: int = seat - 1
	if index < 0 or index >= _pawns.size():
		return null
	return _pawns[index]

func _host_buyer() -> Player:
	var pawn: Player = _pawn_for_seat(1)
	if pawn != null:
		return pawn
	return _player

func _seat_for_owner(owner: Player) -> int:
	if owner == null:
		return 0
	for i: int in _pawns.size():
		if _pawns[i] == owner:
			return i + 1
	return 0

func _pause_companions(paused: bool) -> void:
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion):
			continue
		companion.set_sim_paused(paused)

func _can_buy_consumable(def: ConsumableDef, buyer: Player) -> bool:
	if def.id == ShopOffer.STIM_ID and _shop_stim_bought:
		return false
	if def.kind == ConsumableDef.Kind.HEAL_FLAT and _is_pawn_full_hp(buyer):
		return false
	if def.kind == ConsumableDef.Kind.HEAL_FULL and _is_pawn_full_hp(buyer) and _are_living_companions_full_hp():
		return false
	return true

func _is_pawn_full_hp(pawn: Player) -> bool:
	if pawn == null:
		return false
	var health: PlayerHealth = pawn.get_player_health()
	return health.get_hp() >= health.get_max_hp()

func _are_living_companions_full_hp() -> bool:
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion) or companion.is_defeated():
			continue
		if companion.get_hp() < companion.get_max_hp():
			return false
	return true

func _broadcast_shop_stock(cards: Array[ShopCard]) -> void:
	if not _is_host():
		return
	_net.send_shop_stock(_encode_shop_stock(cards), _run_session.get_gold(), _shop_stim_bought)

func _encode_shop_stock(cards: Array[ShopCard]) -> PackedByteArray:
	var packed: Array[ShopCard] = []
	for card: ShopCard in cards:
		if _shop_card_net_id(card).is_empty():
			continue
		packed.append(card)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_u8(mini(packed.size(), 255))
	for card: ShopCard in packed:
		buf.put_u8(_shop_card_net_kind(card))
		buf.put_utf8_string(_shop_card_net_id(card))
	return buf.data_array

func _decode_shop_stock(data: PackedByteArray) -> Array[ShopCard]:
	var cards: Array[ShopCard] = []
	if data.is_empty():
		return cards
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(0)
	var n: int = buf.get_u8()
	for _i: int in n:
		var kind: int = buf.get_u8()
		var item_id: String = buf.get_utf8_string()
		var card: ShopCard = _shop_card_from_net(kind, item_id)
		if card != null:
			cards.append(card)
	return cards

func _shop_card_net_kind(card: ShopCard) -> int:
	if card.kind == ShopCard.Kind.CONSUMABLE:
		return NetSession.SHOP_KIND_CONSUMABLE
	if card.kind == ShopCard.Kind.COMPANION:
		return NetSession.SHOP_KIND_COMPANION
	return NetSession.SHOP_KIND_UPGRADE

func _shop_card_net_id(card: ShopCard) -> String:
	if card == null:
		return ""
	if card.kind == ShopCard.Kind.CONSUMABLE:
		if card.consumable == null:
			return ""
		return String(card.consumable.id)
	if card.kind == ShopCard.Kind.COMPANION:
		if card.companion == null:
			return ""
		return String(card.companion.id)
	if card.upgrade == null:
		return ""
	return String(card.upgrade.id)

func _shop_card_from_net(kind: int, item_id: String) -> ShopCard:
	if kind == NetSession.SHOP_KIND_CONSUMABLE:
		var consumable: ConsumableDef = CONSUMABLE_CATALOG.get_by_id(StringName(item_id))
		if consumable == null:
			return null
		return ShopCard.for_consumable(consumable)
	if kind == NetSession.SHOP_KIND_COMPANION:
		var companion: CompanionDef = COMPANION_CATALOG.get_by_id(StringName(item_id))
		if companion == null:
			return null
		return ShopCard.for_companion(companion)
	var upgrade: UpgradeDef = UPGRADE_CATALOG.get_by_id(StringName(item_id))
	if upgrade == null:
		return null
	return ShopCard.for_upgrade(upgrade)

func _on_net_shop_stock(data: PackedByteArray, gold: int, stim_bought: bool) -> void:
	if not _is_guest():
		return
	var cards: Array[ShopCard] = _decode_shop_stock(data)
	_shop_stim_bought = stim_bought
	_apply_guest_shop_gold(gold)
	if not _shop_offer.is_open():
		if cards.is_empty():
			return
		_set_combat_frozen(true)
		_shop_offer.present(cards, gold, stim_bought)
		_set_offer_input_lock(true)
		return
	_shop_offer.refresh_stock(cards, stim_bought)

func _on_net_try_shop(seat: int, kind: int, item_id: String, extra: int) -> void:
	if not _is_host():
		return
	if not _shop_offer.is_open():
		return
	if _all_pawns_defeated() or not _run_session.is_playing():
		_abort_shop()
		return
	var buyer: Player = _pawn_for_seat(seat)
	if buyer == null:
		return
	if kind == NetSession.SHOP_KIND_UPGRADE:
		_host_buy_upgrade(StringName(item_id))
		return
	if kind == NetSession.SHOP_KIND_CONSUMABLE:
		_host_buy_consumable(StringName(item_id), buyer)
		return
	if kind == NetSession.SHOP_KIND_COMPANION:
		_host_buy_companion(StringName(item_id), extra, buyer)

func _on_companion_shot_fired(origin: Vector2, direction: Vector2, weapon_index: int, companion: RangedCompanion) -> void:
	if not _is_host() or companion == null:
		return
	var slot: int = _companions.find(companion)
	if slot < 0:
		return
	_net.send_fire_fx(NetSession.COMPANION_FIRE_SEAT_BASE + slot, origin, direction, weapon_index)

func _play_companion_fire_fx(slot: int, origin: Vector2, direction: Vector2, weapon_index: int) -> void:
	if slot < 0 or slot >= _companions.size():
		return
	var ranged: RangedCompanion = _companions[slot] as RangedCompanion
	if ranged == null:
		return
	var weapon: Weapon = ranged.get_weapon_at(weapon_index)
	if weapon == null:
		return
	weapon.spawn_fx_shot(origin, direction)

func _write_companion_snapshot(buf: StreamPeerBuffer) -> void:
	var companion_count: int = mini(_companions.size(), RunSession.COMPANION_CAP)
	buf.put_u8(companion_count)
	for i: int in companion_count:
		var companion: CompanionBase = _companions[i]
		var flags: int = 0
		if companion != null and companion.is_defeated():
			flags |= 1
		var owner_seat: int = 1
		var weapon_index: int = 0
		var pos: Vector2 = Vector2.ZERO
		var aim: Vector2 = Vector2.RIGHT
		var hp: int = 0
		var max_hp: int = 1
		if companion != null:
			owner_seat = _seat_for_owner(companion.get_owner_player())
			pos = companion.global_position
			aim = companion.get_aim_vector()
			hp = companion.get_hp()
			max_hp = companion.get_max_hp()
			var ranged: RangedCompanion = companion as RangedCompanion
			if ranged != null:
				weapon_index = ranged.get_weapon_index()
		buf.put_u8(i)
		buf.put_u8(owner_seat)
		buf.put_u8(clampi(weapon_index, 0, 3))
		buf.put_u8(flags)
		buf.put_float(pos.x)
		buf.put_float(pos.y)
		buf.put_float(aim.x)
		buf.put_float(aim.y)
		buf.put_u16(clampi(hp, 0, 65535))
		buf.put_u16(clampi(max_hp, 0, 65535))

func _read_companion_snapshot(buf: StreamPeerBuffer) -> void:
	var companion_count: int = buf.get_u8()
	_align_companion_puppets(companion_count)
	for _c: int in companion_count:
		var slot: int = buf.get_u8()
		var owner_seat: int = buf.get_u8()
		var weapon_index: int = buf.get_u8()
		var flags: int = buf.get_u8()
		var cpos := Vector2(buf.get_float(), buf.get_float())
		var caim := Vector2(buf.get_float(), buf.get_float())
		var chp: int = buf.get_u16()
		var cmax: int = buf.get_u16()
		if slot < 0 or slot >= _companions.size():
			continue
		var companion: CompanionBase = _companions[slot]
		if companion == null or not is_instance_valid(companion):
			continue
		companion.apply_net_pose(cpos, chp, cmax, (flags & 1) != 0, weapon_index, caim, _pawn_for_seat(owner_seat))
	_sync_companion_bindings()

func _apply_guest_shop_gold(gold: int) -> void:
	_run_session.apply_net_session(
		_run_session.get_loop_index(),
		gold,
		_run_session.get_kill_count(),
		_run_session.get_xp(),
		_run_session.get_level(),
		_run_session.get_pending_level_count(),
		int(_run_session.get_outcome()),
		_run_session.get_elapsed_sec(),
		_run_session.get_owned_upgrade_ids()
	)

func _align_companion_puppets(count: int) -> void:
	var wanted: int = clampi(count, 0, RunSession.COMPANION_CAP)
	while _companions.size() > wanted:
		var extra: CompanionBase = _companions.pop_back()
		if extra != null and is_instance_valid(extra):
			extra.queue_free()
	while _companions.size() < wanted:
		var before: int = _companions.size()
		_spawn_companion_puppet()
		if _companions.size() <= before:
			break

func _spawn_companion_puppet() -> void:
	var def: CompanionDef = COMPANION_CATALOG.get_by_id(&"gunner")
	var companion: CompanionBase = RANGED_COMPANION_SCENE.instantiate() as CompanionBase
	if companion == null:
		return
	_companions_root.add_child(companion)
	if def != null:
		companion.apply_def(def)
	companion.set_remote_puppet(true)
	companion.bind_projectile_pool(_projectiles)
	_companions.append(companion)

func _on_net_return_menu() -> void:
	if _is_guest():
		_present_host_closed()
		return
	_return_to_menu()

func _present_host_closed() -> void:
	if _leaving:
		return
	if _room_notice.is_modal_open():
		return
	_pause_overlay.show_top_bar()
	_room_notice.present_modal(RoomNotice.TEXT_HOST_CLOSED)

func _on_room_notice_dismissed() -> void:
	_pause_overlay.hide_top_bar()
	_return_to_menu()

func _convert_lan_host_to_solo() -> void:
	if not _is_host() or _leaving:
		return
	_net.close_peer()
	_net_role = GameLaunch.NetRole.OFFLINE
	_lan_paused = false
	_remove_remote_pawns()
	_player.set_simulate_combat(true)
	_player.get_player_input().set_remote_driven(false)
	_player.set_sim_paused(false)
	for enemy: EnemyBase in _enemies:
		enemy.bind_players(_synced_pawns)
		enemy.set_sim_paused(false)
	_pause_companions(false)
	_run_session.bind_players(_synced_pawns)
	_upgrade_applier.bind_players(_synced_pawns)
	_shop_offer.bind_player(_player)
	_debug_overlay.bind_p2(null)
	_debug_overlay.bind_p3(null)
	_debug_overlay.bind_seats(_occupied_seats(), _local_seat)
	_debug_overlay.bind_net_session(_net)
	_debug_overlay.bind_net_play(_net_play)
	_bind_weapon_hit_players()
	_bind_battle_hud()
	if _pause_overlay.is_open():
		_pause_overlay.adopt_tree_pause()
	elif _upgrade_offer.is_open() or _shop_offer.is_open():
		_set_combat_frozen(true)
	_room_notice.present_toast(RoomNotice.TEXT_GUEST_LEFT)

func _remove_remote_pawns() -> void:
	for seat: int in range(2, GameLaunch.NET_MAX_SEATS + 1):
		_remove_seat_pawn(seat)
	_pawns.clear()
	_pawns.append(_player)
	_synced_pawns.clear()
	_synced_pawns.append(_player)
	_local_player = _player
	_local_seat = 1
	_sync_companion_bindings()

func _apply_pawn_drive(pawn: Player, remote_driven: bool, simulate_combat: bool) -> void:
	pawn.get_player_input().set_remote_driven(remote_driven)
	pawn.set_simulate_combat(simulate_combat)

func _is_roster_seat_occupied(seat: int) -> bool:
	if seat < 1 or seat > GameLaunch.NET_MAX_SEATS:
		return false
	if seat - 1 >= _lan_character_ids.size():
		return false
	return not str(_lan_character_ids[seat - 1]).is_empty()

func _character_id_for_seat(seat: int) -> String:
	if seat < 1 or seat - 1 >= _lan_character_ids.size():
		return ""
	return str(_lan_character_ids[seat - 1])

func _rebuild_synced_pawns() -> void:
	_synced_pawns.clear()
	for pawn: Player in _pawns:
		if pawn != null:
			_synced_pawns.append(pawn)

func _occupied_seat_count() -> int:
	var n: int = 0
	for pawn: Player in _pawns:
		if pawn != null:
			n += 1
	return n

func _occupied_seats() -> PackedInt32Array:
	var seats: PackedInt32Array = PackedInt32Array()
	for i: int in _pawns.size():
		if _pawns[i] != null:
			seats.append(i + 1)
	return seats

func _ensure_pawn_slot(seat: int) -> void:
	while _pawns.size() < seat:
		_pawns.append(null)

func _ensure_guest_pawn(seat: int) -> Player:
	if seat < 1 or seat > GameLaunch.NET_MAX_SEATS:
		return null
	_ensure_pawn_slot(seat)
	if _pawns[seat - 1] != null:
		return _pawns[seat - 1]
	if seat == 1:
		_pawns[0] = _player
		_apply_pawn_drive(_player, _player != _local_player, false)
		_rebuild_synced_pawns()
		return _player
	var pawn: Player = PLAYER_SCENE.instantiate() as Player
	pawn.name = "Player%d" % seat
	_players_root.add_child(pawn)
	var spawn: Vector2 = _spawn_for_seat(seat)
	pawn.global_position = spawn
	pawn.set_spawn_position(spawn)
	pawn.bind_projectile_pool(_projectiles)
	pawn.bind_sfx_pool(_sfx_pool)
	_apply_character_id(pawn, _character_id_for_seat(seat) if not _character_id_for_seat(seat).is_empty() else "boar")
	_apply_pawn_drive(pawn, pawn != _local_player, false)
	_pawns[seat - 1] = pawn
	_rebuild_synced_pawns()
	_rebind_after_pawn_change()
	return pawn

func _free_unseen_guest_pawns(seen: Dictionary) -> void:
	var removed: bool = false
	for i: int in range(_pawns.size() - 1, -1, -1):
		var pawn: Player = _pawns[i]
		if pawn == null:
			continue
		var seat: int = i + 1
		if seen.has(seat):
			continue
		if seat == 1:
			continue
		_remove_seat_pawn(seat)
		removed = true
	_rebuild_synced_pawns()
	if removed:
		_rebind_after_pawn_change()

func _drop_synced_pawn(pawn: Player) -> void:
	for i: int in _synced_pawns.size():
		if _synced_pawns[i] == pawn:
			_synced_pawns[i] = null
			return

func _remove_seat_pawn(seat: int) -> void:
	if seat < 2 or seat > GameLaunch.NET_MAX_SEATS:
		return
	var pawn: Player = _pawn_for_seat(seat)
	if pawn == null:
		return
	var host_pawn: Player = _pawn_for_seat(1)
	if host_pawn == null:
		host_pawn = _player
	for companion: CompanionBase in _companions:
		if companion == null or not is_instance_valid(companion):
			continue
		if companion.get_owner_player() == pawn:
			companion.bind_owner(host_pawn)
	_drop_synced_pawn(pawn)
	_pawns[seat - 1] = null
	if _local_player == pawn:
		_local_player = _player
	if is_instance_valid(pawn):
		pawn.queue_free()
	while _pawns.size() > 1 and _pawns[_pawns.size() - 1] == null:
		_pawns.pop_back()
	_sync_companion_bindings()

func _rebind_after_pawn_change() -> void:
	_bind_enemies(_enemies)
	_run_session.bind_players(_synced_pawns)
	_upgrade_applier.bind_players(_synced_pawns)
	if _local_player != null:
		_shop_offer.bind_player(_local_player)
		_hud.bind_player(_local_player)
		_hud.bind_weapon_host(_local_player.get_weapon_host())
	_bind_weapon_hit_players()
	_bind_battle_hud()
	_debug_overlay.bind_p2(_pawn_for_seat(2))
	_debug_overlay.bind_p3(_pawn_for_seat(3))
	_debug_overlay.bind_seats(_occupied_seats(), _local_seat)
	_debug_overlay.bind_net_session(_net)
	_debug_overlay.bind_net_play(_net_play)
