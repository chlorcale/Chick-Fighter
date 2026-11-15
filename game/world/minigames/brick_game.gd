extends "res://game/world/minigames/minigame.gd"

## Công trường: bốc gạch từ đống gạch (F_chong_gach) mang tới chân giàn giáo cạnh máy trộn hồ.
## Nhân vật tự đi bằng WASD; đứng ở đống gạch nhấn E để bốc (gạch hiện trên đầu), tới chỗ xuống gạch
## nhấn E để chất. Đủ BRICK_TARGET cữ trong TIME_LIMIT giây = đủ ca. Đi xa công trường = bỏ ca.

const PILE: Vector2 = Vector2(1146, 784)   # trước đống gạch
const DROP: Vector2 = Vector2(1208, 784)   # chân giàn giáo, cạnh máy trộn
const STACK: Vector2 = Vector2(1205, 776)  # chỗ chồng gạch đã chở tới (mép dưới)
const REACH: float = 14.0
const TIME_LIMIT: float = 40.0
const LEAVE_DISTANCE: float = 200.0

var target: int = 8

var _carrying: bool = false
var _delivered: int = 0
var _brick_icon: Node2D
var _marks: Node2D
var _stack: Node2D
var _time: float = 0.0


func _start() -> void:
	time_left = TIME_LIMIT
	set_texts("BỐC GẠCH", "Đứng ở đống gạch nhấn [E] để bốc, mang tới chân giàn giáo (mũi tên) nhấn [E] để chất. Đủ %d cữ là đủ ca!" % target)
	var player: Node2D = world.player
	if bool(player.get("riding")):
		world.mount_bike(false)
	player.set("can_move", true)
	_brick_icon = Node2D.new()
	_brick_icon.z_index = 1
	_brick_icon.visible = false
	_brick_icon.draw.connect(_draw_brick_icon)
	player.add_child(_brick_icon)
	_marks = Node2D.new()
	_marks.z_index = 30
	_marks.draw.connect(_draw_marks)
	world.add_child(_marks)
	_stack = Node2D.new()
	_stack.position = STACK
	_stack.draw.connect(_draw_stack)
	world.map_view.add_actor(_stack)
	_update_status()


func _wants(action: StringName) -> bool:
	return action == &"confirm" or action == &"cancel"


func _on_action(action: StringName) -> void:
	if action != &"confirm":
		return
	var pos: Vector2 = world.player.position
	if not _carrying and pos.distance_to(PILE) <= REACH:
		_carrying = true
		_brick_icon.visible = true
		air_fx.burst(PILE + Vector2(0, -6), Color(0.75, 0.4, 0.25), 6, 18.0, 50.0, 0.45, 12.0)
		sound(&"pick", PILE)
	elif _carrying and pos.distance_to(DROP) <= REACH:
		_carrying = false
		_brick_icon.visible = false
		_delivered += 1
		_stack.queue_redraw()
		air_fx.burst(STACK + Vector2(0, -4), Color(0.8, 0.72, 0.6), 8, 20.0, 30.0, 0.5, 8.0)
		sound(&"drop", DROP)
		if _delivered >= target:
			toast("Đủ ca rồi!", Color(0.7, 1.0, 0.6))
			sound(&"win", DROP)
			finish({"bricks": _delivered, "full": true})
			return
		toast("%d/%d" % [_delivered, target], Color(1.0, 0.9, 0.6))
	elif _carrying:
		toast("Mang tới chân giàn giáo!", Color(1.0, 0.8, 0.5))
	else:
		toast("Ra đống gạch mà bốc!", Color(1.0, 0.8, 0.5))
	_update_status()


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "bricks": _delivered, "full": false}


func _update_status() -> void:
	set_status("Gạch: %d/%d · còn %d giây%s" % [_delivered, target, ceili(maxf(time_left, 0.0)), " · đang bưng gạch" if _carrying else ""])


func _tick(delta: float) -> void:
	_time += delta
	time_left -= delta
	var pos: Vector2 = world.player.position
	if pos.distance_to(PILE) > LEAVE_DISTANCE:
		finish(_cancel_result())
		return
	if time_left <= 0.0:
		finish({"bricks": _delivered, "full": false})
		return
	if autopilot:
		_auto_walk(delta)
	_update_status()
	_marks.queue_redraw()


## Tự đi theo làn trước đống gạch (chỉ dùng khi test/autopilot).
func _auto_walk(delta: float) -> void:
	var goal: Vector2 = DROP if _carrying else PILE
	var pos: Vector2 = world.player.position
	if pos.distance_to(goal) <= 2.0:
		press(&"confirm")
		return
	world.player.position = pos.move_toward(goal, WorldPlayer.WALK_SPEED * delta)


func _cleanup() -> void:
	world.player.set("can_move", false)
	for node in [_brick_icon, _marks]:
		if is_instance_valid(node):
			node.queue_free()
	if is_instance_valid(_stack):
		# Chồng gạch ở lại một lúc rồi biến (thợ đem đi xây).
		var tween := _stack.create_tween()
		tween.tween_interval(4.0)
		tween.tween_property(_stack, "modulate:a", 0.0, 1.0)
		tween.tween_callback(_stack.queue_free)


# ------------------------------------------------------------------ vẽ

func _draw_brick(canvas: CanvasItem, pos: Vector2) -> void:
	canvas.draw_rect(Rect2(pos + Vector2(-1, -1), Vector2(10, 6)), Color(0.3, 0.12, 0.08))
	canvas.draw_rect(Rect2(pos, Vector2(8, 4)), Color(0.78, 0.33, 0.22))
	canvas.draw_rect(Rect2(pos, Vector2(8, 1)), Color(0.92, 0.5, 0.36))
	canvas.draw_rect(Rect2(pos + Vector2(3, 1), Vector2(1, 3)), Color(0.55, 0.22, 0.15))


func _draw_brick_icon() -> void:
	var bob: float = roundf(sin(_time * 9.0) * 0.6)
	_draw_brick(_brick_icon, Vector2(-8, -50 + bob))
	_draw_brick(_brick_icon, Vector2(-1, -50 + bob))
	_draw_brick(_brick_icon, Vector2(-5, -54 + bob))


func _draw_stack() -> void:
	for i in range(_delivered):
		var row: int = floori(i / 3.0)
		var col: int = i % 3
		_draw_brick(_stack, Vector2(-14 + col * 9 + (row % 2) * 4, -5 - row * 5))


func _draw_marks() -> void:
	var goal: Vector2 = DROP if _carrying else PILE
	var p: Vector2 = (goal + Vector2(0, -30 + roundf(sin(_time * 6.0) * 2.0))).round()
	var arrow := PackedVector2Array([p + Vector2(-5, -7), p + Vector2(5, -7), p])
	_marks.draw_colored_polygon(arrow, Color(0.6, 1.0, 0.5) if _carrying else Color(1.0, 0.85, 0.2))
	_marks.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), Color(0.15, 0.1, 0.0), 1.0)
