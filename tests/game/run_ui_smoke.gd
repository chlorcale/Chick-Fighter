extends SceneTree

## Smoke test giao diện (game/ui/**, game/sim/achievements.gd, bản đồ M/N):
## font pixel riêng (đủ glyph cho mọi chữ trong game, phóng nguyên lần), DialogBox (say/choose/ask_name + khung UISkin),
## bản đồ nhỏ mặc định tắt + N/M, sổ tay V (mở/đóng, cấm khi đang thoại, cây thành tựu, trạng thái nút),
## thành tựu (mở, bộ đếm, lưu/tải/xoá, sự kiện World), thông báo "Thành tựu mới!".
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_ui_smoke.gd

const Guidebook := preload("res://game/ui/guidebook.gd")
const AchievementToast := preload("res://game/ui/achievement_toast.gd")
const MapOverlay := preload("res://game/world/world_map_overlay.gd")
const Activities := preload("res://game/world/activities.gd")
const ViewSettings := preload("res://game/world/view_settings.gd")
const TEST_ACH: String = "user://test_ui_achievements.cfg"
const TEST_MAP: String = "user://test_ui_map.cfg"
const TEST_VIEW: String = "user://test_ui_view.cfg"
const TEST_WORLD: String = "user://test_ui_world.cfg"

var _failures: int = 0


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	Achievements.save_path = TEST_ACH
	MapOverlay.settings_path = TEST_MAP
	ViewSettings.save_path = TEST_VIEW
	Activities.save_path = TEST_WORLD
	for p in [TEST_ACH, TEST_MAP, TEST_VIEW]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	GameState.reset()
	Activities.reset()
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e


func _run() -> void:
	_test_font()
	await _test_dialog()
	_test_achievements()
	await _test_toast()
	await _test_world_ui()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------ font

## Mọi ký tự (không phải ký tự điều khiển) xuất hiện trong mã .gd / .json của game.
func _corpus() -> String:
	var seen: Dictionary = {}
	var stack: Array[String] = ["res://game"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			stack.append(dir_path.path_join(sub))
		for f in dir.get_files():
			if not (f.ends_with(".gd") or f.ends_with(".json")):
				continue
			var text: String = FileAccess.get_file_as_string(dir_path.path_join(f))
			for i in range(text.length()):
				var c: int = text.unicode_at(i)
				if c >= 32 and c != 127:
					seen[c] = true
	var out: String = ""
	for c in seen:
		out += String.chr(c)
	return out


func _test_font() -> void:
	DialogBox._font_cache.clear()
	var body: Font = DialogBox.make_font(false)
	var bold: Font = DialogBox.make_font(true)
	_check(DialogBox.has_game_font(), "game pixel font found in res://game/fonts/")
	var body_file: FontFile = DialogBox._load_face(false)
	var bold_file: FontFile = DialogBox._load_face(true)
	_check(body_file != null and bold_file != null and body_file != bold_file, "two separate faces (body + bold) loaded")
	_check(body_file != null and body_file.resource_path.ends_with("chick_body.ttf") and bold_file.resource_path.ends_with("chick_bold.ttf"),
		"faces come from chick_body.ttf / chick_bold.ttf")
	_check(body_file.fixed_size == 11 and body_file.fixed_size_scale_mode == TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
		and body_file.antialiasing == TextServer.FONT_ANTIALIASING_NONE, "fixed size 11, integer-only scaling, no antialiasing")
	_check(body.fallbacks.size() >= 1 and body.fallbacks[0] is SystemFont, "system font fallback for missing glyphs")
	var corpus: String = _corpus()
	var missing_body: String = ""
	var missing_bold: String = ""
	for i in range(corpus.length()):
		var c: int = corpus.unicode_at(i)
		if c == 0xFE0F or (c >= 0x300 and c <= 0x36F):
			continue # bộ chọn biến thể / dấu tổ hợp rời (không dùng để hiển thị)
		if not body_file.has_char(c):
			missing_body += String.chr(c)
		if not bold_file.has_char(c):
			missing_bold += String.chr(c)
	_check(missing_body == "", "body face covers all %d characters used in game scripts (missing: %s)" % [corpus.length(), missing_body])
	_check(missing_bold == "", "bold face covers all characters used in game scripts (missing: %s)" % missing_bold)
	var viet: String = "ăâđêôơưĂÂĐÊÔƠƯấầẩẫậắằẳẵặếềểễệốồổỗộớờởỡợứừửữựỳýỷỹỵẤẦẨẪẬẮẰẲẴẶẾỀỂỄỆỐỒỔỖỘỚỜỞỠỢỨỪỬỮỰ"
	var viet_ok: bool = true
	for i in range(viet.length()):
		viet_ok = viet_ok and body_file.has_char(viet.unicode_at(i)) and bold_file.has_char(viet.unicode_at(i))
	_check(viet_ok, "every Vietnamese letter with every diacritic is in both faces")
	var s1: Vector2 = body.get_string_size("Huyền Thoại Đá Gà", HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var s2: Vector2 = body.get_string_size("Huyền Thoại Đá Gà", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	var s3: Vector2 = body.get_string_size("Huyền Thoại Đá Gà", HORIZONTAL_ALIGNMENT_LEFT, -1, 33)
	_check(s1.x > 60.0 and s1.x < 140.0 and is_equal_approx(s1.y, 15.0), "×1 text size sane (%s)" % s1)
	_check(is_equal_approx(s2.x, s1.x * 2.0) and is_equal_approx(s3.x, s1.x * 3.0) and is_equal_approx(s2.y, 30.0),
		"sizes scale by whole integers (11 → %s, 22 → %s, 33 → %s)" % [s1, s2, s3])
	_check(is_equal_approx(body.get_string_size("Mỗi ngày", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x,
		body.get_string_size("Mỗi ngày", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x), "size 20 rounds to the same ×2 scale as 22")
	var b2: Vector2 = bold.get_string_size("ĐẤU TRƯỜNG", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	_check(is_equal_approx(b2.y, 34.0) and b2.x > s2.x * 0.4, "bold ×2 line height 34 (%s)" % b2)
	_check(body.get_ascent(11) >= 12.0, "ascent reserves room for stacked marks (Ẫ, Ặ) above caps (%s)" % body.get_ascent(11))


# ------------------------------------------------------------------ hộp thoại

func _test_dialog() -> void:
	var dlg := DialogBox.new()
	root.add_child(dlg)
	await _frames(2)
	_check(not dlg.is_open(), "dialog starts closed")
	dlg.say([["Chú Tư", "Ủa, cháu nội ông Hai đây mà! Lớn dữ rồi ha."], ["", "Lời dẫn chuyện."]])
	await _frames(3)
	var parts: Dictionary = dlg.skin_parts()
	_check(dlg.is_open() and dlg._mode == 1, "say() opens the dialog")
	_check(String(parts["panel"]).ends_with("game/art/ui/panel_wood.png") and String(parts["plate"]).ends_with("panel_plate.png"),
		"dialog uses the wooden UISkin frame + name plate (%s)" % str(parts))
	_check(bool(parts["plate_visible"]) and dlg._speaker.text == "Chú Tư" and dlg._portrait_box.visible,
		"speaker on the name plate with portrait")
	_check(dlg._portrait.custom_minimum_size.x == dlg._portrait.texture.get_width() * floorf(dlg._portrait.custom_minimum_size.x / dlg._portrait.texture.get_width()),
		"portrait scaled by a whole number (%s)" % dlg._portrait.custom_minimum_size)
	dlg._text.visible_ratio = 1.0
	await _frames(2)
	_check(bool(dlg.skin_parts()["next_visible"]), "▼ continue marker shows when the line is fully typed")
	dlg._advanced.emit()
	await _frames(2)
	_check(dlg._mode == 1 and not dlg._plate.visible, "narration line hides the name plate")
	dlg._text.visible_ratio = 1.0
	dlg._advanced.emit()
	await _frames(2)
	_check(not dlg.is_open(), "say() closes after the last line")
	var opts: Array = ["Một", "Hai", "Ba", "Bốn", "Năm", "Sáu", "Bảy"]
	var picked: Array = [-1]
	var chooser := func() -> void: picked[0] = await dlg.choose("Mẹ", "Chọn đi con?", opts, ["mô tả 1"])
	chooser.call()
	await _frames(3)
	_check(dlg._mode == 2 and bool(dlg.skin_parts()["cursor_visible"]), "choose() shows options with the pointer cursor")
	for i in range(6):
		dlg._move(1)
	await _frames(3)
	_check(dlg._option_index == 6 and dlg.is_option_visible(6), "scrolled choice stays inside the box (option 7 visible)")
	_check(dlg._more_up.text.begins_with("▲"), "▲ more-above marker when scrolled")
	dlg._chosen.emit(dlg._option_index)
	await _frames(2)
	_check(picked[0] == 6 and not dlg.is_open(), "choose() returns the picked index")
	var named: Array = [""]
	var asker := func() -> void: named[0] = await dlg.ask_name("", "Tên của bạn là gì?", "Tư Gà")
	asker.call()
	await _frames(2)
	_check(dlg._mode == 3 and dlg._name_edit.visible, "ask_name() shows the name entry slot")
	dlg._named.emit("  Út Mèo ")
	await _frames(2)
	_check(named[0] == "Út Mèo" and not dlg.is_open(), "ask_name() returns the trimmed name")
	dlg.queue_free()


# ------------------------------------------------------------------ thành tựu

func _test_achievements() -> void:
	Achievements.reset()
	_check(Achievements.total() >= 35, "at least 35 achievements (%d)" % Achievements.total())
	var ids: Dictionary = {}
	var parents_ok: bool = true
	var icons_ok: bool = true
	for a in Achievements.LIST:
		ids[a["id"]] = true
		icons_ok = icons_ok and UISkin.ICON_NAMES.has(a["icon"])
	for a in Achievements.LIST:
		parents_ok = parents_ok and (a["parent"] == &"" or ids.has(a["parent"]))
	_check(ids.size() == Achievements.total() and parents_ok, "ids unique, every parent exists")
	_check(icons_ok, "every achievement icon exists in the UI icon sheet")
	for b in Achievements.BRANCH_ORDER:
		_check(Achievements.in_branch(b).size() >= 5, "branch %s has ≥ 5 nodes" % b)
	_check(Achievements.visibility(&"story_chicken") == 1 and Achievements.visibility(&"story_tutorial") == 0,
		"root is revealed, child hidden until parent unlocks")
	_check(Achievements.unlock(&"story_chicken") and not Achievements.unlock(&"story_chicken"), "unlock once only")
	_check(not Achievements.unlock(&"no_such_thing"), "unknown id is ignored")
	_check(Achievements.visibility(&"story_tutorial") == 1, "child revealed after parent unlocks")
	Achievements.notify(&"cat_talk", 3)
	_check(Achievements.progress(&"secret_cat") == Vector2i(3, 5) and not Achievements.is_unlocked(&"secret_cat"), "counter progress 3/5")
	var fresh: Array[StringName] = Achievements.notify(&"cat_talk", 2)
	_check(fresh.has(&"secret_cat") and Achievements.is_unlocked(&"secret_cat"), "counter goal unlocks the achievement")
	Achievements.record_max(&"money", 999999)
	_check(not Achievements.is_unlocked(&"life_money"), "999.999đ is not a millionaire yet")
	Achievements.record_max(&"money", 1000000)
	_check(Achievements.is_unlocked(&"life_money"), "1.000.000đ unlocks Triệu phú xóm")
	Achievements.world_event(&"visit_lien_tinh")
	Achievements.world_event(&"visit_lien_tinh")
	_check(Achievements.progress(&"explore_arenas") == Vector2i(1, 2), "set counter ignores repeats (arenas 1/2)")
	Achievements.world_event(&"visit_olympia")
	Achievements.world_event(&"visit_market")
	_check(Achievements.is_unlocked(&"explore_arenas") and Achievements.is_unlocked(&"explore_market"), "World events map to achievements")
	_check(Achievements.when(&"story_chicken").contains("Ngày"), "unlock date recorded (%s)" % Achievements.when(&"story_chicken"))
	Achievements.save()
	var before: int = Achievements.count_unlocked()
	Achievements.unlocked = {}
	Achievements.counters = {}
	_check(Achievements.load_save() and Achievements.count_unlocked() == before and Achievements.counter(&"cat_talk") == 5,
		"achievements persist in their own versioned file")
	var cfg := ConfigFile.new()
	cfg.load(TEST_ACH)
	_check(int(cfg.get_value("meta", "version", 0)) == Achievements.VERSION, "save file carries a version")
	Achievements.reset()
	_check(Achievements.count_unlocked() == 0 and Achievements.load_save() and Achievements.count_unlocked() == 0,
		"reset (new game) clears memory and file")


func _test_toast() -> void:
	var toast: CanvasLayer = AchievementToast.new()
	root.add_child(toast)
	await _frames(1)
	Achievements.unlock(&"fight_first_win")
	Achievements.unlock(&"fight_combo4")
	await _frames(2)
	_check(toast.get("current") == &"fight_first_win" and (toast.get("queue") as Array).size() == 1,
		"toast shows the first unlock and queues the second")
	toast.set("_t", AchievementToast.SHOW_TIME + AchievementToast.SLIDE_TIME * 2.0 + 0.1)
	await _frames(3)
	_check(toast.get("current") == &"fight_combo4", "next toast follows")
	toast.queue_free()
	Achievements.reset()


# ------------------------------------------------------------------ bản đồ + sổ tay (cần World)

func _test_world_ui() -> void:
	GameState.stage = GameState.Stage.TUTORIAL
	var dlg := DialogBox.new()
	root.add_child(dlg)
	var world := World.new()
	root.add_child(world)
	await _frames(3)
	var overlay: Node = world.map_overlay
	overlay.call("wait_grid")
	await _frames(2)
	_check(not bool(overlay.get("minimap_on")) and not bool(overlay.call("minimap_visible")), "corner minimap is OFF by default")
	overlay._unhandled_input(_key(KEY_N))
	await _frames(2)
	_check(bool(overlay.get("minimap_on")) and bool(overlay.call("minimap_visible")), "N turns the minimap on")
	_check(MapOverlay.load_minimap_setting(), "minimap choice remembered in %s" % TEST_MAP)
	overlay._unhandled_input(_key(KEY_N))
	_check(not bool(overlay.get("minimap_on")) and not MapOverlay.load_minimap_setting(), "N turns it off again (remembered)")
	overlay._unhandled_input(_key(KEY_M))
	await _frames(2)
	_check(bool(overlay.get("open")) and not world.player.can_move, "M opens the full map and freezes the player")
	_check(Achievements.is_unlocked(&"explore_map"), "opening the map unlocks Bản đồ trong tay")
	var bike: Variant = overlay.call("bike_marker")
	_check(bike is Vector2 and (bike as Vector2).distance_to(world.bike_pos) < 0.5, "parked motorbike marker at World.bike_pos")
	overlay.call("boat_marker") # không lỗi dù vỏ lãi chưa neo
	overlay._unhandled_input(_key(KEY_ESCAPE))
	await _frames(1)
	_check(not bool(overlay.get("open")) and world.player.can_move, "Esc closes the map")

	var book: CanvasLayer = Guidebook.new()
	book.set("world", world)
	book.set("dialog", dlg)
	root.add_child(book)
	await _frames(1)
	book._unhandled_input(_key(KEY_V))
	await _frames(2)
	_check(bool(book.get("open")) and not world.player.can_move and not world.interactions_enabled, "V opens the guidebook and pauses movement")
	_check(Achievements.is_unlocked(&"secret_book"), "first open unlocks the secret root")
	book._input(_key(KEY_E))
	_check(int(book.get("tab")) == 1, "E flips to the achievement tab")
	book._input(_key(KEY_2))
	var sel0: StringName = book.get("selected")
	_check(sel0 == &"fight_first_win", "branch 2 (Chiến kê) selects its root (%s)" % sel0)
	book._input(_key(KEY_D))
	var sel1: StringName = book.get("selected")
	_check(sel1 != sel0 and Achievements.info(sel1).get("parent", &"") == sel0, "D moves right to a child node (%s)" % sel1)
	book._input(_key(KEY_S))
	_check(book.get("selected") != sel1, "S moves to a sibling")
	Achievements.unlock(&"fight_first_win")
	_check(book.call("node_state", &"fight_first_win") == "unlocked", "unlocked node state")
	_check(book.call("node_state", &"fight_combo4") == "locked" and (book.call("node_text", &"fight_combo4") as Array)[1] == "???",
		"locked node: title shown, description ???")
	_check(book.call("node_state", &"fight_guard_break") == "hidden" and (book.call("node_text", &"fight_guard_break") as Array)[0] == "???",
		"node behind a locked parent is hidden (???)")
	_check(book.call("node_state", &"secret_cat") == "secret" and (book.call("node_text", &"secret_cat") as Array)[0] == "?",
		"secret node shows only ? until unlocked")
	await _frames(2)
	book._input(_key(KEY_V))
	await _frames(1)
	_check(not bool(book.get("open")) and world.player.can_move and world.interactions_enabled, "V closes the book and restores movement")
	dlg.say([["Mẹ", "Ăn cơm con!"]])
	await _frames(2)
	book._unhandled_input(_key(KEY_V))
	_check(not bool(book.get("open")), "cannot open the book during dialogue")
	dlg._text.visible_ratio = 1.0
	dlg._advanced.emit()
	await _frames(2)
	book.set("blocked", func() -> bool: return true)
	book._unhandled_input(_key(KEY_V))
	_check(not bool(book.get("open")), "cannot open the book while main is busy (battle/minigame/cutscene)")
	book.set("blocked", Callable())
	world.set_active(false)
	await _frames(1)
	book._unhandled_input(_key(KEY_V))
	_check(not bool(book.get("open")), "cannot open the book while the world is hidden (battle)")
	world.set_active(true)
	book.queue_free()
	world.queue_free()
	dlg.queue_free()
	await _frames(2)
	Achievements.reset()
