extends Node2D

## Một xe máy / vỏ lãi NPC trên bản đồ (do Traffic điều khiển). Gốc node = điểm trên đường (bánh xe chạm đất / mép
## nước của thân thuyền) → Y-sort chung với người chơi qua MapView.add_actor.
## Ảnh lấy từ game/art/world_map/traffic_atlas.png theo traffic.json: góc trên-trái khung = điểm − anchor (theo hướng,
## hoặc frame_anchors khi các khung khác cỡ). Bóng đổ / vệt sóng / bọt nước nằm ở lớp mặt đất (MapView.add_ground) –
## góc trên-trái = điểm + *_offset[hướng]; mỗi thứ đổi khung theo nhịp riêng (*_ms).

var look: Dictionary = {}
var dir_name: String = "east"
## Lớp mặt đất chứa bóng/vệt sóng/bọt (do Traffic thêm vào MapView.add_ground).
var ground: Node2D

var _sprite: Sprite2D
var _shadow: Sprite2D
var _wake: Sprite2D
var _foam: Sprite2D


## look: một phần tử "vehicles" của traffic.json (hoặc game/art/vehicles/vehicles.json). atlas: ảnh của kiểu xe đó
## (MapView.atlas_for_look).
func setup(p_look: Dictionary, atlas: Texture2D) -> void:
	look = p_look
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite = _make(atlas)
	add_child(_sprite)
	ground = Node2D.new()
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if look.get("shadow") != null:
		_shadow = _make(atlas)
		_shadow.modulate.a = 0.85
		ground.add_child(_shadow)
	if look.get("wake") != null:
		_wake = _make(atlas)
		ground.add_child(_wake)
	if look.get("foam") != null:
		_foam = _make(atlas)
		ground.add_child(_foam)


## Đổi kiểu xe (xe máy NPC xuất hiện lại với dáng khác). Chỉ dùng cho xe máy: bóng đổ có, không vệt sóng/bọt.
func set_look(p_look: Dictionary, atlas: Texture2D) -> void:
	look = p_look
	_sprite.texture = atlas
	if look.get("shadow") != null:
		if _shadow == null:
			_shadow = _make(atlas)
			_shadow.modulate.a = 0.85
			ground.add_child(_shadow)
		_shadow.texture = atlas
		_shadow.visible = true
	elif _shadow != null:
		_shadow.visible = false


func _make(atlas: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.centered = false
	sprite.region_enabled = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite


## Đặt xe tại điểm point (toạ độ bản đồ), hướng "east"/"west", đồng hồ hoạt ảnh t_ms (xe máy: theo quãng bánh lăn),
## speed01 = tốc độ / tốc độ hành trình (0..1) – vệt sóng/bọt mờ dần khi thuyền chậm lại.
func show_at(point: Vector2, direction: String, t_ms: float, speed01: float) -> void:
	dir_name = direction
	var p: Vector2 = point.round()
	position = p
	var frames: Array = (look["frames"] as Dictionary).get(direction, [])
	if frames.is_empty():
		return
	var index: int = int(t_ms / float(look.get("frame_ms", 80))) % frames.size()
	var region: Array = frames[index]
	_sprite.region_rect = Rect2(region[0], region[1], region[2], region[3])
	_sprite.position = -anchor_for(direction, index).round()
	ground.position = p
	if _shadow != null and look.get("shadow") != null:
		var sh: Array = look["shadow"][direction]
		var off: Array = look["shadow_offset"][direction]
		_shadow.region_rect = Rect2(sh[0], sh[1], sh[2], sh[3])
		_shadow.position = Vector2(off[0], off[1])
	_place_fx(_wake, "wake", direction, t_ms, speed01)
	_place_fx(_foam, "foam", direction, t_ms, speed01)


func _place_fx(sprite: Sprite2D, key: String, direction: String, t_ms: float, speed01: float) -> void:
	if sprite == null:
		return
	var frames: Array = (look[key] as Dictionary).get(direction, [])
	sprite.visible = speed01 > 0.15 and not frames.is_empty()
	if not sprite.visible:
		return
	var ms_value: Variant = look.get(key + "_ms")
	var ms: float = 80.0 if ms_value == null else maxf(float(ms_value), 1.0)
	var fi: int = int(t_ms / ms) % frames.size()
	var region: Array = frames[fi]
	var off: Array = look[key + "_offset"][direction]
	# độ lệch riêng từng khung (bọt nước khác cỡ: chân bọt luôn sát mặt nước, mép bọt sát chân vịt)
	var per: Variant = look.get(key + "_frame_offsets")
	if per != null and (per as Dictionary).has(direction):
		var list: Array = per[direction]
		off = list[clampi(fi, 0, list.size() - 1)]
	sprite.region_rect = Rect2(region[0], region[1], region[2], region[3])
	sprite.position = Vector2(off[0], off[1])
	sprite.modulate.a = clampf((speed01 - 0.15) / 0.5, 0.0, 1.0)


## Neo (điểm trên đường tính từ góc trên-trái khung) của khung index theo hướng.
func anchor_for(direction: String, index: int = 0) -> Vector2:
	var per: Variant = look.get("frame_anchors")
	if per != null and (per as Dictionary).has(direction):
		var list: Array = per[direction]
		var a: Array = list[clampi(index, 0, list.size() - 1)]
		return Vector2(a[0], a[1])
	var base: Array = look["anchor"] if direction == "east" else look.get("anchor_west", look["anchor"])
	return Vector2(base[0], base[1])


## Khung ảnh (toạ độ bản đồ) ở khung 0 theo hướng hiện tại – dò đua xe, ảnh chụp.
func frame_rect() -> Rect2:
	var frames: Array = (look["frames"] as Dictionary).get(dir_name, [])
	var size := Vector2(look["size"][0], look["size"][1])
	if not frames.is_empty():
		size = Vector2(frames[0][2], frames[0][3])
	return Rect2(position - anchor_for(dir_name, 0), size)


func set_shown(on: bool) -> void:
	visible = on
	if ground != null:
		ground.visible = on


func set_alpha(a: float) -> void:
	modulate.a = a
	if ground != null:
		ground.modulate.a = a
