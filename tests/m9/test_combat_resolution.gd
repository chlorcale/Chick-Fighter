extends RefCounted

const Player1Script = preload("res://player_1.gd")
const Player2Script = preload("res://player_2.gd")
const AttackCatalogScript = preload("res://core/combat/attack_catalog.gd")
const HitboxScript = preload("res://core/combat/hitbox_component.gd")
const ResolverScript = preload("res://core/combat/combat_resolution_controller.gd")
const HitReactionScript = preload("res://core/combat/hit_reaction_controller.gd")

var _passed: int = 0
var _failed: int = 0


func run(tree: SceneTree) -> Dictionary:
	_passed = 0
	_failed = 0

	await _test_light_damage_and_deduplication(tree)
	await _test_heavy_and_special_reactions(tree)
	await _test_lethal_hit(tree)
	await _test_mismatched_attacker_id(tree)

	return {"passed": _passed, "failed": _failed}


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)


func _make_fighter(
	script: Script,
	fighter_name: String,
	maximum_hp: int,
	add_body_collider: bool
) -> FighterController:
	var fighter: FighterController = script.new() as FighterController
	fighter.name = fighter_name
	fighter.health_max_hp = maximum_hp
	fighter.set_physics_process(false)

	if add_body_collider:
		var collision := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(48.0, 80.0)
		collision.shape = rectangle
		fighter.add_child(collision)

	return fighter


func _make_stage(
	tree: SceneTree,
	defender_hp: int = 200
) -> Dictionary:
	var stage := Node2D.new()
	stage.name = "M9CombatResolutionTest"

	var attacker := _make_fighter(
		Player1Script,
		"M9Attacker",
		200,
		false
	)
	var defender := _make_fighter(
		Player2Script,
		"M9Defender",
		defender_hp,
		true
	)

	stage.add_child(attacker)
	stage.add_child(defender)
	tree.root.add_child(stage)

	return {
		"stage": stage,
		"attacker": attacker,
		"defender": defender,
	}


func _make_hitbox(
	attacker: FighterController,
	instance_id: int,
	attack_data: Resource,
	attacker_id_override: StringName = &""
) -> Area2D:
	var hitbox: Area2D = HitboxScript.new() as Area2D

	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(64.0, 40.0)
	collision.shape = rectangle
	hitbox.add_child(collision)

	var owner_id: StringName = StringName(attacker.name)
	if attacker_id_override != &"":
		owner_id = attacker_id_override

	hitbox.call("configure", owner_id, instance_id, attack_data)
	attacker.add_child(hitbox)
	return hitbox


func _register_hit(
	attacker: FighterController,
	defender: FighterController,
	hitbox: Area2D,
	attack_data: Resource
) -> int:
	var connected: bool = attacker.register_hitbox(hitbox)
	if not connected:
		return -1

	hitbox.call("set_elapsed_attack_tick", int(attack_data.get("startup_ticks")))
	return int(hitbox.call("try_register_hurtbox", defender.get_hurtbox()))


func _test_light_damage_and_deduplication(tree: SceneTree) -> void:
	var fixture: Dictionary = _make_stage(tree)
	var attacker: FighterController = fixture["attacker"]
	var defender: FighterController = fixture["defender"]
	var stage: Node = fixture["stage"]
	await tree.process_frame

	var attack: Resource = AttackCatalogScript.get_attack(&"light")
	var hitbox := _make_hitbox(attacker, 1001, attack)

	_check(is_instance_valid(defender.get_health_component()), "Fighter receives a HealthComponent")
	_check(int(defender.get_health_component().call("get_current_hp")) == 200, "Fighter health initializes from its configured maximum")
	_check(attacker.register_hitbox(hitbox), "Attacker can register a Hitbox signal")

	var result: int = _register_hit(attacker, defender, hitbox, attack)
	_check(result == HitboxScript.RegisterResult.REGISTERED, "Light hitbox registers the target")
	_check(
		int(defender.get_health_component().call("get_current_hp")) == 200 - int(attack.get("base_damage")),
		"Light hit applies AttackData base damage"
	)
	_check(
		defender.get_control_lock_remaining() == int(attack.get("hitstun_ticks")),
		"Light hit applies configured Hitstun duration"
	)

	var hp_before_duplicate: int = int(defender.get_health_component().call("get_current_hp"))
	var duplicate_result: int = int(
		hitbox.call("try_register_hurtbox", defender.get_hurtbox())
	)

	_check(
		duplicate_result == HitboxScript.RegisterResult.DUPLICATE_TARGET,
		"Same attack instance rejects a duplicate target"
	)
	_check(
		int(defender.get_health_component().call("get_current_hp")) == hp_before_duplicate,
		"Duplicate registration cannot apply damage twice"
	)

	stage.queue_free()
	await tree.process_frame


func _test_heavy_and_special_reactions(tree: SceneTree) -> void:
	var fixture: Dictionary = _make_stage(tree)
	var attacker: FighterController = fixture["attacker"]
	var defender: FighterController = fixture["defender"]
	var stage: Node = fixture["stage"]
	await tree.process_frame

	var heavy: Resource = AttackCatalogScript.get_attack(&"heavy")
	var heavy_hitbox := _make_hitbox(attacker, 2001, heavy)

	var heavy_result: int = _register_hit(attacker, defender, heavy_hitbox, heavy)
	_check(heavy_result == HitboxScript.RegisterResult.REGISTERED, "Heavy hit registers")
	_check(
		int(defender.get_health_component().call("get_current_hp")) == 200 - int(heavy.get("base_damage")),
		"Heavy hit applies its configured damage"
	)
	_check(
		defender.get_control_lock_remaining() == int(heavy.get("hitstun_ticks")),
		"Heavy hit applies its configured Hitstun"
	)

	defender.clear_hit_reactions()

	var special: Resource = AttackCatalogScript.get_attack(&"special")
	var special_hitbox := _make_hitbox(attacker, 2002, special)

	var special_result: int = _register_hit(attacker, defender, special_hitbox, special)
	_check(special_result == HitboxScript.RegisterResult.REGISTERED, "Special hit registers")
	_check(
		int(defender.get_health_component().call("get_current_hp")) \
			== 200 - int(heavy.get("base_damage")) - int(special.get("base_damage")),
		"Special hit applies its configured damage"
	)
	_check(
		defender.get_control_lock_remaining() == int(special.get("down_duration_ticks")),
		"Special hit applies Down instead of Hitstun when Down is configured"
	)
	_check(
		defender.get_control_lock_remaining() > int(special.get("hitstun_ticks")),
		"Special Down duration takes precedence over Hitstun"
	)

	stage.queue_free()
	await tree.process_frame


func _test_lethal_hit(tree: SceneTree) -> void:
	var fixture: Dictionary = _make_stage(tree, 5)
	var attacker: FighterController = fixture["attacker"]
	var defender: FighterController = fixture["defender"]
	var stage: Node = fixture["stage"]
	await tree.process_frame

	var attack: Resource = AttackCatalogScript.get_attack(&"light")
	var hitbox := _make_hitbox(attacker, 3001, attack)

	var result: int = _register_hit(attacker, defender, hitbox, attack)
	_check(result == HitboxScript.RegisterResult.REGISTERED, "Lethal hit is registered")
	_check(int(defender.get_health_component().call("get_current_hp")) == 0, "Lethal hit clamps HP to zero")
	_check(not defender.is_alive(), "Lethal hit marks the fighter defeated")
	_check(not defender.is_control_locked(), "Lethal hit does not start a new Hitstun reaction")

	stage.queue_free()
	await tree.process_frame


func _test_mismatched_attacker_id(tree: SceneTree) -> void:
	var fixture: Dictionary = _make_stage(tree)
	var attacker: FighterController = fixture["attacker"]
	var defender: FighterController = fixture["defender"]
	var stage: Node = fixture["stage"]
	await tree.process_frame

	var attack: Resource = AttackCatalogScript.get_attack(&"light")
	var hitbox := _make_hitbox(
		attacker,
		4001,
		attack,
		&"forged_attacker"
	)

	_check(attacker.register_hitbox(hitbox), "Hitbox with valid signal can be connected")
	hitbox.call("set_elapsed_attack_tick", int(attack.get("startup_ticks")))
	hitbox.call("try_register_hurtbox", defender.get_hurtbox())

	_check(
		int(defender.get_health_component().call("get_current_hp")) == 200,
		"Mismatched attacker identity cannot damage the target"
	)

	stage.queue_free()
	await tree.process_frame