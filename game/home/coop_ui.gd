extends "res://game/home/home_panel.gd"

## Bảng chăm gà (mở ở bội gà bằng E): chân dung động, tên, giống + passive, cấp/EXP/cap, Thể trạng + tâm trạng,
## thành tích, thân thiết, bảng chỉ số (đồ đạc/đột biến tô màu), và các việc: chọn gà chiến, cho ăn, vuốt ve / tắm /
## phơi nắng, tập luyện, trang bị 6 ô, đột biến (Biotech), đổi tên, bán gà, làm Khô Gà.
## Dùng: var ui = CoopUI.new(); ui.dialog = dialog; add_child(ui); var r: Dictionary = await ui.run(index); ui.queue_free()
## Kết quả: {"changed": bool (đàn gà đổi: bán/Khô Gà), "day_over": bool (luyện quá 23:00)}.

const ChickenSprite := preload("res://game/home/chicken_sprite.gd")
const HomeState := preload("res://game/home/home_state.gd")
const Items := preload("res://game/data/items.gd")
const Mutations := preload("res://game/data/mutations.gd")
const Breeds := preload("res://game/data/breeds.gd")

## Thứ tự 6 ô theo yêu cầu Owner: Vũ khí, Đầu, Mào, Giáp, Cánh, Cựa.
const SLOT_ORDER: Array[StringName] = [&"weapon", &"head", &"comb", &"armor", &"wing", &"spur"]
const STAT_ROWS: Array = [["hp", "HP"], ["atk", "ATK"], ["def", "DEF"], ["spd", "SPD"], ["weight", "Cân nặng"],
	["crit", "Chí mạng"]]
const PORTRAIT_BOX: Rect2 = Rect2(28, 82, 360, 170)
const PORTRAIT_SCALE: float = 1.6

var index: int = 0
var _portrait: Node2D
var _portrait_id: int = -1
var _portrait_sig: String = ""
## Chỉ số xem trước (đang rê trên một món đồ / đột biến) – rỗng = không xem trước.
var _preview: Dictionary = {}
var _preview_label: String = ""
var _confirm_text: String = ""
var _fx: Array = []          # hạt lúa / tim bay: [pos, vel, life, kind]
var _result: Dictionary = {"changed": false, "day_over": false}
var _last_main: int = 0


func _ready() -> void:
	super._ready()
	title = "BỘI GÀ"


## Chạy bảng cho gà ở chỉ số start_index tới khi người chơi bấm Esc / "Xong".
func run(start_index: int) -> Dictionary:
	index = clampi(start_index, 0, GameState.chickens.size() - 1)
	while not GameState.chickens.is_empty():
		index = clampi(index, 0, GameState.chickens.size() - 1)
		_refresh_portrait()
		_preview = {}
		_confirm_text = ""
		var opts: Array = _main_options()
		var r: int = await pick("Việc chăm gà", opts, Callable(), true, _last_main)
		if r == -1:
			break
		if r == -2 or r == -3:
			index = posmod(index + (-1 if r == -2 else 1), GameState.chickens.size())
			continue
		_last_main = r
		var id: StringName = StringName(opts[r]["id"])
		match id:
			&"active":
				GameState.set_active(index)
				message("%s là gà chiến rồi! Ra sới là nó đá." % _c()["name"], GOOD)
				Audio.sfx(&"rooster_crow", -8.0, 1.1)
				_play(&"happy")
			&"feed":
				await _feed_menu()
			&"pet", &"bath", &"sun":
				_care(id)
			&"train":
				await _train()
				if bool(_result["day_over"]):
					break
			&"equip":
				await _equip_menu()
			&"mutate":
				await _mutate_menu()
			&"rename":
				await _rename()
			&"sell":
				await _sell()
			&"kho_ga":
				await _kho_ga()
			&"back":
				break
	return _result


func _c() -> Dictionary:
	return GameState.chickens[index]


func _main_options() -> Array:
	var c: Dictionary = _c()
	var id: int = int(c["id"])
	var opts: Array = []
	var is_active: bool = index == GameState.active
	opts.append(opt(&"active", "★ Đang là gà chiến" if is_active else "Chọn làm gà chiến",
		"Gà chiến là con mang ra sới, ra giải.", is_active, "%s đang là gà chiến rồi." % c["name"]))
	var foods: int = _food_ids().size()
	opts.append(opt(&"feed", "Cho ăn" + (" (đã ăn bữa chính)" if bool(c["fed_today"]) else ""),
		"Lúa: bữa chính, Thể trạng về 100%. Cám, thuốc bổ: thêm EXP / Thể trạng." if foods > 0 else
		"Trong kho hết đồ ăn rồi – ghé tiệm Cô Ba mua lúa nghen."))
	for kind in HomeState.CARE_ORDER:
		var reason: String = HomeState.care_block_reason(index, kind)
		var done: bool = HomeState.care_done(id, kind)
		opts.append(opt(kind, String(HomeState.CARE[kind]["name"]) + (" ✓" if done else ""),
			"Chăm như thú cưng: +%d%% Thể trạng, thêm thân thiết. Mỗi ngày một lần." % int(HomeState.CARE[kind]["condition"]),
			reason != "", reason))
	var trained: int = int(c["trained_today"])
	opts.append(opt(&"train", "Tập luyện (1 giờ) · %d/%d" % [trained, GameState.TRAIN_PER_DAY],
		"+%d EXP, −%d%% Thể trạng, tốn 1 giờ. Cần Thể trạng từ %d%%." % [GameState.TRAIN_EXP_BASE + GameState.TRAIN_EXP_PER_LEVEL
		* int(c["level"]), int(GameState.TRAIN_CONDITION_COST), int(GameState.TRAIN_MIN_CONDITION)]))
	opts.append(opt(&"equip", "Trang bị (6 ô)", "Gắn / tháo đồ mua ở tiệm Cô Ba, chợ, xe khô gà Lão Gà Khô. Coi chỉ số trước → sau."))
	var locked: bool = GameState.current_act() < Mutations.UNLOCK_ACT
	opts.append(opt(&"mutate", "Đột biến (Biotech)", "Đổi Biotech lấy đột biến – có lợi có hại, VĨNH VIỄN.",
		locked, "Biotech mở ở Act 2 (sau khi vô địch Ao Làng)."))
	opts.append(opt(&"rename", "Đổi tên", "Đặt tên mới cho %s." % c["name"]))
	var last: bool = GameState.chickens.size() <= 1
	opts.append(opt(&"sell", "Bán gà · %s" % GameState.money_text(GameState.sell_price(index)),
		"Bán cho lái gà. Giá theo giống, cấp, số trận thắng, danh hiệu, đột biến. Đồ đang gắn tự tháo về kho.",
		last, "Còn mỗi con này, bán rồi lấy gì đá!"))
	opts.append(opt(&"kho_ga", "Làm Khô Gà · %s kg" % _kg_text(GameState.kho_ga_yield(index)),
		"VĨNH VIỄN: con gà thành Khô Gà, đem bán xe khô gà Lão Gà Khô ngoài chợ 50.000đ/kg hoặc đổi đồ độc quyền.",
		last, "Hổng được làm Khô Gà con gà cuối cùng."))
	opts.append(opt(&"back", "Xong", "Đóng bội gà, ra sân."))
	return opts


static func _kg_text(kg: float) -> String:
	return String.num(kg, 2).replace(".", ",")


# =================================================================== việc

func _food_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Items.items_for_slot(&"food"):
		if GameState.item_count(id) > 0:
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return float(Items.get_item(a)["price"]) < float(Items.get_item(b)["price"]))
	return out


func _feed_menu() -> void:
	var foods: Array[StringName] = _food_ids()
	if foods.is_empty():
		message("Trong kho hết đồ ăn rồi – ghé tiệm Cô Ba mua lúa (15.000đ) nghen!", BAD)
		_play(&"sad")
		return
	var opts: Array = []
	for id in foods:
		opts.append(opt(id, "%s ×%d" % [Items.display_name(id), GameState.item_count(id)], String(Items.get_item(id)["text"])))
	opts.append(opt(&"back", "Thôi", ""))
	var r: int = await pick("Cho %s ăn gì?" % _c()["name"], opts)
	if r < 0 or StringName(opts[r]["id"]) == &"back":
		return
	var food: StringName = StringName(opts[r]["id"])
	var lv: int = int(_c()["level"])
	var before: float = float(_c()["condition"])
	if not GameState.feed(index, food):
		message(GameState.last_error, BAD)
		return
	_play(&"eat")
	_spawn_fx(&"grain", 10)
	Audio.sfx(&"harvest", -10.0, 1.4)
	var parts: PackedStringArray = []
	var after: float = float(_c()["condition"])
	if after > before:
		parts.append("Thể trạng %d%% → %d%%" % [int(round(before)), int(round(after))])
	var exp_gain: int = int((Items.get_item(food).get("effect", {}) as Dictionary).get("exp", 0))
	if exp_gain > 0:
		parts.append("+%d EXP" % exp_gain)
	if int(_c()["level"]) > lv:
		parts.append("LÊN CẤP %d!" % int(_c()["level"]))
		Audio.sfx(&"levelup", -4.0)
	message("%s mổ %s ngon lành. %s" % [_c()["name"], Items.display_name(food).to_lower(), ", ".join(parts)], GOOD)
	await hold(0.6)


func _care(kind: StringName) -> void:
	var r: Dictionary = HomeState.do_care(index, kind)
	if not bool(r["ok"]):
		message(String(r["text"]), BAD)
		return
	_play(&"happy")
	_spawn_fx(&"heart", 5)
	message("%s (+%d%% Thể trạng, thân thiết %s)" % [String(r["text"]), int(round(float(r["condition"]))),
		HomeState.bond_hearts(int(_c()["id"]))], GOOD)


func _train() -> void:
	var lv: int = int(_c()["level"])
	var r: Dictionary = GameState.train(index)
	if not bool(r["ok"]):
		message(GameState.last_error, BAD)
		_play(&"sad")
		return
	_play(&"happy")
	Audio.sfx(&"step_dirt", -6.0, 0.8)
	var text_out: String = "Tập cọc một giờ: +%d EXP, −%d%% Thể trạng. Giờ: %s." % [int(r["exp"]),
		int(GameState.TRAIN_CONDITION_COST), GameState.time_text()]
	if int(_c()["level"]) > lv:
		text_out += " LÊN CẤP %d!" % int(_c()["level"])
		Audio.sfx(&"levelup", -4.0)
	message(text_out, GOOD)
	if bool(r["day_over"]):
		_result["day_over"] = true
	await hold(0.4)


# ------------------------------------------------------------------ trang bị

func _equip_menu() -> void:
	var last: int = 0
	while true:
		var opts: Array = []
		for slot in SLOT_ORDER:
			var cur: StringName = GameState.equipped(index, slot)
			var owned: int = 0
			for id in Items.items_for_slot(slot):
				owned += GameState.item_count(id)
			var label: String = "%s: %s" % [Items.SLOT_NAMES[slot], Items.display_name(cur) if cur != &"" else "— trống —"]
			if owned > 0:
				label += "  (+%d trong kho)" % owned
			var detail: String = String(Items.get_item(cur)["text"]) if cur != &"" else "Chưa gắn gì. Đồ mua ở tiệm Cô Ba, chợ, xe khô gà Lão Gà Khô."
			opts.append(opt(slot, label, detail))
		opts.append(opt(&"back", "Xong", ""))
		_preview = {}
		var r: int = await pick("Trang bị – chọn ô", opts, Callable(), false, last)
		if r < 0 or StringName(opts[r]["id"]) == &"back":
			_preview = {}
			return
		last = r
		await _equip_slot(StringName(opts[r]["id"]))


func _equip_slot(slot: StringName) -> void:
	var cur: StringName = GameState.equipped(index, slot)
	var ids: Array[StringName] = []
	for id in Items.items_for_slot(slot):
		if GameState.item_count(id) > 0:
			ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return float(Items.get_item(a)["price"]) < float(Items.get_item(b)["price"]))
	if ids.is_empty() and cur == &"":
		message("Kho chưa có đồ ô %s. Ghé tiệm Cô Ba hoặc chợ sắm nghen." % Items.SLOT_NAMES[slot], BAD)
		return
	var opts: Array = []
	if cur != &"":
		opts.append(opt(&"", "Tháo %s ra" % Items.display_name(cur), "Món này về lại kho."))
	for id in ids:
		opts.append(opt(id, "%s ×%d" % [Items.display_name(id), GameState.item_count(id)],
			"%s\nGiá: %s" % [String(Items.get_item(id)["text"]), Items.price_text(id)]))
	opts.append(opt(&"back", "Thôi", ""))
	var hover := func(i: int) -> void:
		var id: StringName = StringName(opts[i]["id"])
		if id == &"back":
			_preview = {}
			return
		_preview = _stats_with_item(slot, id)
		_preview_label = "Gắn %s" % Items.display_name(id) if id != &"" else "Tháo đồ ô %s" % Items.SLOT_NAMES[slot]
	var r: int = await pick("Ô %s" % Items.SLOT_NAMES[slot], opts, hover)
	_preview = {}
	if r < 0 or StringName(opts[r]["id"]) == &"back":
		return
	var item: StringName = StringName(opts[r]["id"])
	if not GameState.equip(index, slot, item):
		message(GameState.last_error, BAD)
		return
	_refresh_portrait(true)
	_play(&"happy")
	Audio.sfx(&"brick", -8.0, 1.3)
	if item == &"":
		message("Tháo %s ra cất vô kho." % Items.display_name(cur), TEXT)
	else:
		message("%s gắn %s – ngó oai liền!" % [_c()["name"], Items.display_name(item)], GOOD)


func _stats_with_item(slot: StringName, item: StringName) -> Dictionary:
	var c: Dictionary = _c().duplicate(true)
	if slot == &"weapon":
		c["weapon"] = item
	else:
		c["gear"][slot] = item
	return GameState.stats_of(c)


# ------------------------------------------------------------------ đột biến

func _mutate_menu() -> void:
	var last: int = 0
	while true:
		var opts: Array = []
		opts.append(opt(&"exchange", "Đổi %d Technology → 1 Biotech" % Mutations.TECH_PER_BIOTECH,
			"Technology có từ đi học, thư viện, quiz. Đang có %d Technology · %d Biotech." % [GameState.technology,
			GameState.biotech], GameState.technology < Mutations.TECH_PER_BIOTECH,
			"Cần %d Technology (đang có %d) – đi học, lên thư viện nghen." % [Mutations.TECH_PER_BIOTECH, GameState.technology]))
		var muts: Array = _c()["mutations"]
		for m in Mutations.ORDER:
			var has: bool = muts.has(m)
			var cost: int = Mutations.cost(m)
			var why: String = ""
			if has:
				why = "%s đã có đột biến này." % _c()["name"]
			elif GameState.biotech < cost:
				why = "Cần %d Biotech (đang có %d)." % [cost, GameState.biotech]
			opts.append(opt(m, "%s · %d Biotech%s" % [Mutations.display_name(m), cost, " ✓" if has else ""],
				String(Mutations.info(m)["text"]), why != "", why))
		opts.append(opt(&"back", "Xong", ""))
		var hover := func(i: int) -> void:
			var id: StringName = StringName(opts[i]["id"])
			if Mutations.has(id) and not (_c()["mutations"] as Array).has(id):
				var c: Dictionary = _c().duplicate(true)
				(c["mutations"] as Array).append(id)
				_preview = GameState.stats_of(c)
				_preview_label = "Đột biến %s" % Mutations.display_name(id)
			else:
				_preview = {}
		subtitle = "Technology %d · Biotech %d" % [GameState.technology, GameState.biotech]
		var r: int = await pick("Đột biến (Biotech)", opts, hover, false, last)
		_preview = {}
		subtitle = ""
		if r < 0 or StringName(opts[r]["id"]) == &"back":
			return
		last = r
		var id: StringName = StringName(opts[r]["id"])
		if id == &"exchange":
			if GameState.exchange_biotech(1):
				message("Đổi được 1 Biotech. Còn %d Technology, có %d Biotech." % [GameState.technology, GameState.biotech], GOOD)
				Audio.sfx(&"coin", -6.0)
			else:
				message(GameState.last_error, BAD)
			continue
		var c2: Dictionary = _c().duplicate(true)
		(c2["mutations"] as Array).append(id)
		_preview = GameState.stats_of(c2)
		_preview_label = "Đột biến %s" % Mutations.display_name(id)
		_confirm_text = "ĐỘT BIẾN LÀ VĨNH VIỄN – không gỡ ra được!\n%s: %s\nTốn %d Biotech (còn %d)." % [
			Mutations.display_name(id), String(Mutations.info(id)["text"]), Mutations.cost(id), GameState.biotech]
		var ok: int = await pick("Chắc chưa?", [opt(&"yes", "Đột biến luôn (vĩnh viễn)", _confirm_text),
			opt(&"no", "Để suy nghĩ thêm", "")], Callable(), false, 1)
		_confirm_text = ""
		_preview = {}
		if ok != 0:
			continue
		if GameState.mutate(index, id):
			_refresh_portrait(true)
			_play(&"happy")
			_spawn_fx(&"spark", 14)
			Audio.sfx(&"levelup", -4.0, 0.8)
			message("%s đột biến %s! Lông lá đổi màu, khí thế khác hẳn." % [_c()["name"], Mutations.display_name(id)], GOOD)
			await hold(0.5)
		else:
			message(GameState.last_error, BAD)


# ------------------------------------------------------------------ tên, bán, Khô Gà

func _rename() -> void:
	if dialog == null:
		return
	var old: String = String(_c()["name"])
	var n: String = await dialog.ask_name("", "Đặt tên mới cho %s nghen:" % old, old)
	if GameState.rename(index, n):
		if n != old:
			message("Từ nay kêu nó là %s." % n, GOOD)
		else:
			message("Giữ tên %s." % old)
	else:
		message(GameState.last_error, BAD)


func _sell() -> void:
	var c: Dictionary = _c()
	var price: int = GameState.sell_price(index)
	_confirm_text = "Bán %s (%s Lv%d) cho lái gà được %s.\nĐồ đang gắn tự tháo về kho. Bán rồi là hổng chuộc lại được." % [
		c["name"], Breeds.display_name(int(c["breed"])), int(c["level"]), GameState.money_text(price)]
	var ok: int = await pick("Bán %s?" % c["name"], [opt(&"yes", "Bán · %s" % GameState.money_text(price), _confirm_text),
		opt(&"no", "Thôi, giữ lại", "")], Callable(), false, 1)
	_confirm_text = ""
	if ok != 0:
		return
	var name: String = String(c["name"])
	var got: int = GameState.sell_chicken(index)
	if got < 0:
		message(GameState.last_error, BAD)
		return
	_result["changed"] = true
	Audio.sfx(&"coin", -3.0)
	message("Bán %s được %s. Ráng kiếm con khác đá tiếp nghen." % [name, GameState.money_text(got)], GOOD)
	index = clampi(index, 0, GameState.chickens.size() - 1)
	_last_main = 0


func _kho_ga() -> void:
	var c: Dictionary = _c()
	var kg: float = GameState.kho_ga_yield(index)
	_confirm_text = "VĨNH VIỄN: %s sẽ thành %s kg Khô Gà (Lão Gà Khô ngoài chợ mua 50.000đ/kg ≈ %s).\nĐồ đang gắn về kho. Hổng có đường quay lại đâu!" % [
		c["name"], _kg_text(kg), GameState.money_text(int(round(kg * float(Items.KHO_GA_PRICE_PER_KG))))]
	var ok: int = await pick("Làm Khô Gà?", [opt(&"yes", "Làm Khô Gà (vĩnh viễn)", _confirm_text),
		opt(&"no", "Thôi, thôi! Để nó sống", "")], Callable(), false, 1)
	_confirm_text = ""
	if ok != 0:
		return
	var name: String = String(c["name"])
	var got: float = GameState.convert_to_kho_ga(index)
	if got <= 0.0:
		message(GameState.last_error, BAD)
		return
	_result["changed"] = true
	index = clampi(index, 0, GameState.chickens.size() - 1)
	_last_main = 0
	_refresh_portrait()
	if dialog != null:
		visible = false
		await dialog.say([
			["", "%s được tiễn lên đường trong danh dự… rồi về lại trong một bịch Khô Gà thơm lừng (+%s kg)." % [name, _kg_text(got)]],
			["Ba", "Thôi, nó cũng sống trọn một đời chiến kê rồi con. Lão Gà Khô ngoài chợ chắc vừa khóc vừa cười mà làm khô gà lá chanh cho nó à nghen."],
		])
		visible = true
	message("Nhận %s kg Khô Gà (đang có %s kg)." % [_kg_text(got), _kg_text(GameState.kho_ga)], TEXT)


# =================================================================== chân dung & hiệu ứng

func _refresh_portrait(force: bool = false) -> void:
	if GameState.chickens.is_empty():
		return
	var c: Dictionary = _c()
	var sig: String = "%d|%s|%s|%s" % [int(c["id"]), String(c["weapon"]), str(c["gear"]), str(c["mutations"])]
	if not force and sig == _portrait_sig and is_instance_valid(_portrait):
		return
	_portrait_sig = sig
	if is_instance_valid(_portrait):
		_portrait.queue_free()
	var s: Node2D = ChickenSprite.new()
	s.call("setup", GameState.chicken_side(index), PORTRAIT_SCALE)
	s.position = PORTRAIT_BOX.position + Vector2(PORTRAIT_BOX.size.x * 0.5 - 6.0, PORTRAIT_BOX.size.y - 10.0)
	add_child(s)
	_portrait = s
	_portrait_id = int(c["id"])


func portrait() -> Node2D:
	return _portrait


func _play(kind: StringName) -> void:
	if is_instance_valid(_portrait):
		_portrait.call("play_once", kind)


func _spawn_fx(kind: StringName, n: int) -> void:
	var origin: Vector2 = PORTRAIT_BOX.position + Vector2(PORTRAIT_BOX.size.x * 0.5 + 20.0, PORTRAIT_BOX.size.y - 40.0)
	for i in range(n):
		var vel := Vector2(randf_range(-60, 60), randf_range(-140, -60))
		if kind == &"grain":
			vel = Vector2(randf_range(-30, 30), randf_range(-40, 10))
		_fx.append([origin + Vector2(randf_range(-30, 30), randf_range(-20, 0)), vel, 1.0, kind])


func _process(delta: float) -> void:
	super._process(delta)
	for f in _fx:
		var vel: Vector2 = f[1]
		vel.y += (160.0 if f[3] == &"grain" else 30.0) * delta
		f[1] = vel
		f[0] = (f[0] as Vector2) + vel * delta
		f[2] = float(f[2]) - delta * 0.9
	_fx = _fx.filter(func(f: Array) -> bool: return float(f[2]) > 0.0)


# =================================================================== vẽ

func _draw_left(b: Control) -> void:
	if GameState.chickens.is_empty():
		return
	var c: Dictionary = _c()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.36, 0.5, 0.32)
	box.border_color = BORDER
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	b.draw_style_box(box, PORTRAIT_BOX)
	b.draw_rect(Rect2(PORTRAIT_BOX.position + Vector2(2, PORTRAIT_BOX.size.y - 34), Vector2(PORTRAIT_BOX.size.x - 4, 32)),
		Color(0.66, 0.54, 0.36))
	# hạt lúa / tim
	for f in _fx:
		var p: Vector2 = f[0]
		var a: float = clampf(float(f[2]), 0.0, 1.0)
		match f[3]:
			&"grain":
				b.draw_rect(Rect2(p, Vector2(4, 3)), Color(0.95, 0.8, 0.3, a))
			&"heart":
				text(p, "♥", FS, Color(1.0, 0.45, 0.55, a), true)
			_:
				text(p, "✦", FS, Color(0.7, 0.95, 1.0, a), true)
	if index == GameState.active:
		text(PORTRAIT_BOX.position + Vector2(10, 26), "★ GÀ CHIẾN", FS_SMALL, GOLD, true)
	text(PORTRAIT_BOX.position + Vector2(PORTRAIT_BOX.size.x - 10, 26), "%d/%d" % [index + 1, GameState.chickens.size()],
		FS_SMALL, TEXT, true, HORIZONTAL_ALIGNMENT_RIGHT, 80)
	var x: float = LEFT.position.x
	var w: float = LEFT.size.x
	var y: float = PORTRAIT_BOX.end.y + 34
	text(Vector2(x, y), String(c["name"]), FS, Color.WHITE, true, HORIZONTAL_ALIGNMENT_LEFT, 240)
	text(Vector2(x + w, y), HomeState.bond_hearts(int(c["id"])), FS, Color(1.0, 0.5, 0.6), false,
		HORIZONTAL_ALIGNMENT_RIGHT, 120)
	y += 6
	var breed: int = int(c["breed"])
	wrap_text(Vector2(x, y), "%s · %s" % [Breeds.display_name(breed), String(Breeds.info(breed).get("passive_text", ""))], w,
		FS, Color(0.8, 0.88, 1.0), 2)
	y += 66
	var lv: int = int(c["level"])
	var cap: int = GameState.level_cap()
	var need: int = GameState.exp_to_next(lv)
	var ratio: float = 1.0 if lv >= cap else float(c["xp"]) / float(maxi(need, 1))
	bar(Rect2(x, y, w, 28), ratio, Color(0.35, 0.6, 1.0),
		"Lv %d / cap %d · EXP %s" % [lv, cap, "tối đa" if lv >= cap else "%d/%d" % [int(c["xp"]), need]])
	y += 34
	var cond: float = float(c["condition"])
	var ccol: Color = Color(0.4, 0.78, 0.36) if cond >= 70.0 else (Color(0.9, 0.7, 0.2) if cond >= GameState.CONDITION_WEAK else Color(0.85, 0.3, 0.25))
	bar(Rect2(x, y, w, 28), cond / 100.0, ccol, "Thể trạng %d%%%s" % [int(round(cond)),
		" (<50%: −10% ATK)" if cond < GameState.CONDITION_WEAK else ""])
	y += 36
	wrap_text(Vector2(x, y), mood_line(index), w, FS, Color(1.0, 0.92, 0.75), 2)
	y += 62
	var titles: Array = c["titles"]
	var rec: String = "Thắng %d · Thua %d" % [int(c["wins"]), int(c["losses"])]
	if not titles.is_empty():
		rec += " · " + ", ".join(PackedStringArray(titles))
	wrap_text(Vector2(x, y), rec, w, FS, TEXT, 2)


## Một câu tâm trạng theo Thể trạng, bữa ăn, thắng thua, luyện tập.
static func mood_line(i: int) -> String:
	var c: Dictionary = GameState.chickens[i]
	var cond: float = float(c["condition"])
	var wins: int = int(c["wins"])
	var losses: int = int(c["losses"])
	if cond < 30.0:
		return "Đói lả, mệt rũ cánh – cần lúa với một giấc ngủ ngon."
	if cond < GameState.CONDITION_WEAK:
		return "Uể oải, lông xơ xác. Cho ăn, vuốt ve cho nó lại sức."
	if not bool(c["fed_today"]) and GameState.period() >= GameState.Period.TRUA:
		return "Bụng đói meo, cứ mổ mổ xuống đất kiếm hột lúa."
	if int(c["trained_today"]) >= GameState.TRAIN_PER_DAY:
		return "Tập đủ rồi, đứng thở hồng hộc mà mắt vẫn sáng rỡ."
	if losses > wins:
		return "Còn hờn vụ thua bữa trước, xù lông ngúng nguẩy hổng chịu nhìn ai."
	if not (c["titles"] as Array).is_empty():
		return "Ưỡn ngực ra oai – nhà vô địch mà!"
	if wins > 0:
		return "Gáy vang khoái chí, ra vẻ ta đây mới thắng trận."
	if bool(c["fed_today"]):
		return "No nê, lông mượt, sẵn sàng ra sới."
	return "Thong thả đi tới đi lui, chờ chủ cho ăn."


func _draw_mid(b: Control) -> void:
	if GameState.chickens.is_empty():
		return
	var x: float = MID.position.x
	var w: float = MID.size.x
	var y: float = MID.position.y + 10
	b.draw_rect(Rect2(MID.position + Vector2(0, -4), Vector2(w, 270)), PANEL2)
	var now: Dictionary = GameState.chicken_stats(index)
	var c: Dictionary = _c()
	var base: Dictionary = GameState.scaled_stats(int(c["breed"]), int(c["level"]))
	if _confirm_text != "":
		b.draw_rect(Rect2(MID.position + Vector2(0, -4), Vector2(w, MID.size.y + 4)), PANEL2)
		text(Vector2(x + 12, y + 24), "XÁC NHẬN", FS, BAD, true)
		wrap_text(Vector2(x + 12, y + 40), _confirm_text, w - 24, FS, Color(1.0, 0.9, 0.8), 13)
		return
	text(Vector2(x + 12, y + 24), "Chỉ số" if _preview.is_empty() else _preview_label, FS, GOLD, true,
		HORIZONTAL_ALIGNMENT_LEFT, w - 24)
	var top: float = y + 38
	for k in range(STAT_ROWS.size()):
		var key: String = STAT_ROWS[k][0]
		var ry: float = top + float(k) * 30.0
		text(Vector2(x + 12, ry + 22), String(STAT_ROWS[k][1]), FS, TEXT)
		if _preview.is_empty():
			var d: float = float(now[key]) - float(base[key])
			text(Vector2(x + 190, ry + 22), stat_text(key, float(now[key])), FS, Color.WHITE, true,
				HORIZONTAL_ALIGNMENT_RIGHT, 80)
			if absf(d) > 0.001:
				text(Vector2(x + 198, ry + 22), "(%s)" % delta_text(key, d), FS, GOOD if d > 0.0 else BAD)
		else:
			var after: float = float(_preview[key])
			var d2: float = after - float(now[key])
			text(Vector2(x + 152, ry + 22), stat_text(key, float(now[key])), FS, DIM, false, HORIZONTAL_ALIGNMENT_RIGHT, 56)
			text(Vector2(x + 158, ry + 22), "→", FS, DIM)
			text(Vector2(x + 236, ry + 22), stat_text(key, after), FS,
				Color.WHITE if absf(d2) < 0.001 else (GOOD if d2 > 0.0 else BAD), true, HORIZONTAL_ALIGNMENT_RIGHT, 60)
			if absf(d2) > 0.001:
				text(Vector2(x + 240, ry + 22), delta_text(key, d2), FS_SMALL, GOOD if d2 > 0.0 else BAD, true)
	if bool(now.get("weak", false)):
		text(Vector2(x + 12, top + 6.0 * 30.0 + 18.0), "Thể trạng yếu: ATK −10% trong trận", FS_SMALL, BAD, true)
	# đồ đang gắn + đột biến
	y = MID.position.y + 276
	b.draw_rect(Rect2(x, y, w, MID.size.y - 276), PANEL2)
	text(Vector2(x + 12, y + 28), "Đồ đang gắn", FS, GOLD, true)
	var lines: PackedStringArray = []
	for slot in SLOT_ORDER:
		var it: StringName = GameState.equipped(index, slot)
		if it != &"":
			lines.append("%s: %s" % [Items.SLOT_NAMES[slot], Items.display_name(it)])
	if lines.is_empty():
		lines.append("(chưa gắn gì)")
	wrap_text(Vector2(x + 12, y + 38), " · ".join(lines), w - 24, FS, TEXT, 3)
	var muts: PackedStringArray = []
	for m in c["mutations"]:
		muts.append(Mutations.display_name(m))
	text(Vector2(x + 12, y + 160), "Đột biến", FS, Color(0.7, 0.95, 1.0), true)
	wrap_text(Vector2(x + 12, y + 170), ", ".join(muts) if not muts.is_empty() else "(chưa có)", w - 24, FS, TEXT, 1)


static func stat_text(key: String, v: float) -> String:
	match key:
		"hp", "spd":
			return str(int(round(v)))
		"crit":
			return "%d%%" % int(round(v * 100.0))
		"weight":
			return String.num(v, 1).replace(".", ",")
	return String.num(snappedf(v, 0.1), 1).replace(".", ",")


static func delta_text(key: String, d: float) -> String:
	var sign_s: String = "+" if d > 0.0 else "−"
	return sign_s + stat_text(key, absf(d))
