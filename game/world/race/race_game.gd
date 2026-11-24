extends Node2D

## ĐUA XE ĐƯỜNG QUÊ – trò bí mật: chạy xe máy vượt mặt một xe NPC trên đường làng thì tay lái đó thách đua
## tới cổng ấp. Màn ngang dựng hoàn toàn bằng code (không .tscn): nền parallax (race_backdrop.gd), HUD
## (race_hud.gd), xe đối thủ dùng đúng sprite của xe trên bản đồ (4 region = bánh xe quay).
## Ba làn: W/S (↑/↓) đổi làn, D/→ giữ ga, A/← thắng, J hoặc E bốc ga (nitro, 3 nấc), Esc bỏ cuộc.
## Bốc ga nạp lại khi núp gió sau xe đối thủ, sượt qua chướng ngại, hoặc uống ly nước mía bên đường.
## Mô phỏng ở _physics_process (60 Hz cố định); pha "sát nút" quay chậm bằng hệ số thời gian riêng
## (không đụng Engine.time_scale).
## Dùng: var race := RaceGame.new(); race.setup(rider, map_view, seed); add_child(race); var r := await race.run()
## Kết quả: {cancelled, won, time, rival_time, gap, hits, near_misses, nitro_used, pickups, top_kmh,
##           photo_finish, rider}
## Test/headless: autopilot = true + autopilot_skill (0 = lơ mơ, 1 = hoàn hảo); press(action) với
## action = up/down/nitro/confirm/cancel; hold(&"throttle"|&"brake", bật/tắt).

signal finished(result: Dictionary)
signal fx(kind: StringName, pos: Vector2)

const Backdrop := preload("res://game/world/race/race_backdrop.gd")
const Hud := preload("res://game/world/race/race_hud.gd")
const Audio := preload("res://game/audio/audio_director.gd")
const RiderData := preload("res://game/world/race/race_riders.gd")

enum Phase { INTRO, COUNTDOWN, RACE, FINISH, RESULT, DONE }

const ZOOM: float = 3.0
const PHOTO_ZOOM: float = 4.0
const TRACK_LEN: float = 12000.0
const LANES: Array[float] = [158.0, 177.0, 196.0]
const ANIMAL_TOP: float = 128.0     # chỗ gà vịt chó đứng chờ / chạy tới (ngoài mặt đường)
const ANIMAL_BOTTOM: float = 220.0
const VIEW_CENTER_Y: float = 108.0
const LANE_TIME: float = 0.18
const V_MAX: float = 250.0           # ≈ 62 km/h
const V_NITRO: float = 340.0         # ≈ 85 km/h
const ACCEL: float = 120.0
const NITRO_ACCEL: float = 240.0
const COAST: float = 55.0
const BRAKE: float = 320.0
const RICE_CAP: float = 165.0
const NITRO_COST: float = 1.0 / 3.0
const NITRO_TIME: float = 1.7
const DRAFT_GAIN: float = 0.16       # mỗi giây núp gió
const NEAR_GAIN: float = 0.07
const PICKUP_GAIN: float = 0.34
const PX_PER_M: float = 14.0
const KMH_PER_PX: float = 0.25
const COUNT_STEP: float = 0.8
const RIDER_HALF: float = 20.0       # nửa chiều dài xe khi tính va chạm (rộng lượng hơn hình)
const RIDER_DEPTH: float = 5.0
const RUBBER_END: float = 0.85       # sau 85% quãng đường thì hết kéo giãn: ai hay người đó thắng
const FINISH_WAIT: float = 3.0
const FAR: float = 1.0e9
const RESULT_MIN_TIME: float = 0.9
const RESULT_AUTO_TIME: float = 12.0

## Chướng ngại: w/depth = nửa kích thước va chạm (x / y), slow = hệ số tốc độ còn lại khi va.
const HAZARDS: Dictionary = {
	&"pothole": {"w": 8.0, "depth": 6.0, "slow": 0.42, "flat": true},
	&"puddle": {"w": 16.0, "depth": 6.0, "slow": 0.62, "flat": true},
	&"rice": {"w": 30.0, "depth": 8.0, "slow": 0.6, "flat": true},
	&"chickens": {"w": 12.0, "depth": 6.0, "slow": 0.5, "speed": 30.0},
	&"ducks": {"w": 6.0, "depth": 14.0, "slow": 0.5, "speed": 20.0},
	&"dog": {"w": 12.0, "depth": 6.0, "slow": 0.45, "speed": 64.0},
	&"cart": {"w": 26.0, "depth": 7.0, "slow": 0.0, "vx": 80.0},
}
const HIT_TEXT: Dictionary = {
	&"pothole": "Ổ gà! (Mà kiếm hoài hổng thấy con gà nào…)",
	&"puddle": "Vũng nước! Trơn trợt!",
	&"rice": "Lúa phơi! Bà Tư la kìa!",
	&"chickens": "Cục tác!! Gà bay tán loạn!",
	&"ducks": "Cạp cạp! Bầy vịt đi hàng một!",
	&"dog": "Gâu gâu! Hú hồn!",
	&"cart": "Rầm! Xe ba gác chắn đường!",
}


class Racer:
	var id: int = 0
	var x: float = 0.0
	var lane: int = 1
	var y: float = 177.0
	var lane_from: float = 177.0
	var lane_t: float = 1.0
	var v: float = 0.0
	var nitro: float = 0.0
	var boost: float = 0.0
	var slow: float = 0.0
	var jolt: float = 0.0
	var slide: float = 0.0
	var finish_time: float = -1.0
	var hits: int = 0
	var near: int = 0
	var nitro_used: int = 0
	var pickups: int = 0
	var top: float = 0.0
	var travel: float = 0.0
	var dust: float = 0.0
	var puff: float = 0.0
	var node: Node2D


class Hazard:
	var kind: StringName
	var x: float = 0.0
	var y: float = 0.0
	var w: float = 8.0
	var depth: float = 6.0
	var slow: float = 0.5
	var flat: bool = false
	var vx: float = 0.0
	var vy: float = 0.0
	var y_end: float = 0.0
	var trigger: float = 300.0
	var active: bool = false
	var done: bool = false
	var hit: Dictionary = {}
	var passed: Dictionary = {}
	var anim: float = 0.0
	var node: Node2D


class Pickup:
	var x: float = 0.0
	var lane: int = 1
	var taken: bool = false
	var node: Node2D


var rider: Dictionary = {}
var map_view: Node = null
## Bản hoàng hôn của nền: -1 = theo giờ trong game (sau 16:30 hoặc trước 5:30), 0 = ban ngày, 1 = hoàng hôn.
var sunset_mode: int = -1
var race_seed: int = 1
var autopilot: bool = false
var autopilot_skill: float = 1.0
var phase: int = Phase.INTRO
var player: Racer
var rival: Racer
var result: Dictionary = {}

var _running: bool = false
var _racers: Array[Racer] = []
var _hazards: Array[Hazard] = []
var _pickups: Array[Pickup] = []
var _particles: Array[Dictionary] = []
var _queued: Array[StringName] = []
var _held: Dictionary = {}
var _phase_time: float = 0.0
var _race_time: float = 0.0
var _clock: float = 0.0
var _time_scale: float = 1.0
var _photo: bool = false
var _photo_real: float = 0.0
var _first_finish: float = -1.0
var _after_finish: float = 0.0
var _rival_delay: float = 0.0
var _rival_nitro_k: int = 0
var _rival_decided: Dictionary = {}
var _auto_decided: Dictionary = {}
var _auto_gas: bool = true
var _rng_rival := RandomNumberGenerator.new()
var _rng_auto := RandomNumberGenerator.new()
var _rng_fx := RandomNumberGenerator.new()
var _drafting: bool = false
var _draft_told: bool = false
var _pothole_told: bool = false
var _last_place: int = 1
var _horn_cool: float = 0.0
var _shake: float = 0.0
var _zoom: float = ZOOM
var _view := Vector2(384, 216)
var _cam_left: float = 0.0

var _textures: Dictionary = {}       # tên node bản đồ → Array[Texture2D]
var _rival_frames: Array[Texture2D] = []
## true: ảnh xe đối thủ lấy từ traffic.json hướng đông (đã quay đúng hướng đua, không lật).
var _rival_faces_east: bool = false
var _rival_sprite: Sprite2D
var _rival_emitter: AudioStreamPlayer2D
var _player_visual: Node2D
var _player_bike: Sprite2D           # chỉ có ở hình dự phòng (đổi khung nan hoa)
var _bike_a: Texture2D
var _bike_b: Texture2D
var _wheel_script: Script            # player.gd nếu có WorldPlayer.set_rider_wheel_frame(visual, frame)
var _wheel_frame: int = -1
var _backdrop: Node2D
var _front: Node2D
var _ground: Node2D
var _actors: Node2D
var _fx: Node2D
var _overlay: Node2D
var _camera: Camera2D
var _hud: CanvasLayer
var _sfx: Node


## rider: dữ liệu từ race_riders.gd (có "node" = tên node xe trên bản đồ). map_view: MapView để lấy lại ảnh
## (null được: vẽ hình thay thế). seed: sắp xếp chướng ngại.
func setup(p_rider: Dictionary, p_map_view: Node = null, p_seed: int = 1) -> void:
	rider = p_rider
	map_view = p_map_view
	race_seed = p_seed


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if rider.is_empty():
		rider = (load("res://game/world/race/race_riders.gd") as Script).call("get_rider", "A_xe_may_cho_ga")
	_rng_rival.seed = race_seed * 7 + 3
	_rng_auto.seed = race_seed * 13 + 5
	_rng_fx.seed = race_seed
	_load_textures()
	var sfx_script: Script = load("res://game/battle/sfx.gd")
	if sfx_script != null:
		_sfx = sfx_script.new()
		add_child(_sfx)

	_backdrop = Backdrop.new()
	_backdrop.set("tex", _textures)
	_backdrop.set("track_len", TRACK_LEN)
	_backdrop.set("crowd", _crowd_textures())
	_backdrop.set("sunset", is_sunset())
	add_child(_backdrop)
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_actors = Node2D.new()
	_actors.y_sort_enabled = true
	add_child(_actors)
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_front = Backdrop.new()
	_front.set("front", true)
	_front.set("track_len", TRACK_LEN)
	_front.set("crowd", _backdrop.get("crowd"))
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
	_hud.call("set_rider", String(rider.get("name", "")), rider.get("color", Color.RED))

	player = _make_racer(0, 2)
	rival = _make_racer(1, 0)
	_racers = [player, rival]
	player.node = Node2D.new()
	_player_visual = make_player_visual()
	player.node.add_child(_player_visual)
	_player_bike = _player_visual.get_meta("bike_sprite") if _player_visual.has_meta("bike_sprite") else null
	if _player_bike == null:
		_wheel_script = _script_with("res://game/world/player.gd", "set_rider_wheel_frame")
	_actors.add_child(player.node)
	rival.node = _make_rival_node()
	_actors.add_child(rival.node)
	_generate()
	_place_racers()
	_update_view(0.0)


## Hình người chơi ngồi xe Dream nhìn ngang (quay phải, gốc = điểm chạm đất dưới giữa xe).
## Ưu tiên WorldPlayer.make_rider_visual() (đang được vẽ lại); chưa có thì ghép xe ngang + nửa người
## như lúc chạy xe ở chế độ khám phá; thiếu ảnh nữa thì dùng WorldPlayer.make_parked_bike().
static func make_player_visual() -> Node2D:
	var script: Script = _script_with("res://game/world/player.gd", "make_rider_visual")
	if script != null:
		var made: Variant = script.call("make_rider_visual")
		if made is Node2D:
			return made
	var side: Texture2D = load("res://game/art/bike_side.png") if ResourceLoader.exists("res://game/art/bike_side.png") else null
	var sheet: Texture2D = load("res://game/art/player_sheet.png") if ResourceLoader.exists("res://game/art/player_sheet.png") else null
	if side == null or sheet == null:
		return WorldPlayer.make_parked_bike()
	var root := Node2D.new()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var body := Sprite2D.new()
	body.texture = sheet
	body.centered = false
	body.region_enabled = true
	body.region_rect = Rect2(18 * 64, 0, 64, 44) # khung đi sang phải, nửa trên người (giống player.gd khi ngồi xe)
	body.scale = Vector2(0.8, 0.8)
	body.position = Vector2(-38, -64)
	root.add_child(body)
	var bike := Sprite2D.new()
	bike.texture = side
	bike.centered = false
	bike.position = Vector2(-34, -42)
	root.add_child(bike)
	root.set_meta("bike_sprite", bike)
	return root


## Script ở path nếu nó có hàm (static) tên method_name, ngược lại null. Gọi bằng script.call(...)
## vì hàm có thể chưa tồn tại lúc viết code này (không gọi thẳng WorldPlayer.xxx để khỏi lỗi parse).
static func _script_with(path: String, method_name: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var script: Script = load(path)
	if script == null:
		return null
	for method in script.get_script_method_list():
		if String(method.get("name", "")) == method_name:
			return script
	return null


## Nền hoàng hôn? (theo sunset_mode / giờ GameState).
func is_sunset() -> bool:
	if sunset_mode >= 0:
		return sunset_mode == 1
	var m: int = int(GameState.minutes)
	return m >= 16 * 60 + 30 or m < 5 * 60 + 30


func _make_racer(id: int, lane: int) -> Racer:
	var r := Racer.new()
	r.id = id
	r.lane = lane
	r.y = LANES[lane]
	r.lane_from = r.y
	r.nitro = NITRO_COST
	r.x = 0.0
	return r


func _make_rival_node() -> Node2D:
	var root := Node2D.new()
	var holder := Node2D.new() # con đầu tiên = phần hình nhún nhảy (xem _place_racers)
	root.add_child(holder)
	_rival_sprite = Sprite2D.new()
	_rival_sprite.centered = false
	if not _rival_frames.is_empty():
		_rival_sprite.texture = _rival_frames[0]
		var size: Vector2 = _rival_frames[0].get_size()
		_rival_sprite.position = Vector2(-roundf(size.x * 0.5), -size.y)
		_rival_sprite.flip_h = int(rider.get("dir", 1)) < 0 and not _rival_faces_east # ảnh xe chạy sang trái → lật cho cùng hướng đua
		holder.add_child(_rival_sprite)
	else:
		var stand_in: Node2D = WorldPlayer.make_parked_bike()
		stand_in.modulate = rider.get("color", Color.RED)
		holder.add_child(stand_in)
	_rival_emitter = Audio.make_emitter(&"npc_bike", 420.0, -4.0)
	root.add_child(_rival_emitter)
	return root


func _load_textures() -> void:
	# Xe đối thủ: đúng dáng xe NPC đã thách (traffic.json / game/art/vehicles – cả dáng mới), ảnh hướng đông (đường đua
	# luôn chạy sang phải nên không lật). Không cần MapView.
	var vehicle: String = RiderData.vehicle_of(rider)
	var frames: Array = MapView.vehicle_textures(vehicle, "east") if vehicle != "" else []
	if not frames.is_empty():
		_rival_faces_east = true
	elif map_view != null and map_view.has_method("node_textures"):
		frames = map_view.call("node_textures", String(rider.get("node", "")))
	for frame in frames:
		_rival_frames.append(frame)
	if map_view == null or not map_view.has_method("node_textures"):
		return
	var names: Array[String] = []
	names.append_array(Backdrop.TEXTURE_NODES)
	names.append_array(["B_ga_nha_01", "E_vit_01", "NV_cho_vang"])
	for node_name in names:
		_textures[node_name] = map_view.call("node_textures", node_name)


func _crowd_textures() -> Array[Texture2D]:
	var list: Array[Texture2D] = []
	for k in range(1, 6):
		var path: String = "res://game/art/npc/crowd_%d.png" % k
		if ResourceLoader.exists(path):
			list.append(load(path))
	return list


# ================================================================== sắp đặt đường đua

## Chướng ngại cách nhau 250–430 px, mỗi chỗ chừa ít nhất một làn trống; tối đa 2 xe ba gác.
## Ly nước mía mỗi ~1100–1500 px, không đặt sát chướng ngại cùng làn.
func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = race_seed
	var x: float = 760.0
	var carts: int = 0
	while x < TRACK_LEN - 520.0:
		var roll: int = rng.randi_range(0, 99)
		var kind: StringName = &"pothole"
		if roll >= 28 and roll < 44:
			kind = &"puddle"
		elif roll >= 44 and roll < 56:
			kind = &"rice"
		elif roll >= 56 and roll < 68:
			kind = &"chickens"
		elif roll >= 68 and roll < 77:
			kind = &"ducks"
		elif roll >= 77 and roll < 86:
			kind = &"dog"
		elif roll >= 86 and carts < 2 and x < 7600.0:
			kind = &"cart"
			carts += 1
		match kind:
			&"pothole":
				var lane: int = rng.randi_range(0, 2)
				_add_hazard(kind, x, LANES[lane])
				if rng.randf() < 0.3:
					_add_hazard(kind, x + rng.randf_range(-10.0, 30.0), LANES[(lane + rng.randi_range(1, 2)) % 3])
			&"puddle", &"cart":
				_add_hazard(kind, x, LANES[rng.randi_range(0, 2)])
			&"rice":
				var first: int = rng.randi_range(0, 1)
				_add_hazard(kind, x, LANES[first])
				_add_hazard(kind, x, LANES[first + 1])
			_:
				var from_top: bool = rng.randf() < 0.5
				var hz := _add_hazard(kind, x, ANIMAL_TOP if from_top else ANIMAL_BOTTOM)
				hz.y_end = ANIMAL_BOTTOM if from_top else ANIMAL_TOP
				hz.vy = float(HAZARDS[kind]["speed"]) * (1.0 if from_top else -1.0)
				hz.trigger = rng.randf_range(250.0, 360.0) if kind != &"dog" else rng.randf_range(200.0, 260.0)
		x += rng.randf_range(250.0, 430.0)
	var px: float = 1100.0
	while px < TRACK_LEN - 400.0:
		var p := Pickup.new()
		p.lane = rng.randi_range(0, 2)
		p.x = px
		for hz in _hazards:
			if hz.flat and absf(hz.y - LANES[p.lane]) < 4.0 and absf(hz.x - p.x) < 80.0:
				p.x += 110.0
		p.node = Node2D.new()
		p.node.position = Vector2(roundf(p.x), LANES[p.lane])
		p.node.draw.connect(_draw_pickup.bind(p))
		_actors.add_child(p.node)
		_pickups.append(p)
		px += rng.randf_range(1100.0, 1500.0)


func _add_hazard(kind: StringName, x: float, y: float) -> Hazard:
	var spec: Dictionary = HAZARDS[kind]
	var hz := Hazard.new()
	hz.kind = kind
	hz.x = x
	hz.y = y
	hz.w = float(spec["w"])
	hz.depth = float(spec["depth"])
	hz.slow = float(spec["slow"])
	hz.flat = bool(spec.get("flat", false))
	hz.vx = float(spec.get("vx", 0.0))
	hz.y_end = y
	hz.anim = float(_hazards.size()) * 0.37
	if not hz.flat:
		hz.node = Node2D.new()
		hz.node.position = Vector2(roundf(x), roundf(y))
		hz.node.draw.connect(_draw_hazard.bind(hz))
		_actors.add_child(hz.node)
	_hazards.append(hz)
	return hz


# ================================================================== chạy

func run() -> Dictionary:
	_running = true
	_enter_intro()
	var r: Dictionary = await finished
	return r


## Bơm một thao tác (test dùng trực tiếp; bàn phím cũng đi qua đây).
func press(action: StringName) -> void:
	if not _running:
		return
	if action == &"cancel":
		if phase != Phase.RESULT:
			_end({"cancelled": true, "won": false, "gave_up": true})
		return
	match phase:
		Phase.INTRO:
			if action == &"confirm" or action == &"nitro":
				_enter_countdown()
			elif action == &"up" or action == &"down":
				_queued.append(action)
		Phase.COUNTDOWN, Phase.RACE, Phase.FINISH:
			if action == &"confirm":
				action = &"nitro"
			_queued.append(action)
		Phase.RESULT:
			if (action == &"confirm" or action == &"nitro") and _phase_time >= RESULT_MIN_TIME:
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
			action = &"up"
		KEY_S, KEY_DOWN:
			action = &"down"
		KEY_J, KEY_E:
			action = &"nitro"
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			action = &"confirm"
		KEY_ESCAPE:
			action = &"cancel"
	if action == &"":
		return
	get_viewport().set_input_as_handled()
	press(action)


func _gas_held() -> bool:
	if autopilot:
		return _auto_gas
	return bool(_held.get(&"throttle", false)) or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)


func _brake_held() -> bool:
	if autopilot:
		return false
	return bool(_held.get(&"brake", false)) or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)


func _enter_intro() -> void:
	phase = Phase.INTRO
	_phase_time = 0.0
	Audio.music(&"battle", 0.8)
	Audio.ambience({&"birds": 0.45, &"leaves": 0.35, &"village": 0.25}, 1.0)
	Audio.engine(true, 0.0)
	var who: String = String(rider.get("name", "Đối thủ"))
	_hud.call("show_intro", "ĐUA XE ĐƯỜNG QUÊ", "%s thách đua tới cổng ấp Bình Kê!\n\n" % who
		+ "W/S (↑/↓): đổi làn    D (→): giữ ga    A (←): thắng\n"
		+ "J hoặc E: bốc ga – nạp lại khi núp gió sau đít xe đối thủ,\nsượt sát chướng ngại, hoặc uống ly nước mía bên đường.\n\n"
		+ "Coi chừng ổ gà, vũng nước, lúa phơi, gà vịt, chó và xe ba gác!\n"
		+ "Dấu ◄ ở mép phải báo chướng ngại sắp tới.\n\n[E] Sẵn sàng!        [Esc] Thôi, hổng đua")


func _enter_countdown() -> void:
	phase = Phase.COUNTDOWN
	_phase_time = 0.0
	_hud.call("hide_intro")
	_hud.call("set_countdown", "3")
	_play(&"select", -4.0)


func _enter_race() -> void:
	phase = Phase.RACE
	_phase_time = 0.0
	_hud.call("set_countdown", "ĐI!!!", Color(0.6, 1.0, 0.5))
	_play(&"confirm", -2.0)
	Audio.sfx(&"bike_horn", -4.0)
	_rival_delay = float(rider.get("react", 0.2))
	fx.emit(&"go", Vector2(player.x, player.y))


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_clock += delta
	_phase_time += delta
	match phase:
		Phase.INTRO:
			_take_lane_inputs()
			if (autopilot and _phase_time > 0.4) or _phase_time > 15.0 or (_gas_held() and _phase_time > 0.8):
				_enter_countdown()
		Phase.COUNTDOWN:
			_take_lane_inputs()
			var step: int = int(_phase_time / COUNT_STEP)
			var label: String = ["3", "2", "1"][mini(step, 2)]
			if step >= 3:
				_enter_race()
			elif String(_hud.call("countdown_text")) != label:
				_hud.call("set_countdown", label)
				_play(&"select", -4.0)
		Phase.RACE, Phase.FINISH:
			_tick_race(delta)
		Phase.RESULT:
			if (autopilot and _phase_time > 1.2) or _phase_time > RESULT_AUTO_TIME:
				_end(result)
	_update_engine_audio()
	_update_view(delta)


func _take_lane_inputs() -> void:
	while not _queued.is_empty():
		var action: StringName = _queued.pop_front()
		if action == &"up":
			_change_lane(player, -1)
		elif action == &"down":
			_change_lane(player, 1)


func _tick_race(delta: float) -> void:
	if phase == Phase.RACE and _phase_time > 0.7:
		_hud.call("set_countdown", "")
	# Pha sát nút: quay chậm theo thời gian thật.
	if _photo:
		_photo_real += delta
		if _photo_real >= 1.4 or (player.finish_time >= 0.0 and rival.finish_time >= 0.0 and _photo_real >= 0.8):
			_photo = false
			_time_scale = 1.0
	var dt: float = delta * _time_scale
	_race_time += dt
	_horn_cool = maxf(_horn_cool - dt, 0.0)
	_shake = maxf(_shake - delta, 0.0)
	_update_hazards(dt)
	# Người chơi.
	var gas: bool = _gas_held()
	var brake: bool = _brake_held()
	if autopilot and player.finish_time < 0.0:
		_autopilot(dt)
		gas = _auto_gas
	while not _queued.is_empty():
		var action: StringName = _queued.pop_front()
		if player.finish_time >= 0.0:
			continue
		match action:
			&"up":
				_change_lane(player, -1)
			&"down":
				_change_lane(player, 1)
			&"nitro":
				_use_nitro(player, true)
	_move_racer(player, dt, gas, brake, V_MAX)
	# Đối thủ.
	_move_racer(rival, dt, _rival_think(dt), false, _rival_cruise())
	for r in _racers:
		_contacts(r)
		_trail(r, dt)
	_draft(dt)
	_check_place()
	_check_finish(dt)
	_update_particles(dt)


func _move_racer(r: Racer, dt: float, gas: bool, brake: bool, cruise: float) -> void:
	var cap: float = cruise
	if r.boost > 0.0:
		r.boost = maxf(r.boost - dt, 0.0)
		cap = V_NITRO * cruise / V_MAX
	if r.slow > 0.0:
		r.slow = maxf(r.slow - dt, 0.0)
		cap = minf(cap, RICE_CAP)
	if r.finish_time >= 0.0:
		r.v = move_toward(r.v, 0.0, COAST * 2.5 * dt)
	elif brake:
		r.v = move_toward(r.v, 0.0, BRAKE * dt)
	elif gas:
		if r.v > cap:
			r.v = move_toward(r.v, cap, 150.0 * dt)
		else:
			var accel: float = NITRO_ACCEL if r.boost > 0.0 else ACCEL * (1.15 - 0.5 * r.v / V_MAX)
			r.v = move_toward(r.v, cap, accel * dt)
	else:
		r.v = move_toward(r.v, 0.0, COAST * dt)
	r.x += r.v * dt
	r.travel += r.v * dt
	if r.lane_t < 1.0:
		r.lane_t = minf(r.lane_t + dt / LANE_TIME, 1.0)
		r.y = lerpf(r.lane_from, LANES[r.lane], smoothstep(0.0, 1.0, r.lane_t))
	r.jolt = maxf(r.jolt - dt, 0.0)
	r.slide = maxf(r.slide - dt, 0.0)
	r.top = maxf(r.top, r.v)


func _change_lane(r: Racer, step: int) -> void:
	var target: int = clampi(r.lane + step, 0, LANES.size() - 1)
	if target == r.lane:
		return
	r.lane_from = r.y
	r.lane = target
	r.lane_t = 0.0


func _use_nitro(r: Racer, tell: bool) -> bool:
	if r.finish_time >= 0.0 or phase != Phase.RACE and phase != Phase.FINISH:
		return false
	if r.nitro < NITRO_COST - 0.001 or r.boost > 0.1:
		if tell and r == player and r.boost <= 0.1:
			_hud.call("toast", "Chưa đủ bốc ga! Núp gió hay uống nước mía đi!", Color(1.0, 0.75, 0.5), 0.9)
		return false
	r.nitro -= NITRO_COST
	r.boost = NITRO_TIME
	r.nitro_used += 1
	if r == player:
		_play(&"dash", -2.0)
		Audio.sfx(&"bike_start", -8.0, 1.3)
		if phase == Phase.RACE:
			_hud.call("toast", "BỐC GA!!!", Color(1.0, 0.6, 0.2), 0.7)
		_shake = 0.15
	fx.emit(&"nitro", Vector2(r.x, r.y))
	return true


# ================================================================== đối thủ

## Tốc độ hành trình của đối thủ: pace của preset ± kéo giãn nhẹ (tới 85% quãng đường).
func _rival_cruise() -> float:
	var cruise: float = float(rider.get("pace", 235.0))
	if rival.x < TRACK_LEN * RUBBER_END and player.finish_time < 0.0:
		var gap: float = rival.x - player.x
		var rubber: float = float(rider.get("rubber", 0.05))
		if gap > 200.0:
			cruise *= 1.0 - rubber
		elif gap < -160.0:
			cruise *= 1.0 + rubber
	return cruise


## Đối thủ: trễ xuất phát, né chướng ngại theo skill, bốc ga ở các mốc, thỉnh thoảng đổi làn cho sinh động.
## Trả về có giữ ga hay không.
func _rival_think(dt: float) -> bool:
	if rival.finish_time >= 0.0:
		return false
	if _rival_delay > 0.0:
		_rival_delay -= dt
		return false
	var look: float = float(rider.get("look", 180.0))
	var before: int = rival.lane
	_ai_steer(rival, float(rider.get("skill", 0.7)), look, _rival_decided, _rng_rival)
	if rival.lane == before and rival.lane_t >= 1.0 and _rng_rival.randf() < 0.22 * dt:
		var step: int = -1 if _rng_rival.randf() < 0.5 else 1
		var target: int = clampi(rival.lane + step, 0, 2)
		if target != rival.lane and _threat_dist(rival, target, look * 1.5) >= FAR:
			_change_lane(rival, step)
	var marks: Array = rider.get("nitro_at", [])
	if _rival_nitro_k < marks.size() and rival.x / TRACK_LEN >= float(marks[_rival_nitro_k]):
		_rival_nitro_k += 1
		rival.nitro = maxf(rival.nitro, NITRO_COST)
		_use_nitro(rival, false)
	return true


## Lái né: thấy chướng ngại trên làn trong tầm "look" thì quyết định (một lần cho mỗi chướng ngại) có né hay
## không theo xác suất skill; né thì đổi sang làn trống xa nhất (ưu tiên làn kề).
func _ai_steer(r: Racer, skill: float, look: float, decided: Dictionary, rng: RandomNumberGenerator) -> void:
	if r.lane_t < 1.0 or r.finish_time >= 0.0:
		return
	var threat: Hazard = _first_threat(r, r.lane, look)
	if threat == null:
		return
	var key: int = threat.get_instance_id()
	if not decided.has(key):
		decided[key] = rng.randf() < skill
	if not bool(decided[key]):
		return
	var here: float = threat.x - r.x
	var best: int = r.lane
	var best_score: float = here
	for lane in range(LANES.size()):
		if lane == r.lane:
			continue
		var d: float = _threat_dist(r, lane, look * 1.4)
		if absi(lane - r.lane) == 2 and _threat_dist(r, 1, 60.0) < FAR:
			continue # làn giữa đang kẹt sát bên
		var score: float = minf(d, look * 2.0) - float(absi(lane - r.lane)) * 20.0
		if score > best_score + 8.0:
			best = lane
			best_score = score
	if best != r.lane:
		_change_lane(r, signi(best - r.lane))


func _first_threat(r: Racer, lane: int, look: float) -> Hazard:
	var found: Hazard = null
	var best: float = FAR
	var ly: float = LANES[lane]
	for hz in _hazards:
		if hz.done or hz.hit.has(r.id):
			continue
		var dx: float = hz.x - r.x
		if dx < -(hz.w + RIDER_HALF) or dx > look or dx >= best:
			continue
		var span: Vector2 = _hazard_span(hz, r)
		if span.y + hz.depth + RIDER_DEPTH < ly or span.x - hz.depth - RIDER_DEPTH > ly:
			continue
		best = dx
		found = hz
	return found


func _threat_dist(r: Racer, lane: int, look: float) -> float:
	var hz: Hazard = _first_threat(r, lane, look)
	return FAR if hz == null else hz.x - r.x


## Khoảng y mà chướng ngại sẽ quét qua cho tới lúc xe r tới nơi (động vật đang băng qua đường).
func _hazard_span(hz: Hazard, r: Racer) -> Vector2:
	if hz.vy == 0.0 or not hz.active:
		return Vector2(hz.y, hz.y)
	var closing: float = maxf(r.v - hz.vx, 60.0)
	var t: float = maxf(hz.x - r.x, 0.0) / closing
	var y2: float = move_toward(hz.y, hz.y_end, absf(hz.vy) * t)
	return Vector2(minf(hz.y, y2), maxf(hz.y, y2))


# ================================================================== tự lái (test)

func _autopilot(_dt: float) -> void:
	var s: float = clampf(autopilot_skill, 0.0, 1.0)
	_auto_gas = true
	if s < 0.5:
		# Lơ mơ: nhả ga từng đợt.
		_auto_gas = fmod(_race_time + 0.7, 3.0) < 1.6 + 2.8 * s
	var look: float = 70.0 + 200.0 * s
	var before: int = player.lane
	_ai_steer(player, s, look, _auto_decided, _rng_auto)
	if player.lane == before and player.lane_t >= 1.0 and s >= 0.7:
		_auto_seek(look)
	if s >= 0.5 and player.boost <= 0.0 and player.nitro >= NITRO_COST and player.v > 200.0 \
			and _threat_dist(player, player.lane, 240.0) >= FAR:
		_use_nitro(player, false)
	elif s > 0.15 and s < 0.5 and player.nitro >= 2.0 * NITRO_COST and player.boost <= 0.0:
		_use_nitro(player, false)


## Người lái giỏi: tạt qua lấy ly nước mía, hoặc vô núp gió sau xe đối thủ khi làn đó trống.
func _auto_seek(look: float) -> void:
	for p in _pickups:
		var dx: float = p.x - player.x
		if p.taken or dx < 30.0 or dx > 250.0 or p.lane == player.lane:
			continue
		var target: int = player.lane + signi(p.lane - player.lane)
		if _threat_dist(player, target, dx + 40.0) >= FAR:
			_change_lane(player, signi(p.lane - player.lane))
			return
	var gap: float = rival.x - player.x
	if gap > 30.0 and gap < 170.0 and rival.lane != player.lane and rival.lane_t >= 1.0:
		var target2: int = player.lane + signi(rival.lane - player.lane)
		if _threat_dist(player, target2, look) >= FAR:
			_change_lane(player, signi(rival.lane - player.lane))


# ================================================================== va chạm, núp gió, về đích

func _update_hazards(dt: float) -> void:
	for hz in _hazards:
		hz.anim += dt
		if hz.vx != 0.0 and (phase == Phase.RACE or phase == Phase.FINISH):
			hz.x += hz.vx * dt
		if hz.vy != 0.0 and not hz.done:
			if not hz.active:
				var nearest: float = FAR
				for r in _racers:
					var dx: float = hz.x - r.x
					if dx >= 0.0:
						nearest = minf(nearest, dx)
				if nearest <= hz.trigger:
					hz.active = true
					if absf(hz.x - player.x) < 420.0:
						_animal_call(hz.kind, 0.6)
			else:
				hz.y = move_toward(hz.y, hz.y_end, absf(hz.vy) * dt)
				if is_equal_approx(hz.y, hz.y_end):
					hz.done = true
		if hz.node != null:
			hz.node.position = Vector2(roundf(hz.x), roundf(hz.y))
			hz.node.queue_redraw()


func _contacts(r: Racer) -> void:
	for hz in _hazards:
		if hz.hit.has(r.id) or hz.passed.has(r.id):
			continue
		var dx: float = hz.x - r.x
		var reach: float = hz.w + RIDER_HALF - 4.0
		if dx > reach:
			continue
		var dy: float = absf(hz.y - r.y)
		if dx >= -reach:
			if dy <= hz.depth + RIDER_DEPTH and not hz.done:
				_hit(r, hz)
			continue
		hz.passed[r.id] = true
		if dy <= hz.depth + RIDER_DEPTH + 16.0 and not hz.done and hz.y > ANIMAL_TOP and hz.y < ANIMAL_BOTTOM:
			r.near += 1
			r.nitro = minf(r.nitro + NEAR_GAIN, 1.0)
			if r == player:
				_hud.call("toast", "Sượt qua! +bốc ga", Color(0.7, 1.0, 0.6), 0.7)
				_play(&"whiff", -8.0, 1.4)
				fx.emit(&"near_miss", Vector2(r.x, r.y))
	if r != player:
		return
	for p in _pickups:
		if p.taken or absf(p.x - r.x) > 16.0 or absf(LANES[p.lane] - r.y) > 9.0:
			continue
		p.taken = true
		p.node.visible = false
		r.pickups += 1
		r.nitro = minf(r.nitro + PICKUP_GAIN, 1.0)
		_hud.call("toast", "Ly nước mía mát lạnh! +bốc ga", Color(0.75, 1.0, 0.55), 0.9)
		Audio.sfx(&"coin", -8.0, 1.3)
		_burst(Vector2(p.x, LANES[p.lane] - 10.0), Color(0.85, 0.95, 0.5), 8, 30.0, 0.5)
		fx.emit(&"pickup", Vector2(p.x, LANES[p.lane]))


func _hit(r: Racer, hz: Hazard) -> void:
	hz.hit[r.id] = true
	r.hits += 1
	if hz.kind == &"cart":
		r.v = minf(r.v, hz.vx * 0.85)
	else:
		r.v *= hz.slow
	r.boost = 0.0
	r.jolt = 0.35
	var pos := Vector2(r.x + 14.0, r.y - 2.0)
	match hz.kind:
		&"pothole", &"cart":
			_burst(pos, Color(0.55, 0.5, 0.45), 10, 40.0, 0.5)
			_play(&"hit_heavy", -4.0 if r == player else -10.0)
		&"puddle":
			r.slide = 0.5
			_burst(pos, Color(0.7, 0.85, 0.95), 12, 45.0, 0.6)
			Audio.sfx(&"splash", -6.0 if r == player else -12.0)
		&"rice":
			r.slow = 0.8
			_burst(pos, Color(0.95, 0.8, 0.35), 14, 35.0, 0.7)
			_play(&"whiff", -6.0, 0.8)
		&"chickens", &"ducks":
			_burst(pos + Vector2(0, -6), Color(0.98, 0.96, 0.9), 10, 40.0, 0.9)
			_burst(pos + Vector2(0, -6), Color(0.85, 0.3, 0.2) if hz.kind == &"chickens" else Color(0.95, 0.8, 0.3), 5, 30.0, 0.8)
			_animal_call(hz.kind, 1.0)
			hz.vy *= 2.5 # chạy tán loạn
		&"dog":
			_burst(pos, Color(0.85, 0.65, 0.3), 6, 30.0, 0.5)
			_play(&"hit_light", -4.0)
	if r == player:
		_shake = 0.25
		var text: String = String(HIT_TEXT.get(hz.kind, "Ui da!"))
		if hz.kind == &"pothole":
			text = HIT_TEXT[&"pothole"] if not _pothole_told else "Lại ổ gà!"
			_pothole_told = true
		_hud.call("toast", text, Color(1.0, 0.6, 0.45), 1.2)
		fx.emit(&"bump", pos)
	elif absf(r.x - player.x) < 300.0:
		_hud.call("toast", "%s dính %s!" % [String(rider.get("name", "")), _hazard_name(hz.kind)], Color(0.7, 0.95, 1.0), 0.9)


func _hazard_name(kind: StringName) -> String:
	return String({&"pothole": "ổ gà", &"puddle": "vũng nước", &"rice": "lúa phơi", &"chickens": "bầy gà",
		&"ducks": "bầy vịt", &"dog": "con chó", &"cart": "xe ba gác"}.get(kind, "chướng ngại"))


func _animal_call(kind: StringName, loud: float) -> void:
	match kind:
		&"chickens":
			Audio.sfx(&"rooster_crow", -16.0 + 6.0 * loud, 1.6)
		&"ducks":
			_play(&"select", -10.0 + 4.0 * loud, 0.6)
		&"dog":
			_play(&"hit_light", -12.0 + 4.0 * loud, 0.7)


func _draft(dt: float) -> void:
	var gap: float = rival.x - player.x
	_drafting = phase == Phase.RACE and player.finish_time < 0.0 and gap > 26.0 and gap < 130.0 \
		and absf(rival.y - player.y) < 6.0 and player.v > 120.0
	if _drafting:
		player.nitro = minf(player.nitro + DRAFT_GAIN * dt, 1.0)
		if not _draft_told:
			_draft_told = true
			_hud.call("toast", "Núp gió sau đít xe – bốc ga đầy dần!", Color(0.7, 0.9, 1.0), 1.4)


func _check_place() -> void:
	var place: int = 1 if player.x >= rival.x else 2
	if place != _last_place and phase == Phase.RACE:
		if place == 2 and _horn_cool <= 0.0:
			_horn_cool = 5.0
			Audio.sfx(&"bike_horn", -6.0)
			var taunts: Array = rider.get("taunt", [])
			if not taunts.is_empty():
				_hud.call("bubble", String(taunts[_rng_fx.randi_range(0, taunts.size() - 1)]))
			fx.emit(&"horn", Vector2(rival.x, rival.y))
		_last_place = place


func _check_finish(dt: float) -> void:
	for r in _racers:
		if r.finish_time < 0.0 and r.x >= TRACK_LEN:
			r.finish_time = _race_time - (r.x - TRACK_LEN) / maxf(r.v, 1.0)
			var other: Racer = rival if r == player else player
			if _first_finish < 0.0:
				_first_finish = r.finish_time
				phase = Phase.FINISH
				_backdrop.set("cheer", 3.0)
				_front.set("cheer", 3.0)
				_play(&"cheer", -4.0)
				fx.emit(&"finish", Vector2(r.x, r.y))
				if TRACK_LEN - other.x < 75.0:
					_photo = true
					_photo_real = 0.0
					_time_scale = 0.25
					_hud.call("show_banner", "SÁT NÚT!!", Color(1.0, 0.95, 0.5))
				else:
					_hud.call("show_banner", "VỀ ĐÍCH!" if r == player else "%s VỀ TRƯỚC!" % String(rider.get("name", "")).to_upper(),
						Color(1.0, 0.85, 0.3) if r == player else Color(1.0, 0.55, 0.45))
			elif _photo:
				_hud.call("show_banner", "VỀ NHẤT!" if other == player else "THUA GANG TẤC!",
					Color(1.0, 0.85, 0.3) if other == player else Color(1.0, 0.55, 0.45))
	if phase != Phase.FINISH:
		return
	_after_finish += dt
	var both: bool = player.finish_time >= 0.0 and rival.finish_time >= 0.0
	if (both and _after_finish > 1.6 and not _photo) or _after_finish > FINISH_WAIT:
		_enter_result()


func _enter_result() -> void:
	# Xe chưa về: ước thời gian theo quãng còn lại.
	for r in _racers:
		if r.finish_time < 0.0:
			r.finish_time = _race_time + (TRACK_LEN - r.x) / maxf(r.v, 120.0)
	phase = Phase.RESULT
	_phase_time = 0.0
	_photo = false
	_time_scale = 1.0
	var won: bool = player.finish_time <= rival.finish_time
	var gap: float = absf(rival.finish_time - player.finish_time)
	result = {
		"cancelled": false, "won": won, "time": player.finish_time, "rival_time": rival.finish_time, "gap": gap,
		"hits": player.hits, "near_misses": player.near, "nitro_used": player.nitro_used, "pickups": player.pickups,
		"top_kmh": roundf(player.top * KMH_PER_PX), "photo_finish": gap < 0.35, "rider": rider.get("id", &""),
		"rival_hits": rival.hits,
	}
	Audio.jingle(&"victory" if won else &"defeat")
	var who: String = String(rider.get("name", "Đối thủ"))
	var lines: PackedStringArray = []
	lines.append("Bạn: %s     %s: %s" % [Hud.format_time(player.finish_time), who, Hud.format_time(rival.finish_time)])
	lines.append(("Hơn %.2f giây" if won else "Thua %.2f giây") % gap + ("  –  SÁT NÚT!" if gap < 0.35 else ""))
	lines.append("")
	lines.append("Tốc độ cao nhất: %d km/h   ·   Bốc ga: %d lần" % [int(result["top_kmh"]), player.nitro_used])
	lines.append("Va chướng ngại: %d   ·   Sượt qua: %d   ·   Nước mía: %d" % [player.hits, player.near, player.pickups])
	_hud.call("show_result", "VỀ NHẤT!" if won else "VỀ NHÌ…", Color(1.0, 0.85, 0.3) if won else Color(1.0, 0.55, 0.45),
		"\n".join(lines), "[E] Tiếp tục")


func _end(r: Dictionary) -> void:
	if not _running:
		return
	_running = false
	phase = Phase.DONE
	r["cancelled"] = bool(r.get("cancelled", false))
	r["won"] = bool(r.get("won", false))
	r["rider"] = rider.get("id", &"")
	result = r
	Audio.engine(false)
	if _rival_emitter != null:
		_rival_emitter.stop()
	finished.emit.call_deferred(r)


# ================================================================== âm thanh

func _play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _sfx != null:
		_sfx.call("play", sound, volume_db, pitch)


func _update_engine_audio() -> void:
	if not _running:
		return
	var throttle: float = 0.0
	if phase == Phase.INTRO or phase == Phase.COUNTDOWN:
		throttle = 0.35 if _gas_held() else 0.0
	elif phase == Phase.RACE or phase == Phase.FINISH:
		var ratio: float = clampf(player.v / V_MAX, 0.0, 1.4)
		throttle = clampf(0.15 + 0.85 * ratio, 0.0, 1.0) if _gas_held() and player.finish_time < 0.0 else 0.5 * ratio
	Audio.engine(true, throttle)
	if _rival_emitter != null:
		_rival_emitter.pitch_scale = clampf(0.8 + 0.45 * rival.v / V_MAX, 0.6, 1.5)


# ================================================================== hình

func _place_racers() -> void:
	for r in _racers:
		var bob: float = 0.0
		if r.jolt > 0.0:
			bob = -3.0 if r.jolt > 0.25 else -1.0
		elif r.v > 30.0 and int(r.travel / 9.0) % 7 == 0:
			bob = -1.0
		var wobble: float = roundf(sin(_clock * 40.0) * 2.0) if r.slide > 0.0 else 0.0
		r.node.position = Vector2(roundf(r.x + wobble), roundf(r.y))
		var visual: Node2D = r.node.get_child(0) as Node2D
		if visual != null:
			visual.position.y = bob
	# Bánh xe quay theo quãng đường đã chạy.
	if not _rival_frames.is_empty():
		_rival_sprite.texture = _rival_frames[int(rival.travel / 15.4) % _rival_frames.size()]
	if _player_bike != null:
		if _bike_a == null:
			_bike_a = _player_bike.texture
			_bike_b = load("res://game/art/bike_side_b.png") if ResourceLoader.exists("res://game/art/bike_side_b.png") else _bike_a
		_player_bike.texture = _bike_b if player.v > 5.0 and int(player.travel / 12.0) % 2 == 1 else _bike_a
	if _wheel_script != null:
		var frame: int = int(player.travel / 12.0) % 2 if player.v > 5.0 else 0
		if frame != _wheel_frame:
			_wheel_frame = frame
			_wheel_script.call("set_rider_wheel_frame", _player_visual, frame)


func _update_view(delta: float) -> void:
	_place_racers()
	_zoom = move_toward(_zoom, PHOTO_ZOOM if _photo else ZOOM, delta * 4.0)
	_camera.zoom = Vector2(_zoom, _zoom)
	var vis: Vector2 = get_viewport_rect().size
	_view = vis / _zoom
	var shake := Vector2.ZERO
	if _shake > 0.0:
		shake = Vector2(_rng_fx.randi_range(-1, 1), _rng_fx.randi_range(-1, 1))
	var center := Vector2(roundf(player.x + _view.x * 0.2), VIEW_CENTER_Y)
	if _photo:
		center = Vector2(roundf(TRACK_LEN), VIEW_CENTER_Y + 6.0)
	_camera.position = center + shake
	_cam_left = roundf(center.x - _view.x * 0.5)
	for layer in [_backdrop, _front]:
		layer.set("cam_left", _cam_left)
		layer.set("view_w", _view.x)
		layer.set("view_top", center.y - _view.y * 0.5)
		layer.set("view_h", _view.y)
		layer.set("time", _clock)
		layer.set("cheer", maxf(float(layer.get("cheer")) - delta, 0.0))
		(layer as CanvasItem).queue_redraw()
	for p in _pickups:
		if not p.taken and absf(p.x - player.x) < _view.x:
			p.node.queue_redraw()
	_ground.queue_redraw()
	_fx.queue_redraw()
	_overlay.queue_redraw()
	# HUD.
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var sign_rect: Rect2 = Backdrop.GATE_SIGN
	var tl: Vector2 = canvas * Vector2(TRACK_LEN + sign_rect.position.x, sign_rect.position.y)
	var br: Vector2 = canvas * Vector2(TRACK_LEN + sign_rect.end.x, sign_rect.end.y)
	_hud.call("set_gate", Rect2(tl, br - tl), absf(TRACK_LEN - center.x) < _view.x * 0.5 + 60.0 and phase != Phase.RESULT)
	_hud.call("place_bubble", canvas * Vector2(rival.x, rival.y - 64.0))
	_hud.set("player_progress", player.x / TRACK_LEN)
	_hud.set("rival_progress", rival.x / TRACK_LEN)
	_hud.set("place", 1 if (player.finish_time >= 0.0 and (rival.finish_time < 0.0 or player.finish_time <= rival.finish_time)) \
		or (player.finish_time < 0.0 and rival.finish_time < 0.0 and player.x >= rival.x) else 2)
	_hud.set("kmh", player.v * KMH_PER_PX)
	_hud.set("nitro", player.nitro)
	_hud.set("boosting", player.boost > 0.0)
	_hud.set("drafting", _drafting)
	_hud.set("left_m", (TRACK_LEN - player.x) / PX_PER_M)
	_hud.set("race_time", player.finish_time if player.finish_time >= 0.0 else _race_time)


## Bóng xe/vật, ổ gà, vũng nước, lúa phơi (nằm sát mặt đường, dưới mọi vật).
func _draw_ground() -> void:
	var left: float = _cam_left - 60.0
	var right: float = _cam_left + _view.x + 60.0
	for hz in _hazards:
		if hz.x < left or hz.x > right:
			continue
		var p := Vector2(roundf(hz.x), roundf(hz.y))
		match hz.kind:
			&"pothole":
				_ellipse(p + Vector2(0, -1), 12.0, 4.0, Color(0.45, 0.43, 0.4))
				_ellipse(p + Vector2(0, -1), 10.0, 3.0, Color(0.2, 0.18, 0.17))
				_ellipse(p + Vector2(1, 0), 7.0, 2.0, Color(0.29, 0.27, 0.25))
				_ground.draw_rect(Rect2(p + Vector2(-9, -4), Vector2(18, 1)), Color(0.78, 0.76, 0.72))
				_ground.draw_rect(Rect2(p + Vector2(-14, -2), Vector2(3, 1)), Color(0.55, 0.53, 0.5))
				_ground.draw_rect(Rect2(p + Vector2(12, 1), Vector2(3, 1)), Color(0.55, 0.53, 0.5))
			&"puddle":
				_ellipse(p + Vector2(0, -1), 18.0, 5.0, Color(0.42, 0.55, 0.62))
				_ellipse(p + Vector2(-1, -1), 15.0, 4.0, Color(0.5, 0.66, 0.76))
				var glint: float = roundf(sin(_clock * 3.0 + hz.x) * 3.0)
				_ground.draw_rect(Rect2(p + Vector2(-6 + glint, -3), Vector2(5, 1)), Color(0.9, 0.97, 1.0, 0.85))
				_ground.draw_rect(Rect2(p + Vector2(5 - glint, 0), Vector2(3, 1)), Color(0.9, 0.97, 1.0, 0.6))
			&"rice":
				var mat := Rect2(p + Vector2(-32, -8), Vector2(64, 13))
				_ground.draw_rect(mat.grow(1.0), Color(0.55, 0.45, 0.3))
				_ground.draw_rect(mat, Color(0.9, 0.76, 0.32))
				for k in range(22):
					var h: int = Backdrop.hash_i(int(hz.x) + k, 5)
					_ground.draw_rect(Rect2(mat.position + Vector2(float(h % 62), float((h >> 6) % 12)), Vector2(1, 1)),
						Color(0.75, 0.58, 0.2) if k % 2 == 0 else Color(1.0, 0.9, 0.5))
				# Cây cào gỗ để bên cạnh.
				_ground.draw_line(p + Vector2(18, -9), p + Vector2(30, -14), Color(0.45, 0.3, 0.18), 1.0)
	# Bóng dưới xe, xe ba gác, gà vịt.
	for r in _racers:
		_ellipse(Vector2(roundf(r.x), roundf(r.y)), 26.0, 3.0, Color(0, 0, 0, 0.28))
	for hz in _hazards:
		if not hz.flat and hz.x > left and hz.x < right:
			_ellipse(Vector2(roundf(hz.x), roundf(hz.y)), 30.0 if hz.kind == &"cart" else 9.0, 2.0, Color(0, 0, 0, 0.22))


func _ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var rows: int = int(ry)
	for k in range(-rows, rows + 1):
		var half: float = roundf(rx * sqrt(maxf(1.0 - pow(float(k) / (ry + 0.5), 2.0), 0.0)))
		_ground.draw_rect(Rect2(center.x - half, center.y + float(k), half * 2.0, 1.0), color)


## Gà, vịt, chó băng qua đường; xe ba gác chở bao lúa.
func _draw_hazard(hz: Hazard) -> void:
	var node: Node2D = hz.node
	var moving: bool = hz.active and not hz.done
	match hz.kind:
		&"chickens":
			for k in range(3):
				var t: Texture2D = _tex("B_ga_nha_01", int(hz.anim * (10.0 if moving else 3.0)) + k)
				var off := Vector2(-12 + k * 11, (k % 2) * 3 - 1)
				_draw_stand(node, t, off, k == 1, Color(0.95, 0.35, 0.2))
		&"ducks":
			for k in range(4):
				var t: Texture2D = _tex("E_vit_01", int(hz.anim * (8.0 if moving else 2.0)) + k)
				var off := Vector2((k % 2) * 3 - 1, -12 + k * 8)
				_draw_stand(node, t, off, false, Color(0.95, 0.95, 0.85))
		&"dog":
			var t: Texture2D = _tex("NV_cho_vang", int(hz.anim * (12.0 if moving else 3.0)))
			_draw_stand(node, t, Vector2.ZERO, false, Color(0.85, 0.65, 0.3))
		&"cart":
			_draw_cart(node, hz)


func _draw_stand(node: Node2D, t: Texture2D, off: Vector2, flip: bool, fallback: Color) -> void:
	if t == null:
		node.draw_rect(Rect2(off + Vector2(-5, -8), Vector2(10, 8)), fallback)
		return
	var size: Vector2 = t.get_size()
	var pos := Vector2(roundf(off.x - size.x * 0.5), roundf(off.y - size.y))
	if flip:
		node.draw_set_transform(pos + Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		node.draw_texture(t, Vector2.ZERO)
		node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		node.draw_texture(t, pos)


func _draw_cart(node: Node2D, hz: Hazard) -> void:
	var wood := Color(0.55, 0.36, 0.2)
	var dark := Color(0.3, 0.18, 0.1)
	var spin: int = int(hz.x / 6.0) % 2
	# Bánh xe.
	for wx in [-18.0, 16.0]:
		node.draw_circle(Vector2(wx, -5), 5.0, Color(0.12, 0.12, 0.12))
		node.draw_circle(Vector2(wx, -5), 2.0, Color(0.6, 0.6, 0.6))
		node.draw_rect(Rect2(Vector2(wx - 1 + spin, -9), Vector2(1, 8)), Color(0.4, 0.4, 0.4))
	# Thùng xe + bao lúa.
	node.draw_rect(Rect2(-26, -14, 46, 5), wood)
	node.draw_rect(Rect2(-26, -14, 46, 1), wood.lightened(0.25))
	node.draw_rect(Rect2(-26, -10, 46, 1), dark)
	for k in range(4):
		var sx: float = -24.0 + float(k) * 10.0
		node.draw_rect(Rect2(sx, -23 + (k % 2), 10, 9), Color(0.88, 0.84, 0.7))
		node.draw_rect(Rect2(sx, -23 + (k % 2), 10, 1), Color(0.95, 0.93, 0.85))
		node.draw_rect(Rect2(sx + 9, -22 + (k % 2), 1, 8), Color(0.65, 0.6, 0.48))
	node.draw_rect(Rect2(-19, -31, 10, 8), Color(0.88, 0.84, 0.7))
	# Người đạp/chạy ba gác ngồi trước (đội nón lá).
	var bob: float = float(int(hz.anim * 6.0) % 2)
	node.draw_rect(Rect2(20, -22 + bob, 6, 9), Color(0.3, 0.45, 0.7))
	node.draw_rect(Rect2(21, -25 + bob, 4, 3), Color(0.85, 0.65, 0.5))
	node.draw_colored_polygon(PackedVector2Array([Vector2(17, -25 + bob), Vector2(29, -25 + bob), Vector2(23, -30 + bob)]), Color(0.95, 0.86, 0.55))
	node.draw_rect(Rect2(21, -13, 3, 6), Color(0.2, 0.2, 0.25))
	node.draw_rect(Rect2(26, -18, 4, 1), Color(0.2, 0.2, 0.2))


## Ly nước mía (có ống hút) lơ lửng nhấp nhô, có vầng sáng.
func _draw_pickup(p: Pickup) -> void:
	if p.taken:
		return
	var node: Node2D = p.node
	var bob: float = roundf(sin(_clock * 4.0 + p.x) * 1.5)
	var base := Vector2(0, -12 + bob)
	node.draw_circle(base + Vector2(0, -2), 8.0, Color(1.0, 1.0, 0.7, 0.18 + 0.1 * sin(_clock * 6.0)))
	node.draw_rect(Rect2(base + Vector2(-4, -6), Vector2(8, 10)), Color(0.9, 0.95, 0.95, 0.85))
	node.draw_rect(Rect2(base + Vector2(-3, -3), Vector2(6, 6)), Color(0.75, 0.85, 0.35))
	node.draw_rect(Rect2(base + Vector2(-3, -3), Vector2(6, 1)), Color(0.95, 0.95, 0.75))
	node.draw_rect(Rect2(base + Vector2(1, -11), Vector2(1, 7)), Color(0.9, 0.2, 0.2))
	node.draw_rect(Rect2(base + Vector2(2, -11), Vector2(2, 1)), Color(0.9, 0.2, 0.2))
	_ellipse_on(node, Vector2(0, 0), 5.0, 1.0, Color(0, 0, 0, 0.22))


func _ellipse_on(node: Node2D, center: Vector2, rx: float, ry: float, color: Color) -> void:
	for k in range(-int(ry), int(ry) + 1):
		var half: float = roundf(rx * sqrt(maxf(1.0 - pow(float(k) / (ry + 0.5), 2.0), 0.0)))
		node.draw_rect(Rect2(center.x - half, center.y + float(k), half * 2.0, 1.0), color)


func _tex(node_name: String, frame: int) -> Texture2D:
	var list: Array = _textures.get(node_name, [])
	if list.is_empty():
		return null
	return list[posmod(frame, list.size())]


# ------------------------------------------------------------------ hiệu ứng hạt, lửa bốc ga, gió

func _burst(pos: Vector2, color: Color, count: int, speed: float, life: float) -> void:
	for k in range(count):
		var angle: float = _rng_fx.randf_range(-PI, 0.0)
		var v := Vector2(cos(angle), sin(angle)) * _rng_fx.randf_range(speed * 0.4, speed)
		_particles.append({"p": pos, "v": v, "life": life, "max": life, "c": color, "g": 90.0, "s": 1.0 + float(k % 2)})


func _trail(r: Racer, dt: float) -> void:
	# khói pô xám nhẹ phía sau xe (cả khi chạy chậm), bụi đường khi chạy nhanh
	r.puff += dt
	if r.v > 5.0 and r.puff > 0.12:
		r.puff = 0.0
		_particles.append({"p": Vector2(r.x - 30.0, r.y - 8.0), "v": Vector2(_rng_fx.randf_range(-30.0, -12.0), _rng_fx.randf_range(-10.0, -4.0)),
			"life": 0.7, "max": 0.7, "c": Color(0.75, 0.75, 0.78, 0.45), "g": -6.0, "s": 2.0})
	if r.v < 110.0:
		return
	r.dust -= dt
	if r.dust > 0.0:
		return
	r.dust = 0.07 if r.boost <= 0.0 else 0.035
	var c := Color(0.85, 0.82, 0.75, 0.55) if r.boost <= 0.0 else Color(0.8, 0.8, 0.82, 0.7)
	_particles.append({"p": Vector2(r.x - 28.0, r.y - 2.0), "v": Vector2(_rng_fx.randf_range(-25.0, -5.0), _rng_fx.randf_range(-8.0, -2.0)),
		"life": 0.5, "max": 0.5, "c": c, "g": 0.0, "s": 2.0})


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
		_fx.draw_rect(Rect2((p["p"] as Vector2).round(), Vector2(s, s)), c)
	# Lửa ống bô khi bốc ga.
	for r in _racers:
		if r.boost <= 0.0:
			continue
		var tip := Vector2(roundf(r.x) - 32.0, roundf(r.y) - 9.0)
		var flick: float = float(int(_clock * 30.0) % 3)
		_fx.draw_rect(Rect2(tip + Vector2(-6 - flick, -1), Vector2(7 + flick, 3)), Color(1.0, 0.55, 0.15, 0.9))
		_fx.draw_rect(Rect2(tip + Vector2(-3, 0), Vector2(4, 1)), Color(1.0, 0.95, 0.6))
	# Vệt gió: bốc ga thì vệt tốc độ khắp màn hình, núp gió thì vài vệt quanh xe mình.
	var top: float = VIEW_CENTER_Y - _view.y * 0.5
	if player.boost > 0.0:
		for k in range(12):
			var h: int = Backdrop.hash_i(k, 97)
			var y: float = top + 8.0 + float(h % int(maxf(_view.y - 16.0, 1.0)))
			var span: float = _view.x + 80.0
			var x: float = _cam_left + _view.x - fmod(_clock * 700.0 + float(h % 997), span)
			_fx.draw_rect(Rect2(roundf(x), y, 16.0 + float((h >> 8) % 24), 1.0), Color(1, 1, 1, 0.45))
	elif player.v > 225.0:
		# chạy gần tốc độ tối đa: vài vệt gió mảnh quanh xe mình
		for k in range(6):
			var h2: int = Backdrop.hash_i(k, 131)
			var y2: float = player.y - 40.0 + float(h2 % 46)
			var x2: float = player.x + 60.0 - fmod(_clock * 420.0 + float(h2 % 211), 160.0)
			_fx.draw_rect(Rect2(roundf(x2), roundf(y2), 8.0 + float((h2 >> 5) % 10), 1.0), Color(1, 1, 1, 0.3))
	if _drafting:
		for k in range(4):
			var y: float = player.y - 6.0 - float(k * 9)
			var x: float = player.x + 10.0 - fmod(_clock * 220.0 + float(k) * 23.0, 70.0)
			_fx.draw_rect(Rect2(roundf(x), roundf(y), 10.0, 1.0), Color(0.85, 0.95, 1.0, 0.55))


## Báo trước chướng ngại sắp vào khung hình: dấu ◄ nhấp nháy ở mép phải, ngang làn của nó.
func _draw_overlay() -> void:
	if phase != Phase.RACE:
		return
	var right: float = _cam_left + _view.x
	for hz in _hazards:
		var ahead: float = hz.x - hz.w - right
		if ahead < 0.0 or ahead > 330.0 or hz.done:
			continue
		if hz.vy != 0.0 and not hz.active:
			continue
		var y: float = roundf(clampf(hz.y, LANES[0] - 4.0, LANES[2] + 2.0)) - 5.0
		var blink: bool = int(_clock * 6.0) % 2 == 0 or ahead < 120.0
		if not blink:
			continue
		var x: float = right - 9.0
		var color := Color(1.0, 0.35, 0.2) if hz.kind != &"cart" else Color(1.0, 0.75, 0.2)
		_overlay.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 6, y - 4), Vector2(x + 6, y + 4)]), color)
		_overlay.draw_rect(Rect2(x - 4.0, y - 3.0, 2.0, 4.0), color)
		_overlay.draw_rect(Rect2(x - 4.0, y + 2.0, 2.0, 1.0), color)
