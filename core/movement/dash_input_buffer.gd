class_name DashInputBuffer
extends RefCounted

## Detects a same-direction double tap using simulation ticks.
## This is the 8-tick command window only; it is not a general-purpose
## attack/input leniency buffer.
const DOUBLE_TAP_WINDOW_TICKS: int = 8
const NO_DASH: int = 0
const LEFT: int = -1
const RIGHT: int = 1

var _last_left_tap_tick: int = -1
var _last_right_tap_tick: int = -1
var _last_sampled_tick: int = -1


func consume_frame(frame: InputFrame) -> int:
	if frame == null:
		push_error("DashInputBuffer.consume_frame(): frame cannot be null")
		return NO_DASH
	if frame.tick <= _last_sampled_tick:
		push_error("DashInputBuffer.consume_frame(): ticks must increase (%d <= %d)" % [frame.tick, _last_sampled_tick])
		return NO_DASH
	_last_sampled_tick = frame.tick

	var left_pressed: bool = frame.is_pressed(InputBits.MOVE_LEFT)
	var right_pressed: bool = frame.is_pressed(InputBits.MOVE_RIGHT)
	if left_pressed == right_pressed:
		return NO_DASH

	if left_pressed:
		if _is_second_tap(frame.tick, _last_left_tap_tick):
			_last_left_tap_tick = -1
			return LEFT
		_last_left_tap_tick = frame.tick
		return NO_DASH

	if _is_second_tap(frame.tick, _last_right_tap_tick):
		_last_right_tap_tick = -1
		return RIGHT
	_last_right_tap_tick = frame.tick
	return NO_DASH


func clear() -> void:
	_last_left_tap_tick = -1
	_last_right_tap_tick = -1
	_last_sampled_tick = -1


func _is_second_tap(current_tick: int, previous_tick: int) -> bool:
	if previous_tick < 0:
		return false
	var elapsed_ticks: int = current_tick - previous_tick
	return elapsed_ticks > 0 and elapsed_ticks <= DOUBLE_TAP_WINDOW_TICKS
