class_name BattleFx
extends Node2D

## Hiệu ứng thị giác trong trận: tia trúng đòn, khiên đỡ, lông bay, bụi, vòng sóng va chạm.
## Không tham gia logic trận (GDD 4.11: hiệu ứng lông bay chỉ là hình ảnh).

## Tốc độ hiệu ứng (quay chậm khi K.O.; chỉ hình ảnh).
var time_scale: float = 1.0:
	set(value):
		time_scale = value
		for child in get_children():
			if child is CPUParticles2D:
				(child as CPUParticles2D).speed_scale = value
var _bursts: Array[Dictionary] = []
var _feather_texture: Texture2D
var _dust_texture: Texture2D


func _ready() -> void:
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_feather_texture = _pixel_texture(PackedStringArray([
		"..##", ".###", "###.", "##..",
	]))
	_dust_texture = _pixel_texture(PackedStringArray([
		".##.", "####", "####", ".##.",
	]))


func _pixel_texture(rows: PackedStringArray) -> Texture2D:
	var image := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in range(rows.size()):
		for x in range(rows[y].length()):
			image.set_pixel(x, y, Color.WHITE if rows[y][x] == "#" else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


## kind: 0 light, 1 heavy, 2 special, 3 block, 4 clash.
## scale: to theo sát thương (tia lớn hơn, nhiều lông hơn ở đòn nặng).
func hit_spark(pos: Vector2, kind: int, direction: int, scale: float = 1.0) -> void:
	var colors: Array[Color] = [Color(1.0, 0.95, 0.6), Color(1.0, 0.7, 0.25), Color(1.0, 0.95, 0.35),
		Color(0.55, 0.8, 1.0), Color(1.0, 1.0, 1.0)]
	var sizes: Array[float] = [34.0, 54.0, 86.0, 40.0, 70.0]
	var lives: Array[float] = [0.16, 0.22, 0.34, 0.16, 0.28]
	_bursts.append({"pos": pos, "kind": kind, "dir": direction, "t": 0.0, "life": lives[kind] * (0.8 + 0.2 * scale),
		"size": sizes[kind] * scale, "color": colors[kind], "seed": randi()})
	if kind <= 2:
		feathers(pos, int(float(5 + kind * 6) * scale), direction)
	if kind == 2 and scale > 1.4:
		feathers(pos + Vector2(0, -30), 10, -direction)


func feathers(pos: Vector2, amount: int, direction: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = _feather_texture
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.position = pos
	p.direction = Vector2(float(direction), -0.8)
	p.spread = 70.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 520)
	p.damping_min = 80.0
	p.damping_max = 140.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.25, 0.1))
	ramp.set_color(1, Color(0.15, 0.2, 0.22, 0.0))
	ramp.add_point(0.4, Color(0.95, 0.6, 0.2))
	p.color_ramp = ramp
	add_child(p)
	p.speed_scale = time_scale
	p.emitting = true
	get_tree().create_timer(1.2 / maxf(time_scale, 0.1)).timeout.connect(p.queue_free)


## Sóng chấn lớn (Địa Chấn, Thái Sơn Áp Đỉnh): vòng sóng dẹt trên mặt đất, nứt đất, đá văng, bụi.
func quake(pos: Vector2, radius: float) -> void:
	_bursts.append({"pos": pos, "kind": 5, "dir": 1, "t": 0.0, "life": 0.9, "size": radius,
		"color": Color(1.0, 0.85, 0.5), "seed": randi()})
	dust(pos + Vector2(-radius * 0.4, 0), 10, -1.0)
	dust(pos + Vector2(radius * 0.4, 0), 10, 1.0)
	dust(pos, 14)
	rocks(pos, 8 + int(radius / 60.0))


## Sóng chấn ngắn phía trước (Dậm Chân).
func shock(pos: Vector2, width: float, direction: int) -> void:
	_bursts.append({"pos": pos, "kind": 6, "dir": direction, "t": 0.0, "life": 0.35, "size": width,
		"color": Color(1.0, 0.9, 0.6), "seed": randi()})
	dust(pos, 8, float(direction))


func rocks(pos: Vector2, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = _dust_texture
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 0.95
	p.position = pos
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 380.0
	p.gravity = Vector2(0, 1100)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	p.color = Color(0.45, 0.36, 0.26)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func dust(pos: Vector2, amount: int = 8, spread_x: float = 1.0) -> void:
	var p := CPUParticles2D.new()
	p.texture = _dust_texture
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.position = pos
	p.direction = Vector2(spread_x, -0.4)
	p.spread = 80.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 130.0
	p.gravity = Vector2(0, 80)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.75, 0.55, 0.85))
	ramp.set_color(1, Color(0.85, 0.75, 0.55, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func _process(delta: float) -> void:
	for i in range(_bursts.size() - 1, -1, -1):
		_bursts[i]["t"] += delta * time_scale
		if _bursts[i]["t"] >= _bursts[i]["life"]:
			_bursts.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for b in _bursts:
		var k: float = float(b["t"]) / float(b["life"])
		var pos: Vector2 = b["pos"]
		var size: float = float(b["size"])
		var color: Color = b["color"]
		var kind: int = int(b["kind"])
		var rng := RandomNumberGenerator.new()
		rng.seed = int(b["seed"])
		var fade := Color(color.r, color.g, color.b, 1.0 - k)
		if kind == 5:
			# Vòng sóng dẹt + vết nứt hình răng cưa tỏa hai phía.
			var r: float = size * (0.15 + 0.85 * sqrt(k))
			var ring := PackedVector2Array()
			for i in range(33):
				var a: float = TAU * float(i) / 32.0
				ring.append(pos + Vector2(cos(a) * r, sin(a) * r * 0.12 - 4.0))
			draw_polyline(ring, Color(1.0, 0.95, 0.75, 0.9 * (1.0 - k)), 6.0 * (1.0 - k) + 1.5)
			for side in [-1.0, 1.0]:
				for c in range(3):
					var p := pos + Vector2(0, -2)
					var line := PackedVector2Array([p])
					var length: float = minf(size, 260.0) * (0.45 + 0.25 * float(c)) * minf(1.0, k * 4.0)
					var segs: int = 7
					for seg in range(segs):
						p += Vector2(side * length / float(segs), rng.randf_range(-3, 3) + float(c - 1) * 1.5)
						line.append(p)
					draw_polyline(line, Color(0.22, 0.14, 0.08, 0.85 * (1.0 - k * k)), 3.0)
			continue
		if kind == 6:
			var w: float = size * (0.4 + 0.8 * k)
			var arc := PackedVector2Array()
			for i in range(17):
				var a: float = PI + PI * float(i) / 16.0
				arc.append(pos + Vector2(cos(a) * w * 0.5 + float(b["dir"]) * w * 0.25, sin(a) * 26.0 * (1.0 - k) - 2.0))
			draw_polyline(arc, Color(1.0, 0.95, 0.7, 0.85 * (1.0 - k)), 4.0)
			continue
		if kind == 3:
			# Khiên đỡ: lục giác xanh.
			var hexagon := PackedVector2Array()
			for i in range(7):
				var a: float = TAU * float(i) / 6.0 + PI / 6.0
				hexagon.append(pos + Vector2(cos(a), sin(a)) * size * (0.7 + 0.5 * k))
			draw_polyline(hexagon, fade, 5.0)
			continue
		# Vòng sóng.
		draw_arc(pos, size * (0.3 + 1.1 * k), 0.0, TAU, 24, Color(1, 1, 1, 0.8 * (1.0 - k)), 4.0 * (1.0 - k) + 1.0)
		# Tia sáng nhọn.
		var rays: int = 8 + kind * 4
		for i in range(rays):
			var a: float = TAU * float(i) / float(rays) + rng.randf_range(-0.2, 0.2)
			var length: float = size * rng.randf_range(0.6, 1.25) * (0.5 + k)
			var inner: float = size * 0.25 * k
			var dir := Vector2(cos(a), sin(a))
			var side := Vector2(-dir.y, dir.x) * 4.0 * (1.0 - k)
			draw_colored_polygon(PackedVector2Array([
				pos + dir * inner + side, pos + dir * length, pos + dir * inner - side]), fade)
		if k < 0.35:
			draw_circle(pos, size * 0.35 * (1.0 - k * 2.0), Color(1, 1, 1, 0.95))
		if kind == 2:
			for bolt in range(5):
				var p := pos
				var line := PackedVector2Array([p])
				for seg in range(5):
					p += Vector2(rng.randf_range(-26, 26), rng.randf_range(-26, 26))
					line.append(p)
				draw_polyline(line, Color(0.6, 0.85, 1.0, 1.0 - k), 3.0)
