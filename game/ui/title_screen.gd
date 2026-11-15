class_name TitleScreen
extends Node2D

## Màn hình tiêu đề: bản đồ xóm Bình Kê cuộn chậm làm nền, chiến kê lớn, menu.
## Trả về "new" | "continue" | "quit".

signal _picked(choice: String)

var _map: MapView
var _camera: Camera2D
var _ui: CanvasLayer
var _canvas: Control
var _rooster: Sprite2D
var _options: Array[String] = []
var _ids: Array[String] = []
var _index: int = 0
var _time: float = 0.0
var _sfx: Sfx


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map = MapView.new()
	add_child(_map)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(2, 2)
	_camera.position = Vector2(320, 200)
	add_child(_camera)
	_camera.make_current()
	_sfx = Sfx.new()
	add_child(_sfx)

	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_ui)
	_ui.add_child(_canvas)
	_rooster = Sprite2D.new()
	_rooster.texture = FighterView.SHEET
	_rooster.region_enabled = true
	_rooster.centered = false
	_rooster.offset = -FighterView.FOOT
	_rooster.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rooster.scale = Vector2(4, 4)
	_canvas.add_child(_rooster)

	if GameState.has_save():
		_options.append("Tiếp tục")
		_ids.append("continue")
	_options.append("Chơi mới")
	_ids.append("new")
	_options.append("Thoát")
	_ids.append("quit")


func run() -> String:
	return await _picked


func _process(delta: float) -> void:
	_time += delta
	_camera.position = Vector2(320.0 + sin(_time * 0.07) * 260.0, 190.0)
	var frame: int = FighterView.tag_frame_at("idle", int(_time * 60.0))
	var cycle: float = fmod(_time, 7.0)
	if cycle > 5.6:
		frame = FighterView.tag_frame_at("TAUNT_GayThiUy", int((cycle - 5.6) * 60.0), false)
	_rooster.region_rect = FighterView.frame_region(frame)
	_rooster.position = Vector2(_canvas.size.x * 0.76, _canvas.size.y * 0.8)
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: int = (event as InputEventKey).physical_keycode
	match code:
		KEY_W, KEY_UP:
			_index = posmod(_index - 1, _options.size())
			_sfx.play(&"select", -6.0)
		KEY_S, KEY_DOWN:
			_index = posmod(_index + 1, _options.size())
			_sfx.play(&"select", -6.0)
		KEY_E, KEY_ENTER, KEY_SPACE, KEY_J:
			_sfx.play(&"confirm")
			get_viewport().set_input_as_handled()
			_picked.emit(_ids[_index])


func _text(pos: Vector2, text: String, size: int, color: Color, bold: bool, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0, outline: int = 8) -> void:
	var font: Font = DialogBox.make_font(bold)
	_canvas.draw_string_outline(font, pos, text, align, width, size, outline, Color(0.12, 0.04, 0.02))
	_canvas.draw_string(font, pos, text, align, width, size, color)


func _draw_ui() -> void:
	var w: float = _canvas.size.x
	var h: float = _canvas.size.y
	for i in range(24):
		var k: float = float(i) / 23.0
		_canvas.draw_rect(Rect2(0, h * k, w, h / 23.0 + 1.0), Color(0.05, 0.02, 0.0, 0.15 + 0.55 * k))
	for i in range(30):
		var k: float = float(i) / 29.0
		_canvas.draw_rect(Rect2(w * 0.7 * k, 0, w * 0.7 / 29.0 + 1.0, h), Color(0.05, 0.02, 0.0, 0.45 * (1.0 - k)))
	_text(Vector2(60, 120), "HUYỀN THOẠI", 40, Color(1.0, 0.92, 0.7), true)
	var pulse: float = 1.0 + 0.02 * sin(_time * 3.0)
	_text(Vector2(56, 196), "ĐÁ GÀ", int(86 * pulse), Color(1.0, 0.55, 0.15), true, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	_text(Vector2(62, 236), "CHICK FIGHTER", 28, Color(1.0, 0.85, 0.35), true)
	_text(Vector2(62, 266), "Ao Làng – Act 1", 18, Color(0.95, 0.9, 0.8), false)
	for i in range(_options.size()):
		var selected: bool = i == _index
		_text(Vector2(70, 350 + i * 46), ("▶  " if selected else "    ") + _options[i], 30 if selected else 26,
			Color(1.0, 0.85, 0.3) if selected else Color(0.85, 0.85, 0.85), selected)
	_text(Vector2(0, h - 20), "W/S chọn · E xác nhận", 15, Color(0.8, 0.8, 0.8), false, HORIZONTAL_ALIGNMENT_CENTER, w, 4)
