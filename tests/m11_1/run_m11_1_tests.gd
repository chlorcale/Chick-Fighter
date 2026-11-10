extends SceneTree

const TestSuite = preload("res://tests/m11_1/test_card_system.gd")


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    var suite = TestSuite.new()
    var result: Dictionary = suite.run()
    print("\nM11.1 EXTENSIBLE CARD SYSTEM SUMMARY: %d passed, %d failed" % [
        int(result["passed"]),
        int(result["failed"]),
    ])
    quit(0 if int(result["failed"]) == 0 else 1)
