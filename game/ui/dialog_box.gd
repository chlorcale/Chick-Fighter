class_name DialogBox
extends CanvasLayer

## Hộp thoại có chân dung NPC, chữ chạy, lựa chọn và ô nhập tên.
## E / Space / Enter / J: hiện hết chữ hoặc sang câu tiếp. W/S (↑/↓) chọn.
## Lựa chọn: danh sách cuộn theo cửa sổ (tối đa MAX_VISIBLE_OPTIONS dòng, có ▲/▼ khi còn nữa),
## hộp thoại nới lên trên khi cần nên lựa chọn đang chọn luôn nằm trong khung.

signal _advanced
signal _chosen(index: int)
signal _named(text: String)

const PORTRAITS: Dictionary = {
	"Chú Tư": "chu_tu", "Tèo": "teo", "MC": "mc", "Cô Ba": "lady", "Út Mập": "crowd_3",
	"Bảy Ghe": "fisher", "Ông nội": "fisher", "Ông từ": "temple_man", "Cô bán vé số": "lottery",
}
const SPEAKER_COLORS: Dictionary = {
	"Mẹ": Color(1.0, 0.7, 0.75), "Chú Tư": Color(1.0, 0.8, 0.35), "Tèo": Color(0.6, 0.9, 1.0),
	"Cô Ba": Color(0.95, 0.75, 1.0), "MC": Color(1.0, 0.55, 0.3), "Ông nội": Color(0.85, 0.85, 0.7),
	"Cô Hạnh": Color(0.7, 0.9, 1.0), "Chú Sáu": Color(0.6, 0.95, 0.75), "Cô Năm": Color(1.0, 0.85, 0.45),
	"Ông từ": Color(1.0, 0.65, 0.45), "Thợ hồ": Color(0.95, 0.7, 0.55), "Cô bán vé số": Color(1.0, 0.6, 0.8),
}
const CHARS_PER_SECOND: float = 55.0
const FONT_DIR: String = "res://game/fonts/"
const MAX_VISIBLE_OPTIONS: int = 5
const OPTION_FONT_SIZE: int = 20
const LONG_OPTION_CHARS: int = 64
const OPTION_COLOR: Color = Color(0.92, 0.9, 0.85)
const OPTION_SELECTED_COLOR: Color = Color(1.0, 0.84, 0.35)

static var _font_cache: Dictionary = {}

var _panel: PanelContainer
var _portrait: TextureRect
var _portrait_box: Control
var _speaker: Label
var _text: RichTextLabel
var _hint: Label
var _name_edit: LineEdit
var _list: VBoxContainer
var _rows: Array[Label] = []
var _more_up: Label
var _more_down: Label
var _detail: Label
var _options: Array = []
var _details: Array = []
var _option_index: int = 0
var _option_top: int = 0
var _mode: int = 0 # 0 ẩn, 1 thoại, 2 lựa chọn, 3 nhập tên
var _body: String = ""
var _sfx: Sfx


## Font của toàn bộ game. Nếu có file .ttf/.otf trong res://game/fonts/ (ví dụ font pixel KVN-97) thì dùng
## font đó cho mọi chữ (không khử răng cưa để giữ nét pixel); ký tự thiếu thì lấy từ font hệ thống.
## Chưa có file thì dùng font hệ thống như cũ. Font pixel không có nét đậm riêng nên bold dùng chung một font.
static func make_font(bold: bool = false) -> Font:
	if _font_cache.has(bold):
		return _font_cache[bold]
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans", "sans-serif"])
	system.font_weight = 700 if bold else 400
	var font: Font = system
	var pixel: FontFile = _load_game_font()
	if pixel != null:
		pixel.fallbacks = [system]
		font = pixel
	_font_cache[bold] = font
	return font


static func has_game_font() -> bool:
	return _load_game_font() != null


static func _load_game_font() -> FontFile:
	if _font_cache.has("pixel"):
		return _font_cache["pixel"]
	var found: FontFile = null
	var dir := DirAccess.open(FONT_DIR)
	if dir != null:
		var names: Array = Array(dir.get_files())
		names.sort()
		for file_name in names:
			var lower: String = String(file_name).to_lower()
			if not (lower.ends_with(".ttf") or lower.ends_with(".otf")):
				continue
			var path: String = FONT_DIR + String(file_name)
			if ResourceLoader.exists(path):
				found = load(path) as FontFile
			if found == null:
				# File vừa thả vào, Godot chưa import: đọc thẳng từ đĩa.
				var raw := FontFile.new()
				if raw.load_dynamic_font(path) == OK:
					found = raw
			if found != null:
				break
	if found != null:
		found.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		found.hinting = TextServer.HINTING_NONE
		found.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_font_cache["pixel"] = found
	return found


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx = Sfx.new()
	add_child(_sfx)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 40.0
	_panel.offset_right = -40.0
	_panel.offset_top = -200.0
	_panel.offset_bottom = -18.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN # nội dung dài thì nới lên trên
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.07, 0.05, 0.94)
	style.border_color = Color(0.95, 0.75, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	style.shadow_size = 8
	style.shadow_color = Color(0, 0, 0, 0.4)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_panel.add_child(row)
	_portrait_box = PanelContainer.new()
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.32, 0.5, 0.36)
	portrait_style.border_color = Color(0.95, 0.75, 0.3)
	portrait_style.set_border_width_all(2)
	_portrait_box.add_theme_stylebox_override("panel", portrait_style)
	_portrait_box.custom_minimum_size = Vector2(120, 150)
	row.add_child(_portrait_box)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_box.add_child(_portrait)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	_speaker = Label.new()
	_speaker.add_theme_font_override("font", make_font(true))
	_speaker.add_theme_font_size_override("font_size", 22)
	box.add_child(_speaker)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_override("normal_font", make_font())
	_text.add_theme_font_override("bold_font", make_font(true))
	_text.add_theme_font_size_override("normal_font_size", 21)
	_text.add_theme_font_size_override("bold_font_size", 21)
	box.add_child(_text)
	_detail = Label.new()
	_detail.add_theme_font_override("font", make_font())
	_detail.add_theme_font_size_override("font_size", 17)
	_detail.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.visible = false
	box.add_child(_detail)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.visible = false
	box.add_child(_list)
	_more_up = _make_option_label(15, Color(0.75, 0.75, 0.75))
	_list.add_child(_more_up)
	_more_down = _make_option_label(15, Color(0.75, 0.75, 0.75))
	_list.add_child(_more_down)
	_name_edit = LineEdit.new()
	_name_edit.add_theme_font_override("font", make_font(true))
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.max_length = 16
	_name_edit.visible = false
	_name_edit.text_submitted.connect(func(value: String) -> void:
		if _mode == 3:
			_named.emit(value))
	box.add_child(_name_edit)
	_hint = Label.new()
	_hint.add_theme_font_override("font", make_font())
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_hint)
	_panel.visible = false


func is_open() -> bool:
	return _mode != 0


func _show_speaker(speaker: String) -> void:
	_speaker.text = speaker
	_speaker.add_theme_color_override("font_color", SPEAKER_COLORS.get(speaker, Color(1.0, 0.85, 0.5)))
	var file: String = String(PORTRAITS.get(speaker, ""))
	if speaker == GameState.player_name:
		var atlas := AtlasTexture.new()
		atlas.atlas = preload("res://game/art/player_sheet.png")
		atlas.region = Rect2(14, 2, 36, 40)
		_portrait.texture = atlas
		_portrait_box.visible = true
	elif file != "":
		_portrait.texture = load("res://game/art/npc/%s.png" % file)
		_portrait_box.visible = true
	else:
		_portrait_box.visible = false
	_panel.visible = true


## lines: mảng [người nói, câu thoại]. Người nói rỗng = lời dẫn.
func say(lines: Array) -> void:
	for line in lines:
		_mode = 1
		_show_speaker(String(line[0]))
		_text.text = String(line[1]) if line[0] != "" else "[i]%s[/i]" % String(line[1])
		_text.visible_ratio = 0.0
		_hint.text = "[E] tiếp"
		await _advanced
	_close()


## details (tuỳ chọn): mô tả cho từng lựa chọn, hiện dưới câu hỏi khi lựa chọn đó đang được chọn.
func choose(speaker: String, prompt: String, options: Array, details: Array = []) -> int:
	_mode = 2
	_options = options
	_details = details
	_option_index = 0
	_option_top = 0
	_body = prompt
	_show_speaker(speaker)
	_hint.text = "[W/S] chọn   [E] xác nhận"
	_text.text = prompt
	_text.visible_ratio = 1.0
	_set_choice_layout(true)
	_refresh_options()
	var index: int = await _chosen
	_sfx.play(&"confirm", -6.0)
	_close()
	return index


func ask_name(speaker: String, prompt: String, default_name: String) -> String:
	_mode = 3
	_show_speaker(speaker)
	_text.text = prompt
	_text.visible_ratio = 1.0
	_hint.text = "Gõ tên rồi nhấn Enter"
	_name_edit.text = default_name
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()
	var value: String = await _named
	_name_edit.visible = false
	_name_edit.release_focus()
	_close()
	value = value.strip_edges()
	return default_name if value == "" else value


func _close() -> void:
	_mode = 0
	_panel.visible = false
	_set_choice_layout(false)


func _make_option_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", make_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## Chế độ lựa chọn: câu hỏi co theo nội dung, danh sách lựa chọn bên dưới; hộp nới lên trên khi cần.
func _set_choice_layout(on: bool) -> void:
	_list.visible = on
	_text.fit_content = on
	_text.size_flags_vertical = Control.SIZE_FILL if on else Control.SIZE_EXPAND_FILL
	if not on:
		_detail.visible = false


func _visible_option_count() -> int:
	return mini(_options.size(), MAX_VISIBLE_OPTIONS)


func _refresh_options() -> void:
	var count: int = _options.size()
	var shown: int = _visible_option_count()
	# Cửa sổ cuộn luôn chứa lựa chọn đang chọn.
	if _option_index < _option_top:
		_option_top = _option_index
	elif _option_index >= _option_top + shown:
		_option_top = _option_index - shown + 1
	_option_top = clampi(_option_top, 0, maxi(count - shown, 0))
	while _rows.size() < shown:
		var row: Label = _make_option_label(OPTION_FONT_SIZE, OPTION_COLOR)
		_list.add_child(row)
		_list.move_child(row, _list.get_child_count() - 2) # trước dòng ▼
		_rows.append(row)
	for r in range(_rows.size()):
		var row: Label = _rows[r]
		row.visible = r < shown
		if r >= shown:
			continue
		var i: int = _option_top + r
		var selected: bool = i == _option_index
		row.text = ("▶ " if selected else "   ") + String(_options[i])
		row.add_theme_font_override("font", make_font(selected))
		row.add_theme_color_override("font_color", OPTION_SELECTED_COLOR if selected else OPTION_COLOR)
	var windowed: bool = count > shown
	_more_up.visible = windowed
	_more_down.visible = windowed
	_more_up.text = "   ▲ còn %d lựa chọn" % _option_top if _option_top > 0 else ""
	var below: int = count - (_option_top + shown)
	_more_down.text = "   ▼ còn %d lựa chọn" % below if below > 0 else ""
	# Mỗi dòng lựa chọn chỉ một hàng (dài thì cắt "…"); mô tả hoặc nguyên văn lựa chọn dài hiện ở dòng mô tả.
	var detail: String = String(_details[_option_index]) if _option_index < _details.size() else ""
	if detail == "" and String(_options[_option_index]).length() > LONG_OPTION_CHARS:
		detail = String(_options[_option_index])
	_detail.text = detail
	_detail.visible = detail != ""


func _move(step: int) -> void:
	if _mode != 2 or _options.is_empty():
		return
	_option_index = posmod(_option_index + step, _options.size())
	_sfx.play(&"select", -8.0)
	_refresh_options()


## Lựa chọn i có đang hiện trong khung hộp thoại không (test dùng; cần layout đã cập nhật).
func is_option_visible(i: int) -> bool:
	if _mode != 2 or i < _option_top or i >= _option_top + _visible_option_count():
		return false
	var row: Label = _rows[i - _option_top]
	if not row.is_visible_in_tree():
		return false
	var panel_rect: Rect2 = _panel.get_global_rect()
	var row_rect: Rect2 = row.get_global_rect()
	var view: Rect2 = Rect2(Vector2.ZERO, _panel.get_viewport_rect().size)
	return row_rect.size.y >= 8.0 and panel_rect.grow(1.0).encloses(row_rect) and view.grow(1.0).encloses(panel_rect)


func _process(delta: float) -> void:
	if _mode == 1 and _text.visible_ratio < 1.0:
		var total: int = maxi(_text.get_total_character_count(), 1)
		_text.visible_ratio = minf(1.0, _text.visible_ratio + delta * CHARS_PER_SECOND / float(total))


func _unhandled_input(event: InputEvent) -> void:
	if _mode == 0 or _mode == 3 or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code: int = key.physical_keycode
	get_viewport().set_input_as_handled()
	if _mode == 1:
		if code == KEY_E or code == KEY_SPACE or code == KEY_ENTER or code == KEY_J:
			if _text.visible_ratio < 1.0:
				_text.visible_ratio = 1.0
			else:
				_sfx.play(&"select", -10.0)
				_advanced.emit()
	elif _mode == 2:
		if code == KEY_W or code == KEY_UP:
			_move(-1)
		elif code == KEY_S or code == KEY_DOWN:
			_move(1)
		elif code == KEY_E or code == KEY_SPACE or code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_J:
			_chosen.emit(_option_index)
