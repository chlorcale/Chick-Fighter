class_name CardGaugeComponent
extends RefCounted

## Card Gauge is separate from M10 SpecialGauge.
## GDD baseline: maximum 5, starts at 5, regenerates 1 point every 240 ticks.

signal gauge_changed(current_gauge: int, maximum_gauge: int, delta: int)

const MAX_GAUGE: int = 5
const REGEN_INTERVAL_TICKS: int = 240

var _current_gauge: int = 0
var _regen_progress_ticks: int = 0
var _last_tick: int = -1
var _configured: bool = false


func configure(starting_gauge: int = MAX_GAUGE) -> bool:
    if _configured or starting_gauge < 0 or starting_gauge > MAX_GAUGE:
        return false
    _current_gauge = starting_gauge
    _regen_progress_ticks = 0
    _last_tick = -1
    _configured = true
    return true


func advance_to_tick(tick: int) -> bool:
    if not _configured or tick < 0:
        return false
    if _last_tick >= 0 and tick <= _last_tick:
        return false

    var elapsed_ticks: int = 0
    if _last_tick >= 0:
        elapsed_ticks = tick - _last_tick
    _last_tick = tick

    if _current_gauge >= MAX_GAUGE:
        _regen_progress_ticks = 0
        return true

    _regen_progress_ticks += elapsed_ticks
    var points_to_add: int = int(_regen_progress_ticks / REGEN_INTERVAL_TICKS)
    if points_to_add <= 0:
        return true

    var previous_gauge: int = _current_gauge
    _current_gauge = mini(MAX_GAUGE, _current_gauge + points_to_add)
    if _current_gauge >= MAX_GAUGE:
        _regen_progress_ticks = 0
    else:
        _regen_progress_ticks %= REGEN_INTERVAL_TICKS

    if _current_gauge != previous_gauge:
        gauge_changed.emit(_current_gauge, MAX_GAUGE, _current_gauge - previous_gauge)
    return true


func try_spend(amount: int) -> bool:
    if not _configured or amount < 0 or amount > _current_gauge:
        return false
    if amount == 0:
        return true
    _current_gauge -= amount
    gauge_changed.emit(_current_gauge, MAX_GAUGE, -amount)
    return true


## Restores Card Gauge (used by delayed/triggered card effects such as Gáy Sáng).
## Returns the number of points actually restored after clamping to the maximum.
func add_gauge(amount: int) -> int:
    if not _configured or amount <= 0:
        return 0
    var previous_gauge: int = _current_gauge
    _current_gauge = mini(MAX_GAUGE, _current_gauge + amount)
    if _current_gauge >= MAX_GAUGE:
        _regen_progress_ticks = 0
    var added_amount: int = _current_gauge - previous_gauge
    if added_amount > 0:
        gauge_changed.emit(_current_gauge, MAX_GAUGE, added_amount)
    return added_amount


func get_current_gauge() -> int:
    return _current_gauge


func get_max_gauge() -> int:
    return MAX_GAUGE


func get_regen_progress_ticks() -> int:
    return _regen_progress_ticks


func is_configured() -> bool:
    return _configured
