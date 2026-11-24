extends "res://game/world/minigames/minigame.gd"

## TRANG CÂU CÁ LÓC (trò phụ mới – bờ kênh gần chỗ ông câu cá): nhìn ngang qua con kênh – bờ bên kia dừa, nhà sàn;
## lá sen, lục bình trên mặt nước; người chơi đứng trên bờ cỏ cầm cần tre, xô cá bên chân.
## Mỗi lần thả câu: bóng cá lóc lượn tới, rỉa mồi (phao nhấp nhẹ) vài lần rồi đớp thiệt (phao chìm hẳn) –
## nhấn E đúng lúc phao chìm để giựt. Giựt sớm cá chạy; chậm quá cá ăn mồi rồi đi.
## Dính câu: giữ căng dây – E để kéo (tăng lực căng), cá lóc vùng (lực căng nhảy vọt). Giữ vạch trong ô xanh thì cá
## vô dần; căng quá đứt cước, chùng quá cá sẩy. CASTS lần thả. Kết quả: {fish, casts, lost}.

const CASTS: int = 3
const BOB: Vector2 = Vector2(176, 162)
const HAND: Vector2 = Vector2(66, 128)
const ROD_TIP: Vector2 = Vector2(136, 92)
const HERO_POS: Vector2 = Vector2(56, 156)
const BUCKET: Vector2 = Vector2(16, 172)
const BITE_WINDOW: float = 0.75
const TENSION_DECAY: float = 0.42
const TENSION_PULL: float = 0.17
const ZONE: Vector2 = Vector2(0.35, 0.8)
const REEL_RATE: float = 0.24
const SLACK_LIMIT: float = 1.6

var rng_seed: int = 1

var _rng := RandomNumberGenerator.new()
var _state: StringName = &"cast"   # cast | wait | nibble | bite | reel | land | gap
var _state_t: float = 0.0
var _casts: int = 0
var _fish: int = 0
var _lost: int = 0
var _nibbles: int = 0
var _wait_for: float = 0.0
var _tension: float = 0.5
var _progress: float = 0.0
var _slack: float = 0.0
var _surge: float = 0.0
var _surge_wait: float = 1.0
var _fish_pos: Vector2 = BOB
var _shadow_x: float = 0.0
var _shadow_dir: float = 1.0
var _cast_t: float = 0.0
var _auto_t: float = 0.0
var _time: float = 0.0
var _hero: Sprite2D
var _bobber: Sprite2D
var _shadow: Sprite2D
var _caught: Sprite2D
var _land_t: float = 0.0
var _neighbor: Sprite2D
var _line: Node2D
var _meter: Node2D


func _page() -> String:
	return "fishing"


func _intro() -> Array:
	return ["CÂU CÁ LÓC", "Ngồi câu cá lóc với ông câu cá ở bờ kênh!\n\nCanh cái phao đỏ: cá rỉa mồi thì phao nhấp nhẹ – ĐỪNG giựt. Phao chìm hẳn thì nhấn [E] giựt liền!\nDính câu rồi thì nhấn [E] liên tục để kéo, giữ vạch lực căng trong ô xanh: căng quá đứt cước, chùng quá cá sẩy.\n%d lần thả câu." % CASTS]


func _hint_text() -> String:
	return "[E] Giựt / Kéo cần   ·   [Esc] Nghỉ"


func _ambience() -> Dictionary:
	return {&"river": 0.5, &"birds": 0.45, &"leaves": 0.3}


func _build() -> void:
	_rng.seed = rng_seed
	backdrop("bg")
	_neighbor = sprite(tex("neighbor"), Vector2(30, 150), 3)
	_shadow = Sprite2D.new()
	_shadow.texture = tex("shadow")
	_shadow.z_index = -4
	_shadow.modulate.a = 0.0
	add_child(_shadow)
	_line = Node2D.new()
	_line.z_index = 3
	_line.draw.connect(_draw_line)
	add_child(_line)
	_bobber = sprite(frame("bobber", 2, 0), BOB, 2)
	_bobber.visible = false
	_hero = hero_sprite(HERO_POS, 16, 4)
	_caught = Sprite2D.new()
	_caught.texture = tex("snakehead")
	_caught.z_index = 6
	_caught.visible = false
	add_child(_caught)
	_meter = Node2D.new()
	_meter.z_index = 8
	_meter.draw.connect(_draw_meter)
	add_child(_meter)


func _start() -> void:
	use_timer(false)
	_new_cast()


func _new_cast() -> void:
	_casts += 1
	_state = &"cast"
	_state_t = 0.0
	_cast_t = 0.0
	_nibbles = _rng.randi_range(1, 3)
	_bobber.visible = false
	sound(&"throw", BOB)
	_update_status()


func _on_action(action: StringName) -> void:
	if action != &"confirm":
		return
	match _state:
		&"wait", &"nibble":
			toast("Giựt sớm quá, cá chạy mất!", Color(1.0, 0.6, 0.5))
			sound(&"miss", BOB)
			_lost += 1
			_shadow_dir = -_shadow_dir
			_end_cast()
		&"bite":
			_state = &"reel"
			_state_t = 0.0
			_tension = 0.55
			_progress = 0.0
			_slack = 0.0
			_surge_wait = _rng.randf_range(0.6, 1.2)
			_fish_pos = BOB
			_bobber.visible = false
			toast("Dính rồi! Kéo!", Color(0.7, 1.0, 0.6))
			sound(&"splash", BOB)
			fxl.call("splash", BOB, 14)
			shake(0.2)
		&"reel":
			_tension = minf(1.2, _tension + TENSION_PULL)
			_progress = minf(1.0, _progress + (0.03 if _tension >= ZONE.x and _tension <= ZONE.y else 0.0))


func _end_cast() -> void:
	_state = &"gap"
	_state_t = 0.0
	_bobber.visible = false


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "fish": _fish, "casts": _casts, "lost": _lost}


func _result_info(r: Dictionary) -> Array:
	var n: int = int(r.get("fish", 0))
	if n == 0:
		return ["HỔNG DÍNH CON NÀO", "Phao chìm hẳn mới giựt nghen. Sẩy %d con." % int(r.get("lost", 0)), false]
	return ["ĐƯỢC %d CON CÁ LÓC!" % n, "Cá lóc đồng mập ú, ông câu cá mua hết.\nSẩy %d con." % int(r.get("lost", 0)), true]


func _update_status() -> void:
	set_status("Lần thả: %d/%d   ·   Cá lóc: %d con" % [_casts, CASTS, _fish])


func _tick(delta: float) -> void:
	_state_t += delta
	match _state:
		&"cast":
			_cast_t += delta
			if _cast_t >= 0.7:
				_bobber.visible = true
				fxl.call("ripple", BOB, 8.0, 0.8)
				sound(&"splash", BOB)
				_state = &"wait"
				_state_t = 0.0
				_wait_for = _rng.randf_range(1.2, 2.6)
				_shadow_dir = 1.0 if _rng.randf() < 0.5 else -1.0
				_shadow_x = BOB.x - _shadow_dir * 90.0
		&"wait":
			_shadow_x = move_toward(_shadow_x, BOB.x - _shadow_dir * 10.0, 40.0 * delta)
			if _state_t >= _wait_for:
				_state = &"nibble"
				_state_t = 0.0
		&"nibble":
			if _state_t >= 0.55:
				_nibbles -= 1
				fxl.call("ripple", BOB, 5.0, 0.5)
				_state_t = 0.0
				if _nibbles <= 0:
					_state = &"bite"
					fxl.call("ripple", BOB, 12.0, 0.9)
					fxl.call("splash", BOB, 6)
					sfx(&"fish_jump", -8.0)
		&"bite":
			if _state_t >= BITE_WINDOW:
				toast("Cá ăn mồi rồi chạy mất!", Color(1.0, 0.7, 0.5))
				_lost += 1
				_end_cast()
		&"reel":
			_reel(delta)
		&"land":
			_land_t += delta
			var t: float = minf(_land_t / 0.7, 1.0)
			_caught.position = _fish_pos.lerp(BUCKET + Vector2(0, -6), t) + Vector2(0, -sin(t * PI) * 40.0)
			_caught.rotation = t * 8.0
			if t >= 1.0:
				_caught.visible = false
				fxl.call("splash", BUCKET + Vector2(0, -8), 8)
				sound(&"catch", BUCKET)
				_end_cast()
		&"gap":
			if _state_t >= 0.9:
				if _casts >= CASTS:
					if _fish > 0:
						sound(&"win")
					finish({"fish": _fish, "casts": _casts, "lost": _lost}, 0.3)
					return
				_new_cast()
	if autopilot:
		_auto(delta)
	_update_status()


func _reel(delta: float) -> void:
	_tension -= TENSION_DECAY * delta
	_surge_wait -= delta
	if _surge_wait <= 0.0:
		_surge = 0.22
		_surge_wait = _rng.randf_range(0.7, 1.5)
		fxl.call("splash", _fish_pos, 8)
		sound(&"splash", _fish_pos)
	if _surge > 0.0:
		_surge -= delta
		_tension += 1.3 * delta
	var in_zone: bool = _tension >= ZONE.x and _tension <= ZONE.y
	if in_zone:
		_progress = minf(1.0, _progress + REEL_RATE * delta)
	_slack = _slack + delta if _tension < 0.12 else 0.0
	var far := BOB
	var near := Vector2(92, 176)
	_fish_pos = far.lerp(near, _progress) + Vector2(sin(_time * 7.0) * 6.0, cos(_time * 5.0) * 2.0)
	if fmod(_time, 0.3) < delta:
		fxl.call("ripple", _fish_pos, 7.0, 0.6)
	if _tension >= 1.0:
		toast("Đứt cước rồi!", Color(1.0, 0.55, 0.45))
		sound(&"miss", _fish_pos)
		_lost += 1
		shake(0.2)
		_end_cast()
	elif _slack >= SLACK_LIMIT:
		toast("Dây chùng, cá sẩy mất!", Color(1.0, 0.7, 0.5))
		sound(&"miss", _fish_pos)
		_lost += 1
		_end_cast()
	elif _progress >= 1.0:
		_fish += 1
		_state = &"land"
		_land_t = 0.0
		_caught.visible = true
		_caught.position = _fish_pos
		fxl.call("splash", _fish_pos, 16)
		sfx(&"fish_jump")
		toast("Cá lóc bự quá trời!", Color(0.75, 1.0, 0.6))


func _auto(delta: float) -> void:
	_auto_t += delta
	match _state:
		&"bite":
			if _state_t >= 0.1:
				press(&"confirm")
		&"reel":
			if _auto_t >= 0.12 and _tension < 0.5:
				_auto_t = 0.0
				press(&"confirm")


func _animate(delta: float) -> void:
	_time += delta
	_neighbor.position.y = 150.0 - (1.0 if int(_time * 0.8) % 2 == 0 else 0.0)
	# phao
	var bob_y: float = BOB.y + roundf(sin(_time * 2.5) * 0.6)
	var dip: bool = false
	if _state == &"nibble" and _state_t < 0.18:
		bob_y += 1.0
	if _state == &"bite":
		dip = true
		bob_y += 1.0 + roundf(sin(_time * 30.0))
	_bobber.position = Vector2(BOB.x, bob_y)
	_bobber.texture = frame("bobber", 2, 1 if dip else 0)
	# bóng cá
	var show_shadow: bool = _state in [&"wait", &"nibble", &"bite"]
	_shadow.modulate.a = move_toward(_shadow.modulate.a, 0.85 if show_shadow else 0.0, delta * 2.0)
	if _state == &"gap" or _state == &"cast":
		_shadow_x += _shadow_dir * 50.0 * delta
	_shadow.position = Vector2(roundf(_shadow_x), BOB.y + 8.0)
	_shadow.flip_h = _shadow_dir < 0.0
	# người: nghiêng cần khi kéo
	var pulling: bool = _state == &"reel"
	_hero.texture = hero_texture(17 if pulling and int(_time * 10.0) % 2 == 0 else 16)
	_line.queue_redraw()
	_meter.queue_redraw()


func _tip() -> Vector2:
	var bend: float = 0.0
	if _state == &"reel":
		bend = clampf(_tension, 0.0, 1.2) * 14.0
	elif _state == &"cast":
		bend = -sin(minf(_cast_t / 0.7, 1.0) * PI) * 16.0
	return ROD_TIP + Vector2(-bend * 0.3, bend)


func _draw_line() -> void:
	var tip: Vector2 = _tip()
	var hand: Vector2 = HAND
	# cần tre
	_line.draw_line(hand, tip, Color(0.16, 0.1, 0.07), 3.0)
	_line.draw_line(hand, tip, Color(0.82, 0.7, 0.38), 1.0)
	for i in range(1, 6):
		var p: Vector2 = hand.lerp(tip, float(i) / 6.0)
		_line.draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(0.55, 0.42, 0.2))
	# dây câu
	var end: Vector2 = BOB + Vector2(0, -6)
	if _state == &"reel":
		end = _fish_pos
	elif _state == &"cast":
		var t: float = minf(_cast_t / 0.7, 1.0)
		end = tip.lerp(BOB, t) + Vector2(0, -sin(t * PI) * 40.0)
	elif _state == &"land":
		end = _caught.position
	elif _state == &"gap":
		end = tip + Vector2(4, 30)
	var sag: float = 10.0 if _state != &"reel" else maxf(0.0, (0.6 - _tension) * 30.0)
	var pts := PackedVector2Array()
	for i in range(13):
		var t: float = float(i) / 12.0
		pts.append(tip.lerp(end, t) + Vector2(0, sin(t * PI) * sag))
	_line.draw_polyline(pts, Color(0.95, 0.95, 0.9, 0.85), 1.0)


func _draw_meter() -> void:
	if _state != &"reel":
		return
	var r := Rect2(Vector2(96, 92), Vector2(8, 56))
	_meter.draw_rect(r.grow(2), Color(0.16, 0.08, 0.04))
	_meter.draw_rect(r.grow(1), Color(0.72, 0.45, 0.2))
	_meter.draw_rect(r, Color(0.32, 0.2, 0.14))
	var z0: float = r.end.y - r.size.y * ZONE.y
	var z1: float = r.end.y - r.size.y * ZONE.x
	_meter.draw_rect(Rect2(Vector2(r.position.x, z0), Vector2(r.size.x, z1 - z0)), Color(0.42, 0.82, 0.35))
	_meter.draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), Color(0.85, 0.25, 0.18))
	var y: float = roundf(r.end.y - r.size.y * clampf(_tension, 0.0, 1.0))
	_meter.draw_rect(Rect2(Vector2(r.position.x - 2, y - 1), Vector2(12, 3)), Color(0.12, 0.06, 0.03))
	_meter.draw_rect(Rect2(Vector2(r.position.x - 1, y), Vector2(10, 1)), Color(1.0, 0.95, 0.6))
	# tiến độ kéo cá vô bờ
	var p := Rect2(Vector2(110, 144), Vector2(40, 5))
	_meter.draw_rect(p.grow(1), Color(0.16, 0.08, 0.04))
	_meter.draw_rect(p, Color(0.3, 0.22, 0.16))
	_meter.draw_rect(Rect2(p.position, Vector2(p.size.x * _progress, p.size.y)), Color(1.0, 0.8, 0.3))
