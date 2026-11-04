extends RefCounted

const Player1Script = preload("res://player_1.gd")
const InputFrameScript = preload("res://core/input/input_frame.gd")
const InputBitsScript = preload("res://core/input/input_bits.gd")

var _passed: int = 0
var _failed: int = 0


func run(tree: SceneTree) -> Dictionary:
	_passed = 0
	_failed = 0
	await _test_fighter_reaction_lock(tree)
	return {"passed": _passed, "failed": _failed}


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)


func _test_fighter_reaction_lock(tree: SceneTree) -> void:
	var stage := Node2D.new()
	stage.name = "M8FighterReactionIntegrationTest"

	var fighter: CharacterBody2D = Player1Script.new() as CharacterBody2D
	fighter.name = "M8TestFighter"
	fighter.set_physics_process(false)
	fighter.set("dash_policy", 2)

	stage.add_child(fighter)
	tree.root.add_child(stage)
	await tree.process_frame
	fighter.set_physics_process(false)

	var right_bit: int = 1 << InputBitsScript.MOVE_RIGHT
	var jump_bit: int = 1 << InputBitsScript.JUMP
	var crouch_bit: int = 1 << InputBitsScript.CROUCH
	var movement_mask: int = right_bit | jump_bit | crouch_bit

	var raw_frame: InputFrame = InputFrameScript.new(
		0,
		movement_mask,
		movement_mask,
		0
	)

	var filtered: InputFrame = fighter.call(
		"_filter_movement_input",
		raw_frame,
		true
	)
	_check(filtered.held == 0, "Reaction lock clears held movement/jump/crouch input")
	_check(filtered.pressed == 0, "Reaction lock clears pressed movement/jump/crouch input")
	_check(filtered.tick == raw_frame.tick, "Filtered frame preserves simulation tick")

	var normal_frame: InputFrame = fighter.call(
		"_filter_movement_input",
		raw_frame,
		false
	)
	_check(normal_frame.held == raw_frame.held, "Unlocked fighter preserves held input")
	_check(normal_frame.pressed == raw_frame.pressed, "Unlocked fighter preserves pressed input")

	_check(bool(fighter.call("apply_hitstun", 2)), "Fighter accepts Hitstun through public API")
	_check(bool(fighter.call("is_control_locked")), "Fighter reports control lock immediately")

	# Step 1: control is locked; movement is neutral, but gravity is still applied.
	await tree.physics_frame
	var first_frame: InputFrame = InputFrameScript.new(Engine.get_physics_frames(), right_bit, right_bit, 0)
	fighter.call("step_with_input_frame", first_frame)

	_check(is_zero_approx(fighter.velocity.x), "Hitstun suppresses horizontal movement")
	_check(fighter.velocity.y > 0.0, "Gravity continues during airborne Hitstun")
	_check(bool(fighter.call("is_control_locked")), "First locked tick consumes one reaction tick")
	_check(not bool(fighter.call("is_dashing")), "Dash cannot start during Hitstun")

	# Step 2: final Hitstun tick; unlock occurs after movement.
	await tree.physics_frame
	var second_frame: InputFrame = InputFrameScript.new(Engine.get_physics_frames(), right_bit, right_bit, 0)
	fighter.call("step_with_input_frame", second_frame)

	_check(not bool(fighter.call("is_control_locked")), "Fighter unlocks after exact Hitstun duration")
	_check(not bool(fighter.call("is_dashing")), "Dash taps made during Hitstun are discarded")

	# The first tap after recovery must prime a fresh buffer.
	await tree.physics_frame
	var third_frame: InputFrame = InputFrameScript.new(Engine.get_physics_frames(), right_bit, right_bit, 0)
	fighter.call("step_with_input_frame", third_frame)
	_check(not bool(fighter.call("is_dashing")), "First post-recovery tap only primes Dash buffer")

	# A second tap within the 8-tick window may now start Dash.
	await tree.physics_frame
	var fourth_frame: InputFrame = InputFrameScript.new(Engine.get_physics_frames(), right_bit, right_bit, 0)
	fighter.call("step_with_input_frame", fourth_frame)
	_check(bool(fighter.call("is_dashing")), "Double-tap Dash works again after recovery")

	# Blockstun must suppress an already-active Dash override.
	_check(bool(fighter.call("apply_blockstun", 1)), "Fighter accepts Blockstun through public API")
	await tree.physics_frame
	var fifth_frame: InputFrame = InputFrameScript.new(Engine.get_physics_frames(), right_bit, right_bit, 0)
	fighter.call("step_with_input_frame", fifth_frame)

	_check(is_zero_approx(fighter.velocity.x), "Blockstun suppresses horizontal Dash override")
	_check(not bool(fighter.call("is_control_locked")), "One-tick Blockstun expires after one movement tick")

	_check(bool(fighter.call("apply_down", 1)), "Fighter accepts Down through public API")
	_check(bool(fighter.call("is_control_locked")), "Down also locks fighter control")
	fighter.call("clear_hit_reactions")
	_check(not bool(fighter.call("is_control_locked")), "Fighter can clear all active reactions")

	stage.queue_free()
	await tree.process_frame