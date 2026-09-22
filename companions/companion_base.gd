extends CharacterBody2D
class_name CompanionBase

## 跟班基类。禁止 extends EnemyBase：玩家弹不能打中，死亡不给 XP/gold，句读不当敌人。
const FLASH_DURATION_SEC: float = 0.1
const DEAD_COLOR: Color = Color(0.42, 0.42, 0.44, 1)
const FACE_DEADZONE_PX: float = 2.0
const LEASH_PX: float = 240.0
const SLOT_BACK_PX: float = 56.0
const SLOT_SIDE_PX: float = 52.0
const KEEP_DIST: float = 190.0
const KEEP_BAND: float = 40.0
const STRAFE_SPEED: float = 220.0
const STRAFE_FLIP_SEC: float = 1.1
const AGGRO_DROP_PX: float = 80.0
const ARRIVE_PX: float = 18.0
const CATCH_UP_RELEASE_PX: float = 180.0
const LOS_CHECK: bool = true

enum AiState { CATCH_UP, FOLLOW, ENGAGE }

var _def: CompanionDef
var _hp: int = 1
var _max_hp: int = 1
var _move_speed: float = 260.0
var _acceleration: float = 1600.0
var _follow_distance: float = 56.0
var _aggro_range: float = 280.0
var _i_frame_sec: float = 0.25
var _i_frame_left_sec: float = 0.0
var _flash_left_sec: float = 0.0
var _defeated: bool = false
var _flip_h: bool = false
var _body_modulate: Color = Color(0.45, 0.85, 1, 1)
var _owner_player: Player
var _enemies: Array[EnemyBase] = []
var _allies: Array[CompanionBase] = []
var _sfx_pool: SfxPool
var _hit_reaction: HitReaction
var _ai_state: AiState = AiState.FOLLOW
var _commit_target: EnemyBase
var _strafe_sign: int = 1
var _strafe_flip_left_sec: float = STRAFE_FLIP_SEC
var _hp_bar: WorldHpBar
var _slot_index: int = 0

@onready var _visual: Sprite2D = $Visual
@onready var _hurtbox: CollisionShape2D = $CollisionShape2D
@onready var _contact_area: Area2D = get_node_or_null("ContactArea") as Area2D

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = GameCollisionLayers.MASK_PLAYER
	collision_mask = GameCollisionLayers.MASK_WALL
	_bind_hit_reaction()
	_bind_hp_bar()

func apply_def(def: CompanionDef) -> void:
	if def == null:
		return
	_def = def
	_max_hp = maxi(1, def.base_max_hp)
	_hp = _max_hp
	_move_speed = def.base_move_speed
	_acceleration = def.base_acceleration
	_follow_distance = def.follow_distance
	_aggro_range = def.aggro_range
	_i_frame_sec = def.i_frame_sec
	_body_modulate = def.body_modulate
	_defeated = false
	_i_frame_left_sec = 0.0
	_flash_left_sec = 0.0
	_ai_state = AiState.FOLLOW
	_commit_target = null
	_strafe_sign = 1
	_strafe_flip_left_sec = STRAFE_FLIP_SEC
	_apply_hurtbox_radius(def.hurtbox_radius)
	_apply_body_visual(def)
	if _hit_reaction != null and _visual != null:
		_hit_reaction.bind_visual(_visual)
	_layout_hp_bar()
	_refresh_hp_bar()

func get_companion_id() -> StringName:
	if _def == null:
		return &""
	return _def.id

func get_hp() -> int:
	return _hp

func get_max_hp() -> int:
	return _max_hp

func is_defeated() -> bool:
	return _defeated

func set_slot_index(index: int) -> void:
	_slot_index = maxi(index, 0)

func get_slot_index() -> int:
	return _slot_index

func get_commit_target() -> EnemyBase:
	return _commit_target

func fill_hp() -> void:
	if _defeated:
		return
	_hp = _max_hp
	_refresh_hp_bar()

func bind_owner(player: Player) -> void:
	_owner_player = player

func bind_enemies(enemies: Array[EnemyBase]) -> void:
	_enemies = enemies

func bind_allies(allies: Array[CompanionBase]) -> void:
	_allies = allies

func bind_sfx_pool(sfx_pool: SfxPool) -> void:
	_sfx_pool = sfx_pool

func bind_projectile_pool(_pool: ProjectilePool) -> void:
	pass

func apply_damage(amount: int, hit_position: Vector2, hit_direction: Vector2 = Vector2.ZERO) -> void:
	if _defeated or _i_frame_left_sec > 0.0 or amount <= 0:
		return
	var direction: Vector2 = _resolve_hit_direction(hit_direction)
	_hp = maxi(0, _hp - amount)
	_refresh_hp_bar()
	_spawn_damage_number(amount, hit_position)
	_start_flash()
	_i_frame_left_sec = _i_frame_sec
	if _hit_reaction != null:
		_hit_reaction.play(direction)
	if _sfx_pool != null:
		_sfx_pool.play_hit(hit_position)
	if _hp <= 0:
		_defeat()

func _physics_process(delta: float) -> void:
	if _defeated:
		return
	_tick_ai_state(delta)
	velocity = velocity.move_toward(_compute_desired_velocity(), _acceleration * delta)
	move_and_slide()
	if _ai_state == AiState.ENGAGE and get_slide_collision_count() > 0:
		_flip_strafe_sign()
	_face_for_state()
	_tick_attack(_commit_target, delta)

func _process(delta: float) -> void:
	_tick_i_frame(delta)
	_tick_flash(delta)

func _tick_attack(_target: EnemyBase, _delta: float) -> void:
	pass

func _tick_ai_state(delta: float) -> void:
	if _owner_player == null:
		_ai_state = AiState.FOLLOW
		_commit_target = null
		return
	var dist_player: float = global_position.distance_to(_owner_player.global_position)
	if dist_player > LEASH_PX:
		_ai_state = AiState.CATCH_UP
		_commit_target = null
		return
	if _ai_state == AiState.CATCH_UP and dist_player >= CATCH_UP_RELEASE_PX:
		return
	_refresh_commit_target()
	if _commit_target != null:
		_ai_state = AiState.ENGAGE
		_tick_strafe_timer(delta)
		return
	_ai_state = AiState.FOLLOW

func _compute_desired_velocity() -> Vector2:
	if _ai_state == AiState.ENGAGE:
		return _engage_velocity()
	return _seek_slot_velocity(_ai_state == AiState.FOLLOW)

func _seek_slot_velocity(allow_arrive: bool) -> Vector2:
	if _owner_player == null:
		return Vector2.ZERO
	var to_slot: Vector2 = _follow_slot() - global_position
	var distance: float = to_slot.length()
	if allow_arrive and distance <= ARRIVE_PX:
		return Vector2.ZERO
	if distance <= 0.001:
		return Vector2.ZERO
	return to_slot.normalized() * _move_speed

func _follow_slot() -> Vector2:
	if _owner_player == null:
		return global_position
	var aim: Vector2 = _read_aim_or_left()
	var pair: int = int(_slot_index / 2)
	var side_sign: float = -1.0 if (_slot_index % 2) == 1 else 1.0
	var back: float = SLOT_BACK_PX + float(pair) * 18.0
	var side: float = SLOT_SIDE_PX + float(pair) * 14.0
	return _owner_player.global_position - aim * back + aim.orthogonal() * side * side_sign

func _engage_velocity() -> Vector2:
	var target: EnemyBase = _commit_target
	if target == null or not is_instance_valid(target):
		return Vector2.RIGHT * STRAFE_SPEED * float(_strafe_sign)
	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()
	var radial_dir: Vector2 = Vector2.RIGHT
	if distance > 0.001:
		radial_dir = to_target.normalized()
	var radial: Vector2 = Vector2.ZERO
	if distance > KEEP_DIST + KEEP_BAND:
		radial = radial_dir * _move_speed
	elif distance < KEEP_DIST - KEEP_BAND:
		radial = -radial_dir * _move_speed
	return radial + radial_dir.orthogonal() * STRAFE_SPEED * float(_strafe_sign)

func _tick_strafe_timer(delta: float) -> void:
	_strafe_flip_left_sec -= delta
	if _strafe_flip_left_sec > 0.0:
		return
	_flip_strafe_sign()
	_strafe_flip_left_sec = STRAFE_FLIP_SEC

func _flip_strafe_sign() -> void:
	_strafe_sign *= -1

func _refresh_commit_target() -> void:
	if _is_commit_valid(_commit_target) and not _should_split_from_stack():
		return
	_commit_target = _pick_commit_target()

func _is_commit_valid(target: EnemyBase) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.is_in_reserve() or target.is_defeated() or target.is_entering():
		return false
	if _owner_player == null:
		return false
	return target.global_position.distance_to(_owner_player.global_position) <= _aggro_range + AGGRO_DROP_PX

func _should_split_from_stack() -> bool:
	if not _is_target_taken(_commit_target):
		return false
	return _best_candidate(true) != null

func _pick_commit_target() -> EnemyBase:
	var unclaimed: EnemyBase = _best_candidate(true)
	if unclaimed != null:
		return unclaimed
	return _best_candidate(false)

func _best_candidate(unclaimed_only: bool) -> EnemyBase:
	if _owner_player == null:
		return null
	var aim: Vector2 = _read_aim_or_left()
	var best: EnemyBase = null
	var best_dot: float = -INF
	var best_dist: float = INF
	for enemy: EnemyBase in _enemies:
		if enemy == null or enemy.is_in_reserve() or enemy.is_defeated() or enemy.is_entering():
			continue
		if unclaimed_only and _is_target_taken(enemy):
			continue
		var offset: Vector2 = enemy.global_position - _owner_player.global_position
		var dist: float = offset.length()
		if dist >= _aggro_range:
			continue
		var facing: Vector2 = Vector2.RIGHT if dist <= 0.001 else offset / dist
		var facing_dot: float = facing.dot(aim)
		if best != null and facing_dot < best_dot:
			continue
		if best != null and is_equal_approx(facing_dot, best_dot) and dist >= best_dist:
			continue
		best = enemy
		best_dot = facing_dot
		best_dist = dist
	return best

func _is_target_taken(target: EnemyBase) -> bool:
	if target == null:
		return false
	for ally: CompanionBase in _allies:
		if ally == null or ally == self or not is_instance_valid(ally) or ally.is_defeated():
			continue
		if ally.get_commit_target() == target:
			return true
	return false

func _read_aim_or_left() -> Vector2:
	if _owner_player == null:
		return Vector2.LEFT
	var aim: Vector2 = _owner_player.get_player_input().aim_vector
	if aim.is_zero_approx():
		return Vector2.LEFT
	return aim.normalized()

func _face_for_state() -> void:
	var dx: float = 0.0
	if _ai_state == AiState.ENGAGE and _commit_target != null and is_instance_valid(_commit_target):
		dx = _commit_target.global_position.x - global_position.x
	else:
		dx = _read_aim_or_left().x
	if absf(dx) > FACE_DEADZONE_PX:
		_flip_h = (dx > 0.0) != _native_faces_right()
	_apply_flip(_flip_h)

func _native_faces_right() -> bool:
	if _def != null and _def.kind == CompanionDef.Kind.RANGED:
		return FacingContract.RANGED_NATIVE_FACES_RIGHT
	return FacingContract.MELEE_NATIVE_FACES_RIGHT

func _apply_flip(flip_h: bool) -> void:
	if _visual != null:
		_visual.flip_h = flip_h

func _apply_hurtbox_radius(radius: float) -> void:
	if _hurtbox == null:
		return
	var circle: CircleShape2D = _hurtbox.shape as CircleShape2D
	if circle == null:
		return
	circle.radius = radius

func _apply_body_visual(def: CompanionDef) -> void:
	if _visual == null:
		return
	var texture: Texture2D = def.body_texture
	if texture == null:
		if def.kind == CompanionDef.Kind.RANGED:
			texture = load(FacingContract.RANGED_TEXTURE) as Texture2D
		else:
			texture = load(FacingContract.MELEE_TEXTURE) as Texture2D
	_visual.texture = texture
	_visual.centered = true
	_visual.rotation = 0.0
	_visual.scale = def.body_scale
	_visual.modulate = def.body_modulate

func _bind_hit_reaction() -> void:
	_hit_reaction = HitReaction.new()
	_hit_reaction.name = "HitReaction"
	add_child(_hit_reaction)
	_hit_reaction.bind_visual(_visual)

func _bind_hp_bar() -> void:
	_hp_bar = WorldHpBar.new()
	_hp_bar.name = "HpBar"
	add_child(_hp_bar)

func _layout_hp_bar() -> void:
	if _hp_bar == null:
		return
	var texture: Texture2D = null
	var body_scale: Vector2 = Vector2(0.048, 0.048)
	if _visual != null:
		texture = _visual.texture
	if _def != null:
		body_scale = _def.body_scale
	_hp_bar.configure(
		WorldHpBar.FILL_COMPANION,
		WorldHpBar.y_for_sprite(texture, body_scale),
		WorldHpBar.width_for_sprite(texture, body_scale)
	)

func _refresh_hp_bar() -> void:
	if _hp_bar == null:
		return
	_hp_bar.bind_hp(_hp, _max_hp)
	_hp_bar.set_shown(not _defeated)

func _tick_i_frame(delta: float) -> void:
	if _i_frame_left_sec <= 0.0:
		return
	_i_frame_left_sec = maxf(0.0, _i_frame_left_sec - delta)

func _tick_flash(delta: float) -> void:
	if _flash_left_sec <= 0.0:
		return
	_flash_left_sec -= delta
	if _flash_left_sec <= 0.0:
		_restore_color()

func _start_flash() -> void:
	if _visual == null:
		return
	_flash_left_sec = FLASH_DURATION_SEC
	_visual.modulate = Color(2.2, 2.2, 2.2, 1)

func _restore_color() -> void:
	if _visual == null:
		return
	if _defeated:
		_visual.modulate = DEAD_COLOR
		return
	_visual.modulate = _body_modulate

func _defeat() -> void:
	_defeated = true
	_i_frame_left_sec = 0.0
	collision_layer = GameCollisionLayers.MASK_NONE
	collision_mask = GameCollisionLayers.MASK_NONE
	if _contact_area != null:
		_contact_area.set_deferred("monitoring", false)
	if _visual != null:
		_visual.modulate = DEAD_COLOR
	if _hit_reaction != null:
		_hit_reaction.begin_death(true)
	_refresh_hp_bar()
	_on_defeated()

func _on_defeated() -> void:
	pass

func _resolve_hit_direction(hit_direction: Vector2) -> Vector2:
	if not hit_direction.is_zero_approx():
		return hit_direction.normalized()
	return Vector2.RIGHT

func _spawn_damage_number(amount: int, hit_position: Vector2) -> void:
	DamageNumber.spawn(self, amount, hit_position)
