class_name LocomotionStateMachine
extends RefCounted

## M3 locomotion subset. Combat states are owned by later combat integration.
enum State {
	NEUTRAL,
	FORWARD_WALK,
	BACKWALK,
	CROUCH,
	JUMP_FALL,
}

var current_state: int = State.NEUTRAL


func update(
	frame: InputFrame,
	is_grounded: bool,
	facing: int,
	jump_started: bool = false
) -> int:
	if frame == null:
		push_error("LocomotionStateMachine.update(): frame cannot be null")
		return current_state

	# JumpFall covers both rising and falling portions of an airborne jump.
	if not is_grounded or jump_started:
		current_state = State.JUMP_FALL
		return current_state

	# Crouch is a grounded state and takes priority over walk direction.
	if frame.is_held(InputBits.CROUCH):
		current_state = State.CROUCH
		return current_state

	var direction: int = horizontal_direction(frame)
	if direction == 0:
		current_state = State.NEUTRAL
		return current_state

	var facing_sign: int = -1 if facing == -1 else 1
	if direction == facing_sign:
		current_state = State.FORWARD_WALK
	else:
		current_state = State.BACKWALK
	return current_state


static func horizontal_direction(frame: InputFrame) -> int:
	if frame == null:
		return 0

	var left_held: bool = frame.is_held(InputBits.MOVE_LEFT)
	var right_held: bool = frame.is_held(InputBits.MOVE_RIGHT)
	if left_held == right_held:
		return 0
	return -1 if left_held else 1
