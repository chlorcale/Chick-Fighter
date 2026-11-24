extends RefCounted

## Tay lái xe máy cho trò đua xe bí mật. Bốn tay lái gốc chạy vòng trên đường làng (khoá = tên node xe cũ của tranh),
## sáu tay đua có tên mới (khoá "R_…") gắn với xe dáng mới (game/art/vehicles, traffic.gd NAMED_RIDERS), còn mọi xe máy
## "racer" khác thách đua bằng khoá "generic:<dáng xe>:<số xe>" → get_rider() tạo tay lái vô danh theo dáng xe.
## "vehicle": dáng xe (id traffic.json / vehicles.json) – màn đua vẽ đúng xe đó.
## "dir": hướng chạy trên bản đồ (+1 sang phải / đông, −1 sang trái / tây), suy từ frame của map_layers.json:
##   A_xe_may_con_tay_do  x −69 → 1273  (đường làng bờ bắc, chạy sang phải)
##   A_xe_may_cho_ga      x 1275 → −67  (đường làng bờ bắc, chạy sang trái)
##   C_xe_may_cho_dua     x −63 → 1278  (đường bờ nam, chạy sang phải)
##   C_xe_may_con_tay_den x 1271 → −70  (đường bờ nam, chạy sang trái)
## Ảnh xe trên bản đồ quay mặt theo hướng chạy → trong cuộc đua (luôn chạy sang phải) xe dir = −1 phải lật ngang.
## Độ khó: "pace" = tốc độ hành trình (px/s, người chơi tối đa RaceGame.V_MAX = 250), "skill" = xác suất né
## chướng ngại, "look" = tầm nhìn trước (px), "rubber" = mức kéo giãn khoảng cách (±), "nitro_at" = các mốc
## (tỉ lệ quãng đường) sẽ bốc ga, "react" = trễ khi xuất phát (s).

const RIDERS: Dictionary = {
	"A_xe_may_con_tay_do": {
		"id": &"hai_lua", "name": "Anh Hai Lửa", "dir": 1, "color": Color(0.9, 0.2, 0.15),
		"pace": 254.0, "skill": 0.95, "look": 230.0, "rubber": 0.04, "nitro_at": [0.42, 0.8], "react": 0.12,
		"challenge": "Ê ê ê! Nhóc con mà dám vượt mặt anh Hai Lửa trên con đường này hả? Xóm này chưa ai qua mặt tui đâu nghen! Dám đua tới cổng ấp hông?",
		"decline": "Hừ, biết sợ là khôn đó em. Lần sau thấy xe côn tay đỏ thì nép vô lề nghen!",
		"win": "Trời đất quỷ thần ơi… thua một thằng nhóc chạy xe Dream! Thôi thôi, từ nay anh kêu em bằng… anh luôn.",
		"lose": "Thấy chưa! Xe Dream mà đòi đua với xe côn tay. Về độ lại cái pô đi rồi tính nha cưng!",
		"taunt": ["Bám theo anh nè!", "Hít khói đi em!"],
	},
	"A_xe_may_cho_ga": {
		"id": &"ba_ga", "name": "Chú Ba Giao Gà", "dir": -1, "color": Color(0.95, 0.75, 0.15),
		"pace": 232.0, "skill": 0.55, "look": 160.0, "rubber": 0.06, "nitro_at": [0.7], "react": 0.3,
		"challenge": "Ủa thằng nhỏ, vượt chú chi dữ vậy? Chú đang chở gà đi giao nè… mà nói chơi chứ chạy lẹ thì chú hổng thua ai. Đua tới cổng ấp hông? Lồng gà làm chứng!",
		"decline": "Ờ, vậy cũng được. Mấy con gà trong lồng nó cũng mừng, khỏi bị xóc.",
		"win": "Thua rồi, thua rồi! Mấy con gà trong lồng nó cười chú kìa… Bữa nào ghé nhà chú cho mớ trứng gà ta.",
		"lose": "Hehe, chở nguyên lồng gà mà còn về trước! Tập chạy thêm đi con, đừng để ổ gà nó ăn bánh xe.",
		"taunt": ["Cục tác! Cục tác!", "Gà chú còn lẹ hơn!"],
	},
	"C_xe_may_cho_dua": {
		"id": &"bay_dua", "name": "Chú Bảy Dừa", "dir": 1, "color": Color(0.35, 0.75, 0.3),
		"pace": 238.0, "skill": 0.7, "look": 180.0, "rubber": 0.06, "nitro_at": [0.6, 0.88], "react": 0.25,
		"challenge": "Ê nhỏ! Xe chú chở cả chục trái dừa mà con còn ráng vượt hả? Vậy đua coi: ai tới cổng ấp trước thì người kia… khui dừa mời!",
		"decline": "Thôi để bữa khác. Uống miếng nước dừa cho mát rồi hẵng tính, nóng quá trời.",
		"win": "Chạy gì mà lẹ như sóc vậy con! Nè, cầm trái dừa uống cho mát, chú thua tâm phục khẩu phục.",
		"lose": "Dừa nặng vậy mà chú vẫn về trước! Bữa sau ăn cơm no rồi hẵng đua nghen con.",
		"taunt": ["Dừa xiêm đây!", "Né dừa nè con!"],
	},
	"C_xe_may_con_tay_den": {
		"id": &"tam_ninja", "name": "Tám Ninja", "dir": -1, "color": Color(0.55, 0.55, 0.7),
		"pace": 247.0, "skill": 0.85, "look": 210.0, "rubber": 0.05, "nitro_at": [0.5, 0.86], "react": 0.18,
		"challenge": "…Hừm. Vượt mặt Tám Ninja hả? Con đường này tao chạy từ hồi mày còn bú bình. Đua tới cổng ấp. Thua thì đừng có khóc nhè.",
		"decline": "…Biết điều. Đi đi.",
		"win": "…Được. Mày chạy cũng có nghề. Tám Ninja nhận thua. (Ảnh kéo khẩu trang lên che cái mặt đỏ lừ.)",
		"lose": "Còn non lắm. Về tập ôm cua cho đàng hoàng rồi tính.",
		"taunt": ["…", "Chậm."],
	},
	"R_ba_phuot": {
		"id": &"ba_phuot", "name": "Anh Ba Phượt", "dir": 1, "color": Color(0.25, 0.45, 0.85), "vehicle": "bike_11",
		"pace": 258.0, "skill": 0.92, "look": 240.0, "rubber": 0.04, "nitro_at": [0.35, 0.72, 0.9], "react": 0.15,
		"challenge": "Ê nhóc! Anh mới phượt Hà Giang về, bánh còn dính bụi đèo đây. Dám vượt con cruiser của anh hả? Đua tới cổng ấp, thua thì đãi anh ly cà phê sữa đá!",
		"decline": "Ờ, đường còn dài, phượt còn nhiều. Khi nào gan thì kiếm anh nghen!",
		"win": "Đỉnh thiệt! Xe nhỏ mà chạy như gió đèo. Anh phục, lần sau rủ em đi phượt chung!",
		"lose": "Hehe, máy to vẫn là máy to. Về luyện thêm ôm cua rồi phượt với anh!",
		"taunt": ["Gió đèo đây!", "Bụi đường nè!"],
	},
	"R_ut_vespa": {
		"id": &"ut_vespa", "name": "Cô Út Vespa", "dir": -1, "color": Color(0.55, 0.36, 0.25), "vehicle": "bike_08",
		"pace": 244.0, "skill": 0.88, "look": 220.0, "rubber": 0.05, "nitro_at": [0.55, 0.85], "react": 0.2,
		"challenge": "Ủa, cậu nhỏ chạy kè kè theo xe tui chi vậy? Áo dài tui bay phất phới vậy chứ tay ga tui hổng phải dạng vừa đâu. Đua tới cổng ấp hông?",
		"decline": "Hihi, vậy thôi. Chạy chậm chậm ngắm cảnh cũng vui mà.",
		"win": "Trời đất, thua thằng nhỏ chạy xe Dream! Thôi, tui bao cậu ly nước mía, đừng kể ai nghe nghen.",
		"lose": "Tà áo dài tui còn về trước cậu kìa! Tập thêm đi nghen.",
		"taunt": ["Bye bye nghen!", "Theo kịp hông?"],
	},
	"R_sau_dream": {
		"id": &"sau_dream", "name": "Chú Sáu Dream", "dir": 1, "color": Color(0.85, 0.8, 0.25), "vehicle": "bike_05",
		"pace": 236.0, "skill": 0.7, "look": 190.0, "rubber": 0.06, "nitro_at": [0.6, 0.88], "react": 0.25,
		"challenge": "Ha! Dream đấu Dream nè con! Xe chú đời đầu, máy êm ru, chạy ba chục năm chưa đại tu. Đua tới cổng ấp coi xe ai bền!",
		"decline": "Ừ, Dream thì phải giữ gìn, chạy ẩu chi cho hao xăng.",
		"win": "Xe con đời sau, bốc hơn là phải rồi… Mà con chạy cũng khéo đó nghen!",
		"lose": "Thấy chưa, Dream đời đầu là huyền thoại! Về thay nhớt đi con.",
		"taunt": ["Máy êm ru!", "Dream muôn năm!"],
	},
	"R_nam_cub": {
		"id": &"nam_cub", "name": "Ông Năm Cub Gạo", "dir": -1, "color": Color(0.3, 0.7, 0.7), "vehicle": "bike_14",
		"pace": 226.0, "skill": 0.5, "look": 150.0, "rubber": 0.07, "nitro_at": [0.75], "react": 0.4,
		"challenge": "Ê thằng cháu! Ông chở ba bao gạo mà còn chạy ngang con. Đua tới cổng ấp hông? Thua thì vác phụ ông bao gạo!",
		"decline": "Hà hà, sợ vác gạo hả? Thôi đi chơi đi cháu.",
		"win": "Già rồi, già rồi… mà chở gạo nặng nữa. Con giỏi lắm, ghé nhà ông ăn cơm mới nghen!",
		"lose": "Ba bao gạo mà ông vẫn về trước! Ăn nhiều cơm vô cháu.",
		"taunt": ["Gạo mới nè!", "Xe cũ mà chạy êm!"],
	},
	"R_tu_ba_gac": {
		"id": &"tu_ba_gac", "name": "Bác Tư Ba Gác", "dir": -1, "color": Color(0.6, 0.45, 0.25), "vehicle": "bike_21",
		"pace": 222.0, "skill": 0.45, "look": 140.0, "rubber": 0.08, "nitro_at": [0.5, 0.8], "react": 0.45,
		"challenge": "Ê nhỏ! Ba gác chở cả xe dừa mà con ráng vượt hả? Đua chơi tới cổng ấp! Bác thua thì bác khui dừa cho cả xóm!",
		"decline": "Ờ thôi, dừa của bác cũng mừng, khỏi lăn lóc.",
		"win": "Ba gác thua xe máy là chuyện thường! Nè, cầm trái dừa uống cho đã khát.",
		"lose": "Ha ha! Ba gác mà về trước! Con nhớ kể cả xóm nghe nghen!",
		"taunt": ["Dừa lăn kìa!", "Tránh ra, ba gác!"],
	},
	"R_ut_ga": {
		"id": &"ut_ga", "name": "Út Gà Giao Hàng", "dir": 1, "color": Color(0.85, 0.3, 0.2), "vehicle": "bike_19",
		"pace": 240.0, "skill": 0.75, "look": 200.0, "rubber": 0.05, "nitro_at": [0.45, 0.82], "react": 0.22,
		"challenge": "Giao gà phải lẹ, chậm là khách hủy đơn! Mà mày dám vượt tao hả? Đua tới cổng ấp, lồng gà làm trọng tài!",
		"decline": "Thôi tao đi giao đơn đây, gà nó kêu quá trời.",
		"win": "Ê, mày chạy lẹ hơn shipper thiệt đó! Có muốn làm chung hông?",
		"lose": "Đơn này giao đúng giờ! Mày về tập thêm đi.",
		"taunt": ["Đơn gấp!", "Cục ta cục tác!"],
	},
}
## Tay lái vô danh của xe "racer" (khoá generic): tên theo kiểu xe, độ khó trung bình.
const GENERIC_NAMES: Dictionary = {
	"underbone": ["Thằng Tí Xóm Trên", "Anh Tư Xe Ôm", "Chị Hai Bán Bánh"],
	"scooter": ["Cô Ba Tay Ga", "Bé Na Đi Học Về"],
	"cruiser": ["Anh Năm Mô-tô", "Dân Chơi Phố Huyện"],
	"cub": ["Chú Bảy Cub Cũ", "Ông Chín Đi Đám"],
	"ba_gac": ["Anh Mười Ba Gác"],
	"": ["Thanh Niên Xóm Dưới", "Dân Chơi Xe Côn"],
}


## Khoá tay lái gốc của tranh (4 xe "race_rider" – dáng xe theo traffic.json spawns).
const ORIGINAL_KEYS: Array[String] = ["A_xe_may_con_tay_do", "A_xe_may_cho_ga", "C_xe_may_cho_dua", "C_xe_may_con_tay_den"]


static func has_rider(node_name: String) -> bool:
	return RIDERS.has(node_name) or node_name.begins_with("generic:")


## Bản sao dữ liệu tay lái (thêm "node" = khoá). Khoá "generic:<dáng>:<số>" → tay lái vô danh theo dáng xe đó.
static func get_rider(node_name: String) -> Dictionary:
	if node_name.begins_with("generic:"):
		return generic_rider(node_name)
	var rider: Dictionary = (RIDERS.get(node_name, RIDERS["A_xe_may_cho_ga"]) as Dictionary).duplicate(true)
	rider["node"] = node_name
	return rider


static func generic_rider(key: String) -> Dictionary:
	var parts: PackedStringArray = key.split(":")
	var vehicle: String = parts[1] if parts.size() > 1 else "bike_01"
	var index: int = int(parts[2]) if parts.size() > 2 else 0
	var look: Dictionary = MapView.find_look(vehicle)
	var vtype: String = String(look["type"]) if look.get("type") != null else ""
	var names: Array = GENERIC_NAMES.get(vtype, GENERIC_NAMES[""])
	var rider_name: String = String(names[index % names.size()])
	var fast: bool = vtype == "cruiser" or vehicle == "bike_01" or vehicle == "bike_04"
	var slow: bool = vtype == "ba_gac" or vtype == "cub"
	var pace: float = 246.0 if fast else (224.0 if slow else 236.0)
	return {
		"id": StringName("generic_" + vehicle), "name": rider_name, "dir": 1,
		"color": Color.from_hsv(float(index % 7) / 7.0, 0.6, 0.85), "vehicle": vehicle, "node": key, "pace": pace,
		"skill": 0.6 + float(index % 3) * 0.1, "look": 180.0, "rubber": 0.06, "nitro_at": [0.55, 0.85], "react": 0.28,
		"challenge": "Ê! Chạy kè kè rồi vượt mặt tui hả? Ngon thì đua tới cổng ấp coi ai về trước!",
		"decline": "Hừ, vậy thì né qua một bên cho người ta chạy nghen!",
		"win": "Được lắm! Xe Dream mà chạy vậy là có nghề. Tui chịu thua.",
		"lose": "Ha! Về tập thêm rồi tính nha!",
		"taunt": ["Hít khói nè!", "Bắt kịp hông?"],
	}


## Dáng xe (id traffic.json / vehicles.json) mà tay lái chạy trong màn đua.
static func vehicle_of(rider: Dictionary) -> String:
	if rider.get("vehicle") != null and String(rider["vehicle"]) != "":
		return String(rider["vehicle"])
	return MapView.race_vehicle_id(String(rider.get("node", "")))
