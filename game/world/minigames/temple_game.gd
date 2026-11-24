extends "res://game/world/minigames/minigame.gd"

## TRANG ĐỀN LÀNG (thắp nhang + xin xăm): trong đền – cột son, hoành phi câu đối, khám thờ vàng, nến, đèn lồng,
## lư hương đồng giữa đền, ông từ đứng bên.
## 1. Thắp nhang: E cắm từng nén vô lư hương (3 nén), khói bay lên; khấn vái.
## 2. Xin xăm: lắc ống xăm bằng A và D xen kẽ cho đều tay – thanh "thành tâm" đầy thì một thẻ xăm văng ra.
## 3. Đọc thẻ: lá xăm hiện lời quẻ (runner chọn sẵn `fortune`), E để về.
## Kết quả: {fortune, incense} hoặc {cancelled}.

const URN: Vector2 = Vector2(192, 170)
const HERO_POS: Vector2 = Vector2(192, 214)
const CUP_POS: Vector2 = Vector2(150, 206)
const STICK_SLOTS: Array[float] = [-9.0, 0.0, 9.0]
const SHAKE_GAIN: float = 0.085
const SHAKE_DECAY: float = 0.1

var fortune: String = ""
var prayer: String = "cả nhà"

var _step: StringName = &"incense"   # incense | pray | shake | slip
var _lit: int = 0
var _sticks: Array[Dictionary] = []   # {sprite, from, to, t}
var _smoke_t: float = 0.0
var _pray_t: float = 0.0
var _devotion: float = 0.0
var _last_side: StringName = &""
var _tilt: float = 0.0
var _tilt_v: float = 0.0
var _slip_t: float = 0.0
var _auto_t: float = 0.0
var _time: float = 0.0
var _hero: Sprite2D
var _cup: Sprite2D
var _cup_root: Node2D
var _fallen: Sprite2D
var _fall_t: float = -1.0
var _candles: Array[Sprite2D] = []
var _lanterns: Array[Sprite2D] = []
var _keeper: Sprite2D
var _meter: Node2D
var _slip: PanelContainer
var _slip_text: Label


func _page() -> String:
	return "temple"


func _intro() -> Array:
	return ["THẮP NHANG – XIN XĂM", "Đền thờ vua Hùng, ông từ đã thắp đèn sẵn.\n\n1. Nhấn [E] cắm từng nén nhang vô lư hương (3 nén) rồi khấn vái.\n2. Lắc ống xăm: bấm [A] rồi [D] xen kẽ cho đều tay đến khi một thẻ xăm văng ra.\n3. Đọc lời quẻ trên lá xăm."]


func _hint_text() -> String:
	return "[E] Cắm nhang   ·   [Esc] Thôi"


func _music() -> StringName:
	return &"memory"


func _ambience() -> Dictionary:
	return {&"leaves": 0.25, &"crickets": 0.15, &"birds": 0.1}


func _build() -> void:
	backdrop("bg")
	for x in [118.0, 266.0]:
		_candles.append(sprite(frame("candle", 2, 0), Vector2(x, 112), -4))
	for x in [92.0, 292.0]:
		_lanterns.append(sprite(frame("lantern", 2, 0), Vector2(x, 26), -4))
	_keeper = sprite(tex("keeper"), Vector2(312, 186), 0)
	_keeper.flip_h = true
	sprite(tex("urn"), URN, 1)
	_hero = hero_sprite(HERO_POS, 8, 2)
	_cup_root = Node2D.new()
	_cup_root.position = CUP_POS
	_cup_root.z_index = 6
	_cup_root.visible = false
	add_child(_cup_root)
	_cup = Sprite2D.new()
	_cup.texture = tex("cup")
	_cup.centered = false
	if _cup.texture != null:
		_cup.offset = Vector2(-_cup.texture.get_width() * 0.5, -_cup.texture.get_height())
	_cup_root.add_child(_cup)
	_meter = Node2D.new()
	_meter.z_index = 7
	_meter.draw.connect(_draw_meter)
	add_child(_meter)
	_slip = make_panel()
	_slip.custom_minimum_size = Vector2(520, 0)
	_slip.set_anchors_preset(Control.PRESET_CENTER)
	_slip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_slip.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui.add_child(_slip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_slip.add_child(box)
	var head := make_label(UISkin.FS_BIG, Color(0.7, 0.12, 0.08), true)
	head.text = "~ LÁ XĂM ~"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	_slip_text = make_label(UISkin.FS_BODY, INK)
	_slip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slip_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slip_text.custom_minimum_size = Vector2(480, 0)
	box.add_child(_slip_text)
	var keys := make_label(UISkin.FS_BODY, INK_SOFT)
	keys.text = "[E] Cất lá xăm"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)
	_slip.visible = false
	ui.move_child(_slip, 0)


func _wants(action: StringName) -> bool:
	return action in [&"confirm", &"cancel", &"left", &"right"]


func _start() -> void:
	use_timer(false)
	_update_status()


func _on_action(action: StringName) -> void:
	match _step:
		&"incense":
			if action == &"confirm" and _lit < 3 and _sticks.size() == _lit:
				_light()
		&"shake":
			if action == &"left" or action == &"right":
				_shake_cup(action)
		&"slip":
			if action == &"confirm" and _slip_t >= 0.5:
				finish({"fortune": fortune, "incense": _lit}, 0.1)


func _light() -> void:
	var s := Sprite2D.new()
	s.texture = tex("incense")
	s.z_index = 0 # sau lư hương: chân nhang khuất trong tro
	add_child(s)
	var to: Vector2 = URN + Vector2(STICK_SLOTS[_sticks.size()], -42)
	_sticks.append({"sprite": s, "from": HERO_POS + Vector2(4, -30), "to": to, "t": 0.0})
	sound(&"incense", to)


func _shake_cup(side: StringName) -> void:
	if side == _last_side:
		_tilt_v += (0.08 if side == &"right" else -0.08)
		return
	_last_side = side
	_devotion = minf(1.0, _devotion + SHAKE_GAIN)
	_tilt_v += 0.35 if side == &"right" else -0.35
	sfx(&"ui_move", -14.0, 1.6 + randf() * 0.3)
	if _devotion >= 1.0:
		_drop_stick()


func _drop_stick() -> void:
	_step = &"pray_done"
	_fallen = Sprite2D.new()
	_fallen.texture = tex("stick")
	_fallen.z_index = 8
	add_child(_fallen)
	_fall_t = 0.0
	sound(&"xam", CUP_POS)


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "incense": _lit}


func _result_info(_r: Dictionary) -> Array:
	return ["ĐÃ XIN ĐƯỢC QUẺ", "Thắp %d nén nhang, khấn cho %s mạnh giỏi.\n«%s»" % [_lit, prayer, fortune], true]


func _update_status() -> void:
	match _step:
		&"incense":
			set_status("Nhang: %d/3 nén" % _lit)
		&"pray":
			set_status("Khấn vái…")
		&"shake", &"pray_done":
			set_status("Lắc ống xăm: %d%%" % int(_devotion * 100.0))
		&"slip":
			set_status("Đọc lá xăm")


func _tick(delta: float) -> void:
	match _step:
		&"incense":
			if _lit >= 3:
				_step = &"pray"
				_pray_t = 1.6
				toast("Khấn cho %s mạnh giỏi…" % prayer, Color(1.0, 0.9, 0.6))
		&"pray":
			_pray_t -= delta
			if _pray_t <= 0.0:
				_step = &"shake"
				_cup_root.visible = true
				set_texts("THẮP NHANG – XIN XĂM", "[A] rồi [D] xen kẽ: lắc ống xăm   ·   [Esc] Thôi")
				toast("Lắc ống xăm!", Color(1.0, 0.85, 0.45))
		&"shake":
			_devotion = maxf(0.0, _devotion - SHAKE_DECAY * delta)
		&"slip":
			_slip_t += delta
	if autopilot:
		_auto_t += delta
		match _step:
			&"incense":
				if _auto_t >= 0.3:
					_auto_t = 0.0
					press(&"confirm")
			&"shake":
				if _auto_t >= 0.07:
					_auto_t = 0.0
					press(&"left" if _last_side != &"left" else &"right")
			&"slip":
				if _slip_t >= 0.6:
					press(&"confirm")
	_update_status()


func _animate(delta: float) -> void:
	_time += delta
	for i in range(_candles.size()):
		_candles[i].texture = frame("candle", 2, int(_time * 7.0 + float(i)) % 2)
	for i in range(_lanterns.size()):
		_lanterns[i].texture = frame("lantern", 2, int(_time * 1.2 + float(i)) % 2)
	_keeper.position.y = 186.0 - (1.0 if int(_time * 1.1) % 2 == 0 else 0.0)
	# nén nhang bay vô lư hương
	for st in _sticks:
		var t: float = minf(float(st["t"]) + delta / 0.45, 1.0)
		var was: float = float(st["t"])
		st["t"] = t
		var p: Vector2 = (st["from"] as Vector2).lerp(st["to"], ease(t, 0.6)) + Vector2(0, -sin(t * PI) * 10.0)
		(st["sprite"] as Sprite2D).position = p.round() + Vector2(0, 13)
		if was < 1.0 and t >= 1.0:
			_lit += 1
			fxl.call("burst", st["to"] + Vector2(0, -12), Color(1.0, 0.7, 0.3), 6, 12.0, -10.0, 0.6, 4.0)
	_smoke_t -= delta
	if _smoke_t <= 0.0:
		_smoke_t = 0.22
		for st in _sticks:
			if float(st["t"]) >= 1.0:
				fxl.call("smoke", (st["to"] as Vector2) + Vector2(0, -1), 1)
	# người chơi: cúi lạy khi khấn
	var bow: float = 0.0
	if _step == &"pray":
		bow = 2.0 if int(_pray_t * 2.5) % 2 == 0 else 0.0
	_hero.position = HERO_POS + Vector2(0, bow)
	# ống xăm lắc (lò xo)
	_tilt_v += -_tilt * 40.0 * delta
	_tilt_v *= 1.0 - minf(1.0, 6.0 * delta)
	_tilt += _tilt_v * delta * 10.0
	_tilt = clampf(_tilt, -0.5, 0.5)
	_cup_root.rotation = _tilt
	_cup_root.position = CUP_POS + Vector2(roundf(_tilt * 6.0), 0)
	if _fall_t >= 0.0:
		_fall_t += delta
		var t: float = minf(_fall_t / 0.8, 1.0)
		var start: Vector2 = CUP_POS + Vector2(0, -50)
		var land: Vector2 = CUP_POS + Vector2(40, -6)
		_fallen.position = start.lerp(land, t) + Vector2(0, -sin(t * PI) * 34.0)
		_fallen.rotation = t * 9.0
		if t >= 1.0 and _step == &"pray_done":
			_fallen.rotation = PI * 0.5
			fxl.call("burst", land, Color(0.9, 0.8, 0.5), 6, 18.0, 60.0, 0.4, 8.0)
			_step = &"slip"
			_slip_t = 0.0
			_slip_text.text = fortune
			_slip.visible = true
			_cup_root.visible = false
			set_texts("THẮP NHANG – XIN XĂM", "[E] Cất lá xăm")
	_meter.queue_redraw()


func _draw_meter() -> void:
	if not _cup_root.visible:
		return
	var r := Rect2(CUP_POS + Vector2(-34, -54), Vector2(8, 50))
	_meter.draw_rect(r.grow(2), Color(0.2, 0.08, 0.04))
	_meter.draw_rect(r.grow(1), Color(0.85, 0.6, 0.2))
	_meter.draw_rect(r, Color(0.3, 0.1, 0.08))
	var h: float = r.size.y * _devotion
	_meter.draw_rect(Rect2(Vector2(r.position.x, r.end.y - h), Vector2(r.size.x, h)), Color(0.95, 0.35, 0.2))
	_meter.draw_rect(Rect2(Vector2(r.position.x, r.end.y - h), Vector2(r.size.x, 1)), Color(1.0, 0.8, 0.4))
	# mũi tên nhắc lắc qua bên nào kế tiếp (A = trái, D = phải)
	var want_left: bool = _last_side != &"left"
	for k in range(2):
		var dir: float = -1.0 if k == 0 else 1.0
		var c: Vector2 = CUP_POS + Vector2(dir * 24.0, -30)
		var on: bool = (k == 0) == want_left
		var col := Color(1.0, 0.85, 0.35) if on else Color(0.45, 0.3, 0.2, 0.7)
		var pulse: float = 1.0 + (0.3 * sin(_time * 12.0) if on else 0.0)
		var tri := PackedVector2Array([c + Vector2(dir * 6.0 * pulse, 0), c + Vector2(-dir * 2.0, -5), c + Vector2(-dir * 2.0, 5)])
		_meter.draw_colored_polygon(tri, col)


func _cleanup() -> void:
	_slip.visible = false
