extends RefCounted

## Lưới đi lại cho người nhà trong NHÀ & SÂN GÀ: ô CELL px, một ô đi được khi chân người (hình chữ nhật bàn chân như
## WorldPlayer._blocked_at: x−5..x+4, y−5..y) đặt ở TÂM ô không chạm va chạm tĩnh (collision.png + bội đóng thêm; kiểm
## từng điểm ảnh). CELL = 6 < bề ngang/cao bàn chân nên khi đi giữa hai tâm ô kề nhau, bàn chân luôn nằm trong hợp hai
## hình chữ nhật đã kiểm → người nhà không bao giờ bước vào chỗ đặc, mà vẫn lọt các cửa hẹp như người chơi.
## Tìm đường A* 4 hướng (AStarGrid2D, không đi chéo – đúng kiểu đi của nhân vật).
## Dùng: var nav := HomeNav.new(); nav.build(solid_bytes, Layout.MAP_SIZE, coop_rects)
##       var path: Array[Vector2i] = nav.find_path(from_world, to_world, avoid_cells)

const CELL: int = 6
## Bàn chân (như WorldPlayer): nửa bề ngang + chiều cao.
const FOOT_HALF_WIDTH: int = 5
const FOOT_HEIGHT: int = 5

var size: Vector2i = Vector2i.ZERO
var grid: AStarGrid2D
var _walkable: PackedByteArray = PackedByteArray()


## solid: 1 byte/điểm ảnh (≠0 = đặc, như HomeScene._solid); extra: các hình chữ nhật đặc thêm (bội đóng thêm).
func build(solid: PackedByteArray, map_size: Vector2i, extra: Array[Rect2i] = []) -> void:
	size = Vector2i(map_size.x / CELL, map_size.y / CELL)
	_walkable.resize(size.x * size.y)
	grid = AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	var half: int = CELL / 2
	var w: int = map_size.x
	var full: bool = solid.size() == map_size.x * map_size.y
	for r in range(size.y):
		for c in range(size.x):
			var cx: int = c * CELL + half
			var cy: int = r * CELL + half
			# bàn chân đặt ở tâm ô (kiểm từng điểm ảnh)
			var x0: int = cx - FOOT_HALF_WIDTH
			var x1: int = cx + FOOT_HALF_WIDTH - 1
			var y0: int = cy - FOOT_HEIGHT
			var y1: int = cy
			var ok: bool = x0 >= 0 and y0 >= 0 and x1 < map_size.x and y1 < map_size.y and full
			var area := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
			if ok:
				for e in extra:
					if e.intersects(area):
						ok = false
						break
			var y: int = y0
			while ok and y <= y1:
				var row: int = y * w
				var x: int = x0
				while x <= x1:
					if solid[row + x] != 0:
						ok = false
						break
					x += 1
				y += 1
			_walkable[r * size.x + c] = 1 if ok else 0
			if not ok:
				grid.set_point_solid(Vector2i(c, r), true)


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(pos.x) / CELL, 0, size.x - 1), clampi(int(pos.y) / CELL, 0, size.y - 1))


func center_of(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL + CELL / 2, cell.y * CELL + CELL / 2)


func is_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false
	return _walkable[cell.y * size.x + cell.x] == 1


## Ô đi được gần pos nhất (tìm theo vòng vuông nở dần); không có thì trả Vector2i(-1, -1).
func nearest_walkable(pos: Vector2) -> Vector2i:
	var c: Vector2i = cell_of(pos)
	if is_walkable(c):
		return c
	for radius in range(1, 12):
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: float = INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var n := Vector2i(c.x + dx, c.y + dy)
				if is_walkable(n):
					var d: float = center_of(n).distance_squared_to(pos)
					if d < best_d:
						best_d = d
						best = n
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Đường đi (danh sách ô, gồm ô đầu và ô cuối) giữa hai điểm thế giới; avoid = các ô tạm coi là đặc (người chơi,
## người nhà khác đang đứng). Rỗng nếu không có đường.
func find_path(from: Vector2, to: Vector2, avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	var a: Vector2i = nearest_walkable(from)
	var b: Vector2i = nearest_walkable(to)
	if a.x < 0 or b.x < 0:
		return []
	var marked: Array[Vector2i] = []
	for cell in avoid:
		if cell != a and cell != b and is_walkable(cell) and not grid.is_point_solid(cell):
			grid.set_point_solid(cell, true)
			marked.append(cell)
	var path: Array[Vector2i] = grid.get_id_path(a, b)
	for cell in marked:
		grid.set_point_solid(cell, false)
	return path
