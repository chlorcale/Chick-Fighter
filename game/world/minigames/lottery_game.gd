extends "res://game/world/minigames/minigame.gd"

## TRANG VÉ SỐ: góc lề đường trước quán cà phê, cô bán vé số đứng cạnh bảng vé kẹp đầy màu.
## - MODE_BUY: cô xòe 5 tờ vé, A/D lựa tờ ưng ý, E lấy. Kết quả {ticket}. (Giá + tỉ lệ trúng giữ nguyên – runner trừ
##   tiền và gọi Activities.buy_lottery_ticket(số đã lựa).)
## - MODE_CHECK: dò vé bữa trước trên bảng kết quả phủ lớp bạc: A/D dời đồng xu qua 6 ô, E cào cho lộ số. Kết quả xổ
##   đã quyết trước (Activities.draw_lottery – `won`); trang chỉ dựng số trúng cho khớp: giải khuyến khích = lệch đúng
##   một chữ số (trừ hàng trăm ngàn), an ủi = chỉ lệch hàng trăm ngàn, trật = lệch từ hai số trở lên.
##   Kết quả {won}.

const Activities := preload("res://game/world/activities.gd")
const MODE_BUY: StringName = &"buy"
const MODE_CHECK: StringName = &"check"
const PRIZE: int = 50000
const CONSOLATION: int = 10000
const TICKETS: int = 5
const SELLER_POS: Vector2 = Vector2(206, 174)
const BOARD_POS: Vector2 = Vector2(92, 36)
const CELL0: Vector2 = Vector2(105, 62)
const CELL: Vector2 = Vector2(26, 34)
const CELL_GAP: float = 30.0
const SCRATCH_PER_PRESS: float = 0.34

var mode: StringName = MODE_BUY
var ticket: String = "000000"
var won: int = 0
var rng_seed: int = 1

var _rng := RandomNumberGenerator.new()
var _numbers: Array[String] = []
var _sel: int = 2
var _winning: String = ""
var _scratch: Array[float] = [0, 0, 0, 0, 0, 0]
var _noise: Array = []        # mỗi ô: mảng ngưỡng ngẫu nhiên cho từng điểm bạc
var _cell: int = 0
var _rub: float = 0.0
var _done_t: float = -1.0
var _auto_t: float = 0.0
var _time: float = 0.0
var _seller: Sprite2D
var _hero: Sprite2D
var _layer: Node2D
var _silver: Node2D
var _coin: Node2D
var _labels: Array[Label] = []
var _board_title: Label
var _mine: Label


func _page() -> String:
	return "lottery"


func _intro() -> Array:
	if mode == MODE_CHECK:
		return ["DÒ VÉ SỐ", "Vé của bạn: %s\n\nBảng kết quả còn phủ lớp bạc. [A]/[D] dời đồng xu qua từng ô, [E] cào cho lộ số.\nTrùng 5 số cuối là trúng an ủi; lệch đúng một số là giải khuyến khích!" % ticket]
	return ["MUA VÉ SỐ", "Cô bán vé số xòe ra năm tờ, tờ nào cũng đẹp số!\n\n[A]/[D] lựa tờ ưng ý, [E] lấy tờ đó (%s).\nMai xổ – ngủ một giấc rồi quay lại dò nghen." % GameState.money_text(Activities.LOTTERY_PRICE)]


func _hint_text() -> String:
	if mode == MODE_CHECK:
		return "[A]/[D] Dời đồng xu   ·   [E] Cào   ·   [Esc] Thôi"
	return "[A]/[D] Lựa vé   ·   [E] Lấy tờ này   ·   [Esc] Thôi"


func _ambience() -> Dictionary:
	return {&"village": 0.5, &"crowd": 0.2, &"birds": 0.2}


func _build() -> void:
	_rng.seed = rng_seed
	backdrop("bg")
	_seller = sprite(tex("seller"), SELLER_POS, 0)
	_hero = hero_sprite(Vector2(100, 196), 16, 1)
	toast_y = 400.0
	_layer = Node2D.new()
	_layer.z_index = 4
	_layer.draw.connect(_draw_layer)
	add_child(_layer)
	_silver = Node2D.new()
	_silver.z_index = 5
	_silver.draw.connect(_draw_silver)
	add_child(_silver)
	_coin = Node2D.new()
	_coin.z_index = 7
	_coin.draw.connect(_draw_coin)
	add_child(_coin)
	if mode == MODE_BUY:
		for i in range(TICKETS):
			_numbers.append("%06d" % _rng.randi_range(0, 999999))
			var l := make_label(UISkin.FS_BODY, Color(0.75, 0.12, 0.08), true)
			l.text = _numbers[i]
			ui.add_child(l)
			ui.move_child(l, 0)
			_labels.append(l)
	else:
		_winning = _make_winning()
		for i in range(6):
			var thresholds: Array[float] = []
			for k in range(CELL.x * CELL.y):
				thresholds.append(_rng.randf())
			_noise.append(thresholds)
			var l := make_label(UISkin.FS_HUGE, INK, true)
			l.text = _winning[i]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			ui.add_child(l)
			ui.move_child(l, 0)
			_labels.append(l)
		_board_title = make_label(UISkin.FS_BODY, Color(1.0, 0.92, 0.6), true)
		_board_title.text = "KẾT QUẢ XỔ SỐ KIẾN THIẾT"
		_board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui.add_child(_board_title)
		ui.move_child(_board_title, 0)
		_mine = make_label(UISkin.FS_BODY, Color(0.75, 0.12, 0.08), true)
		_mine.text = ticket
		ui.add_child(_mine)
		ui.move_child(_mine, 0)


## Số trúng khớp với kết quả đã xổ (won).
func _make_winning() -> String:
	var digits: PackedStringArray = []
	for c in ticket:
		digits.append(c)
	if won >= PRIZE:
		var i: int = _rng.randi_range(1, 5)
		digits[i] = str((int(digits[i]) + _rng.randi_range(1, 9)) % 10)
	elif won >= CONSOLATION:
		digits[0] = str((int(digits[0]) + _rng.randi_range(1, 9)) % 10)
	else:
		var a: int = _rng.randi_range(1, 5)
		var b: int = (a + _rng.randi_range(1, 5)) % 6
		for i in [a, b]:
			digits[i] = str((int(digits[i]) + _rng.randi_range(1, 9)) % 10)
	return "".join(digits)


func _wants(action: StringName) -> bool:
	return action in [&"confirm", &"cancel", &"left", &"right"]


func _start() -> void:
	use_timer(false)
	_update_status()


func _on_action(action: StringName) -> void:
	if mode == MODE_BUY:
		match action:
			&"left":
				_sel = maxi(_sel - 1, 0)
				sfx(&"ui_move", -10.0)
			&"right":
				_sel = mini(_sel + 1, TICKETS - 1)
				sfx(&"ui_move", -10.0)
			&"confirm":
				sound(&"ticket")
				finish({"ticket": _numbers[_sel]}, 0.4)
		return
	if _done_t >= 0.0:
		return
	match action:
		&"left":
			_cell = maxi(_cell - 1, 0)
		&"right":
			_cell = mini(_cell + 1, 5)
		&"confirm":
			if _scratch[_cell] >= 1.0:
				_cell = _next_unscratched()
				return
			_scratch[_cell] = minf(1.0, _scratch[_cell] + SCRATCH_PER_PRESS + 0.001)
			_silver.queue_redraw()
			_rub = 0.25
			var p: Vector2 = _cell_rect(_cell).get_center()
			fxl.call("burst", p, Color(0.82, 0.84, 0.88), 8, 26.0, 90.0, 0.5, 14.0)
			sfx(&"ui_move", -12.0, 0.7 + randf() * 0.2)
			if _scratch[_cell] >= 1.0:
				_labels[_cell].add_theme_color_override("font_color", GOOD if _winning[_cell] == ticket[_cell] else BAD)
				if _next_unscratched() < 0:
					_reveal()
				else:
					_cell = _next_unscratched()
	_update_status()


func _next_unscratched() -> int:
	for i in range(6):
		if _scratch[i] < 1.0:
			return i
	return -1


func _reveal() -> void:
	_done_t = 0.0
	if won >= PRIZE:
		toast("TRÚNG GIẢI KHUYẾN KHÍCH!", Color(1.0, 0.9, 0.3))
		sound(&"win")
		sfx(&"coin")
	elif won >= CONSOLATION:
		toast("Trúng an ủi!", Color(0.7, 1.0, 0.6))
		sfx(&"coin")
	else:
		toast("Trật lất rồi…", Color(1.0, 0.7, 0.55))


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "won": won}


func _result_info(r: Dictionary) -> Array:
	if mode == MODE_BUY:
		return ["MUA ĐƯỢC VÉ!", "Tờ số %s. Mai xổ – nhớ quay lại dò nghen." % String(r.get("ticket", "")), true]
	if won >= PRIZE:
		return ["TRÚNG RỒI!", "Vé %s – kết quả %s.\nGiải khuyến khích %s!" % [ticket, _winning, GameState.money_text(won)], true]
	if won >= CONSOLATION:
		return ["TRÚNG AN ỦI", "Vé %s – kết quả %s.\nCô hoàn lại tiền vé %s." % [ticket, _winning, GameState.money_text(won)], true]
	return ["TRẬT RỒI…", "Vé %s – kết quả %s.\nCủa đi thay người, hên xui mà." % [ticket, _winning], false]


func _update_status() -> void:
	if mode == MODE_BUY:
		set_status("Đang lựa tờ %d/%d" % [_sel + 1, TICKETS])
	else:
		var n: int = 0
		for v in _scratch:
			if v >= 1.0:
				n += 1
		set_status("Đã cào: %d/6 ô" % n)


func _tick(delta: float) -> void:
	if mode == MODE_CHECK and _done_t >= 0.0:
		_done_t += delta
		if _done_t >= 1.2:
			finish({"won": won}, 0.2)
		return
	if not autopilot:
		return
	_auto_t += delta
	if _auto_t < 0.12:
		return
	_auto_t = 0.0
	if mode == MODE_BUY:
		press(&"confirm")
	else:
		press(&"confirm")


func _animate(delta: float) -> void:
	_time += delta
	_rub = maxf(_rub - delta, 0.0)
	_seller.position.y = SELLER_POS.y - (1.0 if int(_time * 1.5) % 2 == 0 else 0.0)
	_hero.texture = hero_texture(16 if int(_time * 2.0) % 4 != 0 else 17)
	var z: float = view_zoom()
	if mode == MODE_BUY:
		for i in range(_labels.size()):
			var p: Vector2 = _ticket_pos(i)
			_labels[i].position = to_screen(p + Vector2(-8, -27))
			_labels[i].visible = running
	else:
		for i in range(6):
			var r: Rect2 = _cell_rect(i)
			_labels[i].position = to_screen(r.position)
			_labels[i].size = r.size * z
			_labels[i].modulate.a = clampf((_scratch[i] - 0.25) / 0.6, 0.0, 1.0)
		_board_title.position = to_screen(BOARD_POS + Vector2(3, 3))
		_board_title.size = Vector2(194, 13) * z
		_mine.position = to_screen(Vector2(192, 190) + Vector2(-8, -27))
	_layer.queue_redraw()
	_coin.queue_redraw()


func _ticket_pos(i: int) -> Vector2:
	var raised: float = 10.0 if i == _sel else 0.0
	return Vector2(80.0 + float(i) * 56.0, 194.0 - raised + absf(float(i) - 2.0) * 4.0)


func _cell_rect(i: int) -> Rect2:
	return Rect2(CELL0 + Vector2(float(i) * CELL_GAP, 0), CELL)


func _draw_layer() -> void:
	var t: Texture2D = tex("ticket")
	if mode == MODE_BUY:
		for i in range(TICKETS):
			if t == null:
				break
			var p: Vector2 = _ticket_pos(i)
			var pos := Vector2(p.x - t.get_width() * 0.5, p.y - t.get_height()).round()
			_layer.draw_texture(t, pos, Color.WHITE if i == _sel else Color(0.88, 0.85, 0.8))
			if i == _sel:
				_layer.draw_rect(Rect2(pos - Vector2(2, 2), Vector2(t.get_width() + 4, t.get_height() + 4)), Color(1.0, 0.85, 0.3, 0.6 + 0.4 * sin(_time * 8.0)), false, 2.0)
		return
	var board: Texture2D = tex("result_board")
	if board != null:
		_layer.draw_texture(board, BOARD_POS)
	for i in range(6):
		var r: Rect2 = _cell_rect(i)
		_layer.draw_rect(r.grow(1), Color(0.3, 0.25, 0.2))
		_layer.draw_rect(r, Color(1.0, 0.98, 0.9))
	if t != null:
		var p := Vector2(192, 190)
		_layer.draw_texture(t, Vector2(p.x - t.get_width() * 0.5, p.y - t.get_height()).round())


func _draw_coin() -> void:
	if mode == MODE_CHECK and running and _done_t < 0.0:
		var coin: Texture2D = tex("coin")
		var c: Vector2 = _cell_rect(_cell).get_center() + Vector2(6, 8)
		if _rub > 0.0:
			c += Vector2(sin(_time * 50.0) * 3.0, cos(_time * 40.0) * 2.0)
		else:
			c.y += sin(_time * 5.0) * 1.5
		if coin != null:
			_coin.draw_texture(coin, (c - Vector2(6, 6)).round())


## Lớp bạc phủ 6 ô (chỉ vẽ lại khi cào): điểm nào có ngưỡng ≥ độ cào thì còn bạc. Chữ số (nhãn HUD) hiện dần theo.
func _draw_silver() -> void:
	if mode != MODE_CHECK:
		return
	for i in range(6):
		var r: Rect2 = _cell_rect(i)
		var amount: float = _scratch[i]
		if amount >= 1.0:
			continue
		var th: Array = _noise[i]
		for y in range(int(CELL.y)):
			for x in range(int(CELL.x)):
				if float(th[y * int(CELL.x) + x]) >= amount:
					var shade: float = 0.72 + 0.12 * float((x + y) % 3 == 0)
					_silver.draw_rect(Rect2(r.position + Vector2(x, y), Vector2(1, 1)), Color(shade, shade + 0.02, shade + 0.06))


func _cleanup() -> void:
	for l in _labels:
		l.visible = false
	if _mine != null:
		_mine.visible = false
	if _board_title != null:
		_board_title.visible = false
