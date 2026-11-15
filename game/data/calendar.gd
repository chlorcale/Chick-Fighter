class_name GameCalendar
extends RefCounted

## Lịch & giờ trong game (GDD 3.3, 3.6, 7.5). Chỉ chứa hằng số và hàm thuần; trạng thái (day, minutes)
## nằm ở GameState – nguồn sự thật duy nhất (Activities.day đọc/ghi qua GameState.day).
## Dùng: const Calendar := preload("res://game/data/calendar.gd") hoặc class_name GameCalendar.

const DAY_START: int = 7 * 60      # 07:00 thức dậy
const DAY_END: int = 23 * 60       # 23:00 phải đi ngủ (16 giờ/ngày, GDD 7.5)
const FORCED_WAKE: int = 8 * 60    # GDD 3.6: quá 23:00 tự về ngủ, hôm sau dậy 08:00

## Ngày 1 = Thứ 2. Thứ 7 và Chủ nhật không đi học.
const WEEKDAY_NAMES: PackedStringArray = ["Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7", "Chủ nhật"]

enum Period { SANG, TRUA, CHIEU, TOI, KHUYA }

## GDD 3.3: năm buổi. light = màu modulate gợi ý cho cảnh (PLACEHOLDER, World/HUD tự chọn cách áp).
const PERIODS: Array[Dictionary] = [
	{"id": &"sang", "name": "Sáng", "start": 7 * 60, "end": 10 * 60, "light": Color(1.0, 0.97, 0.9),
		"hint": "Đi học (T2–T6) hoặc phụ gia đình (T7, CN)"},
	{"id": &"trua", "name": "Trưa", "start": 10 * 60, "end": 13 * 60, "light": Color(1.0, 1.0, 1.0),
		"hint": "Quest, gặp NPC, thư viện, khám phá"},
	{"id": &"chieu", "name": "Chiều", "start": 13 * 60, "end": 18 * 60, "light": Color(1.0, 0.88, 0.74),
		"hint": "Làm nghề, luyện gà, mua sắm"},
	{"id": &"toi", "name": "Tối", "start": 18 * 60, "end": 21 * 60, "light": Color(0.66, 0.62, 0.86),
		"hint": "Cho gà ăn, trang bị, xếp thẻ, gặp gia đình"},
	{"id": &"khuya", "name": "Khuya", "start": 21 * 60, "end": 23 * 60, "light": Color(0.38, 0.4, 0.62),
		"hint": "Đấu giải, giao hữu, sự kiện truyện; ngủ (tự lưu)"},
]

## Hoạt động có tốn giờ (GDD 3.6). money/technology: thưởng gốc khi làm đủ (perform() nhân hệ số minigame 0,5–1,3
## cho tiền). Ca làm: GDD 7.2 (bóc gạch 80k / bán hàng 70k / chở ghe 100k, 2 giờ). Học: GDD 6 (2 tiết × +5 Tech).
## Thư viện: +4 Tech/giờ (GDD 7.1). PLACEHOLDER: chat, train, feed, shop, sleep_early không có trong GDD.
const ACTIVITIES: Dictionary = {
	&"class": {"name": "Đi học", "minutes": 180, "technology": 10, "school_day_only": true},
	&"work_brick": {"name": "Bóc gạch", "minutes": 120, "money": 80000},
	&"work_shop": {"name": "Bán hàng", "minutes": 120, "money": 70000},
	&"work_boat": {"name": "Chở ghe", "minutes": 120, "money": 100000},
	&"quest": {"name": "Làm quest", "minutes": 60},
	&"library": {"name": "Thư viện", "minutes": 60, "technology": 4},
	&"match": {"name": "Trận đấu", "minutes": 60},
	&"travel": {"name": "Sang khu vực khác", "minutes": 30},
	&"chat": {"name": "Trò chuyện hàng xóm", "minutes": 30},   # PLACEHOLDER
	&"train": {"name": "Luyện gà", "minutes": 60},              # PLACEHOLDER (xem GameState.train)
	&"feed": {"name": "Cho gà ăn", "minutes": 0},               # PLACEHOLDER: không tốn giờ
	&"shop": {"name": "Mua sắm", "minutes": 0},                 # PLACEHOLDER: đi tới tiệm đã tính bằng travel
}

## Bảng giờ tốn (phút) rút từ ACTIVITIES – GDD 3.6: học 3 giờ, ca làm 2 giờ, quest 1 giờ, thư viện 1 giờ,
## trận 1 giờ, sang khu vực khác 30 phút.
const TIME_COSTS: Dictionary = {
	&"class": 180, &"work": 120, &"work_brick": 120, &"work_shop": 120, &"work_boat": 120, &"quest": 60,
	&"library": 60, &"match": 60, &"travel": 30, &"chat": 30, &"train": 60, &"feed": 0, &"shop": 0,
}
const MINIGAME_FACTOR_MIN: float = 0.5
const MINIGAME_FACTOR_MAX: float = 1.3


static func weekday(day: int) -> int:
	return posmod(day - 1, 7)


static func weekday_name(day: int) -> String:
	return WEEKDAY_NAMES[weekday(day)]


static func week(day: int) -> int:
	return (day - 1) / 7 + 1


static func is_school_day(day: int) -> bool:
	return weekday(day) <= 4


static func is_weekend(day: int) -> bool:
	return weekday(day) >= 5


static func period_of(minutes: int) -> int:
	for i in range(PERIODS.size() - 1, -1, -1):
		if minutes >= int(PERIODS[i]["start"]):
			return i
	return Period.SANG


static func period_name_of(minutes: int) -> String:
	return String(PERIODS[period_of(minutes)]["name"])


static func clock_text_of(minutes: int) -> String:
	return "%02d:%02d" % [posmod(minutes / 60, 24), posmod(minutes, 60)]


static func cost_of(activity: StringName) -> int:
	return int(TIME_COSTS.get(activity, 0))


## Ánh sáng nội suy mượt giữa các buổi (để World đổi tông dần thay vì nhảy).
static func light_at(minutes: int) -> Color:
	var p: int = period_of(minutes)
	var a: Dictionary = PERIODS[p]
	if p == PERIODS.size() - 1:
		return a["light"]
	var t: float = clampf(float(minutes - int(a["start"])) / float(int(a["end"]) - int(a["start"])), 0.0, 1.0)
	return (a["light"] as Color).lerp(PERIODS[p + 1]["light"], t * t)
