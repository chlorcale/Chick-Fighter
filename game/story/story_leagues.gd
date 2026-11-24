extends RefCounted

## GIẢI ĐẤU SAU ACT 1 (GDD 7.4, 9.3) + giao hữu + "Gọi tay trong" (báo công an) + các mốc truyện lớn:
## kết Act 1 → mở Act 2 (Chú Tư đưa bản đồ vẽ tay), giấc mơ ông nội sau Liên tỉnh (mở Olympic), kết game sau Olympic.
## Lịch giải (owner duyệt): vòng 1–3 tối Thứ 7, vòng 4–5 tối Chủ nhật (Tournaments.weekdays), mỗi lần ghé đá một vòng,
## 18:00–22:00. Thua = bị loại tới tuần sau (GameState.tournament_result). Lỡ hẹn: vòng dời sang tuần sau.
## Bố ráp (sống sót 30 giây + chạy thoát): vòng bị hoãn 2 ngày (dời sang buổi giải kế tiếp), chủ gà đối thủ bị phạt nên
## lần gặp lại gà nó yếu hơn (−1 Lv, −0,1 skill mỗi lần; dùng một lần), không thưởng, không mất Thể trạng, chút EXP.
## main.gd giữ một thể hiện: leagues = StoryLeagues.new(self).

const LifeState := preload("res://game/sim/life_state.gd")
const Tournaments := preload("res://game/data/tournaments.gd")
const Calendar := preload("res://game/data/calendar.gd")
const Activities := preload("res://game/world/activities.gd")
const Audio := preload("res://game/audio/audio_director.gd")
const HomeState := preload("res://game/home/home_state.gd")
const ESCAPE_GAME_PATH: String = "res://game/escape/escape_game.gd"
const ESCAPE_CUTSCENE_PATH: String = "res://game/escape/escape_cutscene.gd"

const VENUE: Dictionary = {&"lien_tinh": &"arena_lien_tinh", &"olympic": &"arena_olympic"}
const ORGANISER: Dictionary = {&"lien_tinh": "Ông bầu Sáu Lộc", &"olympic": "Cô Diệu"}
## Số vòng đá vào ngày giải thứ nhất (Thứ 7); còn lại ngày thứ hai (Chủ nhật).
const FIRST_DAY_ROUNDS: int = 3
const SPAR_PER_DAY: int = 2
const SPAR_BANDS: Dictionary = {&"arena": [1, 2], &"arena_lien_tinh": [2, 3], &"arena_olympic": [3, 4]}
const POLICE_FINE: int = 50000
const RAID_POSTPONE_DAYS: int = 2
const ESCAPE_DIFFICULTY: Dictionary = {&"lien_tinh": 0.45, &"olympic": 0.8}

var main: Node


func _init(p_main: Node) -> void:
	main = p_main


func _dialog() -> DialogBox:
	return main.get("dialog") as DialogBox


# =================================================================== lịch giải (tĩnh – StoryLife cũng dùng)

static func round_weekday(tid: StringName, r: int) -> int:
	var wds: Array = Tournaments.info(tid).get("weekdays", [5, 6])
	if wds.is_empty():
		return 5
	return int(wds[0]) if r < FIRST_DAY_ROUNDS else int(wds[mini(1, wds.size() - 1)])


## Số ngày tới buổi đá vòng hiện tại (0 = hôm nay), −1 nếu chưa đăng ký. Tính cả thời gian tạm hoãn.
static func days_until_round(tid: StringName) -> int:
	var r: int = GameState.league_round(tid)
	if r < 0:
		return -1
	var wd: int = round_weekday(tid, r)
	for d in range(0, 21):
		var day: int = GameState.day + d
		if Calendar.weekday(day) == wd and day >= LifeState.postponed_until(tid):
			return d
	return -1


## "" nếu vòng hiện tại đá được ngay bây giờ, không thì lý do (tiếng Việt).
static func round_block_reason(tid: StringName) -> String:
	var r: int = GameState.league_round(tid)
	if r < 0:
		return "Chưa đăng ký giải."
	if LifeState.postponed_until(tid) > GameState.day:
		return "Giải đang tạm hoãn vì vụ bố ráp. Vòng %d dời qua tối %s tuần tới." % [r + 1,
			Calendar.WEEKDAY_NAMES[round_weekday(tid, r)]]
	if GameState.weekday() != round_weekday(tid, r):
		return "Vòng %d đá tối %s (còn %d ngày). Hôm nay %s hổng có vòng của con." % [r + 1,
			Calendar.WEEKDAY_NAMES[round_weekday(tid, r)], days_until_round(tid), GameState.weekday_name()]
	if GameState.clock_running() and GameState.period() < GameState.Period.TOI:
		return "Vòng đấu bắt đầu lúc 18:00. Bây giờ mới %s – đi làm, chăm gà rồi tối quay lại." % GameState.time_text()
	if not GameState.can_spend(GameState.TIME_BATTLE):
		return "Trễ quá rồi, sới đóng lúc 22:00. Vòng %d dời qua tối %s tuần sau." % [r + 1, Calendar.WEEKDAY_NAMES[round_weekday(tid, r)]]
	return ""


## Đối thủ bị phạt sau vụ bố ráp: yếu đi (−1 Lv, −0,1 skill mỗi lần), dựng lại bên đấu từ dữ liệu đã chỉnh.
static func weaken(side: Dictionary) -> Dictionary:
	var id: String = String(side.get("id", ""))
	var n: int = int(LifeState.weakened.get(id, 0))
	if n <= 0:
		return side
	var raw: Dictionary = side.duplicate(true)
	raw["lv"] = maxi(1, int(raw.get("lv", 1)) - n)
	raw["skill"] = clampf(float(raw.get("skill", 0.5)) - 0.1 * float(n), 0.0, 1.0)
	raw.erase("stats")
	var out: Dictionary = GameState.side_from_raw(raw)
	out["id"] = id
	out["weakened"] = n
	return out


# =================================================================== sới Liên tỉnh / Olympic

func venue(tid: StringName) -> void:
	var dlg: DialogBox = _dialog()
	var who: String = ORGANISER[tid]
	var info: Dictionary = Tournaments.info(tid)
	if tid == &"lien_tinh" and not GameState.is_champion(&"ao_lang"):
		await dlg.say([[who, "Sới Liên tỉnh miền Tây đó em! Mà chỉ nhận gà đã vô địch giải làng. Về Ao Làng đá cho thắng rồi lên đây nghen."]])
		return
	if tid == &"olympic" and not GameState.is_champion(&"lien_tinh"):
		await dlg.say([[who, "Nhà thi đấu Olympic Đá Gà chỉ mở cho nhà vô địch Liên tỉnh miền Tây. Sới Liên tỉnh ở phía tây nhà thi đấu đó em."]])
		return
	if tid == &"lien_tinh" and LifeState.today("met:" + String(tid)) == 0 and LifeState.talk_count("bau_sau") == 0:
		LifeState.chat("bau_sau")
		await dlg.say([[who, "Ồ hô! Nhà vô địch Ao Làng đây rồi bà con ơi! Tui là Sáu Lộc, bầu sới Liên tỉnh miền Tây – sới lớn nhứt từ Bến Tre tới Cà Mau!"],
			[who, "Ở đây đá năm vòng, toàn gà có chủ có tên, có đồ có nghề. Gà làng mà lên đây hổng sắm đồ là… ăn hành à nghen!"]])
	LifeState.add_today("met:" + String(tid))
	while true:
		var options: Array = []
		var details: Array = []
		var actions: Array = []
		var r: int = GameState.league_round(tid)
		if GameState.is_champion(tid):
			options.append("Ngắm bảng vàng nhà vô địch")
			details.append("Bạn đã vô địch %s." % String(info["name"]))
			actions.append("champ")
		elif r >= 0:
			var block: String = round_block_reason(tid)
			var opp: Dictionary = GameState.next_league_opponent(tid)
			options.append("Vào sới: vòng %d/%d gặp %s" % [r + 1, Tournaments.round_count(tid), String(opp.get("name", "?"))] if block == "" \
				else "Hỏi lịch vòng %d" % (r + 1))
			details.append(("Đối thủ: %s (Lv%d) của %s, %s. Thắng: %s." % [String(opp.get("name", "?")), int(opp.get("lv", 1)),
				String(opp.get("owner", "?")), String(opp.get("region", "")), GameState.money_text(
				int(info["prize_money"]) if r == Tournaments.round_count(tid) - 1 else int(info["round_prize"]))]) if block == "" else block)
			actions.append("round" if block == "" else "schedule")
		else:
			var fee: int = int(info["entry"]["fee"])
			options.append("Đăng ký giải (lệ phí %s)" % GameState.money_text(fee))
			var check: Dictionary = GameState.can_enter(tid)
			details.append("Đăng ký bằng %s (Lv%d). %s" % [GameState.chicken_name, GameState.level,
				"Đủ điều kiện." if bool(check["ok"]) else " ".join(check["reasons"])])
			actions.append("register")
		var spar_left: int = SPAR_PER_DAY - LifeState.today("spar")
		options.append("Đá giao hữu (còn %d keo hôm nay)" % maxi(spar_left, 0))
		details.append("Đá cho quen tay, thắng có chút tiền xâu + EXP. Từ chiều tới khuya, tối đa %d keo/ngày." % SPAR_PER_DAY)
		actions.append("spar")
		options.append("Hỏi luật & lịch giải")
		details.append("")
		actions.append("rules")
		options.append("Thôi")
		details.append("")
		actions.append("exit")
		var prompt: String = "%s đây! Bây giờ %s. Em tính sao?" % [String(info["name"]), GameState.clock_text()]
		var pick: int = await dlg.choose(who, prompt, options, details)
		match String(actions[pick]):
			"champ":
				await dlg.say([[who, "Tên %s với con %s khắc trên bảng vàng rồi đó! Bà con miệt này ai cũng biết." % [GameState.player_name, GameState.chicken_name]]])
			"schedule":
				await dlg.say([[who, round_block_reason(tid)]])
			"register":
				await register(tid)
			"round":
				await play_round(tid)
				return
			"spar":
				await spar(VENUE[tid])
				return
			"rules":
				await _rules(tid)
			_:
				return
		main.call("_refresh_status")


func _rules(tid: StringName) -> void:
	var info: Dictionary = Tournaments.info(tid)
	var who: String = ORGANISER[tid]
	var lines: Array = [[who, "Năm vòng: vòng 1–3 đá tối Thứ Bảy, bán kết với chung kết tối Chủ nhật, từ 6 giờ tới 10 giờ tối. Mỗi trận ba hiệp, thắng hai."],
		[who, "Thắng mỗi vòng %s, vô địch %s%s. Thua vòng nào là về nhà, tuần sau đăng ký lại." % [
			GameState.money_text(int(info["round_prize"])), GameState.money_text(int(info["prize_money"])),
			(" + %d Biotech" % int(info["prize_biotech"])) if int(info["prize_biotech"]) > 0 else ""]]]
	if bool(info["hell_mode"]):
		lines.append([who, "Luật Hell Mode: đồng hồ hiệp còn %d giây, gà đối thủ vô trận với %d Card Gauge. Chỉ nhận gà đã qua ít nhất 3 đột biến." % [
			int(info["round_time"]), int(info["opponent_start_card_gauge"])]])
		lines.append(["Mẹo", "Đột biến: đi học ở THPT → Technology → đổi Biotech ở bàn học trong nhà → đột biến gà ở chuồng (mỗi đột biến 6–10 Biotech, luôn có đánh đổi). Ấp trứng với nhiều Biotech cũng có thể ra gà sẵn đột biến."])
	await _dialog().say(lines)
	await main.life.tutorial("league")


func register(tid: StringName) -> void:
	var dlg: DialogBox = _dialog()
	var who: String = ORGANISER[tid]
	var info: Dictionary = Tournaments.info(tid)
	await main.life.tutorial("league")
	var first: Dictionary = GameState.opponent_side(String(Tournaments.rounds(tid)[0]))
	if int(first.get("lv", 1)) - GameState.level >= 3:
		var warn: int = await dlg.choose(who, "Gà em mới Lv%d, vòng một gặp gà Lv%d đó nghen. Vẫn đăng ký hả?" % [GameState.level, int(first["lv"])],
			["Đăng ký luôn!", "Thôi, để con đi làm sắm đồ, luyện gà đã"])
		if warn != 0:
			await dlg.say([[who, "Khôn đó! Đi làm kiếm tiền mua cựa, mua giáp, luyện gà cho lên cấp rồi quay lại."]])
			return
	if not GameState.register_tournament(tid):
		await dlg.say([[who, "Chưa được em ơi: %s" % GameState.last_error]])
		return
	await dlg.say([[who, "Ghi tên rồi! %s – gà %s. Lệ phí %s, cảm ơn em!" % [GameState.player_name, GameState.chicken_name,
		GameState.money_text(int(info["entry"]["fee"]))]],
		["", main.life.league_line()]])


## Một vòng giải: chào sân, Chú Tư gọi điện dặn, trận (qua màn chuẩn bị), kết quả.
func play_round(tid: StringName) -> void:
	var dlg: DialogBox = _dialog()
	var who: String = ORGANISER[tid]
	var cfg: Dictionary = GameState.match_config(tid)
	if cfg.is_empty():
		return
	var r: int = int(cfg["round"])
	var n: int = int(cfg["rounds"])
	var opp: Dictionary = weaken(cfg["opponent"])
	var round_name: String = "CHUNG KẾT" if r == n - 1 else ("BÁN KẾT" if r == n - 2 else "VÒNG %d" % (r + 1))
	var intro: Array = [[who, "Bà con ơi! %s %s! Bên này %s của %s, bên kia %s (Lv%d) của %s tới từ %s!" % [
		String(Tournaments.info(tid)["name"]), round_name, GameState.chicken_name, GameState.player_name,
		String(opp.get("name", "?")), int(opp.get("lv", 1)), String(opp.get("owner", "?")), String(opp.get("region", "miệt dưới"))]]]
	if opp.has("quote"):
		intro.append([String(opp.get("owner", "")), String(opp["quote"])])
	if int(opp.get("weakened", 0)) > 0:
		intro.append(["", "Nghe nói chủ gà bị phạt sau vụ bố ráp, gà nó ít được luyện – nhìn hơi đuối."])
	intro.append(["Chú Tư (điện thoại)", "Alô, chú nè. " + main.life.opponent_tip(opp)])
	await dlg.say(intro)
	var final: bool = r == n - 1
	var res: Dictionary = await main.run_match(opp, {
		"mode": "normal", "kind": "league", "tid": tid, "title": String(cfg["title"]), "prize": int(cfg["prize"]),
		"arena_variant": tid, "round_time": float(cfg["round_time"]), "hell_mode": bool(cfg["hell_mode"]),
		"opponent_start_card_gauge": int(cfg["opponent_start_card_gauge"]), "police_ok": true,
		"music": &"final" if final else &"battle", "escape_difficulty": float(ESCAPE_DIFFICULTY.get(tid, 0.5)),
	})
	var outcome: String = String(res.get("outcome", "back"))
	if outcome != "back" and outcome != "raid":
		LifeState.weakened.erase(String(opp.get("id", "")))
	match outcome:
		"won":
			var tr: Dictionary = res.get("league", {})
			if bool(tr.get("champion", false)):
				await champion(tid)
			else:
				var next: Dictionary = GameState.next_league_opponent(tid)
				await dlg.say([[who, "Thắng rồi bà con ơi! %s vô vòng trong!" % GameState.chicken_name],
					["Chú Tư (điện thoại)", "Reng reng… Chú nghe người ta kể rồi! Vòng tới gặp %s. %s" % [String(next.get("name", "?")),
						main.life.opponent_tip(next)]],
					["", main.life.league_line()]])
		"lost", "caught":
			await dlg.say([[who, "Tiếc quá! %s dừng bước ở %s. Tuần sau đăng ký lại nghen em." % [GameState.chicken_name, round_name.to_lower()]],
				["Chú Tư (điện thoại)", "Hông sao con. Về đi làm, sắm đồ, luyện gà. Thua keo này bày keo khác!"]])
		"raid":
			await dlg.say([[who, "(Trên loa) …Do sự cố… ngoài ý muốn… giải %s tạm hoãn hai ngày! Bà con về nghỉ!" % String(Tournaments.info(tid)["name"])],
				["", main.life.league_line()]])


func champion(tid: StringName) -> void:
	var dlg: DialogBox = _dialog()
	var info: Dictionary = Tournaments.info(tid)
	var who: String = ORGANISER[tid]
	await dlg.say([[who, "VÀ NHÀ VÔ ĐỊCH %s LÀ… %s CÙNG CHIẾN KÊ %s!" % [String(info["name"]).to_upper(), GameState.player_name.to_upper(),
		GameState.chicken_name.to_upper()]],
		["", "Nhận %s%s và danh hiệu «%s»." % [GameState.money_text(int(info["prize_money"])),
			(" + %d Biotech" % int(info["prize_biotech"])) if int(info["prize_biotech"]) > 0 else "", String(info["prize_title"])]],
		["Chú Tư (điện thoại)", "Con ơi… chú khóc rồi nè. Ông nội bây mà còn…"]])
	if tid == &"lien_tinh":
		await dream()
	elif tid == &"olympic":
		await ending()


## Giấc mơ ông nội (GDD 9.3: thắng Liên tỉnh → ông nội về trong mơ, nhắc lễ hội đền Vua Hùng) – mở Olympic.
func dream() -> void:
	var cut := Cutscene.new()
	main.add_child(cut)
	Audio.music(&"memory")
	Audio.ambience({&"crickets": 0.6, &"river": 0.2})
	await cut.play([
		["", "Đêm đó, %s ngủ thiếp đi bên chuồng gà. Gió sông thổi lành lạnh…" % GameState.player_name],
		["Ông nội", "Giỏi lắm con. Gà của con biết đọc đối thủ rồi đó."],
		["Ông nội", "Hồi xưa ông với con Ô Tía cũng tới được đây. Mà phía trước còn xa lắm…"],
		["Ông nội", "Lễ hội đền Vua Hùng năm nào cũng kể chuyện gà chín cựa. Người ta nói đó là truyền thuyết. Ông thì tin."],
		["Ông nội", "Olympic Đá Gà ở nhà thi đấu phía đông. Ở đó người ta đá luật Hell Mode – gà phải qua ba lần đột biến mới được vô."],
		["Ông nội", "Học cho giỏi, nuôi gà cho khéo. Biotech… à mà ông già rồi, ông hổng biết mấy chữ đó đâu. Hì hì."],
		["", "%s choàng tỉnh. Con %s đang gáy. Trời vừa sáng." % [GameState.player_name, GameState.chicken_name]],
	])
	LifeState.dream_seen = true
	Audio.music(&"village")
	await _dialog().say([["", "Mở khóa: Olympic Đá Gà (Nhà thi đấu Olympic, phía đông). Cần gà có ít nhất 3 đột biến + lệ phí %s." %
		GameState.money_text(int(Tournaments.info(&"olympic")["entry"]["fee"]))],
		["Mẹo", "Đường tới đột biến: đi học THPT (+Technology) → bàn học trong nhà đổi Biotech (10 → 1) → chuồng gà: đột biến (6–10 Biotech mỗi lần). Nhà vô địch Liên tỉnh vừa nhận 10 Biotech – đủ cho một lần đột biến rồi đó!"]])


## Kết game (GDD 9.3 Ending: thắng Olympic) – cắt cảnh + dòng cảm ơn, rồi chơi tiếp tự do.
func ending() -> void:
	var cut := Cutscene.new()
	main.add_child(cut)
	Audio.music(&"memory")
	await cut.play([
		["", "Cả nhà thi đấu Olympic đứng dậy vỗ tay. Pháo giấy bay đầy trời."],
		["Thầy Cửu", "Năm xưa ông nội con đứng chỗ đó, thua ta một trận. Hôm nay cháu ổng thắng lại. Vậy là huề nghen."],
		["Mẹ", "(Gọi điện) Con trai mẹ lên ti-vi kìa! Mà mai vẫn phải đi học đó nghen!"],
		["", "Trên bàn thờ ở nhà, nén nhang ông nội cháy đỏ. Khói bay thẳng lên, hiền hòa."],
		["", "HUYỀN THOẠI ĐÁ GÀ – %s & %s" % [GameState.player_name, GameState.chicken_name]],
		["", "Kịch bản, mã, hình, tiếng: đội Chick Fighter · Cảm ơn bạn đã chơi Huyền Thoại Đá Gà!"],
		["", "Truyền thuyết gà chín cựa vẫn còn đó… (Bạn có thể chơi tiếp tự do.)"],
	])
	LifeState.game_complete = true
	Audio.music(&"village")
	await _dialog().say([["", "Danh hiệu «Huyền Thoại Đá Gà»! Xã Bình Kê vẫn chờ bạn: đá giao hữu, nuôi thêm gà, ấp trứng, đột biến…"]])


# =================================================================== giao hữu

## Sới Ao Làng sau Act 1: MC mời đá giao hữu.
func village_pit() -> void:
	var pick: int = await _dialog().choose("MC", "Sới Ao Làng đây bà con ơi! Nhà vô địch ghé chơi hả? Đá giao hữu một keo hông?",
		["Đá giao hữu (còn %d keo hôm nay)" % maxi(SPAR_PER_DAY - LifeState.today("spar"), 0), "Thôi"])
	if pick == 0:
		await spar(&"arena")


func spar(venue_id: StringName) -> void:
	var dlg: DialogBox = _dialog()
	var who: String = "MC" if venue_id == &"arena" else String(ORGANISER.get(&"olympic" if venue_id == &"arena_olympic" else &"lien_tinh", "MC"))
	if GameState.clock_running() and GameState.period() < GameState.Period.CHIEU:
		await dlg.say([[who, "Giao hữu đá từ chiều tới khuya thôi em (13:00–22:00). Giờ đi học, đi làm đi!"]])
		return
	if LifeState.today("spar") >= SPAR_PER_DAY:
		await dlg.say([[who, "Hôm nay em đá đủ %d keo rồi. Cho gà nghỉ, mai quay lại nghen." % SPAR_PER_DAY]])
		return
	if not GameState.can_spend(GameState.TIME_BATTLE):
		await dlg.say([[who, "Khuya quá rồi, sới dẹp. Mai ghé nghen."]])
		return
	var ids: Array[String] = []
	for band in SPAR_BANDS.get(venue_id, [1, 2]):
		for id in GameState.spar_opponents(int(band)):
			if not ids.has(id):
				ids.append(id)
	if ids.is_empty():
		await dlg.say([[who, "Hôm nay hổng có ai đá giao hữu hết."]])
		return
	ids.sort_custom(func(a: String, b: String) -> bool: return int(GameState.opponent_data(a)["lv"]) < int(GameState.opponent_data(b)["lv"]))
	var options: Array = []
	var details: Array = []
	for id in ids:
		var o: Dictionary = GameState.opponent_data(id)
		options.append("%s – %s (Lv%d) · thắng %s" % [String(o["owner"]), String(o["name"]), int(o["lv"]), GameState.money_text(int(o.get("purse", 0)))])
		details.append("«%s» %s" % [String(o.get("quote", "")), String(o.get("habits", ""))])
	options.append("Thôi")
	details.append("")
	var pick: int = await dlg.choose(who, "Chọn đối thủ giao hữu (gà của em: %s Lv%d):" % [GameState.chicken_name, GameState.level], options, details)
	if pick >= ids.size():
		return
	var id: String = ids[pick]
	var side: Dictionary = GameState.opponent_side(id)
	side["id"] = id
	await dlg.say([[String(side["owner"]), String(side.get("quote", "Đá thì đá!"))]])
	var variant: Variant = {&"arena_lien_tinh": &"lien_tinh", &"arena_olympic": &"olympic"}.get(venue_id, null)
	var config: Dictionary = {"mode": "friendly", "kind": "spar", "title": "GIAO HỮU – %s" % String(side["name"]).to_upper(),
		"prize": int(side.get("purse", 0)), "police_ok": true, "escape_difficulty": clampf(0.15 + 0.15 * float(side.get("tier", 1)), 0.0, 0.8)}
	if variant != null:
		config["arena_variant"] = variant
	var res: Dictionary = await main.run_match(side, config)
	var outcome: String = String(res.get("outcome", "back"))
	if outcome == "back":
		return
	LifeState.add_today("spar")
	if outcome == "won":
		main.life.on_spar_won()
		await dlg.say([[String(side["owner"]), "Thua rồi! Gà em đá hay thiệt. Tiền xâu đây."]])
	elif outcome == "lost" or outcome == "caught":
		await dlg.say([[String(side["owner"]), "Hì, gà em còn non. Về luyện thêm rồi đá lại nghen!"]])


# =================================================================== gọi tay trong (báo công an)

## Lý do từ chối khi người chơi bấm G ("" = cho phép). Act 1 / trận không cho phép / đã dùng trong tuần.
static func police_refusal(config: Dictionary) -> String:
	if not bool(config.get("police_ok", false)) or GameState.current_act() < 2:
		return "Bạn rút điện thoại ra… Chú Tư giựt lại liền: «Giải làng mình mà báo công an chi con! Đá đàng hoàng đi!»"
	if not LifeState.police_ready():
		return "Tuần này «gọi tay trong» một lần rồi, gọi nữa người ta nghi. (Tuần sau mới gọi được.)"
	return ""


## Cảnh gọi điện thầm thì trước trận (sau khi được phép).
func police_call_scene(side: Dictionary, config: Dictionary) -> void:
	LifeState.police_week = GameState.week()
	var place: String = "sới Liên tỉnh" if String(config.get("tid", "")) == "lien_tinh" else ("nhà thi đấu Olympic" if String(config.get("tid", "")) == "olympic" else "sới gà")
	await _dialog().say([
		["", "Bạn lẻn ra sau chuồng, bấm số thật nhỏ…"],
		[GameState.player_name, "(thì thầm) Alô… dạ, ở %s… có đá gà ăn tiền lớn lắm mấy chú ơi… Dạ, tới liền nghen…" % place],
		["Tổng đài", "Rõ. Ba mươi giây nữa tổ công tác có mặt. Giữ bình tĩnh."],
		["", "Giờ chỉ cần cầm cự 30 giây trước %s của %s, rồi… chạy!" % [String(side.get("name", "?")), String(side.get("owner", "?"))]],
	])


## Sau trận "police": thắng KO = thắng thường; bị hạ = thua thường; sống sót = công an ập vào → tẩu thoát.
## Trả về như main.run_match: {outcome, won, result, league?}.
func police_after(side: Dictionary, config: Dictionary, result: Dictionary) -> Dictionary:
	if bool(result.get("won", false)):
		return await main.settle_match(side, config, true, result)
	if not bool(result.get("survived", false)):
		return await main.settle_match(side, config, false, result)
	var dlg: DialogBox = _dialog()
	await main._fade_to(0.0, 0.3)
	await dlg.say([["Chú công an", "Tuýt tuýt! Đứng yên hết! Công an đây!"], ["", "Cả sới chạy tán loạn. Bạn ôm %s lủi ra cửa sau!" % GameState.chicken_name]])
	await main._fade_to(1.0, 0.3)
	var world: Node = main.get("world")
	world.call("set_active", false)
	var esc: Dictionary = await run_escape(float(config.get("escape_difficulty", 0.5)))
	var escaped: bool = bool(esc.get("escaped", false))
	if escaped:
		Achievements.unlock(&"secret_escape")
		await run_cutscene()
		Achievements.unlock(&"secret_alibi") # cắt cảnh rửa chén ngoại phạm
	main._fade.color.a = 1.0
	world.call("set_active", true)
	Audio.music(&"village")
	Audio.ambience({&"birds": 0.5, &"village": 0.5, &"leaves": 0.3})
	if not escaped:
		var extra: Array[String] = []
		if bool(esc.get("caught", false)):
			var fine: int = mini(POLICE_FINE, GameState.money)
			GameState.money -= fine
			LifeState.fines += fine
			extra.append("Bị lập biên bản: −%s" % GameState.money_text(fine))
			await dlg.say([["Chú công an", "Nhỏ vậy mà đi đá gà ăn tiền hả? Lập biên bản! Lần sau gặp nữa là mời phụ huynh nghen!"]])
		else:
			await dlg.say([["", "Bạn đứng lại thở dốc… Thôi, coi như thua trận này."]])
		var out: Dictionary = await main.settle_match(side, config, false, result, extra)
		out["outcome"] = "caught"
		out["escape"] = esc
		return out
	# Thoát: trận bị hủy – không thắng không thua.
	LifeState.raid_day = GameState.day
	LifeState.police_uses += 1
	var rewards: Array[String] = ["Trận bị hủy: không thắng, không thua, không mất Thể trạng"]
	var tid: StringName = StringName(config.get("tid", ""))
	var opp_id: String = String(side.get("id", ""))
	if tid != &"":
		LifeState.postpone(tid, GameState.day + RAID_POSTPONE_DAYS)
		rewards.append("Giải tạm hoãn %d ngày – vòng này đá lại buổi giải kế tiếp" % RAID_POSTPONE_DAYS)
	if opp_id != "":
		LifeState.weakened[opp_id] = int(LifeState.weakened.get(opp_id, 0)) + 1
		rewards.append("%s bị phạt – gặp lại, gà %s sẽ đuối hơn" % [String(side.get("owner", "?")), String(side.get("name", "?"))])
	var screen := ResultScreen.new()
	screen.won = false
	screen.raid = true
	screen.condition_loss = 0.0
	for line in rewards:
		screen.rewards.append(line)
	screen.exp_gain = 10 + 2 * int(side.get("lv", 1))
	main.add_child(screen)
	await main._fade_to(0.0, 0.3)
	await screen.run()
	return {"outcome": "raid", "won": false, "result": result, "escape": esc}


## Mini-game tẩu thoát (escape agent). Thiếu file → coi như thoát (kèm câu dẫn). Test: main.escape_override.
func run_escape(difficulty: float) -> Dictionary:
	var override: Dictionary = main.get("escape_override")
	if not override.is_empty():
		return override.duplicate()
	if not ResourceLoader.exists(ESCAPE_GAME_PATH):
		await main._fade_to(0.0, 0.2)
		await _dialog().say([["", "Bạn ôm gà chạy thục mạng qua vườn chuối, lội qua rạch, về tới nhà an toàn."]])
		return {"escaped": true, "caught": false, "cancelled": false, "stub": true}
	var script: Script = load(ESCAPE_GAME_PATH)
	var game: Node = script.new()
	game.call("setup", {"difficulty": clampf(difficulty, 0.0, 1.0), "seed": GameState.day * 131 + LifeState.police_uses,
		"chicken": GameState.active_chicken()})
	var skill: float = float(main.get("test_escape_autopilot"))
	if skill >= 0.0:
		game.set("autopilot", true)
		game.set("autopilot_skill", skill)
	main.add_child(game)
	await main._fade_to(0.0, 0.3)
	var r: Dictionary = await game.call("run")
	await main._fade_to(1.0, 0.3)
	game.queue_free()
	return r


func run_cutscene() -> void:
	if not ResourceLoader.exists(ESCAPE_CUTSCENE_PATH):
		await main._fade_to(0.0, 0.2)
		await _dialog().say([["", "Bạn chạy vô bếp, xắn tay áo rửa chén như chưa có chuyện gì. Công an ghé hỏi, bạn chỉ tay ra bến đò: «Nó chạy hướng đó mấy chú!»"]])
		return
	var script: Script = load(ESCAPE_CUTSCENE_PATH)
	var cut: Node = script.new()
	cut.call("setup", {"chicken": GameState.active_chicken()})
	if bool(main.get("test_auto_cutscene")):
		cut.set("auto_advance", true)
	main.add_child(cut)
	main._fade.color.a = 0.0
	await cut.call("play")


# =================================================================== kết Act 1 → Act 2

## Thay cho "HẾT ACT 1 → màn tiêu đề": Mẹ mừng, cắt cảnh đêm, sáng hôm sau Chú Tư ghé nhà đưa bản đồ vẽ tay.
func act1_finale() -> void:
	var dlg: DialogBox = _dialog()
	await dlg.say([
		["Mẹ", "Mẹ nghe xóm nói hết rồi! Con trai mẹ vô địch Ao Làng! Mà mai vẫn phải đi học nghen."],
		[GameState.player_name, "Dạ, con biết mà mẹ."],
	])
	await main._fade_to(1.0, 0.8)
	var world: Node = main.get("world")
	world.call("set_active", false)
	var cut := Cutscene.new()
	main.add_child(cut)
	Audio.engine(false)
	Audio.music(&"memory")
	Audio.ambience({&"crickets": 0.6, &"river": 0.2})
	main._fade.color.a = 0.0
	await cut.play([
		["", "Đêm đó, tiếng ghe máy xa dần trên sông. %s nằm nghe dế kêu, nhớ lời ông nội." % GameState.player_name],
		["Ông nội", "Gà hay là gà biết đọc đối thủ…"],
		["", "Ao Làng chỉ là khởi đầu."],
		["", "HẾT ACT 1 – AO LÀNG"],
		["", "ACT 2 – GIẢI LIÊN TỈNH MIỀN TÂY"],
	])
	GameState.stage = GameState.Stage.ACT_END
	GameState.act = maxi(GameState.act, 2)
	GameState.end_day(false)
	await act2_morning()


## Sáng mở Act 2 (cũng chạy khi tiếp tục một save cũ đã HẾT ACT 1 mà chưa xem cảnh này).
func act2_morning() -> void:
	var dlg: DialogBox = _dialog()
	var world: Node = main.get("world")
	GameState.stage = maxi(GameState.stage, GameState.Stage.ACT_END)
	GameState.act = maxi(GameState.act, 2)
	world.call("set_active", true)
	world.get("player").position = World.SPAWN
	Audio.sfx(&"rooster_crow", -3.0)
	Audio.music(&"village")
	await main._fade_to(0.0, 0.6)
	await dlg.say([
		["", "%s · %s. Sáng sớm có tiếng gõ cửa." % [GameState.weekday_name(), GameState.time_text()]],
		["Chú Tư", "Dậy chưa nhà vô địch! Chú có cái này cho con nè."],
		["Chú Tư", "Giải Liên tỉnh miền Tây – gà khắp miệt dưới tụ về: Bến Tre, Cà Mau, Châu Đốc, Vĩnh Long, Cần Thơ. Năm vòng, đá tối Thứ Bảy với Chủ nhật."],
		["Chú Tư", "Sới nằm tuốt phía đông, qua chợ Bình Kê rồi đi xuống. Chú vẽ cái bản đồ nè – vẽ tay hơi xấu, ráng coi."],
		["", "Nhận «Bản đồ vẽ tay của Chú Tư». Bấm M để mở bản đồ lớn."],
		["Chú Tư", "Mà nói trước: gà ở đó Lv6 tới Lv10, có đồ có nghề. Con phải đi làm kiếm tiền sắm đồ, luyện gà, đi học cho mẹ vui nữa."],
		["Chú Tư", "Ban ngày con là học trò bình thường. Tối về mới là người nuôi gà. Nhớ đó!"],
		["Mẹ", "Thứ Hai tới Thứ Sáu buổi sáng là đi học ở trường THPT nghen con! Trốn học là mẹ biết liền."],
	])
	LifeState.finale_act1 = true
	LifeState.finale_day = GameState.day
	await main.life.tutorial("clock")
	await main.life.tutorial("map")
	GameState.save()
	Activities.save()
	LifeState.save()
	HomeState.save_state()
