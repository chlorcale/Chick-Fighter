class_name UISkin
extends RefCounted

## Bộ giao diện pixel "gỗ + giấy dó" dùng chung cho mọi màn hình (ảnh dựng bằng tools/art/build_ui_skin.py,
## font bằng tools/art/build_font.py). Toàn hàm tĩnh – gọi thẳng UISkin.xxx(), không cần tạo đối tượng.
##
## QUY ƯỚC CỠ CHỮ (font pixel phóng NGUYÊN lần, fixed_size 11): cỡ 11–16 → ×1 (chữ hoa 7 px; đậm 9 px),
## 17–27 → ×2, 28–38 → ×3, 39–49 → ×4… Dùng hằng FS_* cho gọn: FS_SMALL 11, FS_BODY 22, FS_BIG 33, FS_HUGE 44.
## Chiều cao dòng: thường 15 px × hệ số, đậm 17 px × hệ số.
##
## API cho các màn hình khác (WORLD / HOME / MINIGAMES):
##   UISkin.pixel(node)                          – đặt TEXTURE_FILTER_NEAREST cho gốc giao diện (chữ ×2 không nhoè)
##   UISkin.panel_style(kind, pad)               – StyleBoxTexture 9-slice: wood dark plate portrait tooltip paper sign
##                                                 book tab_on tab_off button button_hover button_pressed toast slot
##   UISkin.make_panel(kind, pad)                – PanelContainer đã gắn style + NEAREST
##   UISkin.label(text, size, color, bold, outline) – Label dùng font game
##   UISkin.draw_panel(ci, rect, kind)           – vẽ khung trong _draw()
##   UISkin.draw_text(ci, pos, text, size, color, bold, align, width, outline) – chữ có viền tuỳ chọn
##   UISkin.text_size(text, size, bold)          – đo chữ
##   UISkin.icon(name) / UISkin.draw_icon(ci, name, center, scale) – biểu tượng 12×12 (ICON_NAMES)
##   UISkin.key_prompt(key, action)              – nhãn "[E] Nói chuyện" kiểu phím gỗ
##   UISkin.draw_key_prompt(ci, pos, key, action) – như trên nhưng vẽ trong _draw()
##   UISkin.style_button(button)                 – Button kiểu ván gỗ
##   UISkin.status_panel() / UISkin.objective_style() – gợi ý cho bảng trạng thái/mục tiêu khi khám phá

const DIR: String = "res://game/art/ui/"
## Một pixel thiết kế = 2 px màn hình (ảnh trong game/art/ui đã phóng sẵn ×2).
const PX: int = 2
## Lề 9-slice (đơn vị pixel thiết kế, ×PX khi dùng) – khớp bảng PANELS của build_ui_skin.py.
const MARGINS: Dictionary = {
	&"wood": 10, &"dark": 7, &"plate": 5, &"portrait": 5, &"tooltip": 4, &"paper": 3, &"sign": 6, &"book": 9,
	&"tab_on": 4, &"tab_off": 4, &"button": 5, &"button_hover": 5, &"button_pressed": 5, &"toast": 6, &"slot": 3,
}
## Khung có ruột kéo giãn (gradient/màu phẳng) – còn lại lát gạch (giữ vân gỗ, hạt giấy).
const STRETCH_KINDS: Array[StringName] = [&"portrait", &"tooltip", &"paper", &"tab_on", &"tab_off", &"slot",
	&"button", &"button_hover", &"button_pressed", &"toast"]
## Đệm chữ mặc định trong khung (px màn hình, tính thêm sau lề 9-slice).
const PADS: Dictionary = {&"wood": 6, &"dark": 4, &"plate": 2, &"portrait": 0, &"tooltip": 4, &"paper": 8, &"sign": 2,
	&"book": 10, &"tab_on": 2, &"tab_off": 2, &"button": 4, &"button_hover": 4, &"button_pressed": 4, &"toast": 6, &"slot": 4}

const ICON_SIZE: int = 12
const ICON_COLS: int = 8
const ICON_NAMES: Array[StringName] = [
	&"chicken", &"sword", &"card", &"book", &"coin", &"egg", &"flask", &"house", &"map", &"boat", &"bike", &"siren",
	&"trophy", &"star", &"lock", &"cat", &"fish", &"temple", &"market", &"flag", &"heart", &"clock", &"jar", &"ticket",
	&"sign", &"bridge", &"key", &"shield", &"fire", &"medal", &"dog", &"plate", &"dna", &"coop", &"sparkle", &"sun",
	&"sunset", &"moon", &"you", &"target", &"question", &"school", &"race", &"rice", &"brick", &"fight", &"gear",
]

## Màu chữ.
const INK: Color = Color(0.243, 0.153, 0.094)        ## chữ trên giấy
const INK_SOFT: Color = Color(0.478, 0.337, 0.212)   ## chữ phụ trên giấy
const INK_RED: Color = Color(0.64, 0.2, 0.13)        ## nhấn trên giấy (lựa chọn đang chọn)
const INK_GREEN: Color = Color(0.2, 0.42, 0.18)
const CREAM: Color = Color(0.984, 0.933, 0.816)      ## chữ trên gỗ sẫm
const GOLD: Color = Color(0.957, 0.773, 0.322)
const SHADOW: Color = Color(0.18, 0.1, 0.063)        ## viền chữ
const PAPER: Color = Color(0.965, 0.902, 0.745)
const DIM: Color = Color(0.72, 0.64, 0.52)

## Hướng "đóng dấu" viền chữ (draw_string_crisp).
const STAMP_DIRS: Array[Vector2] = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0),
	Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]
const FS_SMALL: int = 11
const FS_BODY: int = 22
const FS_BIG: int = 33
const FS_HUGE: int = 44

static var _tex: Dictionary = {}
static var _styles: Dictionary = {}
static var _icons: Dictionary = {}


static func texture(file_name: String) -> Texture2D:
	if _tex.has(file_name):
		return _tex[file_name]
	var path: String = DIR + file_name + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex[file_name] = tex
	return tex


static func font(bold: bool = false) -> Font:
	return DialogBox.make_font(bold)


## Gốc giao diện: lọc NEAREST cho chữ/ảnh phóng nguyên lần (Control con thừa hưởng).
static func pixel(ci: CanvasItem) -> void:
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## StyleBoxTexture 9-slice. pad: đệm thêm (px màn hình) sau lề khung; −1 = mặc định PADS[kind].
static func panel_style(kind: StringName = &"wood", pad: float = -1.0) -> StyleBoxTexture:
	var key: String = "%s|%s" % [kind, pad]
	if _styles.has(key):
		return _styles[key]
	var style := StyleBoxTexture.new()
	style.texture = texture("panel_" + String(kind))
	var m: float = float(MARGINS.get(kind, 4)) * PX
	style.texture_margin_left = m
	style.texture_margin_top = m
	style.texture_margin_right = m
	style.texture_margin_bottom = m
	var extra: float = float(PADS.get(kind, 4)) if pad < 0.0 else pad
	# Khung dày (gỗ, sổ): chữ nằm trong ruột giấy; khung mỏng: đệm theo lề.
	var content: float = m + extra
	style.content_margin_left = content
	style.content_margin_right = content
	style.content_margin_top = content
	style.content_margin_bottom = content
	if kind in STRETCH_KINDS:
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	else:
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	_styles[key] = style
	return style


static func make_panel(kind: StringName = &"wood", pad: float = -1.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style(kind, pad))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pixel(panel)
	return panel


static func label(text: String, size: int = FS_SMALL, color: Color = INK, bold: bool = false, outline: int = 0,
		outline_color: Color = SHADOW) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		label_shadow(l, outline, outline_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func draw_panel(ci: CanvasItem, rect: Rect2, kind: StringName = &"wood") -> void:
	ci.draw_style_box(panel_style(kind), Rect2(rect.position.round(), rect.size.round()))


## pos = điểm đường chân chữ (như draw_string). outline > 0: viền màu outline_color.
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, size: int = FS_SMALL, color: Color = INK,
		bold: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, outline: int = 0,
		outline_color: Color = SHADOW) -> void:
	draw_string_crisp(ci, font(bold), pos, text, align, width, size, color, outline, outline_color)


## Chữ có viền "đóng dấu": vẽ lại chính glyph đó bằng màu viền ở các ô lệch quanh rồi vẽ chữ lên trên. Viền glyph riêng
## của Godot (draw_string_outline / outline_size) với font pixel phóng nguyên lần + lọc NEAREST + cửa sổ co giãn lẻ
## (1280×720 ↔ 1152×648) lệch 1 px so với nét chữ → lốm đốm đen trong nét; cùng một glyph thì luôn khớp.
## outline: độ dày như outline_size (bán kính ≈ outline/2 px).
static func draw_string_crisp(ci: CanvasItem, f: Font, pos: Vector2, text: String, align: int, width: float, size: int,
		color: Color, outline: int = 0, outline_color: Color = SHADOW) -> void:
	var p: Vector2 = pos.round()
	if outline > 0 and outline_color.a > 0.0 and color.a > 0.0:
		# 8 hướng ở bán kính r; r không vượt hệ số phóng của chữ (nét chữ rộng đúng bấy nhiêu px) để viền liền nét.
		var r: float = float(clampi(roundi(float(outline) * 0.5), 1, maxi(1, roundi(float(size) / 11.0))))
		var oc := Color(outline_color, outline_color.a * color.a)
		for d in STAMP_DIRS:
			ci.draw_string(f, p + d * r, text, align, width, size, oc)
	ci.draw_string(f, p, text, align, width, size, color)


## Label: thay viền glyph (lệch nét, xem draw_string_crisp) bằng bóng đổ cùng glyph – nét pixel sắc, kiểu Stardew.
## outline: độ dày cũ (bóng lệch ≈ outline/2 px, 1..4).
static func label_shadow(l: Label, outline: int = 4, color: Color = SHADOW) -> void:
	var px: int = clampi(roundi(float(outline) * 0.5), 1, 4)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", color)
	l.add_theme_constant_override("shadow_offset_x", px)
	l.add_theme_constant_override("shadow_offset_y", px)
	l.add_theme_constant_override("shadow_outline_size", 0)


static func text_size(text: String, size: int = FS_SMALL, bold: bool = false) -> Vector2:
	return font(bold).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)


## Đường chân chữ cho chữ căn giữa dọc trong một ô cao h (y = đỉnh ô).
static func baseline_in(y: float, h: float, size: int = FS_SMALL, bold: bool = false) -> float:
	var f: Font = font(bold)
	return roundf(y + (h - f.get_height(size)) * 0.5 + f.get_ascent(size))


static func icon(icon_name: StringName) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var i: int = ICON_NAMES.find(icon_name)
	var sheet: Texture2D = texture("icons")
	if i < 0 or sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet
	var s: int = ICON_SIZE * PX
	at.region = Rect2((i % ICON_COLS) * s, (i / ICON_COLS) * s, s, s)
	_icons[icon_name] = at
	return at


## Vẽ biểu tượng căn giữa ở center; scale 1 = 24 px (12 pixel thiết kế × PX).
static func draw_icon(ci: CanvasItem, icon_name: StringName, center: Vector2, scale: float = 1.0,
		modulate: Color = Color.WHITE) -> void:
	var tex: Texture2D = icon(icon_name)
	if tex == null:
		return
	var s: Vector2 = Vector2(ICON_SIZE * PX, ICON_SIZE * PX) * scale
	ci.draw_texture_rect(tex, Rect2((center - s * 0.5).round(), s), false, modulate)


## Nhãn "[E] Nói chuyện": phím gỗ nhỏ + chữ trên ô chú thích. Trả về PanelContainer (tự co theo chữ).
static func key_prompt(key: String, action: String) -> PanelContainer:
	var panel := make_panel(&"tooltip", 2.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var cap := make_panel(&"button", 0.0)
	var k := label(key, FS_SMALL, CREAM, true)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(k)
	row.add_child(cap)
	var t := label(action, FS_BODY, INK)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(t)
	return panel


## Như key_prompt nhưng vẽ thẳng (pos = góc trên trái). Trả về kích thước đã vẽ.
static func draw_key_prompt(ci: CanvasItem, pos: Vector2, key: String, action: String, size: int = FS_BODY) -> Vector2:
	var ks: Vector2 = text_size(key, FS_SMALL, true)
	var ts: Vector2 = text_size(action, size)
	var h: float = maxf(ts.y, 26.0) + 12.0
	var cap_w: float = ks.x + 20.0
	var w: float = cap_w + ts.x + 26.0
	pos = pos.round()
	var box := Rect2(pos, Vector2(w, h))
	draw_panel(ci, box, &"tooltip")
	var cap := Rect2(pos + Vector2(6, 6), Vector2(cap_w, h - 12.0))
	draw_panel(ci, cap, &"button")
	draw_text(ci, Vector2(cap.position.x, baseline_in(cap.position.y - 1.0, cap.size.y, FS_SMALL, true)), key, FS_SMALL,
		CREAM, true, HORIZONTAL_ALIGNMENT_CENTER, cap.size.x)
	draw_text(ci, Vector2(cap.end.x + 8.0, baseline_in(pos.y, h, size)), action, size, INK)
	return box.size


## Tách "[E] Nói chuyện" → ["E", "Nói chuyện"]; chữ không mở đầu bằng [phím] → ["", chữ].
static func split_prompt(text: String) -> PackedStringArray:
	if text.begins_with("["):
		var close: int = text.find("]")
		if close > 1:
			return PackedStringArray([text.substr(1, close - 1), text.substr(close + 1).strip_edges()])
	return PackedStringArray(["", text])


## Kích thước nhãn phím do draw_key_prompt / draw_prompt vẽ.
static func key_prompt_size(key: String, action: String, size: int = FS_BODY) -> Vector2:
	var ts: Vector2 = text_size(action, size)
	var h: float = maxf(ts.y, 26.0) + 12.0
	if key == "":
		return Vector2(ts.x + 28.0, h)
	return Vector2(text_size(key, FS_SMALL, true).x + 20.0 + ts.x + 26.0, h)


static func prompt_size(text: String, size: int = FS_BODY) -> Vector2:
	var parts: PackedStringArray = split_prompt(text)
	return key_prompt_size(parts[0], parts[1], size)


## Vẽ dòng nhắc "[E] Lên xe máy" (có phím gỗ) hoặc chữ thường ("W ga · S lùi") trên ô chú thích. pos = góc trên trái.
static func draw_prompt(ci: CanvasItem, pos: Vector2, text: String, size: int = FS_BODY) -> Vector2:
	var parts: PackedStringArray = split_prompt(text)
	if parts[0] != "":
		return draw_key_prompt(ci, pos, parts[0], parts[1], size)
	var box := Rect2(pos, key_prompt_size("", parts[1], size))
	draw_panel(ci, box, &"tooltip")
	draw_text(ci, Vector2(pos.x, baseline_in(pos.y, box.size.y, size)), parts[1], size, INK, false,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	return box.size


## Dải nhắc phím nhỏ (chữ ×1 đậm): [[phím, việc], …] trên khung gỗ sẫm. right_bottom = góc dưới phải của dải.
## Trả về khung đã vẽ.
static func draw_key_hints(ci: CanvasItem, right_bottom: Vector2, pairs: Array, size: int = FS_SMALL) -> Rect2:
	var gap: float = 14.0
	var w: float = 16.0
	for pair in pairs:
		if String(pair[0]) != "":
			w += text_size(String(pair[0]), FS_SMALL, true).x + 12.0 + 6.0
		w += text_size(String(pair[1]), size, true).x + gap
	w -= gap
	var h: float = 34.0
	var box := Rect2((right_bottom - Vector2(w, h)).round(), Vector2(w, h).round())
	draw_panel(ci, box, &"dark")
	var x: float = box.position.x + 8.0
	for pair in pairs:
		if String(pair[0]) != "":
			var kw: float = text_size(String(pair[0]), FS_SMALL, true).x + 12.0
			var cap := Rect2(Vector2(x, box.position.y + 6.0), Vector2(kw, h - 12.0))
			draw_panel(ci, cap, &"button")
			draw_text(ci, Vector2(cap.position.x, baseline_in(cap.position.y - 1.0, cap.size.y, FS_SMALL, true)),
				String(pair[0]), FS_SMALL, CREAM, true, HORIZONTAL_ALIGNMENT_CENTER, cap.size.x)
			x = cap.end.x + 6.0
		draw_text(ci, Vector2(x, baseline_in(box.position.y, h, size, true)), String(pair[1]), size, CREAM, true)
		x += text_size(String(pair[1]), size, true).x + gap
	return box


## "[W/S] chọn   [E] xác nhận · [Esc] thôi" → [["W/S", "chọn"], ["E", "xác nhận"], ["Esc", "thôi"]] (cho draw_key_hints).
static func hint_pairs(hint: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\[([^\\]]+)\\]([^\\[]*)")
	for m in re.search_all(hint):
		out.append([m.get_string(1), m.get_string(2).strip_edges().trim_suffix("·").strip_edges()])
	if out.is_empty():
		out.append(["", hint.strip_edges()])
	return out


static func style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", panel_style(&"button"))
	button.add_theme_stylebox_override("hover", panel_style(&"button_hover"))
	button.add_theme_stylebox_override("focus", panel_style(&"button_hover"))
	button.add_theme_stylebox_override("pressed", panel_style(&"button_pressed"))
	button.add_theme_font_override("font", font(true))
	button.add_theme_font_size_override("font_size", FS_SMALL)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	pixel(button)


## Tỉ lệ "sắc nét" cho hình pixel trong bảng UI: làm tròn để mỗi pixel art phủ đúng số NGUYÊN pixel màn hình
## (tính cả co giãn cửa sổ canvas_items). body: hệ số riêng của hình (gà tre 0,9 trong FighterView.Portrait).
## Cùng cách với ChickenSprite.crisp_scale (game/home/chicken_sprite.gd).
static func crisp_scale(ci: CanvasItem, desired: float, body: float = 1.0) -> float:
	if desired < 1.0 or ci == null or not ci.is_inside_tree():
		return desired
	var v: float = ci.get_viewport().get_final_transform().get_scale().x
	var screen: float = maxf(1.0, roundf(desired * body * v))
	return screen / maxf(body * v, 0.001)


## Vị trí bám đúng pixel màn hình (sau co giãn cửa sổ).
static func snap(ci: CanvasItem, pos: Vector2) -> Vector2:
	if ci == null or not ci.is_inside_tree():
		return pos.round()
	var v: float = ci.get_viewport().get_final_transform().get_scale().x
	return (pos * v).round() / maxf(v, 0.001)


## Hệ số thân của hình chân dung (gà tre 0,9) nếu có.
static func body_scale_of(node: Object) -> float:
	var b: Variant = node.get("body_scale") if node != null else null
	return float(b) if b != null else 1.0


## Gợi ý cho WORLD: bảng trạng thái (tên · tiền · gà) – khung gỗ sẫm, chữ kem.
static func status_panel() -> PanelContainer:
	return make_panel(&"dark", 2.0)


## Gợi ý cho WORLD: dải mục tiêu – ô giấy có viền gỗ mảnh.
static func objective_style() -> StyleBoxTexture:
	return panel_style(&"tooltip", 4.0)
