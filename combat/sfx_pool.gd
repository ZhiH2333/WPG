extends Node2D
class_name SfxPool

## 本局音效池，挂在 CombatSandbox 上，不是 Autoload。禁止每发 new 播放器。
## Web / Android 上 AudioStreamPlayer2D 经常没声，一律走非空间播放器。
const VOICE_COUNT: int = 8

var _voices: Array[AudioStreamPlayer] = []
var _started_msec: PackedInt32Array = PackedInt32Array()
var _stream_pistol: AudioStream
var _stream_shotgun: AudioStream
var _stream_rifle: AudioStream
var _stream_smg: AudioStream
var _stream_hit: AudioStream
var _stream_kill: AudioStream
var _stream_hurt: AudioStream
var _stream_click: AudioStream
var _stream_enemy_shot: AudioStream

func _ready() -> void:
	_stream_pistol = GameAudio.load_wav("res://audio/pistol.wav")
	_stream_shotgun = GameAudio.load_wav("res://audio/shotgun.wav")
	_stream_rifle = GameAudio.load_wav("res://audio/rifle.wav")
	_stream_smg = GameAudio.load_wav("res://audio/smg.wav")
	_stream_hit = GameAudio.load_wav("res://audio/hit.wav")
	_stream_kill = GameAudio.load_wav("res://audio/kill.wav")
	_stream_hurt = GameAudio.load_wav("res://audio/hurt.wav")
	_stream_click = GameAudio.load_wav("res://audio/click.wav")
	_stream_enemy_shot = GameAudio.load_wav("res://audio/enemy_shot.wav")
	_started_msec.resize(VOICE_COUNT)
	for i: int in VOICE_COUNT:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.bus = "SFX"
		add_child(voice)
		_voices.append(voice)
		_started_msec[i] = 0

func get_voice_count() -> int:
	return _voices.size()

func play(stream: AudioStream, pitch_scale: float, volume_db: float, _world_position: Vector2 = Vector2.ZERO) -> void:
	if stream == null:
		return
	var index: int = _pick_voice_index()
	var voice: AudioStreamPlayer = _voices[index]
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	voice.volume_db = volume_db
	_started_msec[index] = Time.get_ticks_msec()
	voice.play()

func play_pistol(world_position: Vector2) -> void:
	play(_stream_pistol, randf_range(0.98, 1.02), -6.0, world_position)

func play_shotgun(world_position: Vector2) -> void:
	play(_stream_shotgun, 1.0, -6.0, world_position)

func play_rifle(world_position: Vector2) -> void:
	play(_stream_rifle, randf_range(0.97, 1.03), -7.0, world_position)

func play_smg(world_position: Vector2) -> void:
	play(_stream_smg, randf_range(0.98, 1.03), -10.0, world_position)

func play_weapon(weapon: Weapon, world_position: Vector2) -> void:
	if weapon is Shotgun:
		play_shotgun(world_position)
		return
	if weapon is Rifle:
		play_rifle(world_position)
		return
	if weapon is Smg:
		play_smg(world_position)
		return
	play_pistol(world_position)

func play_hit(world_position: Vector2) -> void:
	play(_stream_hit, 1.0, -10.0, world_position)

func play_kill(world_position: Vector2) -> void:
	play(_stream_kill, 1.0, -6.0, world_position)

func play_hurt(world_position: Vector2) -> void:
	play(_stream_hurt, 1.0, -4.0, world_position)

func play_click(world_position: Vector2) -> void:
	play(_stream_click, 1.0, -8.0, world_position)

func play_dash(world_position: Vector2) -> void:
	play(_stream_click, 0.62, -8.0, world_position)

func play_charge(world_position: Vector2) -> void:
	play(_stream_click, 0.48, -6.0, world_position)

func play_enemy_shot(world_position: Vector2) -> void:
	play(_stream_enemy_shot, 0.94, -7.0, world_position)

func _pick_voice_index() -> int:
	for i: int in _voices.size():
		if not _voices[i].playing:
			return i
	var oldest: int = 0
	var oldest_msec: int = _started_msec[0]
	for i: int in _voices.size():
		if _started_msec[i] < oldest_msec:
			oldest_msec = _started_msec[i]
			oldest = i
	return oldest
