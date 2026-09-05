extends Node2D
class_name SfxPool

## 本局音效池，挂在 CombatSandbox 上，不是 Autoload。禁止每发 new 播放器。
## WAV 用 FileAccess 读 PCM，不依赖编辑器 .import，避免 headless 扫到一半认不出扩展名。
const VOICE_COUNT: int = 8
const MIX_RATE: int = 22050
const WAV_HEADER_BYTES: int = 44

var _voices: Array[AudioStreamPlayer2D] = []
var _started_msec: PackedInt32Array = PackedInt32Array()
var _stream_pistol: AudioStreamWAV
var _stream_shotgun: AudioStreamWAV
var _stream_rifle: AudioStreamWAV
var _stream_hit: AudioStreamWAV
var _stream_kill: AudioStreamWAV
var _stream_hurt: AudioStreamWAV
var _stream_click: AudioStreamWAV
var _stream_enemy_shot: AudioStreamWAV

func _ready() -> void:
	_stream_pistol = _load_wav("res://audio/pistol.wav")
	_stream_shotgun = _load_wav("res://audio/shotgun.wav")
	_stream_rifle = _load_wav("res://audio/rifle.wav")
	_stream_hit = _load_wav("res://audio/hit.wav")
	_stream_kill = _load_wav("res://audio/kill.wav")
	_stream_hurt = _load_wav("res://audio/hurt.wav")
	_stream_click = _load_wav("res://audio/click.wav")
	_stream_enemy_shot = _load_wav("res://audio/enemy_shot.wav")
	_started_msec.resize(VOICE_COUNT)
	for i: int in VOICE_COUNT:
		var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		voice.max_distance = 6000.0
		voice.panning_strength = 0.35
		add_child(voice)
		_voices.append(voice)
		_started_msec[i] = 0

func get_voice_count() -> int:
	return _voices.size()

func play(stream: AudioStream, pitch_scale: float, volume_db: float, world_position: Vector2 = Vector2.ZERO) -> void:
	if stream == null:
		return
	var index: int = _pick_voice_index()
	var voice: AudioStreamPlayer2D = _voices[index]
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	voice.volume_db = volume_db
	voice.global_position = world_position
	_started_msec[index] = Time.get_ticks_msec()
	voice.play()

func play_pistol(world_position: Vector2) -> void:
	play(_stream_pistol, 1.0, -6.0, world_position)

func play_shotgun(world_position: Vector2) -> void:
	play(_stream_shotgun, 1.0, -1.5, world_position)

func play_rifle(world_position: Vector2) -> void:
	play(_stream_rifle, randf_range(0.97, 1.03), -8.0, world_position)

func play_weapon(weapon: Weapon, world_position: Vector2) -> void:
	if weapon is Shotgun:
		play_shotgun(world_position)
		return
	if weapon is Rifle:
		play_rifle(world_position)
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

func _load_wav(path: String) -> AudioStreamWAV:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() <= WAV_HEADER_BYTES:
		push_error("无法读取音效 " + path)
		return null
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes.slice(WAV_HEADER_BYTES)
	return stream
