extends Node

## Điểm vào của game: Tiêu đề → Hồi ức → Khám phá ↔ Hội thoại ↔ Pre-battle ↔ Trận ↔ Kết quả.
## Cốt truyện Act 1 – Ao Làng theo GDD v1.2: 8.3 (5 trận), 8.4 (nhịp dạy), 9.1–9.5 (bối cảnh, nhân vật,
## thoại Nam Bộ), 7.2 (thưởng), Bảng 8.1 (nhà = ngủ/lưu game).

const S := GameState.Stage
const Activities := preload("res://game/world/activities.gd")
const ActivityRunner := preload("res://game/world/activity_runner.gd")
const Audio := preload("res://game/audio/audio_director.gd")
const RaceGame := preload("res://game/world/race/race_game.gd")
const RaceRiders := preload("res://game/world/race/race_riders.gd")

var world: World
var dialog: DialogBox
## Điều phối hoạt động bờ nam (con của world). Tín hiệu activity_started/finished/fx cho âm thanh.
var activities: Node
## Cuộc đua xe bí mật đang chạy (null nếu không có; test đọc để bật autopilot).
var race: Node = null
var _fade: ColorRect
var _busy: bool = false
var _battle_seed: int = 20261111
var _last_money: int = -1
var _last_level: int = -1


func _ready() -> void:
	# Font chung cho mọi Control không tự đặt font (xem DialogBox.make_font, thư mục game/fonts/).
	ThemeDB.fallback_font = DialogBox.make_font()
	add_child(Audio.new()) # nhạc nền + âm thanh môi trường (game/audio/audio_director.gd)
	dialog = DialogBox.new()
	add_child(dialog)
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 90
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)
	_title_loop()


func _fade_to(alpha: float, seconds: float = 0.35) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, seconds)
	await tween.finished


# =================================================================== tiêu đề & mở đầu

func _title_loop() -> void:
	if world != null:
		world.queue_free()
		world = null
	var title := TitleScreen.new()
	add_child(title)
	Audio.engine(false)
	Audio.music(&"title")
	Audio.ambience({&"river": 0.25, &"crickets": 0.2})
	await _fade_to(0.0, 0.8)
	var choice: String = await title.run()
	await _fade_to(1.0)
	title.queue_free()
	match choice:
		"quit":
			get_tree().quit()
			return
		"continue":
			GameState.load_save()
			Activities.load_save()
			_spawn_world()
			await _fade_to(0.0)
			await dialog.say([["", "Đã tải lại tiến trình. Chào mừng trở lại xã Bình Kê, %s!" % GameState.player_name]])
		_:
			GameState.reset()
			Activities.reset()
			await _new_game()


func _new_game() -> void:
	_fade.color.a = 1.0
	GameState.player_name = await dialog.ask_name("", "Tên của bạn là gì? (mặc định: Tư Gà)", "Tư Gà")
	var cut := Cutscene.new()
	add_child(cut)
	Audio.music(&"memory")
	Audio.ambience({&"crickets": 0.5, &"leaves": 0.2})
	await cut.play([
		["", "Xã Bình Kê, miền Tây Nam Bộ. Mười năm trước…"],
		["", "Một buổi chiều, ông nội dắt thằng cháu bảy tuổi ra sân đình coi đá gà."],
		["Ông nội", "Coi kỹ nghen con. Gà hay là gà biết đọc đối thủ: lúc nào tới, lúc nào lui."],
		["Ông nội", "Hồi xưa vua Hùng kén rể, đòi voi chín ngà, gà chín cựa, ngựa chín hồng mao. Con gà chín cựa đó… là huyền thoại."],
		["", "Mười năm sau."],
	])
	_spawn_world()
	Audio.sfx(&"rooster_crow", -4.0) # gà gáy sáng
	await _fade_to(0.0, 0.6)
	await dialog.say([
		["Mẹ", "%s ơi, dậy chưa con? Ăn sáng rồi ra sân đình kiếm chú Tư đi con. Chú dặn hoài à, nhớ về sớm nghen." % GameState.player_name],
		[GameState.player_name, "Dạ, con đi liền!"],
	])
	GameState.stage = S.GO_CHU_TU
	_refresh_status()


func _spawn_world() -> void:
	world = World.new()
	add_child(world)
	world.interact_requested.connect(_on_interact)
	world.race_challenge.connect(_on_race_challenge)
	activities = ActivityRunner.new()
	activities.name = "Activities"
	world.add_child(activities)
	activities.setup(world, dialog)
	activities.connect("fx", _on_activity_fx)
	activities.connect("activity_started", _on_activity_started)
	Audio.music(&"village")
	_last_money = GameState.money
	_last_level = GameState.level
	_refresh_status()


# =================================================================== tương tác

func _on_interact(id: StringName) -> void:
	if _busy:
		return
	_busy = true
	world.player.can_move = false
	match id:
		&"home":
			await _talk_home()
		&"chu_tu":
			await _talk_chu_tu()
		&"teo":
			await _talk_teo()
		&"co_ba":
			await _talk_co_ba()
		&"arena":
			await _enter_arena()
		&"cat":
			await dialog.say([["", "Con mèo tam thể liếc nhìn bạn rồi ngáp dài. Nghe nói ở chợ có người bán Khô Gà cho mèo…"]])
		&"fisher":
			await dialog.say([["Ông câu cá", "Câu cả buổi chưa được con nào. Mà nghe nói giải Ao Làng năm nay có thằng Tèo, gà nó lẹ lắm à nghen."]])
		&"ferry_north", &"ferry_south":
			await _ferry(id == &"ferry_north")
		&"lottery", &"school", &"site", &"farm", &"temple", &"fish_house":
			# Hoạt động bờ nam: game/world/activity_runner.gd + game/world/minigames/.
			await activities.run(id)
	if world != null:
		_refresh_status()
		world.player.can_move = true
	_busy = false


func _ferry(to_south: bool) -> void:
	var line: String = "Qua sông hông con? Lên đò đi, chú chở qua liền." if to_south else "Về xóm hả? Lên đò!"
	var pick: int = await dialog.choose("Chú lái đò", line, ["Lên đò", "Thôi"])
	if pick != 0:
		return
	await world.ride_ferry(to_south)


# =================================================================== đua xe bí mật

## World phát race_challenge khi người chơi chạy xe vượt mặt một xe NPC: tay lái bóp kèn, thách đua.
func _on_race_challenge(node_name: String) -> void:
	if _busy or world == null or not world.player.can_move:
		return
	_busy = true
	world.player.can_move = false
	var rider: Dictionary = RaceRiders.get_rider(node_name)
	Audio.sfx(&"bike_horn", -2.0)
	var pick: int = await dialog.choose(String(rider["name"]), String(rider["challenge"]),
		["Đua thì đua! Sợ gì!", "Thôi, con hổng đua đâu"],
		["Đua tới cổng ấp. Thắng ván đầu trong ngày được bao cà phê %s." % GameState.money_text(Activities.RACE_PRIZE), ""])
	if pick == 0:
		await _run_race(node_name, rider)
	else:
		await dialog.say([[String(rider["name"]), String(rider["decline"])]])
	if world != null:
		world.start_race_cooldown()
		_refresh_status()
		world.player.can_move = true
	_busy = false


func _run_race(_node_name: String, rider: Dictionary) -> void:
	Audio.music(&"", 0.4)
	await _fade_to(1.0, 0.3)
	world.set_active(false)
	_battle_seed += 1
	var game: Node = RaceGame.new()
	game.call("setup", rider, world.map_view, _battle_seed)
	add_child(game)
	race = game
	await _fade_to(0.0, 0.3)
	var result: Dictionary = await game.call("run")
	await _fade_to(1.0, 0.3)
	race = null
	game.queue_free()
	Audio.engine(false)
	world.set_active(true)
	Audio.music(&"village")
	await _fade_to(0.0, 0.3)
	var who: String = String(rider["name"])
	if bool(result.get("cancelled", false)):
		await dialog.say([[who, "Bỏ ngang hả? Vậy là chịu thua rồi nghen! Hahaha!"]])
		return
	var won: bool = bool(result.get("won", false))
	var record: Dictionary = Activities.record_race(won)
	var lines: Array = [[who, String(rider["win"] if won else rider["lose"])]]
	if won:
		if bool(record["first_today"]):
			lines.append(["", "%s bao cà phê: nhận %s." % [who, Activities.reward_text(record["reward"])]])
		else:
			lines.append(["", "Hôm nay ăn cà phê rồi, đua lại cho vui thôi nghen."])
		if bool(record["title_new"]):
			lines.append(["", "Bí mật mở khóa: danh hiệu «%s»! Cả xóm bắt đầu đồn về thằng nhỏ chạy xe Dream." % Activities.RACE_TITLE])
		lines.append(["", "Số lần thắng đua xe đường làng: %d." % int(record["wins"])])
	else:
		lines.append(["", "Gặp xe khác trên đường làng thì vượt mặt để đua lại nghen."])
	await dialog.say(lines)


func _refresh_status() -> void:
	if world == null:
		return
	# Tiếng xu khi có thêm tiền, tiếng lên cấp khi gà lên cấp.
	if _last_money >= 0 and GameState.money > _last_money:
		Audio.sfx(&"coin", -3.0)
	if _last_level >= 0 and GameState.level > _last_level:
		Audio.sfx(&"levelup", -2.0)
	_last_money = GameState.money
	_last_level = GameState.level
	var objective: String = ""
	var target: StringName = &""
	match GameState.stage:
		S.PROLOGUE, S.GO_CHU_TU:
			objective = "Ra sân đình (đi về phía đông) gặp Chú Tư"
			target = &"chu_tu"
		S.TUTORIAL:
			objective = "Đấu tập với gà của Chú Tư"
			target = &"chu_tu"
		S.FRIENDLY:
			objective = "Gặp Tèo ở sới Ao Làng, đá giao hữu"
			target = &"teo"
		S.PREPARE:
			if not GameState.owns_mao_sat and not GameState.owns_dao_chan:
				objective = "Mua đồ ở tiệm Cô Ba, rồi đăng ký giải với Chú Tư"
				target = &"co_ba"
			else:
				objective = "Đăng ký giải Ao Làng với Chú Tư"
				target = &"chu_tu"
		S.ROUND_1:
			objective = "Giải Ao Làng – Vòng 1: vào sới đấu"
			target = &"arena"
		S.ROUND_2:
			objective = "Giải Ao Làng – Vòng 2: vào sới đấu"
			target = &"arena"
		S.FINAL:
			objective = "Giải Ao Làng – Chung kết: vào sới đấu"
			target = &"arena"
		S.CHAMPION:
			objective = "Vô địch Ao Làng! Về nhà báo tin cho mẹ"
			target = &"home"
		S.ACT_END:
			objective = "Hết Act 1"
	var status: String = "%s · %s" % [GameState.player_name, GameState.money_text(GameState.money)]
	if GameState.stage >= S.TUTORIAL:
		status += " · %s Lv%d" % [GameState.chicken_name, GameState.level]
	world.set_status(status, objective, target)


func _talk_home() -> void:
	match GameState.stage:
		S.PROLOGUE, S.GO_CHU_TU:
			await dialog.say([["Mẹ", "Chú Tư ở sân đình đó con, cứ đi dọc đường làng về phía đông là tới."]])
			return
		S.CHAMPION:
			await _ending()
			return
	var pick: int = await dialog.choose("Mẹ", "Về rồi hả con? Mệt thì đi ngủ một giấc.", ["Đi ngủ (lưu game)", "Thôi, con đi tiếp"],
		["Sang ngày mới: các việc làm thêm ở bờ nam mở lại, vé số được dò.", ""])
	if pick == 0:
		Audio.music(&"", 0.8)
		Audio.ambience({&"crickets": 0.7}, 0.6)
		await _fade_to(1.0, 0.5)
		Activities.new_day()
		GameState.save()
		Activities.save()
		await get_tree().create_timer(1.2).timeout
		Audio.sfx(&"rooster_crow", -3.0)
		Audio.music(&"village")
		await _fade_to(0.0, 0.5)
		await dialog.say([["", "Một ngày mới ở xã Bình Kê (ngày %d). Đã lưu game." % Activities.day]])


func _talk_chu_tu() -> void:
	match GameState.stage:
		S.PROLOGUE, S.GO_CHU_TU:
			await dialog.say([
				["Chú Tư", "Ủa, cháu nội ông Hai đây mà! Lớn dữ rồi ha. Hồi đó ông nội bây với chú mê đá gà nhứt xóm."],
				["Chú Tư", "Chú có hứa với ổng: thằng nhỏ lớn lên thì chú giao cho nó một con chiến kê. Nè, con gà nòi này chú nuôi kỹ lắm."],
				["", "Bạn nhận được một con Gà nòi! (HP 100 · ATK 10 · DEF 2 · tốc độ 200)"],
			])
			GameState.chicken_name = await dialog.ask_name("Chú Tư", "Đặt tên cho nó đi con. Chú hay kêu nó là Ô Mun.", "Ô Mun")
			GameState.stage = S.TUTORIAL
			await dialog.say([
				["Chú Tư", "%s hả? Được, nghe cũng oai." % GameState.chicken_name],
				["Chú Tư", "Lại đây chú chỉ cho. Đá gà mà hông biết đỡ là ăn đòn sưng mỏ đó nghen!"],
				["Chú Tư", "J mổ nhanh, K tát cánh, L đá mạnh, H là tuyệt chiêu. Tạm dừng (Esc) là coi được bảng chiêu."],
			])
			await _tutorial()
		S.TUTORIAL:
			await dialog.say([["Chú Tư", "Tập lại nghen con. Từ từ mà làm, gà của chú hiền lắm."]])
			await _tutorial()
		S.FRIENDLY:
			await dialog.say([["Chú Tư", "Thằng Tèo đang khoe gà ở sới Ao Làng kìa, phía dưới đường làng đó. Ra đá giao hữu với nó một trận đi."]])
		S.PREPARE:
			if not GameState.owns_mao_sat and not GameState.owns_dao_chan:
				await dialog.say([["Chú Tư", "Trước khi đăng ký, ghé tiệm Cô Ba sắm đồ cho con gà. Tiền thắng Tèo đủ mua một món đó."]])
			var pick: int = await dialog.choose("Chú Tư",
				"Giải Ao Làng ba vòng: Lửa Đỏ của Út Mập, con Đông Tảo Mun Sông của Bảy Ghe, rồi chung kết. Mỗi trận ba hiệp, thắng hai hiệp là ăn. Thua vòng nào đá lại vòng đó. Đăng ký hông?",
				["Dạ, con đăng ký!", "Để con chuẩn bị thêm."])
			if pick == 0:
				GameState.stage = S.ROUND_1
				await dialog.say([["Chú Tư", "Được! Vô sới đi con. Nhớ: J nối J nối K nối L thành chuỗi; đủ nộ thì H, bấm H liên tục cho nó tới tấp."]])
		S.ROUND_1, S.ROUND_2, S.FINAL:
			await dialog.say([["Chú Tư", "Bình tĩnh mà đá. Đối thủ hay đỡ thì đánh liên tục cho nó vỡ thủ; đối thủ hay nhảy thì đứng đỡ thẳng lưng."]])
		S.CHAMPION, S.ACT_END:
			await dialog.say([
				["Chú Tư", "Được lắm con! Ông nội bây mà còn chắc mừng dữ lắm."],
				["Chú Tư", "Giải Liên tỉnh miền Tây còn ở phía trước. Bữa nào sẵn sàng thì chú dẫn đi."],
			])


func _tutorial() -> void:
	var result: int = await _run_battle("chu_tu", &"tutorial", "ĐẤU TẬP VỚI CHÚ TƯ", 0)
	if result == 1:
		GameState.stage = S.FRIENDLY
		GameState.cards = [&"cuong_no", &"mai_rua"]
		await dialog.say([
			["Chú Tư", "Khá đó! Có khiếu giống ông nội bây."],
			["Chú Tư", "Nè, cầm hai lá bài này: Cuồng Nộ tăng sức đá, Mai Rùa chịu đòn. Vô trận nhấn U/I chọn thẻ, O để tung. Mỗi lá tốn Card Gauge."],
			["", "Nhận thẻ Cuồng Nộ và Mai Rùa!"],
			["Chú Tư", "Thằng Tèo nó khoe gà suốt ngày ngoài sới Ao Làng. Ra thử sức với nó coi."],
		])
	else:
		await dialog.say([["Chú Tư", "Hông sao, thua keo này bày keo khác. Nói chuyện với chú để tập lại nghen."]])


func _talk_teo() -> void:
	match GameState.stage:
		S.PROLOGUE, S.GO_CHU_TU, S.TUTORIAL:
			await dialog.say([["Tèo", "Chưa có gà mà cũng lảng vảng ở sới hả? Kiếm chú Tư đi rồi tính."]])
		S.FRIENDLY:
			await dialog.say([["Tèo", "Ủa, mày cũng nuôi gà hả? Con Tia Chớp của tao lẹ dữ lắm à nha, coi chừng chóng mặt! Đá ba hiệp, thắng hai nghen."]])
			var result: int = await _run_battle("teo_1", &"friendly", "GIAO HỮU – TIA CHỚP", 50000)
			if result == 1:
				GameState.cards.append(&"gio_song")
				GameState.stage = S.PREPARE
				await dialog.say([
					["Tèo", "Trời đất, thua thiệt hả? Bữa nào tao tập lại rồi gặp mày ở chung kết, chờ đó!"],
					["", "Nhận thẻ Gió Sông: Heavy đẩy lùi thêm 50% trong 6 giây – đẩy đối thủ vào góc!"],
					["", "Tiệm tạp hóa Cô Ba bán đồ cho chiến kê. Sắm đồ xong thì đăng ký giải với Chú Tư."],
				])
			elif result == 0:
				await dialog.say([["Tèo", "Thấy chưa! Muốn phục thù thì cứ lại đây."]])
		S.CHAMPION, S.ACT_END:
			await dialog.say([["Tèo", "Rồi rồi, mày vô địch. Nhưng lên Liên tỉnh tao hổng nhường đâu nghen!"]])
		_:
			await dialog.say([["Tèo", "Tao luyện con Tia Chớp kỹ lắm rồi, còn mua thêm Dao chân. Hẹn mày ở chung kết!"]])


func _talk_co_ba() -> void:
	if GameState.stage < S.PREPARE:
		await dialog.say([["Cô Ba", "Chưa có giải mà mua đồ chi con. Chừng nào chú Tư cho đá giải rồi ghé cô nghen."]])
		return
	await dialog.say([["Cô Ba", "Vô đây con! Đồ cho chiến kê cô có đủ, giá phải chăng."]])
	while true:
		# Dòng lựa chọn: tên + giá; mô tả món đang chọn hiện ở dưới câu hỏi.
		var options: Array = []
		var details: Array = []
		var actions: Array = []
		if not GameState.owns_mao_sat:
			options.append("Mào sắt · %s" % GameState.money_text(GameState.PRICE_MAO_SAT))
			details.append("Slot Đầu: +2 DEF, giảm 20% đẩy lùi khi trúng đòn cao.")
			actions.append("mao_sat")
		if not GameState.owns_dao_chan:
			options.append("Dao chân · %s" % GameState.money_text(GameState.PRICE_DAO_CHAN))
			details.append("Light ra nhanh hơn, combo thêm 1 Light; Heavy −10% đẩy lùi.")
			actions.append("dao_chan")
		options.append("Cám tăng lực · %s" % GameState.money_text(GameState.PRICE_CAM))
		details.append("Cho gà ăn liền: +%d EXP." % GameState.CAM_EXP)
		actions.append("cam")
		options.append("Thôi, con cảm ơn cô.")
		details.append("")
		actions.append("exit")
		var picked: int = await dialog.choose("Cô Ba", "Con đang có %s. Mua gì nè?" % GameState.money_text(GameState.money), options, details)
		var action: String = actions[picked]
		if action == "exit":
			return
		var price: int = {"mao_sat": GameState.PRICE_MAO_SAT, "dao_chan": GameState.PRICE_DAO_CHAN, "cam": GameState.PRICE_CAM}[action]
		if GameState.money < price:
			await dialog.say([["Cô Ba", "Thiếu tiền rồi con ơi. Thắng thêm vài trận rồi quay lại nghen."]])
			continue
		GameState.money -= price
		match action:
			"mao_sat":
				GameState.owns_mao_sat = true
				GameState.equip_mao_sat = true
				await dialog.say([["Cô Ba", "Mào sắt đây. Gắn vô là con gà ngó oai liền hà!"]])
			"dao_chan":
				GameState.owns_dao_chan = true
				GameState.equip_dao_chan = true
				await dialog.say([["Cô Ba", "Dao chân bén lắm, ra đòn lẹ hơn hẳn. Đá cho đàng hoàng nghen con."]])
			"cam":
				var levels: int = GameState.add_exp(GameState.CAM_EXP)
				var extra: String = " %s lên cấp %d!" % [GameState.chicken_name, GameState.level] if levels > 0 else ""
				await dialog.say([["", "%s ăn cám ngon lành. +%d EXP.%s" % [GameState.chicken_name, GameState.CAM_EXP, extra]]])
		_refresh_status()


func _enter_arena() -> void:
	match GameState.stage:
		S.ROUND_1:
			await dialog.say([
				["MC", "Bà con ơi! Giải Ao Làng chính thức khai mạc! Vòng một: %s gặp Lửa Đỏ của Út Mập!" % GameState.chicken_name],
				["Út Mập", "Con Lửa Đỏ nhà tui nhảy dữ lắm đó nghen. Coi chừng trên đầu!"],
			])
			await _tournament_match("ut_map", "VÒNG 1 – LỬA ĐỎ", S.ROUND_2, 50000,
				"Đối thủ hay nhảy vào: đứng thẳng giữ lùi để đỡ đòn trên không (đỡ cúi sẽ trúng!).")
		S.ROUND_2:
			await dialog.say([
				["MC", "Vòng hai! Mun Sông của anh Bảy Ghe – con gà Đông Tảo chân to như cột đình, lì đòn nhứt xóm!"],
				["Bảy Ghe", "…Đá đi."],
			])
			await _tournament_match("bay_ghe", "VÒNG 2 – MUN SÔNG", S.FINAL, 50000,
				"Mun Sông là gà Đông Tảo: chậm, hổng nhảy được mà lì lắm. Đánh dồn cho nó vỡ thủ; thấy nó nhún lên dậm đất hay bay lên thì nhảy né; nó húc tới mà mình đỡ được thì phản công liền.")
		S.FINAL:
			await dialog.say([
				["MC", "CHUNG KẾT! Tia Chớp của Tèo – lẹ nhứt Ao Làng, nay gắn Dao chân – gặp %s!" % GameState.chicken_name],
				["Tèo", "Tao nói rồi mà, gặp nhau ở chung kết! Lần này mày hết đường chạy!"],
			])
			await _tournament_match("teo_2", "CHUNG KẾT – TIA CHỚP", S.CHAMPION, 300000,
				"Dùng Gió Sông + Heavy dồn Tèo vào góc. Tia Chớp học thói quen lẹ lắm: đừng nhảy vô hoài, đổi qua đánh thấp; nó dẫn điểm là nó né, phải rượt theo.")
		S.CHAMPION, S.ACT_END:
			await dialog.say([["MC", "Nhà vô địch Ao Làng đây rồi bà con ơi! Vỗ tay!"]])
		_:
			await dialog.say([["MC", "Sới đấu Ao Làng đây bà con ơi! Muốn thi đấu thì đăng ký với Chú Tư nghen."]])


func _tournament_match(opponent_id: String, title: String, next_stage: int, prize: int, tip: String) -> void:
	await dialog.say([["Chú Tư", tip]])
	while true:
		var result: int = await _run_battle(opponent_id, &"normal", title, prize)
		if result == 1:
			GameState.wins += 1
			GameState.stage = next_stage
			if next_stage == S.CHAMPION:
				await _champion()
			else:
				await dialog.say([["MC", "Thắng rồi bà con ơi! %s vô vòng trong!" % GameState.chicken_name]])
			return
		if result == -1:
			return
		var pick: int = await dialog.choose("MC", "Thua rồi! Giải cho đấu lại ngay vòng này.", ["Đấu lại ngay", "Để sau (đi chuẩn bị thêm)"])
		if pick == 1:
			return


func _champion() -> void:
	var bonus: String = ""
	if not GameState.owns_mao_sat:
		GameState.owns_mao_sat = true
		bonus = "Mào sắt"
	elif not GameState.owns_dao_chan:
		GameState.owns_dao_chan = true
		bonus = "Dao chân"
	var lines: Array = [
		["MC", "Và nhà vô địch giải Ao Làng năm nay là… %s cùng chiến kê %s!" % [GameState.player_name, GameState.chicken_name]],
		["", "Nhận 300.000đ tiền thưởng vô địch." + (" Ban tổ chức tặng thêm %s." % bonus if bonus != "" else "")],
		["Tèo", "Hừ… lần này mày hên thôi. Mà công nhận con %s đá hay thiệt." % GameState.chicken_name],
		["Chú Tư", "Được lắm con! Ông nội bây mà còn chắc mừng dữ lắm."],
	]
	await dialog.say(lines)
	_refresh_status()


func _ending() -> void:
	await dialog.say([
		["Mẹ", "Mẹ nghe xóm nói hết rồi! Con trai mẹ vô địch Ao Làng! Mà mai vẫn phải đi học nghen."],
		[GameState.player_name, "Dạ, con biết mà mẹ."],
	])
	await _fade_to(1.0, 0.8)
	var cut := Cutscene.new()
	add_child(cut)
	world.set_active(false)
	Audio.engine(false)
	Audio.music(&"memory")
	Audio.ambience({&"crickets": 0.6, &"river": 0.2})
	_fade.color.a = 0.0
	await cut.play([
		["", "Đêm đó, tiếng ghe máy xa dần trên sông. %s nằm nghe dế kêu, nhớ lời ông nội." % GameState.player_name],
		["Ông nội", "Gà hay là gà biết đọc đối thủ…"],
		["", "Ao Làng chỉ là khởi đầu. Phía trước là giải Liên tỉnh miền Tây, lễ hội đền Vua Hùng, và truyền thuyết Gà Chín Cựa."],
		["", "HẾT ACT 1 – AO LÀNG"],
		["", "Cảm ơn bạn đã chơi Huyền Thoại Đá Gà – Chick Fighter!"],
	])
	GameState.stage = S.ACT_END
	GameState.save()
	Activities.save()
	_busy = false
	await _fade_to(1.0, 0.1)
	_title_loop()


# =================================================================== trận đấu

## Trả về 1 thắng, 0 thua, -1 quay lại từ Pre-battle.
func _run_battle(opponent_id: String, mode: StringName, title: String, prize: int) -> int:
	var opponent: Dictionary = GameState.OPPONENTS[opponent_id].duplicate(true)
	if mode != &"tutorial":
		var pre := PreBattle.new()
		pre.opponent = opponent
		pre.title = title
		add_child(pre)
		var go: bool = await pre.run()
		pre.queue_free()
		if not go:
			return -1

	Audio.music(&"", 0.4)
	await _fade_to(1.0, 0.3)
	world.set_active(false)
	Audio.engine(false)
	Audio.music(&"final" if opponent_id == "teo_2" else &"battle", 0.6)
	Audio.ambience({&"crowd": 0.2 if mode == &"tutorial" else 0.55}, 0.8)
	_battle_seed += 1
	var director := BattleDirector.new()
	director.setup({
		"player": GameState.player_side(), "opponent": opponent, "mode": String(mode),
		"title": title, "seed": _battle_seed,
	})
	add_child(director)
	await _fade_to(0.0, 0.3)
	var result: Dictionary = await director.finished
	Audio.music(&"", 0.5)
	await _fade_to(1.0, 0.3)
	director.queue_free()
	get_tree().paused = false
	world.set_active(true)

	var won: bool = bool(result["won"])
	Audio.jingle(&"victory" if won else &"defeat")
	var screen := ResultScreen.new()
	screen.won = won
	if won and prize > 0:
		GameState.money += prize
		screen.rewards.append("Tiền thưởng: +%s" % GameState.money_text(prize))
	elif not won:
		screen.rewards.append("Không mất tiền, không mất gà – EXP an ủi")
	if won and float(result["player_hp_ratio"]) >= 0.999 and mode != &"tutorial":
		screen.rewards.append("Thắng tuyệt đối – không mất máu!")
	screen.exp_gain = GameState.battle_exp(opponent, won)
	add_child(screen)
	await _fade_to(0.0, 0.3)
	await screen.run()
	Audio.music(&"village")
	_refresh_status()
	return 1 if won else 0


# =================================================================== âm thanh hoạt động

## Âm thanh cho mini-game bờ nam (tín hiệu fx của ActivityRunner).
func _on_activity_fx(kind: StringName, _world_pos: Vector2) -> void:
	match kind:
		&"splash", &"throw":
			Audio.sfx(&"splash", -6.0 if kind == &"splash" else -12.0)
		&"catch":
			Audio.sfx(&"fish_jump")
		&"cut":
			Audio.sfx(&"harvest", -2.0)
		&"pick", &"drop":
			Audio.sfx(&"brick", -4.0, 1.15 if kind == &"pick" else 1.0)
		&"win":
			Audio.jingle(&"reward")
		&"incense":
			Audio.sfx(&"temple_bell", -3.0)
		&"xam":
			Audio.sfx(&"ui_confirm")
		&"ticket":
			Audio.sfx(&"coin")


func _on_activity_started(id: StringName) -> void:
	if id == &"school":
		Audio.sfx(&"school_bell", -4.0)
