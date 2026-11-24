class_name GameState
extends RefCounted

## Trạng thái phiên chơi – v2 (nền dữ liệu + thời gian cho wave 2): đàn gà, kho đồ, tiền tệ (Tiền / Technology /
## Biotech / Khô Gà), ấp trứng, đột biến, giải đấu Liên tỉnh/Olympic, lịch tuần + đồng hồ ngày 5 buổi, lưu/tải có phiên bản.
## Số liệu theo GDD: Bảng 5.1–5.5 (giống, vũ khí, trang bị, đột biến), 6.1 (Thể trạng), 7.1–7.5 (kinh tế, bảy công
## thức, đường cong độ khó), 3.3/3.6 (ngày 5 buổi, Time Cost), 9.3 (Hell Mode).
## Dữ liệu tách ở game/data/: items.gd (ITEMS), mutations.gd (MUTATIONS), opponents.gd (OPPONENTS), breeds.gd,
## tournaments.gd, calendar.gd.
##
## HỢP ĐỒNG API: các hàm theo chỉ số (index) vào `chickens`, trả bool/int như mô tả ở từng hàm. Khi một thao tác
## trả false, `last_error` giữ câu tiếng Việt giải thích lý do (cho UI).
## Tương thích ngược: chicken_name / breed / level / xp / wins / equip_* trỏ vào gà đang chọn (active_chicken());
## owns_* = có món đó (trong kho hoặc đang gắn trên con nào đó); add_exp(), scaled_stats(), battle_exp(), PRICE_*,
## CAM_EXP, LEVEL_CAP giữ nguyên ý nghĩa cũ. player_side() là siêu tập của bản cũ (giữ khóa dao_chan / mao_sat).

const Breeds := preload("res://game/data/breeds.gd")
const Items := preload("res://game/data/items.gd")
const Mutations := preload("res://game/data/mutations.gd")
const Tournaments := preload("res://game/data/tournaments.gd")
const Calendar := preload("res://game/data/calendar.gd")
const Opponents := preload("res://game/data/opponents.gd")
const ACTIVITIES_SCRIPT: String = "res://game/world/activities.gd"

enum Stage {
	PROLOGUE,       # hồi ức ông nội
	GO_CHU_TU,      # mẹ nhắc ra sân đình
	TUTORIAL,       # đã nhận gà, chưa xong trận hướng dẫn
	FRIENDLY,       # giao hữu với Tèo
	PREPARE,        # mua đồ ở tiệm Cô Ba, đăng ký với Chú Tư
	ROUND_1,
	ROUND_2,
	FINAL,
	CHAMPION,       # vô địch, về nhà
	ACT_END,
}

## Năm buổi trong ngày (GDD 3.3): 07–10, 10–13, 13–18, 18–21, 21–23. Cùng giá trị với GameCalendar.Period.
enum Period { SANG, TRUA, CHIEU, TOI, KHUYA }

const SAVE_PATH: String = "user://chick_fighter_save.cfg"
## 1 = save Act 1 cũ (một con gà); 2 = bản nháp v2 (khóa lv/equip/eggs); 3 = hiện tại.
const SAVE_VERSION: int = 3

# ------------------------------------------------------------------ giống & chỉ số
const BREED_NAMES: Array[String] = ["Gà nòi", "Gà tre", "Gà Đông Tảo"]
## Chỉ số giống mà CODE TRẬN đang dùng (BattleDirector gọi scaled_stats()). Gà nòi / gà tre = GDD 5.1.
## Gà Đông Tảo (breed 2): HP 130 · SPD 140 (preset MovementConfig.GA_DONG_TAO) · WEIGHT 12 (bị đẩy lùi 50%) theo
## Owner (dongtao_fight_movelist.md, vòng 4); ATK 10 / DEF 2 / CRIT 3% là PLACEHOLDER cũ.
## LỆCH GDD (dòng 264: ATK 11 · DEF 4 · SPD 150 · WEIGHT 4,5) – chưa đổi vì sẽ đổi cân bằng trận của Bảy Ghe và
## thuộc phạm vi agent trận đấu; xem BREED_STATS_GDD.
const BREED_STATS: Array[Dictionary] = [
	{"hp": 100, "atk": 10.0, "def": 2.0, "spd": 200, "weight": 3.0, "crit": 0.05},
	{"hp": 80, "atk": 9.0, "def": 0.0, "spd": 260, "weight": 1.6, "crit": 0.10},
	{"hp": 130, "atk": 10.0, "def": 2.0, "spd": 140, "weight": 12.0, "crit": 0.03},
]
## Bảng 5.1 nguyên văn GDD (tham khảo cho agent trận đấu / Owner quyết).
const BREED_STATS_GDD: Array[Dictionary] = [
	{"hp": 100, "atk": 10.0, "def": 2.0, "spd": 200, "weight": 3.0, "crit": 0.05},
	{"hp": 80, "atk": 9.0, "def": 0.0, "spd": 260, "weight": 1.6, "crit": 0.10},
	{"hp": 130, "atk": 11.0, "def": 4.0, "spd": 150, "weight": 4.5, "crit": 0.03},
]
const BREEDS: Array[Dictionary] = Breeds.BREEDS

# ------------------------------------------------------------------ giá GDD 7.2 (tên cũ)
const PRICE_MAO_SAT: int = 150000
const PRICE_DAO_CHAN: int = 200000
const PRICE_CAM: int = 40000
const PRICE_LUA: int = 15000
const CAM_EXP: int = 20

## Cap level theo Act (GDD 7.5): Act 1 Lv5, Act 2 Lv15, Act 3–4 Lv30.
const ACT_LEVEL_CAPS: Array[int] = [5, 15, 30, 30]
## Chuồng (GDD 6, 7.2): sức chứa theo cấp chuồng 1..5; giá nâng lên cấp 2..5 = 0,5 / 1,5 / 4 / 10 triệu.
const COOP_CAPACITY: Array[int] = [3, 5, 8, 12, 20]
const COOP_UPGRADE_PRICE: Array[int] = [500000, 1500000, 4000000, 10000000]
## Thể trạng (GDD 6.1): 0..100. Ngủ +30 (tối đa 100), bỏ đói (chưa ăn Lúa trong ngày) −20, thua trận −15,
## ăn Lúa → 100. Dưới 50 → −10% ATK trong trận.
const CONDITION_MAX: float = 100.0
const CONDITION_WEAK: float = 50.0
const CONDITION_WEAK_ATK_MULT: float = 0.9
const CONDITION_LOSS_ON_DEFEAT: float = 15.0
const CONDITION_UNFED_PENALTY: float = 20.0
const CONDITION_SLEEP_RECOVERY: float = 30.0
## Luyện gà (PLACEHOLDER – GDD chỉ nói "luyện gà" cho EXP ở buổi Chiều): 1 giờ, EXP = 20 + 10 × Lv, −10 Thể trạng,
## tối đa 3 lần/ngày/con, cần Thể trạng ≥ 30. Đủ chậm để cap Act 2 (Lv15) cần vài tuần.
const TRAIN_EXP_BASE: int = 20
const TRAIN_EXP_PER_LEVEL: int = 10
const TRAIN_CONDITION_COST: float = 10.0
const TRAIN_PER_DAY: int = 3
const TRAIN_MIN_CONDITION: float = 30.0
## Công thức 6: hệ số danh hiệu 1,0 · Ao Làng 1,2 · Liên tỉnh 1,5 · Olympic 2,0.
const TITLE_SELL_MULT: Array[float] = [1.0, 1.2, 1.5, 2.0]
const TITLE_NAMES: Array[String] = ["", "Vô địch Ao Làng", "Vô địch Liên tỉnh miền Tây", "Huyền Thoại Đá Gà"]
## Công thức 7: Khô Gà (kg) = WEIGHT × 0,4 (WEIGHT thân gà: giống + đột biến, không tính đồ).
const KHO_GA_PER_WEIGHT: float = 0.4
const INCUBATOR_SLOTS: int = 2              # PLACEHOLDER: số trứng ấp cùng lúc
## "Báo công an": mismatch(đối thủ) ≥ ngưỡng này thì cho phép (agent wave 2 làm cơ chế). PLACEHOLDER.
const POLICE_MISMATCH: float = 1.35
## Hệ số AI cho power_rating theo tier (chỉ số 0 = người chơi ≈ tay AI T2). PLACEHOLDER.
const TIER_POWER: Array[float] = [1.0, 0.9, 1.05, 1.23, 1.3]

# ------------------------------------------------------------------ thời gian (GDD 3.6)
const DAY_START: int = Calendar.DAY_START        # 07:00
const DAY_END: int = Calendar.DAY_END            # 23:00
const FORCED_WAKE: int = Calendar.FORCED_WAKE    # 08:00 (quá 23:00 bị đưa về ngủ)
const TIME_SCHOOL: int = 180
const TIME_JOB: int = 120
const TIME_QUEST: int = 60
const TIME_LIBRARY: int = 60
const TIME_BATTLE: int = 60
const TIME_FERRY: int = 30
const TIME_COSTS: Dictionary = Calendar.TIME_COSTS

# ------------------------------------------------------------------ bảng dữ liệu (hợp đồng)
const ITEMS: Dictionary = Items.ITEMS
const MUTATIONS: Dictionary = Mutations.MUTATIONS
const OPPONENTS: Dictionary = Opponents.OPPONENTS
const TOURNAMENTS: Dictionary = Tournaments.TOURNAMENTS
const CARD_INFO: Dictionary = {
	&"cuong_no": {"name": "Cuồng Nộ", "cost": 2, "color": Color(0.85, 0.25, 0.2), "text": "+30% ATK trong 5 giây"},
	&"mai_rua": {"name": "Mai Rùa", "cost": 1, "color": Color(0.25, 0.5, 0.9), "text": "−25% sát thương nhận vào trong 5 giây"},
	&"gio_song": {"name": "Gió Sông", "cost": 2, "color": Color(0.2, 0.65, 0.85), "text": "Heavy +50% đẩy lùi trong 6 giây"},
}

# =================================================================== trạng thái

static var stage: int = Stage.PROLOGUE
static var player_name: String = "Tư Gà"
static var money: int = 200000
static var technology: int = 0
static var biotech: int = 0
static var kho_ga: float = 0.0                       # kg
## Bộ thẻ của người chơi (dùng chung cho mọi con gà).
static var cards: Array[StringName] = []

## Đàn gà. Mỗi con: {"id": int, "name": String, "breed": int, "level": int, "xp": int, "condition": float 0..100,
## "wins": int, "losses": int, "fed_today": bool, "weapon": StringName (&"" = không), "gear": {ô: item id} (5 ô
## head/armor/wing/spur/comb, &"" = trống), "mutations": Array[StringName], "hue_seed": int (0 = màu gốc),
## "titles": Array[String]} + "trained_today": int, "born_day": int. Không bao giờ rỗng (reset tạo sẵn Ô Mun).
static var chickens: Array[Dictionary] = []
## Chỉ số của gà đang chọn đá trong `chickens`.
static var active: int = 0
static var coop_level: int = 1                       # 1..5
static var next_chicken_id: int = 1
## Kho đồ: item id (StringName) → số bản CHƯA gắn (gắn lên gà thì bớt ở đây; tháo ra thì cộng lại).
static var inventory: Dictionary = {}
## Lò ấp: {"egg": StringName, "days_left": int, "biotech": int (đã bỏ vào), "started_day": int}.
static var incubator: Array[Dictionary] = []
## Lịch – nguồn sự thật duy nhất (Activities.day đọc/ghi qua đây). Ngày 1 = Thứ 2.
static var day: int = 1
## Phút kể từ 00:00 (ngày chạy 07:00–23:00).
static var minutes: int = DAY_START
## Act cốt truyện đã mở (1..4). current_act() còn suy ra từ stage / giải đã vô địch.
static var act: int = 1
## Tiến độ giải: tournament id (String) → {round, registered, champion, eliminated_week}.
static var tournament_progress: Dictionary = {}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Đường dẫn file lưu (test đổi sang file tạm để không đè save thật).
static var save_path: String = SAVE_PATH
## true sau khi tải save v1 (chưa có lịch): Activities.load_save() lấy "day" từ file thế giới cũ rồi tắt cờ.
static var legacy_day_pending: bool = false
## Lý do thao tác gần nhất thất bại (tiếng Việt, cho UI). "" = không lỗi.
static var last_error: String = ""
static var _listeners: Array[Callable] = []

# ---------------------------------------------------------------- tên cũ (tương thích ngược)

static var chicken_name: String:
	get:
		return String(active_chicken()["name"])
	set(value):
		active_chicken()["name"] = value
static var breed: int:
	get:
		return int(active_chicken()["breed"])
	set(value):
		active_chicken()["breed"] = clampi(value, 0, BREED_STATS.size() - 1)
static var level: int:
	get:
		return int(active_chicken()["level"])
	set(value):
		active_chicken()["level"] = maxi(value, 1)
static var xp: int:
	get:
		return int(active_chicken()["xp"])
	set(value):
		active_chicken()["xp"] = value
static var wins: int:
	get:
		return int(active_chicken()["wins"])
	set(value):
		active_chicken()["wins"] = value
## Có Mào sắt (trong kho hoặc đang gắn). Gán true khi chưa có → thêm 1 vào kho; gán false → bỏ hết.
static var owns_mao_sat: bool:
	get:
		return owned_total(&"mao_sat") > 0
	set(value):
		_set_owned(&"mao_sat", value)
static var owns_dao_chan: bool:
	get:
		return owned_total(&"dao_chan") > 0
	set(value):
		_set_owned(&"dao_chan", value)
## Gà đang chọn có gắn Mào sắt (ô Đầu). Gán true chỉ có tác dụng khi đã có món.
static var equip_mao_sat: bool:
	get:
		return StringName(active_chicken()["gear"].get(&"head", &"")) == &"mao_sat"
	set(value):
		_set_equipped(&"mao_sat", value)
static var equip_dao_chan: bool:
	get:
		return StringName(active_chicken()["weapon"]) == &"dao_chan"
	set(value):
		_set_equipped(&"dao_chan", value)
## Cap level hiện tại (trước là hằng 5; giờ theo Act – xem level_cap()).
static var LEVEL_CAP: int:
	get:
		return level_cap()
## Tên cũ của `active` (bản nháp v2).
static var active_index: int:
	get:
		return active
	set(value):
		set_active(value)


static func _static_init() -> void:
	reset()


## Ván mới: một Gà nòi "Ô Mun" Lv1, 200.000đ, ngày 1 (Thứ 2) 07:00.
static func reset() -> void:
	stage = Stage.PROLOGUE
	player_name = "Tư Gà"
	money = 200000
	technology = 0
	biotech = 0
	kho_ga = 0.0
	cards = []
	chickens = []
	active = 0
	coop_level = 1
	next_chicken_id = 1
	inventory = {}
	incubator = []
	day = 1
	minutes = DAY_START
	act = 1
	tournament_progress = {}
	legacy_day_pending = false
	last_error = ""
	rng.randomize()
	chickens.append(_new_chicken(Breeds.GA_NOI, "Ô Mun"))
	_notify_time()


static func _fail(reason: String) -> bool:
	last_error = reason
	return false


static func _ok() -> bool:
	last_error = ""
	return true


# =================================================================== đàn gà

static func _empty_gear() -> Dictionary:
	var gear: Dictionary = {}
	for slot in Items.GEAR_SLOTS:
		gear[slot] = &""
	return gear


static func _new_chicken(p_breed: int, p_name: String, p_level: int = 1, p_hue_seed: int = 0) -> Dictionary:
	var id: int = next_chicken_id
	next_chicken_id += 1
	var muts: Array[StringName] = []
	var titles: Array[String] = []
	return {
		"id": id, "name": p_name, "breed": clampi(p_breed, 0, BREED_STATS.size() - 1), "level": maxi(p_level, 1),
		"xp": 0, "condition": CONDITION_MAX, "wins": 0, "losses": 0, "fed_today": false, "weapon": &"",
		"gear": _empty_gear(), "mutations": muts, "hue_seed": p_hue_seed, "titles": titles,
		"trained_today": 0, "born_day": day,
	}


static func _valid_index(index: int) -> bool:
	return index >= 0 and index < chickens.size()


## Gà đang chọn đá (luôn có).
static func active_chicken() -> Dictionary:
	if chickens.is_empty():
		chickens.append(_new_chicken(Breeds.GA_NOI, "Ô Mun"))
	active = clampi(active, 0, chickens.size() - 1)
	return chickens[active]


static func active_id() -> int:
	return int(active_chicken()["id"])


## Chỉ số của con gà có id này (−1 nếu không có).
static func index_of(id: int) -> int:
	for i in range(chickens.size()):
		if int(chickens[i]["id"]) == id:
			return i
	return -1


static func coop_capacity() -> int:
	return COOP_CAPACITY[clampi(coop_level, 1, COOP_CAPACITY.size()) - 1]


static func coop_full() -> bool:
	return chickens.size() >= coop_capacity()


## Giá nâng chuồng lên cấp kế; −1 nếu đã tối đa.
static func coop_upgrade_price() -> int:
	return COOP_UPGRADE_PRICE[coop_level - 1] if coop_level < COOP_CAPACITY.size() else -1


static func upgrade_coop() -> bool:
	var price: int = coop_upgrade_price()
	if price < 0:
		return _fail("Chuồng đã lớn nhất rồi.")
	if money < price:
		return _fail("Không đủ tiền nâng chuồng (%s)." % money_text(price))
	money -= price
	coop_level += 1
	return _ok()


## Thêm gà Lv1 vào chuồng; trả về chỉ số mới, hoặc −1 khi chuồng đầy. Tên rỗng → tên gợi ý ngẫu nhiên.
static func add_chicken(p_breed: int, p_name: String = "") -> int:
	if not Breeds.is_valid(p_breed):
		_fail("Không có giống gà này.")
		return -1
	if coop_full():
		_fail("Chuồng đầy rồi (%d con). Nâng chuồng đi." % coop_capacity())
		return -1
	var look_seed: int = rng.randi_range(1, 0x7fffffff)
	chickens.append(_new_chicken(p_breed, p_name if p_name.strip_edges() != "" else Breeds.random_name(rng), 1, look_seed))
	_ok()
	return chickens.size() - 1


## Bỏ gà khỏi chuồng (đồ đang gắn trở về kho). Không bao giờ bỏ con cuối cùng; sửa lại `active`.
static func remove_chicken(index: int) -> void:
	if not _valid_index(index):
		_fail("Không có con gà này.")
		return
	if chickens.size() <= 1:
		_fail("Không được bỏ con gà cuối cùng.")
		return
	_strip(chickens[index])
	chickens.remove_at(index)
	if index < active:
		active -= 1
	elif index == active:
		active = 0
	active = clampi(active, 0, chickens.size() - 1)
	_ok()


static func set_active(index: int) -> void:
	if _valid_index(index):
		active = index


static func rename(index: int, p_name: String) -> bool:
	if not _valid_index(index) or p_name.strip_edges() == "":
		return _fail("Tên không hợp lệ.")
	chickens[index]["name"] = p_name.strip_edges()
	return _ok()


## Mua gà Lv1 ở chợ (GDD 7.2: tre 250k / nòi 400k / Đông Tảo 600k, Đông Tảo mở ở Act 2). Trả về chỉ số hoặc −1.
static func buy_chicken(p_breed: int, p_name: String = "") -> int:
	if not Breeds.is_valid(p_breed):
		_fail("Không có giống gà này.")
		return -1
	if current_act() < int(Breeds.info(p_breed)["unlock"]):
		_fail("%s chưa bán ở Act này." % Breeds.display_name(p_breed))
		return -1
	if coop_full():
		_fail("Chuồng đầy rồi.")
		return -1
	if money < Breeds.price(p_breed):
		_fail("Không đủ tiền (%s)." % money_text(Breeds.price(p_breed)))
		return -1
	money -= Breeds.price(p_breed)
	return add_chicken(p_breed, p_name)


## Công thức 6: Giá giống × (1 + 0,15 × (Lv − 1)) × (1 + min(0,5; 0,03 × số trận thắng)) × Hệ số danh hiệu
## × (1 + 0,1 × số mutation). (Giá con gà nếu bán – không tính đồ đang gắn.)
static func sell_price(index: int) -> int:
	return price_of(chickens[index]) if _valid_index(index) else 0


static func price_of(c: Dictionary) -> int:
	var base: float = float(Breeds.price(int(c.get("breed", 0))))
	var value: float = base * (1.0 + 0.15 * float(int(c.get("level", 1)) - 1)) \
		* (1.0 + minf(0.5, 0.03 * float(int(c.get("wins", 0))))) * TITLE_SELL_MULT[best_chicken_title(c)] \
		* (1.0 + 0.1 * float((c.get("mutations", []) as Array).size()))
	return int(round(value))


## Bán gà ở chợ: trả về tiền nhận, −1 nếu không bán được (con cuối cùng / sai chỉ số).
static func sell_chicken(index: int) -> int:
	if not _valid_index(index) or chickens.size() <= 1:
		_fail("Không bán được con gà cuối cùng." if chickens.size() <= 1 else "Không có con gà này.")
		return -1
	var price: int = sell_price(index)
	remove_chicken(index)
	money += price
	return price


## Danh hiệu cao nhất của con gà (0 không · 1 Ao Làng · 2 Liên tỉnh · 3 Olympic) – từ "titles".
static func best_chicken_title(c: Dictionary) -> int:
	var best: int = 0
	for t in c.get("titles", []):
		best = maxi(best, TITLE_NAMES.find(String(t)))
	return clampi(best, 0, TITLE_SELL_MULT.size() - 1)


## Trao danh hiệu (1..3) cho gà ở chỉ số index.
static func award_title(index: int, title: int) -> void:
	if not _valid_index(index) or title <= 0 or title >= TITLE_NAMES.size():
		return
	var titles: Array = chickens[index]["titles"]
	if not titles.has(TITLE_NAMES[title]):
		titles.append(TITLE_NAMES[title])


## WEIGHT thân gà (giống + đột biến, không tính đồ) – dùng cho Khô Gà.
static func body_weight(c: Dictionary) -> float:
	var w: float = float(BREED_STATS[clampi(int(c.get("breed", 0)), 0, BREED_STATS.size() - 1)]["weight"])
	for m in c.get("mutations", []):
		w += float((Mutations.info(m).get("stats", {}) as Dictionary).get("weight", 0.0))
	return maxf(w, 0.5)


## Công thức 7: Khô Gà (kg) = WEIGHT × 0,4 (làm tròn 0,01 kg).
static func kho_ga_yield(index: int) -> float:
	return snappedf(body_weight(chickens[index]) * KHO_GA_PER_WEIGHT, 0.01) if _valid_index(index) else 0.0


## Biến gà thành Khô Gà (VĨNH VIỄN; đồ đang gắn về kho). Trả về số kg nhận (0.0 nếu không làm được – con cuối cùng).
static func convert_to_kho_ga(index: int) -> float:
	if not _valid_index(index):
		_fail("Không có con gà này.")
		return 0.0
	if chickens.size() <= 1:
		_fail("Không được làm Khô Gà con gà cuối cùng.")
		return 0.0
	var kg: float = kho_ga_yield(index)
	remove_chicken(index)
	kho_ga = snappedf(kho_ga + kg, 0.01)
	_ok()
	return kg


## Bán Khô Gà cho Lão Gà Khô (id cửa hàng vẫn là &"meo"; 50.000đ/kg). kg < 0 = bán hết. Trả về số tiền nhận.
static func sell_kho_ga(kg: float = -1.0) -> int:
	var amount: float = kho_ga if kg < 0.0 else minf(kg, kho_ga)
	var gained: int = int(round(amount * float(Items.KHO_GA_PRICE_PER_KG)))
	kho_ga = snappedf(maxf(kho_ga - amount, 0.0), 0.01)
	money += gained
	return gained


## Màu lông của gà ({hue, sat, colors} cho rooster.gdshader): hue_seed 0 = màu gốc, khác 0 = màu ngẫu nhiên tất định
## theo seed (giống nhau mỗi lần tải save).
static func chicken_look(c: Dictionary) -> Dictionary:
	var look_seed: int = int(c.get("hue_seed", 0))
	if look_seed == 0:
		return {"hue": 0.0, "sat": 1.0, "colors": {}}
	var r := RandomNumberGenerator.new()
	r.seed = look_seed
	return Breeds.random_look(r)


# =================================================================== chỉ số

## Công thức 5: HP, ATK +3% chỉ số gốc mỗi cấp; SPD +1% mỗi cấp; DEF/WEIGHT/CRIT chỉ theo giống.
## (Code trận gọi hàm này với breed/lv – không gồm đồ, đột biến, Thể trạng.)
static func scaled_stats(p_breed: int, p_level: int) -> Dictionary:
	var base: Dictionary = BREED_STATS[clampi(p_breed, 0, BREED_STATS.size() - 1)]
	var lv: float = float(maxi(p_level, 1) - 1)
	var mult: float = 1.0 + 0.03 * lv
	return {
		"hp": int(round(float(base["hp"]) * mult)),
		"atk": float(base["atk"]) * mult,
		"def": float(base["def"]),
		"spd": float(base["spd"]) * (1.0 + 0.01 * lv),
		"weight": float(base["weight"]),
		"crit": float(base["crit"]),
	}


## Chỉ số cuối của gà ở chỉ số index = giống × cấp (công thức 5) + đồ/đột biến (phẳng) → × (1 + Σ%) → Thể trạng
## < 50: ATK × 0,9. Trả về {hp: int, atk, def, spd, weight, crit: float, weak: bool}. ĐÃ gồm +2 DEF của Mào sắt –
## code trận dùng stats này thì đừng cộng mao_sat lần nữa.
static func chicken_stats(index: int) -> Dictionary:
	return stats_of(chickens[index]) if _valid_index(index) else {}


## Như chicken_stats nhưng nhận thẳng Dictionary con gà.
static func stats_of(c: Dictionary) -> Dictionary:
	return _compute_stats(int(c.get("breed", 0)), int(c.get("level", 1)), _chicken_items(c), c.get("mutations", []),
		float(c.get("condition", CONDITION_MAX)))


static func _compute_stats(p_breed: int, p_level: int, item_ids: Array, mutation_ids: Array, condition: float) -> Dictionary:
	var base: Dictionary = scaled_stats(p_breed, p_level)
	var flat: Dictionary = {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "weight": 0.0, "crit": 0.0}
	var pct: Dictionary = {"hp_pct": 0.0, "atk_pct": 0.0, "spd_pct": 0.0}
	var sources: Array = []
	for id in item_ids:
		sources.append(Items.get_item(id).get("stats", {}))
	for m in mutation_ids:
		sources.append(Mutations.info(m).get("stats", {}))
	for mods in sources:
		for key in mods:
			if flat.has(key):
				flat[key] += float(mods[key])
			elif pct.has(key):
				pct[key] += float(mods[key])
	var weak: bool = condition < CONDITION_WEAK
	var atk: float = maxf(1.0, (float(base["atk"]) + flat["atk"]) * (1.0 + pct["atk_pct"]))
	if weak:
		atk *= CONDITION_WEAK_ATK_MULT
	return {
		"hp": maxi(1, int(round((float(base["hp"]) + flat["hp"]) * (1.0 + pct["hp_pct"])))),
		"atk": atk,
		"def": maxf(0.0, float(base["def"]) + flat["def"]),
		"spd": maxf(60.0, (float(base["spd"]) + flat["spd"]) * (1.0 + pct["spd_pct"])),
		"weight": maxf(0.5, float(base["weight"]) + flat["weight"]),
		"crit": clampf(float(base["crit"]) + flat["crit"], 0.0, 0.5),
		"weak": weak,
	}


## Công thức 1 (GDD 7.3): Sát thương = max(1; ATK × (1 + ΣATK%) − DEF) × Hệ số đòn × Crit × (1 − ΣGiảm sát thương).
## Hệ số đòn: Light 0,8 · Heavy 1,8 · Special 3,0; Crit ×1,5. Hàm thuần cho UI/test (code trận có bản riêng).
static func damage(atk: float, atk_pct: float, def: float, move_mult: float, crit: bool = false, reduction: float = 0.0) -> float:
	return maxf(1.0, atk * (1.0 + atk_pct) - def) * move_mult * (1.5 if crit else 1.0) * (1.0 - reduction)


## Món đang gắn trên gà (vũ khí trước, rồi 5 ô).
static func _chicken_items(c: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var weapon: StringName = StringName(c.get("weapon", &""))
	if weapon != &"":
		out.append(weapon)
	var gear: Dictionary = c.get("gear", {})
	for slot in Items.GEAR_SLOTS:
		var id: StringName = StringName(gear.get(slot, &""))
		if id != &"":
			out.append(id)
	return out


## Gộp cờ hành vi: số có hậu tố _mult nhân dồn, số khác cộng dồn, bool OR, kiểu khác ghi đè.
static func _merge_flags(target: Dictionary, flags: Dictionary) -> void:
	for key in flags:
		var value: Variant = flags[key]
		if not target.has(key):
			target[key] = value
		elif value is bool:
			target[key] = bool(target[key]) or value
		elif value is float or value is int:
			if String(key).ends_with("_mult"):
				target[key] = float(target[key]) * float(value)
			else:
				target[key] = target[key] + value
		else:
			target[key] = value


static func _flags_for(item_ids: Array, mutation_ids: Array) -> Dictionary:
	var flags: Dictionary = {}
	for id in item_ids:
		_merge_flags(flags, Items.get_item(id).get("flags", {}))
	for m in mutation_ids:
		_merge_flags(flags, Mutations.info(m).get("flags", {}))
	return flags


## Lớp sprite trang bị theo thứ tự vẽ (GDD 5.3): [{slot, item, layer, order}], order tăng dần.
static func layers_for(item_ids: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in item_ids:
		var item: Dictionary = Items.get_item(id)
		if item.is_empty():
			continue
		out.append({"slot": StringName(item.get("slot", &"")), "item": StringName(id),
			"layer": StringName(item.get("layer", id)), "order": Items.layer_order(id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	return out


static func _colors_with_mutations(colors: Dictionary, mutation_ids: Array) -> Dictionary:
	var out: Dictionary = colors.duplicate(true)
	for m in mutation_ids:
		var overlay: Dictionary = Mutations.info(m).get("colors", {})
		for part in overlay:
			if not out.has(part):
				out[part] = (overlay[part] as Array).duplicate()
	return out


# =================================================================== bên đấu (giao diện với trận)

## Mọi thứ trận đấu cần cho một con gà của người chơi. Khóa: owner, name, breed, lv, cards, hue, sat, colors,
## weapon, gear (ô → món), mutations, condition, stats (= chicken_stats), dao_chan / mao_sat (bool cũ, suy từ
## weapon/gear – code trận hiện tại đọc), + id, index, flags (passive gộp từ đồ/đột biến), layers, titles.
static func chicken_side(index: int) -> Dictionary:
	if not _valid_index(index):
		return {}
	var c: Dictionary = chickens[index]
	var gear: Dictionary = (c["gear"] as Dictionary).duplicate()
	var ids: Array[StringName] = _chicken_items(c)
	var muts: Array[StringName] = []
	for m in c["mutations"]:
		muts.append(StringName(m))
	var look: Dictionary = chicken_look(c)
	return {
		"owner": player_name, "name": String(c["name"]), "breed": int(c["breed"]), "lv": int(c["level"]),
		"cards": cards.duplicate(), "hue": float(look["hue"]), "sat": float(look["sat"]),
		"colors": _colors_with_mutations(look["colors"], muts),
		"weapon": StringName(c["weapon"]), "gear": gear, "mutations": muts, "condition": float(c["condition"]),
		"stats": stats_of(c),
		"dao_chan": StringName(c["weapon"]) == &"dao_chan",
		"mao_sat": StringName(gear.get(&"head", &"")) == &"mao_sat",
		"id": int(c["id"]), "index": index, "flags": _flags_for(ids, muts), "layers": layers_for(ids),
		"titles": (c["titles"] as Array).duplicate(),
	}


static func player_side() -> Dictionary:
	return chicken_side(active)


## Dữ liệu thô của đối thủ trong OPPONENTS ({} nếu không có).
static func opponent_data(id: String) -> Dictionary:
	return OPPONENTS.get(id, {})


static func opponent_ids() -> Array[String]:
	var out: Array[String] = []
	for id in OPPONENTS.keys():
		out.append(String(id))
	return out


## Đối thủ giao hữu tự do (spar). band < 0 → đúng Act hiện tại (band ≤ act và ≥ act − 1).
static func spar_opponents(band: int = -1) -> Array[String]:
	var out: Array[String] = []
	var a: int = current_act()
	for id in OPPONENTS.keys():
		var o: Dictionary = OPPONENTS[id]
		if not bool(o.get("spar", false)):
			continue
		var b: int = int(o.get("band", 1))
		if (band >= 0 and b == band) or (band < 0 and b <= a and b >= a - 1):
			out.append(String(id))
	return out


## Món của một đối thủ thô: weapon + gear, và cờ cũ dao_chan / mao_sat.
static func _raw_items(raw: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	var weapon: StringName = StringName(raw.get("weapon", &""))
	if weapon == &"" and bool(raw.get("dao_chan", false)):
		weapon = &"dao_chan"
	if weapon != &"":
		ids.append(weapon)
	var gear: Dictionary = raw.get("gear", {})
	for slot in Items.GEAR_SLOTS:
		var id: StringName = StringName(gear.get(slot, &""))
		if id != &"":
			ids.append(id)
	if bool(raw.get("mao_sat", false)) and not ids.has(&"mao_sat"):
		ids.append(&"mao_sat")
	return ids


## Bên đấu đầy đủ dựng từ một Dictionary đối thủ thô (bản sao): + weapon, gear, dao_chan/mao_sat, mutations,
## condition 100, stats, flags, layers, power.
static func side_from_raw(raw: Dictionary) -> Dictionary:
	var side: Dictionary = raw.duplicate(true)
	var ids: Array[StringName] = _raw_items(raw)
	var gear: Dictionary = _empty_gear()
	var weapon: StringName = &""
	for id in ids:
		var slot: StringName = Items.slot_of(id)
		if slot == &"weapon":
			weapon = id
		elif gear.has(slot):
			gear[slot] = id
	var muts: Array[StringName] = []
	for m in raw.get("mutations", []):
		muts.append(StringName(m))
	side["weapon"] = weapon
	side["gear"] = gear
	side["dao_chan"] = weapon == &"dao_chan"
	side["mao_sat"] = StringName(gear[&"head"]) == &"mao_sat"
	side["mutations"] = muts
	side["condition"] = CONDITION_MAX
	side["colors"] = _colors_with_mutations(raw.get("colors", {}), muts)
	side["stats"] = _compute_stats(int(raw.get("breed", 0)), int(raw.get("lv", 1)), ids, muts, CONDITION_MAX)
	side["flags"] = _flags_for(ids, muts)
	side["layers"] = layers_for(ids)
	side["power"] = power_rating(side)
	return side


## Bên đấu của đối thủ theo id (bản sao; truyền thẳng vào BattleDirector được). {} nếu không có.
static func opponent_side(id: String) -> Dictionary:
	var raw: Dictionary = opponent_data(id)
	return {} if raw.is_empty() else side_from_raw(raw)


## Chỉ số của một bên đấu bất kỳ: side["stats"] nếu có, không thì tính từ breed/lv/weapon/gear/cờ cũ/mutations.
static func side_stats(side: Dictionary) -> Dictionary:
	if side.has("stats"):
		return side["stats"]
	return _compute_stats(int(side.get("breed", 0)), int(side.get("lv", 1)), _raw_items(side),
		side.get("mutations", []), float(side.get("condition", CONDITION_MAX)))


## Sức mạnh so sánh được giữa gà người chơi và đối thủ (PLACEHOLDER, chỉ để gợi ý/khóa lựa chọn, không dùng trong trận):
##   công = ATK × (1 + 0,5 × CRIT) × (SPD / 200)^0,25        bền = HP × (1 + 0,08 × DEF)
##   power = √(công × bền) × Π power(vũ khí/đồ/đột biến) × (1 + 0,04 × min(số thẻ, 5)) × TIER_POWER[tier]
##           × (1 + 0,1 × skill) × (1 + 0,03 × (Card Gauge đầu trận − 2))
## Nhận một bên đấu (player_side()/opponent_side()/OPPONENTS thô) – Dictionary có khóa "owner".
static func power_rating(side: Dictionary) -> float:
	var s: Dictionary = side_stats(side)
	var offense: float = float(s["atk"]) * (1.0 + 0.5 * float(s["crit"])) * pow(float(s["spd"]) / 200.0, 0.25)
	var durability: float = float(s["hp"]) * (1.0 + 0.08 * float(s["def"]))
	var mult: float = 1.0
	for id in _raw_items(side):
		mult *= float(Items.get_item(id).get("power", 1.0))
	for m in side.get("mutations", []):
		mult *= float(Mutations.info(m).get("power", 1.0))
	mult *= 1.0 + 0.04 * float(mini((side.get("cards", []) as Array).size(), 5))
	mult *= TIER_POWER[clampi(int(side.get("tier", 0)), 0, TIER_POWER.size() - 1)]
	mult *= 1.0 + 0.1 * clampf(float(side.get("skill", 0.0)), 0.0, 1.0)
	mult *= 1.0 + 0.03 * float(int(side.get("start_card_gauge", 2)) - 2)
	return sqrt(offense * durability) * mult


## Chênh lệch sức mạnh = power(đối thủ) ÷ power(gà đang chọn). Nhận id đối thủ (String) hoặc Dictionary (OPPONENTS
## thô hoặc bên đấu). 1,0 = ngang; > 1 = đối thủ mạnh hơn.
static func mismatch(opponent: Variant) -> float:
	var side: Dictionary = {}
	if opponent is String or opponent is StringName:
		side = opponent_side(String(opponent))
	elif opponent is Dictionary:
		side = opponent
	if side.is_empty():
		return 0.0
	return power_rating(side) / maxf(power_rating(player_side()), 0.001)


## Cho phép "báo công an" khi trận quá chênh lệch (mismatch ≥ POLICE_MISMATCH).
static func can_call_police(opponent: Variant) -> bool:
	return mismatch(opponent) >= POLICE_MISMATCH


# =================================================================== EXP, cấp, Thể trạng

## Công thức 3: EXP lên cấp L → L+1 = round(50 × L^1,5).
static func exp_to_next(p_level: int) -> int:
	return int(round(50.0 * pow(float(p_level), 1.5)))


## Act hiện tại: max(act, suy ra từ stage và giải đã vô địch).
static func current_act() -> int:
	var a: int = act
	if stage >= Stage.CHAMPION:
		a = maxi(a, 2)
	return clampi(maxi(a, mini(best_title() + 1, 4)), 1, 4)


## Act 1: Lv5 · Act 2: Lv15 · Act 3–4: Lv30 (GDD 7.5).
static func level_cap() -> int:
	return ACT_LEVEL_CAPS[clampi(current_act(), 1, ACT_LEVEL_CAPS.size()) - 1]


## Công thức 4 cho gà đang chọn (Bảng 8.3: EXP thắng trận hướng dẫn = exp_bonus 40).
static func battle_exp(opponent: Dictionary, won: bool) -> int:
	return battle_exp_for(active_chicken(), opponent, won)


static func battle_exp_for(c: Dictionary, opponent: Dictionary, won: bool) -> int:
	var lv: int = int(opponent.get("lv", 1))
	var amount: int = (30 + 10 * lv) if won else (10 + 5 * lv)
	if won and opponent.has("exp_bonus"):
		amount = int(opponent["exp_bonus"])
	if int(c.get("level", 1)) - lv >= 3:
		amount = int(amount * 0.5)
	return amount


## Cộng EXP cho gà ở chỉ số index. Trả về số cấp vừa tăng (dừng ở level_cap(); EXP thừa giữ tối đa một cấp).
static func chicken_exp(index: int, amount: int) -> int:
	if not _valid_index(index) or amount <= 0:
		return 0
	var c: Dictionary = chickens[index]
	var cap: int = level_cap()
	c["xp"] = int(c["xp"]) + amount
	var gained: int = 0
	while int(c["level"]) < cap and int(c["xp"]) >= exp_to_next(int(c["level"])):
		c["xp"] = int(c["xp"]) - exp_to_next(int(c["level"]))
		c["level"] = int(c["level"]) + 1
		gained += 1
	if int(c["level"]) >= cap:
		c["xp"] = mini(int(c["xp"]), exp_to_next(int(c["level"])))
	return gained


## Tên cũ: cộng EXP cho gà đang chọn.
static func add_exp(amount: int) -> int:
	return chicken_exp(active, amount)


static func set_condition(index: int, value: float) -> void:
	if _valid_index(index):
		chickens[index]["condition"] = clampf(value, 0.0, CONDITION_MAX)


## Ghi thắng/thua cho gà đang chọn (KHÔNG cộng EXP – ResultScreen đã gọi add_exp). Thua: −15 Thể trạng
## (× condition_loss_mult của đột biến).
static func record_result(won: bool) -> void:
	var c: Dictionary = active_chicken()
	if won:
		c["wins"] = int(c["wins"]) + 1
		return
	c["losses"] = int(c["losses"]) + 1
	var mult: float = float(_flags_for([], c["mutations"]).get("condition_loss_mult", 1.0))
	c["condition"] = clampf(float(c["condition"]) - CONDITION_LOSS_ON_DEFEAT * mult, 0.0, CONDITION_MAX)


## Ghi một trận của gà đang chọn: EXP (công thức 4), thắng/thua, thua −15 Thể trạng. Trả về {"exp", "levels"}.
static func record_battle(won: bool, opponent: Dictionary) -> Dictionary:
	var amount: int = battle_exp(opponent, won)
	var levels: int = chicken_exp(active, amount)
	record_result(won)
	return {"exp": amount, "levels": levels}


## Cho gà ăn (tiêu 1 món food trong kho). &"lua": Thể trạng 100 + fed_today (mỗi ngày một bữa chính);
## &"cam": +20 EXP; món khác theo effect. false + last_error nếu không được.
static func feed(index: int, food: StringName) -> bool:
	if not _valid_index(index):
		return _fail("Không có con gà này.")
	var item: Dictionary = Items.get_item(food)
	if item.is_empty() or StringName(item["slot"]) != &"food":
		return _fail("Món này hổng phải đồ ăn.")
	if item_count(food) <= 0:
		return _fail("Trong kho hết %s rồi." % String(item["name"]))
	var c: Dictionary = chickens[index]
	var effect: Dictionary = item.get("effect", {})
	var meal: bool = bool(effect.get("meal", false))
	if meal and bool(c["fed_today"]):
		return _fail("Hôm nay %s ăn bữa chính rồi." % String(c["name"]))
	_take(food)
	if meal:
		c["fed_today"] = true
		c["condition"] = CONDITION_MAX
	if float(effect.get("condition", 0.0)) != 0.0:
		c["condition"] = clampf(float(c["condition"]) + float(effect["condition"]), 0.0, CONDITION_MAX)
	if int(effect.get("exp", 0)) > 0:
		chicken_exp(index, int(effect["exp"]))
	return _ok()


## Luyện gà 1 giờ (PLACEHOLDER, xem TRAIN_*). Trả về {ok, exp, levels, day_over}.
static func train(index: int) -> Dictionary:
	var out: Dictionary = {"ok": false, "exp": 0, "levels": 0, "day_over": false}
	if not _valid_index(index):
		_fail("Không có con gà này.")
		return out
	var c: Dictionary = chickens[index]
	if int(c["trained_today"]) >= TRAIN_PER_DAY:
		_fail("Hôm nay luyện đủ %d lần rồi, cho gà nghỉ." % TRAIN_PER_DAY)
		return out
	if float(c["condition"]) < TRAIN_MIN_CONDITION:
		_fail("Gà mệt quá (Thể trạng dưới %d%%), cho ăn nghỉ đã." % int(TRAIN_MIN_CONDITION))
		return out
	if not can_spend(Calendar.cost_of(&"train")):
		_fail("Khuya rồi, hổng đủ giờ luyện.")
		return out
	var amount: int = TRAIN_EXP_BASE + TRAIN_EXP_PER_LEVEL * int(c["level"])
	c["trained_today"] = int(c["trained_today"]) + 1
	c["condition"] = clampf(float(c["condition"]) - TRAIN_CONDITION_COST, 0.0, CONDITION_MAX)
	out["levels"] = chicken_exp(index, amount)
	out["exp"] = amount
	out["ok"] = true
	out["day_over"] = spend_time(Calendar.cost_of(&"train"))
	_ok()
	return out


# =================================================================== kho đồ & cửa hàng

## Số bản CHƯA gắn trong kho.
static func item_count(item: StringName) -> int:
	return int(inventory.get(StringName(item), 0))


## Số bản đang gắn trên mọi con gà.
static func equipped_count(item: StringName) -> int:
	var n: int = 0
	for c in chickens:
		if _chicken_items(c).has(StringName(item)):
			n += 1
	return n


## Tổng số bản sở hữu (trong kho + đang gắn).
static func owned_total(item: StringName) -> int:
	return item_count(item) + equipped_count(item)


static func is_unlocked(item: StringName) -> bool:
	var info: Dictionary = Items.get_item(item)
	return not info.is_empty() and current_act() >= int(info.get("act", 1))


## Hàng bày bán ở một tiệm (&"co_ba" | &"cho" | &"meo"), lọc theo Act, xếp theo ô rồi giá.
static func shop_stock(shop: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Items.ids_in_shop(shop):
		if is_unlocked(id):
			out.append(id)
	var order: Array[StringName] = [&"food", &"weapon", &"head", &"armor", &"wing", &"spur", &"comb", &"egg", &"misc"]
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var sa: int = order.find(Items.slot_of(a))
		var sb: int = order.find(Items.slot_of(b))
		if sa != sb:
			return sa < sb
		return float(Items.get_item(a)["price"]) < float(Items.get_item(b)["price"]))
	return out


## Mua (tiền hoặc Khô Gà tùy currency của món). Món vào kho; trang bị phải equip() mới gắn.
static func buy(item: StringName, qty: int = 1) -> bool:
	var info: Dictionary = Items.get_item(item)
	if info.is_empty() or qty <= 0:
		return _fail("Không có món này.")
	if not is_unlocked(item):
		return _fail("%s chưa bán ở Act này." % String(info["name"]))
	if StringName(info.get("currency", &"money")) == &"kho_ga":
		var cost_kg: float = float(info["price"]) * float(qty)
		if kho_ga + 0.0001 < cost_kg:
			return _fail("Không đủ Khô Gà (cần %s kg)." % String.num(cost_kg, 2))
		kho_ga = snappedf(maxf(kho_ga - cost_kg, 0.0), 0.01)
	else:
		var cost: int = int(info["price"]) * qty
		if money < cost:
			return _fail("Không đủ tiền (cần %s)." % money_text(cost))
		money -= cost
	_give(item, qty)
	return _ok()


static func _give(item: StringName, qty: int = 1) -> void:
	inventory[StringName(item)] = item_count(item) + qty


static func _take(item: StringName, qty: int = 1) -> void:
	var left: int = item_count(item) - qty
	if left > 0:
		inventory[StringName(item)] = left
	else:
		inventory.erase(StringName(item))


## Món đang ở ô slot của gà (&"" nếu trống).
static func equipped(index: int, slot: StringName) -> StringName:
	if not _valid_index(index):
		return &""
	var c: Dictionary = chickens[index]
	if slot == &"weapon":
		return StringName(c["weapon"])
	return StringName((c["gear"] as Dictionary).get(slot, &""))


static func _set_slot(c: Dictionary, slot: StringName, item: StringName) -> void:
	if slot == &"weapon":
		c["weapon"] = item
	else:
		c["gear"][slot] = item


## Gắn món item (lấy 1 bản từ kho) vào ô slot của gà; món cũ trong ô về kho. item == &"" → tháo ô đó về kho.
static func equip(index: int, slot: StringName, item: StringName) -> bool:
	if not _valid_index(index):
		return _fail("Không có con gà này.")
	slot = StringName(slot)
	if not Items.SLOTS.has(slot):
		return _fail("Không có ô này.")
	var c: Dictionary = chickens[index]
	var current: StringName = equipped(index, slot)
	if item == &"":
		if current != &"":
			_give(current)
			_set_slot(c, slot, &"")
		return _ok()
	if not Items.has(item):
		return _fail("Không có món này.")
	if Items.slot_of(item) != slot:
		return _fail("%s gắn ở ô %s, hổng phải ô %s." % [Items.display_name(item),
			String(Items.SLOT_NAMES.get(Items.slot_of(item), "?")), String(Items.SLOT_NAMES.get(slot, "?"))])
	if current == item:
		return _ok()
	if item_count(item) <= 0:
		return _fail("Trong kho hết %s." % Items.display_name(item))
	_take(item)
	if current != &"":
		_give(current)
	_set_slot(c, slot, item)
	return _ok()


## Tháo hết đồ của một con gà về kho.
static func _strip(c: Dictionary) -> void:
	for id in _chicken_items(c):
		_give(id)
	c["weapon"] = &""
	c["gear"] = _empty_gear()


static func _set_owned(item: StringName, value: bool) -> void:
	if value:
		if owned_total(item) <= 0:
			_give(item)
		return
	inventory.erase(StringName(item))
	for c in chickens:
		if StringName(c["weapon"]) == item:
			c["weapon"] = &""
		for slot in Items.GEAR_SLOTS:
			if StringName(c["gear"][slot]) == item:
				c["gear"][slot] = &""


## Bật/tắt món cho gà đang chọn (prebattle cũ). Kho hết mà con gà khác đang gắn → lấy từ con đó sang.
static func _set_equipped(item: StringName, value: bool) -> void:
	var slot: StringName = Items.slot_of(item)
	if not value:
		if equipped(active, slot) == item:
			equip(active, slot, &"")
		return
	if equipped(active, slot) == item:
		return
	if item_count(item) <= 0:
		for i in range(chickens.size()):
			if i != active and equipped(i, slot) == item:
				equip(i, slot, &"")
				break
	equip(active, slot, item)


# =================================================================== Technology, Biotech, đột biến, ấp trứng

## Đổi Technology → Biotech (10 → 1). count = số Biotech muốn nhận.
static func exchange_biotech(count: int) -> bool:
	if count <= 0:
		return _fail("Số lượng không hợp lệ.")
	var need: int = count * Mutations.TECH_PER_BIOTECH
	if technology < need:
		return _fail("Cần %d Technology (đang có %d)." % [need, technology])
	technology -= need
	biotech += count
	return _ok()


## Đột biến gà ở chỉ số index (trả Biotech; luôn có đánh đổi – MUTATIONS). Mở từ Act 2.
static func mutate(index: int, mutation: StringName) -> bool:
	if not _valid_index(index):
		return _fail("Không có con gà này.")
	if not Mutations.has(mutation):
		return _fail("Không có đột biến này.")
	if current_act() < Mutations.UNLOCK_ACT:
		return _fail("Biotech mở ở Act 2.")
	var muts: Array = chickens[index]["mutations"]
	if muts.has(StringName(mutation)):
		return _fail("Con này đột biến %s rồi." % Mutations.display_name(mutation))
	if biotech < Mutations.cost(mutation):
		return _fail("Cần %d Biotech." % Mutations.cost(mutation))
	biotech -= Mutations.cost(mutation)
	muts.append(StringName(mutation))
	return _ok()


## Bỏ một quả trứng trong kho vào lò ấp cùng biotech_spent Biotech (≥ biotech_min của trứng).
static func start_incubation(egg: StringName, biotech_spent: int) -> bool:
	var info: Dictionary = Items.get_item(egg)
	if info.is_empty() or StringName(info["slot"]) != &"egg":
		return _fail("Hổng phải trứng.")
	if item_count(egg) <= 0:
		return _fail("Trong kho hết %s." % String(info["name"]))
	if incubator.size() >= INCUBATOR_SLOTS:
		return _fail("Lò ấp đầy rồi (%d trứng)." % INCUBATOR_SLOTS)
	if biotech_spent < int(info["biotech_min"]):
		return _fail("Trứng này cần ít nhất %d Biotech." % int(info["biotech_min"]))
	if biotech < biotech_spent:
		return _fail("Không đủ Biotech.")
	_take(egg)
	biotech -= biotech_spent
	incubator.append({"egg": StringName(egg), "days_left": int(info["incubate_days"]), "biotech": biotech_spent,
		"started_day": day})
	return _ok()


## Chỉ số các trứng đã đủ ngày (days_left ≤ 0) trong `incubator`.
static func hatch_ready() -> Array:
	var out: Array = []
	for i in range(incubator.size()):
		if int(incubator[i]["days_left"]) <= 0:
			out.append(i)
	return out


## Nở trứng i thành gà Lv1. Giống: theo trứng (Trứng lạ: Đông Tảo với xác suất rare_breed_chance, còn lại nòi/tre);
## 1 đột biến ngẫu nhiên với xác suất hatch_mutation_chance (Biotech bỏ thêm càng nhiều càng dễ). Bốc thăm bằng
## GameState.rng (seed được trong test). Trả về chỉ số gà mới, −1 nếu chưa đủ ngày / chuồng đầy.
static func hatch(i: int, p_name: String = "") -> int:
	if i < 0 or i >= incubator.size():
		_fail("Không có trứng này.")
		return -1
	if int(incubator[i]["days_left"]) > 0:
		_fail("Trứng chưa nở (còn %d ngày)." % int(incubator[i]["days_left"]))
		return -1
	if coop_full():
		_fail("Chuồng đầy rồi, nâng chuồng hoặc bớt gà đã.")
		return -1
	var entry: Dictionary = incubator[i]
	var info: Dictionary = Items.get_item(entry["egg"])
	var extra: int = maxi(int(entry["biotech"]) - int(info.get("biotech_min", 0)), 0)
	var egg_breed: int = int(info.get("breed", 0))
	if egg_breed < 0:
		if rng.randf() < Mutations.rare_breed_chance(extra):
			egg_breed = Breeds.GA_DONG_TAO
		else:
			egg_breed = Breeds.GA_NOI if rng.randf() < 0.5 else Breeds.GA_TRE
	var rare: bool = StringName(info.get("rarity", &"common")) == &"rare"
	var mutation: StringName = &""
	if rng.randf() < Mutations.hatch_mutation_chance(extra, rare):
		mutation = Mutations.ORDER[rng.randi_range(0, Mutations.ORDER.size() - 1)]
	var index: int = add_chicken(egg_breed, p_name)
	if index < 0:
		return -1
	if mutation != &"":
		(chickens[index]["mutations"] as Array).append(mutation)
	incubator.remove_at(i)
	return index


# =================================================================== lịch & giờ (GDD 3.3, 3.6)

## 0 = Thứ 2 … 6 = Chủ nhật (ngày 1 = Thứ 2).
static func weekday() -> int:
	return Calendar.weekday(day)


## "Thứ 2" … "Chủ nhật".
static func weekday_name() -> String:
	return Calendar.weekday_name(day)


static func week() -> int:
	return Calendar.week(day)


## Thứ 2 – Thứ 6 (đi học buổi Sáng).
static func is_school_day() -> bool:
	return Calendar.is_school_day(day)


static func is_weekend() -> bool:
	return Calendar.is_weekend(day)


## Buổi hiện tại (Period.SANG … Period.KHUYA).
static func period() -> int:
	return Calendar.period_of(minutes)


static func period_name() -> String:
	return Calendar.period_name_of(minutes)


## Giờ dạng "07:30".
static func time_text() -> String:
	return Calendar.clock_text_of(minutes)


## "Thứ 2 · 07:30 · Sáng".
static func clock_text() -> String:
	return "%s · %s · %s" % [weekday_name(), time_text(), period_name()]


## "Thứ 2 · Ngày 1 · 07:00 (Sáng)".
static func date_text() -> String:
	return "%s · Ngày %d · %s (%s)" % [weekday_name(), day, time_text(), period_name()]


## Đồng hồ ngày có "chạy" không (có ép đi ngủ lúc 23:00). GDD 3.6: Act 1 chưa có đồng hồ ngày → giờ vẫn được ghi
## nhưng kẹt ở 22:59 và không bao giờ ép ngủ/chặn việc gì.
static func clock_running() -> bool:
	return current_act() >= 2


static func minutes_left() -> int:
	return maxi(0, DAY_END - minutes)


## Còn đủ giờ cho việc tốn minutes_cost phút (Act 1 luôn true).
static func can_spend(minutes_cost: int) -> bool:
	if not clock_running():
		return true
	return minutes_cost >= 0 and minutes + minutes_cost <= DAY_END


## Trôi giờ. Trả về true nếu ngày đã hết (≥ 23:00) → nơi gọi đưa người chơi về nhà ngủ (end_day()).
static func spend_time(minutes_cost: int) -> bool:
	if minutes_cost > 0:
		minutes += minutes_cost
		if not clock_running():
			minutes = mini(minutes, DAY_END - 1)
		_notify_time()
	return day_over()


## Đã quá giờ (≥ 23:00) khi đồng hồ ngày đang chạy.
static func day_over() -> bool:
	return clock_running() and minutes >= DAY_END


## Đặt giờ trực tiếp (debug/test/sự kiện truyện).
static func set_time(p_day: int, p_minutes: int) -> void:
	day = maxi(1, p_day)
	minutes = clampi(p_minutes, 0, 24 * 60)
	_notify_time()


static func time_cost(activity: StringName) -> int:
	return Calendar.cost_of(activity)


## Làm một hoạt động trong GameCalendar.ACTIVITIES: kiểm giờ, trôi giờ, cộng tiền (× hệ số minigame 0,5–1,3) và
## Technology. Trả về {ok, reason, minutes, money, technology, day_over}.
static func perform(activity: StringName, minigame_factor: float = 1.0) -> Dictionary:
	var info: Dictionary = Calendar.ACTIVITIES.get(activity, {})
	var out: Dictionary = {"ok": false, "reason": "", "minutes": 0, "money": 0, "technology": 0, "day_over": false}
	if info.is_empty():
		out["reason"] = "Không có việc này."
		return out
	if bool(info.get("school_day_only", false)) and not is_school_day():
		out["reason"] = "Thứ 7, Chủ nhật hổng có học."
		return out
	var cost: int = int(info["minutes"])
	if not can_spend(cost):
		out["reason"] = "Hổng đủ giờ trong ngày."
		return out
	var factor: float = clampf(minigame_factor, Calendar.MINIGAME_FACTOR_MIN, Calendar.MINIGAME_FACTOR_MAX)
	var gained: int = int(round(float(info.get("money", 0)) * factor))
	money += gained
	technology += int(info.get("technology", 0))
	out["ok"] = true
	out["minutes"] = cost
	out["money"] = gained
	out["technology"] = int(info.get("technology", 0))
	out["day_over"] = spend_time(cost)
	return out


## Ngủ / hết ngày: sang ngày mới 07:00 (08:00 nếu bị ép vì quá 23:00 – forced, hoặc tự suy khi minutes ≥ 23:00).
## Với mọi con gà (khi đã nhận gà – stage ≥ TUTORIAL): +30 Thể trạng (tối đa 100), chưa ăn bữa chính hôm đó −20;
## xóa fed_today / trained_today. Lò ấp −1 ngày. Mở lại việc làm thêm (Activities). Không tự lưu (nơi gọi lưu).
## Trả về tóm tắt cho báo cáo buổi sáng: {from_day, day, weekday, weekday_name, forced, wake, clock,
##  chickens: [{index, id, name, before, after, fed}], hatch_ready: [chỉ số lò ấp], incubator: [{egg, name, days_left}]}.
static func end_day(forced: bool = false) -> Dictionary:
	forced = forced or minutes >= DAY_END
	var summary: Dictionary = {"from_day": day, "forced": forced, "chickens": []}
	var has_chicken: bool = stage >= Stage.TUTORIAL
	for i in range(chickens.size()):
		var c: Dictionary = chickens[i]
		var before: float = float(c["condition"])
		var after: float = before
		if has_chicken:
			after = minf(before + CONDITION_SLEEP_RECOVERY, CONDITION_MAX)
			if not bool(c["fed_today"]):
				after -= CONDITION_UNFED_PENALTY
		c["condition"] = clampf(after, 0.0, CONDITION_MAX)
		(summary["chickens"] as Array).append({"index": i, "id": int(c["id"]), "name": String(c["name"]),
			"before": before, "after": float(c["condition"]), "fed": bool(c["fed_today"])})
		c["fed_today"] = false
		c["trained_today"] = 0
	for egg in incubator:
		egg["days_left"] = maxi(int(egg["days_left"]) - 1, 0)
	day += 1
	minutes = FORCED_WAKE if forced else DAY_START
	summary["day"] = day
	summary["weekday"] = weekday()
	summary["weekday_name"] = weekday_name()
	summary["wake"] = minutes
	summary["clock"] = clock_text()
	summary["hatch_ready"] = hatch_ready()
	var eggs: Array = []
	for egg in incubator:
		eggs.append({"egg": StringName(egg["egg"]), "name": Items.display_name(egg["egg"]), "days_left": int(egg["days_left"])})
	summary["incubator"] = eggs
	var acts: Script = load(ACTIVITIES_SCRIPT)
	if acts != null:
		acts.call("on_day_changed")
	_notify_time()
	return summary


## Tên cũ (bản nháp v2) của end_day().
static func sleep() -> Dictionary:
	return end_day()


## Các dòng báo cáo buổi sáng (tiếng Việt) dựng từ tóm tắt của end_day().
static func morning_lines(summary: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var head: String = "%s · Ngày %d · %s." % [String(summary.get("weekday_name", weekday_name())), int(summary.get("day", day)),
		Calendar.clock_text_of(int(summary.get("wake", minutes)))]
	if bool(summary.get("forced", false)):
		head += " Hôm qua thức khuya quá nên dậy trễ."
	head += " Hôm nay đi học." if Calendar.is_school_day(int(summary.get("day", day))) else " Hôm nay được nghỉ học."
	lines.append(head)
	if stage >= Stage.TUTORIAL:
		var parts: PackedStringArray = []
		for entry in summary.get("chickens", []):
			var note: String = "" if bool(entry["fed"]) else " (bỏ đói)"
			parts.append("%s %d%%%s" % [String(entry["name"]), int(round(float(entry["after"]))), note])
		if not parts.is_empty():
			lines.append("Thể trạng: " + ", ".join(parts) + ".")
	for i in summary.get("hatch_ready", []):
		if int(i) < incubator.size():
			lines.append("%s trong lò ấp đã tới ngày nở!" % Items.display_name(incubator[int(i)]["egg"]))
	return lines


## Đăng ký hàm nhận báo khi giờ/ngày đổi (spend_time, end_day, set_time, reset, load_save). Hàm không có tham số.
static func add_listener(c: Callable) -> void:
	if not _listeners.has(c):
		_listeners.append(c)


static func remove_listener(c: Callable) -> void:
	_listeners.erase(c)


static func _notify_time() -> void:
	for c in _listeners.duplicate():
		if c.is_valid():
			c.call()
		else:
			_listeners.erase(c)


# =================================================================== giải đấu (dữ liệu: TournamentCatalog)

static func _progress(tid: StringName) -> Dictionary:
	var key: String = String(tid)
	if not tournament_progress.has(key):
		tournament_progress[key] = {"round": 0, "registered": false, "champion": false, "eliminated_week": 0}
	return tournament_progress[key]


static func is_champion(tid: StringName) -> bool:
	if tid == &"ao_lang" and stage >= Stage.CHAMPION:
		return true
	return bool((tournament_progress.get(String(tid), {}) as Dictionary).get("champion", false))


## Hôm nay có giải này không (TournamentCatalog weekdays; GDD 3.1 "thi giải cuối tuần").
static func is_tournament_day(tid: StringName) -> bool:
	return (Tournaments.info(tid).get("weekdays", []) as Array).has(weekday())


## Danh hiệu cao nhất người chơi đã giành (0..3).
static func best_title() -> int:
	var best: int = 1 if stage >= Stage.CHAMPION else 0
	for tid in Tournaments.ORDER:
		if bool((tournament_progress.get(String(tid), {}) as Dictionary).get("champion", false)):
			best = maxi(best, int(Tournaments.info(tid)["title"]))
	return best


## Kiểm tra điều kiện đăng ký giải cho gà đang chọn (hoặc gà ở chỉ số index). check_day: kiểm cả ngày có giải.
## Trả về {ok: bool, reasons: PackedStringArray}.
static func can_enter(tid: StringName, index: int = -1, check_day: bool = false) -> Dictionary:
	var reasons: PackedStringArray = []
	var info: Dictionary = Tournaments.info(tid)
	if info.is_empty():
		return {"ok": false, "reasons": PackedStringArray(["Không có giải này."])}
	var who: Dictionary = chickens[index] if _valid_index(index) else active_chicken()
	var entry: Dictionary = info["entry"]
	var progress: Dictionary = tournament_progress.get(String(tid), {})
	if is_champion(tid):
		reasons.append("Đã vô địch giải này rồi.")
	if best_title() < int(entry["min_title"]):
		reasons.append("Phải vô địch giải trước đã.")
	if int(who["level"]) < int(entry["min_level"]):
		reasons.append("Gà phải đạt Lv%d." % int(entry["min_level"]))
	if (who["mutations"] as Array).size() < int(entry["min_mutations"]):
		reasons.append("Gà phải qua ít nhất %d đột biến." % int(entry["min_mutations"]))
	if not bool(progress.get("registered", false)) and money < int(entry["fee"]):
		reasons.append("Không đủ lệ phí %s." % money_text(int(entry["fee"])))
	if int(progress.get("eliminated_week", 0)) == week():
		reasons.append("Bị loại tuần này rồi, tuần sau đăng ký lại.")
	if check_day and not is_tournament_day(tid):
		reasons.append("Hôm nay không có giải.")
	return {"ok": reasons.is_empty(), "reasons": reasons}


## Đăng ký giải bằng gà đang chọn (trừ lệ phí, vào vòng 1).
static func register_tournament(tid: StringName, check_day: bool = false) -> bool:
	var progress: Dictionary = tournament_progress.get(String(tid), {})
	if bool(progress.get("registered", false)):
		return _ok()
	var check: Dictionary = can_enter(tid, -1, check_day)
	if not bool(check["ok"]):
		return _fail(" ".join(check["reasons"]))
	money -= int(Tournaments.info(tid)["entry"]["fee"])
	var p: Dictionary = _progress(tid)
	p["registered"] = true
	p["round"] = 0
	return _ok()


## Vòng hiện tại (0-based) của giải; −1 nếu chưa đăng ký.
static func league_round(tid: StringName) -> int:
	var progress: Dictionary = tournament_progress.get(String(tid), {})
	return int(progress.get("round", 0)) if bool(progress.get("registered", false)) else -1


## Id đối thủ vòng hiện tại ("" nếu chưa đăng ký / đã xong).
static func current_round_opponent(tid: StringName) -> String:
	var r: int = league_round(tid)
	var rounds: Array = Tournaments.rounds(tid)
	if r < 0 or r >= rounds.size():
		return ""
	return String(rounds[r])


## Bên đấu của đối thủ vòng kế tiếp (đã gắn luật giải: start_card_gauge, round_time, hell_mode). {} nếu không có.
static func next_league_opponent(tid: StringName) -> Dictionary:
	var config: Dictionary = match_config(tid)
	return config.get("opponent", {})


## Cấu hình trận giải vòng hiện tại (dạng BattleDirector.setup + khóa mới):
## {player, opponent (có start_card_gauge, round_time, hell_mode), mode "tournament", tournament, round (0-based),
##  rounds, title, round_time, opponent_start_card_gauge, hell_mode, prize}. {} nếu chưa đăng ký.
static func match_config(tid: StringName) -> Dictionary:
	var opp_id: String = current_round_opponent(tid)
	if opp_id == "":
		return {}
	var info: Dictionary = Tournaments.info(tid)
	var r: int = league_round(tid)
	var n: int = Tournaments.round_count(tid)
	var raw: Dictionary = opponent_data(opp_id).duplicate(true)
	raw["start_card_gauge"] = int(info["opponent_start_card_gauge"])
	raw["round_time"] = float(info["round_time"])
	raw["hell_mode"] = bool(info["hell_mode"])
	var opponent: Dictionary = side_from_raw(raw)
	opponent["id"] = opp_id
	var round_title: String = "CHUNG KẾT" if r == n - 1 else "VÒNG %d/%d" % [r + 1, n]
	return {
		"player": player_side(), "opponent": opponent, "mode": "tournament", "tournament": String(tid),
		"round": r, "rounds": n, "title": "%s – %s" % [String(info["name"]).to_upper(), round_title],
		"round_time": float(info["round_time"]), "opponent_start_card_gauge": int(info["opponent_start_card_gauge"]),
		"hell_mode": bool(info["hell_mode"]),
		"prize": int(info["prize_money"]) if r == n - 1 else int(info["round_prize"]),
	}


## Ghi kết quả trận giải của gà đang chọn (gọi record_result bên trong – KHÔNG cộng EXP). Thắng: tiền vòng, sang vòng
## kế; thắng chung kết: tiền + Biotech + danh hiệu, mở Act kế. Thua: bị loại, tuần sau đăng ký lại.
## Trả về {ok, champion, eliminated, money, biotech, title}.
static func tournament_result(tid: StringName, won: bool) -> Dictionary:
	var out: Dictionary = {"ok": false, "champion": false, "eliminated": false, "money": 0, "biotech": 0, "title": 0}
	var info: Dictionary = Tournaments.info(tid)
	var progress: Dictionary = tournament_progress.get(String(tid), {})
	if info.is_empty() or not bool(progress.get("registered", false)):
		return out
	out["ok"] = true
	record_result(won)
	if not won:
		progress["registered"] = false
		progress["round"] = 0
		progress["eliminated_week"] = week()
		out["eliminated"] = true
		return out
	var r: int = int(progress["round"])
	if r >= Tournaments.round_count(tid) - 1:
		out["champion"] = true
		out["money"] = int(info["prize_money"])
		out["biotech"] = int(info["prize_biotech"])
		out["title"] = int(info["title"])
		money += out["money"]
		biotech += out["biotech"]
		award_title(active, int(info["title"]))
		progress["champion"] = true
		progress["registered"] = false
		progress["round"] = Tournaments.round_count(tid)
		act = clampi(maxi(act, int(info["title"]) + 1), 1, 4)
	else:
		out["money"] = int(info["round_prize"])
		money += out["money"]
		progress["round"] = r + 1
	return out


# =================================================================== tiện ích

static func money_text(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out + "đ"


# =================================================================== lưu / tải

## GDD 6.1 / Bảng 8.1: [MVP] ngủ ở nhà = lưu game. Bản 3 (meta/version); vẫn ghi các khóa v1 ở [game] cho gà đang
## chọn để dễ đọc/khôi phục.
static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("game", "stage", stage)
	cfg.set_value("game", "player_name", player_name)
	cfg.set_value("game", "money", money)
	cfg.set_value("game", "act", act)
	var card_names: PackedStringArray = []
	for card in cards:
		card_names.append(String(card))
	cfg.set_value("game", "cards", card_names)
	# Khóa v1 – chỉ để tham khảo, load v3 không đọc.
	cfg.set_value("game", "chicken_name", chicken_name)
	cfg.set_value("game", "breed", breed)
	cfg.set_value("game", "level", level)
	cfg.set_value("game", "exp", xp)
	cfg.set_value("game", "wins", wins)
	cfg.set_value("game", "owns_mao_sat", owns_mao_sat)
	cfg.set_value("game", "owns_dao_chan", owns_dao_chan)
	cfg.set_value("game", "equip_mao_sat", equip_mao_sat)
	cfg.set_value("game", "equip_dao_chan", equip_dao_chan)
	var roster: Array = []
	for c in chickens:
		roster.append(_chicken_to_save(c))
	cfg.set_value("roster", "chickens", roster)
	cfg.set_value("roster", "active", active)
	cfg.set_value("roster", "next_chicken_id", next_chicken_id)
	cfg.set_value("roster", "coop_level", coop_level)
	var inv: Dictionary = {}
	for id in inventory:
		inv[String(id)] = int(inventory[id])
	cfg.set_value("items", "inventory", inv)
	cfg.set_value("lab", "technology", technology)
	cfg.set_value("lab", "biotech", biotech)
	cfg.set_value("lab", "kho_ga", kho_ga)
	var eggs: Array = []
	for egg in incubator:
		eggs.append({"egg": String(egg["egg"]), "days_left": int(egg["days_left"]), "biotech": int(egg["biotech"]),
			"started_day": int(egg.get("started_day", day))})
	cfg.set_value("lab", "incubator", eggs)
	cfg.set_value("calendar", "day", day)
	cfg.set_value("calendar", "minutes", minutes)
	cfg.set_value("tournaments", "progress", tournament_progress.duplicate(true))
	cfg.save(save_path)


static func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Tải save (mọi phiên bản: v1 một con gà, v2 bản nháp, v3). Trả về false nếu không đọc được file.
static func load_save() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return false
	reset()
	var version: int = int(cfg.get_value("meta", "version", 1))
	stage = int(cfg.get_value("game", "stage", stage))
	player_name = String(cfg.get_value("game", "player_name", player_name))
	money = int(cfg.get_value("game", "money", money))
	cards = []
	for card in cfg.get_value("game", "cards", PackedStringArray()):
		cards.append(StringName(card))
	if version < 2:
		_migrate_v1(cfg)
		_notify_time()
		return true
	act = clampi(int(cfg.get_value("game", "act", 1)), 1, 4)
	chickens = []
	for d in cfg.get_value("roster", "chickens", []):
		chickens.append(_chicken_from_save(d))
	next_chicken_id = int(cfg.get_value("roster", "next_chicken_id", 1))
	for c in chickens:
		next_chicken_id = maxi(next_chicken_id, int(c["id"]) + 1)
	if chickens.is_empty():
		chickens.append(_new_chicken(Breeds.GA_NOI, "Ô Mun"))
	var saved_active: int = int(cfg.get_value("roster", "active", cfg.get_value("roster", "active_index", 0)))
	active = clampi(saved_active, 0, chickens.size() - 1)
	coop_level = clampi(int(cfg.get_value("roster", "coop_level", 1)), 1, COOP_CAPACITY.size())
	inventory = {}
	var inv: Dictionary = cfg.get_value("items", "inventory", {})
	for id in inv:
		if Items.has(StringName(id)) and int(inv[id]) > 0:
			inventory[StringName(id)] = int(inv[id])
	if version == 2:
		# Bản nháp v2 đếm cả món đang gắn trong inventory → trừ ra.
		for id in inventory.keys():
			var left: int = int(inventory[id]) - equipped_count(id)
			if left > 0:
				inventory[id] = left
			else:
				inventory.erase(id)
	technology = int(cfg.get_value("lab", "technology", 0))
	biotech = int(cfg.get_value("lab", "biotech", 0))
	kho_ga = float(cfg.get_value("lab", "kho_ga", 0.0))
	incubator = []
	var eggs: Array = cfg.get_value("lab", "incubator", cfg.get_value("lab", "eggs", []))
	for e in eggs:
		var egg: StringName = StringName(e.get("egg", e.get("item", "")))
		if Items.is_egg(egg):
			incubator.append({"egg": egg, "days_left": maxi(int(e.get("days_left", 0)), 0),
				"biotech": int(e.get("biotech", e.get("biotech_spent", 0))), "started_day": int(e.get("started_day", 1))})
	day = maxi(1, int(cfg.get_value("calendar", "day", 1)))
	minutes = clampi(int(cfg.get_value("calendar", "minutes", DAY_START)), 0, 24 * 60)
	tournament_progress = (cfg.get_value("tournaments", "progress", {}) as Dictionary).duplicate(true)
	_notify_time()
	return true


## Save v1: một con gà (chicken_name/breed/level/exp/wins) + cờ owns_*/equip_*. Ngày nằm ở file thế giới
## (Activities) → bật legacy_day_pending để Activities.load_save() lấy lại.
static func _migrate_v1(cfg: ConfigFile) -> void:
	var c: Dictionary = active_chicken()
	c["name"] = String(cfg.get_value("game", "chicken_name", "Ô Mun"))
	c["breed"] = clampi(int(cfg.get_value("game", "breed", 0)), 0, BREED_STATS.size() - 1)
	c["level"] = maxi(1, int(cfg.get_value("game", "level", 1)))
	c["xp"] = int(cfg.get_value("game", "exp", 0))
	c["wins"] = int(cfg.get_value("game", "wins", 0))
	if stage >= Stage.CHAMPION:
		award_title(active, 1)
	owns_mao_sat = bool(cfg.get_value("game", "owns_mao_sat", false))
	owns_dao_chan = bool(cfg.get_value("game", "owns_dao_chan", false))
	equip_mao_sat = bool(cfg.get_value("game", "equip_mao_sat", false))
	equip_dao_chan = bool(cfg.get_value("game", "equip_dao_chan", false))
	legacy_day_pending = true


static func _chicken_to_save(c: Dictionary) -> Dictionary:
	var muts: PackedStringArray = []
	for m in c["mutations"]:
		muts.append(String(m))
	var gear: Dictionary = {}
	for slot in Items.GEAR_SLOTS:
		gear[String(slot)] = String(c["gear"].get(slot, &""))
	var titles: PackedStringArray = []
	for t in c["titles"]:
		titles.append(String(t))
	return {
		"id": int(c["id"]), "name": String(c["name"]), "breed": int(c["breed"]), "level": int(c["level"]),
		"xp": int(c["xp"]), "condition": float(c["condition"]), "wins": int(c["wins"]), "losses": int(c["losses"]),
		"fed_today": bool(c["fed_today"]), "weapon": String(c["weapon"]), "gear": gear, "mutations": muts,
		"hue_seed": int(c["hue_seed"]), "titles": titles, "trained_today": int(c["trained_today"]),
		"born_day": int(c["born_day"]),
	}


## Đọc một con gà từ save v3 – hoặc bản nháp v2 (khóa lv / equip gồm cả weapon / title int).
static func _chicken_from_save(d: Dictionary) -> Dictionary:
	var muts: Array[StringName] = []
	for m in d.get("mutations", PackedStringArray()):
		if Mutations.has(StringName(m)) and not muts.has(StringName(m)):
			muts.append(StringName(m))
	var gear: Dictionary = _empty_gear()
	var saved_gear: Dictionary = d.get("gear", d.get("equip", {}))
	for slot in Items.GEAR_SLOTS:
		var id: StringName = StringName(saved_gear.get(String(slot), ""))
		gear[slot] = id if Items.slot_of(id) == slot else &""
	var weapon: StringName = StringName(d.get("weapon", saved_gear.get("weapon", "")))
	if Items.slot_of(weapon) != &"weapon":
		weapon = &""
	var titles: Array[String] = []
	for t in d.get("titles", PackedStringArray()):
		titles.append(String(t))
	var old_title: int = clampi(int(d.get("title", 0)), 0, TITLE_NAMES.size() - 1)
	if old_title > 0 and not titles.has(TITLE_NAMES[old_title]):
		titles.append(TITLE_NAMES[old_title])
	return {
		"id": int(d.get("id", 0)), "name": String(d.get("name", "Ô Mun")),
		"breed": clampi(int(d.get("breed", 0)), 0, BREED_STATS.size() - 1),
		"level": maxi(1, int(d.get("level", d.get("lv", 1)))), "xp": int(d.get("xp", 0)),
		"condition": clampf(float(d.get("condition", CONDITION_MAX)), 0.0, CONDITION_MAX),
		"wins": int(d.get("wins", 0)), "losses": int(d.get("losses", 0)), "fed_today": bool(d.get("fed_today", false)),
		"weapon": weapon, "gear": gear, "mutations": muts, "hue_seed": int(d.get("hue_seed", 0)), "titles": titles,
		"trained_today": int(d.get("trained_today", 0)), "born_day": int(d.get("born_day", 1)),
	}
