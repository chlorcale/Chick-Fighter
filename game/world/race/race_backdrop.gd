extends Node2D

## Nền parallax của màn đua xe đường quê, vẽ hết trong _draw theo vị trí camera:
## trời + nắng + mây, rặng dừa xa, sông có xuồng, ruộng lúa (trâu, bù nhìn), hàng dừa/chuối/dừa nước/nhà lá/tiệm
## tạp hóa, cột điện + dây, đường bê tông ba làn (vạch làn, cột cây số, vạch xuất phát, vạch đích ca-rô), cổng ấp.
## Mỗi lớp một hệ số parallax f: vật ở toạ độ lớp u hiện ở x = u + cam_left·(1 − f). Lớp lặp vô hạn theo ô;
## nội dung mỗi ô chọn bằng hash của chỉ số ô nên ổn định, không tạo node. Toạ độ luôn làm tròn (pixel art).
## Ảnh dùng lại từ bản đồ (MapView.node_textures) qua "tex"; thiếu ảnh nào thì bỏ qua vật đó.
## front = true: lớp sát ống kính (bụi cỏ phía trước, khán giả hàng trước) vẽ đè lên xe.
## Bản Stardew hơn: đoạn chợ nổi trên sông (ghe chở trái cây, cây bẹo treo hàng) ở giữa đường đua, cầu vòm qua sông ở
## lớp xa, đoạn đường bê tông vượt kênh (lan can, nước bên dưới), nhà có dây phơi đồ bay phấp phới, cò trắng bay, vạch
## kẻ đường (vạch lề liền, mũi tên, vạch qua đường), cổng xuất phát + người phất cờ, cổng đích vòm bong bóng; sunset =
## true: trời hoàng hôn cam tím, mặt trời thấp, nước ánh cam.

const HORIZON: float = 74.0
const RIVER_BOTTOM: float = 98.0
const MID_GROUND: float = 132.0
const POLE_GROUND: float = 140.0
const ROAD_TOP: float = 142.0
const ROAD_BOTTOM: float = 206.0
const LANE_MARKS: Array[float] = [167.0, 186.0]
const SKY: Array = [
	[-600.0, Color(0.31, 0.56, 0.83)], [12.0, Color(0.39, 0.64, 0.87)], [28.0, Color(0.5, 0.72, 0.89)],
	[42.0, Color(0.62, 0.8, 0.9)], [55.0, Color(0.75, 0.86, 0.89)], [65.0, Color(0.87, 0.9, 0.8)],
]
## Dừa: [thân, tán, độ lệch góc trên-trái tán so với góc trên-trái thân] (đo trên bản đồ).
const COCONUTS: Array = [
	["D_dua_02_than", "D_dua_02_tan", Vector2(-35, -20)],
	["B_dua_04_than", "B_dua_04_tan", Vector2(-52, -18)],
	["C_dua_04_than", "C_dua_04_tan", Vector2(-33, -15)],
]
## Tên node bản đồ mà nền cần (race_game lấy ảnh qua MapView.node_textures).
const TEXTURE_NODES: Array[String] = [
	"D_dua_02_than", "D_dua_02_tan", "B_dua_04_than", "B_dua_04_tan", "C_dua_04_than", "C_dua_04_tan",
	"B_chuoi_01", "C_chuoi_02", "C_dua_nuoc_01", "B_dua_nuoc_02", "C_nha_la_tuong", "B_nha_vuon_1_tuong",
	"A_quan_tap_hoa_tuong", "C_cot_dien_01", "B_ga_nha_02",
]

var front: bool = false
var cam_left: float = 0.0
var view_w: float = 384.0
var view_top: float = 0.0
var view_h: float = 216.0
var time: float = 0.0
var track_len: float = 10800.0
var tex: Dictionary = {}              # tên node bản đồ → Array[Texture2D]
var crowd: Array[Texture2D] = []      # game/art/npc/crowd_*.png
var cheer: float = 0.0                # > 0: khán giả ở đích nhảy mừng
var sunset: bool = false              # bản hoàng hôn (race_game đặt theo giờ trong game)
## Đoạn chợ nổi (tỉ lệ quãng đường, theo mép trái camera) và các đoạn đường vượt kênh (toạ độ x đường đua, dài px).
const MARKET_SPAN: Vector2 = Vector2(0.34, 0.58)
const ROAD_BRIDGES: Array = [[2600.0, 260.0], [7900.0, 300.0]]
const SKY_SUNSET: Array = [
	[-600.0, Color(0.27, 0.22, 0.45)], [12.0, Color(0.42, 0.29, 0.52)], [28.0, Color(0.66, 0.38, 0.5)],
	[42.0, Color(0.88, 0.5, 0.42)], [55.0, Color(0.98, 0.66, 0.38)], [65.0, Color(1.0, 0.82, 0.5)],
]


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if front:
		_draw_front()
		return
	_draw_sky()
	_draw_far()
	_draw_river()
	_draw_far_bridges()
	_draw_fields()
	_draw_birds()
	_draw_mid()
	_draw_poles()
	_draw_road()
	_draw_road_bridges()
	_draw_start()
	_draw_gate()
	if sunset:
		# phủ ấm nhẹ toàn cảnh (mặt đường, cây) cho hợp ánh chiều
		draw_rect(Rect2(floorf(cam_left) - 2.0, view_top - 20.0, view_w + 6.0, view_h + 60.0), Color(1.0, 0.55, 0.25, 0.08))


# ------------------------------------------------------------------ tiện ích

static func hash_i(i: int, salt: int) -> int:
	var v: int = (i * 73856093) ^ (salt * 19349663) ^ 0x5bd1e995
	v = (v ^ (v >> 13)) * 1274126177
	v = v ^ (v >> 16)
	return absi(v) & 0x3fffffff


func _lx(u: float, f: float) -> float:
	return roundf(u + cam_left * (1.0 - f))


## Các chỉ số ô (độ rộng tile) đang thấy được ở lớp hệ số f (nới thêm margin px hai bên).
func _tiles(f: float, tile: float, margin: float) -> Vector2i:
	var u0: float = cam_left * f - margin
	var u1: float = cam_left * f + view_w + margin
	return Vector2i(floori(u0 / tile), floori(u1 / tile))


func _tex(node_name: String, frame: int = 0) -> Texture2D:
	var list: Array = tex.get(node_name, [])
	if list.is_empty():
		return null
	return list[frame % list.size()]


## Vẽ ảnh với chân (giữa-dưới) ở pos.
func _stand(t: Texture2D, foot: Vector2, flip: bool = false) -> void:
	if t == null:
		return
	var size: Vector2 = t.get_size()
	var top_left := Vector2(roundf(foot.x - size.x * 0.5), roundf(foot.y - size.y))
	if flip:
		draw_set_transform(top_left + Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		draw_texture(t, Vector2.ZERO)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture(t, top_left)


func _band(y0: float, y1: float, color: Color) -> void:
	draw_rect(Rect2(floorf(cam_left) - 2.0, y0, view_w + 6.0, y1 - y0), color)


# ------------------------------------------------------------------ trời, rặng cây xa, sông

func _draw_sky() -> void:
	var top: float = minf(view_top, 0.0) - 20.0
	var sky: Array = SKY_SUNSET if sunset else SKY
	for k in range(sky.size()):
		var y0: float = maxf(float(sky[k][0]), top)
		var y1: float = float(sky[k + 1][0]) if k + 1 < sky.size() else HORIZON
		_band(y0, y1, sky[k][1])
	# Nắng chiều: cố định trên màn hình (hoàng hôn: thấp, to, đỏ cam).
	if sunset:
		var sun_low := Vector2(roundf(cam_left + view_w * 0.72), HORIZON - 10.0)
		draw_circle(sun_low, 24.0, Color(1.0, 0.6, 0.3, 0.2))
		draw_circle(sun_low, 17.0, Color(1.0, 0.65, 0.35, 0.4))
		draw_circle(sun_low, 12.0, Color(1.0, 0.78, 0.45))
		for k in range(3):
			draw_rect(Rect2(sun_low.x - 14.0 + float(k) * 3.0, sun_low.y + 2.0 + float(k) * 3.0, 28.0 - float(k) * 6.0, 1.0), Color(0.95, 0.45, 0.35, 0.7))
	else:
		var sun := Vector2(roundf(cam_left + view_w * 0.8), 24.0)
		draw_circle(sun, 15.0, Color(1.0, 0.95, 0.75, 0.25))
		draw_circle(sun, 11.0, Color(1.0, 0.95, 0.72, 0.45))
		draw_circle(sun, 8.0, Color(1.0, 0.96, 0.78))
	# Mây trôi chậm.
	var f: float = 0.05
	var drift: float = time * 3.0
	var r: Vector2i = _tiles(f, 150.0, 220.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 11)
		if h % 3 == 0:
			continue
		var x: float = _lx(float(i) * 150.0 + float(h % 70) - drift, f)
		var y: float = 6.0 + float((h >> 5) % 30)
		var w: float = 26.0 + float((h >> 9) % 30)
		var c := Color(1.0, 0.86, 0.76, 0.85) if sunset else Color(1.0, 1.0, 1.0, 0.85)
		var c_low := Color(0.86, 0.52, 0.55, 0.85) if sunset else Color(0.82, 0.88, 0.95, 0.85)
		draw_rect(Rect2(x, y + 4.0, w, 5.0), c)
		draw_rect(Rect2(x + 5.0, y, w * 0.45, 5.0), c)
		draw_rect(Rect2(x + w * 0.45, y + 1.0, w * 0.35, 4.0), c)
		draw_rect(Rect2(x + 2.0, y + 8.0, w - 2.0, 2.0), c_low)


func _draw_far() -> void:
	var f: float = 0.12
	var base := Color(0.33, 0.48, 0.42)
	_band(HORIZON - 4.0, HORIZON + 1.0, base)
	var r: Vector2i = _tiles(f, 20.0, 30.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 23)
		var x: float = _lx(float(i) * 20.0 + float(h % 9), f)
		var kind: int = (h >> 4) % 4
		if kind == 0:
			draw_rect(Rect2(x - 5.0, HORIZON - 8.0, 12.0, 5.0), base)
			draw_rect(Rect2(x - 2.0, HORIZON - 10.0, 7.0, 3.0), base)
			continue
		var height: float = 9.0 + float((h >> 7) % 9)
		var lean: float = float((h >> 11) % 3) - 1.0
		var top := Vector2(x + lean, HORIZON - 3.0 - height)
		draw_line(Vector2(x, HORIZON - 3.0), top, base, 1.0)
		draw_rect(Rect2(top.x - 4.0, top.y, 9.0, 2.0), base)
		draw_rect(Rect2(top.x - 6.0, top.y + 2.0, 4.0, 1.0), base)
		draw_rect(Rect2(top.x + 3.0, top.y + 2.0, 4.0, 1.0), base)
		draw_rect(Rect2(top.x - 2.0, top.y - 1.0, 5.0, 1.0), base)


func _draw_river() -> void:
	var water := Color(0.62, 0.52, 0.55) if sunset else Color(0.45, 0.63, 0.66)
	_band(HORIZON + 1.0, RIVER_BOTTOM, water)
	_band(HORIZON + 1.0, HORIZON + 3.0, water.darkened(0.15))
	_band(RIVER_BOTTOM - 6.0, RIVER_BOTTOM, water.lightened(0.08))
	if sunset:
		# vệt nắng cam trên mặt sông
		var sx: float = roundf(cam_left + view_w * 0.72)
		for k in range(6):
			var w: float = 18.0 - float(k) * 2.0 + roundf(sin(time * 3.0 + float(k)) * 2.0)
			draw_rect(Rect2(sx - w * 0.5, HORIZON + 3.0 + float(k) * 3.0, w, 1.0), Color(1.0, 0.75, 0.4, 0.7))
	var f: float = 0.2
	# Ánh nước lấp lánh trôi theo dòng.
	var r: Vector2i = _tiles(f, 16.0, 20.0)
	var flow: float = fmod(time * 7.0, 16.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 31)
		var x: float = _lx(float(i) * 16.0 + float(h % 10) - flow, f)
		var y: float = HORIZON + 4.0 + float((h >> 4) % 18)
		var a: float = 0.35 + 0.3 * sin(time * 2.0 + float(h % 50))
		draw_rect(Rect2(x, y, 3.0 + float((h >> 9) % 4), 1.0), Color(0.86, 0.95, 0.97, a))
	# Xuồng ba lá, ghe có mui, chạy chậm trên sông.
	f = 0.22
	r = _tiles(f, 260.0, 80.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 37)
		if h % 3 == 0:
			continue
		var dirn: float = 1.0 if (h >> 3) % 2 == 0 else -1.0
		var x: float = _lx(float(i) * 260.0 + float(h % 120) + dirn * time * 6.0, f)
		var y: float = HORIZON + 10.0 + float((h >> 6) % 12)
		_draw_boat(x, y, (h >> 10) % 3 == 0, dirn)
	_draw_floating_market()


## Mức "chợ nổi" (0..1) theo vị trí camera trên đường đua.
func market_amount() -> float:
	var t: float = (cam_left + view_w * 0.5) / maxf(track_len, 1.0)
	var a: float = clampf((t - MARKET_SPAN.x) / 0.04, 0.0, 1.0)
	var b: float = clampf((MARKET_SPAN.y - t) / 0.04, 0.0, 1.0)
	return minf(a, b)


## Đoạn chợ nổi: ghe chở trái cây san sát, cây bẹo treo hàng, người bán đội nón lá.
func _draw_floating_market() -> void:
	if market_amount() <= 0.0:
		return
	var f: float = 0.24
	var tile: float = 58.0
	var r: Vector2i = _tiles(f, tile, 60.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 77)
		var cx: float = _lx(float(i) * tile + float(h % 20), f)
		var world_t: float = (cx + view_w * 0.0) / maxf(track_len, 1.0)
		if world_t < MARKET_SPAN.x - 0.05 or world_t > MARKET_SPAN.y + 0.05:
			continue
		var y: float = HORIZON + 9.0 + float((h >> 5) % 3) * 5.0
		var bob: float = roundf(sin(time * 1.6 + float(i)) * 0.6)
		_market_boat(cx, y + bob, h)


func _market_boat(x: float, y: float, h: int) -> void:
	var hull := Color(0.36, 0.24, 0.16)
	var w: float = 36.0
	draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.5 - 4.0, y - 4.0), Vector2(x + w * 0.5 + 4.0, y - 4.0),
		Vector2(x + w * 0.5, y), Vector2(x - w * 0.5, y)]), hull)
	draw_rect(Rect2(x - w * 0.5 - 3.0, y - 4.0, w + 6.0, 1.0), Color(0.62, 0.42, 0.24))
	# mắt ghe (đỏ trắng) ở mũi
	draw_rect(Rect2(x + w * 0.5 - 2.0, y - 3.0, 2.0, 1.0), Color(0.9, 0.2, 0.15))
	draw_rect(Rect2(x - w * 0.5 + 2.0, y + 1.0, w - 4.0, 1.0), Color(0.86, 0.95, 0.97, 0.35))
	# hàng trái cây chất đống
	var fruit: Array[Color] = [Color(0.2, 0.55, 0.2), Color(0.95, 0.75, 0.2), Color(0.9, 0.45, 0.15), Color(0.6, 0.2, 0.35)]
	var c: Color = fruit[h % fruit.size()]
	for k in range(6):
		var fx: float = x - 12.0 + float(k) * 4.0
		draw_rect(Rect2(fx, y - 7.0 - float(k % 2), 3.0, 3.0), c)
		draw_rect(Rect2(fx, y - 7.0 - float(k % 2), 1.0, 1.0), c.lightened(0.35))
	draw_rect(Rect2(x - 6.0, y - 10.0, 8.0, 3.0), fruit[(h >> 3) % fruit.size()])
	# cây bẹo: sào tre cao treo mẫu hàng
	var px: float = x + 8.0
	draw_rect(Rect2(px, y - 26.0, 1.0, 22.0), Color(0.62, 0.5, 0.3))
	var sway: float = roundf(sin(time * 2.0 + x * 0.1))
	draw_rect(Rect2(px - 1.0 + sway, y - 24.0, 3.0, 3.0), fruit[(h >> 5) % fruit.size()])
	draw_rect(Rect2(px - 1.0 + sway, y - 20.0, 3.0, 2.0), fruit[(h >> 7) % fruit.size()])
	_draw_hat_person(x - 12.0, y - 4.0, [Color(0.75, 0.25, 0.2), Color(0.25, 0.4, 0.7), Color(0.85, 0.8, 0.3)][(h >> 9) % 3])


## Cầu vòm bê tông bắc qua sông ở lớp xa (thưa, mỗi ~1100 px lớp).
func _draw_far_bridges() -> void:
	var f: float = 0.23
	var tile: float = 1100.0
	var r: Vector2i = _tiles(f, tile, 120.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 83)
		if h % 2 == 0:
			continue
		var x: float = _lx(float(i) * tile + 300.0 + float(h % 200), f)
		var span: float = 70.0
		var deck_y: float = HORIZON + 2.0
		var col := Color(0.82, 0.8, 0.74) if not sunset else Color(0.86, 0.7, 0.62)
		var dark := col.darkened(0.3)
		# vòm
		var pts := PackedVector2Array()
		for k in range(13):
			var t: float = float(k) / 12.0
			pts.append(Vector2(roundf(x - span * 0.5 + span * t), roundf(deck_y + 14.0 - sin(t * PI) * 10.0)))
		draw_polyline(pts, dark, 2.0)
		draw_rect(Rect2(x - span * 0.5 - 6.0, deck_y - 2.0, span + 12.0, 3.0), col)
		draw_rect(Rect2(x - span * 0.5 - 6.0, deck_y + 1.0, span + 12.0, 1.0), dark)
		for k in range(0, int(span) + 12, 6):
			draw_rect(Rect2(x - span * 0.5 - 6.0 + float(k), deck_y - 5.0, 1.0, 3.0), col)
		draw_rect(Rect2(x - span * 0.5 - 6.0, deck_y - 5.0, span + 12.0, 1.0), col)
		# người đi xe đạp qua cầu
		var bx: float = x - span * 0.5 + fmod(time * 9.0 + float(h % 50), span)
		draw_rect(Rect2(roundf(bx), deck_y - 5.0, 3.0, 3.0), Color(0.3, 0.3, 0.35))
		_draw_hat_person(roundf(bx) + 1.0, deck_y - 4.0, Color(0.9, 0.9, 0.85))


## Cò trắng bay chậm qua ruộng.
func _draw_birds() -> void:
	var f: float = 0.3
	var tile: float = 420.0
	var r: Vector2i = _tiles(f, tile, 60.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 89)
		if h % 3 != 0:
			continue
		for k in range(2 + h % 3):
			var x: float = _lx(float(i) * tile + float(k * 11) - time * 14.0, f)
			var y: float = RIVER_BOTTOM - 18.0 + float((h >> 4) % 10) + float(k % 2) * 4.0 + roundf(sin(time * 1.5 + float(k)) * 1.5)
			var flap: bool = int(time * 4.0 + float(k)) % 2 == 0
			var c := Color(0.98, 0.98, 0.95)
			draw_rect(Rect2(x, y, 3.0, 1.0), c)
			draw_rect(Rect2(x - 2.0, y - (1.0 if flap else -1.0), 2.0, 1.0), c)
			draw_rect(Rect2(x + 3.0, y - (1.0 if flap else -1.0), 2.0, 1.0), c)
			draw_rect(Rect2(x + 3.0, y, 1.0, 1.0), Color(0.95, 0.75, 0.3))


func _draw_boat(x: float, y: float, roofed: bool, dirn: float) -> void:
	var hull := Color(0.3, 0.2, 0.14)
	var w: float = 34.0 if roofed else 24.0
	var pts := PackedVector2Array([Vector2(x - w * 0.5 - 3.0, y - 3.0), Vector2(x + w * 0.5 + 3.0, y - 3.0),
		Vector2(x + w * 0.5, y), Vector2(x - w * 0.5, y)])
	draw_colored_polygon(pts, hull)
	draw_rect(Rect2(x - w * 0.5 - 2.0, y - 3.0, w + 4.0, 1.0), Color(0.55, 0.38, 0.22))
	draw_rect(Rect2(x - w * 0.5, y + 1.0, w, 1.0), Color(0.86, 0.95, 0.97, 0.4))
	if roofed:
		draw_rect(Rect2(x - 9.0, y - 9.0, 16.0, 6.0), Color(0.42, 0.3, 0.18))
		draw_rect(Rect2(x - 10.0, y - 10.0, 18.0, 2.0), Color(0.6, 0.46, 0.28))
		_draw_hat_person(x + dirn * -13.0, y - 3.0, Color(0.25, 0.4, 0.7))
	else:
		_draw_hat_person(x - dirn * 7.0, y - 3.0, Color(0.75, 0.25, 0.2))
		draw_line(Vector2(x - dirn * 7.0 + 2.0, y - 7.0), Vector2(x - dirn * 14.0, y + 1.0), Color(0.5, 0.36, 0.2), 1.0)


func _draw_hat_person(x: float, foot: float, shirt: Color) -> void:
	draw_rect(Rect2(x - 1.0, foot - 5.0, 3.0, 5.0), shirt)
	draw_rect(Rect2(x - 1.0, foot - 6.0, 3.0, 1.0), Color(0.85, 0.65, 0.5))
	draw_colored_polygon(PackedVector2Array([Vector2(x - 3.0, foot - 6.0), Vector2(x + 4.0, foot - 6.0),
		Vector2(x + 0.5, foot - 9.0)]), Color(0.95, 0.86, 0.55))


# ------------------------------------------------------------------ ruộng lúa

func _draw_fields() -> void:
	var f: float = 0.36
	var colors: Array[Color] = [Color(0.5, 0.7, 0.27), Color(0.62, 0.79, 0.34), Color(0.85, 0.74, 0.3), Color(0.43, 0.63, 0.25)]
	_band(RIVER_BOTTOM, MID_GROUND, colors[0])
	_band(RIVER_BOTTOM, RIVER_BOTTOM + 2.0, Color(0.32, 0.5, 0.25))
	var tile: float = 84.0
	var r: Vector2i = _tiles(f, tile, 20.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 41)
		var x: float = _lx(float(i) * tile, f)
		var c: Color = colors[h % colors.size()]
		draw_rect(Rect2(x, RIVER_BOTTOM + 2.0, tile, MID_GROUND - RIVER_BOTTOM - 2.0), c)
		var row := c.darkened(0.12)
		var y: float = RIVER_BOTTOM + 4.0 + float(h % 3)
		while y < MID_GROUND - 1.0:
			draw_rect(Rect2(x + float(int(y) % 4), y, tile - 4.0, 1.0), row)
			y += 3.0 + floorf((y - RIVER_BOTTOM) / 12.0)
		# Bờ ruộng xéo.
		draw_colored_polygon(PackedVector2Array([Vector2(x, RIVER_BOTTOM + 2.0), Vector2(x + 2.0, RIVER_BOTTOM + 2.0),
			Vector2(x - 4.0, MID_GROUND), Vector2(x - 7.0, MID_GROUND)]), Color(0.62, 0.55, 0.32))
	# Trâu, bù nhìn, người làm ruộng (thưa, vẽ nhỏ cho đúng tầm xa).
	tile = 200.0
	r = _tiles(f, tile, 40.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 43)
		var x: float = _lx(float(i) * tile + float(h % 120), f)
		var foot: float = RIVER_BOTTOM + 12.0 + float((h >> 4) % 14)
		match h % 5:
			0:
				_tiny_buffalo(x, foot, (h >> 5) % 2 == 0)
			1:
				_tiny_scarecrow(x, foot)
			2:
				_tiny_farmer(x, foot, int(time * 2.0 + float(h % 5)) % 2)
				_tiny_farmer(x + 9.0, foot + 2.0, int(time * 2.0 + float(h % 3) + 1.0) % 2)
				_tiny_farmer(x + 18.0, foot + 1.0, int(time * 2.0 + float(h % 7) + 0.5) % 2)
			3:
				# bó lúa + nón lá trên bờ ruộng
				draw_rect(Rect2(x - 2.0, foot - 6.0, 4.0, 6.0), Color(0.88, 0.75, 0.35))
				draw_rect(Rect2(x - 3.0, foot - 3.0, 6.0, 1.0), Color(0.6, 0.45, 0.2))
				draw_rect(Rect2(x + 4.0, foot - 5.0, 4.0, 5.0), Color(0.9, 0.78, 0.38))


func _tiny_buffalo(x: float, foot: float, flip: bool) -> void:
	var body := Color(0.27, 0.24, 0.28)
	var s: float = -1.0 if flip else 1.0
	draw_rect(Rect2(x - 6.0, foot - 7.0, 12.0, 5.0), body)
	draw_rect(Rect2(x - 5.0, foot - 8.0, 9.0, 1.0), body)
	var head_x: float = x + 6.0 if not flip else x - 10.0
	draw_rect(Rect2(head_x, foot - 7.0, 4.0, 4.0), body)
	draw_rect(Rect2(head_x + (3.0 if not flip else -1.0), foot - 9.0, 2.0, 1.0), Color(0.9, 0.88, 0.8))
	draw_rect(Rect2(head_x - s, foot - 9.0, 2.0, 1.0), Color(0.9, 0.88, 0.8))
	for lx in [-5.0, -2.0, 2.0, 4.0]:
		draw_rect(Rect2(x + lx * s, foot - 2.0, 1.0, 2.0), body)


func _tiny_scarecrow(x: float, foot: float) -> void:
	draw_rect(Rect2(x, foot - 12.0, 1.0, 12.0), Color(0.45, 0.32, 0.2))
	draw_rect(Rect2(x - 4.0, foot - 9.0, 9.0, 1.0), Color(0.45, 0.32, 0.2))
	draw_rect(Rect2(x - 2.0, foot - 9.0, 5.0, 4.0), Color(0.8, 0.25, 0.2))
	draw_colored_polygon(PackedVector2Array([Vector2(x - 3.0, foot - 12.0), Vector2(x + 4.0, foot - 12.0), Vector2(x + 0.5, foot - 15.0)]), Color(0.95, 0.86, 0.55))


func _tiny_farmer(x: float, foot: float, frame: int) -> void:
	# Người cấy lúa khom lưng, nón lá; hai khung nhấp nhô.
	var bend: float = float(frame)
	draw_rect(Rect2(x - 1.0, foot - 5.0 + bend, 3.0, 3.0), Color(0.3, 0.45, 0.65))
	draw_rect(Rect2(x - 1.0, foot - 2.0, 1.0, 2.0), Color(0.2, 0.2, 0.25))
	draw_rect(Rect2(x + 1.0, foot - 2.0, 1.0, 2.0), Color(0.2, 0.2, 0.25))
	draw_colored_polygon(PackedVector2Array([Vector2(x + 0.0, foot - 5.0 + bend), Vector2(x + 7.0, foot - 5.0 + bend),
		Vector2(x + 3.5, foot - 8.0 + bend)]), Color(0.95, 0.86, 0.55))


# ------------------------------------------------------------------ hàng cây, nhà

func _draw_mid() -> void:
	var f: float = 0.62
	var tile: float = 170.0
	var r: Vector2i = _tiles(f, tile, 200.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 53)
		var x: float = _lx(float(i) * tile, f)
		var sway: int = int(time * 2.5 + float(h % 11)) % 4
		match h % 10:
			0, 1, 2:
				_coconut(x + 40.0 + float((h >> 6) % 40), (h >> 8) % 3)
				if (h >> 11) % 2 == 0:
					_coconut(x + 110.0 + float((h >> 13) % 30), (h >> 15) % 3)
				_stand(_tex("C_dua_nuoc_01", sway), Vector2(x + 80.0, MID_GROUND + 2.0))
			3:
				_stand(_tex("B_chuoi_01", sway), Vector2(x + 50.0, MID_GROUND + 1.0))
				_stand(_tex("B_dua_nuoc_02", sway), Vector2(x + 120.0, MID_GROUND + 2.0))
			4, 5:
				var wall: String = "C_nha_la_tuong" if (h >> 4) % 2 == 0 else "B_nha_vuon_1_tuong"
				_house(x + 85.0, wall, wall == "C_nha_la_tuong")
				if (h >> 7) % 2 == 0:
					_coconut(x + 10.0, (h >> 9) % 3)
			6:
				_stall(x + 85.0)
			7:
				_stand(_tex("C_chuoi_02", sway), Vector2(x + 40.0, MID_GROUND + 1.0))
				_stand(_tex("B_chuoi_01", sway + 1), Vector2(x + 100.0, MID_GROUND + 1.0))
				_coconut(x + 150.0, (h >> 9) % 3)
			8:
				_stand(_tex("C_dua_nuoc_01", sway), Vector2(x + 30.0, MID_GROUND + 2.0))
				_stand(_tex("B_dua_nuoc_02", sway + 2), Vector2(x + 95.0, MID_GROUND + 2.0))
				_stand(_tex("B_ga_nha_02", int(time * 6.0) % 4), Vector2(x + 140.0, MID_GROUND))
			_:
				_coconut(x + 85.0, (h >> 9) % 3)
	_band(MID_GROUND - 1.0, POLE_GROUND - 6.0, Color(0.36, 0.55, 0.24))


func _coconut(x: float, variant: int) -> void:
	var spec: Array = COCONUTS[variant % COCONUTS.size()]
	var trunk: Texture2D = _tex(spec[0])
	var crown: Texture2D = _tex(spec[1], int(time * 1.6 + x * 0.01) % 4)
	if trunk == null:
		return
	var top_left := Vector2(roundf(x - trunk.get_width() * 0.5), MID_GROUND + 1.0 - trunk.get_height())
	draw_texture(trunk, top_left)
	if crown != null:
		draw_texture(crown, top_left + (spec[2] as Vector2))


func _house(cx: float, wall_name: String, thatch: bool) -> void:
	var wall: Texture2D = _tex(wall_name)
	var w: float = 140.0 if wall == null else wall.get_width()
	var h: float = 40.0 if wall == null else wall.get_height()
	var left: float = roundf(cx - w * 0.5)
	var top: float = MID_GROUND + 1.0 - h
	if wall != null:
		draw_texture(wall, Vector2(left, top))
	else:
		draw_rect(Rect2(left, top, w, h), Color(0.7, 0.6, 0.45))
	# Mái: lá dừa nước (nhà lá) hoặc ngói đỏ (nhà vườn), hơi đưa ra hai bên.
	var roof_h: float = 16.0
	var base: Color = Color(0.6, 0.47, 0.28) if thatch else Color(0.66, 0.3, 0.22)
	var pts := PackedVector2Array([Vector2(left - 6.0, top + 2.0), Vector2(left + w + 6.0, top + 2.0),
		Vector2(left + w - 10.0, top - roof_h), Vector2(left + 10.0, top - roof_h)])
	draw_colored_polygon(pts, base)
	var line := base.darkened(0.25)
	for k in range(1, 5):
		var y: float = top + 2.0 - float(k) * 4.0
		var inset: float = 6.0 + float(k) * 4.0
		draw_rect(Rect2(left - 6.0 + inset - 6.0, y, w + 12.0 - 2.0 * (inset - 6.0), 1.0), line)
	draw_rect(Rect2(left + 10.0, top - roof_h - 1.0, w - 20.0, 2.0), base.lightened(0.2))
	draw_rect(Rect2(left - 6.0, top + 2.0, w + 12.0, 1.0), line.darkened(0.3))
	_laundry(left + w + 10.0, top + 10.0, int(cx))


## Dây phơi đồ cạnh nhà: hai cọc tre, áo quần nhiều màu bay phấp phới.
func _laundry(x: float, y: float, seed_i: int) -> void:
	var pole := Color(0.55, 0.42, 0.25)
	var ground: float = MID_GROUND + 1.0
	draw_rect(Rect2(x, y, 1.0, ground - y), pole)
	draw_rect(Rect2(x + 40.0, y, 1.0, ground - y), pole)
	var pts := PackedVector2Array()
	for k in range(9):
		var t: float = float(k) / 8.0
		pts.append(Vector2(roundf(x + 40.0 * t), roundf(y + 1.0 + sin(t * PI) * 2.0)))
	draw_polyline(pts, Color(0.3, 0.28, 0.26), 1.0)
	var cols: Array[Color] = [Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.85), Color(0.95, 0.85, 0.3), Color(0.95, 0.95, 0.92),
		Color(0.4, 0.7, 0.4), Color(0.85, 0.5, 0.75)]
	for k in range(4):
		var cx: float = x + 6.0 + float(k) * 9.0
		var cy: float = y + 2.0 + roundf(sin(float(k + 1) / 5.0 * PI) * 2.0)
		var flap: float = roundf(sin(time * 4.0 + float(k) + float(seed_i)) * 1.0)
		var c: Color = cols[(seed_i / 7 + k) % cols.size()]
		if k % 2 == 0:
			# áo
			draw_rect(Rect2(cx - 3.0, cy, 7.0, 3.0), c)
			draw_rect(Rect2(cx - 2.0 + flap, cy + 3.0, 5.0, 4.0), c)
		else:
			# quần
			draw_rect(Rect2(cx - 2.0, cy, 5.0, 2.0), c)
			draw_rect(Rect2(cx - 2.0 + flap, cy + 2.0, 2.0, 5.0), c)
			draw_rect(Rect2(cx + 1.0 + flap, cy + 2.0, 2.0, 5.0), c)


func _stall(cx: float) -> void:
	var wall: Texture2D = _tex("A_quan_tap_hoa_tuong")
	var w: float = 160.0 if wall == null else wall.get_width()
	var h: float = 38.0 if wall == null else wall.get_height()
	var left: float = roundf(cx - w * 0.5)
	var top: float = MID_GROUND + 1.0 - h
	if wall != null:
		draw_texture(wall, Vector2(left, top))
	# Mái tôn + bạt sọc xanh trắng.
	draw_rect(Rect2(left - 4.0, top - 10.0, w + 8.0, 10.0), Color(0.55, 0.6, 0.62))
	for k in range(0, int(w + 8.0), 4):
		draw_rect(Rect2(left - 4.0 + float(k), top - 10.0, 1.0, 10.0), Color(0.45, 0.5, 0.52))
	for k in range(0, int(w + 8.0), 8):
		draw_rect(Rect2(left - 4.0 + float(k), top, 4.0, 5.0), Color(0.2, 0.5, 0.8))
		draw_rect(Rect2(left + float(k), top, 4.0, 5.0), Color(0.95, 0.95, 0.92))


# ------------------------------------------------------------------ cột điện

func _draw_poles() -> void:
	var f: float = 0.8
	var tile: float = 150.0
	var r: Vector2i = _tiles(f, tile, 160.0)
	var pole: Texture2D = _tex("C_cot_dien_01")
	var height: float = 66.0 if pole == null else pole.get_height()
	var wire := Color(0.16, 0.16, 0.2)
	for i in range(r.x, r.y + 1):
		var x: float = _lx(float(i) * tile, f)
		var top := Vector2(x, POLE_GROUND - height)
		if pole != null:
			draw_texture(pole, Vector2(x - 3.0, top.y))
		else:
			draw_rect(Rect2(x - 2.0, top.y, 4.0, height), Color(0.6, 0.6, 0.6))
		draw_rect(Rect2(x - 7.0, top.y + 5.0, 14.0, 2.0), Color(0.35, 0.33, 0.32))
		var next_x: float = _lx(float(i + 1) * tile, f)
		for k in range(2):
			var a := Vector2(x - 6.0 + 12.0 * float(k), top.y + 5.0)
			var b := Vector2(next_x - 6.0 + 12.0 * float(k), top.y + 5.0)
			var pts := PackedVector2Array()
			for s in range(11):
				var t: float = float(s) / 10.0
				pts.append(Vector2(roundf(lerpf(a.x, b.x, t)), roundf(a.y + sin(t * PI) * 6.0)))
			draw_polyline(pts, wire, 1.0)


# ------------------------------------------------------------------ mặt đường

func _draw_road() -> void:
	var left: float = floorf(cam_left) - 2.0
	var right: float = left + view_w + 6.0
	# Lề cỏ phía sau, mặt đường bê tông, lề phía trước.
	_band(POLE_GROUND - 6.0, ROAD_TOP, Color(0.46, 0.66, 0.29))
	_band(ROAD_TOP, ROAD_BOTTOM, Color(0.67, 0.65, 0.6))
	_band(ROAD_TOP, ROAD_TOP + 1.0, Color(0.5, 0.48, 0.44))
	_band(ROAD_TOP + 1.0, ROAD_TOP + 2.0, Color(0.6, 0.58, 0.54))
	_band(ROAD_BOTTOM - 2.0, ROAD_BOTTOM, Color(0.58, 0.56, 0.52))
	_band(ROAD_BOTTOM, ROAD_BOTTOM + 2.0, Color(0.46, 0.44, 0.4))
	_band(ROAD_BOTTOM + 2.0, view_top + view_h + 40.0, Color(0.4, 0.61, 0.26))
	# Vết nứt, mảng vá, sỏi.
	var r: Vector2i = _tiles(1.0, 36.0, 10.0)
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 61)
		var x: float = float(i) * 36.0
		var y: float = ROAD_TOP + 4.0 + float(h % 58)
		if h % 4 == 0:
			draw_rect(Rect2(x + float((h >> 5) % 20), y, 10.0 + float((h >> 9) % 10), 4.0), Color(0.62, 0.6, 0.55))
		if (h >> 3) % 3 == 0:
			var cx: float = x + float((h >> 12) % 30)
			draw_line(Vector2(cx, y), Vector2(cx + 4.0, y + 1.0), Color(0.55, 0.53, 0.5), 1.0)
			draw_line(Vector2(cx + 4.0, y + 1.0), Vector2(cx + 7.0, y), Color(0.55, 0.53, 0.5), 1.0)
		draw_rect(Rect2(x + float((h >> 15) % 34), ROAD_TOP + 3.0 + float((h >> 18) % 60), 1.0, 1.0), Color(0.58, 0.56, 0.52))
		# Cỏ lề sau và lề trước.
		var g := Color(0.33, 0.52, 0.2)
		draw_rect(Rect2(x + float((h >> 7) % 30), POLE_GROUND - 4.0 + float((h >> 20) % 4), 1.0, 2.0), g)
		draw_rect(Rect2(x + float((h >> 21) % 30), ROAD_BOTTOM + 4.0 + float((h >> 11) % 6), 1.0, 2.0), g)
		draw_rect(Rect2(x + float((h >> 24) % 30) + 1.0, ROAD_BOTTOM + 3.0 + float((h >> 11) % 6), 1.0, 3.0), g)
	# Vạch lề liền (trắng) hai bên mặt đường.
	_band(ROAD_TOP + 4.0, ROAD_TOP + 5.0, Color(0.93, 0.92, 0.85))
	_band(ROAD_BOTTOM - 5.0, ROAD_BOTTOM - 4.0, Color(0.93, 0.92, 0.85))
	# Mũi tên sơn trên làn giữa mỗi 640 px; vết bánh xe mờ.
	var a0: int = floori(left / 640.0)
	for a in range(a0, floori(right / 640.0) + 1):
		var ax: float = float(a) * 640.0 + 300.0
		var ay: float = 177.0
		var paint := Color(0.93, 0.92, 0.85, 0.85)
		draw_rect(Rect2(ax, ay - 1.0, 14.0, 2.0), paint)
		draw_colored_polygon(PackedVector2Array([Vector2(ax + 14.0, ay - 4.0), Vector2(ax + 20.0, ay), Vector2(ax + 14.0, ay + 4.0)]), paint)
		draw_rect(Rect2(ax - 60.0, 160.0, 50.0, 1.0), Color(0.5, 0.48, 0.45, 0.35))
		draw_rect(Rect2(ax - 50.0, 199.0, 70.0, 1.0), Color(0.5, 0.48, 0.45, 0.35))
	# Vạch qua đường (zebra) gần xuất phát và trước đích.
	for zx in [120.0, track_len - 240.0]:
		if zx + 40.0 > left and zx - 10.0 < right:
			for k in range(8):
				var y0: float = ROAD_TOP + 7.0 + float(k) * 7.5
				draw_rect(Rect2(zx + roundf(6.0 * (1.0 - float(k) / 8.0)), y0, 22.0, 4.0), Color(0.94, 0.93, 0.87))
	# Vạch chia làn.
	var dash: float = 32.0
	var k0: int = floori(left / dash)
	var k1: int = floori(right / dash)
	for k in range(k0, k1 + 1):
		for y in LANE_MARKS:
			draw_rect(Rect2(float(k) * dash, y, 13.0, 1.0), Color(0.95, 0.94, 0.86))
	# Cột cây số mỗi 1000 px ở lề sau.
	var m0: int = floori(left / 1000.0)
	for m in range(m0, floori(right / 1000.0) + 1):
		var x: float = float(m) * 1000.0 + 40.0
		draw_rect(Rect2(x, POLE_GROUND - 9.0, 6.0, 9.0), Color(0.95, 0.95, 0.9))
		draw_rect(Rect2(x, POLE_GROUND - 11.0, 6.0, 3.0), Color(0.85, 0.2, 0.15))
		draw_rect(Rect2(x + 6.0, POLE_GROUND - 9.0, 1.0, 9.0), Color(0.6, 0.6, 0.55))
	# Vạch xuất phát (x = 0) và vạch đích ca-rô.
	if left < 20.0 and right > -20.0:
		_slanted_band(0.0, Color(0.96, 0.96, 0.92), 3.0)
	if left < track_len + 30.0 and right > track_len - 30.0:
		_checker(track_len)


## Dải vạch cắt ngang đường, hơi xéo theo phối cảnh (mép sau lệch phải).
func _slanted_band(x: float, color: Color, width: float) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(x + 6.0, ROAD_TOP + 1.0), Vector2(x + 6.0 + width, ROAD_TOP + 1.0),
		Vector2(x + width, ROAD_BOTTOM), Vector2(x, ROAD_BOTTOM)]), color)


func _checker(x: float) -> void:
	var rows: int = 8
	var row_h: float = (ROAD_BOTTOM - ROAD_TOP - 1.0) / float(rows)
	for row in range(rows):
		var y: float = roundf(ROAD_TOP + 1.0 + float(row) * row_h)
		var y2: float = roundf(ROAD_TOP + 1.0 + float(row + 1) * row_h)
		var shift: float = roundf(6.0 * (1.0 - (y - ROAD_TOP) / (ROAD_BOTTOM - ROAD_TOP)))
		for col in range(2):
			var c: Color = Color(0.1, 0.1, 0.1) if (row + col) % 2 == 0 else Color(0.97, 0.97, 0.95)
			draw_rect(Rect2(x + shift + float(col) * 4.0, y, 4.0, y2 - y), c)


## Đoạn đường bê tông vượt kênh: lan can trắng hai bên, khe nước xanh dưới lề trước, cọc tiêu.
func _draw_road_bridges() -> void:
	for b in ROAD_BRIDGES:
		var x0: float = float(b[0])
		var length: float = float(b[1])
		if x0 + length < cam_left - 20.0 or x0 > cam_left + view_w + 20.0:
			continue
		var rail := Color(0.92, 0.92, 0.88)
		var rail_d := Color(0.62, 0.62, 0.6)
		# nước kênh lộ ra dưới mép trước + mép sau
		draw_rect(Rect2(x0, ROAD_BOTTOM + 2.0, length, view_top + view_h + 40.0 - ROAD_BOTTOM), Color(0.38, 0.58, 0.68))
		for k in range(0, int(length), 10):
			var gx: float = x0 + float(k) + fmod(time * 6.0, 10.0)
			draw_rect(Rect2(roundf(gx), ROAD_BOTTOM + 8.0 + float(k % 3) * 5.0, 4.0, 1.0), Color(0.85, 0.95, 0.98, 0.6))
		draw_rect(Rect2(x0, POLE_GROUND - 6.0, length, 6.0), Color(0.38, 0.58, 0.68))
		# lan can phía sau (thấp) và phía trước
		for edge_y in [ROAD_TOP - 6.0, ROAD_BOTTOM - 2.0]:
			draw_rect(Rect2(x0 - 4.0, edge_y, length + 8.0, 2.0), rail)
			draw_rect(Rect2(x0 - 4.0, edge_y + 2.0, length + 8.0, 1.0), rail_d)
			for k in range(0, int(length) + 8, 12):
				draw_rect(Rect2(x0 - 4.0 + float(k), edge_y + 2.0, 2.0, 5.0), rail)
		for side_x in [x0 - 6.0, x0 + length + 2.0]:
			draw_rect(Rect2(side_x, ROAD_TOP - 10.0, 4.0, 10.0), Color(0.95, 0.95, 0.9))
			draw_rect(Rect2(side_x, ROAD_TOP - 10.0, 4.0, 3.0), Color(0.85, 0.2, 0.15))


## Cổng xuất phát: hai cọc tre giăng dây cờ, ông trọng tài phất cờ ở lề sau.
func _draw_start() -> void:
	if cam_left > 160.0 or cam_left + view_w < -160.0:
		return
	var x: float = -30.0
	for k in range(2):
		var px: float = x + float(k) * 70.0
		draw_rect(Rect2(px, POLE_GROUND - 46.0, 2.0, 46.0), Color(0.6, 0.48, 0.28))
	for k in range(12):
		var fx: float = x + 2.0 + float(k) * 6.0
		var fy: float = POLE_GROUND - 44.0 + roundf(sin(float(k) / 11.0 * PI) * 4.0)
		var c: Color = [Color(0.9, 0.2, 0.15), Color(1.0, 0.85, 0.2), Color(0.25, 0.5, 0.9), Color(0.3, 0.7, 0.35)][k % 4]
		draw_colored_polygon(PackedVector2Array([Vector2(fx, fy), Vector2(fx + 4.0, fy), Vector2(fx + 2.0, fy + 4.0)]), c)
	# trọng tài: áo trắng, nón lá, cờ ca-rô phất lên xuống
	var rx: float = 52.0
	var foot: float = POLE_GROUND - 1.0
	draw_rect(Rect2(rx - 3.0, foot - 13.0, 6.0, 8.0), Color(0.95, 0.95, 0.92))
	draw_rect(Rect2(rx - 2.0, foot - 5.0, 2.0, 5.0), Color(0.25, 0.25, 0.3))
	draw_rect(Rect2(rx + 1.0, foot - 5.0, 2.0, 5.0), Color(0.25, 0.25, 0.3))
	draw_rect(Rect2(rx - 2.0, foot - 17.0, 4.0, 4.0), Color(0.85, 0.65, 0.5))
	draw_colored_polygon(PackedVector2Array([Vector2(rx - 6.0, foot - 17.0), Vector2(rx + 6.0, foot - 17.0), Vector2(rx, foot - 22.0)]), Color(0.95, 0.86, 0.55))
	var wave: float = roundf(sin(time * 8.0) * 3.0)
	draw_line(Vector2(rx + 3.0, foot - 12.0), Vector2(rx + 8.0, foot - 22.0 + wave), Color(0.4, 0.3, 0.2), 1.0)
	for yy in range(3):
		for xx in range(3):
			var c2: Color = Color(0.1, 0.1, 0.1) if (xx + yy) % 2 == 0 else Color(0.97, 0.97, 0.95)
			draw_rect(Rect2(rx + 8.0 + float(xx) * 2.0, foot - 26.0 + wave + float(yy) * 2.0, 2.0, 2.0), c2)


# ------------------------------------------------------------------ cổng ấp (đích)

## Mặt cổng ấp đứng ở lề sau, ngay chỗ vạch đích: hai trụ gạch, xà ngang có bảng tên, cờ hai bên.
## Chữ trên bảng do HUD vẽ (sắc nét) tại GATE_SIGN.
const GATE_HALF: float = 52.0
const GATE_TOP: float = 52.0
const GATE_SIGN: Rect2 = Rect2(-40, 56, 80, 14) # so với x đích


func _draw_gate() -> void:
	var x: float = roundf(track_len)
	if x + 120.0 < cam_left or x - 120.0 > cam_left + view_w:
		return
	var brick := Color(0.72, 0.32, 0.22)
	var light := Color(0.86, 0.5, 0.36)
	var dark := Color(0.45, 0.18, 0.12)
	for side in [-1.0, 1.0]:
		var px: float = x + side * GATE_HALF - 5.0
		draw_rect(Rect2(px, GATE_TOP, 10.0, POLE_GROUND - GATE_TOP), brick)
		draw_rect(Rect2(px, GATE_TOP, 2.0, POLE_GROUND - GATE_TOP), light)
		draw_rect(Rect2(px + 8.0, GATE_TOP, 2.0, POLE_GROUND - GATE_TOP), dark)
		for yy in range(int(GATE_TOP) + 6, int(POLE_GROUND), 6):
			draw_rect(Rect2(px + 2.0, float(yy), 6.0, 1.0), dark)
		draw_rect(Rect2(px - 2.0, GATE_TOP - 4.0, 14.0, 4.0), Color(0.55, 0.22, 0.15))
		draw_rect(Rect2(px - 1.0, GATE_TOP - 7.0, 12.0, 3.0), Color(0.85, 0.7, 0.3))
		# Cờ phướn.
		var wave: float = roundf(sin(time * 5.0 + side) * 1.5)
		draw_rect(Rect2(px + 4.0, GATE_TOP - 26.0, 1.0, 19.0), Color(0.3, 0.25, 0.2))
		draw_colored_polygon(PackedVector2Array([Vector2(px + 5.0, GATE_TOP - 26.0), Vector2(px + 17.0, GATE_TOP - 24.0 + wave),
			Vector2(px + 5.0, GATE_TOP - 19.0)]), Color(0.9, 0.15, 0.12))
		draw_rect(Rect2(px + 8.0, GATE_TOP - 24.0 + roundf(wave * 0.5), 2.0, 2.0), Color(1.0, 0.85, 0.2))
	# Xà ngang + bảng tên.
	draw_rect(Rect2(x - GATE_HALF - 4.0, GATE_TOP + 1.0, GATE_HALF * 2.0 + 8.0, 4.0), Color(0.55, 0.22, 0.15))
	draw_rect(Rect2(x + GATE_SIGN.position.x - 2.0, GATE_SIGN.position.y - 2.0, GATE_SIGN.size.x + 4.0, GATE_SIGN.size.y + 4.0), Color(0.85, 0.7, 0.3))
	draw_rect(Rect2(x + GATE_SIGN.position.x, GATE_SIGN.position.y, GATE_SIGN.size.x, GATE_SIGN.size.y), Color(0.75, 0.12, 0.1))
	# Dây cờ đuôi nheo qua đường.
	for k in range(14):
		var fx: float = x - GATE_HALF + float(k) * 8.0
		var fy: float = GATE_TOP + 9.0 + roundf(sin(float(k) / 13.0 * PI) * 5.0)
		var c: Color = [Color(0.9, 0.2, 0.15), Color(1.0, 0.85, 0.2), Color(0.25, 0.5, 0.9)][k % 3]
		draw_colored_polygon(PackedVector2Array([Vector2(fx, fy), Vector2(fx + 5.0, fy), Vector2(fx + 2.5, fy + 5.0)]), c)
	# Vòm bong bóng trên cổng (đỏ – vàng – xanh), lắc nhẹ; pháo giấy khi có người về đích.
	var balloon: Array[Color] = [Color(0.92, 0.22, 0.2), Color(1.0, 0.84, 0.22), Color(0.25, 0.55, 0.95), Color(0.98, 0.98, 0.95)]
	for k in range(23):
		var t: float = float(k) / 22.0
		var bx: float = x - GATE_HALF + GATE_HALF * 2.0 * t
		var by: float = GATE_TOP - 6.0 - sin(t * PI) * 22.0 + roundf(sin(time * 3.0 + float(k)) * 0.6)
		var c: Color = balloon[k % balloon.size()]
		draw_circle(Vector2(roundf(bx), roundf(by)), 3.4, c.darkened(0.25))
		draw_circle(Vector2(roundf(bx), roundf(by)), 2.6, c)
		draw_rect(Rect2(roundf(bx) - 1.0, roundf(by) - 2.0, 1.0, 1.0), Color(1, 1, 1, 0.8))
	if cheer > 0.0:
		for k in range(24):
			var h: int = hash_i(k, 101)
			var cx2: float = x - 60.0 + float(h % 120)
			var cy2: float = GATE_TOP - 30.0 + fmod(time * 30.0 + float((h >> 7) % 80), 90.0)
			draw_rect(Rect2(roundf(cx2 + sin(time * 5.0 + float(k)) * 2.0), roundf(cy2), 2.0, 1.0), balloon[k % balloon.size()])
	# Khán giả hàng sau (lề sau).
	_draw_crowd(x, POLE_GROUND - 1.0, [-82.0, -66.0, -30.0, 18.0, 34.0, 70.0, 86.0], 0)


func _draw_crowd(x: float, foot_y: float, offsets: Array, salt: int) -> void:
	if crowd.is_empty():
		return
	for k in range(offsets.size()):
		var t: Texture2D = crowd[(k + salt) % crowd.size()]
		var hop: float = 0.0
		if cheer > 0.0:
			hop = -absf(roundf(sin(time * 12.0 + float(k) * 1.7) * 3.0))
		else:
			hop = -absf(roundf(sin(time * 3.0 + float(k)) * 1.0))
		_stand(t, Vector2(x + float(offsets[k]), foot_y + hop), (k + salt) % 2 == 1)


# ------------------------------------------------------------------ lớp trước

func _draw_front() -> void:
	# Bụi cỏ, khóm lục bình… ngay mép dưới khung hình (parallax 1.25: trôi nhanh hơn đường).
	var f: float = 1.25
	var r: Vector2i = _tiles(f, 64.0, 40.0)
	var bottom: float = view_top + view_h + 2.0
	for i in range(r.x, r.y + 1):
		var h: int = hash_i(i, 71)
		if h % 3 != 0:
			continue
		var x: float = _lx(float(i) * 64.0 + float(h % 40), f)
		var c := Color(0.25, 0.45, 0.17)
		var c2 := Color(0.33, 0.56, 0.22)
		for k in range(5):
			var bx: float = x + float(k) * 3.0 - 6.0
			var bh: float = 6.0 + float((h >> (k * 3)) % 7)
			draw_rect(Rect2(bx, bottom - bh, 2.0, bh), c if k % 2 == 0 else c2)
	# Khán giả hàng trước ở đích.
	var gx: float = roundf(track_len)
	if gx + 140.0 > cam_left and gx - 140.0 < cam_left + view_w:
		_draw_crowd(gx, ROAD_BOTTOM + 34.0, [-96.0, -74.0, -40.0, 62.0, 80.0, 102.0], 2)
