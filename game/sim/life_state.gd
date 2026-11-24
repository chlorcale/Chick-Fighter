extends RefCounted

## Trạng thái riêng của tầng ĐỜI SỐNG / TRUYỆN (game/story/**) – không làm phình GameState:
## thân thiết hàng xóm, quest, nghề đã mở, lượt trong ngày (giao hữu, thư viện…), chuyên cần đi học + phản ứng của Mẹ,
## lịch giải (tạm hoãn), "Gọi tay trong" (hạn dùng, đối thủ bị phạt), mẹo hướng dẫn đã xem, mốc truyện (kết Act 1,
## giấc mơ ông nội, Olympic, kết game). Lưu file riêng user://chick_fighter_life.cfg có phiên bản.
## Dùng: const LifeState := preload("res://game/sim/life_state.gd")

const SAVE_PATH: String = "user://chick_fighter_life.cfg"
const VERSION: int = 1

## Quest: 0 chưa nhận · 1 đang làm · 2 xong.
const Q_NONE: int = 0
const Q_ACTIVE: int = 1
const Q_DONE: int = 2

static var save_path: String = SAVE_PATH

## npc id (String) → điểm thân thiết.
static var affinity: Dictionary = {}
## npc id → ngày gần nhất đã cộng thân thiết nhờ trò chuyện (mỗi ngày một lần).
static var chat_day: Dictionary = {}
## npc id → số lần đã trò chuyện (thoại nhiều lượt).
static var talks: Dictionary = {}
## Những thứ đã mở: "job_shop", "job_boat", "discount_co_ba", "discount_market", "tip_<npc>" …
static var unlocks: Array[String] = []
## qid → {"state": int, "day": int (ngày nhận), "mark": int (mốc đếm lúc nhận), "step": int}
static var quests: Dictionary = {}
## Lượt trong ngày: chỉ giữ cho ngày daily_day.
static var daily_day: int = 0
static var daily: Dictionary = {}
## Những ngày (GameState.day) đã đi học ở THPT.
static var attended: Array[int] = []
## Tuần (GameState.week()) gần nhất Mẹ đã xét chuyên cần.
static var mom_week: int = 0
## Tuần bị Mẹ cắt tiền tiêu vặt (0 = không).
static var allowance_blocked_week: int = 0
## Ngày phải rửa chén phạt (sáng hôm đó mất 1 giờ).
static var chores_day: int = 0
## Lịch giải: tid → {"postponed_until": ngày}.
static var league: Dictionary = {}
## Gọi tay trong: tuần đã dùng (0 = chưa), số lần, ngày bị bố ráp gần nhất, tổng tiền phạt.
static var police_week: int = 0
static var police_uses: int = 0
static var raid_day: int = 0
static var fines: int = 0
## Đối thủ có chủ bị phạt sau vụ bố ráp → id → số lần (mỗi lần yếu đi một chút).
static var weakened: Dictionary = {}
## Mẹo đã hiện (mỗi hệ thống một lần).
static var tutorials: Array[String] = []
## Mốc truyện.
static var finale_act1: bool = false
## Ngày mở Act 2 (sau cắt cảnh kết Act 1) – Mẹ chỉ xét chuyên cần từ ngày này.
static var finale_day: int = 0
static var dream_seen: bool = false
static var game_complete: bool = false
## Ngày gần nhất đã đọc "kế hoạch hôm nay".
static var plan_day: int = 0


static func reset() -> void:
	affinity = {}
	chat_day = {}
	talks = {}
	unlocks = []
	quests = {}
	daily_day = 0
	daily = {}
	attended = []
	mom_week = 0
	allowance_blocked_week = 0
	chores_day = 0
	league = {}
	police_week = 0
	police_uses = 0
	raid_day = 0
	fines = 0
	weakened = {}
	tutorials = []
	finale_act1 = false
	finale_day = 0
	dream_seen = false
	game_complete = false
	plan_day = 0


# =================================================================== lượt trong ngày

static func _sync_daily() -> void:
	if daily_day != GameState.day:
		daily_day = GameState.day
		daily = {}


static func today(key: String) -> int:
	_sync_daily()
	return int(daily.get(key, 0))


static func add_today(key: String, n: int = 1) -> int:
	_sync_daily()
	daily[key] = int(daily.get(key, 0)) + n
	return int(daily[key])


# =================================================================== thân thiết

static func aff(npc: String) -> int:
	return int(affinity.get(npc, 0))


static func add_aff(npc: String, n: int) -> int:
	affinity[npc] = aff(npc) + n
	return aff(npc)


## Trò chuyện: mỗi ngày một lần cộng 1 thân thiết. Trả về true nếu hôm nay vừa được cộng.
static func chat(npc: String) -> bool:
	talks[npc] = int(talks.get(npc, 0)) + 1
	if int(chat_day.get(npc, -1)) == GameState.day:
		return false
	chat_day[npc] = GameState.day
	add_aff(npc, 1)
	return true


static func talk_count(npc: String) -> int:
	return int(talks.get(npc, 0))


static func has(unlock: String) -> bool:
	return unlocks.has(unlock)


static func unlock(key: String) -> bool:
	if unlocks.has(key):
		return false
	unlocks.append(key)
	return true


# =================================================================== quest

static func quest_state(qid: String) -> int:
	return int((quests.get(qid, {}) as Dictionary).get("state", Q_NONE))


static func quest(qid: String) -> Dictionary:
	if not quests.has(qid):
		quests[qid] = {"state": Q_NONE, "day": 0, "mark": 0, "step": 0}
	return quests[qid]


static func start_quest(qid: String, mark: int = 0) -> void:
	var q: Dictionary = quest(qid)
	q["state"] = Q_ACTIVE
	q["day"] = GameState.day
	q["mark"] = mark
	q["step"] = 0


static func finish_quest(qid: String) -> void:
	quest(qid)["state"] = Q_DONE


static func active_quests() -> Array[String]:
	var out: Array[String] = []
	for qid in quests:
		if int(quests[qid].get("state", 0)) == Q_ACTIVE:
			out.append(String(qid))
	out.sort()
	return out


# =================================================================== mẹo

static func seen(id: String) -> bool:
	return tutorials.has(id)


static func mark_seen(id: String) -> bool:
	if tutorials.has(id):
		return false
	tutorials.append(id)
	return true


# =================================================================== giải & công an

static func postponed_until(tid: StringName) -> int:
	return int((league.get(String(tid), {}) as Dictionary).get("postponed_until", 0))


static func postpone(tid: StringName, until_day: int) -> void:
	var key: String = String(tid)
	if not league.has(key):
		league[key] = {}
	league[key]["postponed_until"] = until_day


static func police_ready() -> bool:
	return police_week != GameState.week()


# =================================================================== lưu / tải

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("social", "affinity", affinity.duplicate())
	cfg.set_value("social", "chat_day", chat_day.duplicate())
	cfg.set_value("social", "talks", talks.duplicate())
	cfg.set_value("social", "unlocks", PackedStringArray(unlocks))
	cfg.set_value("quests", "data", quests.duplicate(true))
	cfg.set_value("daily", "day", daily_day)
	cfg.set_value("daily", "counts", daily.duplicate())
	cfg.set_value("school", "attended", PackedInt32Array(attended))
	cfg.set_value("school", "mom_week", mom_week)
	cfg.set_value("school", "allowance_blocked_week", allowance_blocked_week)
	cfg.set_value("school", "chores_day", chores_day)
	cfg.set_value("league", "data", league.duplicate(true))
	cfg.set_value("police", "week", police_week)
	cfg.set_value("police", "uses", police_uses)
	cfg.set_value("police", "raid_day", raid_day)
	cfg.set_value("police", "fines", fines)
	cfg.set_value("police", "weakened", weakened.duplicate())
	cfg.set_value("story", "tutorials", PackedStringArray(tutorials))
	cfg.set_value("story", "finale_act1", finale_act1)
	cfg.set_value("story", "finale_day", finale_day)
	cfg.set_value("story", "dream_seen", dream_seen)
	cfg.set_value("story", "game_complete", game_complete)
	cfg.set_value("story", "plan_day", plan_day)
	cfg.save(save_path)


static func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Tải (thiếu file → trạng thái mới, trả false).
static func load_save() -> bool:
	reset()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return false
	affinity = (cfg.get_value("social", "affinity", {}) as Dictionary).duplicate()
	chat_day = (cfg.get_value("social", "chat_day", {}) as Dictionary).duplicate()
	talks = (cfg.get_value("social", "talks", {}) as Dictionary).duplicate()
	for u in cfg.get_value("social", "unlocks", PackedStringArray()):
		unlocks.append(String(u))
	quests = (cfg.get_value("quests", "data", {}) as Dictionary).duplicate(true)
	daily_day = int(cfg.get_value("daily", "day", 0))
	daily = (cfg.get_value("daily", "counts", {}) as Dictionary).duplicate()
	for d in cfg.get_value("school", "attended", PackedInt32Array()):
		attended.append(int(d))
	mom_week = int(cfg.get_value("school", "mom_week", 0))
	allowance_blocked_week = int(cfg.get_value("school", "allowance_blocked_week", 0))
	chores_day = int(cfg.get_value("school", "chores_day", 0))
	league = (cfg.get_value("league", "data", {}) as Dictionary).duplicate(true)
	police_week = int(cfg.get_value("police", "week", 0))
	police_uses = int(cfg.get_value("police", "uses", 0))
	raid_day = int(cfg.get_value("police", "raid_day", 0))
	fines = int(cfg.get_value("police", "fines", 0))
	weakened = (cfg.get_value("police", "weakened", {}) as Dictionary).duplicate()
	for t in cfg.get_value("story", "tutorials", PackedStringArray()):
		tutorials.append(String(t))
	finale_act1 = bool(cfg.get_value("story", "finale_act1", false))
	finale_day = int(cfg.get_value("story", "finale_day", 0))
	dream_seen = bool(cfg.get_value("story", "dream_seen", false))
	game_complete = bool(cfg.get_value("story", "game_complete", false))
	plan_day = int(cfg.get_value("story", "plan_day", 0))
	return true
