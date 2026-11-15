extends Node2D

## Hiệu ứng pixel nhỏ ở toạ độ bản đồ: gợn sóng, nước văng, rơm/bụi bay, khói nhang.
## Một bản đặt ở lớp mặt nước (MapView.add_ground) cho gợn sóng; một bản đặt trên cùng cho hạt bay.

const MAX_ITEMS: int = 160

var _rings: Array[Dictionary] = [] # {pos, age, life, radius, color}
var _bits: Array[Dictionary] = []  # {pos, vel, age, life, color, size, gravity, drag}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Vòng gợn sóng dẹt (nhìn từ trên xuống) loang ra rồi mờ dần.
func ripple(pos: Vector2, radius: float = 8.0, life: float = 0.9, color: Color = Color(0.88, 0.97, 1.0, 0.8)) -> void:
	if _rings.size() >= MAX_ITEMS:
		_rings.remove_at(0)
	_rings.append({"pos": pos, "age": 0.0, "life": life, "radius": radius, "color": color})


## Nước văng: vài giọt bắn lên rồi rơi xuống + gợn sóng.
func splash(pos: Vector2, count: int = 8) -> void:
	burst(pos, Color(0.9, 0.97, 1.0), count, 34.0, 120.0, 0.55, 26.0)


## Hạt bắn tung toé quanh pos. up: vận tốc hướng lên cộng thêm.
func burst(pos: Vector2, color: Color, count: int, speed: float, gravity: float, life: float, up: float = 0.0) -> void:
	for i in range(count):
		var angle: float = randf() * TAU
		var vel := Vector2(cos(angle), sin(angle) * 0.6) * speed * randf_range(0.4, 1.0) + Vector2(0, -up)
		_add_bit({"pos": pos, "vel": vel, "age": 0.0, "life": life * randf_range(0.7, 1.1), "color": color,
			"size": 1.0 if randf() < 0.6 else 2.0, "gravity": gravity, "drag": 0.0})


## Khói nhang: các cụm khói nhạt bay lên, lắc nhẹ.
func smoke(pos: Vector2, count: int = 6) -> void:
	for i in range(count):
		_add_bit({"pos": pos + Vector2(randf_range(-2, 2), randf_range(-1, 1)),
			"vel": Vector2(randf_range(-4, 4), randf_range(-16, -9)), "age": -float(i) * 0.18,
			"life": 1.6, "color": Color(0.92, 0.92, 0.9, 0.7), "size": 2.0, "gravity": 0.0, "drag": 0.6})


func clear() -> void:
	_rings.clear()
	_bits.clear()
	queue_redraw()


func is_idle() -> bool:
	return _rings.is_empty() and _bits.is_empty()


func _add_bit(bit: Dictionary) -> void:
	if _bits.size() >= MAX_ITEMS:
		_bits.remove_at(0)
	_bits.append(bit)


func _process(delta: float) -> void:
	if is_idle():
		return
	for ring in _rings:
		ring["age"] = float(ring["age"]) + delta
	_rings = _rings.filter(func(r: Dictionary) -> bool: return float(r["age"]) < float(r["life"]))
	for bit in _bits:
		bit["age"] = float(bit["age"]) + delta
		if float(bit["age"]) < 0.0:
			continue
		var vel: Vector2 = bit["vel"]
		vel.y += float(bit["gravity"]) * delta
		vel *= 1.0 - float(bit["drag"]) * delta
		bit["vel"] = vel
		bit["pos"] = (bit["pos"] as Vector2) + vel * delta
	_bits = _bits.filter(func(b: Dictionary) -> bool: return float(b["age"]) < float(b["life"]))
	queue_redraw()


func _draw() -> void:
	for ring in _rings:
		var t: float = float(ring["age"]) / float(ring["life"])
		var radius: float = 2.0 + float(ring["radius"]) * t
		var color: Color = ring["color"]
		color.a *= 1.0 - t
		var center: Vector2 = ring["pos"]
		var points := PackedVector2Array()
		for i in range(17):
			var angle: float = TAU * float(i) / 16.0
			points.append((center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.45)).round())
		draw_polyline(points, color, 1.0)
	for bit in _bits:
		if float(bit["age"]) < 0.0:
			continue
		var t: float = float(bit["age"]) / float(bit["life"])
		var color: Color = bit["color"]
		color.a *= 1.0 - t * t
		var size: float = float(bit["size"]) + (1.0 if float(bit["drag"]) > 0.0 and t > 0.4 else 0.0)
		draw_rect(Rect2((bit["pos"] as Vector2).round(), Vector2(size, size)), color)
