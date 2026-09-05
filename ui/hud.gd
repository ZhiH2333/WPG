extends CanvasLayer
class_name Hud

## 最小战斗 HUD：左下 HP+武器，顶中句读。只读 getter，禁止自管一份 HP。
const HP_LOW_THRESHOLD: int = 20
const FILL_STYLE_NORMAL: StringName = &""
const FILL_STYLE_LOW: StringName = &"ProgressBarLow"

var _player: Player
var _weapon_host: WeaponHost
var _encounter: EncounterPhrases
var _hp_is_low: bool = false

@onready var _hp_bar: ProgressBar = $Root/BottomLeft/HpRow/HpBar
@onready var _hp_label: Label = $Root/BottomLeft/HpRow/HpLabel
@onready var _weapon_label: Label = $Root/BottomLeft/WeaponLabel
@onready var _phrase_label: Label = $Root/PhraseLabel

func bind_player(player: Player) -> void:
	_player = player

func bind_weapon_host(host: WeaponHost) -> void:
	_weapon_host = host

func bind_encounter(encounter: EncounterPhrases) -> void:
	_encounter = encounter

func _process(_delta: float) -> void:
	_refresh_hp()
	_refresh_weapon()
	_refresh_phrase()

func _refresh_hp() -> void:
	var hp: int = 0
	var max_hp: int = 100
	if _player != null:
		var health: PlayerHealth = _player.get_player_health()
		hp = health.get_hp()
		max_hp = health.get_max_hp()
	_hp_bar.max_value = float(max_hp)
	_hp_bar.value = float(hp)
	_hp_label.text = "%d/%d" % [hp, max_hp]
	_apply_hp_fill(hp)

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
	if _encounter == null:
		_phrase_label.text = "-"
		return
	_phrase_label.text = _encounter.get_phrase_label()
