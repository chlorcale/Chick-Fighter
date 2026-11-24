extends RefCounted

## Ảnh dùng chung cho mini-game tẩu thoát và cắt cảnh rửa chén: tải sheet trong game/art/escape/ (sinh bởi
## tools/art/build_escape.py, toạ độ ở escape_sheets.gd) và cắt thành AtlasTexture (có cache).
## Thiếu file nào thì trả null → nơi gọi vẽ hình thay thế (không bao giờ lỗi).

const Sheets := preload("res://game/escape/escape_sheets.gd")
const DIR: String = "res://game/art/escape/"

static var _tex: Dictionary = {}     # đường dẫn → Texture2D (hoặc null)
static var _cut: Dictionary = {}     # khoá → AtlasTexture


## Xoá cache (test gọi trước khi thoát để không báo rò rỉ tài nguyên tĩnh).
static func clear_cache() -> void:
	_tex.clear()
	_cut.clear()


static func sheet(file: String) -> Texture2D:
	var path: String = DIR + file
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex[path] = t
	return t


static func region(file: String, rect: Rect2i) -> Texture2D:
	var key: String = "%s|%d,%d,%d,%d" % [file, rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if _cut.has(key):
		return _cut[key]
	var base: Texture2D = sheet(file)
	if base == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = base
	atlas.region = Rect2(rect)
	_cut[key] = atlas
	return atlas


## Biến thể gà theo giống: 2 = Đông Tảo, còn lại (nòi/tre) dùng gà đỏ.
static func variant_for(chicken: Dictionary) -> String:
	return "dongtao" if int(chicken.get("breed", 0)) == 2 else "noi"


## Khung nhân vật nhìn ngang (ôm gà) theo tên trong Sheets.HERO.
static func hero(variant: String, frame: String) -> Texture2D:
	var i: int = int(Sheets.HERO.get(frame, 0))
	var c: int = Sheets.HERO_CELL
	return region("hero_%s.png" % variant, Rect2i(i * c, 0, c, c))


static func hero_back(frame: String) -> Texture2D:
	var i: int = int(Sheets.HERO_BACK.get(frame, 0))
	var c: int = Sheets.HERO_CELL
	return region("hero_back.png", Rect2i(i * c, 0, c, c))


## row 0 = chú cao gầy, 1 = chú thấp mập; col theo Sheets.POLICE.
static func police(row: int, col: int) -> Texture2D:
	var cell: Vector2i = Sheets.POLICE_CELL
	return region("police.png", Rect2i(col * cell.x, row * cell.y, cell.x, cell.y))


static func rooster(variant: String, blink: bool) -> Texture2D:
	var cell: Vector2i = Sheets.ROOSTER_CELL
	var row: int = 1 if variant == "dongtao" else 0
	return region("rooster_small.png", Rect2i((1 if blink else 0) * cell.x, row * cell.y, cell.x, cell.y))


## Prop cắt từ bản đồ (gốc = giữa-dưới). frame quay vòng theo số khung.
static func prop(prop_name: String, frame: int = 0) -> Texture2D:
	var spec: Array = Sheets.PROPS.get(prop_name, [])
	if spec.is_empty():
		return null
	var n: int = maxi(int(spec[4]), 1)
	var f: int = posmod(frame, n)
	return region("props.png", Rect2i(int(spec[0]) + f * int(spec[2]), int(spec[1]), int(spec[2]), int(spec[3])))


static func prop_frames(prop_name: String) -> int:
	var spec: Array = Sheets.PROPS.get(prop_name, [])
	return 0 if spec.is_empty() else int(spec[4])


## Vẽ texture với chân (giữa-dưới) ở foot lên canvas item (toạ độ làm tròn). flip = lật ngang.
static func stand(item: CanvasItem, t: Texture2D, foot: Vector2, flip: bool = false, modulate: Color = Color.WHITE) -> void:
	if t == null:
		return
	var size: Vector2 = t.get_size()
	var top_left := Vector2(roundf(foot.x - floorf(size.x * 0.5)), roundf(foot.y - size.y))
	if flip:
		item.draw_set_transform(top_left + Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		item.draw_texture(t, Vector2.ZERO, modulate)
		item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		item.draw_texture(t, top_left, modulate)


## Vẽ một ô nhân vật (HERO_CELL, gốc HERO_FOOT) với gốc ở foot.
static func hero_at(item: CanvasItem, t: Texture2D, foot: Vector2, flip: bool = false) -> void:
	if t == null:
		return
	var f: Vector2i = Sheets.HERO_FOOT
	var pos := Vector2(roundf(foot.x), roundf(foot.y))
	if flip:
		item.draw_set_transform(pos + Vector2(f.x, -f.y), 0.0, Vector2(-1, 1))
		item.draw_texture(t, Vector2.ZERO)
		item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		item.draw_texture(t, pos - Vector2(f))


static func police_at(item: CanvasItem, t: Texture2D, foot: Vector2, flip: bool = false) -> void:
	if t == null:
		return
	var f: Vector2i = Sheets.POLICE_FOOT
	var pos := Vector2(roundf(foot.x), roundf(foot.y))
	if flip:
		item.draw_set_transform(pos + Vector2(f.x, -f.y), 0.0, Vector2(-1, 1))
		item.draw_texture(t, Vector2.ZERO)
		item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		item.draw_texture(t, pos - Vector2(f))


## Mã băm ổn định cho nội dung lặp theo ô (giống race_backdrop.hash_i).
static func hash_i(i: int, salt: int) -> int:
	var v: int = (i * 73856093) ^ (salt * 19349663) ^ 0x5bd1e995
	v = (v ^ (v >> 13)) * 1274126177
	v = v ^ (v >> 16)
	return absi(v) & 0x3fffffff


## Hình elip pixel (các hàng ngang) – bóng, vũng sình, gợn nước.
static func ellipse(item: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	var rows: int = int(ry)
	for k in range(-rows, rows + 1):
		var half: float = roundf(rx * sqrt(maxf(1.0 - pow(float(k) / (ry + 0.5), 2.0), 0.0)))
		item.draw_rect(Rect2(roundf(center.x - half), roundf(center.y) + float(k), half * 2.0, 1.0), color)
