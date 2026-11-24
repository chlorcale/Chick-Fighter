extends Node2D

## Một người nhà (Mẹ / Ba / em trai) đi lại trong nhà theo lịch sinh hoạt từng buổi (home_layout.gd ROUTINES):
## đi tới chỗ làm việc theo đường A* (home_nav.gd), đứng đó quay mặt vào đồ vật một lúc rồi đi chỗ kế (xoay vòng).
## Gặp người chơi / người nhà khác chắn đường: đứng chờ, chờ lâu thì tìm đường vòng (coi chỗ người kia đứng là đặc).
## Đang nói chuyện (begin_talk) thì đứng lại, quay mặt về người chơi. Sprite: sheet 20 khung cùng bố cục với
## nhân vật chính (tools/art/build_family.py), hoạt ảnh/thời lượng theo WorldPlayer.ANIMS; gốc toạ độ = chân.
## Node gốc phóng Layout.NPC_SCALE (cùng cỡ người chơi trong nhà).

const Layout := preload("res://game/home/home_layout.gd")
const HomeNav := preload("res://game/home/home_nav.gd")

## Tốc độ đi (px thế giới nhà / s) theo người – chậm hơn người chơi (WorldPlayer.WALK_SPEED 80).
const SPEED: Dictionary = {&"me": 34.0, &"cha": 28.0, &"em": 40.0}
## Đứng chờ bao lâu thì tìm đường vòng; chờ quá lâu thì bỏ qua chỗ này, đi chỗ kế.
const WAIT_REROUTE: float = 0.8
const WAIT_GIVE_UP: float = 6.0
## Nửa bề ngang / chiều cao vùng chân (va chạm với người chơi & người nhà khác).
const BODY_HALF: int = 6
const BODY_H: int = 5

var who: StringName = &""
var home: Node                      # HomeScene: player, nav, family_blockers(self)
var nav: HomeNav
var talking: bool = false
var facing: Vector2i = Vector2i(0, 1)
## Ô lịch đang làm: [spot id, giây] ; spot = Layout.SPOTS[id] = [chân, hướng nhìn].
var routine: Array = []
var step_index: int = 0
var state: StringName = &"idle"     # idle (đứng làm việc) / walk / wait
var activity_left: float = 0.0
var visited: Array[StringName] = []  # các chỗ đã tới (test đọc)

var _sprite: Sprite2D
var _shadow: Sprite2D
var _anim: String = "idle"
var _anim_frame: int = 0
var _anim_time: float = 0.0
var _path: Array[Vector2i] = []
var _goal: Vector2 = Vector2.ZERO
var _wait: float = 0.0
var _wait_total: float = 0.0
var _talk_prev_facing: Vector2i = Vector2i(0, 1)


func setup(p_who: StringName, p_home: Node, p_nav: HomeNav, sheet: Texture2D, p_routine: Array, start_step: int) -> void:
	who = p_who
	home = p_home
	nav = p_nav
	name = "npc_" + String(who)
	scale = Vector2(Layout.NPC_SCALE, Layout.NPC_SCALE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow = Sprite2D.new()
	_shadow.name = "Shadow"
	_shadow.texture = WorldPlayer.SHADOW_SHEET
	_shadow.centered = false
	_shadow.region_enabled = true
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.name = "Body"
	_sprite.texture = sheet
	_sprite.centered = false
	_sprite.region_enabled = true
	add_child(_sprite)
	# lệch pha nhịp thở/chớp mắt giữa các người
	_anim_time = float(absi(String(who).hash()) % 40) / 100.0
	set_routine(p_routine, start_step, true)


## Đổi lịch (sang buổi khác). place = đặt ngay tại chỗ làm việc đầu tiên (mới vô nhà / mới xuất hiện).
func set_routine(p_routine: Array, start_step: int, place: bool) -> void:
	routine = p_routine
	step_index = clampi(start_step, 0, maxi(routine.size() - 1, 0))
	if routine.is_empty():
		return
	if place:
		position = stand_point(StringName(routine[step_index][0]))
		_arrive()
	else:
		_go_to_step(step_index)


## Chỗ đứng thật của một chỗ làm việc: tâm ô lưới gần chỗ đó nhất (người nhà chỉ đứng ở tâm ô / giữa hai tâm ô kề).
func stand_point(spot_id: StringName) -> Vector2:
	var feet: Vector2 = Layout.SPOTS[spot_id][0]
	if nav == null:
		return feet
	var cell: Vector2i = nav.nearest_walkable(feet)
	return nav.center_of(cell) if cell.x >= 0 else feet


func current_spot() -> StringName:
	return StringName(routine[step_index][0]) if not routine.is_empty() else &""


func is_walking() -> bool:
	return state == &"walk" or state == &"wait"


## Vùng chân (thế giới nhà) – người chơi không đi xuyên qua.
func block_rect() -> Rect2i:
	return Rect2i(int(position.x) - BODY_HALF, int(position.y) - BODY_H + 1, BODY_HALF * 2, BODY_H)


func begin_talk(toward: Vector2) -> void:
	talking = true
	_talk_prev_facing = facing
	var d: Vector2 = toward - position
	if absf(d.x) > absf(d.y):
		facing = Vector2i(signi(int(d.x)), 0)
	else:
		facing = Vector2i(0, 1 if d.y >= 0.0 else -1)
	if facing == Vector2i.ZERO:
		facing = Vector2i(0, 1)
	_set_anim("idle")
	_apply_frame()


func end_talk() -> void:
	talking = false
	if state == &"idle":
		facing = _talk_prev_facing
	_apply_frame()


func _physics_process(delta: float) -> void:
	tick(delta)


## Một bước mô phỏng (test có thể gọi thẳng để tua nhanh).
func tick(delta: float) -> void:
	if routine.is_empty():
		_advance_anim(delta)
		return
	if talking:
		_set_anim("idle")
		_advance_anim(delta)
		return
	match state:
		&"idle":
			_set_anim("idle")
			activity_left -= delta
			if activity_left <= 0.0 and routine.size() > 1:
				_go_to_step((step_index + 1) % routine.size())
		&"walk", &"wait":
			_walk(delta)
	_advance_anim(delta)


func _go_to_step(i: int) -> void:
	step_index = i
	_goal = stand_point(StringName(routine[i][0]))
	_path = nav.find_path(position, _goal) if nav != null else []
	_wait = 0.0
	_wait_total = 0.0
	if _path.is_empty():
		# không có đường (bị chắn kín): đứng chờ, lát thử lại
		state = &"wait"
		return
	if nav.center_of(_path[0]).distance_to(position) < 0.5:
		_path.remove_at(0)
	state = &"walk"


## Điểm đến kế tiếp: tâm ô kế trên đường, hết đường thì đúng chỗ làm việc.
func _next_point() -> Vector2:
	return nav.center_of(_path[0]) if not _path.is_empty() else _goal


func _walk(delta: float) -> void:
	if _path.is_empty() and position != _goal:
		# chưa có đường: chờ rồi tìm lại (không bao giờ đi thẳng xuyên tường)
		state = &"wait"
		_set_anim("idle")
		_wait += delta
		_wait_total += delta
		if _wait_total >= WAIT_GIVE_UP:
			state = &"idle"
			activity_left = 2.0
		elif _wait >= WAIT_REROUTE:
			_wait = 0.0
			_reroute()
		return
	var target: Vector2 = _next_point()
	var d: Vector2 = target - position
	# tới (gần đúng) điểm kế: chốt đúng toạ độ để không trôi số lẻ
	if absf(d.x) < 0.01:
		position.x = target.x
		d.x = 0.0
	if absf(d.y) < 0.01:
		position.y = target.y
		d.y = 0.0
	if d == Vector2.ZERO:
		if _path.is_empty():
			_arrive()
			return
		_path.remove_at(0)
		return
	# đi theo trục như người chơi – không đi chéo (các điểm kế luôn cùng hàng/cột với chỗ đang đứng)
	var dir := Vector2i(1 if d.x > 0.0 else -1, 0) if d.x != 0.0 else Vector2i(0, 1 if d.y > 0.0 else -1)
	facing = dir
	var step: float = minf(float(SPEED.get(who, 32.0)) * delta, absf(d.x) if dir.x != 0 else absf(d.y))
	var next: Vector2 = position + Vector2(dir) * step
	if home != null and home.call("npc_path_blocked", self, next):
		state = &"wait"
		_set_anim("idle")
		_wait += delta
		_wait_total += delta
		if _wait_total >= WAIT_GIVE_UP:
			# kẹt lâu: bỏ chỗ này, đứng làm việc tại chỗ rồi đi chỗ kế
			_path.clear()
			state = &"idle"
			activity_left = 2.0
		elif _wait >= WAIT_REROUTE:
			_wait = 0.0
			_reroute()
		return
	state = &"walk"
	_wait = 0.0
	position = next
	_set_anim({Vector2i(0, -1): "walk_up", Vector2i(0, 1): "walk_down", Vector2i(-1, 0): "walk_left", Vector2i(1, 0): "walk_right"}[dir])


## Tìm đường vòng: các ô người chơi / người nhà khác đang đứng (và ô kề) coi như đặc.
func _reroute() -> void:
	var avoid: Array[Vector2i] = []
	if home != null:
		for p in home.call("family_obstacles", self):
			var c: Vector2i = nav.cell_of(p)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					avoid.append(Vector2i(c.x + dx, c.y + dy))
	# bắt đầu lại từ ô gần nhất (đang ở giữa hai tâm ô kề nhau → một trong hai đầu đoạn)
	var path: Array[Vector2i] = nav.find_path(position, _goal, avoid)
	if not path.is_empty():
		_path = path
		if nav.center_of(_path[0]).distance_to(position) < 0.5:
			_path.remove_at(0)


func _arrive() -> void:
	var entry: Array = routine[step_index]
	var spot: Array = Layout.SPOTS[StringName(entry[0])]
	position = stand_point(StringName(entry[0]))
	facing = spot[1]
	state = &"idle"
	_path.clear()
	# thời gian đứng làm việc: theo lịch ± chút xíu (tất định theo người + chỗ)
	var jitter: float = float(absi((String(who) + String(entry[0])).hash()) % 30) / 10.0 - 1.5
	activity_left = maxf(2.0, float(entry[1]) + jitter)
	if not visited.has(StringName(entry[0])):
		visited.append(StringName(entry[0]))
	_set_anim("idle")
	_apply_frame()


# ------------------------------------------------------------------ hoạt ảnh (giống WorldPlayer)

func _set_anim(anim_name: String) -> void:
	if _anim == anim_name:
		return
	_anim = anim_name
	_anim_frame = 0
	_anim_time = 0.0
	_apply_frame()


func _advance_anim(delta: float) -> void:
	var data: Array = WorldPlayer.ANIMS[_anim]
	_anim_time += delta
	var duration: float = data[2][_anim_frame]
	if _anim_time >= duration:
		_anim_time -= duration
		_anim_frame = (_anim_frame + 1) % int(data[1])
		_apply_frame()


func frame_index() -> int:
	if _anim == "idle" and WorldPlayer.IDLE_HOLD.has(facing):
		return int(WorldPlayer.IDLE_HOLD[facing])
	return int(WorldPlayer.ANIMS[_anim][0]) + _anim_frame


func anim_name() -> String:
	return _anim


func _apply_frame() -> void:
	if _sprite == null:
		return
	var f: int = WorldPlayer.FRAME_SIZE
	_sprite.region_rect = Rect2(frame_index() * f, 0, f, f)
	_sprite.position = -WorldPlayer.FOOT_IN_FRAME
	_shadow.region_rect = _sprite.region_rect
	_shadow.position = _sprite.position
