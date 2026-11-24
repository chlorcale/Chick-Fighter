extends "res://game/world/minigames/minigame.gd"

## TRANG CÔNG TRƯỜNG (phụ hồ – tung gạch): nhà đang xây, giàn giáo tre, máy trộn hồ, xe rùa, đống cát.
## Người chơi đứng dưới sân cạnh đống gạch; thợ hồ trên giàn giáo đi qua lại giữa 3 ô tường, đứng giơ tay
## ("Đây nè!") ở ô nào thì tung gạch lên ô đó.
## - A/D: chạy qua ô tường bên trái/phải (3 làn).
## - Thanh lực bên cạnh chạy lên xuống: nhấn E khi vạch nằm trong ô xanh để tung cữ gạch vừa tầm tay thợ.
##   Đúng làn + thợ đang chờ + đủ lực = thợ chụp được, xây thêm một hàng gạch; sai thì gạch rớt bể.
## Đủ `target` cữ trong TIME_LIMIT giây = đủ ca. Kết quả: {bricks, full, broken}.

const TIME_LIMIT: float = 40.0
const PLANK_Y: float = 96.0
const BAYS: Array[float] = [95.0, 195.0, 295.0]
const HERO_Y: float = 204.0
const HAND_Y: float = 170.0
const CATCH_Y: float = 58.0
const PILE_POS: Vector2 = Vector2(34, 206)
const HERO_SPEED: float = 150.0
const WORKER_SPEED: float = 70.0
const FLIGHT: float = 0.55
const POWER_SPEED: float = 1.35
const THROW_COOL: float = 0.45

var target: int = 8

var _hero: Sprite2D
var _worker: Sprite2D
var _mixer: Sprite2D
var _meter: Node2D
var _wall: Node2D
var _bubble: Node2D
var _lane: int = 1
var _hero_x: float = BAYS[1]
var _worker_bay: int = 1
var _worker_x: float = BAYS[1]
var _worker_state: StringName = &"ready" # ready | lay | walk
var _worker_t: float = 0.0
var _power: float = 0.0
var _power_dir: float = 1.0
var _zone_center: float = 0.7
var _zone_width: float = 0.22
var _cool: float = 0.0
var _courses: Array[int] = [0, 0, 0]
var _bricks: Array[Dictionary] = []   # {sprite, from, to, t, ok, peak, bay}
var _debris: Array[Dictionary] = []   # {sprite, life}
var _delivered: int = 0
var _broken: int = 0
var _time: float = 0.0
var _walk_t: float = 0.0


func _page() -> String:
	return "site"


func _intro() -> Array:
	return ["PHỤ HỒ – TUNG GẠCH", "Thợ hồ trên giàn giáo chờ gạch! Chú đứng giơ tay ở ô tường nào thì tung lên ô đó.\n\n[A]/[D] chạy qua lại 3 ô tường.\nThanh lực kế bên chạy lên xuống: nhấn [E] khi vạch nằm trong ô xanh – tung vừa tầm tay chú.\nYếu quá hay mạnh quá, sai chỗ là gạch rớt bể!\n\nĐủ %d cữ trong %d giây là đủ ca." % [target, int(TIME_LIMIT)]]


func _hint_text() -> String:
	return "[A]/[D] Chạy qua ô   ·   [E] Tung gạch   ·   [Esc] Nghỉ"


func _ambience() -> Dictionary:
	return {&"village": 0.5, &"birds": 0.25}


func _build() -> void:
	backdrop("bg")
	_wall = Node2D.new()
	_wall.z_index = -5
	_wall.draw.connect(_draw_wall)
	add_child(_wall)
	_mixer = sprite(frame("mixer", 2, 0), Vector2(350, 196), -3)
	sprite(tex("wheelbarrow"), Vector2(270, 200), -3)
	sprite(tex("pile"), PILE_POS, 1)
	_worker = sprite(frame("worker", 2, 1), Vector2(BAYS[1], PLANK_Y), -2)
	_hero = hero_sprite(Vector2(BAYS[1], HERO_Y), 8, 2)
	_meter = Node2D.new()
	_meter.z_index = 10
	_meter.draw.connect(_draw_meter)
	add_child(_meter)
	_bubble = Node2D.new()
	_bubble.z_index = 10
	_bubble.draw.connect(_draw_bubble)
	add_child(_bubble)


func _wants(action: StringName) -> bool:
	return action in [&"confirm", &"cancel", &"left", &"right"]


func _start() -> void:
	time_left = TIME_LIMIT
	_update_status()


func _on_action(action: StringName) -> void:
	match action:
		&"left":
			_lane = maxi(_lane - 1, 0)
		&"right":
			_lane = mini(_lane + 1, BAYS.size() - 1)
		&"confirm":
			_throw()


func _throw() -> void:
	if _cool > 0.0 or absf(_hero_x - BAYS[_lane]) > 1.0:
		return
	_cool = THROW_COOL
	var in_zone: bool = absf(_power - _zone_center) <= _zone_width * 0.5
	var ok: bool = in_zone and _worker_state == &"ready" and _worker_bay == _lane
	var from := Vector2(_hero_x, HAND_Y)
	var peak: float = lerpf(HAND_Y - 20.0, CATCH_Y - 40.0, _power)
	var to := Vector2(BAYS[_lane] + 4.0, CATCH_Y)
	if not ok:
		to = Vector2(BAYS[_lane] + randf_range(-26, 26), HERO_Y + 2.0)
	var s := Sprite2D.new()
	s.texture = tex("brick")
	s.z_index = 6
	s.position = from
	add_child(s)
	_bricks.append({"sprite": s, "from": from, "to": to, "t": 0.0, "ok": ok, "peak": peak, "bay": _lane, "power": _power})
	sound(&"pick", from)
	if ok:
		_worker_state = &"catching"
		_worker_t = FLIGHT


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "bricks": _delivered, "full": false, "broken": _broken}


func _result_info(r: Dictionary) -> Array:
	var n: int = int(r.get("bricks", 0))
	if bool(r.get("full", false)):
		return ["ĐỦ CA!", "Tung %d cữ gạch ngọt xớt · bể %d viên.\nChú thợ hồ khen lấy khen để." % [n, int(r.get("broken", 0))], true]
	return ["HẾT GIỜ!", "Được %d/%d cữ · bể %d viên." % [n, target, int(r.get("broken", 0))], n > 0]


func _update_status() -> void:
	set_status("Gạch: %d/%d cữ   ·   Bể: %d" % [_delivered, target, _broken])


func _tick(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		finish({"bricks": _delivered, "full": _delivered >= target, "broken": _broken})
		return
	_cool = maxf(_cool - delta, 0.0)
	_power += _power_dir * POWER_SPEED * delta
	if _power >= 1.0:
		_power = 1.0
		_power_dir = -1.0
	elif _power <= 0.0:
		_power = 0.0
		_power_dir = 1.0
	_update_worker(delta)
	if autopilot:
		_auto()
	_update_status()


func _auto() -> void:
	var goal: int = _worker_bay
	if _lane != goal:
		press(&"left" if goal < _lane else &"right")
		return
	if _worker_state == &"ready" and _cool <= 0.0 and absf(_hero_x - BAYS[_lane]) <= 1.0 \
			and absf(_power - _zone_center) <= 0.04:
		press(&"confirm")


func _update_worker(delta: float) -> void:
	match _worker_state:
		&"catching":
			_worker_t -= delta
		&"lay":
			_worker_t -= delta
			if _worker_t <= 0.0:
				var options: Array[int] = []
				for b in range(BAYS.size()):
					if b != _worker_bay:
						options.append(b)
				_worker_bay = options[randi() % options.size()]
				_worker_state = &"walk"
		&"walk":
			_worker_x = move_toward(_worker_x, BAYS[_worker_bay], WORKER_SPEED * delta)
			if absf(_worker_x - BAYS[_worker_bay]) < 0.5:
				_worker_state = &"ready"
				_zone_center = randf_range(0.55, 0.82)
				_zone_width = maxf(0.13, 0.22 - 0.01 * float(_delivered))


func _land(b: Dictionary) -> void:
	var s: Sprite2D = b["sprite"]
	if bool(b["ok"]):
		var bay: int = int(b["bay"])
		_courses[bay] += 1
		_delivered += 1
		_wall.queue_redraw()
		fxl.call("burst", Vector2(BAYS[bay], PLANK_Y - 10.0 - 5.0 * float(_courses[bay])), Color(0.85, 0.78, 0.66), 8, 22.0, 40.0, 0.5, 10.0)
		sound(&"drop", s.position)
		s.queue_free()
		_worker_state = &"lay"
		_worker_t = 0.55
		if _delivered >= target:
			toast("Đủ ca rồi!", Color(0.7, 1.0, 0.6))
			sound(&"win", s.position)
			finish({"bricks": _delivered, "full": true, "broken": _broken}, 0.9)
		else:
			toast(["Chụp gọn!", "Ngọt!", "Đẹp!"][_delivered % 3] + " %d/%d" % [_delivered, target], Color(0.75, 1.0, 0.6))
		return
	_broken += 1
	s.texture = tex("broken")
	s.position = Vector2(s.position.x, HERO_Y + 2.0)
	_debris.append({"sprite": s, "life": 1.6})
	fxl.call("burst", s.position + Vector2(0, -2), Color(0.75, 0.35, 0.24), 12, 40.0, 140.0, 0.5, 30.0)
	fxl.call("burst", s.position, Color(0.8, 0.7, 0.55), 8, 20.0, 30.0, 0.7, 6.0)
	shake(0.15)
	toast("Bể gạch!", Color(1.0, 0.6, 0.5))
	sound(&"miss", s.position)
	if _worker_state == &"catching":
		_worker_state = &"ready"


func _animate(delta: float) -> void:
	_time += delta
	_mixer.texture = frame("mixer", 2, int(_time * 6.0) % 2)
	# người chơi chạy theo làn
	var goal: float = BAYS[_lane]
	var moving: bool = absf(_hero_x - goal) > 0.5
	_hero_x = move_toward(_hero_x, goal, HERO_SPEED * delta)
	_walk_t += delta
	_hero.position = Vector2(roundf(_hero_x), HERO_Y)
	if moving:
		_hero.texture = hero_texture(hero_walk(&"left" if goal < _hero_x else &"right", _walk_t))
	else:
		_hero.texture = hero_texture(8 + (1 if _cool > THROW_COOL * 0.5 else 0))
		_hero.position.y = HERO_Y - (2.0 if _cool > THROW_COOL * 0.5 else 0.0)
	# thợ hồ
	_worker.position = Vector2(roundf(_worker_x), PLANK_Y)
	var arms: bool = _worker_state == &"ready" or _worker_state == &"catching"
	_worker.texture = frame("worker", 2, 1 if arms else 0)
	if _worker_state == &"walk":
		_worker.position.y -= float(int(_time * 8.0) % 2)
	# gạch bay
	for b in _bricks.duplicate():
		b["t"] = float(b["t"]) + delta / FLIGHT
		var t: float = minf(float(b["t"]), 1.0)
		var from: Vector2 = b["from"]
		var to: Vector2 = b["to"]
		var p := Vector2(lerpf(from.x, to.x, t), 0)
		if bool(b["ok"]):
			p.y = _arc(from.y, float(b["peak"]), to.y, t)
		else:
			# bay lên tới đỉnh theo lực rồi rớt xuống đất
			p.y = _arc(from.y, float(b["peak"]), to.y, t)
		var s: Sprite2D = b["sprite"]
		s.position = p.round()
		s.rotation = t * 6.0 * (1.0 if from.x <= to.x else -1.0)
		if t >= 1.0:
			_bricks.erase(b)
			s.rotation = 0.0
			_land(b)
	for d in _debris.duplicate():
		d["life"] = float(d["life"]) - delta
		(d["sprite"] as Sprite2D).modulate.a = clampf(float(d["life"]) / 0.5, 0.0, 1.0)
		if float(d["life"]) <= 0.0:
			(d["sprite"] as Sprite2D).queue_free()
			_debris.erase(d)
	_meter.queue_redraw()
	_bubble.queue_redraw()


## Đường bay qua đỉnh peak (y nhỏ hơn = cao hơn) rồi tới y1.
func _arc(y0: float, peak: float, y1: float, t: float) -> float:
	var top: float = minf(peak, minf(y0, y1) - 4.0)
	if t < 0.5:
		return lerpf(y0, top, ease(t * 2.0, 0.5))
	return lerpf(top, y1, ease((t - 0.5) * 2.0, 2.0))


func _draw_wall() -> void:
	for bay in range(BAYS.size()):
		var x0: float = BAYS[bay] - 45.0
		for k in range(_courses[bay]):
			var y: float = PLANK_Y - 12.0 - 5.0 * float(k + 1)
			_wall.draw_rect(Rect2(Vector2(x0 - 1, y - 1), Vector2(92, 6)), Color(0.85, 0.76, 0.62))
			var off: float = 0.0 if k % 2 == 0 else 5.0
			var x: float = x0 - off
			var n: int = 0
			while x < x0 + 90.0:
				var a: float = maxf(x, x0)
				var b: float = minf(x + 9.0, x0 + 90.0)
				var c := Color(0.71, 0.32, 0.23) if (n + k) % 3 else Color(0.78, 0.4, 0.28)
				_wall.draw_rect(Rect2(Vector2(a, y), Vector2(b - a, 4)), c)
				_wall.draw_rect(Rect2(Vector2(a, y), Vector2(b - a, 1)), Color(0.88, 0.55, 0.42))
				x += 10.0
				n += 1


func _draw_meter() -> void:
	if not running:
		return
	var base := Vector2(roundf(_hero_x) + 16.0, HERO_Y - 6.0)
	var h: float = 44.0
	var r := Rect2(base + Vector2(0, -h), Vector2(8, h))
	_meter.draw_rect(r.grow(2), Color(0.2, 0.1, 0.05))
	_meter.draw_rect(r.grow(1), Color(0.72, 0.45, 0.2))
	_meter.draw_rect(r, Color(0.3, 0.2, 0.14))
	var z0: float = clampf(_zone_center - _zone_width * 0.5, 0.0, 1.0)
	var z1: float = clampf(_zone_center + _zone_width * 0.5, 0.0, 1.0)
	_meter.draw_rect(Rect2(Vector2(r.position.x, r.end.y - h * z1), Vector2(8, h * (z1 - z0))), Color(0.45, 0.85, 0.35))
	var y: float = roundf(r.end.y - h * _power)
	_meter.draw_rect(Rect2(Vector2(r.position.x - 2, y - 1), Vector2(12, 3)), Color(0.15, 0.08, 0.04))
	_meter.draw_rect(Rect2(Vector2(r.position.x - 1, y), Vector2(10, 1)), Color(1.0, 0.3, 0.2))
	# mũi tên làn đang đứng
	if absf(_hero_x - BAYS[_lane]) > 1.0:
		return


func _draw_bubble() -> void:
	if not running or _worker_state != &"ready":
		return
	var p := Vector2(roundf(_worker_x) + 10.0, PLANK_Y - 58.0 + roundf(sin(_time * 6.0)))
	var r := Rect2(p, Vector2(30, 12))
	_bubble.draw_rect(r.grow(1), Color(0.23, 0.15, 0.09))
	_bubble.draw_rect(r, Color(1.0, 0.98, 0.92))
	_bubble.draw_colored_polygon(PackedVector2Array([p + Vector2(3, 12), p + Vector2(9, 12), p + Vector2(1, 17)]), Color(1.0, 0.98, 0.92))
	# biểu tượng gạch + dấu chấm than
	_bubble.draw_rect(Rect2(p + Vector2(4, 4), Vector2(10, 5)), Color(0.71, 0.32, 0.23))
	_bubble.draw_rect(Rect2(p + Vector2(4, 4), Vector2(10, 1)), Color(0.9, 0.55, 0.42))
	_bubble.draw_rect(Rect2(p + Vector2(20, 2), Vector2(2, 5)), Color(0.85, 0.2, 0.15))
	_bubble.draw_rect(Rect2(p + Vector2(20, 8), Vector2(2, 2)), Color(0.85, 0.2, 0.15))


func _cleanup() -> void:
	pass
