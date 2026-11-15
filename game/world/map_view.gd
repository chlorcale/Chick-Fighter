class_name MapView
extends Node2D

## Hiển thị bản đồ xuất từ BoiCanh_MienTay_NhanVat.aseprite theo từng layer (tools/art/build_assets.py).
## - below: 00_Ground, 01_Water, 02_Decor_Duoi (layer tĩnh đã gộp, layer động giữ riêng)
## - objects: 03_Object, Y-sort cùng nhân vật (thêm nhân vật bằng add_actor)
## - above: 04_Above, vẽ đè lên nhân vật (mái nhà, tán cây, dây điện)
## Mọi layer động chạy đủ 96 frame × 80 ms như trong file Aseprite.
## Node có tên (động hoặc static_frame) tra được theo tên: ẩn/hiện, lấy tâm hiện tại, lấy ảnh từng region.

const MANIFEST_PATH: String = "res://game/art/map/map_layers.json"

var frame_ms: int = 80
var frame_count: int = 96

var _atlases: Array[Texture2D] = []
var _animated: Array[Dictionary] = [] # {holder, sprite, node, y_sorted, hidden, sort_y}
var _by_name: Dictionary = {} # tên node → item (cùng dạng _animated, cả node static_frame)
var _below: Node2D
var _ground_fx: Node2D
var _objects: Node2D
var _time_ms: float = 0.0
var _frame: int = -1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	frame_ms = int(manifest["frame_ms"])
	frame_count = int(manifest["frame_count"])
	for atlas_name in manifest["atlases"]:
		_atlases.append(load("res://game/art/map/" + String(atlas_name)) as Texture2D)

	_below = Node2D.new()
	_below.name = "Below"
	add_child(_below)
	_objects = Node2D.new()
	_objects.name = "Objects"
	_objects.y_sort_enabled = true
	add_child(_objects)
	var above := Node2D.new()
	above.name = "Above"
	above.z_index = 10
	add_child(above)

	for node in manifest["below"]:
		_build(node, _below, false)
	for node in manifest["object"]:
		_build(node, _objects, true)
	for node in manifest["above"]:
		_build(node, above, false)
	# Lớp hiệu ứng mặt đất/mặt nước: trên toàn bộ layer below, dưới vật thể và nhân vật.
	_ground_fx = Node2D.new()
	_ground_fx.name = "GroundFx"
	_below.add_child(_ground_fx)
	_set_frame(0)


## Nhân vật/NPC thêm vào đây được Y-sort theo position.y (đặt gốc ở chân).
func add_actor(actor: Node2D) -> void:
	_objects.add_child(actor)


## Hiệu ứng nằm sát mặt đất/mặt nước (gợn sóng, vệt đò, rơm rạ): vẽ trên nền, dưới mọi vật thể.
func add_ground(node: Node2D) -> void:
	_ground_fx.add_child(node)


## Ẩn/hiện một node của bản đồ theo tên (mọi layer, cả node động lẫn static_frame).
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
## hoặc không hiện ở frame này. Tra bằng dictionary nên gọi mỗi frame được.
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


## Ảnh của từng region trong node (dùng lại sprite của bản đồ cho hiệu ứng riêng, vd. cá tra).
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


## Đổi gốc Y-sort của một vật (layer object) sang toạ độ y bản đồ cố định.
## Vd. cầu ván cá tra: sort theo mặt sàn để nhân vật đi trên cầu được vẽ đè lên ván.
func set_node_sort_y(node_name: String, sort_y: float) -> void:
	var item: Dictionary = _by_name.get(node_name, {})
	if item.is_empty() or not bool(item["y_sorted"]):
		return
	item["sort_y"] = sort_y
	_place_item(item, maxi(_frame, 0))


func _process(delta: float) -> void:
	_time_ms += delta * 1000.0
	var index: int = int(_time_ms / float(frame_ms)) % frame_count
	if index != _frame:
		_set_frame(index)


func _make_sprite(region: Array) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = _atlases[int(region[0])]
	sprite.region_enabled = true
	sprite.region_rect = Rect2(region[1], region[2], region[3], region[4])
	return sprite


func _build(node: Dictionary, parent: Node2D, y_sorted: bool) -> void:
	if node.has("static"):
		var sprite: Sprite2D = _make_sprite(node["static"])
		sprite.position = Vector2(node["pos"][0], node["pos"][1])
		parent.add_child(sprite)
		return

	var regions: Array = node["regions"]
	var sprite: Sprite2D = _make_sprite(regions[0])
	var holder: Node2D = sprite
	if y_sorted:
		# Gốc Y-sort = mép dưới của vật; sprite lệch lên trên bằng chiều cao ảnh.
		holder = Node2D.new()
		holder.add_child(sprite)
	parent.add_child(holder)

	var item: Dictionary = {"holder": holder, "sprite": sprite, "node": node, "y_sorted": y_sorted,
		"hidden": false, "sort_y": null}
	if node.has("name"):
		_by_name[String(node["name"])] = item
	if node.has("static_frame"):
		_place_item(item, 0)
		return
	_animated.append(item)


func _entry_for(item: Dictionary, index: int) -> Variant:
	var node: Dictionary = item["node"]
	if node.has("static_frame"):
		return node["static_frame"]
	return node["frames"][index]


func _place_item(item: Dictionary, index: int) -> void:
	var holder: Node2D = item["holder"]
	if bool(item["hidden"]):
		holder.visible = false
		return
	_place(holder, item["sprite"], item["node"]["regions"], _entry_for(item, index), item["y_sorted"], item["sort_y"])


func _place(holder: Node2D, sprite: Sprite2D, regions: Array, entry: Variant, y_sorted: bool, sort_y: Variant = null) -> void:
	if entry == null:
		holder.visible = false
		return
	holder.visible = true
	var region: Array = regions[int(entry[0])]
	sprite.texture = _atlases[int(region[0])]
	sprite.region_rect = Rect2(region[1], region[2], region[3], region[4])
	var top_left := Vector2(entry[1], entry[2])
	if y_sorted:
		var bottom: float = top_left.y + float(region[4]) if sort_y == null else float(sort_y)
		holder.position = Vector2(0.0, bottom)
		sprite.position = Vector2(top_left.x, top_left.y - bottom)
	else:
		sprite.position = top_left


func _set_frame(index: int) -> void:
	_frame = index
	for item in _animated:
		_place_item(item, index)
