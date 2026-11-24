extends "res://game/world/minigames/minigame.gd"

## TRANG CHÒI CÁ TRA (nhìn ngang, cắt qua mặt ao): chòi trên cọc, cầu ván, cần vó tre bắc trên trụ, cá tra lội
## dưới mặt nước, Chú Sáu đứng coi.
## - "Cho cá ăn" (MODE_FEED): A/D dời chỗ vãi, E vãi một nắm cám (3 nắm); cá tra trồi lên đớp, nước văng.
## - "Kéo vó" (MODE_NET): cá tra lội ngang qua vó chìm dưới nước; lưới sáng vàng (cá ngay trên vó) thì nhấn E kéo
##   vó lên. 3 lần kéo → 0–3 con (mỗi lần tối đa một con). Chậm tay quá (PULL_TIMEOUT) thì cá lội mất, mất lượt.
## Kết quả: {fish, pulls} hoặc {thrown, fish = 0}; bỏ ngang {cancelled}.

const Activities := preload("res://game/world/activities.gd")
const MODE_FEED: StringName = &"feed"
const MODE_NET: StringName = &"net"
const WATER_Y: float = 104.0
const DECK_Y: float = 76.0
const PIVOT: Vector2 = Vector2(198, 26)
const POLE_FAR: float = 112.0
const POLE_BUTT: float = 22.0
const ANGLE_REST: float = 0.67     # rad, vó chìm
const ANGLE_UP: float = 0.07       # rad, vó nhấc khỏi nước
const NET_REST_Y: float = 150.0
const NET_UP_Y: float = 52.0
const NET_HALF: float = 30.0
const HERO_POS: Vector2 = Vector2(222, DECK_Y)
const HAND: Vector2 = Vector2(214, 52)
const OWNER_POS: Vector2 = Vector2(304, DECK_Y)
const POND_X: Vector2 = Vector2(64, 372)
const PULLS: int = 3
const PULL_TIMEOUT: float = 9.0
const LIFT_TIME: float = 1.1
const FEED_THROWS: int = 3
const FISH_SPEEDS: Array[float] = [34.0, 44.0, 54.0]
const AIM_RANGE: Vector2 = Vector2(70, 236)

var mode: StringName = MODE_NET

var _rig: Node2D
var _surface: Sprite2D
var _hero: Sprite2D
var _owner: Sprite2D
var _fishes: Array[Dictionary] = [] # {sprite, pos, vel, alpha, leaving, crossing}
var _pellets: Array[Dictionary] = [] # {from, to, t, landed, life}
var _caught: int = 0
var _pulls: int = 0
var _throws: int = 0
var _lift_t: float = -1.0
var _lift_fish: bool = false
var _pull_time: float = 0.0
var _spawn_wait: float = 0.0
var _end_wait: float = -1.0
var _auto_wait: float = 0.0
var _aim: float = 150.0
var _time: float = 0.0
var _hero_anim: float = 0.0


func _page() -> String:
	return "fish"


func _intro() -> Array:
	if mode == MODE_FEED:
		return ["CHO CÁ TRA ĂN", "Cá tra nhà Chú Sáu đói meo rồi!\n\n[A]/[D] dời chỗ vãi cám trên mặt ao, [E] vãi một nắm (%d nắm).\nCá tra sẽ trồi lên đớp mồi – coi nước văng cho đã." % FEED_THROWS]
	return ["KÉO VÓ BẮT CÁ TRA", "Cái vó lớn đang chìm dưới ao. Cá tra lội ngang qua vó…\n\nKhi lưới vó sáng vàng (cá lội ngay trên vó) thì nhấn [E] kéo vó lên!\n%d lần kéo, mỗi lần dính một con. Chậm tay quá thì cá lội mất.\nChú Sáu mua mỗi con %s." % [PULLS, GameState.money_text(Activities.FISH_PRICE)]]


func _hint_text() -> String:
	if mode == MODE_FEED:
		return "[A]/[D] dời chỗ vãi   ·   [E] Vãi cám   ·   [Esc] Nghỉ"
	return "[E] Kéo vó   ·   [Esc] Nghỉ"


func _music() -> StringName:
	return &"village"


func _ambience() -> Dictionary:
	return {&"river": 0.55, &"birds": 0.4, &"leaves": 0.2}


func _build() -> void:
	backdrop("bg")
	_surface = Sprite2D.new()
	_surface.centered = false
	_surface.position = Vector2(0, WATER_Y - 3)
	_surface.z_index = 2
	_surface.texture = tex("surface_0")
	add_child(_surface)
	_owner = sprite(npc_texture("crowd_3"), OWNER_POS, 4)
	_owner.flip_h = true
	_hero = hero_sprite(HERO_POS, 12, 5)
	_rig = Node2D.new()
	_rig.z_index = 3
	_rig.draw.connect(_draw_rig)
	add_child(_rig)
	# vài con cá lội lững lờ (cảnh) – kéo vó thì không tính
	for i in range(4 if mode == MODE_NET else 7):
		var depth: float = randf_range(116, 192)
		_spawn_fish(Vector2(randf_range(POND_X.x, POND_X.y), depth), Vector2(randf_range(8, 18) * (1 if randf() < 0.5 else -1), 0), false)


func _wants(action: StringName) -> bool:
	return action in [&"confirm", &"cancel", &"left", &"right"]


func _start() -> void:
	if mode == MODE_FEED:
		time_left = 25.0
	else:
		time_left = 40.0
		_spawn_wait = 1.0
	_update_status()


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "fish": 0, "thrown": _throws}


func _result_info(r: Dictionary) -> Array:
	if mode == MODE_FEED:
		return ["CÁ NO CĂNG BỤNG!", "Vãi %d nắm cám – cá tra trồi lên đớp lách tách." % int(r.get("thrown", 0)), true]
	var n: int = int(r.get("fish", 0))
	if n == 0:
		return ["HỤT HẾT TRƠN!", "Ba lần kéo mà hổng dính con nào.\nCanh cá lội ngay giữa vó rồi mới kéo nghen.", false]
	return ["ĐƯỢC %d CON CÁ TRA!" % n, "Chú Sáu mua lại hết: %s." % GameState.money_text(n * Activities.FISH_PRICE), true]


func _on_action(action: StringName) -> void:
	if action != &"confirm" or _end_wait >= 0.0:
		return
	if mode == MODE_FEED:
		if _throws < FEED_THROWS:
			_throws += 1
			_throw_pellets(6, Vector2(_aim, WATER_Y), 10.0)
			_hero_anim = 0.4
			_update_status()
	elif _lift_t < 0.0:
		_pull()


func _pull() -> void:
	_pulls += 1
	_lift_t = 0.0
	_pull_time = 0.0
	_hero_anim = LIFT_TIME
	var fish: Dictionary = _fish_in_net()
	_lift_fish = not fish.is_empty()
	var net_pos := Vector2(_net_x(), WATER_Y)
	if _lift_fish:
		_caught += 1
		_remove_fish(fish)
		toast("Dính rồi! +1 cá tra", Color(0.7, 1.0, 0.6))
		sound(&"catch", net_pos)
	else:
		toast("Hụt rồi!", Color(1.0, 0.6, 0.5))
		sound(&"miss", net_pos)
		for other in _fishes:
			if bool(other["crossing"]):
				other["vel"] = (other["vel"] as Vector2) * 3.0 # cá hoảng, lội lẹ đi chỗ khác
				other["leaving"] = true
	fxl.call("ripple", net_pos, 20.0, 1.0)
	fxl.call("splash", net_pos + Vector2(0, -2), 14)
	sound(&"splash", net_pos)
	_update_status()


func _net_x() -> float:
	return PIVOT.x - cos(ANGLE_REST) * POLE_FAR


func _fish_in_net() -> Dictionary:
	for fish in _fishes:
		if bool(fish["leaving"]) or not bool(fish["crossing"]):
			continue
		var pos: Vector2 = fish["pos"]
		if absf(pos.x - _net_x()) <= NET_HALF - 8.0 and absf(pos.y - (NET_REST_Y - 2.0)) <= 12.0:
			return fish
	return {}


func _update_status() -> void:
	if mode == MODE_FEED:
		set_status("Nắm cám: %d/%d" % [_throws, FEED_THROWS])
	else:
		set_status("Lần kéo: %d/%d   ·   Bắt được: %d con" % [_pulls, PULLS, _caught])


func _tick(delta: float) -> void:
	time_left -= delta
	_update_pellets(delta)
	if mode == MODE_FEED:
		var dir: float = (1.0 if held(&"right") else 0.0) - (1.0 if held(&"left") else 0.0)
		_aim = clampf(_aim + dir * 100.0 * delta, AIM_RANGE.x, AIM_RANGE.y)
	if _lift_t >= 0.0:
		_lift_t += delta / LIFT_TIME
		if _lift_t >= 1.0:
			_lift_t = -1.0
			_lift_fish = false
			if mode == MODE_NET and _pulls >= PULLS:
				_end_wait = 0.4
	if _end_wait >= 0.0:
		_end_wait -= delta
		if _end_wait < 0.0:
			_finish_now()
			return
	elif mode == MODE_FEED:
		if _throws >= FEED_THROWS and _pellets.is_empty():
			_end_wait = 1.4
			for fish in _fishes:
				fish["leaving"] = true
		elif autopilot:
			_auto_wait -= delta
			if _auto_wait <= 0.0 and _throws < FEED_THROWS:
				_auto_wait = 0.7
				_aim = randf_range(AIM_RANGE.x + 20, AIM_RANGE.y - 20)
				press(&"confirm")
	else:
		_pull_time += delta
		if _lift_t < 0.0 and _pulls < PULLS:
			_spawn_wait -= delta
			if _crossing_count() == 0 and _spawn_wait <= 0.0:
				_spawn_crossing_fish()
			if _pull_time >= PULL_TIMEOUT:
				toast("Chậm tay quá, cá lội mất!", Color(1.0, 0.6, 0.5))
				_pulls += 1
				_pull_time = 0.0
				for fish in _fishes:
					if bool(fish["crossing"]):
						fish["leaving"] = true
				if _pulls >= PULLS:
					_end_wait = 0.5
			elif autopilot:
				var fish: Dictionary = _fish_in_net()
				if not fish.is_empty() and absf((fish["pos"] as Vector2).x - _net_x()) <= 3.0:
					press(&"confirm")
	if time_left <= 0.0 and _end_wait < 0.0 and _lift_t < 0.0:
		_finish_now()
		return
	_update_status()


func _finish_now() -> void:
	if mode == MODE_FEED:
		finish({"thrown": _throws, "fish": 0})
	else:
		if _caught > 0:
			sound(&"win")
		finish({"fish": _caught, "pulls": _pulls})


## Cảnh động ở mọi pha: cá lội, mặt nước lăn tăn, người đứng thở.
func _animate(delta: float) -> void:
	_time += delta
	_surface.texture = tex("surface_%d" % (int(_time * 2.5) % 2))
	_update_fishes(delta)
	_hero_anim = maxf(_hero_anim - delta, 0.0)
	_hero.texture = hero_texture(12 + int(_time * 8.0) % 4 if _hero_anim > 0.0 else 12)
	_owner.position.y = OWNER_POS.y - (1.0 if int(_time * 1.5) % 2 == 0 else 0.0)
	_rig.queue_redraw()


# ------------------------------------------------------------------ cám

func _throw_pellets(count: int, target: Vector2, spread: float) -> void:
	for i in range(count):
		var to := target + Vector2(randf_range(-spread, spread), 0)
		_pellets.append({"from": HAND, "to": to, "t": -float(i) * 0.05})
	sound(&"throw", target)


func _update_pellets(delta: float) -> void:
	for pellet in _pellets:
		pellet["t"] = float(pellet["t"]) + delta / 0.55
		if float(pellet["t"]) >= 1.0 and not pellet.has("landed"):
			pellet["landed"] = true
			pellet["life"] = 3.0
			fxl.call("ripple", pellet["to"], 6.0, 0.7)
		if pellet.has("landed"):
			pellet["life"] = float(pellet["life"]) - delta
			pellet["to"] = (pellet["to"] as Vector2) + Vector2(0, delta * 1.5)
	_pellets = _pellets.filter(func(p: Dictionary) -> bool: return not p.has("landed") or float(p["life"]) > 0.0)


func _landed_pellets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pellet in _pellets:
		if pellet.has("landed"):
			out.append(pellet)
	return out


# ------------------------------------------------------------------ cá

func _spawn_fish(pos: Vector2, vel: Vector2, crossing: bool) -> Dictionary:
	var s := Sprite2D.new()
	s.texture = frame("catfish", 2, 0)
	s.z_index = 0
	s.modulate = Color(1, 1, 1, 0.0)
	add_child(s)
	var fish: Dictionary = {"sprite": s, "pos": pos, "vel": vel, "alpha": 0.0, "leaving": false, "crossing": crossing,
		"phase": randf() * 3.0}
	_fishes.append(fish)
	return fish


func _spawn_crossing_fish() -> void:
	var from_left: bool = randf() < 0.5
	var speed: float = FISH_SPEEDS[mini(_pulls, FISH_SPEEDS.size() - 1)] * randf_range(0.9, 1.15)
	var start := Vector2(POND_X.x if from_left else 250.0, NET_REST_Y - 2.0 + randf_range(-3, 3))
	var fish: Dictionary = _spawn_fish(start, Vector2(speed if from_left else -speed, 0), true)
	fish["alpha"] = 0.3
	_spawn_wait = randf_range(0.4, 1.0)


func _crossing_count() -> int:
	var count: int = 0
	for fish in _fishes:
		if bool(fish["crossing"]) and not bool(fish["leaving"]):
			count += 1
	return count


func _remove_fish(fish: Dictionary) -> void:
	(fish["sprite"] as Sprite2D).queue_free()
	_fishes.erase(fish)


func _update_fishes(delta: float) -> void:
	var food: Array[Dictionary] = _landed_pellets()
	for fish in _fishes.duplicate():
		var pos: Vector2 = fish["pos"]
		var vel: Vector2 = fish["vel"]
		var crossing: bool = bool(fish["crossing"])
		if not crossing and not bool(fish["leaving"]):
			var best: Dictionary = {}
			if mode == MODE_FEED:
				for pellet in food:
					if best.is_empty() or pos.distance_to(pellet["to"]) < pos.distance_to(best["to"]):
						best = pellet
			if best.is_empty():
				# lội lững lờ, quay đầu ở mép ao
				if pos.x < POND_X.x + 8 and vel.x < 0 or pos.x > POND_X.y - 8 and vel.x > 0:
					vel.x = -vel.x
				var swim: float = 14.0 * signf(vel.x if vel.x != 0.0 else 1.0)
				vel = vel.lerp(Vector2(swim, sin(_time * 0.8 + float(fish["phase"])) * 6.0), delta * 1.5)
			else:
				var to: Vector2 = best["to"]
				vel = vel.lerp((to + Vector2(0, 4) - pos).normalized() * 60.0, delta * 4.0)
				if pos.distance_to(to) < 7.0:
					best["life"] = 0.0
					fxl.call("splash", to + Vector2(0, -2), 9)
					fxl.call("ripple", to, 10.0, 0.8)
					sound(&"splash", to)
					vel = Vector2(vel.x * 0.5, 40.0)
		pos += vel * delta
		pos.y = clampf(pos.y, WATER_Y + 7.0, 194.0)
		fish["pos"] = pos
		fish["vel"] = vel
		var leaving: bool = bool(fish["leaving"])
		var depth_alpha: float = lerpf(1.0, 0.55, clampf((pos.y - 120.0) / 70.0, 0.0, 1.0))
		fish["alpha"] = clampf(float(fish["alpha"]) + delta * (-1.4 if leaving else 2.0), 0.0, depth_alpha)
		var s: Sprite2D = fish["sprite"]
		s.position = pos.round()
		s.flip_h = vel.x > 0.0 # ảnh gốc: đầu cá quay sang trái
		s.texture = frame("catfish", 2, int(_time * 6.0 + float(fish["phase"])) % 2)
		var tint: float = lerpf(1.0, 0.6, clampf((pos.y - 110.0) / 80.0, 0.0, 1.0))
		s.modulate = Color(tint, tint * 1.02, tint * 1.08, float(fish["alpha"]))
		var out_of_pond: bool = pos.x < POND_X.x - 14.0 or pos.x > POND_X.y + 14.0
		if (leaving and float(fish["alpha"]) <= 0.0) or (out_of_pond and crossing):
			_remove_fish(fish)
		elif crossing and pos.x > 262.0 and vel.x > 0.0:
			fish["leaving"] = true # lội vô gầm chòi


# ------------------------------------------------------------------ vẽ

func _lift_amount() -> float:
	if _lift_t < 0.0:
		return 0.0
	# kéo lên nhanh, giữ một chút, hạ xuống
	var t: float = _lift_t
	if t < 0.35:
		return ease(t / 0.35, 0.5)
	if t < 0.7:
		return 1.0
	return 1.0 - ease((t - 0.7) / 0.3, 2.0)


func _draw_rig() -> void:
	var lift: float = _lift_amount()
	var angle: float = lerpf(ANGLE_REST, ANGLE_UP, lift)
	var dir := Vector2(-cos(angle), sin(angle))
	var tip: Vector2 = PIVOT + dir * POLE_FAR
	var butt: Vector2 = PIVOT - dir * POLE_BUTT
	var bamboo := Color(0.78, 0.68, 0.36)
	var bamboo_dark := Color(0.5, 0.42, 0.2)
	var outline_c := Color(0.16, 0.1, 0.07)
	# cần tre (viền tối + thân + đốt)
	_rig.draw_line(butt, tip, outline_c, 4.0)
	_rig.draw_line(butt, tip, bamboo, 2.0)
	for i in range(1, 9):
		var p: Vector2 = butt.lerp(tip, float(i) / 9.0)
		_rig.draw_rect(Rect2(p.round() - Vector2(1, 1), Vector2(2, 2)), bamboo_dark)
	_rig.draw_circle(PIVOT, 2.5, Color(0.4, 0.28, 0.16))
	# dây người kéo
	var hand: Vector2 = HAND + Vector2(0, -6.0 * lift)
	_rig.draw_line(butt, hand, Color(0.86, 0.8, 0.62), 1.0)
	# vó
	var hub_y: float = lerpf(NET_REST_Y - 24.0, NET_UP_Y - 18.0, lift)
	var hub := Vector2(tip.x, hub_y)
	var under: bool = hub_y + 12.0 > WATER_Y
	var rope_c := Color(0.86, 0.8, 0.62)
	_rig.draw_line(tip, hub, rope_c if hub.y < WATER_Y else Color(rope_c, 0.6), 1.0)
	var bottom_y: float = lerpf(NET_REST_Y, NET_UP_Y, lift)
	var left := Vector2(hub.x - NET_HALF, bottom_y - 4.0)
	var right := Vector2(hub.x + NET_HALF, bottom_y - 4.0)
	var glow: bool = mode == MODE_NET and _lift_t < 0.0 and not _fish_in_net().is_empty()
	var alpha: float = 0.6 if under else 1.0
	var arm := Color(0.62, 0.5, 0.24, alpha)
	# hai cần chữ thập (cong lên)
	for corner in [left, right]:
		var pts := PackedVector2Array()
		for i in range(9):
			var t: float = float(i) / 8.0
			var p: Vector2 = hub.lerp(corner, t) + Vector2(0, -sin(t * PI) * 5.0)
			pts.append(p.round())
		_rig.draw_polyline(pts, Color(outline_c, alpha * 0.8), 3.0)
		_rig.draw_polyline(pts, arm, 1.0)
	# lưới võng xuống
	var sag: float = 9.0 + 6.0 * lift
	var mesh := PackedVector2Array()
	for i in range(13):
		var t: float = float(i) / 12.0
		mesh.append((left.lerp(right, t) + Vector2(0, sin(t * PI) * sag)).round())
	var net_c := Color(1.0, 0.86, 0.3, 0.95) if glow else Color(0.85, 0.82, 0.72, 0.55 * alpha + 0.2)
	_rig.draw_polyline(mesh, net_c, 1.0)
	for i in range(1, 12, 2):
		var t: float = float(i) / 12.0
		var top: Vector2 = left.lerp(right, t) + Vector2(0, -sin(t * PI) * 4.0)
		_rig.draw_line(top.round(), mesh[i], Color(net_c, net_c.a * 0.5), 1.0)
	if glow:
		_rig.draw_rect(Rect2(Vector2(hub.x - NET_HALF, bottom_y - 22.0), Vector2(NET_HALF * 2.0, 2.0)), Color(1.0, 0.9, 0.4, 0.25 + 0.2 * sin(_time * 12.0)))
	# cá trong vó khi nhấc lên + nước nhỏ giọt
	if lift > 0.05 and hub.y + 12.0 < WATER_Y:
		if _lift_fish:
			var flop: float = roundf(sin(_time * 30.0) * 1.5)
			var ft: Texture2D = frame("catfish", 2, int(_time * 12.0) % 2)
			if ft != null:
				_rig.draw_texture(ft, (Vector2(hub.x - 14, bottom_y + sag - 9 + flop)).round())
		for i in range(5):
			var drip: float = fmod(_time * 2.6 + float(i) * 0.21, 1.0)
			var dx: float = -NET_HALF * 0.7 + float(i) * NET_HALF * 0.35
			var start := Vector2(hub.x + dx, bottom_y + sin((dx / NET_HALF * 0.5 + 0.5) * PI) * sag)
			_rig.draw_rect(Rect2((start + Vector2(0, drip * (WATER_Y - start.y))).round(), Vector2(1, 2)),
				Color(0.85, 0.95, 1.0, 0.85 * (1.0 - drip)))
	# cám đang bay theo đường vòng cung + cám nổi
	for pellet in _pellets:
		var t: float = float(pellet["t"])
		if t < 0.0:
			continue
		var p: Vector2
		if pellet.has("landed"):
			p = pellet["to"]
		else:
			p = (pellet["from"] as Vector2).lerp(pellet["to"], t) + Vector2(0, -sin(t * PI) * 26.0)
		_rig.draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(0.85, 0.66, 0.36))
	# chỗ vãi (cho cá ăn)
	if mode == MODE_FEED and running and _throws < FEED_THROWS:
		var bob: float = roundf(sin(_time * 5.0))
		var c := Vector2(_aim, WATER_Y - 1)
		_rig.draw_arc(c, 6.0, 0.0, TAU, 16, Color(1.0, 0.95, 0.6, 0.9), 1.0)
		_rig.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -14 + bob), c + Vector2(4, -14 + bob), c + Vector2(0, -9 + bob)]), Color(1.0, 0.85, 0.3))


func _cleanup() -> void:
	pass
