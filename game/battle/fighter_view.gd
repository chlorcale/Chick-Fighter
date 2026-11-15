class_name FighterView
extends Node2D

## Phần hình của một chiến kê: sprite theo kit (rooster_fight_combo / dongtao_fight_combo), bóng đổ,
## đổi màu lông theo bộ phận (mặt nạ *_mask.png), chớp màu khi trúng/đỡ, bóng mờ (afterimage),
## hào quang Special và sao choáng. Chỉ hiển thị – không quyết định gameplay.

const SHEET: Texture2D = preload("res://game/art/rooster_sheet.png")
const META_PATH: String = "res://game/art/rooster.json"
const CELL := Vector2i(128, 112)
const FOOT := Vector2(56, 105)
const SCALE: float = 2.0

## Hoạt ảnh lấy theo tag của rooster_fight_combo.aseprite; thời lượng frame đúng như file art.
## Các tag ngã/văng/nằm/đứng dậy vẽ gà lùi 12 px trong ảnh (xem movelist) – bù lại bằng X_COMP_TAGS.
const X_COMP_TAGS: Array[String] = ["TE_NgaNgua", "VANG_RaXa", "NAM_Dat", "DUNG_Day"]

var kit: StringName = &"rooster"
var hue: float = 0.0
var saturation: float = 1.0
## Đổi màu theo bộ phận: {"body"|"neck"|"tail"|"legs"|"comb": [lệch hue, ×sat, ×value]}.
var colors: Dictionary = {}
var body_scale: float = 1.0
var fx_parent: Node2D
var ground_y: float = 0.0
var facing: int = 1
var shake_ticks: int = 0
var aura: float = 0.0
var stars: bool = false
var shield_ticks: int = 0

var _sprite: Sprite2D
var _material: ShaderMaterial
var _shadow: Node2D
var _bottoms: Array = []
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE
var _time: float = 0.0
var _afterimages: Array[Sprite2D] = []
var _pose_frame: int = 1
var _pose_rotation: float = 0.0
var _pose_offset: Vector2 = Vector2.ZERO
var _pose_squash: float = 1.0
var _foot: Vector2 = FOOT


## p_kit rỗng: shader đổi màu toàn bộ hình (cách cũ). Có kit: dùng mặt nạ bộ phận của kit.
static func make_material(p_hue: float, p_sat: float, p_kit: StringName = &"", p_colors: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://game/battle/rooster.gdshader")
	material.set_shader_parameter("hue_shift", p_hue)
	material.set_shader_parameter("saturation", p_sat)
	if p_kit != &"":
		material.set_shader_parameter("use_mask", true)
		material.set_shader_parameter("part_mask", Moves.kit(p_kit)["mask"])
		for part in ["body", "neck", "tail", "legs", "comb"]:
			var v: Array = p_colors.get(part, [0.0, 1.0, 1.0])
			material.set_shader_parameter(part + "_hsv", Vector3(float(v[0]), float(v[1]), float(v[2])))
	return material


## Vật liệu cho một bên đấu (kit + màu trong dữ liệu đối thủ).
static func material_for_side(side: Dictionary) -> ShaderMaterial:
	return make_material(float(side.get("hue", 0.0)), float(side.get("sat", 1.0)), Moves.kit_for_side(side),
		side.get("colors", {}))


static func sheet_for(p_kit: StringName) -> Texture2D:
	return Moves.kit(p_kit)["sheet"]


static func foot_for(p_kit: StringName) -> Vector2:
	return Moves.kit(p_kit)["foot"]


static func frame_region(frame: int) -> Rect2:
	var index: int = frame - 1
	return Rect2((index % 12) * CELL.x, (index / 12) * CELL.y, CELL.x, CELL.y)


## Frame (1-based) của tag tại thời điểm `ticks` (tính theo thời lượng trong file art).
static func tag_frame_at(tag: String, ticks: int, loop: bool = true, p_kit: StringName = &"rooster") -> int:
	var frames: Array[int] = Moves.tag_frames(tag, p_kit)
	var total: int = Moves.tag_ticks(tag, p_kit)
	var t: int = ticks % total if loop else mini(ticks, total - 1)
	for f in frames:
		t -= Moves.frame_ticks(f, p_kit)
		if t < 0:
			return f
	return frames[frames.size() - 1]


func _ready() -> void:
	_bottoms = Moves.meta(kit)["bottoms"]
	_foot = foot_for(kit)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_shadow = Node2D.new()
	_shadow.z_index = -1
	_shadow.draw.connect(_draw_shadow)
	add_child(_shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = sheet_for(kit)
	_sprite.region_enabled = true
	_sprite.centered = false
	_sprite.offset = -_foot
	_material = make_material(hue, saturation, kit, colors)
	_sprite.material = _material
	add_child(_sprite)
	play_tag("idle", 0)


## Tag hoạt ảnh của kit cho một trạng thái ("idle", "walk_f", "guard", "nhe", "te", "taunt"…).
func anim_tag(state: String) -> String:
	return String((Moves.kit(kit)["anims"] as Dictionary).get(state, "idle"))


func x_comp_tags() -> Array:
	var anims: Dictionary = Moves.kit(kit)["anims"]
	return [anims["te"], anims["vang"], anims["nam"], anims["dung"]]


## Phát một tag theo thời gian (vòng lặp hoặc giữ frame cuối).
func play_tag(tag: String, ticks: int, loop: bool = true, airborne_fix: bool = false, squash: float = 1.0) -> void:
	set_frame(tag_frame_at(tag, ticks, loop, kit), airborne_fix, 0.0, Vector2.ZERO, squash, tag in x_comp_tags())


## Phát ngược một tag (đi lùi của kit chỉ có một tag đi bộ).
func play_tag_reverse(tag: String, ticks: int) -> void:
	var frames: Array[int] = Moves.tag_frames(tag, kit)
	var total: int = Moves.tag_ticks(tag, kit)
	var t: int = ticks % total
	for i in range(frames.size() - 1, -1, -1):
		t -= Moves.frame_ticks(frames[i], kit)
		if t < 0:
			set_frame(frames[i])
			return
	set_frame(frames[0])


func set_frame(frame: int, airborne_fix: bool = false, rotation_rad: float = 0.0,
		offset: Vector2 = Vector2.ZERO, squash: float = 1.0, x_comp: bool = false) -> void:
	_set_pose(frame, airborne_fix)
	_pose_rotation = rotation_rad
	_pose_offset += offset
	_pose_squash = squash
	if x_comp:
		_pose_offset.x += float(Moves.kit(kit)["x_comp"]) * SCALE * body_scale


## Chọn frame nhảy theo vận tốc dọc (tag jump 21–30).
func set_jump(vertical_velocity: float) -> void:
	var frame: int = 25
	if vertical_velocity < -380.0:
		frame = 23
	elif vertical_velocity < -120.0:
		frame = 24
	elif vertical_velocity < 150.0:
		frame = 25
	elif vertical_velocity < 380.0:
		frame = 26
	else:
		frame = 27
	_set_pose(frame, true)


func _set_pose(frame: int, airborne_fix: bool) -> void:
	_pose_frame = frame
	_pose_rotation = 0.0
	_pose_squash = 1.0
	_pose_offset = Vector2.ZERO
	if airborne_fix:
		# Frame nhảy trong file art tự nâng gà lên; độ cao thật do vật lý lo nên hạ về chân.
		_pose_offset.y = float(int(_foot.y) - int(_bottoms[frame - 1])) * SCALE * body_scale


func flash(color: Color, strength: float = 1.0) -> void:
	_flash_color = color
	_flash = strength


func spawn_afterimage(color: Color, life: float = 0.25) -> void:
	if fx_parent == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = _sprite.texture
	ghost.region_enabled = true
	ghost.region_rect = _sprite.region_rect
	ghost.centered = false
	ghost.offset = -_foot
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.global_transform = _sprite.global_transform
	var material := make_material(hue, saturation, kit, colors)
	material.set_shader_parameter("flash_color", color)
	material.set_shader_parameter("flash", 0.7)
	ghost.material = material
	ghost.modulate.a = 0.55
	ghost.z_index = -1
	fx_parent.add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, life)
	tween.tween_callback(ghost.queue_free)


func _physics_process(_delta: float) -> void:
	if shield_ticks > 0:
		shield_ticks -= 1


func _process(delta: float) -> void:
	_time += delta
	var s: float = SCALE * body_scale
	_sprite.region_rect = frame_region(_pose_frame)
	_sprite.scale = Vector2(s * float(facing), s * _pose_squash)
	_sprite.rotation = _pose_rotation * float(facing)
	var jitter: float = 0.0
	if shake_ticks > 0:
		jitter = (3.0 if (Engine.get_physics_frames() % 2) == 0 else -3.0)
	_sprite.position = Vector2(_pose_offset.x * float(facing) + jitter, _pose_offset.y)

	_flash = maxf(0.0, _flash - delta * 6.0)
	_material.set_shader_parameter("flash", _flash)
	_material.set_shader_parameter("flash_color", _flash_color)

	_shadow.global_position = Vector2(global_position.x, ground_y)
	_shadow.queue_redraw()
	queue_redraw()


func _draw_shadow() -> void:
	var height: float = maxf(0.0, ground_y - global_position.y)
	var k: float = clampf(1.0 - height / 260.0, 0.35, 1.0)
	var w: float = 46.0 * body_scale * k
	var points := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		points.append(Vector2(cos(a) * w, sin(a) * 7.0 * k))
	_shadow.draw_colored_polygon(points, Color(0, 0, 0, 0.35 * k))


func _draw() -> void:
	if aura > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_time * 30.0)
		for bolt in range(4):
			var p := Vector2(rng.randf_range(-60, 60), rng.randf_range(-130, -10))
			var line := PackedVector2Array([p])
			for seg in range(4):
				p += Vector2(rng.randf_range(-18, 18), rng.randf_range(-22, 10))
				line.append(p)
			draw_polyline(line, Color(1.0, 0.95, 0.4, aura), 3.0)
			draw_polyline(line, Color(1, 1, 1, aura), 1.0)
		draw_circle(Vector2(0, -60), 70.0, Color(1.0, 0.8, 0.2, 0.12 * aura))
	if stars:
		for i in range(3):
			var a: float = _time * 5.0 + TAU * float(i) / 3.0
			var c := Vector2(cos(a) * 30.0, -128.0 + sin(a) * 8.0)
			_draw_star(c, 7.0, Color(1.0, 0.9, 0.3))
	if shield_ticks > 0:
		var center := Vector2(34.0 * float(facing), -62.0)
		var alpha: float = clampf(float(shield_ticks) / 6.0, 0.0, 1.0)
		var arc := PackedVector2Array()
		for i in range(13):
			var a: float = -1.1 + 2.2 * float(i) / 12.0
			arc.append(center + Vector2(cos(a) * 22.0 * float(facing), sin(a) * 60.0))
		draw_polyline(arc, Color(0.45, 0.75, 1.0, alpha), 9.0)
		draw_polyline(arc, Color(0.9, 0.97, 1.0, alpha), 3.0)


func _draw_star(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var a: float = -PI / 2.0 + PI * float(i) / 5.0
		var radius: float = r if i % 2 == 0 else r * 0.45
		points.append(c + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, color)
