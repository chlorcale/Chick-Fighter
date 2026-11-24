extends Node2D

## Người đi bộ thông minh hơn: những người "walker_candidate" của game/art/world_map/people.json (79 người đi chợ, đi
## đường, dân xóm, học sinh) được thay bằng người chạy lúc chơi (node bản đồ cùng tên bị ẩn). Người "keep_static" (người
## bán, khán giả, nhân viên sới, NPC cốt truyện, npc_* hàng xóm có hội thoại…) để nguyên trên bản đồ → mọi tương tác giữ
## nguyên.
## - Nhà = chỗ đứng trong tranh. Lịch nhỏ theo vai: người đi chợ → các sạp/cửa chợ, học sinh → cổng/sân THPT, dân xóm →
##   nhà hàng xóm, đình/đền/chợ/quán gần, người đi đường → các ngã ba/bảng chỉ đường; chỉ chọn nơi cách nhà ≤ 800 px.
##   Tới nơi thì đứng 4–14 s rồi chọn chỗ khác (30% về nhà).
## - Tìm đường: A* (AStarGrid2D) trên lưới 8 px dựng từ nav.png (ô đi được = cả 4 ô 4 px đứng được bằng chân và nối với
##   SPAWN), dựng trong luồng phụ (WorkerThreadPool) lúc vào World. Trọng số: mặt đường/lối đi 1, đất trống 1,6, làn xe
##   máy (±12 px quanh đường xe chạy) 4 → đi dọc lề, băng qua đường vuông góc.
## - Trước khi bước xuống làn xe: hỏi Traffic.lane_busy (xe sắp tới trong 2,2 s) → đứng chờ ở lề (tối đa 6 s). Xe cũng
##   nhường người đi bộ; bị bóp kèn khi đang ở làn thì né sang lề rồi tìm đường lại.
## - Né người chơi: không bao giờ bước vào trong 9 px quanh chân người chơi; bị chắn > 1,2 s thì bước tránh sang bên rồi
##   tìm đường lại.
## - Hai người gặp nhau (< 20 px) có thể dừng lại nói chuyện 3–6 s, quay mặt vào nhau (mỗi người nghỉ 40 s mới chuyện tiếp).
## - Tối (GameState Period TOI/KHUYA): 70% về nhà rồi vào trong (ẩn), sáng ra lại; 30% vẫn đi dạo → đêm vắng hơn.
##   Người đi chợ của MarketCrowd cũng chỉ còn 1/3 hiện ra lúc tối.
## - Hoạt ảnh: 3 người có chu kỳ đi 7 khung trong tranh dùng khung thật (đi đông/tây); người chỉ có 2 khung đứng nhún
##   dùng bước giả: đổi khung + nhún 1 px + nghiêng nhẹ + lật ngang theo hướng đi.
## - Hiệu năng: chỉ người trong vùng camera nới 0,5 khung mỗi phía được cập nhật đủ (tối đa MAX_NEAR); người ở xa đi
##   tiếp theo đường đã tính với nhịp 4 Hz, ẩn node.

const PEOPLE_PATH: String = "res://game/art/world_map/people.json"
const ATLAS_PATH: String = "res://game/art/world_map/people_atlas.png"
const CELL: int = 8
const GRID: Vector2i = Vector2i(640, 270)
const MAX_NEAR: int = 48
const MAX_TRIP: float = 800.0
const AVOID_R: float = 9.0
const CHAT_R: float = 20.0
const CHAT_COOLDOWN: float = 40.0
const LANE_WAIT_MAX: float = 6.0
const NIGHT_HOME_SHARE: int = 7 # trên 10
const NEAR_GROW: float = 0.5
## Khung đi thật của 3 người có chu kỳ 7 khung (chỉ số region trong people.json).
const WALK_SETS: Dictionary = {
	"NV_dam_trang_o_nha_vuon": {"idle": 0, "east": [4, 5, 6, 5], "west": [1, 2, 3, 2]},
	"NV_non_den_jean_goi_dien": {"idle": 3, "east": [0, 1, 0, 2], "west": [5, 6, 5, 4]},
	"NV_vest_ca_vat_do_o_san_den": {"idle": 3, "east": [0, 1, 0, 2], "west": [4, 5, 4, 6]},
}
## Điểm hẹn theo vai (toạ độ bản đồ, dồn về ô đi được gần nhất lúc dựng).
const ROLE_SPOTS: Dictionary = {
	"shopper": [Vector2(2480, 960), Vector2(3124, 1000), Vector2(3134, 1062), Vector2(2812, 1014), Vector2(2840, 1182),
		Vector2(2005, 1010), Vector2(2486, 800), Vector2(3175, 1010), Vector2(2486, 1236), Vector2(2700, 730)],
	"student": [Vector2(4540, 313), Vector2(4420, 300), Vector2(4700, 300), Vector2(3975, 353), Vector2(4120, 262)],
	"resident": [Vector2(900, 1046), Vector2(818, 200), Vector2(2480, 960), Vector2(1672, 352), Vector2(3746, 762),
		Vector2(2180, 1688), Vector2(4076, 1659), Vector2(4426, 1804), Vector2(4508, 1100)],
	"passerby": [Vector2(1296, 194), Vector2(1986, 802), Vector2(3648, 548), Vector2(4324, 1087), Vector2(3186, 1254),
		Vector2(1300, 560), Vector2(3975, 353), Vector2(2480, 230)],
}

enum St { IDLE, WALK, CURB, CHAT, INSIDE, PENDING }

var world: Node
var rng := RandomNumberGenerator.new()
var walkers: Array[Dictionary] = []
## true khi lưới A* đã dựng xong.
var ready_grid: bool = false
## Thống kê/test.
var near_count: int = 0
var chats_started: int = 0
var path_requests: int = 0
var last_step_usec: int = 0

var _astar: AStarGrid2D
var _walk := PackedByteArray() # 1 = ô 8 px đi được
var _comp := PackedInt32Array() # số vùng liền của từng ô (−1 = không đi được)
## Số lần tìm đường còn được phép trong bước này (A* dài tốn vài ms → rải ra nhiều bước).
var _path_budget: int = 3
var _lane := PackedByteArray() # 1 = ô thuộc làn xe máy
var _task: int = -1
var _atlas: Texture2D
var _night: bool = false
var _period_check: float = 0.0
var _chat_check: float = 0.0
var _tick: int = 0
## Người ở xa cập nhật mỗi FAR_EVERY bước (so le theo chỉ số).
const FAR_EVERY: int = 15
var _spots: Dictionary = {}


func _ready() -> void:
	rng.seed = 20261124
	_atlas = load(ATLAS_PATH)
	var file := FileAccess.open(PEOPLE_PATH, FileAccess.READ)
	if file == null or world == null:
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	for person in data["people"]:
		if bool(person.get("walker_candidate", false)) and not bool(person.get("keep_static", false)):
			_add_walker(person)
	_lane = _lane_mask()
	var nav: PackedByteArray = world.get("_nav")
	var lane: PackedByteArray = _lane
	_task = WorkerThreadPool.add_task(_build_grid.bind(nav, lane), true, "Pedestrians A*")


func _add_walker(person: Dictionary) -> void:
	var id: String = String(person["id"])
	var regions: Array = person["regions"]
	var holder := Node2D.new()
	holder.name = "Walker_" + id
	var sprite := Sprite2D.new()
	sprite.texture = _atlas
	sprite.centered = false
	sprite.region_enabled = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(sprite)
	var pos := Vector2(person["pos"][0], person["pos"][1])
	var topleft := Vector2(person["topleft"][0], person["topleft"][1])
	var size0 := Vector2(person["size"][0], person["size"][1])
	var w: Dictionary = {
		"id": id, "role": String(person.get("role", "passerby")), "home": pos, "pos": pos, "holder": holder,
		"sprite": sprite, "regions": regions, "anchor_dx": topleft.x - pos.x + size0.x * 0.5,
		"anchor_bottom": topleft.y + size0.y - pos.y, "state": St.PENDING, "timer": rng.randf_range(0.5, 6.0),
		"path": PackedVector2Array(), "pi": 0, "dest": pos, "speed": rng.randf_range(22.0, 32.0), "anim": rng.randf() * 4.0,
		"face": 1.0 if rng.randf() < 0.5 else -1.0, "wait": 0.0, "chat_cd": rng.randf_range(0.0, 20.0), "partner": -1,
		"night_home": (walkers.size() * 7 + 3) % 10 < NIGHT_HOME_SHARE, "walk_set": WALK_SETS.get(id, {}),
		"near": false, "moving": false, "detour": false, "index": walkers.size(),
	}
	walkers.append(w)
	_set_frame(w, int(w["walk_set"].get("idle", 0)) if not (w["walk_set"] as Dictionary).is_empty() else 0, 0.0)
	holder.position = pos
	if world.get("map_view") != null:
		if world.map_view.has_node_named(id):
			world.map_view.set_node_hidden(id, true)
		world.map_view.add_actor(holder)
	else:
		add_child(holder)


## Làn xe máy (ô 8 px trong ±12 px quanh đường xe chạy của Traffic).
func _lane_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(GRID.x * GRID.y)
	var traffic: Node = world.get("traffic")
	if traffic == null:
		return mask
	for id in traffic.routes:
		var route: Object = traffic.routes[id]
		if String(route.get("kind")) != "bike":
			continue
		var length: float = float(route.get("length"))
		var s: float = 0.0
		while s <= length:
			var p: Vector2 = route.call("pos_at", s)
			for dy in [-12.0, -6.0, 0.0, 6.0, 12.0]:
				var c := Vector2i(int(p.x) / CELL, int(p.y + dy) / CELL)
				if c.x >= 0 and c.y >= 0 and c.x < GRID.x and c.y < GRID.y:
					mask[c.y * GRID.x + c.x] = 1
			s += 4.0
	return mask


## Luồng phụ: dựng lưới đi 8 px + AStarGrid2D.
func _build_grid(nav: PackedByteArray, lane: PackedByteArray) -> void:
	var nav_w: int = GRID.x * 2
	var walk := PackedByteArray()
	walk.resize(GRID.x * GRID.y)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, GRID.x, GRID.y)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL / 2, CELL / 2)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for cy in range(GRID.y):
		for cx in range(GRID.x):
			var i0: int = (cy * 2) * nav_w + cx * 2
			var a: int = nav[i0] & nav[i0 + 1] & nav[i0 + nav_w] & nav[i0 + nav_w + 1]
			var ok: bool = (a & 1) != 0 and (a & 16) != 0
			var cell := Vector2i(cx, cy)
			if not ok:
				astar.set_point_solid(cell, true)
				continue
			walk[cy * GRID.x + cx] = 1
			var road: bool = ((nav[i0] | nav[i0 + 1] | nav[i0 + nav_w] | nav[i0 + nav_w + 1]) & 4) != 0
			if lane[cy * GRID.x + cx] == 1:
				astar.set_point_weight_scale(cell, 4.0)
			elif not road:
				astar.set_point_weight_scale(cell, 1.6)
	# Vùng liền (4 hướng) của lưới 8 px: chỉ tìm đường trong cùng vùng (A* tới ô không tới được sẽ quét cả bản đồ).
	var comp := PackedInt32Array()
	comp.resize(GRID.x * GRID.y)
	comp.fill(-1)
	var label: int = 0
	var queue := PackedInt32Array()
	for i in range(walk.size()):
		if walk[i] != 1 or comp[i] >= 0:
			continue
		comp[i] = label
		queue.resize(0)
		queue.append(i)
		var head: int = 0
		while head < queue.size():
			var c: int = queue[head]
			head += 1
			var cx: int = c % GRID.x
			for n in [c - 1, c + 1, c - GRID.x, c + GRID.x]:
				if n < 0 or n >= walk.size() or walk[n] != 1 or comp[n] >= 0:
					continue
				if (n == c - 1 and cx == 0) or (n == c + 1 and cx == GRID.x - 1):
					continue
				comp[n] = label
				queue.append(n)
		label += 1
	_comp = comp
	_astar = astar
	_walk = walk


## Đợi lưới dựng xong (test, hoặc lần đầu cần).
func wait_ready() -> void:
	if ready_grid or _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_finish_grid()


func _finish_grid() -> void:
	ready_grid = _astar != null
	if not ready_grid:
		return
	for role in ROLE_SPOTS:
		var list: Array[Vector2] = []
		for p in ROLE_SPOTS[role]:
			var snapped: Variant = nearest_walkable(p, 10)
			if snapped != null:
				list.append(snapped)
		_spots[role] = list
	for w in walkers:
		var snapped: Variant = nearest_walkable(w["home"], 6)
		if snapped == null:
			w["state"] = St.INSIDE # không có chỗ đi được quanh nhà → đứng yên như tranh (không xảy ra với dữ liệu hiện tại)
			w["stuck"] = true
			continue
		w["home_cell"] = snapped
		w["pos"] = snapped
		(w["holder"] as Node2D).position = (snapped as Vector2).round()
		w["state"] = St.IDLE


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# =================================================================== lưới

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x) / CELL, 0, GRID.x - 1), clampi(int(p.y) / CELL, 0, GRID.y - 1))


func walkable(p: Vector2) -> bool:
	if _walk.is_empty():
		return false
	var c: Vector2i = cell_of(p)
	return _walk[c.y * GRID.x + c.x] == 1


func is_lane(p: Vector2) -> bool:
	var c: Vector2i = cell_of(p)
	return not _lane.is_empty() and _lane[c.y * GRID.x + c.x] == 1


## Tâm ô đi được gần nhất trong bán kính (ô), hoặc null.
func nearest_walkable(p: Vector2, radius: int) -> Variant:
	var c0: Vector2i = cell_of(p)
	for r in range(radius + 1):
		var best: Variant = null
		var best_d: float = INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := c0 + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0 or c.x >= GRID.x or c.y >= GRID.y or _walk[c.y * GRID.x + c.x] != 1:
					continue
				var center := Vector2(c * CELL) + Vector2(CELL / 2, CELL / 2)
				var d: float = center.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = center
		if best != null:
			return best
	return null


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	path_requests += 1
	if _astar == null:
		return PackedVector2Array()
	var a: Vector2i = cell_of(from)
	var b: Vector2i = cell_of(to)
	if _astar.is_point_solid(a):
		var snapped: Variant = nearest_walkable(from, 4)
		if snapped == null:
			return PackedVector2Array()
		a = cell_of(snapped)
	if _astar.is_point_solid(b) or _comp[a.y * GRID.x + a.x] != _comp[b.y * GRID.x + b.x]:
		return PackedVector2Array()
	return _astar.get_point_path(a, b)


## Cùng vùng liền (đi bộ tới được) không.
func same_area(p: Vector2, q: Vector2) -> bool:
	if _comp.is_empty():
		return false
	var a: Vector2i = cell_of(p)
	var b: Vector2i = cell_of(q)
	return _comp[a.y * GRID.x + a.x] >= 0 and _comp[a.y * GRID.x + a.x] == _comp[b.y * GRID.x + b.x]


# =================================================================== mô phỏng

func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	if not ready_grid:
		if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_finish_grid()
		return
	_path_budget = 3
	_period_check -= delta
	if _period_check <= 0.0:
		_period_check = 1.0
		_update_night()
	var near_rect: Rect2 = _near_rect()
	var player_pos := Vector2(-9999, -9999)
	if world.get("player") != null and (world.player as Node2D).visible:
		player_pos = world.player.position
	near_count = 0
	_tick += 1
	for w in walkers:
		var near: bool = near_rect.has_point(w["pos"]) and near_count < MAX_NEAR and w["state"] != St.INSIDE
		if near:
			near_count += 1
		w["near"] = near
		(w["holder"] as Node2D).visible = near
		if near:
			_update_walker(w, delta, player_pos)
		else:
			# Người ở xa: cập nhật so le, mỗi người 4 lần/giây (gộp thời gian đã trôi).
			w["far_dt"] = float(w.get("far_dt", 0.0)) + delta
			if (_tick + int(w["index"])) % FAR_EVERY == 0:
				_update_far(w, float(w["far_dt"]))
				w["far_dt"] = 0.0
	_chat_check -= delta
	if _chat_check <= 0.0:
		_chat_check = 0.5
		_try_chats()
	last_step_usec = Time.get_ticks_usec() - t0


func _near_rect() -> Rect2:
	if world != null and world.has_method("camera_view_rect") and world.get("_camera") != null:
		var view: Rect2 = world.camera_view_rect()
		return view.grow_individual(view.size.x * NEAR_GROW, view.size.y * NEAR_GROW, view.size.x * NEAR_GROW, view.size.y * NEAR_GROW)
	return Rect2(-1e6, -1e6, 2e6, 2e6)


func _update_night() -> void:
	var night: bool = GameState.period() >= GameState.Period.TOI
	if night == _night:
		return
	_night = night
	# Chợ vãn về tối: ẩn 2/3 người đi chợ của MarketCrowd (vẫn chạy, chỉ không hiện) – sáng hiện lại.
	var crowd: Node = world.get("market_crowd")
	if crowd != null:
		var people: Array = crowd.get("people")
		for i in range(people.size()):
			(people[i]["sprite"] as Node2D).visible = not night or i % 3 == 0
	for w in walkers:
		if w.get("stuck", false):
			continue
		if night and bool(w["night_home"]):
			w["going_home"] = true
			_go(w, w["home_cell"])
		elif not night and w["state"] == St.INSIDE:
			w["state"] = St.IDLE
			w["timer"] = rng.randf_range(0.5, 8.0)
			w["going_home"] = false
			w["pos"] = w["home_cell"]
			(w["holder"] as Node2D).position = (w["pos"] as Vector2).round()
		elif not night:
			w["going_home"] = false


## Chọn chỗ đến tiếp theo theo vai.
func _pick_destination(w: Dictionary) -> Vector2:
	var home: Vector2 = w["home_cell"]
	if rng.randf() < 0.3 and (w["pos"] as Vector2).distance_to(home) > 24.0:
		return home
	var options: Array[Vector2] = []
	var here: Vector2 = w["pos"]
	for p in _spots.get(String(w["role"]), []):
		if (p as Vector2).distance_to(home) <= MAX_TRIP and same_area(here, p):
			options.append(p)
	for other in walkers:
		if other != w and other.has("home_cell") and (other["home_cell"] as Vector2).distance_to(home) <= 600.0 				and same_area(here, other["home_cell"]):
			options.append(other["home_cell"])
	if options.is_empty():
		return home
	return options[rng.randi() % options.size()]


func _go(w: Dictionary, dest: Vector2) -> void:
	if _path_budget <= 0:
		# hết lượt tìm đường của bước này → thử lại ngay bước sau
		w["state"] = St.IDLE
		w["timer"] = 0.05
		w["dest"] = dest
		return
	_path_budget -= 1
	var path: PackedVector2Array = find_path(w["pos"], dest)
	w["dest"] = dest
	w["detour"] = false
	if path.size() < 2 and (w["pos"] as Vector2).distance_to(dest) < 12.0:
		_arrive(w) # đã ở đó (vd. đang đứng trước nhà lúc trời tối)
		return
	if path.size() < 2:
		w["state"] = St.IDLE
		w["timer"] = rng.randf_range(2.0, 5.0)
		w["path"] = PackedVector2Array()
		return
	w["path"] = path
	w["pi"] = 1
	w["state"] = St.WALK
	w["wait"] = 0.0


func _arrive(w: Dictionary) -> void:
	w["path"] = PackedVector2Array()
	w["moving"] = false
	if bool(w.get("going_home", false)) and (w["pos"] as Vector2).distance_to(w["home_cell"]) < 10.0:
		w["state"] = St.INSIDE
		(w["holder"] as Node2D).visible = false
		return
	w["state"] = St.IDLE
	w["timer"] = rng.randf_range(4.0, 14.0)


func _update_walker(w: Dictionary, delta: float, player_pos: Vector2) -> void:
	w["chat_cd"] = maxf(float(w["chat_cd"]) - delta, 0.0)
	match int(w["state"]):
		St.PENDING, St.INSIDE:
			return
		St.IDLE:
			w["moving"] = false
			w["timer"] = float(w["timer"]) - delta
			if float(w["timer"]) <= 0.0:
				if _night and bool(w["night_home"]):
					w["going_home"] = true
					_go(w, w["home_cell"])
				else:
					_go(w, _pick_destination(w))
		St.CHAT:
			w["moving"] = false
			w["timer"] = float(w["timer"]) - delta
			if float(w["timer"]) <= 0.0:
				w["partner"] = -1
				if bool(w.get("resume", false)):
					w["resume"] = false
					_go(w, w["dest"])
				else:
					w["state"] = St.IDLE
					w["timer"] = rng.randf_range(0.3, 1.2)
		St.CURB:
			w["moving"] = false
			w["wait"] = float(w["wait"]) + delta
			var next: Vector2 = (w["path"] as PackedVector2Array)[int(w["pi"])]
			if float(w["wait"]) > LANE_WAIT_MAX or not _lane_busy_ahead(w, next):
				w["state"] = St.WALK
				w["wait"] = 0.0
				w["crossing"] = true
		St.WALK:
			_walk_step(w, delta, player_pos)
	_animate(w, delta)


func _lane_busy_ahead(w: Dictionary, next: Vector2) -> bool:
	var traffic: Node = world.get("traffic")
	if traffic == null:
		return false
	var p: Vector2 = w["pos"]
	var dir: Vector2 = (next - p).normalized()
	var probe := Rect2(next + dir * 8.0 - Vector2(8, 8), Vector2(16, 16)).expand(p)
	return bool(traffic.call("lane_busy", probe, 2.2))


func _walk_step(w: Dictionary, delta: float, player_pos: Vector2) -> void:
	var path: PackedVector2Array = w["path"]
	var pi: int = int(w["pi"])
	if pi >= path.size():
		if bool(w["detour"]):
			_go(w, w["dest"])
		else:
			_arrive(w)
		return
	var pos: Vector2 = w["pos"]
	var target: Vector2 = path[pi]
	# Sắp bước xuống làn xe: chờ ở lề nếu xe sắp tới.
	if not bool(w.get("crossing", false)) and is_lane(target) and not is_lane(pos) and _lane_busy_ahead(w, target):
		w["state"] = St.CURB
		w["wait"] = 0.0
		w["moving"] = false
		return
	if not is_lane(pos):
		w["crossing"] = false
	var step_len: float = float(w["speed"]) * delta
	var new_pos: Vector2 = pos.move_toward(target, step_len)
	# Né người chơi.
	if new_pos.distance_to(player_pos) < AVOID_R + 3.0 and new_pos.distance_to(player_pos) <= pos.distance_to(player_pos):
		w["wait"] = float(w["wait"]) + delta
		w["moving"] = false
		if float(w["wait"]) > 1.2:
			_detour(w, player_pos)
		return
	w["wait"] = 0.0
	var dir: Vector2 = target - pos
	if absf(dir.x) > 0.2:
		w["face"] = signf(dir.x)
	w["pos"] = new_pos
	w["moving"] = true
	(w["holder"] as Node2D).position = new_pos.round()
	if new_pos.distance_to(target) < 0.3:
		w["pi"] = pi + 1


## Bước tránh sang bên (vuông góc hướng đi, phía xa người chơi/xe) rồi tìm đường lại.
func _detour(w: Dictionary, away_from: Vector2) -> void:
	var pos: Vector2 = w["pos"]
	var path: PackedVector2Array = w["path"]
	var fwd: Vector2 = Vector2.RIGHT
	if int(w["pi"]) < path.size():
		fwd = (path[int(w["pi"])] - pos).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	if side.dot(pos - away_from) < 0.0:
		side = -side
	for k in [2, 3, -2, -3]:
		var p: Vector2 = pos + side * float(k * CELL)
		var snapped: Variant = nearest_walkable(p, 1)
		if snapped != null and (snapped as Vector2).distance_to(away_from) > AVOID_R + 4.0 and not is_lane(snapped):
			w["path"] = PackedVector2Array([pos, snapped])
			w["pi"] = 1
			w["detour"] = true
			w["wait"] = 0.0
			return
	w["wait"] = 0.0
	_go(w, w["dest"])


## Traffic báo: xe bóp kèn vì người này đứng trên làn → né sang lề.
func honked_at(index: int, vehicle_pos: Vector2) -> void:
	if index < 0 or index >= walkers.size():
		return
	var w: Dictionary = walkers[index]
	if int(w["state"]) == St.CHAT:
		var partner: int = int(w["partner"])
		if partner >= 0:
			walkers[partner]["state"] = St.IDLE
			walkers[partner]["timer"] = 0.5
		w["state"] = St.WALK
	if int(w["state"]) == St.IDLE or int(w["state"]) == St.CURB:
		w["state"] = St.WALK
		w["path"] = PackedVector2Array([w["pos"]])
		w["pi"] = 1
	var pos: Vector2 = w["pos"]
	for r in range(1, 5):
		for sgn in [1.0, -1.0]:
			var p: Vector2 = pos + Vector2(0, sgn * float(r * CELL))
			if (p - vehicle_pos).y * sgn < 0.0 and r < 3:
				continue
			if walkable(p) and not is_lane(p):
				w["path"] = PackedVector2Array([pos, nearest_walkable(p, 0)])
				w["pi"] = 1
				w["detour"] = true
				w["state"] = St.WALK
				return


func _update_far(w: Dictionary, dt: float) -> void:
	match int(w["state"]):
		St.IDLE, St.CHAT, St.CURB:
			w["timer"] = float(w["timer"]) - dt
			if int(w["state"]) != St.IDLE or float(w["timer"]) <= 0.0:
				if int(w["state"]) == St.CURB:
					w["state"] = St.WALK
				elif _night and bool(w["night_home"]):
					w["going_home"] = true
					_go(w, w["home_cell"])
				else:
					w["partner"] = -1
					_go(w, _pick_destination(w))
		St.WALK:
			var path: PackedVector2Array = w["path"]
			var left: float = float(w["speed"]) * dt
			var pos: Vector2 = w["pos"]
			while left > 0.0 and int(w["pi"]) < path.size():
				var target: Vector2 = path[int(w["pi"])]
				var d: float = pos.distance_to(target)
				if d <= left:
					pos = target
					left -= d
					w["pi"] = int(w["pi"]) + 1
				else:
					pos = pos.move_toward(target, left)
					left = 0.0
			w["pos"] = pos
			(w["holder"] as Node2D).position = pos.round()
			if int(w["pi"]) >= path.size():
				if bool(w["detour"]):
					_go(w, w["dest"])
				else:
					_arrive(w)


func _try_chats() -> void:
	var cands: Array[Dictionary] = []
	for w in walkers:
		if bool(w["near"]) and int(w["state"]) == St.WALK and float(w["chat_cd"]) <= 0.0 and not is_lane(w["pos"]) \
				and not bool(w.get("going_home", false)):
			cands.append(w)
	for i in range(cands.size()):
		var a: Dictionary = cands[i]
		if int(a["state"]) != St.WALK:
			continue
		for j in range(i + 1, cands.size()):
			var b: Dictionary = cands[j]
			if int(b["state"]) != St.WALK:
				continue
			if (a["pos"] as Vector2).distance_to(b["pos"]) > CHAT_R:
				continue
			if rng.randf() > 0.5:
				a["chat_cd"] = 8.0
				b["chat_cd"] = 8.0
				continue
			start_chat(a, b)
			break


## Hai người dừng lại nói chuyện, quay mặt vào nhau.
func start_chat(a: Dictionary, b: Dictionary) -> void:
	var t: float = rng.randf_range(3.0, 6.0)
	chats_started += 1
	for pair in [[a, b], [b, a]]:
		var me: Dictionary = pair[0]
		var other: Dictionary = pair[1]
		me["state"] = St.CHAT
		me["timer"] = t
		me["partner"] = int(other["index"])
		me["chat_cd"] = CHAT_COOLDOWN
		me["moving"] = false
		var dx: float = (other["pos"] as Vector2).x - (me["pos"] as Vector2).x
		me["face"] = 1.0 if dx >= 0.0 else -1.0
		# nói xong thì tìm đường lại tới chỗ đang đi
		me["resume"] = int(me["pi"]) < (me["path"] as PackedVector2Array).size()


func _animate(w: Dictionary, delta: float) -> void:
	var holder: Node2D = w["holder"]
	var wset: Dictionary = w["walk_set"]
	var face: float = float(w["face"])
	if bool(w["moving"]):
		w["anim"] = float(w["anim"]) + delta
		var t: float = float(w["anim"])
		if not wset.is_empty():
			var cycle: Array = wset["east"] if face > 0.0 else wset["west"]
			_set_frame(w, int(cycle[int(t / 0.14) % cycle.size()]), 0.0)
			holder.skew = 0.0
		else:
			var step: int = int(t / 0.2) % 2
			_set_frame(w, step, -1.0 if step == 1 else 0.0)
			(w["sprite"] as Sprite2D).flip_h = face < 0.0
			holder.skew = 0.06 * face
	else:
		holder.skew = 0.0
		w["anim"] = float(w["anim"]) + delta
		if not wset.is_empty():
			if int(w["state"]) == St.CHAT:
				var cycle: Array = wset["east"] if face > 0.0 else wset["west"]
				_set_frame(w, int(cycle[0]), 0.0)
			else:
				_set_frame(w, int(wset["idle"]), 0.0)
		else:
			# đứng nhún hai khung như tranh
			_set_frame(w, 1 if fmod(float(w["anim"]), 1.6) > 0.8 else 0, 0.0)
			(w["sprite"] as Sprite2D).flip_h = int(w["state"]) == St.CHAT and face < 0.0


func _set_frame(w: Dictionary, index: int, bob: float) -> void:
	var key: int = index * 4 + int(-bob)
	if int(w.get("frame_key", -1)) == key:
		return
	w["frame_key"] = key
	var regions: Array = w["regions"]
	var r: Array = regions[clampi(index, 0, regions.size() - 1)]
	var sprite: Sprite2D = w["sprite"]
	sprite.region_rect = Rect2(r[0], r[1], r[2], r[3])
	sprite.position = Vector2(roundf(float(w["anchor_dx"]) - float(r[2]) * 0.5), float(w["anchor_bottom"]) - float(r[3]) + bob)


# =================================================================== truy vấn

## Người đi bộ gần camera cho xe nhường: [[Rect2 chân, chỉ số]].
func obstacle_rects() -> Array:
	var out: Array = []
	for w in walkers:
		if bool(w["near"]) and int(w["state"]) != St.INSIDE and int(w["state"]) != St.PENDING:
			var p: Vector2 = w["pos"]
			out.append([Rect2(p.x - 5.0, p.y - 5.0, 10.0, 6.0), int(w["index"])])
	return out


func visible_count() -> int:
	var n: int = 0
	for w in walkers:
		if (w["holder"] as Node2D).visible:
			n += 1
	return n


func outside_count() -> int:
	var n: int = 0
	for w in walkers:
		if int(w["state"]) != St.INSIDE:
			n += 1
	return n
