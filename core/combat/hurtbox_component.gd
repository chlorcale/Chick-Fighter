class_name HurtboxComponent
extends Area2D

## Receives overlap notifications from opposing HitboxComponent nodes.
## It never applies damage; damage resolution belongs to M9.

const HITBOX_COLLISION_LAYER: int = 1 << 2 # Layer 3
const HURTBOX_COLLISION_LAYER: int = 1 << 3 # Layer 4
const HURTBOX_GROUP: StringName = &"fighter_hurtboxes"

@export var owner_fighter_id: StringName = &""
@export_range(0.1, 1.0, 0.01) var crouch_height_scale: float = 0.6

var _collision_node: Node2D
var _base_position: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _base_height: float = 0.0
var _shape_cached: bool = false
var _is_crouched: bool = false


func _ready() -> void:
	collision_layer = HURTBOX_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(HURTBOX_GROUP)
	_cache_collision_node()


func set_owner_fighter_id(value: StringName) -> void:
	owner_fighter_id = value


func get_owner_fighter_id() -> StringName:
	return owner_fighter_id


## Clone the existing fighter body collider without changing the body collider.
## Supports both CollisionShape2D and CollisionPolygon2D used by the current Battle scene.
func copy_collision_from(source: Node2D) -> bool:
	if source == null:
		push_error("HurtboxComponent.copy_collision_from(): source cannot be null")
		return false

	var copy: Node2D = null
	if source is CollisionShape2D:
		var source_shape := source as CollisionShape2D
		if source_shape.shape == null:
			push_error("HurtboxComponent.copy_collision_from(): source shape is null")
			return false
		var shape_copy := CollisionShape2D.new()
		shape_copy.shape = source_shape.shape.duplicate(true) as Shape2D
		shape_copy.disabled = source_shape.disabled
		shape_copy.transform = source_shape.transform
		copy = shape_copy
	elif source is CollisionPolygon2D:
		var source_polygon := source as CollisionPolygon2D
		if source_polygon.polygon.size() < 3:
			push_error("HurtboxComponent.copy_collision_from(): source polygon has fewer than 3 points")
			return false
		var polygon_copy := CollisionPolygon2D.new()
		polygon_copy.polygon = source_polygon.polygon.duplicate()
		polygon_copy.build_mode = source_polygon.build_mode
		polygon_copy.disabled = source_polygon.disabled
		polygon_copy.transform = source_polygon.transform
		copy = polygon_copy
	else:
		push_error("HurtboxComponent.copy_collision_from(): unsupported collider type")
		return false

	copy.name = "CollisionShape2D" if copy is CollisionShape2D else "CollisionPolygon2D"
	add_child(copy)
	_cache_collision_node()
	return _shape_cached


## Shrinks the hurtbox height to 60% while keeping its lower edge approximately anchored.
## This implements the GDD's 40% crouch hurtbox reduction without changing pushbox physics.
func set_crouched(value: bool) -> bool:
	if not _shape_cached or not is_instance_valid(_collision_node):
		return false
	if _is_crouched == value:
		return true

	_is_crouched = value
	if value:
		_collision_node.scale = Vector2(_base_scale.x, _base_scale.y * crouch_height_scale)
		var added_downward_offset: float = _base_height * absf(_base_scale.y) * (1.0 - crouch_height_scale) * 0.5
		_collision_node.position = _base_position + Vector2(0.0, added_downward_offset)
	else:
		_collision_node.position = _base_position
		_collision_node.scale = _base_scale
	queue_redraw()
	return true


func is_crouched() -> bool:
	return _is_crouched


func has_collision_shape() -> bool:
	return _shape_cached and is_instance_valid(_collision_node)


func get_collision_node() -> Node2D:
	return _collision_node


func get_base_height() -> float:
	return _base_height


func set_debug_draw_enabled(enabled: bool) -> void:
	set_meta("debug_draw_enabled", enabled)
	queue_redraw()


func _cache_collision_node() -> void:
	_collision_node = null
	_shape_cached = false
	for child in get_children():
		if child is CollisionShape2D:
			var shape_node := child as CollisionShape2D
			if shape_node.shape == null:
				continue
			_collision_node = shape_node
			_base_height = shape_node.shape.get_rect().size.y
			break
		elif child is CollisionPolygon2D:
			var polygon_node := child as CollisionPolygon2D
			if polygon_node.polygon.size() < 3:
				continue
			_collision_node = polygon_node
			_base_height = _get_polygon_bounds(polygon_node.polygon).size.y
			break

	if is_instance_valid(_collision_node):
		_base_position = _collision_node.position
		_base_scale = _collision_node.scale
		_shape_cached = _base_height > 0.0


func _get_polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for index in range(1, points.size()):
		bounds = bounds.expand(points[index])
	return bounds


func _draw() -> void:
	if not bool(get_meta("debug_draw_enabled", false)):
		return
	if not is_instance_valid(_collision_node):
		return
	var debug_color := Color(0.2, 0.8, 1.0, 0.9)
	if _collision_node is CollisionShape2D:
		var shape_node := _collision_node as CollisionShape2D
		if shape_node.shape != null:
			draw_set_transform(shape_node.position, shape_node.rotation, shape_node.scale)
			draw_rect(shape_node.shape.get_rect(), debug_color, false, 2.0)
	elif _collision_node is CollisionPolygon2D:
		var polygon_node := _collision_node as CollisionPolygon2D
		draw_set_transform(polygon_node.position, polygon_node.rotation, polygon_node.scale)
		draw_polyline(_closed_polygon(polygon_node.polygon), debug_color, 2.0)


func _closed_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if result.size() >= 3:
		result.append(result[0])
	return result
