extends SceneTree

## Smoke test đua xe bí mật: dò thách đua (thuần logic + thật trên World của main), hội thoại thách/từ chối,
## thời gian chờ, cuộc đua chạy hết headless (autopilot thắng/thua/bỏ cuộc), thưởng mỗi ngày một lần,
## trạng thái World trả lại nguyên vẹn sau cuộc đua, lưu/tải số lần thắng.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_race_smoke.gd

const Activities := preload("res://game/world/activities.gd")
const RaceRiders := preload("res://game/world/race/race_riders.gd")
const TEST_SAVE: String = "user://test_race_smoke.cfg"
const NORTH: String = "A_xe_may_con_tay_do"   # bờ bắc, chạy sang phải
const SOUTH: String = "C_xe_may_con_tay_den"  # bờ nam, chạy sang trái

var _main: Node
var _world: World
var _failures: int = 0
var _frames: int = 0
var _step: int = 0
var _drive: bool = true
var _choice: int = 0
var _challenged: String = ""
var _follow: String = ""
var _follow_dir: int = 0
var _follow_ok: bool = true
var _pre_pos: Vector2
var _money: int = 0
var _skill: float = 1.0
var _give_up: bool = false
var _race_seen: bool = false
var _phase_note: String = ""


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	Activities.save_path = TEST_SAVE
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _find(type_check: Callable) -> Node:
	for child in _main.get_children():
		if type_check.call(child):
			return child
	return null


## Tự bấm qua màn tiêu đề, đặt tên, hồi ức, hội thoại (lựa chọn = _choice).
func _drive_ui() -> void:
	if not _drive or _frames % 4 != 0:
		return
	var dialog: DialogBox = _main.dialog
	var title: Node = _find(func(n: Node) -> bool: return n is TitleScreen)
	var cut: Node = _find(func(n: Node) -> bool: return n is Cutscene)
	if title != null:
		title._picked.emit("new")
	elif dialog._mode == 3:
		dialog._named.emit("")
	elif cut != null:
		cut._next.emit()
	elif dialog._mode == 1:
		dialog._text.visible_ratio = 1.0
		dialog._advanced.emit()
	elif dialog._mode == 2:
		dialog._chosen.emit(_choice)


func _idle() -> bool:
	return _main.world != null and _main.world.player.can_move and not _main._busy and not _main.dialog.is_open() and _main.race == null


func _rect(rx: float, ry: float) -> Rect2:
	return Rect2(rx, ry, 72, 60)


## Chạy race_detect_step nhiều frame với vị trí người chơi theo hàm lệch (theo frame), trả về tên xe bị vượt.
func _simulate(bike: String, box: Rect2, frames: int, move_dir: int, pos_of: Callable) -> String:
	for i in range(frames):
		var got: String = _world.race_detect_step(1.0 / 60.0, pos_of.call(i), move_dir, {bike: box})
		if got != "":
			return got
	return ""


func _unit_checks() -> void:
	var w: World = _world
	var north := _rect(200, 175)                # tâm x 236, bánh xe y 235
	var south := _rect(600, 530)                # tâm x 636, bánh xe y 590 (xe chạy sang trái)
	w._race_pace.clear()
	# Đi bộ: không đủ điều kiện.
	w.player.set_riding(false)
	_check(not w.race_eligible(), "walking: race detection disabled")
	w.player.set_riding(true)
	_check(w.race_eligible(), "riding on the road: race detection enabled")
	# Chạy ngược chiều.
	var got: String = _simulate(NORTH, north, 150, -1, func(i: int) -> Vector2: return Vector2(206.0 + 0.6 * i, 232))
	_check(got == "", "riding the opposite way never triggers")
	# Cùng chiều nhưng xa đường (lệch 80 px).
	w._race_pace.clear()
	got = _simulate(NORTH, north, 150, 1, func(i: int) -> Vector2: return Vector2(206.0 + 0.6 * i, 315))
	_check(got == "", "far from the road never triggers")
	# Kè bên nhưng không vượt.
	w._race_pace.clear()
	got = _simulate(NORTH, north, 240, 1, func(_i: int) -> Vector2: return Vector2(206, 232))
	_check(got == "", "riding alongside without overtaking never triggers")
	# Vọt lên trước mà chưa kè đủ lâu.
	w._race_pace.clear()
	got = _simulate(NORTH, north, 20, 1, func(i: int) -> Vector2: return Vector2(206.0 if i < 20 else 270.0, 232))
	got = got if got != "" else w.race_detect_step(1.0 / 60.0, Vector2(270, 232), 1, {NORTH: north})
	_check(got == "", "jumping ahead after only 0.33 s alongside does not trigger")
	# Vượt thật: kè 1 giây rồi vượt lên.
	w._race_pace.clear()
	got = _simulate(NORTH, north, 120, 1, func(i: int) -> Vector2: return Vector2(206.0 + 0.6 * i, 232))
	_check(got == NORTH, "north road: pacing 1 s then overtaking triggers (%s)" % got)
	# Bờ nam, xe chạy sang trái.
	w._race_pace.clear()
	got = _simulate(SOUTH, south, 120, -1, func(i: int) -> Vector2: return Vector2(666.0 - 0.6 * i, 588))
	_check(got == SOUTH, "south road (leftward bike): overtake triggers (%s)" % got)
	# Xe khuất (null) giữa chừng thì tính lại.
	w._race_pace.clear()
	for i in range(40):
		w.race_detect_step(1.0 / 60.0, Vector2(206, 232), 1, {NORTH: north})
	w.race_detect_step(1.0 / 60.0, Vector2(206, 232), 1, {NORTH: null})
	got = w.race_detect_step(1.0 / 60.0, Vector2(270, 232), 1, {NORTH: north})
	_check(got == "", "bike hidden mid-pace resets the pacing")
	# Không dò khi: thời gian chờ, hoạt động, đò.
	w.start_race_cooldown()
	_check(not w.race_eligible() and w.race_cooldown >= World.RACE_COOLDOWN - 0.01, "cooldown blocks detection")
	w.race_cooldown = 0.0
	w.interactions_enabled = false
	_check(not w.race_eligible(), "no detection while an activity runs (interactions disabled)")
	w.interactions_enabled = true
	w._ferry_busy = true
	_check(not w.race_eligible(), "no detection during a ferry ride")
	w._ferry_busy = false
	w.player.can_move = false
	_check(not w.race_eligible(), "no detection while the player is frozen (dialog/busy)")
	w.player.can_move = true
	w._race_pace.clear()
	_check(RaceRiders.has_rider(NORTH) and RaceRiders.has_rider(SOUTH) and RaceRiders.RIDERS.size() == 4, "four riders defined")
	var ids: Dictionary = {}
	var paces: Dictionary = {}
	for key in RaceRiders.RIDERS:
		var rider: Dictionary = RaceRiders.RIDERS[key]
		ids[rider["id"]] = true
		paces[rider["pace"]] = true
		_check(int(rider["dir"]) == int(World.RACE_BIKES[key]), "%s: rider dir matches world table" % key)
	_check(ids.size() == 4 and paces.size() == 4, "each rider has its own id and pace")


## Đặt người chơi sau xe NPC thật trên bản đồ và cho chạy theo 210 px/s (như xe Dream) tới khi bị thách.
func _start_follow(bike: String, frame: int) -> void:
	_world.map_view._time_ms = float(frame * _world.map_view.frame_ms) + 1.0
	_world.map_view._set_frame(frame)
	var box: Rect2 = _world.map_view.node_rect(bike)
	_follow = bike
	_follow_dir = int(World.RACE_BIKES[bike])
	_world.player.position = Vector2(roundf(box.get_center().x - 50.0 * _follow_dir), box.end.y - 3.0)
	_world.race_cooldown = 0.0
	_challenged = ""


func _on_challenge(bike: String) -> void:
	_challenged = bike


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_drive_ui()
	if _main.race != null and not _race_seen:
		_race_seen = true
		_main.race.autopilot = true
		_main.race.autopilot_skill = _skill
	if _give_up and _main.race != null and _main.race._running:
		_give_up = false
		_main.race.press(&"cancel")
	match _step:
		0:
			# Khởi động game mới tới lúc đi lại được.
			if _main.world == null or not _idle() or GameState.stage != GameState.Stage.GO_CHU_TU:
				return _timeout(60 * 150, "boot")
			print("      (booted after %d frames)" % _frames)
			_world = _main.world
			_world.race_challenge.connect(_on_challenge)
			_drive = false
			_money = GameState.money
			_unit_checks()
			_next()
		1:
			# Thật: bám theo xe đỏ bờ bắc rồi vượt → main mở hội thoại thách đua → từ chối.
			if _frames == 1:
				_start_follow(NORTH, 20)
			if _challenged == "":
				_world.player.position.x += 210.0 / 60.0 * _follow_dir
				return _timeout(60 * 8, "north follow")
			_check(_challenged == NORTH, "real map: overtaking the red sport bike (north road) triggers a challenge")
			_check(_main._busy and not _world.player.can_move, "challenge freezes the player")
			_choice = 1
			_drive = true
			_next()
		2:
			if _frames == 3:
				_check(_main.dialog._mode == 2 and not _world.race_eligible(), "challenge dialog offers race/decline; no detection during dialog")
			if not _idle():
				return _timeout(60 * 30, "decline")
			_check(_main.race == null and GameState.money == _money, "declining starts no race and changes no money")
			_check(_world.race_cooldown > World.RACE_COOLDOWN - 5.0 and not _world.race_eligible(), "declining starts the cooldown (%.1f s)" % _world.race_cooldown)
			_check(_world.player.riding and _world.player.can_move, "player still riding and free after declining")
			_drive = false
			_next()
		3:
			# Bờ nam: bám theo xe đen (chạy sang trái) rồi vượt → nhận đua → autopilot thắng.
			if _frames == 1:
				_start_follow(SOUTH, 5)
			if _challenged == "":
				_world.player.position.x += 210.0 / 60.0 * _follow_dir
				return _timeout(60 * 8, "south follow")
			_check(_challenged == SOUTH, "real map: overtaking the black bike (south road, leftward) triggers a challenge")
			_pre_pos = _world.player.position
			_money = GameState.money
			_begin_race(1.0, false)
		4:
			if not _race_done():
				return _timeout(60 * 120, "race 1 (win)")
			_check(GameState.money == _money + Activities.RACE_PRIZE, "first win of the day pays %s (money %+d)" % [GameState.money_text(Activities.RACE_PRIZE), GameState.money - _money])
			_check(Activities.race_wins == 1 and Activities.race_title and Activities.is_done(&"race"), "win counted, secret title unlocked, daily prize used")
			_check_restored("after race 1")
			_check(_world.player.position == _pre_pos, "player back on the road where the challenge happened")
			# Lần hai cùng ngày: thắng nhưng không có thưởng.
			_money = GameState.money
			_world.race_cooldown = 0.0
			_world.race_challenge.emit("A_xe_may_cho_ga")
			_begin_race(1.0, false)
		5:
			if not _race_done():
				return _timeout(60 * 120, "race 2 (win, same day)")
			_check(GameState.money == _money and Activities.race_wins == 2, "second win the same day: no prize (money %+d), wins = %d" % [GameState.money - _money, Activities.race_wins])
			_check_restored("after race 2")
			# Thua: autopilot lơ mơ với xe khó nhất.
			_money = GameState.money
			_world.race_cooldown = 0.0
			_world.race_challenge.emit(NORTH)
			_begin_race(0.0, false)
		6:
			if not _race_done():
				return _timeout(60 * 150, "race 3 (loss)")
			_check(GameState.money == _money and Activities.race_wins == 2 and Activities.race_count == 3, "loss: no money, wins unchanged, 3 races counted")
			_check_restored("after a lost race")
			# Bỏ cuộc (Esc).
			_world.race_cooldown = 0.0
			_world.race_challenge.emit("C_xe_may_cho_dua")
			_begin_race(1.0, true)
		7:
			if not _race_done():
				return _timeout(60 * 30, "race 4 (give up)")
			_check(Activities.race_count == 3 and GameState.money == _money, "giving up: not counted, no money")
			_check_restored("after giving up")
			# Ngày mới + lưu/tải.
			Activities.new_day()
			_check(not Activities.is_done(&"race"), "a new day re-opens the race prize")
			Activities.save()
			Activities.reset()
			_check(Activities.load_save() and Activities.race_wins == 2 and Activities.race_count == 3 and Activities.race_title, "race wins/count/title survive save/load")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
			print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
			quit(1 if _failures > 0 else 0)
			return true
	return false


func _begin_race(skill: float, give_up: bool) -> void:
	_skill = skill
	_give_up = give_up
	_race_seen = false
	_choice = 0
	_drive = true
	_next()


func _race_done() -> bool:
	return _race_seen and _idle()


func _check_restored(label: String) -> void:
	var map_view: MapView = _world.map_view
	var bikes_ok: bool = true
	for bike in World.RACE_BIKES:
		bikes_ok = bikes_ok and not map_view.is_node_hidden(bike)
	var leftover: int = 0
	for child in _main.get_children():
		if child.get_script() == preload("res://game/world/race/race_game.gd"):
			leftover += 1
	_check(_world.visible and _world._ui.visible and _world.process_mode == Node.PROCESS_MODE_INHERIT and _world._camera.is_current(),
		"%s: world active again (visible, processing, its camera current)" % label)
	_check(_world.player.riding and _world.player.can_move and not _main._busy, "%s: player on the bike and free to move" % label)
	_check(_world.race_cooldown > World.RACE_COOLDOWN - 5.0, "%s: cooldown started" % label)
	_check(bikes_ok and _main.race == null and leftover == 0, "%s: NPC bike loop untouched, race node freed" % label)
	if is_instance_valid(AudioDirector.instance):
		_check(AudioDirector.instance._music_track == &"village", "%s: village music back" % label)


func _timeout(limit: int, label: String) -> bool:
	if _frames > limit:
		_check(false, "timed out: %s" % label)
		print("      world=%s busy=%s dialog_mode=%d race=%s stage=%d children=%s" % [_main.world != null, _main._busy, _main.dialog._mode, _main.race, GameState.stage, str(_main.get_children())])
		if _main.world != null:
			print("      can_move=%s dialog_open=%s" % [_main.world.player.can_move, _main.dialog.is_open()])
		print("RESULT: FAIL (%d failure(s))" % _failures)
		quit(1)
		return true
	return false


func _next() -> void:
	_step += 1
	_frames = 0
