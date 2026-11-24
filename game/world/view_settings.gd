extends RefCounted

## Thiết lập khung nhìn dùng chung (không phụ thuộc GameState/file lưu game): mức thu phóng camera bản đồ.
## World đọc/ghi; cảnh trong nhà (game/home) có thể đọc ViewSettings.zoom_level sau này để cùng mức thu phóng.
## Lưu ở user://view_settings.cfg (test đổi save_path để không đụng file thật).
## Dùng: const ViewSettings := preload("res://game/world/view_settings.gd")

## Các nấc thu phóng (1 px bản đồ = bấy nhiêu px màn hình). 2,0 thấy rộng nhất; 2,5 mặc định (trước đây cố định 3,0).
const ZOOM_STEPS: Array[float] = [2.0, 2.5, 3.0, 4.0]
const DEFAULT_ZOOM: float = 2.5

static var save_path: String = "user://view_settings.cfg"
static var zoom_level: float = DEFAULT_ZOOM
static var _loaded: bool = false


## Đọc file thiết lập (một lần). Giá trị lạ → nấc gần nhất.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		zoom_level = snap_zoom(float(cfg.get_value("view", "zoom", DEFAULT_ZOOM)))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value("view", "zoom", zoom_level)
	cfg.save(save_path)


## Nấc gần giá trị z nhất.
static func snap_zoom(z: float) -> float:
	var best: float = DEFAULT_ZOOM
	for step in ZOOM_STEPS:
		if absf(step - z) < absf(best - z):
			best = step
	return best


static func step_index(z: float) -> int:
	return ZOOM_STEPS.find(snap_zoom(z))


## Nấc kế tiếp: dir > 0 phóng to (gần hơn), dir < 0 thu nhỏ (thấy rộng hơn). Đặt + lưu, trả về mức mới.
static func step_zoom(dir: int) -> float:
	ensure_loaded()
	var i: int = clampi(step_index(zoom_level) + signi(dir), 0, ZOOM_STEPS.size() - 1)
	set_zoom(ZOOM_STEPS[i])
	return zoom_level


static func set_zoom(z: float) -> void:
	ensure_loaded()
	zoom_level = snap_zoom(z)
	save()


## Chữ hiển thị: "×2,5".
static func zoom_text(z: float) -> String:
	var s: String = ("%.1f" % z).replace(".", ",")
	return "×" + s
