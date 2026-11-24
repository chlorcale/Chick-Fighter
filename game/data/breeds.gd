class_name BreedCatalog
extends RefCounted

## Giống gà – phần giá/passive/mở khóa (GDD 5.1, 7.2). Chỉ số gốc vẫn nằm ở GameState.BREED_STATS
## (Đông Tảo theo Owner: HP 130, SPD 140, WEIGHT 12 – xem chú thích ở đó) để code trận cũ không đổi.
## Chỉ số giống trùng MovementConfig.Breed (0 nòi, 1 tre, 2 Đông Tảo).
## Dùng: const Breeds := preload("res://game/data/breeds.gd") hoặc class_name BreedCatalog.

const GA_NOI: int = 0
const GA_TRE: int = 1
const GA_DONG_TAO: int = 2

## price: giá mua gà Lv1 ở chợ (GDD 7.2: tre 250k / nòi 400k / Đông Tảo 600k) và là "Giá giống" của công thức 6.
## unlock: Act mở mua (GDD 5.1: Đông Tảo mở ở Act 2). rarity: dùng cho trứng/ấp.
const BREEDS: Array[Dictionary] = [
	{"id": &"ga_noi", "name": "Gà nòi", "price": 400000, "unlock": 1, "rarity": &"common",
		"passive": &"ben_bi", "passive_text": "Bền Bỉ: −10% hao Block Gauge"},
	{"id": &"ga_tre", "name": "Gà tre", "price": 250000, "unlock": 1, "rarity": &"common",
		"passive": &"lanh_le", "passive_text": "Lanh Lẹ: dash hồi nhanh 30%"},
	{"id": &"ga_dong_tao", "name": "Gà Đông Tảo", "price": 600000, "unlock": 2, "rarity": &"rare",
		"passive": &"gong", "passive_text": "Gồng: không bị Light đẩy lùi"},
]

## Tên gợi ý cho gà mới nở / mới mua (PLACEHOLDER, chỉ là gợi ý cho UI đặt tên).
const NAME_POOL: PackedStringArray = ["Tía", "Nhạn", "Điều", "Ó Ma", "Xám Tro", "Bông Lau", "Khét", "Lửa Rơm",
	"Mây Chiều", "Sấm Sét", "Bão Lũ", "Gió Chướng", "Mướp", "Ô Tía", "Chuối Mật", "Hồng Hạc"]


static func count() -> int:
	return BREEDS.size()


static func is_valid(breed: int) -> bool:
	return breed >= 0 and breed < BREEDS.size()


static func info(breed: int) -> Dictionary:
	return BREEDS[breed] if is_valid(breed) else {}


static func display_name(breed: int) -> String:
	return String(info(breed).get("name", "?"))


static func price(breed: int) -> int:
	return int(info(breed).get("price", 0))


static func random_name(rng: RandomNumberGenerator) -> String:
	return NAME_POOL[rng.randi_range(0, NAME_POOL.size() - 1)]


## Màu lông ngẫu nhiên cho gà mới nở (cùng định dạng "colors" của OPPONENTS / rooster.gdshader:
## {bộ phận: [lệch hue, ×sat, ×value]}). PLACEHOLDER: biên độ lệch màu.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var body_hue: float = rng.randf_range(-0.12, 0.12)
	return {
		"hue": 0.0, "sat": 1.0,
		"colors": {
			"body": [body_hue, rng.randf_range(0.6, 1.3), rng.randf_range(0.85, 1.3)],
			"neck": [body_hue + rng.randf_range(-0.05, 0.05), rng.randf_range(0.6, 1.3), rng.randf_range(0.9, 1.25)],
			"tail": [rng.randf_range(-0.3, 0.3), rng.randf_range(0.7, 1.4), rng.randf_range(0.8, 1.8)],
		},
	}
