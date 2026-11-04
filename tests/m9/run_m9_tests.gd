extends SceneTree

const TestSuite = preload("res://tests/m9/test_combat_resolution.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var suite = TestSuite.new()
	var result: Dictionary = await suite.run(self)

	print("\nM9 COMBAT RESOLUTION SUMMARY: %d passed, %d failed" % [
		result["passed"],
		result["failed"]
	])
	quit(0 if int(result["failed"]) == 0 else 1)