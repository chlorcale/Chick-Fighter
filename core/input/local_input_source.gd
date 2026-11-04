class_name LocalInputSource
extends InputSource

# Dictionary format: { logical_bit_index: StringName InputMap action }
var _mapping: Dictionary = {}
var _pending: Array[Vector2i] = [] # Vector2i(bit_index, 1=pressed / 0=released)
var _held: int = 0
var _last_tick: int = -1
var _last_frame: InputFrame = null
var _missing_actions: Array[StringName] = []
var _warned_missing: Dictionary = {}


func configure(mapping: Dictionary) -> void:
	_mapping.clear()
	_pending.clear()
	_held = 0
	_last_tick = -1
	_last_frame = null
	_missing_actions.clear()

	for raw_bit_index in mapping.keys():
		if typeof(raw_bit_index) != TYPE_INT:
			push_warning("LocalInputSource: mapping key must be an integer bit index.")
			continue

		var bit_index: int = int(raw_bit_index)
		if bit_index < 0 or bit_index >= InputBits.COUNT:
			push_warning("LocalInputSource: ignored out-of-range bit index %d." % bit_index)
			continue

		var raw_action: Variant = mapping[raw_bit_index]
		var action: StringName
		if typeof(raw_action) == TYPE_STRING_NAME:
			action = raw_action
		elif typeof(raw_action) == TYPE_STRING:
			action = StringName(raw_action)
		else:
			push_warning("LocalInputSource: action for bit %d must be String or StringName." % bit_index)
			continue

		_mapping[bit_index] = action
		if not InputMap.has_action(action):
			_missing_actions.append(action)
			if not _warned_missing.has(action):
				push_warning("LocalInputSource: missing Input Map action '%s'; bit %d will remain 0." % [String(action), bit_index])
				_warned_missing[action] = true


func get_missing_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	for action in _missing_actions:
		result.append(action)
	return result


func feed_event(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return

	for raw_bit_index in _mapping.keys():
		var bit_index: int = int(raw_bit_index)
		var action: StringName = _mapping[raw_bit_index]
		if not InputMap.has_action(action):
			continue
		if event.is_action_pressed(action):
			push_event(bit_index, true)
		elif event.is_action_released(action):
			push_event(bit_index, false)


func push_event(bit_index: int, is_pressed: bool) -> bool:
	if bit_index < 0 or bit_index >= InputBits.COUNT:
		push_error("LocalInputSource.push_event(): bit index out of range: %d" % bit_index)
		return false
	_pending.append(Vector2i(bit_index, 1 if is_pressed else 0))
	return true


func release_all() -> void:
	# Fold pending events first so a press queued immediately before focus loss is also released.
	var effective_held: int = _held
	for pending_event in _pending:
		var event_mask: int = InputBits.bit(pending_event.x)
		if pending_event.y == 1:
			effective_held |= event_mask
		else:
			effective_held &= ~event_mask

	_pending.clear()
	for bit_index in range(InputBits.COUNT):
		var event_mask: int = InputBits.bit(bit_index)
		if (effective_held & event_mask) != 0:
			_pending.append(Vector2i(bit_index, 0))


func sample(tick: int) -> InputFrame:
	if tick < 0:
		push_error("LocalInputSource.sample(): tick must be >= 0")
		return null
	if tick == _last_tick:
		return _last_frame
	if tick < _last_tick:
		push_error("LocalInputSource.sample(): tick went backwards (%d < %d)" % [tick, _last_tick])
		return null

	var current: int = _held
	var latched_pressed: int = 0
	var latched_released: int = 0

	for pending_event in _pending:
		var event_mask: int = InputBits.bit(pending_event.x)
		if pending_event.y == 1:
			current |= event_mask
			latched_pressed |= event_mask
		else:
			current &= ~event_mask
			latched_released |= event_mask

	_pending.clear()
	_last_frame = InputFrame.from_states(tick, current, _held, latched_pressed, latched_released)
	_held = current
	_last_tick = tick
	return _last_frame
