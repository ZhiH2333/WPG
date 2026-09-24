extends CanvasLayer
class_name Hud

## 最小战斗 HUD：左下 HP+武器+XP+gold，顶中句读。2 人 Battle 右上 RivalRow、Phrase 为 BATTLE。占用≥3 的 Co-op / Battle 右上 Roster 短血。只读 getter，禁止自管一份 HP。
## 血条/XP 条数值用指数缓动追目标（osu 式），数字仍瞬时；左下锚点布局不改。
const HP_LOW_THRESHOLD: int = 20
const BAR_SMOOTHING: float = 10.0
const ROSTER_MAX: int = 4
const FILL_STYLE_NORMAL: StringName = &""
const FILL_STYLE_LOW: StringName = &"ProgressBarLow"

var _player: Player
var _rival: Player
var _weapon_host: WeaponHost
var _encounter: EncounterPhrases
var _run_session: RunSession
var _hp_is_low: bool = false
var _is_battle: bool = false
var _roster_pawns: Array[Player] = [] ## 非本地，已按 seat 升序，长度 0～4
var _roster_seats: PackedInt32Array = PackedInt32Array()

@onready var _hp_bar: ProgressBar = $Root/BottomLeft/HpRow/HpBar
@onready var _hp_label: Label = $Root/BottomLeft/HpRow/HpLabel
@onready var _xp_bar: ProgressBar = $Root/BottomLeft/XpRow/XpBar
@onready var _xp_label: Label = $Root/BottomLeft/XpRow/XpLabel
@onready var _xp_row: HBoxContainer = $Root/BottomLeft/XpRow
@onready var _weapon_label: Label = $Root/BottomLeft/WeaponLabel
@onready var _gold_label: Label = $Root/BottomLeft/GoldLabel
@onready var _phrase_label: Label = $Root/PhraseLabel
@onready var _rival_row: HBoxContainer = $Root/TopRight/RivalRow
@onready var _rival_bar: ProgressBar = $Root/TopRight/RivalRow/HpBar
@onready var _rival_label: Label = $Root/TopRight/RivalRow/HpLabel
@onready var _roster: VBoxContainer = $Root/TopRight/Roster

func bind_player(player: Player) -> void:
	_player = player

func bind_rival(player: Player) -> void:
	_rival = player

func bind_roster(pawns: Array[Player], seats: PackedInt32Array) -> void:
	_roster_pawns.clear()
	_roster_seats = PackedInt32Array()
	var count: int = mini(pawns.size(), seats.size())
	if count > ROSTER_MAX:
		count = ROSTER_MAX
	for i: int in count:
		_roster_pawns.append(pawns[i])
		_roster_seats.append(int(seats[i]))
	_sync_roster_visible()

func _sync_roster_visible() -> void:
	var roster_on: bool = _roster_pawns.size() >= 2
	if _roster != null:
		if roster_on:
			_roster.visible = true
		else:
			_roster.visible = false
			_hide_roster_rows()
	if _rival_row != null:
		_rival_row.visible = _is_battle and not roster_on

func _hide_roster_rows() -> void:
	if _roster == null:
		return
	for child: Node in _roster.get_children():
		var row: CanvasItem = child as CanvasItem
		if row != null:
			row.visible = false

func bind_weapon_host(host: WeaponHost) -> void:
	_weapon_host = host

func bind_encounter(encounter: EncounterPhrases) -> void:
	_encounter = encounter

func bind_run_session(session: RunSession) -> void:
	_run_session = session

func set_battle(battle: bool) -> void:
	_is_battle = battle
	if _xp_row != null:
		_xp_row.visible = not battle
	if _gold_label != null:
		_gold_label.visible = not battle
	_sync_roster_visible()

func _process(delta: float) -> void:
	_refresh_hp(delta)
	_refresh_xp(delta)
	_refresh_gold()
	_refresh_weapon()
	_refresh_phrase()
	_refresh_rival(delta)
	_refresh_roster(delta)

func _refresh_hp(delta: float) -> void:
	var hp: int = 0
	var max_hp: int = 100
	if _player != null:
		var health: PlayerHealth = _player.get_player_health()
		hp = health.get_hp()
		max_hp = health.get_max_hp()
	_hp_bar.max_value = float(max_hp)
	_hp_bar.value = _approach_bar(_hp_bar.value, float(hp), delta)
	_hp_label.text = "%d/%d" % [hp, max_hp]
	_apply_hp_fill(hp)

func _refresh_xp(delta: float) -> void:
	var level: int = 1
	var xp: int = 0
	var need: int = 30
	if _run_session != null:
		level = _run_session.get_level()
		xp = _run_session.get_xp()
		need = _run_session.get_xp_to_next()
	_xp_bar.max_value = float(need)
	_xp_bar.value = _approach_bar(_xp_bar.value, float(xp), delta)
	_xp_label.text = "Lv.%d  %d/%d" % [level, xp, need]

func _approach_bar(current: float, target: float, delta: float) -> float:
	if absf(target - current) < 0.5:
		return target
	return lerpf(current, target, 1.0 - exp(-BAR_SMOOTHING * delta))

func _refresh_gold() -> void:
	var gold: int = 0
	if _run_session != null:
		gold = _run_session.get_gold()
	_gold_label.text = "gold  %d" % gold

func _apply_hp_fill(hp: int) -> void:
	var is_low: bool = hp <= HP_LOW_THRESHOLD
	if is_low == _hp_is_low:
		return
	_hp_is_low = is_low
	if is_low:
		_hp_bar.theme_type_variation = FILL_STYLE_LOW
		return
	_hp_bar.theme_type_variation = FILL_STYLE_NORMAL

func _refresh_weapon() -> void:
	if _weapon_host == null:
		_weapon_label.text = "-"
		return
	var weapon: Weapon = _weapon_host.get_current_weapon()
	if weapon == null:
		_weapon_label.text = "-"
		return
	_weapon_label.text = weapon.get_display_name()

func _refresh_phrase() -> void:
	if _is_battle:
		_phrase_label.text = "BATTLE"
		return
	var phrase: String = "-"
	if _encounter != null:
		phrase = _encounter.get_phrase_label()
	var loop_index: int = 0
	if _run_session != null:
		loop_index = _run_session.get_loop_index()
	if _run_session != null and _run_session.get_loop_goal() > 0:
		_phrase_label.text = "L%d/%d  %s" % [loop_index, _run_session.get_loop_goal(), phrase]
		return
	_phrase_label.text = "L%d  %s" % [loop_index, phrase]

func _refresh_rival(delta: float) -> void:
	if not _is_battle or _rival_row == null or not _rival_row.visible:
		return
	var hp: int = 0
	var max_hp: int = 100
	if _rival != null:
		var health: PlayerHealth = _rival.get_player_health()
		hp = health.get_hp()
		max_hp = health.get_max_hp()
	_rival_bar.max_value = float(max_hp)
	_rival_bar.value = _approach_bar(_rival_bar.value, float(hp), delta)
	_rival_label.text = "rival  %d/%d" % [hp, max_hp]

func _refresh_roster(delta: float) -> void:
	if _roster == null or not _roster.visible:
		return
	for i: int in ROSTER_MAX:
		_refresh_roster_row(i, delta)

func _refresh_roster_row(index: int, delta: float) -> void:
	var row: HBoxContainer = _roster.get_child(index) as HBoxContainer
	if row == null:
		return
	if index >= _roster_pawns.size():
		row.visible = false
		return
	var pawn: Player = _roster_pawns[index]
	if pawn == null or not is_instance_valid(pawn):
		row.visible = false
		return
	row.visible = true
	var health: PlayerHealth = pawn.get_player_health()
	var hp: int = health.get_hp()
	var max_hp: int = health.get_max_hp()
	var bar: ProgressBar = row.get_node("HpBar") as ProgressBar
	var label: Label = row.get_node("HpLabel") as Label
	if bar != null:
		bar.max_value = float(max_hp)
		bar.value = _approach_bar(bar.value, float(hp), delta)
	if label != null:
		var seat: int = 0
		if index < _roster_seats.size():
			seat = _roster_seats[index]
		label.text = "s%d  %d/%d" % [seat, hp, max_hp]
	if pawn.is_defeated() or hp <= 0:
		row.modulate.a = 0.45
		return
	row.modulate.a = 1.0
