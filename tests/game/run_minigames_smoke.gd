extends SceneTree

## Smoke test các TRANG mini-game (game/world/minigames/*): mỗi hoạt động của ActivityRunner mở trang riêng
## (World bị ẩn + tắt xử lý, camera của trang làm camera hiện hành), autopilot chơi thắng → thưởng đúng một lần mỗi
## ngày; bỏ ngang (Esc → E) → không thưởng, không tốn giờ, chưa tính lượt; người chơi về đúng chỗ cũ; tín hiệu
## activity_started/finished bắn đủ; trang + lớp mờ được dọn sạch (không còn node mồ côi/ node thừa ở root).
## Thêm: trò phụ mới (câu cá lóc, thả diều), dò vé số bằng trang cào, lớp học THPT, hai nghề làm thêm.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_minigames_smoke.gd

const Activities := preload("res://game/world/activities.gd")
const ActivityRunner := preload("res://game/world/activity_runner.gd")
const Minigame := preload("res://game/world/minigames/minigame.gd")
const TEST_SAVE: String = "user://test_minigames_smoke.cfg"
const SPOT: Vector2 = Vector2(1146, 784)
const MAX_FRAMES: int = 60 * 90

var _failures: int = 0
var _world: World
var _dialog: DialogBox
var _runner: Node
var _choice: int = 0
var _frame: int = 0
var _started: Array[StringName] = []
var _finished: Array[StringName] = []
var _last: Dictionary = {}
var _done: bool = false
var _fx: Dictionary = {}


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.TUTORIAL # đã có gà → nhận EXP
	Activities.save_path = TEST_SAVE
	Activities.reset()
	Activities.rng.seed = 777
	seed(777)
	_dialog = DialogBox.new()
	root.add_child(_dialog)
	_world = World.new()
	root.add_child(_world)
	_runner = ActivityRunner.new()
	_world.add_child(_runner)
	_runner.setup(_world, _dialog)
	_runner.autopilot = true
	_runner.activity_started.connect(func(id: StringName) -> void: _started.append(id))
	_runner.activity_finished.connect(func(id: StringName, r: Dictionary) -> void:
		_finished.append(id)
		_last = r
		_done = true)
	_runner.fx.connect(func(kind: StringName, _pos: Vector2) -> void: _fx[kind] = int(_fx.get(kind, 0)) + 1)
	_main.call_deferred()


## Tự bấm qua hội thoại (lựa chọn = _choice).
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 3 != 0:
		return false
	if _dialog._mode == 1:
		_dialog._text.visible_ratio = 1.0
		_dialog._advanced.emit()
	elif _dialog._mode == 2:
		_dialog._chosen.emit(_choice)
	return false


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


## Chạy một hoạt động; cancel = bấm Esc rồi E khi trang vào pha chơi. Trả về thông tin quan sát được.
func _run(id: StringName, choice: int = 0, cancel: bool = false) -> Dictionary:
	_choice = choice
	_done = false
	_last = {}
	_world.player.position = SPOT
	var info: Dictionary = {"page": false, "hidden": false, "camera": false, "pages": 0, "script": "", "timeout": false,
		"intro": false, "played": false, "result_panel": false}
	var seen: Array = []
	_runner.run(id)
	var frames: int = 0
	while not _done:
		var page: Node = _runner.current_game
		if page != null and is_instance_valid(page) and page.is_inside_tree():
			if not seen.has(page):
				seen.append(page)
				info["script"] = String((page.get_script() as Script).resource_path.get_file())
			info["page"] = true
			if not _world.visible and _world.process_mode == Node.PROCESS_MODE_DISABLED:
				info["hidden"] = true
			var cam: Camera2D = page.get("camera")
			if cam != null and cam.is_current():
				info["camera"] = true
			var ph: int = int(page.get("phase"))
			if ph == Minigame.Phase.INTRO:
				info["intro"] = true
			elif ph == Minigame.Phase.PLAY:
				info["played"] = true
				if cancel:
					page.call("press", &"cancel")
					page.call("press", &"confirm")
			elif ph == Minigame.Phase.RESULT:
				info["result_panel"] = true
		frames += 1
		if frames > MAX_FRAMES:
			info["timeout"] = true
			break
		await process_frame
	info["pages"] = seen.size()
	await _frames(3)
	return info


func _gained_since(money: int) -> int:
	return GameState.money - money


## Kiểm chung sau một trang: World hiện lại, người chơi đúng chỗ, tín hiệu, không còn trang/lớp mờ.
func _common(id: StringName, info: Dictionary, label: String) -> void:
	_check(not bool(info["timeout"]), "%s: finished in time" % label)
	_check(bool(info["page"]) and bool(info["hidden"]) and bool(info["camera"]),
		"%s: own page (%s) – world hidden + paused, page camera current" % [label, info["script"]])
	_check(_world.visible and _world.process_mode != Node.PROCESS_MODE_DISABLED and _world.player.position == SPOT,
		"%s: back in the village at the same spot" % label)
	_check(not _started.is_empty() and _started.back() == id and not _finished.is_empty() and _finished.back() == id,
		"%s: activity_started/finished(%s)" % [label, id])
	_check(_runner.current_game == null and _runner.current_quiz == null and _world.interactions_enabled,
		"%s: runner idle, interactions restored" % label)
	_check(_leftovers() == 0, "%s: page + fade layer removed (%d left)" % [label, _leftovers()])


func _leftovers() -> int:
	var count: int = 0
	for child in root.get_children():
		if child.get_script() != null and (child.get_script() as Script).resource_path.begins_with("res://game/world/minigames/"):
			count += 1
		elif child is CanvasLayer and (child as CanvasLayer).layer == 95:
			count += 1
	return count


func _main() -> void:
	await _frames(5)
	var orphans0: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var roots0: int = root.get_child_count()

	# --- bỏ ngang: không thưởng, không tốn giờ, chưa tính lượt
	for entry in [[&"farm", 0, "gặt lúa"], [&"site", 0, "phụ hồ"], [&"cau_ca_loc", 0, "câu cá lóc"], [&"lottery", 0, "mua vé số"]]:
		var money: int = GameState.money
		var minutes: int = GameState.minutes
		var info: Dictionary = await _run(entry[0], entry[1], true)
		_common(entry[0], info, "cancel %s" % entry[2])
		var key: StringName = &"fish" if entry[0] == &"fish_house" else entry[0]
		_check(bool(_last.get("cancelled", false)) and GameState.money == money and GameState.minutes == minutes \
			and not Activities.is_done(key) and bool(info["played"]),
			"cancel %s: no reward, no time spent, still available" % entry[2])

	# --- lớp THPT (thứ Hai sáng)
	GameState.set_time(GameState.day, 7 * 60)
	var tech: int = GameState.technology
	var info: Dictionary = await _run(&"thpt")
	_common(&"thpt", info, "lớp THPT")
	var right: int = int(_last.get("right", -1))
	_check(right == int(_last.get("total", 0)) and right == 4 and GameState.technology == tech + 10 + right * 2,
		"lớp THPT: autopilot answers %d/%d → +%d Technology" % [right, int(_last.get("total", 0)), GameState.technology - tech])

	# --- mỗi trang chơi thắng một lần
	var money: int = GameState.money
	info = await _run(&"fish_house", 1)
	_common(&"fish_house", info, "kéo vó")
	_check(int(_last.get("fish", -1)) == 3 and _gained_since(money) == 3 * Activities.FISH_PRICE and bool(info["result_panel"]),
		"kéo vó: 3 fish → %+d" % _gained_since(money))
	money = GameState.money
	info = await _run(&"fish_house", 0)
	_common(&"fish_house", info, "cho cá ăn")
	_check(int(_last.get("thrown", 0)) == 3 and _gained_since(money) == 0, "cho cá ăn: 3 handfuls, free")
	money = GameState.money
	info = await _run(&"farm")
	_common(&"farm", info, "gặt lúa")
	_check(int(_last.get("bundles", 0)) == 8 and _gained_since(money) == 8 * Activities.RICE_MONEY_PER_BUNDLE,
		"gặt lúa: 8 bundles → %+d" % _gained_since(money))
	money = GameState.money
	info = await _run(&"school")
	_common(&"school", info, "trường làng")
	_check(int(_last.get("right", 0)) == 3 and _gained_since(money) == 3 * Activities.QUIZ_MONEY_PER_RIGHT,
		"trường làng: 3/3 → %+d" % _gained_since(money))
	money = GameState.money
	info = await _run(&"site")
	_common(&"site", info, "phụ hồ")
	_check(bool(_last.get("full", false)) and int(_last.get("bricks", 0)) == Activities.BRICK_TARGET \
		and _gained_since(money) == Activities.BRICK_FULL_PAY, "phụ hồ: full shift of %d → %+d (broken %d)" % [
		int(_last.get("bricks", 0)), _gained_since(money), int(_last.get("broken", 0))])
	money = GameState.money
	info = await _run(&"temple")
	_common(&"temple", info, "đền làng")
	_check(String(_last.get("fortune", "")) != "" and int(_last.get("incense", 0)) == 3 \
		and _gained_since(money) == Activities.TEMPLE_FIRST_GIFT, "đền làng: 3 incense + fortune, gift %+d" % _gained_since(money))
	money = GameState.money
	info = await _run(&"lottery")
	_common(&"lottery", info, "mua vé số")
	_check(_gained_since(money) == -Activities.LOTTERY_PRICE and Activities.lottery_ticket.length() == 6 \
		and String(_last.get("ticket", "")) == Activities.lottery_ticket, "vé số: picked ticket %s for %+d" % [Activities.lottery_ticket, _gained_since(money)])
	money = GameState.money
	info = await _run(&"cau_ca_loc")
	_common(&"cau_ca_loc", info, "câu cá lóc")
	var loc: int = int(_last.get("fish", -1))
	_check(loc >= 1 and loc <= 3 and _gained_since(money) == loc * Activities.LOC_PRICE and Activities.is_done(&"cau_ca_loc"),
		"câu cá lóc: %d fish → %+d" % [loc, _gained_since(money)])
	tech = GameState.technology
	info = await _run(&"tha_dieu")
	_common(&"tha_dieu", info, "thả diều")
	var rings: int = int(_last.get("rings", -1))
	_check(rings >= 3 and GameState.technology - tech == Activities.kite_technology(rings) and Activities.is_done(&"tha_dieu"),
		"thả diều: %d wind rings → +%d Technology" % [rings, GameState.technology - tech])
	for job in [[&"job_shop", 70000], [&"job_boat", 100000]]:
		money = GameState.money
		info = await _run(job[0])
		_common(job[0], info, String(job[0]))
		var gained: int = _gained_since(money)
		_check(gained >= int(job[1] * 0.5) and gained <= int(job[1] * 1.3) and float(_last.get("factor", 0.0)) >= 1.0,
			"%s: factor ×%.2f → %+d" % [job[0], float(_last.get("factor", 0.0)), gained])

	# --- lần hai trong ngày: không mở trang, không thưởng
	for id in [&"farm", &"site", &"school", &"cau_ca_loc", &"tha_dieu", &"job_shop"]:
		money = GameState.money
		tech = GameState.technology
		info = await _run(id)
		_check(not bool(info["page"]) and GameState.money == money and GameState.technology == tech and bool(_last.get("cancelled", false)),
			"%s: second run the same day → no page, no reward" % id)

	# --- ngày mới: dò vé số bằng trang cào rồi mua tờ mới
	Activities.new_day()
	_check(Activities.lottery_result_ready() and Activities.is_available(&"cau_ca_loc") and Activities.is_available(&"tha_dieu"),
		"new day: lottery can be checked, side games open again")
	money = GameState.money
	info = await _run(&"lottery")
	_common(&"lottery", info, "dò vé số")
	var won: int = int(_last.get("won", -1))
	_check(int(info["pages"]) == 2 and won in [0, Activities.LOTTERY_CONSOLATION, Activities.LOTTERY_PRIZE] \
		and _gained_since(money) == won - Activities.LOTTERY_PRICE, "dò vé số: scratch page + new ticket (won %d, money %+d)" % [won, _gained_since(money)])

	# --- dọn dẹp
	await _frames(10)
	_check(root.get_child_count() == roots0, "no extra nodes under root (%d → %d)" % [roots0, root.get_child_count()])
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans <= orphans0, "no orphan nodes left (%d → %d)" % [orphans0, orphans])
	_check(int(_fx.get(&"catch", 0)) >= 3 and int(_fx.get(&"cut", 0)) >= 8 and int(_fx.get(&"pick", 0)) >= 8 \
		and int(_fx.get(&"incense", 0)) >= 3, "fx hooks fired (catch %d, cut %d, pick %d, incense %d)" % [
		int(_fx.get(&"catch", 0)), int(_fx.get(&"cut", 0)), int(_fx.get(&"pick", 0)), int(_fx.get(&"incense", 0))])
	_check(not _dialog.is_open(), "dialog closed at the end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
