extends RefCounted

const FacingControllerScript = preload("res://core/combat/facing_controller.gd")

var _passed: int = 0
var _failed: int = 0


func run() -> Dictionary:
	_passed = 0
	_failed = 0

	_test_initial_facing()
	_test_opponent_relative_facing()
	_test_equal_x_keeps_last_facing()
	_test_crossing_updates_facing()
	_test_attack_startup_locks_facing()
	_test_attack_active_keeps_lock()
	_test_attack_recovery_keeps_lock()
	_test_recovery_completion_unlocks_and_refreshes()
	_test_lock_does_not_change_without_attack_lifecycle_calls()

	return {"passed": _passed, "failed": _failed}


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)


func _test_initial_facing() -> void:
	var right_controller = FacingControllerScript.new(FacingControllerScript.RIGHT)
	var left_controller = FacingControllerScript.new(FacingControllerScript.LEFT)
	_expect(right_controller.facing == FacingControllerScript.RIGHT, "Initial facing RIGHT is preserved")
	_expect(left_controller.facing == FacingControllerScript.LEFT, "Initial facing LEFT is preserved")


func _test_opponent_relative_facing() -> void:
	var controller = FacingControllerScript.new(FacingControllerScript.RIGHT)
	_expect(controller.update_facing(100.0, 200.0) == FacingControllerScript.RIGHT, "Opponent on right produces RIGHT facing")
	_expect(controller.update_facing(200.0, 100.0) == FacingControllerScript.LEFT, "Opponent on left produces LEFT facing")


func _test_equal_x_keeps_last_facing() -> void:
	var controller = FacingControllerScript.new(FacingControllerScript.LEFT)
	_expect(controller.update_facing(100.0, 100.0) == FacingControllerScript.LEFT, "Equal X retains last facing")


func _test_crossing_updates_facing() -> void:
	var controller = FacingControllerScript.new(FacingControllerScript.RIGHT)
	controller.update_facing(100.0, 200.0)
	_expect(controller.update_facing(200.0, 100.0) == FacingControllerScript.LEFT, "Crossing opponent updates facing outside attack")


func _test_attack_startup_locks_facing() -> void:
	var controller = FacingControllerScript.new(FacingControllerScript.RIGHT)
	controller.begin_attack_startup()
	_expect(controller.is_attack_locked, "Entering AttackStartup activates facing lock")
	_expect(controller.update_facing(200.0, 100.0) == FacingControllerScript.RIGHT, "Facing does not flip during AttackStartup")


func _test_attack_active_keeps_lock() -> void:
	var controller = FacingControllerScript.new(FacingControllerScript.RIGHT)
	controller.begin_attack_startup()
	# The controller deliberately does not depend on FSM state names. The caller
	# keeps the lock active while the fighter is in AttackActive.
	controller.update_facing(200.0, 100.0)
	_expect(controller.is_attack_locked, "Facing lock remains active through AttackActive")
	_expect(controller.facing == FacingControllerScript.RIGHT, "Facing remains unchanged through AttackActive")


func _test_attack_recovery_keeps_lock() -> void:
	var controller = FacingControllerScript.new(FacingControllerScript.RIGHT)
	controller.begin_attack_startup()
	# The same lock remains active until the explicit recovery-complete callback.
	controller.update_facing(300.0, 100.0)
	_expect(controller.is_attack_locked, "Facing lock remains active through AttackRecovery")
	_expect(controller.facing == FacingControllerScript.RIGHT, "Facing remains unchanged through AttackRecovery")


func _test_recovery_completion_unlocks_and_refreshes() -> void:
	var controller = FacingControllerScript.new(FacingControllerScript.RIGHT)
	controller.begin_attack_startup()
	var facing_after_recovery: int = controller.finish_attack_recovery(200.0, 100.0)
	_expect(not controller.is_attack_locked, "AttackRecovery completion releases facing lock")
	_expect(facing_after_recovery == FacingControllerScript.LEFT, "Facing refreshes toward opponent after recovery")


func _test_lock_does_not_change_without_attack_lifecycle_calls() -> void:
	var controller = FacingControllerScript.new(FacingControllerScript.LEFT)
	controller.update_facing(100.0, 200.0)
	_expect(not controller.is_attack_locked, "Ordinary facing updates do not create an attack lock")
	_expect(controller.facing == FacingControllerScript.RIGHT, "Facing follows opponent outside attack sequence")
