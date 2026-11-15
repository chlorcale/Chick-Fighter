extends SceneTree

## Smoke test âm thanh: file WAV trong game/audio/ tồn tại + nạp được, loop đúng chế độ,
## AudioDirector chạy mọi API headless không lỗi.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_audio_smoke.gd

const Director := preload("res://game/audio/audio_director.gd")

## tên file → [độ dài tối thiểu, tối đa (giây), loop?]
const FILES := {
	"music_village": [80.0, 100.0, true], "music_title": [50.0, 60.0, true], "music_memory": [36.0, 44.0, true],
	"music_battle": [56.0, 64.0, true], "music_final": [56.0, 64.0, true],
	"jingle_victory": [3.0, 5.0, false], "jingle_defeat": [2.0, 4.0, false], "jingle_reward": [1.0, 2.0, false],
	"amb_birds": [12.0, 24.0, true], "amb_leaves": [12.0, 24.0, true], "amb_river": [12.0, 24.0, true],
	"amb_crickets": [12.0, 24.0, true], "amb_crowd": [12.0, 24.0, true], "amb_village": [12.0, 24.0, true],
	"loop_bike_idle": [1.0, 6.0, true], "loop_bike_run": [1.0, 6.0, true], "loop_npc_bike": [1.0, 6.0, true],
	"loop_boat": [1.0, 6.0, true],
	"sfx_bike_start": [0.6, 1.6, false], "sfx_bike_stop": [0.3, 1.0, false], "sfx_bike_horn": [0.2, 1.0, false],
	"sfx_step_dirt_1": [0.05, 0.4, false], "sfx_step_dirt_2": [0.05, 0.4, false], "sfx_step_dirt_3": [0.05, 0.4, false],
	"sfx_step_wood_1": [0.05, 0.4, false], "sfx_step_wood_2": [0.05, 0.4, false],
	"sfx_splash_1": [0.2, 1.5, false], "sfx_splash_2": [0.2, 1.5, false], "sfx_fish_jump": [0.2, 1.0, false],
	"sfx_coin": [0.2, 1.0, false], "sfx_harvest": [0.2, 1.0, false], "sfx_brick": [0.1, 1.0, false],
	"sfx_school_bell": [1.5, 3.5, false], "sfx_temple_bell": [2.0, 6.0, false], "sfx_rooster_crow": [1.0, 2.0, false],
	"sfx_ferry_creak": [0.5, 2.0, false], "sfx_paddle": [0.3, 1.2, false], "sfx_ui_move": [0.02, 0.2, false],
	"sfx_ui_confirm": [0.1, 0.8, false], "sfx_dialog_blip": [0.02, 0.2, false], "sfx_levelup": [0.8, 2.0, false],
}
const SFX_NAMES: Array[StringName] = [&"step_dirt", &"step_wood", &"splash", &"fish_jump", &"coin", &"harvest",
	&"brick", &"school_bell", &"temple_bell", &"rooster_crow", &"ferry_creak", &"paddle", &"ui_move",
	&"ui_confirm", &"dialog_blip", &"levelup", &"bike_start", &"bike_stop", &"bike_horn"]

var _failures: int = 0
var _frames: int = 0
var _step: int = 0
var _dir: Director
var _emitter: AudioStreamPlayer2D
var _t_free: int = 0


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	# 1) file: tồn tại, nạp được, độ dài hợp lý; loop được import sẵn từ chunk smpl
	var missing: Array[String] = []
	var bad_len: Array[String] = []
	var baked := 0
	var loops := 0
	for file: String in FILES:
		var path := "res://game/audio/%s.wav" % file
		if not ResourceLoader.exists(path):
			missing.append(file)
			continue
		var s := load(path) as AudioStream
		if s == null:
			missing.append(file)
			continue
		var spec: Array = FILES[file]
		var length := s.get_length()
		if length < float(spec[0]) or length > float(spec[1]):
			bad_len.append("%s=%.2fs" % [file, length])
		var wav := s as AudioStreamWAV
		if bool(spec[2]):
			loops += 1
			if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_begin == 0 \
					and absi(wav.loop_end - int(round(length * wav.mix_rate))) <= 1:
				baked += 1
		elif wav != null:
			_check(wav.loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shot does not loop: " + file)
	_check(missing.is_empty(), "all %d audio files exist and load as AudioStream %s" % [FILES.size(), str(missing)])
	_check(bad_len.is_empty(), "all lengths within expected bounds %s" % str(bad_len))
	_check(baked == loops, "import baked forward loop 0..end from WAV smpl chunk (%d/%d)" % [baked, loops])

	# 2) static API an toàn khi chưa có instance
	Director.music(&"village")
	Director.sfx(&"coin")
	Director.engine(true, 0.5)
	Director.ambience({&"birds": 1.0})
	Director.ambience_layer(&"river", 0.5)
	Director.jingle(&"victory")
	_check(Director.instance == null, "static calls are no-ops without an instance")

	_dir = Director.new()
	root.add_child(_dir)
	_check(_dir.process_mode == Node.PROCESS_MODE_ALWAYS, "director processes while paused")
	_check(AudioServer.get_bus_index(&"Music") >= 0 and AudioServer.get_bus_index(&"Ambience") >= 0
		and AudioServer.get_bus_index(&"Sfx") >= 0, "runtime buses Music/Ambience/Sfx exist")
	var defaults_ok := true
	for bus: StringName in Director.DEFAULT_BUS_DB:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0 or absf(AudioServer.get_bus_volume_db(idx) - float(Director.DEFAULT_BUS_DB[bus])) > 0.01:
			defaults_ok = false
	_check(defaults_ok, "quieter default bus levels applied (Music -9, Ambience -6, Sfx -4 dB)")
	_check(Director.DEFAULT_BUS_DB[&"Music"] < Director.DEFAULT_BUS_DB[&"Sfx"], "music sits under sfx by default")


func _music_playing() -> Array:
	var out: Array = []
	for c in _dir._music:
		if c.player.playing:
			out.append(c)
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	match _step:
		0:
			_check(Director.instance == _dir, "instance set on enter_tree")
			Director.music(&"village")
			_next()
		1:
			if _frames < 90:
				return false
			var playing := _music_playing()
			_check(playing.size() == 1 and playing[0].tag == &"village", "music village plays")
			var wav := playing[0].player.stream as AudioStreamWAV if playing.size() > 0 else null
			_check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music stream loops forward at play time")
			_check(playing.size() > 0 and playing[0].gain > 0.99, "music faded in to full gain")
			var before: AudioStreamPlayer = playing[0].player if playing.size() > 0 else null
			var pos := before.get_playback_position() if before else 0.0
			Director.music(&"village")
			_check(before != null and before.playing and before.get_playback_position() >= pos, "same track is a no-op")
			Director.music(&"battle", 0.5)
			_next()
		2:
			if _frames == 10:
				_check(_music_playing().size() == 2, "crossfade: both tracks audible during fade")
			if _frames < 60:
				return false
			var playing := _music_playing()
			_check(playing.size() == 1 and playing[0].tag == &"battle", "crossfade to battle finished, old track stopped")
			Director.jingle(&"victory")
			Director.jingle(&"missing_jingle")
			_next()
		3:
			if _frames == 30:
				_check(_dir._jingle.playing, "jingle plays")
				_check(_dir._duck < 0.5, "jingle ducks music (duck=%.2f)" % _dir._duck)
			if _frames < 60:
				return false
			Director.music(&"")
			Director.ambience({&"birds": 0.8, &"leaves": 0.5, &"river": 0.2}, 0.5)
			_next()
		4:
			if _frames < 90:
				return false
			_check(_music_playing().is_empty(), "music(&\"\") fades out and stops")
			var amb: Dictionary = _dir._layers
			_check(amb[&"birds"].player.playing and is_equal_approx(amb[&"birds"].gain, 0.8), "ambience birds at 0.8")
			_check(amb[&"leaves"].player.playing and amb[&"river"].player.playing, "ambience leaves + river playing")
			_check(not amb[&"crowd"].player.playing, "unmentioned layer stays silent")
			var aw := amb[&"birds"].player.stream as AudioStreamWAV
			_check(aw != null and aw.loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambience loops forward")
			Director.ambience({&"crowd": 1.0}, 0.3)
			_next()
		5:
			Director.ambience_layer(&"river", 0.6) # gọi mỗi frame như river-by-distance
			if _frames < 60:
				return false
			var amb: Dictionary = _dir._layers
			_check(not amb[&"birds"].player.playing, "ambience(): layers not mentioned fade to 0 and stop")
			_check(amb[&"crowd"].player.playing and is_equal_approx(amb[&"crowd"].gain, 1.0), "crowd faded in")
			_check(amb[&"river"].player.playing and is_equal_approx(amb[&"river"].gain, 0.6), "ambience_layer sets one layer smoothly")
			Director.ambience_layer(&"nonexistent_layer", 1.0)
			# SFX
			var before := _count_sfx_playing()
			Director.sfx(&"no_such_sound")
			Director.sfx(&"")
			_check(_count_sfx_playing() == before, "unknown sfx names are ignored")
			var ok := true
			for n in SFX_NAMES:
				var streams: Array = Director._sfx_streams(n)
				if streams.is_empty():
					ok = false
					print("  missing sfx: ", n)
			_check(ok, "every sfx short name resolves to a stream")
			_check(Director._sfx_streams(&"step_dirt").size() == 3 and Director._sfx_streams(&"step_wood").size() == 2,
				"footstep variants found (3 dirt, 2 wood)")
			for n in SFX_NAMES:
				Director.sfx(n, -6.0, 1.1)
			_check(_count_sfx_playing() >= mini(SFX_NAMES.size(), Director.SFX_POOL) - 4, "sfx pool plays (%d playing)" % _count_sfx_playing())
			Director.engine(true, 0.0)
			_next()
		6:
			Director.engine(true, 0.0)
			if _frames < 30:
				return false
			_check(_dir._engine_idle.player.playing and _dir._engine_idle.gain > 0.9, "engine idle audible at throttle 0")
			var iw := _dir._engine_idle.player.stream as AudioStreamWAV
			_check(iw != null and iw.loop_mode == AudioStreamWAV.LOOP_FORWARD, "engine idle loops forward")
			_next()
		7:
			Director.engine(true, 1.0)
			if _frames < 60:
				return false
			_check(_dir._engine_run.gain > 0.9 and _dir._engine_idle.gain < 0.1, "throttle 1 crossfades to run loop")
			_check(_dir._engine_run.player.pitch_scale > 1.1, "throttle raises pitch (%.2f)" % _dir._engine_run.player.pitch_scale)
			_next()
		8:
			Director.engine(false)
			if _frames < 30:
				return false
			_check(not _dir._engine_idle.player.playing and not _dir._engine_run.player.playing, "engine(false) silences the bike")
			_emitter = Director.make_emitter(&"npc_bike", 250.0, -3.0)
			_check(_emitter is AudioStreamPlayer2D and _emitter.stream != null, "make_emitter(npc_bike) returns a 2D player with a stream")
			_check(_emitter.autoplay and is_equal_approx(_emitter.max_distance, 250.0), "emitter autoplay + max_distance configured")
			_check(is_equal_approx(_emitter.volume_db, -3.0 + Director.EMITTER_TRIM_DB), "emitter volume = caller dB + emitter trim")
			var ew := _emitter.stream as AudioStreamWAV
			_check(ew != null and ew.loop_mode == AudioStreamWAV.LOOP_FORWARD, "emitter stream loops forward")
			root.add_child(_emitter)
			var boat := Director.make_emitter(&"boat")
			_check(boat.stream != null, "make_emitter(boat) has a stream")
			boat.free()
			var dummy := Director.make_emitter(&"no_such_loop")
			_check(dummy is AudioStreamPlayer2D and dummy.stream == null and not dummy.autoplay, "missing emitter sound → silent dummy")
			dummy.free()
			Director.set_volumes(0.5, 0.0, 1.0)
			_next()
		9:
			if _frames < 5:
				return false
			_check(_emitter.playing, "emitter plays once parented")
			var mi := AudioServer.get_bus_index(&"Music")
			var ai := AudioServer.get_bus_index(&"Ambience")
			_check(absf(AudioServer.get_bus_volume_db(mi) - (float(Director.DEFAULT_BUS_DB[&"Music"]) + linear_to_db(0.5))) < 0.01,
				"set_volumes multiplies on top of the Music default")
			_check(AudioServer.is_bus_mute(ai), "set_volumes 0 mutes Ambience bus")
			Director.set_volumes(1.0, 1.0, 1.0)
			_check(absf(AudioServer.get_bus_volume_db(mi) - float(Director.DEFAULT_BUS_DB[&"Music"])) < 0.01 and not AudioServer.is_bus_mute(ai),
				"set_volumes(1,1,1) restores defaults and unmutes")
			# chạy khi tạm dừng
			Director.music(&"title", 0.2)
			paused = true
			_next()
		10:
			if _frames < 30:
				return false
			var playing := _music_playing()
			_check(playing.size() == 1 and playing[0].tag == &"title" and playing[0].gain > 0.99, "music crossfades while the tree is paused")
			paused = false
			_emitter.queue_free()
			_dir.queue_free()
			_next()
		11:
			# chờ thời gian thực để luồng trộn của AudioServer nhả các playback đã dừng
			# (--fixed-fps chạy frame nhanh hơn thời gian thực)
			if _frames == 1:
				_t_free = Time.get_ticks_msec()
			if Time.get_ticks_msec() - _t_free < 400:
				return false
			_check(Director.instance == null, "instance cleared on exit_tree")
			Director.music(&"village")
			Director.sfx(&"coin")
			Director.engine(true, 1.0)
			_check(true, "static calls after free are no-ops")
			print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
			quit(1 if _failures > 0 else 0)
			return true
	return false


func _count_sfx_playing() -> int:
	var n := 0
	for p in _dir._pool:
		if p.playing:
			n += 1
	return n


func _next() -> void:
	_step += 1
	_frames = 0
