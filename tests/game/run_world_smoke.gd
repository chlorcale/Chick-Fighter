extends SceneTree

## Smoke test thế giới (bản đồ mở rộng 5120×2160): đò ngang (một chiếc, đò bản đồ đã ẩn), danh sách lựa chọn cuộn
## được, các hoạt động chạy hết headless (autopilot) và thưởng mỗi ngày một lần, sang ngày mới, cầu ván cá tra;
## bản đồ mới: atlas/thời gian tải trong ngân sách, mọi địa danh + điểm tương tác đi bộ tới được từ SPAWN (A* trên lưới
## đi 4 px, kiểm lại từng ô của đường đi bằng va chạm thật của người chơi), xe máy tới được các địa danh có đường,
## bản đồ lớn M mở/đóng + đường gợi ý, toán mũi tên mép màn hình, bảng chỉ đường, chợ đông vẫn còn lối đi;
## giao thông đã tách khỏi bản đồ (traffic.json + atlas + water/roads, đường nằm trên mặt đường/nước, bến thuyền), xe khô
## gà + hai sân gà của chủ dự án (va chạm, cổng tới được, không vào trong sới), camera thu phóng theo nấc.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_world_smoke.gd

const Activities := preload("res://game/world/activities.gd")
const ActivityRunner := preload("res://game/world/activity_runner.gd")
const TEST_SAVE: String = "user://test_world_smoke.cfg"
## Ngân sách: trang atlas ≤ 4096 px mỗi cạnh, tổng VRAM atlas ≤ 200 MB, dựng World ≤ 3 s (headless, lần đầu).
const ATLAS_MAX_SIDE: int = 4096
const VRAM_BUDGET_MB: float = 200.0
const BUILD_BUDGET_MS: float = 3000.0
## Địa danh phải tới được bằng xe máy (có đường) từ chỗ đỗ xe ở nhà.
const BIKE_PLACES: Array[StringName] = [&"market", &"floating_market", &"cat_shop", &"thpt", &"arena_lien_tinh",
	&"arena_olympic", &"school", &"temple"]
## Cửa vào chợ (đầu các lối chính) và điểm đứng trước các sạp có tương tác.
const MARKET_ENTRANCES: Array[Vector2] = [Vector2(2005, 1010), Vector2(2486, 800), Vector2(3175, 1010), Vector2(2486, 1236)]
const MARKET_VENDORS: Array[StringName] = [&"market_chicken", &"market_eggs", &"market_food", &"market_gear", &"cat_shop"]
const ViewSettings := preload("res://game/world/view_settings.gd")
const TEST_VIEW: String = "user://test_world_view_settings.cfg"
## Tên layer giao thông (đã tách khỏi bản đồ → không được còn node nào trùng tên / bắt đầu bằng các tiền tố này).
const TRAFFIC_PREFIXES: Array[String] = ["N_xe_may_", "N_vo_lai_song_", "A_xe_may_", "C_xe_may_", "song_vo_lai_"]

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
var _build_ms: float = 0.0


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.TUTORIAL # đã có gà → nhận EXP
	Activities.save_path = TEST_SAVE
	Activities.reset()
	ViewSettings.save_path = TEST_VIEW # không đụng thiết lập thu phóng thật của người chơi
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_VIEW))
	Activities.rng.seed = 4242
	seed(4242)
	_dialog = DialogBox.new()
	root.add_child(_dialog)
	var t0: int = Time.get_ticks_usec()
	_world = World.new()
	root.add_child(_world)
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
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
		var quiz: Object = _runner.current_quiz # trang câu đố (quiz_page.gd) hoặc null
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


# ------------------------------------------------------------------ đi được tới đâu (BFS theo chân, vùng nhỏ)

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


# ------------------------------------------------------------------ đi được trên toàn bản đồ (A* lưới 4 px)

## A* 4 hướng trên lưới đi 4 px (bit bit_mask của nav.png: 1 chân, 2 xe máy). Ô = tâm (4x+2, 4y+2).
func _make_astar(bit_mask: int) -> AStarGrid2D:
	var size: Vector2i = _world.nav_size()
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(World.NAV_CELL, World.NAV_CELL)
	astar.offset = Vector2(2, 2)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in range(size.y):
		var start: int = -1
		for x in range(size.x + 1):
			var open: bool = x < size.x and (_world._nav[y * size.x + x] & bit_mask) != 0
			if not open and start < 0:
				start = x
			elif open and start >= 0:
				astar.fill_solid_region(Rect2i(start, y, x - start, 1), true)
				start = -1
		if start >= 0:
			astar.fill_solid_region(Rect2i(start, y, size.x - start, 1), true)
	return astar


## Ô đi được gần p nhất (trong bán kính radius px), hoặc (-1,-1).
func _cell_near(astar: AStarGrid2D, p: Vector2, radius: float) -> Vector2i:
	var c := Vector2i(p / World.NAV_CELL)
	var r: int = int(ceilf(radius / World.NAV_CELL))
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dy)
			if not astar.region.has_point(q) or astar.is_point_solid(q):
				continue
			var d: float = (Vector2(q * World.NAV_CELL) + Vector2(2, 2)).distance_to(p)
			if d <= radius and d < best_d:
				best_d = d
				best = q
	return best


## Đường từ start tới target (đứng trong bán kính radius), kiểm lại mọi ô bằng WorldPlayer._blocked_at.
## Trả về "" nếu tốt, hoặc lý do lỗi.
func _path_check(astar: AStarGrid2D, start: Vector2, target: Vector2, radius: float, riding: bool) -> String:
	var a: Vector2i = _cell_near(astar, start, 8.0)
	var b: Vector2i = _cell_near(astar, target, radius)
	if a.x < 0:
		return "start not walkable"
	if b.x < 0:
		return "no walkable cell within %.0f px of target" % radius
	var path: Array[Vector2i] = astar.get_id_path(a, b)
	if path.is_empty():
		return "no path"
	var p: WorldPlayer = _world.player
	var was: bool = p.riding
	p.riding = riding
	var bad: String = ""
	for cell in path:
		var pos := Vector2(cell * World.NAV_CELL) + Vector2(2, 2)
		if p._blocked_at(pos):
			bad = "path cell %s blocked at runtime" % pos
			break
	p.riding = was
	return bad


func _check_reachability() -> void:
	var t0: int = Time.get_ticks_usec()
	var foot: AStarGrid2D = _make_astar(1)
	var bike: AStarGrid2D = _make_astar(2)
	var fails: Array[String] = []
	for item in World.INTERACTABLES:
		var id: StringName = item["id"]
		if id == &"ferry_south" or id == &"fish_house":
			continue # bờ nam xóm cũ: chỉ qua bằng đò / cầu ván – kiểm riêng ở bước cá tra & đò
		var why: String = _path_check(foot, World.SPAWN, _world.interactable_pos(item), float(item["radius"]) - 1.0, false)
		if why != "":
			fails.append("%s (%s)" % [id, why])
	_check(fails.is_empty(), "every INTERACTABLE reachable on foot from SPAWN, path re-checked at runtime %s" % str(fails))
	fails.clear()
	for id in World.PLACES:
		var why: String = _path_check(foot, World.SPAWN, World.PLACES[id]["pos"], 20.0, false)
		if why != "":
			fails.append("%s (%s)" % [id, why])
	_check(fails.is_empty(), "every PLACE reachable on foot from SPAWN %s" % str(fails))
	fails.clear()
	for id in BIKE_PLACES:
		var why: String = _path_check(bike, World.BIKE_START, World.PLACES[id]["pos"], 28.0, true)
		if why != "":
			fails.append("%s (%s)" % [id, why])
	_check(fails.is_empty(), "motorbike reaches %d road-side places from the parked bike %s" % [BIKE_PLACES.size(), str(fails)])
	print("      reachability: %.0f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))


## Chợ đông vẫn còn lối: mô phỏng người đi chợ, coi mỗi người là vật chặn bán kính 7 px, BFS lưới 4 px trong chợ
## từ mọi cửa vào tới mọi sạp có tương tác.
func _check_market_aisles() -> void:
	var crowd: Node = _world.market_crowd
	_check(crowd != null and int(crowd.get("people").size()) >= 30, "market crowd spawned (%d shoppers)" % crowd.get("people").size())
	var box := Rect2i(1990, 650, 1200, 620)
	var cells := Rect2i(box.position / World.NAV_CELL, box.size / World.NAV_CELL)
	var ok_all: bool = true
	var moved: float = 0.0
	var before: PackedVector2Array = crowd.call("positions")
	for second in range(12):
		for k in range(30):
			crowd.call("step", 1.0 / 30.0)
		var occupied := {}
		for pos in crowd.call("positions"):
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					occupied[Vector2i(pos / World.NAV_CELL) + Vector2i(dx, dy)] = true
		for vendor in MARKET_VENDORS:
			var goal: Vector2 = _world.interactable_pos(_world.find_interactable(vendor))
			for entrance in MARKET_ENTRANCES:
				if not _bfs_cells(cells, Vector2i(entrance / World.NAV_CELL), Vector2i(goal / World.NAV_CELL), occupied):
					ok_all = false
					print("      t=%ds: %s blocked from entrance %s" % [second, vendor, entrance])
	var after: PackedVector2Array = crowd.call("positions")
	for i in range(mini(before.size(), after.size())):
		moved += before[i].distance_to(after[i])
	_check(ok_all, "market aisles: every entrance reaches every vendor while shoppers wander (12 s)")
	_check(moved > 200.0, "shoppers actually walk (total %.0f px in 12 s)" % moved)


func _bfs_cells(area: Rect2i, start: Vector2i, goal: Vector2i, occupied: Dictionary) -> bool:
	var ok := func(c: Vector2i) -> bool:
		return area.has_point(c) and (_world.nav_bits(c) & 1) != 0 and not occupied.has(c)
	# điểm đầu/cuối: lấy ô trống gần nhất
	for target in [start, goal]:
		pass
	var s: Vector2i = _nearest_ok(start, ok)
	var g: Vector2i = _nearest_ok(goal, ok)
	if s.x < 0 or g.x < 0:
		return false
	var seen := {s: true}
	var queue: Array[Vector2i] = [s]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c.distance_squared_to(g) <= 2:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and ok.call(n):
				seen[n] = true
				queue.append(n)
	return false


func _nearest_ok(c: Vector2i, ok: Callable) -> Vector2i:
	for r in range(0, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if ok.call(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return Vector2i(-1, -1)


func _check_budget() -> void:
	var map_view: MapView = _world.map_view
	var manifest: Dictionary = MapView.load_shared()["manifest"]
	var vram: float = 0.0
	var max_side: int = 0
	for tex in MapView.load_shared()["atlases"]:
		var t: Texture2D = tex
		vram += float(t.get_width() * t.get_height() * 4) / 1e6
		max_side = maxi(max_side, maxi(t.get_width(), t.get_height()))
	_check(max_side <= ATLAS_MAX_SIDE, "atlas pages ≤ %d px (%d pages, largest side %d)" % [ATLAS_MAX_SIDE, manifest["atlases"].size(), max_side])
	_check(vram <= VRAM_BUDGET_MB, "atlas VRAM %.1f MB ≤ %.0f MB" % [vram, VRAM_BUDGET_MB])
	_check(_build_ms <= BUILD_BUDGET_MS, "World build %.0f ms (atlas+manifest load %.0f ms, MapView nodes %.0f ms) ≤ %.0f ms" % [
		_build_ms, MapView.last_load_ms, MapView.last_build_ms, BUILD_BUDGET_MS])
	_check(World.MAP_SIZE == Vector2i(5120, 2160) and map_view.map_size == World.MAP_SIZE, "map is 5120×2160")
	_check(map_view.frame_count == 96 and map_view.frame_ms == 80, "map runs all 96 frames at 80 ms")
	print("      nodes: animated=%d named=%d, updated last frame=%d" % [map_view._animated.size(), map_view._by_name.size(), map_view.last_updated])
	# Mọi node mà code khác tra theo tên vẫn còn.
	var missing: Array[String] = []
	for n in ["C_ca_tra_con_01", "N_lao_ga_kho_xe_kho_ga_la_chanh", "N_san_lien_tinh_khan_dai", "N_san_olympia_khan_dai",
			"NV_co_ban_ve_so", "D_dua_02_than", "B_ga_nha_01", "E_vit_01", "NV_cho_vang", "song_do_ngang",
			"C_ca_tra_cau_van", "A_cau_van_ben_ghe", "N_npc_ba_Lan_ban_com", "N_npc_chu_quan_vong",
			"N_npc_danh_co_tuong", "N_npc_ong_cau_ca_ao_sen", "N_npc_chu_vuon_kieng"]:
		if not map_view.has_node_named(n):
			missing.append(n)
	_check(missing.is_empty(), "named map nodes still resolvable %s" % str(missing))
	# Bản đồ cũ giữ nguyên toạ độ: va chạm cũ.
	_check(_world.is_blocked(300, 400) and _world.is_blocked(100, 60) and not _world.is_blocked(660, 580),
		"old-area collision unchanged (river/house blocked, canal bridge open)")


## Xe khô gà Lão Gà Khô của chủ dự án (layer N_lao_ga_kho_xe_kho_ga_la_chanh) thay xe tự vẽ: node có thật, 8 ảnh khác nhau
## đổi theo nhịp 80 ms của bản đồ, xe tự vẽ cũ đã gỡ, va chạm chặn gốc xe/mía nhưng không chặn ngọn mía, chỗ đứng mua
## trước xe đi tới được, tên mới hiện ở chỗ người chơi thấy.
func _check_lao_ga_kho() -> void:
	var map_view: MapView = _world.map_view
	var node: String = World.LAO_NODE
	_check(node == "N_lao_ga_kho_xe_kho_ga_la_chanh" and map_view.has_node_named(node) and map_view.node_textures(node).size() == 8,
		"owner's Lão Gà Khô cart layer is a map node with 8 images")
	var old_gone: bool = true
	for n in ["X_lao_ga_kho", "X_lao_ga_kho_mia_trai", "X_lao_ga_kho_mia_phai", "X_tiem_meo", "X_tiem_meo_bang", "X_meo_tiem"]:
		old_gone = old_gone and not map_view.has_node_named(n)
	_check(old_gone, "our generated cart / sugarcane / old Tiệm Mèo kiosk are gone")
	var rect: Variant = map_view.node_rect(node)
	_check(rect is Rect2 and (rect as Rect2).has_point(Vector2(2990, 980)) and absf((rect as Rect2).end.y - 1026.0) <= 1.0,
		"cart stands in the east market plaza, wheels on y≈1026 (%s)" % str(rect))
	# hoạt ảnh: 8 frame bản đồ liên tiếp (80 ms) → 8 ảnh khác nhau, vòng lại sau 640 ms
	var seen := {}
	for k in range(8):
		map_view.set_time_ms(float(k) * 80.0 + 40.0)
		seen[map_view.node_region_index(node)] = true
	map_view.set_time_ms(640.0 + 40.0)
	var loops: bool = map_view.node_region_index(node) == (func() -> int:
		map_view.set_time_ms(40.0)
		return map_view.node_region_index(node)).call()
	_check(seen.size() == 8 and loops, "cart animates 8 distinct images at the map's 80 ms rate (%d distinct)" % seen.size())
	map_view.set_time_ms(0.0)
	_check(_world.is_blocked(2990, 1020) and _world.is_blocked(2930, 1015) and _world.is_blocked(3050, 1015),
		"collision: cart base and both sugarcane bases blocked")
	_check(not _world.is_blocked(2935, 960) and not _world.player._blocked_at(World.PLACES[&"cat_shop"]["pos"]),
		"collision: leafy cane tops not blocked, buy spot in front of the cart walkable")
	var door: Vector2 = World.PLACES[&"cat_shop"]["pos"]
	_check(door == _world.find_interactable(&"cat_shop")["pos"] and (rect as Rect2).grow(30.0).has_point(door) and door.y > (rect as Rect2).end.y,
		"cat_shop interaction point sits just in front of the owner's cart (%s)" % str(door))
	_check(String(World.PLACES[&"cat_shop"]["name"]).contains("Lão Gà Khô") and String(World.PLACES[&"cat_shop"]["icon"]) == "cart"
		and String(_world.find_interactable(&"cat_shop")["label"]).begins_with("Lão Gà Khô"), "place name, map icon and [E] label say Lão Gà Khô")
	_check((rect as Rect2).grow(12.0).has_point(World.LAO_BARK_ANCHOR) and (rect as Rect2).has_point(World.MARKER_TARGETS[&"cat_shop"] + Vector2(0, 12)),
		"bark bubble + marker arrow anchored on the owner's cart")
	var sign: String = _world.sign_text(&"sign_market_nw")
	_check(sign.contains("Lão Gà Khô") and not sign.contains("Tiệm Mèo"), "market signpost points to Lão Gà Khô")
	_world.lao_bark(0)
	_check(_world._bark.visible and _world._bark.text.contains("lá chanh"), "walk-by bark bubble shows")
	_world._bark.visible = false


## Hai sân gà của chủ dự án: điểm tương tác ở cổng (tới được – kiểm trong _check_reachability), sân tự vẽ cũ đã gỡ,
## khán đài/rào/bên trong sới không đi vào được, biển chỉ đường + bản đồ M dùng vị trí mới.
func _check_arenas() -> void:
	var map_view: MapView = _world.map_view
	_check(not map_view.has_node_named("X_soi_lien_tinh") and not map_view.has_node_named("X_nha_thi_dau_olympic")
		and map_view.has_node_named("N_san_lien_tinh_rao_vong_truoc") and map_view.has_node_named("N_san_olympia_day_vong_truoc"),
		"our Liên tỉnh building / Olympic dome removed; owner's arenas present")
	var foot: AStarGrid2D = _make_astar(1)
	var gates := {&"arena_lien_tinh": [Rect2(4440, 1024, 110, 14), Vector2(4495, 985), Vector2(4500, 870)],
		&"arena_olympic": [Rect2(4880, 1327, 118, 14), Vector2(4940, 1270), Vector2(4940, 1190)]}
	for id in gates:
		var sign_rect: Rect2 = gates[id][0]
		var pos: Vector2 = World.PLACES[id]["pos"]
		_check(pos == _world.find_interactable(id)["pos"] and absf(pos.x - sign_rect.get_center().x) < 40.0 and pos.y > sign_rect.end.y
			and pos.y - sign_rect.end.y < 80.0, "%s: entrance point right under the gate sign (%s)" % [id, str(pos)])
		var why: String = _path_check(foot, World.SPAWN, pos, 6.0, false)
		_check(why == "", "%s: gate reachable on foot from SPAWN %s" % [id, why])
		var pit: String = _path_check(foot, World.SPAWN, gates[id][1], 10.0, false)
		var stands: String = _path_check(foot, World.SPAWN, gates[id][2], 10.0, false)
		_check(pit != "" and stands != "", "%s: pit and stands cannot be walked into (%s / %s)" % [id, pit, stands])
	_check(_world.is_blocked(4495, 1050) and _world.is_blocked(4938, 1360), "gate thresholds blocked (player stops at the entrance)")


## Giao thông đã tách: không còn node xe/thuyền trong manifest; traffic.json + atlas + water/roads có và đọc được; đường xe
## nằm trên mặt đường, đường thuyền trên mặt nước (hoặc chui dưới cầu); bến thuyền: điểm nước là nước, điểm đứng đi được
## và tới được từ SPAWN; hàm lấy ảnh xe cho trò đua.
func _check_traffic() -> void:
	var manifest: Dictionary = MapView.load_shared()["manifest"]
	var leftovers: Array[String] = []
	for layer in ["below", "object", "above"]:
		for node in manifest[layer]:
			var n: String = String(node.get("name", node.get("part_of", "")))
			for prefix in TRAFFIC_PREFIXES:
				if n.begins_with(prefix):
					leftovers.append(n)
	_check(leftovers.is_empty(), "no traffic layer (bikes, boats, shadows, wakes) left in the map manifest %s" % str(leftovers.slice(0, 5)))
	var data: Dictionary = MapView.traffic_data()
	var atlas: Texture2D = load("res://game/art/world_map/traffic_atlas.png")
	var water: Image = load("res://game/art/world_map/water.png") as Image
	var roads: Image = load("res://game/art/world_map/roads.png") as Image
	_check(not data.is_empty() and atlas != null and water != null and roads != null
		and water.get_size() == World.MAP_SIZE and roads.get_size() == World.MAP_SIZE,
		"traffic.json, traffic_atlas.png, water.png, roads.png exist and parse (masks %s)" % str(water.get_size() if water else Vector2i.ZERO))
	if data.is_empty() or water == null or roads == null:
		return
	var vehicles: Dictionary = {}
	var regions_ok: bool = true
	var spots := {}
	for v in data["vehicles"]:
		vehicles[v["id"]] = v
		for d in ["east", "west"]:
			regions_ok = regions_ok and not v["frames"][d].is_empty()
			for r in v["frames"][d]:
				regions_ok = regions_ok and r[0] + r[2] <= atlas.get_width() and r[1] + r[3] <= atlas.get_height()
				spots[Vector2i(r[0], r[1])] = true
	_check(vehicles.size() >= 4 and regions_ok and spots.size() >= vehicles.size() * 2,
		"%d vehicle looks, frames for both directions, %d distinct atlas regions all inside the atlas" % [vehicles.size(), spots.size()])
	var bridges: Array[Rect2] = []
	for b in data["bridges"]:
		bridges.append(Rect2(b["rect"][0], b["rect"][1], b["rect"][2], b["rect"][3]).grow(6.0))
	var bad_routes: Array[String] = []
	var total: int = 0
	for route in data["routes"]:
		var mask: Image = roads if route["kind"] == "bike" else water
		var pts: Array = route["points"]
		var off: int = 0
		var samples: int = 0
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			var n: int = maxi(1, int(a.distance_to(b) / 8.0))
			for k in range(n):
				var p: Vector2 = a.lerp(b, float(k) / n)
				if p.x < 0 or p.y < 0 or p.x >= World.MAP_SIZE.x or p.y >= World.MAP_SIZE.y:
					continue # vào/ra ở mép bản đồ
				samples += 1
				if not _mask_near(mask, Vector2i(p), 8) and not bridges.any(func(r: Rect2) -> bool: return r.has_point(p)):
					off += 1
		total += samples
		# cho phép ≤ 3% mẫu lệch: thuyền trong tranh lướt sát mép cù lao giữa sông chính / nhà sàn ven sông (vật trên nước đã
		# trừ khỏi water.png)
		if samples == 0 or off > samples * 0.03:
			bad_routes.append("%s %d/%d" % [route["id"], off, samples])
	_check(bad_routes.is_empty(), "%d routes: bike routes on roads.png, boat routes on water.png (or under a bridge) within 8 px (≤ 3%% off), %d samples %s" % [
		data["routes"].size(), total, str(bad_routes)])
	var spawns_ok: bool = data["spawns"].size() >= 30
	for s in data["spawns"]:
		spawns_ok = spawns_ok and vehicles.has(s["vehicle"]) and data["routes"].any(func(r: Dictionary) -> bool: return r["id"] == s["route"])
	_check(spawns_ok, "%d spawns, each names an existing vehicle look and route" % data["spawns"].size())
	var foot: AStarGrid2D = _make_astar(1)
	var dock_fails: Array[String] = []
	for dock in data["docks"]:
		var wp := Vector2i(dock["water_pos"][0], dock["water_pos"][1])
		var pos := Vector2(dock["pos"][0], dock["pos"][1])
		var why: String = _path_check(foot, World.SPAWN, pos, 6.0, false)
		if water.get_pixelv(wp).r <= 0.0 or _world.player._blocked_at(pos) or why != "":
			dock_fails.append("%s (water=%s walk=%s %s)" % [dock["id"], water.get_pixelv(wp).r > 0.0, not _world.player._blocked_at(pos), why])
	_check(data["docks"].size() >= 4 and dock_fails.is_empty(), "%d boat docks: water_pos is water, pos walkable + reachable from SPAWN %s" % [
		data["docks"].size(), str(dock_fails)])
	var race_ok: bool = true
	for rider in World.RACE_BIKES:
		var vid: String = MapView.race_vehicle_id(rider)
		race_ok = race_ok and vid != "" and MapView.vehicle_textures(vid, "east").size() >= 2
	_check(race_ok, "every race rider maps to a traffic vehicle look with east-facing frames (race rival sprite)")
	# Tiếng máy giờ gắn vào xe thật của Traffic (không còn nguồn âm gắn node bản đồ); race_bike_source = giao thông thật.
	_check(_world.traffic != null and _world.traffic._emitters.size() == 7 and not _world.map_view.has_node_named("A_xe_may_con_tay_do")
		and _world.race_bike_source.is_valid(),
		"engine sounds + race detection re-hooked to live traffic (7 pooled emitters, no map vehicle nodes)")
	_check_vehicles_api()


## Tìm xe máy / vỏ lãi (UI bản đồ đọc), ông câu cá quay mặt ra nước, làm trong vật che người, mọi cầu cho thuyền qua.
func _check_vehicles_api() -> void:
	var changed: Array[int] = [0]
	_world.vehicles_changed.connect(func() -> void: changed[0] += 1)
	var events: Array[StringName] = []
	_world.achievement_event.connect(func(id: StringName) -> void: events.append(id))
	var was_riding: bool = _world.player.riding
	_check(_world.bike_parked == not was_riding and (_world.boat_moored_pos() == null or _world.player_boat.moored),
		"World exposes bike_pos / bike_parked / boat_moored_pos()")
	if not was_riding:
		var keep: Vector2 = _world.player.position
		_world.player.position = _world.bike_pos
		_world.mount_bike(true)
		_check(not _world.bike_parked and changed[0] == 1 and events.has(&"first_bike") and _world.vehicle_targets().filter(
			func(e: Dictionary) -> bool: return e["kind"] == "bike").is_empty(), "mounting hides the bike marker, emits vehicles_changed + first_bike")
		_world.mount_bike(false)
		_check(_world.bike_parked and changed[0] == 2 and _world.vehicle_targets().size() >= 1, "dismounting parks the bike and shows its marker again")
		_world.player.position = keep
	var fishers: Array = _world.fisher_nodes()
	_check(fishers.size() == 2 and _world.map_view.is_node_hidden("NV_ong_cau_ca") and _world.map_view.is_node_hidden("N_npc_ong_cau_ca_ao_sen"),
		"both fishermen replaced by the front-facing sprite (map nodes hidden)")
	var all_pass: bool = true
	for b in MapView.traffic_data().get("bridges", []):
		all_pass = all_pass and bool(b["player_boat_passes"])
	_check(all_pass and (MapView.traffic_data().get("fixes", []) as Array).has("boat_water_v1"),
		"map fixes applied: every bridge lets the player boat pass under, bow-lifting boats re-seated on the water")
	_check(MapView.find_look("bike_11").get("type") == "cruiser" and MapView.vehicle_textures("bike_23", "west").size() == 4,
		"new vehicle looks merged into traffic data (cruiser, bicycle…)")
	_check(MapView.focus_material() != null, "occluder fade uses the circular focus shader")


func _mask_near(mask: Image, p: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1, 2):
		for dx in range(-r, r + 1, 2):
			var q: Vector2i = p + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < mask.get_width() and q.y < mask.get_height() and mask.get_pixelv(q).r > 0.0:
				return true
	return false


## Camera: các nấc thu phóng, khung hình luôn nằm trong bản đồ ở bốn góc, toạ độ màn hình (mũi tên mép) theo đúng
## mức thu phóng, nhớ nấc đã chọn, phím/con lăn đổi nấc.
func _check_camera_zoom() -> void:
	_check(ViewSettings.ZOOM_STEPS.size() >= 3 and ViewSettings.DEFAULT_ZOOM == 2.5 and is_equal_approx(_world.zoom_target, 2.5),
		"default zoom ×2,5 (wider than the old ×3), steps %s" % str(ViewSettings.ZOOM_STEPS))
	var saved_pos: Vector2 = _world.player.position
	var corners: Array[Vector2] = [Vector2(8, 12), Vector2(5110, 12), Vector2(8, 2150), Vector2(5110, 2150), Vector2(2560, 1080)]
	var inside_ok: bool = true
	var arrow_ok: bool = true
	var map_rect := Rect2(Vector2.ZERO, Vector2(World.MAP_SIZE))
	for z in ViewSettings.ZOOM_STEPS:
		_world.set_zoom(z, true)
		for c in corners:
			_world.player.position = c
			_world.snap_camera()
			_world._camera.force_update_scroll()
			var view: Rect2 = _world.camera_view_rect()
			var seen: Rect2 = _world.map_view.visible_map_rect()
			if not map_rect.grow(0.51).encloses(view) or not map_rect.grow(0.51).encloses(seen) or view.position.distance_to(seen.position) > 1.0:
				inside_ok = false
				print("      zoom %.1f corner %s: view %s visible %s" % [z, c, view, seen])
		# mũi tên mép: toạ độ màn hình của mục tiêu xa = (p − tâm)·z + nửa màn hình
		_world.player.position = Vector2(2560, 1080)
		_world.snap_camera()
		_world._camera.force_update_scroll()
		var target: Vector2 = World.PLACES[&"arena_olympic"]["pos"]
		var screen: Vector2 = _world.map_to_screen(target)
		var view2: Rect2 = _world.camera_view_rect()
		var expect: Vector2 = (target - view2.get_center()) * z + _world.get_viewport_rect().size * 0.5
		var arrow: Array = World.edge_arrow(_world.get_viewport_rect().size, screen)
		if screen.distance_to(expect) > 1.5 or arrow.is_empty() or (arrow[0] as Vector2).x < _world.get_viewport_rect().size.x * 0.5:
			arrow_ok = false
			print("      zoom %.1f: screen %s expected %s arrow %s" % [z, screen, expect, arrow])
		_world._edge.queue_redraw()
	_check(inside_ok, "at every zoom step the view stays inside the map at all 4 corners (no void)")
	_check(arrow_ok, "edge arrow follows the viewport transform at every zoom step")
	# nhớ nấc đã chọn
	_world.set_zoom(3.0, true)
	ViewSettings._loaded = false
	ViewSettings.zoom_level = 2.0
	ViewSettings.ensure_loaded()
	_check(is_equal_approx(ViewSettings.zoom_level, 3.0), "chosen zoom is remembered in %s" % ViewSettings.save_path)
	# phím: − thu nhỏ, = phóng to, con lăn; thông báo ngắn
	_world.set_zoom(2.5, true)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_MINUS
	_world._unhandled_input(key)
	var after_minus: float = _world.zoom_target
	key.physical_keycode = KEY_KP_ADD
	_world._unhandled_input(key)
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	_world._unhandled_input(wheel)
	_check(is_equal_approx(after_minus, 2.0) and is_equal_approx(_world.zoom_target, 3.0) and _world._zoom_toast.visible
		and _world._zoom_toast.text == "Thu phóng ×3,0", "−/numpad + /wheel step the zoom 2,5→2,0→2,5→3,0 with a toast (%s)" % _world._zoom_toast.text)
	_world.set_zoom(ViewSettings.DEFAULT_ZOOM, true)
	_world._zoom_toast.visible = false
	_world.player.position = saved_pos
	_world.snap_camera()


func _check_wayfinding() -> void:
	# toán mũi tên mép màn hình
	var screen := Vector2(1280, 720)
	_check(World.edge_arrow(screen, Vector2(640, 360)).is_empty(), "edge arrow hidden when target on screen")
	var right: Array = World.edge_arrow(screen, Vector2(3000, 360))
	_check(not right.is_empty() and absf((right[0] as Vector2).x - (1280 - 46)) < 0.5 and absf((right[0] as Vector2).y - 360) < 0.5 \
		and absf(float(right[1])) < 0.001, "edge arrow: target far right → right edge, pointing right (%s)" % str(right))
	var up_left: Array = World.edge_arrow(screen, Vector2(-1000, -2000))
	var p: Vector2 = up_left[0] if not up_left.is_empty() else Vector2(-1, -1)
	_check(not up_left.is_empty() and absf(p.y - 46.0) < 0.5 and p.x > 46.0 and p.x < 640.0, "edge arrow: target up-left → top edge (%s)" % str(p))
	_check(World.format_distance(400.0) == "100 m" and World.format_distance(8000.0) == "2,0 km", "distance format (1 px = 0,25 m)")
	# set_status với id bất kỳ
	_world.set_status("Ngày 1", "Lên Nhà thi đấu Olympic", &"arena_olympic")
	_check(_world.marker_target == &"arena_olympic" and _world.target_position(&"arena_olympic") == World.PLACES[&"arena_olympic"]["pos"],
		"set_status accepts any PLACE id")
	_check(_world.target_position(&"market_gear") is Vector2 and _world.target_position(&"khong_co") == null, "target_position: interactable ids work, unknown → null")
	# bảng chỉ đường
	var text: String = _world.sign_text(&"sign_east")
	_check(text.contains("Olympic") and text.contains("Liên tỉnh") and text.contains(" m"), "signpost text lists landmarks with distance")
	# bản đồ lớn
	var overlay: Node = _world.map_overlay
	overlay.call("wait_grid")
	_world.player.position = World.SPAWN
	_world.player.can_move = true
	overlay.call("open_map")
	_check(bool(overlay.get("open")) and not _world.player.can_move, "M map opens and freezes the player")
	var route: PackedVector2Array = overlay.call("compute_route", World.SPAWN, World.PLACES[&"arena_olympic"]["pos"])
	_check(route.size() >= 2 and route[route.size() - 1].distance_to(World.PLACES[&"arena_olympic"]["pos"]) < 24.0,
		"suggested route home → Olympic (%d turns, ends %.0f px from the door)" % [route.size(),
		route[route.size() - 1].distance_to(World.PLACES[&"arena_olympic"]["pos"]) if route.size() > 0 else -1.0])
	overlay.call("close_map")
	_check(not bool(overlay.get("open")) and _world.player.can_move, "M map closes and frees the player")


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
			_check_budget()
			_check_reachability()
			_check_wayfinding()
			_check_market_aisles()
			_check_lao_ga_kho()
			_check_arenas()
			_check_traffic()
			_check_camera_zoom()
			_world.set_status("", "", &"")
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
				DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_VIEW))
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
