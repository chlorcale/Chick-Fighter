extends "res://game/home/home_panel.gd"

## Lò ấp trứng (rơm + đèn sưởi): bỏ trứng mua ở chợ vào lò kèm Biotech (chọn bao nhiêu, xem số ngày ấp và Biotech
## làm gì), coi tiến độ từng ngày, nở trứng (hoạt ảnh nứt vỏ, đặt tên gà con, báo khi chuồng đầy), đổi
## Technology → Biotech ngay tại chỗ.
## Dùng: var ui = IncubatorUI.new(); ui.dialog = dialog; add_child(ui); var r: Dictionary = await ui.run(); ui.queue_free()
## Kết quả: {"changed": bool (có gà mới), "hatched": [chỉ số gà mới]}.

const ChickenSprite := preload("res://game/home/chicken_sprite.gd")
const Items := preload("res://game/data/items.gd")
const Mutations := preload("res://game/data/mutations.gd")
const Breeds := preload("res://game/data/breeds.gd")

## Thời lượng hoạt ảnh nở (giây). Test có thể giảm.
var hatch_time: float = 1.6
var _result: Dictionary = {"changed": false, "hatched": []}
var _info: String = ""
var _hatching: int = -1         # ô lò đang nở (vẽ hoạt ảnh)
var _hatch_t: float = 0.0
var _chick: Node2D
var _shells: Array = []


func _ready() -> void:
	super._ready()
	title = "LÒ ẤP TRỨNG"


func run() -> Dictionary:
	var last: int = 0
	while true:
		subtitle = "Biotech %d · Technology %d · Chuồng %d/%d" % [GameState.biotech, GameState.technology,
			GameState.chickens.size(), GameState.coop_capacity()]
		var opts: Array = _options_now()
		var hover := func(i: int) -> void:
			_info = String(opts[i].get("info", ""))
		var r: int = await pick("Lò ấp", opts, hover, false, last)
		if r < 0:
			break
		last = r
		var id: String = String(opts[r]["id"])
		if id == "back":
			break
		if id == "place":
			await _place_menu()
		elif id == "exchange":
			if GameState.exchange_biotech(1):
				message("Đổi được 1 Biotech (còn %d Technology)." % GameState.technology, GOOD)
				Audio.sfx(&"coin", -6.0)
			else:
				message(GameState.last_error, BAD)
		elif id.begins_with("hatch_"):
			await _hatch(int(id.trim_prefix("hatch_")))
			last = 0
	return _result


func _options_now() -> Array:
	var opts: Array = []
	for i in GameState.hatch_ready():
		var e: Dictionary = GameState.incubator[int(i)]
		var full: bool = GameState.coop_full()
		var o: Dictionary = opt(StringName("hatch_%d" % int(i)), "Nở trứng: %s" % Items.display_name(e["egg"]),
			"Trứng đã tới ngày nở! Đặt tên cho gà con.", full,
			"Chuồng đầy rồi (%d/%d) – nâng chuồng ở ô đất trống ngoài sân, hoặc bớt gà đã." % [GameState.chickens.size(),
			GameState.coop_capacity()])
		opts.append(o)
	var eggs: int = _egg_ids().size()
	var slots_free: int = GameState.INCUBATOR_SLOTS - GameState.incubator.size()
	var why: String = ""
	if slots_free <= 0:
		why = "Lò đầy rồi (%d trứng). Chờ nở đã." % GameState.INCUBATOR_SLOTS
	elif eggs == 0:
		why = "Kho chưa có trứng. Trứng bán ở chợ (sạp trứng) từ Act 2."
	opts.append(opt(&"place", "Bỏ trứng vào lò", "Chọn trứng trong kho, chọn số Biotech bỏ kèm.", why != "", why))
	opts.append(opt(&"exchange", "Đổi %d Technology → 1 Biotech" % Mutations.TECH_PER_BIOTECH,
		"Đang có %d Technology, %d Biotech." % [GameState.technology, GameState.biotech],
		GameState.technology < Mutations.TECH_PER_BIOTECH,
		"Cần %d Technology – đi học, lên thư viện nghen." % Mutations.TECH_PER_BIOTECH))
	opts.append(opt(&"back", "Xong", ""))
	return opts


func _egg_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Items.items_for_slot(&"egg"):
		if GameState.item_count(id) > 0:
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return float(Items.get_item(a)["price"]) < float(Items.get_item(b)["price"]))
	return out


func _place_menu() -> void:
	var eggs: Array[StringName] = _egg_ids()
	if eggs.is_empty():
		message("Kho chưa có trứng – ghé sạp trứng ngoài chợ nghen.", BAD)
		return
	var opts: Array = []
	for id in eggs:
		var info: Dictionary = Items.get_item(id)
		opts.append(opt(id, "%s ×%d" % [String(info["name"]), GameState.item_count(id)],
			"%s\nCần ít nhất %d Biotech." % [String(info["text"]), int(info["biotech_min"])]))
	opts.append(opt(&"back", "Thôi", ""))
	var r: int = await pick("Chọn trứng", opts)
	if r < 0 or StringName(opts[r]["id"]) == &"back":
		return
	var egg: StringName = StringName(opts[r]["id"])
	var info2: Dictionary = Items.get_item(egg)
	var need: int = int(info2["biotech_min"])
	if GameState.biotech < need:
		message("Trứng này cần ít nhất %d Biotech (đang có %d) – đổi Technology ở bàn học hoặc ngay đây." % [need,
			GameState.biotech], BAD)
		return
	var amounts: Array = []
	var rare: bool = StringName(info2.get("rarity", &"common")) == &"rare"
	for n in range(need, need + 6):
		var extra: int = n - need
		var chance: float = Mutations.hatch_mutation_chance(extra, rare)
		var detail: String = "Ấp %d ngày. Tỷ lệ gà con có sẵn 1 đột biến: %d%%." % [int(info2["incubate_days"]),
			int(round(chance * 100.0))]
		if int(info2.get("breed", 0)) < 0:
			detail += " Tỷ lệ ra Gà Đông Tảo: %d%%." % int(round(Mutations.rare_breed_chance(extra) * 100.0))
		detail += "\nBiotech bỏ thêm (trên mức tối thiểu) làm trứng dễ đột biến hơn."
		amounts.append(opt(StringName(str(n)), "Bỏ %d Biotech" % n, detail, n > GameState.biotech,
			"Hổng đủ Biotech (đang có %d)." % GameState.biotech))
	amounts.append(opt(&"back", "Thôi", ""))
	var r2: int = await pick("Bao nhiêu Biotech?", amounts)
	if r2 < 0 or StringName(amounts[r2]["id"]) == &"back":
		return
	var spend: int = int(String(amounts[r2]["id"]))
	if GameState.start_incubation(egg, spend):
		Audio.sfx(&"ui_confirm", -4.0, 0.8)
		message("Đặt %s lên ổ rơm, bật đèn sưởi. %d ngày nữa nở!" % [String(info2["name"]).to_lower(),
			int(info2["incubate_days"])], GOOD)
	else:
		message(GameState.last_error, BAD)


func _hatch(i: int) -> void:
	if i < 0 or i >= GameState.incubator.size():
		return
	if GameState.coop_full():
		message("Chuồng đầy rồi – nâng chuồng ở ô đất trống ngoài sân, hoặc bớt gà đã.", BAD)
		return
	# Hoạt ảnh: trứng lắc → nứt → vỏ văng.
	_hatching = i
	_hatch_t = 0.0
	Audio.sfx(&"brick", -10.0, 1.6)
	await hold(hatch_time)
	var suggestion: String = Breeds.random_name(GameState.rng)
	var name: String = suggestion
	if dialog != null:
		name = await dialog.ask_name("", "Gà con mới nở, lông tơ vàng ươm! Đặt tên cho nó nghen:", suggestion)
	var idx: int = GameState.hatch(i, name)
	_hatching = -1
	if idx < 0:
		message(GameState.last_error, BAD)
		return
	_result["changed"] = true
	(_result["hatched"] as Array).append(idx)
	var c: Dictionary = GameState.chickens[idx]
	if is_instance_valid(_chick):
		_chick.queue_free()
	_chick = ChickenSprite.new()
	_chick.call("setup", GameState.chicken_side(idx), 1.1)
	_chick.position = Vector2(LEFT.position.x + LEFT.size.x * 0.5, LEFT.position.y + 170)
	add_child(_chick)
	_chick.call("play_once", &"happy")
	Audio.sfx(&"rooster_crow", -6.0, 1.5)
	var muts: Array = c["mutations"]
	var extra_line: String = " Trời, có sẵn đột biến %s!" % Mutations.display_name(muts[0]) if not muts.is_empty() else ""
	message("Nở ra %s – %s!%s" % [Breeds.display_name(int(c["breed"])), String(c["name"]), extra_line], GOOD, 6.0)


func _process(delta: float) -> void:
	super._process(delta)
	if _hatching >= 0:
		_hatch_t += delta


# =================================================================== vẽ

func _draw_left(b: Control) -> void:
	var box := Rect2(LEFT.position, Vector2(LEFT.size.x, 300))
	b.draw_rect(box, Color(0.26, 0.17, 0.1))
	b.draw_rect(box, Color(BORDER, 0.6), false, 2.0)
	# kệ + hai ổ rơm + đèn sưởi
	var shelf_y: float = box.position.y + 176
	b.draw_rect(Rect2(box.position.x + 20, shelf_y, box.size.x - 40, 18), Color(0.54, 0.35, 0.21))
	b.draw_rect(Rect2(box.position.x + 20, shelf_y, box.size.x - 40, 4), Color(0.64, 0.44, 0.25))
	for s in range(GameState.INCUBATOR_SLOTS):
		var cx: float = box.position.x + box.size.x * (0.28 + 0.44 * float(s))
		var glow: float = 0.5 + 0.15 * sin(_time * 3.0 + float(s))
		b.draw_circle(Vector2(cx, shelf_y - 30), 70.0, Color(1.0, 0.6, 0.25, 0.08 * glow))
		b.draw_line(Vector2(cx, box.position.y), Vector2(cx, box.position.y + 40), Color(0.25, 0.25, 0.25), 3.0)
		b.draw_colored_polygon(_dome(Vector2(cx, box.position.y + 66), 34.0, 26.0), Color(0.72, 0.75, 0.78))
		b.draw_circle(Vector2(cx, box.position.y + 66), 10.0, Color(1.0, 0.7 + 0.2 * glow, 0.35))
		_draw_nest(b, Vector2(cx, shelf_y - 4))
		if s < GameState.incubator.size():
			var e: Dictionary = GameState.incubator[s]
			var info: Dictionary = Items.get_item(e["egg"])
			var total: int = maxi(int(info.get("incubate_days", 1)), 1)
			var left: int = int(e["days_left"])
			var rot: float = 0.0
			var crack: float = 0.0
			if s == _hatching:
				var k: float = clampf(_hatch_t / maxf(hatch_time, 0.01), 0.0, 1.0)
				rot = sin(_hatch_t * 26.0) * 0.35 * k
				crack = k
			elif left <= 0:
				rot = sin(_time * 8.0) * 0.12
			_draw_egg(b, Vector2(cx, shelf_y - 30), rot, crack, int(info.get("breed", 0)) != 0 and int(info.get("breed", 0)) != 1)
			var label: String = "Tới ngày nở!" if left <= 0 else "Còn %d ngày" % left
			text(Vector2(cx - 84, shelf_y + 52), String(info["name"]), FS, TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, 168)
			bar(Rect2(cx - 78, shelf_y + 62, 156, 28), float(total - left) / float(total),
				GOOD if left <= 0 else Color(1.0, 0.7, 0.3), label)
		else:
			text(Vector2(cx - 84, shelf_y + 52), "Ổ trống", FS, DIM, false, HORIZONTAL_ALIGNMENT_CENTER, 168)
	var y: float = box.end.y + 8
	wrap_text(Vector2(LEFT.position.x, y), "Trứng mua ở chợ, ấp ở nhà bằng Biotech. Mỗi đêm ngủ dậy trứng bớt một ngày; tới ngày thì trứng lắc lư – chọn «Nở trứng».",
		LEFT.size.x, FS, DIM, 5)


func _dome(c: Vector2, w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(13):
		var a: float = PI + PI * float(k) / 12.0
		pts.append(c + Vector2(cos(a) * w * 0.5, sin(a) * h))
	return pts


func _draw_nest(b: Control, c: Vector2) -> void:
	var pts := PackedVector2Array()
	for k in range(16):
		var a: float = TAU * float(k) / 16.0
		pts.append(c + Vector2(cos(a) * 52.0, sin(a) * 18.0))
	b.draw_colored_polygon(pts, Color(0.86, 0.76, 0.44))
	for k in range(14):
		var x: float = c.x - 46.0 + float(k) * 7.0
		b.draw_line(Vector2(x, c.y - 6), Vector2(x + 6, c.y + 6), Color(0.69, 0.6, 0.3), 2.0)


func _draw_egg(b: Control, c: Vector2, rot: float, crack: float, speckled: bool) -> void:
	b.draw_set_transform(c + Vector2(0, 8), rot, Vector2.ONE)
	var pts := PackedVector2Array()
	for k in range(24):
		var a: float = TAU * float(k) / 24.0
		var ry: float = 30.0 if sin(a) < 0.0 else 24.0
		pts.append(Vector2(cos(a) * 22.0, sin(a) * ry - 8.0))
	b.draw_colored_polygon(pts, Color(0.96, 0.91, 0.8))
	b.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.72, 0.63, 0.44), 2.0)
	b.draw_circle(Vector2(-8, -22), 4.0, Color(1, 1, 1, 0.7))
	if speckled:
		for p in [Vector2(6, -14), Vector2(-4, 2), Vector2(10, 6), Vector2(-12, -4)]:
			b.draw_circle(p, 2.5, Color(0.55, 0.36, 0.2))
	if crack > 0.3:
		var zig := PackedVector2Array([Vector2(-20, -8), Vector2(-12, -14), Vector2(-4, -6), Vector2(4, -14),
			Vector2(12, -6), Vector2(20, -12)])
		b.draw_polyline(zig, Color(0.35, 0.25, 0.15), 2.5)
	if crack > 0.75:
		b.draw_circle(Vector2(0, -26), 9.0, Color(1.0, 0.86, 0.3))   # đầu gà con ló ra
		b.draw_circle(Vector2(3, -28), 1.8, Color(0.1, 0.1, 0.1))
		b.draw_colored_polygon(PackedVector2Array([Vector2(8, -26), Vector2(14, -24), Vector2(8, -22)]), Color(1.0, 0.6, 0.2))
	b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_mid(b: Control) -> void:
	var x: float = MID.position.x
	b.draw_rect(Rect2(MID.position + Vector2(0, -4), Vector2(MID.size.x, 350)), PANEL2)
	text(Vector2(x + 12, MID.position.y + 26), "Biotech làm gì?", FS, GOLD, true)
	var info: String = _info if _info != "" else ("Mỗi trứng cần một mức Biotech tối thiểu để ấp. Bỏ thêm Biotech thì gà con dễ có sẵn một đột biến (luôn có lợi có hại), Trứng lạ dễ ra giống hiếm Gà Đông Tảo.\n\nĐang có %d Biotech · %d Technology (10 Technology đổi 1 Biotech)." % [GameState.biotech, GameState.technology])
	wrap_text(Vector2(x + 12, MID.position.y + 40), info, MID.size.x - 24, FS, TEXT, 10)
	var y: float = MID.position.y + 382
	text(Vector2(x + 12, y), "Trứng trong kho", FS, GOLD, true)
	var eggs: Array[StringName] = _egg_ids()
	var lines: PackedStringArray = []
	for id in eggs:
		lines.append("%s ×%d" % [Items.display_name(id), GameState.item_count(id)])
	wrap_text(Vector2(x + 12, y + 6), "\n".join(lines) if not lines.is_empty() else "(chưa có – sạp trứng ngoài chợ)",
		MID.size.x - 24, FS, TEXT, 2)
