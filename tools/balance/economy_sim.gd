extends RefCounted

## Mô phỏng kinh tế cho một người chơi "điển hình" sau Act 1 (dùng đúng API GameState v2: perform, train, buy,
## equip, feed, sleep, exchange_biotech, mutate, register_tournament, tournament_result).
## Không phải gameplay – chỉ để kiểm cân bằng (GDD 7.2, 7.4, 7.5). Chạy báo cáo:
##   godot --headless --path . -s res://tools/balance/run_economy_report.gd
## Lưu ý: ghi đè trạng thái tĩnh của GameState (gọi GameState.reset() sau khi dùng).

## Giả định của người chơi điển hình (PLACEHOLDER):
const MINIGAME_FACTOR: float = 0.9      # làm minigame khá (0,5–1,3)
const FOOD_RESERVE_DAYS: int = 7        # luôn chừa tiền Lúa 7 ngày trước khi mua đồ
const BEATABLE_GAP: float = 1.0         # chỉ vào trận khi mismatch ≤ 1,0 (người chơi ngang sức AI thì thắng)
## Thứ tự mua đồ (mua là gắn luôn; món sau cùng ô coi như tốt hơn).
## Đồ Act 2 trước Act 3 (món chưa mở khóa chặn danh sách cho tới khi mở).
const SHOPPING_LIST: Array[StringName] = [
	&"cua_sat", &"giap_tre", &"canh_lua", &"mao_cat", &"cua_dong", &"giap_dong", &"mu_dong", &"canh_gio",
	&"mao_dong", &"cua_bac", &"giap_thep", &"mu_thep", &"canh_sat",
]


## Chạy days ngày. Trả về {weeks: [...], events: [...], milestones: {...}}.
static func simulate(days: int = 84) -> Dictionary:
	GameState.reset()
	GameState.rng.seed = 7
	# Hết Act 1: vô địch Ao Làng, Ô Mun Lv5 (cap Act 1), có Mào sắt + Dao chân + 3 thẻ, còn ~300k.
	GameState.stage = GameState.Stage.ACT_END
	GameState.money = 300000
	GameState.level = 5
	GameState.owns_mao_sat = true
	GameState.owns_dao_chan = true
	GameState.equip_mao_sat = true
	GameState.equip_dao_chan = true
	GameState.cards = [&"cuong_no", &"mai_rua", &"gio_song"]
	GameState.award_title(GameState.active, 1)
	var weeks: Array = []
	var events: Array = []
	var milestones: Dictionary = {}
	var week_row: Dictionary = _new_week(1)
	var shop_index: int = 0
	for i in range(days):
		var work_in: int = 0
		var prize_in: int = 0
		var spent: int = 0
		# ---- buổi sáng: đi học (T2–T6), thư viện
		if GameState.is_school_day():
			GameState.perform(&"class")
		GameState.perform(&"library")
		# ---- làm nghề: 2 ca ngày thường, 3 ca cuối tuần (mỗi lần đi tốn 30 phút)
		var shifts: Array[StringName] = [&"work_boat", &"work_brick"]
		if not GameState.is_school_day():
			shifts.append(&"work_shop")
		for shift in shifts:
			if not bool(GameState.perform(&"travel")["ok"]):
				break
			var r: Dictionary = GameState.perform(shift, MINIGAME_FACTOR)
			work_in += int(r["money"])
		GameState.perform(&"travel")
		# ---- luyện gà tới khi mệt / hết giờ (chừa 1 giờ cho trận)
		while GameState.minutes_left() > 120:
			if not bool(GameState.train(GameState.active)["ok"]):
				break
		# ---- Biotech & đột biến
		var can_convert: int = GameState.technology / 10
		if can_convert > 0:
			GameState.exchange_biotech(can_convert)
		for m in MutationCatalog.ORDER:
			if GameState.mutate(GameState.active, m):
				events.append("Ngày %d: đột biến %s" % [GameState.day, MutationCatalog.display_name(m)])
		# ---- mua đồ theo danh sách
		while shop_index < SHOPPING_LIST.size():
			var id: StringName = SHOPPING_LIST[shop_index]
			var price: int = int(ItemCatalog.get_item(id)["price"])
			if not GameState.is_unlocked(id) or GameState.money - price < FOOD_RESERVE_DAYS * 15000:
				break
			GameState.buy(id)
			GameState.equip(GameState.active, ItemCatalog.slot_of(id), id)
			spent += price
			events.append("Ngày %d: mua %s (%s)" % [GameState.day, ItemCatalog.display_name(id), GameState.money_text(price)])
			shop_index += 1
		# ---- giải cuối tuần
		for tid in [&"lien_tinh", &"olympic"]:
			if GameState.is_champion(tid) or not GameState.is_tournament_day(tid):
				continue
			if not bool(GameState.can_enter(tid, -1, true)["ok"]) and not bool((GameState.tournament_progress.get(String(tid), {}) as Dictionary).get("registered", false)):
				continue
			if not GameState.register_tournament(tid, true):
				continue
			if not milestones.has(String(tid) + "_registered"):
				milestones[String(tid) + "_registered"] = GameState.day
				spent += int(TournamentCatalog.info(tid)["entry"]["fee"])
			while GameState.current_round_opponent(tid) != "":
				var opp: String = GameState.current_round_opponent(tid)
				var gap: float = GameState.mismatch(GameState.match_config(tid)["opponent"])
				if gap > BEATABLE_GAP or not GameState.spend_time(GameState.time_cost(&"match")):
					break
				var res: Dictionary = GameState.tournament_result(tid, true)
				prize_in += int(res["money"])
				events.append("Ngày %d: thắng %s (gap %.2f) +%s" % [GameState.day, opp, gap, GameState.money_text(int(res["money"]))])
				if bool(res["champion"]):
					milestones[String(tid) + "_champion"] = GameState.day
		# ---- tối: mua Lúa, cho ăn, ngủ
		var food_spent: int = 0
		if GameState.item_count(&"lua") <= 0 and GameState.buy(&"lua"):
			food_spent = 15000
		GameState.feed(GameState.active, &"lua")
		week_row["work_in"] += work_in
		week_row["prize_in"] += prize_in
		week_row["gear_and_fees"] += spent
		week_row["food"] += food_spent
		if GameState.weekday() == 6:
			_close_week(week_row)
			weeks.append(week_row)
			week_row = _new_week(GameState.week() + 1)
		GameState.sleep()
	if int(week_row["work_in"]) > 0:
		_close_week(week_row)
		weeks.append(week_row)
	return {"weeks": weeks, "events": events, "milestones": milestones}


static func _new_week(n: int) -> Dictionary:
	return {"week": n, "work_in": 0, "prize_in": 0, "gear_and_fees": 0, "food": 0}


static func _close_week(row: Dictionary) -> void:
	row["money_end"] = GameState.money
	row["level"] = GameState.level
	row["mutations"] = (GameState.active_chicken()["mutations"] as Array).size()
	row["technology"] = GameState.technology
	row["biotech"] = GameState.biotech
	row["power"] = snappedf(GameState.power_rating(GameState.player_side()), 0.1)
	var next_tid: StringName = &"lien_tinh" if not GameState.is_champion(&"lien_tinh") else &"olympic"
	var rounds: Array = TournamentCatalog.rounds(next_tid)
	row["gap_next_final"] = snappedf(GameState.mismatch(GameState.opponent_side(String(rounds[rounds.size() - 1]))), 0.01)
	row["next"] = String(next_tid)


static func report_lines(result: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("Tuần | thu nghề | thưởng giải | đồ+phí | ăn | tiền cuối | Lv | mut | Tech | Bio | power | gap chung kết (%s)" % "giải kế")
	for w in result["weeks"]:
		lines.append("%4d | %9s | %11s | %10s | %7s | %11s | %2d | %d | %3d | %3d | %6.1f | %.2f (%s)" % [
			int(w["week"]), GameState.money_text(int(w["work_in"])), GameState.money_text(int(w["prize_in"])),
			GameState.money_text(int(w["gear_and_fees"])), GameState.money_text(int(w["food"])),
			GameState.money_text(int(w["money_end"])), int(w["level"]), int(w["mutations"]), int(w["technology"]),
			int(w["biotech"]), float(w["power"]), float(w["gap_next_final"]), String(w["next"])])
	lines.append("Mốc: %s" % str(result["milestones"]))
	for e in result["events"]:
		lines.append("  " + String(e))
	return lines
