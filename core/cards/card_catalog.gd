class_name CardCatalog
extends RefCounted

## Compatibility facade for the three GDD MVP cards.
## Prefer CardDatabase for new code and for Phase 1 cards.

static func get_mvp_deck() -> Array[CardData]:
    var database := CardDatabase.create_default_database()
    if database == null:
        return []
    return database.get_mvp_deck()


static func get_card(card_id: StringName) -> CardData:
    var database := CardDatabase.create_default_database()
    if database == null:
        return null
    return database.get_card(card_id)
