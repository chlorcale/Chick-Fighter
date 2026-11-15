extends "res://game/world/minigames/minigame.gd"

## Cầu ván chòi cá tra: "Cho cá ăn" (vãi 3 nắm cám, cá tra lội tới đớp, nước văng)
## và "Kéo vó" (cá lội ngang qua vó dưới nước, nhấn E đúng lúc cá ở giữa vó; 3 lần kéo → 0–3 con).
## Cá, vó, cần tre và cám đều là hình riêng của mini-game, không đụng tới cá của bản đồ.

const MODE_FEED: StringName = &"feed"
const MODE_NET: StringName = &"net"
const STAND: Vector2 = Vector2(112, 737)          # cuối cầu ván
const HAND: Vector2 = Vector2(114, 716)
const NET_CENTER: Vector2 = Vector2(92, 784)      # vó đặt dưới nước, phía nam cầu ván
const NET_HALF: Vector2 = Vector2(16, 7)
const POND_X: Vector2 = Vector2(48, 214)          # vùng nước cá lội được (theo x)
const PULLS: int = 3
const PULL_TIMEOUT: float = 9.0
const LIFT_TIME: float = 0.9
const FEED_THROWS: int = 3
const FISH_SPEEDS: Array[float] = [34.0, 44.0, 54.0]

var mode: StringName = MODE_NET

var _water: Node2D   # lớp mặt nước: cá, vó chìm
var _over: Node2D    # trên cùng (Y-sort sau cầu ván): cần tre, vó kéo lên, cám đang bay
var _fish_texture: Texture2D
var _fishes: Array[Dictionary] = [] # {sprite, pos, vel, target, alpha, leaving}
var _pellets: Array[Dictionary] = [] # {from, to, t, landed}
var _caught: int = 0
var _pulls: int = 0
var _throws: int = 0
var _lift_t: float = -1.0
var _lift_fish: bool = false
var _pull_time: float = 0.0
var _spawn_wait: float = 0.0
var _end_wait: float = -1.0
var _auto_wait: float = 0.0
var _time: float = 0.0


func _start() -> void:
	var map_view: MapView = world.map_view
	var textures: Array[Texture2D] = map_view.node_textures("C_ca_tra_con_01")
	_fish_texture = textures[0] if not textures.is_empty() else null
	_water = Node2D.new()
	_water.draw.connect(_draw_water)
	map_view.add_ground(_water)
	_over = Node2D.new()
	_over.position = Vector2(0, 800) # gốc Y-sort dưới cầu ván và nhân vật → vẽ đè lên
	_over.draw.connect(_draw_over)
	map_view.add_actor(_over)
	var tween := world.create_tween()
	tween.tween_property(world.player, "position", STAND, 0.2)
	if mode == MODE_FEED:
		time_left = 25.0
		set_texts("CHO CÁ TRA ĂN", "Nhấn [E] để vãi một nắm cám xuống ao (%d nắm)." % FEED_THROWS)
		for i in range(6):
			_spawn_fish(Vector2(randf_range(POND_X.x + 10, POND_X.y - 10), randf_range(770, 800)), Vector2.ZERO)
	else:
		time_left = 40.0
		set_texts("KÉO VÓ BẮT CÁ TRA", "Cá lội ngang vó: vó sáng vàng (cá ở giữa vó) thì nhấn [E] kéo lên! %d lần kéo." % PULLS)
		_throw_pellets(2, NET_CENTER, 6.0)
		_spawn_wait = 1.0
	_update_status()


func _wants(action: StringName) -> bool:
	return action == &"confirm" or action == &"cancel"


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "fish": 0, "thrown": _throws}


func _on_action(action: StringName) -> void:
	if action != &"confirm" or _end_wait >= 0.0:
		return
	if mode == MODE_FEED:
		if _throws < FEED_THROWS:
			_throws += 1
			_throw_pellets(5, Vector2(randf_range(110, 175), randf_range(772, 792)), 14.0)
			_update_status()
	elif _lift_t < 0.0:
		_pull()


func _pull() -> void:
	_pulls += 1
	_lift_t = 0.0
	_pull_time = 0.0
	var fish: Dictionary = _fish_in_net()
	_lift_fish = not fish.is_empty()
	if _lift_fish:
		_caught += 1
		_remove_fish(fish)
		toast("Dính rồi! +1 cá tra", Color(0.7, 1.0, 0.6))
		sound(&"catch", NET_CENTER)
	else:
		toast("Hụt rồi!", Color(1.0, 0.6, 0.5))
		sound(&"miss", NET_CENTER)
		for other in _fishes:
			other["vel"] = (other["vel"] as Vector2) * 3.0 # cá hoảng, lội lẹ đi chỗ khác
			other["leaving"] = true
	ground_fx.ripple(NET_CENTER, 14.0, 1.0)
	air_fx.splash(NET_CENTER + Vector2(0, -4), 10)
	sound(&"splash", NET_CENTER)
	_update_status()


func _fish_in_net() -> Dictionary:
	for fish in _fishes:
		if bool(fish["leaving"]):
			continue
		var pos: Vector2 = fish["pos"]
		if absf(pos.x - NET_CENTER.x) <= NET_HALF.x - 3.0 and absf(pos.y - NET_CENTER.y) <= NET_HALF.y + 2.0:
			return fish
	return {}


func _update_status() -> void:
	if mode == MODE_FEED:
		set_status("Nắm cám: %d/%d" % [_throws, FEED_THROWS])
	else:
		set_status("Lần kéo: %d/%d · Bắt được: %d con · còn %d giây" % [_pulls, PULLS, _caught, ceili(time_left)])


func _tick(delta: float) -> void:
	_time += delta
	time_left -= delta
	_update_pellets(delta)
	_update_fishes(delta)
	if _lift_t >= 0.0:
		_lift_t += delta / LIFT_TIME
		if _lift_t >= 1.0:
			_lift_t = -1.0
			_lift_fish = false
			if mode == MODE_NET and _pulls >= PULLS:
				_end_wait = 0.5
	if _end_wait >= 0.0:
		_end_wait -= delta
		if _end_wait < 0.0:
			_finish_now()
			return
	elif mode == MODE_FEED:
		if _throws >= FEED_THROWS and _pellets.is_empty():
			_end_wait = 1.6
			for fish in _fishes:
				fish["leaving"] = true
		elif autopilot:
			_auto_wait -= delta
			if _auto_wait <= 0.0 and _throws < FEED_THROWS:
				_auto_wait = 0.7
				press(&"confirm")
	else:
		_pull_time += delta
		if _lift_t < 0.0 and _pulls < PULLS:
			_spawn_wait -= delta
			if _active_fish_count() == 0 and _spawn_wait <= 0.0:
				_spawn_crossing_fish()
			if _pull_time >= PULL_TIMEOUT:
				toast("Chậm tay quá, cá lội mất!", Color(1.0, 0.6, 0.5))
				_pulls += 1
				_pull_time = 0.0
				for fish in _fishes:
					fish["leaving"] = true
				if _pulls >= PULLS:
					_end_wait = 0.5
			elif autopilot:
				var fish: Dictionary = _fish_in_net()
				if not fish.is_empty() and absf((fish["pos"] as Vector2).x - NET_CENTER.x) <= 2.0:
					press(&"confirm")
	if time_left <= 0.0 and _end_wait < 0.0:
		_finish_now()
		return
	_update_status()
	_water.queue_redraw()
	_over.queue_redraw()


func _finish_now() -> void:
	if mode == MODE_FEED:
		finish({"thrown": _throws, "fish": 0})
	else:
		finish({"fish": _caught, "pulls": _pulls})


# ------------------------------------------------------------------ cám

func _throw_pellets(count: int, target: Vector2, spread: float) -> void:
	for i in range(count):
		var to := target + Vector2(randf_range(-spread, spread), randf_range(-spread, spread) * 0.5)
		_pellets.append({"from": HAND, "to": to, "t": -float(i) * 0.05})
	sound(&"throw", target)


func _update_pellets(delta: float) -> void:
	for pellet in _pellets:
		pellet["t"] = float(pellet["t"]) + delta / 0.5
		if float(pellet["t"]) >= 1.0 and not pellet.has("landed"):
			pellet["landed"] = true
			pellet["life"] = 3.0
			ground_fx.ripple(pellet["to"], 5.0, 0.7)
		if pellet.has("landed"):
			pellet["life"] = float(pellet["life"]) - delta
	_pellets = _pellets.filter(func(p: Dictionary) -> bool: return not p.has("landed") or float(p["life"]) > 0.0)


func _landed_pellets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pellet in _pellets:
		if pellet.has("landed"):
			result.append(pellet)
	return result


# ------------------------------------------------------------------ cá

func _spawn_fish(pos: Vector2, vel: Vector2) -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.texture = _fish_texture
	sprite.modulate = Color(1, 1, 1, 0.0)
	_water.add_child(sprite)
	var fish: Dictionary = {"sprite": sprite, "pos": pos, "vel": vel, "alpha": 0.0, "leaving": false}
	_fishes.append(fish)
	return fish


func _spawn_crossing_fish() -> void:
	var from_left: bool = randf() < 0.5
	var speed: float = FISH_SPEEDS[mini(_pulls, FISH_SPEEDS.size() - 1)] * randf_range(0.9, 1.15)
	var start := Vector2(POND_X.x if from_left else POND_X.y, NET_CENTER.y + randf_range(-2, 2))
	_spawn_fish(start, Vector2(speed if from_left else -speed, 0))
	_spawn_wait = randf_range(0.4, 1.0)


func _active_fish_count() -> int:
	var count: int = 0
	for fish in _fishes:
		if not bool(fish["leaving"]):
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
		if mode == MODE_FEED and not bool(fish["leaving"]):
			# Lội tới hạt cám gần nhất, tới nơi thì đớp (nước văng).
			var best: Dictionary = {}
			for pellet in food:
				if best.is_empty() or pos.distance_to(pellet["to"]) < pos.distance_to(best["to"]):
					best = pellet
			if best.is_empty():
				vel = vel.lerp(Vector2(sin(_time + pos.y) * 10.0, cos(_time * 0.7 + pos.x) * 4.0), delta * 2.0)
			else:
				var to: Vector2 = best["to"]
				vel = vel.lerp((to - pos).normalized() * 42.0, delta * 4.0)
				if pos.distance_to(to) < 4.0:
					best["life"] = 0.0
					air_fx.splash(to + Vector2(0, -2), 6)
					ground_fx.ripple(to, 9.0, 0.8)
					sound(&"splash", to)
		pos += vel * delta
		pos.y = clampf(pos.y, 762.0, 806.0)
		fish["pos"] = pos
		fish["vel"] = vel
		var leaving: bool = bool(fish["leaving"])
		fish["alpha"] = clampf(float(fish["alpha"]) + delta * (-1.2 if leaving else 2.0), 0.0, 0.9)
		var sprite: Sprite2D = fish["sprite"]
		sprite.position = pos.round()
		sprite.flip_h = vel.x > 0.0 # ảnh gốc: đầu cá quay sang trái
		sprite.modulate.a = float(fish["alpha"])
		var out_of_pond: bool = pos.x < POND_X.x - 6.0 or pos.x > POND_X.y + 6.0
		if (leaving and float(fish["alpha"]) <= 0.0) or (out_of_pond and mode == MODE_NET):
			_remove_fish(fish)
		elif mode == MODE_NET and fmod(_time + pos.x * 0.01, 0.35) < delta:
			ground_fx.ripple(pos + Vector2(-signf(vel.x) * 10.0, 0), 3.0, 0.6) # bọt sau đuôi


# ------------------------------------------------------------------ vẽ

func _draw_water() -> void:
	if mode != MODE_NET:
		return
	var lifted: bool = _lift_t >= 0.0
	var glow: bool = not _fish_in_net().is_empty() and not lifted
	var rect := Rect2(NET_CENTER - NET_HALF, NET_HALF * 2.0)
	var line := Color(1.0, 0.85, 0.3, 0.95) if glow else Color(0.12, 0.1, 0.08, 0.55)
	if lifted:
		line.a *= 0.3
	for i in range(1, 4):
		var x: float = rect.position.x + rect.size.x * float(i) / 4.0
		_water.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(line, line.a * 0.45), 1.0)
	_water.draw_line(Vector2(rect.position.x, NET_CENTER.y), Vector2(rect.end.x, NET_CENTER.y), Color(line, line.a * 0.45), 1.0)
	_water.draw_rect(rect, line, false, 1.0)


func _draw_over() -> void:
	_over.draw_set_transform(-_over.position)
	# Cám đang bay theo đường vòng cung.
	for pellet in _pellets:
		var t: float = float(pellet["t"])
		if t < 0.0 or pellet.has("landed"):
			continue
		var p: Vector2 = (pellet["from"] as Vector2).lerp(pellet["to"], t) + Vector2(0, -sin(t * PI) * 16.0)
		_over.draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(0.85, 0.7, 0.4))
	if mode != MODE_NET:
		return
	# Cần tre + vó: chìm dưới nước khi chờ, kéo bổng lên khi bấm.
	var lift: float = sin(clampf(_lift_t, 0.0, 1.0) * PI) * 16.0 if _lift_t >= 0.0 else 0.0
	var hub := NET_CENTER + Vector2(0, -14.0 - lift)
	_over.draw_line(HAND, hub + Vector2(0, -2), Color(0.55, 0.4, 0.18), 2.0)
	_over.draw_line(HAND + Vector2(1, -1), hub + Vector2(1, -3), Color(0.8, 0.65, 0.3), 1.0)
	if lift <= 0.5:
		_over.draw_line(hub, NET_CENTER, Color(0.85, 0.8, 0.65, 0.7), 1.0)
		return
	var top := NET_CENTER + Vector2(0, -lift)
	var corners: Array[Vector2] = [top + Vector2(-NET_HALF.x, -NET_HALF.y), top + Vector2(NET_HALF.x, -NET_HALF.y),
		top + Vector2(NET_HALF.x, NET_HALF.y), top + Vector2(-NET_HALF.x, NET_HALF.y)]
	for corner in corners:
		_over.draw_line(hub, corner, Color(0.85, 0.8, 0.65), 1.0)
	var net := Color(0.25, 0.2, 0.15, 0.85)
	var sag := PackedVector2Array()
	for i in range(9):
		var x: float = -NET_HALF.x + NET_HALF.x * 2.0 * float(i) / 8.0
		sag.append((top + Vector2(x, NET_HALF.y + 3.0 - absf(x) / NET_HALF.x * 3.0)).round())
	_over.draw_polyline(sag, net, 1.0)
	_over.draw_line(corners[0], corners[1], net, 1.0)
	_over.draw_line(corners[0], corners[3], net, 1.0)
	_over.draw_line(corners[1], corners[2], net, 1.0)
	if _lift_fish and _fish_texture != null:
		var flop: float = roundf(sin(_time * 30.0))
		_over.draw_texture(_fish_texture, (top + Vector2(-14, -3 + flop)).round())
	# Nước nhỏ giọt từ vó.
	for i in range(3):
		var drip: float = fmod(_time * 3.0 + float(i) * 0.33, 1.0)
		_over.draw_rect(Rect2((top + Vector2(-10 + i * 10, NET_HALF.y + 2 + drip * lift)).round(), Vector2(1, 1)),
			Color(0.85, 0.95, 1.0, 0.8 * (1.0 - drip)))


func _cleanup() -> void:
	for fish in _fishes:
		(fish["sprite"] as Sprite2D).queue_free()
	_fishes.clear()
	if is_instance_valid(_water):
		_water.queue_free()
	if is_instance_valid(_over):
		_over.queue_free()
