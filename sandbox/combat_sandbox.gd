extends Node2D
class_name CombatSandbox

const PROJECTILE_SCENE: PackedScene = preload("res://weapons/projectile.tscn")
const POOL_CAPACITY: int = 96

## 只有鼠标在窗口内且窗口有焦点时才藏系统光标，避免出窗后桌面丢指针。
var _mouse_inside_window: bool = true

@onready var _walls: Node2D = $Walls
@onready var _player: Player = $Player
@onready var _player_camera: PlayerCamera = $PlayerCamera
@onready var _aim_reticle: AimReticle = $AimReticle
@onready var _debug_overlay: DebugOverlay = $DebugOverlay
@onready var _projectiles: ProjectilePool = $Projectiles
@onready var _dummy_targets: Node2D = $DummyTargets

func _ready() -> void:
	_apply_wall_layers()
	_bind_runtime()
	_bind_window_cursor()
	_sync_system_cursor()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _bind_runtime() -> void:
	var player_input: PlayerInput = _player.get_player_input()
	_projectiles.setup(_projectiles, PROJECTILE_SCENE, POOL_CAPACITY)
	_player.bind_projectile_pool(_projectiles)
	_player_camera.bind_player(_player)
	_aim_reticle.bind_player_input(player_input)
	_debug_overlay.bind_player(_player)
	_debug_overlay.bind_player_camera(_player_camera)
	_debug_overlay.bind_weapon_host(_player.get_weapon_host())
	_debug_overlay.bind_projectile_pool(_projectiles)
	_debug_overlay.bind_dummies(_collect_dummies())

func _collect_dummies() -> Array[DummyTarget]:
	var dummies: Array[DummyTarget] = []
	for child: Node in _dummy_targets.get_children():
		var dummy: DummyTarget = child as DummyTarget
		if dummy != null:
			dummies.append(dummy)
	return dummies

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
