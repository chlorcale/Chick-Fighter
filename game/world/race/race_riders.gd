extends RefCounted

## Bốn tay lái xe máy chạy vòng trên đường làng (node MapView) – dữ liệu cho trò đua xe bí mật.
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
}


static func has_rider(node_name: String) -> bool:
	return RIDERS.has(node_name)


## Bản sao dữ liệu tay lái (thêm "node" = tên node bản đồ).
static func get_rider(node_name: String) -> Dictionary:
	var rider: Dictionary = (RIDERS.get(node_name, RIDERS["A_xe_may_cho_ga"]) as Dictionary).duplicate(true)
	rider["node"] = node_name
	return rider
