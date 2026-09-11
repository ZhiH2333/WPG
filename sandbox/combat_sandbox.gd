extends Node2D
class_name CombatSandbox

const PROJECTILE_SCENE: PackedScene = preload("res://weapons/projectile.tscn")
const POOL_CAPACITY: int = 96
const ENEMY_POOL_CAPACITY: int = 64
const UPGRADE_CATALOG: UpgradeCatalog = preload("res://data/upgrade_catalog.tres")
const REQUIRED_UPGRADE_IDS: PackedStringArray = [
	"max_hp_s", "max_hp_m", "swift", "heavy_round", "cadence",
	"long_shot", "second_skin", "extra_pellets", "steady_rifle", "thick_hide",
]
const GRANT_UPGRADE_ID: StringName = &"max_hp_s"
const MENU_SCENE := "res://ui/main_menu.tscn"

## 只有鼠标在窗口内且窗口有焦点时才藏系统光标，避免出窗后桌面丢指针。
var _mouse_inside_window: bool = true
var _enemies: Array[EnemyBase] = []
var _offer_is_phrase: bool = false
var _progress_written: bool = false

@onready var _walls: Node2D = $Walls
@onready var _player: Player = $Player
@onready var _player_camera: PlayerCamera = $PlayerCamera
@onready var _aim_reticle: AimReticle = $AimReticle
@onready var _debug_overlay: DebugOverlay = $DebugOverlay
@onready var _hud: Hud = $Hud
@onready var _upgrade_offer: UpgradeOffer = $UpgradeOffer
@onready var _shop_offer: ShopOffer = $ShopOffer
@onready var _run_summary: RunSummary = $RunSummary
@onready var _projectiles: ProjectilePool = $Projectiles
@onready var _enemy_projectiles: ProjectilePool = $EnemyProjectiles
@onready var _enemies_root: Node2D = $Enemies
@onready var _sfx_pool: SfxPool = $SfxPool
@onready var _encounter: EncounterPhrases = $EncounterPhrases
@onready var _run_session: RunSession = $RunSession
@onready var _upgrade_applier: UpgradeApplier = $UpgradeApplier
@onready var _pause_overlay: PauseOverlay = $PauseOverlay

func _ready() -> void:
	GameSettings.load_from_disk()
	GameSettings.apply()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_apply_wall_layers()
	_bind_runtime()
	_bind_window_cursor()
	_sync_system_cursor()

	var gamepad_debug: Node = preload("res://debug/test_gamepad.gd").new()
	add_child(gamepad_debug)

func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if _pause_overlay.is_open():
		return
	if _run_session.is_playing() and not _upgrade_offer.is_open() and not _shop_offer.is_open() and not _encounter.is_awaiting_offer() and not _run_session.has_pending_level():
		_encounter.tick(delta)
	if _run_session.is_playing() and _encounter.is_awaiting_offer() and not _upgrade_offer.is_open() and not _shop_offer.is_open():
		_open_offer_if_needed()
	elif _run_session.is_playing() and _run_session.has_pending_level() and not _upgrade_offer.is_open() and not _shop_offer.is_open() and not _encounter.is_awaiting_offer() and not _player.is_defeated():
		_open_level_offer_if_needed()
	if _upgrade_offer.is_open() and _player.is_defeated():
		_abort_offer()
	if _shop_offer.is_open() and _player.is_defeated():
		_abort_shop()
	if _run_session.is_playing() and not _player.is_defeated() and _encounter.is_done() and not _upgrade_offer.is_open() and not _shop_offer.is_open() and not _run_session.has_pending_level():
		_loop_phrases()
	_run_session.tick(delta)
	if _run_session.is_player_dead():
		_record_progress_if_needed()

func _unhandled_input(event: InputEvent) -> void:
	if _is_pause_toggle(event):
		get_viewport().set_input_as_handled()
		_on_pause_toggle()
		return
	if event.is_action_pressed("sandbox_reset"):
		if _pause_overlay.is_open():
			return
		_reset_sandbox()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("debug_grant_upgrade"):
		if _pause_overlay.is_open():
			return
		_try_debug_grant()
		get_viewport().set_input_as_handled()

func _bind_runtime() -> void:
	var player_input: PlayerInput = _player.get_player_input()
	_projectiles.setup(_projectiles, PROJECTILE_SCENE, POOL_CAPACITY)
	_enemy_projectiles.setup(_enemy_projectiles, PROJECTILE_SCENE, ENEMY_POOL_CAPACITY)
	_player.bind_projectile_pool(_projectiles)
	_player.bind_sfx_pool(_sfx_pool)
	_player.bind_player_camera(_player_camera)
	_player_camera.bind_player(_player)
	_aim_reticle.bind_player_input(player_input)
	_debug_overlay.bind_player(_player)
	_debug_overlay.bind_player_camera(_player_camera)
	_debug_overlay.bind_weapon_host(_player.get_weapon_host())
	_debug_overlay.bind_projectile_pool(_projectiles)
	_debug_overlay.bind_enemy_projectile_pool(_enemy_projectiles)
	_enemies = _collect_enemies()
	_bind_enemies(_enemies)
	_encounter.bind_enemies(_enemies)
	_encounter.bind_run_session(_run_session)
	_hold_all_in_reserve()
	_debug_overlay.bind_enemies(_enemies)
	_debug_overlay.bind_encounter(_encounter)
	_hud.bind_player(_player)
	_hud.bind_weapon_host(_player.get_weapon_host())
	_hud.bind_encounter(_encounter)
	_hud.bind_run_session(_run_session)
	_run_session.bind_player(_player)
	_run_session.bind_encounter(_encounter)
	_run_session.bind_catalog(UPGRADE_CATALOG)
	_assert_upgrade_catalog()
	_run_session.restart()
	_apply_loop_pressure()
	_encounter.restart()
	_upgrade_applier.bind_player(_player)
	_upgrade_applier.bind_session(_run_session)
	_upgrade_applier.capture_baseline()
	_upgrade_applier.apply_owned()
	_upgrade_offer.bind_session(_run_session)
	_upgrade_offer.bind_player_input(player_input)
	_upgrade_offer.picked.connect(_on_upgrade_picked)
	_shop_offer.bind_session(_run_session)
	_shop_offer.bind_player_input(player_input)
	_shop_offer.bought.connect(_on_shop_bought)
	_shop_offer.skipped.connect(_on_shop_skipped)
	_pause_overlay.bind_run_session(_run_session)
	_pause_overlay.resumed.connect(_on_pause_resumed)
	_pause_overlay.retried.connect(_on_pause_retried)
	_pause_overlay.quit_pressed.connect(_on_pause_quit)
	_run_summary.bind_run_session(_run_session)
	_debug_overlay.bind_run_session(_run_session)
	_debug_overlay.bind_upgrade_offer(_upgrade_offer)
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
		enemy.bind_player(_player)
		enemy.bind_sfx_pool(_sfx_pool)
		enemy.bind_player_camera(_player_camera)
		if not enemy.defeated.is_connected(_on_enemy_defeated):
			enemy.defeated.connect(_on_enemy_defeated.bind(enemy))
		var ranged: RangedEnemy = enemy as RangedEnemy
		if ranged != null:
			ranged.bind_projectile_pool(_enemy_projectiles)

func _on_enemy_defeated(enemy: EnemyBase) -> void:
	if not _run_session.is_playing() or _player.is_defeated():
		return
	_run_session.note_kill()
	var reward: int = enemy.get_xp_reward()
	if reward > 0:
		_run_session.add_xp(reward)
	_run_session.add_gold(enemy.get_gold_reward())

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
	_projectiles.park_all()
	_enemy_projectiles.park_all()
	_hold_all_in_reserve()
	var defs: Array[UpgradeDef] = _run_session.draft_offer(3)
	if defs.is_empty():
		_finish_loop_after_shop()
		return
	_shop_offer.present(defs, _run_session.get_gold())
	_set_offer_input_lock(true)

func _finish_loop_after_shop() -> void:
	_run_session.notify_phrase_loop()
	_apply_loop_pressure()
	_encounter.restart()

func _apply_loop_pressure() -> void:
	var loop_index: int = _run_session.get_loop_index()
	for enemy: EnemyBase in _enemies:
		enemy.apply_loop_pressure(loop_index)

func _reset_sandbox() -> void:
	if _upgrade_offer.is_open():
		_close_offer()
	if _shop_offer.is_open():
		_close_shop()
	_projectiles.park_all()
	_enemy_projectiles.park_all()
	_run_session.restart()
	_upgrade_applier.apply_owned()
	_player.reset_for_sandbox()
	_hold_all_in_reserve()
	_apply_loop_pressure()
	_encounter.restart()
	_debug_overlay.set_last_grant_id("-")
	_progress_written = false

func _try_debug_grant() -> void:
	if _upgrade_offer.is_open() or _shop_offer.is_open() or _pause_overlay.is_open():
		return
	if _player.is_defeated():
		return
	if not _run_session.try_grant(GRANT_UPGRADE_ID):
		return
	_upgrade_applier.apply_owned()
	_debug_overlay.set_last_grant_id(String(GRANT_UPGRADE_ID))

func _open_offer_if_needed() -> void:
	if not _run_session.is_playing() or _player.is_defeated():
		return
	_offer_is_phrase = true
	var defs: Array[UpgradeDef] = _run_session.draft_offer(3)
	if defs.is_empty():
		_encounter.acknowledge_offer()
		return
	_upgrade_offer.present(defs)
	_set_offer_input_lock(true)

func _open_level_offer_if_needed() -> void:
	if not _run_session.is_playing() or _player.is_defeated():
		return
	_offer_is_phrase = false
	var defs: Array[UpgradeDef] = _run_session.draft_offer(3)
	if defs.is_empty():
		_run_session.consume_pending_level()
		return
	_upgrade_offer.present(defs)
	_set_offer_input_lock(true)

func _on_upgrade_picked(upgrade_id: StringName) -> void:
	if not _upgrade_offer.is_open():
		return
	if _player.is_defeated() or not _run_session.is_playing():
		_abort_offer()
		return
	if not _run_session.try_grant(upgrade_id):
		return
	_upgrade_applier.apply_owned()
	_debug_overlay.set_last_grant_id(String(upgrade_id))
	var was_phrase: bool = _offer_is_phrase
	_close_offer()
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

func _on_shop_bought(upgrade_id: StringName) -> void:
	if not _shop_offer.is_open():
		return
	if _player.is_defeated() or not _run_session.is_playing():
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
	_finish_loop_after_shop()

func _on_shop_skipped() -> void:
	if not _shop_offer.is_open():
		return
	_close_shop()
	if _player.is_defeated() or not _run_session.is_playing():
		return
	_finish_loop_after_shop()

func _abort_shop() -> void:
	_close_shop()

func _close_shop() -> void:
	_shop_offer.close()
	_set_offer_input_lock(false)

func _set_offer_input_lock(locked: bool) -> void:
	_player.get_player_input().set_fire_suppressed(locked)
	_player.get_weapon_host().set_switch_suppressed(locked)
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
	_mouse_inside_window = true

func _on_window_mouse_entered() -> void:
	_mouse_inside_window = true
	_sync_system_cursor()

func _on_window_mouse_exited() -> void:
	_mouse_inside_window = false
	_sync_system_cursor()

func _sync_system_cursor() -> void:
	if _upgrade_offer.is_open() or _shop_offer.is_open() or _pause_overlay.is_open():
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
	if _player.is_defeated() or _upgrade_offer.is_open() or _shop_offer.is_open():
		_return_to_menu()
		return
	_set_offer_input_lock(true)
	_pause_overlay.open()

func _on_pause_resumed() -> void:
	_set_offer_input_lock(false)

func _on_pause_retried() -> void:
	_reset_sandbox()
	_pause_overlay.close()

func _on_pause_quit() -> void:
	_return_to_menu()

func _record_progress_if_needed() -> void:
	if _progress_written:
		return
	GameProgress.record_run(_run_session)
	_progress_written = true

func _return_to_menu() -> void:
	_record_progress_if_needed()
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
