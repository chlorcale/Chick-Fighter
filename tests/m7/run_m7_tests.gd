extends SceneTree

const TestSuite = preload("res://tests/m7/test_health_component.gd")


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    var suite = TestSuite.new()
    var result: Dictionary = await suite.run(self)
    print("\nM7 HEALTH COMPONENT TEST SUMMARY: %d passed, %d failed" % [result["passed"], result["failed"]])
    quit(0 if int(result["failed"]) == 0 else 1)