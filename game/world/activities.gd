extends RefCounted

## Trạng thái hoạt động ở bờ nam (cá tra, gặt lúa, hỏi bài, bốc gạch, đền làng, vé số).
## Mỗi hoạt động có thưởng chỉ làm được 1 lần mỗi "ngày"; ngày mới bắt đầu khi ngủ ở nhà.
## Lưu riêng ở user://chick_fighter_world.cfg (không đụng file save của GameState).
## Lịch: GameState.day là nguồn sự thật duy nhất – Activities.day chỉ đọc/ghi qua đó; done_today tự xóa khi
## ngày của GameState đổi (kể cả khi nơi khác gọi thẳng GameState.sleep()).
## Dùng qua: const Activities := preload("res://game/world/activities.gd")

const SAVE_PATH: String = "user://chick_fighter_world.cfg"

## Bảng thưởng (giữ nhỏ so với giá đồ 150–200k và tiền giải 50k/50k/300k).
const FISH_PRICE: int = 8000            # Chú Sáu mua mỗi con cá tra (tối đa 3 con/ngày)
const RICE_MONEY_PER_BUNDLE: int = 2000 # công gặt mỗi bó (8 bó/ngày)
const RICE_EXP_PER_BUNDLE: int = 2      # "lúa" cho gà, chỉ khi đã có gà
const QUIZ_MONEY_PER_RIGHT: int = 5000  # cô giáo thưởng mỗi câu đúng (3 câu/ngày)
const QUIZ_EXP_PER_RIGHT: int = 5
const BRICK_TARGET: int = 8             # đủ ca = 8 cữ gạch
const BRICK_FULL_PAY: int = 80000       # "một ca tám chục ngàn"
const BRICK_PARTIAL_PAY: int = 5000     # mỗi cữ nếu không đủ ca
const TEMPLE_FIRST_GIFT: int = 10000    # lộc đền lần đầu
const LOTTERY_PRICE: int = 10000
const LOTTERY_PRIZE: int = 50000        # giải khuyến khích (8%)
const LOTTERY_CONSOLATION: int = 10000  # trúng an ủi = hoàn tiền vé (20%)
const LOTTERY_PRIZE_ODDS: float = 0.08
const LOTTERY_CONSOLATION_ODDS: float = 0.20
const RACE_PRIZE: int = 30000           # đua xe bí mật: thắng lần đầu trong ngày, đối thủ "bao cà phê"
const RACE_TITLE: String = "Thần Gió Đường Làng" # danh hiệu bí mật khi thắng lần đầu tiên

## Các hoạt động có giới hạn mỗi ngày.
const DAILY: Array[StringName] = [&"fish", &"farm", &"school", &"site", &"temple", &"lottery"]

static var day: int:                         # = GameState.day
	get:
		return GameState.day
	set(value):
		GameState.day = value
static var done_today: Dictionary = {}       # id → true (của ngày _done_day)
static var _done_day: int = 1
static var temple_gift_taken: bool = false
static var lottery_ticket: String = ""       # số vé đang giữ, "" = không có
static var lottery_day: int = 0              # ngày mua vé
static var total_fish: int = 0
static var total_bundles: int = 0
static var total_bricks: int = 0
static var race_wins: int = 0                # tổng số lần thắng đua xe
static var race_count: int = 0               # tổng số lần đua (đua hết, không tính bỏ cuộc)
static var race_title: bool = false          # đã mở danh hiệu bí mật
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Đường dẫn file lưu (test đổi sang file tạm để không đè save thật).
static var save_path: String = SAVE_PATH


## Không đặt lại ngày (lịch thuộc GameState.reset()).
static func reset() -> void:
	done_today = {}
	_done_day = day
	temple_gift_taken = false
	lottery_ticket = ""
	lottery_day = 0
	total_fish = 0
	total_bundles = 0
	total_bricks = 0
	race_wins = 0
	race_count = 0
	race_title = false
	rng.randomize()


## Ngủ ở nhà = sang ngày mới (GameState.sleep(): Thể trạng gà, lò ấp, 07:00): mọi hoạt động có thưởng mở lại.
## Trả về tóm tắt của GameState.sleep().
static func new_day() -> Dictionary:
	var summary: Dictionary = GameState.sleep()
	_sync_day()
	return summary


## Ngày đã đổi (ngủ) → xóa lượt đã làm của ngày cũ.
static func _sync_day() -> void:
	if _done_day != day:
		done_today = {}
		_done_day = day


static func is_done(id: StringName) -> bool:
	_sync_day()
	return done_today.has(String(id))


## Còn lượt hôm nay (dùng cho dấu "!" trên bản đồ). Vé số: còn vé chờ dò cũng tính là có việc.
static func is_available(id: StringName) -> bool:
	if id == &"lottery" and lottery_result_ready():
		return true
	return not is_done(id)


static func mark_done(id: StringName) -> void:
	_sync_day()
	done_today[String(id)] = true


## Cộng tiền (luôn) và EXP (chỉ khi đã có gà: stage ≥ TUTORIAL). Trả về {money, exp, levels}.
static func grant(money: int, exp_amount: int) -> Dictionary:
	GameState.money += money
	var given_exp: int = 0
	var levels: int = 0
	if exp_amount > 0 and has_chicken():
		given_exp = exp_amount
		levels = GameState.add_exp(exp_amount)
	return {"money": money, "exp": given_exp, "levels": levels}


static func has_chicken() -> bool:
	return GameState.stage >= GameState.Stage.TUTORIAL


## Câu tóm tắt phần thưởng cho hộp thoại, vd. "+16.000đ · Ô Mun +16 EXP".
static func reward_text(reward: Dictionary) -> String:
	var parts: PackedStringArray = []
	if int(reward.get("money", 0)) > 0:
		parts.append("+" + GameState.money_text(int(reward["money"])))
	if int(reward.get("exp", 0)) > 0:
		parts.append("%s +%d EXP" % [GameState.chicken_name, int(reward["exp"])])
	if int(reward.get("levels", 0)) > 0:
		parts.append("%s lên cấp %d!" % [GameState.chicken_name, GameState.level])
	return " · ".join(parts)


# ------------------------------------------------------------------ vé số

static func buy_lottery_ticket() -> String:
	lottery_ticket = "%06d" % rng.randi_range(0, 999999)
	lottery_day = day
	mark_done(&"lottery")
	return lottery_ticket


## Vé mua từ hôm trước trở về trước thì đã xổ, dò được.
static func lottery_result_ready() -> bool:
	return lottery_ticket != "" and day > lottery_day


## Dò vé: trả về số tiền trúng (0 = trật) và xoá vé.
static func draw_lottery() -> int:
	var roll: float = rng.randf()
	lottery_ticket = ""
	if roll < LOTTERY_PRIZE_ODDS:
		return LOTTERY_PRIZE
	if roll < LOTTERY_PRIZE_ODDS + LOTTERY_CONSOLATION_ODDS:
		return LOTTERY_CONSOLATION
	return 0


# ------------------------------------------------------------------ đua xe bí mật

## Ghi kết quả một cuộc đua đã chạy hết. Thắng lần đầu trong ngày được RACE_PRIZE (khóa "race" trong
## done_today); thắng lần đầu tiên mở danh hiệu RACE_TITLE. Trả về {reward, first_today, title_new, wins}.
static func record_race(won: bool) -> Dictionary:
	race_count += 1
	var out: Dictionary = {"reward": {}, "first_today": false, "title_new": false, "wins": race_wins}
	if not won:
		return out
	race_wins += 1
	out["wins"] = race_wins
	if not race_title:
		race_title = true
		out["title_new"] = true
	if not is_done(&"race"):
		mark_done(&"race")
		out["first_today"] = true
		out["reward"] = grant(RACE_PRIZE, 0)
	return out


# ------------------------------------------------------------------ lưu / tải

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("world", "day", day)
	var done: PackedStringArray = []
	for key in done_today.keys():
		done.append(String(key))
	cfg.set_value("world", "done_today", done)
	cfg.set_value("world", "temple_gift_taken", temple_gift_taken)
	cfg.set_value("world", "lottery_ticket", lottery_ticket)
	cfg.set_value("world", "lottery_day", lottery_day)
	cfg.set_value("world", "total_fish", total_fish)
	cfg.set_value("world", "total_bundles", total_bundles)
	cfg.set_value("world", "total_bricks", total_bricks)
	cfg.set_value("world", "race_wins", race_wins)
	cfg.set_value("world", "race_count", race_count)
	cfg.set_value("world", "race_title", race_title)
	cfg.save(save_path)


static func load_save() -> bool:
	reset()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return false
	# Ngày nằm ở save GameState v2; chỉ save GameState v1 (chưa có lịch) mới lấy ngày từ đây.
	if GameState.legacy_day_pending:
		GameState.day = maxi(1, int(cfg.get_value("world", "day", 1)))
		GameState.legacy_day_pending = false
	_done_day = day
	for key in cfg.get_value("world", "done_today", PackedStringArray()):
		done_today[String(key)] = true
	temple_gift_taken = bool(cfg.get_value("world", "temple_gift_taken", false))
	lottery_ticket = String(cfg.get_value("world", "lottery_ticket", ""))
	lottery_day = int(cfg.get_value("world", "lottery_day", 0))
	total_fish = int(cfg.get_value("world", "total_fish", 0))
	total_bundles = int(cfg.get_value("world", "total_bundles", 0))
	total_bricks = int(cfg.get_value("world", "total_bricks", 0))
	race_wins = int(cfg.get_value("world", "race_wins", 0))
	race_count = int(cfg.get_value("world", "race_count", 0))
	race_title = bool(cfg.get_value("world", "race_title", false))
	return true
