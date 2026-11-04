class_name MovementController
extends RefCounted

## Movement is stepped at the project's fixed 60 Hz physics tick.
## This remains the sole owner of velocity, gravity and move_and_slide().
const FIXED_TICK_RATE: int = 60
const FIXED_DELTA: float = 1.0 / float(FIXED_TICK_RATE)

var _config: MovementConfig
var _locomotion_fsm: LocomotionStateMachine

var config: MovementConfig:
	get:
		return _config

var locomotion_state: int:
	get:
		if _locomotion_fsm == null:
			return LocomotionStateMachine.State.NEUTRAL
		return _locomotion_fsm.current_state


func _init() -> void:
	_locomotion_fsm = LocomotionStateMachine.new()


## Configure the breed preset after construction.
func configure(p_config: MovementConfig) -> bool:
	if p_config == null:
		push_error("MovementController.configure(): MovementConfig cannot be null")
		return false
	_config = p_config
	return true


## Pure velocity calculation. Horizontal input remains active in the air.
## Grounded crouch stops horizontal movement; crouch-walk is not invented.
func calculate_velocity(
	current_velocity: Vector2,
	frame: InputFrame,
	is_grounded: bool
) -> Vector2:
	if _config == null:
		push_error("MovementController.calculate_velocity(): config is missing")
		return current_velocity
	if frame == null:
		push_error("MovementController.calculate_velocity(): frame cannot be null")
		return current_velocity

	var next_velocity: Vector2 = current_velocity
	var direction: int = LocomotionStateMachine.horizontal_direction(frame)

	if is_grounded and frame.is_held(InputBits.CROUCH) and not frame.is_pressed(InputBits.JUMP):
		direction = 0

	next_velocity.x = float(direction) * _config.speed

	if is_grounded:
		if frame.is_pressed(InputBits.JUMP):
			next_velocity.y = -_config.jump_impulse
		else:
			next_velocity.y = 0.0
	else:
		next_velocity.y += _config.gravity * FIXED_DELTA

	return next_velocity


## Call once per fixed 60 Hz physics tick.
## `facing` is -1 (LEFT) or +1 (RIGHT), supplied by FacingController.
## Optional horizontal override is used by DashController during DASH_TRAVEL.
## Gravity and vertical velocity remain owned and processed here during Dash.
## The original 3-argument call remains valid for M3 callers.
func physics_step(
	body: CharacterBody2D,
	frame: InputFrame,
	facing: int,
	horizontal_override_enabled: bool = false,
	horizontal_velocity_override: float = 0.0
) -> int:
	if body == null:
		push_error("MovementController.physics_step(): body cannot be null")
		return locomotion_state
	if frame == null:
		push_error("MovementController.physics_step(): frame cannot be null")
		return locomotion_state

	var grounded_before_move: bool = body.is_on_floor()
	var jump_started: bool = grounded_before_move and frame.is_pressed(InputBits.JUMP)
	var next_velocity: Vector2 = calculate_velocity(body.velocity, frame, grounded_before_move)
	if horizontal_override_enabled:
		next_velocity.x = horizontal_velocity_override

	body.velocity = next_velocity
	body.move_and_slide()

	return _locomotion_fsm.update(frame, body.is_on_floor(), facing, jump_started)