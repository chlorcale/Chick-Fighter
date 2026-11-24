extends "res://game/world/minigames/minigame.gd"

## TRANG QUÁN CƠM BÀ LAN (GDD 6 "bán hàng – chọn đúng món"): nhìn từ lề đường vô quán – mái sọc, nồi cơm bốc
## khói, bà Lan đứng quầy, khách xếp hàng ngoài đường với bong bóng gọi món.
## A/D (←/→) dời tay tới món trên quầy, E bưng ra. Đúng món +1 khách; lộn món thì khách cằn nhằn (mất kiên nhẫn);
## khách đợi lâu quá thì bỏ đi. Hết TIME_LIMIT giây là hết ca. Hệ số tay nghề 0,5–1,3 (GameState.perform nhân vào
## 70.000đ). Kết quả: {served, missed, mistakes, factor, cancelled}. Test: autopilot = true (tự chọn đúng món).

const MENU: Array[Dictionary] = [
	{"name": "Cơm tấm", "color": Color(0.95, 0.85, 0.55)},
	{"name": "Cơm cháy", "color": Color(0.85, 0.55, 0.25)},
	{"name": "Canh chua", "color": Color(0.95, 0.45, 0.3)},
	{"name": "Trà đá", "color": Color(0.55, 0.8, 0.95)},
]
const TIME_LIMIT: float = 40.0
## Phục vụ đủ chừng này khách (không lộn món) là đạt hệ số tối đa 1,3.
const TARGET: int = 12
const PATIENCE_START: float = 7.0
const PATIENCE_MIN: float = 3.5
const NEXT_DELAY: float = 0.45
const WRONG_PENALTY: float = 1.5
const CUSTOMER_LINES: Array[String] = ["Cho con dĩa %s nghen!", "Một %s, lẹ lẹ giùm!", "Bà Lan ơi, %s!",
	"Cho chú %s, thêm mỡ hành nha.", "%s một phần, ăn liền!"]
const DISH_X: Array[float] = [44.0, 92.0, 140.0, 188.0]
const COUNTER_TOP: float = 149.0
const BEHIND_Y: float = 160.0
const HERO_SIDE: float = 18.0   # đứng lệch bên phải món đang chọn (không bị dĩa che)
const QUEUE_X: Array[float] = [290.0, 318.0, 346.0, 374.0]
const STREET_Y: float = 198.0
const FACES: Array[String] = ["crowd_1", "crowd_2", "crowd_3", "crowd_4", "crowd_5", "co_thao", "chu_muoi", "lady",
	"bao_ve", "mc", "shop", "co_dieu"]

var rng_seed: int = 1

var _rng := RandomNumberGenerator.new()
var _cursor: int = 0
var _want: int = -1
var _patience: float = 0.0
var _patience_max: float = PATIENCE_START
var _wait: float = 0.0
var _served: int = 0
var _missed: int = 0
var _mistakes: int = 0
var _line: String = ""
var _face: int = 0
var _auto_t: float = 0.0
var _time: float = 0.0
var _hero: Sprite2D
var _hero_x: float = DISH_X[0] + HERO_SIDE
var _lan: Sprite2D
var _arrow: Node2D
var _queue: Array[Dictionary] = []   # {sprite, x, leaving, angry}
var _flying: Array[Dictionary] = []  # {sprite, from, to, t}
var _steam_t: float = 0.0
var _say: Label
var _say_box: PanelContainer
var _shake_t: float = 0.0


func _page() -> String:
	return "stall"


func _intro() -> Array:
	return ["BÁN CƠM PHỤ BÀ LAN", "Trưa rồi, khách xếp hàng dài trước quán!\n\nKhách gọi món trong bong bóng. [A]/[D] dời tay tới món trên quầy, [E] bưng ra.\nLộn món khách cằn nhằn, chờ lâu quá khách bỏ đi.\nBán %d khách không lộn món là bà Lan trả công cao nhất." % TARGET]


func _hint_text() -> String:
	return "[A]/[D] Chọn món   ·   [E] Bưng ra   ·   [Esc] Nghỉ"


func _ambience() -> Dictionary:
	return {&"crowd": 0.35, &"village": 0.45}


func _build() -> void:
	_rng.seed = rng_seed
	backdrop("bg")
	_lan = sprite(npc_texture("ba_lan"), Vector2(232, BEHIND_Y), 1)
	_hero = hero_sprite(Vector2(DISH_X[0] + HERO_SIDE, BEHIND_Y), 0, 2)
	backdrop("counter", 3)
	for i in range(MENU.size()):
		sprite(tex("dish_%d" % i), Vector2(DISH_X[i], COUNTER_TOP), 4)
	_arrow = Node2D.new()
	_arrow.z_index = 8
	_arrow.draw.connect(_draw_overlay)
	add_child(_arrow)
	for i in range(3):
		_add_customer(QUEUE_X[i])
	_say_box = make_panel(true)
	_say_box.visible = false
	ui.add_child(_say_box)
	ui.move_child(_say_box, 0)
	_say = make_label(UISkin.FS_BODY, CREAM, true)
	_say.autowrap_mode = TextServer.AUTOWRAP_OFF
	_say_box.add_child(_say)


func _add_customer(x: float) -> void:
	var face: String = FACES[_rng.randi_range(0, FACES.size() - 1)]
	var s: Sprite2D = sprite(npc_texture(face), Vector2(x, STREET_Y), 5)
	_queue.append({"sprite": s, "x": x, "leaving": false, "angry": false})


func _wants(action: StringName) -> bool:
	return action in [&"confirm", &"cancel", &"left", &"right"]


func _start() -> void:
	time_left = TIME_LIMIT
	_next_customer()
	_update_status()


func _next_customer() -> void:
	_want = _rng.randi_range(0, MENU.size() - 1)
	_face = _rng.randi_range(0, 5)
	_patience_max = maxf(PATIENCE_MIN, PATIENCE_START - 0.25 * float(_served))
	_patience = _patience_max
	_line = CUSTOMER_LINES[_rng.randi_range(0, CUSTOMER_LINES.size() - 1)] % String(MENU[_want]["name"]).to_lower()
	_auto_t = 0.0


func _on_action(action: StringName) -> void:
	match action:
		&"left":
			_cursor = posmod(_cursor - 1, MENU.size())
			sfx(&"ui_move", -10.0)
		&"right":
			_cursor = posmod(_cursor + 1, MENU.size())
			sfx(&"ui_move", -10.0)
		&"confirm":
			if _want < 0:
				return
			if _cursor == _want:
				_served += 1
				_want = -1
				_wait = NEXT_DELAY
				toast(["Ngon!", "Đúng món!", "Lẹ ghê!"][_served % 3], Color(0.7, 1.0, 0.6))
				sound(&"ticket")
				_serve_front()
			else:
				_mistakes += 1
				_patience -= WRONG_PENALTY
				_shake_t = 0.4
				toast("Lộn món rồi!", Color(1.0, 0.6, 0.5))
				sound(&"miss")
	_update_status()


## Món bay ra tay khách đầu hàng; khách quay đi, hàng nhích lên, khách mới tới cuối hàng.
func _serve_front() -> void:
	if _queue.is_empty():
		return
	var c: Dictionary = _queue[0]
	var s := Sprite2D.new()
	s.texture = tex("dish_%d" % _cursor)
	s.z_index = 9
	add_child(s)
	_flying.append({"sprite": s, "from": Vector2(DISH_X[_cursor], COUNTER_TOP - 8), "to": (c["sprite"] as Sprite2D).position + Vector2(7, -16), "t": 0.0, "rider": c})
	_leave_front(false)


func _leave_front(angry: bool) -> void:
	if _queue.is_empty():
		return
	var c: Dictionary = _queue.pop_front()
	c["leaving"] = true
	c["angry"] = angry
	_leaving.append(c)
	for i in range(_queue.size()):
		_queue[i]["x"] = QUEUE_X[i]
	_add_customer(QUEUE_X[mini(_queue.size(), QUEUE_X.size() - 1)] + 40.0)
	_queue.back()["x"] = QUEUE_X[mini(_queue.size() - 1, QUEUE_X.size() - 1)]


var _leaving: Array[Dictionary] = []


func factor() -> float:
	var score: float = clampf((float(_served) - 0.5 * float(_mistakes)) / float(TARGET), 0.0, 1.0)
	return 0.5 + 0.8 * score


func _result() -> Dictionary:
	return {"served": _served, "missed": _missed, "mistakes": _mistakes, "factor": factor()}


func _cancel_result() -> Dictionary:
	var r: Dictionary = _result()
	r["cancelled"] = true
	return r


func _result_info(r: Dictionary) -> Array:
	var text: String = "Bán được %d khách · lộn món %d · khách bỏ đi %d.\nHệ số tay nghề ×%s" % [int(r["served"]), int(r["mistakes"]),
		int(r["missed"]), String.num(float(r["factor"]), 2).replace(".", ",")]
	if int(r["served"]) >= TARGET:
		return ["BÁN ĐẮT NHƯ TÔM TƯƠI!", text, true]
	return ["HẾT CA!", text, int(r["served"]) > 0]


func _update_status() -> void:
	set_status("Khách: %d   ·   Lộn món: %d   ·   Bỏ đi: %d" % [_served, _mistakes, _missed])


func _tick(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		if _served >= TARGET:
			sound(&"win")
		finish(_result())
		return
	if _want < 0:
		_wait -= delta
		if _wait <= 0.0:
			_next_customer()
	else:
		_patience -= delta
		if _patience <= 0.0:
			_missed += 1
			_want = -1
			_wait = NEXT_DELAY
			toast("Khách bỏ đi rồi…", Color(1.0, 0.75, 0.5))
			sound(&"miss")
			_leave_front(true)
		elif autopilot:
			_auto_t += delta
			if _auto_t >= 0.22:
				_auto_t = 0.0
				if _cursor == _want:
					press(&"confirm")
				else:
					press(&"right" if posmod(_want - _cursor, MENU.size()) <= 2 else &"left")
	_update_status()


func _animate(delta: float) -> void:
	_time += delta
	_shake_t = maxf(_shake_t - delta, 0.0)
	# hơi nóng từ nồi
	_steam_t -= delta
	if _steam_t <= 0.0:
		_steam_t = 0.35
		var spots: Array[Vector2] = [Vector2(27, 50), Vector2(65, 54), Vector2(106, 52), Vector2(90, 84)]
		fxl.call("smoke", spots[randi() % spots.size()] + Vector2(randf_range(-4, 4), 0), 2)
	# người chơi đi dọc quầy
	var goal: float = DISH_X[_cursor] + HERO_SIDE
	var moving: bool = absf(_hero_x - goal) > 0.5
	_hero_x = move_toward(_hero_x, goal, 220.0 * delta)
	_hero.position = Vector2(roundf(_hero_x), BEHIND_Y)
	_hero.texture = hero_texture(hero_walk(&"left" if goal < _hero_x else &"right", _time) if moving else hero_idle(_time))
	_lan.position.y = BEHIND_Y - (1.0 if int(_time * 1.3) % 2 == 0 else 0.0)
	# hàng khách
	for i in range(_queue.size()):
		var c: Dictionary = _queue[i]
		var s: Sprite2D = c["sprite"]
		var x: float = move_toward(s.position.x, float(c["x"]), 60.0 * delta)
		var walking: bool = absf(x - float(c["x"])) > 0.5
		s.position = Vector2(roundf(x), STREET_Y - (float(int(_time * 8.0) % 2) if walking else 0.0))
		if i == 0 and _shake_t > 0.0:
			s.position.x += roundf(sin(_time * 60.0) * 1.5)
	for c in _leaving.duplicate():
		var s: Sprite2D = c["sprite"]
		s.position.x += 70.0 * delta
		s.position.y = STREET_Y - float(int(_time * 8.0) % 2)
		if bool(c["angry"]):
			s.modulate = Color(1.0, 0.8, 0.8)
		if s.position.x > 420.0:
			s.queue_free()
			_leaving.erase(c)
	for f in _flying.duplicate():
		f["t"] = float(f["t"]) + delta / 0.35
		var t: float = minf(float(f["t"]), 1.0)
		var rider: Dictionary = f["rider"]
		var alive: bool = is_instance_valid(rider["sprite"])
		var to: Vector2 = (rider["sprite"] as Sprite2D).position + Vector2(7, -16) if alive else f["to"]
		f["to"] = to
		var p: Vector2 = (f["from"] as Vector2).lerp(to, t) + Vector2(0, -sin(t * PI) * 24.0)
		(f["sprite"] as Sprite2D).position = p.round()
		if t >= 1.0 and not is_instance_valid(rider["sprite"]):
			(f["sprite"] as Sprite2D).queue_free()
			_flying.erase(f)
	_arrow.queue_redraw()
	_place_say()


## Câu gọi món (chữ HUD) đặt cạnh bong bóng.
func _place_say() -> void:
	_say_box.visible = running and _want >= 0 and not _queue.is_empty()
	if not _say_box.visible:
		return
	_say.text = "“%s”" % _line
	# ngay trên bong bóng gọi món (đỉnh bong bóng = đầu khách − 86 px trang)
	var top: Vector2 = (_queue[0]["sprite"] as Sprite2D).position + Vector2(0, -88)
	var p: Vector2 = to_screen(top)
	_say_box.reset_size()
	var box: Vector2 = _say_box.size
	_say_box.position = Vector2(clampf(p.x - box.x * 0.5, 8.0, get_viewport_rect().size.x - box.x - 8.0), p.y - box.y - 2.0)


func _draw_overlay() -> void:
	# mũi tên chỉ món đang chọn
	var bob: float = roundf(sin(_time * 6.0) * 1.5)
	var a := Vector2(DISH_X[_cursor], COUNTER_TOP - 22.0 + bob)
	_arrow.draw_colored_polygon(PackedVector2Array([a + Vector2(-5, -5), a + Vector2(5, -5), a + Vector2(0, 1)]), Color(0.16, 0.08, 0.04))
	_arrow.draw_colored_polygon(PackedVector2Array([a + Vector2(-3, -4), a + Vector2(3, -4), a + Vector2(0, -1)]), Color(1.0, 0.85, 0.3))
	_arrow.draw_rect(Rect2(Vector2(DISH_X[_cursor] - 15, COUNTER_TOP - 1), Vector2(30, 2)), Color(1.0, 0.85, 0.3, 0.8))
	if not running or _want < 0 or _queue.is_empty():
		return
	# bong bóng gọi món trên đầu khách
	var head: Vector2 = (_queue[0]["sprite"] as Sprite2D).position + Vector2(0, -62)
	var r := Rect2(head + Vector2(-20, -24 + bob), Vector2(40, 30))
	_arrow.draw_rect(r.grow(1), Color(0.23, 0.15, 0.09))
	_arrow.draw_rect(r, Color(1.0, 0.98, 0.93))
	_arrow.draw_colored_polygon(PackedVector2Array([r.position + Vector2(16, 30), r.position + Vector2(24, 30), r.position + Vector2(20, 35)]), Color(1.0, 0.98, 0.93))
	var dish: Texture2D = tex("dish_%d" % _want)
	if dish != null:
		_arrow.draw_texture(dish, (r.position + Vector2(20 - dish.get_width() * 0.5, 3)).round())
	var ratio: float = clampf(_patience / _patience_max, 0.0, 1.0)
	var bar := Rect2(r.position + Vector2(4, 24), Vector2(32, 3))
	_arrow.draw_rect(bar, Color(0.3, 0.2, 0.15))
	_arrow.draw_rect(Rect2(bar.position, Vector2(32 * ratio, 3)), Color(0.4, 0.85, 0.35).lerp(Color(0.95, 0.3, 0.2), 1.0 - ratio))


func _cleanup() -> void:
	_say_box.visible = false
