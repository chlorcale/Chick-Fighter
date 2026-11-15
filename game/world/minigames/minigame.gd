extends CanvasLayer

## Khung chung cho các mini-game ở bờ nam: bảng hướng dẫn trên cùng, đọc phím, kết thúc bằng run().
## - Phím: W/A/S/D hoặc mũi tên = up/down/left/right, E/J/Space/Enter = confirm, Esc/Backspace = cancel.
## - Test/headless: gọi press(&"confirm") để bơm phím, hoặc bật autopilot = true để game tự chơi.
## - Lớp con override _start(), _tick(delta), _on_action(action) và gọi finish(result).
## - fx(kind, world_pos): móc âm thanh/hiệu ứng (splash, catch, miss, cut, pick, drop, throw, tick, win).

signal finished(result: Dictionary)
signal fx(kind: StringName, world_pos: Vector2)

## Các loại khác (splash, catch, cut, pick, drop, throw, win) phát bằng AudioDirector qua tín hiệu fx
## (xem main.gd::_on_activity_fx); ở đây chỉ giữ tiếng "hụt" và tiếng tích tắc.
const SOUNDS: Dictionary = {
	&"miss": [&"whiff", -6.0], &"tick": [&"select", -14.0],
}

var world: Node          # World
var ground_fx: Node2D    # WorldFx ở lớp mặt nước
var air_fx: Node2D       # WorldFx trên cùng
var autopilot: bool = false
var time_left: float = 0.0
var running: bool = false

var _panel: PanelContainer
var _title: Label
var _info: Label
var _status: Label
var _toast: Label
var _toast_time: float = 0.0
var _sfx: Node


func _ready() -> void:
	layer = 20
	var sfx_script: Script = load("res://game/battle/sfx.gd")
	if sfx_script != null:
		_sfx = sfx_script.new()
		add_child(_sfx)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.offset_left = -330.0
	_panel.offset_right = 330.0
	_panel.offset_top = 96.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.07, 0.05, 0.86)
	style.border_color = Color(0.95, 0.75, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_title = _make_label(22, Color(1.0, 0.85, 0.4), true)
	box.add_child(_title)
	_info = _make_label(17, Color(0.95, 0.93, 0.88), false)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_status = _make_label(19, Color(0.75, 1.0, 0.7), true)
	box.add_child(_status)
	_toast = _make_label(30, Color(1.0, 0.95, 0.5), true)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300.0
	_toast.offset_right = 300.0
	_toast.offset_top = 236.0
	_toast.offset_bottom = 280.0
	_toast.visible = false
	add_child(_toast)


func _make_label(font_size: int, color: Color, bold: bool) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", DialogBox.make_font(bold))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


## Chạy mini-game tới khi xong; trả về Dictionary kết quả (luôn có "cancelled": bool).
func run() -> Dictionary:
	running = true
	_start()
	var result: Dictionary = await finished
	running = false
	return result


func finish(result: Dictionary) -> void:
	if not running:
		return
	running = false
	result["cancelled"] = bool(result.get("cancelled", false))
	_cleanup()
	finished.emit.call_deferred(result)


func set_texts(title: String, info: String) -> void:
	_title.text = title
	_info.text = info + "\n[Esc] bỏ ngang"


func set_status(text: String) -> void:
	_status.text = text


## Chữ lớn bật lên giữa màn hình trong chốc lát ("Ngọt!", "Hụt rồi!").
func toast(text: String, color: Color = Color(1.0, 0.95, 0.5)) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast_time = 0.8


func sound(kind: StringName, world_pos: Vector2 = Vector2.ZERO) -> void:
	fx.emit(kind, world_pos)
	if _sfx != null and SOUNDS.has(kind):
		_sfx.call("play", SOUNDS[kind][0], float(SOUNDS[kind][1]))


## Bơm một thao tác (test dùng trực tiếp; bàn phím cũng đi qua đây).
func press(action: StringName) -> void:
	if not running:
		return
	if action == &"cancel":
		finish(_cancel_result())
		return
	_on_action(action)


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0
	if running:
		_tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not running or not (event is InputEventKey):
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
	if action == &"" or not _wants(action):
		return
	get_viewport().set_input_as_handled()
	press(action)


# ------------------------------------------------------------------ để lớp con override

func _start() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _on_action(_action: StringName) -> void:
	pass


## Thao tác nào game này dùng (các phím khác để yên cho nhân vật đi).
func _wants(action: StringName) -> bool:
	return action == &"confirm" or action == &"cancel"


func _cancel_result() -> Dictionary:
	return {"cancelled": true}


func _cleanup() -> void:
	pass
