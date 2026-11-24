class_name EscapeCutscene
extends Node2D

## Cắt cảnh kết màn tẩu thoát (~30 giây): bếp nhà lúc chạng vạng. Nhân vật chính đứng quay lưng rửa chén ở bồn,
## thở hổn hển rồi giả bộ bình tĩnh; gà (nòi/tre hay Đông Tảo theo con đang chọn) ngồi im re trong rổ giữa đống
## chén, chớp mắt một cái. Có tiếng đập cửa, hai chú công an xông vô hỏi; nhân vật không quay lại, vừa lau chén
## vừa chỉ ra cửa sau: "Dạ… nó chạy ra hướng bến đò rồi mấy chú!" – hai chú chạy ra hướng ngược lại (cửa đóng cái
## rầm, tiếng còi xa dần). Gà ló đầu lên cục tác. Tiếng Mẹ ngoài nhà: "Ủa, bữa nay sao siêng dữ vậy con?" Tắt dần.
## Căn bếp: nếu res://game/home/home_scene.gd có build_interior() (tĩnh, trả Node2D có con "Actors" y-sort) thì dùng
## nội thất nhà thật (nhìn từ trên xuống, đứng cạnh thau rửa chén ở HomeScene.SINK_POS; công an từ cửa chính đi xuống
## lối gạch vô bếp – chạy ra cửa hông ra sân gà, HomeScene.SIDE_DOOR); thiếu/lỗi thì dùng hoạ sĩ riêng (_paint_kitchen: bếp nhìn ngang như sân khấu). Chọn tay bằng
## setup({"interior": "painter"}). Camera riêng, khung thoại riêng (font DialogBox.make_font).
## E / J / Space / Enter: hiện hết chữ / câu tiếp; Esc: bỏ qua cả cảnh.
## Dùng: var cut := EscapeCutscene.new(); cut.setup({"chicken": GameState.active_chicken()}); add_child(cut)
##       var r: Dictionary = await cut.play()   # {"skipped": bool, "time": float}; cảnh tự queue_free() khi xong.
## Chưa add vào cây thì play() tự gắn vào root. Test: auto_advance = true (tự sang câu), press(&"next"/&"skip").

signal _tick_done
signal finished(result: Dictionary)

const Art := preload("res://game/escape/escape_art.gd")
const EscSfx := preload("res://game/escape/escape_sfx.gd")
const Audio := preload("res://game/audio/audio_director.gd")
const HOME_SCENE_PATH: String = "res://game/home/home_scene.gd"
## Tên hàm dựng nội thất có thể có trong home_scene.gd (tĩnh, trả Node2D) – thử lần lượt.
const HOME_BUILDERS: Array[String] = ["build_interior", "make_interior", "build_kitchen", "make_kitchen"]

const ZOOM: float = 3.0
const VIEW := Vector2(427, 240)
const FLOOR_Y: float = 176.0
const HERO_POS := Vector2(222, 194)
const COUNTER_TOP: float = 160.0
const FRONT_DOOR := Rect2(34, 104, 36, 72)
const BACK_DOOR := Rect2(362, 104, 34, 72)
const BASKET_POS := Vector2(268, 160)
const CHARS_PER_SECOND: float = 50.0
## Thời gian đọc thêm (auto_advance) = auto_time × hệ số này.
const AUTO_SCALE: float = 0.65

var chicken: Dictionary = {}
var auto_advance: bool = false
var interior_source: String = "painter"   # "painter" hoặc "home_scene"
var interior_request: String = "auto"     # "auto" (nhà thật nếu có) / "painter"

var _variant: String = "noi"
var _chicken_name: String = "Gà"
var _hero_name: String = "Tư Gà"
var _time: float = 0.0
var _wait_left: float = 0.0
var _waiting: bool = false
var _skipping: bool = false
var _advance: bool = false
var _playing: bool = false
var _done: bool = false
var _rng := RandomNumberGenerator.new()

# Trạng thái diễn.
var _hero_mode: String = "wash_fast"      # wash_fast / wash / point / still
var _breath: float = 1.0                  # 1 = thở dốc, 0 = bình tĩnh
var _front_open: float = 0.0
var _back_open: float = 0.0
var _door_shake: float = 0.0
var _cops: Array[Dictionary] = []         # {pos, path: Array[Vector2], mode: run/front/talk/scratch, row, travel}
var _layout: Dictionary = {}              # vị trí diễn theo nội thất đang dùng (xem _make_layout)
var _rooster_peek: float = 0.0
var _rooster_blink: float = 0.0
var _plates: int = 3
var _wash_tick: float = 0.0
var _bubbles: Array[Dictionary] = []
var _fade: float = 1.0
var _fade_target: float = 0.0
var _fx_text: String = ""
var _fx_text_time: float = 0.0
var _pant_cool: float = 0.0
var _whistle_fade: float = -1.0

var _room: Node2D
var _actors: Node2D                       # nơi gắn diễn viên (y-sort): của mình hoặc "Actors" của nội thất nhà
var _hero_actor: Node2D
var _basket_actor: Node2D
var _cop_actors: Array[Node2D] = []
var _fx_node: Node2D
var _light: Node2D
var _home_node: Node2D
var _camera: Camera2D
var _prev_camera: Camera2D
var _ui: CanvasLayer
var _panel: PanelContainer
var _portrait_box: PanelContainer
var _portrait: TextureRect
var _speaker: Label
var _text: Label
var _hint: Label
var _caption: Label
var _black: ColorRect
var _sfx: Node


func setup(options: Dictionary = {}) -> void:
	chicken = options.get("chicken", {}) if options.get("chicken", {}) is Dictionary else {}
	auto_advance = bool(options.get("auto_advance", auto_advance))
	interior_request = String(options.get("interior", interior_request))


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = 2024
	_variant = Art.variant_for(chicken)
	_chicken_name = String(chicken.get("name", "")).strip_edges()
	if _chicken_name == "":
		_chicken_name = "Gà"
	_hero_name = String(GameState.player_name).strip_edges()
	if _hero_name == "":
		_hero_name = "Tư Gà"
	_prev_camera = get_viewport().get_camera_2d()
	_sfx = EscSfx.new()
	add_child(_sfx)
	_room = Node2D.new()
	_room.draw.connect(_paint_kitchen)
	add_child(_room)
	if interior_request != "painter":
		_home_node = _try_home_interior()
	if _home_node != null:
		interior_source = "home_scene"
		add_child(_home_node)
		_actors = _home_node.get_node_or_null(^"Actors") as Node2D
	if _actors == null:
		_actors = Node2D.new()
		_actors.y_sort_enabled = true
		add_child(_actors)
	_layout = _make_layout()
	_basket_actor = _make_actor(_draw_basket_actor)
	if _home_node != null:
		_basket_actor.z_index = 1   # rổ gà nằm TRÊN mặt bàn bếp (ảnh bếp có gốc y-sort thấp hơn)
	_hero_actor = _make_actor(_draw_hero_actor)
	for k in range(2):
		var cop: Node2D = _make_actor(_draw_cop_actor.bind(k))
		cop.visible = false
		_cop_actors.append(cop)
	_fx_node = Node2D.new()
	_fx_node.z_index = 5
	_fx_node.draw.connect(_draw_fx)
	add_child(_fx_node)
	_light = Node2D.new()
	_light.z_index = 10
	_light.draw.connect(_draw_light)
	add_child(_light)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(ZOOM, ZOOM)
	_camera.position = _layout["camera"]
	add_child(_camera)
	_camera.make_current()
	_build_ui()


func _exit_tree() -> void:
	if is_instance_valid(_prev_camera) and _prev_camera.is_inside_tree() and _prev_camera != _camera:
		_prev_camera.make_current()


func _make_actor(painter: Callable) -> Node2D:
	var node := Node2D.new()
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.draw.connect(painter)
	_actors.add_child(node)
	return node


## Vị trí diễn: người rửa chén, rổ gà, bồn (bọt xà bông), chồng chén, camera, đường đi của hai chú công an.
func _make_layout() -> Dictionary:
	if _home_node == null:
		return {
			"hero": HERO_POS, "basket": BASKET_POS, "basin": Vector2(223, COUNTER_TOP - 2.0), "basin_r": 13.0,
			"plates": Vector2(178, COUNTER_TOP - 4.0), "camera": Vector2(VIEW.x * 0.5, 156.0), "glow": Vector2(222, 92),
			"lamp": true, "cop_start": [Vector2(46, 192), Vector2(28, 196)], "cop_stand": [Vector2(150, 192), Vector2(120, 196)],
			"cop_exit": [[Vector2(440, 192)], [Vector2(440, 196)]],
		}
	var consts: Dictionary = (load(HOME_SCENE_PATH) as Script).get_script_constant_map()
	var sink: Vector2 = consts.get("SINK_POS", Vector2(382, 551))
	var basin: Vector2 = consts.get("SINK_BASIN", sink + Vector2(-21, -17))
	var side: Vector2 = consts.get("SIDE_DOOR", Vector2(324, 480))
	# Nhà vẽ tay (nhìn từ trên): thau rửa chén sát vách dưới bếp; công an từ gian thờ (cửa chính) đi xuống lối gạch
	# x≈576..640 vô bếp, đứng bên phải người rửa chén; chạy ra cửa hông bếp (vách trái, y≈448..512) ra sân gà – mái hiên che dần.
	return {
		"hero": sink, "basket": sink + Vector2(25, -2), "basin": basin, "basin_r": 9.0,
		"plates": Vector2(-1000, -1000), "camera": Vector2(470, 505), "glow": Vector2(400, 500), "lamp": false,
		"cop_start": [Vector2(600, 300), Vector2(624, 292)],
		# vô: xuống lối gạch → khe giữa phản ăn cơm và khạp gạo → đứng bên phải người rửa chén
		"cop_in": [[Vector2(600, 446), Vector2(540, 446), Vector2(540, 548)],
			[Vector2(624, 440), Vector2(544, 440), Vector2(544, 544)]],
		"cop_stand": [sink + Vector2(48, -3), sink + Vector2(94, -5)],
		# ra: vòng lại khe phản/khạp → dọc trước bếp củi → cửa hông → sân gà (khuất dưới mái hiên)
		"cop_exit": [[Vector2(540, 548), Vector2(540, 448), Vector2(352, 452), side + Vector2(0, -4), side + Vector2(-80, -2)],
			[Vector2(546, 546), Vector2(546, 442), Vector2(356, 446), side + Vector2(0, 6), side + Vector2(-90, 10)]],
	}


## Nội thất từ home_scene.gd nếu có hàm dựng (tĩnh) trả về Node2D; lỗi/thiếu → null (dùng hoạ sĩ riêng).
func _try_home_interior() -> Node2D:
	if not ResourceLoader.exists(HOME_SCENE_PATH):
		return null
	var script: Script = load(HOME_SCENE_PATH) as Script
	if script == null:
		return null
	var names: Dictionary = {}
	for m in script.get_script_method_list():
		names[String(m.get("name", ""))] = int(m.get("flags", 0))
	for builder in HOME_BUILDERS:
		if not names.has(builder):
			continue
		if (int(names[builder]) & METHOD_FLAG_STATIC) == 0:
			continue
		var made: Variant = script.call(builder)
		if made is Node2D:
			return made
		if made is Node:
			(made as Node).queue_free()
	return null


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 55
	add_child(_ui)
	_black = ColorRect.new()
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_black)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.offset_left = -500.0
	_caption.offset_right = 500.0
	_caption.offset_top = 40.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", DialogBox.make_font(true))
	_caption.add_theme_font_size_override("font_size", UISkin.FS_BIG)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	UISkin.label_shadow(_caption, 8, Color.BLACK)
	_caption.visible = false
	_ui.add_child(_caption)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 40.0
	_panel.offset_right = -40.0
	_panel.offset_top = -196.0
	_panel.offset_bottom = -16.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.add_theme_stylebox_override("panel", UISkin.panel_style(&"dark", 6.0))
	UISkin.pixel(_panel)
	_ui.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_panel.add_child(row)
	_portrait_box = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.32, 0.5, 0.36)
	ps.border_color = Color(0.95, 0.75, 0.3)
	ps.set_border_width_all(2)
	_portrait_box.add_theme_stylebox_override("panel", ps)
	_portrait_box.custom_minimum_size = Vector2(96, 108)
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
	_speaker.add_theme_font_override("font", DialogBox.make_font(true))
	_speaker.add_theme_font_size_override("font_size", UISkin.FS_BODY)
	box.add_child(_speaker)
	_text = Label.new()
	_text.add_theme_font_override("font", DialogBox.make_font(false))
	_text.add_theme_font_size_override("font_size", UISkin.FS_BODY)
	_text.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text)
	_hint = Label.new()
	_hint.add_theme_font_override("font", DialogBox.make_font(true))
	_hint.add_theme_font_size_override("font_size", UISkin.FS_SMALL)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.text = "[E] tiếp    [Esc] bỏ qua"
	box.add_child(_hint)
	_panel.visible = false


# ================================================================== kịch bản

func play() -> Dictionary:
	if not is_inside_tree():
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return {"skipped": true, "time": 0.0}
		tree.root.add_child(self)
	if _playing or _done:
		return {"skipped": _skipping, "time": _time}
	_playing = true
	Audio.music(&"", 1.5)
	Audio.ambience({&"crickets": 0.5, &"village": 0.15}, 1.5)
	_fade = 1.0
	_fade_target = 0.0
	await _script()
	# Tắt dần.
	_panel.visible = false
	_caption.visible = false
	_fade_target = 1.0
	await _wait(0.3 if _skipping else 1.2, true)
	var r: Dictionary = {"skipped": _skipping, "time": snappedf(_time, 0.01), "interior": interior_source}
	_playing = false
	_done = true
	finished.emit(r)
	queue_free()
	return r


func _script() -> void:
	var cop_a: String = "Chú công an"
	var cop_b: String = "Chú công an mập"
	_hero_mode = "wash_fast"
	_breath = 1.0
	await _wait(1.0)
	if _skipping: return
	await _say("", "(Hộc… hộc… Rửa chén. Rửa chén. Hộc…)", 2.4)
	if _skipping: return
	_hero_mode = "wash"
	await _say(_hero_name, "Phù… bình tĩnh… Mình đang rửa chén. Mình rửa chén từ trưa tới giờ.", 3.0)
	if _skipping: return
	_breath = 0.0
	await _wait(0.6)
	if _skipping: return
	# Đập cửa.
	for k in range(2):
		_sfx.call("play", &"knock", 0.0)
		_door_shake = 0.7
		_show_fx_text("CỘC! CỘC! CỘC!", 0.8)
		await _wait(0.85)
		if _skipping: return
	_hero_mode = "still"
	await _wait(0.4)
	if _skipping: return
	# Xông vô.
	_front_open = 1.0
	_sfx.call("play", &"slam", 0.0)
	_sfx.call("play", &"whistle", -4.0)
	_cops = []
	for k in range(2):
		var path: Array = []
		if _layout.has("cop_in"):
			path.append_array(((_layout["cop_in"] as Array)[k] as Array))   # lối đi vòng trong nhà vẽ tay
		path.append((_layout["cop_stand"] as Array)[k])
		_cops.append({"pos": (_layout["cop_start"] as Array)[k], "path": path,
			"mode": "run", "row": k, "travel": float(k) * 5.0})
	await _wait_cops()
	if _skipping: return
	for c in _cops:
		c["mode"] = "front"
	_hero_mode = "wash"
	await _wait(0.4)
	if _skipping: return
	_cops[0]["mode"] = "talk"
	await _say(cop_a, "Công an đây! Nãy giờ có thấy thằng nhỏ nào ôm con gà chạy ngang đây hông?!", 3.4, 0)
	if _skipping: return
	_cops[0]["mode"] = "front"
	_cops[1]["mode"] = "talk"
	await _say(cop_b, "Áo sọc đỏ, đội nón… ờ… nhìn sau lưng giống giống… ai đó!", 3.0, 1)
	if _skipping: return
	_cops[1]["mode"] = "front"
	_rooster_blink = 0.25
	_sfx.call("play", &"clink", -8.0)
	await _wait(0.6)
	if _skipping: return
	_hero_mode = "point"
	await _say(_hero_name, "Dạ… nó chạy ra hướng bến đò rồi mấy chú!", 2.8, -1, true)
	if _skipping: return
	_cops[0]["mode"] = "talk"
	await _say(cop_a, "Cảm ơn nghen! Đi! Đi!", 1.6, 0)
	if _skipping: return
	# Chạy ra cửa sau (hướng ngược với bến đò).
	_hero_mode = "wash"
	_back_open = 1.0
	_sfx.call("play", &"whistle", -4.0)
	for k in range(_cops.size()):
		_cops[k]["path"] = ((_layout["cop_exit"] as Array)[k] as Array).duplicate()
		_cops[k]["mode"] = "run"
	await _wait_cops()
	if _skipping: return
	_back_open = 0.0
	_sfx.call("play", &"slam", -2.0)
	_cops.clear()
	_whistle_fade = 0.0
	await _wait(1.4)
	if _skipping: return
	# Gà ló đầu lên.
	_rooster_peek = 1.0
	_sfx.call("play", &"cluck", -2.0)
	await _say(_chicken_name, "Cục tác! (Hết hồn hà…)", 1.8, -2)
	if _skipping: return
	await _say("Mẹ", "(ngoài nhà) Ủa, bữa nay sao siêng dữ vậy con? Chén sạch bóng luôn kìa!", 3.2, -3)
	if _skipping: return
	_rooster_peek = 0.0
	await _say(_hero_name, "Dạ… con… con siêng từ hồi nào tới giờ mà má!", 2.6)


## Chờ seconds (tính theo _process). force = chờ cả khi đang bỏ qua (để tắt dần).
func _wait(seconds: float, force: bool = false) -> void:
	if _skipping and not force:
		return
	_wait_left = seconds
	_waiting = true
	while _waiting:
		await _tick_done
		if _skipping and not force:
			_waiting = false


func _wait_cops() -> void:
	while not _skipping:
		var moving: bool = false
		for c in _cops:
			if not (c["path"] as Array).is_empty():
				moving = true
		if not moving:
			return
		await _tick_done


## Một câu thoại: chữ chạy; E hiện hết / sang câu; auto_advance tự sang sau auto_time + thời gian chạy chữ.
## portrait: 0/1 = công an (cao/mập), −1 = nhân vật chính, −2 = gà, −3 = không có (người ngoài khung hình).
func _say(speaker: String, line: String, auto_time: float, portrait: int = -1, point_line: bool = false) -> void:
	if _skipping:
		return
	_panel.visible = true
	_speaker.text = speaker if speaker != "" else " "
	_speaker.add_theme_color_override("font_color", _speaker_color(speaker))
	_text.text = line
	_text.visible_ratio = 0.0
	_set_portrait(speaker, portrait)
	_advance = false
	var shown_for: float = 0.0
	var total: float = float(maxi(line.length(), 1))
	while not _skipping:
		await _tick_done
		var dt: float = get_process_delta_time() if is_inside_tree() else 1.0 / 60.0
		if _text.visible_ratio < 1.0:
			_text.visible_ratio = minf(1.0, _text.visible_ratio + dt * CHARS_PER_SECOND / total)
			if _advance:
				_advance = false
				_text.visible_ratio = 1.0
			continue
		shown_for += dt
		if _advance or (auto_advance and shown_for >= auto_time * AUTO_SCALE):
			_advance = false
			break
	if point_line:
		_hero_mode = "point"
	_panel.visible = false


func _speaker_color(speaker: String) -> Color:
	if speaker == "Mẹ":
		return Color(1.0, 0.7, 0.75)
	if speaker.begins_with("Chú công an"):
		return Color(0.7, 0.9, 0.55)
	if speaker == _chicken_name:
		return Color(1.0, 0.6, 0.4)
	return Color(1.0, 0.85, 0.5)


func _set_portrait(speaker: String, which: int) -> void:
	var tex: Texture2D = null
	if speaker == "":
		which = -3
	match which:
		0, 1:
			tex = Art.police(which, 4)
			if tex != null:
				var a := AtlasTexture.new()
				a.atlas = (tex as AtlasTexture).atlas
				var r: Rect2 = (tex as AtlasTexture).region
				a.region = Rect2(r.position + Vector2(6, 0), Vector2(20, 26 if which == 0 else 32))
				tex = a
		-1:
			var portrait_path: String = "res://game/art/player_sheet_v2_portrait.png"   # chân dung nhân vật chính bản mới
			tex = load(portrait_path) if ResourceLoader.exists(portrait_path) else null
		-2:
			tex = Art.rooster(_variant, false)
	_portrait.texture = tex
	_portrait_box.visible = tex != null


func _show_fx_text(text: String, seconds: float) -> void:
	_fx_text = text
	_fx_text_time = seconds
	_caption.text = text
	_caption.visible = true


# ================================================================== điều khiển

func press(action: StringName) -> void:
	if not _playing:
		return
	if action == &"skip":
		if not _skipping:
			_skipping = true
			_waiting = false
	elif action == &"next":
		_advance = true


func _unhandled_input(event: InputEvent) -> void:
	if not _playing or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_E, KEY_J, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			press(&"next")
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			press(&"skip")


func _process(delta: float) -> void:
	_time += delta
	if _waiting:
		_wait_left -= delta
		if _wait_left <= 0.0:
			_waiting = false
	_fade = move_toward(_fade, _fade_target, delta * (3.0 if _skipping else 1.1))
	_black.color.a = _fade
	_door_shake = maxf(_door_shake - delta, 0.0)
	_rooster_blink = maxf(_rooster_blink - delta, 0.0)
	if _fx_text_time > 0.0:
		_fx_text_time -= delta
		_caption.visible = _fx_text_time > 0.0
	# Diễn viên.
	for c in _cops:
		var path: Array = c["path"]
		if path.is_empty():
			continue
		var pos: Vector2 = c["pos"]
		var step: float = 120.0 * delta
		pos = pos.move_toward(path[0], step)
		c["travel"] = float(c["travel"]) + step
		if pos.distance_to(path[0]) < 0.5:
			pos = path[0]
			path.pop_front()
		c["pos"] = pos
	# Rửa chén: chén sạch chồng lên dần, bọt xà bông bay lên.
	if _hero_mode == "wash" or _hero_mode == "wash_fast":
		_wash_tick += delta * (2.2 if _hero_mode == "wash_fast" else 1.0)
		if _wash_tick > 1.6:
			_wash_tick = 0.0
			_plates = mini(_plates + 1, 9)
			_sfx.call("play", &"clink", -12.0, _rng.randf_range(0.9, 1.15))
		if _rng.randf() < delta * (9.0 if _hero_mode == "wash_fast" else 4.0):
			var basin: Vector2 = _layout["basin"]
			var br: float = float(_layout["basin_r"])
			_bubbles.append({"p": basin + Vector2(_rng.randf_range(-br, br), 0.0), "life": _rng.randf_range(0.8, 1.6), "r": _rng.randf_range(1.0, 2.5)})
	var kept: Array[Dictionary] = []
	for b in _bubbles:
		b["life"] = float(b["life"]) - delta
		if float(b["life"]) <= 0.0:
			continue
		b["p"] = (b["p"] as Vector2) + Vector2(sin(_time * 3.0 + float(b["r"]) * 5.0) * 6.0 * delta, -10.0 * delta)
		kept.append(b)
	_bubbles = kept
	# Thở dốc.
	if _breath > 0.5 and _playing:
		_pant_cool -= delta
		if _pant_cool <= 0.0:
			_pant_cool = 0.95
			_sfx.call("play", &"pant", -6.0)
	if _whistle_fade >= 0.0:
		_whistle_fade += delta
		if fmod(_whistle_fade, 0.8) < delta and _whistle_fade < 2.2:
			_sfx.call("play", &"whistle", -10.0 - _whistle_fade * 9.0)
	# Chớp mắt ngẫu nhiên (một lần mỗi ~4 s) – gà "giả tượng".
	if _rooster_blink <= 0.0 and fmod(_time, 4.3) < delta:
		_rooster_blink = 0.18
	_room.queue_redraw()
	_hero_actor.position = _layout["hero"]
	_hero_actor.queue_redraw()
	_basket_actor.position = _layout["basket"]
	_basket_actor.queue_redraw()
	for k in range(_cop_actors.size()):
		_cop_actors[k].visible = k < _cops.size()
		if k < _cops.size():
			_cop_actors[k].position = (_cops[k]["pos"] as Vector2).round()
			_cop_actors[k].queue_redraw()
	_fx_node.queue_redraw()
	_light.queue_redraw()
	_tick_done.emit()


# ================================================================== hoạ sĩ căn bếp

func _paint_kitchen() -> void:
	var g := _room
	if _home_node != null:
		# Ngoài nhà (quanh nội thất): sân tối lúc chạng vạng.
		g.draw_rect(Rect2(-200, -200, 1400, 1000), Color(0.08, 0.07, 0.1))
		return
	# Vách ván + kèo.
	var wall := Color(0.42, 0.29, 0.2)
	g.draw_rect(Rect2(-20, -20, VIEW.x + 40, FLOOR_Y + 20), wall)
	for k in range(-2, int(VIEW.x / 14.0) + 3):
		var x: float = float(k) * 14.0
		g.draw_rect(Rect2(x, 0, 1, FLOOR_Y), wall.darkened(0.25))
		var h: int = Art.hash_i(k, 7)
		g.draw_rect(Rect2(x + 4.0 + float(h % 6), 20.0 + float((h >> 4) % 120), 1, 6), wall.darkened(0.15))
	g.draw_rect(Rect2(-20, 0, VIEW.x + 40, 10), Color(0.3, 0.2, 0.14))
	g.draw_rect(Rect2(-20, 10, VIEW.x + 40, 2), Color(0.22, 0.14, 0.1))
	for k in range(5):
		g.draw_rect(Rect2(20.0 + float(k) * 96.0, 0, 6, 14), Color(0.25, 0.16, 0.1))
	# Nền đất nện.
	g.draw_rect(Rect2(-20, FLOOR_Y, VIEW.x + 40, VIEW.y - FLOOR_Y + 90), Color(0.46, 0.36, 0.27))
	g.draw_rect(Rect2(-20, FLOOR_Y, VIEW.x + 40, 2), Color(0.3, 0.22, 0.16))
	for k in range(40):
		var h: int = Art.hash_i(k, 11)
		g.draw_rect(Rect2(float(h % int(VIEW.x)), FLOOR_Y + 4.0 + float((h >> 9) % 100), 2.0 + float((h >> 3) % 3), 1), Color(0.4, 0.31, 0.23))
	# Cửa sổ trên bồn rửa: trời chạng vạng + hàng dừa.
	var win := Rect2(196, 58, 56, 40)
	var sky: Array[Color] = [Color(0.3, 0.27, 0.5), Color(0.55, 0.36, 0.52), Color(0.86, 0.5, 0.4), Color(0.98, 0.7, 0.42)]
	for k in range(4):
		g.draw_rect(Rect2(win.position.x, win.position.y + float(k) * 10.0, win.size.x, 10.0), sky[k])
	for k in range(3):
		var tx: float = win.position.x + 10.0 + float(k) * 18.0
		g.draw_line(Vector2(tx, win.end.y), Vector2(tx + 3.0, win.position.y + 14.0 + float(k) * 4.0), Color(0.12, 0.1, 0.16), 1.0)
		g.draw_rect(Rect2(tx - 3.0, win.position.y + 13.0 + float(k) * 4.0, 13.0, 2.0), Color(0.12, 0.1, 0.16))
	g.draw_rect(Rect2(win.position.x, win.end.y - 6.0, win.size.x, 6.0), Color(0.12, 0.1, 0.16))
	for k in range(5):
		g.draw_rect(Rect2(win.position.x + 4.0 + float(k) * 12.0, win.position.y, 2.0, win.size.y), Color(0.3, 0.2, 0.12))
	g.draw_rect(win.grow(3.0), Color(0.28, 0.18, 0.12), false, 3.0)
	# Kệ chén bát, nồi treo, lịch tờ.
	g.draw_rect(Rect2(272, 70, 70, 3), Color(0.3, 0.2, 0.12))
	for k in range(5):
		var px: float = 276.0 + float(k) * 13.0
		g.draw_rect(Rect2(px, 62, 10, 8), Color(0.82, 0.84, 0.86) if k % 2 == 0 else Color(0.55, 0.3, 0.22))
	for k in range(3):
		var cx: float = 110.0 + float(k) * 22.0
		g.draw_line(Vector2(cx, 40), Vector2(cx, 52), Color(0.2, 0.15, 0.12), 1.0)
		g.draw_circle(Vector2(cx, 60), 8.0 - float(k), Color(0.6, 0.62, 0.66) if k != 1 else Color(0.25, 0.22, 0.24))
	g.draw_rect(Rect2(150, 80, 22, 28), Color(0.96, 0.94, 0.88))
	g.draw_rect(Rect2(150, 80, 22, 7), Color(0.85, 0.2, 0.18))
	g.draw_rect(Rect2(155, 92, 12, 9), Color(0.85, 0.2, 0.18))
	# Cửa trước (trái) – bung ra khi công an xông vô.
	_paint_door(FRONT_DOOR, _front_open, -1.0, _door_shake)
	# Cửa sau (phải) – mở ra sân sau lúc tối.
	_paint_door(BACK_DOOR, _back_open, 1.0, 0.0)
	# Lu nước + bếp củi góc phải, rổ rá.
	Art.stand(g, Art.prop("jar_b"), Vector2(330, 184))
	Art.stand(g, Art.prop("jar"), Vector2(348, 186))
	g.draw_rect(Rect2(296, 150, 30, 28), Color(0.55, 0.4, 0.3))
	g.draw_rect(Rect2(300, 166, 22, 10), Color(0.18, 0.1, 0.08))
	g.draw_rect(Rect2(304, 168, 14, 5), Color(0.95, 0.45, 0.15, 0.7 + 0.2 * sin(_time * 7.0)))
	g.draw_circle(Vector2(311, 146), 9.0, Color(0.2, 0.18, 0.2))
	# Bàn bếp (bồn rửa): mặt gỗ, thau nhôm, chồng chén.
	var counter := Rect2(168, COUNTER_TOP, 120, 30)
	g.draw_rect(counter, Color(0.5, 0.34, 0.2))
	g.draw_rect(Rect2(counter.position.x - 2.0, COUNTER_TOP - 3.0, counter.size.x + 4.0, 4.0), Color(0.62, 0.44, 0.26))
	for k in range(4):
		g.draw_rect(Rect2(counter.position.x + 4.0 + float(k) * 30.0, COUNTER_TOP + 4.0, 1, 22), Color(0.38, 0.25, 0.15))
	g.draw_rect(Rect2(204, COUNTER_TOP - 9.0, 38, 7), Color(0.72, 0.75, 0.78))
	g.draw_rect(Rect2(204, COUNTER_TOP - 9.0, 38, 1), Color(0.9, 0.92, 0.95))
	g.draw_rect(Rect2(206, COUNTER_TOP - 8.0, 34, 2), Color(0.85, 0.9, 0.95))
	# Chồng chén sạch (cao dần khi rửa).
	var plates: Vector2 = _layout.get("plates", Vector2(178, COUNTER_TOP - 4.0))
	for k in range(_plates):
		var py: float = plates.y - float(k) * 2.0
		g.draw_rect(Rect2(plates.x, py, 18, 2), Color(0.95, 0.96, 0.97) if k % 2 == 0 else Color(0.85, 0.88, 0.9))
		g.draw_rect(Rect2(plates.x + 3.0, py + 1.0, 12, 1), Color(0.35, 0.55, 0.8))
	# Chén dơ chờ rửa bên kia.
	for k in range(3):
		g.draw_rect(Rect2(246 + k * 3, COUNTER_TOP - 5.0 - float(k) * 2.0, 10, 2), Color(0.8, 0.78, 0.7))


func _paint_door(r: Rect2, open: float, hinge_side: float, shake: float) -> void:
	var g := _room
	g.draw_rect(r.grow(3.0), Color(0.24, 0.15, 0.1))
	# Bên ngoài: sân lúc chạng vạng.
	g.draw_rect(r, Color(0.22, 0.22, 0.36))
	g.draw_rect(Rect2(r.position.x, r.end.y - 20.0, r.size.x, 20.0), Color(0.16, 0.22, 0.18))
	g.draw_rect(Rect2(r.position.x + 4.0, r.position.y + 8.0, 2.0, 2.0), Color(1.0, 0.95, 0.7, 0.8))
	var dx: float = roundf(sin(_time * 60.0) * 1.0) if shake > 0.0 else 0.0
	var w: float = roundf(r.size.x * (1.0 - 0.8 * open))
	var x: float = r.position.x if hinge_side < 0.0 else r.end.x - w
	var leaf := Rect2(x + dx, r.position.y, w, r.size.y)
	g.draw_rect(leaf, Color(0.36, 0.5, 0.42))
	if w > 6.0:
		for k in range(3):
			g.draw_rect(Rect2(leaf.position.x + 3.0, leaf.position.y + 6.0 + float(k) * 22.0, leaf.size.x - 6.0, 16.0), Color(0.3, 0.42, 0.36))
		g.draw_rect(Rect2(leaf.end.x - 6.0 if hinge_side < 0.0 else leaf.position.x + 3.0, leaf.position.y + 38.0, 3.0, 3.0), Color(0.85, 0.7, 0.3))


# ================================================================== diễn viên

func _draw_basket_actor() -> void:
	# Gà trong rổ (vẽ trước để thành rổ che nửa dưới) – ngồi im re như tượng, thỉnh thoảng chớp mắt.
	var a := _basket_actor
	var peek: float = roundf(_rooster_peek * 5.0)
	var rt: Texture2D = Art.rooster(_variant, _rooster_blink > 0.0)
	Art.stand(a, rt, Vector2(0, 4.0 - peek), true)
	_draw_basket(a, Vector2.ZERO)


func _draw_hero_actor() -> void:
	var a := _hero_actor
	var frame: String = "stand"
	var bob: float = 0.0
	match _hero_mode:
		"wash_fast":
			frame = ["wash0", "wash1", "wash2", "wash1"][int(_time * 9.0) % 4]
		"wash":
			frame = ["wash0", "wash1", "wash2", "wash1"][int(_time * 4.0) % 4]
		"point":
			frame = "point"
		_:
			frame = "wash0"
	if _breath > 0.5:
		bob = -1.0 if int(_time * 3.2) % 2 == 0 else 0.0
	Art.ellipse(a, Vector2(0, -1), 10.0, 1.0, Color(0, 0, 0, 0.25))
	Art.hero_at(a, Art.hero_back(frame), Vector2(0, bob))


func _draw_cop_actor(k: int) -> void:
	if k >= _cops.size():
		return
	var a := _cop_actors[k]
	var c: Dictionary = _cops[k]
	var col: int = 4
	match String(c["mode"]):
		"run":
			col = int(float(c["travel"]) / 9.0) % 4
		"talk":
			col = 5 if int(_time * 6.0) % 2 == 0 else 4
		"scratch":
			col = 6
	Art.ellipse(a, Vector2.ZERO, 8.0, 1.0, Color(0, 0, 0, 0.25))
	Art.police_at(a, Art.police(int(c["row"]), col), Vector2.ZERO)


## Bọt xà bông bay lên từ bồn rửa (trên mọi diễn viên).
func _draw_fx() -> void:
	for b in _bubbles:
		var p: Vector2 = (b["p"] as Vector2).round()
		var r: float = float(b["r"])
		_fx_node.draw_arc(p, r, 0.0, TAU, 8, Color(0.95, 0.98, 1.0, 0.8), 1.0)
		_fx_node.draw_rect(Rect2(p + Vector2(-r * 0.5, -r * 0.5), Vector2(1, 1)), Color(1, 1, 1, 0.9))


func _draw_basket(a: Node2D, foot: Vector2) -> void:
	var rim := Color(0.62, 0.46, 0.24)
	var body := Rect2(foot.x - 11.0, foot.y - 6.0, 22.0, 6.0)
	a.draw_rect(body, Color(0.78, 0.6, 0.32))
	for k in range(0, 22, 3):
		a.draw_rect(Rect2(body.position.x + float(k), body.position.y, 1.0, body.size.y), rim)
	a.draw_rect(Rect2(body.position.x - 1.0, body.position.y - 1.0, body.size.x + 2.0, 2.0), rim)
	# Hai cái chén úp kế bên cho "ngụy trang".
	a.draw_rect(Rect2(foot.x + 13.0, foot.y - 3.0, 9.0, 3.0), Color(0.92, 0.93, 0.95))
	a.draw_rect(Rect2(foot.x + 14.0, foot.y - 4.0, 7.0, 1.0), Color(0.35, 0.55, 0.8))


# ================================================================== ánh sáng chạng vạng

func _draw_light() -> void:
	var l := _light
	# Tối dần toàn cảnh, đèn bóng tròn trên bồn rửa + ánh lửa bếp.
	var cam: Vector2 = _layout["camera"]
	l.draw_rect(Rect2(cam - VIEW * 0.5 - Vector2(20, 20), VIEW + Vector2(40, 40)), Color(0.1, 0.06, 0.18, 0.24))
	var glow: Vector2 = _layout["glow"]
	if bool(_layout["lamp"]):
		var lamp := Vector2(glow.x, 54)
		l.draw_line(Vector2(lamp.x, 0), lamp, Color(0.1, 0.08, 0.08), 1.0)
		l.draw_circle(lamp + Vector2(0, 4), 4.0, Color(1.0, 0.92, 0.6))
		l.draw_circle(Vector2(311, 170), 20.0, Color(1.0, 0.5, 0.2, 0.07 + 0.03 * sin(_time * 7.0)))
	for k in range(5):
		l.draw_circle(glow, 70.0 - float(k) * 12.0, Color(1.0, 0.85, 0.5, 0.035))
	# Dấu "!" trên đầu gà khi cục tác.
	if _rooster_peek > 0.0:
		l.draw_string(DialogBox.make_font(true), (_layout["basket"] as Vector2) + Vector2(-2, -20), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.95, 0.6))
