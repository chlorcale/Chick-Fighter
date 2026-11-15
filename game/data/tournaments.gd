class_name TournamentCatalog
extends RefCounted

## Giải đấu & đối thủ các tầng sau Ao Làng (GDD 7.2, 7.4, 9.3 Hell Mode). Chỉ là dữ liệu; luồng truyện/UI do nơi khác nối.
## Đối thủ Ao Làng vẫn nằm ở GameState.OPPONENTS (giữ nguyên id/giá trị); đối thủ mới ở OPPONENTS dưới đây, cùng định dạng
## (owner, name, breed, lv, tier, skill, aggr/jumpy/block cho EnemyAI, colors cho rooster.gdshader, cards, portrait)
## và thêm: equip {ô: item id}, mutations, region, quote (câu chào giọng miền Tây).
## Dùng: const Tournaments := preload("res://game/data/tournaments.gd") hoặc class_name TournamentCatalog.
##
## Lưu ý code trận hiện tại: EnemyAI kẹp tier vào 1..3 (T4 chạy như T3 cho tới khi AI có T4); thẻ chỉ dùng 3 thẻ MVP
## (cuong_no, mai_rua, gio_song) vì CardDatabase mặc định chỉ có 3 thẻ đó.

const ORDER: Array[StringName] = [&"ao_lang", &"lien_tinh", &"olympic"]

## title: danh hiệu trao cho gà vô địch (0 không / 1 Ao Làng / 2 Liên tỉnh / 3 Olympic – công thức 6).
## entry: điều kiện đăng ký – min_title (đã vô địch giải có title ≥), min_level, min_mutations, fee (đ).
## round_prize: tiền mỗi vòng thắng (trừ chung kết); prize_*: thưởng vô địch.
## round_time: đồng hồ hiệp (giây); opponent_start_card_gauge: Card Gauge đầu trận của đối thủ (GDD 4.7 = 2).
## weekdays: ngày có giải (0 = Thứ 2 … 6 = Chủ nhật; GDD 3.1 "thi giải cuối tuần").
## story_managed: Ao Làng đang do game/main.gd điều khiển bằng Stage – đừng chạy song song bằng API giải.
const TOURNAMENTS: Dictionary = {
	&"ao_lang": {"name": "Giải Ao Làng", "title": 1, "rounds": ["ut_map", "bay_ghe", "teo_2"],
		"level_range": [2, 3], "ai_range": [1, 3], "round_prize": 50000, "prize_money": 300000, "prize_biotech": 0,
		"prize_title": "Vô địch Ao Làng", "entry": {"min_title": 0, "min_level": 1, "min_mutations": 0, "fee": 0},
		"round_time": 99.0, "opponent_start_card_gauge": 2, "hell_mode": false, "weekdays": [5, 6],
		"unlock_act": 1, "story_managed": true},
	&"lien_tinh": {"name": "Giải Liên tỉnh miền Tây", "title": 2,
		"rounds": ["lt_hai_ben_tre", "lt_ba_ca_mau", "lt_nam_chau_doc", "lt_sau_vinh_long", "lt_tam_can_tho"],
		"level_range": [6, 10], "ai_range": [2, 3],
		"round_prize": 200000,            # PLACEHOLDER
		"prize_money": 2000000, "prize_biotech": 10, "prize_title": "Vô địch Liên tỉnh miền Tây",
		"entry": {"min_title": 1, "min_level": 5, "min_mutations": 0, "fee": 100000},   # PLACEHOLDER: level/phí
		"round_time": 99.0, "opponent_start_card_gauge": 2, "hell_mode": false, "weekdays": [5, 6],
		"unlock_act": 2, "story_managed": false},
	&"olympic": {"name": "Olympic Đá Gà", "title": 3,
		"rounds": ["ol_chin_sai_gon", "ol_muoi_dong_thap", "ol_ut_ha_tien", "ol_bay_bac_lieu", "ol_thay_cuu"],
		"level_range": [20, 30], "ai_range": [4, 4],
		"round_prize": 1000000,           # PLACEHOLDER
		"prize_money": 20000000, "prize_biotech": 0, "prize_title": "Huyền Thoại Đá Gà",
		## GDD 9.3: chỉ nhận Cửu Cự Kê hoặc gà ≥ 3 mutation (Cửu Cự Kê chưa có trong mô hình → chỉ kiểm mutation).
		"entry": {"min_title": 2, "min_level": 15, "min_mutations": 3, "fee": 1000000},  # PLACEHOLDER: level/phí
		"round_time": 60.0, "opponent_start_card_gauge": 4, "hell_mode": true, "weekdays": [5, 6],
		"unlock_act": 3, "story_managed": false},
}

## 10 đối thủ mới: xen kẽ gà đá mặc định đổi màu (nòi/tre) và Gà Đông Tảo (breed 2 → kit "dongtao").
## Đông Tảo không nhảy được nên jumpy = 0. Level luôn nhỉnh hơn level kỳ vọng của người chơi (GDD 7.4).
const OPPONENTS: Dictionary = {
	# ---------------------------------------------------------------- Liên tỉnh miền Tây (Lv 6–10, T2–T3)
	"lt_hai_ben_tre": {"owner": "Hai Bến Tre", "name": "Thanh Long", "breed": 0, "lv": 6, "tier": 2, "skill": 0.55,
		"aggr": 0.5, "jumpy": 0.25, "block": 0.30, "portrait": "crowd_2", "region": "Bến Tre",
		"equip": {"spur": &"cua_sat", "armor": &"giap_tre"}, "mutations": [], "cards": [&"cuong_no", &"mai_rua"],
		"colors": {"body": [0.3, 0.9, 1.1], "neck": [0.25, 0.8, 1.15], "tail": [0.35, 1.1, 1.6]},
		"quote": "Gà xứ dừa nè em, uống nước dừa từ nhỏ nên cựa cứng như sắt đó nghen!"},
	"lt_ba_ca_mau": {"owner": "Ba Cà Mau", "name": "Đất Mũi", "breed": 2, "lv": 7, "tier": 2, "skill": 0.65,
		"aggr": 0.45, "jumpy": 0.0, "block": 0.45, "portrait": "fisher", "region": "Cà Mau",
		"equip": {"head": &"mao_sat", "armor": &"giap_dong"}, "mao_sat": true, "mutations": [],
		"cards": [&"mai_rua", &"cuong_no"],
		"colors": {"body": [-0.05, 0.55, 0.7], "neck": [-0.04, 0.6, 0.8], "tail": [0.5, 0.5, 0.9]},
		"quote": "Xuống tới Cà Mau mới biết đất rộng trời cao, con gà tui đứng đây chưa ai xô ngã."},
	"lt_nam_chau_doc": {"owner": "Năm Châu Đốc", "name": "Thất Sơn", "breed": 1, "lv": 8, "tier": 3, "skill": 0.75,
		"aggr": 0.55, "jumpy": 0.45, "block": 0.30, "portrait": "crowd_4", "region": "An Giang",
		"equip": {"weapon": &"quat_long", "wing": &"canh_lua", "spur": &"cua_sat", "armor": &"giap_tre", "head": &"mao_sat"},
		"mao_sat": true, "mutations": [], "cards": [&"gio_song", &"cuong_no", &"mai_rua"],
		"colors": {"body": [0.62, 0.7, 1.15], "neck": [0.6, 0.8, 1.2], "tail": [0.7, 1.0, 2.0]},
		"quote": "Gà tui luyện trên núi Cấm, gió thổi một cái là bay, bắt hổng kịp đâu."},
	"lt_sau_vinh_long": {"owner": "Sáu Vĩnh Long", "name": "Hắc Hổ", "breed": 2, "lv": 9, "tier": 3, "skill": 0.8,
		"aggr": 0.65, "jumpy": 0.0, "block": 0.40, "portrait": "crowd_5", "region": "Vĩnh Long",
		"equip": {"weapon": &"non_bao_hiem", "armor": &"giap_tre", "spur": &"cua_sat"}, "mutations": [],
		"cards": [&"cuong_no", &"mai_rua", &"gio_song"],
		"colors": {"body": [0.0, 0.2, 0.45], "neck": [0.08, 1.2, 1.1], "tail": [0.0, 0.3, 0.6]},
		"quote": "Vĩnh Long gạch đỏ ngói nung, gà tui húc một phát là sập luôn cái chuồng."},
	"lt_tam_can_tho": {"owner": "Tám Cần Thơ", "name": "Rồng Lửa", "breed": 0, "lv": 10, "tier": 3, "skill": 0.9,
		"aggr": 0.7, "jumpy": 0.3, "block": 0.40, "portrait": "crowd_1", "region": "Cần Thơ",
		"equip": {"weapon": &"dao_chan", "spur": &"cua_bac", "head": &"mao_sat", "armor": &"giap_tre", "wing": &"canh_lua"},
		"dao_chan": true, "mao_sat": true, "mutations": [], "cards": [&"cuong_no", &"mai_rua", &"gio_song"],
		"colors": {"body": [0.03, 1.4, 1.35], "neck": [0.09, 1.3, 1.3], "tail": [-0.05, 1.3, 2.2], "comb": [0.0, 1.2, 1.1]},
		"quote": "Cần Thơ gạo trắng nước trong, vô tới chung kết là hết đường về nghen nhỏ."},
	# ---------------------------------------------------------------- Olympic Đá Gà (Lv 20–30, T4, Hell Mode)
	"ol_chin_sai_gon": {"owner": "Chín Sài Gòn", "name": "Thép Nguội", "breed": 2, "lv": 20, "tier": 4, "skill": 0.6,
		"aggr": 0.55, "jumpy": 0.0, "block": 0.50, "portrait": "crowd_3", "region": "Sài Gòn",
		"equip": {"armor": &"giap_tre"}, "mutations": [&"iron_bone"], "cards": [&"mai_rua", &"cuong_no"],
		"colors": {"body": [0.55, 0.15, 1.05], "neck": [0.55, 0.2, 1.2], "tail": [0.5, 0.25, 1.4]},
		"quote": "Sài Gòn chơi lớn, gà tui ăn đồ nhập, xương cứng như thép. Chú em chịu nổi hông?"},
	"ol_muoi_dong_thap": {"owner": "Mười Đồng Tháp", "name": "Sen Hồng", "breed": 0, "lv": 22, "tier": 4, "skill": 0.7,
		"aggr": 0.7, "jumpy": 0.35, "block": 0.40, "portrait": "crowd_2", "region": "Đồng Tháp",
		"equip": {"weapon": &"dao_chan", "spur": &"cua_sat", "wing": &"canh_lua", "armor": &"giap_tre", "head": &"mao_sat"},
		"dao_chan": true, "mao_sat": true,
		"mutations": [&"fast_muscle"], "cards": [&"cuong_no", &"gio_song", &"mai_rua"],
		"colors": {"body": [-0.08, 0.75, 1.4], "neck": [-0.1, 0.6, 1.4], "tail": [-0.12, 0.9, 2.4], "comb": [-0.03, 1.0, 1.2]},
		"quote": "Sen Đồng Tháp mọc từ bùn mà thơm, gà tui cũng lớn lên từ đất khó vậy đó."},
	"ol_ut_ha_tien": {"owner": "Út Hà Tiên", "name": "Sóng Thần", "breed": 2, "lv": 25, "tier": 4, "skill": 0.55,
		"aggr": 0.65, "jumpy": 0.0, "block": 0.55, "portrait": "fisher", "region": "Kiên Giang",
		"equip": {"weapon": &"non_bao_hiem", "armor": &"giap_tre", "spur": &"cua_sat"},
		"mutations": [&"iron_bone"], "cards": [&"cuong_no", &"mai_rua", &"gio_song"],
		"colors": {"body": [0.45, 0.9, 0.9], "neck": [0.42, 1.0, 1.1], "tail": [0.48, 1.2, 1.8]},
		"quote": "Biển Hà Tiên sóng dữ lắm, gà tui đứng trước sóng chưa lùi một bước nào."},
	"ol_bay_bac_lieu": {"owner": "Ông Bảy Bạc Liêu", "name": "Công Tử", "breed": 1, "lv": 28, "tier": 4, "skill": 0.85,
		"aggr": 0.6, "jumpy": 0.55, "block": 0.45, "portrait": "crowd_5", "region": "Bạc Liêu",
		"equip": {"weapon": &"quat_long", "spur": &"cua_bac", "wing": &"canh_gio", "armor": &"giap_dong", "head": &"mu_dong",
			"comb": &"mao_cat"}, "mutations": [&"fast_muscle", &"wing_evolution"], "cards": [&"gio_song", &"cuong_no", &"mai_rua"],
		"colors": {"body": [0.12, 1.5, 1.5], "neck": [0.1, 1.4, 1.5], "tail": [0.14, 1.5, 2.6], "comb": [0.02, 1.2, 1.2]},
		"quote": "Công tử Bạc Liêu đốt tiền nấu trứng, còn tui chỉ đốt gà của mấy đứa nhỏ thôi."},
	"ol_thay_cuu": {"owner": "Thầy Cửu", "name": "Kê Vương", "breed": 2, "lv": 30, "tier": 4, "skill": 0.9,
		"aggr": 0.7, "jumpy": 0.0, "block": 0.60, "portrait": "temple_man", "region": "Thất Sơn",
		"equip": {"weapon": &"dao_chan", "armor": &"giap_tre", "spur": &"cua_tre"}, "dao_chan": true,
		"mutations": [&"iron_bone", &"fast_muscle"], "cards": [&"cuong_no", &"mai_rua", &"gio_song"],
		"colors": {"body": [0.0, 0.05, 0.35], "neck": [0.13, 1.4, 1.4], "tail": [0.13, 1.3, 2.4], "comb": [0.0, 1.4, 1.2]},
		"quote": "Năm xưa ông nội con cũng đứng chỗ con đứng đó… giờ tới lượt con hả?"},
}


static func has(id: StringName) -> bool:
	return TOURNAMENTS.has(id)


static func info(id: StringName) -> Dictionary:
	return TOURNAMENTS.get(id, {})


static func rounds(id: StringName) -> Array:
	return info(id).get("rounds", [])


static func round_count(id: StringName) -> int:
	return rounds(id).size()
