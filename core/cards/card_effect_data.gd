class_name CardEffectData
extends Resource

## Declarative effect record. M11 stores and emits these records; M12 combat
## integration decides how each effect_id is applied to the live battle.

@export var effect_id: StringName = &""
@export var magnitude: float = 0.0
@export_range(0, 3600, 1) var duration_ticks: int = 0
@export var trigger_id: StringName = &"on_activate"
@export var parameters: Dictionary = {}


func is_valid() -> bool:
    if effect_id == &"" or trigger_id == &"":
        return false
    if duration_ticks < 0 or duration_ticks > 3600:
        return false
    if not is_finite(magnitude):
        return false
    return true
