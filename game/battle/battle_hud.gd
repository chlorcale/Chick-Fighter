class_name BattleHud
extends CanvasLayer

## HUD trận đấu. Chỉ quan sát BattleDirector, không giữ dữ liệu gameplay.
## Màu (GDD 10.3 / baseline): HP đỏ, Block Gauge xanh dương, Special cam (5 vạch), Card vàng.

const HP_COLOR := Color(0.92, 0.22, 0.18)
const HP_LOW_COLOR := Color(1.0, 0.55, 0.1)
const TRAIL_COLOR := Color(1.0, 0.92, 0.75)
const GUARD_COLOR := Color(0.3, 0.6, 1.0)
const SPECIAL_COLOR := Color(1.0, 0.6, 0.12)
const CARD_COLOR := Color(1.0, 0.84, 0.28)
const PANEL := Color(0.07, 0.05, 0.04, 0.85)
const FRAME := Color(0.98, 0.82, 0.38)

var director: BattleDirector
var hint: String = ""

var _canvas: Control
var _font: Font
var _font_bold: Font
var _trail: Array[float] = [1.0, 1.0]
var _trail_delay: Array[float] = [0.0, 0.0]
var _last_hp: Array[float] = [1.0, 1.0]
var _announce: Dictionary = {}
var _cut_in: Dictionary = {}
var _combos: Array[Dictionary] = [{}, {}]
var _popups: Array[Dictionary] = []
var _portraits: Array[TextureRect] = []
var _pause_index: int = 0
var _bar_shake: Array[float] = [0.0, 0.0]
var _bar_flash: Array[float] = [0.0, 0.0]
var _debris: Array[Dictionary] = []
var _hp_rects: Array[Rect2] = [Rect2(), Rect2()]
var _time: float = 0.0
# Trình diễn điện ảnh.
var _letterbox: float = 0.0
var _letterbox_target: float = 0.0
var _flash_color: Color = Color.WHITE
var _flash: float = 0.0
var _grade: float = 0.0
var _vs: float = 0.0
var _vs_t: float = 0.0
var _plates: Array[float] = [-1.0, -1.0]
var _callout: Dictionary = {}
var _heartbeat: float = 0.0
## Cắt cảnh "CÔNG AN TỚI!" (chế độ báo công an).
var _raid: float = -1.0
var _siren_beep: float = 0.0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = DialogBox.make_font()
	_font_bold = DialogBox.make_font(true)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	UISkin.pixel(_canvas)
	add_child(_canvas)
	for i in range(2):
		var portrait := TextureRect.new()
		var f: BattleDirector.Fighter = director.fighters[i]
		var atlas := AtlasTexture.new()
		atlas.atlas = FighterView.sheet_for(f.kit)
		atlas.region = f.kdef["portrait"] # đầu gà ở frame idle đầu tiên
		portrait.texture = atlas
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.size = Vector2(64, 64)
		portrait.flip_h = i == 1
		portrait.material = FighterView.material_for_side(f.side)
		_canvas.add_child(portrait)
		_portraits.append(portrait)


func announce(text: String, ticks: int, color: Color, size_mult: float = 1.0) -> void:
	_announce = {"text": text, "life": float(ticks) / 60.0, "t": 0.0, "color": color, "size": size_mult}


func cut_in(index: int, text: String) -> void:
	_cut_in = {"index": index, "text": text, "t": 0.0, "life": 0.75}


func combo(index: int, hits: int, damage: int) -> void:
	_combos[index] = {"hits": hits, "damage": damage, "t": 0.0}


func popup(index: int, text: String, color: Color) -> void:
	_popups.append({"index": index, "text": text, "color": color, "t": 0.0})


## Dải đen điện ảnh trên/dưới (0 tắt … 1 đầy).
func letterbox(target: float) -> void:
	_letterbox_target = target


func flash(color: Color, alpha: float) -> void:
	_flash_color = color
	_flash = maxf(_flash, alpha)


## Phủ màu "K.O." (ấm, tối viền) cho đòn kết thúc trận.
func grade(amount: float) -> void:
	_grade = amount


func vs_splash(seconds: float) -> void:
	_vs = seconds
	_vs_t = 0.0


func name_plate(index: int) -> void:
	_plates[index] = 0.0


func clear_plates() -> void:
	_plates = [-1.0, -1.0]


func callout(text: String, ticks: int) -> void:
	_callout = {"text": text, "t": 0.0, "life": float(ticks) / 60.0}


## Công an ập vào: băng chữ lớn nhấp nháy đỏ – xanh (chỉ trình diễn).
func raid_cut_in() -> void:
	_raid = 0.0


func reset_round() -> void:
	_combos = [{}, {}]
	_trail = [1.0, 1.0]
	_last_hp = [1.0, 1.0]
	_letterbox_target = 0.0
	_grade = 0.0


func toggle_pause() -> void:
	var tree := get_tree()
	tree.paused = not tree.paused
	_pause_index = 0


func _process(delta: float) -> void:
	_time += delta
	# chân dung gà (con của _canvas, vẽ sau) không được đè lên bảng tạm dừng
	var paused: bool = get_tree().paused
	for portrait in _portraits:
		if portrait.visible == paused:
			portrait.visible = not paused
	var real_delta: float = delta / maxf(Engine.time_scale, 0.01)
	if not _announce.is_empty():
		_announce["t"] += real_delta
		if _announce["t"] >= _announce["life"]:
			_announce = {}
	if not _cut_in.is_empty():
		_cut_in["t"] += real_delta
		if _cut_in["t"] >= _cut_in["life"]:
			_cut_in = {}
	for i in range(2):
		if not _combos[i].is_empty():
			_combos[i]["t"] += real_delta
			if _combos[i]["t"] > 1.6:
				_combos[i] = {}
		var ratio: float = director.fighters[i].hp_ratio()
		if ratio < _last_hp[i]:
			_trail_delay[i] = 0.55
			var lost: float = _last_hp[i] - ratio
			_bar_shake[i] = minf(10.0, 3.0 + lost * 120.0)
			_bar_flash[i] = 0.18
			_spawn_debris(i, ratio, lost)
		_last_hp[i] = ratio
		_bar_shake[i] = maxf(0.0, _bar_shake[i] - real_delta * 30.0)
		_bar_flash[i] = maxf(0.0, _bar_flash[i] - real_delta)
		if _trail_delay[i] > 0.0:
			_trail_delay[i] -= real_delta
		else:
			_trail[i] = move_toward(_trail[i], ratio, real_delta * 0.6)
		_trail[i] = maxf(_trail[i], ratio)
	for i in range(_debris.size() - 1, -1, -1):
		var d: Dictionary = _debris[i]
		d["t"] += real_delta
		d["vel"] += Vector2(0, 900) * real_delta
		d["pos"] += d["vel"] * real_delta
		d["rot"] += float(d["spin"]) * real_delta
		if d["t"] > 0.9:
			_debris.remove_at(i)
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i]["t"] += real_delta
		if _popups[i]["t"] > 1.0:
			_popups.remove_at(i)
	_letterbox = move_toward(_letterbox, _letterbox_target, real_delta * 5.0)
	_flash = maxf(0.0, _flash - real_delta * 3.0)
	if _vs > 0.0:
		_vs_t += real_delta
		if _vs_t >= _vs:
			_vs = 0.0
	for i in range(2):
		if _plates[i] >= 0.0:
			_plates[i] += real_delta
	if not _callout.is_empty():
		_callout["t"] += real_delta
		if _callout["t"] >= _callout["life"]:
			_callout = {}
	if _raid >= 0.0:
		_raid += real_delta
	# Báo công an: còi hú dồn dập dần ở 10 giây cuối.
	if director.mode == &"police" and director.phase == BattleDirector.Phase.FIGHT and director.clock_ticks < 600:
		_siren_beep -= real_delta
		if _siren_beep <= 0.0:
			_siren_beep = 0.35 + 1.4 * float(director.clock_ticks) / 600.0
			director.sfx.play(&"siren", -14.0 + 8.0 * (1.0 - float(director.clock_ticks) / 600.0), 1.0)
	# Nhịp tim khi máu người chơi thấp.
	if director.phase == BattleDirector.Phase.FIGHT and director.fighters[0].hp_ratio() <= 0.25 and director.fighters[0].alive():
		_heartbeat += real_delta
		if _heartbeat >= 0.8:
			_heartbeat = 0.0
			director.sfx.play(&"heartbeat", -4.0)
	else:
		_heartbeat = 0.7
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not get_tree().paused or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: int = (event as InputEventKey).physical_keycode
	get_viewport().set_input_as_handled()
	match code:
		KEY_W, KEY_UP, KEY_S, KEY_DOWN:
			_pause_index = 1 - _pause_index
		KEY_ESCAPE:
			toggle_pause()
		KEY_E, KEY_J, KEY_ENTER, KEY_SPACE:
			toggle_pause()
			if _pause_index == 1:
				director.forfeit()


# ------------------------------------------------------------------ vẽ

func _text(pos: Vector2, text: String, size: int, color: Color = Color.WHITE,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, bold: bool = false, outline: int = 6) -> void:
	# Viền "đóng dấu" (UISkin.draw_string_crisp) – viền glyph của Godot lệch nét với font pixel phóng nguyên lần.
	UISkin.draw_string_crisp(_canvas, _font_bold if bold else _font, pos, text, align, width, size, color, outline, Color.BLACK)


func _slanted(rect: Rect2, ratio: float, color: Color, right: bool, slant: float = 10.0) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if ratio <= 0.0:
		return
	var w: float = rect.size.x * ratio
	var x0: float = rect.end.x - w if right else rect.position.x
	var y0: float = rect.position.y
	var y1: float = rect.end.y
	var s: float = slant if not right else -slant
	var points := PackedVector2Array([
		Vector2(x0 + maxf(s, 0.0), y0), Vector2(x0 + w + minf(s, 0.0) + maxf(s, 0.0), y0),
		Vector2(x0 + w + minf(s, 0.0), y1), Vector2(x0, y1)])
	_canvas.draw_colored_polygon(points, color)


## Điểm trên thanh HP: u = 0..1 dọc thanh tính từ đầu ngoài (chân dung), v = 0..1 từ trên xuống.
func _bar_point(rect: Rect2, right: bool, u: float, v: float, slant: float = 12.0) -> Vector2:
	var y: float = rect.position.y + v * rect.size.y
	var lean: float = (1.0 - v) * slant
	if right:
		return Vector2(rect.end.x - u * rect.size.x - lean, y)
	return Vector2(rect.position.x + u * rect.size.x + lean, y)


func _bar_quad(rect: Rect2, right: bool, u0: float, u1: float, v0: float, v1: float, color: Color) -> void:
	u0 = clampf(u0, -0.05, 1.05)
	u1 = clampf(u1, -0.05, 1.05)
	if u1 <= u0 or color.a <= 0.0:
		return
	_canvas.draw_colored_polygon(PackedVector2Array([
		_bar_point(rect, right, u0, v0), _bar_point(rect, right, u1, v0),
		_bar_point(rect, right, u1, v1), _bar_point(rect, right, u0, v1)]), color)


func _draw_hp_bar(f: BattleDirector.Fighter, rect: Rect2, right: bool, i: int) -> void:
	var ratio: float = f.hp_ratio()
	var low: bool = ratio <= 0.3
	var pulse: float = 0.5 + 0.5 * sin(_time * 9.0)
	# Bóng đổ + khung kim loại hai lớp.
	_bar_quad(Rect2(rect.position + Vector2(5, 6), rect.size), right, -0.02, 1.02, -0.15, 1.2, Color(0, 0, 0, 0.45))
	_bar_quad(rect.grow(6), right, 0.0, 1.0, 0.0, 1.0, Color(0.18, 0.1, 0.06))
	_bar_quad(rect.grow(4), right, 0.0, 1.0, 0.0, 1.0, FRAME.darkened(0.15))
	_bar_quad(rect.grow(2), right, 0.0, 1.0, 0.0, 1.0, Color(0.12, 0.06, 0.04))
	# Lòng thanh tối, có gradient.
	_bar_quad(rect, right, 0.0, 1.0, 0.0, 0.5, Color(0.22, 0.06, 0.06))
	_bar_quad(rect, right, 0.0, 1.0, 0.5, 1.0, Color(0.12, 0.03, 0.03))
	# Lớp máu vừa mất: chớp trắng rồi chuyển cam, rút dần.
	var flashing: bool = _bar_flash[i] > 0.0
	_bar_quad(rect, right, ratio, _trail[i], 0.0, 1.0, Color(1, 1, 1) if flashing else Color(1.0, 0.62, 0.25))
	if not flashing:
		_bar_quad(rect, right, ratio, _trail[i], 0.65, 1.0, Color(0.6, 0.2, 0.05, 0.6))
	# Máu hiện tại: 4 dải sáng → tối tạo khối.
	var top: Color = Color(1.0, 0.55, 0.45)
	var mid: Color = Color(0.9, 0.16, 0.12)
	var deep: Color = Color(0.62, 0.05, 0.06)
	var bottom: Color = Color(0.38, 0.02, 0.04)
	if low:
		top = top.lerp(Color(1.0, 0.85, 0.4), pulse * 0.6)
		mid = mid.lerp(Color(1.0, 0.45, 0.1), pulse * 0.6)
	_bar_quad(rect, right, 0.0, ratio, 0.0, 0.18, top)
	_bar_quad(rect, right, 0.0, ratio, 0.18, 0.55, mid)
	_bar_quad(rect, right, 0.0, ratio, 0.55, 0.82, deep)
	_bar_quad(rect, right, 0.0, ratio, 0.82, 1.0, bottom)
	_bar_quad(rect, right, 0.0, ratio, 0.05, 0.12, Color(1, 1, 1, 0.35))
	# Vệt sáng chạy qua thanh.
	var glint: float = fmod(_time * 0.35 + 0.5 * float(i), 1.0) * 1.4 - 0.2
	_bar_quad(rect, right, maxf(glint, 0.0), minf(glint + 0.05, ratio), 0.0, 1.0, Color(1, 1, 1, 0.22))
	# Vạch chia 10%.
	for k in range(1, 10):
		var u: float = float(k) / 10.0
		_bar_quad(rect, right, u - 0.002, u + 0.002, 0.0, 1.0, Color(0, 0, 0, 0.35))
	# Mép cắt sáng ở đầu thanh máu.
	if ratio > 0.0:
		_bar_quad(rect, right, ratio - 0.006, ratio, 0.0, 1.0, Color(1.0, 0.95, 0.8, 0.9))
	if low:
		_bar_quad(rect.grow(9), right, 0.0, 1.0, 0.0, 1.0, Color(1.0, 0.2, 0.1, 0.12 * pulse))


func _spawn_debris(i: int, ratio: float, lost: float) -> void:
	var rect: Rect2 = _hp_rects[i]
	if not rect.has_area():
		return
	var right: bool = i == 1
	var count: int = clampi(int(lost * 120.0), 3, 16)
	var colors: Array[Color] = [Color(0.95, 0.2, 0.15), Color(1.0, 0.6, 0.3), Color(1, 1, 1)]
	for k in range(count):
		var u: float = ratio + randf() * lost
		_debris.append({"pos": _bar_point(rect, right, u, randf()),
			"vel": Vector2(randf_range(-140, 140), randf_range(-260, -60)),
			"rot": randf() * TAU, "spin": randf_range(-12, 12), "size": randf_range(3.0, 7.0), "t": 0.0,
			"color": colors[randi() % colors.size()]})


func _draw_hud() -> void:
	if director == null or director.fighters.size() < 2:
		return
	var size: Vector2 = _canvas.size
	var w: float = size.x
	var h: float = size.y
	var bar_w: float = w * 0.36
	_draw_backdrop(w, h)

	for i in range(2):
		var f: BattleDirector.Fighter = director.fighters[i]
		var right: bool = i == 1
		var x: float = w - 96.0 - bar_w if right else 96.0
		var portrait: TextureRect = _portraits[i]
		portrait.position = Vector2(w - 84.0 if right else 20.0, 14.0)
		_canvas.draw_rect(Rect2(portrait.position - Vector2(3, 3), portrait.size + Vector2(6, 6)), PANEL)
		_canvas.draw_rect(Rect2(portrait.position - Vector2(3, 3), portrait.size + Vector2(6, 6)), FRAME, false, 2.0)

		# HP – thanh nhiều lớp có chiều sâu.
		var shake := Vector2(randf_range(-_bar_shake[i], _bar_shake[i]), randf_range(-_bar_shake[i], _bar_shake[i]) * 0.5)
		var hp_rect := Rect2(Vector2(x, 20) + shake, Vector2(bar_w, 30))
		_hp_rects[i] = hp_rect
		_draw_hp_bar(f, hp_rect, right, i)
		var name_align: int = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		_text(Vector2(x, 98), "%s" % String(f.side["name"]).to_upper(), UISkin.FS_BODY, Color.WHITE, name_align, bar_w, true, 5)
		_text(Vector2(x, 128), "%s · %s Lv%d" % [String(f.side.get("owner", "")), GameState.BREED_NAMES[int(f.side["breed"])],
			int(f.side["lv"])], UISkin.FS_BODY, Color(0.88, 0.86, 0.8), name_align, bar_w, false, 4)
		_text(Vector2(x + 14.0 if not right else x, 43) + shake, str(f.hp()), UISkin.FS_BODY, Color.WHITE,
			HORIZONTAL_ALIGNMENT_LEFT if not right else HORIZONTAL_ALIGNMENT_RIGHT, bar_w - 14.0, true, 5)
		_draw_round_pips(i, x, bar_w, right)

		# Block Gauge
		var guard_w: float = bar_w * 0.55
		var gx: float = x + bar_w - guard_w if right else x
		var guard_rect := Rect2(gx, 53, guard_w, 8)
		_canvas.draw_rect(guard_rect.grow(2), PANEL)
		var guard_ratio: float = f.guard / BattleDirector.GUARD_MAX
		var guard_color: Color = GUARD_COLOR if not f.break_pending else Color(0.6, 0.6, 0.6)
		if guard_ratio < 0.3 and not f.break_pending:
			guard_color = GUARD_COLOR.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 14.0))
		var fill_w: float = guard_w * clampf(guard_ratio, 0.0, 1.0)
		_canvas.draw_rect(Rect2(gx + (guard_w - fill_w if right else 0.0), 53, fill_w, 8), guard_color)

		# Special Gauge 5 vạch
		var bars: int = f.special.get_available_bars()
		var partial: float = f.special.get_partial_bar_ratio()
		var seg_w: float = 38.0
		var sx: float = w - 40.0 - seg_w * 5.0 - 40.0 if right else 40.0
		var sy: float = h - 40.0
		_text(Vector2(sx + (seg_w * 5.0 + 8.0 if right else -30.0), sy + 14), str(bars), UISkin.FS_BIG,
			SPECIAL_COLOR if bars > 0 else Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		for b in range(SpecialGaugeComponent.MAX_BARS):
			var seg := Rect2(sx + float(b) * seg_w, sy, seg_w - 4.0, 14)
			_canvas.draw_rect(seg.grow(2), PANEL)
			var fill: float = 1.0 if b < bars else (partial if b == bars else 0.0)
			var color: Color = SPECIAL_COLOR if b < bars else SPECIAL_COLOR.darkened(0.35)
			if b < bars:
				color = color.lerp(Color(1, 1, 0.7), 0.25 + 0.25 * sin(_time * 6.0 + float(b)))
			_canvas.draw_rect(Rect2(seg.position, Vector2(seg.size.x * fill, seg.size.y)), color)
		_text(Vector2(sx, sy - 6), "SPECIAL", UISkin.FS_SMALL, SPECIAL_COLOR, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 4)

		# Combo
		if not _combos[i].is_empty():
			var c: Dictionary = _combos[i]
			var pop: float = 1.0 + maxf(0.0, 0.3 - float(c["t"])) * 1.5
			var cx: float = 30.0 if not right else w - 230.0
			var cy: float = 340.0
			var alpha: float = clampf(1.6 - float(c["t"]), 0.0, 1.0)
			_text(Vector2(cx, cy), "%d" % int(c["hits"]), int(66 * pop), Color(1.0, 0.85, 0.3, alpha),
				HORIZONTAL_ALIGNMENT_LEFT, -1, true, 8)
			_text(Vector2(cx + 4, cy + 32.0), "ĐÒN LIÊN HOÀN", UISkin.FS_BODY, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_LEFT, -1, true, 5)
			_text(Vector2(cx + 4, cy + 62.0), "%d sát thương" % int(c["damage"]), UISkin.FS_BODY, Color(1.0, 0.75, 0.6, alpha),
				HORIZONTAL_ALIGNMENT_LEFT, -1, false, 4)

	_draw_clock(w)
	_draw_police(w, h)
	_draw_cards(director.fighters[0], w, h)
	_draw_objectives()

	for p in _popups:
		var f: BattleDirector.Fighter = director.fighters[int(p["index"])]
		var world: Vector2 = f.body.global_position + Vector2(0, -150)
		var screen: Vector2 = director.get_viewport().get_canvas_transform() * world
		var color: Color = p["color"]
		color.a = clampf(1.2 - float(p["t"]) * 1.2, 0.0, 1.0)
		_text(screen + Vector2(-200, -float(p["t"]) * 40.0), String(p["text"]), UISkin.FS_BODY, color,
			HORIZONTAL_ALIGNMENT_CENTER, 400, true, 5)

	for d in _debris:
		var c: Color = d["color"]
		c.a = clampf(1.0 - float(d["t"]) / 0.9, 0.0, 1.0)
		var half: float = float(d["size"]) * 0.5
		var rot: float = float(d["rot"])
		var p: Vector2 = d["pos"]
		var pts := PackedVector2Array()
		for corner in [Vector2(-half, -half * 0.6), Vector2(half, -half * 0.6), Vector2(half, half * 0.6), Vector2(-half, half * 0.6)]:
			pts.append(p + (corner as Vector2).rotated(rot))
		_canvas.draw_colored_polygon(pts, c)

	if director.rush_clash > 0:
		var a: int = director.fighters[0].mash
		var b: int = director.fighters[1].mash
		var share: float = 0.5 if a + b == 0 else float(a) / float(a + b)
		var meter := Rect2(w * 0.5 - 220.0, h * 0.28, 440.0, 22.0)
		_canvas.draw_rect(meter.grow(4), PANEL)
		_canvas.draw_rect(Rect2(meter.position, Vector2(meter.size.x * share, meter.size.y)), HP_COLOR)
		_canvas.draw_rect(Rect2(meter.position + Vector2(meter.size.x * share, 0), Vector2(meter.size.x * (1.0 - share), meter.size.y)), GUARD_COLOR)
		_canvas.draw_rect(meter.grow(4), FRAME, false, 3.0)
		_text(Vector2(0, h * 0.28 - 12.0), "BẤM H LIÊN TỤC!  %d – %d" % [a, b], UISkin.FS_BODY,
			Color(1.0, 0.85, 0.3).lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 16.0)), HORIZONTAL_ALIGNMENT_CENTER, w, true, 5)

	if hint != "":
		_text(Vector2(0, 162), hint, UISkin.FS_BODY, Color(0.9, 1.0, 0.9), HORIZONTAL_ALIGNMENT_CENTER, w, false, 5)
	_draw_cinematic(w, h)

	if not _cut_in.is_empty():
		_draw_cut_in(w, h)
	if _raid >= 0.0:
		_draw_raid(w, h)
	if not _announce.is_empty():
		var t: float = float(_announce["t"])
		var life: float = float(_announce["life"])
		var scale: float = float(_announce["size"]) * (1.0 + maxf(0.0, 0.18 - t) * 3.0)
		var color: Color = _announce["color"]
		color.a = clampf((life - t) * 4.0, 0.0, 1.0)
		_canvas.draw_rect(Rect2(0, h * 0.42 - 52.0 * scale, w, 76.0 * scale), Color(0, 0, 0, 0.35 * color.a))
		_text(Vector2(0, h * 0.42), String(_announce["text"]), int(55 * scale), color,
			HORIZONTAL_ALIGNMENT_CENTER, w, true, 10)

	_text(Vector2(0, h - 8), "A/D đi · W nhảy · S cúi · J nhẹ · K vừa · L mạnh · H đặc biệt · U/I/O thẻ · giữ lùi = đỡ · Esc: bảng chiêu",
		UISkin.FS_SMALL, Color(0.95, 0.93, 0.86, 0.92), HORIZONTAL_ALIGNMENT_CENTER, w, true, 4)

	if get_tree().paused:
		_draw_pause(w, h)


## Bảng tạm dừng: tiêu đề + lựa chọn ở dải trên, bảng chiêu (khung gỗ, giấy) chiếm phần dưới màn hình.
func _draw_pause(w: float, h: float) -> void:
	_canvas.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.7))
	var player: BattleDirector.Fighter = director.fighters[0]
	var moves: Array = Moves.move_list(player.kit)
	var row_h: float = 30.0
	var panel := Rect2(32, 16, w - 64.0, minf(h - 32.0, 218.0 + row_h * float(moves.size())))
	UISkin.draw_panel(_canvas, panel, &"wood")
	var inner_x: float = panel.position.x + 30.0
	var inner_w: float = panel.size.x - 60.0
	_text(Vector2(inner_x, panel.position.y + 76.0), "TẠM DỪNG", UISkin.FS_HUGE, UISkin.INK_RED, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 0)
	var options: Array[String] = ["Tiếp tục", "Bỏ cuộc (tính thua)"]
	var ox: float = inner_x + UISkin.text_size("TẠM DỪNG", UISkin.FS_HUGE, true).x + 56.0
	for i in range(2):
		var sel: bool = i == _pause_index
		var oy: float = panel.position.y + 52.0 + float(i) * 34.0
		if sel:
			_canvas.draw_texture(UISkin.texture("cursor"), Vector2(ox - 30.0, oy - 18.0))
		_text(Vector2(ox, oy), options[i], UISkin.FS_BODY, UISkin.INK_RED if sel else UISkin.INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT, -1,
			sel, 0)
	_canvas.draw_rect(Rect2(inner_x, panel.position.y + 100.0, inner_w, 2.0), Color(UISkin.INK_SOFT, 0.5))
	_text(Vector2(inner_x, panel.position.y + 136.0), "BẢNG CHIÊU", UISkin.FS_BODY, UISkin.INK_RED, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 0)
	_text(Vector2(inner_x, panel.position.y + 136.0), "J = L · K = M · L = H · H = S", UISkin.FS_BODY, UISkin.INK_SOFT,
		HORIZONTAL_ALIGNMENT_RIGHT, inner_w, false, 0)
	var y: float = panel.position.y + 170.0
	var key_x: float = inner_x + inner_w * 0.6
	for entry in moves:
		_text(Vector2(inner_x, y), String(entry[0]), UISkin.FS_BODY, UISkin.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, false, 0)
		_text(Vector2(key_x, y), String(entry[1]), UISkin.FS_BODY, UISkin.INK_RED, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 0)
		y += row_h
	_text(Vector2(inner_x, minf(y + 6.0, panel.end.y - 26.0)), String(player.kdef["combos"]), UISkin.FS_BODY, UISkin.INK_SOFT,
		HORIZONTAL_ALIGNMENT_LEFT, inner_w, false, 0)


## Lớp dưới HUD: phủ màu K.O., viền đỏ nhịp tim khi máu thấp.
func _draw_backdrop(w: float, h: float) -> void:
	if _grade > 0.0:
		_canvas.draw_rect(Rect2(0, 0, w, h), Color(0.35, 0.12, 0.02, 0.18 * _grade))
		for k in range(6):
			var a: float = 0.1 * _grade * float(6 - k) / 6.0
			var e: float = float(k) * 22.0
			_canvas.draw_rect(Rect2(0, e, w, 22), Color(0, 0, 0, a))
			_canvas.draw_rect(Rect2(0, h - e - 22.0, w, 22), Color(0, 0, 0, a))
	var p: BattleDirector.Fighter = director.fighters[0]
	if p.hp_ratio() <= 0.25 and p.alive() and director.phase == BattleDirector.Phase.FIGHT:
		var beat: float = pow(maxf(0.0, sin(_time * TAU * 1.25)), 6.0)
		var strength: float = (0.25 - p.hp_ratio()) / 0.25 * 0.5 + 0.25
		for k in range(8):
			var a: float = strength * (0.4 + 0.6 * beat) * float(8 - k) / 8.0 * 0.38
			var e: float = float(k) * 9.0
			var c := Color(0.85, 0.05, 0.02, a)
			_canvas.draw_rect(Rect2(0, e, w, 9), c)
			_canvas.draw_rect(Rect2(0, h - e - 9.0, w, 9), c)
			_canvas.draw_rect(Rect2(e, 0, 9, h), c)
			_canvas.draw_rect(Rect2(w - e - 9.0, 0, 9, h), c)


## Ô hiệp thắng dưới thanh máu + "ĐIỂM QUYẾT ĐỊNH" khi chỉ còn một hiệp nữa là thắng trận.
func _draw_round_pips(i: int, x: float, bar_w: float, right: bool) -> void:
	var need: int = director.rounds_to_win
	if need <= 1:
		return
	var wins: int = director.round_wins[i]
	for k in range(need):
		var cx: float = (x + bar_w - 12.0 - float(k) * 26.0) if not right else (x + 12.0 + float(k) * 26.0)
		var c := Vector2(cx, 70)
		_canvas.draw_circle(c, 9.0, Color(0, 0, 0, 0.7))
		_canvas.draw_circle(c, 7.0, FRAME.darkened(0.5))
		if k < wins:
			var glow: float = 0.5 + 0.5 * sin(_time * 5.0)
			_canvas.draw_circle(c, 6.0, Color(1.0, 0.82, 0.25).lerp(Color.WHITE, 0.25 * glow))
	if wins == need - 1 and director.phase in [BattleDirector.Phase.FIGHT, BattleDirector.Phase.ROUND_INTRO]:
		var pulse: float = 0.6 + 0.4 * sin(_time * 6.0)
		var label_x: float = (x + bar_w - 26.0 * float(need) - 150.0) if not right else (x + 26.0 * float(need) + 10.0)
		_text(Vector2(label_x, 76), "ĐIỂM QUYẾT ĐỊNH", UISkin.FS_SMALL, Color(1.0, 0.45, 0.25, pulse), HORIZONTAL_ALIGNMENT_LEFT, -1, true, 4)


## Dải đen điện ảnh, màn VS, bảng tên khi ra sân, lời bình (HOÀN HẢO / LỘI NGƯỢC DÒNG), chớp màn hình.
func _draw_cinematic(w: float, h: float) -> void:
	if _letterbox > 0.0:
		var bar: float = h * 0.11 * _letterbox
		_canvas.draw_rect(Rect2(0, 0, w, bar), Color(0, 0, 0, 0.92))
		_canvas.draw_rect(Rect2(0, h - bar, w, bar), Color(0, 0, 0, 0.92))
	for i in range(2):
		if _plates[i] >= 0.0:
			_draw_plate(i, w, h)
	if _vs > 0.0:
		_draw_vs(w, h)
	if director.phase == BattleDirector.Phase.INTRO and director.mode != &"tutorial" and director.cinematics:
		_text(Vector2(0, 162), "J / K / L / H: bỏ qua", UISkin.FS_BODY, Color(1, 1, 1, 0.6 + 0.3 * sin(_time * 4.0)),
			HORIZONTAL_ALIGNMENT_CENTER, w, false, 4)
	if not _callout.is_empty():
		var t: float = float(_callout["t"])
		var a: float = clampf(minf(t * 6.0, (float(_callout["life"]) - t) * 3.0), 0.0, 1.0)
		var sc: float = 1.0 + maxf(0.0, 0.2 - t) * 2.0
		_text(Vector2(0, h * 0.56), String(_callout["text"]), int(44 * sc), Color(1.0, 0.95, 0.55, a),
			HORIZONTAL_ALIGNMENT_CENTER, w, true, 9)
	if _flash > 0.0:
		var c: Color = _flash_color
		c.a = _flash
		_canvas.draw_rect(Rect2(0, 0, w, h), c)


func _draw_plate(i: int, w: float, h: float) -> void:
	var f: BattleDirector.Fighter = director.fighters[i]
	var t: float = _plates[i]
	var k: float = clampf(t / 0.25, 0.0, 1.0)
	var right: bool = i == 1
	var pw: float = 420.0
	var x: float = lerpf(-pw, 40.0, k) if not right else lerpf(w, w - pw - 40.0, k)
	var y: float = h * 0.66
	var panel := Rect2(x, y, pw, 112)
	_canvas.draw_rect(panel, Color(0.06, 0.04, 0.03, 0.88))
	_canvas.draw_rect(Rect2(panel.position, Vector2(pw, 5)), HP_COLOR if not right else GUARD_COLOR)
	_canvas.draw_rect(panel, FRAME, false, 2.0)
	var align: int = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	_text(Vector2(x + 16, y + 48), String(f.side["name"]).to_upper(), UISkin.FS_BIG, Color.WHITE, align, pw - 32.0, true, 6)
	_text(Vector2(x + 16, y + 78), "Chủ gà: %s" % String(f.side.get("owner", "")), UISkin.FS_BODY, Color(0.9, 0.9, 0.9), align, pw - 32.0, false, 4)
	_text(Vector2(x + 16, y + 104), "%s · Lv%d" % [GameState.BREED_NAMES[int(f.side["breed"])], int(f.side["lv"])], UISkin.FS_BODY,
		FRAME, align, pw - 32.0, true, 4)


func _draw_vs(w: float, h: float) -> void:
	var t: float = _vs_t
	var a: float = clampf(minf(t * 5.0, (_vs - t) * 4.0), 0.0, 1.0)
	var slide: float = (1.0 - clampf(t / 0.2, 0.0, 1.0)) * w * 0.5
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(-slide, h * 0.3), Vector2(w * 0.54 - slide, h * 0.3),
		Vector2(w * 0.46 - slide, h * 0.7), Vector2(-slide, h * 0.7)]), Color(0.55, 0.1, 0.06, 0.85 * a))
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.54 + slide, h * 0.3), Vector2(w + slide, h * 0.3),
		Vector2(w + slide, h * 0.7), Vector2(w * 0.46 + slide, h * 0.7)]), Color(0.1, 0.18, 0.45, 0.85 * a))
	for i in range(2):
		var f: BattleDirector.Fighter = director.fighters[i]
		var align: int = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		var x: float = 60.0 - slide if i == 0 else slide
		_text(Vector2(x, h * 0.5 + 12), String(f.side["name"]).to_upper(), UISkin.FS_BIG, Color(1, 1, 1, a), align, w - 60.0, true, 8)
		_text(Vector2(x, h * 0.5 + 46), "%s · %s" % [String(f.side.get("owner", "")), GameState.BREED_NAMES[int(f.side["breed"])]],
			UISkin.FS_BODY, Color(1.0, 0.85, 0.5, a), align, w - 60.0, false, 5)
	var vs_scale: float = 1.0 + maxf(0.0, 0.25 - t) * 4.0
	_text(Vector2(0, h * 0.5 + 24), "VS", int(88 * vs_scale), Color(1.0, 0.92, 0.5, a), HORIZONTAL_ALIGNMENT_CENTER, w, true, 12)


func _draw_clock(w: float) -> void:
	var box := Rect2(w * 0.5 - 46.0, 10, 92, 62)
	_canvas.draw_rect(box, PANEL)
	_canvas.draw_rect(box, FRAME, false, 3.0)
	var label: String = "--" # font pixel không có "∞"
	if director.mode != &"tutorial":
		label = "%02d" % int(ceil(float(maxi(director.clock_ticks, 0)) / 60.0))
	if director.rounds_to_win > 1:
		_text(Vector2(box.position.x - 40.0, box.end.y + 28), "HIỆP %d" % director.round_index, UISkin.FS_BODY, FRAME,
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x + 80.0, true, 5)
	var color: Color = Color(1.0, 0.95, 0.7)
	if director.overtime or (director.clock_ticks < 600 and director.mode != &"tutorial"):
		color = Color(1.0, 0.45, 0.3)
	_text(Vector2(box.position.x, box.position.y + 50), label, UISkin.FS_HUGE, color, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, true, 6)


## Báo công an: dòng đếm ngược dưới đồng hồ + đèn đỏ/xanh hai mép màn hình mạnh dần ở 10 giây cuối.
## Hell Mode: nhãn đỏ dưới đồng hồ.
func _draw_police(w: float, h: float) -> void:
	if director.hell_mode and director.mode != &"police":
		_text(Vector2(0, 124), "HELL MODE", UISkin.FS_SMALL, Color(1.0, 0.35, 0.2, 0.75 + 0.25 * sin(_time * 5.0)),
			HORIZONTAL_ALIGNMENT_CENTER, w, true, 4)
	if director.mode != &"police" or director.raid:
		return
	var secs: int = int(ceil(float(maxi(director.clock_ticks, 0)) / 60.0))
	var urgent: float = clampf(1.0 - float(director.clock_ticks) / 600.0, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_time * (4.0 + 10.0 * urgent))
	_text(Vector2(0, 132), "Công an tới trong %d…" % secs, UISkin.FS_BODY, Color(0.7, 0.85, 1.0).lerp(Color(1.0, 0.4, 0.35), urgent * pulse),
		HORIZONTAL_ALIGNMENT_CENTER, w, true, 6)
	if director.phase != BattleDirector.Phase.FIGHT:
		return
	var level: float = 0.12 + 0.55 * urgent
	var swap: bool = int(_time * (3.0 + 6.0 * urgent)) % 2 == 0
	for k in range(6):
		var a: float = level * float(6 - k) / 6.0 * (0.4 + 0.6 * pulse)
		var e: float = float(k) * 12.0
		var left := Color(0.95, 0.1, 0.1, a) if swap else Color(0.15, 0.35, 1.0, a)
		var right := Color(0.15, 0.35, 1.0, a) if swap else Color(0.95, 0.1, 0.1, a)
		_canvas.draw_rect(Rect2(e, 0, 12, h), left)
		_canvas.draw_rect(Rect2(w - e - 12.0, 0, 12, h), right)


func _draw_raid(w: float, h: float) -> void:
	var t: float = _raid
	var k: float = clampf(t / 0.15, 0.0, 1.0)
	var swap: bool = int(t * 8.0) % 2 == 0
	_canvas.draw_rect(Rect2(0, 0, w, h), (Color(0.9, 0.1, 0.1, 0.18) if swap else Color(0.15, 0.3, 1.0, 0.18)))
	var band_h: float = 150.0 * k
	var y: float = h * 0.42
	_canvas.draw_rect(Rect2(0, y - band_h * 0.5, w, band_h), Color(0.03, 0.04, 0.1, 0.9))
	for i in range(16):
		var x: float = fmod(float(i) * 140.0 + t * 900.0, w + 140.0) - 140.0
		var c := Color(0.95, 0.15, 0.15, 0.85) if (i + int(t * 8.0)) % 2 == 0 else Color(0.2, 0.4, 1.0, 0.85)
		_canvas.draw_rect(Rect2(x, y - band_h * 0.5, 70, 8), c)
		_canvas.draw_rect(Rect2(w - x - 70.0, y + band_h * 0.5 - 8.0, 70, 8), c)
	if band_h > 60.0:
		var shake := Vector2(sin(t * 50.0) * 4.0, cos(t * 43.0) * 2.0) * maxf(0.0, 1.0 - t)
		_text(Vector2(0, y + 18) + shake, "CÔNG AN TỚI!", int(76 * (1.0 + maxf(0.0, 0.25 - t) * 2.0)),
			Color(1.0, 0.95, 0.9), HORIZONTAL_ALIGNMENT_CENTER, w, true, 12)
		_text(Vector2(0, y + 56), "Tuýt tuýt! Giải tán! Bà con chạy tán loạn…", UISkin.FS_BODY, Color(0.75, 0.85, 1.0),
			HORIZONTAL_ALIGNMENT_CENTER, w, true, 6)


func _draw_cards(f: BattleDirector.Fighter, w: float, h: float) -> void:
	if f.cards == null:
		return
	var hand: Array[StringName] = f.cards.get_hand_card_ids()
	var card_w: float = 104.0
	var card_h: float = 66.0
	var total: float = float(hand.size()) * (card_w + 8.0)
	var x0: float = w * 0.5 - total * 0.5
	var y: float = h - 96.0
	var selected: int = f.cards.get_selected_index()
	var gauge: int = f.card_gauge.get_current_gauge()

	# Card Gauge 5 ô + tiến độ hồi.
	var regen: float = float(f.card_gauge.get_regen_progress_ticks()) / float(CardGaugeComponent.REGEN_INTERVAL_TICKS)
	for g in range(CardGaugeComponent.MAX_GAUGE):
		var pip := Rect2(w * 0.5 - 70.0 + float(g) * 28.0, y - 24.0, 24, 12)
		_canvas.draw_rect(pip.grow(2), PANEL)
		if g < gauge:
			_canvas.draw_rect(pip, CARD_COLOR)
		elif g == gauge:
			_canvas.draw_rect(Rect2(pip.position, Vector2(pip.size.x * regen, pip.size.y)), CARD_COLOR.darkened(0.45))

	if f.cards.is_shuffling():
		_text(Vector2(0, y + 40), "Đang xáo bài… %.1fs" % (float(f.cards.get_shuffle_remaining_ticks()) / 60.0),
			UISkin.FS_BODY, CARD_COLOR, HORIZONTAL_ALIGNMENT_CENTER, w, false, 4)
		return
	for i in range(hand.size()):
		var info: Dictionary = GameState.CARD_INFO.get(hand[i], {"name": String(hand[i]), "cost": 0, "color": Color.GRAY})
		var lift: float = 10.0 if i == selected else 0.0
		var rect := Rect2(x0 + float(i) * (card_w + 8.0), y - lift, card_w, card_h)
		var affordable: bool = gauge >= int(info["cost"])
		var base: Color = (info["color"] as Color).darkened(0.25 if affordable else 0.6)
		_canvas.draw_rect(rect, base)
		_canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 28)), base.lightened(0.2))
		_canvas.draw_rect(rect, FRAME if i == selected else Color(0.15, 0.1, 0.08), false, 3.0 if i == selected else 2.0)
		_text(rect.position + Vector2(0, 22), String(info["name"]), UISkin.FS_BODY, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x, false, 4)
		for c in range(int(info["cost"])):
			_canvas.draw_circle(rect.position + Vector2(rect.size.x - 10.0 - float(c) * 14.0, 40), 5.0, CARD_COLOR)
		if i == selected:
			_text(rect.position + Vector2(6, 60), "[O] tung", UISkin.FS_SMALL, CARD_COLOR, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 3)

	var effects: Array[StringName] = f.cards.get_active_effect_ids()
	var ey: float = y - 44.0
	for effect_id in effects:
		var remain: float = float(f.cards.get_active_effect_remaining_ticks(effect_id)) / 60.0
		var label: String = {&"attack_power_bonus": "Cuồng Nộ +30% ATK", &"incoming_damage_reduction": "Mai Rùa −25% sát thương",
			&"heavy_knockback_bonus": "Gió Sông: Heavy đẩy xa"}.get(effect_id, String(effect_id))
		_text(Vector2(0, ey), "%s  %.1fs" % [label, remain], UISkin.FS_BODY, CARD_COLOR, HORIZONTAL_ALIGNMENT_CENTER, w, false, 5)
		ey -= 30.0


func _draw_objectives() -> void:
	if director.objectives.is_empty():
		return
	var y: float = 214.0
	var panel_h: float = 36.0 + 30.0 * float(director.objectives.size())
	_canvas.draw_rect(Rect2(14, y - 30, 620, panel_h), Color(0, 0, 0, 0.5))
	_text(Vector2(24, y - 12), "NHIỆM VỤ", UISkin.FS_SMALL, FRAME, HORIZONTAL_ALIGNMENT_LEFT, -1, true, 4)
	for objective in director.objectives:
		y += 30.0
		var done: bool = int(objective["value"]) >= int(objective["goal"])
		var mark: String = "✔" if done else "□"
		_text(Vector2(24, y), "%s %s  %d/%d" % [mark, String(objective["text"]), int(objective["value"]), int(objective["goal"])],
			UISkin.FS_BODY, Color(0.6, 1.0, 0.6) if done else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 600, false, 4)


func _draw_cut_in(w: float, h: float) -> void:
	var t: float = float(_cut_in["t"])
	var life: float = float(_cut_in["life"])
	var k: float = clampf(t / 0.12, 0.0, 1.0)
	var out: float = clampf((life - t) / 0.15, 0.0, 1.0)
	var band_h: float = 110.0 * k * out
	var y: float = h * 0.62
	_canvas.draw_rect(Rect2(0, y - band_h * 0.5, w, band_h), Color(0.08, 0.04, 0.02, 0.85))
	_canvas.draw_rect(Rect2(0, y - band_h * 0.5, w, 4), SPECIAL_COLOR)
	_canvas.draw_rect(Rect2(0, y + band_h * 0.5 - 4, w, 4), SPECIAL_COLOR)
	for i in range(14):
		var lx: float = fmod(float(i) * 97.0 + t * 2400.0, w + 200.0) - 100.0
		_canvas.draw_line(Vector2(lx, y - band_h * 0.4), Vector2(lx + 60.0, y - band_h * 0.4), Color(1, 0.9, 0.5, 0.5 * out), 2.0)
	if band_h > 40.0:
		var right: bool = int(_cut_in["index"]) == 1
		var slide: float = (1.0 - k) * 300.0 * (1.0 if right else -1.0)
		_text(Vector2(slide, y + 18), String(_cut_in["text"]), 55, Color(1.0, 0.9, 0.35, out),
			HORIZONTAL_ALIGNMENT_CENTER, w, true, 10)
