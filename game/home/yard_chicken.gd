extends Node2D

## MỘT CON GÀ THẢ SÂN (gà thật của người chơi, GameState.chickens[index]) trong NHÀ & SÂN GÀ. Gốc toạ độ = chân chạm đất
## (y-sort trong "Actors" cùng người chơi, người nhà, đồ đạc).
## Hình: sheet gà nhỏ vẽ ở đúng mật độ điểm ảnh của nhà (game/art/home/yard/<v>_sheet.png – tools/art/build_rooster_walk.py
## thu nhỏ giữ nét từ rooster fight.aseprite / dongtao_fight_combo.aseprite; v = noi / tre / dongtao). Đổi màu lông y như
## trong trận: vật liệu FighterView.material_for_side(side) (rooster.gdshader), chỉ thay mặt nạ bộ phận + lớp trang bị
## bằng bản nhỏ cùng bố cục (yard/<v>_mask.png, yard/gear/<v>_<món>.png).
## Hành vi ban ngày: đứng (idle), đi dạo (walk = run_right phát chậm), mổ đất (peck), cào đất (scratch = bước lùi + đất
## văng), vỗ cánh nhảy (flap), gáy (crow), rượt nhau (chase/flee, chạy nhanh có bụi), uống nước ở máng ống tre (drink),
## ngó người chơi khi người chơi lại gần (look). Ban đêm: về bội (go_home → enter) rồi ngủ (sleep: ẩn mình, chỉ còn bội
## + chữ "z"); sáng ra (exit) bước ra cửa bội. Đi lại trên lưới đi được home_nav.gd, chỉ trong sân (yard_chickens.gd
## kiểm), không bao giờ bước vào ô đặc. Vương miện (ActiveMarker) trên đầu gà chiến.

const Data := preload("res://game/home/home_interior_data.gd")
const YARD_DIR: String = "res://game/art/home/yard/"
const CROWN_TEX: String = "res://game/art/home/yard/crown_small.png"

enum State { IDLE, WALK, PECK, SCRATCH, FLAP, CROW, CHASE, FLEE, DRINK, LOOK, TALK, GO_HOME, ENTER, SLEEP, EXIT }
const STATE_NAMES: Array[String] = ["idle", "walk", "peck", "scratch", "flap", "crow", "chase", "flee", "drink", "look",
	"talk", "go_home", "enter", "sleep", "exit"]

## Tốc độ (px nhà / s): đi dạo, chạy rượt, về chuồng (rảo bước).
const WALK_SPEED: float = 12.0
const RUN_SPEED: float = 38.0
const HOME_SPEED: float = 18.0
## Hoạt ảnh đi = run_right phát chậm (×) cho ra dáng bước thong thả.
const WALK_ANIM_SPEED: float = 0.55
## Người chơi lại gần trong bán kính này thì gà đứng lại ngó; đi xa hơn LOOK_RELEASE thì đi tiếp.
const LOOK_RADIUS: float = 20.0
const LOOK_RELEASE: float = 30.0
## Bóng đổ (bán kính ngang theo giống).
const SHADOW_RX: Dictionary = {"noi": 6.0, "tre": 5.0, "dongtao": 7.0}
const SHADOW_COLOR: Color = Color(0.22, 0.13, 0.08, 0.32)

static var _meta_cache: Dictionary = {}

var index: int = 0
var slot: int = 0
var chicken_id: int = -1
var side: Dictionary = {}
var variant: String = "noi"
var kit: StringName = &"rooster"
var yard: Node                      # yard_chickens.gd
var state: int = State.IDLE
var facing: int = 1
var active: bool = false
var rng := RandomNumberGenerator.new()
## Đã gặp ô không đi được (test đọc – phải luôn false).
var stepped_off: bool = false

var _sprite: Sprite2D
var _material: ShaderMaterial
var _crown: Sprite2D
var _zzz: Sprite2D
var _meta: Dictionary = {}
var _cols: int = 12
var _cell: Vector2i = Vector2i(48, 43)
var _foot: Vector2 = Vector2(21, 40)
var _seq: Array = []                # [[khung 1-based, giây], …]
var _seq_loop: bool = true
var _seq_t: float = 0.0
var _seq_i: int = 0
var _frame: int = 1
var _state_t: float = 0.0
var _path: Array[Vector2] = []
var _speed: float = WALK_SPEED
var _partner: Node2D
var _count: int = 0
var _face_x: float = 0.0
var _fx_t: float = 0.0
var _time: float = 0.0
var _alpha: float = 1.0
var _home_t: float = 0.0
var _gear_items: Array[StringName] = []


# =================================================================== dựng

static func variant_for(p_side: Dictionary) -> String:
	if Moves.kit_for_side(p_side) == Moves.KIT_DONGTAO:
		return "dongtao"
	return "tre" if int(p_side.get("breed", 0)) == 1 else "noi"


static func meta_for(v: String) -> Dictionary:
	if _meta_cache.has(v):
		return _meta_cache[v]
	var data: Dictionary = {}
	var f := FileAccess.open(YARD_DIR + v + ".json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			data = parsed
	_meta_cache[v] = data
	return data


static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)       # chưa import (editor đang mở): đọc thẳng PNG
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func setup(p_yard: Node, p_index: int, p_side: Dictionary, p_active: bool) -> void:
	yard = p_yard
	index = p_index
	slot = p_index
	side = p_side
	active = p_active
	chicken_id = int(side.get("id", -1))
	rng.seed = hash(chicken_id * 7919 + 17)
	name = "yard_chicken_%d" % index


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite = Sprite2D.new()
	_sprite.name = "Body"
	_sprite.region_enabled = true
	_sprite.centered = false
	add_child(_sprite)
	_zzz = Sprite2D.new()
	_zzz.name = "Zzz"
	_zzz.texture = load(Data.ART + "zzz.png")
	_zzz.hframes = 3
	_zzz.z_index = 1
	_zzz.visible = false
	add_child(_zzz)
	apply_side(side, active)
	_play("idle")


## Đổi dữ liệu gà (sau khi chăm, gắn đồ, đột biến…): dựng lại vật liệu đổi màu + lớp đồ; bật/tắt vương miện.
func apply_side(p_side: Dictionary, p_active: bool) -> void:
	side = p_side
	active = p_active
	variant = variant_for(side)
	kit = Moves.kit_for_side(side)
	_meta = meta_for(variant)
	_cols = int(_meta.get("cols", 12))
	var cell: Array = _meta.get("cell", [48, 43])
	_cell = Vector2i(int(cell[0]), int(cell[1]))
	var foot: Array = _meta.get("foot", [21, 40])
	_foot = Vector2(float(foot[0]), float(foot[1]))
	if _sprite == null:
		return
	_sprite.texture = _load_tex(YARD_DIR + variant + "_sheet.png")
	_sprite.offset = -_foot
	_material = FighterView.material_for_side(side)
	var mask: Texture2D = _load_tex(YARD_DIR + variant + "_mask.png")
	if mask != null:
		_material.set_shader_parameter("part_mask", mask)
	_apply_gear()
	_sprite.material = _material
	_set_crown(active)
	_refresh_frame()


## Vương miện gà chiến: chỉ con đang là gà chiến mới có node "ActiveMarker".
func _set_crown(on: bool) -> void:
	if on and _crown == null:
		_crown = Sprite2D.new()
		_crown.name = "ActiveMarker"
		_crown.texture = load(CROWN_TEX)
		_crown.z_index = 1
		add_child(_crown)
	elif not on and _crown != null:
		_crown.free()
		_crown = null


## Lớp trang bị bản nhỏ (cùng bố cục sheet nhỏ) theo đúng luật FighterView.apply_gear (mỗi ô một lớp).
func _apply_gear() -> void:
	_gear_items.clear()
	var any: bool = false
	for slot_name in FighterView.GEAR_UNIFORMS.keys():
		_material.set_shader_parameter("has_" + String(FighterView.GEAR_UNIFORMS[slot_name]), false)
	for item in FighterView.gear_items(side):
		var gslot: StringName = StringName(GameState.ITEMS.get(StringName(item), {}).get("slot", &""))
		if not FighterView.GEAR_UNIFORMS.has(gslot):
			continue
		var tex: Texture2D = _load_tex(YARD_DIR + "gear/%s_%s.png" % [variant, item])
		if tex == null:
			continue
		var u: String = String(FighterView.GEAR_UNIFORMS[gslot])
		_material.set_shader_parameter("gear_" + u, tex)
		_material.set_shader_parameter("has_" + u, true)
		_gear_items.append(StringName(item))
		any = true
	_material.set_shader_parameter("use_gear", any)


func sprite_material() -> ShaderMaterial:
	return _material


func gear_shown() -> Array[StringName]:
	return _gear_items


func state_name() -> String:
	return STATE_NAMES[state]


func is_asleep() -> bool:
	return state == State.SLEEP


## Đang ở trong bội (đã chui vào / đang ngủ) – cửa bội đóng.
func in_cage() -> bool:
	return state == State.SLEEP or (state == State.ENTER and _alpha <= 0.05)


## Đang đi lại / làm gì đó ngoài sân (không ngủ, không chui ra vào bội).
func is_roaming() -> bool:
	return state not in [State.SLEEP, State.ENTER, State.EXIT]


# =================================================================== hoạt ảnh

func _tag_range(tag: String) -> Array:
	var tags: Dictionary = _meta.get("tags", {})
	var r: Array = tags.get(tag, tags.get("idle", [1, 1]))
	return [int(r[0]), int(r[1])]


func _dur(f: int) -> float:
	var d: Array = _meta.get("durations", [])
	return float(d[f - 1]) / 1000.0 if f - 1 < d.size() else 0.1


func _play(tag: String, loop: bool = true, speed: float = 1.0) -> void:
	var r: Array = _tag_range(tag)
	var seq: Array = []
	for f in range(int(r[0]), int(r[1]) + 1):
		seq.append([f, _dur(f) / maxf(speed, 0.05)])
	_play_seq(seq, loop)


func _play_seq(seq: Array, loop: bool) -> void:
	_seq = seq
	_seq_loop = loop
	_seq_t = 0.0
	_seq_i = 0
	if not _seq.is_empty():
		_frame = int(_seq[0][0])
	_refresh_frame()


## Một cú mổ: cúi dần (3 khung peck), giữ, ngẩng lên, đứng một chút.
func _peck_seq(slow: bool) -> Array:
	var r: Array = _tag_range("peck")
	var idle0: int = int(_tag_range("idle")[0])
	var k: float = 1.6 if slow else 1.0
	var a: int = int(r[0])
	return [[a, 0.05 * k], [a + 1, 0.05 * k], [a + 2, 0.16 * k], [a + 1, 0.05 * k], [a, 0.05 * k], [idle0, 0.22 * k]]


func _anim_done() -> bool:
	return not _seq_loop and _seq_i >= _seq.size() - 1 and _seq_t >= float(_seq[_seq.size() - 1][1])


func _advance_anim(delta: float) -> void:
	if _seq.is_empty():
		return
	_seq_t += delta
	while _seq_t >= float(_seq[_seq_i][1]):
		if _seq_i >= _seq.size() - 1:
			if not _seq_loop:
				_seq_t = float(_seq[_seq_i][1])
				break
			_seq_t -= float(_seq[_seq_i][1])
			_seq_i = 0
		else:
			_seq_t -= float(_seq[_seq_i][1])
			_seq_i += 1
	_frame = int(_seq[_seq_i][0])


func _refresh_frame() -> void:
	if _sprite == null:
		return
	var i: int = _frame - 1
	_sprite.region_rect = Rect2((i % _cols) * _cell.x, (i / _cols) * _cell.y, _cell.x, _cell.y)
	_sprite.scale = Vector2(float(facing), 1.0)
	# bám điểm ảnh nhà (không nhoè/rung khi đứng ở toạ độ lẻ)
	_sprite.position = position.round() - position
	var tops: Array = _meta.get("tops", [])
	var top: float = float(tops[_tag_range("idle")[0] - 1]) if not tops.is_empty() else 4.0
	var bob: float = roundf(sin(_time * 4.0) * 1.0)
	if _crown == null:
		pass
	elif state == State.SLEEP:
		_crown.position = Vector2(0, yard.call("sleep_crown_y", slot) + bob) + _sprite.position
	else:
		_crown.position = Vector2(0, top - _foot.y - 5.0 + bob) + _sprite.position
	_sprite.modulate.a = _alpha
	queue_redraw()


func _draw() -> void:
	if state == State.SLEEP or _alpha <= 0.05:
		return
	var rx: float = float(SHADOW_RX.get(variant, 6.0))
	var b: Array = _meta.get("bottoms", [])
	var lift: float = maxf(0.0, _foot.y - float(b[_frame - 1])) if _frame - 1 < b.size() else 0.0
	var k: float = clampf(1.0 - lift / 16.0, 0.45, 1.0)
	var c := Color(SHADOW_COLOR.r, SHADOW_COLOR.g, SHADOW_COLOR.b, SHADOW_COLOR.a * _alpha * k)
	var o: Vector2 = position.round() - position
	var r: float = roundf(rx * k)
	draw_rect(Rect2(o + Vector2(-r + 1, -1), Vector2(r * 2.0 - 2.0, 1)), c)
	draw_rect(Rect2(o + Vector2(-r, 0), Vector2(r * 2.0, 1)), c)
	draw_rect(Rect2(o + Vector2(-r + 1, 1), Vector2(r * 2.0 - 2.0, 1)), c)


# =================================================================== API cho cảnh nhà

## Phát một lần hoạt ảnh vui/ăn/xìu (cảnh nhà gọi: rải lúa, tập luyện…). &"eat" mổ ăn, &"happy" vỗ cánh, &"sad" đứng im.
func play_once(kind: StringName) -> void:
	if not is_roaming():
		return
	match kind:
		&"eat":
			_enter(State.PECK)
			_count = 3
		&"happy":
			_enter(State.FLAP)
		_:
			_enter(State.IDLE)


func is_playing_once() -> bool:
	return state in [State.PECK, State.FLAP, State.CROW]


## Người chơi bấm E vào gà: đứng lại, quay sang người chơi, gáy nhẹ.
func begin_talk(at: Vector2) -> void:
	if not is_roaming():
		return
	_face_toward(at.x)
	_enter(State.TALK)


func end_talk() -> void:
	if state == State.TALK:
		_enter(State.IDLE)


## Vào bội ngủ ngay (vô nhà lúc trời tối).
func sleep_now() -> void:
	position = yard.call("sleep_point", slot)
	_alpha = 0.0
	_enter(State.SLEEP)


## Đặt ra sân (vô nhà ban ngày).
func spawn_at(p: Vector2) -> void:
	position = p
	_alpha = 1.0
	_enter(State.IDLE)
	_state_t = rng.randf_range(0.2, 1.5)


# =================================================================== máy trạng thái

func _enter(s: int) -> void:
	state = s
	_path.clear()
	match s:
		State.IDLE:
			_state_t = rng.randf_range(1.0, 3.2)
			_play("idle")
		State.WALK:
			_speed = WALK_SPEED
			_play("walk", true, WALK_ANIM_SPEED)
		State.PECK:
			_count = rng.randi_range(2, 5)
			_play_seq(_peck_seq(false), false)
		State.SCRATCH:
			_state_t = rng.randf_range(1.2, 2.2)
			_play("scratch", true, 0.8)
		State.FLAP:
			_play("flap", false)
			yard.call("feathers", position + Vector2(0, -10), 3, side)
		State.CROW:
			_play("crow", false)
		State.CHASE, State.FLEE:
			_speed = RUN_SPEED
			_state_t = rng.randf_range(1.6, 2.6)
			_play("walk", true, 1.0)
		State.DRINK:
			_speed = WALK_SPEED
			_play("walk", true, WALK_ANIM_SPEED)
		State.LOOK, State.TALK:
			_play("idle")
		State.GO_HOME:
			_speed = HOME_SPEED
			_home_t = 0.0
			_play("walk", true, 0.75)
		State.ENTER:
			_state_t = 0.0
			_play("walk", true, 0.6)
		State.SLEEP:
			_alpha = 0.0
			_play("idle")
		State.EXIT:
			_alpha = 0.0
			_state_t = 0.0
			_play("walk", true, 0.6)


func _process(delta: float) -> void:
	_time += delta
	if yard == null:
		return
	var night: bool = bool(yard.call("is_night"))
	if night and state not in [State.GO_HOME, State.ENTER, State.SLEEP, State.TALK]:
		_go_home()
	elif not night and state == State.SLEEP:
		_wake()
	match state:
		State.IDLE:
			_state_t -= delta
			_maybe_look()
			if _state_t <= 0.0:
				_pick_activity()
		State.WALK, State.DRINK:
			_maybe_look()
			if state == State.LOOK:
				pass
			elif _follow(delta):
				if state == State.DRINK:
					_face_x = float(yard.call("drink_face_x"))
					_face_toward(_face_x)
					_count = rng.randi_range(3, 5)
					state = State.PECK
					_play_seq(_peck_seq(true), false)
				else:
					_enter(State.PECK if rng.randf() < 0.45 else State.IDLE)
		State.PECK:
			if _anim_done():
				_count -= 1
				if rng.randf() < 0.35:
					yard.call("grain", position + Vector2(float(facing) * 6.0, -1.0))
				if _count <= 0:
					_enter(State.IDLE)
				else:
					_play_seq(_peck_seq(false), false)
		State.SCRATCH:
			_state_t -= delta
			_fx_t -= delta
			if _fx_t <= 0.0:
				_fx_t = 0.16
				yard.call("dirt", position + Vector2(-float(facing) * 3.0, -1.0), -facing)
			if _state_t <= 0.0:
				_enter(State.PECK)
		State.FLAP, State.CROW:
			if _anim_done():
				if state == State.FLAP:
					yard.call("dust", position, 3)
				_enter(State.IDLE)
		State.CHASE:
			_state_t -= delta
			_run_fx(delta)
			if _partner == null or not is_instance_valid(_partner) or _state_t <= 0.0:
				_end_chase()
			else:
				var to: Vector2 = (_partner as Node2D).position
				if position.distance_to(to) < 7.0:
					_end_chase()
				else:
					_step_toward(to, delta)
		State.FLEE:
			_state_t -= delta
			_run_fx(delta)
			if _follow(delta) or _state_t <= 0.0:
				_enter(State.FLAP if rng.randf() < 0.5 else State.IDLE)
		State.LOOK:
			var p: Vector2 = yard.call("player_pos")
			_face_toward(p.x)
			if position.distance_to(p) > LOOK_RELEASE:
				_enter(State.IDLE)
		State.TALK:
			pass
		State.GO_HOME:
			_home_t += delta
			var door: Vector2 = yard.call("home_point", slot)
			if _path.is_empty() and position.distance_to(door) > 1.5:
				_path = yard.call("path_to", position, door)
				if _path.is_empty():
					_path = [door] if bool(yard.call("segment_clear", position, door)) else []
			if position.distance_to(door) <= 1.5 or _follow(delta) or _home_t > 20.0:
				_enter(State.ENTER)
		State.ENTER:
			_state_t += delta
			var target: Vector2 = yard.call("sleep_point", slot)
			position = position.move_toward(target, 10.0 * delta)
			_alpha = clampf(1.0 - _state_t / 0.8, 0.0, 1.0)
			if _alpha <= 0.0:
				position = target
				_enter(State.SLEEP)
		State.SLEEP:
			pass
		State.EXIT:
			_state_t += delta
			var out: Vector2 = yard.call("home_point", slot)
			position = position.move_toward(out, 10.0 * delta)
			_alpha = clampf(_state_t / 0.6, 0.0, 1.0)
			if _alpha >= 1.0 and position.distance_to(out) < 0.5:
				_enter(State.IDLE)
	_advance_anim(delta)
	_update_sleep_fx()
	_refresh_frame()


func _go_home() -> void:
	_partner = null
	_enter(State.GO_HOME)


func _wake() -> void:
	# hiện ra ngay trong cửa bội / chân thang chuồng gỗ rồi bước ra chỗ đứng trước cửa
	position = (yard.call("home_point", slot) as Vector2) + Vector2(0, -4)
	_enter(State.EXIT)


func _maybe_look() -> void:
	var p: Vector2 = yard.call("player_pos")
	if position.distance_to(p) < LOOK_RADIUS:
		_enter(State.LOOK)
		_face_toward(p.x)


func _pick_activity() -> void:
	# đứng chồng lên con khác → tản ra (gà không đứng chập vào nhau thành một cục)
	var near: Node2D = yard.call("crowding", self, 11.0)
	if near != null:
		var away: Vector2 = (position - near.position).normalized()
		if away == Vector2.ZERO:
			away = Vector2(float(-facing), 0.3).normalized()
		var spot: Vector2 = yard.call("random_spot", position + away * 24.0, 0.0, 14.0, rng)
		if spot.x >= 0.0 and _set_path(spot):
			_enter_keep_path(State.WALK)
			return
	var roll: float = rng.randf() * 100.0
	if roll < 34.0:
		var to: Vector2 = yard.call("random_spot", position, 14.0, 52.0, rng)
		if to.x >= 0.0 and _set_path(to):
			_enter_keep_path(State.WALK)
			return
	elif roll < 52.0:
		_enter(State.PECK)
		return
	elif roll < 64.0:
		_enter(State.SCRATCH)
		return
	elif roll < 70.0:
		_enter(State.FLAP)
		return
	elif roll < 74.0:
		_enter(State.CROW)
		if variant != "dongtao" and rng.randf() < 0.5:
			yard.call("crow_sound", self)
		return
	elif roll < 82.0:
		var other: Node2D = yard.call("chase_partner", self)
		if other != null:
			_partner = other
			_face_toward(other.position.x)
			_enter(State.CHASE)
			other.call("flee_from", self)
			return
	elif roll < 90.0:
		var spot: Vector2 = yard.call("drink_point")
		if spot.x >= 0.0 and position.distance_to(spot) < 160.0 and _set_path(spot):
			_enter_keep_path(State.DRINK)
			return
	_enter(State.IDLE)


## Bị gà khác rượt: chạy ra xa một quãng.
func flee_from(chaser: Node2D) -> void:
	if not is_roaming() or state in [State.TALK, State.CHASE, State.FLEE]:
		return
	var away: Vector2 = (position - chaser.position).normalized()
	if away == Vector2.ZERO:
		away = Vector2(float(-facing), 0)
	var to: Vector2 = yard.call("random_spot", position + away * 34.0, 0.0, 22.0, rng)
	if to.x < 0.0 or not _set_path(to):
		return
	_enter_keep_path(State.FLEE)


func _end_chase() -> void:
	_partner = null
	_enter(State.CROW if rng.randf() < 0.4 else State.IDLE)


func _enter_keep_path(s: int) -> void:
	var keep: Array[Vector2] = _path.duplicate()
	_enter(s)
	_path = keep


func _set_path(to: Vector2) -> bool:
	_path.clear()
	if bool(yard.call("segment_clear", position, to)):
		_path.append(to)
		return true
	var p: Array[Vector2] = yard.call("path_to", position, to)
	if p.is_empty():
		return false
	_path = p
	return true


## Đi theo _path; true khi tới đích (hoặc kẹt).
func _follow(delta: float) -> bool:
	if _path.is_empty():
		return true
	var to: Vector2 = _path[0]
	if _step_toward(to, delta):
		_path.remove_at(0)
	elif _stuck:
		_path.clear()
		return true
	return _path.is_empty()


var _stuck: bool = false


## Bước về phía to (chỉ bước tới chỗ đi được trong sân). true khi tới nơi.
func _step_toward(to: Vector2, delta: float) -> bool:
	_stuck = false
	var d: Vector2 = to - position
	if absf(d.x) > 0.3:
		facing = 1 if d.x > 0.0 else -1
	var next: Vector2 = position.move_toward(to, _speed * delta)
	if not bool(yard.call("walkable", next)):
		_stuck = true
		return false
	position = next
	if state in [State.CHASE, State.FLEE]:
		pass
	return position.distance_to(to) < 0.01


func _run_fx(delta: float) -> void:
	_fx_t -= delta
	if _fx_t <= 0.0:
		_fx_t = 0.13
		yard.call("dust", position + Vector2(-float(facing) * 4.0, 0.0), 1)
		if rng.randf() < 0.15:
			yard.call("feathers", position + Vector2(0, -9), 1, side)


func _face_toward(x: float) -> void:
	if absf(x - position.x) > 0.5:
		facing = 1 if x > position.x else -1


func _update_sleep_fx() -> void:
	var sleeping: bool = state == State.SLEEP
	_zzz.visible = sleeping
	if not sleeping:
		return
	# chữ z bay lên từ nóc bội, lớn dần rồi tắt, lặp lại (lệch pha theo từng con)
	var t: float = fmod(_time + float(index) * 0.7, 2.4)
	var k: int = clampi(int(t / 0.8), 0, 2)
	_zzz.frame = k
	var top: float = float(yard.call("sleep_crown_y", slot))
	_zzz.position = Vector2(roundf(7.0 + t * 3.0), roundf(top + 22.0 - t * 6.0))   # bay lên trên thân bội của chính nó
	_zzz.modulate.a = 1.0 if t < 2.0 else (2.4 - t) / 0.4
