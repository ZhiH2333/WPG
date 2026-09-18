extends EnemyBase
class_name MeleeEnemy

## 走向玩家，Area2D 碰到才造成接触伤害。不射击。廉价正交分离，禁止探查其它敌人。
@export var contact_damage: int = 8

var _base_contact_damage: int = 0

@onready var _contact_area: Area2D = $ContactArea

func _ready() -> void:
	max_hp = 36
	move_speed = 175.0
	acceleration = 1400.0
	super._ready()
	_base_contact_damage = contact_damage
	_bind_contact_area()

func get_kind_name() -> String:
	return "Melee"

func _native_faces_right() -> bool:
	return FacingContract.MELEE_NATIVE_FACES_RIGHT

func _base_visual_scale() -> Vector2:
	return FacingContract.MELEE_BASE_SCALE

func _setup_visual() -> void:
	_visual.texture = load(FacingContract.MELEE_TEXTURE) as Texture2D
	_visual.centered = true
	_visual.scale = FacingContract.MELEE_BASE_SCALE

func get_xp_reward() -> int:
	return 10

func get_gold_reward() -> int:
	return 3

func get_hp_per_loop() -> int:
	return 8

func get_contact_damage_per_loop() -> int:
	return 2

func _apply_damage_pressure(pressure: int) -> void:
	contact_damage = _base_contact_damage + pressure * get_contact_damage_per_loop()

func _bind_contact_area() -> void:
	_contact_area.collision_layer = GameCollisionLayers.MASK_NONE
	_contact_area.collision_mask = GameCollisionLayers.MASK_PLAYER
	_contact_area.monitorable = false
	_contact_area.monitoring = true
	_contact_area.body_entered.connect(_on_contact_body_entered)

func _tick_ai(delta: float) -> void:
	if is_in_reserve() or is_in_hitstop() or _defeated or is_entering():
		return
	if not _player_alive():
		_steer_toward(delta, Vector2.ZERO)
		return
	_steer_toward(delta, _separated_seek_velocity())
	_try_contact_damage()

func _on_contact_body_entered(body: Node) -> void:
	_try_hit_player(body)

func _try_contact_damage() -> void:
	if is_in_reserve() or not _contact_area.monitoring or is_entering() or _defeated:
		return
	for body: Node2D in _contact_area.get_overlapping_bodies():
		_try_hit_player(body)

func _try_hit_player(body: Node) -> void:
	if not _sim_authority:
		return
	if is_in_reserve() or not _player_alive() or is_in_hitstop() or _defeated or is_entering():
		return
	var player: Player = body as Player
	if player == null:
		return
	var direction: Vector2 = player.global_position - global_position
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()
	player.get_player_health().apply_damage(contact_damage, global_position, direction)

func _on_defeated() -> void:
	_contact_area.set_deferred("monitoring", false)

func _on_hold_in_reserve() -> void:
	_contact_area.monitoring = false
	_contact_area.set_deferred("monitoring", false)

func _on_reset_for_sandbox() -> void:
	_contact_area.monitoring = true
	_contact_area.set_deferred("monitoring", true)
