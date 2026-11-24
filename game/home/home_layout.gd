extends RefCounted

## Bố cục NHÀ & SÂN GÀ theo nét vẽ tay NhaTrong_NhanVatChinh.aseprite (960×576, 1 px art = 1 px thế giới; camera
## zoom 3). Ảnh + danh sách đồ vật do tools/art/build_home_interior.py sinh ra (home_interior_data.gd – đừng sửa tay).
## Trái: sân gà (rào tre, chuồng gỗ, 8 bội, quây tập nền cát, ổ rơm, bao lúa, lu nước mưa, cổng tre ra đồng);
## giữa trên: buồng ngủ (giường + mùng, bàn học); phải: gian thờ (bàn thờ, tủ thờ, bàn trà, phản gỗ, cửa chính dưới);
## giữa dưới: bếp (bếp củi, phản ăn cơm, thau nhôm rửa chén, cửa hông ra sân gà).
## Người chơi: WorldPlayer phóng ×4/3 (art nhân vật cao ~43 px ×4/3 ≈ 57 px = bóng người mẫu 06_Guide; ở zoom 3 mỗi
## pixel nhân vật = đúng 4 pixel màn hình). Người nhà (family_npc.gd) phóng cùng tỉ lệ, đi lại theo ROUTINES.
## Dùng: const Layout := preload("res://game/home/home_layout.gd")

const Data := preload("res://game/home/home_interior_data.gd")

const ART: String = "res://game/art/home/"           # người nhà (build_family.py), vương miện, trứng (build_home.py)
const INTERIOR_ART: String = Data.ART               # nội thất vẽ tay (tools/art/build_home_interior.py)
const MAP_SIZE: Vector2i = Data.SIZE
## WorldPlayer vẽ sprite ×1,0 (cao ~43 px như NPC làng); nhà vẽ cho người cao ~57 px → phóng node người chơi ×4/3.
const PLAYER_SCALE: float = 4.0 / 3.0
## Người nhà (sheet cùng kiểu, cùng cỡ nhân vật chính – em trai thấp hơn) phóng cùng tỉ lệ.
const NPC_SCALE: float = 4.0 / 3.0

## Vùng sân gà (nền đất san_ga_dat_co, tới hết mái hiên tôn xanh) – x < YARD_RIGHT là sân.
const YARD_RECT: Rect2 = Rect2(16, 96, 304, 464)
const YARD_RIGHT: int = 320
## Bếp nền đất (tiếng bước chân đất) – còn lại trong nhà là ván/gạch.
const KITCHEN_RECT: Rect2 = Rect2(328, 336, 320, 220)
const HOUSE_RECT: Rect2 = Rect2(320, 16, 624, 544)

## Chỗ nhân vật đứng rửa chén: thau nhôm sát vách dưới bếp; chân đứng bên phải thau, nhìn lên (lưng ra ngoài).
const SINK_POS: Vector2 = Vector2(382, 551)
## Mặt nước trong thau nhôm (thau_nhom 347..375 × 527..543).
const SINK_BASIN: Vector2 = Vector2(361, 534)
## Vô nhà bằng cửa chính: đứng ngay trong ngạch cửa, nhìn lên.
const SPAWN: Vector2 = Vector2(737, 318)
## Cửa hông bếp ↔ sân gà (lối đi, không phải điểm tương tác).
const SIDE_DOOR: Vector2 = Vector2(324, 480)
const FRONT_DOOR: Vector2 = Vector2(737, 342)

## Điểm tương tác cố định: id, label (dòng [E]), pos (chỗ đứng), radius.
const INTERACTABLES: Array[Dictionary] = [
	{"id": &"door_front", "label": "Ra ngõ (về xóm)", "pos": FRONT_DOOR, "radius": 14.0},
	{"id": &"gate", "label": "Cổng tre ra đồng (về xóm)", "pos": Vector2(265, 512), "radius": 14.0},
	{"id": &"bed", "label": "Giường – đi ngủ (lưu game)", "pos": Vector2(380, 232), "radius": 20.0},
	{"id": &"desk", "label": "Bàn học – sổ gà, đổi Biotech", "pos": Vector2(482, 326), "radius": 18.0},
	{"id": &"altar", "label": "Bàn thờ ông nội", "pos": Vector2(736, 172), "radius": 18.0},
	{"id": &"tv", "label": "Ti vi", "pos": Vector2(589, 166), "radius": 16.0},
	{"id": &"table", "label": "Mâm cơm", "pos": Vector2(392, 500), "radius": 16.0},
	{"id": &"stove", "label": "Bếp củi", "pos": Vector2(404, 452), "radius": 14.0},
	{"id": &"sink", "label": "Thau rửa chén", "pos": SINK_POS, "radius": 16.0},
	{"id": &"incubator", "label": "Ổ rơm ấp trứng (lò ấp)", "pos": Vector2(197, 258), "radius": 16.0},
	{"id": &"feed_all", "label": "Bao lúa · chén thóc (cho cả đàn ăn)", "pos": Vector2(137, 258), "radius": 16.0},
	{"id": &"water_jar", "label": "Lu hứng nước mưa", "pos": Vector2(246, 282), "radius": 14.0},
	{"id": &"post", "label": "Quây tập nền cát (luyện gà)", "pos": Vector2(193, 330), "radius": 22.0},
]

## Đèn (chỉ sáng về tối): [pos, bán kính, năng lượng, màu].
const LIGHTS: Array = [
	[Vector2(736, 230), 190.0, 0.7, Color(1.0, 0.8, 0.5)],     # gian thờ
	[Vector2(736, 96), 60.0, 0.8, Color(1.0, 0.45, 0.25)],     # đèn bàn thờ
	[Vector2(458, 262), 80.0, 1.0, Color(1.0, 0.9, 0.55)],     # đèn bàn học
	[Vector2(420, 200), 130.0, 0.6, Color(1.0, 0.82, 0.55)],   # buồng
	[Vector2(486, 470), 150.0, 0.7, Color(1.0, 0.85, 0.6)],    # bếp
	[Vector2(170, 330), 200.0, 0.22, Color(0.75, 0.8, 1.0)],   # sân (trăng)
]
## Ánh lửa bếp củi (luôn sáng nhẹ, ban đêm rõ hơn).
const FIRE_LIGHTS: Array[Vector2] = [Vector2(364, 428), Vector2(410, 428)]
## Trứng thật (GameState.incubator) đặt trên ổ rơm o_de_rom_trung (183..211 × 233..249).
const EGG_SPOTS: Array[Vector2] = [Vector2(192, 240), Vector2(203, 240)]
const EGG_SCALE: float = 0.75

## Bội gà. Ô 1–8 = 8 bội vẽ sẵn (boi_ga_1..8, luôn hiện vì có trong nét vẽ + bóng + va chạm); ô 9–14 = bội đóng thêm
## (bản sao bội trống) ở chỗ trống của sân; ô 15–20 = ổ rơm trước chuồng gỗ (gà ở chuồng gỗ, không có bội).
const MAX_SLOTS: int = 20
const EXTRA_CAGES: Array[Vector2] = [Vector2(155, 416), Vector2(207, 416), Vector2(276, 340), Vector2(276, 388),
	Vector2(75, 468), Vector2(145, 170)]
const HOUSE_SPOTS: Array[Vector2] = [Vector2(226, 240), Vector2(246, 236), Vector2(266, 240), Vector2(222, 262),
	Vector2(242, 266), Vector2(286, 240)]
## Chỗ người đứng bấm E cho từng ô (cùng thứ tự ô).
const COOP_STANDS: Array[Vector2] = [
	Vector2(104, 262), Vector2(104, 310), Vector2(104, 358), Vector2(104, 406),   # bội 1–4 (cột trái)
	Vector2(128, 474), Vector2(182, 474), Vector2(234, 474), Vector2(268, 448),   # bội 5–7 (hàng dưới), 8
	Vector2(155, 428), Vector2(207, 428), Vector2(276, 352), Vector2(276, 400),   # bội 9–12
	Vector2(106, 468), Vector2(110, 168),                                         # bội 13–14
	Vector2(226, 250), Vector2(246, 246), Vector2(266, 250), Vector2(222, 272),   # ổ 15–18
	Vector2(242, 276), Vector2(286, 250),                                         # ổ 19–20
]
## Gà trong bội: chân gà so với chân bội.
const CHICKEN_IN_CAGE: Vector2 = Vector2(0, -5)
const CHICKEN_SCALE: float = 0.3
const CROWN_Y: float = -44.0


static func cage_count() -> int:
	return Data.PAINTED_CAGES.size() + EXTRA_CAGES.size()


static func is_cage(slot: int) -> bool:
	return slot < cage_count()


static func is_painted(slot: int) -> bool:
	return slot < Data.PAINTED_CAGES.size()


## Chân (giữa đáy) của bội / ổ rơm ô slot.
static func coop_foot(slot: int) -> Vector2:
	var painted: int = Data.PAINTED_CAGES.size()
	if slot < painted:
		return Data.PAINTED_CAGES[slot]
	if slot < painted + EXTRA_CAGES.size():
		return EXTRA_CAGES[slot - painted]
	return HOUSE_SPOTS[clampi(slot - cage_count(), 0, HOUSE_SPOTS.size() - 1)]


static func coop_stand(slot: int) -> Vector2:
	return COOP_STANDS[clampi(slot, 0, COOP_STANDS.size() - 1)]


## Va chạm của bội đóng thêm (bội vẽ sẵn đã có trong collision.png): đúng dải đáy như bội vẽ tay (48×11).
static func coop_block(slot: int) -> Rect2i:
	var f: Vector2 = coop_foot(slot)
	return Rect2i(int(f.x) - 24, int(f.y) - 11, 48, 11)


## Vị trí người nhà theo buổi (GameState.Period 0..4). Vector2.ZERO = vắng nhà. school_day: Thứ 2–6.
## Mẹ là giáo viên: sáng ngày thường đi dạy, chiều ngày thường còn ở trường.
static func family_pos(who: StringName, period: int, school_day: bool) -> Vector2:
	match who:
		&"me":
			match period:
				0:
					return Vector2.ZERO if school_day else Vector2(340, 468)   # bếp củi (đứng bên trái, không che miệng lò)
				1:
					return Vector2(340, 468)
				2:
					return Vector2.ZERO if school_day else Vector2(610, 240)   # gian thờ
				3:
					return Vector2(560, 476)                                    # bếp, cạnh khạp gạo
				4:
					return Vector2(486, 236)                                    # buồng – nhắc đi ngủ
		&"cha":
			match period:
				0:
					return Vector2(705, 300)   # bàn trà
				1:
					return Vector2(846, 250)   # cạnh phản gỗ
				2:
					return Vector2(240, 372)   # sân gà, cạnh quây tập
				3:
					return Vector2(600, 200)   # trước ti vi
		&"em":
			match period:
				0:
					return Vector2.ZERO if school_day else Vector2(430, 256)
				1, 2, 3:
					return Vector2(430, 256)   # buồng, cạnh bàn học
	return Vector2.ZERO


# =================================================================== người nhà đi lại (family_npc.gd)

## Chỗ làm việc của người nhà: id → [chân (px nhà), hướng nhìn khi đứng làm]. Đều là chỗ chân đứng được (test kiểm),
## không trùng điểm tương tác của người chơi.
const SPOTS: Dictionary = {
	&"me_stove": [Vector2(380, 458), Vector2i(0, -1)],     # nấu cơm ở bếp củi
	&"me_mat": [Vector2(396, 496), Vector2i(1, 0)],        # dọn mâm cơm trên phản ăn cơm
	&"me_tea": [Vector2(736, 290), Vector2i(0, -1)],       # chấm bài kiểm tra ở bàn trà
	&"me_altar": [Vector2(610, 240), Vector2i(1, 0)],      # lau bàn thờ, sắp bình bông
	&"me_room": [Vector2(486, 236), Vector2i(0, 1)],       # buồng – nhắc đi ngủ
	&"cha_tea": [Vector2(705, 300), Vector2i(0, -1)],      # cà phê sáng ở bàn trà
	&"cha_phan": [Vector2(872, 316), Vector2i(0, -1)],     # ngả lưng bên bộ phản gỗ
	&"cha_feed": [Vector2(140, 268), Vector2i(0, -1)],     # bốc lúa ở bao lúa cho gà ăn
	&"cha_yard": [Vector2(176, 380), Vector2i(0, -1)],     # coi gà tập ở quây cát
	&"cha_tv": [Vector2(600, 200), Vector2i(0, -1)],       # coi ti vi (đá banh)
	&"em_desk": [Vector2(430, 262), Vector2i(1, 0)],       # học bài ở bàn học
	&"em_yard": [Vector2(220, 380), Vector2i(-1, 0)],      # chơi ngoài sân gà
	&"em_yard2": [Vector2(260, 420), Vector2i(0, 1)],      # chạy giỡn với gà
}

## Lịch sinh hoạt theo buổi (GameState.Period 0 Sáng … 4 Khuya): danh sách [chỗ, giây đứng làm] xoay vòng.
## Ai vắng nhà (family_pos = ZERO hoặc không có câu nói buổi đó) thì không xuất hiện.
const ROUTINES: Dictionary = {
	&"me": [
		[[&"me_stove", 14.0], [&"me_mat", 10.0]],
		[[&"me_stove", 12.0], [&"me_mat", 12.0], [&"me_tea", 8.0]],
		[[&"me_tea", 16.0], [&"me_altar", 8.0]],
		[[&"me_stove", 12.0], [&"me_mat", 10.0], [&"me_tea", 14.0]],
		[[&"me_room", 20.0], [&"me_tea", 10.0]],
	],
	&"cha": [
		[[&"cha_tea", 18.0], [&"cha_feed", 12.0]],
		[[&"cha_phan", 20.0], [&"cha_tea", 10.0]],
		[[&"cha_feed", 12.0], [&"cha_yard", 14.0]],
		[[&"cha_tv", 20.0], [&"cha_tea", 10.0]],
		[[&"cha_phan", 30.0]],
	],
	&"em": [
		[[&"em_desk", 20.0], [&"em_yard", 10.0]],
		[[&"em_desk", 18.0], [&"em_yard", 10.0]],
		[[&"em_desk", 16.0], [&"em_yard", 12.0], [&"em_yard2", 10.0]],
		[[&"em_desk", 30.0]],
		[[&"em_desk", 30.0]],
	],
}


## Lịch của người nhà buổi period (mảng [chỗ, giây]); rỗng nếu vắng nhà (theo family_pos).
static func routine(who: StringName, period: int, school_day: bool) -> Array:
	if family_pos(who, period, school_day) == Vector2.ZERO or not ROUTINES.has(who):
		return []
	var list: Array = ROUTINES[who]
	return list[clampi(period, 0, list.size() - 1)]
