extends "res://game/home/home_panel.gd"

## Bàn học: coi cả đàn gà một lượt (bảng tổng – chọn một con để mở bảng chăm gà), đổi Technology → Biotech,
## sổ tay ghi thói quen đối thủ (từ dữ liệu OPPONENTS: aggr / jumpy / block + câu chào).
## Dùng: var ui = DeskUI.new(); ui.dialog = dialog; add_child(ui); var r: Dictionary = await ui.run(); ui.queue_free()
## Kết quả: {"changed": bool, "day_over": bool} (gộp từ bảng chăm gà mở lồng bên trong).

const CoopUI := preload("res://game/home/coop_ui.gd")
const Mutations := preload("res://game/data/mutations.gd")
const Breeds := preload("res://game/data/breeds.gd")
const Items := preload("res://game/data/items.gd")

var _mode: StringName = &"menu"   # menu | roster | notes
var _note_id: String = ""
var _result: Dictionary = {"changed": false, "day_over": false}
## Bảng chăm gà đang mở lồng (test đọc).
var child_panel: CanvasLayer


func _ready() -> void:
	super._ready()
	title = "BÀN HỌC"


func run() -> Dictionary:
	var last: int = 0
	while true:
		_mode = &"menu"
		subtitle = "%s · Technology %d · Biotech %d · Khô Gà %s kg" % [GameState.money_text(GameState.money),
			GameState.technology, GameState.biotech, String.num(GameState.kho_ga, 2).replace(".", ",")]
		var opts: Array = [
			opt(&"roster", "Coi cả đàn (%d con)" % GameState.chickens.size(), "Bảng tổng: cấp, Thể trạng, thắng thua, đồ đạc. Chọn một con để chăm."),
			opt(&"exchange", "Đổi Technology → Biotech", "10 Technology đổi 1 Biotech. Biotech dùng đột biến gà và ấp trứng.",
				GameState.technology < Mutations.TECH_PER_BIOTECH, "Cần %d Technology (đang có %d)." % [Mutations.TECH_PER_BIOTECH,
				GameState.technology]),
			opt(&"notes", "Sổ tay đối thủ", "Ghi chép thói quen các chiến kê từng nghe danh."),
			opt(&"back", "Xong", "Gấp tập lại."),
		]
		var r: int = await pick("Bàn học", opts, Callable(), false, last)
		if r < 0 or StringName(opts[r]["id"]) == &"back":
			break
		last = r
		match StringName(opts[r]["id"]):
			&"roster":
				await _roster()
				if bool(_result["day_over"]):
					break
			&"exchange":
				await _exchange()
			&"notes":
				await _notes()
	return _result


func _roster() -> void:
	var last: int = GameState.active
	while true:
		_mode = &"roster"
		var opts: Array = []
		for i in range(GameState.chickens.size()):
			var c: Dictionary = GameState.chickens[i]
			opts.append(opt(StringName(str(i)), ("★ " if i == GameState.active else "") + String(c["name"]),
				CoopUI.mood_line(i)))
		opts.append(opt(&"back", "Xong", ""))
		var r: int = await pick("Cả đàn", opts, Callable(), false, mini(last, opts.size() - 1))
		if r < 0 or StringName(opts[r]["id"]) == &"back":
			return
		last = r
		var ui: CanvasLayer = CoopUI.new()
		ui.set("dialog", dialog)
		add_child(ui)
		child_panel = ui
		visible = false
		var res: Dictionary = await ui.call("run", r)
		ui.queue_free()
		child_panel = null
		visible = true
		if bool(res.get("changed", false)):
			_result["changed"] = true
		if bool(res.get("day_over", false)):
			_result["day_over"] = true
			return


func _exchange() -> void:
	var max_n: int = GameState.technology / Mutations.TECH_PER_BIOTECH
	var opts: Array = [opt(&"one", "Đổi 1 Biotech (%d Technology)" % Mutations.TECH_PER_BIOTECH, ""),
		opt(&"all", "Đổi hết: %d Biotech (%d Technology)" % [max_n, max_n * Mutations.TECH_PER_BIOTECH], "", max_n <= 1,
			"Chỉ đủ đổi 1."), opt(&"back", "Thôi", "")]
	var r: int = await pick("Đổi Biotech", opts)
	if r < 0 or r == 2:
		return
	var n: int = 1 if r == 0 else max_n
	if GameState.exchange_biotech(n):
		Audio.sfx(&"coin", -6.0)
		message("Đổi được %d Biotech. Giờ có %d Biotech, còn %d Technology." % [n, GameState.biotech, GameState.technology], GOOD)
	else:
		message(GameState.last_error, BAD)


## Đối thủ đáng ghi sổ: Ao Làng + giao hữu/giải tới Act hiện tại.
static func known_opponents() -> Array[String]:
	var out: Array[String] = []
	var act: int = GameState.current_act()
	for id in GameState.OPPONENTS.keys():
		var o: Dictionary = GameState.OPPONENTS[id]
		var league: StringName = StringName(o.get("league", &""))
		var band: int = int(o.get("band", 1 if league == &"ao_lang" or league == &"" else 2 if league == &"lien_tinh" else 3))
		if band <= act:
			out.append(String(id))
	return out


static func habit_text(o: Dictionary) -> String:
	var parts: PackedStringArray = []
	var aggr: float = float(o.get("aggr", 0.0))
	var jumpy: float = float(o.get("jumpy", 0.0))
	var block: float = float(o.get("block", 0.0))
	parts.append("Hung hăng, xông vào liên tục" if aggr >= 0.6 else ("Vừa công vừa thủ" if aggr >= 0.35 else "Thủ thế, chờ sơ hở"))
	if jumpy >= 0.3:
		parts.append("hay nhảy đá từ trên xuống – đứng thẳng giữ lùi mà đỡ")
	elif int(o.get("breed", 0)) == 2:
		parts.append("Đông Tảo hổng nhảy được, lì đòn – đánh dồn cho vỡ thủ")
	if block >= 0.35:
		parts.append("đỡ đòn giỏi – đánh liên tục, đổi tầng cao thấp")
	var weapon: StringName = StringName(o.get("weapon", &""))
	if weapon != &"":
		parts.append("có %s" % Items.display_name(weapon))
	return ". ".join(parts) + "."


func _notes() -> void:
	_mode = &"notes"
	var ids: Array[String] = known_opponents()
	var opts: Array = []
	for id in ids:
		var o: Dictionary = GameState.OPPONENTS[id]
		opts.append(opt(StringName(id), "%s – %s" % [String(o.get("name", id)), String(o.get("owner", "?"))], ""))
	opts.append(opt(&"back", "Gấp sổ", ""))
	var hover := func(i: int) -> void:
		_note_id = String(opts[i]["id"]) if i < ids.size() else ""
	while true:
		var r: int = await pick("Sổ tay đối thủ", opts, hover)
		if r < 0 or r >= ids.size():
			break
	_mode = &"menu"
	_note_id = ""


# =================================================================== vẽ

func _draw_left(b: Control) -> void:
	# trang vở kẻ ô
	var page := Rect2(LEFT.position, Vector2(LEFT.size.x + MID.size.x + 12, LEFT.size.y - 8))
	b.draw_rect(page, Color(0.95, 0.93, 0.86))
	for k in range(1, int((page.size.y - 10.0) / 30.0)):
		b.draw_line(Vector2(page.position.x, page.position.y + 10 + k * 30), Vector2(page.end.x, page.position.y + 10 + k * 30),
			Color(0.62, 0.72, 0.88, 0.5), 1.0)
	b.draw_line(Vector2(page.position.x + 34, page.position.y), Vector2(page.position.x + 34, page.end.y),
		Color(0.9, 0.4, 0.4, 0.6), 2.0)
	var ink := Color(0.15, 0.2, 0.45)
	var x: float = page.position.x + 44
	var y: float = page.position.y + 34
	match _mode:
		&"roster", &"menu":
			text(Vector2(x, y), "Sổ gà của %s" % GameState.player_name, FS, ink, true)
			y += 30
			var cols: Array = [[0, "Tên"], [158, "Giống"], [290, "Lv"], [326, "Thể trạng"], [430, "T/B"], [486, "Đồ"],
				[522, "ĐB"], [562, "Thân"]]
			for col in cols:
				text(Vector2(x + float(col[0]), y), String(col[1]), FS_SMALL, Color(0.45, 0.3, 0.2), true)
			for i in range(mini(GameState.chickens.size(), 11)):
				var c: Dictionary = GameState.chickens[i]
				y += 30
				var cond: float = float(c["condition"])
				var row_col: Color = ink if i != GameState.active else Color(0.6, 0.15, 0.1)
				text(Vector2(x - 30, y), "★" if i == GameState.active else "", FS, Color(0.75, 0.5, 0.05), true)
				text(Vector2(x, y), String(c["name"]), FS, row_col, false, HORIZONTAL_ALIGNMENT_LEFT, 154)
				text(Vector2(x + 158, y), Breeds.display_name(int(c["breed"])), FS, row_col, false, HORIZONTAL_ALIGNMENT_LEFT, 128)
				text(Vector2(x + 290, y), str(int(c["level"])), FS, row_col)
				text(Vector2(x + 326, y), "%d%%%s" % [int(round(cond)), " ăn" if bool(c["fed_today"]) else " đói"], FS,
					Color(0.15, 0.5, 0.2) if cond >= 70.0 else Color(0.75, 0.2, 0.15), false)
				text(Vector2(x + 430, y), "%d/%d" % [int(c["wins"]), int(c["losses"])], FS, row_col)
				var gear_n: int = 0
				for slot in Items.SLOTS:
					if GameState.equipped(i, slot) != &"":
						gear_n += 1
				text(Vector2(x + 486, y), str(gear_n), FS, row_col)
				text(Vector2(x + 522, y), str((c["mutations"] as Array).size()), FS, row_col)
				var hearts: int = (preload("res://game/home/home_state.gd").bond(int(c["id"])) + 1) / 2
				text(Vector2(x + 562, y), "♥".repeat(hearts), FS, Color(0.8, 0.25, 0.35))
			if GameState.chickens.size() > 11:
				text(Vector2(x, y + 30), "… còn %d con nữa" % (GameState.chickens.size() - 11), FS, ink)
			text(Vector2(x, page.end.y - 12), "Chuồng %d/%d · cấp %d · Lò ấp %d/%d trứng" % [GameState.chickens.size(),
				GameState.coop_capacity(), GameState.coop_level, GameState.incubator.size(), GameState.INCUBATOR_SLOTS], FS,
				Color(0.45, 0.3, 0.2))
		&"notes":
			text(Vector2(x, y), "Sổ tay đối thủ", FS, ink, true)
			if _note_id != "" and GameState.OPPONENTS.has(_note_id):
				var o: Dictionary = GameState.OPPONENTS[_note_id]
				y += 36
				text(Vector2(x, y), "%s (%s) – chủ: %s · Lv%d" % [String(o.get("name", "")), Breeds.display_name(int(o.get("breed", 0))),
					String(o.get("owner", "")), int(o.get("lv", 1))], FS, ink, true, HORIZONTAL_ALIGNMENT_LEFT, page.size.x - 60)
				wrap_text(Vector2(x, y + 14), habit_text(o), page.size.x - 60, FS, ink, 7)
				if String(o.get("quote", "")) != "":
					wrap_text(Vector2(x, y + 244), "“%s”" % String(o["quote"]), page.size.x - 60, FS, Color(0.45, 0.3, 0.2), 4)
			else:
				wrap_text(Vector2(x, y + 24), "Chọn một chiến kê bên phải để coi ghi chép.", page.size.x - 60, FS, ink, 2)
