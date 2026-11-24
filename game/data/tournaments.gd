class_name TournamentCatalog
extends RefCounted

## Giải đấu & đối thủ các tầng sau Ao Làng (GDD 7.2, 7.4, 9.3 Hell Mode). Chỉ là dữ liệu; luồng truyện/UI do nơi khác nối.
## Mọi đối thủ (Ao Làng, Liên tỉnh, Olympic, giao hữu) nằm ở game/data/opponents.gd = GameState.OPPONENTS.
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
		"round_prize": 150000,            # PLACEHOLDER
		"prize_money": 2000000, "prize_biotech": 10, "prize_title": "Vô địch Liên tỉnh miền Tây",
		"entry": {"min_title": 1, "min_level": 0, "min_mutations": 0, "fee": 100000},   # PLACEHOLDER: phí
		"round_time": 99.0, "opponent_start_card_gauge": 2, "hell_mode": false, "weekdays": [5, 6],
		"unlock_act": 2, "story_managed": false},
	&"olympic": {"name": "Olympic Đá Gà", "title": 3,
		"rounds": ["ol_chin_sai_gon", "ol_muoi_dong_thap", "ol_ut_ha_tien", "ol_bay_bac_lieu", "ol_thay_cuu"],
		"level_range": [20, 30], "ai_range": [4, 4],
		"round_prize": 1000000,           # PLACEHOLDER
		"prize_money": 20000000, "prize_biotech": 0, "prize_title": "Huyền Thoại Đá Gà",
		## GDD 9.3: chỉ nhận Cửu Cự Kê hoặc gà ≥ 3 mutation (Cửu Cự Kê chưa có trong mô hình → chỉ kiểm mutation).
		"entry": {"min_title": 2, "min_level": 0, "min_mutations": 3, "fee": 1000000},  # PLACEHOLDER: phí
		"round_time": 60.0, "opponent_start_card_gauge": 4, "hell_mode": true, "weekdays": [5, 6],
		"unlock_act": 3, "story_managed": false},
}

static func has(id: StringName) -> bool:
	return TOURNAMENTS.has(id)


static func info(id: StringName) -> Dictionary:
	return TOURNAMENTS.get(id, {})


static func rounds(id: StringName) -> Array:
	return info(id).get("rounds", [])


static func round_count(id: StringName) -> int:
	return rounds(id).size()
