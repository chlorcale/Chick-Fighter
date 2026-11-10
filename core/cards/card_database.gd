class_name CardDatabase
extends RefCounted

## Explicit resource registry. New .tres cards are added once to DEFAULT_CARD_PATHS
## or registered by the owner at startup; CardController does not need changes.

const DEFAULT_CARD_PATHS: Array[String] = [
    "res://core/cards/data/cuong_no.tres",
    "res://core/cards/data/mai_rua.tres",
    "res://core/cards/data/gio_song.tres",
    "res://core/cards/data/phong_thu.tres",
    "res://core/cards/data/mau_chien.tres",
    "res://core/cards/data/cung_dau.tres",
    "res://core/cards/data/chop_thoi_co.tres",
    "res://core/cards/data/nuoc_lon.tres",
    "res://core/cards/data/mua_chieu.tres",
    "res://core/cards/data/gay_sang.tres",
]

var _cards: Dictionary = {}


static func create_default_database() -> CardDatabase:
    var database := CardDatabase.new()
    for resource_path in DEFAULT_CARD_PATHS:
        var card := load(resource_path) as CardData
        if card == null or not database.register_card(card):
            push_error("CardDatabase: failed to load/register card resource: %s" % resource_path)
            return null
    return database


func register_card(card: CardData, replace_existing: bool = false) -> bool:
    if card == null or not card.is_valid():
        return false
    if _cards.has(card.card_id) and not replace_existing:
        return false
    _cards[card.card_id] = card.duplicate(true) as CardData
    return true


func has_card(card_id: StringName) -> bool:
    return _cards.has(card_id)


## Returns a deep copy so callers cannot mutate the canonical database resource.
func get_card(card_id: StringName) -> CardData:
    if not _cards.has(card_id):
        return null
    return (_cards[card_id] as CardData).duplicate(true) as CardData


func get_card_ids() -> Array[StringName]:
    var result: Array[StringName] = []
    for card_id in _cards.keys():
        result.append(StringName(str(card_id)))
    return result


func get_card_ids_for_group(group_id: StringName) -> Array[StringName]:
    var result: Array[StringName] = []
    for card_id in _cards.keys():
        var card: CardData = _cards[card_id] as CardData
        if card.content_group == group_id:
            result.append(card.card_id)
    return result


func get_card_count() -> int:
    return _cards.size()


func get_mvp_deck() -> Array[CardData]:
    var result: Array[CardData] = []
    for card_id in get_card_ids_for_group(&"mvp"):
        var card := get_card(card_id)
        if card != null:
            result.append(card)
    return result
