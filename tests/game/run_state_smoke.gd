extends SceneTree

## Smoke test nền dữ liệu + thời gian (GameState v2): đàn gà, chuồng, kho đồ/gắn đồ, chỉ số theo công thức GDD,
## Thể trạng, cho ăn, EXP/cap theo Act, Khô Gà, giá bán, trứng → nở, đột biến, Biotech, giờ/buổi/thứ/qua ngày,
## end_day, lưu/tải + chuyển save v1/v2, tên cũ, mismatch / báo công an, dữ liệu đối thủ và vật phẩm, ngày/đêm + đồng hồ.
## Không đụng save thật: dùng user://test_state_smoke*.cfg.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_state_smoke.gd

const Activities := preload("res://game/world/activities.gd")
const DayNight := preload("res://game/world/day_night.gd")
const ClockHud := preload("res://game/ui/clock_hud.gd")
const Items := preload("res://game/data/items.gd")
const Mutations := preload("res://game/data/mutations.gd")
const Tournaments := preload("res://game/data/tournaments.gd")
const Breeds := preload("res://game/data/breeds.gd")
const TEST_SAVE: String = "user://test_state_smoke.cfg"
const TEST_WORLD_SAVE: String = "user://test_state_smoke_world.cfg"

var _failures: int = 0
var _frames: int = 0
var _step: int = 0
var _world: Node2D
var _day_night: Node2D
var _hud: CanvasLayer
var _calls: int = 0


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func _initialize() -> void:
	GameState.save_path = TEST_SAVE
	Activities.save_path = TEST_WORLD_SAVE
	_test_reset()
	_test_roster()
	_test_inventory()
	_test_stats()
	_test_condition_and_feeding()
	_test_exp()
	_test_kho_ga_and_price()
	_test_eggs()
	_test_mutations()
	_test_time()
	_test_end_day()
	_test_save_load()
	_test_migrations()
	_test_compat()
	_test_items_data()
	_test_opponents_data()
	_test_mismatch()
	_test_leagues()
	_start_presentation()


# ==================================================================== mới chơi

func _test_reset() -> void:
	GameState.reset()
	var c: Dictionary = GameState.active_chicken()
	_check(GameState.chickens.size() == 1 and String(c["name"]) == "Ô Mun" and int(c["breed"]) == 0 and int(c["level"]) == 1,
		"reset: one Gà nòi \"Ô Mun\" Lv1")
	_check(GameState.money == 200000 and GameState.technology == 0 and GameState.biotech == 0 and GameState.kho_ga == 0.0,
		"reset: 200.000đ, no Technology/Biotech/Khô Gà")
	_check(GameState.day == 1 and GameState.minutes == 7 * 60 and GameState.weekday() == 0 and GameState.weekday_name() == "Thứ 2",
		"reset: day 1 = Thứ 2, 07:00")
	_check(GameState.clock_text() == "Thứ 2 · 07:00 · Sáng", "clock_text format (%s)" % GameState.clock_text())
	for key in ["id", "name", "breed", "level", "xp", "condition", "wins", "losses", "fed_today", "weapon", "gear",
			"mutations", "hue_seed", "titles"]:
		if not c.has(key):
			_check(false, "chicken has contract key %s" % key)
	_check(c["condition"] is float and c["weapon"] is StringName and (c["gear"] as Dictionary).size() == 5,
		"chicken: condition float, weapon StringName, 5 gear slots")
	_check(GameState.coop_level == 1 and GameState.coop_capacity() == 3, "coop Lv1 holds 3")


# ==================================================================== đàn gà

func _test_roster() -> void:
	GameState.reset()
	var i1: int = GameState.add_chicken(1, "Tre Con")
	var i2: int = GameState.add_chicken(2)
	_check(i1 == 1 and i2 == 2 and GameState.chickens.size() == 3, "add_chicken returns new indices (1, 2)")
	_check(String(GameState.chickens[2]["name"]) != "" and int(GameState.chickens[2]["hue_seed"]) != 0,
		"unnamed chicken gets a suggested name and a random look seed")
	_check(GameState.add_chicken(0, "Dư") == -1 and GameState.last_error != "", "coop full (3/3) → −1 with reason")
	_check(not GameState.upgrade_coop(), "cannot upgrade coop without 500.000đ")
	GameState.money = 600000
	_check(GameState.upgrade_coop() and GameState.coop_capacity() == 5 and GameState.money == 100000,
		"upgrade coop to Lv2 (500.000đ) → capacity 5")
	GameState.set_active(1)
	_check(GameState.active == 1 and GameState.chicken_name == "Tre Con" and GameState.breed == 1, "set_active switches fighter")
	GameState.set_active(9)
	_check(GameState.active == 1, "set_active ignores a bad index")
	GameState.remove_chicken(0)
	_check(GameState.chickens.size() == 2 and GameState.active == 0 and GameState.chicken_name == "Tre Con",
		"remove_chicken before active shifts the active index")
	GameState.remove_chicken(0)
	GameState.remove_chicken(0)
	_check(GameState.chickens.size() == 1, "remove_chicken never removes the last chicken")
	var chk: Dictionary = GameState.can_enter(&"lien_tinh")
	_check(not bool(chk["ok"]), "Liên tỉnh closed before Ao Làng title")


# ==================================================================== kho đồ & gắn đồ

func _test_inventory() -> void:
	GameState.reset()
	GameState.money = 1000000
	_check(GameState.buy(&"mao_sat") and GameState.item_count(&"mao_sat") == 1 and GameState.money == 850000,
		"buy Mào sắt: 150.000đ into inventory")
	_check(not GameState.buy(&"mu_dong"), "Act-2 market gear locked in Act 1")
	_check(GameState.equip(0, &"head", &"mao_sat") and GameState.item_count(&"mao_sat") == 0
		and GameState.equipped(0, &"head") == &"mao_sat", "equip moves the copy from inventory to the chicken")
	_check(not GameState.equip(0, &"weapon", &"mao_sat"), "equip rejects the wrong slot")
	_check(not GameState.equip(0, &"head", &"khan_ran"), "equip rejects an item not in inventory")
	GameState.buy(&"khan_ran")
	_check(GameState.equip(0, &"head", &"khan_ran") and GameState.item_count(&"mao_sat") == 1
		and GameState.item_count(&"khan_ran") == 0, "swapping returns the old item to inventory")
	_check(GameState.equip(0, &"head", &"") and GameState.item_count(&"khan_ran") == 1 and GameState.equipped(0, &"head") == &"",
		"equip &\"\" unequips back to inventory")
	_check(GameState.owned_total(&"mao_sat") == 1 and GameState.equipped_count(&"mao_sat") == 0, "owned_total counts inventory + equipped")
	GameState.equip_mao_sat = true
	_check(GameState.equip_mao_sat and GameState.owns_mao_sat and GameState.item_count(&"mao_sat") == 0,
		"legacy equip_mao_sat = true equips from inventory")
	GameState.owns_dao_chan = true
	GameState.equip_dao_chan = true
	var side: Dictionary = GameState.player_side()
	_check(StringName(side["weapon"]) == &"dao_chan" and bool(side["dao_chan"]) and bool(side["mao_sat"])
		and StringName(side["gear"][&"head"]) == &"mao_sat", "player_side: weapon/gear + legacy dao_chan/mao_sat bools")
	for key in ["owner", "name", "breed", "lv", "cards", "hue", "sat", "weapon", "gear", "mutations", "condition", "stats",
			"dao_chan", "mao_sat"]:
		if not side.has(key):
			_check(false, "player_side has key %s" % key)
	GameState.equip_dao_chan = false
	_check(GameState.item_count(&"dao_chan") == 1 and not GameState.equip_dao_chan and GameState.owns_dao_chan,
		"legacy equip_dao_chan = false unequips (still owned)")
	# Gà thứ hai lấy Dao chân; bỏ gà → đồ về kho.
	var i: int = GameState.add_chicken(1, "Phụ")
	_check(GameState.equip(i, &"weapon", &"dao_chan") and GameState.item_count(&"dao_chan") == 0, "second chicken equips the dagger")
	GameState.equip_dao_chan = true
	_check(GameState.equip_dao_chan and GameState.equipped(i, &"weapon") == &"", "legacy toggle takes the only dagger from another chicken")
	GameState.equip(0, &"weapon", &"")
	GameState.equip(i, &"weapon", &"dao_chan")
	GameState.remove_chicken(i)
	_check(GameState.item_count(&"dao_chan") == 1, "remove_chicken returns its gear to inventory")
	GameState.kho_ga = 2.0
	_check(GameState.buy(&"khan_meo") == false, "cat-shop item locked in Act 1")
	GameState.stage = GameState.Stage.CHAMPION
	_check(GameState.buy(&"khan_meo") and _near(GameState.kho_ga, 0.5), "cat-shop item bought with Khô Gà (1,5 kg)")
	_check(not GameState.buy(&"canh_meo"), "not enough Khô Gà → false")


# ==================================================================== chỉ số & công thức

func _test_stats() -> void:
	GameState.reset()
	var s3: Dictionary = GameState.scaled_stats(0, 3)
	_check(int(s3["hp"]) == 106 and _near(float(s3["atk"]), 10.6) and _near(float(s3["spd"]), 204.0) and float(s3["def"]) == 2.0,
		"formula 5: Lv3 Gà nòi HP 106, ATK 10,6, SPD 204 (+1%%/lv), DEF 2")
	_check(GameState.exp_to_next(1) == 50 and GameState.exp_to_next(2) == 141 and GameState.exp_to_next(3) == 260
		and GameState.exp_to_next(4) == 400, "formula 3: 50 · 141 · 260 · 400")
	# GDD dòng 349: Ô Mun Lv3 (ATK 10,6) + Cuồng Nộ, Heavy vào Gà tre ≈ 25; vào DEF 4 đang Mai Rùa ≈ 13.
	var hit_tre: float = GameState.damage(10.6, 0.3, 0.0, 1.8)
	var hit_tank: float = GameState.damage(10.6, 0.3, 4.0, 1.8, false, 0.25)
	_check(roundi(hit_tre) == 25 and roundi(hit_tank) == 13, "formula 1 worked example: %.2f ≈ 25, %.2f ≈ 13" % [hit_tre, hit_tank])
	_check(_near(GameState.damage(1.0, 0.0, 9.0, 0.8), 0.8), "formula 1: max(1; …) floor")
	GameState.level = 3
	GameState.owns_mao_sat = true
	GameState.equip_mao_sat = true
	var st: Dictionary = GameState.chicken_stats(0)
	_check(float(st["def"]) == 4.0 and int(st["hp"]) == 106 and _near(float(st["atk"]), 10.6),
		"chicken_stats adds gear: Mào sắt +2 DEF")
	GameState.money = 1000000
	GameState.buy(&"cua_sat")
	GameState.equip(0, &"spur", &"cua_sat")
	_check(_near(float(GameState.chicken_stats(0)["atk"]), 12.1), "Cựa sắt +1,5 ATK (flat, before %)")
	GameState.set_condition(0, 49.0)
	var weak: Dictionary = GameState.chicken_stats(0)
	_check(bool(weak["weak"]) and _near(float(weak["atk"]), 12.1 * 0.9), "condition < 50 → −10%% ATK (%.2f)" % float(weak["atk"]))
	GameState.set_condition(0, 50.0)
	_check(not bool(GameState.chicken_stats(0)["weak"]), "condition 50 is not weak")
	var dt: Dictionary = GameState.scaled_stats(2, 1)
	_check(int(dt["hp"]) == 130 and float(dt["weight"]) == 12.0, "Đông Tảo battle stats unchanged (HP 130, WEIGHT 12)")


# ==================================================================== Thể trạng & cho ăn

func _test_condition_and_feeding() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.TUTORIAL
	GameState.record_result(false)
	_check(_near(float(GameState.active_chicken()["condition"]), 85.0) and int(GameState.active_chicken()["losses"]) == 1,
		"loss: −15 condition, losses +1")
	GameState.record_result(true)
	_check(GameState.wins == 1, "win counter")
	_check(not GameState.feed(0, &"lua"), "feed without Lúa in inventory → false")
	GameState.buy(&"lua")
	GameState.buy(&"lua")
	_check(GameState.money == 170000, "Lúa costs 15.000đ")
	_check(GameState.feed(0, &"lua") and _near(float(GameState.active_chicken()["condition"]), 100.0)
		and bool(GameState.active_chicken()["fed_today"]), "Lúa: condition 100 + fed_today")
	_check(not GameState.feed(0, &"lua") and GameState.item_count(&"lua") == 1, "second main meal the same day refused (not consumed)")
	GameState.buy(&"cam")
	var xp0: int = GameState.xp
	_check(GameState.feed(0, &"cam") and GameState.xp == xp0 + GameState.CAM_EXP, "Cám tăng lực: +20 EXP")
	_check(not GameState.feed(0, &"mao_sat"), "non-food refused")
	# Đêm: ăn rồi → +30 (tối đa 100); bỏ đói → +30 rồi −20.
	GameState.add_chicken(1, "Đói")
	GameState.set_condition(1, 60.0)
	GameState.record_result(false)  # gà đang chọn (đã ăn) thua: 85
	var summary: Dictionary = GameState.end_day()
	_check(_near(float(GameState.chickens[0]["condition"]), 100.0) and _near(float(GameState.chickens[1]["condition"]), 70.0),
		"end_day: fed 85 → 100, unfed 60 → 70 (+30 −20)")
	_check(not bool(GameState.chickens[0]["fed_today"]) and (summary["chickens"] as Array).size() == 2, "end_day resets fed_today, reports each chicken")
	GameState.end_day()
	_check(_near(float(GameState.chickens[0]["condition"]), 80.0), "next night unfed: 100 → 80")
	# Máu Lửa: thua mất Thể trạng ×1,5.
	(GameState.active_chicken()["mutations"] as Array).append(&"burning_blood")
	GameState.record_result(false)
	_check(_near(float(GameState.active_chicken()["condition"]), 57.5), "Burning Blood: loss costs 22,5 condition")
	# Luyện gà.
	GameState.set_condition(0, 100.0)
	var lv_before: int = GameState.level
	var t: Dictionary = GameState.train(0)
	_check(bool(t["ok"]) and int(t["exp"]) == GameState.TRAIN_EXP_BASE + GameState.TRAIN_EXP_PER_LEVEL * lv_before
		and _near(float(GameState.active_chicken()["condition"]), 90.0), "train: EXP 20 + 10 × Lv, −10 condition")
	GameState.train(0)
	GameState.train(0)
	_check(not bool(GameState.train(0)["ok"]), "train limited to 3 per day")


# ==================================================================== EXP & cap theo Act

func _test_exp() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.TUTORIAL
	_check(GameState.level_cap() == 5 and GameState.LEVEL_CAP == 5, "Act 1 cap Lv5")
	_check(GameState.chicken_exp(0, 50) == 1 and GameState.level == 2, "50 EXP → Lv2")
	GameState.chicken_exp(0, 100000)
	_check(GameState.level == 5 and GameState.xp <= GameState.exp_to_next(5), "Act 1 caps at Lv5 (xp %d)" % GameState.xp)
	GameState.stage = GameState.Stage.CHAMPION
	_check(GameState.current_act() == 2 and GameState.level_cap() == 15, "Ao Làng champion → Act 2, cap Lv15")
	GameState.chicken_exp(0, 1000000)
	_check(GameState.level == 15, "Act 2 caps at Lv15")
	GameState.tournament_progress["lien_tinh"] = {"round": 5, "registered": false, "champion": true, "eliminated_week": 0}
	_check(GameState.current_act() == 3 and GameState.level_cap() == 30, "Liên tỉnh champion → Act 3, cap Lv30")
	GameState.reset()
	var teo: Dictionary = GameState.OPPONENTS["ut_map"]
	_check(GameState.battle_exp(teo, true) == 50 and GameState.battle_exp(teo, false) == 20, "formula 4: win 30+10×2, loss 10+5×2")
	_check(GameState.battle_exp(GameState.OPPONENTS["chu_tu"], true) == 40, "tutorial EXP bonus 40")
	GameState.level = 5
	_check(GameState.battle_exp(teo, true) == 25, "opponent ≥ 3 levels lower → ×0,5")
	GameState.level = 1
	var r: Dictionary = GameState.record_battle(true, GameState.OPPONENTS["bay_ghe"])
	_check(int(r["exp"]) == 60 and int(r["levels"]) == 1 and GameState.wins == 1, "record_battle: EXP 60 → Lv2, wins +1")
	var l: Dictionary = GameState.record_battle(false, GameState.OPPONENTS["bay_ghe"])
	_check(int(l["exp"]) == 25 and _near(float(GameState.active_chicken()["condition"]), 85.0), "record_battle loss: 25 EXP, −15 condition")


# ==================================================================== Khô Gà & giá bán

func _test_kho_ga_and_price() -> void:
	GameState.reset()
	_check(GameState.sell_price(0) == 400000, "formula 6: Gà nòi Lv1 = 400.000đ")
	var c: Dictionary = GameState.active_chicken()
	c["level"] = 5
	c["wins"] = 10
	c["titles"] = ["Vô địch Ao Làng"]
	(c["mutations"] as Array).append(&"iron_bone")
	var expect: int = roundi(400000.0 * 1.6 * 1.3 * 1.2 * 1.1)
	_check(GameState.sell_price(0) == expect, "formula 6: Lv5, 10 wins, Ao Làng, 1 mutation = %s (%s)" % [GameState.money_text(expect), GameState.money_text(GameState.sell_price(0))])
	c["wins"] = 40
	_check(GameState.sell_price(0) == roundi(400000.0 * 1.6 * 1.5 * 1.2 * 1.1), "formula 6: win bonus capped at +50%")
	_check(_near(GameState.kho_ga_yield(0), 1.52), "formula 7: Iron Bone Gà nòi (3,8) → 1,52 kg")
	_check(GameState.convert_to_kho_ga(0) == 0.0 and GameState.chickens.size() == 1, "cannot turn the last chicken into Khô Gà")
	var i: int = GameState.add_chicken(0, "Thua Hoài")
	GameState.money = 0
	GameState.owns_mao_sat = true
	GameState.equip(i, &"head", &"mao_sat")
	var kg: float = GameState.convert_to_kho_ga(i)
	_check(_near(kg, 1.2) and _near(GameState.kho_ga, 1.2) and GameState.chickens.size() == 1, "formula 7: Gà nòi 3,0 × 0,4 = 1,2 kg Khô Gà")
	_check(GameState.item_count(&"mao_sat") == 1, "Khô Gà conversion returns gear to inventory")
	_check(GameState.sell_kho_ga(1.0) == 50000 and _near(GameState.kho_ga, 0.2) and GameState.money == 50000, "Tiệm Mèo pays 50.000đ/kg")
	i = GameState.add_chicken(1)
	var sold: int = GameState.sell_chicken(i)
	_check(sold == 250000 and GameState.money == 300000, "sell Gà tre Lv1 at the market: 250.000đ")


# ==================================================================== trứng & ấp

func _test_eggs() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.CHAMPION
	GameState.money = 5000000
	GameState.rng.seed = 99
	_check(GameState.buy(&"trung_ga_noi") and GameState.item_count(&"trung_ga_noi") == 1, "buy Trứng gà nòi at the market")
	_check(not GameState.start_incubation(&"trung_ga_noi", 1), "incubation needs Biotech")
	GameState.biotech = 5
	_check(not GameState.start_incubation(&"trung_ga_noi", 0), "below the egg's Biotech minimum → false")
	_check(GameState.start_incubation(&"trung_ga_noi", 1) and GameState.incubator.size() == 1 and GameState.biotech == 4
		and GameState.item_count(&"trung_ga_noi") == 0, "start_incubation consumes egg + Biotech")
	var e: Dictionary = GameState.incubator[0]
	_check(e.has("egg") and e.has("days_left") and e.has("biotech") and int(e["days_left"]) == 2, "incubator entry {egg, days_left 2, biotech}")
	_check(GameState.hatch_ready().is_empty() and GameState.hatch(0) == -1, "not ready before 2 days")
	GameState.end_day()
	GameState.end_day()
	_check(GameState.hatch_ready() == [0], "ready after 2 nights")
	var idx: int = GameState.hatch(0, "Con Nòi")
	_check(idx == 1 and int(GameState.chickens[idx]["breed"]) == 0 and int(GameState.chickens[idx]["level"]) == 1
		and GameState.incubator.is_empty(), "hatch → new Gà nòi Lv1 at index 1")
	# Trứng lạ + nhiều Biotech: tỷ lệ Đông Tảo và đột biến tăng (thống kê có seed).
	GameState.coop_level = 5
	var trials: int = 120
	var low: Array = _hatch_stats(&"trung_la", 2, trials)
	var high: Array = _hatch_stats(&"trung_la", 10, trials)
	_check(int(high[0]) > int(low[0]) and int(high[1]) > int(low[1]),
		"more Biotech → more Đông Tảo (%d → %d) and mutations (%d → %d) of %d" % [low[0], high[0], low[1], high[1], trials])
	_check(absf(float(high[0]) / trials - Mutations.rare_breed_chance(8)) < 0.15, "Trứng lạ rare chance ≈ %.2f" % Mutations.rare_breed_chance(8))
	_check(GameState.incubator.size() <= GameState.INCUBATOR_SLOTS, "incubator never exceeds its slots")


func _hatch_stats(egg: StringName, biotech_spend: int, trials: int) -> Array:
	var rare: int = 0
	var mutated: int = 0
	for t in range(trials):
		GameState.money += 400000
		GameState.biotech += biotech_spend
		GameState.buy(egg)
		GameState.start_incubation(egg, biotech_spend)
		GameState.incubator[0]["days_left"] = 0
		var i: int = GameState.hatch(0)
		if i < 0:
			continue
		if int(GameState.chickens[i]["breed"]) == 2:
			rare += 1
		if not (GameState.chickens[i]["mutations"] as Array).is_empty():
			mutated += 1
		GameState.remove_chicken(i)
	return [rare, mutated]


# ==================================================================== đột biến & Biotech

func _test_mutations() -> void:
	GameState.reset()
	GameState.technology = 25
	_check(not GameState.exchange_biotech(3), "exchange_biotech: 30 Technology needed for 3")
	_check(GameState.exchange_biotech(2) and GameState.technology == 5 and GameState.biotech == 2, "10 Technology → 1 Biotech")
	GameState.biotech = 50
	_check(not GameState.mutate(0, &"fast_muscle"), "mutations locked in Act 1")
	GameState.stage = GameState.Stage.CHAMPION
	GameState.biotech = 5
	_check(not GameState.mutate(0, &"fast_muscle"), "not enough Biotech (6) → false")
	GameState.biotech = 40
	var before: Dictionary = GameState.chicken_stats(0)
	_check(GameState.mutate(0, &"fast_muscle") and GameState.biotech == 34, "Fast Muscle costs 6 Biotech")
	var after: Dictionary = GameState.chicken_stats(0)
	_check(float(after["spd"]) > float(before["spd"]) and int(after["hp"]) < int(before["hp"]), "Fast Muscle: +SPD −HP")
	_check(not GameState.mutate(0, &"fast_muscle"), "same mutation twice refused")
	before = GameState.chicken_stats(0)
	GameState.mutate(0, &"iron_bone")
	after = GameState.chicken_stats(0)
	_check(float(after["def"]) > float(before["def"]) and float(after["spd"]) < float(before["spd"]), "Iron Bone: +DEF −SPD")
	# Mọi đột biến đều có đánh đổi (ít nhất một chỉ số âm) và có lợi (chỉ số dương hoặc cờ passive).
	for id in Mutations.MUTATIONS:
		var m: Dictionary = Mutations.MUTATIONS[id]
		var has_minus: bool = false
		var has_plus: bool = not (m.get("flags", {}) as Dictionary).is_empty()
		for k in m["stats"]:
			if float(m["stats"][k]) < 0.0:
				has_minus = true
			elif float(m["stats"][k]) > 0.0:
				has_plus = true
		_check(has_minus and has_plus and int(m["cost"]) > 0 and String(m["text"]).contains("đánh đổi"),
			"mutation %s is a trade-off (cost %d Biotech)" % [String(id), int(m["cost"])])
	_check(GameState.MUTATIONS.size() >= 4 and GameState.MUTATIONS.has(&"burning_blood") and GameState.MUTATIONS.has(&"wing_evolution"),
		"MUTATIONS has the four GDD mutations")


# ==================================================================== giờ & lịch

func _test_time() -> void:
	GameState.reset()
	_calls = 0
	var listener: Callable = func() -> void: _calls += 1
	GameState.add_listener(listener)
	GameState.stage = GameState.Stage.TUTORIAL
	# Act 1: giờ trôi nhưng không bao giờ hết ngày / chặn việc.
	_check(not GameState.spend_time(60) and GameState.minutes == 8 * 60, "spend_time advances the clock (Act 1)")
	_check(not GameState.spend_time(5000) and GameState.minutes == 23 * 60 - 1 and not GameState.day_over() and GameState.can_spend(600),
		"Act 1 has no day clock: stuck at 22:59, never day over, never blocked")
	_check(_calls == 2, "listener called on each time change (%d)" % _calls)
	GameState.stage = GameState.Stage.ACT_END
	GameState.set_time(1, 7 * 60)
	var expect: Array = [[7 * 60, GameState.Period.SANG, "Sáng"], [10 * 60, GameState.Period.TRUA, "Trưa"],
		[13 * 60, GameState.Period.CHIEU, "Chiều"], [18 * 60, GameState.Period.TOI, "Tối"], [21 * 60, GameState.Period.KHUYA, "Khuya"],
		[9 * 60 + 59, GameState.Period.SANG, "Sáng"], [17 * 60 + 59, GameState.Period.CHIEU, "Chiều"]]
	var ok: bool = true
	for e in expect:
		GameState.set_time(1, int(e[0]))
		ok = ok and GameState.period() == int(e[1]) and GameState.period_name() == String(e[2])
	_check(ok, "periods: Sáng 07–10, Trưa 10–13, Chiều 13–18, Tối 18–21, Khuya 21–23")
	var names: PackedStringArray = []
	var school: Array = []
	for d in range(1, 9):
		GameState.set_time(d, 7 * 60)
		names.append(GameState.weekday_name())
		school.append(GameState.is_school_day())
	_check(", ".join(names) == "Thứ 2, Thứ 3, Thứ 4, Thứ 5, Thứ 6, Thứ 7, Chủ nhật, Thứ 2", "weekdays: %s" % ", ".join(names))
	_check(school == [true, true, true, true, true, false, false, true], "school days Thứ 2–Thứ 6")
	GameState.set_time(6, 7 * 60)
	_check(not bool(GameState.perform(&"class")["ok"]), "no class on Thứ 7")
	GameState.set_time(1, 7 * 60)
	var res: Dictionary = GameState.perform(&"class")
	_check(bool(res["ok"]) and GameState.technology == 10 and GameState.minutes == 10 * 60, "class: 3 h, +10 Technology")
	var m0: int = GameState.money
	res = GameState.perform(&"work_boat", 1.3)
	_check(bool(res["ok"]) and GameState.money == m0 + 130000 and GameState.minutes == 12 * 60, "boat shift: 2 h, 100.000đ × minigame 1,3")
	GameState.set_time(1, 21 * 60)
	_check(not GameState.can_spend(180) and GameState.can_spend(120), "can_spend respects 23:00")
	_check(not bool(GameState.perform(&"class")["ok"]), "perform refuses work that runs past 23:00")
	GameState.set_time(1, 21 * 60 + 30)
	_check(GameState.spend_time(GameState.TIME_JOB) and GameState.day_over(), "spend_time past 23:00 returns true (day ended)")
	var s: Dictionary = GameState.end_day()
	_check(bool(s["forced"]) and GameState.day == 2 and GameState.minutes == 8 * 60 and GameState.weekday_name() == "Thứ 3",
		"forced bedtime: next day Thứ 3, wake 08:00")
	GameState.set_time(2, 20 * 60)
	GameState.end_day()
	_check(GameState.day == 3 and GameState.minutes == 7 * 60, "voluntary sleep: wake 07:00")
	_check(GameState.TIME_SCHOOL == 180 and GameState.TIME_JOB == 120 and GameState.TIME_QUEST == 60 and GameState.TIME_LIBRARY == 60
		and GameState.TIME_BATTLE == 60 and GameState.TIME_FERRY == 30, "GDD 3.6 time costs")
	_check(Activities.time_cost(&"site") == 120 and Activities.time_cost(&"fish_house", {"kind": &"feed"}) == 15
		and Activities.time_cost(&"school") == 60, "south-bank activity time costs")
	_check(GameState.clock_text() == "Thứ 4 · 07:00 · Sáng", "clock_text on day 3 (%s)" % GameState.clock_text())
	var n: int = _calls
	GameState.remove_listener(listener)
	GameState.spend_time(30)
	_check(_calls == n, "removed listener no longer called")


func _test_end_day() -> void:
	GameState.reset()
	Activities.reset()
	GameState.stage = GameState.Stage.TUTORIAL
	Activities.mark_done(&"site")
	Activities.buy_lottery_ticket()
	GameState.stage = GameState.Stage.CHAMPION
	GameState.money = 1000000
	GameState.biotech = 5
	GameState.buy(&"trung_dong_tao")
	GameState.start_incubation(&"trung_dong_tao", 2)
	GameState.active_chicken()["trained_today"] = 3
	_check(Activities.day == GameState.day, "Activities.day follows GameState.day")
	var s: Dictionary = Activities.new_day()
	_check(GameState.day == 2 and Activities.day == 2 and s.has("weekday_name"), "Activities.new_day() = GameState.end_day()")
	_check(not Activities.is_done(&"site") and Activities.lottery_result_ready(), "end_day re-opens activities, lottery can be checked")
	_check(int(GameState.incubator[0]["days_left"]) == 2 and int(GameState.active_chicken()["trained_today"]) == 0,
		"end_day: incubator −1 day (3 → 2), training counter reset")
	var lines: PackedStringArray = GameState.morning_lines(s)
	_check(lines.size() >= 2 and lines[0].begins_with("Thứ 3 · Ngày 2") and lines[1].begins_with("Thể trạng"),
		"morning report: %s" % " / ".join(lines))


# ==================================================================== lưu / tải

func _snapshot() -> String:
	return var_to_str([GameState.stage, GameState.player_name, GameState.money, GameState.technology, GameState.biotech,
		GameState.kho_ga, GameState.cards, GameState.chickens, GameState.active, GameState.coop_level, GameState.inventory,
		GameState.incubator, GameState.day, GameState.minutes, GameState.act, GameState.tournament_progress])


func _test_save_load() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.ACT_END
	GameState.player_name = "Út Test"
	GameState.cards = [&"cuong_no", &"gio_song"]
	GameState.money = 3000000
	GameState.technology = 17
	GameState.biotech = 9
	GameState.kho_ga = 2.4
	GameState.coop_level = 2
	GameState.buy(&"mao_sat")
	GameState.buy(&"cua_dong")
	GameState.buy(&"lua", 3)
	GameState.buy(&"trung_la")
	GameState.equip(0, &"head", &"mao_sat")
	var i: int = GameState.add_chicken(2, "Đông Tảo Test")
	GameState.equip(i, &"spur", &"cua_dong")
	GameState.mutate(i, &"iron_bone")
	GameState.award_title(0, 1)
	GameState.set_condition(i, 42.5)
	GameState.set_active(i)
	GameState.buy(&"trung_ga_tre")
	GameState.start_incubation(&"trung_ga_tre", 1)
	GameState.set_time(12, 19 * 60 + 30)
	GameState.register_tournament(&"lien_tinh")
	GameState.save()
	var before: String = _snapshot()
	GameState.reset()
	_check(GameState.load_save(), "load_save reads the temp save")
	_check(_snapshot() == before, "save → load round-trip keeps every field")
	_check(GameState.active == 1 and GameState.chicken_name == "Đông Tảo Test" and GameState.equipped(1, &"spur") == &"cua_dong"
		and GameState.item_count(&"lua") == 3 and GameState.weekday_name() == "Thứ 6" and GameState.time_text() == "19:30",
		"loaded: active chicken, gear, inventory, day 12 = Thứ 6 19:30")
	var cfg := ConfigFile.new()
	cfg.load(TEST_SAVE)
	_check(int(cfg.get_value("meta", "version", 0)) == GameState.SAVE_VERSION, "save is versioned (v%d)" % GameState.SAVE_VERSION)
	_check(GameState.save_path == TEST_SAVE and GameState.SAVE_PATH == "user://chick_fighter_save.cfg", "real save path untouched")


func _test_migrations() -> void:
	# v1: một con gà, cờ owns_*/equip_*, ngày ở file thế giới.
	var cfg := ConfigFile.new()
	cfg.set_value("game", "stage", GameState.Stage.FINAL)
	cfg.set_value("game", "player_name", "Cũ")
	cfg.set_value("game", "money", 123000)
	cfg.set_value("game", "cards", PackedStringArray(["cuong_no", "mai_rua", "gio_song"]))
	cfg.set_value("game", "chicken_name", "Mun Cũ")
	cfg.set_value("game", "breed", 0)
	cfg.set_value("game", "level", 3)
	cfg.set_value("game", "exp", 77)
	cfg.set_value("game", "wins", 4)
	cfg.set_value("game", "owns_mao_sat", true)
	cfg.set_value("game", "owns_dao_chan", true)
	cfg.set_value("game", "equip_mao_sat", true)
	cfg.set_value("game", "equip_dao_chan", false)
	cfg.save(TEST_SAVE)
	var world := ConfigFile.new()
	world.set_value("world", "day", 6)
	world.save(TEST_WORLD_SAVE)
	_check(GameState.load_save() and GameState.legacy_day_pending, "v1 save loads (legacy day pending)")
	Activities.load_save()
	_check(GameState.chickens.size() == 1 and GameState.chicken_name == "Mun Cũ" and GameState.level == 3 and GameState.xp == 77
		and GameState.wins == 4 and GameState.money == 123000 and GameState.cards.size() == 3, "v1 → one chicken from the old fields")
	_check(GameState.equip_mao_sat and GameState.owns_dao_chan and not GameState.equip_dao_chan and GameState.item_count(&"dao_chan") == 1,
		"v1 gear flags → gear + inventory")
	_check(GameState.day == 6 and not GameState.legacy_day_pending and GameState.weekday_name() == "Thứ 7", "v1 day taken from the world save")
	# Bản nháp v2: khóa lv / equip (gồm weapon) / eggs; inventory đếm cả món đang gắn.
	cfg = ConfigFile.new()
	cfg.set_value("meta", "version", 2)
	cfg.set_value("game", "stage", GameState.Stage.ACT_END)
	cfg.set_value("game", "money", 999)
	cfg.set_value("roster", "chickens", [{"id": 4, "name": "Nháp", "breed": 1, "lv": 7, "xp": 5, "condition": 64, "title": 1,
		"mutations": PackedStringArray(["fast_muscle"]), "equip": {"head": "mao_sat", "weapon": "dao_chan", "armor": ""}}])
	cfg.set_value("roster", "active_index", 0)
	cfg.set_value("items", "inventory", {"mao_sat": 2, "dao_chan": 1})
	cfg.set_value("lab", "eggs", [{"item": "trung_ga_noi", "days_left": 1, "biotech_spent": 2}])
	cfg.set_value("calendar", "day", 9)
	cfg.save(TEST_SAVE)
	_check(GameState.load_save(), "v2 draft save loads")
	var c: Dictionary = GameState.active_chicken()
	_check(int(c["level"]) == 7 and StringName(c["weapon"]) == &"dao_chan" and GameState.equipped(0, &"head") == &"mao_sat"
		and (c["titles"] as Array).has("Vô địch Ao Làng") and _near(float(c["condition"]), 64.0), "v2 draft chicken converted (lv/equip/title)")
	_check(GameState.item_count(&"mao_sat") == 1 and GameState.item_count(&"dao_chan") == 0, "v2 draft inventory minus equipped copies")
	_check(GameState.incubator.size() == 1 and StringName(GameState.incubator[0]["egg"]) == &"trung_ga_noi"
		and int(GameState.incubator[0]["biotech"]) == 2 and GameState.day == 9, "v2 draft eggs → incubator")
	GameState.reset()
	_check(GameState.chickens.size() == 1 and GameState.money == 200000 and GameState.day == 1, "reset after load gives a clean game")


func _test_compat() -> void:
	GameState.reset()
	GameState.chicken_name = "Tên Mới"
	GameState.level = 4
	GameState.xp = 12
	_check(String(GameState.chickens[0]["name"]) == "Tên Mới" and int(GameState.chickens[0]["level"]) == 4 and int(GameState.chickens[0]["xp"]) == 12,
		"legacy chicken_name/level/xp write the active chicken")
	GameState.stage = GameState.Stage.TUTORIAL
	_check(GameState.add_exp(400) == 1 and GameState.level == 5, "legacy add_exp")
	_check(GameState.PRICE_MAO_SAT == 150000 and GameState.PRICE_DAO_CHAN == 200000 and GameState.PRICE_CAM == 40000 and GameState.CAM_EXP == 20,
		"legacy PRICE_* / CAM_EXP")
	_check(int(GameState.ITEMS[&"mao_sat"]["price"]) == GameState.PRICE_MAO_SAT and int(GameState.ITEMS[&"dao_chan"]["price"]) == GameState.PRICE_DAO_CHAN
		and int(GameState.ITEMS[&"cam"]["price"]) == GameState.PRICE_CAM and int(GameState.ITEMS[&"lua"]["price"]) == 15000, "ITEMS prices match GDD 7.2")
	GameState.money = 1000000
	GameState.money -= GameState.PRICE_MAO_SAT
	GameState.owns_mao_sat = true
	GameState.equip_mao_sat = true
	_check(GameState.owns_mao_sat and GameState.equip_mao_sat and GameState.owned_total(&"mao_sat") == 1, "old shop flow (owns + equip) still works")
	GameState.owns_mao_sat = true
	_check(GameState.owned_total(&"mao_sat") == 1, "owns_* = true twice does not duplicate")
	GameState.owns_mao_sat = false
	_check(not GameState.owns_mao_sat and not GameState.equip_mao_sat, "owns_* = false removes it everywhere")


# ==================================================================== dữ liệu

func _test_items_data() -> void:
	var bad: PackedStringArray = []
	for id in GameState.ITEMS:
		var it: Dictionary = GameState.ITEMS[id]
		for key in ["name", "slot", "price", "text", "stats", "shop", "act"]:
			if not it.has(key):
				bad.append("%s.%s" % [id, key])
		if not ([&"weapon", &"head", &"armor", &"wing", &"spur", &"comb", &"food", &"egg", &"misc"] as Array).has(it.get("slot")):
			bad.append("%s slot" % id)
		if not ([&"co_ba", &"cho", &"meo", &""] as Array).has(it.get("shop")):
			bad.append("%s shop" % id)
		if StringName(it.get("shop", &"")) == &"meo" and StringName(it.get("currency", &"")) != &"kho_ga":
			bad.append("%s cat shop must cost Khô Gà" % id)
	_check(bad.is_empty(), "every item has name/slot/price/text/stats/shop/act %s" % str(bad))
	var tiers_ok: bool = true
	for slot in Items.GEAR_SLOTS:
		var cheap: bool = false
		var strong: bool = false
		for id in Items.items_for_slot(slot):
			var it: Dictionary = GameState.ITEMS[id]
			cheap = cheap or (StringName(it["shop"]) == &"co_ba" and int(it["act"]) == 1)
			strong = strong or (StringName(it["shop"]) == &"cho" and int(it["act"]) >= 2)
		tiers_ok = tiers_ok and cheap and strong
	_check(tiers_ok, "each gear slot has a cheap Act-1 tier (Cô Ba) and a stronger tier (Chợ)")
	_check(float(GameState.ITEMS[&"mao_sat"]["stats"]["def"]) == 2.0 and StringName(GameState.ITEMS[&"mao_sat"]["slot"]) == &"head", "Mào sắt: head, +2 DEF")
	_check(GameState.ITEMS.has(&"cua_sat") and GameState.ITEMS.has(&"cua_dong")
		and float(GameState.ITEMS[&"cua_dong"]["stats"]["atk"]) > float(GameState.ITEMS[&"cua_sat"]["stats"]["atk"]), "spurs Cựa sắt < Cựa đồng (ATK)")
	var weapons: Array[StringName] = Items.items_for_slot(&"weapon")
	_check(weapons.size() == 3 and int(GameState.ITEMS[&"quat_long"]["price"]) == 350000 and int(GameState.ITEMS[&"non_bao_hiem"]["price"]) == 500000
		and StringName(GameState.ITEMS[&"quat_long"]["shop"]) == &"co_ba", "three GDD 5.2 weapons at Cô Ba (200k / 350k / 500k)")
	var eggs_ok: bool = true
	for id in Items.items_for_slot(&"egg"):
		var it: Dictionary = GameState.ITEMS[id]
		var b: int = int(it["breed"])
		var adult: int = Breeds.price(b) if b >= 0 else Breeds.price(Breeds.GA_DONG_TAO)
		eggs_ok = eggs_ok and int(it["price"]) < adult and int(it["incubate_days"]) >= 2 and int(it["incubate_days"]) <= 3 \
			and StringName(it["shop"]) == &"cho"
	_check(eggs_ok and Items.items_for_slot(&"egg").size() == 4, "4 market eggs, cheaper than adults, 2–3 days")
	_check(Breeds.price(2) == 600000 and int(Breeds.info(2)["unlock"]) == 2 and String(Breeds.info(2)["passive_text"]).begins_with("Gồng"),
		"Gà Đông Tảo ownable from Act 2 (600k, passive Gồng)")


func _test_opponents_data() -> void:
	var bad: PackedStringArray = []
	var breeds_seen: Dictionary = {}
	for id in GameState.OPPONENTS:
		var o: Dictionary = GameState.OPPONENTS[id]
		var tag: String = String(id)
		for key in ["owner", "name", "breed", "lv", "tier", "aggr", "jumpy", "block", "portrait", "weapon", "gear"]:
			if not o.has(key):
				bad.append("%s.%s" % [tag, key])
		var b: int = int(o.get("breed", -1))
		if b < 0 or b > 2:
			bad.append(tag + " breed")
		breeds_seen[b] = true
		var kit: StringName = Moves.kit_for_side(o)
		if kit != (Moves.KIT_DONGTAO if b == 2 else Moves.KIT_ROOSTER):
			bad.append(tag + " kit")
		if int(o.get("tier", 0)) < 1 or int(o.get("tier", 0)) > 4 or int(o.get("lv", 0)) < 1:
			bad.append(tag + " tier/lv")
		if b == 2 and float(o.get("jumpy", 0.0)) != 0.0:
			bad.append(tag + " Đông Tảo cannot jump")
		for card in o.get("cards", []):
			if not GameState.CARD_INFO.has(StringName(card)):
				bad.append("%s card %s" % [tag, card])
		var weapon: StringName = StringName(o.get("weapon", &""))
		if weapon != &"" and Items.slot_of(weapon) != &"weapon":
			bad.append(tag + " weapon")
		if bool(o.get("dao_chan", false)) != (weapon == &"dao_chan"):
			bad.append(tag + " dao_chan flag")
		var gear: Dictionary = o.get("gear", {})
		for slot in gear:
			if Items.slot_of(StringName(gear[slot])) != StringName(slot):
				bad.append("%s gear %s" % [tag, slot])
		if bool(o.get("mao_sat", false)) != (StringName(gear.get(&"head", &"")) == &"mao_sat"):
			bad.append(tag + " mao_sat flag")
		for m in o.get("mutations", []):
			if not Mutations.has(StringName(m)):
				bad.append("%s mutation %s" % [tag, m])
		if not ResourceLoader.exists("res://game/art/npc/%s.png" % String(o.get("portrait", ""))):
			bad.append(tag + " portrait")
		if bool(o.get("spar", false)) and (int(o.get("purse", 0)) <= 0 or int(o.get("band", 0)) < 1):
			bad.append(tag + " spar purse/band")
		var side: Dictionary = GameState.opponent_side(tag)
		if side.is_empty() or float(side["power"]) <= 0.0:
			bad.append(tag + " side")
	_check(bad.is_empty(), "every opponent: breed/kit/tier/cards/weapon/gear/mutations/portrait valid %s" % str(bad))
	_check(breeds_seen.size() == 3, "opponents mix all three breeds/kits")
	var lt_ok: bool = true
	for id in Tournaments.rounds(&"lien_tinh"):
		var o: Dictionary = GameState.OPPONENTS[id]
		lt_ok = lt_ok and int(o["lv"]) >= 6 and int(o["lv"]) <= 10 and int(o["tier"]) >= 2 and int(o["tier"]) <= 3 \
			and StringName(o["league"]) == &"lien_tinh"
	var ol_ok: bool = true
	for id in Tournaments.rounds(&"olympic"):
		var o: Dictionary = GameState.OPPONENTS[id]
		ol_ok = ol_ok and int(o["lv"]) >= 20 and int(o["lv"]) <= 30 and int(o["tier"]) == 4 and StringName(o["league"]) == &"olympic"
	_check(lt_ok and Tournaments.round_count(&"lien_tinh") == 5, "Liên tỉnh: 5 rounds, Lv 6–10, AI T2–T3")
	_check(ol_ok and Tournaments.round_count(&"olympic") == 5, "Olympic: 5 rounds, Lv 20–30, AI T4")
	for band in [1, 2, 3, 4]:
		_check(not GameState.spar_opponents(band).is_empty(), "sparring opponents for band %d: %s" % [band, str(GameState.spar_opponents(band))])
	# Vòng sau mặc đồ tốt hơn / mạnh hơn vòng trước.
	for tid in [&"lien_tinh", &"olympic"]:
		var last: float = 0.0
		var rising: bool = true
		for id in Tournaments.rounds(tid):
			var p: float = float(GameState.opponent_side(String(id))["power"])
			rising = rising and p > last
			last = p
		_check(rising, "%s rounds get strictly stronger" % String(tid))


func _player_build(lv: int, items: Array, muts: Array = []) -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.ACT_END
	GameState.cards = [&"cuong_no", &"mai_rua", &"gio_song"]
	GameState.level = lv
	for id in items:
		GameState.inventory[StringName(id)] = 1
		GameState.equip(0, Items.slot_of(id), id)
	for m in muts:
		(GameState.active_chicken()["mutations"] as Array).append(StringName(m))


func _test_mismatch() -> void:
	_player_build(4, [&"mao_sat", &"dao_chan"])
	var fresh: float = GameState.mismatch("lt_hai_ben_tre")
	_check(fresh >= 1.3, "fresh Ao Làng champion (Lv4, Mào sắt + Dao chân) vs Liên tỉnh R1: mismatch %.2f ≥ 1,30" % fresh)
	_check(GameState.can_call_police("lt_hai_ben_tre") == (fresh >= GameState.POLICE_MISMATCH), "can_call_police follows the 1,35 threshold")
	_check(GameState.can_call_police("ol_thay_cuu") and GameState.mismatch("ol_thay_cuu") > 3.0, "Olympic boss vs fresh champion: police allowed")
	_check(is_equal_approx(GameState.mismatch(GameState.OPPONENTS["lt_hai_ben_tre"]), fresh), "mismatch accepts a raw OPPONENTS entry")
	_player_build(6, [&"mao_sat", &"dao_chan", &"cua_sat", &"giap_tre", &"canh_lua", &"mao_cat"])
	var prepared: float = GameState.mismatch("lt_hai_ben_tre")
	_check(prepared < 1.12 and not GameState.can_call_police("lt_hai_ben_tre"), "after work + Cô Ba gear (Lv6): R1 mismatch %.2f < 1,12" % prepared)
	_player_build(10, [&"mu_dong", &"dao_chan", &"cua_dong", &"giap_dong", &"canh_gio", &"mao_dong"])
	_check(GameState.mismatch("lt_tam_can_tho") < 1.25, "Lv10 + full market set vs Liên tỉnh final: %.2f" % GameState.mismatch("lt_tam_can_tho"))
	_player_build(1, [])
	var tutor: float = GameState.mismatch("chu_tu")
	_check(tutor < 1.0 and not GameState.can_call_police("teo_1"), "Act 1 story: tutorial easier (%.2f), no police vs Tèo" % tutor)


func _test_leagues() -> void:
	GameState.reset()
	GameState.money = 1000000
	_check(not GameState.register_tournament(&"lien_tinh"), "Liên tỉnh needs the Ao Làng title")
	GameState.stage = GameState.Stage.CHAMPION
	_check(GameState.register_tournament(&"lien_tinh") and GameState.money == 900000, "register Liên tỉnh (100.000đ fee)")
	var opp: Dictionary = GameState.next_league_opponent(&"lien_tinh")
	_check(String(opp.get("id", "")) == "lt_hai_ben_tre" and int(opp["start_card_gauge"]) == 2 and not bool(opp["hell_mode"]), "next_league_opponent: round 1")
	var r: Dictionary = GameState.tournament_result(&"lien_tinh", true)
	_check(bool(r["ok"]) and int(r["money"]) == 150000 and GameState.league_round(&"lien_tinh") == 1, "round win pays, advances")
	r = GameState.tournament_result(&"lien_tinh", false)
	_check(bool(r["eliminated"]) and GameState.league_round(&"lien_tinh") == -1 and not bool(GameState.can_enter(&"lien_tinh")["ok"]),
		"loss eliminates until next week")
	GameState.tournament_progress["lien_tinh"] = {"round": 4, "registered": true, "champion": false, "eliminated_week": 0}
	r = GameState.tournament_result(&"lien_tinh", true)
	_check(bool(r["champion"]) and int(r["money"]) == 2000000 and int(r["biotech"]) == 10 and GameState.current_act() == 3
		and (GameState.active_chicken()["titles"] as Array).has("Vô địch Liên tỉnh miền Tây"), "Liên tỉnh title: 2.000.000đ + 10 Biotech, Act 3")
	GameState.money = 5000000
	_check(not GameState.register_tournament(&"olympic"), "Olympic refuses a chicken with < 3 mutations")
	for m in [&"fast_muscle", &"iron_bone", &"burning_blood"]:
		(GameState.active_chicken()["mutations"] as Array).append(m)
	_check(GameState.register_tournament(&"olympic"), "Olympic accepts a chicken with 3 mutations")
	var cfg: Dictionary = GameState.match_config(&"olympic")
	_check(bool(cfg["hell_mode"]) and float(cfg["round_time"]) == 60.0 and int(cfg["opponent"]["start_card_gauge"]) == 4
		and int(GameState.TOURNAMENTS[&"olympic"]["prize_money"]) == 20000000, "Hell Mode: 4 Card Gauge, 60 s clock, prize 20.000.000đ")


# ==================================================================== ngày/đêm + đồng hồ (cần vài khung hình)

func _start_presentation() -> void:
	GameState.reset()
	GameState.stage = GameState.Stage.ACT_END
	GameState.set_time(1, 12 * 60)
	_world = Node2D.new()
	var p := Node2D.new()
	p.name = "player"
	_world.add_child(p)
	root.add_child(_world)
	_day_night = DayNight.new()
	_day_night.world = _world
	_day_night.add_light(Vector2(100, 100), 90.0)
	_world.add_child(_day_night)
	_hud = ClockHud.new()
	_hud.world = _world
	root.add_child(_hud)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	match _step:
		0:
			if _frames == 5:
				var noon: Color = _day_night.current_tint()
				_check(noon.r > 0.97 and noon.g > 0.97 and noon.b > 0.9, "noon light is bright (%s)" % str(noon))
				_check(_hud.visible and String(_hud.lines()[0]) == "Thứ 2 · Ngày 1" and String(_hud.lines()[1]) == "12:00 · Trưa",
					"clock HUD shows weekday/day/time/period (%s)" % " | ".join(_hud.lines()))
				GameState.spend_time(9 * 60 + 30) # 21:30
			elif _frames == 8:
				var mid: Color = _day_night.current_tint()
				_check(mid.r > 0.5, "light changes smoothly, not in one jump (%s)" % str(mid))
			elif _frames == 200:
				var night: Color = _day_night.current_tint()
				_check(night.b > night.r + 0.15 and night.r < 0.5, "night light is blue (%s)" % str(night))
				_check(DayNight.night_factor(21 * 60 + 30) > 0.8 and DayNight.night_factor(12 * 60) == 0.0, "night factor: 0 at noon, high at night")
				var dusk: Color = DayNight.tint_at(18 * 60)
				var after: Color = DayNight.tint_at(15 * 60)
				_check(dusk.r > dusk.b + 0.3 and after.r > after.b, "afternoon golden, dusk orange")
				var mix: Dictionary = DayNight.ambience_mix(22 * 60)
				_check(float(mix["crickets_min"]) > 0.4 and float(mix["birds_mult"]) < 0.3, "night ambience: crickets up, birds down")
				_world.visible = false
			elif _frames == 203:
				_check(not _hud.visible, "clock HUD hides with the world")
				var modulate: CanvasModulate = null
				for child in _day_night.get_children():
					if child is CanvasModulate:
						modulate = child
				_check(modulate != null and not modulate.is_visible_in_tree(), "CanvasModulate inactive while the world is hidden")
				_world.queue_free()
				_world = null
			elif _frames == 206:
				_check(not _hud.visible, "clock HUD hidden without a world")
				_finish()
				return true
	return false


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_WORLD_SAVE))
	GameState.save_path = GameState.SAVE_PATH
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
