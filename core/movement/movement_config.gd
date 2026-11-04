class_name MovementConfig
extends RefCounted

## Shared, breed-based movement presets.
## P1/P2 identity does not select a breed; the caller must provide it explicitly.
enum Breed {
	GA_NOI,
	GA_TRE,
}

const JUMP_IMPULSE: float = 600.0
const GRAVITY: float = 2000.0

var _breed: int = -1
var _speed: float = 0.0

var breed: int:
	get:
		return _breed

var speed: float:
	get:
		return _speed

var jump_impulse: float:
	get:
		return JUMP_IMPULSE

var gravity: float:
	get:
		return GRAVITY


func _init(p_breed: int) -> void:
	_breed = p_breed
	match p_breed:
		Breed.GA_NOI:
			_speed = 200.0
		Breed.GA_TRE:
			_speed = 260.0
		_:
			_breed = -1
			_speed = 0.0
			push_error("MovementConfig: unsupported breed preset: %d" % p_breed)
