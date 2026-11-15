class_name PreBattle
extends CanvasLayer

## Màn Pre-battle (GDD 3.2, Hình 10.7): xem chiến kê hai bên, gắn trang bị, xem deck thẻ.
## Trả về true khi người chơi vào trận, false khi quay lại.

signal _done(start: bool)

var opponent: Dictionary = {}
var title: String = ""

var _rows: Array[String] = []
var _index: int = 0
var _canvas: Control
var _time: float = 0.0
var _sfx: Sfx
var _views: Array[Sprite2D] = []
var _kits: Array[StringName] = []


func _ready() -> void:
	layer = 40
	_sfx = Sfx.new()
	add_child(_sfx)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_screen)
	add_child(_canvas)
	if GameState.owns_dao_chan:
		_rows.append("dao_chan")
	if GameState.owns_mao_sat:
		_rows.append("mao_sat")
	_rows.append("start")
	for i in range(2):
		var side: Dictionary = GameState.player_side() if i == 0 else opponent
		var kit: StringName = Moves.kit_for_side(side)
		_kits.append(kit)
		var sprite := Sprite2D.new()
		sprite.texture = FighterView.sheet_for(kit)
		sprite.region_enabled = true
		sprite.centered = false
		sprite.offset = -FighterView.foot_for(kit)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.material = FighterView.material_for_side(side)
		_canvas.add_child(sprite)
		_views.append(sprite)


func run() -> bool:
	return await _done


func _process(delta: float) -> void:
	_time += delta
	var size: Vector2 = _canvas.size
	for i in range(2):
		var sprite: Sprite2D = _views[i]
		sprite.region_rect = FighterView.frame_region(FighterView.tag_frame_at("idle", int(_time * 60.0), true, _kits[i]))
		var breed: int = GameState.breed if i == 0 else int(opponent["breed"])
		var s: float = 3.2 * (0.9 if breed == 1 else 1.0)
		sprite.scale = Vector2(s if i == 0 else -s, s)
		sprite.position = Vector2(size.x * (0.22 if i == 0 else 0.78), size.y * 0.56)
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: int = (event as InputEventKey).physical_keycode
	get_viewport().set_input_as_handled()
	match code:
		KEY_W, KEY_UP:
			_index = posmod(_index - 1, _rows.size())
			_sfx.play(&"select", -8.0)
		KEY_S, KEY_DOWN:
			_index = posmod(_index + 1, _rows.size())
			_sfx.play(&"select", -8.0)
		KEY_ESCAPE:
			_done.emit(false)
		KEY_E, KEY_ENTER, KEY_SPACE, KEY_J, KEY_A, KEY_D:
			match _rows[_index]:
				"dao_chan":
					GameState.equip_dao_chan = not GameState.equip_dao_chan
					_sfx.play(&"select")
				"mao_sat":
					GameState.equip_mao_sat = not GameState.equip_mao_sat
					_sfx.play(&"select")
				"start":
					if code != KEY_A and code != KEY_D:
						_sfx.play(&"confirm")
						_done.emit(true)


func _text(pos: Vector2, text: String, size: int, color: Color = Color.WHITE,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, bold: bool = false) -> void:
	var font: Font = DialogBox.make_font(bold)
	_canvas.draw_string_outline(font, pos, text, align, width, size, 5, Color.BLACK)
	_canvas.draw_string(font, pos, text, align, width, size, color)


func _draw_screen() -> void:
	var size: Vector2 = _canvas.size
	var w: float = size.x
	var h: float = size.y
	# Nền chia đôi chéo.
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.06, 0.05))
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.56, 0), Vector2(w * 0.44, h), Vector2(0, h)]),
		Color(0.45, 0.12, 0.08))
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.56, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.44, h)]),
		Color(0.12, 0.18, 0.32))
	for i in range(18):
		var y: float = fmod(float(i) * 41.0 + _time * 60.0, h)
		_canvas.draw_line(Vector2(0, y), Vector2(w, y - 80.0), Color(1, 1, 1, 0.03), 8.0)
	_text(Vector2(0, 52), title, 34, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w, true)
	_text(Vector2(0, h * 0.5), "VS", 72, Color(1.0, 0.95, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w, true)

	# Gà người chơi.
	var me: Dictionary = GameState.scaled_stats(GameState.breed, GameState.level)
	var lx: float = 40.0
	_text(Vector2(lx, 110), GameState.chicken_name.to_upper(), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_text(Vector2(lx, 136), "%s · %s Lv%d" % [GameState.player_name, GameState.BREED_NAMES[GameState.breed], GameState.level], 17)
	var def_bonus: int = 2 if GameState.owns_mao_sat and GameState.equip_mao_sat else 0
	_text(Vector2(lx, h - 210), "HP %d   ATK %.1f   DEF %d   SPD %d" % [int(me["hp"]), float(me["atk"]), int(me["def"]) + def_bonus, int(me["spd"])], 17)
	var y: float = h - 176.0
	for i in range(_rows.size()):
		var row: String = _rows[i]
		var selected: bool = i == _index
		var text: String = ""
		match row:
			"dao_chan":
				text = "[%s] Dao chân – Light nhanh hơn, combo thêm 1 Light" % ("x" if GameState.equip_dao_chan else " ")
			"mao_sat":
				text = "[%s] Mào sắt – +2 DEF, giảm đẩy lùi khi trúng đòn cao" % ("x" if GameState.equip_mao_sat else " ")
			"start":
				text = "VÀO TRẬN!"
		var color: Color = Color(1.0, 0.85, 0.3) if selected else Color(0.85, 0.85, 0.85)
		_text(Vector2(lx, y), ("▶ " if selected else "   ") + text, 20 if row != "start" else 26, color,
			HORIZONTAL_ALIGNMENT_LEFT, -1, row == "start" or selected)
		y += 32.0
	var deck: PackedStringArray = []
	for card in GameState.cards:
		deck.append(String(GameState.CARD_INFO[card]["name"]))
	_text(Vector2(lx, h - 40), "Deck: %s" % (", ".join(deck) if not deck.is_empty() else "(chưa có thẻ)"), 16, Color(1.0, 0.85, 0.4))

	# Đối thủ.
	var rx: float = w - 40.0
	_text(Vector2(0, 110), String(opponent["name"]).to_upper(), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, rx, true)
	_text(Vector2(0, 136), "%s · %s Lv%d" % [String(opponent["owner"]), GameState.BREED_NAMES[int(opponent["breed"])], int(opponent["lv"])],
		17, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, rx)
	var notes: PackedStringArray = ["AI cấp T%d" % int(opponent.get("tier", 1))]
	if bool(opponent.get("mao_sat", false)):
		notes.append("gắn Mào sắt")
	if Moves.kit_for_side(opponent) == Moves.KIT_DONGTAO:
		notes.append("tank: lì đòn, Thiết Giáp, Húc Trâu có giáp")
	if bool(opponent.get("dao_chan", false)):
		notes.append("gắn Dao chân")
	if (opponent.get("cards", []) as Array).has(&"mai_rua"):
		notes.append("có thẻ Mai Rùa")
	_text(Vector2(0, h - 210), " · ".join(notes), 17, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, rx)
	_text(Vector2(0, h - 40), "[W/S] chọn · [E] bật/tắt · [Esc] quay lại", 15, Color(0.7, 0.7, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, rx)
