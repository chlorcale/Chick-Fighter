class_name World
extends Node2D

## Chế độ Exploration (GDD 3.5, 8.1): toàn xã Bình Kê trên bản đồ mở rộng 5120×2160 – xóm cũ hai bờ sông
## (Màn A–F, nguyên toạ độ cũ ở góc trên-trái 1280×1080), chợ nổi + Chợ Bình Kê, trường THPT, khu dân cư,
## kênh rạch, con sông phía nam, xe khô gà Lão Gà Khô (sân chợ phía đông), Sân gà Liên tỉnh và Sân gà Olympia (tranh của
## chủ dự án). Xe máy / vỏ lãi đã tách khỏi bản đồ (game/art/world_map/traffic.json) và chạy lúc chơi bằng Traffic
## (game/world/traffic.gd: nhường người chơi/người đi bộ, giữ khoảng cách, tiếng máy theo xe); người đi đường trong tranh
## đi lại bằng Pedestrians (game/world/pedestrians.gd); người chơi lái vỏ lãi từ các bến (game/world/player_boat.gd).
## Bản đồ hiển thị bằng MapView (đủ 96 frame, Y-sort với nhân vật). Nhân vật chỉ đi 4 hướng,
## có thể chạy xe máy và đi đò ngang qua sông.
## Va chạm = game/art/world_map/collision.png (layer 05_Collision của file art + các sửa lỗi tích hợp đã "nướng" sẵn
## lúc dựng: ô chặn/mở lối của bản đồ cũ, cầu ván/bến, công trình mới – xem tools/art/build_world_map.py).
## Chỉ đường: mũi tên mục tiêu (ngoài màn hình thì mũi tên ở mép màn hình + tên + khoảng cách), bản đồ lớn phím M,
## bản đồ nhỏ góc trái phím N, bảng chỉ đường ở các ngã ba (đọc bằng E).
## Camera: thu phóng theo nấc (ViewSettings.ZOOM_STEPS, mặc định ×2,5) bằng con lăn chuột hoặc phím − / = (cả − / + bàn
## phím số), chuyển mượt, vị trí camera làm tròn theo pixel màn hình (pixel art không rung), nhớ mức đã chọn.

signal interact_requested(id: StringName)
## Xe máy đỗ / vỏ lãi neo đổi chỗ hoặc người chơi lên/xuống (bản đồ M của UI đọc bike_pos, bike_parked, boat_moored_pos()).
signal vehicles_changed
## Sự kiện thành tích (UI ánh xạ sang thành tích): visit_market, visit_lao_ga_kho, visit_lien_tinh, visit_olympia,
## visit_thpt, visit_temple, visit_catfish (mỗi lần bước VÀO khu), first_bike (lên xe máy), first_boat (lên vỏ lãi),
## boat_under_bridge (vỏ lãi chui vào dưới một cầu), bike_over_bridge (chạy xe lên một cầu), boat_long_trip (một chuyến
## vỏ lãi ≥ BOAT_LONG_TRIP px, một lần mỗi chuyến), race_triggered (bị thách đua), honked_at (xe NPC bóp kèn người chơi).
signal achievement_event(id: StringName)

const MAP_SIZE: Vector2i = Vector2i(5120, 2160)
const SPAWN: Vector2 = Vector2(131, 206)
## Mức thu phóng mặc định (nấc thật lấy từ ViewSettings – nhớ giữa các lần chơi).
const CAMERA_ZOOM: float = 2.5
## Bảng trạng thái: chiều rộng tối đa của một dòng chữ (px) trước khi xuống dòng.
const STATUS_MAX_W: float = 680.0
## Dải nhắc phím góc dưới phải.
const HELP_KEYS: Array = [["WASD", "Đi"], ["E", "Tương tác · lên/xuống xe"], ["M", "Bản đồ"], ["N", "Bản đồ nhỏ"], ["V", "Sổ tay"]]
const ViewSettings := preload("res://game/world/view_settings.gd")
## Tốc độ chuyển mượt giữa hai nấc thu phóng (1/giây) và tốc độ camera bám theo người chơi.
const ZOOM_LERP: float = 12.0
const CAMERA_FOLLOW: float = 8.0
const CAMERA_OFFSET: Vector2 = Vector2(0, -28)
## 1 pixel bản đồ = 0,25 m (người cao ~45 px ≈ 1,6 m nhìn chéo) – dùng cho khoảng cách hiển thị.
const METERS_PER_PX: float = 0.25

const COLLISION_PATH: String = "res://game/art/world_map/collision.png"
const WATER_PATH: String = "res://game/art/world_map/water.png"
const NAV_PATH: String = "res://game/art/world_map/nav.png"
const NAV_CELL: int = 4
## Bổ sung lúc chạy (đa số đã "nướng" vào collision.png khi dựng). Mỗi ô: x, y, rộng, cao (pixel bản đồ).
const EXTRA_BLOCKERS: Array[Rect2i] = []
## Cầu ván qua mương ruộng (N_cau_van_muong__01..04) chỉ một tấm ván 14 px: nới lối đi/chạy xe 18 px (đủ thân xe máy ±8 px).
const OPEN_RECTS: Array[Rect2i] = [
	Rect2i(436, 1551, 18, 22), Rect2i(436, 1611, 18, 22), Rect2i(434, 1671, 18, 22), Rect2i(427, 1731, 18, 22),
]
## Cầu hẹp (cầu khỉ tre, cầu ván một tấm, cầu ván ao): đi/chạy xe qua thì người lắc lư nhẹ (chỉ hình). Rect + biên độ.
const WOBBLE_BRIDGES: Array = [
	[Rect2(2976, 1865, 21, 157), 1.0], [Rect2(4741, 1617, 56, 21), 1.0], [Rect2(621, 765, 92, 51), 1.0],
	[Rect2(4040, 1640, 56, 16), 0.6], [Rect2(1389, 376, 28, 151), 0.45],
	[Rect2(436, 1551, 18, 22), 0.8], [Rect2(436, 1611, 18, 22), 0.8], [Rect2(434, 1671, 18, 22), 0.8], [Rect2(427, 1731, 18, 22), 0.8],
]
## Ông câu cá: tranh vẽ ông quay lưng ra nước → thay bằng sprite quay mặt ra sông/ao (game/art/world_map/fisher_front.png,
## tools/art/world_map_fixes.py; 2 khung nhấp nhô như tranh, gốc khung = góc trên-trái node bản đồ).
const FISHER_SHEET_PATH: String = "res://game/art/world_map/fisher_front.png"
const FISHER_NODES: Array[String] = ["NV_ong_cau_ca", "N_npc_ong_cau_ca_ao_sen"]
## Khu "đã ghé" cho sự kiện thành tích (toạ độ bản đồ).
const VISIT_AREAS: Dictionary = {
	&"visit_market": Rect2(2000, 650, 1180, 600),
	&"visit_lao_ga_kho": Rect2(2900, 860, 180, 220),
	&"visit_lien_tinh": Rect2(4316, 806, 356, 300),
	&"visit_olympia": Rect2(4771, 1122, 349, 320),
	&"visit_thpt": Rect2(4330, 120, 520, 260),
	&"visit_temple": Rect2(800, 960, 200, 120),
	&"visit_catfish": Rect2(15, 690, 200, 80),
}
const BOAT_LONG_TRIP: float = 2000.0
## Xe máy / vỏ lãi ở xa hơn chừng này (và ngoài khung hình) thì có mũi tên nhỏ ở mép màn hình.
const VEHICLE_ARROW_MIN: float = 160.0
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
## Đò chỉ dời sang bờ người chơi khi người chơi ở khu bến đò cũ (không phải ở chợ hay bờ sông phía nam).
const FERRY_AREA: Rect2 = Rect2(0, 180, 1300, 470)
const FERRY_SHEET: Texture2D = preload("res://game/art/world/ferry_rowing.png")
const BIKE_START: Vector2 = Vector2(186, 214)

## Địa danh (bản đồ lớn, mục tiêu chỉ đường). "pos" = chỗ đứng trước cửa (đi tới được), "icon" = kiểu biểu tượng.
const PLACES: Dictionary = {
	&"home": {"name": "Nhà mình", "pos": Vector2(131, 196), "icon": "home"},
	&"co_ba": {"name": "Tạp hóa Cô Ba", "pos": Vector2(470, 202), "icon": "shop"},
	&"dinh": {"name": "Đình làng", "pos": Vector2(818, 200), "icon": "temple"},
	&"arena": {"name": "Sới Ao Làng", "pos": Vector2(1020, 305), "icon": "arena"},
	&"ferry": {"name": "Bến đò ngang", "pos": Vector2(460, 384), "icon": "boat"},
	&"school": {"name": "Trường TH Bình Kê", "pos": Vector2(899, 740), "icon": "school"},
	&"site": {"name": "Công trường", "pos": Vector2(1146, 784), "icon": "site"},
	&"temple": {"name": "Đền làng", "pos": Vector2(900, 1046), "icon": "temple"},
	&"market": {"name": "Chợ Bình Kê", "pos": Vector2(2480, 960), "icon": "market"},
	&"floating_market": {"name": "Chợ nổi", "pos": Vector2(2700, 730), "icon": "boat"},
	&"cat_shop": {"name": "Xe khô gà Lão Gà Khô", "pos": Vector2(2968, 1044), "icon": "cart"},
	&"thpt": {"name": "Trường THPT Bình Kê", "pos": Vector2(4540, 313), "icon": "school"},
	&"arena_lien_tinh": {"name": "Sân gà Liên tỉnh miền Tây", "pos": Vector2(4508, 1080), "icon": "arena"},
	&"arena_olympic": {"name": "Sân gà Olympia – Olympic Đá Gà", "pos": Vector2(4938, 1413), "icon": "star"},
}

## "node": vị trí lấy theo NPC động của bản đồ (MapView.node_center + "offset").
## "hint": id hoạt động trong Activities; còn lượt hôm nay thì có dấu "!" nhấp nháy khi lại gần.
## "sign": bảng chỉ đường – World tự hiện bảng hướng đi, không phát interact_requested.
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
	# trò phụ mới (game/world/minigames/**): bờ kênh phía đông ông câu cá, bờ đê trên ruộng lúa chín
	{"id": &"cau_ca_loc", "pos": Vector2(345, 252), "radius": 16.0, "label": "Bờ kênh – câu cá lóc", "hint": &"cau_ca_loc"},
	{"id": &"tha_dieu", "pos": Vector2(480, 842), "radius": 18.0, "label": "Bờ đê ruộng – thả diều", "hint": &"tha_dieu"},
	# --- khu mới
	{"id": &"cat_shop", "pos": Vector2(2968, 1044), "radius": 22.0, "label": "Lão Gà Khô – khô gà lá chanh"},
	{"id": &"market_chicken", "pos": Vector2(3124, 985), "radius": 16.0, "label": "Sạp gà giống"},
	{"id": &"market_eggs", "pos": Vector2(3134, 1050), "radius": 16.0, "label": "Sạp trứng gà, trứng vịt"},
	{"id": &"market_food", "pos": Vector2(2812, 1002), "radius": 16.0, "label": "Sạp gạo, lúa, cám"},
	{"id": &"market_gear", "pos": Vector2(2840, 1170), "radius": 16.0, "label": "Sạp đồ nghề – cựa sắt, mào sắt"},
	{"id": &"thpt", "pos": Vector2(4540, 313), "radius": 26.0, "label": "Cổng trường THPT Bình Kê"},
	# cổng hai sân của chủ dự án: Liên tỉnh – dưới biển "SÂN GÀ LIÊN TỈNH"; Olympia – trước hàng người chờ dưới biển
	# "SÂN GÀ OLYMPIA" (cổng chặn ngưỡng, không vào sới – xem tools/art/world_map_extras.py ARENAS)
	{"id": &"arena_lien_tinh", "pos": Vector2(4508, 1080), "radius": 24.0, "label": "Vào Sân gà Liên tỉnh miền Tây"},
	{"id": &"arena_olympic", "pos": Vector2(4938, 1413), "radius": 26.0, "label": "Vào Sân gà Olympia (Olympic Đá Gà)"},
	{"id": &"npc_ba_lan", "pos": Vector2(3746, 762), "node": "N_npc_ba_Lan_ban_com", "offset": Vector2(0, 30),
		"radius": 20.0, "label": "Nói chuyện với bà Lan bán cơm"},
	{"id": &"npc_chu_bay", "pos": Vector2(1672, 352), "node": "N_npc_chu_quan_vong", "offset": Vector2(0, 30),
		"radius": 20.0, "label": "Nói chuyện với chú Bảy quán võng"},
	{"id": &"npc_ong_tam", "pos": Vector2(2180, 1688), "node": "N_npc_danh_co_tuong", "offset": Vector2(0, 26),
		"radius": 22.0, "label": "Coi ông Tám đánh cờ tướng"},
	{"id": &"npc_ong_sau", "pos": Vector2(4076, 1659), "node": "N_npc_ong_cau_ca_ao_sen", "offset": Vector2(0, 30),
		"radius": 22.0, "label": "Nói chuyện với ông Sáu câu cá"},
	{"id": &"npc_chu_muoi", "pos": Vector2(4426, 1804), "node": "N_npc_chu_vuon_kieng", "offset": Vector2(0, 32),
		"radius": 20.0, "label": "Nói chuyện với chú Mười vườn kiểng"},
	# --- bảng chỉ đường (World tự xử lý)
	{"id": &"sign_village", "pos": Vector2(1296, 194), "radius": 16.0, "label": "Đọc bảng chỉ đường", "sign": true},
	{"id": &"sign_south_road", "pos": Vector2(1300, 560), "radius": 16.0, "label": "Đọc bảng chỉ đường", "sign": true},
	{"id": &"sign_market_nw", "pos": Vector2(1986, 802), "radius": 16.0, "label": "Đọc bảng chỉ đường", "sign": true},
	{"id": &"sign_market_se", "pos": Vector2(3186, 1254), "radius": 16.0, "label": "Đọc bảng chỉ đường", "sign": true},
	{"id": &"sign_bridge", "pos": Vector2(3648, 548), "radius": 16.0, "label": "Đọc bảng chỉ đường", "sign": true},
	{"id": &"sign_east", "pos": Vector2(4324, 1087), "radius": 16.0, "label": "Đọc bảng chỉ đường", "sign": true},
	{"id": &"sign_thpt", "pos": Vector2(3975, 353), "radius": 16.0, "label": "Đọc bảng chỉ đường", "sign": true},
]
## Điểm đặt mũi tên nhấp nhô (trên đầu NPC/cửa) cho các mục tiêu cũ; mục tiêu khác dùng PLACES/INTERACTABLES.
const MARKER_TARGETS: Dictionary = {
	&"home": Vector2(131, 168), &"co_ba": Vector2(470, 150), &"chu_tu": Vector2(838, 130),
	&"teo": Vector2(968, 232), &"arena": Vector2(1020, 258),
	&"cat_shop": Vector2(2990, 916), # trên đầu mèo Lão Gà Khô (mũi tên mặc định −40 px sẽ đè lên bụi mía/hũ khô gà)
	&"arena_lien_tinh": Vector2(4495, 1020), &"arena_olympic": Vector2(4938, 1325), # trên biển tên cổng hai sân gà
}
## Bảng chỉ đường: các địa danh được ghi trên bảng (theo PLACES).
const SIGN_TARGETS: Dictionary = {
	&"sign_village": [&"home", &"market", &"arena_lien_tinh", &"thpt"],
	&"sign_south_road": [&"market", &"school", &"arena_olympic", &"home"],
	&"sign_market_nw": [&"market", &"cat_shop", &"home", &"arena_lien_tinh"],
	&"sign_market_se": [&"arena_lien_tinh", &"arena_olympic", &"market", &"cat_shop"],
	&"sign_bridge": [&"thpt", &"market", &"arena_lien_tinh", &"arena_olympic"],
	&"sign_east": [&"arena_lien_tinh", &"arena_olympic", &"thpt", &"market"],
	&"sign_thpt": [&"thpt", &"market", &"home", &"arena_olympic"],
}
const ActivitiesScript := preload("res://game/world/activities.gd")
const MarketCrowdScript := preload("res://game/world/market_crowd.gd")
const MapOverlayScript := preload("res://game/world/world_map_overlay.gd")
const DayNightScript := preload("res://game/world/day_night.gd")
const TrafficScript := preload("res://game/world/traffic.gd")
const PedestriansScript := preload("res://game/world/pedestrians.gd")
const PlayerBoatScript := preload("res://game/world/player_boat.gd")
## Bến lái vỏ lãi: đứng trong bán kính này quanh "pos" của bến (traffic.json docks) thì có nhắc [E].
const DOCK_RADIUS: float = 16.0
## Lên bờ ở bến: điểm thân thuyền gần "water_pos" của bến hơn chừng này.
const DOCK_LEAVE_RADIUS: float = 40.0
## Lên bờ chỗ bất kỳ: tìm chỗ đứng được (bờ đất nối với xóm) trong bán kính này quanh chỗ người lái.
const BANK_RADIUS: float = 36.0

signal ferry_departed(to_south: bool)
signal ferry_arrived(to_south: bool)

const Audio := preload("res://game/audio/audio_director.gd")
## Tiếng máy xe máy / vỏ lãi NPC: Traffic gắn nguồn âm 2D vào các xe thật gần người chơi (thay cho nguồn âm gắn node
## bản đồ cũ – các node đó đã tách khỏi tranh).
## Đua xe bí mật: chạy xe máy cùng chiều, sát bên một xe NPC "racer" (4 tay lái gốc, 6 tay đua có tên trên xe dáng mới,
## mọi xe máy NPC có cờ racer – traffic.gd) bám theo ≥ RACE_PACE_TIME giây rồi vượt lên trước → phát
## race_challenge(khoá tay lái) cho main.gd mở hội thoại thách đua. Dấu hiệu: đang kè ≥ RACE_CUE_TIME giây thì dấu "!"
## nhảy trên đầu tay lái và xe nẹt pô (khói + tiếng rú); chờ RACE_COOLDOWN giây giữa hai lần thách.
## Hướng chạy của từng xe (suy từ frame của manifest bản đồ): xem game/world/race/race_riders.gd.
## Nguồn khung xe: race_bike_source (Callable → Dictionary tên tay lái → Rect2/null) – World gắn Traffic.race_bike_rects
## (4 xe "race_rider" chạy thật trên đường làng rồi sang đường T1/T2); bỏ trống thì tra node bản đồ cùng tên (không còn).
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

## Mặt ván gỗ (tiếng bước chân khác): hai cầu ván bến đò, cầu khỉ tre, cầu ván chòi cá tra, cầu gỗ/bến khu mới.
const WOOD_RECTS: Array[Rect2i] = [
	Rect2i(448, 262, 24, 129), Rect2i(448, 469, 24, 52), Rect2i(626, 770, 90, 36), Rect2i(18, 728, 110, 13),
	Rect2i(1389, 376, 28, 151), Rect2i(1716, 453, 23, 163), Rect2i(2480, 620, 23, 80), Rect2i(2940, 615, 23, 80),
	Rect2i(2976, 1865, 21, 157), Rect2i(1077, 1927, 23, 156), Rect2i(4741, 1617, 56, 21),
]
## Vùng ồn ào (tiếng người): chợ + kè chợ nổi, hai sới.
const CROWD_RECTS: Array[Rect2] = [
	Rect2(2000, 650, 1180, 600), Rect2(4316, 806, 356, 300), Rect2(4771, 1122, 337, 300), Rect2(908, 246, 224, 112),
]
## Xe khô gà Lão Gà Khô (layer của chủ dự án N_lao_ga_kho_xe_kho_ga_la_chanh, 8 khung × 80 ms): đi ngang qua thì thỉnh
## thoảng lão rao một câu (bong bóng chữ trên đầu mèo). RNG riêng – không đụng GameState.rng.
const LAO_NODE: String = "N_lao_ga_kho_xe_kho_ga_la_chanh"
const LAO_BARK_ANCHOR: Vector2 = Vector2(2990, 920)
const LAO_BARK_RADIUS: float = 90.0
const LAO_BARK_CHANCE: float = 0.6
const LAO_BARK_COOLDOWN: float = 25.0
const LAO_BARK_TIME: float = 2.6
const LAO_BARKS: Array[String] = [
	"Hí hí… hu hu! Khô gà lá chanh đâyyy!",
	"Khô gà nè! Cay cay, thơm lá chanh!",
	"Hu hu… ngon quá trời ngon!",
	"Có Khô Gà hông? Lão mua 50 ngàn một ký!",
	"Hí hí! Mua một hũ, cười cả tuần!",
]

var player: WorldPlayer
var map_view: MapView
var market_crowd: Node2D
var map_overlay: CanvasLayer
var bike_pos: Vector2 = BIKE_START
## true khi xe máy đang đỗ trên bản đồ (người chơi không ngồi trên xe).
var bike_parked: bool = true
var _bike_node: Node2D
## Thành tích: khu đang đứng trong (để chỉ phát khi bước vào), đang trên cầu (xe / thuyền), chuyến thuyền đã báo chưa.
var _visit_in: Dictionary = {}
var _visit_check: float = 0.0
var _bike_on_bridge: bool = false
var _boat_was_under: bool = false
var _trip_told: bool = false
var _honk_cd: float = 0.0
var _fishers: Array = [] # [Node2D gốc, Sprite2D]
var _wobble_t: float = 0.0
## Đua xe: xe đang được "kè" (hiện dấu "!" + nẹt pô) và thời gian.
var race_cue_key: String = ""
var _race_cue_rect: Rect2 = Rect2()
var _race_cue_time: float = 0.0
var _race_rev_cd: float = 0.0
var objective_text: String = ""
var marker_target: StringName = &""
## Câu nhắc [E] theo ngữ cảnh do main.gd đặt (id → chữ), vd. "Vô lớp – Thứ 3 sáng", "Sới Liên tỉnh – vòng 2 tối nay".
var label_overrides: Dictionary = {}
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
var _nav: PackedByteArray
var _nav_size: Vector2i
var _camera: Camera2D
## Thu phóng: mức đang hiện (chuyển mượt) và nấc đích; vị trí camera tự làm mượt (không dùng smoothing của Camera2D để
## làm tròn theo pixel màn hình được).
var zoom_target: float = CAMERA_ZOOM
var _zoom_now: float = CAMERA_ZOOM
var _cam_pos: Vector2 = Vector2.ZERO
var _zoom_toast: Label
var _zoom_toast_time: float = 0.0
var _ui: CanvasLayer
var _prompt: Label
var _prompt_art: Control
var _status: Label
var _objective: Label
var _status_panel: PanelContainer
var _help: Control
var _marker: Node2D
var _edge: Control
var _sign_panel: Label
var _sign_time: float = 0.0
var _nearby: StringName = &""
var _time: float = 0.0
## Giao thông, người đi bộ, vỏ lãi của người chơi.
var traffic: Node2D
var pedestrians: Node2D
var player_boat: Node2D
## true khi người chơi đang lái vỏ lãi (player.can_move = false, vị trí người chơi theo chỗ đứng trên thuyền).
var boating: bool = false
var _boat_busy: bool = false
var _water: PackedByteArray
var _docks: Array = [] # Dictionary của traffic.json
var _bank_spot: Variant = null
var _bank_check: int = 0
## Còn bao nhiêu giây nữa mới được thách đua lại (main.gd đặt sau mỗi lần thách).
var race_cooldown: float = 0.0
## Callable() → Dictionary {tên tay lái (RACE_BIKES) → Rect2 khung xe hiện tại hoặc null}. Hệ thống giao thông gắn vào.
var race_bike_source: Callable = Callable()
## Callable() → Dictionary {khoá tay lái → +1/−1 hướng chạy hiện tại} cho các xe không có trong RACE_BIKES.
var race_dir_source: Callable = Callable()
var _race_pace: Dictionary = {} # tên xe → số giây đã chạy kè liên tục
var _race_last_x: float = NAN
var _race_dir: int = 0
var _race_dir_time: float = 0.0
## Thời gian dựng World (ms) – báo cáo/test.
var build_ms: float = 0.0
var _bark: Label
var _bark_time: float = 0.0
var _bark_cooldown: float = 0.0
var _bark_near: bool = false
var _bark_rng := RandomNumberGenerator.new()


func _ready() -> void:
	var t0: int = Time.get_ticks_usec()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_solid = _load_l8(COLLISION_PATH)
	_nav = _load_l8(NAV_PATH)
	_nav_size = MAP_SIZE / NAV_CELL
	_water = _load_l8(WATER_PATH) if ResourceLoader.exists(WATER_PATH) else PackedByteArray()
	_docks = MapView.traffic_data().get("docks", [])

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
	_build_fishers()

	market_crowd = MarketCrowdScript.new()
	market_crowd.set("world", self)
	add_child(market_crowd)
	traffic = TrafficScript.new()
	traffic.name = "Traffic"
	traffic.set("world", self)
	add_child(traffic)
	race_bike_source = Callable(traffic, "race_bike_rects")
	race_dir_source = Callable(traffic, "race_bike_dirs")
	player_boat = PlayerBoatScript.new()
	player_boat.name = "PlayerBoat"
	player_boat.set("world", self)
	map_view.add_actor(player_boat)
	map_view.add_ground(player_boat.call("wake_node"))
	pedestrians = PedestriansScript.new()
	pedestrians.name = "Pedestrians"
	pedestrians.set("world", self)
	add_child(pedestrians)

	_marker = Node2D.new()
	_marker.z_index = 30
	_marker.draw.connect(_draw_marker)
	add_child(_marker)

	ViewSettings.ensure_loaded()
	zoom_target = ViewSettings.zoom_level
	_zoom_now = zoom_target
	_camera = Camera2D.new()
	_camera.name = "WorldCamera"
	_camera.top_level = true # World tự đặt vị trí (bám người chơi, làm mượt, làm tròn theo pixel màn hình)
	_camera.zoom = Vector2(_zoom_now, _zoom_now)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = MAP_SIZE.x
	_camera.limit_bottom = MAP_SIZE.y
	_camera.position_smoothing_enabled = false
	player.add_child(_camera)
	snap_camera()
	_build_ui()
	map_overlay = MapOverlayScript.new()
	map_overlay.set("world", self)
	add_child(map_overlay)
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## Ảnh xám (nhập dạng Image, không lên GPU) → mảng byte L8.
static func _load_l8(path: String) -> PackedByteArray:
	var res: Resource = load(path)
	var image: Image = res as Image
	if image == null and res is Texture2D:
		image = (res as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_L8:
		image.convert(Image.FORMAT_L8)
	return image.get_data()


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
	# Bảng trạng thái (gỗ sẫm, chữ kem ×2) + dải mục tiêu (giấy, chữ mực ×2) – UISkin, tự co giãn theo chữ.
	_status_panel = UISkin.status_panel()
	_status_panel.position = Vector2(10, 10)
	_ui.add_child(_status_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_child(column)
	_status = UISkin.label("", UISkin.FS_BODY, UISkin.CREAM, false, 4)
	column.add_child(_status)
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UISkin.objective_style())
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(strip)
	_objective = UISkin.label("", UISkin.FS_BODY, UISkin.INK_RED, false)
	strip.add_child(_objective)
	# Nhắc phím [E]: Label giữ chữ (test/logic đọc .text, .visible) nhưng không tự vẽ; con _prompt_art vẽ phím gỗ.
	_prompt = _label(Vector2.ZERO, UISkin.FS_BODY, UISkin.INK, false)
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_prompt.self_modulate = Color(1, 1, 1, 0)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -250.0
	_prompt.offset_left = -300.0
	_prompt.offset_right = 300.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var prompt_art := Control.new()
	prompt_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	prompt_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_art.draw.connect(func() -> void:
		if _prompt.text == "":
			return
		var ps: Vector2 = UISkin.prompt_size(_prompt.text)
		UISkin.draw_prompt(prompt_art, Vector2(roundf((prompt_art.size.x - ps.x) * 0.5), 0.0), _prompt.text))
	_prompt.add_child(prompt_art)
	_prompt.item_rect_changed.connect(prompt_art.queue_redraw)
	_prompt_art = prompt_art
	# Dải nhắc phím góc dưới phải (chữ ×1 đậm, phím gỗ).
	var help := Control.new()
	help.set_anchors_preset(Control.PRESET_FULL_RECT)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.draw.connect(func() -> void:
		UISkin.draw_key_hints(help, help.size - Vector2(10, 8), HELP_KEYS))
	help.resized.connect(help.queue_redraw)
	UISkin.pixel(help)
	_ui.add_child(help)
	_help = help
	# Mũi tên mục tiêu ở mép màn hình (khi mục tiêu nằm ngoài khung hình).
	_edge = Control.new()
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.draw.connect(_draw_edge_arrow)
	UISkin.pixel(_edge)
	_ui.add_child(_edge)
	# Bảng chỉ đường (đọc bằng E): khung gỗ + giấy giữa màn hình, tự tắt sau vài giây hoặc khi đi xa.
	_sign_panel = _label(Vector2.ZERO, UISkin.FS_BODY, UISkin.INK, false)
	_sign_panel.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_sign_panel.set_anchors_preset(Control.PRESET_CENTER)
	_sign_panel.offset_left = -360.0
	_sign_panel.offset_right = 360.0
	_sign_panel.offset_top = -250.0
	_sign_panel.offset_bottom = -20.0
	_sign_panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sign_panel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sign_panel.add_theme_stylebox_override("normal", UISkin.panel_style(&"wood"))
	_sign_panel.visible = false
	# Bong bóng rao hàng của Lão Gà Khô (vị trí màn hình cập nhật mỗi frame theo đầu xe).
	_bark = _label(Vector2.ZERO, UISkin.FS_BODY, UISkin.INK, false)
	_bark.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_bark.add_theme_stylebox_override("normal", UISkin.panel_style(&"tooltip", 4.0))
	_bark.visible = false
	# Thông báo nấc thu phóng ("Thu phóng ×2,5"), hiện ngắn khi đổi.
	_zoom_toast = _label(Vector2.ZERO, UISkin.FS_BODY, UISkin.CREAM, true)
	_zoom_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_zoom_toast.add_theme_stylebox_override("normal", UISkin.panel_style(&"dark", 2.0))
	_zoom_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_zoom_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_zoom_toast.offset_left = 0.0
	_zoom_toast.offset_right = 0.0
	_zoom_toast.offset_top = 96.0
	_zoom_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_toast.visible = false


func _label(pos: Vector2, font_size: int, color: Color, bold: bool) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_override("font", DialogBox.make_font(bold))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UISkin.label_shadow(label, 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UISkin.pixel(label)
	_ui.add_child(label)
	return label


## Hộp thoại của main đang mở (ẩn nhắc [E] + dải phím để khỏi ló sau khung thoại).
func _talking() -> bool:
	var parent: Node = get_parent()
	var dlg: Variant = parent.get("dialog") if parent != null else null
	return dlg is DialogBox and (dlg as DialogBox).is_open()


## Các vùng HUD cố định (bảng trạng thái, bản đồ nhỏ, đồng hồ) – nhãn mũi tên mép màn hình tránh đè lên.
func _hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [Rect2(_status_panel.position, _status_panel.size).grow(4.0),
		Rect2(_edge.size.x - 290.0, 0.0, 290.0, 104.0)]
	if map_overlay != null and bool(map_overlay.call("minimap_visible")):
		out.append(Rect2(map_overlay.call("minimap_rect")).grow(4.0))
	return out


## Bảng trạng thái: chữ dài quá STATUS_MAX_W thì xuống dòng; co lại vừa chữ; bản đồ nhỏ nằm ngay dưới bảng.
func _layout_status() -> void:
	for label in [_status, _objective]:
		var l := label as Label
		var w: float = UISkin.text_size(l.text, UISkin.FS_BODY).x
		if w > STATUS_MAX_W:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(STATUS_MAX_W, 0)
		else:
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.custom_minimum_size = Vector2.ZERO
	_status_panel.reset_size()
	if map_overlay != null and map_overlay.has_method("set_mini_top"):
		map_overlay.call("set_mini_top", _status_panel.position.y + _status_panel.get_combined_minimum_size().y + 16.0)


func set_active(active: bool) -> void:
	visible = active
	if _ui == null:
		# gọi trước _ready (World chưa vào cây): áp dụng lại khi vào cây
		ready.connect(set_active.bind(active), CONNECT_ONE_SHOT)
		return
	_ui.visible = active
	_camera.enabled = active
	if map_overlay != null:
		map_overlay.call("set_world_active", active)
	if active:
		_camera.make_current()
		snap_camera()
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	# Tiếng máy xe NPC / vỏ lãi tắt ngay (Traffic bật lại khi World chạy).
	if traffic != null:
		traffic.call("set_paused", not active)
	if player_boat != null:
		player_boat.call("pause_sound")


## Dòng trạng thái + mục tiêu. target: id bất kỳ trong MARKER_TARGETS, PLACES hoặc INTERACTABLES (&"" = không chỉ).
func set_status(status: String, objective: String, target: StringName) -> void:
	_status.text = status
	_objective.text = "➤ " + objective
	_objective.get_parent().visible = objective != ""
	_layout_status()
	objective_text = objective
	marker_target = target


func is_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= MAP_SIZE.x or y >= MAP_SIZE.y:
		return true
	if not OPEN_RECTS.is_empty() or not EXTRA_BLOCKERS.is_empty():
		var point := Vector2i(x, y)
		for rect in OPEN_RECTS:
			if rect.has_point(point):
				return false
		for rect in EXTRA_BLOCKERS:
			if rect.has_point(point):
				return true
	if _solid[y * MAP_SIZE.x + x] > 0:
		return true
	# Thân xe máy NPC đang chạy (chỉ xét quanh chân người chơi – đúng phép thử bước đi của WorldPlayer).
	if traffic != null and player != null and not traffic.player_blockers.is_empty() \
			and absf(float(x) - player.position.x) < 24.0 and absf(float(y) - player.position.y) < 16.0:
		var point := Vector2(float(x) + 0.5, float(y) + 0.5)
		for rect in traffic.player_blockers:
			if rect.has_point(point):
				return true
	return false


## Mặt nước đi thuyền được (game/art/world_map/water.png).
func is_water(x: float, y: float) -> bool:
	var xi: int = int(x)
	var yi: int = int(y)
	if _water.is_empty() or xi < 0 or yi < 0 or xi >= MAP_SIZE.x or yi >= MAP_SIZE.y:
		return false
	return _water[yi * MAP_SIZE.x + xi] > 0


## Ô lưới đi 4 px (game/art/world_map/nav.png): bit0 chân đứng được, bit1 xe máy, bit2 mặt đường,
## bit3 mặt nước, bit4 nối liền với SPAWN bằng chân (tính lúc dựng).
func nav_bits(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= _nav_size.x or cell.y >= _nav_size.y:
		return 0
	return _nav[cell.y * _nav_size.x + cell.x]


func nav_size() -> Vector2i:
	return _nav_size


func _process(delta: float) -> void:
	_time += delta
	_update_camera(delta)
	_update_ferry(delta)
	_update_audio()
	_update_race_detect(delta)
	_update_achievements(delta)
	_update_wobble(delta)
	_update_fishers()
	_nearby = &""
	if boating:
		_update_boat_prompt()
	elif player.can_move and interactions_enabled:
		for item in INTERACTABLES:
			if player.position.distance_to(interactable_pos(item)) <= float(item["radius"]):
				_nearby = item["id"]
				_prompt.text = "[E] %s" % String(label_overrides.get(item["id"], item["label"]))
				break
		if _nearby == &"":
			_check_dock_prompt()
		if _nearby == &"" and not player.riding and _bike_node.visible and player.position.distance_to(bike_pos) <= 26.0:
			_nearby = &"bike"
			_prompt.text = "[E] Lên xe máy"
		elif _nearby == &"" and player.riding:
			_prompt.text = "[E] Xuống xe"
	_prompt.visible = interactions_enabled and (_nearby != &"" or (player.riding and player.can_move) or (boating and not _boat_busy)) \
		and not _sign_panel.visible and not _talking()
	if _prompt.visible:
		_prompt_art.queue_redraw()
	_help.visible = not _talking()
	if _sign_panel.visible:
		_sign_time -= delta
		if _sign_time <= 0.0 or not player.can_move:
			_sign_panel.visible = false
	_update_lao_bark(delta)
	map_view.set_focus(player.position)
	_marker.queue_redraw()
	_edge.queue_redraw()


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


## Vị trí (toạ độ bản đồ) của một mục tiêu chỉ đường, hoặc null nếu id không có ở đâu.
func target_position(id: StringName) -> Variant:
	if id == &"":
		return null
	if PLACES.has(id):
		return PLACES[id]["pos"]
	var item: Dictionary = find_interactable(id)
	if not item.is_empty():
		return interactable_pos(item)
	if MARKER_TARGETS.has(id):
		return MARKER_TARGETS[id]
	return null


## Tên hiển thị của mục tiêu.
func target_name(id: StringName) -> String:
	if PLACES.has(id):
		return String(PLACES[id]["name"])
	var item: Dictionary = find_interactable(id)
	if not item.is_empty():
		return String(item["label"]).trim_prefix("Nói chuyện với ").trim_prefix("Vào ")
	return String(id)


## Khoảng cách dễ đọc: "85 m", "1,2 km".
static func format_distance(px: float) -> String:
	var meters: float = px * METERS_PER_PX
	if meters < 995.0:
		return "%d m" % int(roundf(meters / 5.0) * 5.0)
	return ("%.1f km" % (meters / 1000.0)).replace(".", ",")


## Hướng la bàn ngắn (bản đồ: trên = bắc).
static func compass(dir: Vector2) -> String:
	var names: Array[String] = ["Đông", "Đông Nam", "Nam", "Tây Nam", "Tây", "Tây Bắc", "Bắc", "Đông Bắc"]
	var index: int = posmod(int(roundf(dir.angle() / (PI / 4.0))), 8)
	return names[index]


func _draw_marker() -> void:
	if interactions_enabled:
		_draw_activity_hints()
		_draw_vehicle_markers()
	_draw_race_cue()
	var target: Variant = target_position(marker_target)
	if target == null:
		return
	var anchor: Vector2 = MARKER_TARGETS.get(marker_target, (target as Vector2) + Vector2(0, -40))
	var p: Vector2 = anchor + Vector2(0, sin(_time * 5.0) * 3.0)
	var arrow := PackedVector2Array([p + Vector2(-6, -8), p + Vector2(6, -8), p])
	_marker.draw_colored_polygon(arrow, Color(1.0, 0.85, 0.2))
	_marker.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), Color(0.3, 0.15, 0.0), 1.0)


## Toạ độ màn hình của một điểm bản đồ, và khung màn hình hiện tại.
func map_to_screen(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas() * p


## Mũi tên mép màn hình: điểm trên viền khung hình (lề margin) theo hướng từ tâm tới mục tiêu.
## Trả về [vị trí, góc] hoặc [] nếu mục tiêu đang ở trong khung hình (thuần toán – test gọi trực tiếp).
static func edge_arrow(screen_size: Vector2, target_screen: Vector2, margin: float = 46.0) -> Array:
	var inner := Rect2(Vector2(margin, margin), (screen_size - Vector2(margin, margin) * 2.0).max(Vector2.ZERO))
	if inner.has_point(target_screen):
		return []
	var center: Vector2 = screen_size * 0.5
	var dir: Vector2 = target_screen - center
	if dir.length() < 0.001:
		return []
	var half: Vector2 = inner.size * 0.5
	var scale_x: float = half.x / absf(dir.x) if absf(dir.x) > 0.0001 else INF
	var scale_y: float = half.y / absf(dir.y) if absf(dir.y) > 0.0001 else INF
	var pos: Vector2 = center + dir * minf(scale_x, scale_y)
	return [pos, dir.angle()]


func _draw_edge_arrow() -> void:
	if not interactions_enabled or (map_overlay != null and bool(map_overlay.get("open"))):
		return
	_draw_vehicle_edge_arrows()
	var target: Variant = target_position(marker_target)
	if target == null:
		return
	var size: Vector2 = _edge.size
	var arrow: Array = edge_arrow(size, map_to_screen(target))
	if arrow.is_empty():
		return
	var pos: Vector2 = arrow[0]
	var angle: float = arrow[1]
	# Mũi tên rơi vào bảng trạng thái / bản đồ nhỏ / đồng hồ: dời xuống dưới vùng đó (vẫn ở mép màn hình).
	for r in _hud_rects():
		if r.grow(16.0).has_point(pos):
			pos.y = r.end.y + 30.0
	var pulse: float = 1.0 + sin(_time * 6.0) * 0.08
	var tip := Vector2(22, 0).rotated(angle) * pulse
	var side := Vector2(0, 13).rotated(angle) * pulse
	var back := Vector2(-10, 0).rotated(angle) * pulse
	var poly := PackedVector2Array([pos + tip, pos + back + side, pos + back * 0.4, pos + back - side])
	_edge.draw_colored_polygon(poly, Color(1.0, 0.85, 0.2, 0.95))
	_edge.draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0.25, 0.12, 0.0), 2.0)
	var dist: float = player.position.distance_to(target)
	var text: String = "%s · %s" % [target_name(marker_target), format_distance(dist)]
	# Nhãn "Tên · khoảng cách": ô giấy chữ ×2, đặt lùi vào trong so với mũi tên, không tràn mép màn hình.
	var box: Vector2 = UISkin.prompt_size(text)
	var tp: Vector2 = pos - Vector2(22, 0).rotated(angle) * 2.4 - box * 0.5
	tp.x = clampf(tp.x, 8.0, size.x - box.x - 8.0)
	tp.y = clampf(tp.y, 8.0, size.y - box.y - 48.0)
	for r in _hud_rects():
		if r.intersects(Rect2(tp, box)):
			tp.y = r.end.y + 4.0
	UISkin.draw_prompt(_edge, tp, text)


## Mũi tên nhỏ ở mép màn hình chỉ về xe máy đỗ / vỏ lãi neo khi ở xa: huy hiệu + "Xe máy · 120 m" (nhỏ hơn mũi tên
## mục tiêu; chữ đặt lệch vào trong để không chồng lên nhau).
func _draw_vehicle_edge_arrows() -> void:
	var size: Vector2 = _edge.size
	var k: int = 0
	for entry in vehicle_targets():
		var pos: Vector2 = entry["pos"]
		var dist: float = player.position.distance_to(pos)
		if dist < VEHICLE_ARROW_MIN:
			continue
		var arrow: Array = edge_arrow(size, map_to_screen(pos), 30.0)
		if arrow.is_empty():
			continue
		var at: Vector2 = arrow[0]
		var angle: float = arrow[1]
		var tip := Vector2(14, 0).rotated(angle)
		var side := Vector2(0, 8).rotated(angle)
		var back := Vector2(-6, 0).rotated(angle)
		var poly := PackedVector2Array([at + tip, at + back + side, at + back * 0.4, at + back - side])
		var col := Color(0.55, 0.85, 1.0, 0.95) if String(entry["kind"]) == "boat" else Color(1.0, 0.78, 0.35, 0.95)
		_edge.draw_colored_polygon(poly, col)
		_edge.draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0.2, 0.1, 0.03), 2.0)
		var badge: Vector2 = at - Vector2(16, 0).rotated(angle)
		_draw_vehicle_badge(_edge, badge, String(entry["kind"]), 1.6)
		var text: String = "%s · %s" % [String(entry["name"]), format_distance(dist)]
		# chữ ×1 đậm (phụ, nhỏ hơn nhãn mục tiêu) trên nền gỗ sẫm
		var fs: int = UISkin.FS_SMALL
		var tw: float = UISkin.text_size(text, fs, true).x
		var tp: Vector2 = badge - Vector2(16, 0).rotated(angle) * 1.6 - Vector2(tw * 0.5, -5 - k * 24)
		tp.x = clampf(tp.x, 12.0, size.x - tw - 12.0)
		tp.y = clampf(tp.y, 24.0, size.y - 52.0)
		UISkin.draw_panel(_edge, Rect2(tp + Vector2(-8, -17), Vector2(tw + 16, 24)), &"dark")
		UISkin.draw_text(_edge, tp, text, fs, col, true)
		k += 1


## Dấu nhấp nhô trên xe máy đang đỗ và vỏ lãi đang neo (biểu tượng nhỏ trong khung tròn), để dễ tìm lại xe.
func _draw_vehicle_markers() -> void:
	for entry in vehicle_targets():
		var anchor: Vector2 = entry["marker"]
		var p: Vector2 = (anchor + Vector2(0, roundf(sin(_time * 3.2 + anchor.x * 0.01) * 2.0))).round()
		_draw_vehicle_badge(_marker, p, String(entry["kind"]), 1.0)


## [{kind "bike"/"boat", name, pos (chỗ đứng), marker (điểm đặt dấu)}] của xe máy đỗ / vỏ lãi neo hiện có.
func vehicle_targets() -> Array:
	var out: Array = []
	if bike_parked and _bike_node != null and _bike_node.visible:
		out.append({"kind": "bike", "name": "Xe máy", "pos": bike_pos, "marker": bike_pos + Vector2(0, -50)})
	var moored: Variant = boat_moored_pos()
	if moored != null:
		var c: Vector2 = moored
		out.append({"kind": "boat", "name": "Vỏ lãi", "pos": c, "marker": c + Vector2(0, -44)})
	return out


## Huy hiệu tròn có hình xe máy / thuyền (pixel vẽ bằng hình chữ nhật), tâm ở p, đuôi nhọn chỉ xuống. scale: 1 = trên bản đồ,
## ~2 = mép màn hình.
func _draw_vehicle_badge(node: CanvasItem, p: Vector2, kind: String, scale: float) -> void:
	var ink := Color(0.2, 0.1, 0.03)
	var fill := Color(0.55, 0.85, 1.0) if kind == "boat" else Color(1.0, 0.78, 0.35)
	var r: float = 7.0 * scale
	node.draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 5) * scale, p + Vector2(3, 5) * scale, p + Vector2(0, 10) * scale]), ink)
	node.draw_circle(p, r + 1.0 * scale, ink)
	node.draw_circle(p, r, fill)
	var u: float = scale
	if kind == "bike":
		# hai bánh + thân + tay lái
		node.draw_circle(p + Vector2(-3.5, 2.5) * u, 2.0 * u, ink)
		node.draw_circle(p + Vector2(3.5, 2.5) * u, 2.0 * u, ink)
		node.draw_rect(Rect2(p + Vector2(-3, -1) * u, Vector2(6, 2) * u), Color(0.6, 0.14, 0.24))
		node.draw_rect(Rect2(p + Vector2(2, -4) * u, Vector2(1, 4) * u), ink)
		node.draw_rect(Rect2(p + Vector2(1, -4) * u, Vector2(3, 1) * u), ink)
	else:
		# thân thuyền + mũi cong + cần đuôi tôm
		node.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 0) * u, p + Vector2(5, -2) * u, p + Vector2(3, 3) * u,
			p + Vector2(-4, 3) * u]), Color(0.17, 0.39, 0.66))
		node.draw_rect(Rect2(p + Vector2(-4, 0) * u, Vector2(7, 1) * u), Color(0.97, 0.93, 0.77))
		node.draw_line(p + Vector2(-5, 1) * u, p + Vector2(-7, 4) * u, ink, maxf(1.0, u))
		node.draw_rect(Rect2(p + Vector2(-2, -3) * u, Vector2(2, 3) * u), ink)


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


## Nội dung bảng chỉ đường: mỗi dòng "mũi tên  Tên – hướng, khoảng cách" tính từ vị trí bảng.
func sign_text(id: StringName) -> String:
	var item: Dictionary = find_interactable(id)
	var origin: Vector2 = item.get("pos", player.position)
	var lines: Array[String] = ["BẢNG CHỈ ĐƯỜNG – XÃ BÌNH KÊ"]
	for place_id in SIGN_TARGETS.get(id, []):
		var place: Dictionary = PLACES[place_id]
		var d: Vector2 = (place["pos"] as Vector2) - origin
		var arrows: Array[String] = ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
		var arrow: String = arrows[posmod(int(roundf(d.angle() / (PI / 4.0))), 8)]
		lines.append("%s  %s – hướng %s, %s" % [arrow, place["name"], compass(d), format_distance(d.length())])
	return "\n".join(lines)


func _show_sign(id: StringName) -> void:
	_sign_panel.text = sign_text(id)
	_sign_panel.visible = true
	_sign_time = 7.0


func _unhandled_input(event: InputEvent) -> void:
	if _handle_zoom_input(event):
		get_viewport().set_input_as_handled()
		return
	if boating and interactions_enabled and event is InputEventKey:
		var bk := event as InputEventKey
		if bk.pressed and not bk.echo and bk.physical_keycode == KEY_E:
			get_viewport().set_input_as_handled()
			if _nearby != &"":
				leave_boat()
		return
	if not player.can_move or not interactions_enabled or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_E:
		return
	get_viewport().set_input_as_handled()
	if _sign_panel.visible:
		_sign_panel.visible = false
		return
	if _nearby == &"bike":
		mount_bike(true)
	elif String(_nearby).begins_with("dock:") or _nearby == &"boat_moored":
		board_boat()
	elif _nearby != &"":
		var item: Dictionary = find_interactable(_nearby)
		if bool(item.get("sign", false)):
			_show_sign(_nearby)
		else:
			interact_requested.emit(_nearby)
	elif player.riding:
		mount_bike(false)


func mount_bike(on: bool) -> void:
	if on:
		_bike_node.visible = false
		bike_parked = false
		player.set_riding(true)
		achievement_event.emit(&"first_bike")
	else:
		bike_pos = player.position
		_bike_node.position = bike_pos
		_bike_node.scale.x = -1.0 if player.facing.x < 0 else 1.0 # xe đỗ quay theo hướng vừa chạy
		_bike_node.visible = true
		bike_parked = true
		player.set_riding(false)
	vehicles_changed.emit()


## Chỗ vỏ lãi đang neo (tâm thân thuyền, toạ độ bản đồ) – null khi chưa có thuyền neo hoặc người chơi đang lái.
func boat_moored_pos() -> Variant:
	if player_boat == null or boating or not bool(player_boat.get("moored")):
		return null
	return player_boat.get("center")


## Đặt lại xe máy đỗ ở chỗ khác (tải game, cốt truyện) – phát vehicles_changed.
func set_bike_parked_at(pos: Vector2) -> void:
	if player.riding:
		mount_bike(false)
	bike_pos = pos
	_bike_node.position = pos
	vehicles_changed.emit()


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
## thì đò dời sang bờ của người chơi (chỉ khi người chơi ở khu bến đò cũ).
func _update_ferry(delta: float) -> void:
	if ferry_boat == null:
		return
	if not _ferry_busy and not boating and FERRY_AREA.has_point(player.position):
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


# =================================================================== camera + thu phóng

## Con lăn chuột / phím − = (cả bàn phím số) đổi nấc thu phóng. Trả về true nếu đã xử lý.
## Không đổi khi bản đồ lớn (M) đang mở hoặc World không hiện.
func _handle_zoom_input(event: InputEvent) -> bool:
	if not visible or (map_overlay != null and bool(map_overlay.get("open"))):
		return false
	var dir: int = 0
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dir = 1
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dir = -1
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.physical_keycode:
				KEY_EQUAL, KEY_KP_ADD:
					dir = 1
				KEY_MINUS, KEY_KP_SUBTRACT:
					dir = -1
	if dir == 0:
		return false
	step_zoom(dir)
	return true


## Sang nấc kế tiếp (dir > 0 phóng to, < 0 thu nhỏ – thấy rộng hơn); nhớ vào ViewSettings, hiện thông báo ngắn.
func step_zoom(dir: int) -> void:
	set_zoom(ViewSettings.step_zoom(dir))


## Đặt nấc thu phóng (làm tròn về nấc gần nhất). immediate: không chuyển mượt (test/ảnh chụp).
func set_zoom(z: float, immediate: bool = false) -> void:
	ViewSettings.set_zoom(z)
	zoom_target = ViewSettings.zoom_level
	if immediate:
		_zoom_now = zoom_target
		snap_camera()
	if _zoom_toast != null:
		_zoom_toast.text = "Thu phóng %s" % ViewSettings.zoom_text(zoom_target)
		_zoom_toast.visible = true
		_zoom_toast_time = 1.2


## Tâm khung hình mong muốn (theo người chơi), đã kẹp trong bản đồ theo mức thu phóng hiện tại.
func _camera_goal() -> Vector2:
	return _clamp_center(player.position + CAMERA_OFFSET, _zoom_now)


func _clamp_center(center: Vector2, z: float) -> Vector2:
	var half: Vector2 = get_viewport_rect().size / (2.0 * z)
	var lo: Vector2 = half
	var hi: Vector2 = Vector2(MAP_SIZE) - half
	return Vector2(clampf(center.x, lo.x, maxf(lo.x, hi.x)), clampf(center.y, lo.y, maxf(lo.y, hi.y)))


## Đặt camera ngay vào chỗ (không trễ): sau khi dịch chuyển người chơi, đổi cảnh, test.
func snap_camera() -> void:
	if _camera == null or player == null:
		return
	_cam_pos = _camera_goal()
	_apply_camera()


func _update_camera(delta: float) -> void:
	if absf(_zoom_now - zoom_target) > 0.001:
		_zoom_now = lerpf(_zoom_now, zoom_target, clampf(delta * ZOOM_LERP, 0.0, 1.0))
		if absf(_zoom_now - zoom_target) < 0.01:
			_zoom_now = zoom_target
	var goal: Vector2 = _camera_goal()
	if _cam_pos.distance_to(goal) > 400.0:
		_cam_pos = goal # dịch chuyển xa (đò, tải game, test) → nhảy thẳng
	else:
		_cam_pos = _cam_pos.lerp(goal, clampf(delta * CAMERA_FOLLOW, 0.0, 1.0))
	_cam_pos = _clamp_center(_cam_pos, _zoom_now)
	_apply_camera()
	if _zoom_toast != null and _zoom_toast.visible:
		_zoom_toast_time -= delta
		if _zoom_toast_time <= 0.0:
			_zoom_toast.visible = false


## Làm tròn tâm camera theo pixel màn hình ở mức thu phóng hiện tại → ô pixel bản đồ không rung khi camera trôi.
func _apply_camera() -> void:
	_camera.zoom = Vector2(_zoom_now, _zoom_now)
	var half: Vector2 = get_viewport_rect().size * 0.5
	# toạ độ màn hình của gốc bản đồ = half − tâm·z → phải là số nguyên
	var origin: Vector2 = (half - _cam_pos * _zoom_now).round()
	_camera.global_position = (half - origin) / _zoom_now


## Vùng bản đồ camera đang thấy (theo tâm + mức thu phóng World đặt) – test kiểm tra không lộ khoảng trống ngoài bản đồ.
func camera_view_rect() -> Rect2:
	var size: Vector2 = get_viewport_rect().size / _zoom_now
	return Rect2(_camera.global_position - size * 0.5, size)


# =================================================================== Lão Gà Khô rao hàng

## Bước vào gần xe khô gà (≤ LAO_BARK_RADIUS) thì có LAO_BARK_CHANCE lão rao một câu, rồi nghỉ LAO_BARK_COOLDOWN giây.
## force_line ≥ 0: test/ảnh chụp ép hiện ngay câu đó.
func lao_bark(force_line: int = -1) -> void:
	var line: int = force_line if force_line >= 0 else _bark_rng.randi_range(0, LAO_BARKS.size() - 1)
	_bark.text = LAO_BARKS[clampi(line, 0, LAO_BARKS.size() - 1)]
	_bark.visible = true
	_bark_time = LAO_BARK_TIME
	_bark_cooldown = LAO_BARK_COOLDOWN


func _update_lao_bark(delta: float) -> void:
	_bark_cooldown = maxf(_bark_cooldown - delta, 0.0)
	var near: bool = player.position.distance_to(LAO_BARK_ANCHOR) <= LAO_BARK_RADIUS and interactions_enabled
	var ready_to_bark: bool = _bark_cooldown <= 0.0 and player.can_move and map_view.node_rect(LAO_NODE) != null
	if near and not _bark_near and ready_to_bark and _bark_rng.randf() < LAO_BARK_CHANCE:
		lao_bark()
	elif near and not _bark_near:
		_bark_cooldown = maxf(_bark_cooldown, 4.0) # lần này lão im – đi vô lại sau ít giây mới xét tiếp
	_bark_near = near
	if not _bark.visible:
		return
	_bark_time -= delta
	if _bark_time <= 0.0 or not interactions_enabled or not player.can_move:
		_bark.visible = false
		return
	_bark.reset_size()
	var sp: Vector2 = map_to_screen(LAO_BARK_ANCHOR)
	_bark.position = (sp - Vector2(_bark.size.x * 0.5, _bark.size.y + 6.0)).round()


# =================================================================== âm thanh môi trường

func is_wood(pos: Vector2) -> bool:
	var point := Vector2i(pos)
	for rect in WOOD_RECTS:
		if rect.has_point(point):
			return true
	return false


## Gần nước bao nhiêu (0..1): đếm ô nước (bit3 của lưới đi) quanh người chơi trong bán kính ~150 px.
func water_nearness(p: Vector2) -> float:
	var c := Vector2i(p) / NAV_CELL
	var best: float = INF
	for dy in range(-36, 37, 6):
		for dx in range(-36, 37, 6):
			if nav_bits(c + Vector2i(dx, dy)) & 8:
				best = minf(best, Vector2(dx, dy).length() * NAV_CELL)
	return 0.0 if best == INF else clampf(1.0 - best / 150.0, 0.0, 1.0)


## Mỗi frame: đặt nguồn âm theo vật thể, và chỉnh các lớp âm nền theo chỗ người chơi đang đứng.
func _update_audio() -> void:
	var p: Vector2 = player.position
	var river: float = water_nearness(p) * 0.85
	if Rect2(35, 668, 270, 162).grow(40.0).has_point(p):
		river = maxf(river, 0.5)
	var in_fields: bool = Rect2(24, 846, 574, 224).has_point(p) or Rect2(90, 1095, 440, 245).has_point(p)
	var on_water: bool = ferry_moving or boating or (nav_bits(Vector2i(p) / NAV_CELL) & 8) != 0
	var crowd: float = 0.0
	for rect in CROWD_RECTS:
		if rect.grow(60.0).has_point(p):
			crowd = maxf(crowd, 0.55 if rect.has_point(p) else 0.3)
	# Theo giờ (DayNight.ambience_mix): tối thì chim thưa, dế kêu, xóm lặng; chợ vãn người.
	var mix: Dictionary = DayNightScript.ambience_mix()
	Audio.ambience_layer(&"river", river)
	Audio.ambience_layer(&"birds", (0.35 if on_water else (0.85 if in_fields else 0.65)) * float(mix["birds_mult"]))
	Audio.ambience_layer(&"leaves", 0.3 if on_water else 0.5)
	Audio.ambience_layer(&"village", (0.25 if (p.y > 620.0 and p.x < 1280.0) else 0.6) * float(mix["village_mult"]))
	Audio.ambience_layer(&"crickets", maxf(0.25 if in_fields else 0.0, float(mix["crickets_min"])))
	Audio.ambience_layer(&"crowd", crowd * lerpf(1.0, 0.35, float(mix["night"])))


# =================================================================== đua xe bí mật

## Được phép dò thách đua không: đang ngồi xe, đi được, không có hội thoại/hoạt động/đò, hết thời gian chờ.
func race_eligible() -> bool:
	return player.riding and player.can_move and interactions_enabled and not _ferry_busy and not ferry_moving \
		and not boating and race_cooldown <= 0.0 and visible


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
	if race_bike_source.is_valid():
		bikes = race_bike_source.call()
	else:
		for bike_name in RACE_BIKES:
			bikes[bike_name] = map_view.node_rect(bike_name) # null khi node không còn trên bản đồ
	var dirs: Dictionary = race_dir_source.call() if race_dir_source.is_valid() else {}
	var overtaken: String = race_detect_step(delta, player.position, move_dir, bikes, dirs)
	_update_race_cue(delta, bikes)
	if overtaken != "":
		start_race_cooldown() # khoá ngay để không phát hai lần; main.gd đặt lại sau hội thoại
		race_cue_key = ""
		achievement_event.emit(&"race_triggered")
		race_challenge.emit(overtaken)


## Một bước dò thuần logic (test bơm thẳng vị trí/thời gian). bikes: tên xe → Rect2 hiện tại (null = đang khuất).
## move_dir: −1/0/+1 hướng người chơi đang chạy ngang. Trả về tên xe vừa bị vượt, hoặc "".
## Luật: cùng đường (|chân − mép dưới xe| ≤ RACE_ROAD_DY), cùng chiều, kè bên/sau xe (lệch tâm theo hướng chạy
## trong [−RACE_NEAR_DX, RACE_PASS_MARGIN]) liên tục ≥ RACE_PACE_TIME, rồi vượt lên quá RACE_PASS_MARGIN
## (nhưng chưa xa hơn RACE_NEAR_DX). Sai một điều kiện là tính lại từ đầu.
func race_detect_step(delta: float, player_pos: Vector2, move_dir: int, bikes: Dictionary, dirs: Dictionary = {}) -> String:
	for bike_name in bikes:
		var rect: Variant = bikes[bike_name]
		var dir: int = int(dirs.get(bike_name, RACE_BIKES.get(bike_name, 0)))
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


## Dấu hiệu trước khi bị thách: đang kè một xe "racer" đủ RACE_CUE_TIME giây → tay lái ngoái nhìn: dấu "!" nhảy trên
## đầu xe NPC, xe nẹt pô (khói + tiếng máy rú) mỗi ~1 s. Hết kè thì tắt.
const RACE_CUE_TIME: float = 0.3


func _update_race_cue(delta: float, bikes: Dictionary) -> void:
	_race_rev_cd = maxf(_race_rev_cd - delta, 0.0)
	var best: String = ""
	var best_t: float = 0.0
	for key in _race_pace:
		var t: float = float(_race_pace[key])
		if t >= RACE_CUE_TIME and t > best_t and bikes.get(key) != null:
			best = String(key)
			best_t = t
	if best == "":
		race_cue_key = ""
		_race_cue_time = 0.0
		return
	if best != race_cue_key:
		race_cue_key = best
		_race_cue_time = 0.0
	_race_cue_time += delta
	_race_cue_rect = bikes[best]
	if _race_rev_cd <= 0.0:
		_race_rev_cd = 1.1
		Audio.sfx(&"bike_start", -10.0, 1.25)
		var smoke: Variant = player.get("_smoke") if player != null else null
		var dir: int = _race_dir if _race_dir != 0 else 1
		if smoke != null:
			var tail := Vector2(_race_cue_rect.get_center().x - float(dir) * _race_cue_rect.size.x * 0.45, _race_cue_rect.end.y - 12.0)
			for k in range(3):
				(smoke as Object).call("emit", tail + Vector2(-float(dir * k) * 3.0, 0.0), Vector2(-float(dir) * 18.0, -8.0))


## Bong bóng "!" trên đầu tay lái đang bị kè (toạ độ bản đồ, lớp _marker).
func _draw_race_cue() -> void:
	if race_cue_key == "" or not race_eligible():
		return
	var top := Vector2(_race_cue_rect.get_center().x, _race_cue_rect.position.y - 4.0)
	var pop: float = minf(_race_cue_time / 0.15, 1.0)
	var p: Vector2 = (top + Vector2(0, -roundf(absf(sin(_time * 9.0)) * 3.0))).round()
	var ink := Color(0.25, 0.08, 0.02)
	_marker.draw_rect(Rect2(p + Vector2(-5, -14) * pop, Vector2(11, 14) * pop), ink)
	_marker.draw_rect(Rect2(p + Vector2(-4, -13) * pop, Vector2(9, 12) * pop), Color(1.0, 0.96, 0.7))
	_marker.draw_colored_polygon(PackedVector2Array([p + Vector2(-2, -1), p + Vector2(2, -1), p + Vector2(0, 3)]), ink)
	_marker.draw_rect(Rect2(p + Vector2(-1, -11) * pop, Vector2(2, 6) * pop), Color(0.9, 0.2, 0.1))
	_marker.draw_rect(Rect2(p + Vector2(-1, -4) * pop, Vector2(2, 2) * pop), Color(0.9, 0.2, 0.1))


# =================================================================== thành tích, cầu hẹp, ông câu cá

## Traffic báo: một xe NPC vừa bóp kèn vì người chơi chắn đường.
func notify_honked(_from: Vector2) -> void:
	if _honk_cd > 0.0:
		return
	_honk_cd = 4.0
	achievement_event.emit(&"honked_at")


func _update_achievements(delta: float) -> void:
	_honk_cd = maxf(_honk_cd - delta, 0.0)
	_visit_check -= delta
	if _visit_check <= 0.0:
		_visit_check = 0.25
		var p: Vector2 = player.position
		for id in VISIT_AREAS:
			var inside: bool = (VISIT_AREAS[id] as Rect2).has_point(p) and visible
			if inside and not bool(_visit_in.get(id, false)):
				achievement_event.emit(id)
			_visit_in[id] = inside
	# chạy xe lên cầu (bất kỳ cầu nào trong traffic.json)
	var on_bridge: bool = false
	if player.riding and not boating:
		on_bridge = bridge_at(player.position) != ""
	if on_bridge and not _bike_on_bridge:
		achievement_event.emit(&"bike_over_bridge")
	_bike_on_bridge = on_bridge
	# vỏ lãi chui dưới cầu (người lái cúi đầu) + chuyến dài
	var under: bool = boating and traffic != null and bool(traffic.get("boat_under_bridge"))
	if under and not _boat_was_under:
		achievement_event.emit(&"boat_under_bridge")
	_boat_was_under = under
	if player.has_method("set_ducking"):
		player.call("set_ducking", under)
	if boating and not _trip_told and float(player_boat.get("trip_px")) >= BOAT_LONG_TRIP:
		_trip_told = true
		achievement_event.emit(&"boat_long_trip")


## Id cầu (traffic.json "bridges") chứa điểm p, "" nếu không.
func bridge_at(p: Vector2) -> String:
	for b in MapView.traffic_data().get("bridges", []):
		var r: Array = b["rect"]
		if Rect2(r[0], r[1], r[2], r[3]).has_point(p):
			return String(b["id"])
	return ""


## Biên độ lắc lư (0 = không) ở chỗ p: cầu khỉ / cầu ván hẹp.
func wobble_at(p: Vector2) -> float:
	for entry in WOBBLE_BRIDGES:
		if (entry[0] as Rect2).has_point(p):
			return float(entry[1])
	return 0.0


func _update_wobble(delta: float) -> void:
	if not player.has_method("set_wobble"):
		return
	var amp: float = 0.0 if boating else wobble_at(player.position)
	if amp > 0.0:
		_wobble_t += delta
	else:
		_wobble_t = 0.0
	player.call("set_wobble", amp, _wobble_t)


func _build_fishers() -> void:
	if not ResourceLoader.exists(FISHER_SHEET_PATH):
		return
	var sheet: Texture2D = load(FISHER_SHEET_PATH)
	for node_name in FISHER_NODES:
		var rect: Variant = map_view.node_rect(node_name)
		if rect == null:
			continue
		var top_left: Vector2 = (rect as Rect2).position
		var feet_y: float = top_left.y + 42.0
		map_view.set_node_hidden(node_name, true)
		var root := Node2D.new()
		root.name = "Fisher_" + node_name
		root.position = Vector2(top_left.x, feet_y)
		var sprite := Sprite2D.new()
		sprite.texture = sheet
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, 53, sheet.get_height())
		sprite.position = Vector2(0, -42)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		root.add_child(sprite)
		map_view.add_actor(root)
		_fishers.append([root, sprite, node_name])


## Hai khung nhấp nhô (phao chìm/nổi) theo nhịp 0,8 s như tranh.
func _update_fishers() -> void:
	var frame: int = int(_time / 0.8) % 2
	for entry in _fishers:
		var sprite: Sprite2D = entry[1]
		sprite.region_rect = Rect2(53.0 * float(frame), 0.0, 53.0, sprite.region_rect.size.y)


## Các sprite ông câu cá thay thế: [[Node2D gốc, Sprite2D, tên node bản đồ]] (test).
func fisher_nodes() -> Array:
	return _fishers


# =================================================================== vỏ lãi của người chơi

## Bến gần chân người chơi (đi bộ hoặc chạy xe) → nhắc "[E] Lái vỏ lãi"; hoặc chỗ vỏ lãi đang neo.
func _check_dock_prompt() -> void:
	for dock in _docks:
		var pos := Vector2(dock["pos"][0], dock["pos"][1])
		if player.position.distance_to(pos) <= DOCK_RADIUS:
			_nearby = StringName("dock:" + String(dock["id"]))
			_prompt.text = "[E] Lái vỏ lãi" + (" (dựng xe máy ở bến)" if player.riding else "")
			return
	if player_boat != null and bool(player_boat.get("moored")) and not player.riding:
		for q in player_boat.call("footprint", player_boat.get("center"), player_boat.get("heading")):
			if player.position.distance_to(q) <= 22.0:
				_nearby = &"boat_moored"
				_prompt.text = "[E] Lái vỏ lãi"
				return


func find_dock(id: String) -> Dictionary:
	for dock in _docks:
		if String(dock["id"]) == id:
			return dock
	return {}


func docks() -> Array:
	return _docks


## Chỗ đặt vỏ lãi ở bến: tâm thân + hướng sao cho thân nằm gọn trong nước, chỗ người lái gần đầu cầu nhất.
## Trả về [tâm, hướng] hoặc [] nếu không đặt được.
func boat_spot_for(dock: Dictionary) -> Array:
	var water := Vector2(dock["water_pos"][0], dock["water_pos"][1])
	var dirs: Dictionary = {"N": Vector2.UP, "S": Vector2.DOWN, "E": Vector2.RIGHT, "W": Vector2.LEFT}
	var facing: Vector2 = dirs.get(String(dock.get("facing", "S")), Vector2.DOWN)
	var best: Array = []
	var best_d: float = INF
	for k in range(0, 160, 8):
		for h in [0, 8, 4, 12, 1, 7, 9, 15, 3, 5, 11, 13]:
			for side in [0.0, 1.0, -1.0]:
				var c: Vector2 = water + facing * float(k) + Vector2(-facing.y, facing.x) * side * float(k) * 0.5
				if not player_boat.call("footprint_clear", c, h):
					continue
				var seat: Vector2 = player_boat.call("seat_of", c, h)
				var d: float = seat.distance_to(water)
				if d < best_d:
					best_d = d
					best = [c, h]
		if not best.is_empty() and best_d < float(k) + 30.0:
			break
	return best


## Lên vỏ lãi: ở bến (dời thuyền tới bến) hoặc ở chỗ thuyền đang neo. Đang chạy xe thì dựng xe ở bến trước.
func board_boat(dock_id: String = "") -> bool:
	if _boat_busy or boating:
		return false
	if dock_id == "" and String(_nearby).begins_with("dock:"):
		dock_id = String(_nearby).trim_prefix("dock:")
	if dock_id != "":
		var dock: Dictionary = find_dock(dock_id)
		if dock.is_empty():
			return false
		var spot: Array = boat_spot_for(dock)
		if spot.is_empty():
			push_warning("World: không đặt được vỏ lãi ở bến %s" % dock_id)
			return false
		player_boat.call("place", spot[0], spot[1])
	elif not bool(player_boat.get("moored")):
		return false
	_boat_busy = true
	if player.riding:
		mount_bike(false) # xe máy đỗ lại ở bến, chỗ người chơi vừa đứng
	player.can_move = false
	Audio.sfx(&"paddle", -6.0)
	await _hop(player.position, player_boat.call("seat_point"))
	boating = true
	_trip_told = false
	player_boat.call("set_driving", true)
	player_boat.call("sync_player")
	_boat_busy = false
	achievement_event.emit(&"first_boat")
	vehicles_changed.emit()
	return true


## Lên bờ: ở bến gần nhất (chân ở "pos" của bến) hoặc chỗ bờ đất đứng được gần chỗ người lái. Thuyền neo lại tại chỗ.
func leave_boat() -> bool:
	if not boating or _boat_busy:
		return false
	var target: Variant = _landing_point()
	if target == null:
		return false
	_boat_busy = true
	player_boat.call("set_driving", false)
	await _hop(player.position, target)
	player.position = target
	boating = false
	player.can_move = true
	_boat_busy = false
	Audio.sfx(&"step_wood", -8.0)
	vehicles_changed.emit()
	return true


## Chỗ lên bờ: bến gần (ưu tiên) hoặc bờ đất sát nước; null nếu không có.
func _landing_point() -> Variant:
	var dock: Dictionary = _dock_near_boat()
	if not dock.is_empty():
		return Vector2(dock["pos"][0], dock["pos"][1])
	if _bank_spot == null:
		_bank_spot = find_bank_spot(player_boat.call("seat_point"))
	return _bank_spot


func _dock_near_boat() -> Dictionary:
	var hull: PackedVector2Array = player_boat.call("footprint", player_boat.get("center"), player_boat.get("heading"))
	for dock in _docks:
		var water := Vector2(dock["water_pos"][0], dock["water_pos"][1])
		for q in hull:
			if q.distance_to(water) <= DOCK_LEAVE_RADIUS:
				return dock
	return {}


## Tìm chỗ bờ đứng được (va chạm thật của người chơi, ô nav nối với xóm) gần chỗ người lái.
func find_bank_spot(seat: Vector2) -> Variant:
	var best: Variant = null
	var best_d: float = INF
	for r in range(8, int(BANK_RADIUS) + 1, 4):
		for a in range(16):
			var p: Vector2 = (seat + Vector2.from_angle(float(a) * TAU / 16.0) * float(r)).round()
			var bits: int = nav_bits(Vector2i(p) / NAV_CELL)
			if (bits & 1) == 0 or (bits & 16) == 0 or player._blocked_at(p):
				continue
			var d: float = p.distance_to(seat)
			if d < best_d:
				best_d = d
				best = p
		if best != null:
			return best
	return null


func _update_boat_prompt() -> void:
	if _boat_busy:
		_prompt.text = ""
		return
	_bank_check -= 1
	if _bank_check <= 0:
		_bank_check = 6
		_bank_spot = find_bank_spot(player_boat.call("seat_point"))
	if not _dock_near_boat().is_empty():
		_nearby = &"leave_boat"
		_prompt.text = "[E] Lên bờ (bến)"
		return
	if _bank_spot != null:
		_nearby = &"leave_boat"
		_prompt.text = "[E] Lên bờ"
		return
	_prompt.text = "W ga · S lùi · A/D bẻ lái"
