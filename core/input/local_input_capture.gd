class_name LocalInputCapture
extends Node

# Thin scene-tree adapter. Keep InputFrame and LocalInputSource themselves free of Node dependencies.
var source: LocalInputSource = null


func bind(input_source: LocalInputSource) -> void:
	source = input_source


func _ready() -> void:
	var window := get_window()
	if window != null and not window.focus_exited.is_connected(_on_window_focus_exited):
		window.focus_exited.connect(_on_window_focus_exited)


func _input(event: InputEvent) -> void:
	if source != null:
		source.feed_event(event)


func _on_window_focus_exited() -> void:
	if source != null and is_instance_valid(source):
		source.release_all()
