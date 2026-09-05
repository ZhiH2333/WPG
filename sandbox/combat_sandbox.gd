extends Node2D
class_name CombatSandbox

const PROJECTILE_SCENE: PackedScene = preload("res://weapons/projectile.tscn")
const POOL_CAPACITY: int = 96
const ENEMY_POOL_CAPACITY: int = 48

## 只有鼠标在窗口内且窗口有焦点时才藏系统光标，避免出窗后桌面丢指针。
var _mouse_inside_window: bool = true
var _enemies: Array[EnemyBase] = []
var _enemy_spawns: Array[Vector2] = []

@onready var _walls: Node2D = $Walls
@onready var _player: Player = $Player
@onready var _player_camera: PlayerCamera = $PlayerCamera
@onready var _aim_reticle: AimReticle = $AimReticle
@onready var _debug_overlay: DebugOverlay = $DebugOverlay
@onready var _projectiles: ProjectilePool = $Projectiles
@onready var _enemy_projectiles: ProjectilePool = $EnemyProjectiles
@onready var _enemies_root: Node2D = $Enemies
@onready var _sfx_pool: SfxPool = $SfxPool

func _ready() -> void:
	_apply_wall_layers()
	_bind_runtime()
	_bind_window_cursor()
	_sync_system_cursor()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("sandbox_reset"):
		return
	_reset_sandbox()
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
	_cache_enemy_spawns()
	_bind_enemies(_enemies)
	_apply_entry_stagger()
	_debug_overlay.bind_enemies(_enemies)

func _collect_enemies() -> Array[EnemyBase]:
	var enemies: Array[EnemyBase] = []
	for child: Node in _enemies_root.get_children():
		var enemy: EnemyBase = child as EnemyBase
		if enemy != null:
			enemies.append(enemy)
	return enemies

func _cache_enemy_spawns() -> void:
	_enemy_spawns.clear()
	for enemy: EnemyBase in _enemies:
		_enemy_spawns.append(enemy.global_position)

func _bind_enemies(enemies: Array[EnemyBase]) -> void:
	for enemy: EnemyBase in enemies:
		enemy.bind_player(_player)
		enemy.bind_sfx_pool(_sfx_pool)
		enemy.bind_player_camera(_player_camera)
		var ranged: RangedEnemy = enemy as RangedEnemy
		if ranged != null:
			ranged.bind_projectile_pool(_enemy_projectiles)

func _apply_entry_stagger() -> void:
	var side_index: Dictionary = {}
	for i: int in _enemies.size():
		var enemy: EnemyBase = _enemies[i]
		var side: String = _side_key_for(_enemy_spawns[i])
		var index_in_side: int = int(side_index.get(side, 0))
		side_index[side] = index_in_side + 1
		enemy.assign_spawn_stagger(_stagger_for_side(side, index_in_side))

func _reset_sandbox() -> void:
	_projectiles.park_all()
	_enemy_projectiles.park_all()
	_player.reset_for_sandbox()
	for i: int in _enemies.size():
		_enemies[i].reset_for_sandbox(_enemy_spawns[i])
	_apply_entry_stagger()

func _side_key_for(spawn: Vector2) -> String:
	if spawn.x < -300.0:
		return "left"
	if spawn.y > 300.0:
		return "bottom"
	if spawn.x > 400.0:
		return "right"
	return "top"

func _stagger_for_side(side: String, index_in_side: int) -> float:
	var base_sec: float = 0.05
	if side == "bottom":
		base_sec = 0.12
	elif side == "right":
		base_sec = 0.10
	elif side == "top":
		base_sec = 0.16
	return clampf(base_sec + float(index_in_side) * 0.12, 0.0, 0.8)

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
