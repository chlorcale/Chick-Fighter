class_name DashController
extends RefCounted

## Deterministic horizontal dash timing for the 60 Hz combat simulation.
## The caller remains responsible for deciding whether the current fighter
## state is eligible to start a dash and for applying the returned horizontal
## velocity to CharacterBody2D.
enum State {
	READY,
	TRAVEL,
	RECOVERY,
}

const FIXED_TICK_RATE: int = 60
const FIXED_DELTA: float = 1.0 / float(FIXED_TICK_RATE)
const DASH_DURATION_TICKS: int = 12
const DASH_DISTANCE_PX: float = 120.0
const DASH_SPEED_PX_PER_SECOND: float = DASH_DISTANCE_PX / (DASH_DURATION_TICKS * FIXED_DELTA)
const RECOVERY_TICKS: int = 30 # 0.5 seconds at 60 simulation ticks/second.

var _state: int = State.READY
var _direction: int = 0
var _travel_ticks_remaining: int = 0
var _recovery_ticks_remaining: int = 0

var state: int:
	get:
		return _state

var direction: int:
	get:
		return _direction

var travel_ticks_remaining: int:
	get:
		return _travel_ticks_remaining

var recovery_ticks_remaining: int:
	get:
		return _recovery_ticks_remaining

var is_travelling: bool:
	get:
		return _state == State.TRAVEL

var can_start: bool:
	get:
		return _state == State.READY


## Returns false when already travelling/recovering or direction is invalid.
func begin_dash(p_direction: int) -> bool:
	if p_direction != -1 and p_direction != 1:
		push_error("DashController.begin_dash(): direction must be -1 or +1")
		return false
	if _state != State.READY:
		return false

	_direction = p_direction
	_state = State.TRAVEL
	_travel_ticks_remaining = DASH_DURATION_TICKS
	_recovery_ticks_remaining = 0
	return true


## Horizontal velocity to be applied for the current travel tick.
## Returns zero outside DASH_TRAVEL. Vertical velocity/gravity are untouched.
func get_horizontal_velocity() -> float:
	if _state != State.TRAVEL:
		return 0.0
	return float(_direction) * DASH_SPEED_PX_PER_SECOND


## Call once after movement has been applied for this simulation tick.
## Exactly 12 calls produce 12 travel ticks, then the 30-tick recovery begins.
func advance_tick() -> int:
	match _state:
		State.TRAVEL:
			_travel_ticks_remaining -= 1
			if _travel_ticks_remaining <= 0:
				_travel_ticks_remaining = 0
				_state = State.RECOVERY
				_recovery_ticks_remaining = RECOVERY_TICKS
		State.RECOVERY:
			_recovery_ticks_remaining -= 1
			if _recovery_ticks_remaining <= 0:
				_recovery_ticks_remaining = 0
				_state = State.READY
	return _state


func reset() -> void:
	_state = State.READY
	_direction = 0
	_travel_ticks_remaining = 0
	_recovery_ticks_remaining = 0
