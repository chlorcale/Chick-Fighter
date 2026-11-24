extends Node2D

## Vỏ lãi của người chơi (lái lấy). World giữ một chiếc: lên ở bến (traffic.json "docks") hoặc chỗ đã neo, xuống ở bến
## hoặc bờ đất sát nước bất kỳ.
## Điều khiển (logic 60 Hz trong _physics_process): W ga tới, S phanh rồi lùi, A/D quay mũi 16 hướng (mỗi nấc 22,5°,
## 0,13 s/nấc). Quán tính: lực đẩy 120 px/s² tới tối đa 150 px/s (lùi 45), cản 0,5/s khi nhả ga, trượt ngang tắt dần
## 3/s (thuyền trôi khi bẻ lái). Va chạm: mọi điểm mẫu của thân thuyền phải là nước (water.png), không nằm trong cầu
## thấp (bridges.player_boat_passes = false), thân vỏ lãi NPC, đò ngang → không thì thử trượt theo từng trục, kẹt cả hai
## thì dội ngược nhẹ (×0,25) + tiếng nước.
## Hình: tranh chỉ có vỏ lãi nhìn ngang (đông/tây) → hướng gần ngang (5 nấc mỗi bên) dùng vỏ lãi boat_01 đã xoá hai người
## ngồi (xử lý ảnh lúc chạy), nghiêng bằng phép trượt dọc (độ dốc = 0,5 × tan góc) để người đứng vẫn thẳng; hướng gần
## dọc (3 nấc mỗi phía) dùng ảnh pixel vỏ lãi nhìn dọc game/art/world_map/player_boat_ns.png (mũi lên | mũi xuống, vẽ bởi
## tools/art/world_map_fixes.py cùng bảng màu boat_01; thiếu ảnh thì vẽ bằng code như cũ).
## Chui qua mọi cầu (water.png đã lấp nước dưới mặt cầu; mặt cầu vẽ đè lên thuyền – traffic.gd). Kênh hẹp: chạy thẳng mà
## vướng mép thì tự lách ngang tối đa NUDGE_PX để bám giữa kênh. trip_px = quãng đã chạy từ lúc lên thuyền (thành tích). Người chơi đứng ở đuôi cạnh máy (World đặt
## vị trí người chơi theo seat_point()).
## Gốc toạ độ logic `center` = tâm thân thuyền trên mặt nước; nhìn ngang: node Y-sort theo mép nước thấp nhất (người
## lái đứng sau mạn gần, mạn che chân); nhìn dọc: node Y-sort trên đầu thuyền (người lái đứng trên sàn, vẽ đè thuyền).

const Audio := preload("res://game/audio/audio_director.gd")
const LOOK_ID: String = "boat_01"
const MAX_FWD: float = 150.0
const MAX_REV: float = 45.0
const THRUST: float = 120.0
const BRAKE: float = 220.0
const DRAG: float = 0.5
const LAT_DAMP: float = 3.0
const TURN_TIME: float = 0.13
const HEADINGS: int = 16
## Thân nhìn ngang: mẫu va chạm theo trục thân (tính từ tâm) và hai hàng mép nước.
const SIDE_XS: Array[float] = [-70.0, -52.0, -35.0, -17.0, 0.0, 17.0, 35.0, 52.0, 70.0]
const SIDE_YS: Array[float] = [-6.0, 0.0]
## Thân nhìn dọc.
const VERT_XS: Array[float] = [-7.0, 0.0, 7.0]
const VERT_YS: Array[float] = [-24.0, -12.0, 0.0, 12.0, 24.0]
## Neo vỏ lãi boat_01 (hướng đông) – tâm thân = điểm neo của traffic.json.
const SIDE_SEAT: Vector2 = Vector2(-51, -8)
const VERT_LEN: int = 60
const VERT_W: int = 30
const NS_SHEET_PATH: String = "res://game/art/world_map/player_boat_ns.png"
const NUDGE_PX: int = 4

var world: Node
## true khi người chơi đang lái.
var active: bool = false
## true khi thuyền đang hiện trên bản đồ (đang lái hoặc neo ở đâu đó).
var moored: bool = false
var center: Vector2 = Vector2.ZERO
var heading: int = 0
var vel: Vector2 = Vector2.ZERO
var throttle: float = 0.0
## Đếm va chạm (test).
var bumps: int = 0
## Test/ảnh chụp đặt lệnh lái thay bàn phím: {"fwd": -1..1, "turn": -1/0/1}; rỗng = đọc phím.
var scripted: Dictionary = {}
## Quãng đường (px) đã chạy trong chuyến hiện tại (đặt lại khi lên thuyền).
var trip_px: float = 0.0
var _ns_tail: int = 18

var _holder: Node2D
var _sprite: Sprite2D
var _tex_east: Texture2D
var _tex_west: Texture2D
var _tex_north: Texture2D
var _tex_south: Texture2D
var _wake: Node2D
var _emitter: AudioStreamPlayer2D
var _turn_time: float = 0.0
var _bump_cd: float = 0.0
var _time: float = 0.0
var _blockers: Array = [] # [Rect2] cầu thấp
var _last_view: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_holder = Node2D.new()
	add_child(_holder)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_holder.add_child(_sprite)
	_build_textures()
	_wake = Node2D.new()
	_wake.name = "PlayerBoatWake"
	_wake.draw.connect(_draw_wake)
	_emitter = Audio.make_emitter(&"boat", 300.0, -1.0)
	_emitter.stream_paused = true
	add_child(_emitter)
	for b in MapView.traffic_data().get("bridges", []):
		if not bool(b["player_boat_passes"]):
			var r: Array = b["rect"]
			_blockers.append(Rect2(r[0], r[1], r[2], r[3]))
	visible = false


## Lớp vệt sóng (World thêm vào MapView.add_ground).
func wake_node() -> Node2D:
	return _wake


# =================================================================== ảnh

func _build_textures() -> void:
	var look: Dictionary = {}
	for v in MapView.traffic_data().get("vehicles", []):
		if String(v["id"]) == LOOK_ID:
			look = v
	var atlas_tex: Texture2D = load(MapView.TRAFFIC_ATLAS)
	if look.is_empty() or atlas_tex == null:
		return
	var atlas: Image = atlas_tex.get_image()
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var r: Array = look["frames"]["east"][0]
	var hull: Image = atlas.get_region(Rect2i(r[0], r[1], r[2], r[3]))
	_strip_passengers(hull)
	_tex_east = ImageTexture.create_from_image(hull)
	var west: Image = hull.duplicate()
	west.flip_x()
	_tex_west = ImageTexture.create_from_image(west)
	if ResourceLoader.exists(NS_SHEET_PATH):
		var sheet: Texture2D = load(NS_SHEET_PATH)
		var w: int = sheet.get_width() / 2
		var up := AtlasTexture.new()
		up.atlas = sheet
		up.region = Rect2(0, 0, w, sheet.get_height())
		var down := AtlasTexture.new()
		down.atlas = sheet
		down.region = Rect2(w, 0, w, sheet.get_height())
		_tex_north = up
		_tex_south = down
		_ns_tail = sheet.get_height() - VERT_LEN
	else:
		_tex_north = ImageTexture.create_from_image(_vertical_hull(true))
		_tex_south = ImageTexture.create_from_image(_vertical_hull(false))


## Xoá hai người ngồi trên boat_01 (cột x 52–118 của khung đông), vẽ lại lòng thuyền: viền mạn xa, sọc xanh, sàn gỗ
## nâu, hai sườn gỗ.
static func _strip_passengers(img: Image) -> void:
	var clear := Color(0, 0, 0, 0)
	var outline := Color8(42, 30, 46)
	var blue_l := Color8(74, 147, 204)
	var blue := Color8(44, 100, 168)
	var floor_c := Color8(100, 57, 47)
	var rib := Color8(182, 124, 70)
	var dark := Color8(58, 36, 48)
	var cream := Color8(247, 237, 196)
	var motor := Color8(91, 90, 110)
	for x in range(52, 58):
		for y in range(0, 38):
			if y < 24:
				img.set_pixel(x, y, clear)
			else:
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.0 and c.g > c.r + 0.1 and c.g > c.b:
					img.set_pixel(x, y, motor) # vạt áo xanh của người lái lẹm vào máy
	for x in range(58, 119):
		var ft: int = 28 if x < 100 else 27
		var nb: int = int(roundf(39.0 - float(x - 60) / 26.0))
		for y in range(0, nb):
			var c: Color
			if y < ft:
				c = clear
			elif y == ft:
				c = outline
			elif y == ft + 1:
				c = blue_l
			elif y == ft + 2:
				c = blue
			elif y == nb - 1:
				c = dark if x < 90 else cream
			else:
				c = rib if x in [75, 76, 96, 97] else floor_c
			img.set_pixel(x, y, c)


## Thân vỏ lãi nhìn dọc (VERT_W × VERT_LEN + chỗ máy/cần đuôi tôm), mũi sơn xanh như boat_01. bow_up: mũi ở trên.
static func _vertical_hull(bow_up: bool) -> Image:
	var tail: int = 18
	var img := Image.create(VERT_W, VERT_LEN + tail, false, Image.FORMAT_RGBA8)
	var outline := Color8(42, 30, 46)
	var cream := Color8(247, 237, 196)
	var shade := Color8(177, 174, 170)
	var blue_l := Color8(74, 147, 204)
	var blue := Color8(44, 100, 168)
	var blue_d := Color8(31, 63, 124)
	var floor_c := Color8(100, 57, 47)
	var rib := Color8(182, 124, 70)
	var motor := Color8(91, 90, 110)
	var motor_l := Color8(177, 174, 170)
	var red := Color8(194, 44, 52)
	var cx: float = float(VERT_W) / 2.0
	for row in range(VERT_LEN):
		var t: float = float(row) / float(VERT_LEN - 1) # 0 = mũi, 1 = đuôi
		var half: float = 12.5 * minf(1.0, sqrt(t / 0.4)) if t < 0.4 else 12.5
		if t > 0.9:
			half = 12.5 - (t - 0.9) * 24.0
		var x0: int = int(floorf(cx - half))
		var x1: int = int(ceilf(cx + half)) - 1
		for x in range(x0, x1 + 1):
			var edge: int = mini(x - x0, x1 - x)
			var c: Color
			if edge == 0 or row == VERT_LEN - 1 or row == 0:
				c = outline
			elif t < 0.2:
				c = blue_l if x < cx else (blue if edge > 1 else blue_d)
			elif edge == 1:
				c = blue_l if x < cx else blue
			elif edge == 2:
				c = cream if x < cx else shade
			elif row == VERT_LEN - 2:
				c = outline
			else:
				c = rib if (row % 11 == 5) else floor_c
			img.set_pixel(x, row, c)
	# máy + cần đuôi tôm ở đuôi
	for y in range(VERT_LEN - 5, VERT_LEN + 3):
		for x in range(int(cx) - 4, int(cx) + 4):
			var c: Color = motor
			if y == VERT_LEN - 5 or x == int(cx) - 4 or x == int(cx) + 3 or y == VERT_LEN + 2:
				c = outline
			elif y == VERT_LEN - 4:
				c = motor_l
			elif y == VERT_LEN - 2 and x > int(cx) - 3 and x < int(cx) + 2:
				c = red
			img.set_pixel(x, y, c)
	for k in range(tail - 3):
		var x: int = int(cx) + 1 + k / 5
		var y: int = VERT_LEN + 3 + k
		if y < img.get_height():
			img.set_pixel(x, y, outline)
			if x + 1 < VERT_W:
				img.set_pixel(x + 1, y, motor_l if k % 2 == 0 else outline)
	if not bow_up:
		img.flip_y()
	return img


# =================================================================== hình học

static func dir_of(h: int) -> Vector2:
	return Vector2.from_angle(float(posmod(h, HEADINGS)) * TAU / float(HEADINGS))


## "east", "west", "north", "south": ảnh dùng cho hướng h.
static func view_of(h: int) -> String:
	var k: int = posmod(h, HEADINGS)
	if k >= 14 or k <= 2:
		return "east"
	if k >= 6 and k <= 10:
		return "west"
	return "south" if k < 8 else "north"


## Độ dốc trượt dọc của thân nhìn ngang (0 ở hướng ngang thật).
static func shear_of(h: int) -> float:
	var view: String = view_of(h)
	if view != "east" and view != "west":
		return 0.0
	return clampf(0.5 * tan(float(posmod(h, HEADINGS)) * TAU / float(HEADINGS)), -0.5, 0.5)


## Điểm mẫu va chạm của thân thuyền ở tâm c, hướng h.
static func footprint(c: Vector2, h: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var view: String = view_of(h)
	if view == "east" or view == "west":
		var k: float = shear_of(h)
		for x in SIDE_XS:
			for y in SIDE_YS:
				out.append(c + Vector2(x, y + k * x))
	else:
		for x in VERT_XS:
			for y in VERT_YS:
				out.append(c + Vector2(x, y))
	return out


## Chỗ người lái đứng (chân) – cạnh máy ở đuôi.
static func seat_of(c: Vector2, h: int) -> Vector2:
	var view: String = view_of(h)
	match view:
		"east":
			return c + Vector2(SIDE_SEAT.x, SIDE_SEAT.y + shear_of(h) * SIDE_SEAT.x)
		"west":
			return c + Vector2(-SIDE_SEAT.x, SIDE_SEAT.y - shear_of(h) * SIDE_SEAT.x)
		"north":
			return c + Vector2(0, 17)
	return c + Vector2(0, -19)


func seat_point() -> Vector2:
	return seat_of(center, heading)


## Khung bao thân thuyền (xe NPC nhường, cầu, test).
func hull_rect() -> Rect2:
	var pts: PackedVector2Array = footprint(center, heading)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(3.0)


## Mọi điểm mẫu ở nơi thuyền vào được.
func footprint_clear(c: Vector2, h: int) -> bool:
	var hulls: Array = []
	if world != null and world.get("traffic") != null:
		hulls = world.traffic.call("boat_hulls", c, 90.0)
	var ferry_rect := Rect2()
	if world != null and world.get("ferry_boat") != null:
		var top: Vector2 = (world.ferry_boat as Node2D).position
		ferry_rect = Rect2(top.x - 18.0, top.y + 4.0, 36.0, 56.0)
	for p in footprint(c, h):
		if not navigable(p):
			return false
		if ferry_rect.has_point(p):
			return false
		for r in hulls:
			if (r as Rect2).has_point(p):
				return false
	return true


func navigable(p: Vector2) -> bool:
	if world == null or not world.call("is_water", p.x, p.y):
		return false
	for r in _blockers:
		if (r as Rect2).grow(2.0).has_point(p):
			return false
	return true


# =================================================================== lái

## Đặt thuyền (không kiểm va chạm) – World gọi khi lên thuyền / neo.
func place(c: Vector2, h: int) -> void:
	center = c
	heading = posmod(h, HEADINGS)
	vel = Vector2.ZERO
	throttle = 0.0
	moored = true
	visible = true
	_apply_view()


func hide_boat() -> void:
	moored = false
	active = false
	visible = false
	_emitter.stream_paused = true
	_wake.queue_redraw()


func set_driving(on: bool) -> void:
	active = on
	_last_view = ""
	if on:
		trip_px = 0.0
	if not on:
		vel = Vector2.ZERO
		throttle = 0.0
		_emitter.stream_paused = true


func pause_sound() -> void:
	if _emitter != null:
		_emitter.stream_paused = true


## Đặt người chơi đứng ở chỗ lái, quay mặt theo hình thuyền đang hiện.
func sync_player() -> void:
	if world == null or world.get("player") == null:
		return
	var player: Node2D = world.player
	player.position = seat_point().round()
	var view: String = view_of(heading)
	if view != _last_view:
		_last_view = view
		var faces: Dictionary = {"east": Vector2i(1, 0), "west": Vector2i(-1, 0), "north": Vector2i(0, -1), "south": Vector2i(0, 1)}
		player.call("face", faces[view])


func _physics_process(delta: float) -> void:
	_time += delta
	if not moored:
		return
	if active:
		drive(delta)
		sync_player()
	_apply_view()
	_wake.queue_redraw()


## Bản đồ M đang mở: thả ga, vỏ lãi trôi chậm lại theo quán tính.
func _map_open() -> bool:
	if world == null:
		return false
	var overlay: Variant = world.get("map_overlay")
	return overlay != null and bool((overlay as Object).get("open"))


## Một bước lái 60 Hz.
func drive(delta: float) -> void:
	_bump_cd = maxf(_bump_cd - delta, 0.0)
	var fwd_in: float = 0.0
	var turn_in: int = 0
	if not scripted.is_empty():
		fwd_in = float(scripted.get("fwd", 0.0))
		turn_in = int(scripted.get("turn", 0))
	elif world == null or (bool(world.get("interactions_enabled")) and not _map_open()):
		if Input.is_action_pressed(&"p1_jump") or Input.is_action_pressed(&"p2_jump"):
			fwd_in += 1.0
		if Input.is_action_pressed(&"p1_crouch") or Input.is_action_pressed(&"p2_crouch"):
			fwd_in -= 1.0
		if Input.is_action_pressed(&"p1_left") or Input.is_action_pressed(&"p2_left"):
			turn_in -= 1
		if Input.is_action_pressed(&"p1_right") or Input.is_action_pressed(&"p2_right"):
			turn_in += 1
	# Quay mũi theo nấc (chỉ khi thân mới vừa chỗ).
	if turn_in != 0:
		_turn_time -= delta
		if _turn_time <= 0.0:
			_turn_time = TURN_TIME
			var h: int = posmod(heading + turn_in, HEADINGS)
			if footprint_clear(center, h):
				heading = h
			else:
				_bump(false)
	else:
		_turn_time = 0.0
	var fwd: Vector2 = dir_of(heading)
	var right := Vector2(-fwd.y, fwd.x)
	var vf: float = vel.dot(fwd)
	var vl: float = vel.dot(right)
	if fwd_in > 0.0:
		vf = minf(vf + THRUST * fwd_in * delta, MAX_FWD)
	elif fwd_in < 0.0:
		if vf > 5.0:
			vf = maxf(vf - BRAKE * delta, 0.0)
		else:
			vf = maxf(vf - THRUST * 0.6 * delta, -MAX_REV)
	else:
		vf -= vf * DRAG * delta
		if absf(vf) < 2.0:
			vf = 0.0
	vl -= vl * minf(LAT_DAMP * delta, 1.0)
	vel = fwd * vf + right * vl
	throttle = absf(fwd_in)
	var step: Vector2 = vel * delta
	var before: Vector2 = center
	if step.length_squared() > 0.0:
		var goal: Vector2 = center + step
		var nudged: Variant = null
		if not footprint_clear(goal, heading):
			nudged = _nudge(goal, right)
		if nudged == null and footprint_clear(goal, heading):
			center = goal
		elif nudged != null:
			center = nudged
		elif footprint_clear(center + Vector2(step.x, 0.0), heading):
			center += Vector2(step.x, 0.0)
			vel.y *= -0.25
			_bump(true)
		elif footprint_clear(center + Vector2(0.0, step.y), heading):
			center += Vector2(0.0, step.y)
			vel.x *= -0.25
			_bump(true)
		else:
			vel *= -0.25
			_bump(true)
	trip_px += center.distance_to(before)
	_update_sound()


## Kênh hẹp: thử lách ngang 1..NUDGE_PX px (hai phía) để thân vừa nước – trả về vị trí mới hoặc null.
func _nudge(goal: Vector2, right: Vector2) -> Variant:
	for k in range(1, NUDGE_PX + 1):
		for side in [1.0, -1.0]:
			var p: Vector2 = goal + right * float(k) * side
			if footprint_clear(p, heading):
				return p
	return null


func _bump(hard: bool) -> void:
	bumps += 1
	if _bump_cd > 0.0:
		return
	_bump_cd = 0.7
	if hard and vel.length() > 20.0:
		Audio.sfx(&"splash", -10.0, 0.9)


func _update_sound() -> void:
	if _emitter.stream == null:
		return
	var speed01: float = clampf(vel.length() / MAX_FWD, 0.0, 1.0)
	_emitter.position = Vector2(0, -12)
	_emitter.pitch_scale = 0.75 + 0.45 * maxf(speed01, throttle * 0.4)
	_emitter.volume_db = -8.0 + 7.0 * maxf(speed01, throttle * 0.5)
	if _emitter.stream_paused:
		_emitter.stream_paused = false


## Cập nhật ảnh, gốc Y-sort, độ nghiêng, nhấp nhô.
func _apply_view() -> void:
	var view: String = view_of(heading)
	var bob: float = roundf(sin(_time * 2.4) * 0.6) if vel.length() < 20.0 else 0.0
	var c: Vector2 = center.round()
	match view:
		"east", "west":
			var k: float = shear_of(heading)
			_sprite.texture = _tex_east if view == "east" else _tex_west
			var anchor := Vector2(117, 50) if view == "east" else Vector2(76, 50)
			_sprite.position = -anchor + Vector2(0, bob)
			# Gốc Y-sort = điểm thấp nhất của mép nước sau khi nghiêng → người đứng ở đuôi luôn sau mạn gần.
			var sort_off: float = absf(k) * 76.0 + 1.0
			position = c + Vector2(0, sort_off)
			_holder.transform = Transform2D(Vector2(1, k), Vector2(0, 1), Vector2(0, -sort_off))
		_:
			_sprite.texture = _tex_north if view == "north" else _tex_south
			var h: float = float(VERT_LEN) / 2.0
			var top: float = -h if view == "north" else -h - float(_ns_tail)
			_sprite.position = Vector2(-VERT_W / 2.0, top + bob)
			# Nhìn dọc: người lái đứng trên sàn thuyền → thuyền vẽ trước người (gốc Y-sort ở trên mũi/đuôi).
			position = c + Vector2(0, -h - 24.0)
			_holder.transform = Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(0, h + 24.0))


## Vệt sóng: chữ V sau đuôi + gợn hai bên mạn khi chạy; đứng yên thì gợn nhẹ quanh thân.
func _draw_wake() -> void:
	if not moored:
		return
	var speed: float = vel.length()
	var water := Color(0.88, 0.96, 1.0, 0.6)
	var fwd: Vector2 = dir_of(heading)
	var view: String = view_of(heading)
	var half_len: float = 72.0 if (view == "east" or view == "west") else 26.0
	var k: float = shear_of(heading)
	var axis: Vector2 = Vector2(1, k).normalized() * (1.0 if view == "east" else -1.0) if (view == "east" or view == "west") else fwd
	var stern: Vector2 = center - axis * half_len
	if speed < 15.0:
		var swing: float = roundf(sin(_time * 2.2))
		var faint := Color(water.r, water.g, water.b, 0.3)
		for side in [-1.0, 1.0]:
			var n: Vector2 = Vector2(-axis.y, axis.x) * float(side) * (6.0 + swing)
			_wake.draw_line((center + axis * 20.0 + n).round(), (center + axis * 34.0 + n).round(), faint, 1.0)
			_wake.draw_line((center - axis * 30.0 + n).round(), (center - axis * 16.0 + n).round(), faint, 1.0)
		return
	var back: Vector2 = -axis
	if vel.dot(axis) < 0.0:
		stern = center + axis * half_len # lùi: sóng dồn ở mũi
		back = axis
	var side_n := Vector2(-back.y, back.x)
	var strength: float = clampf(speed / MAX_FWD, 0.2, 1.0)
	for i in range(6):
		var phase: float = fmod(_time * 1.8 + float(i) / 6.0, 1.0)
		var d: float = 4.0 + phase * 70.0 * strength
		var spread: float = 3.0 + phase * 22.0 * strength
		var a: float = water.a * (1.0 - phase)
		var col := Color(water.r, water.g, water.b, a)
		var base: Vector2 = stern + back * d
		for side in [-1.0, 1.0]:
			var p: Vector2 = base + side_n * side * spread
			_wake.draw_line(p.round(), (p + back * 5.0 + side_n * side * 2.0).round(), col, 1.0)
	# bọt trắng ở chân vịt
	var foam := Color(1, 1, 1, 0.75 * strength)
	_wake.draw_rect(Rect2((stern + back * 3.0 - Vector2(3, 1)).round(), Vector2(6, 2)), foam)
