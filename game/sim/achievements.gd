class_name Achievements
extends RefCounted

## Thành tựu (sổ tay V – cây thành tựu kiểu "advancement"). Toàn hàm tĩnh, lưu file riêng có phiên bản
## user://chick_fighter_achievements.cfg. main.gd: reset() khi chơi mới, load_save() khi "Tiếp tục".
## Mở khóa xong tự lưu ngay (thành tựu không lùi lại khi tải save cũ).
##
## Gọi từ nơi khác:
##   Achievements.unlock(&"id") -> bool            mở một thành tựu (false nếu đã mở / id lạ)
##   Achievements.notify(&"event", 1)               cộng bộ đếm; mở các thành tựu dùng bộ đếm đó khi đủ goal
##   Achievements.record_max(&"event", value)       bộ đếm = max(cũ, value) (tiền, cấp chuồng…)
##   Achievements.add_to_set(&"event", item)        bộ đếm = số phần tử khác nhau (ngày chăm gà, vũ khí đã thắng…)
##   Achievements.world_event(&"visit_market")      sự kiện di chuyển của World (signal achievement_event)
##   Achievements.add_listener(callable)            callable(id: StringName) khi vừa mở (thông báo "Thành tựu mới!")

const SAVE_PATH: String = "user://chick_fighter_achievements.cfg"
const VERSION: int = 1

## Nhánh cây: id → {name, icon, color}. Thứ tự = thứ tự thẻ trong sổ tay.
const BRANCHES: Dictionary = {
	&"story": {"name": "Cốt truyện", "icon": &"flag", "color": Color(0.85, 0.35, 0.25)},
	&"fight": {"name": "Chiến kê", "icon": &"fight", "color": Color(0.9, 0.6, 0.2)},
	&"life": {"name": "Đời sống", "icon": &"house", "color": Color(0.45, 0.7, 0.35)},
	&"explore": {"name": "Khám phá", "icon": &"map", "color": Color(0.35, 0.6, 0.85)},
	&"secret": {"name": "Bí mật", "icon": &"question", "color": Color(0.7, 0.4, 0.8)},
}
const BRANCH_ORDER: Array[StringName] = [&"story", &"fight", &"life", &"explore", &"secret"]

## Danh sách thành tựu. Khóa: id, branch, parent (&"" = gốc), title, desc (hiện khi đã mở), hint (gợi ý khi chưa mở),
## icon (UISkin.ICON_NAMES), secret (chưa mở chỉ hiện "?"), goal + counter (mở khi bộ đếm ≥ goal), frame (&"goal" = cột mốc).
const LIST: Array[Dictionary] = [
	# ---------------------------------------------------------------- Cốt truyện
	{"id": &"story_chicken", "branch": &"story", "parent": &"", "icon": &"chicken", "title": "Chiến kê đầu đời",
		"desc": "Nhận con gà nòi đầu tiên từ tay Chú Tư.", "hint": "Ra sân đình gặp Chú Tư."},
	{"id": &"story_tutorial", "branch": &"story", "parent": &"story_chicken", "icon": &"sword", "title": "Học trò Chú Tư",
		"desc": "Thắng trận đấu tập với gà của Chú Tư.", "hint": "Đấu tập với Chú Tư."},
	{"id": &"story_teo", "branch": &"story", "parent": &"story_tutorial", "icon": &"fight", "title": "Giao hữu với Tèo",
		"desc": "Hạ con Tia Chớp của Tèo trong trận giao hữu.", "hint": "Thằng Tèo đang khoe gà ở sới Ao Làng."},
	{"id": &"story_cards", "branch": &"story", "parent": &"story_teo", "icon": &"card", "title": "Ba lá bài tẩy",
		"desc": "Có đủ ba thẻ Cuồng Nộ, Mai Rùa và Gió Sông.", "hint": "Thắng trận để được tặng thẻ."},
	{"id": &"story_ao_r1", "branch": &"story", "parent": &"story_teo", "icon": &"flag", "title": "Ao Làng – Vòng 1",
		"desc": "Hạ Lửa Đỏ của Út Mập.", "hint": "Đăng ký giải Ao Làng với Chú Tư."},
	{"id": &"story_ao_r2", "branch": &"story", "parent": &"story_ao_r1", "icon": &"flag", "title": "Ao Làng – Vòng 2",
		"desc": "Đánh vỡ thủ con Đông Tảo Mun Sông của Bảy Ghe.", "hint": "Vòng hai: gà Đông Tảo lì đòn."},
	{"id": &"story_ao_lang", "branch": &"story", "parent": &"story_ao_r2", "icon": &"trophy", "title": "Vô địch Ao Làng",
		"desc": "Đăng quang giải Ao Làng. Ông nội mà còn chắc mừng lắm!", "hint": "Thắng chung kết Ao Làng.", "frame": &"goal"},
	{"id": &"story_lien_round", "branch": &"story", "parent": &"story_ao_lang", "icon": &"medal", "title": "Ra quân Liên tỉnh",
		"desc": "Thắng một vòng giải Liên tỉnh miền Tây.", "hint": "Đăng ký giải ở sới Liên tỉnh."},
	{"id": &"story_lien_tinh", "branch": &"story", "parent": &"story_lien_round", "icon": &"trophy", "title": "Vô địch Liên tỉnh",
		"desc": "Năm vòng, năm tỉnh, một nhà vô địch miền Tây.", "hint": "Thắng cả năm vòng Liên tỉnh.", "frame": &"goal"},
	{"id": &"story_olympic_round", "branch": &"story", "parent": &"story_lien_tinh", "icon": &"medal", "title": "Đất Tổ gọi tên",
		"desc": "Thắng một vòng Olympic Đá Gà – Hell Mode thiệt sự.", "hint": "Giấc mơ ông nội chỉ đường lên Olympic."},
	{"id": &"story_olympic", "branch": &"story", "parent": &"story_olympic_round", "icon": &"star", "title": "Huyền Thoại Đá Gà",
		"desc": "Vô địch Olympic. Gà chín cựa có thiệt, và nó là của bạn.", "hint": "Vô địch Olympic Đá Gà.", "frame": &"goal"},
	# ---------------------------------------------------------------- Chiến kê
	{"id": &"fight_first_win", "branch": &"fight", "parent": &"", "icon": &"fight", "title": "Trận thắng đầu tiên",
		"desc": "Thắng một trận đá gà bất kỳ.", "hint": "Vô sới đá một trận."},
	{"id": &"fight_combo4", "branch": &"fight", "parent": &"fight_first_win", "icon": &"sword", "title": "Liên hoàn cước",
		"desc": "Đánh trúng chuỗi 4 đòn liên tiếp (J nối J nối K nối L).", "hint": "Nối đòn nhẹ – vừa – mạnh thành chuỗi."},
	{"id": &"fight_guard_break", "branch": &"fight", "parent": &"fight_combo4", "icon": &"shield", "title": "Phá thủ!",
		"desc": "Đánh vỡ thế thủ của đối thủ.", "hint": "Đối thủ đỡ hoài? Đánh liên tục."},
	{"id": &"fight_super", "branch": &"fight", "parent": &"fight_combo4", "icon": &"fire", "title": "Tuyệt chiêu",
		"desc": "Thắng một trận có tung tuyệt chiêu (H).", "hint": "Đủ nộ thì bấm H."},
	{"id": &"fight_perfect", "branch": &"fight", "parent": &"fight_first_win", "icon": &"heart", "title": "Thắng tuyệt đối",
		"desc": "Thắng cả trận không mất một giọt máu.", "hint": "Thắng mà không bị trúng đòn nào."},
	{"id": &"fight_card", "branch": &"fight", "parent": &"fight_first_win", "icon": &"card", "title": "Lật bài",
		"desc": "Thắng một trận có dùng thẻ bài (U/I chọn, O tung).", "hint": "Thẻ bài tốn Card Gauge."},
	{"id": &"fight_weapon", "branch": &"fight", "parent": &"fight_first_win", "icon": &"sword", "title": "Binh khí lên tiếng",
		"desc": "Thắng một trận khi gà mang vũ khí.", "hint": "Gắn vũ khí ở màn chuẩn bị."},
	{"id": &"fight_all_weapons", "branch": &"fight", "parent": &"fight_weapon", "icon": &"gear", "title": "Đủ mặt binh khí",
		"desc": "Thắng với từng món: Dao chân, Quạt lông, Nón bảo hiểm.", "hint": "Thử thắng với từng vũ khí.",
		"goal": 3, "counter": &"weapon_wins"},
	{"id": &"fight_dongtao", "branch": &"fight", "parent": &"fight_first_win", "icon": &"shield", "title": "Hạ gà Đông Tảo",
		"desc": "Thắng một con gà Đông Tảo chân to như cột đình.", "hint": "Gà Đông Tảo chậm mà lì."},
	{"id": &"fight_wins10", "branch": &"fight", "parent": &"fight_dongtao", "icon": &"medal", "title": "Gà chiến có số",
		"desc": "Thắng 10 trận.", "hint": "Thắng nhiều trận.", "goal": 10, "counter": &"wins"},
	{"id": &"fight_hell", "branch": &"fight", "parent": &"fight_wins10", "icon": &"fire", "title": "Sống sót Hell Mode",
		"desc": "Thắng một trận Hell Mode (đối thủ 4 Card Gauge, hiệp 60 giây).", "hint": "Olympic đá kiểu Hell Mode.",
		"frame": &"goal"},
	# ---------------------------------------------------------------- Đời sống
	{"id": &"life_day", "branch": &"life", "parent": &"", "icon": &"sun", "title": "Ngày mới ở Bình Kê",
		"desc": "Ngủ một giấc ở nhà, sáng ra gà gáy.", "hint": "Về nhà đi ngủ."},
	{"id": &"life_school", "branch": &"life", "parent": &"life_day", "icon": &"school", "title": "Ngày đầu đi học",
		"desc": "Lên lớp hoặc trả bài cho cô giáo.", "hint": "Trường mở buổi sáng."},
	{"id": &"life_week", "branch": &"life", "parent": &"life_school", "icon": &"book", "title": "Chuyên cần",
		"desc": "Đi học THPT đủ 5 buổi trong một tuần.", "hint": "Thứ 2 tới Thứ 6, buổi sáng."},
	{"id": &"life_first_job", "branch": &"life", "parent": &"life_day", "icon": &"coin", "title": "Đồng tiền mồ hôi",
		"desc": "Làm xong một việc kiếm tiền.", "hint": "Bờ nam có nhiều việc làm thêm."},
	{"id": &"life_job_site", "branch": &"life", "parent": &"life_first_job", "icon": &"brick", "title": "Phụ hồ",
		"desc": "Bốc gạch ở công trường.", "hint": "Công trường cần người bốc gạch."},
	{"id": &"life_job_farm", "branch": &"life", "parent": &"life_first_job", "icon": &"rice", "title": "Mùa gặt",
		"desc": "Gặt lúa ngoài đồng.", "hint": "Ruộng lúa đang chín."},
	{"id": &"life_job_fish", "branch": &"life", "parent": &"life_first_job", "icon": &"fish", "title": "Cá tra bờ nam",
		"desc": "Bắt cá tra cho Chú Sáu.", "hint": "Nhà cá bờ nam."},
	{"id": &"life_job_shop", "branch": &"life", "parent": &"life_first_job", "icon": &"plate", "title": "Phụ bán cơm",
		"desc": "Phụ bà Lan bán cơm.", "hint": "Thân với bà Lan thì được nhờ."},
	{"id": &"life_job_boat", "branch": &"life", "parent": &"life_first_job", "icon": &"boat", "title": "Chở ghe",
		"desc": "Phụ chú Bảy chở ghe.", "hint": "Thân với chú Bảy thì được nhờ."},
	{"id": &"life_money", "branch": &"life", "parent": &"life_first_job", "icon": &"coin", "title": "Triệu phú xóm",
		"desc": "Có trong túi 1.000.000đ.", "hint": "Dành dụm tiền.", "goal": 1000000, "counter": &"money", "frame": &"goal"},
	{"id": &"life_snakehead", "branch": &"life", "parent": &"life_day", "icon": &"fish", "title": "Cá lóc đầu tiên",
		"desc": "Câu được con cá lóc đầu tiên ở bờ kênh.", "hint": "Ông câu cá ngồi ở bờ kênh cả buổi."},
	{"id": &"life_kite", "branch": &"life", "parent": &"life_day", "icon": &"sparkle", "title": "Diều sáo vi vu",
		"desc": "Thả diều đón đủ 3 luồng gió (+1 Technology).", "hint": "Gió trên bờ đê thổi lồng lộng."},
	{"id": &"life_gear", "branch": &"life", "parent": &"life_day", "icon": &"gear", "title": "Sắm đồ cho gà",
		"desc": "Mua món đồ đầu tiên cho chiến kê.", "hint": "Tiệm Cô Ba bán đồ cho gà."},
	{"id": &"life_full_gear", "branch": &"life", "parent": &"life_gear", "icon": &"shield", "title": "Giáp trụ đủ bộ",
		"desc": "Gắn đủ 6 ô trang bị cho một con gà.", "hint": "Vũ khí, đầu, giáp, cánh, cựa, mào.", "goal": 6,
		"counter": &"slots"},
	{"id": &"life_care", "branch": &"life", "parent": &"life_day", "icon": &"heart", "title": "Thương gà như con",
		"desc": "Vuốt ve, tắm hoặc phơi nắng cho gà.", "hint": "Chuồng gà ở sân sau nhà."},
	{"id": &"life_care7", "branch": &"life", "parent": &"life_care", "icon": &"heart", "title": "Bảy ngày chăm gà",
		"desc": "Chăm gà 7 ngày khác nhau.", "hint": "Ngày nào cũng ghé chuồng.", "goal": 7, "counter": &"care_days"},
	{"id": &"life_hatch", "branch": &"life", "parent": &"life_care", "icon": &"egg", "title": "Gà con ra ràng",
		"desc": "Ấp nở một quả trứng.", "hint": "Lò ấp trong nhà, kèm Biotech."},
	{"id": &"life_mutation", "branch": &"life", "parent": &"life_hatch", "icon": &"dna", "title": "Đột biến!",
		"desc": "Có một con gà mang đột biến.", "hint": "Bỏ dư Biotech vô lò ấp."},
	{"id": &"life_coop5", "branch": &"life", "parent": &"life_hatch", "icon": &"coop", "title": "Chuồng gà năm sao",
		"desc": "Nâng chuồng gà lên cấp 5.", "hint": "Nâng chuồng cho rộng.", "goal": 5, "counter": &"coop_level"},
	{"id": &"life_kho_ga", "branch": &"life", "parent": &"life_care", "icon": &"jar", "title": "Khô gà lá chanh",
		"desc": "Cho một con gà về hưu thành Khô Gà.", "hint": "Gà già yếu có thể «về hưu»."},
	{"id": &"life_sell_kho", "branch": &"life", "parent": &"life_kho_ga", "icon": &"cat", "title": "Mối ruột Lão Gà Khô",
		"desc": "Bán Khô Gà cho Lão Gà Khô. Hí hí… hu hu!", "hint": "Xe khô gà ở chợ."},
	# ---------------------------------------------------------------- Khám phá
	{"id": &"explore_map", "branch": &"explore", "parent": &"", "icon": &"map", "title": "Bản đồ trong tay",
		"desc": "Mở bản đồ xã (M).", "hint": "Bấm M."},
	{"id": &"explore_market", "branch": &"explore", "parent": &"explore_map", "icon": &"market", "title": "Đi chợ",
		"desc": "Ghé Chợ Bình Kê.", "hint": "Chợ ở bờ nam."},
	{"id": &"explore_lao", "branch": &"explore", "parent": &"explore_market", "icon": &"jar", "title": "Xe khô gà",
		"desc": "Tìm ra xe khô gà lá chanh của Lão Gà Khô.", "hint": "Nghe tiếng cười hí hí trong chợ."},
	{"id": &"explore_thpt", "branch": &"explore", "parent": &"explore_map", "icon": &"school", "title": "Trường THPT",
		"desc": "Tới trường THPT.", "hint": "Trường cấp ba của xã."},
	{"id": &"explore_temple", "branch": &"explore", "parent": &"explore_map", "icon": &"temple", "title": "Đền làng",
		"desc": "Thắp nhang ở đền làng.", "hint": "Đền nằm bên sông."},
	{"id": &"explore_arenas", "branch": &"explore", "parent": &"explore_map", "icon": &"trophy", "title": "Hai sới lớn",
		"desc": "Tới cả sới Liên tỉnh lẫn sới Olympic.", "hint": "Hai sới lớn ở xa xóm.", "goal": 2,
		"counter": &"arenas"},
	{"id": &"explore_catfish", "branch": &"explore", "parent": &"explore_map", "icon": &"fish", "title": "Cầu cá tra",
		"desc": "Đi trên cầu cá tra.", "hint": "Lối đi trên ao cá."},
	{"id": &"explore_ferry", "branch": &"explore", "parent": &"explore_map", "icon": &"boat", "title": "Qua sông",
		"desc": "Đi đò ngang qua sông.", "hint": "Bến đò có chú lái đò."},
	{"id": &"explore_bike", "branch": &"explore", "parent": &"explore_map", "icon": &"bike", "title": "Xế Dream",
		"desc": "Chạy xe máy lần đầu.", "hint": "Chiếc Dream đậu trước nhà."},
	{"id": &"explore_over_bridge", "branch": &"explore", "parent": &"explore_bike", "icon": &"bridge", "title": "Qua cầu dài",
		"desc": "Chạy xe qua cây cầu dài.", "hint": "Có cây cầu bắc qua sông lớn."},
	{"id": &"explore_boat", "branch": &"explore", "parent": &"explore_map", "icon": &"boat", "title": "Tay lái vỏ lãi",
		"desc": "Lái vỏ lãi lần đầu.", "hint": "Ra bến thuyền."},
	{"id": &"explore_under_bridge", "branch": &"explore", "parent": &"explore_boat", "icon": &"bridge", "title": "Luồn gầm cầu",
		"desc": "Lái vỏ lãi chui qua gầm cầu.", "hint": "Đường sông cũng có cầu."},
	{"id": &"explore_boat_trip", "branch": &"explore", "parent": &"explore_boat", "icon": &"map", "title": "Xuôi dòng",
		"desc": "Một chuyến vỏ lãi thật xa.", "hint": "Lái vỏ lãi đi xa.", "frame": &"goal"},
	# ---------------------------------------------------------------- Bí mật (easter egg)
	{"id": &"secret_book", "branch": &"secret", "parent": &"", "icon": &"book", "title": "Kẻ tò mò",
		"desc": "Mở sổ tay lần đầu. Còn nhiều bí mật lắm nghen…", "hint": "Mở sổ tay (V).", "secret": true},
	{"id": &"secret_race", "branch": &"secret", "parent": &"secret_book", "icon": &"race", "title": "Thần Gió Đường Làng",
		"desc": "Thắng một cuộc đua xe đường làng.", "hint": "Vượt mặt xe khác trên đường làng…", "secret": true},
	{"id": &"secret_rider_hai_lua", "branch": &"secret", "parent": &"secret_race", "icon": &"bike", "title": "Dập lửa Anh Hai",
		"desc": "Thắng Anh Hai Lửa.", "hint": "Một tay đua mặc áo đỏ.", "secret": true},
	{"id": &"secret_rider_ba_ga", "branch": &"secret", "parent": &"secret_race", "icon": &"chicken", "title": "Giao gà hỏa tốc",
		"desc": "Thắng Chú Ba Giao Gà.", "hint": "Xe chở lồng gà mà chạy lẹ.", "secret": true},
	{"id": &"secret_rider_bay_dua", "branch": &"secret", "parent": &"secret_race", "icon": &"rice", "title": "Dừa rụng",
		"desc": "Thắng Chú Bảy Dừa.", "hint": "Xe chở dừa xanh.", "secret": true},
	{"id": &"secret_rider_tam_ninja", "branch": &"secret", "parent": &"secret_race", "icon": &"star", "title": "Lột mặt nạ Ninja",
		"desc": "Thắng Tám Ninja.", "hint": "Bịt mặt kín mít.", "secret": true},
	{"id": &"secret_police", "branch": &"secret", "parent": &"secret_book", "icon": &"siren", "title": "Tay trong",
		"desc": "Lén gọi công an tới sới.", "hint": "Trận chênh quá thì có cách…", "secret": true},
	{"id": &"secret_escape", "branch": &"secret", "parent": &"secret_police", "icon": &"bike", "title": "Thoát thân",
		"desc": "Ôm gà chạy thoát khi công an ập vô.", "hint": "Chạy cho lẹ!", "secret": true},
	{"id": &"secret_alibi", "branch": &"secret", "parent": &"secret_escape", "icon": &"plate", "title": "Chứng cứ ngoại phạm",
		"desc": "Về nhà rửa chén như chưa có chuyện gì.", "hint": "Về tới nhà thì làm gì cho tự nhiên?", "secret": true},
	{"id": &"secret_jackpot", "branch": &"secret", "parent": &"secret_book", "icon": &"ticket", "title": "Trúng số!",
		"desc": "Trúng giải khuyến khích vé số.", "hint": "Hên xui…", "secret": true},
	{"id": &"secret_cat", "branch": &"secret", "parent": &"secret_book", "icon": &"cat", "title": "Bạn của mèo",
		"desc": "Nói chuyện với con mèo tam thể 5 lần.", "hint": "Meo meo.", "secret": true, "goal": 5, "counter": &"cat_talk"},
	{"id": &"secret_lao_regular", "branch": &"secret", "parent": &"secret_book", "icon": &"dog", "title": "Khách quen",
		"desc": "Ghé xe khô gà Lão Gà Khô 10 lần – con chó giữ xe sủa riết cũng quen.", "hint": "Gâu gâu!", "secret": true,
		"goal": 10, "counter": &"lao_visits"},
	{"id": &"secret_honk", "branch": &"secret", "parent": &"secret_book", "icon": &"bike", "title": "Tin tin!",
		"desc": "Bị xe khác bóp kèn inh ỏi.", "hint": "Đi giữa đường hoài…", "secret": true},
	{"id": &"secret_night_owl", "branch": &"secret", "parent": &"secret_book", "icon": &"moon", "title": "Cú đêm",
		"desc": "Lang thang quá 23:00, bị Mẹ kêu về ngủ.", "hint": "Khuya lắm rồi…", "secret": true},
	{"id": &"secret_dream", "branch": &"secret", "parent": &"secret_book", "icon": &"sparkle", "title": "Ông nội về trong mơ",
		"desc": "Gặp lại ông nội trong giấc mơ.", "hint": "Một giấc mơ sau chiến thắng lớn.", "secret": true},
]

## Sự kiện World.achievement_event → thành tựu (hoặc bộ đếm "counter:<tên>", tập "set:<tên>:<phần tử>").
const WORLD_EVENTS: Dictionary = {
	&"visit_market": [&"explore_market"],
	&"visit_lao_ga_kho": [&"explore_lao", "counter:lao_visits"],
	&"visit_lien_tinh": ["set:arenas:lien_tinh"],
	&"visit_olympia": ["set:arenas:olympic"],
	&"visit_thpt": [&"explore_thpt"],
	&"visit_temple": [&"explore_temple"],
	&"visit_catfish": [&"explore_catfish"],
	&"first_bike": [&"explore_bike"],
	&"first_boat": [&"explore_boat"],
	&"boat_under_bridge": [&"explore_under_bridge"],
	&"bike_over_bridge": [&"explore_over_bridge"],
	&"boat_long_trip": [&"explore_boat_trip"],
	&"race_triggered": [],
	&"honked_at": [&"secret_honk"],
}

## Đường dẫn lưu (test đổi sang file tạm).
static var save_path: String = SAVE_PATH
## id → {"day": int, "time": String, "weekday": String}
static var unlocked: Dictionary = {}
## tên bộ đếm → int
static var counters: Dictionary = {}
## tên tập → Array (phần tử khác nhau)
static var sets: Dictionary = {}
## Tắt tự lưu (test hàng loạt).
static var autosave: bool = true
static var _listeners: Array[Callable] = []
static var _index: Dictionary = {}


static func _ensure_index() -> void:
	if not _index.is_empty():
		return
	for a in LIST:
		_index[a["id"]] = a


static func info(id: StringName) -> Dictionary:
	_ensure_index()
	return _index.get(id, {})


static func exists(id: StringName) -> bool:
	return not info(id).is_empty()


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in LIST:
		out.append(a["id"])
	return out


static func in_branch(branch: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in LIST:
		if a["branch"] == branch:
			out.append(a)
	return out


static func children(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for a in LIST:
		if a["parent"] == id:
			out.append(a["id"])
	return out


static func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)


static func count_unlocked() -> int:
	return unlocked.size()


static func total() -> int:
	return LIST.size()


## Trạng thái hiển thị: 2 = đã mở; 1 = chưa mở nhưng lộ diện (gốc hoặc cha đã mở); 0 = còn ẩn (đen).
static func visibility(id: StringName) -> int:
	if is_unlocked(id):
		return 2
	var parent: StringName = info(id).get("parent", &"")
	return 1 if parent == &"" or is_unlocked(parent) else 0


static func is_secret(id: StringName) -> bool:
	return bool(info(id).get("secret", false))


static func add_listener(callable: Callable) -> void:
	if not _listeners.has(callable):
		_listeners.append(callable)


static func remove_listener(callable: Callable) -> void:
	_listeners.erase(callable)


## Mở thành tựu. true nếu vừa mở (chưa mở trước đó và id hợp lệ).
static func unlock(id: StringName) -> bool:
	if is_unlocked(id) or not exists(id):
		return false
	unlocked[id] = {"day": GameState.day, "time": GameState.time_text(), "weekday": GameState.weekday_name()}
	if autosave:
		save()
	for callable in _listeners.duplicate():
		if callable.is_valid():
			callable.call(id)
		else:
			_listeners.erase(callable)
	return true


## Ngày mở dạng "Thứ 3 · Ngày 5 · 14:20" (rỗng nếu chưa mở).
static func when(id: StringName) -> String:
	if not is_unlocked(id):
		return ""
	var u: Dictionary = unlocked[id]
	return "%s · Ngày %d · %s" % [String(u.get("weekday", "")), int(u.get("day", 1)), String(u.get("time", ""))]


static func counter(name: StringName) -> int:
	return int(counters.get(name, 0))


## Cộng bộ đếm rồi mở các thành tựu dùng nó. Trả về danh sách vừa mở.
static func notify(event: StringName, value: int = 1) -> Array[StringName]:
	counters[event] = counter(event) + value
	return _check_counter(event)


## Bộ đếm = max(cũ, value).
static func record_max(event: StringName, value: int) -> Array[StringName]:
	if value <= counter(event):
		return []
	counters[event] = value
	return _check_counter(event)


## Thêm phần tử vào tập; bộ đếm cùng tên = số phần tử khác nhau.
static func add_to_set(event: StringName, item: Variant) -> Array[StringName]:
	var arr: Array = sets.get(event, [])
	var key: String = str(item)
	if arr.has(key):
		return []
	arr.append(key)
	sets[event] = arr
	counters[event] = arr.size()
	return _check_counter(event)


static func set_items(event: StringName) -> Array:
	return (sets.get(event, []) as Array).duplicate()


static func _check_counter(event: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for a in LIST:
		if StringName(a.get("counter", &"")) == event and counter(event) >= int(a.get("goal", 1)):
			if unlock(a["id"]):
				out.append(a["id"])
	if autosave and out.is_empty():
		save()
	return out


## Tiến độ (hiện tại, mục tiêu) – thành tựu không có bộ đếm: (0|1, 1).
static func progress(id: StringName) -> Vector2i:
	var a: Dictionary = info(id)
	var goal: int = int(a.get("goal", 1))
	if is_unlocked(id):
		return Vector2i(goal, goal)
	var c: StringName = StringName(a.get("counter", &""))
	if c == &"":
		return Vector2i(0, goal)
	return Vector2i(mini(counter(c), goal), goal)


## Sự kiện di chuyển của World (signal achievement_event). Trả về danh sách vừa mở.
static func world_event(event: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for action in WORLD_EVENTS.get(event, []):
		if action is StringName:
			if unlock(action):
				out.append(action)
		else:
			var parts: PackedStringArray = String(action).split(":")
			if parts[0] == "counter":
				out.append_array(notify(StringName(parts[1])))
			elif parts[0] == "set" and parts.size() >= 3:
				out.append_array(add_to_set(StringName(parts[1]), parts[2]))
	return out


# ------------------------------------------------------------------ lưu / tải

static func reset() -> void:
	unlocked = {}
	counters = {}
	sets = {}
	if autosave:
		save()


static func has_save() -> bool:
	return FileAccess.file_exists(_path())


## File đang dùng. Test đổi GameState.save_path (không đụng save thật) mà quên Achievements.save_path → tự tách file
## riêng cho test, để thành tựu thật của người chơi không bị ghi đè.
static func _path() -> String:
	if save_path == SAVE_PATH and GameState.save_path != GameState.SAVE_PATH:
		return "user://test_achievements_auto.cfg"
	return save_path


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	for id in unlocked:
		cfg.set_value("unlocked", String(id), unlocked[id])
	for key in counters:
		cfg.set_value("counters", String(key), int(counters[key]))
	for key in sets:
		cfg.set_value("sets", String(key), sets[key])
	cfg.save(_path())


## Tải file thành tựu. Không có file / sai phiên bản → để trống. Trả về true nếu tải được.
static func load_save() -> bool:
	unlocked = {}
	counters = {}
	sets = {}
	var cfg := ConfigFile.new()
	if cfg.load(_path()) != OK:
		return false
	if int(cfg.get_value("meta", "version", 0)) != VERSION:
		return false
	if cfg.has_section("unlocked"):
		for key in cfg.get_section_keys("unlocked"):
			if exists(StringName(key)):
				unlocked[StringName(key)] = cfg.get_value("unlocked", key, {})
	if cfg.has_section("counters"):
		for key in cfg.get_section_keys("counters"):
			counters[StringName(key)] = int(cfg.get_value("counters", key, 0))
	if cfg.has_section("sets"):
		for key in cfg.get_section_keys("sets"):
			sets[StringName(key)] = cfg.get_value("sets", key, [])
	return true
