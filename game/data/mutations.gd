class_name MutationCatalog
extends RefCounted

## Đột biến (GDD 5.5, 7.5): luôn có đánh đổi, không có nâng cấp thuần cộng; trả bằng Biotech; mở ở Act 2.
## GameState.MUTATIONS = MUTATIONS (hợp đồng API v2). Dùng: const Mutations := preload("res://game/data/mutations.gd").
## Mỗi đột biến: name, cost (Biotech), stats (cùng định dạng ItemCatalog: phẳng hp/atk/def/spd/weight/crit, %
## hp_pct/atk_pct/spd_pct), flags (passive cho code trận), power (hệ số power_rating), colors (lớp màu chồng lên lông
## gà, định dạng rooster.gdshader), text (một dòng: lợi + đánh đổi).
## PLACEHOLDER: mọi con số (GDD chỉ nêu Fast Muscle +SPD −HP, Iron Bone +DEF −SPD; ~1 mutation/tuần → giá 6–10
## Biotech ≈ 60–100 Technology ≈ một tuần đi học + thư viện).

const UNLOCK_ACT: int = 2
const HELL_MODE_MIN: int = 3          # GDD 9.3: Olympic chỉ nhận gà đã qua ≥ 3 mutation
const TECH_PER_BIOTECH: int = 10      # GDD 7.1: 10 Technology → 1 Biotech

const ORDER: Array[StringName] = [&"fast_muscle", &"iron_bone", &"burning_blood", &"wing_evolution"]

const MUTATIONS: Dictionary = {
	&"fast_muscle": {"name": "Cơ Nhanh (Fast Muscle)", "cost": 6,
		"stats": {"spd_pct": 0.15, "hp_pct": -0.10}, "flags": {"dash_recovery_mult": 0.9}, "power": 1.0,
		"colors": {"legs": [0.0, 1.2, 1.15]},
		"text": "+15% SPD, dash hồi nhanh 10% · đánh đổi: −10% HP"},
	&"iron_bone": {"name": "Xương Sắt (Iron Bone)", "cost": 6,
		"stats": {"def": 3.0, "weight": 0.8, "spd_pct": -0.10}, "flags": {}, "power": 1.0,
		"colors": {"neck": [0.0, 0.6, 0.85]},
		"text": "+3 DEF, nặng thêm 0,8 (khó bị đẩy, nhiều Khô Gà hơn) · đánh đổi: −10% SPD"},
	&"burning_blood": {"name": "Máu Lửa (Burning Blood)", "cost": 8,
		"stats": {"atk_pct": 0.15, "def": -2.0}, "flags": {"low_hp_atk_mult": 1.2, "condition_loss_mult": 1.5},
		"power": 1.03, "colors": {"comb": [0.0, 1.35, 1.2], "body": [0.02, 1.15, 1.05]},
		"text": "+15% ATK, HP dưới 30% thì ATK ×1,2 · đánh đổi: −2 DEF, thua trận mất Thể trạng ×1,5"},
	&"wing_evolution": {"name": "Cánh Tiến Hóa (Wing Evolution)", "cost": 10,
		"stats": {"hp_pct": -0.08, "weight": -0.5}, "flags": {"double_jump": true, "air_dash": true}, "power": 1.08,
		"colors": {"tail": [0.08, 1.2, 1.4]},
		"text": "Nhảy hai lần, lướt trên không · đánh đổi: −8% HP, nhẹ đi 0,5 (bị đẩy lùi xa hơn)"},
}


static func has(id: StringName) -> bool:
	return MUTATIONS.has(StringName(id))


static func info(id: StringName) -> Dictionary:
	return MUTATIONS.get(StringName(id), {})


static func cost(id: StringName) -> int:
	return int(info(id).get("cost", 0))


static func display_name(id: StringName) -> String:
	return String(info(id).get("name", String(id)))


## Tỷ lệ trứng nở ra gà có sẵn 1 đột biến, theo Biotech bỏ thêm (vượt mức tối thiểu của trứng).
## PLACEHOLDER: 10% + 10%/Biotech thêm, trứng hiếm +10%, tối đa 75%.
static func hatch_mutation_chance(extra_biotech: int, rare_egg: bool) -> float:
	return minf(0.75, 0.10 + 0.10 * float(maxi(extra_biotech, 0)) + (0.10 if rare_egg else 0.0))


## Tỷ lệ "Trứng lạ" nở ra giống hiếm (Gà Đông Tảo); còn lại chia đều nòi/tre.
## PLACEHOLDER: 20% + 8%/Biotech thêm, tối đa 60%.
static func rare_breed_chance(extra_biotech: int) -> float:
	return minf(0.60, 0.20 + 0.08 * float(maxi(extra_biotech, 0)))
