class_name BattleDirector
extends Node2D

## Một trận đấu chiến kê 1-vs-1 trên đấu trường Ao Làng.
##
## Dùng lại core của dự án: FighterController (di chuyển, dash, facing, khóa phản ứng, HP, knockback,
## launch), MovementConfig, InputFrame/LocalInputSource (11 bit logic), AttackData/AttackCatalog,
## CombatResolutionController (áp sát thương + phản ứng), SpecialGaugeComponent, CardController.
##
## Bảng chiêu theo D:/GameArt/rooster_fight_movelist.md (Moves.gd). Nút: J = L, K = M, L = H, H = S.
## Director bước mô phỏng cố định 60 Hz theo thứ tự xác định:
##   input → lệnh/bộ đệm → bắt đầu đòn → di chuyển → tiến frame đòn (vòng rush, đạn, hút)
##   → va chạm hitbox/hurtbox/đạn → trúng/đỡ/va chạm đòn → tách pushbox → phản ứng (té, văng, nằm, dậy).
##
## Luật lấy từ GDD v1.2 chương 4: đỡ theo hướng có đỡ đứng/đỡ cúi và tầng đòn (Bảng 4.5),
## Block Gauge 100 hồi 15/s sau 1,5 s, về 0 thì vỡ thủ + ngã, gauge về 50 (Bảng 4.8),
## knockback theo WEIGHT (công thức 2), sát thương công thức 1, tường 0–1000 px, đồng hồ 99 s + hiệp phụ.
## Quyết định Owner giữ nguyên: Special Gauge 5 vạch, chip 1 HP khi đỡ.
## PLACEHOLDER: lượng Special Gauge cộng thêm, hitstun nối combo, chi phí Block Gauge cho từng nhóm đòn.

signal finished(result: Dictionary)

enum Phase { INTRO, FIGHT, KO, END, ROUND_INTRO, ROUND_END }

const USE_HIGH_LOW_GUARD: bool = true
const ROUND_TICKS: int = 99 * 60
const OVERTIME_TICKS: int = 15 * 60
const BUFFER_TICKS: int = 8
const GUARD_CANCEL_TICKS: int = 6
const SUPER_FREEZE_TICKS: int = 50
const SP_FREEZE_TICKS: int = 18
const GUARD_MAX: float = 100.0
const GUARD_COST: Dictionary = {"L": 10.0, "M": 18.0, "H": 25.0, "SP": 8.0, "PROJ": 6.0, "SUPER": 40.0}
const GUARD_REGEN_PER_TICK: float = 15.0 / 60.0
const GUARD_REGEN_DELAY_TICKS: int = 90
const GUARD_AFTER_BREAK: float = 50.0
const CHIP_DAMAGE: int = 1
const CRIT_MULTIPLIER: float = 1.5
const TAUNT_GAIN_RATIO: float = 0.25
const JUGGLE_LIMIT: int = 4
const WAKE_TICKS: int = 41          # DUNG_Day 690 ms
const WAKE_INVULN_TICKS: int = 35   # bất tử f1–f7
const VANG_LAND_TICKS: int = 15     # 3 frame cuối VANG_RaXa
const CLASH_PUSH_PX: float = 30.0
const RUSH_CLASH_TICKS: int = 90    # 1,5 s
const PROJECTILE_SPEED: float = 8.0 # px/tick
const STAGE_MIN: float = 32.0
const STAGE_MAX: float = 968.0
const START_X: Array[float] = [370.0, 630.0]
## PLACEHOLDER (tuning): hệ số HP cho trận nhiều hiệp (không áp dụng trận hướng dẫn) để một hiệp
## kéo dài ~35–55 s giữa hai AI tầm trung (đo bằng tests/game/run_ai_batch.gd).
const HEALTH_SCALE: float = 1.6
const MATCH_ROUNDS_TO_WIN: int = 2
const ROUND_SETTLE_TICKS: int = 30
const INTRO_TICKS: int = 290
const SKIP_MASK: int = (1 << InputBits.LIGHT) | (1 << InputBits.HEAVY) | (1 << InputBits.SPECIAL) | (1 << InputBits.ACTION_H)

const MOVE_MASK: int = (1 << InputBits.MOVE_LEFT) | (1 << InputBits.MOVE_RIGHT) \
	| (1 << InputBits.JUMP) | (1 << InputBits.CROUCH)
const CARD_MASK: int = (1 << InputBits.CARD_PREV) | (1 << InputBits.CARD_NEXT) | (1 << InputBits.CARD_USE)
## Nút logic → nút trong bảng chiêu.
const BTN_L: int = InputBits.LIGHT     # J
const BTN_M: int = InputBits.HEAVY     # K
const BTN_H: int = InputBits.SPECIAL   # L
const BTN_S: int = InputBits.ACTION_H  # H

const PLAYER_ACTIONS: Dictionary = {
	InputBits.MOVE_LEFT: [&"p1_left", KEY_A],
	InputBits.MOVE_RIGHT: [&"p1_right", KEY_D],
	InputBits.JUMP: [&"p1_jump", KEY_W],
	InputBits.CROUCH: [&"p1_crouch", KEY_S],
	InputBits.LIGHT: [&"p1_light", KEY_J],
	InputBits.HEAVY: [&"p1_heavy", KEY_K],
	InputBits.SPECIAL: [&"p1_special", KEY_L],
	InputBits.ACTION_H: [&"p1_action_h", KEY_H],
	InputBits.CARD_PREV: [&"p1_card_prev", KEY_U],
	InputBits.CARD_NEXT: [&"p1_card_next", KEY_I],
	InputBits.CARD_USE: [&"p1_card_use", KEY_O],
}


class Fighter:
	extends RefCounted
	var index: int = 0
	var body: FighterController
	var view: FighterView
	var source: LocalInputSource
	var health: Node
	var ai: EnemyAI
	var ai_held: int = 0
	var side: Dictionary = {}
	var stats: Dictionary = {}
	var is_player: bool = false
	var dao_chan: bool = false
	var mao_sat: bool = false
	var special: SpecialGaugeComponent
	var card_gauge: CardGaugeComponent
	var cards: CardController
	var guard: float = 100.0
	var guard_delay: int = 0
	var break_pending: bool = false
	# Đòn đang ra
	var move: Dictionary = {}
	var mf: int = 0
	var mft: int = 0
	var loops: int = 0
	var loop_req: bool = false
	var hit_used: Array[bool] = []
	var contact_tick: int = -100
	var move_started_now: bool = false
	var chain: int = 0
	var instance: int = 0
	var buffer_cmd: StringName = &""
	var buffer_ticks: int = 0
	# Input
	var pending_pressed: int = 0
	var tick_pressed: int = 0
	var held: int = 0
	var dir_hist: Array = []
	var last_dir: int = 5
	var serial: int = 0
	var mash: int = 0
	# Thân
	var jump_dir: int = 0
	var air_used: bool = false
	var airborne: bool = false
	var was_airborne: bool = false
	var was_dashing: bool = false
	# Phản ứng: "" | nhe | nang | guard | te | vang | vang_land | nam | dung
	var react: StringName = &""
	var react_t: int = 0
	var juggle: int = 0
	var invuln: int = 0
	var ko: bool = false
	var combo_hits: int = 0
	var combo_damage: int = 0
	var damage_taken: int = 0
	var anim: StringName = &""
	var anim_ticks: int = 0
	var track: Dictionary = {"l_hits": 0, "m_hits": 0, "h_hits": 0, "blocks": 0, "specials": 0,
		"cards": 0, "max_combo": 0, "rush": 0, "armor": 0, "counters": 0}
	# Kit (bộ chiêu) và cơ chế riêng của kit.
	var kit: StringName = &"rooster"
	var kdef: Dictionary = {}
	var armor: int = 0           # số đòn còn chịu được (giáp của chiêu đang ra)
	var wake_armor: int = 0      # giáp khi đứng dậy (Đông Tảo DUNG_Day f7–f10)
	var countered: bool = false  # Phản Đòn đã bắt được đòn
	var contact_blocked: bool = false # lần chạm gần nhất bị đỡ
	var move_start_tick: int = 0
	var jump_serial: int = 0
	var run_loops: int = 0
	var prox_guard: bool = false # Thiết Giáp: giữ lùi khi bị đe dọa thì đứng thủ, không lùi
	var intro_pose: bool = false # mở màn: diễn tư thế thị uy
	var total_damage: int = 0    # sát thương nhận ở các hiệp trước

	func x() -> float:
		return body.global_position.x

	func facing() -> int:
		return body.get_facing()

	func hp() -> int:
		return int(health.call("get_current_hp"))

	func hp_ratio() -> float:
		return float(health.call("get_health_ratio"))

	func alive() -> bool:
		return bool(health.call("is_alive"))

	func reaction(kind: int) -> int:
		return int(body._hit_reaction_controller.call("get_remaining_ticks", kind))

	func hitstun() -> int:
		return reaction(HitReactionController.ReactionKind.HITSTUN)

	func blockstun() -> int:
		return reaction(HitReactionController.ReactionKind.BLOCKSTUN)

	func down() -> bool:
		return reaction(HitReactionController.ReactionKind.DOWN) > 0

	func locked() -> bool:
		return body.is_control_locked()

	func crouching() -> bool:
		return not airborne and bool(kdef.get("can_crouch", true)) and (held & (1 << InputBits.CROUCH)) != 0

	func push_half() -> float:
		return float(kdef.get("push_half", Moves.PUSH_HALF_WIDTH))

	func move_cat() -> String:
		return String(move.get("cat", ""))

	func in_rush_loop() -> bool:
		if move.is_empty() or not move.has("loop"):
			return false
		var loop: Array = move["loop"]
		return mf >= int(loop[0]) and mf <= int(loop[1])


class Projectile:
	extends RefCounted
	var owner: int = 0
	var pos: Vector2
	var dir: int = 1
	var hits_left: int = 5
	var cooldown: int = 0
	var t: int = 0
	var node: Sprite2D

	func box() -> Rect2:
		return Rect2(pos.x - 46.0, pos.y - 22.0, 92.0, 44.0)


var phase: int = Phase.INTRO
var mode: StringName = &"normal"
var clock_ticks: int = ROUND_TICKS
var overtime: bool = false
var fighters: Array[Fighter] = []
var projectiles: Array[Projectile] = []
var winner: int = -1
var title: String = ""
var objectives: Array[Dictionary] = []
var tutorial_step: int = 0
var debug_boxes: bool = false
var hud: BattleHud
var sfx: Sfx
var arena: BattleArena
var fx: BattleFx
var camera: Camera2D
var rush_clash: int = 0
## Hiệp đấu: số hiệp thắng của mỗi bên và số hiệp cần để thắng trận.
var round_wins: Array[int] = [0, 0]
var rounds_to_win: int = 1
var round_index: int = 1
## [{winner, ticks, reason, hp}] cho mỗi hiệp đã xong.
var round_log: Array = []
## Trình diễn điện ảnh (mở màn, quay chậm K.O., …). Tắt được cho chạy hàng loạt; không đổi kết quả mô phỏng.
var cinematics: bool = true
var max_rounds: int = 3
## Nhật ký đòn trúng (để test/cân bằng): [tick, attacker, move, react, dealt].
var hit_log: Array = []
## Trận gần nhất (cho màn kết quả): {"sides": [player, opponent], "result": {...}}.
static var last_match: Dictionary = {}

var _config: Dictionary = {}
var _phase_ticks: int = 0
var _sim_tick: int = 0
var _hitstop: int = 0
var _freeze: int = 0
var _shake: float = 0.0
var _rng := RandomNumberGenerator.new()
## RNG riêng cho hình ảnh (rung, bụi, cao độ âm) để trình diễn không ảnh hưởng mô phỏng.
var _fx_rng := RandomNumberGenerator.new()
var _round_ticks: int = 0
var _round_frames: int = 0  # khung hình 60 Hz trong pha FIGHT (gồm hitstop/dừng hình) – thời lượng hiệp thật
var _match_ticks: int = 0
var _match_point_final: bool = false
var _skip_requested: bool = false
var _cine_pos: Vector2 = Vector2(500, -150)
var _cine_zoom: float = 1.0
var _cine_weight: float = 0.0
var _zoom_punch: float = 0.0
var _shake_dir: Vector2 = Vector2(1, 0)
var _last_hit_point: Vector2 = Vector2(500, -60)
var _instance_counter: int = 0
var _cam_zoom: float = 1.4
var _cam_pos: Vector2 = Vector2(500, -150)
var _stage: Node2D


## config: {player: side, opponent: side, mode: "tutorial"|"friendly"|"normal", title: String, seed: int}
func setup(config: Dictionary) -> void:
	_config = config
	mode = StringName(config.get("mode", "normal"))
	title = String(config.get("title", ""))
	_rng.seed = int(config.get("seed", 1))
	_fx_rng.seed = int(config.get("seed", 1)) * 7919 + 13
	cinematics = bool(config.get("cinematics", true))
	rounds_to_win = 1 if mode == &"tutorial" else int(config.get("rounds_to_win", MATCH_ROUNDS_TO_WIN))
	max_rounds = rounds_to_win * 2 - 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 6
	_register_player_actions()

	arena = BattleArena.new()
	arena.configure(_config) # chỉ trình diễn: biến thể sân + ẩn chủ gà đối thủ khỏi khán đài
	arena.z_index = -50
	add_child(arena)
	_stage = Node2D.new()
	_stage.name = "Stage"
	add_child(_stage)
	fx = BattleFx.new()
	add_child(fx)
	sfx = Sfx.new()
	add_child(sfx)

	var sides: Array = [_config["player"], _config["opponent"]]
	last_match = {"sides": sides.duplicate(true)}
	var bodies: Array[FighterController] = []
	for i in range(2):
		var side: Dictionary = sides[i]
		var kit_id: StringName = Moves.kit_for_side(side)
		var kdef: Dictionary = Moves.kit(kit_id)
		var body := FighterController.new()
		body.name = "P%d" % (i + 1)
		body.breed = int(side["breed"])
		var hp_scale: float = 1.0 if mode == &"tutorial" else float(_config.get("health_scale", HEALTH_SCALE))
		body.health_max_hp = int(round(float(GameState.scaled_stats(int(side["breed"]), int(side["lv"]))["hp"]) * hp_scale))
		body.dash_policy = FighterController.DASH_GROUNDED_ONLY if bool(kdef["can_dash"]) else FighterController.DASH_DISABLED
		body.position = Vector2(START_X[i], -2.0)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(float(kdef["push_half"]) * 2.0, 100.0)
		shape.shape = rect
		shape.position = Vector2(0, -50)
		body.add_child(shape)
		var view := FighterView.new()
		view.name = "View"
		view.kit = kit_id
		view.colors = side.get("colors", {})
		view.hue = float(side.get("hue", 0.0))
		view.saturation = float(side.get("sat", 1.0))
		view.body_scale = 0.9 if int(side["breed"]) == MovementConfig.Breed.GA_TRE else 1.0
		view.fx_parent = _stage
		view.facing = 1 if i == 0 else -1
		body.add_child(view)
		_stage.add_child(body)
		bodies.append(body)

	for i in range(2):
		var side: Dictionary = sides[i]
		var f := Fighter.new()
		f.index = i
		f.body = bodies[i]
		f.body.set_physics_process(false) # Director bước mô phỏng.
		f.body.add_collision_exception_with(bodies[1 - i]) # Pushbox do director tự tách.
		f.view = f.body.get_node("View") as FighterView
		f.source = f.body.get_input_source()
		f.health = f.body.get_health_component()
		f.side = side
		f.kit = Moves.kit_for_side(side)
		f.kdef = Moves.kit(f.kit)
		f.stats = GameState.scaled_stats(int(side["breed"]), int(side["lv"]))
		f.is_player = i == 0
		f.dao_chan = bool(side.get("dao_chan", false))
		f.mao_sat = bool(side.get("mao_sat", false))
		f.special = SpecialGaugeComponent.new()
		f.body.add_child(f.special)
		f.special.configure(0)
		var card_ids: Array = side.get("cards", [])
		if not card_ids.is_empty():
			var database: CardDatabase = CardDatabase.create_default_database()
			var deck: Array[CardData] = []
			for card_id in card_ids:
				deck.append(database.get_card(card_id))
			f.card_gauge = CardGaugeComponent.new()
			f.card_gauge.configure(2) # GDD 4.7: bắt đầu trận với 2
			f.cards = CardController.new()
			if not f.cards.configure(deck, f.card_gauge, 0, _rng.randi()):
				f.cards = null
		if f.is_player:
			var mapping: Dictionary = {}
			for bit in PLAYER_ACTIONS.keys():
				mapping[bit] = PLAYER_ACTIONS[bit][0]
			f.source.configure(mapping)
		else:
			f.source.configure({})
			f.ai = EnemyAI.new()
			var ai_config: Dictionary = side.duplicate()
			ai_config["kit"] = f.kit
			f.ai.configure(ai_config, _rng.randi())
		fighters.append(f)

	camera = Camera2D.new()
	camera.position = _cam_pos
	camera.zoom = Vector2(_cam_zoom, _cam_zoom)
	add_child(camera)
	camera.make_current()

	hud = BattleHud.new()
	hud.director = self
	add_child(hud)

	_setup_mode()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _register_player_actions() -> void:
	for bit in PLAYER_ACTIONS.keys():
		var action: StringName = PLAYER_ACTIONS[bit][0]
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = PLAYER_ACTIONS[bit][1]
		InputMap.action_add_event(action, event)


func _setup_mode() -> void:
	match mode:
		&"tutorial":
			fighters[1].ai.script_mode = EnemyAI.Mode.PASSIVE
			objectives = [
				{"text": "Đánh trúng 3 lần bằng J (Mổ Nhanh)", "goal": 3, "value": 0},
				{"text": "Đánh trúng 1 lần bằng K (Tát Cánh)", "goal": 1, "value": 0},
			]
			hud.hint = "Áp sát rồi nhấn J để mổ nhanh, K để tát cánh."
		&"friendly":
			objectives = [{"text": "Dùng ít nhất 1 thẻ (U/I chọn, O tung)", "goal": 1, "value": 0}]


# =================================================================== vòng lặp

func _physics_process(_delta: float) -> void:
	_phase_ticks += 1
	var runs_sim: bool = phase == Phase.FIGHT and _freeze == 0 and _hitstop == 0
	if runs_sim:
		for f in fighters:
			if f.ai != null:
				_drive_ai(f, fighters[1 - f.index])
	var physics_frame: int = Engine.get_physics_frames()
	for f in fighters:
		var frame: InputFrame = f.source.sample(physics_frame)
		if frame != null:
			f.held = frame.held
			f.pending_pressed |= frame.pressed

	match phase:
		Phase.INTRO:
			_intro_tick()
		Phase.ROUND_INTRO:
			_round_intro_tick()
		Phase.FIGHT:
			_round_frames += 1
			if _freeze > 0:
				_freeze -= 1
				if _freeze == 0:
					_end_freeze()
			elif _hitstop > 0:
				_hitstop -= 1
				_tick_clock()
			else:
				_sim_step()
		Phase.KO:
			_ko_tick()
		Phase.ROUND_END:
			_round_end_tick()
		Phase.END:
			_outro_tick()

	for f in fighters:
		f.view.shake_ticks = _hitstop if f.react in [&"nhe", &"nang", &"guard"] else 0
		_update_view(f)
	_update_projectile_views()
	_update_camera()
	queue_redraw()


## Mở màn trận (chỉ trình diễn): lia máy qua khán đài, hai gà ra sân kèm bảng tên, màn "VS",
## rồi gọi hiệp. Bấm J/K/L/H (hoặc E/Enter/Space) để bỏ qua. Trận hướng dẫn chỉ có tiêu đề ngắn.
func _intro_tick() -> void:
	var skip: bool = (fighters[0].pending_pressed & SKIP_MASK) != 0 or _skip_requested
	_skip_requested = false
	for f in fighters:
		f.pending_pressed = 0
		_step_body(f, 0, 0)
	if not cinematics:
		_begin_round_intro()
		return
	if mode == &"tutorial":
		if _phase_ticks == 10:
			hud.announce(title if title != "" else "TRẬN ĐẤU", 70, Color(1.0, 0.92, 0.6))
		elif _phase_ticks >= 80 or (skip and _phase_ticks > 5):
			_begin_round_intro()
		return
	if skip and _phase_ticks > 5 and _phase_ticks < INTRO_TICKS - 20:
		_phase_ticks = INTRO_TICKS - 20
		hud.vs_splash(0.4)
		hud.clear_plates()
	var t: int = _phase_ticks
	if t == 1:
		_cine_set(Vector2(140, -230), 1.25, 1.0)
		arena.cheer(1.0)
		sfx.play(&"cheer", -6.0)
	if t <= 80:
		_cine_pos = Vector2(lerpf(140.0, 860.0, smoothstep(0.0, 80.0, float(t))), -230.0)
		if t == 12:
			hud.announce(title if title != "" else "TRẬN ĐẤU", 70, Color(1.0, 0.92, 0.6))
	elif t == 81:
		_entrance(0)
	elif t == 151:
		_entrance(1)
	elif t == 221:
		_cine_weight = 0.0
		for f in fighters:
			f.intro_pose = false
		hud.clear_plates()
		hud.vs_splash(1.3)
		sfx.play(&"super", -6.0, 0.8)
		arena.cheer(1.0)
	elif t >= INTRO_TICKS:
		for f in fighters:
			f.intro_pose = false
		_begin_round_intro()


func _entrance(i: int) -> void:
	var f: Fighter = fighters[i]
	fighters[1 - i].intro_pose = false
	f.intro_pose = true
	f.anim = &""
	_cine_set(f.body.global_position + Vector2(0, -80), 2.1, 1.0)
	hud.name_plate(i)
	fx.dust(Vector2(f.x(), 0), 12)
	sfx.play(&"land", 0.0, 0.7)
	arena.cheer(0.7)


func _begin_round_intro() -> void:
	phase = Phase.ROUND_INTRO
	_phase_ticks = 0
	_cine_weight = 0.0
	hud.clear_plates()


func _round_intro_tick() -> void:
	for f in fighters:
		f.pending_pressed = 0
		_step_body(f, 0, 0)
	if not cinematics:
		if _phase_ticks >= 2:
			phase = Phase.FIGHT
			_phase_ticks = 0
		return
	var t: int = _phase_ticks
	if t == 4:
		var text: String = "HIỆP %d" % round_index
		var color := Color(1.0, 0.92, 0.6)
		if mode == &"tutorial":
			text = "SẴN SÀNG…"
			color = Color(1, 1, 1)
		elif round_wins[0] == rounds_to_win - 1 and round_wins[1] == rounds_to_win - 1:
			text = "HIỆP QUYẾT ĐỊNH"
			color = Color(1.0, 0.45, 0.25)
		hud.announce(text, 50, color, 1.2)
		sfx.play(&"select", -2.0, 0.7)
	elif t == 52 and mode != &"tutorial":
		hud.announce("SẴN SÀNG…", 40, Color(1, 1, 1))
	elif t == 92:
		hud.announce("ĐÁ!", 45, Color(1.0, 0.55, 0.15), 1.6)
		sfx.play(&"bell")
		arena.cheer(0.8)
		_zoom_punch = 0.06
	elif t >= 96:
		phase = Phase.FIGHT
		_phase_ticks = 0


func _sim_step() -> void:
	_sim_tick += 1
	_round_ticks += 1
	_tick_clock()
	for f in fighters:
		f.tick_pressed = f.pending_pressed
		f.pending_pressed = 0
		f.move_started_now = false
		f.was_airborne = f.airborne
		_record_direction(f)
		_read_buttons(f)
	for f in fighters:
		_try_start_move(f)
	for f in fighters:
		_step_movement(f)
	for f in fighters:
		_advance_move(f, fighters[1 - f.index])
	_update_rush_clash()
	_advance_projectiles()
	_detect_contacts()
	_separate_pushboxes()
	for f in fighters:
		_post_step(f, fighters[1 - f.index])
	_update_objectives()
	_check_end()


func _tick_clock() -> void:
	if mode == &"tutorial":
		return
	clock_ticks -= 1 # Hitstop vẫn tính vào đồng hồ trận (GDD 4.11).


# =================================================================== lệnh

## Hướng tương đối theo bàn phím số: 4 lùi, 6 tiến, 2 xuống, 3 xuống-tiến, 1 xuống-lùi, 5 trung tính.
func _direction_number(f: Fighter) -> int:
	var fwd_bit: int = InputBits.MOVE_RIGHT if f.facing() > 0 else InputBits.MOVE_LEFT
	var back_bit: int = InputBits.MOVE_LEFT if f.facing() > 0 else InputBits.MOVE_RIGHT
	var x: int = (1 if (f.held & (1 << fwd_bit)) != 0 else 0) - (1 if (f.held & (1 << back_bit)) != 0 else 0)
	if (f.held & (1 << InputBits.CROUCH)) != 0:
		return 2 + x
	if (f.held & (1 << InputBits.JUMP)) != 0:
		return 8 + x
	return 5 + x


func _record_direction(f: Fighter) -> void:
	var number: int = _direction_number(f)
	if number != f.last_dir:
		f.last_dir = number
		f.dir_hist.append([_sim_tick, number])
		if f.dir_hist.size() > 16:
			f.dir_hist.pop_front()


## Khớp lệnh vẽ tay (ví dụ ↓↘→) trong `window` tick gần nhất. Mỗi bước là tập hướng chấp nhận.
func _motion(f: Fighter, steps: Array, window: int) -> bool:
	var index: int = 0
	var last_tick: int = -1
	for entry in f.dir_hist:
		if _sim_tick - int(entry[0]) > window:
			continue
		if index < steps.size() and (steps[index] as Array).has(int(entry[1])):
			index += 1
			last_tick = int(entry[0])
	return index == steps.size() and _sim_tick - last_tick <= 10


func _command(f: Fighter, button: int) -> StringName:
	var number: int = _direction_number(f)
	var down: bool = number <= 3
	var forward: bool = number == 6 or number == 3 or number == 9
	var back: bool = number == 4 or number == 1 or number == 7
	if f.kit == Moves.KIT_DONGTAO:
		return _command_dongtao(f, button, down, forward, back)
	match button:
		BTN_S:
			if f.airborne:
				return &""
			if _motion(f, [[2, 1], [3, 6], [2, 1], [3, 6]], 40) or (back and not down):
				return &"loc_xoay_canh"
			if _motion(f, [[6], [2, 1], [3]], 20):
				return &"mo_lien_hoan"
			if _motion(f, [[2, 1], [3, 6]], 20) or down:
				return &"phun_long"
			return &"mo_lien_hoan"
		BTN_H:
			if f.airborne:
				return &"air_l"
			return &"cua_hat" if down else &"da_cua_bay"
		BTN_M:
			if f.airborne:
				return &"air_k"
			return &"quet_canh" if down else &"tat_canh"
		BTN_L:
			if f.airborne:
				return &"air_j"
			if down:
				return &"mo_thap"
			return &"da_nhe" if forward else &"mo_nhanh"
	return &""


## Gà Đông Tảo (cùng quy ước lối tắt với kit mặc định: S, ↓+S, ←+S, →+S, S+H):
##   S hoặc →→+S Húc Trâu · ↓+S hoặc ↓↓+S Địa Chấn · ←+S Phản Đòn ·
##   ↓↘→↓↘→+S hoặc →+S Thái Sơn Áp Đỉnh (→+S khi chưa đủ 2 vạch = Húc Trâu) · L/M/H mọi hướng.
func _command_dongtao(f: Fighter, button: int, down: bool, forward: bool, back: bool) -> StringName:
	match button:
		BTN_S:
			if _motion(f, [[2, 1], [3, 6], [2, 1], [3, 6]], 40):
				return &"thai_son"
			if _motion(f, [[6], [5, 4], [6]], 20):
				return &"huc_trau"
			if down or _motion(f, [[2, 1, 3], [5, 4, 6], [2, 1, 3]], 20):
				return &"dia_chan"
			if back:
				return &"phan_don"
			if forward and f.special.can_spend_bars(2):
				return &"thai_son"
			return &"huc_trau"
		BTN_H:
			return &"da_tru"
		BTN_M:
			return &"dam_chan"
		BTN_L:
			return &"huc_dau"
	return &""


func _read_buttons(f: Fighter) -> void:
	var pressed: int = f.tick_pressed
	if f.is_player or f.ai != null:
		if (pressed & (1 << BTN_S)) != 0:
			f.mash += 1
			if f.in_rush_loop():
				f.loop_req = true
	# Gáy Thị Uy: S + H cùng lúc.
	var s_now: bool = (pressed & (1 << BTN_S)) != 0
	var h_now: bool = (pressed & (1 << BTN_H)) != 0
	var s_held: bool = (f.held & (1 << BTN_S)) != 0
	var h_held: bool = (f.held & (1 << BTN_H)) != 0
	if (s_now and (h_now or h_held)) or (h_now and s_held):
		_buffer(f, StringName(f.kdef["taunt"]))
	elif not (f.in_rush_loop() and s_now):
		for button in [BTN_S, BTN_H, BTN_M, BTN_L]:
			if (pressed & (1 << button)) != 0:
				var cmd: StringName = _command(f, button)
				if cmd != &"":
					_buffer(f, cmd)
				break
	if f.cards != null:
		var card_pressed: int = 0 if f.ko else (pressed & CARD_MASK)
		var result: int = f.cards.process_input_snapshot(_sim_tick, card_pressed)
		if result == CardController.Result.ACTIVATED:
			f.track["cards"] = int(f.track["cards"]) + 1
			sfx.play(&"card")
			f.view.flash(Color(1.0, 0.85, 0.3), 0.8)
			hud.popup(f.index, "THẺ!", Color(1.0, 0.85, 0.3))
		elif result == CardController.Result.INSUFFICIENT_GAUGE and f.is_player:
			hud.popup(f.index, "Thiếu Card Gauge", Color(0.8, 0.8, 0.8))
		elif result == CardController.Result.SELECTION_CHANGED and f.is_player:
			sfx.play(&"select", -6.0)


func _buffer(f: Fighter, cmd: StringName) -> void:
	f.buffer_cmd = cmd
	f.buffer_ticks = BUFFER_TICKS


func _try_start_move(f: Fighter) -> void:
	if f.buffer_cmd == &"":
		return
	f.buffer_ticks -= 1
	if f.buffer_ticks < 0:
		f.buffer_cmd = &""
		return
	if f.ko or f.body.is_dashing():
		return
	var next_id: StringName = f.buffer_cmd
	var next: Dictionary = Moves.get_move(next_id, f.kit)
	var next_cat: String = String(next["cat"])

	# Đỡ xong hủy sang L (Combo 5 – Phản Đòn Thị Uy) hoặc sang chiêu phản đòn (Đông Tảo Combo 2).
	if f.react == &"guard":
		if (next_cat != "L" and not next.has("counter")) or f.blockstun() > GUARD_CANCEL_TICKS:
			return
		f.body.clear_hit_reactions()
		f.react = &""
	elif f.locked() or f.react != &"":
		return

	if not f.move.is_empty():
		if f.move.has("air") or _sim_tick - f.contact_tick > Moves.CANCEL_WINDOW_TICKS:
			return
		if not (f.move["cancel"] as Array).has(next_cat):
			return
		var light_limit: int = 3 + (1 if f.dao_chan else 0)
		if next_cat == "L" and f.chain >= light_limit:
			return
		# Chuỗi J J: đòn L thứ hai thành Đá Nhẹ (Combo 1 trong bảng chiêu).
		if next_id == &"mo_nhanh" and f.move["id"] == &"mo_nhanh" and f.chain == 1:
			next_id = &"da_nhe"
			next = Moves.get_move(next_id, f.kit)
	elif f.airborne:
		if not next.has("air") or f.air_used:
			return
	elif next.has("air"):
		return

	var cost: int = int(next.get("cost", 0))
	if cost > 0 and not f.special.can_spend_bars(cost):
		f.buffer_cmd = &""
		if f.is_player:
			hud.popup(f.index, "Chưa đủ thanh nộ (%d vạch)" % cost, Color(0.85, 0.85, 0.85))
		return
	if next_id == &"phun_long" and _has_projectile(f.index):
		f.buffer_cmd = &""
		return
	if cost > 0:
		f.special.spend_bars(cost)

	var cancelled: bool = not f.move.is_empty()
	if next_cat == "L":
		f.chain = f.chain + 1 if cancelled else 1
	elif not cancelled:
		f.chain = 0
	_start_move(f, next)
	if not cancelled and not f.airborne:
		f.body.begin_attack_facing_lock()


func _start_move(f: Fighter, move: Dictionary) -> void:
	f.move = move
	f.mf = 0
	f.mft = 0
	f.loops = 0
	f.loop_req = false
	f.hit_used.clear()
	for i in range((move["hits"] as Array).size()):
		f.hit_used.append(false)
	f.contact_tick = -100
	f.move_started_now = true
	_instance_counter += 1
	f.instance = _instance_counter
	f.buffer_cmd = &""
	f.armor = 1 if move.has("armor") else 0
	f.countered = false
	f.contact_blocked = false
	f.move_start_tick = _sim_tick
	f.run_loops = 0
	if f.airborne:
		f.air_used = true
	match String(move["cat"]):
		"SP":
			f.track["specials"] = int(f.track["specials"]) + 1
			if move["id"] == &"mo_lien_hoan":
				f.track["rush"] = int(f.track["rush"]) + 1
				f.mash = 0
			if move.has("freeze_text"):
				_start_freeze(f, SP_FREEZE_TICKS, String(move["freeze_text"]), false)
		"SUPER":
			f.track["specials"] = int(f.track["specials"]) + 1
			_start_freeze(f, SUPER_FREEZE_TICKS, String(move.get("freeze_text", String(move["name"]).to_upper())), true)


func _start_freeze(f: Fighter, ticks: int, text: String, big: bool) -> void:
	_freeze = ticks
	if cinematics:
		_cine_set(f.body.global_position + Vector2(0, -90), 1.45 if big else 1.2, 1.0)
		hud.letterbox(1.0 if big else 0.55)
		if big:
			sfx.play(&"cheer", -4.0)
			arena.jump_burst()
	f.view.aura = 1.0
	f.view.flash(Color(1.0, 0.95, 0.5), 1.0)
	sfx.play(&"super", 0.0 if big else -4.0, 1.0 if big else 1.3)
	hud.cut_in(f.index, text)
	var tween := arena.create_tween()
	tween.tween_property(arena, "modulate", Color(0.3, 0.28, 0.4) if big else Color(0.55, 0.5, 0.6), 0.1)
	_shake = maxf(_shake, 4.0 if big else 2.0)


func _end_freeze() -> void:
	_cine_weight = 0.0
	hud.letterbox(0.0)
	var tween := arena.create_tween()
	tween.tween_property(arena, "modulate", Color.WHITE, 0.25)


func _step_movement(f: Fighter) -> void:
	var held_mv: int = 0
	var pressed_mv: int = 0
	var dir_bits: int = 0
	f.prox_guard = false
	if f.jump_dir < 0:
		dir_bits = 1 << InputBits.MOVE_LEFT
	elif f.jump_dir > 0:
		dir_bits = 1 << InputBits.MOVE_RIGHT

	# Nhảy hủy Cựa Hất khi đã trúng (Combo 2 – Hất Tung, Mưa Lông).
	if not f.move.is_empty() and (f.move["cancel"] as Array).has("JUMP") \
			and _sim_tick - f.contact_tick <= Moves.CANCEL_WINDOW_TICKS + 4 \
			and (f.tick_pressed & (1 << InputBits.JUMP)) != 0 and not f.airborne:
		_end_move(f)

	if f.ko or f.react != &"":
		pass
	elif not f.move.is_empty():
		if f.airborne:
			held_mv = dir_bits
		elif f.move.has("crouch"):
			held_mv = 1 << InputBits.CROUCH
	elif f.airborne:
		held_mv = dir_bits # GDD 4.2: không đổi hướng giữa không trung
	else:
		held_mv = f.held & MOVE_MASK
		pressed_mv = f.tick_pressed & MOVE_MASK
		# Kit không có hoạt ảnh nhảy/cúi (Đông Tảo): bỏ qua các bit đó cho di chuyển (lệnh vẫn đọc ↓).
		if not bool(f.kdef["can_jump"]):
			held_mv &= ~(1 << InputBits.JUMP)
			pressed_mv &= ~(1 << InputBits.JUMP)
		if not bool(f.kdef["can_crouch"]):
			held_mv &= ~(1 << InputBits.CROUCH)
			pressed_mv &= ~(1 << InputBits.CROUCH)
		# Thiết Giáp: giữ lùi khi đối thủ đang đe dọa thì đứng thủ tại chỗ thay vì lùi.
		f.prox_guard = bool(f.kdef["guard_all_heights"]) and _holding_back(f) and _threatened(f, fighters[1 - f.index])
		if f.prox_guard:
			held_mv &= ~((1 << InputBits.MOVE_LEFT) | (1 << InputBits.MOVE_RIGHT))
			pressed_mv &= ~((1 << InputBits.MOVE_LEFT) | (1 << InputBits.MOVE_RIGHT))
		if (pressed_mv & (1 << InputBits.JUMP)) != 0:
			f.jump_dir = LocomotionStateMachine.horizontal_direction(InputFrame.new(0, held_mv, 0, 0))
			f.air_used = false
	_step_body(f, held_mv, pressed_mv)


func _holding_back(f: Fighter) -> bool:
	var o: Fighter = fighters[1 - f.index]
	var back_bit: int = InputBits.MOVE_LEFT if o.x() > f.x() else InputBits.MOVE_RIGHT
	var forward_bit: int = InputBits.MOVE_RIGHT if back_bit == InputBits.MOVE_LEFT else InputBits.MOVE_LEFT
	return (f.held & (1 << back_bit)) != 0 and (f.held & (1 << forward_bit)) == 0


## Đối thủ đang ra đòn gần đó (chưa qua nhịp đánh cuối) hoặc có đạn đang bay tới.
func _threatened(f: Fighter, o: Fighter) -> bool:
	if not o.move.is_empty() and not (o.move["hits"] as Array).is_empty() and absf(o.x() - f.x()) < 320.0:
		var hits: Array = o.move["hits"]
		if o.mf <= int(hits[hits.size() - 1]["frames"][-1]):
			return true
	for p in projectiles:
		if p.owner == o.index and absf(p.pos.x - f.x()) < 260.0:
			return true
	return false


func _step_body(f: Fighter, held_mv: int, pressed_mv: int) -> void:
	# Mỗi thân dùng bộ đếm tick riêng tăng dần (DashInputBuffer yêu cầu tick tăng nghiêm ngặt).
	f.serial += 1
	f.body.movement_locked = false
	f.body.step_with_input_frame(InputFrame.new(f.serial, held_mv, pressed_mv, 0))
	f.airborne = not f.body.is_on_floor()


func _advance_move(f: Fighter, o: Fighter) -> void:
	if f.move.is_empty():
		return
	if f.move.has("air") and not f.airborne and not f.move_started_now:
		_end_move(f)
		return
	if not f.move_started_now:
		f.mft += 1
	var ticks: Array = f.move["ticks"]
	# Đoạn chạy (Húc Trâu): engine đẩy tới mỗi tick.
	if f.move.has("run"):
		var run: Dictionary = f.move["run"]
		if f.mf >= int(run["frames"][0]) and f.mf <= int(run["frames"][1]):
			var nx: float = f.x() + float(run["speed"]) * float(f.facing())
			f.body.global_position.x = clampf(nx, STAGE_MIN, STAGE_MAX)
			if _sim_tick % 3 == 0:
				f.view.spawn_afterimage(Color(1.0, 0.55, 0.3), 0.22)
				fx.dust(Vector2(f.x(), 0), 3, -float(f.facing()))
	var frame_ticks: int = int(ticks[f.mf])
	# Phản Đòn hụt: hồi lâu ở frame cuối.
	if f.move.has("counter") and not f.countered and f.mf == ticks.size() - 1:
		frame_ticks += int(f.move.get("whiff_hold", 0))
	if f.mft >= frame_ticks:
		f.mft = 0
		if f.move.has("run") and f.mf == int(f.move["run"]["frames"][1]):
			var run_def: Dictionary = f.move["run"]
			if f.run_loops < int(run_def["max_loops"]) - 1 and absf(o.x() - f.x()) > float(run_def["stop_dist"]) \
					and not _near_wall(f):
				f.run_loops += 1
				f.mf = int(run_def["frames"][0])
				return
		if f.move.has("loop") and f.mf == int(f.move["loop"][1]):
			var loop: Array = f.move["loop"]
			var again: bool = rush_clash > 0 or (f.loop_req and f.loops < int(loop[2]) - 1)
			if again:
				f.loops += 1
				f.loop_req = false
				f.mf = int(loop[0])
				for i in range(f.hit_used.size()):
					if bool((f.move["hits"][i] as Dictionary).get("loop", false)):
						f.hit_used[i] = rush_clash > 0
				return
		f.mf += 1
		if f.mf >= ticks.size():
			_end_move(f)
			return
		_on_frame_enter(f, o)
	# Lốc xoáy hút đối thủ vào tâm.
	if f.move.has("pull"):
		var pull: Array = f.move["pull"]
		if f.mf >= int(pull[0]) and f.mf <= int(pull[1]) and not o.ko and absf(o.x() - f.x()) < 340.0 \
				and o.react != &"vang":
			var dir: float = signf(f.x() - o.x())
			var gap: float = absf(o.x() - f.x())
			if gap > 70.0:
				o.body.global_position.x += dir * minf(7.0, gap - 70.0)
	if f.move["cat"] == "SUPER" and _sim_tick % 4 == 0:
		f.view.spawn_afterimage(Color(1.0, 0.8, 0.35), 0.3)
	if f.move["cat"] == "SUPER" and f.mf >= 3 and f.mf <= 8 and _sim_tick % 3 == 0:
		fx.dust(Vector2(f.x() + _fx_rng.randf_range(-120, 120), 0), 3)
		_shake = maxf(_shake, 2.0)


func _on_frame_enter(f: Fighter, o: Fighter) -> void:
	var move: Dictionary = f.move
	if int(move.get("spawn", -1)) == f.mf:
		_spawn_projectile(f)
	if int(move.get("gain_frame", -1)) == f.mf:
		var gain: int = int(float(f.special.get_maximum_points()) * TAUNT_GAIN_RATIO)
		f.special.add_points(gain)
		hud.popup(f.index, "Ò Ó O! +25% NỘ", Color(1.0, 0.6, 0.15))
		sfx.play(&"card", 0.0, 0.6)
		arena.cheer(0.6)
	for hit in move["hits"]:
		if (hit["frames"] as Array).has(f.mf) and int(hit["frames"][0]) == f.mf and f.contact_tick < _sim_tick - 1:
			sfx.play(&"whiff", -10.0, 1.3 if move["cat"] == "L" else 1.0)
			break
	if move["cat"] == "SP" and move["id"] == &"mo_lien_hoan" and f.in_rush_loop():
		f.view.spawn_afterimage(Color(1.0, 0.85, 0.4), 0.18)
	# Sóng chấn / nứt đất (Đông Tảo): chỉ là hình ảnh, xuất hiện cả khi đánh hụt.
	for hit in move["hits"]:
		if int(hit["frames"][0]) == f.mf and hit.has("fx"):
			var box: Rect2 = Moves.world_rect(hit["box"], f.body.global_position, f.facing())
			if String(hit["fx"]) == "quake":
				var radius: float = minf(box.size.x * 0.5, 620.0)
				fx.quake(Vector2(f.x(), 0), radius)
				_shake = maxf(_shake, 7.0 if move["cat"] == "SUPER" else 4.5)
				sfx.play(&"hit_special", -3.0, 0.55)
			else:
				fx.shock(Vector2(box.get_center().x, 0), box.size.x * 0.6, f.facing())
				_shake = maxf(_shake, 2.0)
				sfx.play(&"land", 0.0, 0.6)
	if move.has("invuln") and f.mf == int(move["invuln"][0]):
		fx.dust(Vector2(f.x(), 0), 14)
		sfx.play(&"jump", -2.0, 0.6)
	if move.has("run") and f.mf == int(move["hits"][0]["frames"][0]):
		_shake = maxf(_shake, 2.5)


func _end_move(f: Fighter) -> void:
	if f.move.is_empty():
		return
	var was_air: bool = f.move.has("air")
	f.move = {}
	f.view.aura = 0.0
	if not was_air and not f.airborne:
		f.body.finish_attack_facing_recovery()


# =================================================================== đạn lông

func _has_projectile(owner: int) -> bool:
	for p in projectiles:
		if p.owner == owner:
			return true
	return false


func _spawn_projectile(f: Fighter) -> void:
	var p := Projectile.new()
	p.owner = f.index
	p.dir = f.facing()
	p.pos = f.body.global_position + Vector2(88.0 * float(p.dir), -70.0)
	p.node = Sprite2D.new()
	p.node.texture = FighterView.SHEET
	p.node.region_enabled = true
	p.node.centered = false
	p.node.offset = -Vector2(40, 53)
	p.node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.node.material = FighterView.make_material(f.view.hue, f.view.saturation, f.kit, f.view.colors)
	p.node.z_index = 3
	_stage.add_child(p.node)
	projectiles.append(p)
	sfx.play(&"dash", -2.0, 1.6)


func _advance_projectiles() -> void:
	for p in projectiles:
		p.pos.x += PROJECTILE_SPEED * float(p.dir)
		p.t += 1
		if p.cooldown > 0:
			p.cooldown -= 1
	# Đạn chạm đạn: triệt tiêu.
	if projectiles.size() >= 2:
		for a in projectiles:
			for b in projectiles:
				if a != b and a.owner != b.owner and a.hits_left > 0 and b.hits_left > 0 and a.box().intersects(b.box()):
					fx.hit_spark((a.pos + b.pos) * 0.5, 4, 1)
					sfx.play(&"block", -2.0, 1.4)
					a.hits_left = 0
					b.hits_left = 0
	for p in projectiles:
		var target: Fighter = fighters[1 - p.owner]
		var hurt: Rect2 = _hurtbox(target)
		if p.hits_left > 0 and p.cooldown == 0 and hurt.has_area() and p.box().intersects(hurt):
			var last: bool = p.hits_left == 1
			var hit: Dictionary = {"dmg": 3, "react": &"nang" if last else &"nhe", "level": Moves.Level.MID,
				"kb": 30.0 if last else 6.0, "hitstop": 4 if last else 2}
			_resolve_hit(fighters[p.owner], target, hit, {"cat": "PROJ", "id": &"long_phi"}, p.box().intersection(hurt).get_center())
			p.hits_left -= 1
			p.cooldown = 4
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Projectile = projectiles[i]
		if p.hits_left <= 0 or p.pos.x < -150.0 or p.pos.x > 1150.0:
			p.node.queue_free()
			projectiles.remove_at(i)


func _update_projectile_views() -> void:
	for p in projectiles:
		p.node.position = p.pos
		p.node.region_rect = FighterView.frame_region(FighterView.tag_frame_at("FX_LongPhi", p.t))
		p.node.scale = Vector2(FighterView.SCALE * float(p.dir), FighterView.SCALE)


# =================================================================== va chạm

func _hurtbox(f: Fighter) -> Rect2:
	if f.ko or f.invuln > 0:
		return Rect2()
	match f.react:
		&"te":
			if f.react_t > 6:
				return Rect2()
		&"nam", &"vang_land":
			return Rect2()
		&"vang":
			if f.juggle >= JUGGLE_LIMIT or not f.airborne:
				return Rect2()
	if f.move.has("invuln") and f.mf >= int(f.move["invuln"][0]) and f.mf <= int(f.move["invuln"][1]):
		return Rect2() # Thái Sơn Áp Đỉnh: bất tử khi bay lên
	var local: Rect2 = f.kdef["hurt_stand"]
	if f.airborne:
		local = f.kdef["hurt_air"]
	elif f.crouching() or f.move.has("crouch"):
		local = f.kdef["hurt_crouch"]
	return Moves.world_rect(local, f.body.global_position, f.facing())


## Chân/mỏ đang vươn ra cũng có thể bị đánh trúng (đòn hụt bị trừng phạt).
func _limb_box(f: Fighter) -> Rect2:
	if f.move.is_empty() or f.invuln > 0 or f.react != &"" or (f.move["hits"] as Array).is_empty():
		return Rect2()
	if f.mf < int(f.move["hits"][0]["frames"][0]) or f.move["cat"] == "SUPER":
		return Rect2()
	var first: Dictionary = f.move["hits"][0]
	if (first["box"] as Rect2).position.x < 0.0 or first.has("counter_only"):
		return Rect2() # sóng chấn hai phía / quạt phản đòn không phải "chân vươn ra"
	var box: Rect2 = first["box"]
	var limb := Rect2(box.position + Vector2(8, 6), box.size - Vector2(24, 12))
	return Moves.world_rect(limb, f.body.global_position, f.facing())


## Hitbox đang hoạt động: [chỉ số nhịp, Rect2] hoặc [].
func _active_hit(f: Fighter) -> Array:
	if f.move.is_empty():
		return []
	var hits: Array = f.move["hits"]
	for i in range(hits.size()):
		if not f.hit_used[i] and (hits[i]["frames"] as Array).has(f.mf):
			if bool(hits[i].get("counter_only", false)) and not f.countered:
				continue
			if bool(hits[i].get("ground_only", false)) and fighters[1 - f.index].airborne:
				continue # sóng chấn mặt đất không trúng đối thủ đang nhảy
			return [i, Moves.world_rect(hits[i]["box"], f.body.global_position, f.facing())]
	return []


func _detect_contacts() -> void:
	var active: Array = [_active_hit(fighters[0]), _active_hit(fighters[1])]
	# Va chạm đòn (GDD 4.8 MVP): hai hitbox thường chạm nhau thì triệt tiêu.
	if not active[0].is_empty() and not active[1].is_empty() and rush_clash == 0 \
			and fighters[0].move_cat() in ["L", "M", "H"] and fighters[1].move_cat() in ["L", "M", "H"] \
			and (active[0][1] as Rect2).intersects(active[1][1]):
		_clash((active[0][1] as Rect2).intersection(active[1][1]).get_center(), active)
		return
	var hits: Array = []
	for i in range(2):
		if active[i].is_empty():
			continue
		var target: Fighter = fighters[1 - i]
		var box: Rect2 = active[i][1]
		var contact := Rect2()
		var hurt: Rect2 = _hurtbox(target)
		var limb: Rect2 = _limb_box(target)
		if hurt.has_area() and box.intersects(hurt):
			contact = box.intersection(hurt)
		elif limb.has_area() and box.intersects(limb):
			contact = box.intersection(limb)
		if contact.has_area():
			hits.append([i, int(active[i][0]), fighters[i].move, contact.get_center()])
	for hit in hits:
		var attacker: Fighter = fighters[int(hit[0])]
		var move: Dictionary = hit[2]
		attacker.hit_used[int(hit[1])] = true
		attacker.contact_tick = _sim_tick
		_resolve_hit(attacker, fighters[1 - int(hit[0])], move["hits"][int(hit[1])], move, hit[3])


func _clash(point: Vector2, active: Array) -> void:
	for f in fighters:
		f.hit_used[int(active[f.index][0])] = true
		f.contact_tick = -100 # hai đòn mất tác dụng, không được cancel
		var away: int = -1 if f.x() < fighters[1 - f.index].x() else 1
		f.body.apply_knockback(CLASH_PUSH_PX, 10, away)
		f.view.flash(Color.WHITE, 0.8)
	fx.hit_spark(point, 4, 1)
	sfx.play(&"block", 0.0, 0.7)
	sfx.play(&"hit_light", -4.0, 0.6)
	hud.announce("VA CHẠM!", 30, Color(1, 1, 1), 0.8)
	_hitstop = 8
	_shake = maxf(_shake, 3.0)


## Rush đối đầu: hai Mổ Liên Hoàn chạm nhau → ai bấm H nhiều hơn trong 1,5 s thắng.
func _update_rush_clash() -> void:
	var a: Fighter = fighters[0]
	var b: Fighter = fighters[1]
	if rush_clash == 0:
		if a.in_rush_loop() and b.in_rush_loop() and absf(a.x() - b.x()) < 300.0:
			rush_clash = RUSH_CLASH_TICKS
			a.mash = 0
			b.mash = 0
			for f in fighters:
				for i in range(f.hit_used.size()):
					f.hit_used[i] = bool((f.move["hits"][i] as Dictionary).get("loop", false))
			hud.announce("ĐỐI ĐẦU!", 50, Color(1.0, 0.5, 0.2), 1.3)
			hud.hint = "BẤM H LIÊN TỤC!"
			sfx.play(&"super", -2.0, 1.5)
		return
	rush_clash -= 1
	if _sim_tick % 4 == 0:
		fx.hit_spark(Vector2((a.x() + b.x()) * 0.5, -80.0 + _fx_rng.randf_range(-20, 20)), 0, 1)
		sfx.play(&"hit_light", -8.0, _fx_rng.randf_range(1.0, 1.4))
		_shake = maxf(_shake, 1.5)
	if rush_clash > 0 and a.in_rush_loop() and b.in_rush_loop():
		return
	rush_clash = 0
	hud.hint = ""
	var win: Fighter = a if a.mash >= b.mash else b
	var lose: Fighter = b if win == a else a
	hud.announce("%s THẮNG ĐỐI ĐẦU!" % String(win.side["name"]).to_upper(), 50, Color(1.0, 0.85, 0.3))
	_end_move(lose)
	if not win.move.is_empty() and win.move.has("loop"):
		win.mf = int(win.move["loop"][1]) + 1
		win.mft = 0
		win.hit_used[win.hit_used.size() - 1] = false
	lose.body.apply_knockback(40.0, 8, -1 if lose.x() < win.x() else 1)


func _guard_result(t: Fighter, a: Fighter, hit: Dictionary, move: Dictionary) -> int:
	if bool(move.get("unblockable", false)):
		return 0
	if not t.move.is_empty() or t.ko or t.airborne or not (t.react in [&"", &"guard"]):
		return 0
	var back_bit: int = InputBits.MOVE_LEFT if a.x() > t.x() else InputBits.MOVE_RIGHT
	var forward_bit: int = InputBits.MOVE_RIGHT if back_bit == InputBits.MOVE_LEFT else InputBits.MOVE_LEFT
	if (t.held & (1 << back_bit)) == 0 or (t.held & (1 << forward_bit)) != 0:
		return 0
	if t.body.is_dashing() and signf(t.body.velocity.x) == signf(a.x() - t.x()):
		return 0 # Forward Dash không đỡ được
	if USE_HIGH_LOW_GUARD and not bool(t.kdef["guard_all_heights"]):
		var crouched: bool = (t.held & (1 << InputBits.CROUCH)) != 0
		var level: int = int(hit["level"])
		if level == Moves.Level.HIGH and crouched:
			return 0
		if level == Moves.Level.LOW and not crouched:
			return 0
	return 1 if t.guard > _guard_cost(t, String(move["cat"])) else 2


func _guard_cost(t: Fighter, cat: String) -> float:
	var cost: float = float(GUARD_COST.get(cat, 10.0))
	if t.body.breed == MovementConfig.Breed.GA_NOI:
		cost *= 0.9 # passive Bền Bỉ
	return cost * float(t.kdef["guard_cost_mult"]) # Thiết Giáp đỡ mọi tầng nhưng tốn gauge hơn


func _near_wall(f: Fighter) -> bool:
	return f.x() <= STAGE_MIN + 6.0 or f.x() >= STAGE_MAX - 6.0


func _resolve_hit(a: Fighter, t: Fighter, hit: Dictionary, move: Dictionary, point: Vector2) -> void:
	var cat: String = String(move["cat"])
	var react: StringName = hit["react"]
	var direction: int = 1 if t.x() >= a.x() else -1
	if is_equal_approx(t.x(), a.x()):
		direction = a.facing()

	# Phản Đòn: bị đánh trong cửa sổ thì hóa giải đòn và quạt lại (không bắt được siêu chiêu).
	if t.move.has("counter") and not t.countered and cat != "SUPER" and not bool(move.get("unblockable", false)):
		var window: Array = t.move["counter"]
		if t.mf >= int(window[0]) and t.mf <= int(window[1]):
			_counter(t, a, point)
			return

	# Công thức 2.
	var knockback: float = float(hit["kb"]) * sqrt(3.0 / float(t.stats["weight"]))
	if cat == "H" or cat == "M":
		if a.cards != null:
			knockback *= a.cards.get_heavy_knockback_multiplier()
		if a.dao_chan:
			knockback *= 0.9
	if t.mao_sat and int(hit["level"]) == Moves.Level.HIGH:
		knockback *= 0.8

	var guard: int = _guard_result(t, a, hit, move)
	a.contact_blocked = guard == 1
	if guard == 1:
		t.guard -= _guard_cost(t, cat)
		t.guard_delay = GUARD_REGEN_DELAY_TICKS
		if t.hp() > CHIP_DAMAGE:
			t.damage_taken += int(t.health.call("apply_damage", CHIP_DAMAGE))
		var blockstun: int = int(Moves.BLOCKSTUN.get(cat, 12))
		t.body.clear_hit_reactions()
		t.body.apply_blockstun(blockstun)
		t.react = &"guard"
		t.react_t = 0
		var push: float = maxf(knockback * 0.5, 8.0)
		var keep: float = float(t.kdef["guard_push"]) # Thiết Giáp: gần như không bị đẩy, người đánh bật ra
		if _near_wall(t):
			a.body.apply_knockback(push, blockstun, -direction)
		elif keep < 1.0:
			t.body.apply_knockback(maxf(push * keep, 4.0), blockstun, direction)
			a.body.apply_knockback(push * (1.0 - keep), blockstun, -direction)
		else:
			t.body.apply_knockback(push, blockstun, direction)
		t.special.add_points(3)
		t.view.shield_ticks = 6
		t.view.flash(Color(0.45, 0.7, 1.0), 0.7)
		fx.hit_spark(point, 3, direction)
		sfx.play(&"block")
		_hitstop = maxi(_hitstop, int(hit["hitstop"]))
		if t.is_player:
			t.track["blocks"] = int(t.track["blocks"]) + 1
		return

	if guard == 2:
		t.guard = 0.0
		t.break_pending = true
		react = &"te" # GDD Bảng 4.8: vỡ thủ thì ngã
		hud.popup(t.index, "PHÁ THỦ!", Color(1.0, 0.5, 0.2))
		sfx.play(&"guard_break")
		if cinematics:
			hud.announce("PHÁ THỦ!", 45, Color(0.55, 0.8, 1.0), 1.3)
			hud.flash(Color(0.55, 0.8, 1.0), 0.55)
			_zoom_punch = maxf(_zoom_punch, 0.08)
			arena.jump_burst()

	# Tung hứng: đối thủ đang bị hất trên không.
	var juggling: bool = t.react == &"vang" and t.airborne
	if juggling:
		if t.juggle >= JUGGLE_LIMIT:
			return
		t.juggle += 1
	elif t.airborne and react != &"vang":
		react = &"vang" # trúng đòn khi đang nhảy thì rơi xuống

	# Công thức 1 (hệ số đòn = sát thương bảng chiêu / 10).
	var atk: float = float(a.stats["atk"])
	if a.cards != null:
		atk *= a.cards.get_attack_damage_multiplier()
	var defense: float = float(t.stats["def"]) + (2.0 if t.mao_sat else 0.0)
	var damage: float = maxf(1.0, atk - defense) * float(hit["dmg"]) / 10.0
	var crit: bool = cat in ["L", "M", "H"] and _rng.randf() < float(a.stats["crit"])
	if crit:
		damage *= CRIT_MULTIPLIER
	if t.cards != null:
		damage *= t.cards.get_incoming_damage_multiplier()
	if juggling:
		damage *= 0.7 # giảm sát thương khi tung hứng
	# Giảm sát thương theo độ dài combo (kiểu game đối kháng): mỗi nhịp −5%, tối thiểu 50%.
	if t.react in [&"nhe", &"nang", &"vang"]:
		damage *= maxf(0.5, 1.0 - 0.05 * float(a.combo_hits))

	# Giáp (Húc Trâu đang chạy / Đông Tảo đứng dậy f7–f10): chịu đúng 1 đòn, vẫn mất máu, không bị ngắt.
	var armored: bool = guard == 0 and not juggling and (
		(t.react == &"" and t.armor > 0 and t.move.has("armor")
			and t.mf >= int(t.move["armor"][0]) and t.mf <= int(t.move["armor"][1]))
		or (t.react == &"dung" and t.wake_armor > 0 and t.invuln == 0))
	if armored and maxi(1, int(round(damage))) < t.hp():
		_absorb_hit(a, t, hit, move, maxi(1, int(round(damage))), point, direction)
		return

	# Trình diễn: trúng lúc đối thủ đang khởi động đòn = COUNTER, lúc đang hồi đòn = PUNISH.
	var t_info: Dictionary = _move_info(t)
	var counter_hit: bool = t.react == &"" and bool(t_info["attacking"]) and int(t_info["to_active"]) > 0
	var punish_hit: bool = t.react == &"" and bool(t_info["recovering"])

	var hit_data: AttackData = AttackCatalog.get_attack(&"light" if cat == "L" else &"heavy")
	hit_data.base_damage = maxi(1, int(round(damage)))
	hit_data.hitstun_ticks = -1
	hit_data.down_duration_ticks = -1
	match react:
		&"nhe", &"nang":
			hit_data.hitstun_ticks = int(Moves.REACTIONS[react]["stun"])
		&"te":
			hit_data.down_duration_ticks = int(t.kdef["te_ticks"]) + Moves.DOWN_TICKS
		&"vang":
			hit_data.down_duration_ticks = 400 # tới khi chạm đất
	var combo_continues: bool = t.react in [&"nhe", &"nang", &"vang"]
	var hp_before: int = t.hp()
	t.body.clear_hit_reactions()
	a.body._on_hit_confirmed(StringName(a.body.name), a.instance, hit_data, t.body.get_hurtbox())
	var dealt: int = hp_before - t.hp()
	t.damage_taken += dealt
	hit_log.append([_sim_tick, a.index, String(move.get("id", "")), String(react), dealt])

	_end_move(t)
	t.buffer_cmd = &""
	t.chain = 0
	t.react = react
	t.react_t = 0
	if not t.alive():
		react = &"vang"
		t.react = &"vang"
	match t.react:
		&"vang":
			var launch: float = float(hit.get("launch", 260.0))
			if juggling:
				launch = 380.0
			elif not t.alive():
				launch = maxf(launch, 520.0)
			t.body.apply_launch(launch)
			t.body.apply_knockback(maxf(knockback, 60.0), 36, direction)
			if not juggling:
				t.juggle = 0
		&"te":
			t.body.apply_knockback(knockback, 24, direction)
		_:
			var stun: int = int(Moves.REACTIONS.get(react, {"stun": 20})["stun"])
			if _near_wall(t):
				a.body.apply_knockback(knockback * 0.6, maxi(stun / 2, 6), -direction)
			else:
				t.body.apply_knockback(knockback, stun, direction)

	a.combo_hits = a.combo_hits + 1 if combo_continues else 1
	a.combo_damage = a.combo_damage + dealt if combo_continues else dealt
	a.track["max_combo"] = maxi(int(a.track["max_combo"]), a.combo_hits)
	if a.combo_hits >= 2:
		hud.combo(a.index, a.combo_hits, a.combo_damage)

	# PLACEHOLDER: đòn thường nạp nộ theo sát thương; chiêu đặc biệt/siêu chiêu/đạn chỉ nạp rất ít để không tự hoàn vạch.
	a.special.add_points(4 + dealt if cat in ["L", "M", "H"] else 1)
	t.special.add_points(2 + dealt / 2)
	var weight: int = 0
	if cat in ["M", "H"] or react == &"nang":
		weight = 1
	if react in [&"vang", &"te"] and cat != "L":
		weight = 2
	fx.hit_spark(point, weight, direction, 0.8 + minf(float(dealt) / 14.0, 1.4))
	t.view.flash(Color(1, 1, 1), 1.0)
	_hitstop = maxi(_hitstop, int(hit["hitstop"]))
	arena.cheer(0.15 + 0.25 * float(weight))
	_last_hit_point = point
	_shake_dir = Vector2(float(direction), -0.3).normalized()
	if weight >= 1:
		_zoom_punch = maxf(_zoom_punch, 0.02 * float(weight) + minf(float(dealt) * 0.002, 0.04))
	if cinematics:
		if counter_hit:
			hud.popup(t.index, "COUNTER!", Color(1.0, 0.45, 0.3))
			hud.flash(Color(1.0, 0.85, 0.5), 0.22)
		elif punish_hit:
			hud.popup(t.index, "PUNISH!", Color(1.0, 0.75, 0.3))
		if a.combo_hits == 3:
			sfx.play(&"cheer", -5.0)
			arena.jump_burst()
		elif react in [&"te", &"vang"] and cat != "L":
			arena.jump_burst()
	match weight:
		0:
			sfx.play(&"hit_light", -2.0 if cat == "SP" else 0.0, _fx_rng.randf_range(0.95, 1.15))
		1:
			sfx.play(&"hit_heavy")
			_shake = maxf(_shake, 2.5)
		2:
			sfx.play(&"hit_special")
			_shake = maxf(_shake, 4.0)
	if crit:
		hud.popup(t.index, "CHÍ MẠNG!", Color(1.0, 0.9, 0.3))
	if a.is_player:
		match cat:
			"L":
				a.track["l_hits"] = int(a.track["l_hits"]) + 1
			"M":
				a.track["m_hits"] = int(a.track["m_hits"]) + 1
			"H":
				a.track["h_hits"] = int(a.track["h_hits"]) + 1
	if mode == &"tutorial":
		_tutorial_protect()
	if overtime and t.alive() and phase == Phase.FIGHT:
		_round_decided(a.index, "TRÚNG ĐÒN TRƯỚC!")


## Phản Đòn bắt được đòn: hóa giải, nhảy tới frame quạt cánh (nhịp counter_only giờ có hiệu lực).
func _counter(t: Fighter, a: Fighter, point: Vector2) -> void:
	t.countered = true
	t.mf = int(t.move["active"])
	t.mft = 0
	for i in range(t.hit_used.size()):
		t.hit_used[i] = false
	t.track["counters"] = int(t.track["counters"]) + 1
	t.view.flash(Color(1.0, 0.95, 0.6), 1.0)
	t.view.shield_ticks = 8
	fx.hit_spark(point, 4, 1 if a.x() > t.x() else -1)
	sfx.play(&"block", 0.0, 0.8)
	sfx.play(&"card", -4.0, 0.7)
	hud.popup(t.index, "PHẢN ĐÒN!", Color(1.0, 0.85, 0.3))
	_hitstop = maxi(_hitstop, 10)
	_shake = maxf(_shake, 3.0)
	_on_counter_flash()


## Đòn trúng nhưng bị giáp hấp thụ: mất máu, không phản ứng, không ngắt chiêu.
func _absorb_hit(a: Fighter, t: Fighter, hit: Dictionary, move: Dictionary, amount: int, point: Vector2, direction: int) -> void:
	if t.react == &"dung":
		t.wake_armor -= 1
	else:
		t.armor -= 1
	var dealt: int = int(t.health.call("apply_damage", amount))
	t.damage_taken += dealt
	t.track["armor"] = int(t.track["armor"]) + 1
	hit_log.append([_sim_tick, a.index, String(move.get("id", "")), "armor", dealt])
	a.special.add_points(4 + dealt if String(move["cat"]) in ["L", "M", "H"] else 1)
	t.special.add_points(2 + dealt / 2)
	a.combo_hits = 0
	t.view.flash(Color(1.0, 0.55, 0.3), 0.9)
	t.view.shield_ticks = 6
	fx.hit_spark(point, 3, direction)
	fx.hit_spark(point, 0, direction)
	sfx.play(&"block", 0.0, 0.6)
	sfx.play(&"hit_heavy", -6.0, 0.8)
	hud.popup(t.index, "GIÁP!", Color(1.0, 0.6, 0.3))
	_hitstop = maxi(_hitstop, int(hit["hitstop"]))
	_shake = maxf(_shake, 2.0)
	if overtime and phase == Phase.FIGHT and t.alive():
		_round_decided(a.index, "TRÚNG ĐÒN TRƯỚC!")


func _on_counter_flash() -> void:
	pass


func _separate_pushboxes() -> void:
	var a: Fighter = fighters[0]
	var b: Fighter = fighters[1]
	if absf(a.body.global_position.y - b.body.global_position.y) > 70.0:
		return # nhảy qua đầu (Bảng 4.13: pushbox tắt khi nhảy)
	if a.react in [&"nam", &"te"] or b.react in [&"nam", &"te"]:
		return
	var dx: float = b.x() - a.x()
	var overlap: float = a.push_half() + b.push_half() - absf(dx)
	if overlap <= 0.0:
		return
	var dir: float = signf(dx)
	if dir == 0.0:
		dir = 1.0 if a.facing() > 0 else -1.0
	var ax: float = a.x() - dir * overlap * 0.5
	var bx: float = b.x() + dir * overlap * 0.5
	if ax < STAGE_MIN or ax > STAGE_MAX:
		var clamped: float = clampf(ax, STAGE_MIN, STAGE_MAX)
		bx += dir * absf(ax - clamped)
		ax = clamped
	if bx < STAGE_MIN or bx > STAGE_MAX:
		var clamped_b: float = clampf(bx, STAGE_MIN, STAGE_MAX)
		ax -= dir * absf(bx - clamped_b)
		bx = clamped_b
	a.body.global_position.x = ax
	b.body.global_position.x = bx


func _post_step(f: Fighter, o: Fighter) -> void:
	f.react_t += 1
	# Cất cánh / tiếp đất.
	if not f.was_airborne and f.airborne:
		f.jump_serial += 1
	if not f.was_airborne and f.airborne and f.react == &"":
		sfx.play(&"jump", -6.0)
		fx.dust(Vector2(f.x(), 0), 6)
	elif f.was_airborne and not f.airborne:
		sfx.play(&"land", -4.0)
		fx.dust(Vector2(f.x(), 0), 8)
		f.air_used = false
		f.jump_dir = 0
		if f.move.has("air"):
			_end_move(f)
		if f.react == &"vang":
			# Đập đất nảy lên rồi nằm (VANG_RaXa f9–f11 → NAM_Dat).
			f.react = &"vang_land"
			f.react_t = 0
			f.body.clear_hit_reactions()
			f.body.apply_down(int(f.kdef["vang_land_ticks"]) + Moves.DOWN_TICKS)
			fx.dust(Vector2(f.x(), 0), 16)
			_shake = maxf(_shake, 3.0)
			sfx.play(&"land", 0.0, 0.7)

	# Chuỗi phản ứng.
	match f.react:
		&"nhe", &"nang":
			if f.hitstun() == 0:
				f.react = &""
		&"guard":
			if f.blockstun() == 0:
				f.react = &""
		&"te":
			if f.react_t >= int(f.kdef["te_ticks"]):
				f.react = &"nam"
				f.react_t = 0
				fx.dust(Vector2(f.x(), 0), 10)
		&"vang_land":
			if f.react_t >= int(f.kdef["vang_land_ticks"]):
				f.react = &"nam"
				f.react_t = 0
		&"nam":
			if not f.down() and not f.ko:
				f.react = &"dung"
				f.react_t = 0
				f.invuln = int(f.kdef["wake_invuln"])
				f.wake_armor = int(f.kdef["wake_armor"])
				f.body.apply_hitstun(int(f.kdef["wake_ticks"]))
				if f.break_pending:
					f.break_pending = false
					f.guard = GUARD_AFTER_BREAK
		&"dung":
			if f.hitstun() == 0:
				f.react = &""
				f.wake_armor = 0
	if f.invuln > 0:
		f.invuln -= 1

	# Dash.
	var dashing: bool = f.body.is_dashing()
	if dashing and not f.was_dashing:
		sfx.play(&"dash", -4.0)
		fx.dust(Vector2(f.x(), 0), 6, -signf(f.body.velocity.x))
	if dashing and _sim_tick % 3 == 0:
		f.view.spawn_afterimage(Color(0.7, 0.85, 1.0), 0.2)
	f.was_dashing = dashing

	# Hồi Block Gauge.
	if not f.break_pending:
		if f.guard_delay > 0:
			f.guard_delay -= 1
		else:
			f.guard = minf(GUARD_MAX, f.guard + GUARD_REGEN_PER_TICK)

	if not (o.react in [&"nhe", &"nang", &"vang", &"vang_land", &"te"]):
		f.combo_hits = 0
		f.combo_damage = 0

	if not f.alive() and not f.ko:
		f.ko = true
		_end_move(f)


func _update_objectives() -> void:
	var p: Fighter = fighters[0]
	match mode:
		&"tutorial":
			match tutorial_step:
				0:
					objectives[0]["value"] = mini(int(p.track["l_hits"]), 3)
					objectives[1]["value"] = mini(int(p.track["m_hits"]), 1)
					if int(objectives[0]["value"]) >= 3 and int(objectives[1]["value"]) >= 1:
						_next_tutorial_step([{"text": "Đỡ 2 đòn: giữ phím LÙI (ngược hướng đối thủ)", "goal": 2, "value": 0}],
							EnemyAI.Mode.SLOW_ATTACK, "Thấy nó sắp mổ thì kéo ngược ra sau, vậy là đỡ được rồi.", "GIỎI LẮM!")
						p.track["blocks"] = 0
				1:
					objectives[0]["value"] = mini(int(p.track["blocks"]), 2)
					if int(objectives[0]["value"]) >= 2:
						_next_tutorial_step([{"text": "Nối combo 3 đòn: J → J → K (→ L)", "goal": 3, "value": 0}],
							EnemyAI.Mode.IDLE, "Bấm đòn kế tiếp ngay khi đòn trước vừa trúng.", "ĐỠ CHUẨN!")
						p.track["max_combo"] = 0
				2:
					objectives[0]["value"] = mini(int(p.track["max_combo"]), 3)
					if int(objectives[0]["value"]) >= 3:
						p.special.add_points(p.special.get_points_per_bar() * 2)
						p.track["rush"] = 0
						_next_tutorial_step([{"text": "Nhấn H: Mổ Liên Hoàn – bấm H liên tục để kéo dài", "goal": 1, "value": 0}],
							EnemyAI.Mode.PASSIVE, "Thanh nộ đã có 2 vạch. ← + H là Lốc Xoáy Cánh (2 vạch)!", "COMBO ĐẸP!")
				3:
					objectives[0]["value"] = mini(int(p.track["rush"]), 1)
					if int(objectives[0]["value"]) >= 1 and p.move.is_empty() and _hitstop == 0:
						tutorial_step = 4
						hud.hint = ""
						_finish(0, "HOÀN THÀNH!")
		&"friendly":
			objectives[0]["value"] = mini(int(p.track["cards"]), 1)


func _next_tutorial_step(new_objectives: Array[Dictionary], ai_mode: int, hint: String, banner: String) -> void:
	tutorial_step += 1
	objectives = new_objectives
	fighters[1].ai.script_mode = ai_mode
	hud.hint = hint
	hud.announce(banner, 40, Color(0.6, 1.0, 0.6))
	sfx.play(&"confirm")


func _tutorial_protect() -> void:
	for f in fighters:
		if f.hp() < 20:
			f.health.call("heal", 40)


func _check_end() -> void:
	if phase != Phase.FIGHT:
		return
	var p_alive: bool = fighters[0].alive()
	var o_alive: bool = fighters[1].alive()
	if not p_alive or not o_alive:
		_begin_ko(0 if p_alive else 1)
		return
	if mode == &"tutorial" or clock_ticks > 0:
		return
	var pr: float = fighters[0].hp_ratio()
	var opr: float = fighters[1].hp_ratio()
	if not overtime:
		if not is_equal_approx(pr, opr):
			_round_decided(0 if pr > opr else 1, "HẾT GIỜ!")
		else:
			overtime = true
			clock_ticks = OVERTIME_TICKS
			hud.announce("HIỆP PHỤ!", 70, Color(1.0, 0.6, 0.2))
			hud.hint = "Bên trúng đòn trước thắng"
	else:
		_round_decided(0 if fighters[0].damage_taken <= fighters[1].damage_taken else 1, "HẾT GIỜ!")


## Ghi một hiệp thắng; trả về true nếu trận đã có người thắng.
func _award_round(win_index: int, reason: String) -> bool:
	round_wins[win_index] += 1
	round_log.append({"winner": win_index, "ticks": _round_ticks, "frames": _round_frames, "reason": reason,
		"hp": [fighters[0].hp_ratio(), fighters[1].hp_ratio()]})
	_match_ticks += _round_ticks
	winner = win_index
	return round_wins[win_index] >= rounds_to_win


## Đòn quyết định hiệp: quay chậm + zoom vào điểm trúng (dài và kịch tính hơn ở đòn kết thúc trận).
func _begin_ko(win_index: int) -> void:
	_match_point_final = _award_round(win_index, "KO")
	phase = Phase.KO
	_phase_ticks = 0
	_hitstop = 0
	_freeze = 0
	rush_clash = 0
	hud.hint = ""
	for f in fighters:
		if f.alive():
			_end_move(f)
	if not cinematics:
		return
	sfx.play(&"ko")
	sfx.play(&"hit_special", -2.0, 0.8)
	sfx.play(&"cheer", 0.0)
	arena.cheer(1.0)
	arena.jump_burst()
	_shake = 6.0
	_zoom_punch = 0.12
	hud.flash(Color(1, 1, 1), 0.85)
	_cine_set(_last_hit_point + Vector2(0, -20), 1.75 if _match_point_final else 1.5, 1.0)
	fx.time_scale = 1.0 / float(_ko_slow_factor())
	if _match_point_final:
		hud.announce("HẠ ĐO VÁN!", 200, Color(1.0, 0.3, 0.2), 2.3)
		hud.grade(0.85)
		var tween := arena.create_tween()
		tween.tween_property(arena, "modulate", Color(0.75, 0.62, 0.5), 0.2)
	else:
		hud.announce("K.O.!", 120, Color(1.0, 0.3, 0.2), 2.2)


func _ko_slow_factor() -> int:
	return 4 if _match_point_final else 3


func _ko_tick() -> void:
	if not cinematics:
		_outro_step()
		if _phase_ticks >= 2:
			_enter_round_end("")
		return
	# Quay chậm bằng cách chỉ bước thân gà 1/3 (1/4 ở đòn kết thúc trận) số tick – không đổi kết quả mô phỏng.
	var slow_ticks: int = 150 if _match_point_final else 105
	var factor: int = _ko_slow_factor()
	if _phase_ticks <= slow_ticks:
		if _phase_ticks % factor == 0:
			_outro_step()
	else:
		fx.time_scale = 1.0
		_outro_step()
		_cine_weight = maxf(0.0, _cine_weight - 0.03)
	var hold: int = 70 if _match_point_final else 25
	if _phase_ticks >= slow_ticks + hold:
		fx.time_scale = 1.0
		_enter_round_end("")


## Hiệp kết thúc không bằng K.O. (hết giờ / hiệp phụ).
func _round_decided(win_index: int, reason: String) -> void:
	_match_point_final = _award_round(win_index, reason)
	_hitstop = 0
	_freeze = 0
	rush_clash = 0
	hud.hint = ""
	for f in fighters:
		_end_move(f)
	if cinematics:
		hud.announce(reason, 80, Color(1.0, 0.85, 0.3), 1.6)
		sfx.play(&"bell")
		sfx.play(&"cheer", -3.0)
		arena.cheer(0.8)
	_enter_round_end(reason)


func _enter_round_end(_reason: String) -> void:
	phase = Phase.ROUND_END
	_phase_ticks = 0
	if not cinematics:
		return
	var w: Fighter = fighters[winner]
	var callout: String = ""
	if w.damage_taken == 0:
		callout = "HOÀN HẢO!"
	elif w.hp_ratio() <= 0.2:
		callout = "LỘI NGƯỢC DÒNG!"
	if callout != "":
		hud.callout(callout, 110)
	arena.cheer(1.0)
	arena.jump_burst()


func _round_end_tick() -> void:
	_outro_step()
	_cine_weight = maxf(0.0, _cine_weight - 0.04)
	var length: int = 110 if cinematics else 1
	if _phase_ticks == 20 and cinematics and not _match_point_final:
		hud.announce("%s THẮNG HIỆP %d" % [String(fighters[winner].side["name"]).to_upper(), round_index], 80,
			Color(1.0, 0.85, 0.3) if winner == 0 else Color(0.85, 0.85, 0.95), 1.0)
	if _phase_ticks >= length:
		if _match_point_final or round_index >= max_rounds:
			if round_wins[0] == round_wins[1]:
				winner = 0 if fighters[0].hp_ratio() >= fighters[1].hp_ratio() else 1
			else:
				winner = 0 if round_wins[0] > round_wins[1] else 1
			phase = Phase.END
			_phase_ticks = 0 if cinematics else 189
			hud.grade(0.0)
			var tween := arena.create_tween()
			tween.tween_property(arena, "modulate", Color.WHITE, 0.4)
		else:
			_reset_round()
			_begin_round_intro()


## Hiệp mới: về vị trí xuất phát, hồi đầy HP và Block Gauge. Special Gauge và Card Gauge GIỮ NGUYÊN.
func _reset_round() -> void:
	round_index += 1
	clock_ticks = ROUND_TICKS
	overtime = false
	rush_clash = 0
	_hitstop = 0
	_freeze = 0
	_round_ticks = 0
	_round_frames = 0
	winner = -1
	_match_point_final = false
	for p in projectiles:
		p.node.queue_free()
	projectiles.clear()
	for f in fighters:
		f.total_damage += f.damage_taken
		f.damage_taken = 0
		f.move = {}
		f.react = &""
		f.react_t = 0
		f.ko = false
		f.invuln = 0
		f.armor = 0
		f.wake_armor = 0
		f.juggle = 0
		f.chain = 0
		f.combo_hits = 0
		f.combo_damage = 0
		f.buffer_cmd = &""
		f.guard = GUARD_MAX
		f.guard_delay = 0
		f.break_pending = false
		f.jump_dir = 0
		f.airborne = false
		f.intro_pose = false
		f.anim = &""
		f.view.aura = 0.0
		f.body.clear_hit_reactions()
		f.body.velocity = Vector2.ZERO
		f.body.set("_knockback_ticks", 0)
		f.body.set("_launch_speed", 0.0)
		f.body.global_position = Vector2(START_X[f.index], -2.0)
		f.health.call("restore_full_health")
		f.body.finish_attack_facing_recovery()
		var dash: Variant = f.body.get("_dash_controller")
		if dash != null:
			dash.call("reset")
		var dash_buffer: Variant = f.body.get("_dash_input_buffer")
		if dash_buffer != null:
			dash_buffer.call("clear")
	# Cho thân gà "lắng" cố định số tick không input: trạng thái đầu hiệp giống hệt nhau
	# bất kể phần trình diễn chuyển hiệp dài hay ngắn (giữ tất định).
	for i in range(ROUND_SETTLE_TICKS):
		for f in fighters:
			_step_body(f, 0, 0)
	for f in fighters:
		f.was_airborne = f.airborne
	_hud_reset_round()


func _hud_reset_round() -> void:
	hud.hint = ""
	hud.reset_round()


## Kết thúc cả trận ngay (bỏ cuộc, xong trận hướng dẫn, test).
func _finish(win_index: int, banner: String) -> void:
	winner = win_index
	phase = Phase.END
	_phase_ticks = 0
	_hitstop = 0
	_freeze = 0
	rush_clash = 0
	if round_log.size() < round_index:
		round_log.append({"winner": win_index, "ticks": _round_ticks, "frames": _round_frames, "reason": banner,
			"hp": [fighters[0].hp_ratio(), fighters[1].hp_ratio()]})
		_match_ticks += _round_ticks
	hud.announce(banner, 80, Color(1.0, 0.85, 0.3), 1.6)
	arena.cheer(0.8)
	for f in fighters:
		_end_move(f)


## Bước thân gà ngoài mô phỏng trận (rơi, nảy, nằm) – dùng ở K.O., cuối hiệp, cuối trận.
func _outro_step() -> void:
	for f in fighters:
		f.pending_pressed = 0
		f.was_airborne = f.airborne
		_step_body(f, 0, 0)
		if f.was_airborne and not f.airborne and f.react == &"vang":
			f.react = &"vang_land"
			f.react_t = 0
			fx.dust(Vector2(f.x(), 0), 16)
			_shake = maxf(_shake, 3.0)
		f.react_t += 1
		if f.react == &"vang_land" and f.react_t >= int(f.kdef["vang_land_ticks"]):
			f.react = &"nam"
		if f.react == &"te" and f.react_t >= int(f.kdef["te_ticks"]):
			f.react = &"nam"


func _outro_tick() -> void:
	_outro_step()
	if _phase_ticks == 40 and cinematics:
		var text: String = "%s THẮNG!" % String(fighters[winner].side["name"])
		if winner == 0 and _perfect() and mode != &"tutorial":
			text = "THẮNG TUYỆT ĐỐI!"
		hud.announce(text.to_upper(), 120, Color(1.0, 0.85, 0.3) if winner == 0 else Color(0.85, 0.85, 0.95), 1.3)
		if winner == 0:
			sfx.play(&"confirm")
		sfx.play(&"cheer", -2.0)
		arena.cheer(1.0)
	if _phase_ticks == 190:
		var result: Dictionary = _result()
		last_match["result"] = result
		finished.emit(result)


func _perfect() -> bool:
	return fighters[0].total_damage + fighters[0].damage_taken == 0


## Kết quả trận. player_hp_ratio: 1 − tổng sát thương người chơi nhận / (HP tối đa × số hiệp đã đấu),
## nên chỉ bằng 1,0 khi cả trận không mất máu (main.gd dùng ≥ 0,999 cho huy hiệu "Thắng tuyệt đối").
func _result() -> Dictionary:
	var p: Fighter = fighters[0]
	var rounds_played: int = maxi(1, round_log.size())
	var total: int = p.total_damage + p.damage_taken
	var ratio: float = clampf(1.0 - float(total) / float(p.health.call("get_max_hp") * rounds_played), 0.0, 1.0)
	var winners: Array = []
	var ticks: Array = []
	var frames: Array = []
	var reasons: Array = []
	for r in round_log:
		winners.append(int(r["winner"]))
		ticks.append(int(r["ticks"]))
		frames.append(int(r.get("frames", r["ticks"])))
		reasons.append(String(r["reason"]))
	return {
		"won": winner == 0,
		"player_hp_ratio": ratio,
		"final_hp_ratio": p.hp_ratio(),
		"perfect": total == 0,
		"cards_used": int(p.track["cards"]),
		"max_combo": int(p.track["max_combo"]),
		"rounds": winners,
		"round_ticks": ticks,
		"round_frames": frames,
		"round_reasons": reasons,
		"round_wins": [round_wins[0], round_wins[1]],
		"duration_ticks": _match_ticks,
	}


## Gọi từ HUD khi người chơi chọn "Bỏ cuộc" trong menu tạm dừng.
func forfeit() -> void:
	if phase in [Phase.FIGHT, Phase.INTRO, Phase.ROUND_INTRO]:
		_finish(1, "BỎ CUỘC")
		_phase_ticks = 150


## Bỏ qua phần mở màn (HUD/phím xác nhận).
func skip_intro() -> void:
	_skip_requested = true


# =================================================================== AI

func _drive_ai(f: Fighter, o: Fighter) -> void:
	var wanted: int = f.ai.think(_ai_view(f, o))
	var changed: int = wanted ^ f.ai_held
	for bit in range(InputBits.COUNT):
		if (changed & (1 << bit)) != 0:
			f.source.push_event(bit, (wanted & (1 << bit)) != 0)
	f.ai_held = wanted


## Thông tin về đòn đang ra của một bên (dùng cho AI; chỉ đọc trạng thái mô phỏng, không đọc input).
func _move_info(x: Fighter) -> Dictionary:
	var info: Dictionary = {"attacking": false, "level": -1, "to_active": -1, "left": 0, "recovering": false,
		"whiffed": false, "reach": 0.0, "unblockable": false, "ground_only": false, "counter": false, "cat": ""}
	if x.move.is_empty():
		return info
	var ticks: Array = x.move["ticks"]
	var left: int = -x.mft
	for i in range(x.mf, ticks.size()):
		left += int(ticks[i])
	if x.move.has("counter") and not x.countered:
		left += int(x.move.get("whiff_hold", 0))
		info["counter"] = x.mf <= int(x.move["counter"][1])
	info["left"] = maxi(left, 0)
	info["cat"] = x.move_cat()
	var hits: Array = x.move["hits"]
	if hits.is_empty() or (bool(hits[0].get("counter_only", false)) and not x.countered):
		info["recovering"] = x.mf >= 2 and left > 6 and not info["counter"]
		info["whiffed"] = info["recovering"]
		return info
	var last: int = int(hits[hits.size() - 1]["frames"][-1])
	info["level"] = int(hits[0]["level"])
	info["reach"] = float(x.move.get("reach", 0.0))
	info["unblockable"] = bool(x.move.get("unblockable", false))
	info["ground_only"] = bool(hits[0].get("ground_only", false))
	if x.mf <= last:
		info["attacking"] = true
		var first_idx: int = 999
		for hit in hits:
			for fr in hit["frames"]:
				if int(fr) >= x.mf:
					first_idx = mini(first_idx, int(fr))
		var to_active: int = 0
		if first_idx > x.mf and first_idx < 999:
			to_active = -x.mft
			for i in range(x.mf, first_idx):
				to_active += int(ticks[i])
		info["to_active"] = maxi(to_active, 0)
	elif left > 4:
		info["recovering"] = true
		info["whiffed"] = x.contact_tick < x.move_start_tick
	return info


func _ai_view(f: Fighter, o: Fighter) -> Dictionary:
	var om: Dictionary = _move_info(o)
	var opp_max_reach: float = 0.0
	for id in Moves.move_ids(o.kit):
		var m: Dictionary = Moves.get_move(id, o.kit)
		if String(m["cat"]) in ["L", "M", "H"]:
			opp_max_reach = maxf(opp_max_reach, float(m["reach"]))
	var proj_near: bool = false
	for p in projectiles:
		if p.owner == o.index and absf(p.pos.x - f.x()) < 300.0 and signf(f.x() - p.pos.x) == float(p.dir):
			proj_near = true
	var wake_left: int = 0
	if o.react in [&"te", &"nam", &"vang_land", &"vang"]:
		wake_left = o.reaction(HitReactionController.ReactionKind.DOWN) + int(o.kdef["wake_invuln"])
	elif o.react == &"dung":
		wake_left = o.invuln
	var selected: StringName = &""
	if f.cards != null and not f.cards.get_hand_card_ids().is_empty():
		var hand: Array[StringName] = f.cards.get_hand_card_ids()
		selected = hand[clampi(f.cards.get_selected_index(), 0, hand.size() - 1)]
	var toward_sign: float = signf(f.x() - o.x())
	return {
		"dx": o.x() - f.x(),
		"distance": absf(o.x() - f.x()),
		"my_airborne": f.airborne,
		"my_busy": not f.move.is_empty(),
		"my_move_cat": f.move_cat(),
		"my_connected": _sim_tick - f.contact_tick <= Moves.CANCEL_WINDOW_TICKS - 2,
		"my_blocked": _sim_tick - f.contact_tick <= Moves.CANCEL_WINDOW_TICKS and f.contact_blocked,
		"my_locked": (f.locked() and f.react != &"guard") or f.ko or f.react != &"" and f.react != &"guard",
		"my_rush_loop": f.in_rush_loop(),
		"my_special_bars": f.special.get_available_bars(),
		"my_hp_ratio": f.hp_ratio(),
		"my_card_gauge": f.card_gauge.get_current_gauge() if f.card_gauge != null else 0,
		"my_card_selected": selected,
		"my_card_cost": int(GameState.CARD_INFO.get(selected, {"cost": 9})["cost"]),
		"mai_rua_active": f.cards != null and f.cards.has_active_effect(&"incoming_damage_reduction"),
		"my_projectile": _has_projectile(f.index),
		"my_at_wall": (f.x() < o.x() and f.x() <= STAGE_MIN + 40.0) or (f.x() > o.x() and f.x() >= STAGE_MAX - 40.0),
		"me_hit": f.react in [&"nhe", &"nang", &"te", &"vang"],
		"opp_projectile": _has_projectile(o.index),
		"opp_projectile_near": proj_near,
		"opp_airborne": o.airborne,
		"opp_vx_toward": o.body.velocity.x * toward_sign,
		"opp_jump_serial": o.jump_serial,
		"opp_attacking": om["attacking"],
		"opp_level": om["level"],
		"opp_ticks_to_active": om["to_active"],
		"opp_ticks_left": om["left"],
		"opp_reach": om["reach"],
		"opp_max_reach": opp_max_reach,
		"opp_unblockable": om["unblockable"],
		"opp_ground_only": om["ground_only"],
		"opp_counter": om["counter"],
		"opp_move_cat": om["cat"],
		"opp_move_serial": o.instance if not o.move.is_empty() else -o.jump_serial - 1,
		"opp_recovering": om["recovering"],
		"opp_was_blocked": om["recovering"] and not om["whiffed"] and o.contact_blocked,
		"opp_down": o.react in [&"te", &"nam", &"vang_land", &"vang"] or o.ko,
		"opp_wake_left": wake_left,
		"opp_juggle": o.react == &"vang" and o.airborne,
		"opp_crouching": o.crouching(),
		"opp_hp_ratio": o.hp_ratio(),
		"rush_clash": rush_clash > 0,
		"clock_ticks": clock_ticks,
		"my_rounds": round_wins[f.index],
		"opp_rounds": round_wins[o.index],
		"rounds_needed": rounds_to_win,
	}


# =================================================================== hình ảnh

func _set_anim(f: Fighter, anim: StringName) -> int:
	if f.anim != anim:
		f.anim = anim
		f.anim_ticks = 0
	else:
		f.anim_ticks += 1
	return f.anim_ticks


func _update_view(f: Fighter) -> void:
	var v: FighterView = f.view
	v.facing = f.facing()
	v.stars = false
	if (_hitstop > 0 or _freeze > 0) and f.anim != &"":
		return
	var t: int = f.react_t
	var anims: Dictionary = f.kdef["anims"]
	match f.react:
		&"vang":
			_set_anim(f, &"vang")
			# Bay: VANG_RaXa tới frame bay cuối của kit, giữ tới khi chạm đất.
			var frames: Array[int] = Moves.tag_frames(String(anims["vang"]), f.kit)
			var frame: int = FighterView.tag_frame_at(String(anims["vang"]), t, false, f.kit)
			var fly_last: int = frames[int(f.kdef["vang_fly_last"])]
			if frame > fly_last:
				frame = fly_last
			v.set_frame(frame, true, 0.0, Vector2.ZERO, 1.0, true)
			return
		&"vang_land":
			_set_anim(f, &"vang_land")
			var land: Array[int] = Moves.tag_frames(String(anims["vang"]), f.kit)
			var span: Array = f.kdef["vang_land"]
			var count: int = int(span[1]) - int(span[0]) + 1
			var step: int = maxi(1, int(f.kdef["vang_land_ticks"]) / count)
			var index: int = mini(int(span[0]) + t / step, int(span[1]))
			v.set_frame(land[index], false, 0.0, Vector2.ZERO, 1.0, true)
			return
		&"te":
			_set_anim(f, &"te")
			v.play_tag(String(anims["te"]), t, false)
			return
		&"nam":
			_set_anim(f, &"nam")
			v.play_tag(String(anims["nam"]), t, true)
			return
		&"dung":
			_set_anim(f, &"dung")
			v.play_tag(String(anims["dung"]), t, false)
			return
		&"nhe":
			_set_anim(f, &"nhe")
			v.play_tag(String(anims["nhe"]), t, false, false, 0.9 if f.crouching() else 1.0)
			return
		&"nang":
			_set_anim(f, &"nang")
			v.play_tag(String(anims["nang"]), t, false)
			return
		&"guard":
			_set_anim(f, &"guard")
			if f.kit == Moves.KIT_ROOSTER:
				var guard_frames: Array[int] = Moves.tag_frames("GUARD_DoCanh")
				var gf: int = guard_frames[0] if t < 3 else (guard_frames[2] if f.blockstun() <= 4 else guard_frames[1])
				v.set_frame(gf, false, 0.0, Vector2.ZERO, 0.88 if f.crouching() else 1.0)
			else:
				# GUARD_TrungDon rồi về GUARD f2 (Thiết Giáp).
				var hit_tag: String = String(anims["guard_hit"])
				if t < Moves.tag_ticks(hit_tag, f.kit):
					v.play_tag(hit_tag, t, false)
				else:
					v.set_frame(Moves.tag_frames(String(anims["guard"]), f.kit)[1])
			return
	if f.ko:
		_set_anim(f, &"nam")
		v.play_tag(String(anims["nam"]), f.anim_ticks, true)
		f.anim_ticks += 1
	elif f.intro_pose or (winner == f.index and not f.airborne and f.move.is_empty()
			and ((phase == Phase.END and _phase_ticks > 30) or (phase == Phase.ROUND_END and _phase_ticks > 15))):
		v.play_tag(String(anims["taunt"]), _set_anim(f, &"win"), true)
	elif not f.move.is_empty():
		_set_anim(f, StringName(f.move["id"]))
		v.set_frame(int(f.move["frames"][f.mf]), f.move.has("air"), 0.0, Vector2.ZERO, float(f.move.get("squash", 1.0)))
		v.aura = 1.0 if f.move["cat"] in ["SP", "SUPER"] and f.move["id"] != &"phun_long" else 0.0
	elif f.airborne and f.kit == Moves.KIT_ROOSTER:
		_set_anim(f, &"jump")
		v.set_jump(f.body.velocity.y)
	elif f.body.is_dashing():
		var forward: bool = signf(f.body.velocity.x) == float(f.facing())
		v.play_tag("run_right" if forward else "run_left", _set_anim(f, &"dash") * 2)
	elif f.prox_guard:
		# Thiết Giáp: f1 rồi giữ vòng f2–f3.
		var guard_tag: String = String(anims["guard"])
		var gt: int = _set_anim(f, &"guard_stance")
		var gframes: Array[int] = Moves.tag_frames(guard_tag, f.kit)
		if gt < Moves.frame_ticks(gframes[0], f.kit):
			v.set_frame(gframes[0])
		else:
			v.set_frame(gframes[1] if (gt / 7) % 2 == 0 else gframes[2])
	else:
		match f.body.get_locomotion_state():
			LocomotionStateMachine.State.CROUCH:
				_set_anim(f, &"crouch")
				v.set_frame(21, false, 0.0, Vector2.ZERO, 0.9)
			LocomotionStateMachine.State.FORWARD_WALK:
				v.play_tag(String(anims["walk_f"]), _set_anim(f, &"walk_f"))
			LocomotionStateMachine.State.BACKWALK:
				if anims["walk_b"] == anims["walk_f"]:
					v.play_tag_reverse(String(anims["walk_b"]), _set_anim(f, &"walk_b"))
				else:
					v.play_tag(String(anims["walk_b"]), _set_anim(f, &"walk_b"))
			_:
				v.play_tag(String(anims["idle"]), _set_anim(f, &"idle"))
	# Gà đang ra đòn được vẽ đè lên.
	f.body.z_index = 1 if not f.move.is_empty() else 0


## Camera điện ảnh (chỉ trình diễn): gần thì zoom sát, xa thì mở rộng; bám dọc khi bị hất tung;
## đẩy zoom + rung theo hướng đòn nặng; khi dừng hình/K.O./mở màn thì kéo về điểm `_cine_pos`.
func _cine_set(pos: Vector2, zoom_mult: float, weight: float) -> void:
	_cine_pos = pos
	_cine_zoom = zoom_mult
	_cine_weight = weight


func _update_camera() -> void:
	var a: Vector2 = fighters[0].body.global_position
	var b: Vector2 = fighters[1].body.global_position
	var distance: float = absf(a.x - b.x)
	var viewport: Vector2 = get_viewport_rect().size
	var visible_w: float = clampf(distance + 500.0, 600.0, 1000.0)
	var base_zoom: float = viewport.x / visible_w
	var target_zoom: float = base_zoom
	var mid_x: float = (a.x + b.x) * 0.5
	# Bám theo bên đang bị hất tung / văng tường.
	for f in fighters:
		if f.react == &"vang" and f.airborne:
			mid_x = lerpf(mid_x, f.x(), 0.3)
	var top: float = minf(a.y, b.y)
	var visible: Vector2 = viewport / target_zoom
	var target := Vector2(mid_x, -visible.y * 0.30 + minf(0.0, top + 40.0) * 0.55)
	if _cine_weight > 0.0:
		var cine_zoom: float = base_zoom * _cine_zoom
		target_zoom = lerpf(target_zoom, cine_zoom, _cine_weight)
		var cine_visible: Vector2 = viewport / target_zoom
		var cine_target := Vector2(_cine_pos.x, _cine_pos.y + cine_visible.y * 0.08)
		target = target.lerp(cine_target, _cine_weight)
	target_zoom *= 1.0 + _zoom_punch
	_zoom_punch *= 0.86
	var speed: float = 0.22 if _cine_weight > 0.5 else 0.12
	_cam_zoom = lerpf(_cam_zoom, target_zoom, speed * 0.7)
	visible = viewport / _cam_zoom
	target.x = clampf(target.x, -110.0 + visible.x * 0.5, 1110.0 - visible.x * 0.5)
	_cam_pos = _cam_pos.lerp(target, speed)
	_shake = maxf(0.0, _shake - 0.35)
	var offset := Vector2.ZERO
	if _shake > 0.0:
		# Rung có hướng: dọc theo hướng đòn, kèm chút ngẫu nhiên (RNG riêng cho hình ảnh).
		var swing: float = sin(float(Engine.get_physics_frames()) * 1.9)
		offset = _shake_dir * _shake * swing + Vector2(_fx_rng.randf_range(-1, 1), _fx_rng.randf_range(-1, 1)) * _shake * 0.45
	camera.position = _cam_pos + offset
	camera.zoom = Vector2(_cam_zoom, _cam_zoom)
	arena.follow_camera(_cam_pos)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_F1:
				debug_boxes = not debug_boxes
			KEY_ESCAPE:
				if phase in [Phase.FIGHT, Phase.INTRO, Phase.ROUND_INTRO]:
					hud.toggle_pause()
					get_viewport().set_input_as_handled()
			KEY_E, KEY_ENTER, KEY_SPACE:
				if phase == Phase.INTRO and not get_tree().paused:
					skip_intro()


func _draw() -> void:
	if not debug_boxes:
		return
	for f in fighters:
		var hurt: Rect2 = _hurtbox(f)
		if hurt.has_area():
			draw_rect(hurt, Color(0.2, 1.0, 0.3, 0.25))
			draw_rect(hurt, Color(0.2, 1.0, 0.3), false, 2.0)
		var limb: Rect2 = _limb_box(f)
		if limb.has_area():
			draw_rect(limb, Color(0.2, 1.0, 0.3), false, 1.0)
		var active: Array = _active_hit(f)
		if not active.is_empty():
			draw_rect(active[1], Color(1.0, 0.2, 0.2, 0.3))
			draw_rect(active[1], Color(1.0, 0.2, 0.2), false, 2.0)
		var p: Vector2 = f.body.global_position
		draw_rect(Rect2(p.x - f.push_half(), p.y - 100.0, f.push_half() * 2.0, 100.0), Color(0.3, 0.6, 1.0), false, 1.0)
	for p in projectiles:
		draw_rect(p.box(), Color(1.0, 0.6, 0.2), false, 2.0)
