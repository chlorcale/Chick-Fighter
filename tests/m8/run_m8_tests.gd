extends SceneTree

const CoreTestSuite = preload("res://tests/m8/test_hit_reaction_controller.gd")
const IntegrationTestSuite = preload("res://tests/m8/test_fighter_reaction_integration.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var core_suite = CoreTestSuite.new()
	var core_result: Dictionary = await core_suite.run(self)

	var integration_suite = IntegrationTestSuite.new()
	var integration_result: Dictionary = await integration_suite.run(self)

	var passed: int = int(core_result["passed"]) + int(integration_result["passed"])
	var failed: int = int(core_result["failed"]) + int(integration_result["failed"])

	print("\nM8 CORE SUMMARY: %d passed, %d failed" % [
		core_result["passed"],
		core_result["failed"]
	])
	print("M8 FIGHTER INTEGRATION SUMMARY: %d passed, %d failed" % [
		integration_result["passed"],
		integration_result["failed"]
	])
	print("\nM8 TOTAL SUMMARY: %d passed, %d failed" % [passed, failed])

	quit(0 if failed == 0 else 1)