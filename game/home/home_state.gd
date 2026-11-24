extends RefCounted

## Trạng thái riêng của NHÀ (ngoài GameState – nền dữ liệu không có các khóa này): chăm gà kiểu thú cưng mỗi ngày
## (vuốt ve / tắm / phơi nắng, mỗi việc một lần/ngày/con), độ thân thiết (bond 0..10) theo id gà, và ngày thắp nhang
## bàn thờ. Lưu file riêng user://chick_fighter_home.cfg (test đổi save_path).
## PLACEHOLDER: mọi con số hiệu ứng chăm sóc (nhỏ, chỉ cho vui – không phá cân bằng Thể trạng GDD 6.1).
## Dùng: const HomeState := preload("res://game/home/home_state.gd")

const SAVE_PATH: String = "user://chick_fighter_home.cfg"
const BOND_MAX: int = 10
## kind → {name, condition (cộng Thể trạng), bond, day_only (chỉ làm được buổi Sáng/Trưa/Chiều), lines}.
const CARE: Dictionary = {
	&"pet": {"name": "Vuốt ve", "condition": 3.0, "bond": 1, "day_only": false,
		"done": "%s rúc đầu vô tay, kêu cục cục khoái chí."},
	&"bath": {"name": "Tắm", "condition": 5.0, "bond": 1, "day_only": false,
		"done": "Múc gáo nước lu tắm cho %s. Nó rũ lông văng nước tùm lum, sạch bong!"},
	&"sun": {"name": "Phơi nắng", "condition": 4.0, "bond": 1, "day_only": true,
		"done": "%s nằm xòe cánh phơi nắng, lông óng mượt hẳn lên."},
}
const CARE_ORDER: Array[StringName] = [&"pet", &"bath", &"sun"]

static var save_path: String = SAVE_PATH
## "id gà" (String) → {"bond": int, "pet": ngày, "bath": ngày, "sun": ngày}; "_altar" → ngày thắp nhang.
static var _data: Dictionary = {}
static var _loaded: bool = false


static func reset() -> void:
	_data = {}
	_loaded = true


static func _ensure() -> void:
	if not _loaded:
		load_state()


static func load_state() -> void:
	_data = {}
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	var raw: Variant = cfg.get_value("home", "data", {})
	if raw is Dictionary:
		_data = (raw as Dictionary).duplicate(true)


static func save_state() -> void:
	_ensure()
	var cfg := ConfigFile.new()
	cfg.set_value("home", "data", _data)
	cfg.save(save_path)


static func _entry(id: int) -> Dictionary:
	_ensure()
	var key: String = str(id)
	if not _data.has(key):
		_data[key] = {"bond": 0}
	return _data[key]


static func bond(id: int) -> int:
	return int(_entry(id).get("bond", 0))


## "♥♥♥♡♡" (5 tim, mỗi tim = 2 điểm thân thiết, làm tròn lên).
static func bond_hearts(id: int) -> String:
	var full: int = (bond(id) + 1) / 2
	var out: String = ""
	for i in range(5):
		out += "♥" if i < full else "♡"
	return out


static func care_done(id: int, kind: StringName) -> bool:
	return int(_entry(id).get(String(kind), -1)) == GameState.day


## Lý do không làm được (rỗng = làm được).
static func care_block_reason(index: int, kind: StringName) -> String:
	if index < 0 or index >= GameState.chickens.size() or not CARE.has(kind):
		return "Hổng có con gà này."
	var c: Dictionary = GameState.chickens[index]
	if care_done(int(c["id"]), kind):
		return "Hôm nay %s rồi, mai làm tiếp nghen." % String(CARE[kind]["name"]).to_lower()
	if bool(CARE[kind]["day_only"]) and GameState.period() > GameState.Period.CHIEU:
		return "Trời tối rồi, nắng đâu mà phơi. Mai phơi nghen."
	return ""


## Chăm gà ở chỉ số index. Trả về {ok, text, condition, bond}.
static func do_care(index: int, kind: StringName) -> Dictionary:
	var reason: String = care_block_reason(index, kind)
	if reason != "":
		return {"ok": false, "text": reason, "condition": 0.0, "bond": 0}
	var c: Dictionary = GameState.chickens[index]
	var info: Dictionary = CARE[kind]
	var e: Dictionary = _entry(int(c["id"]))
	e[String(kind)] = GameState.day
	var before: float = float(c["condition"])
	GameState.set_condition(index, before + float(info["condition"]))
	var gained_bond: int = mini(int(info["bond"]), BOND_MAX - int(e.get("bond", 0)))
	e["bond"] = int(e.get("bond", 0)) + gained_bond
	save_state()
	return {"ok": true, "text": String(info["done"]) % String(c["name"]),
		"condition": float(c["condition"]) - before, "bond": gained_bond}


static func altar_lit_today() -> bool:
	_ensure()
	return int(_data.get("_altar", -1)) == GameState.day


static func light_altar() -> void:
	_ensure()
	_data["_altar"] = GameState.day
	save_state()
