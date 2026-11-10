class_name CardController
extends RefCounted

## Battle runtime for card selection, hand cycling, gauge cost and effect timers.
## Effect records are emitted to M12 integration; this class does not directly
## mutate FighterController, HealthComponent, GuardGauge or the damage resolver.

signal hand_changed(card_ids: Array, selected_index: int)
signal card_activated(card_id: StringName, effect_ids: Array, refreshed_effect_ids: Array)
signal effect_requested(card_id: StringName, effect: CardEffectData)
signal effect_applied(card_id: StringName, effect_id: StringName, refreshed: bool)
signal effect_expired(effect_id: StringName)
signal shuffle_started(duration_ticks: int)
signal shuffle_completed

enum Result {
    ACTIVATED = 0,
    NO_ACTION = 1,
    SELECTION_CHANGED = 2,
    NOT_CONFIGURED = 3,
    INVALID_TICK = 4,
    INVALID_INPUT_MASK = 5,
    SHUFFLING = 6,
    NO_CARD_SELECTED = 7,
    INSUFFICIENT_GAUGE = 8,
    INVALID_CARD = 9,
}

const CARD_PREV_MASK: int = 1 << 7
const CARD_NEXT_MASK: int = 1 << 8
const CARD_USE_MASK: int = 1 << 9
const INPUT_MASK: int = 0x7FF
const MAX_HAND_SIZE: int = 5
const DEFAULT_SHUFFLE_DELAY_TICKS: int = 180 # PROPOSED/PROVISIONAL: 3s at 60Hz.

var _full_deck: Array[CardData] = []
var _draw_pile: Array[CardData] = []
var _hand: Array[CardData] = []
var _card_gauge: CardGaugeComponent
var _hand_limit: int = 0
var _selected_index: int = 0
var _shuffle_remaining_ticks: int = 0
var _shuffle_delay_ticks: int = DEFAULT_SHUFFLE_DELAY_TICKS
var _last_tick: int = -1
var _configured: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _active_effects: Dictionary = {}


## hand_size must come from the selected CardDeckRules profile.
## 0 means auto: draw up to five, never more than the deck contains.
func configure(
        deck: Array[CardData],
        card_gauge: CardGaugeComponent,
        hand_size: int = 0,
        shuffle_seed: int = 1,
        shuffle_delay_ticks: int = DEFAULT_SHUFFLE_DELAY_TICKS
) -> bool:
    if _configured or deck.is_empty() or card_gauge == null:
        return false
    if not card_gauge.is_configured() or shuffle_delay_ticks < 0:
        return false
    if hand_size < 0 or hand_size > MAX_HAND_SIZE:
        return false

    var copied_deck: Array[CardData] = []
    for card in deck:
        if card == null or not card.is_valid():
            return false
        var copied_card := card.duplicate(true) as CardData
        if copied_card == null:
            return false
        copied_deck.append(copied_card)

    _hand_limit = mini(MAX_HAND_SIZE, mini(hand_size if hand_size > 0 else MAX_HAND_SIZE, copied_deck.size()))
    if _hand_limit <= 0:
        return false

    _full_deck = copied_deck
    _card_gauge = card_gauge
    _shuffle_delay_ticks = shuffle_delay_ticks
    _rng.seed = shuffle_seed
    _last_tick = -1
    _selected_index = 0
    _shuffle_remaining_ticks = 0
    _active_effects.clear()
    _configured = true
    _prepare_draw_pile()
    _draw_hand()
    _emit_hand_changed()
    return true


## Consumes logical pressed bits from one InputFrame snapshot.
## Bit 7 = CARD_PREV, bit 8 = CARD_NEXT, bit 9 = CARD_USE.
func process_input_snapshot(tick: int, pressed_mask: int) -> int:
    if not _configured:
        return Result.NOT_CONFIGURED
    if pressed_mask < 0 or (pressed_mask & ~INPUT_MASK) != 0:
        return Result.INVALID_INPUT_MASK
    if not _advance_to_tick(tick):
        return Result.INVALID_TICK

    var selection_changed: bool = false
    if (pressed_mask & CARD_PREV_MASK) != 0:
        selection_changed = _move_selection(-1) or selection_changed
    if (pressed_mask & CARD_NEXT_MASK) != 0:
        selection_changed = _move_selection(1) or selection_changed
    if selection_changed:
        _emit_hand_changed()

    if (pressed_mask & CARD_USE_MASK) != 0:
        return activate_selected()
    if selection_changed:
        return Result.SELECTION_CHANGED
    return Result.NO_ACTION


func advance_to_tick(tick: int) -> bool:
    if not _configured:
        return false
    return _advance_to_tick(tick)


func _advance_to_tick(tick: int) -> bool:
    if tick < 0 or (_last_tick >= 0 and tick <= _last_tick):
        return false

    var elapsed_ticks: int = 0
    if _last_tick >= 0:
        elapsed_ticks = tick - _last_tick
    if not _card_gauge.advance_to_tick(tick):
        push_error("CardController: CardGauge rejected a non-monotonic simulation tick")
        return false
    _last_tick = tick

    _advance_active_effects(elapsed_ticks)
    if _shuffle_remaining_ticks > 0 and elapsed_ticks > 0:
        _shuffle_remaining_ticks = maxi(0, _shuffle_remaining_ticks - elapsed_ticks)
        if _shuffle_remaining_ticks == 0:
            _begin_new_hand_cycle()
    return true


func activate_selected() -> int:
    if not _configured:
        return Result.NOT_CONFIGURED
    if _shuffle_remaining_ticks > 0:
        return Result.SHUFFLING
    if _hand.is_empty() or _selected_index < 0 or _selected_index >= _hand.size():
        return Result.NO_CARD_SELECTED

    var card: CardData = _hand[_selected_index]
    if card == null or not card.is_valid():
        return Result.INVALID_CARD
    if _card_gauge.get_current_gauge() < card.cost:
        return Result.INSUFFICIENT_GAUGE
    if not _card_gauge.try_spend(card.cost):
        return Result.INSUFFICIENT_GAUGE

    var emitted_effect_ids: Array[StringName] = []
    var refreshed_effect_ids: Array[StringName] = []
    for effect in card.effects:
        emitted_effect_ids.append(effect.effect_id)
        effect_requested.emit(card.card_id, effect.duplicate(true) as CardEffectData)
        if effect.duration_ticks <= 0:
            continue

        if effect.trigger_id == &"on_activate":
            var refreshed: bool = _store_timed_effect(card.card_id, effect)
            if refreshed:
                refreshed_effect_ids.append(effect.effect_id)

    _hand.remove_at(_selected_index)
    if _hand.is_empty():
        _selected_index = 0
        _shuffle_remaining_ticks = _shuffle_delay_ticks
        if _shuffle_remaining_ticks > 0:
            shuffle_started.emit(_shuffle_remaining_ticks)
            _emit_hand_changed()
        else:
            _begin_new_hand_cycle()
    else:
        _selected_index = _selected_index % _hand.size()
        _emit_hand_changed()

    card_activated.emit(card.card_id, emitted_effect_ids, refreshed_effect_ids)
    return Result.ACTIVATED


## M12 calls this only after its trigger resolver confirms a conditional effect.
## Timed effects refresh by effect_id and never stack their magnitude.
func apply_timed_effect(card_id: StringName, effect: CardEffectData) -> bool:
    if not _configured or effect == null or not effect.is_valid() or effect.duration_ticks <= 0:
        return false
    if not _deck_contains_card(card_id):
        return false
    _store_timed_effect(card_id, effect)
    return true


func _store_timed_effect(card_id: StringName, effect: CardEffectData) -> bool:
    var refreshed: bool = _active_effects.has(effect.effect_id)
    _active_effects[effect.effect_id] = {
        "card_id": card_id,
        "magnitude": effect.magnitude,
        "remaining_ticks": effect.duration_ticks,
        "trigger_id": effect.trigger_id,
        "parameters": effect.parameters.duplicate(true),
    }
    effect_applied.emit(card_id, effect.effect_id, refreshed)
    return refreshed


func _deck_contains_card(card_id: StringName) -> bool:
    for card in _full_deck:
        if card.card_id == card_id:
            return true
    return false


func _move_selection(direction: int) -> bool:
    if _hand.is_empty() or direction == 0:
        return false
    var previous_index: int = _selected_index
    _selected_index = posmod(_selected_index + direction, _hand.size())
    return previous_index != _selected_index


func _advance_active_effects(elapsed_ticks: int) -> void:
    if elapsed_ticks <= 0 or _active_effects.is_empty():
        return
    for effect_key in _active_effects.keys():
        var effect_id: StringName = StringName(str(effect_key))
        var effect_state: Dictionary = _active_effects[effect_id]
        var remaining: int = int(effect_state.get("remaining_ticks", 0)) - elapsed_ticks
        if remaining <= 0:
            _active_effects.erase(effect_id)
            effect_expired.emit(effect_id)
        else:
            effect_state["remaining_ticks"] = remaining
            _active_effects[effect_id] = effect_state


func _prepare_draw_pile() -> void:
    _draw_pile.clear()
    for card in _full_deck:
        _draw_pile.append(card)
    for index in range(_draw_pile.size() - 1, 0, -1):
        var swap_index: int = _rng.randi_range(0, index)
        var temporary: CardData = _draw_pile[index]
        _draw_pile[index] = _draw_pile[swap_index]
        _draw_pile[swap_index] = temporary


func _draw_hand() -> void:
    _hand.clear()
    while _hand.size() < _hand_limit and not _draw_pile.is_empty():
        _hand.append(_draw_pile.pop_back())
    _selected_index = 0


func _begin_new_hand_cycle() -> void:
    _prepare_draw_pile()
    _draw_hand()
    _shuffle_remaining_ticks = 0
    shuffle_completed.emit()
    _emit_hand_changed()


func _emit_hand_changed() -> void:
    hand_changed.emit(get_hand_card_ids(), _selected_index)


func get_deck_card_ids() -> Array[StringName]:
    var result: Array[StringName] = []
    for card in _full_deck:
        result.append(card.card_id)
    return result


func get_hand_card_ids() -> Array[StringName]:
    var result: Array[StringName] = []
    for card in _hand:
        result.append(card.card_id)
    return result


func get_hand_count() -> int:
    return _hand.size()


func get_hand_limit() -> int:
    return _hand_limit


func get_selected_index() -> int:
    return _selected_index


func get_selected_card() -> CardData:
    if _hand.is_empty() or _selected_index < 0 or _selected_index >= _hand.size():
        return null
    return _hand[_selected_index].duplicate(true) as CardData


func is_shuffling() -> bool:
    return _shuffle_remaining_ticks > 0


func get_shuffle_remaining_ticks() -> int:
    return _shuffle_remaining_ticks


func has_active_effect(effect_id: StringName) -> bool:
    return _active_effects.has(effect_id)


func get_effect_magnitude(effect_id: StringName) -> float:
    if not _active_effects.has(effect_id):
        return 0.0
    var state: Dictionary = _active_effects[effect_id]
    return float(state.get("magnitude", 0.0))


func get_active_effect_remaining_ticks(effect_id: StringName) -> int:
    if not _active_effects.has(effect_id):
        return 0
    var state: Dictionary = _active_effects[effect_id]
    return int(state.get("remaining_ticks", 0))


func get_active_effect_ids() -> Array[StringName]:
    var result: Array[StringName] = []
    for effect_id in _active_effects.keys():
        result.append(StringName(str(effect_id)))
    return result


## Compatibility-style accessors for the three MVP effects; M12 reads these
## when wiring the modifiers into the real damage/knockback calculation.
func get_attack_damage_multiplier() -> float:
    return 1.0 + get_effect_magnitude(&"attack_power_bonus")


func get_incoming_damage_multiplier() -> float:
    return clampf(1.0 - get_effect_magnitude(&"incoming_damage_reduction"), 0.0, 1.0)


func get_heavy_knockback_multiplier() -> float:
    return 1.0 + get_effect_magnitude(&"heavy_knockback_bonus")


func get_card_gauge() -> CardGaugeComponent:
    return _card_gauge


func is_configured() -> bool:
    return _configured
