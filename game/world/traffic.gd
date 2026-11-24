extends Node2D

## Giao thông lúc chơi: xe máy và vỏ lãi NPC chạy theo dữ liệu game/art/world_map/traffic.json (đã tách khỏi tranh bản
## đồ). World sở hữu node này (con của World → dừng theo World khi đua xe / đá gà / ở nhà).
##
## Dựng: mỗi "spawns" của chủ dự án là một xe (cùng kiểu xe, cùng đường, cùng vị trí ban đầu phase_px) → bản đồ nhìn
## giống tranh. Đường: "points" trong traffic.json đã nằm đúng làn (lane_offset chỉ ghi lại độ lệch khỏi tim đường, không
## cộng thêm). Nối tiếp "next" (đường làng cũ → đường T1/T2). Ra mép bản đồ thì biến mất, chờ một khoảng ngẫu nhiên rồi
## xuất hiện lại ở đầu chuỗi đường của nó (đi ngược "prev" tới đầu nằm ở mép bản đồ).
## Khoảng trống sông (xem _add_river_links):
## - Sông chính: tranh chỉ có vỏ lãi đoạn x 3622–5120 (khuất dưới cầu bê tông). Thêm đường "river_market_west/east"
##   (tim sông tính bằng A* trên water.png, cách bờ ≥ 16 px, né ghe chợ nổi) từ cầu bê tông về tây qua chợ nổi tới
##   x≈1836 (trước khúc hẹp ở bến đò nam), quay đầu ở đó rồi chạy ngược ra mép đông. Thêm 2 vỏ lãi cho đoạn này để mật độ
##   tương đương tranh.
## - Sông làng: vỏ lãi tới trước cầu gỗ (x≈1382, cầu thấp) thì quay đầu chạy về tây (như tranh).
## - Sông phía nam: vỏ lãi NPC chui dưới cầu khỉ x≈2986 như tranh (thuyền người chơi giờ cũng qua được mọi cầu).
##
## Luật chạy (đơn vị px, giây):
## - Tốc độ hành trình = speed_px_s của spawn × hệ số tay lái ngẫu nhiên 0,9–1,1 (4 tay lái đua 0,88–0,98 để xe Dream
##   210 px/s vượt được); tăng tốc xe 110 / thuyền 55 px/s²,
##   phanh xe 360 / thuyền 150 px/s².
## - Giữ khoảng cách: điểm-đến-điểm ≥ (mũi xe sau + đuôi xe trước + 14) + 0,35 s × tốc độ; không bao giờ chồng lên nhau
##   (kẹp vị trí sau mỗi bước).
## - Chậm lại trên cầu (× 0,72) và ở khúc cua (× 0,55–1 theo độ gắt trong ±24 px).
## - Nhường người chơi (đi bộ, chạy xe, lái vỏ lãi), người đi bộ, đò ngang đang chạy: vùng phía trước = từ tâm xe tới mũi
##   + (40 + 0,65 s × tốc độ), rộng ±10 px (xe) / ±22 px (thuyền) quanh làn; dừng cách vật cản 16 px. Chờ > 1,2 s thì bóp
##   kèn (mỗi xe nghỉ 5 s), báo người đi bộ né sang lề; thuyền chờ > 1,6 s thì lách sang bên còn nước (±34 px).
## - Chỉ mô phỏng đủ (nhường, hoạt ảnh, âm thanh) trong vùng camera nới rộng 0,5 khung mỗi phía; xe ở xa chỉ chạy đều theo
##   đường (vẫn giữ khoảng cách), ẩn node.
## - Tiếng máy: AudioStreamPlayer2D dùng lại (4 xe máy "npc_bike" + 3 vỏ lãi "boat"), gắn vào các xe gần người chơi nhất.
## - Người chơi đi bộ không bước vào thân xe máy (World.is_blocked xét khung thân xe quanh chân người chơi), nhưng thân xe
##   đang chồng lên chân người chơi thì không tính → xe dừng trên làn không bao giờ nhốt người chơi.

const VehicleActor := preload("res://game/world/vehicle_actor.gd")
const Audio := preload("res://game/audio/audio_director.gd")

## Xe máy đủ kiểu (game/art/vehicles/vehicles.json, vẽ bằng tools/art/build_vehicles.py) + 4 dáng gốc của chủ dự án:
## mỗi lần một xe máy NPC xuất hiện (lúc dựng và mỗi lần quay lại từ mép bản đồ) nó bốc một dáng theo trọng số
## LOOK_WEIGHTS (theo "model"; dáng gốc theo id), tốc độ theo "speed_range" của dáng (xe đạp chậm, cruiser nhanh).
## 4 xe "race_rider" của tranh giữ nguyên dáng; NAMED_RIDERS gắn tay đua có tên mới vào xe đầu tiên của một số đường
## (dáng cố định). Xe đạp / ba gác chạy sát lề (làn chậm riêng, xe khác không phải bám sau).
const LOOK_WEIGHTS: Dictionary = {
	"bike_01": 2.0, "bike_02": 2.0, "bike_03": 2.0, "bike_04": 2.0,
	"dream": 3.0, "scooter": 2.5, "cruiser": 1.5, "cub": 2.0, "family": 1.6, "chicken": 1.5, "ba_gac": 1.2, "bicycle": 1.4,
}
## Dáng gốc của bản đồ là tay chơi xe côn (thách đua được); dáng mới theo cờ "racer" trong vehicles.json.
const RACER_ORIGINAL: Array[String] = ["bike_01", "bike_04"]
## Tay đua có tên gắn với xe đầu tiên (theo thứ tự spawn) của đường: đường → [khoá race_riders.gd, dáng xe].
const NAMED_RIDERS: Dictionary = {
	"road_T1_east": ["R_ba_phuot", "bike_11"],
	"road_T2_west": ["R_ut_vespa", "bike_08"],
	"road_T3_east": ["R_sau_dream", "bike_05"],
	"road_T1_west": ["R_nam_cub", "bike_14"],
	"road_T3_west": ["R_tu_ba_gac", "bike_21"],
	"road_T2_east": ["R_ut_ga", "bike_19"],
}
## Tay đua chạy đường chậm hơn xe Dream của người chơi (210 px/s) để vượt được.
const RACER_SPEED_CAP: float = 188.0
## Làn chậm sát lề (px, sang phải theo chiều chạy).
const EDGE_LAT: float = 7.0
const EDGE_TYPES: Array[String] = ["bicycle", "ba_gac"]

const BIKE_ACCEL: float = 110.0
const BIKE_BRAKE: float = 360.0
const BOAT_ACCEL: float = 55.0
const BOAT_BRAKE: float = 150.0
const GAP_MARGIN: float = 14.0
const HEADWAY: float = 0.35
const YIELD_MARGIN: float = 16.0
const LOOK_BASE: float = 40.0
const LOOK_TIME: float = 0.65
const BIKE_BAND: float = 10.0
const BOAT_BAND: float = 22.0
const HORN_AFTER: float = 1.2
const HORN_COOLDOWN: float = 5.0
const SWERVE_AFTER: float = 1.6
const SWERVE_PX: float = 34.0
const SWERVE_RATE: float = 22.0
const BRIDGE_SLOW: float = 0.72
const CURVE_SLOW_MIN: float = 0.55
const CAP_STEP: float = 8.0
const RESPAWN_MIN: float = 2.0
const RESPAWN_MAX: float = 7.0
## Vùng mô phỏng đủ = khung camera nới mỗi phía thêm NEAR_GROW × cỡ khung.
const NEAR_GROW: float = 0.5
const BIKE_EMITTERS: int = 4
const BOAT_EMITTERS: int = 3
## Thân xe máy chặn chân người chơi (tính từ điểm bánh chạm đất).
const BIKE_BODY: Rect2 = Rect2(-30, -4, 60, 6)

## Tim sông chính từ cầu bê tông (x 3618) về tây qua chợ nổi tới x≈1836 (A* trên water.png, cách bờ ≥ 16 px, đơn giản
## hoá + làm mượt; tính lúc làm bằng Python từ water.png – xem báo cáo). Thứ tự = chạy về tây.
const MARKET_CENTER: PackedVector2Array = [
	Vector2(3618.0, 430.0), Vector2(3388.5, 435.5), Vector2(3373.5, 438.5), Vector2(3321.5, 442.5), Vector2(3306.8, 446.5),
	Vector2(3280.5, 449.8), Vector2(3256.0, 457.5), Vector2(3242.2, 459.2), Vector2(3214.5, 470.5), Vector2(3201.0, 474.2),
	Vector2(3185.0, 476.8), Vector2(3145.5, 478.0), Vector2(3126.5, 474.8), Vector2(3109.5, 468.2), Vector2(3094.5, 458.5),
	Vector2(3081.5, 445.5), Vector2(3056.5, 435.8), Vector2(3019.5, 429.2), Vector2(2970.5, 426.0), Vector2(2832.5, 426.8),
	Vector2(2804.5, 429.8), Vector2(2770.2, 430.5), Vector2(2736.2, 436.5), Vector2(2638.2, 439.5), Vector2(2618.0, 443.0),
	Vector2(2588.5, 445.5), Vector2(2541.0, 446.0), Vector2(2519.5, 444.8), Vector2(2502.5, 442.2), Vector2(2490.0, 438.5),
	Vector2(2466.8, 426.5), Vector2(2445.2, 420.8), Vector2(2430.0, 410.0), Vector2(2408.2, 390.5), Vector2(2397.5, 385.0),
	Vector2(2368.8, 382.5), Vector2(2315.0, 382.0), Vector2(2289.2, 385.2), Vector2(2267.8, 391.8), Vector2(2250.5, 401.5),
	Vector2(2237.5, 414.5), Vector2(2220.8, 424.2), Vector2(2200.2, 430.8), Vector2(2176.0, 434.0), Vector2(2109.2, 436.2),
	Vector2(2079.8, 445.2), Vector2(2047.8, 446.8), Vector2(2040.0, 449.5), Vector2(2003.5, 454.5), Vector2(1929.0, 481.5),
	Vector2(1893.2, 485.2), Vector2(1836.5, 486.0),
]
const MARKET_LANE: float = 12.0
## Vỏ lãi thêm cho đoạn sông chính mới (tranh không có) – giữ mật độ gần như đoạn sông đông.
const EXTRA_SPAWNS: Array[Dictionary] = [
	{"route": "river_market_west", "vehicle": "boat_03", "phase_px": 950.0, "speed_px_s": 214.0},
	{"route": "river_market_east", "vehicle": "boat_04", "phase_px": 420.0, "speed_px_s": 214.0},
]


class Route:
	var id: String
	var kind: String
	var pts: PackedVector2Array
	var cum: PackedFloat32Array
	var length: float = 0.0
	var next: String = ""
	var prev: String = ""
	var edge_start: bool = false
	var edge_end: bool = false
	var caps: PackedFloat32Array

	func pos_at(s: float) -> Vector2:
		if s <= 0.0:
			return pts[0]
		if s >= length:
			return pts[pts.size() - 1]
		var lo: int = 0
		var hi: int = cum.size() - 1
		while hi - lo > 1:
			var mid: int = (lo + hi) >> 1
			if cum[mid] <= s:
				lo = mid
			else:
				hi = mid
		var seg: float = cum[hi] - cum[lo]
		return pts[lo].lerp(pts[hi], (s - cum[lo]) / seg if seg > 0.0 else 0.0)

	func cap_at(s: float) -> float:
		return caps[clampi(int(s / 8.0), 0, caps.size() - 1)]


class Veh:
	var index: int = 0
	var look: Dictionary
	var kind: String = "bike"
	var route: String = ""
	var origin: String = ""
	var s: float = 0.0
	var v: float = 0.0
	var base: float = 160.0
	var active: bool = true
	var near: bool = false
	var respawn_t: float = 0.0
	var wait_t: float = 0.0
	var clear_t: float = 0.0
	var horn_cd: float = 0.0
	var rider: String = ""
	var actor: Node2D
	var dir: String = "east"
	var pos: Vector2
	var lat: float = 0.0
	var lat_target: float = 0.0
	var anim_ms: float = 0.0
	var front: float = 36.0
	var back: float = 36.0
	var yielding_to: String = ""
	var shown: bool = false
	var lead: Veh = null
	## Dáng cố định (tay đua có tên / xe đua của tranh) – không đổi khi xuất hiện lại.
	var fixed_look: bool = false
	## Khoá tay đua (race_riders.gd) nếu xe này thách đua được: tên node cũ, "R_…" có tên, "generic:<dáng>:<số>"; "" = không.
	var racer_key: String = ""
	## Xe đạp/ba gác: làn chậm sát lề (danh sách bám xe riêng).
	var edge: bool = false
	var lat_home: float = 0.0
	var silent: bool = false
	var spawn_speed: float = 160.0


var world: Node
var data: Dictionary = {}
var routes: Dictionary = {} # id → Route
var vehicles: Array = [] # Array[Veh]
var rng := RandomNumberGenerator.new()
## Thống kê/test: số xe mô phỏng đủ ở bước gần nhất, số lần bóp kèn.
var near_count: int = 0
var horn_count: int = 0
var last_step_usec: int = 0
## Thân xe máy gần chân người chơi (World.is_blocked đọc) – cập nhật mỗi bước.
var player_blockers: Array[Rect2] = []

var _atlas: Texture2D
var _looks: Dictionary = {}
## Bốc dáng xe: [id, trọng số cộng dồn].
var _pool: Array = []
var _pool_total: float = 0.0
## Thống kê/test: số lần mỗi dáng được bốc.
var look_counts: Dictionary = {}
## true khi vỏ lãi của người chơi đang nằm dưới một mặt cầu (World đọc: thành tích + cúi đầu).
var boat_under_bridge: bool = false
var _named_used: Dictionary = {}
var _bridges: Array = [] # [Rect2, passes_player_boat]
var _overlays: Array = [] # [Rect2, Node2D]
var _emitters: Array = [] # [AudioStreamPlayer2D, kind, Veh|null]
var _tick: int = 0
var _paused: bool = false
var _by_route: Dictionary = {}


func _ready() -> void:
	rng.seed = 20261123
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	build()


func build() -> void:
	data = MapView.traffic_data()
	if data.is_empty():
		push_warning("Traffic: thiếu traffic.json")
		return
	_atlas = load(MapView.TRAFFIC_ATLAS)
	for look in data["vehicles"]:
		_looks[String(look["id"])] = look
	_build_pool()
	for b in data.get("bridges", []):
		var r: Array = b["rect"]
		_bridges.append([Rect2(r[0], r[1], r[2], r[3]), bool(b["player_boat_passes"])])
	for r in data["routes"]:
		var pts := PackedVector2Array()
		for p in r["points"]:
			pts.append(Vector2(p[0], p[1]))
		var ends: Array = r.get("ends", [])
		var edge_start: bool = ends.size() > 0 and ends[0].get("map_edge") != null
		var edge_end: bool = ends.size() > 1 and ends[1].get("map_edge") != null
		_add_route(String(r["id"]), String(r["kind"]), pts, edge_start, edge_end,
			String(r["next"]) if r.get("next") != null else "")
	_add_river_links()
	for id in routes:
		var route: Route = routes[id]
		if route.next != "" and routes.has(route.next):
			(routes[route.next] as Route).prev = id
	var spawns: Array = []
	spawns.append_array(data["spawns"])
	spawns.append_array(EXTRA_SPAWNS)
	for spawn in spawns:
		_spawn(spawn)
	_resolve_overlaps()
	_build_emitters()
	_build_bridge_overlays()


func _add_route(id: String, kind: String, pts: PackedVector2Array, edge_start: bool, edge_end: bool, next: String) -> Route:
	var route := Route.new()
	route.id = id
	route.kind = kind
	route.pts = pts
	route.next = next
	route.edge_start = edge_start
	route.edge_end = edge_end
	route.cum = PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		route.cum.append(route.cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	route.length = route.cum[route.cum.size() - 1]
	# Giới hạn tốc độ mỗi 8 px: cầu và khúc cua.
	var n: int = int(route.length / CAP_STEP) + 1
	route.caps.resize(n)
	for i in range(n):
		var s: float = float(i) * CAP_STEP
		var p: Vector2 = route.pos_at(s)
		var a: Vector2 = route.pos_at(s - 24.0)
		var b: Vector2 = route.pos_at(s + 24.0)
		var cap: float = 1.0
		if a.distance_to(p) > 4.0 and p.distance_to(b) > 4.0:
			var turn: float = absf((p - a).angle_to(b - p))
			cap = clampf(1.0 - turn * 0.9, CURVE_SLOW_MIN, 1.0)
		for bridge in _bridges:
			if (bridge[0] as Rect2).grow(6.0).has_point(p):
				cap = minf(cap, BRIDGE_SLOW)
		route.caps[i] = cap
	routes[id] = route
	return route


## Nối các khúc sông bị đứt trong tranh (xem chú thích đầu file).
func _add_river_links() -> void:
	if not routes.has("river_main_west") or not routes.has("river_main_east"):
		return
	var west_pts: PackedVector2Array = _offset_line(MARKET_CENTER, MARKET_LANE)
	west_pts[0] = (routes["river_main_west"] as Route).pts[(routes["river_main_west"] as Route).pts.size() - 1]
	var center_east := PackedVector2Array(MARKET_CENTER)
	center_east.reverse()
	var east_pts: PackedVector2Array = _offset_line(center_east, MARKET_LANE)
	east_pts.append((routes["river_main_east"] as Route).pts[0])
	_add_route("river_market_west", "boat", west_pts, false, false, "uturn_market")
	_add_route("river_market_east", "boat", east_pts, false, false, "river_main_east")
	_add_route("uturn_market", "boat", _uturn(west_pts, east_pts), false, false, "river_market_east")
	(routes["river_main_west"] as Route).next = "river_market_west"
	if routes.has("river_village_east") and routes.has("river_village_west"):
		var a: Route = routes["river_village_east"]
		var b: Route = routes["river_village_west"]
		_add_route("uturn_village", "boat", _uturn(a.pts, b.pts), false, false, "river_village_west")
		a.next = "uturn_village"


## Đường song song lệch d px sang phải (theo chiều chạy; trục y hướng xuống → phải = (−dy, dx)).
static func _offset_line(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size()):
		var t: Vector2 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		out.append(pts[i] + Vector2(-t.y, t.x) * d)
	return out


## Đường quay đầu ngắn từ cuối a sang đầu b (vòng ra phía trước 20 px rồi về làn ngược lại).
static func _uturn(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var end: Vector2 = a[a.size() - 1]
	var start: Vector2 = b[0]
	var fwd: Vector2 = (end - a[a.size() - 2]).normalized()
	var mid: Vector2 = (end + start) * 0.5 + fwd * 20.0
	return PackedVector2Array([end, end.lerp(mid, 0.6) + fwd * 4.0, mid, start.lerp(mid, 0.6) + fwd * 4.0, start])


func _origin_of(route_id: String) -> String:
	var id: String = route_id
	for i in range(8):
		var route: Route = routes[id]
		if route.edge_start or route.prev == "":
			return id
		id = route.prev
	return route_id


func _spawn(spawn: Dictionary) -> void:
	var route_id: String = String(spawn["route"])
	var look_id: String = String(spawn["vehicle"])
	if not routes.has(route_id) or not _looks.has(look_id):
		return
	var v := Veh.new()
	v.index = vehicles.size()
	v.look = _looks[look_id]
	v.kind = String(v.look["kind"])
	v.route = route_id
	v.origin = _origin_of(route_id)
	v.s = clampf(float(spawn.get("phase_px", 0.0)), 0.0, (routes[route_id] as Route).length - 1.0)
	v.rider = String(spawn.get("race_rider", ""))
	v.spawn_speed = float(spawn.get("speed_px_s", v.look["speed_px_s"]))
	if v.kind == "bike":
		if v.rider != "":
			v.fixed_look = true
			v.racer_key = v.rider
		elif NAMED_RIDERS.has(route_id) and not _named_used.has(route_id) and _looks.has(String(NAMED_RIDERS[route_id][1])):
			_named_used[route_id] = true
			v.fixed_look = true
			v.racer_key = String(NAMED_RIDERS[route_id][0])
			v.look = _looks[String(NAMED_RIDERS[route_id][1])]
		else:
			v.look = _looks[_pick_look()]
	v.anim_ms = rng.randf() * 1000.0
	var actor: Node2D = VehicleActor.new()
	actor.name = "Vehicle_%02d_%s" % [v.index, look_id]
	actor.call("setup", v.look, MapView.atlas_for_look(v.look))
	v.actor = actor
	_apply_look(v)
	v.v = v.base
	_update_dir(v)
	v.pos = _point(v)
	vehicles.append(v)
	if world != null and world.get("map_view") != null:
		world.map_view.add_actor(actor)
		world.map_view.add_ground(actor.get("ground"))
	else:
		add_child(actor)
		add_child(actor.get("ground"))
	actor.call("set_shown", false)


## Bảng bốc dáng xe máy theo LOOK_WEIGHTS (trọng số của "model" chia đều cho các biến thể).
func _build_pool() -> void:
	_pool.clear()
	_pool_total = 0.0
	var per_model: Dictionary = {}
	for id in _looks:
		var look: Dictionary = _looks[id]
		if String(look.get("kind", "")) != "bike":
			continue
		var key: String = String(look["model"]) if look.get("model") != null else String(id)
		if not LOOK_WEIGHTS.has(key):
			continue
		if not per_model.has(key):
			per_model[key] = []
		(per_model[key] as Array).append(String(id))
	var keys: Array = per_model.keys()
	keys.sort()
	for key in keys:
		var ids: Array = per_model[key]
		ids.sort()
		for id in ids:
			_pool_total += float(LOOK_WEIGHTS[key]) / float(ids.size())
			_pool.append([id, _pool_total])


func _pick_look() -> String:
	if _pool.is_empty():
		return "bike_01"
	var r: float = rng.randf() * _pool_total
	for entry in _pool:
		if r <= float(entry[1]):
			return String(entry[0])
	return String(_pool[_pool.size() - 1][0])


## Áp dáng hiện tại của xe: tốc độ, mũi/đuôi, làn, tay đua, tiếng máy.
func _apply_look(v: Veh) -> void:
	var look: Dictionary = v.look
	var lid: String = String(look["id"])
	look_counts[lid] = int(look_counts.get(lid, 0)) + 1
	var size_x: float = float(look["size"][0])
	var anchor_x: float = float(look["anchor"][0])
	# Mũi/đuôi theo hướng đông (đi về tây thì đối xứng qua anchor_west).
	v.front = size_x - anchor_x
	v.back = anchor_x
	if v.kind == "boat":
		v.front = maxf(v.front, 70.0)
	var vtype: String = String(look["type"]) if look.get("type") != null else ""
	v.silent = bool(look.get("silent", false))
	v.edge = v.kind == "bike" and EDGE_TYPES.has(vtype)
	v.lat_home = EDGE_LAT if v.edge else 0.0
	v.lat = v.lat_home
	v.lat_target = v.lat_home
	if v.kind == "bike" and not v.fixed_look:
		var racer: bool = bool(look["racer"]) if look.has("racer") else RACER_ORIGINAL.has(lid)
		v.racer_key = "generic:%s:%d" % [lid, v.index] if racer else ""
	# Tốc độ: dáng mới theo speed_range; dáng gốc theo tranh × 0,9–1,1. Tay đua chậm hơn xe người chơi một chút.
	var range_value: Variant = look.get("speed_range")
	if v.kind == "bike" and range_value != null:
		v.base = rng.randf_range(float(range_value[0]), float(range_value[1]))
	elif v.rider != "":
		v.base = v.spawn_speed * rng.randf_range(0.88, 0.98)
	else:
		v.base = v.spawn_speed * rng.randf_range(0.9, 1.1)
	if v.racer_key != "":
		v.base = minf(v.base, RACER_SPEED_CAP * rng.randf_range(0.92, 1.0))


## Bốc dáng mới cho xe máy (không đổi xe có dáng cố định).
func _reroll_look(v: Veh) -> void:
	if v.kind != "bike" or v.fixed_look:
		return
	v.look = _looks[_pick_look()]
	v.actor.call("set_look", v.look, MapView.atlas_for_look(v.look))
	_apply_look(v)


## Khoá danh sách bám xe: xe làn chậm sát lề có danh sách riêng (xe làn chính không phải bám sau xe đạp).
static func _list_key(route_id: String, edge: bool) -> String:
	return route_id + "|e" if edge else route_id


# =================================================================== mô phỏng

func _physics_process(delta: float) -> void:
	step(delta)


## Một bước mô phỏng 60 Hz (test gọi trực tiếp).
func step(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_tick += 1
	var near_rect: Rect2 = _near_rect()
	var obstacles: Array = _collect_obstacles()
	_rebuild_lists()
	near_count = 0
	for v in vehicles:
		if not v.active:
			_update_respawn(v, delta)
			continue
		v.near = near_rect.has_point(v.pos)
		if v.near:
			near_count += 1
		_advance(v, delta, obstacles)
	_resolve_overlaps(false)
	for v in vehicles:
		if not v.active:
			continue
		# Xe ở xa (ẩn) chỉ cần toạ độ để biết lúc vào gần → cập nhật so le mỗi 4 bước.
		if v.shown or (_tick + v.index) % 4 == 0:
			v.pos = _point(v)
		v.near = near_rect.has_point(v.pos)
		if v.near:
			_update_dir(v)
			var speed01: float = clampf(v.v / maxf(v.base, 1.0), 0.0, 1.0)
			v.actor.call("show_at", v.pos, v.dir, v.anim_ms, speed01)
		if v.shown != v.near:
			v.shown = v.near
			v.actor.call("set_shown", v.near)
	_update_blockers()
	if _tick % 3 == 0:
		_update_overlays()
	if _tick % 6 == 0:
		_assign_emitters()
	_update_emitters()
	last_step_usec = Time.get_ticks_usec() - t0


func _near_rect() -> Rect2:
	var view := Rect2(-1e6, -1e6, 2e6, 2e6)
	if world != null and world.has_method("camera_view_rect") and world.get("_camera") != null:
		view = world.camera_view_rect()
		view = view.grow_individual(view.size.x * NEAR_GROW, view.size.y * NEAR_GROW, view.size.x * NEAR_GROW, view.size.y * NEAR_GROW)
	return view


## Vật cản xe phải nhường: [Rect2, loại, chỉ số]. loại: "player", "ped", "boat" (thuyền người chơi), "ferry".
func _collect_obstacles() -> Array:
	var list: Array = []
	if world == null:
		return list
	var player: Node2D = world.get("player")
	var boat: Node = world.get("player_boat")
	var boating: bool = boat != null and bool(boat.get("active"))
	if player != null and not boating and player.visible:
		var p: Vector2 = player.position
		if bool(player.get("riding")):
			list.append([Rect2(p.x - 30.0, p.y - 6.0, 60.0, 8.0), "player", -1])
		else:
			list.append([Rect2(p.x - 6.0, p.y - 6.0, 12.0, 7.0), "player", -1])
	if boating:
		list.append([boat.call("hull_rect"), "boat", -1])
	var peds: Node = world.get("pedestrians")
	if peds != null:
		for entry in peds.call("obstacle_rects"):
			list.append([entry[0], "ped", entry[1]])
	if bool(world.get("ferry_moving")) and world.get("ferry_boat") != null:
		var top: Vector2 = (world.get("ferry_boat") as Node2D).position
		list.append([Rect2(top.x - 20.0, top.y, 40.0, 62.0), "ferry", -1])
	return list


func _rebuild_lists() -> void:
	_by_route.clear()
	for v in vehicles:
		if not v.active:
			continue
		var key: String = _list_key(v.route, v.edge)
		if not _by_route.has(key):
			_by_route[key] = []
		(_by_route[key] as Array).append(v)
	for key in _by_route:
		(_by_route[key] as Array).sort_custom(func(a: Veh, b: Veh) -> bool: return a.s < b.s)
	# Xe trước của mỗi xe: phần tử kế trong danh sách đã xếp, hoặc xe cuối hàng của đường kế tiếp (≤ 2 đường).
	for key in _by_route:
		var list: Array = _by_route[key]
		var tail: Veh = null
		var edge_list: bool = String(key).ends_with("|e")
		var id: String = (routes[String(key).trim_suffix("|e")] as Route).next
		for hop in range(2):
			if id == "" or not routes.has(id):
				break
			if _by_route.has(_list_key(id, edge_list)):
				tail = (_by_route[_list_key(id, edge_list)] as Array)[0]
				break
			id = (routes[id] as Route).next
		for i in range(list.size()):
			(list[i] as Veh).lead = list[i + 1] if i + 1 < list.size() else tail


## Xe phía trước gần nhất (cùng đường hoặc 2 đường kế tiếp): [Veh|null, khoảng cách điểm-đến-điểm].
func _leader(v: Veh) -> Array:
	var list: Array = _by_route.get(_list_key(v.route, v.edge), [])
	for other in list:
		if other.s > v.s or (other.s == v.s and other.index > v.index):
			if other != v:
				return [other, other.s - v.s]
	var acc: float = (routes[v.route] as Route).length - v.s
	var id: String = (routes[v.route] as Route).next
	for hop in range(2):
		if id == "" or not routes.has(id):
			break
		var next_list: Array = _by_route.get(_list_key(id, v.edge), [])
		for other in next_list:
			if other != v:
				return [other, acc + other.s]
		acc += (routes[id] as Route).length
		id = (routes[id] as Route).next
	return [null, INF]


func _advance(v: Veh, delta: float, obstacles: Array) -> void:
	var route: Route = routes[v.route]
	var accel: float = BIKE_ACCEL if v.kind == "bike" else BOAT_ACCEL
	var brake: float = BIKE_BRAKE if v.kind == "bike" else BOAT_BRAKE
	var target: float = v.base * route.cap_at(v.s + v.front * 0.5)
	# Giữ khoảng cách với xe trước.
	if v.lead != null:
		var other: Veh = v.lead
		var need: float = v.front + other.back + GAP_MARGIN
		var free: float = _gap_to(v, other) - need
		if free <= 0.0:
			target = 0.0
		else:
			target = minf(target, maxf(other.v + (free - v.v * HEADWAY) * 2.0, 0.0))
	# Nhường vật cản phía trước (chỉ khi gần camera).
	v.yielding_to = ""
	if v.near and not obstacles.is_empty():
		var hit: Array = _obstacle_ahead(v, obstacles)
		if not hit.is_empty():
			var room: float = float(hit[0]) - YIELD_MARGIN
			target = minf(target, maxf(room, 0.0) * 2.5)
			if room <= 4.0:
				target = 0.0
			if float(hit[0]) <= 2.0:
				v.v = 0.0 # có người bước ra sát mũi xe: thắng gấp, không bao giờ cán qua
			v.yielding_to = String(hit[1])
			_on_blocked(v, hit, delta)
	if v.yielding_to == "":
		v.wait_t = 0.0
		v.clear_t += delta
		if v.clear_t > 1.5:
			v.lat_target = v.lat_home
	v.horn_cd = maxf(v.horn_cd - delta, 0.0)
	if v.v < target:
		v.v = minf(v.v + accel * delta, target)
	else:
		v.v = maxf(v.v - brake * delta, target)
	if target <= 0.0 and v.v < 6.0:
		v.v = 0.0
	if v.lat != v.lat_target:
		v.lat = move_toward(v.lat, v.lat_target, SWERVE_RATE * delta)
	v.s += v.v * delta
	v.anim_ms += delta * 1000.0 * (clampf(v.v / maxf(v.base, 1.0), 0.0, 1.0) if v.kind == "bike" else 1.0)
	while v.s >= (routes[v.route] as Route).length:
		var done: Route = routes[v.route]
		if done.next != "" and routes.has(done.next):
			v.s -= done.length
			v.route = done.next
		else:
			_despawn(v)
			return


## Vật cản gần nhất trong vùng phía trước: [khoảng cách tới mép vật cản (px), loại, chỉ số] hoặc [].
func _obstacle_ahead(v: Veh, obstacles: Array) -> Array:
	var look: float = LOOK_BASE + v.v * LOOK_TIME + v.front
	var p0: Vector2 = v.pos
	var p1: Vector2 = _point_at(v, v.s + look)
	var fwd: Vector2 = (p1 - p0).normalized()
	if fwd == Vector2.ZERO:
		return []
	var band: float = BIKE_BAND if v.kind == "bike" else BOAT_BAND
	var zone := Rect2(p0, Vector2.ZERO).expand(p1)
	var side_pad: float = band
	zone = zone.grow_individual(2.0, side_pad, 2.0, side_pad)
	var best: Array = []
	for entry in obstacles:
		var r: Rect2 = entry[0]
		var kind: String = entry[1]
		if v.kind == "bike" and (kind == "boat" or kind == "ferry"):
			continue
		if v.kind == "boat" and (kind == "ped" or kind == "player"):
			continue
		if not zone.intersects(r):
			continue
		# Khoảng cách dọc làn từ mũi xe tới mép gần của vật cản.
		var c: Vector2 = r.get_center()
		var half: float = absf(fwd.x) * r.size.x * 0.5 + absf(fwd.y) * r.size.y * 0.5
		var along: float = (c - p0).dot(fwd) - half - v.front
		if (c - p0).dot(fwd) < 0.0:
			continue
		var lateral: float = absf((c - p0).dot(Vector2(-fwd.y, fwd.x)))
		var half_side: float = absf(fwd.y) * r.size.x * 0.5 + absf(fwd.x) * r.size.y * 0.5
		if lateral - half_side > band:
			continue
		along = maxf(along, 0.0)
		if best.is_empty() or along < float(best[0]):
			best = [along, kind, entry[2]]
	return best


func _on_blocked(v: Veh, hit: Array, delta: float) -> void:
	v.clear_t = 0.0
	if v.v > 8.0:
		return
	v.wait_t += delta
	if v.wait_t > HORN_AFTER and v.horn_cd <= 0.0:
		v.horn_cd = HORN_COOLDOWN
		horn_count += 1
		_honk(v)
		if String(hit[1]) == "ped" and world != null and world.get("pedestrians") != null:
			world.pedestrians.call("honked_at", int(hit[2]), v.pos)
		elif (String(hit[1]) == "player" or String(hit[1]) == "boat") and world != null and world.has_method("notify_honked"):
			world.call("notify_honked", v.pos)
	if v.kind == "boat" and v.wait_t > SWERVE_AFTER and v.lat_target == v.lat_home:
		for side in [1.0, -1.0]:
			if _water_clear(v, side * SWERVE_PX):
				v.lat_target = side * SWERVE_PX
				break


func _water_clear(v: Veh, lat: float) -> bool:
	if world == null or not world.has_method("is_water"):
		return false
	for k in range(-2, 5):
		var s: float = v.s + float(k) * 40.0
		var p: Vector2 = _route_point(v.route, s)
		var q: Vector2 = _route_point(v.route, s + 4.0)
		var t: Vector2 = (q - p).normalized()
		var o: Vector2 = p + Vector2(-t.y, t.x) * lat
		if not world.is_water(o.x, o.y):
			return false
	return true


func _honk(v: Veh) -> void:
	if world == null or world.get("player") == null:
		return
	var d: float = v.pos.distance_to((world.player as Node2D).position)
	if d > 360.0:
		return
	Audio.sfx(&"bike_horn", -6.0 - d / 30.0, 0.72 if v.kind == "boat" else rng.randf_range(0.95, 1.08))


func _despawn(v: Veh) -> void:
	v.active = false
	v.near = false
	v.v = 0.0
	v.lat = v.lat_home
	v.lat_target = v.lat_home
	v.respawn_t = rng.randf_range(RESPAWN_MIN, RESPAWN_MAX)
	v.shown = false
	v.actor.call("set_shown", false)


func _update_respawn(v: Veh, delta: float) -> void:
	v.respawn_t -= delta
	if v.respawn_t > 0.0:
		return
	# Đầu đường phải trống (không xe nào trong khoảng an toàn).
	for other in vehicles:
		if other != v and other.active and other.route == v.origin and other.s < v.front + other.back + GAP_MARGIN + 60.0:
			v.respawn_t = 1.0
			return
	# … và không có người chơi / vỏ lãi của người chơi ở đó (xe không bao giờ hiện ra chồng lên người chơi).
	if world != null and world.get("player") != null:
		var start: Vector2 = (routes[v.origin] as Route).pos_at(0.0)
		var zone := Rect2(start, Vector2.ZERO).grow(150.0 if v.kind == "boat" else 90.0)
		var boat: Node = world.get("player_boat")
		var blocked: bool = zone.has_point((world.player as Node2D).position)
		if boat != null and bool(boat.get("moored")):
			blocked = blocked or zone.intersects(boat.call("hull_rect"))
		if blocked:
			v.respawn_t = 1.0
			return
	v.active = true
	v.route = v.origin
	v.s = 0.0
	if v.kind == "bike" and not v.fixed_look:
		_reroll_look(v) # xuất hiện lại ở mép bản đồ với dáng xe khác
	v.v = v.base * 0.9
	v.wait_t = 0.0
	_update_dir(v)
	v.pos = _point(v)


## Không bao giờ chồng: xe sau bị kẹp lùi về sau xe trước (cùng đường và đường kế tiếp).
## full: tìm lại xe trước (lúc dựng); bình thường dùng xe trước đã tìm trong bước này (danh sách xếp theo s từ đầu bước
## vẫn đúng thứ tự vì không xe nào vượt nhau) → không phải dựng lại danh sách.
func _resolve_overlaps(full: bool = true) -> void:
	if full:
		_rebuild_lists()
	for key in _by_route:
		var list: Array = _by_route[key]
		for i in range(list.size() - 1, -1, -1):
			var v: Veh = list[i]
			if not v.active:
				continue
			var other: Veh = v.lead
			var gap: float = INF
			if other != null and other.active:
				gap = _gap_to(v, other)
			if other == null or not other.active or gap == INF:
				continue
			var need: float = v.front + other.back + GAP_MARGIN
			if gap < need:
				var push: float = need - gap
				v.s -= push
				v.v = minf(v.v, other.v)
				if v.s < 0.0:
					v.s = 0.0 # vừa xuất hiện ở đầu đường – xe trước sẽ chạy xa ra


## Khoảng cách theo đường từ v tới xe o phía trước (cùng đường hoặc 1–2 đường kế tiếp), INF nếu không liên quan.
func _gap_to(v: Veh, o: Veh) -> float:
	if o.route == v.route:
		return o.s - v.s if o.s >= v.s else INF
	var route: Route = routes[v.route]
	var acc: float = route.length - v.s
	var id: String = route.next
	for hop in range(2):
		if id == "" or not routes.has(id):
			return INF
		if o.route == id:
			return acc + o.s
		acc += (routes[id] as Route).length
		id = (routes[id] as Route).next
	return INF


func _update_dir(v: Veh) -> void:
	var a: Vector2 = _route_point(v.route, v.s - 6.0)
	var b: Vector2 = _route_point(v.route, v.s + 6.0)
	var t: Vector2 = b - a
	if t.length() < 0.01:
		return
	if t.x > 0.35 * t.length():
		v.dir = "east"
	elif t.x < -0.35 * t.length():
		v.dir = "west"


## Điểm trên đường theo độ dài cung, đi tiếp sang "next" khi vượt cuối đường.
func _route_point(route_id: String, s: float) -> Vector2:
	var id: String = route_id
	var rest: float = s
	for i in range(4):
		var route: Route = routes[id]
		if rest <= route.length or route.next == "" or not routes.has(route.next):
			return route.pos_at(rest)
		rest -= route.length
		id = route.next
	return (routes[id] as Route).pos_at(rest)


func _point_at(v: Veh, s: float) -> Vector2:
	return _route_point(v.route, s)


func _point(v: Veh) -> Vector2:
	var p: Vector2 = _route_point(v.route, v.s)
	if v.lat != 0.0:
		var t: Vector2 = (_route_point(v.route, v.s + 4.0) - _route_point(v.route, v.s - 4.0)).normalized()
		p += Vector2(-t.y, t.x) * v.lat
	return p


# =================================================================== người chơi, cầu, âm thanh

func _update_blockers() -> void:
	player_blockers.clear()
	if world == null or world.get("player") == null:
		return
	var player: Node2D = world.player
	if bool(player.get("riding")):
		return
	var p: Vector2 = player.position
	for v in vehicles:
		if not v.active or not v.near or v.kind != "bike":
			continue
		if absf(v.pos.x - p.x) > 70.0 or absf(v.pos.y - p.y) > 24.0:
			continue
		var body := Rect2(v.pos + BIKE_BODY.position, BIKE_BODY.size)
		if body.grow(-1.0).has_point(p):
			continue # thân xe đang chồng lên chân người chơi → không chặn (không bao giờ nhốt người chơi)
		player_blockers.append(body)


## Mặt cầu vẽ đè lên thuyền chui dưới cầu (ảnh cắt từ ô nền tĩnh của bản đồ); chỉ hiện khi có thuyền dưới cầu.
func _build_bridge_overlays() -> void:
	if world == null or world.get("map_view") == null:
		return
	var map_view: Node2D = world.map_view
	var shared: Dictionary = MapView.load_shared()
	var atlases: Array = shared["atlases"]
	var tiles: Array = shared["manifest"]["below"]
	for bridge in _bridges:
		var rect: Rect2 = bridge[0]
		if rect.size.x * rect.size.y < 150.0:
			continue
		var holder := Node2D.new()
		holder.name = "BridgeDeck"
		holder.z_index = 1
		holder.visible = false
		holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for tile in tiles:
			if not tile.has("static"):
				continue
			var st: Array = tile["static"]
			var tile_rect := Rect2(float(tile["pos"][0]), float(tile["pos"][1]), float(st[3]), float(st[4]))
			var part: Rect2 = tile_rect.intersection(rect)
			if part.size.x <= 0.0 or part.size.y <= 0.0:
				continue
			var sprite := Sprite2D.new()
			sprite.texture = atlases[int(st[0])]
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(Vector2(float(st[1]), float(st[2])) + part.position - tile_rect.position, part.size)
			sprite.position = part.position
			holder.add_child(sprite)
		# lan can / cầu khỉ là vật thể Y-sort của bản đồ: nâng z lên trên mặt cầu khi có thuyền bên dưới
		var rails: Array[String] = []
		if map_view.has_method("object_names_in"):
			for node_name in map_view.call("object_names_in", rect.grow(2.0)):
				if String(node_name).contains("cau") and not String(node_name).begins_with("N_npc") 						and not String(node_name).begins_with("NV_") and not String(node_name).contains("nguoi"):
					rails.append(String(node_name))
		if holder.get_child_count() == 0 and rails.is_empty():
			holder.free()
			continue
		map_view.add_child(holder)
		_overlays.append([rect, holder, rails])


func _update_overlays() -> void:
	if _overlays.is_empty():
		return
	var boat: Node = world.get("player_boat")
	var boat_rect := Rect2()
	if boat != null and bool(boat.get("active")):
		boat_rect = boat.call("hull_rect")
	boat_under_bridge = false
	if boat_rect.size != Vector2.ZERO:
		for bridge in _bridges:
			if (bridge[0] as Rect2).grow(-2.0).intersects(boat_rect):
				boat_under_bridge = true
				break
	var any_shown: bool = false
	var boats: Array = []
	for v in vehicles:
		if v.active and v.near and v.kind == "boat":
			boats.append(v)
	for entry in _overlays:
		var rect: Rect2 = entry[0]
		var show: bool = boat_rect.size != Vector2.ZERO and boat_rect.intersects(rect)
		if not show:
			for v in boats:
				if absf(v.pos.x - rect.get_center().x) < rect.size.x * 0.5 + 160.0 \
						and v.pos.y > rect.position.y and v.pos.y < rect.end.y + 4.0:
					show = true
					break
		if (entry[1] as Node2D).visible != show:
			for node_name in entry[2]:
				world.map_view.call("set_node_z", node_name, 2 if show else 0)
		(entry[1] as Node2D).visible = show
		any_shown = any_shown or show
	# Người đứng trên mặt cầu vẽ trên lớp mặt cầu.
	var player: Node2D = world.player
	var on_deck: bool = false
	if any_shown and not (boat != null and bool(boat.get("active"))):
		for entry in _overlays:
			if (entry[1] as Node2D).visible and (entry[0] as Rect2).grow(4.0).has_point(player.position):
				on_deck = true
	player.z_index = 2 if on_deck else 0


func _build_emitters() -> void:
	for i in range(BIKE_EMITTERS + BOAT_EMITTERS):
		var bike: bool = i < BIKE_EMITTERS
		var emitter: AudioStreamPlayer2D = Audio.make_emitter(&"npc_bike" if bike else &"boat", 250.0 if bike else 330.0,
			-5.0 if bike else -5.0)
		emitter.stream_paused = true
		add_child(emitter)
		_emitters.append([emitter, "bike" if bike else "boat", null])


## Gắn nguồn âm vào các xe gần người chơi nhất (mỗi loại tối đa số nguồn của loại đó).
func _assign_emitters() -> void:
	if world == null or world.get("player") == null:
		return
	var listener: Vector2 = (world.player as Node2D).position
	for kind in ["bike", "boat"]:
		var max_d: float = 250.0 if kind == "bike" else 330.0
		var cands: Array = []
		for v in vehicles:
			if v.active and v.near and v.kind == kind and not v.silent and v.pos.distance_to(listener) < max_d:
				cands.append(v)
		cands.sort_custom(func(a: Veh, b: Veh) -> bool: return a.pos.distance_squared_to(listener) < b.pos.distance_squared_to(listener))
		var slots: Array = _emitters.filter(func(e: Array) -> bool: return e[1] == kind)
		# Giữ gắn cũ nếu xe vẫn trong danh sách → khỏi giật tiếng.
		var keep: Array = []
		for e in slots:
			if e[2] != null and cands.has(e[2]) and cands.find(e[2]) < slots.size():
				keep.append(e[2])
			else:
				e[2] = null
		for v in cands.slice(0, slots.size()):
			if keep.has(v):
				continue
			for e in slots:
				if e[2] == null:
					e[2] = v
					break


func _update_emitters() -> void:
	for e in _emitters:
		var emitter: AudioStreamPlayer2D = e[0]
		var v: Veh = e[2]
		if v == null or not v.active or _paused:
			if not emitter.stream_paused:
				emitter.stream_paused = true
			continue
		emitter.position = v.pos + Vector2(0, -12)
		emitter.pitch_scale = 0.8 + 0.3 * clampf(v.v / maxf(v.base, 1.0), 0.0, 1.0)
		if emitter.stream_paused:
			emitter.stream_paused = false


## World gọi khi bật/tắt (đua xe, đá gà, ở nhà): tắt tiếng máy ngay.
func set_paused(paused: bool) -> void:
	_paused = paused
	for e in _emitters:
		(e[0] as AudioStreamPlayer2D).stream_paused = true


## Số nguồn âm đang phát (test).
func active_emitters() -> int:
	var n: int = 0
	for e in _emitters:
		if e[2] != null and not (e[0] as AudioStreamPlayer2D).stream_paused:
			n += 1
	return n


# =================================================================== truy vấn

## Móc của World.race_bike_source: {tên tay lái → Rect2 khung xe hiện tại, hoặc null khi xe khuất/ở xa}.
## Gồm 4 tay lái của tranh (luôn có khoá, null khi khuất), tay đua có tên mới và mọi xe máy "racer" đang gần camera.
func race_bike_rects() -> Dictionary:
	var out: Dictionary = {}
	for v in vehicles:
		if v.racer_key == "":
			continue
		var live: bool = v.active and v.near
		if not live and v.rider == "":
			continue
		out[v.racer_key] = (v.actor.call("frame_rect") as Rect2) if live else null
	return out


## Hướng chạy ngang hiện tại (+1 đông / −1 tây) của các xe trong race_bike_rects().
func race_bike_dirs() -> Dictionary:
	var out: Dictionary = {}
	for v in vehicles:
		if v.racer_key != "" and v.active:
			out[v.racer_key] = 1 if v.dir == "east" else -1
	return out


## Xe NPC theo khoá tay đua (null nếu không có).
func find_racer(key: String) -> Veh:
	for v in vehicles:
		if v.racer_key == key:
			return v
	return null


## Đặt xe lên đường ở vị trí s ngay lập tức (test, ảnh chụp): cập nhật toạ độ, hướng, hiện/ẩn.
func place_vehicle(v: Veh, route_id: String, s: float) -> void:
	v.active = true
	v.route = route_id
	v.s = s
	v.v = v.base
	v.lat = v.lat_home
	v.lat_target = v.lat_home
	v.wait_t = 0.0
	_update_dir(v)
	v.pos = _point(v)
	_rebuild_lists()


func find_rider(rider: String) -> Veh:
	for v in vehicles:
		if v.rider == rider:
			return v
	return null


## Có xe nào sắp chạy qua vùng rect (người đi bộ chờ qua đường): xe đang ở trong, hoặc sẽ tới trong `seconds` giây.
func lane_busy(rect: Rect2, seconds: float = 2.2) -> bool:
	for v in vehicles:
		if not v.active or v.kind != "bike" or not v.near:
			continue
		var body := Rect2(v.pos + Vector2(-v.back, -8.0), Vector2(v.back + v.front, 12.0))
		if body.intersects(rect.grow(4.0)):
			return true
		var p1: Vector2 = _point_at(v, v.s + v.front + maxf(v.v, 40.0) * seconds)
		var zone := Rect2(v.pos, Vector2.ZERO).expand(p1).grow_individual(0.0, BIKE_BAND, 0.0, BIKE_BAND)
		if zone.intersects(rect):
			return true
	return false


## Thân thuyền NPC (cho thuyền người chơi tránh): danh sách Rect2 quanh mép nước.
func boat_hulls(near_point: Vector2, radius: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for v in vehicles:
		if not v.active or v.kind != "boat" or v.pos.distance_to(near_point) > radius + 200.0:
			continue
		var f: float = minf(v.front, 80.0)
		var b: float = minf(v.back, 80.0)
		var x0: float = v.pos.x - (b if v.dir == "east" else f)
		out.append(Rect2(x0, v.pos.y - 7.0, b + f, 10.0))
	return out


func route(id: String) -> Route:
	return routes.get(id)
