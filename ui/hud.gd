extends CanvasLayer
class_name Hud

## 最小战斗 HUD：左下 HP+武器+XP+gold，顶中句读。只读 getter，禁止自管一份 HP。
## 血条/XP 条数值用指数缓动追目标（osu 式），数字仍瞬时；锚点布局不改。
const HP_LOW_THRESHOLD: int = 20
const BAR_SMOOTHING: float = 10.0
const FILL_STYLE_NORMAL: StringName = &""
const FILL_STYLE_LOW: StringName = &"ProgressBarLow"

var _player: Player
var _weapon_host: WeaponHost
var _encounter: EncounterPhrases
var _run_session: RunSession
var _hp_is_low: bool = false

@onready var _hp_bar: ProgressBar = $Root/BottomLeft/HpRow/HpBar
@onready var _hp_label: Label = $Root/BottomLeft/HpRow/HpLabel
@onready var _xp_bar: ProgressBar = $Root/BottomLeft/XpRow/XpBar
@onready var _xp_label: Label = $Root/BottomLeft/XpRow/XpLabel
@onready var _weapon_label: Label = $Root/BottomLeft/WeaponLabel
@onready var _gold_label: Label = $Root/BottomLeft/GoldLabel
@onready var _phrase_label: Label = $Root/PhraseLabel

func bind_player(player: Player) -> void:
	_player = player

func bind_weapon_host(host: WeaponHost) -> void:
	_weapon_host = host

func bind_encounter(encounter: EncounterPhrases) -> void:
	_encounter = encounter

func bind_run_session(session: RunSession) -> void:
	_run_session = session

func _process(delta: float) -> void:
	_refresh_hp(delta)
	_refresh_xp(delta)
	_refresh_gold()
	_refresh_weapon()
	_refresh_phrase()

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
	var phrase: String = "-"
	if _encounter != null:
		phrase = _encounter.get_phrase_label()
	var loop_index: int = 0
	if _run_session != null:
		loop_index = _run_session.get_loop_index()
	if _run_session != null and _run_session.is_solo():
		_phrase_label.text = "L%d/%d  %s" % [loop_index, GameLaunch.SOLO_LOOP_GOAL, phrase]
		return
	_phrase_label.text = "L%d  %s" % [loop_index, phrase]
