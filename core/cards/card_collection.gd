class_name CardCollection
extends RefCounted

## Tracks which cards are owned/unlocked and where they came from.
## Persistence is intentionally an import/export boundary; profile saving is
## owned by the later player-profile/save milestone.

const SOURCE_DEFAULT: StringName = &"default"
const SOURCE_TOURNAMENT: StringName = &"tournament"
const SOURCE_NPC: StringName = &"npc"
const SOURCE_ACHIEVEMENT: StringName = &"achievement"
const SOURCE_DEBUG: StringName = &"debug"

signal card_unlocked(card_id: StringName, source_type: StringName, source_id: StringName)

var _database: CardDatabase
var _unlocked: Dictionary = {}
var _configured: bool = false


func configure(database: CardDatabase) -> bool:
    if _configured or database == null or database.get_card_count() <= 0:
        return false
    _database = database
    _unlocked.clear()
    _configured = true
    return true


## Unlocks a card and records the progression source for future save/UI use.
func unlock_card(
        card_id: StringName,
        source_type: StringName,
        source_id: StringName = &""
) -> bool:
    if not _configured or not _database.has_card(card_id):
        return false
    if not _is_supported_source(source_type) or _unlocked.has(card_id):
        return false

    _unlocked[card_id] = {
        "source_type": source_type,
        "source_id": source_id,
    }
    card_unlocked.emit(card_id, source_type, source_id)
    return true


func unlock_mvp_defaults() -> int:
    if not _configured:
        return 0
    var unlocked_count: int = 0
    for card_id in _database.get_card_ids_for_group(&"mvp"):
        if unlock_card(card_id, SOURCE_DEFAULT, &"mvp_starter_set"):
            unlocked_count += 1
    return unlocked_count


func is_unlocked(card_id: StringName) -> bool:
    return _configured and _unlocked.has(card_id)


func get_unlocked_card_ids() -> Array[StringName]:
    var result: Array[StringName] = []
    for card_id in _unlocked.keys():
        result.append(StringName(str(card_id)))
    return result


func get_unlock_record(card_id: StringName) -> Dictionary:
    if not is_unlocked(card_id):
        return {}
    var record: Dictionary = _unlocked[card_id]
    return record.duplicate(true)


func export_save_data() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for card_id in _unlocked.keys():
        var saved_record: Dictionary = _unlocked[card_id]
        var record: Dictionary = saved_record.duplicate(true)
        record["card_id"] = card_id
        result.append(record)
    return result


## Restores only known cards and supported source records. Invalid entries are skipped.
func import_save_data(records: Array) -> int:
    if not _configured:
        return 0
    var imported_count: int = 0
    for raw_record in records:
        if not (raw_record is Dictionary):
            continue
        var record: Dictionary = raw_record
        var card_id: StringName = StringName(str(record.get("card_id", "")))
        var source_type: StringName = StringName(str(record.get("source_type", "")))
        var source_id: StringName = StringName(str(record.get("source_id", "")))
        if unlock_card(card_id, source_type, source_id):
            imported_count += 1
    return imported_count


func is_configured() -> bool:
    return _configured


func uses_database(database: CardDatabase) -> bool:
    return _configured and database != null and _database == database


func _is_supported_source(source_type: StringName) -> bool:
    return (source_type == SOURCE_DEFAULT
        or source_type == SOURCE_TOURNAMENT
        or source_type == SOURCE_NPC
        or source_type == SOURCE_ACHIEVEMENT
        or source_type == SOURCE_DEBUG)
