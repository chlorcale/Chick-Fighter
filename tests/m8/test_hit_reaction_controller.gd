extends RefCounted

const HitReactionScript = preload("res://core/combat/hit_reaction_controller.gd")

var _passed: int = 0
var _failed: int = 0

var _started_events: Array[Vector2i] = []
var _extended_events: Array[Vector3i] = []
var _ended_events: Array[int] = []
var _lock_events: Array[Vector2i] = []


func run(_tree: SceneTree) -> Dictionary:
    _passed = 0
    _failed = 0

    _test_initial_state_and_validation()
    _test_hitstun_countdown()
    _test_blockstun_and_down()
    _test_max_duration_policy()
    _test_refresh_policy()
    _test_signals()
    _test_clear_reactions()

    return {"passed": _passed, "failed": _failed}


func _check(condition: bool, label: String) -> void:
    if condition:
        _passed += 1
        print("[PASS] ", label)
    else:
        _failed += 1
        push_error("[FAIL] " + label)


func _make_controller() -> RefCounted:
    return HitReactionScript.new() as RefCounted


func _connect_signals(controller: RefCounted) -> void:
    controller.connect("reaction_started", Callable(self, "_on_reaction_started"))
    controller.connect("reaction_extended", Callable(self, "_on_reaction_extended"))
    controller.connect("reaction_ended", Callable(self, "_on_reaction_ended"))
    controller.connect("control_lock_changed", Callable(self, "_on_control_lock_changed"))


func _reset_events() -> void:
    _started_events.clear()
    _extended_events.clear()
    _ended_events.clear()
    _lock_events.clear()


func _on_reaction_started(kind: int, duration: int) -> void:
    _started_events.append(Vector2i(kind, duration))


func _on_reaction_extended(kind: int, previous_ticks: int, new_ticks: int) -> void:
    _extended_events.append(Vector3i(kind, previous_ticks, new_ticks))


func _on_reaction_ended(kind: int) -> void:
    _ended_events.append(kind)


func _on_control_lock_changed(locked: bool, remaining_ticks: int) -> void:
    _lock_events.append(Vector2i(1 if locked else 0, remaining_ticks))


func _test_initial_state_and_validation() -> void:
    var controller := _make_controller()

    _check(not bool(controller.call("is_control_locked")), "Controller starts without control lock")
    _check(not bool(controller.call("is_reacting")), "Controller starts without active reaction")
    _check(int(controller.call("get_control_lock_remaining")) == 0, "Initial control-lock duration is zero")

    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 0, "Initial Hitstun timer is zero")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.BLOCKSTUN)) == 0, "Initial Blockstun timer is zero")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.DOWN)) == 0, "Initial Down timer is zero")

    _check(not bool(controller.call("apply_reaction", -1, 5)), "Invalid negative reaction kind is rejected")
    _check(not bool(controller.call("apply_reaction", 3, 5)), "Unknown reaction kind is rejected")
    _check(not bool(controller.call("apply_hitstun", 0)), "Zero-duration Hitstun is rejected")
    _check(not bool(controller.call("apply_blockstun", -5)), "Negative-duration Blockstun is rejected")
    _check(not bool(controller.call("apply_down", 0)), "Zero-duration Down is rejected")

    _check(not bool(controller.call("is_control_locked")), "Invalid reactions do not lock controls")


func _test_hitstun_countdown() -> void:
    var controller := _make_controller()
    _connect_signals(controller)
    _reset_events()

    _check(bool(controller.call("apply_hitstun", 3)), "Hitstun can be started")
    _check(bool(controller.call("is_control_locked")), "Hitstun locks control")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 3, "Hitstun starts with exact duration")
    _check(int(controller.call("get_control_lock_remaining")) == 3, "Control lock reports Hitstun duration")

    controller.call("advance_tick")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 2, "First tick decrements Hitstun by one")
    _check(bool(controller.call("is_control_locked")), "Hitstun remains locked after first tick")

    controller.call("advance_tick")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 1, "Second tick decrements Hitstun by one")
    _check(bool(controller.call("is_control_locked")), "Hitstun remains locked before its final tick")

    controller.call("advance_tick")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 0, "Third tick ends Hitstun")
    _check(not bool(controller.call("is_control_locked")), "Control unlocks exactly when Hitstun expires")
    _check(_ended_events.size() == 1, "Hitstun emits one reaction_ended signal")
    _check(_ended_events[0] == HitReactionScript.ReactionKind.HITSTUN, "Hitstun emits the correct ended kind")
    _check(_lock_events.size() == 2, "Control lock emits one start and one end transition")
    _check(_lock_events[0] == Vector2i(1, 3), "Control lock start reports locked state and duration")
    _check(_lock_events[1] == Vector2i(0, 0), "Control lock end reports unlocked state")


func _test_blockstun_and_down() -> void:
    var controller := _make_controller()

    _check(bool(controller.call("apply_blockstun", 8)), "Blockstun can be started")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.BLOCKSTUN)) == 8, "Blockstun stores exact duration")
    _check(int(controller.call("get_control_lock_remaining")) == 8, "Blockstun locks control for its duration")

    controller.call("clear_reactions")
    _check(bool(controller.call("apply_down", 48)), "Down reaction can be started")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.DOWN)) == 48, "Down stores exact duration")
    _check(int(controller.call("get_control_lock_remaining")) == 48, "Down locks control for its duration")

    for index in range(47):
        controller.call("advance_tick")

    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.DOWN)) == 1, "Down remains active through the penultimate tick")
    _check(bool(controller.call("is_control_locked")), "Down remains locked through the penultimate tick")

    controller.call("advance_tick")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.DOWN)) == 0, "Down ends on its final tick")
    _check(not bool(controller.call("is_control_locked")), "Down unlocks control after its final tick")


func _test_max_duration_policy() -> void:
    var controller := _make_controller()

    controller.call("apply_hitstun", 12)
    controller.call("apply_blockstun", 8)
    controller.call("apply_down", 4)

    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 12, "Hitstun timer remains independent")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.BLOCKSTUN)) == 8, "Blockstun timer remains independent")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.DOWN)) == 4, "Down timer remains independent")
    _check(int(controller.call("get_control_lock_remaining")) == 12, "Concurrent reactions use maximum duration, not sum")
    _check(bool(controller.call("is_control_locked")), "Concurrent reactions keep control locked")

    for index in range(8):
        controller.call("advance_tick")

    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.BLOCKSTUN)) == 0, "Shorter Blockstun expires independently")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.DOWN)) == 0, "Shorter Down expires independently")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 4, "Longer Hitstun continues after shorter reactions expire")
    _check(int(controller.call("get_control_lock_remaining")) == 4, "Remaining control lock is recalculated from active effects")
    _check(bool(controller.call("is_control_locked")), "One remaining reaction keeps controls locked")

    for index in range(4):
        controller.call("advance_tick")

    _check(not bool(controller.call("is_control_locked")), "Controls unlock when the longest reaction expires")
    _check(int(controller.call("get_control_lock_remaining")) == 0, "Maximum remaining duration reaches zero")


func _test_refresh_policy() -> void:
    var controller := _make_controller()
    _connect_signals(controller)
    _reset_events()

    _check(bool(controller.call("apply_hitstun", 10)), "Initial Hitstun starts")
    _check(not bool(controller.call("apply_hitstun", 6)), "Shorter Hitstun does not shorten existing timer")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 10, "Shorter refresh preserves existing duration")

    _check(bool(controller.call("apply_hitstun", 14)), "Longer Hitstun extends existing timer")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 14, "Longer refresh stores the larger duration")
    _check(_started_events.size() == 1, "Refreshing an active reaction does not emit another start")
    _check(_extended_events.size() == 1, "Longer refresh emits one extension signal")
    _check(_extended_events[0] == Vector3i(HitReactionScript.ReactionKind.HITSTUN, 10, 14), "Extension signal reports old and new durations")
    _check(_lock_events.size() == 1, "Extending an active control lock does not emit a second lock transition")

    controller.call("advance_tick")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 13, "Extended timer advances normally")


func _test_signals() -> void:
    var controller := _make_controller()
    _connect_signals(controller)
    _reset_events()

    controller.call("apply_blockstun", 5)
    controller.call("apply_down", 9)

    _check(_started_events.size() == 2, "Different reaction types each emit a start signal")
    _check(_lock_events.size() == 1, "Overlapping reactions emit only one lock-start transition")
    _check(_lock_events[0] == Vector2i(1, 5), "Lock-start transition reports duration at first lock")

    for index in range(5):
        controller.call("advance_tick")

    _check(_ended_events.size() == 1, "Expired Blockstun emits one ended signal")
    _check(_ended_events[0] == HitReactionScript.ReactionKind.BLOCKSTUN, "Ended signal identifies Blockstun")
    _check(_lock_events.size() == 1, "Ending one reaction does not unlock while another remains active")

    for index in range(4):
        controller.call("advance_tick")

    _check(_ended_events.size() == 2, "Down emits its ended signal when its timer expires")
    _check(_ended_events[1] == HitReactionScript.ReactionKind.DOWN, "Second ended signal identifies Down")
    _check(_lock_events.size() == 2, "Final reaction emits one control-unlock transition")


func _test_clear_reactions() -> void:
    var controller := _make_controller()
    _connect_signals(controller)
    _reset_events()

    controller.call("apply_hitstun", 6)
    controller.call("apply_down", 12)

    _check(bool(controller.call("is_control_locked")), "Active reactions lock control before clear")

    controller.call("clear_reactions")

    _check(not bool(controller.call("is_control_locked")), "Clear immediately unlocks controls")
    _check(int(controller.call("get_control_lock_remaining")) == 0, "Clear resets maximum remaining duration")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.HITSTUN)) == 0, "Clear resets Hitstun timer")
    _check(int(controller.call("get_remaining_ticks", HitReactionScript.ReactionKind.DOWN)) == 0, "Clear resets Down timer")
    _check(_ended_events.size() == 2, "Clear emits ended for every active reaction")
    _check(_lock_events.size() == 2, "Clear emits one control-unlock transition")

    controller.call("advance_tick")
    _check(_ended_events.size() == 2, "Advancing after clear does not emit duplicate ended signals")
    _check(_lock_events.size() == 2, "Advancing after clear does not emit duplicate lock transitions")