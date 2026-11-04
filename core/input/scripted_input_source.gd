class_name ScriptedInputSource
extends InputSource

enum AfterEnd { NEUTRAL, HOLD_LAST }

var _start_tick: int = 0
var _masks: Array[int] = []
var _after_end: int = AfterEnd.NEUTRAL
var _tap_pressed: Dictionary = {}
var _tap_released: Dictionary = {}


func load_masks(start_tick: int, masks: Array, after_end: int = AfterEnd.NEUTRAL) -> bool:
	if start_tick < 0:
		push_error("ScriptedInputSource.load_masks(): start_tick must be >= 0")
		return false
	if after_end != AfterEnd.NEUTRAL and after_end != AfterEnd.HOLD_LAST:
		push_error("ScriptedInputSource.load_masks(): invalid after_end mode")
		return false

	# Validate into a temporary array first: failed loads never partially replace current data.
	var validated_masks: Array[int] = []
	for raw_mask in masks:
		if typeof(raw_mask) != TYPE_INT:
			push_error("ScriptedInputSource.load_masks(): every mask must be an integer")
			return false
		var mask: int = int(raw_mask)
		if mask < 0 or (mask & ~InputBits.MASK) != 0:
			push_error("ScriptedInputSource.load_masks(): mask has bits outside InputBits.MASK")
			return false
		validated_masks.append(mask)

	_start_tick = start_tick
	_masks = validated_masks
	_after_end = after_end
	_tap_pressed.clear()
	_tap_released.clear()
	return true


func add_tap(tick: int, bit_index: int) -> bool:
	if tick < 0:
		push_error("ScriptedInputSource.add_tap(): tick must be >= 0")
		return false
	if bit_index < 0 or bit_index >= InputBits.COUNT:
		push_error("ScriptedInputSource.add_tap(): bit index out of range")
		return false

	var tap_mask: int = InputBits.bit(bit_index)
	_tap_pressed[tick] = int(_tap_pressed.get(tick, 0)) | tap_mask
	_tap_released[tick] = int(_tap_released.get(tick, 0)) | tap_mask
	return true


func _held_at(tick: int) -> int:
	if tick < _start_tick or _masks.is_empty():
		return 0
	var index: int = tick - _start_tick
	if index < _masks.size():
		return _masks[index]
	if _after_end == AfterEnd.HOLD_LAST:
		return _masks[_masks.size() - 1]
	return 0


func sample(tick: int) -> InputFrame:
	if tick < 0:
		push_error("ScriptedInputSource.sample(): tick must be >= 0")
		return null
	var current: int = _held_at(tick)
	var previous: int = _held_at(tick - 1)
	var latched_pressed: int = int(_tap_pressed.get(tick, 0))
	var latched_released: int = int(_tap_released.get(tick, 0))
	return InputFrame.from_states(tick, current, previous, latched_pressed, latched_released)
