class_name CardDeckBuilder
extends RefCounted

## Builds a battle deck from IDs selected by the player/preparation UI.

enum Result {
    OK = 0,
    NOT_CONFIGURED = 1,
    INVALID_DECK_SIZE = 2,
    EMPTY_CARD_ID = 3,
    UNKNOWN_CARD = 4,
    CARD_LOCKED = 5,
    DUPLICATE_POLICY_UNSET = 6,
    DUPLICATE_CARD = 7,
}

var _database: CardDatabase
var _collection: CardCollection
var _rules: CardDeckRules
var _configured: bool = false
var _last_result: int = Result.NOT_CONFIGURED


func configure(
        database: CardDatabase,
        collection: CardCollection,
        rules: CardDeckRules
) -> bool:
    if _configured or database == null or collection == null or rules == null:
        return false
    if not collection.uses_database(database) or not rules.is_valid():
        return false
    _database = database
    _collection = collection
    _rules = rules.duplicate(true) as CardDeckRules
    _configured = true
    _last_result = Result.OK
    return true


func validate_deck(card_ids: Array[StringName]) -> int:
    if not _configured:
        _last_result = Result.NOT_CONFIGURED
        return _last_result
    if (card_ids.size() < _rules.minimum_deck_size
            or card_ids.size() > _rules.maximum_deck_size):
        _last_result = Result.INVALID_DECK_SIZE
        return _last_result

    var seen: Dictionary = {}
    for card_id in card_ids:
        if card_id == &"":
            _last_result = Result.EMPTY_CARD_ID
            return _last_result
        if not _database.has_card(card_id):
            _last_result = Result.UNKNOWN_CARD
            return _last_result
        if not _collection.is_unlocked(card_id):
            _last_result = Result.CARD_LOCKED
            return _last_result
        if seen.has(card_id):
            if _rules.duplicate_policy == CardDeckRules.DuplicatePolicy.OWNER_DECISION_REQUIRED:
                _last_result = Result.DUPLICATE_POLICY_UNSET
                return _last_result
            if _rules.duplicate_policy == CardDeckRules.DuplicatePolicy.DISALLOW:
                _last_result = Result.DUPLICATE_CARD
                return _last_result
        seen[card_id] = true

    _last_result = Result.OK
    return _last_result


## Returns a deep-copied Array[CardData]. An empty array means validation failed.
func build_deck(card_ids: Array[StringName]) -> Array[CardData]:
    var result: Array[CardData] = []
    if validate_deck(card_ids) != Result.OK:
        return result
    for card_id in card_ids:
        var card := _database.get_card(card_id)
        if card == null:
            result.clear()
            _last_result = Result.UNKNOWN_CARD
            return result
        result.append(card)
    return result


func get_hand_size() -> int:
    if not _configured:
        return 0
    return _rules.hand_size


func get_last_result() -> int:
    return _last_result


func is_configured() -> bool:
    return _configured
