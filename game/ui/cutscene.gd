class_name Cutscene
extends CanvasLayer

## Cắt cảnh tối giản (GDD 9.5): màn hình tối, tiếng côn trùng đêm, chữ hiện dần.
## Mỗi dòng: [người nói, lời] — người nói rỗng là lời dẫn.

signal _next

var _bg: ColorRect
var _speaker: Label
var _label: Label
var _hint: Label
var _sfx: Sfx
var _cricket_timer: float = 0.0
var crickets: bool = true


func _ready() -> void:
	layer = 60
	_bg = ColorRect.new()
	_bg.color = Color(0.02, 0.02, 0.05)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_speaker = _make_label(22, Color(1.0, 0.85, 0.5), true)
	_speaker.offset_top = -80.0
	_label = _make_label(28, Color(0.95, 0.93, 0.85), false)
	_label.offset_top = -30.0
	_hint = _make_label(14, Color(0.55, 0.55, 0.55), false)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -40.0
	_hint.text = "[E] tiếp"
	_sfx = Sfx.new()
	add_child(_sfx)


func _make_label(font_size: int, color: Color, bold: bool) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = -480.0
	label.offset_right = 480.0
	label.offset_bottom = 120.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", DialogBox.make_font(bold))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func play(lines: Array) -> void:
	for line in lines:
		_speaker.text = String(line[0])
		_label.text = String(line[1])
		_label.modulate.a = 0.0
		_speaker.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_label, "modulate:a", 1.0, 0.6)
		tween.tween_property(_speaker, "modulate:a", 1.0, 0.6)
		await _next
	var fade := create_tween()
	fade.tween_property(_bg, "modulate:a", 0.0, 0.6)
	fade.parallel().tween_property(_label, "modulate:a", 0.0, 0.4)
	fade.parallel().tween_property(_speaker, "modulate:a", 0.0, 0.4)
	await fade.finished
	queue_free()


func _process(delta: float) -> void:
	if not crickets:
		return
	_cricket_timer -= delta
	if _cricket_timer <= 0.0:
		_cricket_timer = randf_range(1.0, 2.2)
		_sfx.play(&"cricket", -4.0, randf_range(0.9, 1.1))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = (event as InputEventKey).physical_keycode
		if code == KEY_E or code == KEY_SPACE or code == KEY_ENTER or code == KEY_J:
			get_viewport().set_input_as_handled()
			_next.emit()
