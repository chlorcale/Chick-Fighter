class_name InputBits
extends RefCounted

# Logical input bit indices. Physical keys and Input Map action names stay outside this class.
const MOVE_LEFT: int = 0
const MOVE_RIGHT: int = 1
const JUMP: int = 2
const CROUCH: int = 3
const LIGHT: int = 4
const HEAVY: int = 5
const SPECIAL: int = 6
const CARD_PREV: int = 7
const CARD_NEXT: int = 8
const CARD_USE: int = 9
const ACTION_H: int = 10

const COUNT: int = 11
const MASK: int = 0x7FF
const NAMES: Array[String] = [
	"MOVE_LEFT",
	"MOVE_RIGHT",
	"JUMP",
	"CROUCH",
	"LIGHT",
	"HEAVY",
	"SPECIAL",
	"CARD_PREV",
	"CARD_NEXT",
	"CARD_USE",
	"ACTION_H",
]


static func bit(index: int) -> int:
	if index < 0 or index >= COUNT:
		push_error("InputBits.bit(): index out of range: %d" % index)
		return 0
	return 1 << index


static func index_from_name(input_name: StringName) -> int:
	return NAMES.find(String(input_name))


static func names_from_mask(mask: int) -> PackedStringArray:
	var result := PackedStringArray()
	var valid_mask: int = mask & MASK
	for index in range(COUNT):
		if (valid_mask & bit(index)) != 0:
			result.append(NAMES[index])
	return result


static func mask_from_names(input_names: Array) -> int:
	var result: int = 0
	for input_name in input_names:
		var index := index_from_name(StringName(input_name))
		if index >= 0:
			result |= bit(index)
	return result & MASK
