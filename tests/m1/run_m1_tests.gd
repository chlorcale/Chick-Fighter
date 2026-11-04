extends SceneTree

const TestSuite = preload("res://tests/m1/test_input_frame.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var suite = TestSuite.new()
	var result: Dictionary = await suite.run(self)
	print("\nM1 INPUT TEST SUMMARY: %d passed, %d failed" % [result["passed"], result["failed"]])	
	quit(0 if int(result["failed"]) == 0 else 1)
