extends CanvasLayer

## Sổ tay (phím V): cuốn sổ bìa da, ba trang
##   Hướng dẫn – cách chơi (điều khiển, nhịp một ngày, chuồng gà, mua sắm, giải đấu, gọi tay trong, bản đồ)
##   Thành tựu – cây thành tựu kiểu "advancement": năm nhánh, nút khung + đường nối cha → con; chưa mở thì đen/mờ,
##               bí mật chỉ hiện "?" tới khi mở. W/A/S/D chọn nút, Tab / 1–5 đổi nhánh.
##   Sổ tay    – gà trong chuồng, đối thủ đã hạ, vài con số.
## Chỉ mở được khi đang khám phá (không trong hội thoại/trận/mini-game); mở thì người chơi đứng yên.
## V hoặc Esc để đóng; Q/E đổi trang. main.gd tạo một lần, gán world + dialog (+ blocked: Callable → true = cấm mở).
## Dùng: const Guidebook := preload("res://game/ui/guidebook.gd")

const StoryLife := preload("res://game/story/story_life.gd")
const Activities := preload("res://game/world/activities.gd")
const Audio := preload("res://game/audio/audio_director.gd")

const TABS: Array[String] = ["Hướng dẫn", "Thành tựu", "Sổ tay"]
const TAB_ICONS: Array[StringName] = [&"book", &"trophy", &"chicken"]
const COL: float = 100.0      ## khoảng cách cột cây (px)
const ROW: float = 60.0       ## khoảng cách hàng cây (px)
const NODE: float = 44.0      ## cỡ khung nút (22 px thiết kế × 2)
const LIST_ROW: float = 40.0

## Mục hướng dẫn: [tiêu đề, biểu tượng, đoạn văn…]. Đoạn bắt đầu bằng "KEY:" là dòng phím: "KEY:J|Mổ nhanh".
const GUIDE: Array = [
	["Đi lại & khám phá", &"you", [
		"KEY:W A S D|Đi bộ (hoặc phím mũi tên)",
		"KEY:E|Nói chuyện, vô nhà, vô tiệm, đọc bảng",
		"KEY:E|Cạnh chiếc Dream: lên xe / xuống xe",
		"KEY:E|Ở bến: lái vỏ lãi (W tới, S lùi, A/D bẻ lái)",
		"KEY:+ −|Phóng to / thu nhỏ",
		"KEY:M|Bản đồ cả xã, có đường vàng chỉ lối",
		"KEY:N|Bật / tắt bản đồ nhỏ ở góc",
		"KEY:V|Mở sổ tay này",
	]],
	["Đá gà", &"fight", [
		"KEY:A D|Tới / lui",
		"KEY:W S|Nhảy / cúi",
		"KEY:J|Mổ nhanh (đòn nhẹ)",
		"KEY:K|Tát cánh (đòn vừa)",
		"KEY:L|Đá mạnh (đòn nặng)",
		"KEY:H|Tuyệt chiêu khi đủ nộ – bấm liên tục cho tới tấp",
		"KEY:Giữ lùi|Đỡ đòn: đứng đỡ đòn trên, cúi đỡ đòn thấp",
		"KEY:U I · O|Chọn thẻ bài · tung thẻ (tốn Card Gauge)",
		"KEY:Esc|Tạm dừng, coi bảng chiêu",
		"Nối J → J → K → L thành chuỗi. Ba hiệp, thắng hai là ăn.",
	]],
	["Một ngày ở Bình Kê", &"sun", ["@clock", "@school", "@jobs"]],
	["Chuồng gà & trứng", &"coop", ["@home", "@eggs", "@kho_ga"]],
	["Chợ & mua sắm", &"market", ["@shop",
		"Chợ Bình Kê có bốn sạp: gà giống, trứng, thức ăn, đồ chiến. Tiệm Cô Ba bán đồ cho gà. Lão Gà Khô vừa cười vừa khóc, mua Khô Gà giá cao."]],
	["Giải đấu", &"trophy", [
		"Ao Làng (3 vòng) → Liên tỉnh miền Tây (5 vòng) → Olympic Đá Gà (5 vòng, Hell Mode: đối thủ vô trận với 4 Card Gauge, hiệp 60 giây).",
		"@league",
		"Trước trận có màn chuẩn bị: đổi gà, thay vũ khí và 5 ô trang bị, coi sức mạnh hai bên."]],
	["Gọi tay trong", &"siren", ["@police"]],
	["Bản đồ & đường đi", &"map", ["@map"]],
]

var world: Node
var dialog: DialogBox
## Callable() -> bool: true = đang bận (main._busy, đua xe…) → không mở.
var blocked: Callable
var open: bool = false
var tab: int = 0
var guide_index: int = 0
var branch_index: int = 0
var selected: StringName = &""

var _bg: ColorRect
var _canvas: Control
var _time: float = 0.0
var _froze_player: bool = false
var _froze_interactions: bool = false
var _pan: Vector2 = Vector2.ZERO
var _layout: Dictionary = {} # id → Vector2 (toạ độ cây, px, gốc ở nút gốc)
var _layout_branch: StringName = &""
var _sfx: Sfx


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx = Sfx.new()
	add_child(_sfx)
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.03, 0.02, 0.6)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_book)
	UISkin.pixel(_canvas)
	add_child(_canvas)
	visible = false


# ================================================================== mở / đóng

## Có được mở sổ lúc này không (chỉ khi đang khám phá tự do).
func can_open() -> bool:
	if world == null or not is_instance_valid(world) or not world.is_inside_tree() or not bool(world.get("visible")):
		return false
	if dialog != null and dialog.is_open():
		return false
	if blocked.is_valid() and bool(blocked.call()):
		return false
	if not bool(world.get("interactions_enabled")):
		return false
	var player: Node = world.get("player")
	if player == null or not bool(player.get("can_move")):
		return false
	var overlay: Node = world.get("map_overlay")
	if overlay != null and bool(overlay.get("open")):
		return false
	return true


func open_book() -> bool:
	if open or not can_open():
		return false
	open = true
	visible = true
	var player: Node = world.get("player")
	player.set("can_move", false)
	_froze_player = true
	world.set("interactions_enabled", false)
	_froze_interactions = true
	_select_branch(branch_index)
	_sfx.play(&"card", -8.0, 0.8)
	Achievements.unlock(&"secret_book")
	_canvas.queue_redraw()
	return true


func close_book() -> void:
	if not open:
		return
	open = false
	visible = false
	if world != null and is_instance_valid(world):
		if _froze_interactions:
			world.set("interactions_enabled", true)
		var player: Node = world.get("player")
		if _froze_player and player != null:
			player.set("can_move", true)
	_froze_player = false
	_froze_interactions = false
	_sfx.play(&"select", -8.0, 0.8)


func _unhandled_input(event: InputEvent) -> void:
	if open or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_V and open_book():
		get_viewport().set_input_as_handled()


## Khi mở: nuốt mọi phím (World/bản đồ không nhận).
func _input(event: InputEvent) -> void:
	if not open or not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_V, KEY_ESCAPE:
			close_book()
		KEY_Q:
			set_tab(posmod(tab - 1, TABS.size()))
		KEY_E:
			set_tab(posmod(tab + 1, TABS.size()))
		KEY_TAB:
			if tab == 1:
				_select_branch(posmod(branch_index + 1, Achievements.BRANCH_ORDER.size()))
				_sfx.play(&"select", -8.0)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			var n: int = key.physical_keycode - KEY_1
			if tab == 1 and n < Achievements.BRANCH_ORDER.size():
				_select_branch(n)
				_sfx.play(&"select", -8.0)
		KEY_W, KEY_UP:
			_nav(Vector2i(0, -1))
		KEY_S, KEY_DOWN:
			_nav(Vector2i(0, 1))
		KEY_A, KEY_LEFT:
			_nav(Vector2i(-1, 0))
		KEY_D, KEY_RIGHT:
			_nav(Vector2i(1, 0))
	_canvas.queue_redraw()


func set_tab(t: int) -> void:
	tab = clampi(t, 0, TABS.size() - 1)
	_sfx.play(&"select", -6.0)
	_canvas.queue_redraw()


func _nav(dir: Vector2i) -> void:
	match tab:
		0:
			if dir.y != 0:
				guide_index = posmod(guide_index + dir.y, GUIDE.size())
				_sfx.play(&"select", -8.0)
		1:
			move_selection(dir)


# ================================================================== cây thành tựu

func _select_branch(i: int) -> void:
	branch_index = clampi(i, 0, Achievements.BRANCH_ORDER.size() - 1)
	var b: StringName = Achievements.BRANCH_ORDER[branch_index]
	_build_layout(b)
	var nodes: Array[Dictionary] = Achievements.in_branch(b)
	selected = nodes[0]["id"] if not nodes.is_empty() else &""
	_pan = _layout.get(selected, Vector2.ZERO)


## Bố cục cây gọn: lá xếp hàng liên tiếp theo thứ tự duyệt, cha nằm giữa con đầu và con cuối; cột = độ sâu.
func _build_layout(branch: StringName) -> void:
	_layout = {}
	_layout_branch = branch
	var next_row: Array[float] = [0.0]
	for a in Achievements.in_branch(branch):
		if a["parent"] == &"":
			_place(a["id"], 0, next_row)


func _place(id: StringName, depth: int, next_row: Array[float]) -> float:
	var kids: Array[StringName] = Achievements.children(id)
	var row: float
	if kids.is_empty():
		row = next_row[0]
		next_row[0] += 1.0
	else:
		var first: float = INF
		var last: float = -INF
		for k in kids:
			var r: float = _place(k, depth + 1, next_row)
			first = minf(first, r)
			last = maxf(last, r)
		row = (first + last) * 0.5
	_layout[id] = Vector2(depth * COL, row * ROW)
	return row


## Chọn nút gần nhất theo hướng (ưu tiên đúng hướng, rồi gần).
func move_selection(dir: Vector2i) -> bool:
	if not _layout.has(selected):
		return false
	var from: Vector2 = _layout[selected]
	var best: StringName = &""
	var best_score: float = INF
	for id in _layout:
		if id == selected:
			continue
		var d: Vector2 = _layout[id] - from
		var along: float = d.x * dir.x + d.y * dir.y
		if along <= 1.0:
			continue
		var across: float = absf(d.x * dir.y) + absf(d.y * dir.x)
		var score: float = along + across * 2.5
		if score < best_score:
			best_score = score
			best = id
	if best == &"":
		return false
	selected = best
	_sfx.play(&"select", -10.0)
	return true


## "unlocked" | "locked" (lộ diện, chưa mở) | "hidden" (cha chưa mở) – bí mật chưa mở luôn là "secret".
func node_state(id: StringName) -> String:
	var v: int = Achievements.visibility(id)
	if v == 2:
		return "unlocked"
	if Achievements.is_secret(id):
		return "secret"
	return "locked" if v == 1 else "hidden"


## Tiêu đề / mô tả hiển thị theo trạng thái (test đọc).
func node_text(id: StringName) -> Array[String]:
	var a: Dictionary = Achievements.info(id)
	match node_state(id):
		"unlocked":
			return [String(a["title"]), String(a["desc"])]
		"secret":
			return ["?", "?"]
		"locked":
			return [String(a["title"]), "???"]
	return ["???", "???"]


func _process(delta: float) -> void:
	if not open:
		return
	_time += delta
	if tab == 1 and _layout.has(selected):
		_pan = _pan.lerp(_layout[selected], minf(1.0, delta * 10.0))
	_canvas.queue_redraw()


# ================================================================== vẽ

func _book_rect() -> Rect2:
	var view: Vector2 = _canvas.size
	return Rect2(Vector2(36, 62), Vector2(view.x - 72, view.y - 80)).abs()


func _page_rect() -> Rect2:
	return _book_rect().grow(-30.0)


func _draw_book() -> void:
	if not open:
		return
	var book: Rect2 = _book_rect()
	# thẻ trang (vẽ trước bìa: thẻ chưa chọn nằm sau)
	for i in range(TABS.size()):
		if i != tab:
			_draw_tab(i, book)
	UISkin.draw_panel(_canvas, book, &"book")
	_draw_tab(tab, book)
	var page: Rect2 = _page_rect()
	match tab:
		0:
			_draw_guide(page)
		1:
			_draw_achievements(page)
		2:
			_draw_notes(page)
	var hint: String = "[Q/E] đổi trang · [V/Esc] đóng"
	match tab:
		0:
			hint = "[W/S] chọn mục · " + hint
		1:
			hint = "[W/A/S/D] chọn · [Tab] đổi nhánh · " + hint
	UISkin.draw_text(_canvas, Vector2(book.position.x, book.end.y + 14), hint, UISkin.FS_SMALL, UISkin.CREAM, true,
		HORIZONTAL_ALIGNMENT_CENTER, book.size.x, 4, UISkin.SHADOW)


func _draw_tab(i: int, book: Rect2) -> void:
	var on: bool = i == tab
	var w: float = 196.0
	var r := Rect2(book.position.x + 40.0 + i * (w + 8.0), book.position.y - (40.0 if on else 34.0), w, 48.0)
	UISkin.draw_panel(_canvas, r, &"tab_on" if on else &"tab_off")
	UISkin.draw_icon(_canvas, TAB_ICONS[i], r.position + Vector2(26, 22), 1.0)
	UISkin.draw_text(_canvas, Vector2(r.position.x + 44, r.position.y + 29), TABS[i], UISkin.FS_SMALL,
		UISkin.INK if on else UISkin.INK_SOFT, true)


func _draw_list_row(rect: Rect2, icon: StringName, text: String, on: bool, extra: String = "") -> void:
	if on:
		_canvas.draw_rect(rect, Color(0.86, 0.72, 0.5, 0.55))
		var nudge: float = 2.0 if fmod(_time, 0.6) < 0.3 else 0.0
		_canvas.draw_texture(UISkin.texture("cursor"), Vector2(rect.position.x - 24.0 + nudge, rect.position.y + 11.0).round())
	UISkin.draw_icon(_canvas, icon, rect.position + Vector2(18, rect.size.y * 0.5), 1.0)
	UISkin.draw_text(_canvas, Vector2(rect.position.x + 38, UISkin.baseline_in(rect.position.y, rect.size.y, UISkin.FS_BODY)),
		text, UISkin.FS_BODY, UISkin.INK_RED if on else UISkin.INK)
	if extra != "":
		UISkin.draw_text(_canvas, Vector2(rect.position.x, UISkin.baseline_in(rect.position.y, rect.size.y, UISkin.FS_SMALL, true)),
			extra, UISkin.FS_SMALL, UISkin.INK_SOFT, true, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 6.0)


func _gutter(x: float, page: Rect2) -> void:
	_canvas.draw_rect(Rect2(x - 2, page.position.y, 2, page.size.y), Color(0.82, 0.68, 0.46))
	_canvas.draw_rect(Rect2(x, page.position.y, 2, page.size.y), Color(1.0, 0.96, 0.86))


# ------------------------------------------------------------------ Hướng dẫn

func _draw_guide(page: Rect2) -> void:
	var list_w: float = 300.0
	var y: float = page.position.y + 4.0
	for i in range(GUIDE.size()):
		_draw_list_row(Rect2(page.position.x + 26.0, y, list_w - 34.0, LIST_ROW), GUIDE[i][1], String(GUIDE[i][0]), i == guide_index)
		y += LIST_ROW + 4.0
	var gx: float = page.position.x + list_w + 6.0
	_gutter(gx, page)
	var x: float = gx + 24.0
	var w: float = page.end.x - x - 8.0
	var entry: Array = GUIDE[guide_index]
	UISkin.draw_icon(_canvas, entry[1], Vector2(x + 24, page.position.y + 22), 2.0)
	UISkin.draw_text(_canvas, Vector2(x + 58, page.position.y + 34), String(entry[0]), UISkin.FS_BODY, UISkin.INK, true)
	y = page.position.y + 64.0
	var body_font: Font = UISkin.font()
	for para in entry[2]:
		var text: String = String(para)
		if text.begins_with("@"):
			text = String(StoryLife.TUTORIALS.get(text.substr(1), ""))
		if text.begins_with("KEY:"):
			var parts: PackedStringArray = text.substr(4).split("|")
			# phím bàn phím: ô sáng, chữ mực ×2
			var cap_w: float = maxf(UISkin.text_size(parts[0], UISkin.FS_BODY).x + 24.0, 40.0)
			var cap := Rect2(x, y, cap_w, 36.0)
			UISkin.draw_panel(_canvas, cap, &"slot")
			_canvas.draw_rect(Rect2(cap.position.x + 2.0, cap.end.y - 4.0, cap.size.x - 4.0, 2.0), Color(0.82, 0.68, 0.46))
			UISkin.draw_text(_canvas, Vector2(cap.position.x, UISkin.baseline_in(cap.position.y - 2.0, cap.size.y, UISkin.FS_BODY)),
				parts[0], UISkin.FS_BODY, UISkin.INK, false, HORIZONTAL_ALIGNMENT_CENTER, cap.size.x)
			var tx: float = x + maxf(cap_w, 112.0) + 14.0
			UISkin.draw_text(_canvas, Vector2(tx, UISkin.baseline_in(y, 36.0, UISkin.FS_BODY)), parts[1] if parts.size() > 1 else "",
				UISkin.FS_BODY, UISkin.INK)
			y += 40.0
			continue
		if text == "":
			continue
		var lines: int = _wrapped_lines(text, UISkin.FS_BODY, w)
		_canvas.draw_multiline_string(body_font, Vector2(x, y + body_font.get_ascent(UISkin.FS_BODY)).round(), text,
			HORIZONTAL_ALIGNMENT_LEFT, w, UISkin.FS_BODY, -1, UISkin.INK)
		y += lines * body_font.get_height(UISkin.FS_BODY) + 10.0


func _wrapped_lines(text: String, size: int, width: float) -> int:
	var tp := TextParagraph.new()
	tp.add_string(text, UISkin.font(), size)
	tp.width = width
	return maxi(tp.get_line_count(), 1)


# ------------------------------------------------------------------ Thành tựu

func _draw_achievements(page: Rect2) -> void:
	var list_w: float = 236.0
	var y: float = page.position.y + 4.0
	for i in range(Achievements.BRANCH_ORDER.size()):
		var b: StringName = Achievements.BRANCH_ORDER[i]
		var nodes: Array[Dictionary] = Achievements.in_branch(b)
		var done: int = 0
		for a in nodes:
			if Achievements.is_unlocked(a["id"]):
				done += 1
		_draw_list_row(Rect2(page.position.x + 26.0, y, list_w - 30.0, LIST_ROW), Achievements.BRANCHES[b]["icon"],
			String(Achievements.BRANCHES[b]["name"]), i == branch_index, "%d/%d" % [done, nodes.size()])
		y += LIST_ROW + 4.0
	# tổng
	UISkin.draw_text(_canvas, Vector2(page.position.x + 26.0, y + 26.0), "Đã mở %d/%d" % [Achievements.count_unlocked(),
		Achievements.total()], UISkin.FS_SMALL, UISkin.INK_SOFT, true)
	var gx: float = page.position.x + list_w + 6.0
	_gutter(gx, page)
	var info_h: float = 118.0
	var area := Rect2(gx + 12.0, page.position.y, page.end.x - gx - 12.0, page.size.y - info_h - 10.0)
	if _layout_branch != Achievements.BRANCH_ORDER[branch_index]:
		_build_layout(Achievements.BRANCH_ORDER[branch_index])
	_draw_tree(area)
	_draw_info(Rect2(area.position.x, area.end.y + 8.0, area.size.x, info_h))


func _tree_origin(area: Rect2) -> Vector2:
	# Cây cuộn theo nút đang chọn: nút chọn nằm trong vùng giữa (giữ khoảng cách mép).
	var center: Vector2 = area.get_center()
	var o: Vector2 = center - _pan
	# Cây nhỏ hơn khung: canh trái-giữa cho đẹp.
	var maxx: float = 0.0
	var maxy: float = 0.0
	for id in _layout:
		maxx = maxf(maxx, _layout[id].x)
		maxy = maxf(maxy, _layout[id].y)
	if maxx + NODE + 60.0 <= area.size.x:
		o.x = area.position.x + 40.0 + NODE * 0.5
	if maxy + NODE + 30.0 <= area.size.y:
		o.y = area.position.y + (area.size.y - maxy) * 0.5
	return o.round()


func _draw_tree(area: Rect2) -> void:
	var o: Vector2 = _tree_origin(area)
	var clip := area.grow(-2.0)
	# đường nối (cha → con, gấp khúc kiểu Minecraft)
	for id in _layout:
		var a: Dictionary = Achievements.info(id)
		var parent: StringName = a.get("parent", &"")
		if parent == &"" or not _layout.has(parent):
			continue
		var p: Vector2 = o + _layout[parent]
		var c: Vector2 = o + _layout[id]
		var lit: bool = Achievements.is_unlocked(id)
		var mid: float = p.x + COL * 0.5
		var pts := PackedVector2Array([p + Vector2(NODE * 0.5, 0), Vector2(mid, p.y), Vector2(mid, c.y), c - Vector2(NODE * 0.5, 0)])
		_clipped_polyline(pts, clip, Color(0.24, 0.15, 0.09), 6.0)
		_clipped_polyline(pts, clip, Color(0.96, 0.82, 0.42) if lit else Color(0.66, 0.56, 0.42), 2.0)
	for id in _layout:
		var c: Vector2 = o + _layout[id]
		var r := Rect2(c - Vector2(NODE, NODE) * 0.5, Vector2(NODE, NODE))
		if not clip.encloses(r):
			continue
		_draw_node(id, r)


func _clipped_polyline(pts: PackedVector2Array, clip: Rect2, color: Color, width: float) -> void:
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		# đoạn thẳng đứng / ngang: kẹp vào khung
		var ra := Rect2(a, Vector2.ZERO).expand(b).grow(width * 0.5)
		var cut: Rect2 = ra.intersection(clip)
		if cut.size.x > 0.0 and cut.size.y > 0.0:
			_canvas.draw_rect(cut, color)


func _draw_node(id: StringName, r: Rect2) -> void:
	var a: Dictionary = Achievements.info(id)
	var state: String = node_state(id)
	var frame: String = "node_locked"
	var modulate := Color.WHITE
	if state == "unlocked":
		frame = "node_secret" if Achievements.is_secret(id) else ("node_goal" if a.get("frame", &"") == &"goal" else "node_open")
	elif state == "hidden" or (state == "secret" and Achievements.visibility(id) == 0):
		modulate = Color(0.55, 0.55, 0.6)
	_canvas.draw_texture_rect(UISkin.texture(frame), r, false, modulate)
	match state:
		"unlocked":
			UISkin.draw_icon(_canvas, a["icon"], r.get_center(), 1.0)
		"locked":
			UISkin.draw_icon(_canvas, a["icon"], r.get_center(), 1.0, Color(0, 0, 0, 0.85))
		"hidden":
			UISkin.draw_icon(_canvas, a["icon"], r.get_center(), 1.0, Color(0, 0, 0, 0.55))
		"secret":
			UISkin.draw_text(_canvas, Vector2(r.position.x, UISkin.baseline_in(r.position.y, r.size.y, UISkin.FS_BODY, true)), "?",
				UISkin.FS_BODY, Color(0.75, 0.55, 0.85), true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if id == selected:
		var blink: float = 0.6 + 0.4 * sin(_time * 6.0)
		_canvas.draw_rect(r.grow(4.0), Color(1.0, 0.85, 0.3, blink), false, 2.0)
		_canvas.draw_rect(r.grow(6.0), Color(0.24, 0.15, 0.09, blink), false, 2.0)


func _draw_info(r: Rect2) -> void:
	UISkin.draw_panel(_canvas, r, &"tooltip")
	if selected == &"":
		return
	var a: Dictionary = Achievements.info(selected)
	var texts: Array[String] = node_text(selected)
	var state: String = node_state(selected)
	var x: float = r.position.x + 16.0
	var w: float = r.size.x - 32.0
	UISkin.draw_text(_canvas, Vector2(x, r.position.y + 36.0), texts[0], UISkin.FS_BODY,
		UISkin.INK_RED if state == "unlocked" else UISkin.INK, true)
	var branch: Dictionary = Achievements.BRANCHES.get(a.get("branch", &""), {})
	UISkin.draw_text(_canvas, Vector2(x, r.position.y + 30.0), String(branch.get("name", "")), UISkin.FS_SMALL, UISkin.INK_SOFT, true,
		HORIZONTAL_ALIGNMENT_RIGHT, w)
	UISkin.draw_text(_canvas, Vector2(x, r.position.y + 70.0), texts[1], UISkin.FS_BODY, UISkin.INK)
	var foot: String = ""
	match state:
		"unlocked":
			foot = "Mở khóa: " + Achievements.when(selected)
		"locked":
			foot = "Gợi ý: " + String(a.get("hint", ""))
		"hidden":
			foot = "Mở các thành tựu trước nó đã."
		"secret":
			foot = "Bí mật – tự khám phá nghen!" if Achievements.visibility(selected) >= 1 else ""
	var prog: Vector2i = Achievements.progress(selected)
	if state != "unlocked" and state != "secret" and prog.y > 1:
		foot += "   Tiến độ: %s / %s" % [_num(prog.x), _num(prog.y)]
		var bar := Rect2(r.end.x - 196.0, r.end.y - 26.0, 176.0, 10.0)
		_canvas.draw_rect(bar.grow(2.0), UISkin.INK)
		_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(prog.x) / float(prog.y), bar.size.y)), Color(0.45, 0.72, 0.3))
	UISkin.draw_text(_canvas, Vector2(x, r.end.y - 16.0), foot, UISkin.FS_SMALL, UISkin.INK_SOFT, true)


func _num(n: int) -> String:
	return GameState.money_text(n).trim_suffix("đ") if n >= 10000 else str(n)


# ------------------------------------------------------------------ Sổ tay

func _draw_notes(page: Rect2) -> void:
	var half: float = page.size.x * 0.5
	var x: float = page.position.x + 20.0
	var y: float = page.position.y + 30.0
	UISkin.draw_text(_canvas, Vector2(x, y), "Chuồng gà của %s" % GameState.player_name, UISkin.FS_BODY, UISkin.INK, true)
	y += 18.0
	if GameState.chickens.is_empty():
		UISkin.draw_text(_canvas, Vector2(x, y + 30.0), "Chưa có con gà nào. Ra sân đình gặp Chú Tư đi!", UISkin.FS_BODY, UISkin.INK_SOFT)
	for i in range(mini(GameState.chickens.size(), 8)):
		var c: Dictionary = GameState.chickens[i]
		var row := Rect2(x, y + 6.0, half - 40.0, 48.0)
		if i == GameState.active:
			_canvas.draw_rect(row, Color(0.86, 0.72, 0.5, 0.45))
		UISkin.draw_icon(_canvas, &"chicken", row.position + Vector2(18, 24), 1.0)
		UISkin.draw_text(_canvas, Vector2(row.position.x + 40, row.position.y + 24), "%s · Lv%d" % [String(c.get("name", "?")), int(c.get("level", 1))],
			UISkin.FS_BODY, UISkin.INK)
		var muts: int = (c.get("mutations", []) as Array).size()
		var sub: String = "%s · Thể trạng %d%%%s" % [GameState.Breeds.display_name(int(c.get("breed", 0))), int(c.get("condition", 100)),
			(" · %d đột biến" % muts) if muts > 0 else ""]
		UISkin.draw_text(_canvas, Vector2(row.position.x + 40, row.position.y + 42), sub, UISkin.FS_SMALL, UISkin.INK_SOFT, true)
		y += 52.0
	var gx: float = page.position.x + half
	_gutter(gx, page)
	x = gx + 24.0
	y = page.position.y + 30.0
	UISkin.draw_text(_canvas, Vector2(x, y), "Đối thủ đã hạ", UISkin.FS_BODY, UISkin.INK, true)
	var beaten: Array = Achievements.set_items(&"beaten")
	y += 8.0
	if beaten.is_empty():
		UISkin.draw_text(_canvas, Vector2(x, y + 34.0), "Chưa hạ ai hết. Ra sới thử sức coi!", UISkin.FS_BODY, UISkin.INK_SOFT)
		y += 54.0
	var col: int = 0
	for i in range(mini(beaten.size(), 16)):
		var bx: float = x + (half * 0.5 - 10.0) * float(col)
		UISkin.draw_icon(_canvas, &"medal", Vector2(bx + 10, y + 22), 0.75)
		UISkin.draw_text(_canvas, Vector2(bx + 26, y + 28), String(beaten[i]), UISkin.FS_SMALL, UISkin.INK, true)
		col += 1
		if col == 2:
			col = 0
			y += 24.0
	if col != 0:
		y += 24.0
	y += 30.0
	UISkin.draw_text(_canvas, Vector2(x, y), "Mấy con số", UISkin.FS_BODY, UISkin.INK, true)
	var stats: Array[String] = [
		"Ngày thứ %d ở xã Bình Kê" % GameState.day,
		"Trong túi: %s" % GameState.money_text(GameState.money),
		"Trận thắng: %d" % Achievements.counter(&"wins"),
		"Đua xe đường làng thắng: %d" % Activities.race_wins,
		"Thành tựu: %d / %d" % [Achievements.count_unlocked(), Achievements.total()],
	]
	for s in stats:
		y += 30.0
		UISkin.draw_text(_canvas, Vector2(x, y), "· " + s, UISkin.FS_BODY, UISkin.INK)
