extends SceneTree

## Smoke test thế giới sống: giao thông (game/world/traffic.gd), vỏ lãi của người chơi (player_boat.gd), người đi bộ
## (pedestrians.gd) trên World thật (không qua main).
## - mọi spawn dựng được; xe chạy theo đường, nằm trên mặt đường / mặt nước; không chồng nhau trên cùng đường
## - dừng trước người chơi đứng giữa làn, bóp kèn, chạy tiếp khi người chơi tránh ra; thân xe chặn chân người chơi
##   nhưng không nhốt người chơi
## - ra mép bản đồ thì biến mất và xuất hiện lại ở đầu đường
## - thách đua qua giao thông thật: xe đỏ đường làng bờ bắc (A_xe_may_con_tay_do), xe đen đường dừa bờ nam
##   (C_xe_may_con_tay_den)
## - vỏ lãi: lên ở bến (đang chạy xe thì xe đỗ lại ở bến), chạy, không lên bờ được, bị cầu thấp chặn, chui qua cầu cao,
##   đủ 4 hướng nhìn, lên bờ ở bến và ở bờ đất
## - người đi bộ: đi giữa các điểm, không bao giờ đứng trong ô cấm, né người chơi, xe nhường người đi bộ, tối về nhà
## - World tạm dừng thì mọi thứ đứng yên
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_traffic_smoke.gd

const Activities := preload("res://game/world/activities.gd")
const ViewSettings := preload("res://game/world/view_settings.gd")
const PlayerBoat := preload("res://game/world/player_boat.gd")
const RaceRiders := preload("res://game/world/race/race_riders.gd")
const TEST_SAVE: String = "user://test_traffic_smoke.cfg"
const TEST_VIEW: String = "user://test_traffic_view.cfg"
const NORTH_RIDER: String = "A_xe_may_con_tay_do"
const SOUTH_RIDER: String = "C_xe_may_con_tay_den"

var _failures: int = 0
var _frames: int = 0
var _step: int = 0
var _world: World
var _traffic: Node
var _peds: Node
var _boat: Node
var _roads: Image
var _water: Image
var _road_samples: int = 0
var _road_hits: int = 0
var _water_samples: int = 0
var _water_hits: int = 0
var _overlap_fail: String = ""
var _s0: Dictionary = {}
var _veh: Object
var _challenged: String = ""
var _tmp: Dictionary = {}
## Sự kiện thành tích World đã phát (id → số lần).
var _ach: Dictionary = {}
var _veh_changed: int = 0
## Mọi id thành tích World phải phát trong lần chạy này.
const ACH_IDS: Array[StringName] = [&"visit_market", &"visit_lao_ga_kho", &"visit_lien_tinh", &"visit_olympia", &"visit_thpt",
	&"visit_temple", &"visit_catfish", &"first_bike", &"first_boat", &"boat_under_bridge", &"bike_over_bridge", &"boat_long_trip",
	&"race_triggered", &"honked_at"]
var _min_dist: float = INF
var _bad_cells: Array = []
var _step_usec: Array[int] = []
var _ped_usec: Array[int] = []


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.TUTORIAL
	Activities.save_path = TEST_SAVE
	Activities.reset()
	ViewSettings.save_path = TEST_VIEW
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_VIEW))
	seed(777)
	_roads = _load_mask("res://game/art/world_map/roads.png")
	_water = _load_mask("res://game/art/world_map/water.png")
	_world = World.new()
	root.add_child(_world)


static func _load_mask(path: String) -> Image:
	var res: Resource = load(path)
	var img: Image = res as Image
	if img == null and res is Texture2D:
		img = (res as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	return img


func _mask_near(img: Image, p: Vector2, r: int) -> bool:
	for dy in range(-r, r + 1, maxi(r, 1)):
		for dx in range(-r, r + 1, maxi(r, 1)):
			var x: int = int(p.x) + dx
			var y: int = int(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).r > 0.0:
				return true
	return false


func _next() -> void:
	_step += 1
	_frames = 0


func _timeout(limit: int, what: String) -> bool:
	if _frames > limit:
		_check(false, "timeout: " + what)
		_next()
	return false


func _place_player(p: Vector2, riding: bool = false) -> void:
	_world.player.set_riding(riding)
	_world.player.position = p
	_world.snap_camera()


## Mẫu vị trí: xe máy trên mặt đường, vỏ lãi trên mặt nước (trong tranh xe có đoạn ra ngoài mép bản đồ → bỏ qua).
func _sample_positions() -> void:
	for v in _traffic.vehicles:
		if not v.active:
			continue
		var p: Vector2 = v.pos
		if p.x < 2.0 or p.x > 5117.0 or p.y < 2.0 or p.y > 2157.0:
			continue
		if v.kind == "bike":
			_road_samples += 1
			if _mask_near(_roads, p + Vector2(0, -3), 4):
				_road_hits += 1
		else:
			_water_samples += 1
			if _mask_near(_water, p + Vector2(0, -4), 4):
				_water_hits += 1


## Khoảng cách điểm-đến-điểm giữa xe liền nhau trên cùng đường không nhỏ hơn khoảng an toàn.
func _check_overlap() -> void:
	if _overlap_fail != "":
		return
	var by_route: Dictionary = {}
	for v in _traffic.vehicles:
		if v.active:
			# xe đạp / ba gác chạy làn sát lề riêng (traffic.gd EDGE_TYPES) – không tính chồng với làn chính
			var key: String = v.route + ("|e" if v.edge else "")
			if not by_route.has(key):
				by_route[key] = []
			by_route[key].append(v)
	for key in by_route:
		var list: Array = by_route[key]
		list.sort_custom(func(a: Object, b: Object) -> bool: return a.s < b.s)
		for i in range(list.size() - 1):
			var a: Object = list[i]
			var b: Object = list[i + 1]
			var need: float = a.front + b.back + float(_traffic.GAP_MARGIN) - 0.5
			if b.s - a.s < need and a.s > 0.0:
				_overlap_fail = "%s: %d at %.0f, %d at %.0f (need %.0f)" % [key, a.index, a.s, b.index, b.s, need]


func _on_challenge(rider: String) -> void:
	_challenged = rider


func _put_vehicle(v: Object, route_id: String, s: float) -> void:
	_traffic.call("place_vehicle", v, route_id, s)
	# Dọn đường: xe khác cùng đường trong ±300 px bị cho biến mất tạm thời.
	for other in _traffic.vehicles:
		if other != v and other.active and other.route == route_id and absf(other.s - s) < 400.0:
			_traffic.call("_despawn", other)
			other.respawn_t = 60.0


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _traffic != null:
		_step_usec.append(int(_traffic.get("last_step_usec")))
	if _peds != null and bool(_peds.get("ready_grid")):
		_ped_usec.append(int(_peds.get("last_step_usec")))
	match _step:
		0:
			if _frames < 3:
				return false
			_traffic = _world.traffic
			_peds = _world.pedestrians
			_boat = _world.player_boat
			_peds.call("wait_ready")
			var data: Dictionary = MapView.traffic_data()
			var expected: int = data["spawns"].size() + _traffic.EXTRA_SPAWNS.size()
			_check(_traffic.vehicles.size() == expected, "all %d spawns (+%d river fillers) built as vehicles (%d)" % [data["spawns"].size(), _traffic.EXTRA_SPAWNS.size(), _traffic.vehicles.size()])
			var looks_ok: bool = true
			for v in _traffic.vehicles:
				looks_ok = looks_ok and v.actor != null and v.actor.is_inside_tree() and _traffic.routes.has(v.route) and _traffic.routes.has(v.origin)
			_check(looks_ok, "every vehicle has an actor in the Y-sorted map and a known route / respawn origin")
			var riders: Array = []
			for v in _traffic.vehicles:
				if v.rider != "":
					riders.append(v.rider)
			_check(riders.size() == 4, "the four race riders are live vehicles %s" % str(riders))
			_check(_traffic.route("river_main_west").next == "river_market_west" and _traffic.route("river_village_east").next == "uturn_village",
				"river gaps linked: main river continues west through the floating market, village river turns at the wooden bridge")
			_check(_world.race_bike_source.is_valid(), "World.race_bike_source hooked to the live traffic")
			_check(_peds.walkers.size() == 79, "79 walker candidates replaced by live pedestrians (%d)" % _peds.walkers.size())
			var hidden_ok: bool = true
			for w in _peds.walkers:
				if _world.map_view.has_node_named(w["id"]):
					hidden_ok = hidden_ok and _world.map_view.is_node_hidden(w["id"])
			_check(hidden_ok, "walkers' static map sprites are hidden")
			_check(not _world.map_view.is_node_hidden("NV_co_ban_ve_so") and not _world.map_view.is_node_hidden("N_npc_ba_Lan_ban_com"),
				"story NPCs / vendors (keep_static) stay on the map")
			for v in _traffic.vehicles:
				_s0[v.index] = [v.route, v.s, v.active]
			_world.achievement_event.connect(func(id: StringName) -> void: _ach[id] = int(_ach.get(id, 0)) + 1)
			_world.vehicles_changed.connect(func() -> void: _veh_changed += 1)
			_static_checks()
			for v in _traffic.vehicles:
				_s0[v.index] = [v.route, v.s, v.active]
			_place_player(Vector2(2480, 230))
			_next()
		1:
			# 6 s chạy: mẫu vị trí, không chồng nhau.
			_sample_positions()
			_check_overlap()
			if _frames < 360:
				return false
			var moved: int = 0
			var total: int = 0
			for v in _traffic.vehicles:
				var before: Array = _s0[v.index]
				if not before[2]:
					continue
				total += 1
				if v.route != before[0] or absf(v.s - before[1]) > 300.0 or not v.active:
					moved += 1
			_check(moved >= total - 2, "vehicles advance along their routes (%d/%d moved > 300 px in 6 s)" % [moved, total])
			_next()
		2:
			_sample_positions()
			_check_overlap()
			if _frames < 900:
				return false
			var road_ratio: float = float(_road_hits) / maxf(_road_samples, 1)
			var water_ratio: float = float(_water_hits) / maxf(_water_samples, 1)
			_check(road_ratio >= 0.97, "bikes stay on the road surface (%.1f%% of %d samples)" % [road_ratio * 100.0, _road_samples])
			_check(water_ratio >= 0.95, "boats stay on water (%.1f%% of %d samples)" % [water_ratio * 100.0, _water_samples])
			_check(_overlap_fail == "", "no two vehicles overlap on the same route over 21 s %s" % _overlap_fail)
			# Xe dừng trước người chơi đứng giữa làn.
			_veh = null
			for v in _traffic.vehicles:
				if v.kind == "bike" and v.rider == "" and v.origin == "road_T3_east":
					_veh = v
					break
			_put_vehicle(_veh, "road_T3_east", 2000.0)
			var stand: Vector2 = _traffic.route("road_T3_east").pos_at(2000.0 + 220.0)
			_place_player(stand + Vector2(0, -1))
			_tmp = {"horns": _traffic.horn_count, "stop_seen": false, "body_hit": false}
			_next()
		3:
			var p: Vector2 = _world.player.position
			var front_x: float = _veh.pos.x + _veh.front
			if front_x > p.x - 4.0:
				_tmp["body_hit"] = true
			if _veh.v <= 0.0:
				_tmp["stop_seen"] = true
			if _frames < 240:
				return false
			_check(bool(_tmp["stop_seen"]) and not bool(_tmp["body_hit"]), "bike brakes and stops behind the player standing in its lane (gap %.0f px)" % (p.x - front_x))
			_check(_traffic.horn_count > int(_tmp["horns"]), "waiting bike honks")
			# Đứng sát thân xe: không bước vào thân xe được, nhưng vẫn đi ra được.
			var body_x: float = _veh.pos.x
			_place_player(Vector2(body_x, _veh.pos.y - 9.0))
			_tmp["y0"] = _world.player.position.y
			Input.action_press(&"p1_crouch")
			_next()
		4:
			if _frames < 20:
				return false
			Input.action_release(&"p1_crouch")
			var blocked: bool = _world.player.position.y <= float(_tmp["y0"]) + 6.0
			_check(blocked and not _world.traffic.player_blockers.is_empty(), "walking player cannot step into a bike's body (moved %.0f px)" % (_world.player.position.y - float(_tmp["y0"])))
			Input.action_press(&"p1_jump")
			_tmp["y1"] = _world.player.position.y
			_next()
		5:
			if _frames < 20:
				return false
			Input.action_release(&"p1_jump")
			_check(_world.player.position.y < float(_tmp["y1"]) - 10.0, "player can always walk away from a stopped bike")
			# Đứng chồng lên thân xe (vd. xe dừng sát) → không bị nhốt.
			_place_player(_veh.pos + Vector2(0, -1))
			Input.action_press(&"p1_jump")
			_tmp["y2"] = _world.player.position.y
			_next()
		6:
			if _frames < 20:
				return false
			Input.action_release(&"p1_jump")
			_check(_world.player.position.y < float(_tmp["y2"]) - 10.0, "a bike overlapping the player's feet never traps the player")
			_place_player(Vector2(_veh.pos.x + 200.0, _veh.pos.y - 60.0))
			_next()
		7:
			if _frames < 120:
				return false
			_check(_veh.v > 60.0 and _veh.yielding_to == "", "bike resumes once the player leaves the lane (v=%.0f)" % _veh.v)
			# Ra mép bản đồ → biến mất → xuất hiện lại ở đầu đường.
			_put_vehicle(_veh, "road_T3_east", _traffic.route("road_T3_east").length - 0.5)
			_next()
		8:
			if _frames < 3:
				return false
			if _frames == 3:
				_check(not _veh.active and not _veh.actor.visible, "vehicle despawns at the east map edge")
			if not _veh.active:
				return _timeout(60 * 12, "respawn")
			_check(_veh.route == "road_T3_east" and _veh.s < 200.0, "vehicle respawns at the start of its route after a gap (s=%.0f)" % _veh.s)
			# Đua: xe đỏ đường làng bờ bắc.
			_world.race_challenge.connect(_on_challenge)
			_tmp = {}
			_next()
		9:
			if _race_follow(NORTH_RIDER, "road_village_north_east", 300.0):
				return false
			_check(_challenged == NORTH_RIDER, "live traffic: pacing then overtaking the red bike (north village road) triggers the race (%s)" % _challenged)
			_tmp = {}
			_next()
		10:
			if _race_follow(SOUTH_RIDER, "road_village_coconut_west", 300.0):
				return false
			_check(_challenged == SOUTH_RIDER, "live traffic: overtaking the black bike (south coconut road, westbound) triggers the race (%s)" % _challenged)
			_check(_ach.has(&"race_triggered"), "achievement_event race_triggered emitted with the challenge")
			_tmp = {}
			_step = 50
			_frames = 0
		50:
			# Tay đua có tên mới (cruiser) trên đường T1 – có dấu "!" trước khi thách.
			if _tmp.is_empty():
				_tmp_cue = false
			if _world.race_cue_key == "R_ba_phuot":
				_tmp_cue = true
			if _race_follow("R_ba_phuot", "road_T1_east", 900.0):
				return false
			_check(_challenged == "R_ba_phuot", "named rider on a new model (Anh Ba Phượt, cruiser) challenges after pacing + overtaking (%s)" % _challenged)
			_check(_tmp_cue, "a '!' cue shows over the rider's bike while pacing (race_cue_key)")
			_tmp = {}
			_next()
		51:
			# Một xe máy "racer" vô danh bất kỳ (dáng mới) cũng thách được.
			if _tmp.is_empty() and _generic_key == "":
				for v in _traffic.vehicles:
					if v.kind == "bike" and String(v.racer_key).begins_with("generic:") and String(v.look.get("model", "")) != "" \
							and String(v.route).begins_with("road_T2"):
						_generic_key = v.racer_key
						_generic_route = v.route
						break
				_check(_generic_key != "", "found an anonymous racer-type bike with a new look on road T2 (%s)" % _generic_key)
			if _generic_key != "" and _race_follow(_generic_key, _generic_route, 900.0):
				return false
			_check(_challenged == _generic_key and RaceRiders.get_rider(_challenged).get("vehicle") != null,
				"any racer-type NPC bike can challenge; its rider data carries the vehicle look (%s)" % _challenged)
			_world.player.set_riding(false)
			_world.mount_bike(false)
			_step = 11
			_frames = 0
		11:
			# Vỏ lãi: chạy xe tới bến chợ nổi rồi lên thuyền.
			for v in _traffic.vehicles:
				if v.kind == "boat":
					_traffic.call("_despawn", v)
					v.respawn_t = 3600.0
			var dock: Dictionary = _world.find_dock("dock_floating_market")
			_world.mount_bike(true)
			_place_player(Vector2(dock["pos"][0], dock["pos"][1]), true)
			_tmp = {"bike_at": _world.player.position}
			_world.board_boat("dock_floating_market")
			_next()
		12:
			if not _world.boating:
				return _timeout(60, "boarding")
			_check(_world.boating and not _world.player.riding and _world._bike_node.visible and _world.bike_pos == _tmp["bike_at"],
				"boarding at a dock while riding parks the motorbike at the dock")
			_check(_world.player.position.distance_to(_boat.call("seat_point")) < 1.5 and not _world.player.can_move, "player stands at the helm")
			_check(_boat.call("footprint_clear", _boat.center, _boat.heading), "boat placed fully on water at the dock")
			_tmp["c0"] = _boat.center
			for h in [0, 8]:
				if _boat.call("footprint_clear", _boat.center, h):
					_boat.heading = h
					break
			_boat.scripted = {"fwd": 1.0, "turn": 0}
			_next()
		13:
			if not _boat.call("footprint_clear", _boat.center, _boat.heading):
				_tmp["left_water"] = true
			if _frames < 150:
				return false
			var moved: float = (_boat.center - _tmp["c0"]).length()
			_check(moved > 120.0 and not _tmp.has("left_water"), "boat drives forward with momentum (%.0f px in 2.5 s, max %.0f px/s)" % [moved, PlayerBoat.MAX_FWD])
			# Quay 4 hướng nhìn.
			_tmp["views"] = {}
			_boat.scripted = {"fwd": 0.0, "turn": 1}
			_next()
		14:
			_tmp["views"][PlayerBoat.view_of(_boat.heading)] = true
			if _frames < 150:
				return false
			_check(_tmp["views"].size() == 4, "steering cycles through east/south/west/north boat views %s" % str(_tmp["views"].keys()))
			# Lao vào bờ phía nam (bờ chợ): không lên bờ được.
			_boat.scripted = {}
			var south_start: Vector2 = _tmp["c0"]
			for k in range(30):
				if _boat.call("footprint_clear", south_start, 4):
					break
				south_start += Vector2(0, -4)
			_boat.call("place", south_start, 4)
			_boat.call("set_driving", true)
			_boat.scripted = {"fwd": 1.0, "turn": 0}
			_tmp["bumps"] = _boat.bumps
			_tmp.erase("left_water")
			_next()
		15:
			if not _boat.call("footprint_clear", _boat.center, _boat.heading):
				_tmp["left_water"] = true
			if _frames < 180:
				return false
			_check(not _tmp.has("left_water") and _boat.bumps > int(_tmp["bumps"]), "boat cannot enter land (bumps the bank, %d bumps)" % (_boat.bumps - int(_tmp["bumps"])))
			# Cầu thấp: cầu gỗ qua sông x 1389–1417.
			var spot: Variant = _find_clear(Vector2(1470, 470), 8, 1440.0, 1620.0)
			_check(spot != null, "found open water just east of the low wooden bridge")
			if spot != null:
				_boat.call("place", spot, 8)
				_boat.call("set_driving", true)
			_boat.scripted = {"fwd": 1.0, "turn": 0}
			_next()
		16:
			if _frames < 240:
				return false
			var hull: Rect2 = _boat.call("hull_rect")
			_check(hull.end.x < 1389.0, "the low wooden bridge no longer blocks: the player boat passes under it (hull right edge x=%.0f)" % hull.end.x)
			# Cầu cao: cầu bê tông sông chính x 3583–3626.
			var spot: Variant = _find_clear(Vector2(3720, 440), 8, 3660.0, 3800.0)
			if spot != null:
				_boat.call("place", spot, 8)
				_boat.call("set_driving", true)
			_boat.scripted = {"fwd": 1.0, "turn": 0}
			_tmp["deck_seen"] = false
			_next()
		17:
			for entry in _traffic.get("_overlays"):
				if (entry[1] as Node2D).visible and (entry[0] as Rect2).position.x == 3583.0:
					_tmp["deck_seen"] = true
			if _frames < 300:
				return false
			_check(_boat.center.x < 3560.0, "high concrete bridge lets the player boat pass under (x=%.0f)" % _boat.center.x)
			_check(bool(_tmp["deck_seen"]), "bridge deck is drawn over the boat while passing under")
			# Lên bờ ở bến tàu du lịch.
			_boat.scripted = {"fwd": 0.0, "turn": 0}
			var dock: Dictionary = _world.find_dock("dock_tour_pier")
			var spot: Array = _world.boat_spot_for(dock)
			_boat.call("place", spot[0], spot[1])
			_boat.call("set_driving", true)
			_boat.call("sync_player")
			_world.leave_boat()
			_next()
		18:
			if _world.boating:
				return _timeout(60, "disembark at dock")
			var dock: Dictionary = _world.find_dock("dock_tour_pier")
			_check(_world.player.position == Vector2(dock["pos"][0], dock["pos"][1]) and _world.player.can_move and not _world.boating,
				"disembark at a dock snaps the player to the dock and frees movement")
			_check(bool(_boat.moored) and not bool(_boat.active), "the boat stays moored where it was left")
			_check(_world.bike_pos == _tmp["bike_at"] and _world._bike_node.visible, "motorbike still parked where it was left")
			# Lên lại ở chỗ neo, chạy ra giữa sông, lên bờ đất (không phải bến).
			_world.board_boat()
			_next()
		19:
			if not _world.boating:
				return _timeout(60, "re-board moored boat")
			var spot: Variant = _find_bank_boat()
			_check(spot != null, "found a non-dock bank spot to test landing")
			if spot != null:
				_boat.call("place", spot[0], spot[1])
				_boat.call("set_driving", true)
				_boat.call("sync_player")
				_world._bank_spot = null
				_world.leave_boat()
			_next()
		20:
			if _world.boating:
				return _timeout(60, "disembark at bank")
			_check(not _world.player._blocked_at(_world.player.position) and (_world.nav_bits(Vector2i(_world.player.position) / 4) & 17) == 17,
				"disembark on a plain bank lands on walkable ground connected to the village (%s)" % str(_world.player.position))
			_check(not _world.ferry_moving and _world.ferry_boat != null, "village ferry untouched")
			# Người đi bộ: camera ở chợ.
			_place_player(Vector2(2300, 1300))
			_tmp = {"p0": {}}
			for w in _peds.walkers:
				_tmp["p0"][w["index"]] = w["pos"]
			_next()
		21:
			for w in _peds.walkers:
				if w["near"] and int(w["state"]) != 4:
					var c: Vector2i = Vector2i(w["pos"]) / 4
					if (_world.nav_bits(c) & 1) == 0 and _bad_cells.size() < 5:
						_bad_cells.append([w["id"], w["pos"]])
			if _frames < 60 * 25:
				return false
			var moved: int = 0
			for w in _peds.walkers:
				if (w["pos"] as Vector2).distance_to(_tmp["p0"][w["index"]]) > 40.0:
					moved += 1
			_check(moved >= 10 and int(_peds.path_requests) > 10, "pedestrians walk between spots on A* paths (%d moved > 40 px, %d paths)" % [moved, _peds.path_requests])
			_check(_bad_cells.is_empty(), "near pedestrians never stand on blocked cells %s" % str(_bad_cells))
			# Né người chơi: cho một người đi thẳng tới chỗ người chơi đứng.
			_tmp = _setup_avoid()
			_next()
		22:
			if _tmp.is_empty():
				_check(false, "found a walker for the avoid test")
				_next()
				return false
			var w: Dictionary = _tmp["w"]
			_min_dist = minf(_min_dist, (w["pos"] as Vector2).distance_to(_world.player.position))
			if _frames < 60 * 10:
				return false
			_check(_min_dist >= 8.5, "pedestrian never walks into the player (closest %.1f px)" % _min_dist)
			_check((w["pos"] as Vector2).distance_to(_tmp["start"]) > 12.0, "pedestrian steps around the player and keeps going")
			# Xe nhường người đi bộ.
			_tmp = _setup_ped_crossing()
			_next()
		23:
			if _tmp.is_empty():
				_check(false, "set up a pedestrian in a lane")
				_next()
				return false
			if _veh.yielding_to == "ped":
				_tmp["yield"] = true
			var w: Dictionary = _tmp["w"]
			var front: float = _veh.pos.x + _veh.front
			if front > (w["pos"] as Vector2).x - 4.0 and absf(_veh.pos.y - (w["pos"] as Vector2).y) < 8.0:
				_tmp["hit"] = true
			if _frames < 150:
				return false
			_check(_tmp.has("yield") and not _tmp.has("hit"), "bikes yield to a pedestrian standing in the lane")
			# Tối: về nhà.
			_tmp = {"outside": _peds.call("outside_count")}
			GameState.minutes = 19 * 60
			_next()
		24:
			if _frames < 60 * 70:
				return false
			var outside: int = _peds.call("outside_count")
			_check(outside <= int(_tmp["outside"]) / 2 and outside > 0, "at night most pedestrians go home (outside %d → %d)" % [_tmp["outside"], outside])
			GameState.minutes = 8 * 60
			_next()
		25:
			if _frames < 90:
				return false
			_check(int(_peds.call("outside_count")) == _peds.walkers.size(), "in the morning everyone comes out again")
			# World tạm dừng.
			_world.set_active(false)
			_tmp = {"veh": [], "peds": [], "boat": _boat.center}
			for v in _traffic.vehicles:
				_tmp["veh"].append(v.s)
			for w in _peds.walkers:
				_tmp["peds"].append(w["pos"])
			_next()
		26:
			if _frames < 60:
				return false
			var same: bool = true
			for i in range(_traffic.vehicles.size()):
				same = same and _traffic.vehicles[i].s == _tmp["veh"][i]
			for i in range(_peds.walkers.size()):
				same = same and _peds.walkers[i]["pos"] == _tmp["peds"][i]
			_check(same and _traffic.call("active_emitters") == 0, "world inactive: traffic, pedestrians and engine sounds all stop")
			_world.set_active(true)
			_tmp = {}
			_step = 60
			_frames = 0
		60:
			# Ghé từng khu → sự kiện visit_* (mỗi khu 24 frame – World xét 4 lần/giây).
			var ids: Array = World.VISIT_AREAS.keys()
			var k: int = _frames / 24
			if k < ids.size():
				if _frames % 24 == 0:
					_world.player.can_move = true
					_place_player((World.VISIT_AREAS[ids[k]] as Rect2).get_center())
				return false
			var missing: Array = []
			for id in ids:
				if not _ach.has(id):
					missing.append(id)
			_check(missing.is_empty(), "walking into every landmark area emits its visit_* event (missing %s)" % str(missing))
			# Chạy xe lên cầu bê tông sông chính.
			_world.mount_bike(true)
			_place_player(Vector2(3604, 300), true)
			_next_to(61)
		61:
			if _frames == 2:
				_place_player(Vector2(3604, 430), true)
			if _frames < 8:
				return false
			_check(_ach.has(&"first_bike") and _ach.has(&"bike_over_bridge"), "first_bike on mount and bike_over_bridge when riding onto a bridge")
			# Vỏ lãi chui dưới cầu khỉ sông phía nam (cầu thấp – trước đây chặn), chạy về tây.
			_world.mount_bike(false)
			var spot: Variant = _find_clear(Vector2(3110, 1930), 8, 3060.0, 3200.0)
			_check(spot != null, "open water east of the south-river monkey bridge")
			if spot != null:
				_boat.call("place", spot, 8)
				_boat.call("set_driving", true)
				_world.boating = true
				_world.player.can_move = false
				_world._trip_told = false
				_boat.call("sync_player")
			_boat.scripted = {"fwd": 1.0, "turn": 0}
			_tmp = {"duck": false}
			_next_to(62)
		62:
			if _world.player.call("is_ducking"):
				_tmp["duck"] = true
			if _frames < 300:
				return false
			_check(_boat.center.x < 2930.0, "player boat passes under the low south-river monkey bridge (x=%.0f)" % _boat.center.x)
			_check(_ach.has(&"boat_under_bridge") and bool(_tmp["duck"]), "boat_under_bridge emitted and the hero ducks under the deck")
			# Rạch vườn: từ sông làng chạy thẳng nam qua cầu xi măng (cầu ngang trên kênh dọc).
			var c: Variant = null
			for y in range(530, 470, -2):
				for x in range(660, 690, 2):
					if _boat.call("footprint_clear", Vector2(x, y), 4):
						c = Vector2(x, y)
						break
				if c != null:
					break
			_check(c != null, "vertical boat fits in the village river above the cement bridge")
			if c != null:
				_boat.call("place", c, 4)
				_boat.call("set_driving", true)
				_tmp["y0"] = (c as Vector2).y
			_boat.scripted = {"fwd": 1.0, "turn": 0}
			_next_to(63)
		63:
			if _frames < 240:
				return false
			_check(_boat.center.y > 640.0, "boat drives south under the cement bridge into the canal (y %.0f → %.0f)" % [float(_tmp.get("y0", 0.0)), _boat.center.y])
			# Chuyến dài: cộng dồn quãng đã chạy (đặt gần ngưỡng rồi chạy thêm trên sông chính).
			var open_spot: Variant = _find_clear(Vector2(2800, 470), 0, 2700.0, 2900.0)
			if open_spot != null:
				_boat.call("place", open_spot, 0)
				_boat.call("set_driving", true)
				_world._trip_told = false
			_boat.trip_px = World.BOAT_LONG_TRIP - 20.0
			_next_to(64)
		64:
			if _frames < 60:
				return false
			_check(_ach.has(&"boat_long_trip") and int(_ach[&"boat_long_trip"]) == 1, "boat_long_trip emitted once when a trip passes %.0f px" % World.BOAT_LONG_TRIP)
			_boat.scripted = {"fwd": 0.0, "turn": 0}
			_world.boating = false
			_boat.call("set_driving", false)
			_world.player.can_move = true
			_place_player(Vector2(131, 206))
			_next_to(65)
		65:
			if _frames < 4:
				return false
			# Tìm xe / thuyền: dấu trên bản đồ + mũi tên mép màn hình.
			var targets: Array = _world.vehicle_targets()
			var kinds: Array = targets.map(func(e: Dictionary) -> String: return String(e["kind"]))
			_check(kinds.has("bike") and kinds.has("boat") and _world.bike_parked and _world.boat_moored_pos() != null,
				"World exposes the parked bike (bike_pos, bike_parked) and the moored boat (boat_moored_pos) %s" % str(kinds))
			var far_ok: bool = true
			for e in targets:
				var screen: Vector2 = _world.map_to_screen(e["pos"])
				far_ok = far_ok and not World.edge_arrow(_world._edge.size, screen, 30.0).is_empty()
			_check(far_ok, "far-away bike and boat get an off-screen edge arrow")
			_check(_veh_changed >= 4, "vehicles_changed emitted on mount/dismount/board/leave (%d)" % _veh_changed)
			_check(_ach.has(&"first_boat"), "first_boat emitted when boarding the boat at a dock")
			var missing: Array = []
			for id in ACH_IDS:
				if not _ach.has(id):
					missing.append(id)
			_check(missing.is_empty(), "achievement_event emitted for every id in a scripted run (missing %s)" % str(missing))
			_step = 27
			_frames = 0
		27:
			if _frames < 30:
				return false
			var avg: float = _avg(_step_usec)
			var avg_p: float = _avg(_ped_usec)
			print("      traffic step avg %.3f ms (max %.3f), pedestrians step avg %.3f ms (max %.3f)" % [avg / 1000.0, _max(_step_usec) / 1000.0, avg_p / 1000.0, _max(_ped_usec) / 1000.0])
			_check(avg < 2000.0 and avg_p < 2000.0, "simulation cost per tick under 2 ms on average")
			print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
			quit(1 if _failures > 0 else 0)
			return true
	return false


static func _avg(list: Array[int]) -> float:
	if list.is_empty():
		return 0.0
	var total: float = 0.0
	for v in list:
		total += float(v)
	return total / float(list.size())


static func _max(list: Array[int]) -> float:
	var m: int = 0
	for v in list:
		m = maxi(m, v)
	return float(m)


var _tmp_cue: bool = false
var _generic_key: String = ""
var _generic_route: String = ""


func _next_to(step: int) -> void:
	_step = step
	_frames = 0


## Kiểm tra tĩnh lúc dựng: dáng xe mới, độ đa dạng, vỏ lãi ngồi trên nước, ông câu cá, xe máy qua cầu, thuyền qua sông.
func _static_checks() -> void:
	# --- dáng xe mới
	var models: Dictionary = {}
	var frames_ok: bool = true
	var new_looks: int = 0
	for id in _traffic._looks:
		var look: Dictionary = _traffic._looks[id]
		if look.get("model") == null:
			continue
		new_looks += 1
		models[String(look["model"])] = true
		frames_ok = frames_ok and (look["frames"]["east"] as Array).size() == 4 and (look["frames"]["west"] as Array).size() == 4 \
			and MapView.atlas_for_look(look) != null and look.get("speed_range") != null
	_check(new_looks >= 16 and models.size() >= 8, "new vehicle looks loaded from game/art/vehicles (%d looks, models %s)" % [new_looks, str(models.keys())])
	_check(frames_ok, "every new look has 4 wheel frames each way, its own atlas and a speed range")
	var bicycle: Dictionary = _traffic._looks.get("bike_23", {})
	var cruiser: Dictionary = _traffic._looks.get("bike_11", {})
	_check(not bicycle.is_empty() and not cruiser.is_empty() and float(bicycle["speed_range"][1]) < 100.0 and float(cruiser["speed_range"][0]) > 160.0
		and bool(bicycle.get("silent", false)), "per-look speeds: bicycle slow and silent, cruiser fast")
	var seen: Dictionary = {}
	var originals_on_road: int = 0
	var riders_ok: bool = true
	for v in _traffic.vehicles:
		if v.kind != "bike":
			continue
		seen[String(v.look["id"])] = true
		if v.rider != "":
			riders_ok = riders_ok and ["bike_01", "bike_02", "bike_03", "bike_04"].has(String(v.look["id"]))
		elif v.look.get("model") == null:
			originals_on_road += 1
	_check(seen.size() >= 8, "bikes on the map use varied looks (%d distinct)" % seen.size())
	_check(riders_ok, "the 4 race_rider bikes keep their original looks")
	_check(originals_on_road >= 1, "the owner's original 4 looks stay in the random mix (%d non-rider bikes use them)" % originals_on_road)
	var named: Array = []
	for v in _traffic.vehicles:
		if String(v.racer_key).begins_with("R_"):
			named.append(v.racer_key)
	_check(named.size() >= 4, "named riders on new models are live vehicles %s" % str(named))
	# xuất hiện lại → dáng khác
	var probe: Object = null
	for v in _traffic.vehicles:
		if v.kind == "bike" and not v.fixed_look:
			probe = v
			break
	var looks_seen: Dictionary = {}
	for i in range(16):
		_traffic.call("_reroll_look", probe)
		looks_seen[String(probe.look["id"])] = true
	_check(looks_seen.size() >= 4, "a respawning bike picks a different look (%d looks in 16 respawns)" % looks_seen.size())
	# --- vỏ lãi: đuôi thuyền chạm mặt nước ở mọi khung, bóng/vệt bóng không tách xa thân
	var atlas_img: Image = (load(MapView.TRAFFIC_ATLAS) as Texture2D).get_image()
	if atlas_img.is_compressed():
		atlas_img.decompress()
	var boat_bad: Array = []
	for id in _traffic._looks:
		var look: Dictionary = _traffic._looks[id]
		if String(look["kind"]) != "boat":
			continue
		for d in ["east", "west"]:
			var list: Array = look["frames"][d]
			for i in range(list.size()):
				var r: Array = list[i]
				var a: Vector2
				if look.get("frame_anchors") != null:
					var e: Array = look["frame_anchors"][d][i]
					a = Vector2(e[0], e[1])
				else:
					var base: Array = look["anchor"] if d == "east" else look["anchor_west"]
					a = Vector2(base[0], base[1])
				var off: int = _stern_offset(atlas_img, Rect2i(r[0], r[1], r[2], r[3]), d == "east") - int(a.y)
				if off < 0 or off > 11:
					boat_bad.append("%s/%s/%d:%d" % [id, d, i, off])
			if look.get("shadow") != null:
				var so: Array = look["shadow_offset"][d]
				if int(so[1]) > 4:
					boat_bad.append("%s/%s shadow +%d" % [id, d, so[1]])
	_check(boat_bad.is_empty(), "every boat look/frame: stern bottom sits on the waterline (0..11 px), no detached shadow %s" % str(boat_bad))
	# --- ông câu cá quay mặt ra nước
	var fishers: Array = _world.fisher_nodes()
	var fisher_ok: bool = fishers.size() == 2
	for e in fishers:
		fisher_ok = fisher_ok and _world.map_view.is_node_hidden(String(e[2]))
		var sprite: Sprite2D = e[1]
		var img: Image = sprite.texture.get_image()
		var bob := Vector2i(-1, -1)
		var face_skin: int = 0
		for y in range(img.get_height()):
			for x in range(53):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.5 and c.r8 == 238 and c.g8 == 88 and c.b8 == 68:
					bob = Vector2i(x, y)
				if y >= 9 and y <= 17 and c.a > 0.5 and c.r8 == 220 and c.g8 == 170:
					face_skin += 1
		var feet: Vector2 = (e[0] as Node2D).position
		var bob_map: Vector2 = feet + sprite.position + Vector2(bob)
		fisher_ok = fisher_ok and bob.y > 0 and bob_map.y > feet.y + 4.0 and face_skin > 30
		if String(e[2]) == "NV_ong_cau_ca":
			var wet: bool = false
			for dy in range(0, 10, 2):
				wet = wet or _world.is_water(bob_map.x, bob_map.y + dy)
			fisher_ok = fisher_ok and wet
	_check(fisher_ok, "both fishermen face the water (front view, face visible) with the bobber in front of them on the water")
	# --- xe máy qua mọi cầu đi bộ được (chân xe ±8 px)
	var bike_bad: Array = []
	var walk_count: int = 0
	_world.player.riding = false
	var walkable: Dictionary = {}
	for b in MapView.traffic_data().get("bridges", []):
		var rect := Rect2i(b["rect"][0], b["rect"][1], b["rect"][2], b["rect"][3])
		if _cross(rect):
			walkable[b["id"]] = rect
	_world.player.riding = true
	for id in walkable:
		walk_count += 1
		if not _cross(walkable[id]):
			bike_bad.append(id)
	_world.player.riding = false
	_check(walk_count >= 15 and bike_bad.is_empty(), "the motorbike can cross all %d walkable bridges %s" % [walk_count, str(bike_bad)])
	# --- thuyền: một vùng nước liền qua mọi sông/kênh chính và dưới mọi cầu trên sông
	var reach: Dictionary = _boat_reach(Vector2(2526, 400))
	var targets: Dictionary = {
		"village river W end": Vector2(30, 440), "main river E end": Vector2(5090, 460), "floating market": Vector2(2700, 470),
		"south river W end": Vector2(30, 1935), "south river E end": Vector2(5090, 1865), "kênh xáng": Vector2(3505, 1100),
		"rạch vườn": Vector2(655, 1200),
	}
	for b in MapView.traffic_data().get("bridges", []):
		if not String(b["id"]).contains("rach_nho") and not String(b["id"]).contains("ao_") and not String(b["id"]).contains("muong") \
				and String(b["id"]) != "N_cau_ban_nha_may":
			targets[String(b["id"])] = Vector2(b["rect"][0] + b["rect"][2] * 0.5, b["rect"][1] + b["rect"][3] * 0.5)
	var miss: Array = []
	for key in targets:
		if not _reach_near(reach, targets[key]):
			miss.append(key)
	_check(miss.is_empty(), "player boat reaches both ends of every river, the canals and under every river bridge (%d targets, missing %s)" % [targets.size(), str(miss)])


## Hàng đáy thân (đuôi) trong khung thuyền: cột dày ≥ 6 px ở 30% thân phía đuôi.
static func _stern_offset(img: Image, r: Rect2i, east: bool) -> int:
	var thick: Array[int] = []
	var bottom: Array[int] = []
	for x in range(r.size.x):
		var n: int = 0
		var b: int = -1
		for y in range(r.size.y):
			var c: Color = img.get_pixel(r.position.x + x, r.position.y + y)
			var dark: bool = c.b8 > c.r8 + 40 and c.r8 < 70
			if c.a > 0.0 and not dark and c.r8 + c.g8 + c.b8 < 690:
				n += 1
				b = y
		thick.append(n)
		bottom.append(b)
	var lo: int = -1
	var hi: int = -1
	for x in range(r.size.x):
		if thick[x] >= 6:
			if lo < 0:
				lo = x
			hi = x
	var span: int = hi - lo + 1
	var best: int = -1
	var from: int = lo if east else hi - int(span * 0.3)
	var to: int = lo + int(span * 0.3) if east else hi + 1
	for x in range(from, to):
		if thick[x] >= 6:
			best = maxi(best, bottom[x])
	return best


## Đi được từ một đầu cầu tới đầu kia (BFS 4 hướng trên ô 1 px quanh cầu, phép thử chân của WorldPlayer).
func _cross(rect: Rect2i) -> bool:
	var vertical: bool = rect.size.y >= rect.size.x
	var m: int = 30
	var area := Rect2i(rect.position - Vector2i(m, m), rect.size + Vector2i(m * 2, m * 2))
	var queue: Array[Vector2i] = []
	var seen: Dictionary = {}
	if vertical:
		for x in range(rect.position.x - 4, rect.end.x + 4):
			queue.append(Vector2i(x, rect.position.y - 6))
	else:
		for y in range(rect.position.y - 4, rect.end.y + 10):
			queue.append(Vector2i(rect.position.x - 6, y))
	var open: Array[Vector2i] = []
	for q in queue:
		if not _world.player._blocked_at(Vector2(q)):
			open.append(q)
			seen[q] = true
	var head: int = 0
	while head < open.size():
		var p: Vector2i = open[head]
		head += 1
		if (vertical and p.y >= rect.end.y + 6) or (not vertical and p.x >= rect.end.x + 6):
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if seen.has(n) or not area.has_point(n):
				continue
			seen[n] = true
			if not _world.player._blocked_at(Vector2(n)):
				open.append(n)
	return false


## Ô 8 px có tâm thuyền đặt được (nhìn ngang hướng 0 hoặc nhìn dọc hướng 4) nối liền với điểm xuất phát (8 hướng).
func _boat_reach(start: Vector2) -> Dictionary:
	var cell: int = 8
	var open: Dictionary = {}
	var s0 := Vector2i(start / float(cell))
	var queue: Array[Vector2i] = [s0]
	var seen: Dictionary = {s0: true}
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var p := Vector2(c * cell)
		if not (_world.is_water(p.x, p.y) and (_boat.call("navigable", p) as bool)):
			continue
		if not (_boat_fits(p, 0) or _boat_fits(p, 4)):
			continue
		open[c] = true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if not seen.has(n):
					seen[n] = true
					queue.append(n)
	return open


func _boat_fits(c: Vector2, h: int) -> bool:
	for q in PlayerBoat.footprint(c, h):
		if not _world.is_water(q.x, q.y):
			return false
	return true


func _reach_near(reach: Dictionary, p: Vector2) -> bool:
	var c := Vector2i(p / 8.0)
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if reach.has(c + Vector2i(dx, dy)):
				return true
	return false


## Bám theo xe tay lái rồi vượt. Trả về true khi còn đang chạy.
func _race_follow(rider: String, route_id: String, s: float) -> bool:
	if _tmp.is_empty():
		var v: Object = _traffic.call("find_racer", rider)
		_put_vehicle(v, route_id, s)
		_traffic.call("step", 0.0)
		var dir: int = 1 if v.dir == "east" else -1
		_world.race_cooldown = 0.0
		_world._race_pace.clear()
		_challenged = ""
		_tmp = {"v": v, "dir": dir}
		_place_player(Vector2(v.pos.x - 60.0 * dir, v.pos.y - 14.0), true)
		return true
	if _challenged != "":
		return false
	if _frames > 60 * 10:
		return false
	_world.player.position.x += 210.0 / 60.0 * float(_tmp["dir"])
	return true


## Tâm thuyền (hướng h) trong nước, x trong [x0, x1], quét quanh điểm gợi ý.
func _find_clear(hint: Vector2, h: int, x0: float, x1: float) -> Variant:
	for dy in range(0, 60, 4):
		for sgn in [1, -1]:
			var y: float = hint.y + float(dy * sgn)
			var x: float = x0
			while x <= x1:
				var c := Vector2(x, y)
				if _boat.call("footprint_clear", c, h):
					return c
				x += 6.0
	return null


## Thuyền đậu sát một bờ đất (không gần bến nào) để thử lên bờ.
func _find_bank_boat() -> Variant:
	for x in range(3000, 3500, 40):
		for y in range(340, 560, 4):
			var c := Vector2(x, y)
			for h in [0, 8]:
				if not _boat.call("footprint_clear", c, h):
					continue
				var seat: Vector2 = PlayerBoat.seat_of(c, h)
				var far: bool = true
				for dock in _world.docks():
					if seat.distance_to(Vector2(dock["water_pos"][0], dock["water_pos"][1])) < 120.0:
						far = false
				if far and _world.find_bank_spot(seat) != null:
					return [c, h]
	return null


## Người đi bộ gần camera đi thẳng tới chỗ người chơi đứng.
func _setup_avoid() -> Dictionary:
	for w in _peds.walkers:
		if not w["near"] or int(w["state"]) == 4:
			continue
		var start: Vector2 = w["pos"]
		for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			var ok: bool = true
			for k in range(1, 9):
				if not _peds.call("walkable", start + dir * float(k * 8)):
					ok = false
					break
			if not ok:
				continue
			var dest: Vector2 = start + dir * 64.0
			_place_player(start + dir * 32.0)
			_world.player.position = start + dir * 32.0
			w["state"] = 1
			w["path"] = PackedVector2Array([start, start + dir * 16.0, start + dir * 32.0, start + dir * 48.0, dest])
			w["pi"] = 1
			w["dest"] = dest
			w["detour"] = false
			w["chat_cd"] = 100.0
			_min_dist = INF
			return {"w": w, "start": start}
	return {}


## Đặt một người đi bộ đứng giữa làn trước một xe máy đang chạy tới.
func _setup_ped_crossing() -> Dictionary:
	for v in _traffic.vehicles:
		if v.kind == "bike" and v.rider == "" and v.origin == "road_T3_east":
			_veh = v
			break
	_put_vehicle(_veh, "road_T3_east", 2600.0)
	var spot: Vector2 = _traffic.route("road_T3_east").pos_at(2600.0 + 200.0)
	_place_player(spot + Vector2(0, -120))
	var best: Dictionary = {}
	for w in _peds.walkers:
		if int(w["state"]) != 4:
			best = w
			break
	if best.is_empty():
		return {}
	best["pos"] = spot
	(best["holder"] as Node2D).position = spot
	best["state"] = 0
	best["timer"] = 30.0
	best["chat_cd"] = 100.0
	_peds.call("step", 0.0)
	_traffic.call("step", 0.0)
	return {"w": best}
