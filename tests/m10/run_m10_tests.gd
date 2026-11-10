extends SceneTree

const TestSuite = preload("res://tests/m10/test_special_gauge.gd")


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    var suite = TestSuite.new()
    var result: Dictionary = await suite.run(self)

    print("\nM10 SPECIAL GAUGE SUMMARY: %d passed, %d failed" % [
        result["passed"],
        result["failed"]
    ])
    quit(0 if int(result["failed"]) == 0 else 1)
