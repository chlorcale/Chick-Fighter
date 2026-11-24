class_name AudioDirector
extends Node

## Đạo diễn âm thanh: nhạc nền (crossfade), jingle (ép nhỏ nhạc), ambience nhiều lớp,
## SFX one-shot, tiếng xe Dream của người chơi và emitter 2D cho vật thể di chuyển.
## File WAV sinh bởi tools/audio/generate_audio.py, nằm trong res://game/audio/.
## Một instance duy nhất (main.gd thêm vào cây); mọi hàm static là no-op an toàn khi chưa có instance.
## Bus "Music", "Ambience", "Sfx" được tạo lúc chạy bằng AudioServer (không sửa project.godot).

const DIR := "res://game/audio/"
const BUS_MUSIC := &"Music"
const BUS_AMB := &"Ambience"
const BUS_SFX := &"Sfx"
const LAYERS: Array[StringName] = [&"birds", &"leaves", &"river", &"crickets", &"crowd", &"village"]
const TRACKS: Array[StringName] = [&"village", &"title", &"memory", &"battle", &"final"]
const SFX_POOL := 12
const DUCK_LEVEL := 0.3
const LAYER_RATE := 2.0 # tốc độ mặc định (đơn vị gain/giây) cho ambience_layer gọi mỗi frame
const ENGINE_FADE := 6.0
## Mức mặc định của các bus (dB) — nhạc nằm dưới SFX/ thoại, ambience nằm dưới nhạc.
## set_volumes() nhân thêm (tuyến tính) lên trên các mức này.
const DEFAULT_BUS_DB := {&"Music": -9.0, &"Ambience": -6.0, &"Sfx": -4.0}
const ENGINE_TRIM_DB := -3.0 # xe Dream của người chơi: nhỏ hơn SFX thường một chút
const EMITTER_TRIM_DB := -3.0 # xe máy NPC/ ghe máy (emitter 2D)

static var instance: AudioDirector
static var _cache: Dictionary = {} # tên file → AudioStream (hoặc null nếu thiếu)
static var _variants: Dictionary = {} # tên sfx ngắn → Array[AudioStream]
static var _mult: Array[float] = [1.0, 1.0, 1.0] # hệ số người chơi (music, ambience, sfx)


## Một kênh có gain được làm mượt trong _process.
class Chan:
	var player: AudioStreamPlayer
	var gain: float = 0.0
	var target: float = 0.0
	var rate: float = 1.0
	var tag: StringName = &""

	func _init(p: AudioStreamPlayer) -> void:
		player = p


var _music: Array[Chan] = []
var _music_track: StringName = &""
var _jingle: AudioStreamPlayer
var _duck: float = 1.0
var _duck_time: float = 0.0
var _layers: Dictionary = {} # StringName → Chan
var _pool: Array[AudioStreamPlayer] = []
var _pool_next: int = 0
var _engine_idle: Chan
var _engine_run: Chan
var _engine_on: bool = false
var _engine_gain: float = 0.0
var _throttle: float = 0.0
var _throttle_target: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "AudioDirector"
	_rng.seed = 20240611
	_ensure_buses()
	_apply_bus_volumes()
	for i in range(2):
		_music.append(Chan.new(_new_player("Music%d" % i, BUS_MUSIC)))
	_jingle = _new_player("Jingle", BUS_MUSIC)
	for layer in LAYERS:
		var c := Chan.new(_new_player("Amb_%s" % layer, BUS_AMB))
		c.tag = layer
		_layers[layer] = c
	for i in range(SFX_POOL):
		_pool.append(_new_player("Sfx%d" % i, BUS_SFX))
	_engine_idle = Chan.new(_new_player("EngineIdle", BUS_SFX))
	_engine_run = Chan.new(_new_player("EngineRun", BUS_SFX))


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
		# nhả cache để không giữ tài nguyên khi thoát game (emitter đang sống vẫn giữ stream của nó)
		_cache.clear()
		_variants.clear()


# ===================================================================== API tĩnh

static func music(track: StringName, fade: float = 1.2) -> void:
	if is_instance_valid(instance):
		instance._play_music(track, fade)


static func jingle(jingle_name: StringName) -> void:
	if is_instance_valid(instance):
		instance._play_jingle(jingle_name)


static func ambience(levels: Dictionary, fade: float = 1.5) -> void:
	if is_instance_valid(instance):
		instance._set_ambience(levels, fade)


static func ambience_layer(layer: StringName, level: float) -> void:
	if is_instance_valid(instance):
		instance._set_layer(layer, level, LAYER_RATE)


static func sfx(sfx_name: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if is_instance_valid(instance):
		instance._play_sfx(sfx_name, volume_db, pitch)


static func engine(active: bool, throttle: float = 0.0) -> void:
	if is_instance_valid(instance):
		instance._engine_on = active
		instance._throttle_target = clampf(throttle, 0.0, 1.0)


static func make_emitter(sound: StringName, max_distance: float = 300.0, volume_db: float = 0.0) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.name = "Emitter_" + String(sound)
	var stream: AudioStream = null
	for file in ["loop_" + String(sound), String(sound), "amb_" + String(sound)]:
		stream = _load(file, true)
		if stream != null:
			break
	if stream == null:
		return player # dummy im lặng: không stream, không autoplay
	player.stream = stream
	player.max_distance = max_distance
	player.attenuation = 1.6
	player.volume_db = volume_db + EMITTER_TRIM_DB
	player.bus = _bus_or_master(BUS_SFX)
	player.autoplay = true
	# lệch pha ngẫu nhiên để nhiều emitter cùng loại không đồng pha
	var length := stream.get_length()
	player.ready.connect(func() -> void:
		if player.is_inside_tree() and length > 0.0:
			player.play(randf() * length), CONNECT_ONE_SHOT)
	return player


static func set_volumes(music_linear: float, ambience_linear: float, sfx_linear: float) -> void:
	_mult = [clampf(music_linear, 0.0, 1.0), clampf(ambience_linear, 0.0, 1.0), clampf(sfx_linear, 0.0, 1.0)]
	_apply_bus_volumes()


## Mức bus = mặc định (DEFAULT_BUS_DB) + hệ số người chơi; hệ số 0 → tắt tiếng bus.
static func _apply_bus_volumes() -> void:
	var buses: Array[StringName] = [BUS_MUSIC, BUS_AMB, BUS_SFX]
	for i in range(3):
		var idx := AudioServer.get_bus_index(buses[i])
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, float(DEFAULT_BUS_DB[buses[i]]) + linear_to_db(maxf(_mult[i], 0.0001)))
			AudioServer.set_bus_mute(idx, _mult[i] <= 0.0001)


# ===================================================================== nạp stream

static func _load(file: String, loop: bool) -> AudioStream:
	if _cache.has(file):
		return _cache[file]
	var path := DIR + file + ".wav"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream != null and loop:
		_ensure_loop(stream)
	_cache[file] = stream
	return stream


## Bật loop forward (0 → hết file) nếu import chưa bật (file có chunk smpl nên thường đã bật sẵn).
static func _ensure_loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null or wav.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		return
	var frames := int(round(wav.get_length() * float(wav.mix_rate)))
	wav.loop_begin = 0
	wav.loop_end = frames
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD


static func _sfx_streams(sfx_name: StringName) -> Array:
	if _variants.has(sfx_name):
		return _variants[sfx_name]
	var list: Array = []
	var base := "sfx_" + String(sfx_name)
	var single := _load(base, false)
	if single != null:
		list.append(single)
	else:
		for i in range(1, 9):
			var v := _load("%s_%d" % [base, i], false)
			if v == null:
				break
			list.append(v)
	_variants[sfx_name] = list
	return list


static func _bus_or_master(bus: StringName) -> StringName:
	return bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"


static func _ensure_buses() -> void:
	for bus in [BUS_MUSIC, BUS_AMB, BUS_SFX]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, &"Master")


func _new_player(player_name: String, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = player_name
	p.bus = _bus_or_master(bus)
	p.volume_db = -80.0
	add_child(p)
	return p


# ===================================================================== hiện thực

func _play_music(track: StringName, fade: float) -> void:
	if track == _music_track:
		return
	var rate := 1.0 / maxf(fade, 0.01)
	_music_track = track
	var stream: AudioStream = null
	if track != &"":
		stream = _load("music_" + String(track), true)
	# kênh đang chơi đúng bài này (vừa bị fade out) → kéo lên lại, không phát lại từ đầu
	for c in _music:
		if track != &"" and c.tag == track and c.player.playing:
			c.target = 1.0
			c.rate = rate
			for other in _music:
				if other != c:
					other.target = 0.0
					other.rate = rate
			return
	for c in _music:
		c.target = 0.0
		c.rate = rate
	if stream == null:
		return
	# chọn kênh nhỏ hơn để thay bài mới
	var free: Chan = _music[0] if _music[0].gain <= _music[1].gain else _music[1]
	free.player.stop()
	free.player.stream = stream
	free.tag = track
	free.gain = 0.0
	free.target = 1.0
	free.rate = rate
	free.player.volume_db = -80.0
	free.player.play()


func _play_jingle(jingle_name: StringName) -> void:
	var stream := _load("jingle_" + String(jingle_name), false)
	if stream == null:
		return
	_jingle.stream = stream
	_jingle.volume_db = 0.0
	_jingle.play()
	_duck_time = maxf(stream.get_length() - 0.4, 0.3)


func _set_ambience(levels: Dictionary, fade: float) -> void:
	var rate := 1.0 / maxf(fade, 0.01)
	for layer in LAYERS:
		_set_layer(layer, float(levels.get(layer, 0.0)), rate)


func _set_layer(layer: StringName, level: float, rate: float) -> void:
	var c: Chan = _layers.get(layer)
	if c == null:
		return
	c.target = clampf(level, 0.0, 1.0)
	c.rate = rate
	if c.target > 0.0 and not c.player.playing:
		var stream := _load("amb_" + String(layer), true)
		if stream == null:
			return
		c.player.stream = stream
		c.gain = 0.0
		c.player.volume_db = -80.0
		c.player.play(_rng.randf() * stream.get_length())


func _play_sfx(sfx_name: StringName, volume_db: float, pitch: float) -> void:
	var streams := _sfx_streams(sfx_name)
	if streams.is_empty():
		return
	var player: AudioStreamPlayer = null
	for i in range(SFX_POOL):
		var p: AudioStreamPlayer = _pool[(_pool_next + i) % SFX_POOL]
		if not p.playing:
			player = p
			break
	if player == null:
		player = _pool[_pool_next]
	_pool_next = (_pool_next + 1) % SFX_POOL
	player.stream = streams[_rng.randi_range(0, streams.size() - 1)]
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch, 0.05, 8.0)
	player.play()


func _process(delta: float) -> void:
	# ép nhỏ nhạc khi có jingle
	_duck_time = maxf(_duck_time - delta, 0.0)
	var duck_target := DUCK_LEVEL if _duck_time > 0.0 else 1.0
	_duck = move_toward(_duck, duck_target, delta * (5.0 if duck_target < _duck else 0.8))
	for c in _music:
		_step(c, delta, _duck)
	for layer in LAYERS:
		_step(_layers[layer], delta, 1.0)
	_process_engine(delta)


func _step(c: Chan, delta: float, mul: float) -> void:
	if not c.player.playing:
		return
	c.gain = move_toward(c.gain, c.target, c.rate * delta)
	c.player.volume_db = linear_to_db(maxf(c.gain * mul, 0.0001))
	if c.target <= 0.0 and c.gain <= 0.0:
		c.player.stop()
		c.tag = &""


func _process_engine(delta: float) -> void:
	var up := _throttle_target > _throttle
	_throttle = move_toward(_throttle, _throttle_target, delta * (2.5 if up else 1.5))
	_engine_gain = move_toward(_engine_gain, 1.0 if _engine_on else 0.0, delta * ENGINE_FADE)
	if _engine_gain <= 0.0:
		for c in [_engine_idle, _engine_run]:
			if c.player.playing:
				c.player.stop()
		return
	for pair in [[_engine_idle, "loop_bike_idle"], [_engine_run, "loop_bike_run"]]:
		var c: Chan = pair[0]
		if not c.player.playing:
			var stream := _load(pair[1], true)
			if stream == null:
				continue
			c.player.stream = stream
			c.player.play(_rng.randf() * stream.get_length())
	# idle → chạy: crossfade công suất đều, cao độ tăng mượt theo ga
	var x := clampf((_throttle - 0.08) / 0.32, 0.0, 1.0)
	var idle_gain := cos(x * PI * 0.5) * _engine_gain
	var run_gain := sin(x * PI * 0.5) * _engine_gain
	_engine_idle.gain = idle_gain
	_engine_run.gain = run_gain
	_engine_idle.player.volume_db = linear_to_db(maxf(idle_gain, 0.0001)) + ENGINE_TRIM_DB
	_engine_run.player.volume_db = linear_to_db(maxf(run_gain, 0.0001)) + ENGINE_TRIM_DB
	_engine_idle.player.pitch_scale = 1.0 + 1.5 * minf(_throttle, 0.4)
	_engine_run.player.pitch_scale = 0.75 + 0.4 * _throttle
