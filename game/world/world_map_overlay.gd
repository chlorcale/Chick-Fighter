extends CanvasLayer

## Chỉ đường trên bản đồ lớn:
## - Phím M: bản đồ toàn xã trên giấy dó khung gỗ (ảnh thu nhỏ game/art/world_map/minimap.png): biểu tượng + tên các
##   địa danh (World.PLACES), người chơi, mục tiêu nhấp nháy, đường gợi ý theo đường sá (A* trên lưới 8 px, ưu tiên
##   mặt đường), xe máy đang đậu và vỏ lãi đang neo (nếu World cho biết), chú thích ở chân bản đồ.
##   M hoặc Esc để đóng; khi mở thì người chơi đứng yên.
## - Phím N: bật/tắt bản đồ nhỏ ở góc trái (dưới khung mục tiêu) – MẶC ĐỊNH TẮT, lựa chọn được nhớ trong
##   user://chick_fighter_map.cfg.
## Lưới đường đi dựng một lần trong luồng phụ (WorkerThreadPool) từ game/art/world_map/nav.png.

const MINIMAP: Texture2D = preload("res://game/art/world_map/minimap.png")
const MAP_SCALE: float = 4.0 # 1 px ảnh thu nhỏ = 4 px bản đồ
const ROUTE_CELL: int = 8
const MINI_SIZE: Vector2 = Vector2(240, 136)
const MINI_POS: Vector2 = Vector2(14, 100)
const ROAD_WEIGHT: float = 1.0
const OFFROAD_WEIGHT: float = 3.0
const SETTINGS_PATH: String = "user://chick_fighter_map.cfg"
## Biểu tượng địa danh (World.PLACES[..]["icon"]) → biểu tượng UISkin.
const PLACE_ICONS: Dictionary = {
	"home": &"house", "shop": &"coin", "temple": &"temple", "arena": &"fight", "boat": &"boat", "school": &"school",
	"site": &"brick", "market": &"market", "cat": &"cat", "cart": &"jar", "star": &"star",
}
const INK: Color = Color(0.243, 0.153, 0.094)

## File nhớ bật/tắt bản đồ nhỏ (test đổi sang file tạm).
static var settings_path: String = SETTINGS_PATH

var world: Node
var open: bool = false
## Bản đồ nhỏ góc trái: mặc định tắt (N bật/tắt, có nhớ).
var minimap_on: bool = false
var route: PackedVector2Array = PackedVector2Array()

var _big_frame: Control
var _big: Control
var _big_ui: Control
var _mini_frame: Control
var _mini: Control
var _font: Font
var _font_bold: Font
var _time: float = 0.0
var _astar: AStarGrid2D
var _grid_task: int = -1
var _grid_ready: bool = false
var _route_key: String = ""
var _route_timer: float = 0.0
var _froze_player: bool = false
var _world_active: bool = true


func _ready() -> void:
	layer = 12
	_font = DialogBox.make_font(false)
	_font_bold = DialogBox.make_font(true)
	minimap_on = load_minimap_setting()
	_mini_frame = Control.new()
	_mini_frame.position = MINI_POS - Vector2(10, 10)
	_mini_frame.size = MINI_SIZE + Vector2(20, 20)
	_mini_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_frame.draw.connect(func() -> void: UISkin.draw_panel(_mini_frame, Rect2(Vector2.ZERO, _mini_frame.size), &"dark"))
	UISkin.pixel(_mini_frame)
	add_child(_mini_frame)
	_mini = Control.new()
	_mini.position = MINI_POS
	_mini.size = MINI_SIZE
	_mini.clip_contents = true
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.draw.connect(_draw_mini)
	UISkin.pixel(_mini)
	add_child(_mini)
	# Bản đồ lớn ba lớp: khung (pixel) → ảnh bản đồ thu nhỏ (lọc mịn) → chữ, biểu tượng (pixel).
	_big_frame = _make_layer(_draw_big_frame, true)
	_big = _make_layer(_draw_big, false)
	_big_ui = _make_layer(_draw_big_ui, true)
	var nav: PackedByteArray = world.get("_nav")
	var nav_size: Vector2i = world.call("nav_size")
	_grid_task = WorkerThreadPool.add_task(_build_grid.bind(nav, nav_size), false, "Lưới chỉ đường")


func _make_layer(draw_fn: Callable, pixel: bool) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(draw_fn)
	c.visible = false
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel else CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(c)
	return c


func _exit_tree() -> void:
	wait_grid()


## Đặt mép trên của bản đồ nhỏ (World gọi khi bảng trạng thái đổi chiều cao – bản đồ nhỏ nằm ngay dưới bảng).
func set_mini_top(y: float) -> void:
	var top: float = maxf(MINI_POS.y, roundf(y) + 10.0)
	if _mini == null:
		return
	_mini.position = Vector2(MINI_POS.x, top)
	_mini_frame.position = _mini.position - Vector2(10, 10)


func set_world_active(active: bool) -> void:
	_world_active = active
	visible = active
	if not active and open:
		close_map()


## Đọc lựa chọn bản đồ nhỏ đã nhớ (không có file → tắt).
static func load_minimap_setting() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return false
	return bool(cfg.get_value("map", "minimap", false))


func set_minimap(on: bool) -> void:
	minimap_on = on
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("map", "minimap", on)
	cfg.save(settings_path)


## Dựng lưới A* 8 px (640×270) từ lưới đi 4 px của World: ô đi được nếu một trong 4 ô con đi được bằng chân;
## ô không phải mặt đường nặng gấp OFFROAD_WEIGHT. Chạy trong luồng phụ, chỉ đọc mảng byte.
func _build_grid(nav: PackedByteArray, size: Vector2i) -> void:
	var cols: int = size.x / 2
	var rows: int = size.y / 2
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2(ROUTE_CELL, ROUTE_CELL)
	astar.offset = Vector2(ROUTE_CELL * 0.5, ROUTE_CELL * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in range(rows):
		var run_start: int = 0
		var run_kind: int = -1
		for x in range(cols + 1):
			var kind: int = 0
			if x < cols:
				var b: int = 0
				var i0: int = (y * 2) * size.x + x * 2
				b = nav[i0] | nav[i0 + 1] | nav[i0 + size.x] | nav[i0 + size.x + 1]
				kind = 0 if (b & 1) == 0 else (1 if (b & 4) != 0 else 2)
			if x == cols or kind != run_kind:
				if run_kind == 0 and x > run_start:
					astar.fill_solid_region(Rect2i(run_start, y, x - run_start, 1), true)
				elif run_kind == 2 and x > run_start:
					astar.fill_weight_scale_region(Rect2i(run_start, y, x - run_start, 1), OFFROAD_WEIGHT)
				run_start = x
				run_kind = kind
	_astar = astar
	_grid_ready = true


## Chờ lưới chỉ đường dựng xong (test).
func wait_grid() -> void:
	if _grid_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_grid_task)
		_grid_task = -1


## Đường gợi ý (toạ độ bản đồ) từ from tới to; rỗng nếu lưới chưa sẵn sàng. allow_partial: đi gần nhất có thể.
func compute_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not _grid_ready:
		return PackedVector2Array()
	var a: Vector2i = _nearest_open(Vector2i(from / ROUTE_CELL))
	var b: Vector2i = _nearest_open(Vector2i(to / ROUTE_CELL))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var path: PackedVector2Array = _astar.get_point_path(a, b, true)
	return _simplify(path)


func _nearest_open(c: Vector2i) -> Vector2i:
	var region: Rect2i = _astar.region
	for r in range(0, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := c + Vector2i(dx, dy)
				if region.has_point(p) and not _astar.is_point_solid(p):
					return p
	return Vector2i(-1, -1)


## Bỏ điểm thẳng hàng (giữ chỗ rẽ) cho đường vẽ gọn.
func _simplify(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 3:
		return path
	var out := PackedVector2Array([path[0]])
	for i in range(1, path.size() - 1):
		var d1: Vector2 = (path[i] - path[i - 1]).normalized()
		var d2: Vector2 = (path[i + 1] - path[i]).normalized()
		if d1.dot(d2) < 0.999:
			out.append(path[i])
	out.append(path[path.size() - 1])
	return out


func toggle_map() -> void:
	if open:
		close_map()
	else:
		open_map()


func open_map() -> void:
	if open or world == null:
		return
	open = true
	for c in [_big_frame, _big, _big_ui]:
		c.visible = true
	_route_key = ""
	if world.player.can_move:
		world.player.can_move = false
		_froze_player = true
	_refresh_route(true)
	Achievements.unlock(&"explore_map")


func close_map() -> void:
	if not open:
		return
	open = false
	for c in [_big_frame, _big, _big_ui]:
		c.visible = false
	if _froze_player and world != null:
		world.player.can_move = true
	_froze_player = false


func _unhandled_input(event: InputEvent) -> void:
	if world == null or not _world_active or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_M:
			# Mở được cả khi đi bộ/chạy xe lẫn khi đang lái vỏ lãi (lúc lái, can_move = false).
			if open or ((world.player.can_move or bool(world.get("boating"))) and bool(world.interactions_enabled)):
				toggle_map()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if open:
				close_map()
				get_viewport().set_input_as_handled()
		KEY_N:
			if not open and bool(world.interactions_enabled):
				set_minimap(not minimap_on)
				get_viewport().set_input_as_handled()


## Khung bản đồ nhỏ (kể cả viền gỗ), toạ độ màn hình.
func minimap_rect() -> Rect2:
	return Rect2(_mini_frame.position, _mini_frame.size)


## Bản đồ nhỏ đang hiện trên màn hình không (test).
func minimap_visible() -> bool:
	return _mini.visible


func _process(delta: float) -> void:
	_time += delta
	_mini.visible = minimap_on and not open and _world_active and bool(world.interactions_enabled)
	_mini_frame.visible = _mini.visible
	_route_timer -= delta
	if _route_timer <= 0.0:
		_route_timer = 0.5
		_refresh_route(false)
	if _mini.visible:
		_mini.queue_redraw()
	if open:
		_big.queue_redraw()
		_big_ui.queue_redraw()


func _refresh_route(force: bool) -> void:
	if world == null:
		return
	var target: Variant = world.call("target_position", world.marker_target)
	if target == null:
		route = PackedVector2Array()
		_route_key = ""
		return
	var cell: Vector2i = Vector2i(world.player.position / 32.0)
	var key: String = "%s|%s|%s" % [world.marker_target, cell, target]
	if key == _route_key and not force:
		return
	var path: PackedVector2Array = compute_route(world.player.position, target)
	if path.is_empty() and not _grid_ready:
		return
	route = path
	_route_key = key


# ------------------------------------------------------------------ vẽ

func _frame_rect(view: Vector2) -> Rect2:
	return Rect2(Vector2(24, 46), Vector2(view.x - 48, view.y - 64))


## Khung ảnh bản đồ (giữ tỉ lệ 5120×2160) trong ruột giấy, chừa dải chú thích ở dưới.
func _map_rect(view: Vector2) -> Rect2:
	var inner: Rect2 = _frame_rect(view).grow(-26.0)
	var avail := Vector2(inner.size.x, inner.size.y - 44.0)
	var s: float = minf(avail.x / 5120.0, avail.y / 2160.0)
	var size: Vector2 = (Vector2(5120, 2160) * s).floor()
	return Rect2((inner.position + Vector2((avail.x - size.x) * 0.5, maxf(4.0, (avail.y - size.y) * 0.5))).round(), size)


func _draw_big_frame() -> void:
	var view: Vector2 = _big_frame.size
	_big_frame.draw_rect(Rect2(Vector2.ZERO, view), Color(0.04, 0.03, 0.02, 0.7))
	UISkin.draw_panel(_big_frame, _frame_rect(view), &"wood")
	var r: Rect2 = _map_rect(view)
	_big_frame.draw_rect(r.grow(4.0), Color(0.42, 0.27, 0.14))
	_big_frame.draw_rect(r.grow(2.0), Color(0.86, 0.74, 0.52))


func _draw_big() -> void:
	var r: Rect2 = _map_rect(_big.size)
	var s: float = r.size.x / 5120.0
	_big.draw_texture_rect(MINIMAP, r, false, Color(1.0, 0.96, 0.86))
	if route.size() >= 2:
		var pts := PackedVector2Array()
		for p in route:
			pts.append(r.position + p * s)
		_big.draw_polyline(pts, Color(0.2, 0.1, 0.0, 0.85), 6.0)
		_big.draw_polyline(pts, Color(1.0, 0.85, 0.2), 3.0)


## Vị trí xe máy đang đậu (null nếu đang chạy xe / không biết).
func bike_marker() -> Variant:
	if world == null:
		return null
	var visible_flag: Variant = world.get("bike_visible")
	var shown: bool = false
	if visible_flag != null:
		shown = bool(visible_flag)
	else:
		var node: Node = world.get("_bike_node")
		shown = node != null and is_instance_valid(node) and bool(node.get("visible"))
	var player: Node = world.get("player")
	if not shown or (player != null and bool(player.get("riding"))):
		return null
	var pos: Variant = world.get("bike_pos")
	return pos if pos is Vector2 else null


## Vị trí vỏ lãi đang neo (null nếu đang lái / chưa neo / World chưa hỗ trợ).
func boat_marker() -> Variant:
	if world == null or bool(world.get("boating")):
		return null
	if world.has_method("boat_moored_pos"):
		var p: Variant = world.call("boat_moored_pos")
		return p if p is Vector2 else null
	var boat: Node = world.get("player_boat")
	if boat == null or not is_instance_valid(boat) or not bool(boat.get("moored")):
		return null
	var c: Variant = boat.get("center")
	if c is Vector2:
		return c
	return (boat as Node2D).position if boat is Node2D else null


func _draw_big_ui() -> void:
	var view: Vector2 = _big_ui.size
	var frame: Rect2 = _frame_rect(view)
	var r: Rect2 = _map_rect(view)
	var s: float = r.size.x / 5120.0
	var to_screen := func(p: Vector2) -> Vector2: return (r.position + p * s).round()
	var target_id: StringName = world.marker_target
	# địa danh: biểu tượng trước, rồi tên (né chồng chữ: thử dưới → trên → phải → trái, kẹp trong khung bản đồ)
	var placed: Array[Rect2] = []
	for id in world.PLACES:
		var place: Dictionary = world.PLACES[id]
		var sp: Vector2 = to_screen.call(place["pos"])
		if id == target_id:
			var pulse: float = 14.0 + sin(_time * 5.0) * 3.0
			_big_ui.draw_circle(sp, pulse + 3.0, Color(1.0, 0.85, 0.2, 0.3))
			_big_ui.draw_arc(sp, pulse, 0.0, TAU, 28, Color(0.75, 0.2, 0.1), 3.0)
		_place_icon(_big_ui, String(place["icon"]), sp, 0.75)
		placed.append(Rect2(sp - Vector2(10, 10), Vector2(20, 20)))
	for id in world.PLACES:
		var place: Dictionary = world.PLACES[id]
		var sp: Vector2 = to_screen.call(place["pos"])
		var is_target: bool = id == target_id
		var text: String = String(place["name"])
		var size: Vector2 = UISkin.text_size(text, UISkin.FS_SMALL, true)
		var best := Rect2()
		for offset in [Vector2(-size.x * 0.5, 12), Vector2(-size.x * 0.5, -12 - size.y), Vector2(13, -size.y * 0.5),
				Vector2(-13 - size.x, -size.y * 0.5)]:
			var box := Rect2(sp + offset, size)
			box.position = box.position.clamp(r.position + Vector2(2, 2), r.end - box.size - Vector2(2, 2))
			best = box
			var clear: bool = true
			for other in placed:
				if other.intersects(box):
					clear = false
					break
			if clear:
				break
		placed.append(best)
		UISkin.draw_text(_big_ui, Vector2(best.position.x, best.position.y + _font_bold.get_ascent(UISkin.FS_SMALL)), text,
			UISkin.FS_SMALL, Color(0.64, 0.16, 0.08) if is_target else INK, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 3,
			Color(1.0, 0.96, 0.84))
	# xe máy đang đậu, vỏ lãi đang neo
	var bike: Variant = bike_marker()
	if bike != null:
		_marker(to_screen.call(bike), &"bike", "Xe máy")
	var boat: Variant = boat_marker()
	if boat != null:
		_marker(to_screen.call(boat), &"boat", "Vỏ lãi")
	# người chơi
	var pp: Vector2 = to_screen.call(world.player.position)
	var bob: float = -2.0 if fmod(_time, 0.8) < 0.4 else 0.0
	UISkin.draw_icon(_big_ui, &"you", pp + Vector2(0, -8 + bob), 1.0)
	UISkin.draw_text(_big_ui, pp + Vector2(-40, -24 + bob), "Bạn", UISkin.FS_SMALL, Color(0.7, 0.12, 0.08), true,
		HORIZONTAL_ALIGNMENT_CENTER, 80, 3, Color(1.0, 0.96, 0.84))
	# bảng tên trên khung
	var title: String = "BẢN ĐỒ XÃ BÌNH KÊ"
	var tw: float = UISkin.text_size(title, UISkin.FS_BODY, true).x
	var plate := Rect2(Vector2(roundf(view.x * 0.5 - tw * 0.5 - 22.0), frame.position.y - 26.0), Vector2(tw + 44.0, 58.0))
	UISkin.draw_panel(_big_ui, plate, &"plate")
	UISkin.draw_text(_big_ui, Vector2(plate.position.x, UISkin.baseline_in(plate.position.y, plate.size.y, UISkin.FS_BODY, true)),
		title, UISkin.FS_BODY, UISkin.GOLD, true, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x, 4, UISkin.SHADOW)
	# chú thích + mục tiêu
	var y: float = r.end.y + 12.0
	var x: float = r.position.x
	for item in [[&"you", "Bạn"], [&"target", "Mục tiêu"], [&"", "Đường gợi ý"], [&"bike", "Xe máy đậu"], [&"boat", "Vỏ lãi neo"]]:
		if item[0] == &"":
			_big_ui.draw_rect(Rect2(x, y + 9.0, 22.0, 6.0), Color(0.2, 0.1, 0.0))
			_big_ui.draw_rect(Rect2(x, y + 10.0, 22.0, 3.0), Color(1.0, 0.85, 0.2))
		else:
			UISkin.draw_icon(_big_ui, item[0], Vector2(x + 11.0, y + 12.0), 0.75)
		UISkin.draw_text(_big_ui, Vector2(x + 28.0, y + 18.0), String(item[1]), UISkin.FS_SMALL, INK, true)
		x += 36.0 + UISkin.text_size(String(item[1]), UISkin.FS_SMALL, true).x + 18.0
	var foot: String = "M / Esc: đóng · N: bản đồ nhỏ"
	var target: Variant = world.call("target_position", target_id)
	if target != null:
		foot = "Mục tiêu: %s · cách %s   ·   %s" % [world.call("target_name", target_id),
			world.call("format_distance", world.player.position.distance_to(target)), foot]
	UISkin.draw_text(_big_ui, Vector2(r.position.x, y + 18.0), foot, UISkin.FS_SMALL, UISkin.INK_SOFT, true,
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x)


func _marker(p: Vector2, icon: StringName, text: String) -> void:
	_big_ui.draw_circle(p + Vector2(0, 9), 6.0, Color(0, 0, 0, 0.25))
	UISkin.draw_icon(_big_ui, icon, p, 1.0)
	UISkin.draw_text(_big_ui, p + Vector2(-50, 26), text, UISkin.FS_SMALL, INK, true, HORIZONTAL_ALIGNMENT_CENTER, 100, 3,
		Color(1.0, 0.96, 0.84))


## Biểu tượng địa danh: đĩa giấy viền mực + hình UISkin.
func _place_icon(ci: CanvasItem, kind: String, p: Vector2, k: float) -> void:
	var icon: StringName = PLACE_ICONS.get(kind, &"")
	if icon == &"":
		draw_icon(ci, kind, p, k)
		return
	ci.draw_circle(p, 13.0 * k + 2.0, INK)
	ci.draw_circle(p, 13.0 * k, Color(0.98, 0.93, 0.8))
	UISkin.draw_icon(ci, icon, p, k)


func _draw_mini() -> void:
	var size: Vector2 = _mini.size
	var center: Vector2 = world.player.position
	var half: Vector2 = size * MAP_SCALE * 0.5
	var origin: Vector2 = (center - half).clamp(Vector2.ZERO, Vector2(5120, 2160) - half * 2.0)
	var src := Rect2((origin / MAP_SCALE).round(), size)
	_mini.draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.1))
	_mini.draw_texture_rect_region(MINIMAP, Rect2(Vector2.ZERO, size), src)
	var to_mini := func(p: Vector2) -> Vector2: return ((p - origin) / MAP_SCALE).round()
	if route.size() >= 2:
		var pts := PackedVector2Array()
		for p in route:
			pts.append(to_mini.call(p))
		_mini.draw_polyline(pts, Color(0.1, 0.05, 0.0, 0.8), 4.0)
		_mini.draw_polyline(pts, Color(1.0, 0.85, 0.2), 2.0)
	for id in world.PLACES:
		var place: Dictionary = world.PLACES[id]
		var mp: Vector2 = to_mini.call(place["pos"])
		if Rect2(Vector2(-10, -10), size + Vector2(20, 20)).has_point(mp):
			_place_icon(_mini, String(place["icon"]), mp, 0.5)
	var bike: Variant = bike_marker()
	if bike != null:
		UISkin.draw_icon(_mini, &"bike", to_mini.call(bike), 0.5)
	var boat: Variant = boat_marker()
	if boat != null:
		UISkin.draw_icon(_mini, &"boat", to_mini.call(boat), 0.5)
	var target: Variant = world.call("target_position", world.marker_target)
	if target != null:
		var tp: Vector2 = to_mini.call(target)
		var inner := Rect2(Vector2(8, 8), (size - Vector2(16, 16)).max(Vector2.ZERO))
		if inner.has_point(tp):
			_mini.draw_arc(tp, 7.0 + sin(_time * 5.0) * 2.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.2), 2.0)
		else:
			var arrow: Array = World.edge_arrow(size, tp, 10.0)
			if not arrow.is_empty():
				var p: Vector2 = arrow[0]
				var a: float = arrow[1]
				var poly := PackedVector2Array([p + Vector2(9, 0).rotated(a), p + Vector2(-5, 6).rotated(a),
					p + Vector2(-5, -6).rotated(a)])
				_mini.draw_colored_polygon(poly, Color(1.0, 0.85, 0.2))
	var pp: Vector2 = to_mini.call(center)
	_mini.draw_circle(pp, 4.0, Color(0, 0, 0, 0.7))
	_mini.draw_circle(pp, 3.0, Color(1.0, 0.25, 0.2))
	UISkin.draw_text(_mini, Vector2(6, size.y - 6), "N: ẩn · M: bản đồ", UISkin.FS_SMALL, UISkin.CREAM, true,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 3, UISkin.SHADOW)


## Biểu tượng địa danh vẽ bằng hình khối (không dùng ảnh): nền tròn + hình đặc trưng.
static func draw_icon(ci: CanvasItem, kind: String, p: Vector2, k: float) -> void:
	var r: float = 10.0 * k
	var bg: Color = {"home": Color(0.85, 0.35, 0.25), "shop": Color(0.9, 0.55, 0.2), "temple": Color(0.75, 0.2, 0.2),
		"arena": Color(0.8, 0.15, 0.15), "boat": Color(0.2, 0.45, 0.8), "school": Color(0.2, 0.55, 0.35),
		"site": Color(0.6, 0.5, 0.3), "market": Color(0.95, 0.6, 0.1), "cat": Color(0.95, 0.75, 0.45), "cart": Color(0.55, 0.62, 0.6),
		"star": Color(0.95, 0.75, 0.1)}.get(kind, Color(0.5, 0.5, 0.5))
	ci.draw_circle(p, r + 2.0 * k, Color(0.1, 0.06, 0.02))
	ci.draw_circle(p, r, bg)
	var w := Color(1, 1, 1)
	match kind:
		"home":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-6, -1) * k, p + Vector2(0, -7) * k, p + Vector2(6, -1) * k]), w)
			ci.draw_rect(Rect2(p + Vector2(-4, -1) * k, Vector2(8, 6) * k), w)
		"shop", "market":
			ci.draw_rect(Rect2(p + Vector2(-6, -5) * k, Vector2(12, 4) * k), w)
			ci.draw_rect(Rect2(p + Vector2(-5, -1) * k, Vector2(10, 6) * k), Color(1, 1, 1, 0.8))
		"temple":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, -2) * k, p + Vector2(0, -7) * k, p + Vector2(7, -2) * k]), w)
			ci.draw_rect(Rect2(p + Vector2(-4, -2) * k, Vector2(8, 7) * k), w)
		"arena":
			ci.draw_arc(p, 5.5 * k, 0.0, TAU, 16, w, 2.0 * k)
			ci.draw_circle(p, 2.0 * k, w)
		"boat":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0) * k, p + Vector2(7, 0) * k, p + Vector2(4, 4) * k, p + Vector2(-4, 4) * k]), w)
			ci.draw_line(p + Vector2(0, 0) * k, p + Vector2(0, -7) * k, w, 1.5 * k)
		"school":
			ci.draw_line(p + Vector2(-3, 6) * k, p + Vector2(-3, -6) * k, w, 1.5 * k)
			ci.draw_rect(Rect2(p + Vector2(-3, -6) * k, Vector2(8, 5) * k), Color(1.0, 0.3, 0.3))
		"site":
			ci.draw_rect(Rect2(p + Vector2(-6, 0) * k, Vector2(5, 4) * k), w)
			ci.draw_rect(Rect2(p + Vector2(1, 0) * k, Vector2(5, 4) * k), w)
			ci.draw_rect(Rect2(p + Vector2(-3, -5) * k, Vector2(6, 4) * k), w)
		"cat":
			ci.draw_circle(p + Vector2(0, 1) * k, 5.0 * k, w)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -1) * k, p + Vector2(-4, -7) * k, p + Vector2(-1, -3) * k]), w)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(5, -1) * k, p + Vector2(4, -7) * k, p + Vector2(1, -3) * k]), w)
		"cart":
			# xe khô gà Lão Gà Khô: hũ khô gà (nắp đỏ, thân cam) trên mặt xe, hai bánh
			ci.draw_rect(Rect2(p + Vector2(-3, -7) * k, Vector2(6, 2) * k), Color(0.85, 0.2, 0.15))
			ci.draw_rect(Rect2(p + Vector2(-3, -5) * k, Vector2(6, 5) * k), Color(0.95, 0.62, 0.2))
			ci.draw_rect(Rect2(p + Vector2(-1, -4) * k, Vector2(2, 2) * k), w)
			ci.draw_rect(Rect2(p + Vector2(-7, 0) * k, Vector2(14, 3) * k), w)
			ci.draw_circle(p + Vector2(-4, 5) * k, 1.8 * k, w)
			ci.draw_circle(p + Vector2(4, 5) * k, 1.8 * k, w)
		"star":
			var pts := PackedVector2Array()
			for i in range(10):
				var rr: float = (7.0 if i % 2 == 0 else 3.0) * k
				pts.append(p + Vector2(0, -rr).rotated(TAU * i / 10.0))
			ci.draw_colored_polygon(pts, w)
		_:
			ci.draw_circle(p, 3.0 * k, w)
