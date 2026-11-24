class_name Sfx
extends Node

## Hiệu ứng âm thanh sinh bằng code (dự án chưa có asset audio).
## Thay bằng file thật sau này: chỉ cần đổi _streams[tên] sang AudioStream đã import.

const RATE: int = 22050

static var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	if _streams.is_empty():
		_build_all()
	for i in range(10):
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_players.append(player)


func play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(sound):
		return
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


static func _build_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_streams[&"hit_light"] = _make(0.09, func(t: float, _i: int) -> float:
		return (rng.randf_range(-1, 1) * 0.7 + sin(TAU * 190.0 * t) * 0.6) * exp(-t * 45.0))
	_streams[&"hit_heavy"] = _make(0.18, func(t: float, _i: int) -> float:
		return (rng.randf_range(-1, 1) * 0.6 + sin(TAU * (110.0 - 200.0 * t) * t) * 0.9) * exp(-t * 20.0))
	_streams[&"hit_special"] = _make(0.42, func(t: float, _i: int) -> float:
		var crack: float = rng.randf_range(-1, 1) * exp(-t * 9.0)
		return (crack * 0.7 + sin(TAU * (160.0 - 220.0 * t) * t) * exp(-t * 6.0)) * 0.9)
	_streams[&"block"] = _make(0.12, func(t: float, _i: int) -> float:
		return (sin(TAU * 980.0 * t) * 0.5 + sin(TAU * 1460.0 * t) * 0.35 + rng.randf_range(-1, 1) * 0.25) * exp(-t * 30.0))
	_streams[&"whiff"] = _make(0.11, func(t: float, _i: int) -> float:
		return rng.randf_range(-1, 1) * sin(PI * t / 0.11) * 0.35)
	_streams[&"jump"] = _make(0.07, func(t: float, _i: int) -> float:
		return sin(TAU * (260.0 + 2400.0 * t) * t) * (1.0 - t / 0.07) * 0.3)
	_streams[&"land"] = _make(0.08, func(t: float, _i: int) -> float:
		return (sin(TAU * 75.0 * t) * 0.8 + rng.randf_range(-1, 1) * 0.3) * exp(-t * 40.0))
	_streams[&"dash"] = _make(0.16, func(t: float, _i: int) -> float:
		return rng.randf_range(-1, 1) * sin(PI * t / 0.16) * 0.3)
	_streams[&"card"] = _make(0.3, func(t: float, _i: int) -> float:
		var note: float = [784.0, 988.0, 1318.0][mini(int(t / 0.1), 2)]
		return signf(sin(TAU * note * t)) * 0.18 * exp(-fmod(t, 0.1) * 18.0))
	_streams[&"super"] = _make(0.55, func(t: float, _i: int) -> float:
		return (sin(TAU * (200.0 + 900.0 * t) * t) * 0.5 + rng.randf_range(-1, 1) * 0.25 * t) * minf(1.0, (0.55 - t) * 8.0))
	_streams[&"guard_break"] = _make(0.5, func(t: float, _i: int) -> float:
		return (sin(TAU * 520.0 * t) * sin(TAU * 7.0 * t) * 0.6 + rng.randf_range(-1, 1) * 0.4) * exp(-t * 5.0))
	_streams[&"ko"] = _make(1.6, func(t: float, _i: int) -> float:
		return (sin(TAU * 523.0 * t) * 0.45 + sin(TAU * 784.0 * t) * 0.3 + sin(TAU * 1046.0 * t) * 0.15) * exp(-t * 2.2))
	_streams[&"bell"] = _make(1.0, func(t: float, _i: int) -> float:
		return (sin(TAU * 440.0 * t) * 0.45 + sin(TAU * 1108.0 * t) * 0.2) * exp(-t * 3.0))
	_streams[&"select"] = _make(0.05, func(t: float, _i: int) -> float:
		return signf(sin(TAU * 1200.0 * t)) * 0.15 * (1.0 - t / 0.05))
	_streams[&"confirm"] = _make(0.14, func(t: float, _i: int) -> float:
		return signf(sin(TAU * (880.0 if t < 0.06 else 1320.0) * t)) * 0.16 * (1.0 - t / 0.14))
	# Khán giả reo (nhiễu lọc thấp + nhịp hò) – thay bằng âm thanh thật khi có.
	var low := [0.0]
	_streams[&"cheer"] = _make(1.4, func(t: float, _i: int) -> float:
		low[0] = low[0] * 0.92 + rng.randf_range(-1, 1) * 0.08
		var swell: float = minf(1.0, t * 5.0) * exp(-maxf(0.0, t - 0.5) * 2.2)
		var chant: float = 0.7 + 0.3 * sin(TAU * 5.5 * t)
		return (low[0] * 3.2 + rng.randf_range(-1, 1) * 0.12) * swell * chant * 0.8)
	_streams[&"heartbeat"] = _make(0.42, func(t: float, _i: int) -> float:
		var beat1: float = sin(TAU * 52.0 * t) * exp(-t * 28.0)
		var t2: float = maxf(0.0, t - 0.16)
		var beat2: float = sin(TAU * 46.0 * t2) * exp(-t2 * 24.0) * (1.0 if t > 0.16 else 0.0)
		return (beat1 + beat2 * 0.8) * 0.9)
	# Còi công an (hai tiếng tu huýt trill), còi hú xe công an, luồng gió Quạt lông.
	_streams[&"whistle"] = _make(0.7, func(t: float, _i: int) -> float:
		var on: float = 1.0 if fmod(t, 0.35) < 0.26 else 0.0
		var trill: float = 2900.0 + 180.0 * signf(sin(TAU * 32.0 * t))
		return sin(TAU * trill * t) * on * 0.22 * minf(1.0, (0.7 - t) * 10.0))
	var siren_phase := [0.0]
	_streams[&"siren"] = _make(1.6, func(t: float, _i: int) -> float:
		var freq: float = 640.0 + 360.0 * (0.5 + 0.5 * sin(TAU * 1.25 * t))
		siren_phase[0] += TAU * freq / float(RATE)
		return signf(sin(siren_phase[0])) * 0.1 * minf(1.0, t * 8.0) * minf(1.0, (1.6 - t) * 4.0))
	var wind := [0.0]
	_streams[&"gust"] = _make(0.45, func(t: float, _i: int) -> float:
		wind[0] = wind[0] * 0.85 + rng.randf_range(-1, 1) * 0.15
		return wind[0] * 2.4 * sin(PI * t / 0.45) * (0.7 + 0.3 * sin(TAU * 9.0 * t)))
	_streams[&"cricket"] = _make(1.2, func(t: float, _i: int) -> float:
		var chirp: float = 1.0 if fmod(t, 0.4) < 0.12 and fmod(t * 60.0, 1.0) < 0.5 else 0.0
		return sin(TAU * 4300.0 * t) * chirp * 0.08)


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
