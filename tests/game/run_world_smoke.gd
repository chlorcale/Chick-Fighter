extends SceneTree

## Smoke test thế giới bờ nam: đò ngang (một chiếc, đò bản đồ đã ẩn), danh sách lựa chọn cuộn được,
## các hoạt động chạy hết headless (autopilot) và thưởng mỗi ngày một lần, sang ngày mới, cầu ván cá tra.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_world_smoke.gd

const Activities := preload("res://game/world/activities.gd")
const ActivityRunner := preload("res://game/world/activity_runner.gd")
const TEST_SAVE: String = "user://test_world_smoke.cfg"

var _failures: int = 0
var _frames: int = 0
var _step: int = 0
var _world: World
var _dialog: DialogBox
var _runner: Node
var _drive: bool = true
var _choice: int = 0
var _result: Dictionary = {}
var _running: bool = false
var _money: int = 0
var _xp: int = 0
var _level: int = 0
var _sub: int = 0
var _crossing_ok: bool = true
var _queue: Array = []


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.TUTORIAL # đã có gà → nhận EXP
	Activities.save_path = TEST_SAVE
	Activities.reset()
	Activities.rng.seed = 4242
	seed(4242)
	_dialog = DialogBox.new()
	root.add_child(_dialog)
	_world = World.new()
	root.add_child(_world)
	_runner = ActivityRunner.new()
	_world.add_child(_runner)
	_runner.setup(_world, _dialog)
	_runner.autopilot = true
	_runner.activity_finished.connect(func(_id: StringName, r: Dictionary) -> void:
		_result = r
		_running = false)


## Tự bấm qua hội thoại: câu đố trả lời đúng, lựa chọn khác dùng _choice.
func _drive_dialog() -> void:
	if not _drive or _frames % 3 != 0:
		return
	if _dialog._mode == 1:
		_dialog._text.visible_ratio = 1.0
		_dialog._advanced.emit()
	elif _dialog._mode == 2:
		var quiz: RefCounted = _runner.current_quiz
		_dialog._chosen.emit(int(quiz.get("current_answer")) if quiz != null else _choice)


func _start_activity(id: StringName, choice: int = 0) -> void:
	_choice = choice
	_result = {}
	_running = true
	_money = GameState.money
	_xp = GameState.xp
	_level = GameState.level
	_world.player.position = Vector2(_world.interactable_pos(_world.find_interactable(id)))
	_runner.run(id)


func _exp_gained() -> int:
	# Chưa lên cấp trong test (EXP nhỏ) nhưng vẫn tính phòng khi lên cấp.
	var total: int = GameState.xp - _xp
	for lv in range(_level, GameState.level):
		total += GameState.exp_to_next(lv)
	return total


func _count_visible_boats() -> int:
	var count: int = 0
	var stack: Array[Node] = [_world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D and (node as Sprite2D).is_visible_in_tree():
			var tex: Texture2D = (node as Sprite2D).texture
			if tex != null and tex.resource_path.contains("ferry"):
				count += 1
	var map_ferry: Dictionary = _world.map_view._by_name["song_do_ngang"]
	if (map_ferry["holder"] as Node2D).visible:
		count += 1
	return count


# ------------------------------------------------------------------ đi được tới đâu (BFS theo chân)

func _grid(box: Rect2i) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(box.size.x * box.size.y)
	for y in range(box.size.y):
		for x in range(box.size.x):
			grid[y * box.size.x + x] = 1 if _world._solid[(box.position.y + y) * World.MAP_SIZE.x + box.position.x + x] > 0 else 0
	for list_value in [[World.EXTRA_BLOCKERS, 1], [World.OPEN_RECTS, 0]]:
		for rect in list_value[0]:
			var part: Rect2i = (rect as Rect2i).intersection(box)
			for y in range(part.position.y, part.end.y):
				for x in range(part.position.x, part.end.x):
					grid[(y - box.position.y) * box.size.x + x - box.position.x] = list_value[1]
	return grid


func _reachable(box: Rect2i, start: Vector2i, goal: Vector2i) -> bool:
	var grid: PackedByteArray = _grid(box)
	# Đối chiếu nhanh với World.is_blocked.
	for i in range(300):
		var p := Vector2i(box.position.x + randi() % box.size.x, box.position.y + randi() % box.size.y)
		if (grid[(p.y - box.position.y) * box.size.x + p.x - box.position.x] == 1) != _world.is_blocked(p.x, p.y):
			print("      grid mismatch at %s" % p)
			return false
	var blocked := func(p: Vector2i) -> bool:
		for yy in [p.y - 5, p.y - 3, p.y - 1]:
			for xx in [p.x - 5, p.x - 2, p.x, p.x + 2, p.x + 4]:
				if not box.has_point(Vector2i(xx, yy)) or grid[(yy - box.position.y) * box.size.x + xx - box.position.x] == 1:
					return true
		return false
	if blocked.call(start) or blocked.call(goal):
		return false
	var seen := PackedByteArray()
	seen.resize(box.size.x * box.size.y)
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	seen[(start.y - box.position.y) * box.size.x + start.x - box.position.x] = 1
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		if p == goal:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if not box.has_point(n):
				continue
			var k: int = (n.y - box.position.y) * box.size.x + n.x - box.position.x
			if seen[k] == 1:
				continue
			seen[k] = 1
			if not blocked.call(n):
				queue.append(n)
	return false


# ------------------------------------------------------------------ các bước

func _physics_process(_delta: float) -> bool:
	_frames += 1
	_drive_dialog()
	match _step:
		0:
			if _frames < 3:
				return false
			var map_view: MapView = _world.map_view
			_check(map_view.is_node_hidden("song_do_ngang") and map_view.is_node_hidden("song_do_ngang_gon"), "map ferry + ripple are hidden")
			_check(map_view.node_center("song_do_ngang") == null, "node_center of hidden node is null")
			_check(map_view.node_center("NV_co_ban_ve_so") is Vector2, "node_center finds the lottery seller (%s)" % str(map_view.node_center("NV_co_ban_ve_so")))
			_check(map_view.node_center("khong_co_node_nay") == null, "node_center of unknown node is null")
			_check(_count_visible_boats() == 1, "exactly one visible boat (%d)" % _count_visible_boats())
			_check(_world.ferry_at_north and is_equal_approx(_world.ferry_boat.position.y, World.BOAT_TOP_NORTH), "boat waits on the player's (north) bank")
			_check(not _world.player._blocked_at(World.FERRY_NORTH) and not _world.player._blocked_at(World.FERRY_SOUTH), "both pier ends are walkable")
			_check(_world.is_blocked(492, 420), "river beside the pier stays blocked")
			_world.player.position = World.FERRY_NORTH
			_world.ride_ferry(true)
			_next()
		1:
			if _frames % 20 == 0 and _world.ferry_moving:
				var boat_sorted_under: bool = _world.player.position.y > _world.ferry_boat.position.y \
					and _world.player.get_parent() == _world.ferry_boat.get_parent()
				_crossing_ok = _crossing_ok and boat_sorted_under and _count_visible_boats() == 1 \
					and not (_world.map_view._by_name["song_do_ngang"]["holder"] as Node2D).visible
			if _frames < 240:
				return false
			_check(_crossing_ok, "during the crossing: player drawn above the boat, still one boat, map ferry hidden")
			_check(_world.player.position.distance_to(World.FERRY_SOUTH) < 2.0 and _world.player.can_move, "ferry lands on the south pier, player can move")
			_check(not _world.ferry_at_north and is_equal_approx(_world.ferry_boat.position.y, World.BOAT_TOP_SOUTH), "boat stays moored on the south bank")
			_world.ride_ferry(false)
			_next()
		2:
			if _frames < 240:
				return false
			_check(_world.player.position.distance_to(World.FERRY_NORTH) < 2.0 and _world.player.can_move, "ferry brings the player back north")
			_check(_world.ferry_at_north, "boat moored on the north bank after the return trip")
			_check(_count_visible_boats() == 1, "still exactly one boat after a round trip")
			# Người chơi "xuất hiện" ở bờ nam (vd. tải game) → đò dời sang bờ nam.
			_world.player.position = Vector2(460, 560)
			_next()
		3:
			if _frames < 3:
				return false
			_check(not _world.ferry_at_north, "boat moves to the player's bank when they are on the other side")
			_drive = false
			var options: Array = []
			var details: Array = []
			for i in range(8):
				options.append("Lựa chọn số %d – một dòng thiệt dài để thử coi hộp thoại có cuộn được hông, chữ chữ chữ chữ chữ chữ" % (i + 1))
				details.append("Mô tả lựa chọn %d" % (i + 1))
			_dialog.choose("Cô Ba", "Con đang có 200.000đ. Mua gì nè? Câu hỏi này cũng hơi dài một chút cho chắc ăn.", options, details)
			_sub = 0
			_next()
		4:
			# Mỗi 3 frame bấm S một lần; kiểm tra lựa chọn đang chọn luôn nằm trong khung.
			if _frames % 3 != 0:
				return false
			if not _dialog.is_option_visible(_dialog._option_index):
				_crossing_ok = false
				print("      option %d not visible" % _dialog._option_index)
			if _sub == 0:
				_crossing_ok = true
				_check(_dialog.is_option_visible(0), "8 long options: first option visible")
			if _sub < 7:
				_dialog._move(1)
				_sub += 1
				return false
			_check(_dialog._option_index == 7 and _dialog.is_option_visible(7), "moving down to the last option keeps it visible")
			_check(_crossing_ok, "every selected option stayed visible while scrolling")
			_check(_dialog._more_up.text != "" and _dialog._more_down.text == "", "▲ indicator shown at the bottom of the list")
			_check(_dialog._detail.text == "Mô tả lựa chọn 8", "detail line follows the highlighted option")
			_dialog._move(1)
			_next()
		5:
			if _frames < 3:
				return false
			_check(_dialog._option_index == 0 and _dialog.is_option_visible(0), "wrap-around back to the first option")
			_dialog._chosen.emit(0)
			_drive = true
			_world.player.position = Vector2(112, 737)
			_queue = [
				[&"fish_house", 1, "fish"], [&"fish_house", 0, "feed"], [&"farm", 0, "farm"],
				[&"school", 0, "school"], [&"site", 0, "site"], [&"temple", 0, "temple"], [&"lottery", 0, "lottery"],
			]
			_next()
		6:
			# Cầu ván cá tra: đi được từ đường làng ra tới cuối cầu, hai bên là nước.
			_check(_reachable(Rect2i(0, 585, 150, 175), Vector2i(90, 600), Vector2i(112, 737)), "catfish walkway reachable on foot from the south road")
			_check(_world.is_blocked(70, 752) and _world.is_blocked(70, 720), "water on both sides of the walkway is blocked")
			_check(_reachable(Rect2i(440, 465, 200, 150), Vector2i(460, 484), Vector2i(500, 590)), "south pier connects to the south road")
			_check(_reachable(Rect2i(1060, 590, 220, 210), Vector2i(1085, 600), Vector2i(1146, 784)), "brick pile reachable")
			_check(_reachable(Rect2i(1060, 590, 220, 210), Vector2i(1146, 784), Vector2i(1208, 784)), "brick drop spot reachable from the pile")
			_check(_reachable(Rect2i(700, 590, 400, 170), Vector2i(1085, 600), Vector2i(899, 740)), "school door reachable")
			_check(_reachable(Rect2i(700, 590, 400, 470), Vector2i(1085, 600), Vector2i(900, 1046)), "temple incense urn reachable")
			_check(_reachable(Rect2i(380, 585, 240, 375), Vector2i(500, 600), Vector2i(418, 946)), "ripe rice field reachable")
			_next()
		7:
			# Chạy lần lượt từng hoạt động (lần đầu trong ngày): phải có thưởng.
			if _running:
				if _frames > 60 * 70:
					_check(false, "activity timed out (%s)" % str(_queue.front()))
					_running = false
					_queue.pop_front()
				return false
			if _frames > 1 and not _result.is_empty():
				_verify_first(_queue.pop_front(), _result)
				_result = {}
			if _queue.is_empty():
				_queue = [&"fish_house", &"farm", &"school", &"site", &"temple", &"lottery"]
				_next()
				return false
			var entry: Array = _queue.front()
			_frames = 1
			_start_activity(entry[0], entry[1])
		8:
			# Lần hai trong cùng ngày: không có thưởng.
			if _running:
				if _frames > 60 * 30:
					_check(false, "second run timed out (%s)" % str(_queue.front()))
					_running = false
					_queue.pop_front()
				return false
			if _frames > 1 and not _result.is_empty():
				var id: StringName = _queue.pop_front()
				var gained: int = GameState.money - _money
				_check(gained == 0 and _exp_gained() == 0, "%s: no second reward the same day (money %+d)" % [id, gained])
				_result = {}
			if _queue.is_empty():
				_sub = 0
				_next()
				return false
			_frames = 1
			_start_activity(_queue.front(), 1 if _queue.front() == &"fish_house" else 0)
		9:
			if _running:
				return false
			if _sub == 0:
				# Sang ngày mới: mở lại, dò vé số.
				Activities.new_day()
				_check(Activities.is_available(&"farm") and Activities.is_available(&"site") and Activities.lottery_result_ready(), "new day re-opens activities and the lottery can be checked")
				_sub = 1
				_start_activity(&"lottery")
				return false
			if _sub == 1:
				var won: int = int(_result.get("won", -1))
				var delta: int = GameState.money - _money
				_check(Activities.lottery_ticket != "" and won in [0, Activities.LOTTERY_CONSOLATION, Activities.LOTTERY_PRIZE] \
					and delta == won - Activities.LOTTERY_PRICE, "lottery: old ticket checked (won %d), a new one bought (money %+d)" % [won, delta])
				# Chưa có gà: vẫn được tiền, không cộng EXP.
				GameState.stage = GameState.Stage.GO_CHU_TU
				_sub = 2
				_start_activity(&"farm")
				return false
			if _sub == 2:
				_check(GameState.money > _money and GameState.xp == _xp and GameState.level == _level, "farm on a new day pays again; no EXP before owning a chicken")
				GameState.stage = GameState.Stage.TUTORIAL
				# Lưu/tải trạng thái hoạt động.
				Activities.save()
				var day: int = Activities.day
				var done: Dictionary = Activities.done_today.duplicate()
				var ticket: String = Activities.lottery_ticket
				Activities.reset()
				_check(Activities.load_save() and Activities.day == day and Activities.done_today == done \
					and Activities.lottery_ticket == ticket and Activities.temple_gift_taken, "activity state survives save/load")
				DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
				_check(_world.interactions_enabled and _runner.current_game == null, "world interactions restored after activities")
				_check(not _dialog.is_open(), "dialog closed at the end")
				print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
				quit(1 if _failures > 0 else 0)
				return true
	return false


func _verify_first(entry: Array, result: Dictionary) -> void:
	var kind: String = entry[2]
	var gained: int = GameState.money - _money
	var exp_gain: int = _exp_gained()
	var cancelled: bool = bool(result.get("cancelled", false))
	match kind:
		"fish":
			var fish: int = int(result.get("fish", -1))
			_check(not cancelled and fish == 3 and gained == 3 * Activities.FISH_PRICE, "kéo vó: autopilot catches 3 fish, sold for %+d" % gained)
		"feed":
			_check(not cancelled and int(result.get("thrown", 0)) == 3 and gained == 0, "cho cá ăn: 3 handfuls thrown, free")
		"farm":
			_check(not cancelled and int(result.get("bundles", 0)) == 8 and gained == 8 * Activities.RICE_MONEY_PER_BUNDLE \
				and exp_gain == 8 * Activities.RICE_EXP_PER_BUNDLE, "gặt lúa: 8 bundles → %+d, +%d EXP" % [gained, exp_gain])
		"school":
			_check(not cancelled and int(result.get("right", 0)) == 3 and gained == 3 * Activities.QUIZ_MONEY_PER_RIGHT \
				and exp_gain == 3 * Activities.QUIZ_EXP_PER_RIGHT, "quiz: 3/3 right → %+d, +%d EXP" % [gained, exp_gain])
		"site":
			_check(not cancelled and bool(result.get("full", false)) and gained == Activities.BRICK_FULL_PAY, "bốc gạch: full shift of 8 → %+d" % gained)
		"temple":
			_check(not cancelled and gained == Activities.TEMPLE_FIRST_GIFT and String(result.get("fortune", "")) != "", "đền: incense + fortune, first-time gift %+d" % gained)
		"lottery":
			_check(not cancelled and gained == -Activities.LOTTERY_PRICE and Activities.lottery_ticket.length() == 6, "vé số: ticket bought for %+d" % gained)


func _next() -> void:
	_step += 1
	_frames = 0
