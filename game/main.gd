extends Node

## Điểm vào của game: Tiêu đề → Hồi ức → Khám phá ↔ Hội thoại ↔ Pre-battle ↔ Trận ↔ Kết quả.
## Cốt truyện Act 1 – Ao Làng theo GDD v1.2: 8.3 (5 trận), 8.4 (nhịp dạy), 9.1–9.5 (bối cảnh, nhân vật,
## thoại Nam Bộ), 7.2 (thưởng), Bảng 8.1 (nhà = ngủ/lưu game).
## Sau Act 1 (wave 3 – tầng đời sống/truyện): main.gd chỉ còn là bộ định tuyến; phần việc nằm ở
##   game/story/story_life.gd    – trường THPT, Mẹ, hàng xóm + thân thiết + quest, giờ mở cửa, mục tiêu, mẹo, buổi sáng
##   game/story/story_shops.gd   – tiệm Cô Ba, bốn sạp chợ, xe khô gà Lão Gà Khô (Khô Gà)
##   game/story/story_leagues.gd – Liên tỉnh / Olympic / giao hữu, gọi tay trong + tẩu thoát, kết Act 1, giấc mơ, kết game
##   game/sim/life_state.gd      – trạng thái riêng (lưu user://chick_fighter_life.cfg)
## Mọi trận đi qua run_match(side, config): màn chuẩn bị → (nhánh công an) → trận → kết quả → ghi trận → trừ giờ.

const S := GameState.Stage
const Activities := preload("res://game/world/activities.gd")
const ActivityRunner := preload("res://game/world/activity_runner.gd")
const Audio := preload("res://game/audio/audio_director.gd")
const RaceGame := preload("res://game/world/race/race_game.gd")
const RaceRiders := preload("res://game/world/race/race_riders.gd")
const DayNight := preload("res://game/world/day_night.gd")
const ClockHud := preload("res://game/ui/clock_hud.gd")
const HomeState := preload("res://game/home/home_state.gd")
const LifeState := preload("res://game/sim/life_state.gd")
const StoryLife := preload("res://game/story/story_life.gd")
const StoryShops := preload("res://game/story/story_shops.gd")
const StoryLeagues := preload("res://game/story/story_leagues.gd")
const Guidebook := preload("res://game/ui/guidebook.gd")
const AchievementToast := preload("res://game/ui/achievement_toast.gd")

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
## Ánh sáng ngày/đêm (con của world) và đồng hồ góc trên phải (tự ẩn khi world ẩn).
var day_night: Node2D
var clock_hud: CanvasLayer
## Tầng đời sống/truyện (game/story/**).
var life: RefCounted
var shops: RefCounted
var leagues: RefCounted
## Cấu hình BattleDirector của trận gần nhất (test đọc).
var last_battle_config: Dictionary = {}
## Test: kết quả tẩu thoát dựng sẵn (bỏ qua mini-game), autopilot cho EscapeGame (skill ≥ 0), tự chạy cắt cảnh.
var escape_override: Dictionary = {}
var test_escape_autopilot: float = -1.0
var test_auto_cutscene: bool = false
## Sổ tay V (hướng dẫn + cây thành tựu + sổ tay) và thông báo "Thành tựu mới!" (game/ui, game/sim/achievements.gd).
var guidebook: CanvasLayer
var achievement_toast: CanvasLayer
var _ach_timer: float = 0.0
var _ach_prev: Dictionary = {}
var _match_director: Node = null
var _match_specials: int = 0


func _ready() -> void:
	# Font chung cho mọi Control không tự đặt font (xem DialogBox.make_font, thư mục game/fonts/).
	ThemeDB.fallback_font = DialogBox.make_font()
	# Pixel art ở mọi nơi: chữ/ảnh phóng nguyên lần không nhoè (nút nào cần mịn tự đặt LINEAR – vd. lớp ảnh bản đồ M).
	get_tree().root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
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
	clock_hud = ClockHud.new()
	add_child(clock_hud)
	achievement_toast = AchievementToast.new()
	add_child(achievement_toast)
	guidebook = Guidebook.new()
	guidebook.set("dialog", dialog)
	guidebook.set("blocked", func() -> bool: return _busy or race != null)
	add_child(guidebook)
	life = StoryLife.new(self)
	shops = StoryShops.new(self)
	leagues = StoryLeagues.new(self)
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
			HomeState.load_state()
			LifeState.load_save()
			Achievements.load_save()
			_spawn_world()
			if GameState.stage >= S.ACT_END and not LifeState.finale_act1:
				# Save cũ đã "HẾT ACT 1" (bản trước quay về tiêu đề): mở Act 2 ngay.
				_busy = true
				world.player.can_move = false
				await leagues.act2_morning()
				world.player.can_move = true
				_busy = false
				_refresh_status()
				return
			await _fade_to(0.0)
			var lines: Array = [["", "Đã tải lại tiến trình. Chào mừng trở lại xã Bình Kê, %s!" % GameState.player_name]]
			if LifeState.finale_act1:
				lines.append(["", "%s. %s" % [GameState.clock_text(), life.plan_line()]])
			await dialog.say(lines)
			_refresh_status()
		_:
			GameState.reset()
			Activities.reset()
			HomeState.reset()
			LifeState.reset()
			Achievements.reset()
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
	# Ngày/đêm: con của world → ẩn theo world trong trận; đèn ấm trước cửa nhà về tối.
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.world = world
	day_night.add_light(World.SPAWN + Vector2(0, -24), 110.0, 1.0)
	world.add_child(day_night)
	clock_hud.world = world
	guidebook.set("world", world)
	_ach_prev = {}
	activities.connect("activity_finished", _on_activity_finished_achievements)
	if world.has_signal(&"achievement_event"):
		world.connect(&"achievement_event", func(id: StringName) -> void: Achievements.world_event(id))
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
	var free_roam: bool = LifeState.finale_act1
	match id:
		&"home":
			await _talk_home()
		&"chu_tu":
			if free_roam:
				await _talk_chu_tu_coach()
			else:
				await _talk_chu_tu()
		&"teo":
			if free_roam:
				await life.talk_npc(&"teo")
			else:
				await _talk_teo()
		&"co_ba":
			await shops.open(&"co_ba")
		&"arena":
			if free_roam:
				await leagues.village_pit()
			else:
				await _enter_arena()
		&"cat":
			if GameState.stage < S.TUTORIAL:
				await dialog.say([["", "Con mèo tam thể liếc nhìn bạn rồi ngáp dài. Nghe nói ngoài chợ có lão mèo vừa khóc vừa cười đẩy xe khô gà lá chanh…"]])
			else:
				await life.talk_npc(&"cat")
			Achievements.notify(&"cat_talk")
		&"fisher":
			if free_roam:
				await life.talk_npc(&"fisher")
			else:
				await dialog.say([["Ông câu cá", "Câu cả buổi chưa được con nào. Mà nghe nói giải Ao Làng năm nay có thằng Tèo, gà nó lẹ lắm à nghen."]])
		&"ferry_north", &"ferry_south":
			await _ferry(id == &"ferry_north")
		&"lottery":
			var chat: bool = false
			if free_roam:
				chat = await dialog.choose("Cô bán vé số", "Vé số đây con ơi! Mua vé hay ngồi nghe cô kể chuyện?",
					["Vé số (mua / dò)", "Hỏi chuyện xóm (15 phút)"]) == 1
			if chat:
				await life.chat(&"lottery")
			elif await life.gate(id, "Cô bán vé số"):
				await run_activity(id)
		&"school", &"site", &"farm", &"temple", &"fish_house", &"cau_ca_loc", &"tha_dieu":
			# Hoạt động bờ nam: game/world/activity_runner.gd + game/world/minigames/.
			if await life.gate(id, ""):
				if id == &"site":
					await life.quest_deliver(&"site")
				await run_activity(id)
		&"cat_shop", &"market_chicken", &"market_eggs", &"market_food", &"market_gear":
			await shops.open(id)
		&"thpt":
			await life.thpt()
		&"arena_lien_tinh":
			await leagues.venue(&"lien_tinh")
		&"arena_olympic":
			await leagues.venue(&"olympic")
		&"npc_ba_lan", &"npc_chu_bay", &"npc_ong_tam", &"npc_ong_sau", &"npc_chu_muoi":
			await life.talk_npc(id)
	if world != null:
		await _check_bedtime()
	if world != null:
		_refresh_status()
		world.player.can_move = true
	_busy = false


## Chạy một hoạt động của ActivityRunner (bờ nam, lớp THPT, nghề làm thêm) rồi cập nhật tiến độ quest.
func run_activity(id: StringName) -> void:
	await activities.run(id)
	await life.after_activity(id)


func _ferry(to_south: bool) -> void:
	var line: String = "Qua sông hông con? Lên đò đi, chú chở qua liền." if to_south else "Về xóm hả? Lên đò!"
	var pick: int = await dialog.choose("Chú lái đò", line, ["Lên đò", "Thôi"])
	if pick != 0:
		return
	await world.ride_ferry(to_south)
	GameState.spend_time(GameState.TIME_FERRY)
	Achievements.unlock(&"explore_ferry")


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
		await _check_bedtime()
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
	GameState.spend_time(GameState.time_cost(&"race"))
	var record: Dictionary = Activities.record_race(won)
	if won:
		Achievements.unlock(&"secret_race")
		Achievements.unlock(StringName("secret_rider_%s" % String(rider.get("id", ""))))
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
			if not _owns_any_gear():
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
			objective = "Về nhà"
			target = &"home"
	if LifeState.finale_act1:
		var pick: Array = life.objective()
		objective = String(pick[0])
		target = StringName(pick[1])
	var status: String = "%s · %s" % [GameState.player_name, GameState.money_text(GameState.money)]
	if GameState.stage >= S.TUTORIAL:
		status += " · %s Lv%d" % [GameState.chicken_name, GameState.level]
	if LifeState.finale_act1:
		status += " · Tech %d · Bio %d" % [GameState.technology, GameState.biotech]
		if GameState.kho_ga > 0.0:
			status += " · Khô Gà %s kg" % String.num(GameState.kho_ga, 2)
	world.set_status(status, objective, target)
	world.label_overrides = life.label_overrides()


## Có món đồ gắn được nào chưa (Act 1: mục tiêu "sắm đồ ở Cô Ba").
func _owns_any_gear() -> bool:
	for id in GameState.ITEMS:
		if ItemCatalog.is_equipment(id) and GameState.owned_total(id) > 0:
			return true
	return false


func _talk_home() -> void:
	match GameState.stage:
		S.PROLOGUE, S.GO_CHU_TU:
			await dialog.say([["Mẹ", "Chú Tư ở sân đình đó con, cứ đi dọc đường làng về phía đông là tới."]])
			return
		S.CHAMPION:
			await leagues.act1_finale()
			return
	if GameState.stage >= S.TUTORIAL:
		await life.tutorial("home")
	# --- Nhà & chuồng gà (game/home) ---
	# "Vô nhà" mở cảnh nội thất + sân sau (bội gà, lò ấp, bàn học, giường). HomeScene tự ẩn/hiện world;
	# trả về {"sleep": bool, "day_over": bool}: chọn ngủ ở giường → ngủ như cũ; luyện quá 23:00 → _check_bedtime lo.
	const HomeScene := preload("res://game/home/home_scene.gd")
	# Thứ tự lựa chọn giữ nguyên (0 = Vô nhà, 1 = Đi ngủ – test nhà dựa vào); từ Act 2 thêm "Nói chuyện" trước "Thôi".
	var options: Array = ["Vô nhà (chuồng gà, bàn học)", "Đi ngủ (lưu game)"]
	var details: Array = ["Coi gà, cho ăn, gắn cựa, ấp trứng, đổi Biotech… (bây giờ %s)." % GameState.clock_text(),
		"Sang ngày mới (bây giờ %s, mai dậy 07:00): việc làm thêm mở lại, vé số được dò." % GameState.clock_text()]
	if LifeState.finale_act1:
		options.append("Nói chuyện với Mẹ, Ba (15 phút)")
		details.append("Mẹ theo dõi chuyên cần; đầu tuần xét tiền tiêu vặt.")
	options.append("Thôi, con đi tiếp")
	details.append("")
	var pick: int = await dialog.choose("Mẹ", "Về rồi hả con? Mệt thì đi ngủ một giấc.", options, details)
	if LifeState.finale_act1 and pick == 2:
		await life.talk_mom()
	elif pick == 0:
		var home: Dictionary = await HomeScene.run(self)
		if bool(home.get("sleep", false)):
			await _sleep_until_morning(false)
	elif pick == 1:
		await _sleep_until_morning(false)
	# --- hết phần Nhà & chuồng gà ---


## Ngủ (tự lưu): end_day() → báo cáo buổi sáng (thứ, Thể trạng gà, trứng tới ngày nở, vé số).
## forced: bị đưa về nhà vì quá 23:00 (GDD 3.6: hôm sau dậy 08:00).
func _sleep_until_morning(forced: bool) -> void:
	Audio.music(&"", 0.8)
	Audio.ambience({&"crickets": 0.7}, 0.6)
	await _fade_to(1.0, 0.5)
	if forced and world != null:
		world.set_active(false)
		world.player.position = World.SPAWN
		world.set_active(true)
	var summary: Dictionary = GameState.end_day(forced)
	Achievements.unlock(&"life_day")
	# Mẹ xét chuyên cần / tiền tiêu vặt / rửa chén phạt áp dụng TRƯỚC khi lưu (lưu khớp trạng thái buổi sáng).
	var life_lines: Array = life.morning_lines()
	GameState.save()
	Activities.save()
	HomeState.save_state()
	LifeState.save()
	await get_tree().create_timer(1.2).timeout
	Audio.sfx(&"rooster_crow", -3.0)
	Audio.music(&"village")
	await _fade_to(0.0, 0.5)
	var lines: Array = []
	for line in GameState.morning_lines(summary):
		lines.append(["", line])
	if Activities.lottery_result_ready():
		lines.append(["", "Vé số hôm qua xổ rồi – ghé cô bán vé số dò thử coi."])
	lines.append(["", "Một ngày mới ở xã Bình Kê. Đã lưu game."])
	lines.append_array(life_lines)
	await dialog.say(lines)


## Sau mỗi việc tốn giờ: quá 23:00 (chỉ từ Act 2 – Act 1 chưa có đồng hồ ngày) → nhắc khuya, đưa về nhà ngủ.
func _check_bedtime() -> void:
	if world == null or not GameState.day_over():
		return
	Achievements.unlock(&"secret_night_owl")
	await dialog.say([["", "Trời khuya lơ khuya lắc rồi (%s). Mẹ gọi kêu về ngủ, mai còn đi học nữa!" % GameState.time_text()]])
	await _sleep_until_morning(true)
	_refresh_status()


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


# =================================================================== trận đấu

## Act 1 (giữ chữ ký cũ): trận với đối thủ theo id. Trả về 1 thắng, 0 thua, −1 quay lại từ Pre-battle.
func _run_battle(opponent_id: String, mode: StringName, title: String, prize: int) -> int:
	var side: Dictionary = GameState.opponent_side(opponent_id)
	side["id"] = opponent_id
	var out: Dictionary = await run_match(side, {"mode": String(mode), "kind": "story", "title": title, "prize": prize,
		"police_ok": false, "music": &"final" if opponent_id == "teo_2" else &"battle"})
	match String(out["outcome"]):
		"back":
			return -1
		"won":
			return 1
	return 0


## MỘT đường cho mọi trận: màn chuẩn bị (trừ trận hướng dẫn) → nhánh "Gọi tay trong" → BattleDirector → kết quả
## (ResultScreen) → ghi trận → trừ giờ (TIME_BATTLE); _on_interact gọi _check_bedtime sau đó như mọi việc khác.
## side: bên đấu dựng sẵn (GameState.opponent_side / next_league_opponent – không dùng OPPONENTS thô).
## config: mode ("tutorial"|"friendly"|"normal"), kind ("story"|"spar"|"league"), title, prize, tid (giải),
##   police_ok, music, escape_difficulty + khóa chuyển thẳng cho BattleDirector: arena_variant, round_time, hell_mode,
##   opponent_start_card_gauge, rounds_to_win.
## Trả về {outcome: "won"|"lost"|"back"|"raid"|"caught", won, result (của BattleDirector), league (tournament_result)}.
func run_match(side: Dictionary, config: Dictionary) -> Dictionary:
	var mode: String = String(config.get("mode", "normal"))
	var title: String = String(config.get("title", ""))
	var police: bool = false
	if mode != "tutorial":
		if bool(config.get("police_ok", false)) and StoryLeagues.police_refusal(config) == "" and GameState.can_call_police(side):
			await life.tutorial("police")
		while true:
			var pre := PreBattle.new()
			pre.opponent = side
			pre.title = title
			add_child(pre)
			var go: bool = await pre.run()
			var called: bool = bool(pre.police_called)
			pre.queue_free()
			if not go:
				return {"outcome": "back", "won": false, "result": {}}
			if called:
				var why: String = StoryLeagues.police_refusal(config)
				if why != "":
					await dialog.say([["", why]])
					continue
				police = true
			break
	if police:
		Achievements.unlock(&"secret_police")
		await leagues.police_call_scene(side, config)

	Audio.music(&"", 0.4)
	await _fade_to(1.0, 0.3)
	world.set_active(false)
	Audio.engine(false)
	Audio.music(StringName(config.get("music", &"battle")), 0.6)
	Audio.ambience({&"crowd": 0.2 if mode == "tutorial" else 0.55}, 0.8)
	_battle_seed += 1
	var setup: Dictionary = {
		"player": GameState.player_side(), "opponent": side, "mode": "police" if police else mode,
		"title": title, "seed": _battle_seed,
	}
	for key in ["arena_variant", "round_time", "hell_mode", "opponent_start_card_gauge", "rounds_to_win"]:
		if config.has(key):
			setup[key] = config[key]
	last_battle_config = setup
	var director := BattleDirector.new()
	director.setup(setup)
	add_child(director)
	_match_director = director
	await _fade_to(0.0, 0.3)
	var result: Dictionary = await director.finished
	_match_specials = _player_track(director, "specials")
	_match_director = null
	Audio.music(&"", 0.5)
	await _fade_to(1.0, 0.3)
	director.queue_free()
	get_tree().paused = false
	world.set_active(true)
	GameState.spend_time(GameState.TIME_BATTLE)
	var out: Dictionary
	if police:
		out = await leagues.police_after(side, config, result)
	else:
		out = await settle_match(side, config, bool(result.get("won", false)), result)
	Audio.music(&"village")
	_refresh_status()
	return out


## Kết quả thường của một trận: tiền thưởng / giải (tournament_result – đã gồm record_result), EXP (ResultScreen
## cộng), Thể trạng (thua −15 qua record_result). extra: dòng thêm cho màn kết quả (vd. tiền phạt).
func settle_match(side: Dictionary, config: Dictionary, won: bool, result: Dictionary, extra: Array[String] = []) -> Dictionary:
	var mode: String = String(config.get("mode", "normal"))
	var tid: StringName = StringName(config.get("tid", ""))
	var prize: int = int(config.get("prize", 0))
	Audio.jingle(&"victory" if won else &"defeat")
	var screen := ResultScreen.new()
	screen.won = won
	if tid != &"":
		var info: Dictionary = GameState.TOURNAMENTS.get(tid, {})
		var final: bool = GameState.league_round(tid) >= int((info.get("rounds", []) as Array).size()) - 1
		if won:
			screen.rewards.append("Tiền thưởng: +%s" % GameState.money_text(prize))
			if final:
				screen.rewards.append("VÔ ĐỊCH! Danh hiệu «%s»" % String(info.get("prize_title", "")))
				if int(info.get("prize_biotech", 0)) > 0:
					screen.rewards.append("+%d Biotech" % int(info["prize_biotech"]))
		else:
			screen.rewards.append("Bị loại – tuần sau đăng ký lại. Không mất tiền, không mất gà")
	elif won and prize > 0:
		GameState.money += prize
		screen.rewards.append("Tiền thưởng: +%s" % GameState.money_text(prize))
	elif not won:
		screen.rewards.append("Không mất tiền, không mất gà – EXP an ủi")
	if won and float(result.get("player_hp_ratio", 0.0)) >= 0.999 and mode != "tutorial":
		screen.rewards.append("Thắng tuyệt đối – không mất máu!")
	for line in extra:
		screen.rewards.append(line)
	screen.exp_gain = GameState.battle_exp(side, won)
	add_child(screen)
	await _fade_to(0.0, 0.3)
	await screen.run()
	var out: Dictionary = {"outcome": "won" if won else "lost", "won": won, "result": result}
	# ResultScreen đã cộng EXP (add_exp); ở đây ghi thắng/thua + Thể trạng (thua −15). Trận giải: tournament_result
	# tự gọi record_result (không ghi hai lần).
	if tid != &"":
		out["league"] = GameState.tournament_result(tid, won)
	else:
		GameState.record_result(won)
	_achievements_after_match(side, config, won, result, out)
	return out


## Act 2+: Chú Tư làm huấn luyện viên (lời khuyên về đối thủ kế tiếp) – cũng gọi điện dặn dò giữa các vòng.
func _talk_chu_tu_coach() -> void:
	var pick: int = await dialog.choose("Chú Tư", "Sao rồi nhà vô địch? Gà con bữa nay ăn uống được hông?",
		["Hỏi về đối thủ kế tiếp", "Trò chuyện (15 phút)", "Thôi"])
	if pick == 0:
		await dialog.say([["Chú Tư", life.opponent_tip(life.next_opponent())]])
	elif pick == 1:
		GameState.spend_time(StoryLife.CHAT_MINUTES)
		var lines: Array[String] = [
			"Hồi chú bằng tuổi con, chú với ông nội con đạp xe ba chục cây số đi coi đá gà Liên tỉnh. Về tới nhà bị bà nội con rượt chạy quanh xóm.",
			"Nuôi gà như nuôi con: ăn đúng bữa, ngủ đủ giấc, đừng bắt nó đá lúc mệt.",
			"Đồ tốt thì cũng phải hợp gà. Gà tre lẹ thì gắn Cánh, gà nòi lì thì gắn Giáp. Thử ở màn chuẩn bị coi cái nào hợp.",
			"Con đi học đều hông đó? Mẹ con mà la thì chú hổng đỡ nổi đâu nghen!",
		]
		await dialog.say([["Chú Tư", lines[GameState.day % lines.size()]]])


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


# =================================================================== thành tựu (game/sim/achievements.gd)

## Mỗi khung: phá thủ trong trận (đọc cờ break_pending của đối thủ). Mỗi giây: dò GameState/LifeState/HomeState.
func _process(delta: float) -> void:
	if _match_director != null and is_instance_valid(_match_director):
		var fighters: Array = _match_director.get("fighters")
		if fighters.size() == 2 and fighters[1] != null and bool(fighters[1].get("break_pending")):
			Achievements.unlock(&"fight_guard_break")
	_ach_timer -= delta
	if _ach_timer <= 0.0 and world != null:
		_ach_timer = 1.0
		poll_achievements()


## Số liệu trận của gà người chơi (track của BattleDirector.Fighter) – đọc trước khi director bị xoá.
func _player_track(director: Node, key: String) -> int:
	var fighters: Array = director.get("fighters")
	if fighters.is_empty() or fighters[0] == null:
		return 0
	var track: Dictionary = fighters[0].get("track")
	return int(track.get(key, 0))


## Dò trạng thái game (rẻ, mỗi giây một lần): mốc truyện, tiền, đồ, chuồng, trứng, đột biến, khô gà, chăm gà.
func poll_achievements() -> void:
	var st: int = GameState.stage
	for pair in [[S.TUTORIAL, &"story_chicken"], [S.FRIENDLY, &"story_tutorial"], [S.PREPARE, &"story_teo"],
			[S.ROUND_2, &"story_ao_r1"], [S.FINAL, &"story_ao_r2"], [S.CHAMPION, &"story_ao_lang"]]:
		if st >= int(pair[0]):
			Achievements.unlock(pair[1])
	if GameState.cards.has(&"cuong_no") and GameState.cards.has(&"mai_rua") and GameState.cards.has(&"gio_song"):
		Achievements.unlock(&"story_cards")
	if LifeState.dream_seen:
		Achievements.unlock(&"secret_dream")
	Achievements.record_max(&"money", GameState.money)
	Achievements.record_max(&"coop_level", GameState.coop_level)
	if _owns_any_gear():
		Achievements.unlock(&"life_gear")
	if not GameState.chickens.is_empty():
		var slots: int = 0
		for slot in PreBattle.SLOT_ROWS:
			if GameState.equipped(GameState.active, slot) != &"":
				slots += 1
		Achievements.record_max(&"slots", slots)
	var cared: bool = false
	for c in GameState.chickens:
		if not (c.get("mutations", []) as Array).is_empty():
			Achievements.unlock(&"life_mutation")
		for kind in HomeState.CARE_ORDER:
			if HomeState.care_done(int(c.get("id", -1)), kind):
				cared = true
	if cared:
		Achievements.unlock(&"life_care")
		Achievements.add_to_set(&"care_days", GameState.day)
	var week: int = GameState.week()
	var days: int = 0
	for d in LifeState.attended:
		if GameCalendar.week(int(d)) == week:
			days += 1
	if days >= 5:
		Achievements.unlock(&"life_week")
	# chênh lệch so với lần dò trước: trứng nở (lò ấp bớt, chuồng thêm), làm Khô Gà (kg tăng)
	if not _ach_prev.is_empty():
		if GameState.incubator.size() < int(_ach_prev["incubator"]) and GameState.chickens.size() > int(_ach_prev["chickens"]):
			Achievements.unlock(&"life_hatch")
		if GameState.kho_ga > float(_ach_prev["kho_ga"]) + 0.001:
			Achievements.unlock(&"life_kho_ga")
	_ach_prev = {"incubator": GameState.incubator.size(), "chickens": GameState.chickens.size(), "kho_ga": GameState.kho_ga}


## Sau mỗi trận thường (settle_match): thắng, chuỗi đòn, tuyệt đối, thẻ, tuyệt chiêu, vũ khí, Đông Tảo, Hell Mode, giải.
func _achievements_after_match(side: Dictionary, config: Dictionary, won: bool, result: Dictionary, out: Dictionary) -> void:
	if not won:
		return
	Achievements.unlock(&"fight_first_win")
	Achievements.notify(&"wins")
	if int(result.get("max_combo", 0)) >= 4:
		Achievements.unlock(&"fight_combo4")
	if String(config.get("mode", "normal")) != "tutorial" and (bool(result.get("perfect", false)) or float(result.get("player_hp_ratio", 0.0)) >= 0.999):
		Achievements.unlock(&"fight_perfect")
	if int(result.get("cards_used", 0)) > 0:
		Achievements.unlock(&"fight_card")
	if _match_specials > 0:
		Achievements.unlock(&"fight_super")
	if bool(result.get("hell_mode", false)):
		Achievements.unlock(&"fight_hell")
	if not GameState.chickens.is_empty():
		var weapon: StringName = GameState.equipped(GameState.active, &"weapon")
		if weapon != &"":
			Achievements.unlock(&"fight_weapon")
			Achievements.add_to_set(&"weapon_wins", weapon)
	if Moves.kit_for_side(side) == Moves.KIT_DONGTAO:
		Achievements.unlock(&"fight_dongtao")
	var who: String = String(side.get("name", ""))
	if who != "":
		Achievements.add_to_set(&"beaten", who)
	var tid: StringName = StringName(config.get("tid", ""))
	var league: Dictionary = out.get("league", {})
	match tid:
		&"lien_tinh":
			Achievements.unlock(&"story_lien_round")
			if bool(league.get("champion", false)):
				Achievements.unlock(&"story_lien_tinh")
		&"olympic":
			Achievements.unlock(&"story_olympic_round")
			if bool(league.get("champion", false)):
				Achievements.unlock(&"story_olympic")


## ActivityRunner.activity_finished: đi học, việc làm thêm, vé số.
func _on_activity_finished_achievements(id: StringName, result: Dictionary) -> void:
	if bool(result.get("cancelled", false)):
		return
	match id:
		&"school", &"thpt":
			Achievements.unlock(&"life_school")
		&"site", &"farm", &"fish_house", &"job_shop", &"job_boat":
			Achievements.unlock(&"life_first_job")
			var jobs: Dictionary = {&"site": &"life_job_site", &"farm": &"life_job_farm", &"fish_house": &"life_job_fish",
				&"job_shop": &"life_job_shop", &"job_boat": &"life_job_boat"}
			Achievements.unlock(jobs[id])
		&"cau_ca_loc":
			if int(result.get("fish", 0)) > 0:
				Achievements.unlock(&"life_snakehead")
		&"tha_dieu":
			if int(result.get("rings", 0)) >= Activities.KITE_RINGS_PER_TECH:
				Achievements.unlock(&"life_kite")
		&"lottery":
			if int(result.get("won", 0)) >= Activities.LOTTERY_PRIZE:
				Achievements.unlock(&"secret_jackpot")


## Sổ tay V mở được lúc này không (test).
func can_open_guidebook() -> bool:
	return guidebook != null and bool(guidebook.call("can_open"))
