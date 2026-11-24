extends SceneTree

## Smoke test NHÀ & CHUỒNG GÀ (game/home): dựng cảnh với chuồng cấp 1–5 và 1..N gà đủ ba giống; mọi điểm tương tác đi
## bộ tới được (BFS trên lưới 2 px bằng va chạm thật của WorldPlayer); đi bằng phím thật; mọi việc trong bảng chăm gà
## qua phím bơm (press): chọn gà chiến, cho ăn có/không có đồ, chăm thú cưng mỗi ngày một lần, tập luyện, gắn/tháo đủ
## 6 ô (đếm kho), đột biến + đổi Biotech, đổi tên, bán gà, Khô Gà (không cho con cuối); lò ấp: bỏ trứng → qua ngày →
## nở (đặt tên, chuồng đầy bị chặn); nâng chuồng ở ô đất; bàn học (bảng đàn, đổi Biotech, sổ tay); ra vào lại nhà;
## ngủ trả {"sleep": true}; kho trống không lỗi; và nối với main.gd thật (Vô nhà → về xóm, Vô nhà → ngủ).
## Nhà vẽ tay (home_interior_data.gd): người chơi cao ≈ bóng người mẫu 57 px, flood fill không lọt ra ngoài vách/rào, mọi
## phòng + bếp + sân tới được, lớp trên làm trong khi đứng dưới, lửa bếp chạy khung, không còn gà vẽ sẵn.
## Nhân vật chính bản mới (player_sheet_v2: 20 khung + tag + thời lượng khung theo JSON của art), hợp đồng ảnh người lái
## xe (make_rider_visual / set_rider_wheel_frame), sheet người nhà 4 hướng, người nhà đi lại giữa các chỗ làm việc theo
## lịch, không bao giờ bước vào chỗ đặc, tránh người chơi, nói chuyện được khi đang đi; camera zoom không lộ khoảng trống.
## Gà thả sân: một con mỗi gà, đổi màu (rooster.gdshader + mặt nạ bản nhỏ) + lớp đồ đúng từng con, vương miện gà chiến,
## 60 giây đi lại chỉ trên ô đi được trong sân, nhiều hành vi, E vào gà mở đúng bảng (E ở bội vẫn được); đêm ngủ trong
## bội (cửa đóng, chữ z), chiều tối tự về bội, sáng ra sân. Chuồng gỗ nhà sàn có chân cột vẽ thêm + gầm đặc.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_home_smoke.gd

const HomeScene := preload("res://game/home/home_scene.gd")
const HomeState := preload("res://game/home/home_state.gd")
const Layout := preload("res://game/home/home_layout.gd")
const ChickenSprite := preload("res://game/home/chicken_sprite.gd")
const Items := preload("res://game/data/items.gd")
const Activities := preload("res://game/world/activities.gd")
const Data := preload("res://game/home/home_interior_data.gd")
const FamilyNPC := preload("res://game/home/family_npc.gd")
const HERO_JSON: String = "res://game/art/player_sheet_v2.json"
## Chiều cao nhân vật trong art (px, không tính bóng) và bóng người mẫu 06_Guide của nhà vẽ tay.
const HERO_ART_HEIGHT: float = 42.0
const HOUSE_GUIDE_HEIGHT: float = 57.0

var _failures: int = 0
var _home: Node2D
var _auto_dialog: bool = true
var _dlg_choice: int = 0
var _name_answer: String = ""
var _frame: int = 0


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	GameState.save_path = "user://test_home_smoke.cfg"
	HomeState.save_path = "user://test_home_state.cfg"
	Activities.save_path = "user://test_home_world.cfg"
	_main_flow.call_deferred()


## Tự bấm qua hội thoại: câu thoại → tiếp; lựa chọn → _dlg_choice; nhập tên → _name_answer.
func _process(_delta: float) -> bool:
	_frame += 1
	if not _auto_dialog or _frame % 3 != 0:
		return false
	var dialog: DialogBox = _current_dialog()
	if dialog == null:
		return false
	if dialog._mode == 1:
		dialog._text.visible_ratio = 1.0
		dialog._advanced.emit()
	elif dialog._mode == 2:
		dialog._chosen.emit(_dlg_choice)
	elif dialog._mode == 3:
		dialog._named.emit(_name_answer)
	return false


var _main: Node


func _current_dialog() -> DialogBox:
	if _main != null and is_instance_valid(_main) and _main.get("dialog") != null:
		return _main.get("dialog")
	if _home != null and is_instance_valid(_home):
		return _home.get("dialog")
	return null


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _until(cond: Callable, max_frames: int = 600) -> bool:
	for i in range(max_frames):
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _reset_state() -> void:
	GameState.reset()
	HomeState.reset()
	GameState.stage = GameState.Stage.TUTORIAL
	GameState.rng.seed = 77
	GameState.set_time(1, 8 * 60)


func _spawn_home() -> Node2D:
	if _home != null and is_instance_valid(_home):
		_home.queue_free()
		await process_frame
	_home = HomeScene.new()
	root.add_child(_home)
	await _frames(2)
	return _home


func _panel() -> CanvasLayer:
	return _home.get("open_panel") as CanvasLayer


## Đưa con trỏ tới lựa chọn id (bấm xuống), trả về true nếu tìm thấy.
func _nav(panel: CanvasLayer, id: StringName) -> bool:
	var ids: Array = panel.call("option_ids")
	for i in range(ids.size() + 1):
		if StringName(panel.call("current_id")) == id:
			return true
		panel.call("press", &"down")
	return StringName(panel.call("current_id")) == id


func _choose(panel: CanvasLayer, id: StringName, frames: int = 3) -> bool:
	var ok: bool = _nav(panel, id)
	panel.call("press", &"confirm")
	await _frames(frames)
	return ok


func _open(id: StringName) -> CanvasLayer:
	_home.call("interact", id)
	await _until(func() -> bool: return _panel() != null and bool(_panel().call("is_waiting")), 120)
	return _panel()


func _close_panel() -> void:
	for i in range(6):
		var p: CanvasLayer = _panel()
		if p == null:
			break
		p.call("press", &"cancel")
		await _frames(2)
	await _until(func() -> bool: return not bool(_home.get("busy")), 240)


# =================================================================== kịch bản

func _main_flow() -> void:
	var probe: Node2D = ChickenSprite.new()
	probe.call("setup", GameState.chicken_side(0), 0.3)
	root.add_child(probe)
	await _frames(2)
	_check(bool(probe.get("used_portrait_api")) == ChickenSprite.portrait_api_available(),
		"chicken sprite uses FighterView.make_portrait when available (available: %s)" % ChickenSprite.portrait_api_available())
	probe.queue_free()
	await _test_player_sheet()
	await _test_rider_contract()
	await _test_builds()
	await _test_coop_stilts()
	await _test_yard_chickens()
	await _test_yard_night()
	await _test_reachability()
	await _test_walk_and_key()
	await _test_coop_actions()
	await _test_equipment()
	await _test_mutation_rename_sell_kho()
	await _test_incubator()
	await _test_upgrade_desk_family()
	await _test_family_walk()
	await _test_camera_zoom()
	await _test_empty_inventory()
	await _test_leave_reenter_sleep()
	await _test_static_contract()
	await _test_main_integration()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _test_builds() -> void:
	for lvl in range(1, 6):
		_reset_state()
		GameState.coop_level = lvl
		var target: int = GameState.coop_capacity()
		var b: int = 1
		while GameState.chickens.size() < target:
			GameState.add_chicken(b % 3)
			b += 1
		GameState.set_active(target - 1)
		await _spawn_home()
		var coops: int = 0
		var sprites: Array = _home.call("chicken_sprites")
		for it in _home.call("interactables"):
			if String(it["id"]).begins_with("coop_"):
				coops += 1
		_check(coops == HomeScene.slot_count() and coops >= target,
			"coop level %d: %d slots shown for capacity %d" % [lvl, coops, target])
		_check(sprites.size() == target, "coop level %d: %d chicken sprites for %d chickens" % [lvl, sprites.size(), target])
		var breeds: Dictionary = {}
		for c in GameState.chickens:
			breeds[int(c["breed"])] = true
		_check(breeds.size() == 3 or target < 3, "coop level %d: all three breeds present" % lvl)
		var marker: int = 0
		for s in sprites:
			if (s as Node).get_node_or_null(^"ActiveMarker") != null:
				marker += 1
		_check(marker == 1, "coop level %d: exactly one active marker" % lvl)
		var inside: bool = true
		for s in sprites:
			if not Layout.YARD_RECT.has_point((s as Node2D).global_position):
				inside = false
		_check(inside, "coop level %d: chickens stand inside the chicken yard" % lvl)
		var cages_ok: bool = true
		for slot in range(target):
			var node: Node = _home.get_node("Actors/Coops").get_node_or_null("coop_%d" % slot)
			if node == null or (Layout.is_cage(slot) and node.get_node_or_null(^"Back") == null):
				cages_ok = false
		_check(cages_ok, "coop level %d: every built slot has its cage / straw pad node" % lvl)
	# một con gà duy nhất, đủ ba giống từng con một
	for breed in range(3):
		_reset_state()
		GameState.chickens[0]["breed"] = breed
		await _spawn_home()
		var sprites2: Array = _home.call("chicken_sprites")
		_check(sprites2.size() == 1 and is_instance_valid(sprites2[0]), "single chicken of breed %d renders" % breed)


## Chuồng gỗ nhà sàn: lớp chân cột vẽ thêm (coop_stilts trong build_home_interior.py) có trong ảnh + gầm chuồng đặc.
func _test_coop_stilts() -> void:
	var tex: Texture2D = load(Data.ART + "obj_chuong_ga_go.png")
	var img: Image = tex.get_image() if tex != null else null
	if img != null and img.is_compressed():
		img.decompress()
	var entry: Dictionary = {}
	for e in Data.OBJECTS:
		if String(e["name"]) == "chuong_ga_go":
			entry = e
	var posts_ok: bool = img != null and not entry.is_empty()
	var mid_y: int = Data.COOP_STILTS.position.y + Data.COOP_STILTS.size.y / 2
	if posts_ok:
		var origin: Vector2i = Vector2i(entry["pos"])
		for x in Data.COOP_POSTS:
			for dx in range(5):
				if img.get_pixel(x + dx - origin.x, mid_y - origin.y).a < 0.99:
					posts_ok = false
	_check(posts_ok, "coop stilts overlay present: %d opaque posts under the hen-house (y %d)" % [Data.COOP_POSTS.size(), mid_y])
	var foot_ok: bool = posts_ok and int(entry["sort"]) >= Data.COOP_STILTS.end.y - 2
	_check(foot_ok, "hen-house y-sort base sits on the stilts' ground line (%s)" % str(entry.get("sort", -1)))
	_reset_state()
	await _spawn_home()
	var under: Vector2i = Data.COOP_STILTS.get_center()
	_check(bool(_home.call("is_static_blocked", under.x, under.y)), "nobody walks under the stilted hen-house")


## Một đàn 8 con đủ 3 giống (một con đủ đồ) thả sân ban ngày.
func _setup_flock(n: int, minutes: int) -> void:
	_reset_state()
	GameState.coop_level = 5
	if n < 0:
		n = GameState.coop_capacity()
	var b: int = 1
	while GameState.chickens.size() < n:
		GameState.add_chicken(b % 3)
		b += 1
	GameState.chickens[1]["gear"][&"head"] = &"mu_thep"
	GameState.chickens[1]["gear"][&"armor"] = &"giap_dong"
	GameState.chickens[1]["weapon"] = &"dao_chan"
	GameState.set_active(2)
	GameState.set_time(1, minutes)


## Gà thả sân: một con mỗi gà, đổi màu + đồ đúng từng con, đi 60 giây chỉ trên ô đi được trong sân, E vào gà mở bảng.
func _test_yard_chickens() -> void:
	_setup_flock(8, 9 * 60)
	await _spawn_home()
	var yard: Node = _home.call("yard")
	var chicks: Array = _home.call("chicken_sprites")
	var actors: Node = _home.get_node("Actors")
	var one_each: bool = chicks.size() == GameState.chickens.size()
	for i in range(chicks.size()):
		var c: Node2D = chicks[i]
		if not is_instance_valid(c) or c.get_parent() != actors or int(c.get("chicken_id")) != int(GameState.chickens[i]["id"]):
			one_each = false
	_check(one_each, "yard: one roaming chicken per owned bird (%d / %d), y-sorted in Actors" % [chicks.size(),
		GameState.chickens.size()])
	# vật liệu đổi màu: rooster.gdshader với mặt nạ bộ phận bản nhỏ, màu từng bộ phận đúng dữ liệu con gà, mỗi con một vật liệu
	var mats_ok: bool = true
	var seen_mats: Dictionary = {}
	var variants: Dictionary = {}
	for i in range(chicks.size()):
		var mat: ShaderMaterial = chicks[i].call("sprite_material")
		var side: Dictionary = GameState.chicken_side(i)
		var body: Array = side.get("colors", {}).get("body", [0.0, 1.0, 1.0])
		var want := Vector3(float(body[0]), float(body[1]), float(body[2]))
		if mat == null or not String(mat.shader.resource_path).ends_with("rooster.gdshader") \
				or not bool(mat.get_shader_parameter("use_mask")) or seen_mats.has(mat) \
				or not (mat.get_shader_parameter("body_hsv") as Vector3).is_equal_approx(want) \
				or not is_equal_approx(float(mat.get_shader_parameter("hue_shift")), float(side.get("hue", 0.0))):
			mats_ok = false
		var mask: Texture2D = mat.get_shader_parameter("part_mask") if mat != null else null
		var sprite: Sprite2D = chicks[i].get_node(^"Body")
		if mask == null or sprite.texture == null or mask.get_size() != sprite.texture.get_size() or sprite.material != mat:
			mats_ok = false
		seen_mats[mat] = true
		variants[String(chicks[i].get("variant"))] = true
	_check(mats_ok, "yard: every chicken has its own battle recolour material (part mask matches its sheet)")
	_check(variants.size() == 3, "yard: gà nòi, gà tre and Đông Tảo sheets all used (%s)" % str(variants.keys()))
	var geared: Node = chicks[1]
	var gmat: ShaderMaterial = geared.call("sprite_material")
	_check(bool(gmat.get_shader_parameter("use_gear")) and bool(gmat.get_shader_parameter("has_head"))
		and bool(gmat.get_shader_parameter("has_armor")) and bool(gmat.get_shader_parameter("has_weapon"))
		and (geared.call("gear_shown") as Array).size() == 3, "yard: equipped chicken shows its gear layers %s" % str(geared.call("gear_shown")))
	var marker: int = 0
	for c in chicks:
		if (c as Node).get_node_or_null(^"ActiveMarker") != null:
			marker += 1
	_check(marker == 1 and chicks[2].get_node_or_null(^"ActiveMarker") != null, "yard: crown only on the active fighter")
	# 60 giây mô phỏng: chỉ đứng trên ô đi được trong sân, có đi lại, có nhiều kiểu hành vi
	var player: Node2D = _home.get("player")
	player.position = Layout.SPAWN
	var start: Array = []
	for c in chicks:
		start.append((c as Node2D).position)
	var off_cells: int = 0
	var off_where: PackedStringArray = []
	var behaviours: Dictionary = {}
	var travelled: float = 0.0
	var prev: Array = start.duplicate()
	for f in range(60 * 60):
		await process_frame
		if f % 2 != 0:
			continue
		for i in range(chicks.size()):
			var c: Node2D = chicks[i]
			behaviours[String(c.call("state_name"))] = true
			if bool(c.call("is_roaming")):
				if not bool(yard.call("walkable", c.position)) or not Layout.YARD_RECT.has_point(c.position):
					off_cells += 1
					if off_where.size() < 4:
						off_where.append("%d@%s(%s)" % [i, str(c.position.round()), c.call("state_name")])
			travelled += c.position.distance_to(prev[i])
			prev[i] = c.position
	_check(off_cells == 0, "yard: 60 s of roaming stays on walkable yard cells (%d off-cell samples %s)" % [off_cells,
		", ".join(off_where)])
	_check(travelled > 8.0 * 30.0, "yard: chickens actually wander (%.0f px walked in 60 s)" % travelled)
	_check(behaviours.size() >= 4, "yard: several behaviours seen in 60 s %s" % str(behaviours.keys()))
	_check(not behaviours.has("sleep"), "yard: nobody sleeps during the day")
	# đứng cạnh một con gà: thấy "[E] <tên gà>", bấm E thật mở bảng chăm đúng con đó
	var idx: int = 3
	var target: Node2D = chicks[idx]
	# chỗ trống cách xa các con khác + điểm tương tác cố định (gà gần nhất mới được chọn – đúng luật [E])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in range(200):
		var spot: Vector2 = yard.call("random_spot", Vector2(160, 330), 0.0, 150.0, rng)
		var free: bool = spot.x >= 0.0
		for c in chicks:
			if c != target and (c as Node2D).position.distance_to(spot) < 40.0:
				free = false
		for it in _home.call("interactables"):
			if not String(it["id"]).begins_with("chick_") and (it["pos"] as Vector2).distance_to(spot) < 30.0:
				free = false
		if free:
			target.call("spawn_at", spot)
			break
	target.call("begin_talk", target.position)          # đứng yên cho dễ đứng cạnh (như đang ngó người chơi)
	player.position = _stand_near(target.position)
	await _frames(3)
	var near: Dictionary = _home.call("nearest_interactable", player.position)
	var prompt: Label = _home.get("_prompt")
	_check(String(near.get("id", "")) == "chick_%d" % idx and prompt.visible
		and prompt.text == "[E] %s" % String(GameState.chickens[idx]["name"]),
		"yard: standing by a chicken shows «%s» (got %s)" % ["[E] " + String(GameState.chickens[idx]["name"]), prompt.text])
	await _press_e()
	var opened: bool = await _until(func() -> bool: return _panel() != null and bool(_panel().call("is_waiting")), 60)
	_check(opened and _panel().get_script() == preload("res://game/home/coop_ui.gd") and int(_panel().get("index")) == idx,
		"yard: E on a roaming chicken opens its own coop panel (index %d)" % (int(_panel().get("index")) if _panel() != null else -1))
	_check(String(target.call("state_name")) == "talk", "yard: the chicken stops and faces the player while the panel is open")
	await _close_panel()
	_check(String(target.call("state_name")) != "talk", "yard: the chicken goes back to roaming after the panel closes")
	# E ở bội vẫn mở bảng như cũ
	_home.call("interact", &"coop_0")
	var by_cage: bool = await _until(func() -> bool: return _panel() != null and bool(_panel().call("is_waiting")), 60)
	_check(by_cage and int(_panel().get("index")) == 0, "yard: E at a cage still opens that chicken's panel")
	await _close_panel()
	player.position = Layout.SPAWN
	await _frames(2)


## Ô đứng được (chân người chơi) cạnh một điểm – thử 4 hướng 8 px.
func _stand_near(p: Vector2) -> Vector2:
	for d in [Vector2(9, 0), Vector2(-9, 0), Vector2(0, 7), Vector2(0, -7), Vector2(7, 5), Vector2(-7, 5)]:
		var q: Vector2 = p + d
		if not (_home.get("player") as WorldPlayer)._blocked_at(q):
			return q
	return p + Vector2(9, 0)


func _press_e() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var ev2 := ev.duplicate() as InputEventKey
	ev2.pressed = false
	Input.parse_input_event(ev2)


## Ban đêm: vô nhà lúc tối thì gà đã ngủ trong bội (cửa đóng, chữ z, không bấm được); chiều xuống thì gà tự về bội
## ngủ; sáng ra gà bước ra sân, cửa bội mở lại.
func _test_yard_night() -> void:
	_setup_flock(-1, 20 * 60)        # chuồng cấp 5 đầy: cả gà ở bội lẫn gà ở chuồng gỗ nhà sàn
	await _spawn_home()
	var chicks: Array = _home.call("chicken_sprites")
	var asleep: bool = chicks.size() == GameState.coop_capacity()
	var closed: bool = true
	var hidden: bool = true
	for i in range(chicks.size()):
		var c: Node2D = chicks[i]
		if not bool(c.call("is_asleep")):
			asleep = false
		if (c.get_node(^"Body") as Sprite2D).modulate.a > 0.01 or not (c.get_node(^"Zzz") as Sprite2D).visible:
			hidden = false
		if Layout.is_cage(i) and not bool(_home.call("cage_closed", i)):
			closed = false
		if c.position.distance_to(_home.call("yard").call("sleep_point", i)) > 0.5:
			asleep = false
	_check(asleep, "night: every chicken sleeps in its own cage when entering at 20:00")
	_check(hidden and closed, "night: only the closed cage + «z» show (body hidden, door shut)")
	var any_chick: bool = false
	for it in _home.call("interactables"):
		if String(it["id"]).begins_with("chick_") and float(it["radius"]) > 0.0:
			any_chick = true
	_check(not any_chick, "night: sleeping chickens are not E-targets (their cage still is)")
	# chiều tối trong lúc đang ở nhà → tự đi về bội (cả chuồng gỗ)
	_setup_flock(-1, 9 * 60)
	await _spawn_home()
	chicks = _home.call("chicken_sprites")
	await _frames(30)
	GameState.set_time(1, 18 * 60 + 5)
	var went_home: bool = await _until(func() -> bool:
		for c in chicks:
			if not bool((c as Node).call("is_asleep")):
				return false
		return true, 60 * 30)
	var doors: bool = true
	for i in range(chicks.size()):
		if Layout.is_cage(i) and not bool(_home.call("cage_closed", i)):
			doors = false
	_check(went_home and doors, "dusk: all chickens walk back and sleep in their cages, doors close (%s)" % str(
		chicks.map(func(c: Node) -> String: return String(c.call("state_name")))))
	GameState.set_time(2, 6 * 60)
	var woke: bool = await _until(func() -> bool:
		for c in chicks:
			if not bool((c as Node).call("is_roaming")):
				return false
		return true, 60 * 5)
	var open: bool = true
	for i in range(chicks.size()):
		if Layout.is_cage(i) and bool(_home.call("cage_closed", i)):
			open = false
	_check(woke and open, "morning: chickens step out into the yard and cage doors open again")
func _reach_grid() -> Dictionary:
	var w: int = Layout.MAP_SIZE.x
	var h: int = Layout.MAP_SIZE.y
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in range(h):
		for x in range(w):
			solid[y * w + x] = 1 if _home.call("is_blocked", x, y) else 0
	var stand := func(fx: int, fy: int) -> bool:
		for yy in range(fy - WorldPlayer.FOOT_HEIGHT, fy + 1, 2):
			for xx in [fx - WorldPlayer.FOOT_HALF_WIDTH, fx - 2, fx, fx + 2, fx + WorldPlayer.FOOT_HALF_WIDTH - 1]:
				if xx < 0 or yy < 0 or xx >= w or yy >= h or solid[yy * w + xx] == 1:
					return false
		return true
	var seen: Dictionary = {}
	var start := Vector2i(Layout.SPAWN)
	if not stand.call(start.x, start.y):
		return {}
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var head: int = 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var n: Vector2i = p + d
			if seen.has(n) or not stand.call(n.x, n.y):
				continue
			seen[n] = true
			queue.append(n)
	return seen


func _test_reachability() -> void:
	for lvl in [1, 5]:
		_reset_state()
		GameState.coop_level = lvl
		while GameState.chickens.size() < GameState.coop_capacity():
			GameState.add_chicken(GameState.chickens.size() % 3)
		GameState.set_time(1, 14 * 60)   # chiều: Ba ra sân sau (chắn đường?)
		await _spawn_home()
		var seen: Dictionary = _reach_grid()
		var missing: PackedStringArray = []
		for it in _home.call("interactables"):
			var pos: Vector2 = it["pos"]
			var r: float = float(it["radius"]) - 2.0
			var ok: bool = false
			for cell in seen:
				if Vector2(cell).distance_to(pos) <= r:
					ok = true
					break
			if not ok:
				missing.append(String(it["id"]))
		_check(missing.is_empty(), "coop level %d: every interactable reachable on foot from the front door (%d cells; missing: %s)" % [
			lvl, seen.size(), ", ".join(missing)])
		var sink_ok: bool = false
		for cell in seen:
			if Vector2(cell).distance_to(Layout.SINK_POS) <= 1.5:
				sink_ok = true
				break
		_check(sink_ok, "coop level %d: SINK_POS is standable and reachable" % lvl)
		# không lọt ra ngoài: mọi ô tới được nằm trong nhà hoặc sân gà, không chạm mép bản đồ
		var leaks: int = 0
		var rooms: Dictionary = {"bedroom": false, "main": false, "kitchen": false, "yard": false, "steps": false}
		for cell in seen:
			var c := Vector2(cell)
			if not (Layout.HOUSE_RECT.has_point(c) or Layout.YARD_RECT.has_point(c)):
				leaks += 1
			if Rect2(328, 120, 192, 208).has_point(c):
				rooms["bedroom"] = true
			if Rect2(536, 120, 400, 208).has_point(c):
				rooms["main"] = true
			if Layout.KITCHEN_RECT.has_point(c):
				rooms["kitchen"] = true
			if Layout.YARD_RECT.has_point(c):
				rooms["yard"] = true
			if Rect2(704, 336, 64, 12).has_point(c):
				rooms["steps"] = true
		_check(leaks == 0, "coop level %d: walkable area stays inside the walls and fences (%d leaking cells)" % [lvl, leaks])
		_check(not rooms.values().has(false), "coop level %d: bedroom, main room, kitchen, yard and front steps reachable %s" % [
			lvl, str(rooms)])


func _test_walk_and_key() -> void:
	_reset_state()
	await _spawn_home()
	var player: WorldPlayer = _home.get("player")
	var x0: float = player.position.x
	Input.action_press(&"p1_right")
	await _frames(30)
	Input.action_release(&"p1_right")
	await _frames(2)
	_check(player.position.x > x0 + 10.0, "W/A/S/D walking moves the player (Δx %.0f)" % (player.position.x - x0))
	Input.action_press(&"p1_jump")
	await _frames(400)
	Input.action_release(&"p1_jump")
	_check(player.position.y > 16.0 and not player._blocked_at(player.position),
		"player stops at furniture/walls going up (y %.0f)" % player.position.y)
	var drawn: float = HERO_ART_HEIGHT * WorldPlayer.SPRITE_SCALE * player.scale.x
	_check(absf(drawn - HOUSE_GUIDE_HEIGHT) <= 2.0,
		"player drawn at the house guide height (%.1f px vs guide %.0f, node scale %.2f)" % [drawn, HOUSE_GUIDE_HEIGHT, player.scale.x])
	# lớp trên: đứng dưới mái hiên cửa hông → mái làm trong
	player.position = Vector2(304, 480)
	await _frames(2)
	var eave: float = minf(float(_home.call("above_alpha", "mai_hien_ton_xanh")), float(_home.call("above_alpha", "mai_che_cua_hong")))
	_check(eave < 1.0 and eave >= 0.0, "roof over the side door turns see-through when the player is under it (%.2f)" % eave)
	player.position = Layout.SPAWN
	await _frames(2)
	_check(float(_home.call("above_alpha", "mai_hien_ton_xanh")) == 1.0, "roof opaque again when the player leaves")
	# lửa bếp chạy khung
	var fire: Sprite2D = _home.find_child("s_bep_lua_chay_anim", true, false) as Sprite2D
	var f0: int = fire.frame if fire != null else -1
	await _frames(12)
	_check(fire != null and fire.hframes == Data.FRAMES and fire.frame != f0, "stove fire animates (%d frames)" % Data.FRAMES)
	# phím E thật ở trước bội gà đầu tiên → mở bảng chăm gà
	player.position = Layout.coop_stand(0)
	await _frames(3)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var ev2 := ev.duplicate() as InputEventKey
	ev2.pressed = false
	Input.parse_input_event(ev2)
	var opened: bool = await _until(func() -> bool: return _panel() != null, 30)
	_check(opened and _panel().get_script() == preload("res://game/home/coop_ui.gd"), "pressing E at a coop opens the chicken panel")
	await _close_panel()
	_check(not bool(_home.get("busy")) and player.can_move, "Esc closes the panel and gives control back")


func _test_coop_actions() -> void:
	_reset_state()
	GameState.add_chicken(1, "Tía")
	await _spawn_home()
	# chọn gà chiến
	var p: CanvasLayer = await _open(&"coop_1")
	await _choose(p, &"active")
	_check(GameState.active == 1, "select active fighter via panel")
	# cho ăn khi kho trống
	await _choose(p, &"feed")
	_check(String(p.call("last_message")).contains("Cô Ba"), "feed with empty inventory warns to buy rice at Cô Ba")
	# cho ăn có lúa + cám
	GameState._give(&"lua", 2)
	GameState._give(&"cam", 1)
	GameState.set_condition(1, 40.0)
	await _choose(p, &"feed")
	await _choose(p, &"lua", 50)
	var c: Dictionary = GameState.chickens[1]
	_check(float(c["condition"]) == 100.0 and bool(c["fed_today"]) and GameState.item_count(&"lua") == 1,
		"feeding Lúa: condition 100, fed today, one bag used")
	var xp0: int = int(c["xp"])
	await _choose(p, &"feed")
	await _choose(p, &"cam", 50)
	_check(int(c["xp"]) > xp0 or int(c["level"]) > 1, "feeding Cám gives EXP")
	_check(GameState.item_count(&"cam") == 0, "Cám consumed")
	# chăm thú cưng mỗi ngày một lần
	GameState.set_condition(1, 60.0)
	for kind in [&"pet", &"bath", &"sun"]:
		var before: float = float(c["condition"])
		await _choose(p, kind)
		_check(float(c["condition"]) > before and HomeState.care_done(int(c["id"]), kind), "pet care %s raises condition" % kind)
		var mid: float = float(c["condition"])
		await _choose(p, kind)
		_check(float(c["condition"]) == mid, "pet care %s only once per day" % kind)
	_check(HomeState.bond(int(c["id"])) == 3, "bond grows with care (%d)" % HomeState.bond(int(c["id"])))
	# tập luyện
	var m0: int = GameState.minutes
	var xp1: int = int(c["xp"]) + 1000 * int(c["level"])
	await _choose(p, &"train", 40)
	_check(int(c["trained_today"]) == 1 and GameState.minutes == m0 + 60, "training costs 1 hour and counts per day")
	_check(int(c["xp"]) + 1000 * int(c["level"]) > xp1, "training gives EXP")
	# A/D đổi gà
	p.call("press", &"left")
	await _frames(2)
	_check(int(p.get("index")) == 0, "A switches to the previous chicken")
	await _close_panel()


func _test_equipment() -> void:
	_reset_state()
	await _spawn_home()
	var gear: Dictionary = {&"weapon": &"dao_chan", &"head": &"mao_sat", &"comb": &"mao_cat", &"armor": &"giap_tre",
		&"wing": &"canh_lua", &"spur": &"cua_tre"}
	for slot in gear:
		GameState._give(gear[slot], 1)
	var p: CanvasLayer = await _open(&"coop_0")
	await _choose(p, &"equip")
	var def0: float = float(GameState.chicken_stats(0)["def"])
	for slot in gear:
		await _choose(p, slot)
		_nav(p, gear[slot])
		var preview: Dictionary = p.get("_preview")
		_check(not preview.is_empty(), "equip %s shows a before→after preview" % slot)
		p.call("press", &"confirm")
		await _frames(3)
		_check(GameState.equipped(0, slot) == gear[slot] and GameState.item_count(gear[slot]) == 0,
			"equip %s: %s on chicken, inventory 0" % [slot, gear[slot]])
	_check(float(GameState.chicken_stats(0)["def"]) > def0, "gear raises DEF (%.1f → %.1f)" % [def0,
		float(GameState.chicken_stats(0)["def"])])
	var portrait: Node = p.call("portrait")
	_check(portrait != null and is_instance_valid(portrait), "portrait present after equipping")
	for slot in gear:
		await _choose(p, slot)
		await _choose(p, &"")
		_check(GameState.equipped(0, slot) == &"" and GameState.item_count(gear[slot]) == 1,
			"unequip %s: back to inventory" % slot)
	await _close_panel()


func _test_mutation_rename_sell_kho() -> void:
	_reset_state()
	GameState.add_chicken(2, "Mun")
	GameState.add_chicken(1, "Lẹ")
	await _spawn_home()
	var p: CanvasLayer = await _open(&"coop_0")
	# Act 1: đột biến khóa
	await _choose(p, &"mutate")
	_check(String(p.call("last_message")).contains("Act 2"), "Act 1: mutation locked with a reason")
	GameState.act = 2
	GameState.biotech = 10
	GameState.technology = 20
	await _close_panel()
	p = await _open(&"coop_0")
	await _choose(p, &"mutate")
	await _choose(p, &"exchange")
	_check(GameState.biotech == 11 and GameState.technology == 10, "exchange 10 Technology → 1 Biotech")
	await _choose(p, &"fast_muscle")
	_check(String(p.get("_confirm_text")).contains("VĨNH VIỄN"), "mutation confirm stresses permanence")
	await _choose(p, &"yes", 50)
	_check((GameState.chickens[0]["mutations"] as Array).has(&"fast_muscle") and GameState.biotech == 5,
		"mutate Fast Muscle costs 6 Biotech")
	p.call("press", &"cancel")
	await _frames(2)
	# đổi tên
	_name_answer = "Ô Mun Hai"
	await _choose(p, &"rename", 30)
	_check(String(GameState.chickens[0]["name"]) == "Ô Mun Hai", "rename through the name dialog")
	# bán con thứ 3 (Lẹ)
	p.call("press", &"right")
	await _frames(2)
	p.call("press", &"right")
	await _frames(2)
	_check(int(p.get("index")) == 2, "D moves to the third chicken")
	var price: int = GameState.sell_price(2)
	var money0: int = GameState.money
	await _choose(p, &"sell")
	await _choose(p, &"yes", 10)
	_check(GameState.chickens.size() == 2 and GameState.money == money0 + price, "sell chicken pays %d" % price)
	# Khô Gà con thứ 2 (Mun – Đông Tảo)
	p.call("press", &"right")
	await _frames(2)
	var idx: int = int(p.get("index"))
	var kg: float = GameState.kho_ga_yield(idx)
	await _choose(p, &"kho_ga")
	await _choose(p, &"yes", 10)
	await _until(func() -> bool: return bool(p.call("is_waiting")), 300)
	_check(GameState.chickens.size() == 1 and absf(GameState.kho_ga - kg) < 0.001, "Khô Gà gives %.2f kg" % kg)
	# con cuối cùng: bán / Khô Gà bị khóa
	await _choose(p, &"kho_ga")
	_check(GameState.chickens.size() == 1, "last chicken cannot become Khô Gà")
	await _choose(p, &"sell")
	_check(GameState.chickens.size() == 1, "last chicken cannot be sold")
	await _close_panel()


func _test_incubator() -> void:
	_reset_state()
	GameState.act = 2
	GameState.biotech = 4
	GameState._give(&"trung_ga_tre", 1)
	GameState._give(&"trung_la", 1)
	await _spawn_home()
	var p: CanvasLayer = await _open(&"incubator")
	p.set("hatch_time", 0.3)
	await _choose(p, &"place")
	await _choose(p, &"trung_ga_tre")
	await _choose(p, &"2")
	_check(GameState.incubator.size() == 1 and GameState.biotech == 2 and int(GameState.incubator[0]["biotech"]) == 2,
		"place egg with 2 Biotech")
	await _close_panel()
	_check(_home.get_node("Actors") != null, "home still alive after incubator")
	GameState.end_day()
	GameState.end_day()
	_check(GameState.hatch_ready().size() == 1, "egg ready after its days")
	_home.call("rebuild")
	p = await _open(&"incubator")
	p.set("hatch_time", 0.3)
	_name_answer = "Bé Tre"
	var n0: int = GameState.chickens.size()
	await _choose(p, &"hatch_0", 5)
	await _until(func() -> bool: return GameState.chickens.size() > n0, 300)
	_check(GameState.chickens.size() == n0 + 1 and String(GameState.chickens[-1]["name"]) == "Bé Tre"
		and int(GameState.chickens[-1]["breed"]) == 1, "hatch → named Gà tre chick")
	_check(GameState.incubator.is_empty(), "incubator slot freed")
	await _until(func() -> bool: return bool(p.call("is_waiting")), 120)
	await _close_panel()
	# chuồng đầy: trứng tới ngày nhưng nút nở bị khóa
	while not GameState.coop_full():
		GameState.add_chicken(0)
	GameState.biotech = 4
	GameState.start_incubation(&"trung_la", 2)
	GameState.incubator[0]["days_left"] = 0
	p = await _open(&"incubator")
	await _choose(p, &"hatch_0")
	_check(GameState.incubator.size() == 1 and String(p.call("last_message")).contains("Chuồng đầy"),
		"hatching blocked when the coop is full")
	await _close_panel()


func _test_upgrade_desk_family() -> void:
	_reset_state()
	GameState.money = 600000
	await _spawn_home()
	var locked: StringName = StringName("coop_%d" % GameState.coop_capacity())
	_check(not _home.call("find_interactable", locked).is_empty(), "buildable plot shown beyond capacity")
	_dlg_choice = 0
	_home.call("interact", locked)
	await _until(func() -> bool: return not bool(_home.get("busy")), 300)
	_check(GameState.coop_level == 2 and GameState.money == 100000, "coop upgrade at a plot (level %d, money %d)" % [
		GameState.coop_level, GameState.money])
	var coops: int = 0
	for it in _home.call("interactables"):
		if String(it["id"]).begins_with("coop_"):
			coops += 1
	_check(coops == HomeScene.slot_count() and coops >= 5, "coops rebuilt after upgrade (%d)" % coops)
	# bàn học
	GameState.technology = 30
	var p: CanvasLayer = await _open(&"desk")
	await _choose(p, &"exchange")
	await _choose(p, &"all")
	_check(GameState.biotech == 3 and GameState.technology == 0, "desk: exchange all Technology")
	await _choose(p, &"roster")
	await _choose(p, &"0", 4)
	var child: CanvasLayer = p.get("child_panel")
	_check(child != null and bool(child.call("is_waiting")), "desk roster opens the chicken panel")
	if child != null:
		child.call("press", &"cancel")
		await _frames(3)
	p.call("press", &"cancel")
	await _frames(2)
	await _choose(p, &"notes")
	_check(p.call("option_ids").size() >= 2, "desk notebook lists opponents")
	await _close_panel()
	# người nhà theo buổi
	for minute in [8 * 60, 11 * 60, 14 * 60, 19 * 60, 22 * 60]:
		GameState.set_time(6, minute)   # ngày 6 = Thứ 7 (cả nhà ở nhà)
		await _frames(2)
		var ids: Array = _home.call("npc_ids")
		_check(ids.size() >= 1, "family present at %02d:00 on Saturday (%s)" % [minute / 60, str(ids)])
	GameState.set_time(6, 19 * 60)
	await _frames(2)
	_home.call("interact", &"npc_me")
	await _until(func() -> bool: return not bool(_home.get("busy")), 200)
	_check(true, "talking to Mẹ finishes")
	for id in [&"altar", &"table", &"sink", &"water_jar", &"stove", &"tv"]:
		_home.call("interact", id)
		var ok: bool = await _until(func() -> bool: return not bool(_home.get("busy")), 300)
		_check(ok, "interaction %s finishes" % id)
	_check(HomeState.altar_lit_today(), "incense lit at the altar")
	# khạp lúa: cho cả đàn ăn
	GameState._give(&"lua", 5)
	_home.call("interact", &"feed_all")
	await _until(func() -> bool: return not bool(_home.get("busy")), 200)
	var all_fed: bool = true
	for c in GameState.chickens:
		all_fed = all_fed and bool(c["fed_today"])
	_check(all_fed, "rice jar feeds the whole flock")
	# cọc tập: chọn con đầu
	_dlg_choice = 0
	var t0: int = int(GameState.chickens[0]["trained_today"])
	_home.call("interact", &"post")
	await _until(func() -> bool: return not bool(_home.get("busy")), 200)
	_check(int(GameState.chickens[0]["trained_today"]) == t0 + 1, "training post trains the picked chicken")


# =================================================================== nhân vật chính bản mới / xe / người nhà / camera

func _read_hero_json() -> Dictionary:
	var f := FileAccess.open(HERO_JSON, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _test_player_sheet() -> void:
	var tex: Texture2D = WorldPlayer.SHEET
	_check(tex != null and tex.get_width() == 20 * WorldPlayer.FRAME_SIZE and tex.get_height() == WorldPlayer.FRAME_SIZE,
		"player_sheet_v2 loads with 20 frames of 64×64 (%s)" % (str(tex.get_size()) if tex != null else "null"))
	_check(WorldPlayer.SHADOW_SHEET != null and WorldPlayer.SHADOW_SHEET.get_size() == tex.get_size(), "shadow strip matches the sheet")
	_check(is_equal_approx(WorldPlayer.SPRITE_SCALE, 1.0), "new hero drawn ×1.0 (already NPC scale)")
	var meta: Dictionary = _read_hero_json()
	var tags: Dictionary = meta.get("tags", {})
	var durs: Array = meta.get("durations_ms", [])
	_check(int(meta.get("frames", 0)) == 20 and durs.size() == 20, "sheet json: 20 frames with durations")
	var tag_ok: bool = tags.size() == 5
	for anim in ["idle", "walk_down", "walk_up", "walk_left", "walk_right"]:
		var t: Array = tags.get(anim, [-1, -1])
		var a: Array = WorldPlayer.ANIMS.get(anim, [])
		if a.is_empty() or int(t[0]) != int(a[0]) or int(t[1]) - int(t[0]) + 1 != int(a[1]):
			tag_ok = false
			continue
		for k in range(int(a[1])):
			if absf(float(a[2][k]) * 1000.0 - float(durs[int(t[0]) + k])) > 0.5:
				tag_ok = false
	_check(tag_ok, "WorldPlayer.ANIMS matches the art's tags + frame durations (%s)" % str(tags))
	# phát thử từng hoạt ảnh bằng bước 1/60 s: đúng khung, đúng thứ tự, đổi khung đúng thời lượng art (±1 tick)
	var p := WorldPlayer.new()
	p.can_move = false
	root.add_child(p)
	await _frames(1)
	p.set_physics_process(false)
	var play_ok: bool = true
	var detail: String = ""
	for anim in ["idle", "walk_down", "walk_up", "walk_left", "walk_right"]:
		p.facing = Vector2i(0, 1)
		p.call("_set_anim", anim)
		var a: Array = WorldPlayer.ANIMS[anim]
		var seen_frames: Array[int] = [p.frame_index()]
		var changes: Array[float] = []
		var t: float = 0.0
		var last: int = p.frame_index()
		for i in range(int(2.5 * 60.0)):
			p.call("_advance_anim", 1.0 / 60.0)
			t += 1.0 / 60.0
			var fi: int = p.frame_index()
			if fi != last:
				changes.append(t)
				seen_frames.append(fi)
				last = fi
		var expect_frames: Array[int] = []
		for k in range(int(a[1])):
			expect_frames.append(int(a[0]) + k)
		for k in range(seen_frames.size()):
			if seen_frames[k] != expect_frames[k % expect_frames.size()]:
				play_ok = false
				detail = "%s frames %s" % [anim, str(seen_frames)]
		var acc: float = 0.0
		for k in range(mini(changes.size(), int(a[1]))):
			acc += float(a[2][k])
			if absf(changes[k] - acc) > 1.0 / 60.0 + 0.001:
				play_ok = false
				detail = "%s change %d at %.3f s, art %.3f s" % [anim, k, changes[k], acc]
	_check(play_ok, "each animation plays its tag frames with the art durations %s" % detail)
	# đứng yên quay lưng / quay ngang: giữ khung chụm chân của hướng đó
	p.call("_set_anim", "idle")
	p.face(Vector2i(1, 0))
	_check(p.frame_index() == int(WorldPlayer.IDLE_HOLD[Vector2i(1, 0)]), "idle facing right holds a right-facing frame")
	p.face(Vector2i(0, 1))
	_check(p.frame_index() == 0, "idle facing down plays the front idle (blink) tag")
	var body: Sprite2D = p.get_node_or_null(^"Body") as Sprite2D
	var shadow: Sprite2D = p.get_node_or_null(^"Shadow") as Sprite2D
	_check(body != null and body.material == null and body.position == -WorldPlayer.FOOT_IN_FRAME,
		"hero sprite has no shader outline (art is pre-outlined) and its feet sit on the node origin")
	_check(shadow != null and shadow.visible and shadow.get_index() < body.get_index(), "shadow drawn under the hero")
	p.set_riding(true)
	_check(not shadow.visible and not body.visible, "walking sprite + shadow hidden while riding")
	p.queue_free()
	await _frames(1)


func _test_rider_contract() -> void:
	var v: Node2D = WorldPlayer.make_rider_visual()
	var bike: Sprite2D = v.get_node_or_null(^"Bike") as Sprite2D
	_check(bike != null and bike.texture == WorldPlayer.RIDE_SIDE_A and bike.position == Vector2(-34, -WorldPlayer.RIDE_HEIGHT)
		and not bike.centered, "make_rider_visual(): one Sprite2D 'Bike', side frame A, origin at the ground contact")
	_check(WorldPlayer.RIDE_SIDE_A.get_size() == Vector2(68, 60) and WorldPlayer.RIDE_SIDE_B.get_size() == Vector2(68, 60)
		and WorldPlayer.RIDE_FRONT.get_size() == Vector2(30, 60) and WorldPlayer.RIDE_BACK.get_size() == Vector2(30, 60),
		"rider composites keep their sizes (side 68×60 ×2, front/back 30×60)")
	WorldPlayer.set_rider_wheel_frame(v, 1)
	var b_ok: bool = bike.texture == WorldPlayer.RIDE_SIDE_B
	WorldPlayer.set_rider_wheel_frame(v, 2)
	_check(b_ok and bike.texture == WorldPlayer.RIDE_SIDE_A, "set_rider_wheel_frame(): odd = B, even = A")
	v.free()


## Chân đứng được theo va chạm tĩnh (như WorldPlayer._blocked_at).
func _static_ok(home: Node, feet: Vector2) -> bool:
	var x: int = int(feet.x)
	var y: int = int(feet.y)
	for yy in range(y - WorldPlayer.FOOT_HEIGHT, y + 1, 2):
		for xx in [x - WorldPlayer.FOOT_HALF_WIDTH, x - 2, x, x + 2, x + WorldPlayer.FOOT_HALF_WIDTH - 1]:
			if home.call("is_static_blocked", xx, yy):
				return false
	return true


func _tick_family(seconds: float, sample: Callable = Callable()) -> void:
	var steps: int = int(seconds * 60.0)
	for i in range(steps):
		for who in _home.call("npc_ids"):
			var npc: FamilyNPC = _home.call("npc_node", who)
			npc.tick(1.0 / 60.0)
		if sample.is_valid():
			sample.call()


func _test_family_walk() -> void:
	# sheet người nhà: 20 khung (đủ 4 hướng như nhân vật chính) + chân dung
	var sheets_ok: bool = true
	for who in [&"me", &"cha", &"em"]:
		var tex: Texture2D = load(Layout.ART + String(HomeScene.FAMILY[who]["tex"]) + ".png")
		var img: Image = tex.get_image() if tex != null else null
		if img == null or tex.get_width() != 20 * 64 or tex.get_height() != 64:
			sheets_ok = false
			continue
		if img.is_compressed():
			img.decompress()
		for start in [0, 4, 8, 12, 16]:   # idle, xuống, lên, trái, phải: mỗi tag có khung không rỗng
			if img.get_region(Rect2i(start * 64, 0, 64, 64)).is_invisible():
				sheets_ok = false
		var face: Image = img.get_region(Rect2i(0, 0, 64, 64))
		var right: Image = img.get_region(Rect2i(16 * 64, 0, 64, 64))
		if face.get_data() == right.get_data():
			sheets_ok = false
		if not ResourceLoader.exists(Layout.ART + String(HomeScene.FAMILY[who]["tex"]) + "_portrait.png"):
			sheets_ok = false
	_check(sheets_ok, "family sheets: 20 frames each (idle + 4 walking directions) + portraits")
	# chỗ làm việc: chân đứng được + ô lưới tìm đường ngay đó
	_reset_state()
	GameState.set_time(6, 14 * 60)   # Thứ 7, chiều: cả nhà ở nhà
	await _spawn_home()
	var nav: Variant = _home.call("nav")
	var bad_spots: PackedStringArray = []
	for id in Layout.SPOTS:
		var feet: Vector2 = Layout.SPOTS[id][0]
		var cell: Vector2i = nav.nearest_walkable(feet)
		if not _static_ok(_home, feet) or cell.x < 0 or nav.center_of(cell).distance_to(feet) > 8.0:
			bad_spots.append(String(id))
	_check(bad_spots.is_empty(), "every family activity spot is standable and on the path grid (bad: %s)" % ", ".join(bad_spots))
	var ids: Array = _home.call("npc_ids")
	_check(ids.size() == 3, "Saturday afternoon: Mẹ, Ba and em trai are home (%s)" % str(ids))
	var player: WorldPlayer = _home.get("player")
	player.position = Vector2(880, 30) if _static_ok(_home, Vector2(880, 30)) else Layout.SPAWN
	player.can_move = false
	# 70 s mô phỏng: ai cũng đi qua ≥ 2 chỗ, mọi vị trí đều đứng được, có đổi hướng đi
	var start: Dictionary = {}
	for who in ids:
		start[who] = (_home.call("npc_node", who) as Node2D).position
	var bad_pos: Array = []
	var walked_frames: Dictionary = {}
	var check_pos := func() -> void:
		for who in _home.call("npc_ids"):
			var npc: FamilyNPC = _home.call("npc_node", who)
			if not _static_ok(_home, npc.position) and bad_pos.size() < 5:
				bad_pos.append([who, npc.position])
			if npc.anim_name().begins_with("walk"):
				walked_frames[npc.anim_name()] = true
	_tick_family(70.0, check_pos)
	var visited_ok: bool = true
	var report: PackedStringArray = []
	for who in ids:
		var npc: FamilyNPC = _home.call("npc_node", who)
		report.append("%s:%s" % [who, str(npc.visited)])
		if npc.visited.size() < 2:
			visited_ok = false
	_check(visited_ok, "family members walk between activity spots over time (%s)" % " ".join(report))
	_check(bad_pos.is_empty(), "family members never step into solid furniture/walls (%s)" % str(bad_pos))
	_check(walked_frames.size() >= 2, "walking plays directional walk animations (%s)" % str(walked_frames.keys()))
	# đứng ở chỗ làm việc thì quay mặt vào đồ vật
	var facing_ok: bool = true
	for who in ids:
		var npc: FamilyNPC = _home.call("npc_node", who)
		if npc.state == &"idle" and not npc.talking:
			if npc.facing != Layout.SPOTS[npc.current_spot()][1]:
				facing_ok = false
	_check(facing_ok, "family members face their activity object while working")
	# tránh người chơi: đứng chắn ngay trên đường đi → không bao giờ đè lên người chơi, rồi vẫn tới nơi (đi vòng)
	var walker: FamilyNPC = null
	for i in range(60 * 40):
		_tick_family(1.0 / 60.0)
		for who in _home.call("npc_ids"):
			var n: FamilyNPC = _home.call("npc_node", who)
			if n.state == &"walk" and n.get("_path").size() >= 6:
				walker = n
				break
		if walker != null:
			break
	_check(walker != null, "found a family member mid-walk")
	if walker != null:
		var path: Array = walker.get("_path")
		var block_cell: Vector2i = path[3]
		player.position = nav.center_of(block_cell)
		var goal_spot: StringName = walker.current_spot()
		var overlap: Array = [0]
		var waited: Array = [false]
		var watch := func() -> void:
			if walker.block_rect().intersects(_home.call("_player_rect")):
				overlap[0] += 1
			if walker.state == &"wait":
				waited[0] = true
		_tick_family(25.0, watch)
		_check(overlap[0] == 0, "walking family member never overlaps the player standing in the way")
		_check(waited[0], "family member stops and waits when the player blocks the path")
		_check(walker.visited.has(goal_spot) or walker.current_spot() != goal_spot,
			"family member reroutes around the player and carries on (%s → %s)" % [goal_spot, walker.current_spot()])
	# nói chuyện khi đang đi: E ở gần → đứng lại, quay sang người chơi; xong thì đi tiếp
	walker = null
	player.position = Vector2(880, 30) if _static_ok(_home, Vector2(880, 30)) else Layout.SPAWN
	for i in range(60 * 40):
		_tick_family(1.0 / 60.0)
		for who in _home.call("npc_ids"):
			var n: FamilyNPC = _home.call("npc_node", who)
			if n.state == &"walk" and n.get("_path").size() >= 3:
				walker = n
				break
		if walker != null:
			break
	if walker != null:
		# người chơi đứng ngay sau lưng/bên cạnh (chỗ đứng được gần nhất trong bán kính nói chuyện)
		var spot: Vector2 = walker.position
		for off in [Vector2(0, 12), Vector2(0, -12), Vector2(12, 0), Vector2(-12, 0), Vector2(0, 16), Vector2(16, 0), Vector2(-16, 0)]:
			if _static_ok(_home, walker.position + off) and not _home.call("is_blocked", int(walker.position.x + off.x), int(walker.position.y + off.y)):
				spot = walker.position + off
				break
		player.position = spot
		player.can_move = true
		await _frames(2)
		var near: Dictionary = _home.call("nearest_interactable", player.position)
		_check(String(near.get("id", "")) == "npc_" + String(walker.who), "[E] prompt follows the walking family member (%s)" % str(near.get("id", "")))
		_auto_dialog = false
		_home.call("interact", StringName("npc_" + String(walker.who)))
		await _frames(3)
		var at: Vector2 = walker.position
		var d: Vector2 = player.position - walker.position
		var want: Vector2i = Vector2i(signi(int(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, 1 if d.y >= 0.0 else -1)
		_check(walker.talking and walker.facing == want, "family member stops and turns to face the player while talking")
		await _frames(30)
		_check(walker.position == at, "family member stays put during the conversation")
		_auto_dialog = true
		await _until(func() -> bool: return not bool(_home.get("busy")), 300)
		_check(not walker.talking, "talking while walking finishes")
		var p0: Vector2 = walker.position
		await _frames(90)
		_check(walker.position != p0 or walker.state == &"idle", "family member resumes the routine after talking")
	else:
		_check(false, "found a walking family member to talk to")
	# sang buổi khác: người còn ở nhà đi bộ tới chỗ mới (không dịch chuyển tức thời)
	var me: FamilyNPC = _home.call("npc_node", &"me")
	var before: Vector2 = me.position if me != null else Vector2.ZERO
	GameState.set_time(6, 19 * 60)
	await _frames(2)
	me = _home.call("npc_node", &"me")
	_check(me != null and me.position.distance_to(before) < 4.0 and Layout.ROUTINES[&"me"][3][0][0] == me.current_spot(),
		"evening: Mẹ walks to the stove instead of teleporting")
	player.can_move = true


func _test_camera_zoom() -> void:
	_reset_state()
	HomeScene.zoom_index = HomeScene.DEFAULT_ZOOM_INDEX
	await _spawn_home()
	var cam: Camera2D = _home.get("_camera")
	_check(cam.zoom.x < 3.0 - 0.01, "house camera starts a bit wider than before (zoom %.2f < 3.0)" % cam.zoom.x)
	var view: Vector2 = _home.get_viewport_rect().size
	var ok: bool = true
	var zooms: Array[float] = []
	for i in range(6):
		_home.call("step_zoom", -1)
		await _frames(40)
		zooms.append(cam.zoom.x)
		if view.x / cam.zoom.x > float(Layout.MAP_SIZE.x) + 0.5 or view.y / cam.zoom.y > float(Layout.MAP_SIZE.y) + 0.5:
			ok = false
	_check(ok, "zooming out never shows more than the house art (no void; zooms %s)" % str(zooms))
	# phím - / = và lăn chuột
	var z0: float = float(_home.call("target_zoom"))
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_EQUAL
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	var z1: float = float(_home.call("target_zoom"))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await _frames(3)
	var z2: float = float(_home.call("target_zoom"))
	_check(z1 > z0 and z2 > z1, "= key and mouse wheel zoom in (%.2f → %.2f → %.2f)" % [z0, z1, z2])
	for i in range(6):
		_home.call("step_zoom", 1)
	await _frames(40)
	_check(is_equal_approx(cam.zoom.x, HomeScene.ZOOM_STEPS[-1]), "zoom in stops at the last step (%.2f)" % cam.zoom.x)
	HomeScene.zoom_index = HomeScene.DEFAULT_ZOOM_INDEX


func _test_empty_inventory() -> void:
	_reset_state()
	GameState.inventory = {}
	await _spawn_home()
	var p: CanvasLayer = await _open(&"coop_0")
	await _choose(p, &"feed")
	await _choose(p, &"equip")
	for slot in [&"weapon", &"head", &"comb", &"armor", &"wing", &"spur"]:
		await _choose(p, slot)
	p.call("press", &"cancel")
	await _frames(2)
	await _choose(p, &"mutate")
	await _close_panel()
	p = await _open(&"incubator")
	await _choose(p, &"place")
	await _close_panel()
	_home.call("interact", &"feed_all")
	await _until(func() -> bool: return not bool(_home.get("busy")), 200)
	_check(GameState.inventory.is_empty() and GameState.chickens.size() == 1, "empty inventory: every menu opens without changes")


func _test_leave_reenter_sleep() -> void:
	_reset_state()
	await _spawn_home()
	var got: Array = []
	_home.connect("finished", func(r: Dictionary) -> void: got.append(r))
	var p: CanvasLayer = await _open(&"coop_0")
	await _choose(p, &"pet")
	await _close_panel()
	_home.call("interact", &"door_front")
	await _frames(2)
	_check(got.size() == 1 and not bool(got[0]["sleep"]), "front door leaves without sleeping")
	await _spawn_home()
	var got_gate: Array = []
	_home.connect("finished", func(r: Dictionary) -> void: got_gate.append(r))
	_home.call("interact", &"gate")
	await _frames(2)
	_check(got_gate.size() == 1 and not bool(got_gate[0]["sleep"]), "bamboo gate to the fields also leaves to the village")
	await _spawn_home()
	p = await _open(&"coop_0")
	_nav(p, &"pet")
	_check(bool(p.call("current_option").get("disabled", false)), "pet care state persists across leaving and re-entering")
	await _close_panel()
	# Esc trong nhà = về xóm
	var got2: Array = []
	_home.connect("finished", func(r: Dictionary) -> void: got2.append(r))
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(3)
	_check(got2.size() == 1 and not bool(got2[0]["sleep"]), "Esc leaves the house")
	await _spawn_home()
	var got3: Array = []
	_home.connect("finished", func(r: Dictionary) -> void: got3.append(r))
	_dlg_choice = 0
	_home.call("interact", &"bed")
	await _until(func() -> bool: return got3.size() > 0, 200)
	_check(got3.size() == 1 and bool(got3[0]["sleep"]), "bed returns {sleep: true}")


func _test_static_contract() -> void:
	var interior: Node2D = HomeScene.build_interior()
	root.add_child(interior)
	await _frames(1)
	_check(interior.get_node_or_null(^"Actors") != null and interior.get_node(^"Actors").get_child_count() >= 6,
		"build_interior() gives ground + interior props")
	_check(HomeScene.SINK_POS == Layout.SINK_POS and Layout.KITCHEN_RECT.has_point(HomeScene.SINK_POS),
		"SINK_POS exposed inside the kitchen")
	_check(interior.get_node_or_null(^"Above") != null and interior.get_node(^"Ground") is Sprite2D,
		"build_interior() has the ground and the above layer")
	interior.queue_free()
	# không còn gà vẽ sẵn: gà thả/gà tập và bội vẽ sẵn (có gà bên trong) không có trong dữ liệu
	var painted_birds: PackedStringArray = []
	for e in Data.OBJECTS:
		var n: String = String(e["name"])
		if n.begins_with("boi_ga_") or n.begins_with("ga_noi_tap") or n in ["ga_tha_1_mai", "ga_tha_4_mai", "ga_tha_6_trong"]:
			painted_birds.append(n)
	_check(painted_birds.is_empty() and Data.PAINTED_CAGES.size() == 8, "no painted adult birds left in the house art (%s)" % str(painted_birds))


## Nối với main.gd thật: Vô nhà → về xóm (world hiện lại), Vô nhà → giường → ngủ (sang ngày).
func _test_main_integration() -> void:
	if _home != null and is_instance_valid(_home):
		_home.queue_free()
		_home = null
	GameState.reset()
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_name_answer = ""
	_dlg_choice = 0
	var saw_title: Array = [false]
	var ready: bool = await _until(func() -> bool:
		for child in _main.get_children():
			if child is TitleScreen:
				saw_title[0] = true
				(child as TitleScreen)._picked.emit("new")
			elif child is Cutscene:
				(child as Cutscene)._next.emit()
		return GameState.stage == GameState.Stage.GO_CHU_TU and _main.get("world") != null and not _current_dialog().is_open(), 3000)
	_check(saw_title[0], "main: title screen reached")
	_check(ready, "main: new game reaches the village")
	if not ready:
		var names: PackedStringArray = []
		for child in _main.get_children():
			names.append(child.get_class() + ":" + str(child.get_script()))
		print("   stage %d world %s dialog mode %d children %s" % [GameState.stage, str(_main.get("world")),
			_current_dialog()._mode, ", ".join(names)])
	GameState.stage = GameState.Stage.TUTORIAL
	var world: Node = _main.get("world")
	# Vô nhà → Esc về xóm
	_dlg_choice = 0
	_main.call("_on_interact", &"home")
	var home_found: bool = await _until(func() -> bool: return _find_home() != null and _find_home().visible 		and not bool(world.get("visible")), 400)
	_check(home_found, "main: «Vô nhà» opens the home scene")
	var home: Node = _find_home()
	if home != null:
		_check(not bool(world.get("visible")), "main: world hidden while at home")
		var hud: Node = _main.get("clock_hud")
		_check(hud.get("world") == home and bool(hud.get("visible")), "main: clock HUD follows the home scene")
		await _frames(30)
		home.call("leave", false)
		var back: bool = await _until(func() -> bool: return not bool(_main.get("_busy")) and bool(world.get("visible")), 400)
		_check(back and _find_home() == null, "main: leaving home restores the village")
		_check(hud.get("world") == world, "main: clock HUD back on the village")
	# Vô nhà → giường → ngủ
	var day0: int = GameState.day
	_dlg_choice = 0
	_main.call("_on_interact", &"home")
	await _until(func() -> bool: return _find_home() != null and _find_home().visible and not bool(world.get("visible")), 400)
	await _frames(30)
	home = _find_home()
	if home != null:
		home.call("interact", &"bed")
	var slept: bool = await _until(func() -> bool: return GameState.day == day0 + 1 and not bool(_main.get("_busy")), 900)
	_check(slept and bool(world.get("visible")), "main: sleeping in the home bed advances the day (day %d)" % GameState.day)
	_auto_dialog = false
	_main.queue_free()
	_main = null
	await _frames(2)


func _find_home() -> Node2D:
	for child in _main.get_children():
		if child.get_script() == HomeScene:
			return child as Node2D
	return null
