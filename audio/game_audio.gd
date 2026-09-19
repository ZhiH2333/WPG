extends Object
class_name GameAudio

## 音效加载：导出后 res:// wav 会 remap 成 .sample，FileAccess 再也读不到 PCM。
## 优先 ResourceLoader；只有编辑器/headless 还能摸到原始 RIFF 时才走字节切片。
const MIX_RATE: int = 22050
const WAV_HEADER_BYTES: int = 44

static var _web_unlocked: bool = false

static func load_wav(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var loaded: Resource = ResourceLoader.load(path)
		var stream: AudioStream = loaded as AudioStream
		if stream != null:
			return stream
	return _load_pcm_wav(path)

static func format_playtime(elapsed_sec: float) -> String:
	var total: int = maxi(int(elapsed_sec), 0)
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var seconds: int = total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]

static func unlock_driver(host: Node) -> void:
	if host == null or not OS.has_feature("web") or _web_unlocked:
		return
	_web_unlocked = true
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.volume_db = -80.0
	player.stream = _make_silence()
	host.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

static func _load_pcm_wav(path: String) -> AudioStreamWAV:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() <= WAV_HEADER_BYTES:
		push_error("无法读取音效 " + path)
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		push_error("音效不是 PCM WAV " + path)
		return null
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes.slice(WAV_HEADER_BYTES)
	return stream

static func _make_silence() -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = PackedByteArray([0, 0, 0, 0])
	return stream
