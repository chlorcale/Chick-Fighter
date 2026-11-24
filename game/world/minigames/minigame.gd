extends Node2D

## Khung chung cho các TRANG mini-game (màn riêng, như trò đua xe): ActivityRunner làm mờ, ẩn World
## (world.set_active(false)), thêm trang này vào cây; trang có camera riêng, cảnh vẽ riêng 384×216 (art ở
## res://game/art/minigames/<trang>/, dựng bởi tools/art/build_minigames.py), bảng hướng dẫn, pha chơi, bảng
## kết quả; xong thì runner mờ dần về đúng chỗ cũ trong xóm.
## - Phím: W/A/S/D hoặc mũi tên = up/down/left/right, E/J/Space/Enter = confirm, Esc/Backspace = cancel
##   (đang chơi: hỏi lại "Bỏ ngang?" – E bỏ, Esc chơi tiếp).
## - Test/headless: press(&"confirm") để bơm phím, hold(action, bật/tắt) để giữ phím, hoặc autopilot = true để
##   trang tự qua bảng hướng dẫn, tự chơi và tự đóng bảng kết quả.
## - Lớp con: _page() (thư mục art), _intro() [tiêu đề, hướng dẫn], _build() (dựng cảnh), _start(), _tick(delta),
##   _animate(delta) (cảnh động ở mọi pha), _on_action(action), _wants(action), _cancel_result(),
##   _result_info(result) [tiêu đề, nội dung, tốt?]; gọi finish(result) khi xong.
## - fx(kind, pos): móc âm thanh của main.gd (splash, throw, catch, cut, pick, drop, win, incense, xam, ticket);
##   các tiếng khác trang tự phát bằng Audio.sfx.

signal finished(result: Dictionary)
signal fx(kind: StringName, pos: Vector2)

enum Phase { INTRO, PLAY, RESULT, DONE }

const VIEW: Vector2 = Vector2(384, 216)
const ART_DIR: String = "res://game/art/minigames/"
const PLAYER_SHEET: Texture2D = preload("res://game/art/player_sheet_v2.png")
const HERO_FOOT: Vector2 = Vector2(32, 58)
const Audio := preload("res://game/audio/audio_director.gd")
const WorldFx := preload("res://game/world/world_fx.gd")
## Các fx mà main.gd đã phát tiếng (_on_activity_fx) – trang không phát lại cho khỏi trùng.
const ROUTED: Array[StringName] = [&"splash", &"throw", &"catch", &"cut", &"pick", &"drop", &"win", &"incense",
	&"xam", &"ticket"]
const INTRO_AUTO: float = 0.25
const RESULT_MIN: float = 0.5
const RESULT_AUTO: float = 0.35
const INK: Color = Color(0.29, 0.16, 0.08)
const INK_SOFT: Color = Color(0.45, 0.28, 0.14)
const CREAM: Color = Color(1.0, 0.95, 0.82)
const GOOD: Color = Color(0.22, 0.5, 0.16)
const BAD: Color = Color(0.7, 0.2, 0.12)

var world: Node          # World (chỉ tham chiếu; trang không vẽ lên bản đồ)
var ground_fx: Node2D    # giữ tương thích với runner cũ (không dùng)
var air_fx: Node2D
var autopilot: bool = false
var time_left: float = 0.0
## true trong pha chơi (giữa bảng hướng dẫn và bảng kết quả).
var running: bool = false
var phase: int = Phase.INTRO
var result: Dictionary = {}
## Hiện đồng hồ đếm ngược ở góc phải (lớp con tắt nếu không tính giờ).
var show_timer: bool = true
## Độ cao (px màn hình) của chữ bật – trang nào có bảng ở giữa thì hạ xuống.
var toast_y: float = 150.0

var camera: Camera2D
var fxl: Node2D          # WorldFx trong toạ độ trang (gợn sóng, nước văng, bụi, khói)
var hud: CanvasLayer
var ui: Control          # gốc giao diện (toàn màn hình)
## Bảng gỗ góc trái trên (tên trò + trạng thái) – trang con tránh đặt chữ cảnh dưới bảng này.
var top_panel: PanelContainer

var _phase_time: float = 0.0
## true khi runner đã gọi run() (màn mờ xong) – trước đó trang chỉ vẽ cảnh, chưa nhận phím.
var _live: bool = false
var _confirming: bool = false
var _held: Dictionary = {}
var _shake: float = 0.0
var _clock: float = 0.0
var _textures: Dictionary = {}
var _sfx: Node
var _title: Label
var _status: Label
var _timer: Label
var _timer_panel: PanelContainer
var _hint: Label
var _toast: Label
var _toast_time: float = 0.0
var _dim: ColorRect
var _intro_panel: PanelContainer
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: Label
var _confirm_panel: PanelContainer
var _result_wait: float = -1.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sfx_script: Script = load("res://game/battle/sfx.gd")
	if sfx_script != null:
		_sfx = sfx_script.new()
		add_child(_sfx)
	var letterbox := Node2D.new()
	letterbox.z_index = -100
	letterbox.draw.connect(func() -> void:
		letterbox.draw_rect(Rect2(-VIEW, VIEW * 3.0), Color(0.08, 0.05, 0.04)))
	add_child(letterbox)
	camera = Camera2D.new()
	camera.position = VIEW * 0.5
	add_child(camera)
	camera.make_current()
	_build_hud()
	_build()
	fxl = WorldFx.new()
	fxl.z_index = 60
	add_child(fxl)
	var intro: Array = _intro()
	_show_intro(String(intro[0]), String(intro[1]))
	set_texts(String(intro[0]), "")
	_fit_view()


## Chạy tới khi người chơi rời trang; trả về kết quả (luôn có "cancelled": bool).
func run() -> Dictionary:
	_live = true
	_phase_time = 0.0
	var r: Dictionary = await finished
	return r


## Nhạc + tiếng nền của trang (runner gọi khi vào; tự trả lại tiếng cũ khi ra).
func enter_audio() -> void:
	var track: StringName = _music()
	if track != &"-":
		Audio.music(track, 0.8)
	Audio.ambience(_ambience(), 0.8)


# ================================================================== lớp con override

func _page() -> String:
	return ""


func _intro() -> Array:
	return ["", ""]


func _build() -> void:
	pass


func _start() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _animate(_delta: float) -> void:
	pass


func _on_action(_action: StringName) -> void:
	pass


func _wants(action: StringName) -> bool:
	return action == &"confirm" or action == &"cancel"


func _cancel_result() -> Dictionary:
	return {"cancelled": true}


## [tiêu đề, nội dung, tốt?] cho bảng kết quả.
func _result_info(_r: Dictionary) -> Array:
	return ["XONG!", "", true]


func _cleanup() -> void:
	pass


func _music() -> StringName:
	return &"village"


func _ambience() -> Dictionary:
	return {&"birds": 0.4, &"leaves": 0.3}


## Dòng nhắc phím ở đáy màn hình.
func _hint_text() -> String:
	return "[E] Làm   ·   [Esc] Nghỉ"


# ================================================================== điều khiển

## Bơm một thao tác (test dùng trực tiếp; bàn phím cũng đi qua đây).
func press(action: StringName) -> void:
	if not _live:
		return
	match phase:
		Phase.INTRO:
			if action == &"confirm":
				_begin_play()
			elif action == &"cancel":
				result = _cancel_result()
				result["cancelled"] = true
				_end()
		Phase.PLAY:
			if _confirming:
				if action == &"confirm":
					_confirming = false
					_confirm_panel.visible = false
					_dim.visible = false
					finish(_cancel_result())
				elif action == &"cancel":
					_confirming = false
					_confirm_panel.visible = false
					_dim.visible = false
				return
			if action == &"cancel":
				_confirming = true
				_confirm_panel.visible = true
				_dim.visible = true
				sfx(&"ui_move", -8.0)
				return
			_on_action(action)
		Phase.RESULT:
			if (action == &"confirm" or action == &"cancel") and _phase_time >= RESULT_MIN:
				sfx(&"ui_confirm", -6.0)
				_end()


## Bỏ ngang ngay (không hỏi lại) – cho test.
func quit_now() -> void:
	if phase == Phase.PLAY:
		_confirming = false
		finish(_cancel_result())
	elif phase == Phase.INTRO:
		press(&"cancel")


func hold(action: StringName, on: bool) -> void:
	_held[action] = on


## Phím hướng đang giữ (bàn phím thật hoặc hold() của test).
func held(action: StringName) -> bool:
	if bool(_held.get(action, false)):
		return true
	if autopilot:
		return false
	match action:
		&"left":
			return Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
		&"right":
			return Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
		&"up":
			return Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
		&"down":
			return Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
		&"confirm":
			return Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_J) \
				or Input.is_physical_key_pressed(KEY_SPACE)
	return false


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.DONE or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var action: StringName = &""
	match key.physical_keycode:
		KEY_E, KEY_J, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			action = &"confirm"
		KEY_ESCAPE, KEY_BACKSPACE:
			action = &"cancel"
		KEY_W, KEY_UP:
			action = &"up"
		KEY_S, KEY_DOWN:
			action = &"down"
		KEY_A, KEY_LEFT:
			action = &"left"
		KEY_D, KEY_RIGHT:
			action = &"right"
	if action == &"":
		return
	get_viewport().set_input_as_handled()
	if phase == Phase.PLAY and not _confirming and not _wants(action):
		return
	press(action)


func _begin_play() -> void:
	phase = Phase.PLAY
	_phase_time = 0.0
	running = true
	_intro_panel.visible = false
	_dim.visible = false
	_hint.get_parent().visible = true
	sfx(&"ui_confirm", -4.0)
	_start()
	_timer_panel.visible = show_timer


## Kết thúc pha chơi. Bỏ ngang thì rời trang ngay; xong thì hiện bảng kết quả (delay giây để xem nốt cảnh).
func finish(r: Dictionary, delay: float = 0.6) -> void:
	if phase != Phase.PLAY:
		return
	running = false
	_confirming = false
	r["cancelled"] = bool(r.get("cancelled", false))
	result = r
	_cleanup()
	if bool(r["cancelled"]):
		_end()
		return
	_result_wait = delay
	phase = Phase.RESULT
	_phase_time = -delay


func _end() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	running = false
	finished.emit.call_deferred(result)


func _process(delta: float) -> void:
	_clock += delta
	_phase_time += delta
	_fit_view()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0
		_toast.modulate.a = clampf(_toast_time / 0.25, 0.0, 1.0)
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)).round() * ceilf(_shake * 6.0)
	else:
		camera.offset = Vector2.ZERO
	_animate(delta)
	if not _live:
		return
	match phase:
		Phase.INTRO:
			if autopilot and _phase_time >= INTRO_AUTO:
				press(&"confirm")
		Phase.PLAY:
			if not _confirming:
				_tick(delta)
			if show_timer:
				_timer.text = "%d" % ceili(maxf(time_left, 0.0))
				_timer.add_theme_color_override("font_color", BAD if time_left < 6.0 else INK)
		Phase.RESULT:
			if _result_wait >= 0.0:
				_result_wait -= delta
				if _result_wait < 0.0:
					_show_result()
			elif autopilot and _phase_time >= RESULT_AUTO:
				press(&"confirm")


func _fit_view() -> void:
	var vis: Vector2 = get_viewport_rect().size
	var z: float = minf(vis.x / VIEW.x, vis.y / VIEW.y)
	camera.zoom = Vector2(z, z)


# ================================================================== tiện ích cho lớp con

func tex(name: String) -> Texture2D:
	var key: String = _page() + "/" + name
	if _textures.has(key):
		return _textures[key]
	var path: String = ART_DIR + key + ".png"
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[key] = t
	return t


## Khung thứ i của một sheet ngang có count khung.
func frame(name: String, count: int, i: int) -> Texture2D:
	var key: String = "%s#%d/%d" % [name, i, count]
	if _textures.has(key):
		return _textures[key]
	var sheet: Texture2D = tex(name)
	if sheet == null:
		return null
	var w: int = sheet.get_width() / count
	var a := AtlasTexture.new()
	a.atlas = sheet
	a.region = Rect2(w * posmod(i, count), 0, w, sheet.get_height())
	_textures[key] = a
	return a


## Sprite đặt theo chân (gốc = giữa đáy ảnh).
func sprite(t: Texture2D, pos: Vector2, z: int = 0, parent: Node = null) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = t
	s.centered = false
	if t != null:
		s.offset = Vector2(-floorf(t.get_width() * 0.5), -t.get_height())
	s.position = pos
	s.z_index = z
	(parent if parent != null else self).add_child(s)
	return s


## Ảnh nền đặt ở góc trái trên.
func backdrop(name: String, z: int = -10) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(name)
	s.centered = false
	s.z_index = z
	add_child(s)
	return s


func npc_texture(name: String) -> Texture2D:
	var path: String = "res://game/art/npc/%s.png" % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Khung của sprite người chơi (player_sheet_v2: 0–3 đứng, 4–7 xuống, 8–11 lên, 12–15 trái, 16–19 phải).
func hero_texture(i: int) -> Texture2D:
	var key: String = "hero#%d" % i
	if _textures.has(key):
		return _textures[key]
	var a := AtlasTexture.new()
	a.atlas = PLAYER_SHEET
	a.region = Rect2(64 * i, 0, 64, 64)
	_textures[key] = a
	return a


## Sprite người chơi: gốc = chân.
func hero_sprite(pos: Vector2, i: int = 0, z: int = 0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = hero_texture(i)
	s.centered = false
	s.offset = -HERO_FOOT
	s.position = pos
	s.z_index = z
	add_child(s)
	return s


## Khung đi bộ theo hướng (left/right/up/down) và thời gian.
func hero_walk(dir: StringName, t: float) -> int:
	var base: int = {&"down": 4, &"up": 8, &"left": 12, &"right": 16}.get(dir, 4)
	return base + int(t * 7.0) % 4


func hero_idle(t: float) -> int:
	return int(t * 2.0) % 4


## Toạ độ trang → toạ độ màn hình (đặt nhãn chữ của HUD lên cảnh).
func to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


func view_zoom() -> float:
	return camera.zoom.x


func shake(amount: float = 0.25) -> void:
	_shake = maxf(_shake, amount)


func sound(kind: StringName, pos: Vector2 = Vector2.ZERO) -> void:
	fx.emit(kind, pos)
	if kind == &"miss" and _sfx != null:
		_sfx.call("play", &"whiff", -6.0)


func sfx(name: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	Audio.sfx(name, volume_db, pitch)


func set_texts(title: String, info: String) -> void:
	_title.text = title
	if info != "":
		_hint.text = info


func set_status(text: String) -> void:
	_status.text = text
	# dòng trống thì ẩn để bảng góc trái co lại vừa tiêu đề
	if _status.visible != (text != ""):
		_status.visible = text != ""
		top_panel.reset_size.call_deferred()


## Chữ lớn bật lên giữa màn hình trong chốc lát ("Ngọt!", "Hụt rồi!").
func toast(text: String, color: Color = Color(1.0, 0.95, 0.5)) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast.offset_top = toast_y
	_toast.modulate.a = 1.0
	_toast_time = 0.9


# ================================================================== giao diện

func make_label(font_size: int, color: Color, bold: bool = false, outline_px: int = 0) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", DialogBox.make_font(bold))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline_px > 0:
		UISkin.label_shadow(label, outline_px, Color(0.16, 0.08, 0.04))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Khung gỗ + giấy da (ui/panel.png, 9 mảnh); dark = khung gỗ tối cho chữ sáng.
func make_panel(dark: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path: String = ART_DIR + ("ui/panel_dark.png" if dark else "ui/panel.png")
	if ResourceLoader.exists(path):
		var box := StyleBoxTexture.new()
		box.texture = load(path)
		box.texture_margin_left = 15
		box.texture_margin_right = 15
		box.texture_margin_top = 15
		box.texture_margin_bottom = 15
		box.content_margin_left = 20
		box.content_margin_right = 20
		box.content_margin_top = 14
		box.content_margin_bottom = 14
		panel.add_theme_stylebox_override("panel", box)
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.23, 0.13, 0.08, 0.92) if dark else Color(0.97, 0.87, 0.65)
		flat.border_color = Color(0.45, 0.22, 0.1)
		flat.set_border_width_all(4)
		flat.set_content_margin_all(14)
		panel.add_theme_stylebox_override("panel", flat)
	return panel


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 30
	add_child(hud)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hud.add_child(ui)
	# góc trái trên: tên trò + trạng thái
	var top := make_panel()
	top_panel = top
	top.position = Vector2(12, 10)
	ui.add_child(top)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	top.add_child(box)
	_title = make_label(UISkin.FS_BODY, Color(0.55, 0.2, 0.08), true)
	box.add_child(_title)
	_status = make_label(UISkin.FS_BODY, INK)
	box.add_child(_status)
	_status.visible = false
	# góc phải trên: đồng hồ
	_timer_panel = make_panel()
	_timer_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_panel.offset_left = -108
	_timer_panel.offset_right = -12
	_timer_panel.offset_top = 10
	_timer_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui.add_child(_timer_panel)
	_timer = make_label(UISkin.FS_BIG, INK, true)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.custom_minimum_size = Vector2(56, 0)
	_timer_panel.add_child(_timer)
	_timer_panel.visible = false
	# đáy: nhắc phím
	var hint_panel := make_panel(true)
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.offset_bottom = -8
	ui.add_child(hint_panel)
	_hint = make_label(UISkin.FS_BODY, CREAM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_panel.add_child(_hint)
	hint_panel.visible = false
	_hint.text = _hint_text()
	# chữ bật
	_toast = make_label(UISkin.FS_BIG, Color(1.0, 0.95, 0.5), true, 8)
	_toast.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.02, 0.85))
	_toast.add_theme_constant_override("shadow_offset_x", 3)
	_toast.add_theme_constant_override("shadow_offset_y", 4)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 150
	_toast.visible = false
	ui.add_child(_toast)
	# lớp tối + các bảng
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.03, 0.02, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_dim)
	_intro_panel = _center_panel(700)
	_result_panel = _center_panel(640)
	_confirm_panel = _center_panel(580)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 8)
	_confirm_panel.get_child(0).add_child(cbox)
	var q := make_label(UISkin.FS_BODY, INK, true)
	q.text = "Bỏ ngang, hổng làm nữa hả?"
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(q)
	var keys := make_label(UISkin.FS_BODY, INK_SOFT)
	keys.text = "[E] Bỏ ngang (không có thưởng)     [Esc] Làm tiếp"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(keys)
	_confirm_panel.visible = false
	_result_panel.visible = false


func _center_panel(width: float) -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(center)
	var panel := make_panel()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var inner := MarginContainer.new()
	panel.add_child(inner)
	# bảng ẩn/hiện bằng cả CenterContainer
	panel.visibility_changed.connect(func() -> void: center.visible = panel.visible)
	return panel


func _show_intro(title: String, body: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_intro_panel.get_child(0).add_child(box)
	var t := make_label(UISkin.FS_BIG, Color(0.55, 0.2, 0.08), true)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var b := make_label(UISkin.FS_BODY, INK)
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(640, 0)
	box.add_child(b)
	var keys := make_label(UISkin.FS_BODY, Color(0.55, 0.2, 0.08), true)
	keys.text = "[E] Bắt đầu          [Esc] Thôi"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)
	_intro_panel.visible = true
	_dim.visible = true


func _show_result() -> void:
	var info: Array = _result_info(result)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_result_panel.get_child(0).add_child(box)
	_result_title = make_label(UISkin.FS_BIG, GOOD if bool(info[2]) else BAD, true)
	_result_title.text = String(info[0])
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_body = make_label(UISkin.FS_BODY, INK)
	_result_body.text = String(info[1])
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_body.custom_minimum_size = Vector2(580, 0)
	box.add_child(_result_body)
	var keys := make_label(UISkin.FS_BODY, Color(0.55, 0.2, 0.08), true)
	keys.text = "[E] Về xóm"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)
	_result_panel.visible = true
	_dim.visible = true
	_hint.get_parent().visible = false
	_phase_time = 0.0
	sfx(&"ui_confirm", -6.0)


## Bật/tắt đồng hồ góc phải (gọi trong _start).
func use_timer(on: bool) -> void:
	show_timer = on
	_timer_panel.visible = on
