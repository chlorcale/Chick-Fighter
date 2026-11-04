class_name FacingController
extends RefCounted

## Horizontal facing values shared by fighter controllers.
## RIGHT = 1 means the opponent is to the owner's right.
## LEFT = -1 means the opponent is to the owner's left.
const LEFT: int = -1
const RIGHT: int = 1

var _facing: int = RIGHT
var _attack_sequence_locked: bool = false

## Read-only current facing. No setter is exposed intentionally.
var facing: int:
	get:
		return _facing

## True from entry into AttackStartup until AttackRecovery completes.
var is_attack_locked: bool:
	get:
		return _attack_sequence_locked


func _init(initial_facing: int = RIGHT) -> void:
	_facing = LEFT if initial_facing == LEFT else RIGHT


## Update facing from horizontal world positions.
## If both fighters have the same X coordinate, retain the last valid facing.
## While the attack sequence is locked, positions cannot change facing.
func update_facing(owner_global_x: float, opponent_global_x: float) -> int:
	if _attack_sequence_locked:
		return _facing

	var offset_x: float = opponent_global_x - owner_global_x
	if is_zero_approx(offset_x):
		return _facing

	_facing = RIGHT if offset_x > 0.0 else LEFT
	return _facing


## Call exactly when entering AttackStartup.
## This lock remains active through AttackActive and AttackRecovery.
func begin_attack_startup() -> void:
	_attack_sequence_locked = true


## Call exactly when AttackRecovery has completed.
## Unlock and immediately refresh facing using the fighters' current positions.
func finish_attack_recovery(owner_global_x: float, opponent_global_x: float) -> int:
	_attack_sequence_locked = false
	return update_facing(owner_global_x, opponent_global_x)
