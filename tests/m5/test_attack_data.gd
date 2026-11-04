extends RefCounted

const CatalogScript = preload("res://core/combat/attack_catalog.gd")
const DataScript = preload("res://core/combat/attack_data.gd")

var _passed: int = 0
var _failed: int = 0


func run() -> Dictionary:
	_passed = 0
	_failed = 0
	_test_catalog()
	_test_attack_values()
	_test_tick_windows()
	_test_reaction_and_cost_fields()
	_test_validation_and_copy_isolation()
	return {"passed": _passed, "failed": _failed}


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", description)
	else:
		_failed += 1
		push_error("[FAIL] " + description)


func _test_catalog() -> void:
	var attacks: Array[AttackData] = CatalogScript.get_all_attacks()
	_check(attacks.size() == 3, "Catalog contains exactly Light, Heavy and Special")
	_check(CatalogScript.contains(&"light"), "Catalog recognizes Light")
	_check(CatalogScript.contains(&"heavy"), "Catalog recognizes Heavy")
	_check(CatalogScript.contains(&"special"), "Catalog recognizes Special")
	_check(not CatalogScript.contains(&"roll"), "Catalog does not invent a Roll attack")
	_check(CatalogScript.get_attack(&"unknown") == null, "Unknown attack id returns null")


func _test_attack_values() -> void:
	var light := CatalogScript.get_attack(&"light")
	var heavy := CatalogScript.get_attack(&"heavy")
	var special := CatalogScript.get_attack(&"special")
	if light == null or heavy == null or special == null:
		_check(false, "All attack resources load")
		return

	_check(light.base_damage == 8 and light.input_bit == InputBits.LIGHT, "Light damage 8 maps to J logical bit")
	_check(light.startup_ticks == 5 and light.active_ticks == 3 and light.recovery_ticks == 10, "Light frame data is 5/3/10 ticks")
	_check(is_equal_approx(light.base_knockback_px, 20.0), "Light base knockback is 20 px")

	_check(heavy.base_damage == 18 and heavy.input_bit == InputBits.HEAVY, "Heavy damage 18 maps to K logical bit")
	_check(heavy.startup_ticks == 14 and heavy.active_ticks == 4 and heavy.recovery_ticks == 22, "Heavy frame data is 14/4/22 ticks")
	_check(is_equal_approx(heavy.base_knockback_px, 120.0), "Heavy base knockback is 120 px")

	_check(special.base_damage == 30 and special.input_bit == InputBits.SPECIAL, "Special damage 30 maps to L logical bit")
	_check(special.startup_ticks == 20 and special.active_ticks == 6 and special.recovery_ticks == 30, "Special frame data is 20/6/30 ticks")
	_check(is_equal_approx(special.base_knockback_px, 200.0), "Special base knockback is 200 px")
	_check(special.display_name.contains("Cước Sấm"), "MVP Special is labeled Cước Sấm")

	_check(light.is_valid() and heavy.is_valid() and special.is_valid(), "All three default resources pass validation")
	_check(light.balance_status.begins_with("PROVISIONAL"), "Base frame data is marked PROVISIONAL")


func _test_tick_windows() -> void:
	var light := CatalogScript.get_attack(&"light")
	var heavy := CatalogScript.get_attack(&"heavy")
	var special := CatalogScript.get_attack(&"special")
	if light == null or heavy == null or special == null:
		_check(false, "Tick windows have loaded resources")
		return

	_check(light.get_total_ticks() == 18, "Light total sequence is 18 ticks")
	_check(heavy.get_total_ticks() == 40, "Heavy total sequence is 40 ticks")
	_check(special.get_total_ticks() == 56, "Special total sequence is 56 ticks")

	_check(light.is_startup_tick(0) and light.is_startup_tick(4), "Light startup includes elapsed ticks 0 through 4")
	_check(not light.is_active_tick(4) and light.is_active_tick(5), "Light active begins exactly at elapsed tick 5")
	_check(light.is_active_tick(7) and not light.is_active_tick(8), "Light active ends after exactly 3 ticks")
	_check(light.is_recovery_tick(8) and light.is_recovery_tick(17), "Light recovery spans elapsed ticks 8 through 17")
	_check(not light.is_recovery_complete(17) and light.is_recovery_complete(18), "Light recovery completes at elapsed tick 18")
	_check(not light.is_startup_tick(-1) and not light.is_active_tick(-1), "Negative elapsed ticks match no attack phase")

	_check(heavy.is_active_tick(14) and heavy.is_active_tick(17) and not heavy.is_active_tick(18), "Heavy active interval is exactly 4 ticks")
	_check(special.is_active_tick(20) and special.is_active_tick(25) and not special.is_active_tick(26), "Special active interval is exactly 6 ticks")


func _test_reaction_and_cost_fields() -> void:
	var light := CatalogScript.get_attack(&"light")
	var heavy := CatalogScript.get_attack(&"heavy")
	var special := CatalogScript.get_attack(&"special")
	if light == null or heavy == null or special == null:
		_check(false, "Reaction fields have loaded resources")
		return

	_check(light.hitstun_ticks == 12 and heavy.hitstun_ticks == 20, "Light/Heavy hitstun baselines are 12/20 ticks")
	_check(light.blockstun_ticks == 8 and heavy.blockstun_ticks == 14, "Light/Heavy blockstun baselines are 8/14 ticks")
	_check(special.down_duration_ticks == 48, "Special down duration is 0.8 seconds at 60 Hz")
	_check(light.hitstop_ticks == 3 and heavy.hitstop_ticks == 6 and special.hitstop_ticks == 10, "Hitstop baselines are 3/6/10 ticks")
	_check(special.special_cost_bars == 1, "Special cost uses the confirmed one-bar unit")
	_check(light.special_cost_bars == 0 and heavy.special_cost_bars == 0, "Light and Heavy have no Special bar cost")
	_check(light.combo_limit == 3, "Light combo limit is 3")
	_check(special.hit_level == DataScript.HitLevel.UNSPECIFIED, "Special hit level remains unspecified")


func _test_validation_and_copy_isolation() -> void:
	var first := CatalogScript.get_attack(&"light")
	var second := CatalogScript.get_attack(&"light")
	if first == null or second == null:
		_check(false, "Catalog can create independent resource copies")
		return
	_check(first != second, "Catalog returns an independent resource instance")
	first.base_damage = 999
	_check(second.base_damage == 8, "Editing one runtime copy does not mutate catalog template")

	var invalid := DataScript.new()
	invalid.attack_id = &"bad"
	invalid.display_name = "Invalid test"
	invalid.attack_kind = DataScript.AttackKind.SPECIAL
	invalid.input_bit = InputBits.LIGHT
	invalid.startup_ticks = 0
	invalid.active_ticks = 0
	invalid.special_cost_bars = 2
	_check(not invalid.is_valid(), "Validation rejects invalid mapping, frame values and Special cost")
