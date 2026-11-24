extends CanvasLayer

## Thông báo "Thành tựu mới!" trượt vào từ mép phải, ngay dưới biển đồng hồ (kèm tiếng levelup) – không che bảng
## trạng thái (trái) hay tiêu đề màn hình (giữa). Nghe Achievements.add_listener;
## nhiều thành tựu cùng lúc thì xếp hàng lần lượt. main.gd tạo một lần.
## Dùng: const AchievementToast := preload("res://game/ui/achievement_toast.gd")

const Audio := preload("res://game/audio/audio_director.gd")

const SHOW_TIME: float = 3.2
const SLIDE_TIME: float = 0.35
const WIDTH: float = 440.0
const HEIGHT: float = 76.0
## Mép trên (dưới biển đồng hồ góc phải).
const TOP: float = 104.0

## Hàng chờ (id thành tựu) – test đọc.
var queue: Array[StringName] = []
## Thành tựu đang hiện (&"" = không có).
var current: StringName = &""
var _t: float = 0.0
var _canvas: Control


func _ready() -> void:
	layer = 85
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_toast)
	UISkin.pixel(_canvas)
	add_child(_canvas)
	Achievements.add_listener(_on_unlocked)


func _exit_tree() -> void:
	Achievements.remove_listener(_on_unlocked)


func _on_unlocked(id: StringName) -> void:
	queue.append(id)


func is_showing() -> bool:
	return current != &""


func _process(delta: float) -> void:
	if current == &"" and not queue.is_empty():
		current = queue.pop_front()
		_t = 0.0
		Audio.sfx(&"levelup", -4.0)
	if current == &"":
		return
	_t += delta
	if _t >= SHOW_TIME + SLIDE_TIME * 2.0:
		current = &""
	_canvas.queue_redraw()


func _draw_toast() -> void:
	if current == &"":
		return
	var a: Dictionary = Achievements.info(current)
	var k: float = 1.0
	if _t < SLIDE_TIME:
		k = _t / SLIDE_TIME
	elif _t > SHOW_TIME + SLIDE_TIME:
		k = 1.0 - (_t - SHOW_TIME - SLIDE_TIME) / SLIDE_TIME
	k = clampf(k, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 3.0)
	var view: Vector2 = _canvas.size
	var r := Rect2(Vector2(view.x - (WIDTH + 12.0) * k, TOP), Vector2(WIDTH, HEIGHT))
	r.position = r.position.round()
	UISkin.draw_panel(_canvas, r, &"toast")
	var frame: String = "node_secret" if bool(a.get("secret", false)) else ("node_goal" if a.get("frame", &"") == &"goal" else "node_open")
	var node := Rect2(r.position + Vector2(16, 16), Vector2(44, 44))
	_canvas.draw_texture_rect(UISkin.texture(frame), node, false)
	UISkin.draw_icon(_canvas, a.get("icon", &"star"), node.get_center(), 1.0)
	var sparkle: float = 0.75 + 0.25 * sin(_t * 10.0)
	UISkin.draw_text(_canvas, Vector2(r.position.x + 74, r.position.y + 32), "Thành tựu mới!", UISkin.FS_SMALL,
		Color(UISkin.GOLD, sparkle), true, HORIZONTAL_ALIGNMENT_LEFT, -1, 4, UISkin.SHADOW)
	UISkin.draw_text(_canvas, Vector2(r.position.x + 74, r.position.y + 62), String(a.get("title", "")), UISkin.FS_BODY,
		UISkin.CREAM, false, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 90.0, 4, UISkin.SHADOW)
