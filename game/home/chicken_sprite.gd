extends Node2D

## Con gà nhỏ có hoạt ảnh cho nhà/chuồng/bảng chăm gà. Gốc toạ độ = điểm chạm đất (chân).
## Hình: ưu tiên FighterView.make_portrait(side, tag) (kiểm bằng danh sách hàm của script rồi gọi phòng thủ). Hợp đồng
## hiện tại: trả FighterView.Portrait (Node2D, gốc = chân, nhìn phải, 1 px art = 1 đơn vị, có lớp trang bị thật,
## set_tag(tag, loop) / set_facing(±1)) → bọc trong holder scale = px_scale. Trả Texture2D cũng nhận. Không có hàm thì
## dự phòng: tự cắt khung tag trong sheet của kit (rooster / dongtao, thời lượng khung đọc từ *.json) + vật liệu
## FighterView.material_for_side (nếu có) + lớp đồ đạc vẽ bằng code (chỉ gợi hình).
## Dùng: const ChickenSprite := preload("res://game/home/chicken_sprite.gd")
##       var s = ChickenSprite.new(); s.setup(GameState.chicken_side(i), 0.3); add_child(s)

const FIGHTER_VIEW_PATH: String = "res://game/battle/fighter_view.gd"
const KITS: Dictionary = {
	&"rooster": {"sheet": "res://game/art/rooster_sheet.png", "meta": "res://game/art/rooster.json",
		"foot": Vector2(56, 105), "eat": "L_MoNhanh", "happy": "TAUNT_GayThiUy", "sad": "HIT_Nhe", "walk": "idle"},
	&"dongtao": {"sheet": "res://game/art/dongtao_sheet.png", "meta": "res://game/art/dongtao.json",
		"foot": Vector2(57, 105), "eat": "L_HucDau", "happy": "TAUNT_DamNguc", "sad": "HIT_Nhe", "walk": "walk"},
}
const CELL: Vector2i = Vector2i(128, 112)
const COLS: int = 12
## Chỗ vẽ lớp đồ (toạ độ ô sheet so với chân, gà nhìn sang phải) theo kit.
const GEAR_ANCHORS: Dictionary = {
	&"rooster": {&"head": Vector2(16, -62), &"comb": Vector2(11, -68), &"armor": Vector2(2, -34),
		&"wing": Vector2(-6, -38), &"spur": Vector2(-1, -9), &"weapon": Vector2(10, -6)},
	&"dongtao": {&"head": Vector2(21, -64), &"comb": Vector2(20, -71), &"armor": Vector2(6, -38),
		&"wing": Vector2(-4, -42), &"spur": Vector2(-3, -12), &"weapon": Vector2(8, -6)},
}

static var _meta_cache: Dictionary = {}
static var _api_checked: bool = false
static var _api_portrait: bool = false
static var _api_material: bool = false

var side: Dictionary = {}
var px_scale: float = 0.3
## 1 nhìn phải, −1 nhìn trái.
var facing: int = 1
## Đi tới đi lui quanh chỗ đứng (ngoài sân).
var wander: float = 0.0
## Bật/tắt lớp đồ vẽ bằng code (chỉ khi dùng hình dự phòng).
var show_gear: bool = true
## true nếu đang dùng FighterView.make_portrait (báo cáo/test đọc).
var used_portrait_api: bool = false

var _kit: StringName = &"rooster"
var _sprite: Sprite2D
var _portrait: Node
var _portrait_tag: String = "idle"
var _portrait_facing: int = 1
var _tag: String = "idle"
var _once: String = ""
var _t: float = 0.0
var _home_x: float = 0.0
var _wander_t: float = 0.0
var _wander_target: float = 0.0
var _breed_scale: float = 1.0


func setup(p_side: Dictionary, p_scale: float = 0.3) -> void:
	side = p_side
	px_scale = p_scale


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_kit = &"dongtao" if int(side.get("breed", 0)) == 2 else &"rooster"
	_breed_scale = 0.86 if int(side.get("breed", 0)) == 1 else 1.0   # gà tre nhỏ con hơn
	_home_x = position.x
	_wander_target = _home_x
	_t = randf() * 3.0
	_check_api()
	if _api_portrait:
		_try_portrait()
	if not used_portrait_api:
		_sprite = Sprite2D.new()
		_sprite.texture = load(String(KITS[_kit]["sheet"]))
		_sprite.region_enabled = true
		_sprite.centered = false
		_sprite.offset = -KITS[_kit]["foot"]
		if _api_material:
			var fv: Script = load(FIGHTER_VIEW_PATH)
			var mat: Variant = fv.call("material_for_side", side)
			if mat is ShaderMaterial:
				_sprite.material = mat
		add_child(_sprite)
	_apply_frame()


static func _check_api() -> void:
	if _api_checked:
		return
	_api_checked = true
	var fv: Script = load(FIGHTER_VIEW_PATH) if ResourceLoader.exists(FIGHTER_VIEW_PATH) else null
	if fv == null:
		return
	for m in fv.get_script_method_list():
		var n: String = String(m.get("name", ""))
		if n == "make_portrait":
			_api_portrait = true
		elif n == "material_for_side":
			_api_material = true


## Có hàm FighterView.make_portrait không (báo cáo/test).
static func portrait_api_available() -> bool:
	_check_api()
	return _api_portrait


func _try_portrait() -> void:
	var fv: Script = load(FIGHTER_VIEW_PATH)
	var r: Variant = fv.call("make_portrait", side, "idle")
	if r is Node2D:
		# HỢP ĐỒNG FighterView.Portrait: gốc = chân, nhìn phải, 1 px art = 1 đơn vị, gà tre đã thu nhỏ sẵn,
		# có set_tag(tag, loop) / set_facing(±1) và tự chạy hoạt ảnh.
		var holder := Node2D.new()
		holder.name = "Holder"
		holder.scale = Vector2.ONE * crisp_scale(px_scale, float(r.get("body_scale")) if r.get("body_scale") != null else 1.0)
		holder.add_child(r)
		add_child(holder)
		_portrait = r
		used_portrait_api = true
		show_gear = false
	elif r is Texture2D:
		var tex: Texture2D = r
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		var size: Vector2 = tex.get_size()
		sprite.offset = -KITS[_kit]["foot"] if Vector2i(size) == CELL else Vector2(-size.x * 0.5, -size.y)
		sprite.scale = Vector2.ONE * px_scale
		add_child(sprite)
		used_portrait_api = true
		show_gear = false


## Tỉ lệ "sắc nét" cho bảng UI (px_scale ≥ 1): làm tròn để mỗi pixel art phủ đúng số NGUYÊN pixel màn hình (sau
## co giãn cửa sổ canvas_items) – tỉ lệ lẻ (1,6 × 1,11) làm pixel art lúc 1 lúc 2 điểm ảnh, nét gà méo/răng cưa.
## body: hệ số giống (gà tre 0,9 trong Portrait). Nhỏ hơn 1 (gà nhỏ trong thế giới) thì giữ nguyên.
func crisp_scale(desired: float, body: float = 1.0) -> float:
	if desired < 1.0 or not is_inside_tree():
		return desired
	var v: float = get_viewport().get_final_transform().get_scale().x if get_viewport() != null else 1.0
	var screen: float = maxf(1.0, roundf(desired * body * v))
	return screen / maxf(body * v, 0.001)


static func _meta(kit: StringName) -> Dictionary:
	if _meta_cache.has(kit):
		return _meta_cache[kit]
	var data: Dictionary = {}
	var f := FileAccess.open(String(KITS[kit]["meta"]), FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			data = parsed
	_meta_cache[kit] = data
	return data


## Phát một lần hoạt ảnh (&"eat" mổ ăn, &"happy" vui/gáy, &"sad" xìu) rồi về idle.
func play_once(kind: StringName) -> void:
	var tag: String = String(KITS[_kit].get(String(kind), "idle"))
	if not (_meta(_kit).get("tags", {}) as Dictionary).has(tag):
		return
	_once = tag
	_t = 0.0
	if _portrait != null and _portrait.has_method("set_tag"):
		_portrait.call("set_tag", tag, false)
		_portrait_tag = tag


func is_playing_once() -> bool:
	return _once != ""


func _frames_for(tag: String) -> Array:
	var tags: Dictionary = _meta(_kit).get("tags", {})
	var r: Array = tags.get(tag, tags.get("idle", [1, 1]))
	return [int(r[0]), int(r[1])]


func _frame_at(tag: String, t: float, loop: bool) -> int:
	var rng: Array = _frames_for(tag)
	var durations: Array = _meta(_kit).get("durations", [])
	var total: float = 0.0
	for f in range(int(rng[0]), int(rng[1]) + 1):
		total += float(durations[f - 1]) / 1000.0 if f - 1 < durations.size() else 0.1
	if total <= 0.0:
		return int(rng[0])
	var tt: float = fmod(t, total) if loop else minf(t, total - 0.001)
	for f in range(int(rng[0]), int(rng[1]) + 1):
		tt -= float(durations[f - 1]) / 1000.0 if f - 1 < durations.size() else 0.1
		if tt < 0.0:
			return f
	return int(rng[1])


func _tag_length(tag: String) -> float:
	var rng: Array = _frames_for(tag)
	var durations: Array = _meta(_kit).get("durations", [])
	var total: float = 0.0
	for f in range(int(rng[0]), int(rng[1]) + 1):
		total += float(durations[f - 1]) / 1000.0 if f - 1 < durations.size() else 0.1
	return total


func _process(delta: float) -> void:
	_t += delta
	if _once != "" and _t >= _tag_length(_once):
		_once = ""
		_t = 0.0
	# Đi tới đi lui chậm rãi quanh chỗ đứng.
	var walking: bool = false
	if wander > 0.0 and _once == "":
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 5.0)
			_wander_target = _home_x + randf_range(-wander, wander)
		var dx: float = _wander_target - position.x
		if absf(dx) > 0.6:
			position.x += signf(dx) * minf(absf(dx), 9.0 * delta)
			facing = 1 if dx > 0.0 else -1
			walking = true
	_tag = _once if _once != "" else (String(KITS[_kit]["walk"]) if walking else "idle")
	_apply_frame()


func _apply_frame() -> void:
	var s: float = px_scale * _breed_scale
	if _sprite != null:
		var frame: int = _frame_at(_tag, _t, _once == "")
		var index: int = frame - 1
		_sprite.region_rect = Rect2((index % COLS) * CELL.x, (index / COLS) * CELL.y, CELL.x, CELL.y)
		_sprite.scale = Vector2(s * float(facing), s)
	elif _portrait != null:
		if _tag != _portrait_tag and _portrait.has_method("set_tag"):
			_portrait.call("set_tag", _tag, _once == "")
			_portrait_tag = _tag
		if facing != _portrait_facing and _portrait.has_method("set_facing"):
			_portrait.call("set_facing", facing)
			_portrait_facing = facing
	queue_redraw()


# ------------------------------------------------------------------ lớp đồ đạc (hình dự phòng)

static func gear_color(item: StringName) -> Color:
	var id: String = String(item)
	if id.contains("meo"):
		return Color(0.62, 0.42, 0.85)
	if id.contains("vang"):
		return Color(1.0, 0.8, 0.25)
	if id.contains("tre"):
		return Color(0.78, 0.7, 0.36)
	if id.contains("dong"):
		return Color(0.85, 0.52, 0.25)
	if id.contains("bac"):
		return Color(0.88, 0.9, 0.95)
	if id.contains("thep") or id.contains("sat"):
		return Color(0.62, 0.66, 0.72)
	if id.contains("lua"):
		return Color(0.98, 0.6, 0.72)
	if id.contains("gio"):
		return Color(0.55, 0.88, 0.95)
	if id.contains("ran"):
		return Color(0.18, 0.18, 0.2)
	if id.contains("cat"):
		return Color(0.9, 0.25, 0.2)
	if id.contains("non_bao_hiem"):
		return Color(0.98, 0.82, 0.2)
	return Color(0.8, 0.8, 0.8)


func _draw() -> void:
	if not show_gear or _sprite == null:
		return
	var s: float = px_scale * _breed_scale
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s * float(facing), s))
	var anchors: Dictionary = GEAR_ANCHORS[_kit]
	var gear: Dictionary = side.get("gear", {})
	var bob: float = 1.0 if _tag == "idle" and int(_t * 2.0) % 2 == 1 else 0.0
	for slot in [&"spur", &"wing", &"armor", &"comb", &"head", &"weapon"]:
		var item: StringName = StringName(side.get("weapon", &"")) if slot == &"weapon" else StringName(gear.get(slot, &""))
		if item == &"":
			continue
		var p: Vector2 = anchors[slot] + Vector2(0, bob if slot in [&"head", &"comb"] else 0.0)
		var col: Color = gear_color(item)
		var dark: Color = col.darkened(0.45)
		match slot:
			&"head":
				if String(item) == "khan_ran" or String(item) == "khan_meo":
					draw_rect(Rect2(p + Vector2(-9, -2), Vector2(18, 6)), col)
					for k in range(3):
						draw_rect(Rect2(p + Vector2(-7 + k * 6, -1), Vector2(2, 2)), Color(0.95, 0.95, 0.9))
				else:
					_half_disc(p + Vector2(0, 2), 10.0, col, dark)
			&"comb":
				for k in range(3):
					var bx: float = p.x - 6.0 + float(k) * 6.0
					draw_colored_polygon(PackedVector2Array([Vector2(bx - 3, p.y + 4), Vector2(bx, p.y - 5),
						Vector2(bx + 3, p.y + 4)]), col)
			&"armor":
				draw_rect(Rect2(p + Vector2(-13, -8), Vector2(26, 15)), dark)
				draw_rect(Rect2(p + Vector2(-12, -7), Vector2(24, 13)), Color(col, 0.92))
				for k in range(3):
					draw_rect(Rect2(p + Vector2(-8 + k * 7, -2), Vector2(2, 2)), dark)
			&"wing":
				var pts := PackedVector2Array()
				for k in range(12):
					var a: float = PI + PI * float(k) / 11.0
					pts.append(p + Vector2(cos(a) * 14.0, sin(a) * 7.0 + 3.0))
				draw_colored_polygon(pts, Color(col, 0.85))
				draw_polyline(pts, dark, 1.5)
			&"spur":
				draw_colored_polygon(PackedVector2Array([p + Vector2(-2, -2), p + Vector2(-10, 2), p + Vector2(-2, 3)]), col)
			&"weapon":
				match String(item):
					"quat_long":
						var fan := PackedVector2Array([p])
						for k in range(7):
							var a2: float = -PI * 0.9 + PI * 0.8 * float(k) / 6.0
							fan.append(p + Vector2(cos(a2), sin(a2)) * 14.0)
						draw_colored_polygon(fan, Color(0.95, 0.9, 0.8))
					"non_bao_hiem":
						_half_disc(anchors[&"head"] + Vector2(0, 2 + bob), 12.0, col, dark)
					_:
						draw_line(p + Vector2(-2, 0), p + Vector2(14, -3), Color(0.92, 0.94, 0.98), 3.0)
						draw_line(p + Vector2(-5, 1), p + Vector2(-1, 0), Color(0.45, 0.28, 0.15), 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _half_disc(c: Vector2, r: float, col: Color, dark: Color) -> void:
	var pts := PackedVector2Array()
	for k in range(13):
		var a: float = PI + PI * float(k) / 12.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.8))
	draw_colored_polygon(pts, col)
	draw_polyline(pts, dark, 1.5)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), dark, 2.0)
