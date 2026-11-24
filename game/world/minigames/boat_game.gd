extends "res://game/world/minigames/minigame.gd"

## TRANG CHỞ GHE (phụ chú Bảy, GDD 6 "chở ghe – né chướng ngại"): nhìn từ trên xuống dòng sông phù sa qua chợ nổi –
## hai bờ dừa, nhà sàn, ghe buôn đậu treo cây bẹo. Ghe chở 5 bao hàng xuôi dòng; A/D (←/→) lách qua 3 làn nước.
## Ghe ngược chiều, bè lục bình, khúc dừa trôi tới – đụng là rớt một bao hàng (chớp 1 giây không đụng nữa).
## Hết TIME_LIMIT giây là tới bến. Hệ số tay nghề 0,5–1,3 theo số bao còn lại (GameState.perform nhân vào 100.000đ).
## Luôn chừa ít nhất một làn trống mỗi hàng chướng ngại. Kết quả: {cargo, hits, factor, cancelled}.
## Test: autopilot = true (né theo làn trống xa nhất), rng_seed để tất định.

const LANES: int = 3
const TIME_LIMIT: float = 36.0
const CARGO: int = 5
const SPEED_START: float = 108.0
const SPEED_END: float = 188.0
const ROW_GAP: float = 150.0
const INVULN: float = 1.0
const BOAT_Y: float = 166.0
const VIEW_H: float = 216.0
const RIVER: Vector2 = Vector2(82, 302)
const KINDS: Array[Dictionary] = [
	{"name": "ghe", "tex": "obs_ghe", "h": 46.0},
	{"name": "luc_binh", "tex": "obs_lucbinh", "h": 24.0},
	{"name": "khuc_dua", "tex": "obs_dua", "h": 14.0},
]

var rng_seed: int = 1

var _rng := RandomNumberGenerator.new()
var _lane: int = 1
var _boat_x: float = 192.0
var _cargo: int = CARGO
var _hits: int = 0
var _obstacles: Array[Dictionary] = []   # {lane, y, kind, sprite}
var _next_row: float = 0.0
var _invuln: float = 0.0
var _time: float = 0.0
var _scroll: float = 0.0
var _auto_t: float = 0.0
var _wake_t: float = 0.0
var _water: Array[Sprite2D] = []
var _banks: Array[Sprite2D] = []
var _decor: Array[Dictionary] = []       # {sprite, y}
var _decor_next: float = 0.0
var _boat: Node2D
var _sacks: Array[Sprite2D] = []
var _lost: Array[Dictionary] = []        # bao rớt: {sprite, vel, life}


func _page() -> String:
	return "boat"


func _intro() -> Array:
	return ["CHỞ GHE QUA CHỢ NỔI", "Chở 5 bao hàng của chú Bảy xuôi qua chợ nổi tới bến!\n\n[A]/[D] lách ghe qua trái/phải.\nNé ghe ngược chiều, bè lục bình, khúc dừa trôi – đụng là rớt bao hàng xuống sông.\nTới bến còn đủ bao thì chú Bảy trả công cao nhất."]


func _hint_text() -> String:
	return "[A]/[D] Lách ghe   ·   [Esc] Nghỉ"


func _ambience() -> Dictionary:
	return {&"river": 0.7, &"crowd": 0.15, &"birds": 0.25}


func _build() -> void:
	_rng.seed = rng_seed
	for i in range(2):
		var w := Sprite2D.new()
		w.texture = tex("water")
		w.centered = false
		w.z_index = -20
		add_child(w)
		_water.append(w)
	for side in ["left", "right"]:
		for i in range(2):
			var b := Sprite2D.new()
			b.texture = tex("bank_" + side)
			b.centered = false
			b.z_index = -15
			b.position.x = 0.0 if side == "left" else VIEW.x * 0.5
			add_child(b)
			_banks.append(b)
	_boat = Node2D.new()
	_boat.z_index = 5
	_boat.position = Vector2(_boat_x, BOAT_Y)
	add_child(_boat)
	var hull := Sprite2D.new()
	hull.texture = tex("player_boat")
	_boat.add_child(hull)
	for i in range(CARGO):
		var s := Sprite2D.new()
		s.texture = tex("sack")
		s.position = Vector2(-6 + (i % 2) * 12, -14 + floorf(i * 0.5) * 10)
		_boat.add_child(s)
		_sacks.append(s)
	var rower := Node2D.new()
	rower.position = Vector2(0, 22)
	rower.draw.connect(func() -> void:
		rower.draw_circle(Vector2(0, 1), 5.0, Color(0.16, 0.1, 0.07))
		rower.draw_circle(Vector2.ZERO, 4.0, Color(0.78, 0.22, 0.16))
		rower.draw_rect(Rect2(-2, -6, 4, 3), Color(0.62, 0.15, 0.12))
		rower.draw_line(Vector2(-3, 4), Vector2(-12, 14), Color(0.55, 0.38, 0.2), 2.0))
	_boat.add_child(rower)
	_place_scroll()
	for k in range(4):
		_spawn_decor(float(k) * 60.0 - 20.0)


func _wants(action: StringName) -> bool:
	return action in [&"cancel", &"left", &"right"]


func _start() -> void:
	time_left = TIME_LIMIT
	_next_row = 40.0
	_update_status()


func _on_action(action: StringName) -> void:
	if action == &"left":
		_lane = maxi(_lane - 1, 0)
	elif action == &"right":
		_lane = mini(_lane + 1, LANES - 1)


func factor() -> float:
	return 0.5 + 0.8 * float(_cargo) / float(CARGO)


func _result() -> Dictionary:
	return {"cargo": _cargo, "hits": _hits, "factor": factor()}


func _cancel_result() -> Dictionary:
	var r: Dictionary = _result()
	r["cancelled"] = true
	return r


func _result_info(r: Dictionary) -> Array:
	var text: String = "Tới bến còn %d/%d bao · đụng %d lần.\nHệ số tay nghề ×%s" % [int(r["cargo"]), CARGO, int(r["hits"]),
		String.num(float(r["factor"]), 2).replace(".", ",")]
	if int(r["cargo"]) >= CARGO:
		return ["TỚI BẾN – ĐỦ HÀNG!", text, true]
	return ["TỚI BẾN!", text, int(r["cargo"]) > 0]


func _speed() -> float:
	return lerpf(SPEED_START, SPEED_END, clampf(1.0 - time_left / TIME_LIMIT, 0.0, 1.0))


func _lane_x(lane: int) -> float:
	return RIVER.x + (RIVER.y - RIVER.x) * (float(lane) + 0.5) / float(LANES)


func _spawn_row() -> void:
	# 1–2 chướng ngại mỗi hàng, luôn chừa một làn trống.
	var free_lane: int = _rng.randi_range(0, LANES - 1)
	var count: int = 1 if _rng.randf() < 0.55 else 2
	var lanes: Array = []
	for l in range(LANES):
		if l != free_lane:
			lanes.append(l)
	lanes.shuffle()
	for i in range(mini(count, lanes.size())):
		var kind: int = _rng.randi_range(0, KINDS.size() - 1)
		var s := Sprite2D.new()
		s.texture = tex(String(KINDS[kind]["tex"]))
		s.z_index = 3
		s.flip_h = _rng.randf() < 0.5 and kind != 0
		add_child(s)
		_obstacles.append({"lane": int(lanes[i]), "y": -40.0, "kind": kind, "sprite": s, "wob": _rng.randf() * TAU})


func _update_status() -> void:
	set_status("Hàng còn: %d/%d bao" % [_cargo, CARGO])


func _tick(delta: float) -> void:
	time_left -= delta
	_invuln = maxf(_invuln - delta, 0.0)
	if time_left <= 0.0:
		if _cargo == CARGO:
			sound(&"win")
		finish(_result())
		return
	var dy: float = _speed() * delta
	_scroll += dy
	_next_row -= dy
	if _next_row <= 0.0 and time_left > 2.0:
		_spawn_row()
		_next_row = ROW_GAP
	var keep: Array[Dictionary] = []
	for o in _obstacles:
		o["y"] = float(o["y"]) + dy
		var h: float = float(KINDS[int(o["kind"])]["h"])
		if int(o["lane"]) == _lane and _invuln <= 0.0 and float(o["y"]) + h * 0.5 > BOAT_Y - 24.0 and float(o["y"]) - h * 0.5 < BOAT_Y + 24.0:
			_hits += 1
			_cargo = maxi(_cargo - 1, 0)
			_invuln = INVULN
			toast("Rớt một bao hàng!", Color(1.0, 0.6, 0.5))
			sound(&"splash", Vector2(_boat_x, BOAT_Y))
			shake(0.25)
			_drop_sack()
			fxl.call("splash", Vector2(_lane_x(int(o["lane"])), float(o["y"])), 12)
			(o["sprite"] as Sprite2D).queue_free()
			continue
		if float(o["y"]) < VIEW_H + 60.0:
			keep.append(o)
		else:
			(o["sprite"] as Sprite2D).queue_free()
	_obstacles = keep
	if autopilot:
		_auto_t += delta
		if _auto_t >= 0.12:
			_auto_t = 0.0
			_auto_steer()
	_update_status()


func _drop_sack() -> void:
	for i in range(_sacks.size() - 1, -1, -1):
		var s: Sprite2D = _sacks[i]
		if s.visible:
			s.visible = false
			var flying := Sprite2D.new()
			flying.texture = s.texture
			flying.position = _boat.position + s.position
			flying.z_index = 6
			add_child(flying)
			_lost.append({"sprite": flying, "vel": Vector2(randf_range(-60, 60), -30), "life": 0.7})
			return


## Né: chọn làn đang trống (không chướng ngại nào chồng lên vùng ghe, tính thêm quãng phản xạ) có chướng ngại kế tiếp
## xa nhất; chỉ bước sang làn bên cạnh khi làn đó cũng đang trống.
func _auto_steer() -> void:
	var margin: float = _speed() * 0.3
	var best: int = _lane
	var best_score: float = -INF
	for l in range(LANES):
		if _danger(l, margin):
			continue
		var score: float = _next_gap(l, margin) - absf(float(l - _lane)) * 8.0
		if score > best_score:
			best_score = score
			best = l
	if best == _lane:
		return
	var step: int = _lane + (1 if best > _lane else -1)
	if not _danger(step, margin):
		press(&"right" if best > _lane else &"left")


func _danger(lane: int, margin: float) -> bool:
	for o in _obstacles:
		var h: float = float(KINDS[int(o["kind"])]["h"])
		if int(o["lane"]) == lane and float(o["y"]) + h * 0.5 > BOAT_Y - 24.0 - margin and float(o["y"]) - h * 0.5 < BOAT_Y + 28.0:
			return true
	return false


func _next_gap(lane: int, margin: float) -> float:
	var gap: float = 1000.0
	for o in _obstacles:
		var h: float = float(KINDS[int(o["kind"])]["h"])
		var bottom: float = float(o["y"]) + h * 0.5
		if int(o["lane"]) == lane and bottom <= BOAT_Y - 24.0 - margin:
			gap = minf(gap, BOAT_Y - 24.0 - bottom)
	return gap


func _spawn_decor(y: float) -> void:
	var left: bool = _rng.randf() < 0.5
	var s := Sprite2D.new()
	s.texture = tex("moored")
	s.z_index = -10
	s.position = Vector2(RIVER.x + 14.0 if left else RIVER.y - 14.0, y)
	add_child(s)
	var beo := Sprite2D.new()
	beo.texture = tex("beo")
	beo.position = Vector2(0, -26)
	s.add_child(beo)
	var pole := Line2D.new()
	pole.points = PackedVector2Array([Vector2(0, -20), Vector2(0, -26)])
	pole.width = 1.0
	pole.default_color = Color(0.5, 0.35, 0.2)
	s.add_child(pole)
	_decor.append({"sprite": s, "y": y})


func _place_scroll() -> void:
	var wy: float = fposmod(_scroll, VIEW_H)
	_water[0].position.y = roundf(wy - VIEW_H)
	_water[1].position.y = roundf(wy)
	var by: float = fposmod(_scroll, 432.0)
	for i in range(_banks.size()):
		_banks[i].position.y = roundf(by - 432.0 * float(i % 2))


func _animate(delta: float) -> void:
	_time += delta
	if phase == Phase.INTRO:
		_scroll += 30.0 * delta
	var dy: float = (_speed() if running else 30.0) * delta
	_place_scroll()
	_decor_next -= dy
	if _decor_next <= 0.0:
		_decor_next = _rng.randf_range(70.0, 140.0)
		_spawn_decor(-40.0)
	for d in _decor.duplicate():
		d["y"] = float(d["y"]) + (dy if running or phase == Phase.INTRO else 0.0)
		var s: Sprite2D = d["sprite"]
		s.position.y = roundf(float(d["y"]) + sin(_time * 1.5 + s.position.x) * 1.0)
		if float(d["y"]) > VIEW_H + 50.0:
			s.queue_free()
			_decor.erase(d)
	for o in _obstacles:
		var s: Sprite2D = o["sprite"]
		s.position = Vector2(roundf(_lane_x(int(o["lane"])) + sin(_time * 2.0 + float(o["wob"])) * 2.0), roundf(float(o["y"])))
	# ghe mình: trượt êm qua làn + nghiêng nhẹ
	var goal: float = _lane_x(_lane)
	var before: float = _boat_x
	_boat_x = lerpf(_boat_x, goal, minf(1.0, delta * 10.0))
	_boat.position = Vector2(roundf(_boat_x), BOAT_Y + roundf(sin(_time * 3.0)))
	_boat.rotation = clampf((_boat_x - before) * 0.06, -0.25, 0.25)
	_boat.visible = not (_invuln > 0.0 and int(_time * 12.0) % 2 == 0)
	_wake_t -= delta
	if _wake_t <= 0.0 and phase != Phase.DONE:
		_wake_t = 0.12
		fxl.call("ripple", Vector2(_boat_x + randf_range(-4, 4), BOAT_Y + 30.0), 10.0, 0.8, Color(0.9, 0.97, 0.95, 0.7))
	for l in _lost.duplicate():
		l["life"] = float(l["life"]) - delta
		var s: Sprite2D = l["sprite"]
		l["vel"] = (l["vel"] as Vector2) + Vector2(0, 160.0 * delta)
		s.position += (l["vel"] as Vector2) * delta
		if float(l["life"]) <= 0.0:
			fxl.call("splash", s.position, 8)
			fxl.call("ripple", s.position, 10.0, 0.9)
			s.queue_free()
			_lost.erase(l)


func _cleanup() -> void:
	pass
