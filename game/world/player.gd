class_name WorldPlayer
extends Node2D

## Nhân vật chính ở chế độ khám phá (top-down).
## Chỉ đi 4 hướng lên/xuống/trái/phải, không đi chéo; bị chặn bởi World.is_blocked().
## Sprite bản mới xuất từ truongcon_stardew.aseprite (tools/art/build_player.py → player_sheet_v2.png): đã vẽ đúng cỡ
## NPC bản đồ (~43 px) và có viền sẵn nên vẽ ×1,0, không dùng shader viền; bóng đổ (layer "Bong") là sprite riêng
## nằm dưới. Có thể chạy xe máy (nhanh hơn).

const SHEET: Texture2D = preload("res://game/art/player_sheet_v2.png")
## Bóng đổ (layer "Bong"), cùng lưới khung với SHEET.
const SHADOW_SHEET: Texture2D = preload("res://game/art/player_sheet_v2_shadow.png")
const BIKE_SIDE: Texture2D = preload("res://game/art/bike_side.png")
const BIKE_SIDE_B: Texture2D = preload("res://game/art/bike_side_b.png") # khung nan hoa thứ hai
const BIKE_FRONT: Texture2D = preload("res://game/art/bike_front.png")
const BIKE_BACK: Texture2D = preload("res://game/art/bike_back.png")
const BIKE_PARKED: Texture2D = preload("res://game/art/bike_parked.png") # xe đỗ, không có chân người
## Người lái ngồi trên xe (ảnh ghép người + xe, cao RIDE_HEIGHT, mép dưới = mặt đất), vẽ bằng
## tools/art/build_dream_bike.py. Ngang: hai khung nan hoa A/B, quay phải (lật để quay trái).
const RIDE_SIDE_A: Texture2D = preload("res://game/art/bike_ride_side.png")
const RIDE_SIDE_B: Texture2D = preload("res://game/art/bike_ride_side_b.png")
const RIDE_FRONT: Texture2D = preload("res://game/art/bike_ride_front.png")
const RIDE_BACK: Texture2D = preload("res://game/art/bike_ride_back.png")
const RIDE_HEIGHT: int = 60
const Audio := preload("res://game/audio/audio_director.gd")
const FRAME_SIZE: int = 64
## Art mới đã cùng cỡ NPC bản đồ → vẽ ×1,0 (sheet cũ cần ×0,8).
const SPRITE_SCALE: float = 1.0
## Gốc toạ độ (giữa hai bàn chân, ngay dưới hàng viền chân thấp nhất) trong ô 64×64.
const FOOT_IN_FRAME: Vector2 = Vector2(32, 58)
const WALK_SPEED: float = 80.0 # px/s
const BIKE_SPEED: float = 210.0
const FOOT_HALF_WIDTH: int = 5
const FOOT_HEIGHT: int = 5

## [khung đầu, số khung, thời lượng mỗi khung (s)] theo tag + thời lượng khung trong file Aseprite
## (player_sheet_v2.json; idle có nhịp thở + chớp mắt ở khung thứ 3). Test so khớp với JSON.
const ANIMS: Dictionary = {
	"idle": [0, 4, [0.45, 0.3, 0.11, 0.45]],
	"walk_down": [4, 4, [0.14, 0.14, 0.14, 0.14]],
	"walk_up": [8, 4, [0.14, 0.14, 0.14, 0.14]],
	"walk_left": [12, 4, [0.14, 0.14, 0.14, 0.14]],
	"walk_right": [16, 4, [0.14, 0.14, 0.14, 0.14]],
}
## Khung chạm đất trong chu kỳ đi (khung 1 và 3 của tag – hai chân dang rộng) → phát tiếng bước chân.
const STEP_FRAMES: Array[int] = [0, 2]
## Đứng yên quay lưng/quay ngang: art chỉ có idle nhìn thẳng → giữ khung chụm chân của tag đi theo hướng đó.
const IDLE_HOLD: Dictionary = {Vector2i(0, -1): 9, Vector2i(-1, 0): 13, Vector2i(1, 0): 17}
const DIRECTIONS: Array = [
	[Vector2i(0, -1), "walk_up", [&"p1_jump", &"p2_jump"]],
	[Vector2i(0, 1), "walk_down", [&"p1_crouch", &"p2_crouch"]],
	[Vector2i(-1, 0), "walk_left", [&"p1_left", &"p2_left"]],
	[Vector2i(1, 0), "walk_right", [&"p1_right", &"p2_right"]],
]

var world: Node
var can_move: bool = true
var riding: bool = false
var facing: Vector2i = Vector2i(0, 1)

var _sprite: Sprite2D
var _shadow: Sprite2D
var _bike: Sprite2D
var _anim: String = "idle"
var _anim_frame: int = 0
var _anim_time: float = 0.0
var _held_order: Array[int] = [] # chỉ số hướng, phím nhấn sau cùng nằm cuối
var _remainder: float = 0.0
var _smoke: ExhaustSmoke
var _smoke_timer: float = 0.0
var _wheel_time: float = 0.0
## Lắc lư trên cầu khỉ / cầu ván hẹp (World.set_wobble mỗi frame) và cúi đầu khi vỏ lãi chui dưới cầu – chỉ đổi hình.
var _wobble_amp: float = 0.0
var _wobble_phase: float = 0.0
var _duck: bool = false
var _base_sprite_pos: Vector2 = Vector2.ZERO
var _base_bike_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_smoke = ExhaustSmoke.new() # con đầu tiên: khói vẽ dưới xe
	add_child(_smoke)
	_shadow = Sprite2D.new() # bóng đổ dưới chân (ẩn khi chạy xe – ảnh xe có bóng riêng)
	_shadow.name = "Shadow"
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow.texture = SHADOW_SHEET
	_shadow.centered = false
	_shadow.region_enabled = true
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.name = "Body"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = SHEET
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(_sprite)
	_bike = Sprite2D.new() # ảnh ghép người + xe khi đang chạy xe (đã có viền sẵn)
	_bike.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bike.centered = false
	_bike.visible = false
	add_child(_bike)
	_apply_frame()


func set_riding(value: bool) -> void:
	if value != riding:
		Audio.sfx(&"bike_start" if value else &"bike_stop", -4.0)
		if not value:
			Audio.engine(false)
	riding = value
	_bike.visible = value
	_sprite.visible = not value
	_wheel_time = 0.0
	_apply_frame()


func _physics_process(delta: float) -> void:
	var direction_index: int = _read_direction() if can_move else -1
	if direction_index < 0:
		_held_order.clear()
		_remainder = 0.0
		_set_anim("idle")
	else:
		var entry: Array = DIRECTIONS[direction_index]
		facing = entry[0]
		_set_anim(String(entry[1]))
		_remainder += (BIKE_SPEED if riding else WALK_SPEED) * delta
		var steps: int = int(_remainder)
		_remainder -= float(steps)
		var step: Vector2i = entry[0]
		for i in range(steps):
			var next: Vector2 = position + Vector2(step)
			if _blocked_at(next):
				break
			position = next
	_advance_anim(delta)
	_update_bike_fx(delta, direction_index >= 0)
	if riding:
		Audio.engine(true, 1.0 if direction_index >= 0 else 0.0) # tiếng máy theo tay ga


## Nan hoa quay (xe ngang) và khói ống xả khi đang ngồi trên xe.
func _update_bike_fx(delta: float, moving: bool) -> void:
	if not riding:
		return
	if moving and (_anim == "walk_left" or _anim == "walk_right"):
		_wheel_time += delta
		_bike.texture = RIDE_SIDE_B if int(_wheel_time / 0.06) % 2 == 1 else RIDE_SIDE_A
	_smoke_timer -= delta
	if _smoke_timer > 0.0:
		return
	_smoke_timer = 0.09 if moving else 0.7
	var tip: Vector2
	var drift: Vector2
	match _anim:
		"walk_left":
			tip = Vector2(29, -14)
			drift = Vector2(14, -7)
		"walk_right":
			tip = Vector2(-29, -14)
			drift = Vector2(-14, -7)
		"walk_up":
			tip = Vector2(7, -8)
			drift = Vector2(2, 12)
		_:
			return # nhìn xuống: ống xả khuất sau xe
	if not moving:
		drift *= 0.4
	_smoke.emit(global_position + tip, drift)


## Xe đỗ (không người): Node2D gốc ở điểm chạm đất, chứa sprite xe ngang có viền.
static func make_parked_bike() -> Node2D:
	var root := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.texture = BIKE_PARKED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.position = Vector2(-34, -42)
	root.add_child(sprite)
	return root


## Nhân vật ngồi trên xe Dream nhìn ngang, quay phải (dùng cho mini-game đua xe).
## Gốc toạ độ = điểm chạm đất dưới tâm xe; ảnh 68x60 (RIDE_HEIGHT) nằm trong x -34..34, y -60..0,
## bánh sau tâm (-20, -11), bánh trước tâm (20, -11), bán kính ~10. Lọc NEAREST, viền có sẵn.
## Con duy nhất là Sprite2D tên "Bike": đổi bánh xe bằng set_rider_wheel_frame(node, i) hoặc gán
## trực tiếp texture = WorldPlayer.RIDE_SIDE_A / RIDE_SIDE_B (xoay vòng ~0,06 s/khung khi chạy).
## Quay trái: đặt scale.x = -1 cho node gốc.
static func make_rider_visual() -> Node2D:
	var root := Node2D.new()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sprite := Sprite2D.new()
	sprite.name = "Bike"
	sprite.texture = RIDE_SIDE_A
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.position = Vector2(-34, -RIDE_HEIGHT)
	root.add_child(sprite)
	return root


## Khung nan hoa cho node từ make_rider_visual(): số chẵn = RIDE_SIDE_A, số lẻ = RIDE_SIDE_B.
static func set_rider_wheel_frame(visual: Node2D, frame: int) -> void:
	var sprite := visual.get_node_or_null(^"Bike") as Sprite2D
	if sprite != null:
		sprite.texture = RIDE_SIDE_B if frame % 2 == 1 else RIDE_SIDE_A


## Hướng đang đi = phím hướng được nhấn sau cùng còn đang giữ. Không bao giờ đi chéo.
func _read_direction() -> int:
	for i in range(DIRECTIONS.size()):
		var pressed: bool = false
		for action in DIRECTIONS[i][2]:
			if InputMap.has_action(action) and Input.is_action_pressed(action):
				pressed = true
		if pressed and not _held_order.has(i):
			_held_order.append(i)
		elif not pressed:
			_held_order.erase(i)
	return _held_order.back() if not _held_order.is_empty() else -1


func _blocked_at(feet: Vector2) -> bool:
	var half: int = FOOT_HALF_WIDTH + (3 if riding else 0)
	var x: int = int(feet.x)
	var y: int = int(feet.y)
	for yy in range(y - FOOT_HEIGHT, y + 1, 2):
		for xx in [x - half, x - 2, x, x + 2, x + half - 1]:
			if world.is_blocked(xx, yy):
				return true
	return false


func _set_anim(anim_name: String) -> void:
	if riding and anim_name == "idle":
		# Ngồi yên trên xe: giữ hướng đang nhìn.
		anim_name = {Vector2i(0, -1): "walk_up", Vector2i(-1, 0): "walk_left", Vector2i(1, 0): "walk_right"}.get(facing, "walk_down")
	if _anim == anim_name:
		return
	_anim = anim_name
	_anim_frame = 0
	_anim_time = 0.0
	_apply_frame()


func _advance_anim(delta: float) -> void:
	if riding:
		_apply_frame()
		return
	var data: Array = ANIMS[_anim]
	_anim_time += delta
	var duration: float = data[2][_anim_frame]
	if _anim_time >= duration:
		_anim_time -= duration
		_anim_frame = (_anim_frame + 1) % int(data[1])
		_apply_frame()
		if _anim != "idle" and STEP_FRAMES.has(_anim_frame):
			# Tiếng bước chân: ván gỗ trên cầu, còn lại là đường đất.
			var wood: bool = world != null and world.has_method("is_wood") and world.is_wood(position)
			Audio.sfx(&"step_wood" if wood else &"step_dirt", -9.0, randf_range(0.92, 1.08))


func _apply_frame() -> void:
	if _sprite == null:
		return
	var index: int = frame_index()
	_sprite.visible = not riding
	_shadow.visible = not riding
	if not riding:
		_sprite.region_rect = Rect2(index * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		_sprite.position = -FOOT_IN_FRAME * SPRITE_SCALE # chân nhân vật nằm ở gốc toạ độ
		_shadow.region_rect = _sprite.region_rect
		_shadow.position = _sprite.position
		_shadow.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
		_base_sprite_pos = _sprite.position
		if _wobble_amp > 0.0 or _duck:
			_apply_pose()
		return
	# Trên xe: chỉ vẽ ảnh ghép người ngồi + xe theo hướng (sprite đi bộ ẩn).
	match _anim:
		"walk_left", "walk_right":
			if _wheel_time == 0.0 or _held_order.is_empty() or (_bike.texture != RIDE_SIDE_A and _bike.texture != RIDE_SIDE_B):
				_bike.texture = RIDE_SIDE_A
			_bike.flip_h = _anim == "walk_left"
			_bike.position = Vector2(-34, -RIDE_HEIGHT)
		"walk_up":
			_bike.texture = RIDE_BACK
			_bike.flip_h = false
			_bike.position = Vector2(-15, -RIDE_HEIGHT)
		_:
			_bike.texture = RIDE_FRONT
			_bike.flip_h = false
			_bike.position = Vector2(-15, -RIDE_HEIGHT)
	_base_bike_pos = _bike.position
	if _wobble_amp > 0.0 or _duck:
		_apply_pose()


## Lắc lư (amp 0 = tắt, ~1 = cầu khỉ) theo đồng hồ t (s) – World gọi mỗi frame.
func set_wobble(amp: float, t: float) -> void:
	if amp == 0.0 and _wobble_amp == 0.0:
		return
	_wobble_amp = amp
	_wobble_phase = t
	_apply_pose()


## Cúi người (thấp xuống ~20%) khi vỏ lãi đang chui dưới mặt cầu.
func set_ducking(on: bool) -> void:
	if on == _duck:
		return
	_duck = on
	_apply_pose()


func is_ducking() -> bool:
	return _duck


## Góc nghiêng hiện tại (rad) của hình nhân vật – test đọc.
func pose_rotation() -> float:
	return _sprite.rotation if not riding else _bike.rotation


## Áp lắc lư/cúi lên sprite người và ảnh xe (xoay quanh chân = gốc node).
func _apply_pose() -> void:
	if _sprite == null:
		return
	var rot: float = 0.0
	var dx: float = 0.0
	if _wobble_amp > 0.0:
		rot = sin(_wobble_phase * 7.0) * 0.07 * _wobble_amp
		dx = roundf(sin(_wobble_phase * 3.5) * _wobble_amp)
	var sy: float = 0.8 if _duck else 1.0
	_sprite.rotation = rot
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE * sy)
	_sprite.position = Vector2(dx, 0.0) + (_base_sprite_pos * Vector2(1.0, sy)).rotated(rot)
	_bike.rotation = rot
	_bike.scale = Vector2(1.0, sy)
	_bike.position = Vector2(dx, 0.0) + (_base_bike_pos * Vector2(1.0, sy)).rotated(rot)


## Quay mặt về hướng dir khi đứng yên (vd. quay sang người đang nói chuyện).
func face(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	facing = dir
	if not riding:
		_set_anim("idle")
	_apply_frame()


## Tên hoạt ảnh + chỉ số khung trong tag đang vẽ (test đọc).
func anim_state() -> Array:
	return [_anim, _anim_frame]


## Ô khung đang vẽ trong SHEET (test đọc).
func frame_index() -> int:
	if _anim == "idle" and IDLE_HOLD.has(facing):
		return int(IDLE_HOLD[facing])
	return int(ANIMS[_anim][0]) + _anim_frame
