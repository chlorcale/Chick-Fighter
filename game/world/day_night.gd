extends Node2D

## Ánh sáng ngày/đêm cho bản đồ khám phá (GDD 3.3: 5 buổi). Chỉ là trình diễn – không đổi gameplay.
## main.gd thêm node này làm con của World sau khi tạo World → ẩn theo World trong trận/đua xe (CanvasModulate chỉ
## có tác dụng khi visible trong cây). Không tô màu UI: các CanvasLayer (HUD, hội thoại…) là canvas riêng.
##   • CanvasModulate: màu nội suy mượt theo GameState.minutes (sáng trong, trưa sáng gắt, chiều vàng ấm,
##     chạng vạng cam-tím, đêm xanh lam).
##   • Đèn ấm (PointLight2D cộng sáng) chỉ hiện về tối: đèn lồng quanh người chơi + add_light() cho nhà/đèn đường.
## Khi giờ nhảy (làm việc 2 tiếng…), màu "chạy" qua các mốc trung gian trong ~1–2 giây thay vì nhảy cóc.
## Dùng: const DayNight := preload("res://game/world/day_night.gd"); var dn = DayNight.new(); dn.world = world;
##       world.add_child(dn); dn.add_light(Vector2(...), 90.0)

## Mốc màu theo phút trong ngày [phút, Color]. PLACEHOLDER: chỉnh theo mắt khi có bản đồ mới.
const KEYS: Array = [
	[0, Color(0.27, 0.31, 0.56)],
	[5 * 60, Color(0.30, 0.34, 0.58)],
	[6 * 60 + 30, Color(0.80, 0.76, 0.88)],
	[7 * 60, Color(0.93, 0.95, 0.96)],      # sáng sớm trong, hơi mát
	[9 * 60, Color(0.99, 0.99, 0.96)],
	[10 * 60, Color(1.0, 1.0, 1.0)],        # trưa sáng gắt
	[13 * 60, Color(1.0, 0.99, 0.95)],
	[15 * 60, Color(1.0, 0.93, 0.80)],      # chiều vàng ấm
	[17 * 60, Color(1.0, 0.84, 0.64)],
	[18 * 60, Color(0.97, 0.68, 0.52)],     # hoàng hôn cam
	[19 * 60, Color(0.70, 0.55, 0.76)],     # chạng vạng tím
	[20 * 60, Color(0.46, 0.47, 0.74)],
	[21 * 60, Color(0.35, 0.40, 0.67)],     # đêm xanh lam
	[23 * 60, Color(0.29, 0.34, 0.60)],
	[24 * 60, Color(0.27, 0.31, 0.56)],
]
## Tốc độ "chạy" của đồng hồ hiển thị (phút game mỗi giây thật) khi giờ thật nhảy tới.
const CATCH_UP_MIN: float = 90.0
const CATCH_UP_TIME: float = 1.4
const LIGHT_COLOR: Color = Color(1.0, 0.72, 0.38)

var world: Node
## Đèn lồng ấm quanh người chơi về đêm.
var player_lantern: bool = true

var _modulate: CanvasModulate
var _lights: Node2D
var _lantern: PointLight2D
var _shown: float = -1.0        # phút tuyệt đối đang hiển thị ((day − 1) × 1440 + minutes)
var _light_tex: Texture2D
var _pending: Array = []


func _ready() -> void:
	if world == null:
		world = get_parent()
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	_lights = Node2D.new()
	_lights.name = "Lights"
	add_child(_lights)
	_light_tex = _make_light_texture()
	_lantern = _make_light(Vector2.ZERO, 70.0, 0.9)
	for p in _pending:
		_make_light(p[0], p[1], p[2])
	_pending.clear()
	_snap()


## Thêm một vùng đèn ấm (nhà, đèn lồng, quán) – chỉ sáng về tối. radius: bán kính px (tọa độ thế giới).
## Gọi trước khi node vào cây cũng được (đèn được tạo trong _ready; khi đó trả về null).
func add_light(world_pos: Vector2, radius: float = 90.0, energy: float = 1.0) -> PointLight2D:
	if _lights == null:
		_pending.append([world_pos, radius, energy])
		return null
	return _make_light(world_pos, radius, energy)


## Màu ánh sáng đang hiển thị (để test/HUD đọc).
func current_tint() -> Color:
	return _modulate.color if _modulate != null else Color.WHITE


func _make_light(pos: Vector2, radius: float, energy: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = _light_tex
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # quầng sáng mịn (gốc cây mặc định NEAREST)
	light.texture_scale = radius / 64.0
	light.color = LIGHT_COLOR
	light.position = pos
	light.set_meta("base_energy", energy)
	light.energy = 0.0
	light.visible = false
	_lights.add_child(light)
	return light


func _make_light_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _target() -> float:
	return float((GameState.day - 1) * 1440 + GameState.minutes)


func _snap() -> void:
	_shown = _target()
	_apply()


func _process(delta: float) -> void:
	var target: float = _target()
	var diff: float = target - _shown
	if _shown < 0.0 or diff < 0.0 or diff > 1440.0 * 2.0:
		_shown = target          # tải save / lùi giờ → nhảy thẳng
	elif diff > 0.0:
		var speed: float = maxf(CATCH_UP_MIN, diff / CATCH_UP_TIME)
		_shown = minf(target, _shown + speed * delta)
	_apply()
	if _lantern != null and world != null and world.get("player") != null:
		_lantern.global_position = (world.get("player") as Node2D).global_position + Vector2(0, -10)
		_lantern.visible = player_lantern and _lantern.energy > 0.01


func _apply() -> void:
	var m: int = int(posmod(int(_shown), 1440))
	_modulate.color = tint_at(m)
	var night: float = night_factor(m)
	for light in _lights.get_children():
		var l := light as PointLight2D
		l.energy = night * float(l.get_meta("base_energy", 1.0))
		l.visible = l.energy > 0.01 and (l != _lantern or player_lantern)


## Màu CanvasModulate tại phút m trong ngày (nội suy smoothstep giữa các mốc KEYS).
static func tint_at(m: int) -> Color:
	m = posmod(m, 1440)
	for i in range(KEYS.size() - 1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if m >= int(a[0]) and m <= int(b[0]):
			var t: float = float(m - int(a[0])) / maxf(1.0, float(int(b[0]) - int(a[0])))
			return (a[1] as Color).lerp(b[1], smoothstep(0.0, 1.0, t))
	return KEYS[0][1]


## 0 = ban ngày, 1 = đêm sâu (theo độ sáng của màu tint) – dùng cho đèn và âm thanh.
static func night_factor(m: int) -> float:
	var c: Color = tint_at(m)
	var lum: float = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	return clampf((0.82 - lum) / (0.82 - 0.36), 0.0, 1.0)


## Gợi ý trộn âm thanh nền theo giờ cho world.gd (_update_audio): nhân "birds" với birds_mult, đặt "crickets" tối
## thiểu crickets_min; "village" nhân village_mult. Ví dụ: Audio.ambience_layer(&"birds", base * mix["birds_mult"]).
static func ambience_mix(m: int = -1) -> Dictionary:
	if m < 0:
		m = GameState.minutes
	var night: float = night_factor(m)
	return {
		"birds_mult": lerpf(1.0, 0.1, night),
		"crickets_min": lerpf(0.0, 0.6, night),
		"village_mult": lerpf(1.0, 0.45, night),
		"night": night,
	}
