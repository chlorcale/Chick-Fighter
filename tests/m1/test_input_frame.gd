extends RefCounted

var _passed: int = 0
var _failed: int = 0


func run(tree: SceneTree) -> Dictionary:
	_passed = 0
	_failed = 0
	_test_scripted_edges()
	_test_simultaneous_inputs()
	_test_short_tap()
	await _test_input_parse_integration(tree)
	_test_separate_player_mappings()
	_test_missing_action()
	_test_scripted_determinism()
	_test_mask_round_trip()
	_test_tick_rules()
	return {"passed": _passed, "failed": _failed}


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", description)
	else:
		_failed += 1
		push_error("[FAIL] " + description)


func _test_scripted_edges() -> void:
	var source := ScriptedInputSource.new()
	_check(source.load_masks(0, [0, 1, 1, 1, 0]), "Test 1: load held-state sequence")
	var frames: Array[InputFrame] = []
	for tick in range(5):
		frames.append(source.sample(tick))
	_check(frames[1].pressed == 1 and frames[2].pressed == 0, "Test 1: pressed is set only on rising edge")
	_check(frames[1].held == 1 and frames[2].held == 1 and frames[3].held == 1, "Test 2: held persists across ticks")
	_check(frames[4].released == 1 and frames[3].released == 0, "Test 3: released is set only on falling edge")


func _test_simultaneous_inputs() -> void:
	var mask: int = InputBits.bit(InputBits.MOVE_LEFT) | InputBits.bit(InputBits.LIGHT) | InputBits.bit(InputBits.ACTION_H)
	var frame := InputFrame.from_states(7, mask, 0)
	_check(
		frame.is_held(InputBits.MOVE_LEFT) and frame.is_pressed(InputBits.LIGHT) and frame.is_pressed(InputBits.ACTION_H)
		and not frame.is_held(InputBits.HEAVY),
		"Test 4: independent bits can be active simultaneously"
	)


func _test_short_tap() -> void:
	var source := LocalInputSource.new()
	_check(source.push_event(InputBits.LIGHT, true), "Test 5: queue tap press")
	_check(source.push_event(InputBits.LIGHT, false), "Test 5: queue tap release")
	var frame := source.sample(0)
	var tap_bit: int = InputBits.bit(InputBits.LIGHT)
	_check(frame.held == 0 and frame.pressed == tap_bit and frame.released == tap_bit, "Test 5: short tap survives inside one tick")


func _test_input_parse_integration(tree: SceneTree) -> void:
	if not InputMap.has_action(&"p1_left"):
		_check(false, "Test 5 integration: baseline action p1_left exists")
		return

	var source := LocalInputSource.new()
	source.configure({InputBits.MOVE_LEFT: &"p1_left"})
	var capture := LocalInputCapture.new()
	capture.bind(source)
	tree.root.add_child(capture)
	await tree.process_frame

	var press := InputEventKey.new()
	press.physical_keycode = KEY_A
	press.pressed = true
	Input.parse_input_event(press)
	await tree.process_frame

	var release := InputEventKey.new()
	release.physical_keycode = KEY_A
	release.pressed = false
	Input.parse_input_event(release)
	await tree.process_frame

	var frame := source.sample(0)
	var move_left_mask: int = InputBits.bit(InputBits.MOVE_LEFT)
	_check(
		frame.held == 0 and (frame.pressed & move_left_mask) != 0 and (frame.released & move_left_mask) != 0,
		"Test 5 integration: Input.parse_input_event reaches LocalInputCapture without losing tap"
	)
	capture.queue_free()
	await tree.process_frame


func _test_separate_player_mappings() -> void:
	var p1 := LocalInputSource.new()
	var p2 := LocalInputSource.new()
	p1.configure({InputBits.MOVE_LEFT: &"p1_left"})
	p2.configure({InputBits.MOVE_LEFT: &"p2_left"})

	var p1_key := InputEventKey.new()
	p1_key.physical_keycode = KEY_A
	p1_key.pressed = true
	p1.feed_event(p1_key)
	var p1_frame := p1.sample(0)
	var p2_after_a := p2.sample(0)

	var p2_key := InputEventKey.new()
	p2_key.physical_keycode = KEY_LEFT
	p2_key.pressed = true
	p1.feed_event(p2_key)
	p2.feed_event(p2_key)
	var p1_after_arrow := p1.sample(1)
	var p2_frame := p2.sample(1)

	_check(
		p1_frame.is_held(InputBits.MOVE_LEFT) and not p2_after_a.is_held(InputBits.MOVE_LEFT)
		and p2_frame.is_held(InputBits.MOVE_LEFT) and p1_after_arrow.is_held(InputBits.MOVE_LEFT),
		"Test 6: P1 and P2 physical mappings produce the same logical bit"
	)


func _test_missing_action() -> void:
	var source := LocalInputSource.new()
	source.configure({InputBits.LIGHT: &"p1_light"})
	var missing := source.get_missing_actions()
	var frame := source.sample(0)
	_check(
		missing.has(&"p1_light") and frame.held == 0 and frame.pressed == 0 and frame.released == 0,
		"Test 7: missing Input Map action is reported and does not crash or set a bit"
	)


func _test_scripted_determinism() -> void:
	var source_a := ScriptedInputSource.new()
	var source_b := ScriptedInputSource.new()
	var masks: Array = [0, 1, 3, 2, 0]
	source_a.load_masks(0, masks)
	source_b.load_masks(0, masks)
	var expected: Dictionary = {}
	for tick in range(5):
		expected[tick] = source_a.sample(tick).to_packed()
	var query_order: Array[int] = [4, 2, 0, 3, 1, 2]
	var deterministic := true
	for tick in query_order:
		if source_b.sample(tick).to_packed() != expected[tick]:
			deterministic = false
			break
	_check(deterministic, "Test 8: scripted source is deterministic for skipped and repeated samples")

	var tap_source := ScriptedInputSource.new()
	tap_source.load_masks(0, [0])
	_check(tap_source.add_tap(0, InputBits.SPECIAL), "Test 8: add scripted tap")
	var tap_frame := tap_source.sample(0)
	var special_mask: int = InputBits.bit(InputBits.SPECIAL)
	_check(tap_frame.held == 0 and tap_frame.pressed == special_mask and tap_frame.released == special_mask, "Test 8: scripted tap sets both edge masks")


func _test_mask_round_trip() -> void:
	var round_trip_ok := true
	for mask in range(InputBits.MASK + 1):
		var original := InputFrame.from_states(123, mask, 0)
		var restored := InputFrame.from_packed(original.to_packed())
		if restored == null or restored.tick != 123 or restored.held != mask or restored.pressed != mask:
			round_trip_ok = false
			break
	_check(round_trip_ok, "Test 9: all 2048 masks round-trip through PackedInt32Array")

	var clipped := InputFrame.from_states(0, 0xFFFF, 0)
	_check(clipped.held == InputBits.MASK, "Test 9: InputFrame factory clips out-of-range bits")
	var scripted := ScriptedInputSource.new()
	_check(not scripted.load_masks(0, [0, 0x800]), "Test 9: ScriptedInputSource rejects out-of-range masks atomically")


func _test_tick_rules() -> void:
	var source := LocalInputSource.new()
	source.configure({})
	source.push_event(InputBits.MOVE_RIGHT, true)
	var first := source.sample(5)
	var same_tick := source.sample(5)
	_check(first == same_tick, "Test 10: repeated sample of same tick returns the cached frame")

	var backwards := source.sample(4)
	_check(backwards == null, "Test 10: backwards tick is rejected")

	source.push_event(InputBits.MOVE_RIGHT, false)
	var skipped := source.sample(9)
	_check(
		skipped.held == 0 and skipped.released == InputBits.bit(InputBits.MOVE_RIGHT),
		"Test 10: skipped ticks are not fabricated; queued events apply to the next sample"
	)

	source.push_event(InputBits.JUMP, true)
	source.sample(10)
	source.release_all()
	var focus_released := source.sample(11)
	_check(
		focus_released.held == 0 and focus_released.released == InputBits.bit(InputBits.JUMP),
		"Local input: focus loss releases held inputs to prevent stuck keys"
	)
