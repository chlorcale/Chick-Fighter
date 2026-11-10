extends RefCounted

const GaugeScript = preload("res://core/combat/special_gauge_component.gd")

var _passed: int = 0
var _failed: int = 0


func run(tree: SceneTree) -> Dictionary:
    _passed = 0
    _failed = 0

    _test_explicit_mode_configuration()
    _test_invalid_configuration()
    _test_add_points_and_cap()
    _test_reserve_and_spend()
    _test_reservation_release_policy()
    _test_partial_progress_with_reservation()

    await tree.process_frame
    return {"passed": _passed, "failed": _failed}


func _check(condition: bool, label: String) -> void:
    if condition:
        _passed += 1
        print("[PASS] ", label)
    else:
        _failed += 1
        push_error("[FAIL] " + label)


func _new_gauge(starting_points: int, points_per_bar: int = 50) -> Node:
    var gauge: Node = GaugeScript.new()
    var configured: bool = bool(gauge.call("configure", starting_points, points_per_bar))
    if not configured:
        push_error("Test fixture failed to configure SpecialGaugeComponent")
    return gauge


func _test_explicit_mode_configuration() -> void:
    var gauge: Node = _new_gauge(125)

    _check(bool(gauge.call("is_configured")), "Gauge accepts an explicit mode starting value")
    _check(int(gauge.call("get_current_points")) == 125, "Gauge stores configured current points")
    _check(int(gauge.call("get_maximum_bars")) == 5, "Gauge maximum is five bars")
    _check(int(gauge.call("get_points_per_bar")) == 50, "Default point conversion is provisional 50 points per bar")
    _check(int(gauge.call("get_maximum_points")) == 250, "Maximum points derive from five bars and configured conversion")
    _check(int(gauge.call("get_full_bars")) == 2, "Gauge reports two full bars")
    _check(int(gauge.call("get_partial_bar_points")) == 25, "Gauge reports 25 partial-bar points")
    _check(is_equal_approx(float(gauge.call("get_partial_bar_ratio")), 0.5), "Gauge reports half-bar progress")
    _check(int(gauge.call("get_available_bars")) == 2, "Unreserved full bars are available")
    _check(int(gauge.call("get_reserved_bars")) == 0, "New gauge has no reserved bars")
    _check(int(gauge.call("get_spent_bars_total")) == 0, "New gauge has no spent bars")

    # A different mode can supply a different starting amount.
    var other_mode: Node = _new_gauge(50)
    _check(int(other_mode.call("get_current_points")) == 50, "A second mode can use a different explicit starting value")

    gauge.free()
    other_mode.free()


func _test_invalid_configuration() -> void:
    var negative: Node = GaugeScript.new()
    _check(not bool(negative.call("configure", -1)), "Negative starting points are rejected")
    negative.free()

    var above_maximum: Node = GaugeScript.new()
    _check(not bool(above_maximum.call("configure", 251)), "Starting points above maximum are rejected")
    above_maximum.free()

    var invalid_conversion: Node = GaugeScript.new()
    _check(not bool(invalid_conversion.call("configure", 10, 0)), "Zero points per bar is rejected")
    _check(not bool(invalid_conversion.call("is_configured")), "Rejected configuration leaves gauge unconfigured")
    _check(bool(invalid_conversion.call("configure", 10, 25)), "A valid provisional conversion can be configured")
    _check(int(invalid_conversion.call("get_maximum_points")) == 125, "Custom conversion recalculates maximum points")
    _check(not bool(invalid_conversion.call("configure", 20, 25)), "Gauge cannot be configured twice")
    invalid_conversion.free()


func _test_add_points_and_cap() -> void:
    var gauge: Node = _new_gauge(230)

    _check(int(gauge.call("add_points", 100)) == 20, "Added points are clamped to remaining capacity")
    _check(int(gauge.call("get_current_points")) == 250, "Gauge reaches maximum points without overflow")
    _check(int(gauge.call("add_points", 1)) == 0, "Gauge at maximum rejects additional points")
    _check(int(gauge.call("add_points", 0)) == 0, "Zero-point gain is ignored")
    _check(int(gauge.call("add_points", -5)) == 0, "Negative-point gain is ignored")

    var unconfigured: Node = GaugeScript.new()
    _check(int(unconfigured.call("add_points", 10)) == 0, "Unconfigured gauge cannot receive points")

    gauge.free()
    unconfigured.free()


func _test_reserve_and_spend() -> void:
    var gauge: Node = _new_gauge(150)

    _check(bool(gauge.call("reserve_bars", &"special_action", 1)), "One full bar can be reserved")
    _check(bool(gauge.call("has_reservation", &"special_action")), "Reservation is tracked by its identifier")
    _check(int(gauge.call("get_reservation_bars", &"special_action")) == 1, "Reservation reports its bar amount")
    _check(int(gauge.call("get_current_points")) == 150, "Reservation does not deduct points immediately")
    _check(int(gauge.call("get_reserved_bars")) == 1, "Reserved bar is accounted separately")
    _check(int(gauge.call("get_available_bars")) == 2, "Reserved bar is excluded from available bars")
    _check(not bool(gauge.call("reserve_bars", &"special_action", 1)), "Duplicate reservation identifier is rejected")
    _check(not bool(gauge.call("reserve_bars", &"", 1)), "Empty reservation identifier is rejected")
    _check(not bool(gauge.call("reserve_bars", &"bad_amount", 0)), "Zero-bar reservation is rejected")
    _check(not bool(gauge.call("spend_bars", 3)), "Cannot spend more bars than are available")
    _check(bool(gauge.call("spend_bars", 2)), "Two unreserved bars can be spent immediately")
    _check(int(gauge.call("get_current_points")) == 50, "Immediate spending deducts exactly two bars")
    _check(int(gauge.call("get_spent_bars_total")) == 2, "Immediate spending increments spent-bar accounting")
    _check(int(gauge.call("get_available_bars")) == 0, "Remaining reserved bar is not available to spend")
    _check(bool(gauge.call("spend_reservation", &"special_action")), "Reserved bar can be committed as spent")
    _check(int(gauge.call("get_current_points")) == 0, "Committing reservation deducts the reserved points exactly once")
    _check(int(gauge.call("get_reserved_bars")) == 0, "Committed reservation is removed")
    _check(int(gauge.call("get_spent_bars_total")) == 3, "Committed reservation increments spent-bar accounting")
    _check(not bool(gauge.call("spend_reservation", &"special_action")), "A spent reservation cannot be spent twice")

    gauge.free()


func _test_reservation_release_policy() -> void:
    var gauge: Node = _new_gauge(75)

    _check(not bool(gauge.call("reserve_bars", &"too_many", 2)), "Reservation fails when insufficient full bars are available")
    _check(bool(gauge.call("reserve_bars", &"windup", 1)), "One available bar can be reserved")
    _check(not bool(gauge.call("spend_bars", 1)), "Reserved bar cannot be spent by another action")
    _check(not bool(gauge.call("release_reservation", &"windup")), "Reservation release is denied by default")
    _check(int(gauge.call("get_reserved_bars")) == 1, "Denied release keeps reservation intact")
    _check(bool(gauge.call("release_reservation", &"windup", true)), "Explicitly permitted reservation can be released")
    _check(int(gauge.call("get_current_points")) == 75, "Releasing an unspent reservation does not change current points")
    _check(int(gauge.call("get_available_bars")) == 1, "Released bar becomes available again")
    _check(int(gauge.call("get_spent_bars_total")) == 0, "Released reservation is not counted as spent")
    _check(not bool(gauge.call("release_reservation", &"windup", true)), "A reservation cannot be released twice")

    gauge.free()


func _test_partial_progress_with_reservation() -> void:
    var gauge: Node = _new_gauge(175)

    _check(bool(gauge.call("reserve_bars", &"reserved_pair", 2)), "Two of three full bars can be reserved")
    _check(int(gauge.call("get_full_bars")) == 3, "Full-bar count includes reserved bars")
    _check(int(gauge.call("get_available_bars")) == 1, "One full bar remains available")
    _check(int(gauge.call("get_available_points")) == 75, "Available points exclude reserved full bars")
    _check(int(gauge.call("get_partial_bar_points")) == 25, "Partial progress remains visible while bars are reserved")

    gauge.free()
