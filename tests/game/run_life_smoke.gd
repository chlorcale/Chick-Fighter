extends SceneTree

## Smoke test TẦNG ĐỜI SỐNG / TRUYỆN (game/story/**, game/sim/life_state.gd) trên main.tscn thật:
## Act 1 → cắt cảnh kết Act 1 → Act 2 tự do (không về màn tiêu đề); một ngày học THPT (Technology, giờ, Chủ nhật đóng);
## ba nghề (bốc gạch, bán cơm, chở ghe – autopilot, tiền trong khoảng hệ số, mỗi ngày một ca); mọi tiệm (mua, thiếu tiền,
## số đang có); Lão Gà Khô (bán Khô Gà, mua đồ độc quyền); trò chuyện → thân thiết → mở khóa; quest nhận → xong;
## Liên tỉnh (từ chối, đăng ký, thắng lên vòng, thua bị loại, vô địch → danh hiệu + mở Olympic); Olympic (từ chối khi
## thiếu 3 đột biến, cấu hình Hell Mode tới BattleDirector); giới hạn giao hữu; gọi tay trong (sống sót → tẩu thoát →
## cắt cảnh → hậu quả; bị hạ → thua; bị bắt → thua + phạt; hạn mỗi tuần; mini-game tẩu thoát thật chạy autopilot);
## ép đi ngủ sau 23:00; Mẹ phát tiền tiêu vặt đầu tuần; lưu → tiếp tục khôi phục hết.
## Trận đấu được "kết thúc giả" bằng cách phát BattleDirector.finished với kết quả dựng sẵn (luồng main thật).
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_life_smoke.gd

const Activities := preload("res://game/world/activities.gd")
const HomeState := preload("res://game/home/home_state.gd")
const LifeState := preload("res://game/sim/life_state.gd")
const StoryLeagues := preload("res://game/story/story_leagues.gd")
const Items := preload("res://game/data/items.gd")
const ESCAPE_CUTSCENE := "res://game/escape/escape_cutscene.gd"
const ESCAPE_GAME := "res://game/escape/escape_game.gd"

var _main: Node
var _failures: int = 0
var _frame: int = 0
## Lựa chọn theo chuỗi con (lần lượt); hết thì chọn lựa chọn cuối (thường là "Thôi").
var _answers: Array = []
## Hành động ở màn chuẩn bị: "start" | "police" | "back" (lần lượt; hết thì "start").
var _pre_actions: Array = []
## Kết quả trận dựng sẵn (lần lượt; hết thì thắng).
var _results: Array = []
var _drive: bool = true
var _missed_answers: Array[String] = []
var _director_modes: Array[String] = []
var _pre_count: int = 0
## Người nói đã gặp trong hội thoại → đường dẫn ảnh chân dung đang hiện ("" = không có).
var _speakers: Dictionary = {}


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	GameState.save_path = "user://test_life_game.cfg"
	Activities.save_path = "user://test_life_world.cfg"
	HomeState.save_path = "user://test_life_home.cfg"
	LifeState.save_path = "user://test_life_life.cfg"
	for p in [GameState.save_path, Activities.save_path, HomeState.save_path, LifeState.save_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_flow.call_deferred()


# =================================================================== bộ lái giao diện

func _process(_delta: float) -> bool:
	_frame += 1
	if not _drive or _main == null or not is_instance_valid(_main) or _frame % 3 != 0:
		return false
	var dialog: DialogBox = _main.get("dialog")
	for child in _main.get_children():
		if child is TitleScreen:
			(child as TitleScreen)._picked.emit(_title_choice)
			return false
		if child is Cutscene:
			(child as Cutscene)._next.emit()
			return false
		if child is PreBattle:
			_pre_count += 1
			var action: String = String(_pre_actions.pop_front()) if not _pre_actions.is_empty() else "start"
			if action == "police":
				(child as PreBattle).police_called = true
			(child as PreBattle)._done.emit(action != "back")
			return false
		if child is BattleDirector:
			# Chỉ kết thúc khi đã vào đánh (main đang await finished sau màn mờ dần).
			if (child as BattleDirector).phase == BattleDirector.Phase.FIGHT and not bool(child.get_meta("stubbed", false)):
				child.set_meta("stubbed", true)
				_director_modes.append(String((child as BattleDirector).mode))
				var r: Dictionary = _results.pop_front() if not _results.is_empty() else {"won": true}
				var full: Dictionary = {"won": false, "player_hp_ratio": 0.6, "raid": false, "survived": false, "mode": "normal"}
				full.merge(r, true)
				(child as BattleDirector).finished.emit.call_deferred(full)
			return false
		if child is ResultScreen:
			(child as ResultScreen)._remaining = 0.0
			(child as ResultScreen)._closed.emit()
			return false
		var s: Script = child.get_script()
		if s != null and s.resource_path == ESCAPE_CUTSCENE:
			child.call("press", &"skip")
			return false
	if dialog == null:
		return false
	if dialog._mode != 0:
		var tex: Texture2D = dialog._portrait.texture if dialog._portrait_box.visible else null
		_speakers[dialog._speaker.text] = tex.resource_path if tex != null else ""
	if dialog._mode == 1:
		dialog._text.visible_ratio = 1.0
		dialog._advanced.emit()
	elif dialog._mode == 3:
		dialog._named.emit("")
	elif dialog._mode == 2:
		dialog._chosen.emit(_pick(dialog))
	return false


var _title_choice: String = "new"


func _pick(dialog: DialogBox) -> int:
	var runner: Node = _main.get("activities")
	if runner != null and runner.get("current_quiz") != null:
		return int(runner.get("current_quiz").get("current_answer"))
	var options: Array = dialog._options
	if not _answers.is_empty():
		var want: String = String(_answers[0])
		for i in range(options.size()):
			if String(options[i]).contains(want):
				_answers.pop_front()
				return i
		_missed_answers.append("%s (có: %s)" % [want, " | ".join(PackedStringArray(options))])
		_answers.pop_front()
	return options.size() - 1


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _until(cond: Callable, max_frames: int = 3000) -> bool:
	for i in range(max_frames):
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _idle() -> bool:
	if _main == null or _main.get("world") == null or bool(_main.get("_busy")):
		return false
	if (_main.get("dialog") as DialogBox).is_open():
		return false
	for child in _main.get_children():
		if child is PreBattle or child is BattleDirector or child is ResultScreen or child is Cutscene or child is TitleScreen:
			return false
		var s: Script = child.get_script()
		if s != null and (s.resource_path == ESCAPE_CUTSCENE or s.resource_path == ESCAPE_GAME):
			return false
	return true


## Tương tác như bấm E trước điểm id, rồi chờ xong hết hội thoại/trận.
func _do(id: StringName, answers: Array = [], max_frames: int = 6000) -> bool:
	_answers = answers.duplicate()
	_missed_answers.clear()
	await _until(_idle, 600)
	_main.call("_on_interact", id)
	await _frames(2)
	var ok: bool = await _until(_idle, max_frames)
	if not _missed_answers.is_empty():
		print("      note: unmatched answers %s" % str(_missed_answers))
	if not ok:
		print("      timeout at %s (busy %s, dialog %d)" % [id, str(_main.get("_busy")), (_main.get("dialog") as DialogBox)._mode])
	return ok


## Đặt ngày là thứ wd (0 = T2) kế tiếp (hoặc hôm nay) lúc minute.
func _goto(wd: int, minute: int, next_week: bool = false) -> void:
	var d: int = GameState.day
	while GameCalendar.weekday(d) != wd or (next_week and d == GameState.day):
		d += 1
	GameState.set_time(d, minute)


# =================================================================== kịch bản

func _flow() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	var reached: bool = await _until(func() -> bool: return GameState.stage == GameState.Stage.GO_CHU_TU and _idle(), 3000)
	_check(reached, "new game reaches the village (Act 1)")
	await _test_act1_finale()
	await _test_school()
	await _test_jobs()
	await _test_shops()
	await _test_cat_shop()
	await _test_social_and_quest()
	await _test_lien_tinh()
	await _test_olympic_and_spar()
	await _test_police()
	await _test_bedtime()
	await _test_allowance_save_continue()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _test_act1_finale() -> void:
	_check(StoryLeagues.police_refusal({"police_ok": false}) != "", "police call refused in Act 1 story matches")
	GameState.stage = GameState.Stage.CHAMPION
	GameState.chickens[0]["level"] = 5
	var day0: int = GameState.day
	var ok: bool = await _do(&"home", [], 4000)
	var world: Node = _main.get("world")
	var has_title: bool = false
	for child in _main.get_children():
		has_title = has_title or child is TitleScreen
	_check(ok and not has_title and world != null and bool(world.get("visible")), "Act 1 finale keeps playing (no title screen, world visible)")
	_check(GameState.stage == GameState.Stage.ACT_END and LifeState.finale_act1 and GameState.current_act() >= 2,
		"finale opens Act 2 (stage %d, act %d)" % [GameState.stage, GameState.current_act()])
	_check(GameState.day == day0 + 1 and GameState.clock_running(), "finale passes the night (day %d) and the day clock runs" % GameState.day)
	_check(LifeState.seen("clock") and LifeState.seen("map"), "clock + map tutorials shown at the start of Act 2")
	_check(String(world.get("objective_text")) != "" and StringName(world.get("marker_target")) != &"",
		"free-roam objective + arrow: «%s» → %s" % [world.get("objective_text"), world.get("marker_target")])


func _test_school() -> void:
	_goto(0, 7 * 60 + 30, true)
	_main.call("_refresh_status")
	_check(StringName(_main.get("world").get("marker_target")) == &"thpt", "Monday morning objective points to THPT («%s»)" % _main.get("world").get("objective_text"))
	var tech: int = GameState.technology
	var t0: int = GameState.minutes
	# Lớp học là trang mini-game riêng (quiz_page.gd): autopilot trả lời (đọc current_answer) thay cho hộp thoại.
	_main.get("activities").set("autopilot", true)
	await _do(&"thpt", ["Vô lớp"])
	_main.get("activities").set("autopilot", false)
	_check(GameState.technology == tech + 10 + 4 * 2, "class: +10 Technology + 4 right answers × 2 (got %+d)" % (GameState.technology - tech))
	_check(GameState.minutes == t0 + GameState.TIME_SCHOOL and LifeState.attended.has(GameState.day), "class costs 3 h and records attendance")
	tech = GameState.technology
	await _do(&"thpt", ["Vô lớp"])
	_check(GameState.technology == tech, "class only once a day")
	GameState.set_time(GameState.day, 14 * 60)
	await _do(&"thpt", ["thư viện"])
	_check(GameState.technology == tech + 4, "library (afternoon) +4 Technology")
	_goto(6, 9 * 60)
	tech = GameState.technology
	var m: int = GameState.minutes
	await _do(&"thpt", ["Vô lớp"])
	_check(GameState.technology == tech and GameState.minutes == m, "Sunday: school closed, nothing gained or spent")
	_goto(1, 11 * 60, true)
	tech = GameState.technology
	await _do(&"thpt", ["Vô lớp"])
	_check(GameState.technology == tech and not LifeState.attended.has(GameState.day), "weekday 11:00: too late for class")


func _test_jobs() -> void:
	_main.get("activities").set("autopilot", true)
	_goto(2, 13 * 60, true)
	# Bốc gạch (công trường bờ nam): đứng sẵn ở đống gạch.
	_main.get("world").get("player").position = Vector2(1146, 784)
	var money: int = GameState.money
	await _do(&"site", ["Làm một ca"], 4000)
	_check(GameState.money - money == Activities.BRICK_FULL_PAY, "brick job pays a full shift (%+d)" % (GameState.money - money))
	for job in [["npc_ba_lan", "job_shop", "Phụ bán cơm", 70000], ["npc_chu_bay", "job_boat", "Chạy ghe", 100000]]:
		LifeState.unlock(String(job[1]))
		money = GameState.money
		var t0: int = GameState.minutes
		var ok: bool = await _do(StringName(job[0]), [String(job[2])], 5000)
		var gained: int = GameState.money - money
		_check(ok and gained >= int(job[3] * 0.5) and gained <= int(job[3] * 1.3) and GameState.minutes >= t0 + 120,
			"%s: paid %d within ×0,5–1,3 of %d, 2 h spent" % [job[1], gained, job[3]])
		money = GameState.money
		await _do(StringName(job[0]), [String(job[2])], 3000)
		_check(GameState.money == money, "%s: second shift the same day pays nothing" % job[1])
	GameState.set_time(GameState.day, 22 * 60 + 30)
	money = GameState.money
	_check(not Activities.is_done(&"farm"), "farm still available today")
	await _do(&"farm", [])
	_check(GameState.money == money and not Activities.is_done(&"farm"), "after hours: rice field closed with a hint")
	_main.get("activities").set("autopilot", false)


func _test_shops() -> void:
	_goto(2, 10 * 60, true)
	GameState.money = 500000
	var have: int = GameState.owned_total(&"cua_tre")
	await _do(&"co_ba", ["Cựa tre"])
	_check(GameState.money == 500000 - 60000 and GameState.owned_total(&"cua_tre") == have + 1, "Cô Ba: buy Cựa tre (−60.000đ, owned %d)" % GameState.owned_total(&"cua_tre"))
	GameState.money = 1000
	var ms: int = GameState.owned_total(&"mao_sat")
	await _do(&"co_ba", ["Mào sắt"])
	_check(GameState.money == 1000 and GameState.owned_total(&"mao_sat") == ms, "Cô Ba: not enough money → nothing bought")
	var labels: Array = []
	GameState.money = 2000000
	_answers = []
	_drive = false
	_main.call("_on_interact", &"co_ba")
	await _until(func() -> bool: return (_main.get("dialog") as DialogBox)._mode == 2, 600)
	labels = (_main.get("dialog") as DialogBox)._options.duplicate()
	_drive = true
	await _until(_idle, 600)
	var shown: bool = false
	for l in labels:
		shown = shown or String(l).contains("Cựa tre") and String(l).contains("(có %d)" % GameState.owned_total(&"cua_tre"))
	_check(shown, "shop rows show owned counts")
	await _do(&"market_gear", ["Mũ đồng"])
	_check(GameState.owned_total(&"mu_dong") == 1 and GameState.money == 2000000 - 650000, "market gear: Mũ đồng 650.000đ (weekday, no discount)")
	var lua: int = GameState.item_count(&"lua")
	var before: int = GameState.money
	await _do(&"market_food", ["Lúa ×5"])
	_check(GameState.item_count(&"lua") == lua + 5 and before - GameState.money == 67500, "market food: bulk Lúa ×5 at −10%% (paid %d)" % (before - GameState.money))
	await _do(&"market_eggs", ["Trứng gà tre"])
	_check(GameState.item_count(&"trung_ga_tre") == 1, "market eggs: buy an egg")
	var n: int = GameState.chickens.size()
	await _do(&"market_chicken", ["Mua Gà tre"])
	_check(GameState.chickens.size() == n + 1, "chicken stall: buy a Gà tre (coop %d/%d)" % [GameState.chickens.size(), GameState.coop_capacity()])
	before = GameState.money
	var price: int = GameState.sell_price(GameState.chickens.size() - 1)
	await _do(&"market_chicken", ["Bán %s" % String(GameState.chickens[GameState.chickens.size() - 1]["name"]), "Bán"])
	_check(GameState.chickens.size() == n and GameState.money == before + price, "chicken stall: sell it back (+%d)" % price)
	GameState.set_time(GameState.day, 19 * 60)
	before = GameState.money
	await _do(&"market_gear", ["Cựa đồng"])
	_check(GameState.money == before, "market closed in the evening")


func _test_cat_shop() -> void:
	GameState.set_time(GameState.day, 14 * 60)
	GameState.kho_ga = 2.0
	var money: int = GameState.money
	await _do(&"cat_shop", ["Bán 1 kg"])
	_check(GameState.money == money + 50000 and is_equal_approx(GameState.kho_ga, 1.0), "Lão Gà Khô: sell 1 kg Khô Gà for 50.000đ")
	await _do(&"cat_shop", ["Pate Lão Gà Khô"])
	_check(GameState.item_count(&"pate_meo") == 1 and is_equal_approx(GameState.kho_ga, 0.2), "Lão Gà Khô: buy an exclusive item with Khô Gà (left %.2f kg)" % GameState.kho_ga)
	money = GameState.money
	await _do(&"cat_shop", ["Bán hết Khô Gà"])
	_check(GameState.money == money + 10000 and is_equal_approx(GameState.kho_ga, 0.0), "Lão Gà Khô: sell all (0,2 kg → 10.000đ, still 50.000đ/kg)")
	_check(String(_speakers.get("Lão Gà Khô", "-")) == "res://game/art/npc/lao_ga_kho.png",
		"Lão Gà Khô speaks with his own portrait (%s)" % str(_speakers.get("Lão Gà Khô", "never spoke")))
	_check(not _speakers.has("Mèo tam thể") and Items.SHOP_NAMES[&"meo"] == "Lão Gà Khô", "old «Mèo tam thể» shopkeeper / «Tiệm Mèo» shop name gone")
	_check(LifeState.seen("kho_ga") and LifeState.seen("shop") and LifeState.seen("eggs"), "shop / eggs / Khô Gà tutorials shown once")


func _test_social_and_quest() -> void:
	GameState.set_time(GameState.day, 10 * 60)
	var aff0: int = LifeState.aff("npc_chu_muoi")
	var t0: int = GameState.minutes
	await _do(&"npc_chu_muoi", ["Trò chuyện"])
	_check(LifeState.aff("npc_chu_muoi") == aff0 + 1 and GameState.minutes == t0 + 15, "chat: +1 affinity, 15 minutes")
	await _do(&"npc_chu_muoi", ["Trò chuyện"])
	_check(LifeState.aff("npc_chu_muoi") == aff0 + 1, "chat: affinity once per day")
	GameState.set_time(GameState.day + 1, 10 * 60)
	await _do(&"npc_chu_muoi", ["Trò chuyện"])
	_check(LifeState.has("discount_market"), "affinity 2 with Chú Mười unlocks the market discount")
	GameState.set_time(GameState.day + 1, 10 * 60)
	await _do(&"npc_chu_muoi", ["Trò chuyện", "Dạ, để con giúp"])
	_check(LifeState.quest_state("q_chau_kieng") == LifeState.Q_ACTIVE, "affinity 3 offers a quest, accepted")
	_main.call("_refresh_status")
	_check(StringName(_main.get("world").get("marker_target")) == &"npc_ba_lan", "quest objective arrow points to Bà Lan («%s»)" % _main.get("world").get("objective_text"))
	var cat: int = GameState.item_count(&"mao_cat")
	await _do(&"npc_ba_lan", [])
	_check(LifeState.quest_state("q_chau_kieng") == LifeState.Q_DONE and GameState.item_count(&"mao_cat") == cat + 1, "quest completed at Bà Lan: Mào cắt gọn reward")
	# Quest cờ tướng (thắng giao hữu rồi về kể ông Tám) được kiểm ở phần giao hữu.
	LifeState.affinity["npc_ong_tam"] = 0
	GameState.set_time(GameState.day + 1, 11 * 60)
	await _do(&"npc_ong_tam", ["Trò chuyện", "Dạ, để con giúp"])
	_check(LifeState.quest_state("q_co_tuong") == LifeState.Q_ACTIVE, "Ông Tám's chess quest started")


func _test_lien_tinh() -> void:
	_goto(4, 15 * 60, true)
	GameState.money = 0
	await _do(&"arena_lien_tinh", ["Đăng ký", "Đăng ký luôn"])
	_check(GameState.league_round(&"lien_tinh") < 0, "Liên tỉnh: registration refused without the fee")
	GameState.money = 1000000
	await _do(&"arena_lien_tinh", ["Đăng ký", "Đăng ký luôn"])
	_check(GameState.league_round(&"lien_tinh") == 0 and GameState.money == 900000, "Liên tỉnh: registered (fee 100.000đ)")
	_check(StoryLeagues.round_block_reason(&"lien_tinh") != "", "no round on a Friday afternoon")
	_goto(5, 19 * 60)
	await _do(&"arena_lien_tinh", ["Vào sới"], 4000)
	var cfg: Dictionary = _main.get("last_battle_config")
	_check(GameState.league_round(&"lien_tinh") == 1 and GameState.money == 900000 + 150000, "round 1 win advances and pays 150.000đ")
	_check(String(cfg.get("mode", "")) == "normal" and StringName(cfg.get("arena_variant", &"")) == &"lien_tinh"
		and String(cfg["opponent"].get("id", "")) == "lt_hai_ben_tre" and cfg["opponent"].has("stats"),
		"league match config: mode normal, arena lien_tinh, built opponent side")
	var losses: int = int(GameState.active_chicken()["losses"])
	_results = [{"won": false}]
	await _do(&"arena_lien_tinh", ["Vào sới"], 4000)
	_check(GameState.league_round(&"lien_tinh") < 0 and int(GameState.tournament_progress["lien_tinh"]["eliminated_week"]) == GameState.week()
		and int(GameState.active_chicken()["losses"]) == losses + 1, "round 2 loss eliminates until next week (recorded once)")
	await _do(&"arena_lien_tinh", ["Đăng ký", "Đăng ký luôn"])
	_check(GameState.league_round(&"lien_tinh") < 0, "re-registration refused in the same week")
	# Nhảy tới chung kết.
	_goto(6, 19 * 60)
	GameState.tournament_progress["lien_tinh"] = {"round": 4, "registered": true, "champion": false, "eliminated_week": 0}
	var money: int = GameState.money
	var bio: int = GameState.biotech
	await _do(&"arena_lien_tinh", ["Vào sới"], 4000)
	_check(GameState.is_champion(&"lien_tinh") and GameState.money == money + 2000000 and GameState.biotech == bio + 10,
		"Liên tỉnh champion: 2.000.000đ + 10 Biotech")
	_check((GameState.active_chicken()["titles"] as Array).has(GameState.TITLE_NAMES[2]) and LifeState.dream_seen
		and GameState.current_act() >= 3, "title awarded, grandpa's dream played, Olympic opened (act %d)" % GameState.current_act())


func _test_olympic_and_spar() -> void:
	_goto(0, 14 * 60, true)
	GameState.money = 3000000
	await _do(&"arena_olympic", ["Đăng ký", "Đăng ký luôn"])
	_check(GameState.league_round(&"olympic") < 0 and GameState.last_error.contains("đột biến"), "Olympic refused without 3 mutations")
	for m in [&"fast_muscle", &"iron_bone", &"burning_blood"]:
		(GameState.active_chicken()["mutations"] as Array).append(m)
	await _do(&"arena_olympic", ["Đăng ký", "Đăng ký luôn"])
	_check(GameState.league_round(&"olympic") == 0, "Olympic registration with 3 mutations")
	_goto(5, 19 * 60)
	await _do(&"arena_olympic", ["Vào sới"], 4000)
	var cfg: Dictionary = _main.get("last_battle_config")
	_check(bool(cfg.get("hell_mode", false)) and is_equal_approx(float(cfg.get("round_time", 0.0)), 60.0)
		and int(cfg.get("opponent_start_card_gauge", 0)) == 4 and StringName(cfg.get("arena_variant", &"")) == &"olympic",
		"Hell Mode config reaches the director (60 s, card gauge 4, olympic arena)")
	_check(GameState.league_round(&"olympic") == 1, "Olympic round 1 won")
	# Giao hữu ở sới làng: tối đa 2 keo/ngày, có tiền xâu; thắng → quest ông Tám sang bước "về kể".
	_goto(1, 14 * 60, true)
	var money: int = GameState.money
	await _do(&"arena", ["Đá giao hữu", "Ba Khía"], 4000)
	await _do(&"arena", ["Đá giao hữu", "Ba Khía"], 4000)
	_check(LifeState.today("spar") == 2 and GameState.money == money + 40000, "two spars today, purses paid (%+d)" % (GameState.money - money))
	var n: int = _director_modes.size()
	await _do(&"arena", ["Đá giao hữu", "Ba Khía"], 2000)
	_check(_director_modes.size() == n and LifeState.today("spar") == 2, "third spar refused (daily limit)")
	_check(int(LifeState.quest("q_co_tuong")["step"]) == 1, "spar win advances Ông Tám's quest")
	await _do(&"npc_ong_tam", [])
	_check(LifeState.quest_state("q_co_tuong") == LifeState.Q_DONE, "Ông Tám's quest completed")


func _test_police() -> void:
	# a) Sống sót → tẩu thoát (giả) → cắt cảnh → hậu quả, ở vòng 2 Olympic (chênh lệch lớn).
	_goto(5, 19 * 60, true)
	GameState.tournament_progress["olympic"]["round"] = 1
	var opp: Dictionary = GameState.next_league_opponent(&"olympic")
	_check(GameState.can_call_police(opp), "Olympic round 2 is lopsided enough for the police call (mismatch %.2f)" % GameState.mismatch(opp))
	_main.set("escape_override", {"escaped": true, "caught": false, "cancelled": false})
	_main.set("test_auto_cutscene", true)
	var money: int = GameState.money
	var cond: float = float(GameState.active_chicken()["condition"])
	var losses: int = int(GameState.active_chicken()["losses"])
	_pre_actions = ["police"]
	_results = [{"won": false, "raid": true, "survived": true, "mode": "police"}]
	await _do(&"arena_olympic", ["Vào sới"], 6000)
	var cfg: Dictionary = _main.get("last_battle_config")
	_check(String(cfg.get("mode", "")) == "police", "police call → director runs in police mode")
	_check(GameState.league_round(&"olympic") == 1 and LifeState.postponed_until(&"olympic") == GameState.day + 2
		and int(LifeState.weakened.get(String(opp["id"]), 0)) == 1, "raid: round voided, league postponed 2 days, opponent fined")
	_check(GameState.money == money and is_equal_approx(float(GameState.active_chicken()["condition"]), cond)
		and int(GameState.active_chicken()["losses"]) == losses and LifeState.raid_day == GameState.day,
		"raid: no prize, no condition loss, no loss recorded, gossip scheduled")
	_check(StoryLeagues.round_block_reason(&"olympic").contains("hoãn"), "postponed round can't be played tonight")
	# b) Hạn mỗi tuần: gọi lần hai trong tuần → câu từ chối, quay lại màn chuẩn bị, đá thường.
	_goto(6, 14 * 60)
	var pre0: int = _pre_count
	_pre_actions = ["police", "start"]
	_results = [{"won": true}]
	await _do(&"arena_olympic", ["Đá giao hữu", "Chảo Lửa"], 4000)
	_check(_pre_count == pre0 + 2 and _director_modes.back() == "friendly", "weekly cooldown: second call refused, back to the prep screen")
	# c) Bị hạ trong 30 giây → thua thường.
	_goto(1, 14 * 60, true)
	losses = int(GameState.active_chicken()["losses"])
	_pre_actions = ["police"]
	_results = [{"won": false, "raid": false, "survived": false, "mode": "police"}]
	await _do(&"arena_olympic", ["Đá giao hữu", "Chảo Lửa"], 4000)
	_check(int(GameState.active_chicken()["losses"]) == losses + 1 and LifeState.police_week == GameState.week(), "KO'd during the 30 s → normal loss")
	# d) Bị bắt khi tẩu thoát → thua + phạt.
	_goto(1, 14 * 60, true)
	losses = int(GameState.active_chicken()["losses"])
	money = GameState.money
	_main.set("escape_override", {"escaped": false, "caught": true, "cancelled": false})
	_pre_actions = ["police"]
	_results = [{"won": false, "raid": true, "survived": true, "mode": "police"}]
	await _do(&"arena_olympic", ["Đá giao hữu", "Chảo Lửa"], 4000)
	_check(int(GameState.active_chicken()["losses"]) == losses + 1 and GameState.money == money - StoryLeagues.POLICE_FINE,
		"caught in the escape → loss + %d fine" % StoryLeagues.POLICE_FINE)
	# e) Mini-game tẩu thoát thật (autopilot giỏi) + cắt cảnh thật.
	if ResourceLoader.exists(ESCAPE_GAME):
		_goto(1, 14 * 60, true)
		_main.set("escape_override", {})
		_main.set("test_escape_autopilot", 1.0)
		var uses: int = LifeState.police_uses
		losses = int(GameState.active_chicken()["losses"])
		_pre_actions = ["police"]
		_results = [{"won": false, "raid": true, "survived": true, "mode": "police"}]
		var ok: bool = await _do(&"arena_olympic", ["Đá giao hữu", "Chảo Lửa"], 30000)
		var escaped: bool = LifeState.police_uses == uses + 1
		_check(ok and (escaped or int(GameState.active_chicken()["losses"]) == losses + 1),
			"real EscapeGame (autopilot) finishes and is settled (%s)" % ("escaped → raid" if escaped else "caught → loss"))
		_main.set("test_escape_autopilot", -1.0)
	_main.set("escape_override", {})


func _test_bedtime() -> void:
	GameState.set_time(GameState.day, 22 * 60 + 50)
	var day0: int = GameState.day
	await _do(&"chu_tu", ["Trò chuyện"])
	await _until(_idle, 2000)
	_check(GameState.day == day0 + 1 and GameState.minutes == GameState.FORCED_WAKE, "past 23:00 → sent home to sleep, wake 08:00 (day %d %s)" % [GameState.day, GameState.time_text()])


func _test_allowance_save_continue() -> void:
	# Tuần này đi học đủ 5 buổi → sáng Thứ Hai Mẹ cho tiền tiêu vặt.
	_goto(6, 20 * 60)
	var first: int = GameState.day - 6
	for d in range(first, first + 5):
		if not LifeState.attended.has(d):
			LifeState.attended.append(d)
	LifeState.finale_day = mini(LifeState.finale_day, first)
	var money: int = GameState.money
	await _do(&"home", ["Đi ngủ"], 3000)
	_check(GameState.weekday() == 0 and GameState.money == money + 100000, "Monday morning: full attendance → 100.000đ allowance")
	# Lưu → tiếp tục.
	var snap: Dictionary = {"money": GameState.money, "day": GameState.day, "aff": LifeState.affinity.duplicate(),
		"quests": LifeState.quests.duplicate(true), "unlocks": LifeState.unlocks.duplicate(), "tut": LifeState.tutorials.duplicate(),
		"police": LifeState.police_week, "olympic": GameState.league_round(&"olympic"), "post": LifeState.postponed_until(&"olympic"),
		"tech": GameState.technology, "attended": LifeState.attended.duplicate()}
	_drive = false
	_main.queue_free()
	_main = null
	await _frames(3)
	GameState.reset()
	Activities.reset()
	HomeState.reset()
	LifeState.reset()
	_title_choice = "continue"
	_drive = true
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	var ok: bool = await _until(func() -> bool: return _main.get("world") != null and _idle(), 3000)
	_check(ok and GameState.money == int(snap["money"]) and GameState.day == int(snap["day"]) and GameState.technology == int(snap["tech"]),
		"continue restores money/day/Technology")
	_check(LifeState.finale_act1 and LifeState.affinity == snap["aff"] and LifeState.quests == snap["quests"]
		and LifeState.unlocks == snap["unlocks"] and LifeState.tutorials == snap["tut"] and LifeState.attended == snap["attended"],
		"continue restores affinity, quests, unlocks, tutorials, attendance")
	_check(LifeState.police_week == int(snap["police"]) and GameState.league_round(&"olympic") == int(snap["olympic"])
		and LifeState.postponed_until(&"olympic") == int(snap["post"]), "continue restores police cooldown + league schedule")
	var world: Node = _main.get("world")
	_check(world != null and String(world.get("objective_text")) != "" and String(world.get("objective_text")) != "Hết Act 1",
		"continue resumes with a free-roam objective («%s»)" % world.get("objective_text"))
