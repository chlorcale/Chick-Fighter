extends SceneTree

const TestSuiteScript = preload("res://tests/m3/test_movement.gd")


func _initialize() -> void:
	var suite = TestSuiteScript.new()
	var result: Dictionary = suite.run()
	var passed: int = int(result["passed"])
	var failed: int = int(result["failed"])

	print("\nM3 MOVEMENT TEST SUMMARY: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
