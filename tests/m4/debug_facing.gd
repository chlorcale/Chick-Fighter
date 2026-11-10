extends SceneTree

const Player1Script = preload("res://player_1.gd")
const Player2Script = preload("res://player_2.gd")

func _initialize() -> void:
    call_deferred("_run_debug")

func _run_debug() -> void:
    var stage := Node2D.new()

    var p1 = Player1Script.new()
    var p2 = Player2Script.new()

    p1.name = "player1_test"
    p2.name = "player2_test"

    p1.position = Vector2(0, 0)
    p2.position = Vector2(905, 363)
    p2.scale = Vector2(0.3, 0.3)

    var s1 := AnimatedSprite2D.new()
    s1.name = "AnimatedSprite2D"
    s1.position = Vector2(306, 396)

    var s2 := AnimatedSprite2D.new()
    s2.name = "AnimatedSprite2D"
    s2.position = Vector2(-200.76, 95.92)

    p1.add_child(s1)
    p2.add_child(s2)

    stage.add_child(p1)
    stage.add_child(p2)
    root.add_child(stage)

    await process_frame

    print("\n========== M4 FACING DEBUG ==========")
    print("P1 opponent: ", p1.get("_opponent"))
    print("P1 body global X: ", p1.global_position.x)
    print("P1 sprite global X: ", s1.global_position.x)
    print("P1 facing anchor: ", p1.get_facing_anchor_x())

    print("P2 body global X: ", p2.global_position.x)
    print("P2 scale: ", p2.global_scale)
    print("P2 sprite local X: ", s2.position.x)
    print("P2 sprite global X: ", s2.global_position.x)
    print("P2 facing anchor: ", p2.get_facing_anchor_x())

    print("\n========== MOVE P2 TO X=200 ==========")

    p2.position.x = 200
    p2.force_update_transform()
    s2.force_update_transform()

    await process_frame

    print("P1 anchor: ", p1.get_facing_anchor_x())
    print("P2 body global X: ", p2.global_position.x)
    print("P2 sprite global X: ", s2.global_position.x)
    print("P2 facing anchor: ", p2.get_facing_anchor_x())
    print("P1 opponent anchor: ", p1.call("_get_opponent_facing_anchor_x"))

    var result = p1.call("_refresh_facing")
    print("P1 facing after refresh: ", result)
    print("Expected: -1 (LEFT)")

    print("\n========== ATTACK LOCK ==========")
    p1.call("begin_attack_facing_lock")
    print("Lock active: ", p1.get("_facing_controller").is_attack_locked)

    p2.position.x = 600
    p2.force_update_transform()
    s2.force_update_transform()

    await process_frame

    print("P2 anchor after moving right: ", p2.get_facing_anchor_x())
    print("P1 facing while locked: ", p1.call("_refresh_facing"))
    print("Expected while locked: -1 (LEFT)")

    stage.queue_free()
    quit()
