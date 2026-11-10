extends RefCounted

const CardDataScript = preload("res://core/cards/card_data.gd")
const CardEffectDataScript = preload("res://core/cards/card_effect_data.gd")
const CardDatabaseScript = preload("res://core/cards/card_database.gd")
const CardCatalogScript = preload("res://core/cards/card_catalog.gd")
const CardCollectionScript = preload("res://core/cards/card_collection.gd")
const CardDeckRulesScript = preload("res://core/cards/card_deck_rules.gd")
const CardDeckBuilderScript = preload("res://core/cards/card_deck_builder.gd")
const CardGaugeScript = preload("res://core/cards/card_gauge_component.gd")
const CardControllerScript = preload("res://core/cards/card_controller.gd")

const CARD_PREV: int = 1 << 7
const CARD_NEXT: int = 1 << 8
const CARD_USE: int = 1 << 9

var _passed: int = 0
var _failed: int = 0


func run() -> Dictionary:
    _passed = 0
    _failed = 0
    _test_database_and_catalog()
    _test_collection_and_progression_sources()
    _test_deck_builder_profiles()
    _test_duplicate_policy()
    _test_custom_card_registration()
    _test_gauge()
    _test_hand_limit_and_cycle()
    _test_effect_refresh_and_expiry()
    _test_conditional_effect_activation()
    _test_input_validation()
    return {"passed": _passed, "failed": _failed}


func _test_database_and_catalog() -> void:
    var database = CardDatabaseScript.create_default_database()
    _check(database != null, "Default database loads without null resources")
    if database == null:
        return

    _check(database.get_card_count() == 10, "Database registers 3 MVP + 7 Phase 1 cards")
    _check(database.get_card_ids_for_group(&"mvp").size() == 3, "MVP group contains exactly three cards")
    _check(database.get_card_ids_for_group(&"phase1").size() == 7, "Phase 1 group contains seven card definitions")

    for card_id in database.get_card_ids():
        var card = database.get_card(card_id)
        _check(card != null and card.is_valid(), "Registered card resource is valid: %s" % str(card_id))

    var mvp_deck = database.get_mvp_deck()
    _check(mvp_deck.size() == 3, "Default MVP deck returns exactly three cards")
    _check(CardCatalogScript.get_mvp_deck().size() == 3, "Legacy CardCatalog facade remains compatible with MVP callers")
    _check(CardCatalogScript.get_card(&"cuong_no") != null, "Legacy CardCatalog can still retrieve MVP cards")
    _check(CardDatabaseScript.create_default_database().get_card(&"mau_chien") != null, "Phase 1 resource is retrievable by ID")


func _test_collection_and_progression_sources() -> void:
    var database = CardDatabaseScript.create_default_database()
    var collection = CardCollectionScript.new()
    _check(collection.configure(database), "Collection configures against the card database")
    _check(collection.unlock_mvp_defaults() == 3, "Three MVP cards are unlocked by default")
    _check(collection.is_unlocked(&"cuong_no"), "MVP Cuồng Nộ is unlocked")
    _check(not collection.is_unlocked(&"phong_thu"), "Phase 1 card is locked by default")

    _check(collection.unlock_card(&"phong_thu", &"tournament", &"ao_lang_round_3"), "Tournament can unlock a card")
    _check(collection.unlock_card(&"mau_chien", &"npc", &"chu_tu"), "NPC can unlock a card")
    _check(collection.unlock_card(&"cung_dau", &"achievement", &"perfect_guard"), "Achievement can unlock a card")
    _check(not collection.unlock_card(&"phong_thu", &"npc", &"duplicate_unlock"), "Already unlocked card is not duplicated")
    _check(not collection.unlock_card(&"nuoc_lon", &"shop", &"invalid_source"), "Unsupported progression source is rejected")

    var saved_records = collection.export_save_data()
    var restored = CardCollectionScript.new()
    restored.configure(database)
    _check(restored.import_save_data(saved_records) == saved_records.size(), "Collection unlocks round-trip through save data")
    var tournament_record = restored.get_unlock_record(&"phong_thu")
    _check(StringName(str(tournament_record.get("source_type", ""))) == &"tournament", "Unlock source metadata survives export/import")


func _test_deck_builder_profiles() -> void:
    var database = CardDatabaseScript.create_default_database()
    var collection = CardCollectionScript.new()
    collection.configure(database)
    collection.unlock_mvp_defaults()

    var mvp_rules = CardDeckRulesScript.create_mvp_rules()
    var mvp_builder = CardDeckBuilderScript.new()
    _check(mvp_builder.configure(database, collection, mvp_rules), "MVP deck builder configures")
    var mismatched_builder = CardDeckBuilderScript.new()
    var foreign_database = CardDatabaseScript.create_default_database()
    _check(not mismatched_builder.configure(foreign_database, collection, mvp_rules), "Deck builder rejects a collection tied to a different database instance")
    var mvp_ids: Array[StringName] = [&"cuong_no", &"mai_rua", &"gio_song"]
    _check(mvp_builder.validate_deck(mvp_ids) == CardDeckBuilderScript.Result.OK, "MVP deck with three starter cards validates")
    _check(mvp_builder.build_deck(mvp_ids).size() == 3, "MVP builder returns three CardData resources")
    var short_ids: Array[StringName] = [&"cuong_no", &"mai_rua"]
    _check(mvp_builder.validate_deck(short_ids) == CardDeckBuilderScript.Result.INVALID_DECK_SIZE, "MVP deck rejects fewer than three cards")
    var locked_ids: Array[StringName] = [&"cuong_no", &"mai_rua", &"phong_thu"]
    _check(mvp_builder.validate_deck(locked_ids) == CardDeckBuilderScript.Result.CARD_LOCKED, "Deck builder rejects a locked card")

    var phase_ids_to_unlock: Array[StringName] = [
        &"phong_thu", &"mau_chien", &"cung_dau", &"chop_thoi_co", &"nuoc_lon",
        &"mua_chieu", &"gay_sang",
    ]
    for card_id in phase_ids_to_unlock:
        _check(collection.unlock_card(card_id, &"achievement", &"test_phase_unlock"), "Phase 1 card can be unlocked: %s" % str(card_id))

    var phase_rules = CardDeckRulesScript.create_phase1_rules()
    var phase_builder = CardDeckBuilderScript.new()
    _check(phase_builder.configure(database, collection, phase_rules), "Phase 1 deck builder configures")
    var phase8: Array[StringName] = [
        &"cuong_no", &"mai_rua", &"gio_song", &"phong_thu", &"mau_chien",
        &"cung_dau", &"chop_thoi_co", &"nuoc_lon",
    ]
    _check(phase_builder.validate_deck(phase8) == CardDeckBuilderScript.Result.OK, "Phase 1 deck of eight cards validates")
    _check(phase_builder.build_deck(phase8).size() == 8, "Phase 1 builder builds an eight-card deck")
    _check(phase_builder.get_hand_size() == 5, "Phase 1 rules set opening hand to five")

    var all10: Array[StringName] = [
        &"cuong_no", &"mai_rua", &"gio_song", &"phong_thu", &"mau_chien",
        &"cung_dau", &"chop_thoi_co", &"nuoc_lon", &"mua_chieu", &"gay_sang",
    ]
    _check(phase_builder.validate_deck(all10) == CardDeckBuilderScript.Result.OK, "Phase 1 deck of ten cards validates")
    var too_many: Array[StringName] = []
    too_many.assign(all10)
    too_many.append(&"cuong_no")
    _check(phase_builder.validate_deck(too_many) == CardDeckBuilderScript.Result.INVALID_DECK_SIZE, "Phase 1 deck rejects more than ten cards")


func _test_duplicate_policy() -> void:
    var database = CardDatabaseScript.create_default_database()
    var collection = CardCollectionScript.new()
    collection.configure(database)
    collection.unlock_mvp_defaults()
    var duplicate_ids: Array[StringName] = [&"cuong_no", &"mai_rua", &"cuong_no"]

    var required_rules = CardDeckRulesScript.new()
    required_rules.minimum_deck_size = 3
    required_rules.maximum_deck_size = 3
    required_rules.hand_size = 3
    required_rules.duplicate_policy = CardDeckRulesScript.DuplicatePolicy.OWNER_DECISION_REQUIRED
    var required_builder = CardDeckBuilderScript.new()
    required_builder.configure(database, collection, required_rules)
    _check(required_builder.validate_deck(duplicate_ids) == CardDeckBuilderScript.Result.DUPLICATE_POLICY_UNSET, "Duplicate deck requires an explicit owner rule")

    var disallow_rules = required_rules.duplicate(true)
    disallow_rules.duplicate_policy = CardDeckRulesScript.DuplicatePolicy.DISALLOW
    var disallow_builder = CardDeckBuilderScript.new()
    disallow_builder.configure(database, collection, disallow_rules)
    _check(disallow_builder.validate_deck(duplicate_ids) == CardDeckBuilderScript.Result.DUPLICATE_CARD, "No-duplicate policy rejects repeated cards")

    var allow_rules = required_rules.duplicate(true)
    allow_rules.duplicate_policy = CardDeckRulesScript.DuplicatePolicy.ALLOW
    var allow_builder = CardDeckBuilderScript.new()
    allow_builder.configure(database, collection, allow_rules)
    _check(allow_builder.validate_deck(duplicate_ids) == CardDeckBuilderScript.Result.OK, "Allow-duplicate policy accepts repeated cards")


func _test_custom_card_registration() -> void:
    var database = CardDatabaseScript.create_default_database()
    var custom_card = database.get_card(&"cuong_no")
    custom_card.card_id = &"sample_owner_card"
    custom_card.display_name = "Thẻ thử nghiệm"
    custom_card.content_group = &"phase1"
    _check(database.register_card(custom_card), "A new CardData Resource can be registered without changing CardController")
    _check(database.has_card(&"sample_owner_card"), "Registered custom card is discoverable by ID")

    var collection = CardCollectionScript.new()
    collection.configure(database)
    collection.unlock_mvp_defaults()
    _check(collection.unlock_card(&"sample_owner_card", &"npc", &"custom_npc_reward"), "Custom registered card can be unlocked")


func _test_gauge() -> void:
    var gauge = CardGaugeScript.new()
    _check(gauge.configure(), "Card Gauge configures")
    _check(gauge.get_current_gauge() == 5, "Card Gauge starts at five")
    _check(gauge.try_spend(2), "Card Gauge spends two points")
    _check(gauge.get_current_gauge() == 3, "Card Gauge now contains three points")
    _check(gauge.advance_to_tick(0), "Card Gauge accepts first simulation tick")
    _check(gauge.advance_to_tick(239), "Card Gauge advances 239 ticks")
    _check(gauge.get_current_gauge() == 3, "No regeneration before the 240-tick threshold")
    _check(gauge.advance_to_tick(240), "Card Gauge advances to the 240-tick threshold")
    _check(gauge.get_current_gauge() == 4, "Card Gauge regenerates one point every 240 ticks")
    _check(not gauge.try_spend(5), "Card Gauge rejects spending beyond available points")
    _check(gauge.add_gauge(10) == 1, "Card effects can restore gauge but cannot exceed the maximum")
    _check(gauge.get_current_gauge() == 5, "Restored Card Gauge is clamped to five")
    _check(gauge.add_gauge(1) == 0, "Restoring a full Card Gauge adds no extra points")


func _test_hand_limit_and_cycle() -> void:
    var base_database = CardDatabaseScript.create_default_database()
    var source_card = base_database.get_card(&"cuong_no")
    var runtime_deck: Array[CardData] = []
    for index in range(8):
        var card = source_card.duplicate(true)
        card.card_id = StringName("cycle_card_%d" % index)
        card.display_name = "Cycle Card %d" % index
        card.cost = 0
        runtime_deck.append(card)

    var gauge = CardGaugeScript.new()
    gauge.configure(5)
    var controller = CardControllerScript.new()
    var hand_snapshots: Array = []
    controller.hand_changed.connect(func(card_ids: Array, _selected_index: int) -> void:
        hand_snapshots.append(card_ids.duplicate())
    )
    _check(controller.configure(runtime_deck, gauge, 5, 12345, 180), "CardController configures an eight-card deck with hand size five")
    _check(controller.get_hand_count() == 5, "Only five of eight deck cards are drawn into the opening hand")
    _check(controller.get_hand_limit() == 5, "Controller records a five-card maximum hand")
    _check(controller.get_hand_card_ids().size() == 5, "Hand snapshot contains exactly five card IDs")

    var opening_ids: Array[StringName] = controller.get_hand_card_ids()
    var unique_ids: Dictionary = {}
    for card_id in opening_ids:
        unique_ids[card_id] = true
    _check(unique_ids.size() == 5, "A hand contains five distinct entries from a unique-card deck")

    for tick in range(5):
        _check(int(controller.process_input_snapshot(tick, CARD_USE)) == CardControllerScript.Result.ACTIVATED, "A free card activates from the current hand (tick %d)" % tick)
    _check(controller.get_hand_count() == 0, "Using all five hand cards empties the hand")
    _check(not hand_snapshots.is_empty() and hand_snapshots[hand_snapshots.size() - 1].is_empty(), "HUD listeners receive an immediate empty-hand snapshot")
    _check(controller.is_shuffling(), "An empty hand enters the configured shuffle delay")
    _check(int(controller.process_input_snapshot(5, CARD_USE)) == CardControllerScript.Result.SHUFFLING, "Cards cannot be activated during shuffle delay")
    _check(controller.advance_to_tick(185), "Controller advances to the end of the 180-tick delay")
    _check(controller.get_hand_count() == 5, "New hand draws five cards from the full eight-card deck")
    _check(controller.get_hand_count() <= 5, "Hand limit remains five after deck cycle")


func _test_effect_refresh_and_expiry() -> void:
    var database = CardDatabaseScript.create_default_database()
    var source_card = database.get_card(&"cuong_no")
    var runtime_deck: Array[CardData] = []
    for index in range(3):
        var card = source_card.duplicate(true)
        card.card_id = StringName("refresh_card_%d" % index)
        card.display_name = "Refresh Card %d" % index
        card.cost = 0
        runtime_deck.append(card)

    var gauge = CardGaugeScript.new()
    gauge.configure(5)
    var controller = CardControllerScript.new()
    _check(controller.configure(runtime_deck, gauge, 3, 7, 0), "Effect test controller configures")
    _check(int(controller.process_input_snapshot(0, CARD_USE)) == CardControllerScript.Result.ACTIVATED, "First attack-bonus card activates")
    _check(is_equal_approx(controller.get_attack_damage_multiplier(), 1.3), "MVP-style attack bonus exposes a 1.3x multiplier")
    _check(int(controller.process_input_snapshot(1, CARD_USE)) == CardControllerScript.Result.ACTIVATED, "Second card with same effect activates")
    _check(controller.get_active_effect_remaining_ticks(&"attack_power_bonus") == 300, "Reusing an active effect refreshes its duration to 300 ticks")
    _check(is_equal_approx(controller.get_attack_damage_multiplier(), 1.3), "Same effect refresh does not stack its magnitude")
    _check(controller.advance_to_tick(301), "Effect timer advances to expiry")
    _check(not controller.has_active_effect(&"attack_power_bonus"), "Attack bonus expires after its 300-tick refreshed duration")
    _check(is_equal_approx(controller.get_attack_damage_multiplier(), 1.0), "Expired attack bonus returns multiplier to 1.0")


func _test_conditional_effect_activation() -> void:
    var database = CardDatabaseScript.create_default_database()
    var conditional_card: CardData = database.get_card(&"mau_chien")
    var deck: Array[CardData] = [conditional_card]
    var gauge = CardGaugeScript.new()
    gauge.configure(5)
    var controller = CardControllerScript.new()
    var requested_effects: Array[CardEffectData] = []
    controller.effect_requested.connect(func(_card_id: StringName, effect: CardEffectData) -> void:
        requested_effects.append(effect)
    )
    _check(controller.configure(deck, gauge, 1, 31, 0), "Conditional-effect test controller configures")
    _check(int(controller.process_input_snapshot(0, CARD_USE)) == CardControllerScript.Result.ACTIVATED, "HP-gated card can be activated")
    _check(requested_effects.size() == 1, "Conditional card emits its declarative effect request")
    _check(not controller.has_active_effect(&"attack_power_bonus"), "Conditional effect does not activate before M12 confirms its trigger")
    if not requested_effects.is_empty():
        _check(controller.apply_timed_effect(&"mau_chien", requested_effects[0]), "M12 can activate a timed effect after its trigger condition succeeds")
        _check(is_equal_approx(controller.get_attack_damage_multiplier(), 1.6), "Triggered conditional effect exposes its 1.6x attack multiplier")


func _test_input_validation() -> void:
    var database = CardDatabaseScript.create_default_database()
    var deck = database.get_mvp_deck()
    var gauge = CardGaugeScript.new()
    gauge.configure()
    var controller = CardControllerScript.new()
    controller.configure(deck, gauge, 3, 22, 0)
    _check(int(controller.process_input_snapshot(0, 1 << 11)) == CardControllerScript.Result.INVALID_INPUT_MASK, "Input bits outside the eleven-bit schema are rejected")
    _check(int(controller.process_input_snapshot(0, 0)) == CardControllerScript.Result.NO_ACTION, "Rejected input mask does not consume the simulation tick")
    _check(int(controller.process_input_snapshot(0, 0)) == CardControllerScript.Result.INVALID_TICK, "Duplicate simulation tick is rejected")
    _check(int(controller.process_input_snapshot(-1, CARD_NEXT)) == CardControllerScript.Result.INVALID_TICK, "Negative simulation tick is rejected")

    var unconfigured = CardControllerScript.new()
    _check(int(unconfigured.process_input_snapshot(0, CARD_USE)) == CardControllerScript.Result.NOT_CONFIGURED, "Unconfigured controller rejects card input")


func _check(condition: bool, message: String) -> void:
    if condition:
        _passed += 1
        print("[PASS] %s" % message)
    else:
        _failed += 1
        push_error("[FAIL] %s" % message)
