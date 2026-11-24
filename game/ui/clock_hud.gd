extends CanvasLayer

## Đồng hồ khám phá (góc trên phải) – biển gỗ treo dây (UISkin "sign"): thứ trong tuần, ngày thứ mấy, giờ, buổi +
## biểu tượng mặt trời / hoàng hôn / trăng pixel (GDD 3.3, 3.6). main.gd tạo một lần và gán `world`; tự ẩn khi không có World hoặc World bị ẩn (trận đấu,
## đua xe, cảnh hồi ức, màn hình tiêu đề). Cập nhật qua GameState.add_listener + vẽ lại định kỳ.
## Dùng: const ClockHud := preload("res://game/ui/clock_hud.gd")

const SIZE: Vector2 = Vector2(262, 84)
const MARGIN: Vector2 = Vector2(12, 10)
const PERIOD_COLORS: Array[Color] = [
	Color(1.0, 0.86, 0.35),   # Sáng
	Color(1.0, 0.95, 0.55),   # Trưa
	Color(1.0, 0.68, 0.3),    # Chiều
	Color(0.85, 0.75, 1.0),   # Tối
	Color(0.75, 0.85, 1.0),   # Khuya
]

var world: Node
## Cho phép main ẩn hẳn (vd. đoạn phim) dù World đang hiện.
var suppressed: bool = false

var _panel: Control
var _font: Font
var _font_bold: Font
var _redraw_timer: float = 0.0


func _ready() -> void:
	layer = 11
	_font = DialogBox.make_font(false)
	_font_bold = DialogBox.make_font(true)
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -SIZE.x - MARGIN.x
	_panel.offset_right = -MARGIN.x
	_panel.offset_top = MARGIN.y
	_panel.offset_bottom = MARGIN.y + SIZE.y
	_panel.draw.connect(_draw_panel)
	UISkin.pixel(_panel)
	add_child(_panel)
	GameState.add_listener(_on_time_changed)
	_update_visibility()


func _exit_tree() -> void:
	GameState.remove_listener(_on_time_changed)


func _on_time_changed() -> void:
	if _panel != null:
		_panel.queue_redraw()


func _process(delta: float) -> void:
	_update_visibility()
	_redraw_timer -= delta
	if _redraw_timer <= 0.0 and visible:
		_redraw_timer = 0.5
		_panel.queue_redraw()


func _update_visibility() -> void:
	var want: bool = not suppressed and world != null and is_instance_valid(world) and world.is_inside_tree() \
		and bool(world.get("visible"))
	if visible != want:
		visible = want


## Văn bản đang hiển thị (cho test): ["Thứ 2 · Ngày 1", "07:00 · Sáng"].
func lines() -> PackedStringArray:
	return PackedStringArray(["%s · Ngày %d" % [GameState.weekday_name(), GameState.day],
		"%s · %s" % [GameState.time_text(), GameState.period_name()]])


func _draw_panel() -> void:
	# Biển gỗ treo hai sợi dây: biểu tượng buổi (mặt trời / hoàng hôn / trăng) + thứ, ngày, giờ.
	var rect := Rect2(Vector2.ZERO, SIZE)
	for x in [26.0, SIZE.x - 28.0]:
		_panel.draw_rect(Rect2(x, -MARGIN.y - 2.0, 2.0, MARGIN.y + 8.0), Color(0.36, 0.24, 0.12))
		_panel.draw_rect(Rect2(x + 2.0, -MARGIN.y - 2.0, 2.0, MARGIN.y + 8.0), Color(0.22, 0.13, 0.07))
	UISkin.draw_panel(_panel, rect, &"sign")
	var p: int = GameState.period()
	var tint: Color = PERIOD_COLORS[clampi(p, 0, PERIOD_COLORS.size() - 1)]
	var icon: StringName = &"sun"
	if p == GameState.Period.CHIEU:
		icon = &"sunset"
	elif p > GameState.Period.CHIEU:
		icon = &"moon"
	var icon_center := Vector2(34, SIZE.y * 0.5)
	_panel.draw_circle(icon_center, 20.0, Color(0.16, 0.09, 0.05, 0.55))
	UISkin.draw_icon(_panel, icon, icon_center, 1.5)
	var text: PackedStringArray = lines()
	var x: float = 64.0
	UISkin.draw_text(_panel, Vector2(x, 36), text[0], UISkin.FS_BODY, UISkin.CREAM, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 4,
		UISkin.SHADOW)
	UISkin.draw_text(_panel, Vector2(x, 66), text[1], UISkin.FS_BODY, tint, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 4, UISkin.SHADOW)
