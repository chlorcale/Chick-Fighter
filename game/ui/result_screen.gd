class_name ResultScreen
extends CanvasLayer

## Màn kết quả sau trận: thắng/thua, tiền thưởng, EXP chạy thanh, lên cấp (công thức 3–4).

signal _closed

var won: bool = false
var rewards: Array[String] = []
var exp_gain: int = 0

var _canvas: Control
var _time: float = 0.0
var _start_level: int = 1
var _start_xp: int = 0
var _shown_level: int = 1
var _shown_xp: float = 0.0
var _remaining: float = 0.0
var _level_ups: int = 0
var _sfx: Sfx
## Hình hai chiến kê của trận vừa đấu (theo kit; lấy từ BattleDirector.last_match).
var _views: Array[Sprite2D] = []
var _tags: Array[String] = []
var _kits: Array[StringName] = []


func _ready() -> void:
	layer = 45
	_sfx = Sfx.new()
	add_child(_sfx)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_screen)
	add_child(_canvas)
	var sides: Array = BattleDirector.last_match.get("sides", [])
	if sides.size() == 2:
		for i in range(2):
			var side: Dictionary = sides[i]
			var kit: StringName = Moves.kit_for_side(side)
			var anims: Dictionary = Moves.kit(kit)["anims"]
			var winner: bool = (i == 0) == won
			var sprite := Sprite2D.new()
			sprite.texture = FighterView.sheet_for(kit)
			sprite.region_enabled = true
			sprite.centered = false
			sprite.offset = -FighterView.foot_for(kit)
			if not winner:
				sprite.offset.x += float(Moves.kit(kit)["x_comp"]) # tag nằm vẽ lệch (xem movelist)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.material = FighterView.material_for_side(side)
			sprite.modulate = Color.WHITE if winner else Color(0.6, 0.6, 0.7)
			_canvas.add_child(sprite)
			_views.append(sprite)
			_kits.append(kit)
			_tags.append(String(anims["taunt"] if winner else anims["nam"]))


## Gọi trước khi GameState.add_exp để thanh EXP chạy từ giá trị cũ.
func run() -> void:
	_start_level = GameState.level
	_start_xp = GameState.xp
	_shown_level = _start_level
	_shown_xp = float(_start_xp)
	_remaining = float(exp_gain)
	_level_ups = GameState.add_exp(exp_gain)
	_sfx.play(&"confirm" if won else &"select")
	await _closed
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	for i in range(_views.size()):
		var sprite: Sprite2D = _views[i]
		var s: float = 2.4
		sprite.scale = Vector2(s if i == 0 else -s, s)
		sprite.position = Vector2(_canvas.size.x * (0.16 if i == 0 else 0.84), _canvas.size.y * 0.62)
		sprite.region_rect = FighterView.frame_region(FighterView.tag_frame_at(_tags[i], int(_time * 60.0), true, _kits[i]))
		sprite.self_modulate.a = clampf(_time / 0.4, 0.0, 1.0)
	if _time > 0.8 and _remaining > 0.0:
		var step: float = minf(_remaining, delta * 80.0)
		_remaining -= step
		_shown_xp += step
		var need: int = GameState.exp_to_next(_shown_level)
		if _shown_xp >= float(need) and _shown_level < GameState.LEVEL_CAP:
			_shown_xp -= float(need)
			_shown_level += 1
			_sfx.play(&"card")
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = (event as InputEventKey).physical_keycode
		if code == KEY_E or code == KEY_ENTER or code == KEY_SPACE or code == KEY_J:
			get_viewport().set_input_as_handled()
			if _remaining > 0.0:
				_shown_level = GameState.level
				_shown_xp = float(GameState.xp)
				_remaining = 0.0
			else:
				_closed.emit()


func _text(pos: Vector2, text: String, size: int, color: Color = Color.WHITE, bold: bool = false) -> void:
	var font: Font = DialogBox.make_font(bold)
	_canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, _canvas.size.x, size, 6, Color.BLACK)
	_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, _canvas.size.x, size, color)


func _draw_screen() -> void:
	var w: float = _canvas.size.x
	var h: float = _canvas.size.y
	var appear: float = clampf(_time / 0.3, 0.0, 1.0)
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.05, 0.03, 0.02, 0.88 * appear))
	_text(Vector2(0, h * 0.24), "THẮNG!" if won else "THUA…", 64, Color(1.0, 0.85, 0.3) if won else Color(0.75, 0.8, 0.95), true)
	var y: float = h * 0.36
	for line in rewards:
		_text(Vector2(0, y), line, 22, Color(1, 1, 1))
		y += 32.0
	y += 20.0
	_text(Vector2(0, y), "%s · Lv%d" % [GameState.chicken_name, _shown_level], 24, Color(1.0, 0.9, 0.6), true)
	var bar := Rect2(w * 0.5 - 220.0, y + 16.0, 440.0, 18.0)
	_canvas.draw_rect(bar.grow(3), Color(0, 0, 0, 0.8))
	var need: int = GameState.exp_to_next(_shown_level)
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_shown_xp / float(need), 0.0, 1.0), bar.size.y)),
		Color(0.45, 0.85, 0.35))
	_text(Vector2(0, y + 60.0), "EXP +%d   (%d / %d)" % [exp_gain, int(_shown_xp), need], 18, Color(0.85, 0.95, 0.85))
	if _shown_level > _start_level:
		var pulse: float = 0.8 + 0.2 * sin(_time * 8.0)
		_text(Vector2(0, y + 100.0), "LÊN CẤP %d!  HP và ATK tăng" % _shown_level, 26, Color(1.0, 0.85, 0.3, pulse), true)
	if _remaining <= 0.0:
		_text(Vector2(0, h - 40.0), "[E] tiếp tục", 16, Color(0.7, 0.7, 0.7))
