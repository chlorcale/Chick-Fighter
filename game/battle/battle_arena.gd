class_name BattleArena
extends Node2D

## Sân đấu "Sới gà Ao Làng" nhìn ngang (GDD 8.2): rộng 1000 px, nền phẳng, tường hai đầu.
## Chỉ là trình diễn: không đọc/ghi gì của mô phỏng, chỉ dùng RNG + đồng hồ riêng cho hình ảnh.
##
## Lớp (sau → trước) cuộn thị sai theo tâm camera: trời chiều → sông + bờ xa → đình, cây đa, dừa,
## quán lá → dây cờ, lồng đèn, băng rôn → bậc ghế + khán giả → nền sới → hàng rào tre + đồ vật mép sân
## → [gà] → tiền cảnh mờ ở mép dưới. Ảnh tĩnh nướng sẵn bằng tools/art/build_arena.py (game/art/arena/),
## phần động (tán cây, cờ, lồng đèn, khói, ghe, mây, khán giả) cắt từ hai atlas.
##
## Khán giả: mỗi người đứng cố định tại một "chỗ" (Node2D không bao giờ di chuyển); chỉ sprite con
## được nhấc lên theo trục dọc (nhún nhẹ khi đứng xem, nhảy parabol ngắn khi reo hò) và luôn trở về
## đúng vị trí nghỉ. Không xoay, không trôi ngang.

const STAGE_LEFT: float = 0.0
const STAGE_RIGHT: float = 1000.0
const PX: float = 2.0
const ART: String = "res://game/art/arena/"

## Biến thể: &"chieu" (chiều tà, mặc định) hoặc &"toi" (chập tối, lồng đèn sáng – trận cuối) – sới Ao Làng;
## &"lien_tinh" (sới tỉnh: khán đài mái tôn, băng rôn) và &"olympic" (nhà thi đấu trong nhà, đèn pha, huy hiệu gà
## vàng) – ảnh từ tools/art/build_arena_venues.py (arena_<biến thể>_<lớp>.png, thiếu lớp nào thì dùng lớp Ao Làng).
## Biên sân mô phỏng KHÔNG đổi (GDD: sàn Olympic 1.400 px – OPEN).
const VARIANTS: Array[StringName] = [&"chieu", &"toi", &"lien_tinh", &"olympic"]
const VENUES: Array[StringName] = [&"lien_tinh", &"olympic"]
const OLY_TOP: Color = Color8(10, 12, 26)
const OLY_LOW: Color = Color8(26, 26, 44)

## Độ lệch dọc tối đa của một khán giả so với chỗ đứng (px thế giới).
const HOP_MAX: float = 8.0
const BOB_IDLE: float = 1.0

# Lớp: [ảnh, gốc thế giới (góc trên-trái), hệ số thị sai ngang h, hệ số thị sai dọc vy, z].
# Khớp L_* trong tools/art/build_arena.py. h = 1 đi cùng gà; h < 1 ở xa; h > 1 ở gần ống kính.
const LAYERS: Dictionary = {
	&"sky": ["arena_sky.png", Vector2(-400, -1100), 0.05, 0.45, -40],
	&"far": ["arena_far.png", Vector2(-400, -340), 0.25, 0.32, -36],
	&"mid": ["arena_mid.png", Vector2(-400, -520), 0.55, 0.18, -32],
	&"bunt": ["arena_bunt.png", Vector2(-400, -440), 0.75, 0.10, -28],
	&"stands": ["arena_stands.png", Vector2(-400, -240), 0.95, 0.0, -24],
	&"floor": ["arena_floor.png", Vector2(-400, -80), 1.0, 0.0, -18],
	&"fence": ["arena_fence.png", Vector2(-400, -170), 1.0, 0.0, -16],
	&"front": ["arena_front.png", Vector2(-400, 20), 1.12, 0.0, 52],
}
## Các lớp phải phủ kín bề ngang khung nhìn (kiểm tra trong smoke test).
const FULL_WIDTH_LAYERS: Array[StringName] = [&"sky", &"far", &"mid", &"stands", &"floor", &"fence"]
const TEX_WIDTH: float = 900.0 * PX

const SKY_TOP: Color = Color8(86, 132, 196)
const SKY_LOW: Color = Color8(252, 226, 176)
const TOI_TOP: Color = Color8(44, 46, 96)
const TOI_LOW: Color = Color8(246, 170, 112)
const EARTH: Color = Color8(150, 118, 82)

# Atlas đồ vật động (arena_props.png): khoá → [y, rộng ô, cao ô, số khung, thứ tự khung 96 bước × 80 ms].
# Sinh bởi build_arena.py (dòng "PROPS = {").
const PROPS: Dictionary = {
	"da": [0, 99, 75, 2, "000111111111111111100000000000000001111111111111111000000000000000011111111111111110000000000000"],
	"dua_a": [76, 120, 55, 4, "001111112222223333330000001111112222223333330000001111112222223333330000001111112222223333330000"],
	"dua_b": [132, 118, 50, 4, "000011111122222233333300000011111122222233333300000011111122222233333300000011111122222233333300"],
	"dua_c": [183, 107, 47, 4, "000001111112222223333330000001111112222223333330000001111112222223333330000001111112222223333330"],
	"chuoi": [231, 65, 52, 4, "001111112222223333330000001111112222223333330000001111112222223333330000001111112222223333330000"],
	"day_co_a": [284, 342, 20, 4, "001111222233330000111122223333000011112222333300001111222233330000111122223333000011112222333300"],
	"day_co_b": [305, 342, 20, 4, "000011112222333300001111222233330000111122223333000011112222333300001111222233330000111122223333"],
	"den_long_a": [326, 14, 18, 3, "001111111100000000222222220000000011111111000000002222222200000000111111110000000022222222000000"],
	"den_long_b": [345, 14, 18, 3, "000011111111222222221111111100000000111111112222222211111111000000001111111122222222111111110000"],
	"co_to_quoc": [364, 33, 27, 4, "000111222333000111222333000111222333000111222333000111222333000111222333000111222333000111222333"],
	"co_hoi": [392, 37, 27, 4, "000111222333000111222333000111222333000111222333000111222333000111222333000111222333000111222333"],
	"co_dt": [420, 27, 22, 4, "000111222333000111222333000111222333000111222333000111222333000111222333000111222333000111222333"],
	"khoi_nhang": [443, 20, 20, 8, "000111222333444555666777000111222333444555666777000111222333444555666777000111222333444555666777"],
	"khoi_bep": [464, 20, 42, 8, "000111222333444555666777000111222333444555666777000111222333444555666777000111222333444555666777"],
	"ghe_a": [507, 34, 14, 1, ""],
	"ghe_b": [522, 28, 14, 1, ""],
	"may_a": [537, 72, 22, 1, ""],
	"may_b": [560, 54, 18, 1, ""],
	"may_c": [579, 90, 26, 1, ""],
	"may_toi_a": [606, 72, 22, 1, ""],
	"may_toi_b": [629, 54, 18, 1, ""],
	"may_toi_c": [648, 90, 26, 1, ""],
	"banner": [675, 76, 13, 1, ""],
	"glow": [689, 56, 56, 1, ""],
	"mote": [746, 2, 2, 1, ""],
}

# Phần tử động: [lớp, khoá atlas, x, y thế giới góc trên-trái, lật ngang, kiểu]. Sinh bởi build_arena.py ("DYN = [").
const DYN: Array = [
	[&"sky", "may_a", -200, -760, false, &"cloud"],
	[&"sky", "may_b", 420, -640, false, &"cloud"],
	[&"sky", "may_c", 900, -840, false, &"cloud"],
	[&"far", "ghe_a", 120, -238, false, &"boat"],
	[&"far", "ghe_b", 760, -232, true, &"boat"],
	[&"mid", "dua_a", -257, -427, false, &"anim"],
	[&"mid", "dua_c", 236, -419, false, &"anim"],
	[&"mid", "dua_b", 857, -446, false, &"anim"],
	[&"mid", "dua_a", 982, -415, true, &"anim"],
	[&"mid", "da", -29, -440, false, &"anim"],
	[&"mid", "chuoi", 150, -262, false, &"anim"],
	[&"mid", "chuoi", 800, -258, true, &"anim"],
	[&"mid", "co_to_quoc", 893, -380, false, &"anim"],
	[&"mid", "khoi_nhang", 548, -262, false, &"anim"],
	[&"mid", "khoi_bep", 1160, -386, false, &"anim"],
	[&"bunt", "day_co_a", -380, -366, false, &"anim"],
	[&"bunt", "day_co_b", 304, -366, false, &"anim"],
	[&"bunt", "day_co_a", 988, -366, false, &"anim"],
	[&"bunt", "co_dt", 306, -400, false, &"anim"],
	[&"bunt", "co_hoi", -378, -404, false, &"anim"],
	[&"bunt", "co_dt", 990, -400, true, &"anim"],
	[&"bunt", "banner", 150, -300, false, &"banner"],
	[&"bunt", "den_long_a", -280, -320, false, &"lantern"],
	[&"bunt", "den_long_b", -166, -311, false, &"lantern"],
	[&"bunt", "den_long_a", -52, -308, false, &"lantern"],
	[&"bunt", "den_long_b", 62, -311, false, &"lantern"],
	[&"bunt", "den_long_a", 404, -320, false, &"lantern"],
	[&"bunt", "den_long_b", 518, -311, false, &"lantern"],
	[&"bunt", "den_long_a", 632, -308, false, &"lantern"],
	[&"bunt", "den_long_b", 746, -311, false, &"lantern"],
	[&"bunt", "den_long_a", 860, -320, false, &"lantern"],
	[&"bunt", "den_long_b", 1088, -320, false, &"lantern"],
	[&"bunt", "den_long_a", 1202, -311, false, &"lantern"],
]

# Atlas khán giả (arena_crowd.png): cột = NPC, hàng = (độ mờ hàng 0..2) × (đứng, giơ tay). Ô 36×48, chân chạm đáy ô.
const CROWD_CELL: Vector2 = Vector2(36, 48)
const CROWD_NPCS: Array[String] = ["crowd_1", "crowd_2", "crowd_3", "crowd_4", "crowd_5", "lady", "lottery", "shop",
	"temple_man", "mc", "chu_tu", "teo"]
const CROWD_HEIGHTS: Array[int] = [41, 41, 45, 41, 43, 45, 45, 45, 43, 42, 41, 40]
const NPC_MC: int = 9
const NPC_CHU_TU: int = 10
const NPC_TEO: int = 11
## Thứ tự khán giả "thường" lặp theo hàng (đủ 9 kiểu trong mỗi đoạn 9 người → không bị dồn cụm).
const CROWD_SEQ: Array[int] = [0, 3, 6, 1, 8, 4, 2, 7, 5]

var excitement: float = 0.0
## Báo công an: 0..1 – khán giả nhấp nhổm, ngó nghiêng (nhún nhanh hơn, nhảy lẻ tẻ). Vẫn chỉ dịch dọc ≤ HOP_MAX.
var nervous: float = 0.0
## Công an ập vào (scatter()): mọi người bỏ chạy ra hai bên – NGOẠI LỆ duy nhất cho phép dịch ngang.
var scattering: bool = false
var _scatter_t0: float = 0.0
## Đặt trước khi add_child (hoặc qua configure()).
var variant: StringName = &"chieu"
var opponent_owner: String = ""

var _layers: Dictionary = {} # StringName → {node, h, vy}
var _layer_list: Array[Dictionary] = []
var _crowd: Array[CrowdMember] = []
var _anims: Array[PropAnim] = []
var _drifters: Array[Drifter] = []
var _glows: Array[Sprite2D] = []
var _rays: Sprite2D
var _dust: DustMotes
var _time: float = 0.0
## RNG trình diễn riêng (không đụng RNG mô phỏng).
var _rng := RandomNumberGenerator.new()
var _props_tex: Texture2D
var _crowd_tex: Texture2D


## Một khán giả: `spot` cố định ở chỗ đứng; `sprite` chỉ dịch dọc từ `rest`.
class CrowdMember:
	var spot: Node2D
	var sprite: Sprite2D
	var rest: Vector2
	var npc: int = 0
	var row: int = 0
	var phase: float = 0.0
	var rate: float = 2.0
	var hop_t0: float = -100.0
	var hop_len: float = 0.45
	var hop_h: float = 0.0
	var arms_until: float = -100.0
	var arms_on_hop: bool = false
	var pose: int = 0


## Sprite động cắt khung từ atlas theo chuỗi thứ tự khung của bản đồ.
class PropAnim:
	var sprite: Sprite2D
	var key: String
	var y: int
	var cw: int
	var ch: int
	var order: String
	var speed: float = 1.0
	var offset: int = 0
	var frame: int = -1


## Mây trôi / ghe xuôi dòng: chạy ngang có quấn vòng, ghe nhấp nhô 1 px.
class Drifter:
	var sprite: Sprite2D
	var base: Vector2
	var speed: float
	var span_min: float
	var span_max: float
	var bob: bool
	var phase: float


## Bụi lấp lánh trong nắng (hoặc đom đóm buổi tối) – vẽ bằng vài hình vuông 2×2 px.
class DustMotes:
	extends Node2D
	var time: float = 0.0
	var evening: bool = false
	var seeds: PackedVector4Array = PackedVector4Array()

	func _draw() -> void:
		for s in seeds:
			var t: float = time * s.w + s.z
			var x: float = s.x + sin(t * 0.37) * 14.0
			var y: float = s.y - fposmod(time * (3.0 + s.w * 4.0) + s.z * 20.0, 150.0)
			var a: float = 0.25 + 0.35 * (0.5 + 0.5 * sin(t * 1.7))
			var c: Color = Color(0.85, 1.0, 0.45, a + 0.2) if evening else Color(1.0, 0.95, 0.8, a)
			draw_rect(Rect2(roundf(x), roundf(y), 2.0, 2.0), c)


## Đọc cấu hình trận (chỉ phần trình diễn). Gọi trước khi add_child.
## config["arena_variant"] nếu có; nếu không, đối thủ hạng cao nhất (tier ≥ 3, trận cuối) → buổi tối.
func configure(config: Dictionary) -> void:
	var opponent: Dictionary = config.get("opponent", {})
	opponent_owner = String(opponent.get("owner", ""))
	var wanted: StringName = StringName(config.get("arena_variant", ""))
	var league: StringName = StringName(opponent.get("league", config.get("tournament", "")))
	if wanted in VARIANTS:
		variant = wanted
	elif league in VENUES:
		variant = league
	elif int(opponent.get("tier", 0)) >= 3:
		variant = &"toi"
	else:
		variant = &"chieu"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = 2026
	if not variant in VARIANTS:
		variant = &"chieu"
	var evening: bool = variant == &"toi"
	_props_tex = load(ART + "arena_props.png")
	_crowd_tex = load(ART + "arena_crowd.png")
	for key in LAYERS.keys():
		_make_layer(key)
	_build_backstops(evening)
	_build_dynamic(evening)
	_build_rays(evening)
	_build_crowd()
	_build_dust(evening)
	_apply_variant_tints(evening)
	_build_venue()
	_build_walls()
	follow_camera(Vector2(500, -150))
	_update_crowd(0.0)


func _make_layer(key: StringName) -> Node2D:
	var def: Array = LAYERS[key]
	var holder := Node2D.new()
	holder.name = "Layer_%s" % key
	holder.z_index = int(def[4])
	add_child(holder)
	var sprite := Sprite2D.new()
	var file: String = String(def[0])
	if key == &"sky" and variant == &"toi":
		file = "arena_sky_toi.png"
	if variant in VENUES:
		var venue_file: String = "arena_%s_%s.png" % [variant, key]
		if ResourceLoader.exists(ART + venue_file):
			file = venue_file
	sprite.texture = load(ART + file)
	sprite.centered = false
	sprite.scale = Vector2(PX, PX)
	sprite.position = def[1]
	sprite.name = "Art"
	holder.add_child(sprite)
	var entry: Dictionary = {"node": holder, "h": float(def[2]), "vy": float(def[3]), "key": key}
	_layers[key] = entry
	_layer_list.append(entry)
	return holder


## Mảng màu phủ phần trời / đất ngoài ảnh để không bao giờ lộ khoảng trống khi camera mở rộng hoặc rung.
func _build_backstops(evening: bool) -> void:
	var sky: Node2D = _layers[&"sky"]["node"]
	var top := ColorRect.new()
	top.color = OLY_TOP if variant == &"olympic" else (TOI_TOP if evening else SKY_TOP)
	top.position = Vector2(-3000, -6000)
	top.size = Vector2(7000, 4900 + 2)
	top.z_index = -1 # dưới ảnh của lớp
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.add_child(top)
	var low := ColorRect.new()
	low.color = OLY_LOW if variant == &"olympic" else (TOI_LOW if evening else SKY_LOW)
	low.position = Vector2(-3000, -62)
	low.size = Vector2(7000, 3062)
	low.z_index = -1 # dưới ảnh của lớp
	low.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.add_child(low)
	var floor_node: Node2D = _layers[&"floor"]["node"]
	var earth := ColorRect.new()
	earth.color = EARTH
	earth.position = Vector2(-3000, 40)
	earth.size = Vector2(7000, 3000)
	earth.z_index = -1 # dưới ảnh của lớp
	earth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_node.add_child(earth)


func _build_dynamic(evening: bool) -> void:
	var index: int = 0
	for item in DYN:
		var layer: StringName = item[0]
		var key: String = item[1]
		var kind: StringName = item[5]
		if kind == &"cloud" and evening:
			key = key.replace("may_", "may_toi_")
		# Sân tỉnh / Olympic không có cây dừa, đình, lồng đèn làng: chỉ giữ mây trôi (Liên tỉnh dùng trời Ao Làng).
		if variant in VENUES and not (kind == &"cloud" and variant == &"lien_tinh"):
			index += 1
			continue
		var def: Array = PROPS[key]
		var sprite := Sprite2D.new()
		sprite.texture = _props_tex
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, float(def[0]), float(def[1]), float(def[2]))
		sprite.scale = Vector2(PX, PX)
		sprite.flip_h = bool(item[4])
		sprite.position = Vector2(float(item[2]), float(item[3]))
		var holder: Node2D = _layers[layer]["node"]
		if kind == &"lantern" and evening:
			var glow := _make_glow(Vector2(float(item[2]) + 14.0, float(item[3]) + 20.0), 1.4)
			holder.add_child(glow)
			_glows.append(glow)
		holder.add_child(sprite)
		match kind:
			&"cloud", &"boat":
				var d := Drifter.new()
				d.sprite = sprite
				d.base = sprite.position
				d.bob = kind == &"boat"
				d.speed = (5.0 + 2.0 * float(index % 3)) if kind == &"cloud" else (9.0 if not sprite.flip_h else -6.0)
				d.span_min = -500.0
				d.span_max = 1500.0
				d.phase = float(index) * 1.7
				_drifters.append(d)
			_:
				if int(def[3]) > 1:
					var a := PropAnim.new()
					a.sprite = sprite
					a.key = key
					a.y = int(def[0])
					a.cw = int(def[1])
					a.ch = int(def[2])
					a.order = String(def[4])
					a.speed = 0.8 + 0.1 * float(index % 4)
					a.offset = (index * 23) % 96
					_anims.append(a)
		index += 1


func _make_glow(center: Vector2, size: float) -> Sprite2D:
	var def: Array = PROPS["glow"]
	var glow := Sprite2D.new()
	glow.texture = _props_tex
	glow.region_enabled = true
	glow.region_rect = Rect2(0, float(def[0]), float(def[1]), float(def[2]))
	glow.centered = true
	glow.position = center
	glow.scale = Vector2(PX * size, PX * size)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	return glow


func _build_rays(evening: bool) -> void:
	var mid: Node2D = _layers[&"mid"]["node"]
	_rays = Sprite2D.new()
	_rays.name = "Rays"
	_rays.texture = load(ART + "arena_rays.png")
	_rays.centered = false
	_rays.scale = Vector2(PX, PX)
	_rays.position = LAYERS[&"mid"][1]
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_rays.material = mat
	_rays.visible = not evening and not variant in VENUES
	_rays.z_index = 1
	mid.add_child(_rays)
	if evening:
		# Vũng sáng ấm trên sới (đèn treo) để gà tối màu vẫn nổi trên nền.
		var pool := _make_glow(Vector2(500, -20), 1.0)
		pool.scale = Vector2(PX * 9.0, PX * 1.6)
		pool.modulate = Color(1, 1, 1, 0.55)
		pool.z_index = 1
		_layers[&"floor"]["node"].add_child(pool)


## Phần riêng của sân tỉnh / Olympic (chỉ hình ảnh): Olympic có cột sáng đèn pha (cộng sáng), vũng sáng trên sàn,
## đèn flash máy ảnh lấp lánh trên khán đài tầng trên; khán đài tầng dưới tối hơn để gà nổi bật.
func _build_venue() -> void:
	if variant != &"olympic":
		return
	var sky: Node2D = _layers[&"sky"]["node"]
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for x in [-280.0, 20.0, 320.0, 620.0, 920.0, 1220.0]:
		var pts := PackedVector2Array([Vector2(x, -680), Vector2(x + 110.0, -680), Vector2(x + 340.0, 0), Vector2(x - 180.0, 0)])
		var beam := Polygon2D.new()
		beam.polygon = pts
		beam.color = Color(0.6, 0.65, 0.8, 0.07)
		beam.material = mat
		beam.z_index = 3
		sky.add_child(beam)
	var pool := _make_glow(Vector2(500, -20), 1.0)
	pool.scale = Vector2(PX * 10.0, PX * 1.8)
	pool.modulate = Color(0.8, 0.85, 1.0, 0.5)
	pool.z_index = 1
	_layers[&"floor"]["node"].add_child(pool)
	_layers[&"stands"]["node"].modulate = Color(0.78, 0.78, 0.9)
	_layers[&"far"]["node"].add_child(_make_flashes())


func _make_flashes() -> Node2D:
	var f := FlashBulbs.new()
	f.name = "Flashes"
	f.z_index = 2
	for i in range(28):
		f.seeds.append(Vector3(_rng.randf_range(-400.0, 1400.0), _rng.randf_range(-330.0, -60.0), _rng.randf() * 10.0))
	return f


## Đèn flash máy ảnh trên khán đài Olympic: chớp ngẫu nhiên tất định theo đồng hồ hình ảnh.
class FlashBulbs:
	extends Node2D
	var time: float = 0.0
	var seeds: PackedVector3Array = PackedVector3Array()

	func _process(delta: float) -> void:
		time += delta
		queue_redraw()

	func _draw() -> void:
		for s in seeds:
			var phase: float = fposmod(time * 0.7 + s.z, 3.3)
			if phase < 0.09:
				var a: float = 1.0 - phase / 0.09
				draw_rect(Rect2(s.x - 2.0, s.y - 2.0, 4.0, 4.0), Color(1, 1, 1, a))
				draw_rect(Rect2(s.x - 5.0, s.y - 0.5, 10.0, 1.0), Color(1, 1, 0.9, a * 0.7))


func _apply_variant_tints(evening: bool) -> void:
	if not evening:
		return
	var tints: Dictionary = {
		&"far": Color(0.55, 0.55, 0.74), &"mid": Color(0.62, 0.58, 0.74), &"bunt": Color(0.74, 0.66, 0.78),
		&"stands": Color(0.8, 0.74, 0.82), &"floor": Color(0.94, 0.88, 0.86), &"fence": Color(0.88, 0.82, 0.84),
	}
	for key in tints.keys():
		var node: Node2D = _layers[key]["node"]
		node.modulate = tints[key]
	# Lồng đèn tự sáng: không nhuộm tối theo lớp.
	for glow in _glows:
		glow.modulate = Color(1.6, 1.4, 1.2, 1.0)


func _build_dust(evening: bool) -> void:
	_dust = DustMotes.new()
	_dust.name = "Dust"
	_dust.evening = evening
	_dust.z_index = 2
	for i in range(26):
		var x: float = _rng.randf_range(-100.0, 1100.0)
		var y: float = _rng.randf_range(-130.0, -40.0)
		_dust.seeds.append(Vector4(x, y, _rng.randf() * TAU, _rng.randf_range(0.4, 1.2)))
	_layers[&"stands"]["node"].add_child(_dust)


# ---------------------------------------------------------------- khán giả

## Bố cục khán giả (tất định, khớp views.py trong ghi chú dựng ảnh): 3 hàng sau hàng rào, hàng sau đứng
## bậc cao hơn, cong theo vòng sới. Trả về danh sách [npc, x, y chân, hàng, npc trẻ em trên vai hoặc -1].
static func crowd_layout(owner: String) -> Array:
	var out: Array = []
	for r in [2, 1, 0]:
		var spacing: float = 46.0 - 2.0 * float(r)
		var x: float = -300.0 + float(r) * 17.0
		var i: int = 0
		while x < 1300.0:
			var px: float = x + float((i * 37 + r * 11) % 9) - 4.0
			var q: float = pow((px - 500.0) / 610.0, 2.0)
			var y: float = roundf(-64.0 - 26.0 * float(r) + 34.0 * q * 0.8)
			if not (r > 0 and (i * 13 + r * 5) % 11 == 0):
				var npc: int = CROWD_SEQ[(i + r * 4) % 9]
				var kid: int = (i + 2) % 9 if (r == 1 and i % 7 == 3) else -1
				out.append([npc, roundf(px), y, r, kid])
			x += spacing
			i += 1
	# Nhân vật quen ở hàng đầu: MC (đứng trên thùng, cầm loa), Chú Tư, Tèo – trừ khi là chủ gà đối thủ.
	var mc: Array = _nearest_front(out, 150.0)
	mc[0] = NPC_MC
	mc[2] = float(mc[2]) - 14.0
	if owner != "Chú Tư":
		_nearest_front(out, 300.0)[0] = NPC_CHU_TU
	if owner != "Tèo":
		_nearest_front(out, 720.0)[0] = NPC_TEO
	return out


static func _nearest_front(list: Array, x: float) -> Array:
	var best: Array = []
	for m in list:
		if int(m[3]) == 0 and (best.is_empty() or absf(float(m[1]) - x) < absf(float(best[1]) - x)):
			best = m
	return best


func _build_crowd() -> void:
	var holder: Node2D = _layers[&"stands"]["node"]
	var crowd_root := Node2D.new()
	crowd_root.name = "Crowd"
	crowd_root.z_index = 1
	holder.add_child(crowd_root)
	for entry in crowd_layout(opponent_owner):
		var m := CrowdMember.new()
		m.npc = int(entry[0])
		m.row = int(entry[3])
		m.spot = Node2D.new()
		m.spot.position = Vector2(float(entry[1]), float(entry[2]))
		crowd_root.add_child(m.spot)
		m.sprite = Sprite2D.new()
		m.sprite.texture = _crowd_tex
		m.sprite.centered = false
		m.sprite.region_enabled = true
		m.sprite.scale = Vector2(PX, PX)
		m.rest = Vector2(-CROWD_CELL.x, -CROWD_CELL.y * PX)
		m.sprite.position = m.rest
		m.spot.add_child(m.sprite)
		var kid: int = int(entry[4])
		if kid >= 0:
			# Trẻ con ngồi trên vai: nửa trên sprite, vẽ sau đầu người lớn, nhún theo người lớn.
			var k := Sprite2D.new()
			k.texture = _crowd_tex
			k.centered = false
			k.region_enabled = true
			var kh: int = CROWD_HEIGHTS[kid]
			k.region_rect = Rect2(float(kid) * CROWD_CELL.x, float(m.row * 2) * CROWD_CELL.y + CROWD_CELL.y - float(kh), CROWD_CELL.x, 22.0)
			k.position = Vector2(0, CROWD_CELL.y - float(CROWD_HEIGHTS[m.npc]) - 15.0)
			k.show_behind_parent = true
			m.sprite.add_child(k)
		m.phase = _rng.randf() * TAU
		m.rate = _rng.randf_range(1.6, 2.6)
		m.arms_on_hop = _rng.randf() < 0.65
		_set_pose(m, 0)
		_crowd.append(m)


func _set_pose(m: CrowdMember, pose: int) -> void:
	if pose == m.pose and m.sprite.region_rect.size.x > 0.0:
		return
	m.pose = pose
	m.sprite.region_rect = Rect2(float(m.npc) * CROWD_CELL.x, float(m.row * 2 + pose) * CROWD_CELL.y, CROWD_CELL.x, CROWD_CELL.y)


## Danh sách khán giả cho kiểm thử/chụp hình: sprite + vị trí nghỉ (toạ độ cục bộ của chỗ đứng).
func crowd_members() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _crowd:
		out.append({"sprite": m.sprite, "spot": m.spot, "rest": m.rest, "row": m.row, "npc": m.npc})
	return out


## Công an tới: khán giả chạy tán loạn (từ giữa ra hai bên, vừa chạy vừa nhảy, giơ tay).
func scatter() -> void:
	scattering = true
	_scatter_t0 = _time
	excitement = 1.0


func cheer(amount: float) -> void:
	excitement = minf(1.0, excitement + amount)


## Khán giả nhảy cẫng (combo dài, đánh ngã, siêu chiêu, hết hiệp): một đợt sóng lan từ giữa ra hai bên.
## Mỗi người một cú nhảy parabol ≤ HOP_MAX rồi về đúng chỗ; cú nhảy đang dở thì xếp cú mới ngay sau đó.
func jump_burst() -> void:
	excitement = 1.0
	for m in _crowd:
		var delay: float = absf(m.spot.position.x - 500.0) / 1000.0 * 0.45 + _rng.randf() * 0.08
		var start: float = maxf(_time + delay, m.hop_t0 + m.hop_len)
		_schedule_hop(m, start, _rng.randf_range(6.0, HOP_MAX), _rng.randf_range(0.42, 0.5))
		if m.arms_on_hop:
			m.arms_until = maxf(m.arms_until, start + m.hop_len + 0.6)


func _schedule_hop(m: CrowdMember, start: float, height: float, length: float) -> void:
	m.hop_t0 = start
	m.hop_len = length
	m.hop_h = minf(height, HOP_MAX)


## Gọi mỗi khung hình (từ director) với tâm camera để tạo thị sai. Chỉ dịch các lớp, không đụng khán giả.
func follow_camera(camera_center: Vector2) -> void:
	for layer in _layer_list:
		var node: Node2D = layer["node"]
		node.position = Vector2((camera_center.x - 500.0) * (1.0 - float(layer["h"])), (camera_center.y + 150.0) * float(layer["vy"]))


func _process(delta: float) -> void:
	_time += delta
	excitement = maxf(0.0, excitement - delta * 0.35)
	_update_crowd(delta)
	_update_props()
	if _dust != null:
		_dust.time = _time
		_dust.queue_redraw()


func _update_crowd(delta: float) -> void:
	if scattering:
		for m in _crowd:
			var dir: float = -1.0 if m.spot.position.x < 500.0 else 1.0
			var delay: float = fposmod(m.phase, 1.0) * 0.4
			var run: float = maxf(0.0, _time - _scatter_t0 - delay)
			var hop: float = absf(sin(run * 14.0 + m.phase)) * HOP_MAX
			m.sprite.position = Vector2(m.rest.x + dir * run * (220.0 + 60.0 * m.rate), m.rest.y - roundf(hop))
			_set_pose(m, 1)
		return
	for m in _crowd:
		# Pha tích luỹ (không nhân thời gian tuyệt đối với tần số thay đổi) → tốc độ nhún luôn mượt.
		m.phase = fposmod(m.phase + delta * m.rate * (1.0 + 0.8 * excitement + 2.0 * nervous), TAU)
		var bob: float = (0.5 - 0.5 * cos(m.phase)) * (BOB_IDLE + excitement + 2.0 * nervous)
		var hop: float = 0.0
		var u: float = (_time - m.hop_t0) / m.hop_len
		if u >= 0.0 and u < 1.0:
			hop = m.hop_h * 4.0 * u * (1.0 - u)
			bob = 0.0
		elif u >= 1.0 and (excitement > 0.35 or nervous > 0.3) and _rng.randf() < delta * (excitement * 0.8 + nervous * 1.2):
			# Đang hào hứng: thỉnh thoảng nhảy nhỏ lẻ tẻ.
			_schedule_hop(m, _time + _rng.randf() * 0.2, _rng.randf_range(3.0, 6.0), 0.36)
			if m.arms_on_hop:
				m.arms_until = maxf(m.arms_until, m.hop_t0 + 0.6)
		var lift: float = clampf(roundf(bob + hop), 0.0, HOP_MAX)
		m.sprite.position = Vector2(m.rest.x, m.rest.y - lift)
		_set_pose(m, 1 if _time < m.arms_until else 0)


func _update_props() -> void:
	var step: int = int(_time / 0.08)
	for a in _anims:
		var n: int = a.order.length()
		var idx: int = (int(float(step) * a.speed) + a.offset) % n
		var f: int = a.order.unicode_at(idx) - 48
		if f != a.frame:
			a.frame = f
			a.sprite.region_rect = Rect2(float(f * a.cw), float(a.y), float(a.cw), float(a.ch))
	for d in _drifters:
		var span: float = d.span_max - d.span_min
		var x: float = d.span_min + fposmod(d.base.x - d.span_min + _time * d.speed, span)
		var y: float = d.base.y
		if d.bob:
			y += roundf(sin(_time * 1.3 + d.phase)) * PX * 0.5
		d.sprite.position = Vector2(roundf(x), y)
	if _rays != null and _rays.visible:
		_rays.modulate = Color(1, 1, 1, 0.75 + 0.25 * sin(_time * 0.35))
	for i in range(_glows.size()):
		var g: Sprite2D = _glows[i]
		g.modulate.a = 0.75 + 0.2 * sin(_time * 2.3 + float(i) * 1.9)


## Kiểm tra phủ khung nhìn: trả về tên các lớp có ảnh KHÔNG phủ kín bề ngang khung nhìn `view`
## (hình chữ nhật thế giới của camera) với tâm camera `camera_center` dùng cho thị sai.
func uncovered_layers(camera_center: Vector2, view: Rect2) -> Array[StringName]:
	var missing: Array[StringName] = []
	for key in FULL_WIDTH_LAYERS:
		var def: Array = LAYERS[key]
		var h: float = float(def[2])
		var origin: Vector2 = def[1]
		var shift: float = (camera_center.x - 500.0) * (1.0 - h)
		var left: float = origin.x + shift
		var right: float = left + TEX_WIDTH
		if view.position.x < left or view.end.x > right:
			missing.append(key)
	# Trời + đất có mảng màu phủ vô hạn theo chiều dọc: chỉ cần chúng tồn tại.
	if _layers[&"sky"]["node"].get_child_count() < 3 or _layers[&"floor"]["node"].get_child_count() < 2:
		missing.append(&"backstop")
	return missing


func _build_walls() -> void:
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(3000, 200)
	floor_shape.shape = rect
	floor_shape.position = Vector2(500, 100)
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	for x in [STAGE_LEFT - 50.0, STAGE_RIGHT + 50.0]:
		var wall := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var wall_rect := RectangleShape2D.new()
		wall_rect.size = Vector2(100, 2000)
		shape.shape = wall_rect
		shape.position = Vector2(x, -900)
		wall.add_child(shape)
		add_child(wall)
