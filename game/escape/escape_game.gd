class_name EscapeGame
extends Node2D

## TẨU THOÁT – mini-game sau "Gọi tay trong": công an ập tới sới gà, nhân vật chính ôm gà chạy về nhà.
## Màn ngang dựng hoàn toàn bằng code (theo kiến trúc race_game.gd): nền parallax (escape_backdrop.gd), HUD
## (escape_hud.gd), ảnh nhân vật / công an / đồ vật sinh bởi tools/art/build_escape.py (escape_art.gd).
## Hai chặng (~60–75 giây):
##   1. CHẠY BỘ qua hẻm sau xóm + vườn: tự chạy sang phải; W/Space/J nhảy, S trượt/cúi (giữ để trượt lâu hơn),
##      giữ D chạy nước rút (tốn sức). Cầu khỉ: gõ A/D giữ thăng bằng. Sình làm chậm.
##   2. BƠI qua rạch (gà ngồi trên đầu cho khô): W/S lên xuống, D (hoặc J/Space) sải tay bứt tốc (tốn sức);
##      né lục bình, khúc dừa, lưới giăng, bầy vịt, ghe bán trái cây, đò ngang; dòng nước đẩy lệch.
## Tới bờ bên kia chạy vô nhà = thoát. Bị tóm khi công an đuổi kịp (thước khoảng cách cạn), té 3 lần liên tiếp
## (đụng vật cứng) hoặc hết giờ. Bị tóm ở chặng bơi được bơi lại từ bến (điểm lưu) một lần.
## Mô phỏng ở _physics_process (60 Hz cố định, _tick); chướng ngại sinh theo seed + độ khó, luôn có đường đi
## (validate_course kiểm tĩnh), mỗi chướng ngại báo trước ≥ 1 giây (dấu ◄ ở mép phải kèm ký hiệu nhảy/cúi).
## Dùng: var g := EscapeGame.new(); g.setup({"difficulty": 0.5, "seed": 7, "chicken": GameState.active_chicken()})
##       add_child(g); var r: Dictionary = await g.run(); g.queue_free()
## Kết quả: {escaped, caught, cancelled, time, stumbles, stage_reached} + phụ: reason, near_misses, retried.
## Test/headless: autopilot = true + autopilot_skill (0 = lơ mơ, 1 = hoàn hảo); press(action) với action =
## confirm/cancel/jump/slide/left/right/stroke; hold(&"sprint"|&"slide"|&"up"|&"down", bật/tắt);
## simulate(max_seconds) chạy đồng bộ tới khi xong (không cần đợi frame).

signal finished(result: Dictionary)
signal fx(kind: StringName, pos: Vector2)

const Art := preload("res://game/escape/escape_art.gd")
const Backdrop := preload("res://game/escape/escape_backdrop.gd")
const Hud := preload("res://game/escape/escape_hud.gd")
const EscSfx := preload("res://game/escape/escape_sfx.gd")
const Audio := preload("res://game/audio/audio_director.gd")

enum Phase { INTRO, COUNTDOWN, RUN, DIVE, SWIM, HOME, CAUGHT, RESULT, DONE }

# ------------------------------------------------------------------ hình học
const ZOOM: float = 3.0
const VIEW_CENTER_Y: float = 120.0
const GROUND_Y: float = 192.0
const PATH_TOP: float = 182.0
const LANES2: Array[float] = [150.0, 174.0, 198.0]
const SWIM_TOP: float = 144.0
const SWIM_BOTTOM: float = 204.0
const RUN_LEN: float = 4700.0
const SWIM_LEN: float = 2600.0
const BRIDGE_LEN: float = 300.0
const HOME_FOOT_Y: float = 158.0
const HOME_DOOR_DX: float = 118.0     # cửa nhà cách mép bờ (SWIM_LEN) bao nhiêu px
const TIME_LIMIT: float = 110.0

# ------------------------------------------------------------------ chặng chạy
const RUN_V: float = 130.0
const SPRINT_V: float = 182.0
const BRIDGE_V: float = 72.0
const MUD_K: float = 0.55
const ACCEL: float = 200.0
const JUMP_V: float = 285.0
const GRAVITY: float = 950.0
const SLIDE_TIME: float = 0.55
const SLIDE_MAX: float = 0.95
const STAND_H: float = 40.0
const SLIDE_H: float = 16.0
const HERO_HW: float = 7.0
const SLIDE_HW: float = 12.0
const STUMBLE_TIME: float = 0.5
const STUMBLE_KEEP: float = 0.4
const SPRINT_COST: float = 0.34
const STAMINA_REGEN: float = 0.2
const JUMP_BUFFER: float = 0.14
const FALL_TIME: float = 1.4
const MIN_SPACING_1: float = 210.0

## Chướng ngại chặng chạy: mode jump (thấp, phải nhảy) / duck (cao, phải trượt); w = nửa bề ngang va chạm;
## h = chiều cao đỉnh (jump) hoặc mép dưới (duck); hard = đụng vật cứng (tính chuỗi té liên tiếp).
const KINDS1: Dictionary = {
	&"fence": {"mode": &"jump", "w": 11.0, "h": 19.0, "hard": true},
	&"jar": {"mode": &"jump", "w": 9.0, "h": 21.0, "hard": true},
	&"dog": {"mode": &"jump", "w": 13.0, "h": 10.0, "hard": true},
	&"cage": {"mode": &"jump", "w": 11.0, "h": 16.0, "hard": true},
	&"basket": {"mode": &"jump", "w": 9.0, "h": 12.0, "hard": false},
	&"clothes": {"mode": &"duck", "w": 10.0, "h": 25.0, "hard": false},
	&"rack": {"mode": &"duck", "w": 25.0, "h": 26.0, "hard": true},
}
const HIT_TEXT: Dictionary = {
	&"fence": "Rầm! Hàng rào tre nhà ông Bảy!",
	&"jar": "Bể lu! Ướt nhẹp hết trơn!",
	&"dog": "Đạp trúng đuôi con Mực! Gâu gâu!",
	&"cage": "Lồng gà lật! Cục tác tùm lum!",
	&"basket": "Thúng trái cây đổ! Xin lỗi cô Sáu!",
	&"clothes": "Dính áo bà ba lên đầu! Hổng thấy đường!",
	&"rack": "Giàn khô cá sặc! Thơm phức luôn!",
	&"hyacinth": "Vướng lục bình!",
	&"log": "Cốp! Đụng khúc dừa!",
	&"ducks": "Cạp cạp! Bầy vịt nổi giận!",
	&"net": "Mắc lưới của chú Tư Cá!",
	&"vendor": "Đụng ghe bán trái cây! Cô Ba la quá trời!",
	&"ferry": "Đụng đò ngang! Xin lỗi bà con!",
}

# ------------------------------------------------------------------ chặng bơi
const SWIM_V: float = 86.0
const STROKE_V: float = 80.0
const STROKE_TIME: float = 0.6
const STROKE_COST: float = 0.24
const STROKE_REGEN: float = 0.26
const STROKE_COOL: float = 0.32
const SWIM_VY: float = 85.0
const HERO_DEPTH: float = 5.0
const SWIM_STUN: float = 0.5
const MIN_SPACING_2: float = 160.0
const FERRY_TRIGGER: float = 260.0
const FERRY_VY: float = 46.0
const FERRY_TOP_Y: float = 132.0
const FERRY_BOTTOM_Y: float = 218.0

## Chướng ngại chặng bơi (đứng yên theo x, chỉ nhấp nhô; đò ngang chạy theo y). depth = nửa bề sâu (y).
const KINDS2: Dictionary = {
	&"hyacinth": {"w": 16.0, "depth": 7.0, "hard": false, "slow": 0.5},
	&"log": {"w": 20.0, "depth": 5.0, "hard": true, "slow": 0.3},
	&"ducks": {"w": 14.0, "depth": 6.0, "hard": false, "slow": 0.55},
	&"net": {"w": 6.0, "depth": 20.0, "hard": true, "slow": 0.0},
	&"vendor": {"w": 34.0, "depth": 7.0, "hard": true, "slow": 0.3},
	&"ferry": {"w": 22.0, "depth": 6.0, "hard": true, "slow": 0.25},
}

# ------------------------------------------------------------------ công an
const GAP_MAX: float = 240.0
const CATCH_GAP: float = 16.0
const POLICE_SHOUTS: Array[String] = ["Đứng lại!!", "Tuýt tuýt! Đứng lại coi!", "Ê nhóc! Ôm gà đi đâu đó?!",
	"Chạy đâu cho thoát nè!", "Từ từ… chờ chú với!", "Ai cho đá gà ăn tiền hả?!"]
const CANOE_SHOUTS: Array[String] = ["Bơi giỏi dữ ha!", "Chèo lẹ lên chú Ba ơi!", "Ủa ghe này có lủng hông vậy?!",
	"Lên bờ nói chuyện đàng hoàng nè con!", "Tuýt tuýt tuýt!!"]

const COUNT_STEP: float = 0.7
const RESULT_MIN_TIME: float = 0.9
const RESULT_AUTO_TIME: float = 15.0
const FAR: float = 1.0e9


class Obstacle:
	var kind: StringName
	var stage: int = 1
	var x: float = 0.0
	var w: float = 8.0
	var h: float = 0.0
	var mode: StringName = &"jump"
	var hard: bool = true
	var slow: float = 0.5
	var y: float = 0.0           # chặng bơi: tâm theo y
	var y0: float = 0.0
	var depth: float = 6.0
	var vy: float = 0.0
	var y_end: float = 0.0
	var active: bool = false
	var done: bool = false
	var hit: bool = false
	var passed: bool = false
	var margin: float = FAR      # khe hở nhỏ nhất lúc vượt (sát nút)
	var anim: float = 0.0
	var node: Node2D


var difficulty: float = 0.0
var course_seed: int = 1
var chicken: Dictionary = {}
var autopilot: bool = false
var autopilot_skill: float = 1.0
var phase: int = Phase.INTRO
var result: Dictionary = {}
var course: Dictionary = {}

var _running: bool = false
var _stage: int = 1
var _variant: String = "noi"
var _chicken_name: String = "con gà"
var _obstacles: Array[Obstacle] = []
var _particles: Array[Dictionary] = []
var _queued: Array[StringName] = []
var _held: Dictionary = {}
var _auto_held: Dictionary = {}
var _phase_time: float = 0.0
var _play_time: float = 0.0
var _clock: float = 0.0
var _rng_fx := RandomNumberGenerator.new()
var _rng_auto := RandomNumberGenerator.new()
var _cancel_armed: float = 0.0

# Người chơi.
var _x: float = 0.0
var _alt: float = 0.0            # chặng chạy: độ cao so với mặt đất (≥ 0; < 0 = rớt xuống mương)
var _vy_up: float = 0.0
var _y: float = 174.0            # chặng bơi: vị trí y
var _v: float = RUN_V
var _stamina: float = 1.0
var _sprinting: bool = false
var _slide: float = 0.0
var _slide_total: float = 0.0
var _stumble: float = 0.0
var _stun: float = 0.0
var _stroke: float = 0.0
var _stroke_cool: float = 0.0
var _jump_buffer: float = 0.0
var _travel: float = 0.0
var _stumbles: int = 0
var _streak: int = 0
var _near: int = 0
var _on_bridge: bool = false
var _fallen: float = 0.0
var _balance: float = 0.0
var _balance_v: float = 0.0
var _bridge_told: bool = false
var _mud_told: bool = false
var _hurt_text: float = 0.0
var _home_door: float = 0.0      # 0 đóng → 1 mở
var _home_inside: bool = false
var _stage_reached: int = 1
var _retried: bool = false
var _caught_reason: String = ""
var _checkpoint_time: float = 0.0
var _checkpoint_stumbles: int = 0
var _dive_vx: float = 0.0

# Công an.
var _police_x: float = 0.0
var _police_y: float = 174.0
var _police_travel: float = 0.0
var _whistle_cool: float = 2.0
var _shout_cool: float = 3.0
var _confused: float = 0.0

# Tự chơi.
var _auto_decided: Dictionary = {}
var _auto_err: Dictionary = {}
var _auto_tap_cool: float = 0.0
var _auto_target_lane: int = 1

# Hình.
var _shake: float = 0.0
var _view := Vector2(427, 240)
var _cam_left: float = 0.0
var _wipe: float = 0.0
var _backdrop: Node2D
var _front: Node2D
var _ground: Node2D
var _actors: Node2D
var _fx_layer: Node2D
var _overlay: Node2D
var _hero_node: Node2D
var _police_node: Node2D
var _camera: Camera2D
var _prev_camera: Camera2D
var _hud: CanvasLayer
var _sfx: Node
var _esc: Node


## options: {"difficulty": 0..1, "seed": int, "chicken": Dictionary (GameState.active_chicken() hoặc {})}.
func setup(options: Dictionary = {}) -> void:
	difficulty = clampf(float(options.get("difficulty", 0.0)), 0.0, 1.0)
	course_seed = int(options.get("seed", 1))
	chicken = options.get("chicken", {}) if options.get("chicken", {}) is Dictionary else {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_variant = Art.variant_for(chicken)
	_chicken_name = String(chicken.get("name", "")).strip_edges()
	if _chicken_name == "":
		_chicken_name = "con gà"
	_rng_fx.seed = course_seed * 31 + 7
	_rng_auto.seed = course_seed * 13 + 5
	course = generate_course(course_seed, difficulty)
	var cam := get_viewport().get_camera_2d()
	_prev_camera = cam
	var sfx_script: Script = load("res://game/battle/sfx.gd")
	if sfx_script != null:
		_sfx = sfx_script.new()
		add_child(_sfx)
	_esc = EscSfx.new()
	add_child(_esc)

	_backdrop = Backdrop.new()
	add_child(_backdrop)
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_actors = Node2D.new()
	_actors.y_sort_enabled = true
	add_child(_actors)
	_fx_layer = Node2D.new()
	_fx_layer.z_index = 5
	_fx_layer.draw.connect(_draw_fx)
	add_child(_fx_layer)
	_front = Backdrop.new()
	_front.set("front", true)
	_front.z_index = 10
	add_child(_front)
	_overlay = Node2D.new()
	_overlay.z_index = 20
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(ZOOM, ZOOM)
	_camera.position = Vector2(0, VIEW_CENTER_Y)
	add_child(_camera)
	_camera.make_current()
	_hud = Hud.new()
	add_child(_hud)
	var who: String = String(GameState.player_name).strip_edges()
	_hud.set("hero_letter", who.substr(0, 1).to_upper() if who != "" else "T")

	_hero_node = Node2D.new()
	_hero_node.draw.connect(_draw_hero)
	_actors.add_child(_hero_node)
	_police_node = Node2D.new()
	_police_node.draw.connect(_draw_police)
	_actors.add_child(_police_node)
	_build_stage(1)
	_update_view(0.0)


func _exit_tree() -> void:
	# Trả camera cho cảnh trước (nếu còn) – mini-game không để lại gì.
	if is_instance_valid(_prev_camera) and _prev_camera.is_inside_tree() and _prev_camera != _camera:
		_prev_camera.make_current()


# ================================================================== sinh màn chơi (tĩnh, test được)

## Sinh toàn bộ màn theo seed + độ khó. Trả Dictionary thuần dữ liệu:
## {run: [{kind, x}], mud: [Vector2(x0, x1)], bridge: Vector2(x0, x1), swim: [{kind, x, lanes: [int], from_top}],
##  currents: [{x0, x1, push_x, push_y}], wind: [pha1, pha2], difficulty, seed}.
static func generate_course(p_seed: int, p_difficulty: float) -> Dictionary:
	var d: float = clampf(p_difficulty, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed * 7919 + 17
	var bx0: float = roundf(RUN_LEN * rng.randf_range(0.48, 0.56))
	var bridge := Vector2(bx0, bx0 + BRIDGE_LEN)
	var mud: Array[Vector2] = []
	var mud_count: int = 2 if d < 0.5 else 3
	var tries: int = 0
	while mud.size() < mud_count and tries < 50:
		tries += 1
		var mx: float = roundf(rng.randf_range(700.0, RUN_LEN - 500.0))
		var ml: float = roundf(rng.randf_range(60.0, 90.0 + 40.0 * d))
		var ok: bool = mx + ml < bridge.x - 200.0 or mx > bridge.y + 200.0
		for m in mud:
			if absf(m.x - mx) < 500.0:
				ok = false
		if ok:
			mud.append(Vector2(mx, mx + ml))
	mud.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var run: Array[Dictionary] = []
	var x: float = 560.0
	var duck_chance: float = 0.24 + 0.16 * d
	var jump_kinds: Array[StringName] = [&"fence", &"jar", &"dog", &"cage", &"basket"]
	var last_kind: StringName = &""
	while x < RUN_LEN - 360.0:
		if x > bridge.x - 170.0 and x < bridge.y + 170.0:
			x = bridge.y + 190.0
			continue
		var in_mud: bool = false
		for m in mud:
			if x > m.x - 70.0 and x < m.y + 70.0:
				x = m.y + 80.0
				in_mud = true
		if in_mud:
			continue
		var kind: StringName
		if rng.randf() < duck_chance:
			kind = &"clothes" if rng.randf() < 0.55 else &"rack"
		else:
			kind = jump_kinds[rng.randi_range(0, jump_kinds.size() - 1)]
		if kind == last_kind:
			kind = jump_kinds[(jump_kinds.find(kind) + 1) % jump_kinds.size()] if KINDS1[kind]["mode"] == &"jump" else (&"rack" if kind == &"clothes" else &"clothes")
		last_kind = kind
		run.append({"kind": kind, "x": x})
		x += roundf(lerpf(300.0, 215.0, d) + rng.randf_range(0.0, lerpf(140.0, 70.0, d)))
	var swim: Array[Dictionary] = []
	var sx: float = 480.0
	var ferries: int = 0
	var last_ferry: float = -1000.0
	var singles: Array[StringName] = [&"hyacinth", &"log", &"ducks"]
	while sx < SWIM_LEN - 380.0:
		var roll: float = rng.randf()
		var prev_x: float = float(swim.back()["x"]) if not swim.is_empty() else -1000.0
		if roll < 0.12 + 0.06 * d and ferries < 1 + int(round(2.0 * d)) and sx - prev_x >= 220.0 and sx - last_ferry > 600.0:
			var from_top: bool = rng.randf() < 0.5
			swim.append({"kind": &"ferry", "x": sx, "lanes": [0, 1, 2], "from_top": from_top})
			ferries += 1
			last_ferry = sx
			sx += 240.0
			continue
		if sx - last_ferry < 220.0:
			sx = last_ferry + 230.0
			continue
		if roll < 0.32:
			var top: int = rng.randi_range(0, 1)
			swim.append({"kind": &"net", "x": sx, "lanes": [top, top + 1], "from_top": false})
		elif roll < 0.42:
			swim.append({"kind": &"vendor", "x": sx, "lanes": [rng.randi_range(0, 2)], "from_top": false})
			sx += 60.0
		elif roll < 0.42 + 0.25 + 0.2 * d and d >= 0.25:
			var free: int = rng.randi_range(0, 2)
			var k: int = 0
			for lane in range(3):
				if lane == free:
					continue
				swim.append({"kind": singles[(rng.randi_range(0, 2) + k) % 3], "x": sx + float(k) * rng.randf_range(0.0, 12.0), "lanes": [lane], "from_top": false})
				k += 1
		else:
			swim.append({"kind": singles[rng.randi_range(0, 2)], "x": sx, "lanes": [rng.randi_range(0, 2)], "from_top": false})
		sx += roundf(lerpf(250.0, 175.0, d) + rng.randf_range(0.0, lerpf(120.0, 60.0, d)))
	var currents: Array[Dictionary] = []
	var cx: float = 400.0 + rng.randf_range(0.0, 200.0)
	while cx < SWIM_LEN - 500.0:
		var length: float = roundf(rng.randf_range(180.0, 260.0))
		var push_y: float = (14.0 + 16.0 * d) * (1.0 if rng.randf() < 0.5 else -1.0)
		currents.append({"x0": cx, "x1": cx + length, "push_x": -(12.0 + 10.0 * d), "push_y": push_y})
		cx += length + rng.randf_range(420.0, 700.0)
	return {
		"seed": p_seed, "difficulty": d, "run": run, "mud": mud, "bridge": bridge, "swim": swim,
		"currents": currents, "wind": [rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)],
	}


## Kiểm tĩnh: màn chơi giải được (chặng chạy: mỗi chướng ngại vượt được bằng đúng thao tác ở tốc độ thường lẫn
## nước rút, đủ khoảng cách để phản ứng, không đè cầu khỉ/sình; chặng bơi: mỗi cụm luôn chừa ≥ 1 làn trống, đổi
## làn kịp, đò ngang đứng riêng và rời làn xuất phát trước khi tới nơi). Trả danh sách lỗi (rỗng = hợp lệ).
static func validate_course(c: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var run: Array = c.get("run", [])
	var bridge: Vector2 = c.get("bridge", Vector2.ZERO)
	var mud: Array = c.get("mud", [])
	var air: float = 2.0 * JUMP_V / GRAVITY
	var prev_x: float = -FAR
	if run.is_empty():
		errors.append("run: không có chướng ngại")
	for item in run:
		var kind: StringName = item["kind"]
		var x: float = float(item["x"])
		var spec: Dictionary = KINDS1.get(kind, {})
		if spec.is_empty():
			errors.append("run: loại lạ %s" % kind)
			continue
		var w: float = float(spec["w"])
		var h: float = float(spec["h"])
		if x < 500.0:
			errors.append("run: %s ở x=%.0f quá sát vạch xuất phát (chưa kịp báo trước)" % [kind, x])
		if x - prev_x < MIN_SPACING_1:
			errors.append("run: %s ở x=%.0f cách chướng ngại trước %.0f px (< %.0f)" % [kind, x, x - prev_x, MIN_SPACING_1])
		prev_x = x
		if x + w > bridge.x - 120.0 and x - w < bridge.y + 120.0:
			errors.append("run: %s đè lên cầu khỉ" % kind)
		for m in mud:
			if x + w > (m as Vector2).x - 30.0 and x - w < (m as Vector2).y + 40.0:
				errors.append("run: %s nằm trong vũng sình" % kind)
		if spec["mode"] == &"jump":
			# Thời gian ở trên độ cao h phải đủ để lướt qua bề ngang chướng ngại ở tốc độ thường lẫn nước rút.
			var disc: float = JUMP_V * JUMP_V - 2.0 * GRAVITY * (h + 2.0)
			if disc <= 0.0:
				errors.append("run: %s cao %.0f – nhảy không qua" % [kind, h])
				continue
			var above: float = 2.0 * sqrt(disc) / GRAVITY
			var need: float = 2.0 * (w + HERO_HW)
			for speed in [RUN_V, SPRINT_V]:
				if above * float(speed) < need + 12.0:
					errors.append("run: %s quá rộng để nhảy qua ở %.0f px/s" % [kind, speed])
			if air * SPRINT_V > MIN_SPACING_1 - 40.0:
				errors.append("run: khoảng cách tối thiểu không đủ cho một cú nhảy + phản ứng")
		else:
			if h < SLIDE_H + 4.0 or h > STAND_H - 6.0:
				errors.append("run: %s cao %.0f – trượt không lọt / đứng vẫn lọt" % [kind, h])
			if SLIDE_MAX * RUN_V < 2.0 * (w + SLIDE_HW) + 16.0:
				errors.append("run: %s quá dài để trượt qua" % kind)
	var swim: Array = c.get("swim", [])
	if swim.is_empty():
		errors.append("swim: không có chướng ngại")
	# Gom cụm theo x (≤ 40 px) để kiểm làn trống.
	var groups: Array = []
	for item in swim:
		var x: float = float(item["x"])
		if groups.is_empty() or x - float(groups.back()["x1"]) > 40.0:
			groups.append({"x0": x, "x1": x, "lanes": {}, "kinds": []})
		var g: Dictionary = groups.back()
		g["x1"] = x
		(g["kinds"] as Array).append(item["kind"])
		if item["kind"] != &"ferry":
			for lane in item["lanes"]:
				(g["lanes"] as Dictionary)[int(lane)] = true
	var lane_change: float = (LANES2[2] - LANES2[0]) / (SWIM_VY - 30.0) * (SWIM_V + STROKE_V)
	for i in range(groups.size()):
		var g: Dictionary = groups[i]
		var kinds: Array = g["kinds"]
		if (g["lanes"] as Dictionary).size() >= 3:
			errors.append("swim: cụm x=%.0f chặn cả 3 làn" % float(g["x0"]))
		if i > 0:
			var gap: float = float(g["x0"]) - float(groups[i - 1]["x1"])
			if gap < MIN_SPACING_2:
				errors.append("swim: cụm x=%.0f sát cụm trước (%.0f px)" % [float(g["x0"]), gap])
			if gap < lane_change:
				errors.append("swim: cụm x=%.0f không kịp đổi làn" % float(g["x0"]))
			if kinds.has(&"ferry") or (groups[i - 1]["kinds"] as Array).has(&"ferry"):
				if gap < 200.0:
					errors.append("swim: đò ngang ở x≈%.0f không đứng riêng" % float(g["x0"]))
		if kinds.has(&"ferry") and kinds.size() > 1:
			errors.append("swim: đò ngang chung cụm với vật khác")
	# Đò ngang rời làn xuất phát trước khi người bơi nhanh nhất tới nơi.
	var clear_time: float = (LANES2[0] + float(KINDS2[&"ferry"]["depth"]) + HERO_DEPTH - FERRY_TOP_Y) / FERRY_VY
	if clear_time * (SWIM_V + STROKE_V) > FERRY_TRIGGER - 30.0:
		errors.append("swim: đò ngang chạy quá chậm so với tầm kích hoạt")
	for cur in c.get("currents", []):
		if absf(float(cur["push_y"])) >= SWIM_VY * 0.5:
			errors.append("swim: dòng nước đẩy quá mạnh")
	return errors


func _build_stage(stage: int) -> void:
	for o in _obstacles:
		if o.node != null:
			o.node.queue_free()
	_obstacles.clear()
	_stage = stage
	_backdrop.set("stage", stage)
	_front.set("stage", stage)
	if stage == 1:
		for item in course["run"]:
			var o := Obstacle.new()
			var spec: Dictionary = KINDS1[item["kind"]]
			o.kind = item["kind"]
			o.stage = 1
			o.x = float(item["x"])
			o.w = float(spec["w"])
			o.h = float(spec["h"])
			o.mode = spec["mode"]
			o.hard = bool(spec["hard"])
			o.anim = float(_obstacles.size()) * 0.37
			_add_node(o, GROUND_Y + (14.0 if o.mode == &"duck" else -1.0))
			_obstacles.append(o)
	else:
		for item in course["swim"]:
			var o := Obstacle.new()
			var spec: Dictionary = KINDS2[item["kind"]]
			o.kind = item["kind"]
			o.stage = 2
			o.x = float(item["x"])
			o.w = float(spec["w"])
			o.depth = float(spec["depth"])
			o.hard = bool(spec["hard"])
			o.slow = float(spec["slow"])
			o.anim = float(_obstacles.size()) * 0.41
			var lanes: Array = item["lanes"]
			if o.kind == &"ferry":
				o.y = FERRY_TOP_Y if bool(item["from_top"]) else FERRY_BOTTOM_Y
				o.y_end = FERRY_BOTTOM_Y if bool(item["from_top"]) else FERRY_TOP_Y
				o.vy = FERRY_VY * (1.0 if bool(item["from_top"]) else -1.0)
			elif lanes.size() == 2:
				o.y = (LANES2[int(lanes[0])] + LANES2[int(lanes[1])]) * 0.5
				o.depth = (LANES2[int(lanes[1])] - LANES2[int(lanes[0])]) * 0.5 + 8.0
			else:
				o.y = LANES2[int(lanes[0])]
			o.y0 = o.y
			_add_node(o, o.y)
			_obstacles.append(o)


func _add_node(o: Obstacle, sort_y: float) -> void:
	o.node = Node2D.new()
	o.node.position = Vector2(roundf(o.x), roundf(sort_y))
	o.node.draw.connect(_draw_obstacle.bind(o))
	_actors.add_child(o.node)


# ================================================================== chạy

func run() -> Dictionary:
	_running = true
	_enter_intro()
	var r: Dictionary = await finished
	return r


## Chạy đồng bộ (test): tự bấm qua bảng hướng dẫn nếu autopilot, mô phỏng từng bước 1/60 s tới khi xong.
## Hết max_seconds mà chưa xong: end_on_timeout = true thì kết thúc (cancelled, reason "timeout"), false thì để
## nguyên trạng thái (test chạy tiếp từng bước).
func simulate(max_seconds: float = 300.0, end_on_timeout: bool = true) -> Dictionary:
	if not _running:
		_running = true
		_enter_intro()
	var steps: int = int(max_seconds * 60.0)
	for i in range(steps):
		if not _running:
			break
		_tick(1.0 / 60.0)
	if _running and end_on_timeout:
		_end({"cancelled": true, "reason": "timeout"})
	return result


## Bơm một thao tác (test dùng trực tiếp; bàn phím cũng đi qua đây).
func press(action: StringName) -> void:
	if not _running:
		return
	if action == &"cancel":
		if phase == Phase.INTRO or _cancel_armed > 0.0:
			_end({"cancelled": true, "reason": "cancel"})
		elif phase == Phase.RESULT:
			_end(result)
		else:
			_cancel_armed = 2.0
			_hud.call("toast", "Nhấn Esc lần nữa để bỏ chạy (coi như bị bắt)", Color(1.0, 0.75, 0.5), 2.0)
		return
	match phase:
		Phase.INTRO:
			if action == &"confirm" or action == &"jump" or action == &"stroke":
				_enter_countdown()
		Phase.COUNTDOWN, Phase.RUN, Phase.SWIM, Phase.DIVE:
			if action == &"confirm":
				action = &"jump" if _stage == 1 else &"stroke"
			_queued.append(action)
		Phase.RESULT:
			if (action == &"confirm" or action == &"jump") and _phase_time >= RESULT_MIN_TIME:
				if bool(result.get("_retry_offer", false)):
					_retry_from_checkpoint()
				else:
					_end(result)


func hold(action: StringName, on: bool) -> void:
	_held[action] = on


func _unhandled_input(event: InputEvent) -> void:
	if not _running or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var action: StringName = &""
	match key.physical_keycode:
		KEY_W, KEY_UP:
			action = &"jump" if _stage == 1 else &"up"
		KEY_SPACE, KEY_J:
			action = &"jump" if _stage == 1 else &"stroke"
		KEY_S, KEY_DOWN:
			action = &"slide" if _stage == 1 else &"down"
		KEY_A, KEY_LEFT:
			action = &"left"
		KEY_D, KEY_RIGHT:
			action = &"right" if _stage == 1 else &"stroke"
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			action = &"confirm"
		KEY_ESCAPE:
			action = &"cancel"
	if action == &"":
		return
	get_viewport().set_input_as_handled()
	if phase == Phase.INTRO and action != &"cancel" and action != &"confirm" and action != &"jump" and action != &"stroke":
		return
	press(action)


func _is_held(action: StringName) -> bool:
	if autopilot:
		return bool(_auto_held.get(action, false))
	if bool(_held.get(action, false)):
		return true
	match action:
		&"sprint":
			return Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
		&"slide", &"down":
			return Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
		&"up":
			return Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	return false


func _start_gap() -> float:
	return lerpf(180.0, 140.0, difficulty)


func _enter_intro() -> void:
	phase = Phase.INTRO
	_phase_time = 0.0
	_x = 0.0
	_police_x = -_start_gap()
	Audio.music(&"battle", 0.6)
	Audio.ambience({&"village": 0.35, &"birds": 0.3, &"leaves": 0.3}, 1.0)
	_hud.call("show_intro", "CÔNG AN TỚI! – TẨU THOÁT!",
		"Ôm %s chạy về nhà cho lẹ! Công an đang rượt sau lưng!\n\n" % _chicken_name
		+ "CHẶNG 1 – CHẠY BỘ qua hẻm sau xóm:\n"
		+ "W / Space / J: nhảy (rào tre, lu nước, chó ngủ, lồng gà, thúng trái cây)\n"
		+ "S: trượt / cúi (dây phơi đồ, giàn khô) – giữ S để trượt xa hơn\n"
		+ "Giữ D: chạy nước rút (tốn sức) · Cầu khỉ: gõ A / D giữ thăng bằng\n\n"
		+ "CHẶNG 2 – NHẢY SÔNG BƠI về nhà (gà ngồi trên đầu cho khô):\n"
		+ "W / S: bơi lên / xuống · D (hoặc J): sải tay bứt tốc (tốn sức)\n\n"
		+ "Té 3 lần liên tiếp, công an đuổi kịp hoặc hết giờ là bị tóm!\n"
		+ "Dấu ◄ ở mép phải: ▲ = nhảy, ▼ = cúi.\n\n[E] Chạy!        [Esc] Thôi, đầu thú")
	_hud.call("set_help", "W/Space nhảy · S trượt · giữ D chạy nước rút · A/D thăng bằng · Esc bỏ chạy")


func _enter_countdown() -> void:
	phase = Phase.COUNTDOWN
	_phase_time = 0.0
	_hud.call("hide_intro")
	_hud.call("set_countdown", "3")
	_play(&"select", -4.0)
	_esc.call("play", &"whistle", -8.0)


func _enter_run() -> void:
	phase = Phase.RUN
	_phase_time = 0.0
	_v = RUN_V
	_hud.call("set_countdown", "CHẠY!", Color(0.6, 1.0, 0.5))
	_play(&"confirm", -2.0)
	_esc.call("play", &"whistle", -4.0)
	_esc.call("play", &"siren", -10.0)
	_hud.call("bubble", "Đứng lại!! Tuýt tuýt!", 1.6)
	fx.emit(&"go", Vector2(_x, GROUND_Y))


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_tick(delta)
	_update_view(delta)


func _tick(delta: float) -> void:
	_clock += delta
	_phase_time += delta
	_cancel_armed = maxf(_cancel_armed - delta, 0.0)
	_shake = maxf(_shake - delta, 0.0)
	_wipe = maxf(_wipe - delta * 1.6, 0.0)
	match phase:
		Phase.INTRO:
			if (autopilot and _phase_time > 0.4) or _phase_time > 30.0:
				_enter_countdown()
		Phase.COUNTDOWN:
			_queued.clear()
			var step: int = int(_phase_time / COUNT_STEP)
			var label: String = ["3", "2", "1"][mini(step, 2)]
			if step >= 3:
				_enter_run()
			elif String(_hud.call("countdown_text")) != label:
				_hud.call("set_countdown", label)
				_play(&"select", -4.0)
		Phase.RUN:
			if _phase_time > 0.7 and String(_hud.call("countdown_text")) != "":
				_hud.call("set_countdown", "")
			_play_time += delta
			_tick_run(delta)
		Phase.DIVE:
			_play_time += delta
			_tick_dive(delta)
		Phase.SWIM:
			_play_time += delta
			_tick_swim(delta)
		Phase.HOME:
			_tick_home(delta)
		Phase.CAUGHT:
			_tick_caught(delta)
		Phase.RESULT:
			if (autopilot and _phase_time > 1.2) or _phase_time > RESULT_AUTO_TIME:
				if bool(result.get("_retry_offer", false)) and autopilot:
					_retry_from_checkpoint()
				else:
					_end(result)
	_update_obstacles(delta)
	_update_particles(delta)
	if phase == Phase.RUN or phase == Phase.SWIM:
		if _play_time >= TIME_LIMIT:
			_get_caught("time")


# ================================================================== chặng 1: chạy bộ

func _tick_run(dt: float) -> void:
	var bridge: Vector2 = course["bridge"]
	if autopilot:
		_auto_run(dt)
	# Thao tác.
	while not _queued.is_empty():
		var action: StringName = _queued.pop_front()
		match action:
			&"jump":
				_jump_buffer = JUMP_BUFFER
			&"slide":
				if _on_bridge:
					_bridge_hint()
				elif _alt <= 0.0 and _stumble <= 0.0 and _fallen <= 0.0:
					if _slide <= 0.0:
						_slide = SLIDE_TIME
						_slide_total = 0.0
						_esc.call("play", &"skid", -10.0)
			&"left":
				_balance_tap(-1.0)
			&"right":
				_balance_tap(1.0)
	_jump_buffer = maxf(_jump_buffer - dt, 0.0)
	if _jump_buffer > 0.0 and _alt <= 0.0 and _fallen <= 0.0 and _stumble <= 0.0:
		if _on_bridge:
			_bridge_hint()
			_jump_buffer = 0.0
		else:
			_jump_buffer = 0.0
			_slide = 0.0
			_vy_up = JUMP_V
			_alt = 0.01
			_esc.call("play", &"hop", -8.0)
	# Trượt: giữ S để kéo dài tới SLIDE_MAX.
	if _slide > 0.0:
		_slide_total += dt
		if _is_held(&"slide") and _slide_total < SLIDE_MAX:
			_slide = maxf(_slide, dt * 1.5)
		_slide = maxf(_slide - dt, 0.0)
	# Sức + nước rút.
	var want_sprint: bool = _is_held(&"sprint") and not _on_bridge and _fallen <= 0.0 and _stumble <= 0.0
	if want_sprint and (_stamina > 0.08 or (_sprinting and _stamina > 0.0)):
		_sprinting = true
		_stamina = maxf(_stamina - SPRINT_COST * dt, 0.0)
	else:
		_sprinting = false
		_stamina = minf(_stamina + STAMINA_REGEN * dt, 1.0)
	# Cầu khỉ.
	var was_on_bridge: bool = _on_bridge
	_on_bridge = _x >= bridge.x and _x <= bridge.y and _alt <= 0.0
	if _on_bridge and not was_on_bridge and _fallen <= 0.0:
		_balance = 0.0
		_balance_v = 0.0
		_hud.call("toast", "CẦU KHỈ! Gõ A / D giữ thăng bằng!", Color(1.0, 0.9, 0.5), 1.6)
		_esc.call("play", &"hop", -10.0, 0.7)
	if _fallen > 0.0:
		_fallen -= dt
		_v = 0.0
		if _fallen <= 0.0:
			_alt = 0.0
			_balance = 0.0
			_balance_v = 0.0
			_hud.call("toast", "Leo lên cầu lại… ướt như chuột lột!", Color(0.8, 0.9, 1.0), 1.2)
	elif _on_bridge:
		_tick_balance(dt)
	# Tốc độ.
	if _fallen <= 0.0:
		var target: float = SPRINT_V if _sprinting else RUN_V
		if _on_bridge:
			target = BRIDGE_V
		elif _alt <= 0.0 and _in_mud(_x):
			target *= MUD_K
			if not _mud_told:
				_mud_told = true
				_hud.call("toast", "Sình lầy! Nhảy qua cho lẹ!", Color(0.85, 0.7, 0.45), 1.0)
			if _rng_fx.randf() < 12.0 * dt:
				_burst(Vector2(_x - 4.0, GROUND_Y - 1.0), Color(0.36, 0.26, 0.16), 2, 40.0, 0.4)
		if _stumble > 0.0:
			_stumble -= dt
			target = minf(target, RUN_V * 0.4)
		var rate: float = ACCEL if _v < target else ACCEL * 2.2
		_v = move_toward(_v, target, rate * dt)
	# Bay nhảy.
	if _alt > 0.0:
		_vy_up -= GRAVITY * dt
		_alt += _vy_up * dt
		if _alt <= 0.0:
			_alt = 0.0
			_vy_up = 0.0
			_play(&"land", -10.0)
			_burst(Vector2(_x, GROUND_Y - 1.0), Color(0.78, 0.66, 0.5), 4, 30.0, 0.35)
	_x += _v * dt
	_travel += _v * dt
	if _sprinting and _alt <= 0.0 and _rng_fx.randf() < 14.0 * dt:
		_particles.append({"p": Vector2(_x - 8.0, GROUND_Y - 2.0), "v": Vector2(_rng_fx.randf_range(-40.0, -10.0), _rng_fx.randf_range(-12.0, -2.0)),
			"life": 0.4, "max": 0.4, "c": Color(0.85, 0.75, 0.6, 0.6), "g": 0.0, "s": 2.0})
	_contacts_run()
	_police_run(dt)
	_check_gap()
	if phase == Phase.RUN and _x >= RUN_LEN:
		_enter_dive()


func _in_mud(x: float) -> bool:
	for m in course["mud"]:
		if x >= (m as Vector2).x and x <= (m as Vector2).y:
			return true
	return false


func _bridge_hint() -> void:
	if not _bridge_told:
		_bridge_told = true
		_hud.call("toast", "Trên cầu khỉ hổng nhảy được! Gõ A / D!", Color(1.0, 0.8, 0.5), 1.2)


## Thăng bằng: con lắc ngược (lệch càng nhiều càng ngã nhanh) + gió/rung cầu theo seed; gõ A/D đẩy ngược lại.
func _tick_balance(dt: float) -> void:
	var wind: Array = course["wind"]
	var amp: float = 0.35 + 0.45 * difficulty
	var k: float = 1.6 + 1.2 * difficulty
	var t: float = _play_time
	var push: float = amp * (sin(1.7 * t + float(wind[0])) + 0.6 * sin(3.1 * t + float(wind[1])))
	_balance_v += (k * _balance + push) * dt
	_balance_v *= maxf(1.0 - 1.2 * dt, 0.0)
	_balance += _balance_v * dt
	if absf(_balance) >= 1.0:
		_fall_off_bridge()


func _balance_tap(direction: float) -> void:
	if not _on_bridge or _fallen > 0.0:
		return
	# Gõ phía ngược lại với phía đang nghiêng: A kéo về trái, D kéo về phải.
	_balance_v += 0.6 * direction
	_esc.call("play", &"hop", -16.0, 1.4)


func _fall_off_bridge() -> void:
	_fallen = FALL_TIME
	_alt = -1.0
	_stumbles += 1
	_streak += 1
	_shake = 0.3
	_balance = 0.0
	_balance_v = 0.0
	Audio.sfx(&"splash", -4.0)
	_esc.call("play", &"big_splash", -8.0, 1.3)
	_burst(Vector2(_x, GROUND_Y + 10.0), Color(0.6, 0.72, 0.7), 14, 70.0, 0.7)
	_hud.call("toast", "Ùm! Té xuống mương!", Color(0.7, 0.9, 1.0), 1.2)
	fx.emit(&"fall", Vector2(_x, GROUND_Y))
	if _streak >= 3:
		_get_caught("stumbles")


## Va chạm chặng chạy: hộp người (cao 40, trượt 16) với hộp chướng ngại.
func _contacts_run() -> void:
	var sliding: bool = _slide > 0.0 and _alt <= 0.0
	var hw: float = SLIDE_HW if sliding else HERO_HW
	var top: float = _alt + (SLIDE_H if sliding else STAND_H)
	for o in _obstacles:
		if o.hit or o.passed:
			continue
		var dx: float = o.x - _x
		var reach: float = o.w + hw - 2.0
		if dx > reach:
			continue
		if dx >= -reach:
			if _fallen > 0.0:
				continue
			var collide: bool
			if o.mode == &"jump":
				collide = _alt < o.h - 1.0
				o.margin = minf(o.margin, _alt - o.h)
			else:
				collide = top > o.h + 1.0
				o.margin = minf(o.margin, o.h - top)
			if collide:
				_hit_run(o)
			continue
		o.passed = true
		_streak = 0
		if o.margin < 5.0:
			_near_miss(Vector2(o.x, GROUND_Y - 20.0))


func _hit_run(o: Obstacle) -> void:
	o.hit = true
	_stumbles += 1
	if o.hard:
		_streak += 1
	_stumble = STUMBLE_TIME
	_v = minf(_v, RUN_V) * STUMBLE_KEEP
	_slide = 0.0
	if _alt > 0.0:
		_vy_up = minf(_vy_up, 0.0)
	_shake = 0.25
	_hurt_text = 1.0
	var pos := Vector2(o.x, GROUND_Y - 10.0)
	match o.kind:
		&"jar":
			_burst(pos, Color(0.65, 0.8, 0.9), 14, 60.0, 0.6)
			_burst(pos, Color(0.6, 0.3, 0.2), 6, 50.0, 0.6)
			Audio.sfx(&"splash", -6.0)
		&"basket":
			_burst(pos, Color(0.95, 0.8, 0.2), 6, 55.0, 0.8)
			_burst(pos, Color(0.85, 0.2, 0.2), 5, 50.0, 0.8)
			_esc.call("play", &"plop", -6.0)
		&"cage":
			_burst(pos + Vector2(0, -6), Color(0.98, 0.96, 0.9), 10, 50.0, 0.9)
			Audio.sfx(&"rooster_crow", -12.0, 1.5)
		&"dog":
			_play(&"hit_light", -4.0, 0.7)
			_hud.call("bubble", "Gâu gâu gâu!!", 1.0)
		&"clothes", &"rack":
			_burst(pos + Vector2(0, -16), Color(0.9, 0.88, 0.8), 6, 30.0, 0.6)
			_esc.call("play", &"skid", -8.0, 0.8)
		_:
			_burst(pos, Color(0.7, 0.6, 0.4), 8, 50.0, 0.5)
	_esc.call("play", &"thud", -4.0)
	var text: String = String(HIT_TEXT.get(o.kind, "Ui da!"))
	if o.hard and _streak >= 2:
		text += "  (té %d lần liền!)" % _streak
	_hud.call("toast", text, Color(1.0, 0.6, 0.45), 1.2)
	fx.emit(&"stumble", pos)
	if _streak >= 3:
		_get_caught("stumbles")


func _near_miss(pos: Vector2) -> void:
	_near += 1
	_stamina = minf(_stamina + 0.12, 1.0)
	_hud.call("toast", ["Sát nút! +sức", "Hú hồn! +sức", "Lẹ dữ! +sức"][_near % 3], Color(0.7, 1.0, 0.6), 0.8)
	_esc.call("play", &"twinkle", -10.0)
	_burst(pos, Color(1.0, 0.95, 0.5), 6, 40.0, 0.5)
	fx.emit(&"near_miss", pos)


## Công an chạy bộ: tốc độ theo độ khó, chậm lại trên cầu khỉ / trong sình, kéo giãn nhẹ khi bị bỏ xa.
func _police_run(dt: float) -> void:
	var bridge: Vector2 = course["bridge"]
	var pv: float = 120.0 + 18.0 * difficulty
	var gap: float = _x - _police_x
	if gap > 200.0:
		pv *= 1.15
	if _police_x >= bridge.x and _police_x <= bridge.y:
		pv *= 0.55
	elif _in_mud(_police_x):
		pv *= 0.7
	if _phase_time < 0.6:
		pv *= _phase_time / 0.6
	_police_x += pv * dt
	_police_travel += pv * dt
	_police_x = maxf(_police_x, _x - GAP_MAX)
	_police_noise(dt, false)


func _police_noise(dt: float, canoe: bool) -> void:
	var gap: float = _gap()
	_whistle_cool -= dt
	if _whistle_cool <= 0.0:
		_whistle_cool = _rng_fx.randf_range(2.2, 4.0)
		var loud: float = clampf(1.0 - gap / GAP_MAX, 0.0, 1.0)
		_esc.call("play", &"whistle", -16.0 + 10.0 * loud, _rng_fx.randf_range(0.95, 1.05))
		if _rng_fx.randf() < 0.3:
			_esc.call("play", &"siren", -16.0 + 6.0 * loud)
	_shout_cool -= dt
	if _shout_cool <= 0.0 and gap < 170.0:
		_shout_cool = _rng_fx.randf_range(4.0, 7.0)
		var lines: Array[String] = CANOE_SHOUTS if canoe else POLICE_SHOUTS
		_hud.call("bubble", lines[_rng_fx.randi_range(0, lines.size() - 1)], 1.6)


func _gap() -> float:
	return _x - _police_x


func _check_gap() -> void:
	if _gap() <= CATCH_GAP:
		_get_caught("gap")


# ================================================================== nhảy sông (chuyển chặng)

func _enter_dive() -> void:
	phase = Phase.DIVE
	_phase_time = 0.0
	_slide = 0.0
	_sprinting = false
	_on_bridge = false
	_alt = maxf(_alt, 0.01)
	_vy_up = 230.0
	_dive_vx = maxf(_v, 120.0)
	_hud.call("show_banner", "NHẢY SÔNG!", Color(0.6, 0.9, 1.0), 1.8)
	_esc.call("play", &"hop", -4.0, 0.8)
	_stage_reached = 2


func _tick_dive(dt: float) -> void:
	if _alt > -26.0:
		_vy_up -= GRAVITY * dt
		_alt += _vy_up * dt
		_x += _dive_vx * dt
		if _alt <= -26.0:
			_alt = -26.0
			_esc.call("play", &"big_splash", -2.0)
			Audio.sfx(&"splash", -2.0)
			_burst(Vector2(_x, GROUND_Y + 24.0), Color(0.7, 0.85, 0.95), 24, 90.0, 0.9)
			_wipe = 1.0
			_shake = 0.3
	# Công an dừng ở mép bờ, ngơ ngác.
	_police_x = minf(_police_x + 120.0 * dt, RUN_LEN - 30.0)
	_police_travel += 120.0 * dt
	if _phase_time > 1.2:
		_start_swim(false)


func _start_swim(retry: bool) -> void:
	_build_stage(2)
	phase = Phase.SWIM
	_phase_time = 0.0
	_x = 0.0
	_y = LANES2[1]
	_alt = 0.0
	_v = SWIM_V
	_stroke = 0.0
	_stun = 0.0
	_streak = 0
	_stamina = maxf(_stamina, 0.6)
	_police_x = -maxf(lerpf(150.0, 115.0, difficulty), 90.0)
	_police_y = LANES2[0] - 6.0
	_auto_decided.clear()
	_auto_target_lane = 1
	_checkpoint_time = _play_time
	_checkpoint_stumbles = _stumbles
	_hud.call("set_help", "W/S bơi lên xuống · D (hoặc J/Space) sải tay bứt tốc · Esc bỏ chạy")
	Audio.ambience({&"river": 0.6, &"birds": 0.2}, 1.0)
	if retry:
		_hud.call("show_banner", "BƠI LẠI TỪ BẾN!", Color(0.6, 0.9, 1.0), 1.4)
	else:
		_hud.call("toast", "%s ngồi trên đầu cho khô nè!" % _chicken_name.capitalize(), Color(1.0, 0.9, 0.6), 1.6)
		_hud.call("bubble", "Ủa! Nhảy sông luôn hả?! Lấy ghe!", 1.8)
	_wipe = maxf(_wipe, 0.6)


# ================================================================== chặng 2: bơi

func _tick_swim(dt: float) -> void:
	if autopilot:
		_auto_swim(dt)
	while not _queued.is_empty():
		var action: StringName = _queued.pop_front()
		if action == &"stroke" or action == &"jump" or action == &"right":
			_try_stroke()
	_stroke_cool = maxf(_stroke_cool - dt, 0.0)
	_stamina = minf(_stamina + STROKE_REGEN * dt, 1.0)
	# Lên / xuống + dòng nước.
	var vy: float = 0.0
	if _stun <= 0.0:
		if _is_held(&"up"):
			vy -= SWIM_VY
		if _is_held(&"down"):
			vy += SWIM_VY
	var cur: Dictionary = _current_at(_x)
	if not cur.is_empty():
		vy += float(cur["push_y"])
	_y = clampf(_y + vy * dt, SWIM_TOP, SWIM_BOTTOM)
	# Tốc độ: nền + sải tay (giảm dần) − dòng ngược.
	var target: float = SWIM_V + STROKE_V * clampf(_stroke / STROKE_TIME, 0.0, 1.0)
	if not cur.is_empty():
		target += float(cur["push_x"])
	if _stun > 0.0:
		_stun -= dt
		target *= 0.35
	_stroke = maxf(_stroke - dt, 0.0)
	_v = move_toward(_v, target, (260.0 if _v < target else 200.0) * dt)
	_x += _v * dt
	_travel += _v * dt
	_contacts_swim()
	_police_swim(dt)
	_check_gap()
	if phase == Phase.SWIM and _x >= SWIM_LEN:
		_enter_home()


func _try_stroke() -> void:
	if _stun > 0.0 or _stroke_cool > 0.0:
		return
	if _stamina < STROKE_COST:
		_hud.call("toast", "Hết sức rồi! Thở cái đã…", Color(1.0, 0.75, 0.5), 0.6)
		_stroke_cool = 0.3
		return
	_stamina -= STROKE_COST
	_stroke = STROKE_TIME
	_stroke_cool = STROKE_COOL
	_esc.call("play", &"stroke", -6.0, _rng_fx.randf_range(0.9, 1.15))
	_burst(Vector2(_x + 8.0, _y - 2.0), Color(0.85, 0.95, 1.0), 5, 40.0, 0.4)


func _current_at(x: float) -> Dictionary:
	for cur in course["currents"]:
		if x >= float(cur["x0"]) and x <= float(cur["x1"]):
			return cur
	return {}


func _contacts_swim() -> void:
	for o in _obstacles:
		if o.hit or o.passed:
			continue
		var dx: float = o.x - _x
		var reach: float = o.w + 9.0
		if dx > reach:
			continue
		var dy: float = absf(o.y - _y)
		var lim: float = o.depth + HERO_DEPTH
		if dx >= -reach:
			o.margin = minf(o.margin, dy - lim)
			if dy <= lim and (o.kind != &"ferry" or o.active):
				_hit_swim(o)
			continue
		o.passed = true
		_streak = 0
		if o.margin < 6.0 and o.margin > -FAR * 0.5:
			_near_miss(Vector2(o.x, o.y - 12.0))


func _hit_swim(o: Obstacle) -> void:
	o.hit = true
	_stumbles += 1
	if o.hard:
		_streak += 1
	_stun = 0.9 if o.kind == &"net" else SWIM_STUN
	_v *= o.slow
	_stroke = 0.0
	_shake = 0.2
	_hurt_text = 1.0
	var pos := Vector2(_x + 10.0, _y - 4.0)
	_burst(pos, Color(0.8, 0.92, 1.0), 10, 50.0, 0.6)
	match o.kind:
		&"ducks":
			_burst(pos + Vector2(0, -6), Color(0.98, 0.96, 0.85), 8, 40.0, 0.8)
			_play(&"select", -6.0, 0.6)
		&"vendor":
			_hud.call("bubble", "Trời đất! Bể hết mớ xoài của tui!", 1.4)
			_esc.call("play", &"plop", -6.0)
		&"ferry":
			_hud.call("bubble", "Coi chừng nghen mậy!", 1.2)
		_:
			pass
	_esc.call("play", &"thud", -6.0, 1.2)
	Audio.sfx(&"splash", -8.0)
	var text: String = String(HIT_TEXT.get(o.kind, "Ui da!"))
	if o.hard and _streak >= 2:
		text += "  (té %d lần liền!)" % _streak
	_hud.call("toast", text, Color(1.0, 0.6, 0.45), 1.2)
	fx.emit(&"stumble", pos)
	if _streak >= 3:
		_get_caught("stumbles")


## Công an chèo xuồng: bám theo, kéo giãn nhẹ khi bị bỏ xa; xuồng trôi theo hàng của người bơi.
func _police_swim(dt: float) -> void:
	var pv: float = 86.0 + 10.0 * difficulty
	if _gap() > 190.0:
		pv *= 1.15
	if _phase_time < 1.0:
		pv *= _phase_time
	_police_x += pv * dt
	_police_travel += pv * dt
	_police_x = maxf(_police_x, _x - GAP_MAX)
	_police_y = move_toward(_police_y, _y - 4.0, 30.0 * dt)
	_police_noise(dt, true)


# ================================================================== về tới nhà / bị tóm / kết quả

func _enter_home() -> void:
	phase = Phase.HOME
	_phase_time = 0.0
	_home_door = 0.0
	_home_inside = false
	_hud.call("show_banner", "TỚI BỜ RỒI!", Color(1.0, 0.9, 0.5), 1.2)
	Audio.sfx(&"splash", -6.0)


func _tick_home(dt: float) -> void:
	var door := Vector2(SWIM_LEN + HOME_DOOR_DX, HOME_FOOT_Y)
	if not _home_inside:
		var to: Vector2 = door - Vector2(_x, _y)
		var step: float = 95.0 * dt
		if to.length() <= step:
			_x = door.x
			_y = door.y
			_home_inside = true
			_phase_time = 0.0
			_esc.call("play", &"slam", -2.0)
			_hud.call("show_banner", "VỀ TỚI NHÀ!", Color(1.0, 0.85, 0.3), 2.2)
			Audio.jingle(&"victory")
			Audio.sfx(&"rooster_crow", -6.0)
			for k in range(4):
				_burst(door + Vector2(_rng_fx.randf_range(-30.0, 30.0), -50.0), [Color(1.0, 0.85, 0.3), Color(0.9, 0.35, 0.3), Color(0.5, 0.85, 1.0)][k % 3], 8, 70.0, 1.2)
		else:
			_x += to.normalized().x * step
			_y += to.normalized().y * step
			_travel += step
			_home_door = clampf(1.0 - (to.length() - 20.0) / 60.0, 0.0, 1.0)
	else:
		_home_door = maxf(_home_door - dt * 6.0, 0.0)
	# Xuồng công an tới sát bờ thì đứng lại gãi đầu.
	_police_x = minf(_police_x + 70.0 * dt, SWIM_LEN - 50.0)
	_police_travel += 70.0 * dt
	_police_y = move_toward(_police_y, LANES2[1], 20.0 * dt)
	if _home_inside and _phase_time > 0.6 and _confused <= 0.0:
		_confused = 1.0
		_hud.call("bubble", "Ủa… thằng nhỏ đâu mất rồi ta?", 2.0)
	if _home_inside and _phase_time > 2.2:
		_finish_escape()


func _finish_escape() -> void:
	phase = Phase.RESULT
	_phase_time = 0.0
	result = {"escaped": true, "caught": false, "cancelled": false, "time": snappedf(_play_time, 0.01),
		"stumbles": _stumbles, "stage_reached": 2, "reason": "home", "near_misses": _near, "retried": _retried}
	var lines: PackedStringArray = []
	lines.append("Thời gian: %s   ·   Té: %d lần   ·   Sát nút: %d" % [_fmt(_play_time), _stumbles, _near])
	lines.append("")
	lines.append("Cửa đóng cái rầm. Công an còn đứng ngoài bến gãi đầu…")
	lines.append("%s an toàn, lông khô re!" % _chicken_name.capitalize())
	_hud.call("show_result", "THOÁT RỒI!", Color(1.0, 0.85, 0.3), "\n".join(lines), "[E] Vô nhà (giả bộ rửa chén…)")


func _get_caught(reason: String) -> void:
	if phase == Phase.CAUGHT or phase == Phase.RESULT or phase == Phase.DONE:
		return
	_caught_reason = reason
	phase = Phase.CAUGHT
	_phase_time = 0.0
	_slide = 0.0
	_sprinting = false
	_fallen = 0.0
	_stun = 0.0
	if _stage == 1:
		_alt = 0.0
	_police_x = _x - CATCH_GAP + 2.0
	_hud.call("show_banner", "BỊ TÓM RỒI!" if reason != "time" else "HẾT GIỜ!", Color(1.0, 0.5, 0.4), 2.2)
	_esc.call("play", &"whistle", -2.0)
	Audio.jingle(&"defeat")
	var lines: Array[String] = ["Đứng yên đó! Lập biên bản nghen con!", "Bắt được rồi nha! Ôm gà chạy chi cho mệt?",
		"Thôi nghen, về đồn uống trà nói chuyện!"]
	if reason == "time":
		lines = ["Công an bao vây cả xóm rồi con ơi!"]
	_hud.call("bubble", lines[_rng_fx.randi_range(0, lines.size() - 1)], 2.2)
	fx.emit(&"caught", Vector2(_x, GROUND_Y if _stage == 1 else _y))


func _tick_caught(_dt: float) -> void:
	if _phase_time < 2.4:
		return
	phase = Phase.RESULT
	_phase_time = 0.0
	var offer: bool = _stage == 2 and not _retried and _caught_reason != "time" and TIME_LIMIT - _play_time > 20.0
	result = {"escaped": false, "caught": true, "cancelled": false, "time": snappedf(_play_time, 0.01),
		"stumbles": _stumbles, "stage_reached": _stage_reached, "reason": _caught_reason, "near_misses": _near,
		"retried": _retried, "_retry_offer": offer}
	var why: String = {"gap": "Công an đuổi kịp rồi!", "stumbles": "Té ba lần liên tiếp – hổng chạy nổi nữa!",
		"time": "Hết giờ – công an bao vây cả xóm!"}.get(_caught_reason, "Bị tóm!")
	var lines: PackedStringArray = []
	lines.append(why)
	lines.append("")
	lines.append("Chặng: %s   ·   Thời gian: %s   ·   Té: %d lần" % ["bơi" if _stage_reached == 2 else "chạy", _fmt(_play_time), _stumbles])
	lines.append("Bị lập biên bản, %s bị giữ lại “làm tang chứng” một bữa…" % _chicken_name)
	var hint: String = "[E] Bơi lại từ bến (còn 1 lần)     [Esc] Chịu thua" if offer else "[E] Tiếp tục"
	_hud.call("show_result", "BỊ LẬP BIÊN BẢN…", Color(1.0, 0.55, 0.45), "\n".join(lines), hint)


func _retry_from_checkpoint() -> void:
	_retried = true
	_hud.call("hide_result")
	_hud.call("set_play_visible", true)
	_stumbles = _checkpoint_stumbles
	_start_swim(true)


static func _fmt(seconds: float) -> String:
	var s: float = maxf(seconds, 0.0)
	return "%d:%04.1f" % [int(s / 60.0), fmod(s, 60.0)]


func _end(r: Dictionary) -> void:
	if not _running:
		return
	_running = false
	phase = Phase.DONE
	var out: Dictionary = {
		"escaped": bool(r.get("escaped", false)), "caught": bool(r.get("caught", false)),
		"cancelled": bool(r.get("cancelled", false)), "time": float(r.get("time", snappedf(_play_time, 0.01))),
		"stumbles": int(r.get("stumbles", _stumbles)), "stage_reached": int(r.get("stage_reached", _stage_reached)),
		"reason": String(r.get("reason", "")), "near_misses": _near, "retried": _retried,
	}
	if out["cancelled"]:
		out["escaped"] = false
		out["caught"] = false
	result = out
	if _esc != null:
		_esc.call("stop_all")
	finished.emit.call_deferred(out)


# ================================================================== tự chơi (test)

func _auto_react(o: Obstacle) -> bool:
	var key: int = o.get_instance_id()
	if not _auto_decided.has(key):
		var s: float = clampf(autopilot_skill, 0.0, 1.0)
		_auto_decided[key] = _rng_auto.randf() < 0.1 + 0.9 * s
		_auto_err[key] = _rng_auto.randf_range(-1.0, 1.0) * (1.0 - s) * 0.16
	return bool(_auto_decided[key])


func _auto_run(dt: float) -> void:
	var s: float = clampf(autopilot_skill, 0.0, 1.0)
	_auto_held.clear()
	# Nước rút: giỏi thì chạy theo nhịp sức, tệ thì không.
	if s >= 0.6:
		_auto_held[&"sprint"] = _stamina > 0.35 or (_sprinting and _stamina > 0.05)
	elif s >= 0.3:
		_auto_held[&"sprint"] = _gap() < 70.0 and _stamina > 0.3
	# Cầu khỉ.
	if _on_bridge and _fallen <= 0.0:
		_auto_tap_cool -= dt
		var look: float = 0.25
		var predicted: float = _balance + _balance_v * look
		var thr: float = 0.18 + (1.0 - s) * 0.5
		if _auto_tap_cool <= 0.0 and absf(predicted) > thr:
			_balance_tap(-signf(predicted))
			_auto_tap_cool = 0.1 + (1.0 - s) * 0.35
		return
	# Chướng ngại phía trước gần nhất chưa qua.
	var next: Obstacle = null
	for o in _obstacles:
		if o.passed or o.hit or o.x + o.w + SLIDE_HW < _x:
			continue
		if next == null or o.x < next.x:
			next = o
	if next == null:
		return
	if not _auto_react(next):
		return
	var err: float = float(_auto_err.get(next.get_instance_id(), 0.0))
	var v: float = maxf(_v, 30.0)
	if next.mode == &"jump":
		var t_center: float = (next.x - _x) / v
		var half_air: float = JUMP_V / GRAVITY
		if _alt <= 0.0 and t_center <= half_air + err and t_center > 0.0:
			press(&"jump")
		if (next.x - next.w - _x) < v * (half_air + 0.25) and _alt <= 0.0:
			# Đừng chạy nước rút ngay trước cú nhảy (thời điểm đã tính theo tốc độ hiện tại).
			_auto_held[&"sprint"] = _sprinting
	else:
		var t_edge: float = (next.x - next.w - SLIDE_HW - _x) / v
		if _slide <= 0.0 and _alt <= 0.0 and t_edge <= 0.12 + err:
			press(&"slide")
		if _slide > 0.0 and _x < next.x + next.w + SLIDE_HW + 4.0:
			_auto_held[&"slide"] = true


func _auto_swim(_dt: float) -> void:
	var s: float = clampf(autopilot_skill, 0.0, 1.0)
	_auto_held.clear()
	var look: float = 70.0 + 200.0 * s
	# Làn mục tiêu: nếu làn hiện tại có vật cản trong tầm nhìn → chọn làn trống gần nhất.
	var cur_lane: int = _nearest_lane(_y)
	var threat: Obstacle = _swim_threat(_auto_target_lane, look)
	if threat != null and _auto_react(threat):
		var best: int = _auto_target_lane
		var best_score: float = -FAR
		for lane in range(3):
			var t2: Obstacle = _swim_threat(lane, look * 1.3)
			var dist: float = FAR if t2 == null else t2.x - _x
			var score: float = minf(dist, look * 2.0) - float(absi(lane - cur_lane)) * 25.0
			if score > best_score:
				best_score = score
				best = lane
		_auto_target_lane = best
	var ty: float = LANES2[_auto_target_lane]
	if _y < ty - 2.0:
		_auto_held[&"down"] = true
	elif _y > ty + 2.0:
		_auto_held[&"up"] = true
	# Sải tay.
	var want: bool = false
	if s >= 0.4:
		want = _stamina >= 0.5 or (_gap() < 70.0 and _stamina >= STROKE_COST)
	elif s > 0.1:
		want = _stamina >= 0.95
	if want and _stroke <= 0.05:
		_try_stroke()


func _nearest_lane(y: float) -> int:
	var best: int = 0
	for lane in range(3):
		if absf(LANES2[lane] - y) < absf(LANES2[best] - y):
			best = lane
	return best


## Vật cản đầu tiên chặn làn trong tầm look (tính cả đò ngang sẽ quét qua lúc mình tới).
func _swim_threat(lane: int, look: float) -> Obstacle:
	var ly: float = LANES2[lane]
	var found: Obstacle = null
	for o in _obstacles:
		if o.passed or o.hit:
			continue
		var dx: float = o.x - _x
		if dx < -(o.w + 9.0) or dx > look:
			continue
		var lo: float = o.y - o.depth - HERO_DEPTH - 3.0
		var hi: float = o.y + o.depth + HERO_DEPTH + 3.0
		if o.kind == &"ferry":
			var t: float = maxf(dx, 0.0) / maxf(_v, 60.0)
			var y2: float = move_toward(o.y, o.y_end, FERRY_VY * t) if o.active or dx < FERRY_TRIGGER + 40.0 else o.y
			lo = minf(o.y, y2) - o.depth - HERO_DEPTH - 3.0
			hi = maxf(o.y, y2) + o.depth + HERO_DEPTH + 3.0
		if ly < lo or ly > hi:
			continue
		if found == null or o.x < found.x:
			found = o
	return found


# ================================================================== vật thể động

func _update_obstacles(dt: float) -> void:
	for o in _obstacles:
		o.anim += dt
		if o.kind == &"ferry" and not o.done:
			if not o.active and (o.x - _x) <= FERRY_TRIGGER and phase == Phase.SWIM:
				o.active = true
				_esc.call("play", &"hop", -14.0, 0.6)
			if o.active:
				o.y = move_toward(o.y, o.y_end, FERRY_VY * dt)
				if is_equal_approx(o.y, o.y_end):
					o.done = true
			if o.node != null:
				o.node.position.y = roundf(o.y)
	_hurt_text = maxf(_hurt_text - dt, 0.0)


# ================================================================== âm thanh

func _play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _sfx != null:
		_sfx.call("play", sound, volume_db, pitch)


# ================================================================== hình

func _update_view(delta: float) -> void:
	var vis: Vector2 = get_viewport_rect().size
	_view = vis / ZOOM
	var shake := Vector2.ZERO
	if _shake > 0.0:
		shake = Vector2(_rng_fx.randi_range(-1, 1), _rng_fx.randi_range(-1, 1))
	var follow: float = _x
	if _stage == 2 and (phase == Phase.HOME or _home_inside):
		follow = minf(_x, SWIM_LEN + HOME_DOOR_DX - _view.x * 0.12)
	var center := Vector2(roundf(follow + _view.x * 0.15), VIEW_CENTER_Y)
	_camera.position = center + shake
	_cam_left = roundf(center.x - _view.x * 0.5)
	for layer in [_backdrop, _front]:
		layer.set("cam_left", _cam_left)
		layer.set("view_w", _view.x)
		layer.set("view_top", center.y - _view.y * 0.5)
		layer.set("view_h", _view.y)
		layer.set("time", _clock)
		(layer as CanvasItem).queue_redraw()
	var hero_y: float = GROUND_Y if _stage == 1 else _y
	if _home_inside:
		hero_y = HOME_FOOT_Y - 2.0
	_hero_node.position = Vector2(roundf(_x), roundf(hero_y))
	_hero_node.queue_redraw()
	_police_node.position = Vector2(roundf(_police_x), roundf(GROUND_Y if _stage == 1 else _police_y))
	_police_node.queue_redraw()
	for o in _obstacles:
		if o.node != null and absf(o.x - _x) < _view.x + 80.0:
			o.node.queue_redraw()
	_ground.queue_redraw()
	_fx_layer.queue_redraw()
	_overlay.queue_redraw()
	# HUD.
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var length: float = RUN_LEN if _stage == 1 else SWIM_LEN
	_hud.set("stage", _stage)
	_hud.set("progress", clampf(_x / length, 0.0, 1.0))
	_hud.set("police_progress", clampf(_police_x / length, 0.0, 1.0))
	_hud.set("gap_ratio", clampf((_gap() - CATCH_GAP) / (GAP_MAX - CATCH_GAP), 0.0, 1.0))
	_hud.set("stamina", _stamina)
	_hud.set("sprinting", _sprinting)
	_hud.set("time_left", TIME_LIMIT - _play_time)
	_hud.set("streak", _streak)
	_hud.set("balance_on", _on_bridge and _fallen <= 0.0 and phase == Phase.RUN)
	_hud.set("balance", _balance)
	var close: float = clampf(1.0 - (_gap() - CATCH_GAP) / 150.0, 0.0, 1.0)
	_hud.set("flash", close if (phase == Phase.RUN or phase == Phase.SWIM) else (1.0 if phase == Phase.CAUGHT else 0.0))
	var speaker: Vector2 = Vector2(_police_x, (GROUND_Y if _stage == 1 else _police_y) - 56.0)
	if _home_inside:
		speaker = Vector2(_police_x, _police_y - 50.0)
	_hud.call("place_bubble", canvas * speaker)
	if _wipe > 0.0:
		_overlay.queue_redraw()


# ------------------------------------------------------------------ người chơi

func _draw_hero() -> void:
	var node: Node2D = _hero_node
	if _home_inside:
		return
	var frame: String = "stand"
	var foot := Vector2.ZERO
	if _stage == 1 or phase == Phase.DIVE:
		foot = Vector2(0, -roundf(_alt))
		if phase == Phase.DIVE:
			frame = "dive" if _alt > -20.0 else "swim2"
		elif phase == Phase.CAUGHT or phase == Phase.RESULT:
			frame = "stand"
		elif phase == Phase.INTRO or phase == Phase.COUNTDOWN:
			frame = "stand"
		elif _fallen > 0.0:
			frame = "fall"
			var sink: float = minf((FALL_TIME - _fallen) * 60.0, 18.0)
			if _fallen < 0.5:
				sink = 18.0 * (_fallen / 0.5)
			foot = Vector2(0, roundf(sink))
		elif _stumble > STUMBLE_TIME * 0.4:
			frame = "stumble"
		elif _alt > 0.0:
			frame = "jump" if _vy_up > 0.0 else "fall"
		elif _slide > 0.0:
			frame = "slide"
		else:
			frame = "run%d" % (int(_travel / 11.0) % 4)
		if _alt >= 0.0 and phase != Phase.DIVE and _fallen <= 0.0:
			Art.ellipse(node, Vector2(0, 0), 9.0 if _alt < 10.0 else 6.0, 1.0, Color(0, 0, 0, 0.25))
		Art.hero_at(node, Art.hero(_variant, frame), foot)
		if _on_bridge and _fallen <= 0.0:
			# Hai tay dang ra giữ thăng bằng, nghiêng theo kim.
			var lean: float = roundf(_balance * 4.0)
			node.draw_line(Vector2(-12, -30 + lean), Vector2(-2, -27), Color(0.75, 0.16, 0.22), 2.0)
			node.draw_line(Vector2(2, -27), Vector2(12, -30 - lean), Color(0.75, 0.16, 0.22), 2.0)
	else:
		if phase == Phase.HOME:
			frame = "run%d" % (int(_travel / 11.0) % 4)
			Art.ellipse(node, Vector2(0, 0), 9.0, 1.0, Color(0, 0, 0, 0.25))
			Art.hero_at(node, Art.hero(_variant, frame), Vector2.ZERO)
			return
		var cycle: float = 0.09 if _stroke > 0.0 else 0.16
		frame = "swim%d" % (int(_clock / cycle) % 4)
		if _stun > 0.0:
			frame = "swim2"
		var bob: float = roundf(sin(_clock * 6.0) * 1.0)
		var wobble: float = roundf(sin(_clock * 40.0) * 2.0) if _stun > 0.0 else 0.0
		# Thân dưới nước: bóng tối + chân đạp nước phía sau.
		Art.ellipse(node, Vector2(-2, 3), 11.0, 2.0, Color(0.2, 0.3, 0.32, 0.45))
		var kick: float = float(int(_clock * 10.0) % 2)
		node.draw_rect(Rect2(-16 - kick * 2.0, -1, 4, 1), Color(0.9, 0.96, 1.0, 0.8))
		node.draw_rect(Rect2(-20 + kick * 2.0, 0, 3, 1), Color(0.9, 0.96, 1.0, 0.6))
		Art.hero_at(node, Art.hero(_variant, frame), Vector2(wobble, bob))
		# Gợn nước quanh cổ.
		node.draw_rect(Rect2(-12, bob, 24, 1), Color(0.85, 0.94, 0.97, 0.75))
		node.draw_rect(Rect2(-9 + float(int(_clock * 8.0) % 3), bob + 2, 18, 1), Color(0.85, 0.94, 0.97, 0.4))


# ------------------------------------------------------------------ công an

func _draw_police() -> void:
	var node: Node2D = _police_node
	if _stage == 1:
		var caught: bool = phase == Phase.CAUGHT or (phase == Phase.RESULT and bool(result.get("caught", false)))
		var stopped: bool = phase == Phase.DIVE and _police_x >= RUN_LEN - 31.0
		for k in range(2):
			var off := Vector2(-20.0 * float(k), 0.0)
			var cop_x: float = _police_x + off.x
			var frame: int = int((_police_travel + float(k) * 9.0) / 10.0) % 4
			var hop: float = _cop_hop(cop_x)
			var t: Texture2D = Art.police(k, frame)
			if caught:
				t = Art.police(k, 7 if k == 0 else 5)
				hop = 0.0
			elif stopped or phase == Phase.INTRO or phase == Phase.COUNTDOWN:
				t = Art.police(k, 6 if stopped else 4)
				hop = 0.0
			Art.ellipse(node, off, 8.0, 1.0, Color(0, 0, 0, 0.22))
			Art.police_at(node, t, off + Vector2(0, -hop))
		return
	# Chặng bơi: hai chú chèo xuồng ba lá.
	var bob: float = roundf(sin(_clock * 3.0) * 1.0)
	var paddle: float = sin(_police_travel / 9.0)
	var stopped2: bool = _home_inside
	for k in range(2):
		var sx: float = -14.0 + 20.0 * float(k)
		var t2 := Art.police(k, 6 if stopped2 else 1) as AtlasTexture
		if t2 != null:
			# Chỉ vẽ nửa trên (tới thắt lưng); mép cắt nằm ngay mạn xuồng.
			var cut: float = 34.0 if k == 0 else 38.0
			var src := Rect2(t2.region.position, Vector2(t2.region.size.x, cut))
			var dest := Rect2(Vector2(sx - 16.0, -4.0 + bob - cut), Vector2(t2.region.size.x, cut))
			node.draw_texture_rect_region(t2.atlas, dest, src)
		if not stopped2:
			var px: float = sx + 6.0 + paddle * 6.0
			node.draw_line(Vector2(sx + 4.0, -14.0 + bob), Vector2(px, 6.0 + bob), Color(0.5, 0.34, 0.18), 1.0)
			node.draw_rect(Rect2(px - 1.0, 4.0 + bob, 3.0, 4.0), Color(0.5, 0.34, 0.18))
	var hull := Color(0.32, 0.22, 0.15)
	node.draw_colored_polygon(PackedVector2Array([Vector2(-34, -4 + bob), Vector2(30, -4 + bob), Vector2(24, 3 + bob), Vector2(-28, 3 + bob)]), hull)
	node.draw_rect(Rect2(-34, -5 + bob, 64, 2), Color(0.55, 0.38, 0.22))
	node.draw_rect(Rect2(-28, 4 + bob, 52, 1), Color(0.85, 0.94, 0.97, 0.6))


func _cop_hop(cop_x: float) -> float:
	for o in _obstacles:
		if o.mode != &"jump":
			continue
		var d: float = cop_x - o.x
		if absf(d) < 22.0:
			return roundf(sin((d + 22.0) / 44.0 * PI) * 14.0)
	return 0.0


# ------------------------------------------------------------------ chướng ngại

func _draw_obstacle(o: Obstacle) -> void:
	var n: Node2D = o.node
	if o.stage == 1:
		var base := Vector2(0, -(n.position.y - GROUND_Y))   # chân chướng ngại = mặt đất
		match o.kind:
			&"fence":
				Art.stand(n, Art.prop("fence"), base + Vector2(0, 1))
			&"jar":
				Art.stand(n, Art.prop("jar"), base + Vector2(0, 1))
				if o.hit:
					n.draw_rect(Rect2(base + Vector2(-12, -2), Vector2(24, 2)), Color(0.6, 0.75, 0.85, 0.7))
			&"dog":
				var hop: float = 0.0
				if o.hit and o.anim < 99.0:
					hop = roundf(absf(sin(_clock * 10.0)) * 4.0)
				Art.stand(n, Art.prop("dog_sleep", int(o.anim * 1.2) % 2), base + Vector2(0, 1 - hop), o.hit)
				if not o.hit and int(o.anim * 1.2) % 2 == 0:
					n.draw_string(DialogBox.make_font(true), base + Vector2(6, -14), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.8))
			&"cage":
				_draw_cage(n, base, o)
			&"basket":
				_draw_basket(n, base, o)
			&"clothes":
				_draw_clothesline(n, base, o)
			&"rack":
				var rack: Texture2D = Art.prop("rack")
				var lift: float = 16.0
				if rack != null:
					var size: Vector2 = rack.get_size()
					var left: float = base.x - floorf(size.x * 0.5)
					for px in [left + 1.0, left + size.x - 4.0]:
						n.draw_rect(Rect2(px, base.y - lift - 1.0, 3.0, lift + 1.0), Color(0.42, 0.28, 0.16))
					Art.stand(n, rack, base + Vector2(0, -lift))
		return
	var bob: float = roundf(sin(o.anim * 2.2) * 1.0)
	match o.kind:
		&"hyacinth":
			for k in range(3):
				var name_k: String = ["hyacinth_a", "hyacinth_b", "hyacinth_c"][k]
				Art.stand(n, Art.prop(name_k, int(o.anim * 2.0 + float(k)) % 2), Vector2(-14 + k * 13, 4 + bob + (k % 2) * 2))
		&"log":
			_draw_log(n, bob)
		&"ducks":
			for k in range(3):
				var fr: int = int(o.anim * 6.0 + float(k)) % 4
				Art.stand(n, Art.prop("ducks", fr), Vector2(-12 + k * 11, 3 + bob + (k % 2)), true)
		&"net":
			_draw_net(n, o, bob)
		&"vendor":
			Art.stand(n, Art.prop("fruit_boat"), Vector2(0, 8 + bob))
			_hat_person(n, Vector2(-14, -2 + bob), Color(0.85, 0.3, 0.45))
		&"ferry":
			_draw_ferry(n, o, bob)
	# Gợn nước quanh vật.
	n.draw_rect(Rect2(-o.w - 2.0, 6 + bob, o.w * 2.0 + 4.0, 1), Color(0.85, 0.94, 0.97, 0.5))


func _draw_cage(n: Node2D, base: Vector2, o: Obstacle) -> void:
	# Lồng gà tre (bội) hình chuông, có gà mái bên trong.
	var hen: Texture2D = Art.prop("hens", int(o.anim * 3.0) % 4)
	if not o.hit:
		Art.stand(n, hen, base + Vector2(0, 0))
	var bamboo := Color(0.82, 0.68, 0.36)
	var dark := Color(0.55, 0.42, 0.2)
	for k in range(-5, 6):
		var x: float = float(k) * 2.0
		var hh: float = 16.0 - absf(float(k)) * absf(float(k)) * 0.22
		n.draw_rect(Rect2(base.x + x, base.y - hh, 1.0, hh), bamboo if k % 2 == 0 else dark)
	n.draw_rect(Rect2(base.x - 11.0, base.y - 2.0, 23.0, 2.0), dark)
	n.draw_rect(Rect2(base.x - 9.0, base.y - 9.0, 19.0, 1.0), dark)
	n.draw_rect(Rect2(base.x - 2.0, base.y - 18.0, 5.0, 2.0), dark)
	if o.hit:
		Art.stand(n, hen, base + Vector2(14, -6 - roundf(absf(sin(_clock * 8.0)) * 6.0)), true)


func _draw_basket(n: Node2D, base: Vector2, o: Obstacle) -> void:
	# Thúng trái cây: xoài, chôm chôm, mận.
	var rim := Color(0.62, 0.44, 0.22)
	n.draw_rect(Rect2(base.x - 10.0, base.y - 7.0, 20.0, 7.0), Color(0.75, 0.56, 0.3))
	for k in range(0, 20, 3):
		n.draw_rect(Rect2(base.x - 10.0 + float(k), base.y - 7.0, 1.0, 7.0), rim)
	n.draw_rect(Rect2(base.x - 11.0, base.y - 8.0, 22.0, 2.0), rim)
	if not o.hit:
		var fruits: Array = [[-7, Color(0.95, 0.8, 0.2)], [-3, Color(0.85, 0.15, 0.2)], [1, Color(0.95, 0.75, 0.15)],
			[5, Color(0.6, 0.15, 0.3)], [-5, Color(0.85, 0.15, 0.2)], [3, Color(0.95, 0.8, 0.2)]]
		for k in range(fruits.size()):
			var f: Array = fruits[k]
			var yy: float = base.y - 11.0 - (3.0 if k >= 4 else 0.0)
			n.draw_rect(Rect2(base.x + float(f[0]), yy, 4.0, 3.0), f[1])
			n.draw_rect(Rect2(base.x + float(f[0]), yy, 4.0, 1.0), (f[1] as Color).lightened(0.3))


func _draw_clothesline(n: Node2D, base: Vector2, o: Obstacle) -> void:
	# Dây phơi băng ngang hẻm: cọc sau (cao hơn, lùi vô) + cọc trước, áo bà ba, quần, khăn rằn.
	var pole := Color(0.55, 0.4, 0.22)
	var back := base + Vector2(8, -14)
	var front := base + Vector2(-8, 0)
	n.draw_rect(Rect2(back.x, back.y - 42.0, 2.0, 42.0), pole.darkened(0.2))
	var line_a := back + Vector2(1, -40)
	var line_b := front + Vector2(1, -44)
	n.draw_line(line_a, line_b, Color(0.9, 0.9, 0.85), 1.0)
	var swing: float = roundf(sin(_clock * 3.0 + o.x) * 1.0)
	var top_y: float = base.y - 42.0
	var drop: float = 42.0 - o.h          # áo rủ xuống tới mép dưới h
	if o.hit:
		drop -= 6.0
	# Áo bà ba (nâu), quần đen, khăn rằn ca-rô.
	n.draw_rect(Rect2(base.x - 5.0 + swing, top_y, 9.0, drop), Color(0.62, 0.36, 0.24))
	n.draw_rect(Rect2(base.x - 7.0 + swing, top_y, 13.0, 4.0), Color(0.62, 0.36, 0.24))
	n.draw_rect(Rect2(base.x - 1.0 + swing, top_y + 2.0, 1.0, drop - 3.0), Color(0.45, 0.25, 0.16))
	n.draw_rect(Rect2(base.x + 5.0 - swing, top_y + 1.0, 5.0, drop - 3.0), Color(0.16, 0.14, 0.18))
	for k in range(4):
		var c: Color = Color(0.9, 0.9, 0.85) if k % 2 == 0 else Color(0.2, 0.22, 0.3)
		n.draw_rect(Rect2(base.x - 11.0, top_y + 1.0 + float(k) * 3.0, 5.0, 3.0), c)
	n.draw_rect(Rect2(front.x, front.y - 46.0, 2.0, 46.0), pole)


func _draw_log(n: Node2D, bob: float) -> void:
	var c := Color(0.5, 0.36, 0.22)
	n.draw_rect(Rect2(-20, -3 + bob, 40, 7), c)
	n.draw_rect(Rect2(-20, -3 + bob, 40, 1), c.lightened(0.25))
	n.draw_rect(Rect2(-20, 3 + bob, 40, 1), c.darkened(0.35))
	for k in range(-16, 18, 6):
		n.draw_rect(Rect2(float(k), -2 + bob, 1, 5), c.darkened(0.2))
	n.draw_rect(Rect2(18, -3 + bob, 3, 7), Color(0.78, 0.62, 0.42))
	n.draw_rect(Rect2(19, -1 + bob, 1, 2), c.darkened(0.3))


func _draw_net(n: Node2D, o: Obstacle, bob: float) -> void:
	# Lưới giăng giữa hai cọc tre: cọc ở mép trên và mép dưới của hai làn, phao cam trên dây.
	var half: float = o.depth - 8.0
	var top := Vector2(0, -half - 6.0)
	var bottom := Vector2(0, half + 2.0)
	var pole := Color(0.78, 0.66, 0.36)
	n.draw_rect(Rect2(top.x - 1.0, top.y - 22.0, 2.0, 24.0), pole)
	n.draw_rect(Rect2(bottom.x - 1.0, bottom.y - 22.0, 2.0, 24.0), pole)
	var mesh := Color(0.85, 0.85, 0.8, 0.65)
	for k in range(6):
		var t: float = float(k) / 5.0
		var p := top.lerp(bottom, t)
		n.draw_line(p + Vector2(-3, -12), p + Vector2(3, -2), mesh, 1.0)
		n.draw_line(p + Vector2(3, -12), p + Vector2(-3, -2), mesh, 1.0)
	n.draw_line(top + Vector2(0, -14), bottom + Vector2(0, -14), Color(0.9, 0.9, 0.85), 1.0)
	for k in range(5):
		var p2 := top.lerp(bottom, float(k) / 4.0) + Vector2(0, -15 + bob)
		n.draw_rect(Rect2(p2.x - 1.0, p2.y, 3.0, 2.0), Color(1.0, 0.55, 0.15))


func _draw_ferry(n: Node2D, o: Obstacle, bob: float) -> void:
	# Đò ngang (xuồng ba lá): người chèo đội nón lá + bà cụ ôm giỏ.
	var hull := Color(0.36, 0.25, 0.16)
	n.draw_colored_polygon(PackedVector2Array([Vector2(-24, -5 + bob), Vector2(24, -5 + bob), Vector2(19, 2 + bob), Vector2(-19, 2 + bob)]), hull)
	n.draw_rect(Rect2(-24, -6 + bob, 48, 2), Color(0.6, 0.42, 0.24))
	_hat_person(n, Vector2(-12, -5 + bob), Color(0.3, 0.45, 0.7))
	_hat_person(n, Vector2(8, -5 + bob), Color(0.75, 0.3, 0.3))
	n.draw_rect(Rect2(11, -11 + bob, 5, 4), Color(0.75, 0.6, 0.3))
	var oar: float = sin(o.anim * 5.0) * 4.0
	n.draw_line(Vector2(-10, -14 + bob), Vector2(-18 + oar, 3 + bob), Color(0.5, 0.36, 0.2), 1.0)


func _hat_person(n: Node2D, foot: Vector2, shirt: Color) -> void:
	n.draw_rect(Rect2(foot.x - 2.0, foot.y - 9.0, 5.0, 9.0), shirt)
	n.draw_rect(Rect2(foot.x - 1.0, foot.y - 12.0, 4.0, 3.0), Color(0.86, 0.66, 0.5))
	n.draw_colored_polygon(PackedVector2Array([Vector2(foot.x - 5.0, foot.y - 11.0), Vector2(foot.x + 7.0, foot.y - 11.0),
		Vector2(foot.x + 1.0, foot.y - 17.0)]), Color(0.95, 0.86, 0.55))


# ------------------------------------------------------------------ mặt đất: sình, cầu khỉ, mép rạch, bến nhà

func _draw_ground() -> void:
	var left: float = _cam_left - 80.0
	var right: float = _cam_left + _view.x + 80.0
	if _stage == 1:
		for m in course["mud"]:
			var mv: Vector2 = m
			if mv.y < left or mv.x > right:
				continue
			var cx: float = (mv.x + mv.y) * 0.5
			var rx: float = (mv.y - mv.x) * 0.5
			Art.ellipse(_ground, Vector2(cx, GROUND_Y + 2.0), rx + 4.0, 6.0, Color(0.4, 0.3, 0.2))
			Art.ellipse(_ground, Vector2(cx, GROUND_Y + 2.0), rx, 4.0, Color(0.3, 0.22, 0.15))
			for k in range(int(rx / 10.0)):
				var gx: float = mv.x + 6.0 + float(k) * 10.0 + roundf(sin(_clock * 2.0 + float(k)) * 1.0)
				_ground.draw_rect(Rect2(gx, GROUND_Y + float(k % 3), 3.0, 1.0), Color(0.55, 0.45, 0.32))
		var bridge: Vector2 = course["bridge"]
		if bridge.y > left and bridge.x < right:
			_draw_ditch(bridge)
		if RUN_LEN - 60.0 < right:
			_draw_canal_edge()
	else:
		# Dòng nước chảy xiết: vệt trắng trôi theo hướng đẩy.
		for cur in course["currents"]:
			var x0: float = float(cur["x0"])
			var x1: float = float(cur["x1"])
			if x1 < left or x0 > right:
				continue
			var dirx: float = signf(float(cur["push_x"]))
			var diry: float = signf(float(cur["push_y"]))
			for k in range(int((x1 - x0) / 14.0)):
				var h: int = Art.hash_i(k, int(x0))
				var px: float = x0 + fmod(float(h % 1000) + _clock * 30.0 * dirx + 2000.0, x1 - x0)
				var py: float = SWIM_TOP - 4.0 + float((h >> 5) % 70) + fmod(_clock * 12.0 * diry + float(h % 20) + 40.0, 20.0) - 10.0
				_ground.draw_rect(Rect2(roundf(px), roundf(py), 6.0, 1.0), Color(0.92, 0.97, 1.0, 0.45))
				_ground.draw_rect(Rect2(roundf(px) + 5.0, roundf(py) + diry, 2.0, 1.0), Color(0.92, 0.97, 1.0, 0.35))
		if SWIM_LEN - 60.0 < right:
			_draw_home_bank()


func _draw_ditch(bridge: Vector2) -> void:
	# Mương nước cắt ngang con hẻm + cầu khỉ một cây tre, tay vịn, chân chữ X.
	var x0: float = bridge.x - 6.0
	var x1: float = bridge.y + 6.0
	var bottom: float = _view.y + 40.0
	_ground.draw_rect(Rect2(x0, 176.0, x1 - x0, bottom), Color(0.38, 0.46, 0.4))
	_ground.draw_rect(Rect2(x0, 176.0, x1 - x0, 3.0), Color(0.3, 0.38, 0.32))
	for k in range(int((x1 - x0) / 12.0)):
		var h: int = Art.hash_i(k, 401)
		var gx: float = x0 + float(k) * 12.0 + fmod(_clock * 6.0, 12.0)
		_ground.draw_rect(Rect2(roundf(gx), 186.0 + float(h % 40), 4.0, 1.0), Color(0.75, 0.85, 0.8, 0.5))
	for side in [x0, x1]:
		_ground.draw_colored_polygon(PackedVector2Array([Vector2(side - 8.0 if side == x0 else side, 176.0),
			Vector2(side + 8.0 if side == x1 else side, 176.0), Vector2(side, bottom)]), Color(0.45, 0.35, 0.22))
	var bamboo := Color(0.8, 0.68, 0.36)
	var dark := Color(0.55, 0.44, 0.22)
	# Chân cầu chữ X mỗi ~60 px.
	var x: float = bridge.x + 20.0
	while x < bridge.y:
		_ground.draw_line(Vector2(x - 8.0, GROUND_Y + 30.0), Vector2(x + 6.0, GROUND_Y - 2.0), dark, 2.0)
		_ground.draw_line(Vector2(x + 8.0, GROUND_Y + 30.0), Vector2(x - 6.0, GROUND_Y - 2.0), dark, 2.0)
		x += 60.0
	# Cây tre làm mặt cầu (hero đi trên GROUND_Y).
	_ground.draw_rect(Rect2(bridge.x - 12.0, GROUND_Y - 1.0, BRIDGE_LEN + 24.0, 3.0), bamboo)
	_ground.draw_rect(Rect2(bridge.x - 12.0, GROUND_Y + 1.0, BRIDGE_LEN + 24.0, 1.0), dark)
	for k in range(int(BRIDGE_LEN / 24.0) + 2):
		_ground.draw_rect(Rect2(bridge.x - 12.0 + float(k) * 24.0, GROUND_Y - 1.0, 1.0, 3.0), dark)


func _draw_canal_edge() -> void:
	# Cuối hẻm: bờ rạch + mặt nước (nơi nhảy sông).
	var x: float = RUN_LEN + 16.0
	var bottom: float = _view.y + 40.0
	_ground.draw_rect(Rect2(x, 176.0, _view.x + 300.0, bottom), Color(0.4, 0.52, 0.5))
	_ground.draw_rect(Rect2(x, 176.0, _view.x + 300.0, 2.0), Color(0.32, 0.4, 0.38))
	for k in range(40):
		var h: int = Art.hash_i(k, 503)
		var gx: float = x + 10.0 + float(k) * 14.0 - fmod(_clock * 8.0, 14.0)
		_ground.draw_rect(Rect2(roundf(gx), 184.0 + float(h % 50), 5.0, 1.0), Color(0.85, 0.94, 0.97, 0.5))
	_ground.draw_colored_polygon(PackedVector2Array([Vector2(x - 20.0, PATH_TOP), Vector2(x, PATH_TOP), Vector2(x + 6.0, bottom), Vector2(x - 20.0, bottom)]), Color(0.52, 0.4, 0.26))
	Art.stand(_ground, Art.prop("sign_ferry"), Vector2(x - 30.0, 182.0))
	Art.stand(_ground, Art.prop("nipa", int(_clock * 2.0) % 4), Vector2(x + 50.0, 180.0))


func _draw_home_bank() -> void:
	# Bờ bên kia: đất + cầu ván + nhà mình (vẽ tay, cao ráo cho vừa người), cửa mở/đóng.
	var x: float = SWIM_LEN
	var bottom: float = _view.y + 40.0
	var right: float = x + _view.x + 300.0
	_ground.draw_colored_polygon(PackedVector2Array([Vector2(x + 4.0, 120.0), Vector2(right, 120.0), Vector2(right, bottom), Vector2(x - 14.0, bottom)]), Color(0.42, 0.6, 0.28))
	_ground.draw_colored_polygon(PackedVector2Array([Vector2(x + 4.0, 120.0), Vector2(x + 12.0, 120.0), Vector2(x - 6.0, bottom), Vector2(x - 14.0, bottom)]), Color(0.5, 0.4, 0.26))
	# Cầu ván xuống nước.
	for k in range(4):
		_ground.draw_rect(Rect2(x - 22.0 + float(k) * 2.0, 160.0 + float(k) * 12.0, 30.0, 3.0), Color(0.6, 0.45, 0.26))
	# Lối đi đất tới cửa.
	var door_x: float = x + HOME_DOOR_DX
	_ground.draw_colored_polygon(PackedVector2Array([Vector2(door_x - 10.0, HOME_FOOT_Y), Vector2(door_x + 10.0, HOME_FOOT_Y),
		Vector2(x + 30.0, 214.0), Vector2(x - 4.0, 214.0)]), Color(0.7, 0.58, 0.4))
	_draw_home_house(Vector2(door_x, HOME_FOOT_Y))


func _draw_home_house(door_foot: Vector2) -> void:
	var g := _ground
	var w: float = 136.0
	var h: float = 56.0
	var left: float = roundf(door_foot.x - w * 0.5)
	var top: float = door_foot.y - h
	var wood := Color(0.62, 0.42, 0.26)
	g.draw_rect(Rect2(left, top, w, h), wood)
	for k in range(0, int(w), 8):
		g.draw_rect(Rect2(left + float(k), top, 1.0, h), wood.darkened(0.2))
	g.draw_rect(Rect2(left, top + h - 3.0, w, 3.0), Color(0.45, 0.4, 0.36))
	# Cửa sổ hai bên.
	for wx in [left + 16.0, left + w - 40.0]:
		g.draw_rect(Rect2(wx, top + 16.0, 24.0, 16.0), Color(0.25, 0.18, 0.12))
		for k in range(4):
			g.draw_rect(Rect2(wx + 3.0 + float(k) * 6.0, top + 16.0, 1.0, 16.0), Color(0.55, 0.4, 0.22))
		g.draw_rect(Rect2(wx - 2.0, top + 14.0, 28.0, 2.0), Color(0.3, 0.55, 0.4))
	# Mái lá dừa nước.
	var roof := Color(0.62, 0.48, 0.28)
	g.draw_colored_polygon(PackedVector2Array([Vector2(left - 10.0, top + 2.0), Vector2(left + w + 10.0, top + 2.0),
		Vector2(left + w - 18.0, top - 30.0), Vector2(left + 18.0, top - 30.0)]), roof)
	for k in range(1, 8):
		var yy: float = top + 2.0 - float(k) * 4.0
		var inset: float = float(k) * 4.0
		g.draw_rect(Rect2(left - 10.0 + inset, yy, w + 20.0 - inset * 2.0, 1.0), roof.darkened(0.22))
	g.draw_rect(Rect2(left + 18.0, top - 31.0, w - 36.0, 2.0), roof.lightened(0.2))
	Art.stand(g, Art.prop("smoke", int(_clock * 10.0) % 8), Vector2(left + w - 30.0, top - 28.0))
	# Cửa: khung + hai cánh (mở theo _home_door).
	var door := Rect2(door_foot.x - 11.0, door_foot.y - 44.0, 22.0, 44.0)
	g.draw_rect(door.grow(2.0), Color(0.35, 0.22, 0.14))
	g.draw_rect(door, Color(0.12, 0.08, 0.06))
	var open: float = clampf(_home_door, 0.0, 1.0)
	var leaf: float = roundf(11.0 * (1.0 - open))
	if leaf > 0.0:
		g.draw_rect(Rect2(door.position.x, door.position.y, leaf, door.size.y), Color(0.3, 0.55, 0.45))
		g.draw_rect(Rect2(door.end.x - leaf, door.position.y, leaf, door.size.y), Color(0.3, 0.55, 0.45))
		g.draw_rect(Rect2(door.position.x + leaf - 1.0, door.position.y, 1.0, door.size.y), Color(0.2, 0.38, 0.3))
	# Bảng "NHÀ MÌNH" nho nhỏ + lu nước + chuối.
	g.draw_rect(Rect2(door_foot.x - 14.0, door.position.y - 9.0, 28.0, 6.0), Color(0.85, 0.75, 0.5))
	Art.stand(g, Art.prop("jar"), Vector2(left + 6.0, door_foot.y + 2.0))
	Art.stand(g, Art.prop("banana", int(_clock * 2.0) % 4), Vector2(left + w + 24.0, door_foot.y + 2.0))


# ------------------------------------------------------------------ hiệu ứng hạt

func _burst(pos: Vector2, color: Color, count: int, speed: float, life: float) -> void:
	for k in range(count):
		var angle: float = _rng_fx.randf_range(-PI, 0.0)
		var v := Vector2(cos(angle), sin(angle)) * _rng_fx.randf_range(speed * 0.4, speed)
		_particles.append({"p": pos, "v": v, "life": life, "max": life, "c": color, "g": 160.0, "s": 1.0 + float(k % 2)})


func _update_particles(dt: float) -> void:
	var kept: Array[Dictionary] = []
	for p in _particles:
		p["life"] = float(p["life"]) - dt
		if float(p["life"]) <= 0.0:
			continue
		var v: Vector2 = p["v"]
		v.y += float(p["g"]) * dt
		p["v"] = v
		p["p"] = (p["p"] as Vector2) + v * dt
		kept.append(p)
	_particles = kept


func _draw_fx() -> void:
	for p in _particles:
		var c: Color = p["c"]
		c.a *= clampf(float(p["life"]) / float(p["max"]), 0.0, 1.0)
		var s: float = float(p["s"])
		_fx_layer.draw_rect(Rect2((p["p"] as Vector2).round(), Vector2(s, s)), c)
	# Vệt gió khi chạy nước rút.
	if _sprinting and phase == Phase.RUN:
		for k in range(6):
			var h: int = Art.hash_i(k, 97)
			var y: float = GROUND_Y - 6.0 - float(h % 36)
			var x: float = _x - 10.0 - fmod(_clock * 260.0 + float(h % 97), 60.0)
			_fx_layer.draw_rect(Rect2(roundf(x), y, 8.0 + float((h >> 8) % 8), 1.0), Color(1, 1, 1, 0.5))
	# Mương nước phía trước khi rớt xuống (che nửa người).
	if _stage == 1 and _fallen > 0.0:
		_fx_layer.draw_rect(Rect2(roundf(_x) - 16.0, GROUND_Y + 4.0, 32.0, 30.0), Color(0.38, 0.46, 0.4, 0.92))
		_fx_layer.draw_rect(Rect2(roundf(_x) - 16.0, GROUND_Y + 4.0, 32.0, 1.0), Color(0.8, 0.9, 0.9, 0.8))
	# Cầu khỉ: tay vịn tre phía trước người.
	if _stage == 1:
		var bridge: Vector2 = course["bridge"]
		if bridge.y > _cam_left - 40.0 and bridge.x < _cam_left + _view.x + 40.0:
			var rail_y: float = GROUND_Y - 24.0
			_fx_layer.draw_rect(Rect2(bridge.x - 10.0, rail_y, BRIDGE_LEN + 20.0, 2.0), Color(0.82, 0.7, 0.38))
			var px: float = bridge.x - 10.0
			while px <= bridge.y + 10.0:
				_fx_layer.draw_rect(Rect2(px, rail_y, 2.0, 40.0), Color(0.6, 0.48, 0.24))
				px += 60.0
	# Đốm sáng xanh – đỏ trên vai công an (đèn pin nhấp nháy).
	if phase == Phase.RUN or phase == Phase.SWIM:
		var red: bool = int(_clock * 4.0) % 2 == 0
		var lp := Vector2(roundf(_police_x) - 4.0, (GROUND_Y - 22.0) if _stage == 1 else (_police_y - 14.0))
		_fx_layer.draw_rect(Rect2(lp, Vector2(3, 3)), Color(1.0, 0.2, 0.15) if red else Color(0.25, 0.45, 1.0))
		_fx_layer.draw_circle(lp + Vector2(1.5, 1.5), 7.0, Color(1.0, 0.2, 0.15, 0.18) if red else Color(0.25, 0.45, 1.0, 0.18))


## Dấu báo trước chướng ngại sắp vào khung hình (◄ + ▲ nhảy / ▼ cúi; chặng bơi: ◄ ngang làn) + màn nước khi lặn.
func _draw_overlay() -> void:
	if _wipe > 0.0:
		var a: float = clampf(_wipe, 0.0, 1.0)
		_overlay.draw_rect(Rect2(_cam_left - 4.0, -20.0, _view.x + 8.0, _view.y + 60.0), Color(0.75, 0.9, 1.0, a * 0.85))
	if phase != Phase.RUN and phase != Phase.SWIM:
		return
	var right: float = _cam_left + _view.x
	for o in _obstacles:
		if o.hit or o.passed:
			continue
		var ahead: float = o.x - o.w - right
		if ahead < 0.0 or ahead > 330.0:
			continue
		var blink: bool = int(_clock * 6.0) % 2 == 0 or ahead < 120.0
		if not blink:
			continue
		var x: float = right - 10.0
		var y: float
		var color := Color(1.0, 0.35, 0.2) if o.hard else Color(1.0, 0.75, 0.2)
		if o.stage == 1:
			y = GROUND_Y - (34.0 if o.mode == &"duck" else 10.0)
		else:
			y = roundf(clampf(o.y, SWIM_TOP, SWIM_BOTTOM))
		_overlay.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 6, y - 4), Vector2(x + 6, y + 4)]), color)
		_overlay.draw_rect(Rect2(x - 4.0, y - 3.0, 2.0, 4.0), color)
		_overlay.draw_rect(Rect2(x - 4.0, y + 2.0, 2.0, 1.0), color)
		if o.stage == 1:
			var up: bool = o.mode == &"jump"
			var ay: float = y - 9.0
			if up:
				_overlay.draw_colored_polygon(PackedVector2Array([Vector2(x - 1, ay + 3), Vector2(x + 7, ay + 3), Vector2(x + 3, ay - 2)]), Color(1, 1, 1))
			else:
				_overlay.draw_colored_polygon(PackedVector2Array([Vector2(x - 1, ay - 2), Vector2(x + 7, ay - 2), Vector2(x + 3, ay + 3)]), Color(1, 1, 1))
