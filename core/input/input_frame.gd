class_name InputFrame
extends RefCounted

# Immutable-by-interface, tick-based snapshot. The backing fields are intentionally private by convention.
var _tick: int
var _held: int
var _pressed: int
var _released: int

var tick: int:
	get:
		return _tick

var held: int:
	get:
		return _held

var pressed: int:
	get:
		return _pressed

var released: int:
	get:
		return _released


func _init(p_tick: int, p_held: int, p_pressed: int, p_released: int) -> void:
	_tick = p_tick
	_held = p_held & InputBits.MASK
	_pressed = p_pressed & InputBits.MASK
	_released = p_released & InputBits.MASK


static func from_states(
	p_tick: int,
	p_current: int,
	p_previous: int,
	p_latched_pressed: int = 0,
	p_latched_released: int = 0
) -> InputFrame:
	if p_tick < 0:
		push_error("InputFrame.from_states(): tick must be >= 0")
		return null

	var current: int = p_current & InputBits.MASK
	var previous: int = p_previous & InputBits.MASK
	var latched_pressed: int = p_latched_pressed & InputBits.MASK
	var latched_released: int = p_latched_released & InputBits.MASK
	var pressed_mask: int = ((current & ~previous) | latched_pressed) & InputBits.MASK
	var released_mask: int = ((previous & ~current) | latched_released) & InputBits.MASK
	return InputFrame.new(p_tick, current, pressed_mask, released_mask)


static func from_packed(data: PackedInt32Array) -> InputFrame:
	if data.size() != 4:
		push_error("InputFrame.from_packed(): expected [tick, held, pressed, released]")
		return null
	if data[0] < 0:
		push_error("InputFrame.from_packed(): tick must be >= 0")
		return null
	return InputFrame.new(data[0], data[1], data[2], data[3])


func is_held(bit_index: int) -> bool:
	return (_held & InputBits.bit(bit_index)) != 0


func is_pressed(bit_index: int) -> bool:
	return (_pressed & InputBits.bit(bit_index)) != 0


func is_released(bit_index: int) -> bool:
	return (_released & InputBits.bit(bit_index)) != 0


func to_packed() -> PackedInt32Array:
	return PackedInt32Array([_tick, _held, _pressed, _released])
