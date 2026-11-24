extends Node2D

## NHÀ & CHUỒNG GÀ: nhà miền Tây vẽ tay (NhaTrong_NhanVatChinh.aseprite) – buồng ngủ (giường + mùng, bàn học), gian
## thờ (bàn thờ ông nội, bàn trà, phản gỗ, cửa chính), bếp củi (phản ăn cơm, thau nhôm rửa chén, cửa hông) và sân gà
## (bội gà theo sức chứa chuồng, ổ rơm ấp trứng, bao lúa, lu nước mưa, quây tập nền cát, cổng tre ra đồng).
## Người nhà (Mẹ, Ba, em trai – family_npc.gd) có mặt theo buổi, đi lại theo lịch sinh hoạt (home_layout.gd ROUTINES,
## tìm đường A* trên lưới thô home_nav.gd, tránh người chơi), nói câu ngắn theo giờ (E khi đứng gần, kể cả lúc đang đi).
## Gà của người chơi THẢ SÂN (yard_chickens.gd / yard_chicken.gd): ban ngày đi dạo, mổ, cào, vỗ cánh, rượt nhau, uống
## nước; tối về bội ngủ (cửa bội đóng, chữ "z"), sáng ra cửa bội mở. Lại gần gà: "[E] <tên gà>" mở bảng chăm (E ở bội
## vẫn được). Đồ vật cao cắt lát y-sort (_sliced) để không đè lên vai người đứng bên cạnh.
## Đi bằng W/A/S/D như ngoài làng (WorldPlayer, phóng ×4/3 cho khớp nét vẽ), E tương tác ([E] gợi ý), Esc / cửa chính /
## cổng tre để về xóm. Camera: lăn chuột hoặc phím - / = để thu/phóng (không bao giờ lộ khoảng trống ngoài nhà). Ánh sáng theo
## GameState.period() (đèn ấm ban đêm). Mái, tán cây, mùng, rèm, khói bếp (04_Above) làm trong khi người chơi đứng dưới.
##
## HỢP ĐỒNG (main.gd):  const HomeScene := preload("res://game/home/home_scene.gd")
##   var r: Dictionary = await HomeScene.run(self)   # self = main (có world, dialog, clock_hud, _fade_to)
##   → {"sleep": bool (chọn ngủ ở giường – main gọi _sleep_until_morning), "day_over": bool (luyện quá 23:00),
##      "changed": bool (đàn gà đổi)}. HomeScene tự ẩn/hiện world (world.set_active), đổi đồng hồ góc phải sang nhà,
##      âm thanh môi trường, và tự giải phóng khi xong.
## HỢP ĐỒNG (cảnh cắt rửa chén): HomeScene.SINK_POS (chân người đứng cạnh thau rửa chén), HomeScene.SINK_BASIN,
##   HomeScene.FRONT_DOOR / SIDE_DOOR (lối công an vô/ra), HomeScene.build_interior() → Node2D gốc (0,0) theo toạ độ
##   nhà, có nền + đồ nội thất y-sort trong con "Actors" (thêm diễn viên vào đó: chân = position) + lớp trên "Above".
##   Không có logic/đầu vào (chỉ lửa/khói bếp chạy hoạt ảnh); tự đặt Camera2D nếu cần (zoom 3 như nhà).

signal finished(result: Dictionary)

const Layout := preload("res://game/home/home_layout.gd")
const Data := preload("res://game/home/home_interior_data.gd")
const ChickenSprite := preload("res://game/home/chicken_sprite.gd")
const HomeState := preload("res://game/home/home_state.gd")
const CoopUI := preload("res://game/home/coop_ui.gd")
const IncubatorUI := preload("res://game/home/incubator_ui.gd")
const DeskUI := preload("res://game/home/desk_ui.gd")
const Items := preload("res://game/data/items.gd")
const Breeds := preload("res://game/data/breeds.gd")
const Audio := preload("res://game/audio/audio_director.gd")
const DayNight := preload("res://game/world/day_night.gd")
const HomeNav := preload("res://game/home/home_nav.gd")
const FamilyNPC := preload("res://game/home/family_npc.gd")
const YardChickens := preload("res://game/home/yard_chickens.gd")
const SCRIPT_PATH: String = "res://game/home/home_scene.gd"
## Bán kính bấm E vào một con gà thả sân (quanh chân gà).
const CHICKEN_TALK_RADIUS: float = 14.0
## Bề cao một lát cắt y-sort của đồ vật cao (xem _sliced).
const SLICE_H: int = 4

const SINK_POS: Vector2 = Layout.SINK_POS
const SINK_BASIN: Vector2 = Layout.SINK_BASIN
const FRONT_DOOR: Vector2 = Layout.FRONT_DOOR
const SIDE_DOOR: Vector2 = Layout.SIDE_DOOR
const MAP_SIZE: Vector2i = Layout.MAP_SIZE
## Các nấc zoom camera trong nhà (lăn chuột / phím - =); mặc định rộng hơn bản cũ (3,0) một chút. Nấc nhỏ hơn mức
## phủ kín màn hình bằng ảnh nhà bị nâng lên mức đó (không lộ khoảng trống).
const ZOOM_STEPS: Array[float] = [2.0, 2.5, 3.0, 3.5, 4.0]
const DEFAULT_ZOOM_INDEX: int = 1
const CAMERA_ZOOM: float = 2.5
## Nấc zoom đang chọn – giữ giữa các lần vô nhà.
static var zoom_index: int = DEFAULT_ZOOM_INDEX
const TINT_DAY: Color = Color(1.0, 0.98, 0.94)
const TINT_NIGHT: Color = Color(0.4, 0.38, 0.55)
## Độ trong của lớp trên (mái, tán, mùng…) khi người chơi đứng dưới – như bản đồ làng.
const FOCUS_ALPHA: float = 0.45
## Bán kính bấm E nói chuyện với người nhà (quanh chân người đó).
const NPC_TALK_RADIUS: float = 22.0
## Bội chưa sửa (ngoài sức chứa) / bội sắp đóng (cấp chuồng kế).
const BROKEN_CAGE: Color = Color(0.74, 0.69, 0.64, 1.0)
const NEXT_PAINTED_CAGE: Color = Color(0.9, 0.86, 0.82, 1.0)
const GHOST_CAGE: Color = Color(1.0, 1.0, 1.0, 0.35)

## Câu nói người nhà theo buổi (0 Sáng … 4 Khuya). Mẹ giáo viên nghiêm chuyện học; Ba hiền, hài; em trai học giỏi.
const FAMILY: Dictionary = {
	&"me": {"name": "Mẹ", "tex": "family_me", "lines": [
		"Chủ nhật mà dậy sớm dữ ha. Cho gà ăn xong rồi phụ mẹ quét nhà nghen.",
		"Rửa tay rồi vô ăn cơm con. Ăn xong coi lại bài, chiều mẹ dò đó.",
		"Học bài chưa mà ra chuồng gà hoài vậy? Kiểm tra dưới tám điểm là mẹ khóa bội gà à nghen.",
		"Tối rồi, ngồi vô bàn học đi con. Gà thì ăn lúa cho no, còn con thì ăn chữ cho no.",
		"Khuya lắm rồi, tắt đèn đi ngủ con. Mai còn dậy sớm.",
	]},
	&"cha": {"name": "Ba", "tex": "family_cha", "lines": [
		"Sáng ra ly cà phê đen, nghe gà gáy một tiếng, đời vậy là sướng rồi con.",
		"Ba ngả lưng trên bộ phản chút xíu thôi… mà gà của con gáy còn to hơn ba ngáy nữa đó, hì hì.",
		"Con này nhìn có tướng nghen. Hồi xưa ông nội chỉ ba coi vảy chân, mà ba quên sạch trơn rồi.",
		"Mẹ con hỏi thì nói ba đang kèm con học nghen. Thiệt ra ba coi đá banh.",
		"",
	]},
	&"em": {"name": "Em trai", "tex": "family_em", "lines": [
		"Hôm nay em làm đề thi thử. Anh Hai đừng cho gà gáy sát cửa sổ nha.",
		"Anh Hai ăn cơm đi, em ăn trước rồi. Chiều em đi bồi dưỡng học sinh giỏi.",
		"Anh biết hông, gà là họ hàng xa của khủng long đó. Đột biến đúng cách là… thôi để em đọc thêm đã.",
		"Bài Công nghệ khó hông anh? Em giải giùm cho, đổi lại anh cho em đặt tên con gà kế nghen.",
		"",
	]},
}

## Sprite có hoạt ảnh theo dải khung ngang (lửa bếp, khói, ánh lửa) – tự chạy, không cần cảnh điều khiển.
class AnimSprite extends Sprite2D:
	var frame_time: float = 0.11
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		frame = int(_t / frame_time) % maxi(hframes, 1)


## Lưới va chạm từ collision.png (1 byte/điểm ảnh, ≠0 = đặc) – nạp một lần cho mọi lần vô nhà.
static var _solid: PackedByteArray = PackedByteArray()
## Lưới tìm đường người nhà theo bộ bội đóng thêm (dựng một lần cho mỗi cấp chuồng).
static var _nav_cache: Dictionary = {}

var main: Node
var dialog: DialogBox
var player: WorldPlayer
## Bảng đang mở (CoopUI/IncubatorUI/DeskUI) – test đọc để bơm phím.
var open_panel: CanvasLayer
var busy: bool = false

var _actors: Node2D
var _coop_root: Node2D
var _egg_root: Node2D
var _chickens: Array = []          # YardChicken (gà thả sân) theo chỉ số gà
var _yard: YardChickens
var _cage_backs: Dictionary = {}   # ô bội có gà → Sprite2D "Back" (đổi ảnh cửa mở / đóng)
var _coop_blocks: Array[Rect2i] = []
var _npc_nodes: Dictionary = {}    # who → FamilyNPC
var _nav: HomeNav
var _nav_blocks: int = -1          # số bội đóng thêm lúc dựng lưới (đổi → dựng lại)
var _yield_nodes: Array = []       # [Node2D, ô bội chiếm chỗ] – vật dời đi khi đóng bội mở rộng
var _above: Array = []             # [Sprite2D, Image hoặc null, Rect2]
var _interactables: Array[Dictionary] = []
var _nearby: Dictionary = {}
var _camera: Camera2D
var _modulate: CanvasModulate
var _lights: Array = []           # [PointLight2D, năng lượng gốc, luôn sáng]
var _light_tex: Texture2D
var _ui: CanvasLayer
var _prompt: Label
var _status: Label
var _prompt_art: Control
var _time: float = 0.0
var _done: bool = false
var _own_dialog: bool = false
var _period: int = -1
var _prev_clock_world: Node


# =================================================================== API tĩnh

## Vô nhà từ main: ẩn world, chạy cảnh, chờ người chơi ra/ngủ, hiện lại world. Xem HỢP ĐỒNG ở đầu file.
static func run(p_main: Node) -> Dictionary:
	var script: GDScript = load(SCRIPT_PATH)
	var home: Node2D = script.new()
	home.set("main", p_main)
	p_main.add_child(home)
	var result: Dictionary = await home.call("_session")
	return result


## Dựng nội thất y như trong nhà (nền + đồ đạc y-sort trong "Actors" + lớp trên "Above") cho cảnh cắt. Bội gà vẽ sẵn
## hiện như bội trống; không có gà, người nhà, đèn hay logic.
static func build_interior() -> Node2D:
	_load_collision()
	var root := Node2D.new()
	root.name = "HomeInterior"
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var actors: Node2D = _build_static(root, [], [])
	for f in Data.PAINTED_CAGES:
		actors.add_child(make_cage(f, Color.WHITE, true))
	return root


## Nền + hoạt ảnh sát nền + vật sát nền + "Actors" (y-sort, đồ vật) + "Above". yield_out/above_out nhận
## [node, ô bội] và [sprite, Image, Rect2] (để dời vật / làm trong mái). Trả về node "Actors".
static func _build_static(root: Node2D, yield_out: Array, above_out: Array) -> Node2D:
	var ground := Sprite2D.new()
	ground.name = "Ground"
	ground.texture = load(Data.ART + "ground.png")
	ground.centered = false
	root.add_child(ground)
	for e in Data.DECOR_ANIM:
		root.add_child(_make_sprite(e))
	var floor_props := Node2D.new()
	floor_props.name = "FloorProps"
	root.add_child(floor_props)
	var actors := Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	root.add_child(actors)
	for e in Data.OBJECTS:
		var sprite: Sprite2D = _make_sprite(e)
		var node: Node2D
		var top: int = _footprint_top(e)
		if int(e["sort"]) == Data.FLOOR_SORT:
			node = sprite
			floor_props.add_child(sprite)
		elif int(e["frames"]) == 1 and top < int(e["sort"]) - SLICE_H:
			node = _sliced(e, sprite, top)
			actors.add_child(node)
		else:
			node = Node2D.new()
			node.name = String(e["name"])
			node.position = Vector2(0.0, float(e["sort"]))
			sprite.position.y -= float(e["sort"])
			node.add_child(sprite)
			actors.add_child(node)
		if int(e["yield"]) >= 0:
			yield_out.append([node, int(e["yield"])])
	var above := Node2D.new()
	above.name = "Above"
	above.z_index = 10
	root.add_child(above)
	for e in Data.ABOVE:
		var s: Sprite2D = _make_sprite(e)
		above.add_child(s)
		var img: Image = null
		if int(e["frames"]) == 1:
			img = (s.texture as Texture2D).get_image()
			if img != null and img.is_compressed():
				img = null
		above_out.append([s, img, Rect2(e["pos"], e["size"])])
	return actors


## Đỉnh "chân đế" của đồ vật trên lưới va chạm: từ gốc y-sort đi ngược lên theo từng cột của vật khi còn đặc (lấy
## trung vị các cột). Vật không có va chạm dưới chân → trả về chính gốc y-sort (không cắt lát).
static func _footprint_top(e: Dictionary) -> int:
	var sort: int = int(e["sort"])
	if sort == Data.FLOOR_SORT or _solid.size() != MAP_SIZE.x * MAP_SIZE.y:
		return sort
	var x0: int = int(e["pos"].x)
	var x1: int = x0 + int(e["size"].x)
	var tops: Array[int] = []
	for x in range(maxi(x0, 0), mini(x1, MAP_SIZE.x)):
		var y: int = mini(sort - 1, MAP_SIZE.y - 1)
		if _solid[y * MAP_SIZE.x + x] == 0:
			continue
		while y > 0 and _solid[(y - 1) * MAP_SIZE.x + x] != 0:
			y -= 1
		tops.append(y)
	if tops.size() < 3:
		return sort
	tops.sort()
	return tops[tops.size() / 2]


## Đồ vật cao/dài (tủ áo, kệ ti vi, bàn thờ, giường, trường kỷ, chuồng gỗ…) cắt thành lát ngang SLICE_H px, mỗi lát
## một gốc y-sort = đáy lát, kẹp trong [đỉnh chân đế, gốc y-sort của vật]. Đứng BÊN CẠNH vật (chân nằm trong chiều sâu
## chân đế) thì phần thân trên của vật vẽ sau lưng người – không còn đè lên vai; đứng SAU vật (trên đỉnh chân đế) thì
## cả vật vẫn che người như cũ. Container giữ tên vật, y_sort_enabled để các lát y-sort chung với "Actors".
static func _sliced(e: Dictionary, sprite: Sprite2D, top: int) -> Node2D:
	var node := Node2D.new()
	node.name = String(e["name"])
	node.y_sort_enabled = true
	node.set_meta("footprint_top", top)
	var sort: int = int(e["sort"])
	var pos: Vector2 = e["pos"]
	var size: Vector2 = e["size"]
	var y: int = int(pos.y)
	var end: int = int(pos.y + size.y)
	var k: int = 0
	while y < end:
		var bottom: int = mini(y + SLICE_H, end)
		var s_sort: int = clampi(bottom, top, sort)
		# gộp các lát cùng gốc (phần trên kẹp ở đỉnh chân đế) thành một
		while bottom < end and clampi(mini(bottom + SLICE_H, end), top, sort) == s_sort:
			bottom = mini(bottom + SLICE_H, end)
		var holder := Node2D.new()
		holder.position = Vector2(0, s_sort)
		var s: Sprite2D = sprite if k == 0 else Sprite2D.new()
		s.texture = sprite.texture
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(0, y - pos.y, size.x, bottom - y)
		s.position = Vector2(pos.x, y - s_sort)
		holder.add_child(s)
		node.add_child(holder)
		y = bottom
		k += 1
	return node


## Sprite của một mục dữ liệu (góc trên trái = pos; dải khung → AnimSprite).
static func _make_sprite(e: Dictionary) -> Sprite2D:
	var frames: int = int(e["frames"])
	var s: Sprite2D = AnimSprite.new() if frames > 1 else Sprite2D.new()
	s.name = "s_" + String(e["name"])
	s.texture = load(Data.ART + String(e["tex"]))
	s.centered = false
	s.position = e["pos"]
	if frames > 1:
		s.hframes = frames
		(s as AnimSprite).frame_time = Data.FRAME_TIME
	return s


## Ảnh thân bội theo cửa: 0 bội trống (không cửa), 1 cửa mở (ban ngày, gà ra sân), 2 cửa đóng (gà ngủ trong bội).
static func cage_texture(door: int) -> Texture2D:
	match door:
		1:
			return load(Data.ART + "cage_open.png")
		2:
			return load(Data.ART + "cage_closed.png")
	return load(Data.ART + "cage_empty.png")


## Bội gà (gốc = giữa đáy): bóng đổ + thân bội ("Back", ảnh theo door – xem cage_texture). with_front: thêm lớp nan
## tre (tên "Front") vẽ đè lên trên (bản cũ nhốt gà trong bội; nay gà thả sân nên không dùng nữa, giữ cho cảnh cắt).
static func make_cage(foot: Vector2, tint: Color, shadow: bool, with_front: bool = false, door: int = 0) -> Node2D:
	var node := Node2D.new()
	node.position = foot
	var size := Vector2(Data.CAGE_SIZE)
	if shadow:
		var sh := Sprite2D.new()
		sh.texture = load(Data.ART + "cage_shadow.png")
		sh.centered = false
		sh.position = Data.CAGE_SHADOW_OFFSET
		sh.modulate = Color(1, 1, 1, tint.a)
		node.add_child(sh)
	var back := Sprite2D.new()
	back.name = "Back"
	back.texture = cage_texture(door)
	back.centered = false
	back.position = Vector2(-floorf(size.x * 0.5), -size.y)
	back.modulate = tint
	node.add_child(back)
	if with_front:
		var front := Sprite2D.new()
		front.name = "Front"
		front.texture = load(Data.ART + "cage_front.png")
		front.centered = false
		front.position = back.position
		front.modulate = Color(tint.r, tint.g, tint.b, tint.a * 0.7)   # nan tre hơi trong để thấy rõ gà bên trong
		node.add_child(front)
	return node


# =================================================================== dựng cảnh

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_collision()
	if main != null:
		dialog = main.get("dialog") as DialogBox
	if dialog == null:
		dialog = DialogBox.new()
		add_child(dialog)
		_own_dialog = true
	_actors = _build_static(self, _yield_nodes, _above)
	_coop_root = Node2D.new()
	_coop_root.name = "Coops"
	_coop_root.y_sort_enabled = true
	_actors.add_child(_coop_root)
	_egg_root = Node2D.new()
	_egg_root.name = "Eggs"
	_egg_root.position = Vector2(0, 250)          # gốc y-sort ngay dưới ổ rơm (đáy 249)
	_actors.add_child(_egg_root)
	_yard = YardChickens.new()
	_yard.setup(self, _actors)
	add_child(_yard)
	move_child(_yard, _actors.get_index())        # vẽ bụi/đất ngay dưới "Actors"
	player = WorldPlayer.new()
	player.world = self
	player.position = Layout.SPAWN
	player.facing = Vector2i(0, -1)
	player.scale = Vector2(Layout.PLAYER_SCALE, Layout.PLAYER_SCALE)
	_actors.add_child(player)
	_camera = Camera2D.new()
	_camera.zoom = Vector2.ONE * _zoom_for(zoom_index)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = MAP_SIZE.x
	_camera.limit_bottom = MAP_SIZE.y
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	_follow_camera()
	_build_lights()
	_build_ui()
	rebuild()
	_camera.make_current()
	_camera.reset_smoothing()


## Camera là con của cảnh (không phải của người chơi đã phóng ×1,25) – bám theo thân người chơi.
func _follow_camera() -> void:
	_camera.position = player.position + Vector2(0, -24)


static func _load_collision() -> void:
	if _solid.size() == MAP_SIZE.x * MAP_SIZE.y:
		return
	var tex: Texture2D = load(Data.ART + "collision.png")
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		push_error("home: thiếu collision.png – chạy tools/art/build_home_interior.py")
		_solid = PackedByteArray()
		_solid.resize(MAP_SIZE.x * MAP_SIZE.y)
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_L8)
	_solid = img.get_data()


## Dựng lại phần thay đổi theo dữ liệu: bội gà + gà, trứng trên ổ rơm, người nhà theo buổi.
func rebuild() -> void:
	_build_coops()
	_build_eggs()
	_ensure_nav()
	var feet: Array = []
	for slot in range(maxi(slot_count(), Data.PAINTED_CAGES.size())):
		if Layout.is_cage(slot) and (Layout.is_painted(slot) or slot < slot_count()):
			feet.append(Layout.coop_foot(slot))
	_yard.set_nav(_nav, feet)
	_yard.sync()
	_chickens = _yard.chickens()
	_update_cage_doors()
	_build_family()
	_build_interactables()


## Lưới tìm đường cho người nhà (dựng lại khi số bội đóng thêm đổi).
func _ensure_nav() -> void:
	if _nav != null and _nav_blocks == _coop_blocks.size():
		return
	var key: String = str(_coop_blocks)
	_nav = _nav_cache.get(key) as HomeNav
	if _nav == null:
		_nav = HomeNav.new()
		_nav.build(_solid, MAP_SIZE, _coop_blocks)
		_nav_cache[key] = _nav
	_nav_blocks = _coop_blocks.size()
	for who in _npc_nodes:
		(_npc_nodes[who] as FamilyNPC).nav = _nav


## Số ô bội hiển thị: sức chứa hiện tại + các ô của cấp chuồng kế (vẽ mờ "đóng được").
static func slot_count() -> int:
	var cap: int = GameState.coop_capacity()
	if GameState.coop_upgrade_price() < 0:
		return mini(cap, Layout.MAX_SLOTS)
	var next: int = GameState.COOP_CAPACITY[mini(GameState.coop_level, GameState.COOP_CAPACITY.size() - 1)]
	return maxi(cap, mini(next, Layout.MAX_SLOTS))


func _build_coops() -> void:
	for child in _coop_root.get_children():
		child.queue_free()
	_cage_backs.clear()
	_coop_blocks.clear()
	var cap: int = GameState.coop_capacity()
	var shown: int = slot_count()
	for entry in _yield_nodes:
		(entry[0] as CanvasItem).visible = shown <= int(entry[1])
	var total: int = maxi(shown, Data.PAINTED_CAGES.size())
	for slot in range(total):
		var foot: Vector2 = Layout.coop_foot(slot)
		var built: bool = slot < cap
		var tint: Color = Color.WHITE
		if not built:
			if Layout.is_painted(slot):
				tint = NEXT_PAINTED_CAGE if slot < shown else BROKEN_CAGE
			else:
				tint = GHOST_CAGE
		var has_chicken: bool = built and slot < GameState.chickens.size()
		var node: Node2D
		if Layout.is_cage(slot):
			node = make_cage(foot, tint, built and not Layout.is_painted(slot), false, 1 if has_chicken else 0)
			if has_chicken:
				_cage_backs[slot] = node.get_node(^"Back")
			if built and not Layout.is_painted(slot):
				_coop_blocks.append(Layout.coop_block(slot))
		else:
			node = Node2D.new()
			node.position = foot
			var pad := Sprite2D.new()
			pad.texture = load(Data.ART + "straw_pad.png")
			pad.position = Vector2(0, -3)
			pad.modulate = Color(1, 1, 1, 1.0 if built else 0.4)
			node.add_child(pad)
		node.name = "coop_%d" % slot
		_coop_root.add_child(node)
	# Gà không còn nhốt trong bội (nan tre che gà thành từng mảnh): gà thả sân – yard_chickens.gd (rebuild() đồng bộ).


## Cửa bội: mở khi gà ra sân, đóng khi gà đã chui vào ngủ.
func _update_cage_doors() -> void:
	for slot in _cage_backs:
		var back: Sprite2D = _cage_backs[slot]
		if not is_instance_valid(back):
			continue
		var asleep: bool = slot < _chickens.size() and is_instance_valid(_chickens[slot]) \
			and bool((_chickens[slot] as Node).call("in_cage"))
		var want: int = 2 if asleep else 1
		if int(back.get_meta("door", -1)) != want:
			back.set_meta("door", want)
			back.texture = cage_texture(want)


## Cửa bội ô slot đang đóng (test đọc).
func cage_closed(slot: int) -> bool:
	var back: Sprite2D = _cage_backs.get(slot) as Sprite2D
	return back != null and is_instance_valid(back) and int(back.get_meta("door", -1)) == 2


func yard() -> YardChickens:
	return _yard


func _build_eggs() -> void:
	for child in _egg_root.get_children():
		child.queue_free()
	for i in range(mini(GameState.incubator.size(), Layout.EGG_SPOTS.size())):
		var e: Dictionary = GameState.incubator[i]
		var info: Dictionary = Items.get_item(e["egg"])
		var rare: bool = StringName(info.get("rarity", &"common")) == &"rare"
		var egg := Sprite2D.new()
		egg.texture = load(Layout.ART + ("egg_rare.png" if rare else "egg.png"))
		egg.scale = Vector2(Layout.EGG_SCALE, Layout.EGG_SCALE)
		egg.position = Layout.EGG_SPOTS[i] - _egg_root.position
		egg.set_meta("ready", int(e["days_left"]) <= 0)
		_egg_root.add_child(egg)


## Người nhà theo buổi: ai mới có mặt thì xuất hiện ngay tại chỗ làm việc đầu tiên; ai còn ở nhà mà sang buổi mới thì
## đi bộ tới chỗ mới; ai vắng thì biến mất. Gọi lại trong cùng buổi (sau mỗi tương tác) không làm gì người đang đi.
func _build_family() -> void:
	var period: int = GameState.period()
	var changed: bool = period != _period
	_period = period
	for who in FAMILY:
		var plan: Array = Layout.routine(who, period, GameState.is_school_day())
		var present: bool = not plan.is_empty() and String(FAMILY[who]["lines"][period]) != ""
		var npc: FamilyNPC = _npc_nodes.get(who) as FamilyNPC
		if not present:
			if npc != null:
				npc.queue_free()
				_npc_nodes.erase(who)
			continue
		if npc == null:
			npc = FamilyNPC.new()
			npc.setup(who, self, _nav, load(Layout.ART + String(FAMILY[who]["tex"]) + ".png"), plan, 0)
			_actors.add_child(npc)
			_npc_nodes[who] = npc
		elif changed:
			npc.set_routine(plan, 0, false)


func _build_interactables() -> void:
	_interactables.clear()
	for it in Layout.INTERACTABLES:
		_interactables.append(it.duplicate())
	var cap: int = GameState.coop_capacity()
	for slot in range(slot_count()):
		var label: String
		var where: String = "Bội gà" if Layout.is_cage(slot) else "Chuồng gỗ"
		if slot < GameState.chickens.size():
			var c: Dictionary = GameState.chickens[slot]
			label = "%s: %s (%s Lv%d)" % [where, c["name"], Breeds.display_name(int(c["breed"])), int(c["level"])]
		elif slot < cap:
			label = "Bội trống" if Layout.is_cage(slot) else "Ổ rơm trống (chuồng gỗ)"
		else:
			label = "%s (nâng chuồng · %s)" % ["Sửa bội cũ" if Layout.is_painted(slot) else "Đóng thêm bội" if Layout.is_cage(slot)
				else "Lót thêm ổ chuồng gỗ", GameState.money_text(GameState.coop_upgrade_price())]
		_interactables.append({"id": StringName("coop_%d" % slot), "label": label,
			"pos": Layout.coop_stand(slot), "radius": 15.0, "slot": slot})
	for who in _npc_nodes:
		_interactables.append({"id": StringName("npc_" + String(who)), "label": "Nói chuyện với %s" % FAMILY[who]["name"],
			"pos": (_npc_nodes[who] as Node2D).position, "radius": NPC_TALK_RADIUS, "who": who})
	# gà thả sân: lại gần thấy "[E] <tên gà>", bấm E mở bảng chăm con đó (như bấm E ở bội của nó)
	for i in range(mini(_chickens.size(), GameState.chickens.size())):
		if not is_instance_valid(_chickens[i]):
			continue
		_interactables.append({"id": StringName("chick_%d" % i), "label": String(GameState.chickens[i]["name"]),
			"pos": (_chickens[i] as Node2D).position, "radius": CHICKEN_TALK_RADIUS, "chick": i})
	_update_npc_interactables()


## Điểm nói chuyện đi theo người nhà / gà đang đi lại (gà đang ngủ trong bội thì không bấm được – bấm ở bội).
func _update_npc_interactables() -> void:
	for it in _interactables:
		var who: StringName = StringName(it.get("who", &""))
		if who != &"" and _npc_nodes.has(who):
			it["pos"] = (_npc_nodes[who] as Node2D).position
		var ci: int = int(it.get("chick", -1))
		if ci >= 0 and ci < _chickens.size() and is_instance_valid(_chickens[ci]):
			var c: Node2D = _chickens[ci]
			it["pos"] = c.position
			it["radius"] = CHICKEN_TALK_RADIUS if bool(c.call("is_roaming")) else 0.0


func _build_lights() -> void:
	_modulate = CanvasModulate.new()
	add_child(_modulate)
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
	_light_tex = tex
	for l in Layout.LIGHTS:
		_add_light(l[0], float(l[1]), float(l[2]), l[3], false)
	for p in Layout.FIRE_LIGHTS:
		_add_light(p, 44.0, 0.6, Color(1.0, 0.55, 0.25), true)


func _add_light(pos: Vector2, radius: float, energy: float, color: Color, always: bool) -> void:
	var light := PointLight2D.new()
	light.texture = _light_tex
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # quầng sáng mịn (gốc cây mặc định NEAREST)
	light.texture_scale = radius / 64.0
	light.color = color
	light.position = pos
	add_child(light)
	_lights.append([light, energy, always])


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	# Bảng trạng thái gỗ sẫm (UISkin) – chữ kem ×2, tự co theo chữ.
	var panel: PanelContainer = UISkin.status_panel()
	panel.position = Vector2(10, 10)
	_ui.add_child(panel)
	_status = UISkin.label("", UISkin.FS_BODY, UISkin.CREAM, false, 4)
	panel.add_child(_status)
	_status.resized.connect(func() -> void: panel.reset_size())
	# Nhắc [E]: Label giữ chữ (test đọc .text/.visible) nhưng không tự vẽ; con vẽ phím gỗ UISkin.
	_prompt = _label(Vector2.ZERO, UISkin.FS_BODY, UISkin.INK, false)
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_prompt.self_modulate = Color(1, 1, 1, 0)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -250.0
	_prompt.offset_left = -360.0
	_prompt.offset_right = 360.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var art := Control.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(func() -> void:
		if _prompt.text == "":
			return
		var ps: Vector2 = UISkin.prompt_size(_prompt.text)
		UISkin.draw_prompt(art, Vector2(roundf((art.size.x - ps.x) * 0.5), 0.0), _prompt.text))
	_prompt.add_child(art)
	_prompt_art = art
	var help := Control.new()
	help.set_anchors_preset(Control.PRESET_FULL_RECT)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.draw.connect(func() -> void:
		UISkin.draw_key_hints(help, help.size - Vector2(10, 8), [["WASD", "Đi"], ["E", "Tương tác"], ["Esc", "Về xóm (ra ngõ)"]]))
	help.resized.connect(help.queue_redraw)
	UISkin.pixel(help)
	_ui.add_child(help)


func _label(pos: Vector2, font_size: int, color: Color, bold: bool) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_override("font", DialogBox.make_font(bold))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UISkin.label_shadow(label, 4)
	UISkin.pixel(label)
	_ui.add_child(label)
	return label


# =================================================================== phiên (vào → ra)

func _fade(alpha: float, seconds: float) -> void:
	if main != null and main.has_method("_fade_to"):
		await main.call("_fade_to", alpha, seconds)


func _session() -> Dictionary:
	var world: Node = main.get("world") if main != null else null
	var hud: Node = main.get("clock_hud") if main != null else null
	await _fade(1.0, 0.3)
	if world != null and is_instance_valid(world):
		world.call("set_active", false)
	_camera.make_current()
	_camera.reset_smoothing()
	if hud != null:
		_prev_clock_world = hud.get("world")
		hud.set("world", self)
	Audio.sfx(&"step_wood", -6.0)
	_apply_ambience()
	await _fade(0.0, 0.3)
	var result: Dictionary = await finished
	HomeState.save_state()
	if not bool(result.get("sleep", false)) or main == null:
		await _fade(1.0, 0.3)
	if hud != null:
		hud.set("world", _prev_clock_world if _prev_clock_world != null else world)
	if world != null and is_instance_valid(world):
		world.call("set_active", true)
		var wp: Variant = world.get("player")
		if wp is WorldPlayer:
			(wp as WorldPlayer).can_move = false   # main bật lại sau khi xong lượt tương tác
	visible = false
	_ui.visible = false
	if not bool(result.get("sleep", false)):
		await _fade(0.0, 0.3)
	queue_free()   # cuối cùng: coroutine phải chạy xong trước khi node bị giải phóng
	return result


func _apply_ambience() -> void:
	var night: float = DayNight.night_factor(GameState.minutes)
	Audio.ambience({&"birds": lerpf(0.18, 0.0, night), &"crickets": lerpf(0.0, 0.45, night), &"village": 0.08})


## Kết thúc phiên: sleep = ngủ ở giường (main gọi _sleep_until_morning).
func leave(sleep: bool = false, day_over: bool = false) -> void:
	if _done:
		return
	_done = true
	busy = true
	player.can_move = false
	finished.emit({"sleep": sleep, "day_over": day_over, "changed": false})


# =================================================================== mỗi frame

func _process(delta: float) -> void:
	_time += delta
	_update_light()
	_update_zoom(delta)
	_follow_camera()
	_update_above(player.position)
	if GameState.period() != _period and not busy:
		_build_family()
		_build_interactables()
	# trứng tới ngày nở thì lắc lư; vương miện gà chiến nhún nhảy; người nhà thở
	for egg in _egg_root.get_children():
		var s := egg as Sprite2D
		if s != null and bool(s.get_meta("ready", false)):
			s.rotation = sin(_time * 9.0) * 0.18
	_update_cage_doors()
	_update_npc_interactables()
	_status.text = "%s · %s\nTechnology %d · Biotech %d · Gà %d/%d" % [GameState.player_name,
		GameState.money_text(GameState.money), GameState.technology, GameState.biotech, GameState.chickens.size(),
		GameState.coop_capacity()]
	_nearby = {}
	if not busy and player.can_move:
		_nearby = nearest_interactable(player.position)
	_prompt.visible = not _nearby.is_empty() and not busy and not dialog.is_open()
	if _prompt.visible:
		_prompt.text = "[E] %s" % String(_nearby["label"])
		_prompt_art.queue_redraw()


## Người chơi đứng dưới mái/tán/mùng/rèm/khói (lớp trên): làm trong lớp đó (xét 3 điểm trên thân, theo điểm ảnh đục).
func _update_above(foot: Vector2) -> void:
	var points: Array[Vector2] = [foot + Vector2(0, -8), foot + Vector2(0, -26), foot + Vector2(0, -44)]
	for entry in _above:
		var s: Sprite2D = entry[0]
		var img: Image = entry[1]
		var rect: Rect2 = entry[2]
		var under: bool = false
		for p in points:
			if not rect.has_point(p):
				continue
			if img == null:
				under = true
				break
			var local := Vector2i(p - rect.position)
			if img.get_pixelv(local).a > 0.05:
				under = true
				break
		s.self_modulate.a = FOCUS_ALPHA if under else 1.0


## Mức trong hiện tại của lớp trên tên name (test đọc).
func above_alpha(layer_name: String) -> float:
	for entry in _above:
		if (entry[0] as Sprite2D).name == "s_" + layer_name:
			return (entry[0] as Sprite2D).self_modulate.a
	return -1.0


func _update_light() -> void:
	var night: float = DayNight.night_factor(GameState.minutes)
	_modulate.color = TINT_DAY.lerp(TINT_NIGHT, night)
	for entry in _lights:
		var l: PointLight2D = entry[0]
		var e: float = float(entry[1]) * (maxf(night, 0.35) if bool(entry[2]) else night)
		l.energy = e
		l.visible = e > 0.01


## Điểm tương tác gần nhất trong bán kính ({} nếu không có).
func nearest_interactable(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for it in _interactables:
		var d: float = pos.distance_to(it["pos"])
		if d <= float(it["radius"]) and d < best_d:
			best_d = d
			best = it
	return best


func interactables() -> Array[Dictionary]:
	return _interactables


func find_interactable(id: StringName) -> Dictionary:
	for it in _interactables:
		if StringName(it["id"]) == id:
			return it
	return {}


func chicken_sprites() -> Array:
	return _chickens


func npc_ids() -> Array:
	return _npc_nodes.keys()


# =================================================================== va chạm (WorldPlayer gọi)

func is_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= MAP_SIZE.x or y >= MAP_SIZE.y:
		return true
	if _solid[y * MAP_SIZE.x + x] != 0:
		return true
	var p := Vector2i(x, y)
	for r in _coop_blocks:
		if r.has_point(p):
			return true
	for who in _npc_nodes:
		if (_npc_nodes[who] as FamilyNPC).block_rect().has_point(p):
			return true
	return false


## Va chạm tĩnh (nền vẽ + bội đóng thêm), không tính người – để kiểm người nhà không bước vào chỗ đặc.
func is_static_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= MAP_SIZE.x or y >= MAP_SIZE.y:
		return true
	if _solid[y * MAP_SIZE.x + x] != 0:
		return true
	var p := Vector2i(x, y)
	for r in _coop_blocks:
		if r.has_point(p):
			return true
	return false


## Vùng chân người chơi (thế giới nhà).
func _player_rect() -> Rect2i:
	var f: int = WorldPlayer.FOOT_HALF_WIDTH + 1
	return Rect2i(int(player.position.x) - f, int(player.position.y) - WorldPlayer.FOOT_HEIGHT - 1, f * 2, WorldPlayer.FOOT_HEIGHT + 2)


## FamilyNPC hỏi: bước tới next có đụng người chơi / người nhà khác không (chỉ tính khi đang tiến lại gần họ –
## lỡ đứng sát nhau thì vẫn được bước ra).
func npc_path_blocked(npc: FamilyNPC, next: Vector2) -> bool:
	var r := Rect2i(int(next.x) - FamilyNPC.BODY_HALF, int(next.y) - FamilyNPC.BODY_H + 1, FamilyNPC.BODY_HALF * 2, FamilyNPC.BODY_H)
	var others: Array = [[_player_rect(), player.position]]
	for who in _npc_nodes:
		var o: FamilyNPC = _npc_nodes[who]
		if o != npc:
			others.append([o.block_rect(), o.position])
	for e in others:
		var rect: Rect2i = e[0]
		var at: Vector2 = e[1]
		if r.grow(1).intersects(rect) and next.distance_to(at) < npc.position.distance_to(at):
			return true
	return false


## Chỗ đang đứng của người chơi + người nhà khác (FamilyNPC tìm đường vòng quanh).
func family_obstacles(npc: FamilyNPC) -> Array:
	var out: Array = [player.position]
	for who in _npc_nodes:
		if _npc_nodes[who] != npc:
			out.append((_npc_nodes[who] as Node2D).position)
	return out


func npc_node(who: StringName) -> FamilyNPC:
	return _npc_nodes.get(who) as FamilyNPC


func nav() -> HomeNav:
	return _nav


# =================================================================== camera zoom

## Zoom nhỏ nhất để ảnh nhà phủ kín khung nhìn (không lộ khoảng trống ngoài nhà).
func min_zoom() -> float:
	var view: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1152, 648)
	return maxf(view.x / float(MAP_SIZE.x), view.y / float(MAP_SIZE.y))


func _zoom_for(index: int) -> float:
	return maxf(ZOOM_STEPS[clampi(index, 0, ZOOM_STEPS.size() - 1)], min_zoom())


## Đổi nấc zoom (+1 = phóng to / gần hơn, −1 = thu nhỏ / thấy rộng hơn). Nấc dưới mức phủ kín thì không xuống nữa.
func step_zoom(dir: int) -> void:
	var i: int = clampi(zoom_index + dir, 0, ZOOM_STEPS.size() - 1)
	if dir < 0 and ZOOM_STEPS[i] < min_zoom() and ZOOM_STEPS[zoom_index] <= min_zoom():
		i = zoom_index
	zoom_index = i


func target_zoom() -> float:
	return _zoom_for(zoom_index)


func _update_zoom(delta: float) -> void:
	var z: float = target_zoom()
	var cur: float = _camera.zoom.x
	if absf(cur - z) < 0.002:
		cur = z
	else:
		cur = lerpf(cur, z, clampf(delta * 12.0, 0.0, 1.0))
	cur = maxf(cur, min_zoom())
	_camera.zoom = Vector2(cur, cur)


## Tiếng bước chân: ván/gạch trong nhà nghe "gỗ", bếp nền đất và sân gà nghe đất.
func is_wood(pos: Vector2) -> bool:
	return Layout.HOUSE_RECT.has_point(pos) and not Layout.KITCHEN_RECT.has_point(pos)

# =================================================================== đầu vào & tương tác

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	# zoom camera: lăn chuột hoặc - / = (kể cả khi đang mở hộp thoại; bảng chuồng/lò ấp/bàn học thì không)
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and open_panel == null \
			and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		step_zoom(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		get_viewport().set_input_as_handled()
		return
	var zk := event as InputEventKey
	if zk != null and zk.pressed and not zk.echo and open_panel == null:
		match zk.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD:
				step_zoom(1)
				get_viewport().set_input_as_handled()
				return
			KEY_MINUS, KEY_KP_SUBTRACT:
				step_zoom(-1)
				get_viewport().set_input_as_handled()
				return
	if busy or not (event is InputEventKey) or dialog.is_open():
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_E:
		get_viewport().set_input_as_handled()
		if not _nearby.is_empty():
			interact(StringName(_nearby["id"]))
	elif key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		leave(false)


## Chạy một tương tác theo id (cùng đường với phím E; test gọi thẳng).
func interact(id: StringName) -> void:
	if busy or _done:
		return
	busy = true
	player.can_move = false
	var it: Dictionary = find_interactable(id)
	var s: String = String(id)
	if s.begins_with("coop_"):
		await _on_coop(int(it.get("slot", int(s.trim_prefix("coop_")))))
	elif s.begins_with("chick_"):
		await _on_chicken(int(it.get("chick", int(s.trim_prefix("chick_")))))
	elif s.begins_with("npc_"):
		await _on_family(StringName(s.trim_prefix("npc_")))
	else:
		match id:
			&"door_front", &"gate":
				leave(false)
				return
			&"bed":
				await _on_bed()
			&"desk":
				var r: Dictionary = await _open_panel(DeskUI.new(), [])
				if bool(r.get("day_over", false)):
					await _say([["", "Khuya lơ khuya lắc rồi (%s)! Mẹ kêu đi ngủ kìa." % GameState.time_text()]])
					leave(false, true)
					return
			&"altar":
				await _on_altar()
			&"table":
				await _on_table()
			&"sink":
				await _say([["", "Thau nhôm đầy nước, chén dĩa sau bữa cơm chất cao như núi. Mẹ dặn ăn xong là rửa liền, để lâu kiến bu."]])
			&"stove":
				await _say([["", "Bếp củi đỏ lửa, nồi cơm sôi lục bục. Ông Táo coi bếp, mẹ coi nồi, còn con coi… mấy miếng cơm cháy."]])
			&"tv":
				await _say([["", "Ti vi đang chiếu cải lương. Ba dặn tối nay chừa kênh đá banh cho ba nghen."]])
			&"incubator":
				await _open_panel(IncubatorUI.new(), [])
			&"feed_all":
				await _on_feed_all()
			&"water_jar":
				await _say([["", "Lu hứng nước mưa mát rượi. Muốn tắm cho gà thì mở bội gà rồi chọn «Tắm» nghen."]])
			&"post":
				await _on_post()
	if _done:
		return
	rebuild()
	busy = false
	player.can_move = true


func _say(lines: Array) -> void:
	await dialog.say(lines)


## Mở một bảng (CanvasLayer có run()) và chờ xong. args: tham số của run().
func _open_panel(panel: CanvasLayer, args: Array) -> Dictionary:
	panel.set("dialog", dialog)
	add_child(panel)
	open_panel = panel
	var r: Variant = await panel.callv("run", args)
	open_panel = null
	panel.queue_free()
	return r if r is Dictionary else {}


func _on_coop(slot: int) -> void:
	var cap: int = GameState.coop_capacity()
	if slot < GameState.chickens.size():
		var r: Dictionary = await _open_panel(CoopUI.new(), [slot])
		if bool(r.get("day_over", false)):
			await _say([["", "Khuya lơ khuya lắc rồi (%s)! Mẹ kêu đi ngủ kìa." % GameState.time_text()]])
			leave(false, true)
		return
	if slot < cap:
		await _say([["", "Bội này còn trống, rơm mới thay. Mua gà ở chợ, hoặc ấp trứng ở lò ấp để có thêm chiến kê."]])
		return
	var price: int = GameState.coop_upgrade_price()
	if price < 0:
		return
	var next_cap: int = GameState.COOP_CAPACITY[GameState.coop_level]
	var pick: int = await dialog.choose("Ba", "Muốn đóng thêm bội hả con? Nâng chuồng lên cấp %d (chứa %d con) tốn %s. Con đang có %s." % [
		GameState.coop_level + 1, next_cap, GameState.money_text(price), GameState.money_text(GameState.money)],
		["Nâng chuồng · %s" % GameState.money_text(price), "Để dành tiền đã"])
	if pick != 0:
		return
	if GameState.upgrade_coop():
		Audio.sfx(&"coin", -3.0)
		await _say([["Ba", "Được! Ba với con chặt tre đan thêm bội liền. Giờ chuồng chứa được %d con rồi đó." % GameState.coop_capacity()]])
	else:
		await _say([["Ba", GameState.last_error + " Đi làm thêm kiếm tiền đã con."]])


## Bấm E vào một con gà thả sân: gà đứng lại quay sang người chơi, mở bảng chăm của nó (như ở bội).
func _on_chicken(i: int) -> void:
	if i < 0 or i >= GameState.chickens.size():
		return
	var c: Node2D = _chickens[i] if i < _chickens.size() else null
	if c != null and is_instance_valid(c):
		c.call("begin_talk", player.position)
		var d: Vector2 = c.position - player.position
		player.face(Vector2i(signi(int(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, 1 if d.y >= 0.0 else -1))
	await _on_coop(i)
	if c != null and is_instance_valid(c):
		c.call("end_talk")


func _on_family(who: StringName) -> void:
	var line: String = String(FAMILY[who]["lines"][clampi(GameState.period(), 0, 4)])
	if line == "":
		line = "…"
	var npc: FamilyNPC = _npc_nodes.get(who) as FamilyNPC
	if npc != null:
		npc.begin_talk(player.position)     # đứng lại, quay sang người chơi
		var d: Vector2 = npc.position - player.position
		player.face(Vector2i(signi(int(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, 1 if d.y >= 0.0 else -1))
	await _say([[String(FAMILY[who]["name"]), line]])
	if npc != null and is_instance_valid(npc):
		npc.end_talk()


func _on_bed() -> void:
	var pick: int = await dialog.choose("", "Đi ngủ tới sáng mai? (bây giờ %s)" % GameState.clock_text(),
		["Ngủ (lưu game)", "Chưa buồn ngủ"],
		["Sang ngày mới: gà hồi Thể trạng (con nào chưa ăn lúa bị đói), trứng trong lò bớt một ngày.", ""])
	if pick == 0:
		leave(true)


func _on_altar() -> void:
	if HomeState.altar_lit_today():
		await _say([["", "Khói nhang còn thơm. Ông nội trong ảnh cười hiền như hồi dắt bạn ra sân đình."]])
		return
	var pick: int = await dialog.choose("", "Bàn thờ ông nội. Thắp một nén nhang hông?", ["Thắp nhang", "Để lát"])
	if pick != 0:
		return
	HomeState.light_altar()
	Audio.sfx(&"temple_bell", -8.0)
	await _say([
		["", "Bạn thắp nén nhang, khấn nhỏ: «Ông ơi, phù hộ cho con với chiến kê của con nghen.»"],
		["Ông nội", "Gà hay là gà biết đọc đối thủ…"],
	])


func _on_table() -> void:
	var p: int = GameState.period()
	if p == GameState.Period.TRUA or p == GameState.Period.TOI:
		await _say([["", "Mâm cơm có cá kho tộ với canh chua bông điên điển. Thơm muốn xỉu!"]])
	else:
		await _say([["", "Bàn ăn dọn sạch rồi, chỉ còn bình trà nguội với dĩa chuối."]])


func _on_feed_all() -> void:
	var stock: int = GameState.item_count(&"lua")
	var hungry: Array[int] = []
	for i in range(GameState.chickens.size()):
		if not bool(GameState.chickens[i]["fed_today"]):
			hungry.append(i)
	if hungry.is_empty():
		await _say([["", "Cả đàn ăn no hết rồi, đứng mổ chơi mấy hột lúa rớt."]])
		return
	if stock <= 0:
		await _say([["", "Bao lúa trống trơn! Ghé tiệm Cô Ba mua lúa (15.000đ một bao) nghen."]])
		return
	var fed: PackedStringArray = []
	for i in hungry:
		if GameState.item_count(&"lua") <= 0:
			break
		if GameState.feed(i, &"lua"):
			fed.append(String(GameState.chickens[i]["name"]))
			if i < _chickens.size():
				(_chickens[i] as Node).call("play_once", &"eat")
	Audio.sfx(&"harvest", -8.0, 1.4)
	var left: int = hungry.size() - fed.size()
	var line: String = "Bốc lúa rải ra chén thóc: %s ăn ngon lành, Thể trạng về 100%%." % ", ".join(fed)
	if left > 0:
		line += " Còn %d con chưa có lúa – mua thêm nghen." % left
	await _say([["", line + " (Còn %d bao lúa.)" % GameState.item_count(&"lua")]])


func _on_post() -> void:
	var options: Array = []
	for i in range(GameState.chickens.size()):
		var c: Dictionary = GameState.chickens[i]
		options.append("%s · Lv%d · %d%% · đã tập %d/%d" % [c["name"], int(c["level"]), int(round(float(c["condition"]))),
			int(c["trained_today"]), GameState.TRAIN_PER_DAY])
	options.append("Thôi")
	var pick: int = await dialog.choose("", "Quây tập nền cát: dắt con nào vô tập (1 giờ)?", options)
	if pick < 0 or pick >= GameState.chickens.size():
		return
	var lv: int = int(GameState.chickens[pick]["level"])
	var r: Dictionary = GameState.train(pick)
	if not bool(r["ok"]):
		await _say([["", GameState.last_error]])
		return
	if pick < _chickens.size():
		(_chickens[pick] as Node).call("play_once", &"happy")
	var line: String = "%s chạy vòng quây cát, nhảy đá bao rơm tới tấp: +%d EXP." % [GameState.chickens[pick]["name"], int(r["exp"])]
	if int(GameState.chickens[pick]["level"]) > lv:
		line += " LÊN CẤP %d!" % int(GameState.chickens[pick]["level"])
		Audio.sfx(&"levelup", -4.0)
	await _say([["", line]])
	if bool(r["day_over"]):
		await _say([["", "Khuya lơ khuya lắc rồi (%s)! Mẹ kêu đi ngủ kìa." % GameState.time_text()]])
		leave(false, true)
