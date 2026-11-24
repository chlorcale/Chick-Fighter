extends RefCounted

## TẦNG ĐỜI SỐNG (GDD 3.2–3.4, 6, 7.5, 9.5): trường THPT (2 tiết sáng T2–T6 + thư viện), Mẹ xét chuyên cần, giờ mở cửa
## theo buổi, hàng xóm (trò chuyện 15 phút, thân thiết mỗi ngày một lần, mốc thân thiết mở nghề/giảm giá/quà/quest/
## mẹo đối thủ), quest (mũi tên chỉ đường), báo cáo buổi sáng + "kế hoạch hôm nay", mẹo hướng dẫn một lần, và hàm ưu
## tiên chọn MỤC TIÊU (dòng ➤ + mũi tên mép màn hình) sau Act 1.
## main.gd giữ một thể hiện: life = StoryLife.new(self). Mọi hàm có hội thoại đều phải await.
## Trạng thái: game/sim/life_state.gd. Dữ liệu NPC/quest: game/story/neighbours.gd.

const LifeState := preload("res://game/sim/life_state.gd")
const Neighbours := preload("res://game/story/neighbours.gd")
const Calendar := preload("res://game/data/calendar.gd")
const Tournaments := preload("res://game/data/tournaments.gd")
const Items := preload("res://game/data/items.gd")
const Activities := preload("res://game/world/activities.gd")
const Leagues := preload("res://game/story/story_leagues.gd")

## Giờ mở cửa (buổi đầu, buổi cuối – GameState.Period) khi đồng hồ ngày chạy (Act 2+). PLACEHOLDER.
const HOURS: Dictionary = {
	&"co_ba": [0, 3], &"market_gear": [0, 2], &"market_eggs": [0, 2], &"market_food": [0, 2], &"market_chicken": [0, 2],
	&"cat_shop": [1, 4], &"site": [0, 2], &"farm": [0, 2], &"fish_house": [0, 3], &"school": [1, 2],
	&"lottery": [0, 3], &"temple": [0, 3],
}
const LIBRARY_PER_DAY: int = 2
const CHAT_MINUTES: int = 15
const ALLOWANCE_FULL: int = 100000
const ALLOWANCE_PART: int = 50000

const TUTORIALS: Dictionary = {
	"clock": "Đồng hồ góc trên bên phải: Thứ · giờ · buổi. Mỗi việc đều tốn giờ – đi học 3 giờ, một ca làm 2 giờ, một trận 1 giờ, trò chuyện 15 phút. Quá 23:00 là Mẹ kêu về ngủ, mai dậy trễ (08:00). T2–T6 buổi sáng có lớp ở THPT; giải đấu đá tối Thứ 7 và Chủ nhật.",
	"map": "Bấm M mở bản đồ lớn (có đường đi tới mục tiêu), N bật/tắt bản đồ nhỏ. Mũi tên vàng ở mép màn hình luôn chỉ việc nên làm kế tiếp – kèm khoảng cách.",
	"home": "Trong nhà: ra sân sau là chuồng gà – cho ăn Lúa mỗi ngày (bỏ đói −20% Thể trạng), gắn đồ, luyện gà, ấp trứng. Bàn học đổi Technology → Biotech. Giường: ngủ = lưu game.",
	"shop": "Đồ mua về nằm trong kho. Về nhà ra chuồng gà để gắn cho gà – hoặc thay ngay ở màn chuẩn bị trước trận. Mua sắm chỉ tốn vài phút.",
	"eggs": "Trứng mua về bỏ vô lò ấp trong nhà, kèm Biotech (đi học → Technology → đổi Biotech ở bàn học, 10 → 1). Bỏ dư Biotech thì gà con dễ có đột biến; Trứng lạ có thể nở ra Gà Đông Tảo.",
	"kho_ga": "Khô Gà: con gà nào già yếu có thể cho «về hưu» ở chuồng gà, đổi thành Khô Gà tính theo ký (gà nặng ký thì nhiều). Lão Gà Khô (xe khô gà lá chanh ở Chợ Bình Kê) mua 50.000đ/kg và bán đồ độc quyền tính bằng Khô Gà. Việc này hổng làm lại được – suy nghĩ kỹ nghen!",
	"police": "«Gọi tay trong»: trận chênh lệch quá thì ở màn chuẩn bị bấm G để báo công an. Cầm cự 30 giây tới khi công an ập vô, rồi ôm gà chạy về nhà. Bị hạ hay bị bắt = thua. Vòng giải bị hoãn, mỗi tuần chỉ gọi được một lần.",
	"jobs": "Nghề làm thêm: bốc gạch (thợ hồ, công trường), bán cơm (bà Lan), chở ghe (chú Bảy) – mở ra khi thân với hàng xóm. Mỗi nghề một ca mỗi ngày, 2 giờ; tiền công nhân hệ số tay nghề 0,5–1,3.",
	"school": "Lớp THPT: T2–T6 buổi sáng (07:00–10:00), 2 tiết = +10 Technology, trả lời đúng mỗi câu thêm +2. Thư viện trưa–chiều: 1 giờ = +4 Technology. Mẹ theo dõi chuyên cần đó nghen!",
	"league": "Giải đấu đá buổi tối: vòng 1–3 tối Thứ 7, vòng 4–5 (bán kết, chung kết) tối Chủ nhật, mỗi lần ghé đá một vòng (18:00–22:00). Thua một vòng là bị loại, tuần sau đăng ký lại. Lỡ hẹn thì vòng đó dời qua tuần sau.",
}

var main: Node


func _init(p_main: Node) -> void:
	main = p_main


func _dialog() -> DialogBox:
	return main.get("dialog") as DialogBox


func clock_on() -> bool:
	return GameState.clock_running()


## Còn trong giờ [first, last] (buổi) không. Act 1 (đồng hồ chưa chạy) luôn mở.
func open_now(hours: Array) -> bool:
	if not clock_on():
		return true
	var p: int = GameState.period()
	return p >= int(hours[0]) and p <= int(hours[1])


static func hours_text(hours: Array) -> String:
	var a: Dictionary = Calendar.PERIODS[int(hours[0])]
	var b: Dictionary = Calendar.PERIODS[int(hours[1])]
	return "%s – %s (%s–%s)" % [String(a["name"]), String(b["name"]), Calendar.clock_text_of(int(a["start"])),
		Calendar.clock_text_of(int(b["end"]))]


## Mẹo một lần cho mỗi hệ thống (lời dẫn "Mẹo").
func tutorial(id: String) -> void:
	if not TUTORIALS.has(id) or not LifeState.mark_seen(id):
		return
	await _dialog().say([["Mẹo", String(TUTORIALS[id])]])


## Điểm tương tác có giờ (tiệm, chợ, việc bờ nam): ngoài giờ → câu nhắc + giờ mở. Trả về true nếu được vào.
func gate(id: StringName, who: String = "") -> bool:
	if not HOURS.has(id) or open_now(HOURS[id]):
		return true
	var hours: Array = HOURS[id]
	var text: String = "Giờ này đóng cửa rồi. Mở cửa buổi %s – quay lại giờ đó nghen." % hours_text(hours)
	if GameState.period() > int(hours[1]):
		text = "Hết giờ rồi, dọn hàng nghỉ rồi con. Mai ghé lại buổi %s nghen." % hours_text(hours)
	await _dialog().say([[who, text]])
	return false


# =================================================================== hàng xóm

func _lines_for(id: StringName) -> String:
	var npc: Dictionary = Neighbours.info(id)
	var tiers: Array = npc.get("lines", [])
	if tiers.is_empty():
		return "…"
	var tier: int = clampi(floori(LifeState.aff(String(id)) / 2.0), 0, tiers.size() - 1)
	var pool: Array = tiers[tier]
	return String(pool[posmod(LifeState.talk_count(String(id)), pool.size())])


static func hearts(n: int) -> String:
	var full: int = clampi(n, 0, 10)
	return "♥".repeat(mini(full, 10)) + ("" if full >= 1 else "–")


## Nói chuyện với một hàng xóm (npc_*, co_ba, teo, fisher, lottery, cat).
func talk_npc(id: StringName) -> void:
	var npc: Dictionary = Neighbours.info(id)
	if npc.is_empty():
		return
	var who: String = String(npc["name"])
	if not open_now(npc.get("hours", [0, 4])):
		await _dialog().say([[who, String(npc.get("away", "…"))]])
		return
	await _gossip(id, who)
	await quest_deliver(id)
	while true:
		var options: Array = ["Trò chuyện (15 phút)"]
		var details: Array = ["Thân thiết: %s (%d). Mỗi ngày trò chuyện lần đầu được thêm thân thiết." % [
			hearts(LifeState.aff(String(id))), LifeState.aff(String(id))]]
		var actions: Array = ["chat"]
		var job: StringName = &"job_shop" if id == &"npc_ba_lan" else (&"job_boat" if id == &"npc_chu_bay" else &"")
		if job != &"" and LifeState.has(String(job)):
			options.append("Phụ bán cơm một ca (2 giờ)" if job == &"job_shop" else "Chạy ghe chở hàng một chuyến (2 giờ)")
			details.append(("70.000đ" if job == &"job_shop" else "100.000đ") + " × tay nghề 0,5–1,3. Mỗi ngày một ca." \
				+ (" (Hôm nay làm rồi.)" if Activities.is_done(job) else ""))
			actions.append("job")
		var offer: String = _pending_offer(id)
		if offer != "":
			options.append("Hỏi coi có cần giúp gì hông")
			details.append(String(Neighbours.quest_info(offer)["name"]))
			actions.append("quest")
		if LifeState.has("tip_" + String(id)) or id == &"teo":
			options.append("Hỏi chuyện đối thủ")
			details.append("Nghe kể thói quen của đối thủ kế tiếp.")
			actions.append("tip")
		options.append("Thôi")
		details.append("")
		actions.append("exit")
		var pick: int = await _dialog().choose(who, _greeting(id), options, details)
		match String(actions[pick]):
			"chat":
				await chat(id)
			"job":
				await main.call("run_activity", job)
				return
			"quest":
				await offer_quest(offer)
			"tip":
				await _dialog().say([[who, opponent_tip(next_opponent())]])
			_:
				return
		main.call("_refresh_status")
		if GameState.day_over():
			return


func _greeting(id: StringName) -> String:
	match id:
		&"npc_ba_lan":
			return "Ghé bà chơi hả con? Ăn gì chưa?"
		&"npc_chu_bay":
			return "…Ờ. Ngồi đi."
		&"npc_ong_tam":
			return "Pháo đầu! Con tới đúng lúc, ông đang thiếu người đánh."
		&"npc_ong_sau":
			return "Ngồi xuống đây con, nói nhỏ thôi kẻo cá chạy."
		&"npc_chu_muoi":
			return "Vô coi kiểng hả? Nhẹ chân thôi nghen!"
		&"teo":
			return "Ê! Tới đúng lúc, tao đang định khoe mày cái này."
		&"cat":
			return "Meo? (Con mèo ngước nhìn bạn.)"
	return "Chào con."


## Trò chuyện: 15 phút; thân thiết +1 lần đầu trong ngày; xét mốc thưởng.
func chat(id: StringName) -> void:
	var npc: Dictionary = Neighbours.info(id)
	var who: String = String(npc.get("name", ""))
	var line: String = _lines_for(id)
	var gained: bool = LifeState.chat(String(id))
	GameState.spend_time(CHAT_MINUTES)
	var lines: Array = [[who, line]]
	if gained:
		lines.append(["", "Thân thiết với %s: %s" % [who, hearts(LifeState.aff(String(id)))]])
	await _dialog().say(lines)
	await check_rewards(id)


## Mốc thân thiết (mỗi mốc một lần): nghề, giảm giá, quà, tiền, quest, mẹo đối thủ.
func check_rewards(id: StringName) -> void:
	var rewards: Dictionary = Neighbours.info(id).get("rewards", {})
	var who: String = String(Neighbours.info(id).get("name", ""))
	var keys: Array = rewards.keys()
	keys.sort()
	for n in keys:
		if LifeState.aff(String(id)) < int(n):
			continue
		var key: String = "reward:%s:%d" % [String(id), int(n)]
		if LifeState.has(key):
			continue
		LifeState.unlock(key)
		var r: Dictionary = rewards[n]
		var lines: Array = []
		if r.has("text"):
			lines.append(["", String(r["text"])])
		if r.has("job"):
			LifeState.unlock(String(r["job"]))
			lines.append(["", "Mở nghề làm thêm: %s (nói chuyện với %s)." % ["Bán cơm" if String(r["job"]) == "job_shop" else "Chở ghe", who]])
		if r.has("discount"):
			LifeState.unlock(String(r["discount"]))
		if r.has("item"):
			give_item(StringName(r["item"][0]), int(r["item"][1]))
		if r.has("money"):
			GameState.money += int(r["money"])
		if bool(r.get("tip", false)):
			LifeState.unlock("tip_" + String(id))
		if not lines.is_empty():
			await _dialog().say(lines)
		if r.has("job"):
			await tutorial("jobs")
		if r.has("quest"):
			await offer_quest(String(r["quest"]))


static func give_item(item: StringName, qty: int) -> void:
	if Items.has(item) and qty > 0:
		GameState.inventory[item] = GameState.item_count(item) + qty


func _gossip(id: StringName, who: String) -> void:
	if LifeState.raid_day <= 0 or GameState.day - LifeState.raid_day > 1 or GameState.day == LifeState.raid_day:
		return
	if LifeState.today("gossip:" + String(id)) > 0 or id == &"cat":
		return
	LifeState.add_today("gossip:" + String(id))
	var line: String = "Nghe gì chưa? Tối qua công an bố ráp sới gà, người ta chạy tán loạn! Có đứa ôm gà nhảy sông bơi về nhà, hay dữ!"
	match id:
		&"npc_ba_lan":
			line = "Trời đất ơi con nghe chưa! Tối qua công an ập vô sới, có thằng nhỏ ôm gà bơi qua rạch. Bà mà biết đứa nào là bà… cho nó chén cơm cháy!"
		&"npc_chu_bay":
			line = "…Tối qua có bố ráp. Hồi xưa cũng vậy. Người khôn thì về nhà rửa chén."
		&"npc_ong_tam":
			line = "Công an bố ráp sới gà hả? Nước cờ đó ai đi vậy ta… Hay à nghen!"
		&"teo":
			line = "Mày nghe chưa, tối qua công an bố ráp! Tao mà ở đó là tao chạy lẹ hơn ai hết. (Tèo ngó bạn nghi nghi.)"
	await _dialog().say([[who, line]])


# =================================================================== quest

## Quest của NPC đã tới mốc nhưng chưa nhận (để hỏi lại qua menu).
func _pending_offer(id: StringName) -> String:
	for qid in Neighbours.QUESTS:
		var q: Dictionary = Neighbours.QUESTS[qid]
		if StringName(q["giver"]) != id or LifeState.quest_state(qid) != LifeState.Q_NONE:
			continue
		if LifeState.has("reward:%s:%d" % [String(id), _quest_threshold(id, qid)]):
			return String(qid)
	return ""


func _quest_threshold(id: StringName, qid: String) -> int:
	var rewards: Dictionary = Neighbours.info(id).get("rewards", {})
	for n in rewards:
		if String(rewards[n].get("quest", "")) == qid:
			return int(n)
	return 999


func offer_quest(qid: String) -> void:
	var q: Dictionary = Neighbours.quest_info(qid)
	if q.is_empty() or LifeState.quest_state(qid) != LifeState.Q_NONE:
		return
	var who: String = String(Neighbours.info(StringName(q["giver"])).get("name", ""))
	var pick: int = await _dialog().choose(who, String(q["offer"]).trim_prefix(who + ": "),
		["Dạ, để con giúp!", "Để bữa khác nghen"], [String((q["steps"] as Array)[0]["text"]), ""])
	if pick != 0:
		await _dialog().say([[who, "Ờ, rảnh thì ghé nghen."]])
		return
	LifeState.start_quest(qid, Activities.total_fish if qid == "q_ca_ong_sau" else 0)
	await _dialog().say([["", "Nhận việc: «%s». Mũi tên vàng sẽ chỉ đường." % String(q["name"])]])


## Bước hiện tại của quest: {text, target}.
static func quest_step(qid: String) -> Dictionary:
	var q: Dictionary = Neighbours.quest_info(qid)
	var steps: Array = q.get("steps", [])
	var step: int = clampi(int(LifeState.quest(qid).get("step", 0)), 0, maxi(steps.size() - 1, 0))
	return steps[step] if not steps.is_empty() else {}


static func advance_quest(qid: String) -> void:
	var q: Dictionary = LifeState.quest(qid)
	q["step"] = int(q.get("step", 0)) + 1


## Giao/hoàn thành quest khi người chơi tới đúng chỗ (target của bước cuối). Trả về true nếu có hoàn thành.
func quest_deliver(target: StringName) -> bool:
	var done_any: bool = false
	for qid in LifeState.active_quests():
		var info: Dictionary = Neighbours.quest_info(qid)
		var steps: Array = info.get("steps", [])
		var step: int = int(LifeState.quest(qid).get("step", 0))
		if step != steps.size() - 1 or StringName(steps[step]["target"]) != target:
			continue
		# Bước cuối phụ thuộc điều kiện: cá phải bắt được, trận giao hữu phải thắng (đã qua bước trước nên đúng).
		await complete_quest(qid)
		done_any = true
	return done_any


func complete_quest(qid: String) -> void:
	var info: Dictionary = Neighbours.quest_info(qid)
	LifeState.finish_quest(qid)
	var r: Dictionary = info.get("reward", {})
	if r.has("money"):
		GameState.money += int(r["money"])
	if r.has("item"):
		give_item(StringName(r["item"][0]), int(r["item"][1]))
	if r.has("aff"):
		LifeState.add_aff(String(info["giver"]), int(r["aff"]))
	if qid == "q_chau_kieng":
		LifeState.add_aff("npc_ba_lan", 1)
	GameState.spend_time(GameState.TIME_QUEST if qid in ["q_com_tho_ho", "q_chau_kieng"] else 0)
	var lines: Array = (info.get("done", []) as Array).duplicate()
	lines.append(["", "Xong việc «%s». %s" % [String(info["name"]), String(r.get("text", ""))]])
	await _dialog().say(lines)
	await check_rewards(StringName(info["giver"]))


## Sau một hoạt động bờ nam: tiến độ quest cá của ông Sáu.
func after_activity(id: StringName) -> void:
	if id == &"fish_house" and LifeState.quest_state("q_ca_ong_sau") == LifeState.Q_ACTIVE \
			and int(LifeState.quest("q_ca_ong_sau")["step"]) == 0 \
			and Activities.total_fish > int(LifeState.quest("q_ca_ong_sau")["mark"]):
		advance_quest("q_ca_ong_sau")
		await _dialog().say([["", "Có cá tra rồi! Đem về cho ông Sáu ở ao sen (phía đông nam)."]])


## Thắng một trận giao hữu: quest cờ tướng của ông Tám sang bước "về kể".
func on_spar_won() -> void:
	if LifeState.quest_state("q_co_tuong") == LifeState.Q_ACTIVE and int(LifeState.quest("q_co_tuong")["step"]) == 0:
		advance_quest("q_co_tuong")


# =================================================================== trường THPT & thư viện

func thpt() -> void:
	var dlg: DialogBox = _dialog()
	await tutorial("school")
	if GameState.weekday() == 6:
		await dlg.say([["Chú bảo vệ", "Chủ nhật trường đóng cửa nghen con. Thứ Hai đi học sớm, đừng có trễ!"]])
		return
	var p: int = GameState.period()
	var class_open: bool = GameState.is_school_day() and (not clock_on() or p == GameState.Period.SANG)
	var library_open: bool = not clock_on() or p == GameState.Period.TRUA or p == GameState.Period.CHIEU
	var options: Array = []
	var details: Array = []
	var actions: Array = []
	if GameState.is_school_day():
		if Activities.is_done(&"thpt"):
			options.append("Vô lớp (hôm nay học rồi)")
			details.append("Mỗi ngày học 2 tiết buổi sáng.")
			actions.append("done")
		elif class_open:
			options.append("Vô lớp: 2 tiết (3 giờ, +10 Technology)")
			details.append("Trả lời đúng mỗi câu thêm +2 Technology. Học xong khoảng %s." % Calendar.clock_text_of(GameState.minutes + GameState.TIME_SCHOOL))
			actions.append("class")
		else:
			options.append("Vô lớp (trễ rồi – lớp chỉ học buổi Sáng)")
			details.append("Mai tới trước 10:00 nghen, Mẹ biết là la đó.")
			actions.append("late")
	if library_open:
		var left: int = LIBRARY_PER_DAY - LifeState.today("library")
		options.append("Vô thư viện (1 giờ, +4 Technology)" + ("" if left > 0 else " – đủ lượt"))
		details.append("Thư viện mở buổi Trưa – Chiều, tối đa %d lần/ngày (còn %d)." % [LIBRARY_PER_DAY, maxi(left, 0)])
		actions.append("library")
	options.append("Thôi")
	details.append("")
	actions.append("exit")
	var prompt: String = "Trường THPT Bình Kê. Bây giờ %s." % GameState.clock_text()
	if not GameState.is_school_day():
		prompt += " Thứ Bảy hổng có lớp, chỉ mở thư viện."
	var pick: int = await dlg.choose("Chú bảo vệ", prompt, options, details)
	match String(actions[pick]):
		"class":
			await main.call("run_activity", &"thpt")
		"done":
			await dlg.say([["Thầy Khoa", "Hôm nay em học rồi. Chiều ra thư viện đọc thêm cũng được."]])
		"late":
			await dlg.say([["Chú bảo vệ", "Lớp học từ 7 tới 10 giờ sáng thôi con. Trưa chiều thì vô thư viện."]])
		"library":
			await library()


func library() -> void:
	var dlg: DialogBox = _dialog()
	if LifeState.today("library") >= LIBRARY_PER_DAY:
		await dlg.say([["Cô thủ thư", "Đọc nhiều quá mỏi mắt đó em. Mai ghé tiếp nghen."]])
		return
	var done: Dictionary = GameState.perform(&"library")
	if not bool(done["ok"]):
		await dlg.say([["Cô thủ thư", String(done["reason"])]])
		return
	LifeState.add_today("library")
	var books: Array[String] = ["«Kỹ thuật nuôi gà nòi»", "«Di truyền học vui»", "«Sổ tay chăm gà đá»", "«Truyền thuyết Hùng Vương»"]
	await dlg.say([["", "Bạn đọc cuốn %s suốt một tiếng. +%d Technology (đang có %d)." % [
		books[GameState.day % books.size()], int(done["technology"]), GameState.technology]]])


# =================================================================== buổi sáng, Mẹ, kế hoạch

## Dòng thêm cho báo cáo buổi sáng (sau end_day): rửa chén phạt, Mẹ xét chuyên cần đầu tuần, nhắc trốn học,
## tin đồn bố ráp, kế hoạch hôm nay. Trả về [[người nói, câu]].
func morning_lines() -> Array:
	var out: Array = []
	if not LifeState.finale_act1:
		return out
	var day: int = GameState.day
	# Hôm qua là ngày học mà không đi.
	var yesterday: int = day - 1
	if yesterday >= LifeState.finale_day and Calendar.is_school_day(yesterday) and not LifeState.attended.has(yesterday):
		out.append(["Mẹ", "Thầy Khoa chủ nhiệm nhắn mẹ là hôm qua con hổng có đi học. Mẹ cũng là giáo viên đó nghen con, đừng để mẹ mắc cỡ!"])
	if GameState.weekday() == 0 and LifeState.mom_week < GameState.week():
		LifeState.mom_week = GameState.week()
		var first: int = (GameState.week() - 2) * 7 + 1
		var expected: int = 0
		var went: int = 0
		for d in range(first, first + 5):
			if d >= 1 and d >= LifeState.finale_day:
				expected += 1
				if LifeState.attended.has(d):
					went += 1
		if expected > 0:
			if went >= expected:
				GameState.money += ALLOWANCE_FULL
				out.append(["Mẹ", "Tuần rồi con đi học đủ %d/%d buổi. Giỏi lắm! Nè, tiền tiêu vặt %s, mua lúa cho gà." % [went, expected, GameState.money_text(ALLOWANCE_FULL)]])
			elif expected - went >= 3:
				LifeState.allowance_blocked_week = GameState.week()
				LifeState.chores_day = day
				out.append(["Mẹ", "Tuần rồi con trốn học tới %d buổi! Tuần này cắt tiền tiêu vặt, sáng nay ở nhà rửa chén một tiếng cho mẹ!" % (expected - went)])
			else:
				GameState.money += ALLOWANCE_PART
				out.append(["Mẹ", "Tuần rồi đi học %d/%d buổi, tạm được. Mẹ cho %s thôi, tuần này ráng đi đủ nghen." % [went, expected, GameState.money_text(ALLOWANCE_PART)]])
	if LifeState.chores_day == day and LifeState.today("chores") == 0:
		LifeState.add_today("chores")
		GameState.spend_time(60)
		out.append(["", "Bạn rửa một thau chén, lau nhà, quét sân… Mất một tiếng (bây giờ %s)." % GameState.time_text()])
	if LifeState.raid_day > 0 and day - LifeState.raid_day == 1:
		out.append(["Ba", "Đọc báo nè: «Bố ráp sới gà, một thanh niên ôm gà bơi qua rạch trốn mất». Ủa con, tối qua con đi đâu mà về ướt nhẹp vậy? Hì hì."])
	out.append(["", plan_line()])
	LifeState.plan_day = day
	return out


## "Kế hoạch hôm nay": thứ, việc chính theo buổi, vòng giải kế tiếp.
func plan_line() -> String:
	var parts: PackedStringArray = []
	if GameState.is_school_day():
		parts.append("sáng lên lớp THPT (07:00–10:00)")
	else:
		parts.append("nghỉ học – chợ phiên cuối tuần đông, đồ rẻ")
	parts.append("chiều làm thêm, luyện gà")
	parts.append("tối cho gà ăn")
	var line: String = "Kế hoạch %s: %s." % [GameState.weekday_name(), ", ".join(parts)]
	var league: String = league_line()
	if league != "":
		line += " " + league
	return line


## Câu về vòng giải kế tiếp ("" nếu không có).
func league_line() -> String:
	for tid in [&"lien_tinh", &"olympic"]:
		var r: int = GameState.league_round(tid)
		if r < 0:
			continue
		var wd: int = Leagues.round_weekday(tid, r)
		var days: int = Leagues.days_until_round(tid)
		var name: String = String(Tournaments.info(tid)["name"])
		if days == 0:
			return "Tối nay: %s vòng %d (18:00–22:00)!" % [name, r + 1]
		return "%s vòng %d: tối %s (còn %d ngày)." % [name, r + 1, Calendar.WEEKDAY_NAMES[wd], days]
	return ""


func talk_mom() -> void:
	var week_first: int = (GameState.week() - 1) * 7 + 1
	var went: int = 0
	for d in range(week_first, GameState.day + 1):
		if LifeState.attended.has(d):
			went += 1
	var school_days: int = mini(GameState.weekday() + 1, 5)
	var lines: Array = []
	if GameState.period() == GameState.Period.SANG and GameState.is_school_day() and not Activities.is_done(&"thpt"):
		lines.append(["Mẹ", "Giờ này còn ở nhà? Đi học lẹ lên, trễ rồi kìa!"])
	elif went >= school_days:
		lines.append(["Mẹ", "Tuần này con đi học đều (%d buổi). Mẹ mừng. Nuôi gà thì nuôi, mà học là trên hết nghen." % went])
	else:
		lines.append(["Mẹ", "Tuần này con mới đi học %d/%d buổi. Cuối tuần mẹ xét tiền tiêu vặt đó nghen." % [went, school_days]])
	if GameState.is_champion(&"lien_tinh"):
		lines.append(["Mẹ", "Con trai mẹ vô địch Liên tỉnh mà vẫn phải rửa chén nghen. Hì."])
	lines.append(["Ba", ["Con gà nhà mình hôm nay gáy hay ghê. Giống ba hồi trẻ.", "Ba nói nhỏ nghen: mẹ con khen con hoài mà hổng cho con biết đó.",
		"Tối nay ba nấu cháo gà… à không, cháo vịt. Cháo vịt! Đừng nói con gà nghe."][GameState.day % 3]])
	GameState.spend_time(CHAT_MINUTES)
	await _dialog().say(lines)


# =================================================================== đối thủ & lời khuyên

## Đối thủ kế tiếp đáng lo nhất: vòng đang đăng ký, không thì vòng 1 của giải kế tiếp. {} nếu hết.
static func next_opponent() -> Dictionary:
	for tid in [&"lien_tinh", &"olympic"]:
		if GameState.league_round(tid) >= 0:
			return GameState.next_league_opponent(tid)
	for tid in [&"lien_tinh", &"olympic"]:
		if not GameState.is_champion(tid):
			var rounds: Array = Tournaments.rounds(tid)
			return GameState.opponent_side(String(rounds[0])) if not rounds.is_empty() else {}
	return {}


## Lời khuyên về một đối thủ (thói quen "habits" trong data, không có thì suy từ tính cách/giống/vũ khí).
static func opponent_tip(side: Dictionary) -> String:
	if side.is_empty():
		return "Giờ hổng còn ai đáng gờm. Cứ đá cho vui!"
	var who: String = "%s của %s" % [String(side.get("name", "?")), String(side.get("owner", "?"))]
	var habits: String = String(side.get("habits", ""))
	if habits == "":
		var traits: PackedStringArray = []
		if float(side.get("jumpy", 0.0)) >= 0.35:
			traits.append("hay nhảy vào – đứng thẳng giữ lùi mà đỡ")
		if float(side.get("block", 0.0)) >= 0.4:
			traits.append("đỡ lì – đánh dồn cho vỡ thủ")
		if float(side.get("aggr", 0.0)) >= 0.6:
			traits.append("hung hăng – đỡ trước rồi phản")
		if int(side.get("breed", 0)) == 2:
			traits.append("Đông Tảo nặng ký, khó đẩy")
		habits = ", ".join(traits) if not traits.is_empty() else "đá đều tay, hổng có tật gì rõ"
	var lv: int = int(side.get("lv", 1))
	var gap: String = ""
	if lv - GameState.level >= 3:
		gap = " Gà nó Lv%d, của con mới Lv%d – đi làm sắm đồ, luyện thêm đi đã." % [lv, GameState.level]
	return "Con %s: %s.%s" % [who, habits, gap]


# =================================================================== mục tiêu (sau Act 1)

## Nơi làm thêm nên tới: còn ca bốc gạch → công trường; đã thân bà Lan/chú Bảy → quán của họ.
static func job_target() -> StringName:
	if LifeState.has("job_boat") and not Activities.is_done(&"job_boat"):
		return &"npc_chu_bay"
	if LifeState.has("job_shop") and not Activities.is_done(&"job_shop"):
		return &"npc_ba_lan"
	if not Activities.is_done(&"site"):
		return &"site"
	return &"npc_ba_lan"


## [câu mục tiêu, id mục tiêu] theo thứ tự ưu tiên: khuya → gà đói/yếu → giải tối nay → đi học → quest → tiến trình
## giải (đủ sức chưa, đủ tiền chưa) → gợi ý theo buổi.
func objective() -> Array:
	var head: String = "%s · %s: " % [GameState.weekday_name(), GameState.period_name()]
	var m: int = GameState.minutes
	var c: Dictionary = GameState.active_chicken()
	var p: int = GameState.period()
	if clock_on() and m >= 22 * 60:
		return [head + "khuya rồi – về nhà ngủ (tự lưu game)", &"home"]
	if p >= GameState.Period.TOI and not bool(c["fed_today"]):
		if GameState.item_count(&"lua") > 0 or GameState.item_count(&"pate_meo") > 0:
			return [head + "%s chưa ăn bữa chính – về nhà cho ăn" % String(c["name"]), &"home"]
		return [head + "%s chưa ăn – ghé Cô Ba mua Lúa rồi về nhà cho ăn" % String(c["name"]), &"co_ba"]
	if float(c["condition"]) < GameState.CONDITION_WEAK:
		return [head + "%s yếu (Thể trạng %d%%) – về nhà cho ăn, nghỉ ngơi" % [String(c["name"]), int(c["condition"])], &"home"]
	for tid in [&"lien_tinh", &"olympic"]:
		var r: int = GameState.league_round(tid)
		if r >= 0 and Leagues.days_until_round(tid) == 0 and p >= GameState.Period.CHIEU:
			return [head + "tối nay %s vòng %d (18:00–22:00)" % [String(Tournaments.info(tid)["name"]), r + 1], Leagues.VENUE[tid]]
	if GameState.is_school_day() and p == GameState.Period.SANG and not Activities.is_done(&"thpt") and m <= 9 * 60 + 30:
		return [head + "lên lớp ở trường THPT", &"thpt"]
	var quests: Array[String] = LifeState.active_quests()
	if not quests.is_empty():
		var step: Dictionary = quest_step(quests[0])
		return [head + String(step.get("text", "")), StringName(step.get("target", &""))]
	if LifeState.game_complete:
		return [head + "Huyền Thoại Đá Gà! Tự do khám phá, đá giao hữu, nuôi thêm gà", &""]
	for tid in [&"lien_tinh", &"olympic"]:
		if GameState.is_champion(tid):
			continue
		var name: String = String(Tournaments.info(tid)["name"])
		var venue: StringName = Leagues.VENUE[tid]
		if tid == &"olympic" and (GameState.active_chicken()["mutations"] as Array).size() < 3:
			var muts: int = (GameState.active_chicken()["mutations"] as Array).size()
			if GameState.biotech >= 6:
				return [head + "Olympic cần gà 3 đột biến (đang %d) – về nhà, bàn học/chuồng gà để đột biến" % muts, &"home"]
			return [head + "Olympic cần gà 3 đột biến (đang %d): đi học → Technology → Biotech → đột biến" % muts,
				&"thpt" if GameState.is_school_day() else &"home"]
		var r2: int = GameState.league_round(tid)
		if r2 >= 0:
			var days: int = Leagues.days_until_round(tid)
			return [head + "%s vòng %d tối %s (còn %d ngày) – trong lúc chờ: làm thêm, luyện gà" % [name, r2 + 1,
				Calendar.WEEKDAY_NAMES[Leagues.round_weekday(tid, r2)], days], job_target() if p <= GameState.Period.CHIEU else &"home"]
		var check: Dictionary = GameState.can_enter(tid)
		if bool(check["ok"]):
			var first: Dictionary = GameState.opponent_side(String(Tournaments.rounds(tid)[0]))
			if int(first.get("lv", 1)) - GameState.level >= 3 and p <= GameState.Period.CHIEU:
				return [head + "gà còn yếu (Lv%d, đối thủ Lv%d+) – đi làm kiếm tiền sắm đồ, luyện gà" % [GameState.level, int(first["lv"])], job_target()]
			return [head + "đăng ký %s (đá tối T7, CN)" % name, venue]
		var reasons: String = " ".join(check["reasons"])
		if reasons.contains("Bị loại"):
			return [head + "bị loại tuần này – đi làm, luyện gà, tuần sau đăng ký lại", job_target()]
		if reasons.contains("lệ phí"):
			return [head + "cần %s lệ phí %s – đi làm thêm" % [GameState.money_text(int(Tournaments.info(tid)["entry"]["fee"])), name], job_target()]
		break
	match p:
		GameState.Period.SANG, GameState.Period.TRUA:
			return [head + "đi chợ, trò chuyện hàng xóm, nhận việc giúp", &"market"]
		GameState.Period.CHIEU:
			return [head + "đi làm thêm kiếm tiền, hoặc về nhà luyện gà", job_target()]
		GameState.Period.TOI:
			return [head + "về nhà cho gà ăn, gắn đồ, luyện gà", &"home"]
	return [head + "về nhà ngủ (tự lưu game)", &"home"]


## Câu nhắc [E] theo ngữ cảnh cho World.label_overrides.
func label_overrides() -> Dictionary:
	var out: Dictionary = {}
	if GameState.is_school_day() and (not clock_on() or GameState.period() == GameState.Period.SANG) and not Activities.is_done(&"thpt"):
		out[&"thpt"] = "Vô lớp – %s sáng (2 tiết, +10 Technology)" % GameState.weekday_name()
	else:
		out[&"thpt"] = "Trường THPT Bình Kê – thư viện (trưa, chiều)"
	for tid in [&"lien_tinh", &"olympic"]:
		var venue: StringName = Leagues.VENUE[tid]
		var r: int = GameState.league_round(tid)
		if r >= 0 and Leagues.days_until_round(tid) == 0:
			out[venue] = "%s – vòng %d tối nay" % [String(Tournaments.info(tid)["name"]), r + 1]
	if LifeState.has("job_shop"):
		out[&"npc_ba_lan"] = "Bà Lan bán cơm – trò chuyện, phụ bán (2 giờ)"
	if LifeState.has("job_boat"):
		out[&"npc_chu_bay"] = "Chú Bảy quán võng – trò chuyện, chở ghe (2 giờ)"
	out[&"cat_shop"] = "Lão Gà Khô – khô gà lá chanh · bán Khô Gà, đồ độc quyền"
	return out
