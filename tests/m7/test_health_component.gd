extends RefCounted

const HealthComponentScript = preload("res://core/combat/health_component.gd")

var _passed: int = 0
var _failed: int = 0

var _health_signal_count: int = 0
var _died_signal_count: int = 0
var _revived_signal_count: int = 0

var _last_current_hp: int = -1
var _last_max_hp: int = -1
var _last_delta: int = 0


func run(tree: SceneTree) -> Dictionary:
    _passed = 0
    _failed = 0
    await _test_default_initialization(tree)
    await _test_configuration(tree)
    await _test_damage_and_death(tree)
    await _test_healing_and_revival(tree)

    return {"passed": _passed, "failed": _failed}


func _check(condition: bool, label: String) -> void:
    if condition:
        _passed += 1
        print("[PASS] ", label)
    else:
        _failed += 1
        push_error("[FAIL] " + label)


func _make_component(tree: SceneTree) -> Node:
    var health: Node = HealthComponentScript.new() as Node
    tree.root.add_child(health)
    return health


func _connect_signals(health: Node) -> void:
    health.connect("health_changed", Callable(self, "_on_health_changed"))
    health.connect("died", Callable(self, "_on_died"))
    health.connect("revived", Callable(self, "_on_revived"))


func _reset_signal_counts() -> void:
    _health_signal_count = 0
    _died_signal_count = 0
    _revived_signal_count = 0
    _last_current_hp = -1
    _last_max_hp = -1
    _last_delta = 0


func _on_health_changed(current_hp: int, maximum_hp: int, delta: int) -> void:
    _health_signal_count += 1
    _last_current_hp = current_hp
    _last_max_hp = maximum_hp
    _last_delta = delta


func _on_died() -> void:
    _died_signal_count += 1


func _on_revived() -> void:
    _revived_signal_count += 1


func _test_default_initialization(tree: SceneTree) -> void:
    var health := _make_component(tree)
    await tree.process_frame

    _check(bool(health.call("is_initialized")), "HealthComponent initializes in the SceneTree")
    _check(int(health.call("get_max_hp")) == 100, "Default max HP is the technical value 100")
    _check(int(health.call("get_current_hp")) == 100, "Default initial HP is full")
    _check(bool(health.call("is_alive")), "Fighter starts alive")
    _check(is_equal_approx(float(health.call("get_health_ratio")), 1.0), "Full health ratio is 1.0")

    health.queue_free()
    await tree.process_frame


func _test_configuration(tree: SceneTree) -> void:
    var health := _make_component(tree)
    await tree.process_frame

    _check(bool(health.call("configure", 250, 175)), "Custom HP configuration is accepted")
    _check(int(health.call("get_max_hp")) == 250, "Custom max HP is stored")
    _check(int(health.call("get_current_hp")) == 175, "Custom starting HP is stored")
    _check(bool(health.call("is_alive")), "Positive starting HP means alive")
    _check(is_equal_approx(float(health.call("get_health_ratio")), 0.7), "Health ratio uses current/max HP")

    _check(not bool(health.call("configure", 0, 0)), "Zero maximum HP is rejected")
    _check(not bool(health.call("configure", 100, -2)), "Invalid negative starting HP is rejected")
    _check(int(health.call("get_max_hp")) == 250, "Rejected configuration preserves max HP")
    _check(int(health.call("get_current_hp")) == 175, "Rejected configuration preserves current HP")

    _check(bool(health.call("configure", 100, 999)), "Starting HP above maximum is accepted and clamped")
    _check(int(health.call("get_current_hp")) == 100, "Starting HP is clamped to maximum HP")

    _check(bool(health.call("configure", 100, 0)), "Zero starting HP is accepted")
    _check(int(health.call("get_current_hp")) == 0, "Zero starting HP is preserved")
    _check(not bool(health.call("is_alive")), "Zero starting HP means defeated")

    health.queue_free()
    await tree.process_frame


func _test_damage_and_death(tree: SceneTree) -> void:
    var health := _make_component(tree)
    await tree.process_frame

    _connect_signals(health)
    _reset_signal_counts()
    health.call("configure", 100, 100)

    _check(int(health.call("apply_damage", 30)) == 30, "Damage returns the actual HP removed")
    _check(int(health.call("get_current_hp")) == 70, "Damage reduces current HP")
    _check(_health_signal_count == 1, "Damage emits one health_changed signal")
    _check(_last_delta == -30, "Damage signal reports a negative delta")
    _check(_last_current_hp == 70 and _last_max_hp == 100, "Damage signal reports current and maximum HP")

    _check(int(health.call("apply_damage", 0)) == 0, "Zero damage is ignored")
    _check(int(health.call("apply_damage", -5)) == 0, "Negative damage is ignored")
    _check(_health_signal_count == 1, "Ignored damage emits no health_changed signal")

    _check(int(health.call("apply_damage", 999)) == 70, "Overkill damage is capped at remaining HP")
    _check(int(health.call("get_current_hp")) == 0, "Current HP never drops below zero")
    _check(not bool(health.call("is_alive")), "Fighter becomes defeated at zero HP")
    _check(_died_signal_count == 1, "Reaching zero HP emits died once")
    _check(_last_delta == -70, "Lethal damage reports only the remaining HP removed")

    _check(int(health.call("apply_damage", 10)) == 0, "Defeated fighter cannot take additional HP damage")
    _check(_died_signal_count == 1, "Further damage does not emit died again")
    _check(_health_signal_count == 2, "Further damage to defeated fighter emits no health_changed")

    health.queue_free()
    await tree.process_frame


func _test_healing_and_revival(tree: SceneTree) -> void:
    var health := _make_component(tree)
    await tree.process_frame

    _connect_signals(health)
    _reset_signal_counts()
    health.call("configure", 100, 60)

    _check(int(health.call("heal", 15)) == 15, "Healing returns actual HP restored")
    _check(int(health.call("get_current_hp")) == 75, "Healing increases current HP")
    _check(_last_delta == 15, "Healing signal reports a positive delta")

    _check(int(health.call("heal", 100)) == 25, "Healing is capped by missing HP")
    _check(int(health.call("get_current_hp")) == 100, "Healing cannot exceed maximum HP")
    _check(int(health.call("heal", 1)) == 0, "Healing a full-health fighter has no effect")
    _check(_health_signal_count == 2, "Only effective healing emits health_changed")

    _check(int(health.call("apply_damage", 999)) == 100, "Lethal damage can defeat the fighter")
    _check(_died_signal_count == 1, "Lethal damage emits died")

    _check(int(health.call("heal", 10)) == 0, "Healing cannot revive a defeated fighter")
    _check(not bool(health.call("is_alive")), "Healing leaves defeated state unchanged")

    _check(int(health.call("restore_full_health")) == 100, "Restore returns the HP restored during revival")
    _check(int(health.call("get_current_hp")) == 100, "Restore fills HP to maximum")
    _check(bool(health.call("is_alive")), "Restore revives the fighter")
    _check(_revived_signal_count == 1, "Revival emits one revived signal")
    _check(_last_delta == 100, "Revival reports the restored HP amount")

    _check(int(health.call("restore_full_health")) == 0, "Restoring an already full fighter changes nothing")
    _check(_revived_signal_count == 1, "Restoring an alive fighter does not emit revived again")

    health.queue_free()
    await tree.process_frame