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

## 只有鼠标在窗口内且窗口有焦点时才藏系统光标，避免出窗后桌面丢指针。
var _mouse_inside_window: bool = true
var _enemies: Array[EnemyBase] = []

@onready var _walls: Node2D = $Walls
@onready var _player: Player = $Player
@onready var _player_camera: PlayerCamera = $PlayerCamera
@onready var _aim_reticle: AimReticle = $AimReticle
@onready var _debug_overlay: DebugOverlay = $DebugOverlay
@onready var _hud: Hud = $Hud
@onready var _projectiles: ProjectilePool = $Projectiles
@onready var _enemy_projectiles: ProjectilePool = $EnemyProjectiles
@onready var _enemies_root: Node2D = $Enemies
@onready var _sfx_pool: SfxPool = $SfxPool
@onready var _encounter: EncounterPhrases = $EncounterPhrases
@onready var _run_session: RunSession = $RunSession
@onready var _upgrade_applier: UpgradeApplier = $UpgradeApplier

func _ready() -> void:
	_apply_wall_layers()
	_bind_runtime()
	_bind_window_cursor()
	_sync_system_cursor()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if _run_session.is_playing():
		_encounter.tick(delta)
	_run_session.tick(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sandbox_reset"):
		_reset_sandbox()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("debug_grant_upgrade"):
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
	_hold_all_in_reserve()
	_encounter.restart()
	_debug_overlay.bind_enemies(_enemies)
	_debug_overlay.bind_encounter(_encounter)
	_hud.bind_player(_player)
	_hud.bind_weapon_host(_player.get_weapon_host())
	_hud.bind_encounter(_encounter)
	_run_session.bind_player(_player)
	_run_session.bind_encounter(_encounter)
	_run_session.bind_catalog(UPGRADE_CATALOG)
	_assert_upgrade_catalog()
	_run_session.restart()
	_upgrade_applier.bind_player(_player)
	_upgrade_applier.bind_session(_run_session)
	_upgrade_applier.capture_baseline()
	_upgrade_applier.apply_owned()
	_debug_overlay.bind_run_session(_run_session)
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
		var ranged: RangedEnemy = enemy as RangedEnemy
		if ranged != null:
			ranged.bind_projectile_pool(_enemy_projectiles)

func _assert_upgrade_catalog() -> void:
	if UPGRADE_CATALOG.get_count() != 10:
		push_error("升级目录条目数应为 10，实际 %d" % UPGRADE_CATALOG.get_count())
	for upgrade_id: String in REQUIRED_UPGRADE_IDS:
		if UPGRADE_CATALOG.get_by_id(StringName(upgrade_id)) == null:
			push_error("升级目录缺少 id: %s" % upgrade_id)

func _hold_all_in_reserve() -> void:
	for enemy: EnemyBase in _enemies:
		enemy.hold_in_reserve()

func _reset_sandbox() -> void:
	_projectiles.park_all()
	_enemy_projectiles.park_all()
	_run_session.restart()
	_upgrade_applier.apply_owned()
	_player.reset_for_sandbox()
	_hold_all_in_reserve()
	_encounter.restart()
	_debug_overlay.set_last_grant_id("-")

func _try_debug_grant() -> void:
	if _player.is_defeated():
		return
	if not _run_session.try_grant(GRANT_UPGRADE_ID):
		return
	_upgrade_applier.apply_owned()
	_debug_overlay.set_last_grant_id(String(GRANT_UPGRADE_ID))

func _bind_window_cursor() -> void:
	var window: Window = get_window()
	window.mouse_entered.connect(_on_window_mouse_entered)
	window.mouse_exited.connect(_on_window_mouse_exited)
	window.focus_entered.connect(_sync_system_cursor)
	window.focus_exited.connect(_sync_system_cursor)
	_mouse_inside_window = _is_mouse_inside_window()

func _on_window_mouse_entered() -> void:
	_mouse_inside_window = true
	_sync_system_cursor()

func _on_window_mouse_exited() -> void:
	_mouse_inside_window = false
	_sync_system_cursor()

func _sync_system_cursor() -> void:
	var hide_cursor: bool = get_window().has_focus() and _mouse_inside_window
	if hide_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_aim_reticle.visible = hide_cursor

func _is_mouse_inside_window() -> bool:
	var window: Window = get_window()
	var window_rect: Rect2i = Rect2i(window.position, window.size)
	return window_rect.has_point(DisplayServer.mouse_get_position())

func _apply_wall_layers() -> void:
	for child: Node in _walls.get_children():
		var body: StaticBody2D = child as StaticBody2D
		if body == null:
			continue
		body.collision_layer = GameCollisionLayers.MASK_WALL
		body.collision_mask = GameCollisionLayers.MASK_NONE
