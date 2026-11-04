extends SceneTree

const TestSuite = preload("res://tests/m4/test_fighter_integration.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var suite = TestSuite.new()
	var result: Dictionary = await suite.run(self)
	print("\nM4 FIGHTER INTEGRATION TEST SUMMARY: %d passed, %d failed" % [result["passed"], result["failed"]])
	quit(0 if result["failed"] == 0 else 1)
