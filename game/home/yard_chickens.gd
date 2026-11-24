extends Node2D

## ĐÀN GÀ THẢ SÂN (NHÀ & SÂN GÀ): quản lý các YardChicken (yard_chicken.gd) – một con cho mỗi gà người chơi đang nuôi –
## và hiệu ứng sát đất của sân (bụi chân khi chạy, đất văng khi cào, hột lúa) + lông gà bay (lớp "Air" nổi trên người).
## Node này nằm NGAY TRƯỚC "Actors" (vẽ dưới mọi thứ y-sort); các con gà là con của "Actors" (y-sort cùng người chơi,
## người nhà, đồ đạc). Ban ngày gà đi lại trong sân, ban đêm (18:00–05:00) về bội ngủ, sáng ra bước ra cửa bội.
## Lưới đi được: home_nav.gd (ô 6 px, chân người chơi đặt ở tâm ô không chạm va chạm) ∩ khung sân YARD_BOUNDS.
## Dùng (home_scene.gd):  _yard = YardChickens.new(); _yard.setup(self, _actors)  ·  _yard.set_nav(nav); _yard.sync()

const YardChicken := preload("res://game/home/yard_chicken.gd")
const Layout := preload("res://game/home/home_layout.gd")
const HomeNav := preload("res://game/home/home_nav.gd")
const Data := preload("res://game/home/home_interior_data.gd")
const Audio := preload("res://game/audio/audio_director.gd")

## Khung sân gà gà được đi (trong rào tre, chưa tới mái hiên tôn xanh x ≥ 295 – dưới mái thì bị che).
const YARD_BOUNDS: Rect2 = Rect2(24, 134, 266, 386)
## Giờ gà lên chuồng / xuống chuồng (phút trong ngày).
const ROOST_AT: int = 18 * 60
const WAKE_AT: int = 5 * 60
## Chuồng gỗ nhà sàn (ô ổ rơm 15–20): chân thang + cửa chuồng (chỗ "ngủ").
const COOP_LADDER: Vector2 = Vector2(214, 230)
const COOP_DOOR: Vector2 = Vector2(252, 192)
## Máng nước ống tre (mang_nuoc_ong_tre 96..144 × 439..450): gà đứng đầu phải máng, quay trái mổ nước.
const DRINK_AT: Vector2 = Vector2(150, 447)
const DRINK_FACE_X: float = 128.0
const DUST: Color = Color(0.89, 0.76, 0.52, 0.85)
const DIRT: Color = Color(0.47, 0.32, 0.22, 1.0)
const GRAIN: Color = Color(0.96, 0.82, 0.29, 1.0)

var scene: Node2D                 # HomeScene (player)
var actors: Node2D
var nav: HomeNav
## Giờ ép (test / cảnh): −1 = theo GameState.minutes.
var force_minutes: int = -1

var _chickens: Array = []         # YardChicken theo chỉ số gà
var _hidden: Dictionary = {}      # ô đi được nhưng bị đồ vật che (sau bội, dưới tán cây/mái) – gà không vào
var _hidden_cages: int = -1
var _cells: Array[Vector2] = []   # tâm các ô đi được trong sân
var _ground_fx: Array = []        # [pos, vel, life, max, kind, color]
var _air_fx: Array = []
var _air: Node2D
var _crow_cd: float = 0.0
var _time: float = 0.0


func setup(p_scene: Node2D, p_actors: Node2D) -> void:
	scene = p_scene
	actors = p_actors
	name = "YardChickens"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_air = Node2D.new()
	_air.name = "Air"
	_air.z_index = 9
	_air.draw.connect(_draw_air)
	add_child(_air)


## cage_feet: chân các bội đang hiện (bội vẽ sẵn + bội đóng thêm) – gà không đi vào chỗ bị bội che khuất.
func set_nav(p_nav: HomeNav, cage_feet: Array = []) -> void:
	if p_nav == nav and not _cells.is_empty() and cage_feet.size() == _hidden_cages:
		return
	nav = p_nav
	_hidden_cages = cage_feet.size()
	_cells.clear()
	_hidden.clear()
	if nav == null:
		return
	var covers: Array[Rect2] = _cover_rects(cage_feet)
	for r in range(nav.size.y):
		for c in range(nav.size.x):
			var cell := Vector2i(c, r)
			var p: Vector2 = nav.center_of(cell)
			if not nav.is_walkable(cell) or not YARD_BOUNDS.has_point(p):
				continue
			if _covered(p, covers):
				_hidden[cell] = true
				continue
			_cells.append(p)
	# bội mới đóng chồng lên chỗ gà đang đứng: dời gà ra ô đi được gần nhất
	for ch in _chickens:
		var c2: Node2D = ch
		if bool(c2.call("is_roaming")) and not walkable(c2.position):
			c2.position = nearest_point(c2.position)


## Khớp đàn gà với GameState.chickens (thêm con mới, bỏ con đã bán, cập nhật màu/đồ/vương miện) – gà đang đi giữ chỗ.
func sync() -> void:
	var by_id: Dictionary = {}
	for ch in _chickens:
		if is_instance_valid(ch):
			by_id[int((ch as Node).get("chicken_id"))] = ch
	var keep: Array = []
	for i in range(GameState.chickens.size()):
		var side: Dictionary = GameState.chicken_side(i)
		var id: int = int(side.get("id", -1))
		var c: Node2D = by_id.get(id) as Node2D
		if c != null:
			by_id.erase(id)
			c.set("index", i)
			c.set("slot", i)
			c.call("apply_side", side, i == GameState.active)
		else:
			c = YardChicken.new()
			c.call("setup", self, i, side, i == GameState.active)
			actors.add_child(c)
			if is_night():
				c.call("sleep_now")
			else:
				c.call("spawn_at", _spawn_point(i))
		c.name = "yard_chicken_%d" % i
		keep.append(c)
	for id in by_id:
		(by_id[id] as Node).queue_free()
	_chickens = keep


func chickens() -> Array:
	return _chickens


func is_night() -> bool:
	var m: int = posmod(force_minutes if force_minutes >= 0 else GameState.minutes, 1440)
	return m >= ROOST_AT or m < WAKE_AT


func player_pos() -> Vector2:
	var p: Variant = scene.get("player") if scene != null else null
	return (p as Node2D).position if p is Node2D else Vector2(-1000, -1000)


# =================================================================== lưới đi trong sân

func walkable(p: Vector2) -> bool:
	if nav == null or not YARD_BOUNDS.has_point(p):
		return false
	var c := Vector2i(int(p.x) / HomeNav.CELL, int(p.y) / HomeNav.CELL)
	return nav.is_walkable(c) and not _hidden.has(c)


## Vùng che khuất (gà đứng đó chỉ lòi cái mào ra sau đồ vật): sau lưng bội gà, sau đồ vật y-sort cao (chân gà nằm trên
## gốc y-sort của vật mà vẫn trong khung hình vật), dưới lớp trên (tán cây, lá chuối, mái chuồng, mái hiên).
func _cover_rects(cage_feet: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var cs: Vector2 = Vector2(Data.CAGE_SIZE)
	for f in cage_feet:
		var foot: Vector2 = f
		out.append(Rect2(foot.x - cs.x * 0.5 - 2.0, foot.y - cs.y + 2.0, cs.x + 4.0, cs.y - 2.0 + 6.0))
	for e in Data.OBJECTS:
		var sort: int = int(e["sort"])
		if sort == Data.FLOOR_SORT:
			continue
		var r := Rect2(e["pos"], e["size"])
		# chỉ phần phía trên gốc y-sort (gà ở đó bị vật vẽ đè), nới 6 px cho thân gà
		r.size.y = float(sort) - r.position.y + 6.0
		if r.size.y > 0.0:
			out.append(r.grow_individual(3.0, 0.0, 3.0, 0.0))
	for e in Data.ABOVE:
		out.append(Rect2(e["pos"], e["size"]).grow(4.0))
	return out


func _covered(p: Vector2, covers: Array[Rect2]) -> bool:
	for r in covers:
		if r.has_point(p) or r.has_point(p + Vector2(0, -12)):
			return true
	return false


## Đoạn thẳng a→b đi được (lấy mẫu từng px).
func segment_clear(a: Vector2, b: Vector2) -> bool:
	var n: int = maxi(1, int(ceil(a.distance_to(b))))
	for k in range(n + 1):
		if not walkable(a.lerp(b, float(k) / float(n))):
			return false
	return true


## Đường đi (A* của home_nav) chỉ qua ô trong sân; bỏ ô xuất phát; điểm cuối = to. Rỗng nếu không có.
func path_to(from: Vector2, to: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if nav == null:
		return out
	var cells: Array[Vector2i] = nav.find_path(from, to)
	if cells.is_empty():
		return out
	for k in range(cells.size()):
		var p: Vector2 = nav.center_of(cells[k])
		if not YARD_BOUNDS.has_point(p):
			out.clear()
			return out
		if k == 0:
			continue
		out.append(p)
	if walkable(to) and (out.is_empty() or segment_clear(out[out.size() - 1], to)):
		out.append(to)
	return out


func nearest_point(p: Vector2) -> Vector2:
	var best: Vector2 = p
	var best_d: float = INF
	for c in _cells:
		var d: float = c.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best


## Một chỗ đi được trong sân cách near từ rmin tới rmax (Vector2(-1, -1) nếu không có).
func random_spot(near: Vector2, rmin: float, rmax: float, rng: RandomNumberGenerator) -> Vector2:
	var cand: Array[Vector2] = []
	for c in _cells:
		var d: float = c.distance_to(near)
		if d >= rmin and d <= rmax:
			cand.append(c)
	if cand.is_empty():
		return Vector2(-1, -1)
	return cand[rng.randi_range(0, cand.size() - 1)]


func _spawn_point(i: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(i * 131 + 7)
	var home: Vector2 = home_point(i)
	for k in range(12):
		var p: Vector2 = random_spot(home, 8.0, 42.0, rng)
		if p.x < 0.0:
			break
		var free: bool = true
		for ch in _chickens:
			if is_instance_valid(ch) and (ch as Node2D).position.distance_to(p) < 9.0:
				free = false
		if free:
			return p
	return home


# =================================================================== bội / chuồng

func _is_coop_house(slot: int) -> bool:
	return not Layout.is_cage(slot)


## Chỗ đứng trước cửa bội (ô đi được gần nhất dưới chân bội) / chân thang chuồng gỗ.
func home_point(slot: int) -> Vector2:
	var p: Vector2 = COOP_LADDER if _is_coop_house(slot) else Layout.coop_foot(slot) + Vector2(0, 6)
	return nearest_point(p)


## Chỗ con gà "ở" khi ngủ (trong bội / trong cửa chuồng gỗ) – vương miện + chữ z vẽ theo đây.
func sleep_point(slot: int) -> Vector2:
	if _is_coop_house(slot):
		return COOP_DOOR
	return Layout.coop_foot(slot) + Vector2(0, -2)


## Độ cao vương miện so với chỗ ngủ (ngồi trên chóp bội – bội xếp sát nhau nên không bay cao hơn chóp).
func sleep_crown_y(slot: int) -> float:
	if _is_coop_house(slot):
		return -32.0
	return -float(Data.CAGE_SIZE.y) + 3.0


func drink_point() -> Vector2:
	return nearest_point(DRINK_AT) if nav != null else Vector2(-1, -1)


func drink_face_x() -> float:
	return DRINK_FACE_X


## Một con gà khác đang rảnh gần c (để rượt) – null nếu không có.
func chase_partner(c: Node2D) -> Node2D:
	var cand: Array = []
	for o in _chickens:
		if o == c or not is_instance_valid(o):
			continue
		var on: Node2D = o
		if String(on.call("state_name")) in ["idle", "peck", "scratch", "walk"] and on.position.distance_to(c.position) < 70.0:
			cand.append(on)
	if cand.is_empty():
		return null
	return cand[int(c.get("rng").randi_range(0, cand.size() - 1))]


## Con gà đang đi lại gần c nhất trong bán kính r (null nếu không có).
func crowding(c: Node2D, r: float) -> Node2D:
	var best: Node2D = null
	var best_d: float = r
	for o in _chickens:
		if o == c or not is_instance_valid(o) or not bool((o as Node).call("is_roaming")):
			continue
		var d: float = (o as Node2D).position.distance_to(c.position)
		if d < best_d:
			best_d = d
			best = o
	return best


func crow_sound(_c: Node2D) -> void:
	if _crow_cd > 0.0:
		return
	_crow_cd = 25.0
	Audio.sfx(&"rooster_crow", -20.0, randf_range(0.95, 1.12))


# =================================================================== hiệu ứng sân

func dust(p: Vector2, n: int) -> void:
	for k in range(n):
		_ground_fx.append([p + Vector2(randf_range(-2, 2), randf_range(-1, 0)), Vector2(randf_range(-6, 6),
			randf_range(-5, -1)), 0.45, 0.45, &"dust", DUST])


func dirt(p: Vector2, dir: int) -> void:
	for k in range(2):
		_ground_fx.append([p, Vector2(float(dir) * randf_range(14, 26), randf_range(-26, -12)), 0.5, 0.5, &"dirt", DIRT])


func grain(p: Vector2) -> void:
	_ground_fx.append([p, Vector2.ZERO, 0.9, 0.9, &"grain", GRAIN])


## Lông gà bay: màu lấy theo màu thân của con gà (lệch hue như shader) – cam đỏ / đen.
func feathers(p: Vector2, n: int, side: Dictionary) -> void:
	var colors: Dictionary = side.get("colors", {})
	var body: Array = colors.get("body", [0.0, 1.0, 1.0])
	var base := Color(0.72, 0.26, 0.16)
	base = Color.from_hsv(fposmod(base.h + float(body[0]) + float(side.get("hue", 0.0)), 1.0),
		clampf(base.s * float(body[1]) * float(side.get("sat", 1.0)), 0.0, 1.0), clampf(base.v * float(body[2]), 0.0, 1.0))
	for k in range(n):
		var col: Color = base if k % 2 == 0 else Color(0.16, 0.2, 0.26)
		_air_fx.append([p + Vector2(randf_range(-4, 4), randf_range(-3, 2)), Vector2(randf_range(-10, 10),
			randf_range(-14, -6)), 1.4, 1.4, &"feather", col])


func ground_fx_count() -> int:
	return _ground_fx.size() + _air_fx.size()


func _process(delta: float) -> void:
	_time += delta
	_crow_cd = maxf(0.0, _crow_cd - delta)
	for f in _ground_fx:
		var v: Vector2 = f[1]
		if f[4] == &"dirt":
			v.y += 90.0 * delta
		else:
			v *= 1.0 - minf(1.0, 3.0 * delta)
		f[1] = v
		f[0] = (f[0] as Vector2) + v * delta
		f[2] = float(f[2]) - delta
	_ground_fx = _ground_fx.filter(func(f: Array) -> bool: return float(f[2]) > 0.0)
	for f in _air_fx:
		var v2: Vector2 = f[1]
		v2.y = minf(v2.y + 16.0 * delta, 7.0)          # rơi chậm, đung đưa
		v2.x = sin(_time * 5.0 + float(f[3]) * 9.0) * 6.0
		f[1] = v2
		f[0] = (f[0] as Vector2) + v2 * delta
		f[2] = float(f[2]) - delta
	_air_fx = _air_fx.filter(func(f: Array) -> bool: return float(f[2]) > 0.0)
	queue_redraw()
	if _air != null:
		_air.queue_redraw()


func _draw() -> void:
	for f in _ground_fx:
		var p: Vector2 = (f[0] as Vector2).round()
		var k: float = float(f[2]) / float(f[3])
		var col: Color = f[5]
		match f[4]:
			&"dust":
				var r: float = roundf(lerpf(3.0, 1.0, k))
				draw_rect(Rect2(p - Vector2(r, 1), Vector2(r * 2.0, 2)), Color(col, col.a * k))
				draw_rect(Rect2(p - Vector2(r - 1, 2), Vector2(maxf(r * 2.0 - 2.0, 1.0), 1)), Color(col, col.a * k * 0.7))
			&"dirt":
				draw_rect(Rect2(p, Vector2(1, 1)), Color(col, minf(1.0, k * 2.0)))
			&"grain":
				draw_rect(Rect2(p, Vector2(1, 1)), Color(col, minf(1.0, k * 2.0)))


func _draw_air() -> void:
	for f in _air_fx:
		var p: Vector2 = (f[0] as Vector2).round()
		var k: float = float(f[2]) / float(f[3])
		var col: Color = f[5]
		var c := Color(col, minf(1.0, k * 1.5))
		_air.draw_rect(Rect2(p, Vector2(2, 1)), c)
		_air.draw_rect(Rect2(p + Vector2(1, -1), Vector2(1, 1)), Color(c.lightened(0.25), c.a))
