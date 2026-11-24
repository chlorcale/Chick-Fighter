extends CanvasLayer

## HUD màn tẩu thoát (toạ độ màn hình, chữ nét cao như race_hud.gd): thanh tiến trình hai chặng (chạy → bơi → nhà)
## với dấu người chơi / công an / căn nhà, thước "KHOẢNG CÁCH CÔNG AN", thanh SỨC, đồng hồ đếm ngược, chuỗi té
## liên tiếp, đồng hồ thăng bằng khi qua cầu khỉ, viền đèn xanh-đỏ nhấp nháy khi công an áp sát, bảng hướng dẫn,
## đếm ngược 3-2-1, thông báo nhanh, băng rôn, bong bóng thoại bám theo nhân vật, bảng kết quả.
## escape_game.gd gán các biến + gọi show_*/toast; HUD không tự đọc trạng thái trò chơi.

const GOLD := Color(1.0, 0.85, 0.4)
const PANEL := Color(0.1, 0.07, 0.05, 0.82)
const BORDER := Color(0.95, 0.75, 0.3)
const HERO_COLOR := Color(1.0, 0.85, 0.2)
const POLICE_COLOR := Color(0.45, 0.62, 0.3)
const STAGE_SPLIT: float = 0.6        # phần thanh tiến trình dành cho chặng chạy

var show_play: bool = false
var stage: int = 1
var progress: float = 0.0             # 0..1 trong chặng hiện tại
var police_progress: float = 0.0
var gap_ratio: float = 1.0            # 0 = bị tóm, 1 = xa nhất
var stamina: float = 1.0
var sprinting: bool = false
var time_left: float = 120.0
var streak: int = 0
var balance_on: bool = false
var balance: float = 0.0
var flash: float = 0.0
var hero_letter: String = "T"

var _root: Control
var _font: Font
var _font_bold: Font
var _time: Label
var _gap_label: Label
var _stamina_label: Label
var _streak_label: Label
var _help: Control
var _help_text: String = ""
var _count: Label
var _toast: Label
var _toast_time: float = 0.0
var _banner: Label
var _banner_time: float = 0.0
var _bubble: Label
var _bubble_time: float = 0.0
var _intro: PanelContainer
var _intro_title: Label
var _intro_text: Label
var _result: PanelContainer
var _result_title: Label
var _result_body: Label
var _result_hint: Label
var _clock: float = 0.0


func _ready() -> void:
	layer = 25
	_font = DialogBox.make_font(false)
	_font_bold = DialogBox.make_font(true)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_hud)
	UISkin.pixel(_root)
	add_child(_root)
	_time = _label(UISkin.FS_BIG, Color(0.95, 0.93, 0.88), true)
	_time.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_time.offset_left = -220.0
	_time.offset_right = -24.0
	_time.offset_top = 16.0
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gap_label = _label(UISkin.FS_SMALL, Color(0.95, 0.93, 0.88), true)
	_gap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gap_label.text = "KHOẢNG CÁCH CÔNG AN"
	_stamina_label = _label(UISkin.FS_BODY, Color(0.75, 1.0, 0.65), true)
	_stamina_label.position = Vector2(28, 4)
	_streak_label = _label(UISkin.FS_BODY, Color(1.0, 0.7, 0.55), true)
	_streak_label.position = Vector2(28, 68)
	# Dải nhắc phím góc dưới phải (khung gỗ sẫm, chữ ×1 đậm) – nội dung do escape_game đặt qua set_help().
	_help = Control.new()
	_help.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.draw.connect(func() -> void:
		if _help_text != "":
			UISkin.draw_key_hints(_help, _help.size - Vector2(12, 10), [["", _help_text]]))
	_help.resized.connect(_help.queue_redraw)
	_root.add_child(_help)
	_count = _center_label(110, GOLD, 0.36)
	_toast = _center_label(UISkin.FS_BIG, Color(1.0, 0.95, 0.5), 0.26)
	_banner = _center_label(66, GOLD, 0.42)
	_bubble = _label(UISkin.FS_BODY, UISkin.INK, false)
	_bubble.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_bubble.add_theme_stylebox_override("normal", UISkin.panel_style(&"tooltip", 2.0))
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for node in [_count, _toast, _banner, _bubble]:
		(node as Control).visible = false
	_build_intro()
	_build_result()
	set_play_visible(false)


func _label(font_size: int, color: Color, bold: bool) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", _font_bold if bold else _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UISkin.label_shadow(label, 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


func _center_label(font_size: int, color: Color, y_ratio: float) -> Label:
	var label := _label(font_size, color, true)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = y_ratio
	label.anchor_bottom = y_ratio
	label.offset_top = -float(font_size) * 0.8
	label.offset_bottom = float(font_size) * 0.8
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UISkin.label_shadow(label, 8)
	return label


func _panel(width: float, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", UISkin.panel_style(&"dark", 12.0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	return panel


func _build_intro() -> void:
	_intro = _panel(760.0, 470.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_intro.add_child(box)
	_intro_title = Label.new()
	_intro_title.add_theme_font_override("font", _font_bold)
	_intro_title.add_theme_font_size_override("font_size", UISkin.FS_BIG)
	_intro_title.add_theme_color_override("font_color", GOLD)
	_intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_intro_title)
	_intro_text = Label.new()
	_intro_text.add_theme_font_override("font", _font)
	_intro_text.add_theme_font_size_override("font_size", UISkin.FS_BODY)
	_intro_text.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_intro_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_intro_text)
	_intro.visible = false


func _build_result() -> void:
	_result = _panel(600.0, 380.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_result.add_child(box)
	_result_title = Label.new()
	_result_title.add_theme_font_override("font", _font_bold)
	_result_title.add_theme_font_size_override("font_size", UISkin.FS_HUGE)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_body = Label.new()
	_result_body.add_theme_font_override("font", _font)
	_result_body.add_theme_font_size_override("font_size", UISkin.FS_BODY)
	_result_body.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_result_body)
	_result_hint = Label.new()
	_result_hint.add_theme_font_override("font", _font_bold)
	_result_hint.add_theme_font_size_override("font_size", UISkin.FS_BODY)
	_result_hint.add_theme_color_override("font_color", Color(0.75, 1.0, 0.7))
	_result_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_hint)
	_result.visible = false


func set_play_visible(on: bool) -> void:
	show_play = on
	for node in [_time, _gap_label, _stamina_label, _streak_label, _help]:
		(node as Control).visible = on


# ------------------------------------------------------------------ API cho escape_game

func show_intro(title: String, text: String) -> void:
	_intro_title.text = title
	_intro_text.text = text
	_intro.visible = true


func hide_intro() -> void:
	_intro.visible = false
	set_play_visible(true)


func is_intro_visible() -> bool:
	return _intro.visible


func set_help(text: String) -> void:
	_help_text = text
	_help.queue_redraw()


func set_countdown(text: String, color: Color = GOLD) -> void:
	_count.text = text
	_count.add_theme_color_override("font_color", color)
	_count.visible = text != ""


func countdown_text() -> String:
	return _count.text if _count.visible else ""


func toast(text: String, color: Color = Color(1.0, 0.95, 0.5), seconds: float = 1.1) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast_time = seconds


func show_banner(text: String, color: Color = GOLD, seconds: float = 1.6) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = text != ""
	_banner_time = seconds


func banner_text() -> String:
	return _banner.text if _banner.visible else ""


## Bong bóng thoại (screen_pos = điểm trên đầu người nói, toạ độ màn hình).
func bubble(text: String, seconds: float = 1.6) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_time = seconds


func place_bubble(screen_pos: Vector2) -> void:
	_bubble.reset_size()
	var view: Vector2 = _root.size
	var bs: Vector2 = _bubble.size
	var pos: Vector2 = (screen_pos - Vector2(bs.x * 0.5, bs.y + 4.0)).round()
	pos.x = clampf(pos.x, 8.0, maxf(view.x - bs.x - 8.0, 8.0))
	pos.y = clampf(pos.y, 110.0, maxf(view.y - 80.0, 110.0))
	_bubble.position = pos


func show_result(title: String, title_color: Color, body: String, hint: String) -> void:
	_result_title.text = title
	_result_title.add_theme_color_override("font_color", title_color)
	_result_body.text = body
	_result_hint.text = hint
	_result.visible = true
	_banner.visible = false
	_toast.visible = false
	_bubble.visible = false
	_banner_time = 0.0
	_toast_time = 0.0
	_bubble_time = 0.0
	set_play_visible(false)


func hide_result() -> void:
	_result.visible = false


func is_result_visible() -> bool:
	return _result.visible


func _process(delta: float) -> void:
	_clock += delta
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.visible = _banner_time > 0.0
	if _bubble_time > 0.0:
		_bubble_time -= delta
		_bubble.visible = _bubble_time > 0.0
	if show_play:
		var t: float = maxf(time_left, 0.0)
		_time.text = "⏱ %d:%02d" % [int(t / 60.0), int(t) % 60]
		_time.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if t < 15.0 and int(_clock * 3.0) % 2 == 0 else Color(0.95, 0.93, 0.88))
		_stamina_label.text = ("CHẠY HẾT SỨC!" if sprinting else "SỨC") if stage == 1 else "SỨC BƠI"
		var dots: String = ""
		for k in range(3):
			dots += "● " if k < streak else "○ "
		_streak_label.text = "Té liên tiếp: " + dots.strip_edges()
		_streak_label.visible = show_play and streak > 0
		var vw: float = _root.size.x
		_gap_label.position = Vector2(roundf(vw * 0.5 - 160.0), 79.0)
		_gap_label.size = Vector2(320, 17)
	_root.queue_redraw()


# ------------------------------------------------------------------ vẽ

func _draw_hud() -> void:
	var screen: Vector2 = _root.size
	_draw_flash(screen)
	if not show_play:
		return
	# Thanh tiến trình: [chặng chạy | chặng bơi] → nhà.
	var w: float = clampf(screen.x * 0.5, 380.0, 680.0)
	var box := Rect2(roundf((screen.x - w) * 0.5), 12.0, w, 64.0)
	_root.draw_rect(box, PANEL)
	_root.draw_rect(box, BORDER, false, 2.0)
	var x0: float = box.position.x + 24.0
	var x1: float = box.end.x - 44.0
	var y: float = box.position.y + 28.0
	var xs: float = roundf(lerpf(x0, x1, STAGE_SPLIT))
	_root.draw_rect(Rect2(x0, y - 2.0, xs - x0, 4.0), Color(0.62, 0.5, 0.36))
	_root.draw_rect(Rect2(xs, y - 2.0, x1 - xs, 4.0), Color(0.35, 0.58, 0.72))
	_root.draw_rect(Rect2(xs - 1.0, y - 8.0, 2.0, 16.0), Color(0.9, 0.9, 0.85))
	_root.draw_string(_font_bold, Vector2(x0, box.position.y + 15.0), "CHẠY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.78, 0.6))
	_root.draw_string(_font_bold, Vector2(xs + 6.0, box.position.y + 15.0), "BƠI", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.85, 0.95))
	_root.draw_string(_font_bold, Vector2(x1 - 30.0, box.position.y + 15.0), "NHÀ", HORIZONTAL_ALIGNMENT_RIGHT, 60, 11, Color(0.95, 0.85, 0.6))
	_house_icon(Vector2(x1 + 20.0, y + 2.0))
	var to_bar := func(p: float) -> float:
		var q: float = clampf(p, 0.0, 1.0)
		return lerpf(x0, xs, q) if stage == 1 else lerpf(xs, x1, q)
	_police_marker(Vector2(roundf(float(to_bar.call(police_progress))), y + 1.0))
	_marker(Vector2(roundf(float(to_bar.call(progress))), y - 1.0), HERO_COLOR, hero_letter)
	# Thước khoảng cách công an.
	var gw: float = 320.0
	var gb := Rect2(roundf(screen.x * 0.5 - gw * 0.5), 102.0, gw, 14.0)
	_root.draw_rect(gb.grow(3.0), PANEL)
	_root.draw_rect(gb, Color(0.22, 0.16, 0.12))
	var r: float = clampf(gap_ratio, 0.0, 1.0)
	var c: Color = Color(0.45, 0.85, 0.4).lerp(Color(1.0, 0.85, 0.25), clampf((0.6 - r) / 0.3, 0.0, 1.0))
	if r < 0.3:
		c = Color(1.0, 0.3, 0.2) if int(_clock * 6.0) % 2 == 0 else Color(0.95, 0.55, 0.2)
	_root.draw_rect(Rect2(gb.position, Vector2(roundf(gb.size.x * r), gb.size.y)), c)
	for k in range(1, 4):
		_root.draw_rect(Rect2(roundf(gb.position.x + gb.size.x * float(k) / 4.0), gb.position.y, 1.0, gb.size.y), Color(0, 0, 0, 0.35))
	_root.draw_rect(gb, Color(0.95, 0.75, 0.3, 0.8), false, 1.0)
	# Thanh sức (chạy nước rút / sải tay bơi).
	var sb := Rect2(28.0, 44.0, 200.0, 14.0)
	_root.draw_rect(sb.grow(3.0), PANEL)
	_root.draw_rect(sb, Color(0.2, 0.16, 0.12))
	var sc: Color = Color(0.55, 0.9, 0.45) if stamina > 0.3 else Color(0.95, 0.6, 0.3)
	if sprinting:
		sc = sc.lightened(0.25)
	_root.draw_rect(Rect2(sb.position, Vector2(roundf(sb.size.x * clampf(stamina, 0.0, 1.0)), sb.size.y)), sc)
	_root.draw_rect(sb, Color(0.95, 0.75, 0.3, 0.8), false, 1.0)
	if balance_on:
		_draw_balance(screen)


func _marker(pos: Vector2, color: Color, letter: String) -> void:
	_root.draw_circle(pos, 11.0, Color.BLACK)
	_root.draw_circle(pos, 9.0, color)
	_root.draw_string(_font_bold, (pos + Vector2(-6.0, 5.0)).round(), letter, HORIZONTAL_ALIGNMENT_CENTER, 12, UISkin.FS_SMALL, Color.BLACK)


## Dấu công an: mũ kê-pi xanh + đèn xanh/đỏ nhấp nháy.
func _police_marker(pos: Vector2) -> void:
	_root.draw_circle(pos, 11.0, Color.BLACK)
	_root.draw_circle(pos, 9.0, POLICE_COLOR)
	_root.draw_rect(Rect2(pos + Vector2(-7, -4), Vector2(14, 4)), Color(0.3, 0.38, 0.2))
	_root.draw_rect(Rect2(pos + Vector2(-8, 0), Vector2(16, 2)), Color(0.12, 0.1, 0.12))
	var blink: bool = int(_clock * 5.0) % 2 == 0
	_root.draw_rect(Rect2(pos + Vector2(-5, 4), Vector2(4, 3)), Color(1.0, 0.25, 0.2) if blink else Color(0.4, 0.15, 0.15))
	_root.draw_rect(Rect2(pos + Vector2(1, 4), Vector2(4, 3)), Color(0.3, 0.5, 1.0) if not blink else Color(0.15, 0.2, 0.4))


func _house_icon(pos: Vector2) -> void:
	_root.draw_colored_polygon(PackedVector2Array([pos + Vector2(-14, -4), pos + Vector2(14, -4), pos + Vector2(0, -16)]), Color(0.75, 0.55, 0.3))
	_root.draw_rect(Rect2(pos + Vector2(-10, -4), Vector2(20, 13)), Color(0.85, 0.75, 0.55))
	_root.draw_rect(Rect2(pos + Vector2(-3, 1), Vector2(6, 8)), Color(0.35, 0.22, 0.14))
	_root.draw_polyline(PackedVector2Array([pos + Vector2(-14, -4), pos + Vector2(0, -16), pos + Vector2(14, -4)]), Color.BLACK, 2.0)


## Đồng hồ thăng bằng trên cầu khỉ: thanh ngang, vùng an toàn giữa, kim lệch theo balance (−1..1).
func _draw_balance(screen: Vector2) -> void:
	var w: float = 360.0
	var box := Rect2(roundf(screen.x * 0.5 - w * 0.5), roundf(screen.y * 0.86), w, 18.0)
	_root.draw_rect(box.grow(4.0), PANEL)
	_root.draw_rect(box, Color(0.75, 0.25, 0.2))
	var safe := Rect2(box.position.x + w * 0.3, box.position.y, w * 0.4, box.size.y)
	_root.draw_rect(Rect2(box.position.x + w * 0.15, box.position.y, w * 0.7, box.size.y), Color(0.9, 0.7, 0.25))
	_root.draw_rect(safe, Color(0.45, 0.8, 0.4))
	var nx: float = roundf(box.position.x + w * 0.5 + clampf(balance, -1.0, 1.0) * w * 0.5)
	_root.draw_rect(Rect2(nx - 2.0, box.position.y - 6.0, 4.0, box.size.y + 12.0), Color.WHITE)
	_root.draw_rect(Rect2(nx - 2.0, box.position.y - 6.0, 4.0, box.size.y + 12.0), Color.BLACK, false, 1.0)
	var label: String = "THĂNG BẰNG – gõ [A] / [D] để giữ kim ở giữa"
	var tw: float = UISkin.text_size(label, UISkin.FS_BODY).x
	UISkin.draw_text(_root, Vector2(roundf(box.get_center().x - tw * 0.5), box.position.y - 14.0), label, UISkin.FS_BODY,
		Color(1.0, 0.95, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)


## Viền đèn xanh – đỏ nhấp nháy phía sau (bên trái màn hình) khi công an áp sát.
func _draw_flash(screen: Vector2) -> void:
	if flash <= 0.01:
		return
	var red: bool = int(_clock * 4.0) % 2 == 0
	var c: Color = Color(1.0, 0.15, 0.1) if red else Color(0.2, 0.4, 1.0)
	var bands: int = 8
	for k in range(bands):
		var a: float = flash * 0.32 * (1.0 - float(k) / float(bands))
		_root.draw_rect(Rect2(float(k) * 12.0, 0.0, 12.0, screen.y), Color(c.r, c.g, c.b, a))
	# Vệt mỏng trên cùng/dưới cùng để thấy rõ cả khi nền tối.
	_root.draw_rect(Rect2(0, 0, screen.x * 0.25 * flash, 3.0), Color(c.r, c.g, c.b, 0.5 * flash))
	_root.draw_rect(Rect2(0, screen.y - 3.0, screen.x * 0.25 * flash, 3.0), Color(c.r, c.g, c.b, 0.5 * flash))
