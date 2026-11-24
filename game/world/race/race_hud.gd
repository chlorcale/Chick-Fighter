extends CanvasLayer

## HUD của màn đua xe đường quê (toạ độ màn hình, chữ độ phân giải cao như các HUD khác của game):
## thanh tiến trình hai xe + cổng ấp, hạng, thời gian, quãng đường còn lại, đồng hồ tốc độ, thanh bốc ga 3 nấc,
## bảng hướng dẫn đầu trận, đếm ngược 3-2-1, thông báo nhanh, băng rôn về đích, bảng kết quả,
## chữ trên bảng cổng ấp và bong bóng thoại của đối thủ (bám theo vị trí trong màn chơi).
## race_game.gd gọi các hàm set_*/show_*/toast; HUD không tự đọc trạng thái trò chơi.

const GOLD := Color(1.0, 0.85, 0.4)
const PANEL := Color(0.1, 0.07, 0.05, 0.82)
const BORDER := Color(0.95, 0.75, 0.3)
const PLAYER_COLOR := Color(1.0, 0.85, 0.2)

var rider_name: String = ""
var rider_color: Color = Color.RED
var player_progress: float = 0.0
var rival_progress: float = 0.0
var place: int = 1
var kmh: float = 0.0
var nitro: float = 0.0
var boosting: bool = false
var drafting: bool = false
var left_m: float = 0.0
var race_time: float = 0.0
var show_race: bool = false
var gate_rect: Rect2 = Rect2()
var gate_visible: bool = false

var _root: Control
var _font: Font
var _font_bold: Font
var _place: Label
var _time: Label
var _left: Label
var _speed: Label
var _speed_unit: Label
var _nitro_label: Label
var _help: Control
var _count: Label
var _toast: Label
var _toast_time: float = 0.0
var _banner: Label
var _gate: Label
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
	# Góc trên trái (chữ pixel phóng nguyên lần): hạng ×4 · giờ ×2 · km/h ×4 · vạch tốc độ · BỐC GA ×2 · thanh bốc ga.
	_place = _label(UISkin.FS_HUGE, GOLD, true)
	_place.position = Vector2(24, 6)
	_time = _label(UISkin.FS_BODY, Color(0.95, 0.93, 0.88), false)
	_time.position = Vector2(26, 72)
	_left = _label(UISkin.FS_BODY, Color(0.95, 0.93, 0.88), true)
	_left.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_left.offset_left = -260.0
	_left.offset_right = -24.0
	_left.offset_top = 16.0
	_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Đồng hồ tốc độ + bốc ga ở góc trên-trái (trên nền trời, không che xe chạy ở làn dưới).
	_speed = _label(UISkin.FS_HUGE, Color.WHITE, true)
	_speed.position = Vector2(28, 100)
	_speed_unit = _label(UISkin.FS_BODY, Color(0.9, 0.9, 0.9), false)
	_speed_unit.position = Vector2(112, 126)
	_speed_unit.text = "km/h"
	_nitro_label = _label(UISkin.FS_BODY, Color(1.0, 0.75, 0.35), true)
	_nitro_label.position = Vector2(30, 174)
	# Dải phím góc dưới phải (phím gỗ UISkin, chữ ×1 đậm).
	_help = Control.new()
	_help.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.draw.connect(func() -> void:
		UISkin.draw_key_hints(_help, _help.size - Vector2(12, 10), [["W/S", "Đổi làn"], ["D", "Ga"], ["A", "Thắng"],
			["J/E", "Bốc ga"], ["Esc", "Bỏ cuộc"]]))
	_help.resized.connect(_help.queue_redraw)
	_root.add_child(_help)
	_count = _center_label(110, GOLD, 0.36)
	_toast = _center_label(UISkin.FS_BIG, Color(1.0, 0.95, 0.5), 0.24)
	_banner = _center_label(66, GOLD, 0.42)
	_gate = _label(UISkin.FS_BODY, Color(1.0, 0.92, 0.5), true)
	_gate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gate.text = "ẤP BÌNH KÊ"
	_bubble = _label(UISkin.FS_BODY, UISkin.INK, false)
	_bubble.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_bubble.add_theme_stylebox_override("normal", UISkin.panel_style(&"tooltip", 2.0))
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for node in [_count, _toast, _banner, _gate, _bubble]:
		(node as Control).visible = false
	_build_intro()
	_build_result()
	_set_race_visible(false)


func _label(font_size: int, color: Color, bold: bool) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", _font_bold if bold else _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UISkin.label_shadow(label, 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


## Nhãn canh giữa ngang màn hình, mép trên ở tỉ lệ y_ratio chiều cao.
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


func _panel(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", UISkin.panel_style(&"dark", 12.0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	return panel


func _build_intro() -> void:
	_intro = _panel(700.0)
	_intro.offset_top = -190.0
	_intro.offset_bottom = 190.0
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
	_result = _panel(560.0)
	_result.offset_top = -190.0
	_result.offset_bottom = 190.0
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
	box.add_child(_result_body)
	_result_hint = Label.new()
	_result_hint.add_theme_font_override("font", _font_bold)
	_result_hint.add_theme_font_size_override("font_size", UISkin.FS_BODY)
	_result_hint.add_theme_color_override("font_color", Color(0.75, 1.0, 0.7))
	_result_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_hint)
	_result.visible = false


func _set_race_visible(on: bool) -> void:
	show_race = on
	for node in [_place, _time, _left, _speed, _speed_unit, _nitro_label, _help]:
		(node as Control).visible = on


# ------------------------------------------------------------------ API cho race_game

func set_rider(display_name: String, color: Color) -> void:
	rider_name = display_name
	rider_color = color


func show_intro(title: String, text: String) -> void:
	_intro_title.text = title
	_intro_text.text = text
	_intro.visible = true


func hide_intro() -> void:
	_intro.visible = false
	_set_race_visible(true)


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


func show_banner(text: String, color: Color = GOLD) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = text != ""


## Bong bóng thoại trên đầu đối thủ (screen_pos = điểm trên đầu, toạ độ màn hình).
func bubble(text: String, seconds: float = 1.6) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_time = seconds


func place_bubble(screen_pos: Vector2) -> void:
	_bubble.reset_size()
	_bubble.position = (screen_pos - Vector2(_bubble.size.x * 0.5, _bubble.size.y + 4.0)).round()


func set_gate(screen_rect: Rect2, on: bool) -> void:
	gate_rect = screen_rect
	gate_visible = on
	_gate.visible = on and not _result.visible
	if on:
		_gate.position = screen_rect.position.round()
		_gate.size = screen_rect.size.round()
		_gate.add_theme_font_size_override("font_size", maxi(10, int(screen_rect.size.y * 0.62)))


func show_result(title: String, title_color: Color, body: String, hint: String) -> void:
	_result_title.text = title
	_result_title.add_theme_color_override("font_color", title_color)
	_result_body.text = body
	_result_hint.text = hint
	_result.visible = true
	_banner.visible = false
	_toast.visible = false
	_gate.visible = false
	_bubble.visible = false


func is_result_visible() -> bool:
	return _result.visible


func _process(delta: float) -> void:
	_clock += delta
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0
	if _bubble_time > 0.0:
		_bubble_time -= delta
		_bubble.visible = _bubble_time > 0.0
	if show_race:
		_place.text = "HẠNG %d/2" % place
		_place.add_theme_color_override("font_color", GOLD if place == 1 else Color(1.0, 0.55, 0.45))
		_time.text = "⏱ %s" % format_time(race_time)
		_left.text = "Còn %d m" % int(ceilf(maxf(left_m, 0.0))) if left_m > 0.0 else "VỀ ĐÍCH!"
		_speed.text = "%d" % int(roundf(kmh))
		var charged: bool = nitro >= 1.0 / 3.0 - 0.001
		_nitro_label.text = ("BỐC GA!!" if boosting else "BỐC GA [J]") + ("  · núp gió" if drafting else "")
		_nitro_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if charged or boosting else Color(0.8, 0.7, 0.55))
	_root.queue_redraw()


static func format_time(seconds: float) -> String:
	var s: float = maxf(seconds, 0.0)
	return "%02d:%04.1f" % [int(s / 60.0), fmod(s, 60.0)]


# ------------------------------------------------------------------ vẽ thanh tiến trình, bốc ga

func _draw_hud() -> void:
	if not show_race:
		return
	var screen: Vector2 = _root.size
	# Thanh tiến trình trên cùng.
	var w: float = clampf(screen.x * 0.46, 360.0, 640.0)
	var box := Rect2(roundf((screen.x - w) * 0.5), 14.0, w, 50.0)
	_root.draw_rect(box, PANEL)
	_root.draw_rect(box, BORDER, false, 2.0)
	var x0: float = box.position.x + 26.0
	var x1: float = box.end.x - 40.0
	var y: float = box.position.y + 30.0
	_root.draw_rect(Rect2(x0, y - 2.0, x1 - x0, 4.0), Color(0.55, 0.5, 0.42))
	for k in range(1, 10):
		var tx: float = roundf(lerpf(x0, x1, float(k) / 10.0))
		_root.draw_rect(Rect2(tx, y - 4.0, 1.0, 8.0), Color(0.55, 0.5, 0.42))
	# Cổng ấp ở cuối thanh.
	_root.draw_rect(Rect2(x1 + 6.0, y - 14.0, 3.0, 18.0), Color(0.75, 0.3, 0.2))
	_root.draw_rect(Rect2(x1 + 22.0, y - 14.0, 3.0, 18.0), Color(0.75, 0.3, 0.2))
	_root.draw_rect(Rect2(x1 + 3.0, y - 18.0, 25.0, 5.0), Color(0.85, 0.15, 0.1))
	_root.draw_string(_font_bold, Vector2(box.position.x + 8.0, box.position.y + 16.0), "XUẤT PHÁT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.75, 0.6))
	_root.draw_string(_font_bold, Vector2(box.end.x - 86.0, box.position.y + 16.0), "CỔNG ẤP", HORIZONTAL_ALIGNMENT_RIGHT, 80, 11, Color(0.8, 0.75, 0.6))
	_marker(Vector2(lerpf(x0, x1, clampf(rival_progress, 0.0, 1.0)), y - 1.0), rider_color, rider_name.substr(rider_name.rfind(" ") + 1, 1))
	_marker(Vector2(lerpf(x0, x1, clampf(player_progress, 0.0, 1.0)), y + 1.0), PLAYER_COLOR, "B")
	# Thanh bốc ga 3 nấc.
	var nb := Rect2(28.0, 212.0, 210.0, 18.0)
	_root.draw_rect(nb.grow(3.0), PANEL)
	for k in range(3):
		var seg := Rect2(nb.position.x + float(k) * 70.0 + 1.0, nb.position.y, 68.0, nb.size.y)
		_root.draw_rect(seg, Color(0.25, 0.18, 0.12))
		var fill: float = clampf(nitro * 3.0 - float(k), 0.0, 1.0)
		if fill > 0.0:
			var c: Color = Color(1.0, 0.55, 0.15) if fill >= 1.0 else Color(0.75, 0.45, 0.2)
			if boosting or (fill >= 1.0 and int(_clock * 4.0) % 2 == 0):
				c = c.lightened(0.25)
			_root.draw_rect(Rect2(seg.position, Vector2(seg.size.x * fill, seg.size.y)), c)
		_root.draw_rect(seg, Color(0.95, 0.75, 0.3, 0.8), false, 1.0)
	# Vạch tốc độ dưới số km/h.
	var sb := Rect2(28.0, 162.0, 210.0, 6.0)
	_root.draw_rect(sb, Color(0.2, 0.15, 0.1, 0.8))
	_root.draw_rect(Rect2(sb.position, Vector2(sb.size.x * clampf(kmh / 90.0, 0.0, 1.0), sb.size.y)),
		Color(1.0, 0.45, 0.2) if boosting else Color(0.6, 0.9, 0.5))


func _marker(pos: Vector2, color: Color, letter: String) -> void:
	_root.draw_circle(pos, 11.0, Color.BLACK)
	_root.draw_circle(pos, 9.0, color)
	_root.draw_string(_font_bold, (pos + Vector2(-6.0, 5.0)).round(), letter, HORIZONTAL_ALIGNMENT_CENTER, 12, UISkin.FS_SMALL, Color.BLACK)
