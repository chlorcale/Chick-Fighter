extends Node

## Điều phối hoạt động ở bờ nam: hội thoại trước/sau, chạy mini-game, phát thưởng, giới hạn mỗi ngày.
## main.gd chỉ gọi: await runner.run(id) với id = fish_house, farm, school, site, temple, lottery.
## Tín hiệu cho âm thanh/hiệu ứng:
##   activity_started(id), activity_finished(id, result)
##   fx(kind, world_pos) – chuyển tiếp từ mini-game (splash, catch, miss, cut, pick, drop, throw, win)
##   và của runner (incense, xam, ticket).

signal activity_started(id: StringName)
signal activity_finished(id: StringName, result: Dictionary)
signal fx(kind: StringName, world_pos: Vector2)

const Activities := preload("res://game/world/activities.gd")
const WorldFx := preload("res://game/world/world_fx.gd")
const FishGame := preload("res://game/world/minigames/fish_game.gd")
const HarvestGame := preload("res://game/world/minigames/harvest_game.gd")
const BrickGame := preload("res://game/world/minigames/brick_game.gd")
const SchoolQuiz := preload("res://game/world/minigames/school_quiz.gd")

const IDS: Array[StringName] = [&"fish_house", &"farm", &"school", &"site", &"temple", &"lottery"]
const URN_TOP: Vector2 = Vector2(900, 1002)
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
## Mini-game/câu đố đang chạy (null nếu không có).
var current_game: Node = null
var current_quiz: RefCounted = null
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
	activity_finished.emit(id, result)


## Chạy một mini-game: tắt tương tác của World, khoá nhân vật (game tự mở nếu cần), chờ kết quả.
func _play(game: Node) -> Dictionary:
	game.set("world", world)
	game.set("ground_fx", ground_fx)
	game.set("air_fx", air_fx)
	game.set("autopilot", autopilot)
	game.connect("fx", func(kind: StringName, pos: Vector2) -> void: fx.emit(kind, pos))
	add_child(game)
	current_game = game
	world.interactions_enabled = false
	world.player.can_move = false
	var result: Dictionary = await game.run()
	world.interactions_enabled = true
	world.player.can_move = false # main.gd mở lại sau hội thoại cuối
	current_game = null
	game.queue_free()
	return result


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
	world.interactions_enabled = false
	var quiz: RefCounted = SchoolQuiz.new()
	current_quiz = quiz
	var result: Dictionary = await quiz.run(dialog, Activities.rng)
	current_quiz = null
	world.interactions_enabled = true
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
		"Bốc gạch hông con? Một ca tám chục ngàn đó. Chở %d cữ gạch từ đống gạch tới chân giàn giáo, trong %d giây." % [Activities.BRICK_TARGET, int(BrickGame.TIME_LIMIT)],
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
		line = "Đủ ca rồi! Lẹ tay dữ ha. Tám chục ngàn đây, cầm lấy mua cám cho gà."
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
	air_fx.smoke(URN_TOP, 8)
	fx.emit(&"incense", URN_TOP)
	var result: Dictionary = {"cancelled": false, "reward": {}}
	var who: String = GameState.chicken_name if Activities.has_chicken() else "cả nhà"
	await _say([["", "Bạn thắp ba nén nhang, khấn vái cho %s mạnh giỏi, đá đâu thắng đó." % who]])
	if not Activities.temple_gift_taken:
		Activities.temple_gift_taken = true
		var gift: Dictionary = Activities.grant(Activities.TEMPLE_FIRST_GIFT, 0)
		result["reward"] = gift
		await _say([["Ông từ", "Con nhỏ mà có lòng quá. Nè, lộc đền, cầm lấy mua cám cho gà."], ["", "Nhận %s." % Activities.reward_text(gift)]])
	if Activities.is_done(&"temple"):
		await _say([["Ông từ", "Mỗi ngày xin một quẻ thôi con, xin hoài thần linh quở à nghen."]])
		result["limited"] = true
		return result
	Activities.mark_done(&"temple")
	var fortune: String = FORTUNES[Activities.rng.randi_range(0, FORTUNES.size() - 1)]
	result["fortune"] = fortune
	fx.emit(&"xam", URN_TOP)
	await _say([["", "Xóc xóc… xóc xóc… Một thẻ xăm rớt ra."], ["Ông từ", fortune]])
	return result


# ================================================================== vé số

func _lottery() -> Dictionary:
	var seller: String = "Cô bán vé số"
	var result: Dictionary = {"cancelled": false, "won": 0, "reward": {}}
	if Activities.lottery_result_ready():
		var ticket: String = Activities.lottery_ticket
		var won: int = Activities.draw_lottery()
		result["won"] = won
		await _say([[seller, "Vé số %s bữa trước của con nè, để cô dò coi… dò… dò…" % ticket]])
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
		["Mỗi ngày một tờ. Ngủ một giấc (ngày mới) rồi quay lại dò.", ""])
	if pick != 0:
		result["cancelled"] = true
		return result
	if GameState.money < Activities.LOTTERY_PRICE:
		await _say([[seller, "Thôi để dành tiền đi con, bữa nào dư hẵng mua."]])
		result["cancelled"] = true
		return result
	GameState.money -= Activities.LOTTERY_PRICE
	var number: String = Activities.buy_lottery_ticket()
	result["ticket"] = number
	fx.emit(&"ticket", world.player.position)
	await _say([[seller, "Số %s nè. Hên xui nghen con, mai dò!" % number]])
	return result
