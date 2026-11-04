class_name HealthComponent
extends Node

## M7: standalone health and alive/dead state.
## This component does not resolve hits, block, knockback, or movement.

signal health_changed(current_hp: int, max_hp: int, delta: int)
signal died
signal revived

## Technical default only. Set the actual fighter HP through the Inspector/configuration.
@export_range(1, 999999, 1) var max_hp: int = 100

## -1 means start at full HP. Other values are clamped to [0, max_hp].
@export_range(-1, 999999, 1) var initial_hp: int = -1

var _current_hp: int = 0
var _is_alive: bool = false
var _initialized: bool = false


func _ready() -> void:
    if _initialized:
        return

    if not configure(max_hp, initial_hp):
        push_error("HealthComponent: invalid exported HP configuration")


## Setup API. This does not emit gameplay signals.
## Use restore_full_health() for an in-game reset/revival.
func configure(maximum_hp: int, starting_hp: int = -1) -> bool:
    if maximum_hp <= 0 or starting_hp < -1:
        return false

    max_hp = maximum_hp
    initial_hp = starting_hp

    if starting_hp == -1:
        _current_hp = maximum_hp
    else:
        _current_hp = clampi(starting_hp, 0, maximum_hp)

    _is_alive = _current_hp > 0
    _initialized = true
    return true


## Applies damage and returns the actual HP removed.
## Non-positive damage and damage to a defeated fighter are ignored.
func apply_damage(amount: int) -> int:
    if not _initialized or not _is_alive or amount <= 0:
        return 0

    var applied_damage: int = mini(amount, _current_hp)
    if applied_damage <= 0:
        return 0

    _current_hp -= applied_damage
    health_changed.emit(_current_hp, max_hp, -applied_damage)

    if _current_hp == 0:
        _is_alive = false
        died.emit()

    return applied_damage


## Restores HP and returns the actual HP restored.
## A defeated fighter cannot be revived through healing.
func heal(amount: int) -> int:
    if not _initialized or not _is_alive or amount <= 0:
        return 0

    var restored_hp: int = mini(amount, max_hp - _current_hp)
    if restored_hp <= 0:
        return 0

    _current_hp += restored_hp
    health_changed.emit(_current_hp, max_hp, restored_hp)
    return restored_hp


## Restores full HP. Also revives a defeated fighter.
## Returns the amount of HP restored.
func restore_full_health() -> int:
    if not _initialized:
        return 0

    var was_alive: bool = _is_alive
    var restored_hp: int = max_hp - _current_hp

    if restored_hp > 0:
        _current_hp = max_hp
        health_changed.emit(_current_hp, max_hp, restored_hp)

    _is_alive = true

    if not was_alive:
        revived.emit()

    return restored_hp


func get_current_hp() -> int:
    return _current_hp


func get_max_hp() -> int:
    return max_hp


func is_alive() -> bool:
    return _initialized and _is_alive


func get_health_ratio() -> float:
    if not _initialized or max_hp <= 0:
        return 0.0

    return float(_current_hp) / float(max_hp)


func is_initialized() -> bool:
    return _initialized