extends RefCounted

const Player1Script = preload("res://player_1.gd")
const Player2Script = preload("res://player_2.gd")
const MovementConfigScript = preload("res://core/movement/movement_config.gd")
const FacingControllerScript = preload("res://core/combat/facing_controller.gd")

var _passed: int = 0
var _failed: int = 0


func run(tree: SceneTree) -> Dictionary:
	_passed = 0
	_failed = 0

	var stage := Node2D.new()
	var p1: FighterController = Player1Script.new()
	var p2: FighterController = Player2Script.new()
	p1.name = "player1_test"
	p2.name = "player2_test"
	# Mirror the real Battle scene's unusual visual offsets and P2 parent scale.
	p1.position = Vector2(0.0, 0.0)
	p2.position = Vector2(905.0, 363.0)
	p2.scale = Vector2(0.3, 0.3)
	p1.breed = MovementConfigScript.Breed.GA_NOI
	p2.breed = MovementConfigScript.Breed.GA_TRE
	p1.set_physics_process(false)
	p2.set_physics_process(false)
	var p1_sprite := AnimatedSprite2D.new()
	# FighterController resolves this child by the exact name used in battle_system.tscn.
	p1_sprite.name = "AnimatedSprite2D"
	p1_sprite.position = Vector2(306.0, 396.0)
	var p2_sprite := AnimatedSprite2D.new()
	p2_sprite.name = "AnimatedSprite2D"
	p2_sprite.position = Vector2(-200.76, 95.92)
	# Match the actual Battle scene: P2 sprite has a negative local X scale.
	p2_sprite.scale = Vector2(-2.096, 2.064)
	p1.add_child(p1_sprite)
	p2.add_child(p2_sprite)
	stage.add_child(p1)
	stage.add_child(p2)
	tree.root.add_child(stage)
	# Let Godot propagate parent/child global transforms before sampling sprite anchors.
	await tree.process_frame

	_expect(is_equal_approx(p1.get_movement_config().speed, 200.0), "P1 can select Gà nòi preset explicitly")
	_expect(is_equal_approx(p2.get_movement_config().speed, 260.0), "P2 can select Gà tre preset explicitly")
	_expect(is_equal_approx(p1.get_movement_config().jump_impulse, 600.0), "P1 receives shared jump impulse")
	_expect(is_equal_approx(p2.get_movement_config().gravity, 2000.0), "P2 receives shared gravity")
	_expect(p1.get_facing() == FacingControllerScript.RIGHT, "P1 logical Facing is RIGHT")
	_expect(p2.get_facing() == FacingControllerScript.LEFT, "P2 logical Facing is LEFT")
	_expect(not p1_sprite.flip_h, "P1 positive-X sprite scale renders RIGHT without flip_h")
	_expect(not p2_sprite.flip_h, "P2 negative-X sprite scale renders LEFT without a second flip")
	_expect(p1.get_missing_input_actions().is_empty(), "P1 movement mapping uses existing Input Map actions")
	_expect(p2.get_missing_input_actions().is_empty(), "P2 movement mapping uses existing Input Map actions")

	p2.position.x = 200.0
	# A frame wait alone does not force Node2D's cached global transform to update
	# in this headless test. Mirror the proven runtime diagnostic: update both
	# the parent body and its offset child sprite before reading the anchor.
	p2.force_update_transform()
	p2_sprite.force_update_transform()
	await tree.process_frame
	var p1_anchor_after_cross: float = p1.get_facing_anchor_x()
	var p2_anchor_after_cross: float = p2.get_facing_anchor_x()
	var facing_after_cross: int = p1._refresh_facing()
	print("[DEBUG] Crossing anchors: P1=%.3f P2=%.3f Facing=%d" % [p1_anchor_after_cross, p2_anchor_after_cross, facing_after_cross])
	_expect(is_equal_approx(p1_anchor_after_cross, 306.0), "P1 facing anchor uses its named AnimatedSprite2D child")
	_expect(is_equal_approx(p2_anchor_after_cross, 139.772), "P2 facing anchor includes parent and negative sprite scale")
	_expect(facing_after_cross == FacingControllerScript.LEFT, "P1 tracks opponent sprite anchor crossing to its left")
	_expect(p1_sprite.flip_h, "P1 sprite visually mirrors when Facing becomes LEFT")
	p1.begin_attack_facing_lock()
	p2.position.x = 600.0
	p2.force_update_transform()
	p2_sprite.force_update_transform()
	await tree.process_frame
	var locked_facing: int = p1._refresh_facing()
	print("[DEBUG] During attack lock: P1 Facing=%d P1.flip_h=%s" % [locked_facing, str(p1_sprite.flip_h)])
	_expect(locked_facing == FacingControllerScript.LEFT, "P1 facing remains locked through attack sequence")
	_expect(p1_sprite.flip_h, "P1 sprite visual direction remains locked during attack")
	_expect(p1.finish_attack_facing_recovery() == FacingControllerScript.RIGHT, "P1 unlocks and refreshes facing after recovery")
	_expect(not p1_sprite.flip_h, "P1 sprite visually returns to RIGHT after recovery")
	_expect(p1.dash_policy == FighterController.DASH_DISABLED, "Dash eligibility remains disabled until owner selects a policy")

	stage.queue_free()
	return {"passed": _passed, "failed": _failed}


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)
