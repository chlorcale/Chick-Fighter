extends "res://game/world/minigames/minigame.gd"

## TRANG GẶT LÚA: đồng lúa chín vàng theo phối cảnh, trâu trên bờ, cò trắng, cô bác nón lá cúi gặt phía xa.
## Một hàng TUFTS bụi lúa trước mặt; vạch đỏ chạy qua lại trên thanh nhịp – nhấn E khi vạch nằm trong ô vàng để
## phạt một bụi (giữa ô = "Ngọt!"), lúa thành bó bay lên đống bên phải, người chơi bước tới bụi kế.
## Trật thì khựng tay một chút. TIME_LIMIT giây. Kết quả: {bundles, misses, perfect}.

const ROW_BASE: float = 178.0
const FIRST_X: float = 96.0
const STEP: float = 26.0
const TUFTS: int = 8
const STAND_GAP: float = 15.0
const TIME_LIMIT: float = 30.0
const PILE: Vector2 = Vector2(338, 188)
const BAR_W: float = 460.0

var _tufts: Array[Sprite2D] = []
var _stubble: Array[Sprite2D] = []
var _bundles: Array[Sprite2D] = []
var _flying: Array[Dictionary] = []  # {sprite, from, to, t}
var _hero: Sprite2D
var _sickle: Sprite2D
var _buffalo: Sprite2D
var _farmers: Array[Sprite2D] = []
var _egret_fly: Sprite2D
var _bar: Control
var _cut: int = 0
var _misses: int = 0
var _perfect: int = 0
var _cursor_pos: float = 0.0
var _cursor_dir: float = 1.0
var _zone_center: float = 0.5
var _zone_width: float = 0.22
var _stun: float = 0.0
var _stepping: bool = false
var _swing: float = 0.0
var _walk: float = 0.0
var _time: float = 0.0
var _fly_x: float = -40.0


func _page() -> String:
	return "farm"


func _intro() -> Array:
	return ["GẶT LÚA", "Lúa chín vàng đồng, Cô Năm thiếu người gặt!\n\nVạch đỏ chạy qua lại trên thanh nhịp. Nhấn [E] khi vạch nằm trong ô vàng để phạt một bụi lúa – ngay giữa ô là gặt \"ngọt\" nhất.\nTrật thì khựng tay. Gặt hết hàng %d bụi trong %d giây!" % [TUFTS, int(TIME_LIMIT)]]


func _hint_text() -> String:
	return "[E] Phạt lúa   ·   [Esc] Nghỉ"


func _ambience() -> Dictionary:
	return {&"birds": 0.6, &"leaves": 0.45, &"village": 0.1}


func _build() -> void:
	backdrop("bg")
	_buffalo = sprite(frame("buffalo", 2, 0), Vector2(52, 108), -5)
	sprite(tex("egret"), Vector2(158, 128), -5)
	sprite(tex("egret"), Vector2(206, 121), -5).flip_h = true
	_farmers.append(sprite(frame("farmer_a", 2, 0), Vector2(250, 144), -4))
	_farmers.append(sprite(frame("farmer_b", 2, 0), Vector2(318, 130), -4))
	_farmers[1].flip_h = true
	_egret_fly = sprite(frame("egret_fly", 2, 0), Vector2(-40, 30), -6)
	for i in range(TUFTS):
		var x: float = FIRST_X + STEP * float(i)
		var s: Sprite2D = sprite(frame("tuft", 2, i % 2), Vector2(x, ROW_BASE), 2)
		_tufts.append(s)
		var st: Sprite2D = sprite(tex("stubble"), Vector2(x, ROW_BASE + 1), 1)
		st.visible = false
		_stubble.append(st)
	_hero = hero_sprite(_stand_pos(0), 16, 3)
	_sickle = Sprite2D.new()
	_sickle.texture = tex("sickle")
	_sickle.position = Vector2(7, -18)
	_sickle.offset = Vector2(-2, -10)
	_hero.add_child(_sickle)
	_build_bar()


func _build_bar() -> void:
	_bar = Control.new()
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -BAR_W * 0.5 - 8
	_bar.offset_right = BAR_W * 0.5 + 8
	_bar.offset_top = -118
	_bar.offset_bottom = -78
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_bar.visible = false
	ui.add_child(_bar)
	ui.move_child(_bar, 0)


func _start() -> void:
	time_left = TIME_LIMIT
	_bar.visible = true
	_new_zone()
	_update_status()


func _new_zone() -> void:
	_zone_width = maxf(0.13, 0.22 - 0.012 * float(_cut))
	_zone_center = randf_range(0.15 + _zone_width * 0.5, 0.85 - _zone_width * 0.5)


func _stand_pos(i: int) -> Vector2:
	return Vector2(FIRST_X + STEP * float(i) - STAND_GAP, ROW_BASE + 3.0)


func _in_zone() -> bool:
	return absf(_cursor_pos - _zone_center) <= _zone_width * 0.5


func _on_action(action: StringName) -> void:
	if action != &"confirm" or _stun > 0.0 or _stepping or _cut >= TUFTS:
		return
	if _in_zone():
		_cut_tuft(absf(_cursor_pos - _zone_center) <= _zone_width * 0.18)
	else:
		_misses += 1
		_stun = 0.45
		_swing = 0.2
		toast("Trật rồi!", Color(1.0, 0.6, 0.5))
		sound(&"miss", _tufts[_cut].position)


func _cut_tuft(perfect: bool) -> void:
	var i: int = _cut
	var pos: Vector2 = _tufts[i].position + Vector2(0, -12)
	_cut += 1
	if perfect:
		_perfect += 1
	_swing = 0.3
	_tufts[i].visible = false
	_stubble[i].visible = true
	fxl.call("burst", pos, Color(0.98, 0.85, 0.35), 16 if perfect else 10, 40.0, 70.0, 0.7, 24.0)
	fxl.call("burst", pos, Color(0.7, 0.55, 0.2), 6, 24.0, 50.0, 0.5, 12.0)
	sound(&"cut", pos)
	if perfect:
		toast(["Ngọt!", "Ngọt xớt!", "Đẹp!"][_perfect % 3], Color(1.0, 0.92, 0.45))
	else:
		toast(["Gọn!", "Được!", "Ổn!"][_cut % 3], Color(0.7, 1.0, 0.6))
	# bó lúa bay lên đống
	var b: Sprite2D = sprite(tex("bundle"), pos, 4)
	var slot: int = _bundles.size()
	var to: Vector2 = PILE + Vector2(float(slot % 3) * 14.0 - 14.0 + float(slot / 3 % 2) * 7.0, -float(slot / 3) * 7.0)
	_flying.append({"sprite": b, "from": pos, "to": to, "t": 0.0})
	_bundles.append(b)
	_update_status()
	if _cut >= TUFTS:
		sound(&"win", pos)
		_stepping = true
		finish({"bundles": _cut, "misses": _misses, "perfect": _perfect}, 1.0)
		return
	_new_zone()
	_stepping = true
	_walk = 0.0
	var tween := create_tween()
	tween.tween_interval(0.15)
	tween.tween_property(_hero, "position", _stand_pos(_cut), 0.25)
	tween.tween_callback(func() -> void: _stepping = false)


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "bundles": _cut, "misses": _misses}


func _result_info(r: Dictionary) -> Array:
	var n: int = int(r.get("bundles", 0))
	if n >= TUFTS:
		return ["GẶT SẠCH HÀNG!", "%d bó lúa vàng óng · %d nhát \"ngọt\" · trật %d lần." % [n, int(r.get("perfect", 0)), int(r.get("misses", 0))], true]
	if n == 0:
		return ["HẾT GIỜ…", "Chưa gặt được bụi nào. Canh vạch đỏ vô ô vàng rồi hẵng phạt nghen.", false]
	return ["HẾT GIỜ!", "Gặt được %d/%d bó · trật %d lần." % [n, TUFTS, int(r.get("misses", 0))], true]


func _update_status() -> void:
	set_status("Đã gặt: %d/%d bó" % [_cut, TUFTS])


func _tick(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0 and not _stepping:
		finish({"bundles": _cut, "misses": _misses, "perfect": _perfect})
		return
	if _stun > 0.0:
		_stun -= delta
	else:
		var speed: float = 1.15 + 0.09 * float(_cut)
		_cursor_pos += _cursor_dir * speed * delta
		if _cursor_pos >= 1.0:
			_cursor_pos = 1.0
			_cursor_dir = -1.0
		elif _cursor_pos <= 0.0:
			_cursor_pos = 0.0
			_cursor_dir = 1.0
	if autopilot and absf(_cursor_pos - _zone_center) <= 0.03:
		press(&"confirm")
	_update_status()
	_bar.queue_redraw()


func _animate(delta: float) -> void:
	_time += delta
	for i in range(_tufts.size()):
		_tufts[i].texture = frame("tuft", 2, int(_time * 1.6 + float(i) * 0.37) % 2)
	_buffalo.texture = frame("buffalo", 2, int(_time * 1.2) % 2)
	for k in range(_farmers.size()):
		_farmers[k].texture = frame("farmer_a" if k == 0 else "farmer_b", 2, int(_time * 1.7 + float(k)) % 2)
	# cò bay ngang trời
	_fly_x += delta * 34.0
	if _fly_x > 520.0:
		_fly_x = -60.0
	_egret_fly.position = Vector2(_fly_x, 34.0 + sin(_fly_x * 0.03) * 6.0).round()
	_egret_fly.texture = frame("egret_fly", 2, int(_time * 5.0) % 2)
	# người chơi: bước / đứng / vung liềm
	_walk += delta
	if _stepping and _cut < TUFTS:
		_hero.texture = hero_texture(hero_walk(&"right", _walk))
	else:
		_hero.texture = hero_texture(16)
	_swing = maxf(_swing - delta, 0.0)
	_sickle.rotation = -1.6 * sin(_swing / 0.3 * PI) if _swing > 0.0 else 0.25
	for f in _flying.duplicate():
		f["t"] = float(f["t"]) + delta / 0.5
		var t: float = minf(float(f["t"]), 1.0)
		var p: Vector2 = (f["from"] as Vector2).lerp(f["to"], t) + Vector2(0, -sin(t * PI) * 30.0)
		(f["sprite"] as Sprite2D).position = p.round()
		if t >= 1.0:
			_flying.erase(f)


func _draw_bar() -> void:
	var size: Vector2 = _bar.size
	var frame_c := Color(0.36, 0.18, 0.08)
	_bar.draw_rect(Rect2(Vector2.ZERO, size), frame_c)
	_bar.draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(0.72, 0.45, 0.2))
	var track := Rect2(Vector2(8, 8), Vector2(BAR_W, size.y - 16))
	_bar.draw_rect(track, Color(0.36, 0.52, 0.24))
	_bar.draw_rect(Rect2(track.position, Vector2(BAR_W, 3)), Color(0.46, 0.64, 0.3))
	var zx: float = track.position.x + BAR_W * (_zone_center - _zone_width * 0.5)
	_bar.draw_rect(Rect2(Vector2(zx, track.position.y), Vector2(BAR_W * _zone_width, track.size.y)), Color(1.0, 0.82, 0.25))
	var px_: float = track.position.x + BAR_W * (_zone_center - _zone_width * 0.18)
	_bar.draw_rect(Rect2(Vector2(px_, track.position.y), Vector2(BAR_W * _zone_width * 0.36, track.size.y)), Color(1.0, 0.6, 0.18))
	var cx: float = track.position.x + BAR_W * _cursor_pos
	var cur := Color(0.92, 0.16, 0.1) if _stun <= 0.0 else Color(0.5, 0.5, 0.5)
	_bar.draw_rect(Rect2(Vector2(cx - 4, 0), Vector2(8, size.y)), frame_c)
	_bar.draw_rect(Rect2(Vector2(cx - 2, 2), Vector2(4, size.y - 4)), cur)


func _cleanup() -> void:
	if is_instance_valid(_bar):
		_bar.visible = false
