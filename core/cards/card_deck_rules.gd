class_name CardDeckRules
extends Resource

## GDD profiles: MVP = exactly 3 cards / hand 3; Phase 1 = 8-10 cards / hand 5.
## Duplicate-copy policy is intentionally unresolved by the GDD and must be
## selected by the owner if a deck contains duplicate card IDs.

enum DuplicatePolicy {
    OWNER_DECISION_REQUIRED = 0,
    DISALLOW = 1,
    ALLOW = 2,
}

@export_range(1, 100, 1) var minimum_deck_size: int = 3
@export_range(1, 100, 1) var maximum_deck_size: int = 3
@export_range(1, 5, 1) var hand_size: int = 3
@export var duplicate_policy: int = DuplicatePolicy.OWNER_DECISION_REQUIRED


static func create_mvp_rules() -> CardDeckRules:
    var rules := CardDeckRules.new()
    rules.minimum_deck_size = 3
    rules.maximum_deck_size = 3
    rules.hand_size = 3
    rules.duplicate_policy = DuplicatePolicy.OWNER_DECISION_REQUIRED
    return rules


static func create_phase1_rules() -> CardDeckRules:
    var rules := CardDeckRules.new()
    rules.minimum_deck_size = 8
    rules.maximum_deck_size = 10
    rules.hand_size = 5
    rules.duplicate_policy = DuplicatePolicy.OWNER_DECISION_REQUIRED
    return rules


func is_valid() -> bool:
    if minimum_deck_size <= 0 or maximum_deck_size < minimum_deck_size:
        return false
    if hand_size <= 0 or hand_size > 5 or hand_size > maximum_deck_size:
        return false
    return (duplicate_policy >= DuplicatePolicy.OWNER_DECISION_REQUIRED
        and duplicate_policy <= DuplicatePolicy.ALLOW)
