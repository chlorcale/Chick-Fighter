extends RefCounted

## CỬA HÀNG (GDD 6 "Chợ", 7.1–7.2): một luồng mua bán dùng chung (DialogBox.choose + dòng mô tả) cho tiệm tạp hóa
## Cô Ba, bốn sạp chợ (đồ nghề, trứng, lúa cám, gà giống) và xe khô gà Lão Gà Khô (bán Khô Gà 50.000đ/kg, đồ độc quyền tính bằng
## Khô Gà). Dòng hàng ghi số đang có (kho + đang gắn) và món gà đang chọn gắn ở ô đó; mua xong nhắc "về nhà ra chuồng
## gà để gắn" (Act 1: ô trống thì Cô Ba gắn giùm luôn như cũ). Giảm giá: thân Cô Ba (−10%), quen Chú Mười (sạp đồ
## nghề −10%), chợ phiên Thứ 7/CN (−10% sạp lúa cám, đồ nghề; Trứng lạ chỉ bán cuối tuần). Mua sắm chỉ tốn 5 phút.
## main.gd giữ một thể hiện: shops = StoryShops.new(self).

const LifeState := preload("res://game/sim/life_state.gd")
const Items := preload("res://game/data/items.gd")
const Breeds := preload("res://game/data/breeds.gd")
const Audio := preload("res://game/audio/audio_director.gd")

const SHOP_MINUTES: int = 5
const DISCOUNT: float = 0.10
## Người bán ở xe khô gà (tên người nói trong hội thoại, có chân dung game/art/npc/lao_ga_kho.png).
const LAO_GA_KHO: String = "Lão Gà Khô"
const KEEPERS: Dictionary = {
	&"co_ba": "Cô Ba", &"market_gear": "Cô Tám đồ nghề", &"market_eggs": "Chị Hai bán trứng",
	&"market_food": "Chú Ba gạo", &"market_chicken": "Anh Út gà giống", &"cat_shop": LAO_GA_KHO,
}
const TAPE_PRICE: int = 20000

var main: Node
var _bought: bool = false


func _init(p_main: Node) -> void:
	main = p_main


func _dialog() -> DialogBox:
	return main.get("dialog") as DialogBox


func open(id: StringName) -> void:
	if not KEEPERS.has(id):
		return
	if not await main.life.gate(id, String(KEEPERS[id])):
		return
	_bought = false
	await main.life.tutorial("shop")
	match id:
		&"co_ba":
			await co_ba()
		&"market_gear":
			await market_gear()
		&"market_eggs":
			await market_eggs()
		&"market_food":
			await market_food()
		&"market_chicken":
			await market_chicken()
		&"cat_shop":
			await cat_shop()
	if _bought:
		GameState.spend_time(SHOP_MINUTES)


static func weekend_sale() -> bool:
	return GameState.is_weekend()


# =================================================================== dòng hàng

static func owned_text(id: StringName) -> String:
	if Items.is_equipment(id):
		return " (có %d)" % GameState.owned_total(id)
	return " (kho %d)" % GameState.item_count(id)


static func price_of(id: StringName, qty: int, discount: float) -> float:
	var info: Dictionary = Items.get_item(id)
	var base: float = float(info.get("price", 0)) * float(qty)
	if StringName(info.get("currency", &"money")) == &"kho_ga":
		return base
	return roundf(base * (1.0 - discount))


static func price_label(id: StringName, qty: int, discount: float) -> String:
	if StringName(Items.get_item(id).get("currency", &"money")) == &"kho_ga":
		return Items.price_text(id) if qty == 1 else "%s kg Khô Gà" % String.num(price_of(id, qty, 0.0), 2)
	var text: String = GameState.money_text(int(price_of(id, qty, discount)))
	return text + (" (−%d%%)" % int(round(discount * 100.0)) if discount > 0.0 else "")


## Mô tả món: hiệu ứng + ô của gà đang chọn đang gắn gì.
static func detail_of(id: StringName) -> String:
	var info: Dictionary = Items.get_item(id)
	var text: String = String(info.get("text", ""))
	var slot: StringName = Items.slot_of(id)
	if Items.is_equipment(id):
		var cur: StringName = GameState.equipped(GameState.active, slot)
		text += " · Ô %s của %s: %s" % [String(Items.SLOT_NAMES.get(slot, "?")), GameState.chicken_name,
			Items.display_name(cur) if cur != &"" else "trống"]
	return text


## Mua qty món với giảm giá (tiền); Khô Gà không giảm. Trả về true nếu mua được (last_error giữ lý do).
static func buy(id: StringName, qty: int, discount: float) -> bool:
	var info: Dictionary = Items.get_item(id)
	if StringName(info.get("currency", &"money")) == &"kho_ga" or discount <= 0.0:
		return GameState.buy(id, qty)
	var full: int = int(info["price"]) * qty
	var pay: int = int(price_of(id, qty, discount))
	if GameState.money < pay:
		GameState.last_error = "Không đủ tiền (cần %s)." % GameState.money_text(pay)
		return false
	var rebate: int = full - pay
	GameState.money += rebate
	if not GameState.buy(id, qty):
		GameState.money -= rebate
		return false
	return true


## Vòng lặp một tiệm bán đồ. extra: các lựa chọn riêng [{label, detail, key}] – trả key được chọn cho nơi gọi (""
## nếu thoát). bulk: [id, số lượng] bán theo bao lớn.
func item_shop(keeper: String, greeting: String, stock: Array[StringName], discount: float, bulk: Array = [],
		extra: Array = []) -> String:
	var dlg: DialogBox = _dialog()
	while true:
		var options: Array = []
		var details: Array = []
		var actions: Array = []
		for id in stock:
			options.append("%s · %s%s" % [Items.display_name(id), price_label(id, 1, discount), owned_text(id)])
			details.append(detail_of(id))
			actions.append([id, 1])
		for b in bulk:
			var bid: StringName = b[0]
			var qty: int = int(b[1])
			options.append("%s ×%d (bao lớn) · %s%s" % [Items.display_name(bid), qty, price_label(bid, qty, discount + 0.1), owned_text(bid)])
			details.append("Mua sỉ rẻ hơn 10%%. %s" % String(Items.get_item(bid).get("text", "")))
			actions.append([bid, qty, 0.1])
		for e in extra:
			options.append(String(e["label"]))
			details.append(String(e.get("detail", "")))
			actions.append(String(e["key"]))
		options.append("Thôi")
		details.append("")
		actions.append("exit")
		var wallet: String = "Con đang có %s" % GameState.money_text(GameState.money)
		if GameState.kho_ga > 0.0:
			wallet += " · %s kg Khô Gà" % String.num(GameState.kho_ga, 2)
		var pick: int = await dlg.choose(keeper, "%s %s." % [greeting, wallet], options, details)
		var action: Variant = actions[pick]
		if action is String:
			return "" if action == "exit" else String(action)
		var id: StringName = action[0]
		var qty: int = int(action[1])
		var disc: float = discount + (float(action[2]) if (action as Array).size() > 2 else 0.0)
		if not buy(id, qty, disc):
			await dlg.say([[keeper, "Thiếu rồi con ơi: %s" % GameState.last_error]])
			continue
		_bought = true
		await _after_buy(keeper, id, qty)
		main.call("_refresh_status")
	return ""


func _after_buy(keeper: String, id: StringName, qty: int) -> void:
	var dlg: DialogBox = _dialog()
	var name: String = Items.display_name(id)
	if Items.is_equipment(id):
		var slot: StringName = Items.slot_of(id)
		# Act 1: ô trống thì gắn giùm luôn (giữ cảm giác cũ của tiệm Cô Ba).
		if GameState.current_act() < 2 and GameState.equipped(GameState.active, slot) == &"":
			GameState.equip(GameState.active, slot, id)
			await dlg.say([[keeper, "%s đây. Cô gắn giùm %s luôn nè – ngó oai liền hà! (Muốn đổi thì về nhà ra chuồng gà.)" % [name, GameState.chicken_name]]])
		else:
			await dlg.say([[keeper, "%s đây con. Về nhà ra chuồng gà để gắn cho gà nghen (hoặc thay ở màn chuẩn bị trước trận)." % name]])
	elif Items.is_egg(id):
		await dlg.say([[keeper, "%s đây, cầm nhẹ tay nghen. Về nhà bỏ vô lò ấp, nhớ kèm Biotech." % name]])
		await main.life.tutorial("eggs")
	else:
		await dlg.say([[keeper, "%s ×%d đây con. Về nhà ra chuồng gà cho ăn nghen." % [name, qty]]])


# =================================================================== từng tiệm

func co_ba() -> void:
	if GameState.stage < GameState.Stage.PREPARE:
		await _dialog().say([["Cô Ba", "Chưa có giải mà mua đồ chi con. Chừng nào chú Tư cho đá giải rồi ghé cô nghen."]])
		return
	var discount: float = DISCOUNT if LifeState.has("discount_co_ba") else 0.0
	while true:
		var key: String = await item_shop("Cô Ba", "Vô đây con! Đồ cho chiến kê cô có đủ, giá phải chăng." if discount <= 0.0
			else "Mối ruột tới rồi! Cô bớt mười phần trăm nghen.", GameState.shop_stock(&"co_ba"), discount, [],
			[{"label": "Hỏi chuyện Cô Ba (15 phút)", "detail": "Thân thiết với Cô Ba: %s" % main.life.hearts(LifeState.aff("co_ba")), "key": "chat"}])
		if key == "chat":
			await main.life.chat(&"co_ba")
			if LifeState.has("discount_co_ba"):
				discount = DISCOUNT
			continue
		return


func market_gear() -> void:
	var stock: Array[StringName] = []
	for id in GameState.shop_stock(&"cho"):
		if Items.is_equipment(id):
			stock.append(id)
	if stock.is_empty():
		await _dialog().say([["Cô Tám đồ nghề", "Đồ đồng, đồ thép cho gà Liên tỉnh chưa về con ơi. Ghé tiệm Cô Ba bên xóm mua đồ tre, đồ sắt trước đi."]])
		return
	var discount: float = (DISCOUNT if LifeState.has("discount_market") else 0.0) + (DISCOUNT if weekend_sale() else 0.0)
	var greet: String = "Đồ nghề cho gà đá đây! Mũ đồng, giáp đồng, cựa bạc, toàn đồ thiệt."
	if weekend_sale():
		greet += " Chợ phiên cuối tuần, bớt mười phần trăm!"
	if LifeState.has("discount_market"):
		greet += " Người quen chú Mười hả? Bớt thêm cho nè."
	await item_shop("Cô Tám đồ nghề", greet, stock, discount)


func market_eggs() -> void:
	var dlg: DialogBox = _dialog()
	var stock: Array[StringName] = []
	for id in GameState.shop_stock(&"cho"):
		if Items.is_egg(id) and (id != &"trung_la" or weekend_sale()):
			stock.append(id)
	if stock.is_empty():
		await dlg.say([["Chị Hai bán trứng", "Trứng gà đá giống hiếm phải đặt từ xa, chừng nào em lên Liên tỉnh chị mới lấy hàng về. Giờ chị bán trứng vịt luộc thôi hà!"]])
		return
	var greet: String = "Trứng gà giống nè em! Ấp ra gà con, nuôi lớn thành chiến kê."
	if weekend_sale():
		greet += " Cuối tuần có Trứng lạ – hổng biết gà gì, hên thì ra Đông Tảo!"
	else:
		greet += " (Trứng lạ chỉ có Thứ Bảy, Chủ nhật.)"
	while true:
		var key: String = await item_shop("Chị Hai bán trứng", greet, stock, 0.0, [],
			[{"label": "Hỏi: ấp trứng làm sao?", "detail": "", "key": "how"}])
		if key != "how":
			return
		await dlg.say([["Chị Hai bán trứng", "Đem về bỏ vô lò ấp trong nhà, kèm Biotech – cái này em học ở trường mới có: đi học được Technology, mười Technology đổi một Biotech ở bàn học."],
			["Chị Hai bán trứng", "Bỏ dư Biotech thì gà con dễ có đột biến lắm nghen. Vài ngày là nở, nhớ chuồng còn chỗ."]])
		await main.life.tutorial("eggs")


func market_food() -> void:
	var stock: Array[StringName] = []
	for id in GameState.shop_stock(&"cho"):
		if Items.is_food(id):
			stock.append(id)
	var discount: float = DISCOUNT if weekend_sale() else 0.0
	var greet: String = "Lúa, cám đủ hết! Mua bao lớn rẻ hơn nghen con."
	if weekend_sale():
		greet = "Chợ phiên cuối tuần! Lúa cám bớt mười phần trăm."
	await item_shop("Chú Ba gạo", greet, stock, discount, [[&"lua", 5], [&"cam", 3]])


func market_chicken() -> void:
	var dlg: DialogBox = _dialog()
	var who: String = "Anh Út gà giống"
	while true:
		var options: Array = []
		var details: Array = []
		var actions: Array = []
		for b in range(Breeds.count()):
			options.append("Mua %s Lv1 · %s" % [Breeds.display_name(b), GameState.money_text(Breeds.price(b))])
			var lock: String = "" if GameState.current_act() >= int(Breeds.info(b)["unlock"]) else " (Act %d mới bán)" % int(Breeds.info(b)["unlock"])
			details.append("%s%s · Chuồng: %d/%d con." % [String(Breeds.info(b)["passive_text"]), lock, GameState.chickens.size(), GameState.coop_capacity()])
			actions.append(["buy", b])
		for i in range(GameState.chickens.size()):
			var c: Dictionary = GameState.chickens[i]
			options.append("Bán %s (%s Lv%d) · %s" % [String(c["name"]), Breeds.display_name(int(c["breed"])), int(c["level"]),
				GameState.money_text(GameState.sell_price(i))])
			details.append("Giá theo cấp, số trận thắng, danh hiệu, đột biến. Đồ đang gắn trở về kho." if GameState.chickens.size() > 1
				else "Con gà cuối cùng thì hổng bán được.")
			actions.append(["sell", i])
		options.append("Thôi")
		details.append("")
		actions.append(["exit", 0])
		var pick: int = await dlg.choose(who, "Gà giống đây! Mua về nuôi hay bán bớt cũng được. Con đang có %s." % GameState.money_text(GameState.money), options, details)
		var a: Array = actions[pick]
		match String(a[0]):
			"buy":
				if GameState.coop_full():
					await dlg.say([[who, "Chuồng em đầy rồi (%d/%d con)! Về nhà nâng chuồng ở ô đất sân sau, hoặc bán bớt một con." % [GameState.chickens.size(), GameState.coop_capacity()]]])
					continue
				var breed: int = int(a[1])
				if GameState.current_act() < int(Breeds.info(breed)["unlock"]):
					await dlg.say([[who, "%s hiếm lắm, phải lên Liên tỉnh anh mới có hàng." % Breeds.display_name(breed)]])
					continue
				if GameState.money < Breeds.price(breed):
					await dlg.say([[who, "Thiếu tiền rồi em: con này %s." % GameState.money_text(Breeds.price(breed))]])
					continue
				var chick_name: String = await dlg.ask_name(who, "Đặt tên cho con %s mới đi em." % Breeds.display_name(breed),
					Breeds.random_name(GameState.rng))
				var index: int = GameState.buy_chicken(breed, chick_name)
				if index < 0:
					await dlg.say([[who, GameState.last_error]])
					continue
				_bought = true
				await dlg.say([[who, "Gà tốt đó! Về nhà ra chuồng chăm nó nghen. Muốn đá con này thì chọn ở chuồng hoặc màn chuẩn bị trước trận."]])
			"sell":
				var i: int = int(a[1])
				if GameState.chickens.size() <= 1:
					await dlg.say([[who, "Còn có một con mà bán sao được em!"]])
					continue
				var c2: Dictionary = GameState.chickens[i]
				var ok: int = await dlg.choose(who, "Bán %s thiệt hả? Anh trả %s." % [String(c2["name"]), GameState.money_text(GameState.sell_price(i))],
					["Bán", "Thôi, giữ lại"])
				if ok != 0:
					continue
				var got: int = GameState.sell_chicken(i)
				if got < 0:
					await dlg.say([[who, GameState.last_error]])
					continue
				_bought = true
				await dlg.say([[who, "Đây, %s. Anh nuôi nó đàng hoàng, em yên tâm." % GameState.money_text(got)]])
			_:
				return
		main.call("_refresh_status")


## Lão Gà Khô: lão mèo tam thể vừa khóc vừa cười, đẩy xe khô gà lá chanh ở Chợ Bình Kê (id cũ &"cat_shop", tiệm &"meo").
## Cơ chế giữ nguyên: bán Khô Gà 50.000đ/kg (bán hết / bán 1 kg), đồ độc quyền tính bằng Khô Gà, băng cải lương cho chú Bảy.
func cat_shop() -> void:
	var dlg: DialogBox = _dialog()
	var lao: String = LAO_GA_KHO
	await main.life.tutorial("kho_ga")
	while true:
		var extra: Array = []
		if GameState.kho_ga > 0.0:
			extra.append({"label": "Bán hết Khô Gà (%s kg → %s)" % [String.num(GameState.kho_ga, 2), GameState.money_text(int(round(GameState.kho_ga * Items.KHO_GA_PRICE_PER_KG)))],
				"detail": "Lão Gà Khô mua 50.000đ/kg.", "key": "sell_all"})
		if GameState.kho_ga >= 1.0:
			extra.append({"label": "Bán 1 kg Khô Gà (%s)" % GameState.money_text(Items.KHO_GA_PRICE_PER_KG), "detail": "Giữ lại phần còn lại để đổi đồ độc quyền.", "key": "sell_one"})
		if LifeState.quest_state("q_bang_cai_luong") == LifeState.Q_ACTIVE and int(LifeState.quest("q_bang_cai_luong")["step"]) == 0:
			extra.append({"label": "Băng cải lương «Tô Ánh Nguyệt» · %s" % GameState.money_text(TAPE_PRICE), "detail": "Chú Bảy nhờ mua.", "key": "tape"})
		extra.append({"label": "Hỏi: Khô Gà là gì?", "detail": "", "key": "what"})
		var stock: Array[StringName] = GameState.shop_stock(&"meo")
		var greet: String = "Hí hí… hu hu! Khô gà lá chanh đâyyy! (Lão cười chảy nước mắt.) Có Khô Gà hông, lão mua giá cao nè."
		if stock.is_empty():
			greet = "Hu hu… đồ độc quyền chưa về, lên Liên tỉnh rồi ghé nghen. Hí hí, mà Khô Gà thì lão vẫn mua!"
		var key: String = await item_shop(lao, greet, stock, 0.0, [], extra)
		match key:
			"sell_all", "sell_one":
				var got: int = GameState.sell_kho_ga(-1.0 if key == "sell_all" else 1.0)
				_bought = true
				Achievements.unlock(&"life_sell_kho")
				Audio.sfx(&"coin", -3.0)
				await dlg.say([[lao, "Hí hí hí! (Lão lắc hũ khô gà kêu lốc cốc, rắc thêm nhúm lá chanh.) Đây %s. Có nữa thì đẩy tới đây nghen!" % GameState.money_text(got)]])
			"tape":
				if GameState.money < TAPE_PRICE:
					await dlg.say([[lao, "Hu hu… thiếu tiền rồi con. Lão cười vậy chớ hổng bán thiếu đâu nghen."]])
					continue
				GameState.money -= TAPE_PRICE
				main.life.advance_quest("q_bang_cai_luong")
				_bought = true
				Audio.sfx(&"coin", -4.0)
				await dlg.say([[lao, "Cuộn này lão nghe hoài, tới khúc «Tô Ánh Nguyệt» là khóc ròng… hí hí, mà khóc xong lại cười. Đem cho ông già quán võng hả? Ổng ghé đây hoài mà hổng dám hỏi."],
					["", "Nhận cuộn băng cải lương. Đem về cho chú Bảy ở quán võng."]])
			"what":
				await dlg.say([[lao, "Hí hí… con gà nào già, đá hết nổi thì cho nó «về hưu» ở chuồng gà nhà con – đổi thành Khô Gà, tính theo ký."],
					[lao, "Gà nặng ký thì nhiều Khô Gà. Lão đổi lại đồ độc quyền: khăn, cánh, mào vàng… với pate ngon nhứt xóm. Thêm sợi lá chanh là hết sẩy!"],
					["", "(Lão Gà Khô vừa cười vừa lau nước mắt bằng hũ khô gà. Bạn hổng biết lão vui hay buồn, và quyết định không hỏi thêm.)"]])
			_:
				return
		main.call("_refresh_status")
