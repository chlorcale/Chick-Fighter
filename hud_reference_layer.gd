
extends CanvasLayer

var hud_reference: TextureRect

func _ready() -> void:
	layer = 100

	# Tìm TextureRect có tên HUD_Reference trong các node con.
	hud_reference = find_child(
		"HUD_Reference",
		true,
		false
	) as TextureRect

	if hud_reference == null:
		push_error(
			"Không tìm thấy HUD_Reference! " +
            "Hãy kiểm tra tên node trong Scene Tree."
		)
		return

	hud_reference.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	hud_reference.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_reference.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hud_reference.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_reference.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	hud_reference.modulate.a = 0.7


func _unhandled_key_input(event: InputEvent) -> void:
	if hud_reference == null:
		return

	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_F8:
			hud_reference.visible = not hud_reference.visible
