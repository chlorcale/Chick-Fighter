class_name HitReactionController
extends RefCounted

## M8: tick-based reaction timers.
## This controller does not own velocity, movement, damage, or animation.

signal reaction_started(reaction_kind: int, duration_ticks: int)
signal reaction_extended(reaction_kind: int, previous_ticks: int, new_ticks: int)
signal reaction_ended(reaction_kind: int)

## Emitted only when the overall control-lock state changes.
## The remaining duration is the maximum of all active reaction timers.
signal control_lock_changed(is_locked: bool, remaining_ticks: int)

enum ReactionKind {
    HITSTUN,
    BLOCKSTUN,
    DOWN,
}

var _remaining_ticks: Array[int] = [0, 0, 0]


## Applies or refreshes one reaction timer.
## A shorter/equal duration never shortens an existing reaction.
## Returns true only when the timer is started or extended.
func apply_reaction(reaction_kind: int, duration_ticks: int) -> bool:
    if not _is_valid_reaction_kind(reaction_kind):
        return false
    if duration_ticks <= 0:
        return false

    var was_locked: bool = is_control_locked()
    var previous_ticks: int = _remaining_ticks[reaction_kind]

    if duration_ticks <= previous_ticks:
        return false

    _remaining_ticks[reaction_kind] = duration_ticks

    if previous_ticks == 0:
        reaction_started.emit(reaction_kind, duration_ticks)
    else:
        reaction_extended.emit(reaction_kind, previous_ticks, duration_ticks)

    if not was_locked:
        control_lock_changed.emit(true, get_control_lock_remaining())

    return true


func apply_hitstun(duration_ticks: int) -> bool:
    return apply_reaction(ReactionKind.HITSTUN, duration_ticks)


func apply_blockstun(duration_ticks: int) -> bool:
    return apply_reaction(ReactionKind.BLOCKSTUN, duration_ticks)


func apply_down(duration_ticks: int) -> bool:
    return apply_reaction(ReactionKind.DOWN, duration_ticks)


## Advance exactly once per fixed physics tick.
func advance_tick() -> void:
    var was_locked: bool = is_control_locked()

    for reaction_kind in range(ReactionKind.size()):
        if _remaining_ticks[reaction_kind] <= 0:
            continue

        _remaining_ticks[reaction_kind] -= 1

        if _remaining_ticks[reaction_kind] == 0:
            reaction_ended.emit(reaction_kind)

    if was_locked and not is_control_locked():
        control_lock_changed.emit(false, 0)


## Clears every active reaction immediately.
func clear_reactions() -> void:
    var was_locked: bool = is_control_locked()

    for reaction_kind in range(ReactionKind.size()):
        if _remaining_ticks[reaction_kind] <= 0:
            continue

        _remaining_ticks[reaction_kind] = 0
        reaction_ended.emit(reaction_kind)

    if was_locked:
        control_lock_changed.emit(false, 0)


func get_remaining_ticks(reaction_kind: int) -> int:
    if not _is_valid_reaction_kind(reaction_kind):
        return 0

    return _remaining_ticks[reaction_kind]


## Control lock uses MAX remaining duration, never the sum of timers.
func get_control_lock_remaining() -> int:
    var maximum_remaining: int = 0

    for remaining in _remaining_ticks:
        maximum_remaining = maxi(maximum_remaining, remaining)

    return maximum_remaining


func is_control_locked() -> bool:
    return get_control_lock_remaining() > 0


func is_reacting() -> bool:
    return is_control_locked()


func _is_valid_reaction_kind(reaction_kind: int) -> bool:
    return reaction_kind >= ReactionKind.HITSTUN \
        and reaction_kind <= ReactionKind.DOWN