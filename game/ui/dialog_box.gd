class_name DialogBox
extends CanvasLayer

## Hộp thoại kiểu sổ gỗ cổ (UISkin): khung gỗ có đinh tán + ruột giấy dó, bảng tên ván gỗ nhô trên khung,
## khung chân dung viền đồng, chữ chạy có tiếng "bíp" nhẹ, dấu ▼ nhún nhảy khi chờ bấm, lựa chọn có mũi tên chỉ.
## E / Space / Enter / J: hiện hết chữ hoặc sang câu tiếp. W/S (↑/↓) chọn.
## Lựa chọn: danh sách cuộn theo cửa sổ (tối đa MAX_VISIBLE_OPTIONS dòng, có ▲/▼ khi còn nữa),
## hộp thoại nới lên trên khi cần nên lựa chọn đang chọn luôn nằm trong khung.
## Font: make_font() – font pixel riêng của game (game/fonts/chick_body.ttf, chick_bold.ttf; tools/art/build_font.py).

signal _advanced
signal _chosen(index: int)
signal _named(text: String)

const Audio := preload("res://game/audio/audio_director.gd")

## Chân dung nhân vật chính bản mới (bán thân, phóng ×4 NEAREST).
const PLAYER_PORTRAIT: Texture2D = preload("res://game/art/player_sheet_v2_portrait.png")
## Tên người nói → ảnh trong res://game/art/npc/ (hoặc đường dẫn res:// đầy đủ).
const PORTRAITS: Dictionary = {
	"Chú Tư": "chu_tu", "Tèo": "teo", "MC": "mc", "Cô Ba": "lady", "Út Mập": "crowd_3",
	"Bảy Ghe": "fisher", "Ông nội": "fisher", "Ông từ": "temple_man", "Cô bán vé số": "lottery",
	# tầng đời sống (game/story): hàng xóm, trường THPT, sới Liên tỉnh/Olympic, công an, người nhà
	"Bà Lan": "ba_lan", "Chú Bảy": "chu_bay", "Ông Tám": "ong_tam", "Ông Sáu": "ong_sau", "Chú Mười": "chu_muoi",
	"Thầy Khoa": "co_thao", "Chú bảo vệ": "bao_ve", "Mèo tam thể": "meo", "Con mèo": "meo", "Lão Gà Khô": "lao_ga_kho",
	"Ông bầu Sáu Lộc": "bau_sau", "Cô Diệu": "co_dieu", "Công an": "cong_an", "Chú công an": "cong_an",
	"Tổng đài": "dien_thoai", "Chú Tư (điện thoại)": "dien_thoai", "Ông câu cá": "fisher",
	"Mẹ": "res://game/art/home/family_me_portrait.png", "Ba": "res://game/art/home/family_cha_portrait.png",
	"Em trai": "res://game/art/home/family_em_portrait.png",
	"Hai Bến Tre": "crowd_2", "Ba Cà Mau": "fisher", "Năm Châu Đốc": "crowd_4", "Sáu Vĩnh Long": "crowd_5",
	"Tám Cần Thơ": "crowd_1", "Chín Sài Gòn": "crowd_3", "Mười Đồng Tháp": "crowd_2", "Út Hà Tiên": "fisher",
	"Ông Bảy Bạc Liêu": "crowd_5", "Thầy Cửu": "temple_man",
}
const SPEAKER_COLORS: Dictionary = {
	"Mẹ": Color(1.0, 0.7, 0.75), "Chú Tư": Color(1.0, 0.8, 0.35), "Tèo": Color(0.6, 0.9, 1.0),
	"Cô Ba": Color(0.95, 0.75, 1.0), "MC": Color(1.0, 0.55, 0.3), "Ông nội": Color(0.85, 0.85, 0.7),
	"Cô Hạnh": Color(0.7, 0.9, 1.0), "Chú Sáu": Color(0.6, 0.95, 0.75), "Cô Năm": Color(1.0, 0.85, 0.45),
	"Ông từ": Color(1.0, 0.65, 0.45), "Thợ hồ": Color(0.95, 0.7, 0.55), "Cô bán vé số": Color(1.0, 0.6, 0.8),
	"Bà Lan": Color(1.0, 0.78, 0.55), "Chú Bảy": Color(0.75, 0.85, 0.65), "Ông Tám": Color(0.95, 0.9, 0.55),
	"Ông Sáu": Color(0.7, 0.85, 0.95), "Chú Mười": Color(0.6, 0.95, 0.6), "Thầy Khoa": Color(0.75, 0.85, 1.0),
	"Mèo tam thể": Color(1.0, 0.75, 0.4), "Con mèo": Color(1.0, 0.75, 0.4), "Lão Gà Khô": Color(1.0, 0.68, 0.3), "Ông bầu Sáu Lộc": Color(1.0, 0.85, 0.2),
	"Cô Diệu": Color(0.95, 0.6, 0.85), "Công an": Color(0.55, 0.8, 0.55), "Chú công an": Color(0.55, 0.8, 0.55),
	"Tổng đài": Color(0.7, 0.9, 0.9), "Chú Tư (điện thoại)": Color(1.0, 0.8, 0.35), "Mẹo": Color(0.6, 1.0, 0.85),
	"Ba": Color(0.8, 0.85, 1.0), "Em trai": Color(0.7, 1.0, 0.8),
}
const CHARS_PER_SECOND: float = 55.0
const FONT_DIR: String = "res://game/fonts/"
## Hai mặt chữ pixel của game (build_font.py). Font khác (.ttf/.otf) thả vào FONT_DIR chỉ dùng khi thiếu hai file này.
const BODY_FONT: String = "res://game/fonts/chick_body.ttf"
const BOLD_FONT: String = "res://game/fonts/chick_bold.ttf"
## Cỡ gốc của font pixel: cỡ chữ được làm tròn về bội nguyên của số này (11–16 → ×1, 17–27 → ×2, …).
const PIXEL_FIXED_SIZE: int = 11
const MAX_VISIBLE_OPTIONS: int = 5
const OPTION_FONT_SIZE: int = 22
const TEXT_FONT_SIZE: int = 22
const LONG_OPTION_CHARS: int = 64
const OPTION_COLOR: Color = Color(0.243, 0.153, 0.094)
const OPTION_SELECTED_COLOR: Color = Color(0.64, 0.2, 0.13)
const NARRATION_COLOR: String = "#7a5636"
## Khung chân dung (px màn hình, ruột trong viền).
const PORTRAIT_AREA: Vector2 = Vector2(132, 150)
## Một tiếng bíp mỗi BLIP_EVERY ký tự hiện ra.
const BLIP_EVERY: int = 3

static var _font_cache: Dictionary = {}

var _root: Control
var _panel: PanelContainer
var _plate: PanelContainer
var _portrait: TextureRect
var _portrait_box: Control
var _speaker: Label
var _text: RichTextLabel
var _hint: Label
var _next: TextureRect
var _cursor: TextureRect
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
var _time: float = 0.0
var _blip_count: int = 0
var _row_selected_style: StyleBoxFlat
var _row_style: StyleBoxEmpty


## Font của toàn bộ game: font pixel riêng (chick_body / chick_bold, phóng nguyên lần, không khử răng cưa),
## ký tự thiếu thì lấy từ font hệ thống. Thiếu file font thì thử font .ttf/.otf khác trong FONT_DIR, rồi font hệ thống.
static func make_font(bold: bool = false) -> Font:
	if _font_cache.has(bold):
		return _font_cache[bold]
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans", "sans-serif"])
	system.font_weight = 700 if bold else 400
	var font: Font = system
	var pixel: FontFile = _load_face(bold)
	if pixel != null:
		pixel.fallbacks = [system]
		font = pixel
	_font_cache[bold] = font
	return font


static func has_game_font() -> bool:
	return _load_face(false) != null


## Mặt chữ pixel (bold hoặc thường), đã đặt chế độ hiển thị nét pixel.
static func _load_face(bold: bool) -> FontFile:
	var key: String = "face_bold" if bold else "face_body"
	if _font_cache.has(key):
		return _font_cache[key]
	var path: String = BOLD_FONT if bold else BODY_FONT
	var found: FontFile = _load_font_file(path)
	var ours: bool = found != null
	if found == null:
		found = _load_game_font()
	if found != null:
		found.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		found.hinting = TextServer.HINTING_NONE
		found.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		if ours:
			# Dựng ở cỡ gốc (1 pixel thiết kế = 1 px) rồi phóng nguyên lần: nét pixel luôn đều.
			found.fixed_size = PIXEL_FIXED_SIZE
			found.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	_font_cache[key] = found
	return found


static func _load_font_file(path: String) -> FontFile:
	var found: FontFile = null
	if ResourceLoader.exists(path):
		found = load(path) as FontFile
	if found == null and FileAccess.file_exists(path):
		# File vừa thả vào, Godot chưa import: đọc thẳng từ đĩa.
		var raw := FontFile.new()
		if raw.load_dynamic_font(path) == OK:
			found = raw
	return found


## Font khác do người dùng thả vào game/fonts/ (vd. KVN-97) – chỉ dùng khi thiếu font pixel của game.
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
			if not (lower.ends_with(".ttf") or lower.ends_with(".otf")) or lower.begins_with("chick_"):
				continue
			found = _load_font_file(FONT_DIR + String(file_name))
			if found != null:
				break
	_font_cache["pixel"] = found
	return found


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx = Sfx.new()
	add_child(_sfx)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UISkin.pixel(_root)
	add_child(_root)
	_row_selected_style = StyleBoxFlat.new()
	_row_selected_style.bg_color = Color(0.86, 0.72, 0.5, 0.55)
	_row_selected_style.set_content_margin_all(0)
	_row_style = StyleBoxEmpty.new()

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 48.0
	_panel.offset_right = -48.0
	_panel.offset_top = -214.0
	_panel.offset_bottom = -14.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN # nội dung dài thì nới lên trên
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UISkin.panel_style(&"wood", 8.0))
	_root.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)
	_portrait_box = PanelContainer.new()
	_portrait_box.add_theme_stylebox_override("panel", UISkin.panel_style(&"portrait", 0.0))
	_portrait_box.custom_minimum_size = PORTRAIT_AREA + Vector2(20, 20)
	_portrait_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait_box)
	var center := CenterContainer.new()
	_portrait_box.add_child(center)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	center.add_child(_portrait)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, 96)
	_text.add_theme_font_override("normal_font", make_font())
	_text.add_theme_font_override("bold_font", make_font(true))
	_text.add_theme_font_override("italics_font", make_font())
	_text.add_theme_font_size_override("normal_font_size", TEXT_FONT_SIZE)
	_text.add_theme_font_size_override("bold_font_size", TEXT_FONT_SIZE)
	_text.add_theme_font_size_override("italics_font_size", TEXT_FONT_SIZE)
	_text.add_theme_color_override("default_color", UISkin.INK)
	box.add_child(_text)
	_detail = UISkin.label("", UISkin.FS_SMALL, UISkin.INK_GREEN, true)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.visible = false
	box.add_child(_detail)
	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", 30)
	box.add_child(list_margin)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.visible = false
	list_margin.add_child(_list)
	_more_up = _make_option_label(UISkin.FS_SMALL, UISkin.INK_SOFT)
	_list.add_child(_more_up)
	_more_down = _make_option_label(UISkin.FS_SMALL, UISkin.INK_SOFT)
	_list.add_child(_more_down)
	_name_edit = LineEdit.new()
	_name_edit.add_theme_font_override("font", make_font(true))
	_name_edit.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
	_name_edit.add_theme_color_override("font_color", UISkin.INK)
	_name_edit.add_theme_color_override("font_selected_color", UISkin.CREAM)
	_name_edit.add_theme_color_override("selection_color", Color(0.64, 0.2, 0.13, 0.8))
	_name_edit.add_theme_color_override("caret_color", UISkin.INK_RED)
	_name_edit.add_theme_constant_override("caret_width", 2)
	_name_edit.add_theme_stylebox_override("normal", UISkin.panel_style(&"slot", 8.0))
	_name_edit.add_theme_stylebox_override("focus", UISkin.panel_style(&"slot", 8.0))
	_name_edit.custom_minimum_size = Vector2(320, 0)
	_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name_edit.max_length = 16
	_name_edit.visible = false
	_name_edit.text_submitted.connect(func(value: String) -> void:
		if _mode == 3:
			_named.emit(value))
	box.add_child(_name_edit)
	_hint = UISkin.label("", UISkin.FS_SMALL, UISkin.INK_SOFT, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var hint_margin := MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_right", 30) # chừa chỗ cho dấu ▼
	hint_margin.add_child(_hint)
	box.add_child(hint_margin)

	# Bảng tên (ván gỗ) nhô lên trên khung, dấu ▼ chờ bấm, mũi tên chỉ lựa chọn: đặt tay mỗi khung hình.
	_plate = UISkin.make_panel(&"plate", 4.0)
	var plate_style: StyleBoxTexture = UISkin.panel_style(&"plate", 4.0).duplicate()
	plate_style.content_margin_left = 24.0
	plate_style.content_margin_right = 24.0
	plate_style.content_margin_top = 8.0
	plate_style.content_margin_bottom = 8.0
	_plate.add_theme_stylebox_override("panel", plate_style)
	_speaker = UISkin.label("", TEXT_FONT_SIZE, UISkin.CREAM, true, 4, UISkin.SHADOW)
	_plate.add_child(_speaker)
	_root.add_child(_plate)
	_next = TextureRect.new()
	_next.texture = UISkin.texture("next")
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_next)
	_cursor = TextureRect.new()
	_cursor.texture = UISkin.texture("cursor")
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cursor)
	_panel.visible = false
	_plate.visible = false
	_next.visible = false
	_cursor.visible = false


func is_open() -> bool:
	return _mode != 0


func _show_speaker(speaker: String) -> void:
	_speaker.text = speaker
	_speaker.add_theme_color_override("font_color", SPEAKER_COLORS.get(speaker, Color(1.0, 0.85, 0.5)))
	var file: String = String(PORTRAITS.get(speaker, ""))
	if speaker == GameState.player_name:
		# chân dung bán thân nhân vật chính (tools/art/build_player.py, khung idle nhìn thẳng ×4)
		_portrait.texture = PLAYER_PORTRAIT
		_portrait_box.visible = true
	elif file != "":
		var path: String = file if file.begins_with("res://") else "res://game/art/npc/%s.png" % file
		_portrait.texture = load(path) if ResourceLoader.exists(path) else null
		_portrait_box.visible = _portrait.texture != null
	else:
		_portrait.texture = null
		_portrait_box.visible = false
	_fit_portrait()
	_panel.visible = true
	_plate.visible = speaker != ""
	_plate.reset_size()


## Chân dung phóng NGUYÊN lần lớn nhất vừa khung (ảnh NPC 20×42 → ×3, chân dung 96×112 → ×1).
func _fit_portrait() -> void:
	var tex: Texture2D = _portrait.texture
	if tex == null:
		_portrait.custom_minimum_size = Vector2.ZERO
		return
	var ts: Vector2 = tex.get_size()
	var k: float = maxf(1.0, floorf(minf(PORTRAIT_AREA.x / ts.x, PORTRAIT_AREA.y / ts.y)))
	if ts.x * k > PORTRAIT_AREA.x or ts.y * k > PORTRAIT_AREA.y:
		k = minf(PORTRAIT_AREA.x / ts.x, PORTRAIT_AREA.y / ts.y) # ảnh quá lớn: thu nhỏ vừa khung
	_portrait.custom_minimum_size = (ts * k).floor()
	_portrait.size = _portrait.custom_minimum_size


## lines: mảng [người nói, câu thoại]. Người nói rỗng = lời dẫn.
func say(lines: Array) -> void:
	for line in lines:
		_mode = 1
		_show_speaker(String(line[0]))
		_text.text = String(line[1]) if line[0] != "" else "[color=%s]%s[/color]" % [NARRATION_COLOR, String(line[1])]
		_text.visible_ratio = 0.0
		_blip_count = 0
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


## Ô nhập tên là hộp thoại "chặn" – luôn nằm trên lớp màn đen chuyển cảnh (main hỏi tên lúc màn hình còn đen).
func ask_name(speaker: String, prompt: String, default_name: String) -> String:
	_mode = 3
	layer = 96
	_show_speaker(speaker)
	_text.text = prompt
	_text.visible_ratio = 1.0
	_text.fit_content = true
	_text.size_flags_vertical = Control.SIZE_FILL
	_text.custom_minimum_size.y = 0.0
	_hint.text = "Gõ tên rồi nhấn Enter"
	_name_edit.text = default_name
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()
	var value: String = await _named
	_name_edit.visible = false
	_name_edit.release_focus()
	_close()
	layer = 50
	value = value.strip_edges()
	return default_name if value == "" else value


func _close() -> void:
	_mode = 0
	_panel.visible = false
	_plate.visible = false
	_next.visible = false
	_cursor.visible = false
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
	_text.custom_minimum_size.y = 0.0 if on else 96.0
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
		row.text = String(_options[i])
		row.add_theme_color_override("font_color", OPTION_SELECTED_COLOR if selected else OPTION_COLOR)
		row.add_theme_stylebox_override("normal", _row_selected_style if selected else _row_style)
	var windowed: bool = count > shown
	_more_up.visible = windowed
	_more_down.visible = windowed
	_more_up.text = "▲ còn %d lựa chọn" % _option_top if _option_top > 0 else ""
	var below: int = count - (_option_top + shown)
	_more_down.text = "▼ còn %d lựa chọn" % below if below > 0 else ""
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


## Mảnh giao diện đang dùng (test: kiểm tra hộp thoại đã lấy ảnh khung từ UISkin).
func skin_parts() -> Dictionary:
	var panel_box: StyleBoxTexture = _panel.get_theme_stylebox("panel") as StyleBoxTexture
	var plate_box: StyleBoxTexture = _plate.get_theme_stylebox("panel") as StyleBoxTexture
	return {
		"panel": panel_box.texture.resource_path if panel_box != null and panel_box.texture != null else "",
		"plate": plate_box.texture.resource_path if plate_box != null and plate_box.texture != null else "",
		"cursor": _cursor.texture.resource_path if _cursor.texture != null else "",
		"next": _next.texture.resource_path if _next.texture != null else "",
		"plate_visible": _plate.visible, "cursor_visible": _cursor.visible, "next_visible": _next.visible,
	}


func _process(delta: float) -> void:
	_time += delta
	if _mode == 1 and _text.visible_ratio < 1.0:
		var total: int = maxi(_text.get_total_character_count(), 1)
		_text.visible_ratio = minf(1.0, _text.visible_ratio + delta * CHARS_PER_SECOND / float(total))
		var shown: int = int(_text.visible_ratio * float(total))
		if shown / BLIP_EVERY > _blip_count:
			_blip_count = shown / BLIP_EVERY
			Audio.sfx(&"dialog_blip", -16.0, randf_range(0.92, 1.08))
	if _mode == 0:
		return
	var pr: Rect2 = Rect2(_panel.position, _panel.size)
	# bảng tên: góc trên trái, đè lên viền khung
	_plate.position = Vector2(pr.position.x + 26.0, pr.position.y - _plate.size.y + 14.0).round()
	# ▼ chờ bấm (chữ đã hiện hết)
	_next.visible = _mode == 1 and _text.visible_ratio >= 1.0
	if _next.visible:
		var bob: float = 2.0 if fmod(_time, 0.8) < 0.4 else 0.0
		_next.position = Vector2(pr.end.x - 50.0, pr.end.y - 44.0 + bob).round()
	# mũi tên chỉ lựa chọn đang chọn
	_cursor.visible = _mode == 2 and _option_index - _option_top < _rows.size() and _option_index >= _option_top
	if _cursor.visible:
		var row: Label = _rows[_option_index - _option_top]
		var nudge: float = 2.0 if fmod(_time, 0.6) < 0.3 else 0.0
		var rr: Rect2 = row.get_global_rect()
		_cursor.position = Vector2(rr.position.x - 26.0 + nudge, rr.position.y + (rr.size.y - 18.0) * 0.5).round()


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
