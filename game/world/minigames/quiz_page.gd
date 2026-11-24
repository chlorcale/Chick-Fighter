extends "res://game/world/minigames/minigame.gd"

## TRANG LỚP HỌC (trường làng – cô Hạnh đố 3 câu; THPT – thầy Khoa 2 tiết × 2 câu): tường vàng, bảng xanh, băng rôn
## "Tiên học lễ – Hậu học văn", cửa sổ song sắt nắng chiếu, quạt trần, bạn học ngồi bàn gỗ.
## Câu hỏi viết phấn lên bảng, 4 thẻ đáp án dán trên bảng (2×2): W/A/S/D chọn, E trả lời; thầy cô giải thích,
## E đi tiếp. Dữ liệu câu hỏi: SchoolQuiz.build() / ClassQuiz.build() (đáp án đã xáo, kèm chỉ số đúng).
## current_answer: chỉ số đáp án đúng của câu đang hỏi (−1 khi không hỏi) – test/autopilot đọc để trả lời.
## Kết quả: {right, total, cancelled}.

const BOARD: Rect2 = Rect2(84, 18, 216, 100)
const CARDS: Array[Vector2] = [Vector2(90, 70), Vector2(194, 70), Vector2(90, 94), Vector2(194, 94)]
const CARD_SIZE: Vector2 = Vector2(100, 18)
const CHALK: Color = Color(0.95, 0.96, 0.9)

var teacher: String = "Cô Hạnh"
var teacher_sprite: String = "lady"
var title: String = "TRƯỜNG LÀNG – CÔ HẠNH ĐỐ BÀI"
var intro_text: String = ""
var questions: Array = []
var current_answer: int = -1

var _index: int = -1
var _sel: int = 0
var _answered: int = -1   # lựa chọn đã trả lời (−1 = đang hỏi)
var _right: int = 0
var _wait: float = 0.0
var _time: float = 0.0
var _teacher: Sprite2D
var _fan: Sprite2D
var _hero: Sprite2D
var _hand: Sprite2D
var _marks: Node2D
var _q_label: Label
var _head_label: Label
var _banner: Label
var _card_labels: Array[Label] = []
var _bubble: PanelContainer
var _bubble_text: Label
var _bubble_name: Label
var _hand_t: float = 0.0


func setup_school(list: Array) -> void:
	questions = list
	teacher = "Cô Hạnh"
	teacher_sprite = "lady"
	title = "TRƯỜNG LÀNG – CÔ HẠNH ĐỐ BÀI"
	intro_text = "Cô Hạnh đố %d câu, trả lời đúng cô thưởng!\n\n[W]/[A]/[S]/[D] chọn thẻ đáp án trên bảng, [E] trả lời.\nNghe cô giải thích xong thì [E] qua câu kế." % list.size()


func setup_class(plan: Dictionary) -> void:
	questions = plan["questions"]
	teacher = "Thầy Khoa"
	teacher_sprite = "chu_tu"
	var subjects: Array = plan["subjects"]
	title = "LỚP 10A – THPT BÌNH KÊ"
	intro_text = "Hai tiết sáng nay: %s và %s. Thầy Khoa gọi lên bảng trả bài!\n\n[W]/[A]/[S]/[D] chọn thẻ đáp án, [E] trả lời. Mỗi câu đúng +2 Technology.\nNghe thầy giải thích xong thì [E] qua câu kế." % [subjects[0], subjects[1]]


func _page() -> String:
	return "class"


func _intro() -> Array:
	return [title, intro_text]


func _hint_text() -> String:
	return "[W][A][S][D] Chọn đáp án   ·   [E] Trả lời   ·   [Esc] Nghỉ"


func _music() -> StringName:
	return &"-"


func _ambience() -> Dictionary:
	return {&"birds": 0.35, &"leaves": 0.15, &"village": 0.1}


func _build() -> void:
	backdrop("bg")
	_fan = sprite(frame("fan", 2, 0), Vector2(36, 12), -5)
	_teacher = sprite(npc_texture(teacher_sprite), Vector2(334, 150), -4)
	_teacher.flip_h = true
	# bạn học: hai dãy, quay lưng lên bảng
	var kid_rows: Array = [[176.0, [44.0, 96.0, 148.0, 244.0, 296.0, 348.0]], [204.0, [22.0, 76.0, 130.0, 254.0, 310.0, 364.0]]]
	var k: int = 0
	for row in kid_rows:
		for x in row[1]:
			sprite(frame("kids", 4, (k * 7 + 3) % 4), Vector2(float(x), float(row[0]) + 2.0), 0)
			k += 1
	_hero = hero_sprite(Vector2(194, 222), 8, 1)
	_hand = sprite(tex("kid_hand"), Vector2(196, 206), 1)
	_hand.visible = false
	sprite(tex("desks"), Vector2(0, 216), 3).offset = Vector2(0, -216)
	_marks = Node2D.new()
	_marks.z_index = 4
	_marks.draw.connect(_draw_marks)
	add_child(_marks)
	_banner = make_label(UISkin.FS_BODY, Color(1.0, 0.9, 0.45), true)
	_banner.text = "TIÊN HỌC LỄ  –  HẬU HỌC VĂN"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.add_child(_banner)
	_head_label = make_label(UISkin.FS_BODY, Color(1.0, 0.9, 0.55), true)
	_head_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(_head_label)
	_q_label = make_label(UISkin.FS_BODY, CHALK, true)
	_q_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.add_child(_q_label)
	for i in range(4):
		var l := make_label(UISkin.FS_BODY, INK, true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = false
		ui.add_child(l)
		_card_labels.append(l)
	for n in [_banner, _head_label, _q_label]:
		ui.move_child(n, 0)
	for l in _card_labels:
		ui.move_child(l, 0)
	_bubble = make_panel()
	_bubble.custom_minimum_size = Vector2(430, 0)
	_bubble.position = Vector2(14, 452)
	ui.add_child(_bubble)
	var box := VBoxContainer.new()
	_bubble.add_child(box)
	_bubble_name = make_label(UISkin.FS_BODY, Color(0.55, 0.2, 0.08), true)
	_bubble_name.text = teacher
	box.add_child(_bubble_name)
	_bubble_text = make_label(UISkin.FS_BODY, INK)
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.custom_minimum_size = Vector2(400, 0)
	box.add_child(_bubble_text)
	_bubble.visible = false
	_set_board_visible(false)


func _set_board_visible(on: bool) -> void:
	_q_label.visible = on
	_head_label.visible = on
	for l in _card_labels:
		l.visible = on


func _wants(action: StringName) -> bool:
	return action in [&"confirm", &"cancel", &"up", &"down", &"left", &"right"]


func _start() -> void:
	use_timer(false)
	sfx(&"school_bell", -6.0)
	_next_question()


func _next_question() -> void:
	_index += 1
	if _index >= questions.size():
		current_answer = -1
		finish({"right": _right, "total": questions.size()}, 0.3)
		return
	var q: Dictionary = questions[_index]
	if _index > 0 and String(q.get("subject", "")) != String(questions[_index - 1].get("subject", "")):
		toast(String(q["header"]), Color(1.0, 0.92, 0.5))
		sfx(&"school_bell", -8.0)
	current_answer = int(q["correct"])
	_answered = -1
	_sel = 0
	_wait = 0.0
	_bubble.visible = false
	_q_label.text = String(q["q"])
	_head_label.text = String(q.get("header", ""))
	var answers: Array = q["answers"]
	for i in range(4):
		_card_labels[i].text = "%s. %s" % [["A", "B", "C", "D"][i], answers[i]] if i < answers.size() else ""
	_set_board_visible(true)
	_update_status()


func _on_action(action: StringName) -> void:
	if _answered >= 0:
		if action == &"confirm" and _wait >= 0.4:
			sfx(&"ui_confirm", -8.0)
			_next_question()
		return
	match action:
		&"left", &"right":
			_sel = _sel ^ 1
			sfx(&"ui_move", -10.0)
		&"up", &"down":
			_sel = _sel ^ 2
			sfx(&"ui_move", -10.0)
		&"confirm":
			_answer(_sel)


func _answer(pick: int) -> void:
	var q: Dictionary = questions[_index]
	_answered = pick
	_wait = 0.0
	_hand_t = 1.2
	var answers: Array = q["answers"]
	_bubble_name.text = "%s – %s" % [teacher, "Đúng rồi!" if pick == current_answer else "Chưa đúng…"]
	_bubble_name.add_theme_color_override("font_color", GOOD if pick == current_answer else BAD)
	if pick == current_answer:
		_right += 1
		_bubble_text.text = "%s %s" % [String(q.get("praise", "Đúng rồi!")), String(q["why"])]
		sfx(&"coin", -8.0)
	else:
		_bubble_text.text = "Chưa đúng rồi. Đáp án là: %s. %s" % [String(answers[current_answer]), String(q["why"])]
		sound(&"miss")
	_bubble.visible = true
	_update_status()


func _cancel_result() -> Dictionary:
	return {"cancelled": true, "right": _right, "total": questions.size()}


func _result_info(r: Dictionary) -> Array:
	var right: int = int(r.get("right", 0))
	var total: int = int(r.get("total", 0))
	var text: String = "Trả lời đúng %d/%d câu." % [right, total]
	if right >= total:
		return ["ĐÚNG HẾT TRƠN!", text + "\nCả lớp vỗ tay rần rần!", true]
	return ["HẾT GIỜ HỌC!", text, right > 0]


func _update_status() -> void:
	set_status("Câu %d/%d   ·   Đúng: %d" % [mini(_index + 1, questions.size()), questions.size(), _right])


func _tick(delta: float) -> void:
	_wait += delta
	if not autopilot:
		return
	if _answered < 0 and _wait >= 0.3:
		if _sel != current_answer:
			_sel = current_answer
		press(&"confirm")
	elif _answered >= 0 and _wait >= 0.5:
		press(&"confirm")


func _animate(delta: float) -> void:
	_time += delta
	_fan.texture = frame("fan", 2, int(_time * 10.0) % 2)
	_teacher.position.y = 150.0 - (1.0 if int(_time * 1.4) % 2 == 0 else 0.0)
	_hand_t = maxf(_hand_t - delta, 0.0)
	_hand.visible = _hand_t > 0.0
	_hero.visible = not _hand.visible
	_place_labels()
	_marks.queue_redraw()


func _place_labels() -> void:
	var z: float = view_zoom()
	_banner.position = to_screen(Vector2(96, 0))
	_banner.size = Vector2(192, 12) * z
	# bảng tên trò (HUD góc trái) che đầu băng rôn: dồn chữ vào phần băng rôn còn thấy
	var hud_right: float = top_panel.get_rect().end.x + 8.0 if top_panel != null and top_panel.visible else 0.0
	if _banner.position.x < hud_right:
		_banner.size.x = maxf(_banner.size.x - (hud_right - _banner.position.x), 0.0)
		_banner.position.x = hud_right
	_head_label.position = to_screen(BOARD.position + Vector2(6, 2))
	_head_label.size = Vector2(BOARD.size.x - 12, 9) * z
	_q_label.position = to_screen(BOARD.position + Vector2(6, 11))
	_q_label.size = Vector2(BOARD.size.x - 12, 46) * z
	for i in range(4):
		_card_labels[i].position = to_screen(CARDS[i] + Vector2(2, 0))
		_card_labels[i].size = (CARD_SIZE - Vector2(4, 2)) * z


func _draw_marks() -> void:
	if not running or _index < 0 or _index >= questions.size():
		return
	var card: Texture2D = tex("card")
	for i in range(4):
		var p: Vector2 = CARDS[i]
		var tint := Color.WHITE
		if _answered >= 0:
			if i == current_answer:
				tint = Color(0.75, 1.0, 0.7)
			elif i == _answered:
				tint = Color(1.0, 0.7, 0.65)
			else:
				tint = Color(0.8, 0.8, 0.78)
		if card != null:
			_marks.draw_texture(card, p - Vector2(1, 1), tint)
		else:
			_marks.draw_rect(Rect2(p, CARD_SIZE), tint)
	var s: Vector2 = CARDS[_sel if _answered < 0 else _answered]
	var pulse: float = 0.6 + 0.4 * sin(_time * 8.0)
	var sel_c := Color(1.0, 0.85, 0.3, pulse) if _answered < 0 else (Color(0.4, 0.9, 0.35) if _answered == current_answer else Color(0.95, 0.3, 0.2))
	_marks.draw_rect(Rect2(s - Vector2(3, 3), CARD_SIZE + Vector2(6, 6)), sel_c, false, 2.0)
	if _answered >= 0:
		# dấu phấn ✓ / ✗ bên phải thẻ
		var m: Vector2 = s + Vector2(CARD_SIZE.x - 10, 3)
		if _answered == current_answer:
			_marks.draw_polyline(PackedVector2Array([m + Vector2(0, 6), m + Vector2(3, 10), m + Vector2(9, 0)]), Color(0.2, 0.6, 0.15), 2.0)
		else:
			_marks.draw_line(m, m + Vector2(8, 10), Color(0.8, 0.15, 0.1), 2.0)
			_marks.draw_line(m + Vector2(8, 0), m + Vector2(0, 10), Color(0.8, 0.15, 0.1), 2.0)


func _cleanup() -> void:
	_set_board_visible(false)
	_bubble.visible = false
	current_answer = -1
