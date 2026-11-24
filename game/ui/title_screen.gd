class_name TitleScreen
extends Node2D

## Màn hình tiêu đề: bản đồ xóm Bình Kê cuộn chậm làm nền, chiến kê lớn, logo chữ pixel, menu trong khung gỗ (UISkin).
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
	UISkin.pixel(_canvas)
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
	UISkin.draw_text(_canvas, pos, text, size, color, bold, align, width, outline, Color(0.12, 0.04, 0.02))


func _draw_ui() -> void:
	var w: float = _canvas.size.x
	var h: float = _canvas.size.y
	for i in range(24):
		var k: float = float(i) / 23.0
		_canvas.draw_rect(Rect2(0, h * k, w, h / 23.0 + 1.0), Color(0.05, 0.02, 0.0, 0.15 + 0.55 * k))
	for i in range(30):
		var k: float = float(i) / 29.0
		_canvas.draw_rect(Rect2(w * 0.7 * k, 0, w * 0.7 / 29.0 + 1.0, h), Color(0.05, 0.02, 0.0, 0.45 * (1.0 - k)))
	# Logo: chữ pixel phóng nguyên lần (cỡ là bội của 11), "ĐÁ GÀ" nhún nhẹ.
	var bob: float = -2.0 if fmod(_time, 1.6) < 0.8 else 0.0
	_text(Vector2(60, 108), "HUYỀN THOẠI", UISkin.FS_BIG, Color(1.0, 0.92, 0.7), true)
	_text(Vector2(52, 200 + bob), "ĐÁ GÀ", 88, Color(1.0, 0.55, 0.15), true, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	_text(Vector2(62, 244), "CHICK FIGHTER", UISkin.FS_BODY, UISkin.GOLD, true)
	_text(Vector2(62, 276), "Ao Làng – Act 1", UISkin.FS_BODY, Color(0.95, 0.9, 0.8), false, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	# Bảng chọn: khung gỗ giấy dó, mũi tên chỉ.
	var row_h: float = 42.0
	var box := Rect2(52, 312, 300, _options.size() * row_h + 52.0)
	UISkin.draw_panel(_canvas, box, &"wood")
	for i in range(_options.size()):
		var selected: bool = i == _index
		var y: float = box.position.y + 26.0 + i * row_h
		if selected:
			_canvas.draw_rect(Rect2(box.position.x + 20, y, box.size.x - 40, row_h), Color(0.86, 0.72, 0.5, 0.55))
			var nudge: float = 2.0 if fmod(_time, 0.6) < 0.3 else 0.0
			_canvas.draw_texture(UISkin.texture("cursor"), Vector2(box.position.x + 28 + nudge, y + 12))
		UISkin.draw_text(_canvas, Vector2(box.position.x + 60, UISkin.baseline_in(y, row_h, UISkin.FS_BODY, selected)), _options[i],
			UISkin.FS_BODY, UISkin.INK_RED if selected else UISkin.INK, selected)
	UISkin.draw_key_hints(_canvas, Vector2(w - 12, h - 10), [["W/S", "Chọn"], ["E", "Xác nhận"]])
