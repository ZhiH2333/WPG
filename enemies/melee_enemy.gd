extends EnemyBase
class_name MeleeEnemy

## 走向玩家，Area2D 碰到才造成接触伤害。不射击。
@export var contact_damage: int = 8

@onready var _contact_area: Area2D = $ContactArea

func _ready() -> void:
	max_hp = 36
	move_speed = 175.0
	acceleration = 1400.0
	super._ready()
	_bind_contact_area()

func get_kind_name() -> String:
	return "Melee"

func _bind_contact_area() -> void:
	_contact_area.collision_layer = GameCollisionLayers.MASK_NONE
	_contact_area.collision_mask = GameCollisionLayers.MASK_PLAYER
	_contact_area.monitorable = false
	_contact_area.monitoring = true
	_contact_area.body_entered.connect(_on_contact_body_entered)

func _tick_ai(delta: float) -> void:
	if is_in_hitstop() or _defeated:
		return
	if not _player_alive():
		_steer_toward(delta, Vector2.ZERO)
		return
	_steer_toward(delta, _desired_velocity_to_player())
	_try_contact_damage()

func _on_contact_body_entered(body: Node) -> void:
	_try_hit_player(body)

func _try_contact_damage() -> void:
	for body: Node2D in _contact_area.get_overlapping_bodies():
		_try_hit_player(body)

func _try_hit_player(body: Node) -> void:
	if not _player_alive() or is_in_hitstop() or _defeated:
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
	_contact_area.monitoring = false
	_contact_area.set_deferred("monitoring", false)
