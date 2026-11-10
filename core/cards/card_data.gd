class_name CardData
extends Resource

## Static card definition. Mutable battle state is owned by CardController.

@export var card_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(0, 3, 1) var cost: int = 0
@export var effects: Array[CardEffectData] = []
@export var content_group: StringName = &"mvp"
@export var is_proposed: bool = false


func is_valid() -> bool:
    if card_id == &"" or display_name.strip_edges().is_empty():
        return false
    if cost < 0 or cost > 3 or effects.is_empty():
        return false
    if content_group == &"":
        return false

    var seen_effect_ids: Dictionary = {}
    for effect in effects:
        if effect == null or not effect.is_valid():
            return false
        if seen_effect_ids.has(effect.effect_id):
            return false
        seen_effect_ids[effect.effect_id] = true
    return true


func get_effect_ids() -> Array[StringName]:
    var result: Array[StringName] = []
    for effect in effects:
        if effect != null:
            result.append(effect.effect_id)
    return result
