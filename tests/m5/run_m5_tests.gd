extends SceneTree

const TestSuite = preload("res://tests/m5/test_attack_data.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var suite = TestSuite.new()
	var result: Dictionary = suite.run()
	print("\nM5 ATTACK DATA TEST SUMMARY: %d passed, %d failed" % [result["passed"], result["failed"]])
	quit(0 if int(result["failed"]) == 0 else 1)
