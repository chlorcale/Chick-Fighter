extends Node

## Tiếng động sinh bằng code cho màn tẩu thoát + cắt cảnh (theo cách của game/battle/sfx.gd): còi công an,
## còi hú (giả tiếng còi xe), tõm nước, sải tay bơi, vấp té, nhảy, trượt, gõ cửa, đóng cửa cái rầm, chén va
## lẻng kẻng, gà cục tác, thở hổn hển. Phát qua bus "Sfx" nếu có (AudioDirector tạo), không có thì Master.

const RATE: int = 22050

static var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	if _streams.is_empty():
		_build_all()
	var bus: StringName = &"Sfx" if AudioServer.get_bus_index(&"Sfx") >= 0 else &"Master"
	for i in range(8):
		var player := AudioStreamPlayer.new()
		player.bus = bus
		add_child(player)
		_players.append(player)


func play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(sound) or _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch, 0.1, 4.0)
	player.play()


func stop_all() -> void:
	for p in _players:
		p.stop()


static func clear_cache() -> void:
	_streams.clear()


static func has_sound(sound: StringName) -> bool:
	if _streams.is_empty():
		_build_all()
	return _streams.has(sound)


static func _build_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# Còi công an: "tuýt tuýt" – hai hồi, sóng vuông mềm ~2,9 kHz có rung (hạt bi trong còi).
	_streams[&"whistle"] = _make(0.62, func(t: float, _i: int) -> float:
		var gate: float = 1.0 if (t < 0.22 or (t > 0.3 and t < 0.6)) else 0.0
		var trill: float = 1.0 + 0.035 * sin(TAU * 34.0 * t)
		var tone: float = sin(TAU * 2900.0 * trill * t) * 0.7 + sin(TAU * 5800.0 * trill * t) * 0.12
		var env: float = minf(1.0, fmod(t, 0.3) * 60.0)
		return (tone + rng.randf_range(-1, 1) * 0.08) * gate * env * 0.32)
	# Còi hú (giả tiếng xe – công an chạy bộ nên tự "hú" bằng miệng, nhỏ và hơi buồn cười).
	_streams[&"siren"] = _make(1.6, func(t: float, _i: int) -> float:
		var ph: float = TAU * (620.0 * t - 260.0 / (TAU * 1.25) * cos(TAU * 1.25 * t))
		var env: float = minf(1.0, t * 6.0) * minf(1.0, (1.6 - t) * 5.0)
		return (sin(ph) * 0.5 + signf(sin(ph)) * 0.08) * env * 0.22)
	# Tõm nước lớn (nhảy sông).
	var low := [0.0]
	_streams[&"big_splash"] = _make(0.9, func(t: float, _i: int) -> float:
		low[0] = low[0] * 0.8 + rng.randf_range(-1, 1) * 0.2
		var body: float = sin(TAU * (180.0 - 120.0 * t) * t) * exp(-t * 9.0) * 0.6
		return (low[0] * 2.2 * exp(-t * 3.5) + rng.randf_range(-1, 1) * 0.25 * exp(-t * 7.0) + body) * 0.7)
	var low2 := [0.0]
	_streams[&"stroke"] = _make(0.22, func(t: float, _i: int) -> float:
		low2[0] = low2[0] * 0.7 + rng.randf_range(-1, 1) * 0.3
		return low2[0] * sin(PI * t / 0.22) * 0.55)
	# Vấp té: tiếng "bịch" + rổ rá lộn xộn.
	_streams[&"thud"] = _make(0.28, func(t: float, _i: int) -> float:
		var thump: float = sin(TAU * (95.0 - 60.0 * t) * t) * exp(-t * 16.0)
		var rattle: float = rng.randf_range(-1, 1) * exp(-t * 22.0) * (0.6 if fmod(t, 0.05) < 0.02 else 0.2)
		return (thump * 0.9 + rattle * 0.5) * 0.8)
	_streams[&"hop"] = _make(0.12, func(t: float, _i: int) -> float:
		return sin(TAU * (300.0 + 1800.0 * t) * t) * (1.0 - t / 0.12) * 0.25)
	_streams[&"skid"] = _make(0.4, func(t: float, _i: int) -> float:
		return rng.randf_range(-1, 1) * (0.35 + 0.15 * sin(TAU * 40.0 * t)) * minf(1.0, t * 30.0) * (1.0 - t / 0.4) * 0.5)
	# Gõ cửa: ba tiếng "cộc" gỗ.
	_streams[&"knock"] = _make(0.75, func(t: float, _i: int) -> float:
		var k: float = fmod(t, 0.22)
		if t > 0.66:
			return 0.0
		return (sin(TAU * 210.0 * k) * 0.8 + rng.randf_range(-1, 1) * 0.3) * exp(-k * 38.0) * 0.9)
	_streams[&"slam"] = _make(0.5, func(t: float, _i: int) -> float:
		return (sin(TAU * (120.0 - 50.0 * t) * t) * 0.9 + rng.randf_range(-1, 1) * 0.5 * exp(-t * 30.0)) * exp(-t * 9.0))
	# Chén va nhau "keng".
	_streams[&"clink"] = _make(0.35, func(t: float, _i: int) -> float:
		return (sin(TAU * 2350.0 * t) * 0.4 + sin(TAU * 3720.0 * t) * 0.25 + sin(TAU * 5110.0 * t) * 0.1) * exp(-t * 14.0))
	# Gà "cục tác" ngắn: chuỗi xung có formant.
	_streams[&"cluck"] = _make(0.38, func(t: float, _i: int) -> float:
		var syll: float = fmod(t, 0.13)
		var on: float = 1.0 if syll < 0.08 else 0.0
		var f0: float = 520.0 if t < 0.26 else 760.0
		var buzz: float = signf(sin(TAU * f0 * t)) * 0.4 + sin(TAU * f0 * 2.7 * t) * 0.3
		return buzz * on * exp(-syll * 14.0) * 0.28)
	# Thở hổn hển (nhiễu lọc, hai nhịp hít-thở).
	var low3 := [0.0]
	_streams[&"pant"] = _make(0.9, func(t: float, _i: int) -> float:
		low3[0] = low3[0] * 0.9 + rng.randf_range(-1, 1) * 0.1
		var beat: float = maxf(sin(TAU * 2.2 * t), 0.0)
		return low3[0] * 3.0 * beat * 0.5)
	# Trái cây rơi lộp độp.
	_streams[&"plop"] = _make(0.3, func(t: float, _i: int) -> float:
		var k: float = fmod(t, 0.1)
		return sin(TAU * (520.0 - 1500.0 * k) * k) * exp(-k * 40.0) * 0.4)
	# Ting ting (bọt xà bông vỡ / lấp lánh).
	_streams[&"twinkle"] = _make(0.4, func(t: float, _i: int) -> float:
		var note: float = [1568.0, 2093.0, 2637.0][mini(int(t / 0.12), 2)]
		return sin(TAU * note * t) * 0.15 * exp(-fmod(t, 0.12) * 20.0))


static func _make(duration: float, generator: Callable) -> AudioStreamWAV:
	var count: int = int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / float(RATE)
		var sample: float = clampf(float(generator.call(t, i)), -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
