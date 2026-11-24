class_name MapView
extends Node2D

## Hiển thị bản đồ thế giới 5120×2160 (Chick_Fighter_World_Map_Expanded.aseprite) theo từng layer, dựng bởi
## tools/art/build_world_map.py (manifest v3 trong game/art/world_map/world_layers.json):
## - below: nền đất, nước, decor sát đất (layer tĩnh đã gộp + cắt ô ≤ 512 px; layer động giữ riêng / tách mảnh)
## - objects: 03_Object, Y-sort cùng nhân vật (thêm nhân vật bằng add_actor); cụm cây tách thành từng cây
## - above: mái nhà, tán cây, dây điện – vẽ đè lên nhân vật
## Mọi layer động chạy đủ 96 frame × 80 ms như trong file Aseprite.
##
## Manifest v3: "atlases", "seqs" (bảng chuỗi 96 frame dùng chung), "below"/"object"/"above" là danh sách node:
##   ô tĩnh: {"static": [trang, ax, ay, w, h], "pos": [x, y]}
##   node có tên: {"name", "regions": [[trang, ax, ay, w, h]…], "states": [[region, x, y]…], "seq": chỉ số "seqs"
##                 (−1 = tĩnh, luôn trạng thái 0), "box": [x0, y0, x1, y1], tuỳ chọn "sort_y", "fade", "part_of",
##                 "clock": {"ms", "states"} – vật có nhịp riêng (vd. xe khô gà Lão Gà Khô 8 frame × 100 ms): trạng thái
##                 = states[⌊thời gian / ms⌋ mod số frame], tính từ cùng đồng hồ _time_ms của bản đồ (không theo 80 ms).}
##   seqs[seq][frame] = chỉ số trạng thái, −1 = ẩn ở frame đó.
## Hiệu năng: chỉ cập nhật node động có "box" giao với vùng camera (+ lề), chia theo ô 256 px. Atlas tải song song
## (ResourceLoader luồng) và giữ trong bộ nhớ tĩnh để màn tiêu đề → World không tải lại.

const MANIFEST_PATH: String = "res://game/art/world_map/world_layers.json"
const ATLAS_DIR: String = "res://game/art/world_map/"
const CELL: int = 256
const VIEW_MARGIN: float = 192.0

## Dùng chung giữa các MapView (màn tiêu đề, World): manifest đã parse + atlas đã tải. Giữ trong metadata của
## root (không dùng biến static) để khi thoát game root bị huỷ thì atlas được giải phóng theo.
const SHARED_META: StringName = &"map_view_shared"
## Thời gian dựng MapView gần nhất (ms): tải manifest + atlas (lần đầu) + tạo node. Để báo cáo/test.
static var last_build_ms: float = 0.0
static var last_load_ms: float = 0.0

var frame_ms: int = 80
var frame_count: int = 96
var map_size: Vector2i = Vector2i(5120, 2160)

var _atlases: Array[Texture2D] = []
var _seqs: Array = []
var _animated: Array[Dictionary] = [] # node động: {holder, sprite, node, y_sorted, hidden, sort_y, fade, stamp}
## Node có "clock" (nhịp riêng): cập nhật khi frame riêng đổi, độc lập với frame 80 ms của bản đồ.
var _clocked: Array[Dictionary] = []
var _by_name: Dictionary = {} # tên node → item (cả node tĩnh)
var _buckets: Dictionary = {} # Vector2i ô → Array[Dictionary]
var _above_buckets: Dictionary = {} # Vector2i ô → Array[Dictionary] – node có tên của lớp above (tán cây…)
## Node có tên của lớp object (cây dừa, nhà…) theo ô – làm trong vật cao đứng TRƯỚC người chơi (che người).
var _object_buckets: Dictionary = {}
var _faded: Array[Dictionary] = []
## Độ trong của tán cây/mái che (lớp above) khi người chơi đứng dưới.
const FOCUS_ALPHA: float = 0.45
## Vật Y-sort đứng trước người chơi (cây dừa, nhà, bụi to) che người: làm trong nếu cao ≥ chừng này.
const FOCUS_OBJECT_MIN_H: float = 40.0
const FOCUS_OBJECT_ALPHA: float = 0.55
## Làm trong kiểu "lỗ tròn" quanh người chơi (Stardew): chỉ phần tán/mái/cây trong bán kính FOCUS_RADIUS quanh thân bị
## làm mờ, phần còn lại của cụm cây vẫn đục (trước đây cả cụm tán to bị mờ → mảng "ma" lớn trên màn hình).
const FOCUS_RADIUS: float = 30.0
const FOCUS_SHADER: String = """
shader_type canvas_item;
uniform vec2 focus_pos;
uniform float radius = 30.0;
uniform float min_alpha = 0.35;
varying vec2 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec2 d = floor(world_pos) - floor(focus_pos);
	float k = 1.0 - smoothstep(radius * 0.55, radius, length(d * vec2(1.0, 0.8)));
	c.a *= mix(1.0, min_alpha, k);
	COLOR = c;
}
"""
static var _focus_material: ShaderMaterial
var _below: Node2D
var _ground_fx: Node2D
var _objects: Node2D
var _above: Node2D
var _time_ms: float = 0.0
var _frame: int = -1
var _stamp: int = 0
## false: cập nhật mọi node động mỗi frame (test/ảnh chụp toàn bản đồ).
var cull_enabled: bool = true
## Số node động cập nhật ở frame gần nhất (thống kê).
var last_updated: int = 0


static func load_shared() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_meta(SHARED_META):
		return tree.root.get_meta(SHARED_META)
	var t0: int = Time.get_ticks_usec()
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	var paths: Array[String] = []
	for atlas_name in manifest["atlases"]:
		var path: String = ATLAS_DIR + String(atlas_name)
		paths.append(path)
		ResourceLoader.load_threaded_request(path, "Texture2D")
	var atlases: Array[Texture2D] = []
	for path in paths:
		atlases.append(ResourceLoader.load_threaded_get(path) as Texture2D)
	var shared: Dictionary = {"manifest": manifest, "atlases": atlases}
	if tree != null:
		tree.root.set_meta(SHARED_META, shared)
	last_load_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return shared


func _ready() -> void:
	var t0: int = Time.get_ticks_usec()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shared: Dictionary = load_shared()
	var manifest: Dictionary = shared["manifest"]
	_atlases = shared["atlases"]
	frame_ms = int(manifest["frame_ms"])
	frame_count = int(manifest["frame_count"])
	map_size = Vector2i(int(manifest["size"][0]), int(manifest["size"][1]))
	_seqs = manifest["seqs"]

	_below = Node2D.new()
	_below.name = "Below"
	add_child(_below)
	_objects = Node2D.new()
	_objects.name = "Objects"
	_objects.y_sort_enabled = true
	add_child(_objects)
	_above = Node2D.new()
	_above.name = "Above"
	_above.z_index = 10
	add_child(_above)

	for node in manifest["below"]:
		_build(node, _below, false)
	for node in manifest["object"]:
		_build(node, _objects, true)
	for node in manifest["above"]:
		_build(node, _above, false)
	# Lớp hiệu ứng mặt đất/mặt nước: trên toàn bộ layer below, dưới vật thể và nhân vật.
	_ground_fx = Node2D.new()
	_ground_fx.name = "GroundFx"
	_below.add_child(_ground_fx)
	_set_frame(0, true)
	last_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## Nhân vật/NPC thêm vào đây được Y-sort theo position.y (đặt gốc ở chân).
func add_actor(actor: Node2D) -> void:
	_objects.add_child(actor)


## Hiệu ứng nằm sát mặt đất/mặt nước (gợn sóng, vệt đò, rơm rạ): vẽ trên nền, dưới mọi vật thể.
func add_ground(node: Node2D) -> void:
	_ground_fx.add_child(node)


## Ẩn/hiện một node của bản đồ theo tên (mọi layer, cả node động lẫn tĩnh).
## Node đã ẩn giữ nguyên trạng thái ẩn qua mọi frame.
func set_node_hidden(node_name: String, hidden: bool) -> void:
	var item: Dictionary = _by_name.get(node_name, {})
	if item.is_empty():
		push_warning("MapView: không có node '%s'" % node_name)
		return
	item["hidden"] = hidden
	_place_item(item, maxi(_frame, 0))


func is_node_hidden(node_name: String) -> bool:
	return bool(_by_name.get(node_name, {}).get("hidden", false))


func has_node_named(node_name: String) -> bool:
	return _by_name.has(node_name)


## Tâm của node ở frame hiện tại (toạ độ bản đồ), hoặc null nếu node không tồn tại, đang ẩn
## hoặc không hiện ở frame này. Tra bằng dictionary nên gọi mỗi frame được (không phụ thuộc lọc camera).
func node_center(node_name: String) -> Variant:
	var rect: Variant = node_rect(node_name)
	if rect == null:
		return null
	return (rect as Rect2).get_center()


## Khung (góc trên-trái + kích thước, toạ độ bản đồ) của node ở frame hiện tại, hoặc null.
func node_rect(node_name: String) -> Variant:
	var item: Dictionary = _by_name.get(node_name, {})
	if item.is_empty() or bool(item["hidden"]):
		return null
	var entry: Variant = _entry_for(item, maxi(_frame, 0))
	if entry == null:
		return null
	var region: Array = item["node"]["regions"][int(entry[0])]
	return Rect2(float(entry[1]), float(entry[2]), float(region[3]), float(region[4]))


## Ảnh của từng region trong node (dùng lại sprite của bản đồ cho hiệu ứng riêng, vd. cá tra, đua xe).
func node_textures(node_name: String) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var item: Dictionary = _by_name.get(node_name, {})
	if item.is_empty():
		return result
	for region in item["node"]["regions"]:
		var atlas := AtlasTexture.new()
		atlas.atlas = _atlases[int(region[0])]
		atlas.region = Rect2(region[1], region[2], region[3], region[4])
		result.append(atlas)
	return result


## Dữ liệu giao thông (game/art/world_map/traffic.json, dựng bởi tools/art/world_map_traffic.py): xe máy/vỏ lãi đã tách
## khỏi bản đồ để chạy lúc chơi. Đọc một lần, giữ tĩnh.
const TRAFFIC_PATH: String = "res://game/art/world_map/traffic.json"
const TRAFFIC_ATLAS: String = "res://game/art/world_map/traffic_atlas.png"
## Xe NPC mới vẽ riêng (tools/art/build_vehicles.py): cùng định dạng "vehicles", mỗi kiểu có "atlas" riêng – gộp vào
## traffic_data() lúc đọc (dựng lại bản đồ không làm mất xe mới).
const VEHICLES_PATH: String = "res://game/art/vehicles/vehicles.json"
static var _traffic: Dictionary = {}
static var _atlas_cache: Dictionary = {}


static func traffic_data() -> Dictionary:
	if _traffic.is_empty() and FileAccess.file_exists(TRAFFIC_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRAFFIC_PATH))
		if parsed is Dictionary:
			_traffic = parsed
			if FileAccess.file_exists(VEHICLES_PATH):
				var extra: Variant = JSON.parse_string(FileAccess.get_file_as_string(VEHICLES_PATH))
				if extra is Dictionary:
					var ids: Dictionary = {}
					for look in _traffic.get("vehicles", []):
						ids[String(look["id"])] = true
					for look in (extra as Dictionary).get("vehicles", []):
						if not ids.has(String(look["id"])):
							(_traffic["vehicles"] as Array).append(look)
	return _traffic


## Atlas ảnh của một kiểu xe ("atlas" = đường dẫn res:// riêng, mặc định traffic_atlas.png của bản đồ).
static func atlas_for_look(look: Dictionary) -> Texture2D:
	var path: String = String(look.get("atlas", "")) if look.get("atlas") != null else ""
	if path == "" or not path.begins_with("res://"):
		path = TRAFFIC_ATLAS
	if not _atlas_cache.has(path):
		_atlas_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _atlas_cache[path]


## Một kiểu xe/thuyền trong traffic_data() theo id ({} nếu không có).
static func find_look(vehicle_id: String) -> Dictionary:
	for vehicle in traffic_data().get("vehicles", []):
		if String(vehicle["id"]) == vehicle_id:
			return vehicle
	return {}


## Ảnh từng khung của một kiểu xe/thuyền trong traffic.json theo hướng ("east"/"west"), [] nếu không có.
static func vehicle_textures(vehicle_id: String, direction: String = "east") -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var vehicle: Dictionary = find_look(vehicle_id)
	if vehicle.is_empty():
		return result
	var atlas: Texture2D = atlas_for_look(vehicle)
	if atlas == null:
		return result
	for region in (vehicle["frames"] as Dictionary).get(direction, []):
		var tex := AtlasTexture.new()
		tex.atlas = atlas
		tex.region = Rect2(region[0], region[1], region[2], region[3])
		result.append(tex)
	return result


## Kiểu xe (id trong traffic.json) của tay lái trò đua bí mật – khoá là tên node xe cũ (race_riders.gd), "" nếu không có.
static func race_vehicle_id(rider_node: String) -> String:
	for spawn in traffic_data().get("spawns", []):
		if String(spawn.get("race_rider", "")) == rider_node:
			return String(spawn["vehicle"])
	return ""


## Đổi z_index của một node bản đồ (vd. lan can cầu vẽ đè lên vỏ lãi đang chui dưới mặt cầu).
func set_node_z(node_name: String, z: int) -> void:
	var item: Dictionary = _by_name.get(node_name, {})
	if not item.is_empty():
		(item["holder"] as Node2D).z_index = z


## Tên các node của lớp object có khung giao với rect (toạ độ bản đồ) – tìm lan can/cầu quanh một cây cầu.
func object_names_in(rect: Rect2) -> Array[String]:
	var out: Array[String] = []
	for node_name in _by_name:
		var item: Dictionary = _by_name[node_name]
		if not bool(item["y_sorted"]) or not (item["node"] as Dictionary).has("box"):
			continue
		var b: Array = item["node"]["box"]
		if Rect2(b[0], b[1], float(b[2]) - float(b[0]), float(b[3]) - float(b[1])).intersects(rect):
			out.append(String(node_name))
	return out


## Đổi gốc Y-sort của một vật (layer object) sang toạ độ y bản đồ cố định.
## Vd. cầu ván cá tra: sort theo mặt sàn để nhân vật đi trên cầu được vẽ đè lên ván.
func set_node_sort_y(node_name: String, sort_y: float) -> void:
	var item: Dictionary = _by_name.get(node_name, {})
	if item.is_empty() or not bool(item["y_sorted"]):
		return
	item["sort_y"] = sort_y
	_place_item(item, maxi(_frame, 0))


## Vùng bản đồ đang thấy (theo camera hiện tại) – dùng cho lọc cập nhật.
func visible_map_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2(Vector2.ZERO, Vector2(map_size))
	var screen := Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	return get_global_transform_with_canvas().affine_inverse() * screen


func _process(delta: float) -> void:
	_time_ms += delta * 1000.0
	var index: int = int(_time_ms / float(frame_ms)) % frame_count
	if index != _frame:
		_set_frame(index)
	for item in _clocked:
		var own: int = _clock_frame(item["node"])
		if own != int(item["clock_frame"]):
			item["clock_frame"] = own
			_place_item(item, maxi(_frame, 0))


func _make_sprite(region: Array) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = _atlases[int(region[0])]
	sprite.region_enabled = true
	sprite.region_rect = Rect2(region[1], region[2], region[3], region[4])
	return sprite


func _build(node: Dictionary, parent: Node2D, y_sorted: bool) -> void:
	if node.has("static"):
		var tile: Sprite2D = _make_sprite(node["static"])
		tile.position = Vector2(node["pos"][0], node["pos"][1])
		parent.add_child(tile)
		return

	var regions: Array = node["regions"]
	var sprite: Sprite2D = _make_sprite(regions[0])
	var holder: Node2D = sprite
	if y_sorted:
		# Gốc Y-sort = mép dưới của vật (hoặc "sort_y"); sprite lệch lên trên.
		holder = Node2D.new()
		holder.add_child(sprite)
	parent.add_child(holder)

	var item: Dictionary = {"holder": holder, "sprite": sprite, "node": node, "y_sorted": y_sorted,
		"hidden": false, "sort_y": node.get("sort_y", null), "fade": node.get("fade", null), "stamp": -1}
	if node.has("name"):
		_by_name[String(node["name"])] = item
	if parent == _above and node.has("box"):
		_register(_above_buckets, item, node["box"])
	elif y_sorted and node.has("name") and node.has("box"):
		_register(_object_buckets, item, node["box"])
	if int(node["seq"]) < 0:
		_place_item(item, 0)
		return
	_animated.append(item)
	_register(_buckets, item, node["box"])
	if node.has("clock"):
		item["clock_frame"] = _clock_frame(node)
		_clocked.append(item)


func _register(buckets: Dictionary, item: Dictionary, box: Array) -> void:
	for cy in range(floori(float(box[1]) / CELL), floori(float(int(box[3]) - 1) / CELL) + 1):
		for cx in range(floori(float(box[0]) / CELL), floori(float(int(box[2]) - 1) / CELL) + 1):
			var key := Vector2i(cx, cy)
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(item)


## Người chơi đứng dưới tán cây/mái che (lớp above): làm trong tán đó; đứng sau một vật cao Y-sort (cây dừa, nhà) mà
## phần giữa của vật che thân/đầu: làm trong vật gần nhất đó (gọi mỗi frame). point: chân người chơi (toạ độ bản đồ).
func set_focus(point: Vector2) -> void:
	var p: Vector2 = point + Vector2(0, -18)
	var now: Array[Dictionary] = []
	var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var bucket: Variant = _above_buckets.get(key)
	if bucket != null:
		for item in bucket:
			var holder: Node2D = item["holder"]
			if not holder.visible:
				continue
			var sprite: Sprite2D = item["sprite"]
			var rect := Rect2(sprite.position, sprite.region_rect.size)
			# Vật nhỏ hơn 5 px: thu vào 2 px sẽ ra kích thước âm (Godot báo lỗi) – bỏ qua, không cần làm trong.
			if rect.size.x > 4.0 and rect.size.y > 4.0 and rect.grow(-2.0).has_point(p):
				now.append(item)
	# Vật Y-sort cao đứng trước người chơi (cây dừa, nhà, bụi to) mà phần giữa che thân/đầu.
	var head: Vector2 = point + Vector2(0, -30)
	var objects: Variant = _object_buckets.get(key)
	if objects != null:
		for item in objects:
			var holder: Node2D = item["holder"]
			if not holder.visible or holder.position.y <= point.y + 1.0:
				continue
			var sprite: Sprite2D = item["sprite"]
			var size: Vector2 = sprite.region_rect.size
			if size.y < FOCUS_OBJECT_MIN_H or size.x < 8.0:
				continue
			var pos: Vector2 = holder.position + sprite.position
			var core := Rect2(pos.x + size.x * 0.15, pos.y, size.x * 0.7, size.y * 0.9)
			if core.has_point(p) or core.has_point(head):
				now.append(item)
	var mat: ShaderMaterial = focus_material()
	mat.set_shader_parameter("focus_pos", point + Vector2(0, -20))
	for item in _faded:
		if not now.has(item):
			(item["sprite"] as Sprite2D).material = null
	for item in now:
		(item["sprite"] as Sprite2D).material = mat
	_faded = now


static func focus_material() -> ShaderMaterial:
	if _focus_material == null:
		var shader := Shader.new()
		shader.code = FOCUS_SHADER
		_focus_material = ShaderMaterial.new()
		_focus_material.shader = shader
		_focus_material.set_shader_parameter("radius", FOCUS_RADIUS)
	return _focus_material


## Vật đang được làm trong quanh người chơi (test).
func faded_items() -> Array[Dictionary]:
	return _faded


## Frame riêng của node có "clock" (0..số frame − 1) theo đồng hồ bản đồ.
func _clock_frame(node: Dictionary) -> int:
	var clock: Dictionary = node["clock"]
	return int(_time_ms / float(clock["ms"])) % (clock["states"] as Array).size()


## Chỉ số ảnh (region) node đang hiện, −1 nếu không có/ẩn – để test kiểm tra hoạt ảnh.
func node_region_index(node_name: String) -> int:
	var item: Dictionary = _by_name.get(node_name, {})
	if item.is_empty() or bool(item["hidden"]):
		return -1
	var entry: Variant = _entry_for(item, maxi(_frame, 0))
	return -1 if entry == null else int(entry[0])


## Tua đồng hồ hoạt ảnh của bản đồ tới thời điểm ms (test/ảnh chụp), cập nhật mọi node động.
func set_time_ms(ms: float) -> void:
	_time_ms = ms
	_set_frame(int(_time_ms / float(frame_ms)) % frame_count, true)
	for item in _clocked:
		item["clock_frame"] = _clock_frame(item["node"])


func _entry_for(item: Dictionary, index: int) -> Variant:
	var node: Dictionary = item["node"]
	if node.has("clock"):
		return node["states"][int(node["clock"]["states"][_clock_frame(node)])]
	var seq: int = int(node["seq"])
	if seq < 0:
		return node["states"][0]
	var state: int = int(_seqs[seq][index])
	if state < 0:
		return null
	return node["states"][state]


func _place_item(item: Dictionary, index: int) -> void:
	var holder: Node2D = item["holder"]
	if bool(item["hidden"]):
		holder.visible = false
		return
	var entry: Variant = _entry_for(item, index)
	if entry == null:
		holder.visible = false
		return
	var sprite: Sprite2D = item["sprite"]
	var region: Array = item["node"]["regions"][int(entry[0])]
	sprite.texture = _atlases[int(region[0])]
	sprite.region_rect = Rect2(region[1], region[2], region[3], region[4])
	var top_left := Vector2(entry[1], entry[2])
	if item["fade"] != null:
		# Vật chạy vòng của bản đồ cũ: mờ dần khi tới mép cũ (không "biến mất" giữa đường).
		var fade: Array = item["fade"]
		var right: float = top_left.x + float(region[3])
		var alpha: float = clampf((float(fade[1]) - right) / maxf(float(fade[1]) - float(fade[0]), 1.0), 0.0, 1.0)
		sprite.modulate.a = alpha
		if alpha <= 0.0:
			holder.visible = false
			return
	holder.visible = true
	if item["y_sorted"]:
		var bottom: float = top_left.y + float(region[4]) if item["sort_y"] == null else float(item["sort_y"])
		holder.position = Vector2(0.0, bottom)
		sprite.position = Vector2(top_left.x, top_left.y - bottom)
	else:
		sprite.position = top_left


func _set_frame(index: int, all_items: bool = false) -> void:
	_frame = index
	_stamp += 1
	last_updated = 0
	if all_items or not cull_enabled:
		for item in _animated:
			_place_item(item, index)
		last_updated = _animated.size()
		return
	var view: Rect2 = visible_map_rect().grow(VIEW_MARGIN)
	var c0 := Vector2i(floori(view.position.x / CELL), floori(view.position.y / CELL))
	var c1 := Vector2i(floori(view.end.x / CELL), floori(view.end.y / CELL))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var bucket: Variant = _buckets.get(Vector2i(cx, cy))
			if bucket == null:
				continue
			for item in bucket:
				if int(item["stamp"]) == _stamp:
					continue
				item["stamp"] = _stamp
				_place_item(item, index)
				last_updated += 1
