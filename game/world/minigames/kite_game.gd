extends "res://game/world/minigames/minigame.gd"

## TRANG THẢ DIỀU (trò phụ mới – bờ đê ruộng lúa lúc chiều): trời hoàng hôn, mặt trời đỏ, ruộng xanh, Tèo đứng coi.
## Con diều sáo bay theo gió: A/D lái qua trái/phải, W hoặc E giựt dây cho diều bốc lên (sức tay hồi dần).
## Diều tụt dần nếu không giựt; chạm ruộng là rớt (mất một lúc thả lại). Lượn qua "luồng gió" (vòng xoáy sáng)
## để được điểm; đụng đàn cò bay ngang là diều chao xuống. TIME_LIMIT giây. Kết quả: {rings, crashes}.

const TIME_LIMIT: float = 40.0
const HAND: Vector2 = Vector2(70, 152)
const HERO_POS: Vector2 = Vector2(64, 178)
const FRIEND_POS: Vector2 = Vector2(30, 180)
const SKY: Rect2 = Rect2(24, 12, 352, 140)
const LINE_MAX: float = 290.0
const SINK: float = 24.0
const TUG: float = 62.0
const STEER: float = 80.0
const RING_R: float = 12.0
const START: Vector2 = Vector2(170, 80)

var rng_seed: int = 1

var _rng := RandomNumberGenerator.new()
var _kite: Vector2 = START
var _vel: Vector2 = Vector2.ZERO
var _stamina: float = 1.0
var _rings: int = 0
var _crashes: int = 0
var _down: float = 0.0          # >0: diều đang rớt / chờ thả lại
var _stun: float = 0.0
var _wind: float = 0.0
var _gust: float = 0.0
var _gust_wait: float = 3.0
var _targets: Array[Dictionary] = []   # {pos, life, spin}
var _ring_wait: float = 0.5
var _birds: Array[Dictionary] = []     # {pos, speed}
var _bird_wait: float = 6.0
var _tail: Array[Vector2] = []
var _tail_t: float = 0.0
var _auto_t: float = 0.0
var _time: float = 0.0
var _hero: Sprite2D
var _friend: Sprite2D
var _kite_sprite: Sprite2D
var _sky: Node2D
var _bird_sprites: Array[Sprite2D] = []
var _streaks: Array[Vector2] = []


func _page() -> String:
	return "kite"


func _intro() -> Array:
	return ["THẢ DIỀU TRÊN BỜ ĐÊ", "Gió chiều lồng lộng, Tèo đưa con diều sáo cho bạn thả!\n\n[A]/[D] lái diều qua trái/phải. [W] hoặc [E] giựt dây cho diều bốc lên – giựt hoài thì mỏi tay.\nLượn qua các luồng gió (vòng xoáy sáng) để diều kêu vi vu. Coi chừng đàn cò bay ngang!\nMỗi %d luồng gió: +1 Technology (tối đa %d)." % [3, 4]]


func _hint_text() -> String:
	return "[A]/[D] Lái diều   ·   [W]/[E] Giựt dây   ·   [Esc] Thu dây"


func _music() -> StringName:
	return &"memory"


func _ambience() -> Dictionary:
	return {&"leaves": 0.55, &"birds": 0.35, &"crickets": 0.15}


func _build() -> void:
	_rng.seed = rng_seed
	backdrop("bg")
	_sky = Node2D.new()
	_sky.z_index = 2
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	_friend = sprite(tex("friend"), FRIEND_POS, 3)
	_hero = hero_sprite(HERO_POS, 8, 4)
	_kite_sprite = Sprite2D.new()
	_kite_sprite.texture = frame("kite", 2, 0)
	_kite_sprite.z_index = 6
	add_child(_kite_sprite)
	for i in range(3):
		var b := Sprite2D.new()
		b.texture = frame("bird", 2, 0)
		b.z_index = 5
		b.visible = false
		add_child(b)
		_bird_sprites.append(b)
	for i in range(10):
		_streaks.append(Vector2(_rng.randf_range(0, 384), _rng.randf_range(16, 140)))
	for i in range(14):
		_tail.append(START)


func _wants(action: StringName) -> bool:
	return action in [&"confirm", &"cancel", &"up", &"left", &"right"]


func _start() -> void:
	time_left = TIME_LIMIT
	_update_status()


func _on_action(action: StringName) -> void:
	if action == &"confirm" or action == &"up":
		_tug()


func _tug() -> void:
	if _down > 0.0:
		return
	var power: float = clampf(_stamina, 0.25, 1.0)
	_vel.y -= TUG * power
	_vel.x -= (_kite.x - HAND.x) * 0.06 * power
	_stamina = maxf(0.0, _stamina - 0.22)
	sfx(&"ui_move", -16.0, 0.6)


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "rings": _rings, "crashes": _crashes}


func _result_info(r: Dictionary) -> Array:
	var n: int = int(r.get("rings", 0))
	var tech: int = clampi(n / 3, 0, 4)
	var text: String = "Đón được %d luồng gió · diều rớt %d lần." % [n, int(r.get("crashes", 0))]
	if tech > 0:
		text += "\nHiểu thêm về gió: +%d Technology." % tech
	return ["DIỀU KÊU VI VU!" if n >= 6 else "THU DÂY!", text, n > 0]


func _update_status() -> void:
	set_status("Luồng gió: %d   ·   Sức tay: %d%%" % [_rings, int(_stamina * 100.0)])


func _tick(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		if _rings >= 6:
			sound(&"win")
		finish({"rings": _rings, "crashes": _crashes})
		return
	_stamina = minf(1.0, _stamina + 0.32 * delta)
	_stun = maxf(_stun - delta, 0.0)
	# gió: nền + cơn gió giật
	_gust_wait -= delta
	if _gust_wait <= 0.0:
		_gust_wait = _rng.randf_range(3.0, 6.0)
		_gust = _rng.randf_range(-40, 40)
	_gust = move_toward(_gust, 0.0, 10.0 * delta)
	_wind = 10.0 + 10.0 * sin(_time * 0.45) + _gust
	if _down > 0.0:
		_down -= delta
		if _down <= 0.0:
			_kite = START
			_vel = Vector2.ZERO
			for i in range(_tail.size()):
				_tail[i] = START
		_update_status()
		return
	var steer: float = 0.0
	if _stun <= 0.0:
		steer = (1.0 if held(&"right") else 0.0) - (1.0 if held(&"left") else 0.0)
		if autopilot:
			steer = _auto_steer()
	_vel.x = lerpf(_vel.x, steer * STEER + _wind * 0.6, minf(1.0, delta * 2.2))
	_vel.y = lerpf(_vel.y, SINK, minf(1.0, delta * 1.4))
	_kite += _vel * delta
	# dây giới hạn
	var off: Vector2 = _kite - HAND
	if off.length() > LINE_MAX:
		_kite = HAND + off.normalized() * LINE_MAX
		_vel *= 0.5
	_kite.x = clampf(_kite.x, SKY.position.x, SKY.end.x)
	if _kite.y < SKY.position.y:
		_kite.y = SKY.position.y
		_vel.y = maxf(_vel.y, 0.0)
	if _kite.y > SKY.end.y:
		_crash()
	_update_targets(delta)
	_update_birds(delta)
	if autopilot:
		_auto_t += delta
		var goal: Vector2 = _auto_goal()
		if _auto_t >= 0.25 and (_kite.y > goal.y + 4.0 or _kite.y > 110.0) and _stamina > 0.3:
			_auto_t = 0.0
			press(&"confirm")
	_update_status()


func _crash() -> void:
	_crashes += 1
	_down = 1.2
	toast("Diều rớt rồi!", Color(1.0, 0.6, 0.5))
	sound(&"miss", _kite)
	fxl.call("burst", _kite, Color(0.5, 0.75, 0.35), 10, 30.0, 80.0, 0.5, 20.0)
	shake(0.15)


func _auto_goal() -> Vector2:
	var best: Vector2 = Vector2(200, 70)
	var d: float = INF
	for t in _targets:
		var p: Vector2 = t["pos"]
		if p.distance_to(_kite) < d:
			d = p.distance_to(_kite)
			best = p
	return best


func _auto_steer() -> float:
	var goal: Vector2 = _auto_goal()
	var want: float = (goal.x - _kite.x - _wind * 0.6) / 30.0
	return clampf(want, -1.0, 1.0)


func _update_targets(delta: float) -> void:
	_ring_wait -= delta
	if _ring_wait <= 0.0 and _targets.size() < 2:
		_ring_wait = _rng.randf_range(0.8, 2.0)
		_targets.append({"pos": Vector2(_rng.randf_range(110, 360), _rng.randf_range(24, 108)), "life": 7.0, "spin": 0.0})
	for t in _targets.duplicate():
		t["life"] = float(t["life"]) - delta
		t["spin"] = float(t["spin"]) + delta * 4.0
		t["pos"] = (t["pos"] as Vector2) + Vector2(_wind * 0.15 * delta, sin(_time + float(t["life"])) * 4.0 * delta)
		if (t["pos"] as Vector2).distance_to(_kite) <= RING_R + 4.0:
			_rings += 1
			_targets.erase(t)
			fxl.call("burst", t["pos"], Color(1.0, 0.97, 0.75), 14, 36.0, 0.0, 0.6)
			sfx(&"coin", -6.0, 1.2)
			toast(["Vi vu!", "Lên nữa!", "Đẹp quá!"][_rings % 3], Color(0.85, 1.0, 1.0))
		elif float(t["life"]) <= 0.0:
			_targets.erase(t)


func _update_birds(delta: float) -> void:
	_bird_wait -= delta
	if _bird_wait <= 0.0 and _birds.is_empty():
		_bird_wait = _rng.randf_range(5.0, 9.0)
		var y: float = _rng.randf_range(30, 110)
		for i in range(3):
			_birds.append({"pos": Vector2(400.0 + float(i) * 14.0, y + float(i % 2) * 7.0), "speed": 62.0})
	for b in _birds.duplicate():
		b["pos"] = (b["pos"] as Vector2) + Vector2(-float(b["speed"]) * delta, sin(_time * 3.0) * 6.0 * delta)
		if _stun <= 0.0 and (b["pos"] as Vector2).distance_to(_kite) < 11.0:
			_stun = 0.9
			_vel.y += 70.0
			toast("Đụng đàn cò!", Color(1.0, 0.75, 0.5))
			sound(&"miss", _kite)
		if (b["pos"] as Vector2).x < -30.0:
			_birds.erase(b)


func _animate(delta: float) -> void:
	_time += delta
	if phase == Phase.INTRO:
		_kite = START + Vector2(sin(_time * 0.9) * 10.0, sin(_time * 1.3) * 5.0)
	_kite_sprite.visible = _down <= 0.0 or int(_time * 10.0) % 2 == 0
	var k: Vector2 = _kite
	if _down > 0.0:
		k = _kite + Vector2(0, (1.2 - _down) * 20.0)
	_kite_sprite.position = k.round()
	_kite_sprite.rotation = clampf(_vel.x * 0.006, -0.4, 0.4) + (sin(_time * 18.0) * 0.4 if _stun > 0.0 else 0.0)
	_kite_sprite.texture = frame("kite", 2, int(_time * 4.0) % 2)
	_tail_t += delta
	if _tail_t >= 0.03:
		_tail_t = 0.0
		_tail.push_front(k + Vector2(0, 12))
		_tail.resize(14)
	for i in range(_bird_sprites.size()):
		var s: Sprite2D = _bird_sprites[i]
		s.visible = i < _birds.size()
		if s.visible:
			s.position = (_birds[i]["pos"] as Vector2).round()
			s.texture = frame("bird", 2, int(_time * 6.0 + float(i)) % 2)
	for i in range(_streaks.size()):
		_streaks[i].x += (20.0 + _wind) * delta * (0.6 + 0.08 * float(i % 4))
		if _streaks[i].x > 400.0:
			_streaks[i] = Vector2(-20.0, _rng.randf_range(16, 140))
		elif _streaks[i].x < -30.0:
			_streaks[i].x = 400.0
	_hero.texture = hero_texture(8 if int(_time * 3.0) % 3 else 9)
	_sky.queue_redraw()


func _draw_sky() -> void:
	# vệt gió
	for i in range(_streaks.size()):
		var p: Vector2 = _streaks[i].round()
		_sky.draw_line(p, p + Vector2(10 + i % 3 * 4, 0), Color(1.0, 1.0, 1.0, 0.35), 1.0)
	# luồng gió (vòng xoáy sáng)
	for t in _targets:
		var p: Vector2 = t["pos"]
		var fade: float = clampf(float(t["life"]), 0.0, 1.0)
		var spin: float = float(t["spin"])
		_sky.draw_arc(p, RING_R, spin, spin + PI * 1.4, 16, Color(1.0, 1.0, 0.92, 0.85 * fade), 2.0)
		_sky.draw_arc(p, RING_R - 4.0, -spin * 1.3, -spin * 1.3 + PI, 12, Color(0.75, 0.95, 1.0, 0.7 * fade), 1.0)
		var sp: Vector2 = p + Vector2(cos(spin * 2.0), sin(spin * 2.0)) * (RING_R + 3.0)
		_sky.draw_rect(Rect2(sp.round(), Vector2(1, 1)), Color(1, 1, 1, fade))
	# dây diều (võng xuống)
	var k: Vector2 = _kite_sprite.position + Vector2(0, 4)
	var sag: float = 18.0 + absf(_vel.x) * 0.05
	var pts := PackedVector2Array()
	for i in range(17):
		var t: float = float(i) / 16.0
		pts.append(HAND.lerp(k, t) + Vector2(0, sin(t * PI) * sag))
	_sky.draw_polyline(pts, Color(0.96, 0.94, 0.88, 0.8), 1.0)
	# đuôi diều: dải đỏ vàng phấp phới
	if _kite_sprite.visible:
		var tail := PackedVector2Array()
		for i in range(_tail.size()):
			tail.append(_tail[i] + Vector2(sin(_time * 9.0 + float(i) * 0.8) * float(i) * 0.4, float(i) * 1.5))
		_sky.draw_polyline(tail, Color(0.95, 0.25, 0.15), 2.0)
		for i in range(2, tail.size(), 3):
			_sky.draw_rect(Rect2(tail[i] - Vector2(2, 1), Vector2(4, 2)), Color(1.0, 0.85, 0.25))
	# sức tay (thanh nhỏ trên đầu người chơi)
	if running:
		var r := Rect2(HERO_POS + Vector2(-10, -50), Vector2(20, 3))
		_sky.draw_rect(r.grow(1), Color(0.16, 0.08, 0.04))
		_sky.draw_rect(Rect2(r.position, Vector2(r.size.x * _stamina, r.size.y)), Color(0.45, 0.85, 0.35).lerp(Color(0.95, 0.35, 0.2), 1.0 - _stamina))
