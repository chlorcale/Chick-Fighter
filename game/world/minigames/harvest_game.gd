extends "res://game/world/minigames/minigame.gd"

## Gặt lúa thử ở ruộng chín E_ruong_3_vang: một hàng 8 bụi lúa dưới chân hai cây rơm.
## Vạch đỏ chạy qua lại trên thanh nhịp; nhấn E khi vạch nằm trong ô vàng → phạt một bụi, lúa ngã
## thành bó, nhân vật bước tới bụi kế. Trật thì khựng tay một chút. 30 giây.

const ROW_Y: float = 946.0
const FIRST_X: float = 434.0
const STEP: float = 20.0
const TUFTS: int = 8
const STAND_GAP: float = 14.0
const TIME_LIMIT: float = 30.0

var _row: Node2D       # bụi lúa đứng + bó lúa (Y-sort ngay trên chân nhân vật)
var _ground: Node2D    # gốc rạ sau khi gặt
var _bar: Control
var _zone: ColorRect
var _cursor: ColorRect
var _cut: int = 0
var _misses: int = 0
var _cursor_pos: float = 0.0
var _cursor_dir: float = 1.0
var _zone_center: float = 0.5
var _zone_width: float = 0.22
var _stun: float = 0.0
var _stepping: bool = false
var _time: float = 0.0


func _start() -> void:
	time_left = TIME_LIMIT
	set_texts("GẶT LÚA", "Nhấn [E] khi vạch đỏ nằm trong ô vàng để phạt một bụi lúa. Gặt hết hàng %d bụi!" % TUFTS)
	_row = Node2D.new()
	_row.position = Vector2(0, ROW_Y - 1.0)
	_row.draw.connect(_draw_row)
	world.map_view.add_actor(_row)
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground)
	world.map_view.add_ground(_ground)
	_build_bar()
	_new_zone()
	var tween := world.create_tween()
	tween.tween_property(world.player, "position", _stand_pos(0), 0.25)
	_update_status()


func _build_bar() -> void:
	_bar = Control.new()
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -220.0
	_bar.offset_right = 220.0
	_bar.offset_top = -170.0
	_bar.offset_bottom = -140.0
	add_child(_bar)
	var back := ColorRect.new()
	back.color = Color(0.08, 0.05, 0.03, 0.9)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.add_child(back)
	var track := ColorRect.new()
	track.color = Color(0.35, 0.5, 0.25)
	track.position = Vector2(4, 4)
	track.size = Vector2(432, 22)
	_bar.add_child(track)
	_zone = ColorRect.new()
	_zone.color = Color(1.0, 0.82, 0.25)
	_zone.position = Vector2(4, 4)
	_zone.size = Vector2(80, 22)
	_bar.add_child(_zone)
	_cursor = ColorRect.new()
	_cursor.color = Color(0.95, 0.15, 0.1)
	_cursor.size = Vector2(5, 34)
	_cursor.position = Vector2(4, -2)
	_bar.add_child(_cursor)


func _new_zone() -> void:
	_zone_width = maxf(0.13, 0.22 - 0.012 * float(_cut))
	_zone_center = randf_range(0.15 + _zone_width * 0.5, 0.85 - _zone_width * 0.5)
	_zone.position.x = 4.0 + 432.0 * (_zone_center - _zone_width * 0.5)
	_zone.size.x = 432.0 * _zone_width


func _tuft_x(i: int) -> float:
	return FIRST_X + STEP * float(i)


func _stand_pos(i: int) -> Vector2:
	return Vector2(_tuft_x(i) - STAND_GAP, ROW_Y)


func _in_zone() -> bool:
	return absf(_cursor_pos - _zone_center) <= _zone_width * 0.5


func _on_action(action: StringName) -> void:
	if action != &"confirm" or _stun > 0.0 or _stepping or _cut >= TUFTS:
		return
	if _in_zone():
		_cut_tuft()
	else:
		_misses += 1
		_stun = 0.45
		toast("Trật rồi!", Color(1.0, 0.6, 0.5))
		sound(&"miss", Vector2(_tuft_x(_cut), ROW_Y))


func _cut_tuft() -> void:
	var pos := Vector2(_tuft_x(_cut), ROW_Y - 6.0)
	_cut += 1
	air_fx.burst(pos, Color(0.98, 0.85, 0.35), 10, 30.0, 60.0, 0.6, 18.0)
	air_fx.burst(pos, Color(0.7, 0.55, 0.2), 5, 20.0, 40.0, 0.5, 10.0)
	sound(&"cut", pos)
	toast(["Ngọt!", "Gọn!", "Đẹp!"][_cut % 3], Color(0.7, 1.0, 0.6))
	_row.queue_redraw()
	_ground.queue_redraw()
	_update_status()
	if _cut >= TUFTS:
		sound(&"win", pos)
		_stepping = true
		await get_tree().create_timer(0.7).timeout
		finish({"bundles": _cut, "misses": _misses})
		return
	_new_zone()
	_stepping = true
	var tween := world.create_tween()
	tween.tween_property(world.player, "position", _stand_pos(_cut), 0.22)
	await tween.finished
	_stepping = false


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "bundles": _cut, "misses": _misses}


func _update_status() -> void:
	set_status("Đã gặt: %d/%d bó · còn %d giây" % [_cut, TUFTS, ceili(maxf(time_left, 0.0))])


func _tick(delta: float) -> void:
	_time += delta
	time_left -= delta
	if time_left <= 0.0 and not _stepping:
		finish({"bundles": _cut, "misses": _misses})
		return
	if _stun > 0.0:
		_stun -= delta
	else:
		var speed: float = 1.15 + 0.09 * float(_cut)
		_cursor_pos += _cursor_dir * speed * delta
		if _cursor_pos >= 1.0:
			_cursor_pos = 1.0
			_cursor_dir = -1.0
		elif _cursor_pos <= 0.0:
			_cursor_pos = 0.0
			_cursor_dir = 1.0
	_cursor.position.x = 4.0 + 432.0 * _cursor_pos - 2.0
	_cursor.color = Color(0.95, 0.15, 0.1) if _stun <= 0.0 else Color(0.5, 0.5, 0.5)
	if autopilot and absf(_cursor_pos - _zone_center) <= 0.03:
		press(&"confirm")
	_update_status()
	_row.queue_redraw()


# ------------------------------------------------------------------ vẽ (toạ độ bản đồ)

func _draw_row() -> void:
	_row.draw_set_transform(-_row.position)
	var stalk := Color(0.52, 0.46, 0.12)
	var head := Color(1.0, 0.86, 0.36)
	var dark := Color(0.4, 0.28, 0.06)
	for i in range(TUFTS):
		var x: float = _tuft_x(i)
		if i < _cut:
			# Bó lúa nằm ngang, buộc rơm ở giữa.
			var b := Vector2(x - 6, ROW_Y + 2)
			_row.draw_rect(Rect2(b + Vector2(-1, -1), Vector2(14, 6)), dark)
			_row.draw_rect(Rect2(b, Vector2(12, 4)), Color(0.93, 0.78, 0.3))
			_row.draw_rect(Rect2(b + Vector2(8, 0), Vector2(4, 4)), head)
			_row.draw_rect(Rect2(b + Vector2(5, -1), Vector2(2, 6)), Color(0.55, 0.35, 0.12))
			continue
		# Bụi lúa đứng: bóng dưới gốc, thân sẫm viền tối, bông vàng sáng trĩu đầu (nổi trên nền ruộng vàng).
		var sway: float = roundf(sin(_time * 2.5 + x * 0.3) * 1.0)
		_row.draw_rect(Rect2(Vector2(x - 7, ROW_Y - 2), Vector2(15, 3)), Color(0.35, 0.25, 0.05, 0.45))
		for k in range(-4, 5):
			var base := Vector2(x + float(k) * 1.4, ROW_Y)
			var height: float = 19.0 - absf(float(k)) * 1.6
			var tip := base + Vector2(float(k) * 1.3 + sway, -height)
			_row.draw_line(base.round() + Vector2(1, 0), tip.round() + Vector2(1, 0), dark, 1.0)
			_row.draw_line(base.round(), tip.round(), stalk, 1.0)
		for k in range(-4, 5, 2):
			var tip := Vector2(x + float(k) * 1.4, ROW_Y) + Vector2(float(k) * 1.3 + sway, -(19.0 - absf(float(k)) * 1.6))
			var bend: float = 2.0 if k >= 0 else -3.0
			var grain := (tip + Vector2(bend, 0)).round()
			_row.draw_rect(Rect2(grain + Vector2(-1, -1), Vector2(4, 6)), dark)
			_row.draw_rect(Rect2(grain, Vector2(2, 4)), head)


func _draw_ground() -> void:
	for i in range(_cut):
		var x: float = _tuft_x(i)
		for k in range(-3, 4, 2):
			_ground.draw_rect(Rect2(Vector2(x + float(k) * 1.5, ROW_Y - 2).round(), Vector2(1, 2)), Color(0.55, 0.4, 0.12))


func _cleanup() -> void:
	if is_instance_valid(_row):
		_row.queue_free()
	if is_instance_valid(_ground):
		_ground.queue_free()
