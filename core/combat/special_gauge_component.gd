class_name SpecialGaugeComponent
extends Node

## M10: accounting core for the five-bar Special Gauge.
##
## Design authority:
## - Maximum bars: 5 (CONFIRMED).
## - Points per bar: 50 (PROVISIONAL; configurable at setup).
## - Starting points: must be supplied explicitly by the selected game mode.
## - Gauge gain amounts and gain sources are intentionally not defined here.
## - A reservation is not spent until spend_reservation() is called.
## - Releasing a reservation requires explicit caller permission.
##
## This component does not decide when attacks/cards gain or spend gauge.

signal gauge_changed(
    current_points: int,
    maximum_points: int,
    full_bars: int,
    available_bars: int,
    reserved_bars: int,
    spent_bars_total: int
)

const MAX_BARS: int = 5
const DEFAULT_POINTS_PER_BAR: int = 50 # PROVISIONAL conversion, not final balance.

var _configured: bool = false
var _points_per_bar: int = DEFAULT_POINTS_PER_BAR
var _maximum_points: int = MAX_BARS * DEFAULT_POINTS_PER_BAR
var _current_points: int = 0
var _reserved_bars: int = 0
var _spent_bars_total: int = 0
var _reservations: Dictionary = {}


## Configure once for the selected game mode.
## starting_points is required: there is deliberately no universal starting value.
## points_per_bar defaults to the provisional 50-point conversion and is configurable.
func configure(starting_points: int, points_per_bar: int = DEFAULT_POINTS_PER_BAR) -> bool:
    if _configured:
        return false
    if points_per_bar <= 0:
        return false

    var maximum_points: int = MAX_BARS * points_per_bar
    if starting_points < 0 or starting_points > maximum_points:
        return false

    _points_per_bar = points_per_bar
    _maximum_points = maximum_points
    _current_points = starting_points
    _reserved_bars = 0
    _spent_bars_total = 0
    _reservations.clear()
    _configured = true
    return true


func is_configured() -> bool:
    return _configured


## Adds an explicit amount supplied by an external, approved gameplay rule.
## This method intentionally contains no Light/Heavy/Block/Hit gain values.
## Returns the number of points actually added after clamping.
func add_points(amount: int) -> int:
    if not _configured or amount <= 0:
        return 0

    var room: int = _maximum_points - _current_points
    var added: int = mini(amount, room)
    if added <= 0:
        return 0

    _current_points += added
    _emit_gauge_changed()
    return added


## Spend currently available full bars immediately.
func spend_bars(bars: int) -> bool:
    if not can_spend_bars(bars):
        return false

    _current_points -= bars * _points_per_bar
    _spent_bars_total += bars
    _emit_gauge_changed()
    return true


## Reserve full bars without deducting points yet.
## reservation_id must be unique until the reservation is spent or released.
func reserve_bars(reservation_id: StringName, bars: int) -> bool:
    if not _configured or reservation_id == &"" or bars <= 0:
        return false
    if _reservations.has(reservation_id):
        return false
    if get_available_bars() < bars:
        return false

    _reservations[reservation_id] = bars
    _reserved_bars += bars
    _emit_gauge_changed()
    return true


## Commit a reservation as spent. No second charge is made at this point:
## the reserved points are deducted exactly once here.
func spend_reservation(reservation_id: StringName) -> bool:
    if not _configured or not _reservations.has(reservation_id):
        return false

    var bars: int = int(_reservations[reservation_id])
    var points: int = bars * _points_per_bar
    if bars <= 0 or _current_points < points:
        return false

    _reservations.erase(reservation_id)
    _reserved_bars -= bars
    _current_points -= points
    _spent_bars_total += bars
    _emit_gauge_changed()
    return true


## Release a reservation only when the calling gameplay rule explicitly permits it.
## This does not add points or refund a previously spent reservation.
func release_reservation(
    reservation_id: StringName,
    release_permitted: bool = false
) -> bool:
    if not _configured or not release_permitted:
        return false
    if not _reservations.has(reservation_id):
        return false

    var bars: int = int(_reservations[reservation_id])
    _reservations.erase(reservation_id)
    _reserved_bars -= bars
    _emit_gauge_changed()
    return true


func can_spend_bars(bars: int) -> bool:
    return _configured and bars > 0 and get_available_bars() >= bars


func has_reservation(reservation_id: StringName) -> bool:
    return _configured and _reservations.has(reservation_id)


func get_reservation_bars(reservation_id: StringName) -> int:
    if not has_reservation(reservation_id):
        return 0
    return int(_reservations[reservation_id])


func get_current_points() -> int:
    return _current_points


func get_maximum_points() -> int:
    return _maximum_points


func get_maximum_bars() -> int:
    return MAX_BARS


func get_points_per_bar() -> int:
    return _points_per_bar


## Total full bars represented by current_points, including reserved bars.
func get_full_bars() -> int:
    if not _configured or _points_per_bar <= 0:
        return 0
    return floori(float(_current_points) / float(_points_per_bar))


## Points in the current partial bar. Reserved bars are whole bars, so this
## remainder is also the unreserved partial progress.
func get_partial_bar_points() -> int:
    if not _configured or _points_per_bar <= 0:
        return 0
    return _current_points % _points_per_bar


func get_partial_bar_ratio() -> float:
    if not _configured or _points_per_bar <= 0:
        return 0.0
    return float(get_partial_bar_points()) / float(_points_per_bar)


## Unreserved points, including partial-bar progress.
func get_available_points() -> int:
    if not _configured:
        return 0
    return maxi(0, _current_points - _reserved_bars * _points_per_bar)


func get_available_bars() -> int:
    if not _configured:
        return 0
    return maxi(0, get_full_bars() - _reserved_bars)


func get_reserved_bars() -> int:
    return _reserved_bars


## Cumulative number of bars actually spent since configure().
func get_spent_bars_total() -> int:
    return _spent_bars_total


func _emit_gauge_changed() -> void:
    gauge_changed.emit(
        _current_points,
        _maximum_points,
        get_full_bars(),
        get_available_bars(),
        _reserved_bars,
        _spent_bars_total
    )
