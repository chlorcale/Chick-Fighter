class_name GameState
extends RefCounted

## Trạng thái phiên chơi – v2 (đàn gà, kho đồ, Biotech/đột biến, ấp trứng, Khô Gà, lịch/giờ, giải đấu).
## Số liệu theo GDD v1.2/v2: Bảng 5.1–5.5 (giống, vũ khí, trang bị, đột biến), 6.1 (Thể trạng), 7.1–7.5 (kinh tế,
## bảy công thức, đường cong độ khó), 3.3/3.6 (ngày 5 buổi, Time Cost), 9.3 (Hell Mode).
## Hợp đồng API cho các agent khác: docs/technical/GameState_v2_API.md.
##
## Tương thích ngược: các tên tĩnh cũ (chicken_name, breed, level, xp, wins, owns_*, equip_*, cards, money…) vẫn
## đọc/ghi được như trước – chicken_name/breed/level/xp/wins/equip_* trỏ vào gà đang chọn (active()), owns_* trỏ vào
## kho đồ (inventory). player_side() = chicken_side(active()).

const Breeds := preload("res://game/data/breeds.gd")
const Items := preload("res://game/data/items.gd")
const Mutations := preload("res://game/data/mutations.gd")
const Tournaments := preload("res://game/data/tournaments.gd")
const Calendar := preload("res://game/data/calendar.gd")

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

## Mã kết quả của các thao tác (buy/equip/feed/…). result_text() cho câu tiếng Việt.
enum Result {
	OK, UNKNOWN, LOCKED, NO_MONEY, NO_KHO_GA, NO_BIOTECH, NO_TECHNOLOGY, NOT_OWNED, NOT_AVAILABLE, WRONG_KIND,
	NO_CHICKEN, COOP_FULL, MAX_LEVEL, ALREADY_FED, ALREADY_HAS, LAST_CHICKEN, INCUBATOR_FULL, NOT_READY, NO_TIME,
	NOT_ALLOWED, TOO_TIRED,
}
const RESULT_TEXT: Array[String] = [
	"Xong.", "Không có món này.", "Chưa mở khóa.", "Không đủ tiền.", "Không đủ Khô Gà.", "Không đủ Biotech.",
	"Không đủ Technology.", "Chưa có món này.", "Món này đang gắn cho gà khác.", "Không dùng được kiểu này.",
	"Không có con gà này.", "Chuồng đã đầy.", "Đã tối đa.", "Hôm nay gà đã ăn bữa chính rồi.", "Đã có rồi.",
	"Không được bỏ con gà cuối cùng.", "Lò ấp đã đầy.", "Chưa tới lúc.", "Không đủ thời gian trong ngày.",
	"Không đủ điều kiện.", "Gà mệt quá, cho nghỉ đã.",
]

const SAVE_PATH: String = "user://chick_fighter_save.cfg"
const SAVE_VERSION: int = 2
const BREED_NAMES: Array[String] = ["Gà nòi", "Gà tre", "Gà Đông Tảo"]
## Chỉ số 3 (Gà Đông Tảo, tank – Owner yêu cầu, theo dongtao_fight_movelist.md): HP 130% gà nòi, đi 70%
## (preset MovementConfig.GA_DONG_TAO = 140 px/s), bị đẩy lùi 50% → WEIGHT 12 (công thức 2: √(3/12) = 0,5).
## PLACEHOLDER: atk/def/crit của Đông Tảo.
const BREED_STATS: Array[Dictionary] = [
	{"hp": 100, "atk": 10.0, "def": 2.0, "spd": 200, "weight": 3.0, "crit": 0.05},
	{"hp": 80, "atk": 9.0, "def": 0.0, "spd": 260, "weight": 1.6, "crit": 0.10},
	{"hp": 130, "atk": 10.0, "def": 2.0, "spd": 140, "weight": 12.0, "crit": 0.03},
]
const PRICE_MAO_SAT: int = 150000
const PRICE_DAO_CHAN: int = 200000
const PRICE_CAM: int = 40000
const CAM_EXP: int = 20

## Cap level theo Act (GDD 7.5): Act 1 Lv5, Act 2 Lv15, Act 3–4 Lv30.
const ACT_LEVEL_CAPS: Array[int] = [5, 15, 30, 30]
## Chuồng (GDD 6, 7.2): sức chứa theo cấp chuồng 1..5; giá nâng lên cấp 2..5 = 0,5 / 1,5 / 4 / 10 triệu.
const COOP_CAPACITY: Array[int] = [3, 5, 8, 12, 20]
const COOP_UPGRADE_PRICE: Array[int] = [500000, 1500000, 4000000, 10000000]
## Thể trạng (GDD 6.1). Ban đêm: ngủ +30 (tối đa 100) rồi bỏ đói −20; ăn bữa chính (Lúa) → về 100.
const CONDITION_MAX: int = 100
const CONDITION_WEAK: int = 50              # dưới mức này −10% ATK trong trận
const CONDITION_WEAK_ATK_MULT: float = 0.9
const CONDITION_LOSS_ON_DEFEAT: int = 15
const CONDITION_UNFED_PENALTY: int = 20
const CONDITION_SLEEP_RECOVERY: int = 30
## Luyện gà (PLACEHOLDER – GDD chỉ nói "luyện gà" cho EXP ở buổi Chiều): 1 giờ, EXP = 25% EXP cần để lên cấp,
## −10 Thể trạng, tối đa 3 lần/ngày/con, cần Thể trạng ≥ 30.
const TRAIN_EXP_FRACTION: float = 0.25
const TRAIN_CONDITION_COST: int = 10
const TRAIN_PER_DAY: int = 3
const TRAIN_MIN_CONDITION: int = 30
## Công thức 6: hệ số danh hiệu 1,0 · Ao Làng 1,2 · Liên tỉnh 1,5 · Olympic 2,0.
const TITLE_SELL_MULT: Array[float] = [1.0, 1.2, 1.5, 2.0]
const TITLE_NAMES: Array[String] = ["", "Vô địch Ao Làng", "Vô địch Liên tỉnh", "Huyền Thoại Đá Gà"]
## Công thức 7: Khô Gà (kg) = WEIGHT × 0,4 (WEIGHT thân gà: giống + đột biến, không tính đồ).
const KHO_GA_PER_WEIGHT: float = 0.4
const INCUBATOR_SLOTS: int = 2              # PLACEHOLDER
## "Gọi tay trong": hiện lựa chọn khi power_gap(đối thủ) ≥ ngưỡng này. PLACEHOLDER.
const INSIDE_MAN_GAP: float = 1.6
## Hệ số AI cho power_rating theo tier (0 = người chơi/không có tier ≈ ngang AI T2). PLACEHOLDER.
const TIER_POWER: Array[float] = [1.0, 0.9, 1.05, 1.23, 1.3]

const CARD_INFO: Dictionary = {
	&"cuong_no": {"name": "Cuồng Nộ", "cost": 2, "color": Color(0.85, 0.25, 0.2), "text": "+30% ATK trong 5 giây"},
	&"mai_rua": {"name": "Mai Rùa", "cost": 1, "color": Color(0.25, 0.5, 0.9), "text": "−25% sát thương nhận vào trong 5 giây"},
	&"gio_song": {"name": "Gió Sông", "cost": 2, "color": Color(0.2, 0.65, 0.85), "text": "Heavy +50% đẩy lùi trong 6 giây"},
}

## Bảng 8.3. Đối thủ: gà đá mặc định đổi màu xen kẽ với Gà Đông Tảo (breed 2 → kit "dongtao").
##  colors: đổi màu theo bộ phận {"body"|"neck"|"tail"|"legs"|"comb": [lệch hue, ×sat, ×value]} (rooster.gdshader);
##          hue/sat cũ vẫn dùng được (áp lên toàn bộ lông, giữ mào/chân/mắt).
##  tier 1–3 + skill 0..1 (PLACEHOLDER) và tính cách aggr / jumpy / block cho EnemyAI.
##  spar: đối thủ dữ liệu cho chế độ đấu tự do sau này (chưa gắn vào cốt truyện).
## Đối thủ Liên tỉnh / Olympic: TournamentCatalog.OPPONENTS (dùng opponent_data / opponent_side cho cả hai bảng).
const OPPONENTS: Dictionary = {
	"chu_tu": {"owner": "Chú Tư", "name": "Ông Tướng", "breed": 0, "lv": 1, "tier": 1, "skill": 0.15,
		"aggr": 0.2, "jumpy": 0.0, "block": 0.10, "hue": 0.0, "sat": 0.35, "exp_bonus": 40,
		"colors": {"comb": [0.0, 0.8, 0.9]}, "portrait": "chu_tu"},
	"teo_1": {"owner": "Tèo", "name": "Tia Chớp", "breed": 1, "lv": 2, "tier": 1, "skill": 0.25,
		"aggr": 0.5, "jumpy": 0.1, "block": 0.10, "portrait": "teo",
		"colors": {"body": [0.15, 1.05, 1.25], "neck": [0.05, 0.75, 1.15], "tail": [-0.22, 1.0, 1.5]}},
	"ut_map": {"owner": "Út Mập", "name": "Lửa Đỏ", "breed": 0, "lv": 2, "tier": 1, "skill": 0.38,
		"aggr": 0.65, "jumpy": 0.45, "block": 0.12, "portrait": "crowd_3",
		"colors": {"body": [0.045, 1.25, 1.3], "neck": [0.06, 1.25, 1.2], "tail": [0.45, 1.35, 2.3],
			"comb": [0.0, 1.1, 1.1]}},
	"bay_ghe": {"owner": "Bảy Ghe", "name": "Mun Sông", "breed": 2, "lv": 3, "tier": 2, "skill": 0.6,
		"aggr": 0.45, "jumpy": 0.0, "block": 0.45, "portrait": "fisher",
		"colors": {"body": [0.62, 0.35, 0.62], "neck": [0.58, 0.55, 0.9], "tail": [0.0, 0.8, 0.85]}},
	"teo_2": {"owner": "Tèo", "name": "Tia Chớp", "breed": 1, "lv": 3, "tier": 3, "skill": 0.9,
		"aggr": 0.7, "jumpy": 0.2, "block": 0.30, "dao_chan": true, "cards": [&"mai_rua"], "portrait": "teo",
		"colors": {"body": [0.15, 1.05, 1.25], "neck": [0.05, 0.75, 1.15], "tail": [-0.22, 1.0, 1.5]}},
	# Dữ liệu cho đấu tự do sau này (chưa có trong cốt truyện).
	"sau_lua": {"owner": "Sáu Lúa", "name": "Hổ Phách", "breed": 2, "lv": 4, "tier": 2, "skill": 0.7,
		"aggr": 0.6, "jumpy": 0.0, "block": 0.35, "portrait": "crowd_1", "spar": true,
		"colors": {"body": [0.08, 0.9, 1.15], "neck": [0.04, 0.9, 1.1]}},
	"tu_bach": {"owner": "Tư Bạch", "name": "Bạch Vân", "breed": 0, "lv": 4, "tier": 3, "skill": 0.8,
		"aggr": 0.55, "jumpy": 0.25, "block": 0.35, "portrait": "crowd_5", "spar": true,
		"colors": {"body": [0.0, 0.12, 1.6], "neck": [0.0, 0.1, 1.25], "tail": [0.0, 0.15, 3.0]}},
}

# =================================================================== trạng thái

static var stage: int = Stage.PROLOGUE
static var player_name: String = "Tư Gà"
static var money: int = 200000
## Bộ thẻ của người chơi (dùng chung cho mọi con gà).
static var cards: Array[StringName] = []

## Đàn gà. Mỗi con: {id, name, breed, lv, xp, condition, fed_today, trained_today, wins, losses, title,
## mutations: Array[StringName], equip: {"head"|"armor"|"wing"|"spur"|"comb"|"weapon": item id hoặc &""},
## born_day, look: {hue, sat, colors}}. Không bao giờ rỗng (reset tạo sẵn Ô Mun).
static var chickens: Array[Dictionary] = []
static var active_index: int = 0
static var next_chicken_id: int = 1
static var coop_level: int = 1                       # 1..5
## Kho đồ: item id (StringName) → số lượng sở hữu (kể cả cái đang gắn cho gà).
static var inventory: Dictionary = {}
static var technology: int = 0
static var biotech: int = 0
static var kho_ga: float = 0.0                       # kg
## Lò ấp: {item, breed, days_left, biotech_spent, mutation_roll (StringName, &"" = không), look, started_day}.
static var eggs: Array[Dictionary] = []
## Lịch – nguồn sự thật duy nhất (Activities.day đọc/ghi qua đây).
static var day: int = 1
static var minutes: int = Calendar.DAY_START
## Act cốt truyện (1..4). current_act() còn suy ra từ stage / giải đã vô địch.
static var act: int = 1
## Tiến độ giải: tournament id (String) → {round, registered, champion, eliminated_week}.
static var tournament_progress: Dictionary = {}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Đường dẫn file lưu (test đổi sang file tạm để không đè save thật).
static var save_path: String = SAVE_PATH
## true sau khi tải save v1 (chưa có lịch): Activities.load_save() lấy "day" từ file thế giới cũ rồi tắt cờ.
static var legacy_day_pending: bool = false

# ---------------------------------------------------------------- tên cũ (tương thích ngược)

static var chicken_name: String:
	get:
		return String(active()["name"])
	set(value):
		active()["name"] = value
static var breed: int:
	get:
		return int(active()["breed"])
	set(value):
		active()["breed"] = value
static var level: int:
	get:
		return int(active()["lv"])
	set(value):
		active()["lv"] = value
static var xp: int:
	get:
		return int(active()["xp"])
	set(value):
		active()["xp"] = value
static var wins: int:
	get:
		return int(active()["wins"])
	set(value):
		active()["wins"] = value
static var owns_mao_sat: bool:
	get:
		return owned(&"mao_sat") > 0
	set(value):
		_set_owned(&"mao_sat", value)
static var owns_dao_chan: bool:
	get:
		return owned(&"dao_chan") > 0
	set(value):
		_set_owned(&"dao_chan", value)
## true = gà đang chọn gắn Mào sắt (ô Đầu). Gán true chỉ có tác dụng khi đã sở hữu.
static var equip_mao_sat: bool:
	get:
		return StringName(active()["equip"]["head"]) == &"mao_sat"
	set(value):
		_set_equipped(&"mao_sat", value)
static var equip_dao_chan: bool:
	get:
		return StringName(active()["equip"]["weapon"]) == &"dao_chan"
	set(value):
		_set_equipped(&"dao_chan", value)
## Cap level hiện tại (trước là hằng 5; giờ theo Act – xem level_cap()).
static var LEVEL_CAP: int:
	get:
		return level_cap()


static func _static_init() -> void:
	reset()


static func reset() -> void:
	stage = Stage.PROLOGUE
	player_name = "Tư Gà"
	money = 200000
	cards = []
	chickens = []
	active_index = 0
	next_chicken_id = 1
	coop_level = 1
	inventory = {}
	technology = 0
	biotech = 0
	kho_ga = 0.0
	eggs = []
	day = 1
	minutes = Calendar.DAY_START
	act = 1
	tournament_progress = {}
	legacy_day_pending = false
	rng.randomize()
	chickens.append(_new_chicken(Breeds.GA_NOI, "Ô Mun"))


static func result_text(code: int) -> String:
	return RESULT_TEXT[code] if code >= 0 and code < RESULT_TEXT.size() else "?"


# =================================================================== đàn gà

static func _empty_equip() -> Dictionary:
	var equip: Dictionary = {}
	for slot in Items.SLOTS:
		equip[String(slot)] = &""
	return equip


static func _new_chicken(p_breed: int, p_name: String, p_lv: int = 1, p_look: Dictionary = {}) -> Dictionary:
	var id: int = next_chicken_id
	next_chicken_id += 1
	var look: Dictionary = p_look.duplicate(true) if not p_look.is_empty() else {"hue": 0.0, "sat": 1.0, "colors": {}}
	var muts: Array[StringName] = []
	return {
		"id": id, "name": p_name, "breed": clampi(p_breed, 0, BREED_STATS.size() - 1), "lv": maxi(p_lv, 1), "xp": 0,
		"condition": CONDITION_MAX, "fed_today": false, "trained_today": 0, "wins": 0, "losses": 0, "title": 0,
		"mutations": muts, "equip": _empty_equip(), "born_day": day, "look": look,
	}


## Gà đang chọn đá (luôn có).
static func active() -> Dictionary:
	if chickens.is_empty():
		chickens.append(_new_chicken(Breeds.GA_NOI, "Ô Mun"))
	active_index = clampi(active_index, 0, chickens.size() - 1)
	return chickens[active_index]


static func active_id() -> int:
	return int(active()["id"])


static func index_of(id: int) -> int:
	for i in range(chickens.size()):
		if int(chickens[i]["id"]) == id:
			return i
	return -1


## Gà theo id ({} nếu không có). Trả về chính Dictionary trong đàn (sửa trực tiếp được).
static func chicken(id: int) -> Dictionary:
	var i: int = index_of(id)
	return chickens[i] if i >= 0 else {}


static func coop_capacity() -> int:
	return COOP_CAPACITY[clampi(coop_level, 1, COOP_CAPACITY.size()) - 1]


static func coop_full() -> bool:
	return chickens.size() >= coop_capacity()


## Giá nâng chuồng lên cấp kế; −1 nếu đã tối đa.
static func coop_upgrade_price() -> int:
	return COOP_UPGRADE_PRICE[coop_level - 1] if coop_level < COOP_CAPACITY.size() else -1


static func upgrade_coop() -> int:
	var price: int = coop_upgrade_price()
	if price < 0:
		return Result.MAX_LEVEL
	if money < price:
		return Result.NO_MONEY
	money -= price
	coop_level += 1
	return Result.OK


## Thêm gà vào chuồng; trả về id, hoặc −1 khi chuồng đầy. Tên rỗng → tên ngẫu nhiên.
static func add_chicken(p_breed: int, p_name: String = "", p_lv: int = 1, p_look: Dictionary = {}) -> int:
	if coop_full():
		return -1
	var c: Dictionary = _new_chicken(p_breed, p_name if p_name != "" else Breeds.random_name(rng), p_lv, p_look)
	chickens.append(c)
	return int(c["id"])


## Bỏ gà khỏi đàn (đồ đang gắn trở về kho). Không bao giờ bỏ con cuối cùng.
static func remove_chicken(id: int) -> int:
	var i: int = index_of(id)
	if i < 0:
		return Result.NO_CHICKEN
	if chickens.size() <= 1:
		return Result.LAST_CHICKEN
	chickens.remove_at(i)
	if i < active_index:
		active_index -= 1
	elif i == active_index:
		active_index = 0
	active_index = clampi(active_index, 0, chickens.size() - 1)
	return Result.OK


static func set_active(id: int) -> bool:
	var i: int = index_of(id)
	if i < 0:
		return false
	active_index = i
	return true


static func rename(id: int, p_name: String) -> bool:
	var c: Dictionary = chicken(id)
	if c.is_empty() or p_name.strip_edges() == "":
		return false
	c["name"] = p_name.strip_edges()
	return true


static func can_buy_chicken(p_breed: int) -> int:
	if not Breeds.is_valid(p_breed):
		return Result.UNKNOWN
	if current_act() < int(Breeds.info(p_breed)["unlock"]):
		return Result.LOCKED
	if coop_full():
		return Result.COOP_FULL
	if money < Breeds.price(p_breed):
		return Result.NO_MONEY
	return Result.OK


## Mua gà Lv1 ở chợ (GDD 7.2). Trả về id hoặc −1 (xem can_buy_chicken để biết lý do).
static func buy_chicken(p_breed: int, p_name: String = "") -> int:
	if can_buy_chicken(p_breed) != Result.OK:
		return -1
	money -= Breeds.price(p_breed)
	return add_chicken(p_breed, p_name)


## Công thức 6: Giá giống × (1 + 0,15 × (Lv − 1)) × (1 + min(0,5; 0,03 × số trận thắng)) × Hệ số danh hiệu
## × (1 + 0,1 × số mutation).
static func sell_price(c: Dictionary) -> int:
	var base: float = float(Breeds.price(int(c.get("breed", 0))))
	var title: int = clampi(int(c.get("title", 0)), 0, TITLE_SELL_MULT.size() - 1)
	var value: float = base * (1.0 + 0.15 * float(int(c.get("lv", 1)) - 1)) \
		* (1.0 + minf(0.5, 0.03 * float(int(c.get("wins", 0))))) * TITLE_SELL_MULT[title] \
		* (1.0 + 0.1 * float((c.get("mutations", []) as Array).size()))
	return int(round(value))


static func sell_chicken(id: int) -> int:
	var c: Dictionary = chicken(id)
	if c.is_empty():
		return Result.NO_CHICKEN
	if chickens.size() <= 1:
		return Result.LAST_CHICKEN
	var price: int = sell_price(c)
	var code: int = remove_chicken(id)
	if code == Result.OK:
		money += price
	return code


## WEIGHT thân gà (giống + đột biến, không tính đồ) – dùng cho Khô Gà.
static func body_weight(c: Dictionary) -> float:
	var w: float = float(BREED_STATS[clampi(int(c.get("breed", 0)), 0, BREED_STATS.size() - 1)]["weight"])
	for m in c.get("mutations", []):
		w += float((Mutations.info(m).get("mods", {}) as Dictionary).get("weight", 0.0))
	return maxf(w, 0.5)


## Công thức 7: Khô Gà (kg) = WEIGHT × 0,4 (làm tròn 0,01 kg).
static func kho_ga_yield(c: Dictionary) -> float:
	return snappedf(body_weight(c) * KHO_GA_PER_WEIGHT, 0.01)


## Chuyển gà thành Khô Gà (vĩnh viễn). Không cho phép với con gà cuối cùng.
static func convert_to_kho_ga(id: int) -> int:
	var c: Dictionary = chicken(id)
	if c.is_empty():
		return Result.NO_CHICKEN
	if chickens.size() <= 1:
		return Result.LAST_CHICKEN
	var kg: float = kho_ga_yield(c)
	var code: int = remove_chicken(id)
	if code == Result.OK:
		kho_ga = snappedf(kho_ga + kg, 0.01)
	return code


## Bán Khô Gà ở Tiệm Mèo (50.000đ/kg). kg < 0 = bán hết. Trả về số tiền nhận.
static func sell_kho_ga(kg: float = -1.0) -> int:
	var amount: float = kho_ga if kg < 0.0 else minf(kg, kho_ga)
	var gained: int = int(round(amount * float(Items.KHO_GA_PRICE_PER_KG)))
	kho_ga = snappedf(maxf(kho_ga - amount, 0.0), 0.01)
	money += gained
	return gained


# =================================================================== chỉ số

## Công thức 5: HP, ATK +3% chỉ số gốc mỗi cấp; SPD +1% (SPD di chuyển thật dùng preset MovementConfig).
static func scaled_stats(p_breed: int, p_level: int) -> Dictionary:
	var base: Dictionary = BREED_STATS[p_breed]
	var mult: float = 1.0 + 0.03 * float(p_level - 1)
	return {
		"hp": int(round(float(base["hp"]) * mult)),
		"atk": float(base["atk"]) * mult,
		"def": float(base["def"]),
		"spd": float(base["spd"]),
		"weight": float(base["weight"]),
		"crit": float(base["crit"]),
	}


## Chỉ số cuối = giống × cấp (công thức 5) + đồ (phẳng) → × (1 + Σ% đồ/đột biến) → Thể trạng < 50: ATK × 0,9.
## Trả về {hp: int, atk, def, spd, weight, crit, weak: bool}. Đã gồm +2 DEF của Mào sắt – code trận dùng
## stats này thì đừng cộng mao_sat lần nữa.
static func chicken_stats(c: Dictionary) -> Dictionary:
	return _compute_stats(int(c.get("breed", 0)), int(c.get("lv", 1)), _equip_ids(c.get("equip", {})),
		c.get("mutations", []), int(c.get("condition", CONDITION_MAX)))


static func _compute_stats(p_breed: int, p_lv: int, item_ids: Array, mutation_ids: Array, condition: int) -> Dictionary:
	var base: Dictionary = scaled_stats(clampi(p_breed, 0, BREED_STATS.size() - 1), maxi(p_lv, 1))
	var flat: Dictionary = {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "weight": 0.0, "crit": 0.0}
	var pct: Dictionary = {"hp_pct": 0.0, "atk_pct": 0.0, "spd_pct": 0.0}
	var sources: Array = []
	for id in item_ids:
		sources.append(Items.get_item(id).get("mods", {}))
	for m in mutation_ids:
		sources.append(Mutations.info(m).get("mods", {}))
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


static func _equip_ids(equip: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in Items.SLOTS:
		var id: StringName = StringName(equip.get(String(slot), &""))
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
static func layers_for(equip: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _equip_ids(equip):
		var item: Dictionary = Items.get_item(id)
		out.append({"slot": StringName(item.get("slot", &"")), "item": id, "layer": StringName(item.get("layer", id)),
			"order": Items.layer_order(id)})
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


## Bên đấu cho BattleDirector (siêu tập của player_side() cũ). Khóa: owner, name, breed, lv, dao_chan, mao_sat, cards,
## hue, sat, colors + id, weapon, equip, mutations, condition, title, stats (chỉ số cuối), flags, layers.
static func chicken_side(c: Dictionary) -> Dictionary:
	var equip: Dictionary = (c.get("equip", _empty_equip()) as Dictionary).duplicate()
	var ids: Array[StringName] = _equip_ids(equip)
	var muts: Array[StringName] = []
	for m in c.get("mutations", []):
		muts.append(StringName(m))
	var look: Dictionary = c.get("look", {})
	return {
		"owner": player_name, "name": String(c.get("name", "")), "breed": int(c.get("breed", 0)), "lv": int(c.get("lv", 1)),
		"dao_chan": StringName(equip.get("weapon", &"")) == &"dao_chan",
		"mao_sat": StringName(equip.get("head", &"")) == &"mao_sat",
		"cards": cards.duplicate(), "hue": float(look.get("hue", 0.0)), "sat": float(look.get("sat", 1.0)),
		"colors": _colors_with_mutations(look.get("colors", {}), muts),
		"id": int(c.get("id", 0)), "weapon": StringName(equip.get("weapon", &"")), "equip": equip, "mutations": muts,
		"condition": int(c.get("condition", CONDITION_MAX)), "title": int(c.get("title", 0)),
		"stats": chicken_stats(c), "flags": _flags_for(ids, muts), "layers": layers_for(equip),
	}


static func player_side() -> Dictionary:
	return chicken_side(active())


## Dữ liệu thô của đối thủ (GameState.OPPONENTS hoặc TournamentCatalog.OPPONENTS); {} nếu không có.
static func opponent_data(id: String) -> Dictionary:
	if OPPONENTS.has(id):
		return OPPONENTS[id]
	return Tournaments.OPPONENTS.get(id, {})


static func opponent_ids() -> Array[String]:
	var out: Array[String] = []
	for id in OPPONENTS.keys():
		out.append(String(id))
	for id in Tournaments.OPPONENTS.keys():
		out.append(String(id))
	return out


## Bên đấu của đối thủ (bản sao): dữ liệu gốc + equip/weapon/dao_chan/mao_sat suy ra, mutations, condition 100,
## stats, flags, layers, power. Truyền thẳng vào BattleDirector được.
static func opponent_side(id: String) -> Dictionary:
	var raw: Dictionary = opponent_data(id)
	if raw.is_empty():
		return {}
	var side: Dictionary = raw.duplicate(true)
	var equip: Dictionary = _empty_equip()
	var raw_equip: Dictionary = raw.get("equip", {})
	for slot in raw_equip:
		equip[String(slot)] = StringName(raw_equip[slot])
	if bool(raw.get("dao_chan", false)) and StringName(equip["weapon"]) == &"":
		equip["weapon"] = &"dao_chan"
	if bool(raw.get("mao_sat", false)) and StringName(equip["head"]) == &"":
		equip["head"] = &"mao_sat"
	var muts: Array[StringName] = []
	for m in raw.get("mutations", []):
		muts.append(StringName(m))
	var ids: Array[StringName] = _equip_ids(equip)
	side["id"] = id
	side["equip"] = equip
	side["weapon"] = StringName(equip["weapon"])
	side["dao_chan"] = StringName(equip["weapon"]) == &"dao_chan"
	side["mao_sat"] = StringName(equip["head"]) == &"mao_sat"
	side["mutations"] = muts
	side["condition"] = CONDITION_MAX
	side["colors"] = _colors_with_mutations(raw.get("colors", {}), muts)
	side["stats"] = _compute_stats(int(raw["breed"]), int(raw["lv"]), ids, muts, CONDITION_MAX)
	side["flags"] = _flags_for(ids, muts)
	side["layers"] = layers_for(equip)
	side["power"] = power_rating(side)
	return side


## Chỉ số của một bên đấu bất kỳ: side["stats"] nếu có, không thì tính từ breed/lv/equip/dao_chan/mao_sat/mutations.
static func side_stats(side: Dictionary) -> Dictionary:
	if side.has("stats"):
		return side["stats"]
	return _compute_stats(int(side.get("breed", 0)), int(side.get("lv", 1)), _side_item_ids(side),
		side.get("mutations", []), int(side.get("condition", CONDITION_MAX)))


static func _side_item_ids(side: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = _equip_ids(side.get("equip", {}))
	if bool(side.get("dao_chan", false)) and not ids.has(&"dao_chan"):
		ids.append(&"dao_chan")
	if bool(side.get("mao_sat", false)) and not ids.has(&"mao_sat"):
		ids.append(&"mao_sat")
	return ids


## Sức mạnh so sánh được giữa gà người chơi và đối thủ (PLACEHOLDER, chỉ để gợi ý/khóa lựa chọn, không dùng trong trận):
##   công = ATK × (1 + 0,5 × CRIT) × (SPD / 200)^0,25        bền = HP × (1 + 0,08 × DEF)
##   power = √(công × bền) × Π power(vũ khí/đồ/đột biến) × (1 + 0,04 × min(số thẻ, 5)) × TIER_POWER[tier]
##           × (1 + 0,1 × skill) × (1 + 0,03 × (Card Gauge đầu trận − 2))
## Nhận một bên đấu (có khóa "owner") hoặc một con gà trong đàn.
static func power_rating(side_or_chicken: Dictionary) -> float:
	var side: Dictionary = side_or_chicken if side_or_chicken.has("owner") else chicken_side(side_or_chicken)
	var s: Dictionary = side_stats(side)
	var offense: float = float(s["atk"]) * (1.0 + 0.5 * float(s["crit"])) * pow(float(s["spd"]) / 200.0, 0.25)
	var durability: float = float(s["hp"]) * (1.0 + 0.08 * float(s["def"]))
	var mult: float = 1.0
	for id in _side_item_ids(side):
		mult *= float(Items.get_item(id).get("power", 1.0))
	for m in side.get("mutations", []):
		mult *= float(Mutations.info(m).get("power", 1.0))
	mult *= 1.0 + 0.04 * float(mini((side.get("cards", []) as Array).size(), 5))
	mult *= TIER_POWER[clampi(int(side.get("tier", 0)), 0, TIER_POWER.size() - 1)]
	mult *= 1.0 + 0.1 * clampf(float(side.get("skill", 0.0)), 0.0, 1.0)
	mult *= 1.0 + 0.03 * float(int(side.get("start_card_gauge", 2)) - 2)
	return sqrt(offense * durability) * mult


## Tỷ lệ power(đối thủ) / power(gà đang chọn). Nhận id đối thủ (String) hoặc Dictionary bên đấu.
static func power_gap(opponent: Variant) -> float:
	var side: Dictionary = opponent_side(String(opponent)) if (opponent is String or opponent is StringName) else opponent
	if side.is_empty():
		return 0.0
	return power_rating(side) / maxf(power_rating(player_side()), 0.001)


## Hiện lựa chọn "Gọi tay trong" khi trận kế tiếp chênh lệch quá xa (power_gap ≥ INSIDE_MAN_GAP).
static func can_call_inside_man(opponent: Variant) -> bool:
	return power_gap(opponent) >= INSIDE_MAN_GAP


# =================================================================== EXP & Thể trạng

## Công thức 3.
static func exp_to_next(p_level: int) -> int:
	return int(round(50.0 * pow(float(p_level), 1.5)))


## Act hiện tại: max(act, suy ra từ stage và giải đã vô địch).
static func current_act() -> int:
	var a: int = act
	if stage >= Stage.CHAMPION:
		a = maxi(a, 2)
	return clampi(maxi(a, mini(best_title() + 1, 4)), 1, 4)


static func level_cap() -> int:
	return ACT_LEVEL_CAPS[clampi(current_act(), 1, ACT_LEVEL_CAPS.size()) - 1]


## Công thức 4 (Bảng 8.3 ghi rõ EXP thắng của trận hướng dẫn = 40). Tính theo gà đang chọn.
static func battle_exp(opponent: Dictionary, won: bool) -> int:
	return battle_exp_for(active(), opponent, won)


static func battle_exp_for(c: Dictionary, opponent: Dictionary, won: bool) -> int:
	var lv: int = int(opponent["lv"])
	var amount: int = (30 + 10 * lv) if won else (10 + 5 * lv)
	if won and opponent.has("exp_bonus"):
		amount = int(opponent["exp_bonus"])
	if int(c.get("lv", 1)) - lv >= 3:
		amount = int(amount * 0.5)
	return amount


## Cộng EXP cho gà đang chọn. Trả về số cấp vừa tăng.
static func add_exp(amount: int) -> int:
	return add_exp_to(active_id(), amount)


static func add_exp_to(id: int, amount: int) -> int:
	var c: Dictionary = chicken(id)
	if c.is_empty():
		return 0
	var cap: int = level_cap()
	c["xp"] = int(c["xp"]) + amount
	var gained: int = 0
	while int(c["lv"]) < cap and int(c["xp"]) >= exp_to_next(int(c["lv"])):
		c["xp"] = int(c["xp"]) - exp_to_next(int(c["lv"]))
		c["lv"] = int(c["lv"]) + 1
		gained += 1
	if int(c["lv"]) >= cap:
		c["xp"] = mini(int(c["xp"]), exp_to_next(int(c["lv"])))
	return gained


static func set_condition(id: int, value: int) -> void:
	var c: Dictionary = chicken(id)
	if not c.is_empty():
		c["condition"] = clampi(value, 0, CONDITION_MAX)


## Ghi kết quả một trận cho gà: thắng/thua; thua −15 Thể trạng (× condition_loss_mult của đột biến).
## (Code cũ trong main.gd tự cộng GameState.wins – nơi gọi hàm này thì đừng cộng thêm.)
static func record_match(id: int, won: bool) -> void:
	var c: Dictionary = chicken(id)
	if c.is_empty():
		return
	if won:
		c["wins"] = int(c["wins"]) + 1
		return
	c["losses"] = int(c["losses"]) + 1
	var mult: float = float(_flags_for([], c.get("mutations", [])).get("condition_loss_mult", 1.0))
	c["condition"] = clampi(int(c["condition"]) - int(round(CONDITION_LOSS_ON_DEFEAT * mult)), 0, CONDITION_MAX)


## Trao danh hiệu (giữ danh hiệu cao nhất).
static func award_title(id: int, title: int) -> void:
	var c: Dictionary = chicken(id)
	if not c.is_empty():
		c["title"] = maxi(int(c["title"]), clampi(title, 0, TITLE_NAMES.size() - 1))


## Cho gà ăn một món trong kho (food). Bữa chính (meal) mỗi ngày một lần: đêm đó Thể trạng về 100.
static func feed(id: int, item_id: StringName) -> int:
	var c: Dictionary = chicken(id)
	if c.is_empty():
		return Result.NO_CHICKEN
	var item: Dictionary = Items.get_item(item_id)
	if item.is_empty():
		return Result.UNKNOWN
	if StringName(item["kind"]) != &"food":
		return Result.WRONG_KIND
	if owned(item_id) <= 0:
		return Result.NOT_OWNED
	var effect: Dictionary = item.get("effect", {})
	var meal: bool = bool(effect.get("meal", false))
	if meal and bool(c["fed_today"]):
		return Result.ALREADY_FED
	_consume(item_id)
	if meal:
		c["fed_today"] = true
	if int(effect.get("condition", 0)) != 0:
		c["condition"] = clampi(int(c["condition"]) + int(effect["condition"]), 0, CONDITION_MAX)
	if int(effect.get("exp", 0)) > 0:
		add_exp_to(id, int(effect["exp"]))
	return Result.OK


## Luyện gà 1 giờ (PLACEHOLDER, xem TRAIN_*). Trả về {result, exp, levels}.
static func train(id: int) -> Dictionary:
	var c: Dictionary = chicken(id)
	if c.is_empty():
		return {"result": Result.NO_CHICKEN, "exp": 0, "levels": 0}
	if int(c["trained_today"]) >= TRAIN_PER_DAY or int(c["condition"]) < TRAIN_MIN_CONDITION:
		return {"result": Result.TOO_TIRED, "exp": 0, "levels": 0}
	if not spend_time(Calendar.cost_of(&"train")):
		return {"result": Result.NO_TIME, "exp": 0, "levels": 0}
	var amount: int = maxi(5, int(round(TRAIN_EXP_FRACTION * float(exp_to_next(int(c["lv"]))))))
	c["trained_today"] = int(c["trained_today"]) + 1
	c["condition"] = clampi(int(c["condition"]) - TRAIN_CONDITION_COST, 0, CONDITION_MAX)
	var levels: int = add_exp_to(id, amount)
	return {"result": Result.OK, "exp": amount, "levels": levels}


# =================================================================== kho đồ & cửa hàng

static func owned(item_id: StringName) -> int:
	return int(inventory.get(StringName(item_id), 0))


## Số món đang gắn trên các con gà.
static func equipped_count(item_id: StringName) -> int:
	var n: int = 0
	for c in chickens:
		for slot in Items.SLOTS:
			if StringName(c["equip"].get(String(slot), &"")) == item_id:
				n += 1
	return n


## Số món còn rảnh để gắn.
static func available(item_id: StringName) -> int:
	return owned(item_id) - equipped_count(item_id)


static func is_unlocked(item_id: StringName) -> bool:
	var item: Dictionary = Items.get_item(item_id)
	return not item.is_empty() and current_act() >= int(item.get("unlock", 1))


## Hàng bày bán ở một tiệm (grocery | market | cat), lọc theo mở khóa, xếp theo loại rồi giá.
static func shop_stock(shop: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Items.ids_in_shop(shop):
		if is_unlocked(id):
			out.append(id)
	var kind_rank: Dictionary = {&"food": 0, &"equipment": 1, &"egg": 2}
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ia: Dictionary = Items.get_item(a)
		var ib: Dictionary = Items.get_item(b)
		var ka: int = int(kind_rank.get(StringName(ia["kind"]), 9))
		var kb: int = int(kind_rank.get(StringName(ib["kind"]), 9))
		if ka != kb:
			return ka < kb
		var sa: int = Items.SLOTS.find(StringName(ia.get("slot", &"")))
		var sb: int = Items.SLOTS.find(StringName(ib.get("slot", &"")))
		if sa != sb:
			return sa < sb
		return float(ia["price"]) < float(ib["price"]))
	return out


## Mua qty món (tiền hoặc Khô Gà tùy currency của món). Món vào kho; trang bị phải equip() mới gắn.
static func buy(item_id: StringName, qty: int = 1) -> int:
	var item: Dictionary = Items.get_item(item_id)
	if item.is_empty() or qty <= 0:
		return Result.UNKNOWN
	if not is_unlocked(item_id):
		return Result.LOCKED
	if StringName(item.get("currency", &"money")) == &"kho_ga":
		var cost_kg: float = float(item["price"]) * float(qty)
		if kho_ga + 0.0001 < cost_kg:
			return Result.NO_KHO_GA
		kho_ga = snappedf(maxf(kho_ga - cost_kg, 0.0), 0.01)
	else:
		var cost: int = int(item["price"]) * qty
		if money < cost:
			return Result.NO_MONEY
		money -= cost
	inventory[StringName(item_id)] = owned(item_id) + qty
	return Result.OK


static func _consume(item_id: StringName, qty: int = 1) -> void:
	var left: int = owned(item_id) - qty
	if left > 0:
		inventory[StringName(item_id)] = left
	else:
		inventory.erase(StringName(item_id))


## Gắn trang bị (vào đúng ô của món; món cũ trong ô trở về kho).
static func equip(chicken_id: int, item_id: StringName) -> int:
	var c: Dictionary = chicken(chicken_id)
	if c.is_empty():
		return Result.NO_CHICKEN
	if not Items.has(item_id):
		return Result.UNKNOWN
	if not Items.is_equipment(item_id):
		return Result.WRONG_KIND
	if owned(item_id) <= 0:
		return Result.NOT_OWNED
	var slot: String = String(Items.slot_of(item_id))
	if StringName(c["equip"][slot]) == item_id:
		return Result.OK
	if available(item_id) <= 0:
		return Result.NOT_AVAILABLE
	c["equip"][slot] = StringName(item_id)
	return Result.OK


static func unequip(chicken_id: int, slot: StringName) -> int:
	var c: Dictionary = chicken(chicken_id)
	if c.is_empty():
		return Result.NO_CHICKEN
	if not (c["equip"] as Dictionary).has(String(slot)):
		return Result.WRONG_KIND
	c["equip"][String(slot)] = &""
	return Result.OK


static func _set_owned(item_id: StringName, value: bool) -> void:
	if value:
		if owned(item_id) <= 0:
			inventory[item_id] = 1
		return
	inventory.erase(item_id)
	for c in chickens:
		for slot in Items.SLOTS:
			if StringName(c["equip"].get(String(slot), &"")) == item_id:
				c["equip"][String(slot)] = &""


static func _set_equipped(item_id: StringName, value: bool) -> void:
	if value:
		equip(active_id(), item_id)
	elif StringName(active()["equip"][String(Items.slot_of(item_id))]) == item_id:
		unequip(active_id(), Items.slot_of(item_id))


# =================================================================== Technology, Biotech, đột biến, ấp trứng

static func add_technology(amount: int) -> void:
	technology = maxi(technology + amount, 0)


## Đổi Technology → Biotech (10 → 1).
static func convert_technology(biotech_amount: int = 1) -> int:
	if biotech_amount <= 0:
		return Result.UNKNOWN
	var need: int = biotech_amount * Mutations.TECH_PER_BIOTECH
	if technology < need:
		return Result.NO_TECHNOLOGY
	technology -= need
	biotech += biotech_amount
	return Result.OK


static func apply_mutation(chicken_id: int, mutation: StringName) -> int:
	var c: Dictionary = chicken(chicken_id)
	if c.is_empty():
		return Result.NO_CHICKEN
	if not Mutations.has(mutation):
		return Result.UNKNOWN
	if current_act() < Mutations.UNLOCK_ACT:
		return Result.LOCKED
	if (c["mutations"] as Array).has(mutation):
		return Result.ALREADY_HAS
	if biotech < Mutations.cost(mutation):
		return Result.NO_BIOTECH
	biotech -= Mutations.cost(mutation)
	(c["mutations"] as Array).append(StringName(mutation))
	return Result.OK


## Bỏ một quả trứng trong kho vào lò ấp, kèm biotech_spend Biotech (≥ biotech_min của trứng).
## Kết quả (giống, đột biến, màu lông) bốc thăm ngay bằng GameState.rng (seed được trong test) và lưu theo trứng.
## Tỷ lệ: MutationCatalog.hatch_mutation_chance / rare_breed_chance theo Biotech bỏ thêm.
static func start_incubation(item_id: StringName, biotech_spend: int) -> int:
	var item: Dictionary = Items.get_item(item_id)
	if item.is_empty():
		return Result.UNKNOWN
	if StringName(item["kind"]) != &"egg":
		return Result.WRONG_KIND
	if owned(item_id) <= 0:
		return Result.NOT_OWNED
	if eggs.size() >= INCUBATOR_SLOTS:
		return Result.INCUBATOR_FULL
	if biotech_spend < int(item["biotech_min"]) or biotech < biotech_spend:
		return Result.NO_BIOTECH
	var extra: int = biotech_spend - int(item["biotech_min"])
	var rare: bool = StringName(item.get("rarity", &"common")) == &"rare"
	var egg_breed: int = int(item["breed"])
	if egg_breed < 0:
		if rng.randf() < Mutations.rare_breed_chance(extra):
			egg_breed = Breeds.GA_DONG_TAO
		else:
			egg_breed = Breeds.GA_NOI if rng.randf() < 0.5 else Breeds.GA_TRE
	var roll: StringName = &""
	if rng.randf() < Mutations.hatch_mutation_chance(extra, rare):
		roll = Mutations.ORDER[rng.randi_range(0, Mutations.ORDER.size() - 1)]
	_consume(item_id)
	biotech -= biotech_spend
	eggs.append({"item": StringName(item_id), "breed": egg_breed, "days_left": int(item["incubate_days"]),
		"biotech_spent": biotech_spend, "mutation_roll": roll, "look": Breeds.random_look(rng), "started_day": day})
	return Result.OK


## Chỉ số các trứng đã đủ ngày (days_left == 0).
static func hatch_ready() -> Array[int]:
	var out: Array[int] = []
	for i in range(eggs.size()):
		if int(eggs[i]["days_left"]) <= 0:
			out.append(i)
	return out


## Nở trứng ở vị trí index thành gà Lv1 (kèm đột biến đã bốc). Trả về id gà, −1 nếu chưa đủ ngày / chuồng đầy.
static func hatch(index: int, p_name: String = "") -> int:
	if index < 0 or index >= eggs.size() or int(eggs[index]["days_left"]) > 0 or coop_full():
		return -1
	var egg: Dictionary = eggs[index]
	var id: int = add_chicken(int(egg["breed"]), p_name, 1, egg.get("look", {}))
	if id < 0:
		return -1
	if StringName(egg.get("mutation_roll", &"")) != &"":
		(chicken(id)["mutations"] as Array).append(StringName(egg["mutation_roll"]))
	eggs.remove_at(index)
	return id


# =================================================================== lịch & giờ (GDD 3.3, 3.6)

static func weekday() -> int:
	return Calendar.weekday(day)


static func weekday_name() -> String:
	return Calendar.weekday_name(day)


static func week() -> int:
	return Calendar.week(day)


static func is_school_day() -> bool:
	return Calendar.is_school_day(day)


static func is_weekend() -> bool:
	return Calendar.is_weekend(day)


static func period() -> int:
	return Calendar.period_of(minutes)


static func period_name() -> String:
	return Calendar.period_name_of(minutes)


static func clock_text() -> String:
	return Calendar.clock_text_of(minutes)


## Vd. "Thứ 2 · Ngày 1 · 07:00 (Sáng)".
static func date_text() -> String:
	return "%s · Ngày %d · %s (%s)" % [weekday_name(), day, clock_text(), period_name()]


static func light_color() -> Color:
	return Calendar.light_at(minutes)


static func minutes_left() -> int:
	return maxi(0, Calendar.DAY_END - minutes)


static func time_cost(activity: StringName) -> int:
	return Calendar.cost_of(activity)


static func can_spend(p_minutes: int) -> bool:
	return p_minutes >= 0 and minutes + p_minutes <= Calendar.DAY_END


## Trừ giờ. Vượt 23:00 bị từ chối, trừ khi allow_overflow (khi đó is_bedtime() → phải ngủ, mai dậy 08:00).
static func spend_time(p_minutes: int, allow_overflow: bool = false) -> bool:
	if p_minutes < 0 or (not can_spend(p_minutes) and not allow_overflow):
		return false
	minutes += p_minutes
	return true


static func is_bedtime() -> bool:
	return minutes >= Calendar.DAY_END


## Làm một hoạt động trong GameCalendar.ACTIVITIES: trừ giờ, cộng tiền (× hệ số minigame 0,5–1,3) và Technology.
## Trả về {result, minutes, money, technology}.
static func perform(activity: StringName, minigame_factor: float = 1.0) -> Dictionary:
	var info: Dictionary = Calendar.ACTIVITIES.get(activity, {})
	var out: Dictionary = {"result": Result.OK, "minutes": 0, "money": 0, "technology": 0}
	if info.is_empty():
		out["result"] = Result.UNKNOWN
		return out
	if bool(info.get("school_day_only", false)) and not is_school_day():
		out["result"] = Result.NOT_ALLOWED
		return out
	var cost: int = int(info["minutes"])
	if not spend_time(cost):
		out["result"] = Result.NO_TIME
		return out
	var factor: float = clampf(minigame_factor, Calendar.MINIGAME_FACTOR_MIN, Calendar.MINIGAME_FACTOR_MAX)
	var gained: int = int(round(float(info.get("money", 0)) * factor))
	money += gained
	add_technology(int(info.get("technology", 0)))
	out["minutes"] = cost
	out["money"] = gained
	out["technology"] = int(info.get("technology", 0))
	return out


## Ngủ: sang ngày mới 07:00 (quá 23:00 thì 08:00). Ban đêm, với mọi con gà (khi đã nhận gà – stage ≥ TUTORIAL):
## ăn bữa chính → Thể trạng 100; không thì +30 (ngủ, tối đa 100) rồi −20 (bỏ đói). Xóa fed_today/trained_today,
## lò ấp bớt 1 ngày. Không tự lưu (nơi gọi lưu). Trả về tóm tắt cho UI:
## {from_day, day, weekday, forced, wake, chickens: [{id, name, before, after, fed}], hatch_ready: [index]}.
static func sleep() -> Dictionary:
	var forced: bool = minutes > Calendar.DAY_END
	var summary: Dictionary = {"from_day": day, "forced": forced, "chickens": []}
	var has_chicken: bool = stage >= Stage.TUTORIAL
	for c in chickens:
		var before: int = int(c["condition"])
		var after: int = before
		if has_chicken:
			if bool(c["fed_today"]):
				after = CONDITION_MAX
			else:
				after = mini(before + CONDITION_SLEEP_RECOVERY, CONDITION_MAX) - CONDITION_UNFED_PENALTY
		c["condition"] = clampi(after, 0, CONDITION_MAX)
		(summary["chickens"] as Array).append({"id": int(c["id"]), "name": String(c["name"]), "before": before,
			"after": int(c["condition"]), "fed": bool(c["fed_today"])})
		c["fed_today"] = false
		c["trained_today"] = 0
	for egg in eggs:
		egg["days_left"] = maxi(int(egg["days_left"]) - 1, 0)
	day += 1
	minutes = Calendar.FORCED_WAKE if forced else Calendar.DAY_START
	summary["day"] = day
	summary["weekday"] = weekday_name()
	summary["wake"] = minutes
	summary["hatch_ready"] = hatch_ready()
	return summary


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


## Kiểm tra điều kiện đăng ký giải cho một con gà (mặc định gà đang chọn). check_day: kiểm cả ngày có giải.
## Trả về {ok: bool, reasons: PackedStringArray}.
static func can_enter(tid: StringName, c: Dictionary = {}, check_day: bool = false) -> Dictionary:
	var reasons: PackedStringArray = []
	var info: Dictionary = Tournaments.info(tid)
	if info.is_empty():
		return {"ok": false, "reasons": PackedStringArray(["Không có giải này."])}
	var who: Dictionary = c if not c.is_empty() else active()
	var entry: Dictionary = info["entry"]
	var progress: Dictionary = tournament_progress.get(String(tid), {})
	if is_champion(tid):
		reasons.append("Đã vô địch giải này rồi.")
	if best_title() < int(entry["min_title"]):
		reasons.append("Phải vô địch giải trước đã.")
	if int(who.get("lv", 1)) < int(entry["min_level"]):
		reasons.append("Gà phải đạt Lv%d." % int(entry["min_level"]))
	if (who.get("mutations", []) as Array).size() < int(entry["min_mutations"]):
		reasons.append("Gà phải qua ít nhất %d đột biến." % int(entry["min_mutations"]))
	if not bool(progress.get("registered", false)) and money < int(entry["fee"]):
		reasons.append("Không đủ lệ phí %s." % money_text(int(entry["fee"])))
	if int(progress.get("eliminated_week", 0)) == week():
		reasons.append("Bị loại tuần này rồi, tuần sau đăng ký lại.")
	if check_day and not is_tournament_day(tid):
		reasons.append("Hôm nay không có giải.")
	return {"ok": reasons.is_empty(), "reasons": reasons}


## Đăng ký giải bằng gà đang chọn (trừ lệ phí, vào vòng 1).
static func register_tournament(tid: StringName, check_day: bool = false) -> int:
	var progress: Dictionary = tournament_progress.get(String(tid), {})
	if bool(progress.get("registered", false)):
		return Result.OK
	if not bool(can_enter(tid, {}, check_day)["ok"]):
		return Result.NOT_ALLOWED
	money -= int(Tournaments.info(tid)["entry"]["fee"])
	var p: Dictionary = _progress(tid)
	p["registered"] = true
	p["round"] = 0
	return Result.OK


## Id đối thủ vòng hiện tại ("" nếu chưa đăng ký / đã xong).
static func current_round_opponent(tid: StringName) -> String:
	var progress: Dictionary = tournament_progress.get(String(tid), {})
	var rounds: Array = Tournaments.rounds(tid)
	var r: int = int(progress.get("round", 0))
	if not bool(progress.get("registered", false)) or r >= rounds.size():
		return ""
	return String(rounds[r])


## Cấu hình trận giải vòng hiện tại (dạng BattleDirector.setup + khóa mới):
## {player, opponent (có start_card_gauge), mode "tournament", tournament, round (0-based), rounds, title,
##  round_time, opponent_start_card_gauge, hell_mode, prize}. {} nếu chưa đăng ký.
static func match_config(tid: StringName) -> Dictionary:
	var opp_id: String = current_round_opponent(tid)
	if opp_id == "":
		return {}
	var info: Dictionary = Tournaments.info(tid)
	var r: int = int(_progress(tid)["round"])
	var n: int = Tournaments.round_count(tid)
	var opponent: Dictionary = opponent_side(opp_id)
	opponent["start_card_gauge"] = int(info["opponent_start_card_gauge"])
	opponent["power"] = power_rating(opponent)
	var round_title: String = "CHUNG KẾT" if r == n - 1 else "VÒNG %d/%d" % [r + 1, n]
	return {
		"player": player_side(), "opponent": opponent, "mode": "tournament", "tournament": String(tid),
		"round": r, "rounds": n, "title": "%s – %s" % [String(info["name"]).to_upper(), round_title],
		"round_time": float(info["round_time"]), "opponent_start_card_gauge": int(info["opponent_start_card_gauge"]),
		"hell_mode": bool(info["hell_mode"]),
		"prize": int(info["prize_money"]) if r == n - 1 else int(info["round_prize"]),
	}


## Ghi kết quả trận giải của gà đang chọn (gọi record_match bên trong). Thắng: tiền vòng, sang vòng kế; thắng chung
## kết: tiền + Biotech + danh hiệu, mở Act kế. Thua: bị loại, tuần sau đăng ký lại.
## Trả về {result, champion, eliminated, money, biotech, title}.
static func tournament_result(tid: StringName, won: bool) -> Dictionary:
	var out: Dictionary = {"result": Result.OK, "champion": false, "eliminated": false, "money": 0, "biotech": 0, "title": 0}
	var info: Dictionary = Tournaments.info(tid)
	var progress: Dictionary = tournament_progress.get(String(tid), {})
	if info.is_empty() or not bool(progress.get("registered", false)):
		out["result"] = Result.NOT_ALLOWED
		return out
	record_match(active_id(), won)
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
		award_title(active_id(), int(info["title"]))
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

## GDD 6.1 / Bảng 8.1: [MVP] ngủ ở nhà = lưu game. Bản 2 (meta/version = 2); vẫn ghi các khóa cũ ở [game] cho gà
## đang chọn để dễ đọc/khôi phục.
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
	# Khóa cũ (v1) – chỉ để tham khảo, load v2 không đọc.
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
	cfg.set_value("roster", "active_index", active_index)
	cfg.set_value("roster", "next_chicken_id", next_chicken_id)
	cfg.set_value("roster", "coop_level", coop_level)
	var inv: Dictionary = {}
	for id in inventory:
		inv[String(id)] = int(inventory[id])
	cfg.set_value("items", "inventory", inv)
	cfg.set_value("lab", "technology", technology)
	cfg.set_value("lab", "biotech", biotech)
	cfg.set_value("lab", "kho_ga", kho_ga)
	var egg_list: Array = []
	for egg in eggs:
		egg_list.append({"item": String(egg["item"]), "breed": int(egg["breed"]), "days_left": int(egg["days_left"]),
			"biotech_spent": int(egg["biotech_spent"]), "mutation_roll": String(egg["mutation_roll"]),
			"look": (egg.get("look", {}) as Dictionary).duplicate(true), "started_day": int(egg.get("started_day", 1))})
	cfg.set_value("lab", "eggs", egg_list)
	cfg.set_value("calendar", "day", day)
	cfg.set_value("calendar", "minutes", minutes)
	cfg.set_value("tournaments", "progress", tournament_progress.duplicate(true))
	cfg.save(save_path)


static func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Tải save; save cũ (v1, một con gà) được chuyển sang mô hình mới.
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
		return true
	act = int(cfg.get_value("game", "act", 1))
	chickens = []
	for d in cfg.get_value("roster", "chickens", []):
		chickens.append(_chicken_from_save(d))
	next_chicken_id = int(cfg.get_value("roster", "next_chicken_id", 1))
	for c in chickens:
		next_chicken_id = maxi(next_chicken_id, int(c["id"]) + 1)
	if chickens.is_empty():
		chickens.append(_new_chicken(Breeds.GA_NOI, "Ô Mun"))
	active_index = clampi(int(cfg.get_value("roster", "active_index", 0)), 0, chickens.size() - 1)
	coop_level = clampi(int(cfg.get_value("roster", "coop_level", 1)), 1, COOP_CAPACITY.size())
	inventory = {}
	var inv: Dictionary = cfg.get_value("items", "inventory", {})
	for id in inv:
		if int(inv[id]) > 0:
			inventory[StringName(id)] = int(inv[id])
	technology = int(cfg.get_value("lab", "technology", 0))
	biotech = int(cfg.get_value("lab", "biotech", 0))
	kho_ga = float(cfg.get_value("lab", "kho_ga", 0.0))
	eggs = []
	for e in cfg.get_value("lab", "eggs", []):
		eggs.append({"item": StringName(e.get("item", "")), "breed": int(e.get("breed", 0)),
			"days_left": int(e.get("days_left", 0)), "biotech_spent": int(e.get("biotech_spent", 0)),
			"mutation_roll": StringName(e.get("mutation_roll", "")), "look": (e.get("look", {}) as Dictionary).duplicate(true),
			"started_day": int(e.get("started_day", 1))})
	day = maxi(1, int(cfg.get_value("calendar", "day", 1)))
	minutes = int(cfg.get_value("calendar", "minutes", Calendar.DAY_START))
	tournament_progress = (cfg.get_value("tournaments", "progress", {}) as Dictionary).duplicate(true)
	return true


## Save v1: một con gà (chicken_name/breed/level/exp/wins) + cờ owns_*/equip_*. Ngày nằm ở file thế giới
## (Activities) → bật legacy_day_pending để Activities.load_save() lấy lại.
static func _migrate_v1(cfg: ConfigFile) -> void:
	var c: Dictionary = active()
	c["name"] = String(cfg.get_value("game", "chicken_name", "Ô Mun"))
	c["breed"] = clampi(int(cfg.get_value("game", "breed", 0)), 0, BREED_STATS.size() - 1)
	c["lv"] = maxi(1, int(cfg.get_value("game", "level", 1)))
	c["xp"] = int(cfg.get_value("game", "exp", 0))
	c["wins"] = int(cfg.get_value("game", "wins", 0))
	if stage >= Stage.CHAMPION:
		c["title"] = 1
	owns_mao_sat = bool(cfg.get_value("game", "owns_mao_sat", false))
	owns_dao_chan = bool(cfg.get_value("game", "owns_dao_chan", false))
	equip_mao_sat = bool(cfg.get_value("game", "equip_mao_sat", false))
	equip_dao_chan = bool(cfg.get_value("game", "equip_dao_chan", false))
	legacy_day_pending = true


static func _chicken_to_save(c: Dictionary) -> Dictionary:
	var muts: PackedStringArray = []
	for m in c["mutations"]:
		muts.append(String(m))
	var equip: Dictionary = {}
	for slot in Items.SLOTS:
		equip[String(slot)] = String(c["equip"].get(String(slot), &""))
	return {
		"id": int(c["id"]), "name": String(c["name"]), "breed": int(c["breed"]), "lv": int(c["lv"]), "xp": int(c["xp"]),
		"condition": int(c["condition"]), "fed_today": bool(c["fed_today"]), "trained_today": int(c["trained_today"]),
		"wins": int(c["wins"]), "losses": int(c["losses"]), "title": int(c["title"]), "mutations": muts, "equip": equip,
		"born_day": int(c["born_day"]), "look": (c.get("look", {}) as Dictionary).duplicate(true),
	}


static func _chicken_from_save(d: Dictionary) -> Dictionary:
	var muts: Array[StringName] = []
	for m in d.get("mutations", PackedStringArray()):
		if Mutations.has(StringName(m)):
			muts.append(StringName(m))
	var equip: Dictionary = _empty_equip()
	var saved_equip: Dictionary = d.get("equip", {})
	for slot in Items.SLOTS:
		var id: StringName = StringName(saved_equip.get(String(slot), ""))
		equip[String(slot)] = id if Items.has(id) else &""
	return {
		"id": int(d.get("id", 0)), "name": String(d.get("name", "Ô Mun")),
		"breed": clampi(int(d.get("breed", 0)), 0, BREED_STATS.size() - 1), "lv": maxi(1, int(d.get("lv", 1))),
		"xp": int(d.get("xp", 0)), "condition": clampi(int(d.get("condition", CONDITION_MAX)), 0, CONDITION_MAX),
		"fed_today": bool(d.get("fed_today", false)), "trained_today": int(d.get("trained_today", 0)),
		"wins": int(d.get("wins", 0)), "losses": int(d.get("losses", 0)), "title": int(d.get("title", 0)),
		"mutations": muts, "equip": equip, "born_day": int(d.get("born_day", 1)),
		"look": (d.get("look", {"hue": 0.0, "sat": 1.0, "colors": {}}) as Dictionary).duplicate(true),
	}
