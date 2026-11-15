class_name World
extends Node2D

## Chế độ Exploration (GDD 3.5, 8.1): toàn bộ xã Bình Kê hai bờ sông (Màn A–F).
## Bản đồ hiển thị bằng MapView (đủ 96 frame, Y-sort với nhân vật). Nhân vật chỉ đi 4 hướng,
## có thể chạy xe máy và đi đò ngang qua sông.
## Va chạm = layer 05_Collision của file art + các ô bổ sung bên dưới; hai cây cầu qua kênh được mở lối.

signal interact_requested(id: StringName)

const MAP_SIZE: Vector2i = Vector2i(1280, 1080)
const SPAWN: Vector2 = Vector2(131, 206)
const CAMERA_ZOOM: float = 3.0

## Layer 05_Collision trong file art chưa phủ nhà/hàng rào/NPC ở bờ bắc, nên bổ sung tại đây.
## Mỗi ô: x, y, rộng, cao (pixel bản đồ).
const EXTRA_BLOCKERS: Array[Rect2i] = [
	Rect2i(0, 0, 1280, 14),          # mép trên bản đồ
	Rect2i(228, 14, 1052, 26),       # hàng bụi cây phía trên
	Rect2i(28, 10, 196, 100),        # nhà chính
	Rect2i(2, 170, 110, 16),         # hàng rào nhà (trái cổng)
	Rect2i(150, 170, 108, 16),       # hàng rào nhà (phải cổng)
	Rect2i(35, 128, 47, 24),         # lu nước
	Rect2i(232, 70, 46, 42),         # chuồng gà
	Rect2i(310, 40, 176, 86),        # tiệm tạp hóa
	Rect2i(328, 142, 44, 32),        # bàn ghế 1
	Rect2i(412, 146, 40, 28),        # bàn ghế 2
	Rect2i(456, 168, 30, 26),        # người ở tiệm
	Rect2i(394, 178, 20, 14),        # con mèo
	Rect2i(545, 165, 30, 25),        # gốc cây lớn
	Rect2i(300, 236, 26, 16),        # người gọi điện
	Rect2i(208, 256, 28, 16),        # ông câu cá
	Rect2i(130, 250, 30, 14),        # chó vàng
	Rect2i(672, 30, 276, 130),       # đình
	Rect2i(822, 160, 30, 20),        # Chú Tư
	Rect2i(760, 170, 62, 34),        # xe đẩy
	Rect2i(862, 182, 26, 12),        # ghế đá 1
	Rect2i(902, 182, 26, 12),        # ghế đá 2
	Rect2i(985, 140, 30, 20),        # gốc cây + cờ
	Rect2i(1033, 40, 239, 90),       # nhà vườn
	Rect2i(1138, 130, 24, 22),       # cô áo trắng
	Rect2i(1040, 182, 176, 18),      # hàng rào nhà vườn
	Rect2i(910, 246, 92, 16),        # rào đấu trường (trên, trái cổng)
	Rect2i(1040, 246, 90, 16),       # rào đấu trường (trên, phải cổng)
	Rect2i(908, 246, 10, 112),       # rào trái
	Rect2i(1122, 246, 10, 112),      # rào phải
	Rect2i(908, 344, 224, 14),       # rào dưới
	Rect2i(922, 328, 60, 18),        # khán giả trái
	Rect2i(1062, 328, 60, 18),       # khán giả phải
	Rect2i(1052, 286, 28, 18),       # MC
	Rect2i(954, 262, 26, 18),        # Tèo
]

## Layer va chạm của file art đánh dấu cả cầu là nước; mở lối đi trên cầu.
const OPEN_RECTS: Array[Rect2i] = [
	Rect2i(632, 558, 92, 44),        # cầu bê tông qua kênh (đường dừa)
	Rect2i(626, 770, 90, 36),        # cầu khỉ tre
	Rect2i(448, 262, 24, 129),       # cầu ván bến đò bờ bắc (A_cau_van_ben_ghe + nối dài)
	Rect2i(448, 469, 24, 52),        # cầu tàu bến đò bờ nam (C_cau_tau_ben_do)
	Rect2i(18, 728, 110, 13),        # cầu ván ra chòi cá tra (C_ca_tra_cau_van), chỉ mặt ván
]
## Chỗ đứng lên/xuống đò: đầu cầu ván phía sông của mỗi bờ.
const FERRY_NORTH: Vector2 = Vector2(460, 384)
const FERRY_SOUTH: Vector2 = Vector2(460, 484)
## Đò của World: đậu sát cầu ván (cùng chỗ đò của bản đồ), gốc node = mép trên thân đò.
const BOAT_X: float = 492.0
const BOAT_TOP_NORTH: float = 373.0
const BOAT_TOP_SOUTH: float = 459.0
const BOAT_DECK: Vector2 = Vector2(0, 29) # chỗ khách đứng (chân), tính từ gốc đò
const BOAT_CROSS_TIME: float = 2.4
const BOAT_STEP_TIME: float = 0.35
const RIVER_MID_Y: float = 430.0
const FERRY_SHEET: Texture2D = preload("res://game/art/world/ferry_rowing.png")
const BIKE_START: Vector2 = Vector2(186, 214)

## "node": vị trí lấy theo NPC động của bản đồ (MapView.node_center + "offset").
## "hint": id hoạt động trong Activities; còn lượt hôm nay thì có dấu "!" nhấp nháy khi lại gần.
const INTERACTABLES: Array[Dictionary] = [
	{"id": &"home", "pos": Vector2(131, 196), "radius": 16.0, "label": "Về nhà"},
	{"id": &"co_ba", "pos": Vector2(470, 202), "radius": 26.0, "label": "Tiệm tạp hóa Cô Ba"},
	{"id": &"chu_tu", "pos": Vector2(838, 188), "radius": 26.0, "label": "Nói chuyện với Chú Tư"},
	{"id": &"teo", "pos": Vector2(968, 288), "radius": 26.0, "label": "Nói chuyện với Tèo"},
	{"id": &"arena", "pos": Vector2(1020, 305), "radius": 22.0, "label": "Vào sới Ao Làng"},
	{"id": &"cat", "pos": Vector2(404, 196), "radius": 14.0, "label": "Con mèo"},
	{"id": &"fisher", "pos": Vector2(222, 252), "radius": 20.0, "label": "Ông câu cá"},
	{"id": &"ferry_north", "pos": FERRY_NORTH, "radius": 12.0, "label": "Lên đò qua sông"},
	{"id": &"ferry_south", "pos": FERRY_SOUTH, "radius": 12.0, "label": "Lên đò về xóm"},
	{"id": &"lottery", "pos": Vector2(87, 586), "node": "NV_co_ban_ve_so", "offset": Vector2(0, 20),
		"radius": 22.0, "label": "Cô bán vé số", "hint": &"lottery"},
	{"id": &"school", "pos": Vector2(899, 740), "radius": 20.0, "label": "Trường TH Bình Kê – hỏi bài cô giáo", "hint": &"school"},
	{"id": &"site", "pos": Vector2(1146, 784), "radius": 18.0, "label": "Công trường – phụ bốc gạch", "hint": &"site"},
	{"id": &"farm", "pos": Vector2(418, 946), "radius": 20.0, "label": "Ruộng lúa chín – gặt thử", "hint": &"farm"},
	{"id": &"temple", "pos": Vector2(900, 1046), "radius": 20.0, "label": "Lư hương đền làng – thắp nhang", "hint": &"temple"},
	{"id": &"fish_house", "pos": Vector2(112, 737), "radius": 12.0, "label": "Chòi cá tra – cho cá ăn, kéo vó", "hint": &"fish"},
]
const MARKER_TARGETS: Dictionary = {
	&"home": Vector2(131, 168), &"co_ba": Vector2(470, 150), &"chu_tu": Vector2(838, 130),
	&"teo": Vector2(968, 232), &"arena": Vector2(1020, 258),
}
const ActivitiesScript := preload("res://game/world/activities.gd")

signal ferry_departed(to_south: bool)
signal ferry_arrived(to_south: bool)

const Audio := preload("res://game/audio/audio_director.gd")
## Vật thể chuyển động trên bản đồ có tiếng máy: [tên node MapView, tên âm thanh, khoảng nghe xa nhất (px), dB].
const SOUND_SOURCES: Array = [
	["A_xe_may_con_tay_do", &"npc_bike", 250.0, -5.0], ["A_xe_may_cho_ga", &"npc_bike", 250.0, -7.0],
	["C_xe_may_cho_dua", &"npc_bike", 250.0, -7.0], ["C_xe_may_con_tay_den", &"npc_bike", 250.0, -5.0],
	["song_vo_lai_1_boc_dau", &"boat", 330.0, -4.0], ["song_vo_lai_2", &"boat", 330.0, -6.0],
]
## Đua xe bí mật: chạy xe máy cùng chiều, sát bên một xe NPC trên đường làng (bám theo ≥ RACE_PACE_TIME giây)
## rồi vượt lên trước → phát race_challenge(tên node) cho main.gd mở hội thoại thách đua. Không có dấu hiệu gì.
## Hướng chạy của từng xe (suy từ frame trong map_layers.json): xem game/world/race/race_riders.gd.
signal race_challenge(node_name: String)
const RACE_BIKES: Dictionary = {
	"A_xe_may_con_tay_do": 1, "A_xe_may_cho_ga": -1, "C_xe_may_cho_dua": 1, "C_xe_may_con_tay_den": -1,
}
const RACE_ROAD_DY: float = 45.0       # chân người chơi cách mép dưới (bánh xe) xe NPC tối đa (px)
const RACE_NEAR_DX: float = 90.0       # bám theo: tâm cách nhau tối đa (px) theo phương ngang
const RACE_PACE_TIME: float = 0.8      # thời gian chạy kè liên tục trước khi vượt (s)
const RACE_PASS_MARGIN: float = 24.0   # vượt = tâm người chơi vượt tâm xe NPC hơn chừng này theo hướng chạy
const RACE_COOLDOWN: float = 45.0      # sau khi thách (đua xong hay từ chối) phải chờ (s)
const RACE_MOVE_GRACE: float = 0.15    # khung hình không nhích (render nhanh hơn 60 Hz) vẫn tính là đang chạy

## Mặt ván gỗ (tiếng bước chân khác): hai cầu ván bến đò, cầu khỉ tre, cầu ván chòi cá tra.
const WOOD_RECTS: Array[Rect2i] = [
	Rect2i(448, 262, 24, 129), Rect2i(448, 469, 24, 52), Rect2i(626, 770, 90, 36), Rect2i(18, 728, 110, 13),
]

var player: WorldPlayer
var map_view: MapView
var bike_pos: Vector2 = BIKE_START
var _bike_node: Node2D
var objective_text: String = ""
var marker_target: StringName = &""
## false khi đang chơi hoạt động: tắt nhắc [E] và tương tác của World (mini-game tự đọc phím).
var interactions_enabled: bool = true
## Đò ngang duy nhất của World (thay cho đò chạy vòng của bản đồ). Gốc = mép trên thân đò.
var ferry_boat: Node2D
var ferry_moving: bool = false
var ferry_at_north: bool = true

var _ferry_sprite: Sprite2D
var _ferry_wake: Node2D
var _ferry_busy: bool = false
var _ferry_dir: float = 0.0 # +1 đi xuống (nam), -1 đi lên (bắc), 0 đang đậu
var _ferry_bob: float = 0.0
var _solid: PackedByteArray
var _camera: Camera2D
var _ui: CanvasLayer
var _prompt: Label
var _status: Label
var _objective: Label
var _marker: Node2D
var _nearby: StringName = &""
var _time: float = 0.0
var _emitters: Array = [] # [tên node, AudioStreamPlayer2D]
## Còn bao nhiêu giây nữa mới được thách đua lại (main.gd đặt sau mỗi lần thách).
var race_cooldown: float = 0.0
var _race_pace: Dictionary = {} # tên xe → số giây đã chạy kè liên tục
var _race_last_x: float = NAN
var _race_dir: int = 0
var _race_dir_time: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var collision_image: Image = (load("res://game/art/collision.png") as Texture2D).get_image()
	if collision_image.is_compressed():
		collision_image.decompress()
	collision_image.convert(Image.FORMAT_L8)
	_solid = collision_image.get_data()

	map_view = MapView.new()
	add_child(map_view)
	player = WorldPlayer.new()
	player.world = self
	player.position = SPAWN
	map_view.add_actor(player)
	_bike_node = WorldPlayer.make_parked_bike() # xe Dream đỗ, gốc ở điểm chạm đất
	_bike_node.position = bike_pos
	map_view.add_actor(_bike_node)
	_build_ferry()
	_build_sound_sources()
	ferry_departed.connect(func(_south: bool) -> void:
		Audio.sfx(&"ferry_creak", -4.0)
		Audio.sfx(&"paddle", -6.0))
	ferry_arrived.connect(func(_south: bool) -> void: Audio.sfx(&"ferry_creak", -6.0, 0.9))
	# Cầu ván cá tra: sort theo mặt ván để người đi trên cầu được vẽ đè lên ván và lan can.
	map_view.set_node_sort_y("C_ca_tra_cau_van", 727.0)
	# Cầu ván bến đò cũng là mặt sàn để đi: sort theo mép trên để người đứng trên cầu không bị ván che.
	map_view.set_node_sort_y("A_cau_van_ben_ghe", 262.0)
	map_view.set_node_sort_y("A_cau_van_noi_dai", 359.0)
	map_view.set_node_sort_y("C_cau_tau_ben_do", 469.0)

	_marker = Node2D.new()
	_marker.z_index = 30
	_marker.draw.connect(_draw_marker)
	add_child(_marker)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = MAP_SIZE.x
	_camera.limit_bottom = MAP_SIZE.y
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_camera.position = Vector2(0, -28)
	player.add_child(_camera)
	_build_ui()


## Đò của bản đồ chạy vòng qua sông bất kể người chơi → ẩn hẳn, World tự quản một chiếc đò.
## Ảnh đò: game/art/world/ferry_rowing.png (3 khung chèo, lấy từ đò của bản đồ, bỏ người khách
## ngồi mũi để nhân vật đứng vào chỗ đó; ông lái ngồi đuôi).
func _build_ferry() -> void:
	map_view.set_node_hidden("song_do_ngang", true)
	map_view.set_node_hidden("song_do_ngang_gon", true)
	ferry_boat = Node2D.new()
	ferry_boat.name = "FerryBoat"
	_ferry_sprite = Sprite2D.new()
	_ferry_sprite.texture = FERRY_SHEET
	_ferry_sprite.hframes = 3
	_ferry_sprite.centered = false
	_ferry_sprite.position = Vector2(-20, 0)
	ferry_boat.add_child(_ferry_sprite)
	map_view.add_actor(ferry_boat)
	_ferry_wake = Node2D.new()
	_ferry_wake.name = "FerryWake"
	_ferry_wake.draw.connect(_draw_ferry_wake)
	map_view.add_ground(_ferry_wake)
	_place_boat(player.position.y < RIVER_MID_Y)


func _place_boat(north: bool) -> void:
	ferry_at_north = north
	ferry_boat.position = Vector2(BOAT_X, BOAT_TOP_NORTH if north else BOAT_TOP_SOUTH)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.04, 0.03, 0.6)
	panel.position = Vector2(10, 10)
	panel.size = Vector2(430, 78)
	_ui.add_child(panel)
	_status = _label(Vector2(22, 16), 17, Color.WHITE, false)
	_objective = _label(Vector2(22, 44), 17, Color(1.0, 0.85, 0.35), true)
	_prompt = _label(Vector2.ZERO, 20, Color(1.0, 0.92, 0.5), true)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -250.0
	_prompt.offset_left = -300.0
	_prompt.offset_right = 300.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var help := _label(Vector2.ZERO, 14, Color(0.9, 0.9, 0.9, 0.8), false)
	help.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	help.offset_left = -430.0
	help.offset_top = -30.0
	help.text = "WASD di chuyển · E tương tác / lên-xuống xe máy"


func _label(pos: Vector2, font_size: int, color: Color, bold: bool) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_override("font", DialogBox.make_font(bold))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	_ui.add_child(label)
	return label


func set_active(active: bool) -> void:
	visible = active
	_ui.visible = active
	_camera.enabled = active
	if active:
		_camera.make_current()
		_camera.reset_smoothing()
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	for entry in _emitters:
		(entry[1] as AudioStreamPlayer2D).stream_paused = true # _update_audio bật lại khi World chạy


func set_status(status: String, objective: String, target: StringName) -> void:
	_status.text = status
	_objective.text = "➤ " + objective
	marker_target = target


func is_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= MAP_SIZE.x or y >= MAP_SIZE.y:
		return true
	var point := Vector2i(x, y)
	for rect in OPEN_RECTS:
		if rect.has_point(point):
			return false
	if _solid[y * MAP_SIZE.x + x] > 0:
		return true
	for rect in EXTRA_BLOCKERS:
		if rect.has_point(point):
			return true
	return false


func _process(delta: float) -> void:
	_time += delta
	_update_ferry(delta)
	_update_audio()
	_update_race_detect(delta)
	_nearby = &""
	if player.can_move and interactions_enabled:
		for item in INTERACTABLES:
			if player.position.distance_to(interactable_pos(item)) <= float(item["radius"]):
				_nearby = item["id"]
				_prompt.text = "[E] %s" % String(item["label"])
				break
		if _nearby == &"" and not player.riding and _bike_node.visible and player.position.distance_to(bike_pos) <= 26.0:
			_nearby = &"bike"
			_prompt.text = "[E] Lên xe máy"
		elif _nearby == &"" and player.riding:
			_prompt.text = "[E] Xuống xe"
	_prompt.visible = interactions_enabled and (_nearby != &"" or (player.riding and player.can_move))
	_marker.queue_redraw()


## Vị trí hiện tại của một điểm tương tác (NPC đi lại thì bám theo NPC trên bản đồ).
func interactable_pos(item: Dictionary) -> Vector2:
	if item.has("node") and map_view != null:
		var center: Variant = map_view.node_center(String(item["node"]))
		if center != null:
			return (center as Vector2) + (item.get("offset", Vector2.ZERO) as Vector2)
	return item["pos"]


func find_interactable(id: StringName) -> Dictionary:
	for item in INTERACTABLES:
		if item["id"] == id:
			return item
	return {}


func _draw_marker() -> void:
	if interactions_enabled:
		_draw_activity_hints()
	if marker_target == &"" or not MARKER_TARGETS.has(marker_target):
		return
	var p: Vector2 = MARKER_TARGETS[marker_target] + Vector2(0, sin(_time * 5.0) * 3.0)
	var arrow := PackedVector2Array([p + Vector2(-6, -8), p + Vector2(6, -8), p])
	_marker.draw_colored_polygon(arrow, Color(1.0, 0.85, 0.2))
	_marker.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), Color(0.3, 0.15, 0.0), 1.0)


## Dấu "!" nhỏ trên các điểm hoạt động còn lượt hôm nay, hiện khi người chơi lại gần (≤ 150 px).
func _draw_activity_hints() -> void:
	for item in INTERACTABLES:
		if not item.has("hint") or not ActivitiesScript.is_available(item["hint"]):
			continue
		var pos: Vector2 = interactable_pos(item)
		var distance: float = player.position.distance_to(pos)
		if distance > 150.0 or distance <= float(item["radius"]):
			continue
		var p: Vector2 = (pos + Vector2(0, -34 + roundf(sin(_time * 4.0 + pos.x) * 2.0))).round()
		_marker.draw_rect(Rect2(p + Vector2(-4, -9), Vector2(9, 12)), Color(0.25, 0.12, 0.0, 0.85))
		_marker.draw_rect(Rect2(p + Vector2(-3, -8), Vector2(7, 10)), Color(1.0, 0.95, 0.75, 0.95))
		_marker.draw_rect(Rect2(p + Vector2(0, -7), Vector2(1, 5)), Color(0.85, 0.35, 0.1))
		_marker.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), Color(0.85, 0.35, 0.1))


func _unhandled_input(event: InputEvent) -> void:
	if not player.can_move or not interactions_enabled or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_E:
		return
	get_viewport().set_input_as_handled()
	if _nearby == &"bike":
		mount_bike(true)
	elif _nearby != &"":
		interact_requested.emit(_nearby)
	elif player.riding:
		mount_bike(false)


func mount_bike(on: bool) -> void:
	if on:
		_bike_node.visible = false
		player.set_riding(true)
	else:
		bike_pos = player.position
		_bike_node.position = bike_pos
		_bike_node.scale.x = -1.0 if player.facing.x < 0 else 1.0 # xe đỗ quay theo hướng vừa chạy
		_bike_node.visible = true
		player.set_riding(false)


## Đi đò ngang: bước từ đầu cầu ván xuống đò, ông lái chèo qua sông, bước lên cầu ván bờ bên kia.
## Người (và xe máy nếu đang chạy) đứng ở mũi đò, luôn được vẽ trên đò (gốc Y-sort của đò = mép trên).
## Đò ở lại bờ đến. Kết thúc: người đứng ở FERRY_SOUTH/FERRY_NORTH (đi được), can_move = true.
func ride_ferry(to_south: bool) -> void:
	if _ferry_busy:
		return
	_ferry_busy = true
	player.can_move = false
	_place_boat(to_south) # đò luôn chờ ở bờ xuất phát
	var target: Vector2 = FERRY_SOUTH if to_south else FERRY_NORTH
	# 1. Bước xuống đò (nhảy nhẹ).
	await _hop(player.position, ferry_boat.position + BOAT_DECK)
	# 2. Chèo qua sông; người đứng trên đò di chuyển theo đò.
	ferry_moving = true
	_ferry_dir = 1.0 if to_south else -1.0
	ferry_departed.emit(to_south)
	var tween := create_tween()
	tween.tween_method(_set_boat_y, ferry_boat.position.y, BOAT_TOP_SOUTH if to_south else BOAT_TOP_NORTH,
		BOAT_CROSS_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	ferry_moving = false
	_ferry_dir = 0.0
	ferry_at_north = not to_south
	# 3. Bước lên cầu ván bờ bên kia.
	await _hop(player.position, target)
	player.position = target
	player.can_move = true
	_ferry_busy = false
	ferry_arrived.emit(to_south)


func _set_boat_y(y: float) -> void:
	ferry_boat.position.y = roundf(y)
	player.position = ferry_boat.position + BOAT_DECK + Vector2(0, _ferry_bob)


func _hop(from: Vector2, to: Vector2) -> void:
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		player.position = (from.lerp(to, t) + Vector2(0, -sin(t * PI) * 5.0)).round(), 0.0, 1.0, BOAT_STEP_TIME)
	await tween.finished


## Đò đậu nhấp nhô nhẹ; chèo thì đổi khung mái chèo. Nếu người chơi ở bờ bên kia (vd. vừa tải game)
## thì đò dời sang bờ của người chơi.
func _update_ferry(delta: float) -> void:
	if ferry_boat == null:
		return
	if not _ferry_busy:
		var player_north: bool = player.position.y < RIVER_MID_Y
		if player_north != ferry_at_north:
			_place_boat(player_north)
	_ferry_bob = roundf(sin(_time * 2.2) * 0.6)
	_ferry_sprite.position.y = _ferry_bob
	if ferry_moving:
		_ferry_sprite.frame = [0, 1, 2, 1][int(_time * 6.0) % 4]
	else:
		_ferry_sprite.frame = 0
	_ferry_wake.queue_redraw()


## Gợn sóng quanh đò (lớp mặt nước, dưới đò): đậu thì gợn hai bên mạn, chạy thì vệt sóng chữ V sau đuôi.
func _draw_ferry_wake() -> void:
	var top: Vector2 = ferry_boat.position
	var water := Color(0.86, 0.95, 1.0, 0.55)
	var faint := Color(0.86, 0.95, 1.0, 0.3)
	if _ferry_dir == 0.0:
		var swing: float = roundf(sin(_time * 2.2) * 1.0)
		for side in [-1.0, 1.0]:
			var x: float = top.x + side * (18.0 + swing)
			_ferry_wake.draw_line(Vector2(x, top.y + 14), Vector2(x, top.y + 22), faint, 1.0)
			_ferry_wake.draw_line(Vector2(x + side, top.y + 34), Vector2(x + side, top.y + 44), faint, 1.0)
		_ferry_wake.draw_line(Vector2(top.x - 6 - swing, top.y + 60), Vector2(top.x + 6 + swing, top.y + 60), faint, 1.0)
		return
	# Đuôi đò = phía ngược hướng chạy.
	var stern_y: float = top.y - 1.0 if _ferry_dir > 0.0 else top.y + 60.0
	var back: float = -_ferry_dir
	for k in range(4):
		var phase: float = fmod(_time * 1.6 + float(k) * 0.25, 1.0)
		var spread: float = 4.0 + phase * 16.0
		var y: float = roundf(stern_y + back * (2.0 + phase * 22.0))
		var color := Color(water.r, water.g, water.b, water.a * (1.0 - phase))
		_ferry_wake.draw_line(Vector2(top.x - spread, y), Vector2(top.x - spread + 5.0, y), color, 1.0)
		_ferry_wake.draw_line(Vector2(top.x + spread - 5.0, y), Vector2(top.x + spread, y), color, 1.0)
	for side in [-1.0, 1.0]:
		_ferry_wake.draw_line(Vector2(top.x + side * 17.0, top.y + 10), Vector2(top.x + side * 18.0, top.y + 50), faint, 1.0)


# =================================================================== âm thanh môi trường

func is_wood(pos: Vector2) -> bool:
	var point := Vector2i(pos)
	for rect in WOOD_RECTS:
		if rect.has_point(point):
			return true
	return false


## Gắn nguồn âm 2D vào xe máy NPC và vỏ lái trên bản đồ: xe chạy ngang thì nghe tiếng máy lớn dần rồi xa dần.
func _build_sound_sources() -> void:
	for source in SOUND_SOURCES:
		if not map_view.has_node_named(String(source[0])):
			continue
		var emitter: AudioStreamPlayer2D = Audio.make_emitter(source[1], float(source[2]), float(source[3]))
		emitter.stream_paused = true
		add_child(emitter)
		_emitters.append([String(source[0]), emitter])


## Mỗi frame: đặt nguồn âm theo vật thể, và chỉnh các lớp âm nền theo chỗ người chơi đang đứng.
func _update_audio() -> void:
	for entry in _emitters:
		var emitter: AudioStreamPlayer2D = entry[1]
		var center: Variant = map_view.node_center(entry[0])
		emitter.stream_paused = center == null
		if center != null:
			emitter.position = center
	var p: Vector2 = player.position
	# Sông lớn y ≈ 280–515; ao cá tra và ruộng nước cũng có tiếng nước nhẹ.
	var river_gap: float = maxf(0.0, maxf(280.0 - p.y, p.y - 515.0))
	var river: float = clampf(1.0 - river_gap / 150.0, 0.0, 1.0) * 0.85
	if Rect2(35, 668, 270, 162).grow(40.0).has_point(p):
		river = maxf(river, 0.5)
	var in_fields: bool = Rect2(24, 846, 574, 224).has_point(p)
	var on_water: bool = river_gap == 0.0 and (ferry_moving or (p.y > 300.0 and p.y < 500.0))
	Audio.ambience_layer(&"river", river)
	Audio.ambience_layer(&"birds", 0.35 if on_water else (0.85 if in_fields else 0.65))
	Audio.ambience_layer(&"leaves", 0.3 if on_water else 0.5)
	Audio.ambience_layer(&"village", 0.25 if p.y > 620.0 else 0.6)
	Audio.ambience_layer(&"crickets", 0.25 if in_fields else 0.0)
	Audio.ambience_layer(&"crowd", 0.0)


# =================================================================== đua xe bí mật

## Được phép dò thách đua không: đang ngồi xe, đi được, không có hội thoại/hoạt động/đò, hết thời gian chờ.
func race_eligible() -> bool:
	return player.riding and player.can_move and interactions_enabled and not _ferry_busy and not ferry_moving \
		and race_cooldown <= 0.0 and visible


## Gọi sau mỗi lần thách đua (đua xong hoặc từ chối) để khỏi bị thách liên tục.
func start_race_cooldown(seconds: float = RACE_COOLDOWN) -> void:
	race_cooldown = seconds
	_race_pace.clear()


## Mỗi frame: hướng chạy ngang của người chơi (suy từ vị trí, vì player.gd tự đọc phím) + khung xe NPC.
func _update_race_detect(delta: float) -> void:
	race_cooldown = maxf(race_cooldown - delta, 0.0)
	var x: float = player.position.x
	if not is_nan(_race_last_x) and x != _race_last_x:
		_race_dir = 1 if x > _race_last_x else -1
		_race_dir_time = 0.0
	else:
		_race_dir_time += delta
	_race_last_x = x
	if not race_eligible():
		_race_pace.clear()
		return
	var move_dir: int = _race_dir if _race_dir_time <= RACE_MOVE_GRACE else 0
	var bikes: Dictionary = {}
	for bike_name in RACE_BIKES:
		bikes[bike_name] = map_view.node_rect(bike_name)
	var overtaken: String = race_detect_step(delta, player.position, move_dir, bikes)
	if overtaken != "":
		start_race_cooldown() # khoá ngay để không phát hai lần; main.gd đặt lại sau hội thoại
		race_challenge.emit(overtaken)


## Một bước dò thuần logic (test bơm thẳng vị trí/thời gian). bikes: tên xe → Rect2 hiện tại (null = đang khuất).
## move_dir: −1/0/+1 hướng người chơi đang chạy ngang. Trả về tên xe vừa bị vượt, hoặc "".
## Luật: cùng đường (|chân − mép dưới xe| ≤ RACE_ROAD_DY), cùng chiều, kè bên/sau xe (lệch tâm theo hướng chạy
## trong [−RACE_NEAR_DX, RACE_PASS_MARGIN]) liên tục ≥ RACE_PACE_TIME, rồi vượt lên quá RACE_PASS_MARGIN
## (nhưng chưa xa hơn RACE_NEAR_DX). Sai một điều kiện là tính lại từ đầu.
func race_detect_step(delta: float, player_pos: Vector2, move_dir: int, bikes: Dictionary) -> String:
	for bike_name in bikes:
		var rect: Variant = bikes[bike_name]
		var dir: int = int(RACE_BIKES.get(bike_name, 0))
		if rect == null or dir == 0 or move_dir != dir:
			_race_pace.erase(bike_name)
			continue
		var box: Rect2 = rect
		if absf(player_pos.y - box.end.y) > RACE_ROAD_DY:
			_race_pace.erase(bike_name)
			continue
		var ahead: float = (player_pos.x - box.get_center().x) * float(dir)
		if ahead >= -RACE_NEAR_DX and ahead <= RACE_PASS_MARGIN:
			_race_pace[bike_name] = float(_race_pace.get(bike_name, 0.0)) + delta
		elif ahead > RACE_PASS_MARGIN and ahead <= RACE_NEAR_DX and float(_race_pace.get(bike_name, 0.0)) >= RACE_PACE_TIME:
			_race_pace.clear()
			return String(bike_name)
		else:
			_race_pace.erase(bike_name)
	return ""
