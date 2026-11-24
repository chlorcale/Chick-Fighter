extends Node2D

## Người đi chợ ở Chợ Bình Kê và kè chợ nổi: đi lang thang theo mạng lối đi (game/art/world_map/market_lanes.json,
## dựng sẵn bởi tools/art/build_world_map.py: điểm lưới 12 px ở lối trống, nối 4 hướng), dừng xem hàng ở các điểm
## sát sạp. Không chặn người chơi (nhẹ, Y-sort chung với người chơi qua MapView.add_actor); né người chơi: điểm kế
## tiếp quá gần người chơi thì đứng chờ hoặc rẽ lối khác, nên không bao giờ dồn người chơi vào góc.
## Ảnh: game/art/world_map/shoppers.png – mỗi hàng một người (NPC của bản đồ, đổi màu áo), 4 khung
## (đứng, bước trái, nhún, bước phải), ô 24×46, gốc ở chân (12, 45).

const SHEET: Texture2D = preload("res://game/art/world_map/shoppers.png")
const LANES_PATH: String = "res://game/art/world_map/market_lanes.json"
const CELL: Vector2i = Vector2i(24, 46)
const FOOT: Vector2 = Vector2(12, 45)
const COUNT: int = 46
const AVOID_RADIUS: float = 14.0
const ACTIVE_MARGIN: float = 260.0

var world: Node
var rng := RandomNumberGenerator.new()
var nodes: PackedVector2Array = PackedVector2Array()
var links: Array[PackedInt32Array] = []
var browse: Dictionary = {}
var people: Array[Dictionary] = []
var _variants: int = 1


func _ready() -> void:
	rng.seed = 20261117
	var file := FileAccess.open(LANES_PATH, FileAccess.READ)
	if file == null:
		push_warning("MarketCrowd: thiếu %s" % LANES_PATH)
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	for p in data["nodes"]:
		nodes.append(Vector2(p[0], p[1]))
	links.resize(nodes.size())
	for i in range(nodes.size()):
		links[i] = PackedInt32Array()
	for pair in data["links"]:
		links[int(pair[0])].append(int(pair[1]))
		links[int(pair[1])].append(int(pair[0]))
	for i in data["browse"]:
		browse[int(i)] = true
	_variants = maxi(1, SHEET.get_height() / CELL.y)
	if nodes.is_empty():
		return
	var used: Dictionary = {}
	for k in range(COUNT):
		var start: int = rng.randi() % nodes.size()
		for attempt in range(20):
			if not used.has(start) and links[start].size() > 0:
				break
			start = rng.randi() % nodes.size()
		used[start] = true
		_spawn(k, start)


func _spawn(k: int, start: int) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = SHEET
	sprite.centered = false
	sprite.region_enabled = true
	sprite.offset = -FOOT
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = nodes[start]
	var person: Dictionary = {
		"sprite": sprite, "at": start, "prev": -1, "next": start, "pos": nodes[start],
		"wait": rng.randf_range(0.0, 3.0), "variant": k % _variants, "speed": rng.randf_range(15.0, 26.0),
		"anim": rng.randf() * 4.0, "dir": Vector2.ZERO,
	}
	people.append(person)
	_apply_frame(person, 0)
	if world != null and world.get("map_view") != null:
		world.map_view.add_actor(sprite)
	else:
		add_child(sprite)


func _process(delta: float) -> void:
	step(delta)


## Một bước mô phỏng (test gọi trực tiếp với delta cố định).
func step(delta: float) -> void:
	if people.is_empty():
		return
	var player_pos: Vector2 = Vector2(-9999, -9999)
	var view := Rect2(-1e9, -1e9, 2e9, 2e9)
	if world != null and world.get("player") != null:
		player_pos = world.player.position
		if world.get("map_view") != null:
			view = world.map_view.visible_map_rect().grow(ACTIVE_MARGIN)
	for person in people:
		_update_person(person, delta, player_pos, view)


func _update_person(person: Dictionary, delta: float, player_pos: Vector2, view: Rect2) -> void:
	var sprite: Sprite2D = person["sprite"]
	if float(person["wait"]) > 0.0:
		person["wait"] = float(person["wait"]) - delta
		if view.has_point(person["pos"]):
			# đứng xem hàng: thỉnh thoảng nhún
			_apply_frame(person, 2 if fmod(float(person["anim"]) + float(person["wait"]), 2.6) < 0.3 else 0)
		return
	var target: Vector2 = nodes[int(person["next"])]
	var pos: Vector2 = person["pos"]
	if pos.distance_to(target) < 0.5:
		_arrive(person, player_pos)
		return
	if target.distance_to(player_pos) < AVOID_RADIUS or pos.distance_to(player_pos) < AVOID_RADIUS * 0.8 \
			and (target - pos).dot(player_pos - pos) > 0.0:
		# người chơi chắn lối: đứng chờ một chút rồi đổi hướng (quay lại điểm cũ)
		person["wait"] = rng.randf_range(0.3, 0.8)
		var back: int = int(person["at"])
		person["at"] = int(person["next"])
		person["next"] = back
		return
	pos = pos.move_toward(target, float(person["speed"]) * delta)
	person["pos"] = pos
	person["dir"] = (target - pos).normalized()
	person["anim"] = float(person["anim"]) + delta * 7.0
	if view.has_point(pos):
		sprite.position = pos.round()
		sprite.flip_h = (person["dir"] as Vector2).x < -0.1
		_apply_frame(person, [1, 2, 3, 0][int(person["anim"]) % 4])
	else:
		sprite.position = pos.round()


func _arrive(person: Dictionary, player_pos: Vector2) -> void:
	var here: int = int(person["next"])
	person["prev"] = int(person["at"])
	person["at"] = here
	if browse.has(here) and rng.randf() < 0.35:
		person["wait"] = rng.randf_range(1.5, 5.0)
		_apply_frame(person, 0)
	var options: PackedInt32Array = links[here]
	if options.is_empty():
		return
	var prev: int = int(person["prev"])
	var dir: Vector2 = person["dir"]
	var best: int = options[rng.randi() % options.size()]
	# ưu tiên đi thẳng, tránh quay đầu (trừ ngõ cụt)
	var straight: Array[int] = []
	var others: Array[int] = []
	for o in options:
		if o == prev and options.size() > 1:
			continue
		if nodes[o].distance_to(player_pos) < AVOID_RADIUS:
			continue
		if (nodes[o] - nodes[here]).normalized().dot(dir) > 0.7:
			straight.append(o)
		else:
			others.append(o)
	if not straight.is_empty() and rng.randf() < 0.7:
		best = straight[rng.randi() % straight.size()]
	elif not others.is_empty():
		best = others[rng.randi() % others.size()]
	elif not straight.is_empty():
		best = straight[0]
	person["next"] = best


func _apply_frame(person: Dictionary, frame: int) -> void:
	var sprite: Sprite2D = person["sprite"]
	sprite.region_rect = Rect2(frame * CELL.x, int(person["variant"]) * CELL.y, CELL.x, CELL.y)


## Vị trí chân hiện tại của mọi người đi chợ (test).
func positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for person in people:
		out.append(person["pos"])
	return out
