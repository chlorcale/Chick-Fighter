extends Node2D

## Nền parallax của màn tẩu thoát, vẽ hết trong _draw theo vị trí camera (cách của race_backdrop.gd):
## stage 1 – hẻm sau xóm + vườn cây trái lúc xế chiều: trời, rặng cây xa, hàng dừa xa, nhà lá/nhà vườn, xoài, mít,
##           tre, chuối, khói bếp, bờ rào + bụi cây, gà mái, con đường đất (hero chạy trên GROUND_Y);
## stage 2 – kinh rạch lúc hoàng hôn: rặng cây xa, bờ bên kia (dừa, dừa nước, nhà, ông câu cá, trâu), mặt nước
##           gợn sóng lấp lánh, ghe du lịch chạy xa.
## Mỗi lớp một hệ số parallax f: vật ở toạ độ lớp u hiện ở x = u + cam_left·(1 − f). Nội dung chọn bằng hash của
## chỉ số ô nên ổn định, không tạo node. Ảnh cắt từ bản đồ (EscapeArt.prop); thiếu ảnh thì bỏ qua vật đó.
## front = true: lớp sát ống kính (cỏ, lá dừa nước) vẽ đè lên nhân vật.

const Art := preload("res://game/escape/escape_art.gd")

const GROUND_Y: float = 192.0
const PATH_TOP: float = 182.0
const PATH_BOTTOM: float = 206.0
const WATER_TOP: float = 128.0
const BANK_TOP: float = 112.0

var stage: int = 1
var front: bool = false
var cam_left: float = 0.0
var view_w: float = 427.0
var view_top: float = 0.0
var view_h: float = 240.0
var time: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if front:
		_draw_front()
		return
	if stage == 1:
		_draw_sky(false)
		_draw_far(84.0, Color(0.42, 0.5, 0.46))
		_band(94.0, 160.0, Color(0.47, 0.58, 0.4))
		_band(94.0, 96.0, Color(0.4, 0.5, 0.36))
		_draw_far_palms(112.0, 0.25, Color(0.6, 0.66, 0.66))
		_draw_village()
		_draw_hedge()
		_draw_path()
	else:
		_draw_sky(true)
		_draw_far(92.0, Color(0.36, 0.38, 0.42))
		_band(102.0, BANK_TOP, Color(0.34, 0.42, 0.32))
		_draw_far_palms(104.0, 0.18, Color(0.5, 0.5, 0.58))
		_draw_far_bank()
		_draw_water()


# ------------------------------------------------------------------ tiện ích

func _lx(u: float, f: float) -> float:
	return roundf(u + cam_left * (1.0 - f))


func _tiles(f: float, tile: float, margin: float) -> Vector2i:
	var u0: float = cam_left * f - margin
	var u1: float = cam_left * f + view_w + margin
	return Vector2i(floori(u0 / tile), floori(u1 / tile))


func _band(y0: float, y1: float, color: Color) -> void:
	draw_rect(Rect2(floorf(cam_left) - 2.0, y0, view_w + 6.0, y1 - y0), color)


func _prop(prop_name: String, foot: Vector2, frame: int = 0, flip: bool = false, tint: Color = Color.WHITE) -> void:
	Art.stand(self, Art.prop(prop_name, frame), foot, flip, tint)


# ------------------------------------------------------------------ trời, rặng cây

func _draw_sky(sunset: bool) -> void:
	var top: float = minf(view_top, 0.0) - 20.0
	var stops: Array = [
		[-600.0, Color(0.36, 0.5, 0.78)], [20.0, Color(0.5, 0.62, 0.85)], [40.0, Color(0.72, 0.74, 0.84)],
		[56.0, Color(0.93, 0.8, 0.7)], [70.0, Color(0.98, 0.84, 0.62)],
	]
	if sunset:
		stops = [
			[-600.0, Color(0.27, 0.3, 0.55)], [18.0, Color(0.45, 0.4, 0.62)], [36.0, Color(0.78, 0.52, 0.55)],
			[54.0, Color(0.96, 0.62, 0.42)], [72.0, Color(1.0, 0.76, 0.42)],
		]
	for k in range(stops.size()):
		var y0: float = maxf(float(stops[k][0]), top)
		var y1: float = float(stops[k + 1][0]) if k + 1 < stops.size() else 100.0
		_band(y0, y1, stops[k][1])
	var sun := Vector2(roundf(cam_left + view_w * (0.78 if not sunset else 0.62)), 44.0 if not sunset else 70.0)
	draw_circle(sun, 18.0, Color(1.0, 0.9, 0.65, 0.22))
	draw_circle(sun, 12.0, Color(1.0, 0.88, 0.6, 0.45))
	draw_circle(sun, 9.0, Color(1.0, 0.86, 0.55) if not sunset else Color(1.0, 0.62, 0.32))
	var f: float = 0.05
	var drift: float = time * 3.0
	var r: Vector2i = _tiles(f, 150.0, 220.0)
	for i in range(r.x, r.y + 1):
		var h: int = Art.hash_i(i, 11 + stage)
		if h % 3 == 0:
			continue
		var x: float = _lx(float(i) * 150.0 + float(h % 70) - drift, f)
		var y: float = 8.0 + float((h >> 5) % 28)
		var w: float = 26.0 + float((h >> 9) % 30)
		var c := Color(1.0, 0.95, 0.9, 0.8) if not sunset else Color(1.0, 0.78, 0.7, 0.75)
		draw_rect(Rect2(x, y + 4.0, w, 5.0), c)
		draw_rect(Rect2(x + 5.0, y, w * 0.45, 5.0), c)
		draw_rect(Rect2(x + w * 0.45, y + 1.0, w * 0.35, 4.0), c)
		draw_rect(Rect2(x + 2.0, y + 8.0, w - 2.0, 2.0), Color(0.85, 0.75, 0.82, 0.7))


func _draw_far(horizon: float, base: Color) -> void:
	var f: float = 0.1
	_band(horizon - 4.0, horizon + 12.0, base)
	var r: Vector2i = _tiles(f, 22.0, 30.0)
	for i in range(r.x, r.y + 1):
		var h: int = Art.hash_i(i, 23)
		var x: float = _lx(float(i) * 22.0 + float(h % 9), f)
		var bump: float = 6.0 + float((h >> 4) % 9)
		draw_rect(Rect2(x - 7.0, horizon - bump, 16.0, bump), base)
		draw_rect(Rect2(x - 3.0, horizon - bump - 3.0, 9.0, 3.0), base)
		if (h >> 9) % 3 == 0:
			# Dừa xa: thân mảnh + tán.
			var height: float = 12.0 + float((h >> 11) % 8)
			var top := Vector2(x + 2.0, horizon - bump - height)
			draw_line(Vector2(x + 1.0, horizon - bump), top, base, 1.0)
			draw_rect(Rect2(top.x - 4.0, top.y, 9.0, 2.0), base)
			draw_rect(Rect2(top.x - 6.0, top.y + 2.0, 4.0, 1.0), base)
			draw_rect(Rect2(top.x + 3.0, top.y + 2.0, 4.0, 1.0), base)


func _draw_far_palms(foot: float, f: float, tint: Color) -> void:
	var tile: float = 120.0
	var r: Vector2i = _tiles(f, tile, 120.0)
	for i in range(r.x, r.y + 1):
		var h: int = Art.hash_i(i, 29 + stage)
		if h % 3 == 0:
			continue
		var x: float = _lx(float(i) * tile + float(h % 60), f)
		var kind: String = ["coconut_a", "coconut_b", "coconut_c"][(h >> 4) % 3]
		_prop(kind, Vector2(x, foot), int(time * 1.4 + float(h % 7)) % 4, (h >> 7) % 2 == 0, tint)


# ------------------------------------------------------------------ stage 1: xóm + vườn

func _draw_village() -> void:
	var f: float = 0.55
	var foot: float = 156.0
	_band(foot - 6.0, 176.0, Color(0.4, 0.56, 0.3))
	var tile: float = 190.0
	var r: Vector2i = _tiles(f, tile, 200.0)
	for i in range(r.x, r.y + 1):
		var h: int = Art.hash_i(i, 53)
		var x: float = _lx(float(i) * tile, f)
		var sway: int = int(time * 2.0 + float(h % 11)) % 4
		match h % 7:
			0, 1:
				var wall: String = "house_thatch" if (h >> 4) % 2 == 0 else "house_garden"
				_house(x + 95.0, foot, wall, wall == "house_thatch")
				_prop("smoke", Vector2(x + 95.0 + float((h >> 8) % 40) - 20.0, foot - 56.0), int(time * 10.0) % 8)
			2:
				_prop("mango", Vector2(x + 60.0, foot + 2.0), int(time * 1.5) % 2)
				_prop("jackfruit", Vector2(x + 140.0, foot + 2.0), int(time * 1.3 + 1.0) % 2)
			3:
				_prop("bamboo", Vector2(x + 70.0, foot + 2.0), sway % 3)
				_prop("banana", Vector2(x + 150.0, foot + 1.0), sway)
			4:
				_prop("jackfruit", Vector2(x + 50.0, foot + 2.0), int(time * 1.3) % 2)
				_prop("banana_b", Vector2(x + 120.0, foot + 1.0), sway)
				_prop("coconut_a", Vector2(x + 170.0, foot + 2.0), sway)
			5:
				_prop("coconut_b", Vector2(x + 40.0, foot + 2.0), sway)
				_prop("mango", Vector2(x + 120.0, foot + 2.0), int(time * 1.5 + 1.0) % 2)
			_:
				_prop("banana", Vector2(x + 40.0, foot + 1.0), sway)
				_prop("bamboo", Vector2(x + 120.0, foot + 2.0), (sway + 1) % 3)


func _house(cx: float, foot: float, wall_name: String, thatch: bool) -> void:
	var wall: Texture2D = Art.prop(wall_name)
	var w: float = 140.0 if wall == null else wall.get_width()
	var h: float = 40.0 if wall == null else wall.get_height()
	var left: float = roundf(cx - w * 0.5)
	var top: float = foot - h
	if wall != null:
		draw_texture(wall, Vector2(left, top))
	else:
		draw_rect(Rect2(left, top, w, h), Color(0.7, 0.6, 0.45))
	var roof_h: float = 18.0
	var base: Color = Color(0.62, 0.48, 0.28) if thatch else Color(0.66, 0.3, 0.22)
	draw_colored_polygon(PackedVector2Array([Vector2(left - 7.0, top + 2.0), Vector2(left + w + 7.0, top + 2.0),
		Vector2(left + w - 12.0, top - roof_h), Vector2(left + 12.0, top - roof_h)]), base)
	var line_c := base.darkened(0.25)
	for k in range(1, 5):
		var y: float = top + 2.0 - float(k) * 4.0
		var inset: float = float(k) * 4.0
		draw_rect(Rect2(left - 7.0 + inset, y, w + 14.0 - 2.0 * inset, 1.0), line_c)
	draw_rect(Rect2(left + 12.0, top - roof_h - 1.0, w - 24.0, 2.0), base.lightened(0.2))
	draw_rect(Rect2(left - 7.0, top + 2.0, w + 14.0, 1.0), line_c.darkened(0.3))


func _draw_hedge() -> void:
	var f: float = 0.8
	var foot: float = 178.0
	_band(176.0, PATH_TOP, Color(0.36, 0.55, 0.25))
	var tile: float = 64.0
	var r: Vector2i = _tiles(f, tile, 80.0)
	for i in range(r.x, r.y + 1):
		var h: int = Art.hash_i(i, 61)
		var x: float = _lx(float(i) * tile + float(h % 24), f)
		var tint := Color(0.78, 0.82, 0.78)
		match h % 6:
			0, 1, 2:
				_prop("bush", Vector2(x, foot + 1.0), 0, (h >> 4) % 2 == 0, tint)
			3:
				_prop("hens", Vector2(x, foot), int(time * 5.0 + float(h % 4)) % 4, (h >> 5) % 2 == 0, tint)
			4:
				_prop("jar_b", Vector2(x, foot), 0, false, tint)
			_:
				pass


func _draw_path() -> void:
	_band(PATH_TOP, PATH_BOTTOM, Color(0.7, 0.56, 0.4))
	_band(PATH_TOP, PATH_TOP + 1.0, Color(0.5, 0.4, 0.28))
	_band(PATH_TOP + 1.0, PATH_TOP + 3.0, Color(0.6, 0.48, 0.34))
	_band(PATH_BOTTOM - 2.0, PATH_BOTTOM, Color(0.6, 0.47, 0.33))
	_band(PATH_BOTTOM, view_top + view_h + 40.0, Color(0.38, 0.58, 0.25))
	_band(PATH_BOTTOM, PATH_BOTTOM + 2.0, Color(0.3, 0.46, 0.2))
	var r: Vector2i = _tiles(1.0, 32.0, 10.0)
	for i in range(r.x, r.y + 1):
		var h: int = Art.hash_i(i, 67)
		var x: float = float(i) * 32.0
		var y: float = PATH_TOP + 4.0 + float(h % 18)
		draw_rect(Rect2(x + float((h >> 5) % 24), y, 2.0, 1.0), Color(0.55, 0.43, 0.3))
		draw_rect(Rect2(x + float((h >> 9) % 28), PATH_TOP + 5.0 + float((h >> 13) % 16), 1.0, 1.0), Color(0.82, 0.7, 0.52))
		if (h >> 17) % 4 == 0:
			draw_rect(Rect2(x + float((h >> 19) % 20), PATH_TOP + 8.0 + float((h >> 21) % 10), 3.0, 2.0), Color(0.6, 0.58, 0.55))
		var g := Color(0.28, 0.46, 0.18)
		draw_rect(Rect2(x + float((h >> 7) % 30), PATH_BOTTOM + 4.0 + float((h >> 20) % 8), 1.0, 2.0), g)
		draw_rect(Rect2(x + float((h >> 23) % 30), PATH_BOTTOM + 10.0 + float((h >> 11) % 12), 1.0, 3.0), g)


# ------------------------------------------------------------------ stage 2: bờ bên kia + mặt nước

func _draw_far_bank() -> void:
	var f: float = 0.4
	var haze := Color(0.78, 0.74, 0.86)
	_band(BANK_TOP - 6.0, WATER_TOP, Color(0.36, 0.48, 0.28))
	var tile: float = 170.0
	var r: Vector2i = _tiles(f, tile, 200.0)
	for i in range(r.x, r.y + 1):
		var h: int = Art.hash_i(i, 73)
		var x: float = _lx(float(i) * tile, f)
		var sway: int = int(time * 2.0 + float(h % 9)) % 4
		match h % 6:
			0:
				_house(x + 85.0, BANK_TOP + 4.0, "house_thatch", true)
			1:
				_prop("nipa", Vector2(x + 40.0, BANK_TOP + 8.0), sway, false, haze)
				_prop("fisher", Vector2(x + 110.0, BANK_TOP + 6.0), int(time * 1.2) % 2, false, haze)
			2:
				_prop("coconut_c", Vector2(x + 60.0, BANK_TOP + 6.0), sway, false, haze)
				_prop("nipa_b", Vector2(x + 130.0, BANK_TOP + 8.0), sway, false, haze)
			3:
				_prop("buffalo", Vector2(x + 70.0, BANK_TOP + 6.0), int(time * 1.0) % 2, (h >> 6) % 2 == 0, haze)
				_prop("banana", Vector2(x + 140.0, BANK_TOP + 6.0), sway, false, haze)
			4:
				_prop("sign_ferry", Vector2(x + 60.0, BANK_TOP + 6.0), 0, false, haze)
				_prop("coconut_a", Vector2(x + 120.0, BANK_TOP + 6.0), sway, false, haze)
			_:
				_prop("nipa", Vector2(x + 50.0, BANK_TOP + 8.0), sway, false, haze)
				_prop("nipa_b", Vector2(x + 100.0, BANK_TOP + 8.0), (sway + 2) % 4, false, haze)
	# Mép bờ bùn + cỏ lác.
	_band(WATER_TOP - 5.0, WATER_TOP, Color(0.46, 0.38, 0.26))
	_band(WATER_TOP - 6.0, WATER_TOP - 5.0, Color(0.3, 0.42, 0.22))
	var r2: Vector2i = _tiles(1.0, 18.0, 10.0)
	for i in range(r2.x, r2.y + 1):
		var h: int = Art.hash_i(i, 79)
		var x: float = float(i) * 18.0 + float(h % 12)
		draw_rect(Rect2(x, WATER_TOP - 9.0 - float(h % 4), 1.0, 5.0 + float(h % 4)), Color(0.3, 0.48, 0.2))


func _draw_water() -> void:
	var bottom: float = view_top + view_h + 40.0
	_band(WATER_TOP, WATER_TOP + 10.0, Color(0.42, 0.5, 0.52))
	_band(WATER_TOP + 10.0, WATER_TOP + 34.0, Color(0.44, 0.55, 0.55))
	_band(WATER_TOP + 34.0, WATER_TOP + 70.0, Color(0.4, 0.52, 0.5))
	_band(WATER_TOP + 70.0, bottom, Color(0.36, 0.48, 0.46))
	_band(WATER_TOP, WATER_TOP + 1.0, Color(0.32, 0.38, 0.36))
	# Phản chiếu nắng chiều (dải sáng dưới mặt trời).
	var sx: float = roundf(cam_left + view_w * 0.62)
	for k in range(10):
		var y: float = WATER_TOP + 2.0 + float(k) * 5.0
		var w: float = 6.0 + float(k) * 2.0 + roundf(sin(time * 3.0 + float(k)) * 2.0)
		draw_rect(Rect2(sx - w * 0.5, y, w, 1.0), Color(1.0, 0.75, 0.45, 0.5 - float(k) * 0.04))
	# Gợn sóng: xa trôi chậm, gần trôi nhanh hơn (dòng chảy sang trái).
	for layer in [[0.6, WATER_TOP + 4.0, 26.0, 3.0], [1.0, WATER_TOP + 20.0, 120.0, 6.0]]:
		var lf: float = float(layer[0])
		var y0: float = float(layer[1])
		var span: float = float(layer[2])
		var flow: float = fmod(time * float(layer[3]), 18.0)
		var rr: Vector2i = _tiles(lf, 18.0, 20.0)
		for i in range(rr.x, rr.y + 1):
			var h: int = Art.hash_i(i, 89 + int(lf * 10.0))
			var x: float = _lx(float(i) * 18.0 + float(h % 12) - flow, lf)
			var y: float = y0 + float((h >> 4) % int(span))
			var a: float = 0.3 + 0.25 * sin(time * 2.0 + float(h % 50))
			draw_rect(Rect2(x, y, 3.0 + float((h >> 9) % 5), 1.0), Color(0.85, 0.93, 0.95, a))


# ------------------------------------------------------------------ lớp trước

func _draw_front() -> void:
	var f: float = 1.25
	var r: Vector2i = _tiles(f, 72.0, 60.0)
	var bottom: float = view_top + view_h + 2.0
	for i in range(r.x, r.y + 1):
		var h: int = Art.hash_i(i, 97 + stage)
		if h % 3 != 0:
			continue
		var x: float = _lx(float(i) * 72.0 + float(h % 40), f)
		if stage == 1:
			var c := Color(0.22, 0.42, 0.15)
			var c2 := Color(0.32, 0.55, 0.22)
			for k in range(6):
				var bx: float = x + float(k) * 3.0 - 8.0
				var bh: float = 6.0 + float((h >> (k * 3)) % 8)
				draw_rect(Rect2(bx, bottom - bh, 2.0, bh), c if k % 2 == 0 else c2)
		else:
			# Lục bình trôi sát ống kính + cỏ lác mép bờ gần.
			if (h >> 4) % 2 == 0:
				_prop(["hyacinth_a", "hyacinth_b", "hyacinth_c"][(h >> 6) % 3], Vector2(x, bottom - 2.0), int(time * 2.0) % 2)
			else:
				for k in range(5):
					var bx: float = x + float(k) * 3.0 - 6.0
					var bh: float = 8.0 + float((h >> (k * 3)) % 9)
					draw_rect(Rect2(bx, bottom - bh, 1.0, bh), Color(0.28, 0.45, 0.2))
