class_name PreBattle
extends CanvasLayer

## Màn chuẩn bị trước trận (GDD 3.2, Hình 10.7): chọn gà trong chuồng, thay vũ khí + 5 ô trang bị từ kho,
## xem tay bài, xem đối thủ (đồ của nó hiện trên hình), so sánh sức mạnh (GameState.mismatch).
## Khi trận quá chênh (GameState.can_call_police) có lựa chọn bí mật [G] "Gọi tay trong (báo công an)".
##
## HỢP ĐỒNG (main.gd): đặt `opponent` (bên đấu thô hoặc dựng sẵn) và `title` trước add_child;
## `await pre.run()` → true = vào trận, false = quay lại (Esc). Sau đó đọc `pre.police_called` (true = người chơi đã
## báo công an → main.gd dựng BattleDirector với "mode": "police"). Gà được chọn = GameState.active (đổi qua
## GameState.set_active); đồ thay qua GameState.equip – main.gd chỉ cần GameState.player_side() như trước.
##
## Phím: W/S chọn dòng · A/D đổi (gà / món) · E hoặc J xác nhận · G gọi tay trong (khi được phép) · Esc quay lại.
## Giao diện: khung gỗ sẫm UISkin, chữ pixel cỡ nguyên lần (11 = ×1, 22 = ×2, 33 = ×3).

signal _done(start: bool)

const SLOT_ROWS: Array[StringName] = [&"weapon", &"head", &"armor", &"wing", &"spur", &"comb"]
const BG := Color(0.08, 0.05, 0.04)
const PANEL := Color(0.05, 0.035, 0.03, 0.82)
const FRAME := Color(0.98, 0.82, 0.38)
const DIM := Color(0.72, 0.68, 0.62)
const TIER_TEXT: Array[String] = ["", "Tay mơ", "Có nghề", "Lão luyện", "Cao thủ (Hell Mode)"]

var opponent: Dictionary = {}
var title: String = ""
## true khi người chơi chọn [G] Gọi tay trong (báo công an). run() khi đó cũng trả true.
var police_called: bool = false

var _row: int = 0
var _canvas: Control
var _time: float = 0.0
var _sfx: Sfx
var _me_view: Node2D
var _opp_view: Node2D
var _police_ok: bool = false
var _message: String = ""
var _message_t: float = 0.0
var _font: Font
var _font_bold: Font


func _ready() -> void:
	layer = 40
	_sfx = Sfx.new()
	add_child(_sfx)
	_font = DialogBox.make_font()
	_font_bold = DialogBox.make_font(true)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_screen)
	UISkin.pixel(_canvas)
	add_child(_canvas)
	_opp_view = FighterView.make_portrait(opponent, "idle")
	(_opp_view as FighterView.Portrait).set_facing(-1)
	_canvas.add_child(_opp_view)
	_police_ok = not opponent.is_empty() and GameState.can_call_police(opponent)
	_rebuild_me()


func run() -> bool:
	return await _done


## Số dòng chọn được: 0 = gà, 1..6 = vũ khí + 5 ô, 7 = VÀO TRẬN.
func _row_count() -> int:
	return SLOT_ROWS.size() + 2


func _rebuild_me() -> void:
	if _me_view != null:
		_me_view.queue_free()
	_me_view = FighterView.make_portrait(GameState.player_side(), "idle")
	_canvas.add_child(_me_view)


func _process(delta: float) -> void:
	_time += delta
	_message_t = maxf(0.0, _message_t - delta)
	var size: Vector2 = _canvas.size
	var s: float = clampf(size.y / 720.0, 0.6, 2.0) * 3.0
	# Tỉ lệ nguyên pixel màn hình (gà tre ×0,9 cũng sắc nét) + vị trí bám pixel.
	if _me_view != null:
		var k: float = UISkin.crisp_scale(_me_view, s, UISkin.body_scale_of(_me_view))
		_me_view.scale = Vector2(k, k)
		_me_view.position = UISkin.snap(_me_view, Vector2(size.x * 0.155, size.y * 0.505))
	var ko: float = UISkin.crisp_scale(_opp_view, s, UISkin.body_scale_of(_opp_view))
	_opp_view.scale = Vector2(ko, ko)
	_opp_view.position = UISkin.snap(_opp_view, Vector2(size.x * 0.845, size.y * 0.505))
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: int = (event as InputEventKey).physical_keycode
	get_viewport().set_input_as_handled()
	match code:
		KEY_W, KEY_UP:
			_row = posmod(_row - 1, _row_count())
			_sfx.play(&"select", -8.0)
		KEY_S, KEY_DOWN:
			_row = posmod(_row + 1, _row_count())
			_sfx.play(&"select", -8.0)
		KEY_A, KEY_LEFT:
			_change(-1)
		KEY_D, KEY_RIGHT:
			_change(1)
		KEY_ESCAPE:
			_done.emit(false)
		KEY_G:
			if _police_ok:
				police_called = true
				_sfx.play(&"confirm")
				_done.emit(true)
		KEY_E, KEY_ENTER, KEY_SPACE, KEY_J:
			if _row == _row_count() - 1:
				_sfx.play(&"confirm")
				_done.emit(true)
			else:
				_change(1)


## A/D: dòng gà → đổi gà đang chọn; dòng ô → món kế tiếp trong kho (kể cả "trống").
func _change(step: int) -> void:
	if _row == 0:
		if GameState.chickens.size() <= 1:
			return
		GameState.set_active(posmod(GameState.active + step, GameState.chickens.size()))
		_after_change()
		return
	if _row > SLOT_ROWS.size():
		return
	var slot: StringName = SLOT_ROWS[_row - 1]
	var options: Array[StringName] = _options(slot)
	if options.size() <= 1:
		_flash_message("Kho chưa có món nào cho ô %s." % String(GameState.Items.SLOT_NAMES.get(slot, "?")))
		return
	var current: StringName = GameState.equipped(GameState.active, slot)
	var next: StringName = options[posmod(options.find(current) + step, options.size())]
	if not GameState.equip(GameState.active, slot, next):
		_flash_message(GameState.last_error)
		return
	_after_change()


func _after_change() -> void:
	_sfx.play(&"select")
	_rebuild_me()
	_police_ok = not opponent.is_empty() and GameState.can_call_police(opponent)


func _flash_message(text: String) -> void:
	_message = text
	_message_t = 2.2
	_sfx.play(&"select", -4.0, 0.7)


## Lựa chọn cho một ô: trống + món đang gắn + mọi món cùng ô còn trong kho (đã mở ở Act hiện tại hoặc đang có).
func _options(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = [&""]
	var current: StringName = GameState.equipped(GameState.active, slot)
	for id in GameState.Items.items_for_slot(slot):
		if id == current or GameState.item_count(id) > 0:
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		if a == &"" or b == &"":
			return a == &""
		return float(GameState.ITEMS[a]["price"]) < float(GameState.ITEMS[b]["price"]))
	return out


# =================================================================== vẽ

func _text(pos: Vector2, text: String, size: int, color: Color = Color.WHITE,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, bold: bool = false, outline: int = 5) -> void:
	# viền chữ: ×1 mỏng (2 px), ×2 trở lên giữ như cũ
	var o: int = mini(outline, 3) if size < 17 else outline
	UISkin.draw_text(_canvas, pos, text, size, color, bold, align, width, o, Color(0, 0, 0, color.a))


## Ngắt dòng theo từ cho vừa bề rộng.
func _wrap(text: String, size: int, width: float) -> PackedStringArray:
	var out: PackedStringArray = []
	var line: String = ""
	for word in text.split(" "):
		var trial: String = word if line == "" else line + " " + word
		if line != "" and _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


## Cắt bớt cho vừa một dòng (thêm "…").
func _fit(text: String, size: int, width: float) -> String:
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return text
	var t: String = text
	while t.length() > 4 and _font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		t = t.substr(0, t.length() - 1)
	return t + "…"


func _panel(rect: Rect2, accent: Color) -> void:
	UISkin.draw_panel(_canvas, rect, &"dark")
	_canvas.draw_rect(Rect2(rect.position + Vector2(16, 16), Vector2(rect.size.x - 32, 2)), accent)


func _bar(rect: Rect2, ratio: float, color: Color) -> void:
	_canvas.draw_rect(rect.grow(2), Color(0, 0, 0, 0.8))
	_canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0.0, 1.0), rect.size.y)), color)


func _draw_screen() -> void:
	var size: Vector2 = _canvas.size
	var w: float = size.x
	var h: float = size.y
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), BG)
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.34, 0), Vector2(w * 0.3, h), Vector2(0, h)]),
		Color(0.36, 0.1, 0.07))
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.7, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.66, h)]),
		Color(0.1, 0.15, 0.28))
	for i in range(16):
		var y: float = fmod(float(i) * 47.0 + _time * 50.0, h)
		_canvas.draw_line(Vector2(0, y), Vector2(w, y - 90.0), Color(1, 1, 1, 0.025), 8.0)
	_text(Vector2(0, 46), title if title != "" else "CHUẨN BỊ TRẬN ĐẤU", UISkin.FS_BIG, FRAME, HORIZONTAL_ALIGNMENT_CENTER, w, true, 6)
	_draw_me(w, h)
	_draw_loadout(w, h)
	_draw_opponent(w, h)
	_draw_power(w, h)
	var hint: String = "[W/S] chọn dòng · [A/D] đổi gà / đổi món · [E/J] xác nhận · [Esc] quay lại"
	_text(Vector2(0, h - 12), hint, UISkin.FS_SMALL, DIM, HORIZONTAL_ALIGNMENT_CENTER, w, true, 3)
	if _message_t > 0.0:
		_text(Vector2(0, h * 0.5), _message, UISkin.FS_BODY, Color(1.0, 0.7, 0.5, minf(1.0, _message_t * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, w, true, 6)


func _draw_me(w: float, h: float) -> void:
	var c: Dictionary = GameState.active_chicken()
	var stats: Dictionary = GameState.chicken_stats(GameState.active)
	var x: float = 24.0
	var pw: float = w * 0.27
	var selected: bool = _row == 0
	var count: int = GameState.chickens.size()
	_text(Vector2(x, 86), "GÀ CỦA BẠN  (%d/%d)" % [GameState.active + 1, count], UISkin.FS_SMALL, FRAME, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 3)
	var name_text: String = ("◀ %s ▶" if count > 1 and selected else "%s") % String(c["name"]).to_upper()
	if selected:
		_canvas.draw_rect(Rect2(x - 8, 92, pw, 34), Color(1.0, 0.8, 0.3, 0.14))
		_canvas.draw_texture(UISkin.texture("cursor"), Vector2(x - 30 + (2.0 if fmod(_time, 0.6) < 0.3 else 0.0), 100))
	_text(Vector2(x, 118), name_text, UISkin.FS_BODY, FRAME if selected else Color.WHITE,
		HORIZONTAL_ALIGNMENT_LEFT, pw, true, 4)
	var breed: int = int(c["breed"])
	_text(Vector2(x, 150), "%s · Lv%d · %s" % [GameState.Breeds.display_name(breed), int(c["level"]), GameState.player_name],
		UISkin.FS_BODY, Color(0.92, 0.9, 0.86), HORIZONTAL_ALIGNMENT_LEFT, -1.0, false, 4)
	var py: float = h * 0.56
	var cond: float = float(c["condition"]) / GameState.CONDITION_MAX
	var cond_color: Color = Color(0.35, 0.85, 0.35) if cond >= 0.75 else (Color(0.95, 0.8, 0.25) if cond >= 0.5 else Color(0.95, 0.3, 0.2))
	_text(Vector2(x, py), "Thể trạng %d%%%s" % [int(c["condition"]), " (yếu: −10% ATK)" if bool(stats.get("weak", false)) else ""],
		UISkin.FS_BODY, cond_color, HORIZONTAL_ALIGNMENT_LEFT, -1, false, 4)
	_bar(Rect2(x, py + 8, pw - 20.0, 8), cond, cond_color)
	var lines: Array[String] = [
		"HP %d · ATK %.1f · DEF %.0f" % [int(stats["hp"]), float(stats["atk"]), float(stats["def"])],
		"SPD %.0f · WEIGHT %.1f · CRIT %d%%" % [float(stats["spd"]), float(stats["weight"]), int(round(float(stats["crit"]) * 100.0))],
		String(GameState.Breeds.info(breed).get("passive_text", "")),
	]
	var muts: PackedStringArray = []
	for m in c["mutations"]:
		muts.append(GameState.Mutations.display_name(m).split(" (")[0])
	if not muts.is_empty():
		lines.append("Đột biến: " + ", ".join(muts))
	var y: float = py + 46.0
	for line in lines:
		for part in _wrap(line, UISkin.FS_BODY, pw):
			if y > h - 34.0:
				break
			_text(Vector2(x, y), part, UISkin.FS_BODY, Color(0.95, 0.93, 0.88), HORIZONTAL_ALIGNMENT_LEFT, pw, false, 4)
			y += 28.0


func _draw_loadout(w: float, h: float) -> void:
	var x: float = w * 0.335
	var pw: float = w * 0.33
	var rect := Rect2(x, 70, pw, 6.0 * 46.0 + 70.0)
	_panel(rect, Color(0.85, 0.55, 0.2))
	_text(Vector2(x + 18, 102), "TRANG BỊ", UISkin.FS_SMALL, FRAME, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 3)
	var y: float = 124.0
	for i in range(SLOT_ROWS.size()):
		var slot: StringName = SLOT_ROWS[i]
		var row: int = i + 1
		var selected: bool = _row == row
		var item: StringName = GameState.equipped(GameState.active, slot)
		var label: String = String(GameState.Items.SLOT_NAMES.get(slot, "?"))
		var name: String = GameState.Items.display_name(item) if item != &"" else "— trống —"
		var avail: int = _options(slot).size() - 1
		if selected:
			_canvas.draw_rect(Rect2(x + 10, y - 18, pw - 20, 42), Color(1.0, 0.8, 0.3, 0.14))
			_canvas.draw_texture(UISkin.texture("cursor"), Vector2(x + 12 + (2.0 if fmod(_time, 0.6) < 0.3 else 0.0), y - 12))
		_text(Vector2(x + 36, y + 2), label, UISkin.FS_BODY, FRAME if selected else DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 3)
		var arrows: String = ("◀ %s ▶" % name) if selected and avail > 0 else name
		_text(Vector2(x + 118, y + 2), _fit(arrows, UISkin.FS_BODY, pw - 130.0), UISkin.FS_BODY, Color.WHITE if item != &"" else Color(0.6, 0.6, 0.6),
			HORIZONTAL_ALIGNMENT_LEFT, pw - 130.0, false, 3)
		var desc: String = String(GameState.ITEMS.get(item, {}).get("text", "")) if item != &"" else \
			("%d món trong kho" % avail if avail > 0 else "chưa có món nào trong kho")
		_text(Vector2(x + 118, y + 19), _fit(desc, UISkin.FS_SMALL, pw - 130.0), UISkin.FS_SMALL, Color(0.85, 0.8, 0.7), HORIZONTAL_ALIGNMENT_LEFT, pw - 130.0, false, 2)
		y += 46.0
	# Tay bài.
	var deck: PackedStringArray = []
	for card in GameState.cards:
		var info: Dictionary = GameState.CARD_INFO.get(card, {})
		deck.append("%s (%d)" % [String(info.get("name", String(card))), int(info.get("cost", 0))])
	_text(Vector2(x + 18, y + 2), _fit("Tay bài: " + (", ".join(deck) if not deck.is_empty() else "(chưa có thẻ)"), UISkin.FS_SMALL, pw - 36.0),
		UISkin.FS_SMALL, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_LEFT, pw - 36.0, true, 3)
	# Nút vào trận.
	var start_sel: bool = _row == _row_count() - 1
	var by: float = rect.end.y + 34.0
	var btn := Rect2(roundf(x + pw * 0.18), by - 30, roundf(pw * 0.64), 50)
	var pulse: float = 0.75 + 0.25 * sin(_time * 6.0)
	UISkin.draw_panel(_canvas, btn, &"button_hover" if start_sel else &"button")
	_text(Vector2(btn.position.x, UISkin.baseline_in(btn.position.y - 2.0, btn.size.y, UISkin.FS_BODY, true)), "VÀO TRẬN!", UISkin.FS_BODY,
		Color(1, 1, 1, pulse if start_sel else 0.85), HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, true, 4)
	if _police_ok:
		var py: float = h - 92.0
		_text(Vector2(x, py), "[G] Gọi tay trong (báo công an)", UISkin.FS_SMALL, Color(0.6, 0.78, 1.0, 0.75 + 0.25 * sin(_time * 3.0)),
			HORIZONTAL_ALIGNMENT_CENTER, pw, true, 3)
		_text(Vector2(x, py + 20), "Lén báo công an rồi cầm cự 30 giây: công an ập vào", UISkin.FS_SMALL, DIM, HORIZONTAL_ALIGNMENT_CENTER, pw, false, 2)
		_text(Vector2(x, py + 36), "là sới giải tán, không ai thắng. Bị hạ trước thì vẫn thua.", UISkin.FS_SMALL, DIM,
			HORIZONTAL_ALIGNMENT_CENTER, pw, false, 2)


func _draw_opponent(w: float, h: float) -> void:
	if opponent.is_empty():
		return
	var rx: float = w - 24.0
	var pw: float = w * 0.27
	_text(Vector2(0, 86), "ĐỐI THỦ", UISkin.FS_SMALL, Color(0.6, 0.78, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, rx, true, 3)
	_text(Vector2(0, 118), String(opponent.get("name", "?")).to_upper(), UISkin.FS_BODY, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, rx, true, 4)
	var breed: int = int(opponent.get("breed", 0))
	_text(Vector2(0, 150), "Chủ gà: %s · %s · Lv%d" % [String(opponent.get("owner", "?")), GameState.Breeds.display_name(breed),
		int(opponent.get("lv", 1))], UISkin.FS_BODY, Color(0.9, 0.92, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, rx, false, 4)
	var tier: int = clampi(int(opponent.get("tier", 1)), 1, 4)
	var lines: Array[String] = ["Bậc: T%d – %s" % [tier, TIER_TEXT[tier]]]
	var items: PackedStringArray = []
	for id in FighterView.gear_items(opponent):
		items.append(GameState.Items.display_name(id))
	lines.append("Đồ: " + (", ".join(items) if not items.is_empty() else "không đồ"))
	var muts: PackedStringArray = []
	for m in opponent.get("mutations", []):
		muts.append(GameState.Mutations.display_name(m).split(" (")[0])
	if not muts.is_empty():
		lines.append("Đột biến: " + ", ".join(muts))
	var habits: String = String(opponent.get("habits", ""))
	if habits == "":
		var traits: PackedStringArray = []
		if float(opponent.get("aggr", 0.5)) >= 0.6:
			traits.append("hung hăng, ép sát")
		if float(opponent.get("jumpy", 0.0)) >= 0.35:
			traits.append("hay nhảy")
		if float(opponent.get("block", 0.1)) >= 0.4:
			traits.append("đỡ chắc")
		if Moves.kit_for_side(opponent) == Moves.KIT_DONGTAO:
			traits.append("tank Thiết Giáp, Húc Trâu có giáp")
		if not traits.is_empty():
			habits = "Thói quen: " + ", ".join(traits)
	if habits != "":
		lines.append(habits)
	if bool(opponent.get("hell_mode", false)):
		lines.append("HELL MODE: đối thủ vào trận với 4 Card Gauge, hiệp 60 giây")
	var y: float = h * 0.56 + 14.0
	for line in lines:
		for part in _wrap(line, UISkin.FS_BODY, pw):
			if y > h - 34.0:
				break
			_text(Vector2(w - 24.0 - pw, y), part, UISkin.FS_BODY, Color(0.92, 0.94, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, pw, false, 4)
			y += 28.0
	var quote: String = String(opponent.get("quote", ""))
	if quote != "":
		y += 4.0
		for part in _wrap("“%s”" % quote, UISkin.FS_BODY, pw):
			if y > h - 34.0:
				break
			_text(Vector2(w - 24.0 - pw, y), part, UISkin.FS_BODY, Color(0.8, 0.82, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, pw, false, 3)
			y += 28.0


func _draw_power(w: float, h: float) -> void:
	if opponent.is_empty():
		return
	var m: float = GameState.mismatch(opponent)
	var share: float = 1.0 / (1.0 + maxf(m, 0.01))
	var bar := Rect2(w * 0.335, 70.0 + 6.0 * 46.0 + 70.0 + 84.0, w * 0.33, 14.0)
	_canvas.draw_rect(bar.grow(3), Color(0, 0, 0, 0.85))
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), Color(0.9, 0.3, 0.2))
	_canvas.draw_rect(Rect2(bar.position + Vector2(bar.size.x * share, 0), Vector2(bar.size.x * (1.0 - share), bar.size.y)),
		Color(0.25, 0.45, 0.95))
	_canvas.draw_line(Vector2(bar.position.x + bar.size.x * 0.5, bar.position.y - 4), Vector2(bar.position.x + bar.size.x * 0.5, bar.end.y + 4),
		Color(1, 1, 1, 0.7), 2.0)
	var verdict: String = "Ngang ngửa"
	if m >= GameState.POLICE_MISMATCH:
		verdict = "Đối thủ vượt trội ×%.2f" % m
	elif m >= 1.12:
		verdict = "Đối thủ nhỉnh hơn ×%.2f" % m
	elif m <= 0.88:
		verdict = "Gà mình trội hơn ×%.2f" % m
	_text(Vector2(bar.position.x - 40.0, bar.position.y - 10), "SỨC MẠNH: " + verdict, UISkin.FS_BODY, FRAME, HORIZONTAL_ALIGNMENT_CENTER,
		bar.size.x + 80.0, false, 4)
