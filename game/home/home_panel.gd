extends CanvasLayer

## Khung bảng điều khiển bàn phím dùng chung cho nhà (chuồng gà, lò ấp, bàn học).
## Bố cục theo khung tham chiếu 1152×648 (kích thước viewport gốc của dự án, stretch canvas_items/expand), canh giữa
## màn hình qua CanvasLayer.offset: khung gỗ sẫm (UISkin "dark") y 12..636, chữ pixel ×2 (UISkin.FS_BODY), ba cột y 82..562:
##   trái x 28..388 (hình/thông tin – lớp con vẽ trong _draw_left), giữa x 400..716 (_draw_mid),
##   phải x 728..1124: danh sách lựa chọn (cuộn), mô tả lựa chọn đang chọn; dòng thông báo + dải phím ở đáy khung.
## Khi cần nhập tên, DialogBox (lớp 50) phủ lên đáy khung.
## Phím: W/S (↑/↓) chọn · A/D (←/→) đổi gà khi được phép · E/J/Space/Enter xác nhận · Esc/Backspace quay lại.
## Test/headless: press(&"up"|&"down"|&"left"|&"right"|&"confirm"|&"cancel") bơm phím; current_id() đọc lựa chọn.
## Lựa chọn: Dictionary {id: StringName, label: String, detail: String, disabled: bool, why: String}.
## pick() trả về chỉ số; −1 = Esc, −2 = A (trái), −3 = D (phải).

signal _picked(index: int)

const Audio := preload("res://game/audio/audio_director.gd")
const REF_SIZE: Vector2 = Vector2(1152, 648)
const FRAME: Rect2 = Rect2(16, 12, 1120, 624)
const LEFT: Rect2 = Rect2(28, 82, 360, 480)
const MID: Rect2 = Rect2(400, 82, 316, 480)
const RIGHT: Rect2 = Rect2(728, 82, 396, 480)
const ROW_H: int = 32
const MAX_ROWS: int = 8
## Cỡ chữ (font pixel phóng nguyên lần – UISkin): thân ×2, tiêu đề ×3, chú thích ×1 đậm.
const FS: int = UISkin.FS_BODY
const FS_TITLE: int = UISkin.FS_BIG
const FS_SMALL: int = UISkin.FS_SMALL
const BG: Color = Color(0.11, 0.07, 0.05, 0.96)
const BORDER: Color = Color(0.95, 0.75, 0.3)
const TEXT: Color = Color(0.94, 0.91, 0.84)
const DIM: Color = Color(0.62, 0.6, 0.55)
const GOLD: Color = Color(1.0, 0.84, 0.35)
const GOOD: Color = Color(0.55, 0.92, 0.5)
const BAD: Color = Color(1.0, 0.5, 0.42)
const PANEL2: Color = Color(0.17, 0.11, 0.08, 1.0)

## Hộp thoại chung (để nhường phím khi đang mở) – có thể null.
var dialog: DialogBox
var title: String = ""
var subtitle: String = ""
## Đang chạy hoạt ảnh (ăn, nở trứng…): chặn phím.
var busy_anim: bool = false

var _options: Array = []
var _index: int = 0
var _top: int = 0
var _list_title: String = ""
var _hover: Callable = Callable()
var _allow_lr: bool = false
var _waiting: bool = false
var _msg: String = ""
var _msg_color: Color = TEXT
var _msg_time: float = 0.0
var _board: Control
var _font: Font
var _bold: Font
var _time: float = 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = DialogBox.make_font(false)
	_bold = DialogBox.make_font(true)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.position = Vector2(-2000, -2000)
	dim.size = Vector2(6000, 6000)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_board = Control.new()
	_board.size = REF_SIZE
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.draw.connect(_draw_board)
	UISkin.pixel(_board)
	add_child(_board)


func _process(delta: float) -> void:
	_time += delta
	# canh giữa khung tham chiếu trong viewport (rộng hơn 16:9 thì dư hai bên, cao hơn thì dư trên dưới)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	offset = ((vp - REF_SIZE) * 0.5).floor()
	if _msg_time > 0.0:
		_msg_time -= delta
		if _msg_time <= 0.0:
			_msg = ""
	_board.queue_redraw()


# =================================================================== lựa chọn

static func opt(id: StringName, label: String, detail: String = "", disabled: bool = false, why: String = "") -> Dictionary:
	return {"id": id, "label": label, "detail": detail, "disabled": disabled, "why": why}


## Chờ người chơi chọn trong danh sách. hover(index) được gọi mỗi khi đổi dòng (cả lúc mở).
func pick(list_title: String, options: Array, hover: Callable = Callable(), allow_lr: bool = false, start: int = 0) -> int:
	_list_title = list_title
	_options = options
	_hover = hover
	_allow_lr = allow_lr
	_index = clampi(start, 0, maxi(options.size() - 1, 0))
	_top = 0
	_ensure_visible()
	_call_hover()
	_waiting = true
	var r: int = await _picked
	_waiting = false
	return r


func is_waiting() -> bool:
	return _waiting


func current_id() -> StringName:
	if _index < 0 or _index >= _options.size():
		return &""
	return StringName(_options[_index].get("id", &""))


func option_ids() -> Array:
	var out: Array = []
	for o in _options:
		out.append(StringName(o.get("id", &"")))
	return out


func current_option() -> Dictionary:
	return _options[_index] if _index >= 0 and _index < _options.size() else {}


func message(text: String, color: Color = TEXT, seconds: float = 4.0) -> void:
	_msg = text
	_msg_color = color
	_msg_time = seconds


func last_message() -> String:
	return _msg


func press(action: StringName) -> void:
	if not _waiting or busy_anim:
		return
	match action:
		&"up", &"down":
			if _options.is_empty():
				return
			_index = posmod(_index + (-1 if action == &"up" else 1), _options.size())
			_ensure_visible()
			_call_hover()
			Audio.sfx(&"ui_move", -10.0)
		&"confirm":
			if _options.is_empty():
				return
			var o: Dictionary = _options[_index]
			if bool(o.get("disabled", false)):
				message(String(o.get("why", "Chưa làm được.")), BAD)
				Audio.sfx(&"ui_move", -6.0, 0.7)
				return
			Audio.sfx(&"ui_confirm", -6.0)
			_picked.emit(_index)
		&"cancel":
			Audio.sfx(&"ui_move", -8.0, 0.85)
			_picked.emit(-1)
		&"left", &"right":
			if _allow_lr:
				Audio.sfx(&"ui_move", -8.0)
				_picked.emit(-2 if action == &"left" else -3)


func _ensure_visible() -> void:
	if _index < _top:
		_top = _index
	elif _index >= _top + MAX_ROWS:
		_top = _index - MAX_ROWS + 1
	_top = clampi(_top, 0, maxi(_options.size() - MAX_ROWS, 0))


func _call_hover() -> void:
	if _hover.is_valid():
		_hover.call(_index)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	if dialog != null and is_instance_valid(dialog) and dialog.is_open():
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var action: StringName = &""
	match key.physical_keycode:
		KEY_W, KEY_UP:
			action = &"up"
		KEY_S, KEY_DOWN:
			action = &"down"
		KEY_A, KEY_LEFT:
			action = &"left"
		KEY_D, KEY_RIGHT:
			action = &"right"
		KEY_E, KEY_J, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			action = &"confirm"
		KEY_ESCAPE, KEY_BACKSPACE:
			action = &"cancel"
	if action == &"":
		return
	get_viewport().set_input_as_handled()
	press(action)


## Chờ vài giây (hoạt ảnh) – chặn phím trong lúc chờ.
func hold(seconds: float) -> void:
	busy_anim = true
	await get_tree().create_timer(seconds).timeout
	busy_anim = false


# =================================================================== vẽ

func _draw_board() -> void:
	var b: Control = _board
	b.draw_rect(Rect2(FRAME.position + Vector2(6, 8), FRAME.size), Color(0, 0, 0, 0.35))
	UISkin.draw_panel(b, FRAME, &"dark")
	text(Vector2(FRAME.position.x + 22, FRAME.position.y + 50), title, FS_TITLE, GOLD, true)
	if subtitle != "":
		text(Vector2(FRAME.end.x - 22, FRAME.position.y + 46), subtitle, FS, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT, 760)
	b.draw_rect(Rect2(FRAME.position.x + 16, FRAME.position.y + 62, FRAME.size.x - 32, 2), Color(BORDER, 0.35))
	_draw_left(b)
	_draw_mid(b)
	_draw_list(b)


func _draw_left(_b: Control) -> void:
	pass


func _draw_mid(_b: Control) -> void:
	pass


func _draw_list(b: Control) -> void:
	var x: float = RIGHT.position.x
	var y: float = RIGHT.position.y
	b.draw_rect(Rect2(RIGHT.position + Vector2(0, -4), Vector2(RIGHT.size.x, 4 + ROW_H * MAX_ROWS + 52)), PANEL2)
	text(Vector2(x + 12, y + 30), _list_title, FS, GOLD, true, HORIZONTAL_ALIGNMENT_LEFT, RIGHT.size.x - 80)
	y += 44
	var shown: int = mini(_options.size(), MAX_ROWS)
	if _top > 0:
		text(Vector2(x + RIGHT.size.x - 12, y - 16), "▲ %d" % _top, FS_SMALL, DIM, true, HORIZONTAL_ALIGNMENT_RIGHT, 80)
	for r in range(shown):
		var i: int = _top + r
		var o: Dictionary = _options[i]
		var selected: bool = i == _index and _waiting
		var ry: float = y + float(r * ROW_H)
		if selected:
			var pulse: float = 0.18 + 0.06 * sin(_time * 5.0)
			b.draw_rect(Rect2(x + 4, ry, RIGHT.size.x - 8, ROW_H - 2), Color(1.0, 0.8, 0.3, pulse))
			text(Vector2(x + 10, ry + 23), "▶", FS, GOLD, true)
		var col: Color = DIM if bool(o.get("disabled", false)) else (GOLD if selected else TEXT)
		text(Vector2(x + 34, ry + 23), String(o.get("label", "")), FS, col, false, HORIZONTAL_ALIGNMENT_LEFT,
			RIGHT.size.x - 42)
	var below: int = _options.size() - (_top + shown)
	if below > 0:
		text(Vector2(x + RIGHT.size.x - 12, y + float(shown * ROW_H) + 4), "▼ %d" % below, FS_SMALL, DIM, true,
			HORIZONTAL_ALIGNMENT_RIGHT, 80)
	# mô tả lựa chọn đang chọn
	var detail_y: float = RIGHT.position.y + ROW_H * MAX_ROWS + 58
	var o2: Dictionary = current_option()
	var detail: String = String(o2.get("detail", ""))
	if bool(o2.get("disabled", false)) and String(o2.get("why", "")) != "":
		detail = String(o2.get("why", "")) + ("\n" + detail if detail != "" else "")
	if detail != "":
		wrap_text(Vector2(x + 6, detail_y), detail, RIGHT.size.x - 12, FS, Color(0.78, 0.92, 0.76), 4)
	# thông báo (dải ngang đáy khung, trên dải phím)
	if _msg != "":
		# dải thông báo nổi (như toast) – che tạm phần đáy các cột trong vài giây
		var a: float = clampf(_msg_time / 0.5, 0.0, 1.0)
		var strip := Rect2(LEFT.position.x - 4, FRAME.end.y - 124, FRAME.end.x - LEFT.position.x - 20, 80)
		b.draw_rect(strip, Color(0.07, 0.045, 0.03, 0.96 * a))
		b.draw_rect(strip, Color(BORDER, 0.6 * a), false, 2.0)
		wrap_text(Vector2(strip.position.x + 14, strip.position.y + 8), _msg, strip.size.x - 28, FS,
			Color(_msg_color, a), 2, true)
	UISkin.draw_key_hints(b, FRAME.end - Vector2(14, 12), UISkin.hint_pairs(_hint_text()))


func _hint_text() -> String:
	var s: String = "[W/S] chọn   [E] xác nhận   [Esc] quay lại"
	if _allow_lr:
		s = "[A/D] đổi gà   " + s
	return s


# =================================================================== tiện ích vẽ (cho lớp con)

## Vẽ chữ một dòng. Canh trái/giữa: pos.x là mép trái khung rộng width; canh phải: pos.x là mép phải.
func text(pos: Vector2, s: String, size: int, color: Color, bold: bool = false,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	# Canh phải: pos.x là MÉP PHẢI của chữ (khung rộng width tính ngược sang trái).
	if align == HORIZONTAL_ALIGNMENT_RIGHT and width > 0.0:
		pos.x -= width
	_board.draw_string(_bold if bold else _font, pos.round(), s, align, width, size, color)


## Chữ nhiều dòng: pos = góc trên trái của dòng đầu (đường chân = pos.y + ascent).
func wrap_text(pos: Vector2, s: String, width: float, size: int, color: Color, max_lines: int = -1, bold: bool = false) -> void:
	var f: Font = _bold if bold else _font
	_board.draw_multiline_string(f, (pos + Vector2(0, f.get_ascent(size))).round(), s, HORIZONTAL_ALIGNMENT_LEFT, width,
		size, max_lines, color)


## Thanh ngang có chữ: ratio 0..1.
func bar(rect: Rect2, ratio: float, color: Color, label: String = "") -> void:
	_board.draw_rect(rect, Color(0.05, 0.03, 0.02))
	_board.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2((rect.size.x - 4) * clampf(ratio, 0.0, 1.0),
		rect.size.y - 4)), color)
	_board.draw_rect(rect, Color(BORDER, 0.5), false, 1.0)
	if label != "":
		var size: int = FS if rect.size.y >= 24.0 else FS_SMALL
		var base := Vector2(rect.position.x + 8, UISkin.baseline_in(rect.position.y, rect.size.y, size))
		UISkin.draw_string_crisp(_board, _font, base, label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, size, Color.WHITE, 4,
			Color(0, 0, 0, 0.9))


func board() -> Control:
	return _board


func font(bold: bool = false) -> Font:
	return _bold if bold else _font
