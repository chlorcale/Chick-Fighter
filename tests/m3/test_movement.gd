extends RefCounted

const MovementConfigScript = preload("res://core/movement/movement_config.gd")
const LocomotionStateMachineScript = preload("res://core/movement/locomotion_state_machine.gd")
const MovementControllerScript = preload("res://core/movement/movement_controller.gd")
const InputFrameScript = preload("res://core/input/input_frame.gd")

var _passed: int = 0
var _failed: int = 0


func run() -> Dictionary:
	_passed = 0
	_failed = 0
	_test_breed_presets()
	_test_locomotion_states()
	_test_velocity_calculation()
	_test_fixed_tick_contract()
	return {"passed": _passed, "failed": _failed}


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)


func _frame(tick: int, held: int = 0, pressed: int = 0, released: int = 0) -> InputFrame:
	return InputFrameScript.new(tick, held, pressed, released)


func _test_breed_presets() -> void:
	var ga_noi = MovementConfigScript.new(MovementConfigScript.Breed.GA_NOI)
	var ga_tre = MovementConfigScript.new(MovementConfigScript.Breed.GA_TRE)
	_expect(is_equal_approx(ga_noi.speed, 200.0), "Gà nòi speed preset is 200")
	_expect(is_equal_approx(ga_tre.speed, 260.0), "Gà tre speed preset is 260")
	_expect(is_equal_approx(ga_noi.jump_impulse, 600.0), "Gà nòi jump impulse is 600")
	_expect(is_equal_approx(ga_tre.jump_impulse, 600.0), "Gà tre jump impulse is 600")
	_expect(is_equal_approx(ga_noi.gravity, 2000.0), "Gà nòi gravity is 2000")
	_expect(is_equal_approx(ga_tre.gravity, 2000.0), "Gà tre gravity is 2000")


func _test_locomotion_states() -> void:
	var fsm = LocomotionStateMachineScript.new()
	var neutral: InputFrame = _frame(0)
	var move_right: InputFrame = _frame(1, InputBits.bit(InputBits.MOVE_RIGHT))
	var move_left: InputFrame = _frame(2, InputBits.bit(InputBits.MOVE_LEFT))
	var crouch_right: InputFrame = _frame(
		3,
		InputBits.bit(InputBits.CROUCH) | InputBits.bit(InputBits.MOVE_RIGHT)
	)
	var airborne_right: InputFrame = _frame(4, InputBits.bit(InputBits.MOVE_RIGHT))
	var jump_pressed: InputFrame = _frame(
		5,
		InputBits.bit(InputBits.JUMP),
		InputBits.bit(InputBits.JUMP)
	)
	var both_directions: InputFrame = _frame(
		6,
		InputBits.bit(InputBits.MOVE_LEFT) | InputBits.bit(InputBits.MOVE_RIGHT)
	)

	_expect(
		fsm.update(neutral, true, 1) == LocomotionStateMachineScript.State.NEUTRAL,
		"No directional input produces Neutral"
	)
	_expect(
		fsm.update(move_right, true, 1) == LocomotionStateMachineScript.State.FORWARD_WALK,
		"Right input while facing right produces ForwardWalk"
	)
	_expect(
		fsm.update(move_left, true, 1) == LocomotionStateMachineScript.State.BACKWALK,
		"Left input while facing right produces Backwalk"
	)
	_expect(
		fsm.update(move_right, true, -1) == LocomotionStateMachineScript.State.BACKWALK,
		"Right input while facing left produces Backwalk"
	)
	_expect(
		fsm.update(move_left, true, -1) == LocomotionStateMachineScript.State.FORWARD_WALK,
		"Left input while facing left produces ForwardWalk"
	)
	_expect(
		fsm.update(crouch_right, true, 1) == LocomotionStateMachineScript.State.CROUCH,
		"Grounded crouch takes priority over walk state"
	)
	_expect(
		fsm.update(airborne_right, false, 1) == LocomotionStateMachineScript.State.JUMP_FALL,
		"Airborne fighter remains in JumpFall"
	)
	_expect(
		fsm.update(jump_pressed, true, 1, true) == LocomotionStateMachineScript.State.JUMP_FALL,
		"Ground jump starts JumpFall immediately"
	)
	_expect(
		fsm.update(both_directions, true, 1) == LocomotionStateMachineScript.State.NEUTRAL,
		"Simultaneous left and right inputs cancel"
	)


func _test_velocity_calculation() -> void:
	var ga_noi = MovementConfigScript.new(MovementConfigScript.Breed.GA_NOI)
	var ga_tre = MovementConfigScript.new(MovementConfigScript.Breed.GA_TRE)
	var noi_controller = MovementControllerScript.new()
	var tre_controller = MovementControllerScript.new()
	_expect(noi_controller.configure(ga_noi), "Gà nòi preset configures movement controller")
	_expect(tre_controller.configure(ga_tre), "Gà tre preset configures movement controller")
	var right_mask: int = InputBits.bit(InputBits.MOVE_RIGHT)
	var left_mask: int = InputBits.bit(InputBits.MOVE_LEFT)
	var crouch_mask: int = InputBits.bit(InputBits.CROUCH)
	var jump_mask: int = InputBits.bit(InputBits.JUMP)

	var right_frame: InputFrame = _frame(10, right_mask)
	var left_frame: InputFrame = _frame(11, left_mask)
	var crouch_frame: InputFrame = _frame(12, crouch_mask | right_mask)
	var jump_frame: InputFrame = _frame(13, jump_mask, jump_mask)
	var both_frame: InputFrame = _frame(14, left_mask | right_mask)

	var noi_right: Vector2 = noi_controller.calculate_velocity(Vector2.ZERO, right_frame, true)
	var tre_right: Vector2 = tre_controller.calculate_velocity(Vector2.ZERO, right_frame, true)
	var noi_left: Vector2 = noi_controller.calculate_velocity(Vector2.ZERO, left_frame, true)
	var crouched: Vector2 = noi_controller.calculate_velocity(Vector2(120.0, 0.0), crouch_frame, true)
	var jumping: Vector2 = noi_controller.calculate_velocity(Vector2(0.0, 0.0), jump_frame, true)
	var falling: Vector2 = noi_controller.calculate_velocity(Vector2(0.0, 100.0), _frame(15), false)
	var airborne_right: Vector2 = tre_controller.calculate_velocity(Vector2(0.0, 100.0), right_frame, false)
	var cancelled: Vector2 = noi_controller.calculate_velocity(Vector2.ZERO, both_frame, true)
	var landed: Vector2 = noi_controller.calculate_velocity(Vector2(40.0, 30.0), _frame(16), true)

	_expect(is_equal_approx(noi_right.x, 200.0), "Gà nòi horizontal velocity uses speed 200")
	_expect(is_equal_approx(tre_right.x, 260.0), "Gà tre horizontal velocity uses speed 260")
	_expect(is_equal_approx(noi_left.x, -200.0), "Left input produces negative horizontal velocity")
	_expect(is_equal_approx(crouched.x, 0.0), "Grounded crouch stops horizontal movement")
	_expect(is_equal_approx(jumping.y, -600.0), "Jump press applies -600 vertical impulse")
	_expect(is_equal_approx(falling.y, 100.0 + (2000.0 / 60.0)), "Gravity adds 2000/60 per air tick")
	_expect(is_equal_approx(airborne_right.x, 260.0), "Horizontal movement remains available in air")
	_expect(is_equal_approx(cancelled.x, 0.0), "Opposite simultaneous directions produce zero horizontal velocity")
	_expect(is_equal_approx(landed.y, 0.0), "Ground contact clears vertical velocity")


func _test_fixed_tick_contract() -> void:
	_expect(MovementControllerScript.FIXED_TICK_RATE == 60, "Movement simulation runs at 60 fixed ticks per second")
	_expect(
		is_equal_approx(MovementControllerScript.FIXED_DELTA, 1.0 / 60.0),
		"Movement gravity uses fixed 1/60 second tick, not render delta"
	)
