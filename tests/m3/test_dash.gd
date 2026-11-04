extends RefCounted

const DashInputBufferScript = preload("res://core/movement/dash_input_buffer.gd")
const DashControllerScript = preload("res://core/movement/dash_controller.gd")
const InputFrameScript = preload("res://core/input/input_frame.gd")

var _passed: int = 0
var _failed: int = 0


func run() -> Dictionary:
	_passed = 0
	_failed = 0
	_test_double_tap_buffer()
	_test_dash_travel_and_distance()
	_test_dash_recovery()
	return {"passed": _passed, "failed": _failed}


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)


func _frame(tick: int, held: int = 0, pressed: int = 0) -> InputFrame:
	return InputFrameScript.new(tick, held, pressed, 0)


func _test_double_tap_buffer() -> void:
	var buffer = DashInputBufferScript.new()
	var left: int = InputBits.bit(InputBits.MOVE_LEFT)
	var right: int = InputBits.bit(InputBits.MOVE_RIGHT)

	_expect(buffer.consume_frame(_frame(0, left, left)) == DashInputBufferScript.NO_DASH, "First left tap is buffered, not dashed")
	_expect(buffer.consume_frame(_frame(4, 0, 0)) == DashInputBufferScript.NO_DASH, "Release between taps does not trigger dash")
	_expect(buffer.consume_frame(_frame(8, left, left)) == DashInputBufferScript.LEFT, "Second left tap within 8 ticks triggers left dash")
	_expect(buffer.consume_frame(_frame(9, 0, 0)) == DashInputBufferScript.NO_DASH, "Consumed double tap cannot trigger twice")

	buffer.clear()
	_expect(buffer.consume_frame(_frame(20, right, right)) == DashInputBufferScript.NO_DASH, "First right tap is buffered")
	_expect(buffer.consume_frame(_frame(29, right, right)) == DashInputBufferScript.NO_DASH, "Right tap after the 8-tick window starts a new pair")
	_expect(buffer.consume_frame(_frame(30, 0, 0)) == DashInputBufferScript.NO_DASH, "Release after a late tap does not trigger dash")
	_expect(buffer.consume_frame(_frame(37, right, right)) == DashInputBufferScript.RIGHT, "New right tap within the refreshed window triggers dash")

	buffer.clear()
	_expect(buffer.consume_frame(_frame(50, left, left)) == DashInputBufferScript.NO_DASH, "Left tap begins an independent sequence")
	_expect(buffer.consume_frame(_frame(53, right, right)) == DashInputBufferScript.NO_DASH, "Opposite direction does not complete left double tap")
	_expect(buffer.consume_frame(_frame(56, left, left)) == DashInputBufferScript.LEFT, "Same direction can complete despite an intervening opposite tap")

	buffer.clear()
	_expect(buffer.consume_frame(_frame(70, left | right, left | right)) == DashInputBufferScript.NO_DASH, "Simultaneous opposite press is ambiguous and ignored")


func _test_dash_travel_and_distance() -> void:
	var dash = DashControllerScript.new()
	_expect(dash.begin_dash(-1), "Dash starts in the left direction")
	_expect(dash.state == DashControllerScript.State.TRAVEL, "Dash enters travel state")
	_expect(is_equal_approx(dash.get_horizontal_velocity(), -600.0), "Left dash velocity is -600 px/s")
	_expect(not dash.begin_dash(1), "A second dash cannot start during travel")

	var total_distance: float = 0.0
	for tick in range(DashControllerScript.DASH_DURATION_TICKS):
		total_distance += absf(dash.get_horizontal_velocity()) * DashControllerScript.FIXED_DELTA
		dash.advance_tick()
		if tick == 10:
			_expect(dash.is_travelling, "Dash remains active through the first 11 travel ticks")

	_expect(is_equal_approx(total_distance, 120.0), "12 travel ticks cover exactly 120 px")
	_expect(dash.state == DashControllerScript.State.RECOVERY, "Dash enters recovery after exactly 12 travel ticks")
	_expect(is_zero_approx(dash.get_horizontal_velocity()), "Dash horizontal override ends after travel")

	var right_dash = DashControllerScript.new()
	_expect(right_dash.begin_dash(1), "Dash starts in the right direction")
	_expect(is_equal_approx(right_dash.get_horizontal_velocity(), 600.0), "Right dash velocity is +600 px/s")


func _test_dash_recovery() -> void:
	var dash = DashControllerScript.new()
	dash.begin_dash(1)
	for tick in range(DashControllerScript.DASH_DURATION_TICKS):
		dash.advance_tick()

	_expect(dash.recovery_ticks_remaining == 30, "Recovery is 30 ticks (0.5 seconds at 60 Hz)")
	_expect(not dash.can_start, "Dash cannot restart during recovery")
	for tick in range(29):
		dash.advance_tick()
	_expect(not dash.can_start, "Dash remains unavailable before all 30 recovery ticks elapse")
	dash.advance_tick()
	_expect(dash.can_start, "Dash becomes available after 30 recovery ticks")
	_expect(dash.begin_dash(-1), "A new dash can start after recovery")
	_expect(not dash.begin_dash(0), "Zero direction is rejected")
