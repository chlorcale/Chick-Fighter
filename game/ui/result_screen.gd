class_name ResultScreen
extends CanvasLayer

## Màn kết quả sau trận: thắng/thua (hoặc "CHẠY THÔI!" khi công an ập vào), tiền thưởng, gà đang chọn với đủ lớp
## trang bị, thay đổi Thể trạng, EXP chạy thanh, lên cấp (công thức 3–4).
##
## HỢP ĐỒNG (main.gd): đặt won, rewards, exp_gain (+ tuỳ chọn raid, condition_loss) trước add_child; `await screen.run()`
## (run() cộng EXP qua GameState.add_exp như trước). Thể trạng hiển thị là DỰ KIẾN: thua thường −15 × hệ số đột biến
## (GameState.record_result sẽ trừ sau); thắng / raid: không đổi. Đặt `condition_loss` = −1 để tự tính, 0 để ẩn.

signal _closed

var won: bool = false
## Công an ập vào (BattleDirector result "raid"): hiện "CHẠY THÔI!", không phải thắng cũng không phải thua.
var raid: bool = false
var rewards: Array[String] = []
var exp_gain: int = 0
## Thể trạng sẽ mất sau trận (−1 = tự tính theo GameState: thua thường −15 × condition_loss_mult).
var condition_loss: float = -1.0

var _canvas: Control
var _time: float = 0.0
var _start_level: int = 1
var _start_xp: int = 0
var _shown_level: int = 1
var _shown_xp: float = 0.0
var _remaining: float = 0.0
var _level_ups: int = 0
var _sfx: Sfx
var _views: Array[Node2D] = []
var _cond_before: float = 100.0
var _cond_after: float = 100.0
var _name: String = ""


func _ready() -> void:
	layer = 45
	_sfx = Sfx.new()
	add_child(_sfx)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_screen)
	UISkin.pixel(_canvas)
	add_child(_canvas)
	var c: Dictionary = GameState.active_chicken()
	_name = String(c["name"])
	_cond_before = float(c["condition"])
	var loss: float = condition_loss
	if loss < 0.0:
		loss = 0.0
		if not won and not raid:
			var mult: float = 1.0
			for m in c["mutations"]:
				mult *= float(GameState.Mutations.info(m).get("flags", {}).get("condition_loss_mult", 1.0))
			loss = GameState.CONDITION_LOSS_ON_DEFEAT * mult
	_cond_after = clampf(_cond_before - loss, 0.0, GameState.CONDITION_MAX)
	var sides: Array = BattleDirector.last_match.get("sides", [])
	if sides.size() != 2:
		sides = [GameState.player_side(), {}]
	for i in range(2):
		var side: Dictionary = sides[i]
		if side.is_empty():
			continue
		var winner: bool = (i == 0) == won
		var tag: String = "taunt" if winner else "nam"
		if raid:
			tag = "walk_f"
		var view: Node2D = FighterView.make_portrait(side, tag)
		var portrait := view as FighterView.Portrait
		portrait.set_facing(1 if i == 0 else -1)
		if raid:
			portrait.set_facing(-1 if i == 0 else 1) # bỏ chạy ra hai phía
			portrait.speed = 1.6
		if not winner and not raid:
			view.modulate = Color(0.6, 0.6, 0.7)
		view.set_meta("side_index", i)
		_canvas.add_child(view)
		_views.append(view)


## Gọi trước khi GameState.add_exp để thanh EXP chạy từ giá trị cũ.
func run() -> void:
	_start_level = GameState.level
	_start_xp = GameState.xp
	_shown_level = _start_level
	_shown_xp = float(_start_xp)
	_remaining = float(exp_gain)
	_level_ups = GameState.add_exp(exp_gain)
	if raid:
		_sfx.play(&"whistle", -4.0)
	else:
		_sfx.play(&"confirm" if won else &"select")
	await _closed
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	var size: Vector2 = _canvas.size
	var s: float = clampf(size.y / 720.0, 0.6, 2.0) * (3.0)
	for view in _views:
		var i: int = int(view.get_meta("side_index"))
		var x: float = size.x * (0.17 if i == 0 else 0.83)
		if raid:
			x += (-1.0 if i == 0 else 1.0) * minf(_time * 40.0, size.x * 0.08)
		# Tỉ lệ nguyên pixel màn hình (đối thủ nhỏ hơn: ×0,8 → làm tròn; gà tre ×0,9) + vị trí bám pixel.
		var k: float = UISkin.crisp_scale(view, s * (1.0 if i == 0 else 0.8), UISkin.body_scale_of(view))
		view.scale = Vector2(k, k)
		view.position = UISkin.snap(view, Vector2(x, size.y * 0.66))
		view.modulate.a = clampf(_time / 0.4, 0.0, 1.0)
	if _time > 0.8 and _remaining > 0.0:
		var step: float = minf(_remaining, delta * 80.0)
		_remaining -= step
		_shown_xp += step
		var need: int = GameState.exp_to_next(_shown_level)
		if _shown_xp >= float(need) and _shown_level < GameState.LEVEL_CAP:
			_shown_xp -= float(need)
			_shown_level += 1
			_sfx.play(&"card")
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = (event as InputEventKey).physical_keycode
		if code == KEY_E or code == KEY_ENTER or code == KEY_SPACE or code == KEY_J:
			get_viewport().set_input_as_handled()
			if _remaining > 0.0:
				_shown_level = GameState.level
				_shown_xp = float(GameState.xp)
				_remaining = 0.0
			else:
				_closed.emit()


func _text(pos: Vector2, text: String, size: int, color: Color = Color.WHITE, bold: bool = false) -> void:
	UISkin.draw_text(_canvas, pos, text, size, color, bold, HORIZONTAL_ALIGNMENT_CENTER, _canvas.size.x, 6 if size >= 17 else 3,
		UISkin.SHADOW)


func _draw_screen() -> void:
	var w: float = _canvas.size.x
	var h: float = _canvas.size.y
	var appear: float = clampf(_time / 0.3, 0.0, 1.0)
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.05, 0.03, 0.02, 0.88 * appear))
	if raid:
		# Đèn công an quét hai bên.
		var swap: bool = int(_time * 3.0) % 2 == 0
		for k in range(8):
			var a: float = 0.08 * float(8 - k) / 8.0 * appear
			var e: float = float(k) * 14.0
			_canvas.draw_rect(Rect2(e, 0, 14, h), Color(0.95, 0.12, 0.12, a) if swap else Color(0.15, 0.35, 1.0, a))
			_canvas.draw_rect(Rect2(w - e - 14.0, 0, 14, h), Color(0.15, 0.35, 1.0, a) if swap else Color(0.95, 0.12, 0.12, a))
		var shake: float = sin(_time * 30.0) * 3.0 * maxf(0.0, 1.0 - _time)
		_text(Vector2(roundf(shake), h * 0.2), "CHẠY THÔI!", 66, Color(0.75, 0.85, 1.0).lerp(Color(1.0, 0.5, 0.45), 0.5 + 0.5 * sin(_time * 6.0)), true)
		_text(Vector2(0, h * 0.2 + 38.0), "Công an ập vào – sới giải tán, trận này không ai thắng.", UISkin.FS_BODY, Color(0.85, 0.88, 1.0))
	else:
		_text(Vector2(0, h * 0.22), "THẮNG!" if won else "THUA…", 66, Color(1.0, 0.85, 0.3) if won else Color(0.75, 0.8, 0.95), true)
	# Bảng kết quả: khung gỗ sẫm sau phần thưởng, EXP, Thể trạng.
	var y: float = roundf(h * 0.33)
	var panel_h: float = rewards.size() * 30.0 + 246.0
	UISkin.draw_panel(_canvas, Rect2(roundf(w * 0.5 - 300.0), y - 34.0, 600.0, panel_h), &"dark")
	for line in rewards:
		_text(Vector2(0, y), line, UISkin.FS_BODY, Color(1, 1, 1))
		y += 30.0
	y += 16.0
	_text(Vector2(0, y), "%s · Lv%d" % [_name, _shown_level], UISkin.FS_BODY, Color(1.0, 0.9, 0.6), true)
	var bar := Rect2(roundf(w * 0.5 - 220.0), y + 14.0, 440.0, 16.0)
	_canvas.draw_rect(bar.grow(3), Color(0, 0, 0, 0.8))
	var need: int = GameState.exp_to_next(_shown_level)
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_shown_xp / float(need), 0.0, 1.0), bar.size.y)),
		Color(0.45, 0.85, 0.35))
	_text(Vector2(0, y + 60.0), "EXP +%d   (%d / %d)" % [exp_gain, int(_shown_xp), need], UISkin.FS_BODY, Color(0.85, 0.95, 0.85))
	# Thể trạng trước → sau.
	var cy: float = y + 96.0
	var cbar := Rect2(roundf(w * 0.5 - 160.0), cy + 8.0, 320.0, 10.0)
	_canvas.draw_rect(cbar.grow(2), Color(0, 0, 0, 0.8))
	var after_w: float = cbar.size.x * _cond_after / GameState.CONDITION_MAX
	var before_w: float = cbar.size.x * _cond_before / GameState.CONDITION_MAX
	_canvas.draw_rect(Rect2(cbar.position, Vector2(before_w, cbar.size.y)), Color(0.85, 0.3, 0.2, 0.55 + 0.35 * sin(_time * 5.0)))
	_canvas.draw_rect(Rect2(cbar.position, Vector2(after_w, cbar.size.y)), Color(0.35, 0.8, 0.4))
	var cond_text: String = "Thể trạng %d%%" % int(round(_cond_after))
	if _cond_after < _cond_before - 0.01:
		cond_text = "Thể trạng %d%% → %d%%  (thua trận)" % [int(round(_cond_before)), int(round(_cond_after))]
	if _cond_after < GameState.CONDITION_WEAK:
		cond_text += " · gà yếu: cho ăn, cho ngủ!"
	_text(Vector2(0, cy), cond_text, UISkin.FS_BODY, Color(0.9, 0.9, 0.85))
	if _shown_level > _start_level:
		var pulse: float = 0.8 + 0.2 * sin(_time * 8.0)
		_text(Vector2(0, cy + 56.0), "LÊN CẤP %d!  HP và ATK tăng" % _shown_level, UISkin.FS_BODY, Color(1.0, 0.85, 0.3, pulse), true)
	if _remaining <= 0.0:
		_text(Vector2(0, h - 36.0), "[E] tiếp tục ▼", UISkin.FS_BODY, Color(0.8, 0.76, 0.66))
