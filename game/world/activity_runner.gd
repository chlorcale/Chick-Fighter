extends Node

## Điều phối hoạt động ở bờ nam: hội thoại trước/sau, chạy mini-game, phát thưởng, giới hạn mỗi ngày.
## main.gd chỉ gọi: await runner.run(id) với id = fish_house, farm, school, site, temple, lottery
## + (tầng đời sống, game/story): thpt (2 tiết học THPT), job_shop (bán cơm phụ bà Lan), job_boat (chở ghe phụ chú Bảy)
## + trò phụ mới: cau_ca_loc (câu cá lóc ở bờ kênh), tha_dieu (thả diều trên bờ đê ruộng).
## Mỗi mini-game là một TRANG riêng (game/world/minigames/*, như trò đua xe): _play() làm mờ, ẩn World,
## thêm trang vào cây (cạnh World), chờ kết quả, rồi mờ dần về đúng chỗ cũ, trả lại nhạc/tiếng nền.
## Tín hiệu cho âm thanh/hiệu ứng:
##   activity_started(id), activity_finished(id, result)
##   fx(kind, pos) – chuyển tiếp từ trang mini-game (splash, throw, catch, miss, cut, pick, drop, win, incense,
##   xam, ticket) và của runner (incense, xam, ticket). pos là toạ độ trong trang (hoặc bản đồ nếu ở xóm).
## Test: autopilot = true (mọi trang tự chơi), current_game = trang đang chạy (press/hold/quit_now),
##       current_quiz = trang câu đố đang chạy (current_answer).

signal activity_started(id: StringName)
signal activity_finished(id: StringName, result: Dictionary)
signal fx(kind: StringName, world_pos: Vector2)

const Activities := preload("res://game/world/activities.gd")
const WorldFx := preload("res://game/world/world_fx.gd")
const FishGame := preload("res://game/world/minigames/fish_game.gd")
const HarvestGame := preload("res://game/world/minigames/harvest_game.gd")
const BrickGame := preload("res://game/world/minigames/brick_game.gd")
const SchoolQuiz := preload("res://game/world/minigames/school_quiz.gd")
const ClassQuiz := preload("res://game/world/minigames/class_quiz.gd")
const QuizPage := preload("res://game/world/minigames/quiz_page.gd")
const SalesGame := preload("res://game/world/minigames/sales_game.gd")
const BoatGame := preload("res://game/world/minigames/boat_game.gd")
const TempleGame := preload("res://game/world/minigames/temple_game.gd")
const LotteryGame := preload("res://game/world/minigames/lottery_game.gd")
const FishingGame := preload("res://game/world/minigames/fishing_game.gd")
const KiteGame := preload("res://game/world/minigames/kite_game.gd")
const LifeState := preload("res://game/sim/life_state.gd")
const Calendar := preload("res://game/data/calendar.gd")
const AudioDir := preload("res://game/audio/audio_director.gd")

const IDS: Array[StringName] = [&"fish_house", &"farm", &"school", &"site", &"temple", &"lottery", &"thpt", &"job_shop",
	&"job_boat", &"cau_ca_loc", &"tha_dieu"]
const URN_TOP: Vector2 = Vector2(900, 1002)
const FADE_TIME: float = 0.3
const FORTUNES: Array[String] = [
	"Quẻ thượng: Gà nhà gáy sớm, việc gì cũng thuận. Ra sới cứ bình tĩnh mà đá.",
	"Quẻ trung: Nước lớn rồi nước ròng. Thua keo này thì bày keo khác.",
	"Quẻ thượng: Lúa chín đầy đồng – siêng năng thì có ăn.",
	"Quẻ hạ: Chớ nóng nảy. Gà hăng quá là dễ ăn đòn phản.",
	"Quẻ trung: Có quý nhân phù trợ – người lớn tuổi trong xóm sẽ chỉ đường.",
	"Quẻ thượng: Gió sông thổi thuận, ghe về đầy khoang.",
	"Quẻ trung: Tiền vô cửa trước, ra cửa sau. Mua sắm vừa phải thôi nghen.",
	"Quẻ hạ: Trời chuyển mưa, việc lớn để mai hẵng tính.",
	"Quẻ thượng: Học một biết mười – ráng nghe lời thầy cô.",
	"Quẻ trung: Đỡ được thì mới đánh được. Giữ thủ cho chắc.",
	"Quẻ thượng: Chín cựa chưa thấy, mà gà con đang lớn từng ngày.",
	"Quẻ trung: Bạn hiền như nước giếng trong. Chơi với Tèo cho đàng hoàng.",
]

var world: Node      # World
var dialog: DialogBox
## Test bật để mọi mini-game tự chơi.
var autopilot: bool = false
## Trang mini-game đang chạy (null nếu không có).
var current_game: Node = null
## Trang câu đố đang chạy (có current_answer) – null nếu không có.
var current_quiz: Object = null
var ground_fx: Node2D
var air_fx: Node2D


func setup(p_world: Node, p_dialog: DialogBox) -> void:
	world = p_world
	dialog = p_dialog
	if not world.is_node_ready():
		await world.ready
	ground_fx = WorldFx.new()
	world.map_view.add_ground(ground_fx)
	air_fx = WorldFx.new()
	air_fx.z_index = 20
	world.add_child(air_fx)


func run(id: StringName) -> void:
	if not IDS.has(id):
		return
	activity_started.emit(id)
	var result: Dictionary = {}
	match id:
		&"fish_house":
			result = await _fish_house()
		&"farm":
			result = await _farm()
		&"school":
			result = await _school()
		&"site":
			result = await _site()
		&"temple":
			result = await _temple()
		&"lottery":
			result = await _lottery()
		&"thpt":
			result = await _thpt_class()
		&"job_shop":
			result = await _job(&"job_shop")
		&"job_boat":
			result = await _job(&"job_boat")
		&"cau_ca_loc":
			result = await _fishing()
		&"tha_dieu":
			result = await _kite()
	# Tốn giờ (GDD 3.6) khi đã làm xong việc; main.gd kiểm GameState.day_over() sau hoạt động.
	result["day_over"] = Activities.spend(id, result)
	activity_finished.emit(id, result)


# ================================================================== chuyển trang

## Chạy một trang mini-game: mờ → ẩn World → trang (camera, cảnh, hướng dẫn, chơi, kết quả) → mờ → về đúng chỗ cũ.
func _play(game: Node) -> Dictionary:
	game.set("world", world)
	game.set("ground_fx", ground_fx)
	game.set("air_fx", air_fx)
	game.set("autopilot", autopilot)
	game.connect("fx", func(kind: StringName, pos: Vector2) -> void: fx.emit(kind, pos))
	current_game = game
	if game.get("current_answer") != null:
		current_quiz = game
	world.interactions_enabled = false
	world.player.can_move = false
	var host: Node = world.get_parent() if world.get_parent() != null else self
	var spot: Vector2 = world.player.position
	var audio: Dictionary = _audio_snapshot()
	var fade: ColorRect = _make_fade(host)
	await _fade(fade, 1.0)
	world.set_active(false)
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	host.add_child(game)
	game.call("enter_audio")
	await _fade(fade, 0.0)
	var result: Dictionary = await game.call("run")
	await _fade(fade, 1.0)
	game.queue_free()
	current_game = null
	current_quiz = null
	world.player.position = spot
	world.set_active(true)
	_audio_restore(audio)
	await _fade(fade, 0.0)
	fade.get_parent().queue_free()
	world.interactions_enabled = true
	world.player.can_move = false # main.gd mở lại sau hội thoại cuối
	return result


func _make_fade(host: Node) -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = 95
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	return rect


func _fade(rect: ColorRect, alpha: float) -> void:
	var tween := rect.create_tween()
	tween.tween_property(rect, "color:a", alpha, FADE_TIME)
	await tween.finished


## Nhạc + mức tiếng nền đang chơi (để trả lại sau trang).
func _audio_snapshot() -> Dictionary:
	var out: Dictionary = {"music": &"village", "layers": {}}
	var director: Object = AudioDir.instance
	if not is_instance_valid(director):
		return out
	out["music"] = director.get("_music_track")
	var layers: Dictionary = director.get("_layers")
	for key in layers.keys():
		var chan: Object = layers[key]
		if chan != null:
			out["layers"][key] = float(chan.get("target"))
	return out


func _audio_restore(snap: Dictionary) -> void:
	AudioDir.music(StringName(snap.get("music", &"village")), 0.8)
	AudioDir.ambience(snap.get("layers", {}), 0.8)


func _say(lines: Array) -> void:
	await dialog.say(lines)


# ================================================================== cầu cá tra

func _fish_house() -> Dictionary:
	var done: bool = Activities.is_done(&"fish")
	var options: Array = ["Cho cá ăn", "Kéo vó bắt cá tra" + (" (mai quay lại)" if done else ""), "Thôi"]
	var details: Array = ["Vãi cám cho cá tra đớp – chơi hoài được.",
		"Ba lần kéo vó; bắt được con nào Chú Sáu mua con đó %s." % GameState.money_text(Activities.FISH_PRICE), ""]
	var pick: int = await dialog.choose("Chú Sáu", "Ra cầu ván chơi hả con? Ván chắc lắm, cứ đi tự nhiên. Cá tra nhà chú đói rồi đó.", options, details)
	if pick == 0:
		var game: Node = FishGame.new()
		game.set("mode", FishGame.MODE_FEED)
		var fed: Dictionary = await _play(game)
		fed["kind"] = &"feed"
		if not bool(fed["cancelled"]):
			await _say([["", "Cá tra trồi lên đớp mồi lách tách, nước văng tung tóe. Coi đã con mắt!"]])
		return fed
	if pick != 1:
		return {"cancelled": true}
	if done:
		await _say([["Chú Sáu", "Hôm nay kéo một lần thôi con, để cá nó còn lớn. Mai ghé nghen."]])
		return {"cancelled": true, "limited": true}
	var game: Node = FishGame.new()
	game.set("mode", FishGame.MODE_NET)
	var result: Dictionary = await _play(game)
	if bool(result["cancelled"]):
		await _say([["Chú Sáu", "Thôi hả? Bữa nào rảnh ra kéo tiếp nghen."]])
		return result
	Activities.mark_done(&"fish")
	var caught: int = int(result["fish"])
	Activities.total_fish += caught
	if caught == 0:
		await _say([["Chú Sáu", "Hụt hết trơn! Kéo vó phải canh cá lội ngay giữa vó mới dính. Mai thử lại nghen."]])
		result["reward"] = {}
		return result
	var reward: Dictionary = Activities.grant(caught * Activities.FISH_PRICE, 0)
	result["reward"] = reward
	await _say([["Chú Sáu", "Được %d con cá tra, mập ú! Chú mua lại hết nghen, %s đây con." % [caught, GameState.money_text(int(reward["money"]))]],
		["", "Nhận %s." % Activities.reward_text(reward)]])
	return result


# ================================================================== ruộng lúa chín

func _farm() -> Dictionary:
	if Activities.is_done(&"farm"):
		await _say([["Cô Năm", "Hôm nay con gặt phụ cô rồi, nghỉ cho khỏe đi con. Mai lúa còn chín nữa."]])
		return {"cancelled": true, "limited": true}
	var prompt: String = "Lúa chín rộ mà thiếu người gặt quá trời. Con gặt phụ cô một hàng hông? Cô trả công, còn cho lúa về cho gà ăn."
	if not Activities.has_chicken():
		prompt = "Lúa chín rộ mà thiếu người gặt quá trời. Con gặt phụ cô một hàng hông? Cô trả công cho."
	var pick: int = await dialog.choose("Cô Năm", prompt, ["Dạ, con gặt phụ cô!", "Thôi, để bữa khác"],
		["Gặt một hàng %d bụi trong %d giây: %s mỗi bó." % [HarvestGame.TUFTS, int(HarvestGame.TIME_LIMIT), GameState.money_text(Activities.RICE_MONEY_PER_BUNDLE)], ""])
	if pick != 0:
		return {"cancelled": true}
	await _say([["Cô Năm", "Cầm cây liềm nè. Nắm gọn bụi lúa rồi phạt một cái cho ngọt, đừng có giựt nghen!"]])
	var result: Dictionary = await _play(HarvestGame.new())
	if bool(result["cancelled"]):
		await _say([["Cô Năm", "Mỏi tay rồi hả? Thôi nghỉ đi con, bữa khác gặt tiếp."]])
		return result
	Activities.mark_done(&"farm")
	var bundles: int = int(result["bundles"])
	Activities.total_bundles += bundles
	var reward: Dictionary = Activities.grant(bundles * Activities.RICE_MONEY_PER_BUNDLE, bundles * Activities.RICE_EXP_PER_BUNDLE)
	result["reward"] = reward
	var lines: Array = []
	if bundles >= HarvestGame.TUFTS:
		lines.append(["Cô Năm", "Trời đất, gặt sạch hàng luôn! Tay nghề vầy đi gặt mướn được rồi đó con."])
	elif bundles > 0:
		lines.append(["Cô Năm", "Được %d bó, khá lắm! Lần đầu cầm liềm mà vậy là giỏi." % bundles])
	else:
		lines.append(["Cô Năm", "Hổng sao, gặt lúa cũng phải tập. Mai ra cô chỉ tiếp."])
	if bundles > 0:
		var text: String = "Nhận %s." % Activities.reward_text(reward)
		if Activities.has_chicken():
			text += " %s mổ lúa ngon lành." % GameState.chicken_name
		else:
			text += " (Có gà rồi thì lúa này cho gà ăn, tăng EXP.)"
		lines.append(["", text])
	await _say(lines)
	return result


# ================================================================== trường học

func _school() -> Dictionary:
	if Activities.is_done(&"school"):
		await _say([["Cô Hạnh", "Hôm nay cô đố rồi. Mai ghé, cô đố câu khác nghen."]])
		return {"cancelled": true, "limited": true}
	var pick: int = await dialog.choose("Cô Hạnh",
		"Ủa, %s! Chủ nhật mà cũng ghé trường hả con? Vô đây cô đố ba câu, trả lời đúng cô thưởng." % GameState.player_name,
		["Dạ, cô đố đi!", "Dạ thôi, con đi chơi"],
		["Mỗi câu đúng: %s%s." % [GameState.money_text(Activities.QUIZ_MONEY_PER_RIGHT),
			(" + %d EXP cho gà" % Activities.QUIZ_EXP_PER_RIGHT) if Activities.has_chicken() else ""], ""])
	if pick != 0:
		return {"cancelled": true}
	var page: Node = QuizPage.new()
	page.call("setup_school", SchoolQuiz.build(Activities.rng))
	var result: Dictionary = await _play(page)
	if bool(result["cancelled"]):
		await _say([["Cô Hạnh", "Bận hả con? Thôi bữa khác ghé cô đố tiếp."]])
		return result
	Activities.mark_done(&"school")
	var right: int = int(result["right"])
	var reward: Dictionary = Activities.grant(right * Activities.QUIZ_MONEY_PER_RIGHT, right * Activities.QUIZ_EXP_PER_RIGHT)
	result["reward"] = reward
	var verdict: String = ["Hổng sao, về đọc sách thêm nghen con.", "Được một câu, ráng lên con!",
		"Hai câu đúng, giỏi!", "Đúng hết ba câu! Học trò cưng của cô đây rồi."][clampi(right, 0, 3)]
	var lines: Array = [["Cô Hạnh", "Con trả lời đúng %d/%d câu. %s" % [right, SchoolQuiz.COUNT, verdict]]]
	if right > 0:
		lines.append(["", "Nhận %s." % Activities.reward_text(reward)])
	await _say(lines)
	return result


# ================================================================== công trường

func _site() -> Dictionary:
	if Activities.is_done(&"site"):
		await _say([["Thợ hồ", "Hết ca rồi con. Mai ghé phụ tiếp nghen, công trường còn lâu mới xong."]])
		return {"cancelled": true, "limited": true}
	var pick: int = await dialog.choose("Thợ hồ",
		"Phụ hồ hông con? Một ca tám chục ngàn đó. Tung %d cữ gạch lên giàn giáo cho chú chụp, trong %d giây." % [Activities.BRICK_TARGET, int(BrickGame.TIME_LIMIT)],
		["Làm một ca!", "Thôi, để bữa khác"],
		["Đủ %d cữ: %s. Thiếu thì %s mỗi cữ." % [Activities.BRICK_TARGET, GameState.money_text(Activities.BRICK_FULL_PAY), GameState.money_text(Activities.BRICK_PARTIAL_PAY)], ""])
	if pick != 0:
		return {"cancelled": true}
	var game: Node = BrickGame.new()
	game.set("target", Activities.BRICK_TARGET)
	var result: Dictionary = await _play(game)
	if bool(result["cancelled"]):
		await _say([["Thợ hồ", "Bỏ ngang hả con? Thôi, bữa nào rảnh làm tiếp. Gạch nặng lắm, hông trách."]])
		return result
	Activities.mark_done(&"site")
	var bricks: int = int(result["bricks"])
	Activities.total_bricks += bricks
	var pay: int = Activities.BRICK_FULL_PAY if bool(result["full"]) else bricks * Activities.BRICK_PARTIAL_PAY
	var reward: Dictionary = Activities.grant(pay, 0)
	result["reward"] = reward
	var line: String = "Được %d cữ, hông đủ ca nhưng chú vẫn tính công cho con." % bricks
	if bool(result["full"]):
		line = "Đủ ca rồi! Tung gạch ngọt dữ ha. Tám chục ngàn đây, cầm lấy mua cám cho gà."
	var lines: Array = [["Thợ hồ", line]]
	if pay > 0:
		lines.append(["", "Nhận %s." % Activities.reward_text(reward)])
	await _say(lines)
	return result


# ================================================================== đền làng

func _temple() -> Dictionary:
	var pick: int = await dialog.choose("Ông từ", "Con vô thắp nhang hả? Đền này thờ vua Hùng, linh lắm đó nghen.",
		["Thắp nhang, xin xăm", "Hỏi chuyện gà chín cựa", "Thôi"],
		["Thắp ba nén nhang rồi xin một quẻ xăm (mỗi ngày một quẻ).", "", ""])
	if pick == 1:
		await _say([["Ông từ", "Đền làng này thờ vua Hùng. Tới lễ hội, người ta kể chuyện gà chín cựa cả đêm hông hết."],
			["", "Bạn nhớ tới lời ông nội… (Lễ hội đền Vua Hùng: Act 3)"]])
		return {"cancelled": true}
	if pick != 0:
		return {"cancelled": true}
	var result: Dictionary = {"cancelled": false, "reward": {}}
	var who: String = GameState.chicken_name if Activities.has_chicken() else "cả nhà"
	if Activities.is_done(&"temple"):
		# Đã xin quẻ hôm nay: chỉ thắp nhang ngay trước đền (không mở trang).
		air_fx.smoke(URN_TOP, 8)
		fx.emit(&"incense", URN_TOP)
		await _say([["", "Bạn thắp ba nén nhang, khấn vái cho %s mạnh giỏi, đá đâu thắng đó." % who]])
		await _give_temple_gift(result)
		await _say([["Ông từ", "Mỗi ngày xin một quẻ thôi con, xin hoài thần linh quở à nghen."]])
		result["limited"] = true
		return result
	var game: Node = TempleGame.new()
	game.set("fortune", FORTUNES[Activities.rng.randi_range(0, FORTUNES.size() - 1)])
	game.set("prayer", who)
	var page: Dictionary = await _play(game)
	if bool(page["cancelled"]):
		await _say([["Ông từ", "Ừ, lúc nào lòng yên thì vô thắp nhang cũng được con."]])
		return page
	Activities.mark_done(&"temple")
	var fortune: String = String(page["fortune"])
	result["fortune"] = fortune
	result["incense"] = int(page.get("incense", 3))
	await _give_temple_gift(result)
	await _say([["Ông từ", "Quẻ của con nè: «%s» Nhớ lấy mà làm nghen." % fortune]])
	return result


func _give_temple_gift(result: Dictionary) -> void:
	if Activities.temple_gift_taken:
		return
	Activities.temple_gift_taken = true
	var gift: Dictionary = Activities.grant(Activities.TEMPLE_FIRST_GIFT, 0)
	result["reward"] = gift
	await _say([["Ông từ", "Con nhỏ mà có lòng quá. Nè, lộc đền, cầm lấy mua cám cho gà."], ["", "Nhận %s." % Activities.reward_text(gift)]])


# ================================================================== vé số

func _lottery() -> Dictionary:
	var seller: String = "Cô bán vé số"
	var result: Dictionary = {"cancelled": false, "won": 0, "reward": {}}
	if Activities.lottery_result_ready():
		var ticket: String = Activities.lottery_ticket
		var won: int = Activities.draw_lottery()
		result["won"] = won
		await _say([[seller, "Vé số %s bữa trước của con nè. Cào bảng kết quả coi trúng hông nghen!" % ticket]])
		var check: Node = LotteryGame.new()
		check.set("mode", LotteryGame.MODE_CHECK)
		check.set("ticket", ticket)
		check.set("won", won)
		check.set("rng_seed", Activities.rng.randi())
		await _play(check) # bỏ ngang thì kết quả vẫn vậy (vé đã xổ)
		if won > 0:
			var reward: Dictionary = Activities.grant(won, 0)
			result["reward"] = reward
			var text: String = "Trời ơi trúng rồi con ơi! Giải khuyến khích!" if won >= Activities.LOTTERY_PRIZE else "Trúng an ủi, cô hoàn lại tiền vé nè."
			await _say([[seller, text], ["", "Nhận %s." % Activities.reward_text(reward)]])
		else:
			await _say([[seller, "Trật lất rồi con. Thôi, của đi thay người, hên xui mà."]])
	if Activities.is_done(&"lottery"):
		if Activities.lottery_ticket != "":
			await _say([[seller, "Mai mới xổ con ơi. Ngủ một giấc rồi ghé cô dò cho nghen."]])
		else:
			await _say([[seller, "Hôm nay con mua rồi, một tờ thôi cho vui. Mai ghé nghen."]])
		result["cancelled"] = true
		return result
	var pick: int = await dialog.choose(seller, "Vé số đây! Mua một tờ hông con? Mai xổ, hên thì có tiền mua lúa cho gà.",
		["Mua một tờ (%s)" % GameState.money_text(Activities.LOTTERY_PRICE), "Thôi cô"],
		["Mỗi ngày một tờ, tự lựa số. Ngủ một giấc (ngày mới) rồi quay lại dò.", ""])
	if pick != 0:
		result["cancelled"] = true
		return result
	if GameState.money < Activities.LOTTERY_PRICE:
		await _say([[seller, "Thôi để dành tiền đi con, bữa nào dư hẵng mua."]])
		result["cancelled"] = true
		return result
	var buy: Node = LotteryGame.new()
	buy.set("mode", LotteryGame.MODE_BUY)
	buy.set("rng_seed", Activities.rng.randi())
	var picked: Dictionary = await _play(buy)
	if bool(picked["cancelled"]):
		await _say([[seller, "Hổng lựa được số nào ưng hả? Thôi mai ghé nghen."]])
		result["cancelled"] = true
		return result
	GameState.money -= Activities.LOTTERY_PRICE
	var number: String = Activities.buy_lottery_ticket(String(picked.get("ticket", "")))
	result["ticket"] = number
	fx.emit(&"ticket", world.player.position)
	await _say([[seller, "Số %s nè. Hên xui nghen con, mai dò!" % number]])
	return result


# ================================================================== lớp học THPT (game/story)

## Hai tiết sáng (GDD 6): GameState.perform(&"class") cộng +10 Technology và trừ 3 giờ; mỗi câu đúng +2 Technology.
## Mỗi ngày một lần; ghi chuyên cần cho Mẹ (LifeState.attended). Kiểm buổi/ngày do game/story/story_life.gd lo.
func _thpt_class() -> Dictionary:
	if Activities.is_done(&"thpt"):
		await _say([[ClassQuiz.TEACHER, "Hôm nay em học rồi mà. Về nhà làm bài tập đi em."]])
		return {"cancelled": true, "limited": true}
	var done: Dictionary = GameState.perform(&"class")
	if not bool(done["ok"]):
		await _say([[ClassQuiz.TEACHER, String(done["reason"])]])
		return {"cancelled": true}
	Activities.mark_done(&"thpt")
	if not LifeState.attended.has(GameState.day):
		LifeState.attended.append(GameState.day)
	var page: Node = QuizPage.new()
	var plan: Dictionary = ClassQuiz.build(Activities.rng)
	page.call("setup_class", plan)
	var result: Dictionary = await _play(page)
	# Đã vô lớp (giờ + chuyên cần đã tính): bỏ ngang giữa chừng thì chỉ mất điểm câu hỏi.
	result["cancelled"] = false
	result["subjects"] = plan["subjects"]
	result["total"] = int(result.get("total", (plan["questions"] as Array).size()))
	var bonus: int = int(result.get("right", 0)) * ClassQuiz.TECH_PER_RIGHT
	GameState.technology += bonus
	result["technology"] = int(done["technology"]) + bonus
	result["minutes"] = int(done["minutes"])
	await _say([[ClassQuiz.TEACHER, "Hết giờ! Em trả lời đúng %d/%d câu." % [int(result.get("right", 0)), int(result["total"])]],
		["", "Đi học 2 tiết: +%d Technology (%d tiết × 5 + %d câu đúng × %d). Technology đổi Biotech ở bàn học trong nhà." % [
			int(result["technology"]), 2, int(result.get("right", 0)), ClassQuiz.TECH_PER_RIGHT]]])
	return result


# ================================================================== nghề làm thêm (game/story)

## Bán cơm (70.000đ) / chở ghe (100.000đ) × hệ số tay nghề 0,5–1,3 qua GameState.perform; mỗi ngày một ca.
func _job(id: StringName) -> Dictionary:
	var boat: bool = id == &"job_boat"
	var boss: String = "Chú Bảy" if boat else "Bà Lan"
	var activity: StringName = &"work_boat" if boat else &"work_shop"
	var info: Dictionary = Calendar.ACTIVITIES[activity]
	if Activities.is_done(id):
		await _say([[boss, "Hôm nay con làm một ca rồi, nghỉ đi con. Mai ghé." if not boat else "…Mai chạy tiếp. Ghe cũng cần nghỉ."]])
		return {"cancelled": true, "limited": true}
	if not GameState.can_spend(int(info["minutes"])):
		await _say([[boss, "Trễ quá rồi con, hổng đủ giờ làm một ca (2 tiếng). Mai ghé sớm nghen."]])
		return {"cancelled": true}
	var game: Node = BoatGame.new() if boat else SalesGame.new()
	game.set("rng_seed", Activities.rng.randi())
	var result: Dictionary = await _play(game)
	if bool(result["cancelled"]):
		await _say([[boss, "Bỏ ngang hả con? Thôi, bữa khác làm tiếp." if not boat else "…Ghe để đó. Bữa khác chạy."]])
		return result
	var done: Dictionary = GameState.perform(activity, float(result["factor"]))
	if not bool(done["ok"]):
		await _say([[boss, String(done["reason"])]])
		result["cancelled"] = true
		return result
	Activities.mark_done(id)
	result["money"] = int(done["money"])
	result["minutes"] = int(done["minutes"])
	var verdict: String
	if boat:
		verdict = "Đủ năm bao, hổng rớt bao nào! Tay lái lụa." if int(result["cargo"]) >= BoatGame.CARGO \
			else "Còn %d bao. Rớt vài bao… thôi, cá nó ăn cũng được." % int(result["cargo"])
	else:
		verdict = "Bán đắt như tôm tươi! Bà mà có đứa cháu như con là khỏe re." if int(result["served"]) >= SalesGame.TARGET \
			else "Được %d khách. Lần sau lanh tay hơn chút nghen." % int(result["served"])
	await _say([[boss, verdict], ["", "Nhận %s (hệ số tay nghề ×%s). Tốn 2 giờ." % [GameState.money_text(int(done["money"])),
		String.num(float(result["factor"]), 2).replace(".", ",")]]])
	return result


# ================================================================== trò phụ: câu cá lóc (bờ kênh)

func _fishing() -> Dictionary:
	var who: String = "Ông câu cá"
	if Activities.is_done(&"cau_ca_loc"):
		await _say([[who, "Hôm nay câu vậy đủ rồi con, để cá nó sanh sôi. Mai ra ngồi với ông."]])
		return {"cancelled": true, "limited": true}
	var pick: int = await dialog.choose(who, "Ngồi câu cá lóc với ông hông? Mồi nhái sẵn đây. Cá lóc khôn lắm, phải canh phao cho kỹ.",
		["Dạ, con câu thử!", "Thôi ông"],
		["%d lần thả câu; cá lóc dính câu ông mua %s mỗi con." % [FishingGame.CASTS, GameState.money_text(Activities.LOC_PRICE)], ""])
	if pick != 0:
		return {"cancelled": true}
	var game: Node = FishingGame.new()
	game.set("rng_seed", Activities.rng.randi())
	var result: Dictionary = await _play(game)
	if bool(result["cancelled"]):
		await _say([[who, "Câu cá phải nhẫn nại con à. Bữa khác ra ngồi tiếp."]])
		return result
	Activities.mark_done(&"cau_ca_loc")
	var caught: int = int(result["fish"])
	var reward: Dictionary = Activities.grant(caught * Activities.LOC_PRICE, 0)
	result["reward"] = reward
	if caught == 0:
		await _say([[who, "Hổng con nào hết! Phao chìm hẳn mới giựt nghen, giựt sớm là cá nó chạy."]])
		return result
	await _say([[who, "%d con cá lóc đồng, nướng trui là hết sẩy! Ông lấy hết, tiền đây con." % caught],
		["", "Nhận %s." % Activities.reward_text(reward)]])
	return result


# ================================================================== trò phụ: thả diều (bờ đê ruộng)

func _kite() -> Dictionary:
	var who: String = "Tèo"
	if Activities.is_done(&"tha_dieu"):
		await _say([[who, "Diều tao rách một miếng rồi, mai dán lại rồi thả tiếp nghen mậy."]])
		return {"cancelled": true, "limited": true}
	var pick: int = await dialog.choose(who, "Gió chiều lên rồi! Thả con diều sáo của tao hông? Lượn qua mấy luồng gió là nó kêu vi vu đã lắm.",
		["Thả diều!", "Thôi"],
		["Lái diều đón luồng gió (mỗi 3 luồng +1 Technology, tối đa %d). Coi chừng đàn cò." % Activities.KITE_TECH_MAX, ""])
	if pick != 0:
		return {"cancelled": true}
	var game: Node = KiteGame.new()
	game.set("rng_seed", Activities.rng.randi())
	var result: Dictionary = await _play(game)
	if bool(result["cancelled"]):
		await _say([[who, "Thu dây rồi hả? Bữa khác thả tiếp."]])
		return result
	Activities.mark_done(&"tha_dieu")
	var tech: int = Activities.kite_technology(int(result["rings"]))
	GameState.technology += tech
	result["technology"] = tech
	var line: String = "Diều lên cao vút luôn! Mày thả diều giỏi hơn tao rồi đó." if tech >= Activities.KITE_TECH_MAX \
		else "Được %d luồng gió. Diều sáo kêu vi vu nghe đã ghê!" % int(result["rings"])
	var lines: Array = [[who, line]]
	if tech > 0:
		lines.append(["", "Hiểu thêm về gió và lực nâng: +%d Technology." % tech])
	await _say(lines)
	return result
