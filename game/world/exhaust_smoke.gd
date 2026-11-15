class_name ExhaustSmoke
extends Node2D

## Khói ống xả: các cụm khói pixel ở toạ độ thế giới (node top_level nên không đi theo xe).

const MAX_PUFFS: int = 18
const LIFE: float = 0.7

var _puffs: Array[Dictionary] = [] # {pos, vel, age}


func _ready() -> void:
	top_level = true
	position = Vector2.ZERO


func emit(world_pos: Vector2, drift: Vector2) -> void:
	if _puffs.size() >= MAX_PUFFS:
		_puffs.remove_at(0)
	_puffs.append({"pos": world_pos, "vel": drift, "age": 0.0})
	queue_redraw()


func _process(delta: float) -> void:
	if _puffs.is_empty():
		return
	for p in _puffs:
		p["age"] += delta
		p["pos"] += p["vel"] * delta
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return p["age"] < LIFE)
	queue_redraw()


func _draw() -> void:
	for p in _puffs:
		var t: float = p["age"] / LIFE
		var s: int = 3 + int(t * 5.0)
		var pos: Vector2 = p["pos"]
		var x: float = floorf(pos.x) - s / 2
		var y: float = floorf(pos.y) - s / 2
		# Xám đậm lúc mới phụt rồi nhạt dần: thấy rõ cả trên đường bê tông sáng lẫn trên cỏ.
		var shade: float = 0.42 + t * 0.4
		var col := Color(shade, shade, shade + 0.04, 0.85 * (1.0 - t * t))
		draw_rect(Rect2(x + 1, y, s - 2, s), col)
		draw_rect(Rect2(x, y + 1, s, s - 2), col)
