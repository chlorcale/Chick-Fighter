extends SceneTree

## Smoke test lớp game/: khám phá (4 hướng, xe máy, đò qua sông) và bộ chiêu trong trận.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_game_smoke.gd

var _failures: int = 0
var _frames: int = 0
var _step: int = 0
var _world: World
var _start: Vector2
var _director: BattleDirector
var _max_combo: int = 0
var _hp_before: Array[int] = []
var _result: Dictionary = {}
var _seen: Dictionary = {}
const AiRunner = preload("res://tests/game/ai_match_runner.gd")
var _runner: Node
var _batch: Array = []


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	_world = World.new()
	root.add_child(_world)


func _new_battle(p_side: Dictionary, o_side: Dictionary, mode: String = "normal") -> void:
	if _director != null:
		_director.queue_free()
	_director = BattleDirector.new()
	_director.setup({"player": p_side, "opponent": o_side, "mode": mode, "seed": 5})
	root.add_child(_director)
	_director.finished.connect(func(r: Dictionary) -> void: _result = r)
	_result = {}
	_seen = {}


func _side(breed: int = 0) -> Dictionary:
	return {"owner": "T", "name": "Gà", "breed": breed, "lv": 3, "cards": [&"cuong_no", &"mai_rua", &"gio_song"]}


func _p(i: int) -> BattleDirector.Fighter:
	return _director.fighters[i]


func _setup_duel(x0: float, x1: float, ai_mode: int = EnemyAI.Mode.IDLE) -> void:
	_director.phase = BattleDirector.Phase.FIGHT
	_director.fighters[1].ai.script_mode = ai_mode
	_p(0).body.global_position = Vector2(x0, -1)
	_p(1).body.global_position = Vector2(x1, -1)


func _tap(i: int, bit: int, at: int, now: int) -> void:
	if now == at:
		_p(i).source.push_event(bit, true)
	elif now == at + 2:
		_p(i).source.push_event(bit, false)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	match _step:
		# ---------------------------------------------------------------- khám phá
		0:
			if _frames < 3:
				return false
			var p: WorldPlayer = _world.player
			_check(not p._blocked_at(World.SPAWN), "spawn is walkable")
			_check(_world.is_blocked(300, 400), "river is blocked")
			_check(_world.is_blocked(100, 60), "house is blocked")
			_check(not _world.is_blocked(660, 580), "canal road bridge is walkable")
			_check(_world.map_view.frame_count == 96 and _world.map_view.frame_ms == 80, "map runs all 96 frames at 80 ms")
			_check(_world.map_view._animated.size() > 100, "map has animated layers (%d)" % _world.map_view._animated.size())
			_check(is_equal_approx(p._sprite.scale.x, WorldPlayer.SPRITE_SCALE), "player drawn at NPC scale")
			_start = p.position
			Input.action_press(&"p1_right")
			_next()
		1:
			if _frames < 60:
				return false
			var p: WorldPlayer = _world.player
			_check(p.position.x > _start.x + 50.0 and is_equal_approx(p.position.y, _start.y), "walk right only changes x")
			_start = p.position
			Input.action_press(&"p1_crouch")
			_next()
		2:
			if _frames < 30:
				return false
			var moved: Vector2 = _world.player.position - _start
			_check(moved.x == 0.0 and moved.y > 0.0, "no diagonal; last pressed direction wins (moved %s)" % moved)
			Input.action_release(&"p1_right")
			_next()
		3:
			if _frames < 400:
				return false
			_check(_world.player.position.y < 285.0, "river bank stops the player (y=%.0f)" % _world.player.position.y)
			Input.action_release(&"p1_crouch")
			# Xe máy: đi nhanh hơn.
			_world.player.position = Vector2(300, 220)
			_world.mount_bike(true)
			_start = _world.player.position
			Input.action_press(&"p1_right")
			_next()
		4:
			if _frames < 60:
				return false
			Input.action_release(&"p1_right")
			var dist: float = _world.player.position.x - _start.x
			_check(_world.player.riding and dist > 150.0, "motorbike moves faster (%.0f px/s)" % dist)
			_world.mount_bike(false)
			_check(not _world.player.riding and _world._bike_node.visible, "dismount leaves the bike parked")
			_world.player.position = World.FERRY_NORTH
			_world.ride_ferry(true)
			_next()
		5:
			if _frames < 240:
				return false
			_check(_world.player.position.distance_to(World.FERRY_SOUTH) < 2.0 and _world.player.can_move, "ferry crosses the river")
			_check(not _world.player._blocked_at(World.FERRY_SOUTH), "south bank is walkable")
			_world.queue_free()
			_new_battle(_side(), _side())
			_next()
		# ---------------------------------------------------------------- trận
		6:
			# Combo 1: J → J (Đá Nhẹ) → K → L.
			if _frames == 2:
				_setup_duel(450, 560)
			for pair in [[4, InputBits.LIGHT], [13, InputBits.LIGHT], [22, InputBits.HEAVY], [32, InputBits.SPECIAL]]:
				_tap(0, int(pair[1]), int(pair[0]), _frames)
			_max_combo = maxi(_max_combo, _p(0).combo_hits)
			if _p(0).move.get("id", &"") == &"da_nhe":
				_seen["da_nhe"] = true
			if _p(1).react == &"te":
				_seen["te"] = true
			if _frames == 140:
				_check(_max_combo >= 4, "J J K L chains into a 4-hit combo (max %d)" % _max_combo)
				_check(_seen.has("da_nhe"), "second J in a chain becomes Đá Nhẹ")
				_check(_seen.has("te"), "Đá Cựa Bay knocks down (TE_NgaNgua)")
				_new_battle(_side(), _side())
				_next()
		7:
			# Cựa Hất hất tung rồi đối thủ nằm → đứng dậy.
			if _frames == 2:
				_setup_duel(450, 560)
				_p(0).source.push_event(InputBits.CROUCH, true)
			_tap(0, InputBits.SPECIAL, 4, _frames)
			if _frames == 8:
				_p(0).source.push_event(InputBits.CROUCH, false)
			if _p(1).react == &"vang" and _p(1).airborne:
				_seen["air"] = true
			if _p(1).react == &"nam":
				_seen["nam"] = true
			if _p(1).react == &"dung":
				_seen["dung"] = true
			if _frames == 200:
				_check(_seen.has("air"), "↓+L Cựa Hất launches the opponent into the air")
				_check(_seen.has("nam") and _seen.has("dung"), "launched opponent lies down then gets up")
				_new_battle(_side(), _side())
				_next()
		8:
			# Mổ Liên Hoàn (1 vạch) bấm H liên tục.
			if _frames == 2:
				_setup_duel(450, 560)
				_p(0).special.add_points(100)
				_hp_before = [_p(1).hp()]
			for t in range(4, 80, 6):
				_tap(0, InputBits.ACTION_H, t, _frames)
			if _p(0).loops >= 1:
				_seen["loop"] = true
			if _frames == 200:
				_check(int(_p(0).track["rush"]) == 1, "H starts Mổ Liên Hoàn")
				_check(_seen.has("loop"), "mashing H repeats the rush loop")
				_check(_p(0).special.get_available_bars() == 1, "rush costs 1 bar (bars left %d)" % _p(0).special.get_available_bars())
				_check(_hp_before[0] - _p(1).hp() >= 10, "rush deals multi-hit damage (%d)" % (_hp_before[0] - _p(1).hp()))
				_new_battle(_side(), _side())
				_next()
		9:
			# Phun Lông (↓+H) và Lốc Xoáy Cánh (←+H, 2 vạch, không đỡ được).
			if _frames == 2:
				_setup_duel(300, 700)
				_p(0).source.push_event(InputBits.CROUCH, true)
			_tap(0, InputBits.ACTION_H, 4, _frames)
			if _frames == 8:
				_p(0).source.push_event(InputBits.CROUCH, false)
			if not _director.projectiles.is_empty():
				_seen["proj"] = true
			if _frames == 100:
				_check(_seen.has("proj"), "↓+H spawns a feather projectile")
				_check(_p(1).hp() < _p(1).body.health_max_hp, "projectile hits at range")
				_p(0).special.add_points(250)
				_p(0).body.global_position.x = 500
				_p(1).body.global_position.x = 640
				_p(1).body.clear_hit_reactions()
				_p(1).react = &""
				_p(1).source.push_event(InputBits.MOVE_RIGHT, true) # giữ lùi để đỡ
				_p(0).source.push_event(InputBits.MOVE_LEFT, true)
				_hp_before = [_p(1).hp()]
			_tap(0, InputBits.ACTION_H, 104, _frames)
			if _frames == 107:
				_p(0).source.push_event(InputBits.MOVE_LEFT, false)
			if _p(0).move.get("id", &"") == &"loc_xoay_canh":
				_seen["super"] = true
			if _frames == 260:
				_check(_seen.has("super"), "←+H with 2 bars starts Lốc Xoáy Cánh")
				_check(_p(1).hp() < _hp_before[0] - 5, "super is unblockable (hp %d → %d)" % [_hp_before[0], _p(1).hp()])
				_new_battle(_side(), _side())
				_next()
		10:
			# Đỡ theo hướng + tầng đòn + va chạm đòn.
			if _frames == 2:
				_setup_duel(450, 560, EnemyAI.Mode.SLOW_ATTACK)
				_p(0).source.push_event(InputBits.MOVE_LEFT, true)
				_hp_before = [_p(0).hp()]
			if _frames == 200:
				var p: BattleDirector.Fighter = _p(0)
				var o: BattleDirector.Fighter = _p(1)
				_check(int(p.track["blocks"]) >= 1, "holding back blocks (%d blocks)" % int(p.track["blocks"]))
				_check(_hp_before[0] - p.hp() <= int(p.track["blocks"]) * BattleDirector.CHIP_DAMAGE, "blocked hits only deal 1 HP chip")
				var low: Dictionary = Moves.get_move(&"mo_thap")
				var high: Dictionary = Moves.get_move(&"air_j")
				var mid: Dictionary = Moves.get_move(&"mo_nhanh")
				var sup: Dictionary = Moves.get_move(&"loc_xoay_canh")
				p.move = {}
				p.react = &""
				p.held = 1 << InputBits.MOVE_LEFT
				_check(_director._guard_result(p, o, mid["hits"][0], mid) == 1, "standing guard blocks mid")
				_check(_director._guard_result(p, o, low["hits"][0], low) == 0, "standing guard loses to low")
				_check(_director._guard_result(p, o, sup["hits"][0], sup) == 0, "super cannot be guarded")
				p.held = (1 << InputBits.MOVE_LEFT) | (1 << InputBits.CROUCH)
				_check(_director._guard_result(p, o, low["hits"][0], low) == 1, "crouch guard blocks low")
				_check(_director._guard_result(p, o, high["hits"][0], high) == 0, "crouch guard loses to high")
				p.guard = 5.0
				_check(_director._guard_result(p, o, mid["hits"][0], mid) == 2, "low Block Gauge causes Guard Break")
				_new_battle(_side(), _side())
				_next()
		11:
			if _frames == 2:
				_setup_duel(430, 570)
				_hp_before = [_p(0).hp(), _p(1).hp()]
			_tap(0, InputBits.LIGHT, 4, _frames)
			_tap(1, InputBits.LIGHT, 4, _frames)
			if _frames == 40:
				_check(_p(0).hp() == _hp_before[0] and _p(1).hp() == _hp_before[1], "simultaneous hitboxes clash: no damage")
				_new_battle(_dt_side(), _side())
				_next()
		12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23:
			if _dongtao_step():
				_new_battle(_side(), _side())
				_step = 24
				_frames = 0
		24, 25, 26, 27:
			if _rounds_step():
				var opponent: Dictionary = GameState.OPPONENTS["teo_2"].duplicate(true)
				_new_battle({"owner": "Test", "name": "Ô Mun", "breed": 0, "lv": 3, "dao_chan": true,
					"cards": [&"cuong_no", &"mai_rua", &"gio_song"]}, opponent)
				_step = 40
				_frames = 0
		40:
			if _frames == 5:
				var c: BattleDirector.Fighter = _p(0)
				c.source.configure({})
				c.ai = EnemyAI.new()
				c.ai.configure({"tier": 2, "aggr": 0.9, "block": 0.3}, 7)
			_track_crowd()
			# Trận nhiều hiệp (best-of-3 + mở màn) dài hơn trận 1 hiệp cũ: giới hạn 125 s → giới hạn kẹt trận của runner.
			if not _result.is_empty() or _frames > AiRunner.FRAME_LIMIT:
				_check(not _result.is_empty(), "AI-vs-AI battle finished (frames=%d)" % _frames)
				var hp: Array = [_p(0).hp(), _p(1).hp()]
				_check(hp[0] < _p(0).body.health_max_hp or hp[1] < _p(1).body.health_max_hp, "damage was dealt (hp %s)" % str(hp))
				_crowd_checks()
				print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
				quit(1 if _failures > 0 else 0)
				return true
	return false


func _next() -> void:
	_step += 1
	_frames = 0


# ==================================================================== Gà Đông Tảo (kit "dongtao")

func _dt_side(lv: int = 3) -> Dictionary:
	return {"owner": "T", "name": "Mun", "breed": 2, "lv": lv}


func _logged(attacker: int, move_id: String) -> Array:
	var out: Array = []
	for entry in _director.hit_log:
		if int(entry[1]) == attacker and String(entry[2]) == move_id:
			out.append(entry)
	return out


## Bấm một nút ngay bây giờ, tự nhả sau 2 frame.
func _press(i: int, bit: int) -> void:
	_p(i).source.push_event(bit, true)
	_seen["release_%d_%d" % [i, bit]] = _frames + 2


func _release_due() -> void:
	for key in _seen.keys():
		if String(key).begins_with("release_") and int(_seen[key]) == _frames:
			var parts: PackedStringArray = String(key).split("_")
			_p(int(parts[1])).source.push_event(int(parts[2]), false)


## Giữ đúng tập bit `wanted` cho bên i (như AI đẩy input).
func _hold(i: int, wanted: int) -> void:
	var key: String = "held_%d" % i
	var before: int = int(_seen.get(key, 0))
	var changed: int = before ^ wanted
	for bit in range(InputBits.COUNT):
		if (changed & (1 << bit)) != 0:
			_p(i).source.push_event(bit, (wanted & (1 << bit)) != 0)
	_seen[key] = wanted


## Trả về true khi đã xong toàn bộ test Đông Tảo.
func _dongtao_step() -> bool:
	_release_due()
	var d: BattleDirector.Fighter = _p(0) if not _director.fighters.is_empty() else null
	match _step:
		12:
			# Kit nạp đúng: frame, tag, tick từ file art; chỉ số tank.
			if _frames == 2:
				_setup_duel(450, 560)
				var meta: Dictionary = Moves.meta(Moves.KIT_DONGTAO)
				_check(int(meta["count"]) == 119 and (meta["tags"] as Dictionary).size() == 18, "Đông Tảo sheet: 119 frames, 18 tags")
				var huc: Dictionary = Moves.get_move(&"huc_dau", Moves.KIT_DONGTAO)
				_check(str(huc["ticks"]) == str([5, 3, 6, 4, 5, 5]) and int(huc["startup"]) == 8,
					"Húc Đầu frame data from art durations (ticks %s, startup %d)" % [str(huc["ticks"]), int(huc["startup"])])
				var sup: Dictionary = Moves.get_move(&"thai_son", Moves.KIT_DONGTAO)
				_check(int(sup["startup"]) == 33 and int(sup["cost"]) == 2, "Thái Sơn Áp Đỉnh startup 33 ticks, 2 bars")
				var all_ok: bool = true
				for id in Moves.move_ids(Moves.KIT_DONGTAO):
					var m: Dictionary = Moves.get_move(id, Moves.KIT_DONGTAO)
					all_ok = all_ok and (m["frames"] as Array).size() == (m["ticks"] as Array).size() and (m["frames"] as Array).size() > 0
				_check(all_ok, "every Đông Tảo move resolves to art frames")
				_check(d.kit == Moves.KIT_DONGTAO and d.view.kit == Moves.KIT_DONGTAO, "breed 2 selects the dongtao kit")
				_check(is_equal_approx(d.body.get_movement_config().speed, 140.0), "Đông Tảo walk speed preset 140 px/s (%.0f)" % d.body.get_movement_config().speed)
				var tank_hp: int = int(GameState.scaled_stats(2, 3)["hp"])
				_check(tank_hp == int(round(1.3 * float(GameState.scaled_stats(0, 3)["hp"]))), "Đông Tảo HP 130%% of Gà nòi (%d)" % tank_hp)
				_check(d.body.health_max_hp == int(round(float(tank_hp) * BattleDirector.HEALTH_SCALE)),
					"match HP uses the round health scale (%d)" % d.body.health_max_hp)
				_check(is_equal_approx(sqrt(3.0 / float(d.stats["weight"])), 0.5), "Đông Tảo takes 50% knockback (weight 12)")
				_check(_p(1).kit == Moves.KIT_ROOSTER, "default breed keeps the rooster kit")
				d.source.push_event(InputBits.JUMP, true)
				d.source.push_event(InputBits.CROUCH, true)
			if _frames == 30:
				_check(not d.airborne and d.body.global_position.y > -3.0, "Đông Tảo cannot jump")
				_check(not d.crouching(), "Đông Tảo cannot crouch")
				d.source.push_event(InputBits.JUMP, false)
				d.source.push_event(InputBits.CROUCH, false)
				# Thiết Giáp: đỡ mọi tầng, tốn gauge ×1,5.
				var o: BattleDirector.Fighter = _p(1)
				var low: Dictionary = Moves.get_move(&"mo_thap")
				var high: Dictionary = Moves.get_move(&"air_j")
				d.held = 1 << InputBits.MOVE_LEFT
				_check(_director._guard_result(d, o, low["hits"][0], low) == 1, "Thiết Giáp blocks lows standing")
				_check(_director._guard_result(d, o, high["hits"][0], high) == 1, "Thiết Giáp blocks highs")
				_check(is_equal_approx(_director._guard_cost(d, "M"), 18.0 * 1.5), "Thiết Giáp drains 1.5× Block Gauge")
				d.held = 0
				_new_battle(_dt_side(), _side())
				_next()
		13:
			# Chuỗi L → M → H (Combo 1 "Ba Đòn Nặng").
			if _frames == 2:
				_setup_duel(450, 560)
			if _frames == 4:
				_press(0, InputBits.LIGHT)
			var n: int = _director.hit_log.size()
			if n != int(_seen.get("n", 0)):
				_seen["n"] = n
				var last: Array = _director.hit_log[n - 1]
				if String(last[2]) == "huc_dau":
					_seen["press_m"] = _frames + 1
				elif String(last[2]) == "dam_chan":
					_seen["press_h"] = _frames + 1
			if _frames == int(_seen.get("press_m", -1)):
				_press(0, InputBits.HEAVY)
			if _frames == int(_seen.get("press_h", -1)):
				_press(0, InputBits.SPECIAL)
			_max_combo = maxi(_max_combo, d.combo_hits)
			if _frames == 120:
				_check(_logged(0, "huc_dau").size() == 1 and _logged(0, "dam_chan").size() == 1 and _logged(0, "da_tru").size() == 1,
					"L → M → H chain connects (Húc Đầu, Dậm Chân, Đá Trụ)")
				_check(_max_combo >= 3, "Ba Đòn Nặng is a 3-hit combo (max %d)" % _max_combo)
				var tru: Array = _logged(0, "da_tru")
				_check(not tru.is_empty() and String(tru[0][3]) == "vang", "Đá Trụ sends the opponent flying (VANG)")
				_max_combo = 0
				_new_battle(_dt_side(), _side())
				_next()
		14:
			# Húc Trâu: lao tới từ xa và tông trúng.
			if _frames == 2:
				_setup_duel(300, 640)
				_seen["x0"] = d.x()
			if _frames == 4:
				_press(0, InputBits.ACTION_H)
			if d.move.get("id", &"") == &"huc_trau":
				_seen["started"] = true
			if _frames == 120:
				_check(_seen.has("started"), "S starts Húc Trâu")
				_check(d.x() - float(_seen["x0"]) > 120.0, "Húc Trâu travels forward (%.0f px)" % (d.x() - float(_seen["x0"])))
				_check(_logged(0, "huc_trau").size() == 1, "Húc Trâu rams the opponent")
				_new_battle(_dt_side(), _side())
				_next()
		15:
			# Giáp: chịu đúng 1 đòn khi chạy (vẫn mất máu), đòn thứ hai ngắt chiêu.
			if _frames == 2:
				_setup_duel(300, 900)
			if _frames == 4:
				_press(0, InputBits.ACTION_H)
			if not _seen.has("hit1") and d.move.get("id", &"") == &"huc_trau" and d.mf >= 2 and _director._hitstop == 0:
				var jab: Dictionary = Moves.get_move(&"mo_nhanh")
				var hp0: int = d.hp()
				_director._resolve_hit(_p(1), d, jab["hits"][0], jab, d.body.global_position + Vector2(0, -60))
				_seen["hit1"] = true
				_check(d.hp() < hp0, "armoured hit still deals damage (%d → %d)" % [hp0, d.hp()])
				_check(d.react == &"" and d.move.get("id", &"") == &"huc_trau", "Húc Trâu armour absorbs the first hit")
				_seen["hit2_at"] = _frames + 3
			if _frames == int(_seen.get("hit2_at", -1)):
				var jab2: Dictionary = Moves.get_move(&"mo_nhanh")
				_director._resolve_hit(_p(1), d, jab2["hits"][0], jab2, d.body.global_position + Vector2(0, -60))
				_check(d.react == &"nhe" and d.move.is_empty(), "armour absorbs exactly one hit (second hit interrupts)")
				_check(int(d.track["armor"]) == 1, "armour counted once")
			if _frames == 60:
				_new_battle(_dt_side(), _side())
				_next()
		16:
			# Địa Chấn: đánh ngã đối thủ đang đứng dưới đất (đứng đỡ cũng không chặn được vì là đòn thấp).
			if _frames == 2:
				_setup_duel(450, 570)
				d.source.push_event(InputBits.CROUCH, true)
			if _frames == 4:
				_press(0, InputBits.ACTION_H)
			if _frames == 6:
				d.source.push_event(InputBits.CROUCH, false)
			if _frames == 90:
				var quake: Array = _logged(0, "dia_chan")
				_check(quake.size() == 1 and String(quake[0][3]) == "te", "↓+S Địa Chấn knocks down a grounded opponent")
				_new_battle(_dt_side(), _side())
				_next()
		17:
			# Địa Chấn không trúng đối thủ đang nhảy.
			if _frames == 2:
				_setup_duel(450, 570)
				d.source.push_event(InputBits.CROUCH, true)
			if _frames == 4:
				_press(0, InputBits.ACTION_H)
			if _frames == 6:
				d.source.push_event(InputBits.CROUCH, false)
			if _frames == 10:
				_press(1, InputBits.JUMP)
			if _p(1).airborne:
				_seen["air"] = true
			if _frames == 90:
				_check(_seen.has("air") and _logged(0, "dia_chan").is_empty(), "Địa Chấn misses an airborne opponent")
				_new_battle(_dt_side(), _side())
				_next()
		18:
			# Thái Sơn Áp Đỉnh: 2 vạch, không đỡ được.
			if _frames == 2:
				_setup_duel(450, 640)
				d.special.add_points(d.special.get_points_per_bar() * 3)
				_seen["bars"] = d.special.get_available_bars()
				_p(1).source.push_event(InputBits.MOVE_RIGHT, true) # giữ lùi để đỡ
				d.source.push_event(InputBits.MOVE_RIGHT, true)
			if _frames == 4:
				_press(0, InputBits.ACTION_H)
			if _frames == 7:
				d.source.push_event(InputBits.MOVE_RIGHT, false)
			if d.move.get("id", &"") == &"thai_son":
				_seen["super"] = true
			if _frames == 160:
				_check(_seen.has("super"), "→+S with 2 bars starts Thái Sơn Áp Đỉnh")
				_check(int(_seen["bars"]) - d.special.get_available_bars() >= 2, "super costs 2 bars")
				var hit: Array = _logged(0, "thai_son")
				_check(hit.size() == 1 and int(_p(1).track["blocks"]) == 0, "super is unblockable (hit while holding back)")
				_p(1).source.push_event(InputBits.MOVE_RIGHT, false)
				_new_battle(_dt_side(), _side())
				_next()
		19:
			# Né siêu chiêu bằng cách nhảy đúng lúc (sau khi dừng hình, lúc gà bay lên).
			if _frames == 2:
				_setup_duel(450, 640)
				d.special.add_points(d.special.get_points_per_bar() * 2)
				d.source.push_event(InputBits.MOVE_RIGHT, true)
			if _frames == 4:
				_press(0, InputBits.ACTION_H)
			if _frames == 7:
				d.source.push_event(InputBits.MOVE_RIGHT, false)
			if d.move.get("id", &"") == &"thai_son" and d.mf == 3 and not _seen.has("jumped") and _director._freeze == 0:
				_seen["jumped"] = true
				_press(1, InputBits.JUMP)
			if _frames == 170:
				_check(_seen.has("jumped") and _logged(0, "thai_son").is_empty(), "jumping during the rise dodges Thái Sơn Áp Đỉnh")
				_new_battle(_dt_side(), _side())
				_next()
		20:
			# Phản Đòn: bắt đòn trong cửa sổ → hóa giải và quạt lại; hụt thì hồi lâu.
			if _frames == 2:
				_setup_duel(450, 560)
				d.source.push_event(InputBits.MOVE_LEFT, true)
			if _frames == 4:
				_press(0, InputBits.ACTION_H)
			if _frames == 6:
				d.source.push_event(InputBits.MOVE_LEFT, false)
			if not _seen.has("struck") and d.move.get("id", &"") == &"phan_don" and d.mf == 1:
				_seen["struck"] = true
				var hp0: int = d.hp()
				var jab: Dictionary = Moves.get_move(&"mo_nhanh")
				_director._resolve_hit(_p(1), d, jab["hits"][0], jab, d.body.global_position + Vector2(0, -60))
				_check(d.countered and d.hp() == hp0, "←+S Phản Đòn negates a hit inside its window")
			if _frames == 70:
				var swat: Array = _logged(0, "phan_don")
				_check(swat.size() == 1 and String(swat[0][3]) == "nang", "Phản Đòn swats back (HIT_Nang)")
				_new_battle(_dt_side(), _side())
				_next()
		21:
			# Phản Đòn hụt: hồi lâu; Đấm Ngực Thị Uy +25% nộ.
			if _frames == 2:
				_setup_duel(450, 700)
				d.source.push_event(InputBits.MOVE_LEFT, true)
			if _frames == 4:
				_press(0, InputBits.ACTION_H)
			if _frames == 6:
				d.source.push_event(InputBits.MOVE_LEFT, false)
			if d.move.get("id", &"") == &"phan_don":
				_seen["len"] = int(_seen.get("len", 0)) + 1
			if _frames == 90:
				var plain: int = int(Moves.get_move(&"phan_don", Moves.KIT_DONGTAO)["total"])
				_check(int(_seen.get("len", 0)) >= plain + 15, "whiffed Phản Đòn has long recovery (%d ticks vs %d)" % [int(_seen.get("len", 0)), plain])
				_seen["sp0"] = d.special.get_current_points()
				d.source.push_event(InputBits.ACTION_H, true)
				d.source.push_event(InputBits.SPECIAL, true)
			if _frames == 93:
				d.source.push_event(InputBits.ACTION_H, false)
				d.source.push_event(InputBits.SPECIAL, false)
			if _frames == 170:
				var gain: int = d.special.get_current_points() - int(_seen["sp0"])
				_check(gain >= int(d.special.get_maximum_points() * 0.25), "S+H Đấm Ngực Thị Uy grants +25%% gauge (+%d)" % gain)
				# AI-vs-AI: gà mặc định (T2) vs Đông Tảo (T2).
				var dt: Dictionary = GameState.OPPONENTS["bay_ghe"].duplicate(true)
				_new_battle(_side(), dt)
				_next()
		22:
			if _frames == 3:
				var c: BattleDirector.Fighter = _p(0)
				c.source.configure({})
				c.ai = EnemyAI.new()
				c.ai.configure({"tier": 2, "aggr": 0.6, "block": 0.3, "kit": &"rooster"}, 11)
			if not _result.is_empty() or _frames > 400 * 60:
				_check(not _result.is_empty(), "AI-vs-AI default vs Đông Tảo finished (frames=%d, %s)" % [_frames, str(_result.get("rounds", []))])
				_check(_logged(1, "huc_dau").size() + _logged(1, "dam_chan").size() + _logged(1, "da_tru").size() > 0,
					"Đông Tảo AI lands normals")
				var opp: Dictionary = GameState.OPPONENTS["bay_ghe"].duplicate(true)
				opp["tier"] = 1
				_new_battle(_side(), opp)
				_next()
		23:
			# Người chơi (input kịch bản) gà mặc định thắng Đông Tảo bị động: không kẹt ở đứng dậy, góc, giáp, nằm.
			if _frames == 3:
				_director.fighters[1].ai.script_mode = EnemyAI.Mode.PASSIVE
			_scripted_human()
			if not _result.is_empty() or _frames > 300 * 60:
				_check(not _result.is_empty() and bool(_result["won"]), "scripted human rooster beats a passive Đông Tảo (frames=%d)" % _frames)
				_hold(0, 0)
				return true
	return false


## Người chơi giả: đi tới, J J K L, chờ đối thủ dậy, lặp lại.
func _scripted_human() -> void:
	var p: BattleDirector.Fighter = _p(0)
	var o: BattleDirector.Fighter = _p(1)
	if _director.phase != BattleDirector.Phase.FIGHT or p.react != &"" or p.ko:
		_hold(0, 0)
		return
	var toward: int = InputBits.MOVE_RIGHT if o.x() > p.x() else InputBits.MOVE_LEFT
	var distance: float = absf(o.x() - p.x())
	var t: int = int(_seen.get("seq_t", 0))
	if not p.move.is_empty() or t > 0:
		_seen["seq_t"] = t + 1
		var seq: Array = [InputBits.LIGHT, InputBits.LIGHT, InputBits.HEAVY, InputBits.SPECIAL]
		var step: int = t / 10
		if step < seq.size() and t % 10 == 0:
			_hold(0, 1 << int(seq[step]))
		elif t % 10 == 2:
			_hold(0, 0)
		if t > 70:
			_seen["seq_t"] = 0
		return
	if o.react in [&"te", &"nam", &"vang", &"vang_land", &"dung"]:
		_hold(0, (1 << toward) if distance > 140.0 else 0)
		return
	if distance > 105.0:
		_hold(0, 1 << toward)
	else:
		_hold(0, 1 << InputBits.LIGHT)
		_seen["seq_t"] = 1


# ==================================================================== hiệp đấu, AI hàng loạt, không kẹt trận

func _rounds_step() -> bool:
	_release_due()
	match _step:
		24:
			# Best-of-3: thắng hiệp 1 → reset vị trí/HP/Block Gauge, giữ Special/Card Gauge; chưa kết thúc trận.
			var d: BattleDirector = _director
			if _frames == 2:
				_check(d.rounds_to_win == 2 and d.phase == BattleDirector.Phase.INTRO, "normal match is best-of-3 and opens with the intro")
			if d.phase == BattleDirector.Phase.FIGHT and not _seen.has("r1"):
				_seen["r1"] = true
				d.fighters[1].ai.script_mode = EnemyAI.Mode.IDLE
				_p(0).body.global_position.x = 450
				_p(1).body.global_position.x = 560
				_p(1).health.call("apply_damage", _p(1).hp() - 1)
				_p(0).guard = 40.0
				_press(0, InputBits.LIGHT)
			if d.phase == BattleDirector.Phase.KO and not _seen.has("ko"):
				_seen["ko"] = true
				_seen["sp"] = _p(0).special.get_current_points()
				_seen["cg"] = _p(0).card_gauge.get_current_gauge()
				_check(d.round_wins[0] == 1 and d.round_wins[1] == 0, "KO wins round 1 (%s)" % str(d.round_wins))
			if d.phase == BattleDirector.Phase.ROUND_INTRO and _seen.has("ko") and not _seen.has("reset"):
				_seen["reset"] = true
				_check(_result.is_empty(), "match continues after one round win")
				_check(d.round_index == 2, "round 2 starts")
				_check(_p(1).hp() == _p(1).body.health_max_hp and _p(0).hp() == _p(0).body.health_max_hp, "HP restored for the new round")
				_check(is_equal_approx(_p(0).guard, BattleDirector.GUARD_MAX), "Block Gauge restored for the new round")
				_check(is_equal_approx(_p(0).x(), BattleDirector.START_X[0]) and is_equal_approx(_p(1).x(), BattleDirector.START_X[1]), "positions reset")
				_check(_p(0).special.get_current_points() == int(_seen["sp"]), "Special Gauge carries over between rounds")
				_check(_p(0).card_gauge.get_current_gauge() >= int(_seen["cg"]), "Card Gauge carries over between rounds")
			if _seen.has("reset") and d.phase == BattleDirector.Phase.FIGHT and not _seen.has("r2"):
				_seen["r2"] = true
				d.fighters[1].ai.script_mode = EnemyAI.Mode.IDLE
				_p(0).body.global_position.x = 450
				_p(1).body.global_position.x = 560
				_p(1).health.call("apply_damage", _p(1).hp() - 1)
				_press(0, InputBits.LIGHT)
			if not _result.is_empty():
				_check(bool(_result["won"]) and str(_result["round_wins"]) == str([2, 0]) and (_result["rounds"] as Array).size() == 2,
					"two round wins end the match (%s)" % str(_result["round_wins"]))
				_check(float(_result["player_hp_ratio"]) >= 0.999 and bool(_result["perfect"]), "flawless 2-0 reports player_hp_ratio 1.0")
				_check(int(_result["duration_ticks"]) > 0, "result carries duration_ticks")
				_new_battle(_side(), _side(), "tutorial")
				_next()
			elif _frames > 60 * 60:
				_check(false, "rounds flow timed out (phase %d)" % d.phase)
				_new_battle(_side(), _side(), "tutorial")
				_next()
		25:
			# Trận hướng dẫn: một hiệp ngắn, đồng hồ không chạy.
			var d: BattleDirector = _director
			if _frames == 2:
				_check(d.rounds_to_win == 1, "tutorial is a single round")
			if d.phase == BattleDirector.Phase.FIGHT and not _seen.has("fight"):
				_seen["fight"] = true
				_seen["clock"] = d.clock_ticks
				_seen["t0"] = _frames
				_check(_frames < 200, "tutorial intro is short (%d frames)" % _frames)
			if _seen.has("fight") and not _seen.has("done") and _frames - int(_seen["t0"]) == 60:
				_check(d.clock_ticks == int(_seen["clock"]), "tutorial clock does not run")
				_seen["done"] = true
				d._finish(0, "HOÀN THÀNH!")
			if not _result.is_empty():
				_check(bool(_result["won"]) and (_result["rounds"] as Array).size() == 1, "tutorial ends after one round")
				_new_battle(_side(), _side())
				_next()
		26:
			# Hết giờ: bên còn nhiều máu thắng hiệp.
			var d: BattleDirector = _director
			if d.phase == BattleDirector.Phase.FIGHT and not _seen.has("t"):
				_seen["t"] = true
				d.fighters[1].ai.script_mode = EnemyAI.Mode.IDLE
				_p(1).health.call("apply_damage", 10)
				d.clock_ticks = 2
			if _seen.has("t") and d.phase == BattleDirector.Phase.ROUND_END and not _seen.has("end"):
				_seen["end"] = true
				_check(d.round_wins[0] == 1 and String(d.round_log[0]["reason"]) == "HẾT GIỜ!", "time-up awards the round on HP")
				_start_batch()
				_next()
		27:
			# AI hàng loạt (không cảnh điện ảnh) + đối chứng có cảnh điện ảnh cùng seed.
			if _batch.is_empty():
				return false
			_report_batch()
			return true
	return false


func _start_batch() -> void:
	if _director != null:
		_director.queue_free()
		_director = null
	_runner = AiRunner.new()
	root.add_child(_runner)
	var t3: Dictionary = {"owner": "AI", "name": "T3", "breed": 0, "lv": 3, "tier": 3, "skill": 0.9, "aggr": 0.6, "block": 0.35, "jumpy": 0.2}
	var t1: Dictionary = {"owner": "AI", "name": "T1", "breed": 0, "lv": 3, "tier": 1, "skill": 0.2, "aggr": 0.5, "block": 0.1, "jumpy": 0.1}
	var mid: Dictionary = {"owner": "AI", "name": "P", "breed": 0, "lv": 3, "tier": 2, "skill": 0.6, "aggr": 0.55, "block": 0.3, "jumpy": 0.2}
	for s in range(10):
		if s % 2 == 0:
			_runner.jobs.append({"label": "T3>T1", "p": t3, "p_ai": t3, "o": t1, "seed": 200 + s})
		else:
			_runner.jobs.append({"label": "T1<T3", "p": t1, "p_ai": t1, "o": t3, "seed": 200 + s})
	# Mọi đối thủ trong danh sách: AI tầm trung đứng thay người chơi (trận hướng dẫn chạy như trận thường).
	var modes: Dictionary = {"teo_1": "friendly"}
	for id in GameState.OPPONENTS.keys():
		_runner.jobs.append({"label": "roster:" + String(id), "p": mid, "p_ai": mid, "o": GameState.OPPONENTS[id].duplicate(true),
			"mode": modes.get(id, "normal"), "seed": 900 + String(id).length()})
	# Cảnh điện ảnh không đổi kết quả mô phỏng.
	_runner.jobs.append({"label": "det:off", "p": mid, "p_ai": mid, "o": GameState.OPPONENTS["bay_ghe"].duplicate(true), "seed": 77, "cinematics": false})
	_runner.jobs.append({"label": "det:on", "p": mid, "p_ai": mid, "o": GameState.OPPONENTS["bay_ghe"].duplicate(true), "seed": 77, "cinematics": true})
	_runner.all_done.connect(func(results: Array) -> void: _batch = results)


func _report_batch() -> void:
	var t3_wins: int = 0
	var det: Dictionary = {}
	for r in _batch:
		var label: String = String(r["label"])
		if label == "T3>T1" and bool(r["won"]):
			t3_wins += 1
		elif label == "T1<T3" and not bool(r["won"]):
			t3_wins += 1
		elif label.begins_with("roster:"):
			var rounds: Array = r.get("rounds", [])
			_check(not bool(r["stalemate"]) and rounds.size() >= 2 and int(r["hits"]) > 0,
				"%s: full match finishes without softlock (rounds %s, %d hits, %.0f s)" % [label, str(rounds), int(r["hits"]), float(r["frames"]) / 60.0])
		elif label.begins_with("det:"):
			det[label] = r
	_check(t3_wins >= 7, "T3 beats T1 in ≥ 7 of 10 seeded matches (%d/10)" % t3_wins)
	if det.size() == 2:
		var a: Dictionary = det["det:off"]
		var b: Dictionary = det["det:on"]
		_check(str(a["rounds"]) == str(b["rounds"]) and str(a["round_ticks"]) == str(b["round_ticks"]) and str(a["log"]) == str(b["log"]),
			"cinematics do not change simulation results (same seed: %s / %s)" % [str(a["round_ticks"]), str(b["round_ticks"])])
	_runner.queue_free()
	_runner = null


# ==================================================================== sân đấu + khán giả (chỉ trình diễn)

var _crowd_spots: Dictionary = {}
var _crowd_dev_y: float = 0.0
var _crowd_dev_x: float = 0.0
var _crowd_below_rest: float = 0.0
var _crowd_rot: float = 0.0
var _crowd_spot_moved: float = 0.0
var _crowd_bursts: int = 0
var _crowd_rounds: int = 0


## Theo dõi mọi khán giả suốt trận AI-vs-AI nhiều hiệp (đứng xem, reo hò, K.O., sang hiệp mới):
## sprite chỉ được nhấc dọc 0..HOP_MAX so với vị trí nghỉ; không trôi ngang, không xoay, chỗ đứng không đổi.
func _track_crowd() -> void:
	var arena: BattleArena = _director.arena
	if _frames == 6:
		_crowd_spots = {}
		for m in arena.crowd_members():
			_crowd_spots[(m["sprite"] as Sprite2D).get_instance_id()] = (m["spot"] as Node2D).position
		_crowd_rounds = _director.round_log.size()
		_check_arena_coverage(arena)
		_check(arena.variant == &"toi", "final-tier opponent gets the evening arena variant")
		var teo_in_crowd: bool = false
		for m in arena.crowd_members():
			teo_in_crowd = teo_in_crowd or int(m["npc"]) == BattleArena.NPC_TEO
		_check(not teo_in_crowd, "opponent's owner (Tèo) is not standing in the crowd")
	if _frames < 6:
		return
	# Reo hò dồn dập (thêm vào các lần director tự gọi) để thử cú nhảy chồng nhau.
	if _frames % 180 == 40:
		arena.jump_burst()
		_crowd_bursts += 1
	if _frames % 97 == 0:
		arena.cheer(0.6)
	for m in arena.crowd_members():
		var sprite: Sprite2D = m["sprite"]
		var rest: Vector2 = m["rest"]
		var spot: Node2D = m["spot"]
		_crowd_dev_y = maxf(_crowd_dev_y, rest.y - sprite.position.y)
		_crowd_below_rest = maxf(_crowd_below_rest, sprite.position.y - rest.y)
		_crowd_dev_x = maxf(_crowd_dev_x, absf(sprite.position.x - rest.x))
		_crowd_rot = maxf(_crowd_rot, absf(sprite.rotation) + absf(spot.rotation) + absf(spot.get_parent().rotation))
		var start: Vector2 = _crowd_spots.get(sprite.get_instance_id(), spot.position)
		_crowd_spot_moved = maxf(_crowd_spot_moved, start.distance_to(spot.position))


func _crowd_checks() -> void:
	var arena: BattleArena = _director.arena
	_check(arena.crowd_members().size() >= 60, "arena has a crowd (%d spectators)" % arena.crowd_members().size())
	_check(_crowd_bursts >= 5 and _director.round_log.size() > _crowd_rounds, "crowd watched %d cheers + %d round(s)" % [_crowd_bursts, _director.round_log.size()])
	_check(_crowd_dev_y <= BattleArena.HOP_MAX + 0.001 and _crowd_dev_y >= 4.0,
		"spectators hop vertically only up to HOP_MAX (max lift %.1f px)" % _crowd_dev_y)
	_check(_crowd_below_rest <= 0.001, "spectators never sink below their rest spot (%.2f px)" % _crowd_below_rest)
	_check(_crowd_dev_x == 0.0, "spectators never drift horizontally (%.2f px)" % _crowd_dev_x)
	_check(_crowd_rot == 0.0, "spectators are never rotated")
	_check(_crowd_spot_moved == 0.0, "spectator spots stay planted (%.2f px)" % _crowd_spot_moved)
	# Hết reo hò: mọi người trở về đúng vị trí nghỉ (chỉ còn nhún ≤ 2 px).
	arena.excitement = 0.0
	arena._time += 5.0
	arena._update_crowd(0.0)
	var settle: float = 0.0
	for m in arena.crowd_members():
		settle = maxf(settle, absf((m["sprite"] as Sprite2D).position.y - (m["rest"] as Vector2).y))
	_check(settle <= BattleArena.BOB_IDLE + 0.001, "after cheering everyone is back at rest (±%.1f px)" % settle)


## Ảnh nền phủ kín khung nhìn camera ở zoom nhỏ/lớn nhất, khi lia mở màn và khi rung (theo luật camera director).
func _check_arena_coverage(arena: BattleArena) -> void:
	var bad: Array[String] = []
	var tested: int = 0
	for vp in [Vector2(1152, 648), Vector2(1152, 864), Vector2(1536, 648)]:
		var widths: Array[float] = [600.0, 760.0, 1000.0]
		for w in widths:
			var base_zoom: float = vp.x / w
			for mult in [1.0, 1.25, 1.75, 2.1]:
				for zoom in [base_zoom * float(mult), 1.4]:
					var vis: Vector2 = vp / zoom
					var lo: float = -110.0 + vis.x * 0.5
					var hi: float = 1110.0 - vis.x * 0.5
					var xs: Array = [lo, 500.0, hi, 140.0, 860.0] if lo <= hi else [500.0]
					for x in xs:
						var cx: float = clampf(float(x), lo, hi) if lo <= hi else 500.0
						for cy in [-vis.y * 0.3, -vis.y * 0.3 - 200.0, -230.0 + vis.y * 0.08, -60.0]:
							var center := Vector2(cx, float(cy))
							var view := Rect2(center - vis * 0.5 - Vector2(12, 12), vis + Vector2(24, 24))
							var missing: Array[StringName] = arena.uncovered_layers(center, view)
							tested += 1
							if not missing.is_empty() and bad.size() < 5:
								bad.append("%s@%s:%s" % [str(vis.round()), str(center.round()), str(missing)])
	_check(bad.is_empty(), "arena art covers the camera view at every zoom/sweep/shake extreme (%d views) %s" % [tested, str(bad)])
