extends SceneTree

## Smoke test mini-game TẨU THOÁT + cắt cảnh rửa chén (không nạp World/main, GameState vừa reset):
## - sinh màn: mọi seed × độ khó đều qua validate_course (luôn có đường đi, báo trước ≥ 1 s), cùng seed → cùng màn;
## - autopilot giỏi (1.0) thoát ở độ khó 0 / 0.5 / 1 trên nhiều seed; lơ mơ (0.0) bị tóm; trung bình (0.5) có
##   lúc thắng ở độ khó thấp;
## - dạng Dictionary kết quả; bỏ chạy (Esc) ở bảng hướng dẫn và giữa chừng (2 lần Esc);
## - thao tác bơm tay: nhảy / trượt / chạy nước rút / thăng bằng / sải tay;
## - một lượt chạy thật theo frame (await run()) tới khi thoát; camera cũ được trả lại, cây sạch sau queue_free();
## - cắt cảnh chạy hết (auto_advance) trong 20–45 s, bỏ qua bằng Esc, tự giải phóng.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_escape_smoke.gd

const EscapeGameScript := preload("res://game/escape/escape_game.gd")
const EscapeCutsceneScript := preload("res://game/escape/escape_cutscene.gd")
const SEEDS: Array[int] = [3, 7, 11, 19, 42]

var _failures: int = 0
var _started: bool = false


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_all()
	return false


func _make(difficulty: float, p_seed: int, skill: float, chicken: Dictionary = {}) -> Node2D:
	var g: Node2D = EscapeGameScript.new()
	g.setup({"difficulty": difficulty, "seed": p_seed, "chicken": chicken})
	g.autopilot = true
	g.autopilot_skill = skill
	root.add_child(g)
	return g


func _leftovers() -> int:
	var n: int = 0
	for child in root.get_children():
		var s: Script = child.get_script()
		if s == EscapeGameScript or s == EscapeCutsceneScript:
			n += 1
	return n


func _count_world(node: Node) -> int:
	var n: int = 0
	var s: Script = node.get_script()
	if s != null and (s.get_global_name() == &"World" or s.resource_path == "res://game/main.gd"):
		n += 1
	for child in node.get_children():
		n += _count_world(child)
	return n


func _run_all() -> void:
	var t0: int = Time.get_ticks_msec()
	GameState.reset()
	_check(_count_world(root) == 0, "no World / main scene loaded")
	_check(GameState.active_chicken().has("breed"), "GameState freshly reset (active chicken exists)")
	# Nạp theo class_name lẫn theo đường dẫn.
	var tmp: Node2D = EscapeGame.new()
	_check(tmp is Node2D and tmp.get_script() == EscapeGameScript and load("res://game/escape/escape_game.gd") == EscapeGameScript, "EscapeGame loadable by class_name and by path")
	tmp.free()
	_check(load("res://game/escape/escape_cutscene.gd") == EscapeCutsceneScript, "EscapeCutscene loadable by path")

	# ---------------------------------------------------------------- sinh màn
	var bad: int = 0
	var first_bad: String = ""
	var total: int = 0
	for s in range(1, 151):
		for d in [0.0, 0.25, 0.5, 0.75, 1.0]:
			total += 1
			var c: Dictionary = EscapeGame.generate_course(s, d)
			var errors: PackedStringArray = EscapeGame.validate_course(c)
			if not errors.is_empty():
				bad += 1
				if first_bad == "":
					first_bad = "seed %d d %.2f: %s" % [s, d, errors[0]]
	_check(bad == 0, "all %d generated courses pass the static solvability check %s" % [total, first_bad])
	var a: Dictionary = EscapeGame.generate_course(5, 0.5)
	var b: Dictionary = EscapeGame.generate_course(5, 0.5)
	var c2: Dictionary = EscapeGame.generate_course(6, 0.5)
	_check(str(a["run"]) == str(b["run"]) and str(a["swim"]) == str(b["swim"]), "same seed → same course")
	_check(str(a["run"]) != str(c2["run"]), "different seed → different course")
	var easy: Dictionary = EscapeGame.generate_course(9, 0.0)
	var hard: Dictionary = EscapeGame.generate_course(9, 1.0)
	_check((hard["run"] as Array).size() > (easy["run"] as Array).size(), "difficulty 1 has more run obstacles than 0 (%d > %d)" % [(hard["run"] as Array).size(), (easy["run"] as Array).size()])
	# Một màn hỏng phải bị bắt: hai chướng ngại sát nhau, cụm bơi chặn 3 làn.
	var broken: Dictionary = a.duplicate(true)
	(broken["run"] as Array).append({"kind": &"jar", "x": float((broken["run"] as Array).back()["x"]) + 40.0})
	(broken["swim"] as Array).append({"kind": &"log", "x": 2400.0, "lanes": [0], "from_top": false})
	(broken["swim"] as Array).append({"kind": &"net", "x": 2405.0, "lanes": [1, 2], "from_top": false})
	var broken_errors: PackedStringArray = EscapeGame.validate_course(broken)
	_check(broken_errors.size() >= 2, "validator rejects a crammed run pair and a 3-lane swim block (%d errors)" % broken_errors.size())

	# ---------------------------------------------------------------- autopilot (mô phỏng đồng bộ)
	for d in [0.0, 0.5, 1.0]:
		var wins: int = 0
		var times: Array = []
		for s in SEEDS:
			var g := _make(d, s, 1.0)
			var r: Dictionary = g.simulate(200.0)
			if bool(r["escaped"]):
				wins += 1
			times.append(int(r["time"]))
			g.free()
		_check(wins == SEEDS.size(), "skill 1.0 escapes at difficulty %.1f on all %d seeds (times %s)" % [d, SEEDS.size(), str(times)])
		var t_ok: bool = true
		for t in times:
			t_ok = t_ok and t >= 50 and t <= 95
		_check(t_ok, "skill 1.0 run length is about a minute at difficulty %.1f" % d)
	for d in [0.0, 0.5, 1.0]:
		var caught: int = 0
		for s in SEEDS:
			var g := _make(d, s, 0.0)
			var r: Dictionary = g.simulate(200.0)
			if bool(r["caught"]) and not bool(r["escaped"]):
				caught += 1
			g.free()
		_check(caught == SEEDS.size(), "skill 0.0 gets caught at difficulty %.1f on all seeds (%d/%d)" % [d, caught, SEEDS.size()])
	var mid_wins: int = 0
	var mid_losses: int = 0
	for s in range(1, 9):
		var g := _make(0.0, s * 11 + 3, 0.5)
		var r: Dictionary = g.simulate(200.0)
		if bool(r["escaped"]):
			mid_wins += 1
		else:
			mid_losses += 1
		g.free()
	_check(mid_wins >= 1, "skill 0.5 sometimes wins at difficulty 0 (%d wins / %d losses)" % [mid_wins, mid_losses])

	# ---------------------------------------------------------------- dạng kết quả + Đông Tảo
	var gd := _make(0.3, 77, 1.0, {"name": "Ô Mun", "breed": 2})
	var rd: Dictionary = gd.simulate(200.0)
	var keys_ok: bool = true
	for key in ["escaped", "caught", "cancelled", "time", "stumbles", "stage_reached"]:
		keys_ok = keys_ok and rd.has(key)
	_check(keys_ok, "result has escaped/caught/cancelled/time/stumbles/stage_reached")
	_check(rd["escaped"] is bool and rd["caught"] is bool and rd["cancelled"] is bool and rd["time"] is float
		and rd["stumbles"] is int and rd["stage_reached"] is int, "result value types (bool, bool, bool, float, int, int)")
	_check(bool(rd["escaped"]) and int(rd["stage_reached"]) == 2 and not bool(rd["caught"]), "Đông Tảo variant escapes, reached stage 2")
	_check(gd.get("_variant") == "dongtao", "breed 2 uses the Đông Tảo sprite variant")
	gd.free()

	# ---------------------------------------------------------------- bỏ chạy
	var gc := _make(0.5, 3, 1.0)
	gc.autopilot = false
	gc.set("_running", true)
	gc.call("_enter_intro")
	gc.press(&"cancel")
	var rc: Dictionary = gc.result
	_check(bool(rc.get("cancelled", false)) and not bool(rc.get("escaped", true)) and not bool(rc.get("caught", true)), "Esc on the intro panel cancels (cancelled, not escaped, not caught)")
	gc.free()
	var gm := _make(0.5, 3, 1.0)
	gm.simulate(6.0, false)
	_check(int(gm.phase) == EscapeGame.Phase.RUN, "autopilot is running after 6 s")
	gm.press(&"cancel")
	_check(not bool(gm.result.get("cancelled", false)) and float(gm.get("_cancel_armed")) > 0.0, "first Esc mid-run only asks for confirmation")
	gm.press(&"cancel")
	_check(bool(gm.result.get("cancelled", false)) and int(gm.phase) == EscapeGame.Phase.DONE, "second Esc cancels the run")
	gm.free()

	# ---------------------------------------------------------------- thao tác bơm tay
	var gi := _make(0.0, 3, 1.0)
	gi.autopilot = false
	gi.set("_running", true)
	gi.call("_enter_intro")
	gi.press(&"confirm")
	_check(int(gi.phase) == EscapeGame.Phase.COUNTDOWN, "confirm on intro starts the 3-2-1")
	for i in range(int(2.2 * 60.0)):
		gi.call("_tick", 1.0 / 60.0)
	_check(int(gi.phase) == EscapeGame.Phase.RUN, "countdown hands over to the run")
	gi.press(&"jump")
	gi.call("_tick", 1.0 / 60.0)
	_check(float(gi.get("_alt")) > 0.0, "press(jump) leaves the ground")
	for i in range(60):
		gi.call("_tick", 1.0 / 60.0)
	_check(float(gi.get("_alt")) == 0.0, "lands again after ~0.6 s")
	gi.press(&"slide")
	gi.call("_tick", 1.0 / 60.0)
	_check(float(gi.get("_slide")) > 0.0, "press(slide) starts a slide")
	for i in range(60):
		gi.call("_tick", 1.0 / 60.0)
	gi.hold(&"sprint", true)
	for i in range(60):
		gi.call("_tick", 1.0 / 60.0)
	_check(float(gi.get("_v")) > EscapeGame.RUN_V + 20.0 and float(gi.get("_stamina")) < 1.0, "hold(sprint) speeds up and drains stamina (v %.0f)" % float(gi.get("_v")))
	gi.hold(&"sprint", false)
	# Thăng bằng trên cầu: đặt người lên đầu cầu, gõ phải đẩy kim sang phải.
	var bridge: Vector2 = gi.course["bridge"]
	gi.set("_x", bridge.x + 2.0)
	gi.set("_police_x", bridge.x - 200.0)
	gi.call("_tick", 1.0 / 60.0)
	_check(bool(gi.get("_on_bridge")), "on the monkey bridge")
	var before: float = float(gi.get("_balance_v"))
	gi.press(&"right")
	gi.call("_tick", 1.0 / 60.0)
	_check(float(gi.get("_balance_v")) > before + 0.3, "press(right) pushes the balance to the right")
	gi.free()
	var gs := _make(0.0, 3, 1.0)
	gs.autopilot = false
	gs.set("_running", true)
	gs.call("_start_swim", false)
	var y0: float = float(gs.get("_y"))
	gs.hold(&"up", true)
	for i in range(20):
		gs.call("_tick", 1.0 / 60.0)
	gs.hold(&"up", false)
	_check(float(gs.get("_y")) < y0 - 10.0, "hold(up) swims up")
	var stam: float = float(gs.get("_stamina"))
	gs.press(&"stroke")
	gs.call("_tick", 1.0 / 60.0)
	_check(float(gs.get("_stroke")) > 0.0 and float(gs.get("_stamina")) < stam, "press(stroke) bursts and costs stamina")
	gs.free()

	# ---------------------------------------------------------------- lượt chạy thật theo frame
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	await process_frame
	var children_before: int = root.get_child_count()
	var gr := _make(0.0, 11, 1.0, GameState.active_chicken())
	await process_frame
	_check(not cam.is_current(), "the escape game owns the current camera while it runs")
	var frames_start: int = Engine.get_physics_frames()
	var rr: Dictionary = await gr.run()
	var frames_used: int = Engine.get_physics_frames() - frames_start
	_check(bool(rr["escaped"]), "frame-driven run (await run()) escapes with autopilot 1.0 (%d physics frames, %.1f s)" % [frames_used, float(rr["time"])])
	gr.queue_free()
	await process_frame
	await process_frame
	_check(_leftovers() == 0 and root.get_child_count() == children_before, "nothing left in the tree after queue_free()")
	_check(cam.is_current(), "previous camera is current again")

	# ---------------------------------------------------------------- cắt cảnh
	var cut: Node2D = EscapeCutsceneScript.new()
	cut.setup({"chicken": GameState.active_chicken(), "auto_advance": true, "interior": "painter"})
	root.add_child(cut)
	await process_frame
	_check(not cam.is_current(), "cutscene owns the camera")
	var cut_start: int = Engine.get_process_frames()
	var cr: Dictionary = await cut.play()
	var cut_seconds: float = float(Engine.get_process_frames() - cut_start) / 60.0
	_check(not bool(cr.get("skipped", true)), "cutscene plays to the end with auto-advance")
	_check(cut_seconds >= 20.0 and cut_seconds <= 45.0, "cutscene length %.1f s (20–45 s)" % cut_seconds)
	_check(String(cr.get("interior", "")) == "painter", "own kitchen painter used when requested")
	await process_frame
	await process_frame
	_check(_leftovers() == 0, "cutscene frees itself")
	_check(cam.is_current(), "camera restored after the cutscene")
	var cut2: Node2D = EscapeCutsceneScript.new()
	cut2.setup({"chicken": {"name": "Tía", "breed": 2}})
	root.add_child(cut2)
	var skip_at: int = Engine.get_process_frames() + 90
	var timer := func() -> void:
		while Engine.get_process_frames() < skip_at:
			await process_frame
		cut2.press(&"skip")
	timer.call()
	var start2: int = Engine.get_process_frames()
	var cr2: Dictionary = await cut2.play()
	var skip_seconds: float = float(Engine.get_process_frames() - start2) / 60.0
	_check(bool(cr2.get("skipped", false)) and skip_seconds < 4.0, "Esc skips the whole cutscene (ended after %.1f s)" % skip_seconds)
	var cut3: Node2D = EscapeCutsceneScript.new()
	cut3.setup({"chicken": {}})   # nội thất: nhà thật nếu home_scene.gd có build_interior(), không thì hoạ sĩ riêng
	root.add_child(cut3)
	var advancer := func() -> void:
		while is_instance_valid(cut3) and cut3.is_inside_tree():
			cut3.press(&"next")
			for k in range(20):
				await process_frame
	advancer.call()
	var start3: int = Engine.get_process_frames()
	var cr3: Dictionary = await cut3.play()
	var manual_seconds: float = float(Engine.get_process_frames() - start3) / 60.0
	_check(not bool(cr3.get("skipped", true)) and manual_seconds < 40.0, "pressing E line by line reaches the end (%.1f s)" % manual_seconds)
	var expect: String = "home_scene" if ResourceLoader.exists("res://game/home/home_scene.gd") else "painter"
	_check(String(cr3.get("interior", "")) == expect, "auto interior picks %s (got %s)" % [expect, String(cr3.get("interior", ""))])
	await process_frame
	await process_frame
	_check(_leftovers() == 0, "no cutscene left after skip / manual play")
	cam.queue_free()
	await process_frame
	(load("res://game/escape/escape_art.gd") as Script).call("clear_cache")
	(load("res://game/escape/escape_sfx.gd") as Script).call("clear_cache")
	# Cache tĩnh của script dùng chung (font hộp thoại, tiếng Sfx) – xoá để thoát sạch, không báo rò rỉ.
	DialogBox._font_cache.clear()
	Sfx._streams.clear()
	await process_frame
	print("      (%d ms)" % (Time.get_ticks_msec() - t0))
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
