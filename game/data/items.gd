class_name ItemCatalog
extends RefCounted

## Danh mục vật phẩm: trang bị 6 ô (GDD 5.3), vũ khí (GDD 5.2), thức ăn, trứng, đồ Tiệm Mèo (GDD 7.1).
## Dùng: const Items := preload("res://game/data/items.gd") hoặc class_name ItemCatalog.
##
## Mỗi món: id, name, kind (equipment|food|egg), slot (trang bị), price, currency (money|kho_ga),
##  mods  – chỉ số cộng phẳng: hp, atk, def, spd, weight, crit; phần trăm: hp_pct, atk_pct, spd_pct,
##  flags – passive/hành vi cho code trận đọc (xem FLAG_DOCS), power – hệ số cho power_rating (mặc định 1.0),
##  shop (grocery = Tiệm Cô Ba, market = chợ, cat = Tiệm Mèo), unlock (Act tối thiểu), desc, passive,
##  layer + order (trang bị: tên lớp sprite chồng lên thân gà và thứ tự vẽ, GDD 5.3).
## Thức ăn: effect {meal: bool (bữa chính, tránh phạt bỏ đói), exp, condition}.
## Trứng: breed (−1 = ngẫu nhiên), incubate_days, biotech_min, rarity.
## Giá ngoài GDD là PLACEHOLDER (GDD chỉ chốt Mào sắt 150k, Dao chân 200k, Lúa 15k, Cám 40k).

const SLOTS: Array[StringName] = [&"head", &"armor", &"wing", &"spur", &"comb", &"weapon"]
const SLOT_NAMES: Dictionary = {
	&"head": "Đầu", &"armor": "Giáp", &"wing": "Cánh", &"spur": "Cựa", &"comb": "Mào", &"weapon": "Vũ khí",
}
## Thứ tự vẽ lớp sprite (nhỏ vẽ trước). GDD 5.3: Thân → Đầu → Mào → Giáp → Cánh → Vũ khí.
## PLACEHOLDER: GDD không xếp ô Cựa; đặt ngay sau Thân (cựa nằm ở chân, bị thân/cánh che bớt).
const LAYER_ORDER: Dictionary = {
	&"body": 0, &"spur": 5, &"head": 10, &"comb": 20, &"armor": 30, &"wing": 40, &"weapon": 50,
}
const SHOP_NAMES: Dictionary = {&"grocery": "Tiệm tạp hóa Cô Ba", &"market": "Chợ", &"cat": "Tiệm Mèo"}
const KHO_GA_PRICE_PER_KG: int = 50000   # GDD 7.1: bán Khô Gà 50.000đ/kg

## Cờ hành vi (code trận đọc từ side["flags"]; số có hậu tố _mult nhân dồn, số khác cộng dồn, bool OR).
const FLAG_DOCS: Dictionary = {
	"light_startup": "Light startup (frame) thay cho mặc định 5 – Dao chân = 3",
	"light_combo_extra": "Số Light thêm vào chuỗi combo (Dao chân +1: L-L-L-H)",
	"heavy_kb_mult": "Hệ số knockback Heavy gây ra",
	"heavy_gust": "Heavy bắn luồng gió đẩy lùi (Quạt lông)",
	"melee_dmg_mult": "Hệ số sát thương cận chiến gây ra",
	"heavy_rush": "Heavy thành cú lao (Nón bảo hiểm)",
	"heavy_armor_hits": "Số đòn chịu được (không hitstun) trong Heavy",
	"heavy_startup_add": "Frame cộng thêm vào startup Heavy",
	"high_hit_kb_taken_mult": "Hệ số knockback nhận khi trúng đòn cao",
	"low_hit_kb_taken_mult": "Hệ số knockback nhận khi trúng đòn thấp",
	"high_hit_dmg_taken_mult": "Hệ số sát thương nhận từ đòn cao",
	"dmg_taken_mult": "Hệ số mọi sát thương nhận",
	"chip_taken_mult": "Hệ số sát thương xuyên đỡ (chip) nhận",
	"dash_recovery_mult": "Hệ số thời gian hồi dash",
	"block_drain_mult": "Hệ số hao Block Gauge khi đỡ",
	"block_damage_mult": "Hệ số hao Block Gauge gây ra cho đối thủ",
	"light_dmg_mult": "Hệ số sát thương Light gây ra",
	"heavy_dmg_mult": "Hệ số sát thương Heavy gây ra",
	"crit_dmg_add": "Cộng vào hệ số chí mạng ×1,5",
	"special_gain_mult": "Hệ số tích Special Gauge",
	"hitstun_taken_mult": "Hệ số thời gian hitstun nhận",
	"low_hp_atk_mult": "Hệ số ATK khi HP < 30% (Máu Lửa)",
	"condition_loss_mult": "Hệ số Thể trạng mất khi thua (Máu Lửa)",
	"double_jump": "Được nhảy hai lần (Cánh Tiến Hóa)",
	"air_dash": "Được lướt trên không (Cánh Tiến Hóa)",
	"cosmetic": "Chỉ đổi ngoại hình",
}

const ITEMS: Dictionary = {
	# ---------------------------------------------------------------- Đầu
	&"mao_sat": {"name": "Mào sắt", "kind": &"equipment", "slot": &"head", "price": 150000, "currency": &"money",
		"mods": {"def": 2.0}, "flags": {"high_hit_kb_taken_mult": 0.8}, "shop": &"grocery", "unlock": 1,
		"passive": "Giảm 20% knockback khi trúng đòn cao", "desc": "Mũ sắt che mào (GDD 5.3). +2 DEF.",
		"layer": &"head_mao_sat", "order": 10},
	&"khan_ran": {"name": "Khăn rằn", "kind": &"equipment", "slot": &"head", "price": 220000, "currency": &"money",
		"mods": {"def": 1.0, "crit": 0.02}, "flags": {"hitstun_taken_mult": 0.95}, "shop": &"grocery", "unlock": 2,
		"passive": "Lì đòn: hitstun nhận −5%", "desc": "Khăn rằn Nam Bộ cột đầu. +1 DEF, +2% CRIT.",
		"layer": &"head_khan_ran", "order": 10},
	&"mu_dong": {"name": "Mũ đồng", "kind": &"equipment", "slot": &"head", "price": 900000, "currency": &"money",
		"mods": {"def": 3.0, "hp": 10.0}, "flags": {"high_hit_kb_taken_mult": 0.7}, "shop": &"grocery", "unlock": 2,
		"passive": "Giảm 30% knockback khi trúng đòn cao", "desc": "Mũ đồng gò tay. +3 DEF, +10 HP.",
		"layer": &"head_mu_dong", "order": 10},
	&"khan_meo": {"name": "Khăn choàng Mèo Mun", "kind": &"equipment", "slot": &"head", "price": 1.5, "currency": &"kho_ga",
		"mods": {}, "flags": {"cosmetic": true}, "shop": &"cat", "unlock": 2,
		"passive": "Chỉ để làm đẹp", "desc": "Đồ độc quyền Tiệm Mèo. Không có chỉ số.",
		"layer": &"head_khan_meo", "order": 10},
	# ---------------------------------------------------------------- Giáp
	&"giap_tre": {"name": "Giáp tre", "kind": &"equipment", "slot": &"armor", "price": 250000, "currency": &"money",
		"mods": {"def": 2.0, "hp": 10.0}, "flags": {"chip_taken_mult": 0.8}, "shop": &"grocery", "unlock": 2,
		"passive": "Sát thương xuyên đỡ nhận −20%", "desc": "Nan tre đan áo ngực. +2 DEF, +10 HP.",
		"layer": &"armor_giap_tre", "order": 30},
	&"giap_dong": {"name": "Giáp đồng", "kind": &"equipment", "slot": &"armor", "price": 900000, "currency": &"money",
		"mods": {"def": 4.0, "hp": 20.0, "spd": -10.0, "weight": 0.5}, "flags": {"low_hit_kb_taken_mult": 0.8},
		"shop": &"grocery", "unlock": 2,
		"passive": "Giảm 20% knockback khi trúng đòn thấp", "desc": "Vảy đồng. +4 DEF, +20 HP, −10 SPD.",
		"layer": &"armor_giap_dong", "order": 30},
	&"giap_thep": {"name": "Giáp thép mạ", "kind": &"equipment", "slot": &"armor", "price": 2500000, "currency": &"money",
		"mods": {"def": 7.0, "hp": 35.0, "spd": -15.0, "weight": 1.0}, "flags": {"dmg_taken_mult": 0.95},
		"shop": &"grocery", "unlock": 3,
		"passive": "Mọi sát thương nhận −5%", "desc": "Hàng Sài Gòn. +7 DEF, +35 HP, −15 SPD.",
		"layer": &"armor_giap_thep", "order": 30},
	# ---------------------------------------------------------------- Cánh
	&"canh_lua": {"name": "Cánh lụa", "kind": &"equipment", "slot": &"wing", "price": 200000, "currency": &"money",
		"mods": {"spd": 10.0}, "flags": {"dash_recovery_mult": 0.9}, "shop": &"grocery", "unlock": 2,
		"passive": "Dash hồi nhanh 10%", "desc": "Lụa Tân Châu bọc cánh. +10 SPD.",
		"layer": &"wing_canh_lua", "order": 40},
	&"canh_gio": {"name": "Cánh gió", "kind": &"equipment", "slot": &"wing", "price": 1000000, "currency": &"money",
		"mods": {"spd": 20.0, "crit": 0.02}, "flags": {"dash_recovery_mult": 0.85}, "shop": &"grocery", "unlock": 2,
		"passive": "Dash hồi nhanh 15%", "desc": "Lông vũ ghép nan mỏng. +20 SPD, +2% CRIT.",
		"layer": &"wing_canh_gio", "order": 40},
	&"canh_sat": {"name": "Cánh sắt", "kind": &"equipment", "slot": &"wing", "price": 2000000, "currency": &"money",
		"mods": {"def": 3.0, "hp": 15.0, "spd": -5.0}, "flags": {"block_drain_mult": 0.85}, "shop": &"grocery", "unlock": 3,
		"passive": "Đỡ đòn hao Block Gauge −15%", "desc": "Lá sắt che cánh. +3 DEF, +15 HP, −5 SPD.",
		"layer": &"wing_canh_sat", "order": 40},
	&"canh_ma_meo": {"name": "Cánh Mèo Mun", "kind": &"equipment", "slot": &"wing", "price": 6.0, "currency": &"kho_ga",
		"mods": {"spd": 15.0, "crit": 0.03}, "flags": {"dash_recovery_mult": 0.85}, "shop": &"cat", "unlock": 2,
		"passive": "Dash hồi nhanh 15%", "desc": "Đồ độc quyền Tiệm Mèo. +15 SPD, +3% CRIT.",
		"layer": &"wing_canh_ma_meo", "order": 40},
	# ---------------------------------------------------------------- Cựa
	&"cua_tre": {"name": "Cựa tre", "kind": &"equipment", "slot": &"spur", "price": 60000, "currency": &"money",
		"mods": {"atk": 0.5}, "flags": {"light_dmg_mult": 1.05}, "shop": &"grocery", "unlock": 1,
		"passive": "Light +5% sát thương", "desc": "Cựa tre vót nhọn, rẻ mà xài được. +0,5 ATK.",
		"layer": &"spur_cua_tre", "order": 5},
	&"cua_sat": {"name": "Cựa sắt", "kind": &"equipment", "slot": &"spur", "price": 350000, "currency": &"money",
		"mods": {"atk": 1.5}, "flags": {"heavy_dmg_mult": 1.05}, "shop": &"grocery", "unlock": 2,
		"passive": "Heavy +5% sát thương", "desc": "Cựa sắt rèn ở Chợ Lách. +1,5 ATK.",
		"layer": &"spur_cua_sat", "order": 5},
	&"cua_bac": {"name": "Cựa bạc", "kind": &"equipment", "slot": &"spur", "price": 1200000, "currency": &"money",
		"mods": {"atk": 2.5, "crit": 0.03}, "flags": {"crit_dmg_add": 0.1}, "shop": &"grocery", "unlock": 2,
		"passive": "Chí mạng ×1,6 thay vì ×1,5", "desc": "Cựa bạc bén ngọt. +2,5 ATK, +3% CRIT.",
		"layer": &"spur_cua_bac", "order": 5},
	&"cua_thep": {"name": "Cựa thép", "kind": &"equipment", "slot": &"spur", "price": 3000000, "currency": &"money",
		"mods": {"atk": 4.0, "crit": 0.04}, "flags": {"block_damage_mult": 1.2}, "shop": &"grocery", "unlock": 3,
		"passive": "Đánh vào thế đỡ hao Block Gauge đối thủ +20%", "desc": "Thép tốt nhất miền Tây. +4 ATK, +4% CRIT.",
		"layer": &"spur_cua_thep", "order": 5},
	# ---------------------------------------------------------------- Mào
	&"mao_cat": {"name": "Mào cắt gọn", "kind": &"equipment", "slot": &"comb", "price": 100000, "currency": &"money",
		"mods": {"def": 1.0, "crit": 0.01}, "flags": {"high_hit_dmg_taken_mult": 0.9}, "shop": &"grocery", "unlock": 2,
		"passive": "Sát thương nhận từ đòn cao −10%", "desc": "Sửa mào gọn cho khó bị mổ. +1 DEF.",
		"layer": &"comb_mao_cat", "order": 20},
	&"mao_dong": {"name": "Mào đồng", "kind": &"equipment", "slot": &"comb", "price": 700000, "currency": &"money",
		"mods": {"def": 2.0, "hp": 10.0}, "flags": {"special_gain_mult": 1.1}, "shop": &"grocery", "unlock": 2,
		"passive": "Special Gauge tích nhanh 10%", "desc": "Bọc mào bằng đồng mỏng. +2 DEF, +10 HP.",
		"layer": &"comb_mao_dong", "order": 20},
	&"mao_vang_meo": {"name": "Mào vàng Tiệm Mèo", "kind": &"equipment", "slot": &"comb", "price": 4.0, "currency": &"kho_ga",
		"mods": {"def": 2.0, "crit": 0.03}, "flags": {"special_gain_mult": 1.15}, "shop": &"cat", "unlock": 2,
		"passive": "Special Gauge tích nhanh 15%", "desc": "Đồ độc quyền Tiệm Mèo. +2 DEF, +3% CRIT.",
		"layer": &"comb_mao_vang_meo", "order": 20},
	# ---------------------------------------------------------------- Vũ khí (GDD 5.2 – hành vi và đánh đổi đúng bảng)
	&"dao_chan": {"name": "Dao chân", "kind": &"equipment", "slot": &"weapon", "price": 200000, "currency": &"money",
		"mods": {}, "flags": {"light_startup": 3, "light_combo_extra": 1, "heavy_kb_mult": 0.9}, "power": 1.08,
		"shop": &"grocery", "unlock": 1,
		"passive": "Light startup 3 thay vì 5; combo thêm 1 Light (L-L-L-H). Đánh đổi: Heavy −10% knockback",
		"desc": "Dao buộc chân gà (GDD 5.2).", "layer": &"weapon_dao_chan", "order": 50},
	&"quat_long": {"name": "Quạt lông", "kind": &"equipment", "slot": &"weapon", "price": 600000, "currency": &"money",
		"mods": {}, "flags": {"heavy_gust": true, "melee_dmg_mult": 0.8}, "power": 1.05, "shop": &"grocery", "unlock": 2,
		"passive": "Heavy bắn luồng gió đẩy lùi, kiểm soát khoảng cách. Đánh đổi: sát thương cận chiến −20%",
		"desc": "Quạt lông gà buộc cánh (GDD 5.2).", "layer": &"weapon_quat_long", "order": 50},
	&"non_bao_hiem": {"name": "Nón bảo hiểm", "kind": &"equipment", "slot": &"weapon", "price": 700000, "currency": &"money",
		"mods": {}, "flags": {"heavy_rush": true, "heavy_armor_hits": 1, "heavy_startup_add": 6}, "power": 1.06,
		"shop": &"grocery", "unlock": 2,
		"passive": "Heavy thành cú lao có giáp chịu 1 đòn. Đánh đổi: startup Heavy +6 frame",
		"desc": "Nón bảo hiểm cắt nhỏ đội đầu húc (GDD 5.2).", "layer": &"weapon_non_bao_hiem", "order": 50},
	# ---------------------------------------------------------------- Thức ăn
	&"lua": {"name": "Lúa", "kind": &"food", "price": 15000, "currency": &"money", "shop": &"market", "unlock": 1,
		"effect": {"meal": true}, "desc": "Bữa chính 15.000đ/ngày/con: đêm đó Thể trạng về 100% (GDD 6.1)."},
	&"cam": {"name": "Cám tăng lực", "kind": &"food", "price": 40000, "currency": &"money", "shop": &"grocery", "unlock": 1,
		"effect": {"meal": false, "exp": 20}, "desc": "+20 EXP (GDD 7.2). Không thay bữa chính."},
	&"cam_cao_dam": {"name": "Cám cao đạm", "kind": &"food", "price": 150000, "currency": &"money", "shop": &"grocery", "unlock": 2,
		"effect": {"meal": false, "exp": 120}, "desc": "+120 EXP. Không thay bữa chính."},
	&"thuoc_bo": {"name": "Thuốc bổ gà", "kind": &"food", "price": 50000, "currency": &"money", "shop": &"grocery", "unlock": 1,
		"effect": {"meal": false, "condition": 30}, "desc": "+30% Thể trạng ngay."},
	&"pate_meo": {"name": "Pate Tiệm Mèo", "kind": &"food", "price": 0.8, "currency": &"kho_ga", "shop": &"cat", "unlock": 2,
		"effect": {"meal": true, "condition": 50, "exp": 30}, "desc": "Bữa chính hảo hạng: +50% Thể trạng, +30 EXP."},
	# ---------------------------------------------------------------- Trứng (ấp ở nhà + Biotech; rẻ hơn gà trưởng thành)
	&"trung_ga_tre": {"name": "Trứng gà tre", "kind": &"egg", "price": 120000, "currency": &"money", "shop": &"market",
		"unlock": 2, "breed": 1, "incubate_days": 2, "biotech_min": 1, "rarity": &"common",
		"desc": "Ấp 2 ngày, tối thiểu 1 Biotech."},
	&"trung_ga_noi": {"name": "Trứng gà nòi", "kind": &"egg", "price": 180000, "currency": &"money", "shop": &"market",
		"unlock": 2, "breed": 0, "incubate_days": 3, "biotech_min": 1, "rarity": &"common",
		"desc": "Ấp 3 ngày, tối thiểu 1 Biotech."},
	&"trung_dong_tao": {"name": "Trứng gà Đông Tảo", "kind": &"egg", "price": 300000, "currency": &"money", "shop": &"market",
		"unlock": 2, "breed": 2, "incubate_days": 4, "biotech_min": 2, "rarity": &"rare",
		"desc": "Giống hiếm. Ấp 4 ngày, tối thiểu 2 Biotech."},
	&"trung_la": {"name": "Trứng lạ", "kind": &"egg", "price": 250000, "currency": &"money", "shop": &"market",
		"unlock": 3, "breed": -1, "incubate_days": 5, "biotech_min": 3, "rarity": &"rare",
		"desc": "Không rõ giống. Bỏ nhiều Biotech thì dễ ra gà Đông Tảo và đột biến. Ấp 5 ngày."},
}


static func has(id: StringName) -> bool:
	return ITEMS.has(id)


static func get_item(id: StringName) -> Dictionary:
	return ITEMS.get(id, {})


static func display_name(id: StringName) -> String:
	return String(get_item(id).get("name", String(id)))


static func kind_of(id: StringName) -> StringName:
	return StringName(get_item(id).get("kind", &""))


static func is_equipment(id: StringName) -> bool:
	return kind_of(id) == &"equipment"


static func slot_of(id: StringName) -> StringName:
	return StringName(get_item(id).get("slot", &""))


static func layer_order(id: StringName) -> int:
	var item: Dictionary = get_item(id)
	return int(item.get("order", LAYER_ORDER.get(StringName(item.get("slot", &"")), 0)))


static func items_for_slot(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ITEMS.keys():
		if StringName(ITEMS[id].get("slot", &"")) == slot:
			out.append(id)
	return out


static func ids_in_shop(shop: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ITEMS.keys():
		if StringName(ITEMS[id].get("shop", &"")) == shop:
			out.append(id)
	return out


## Chuỗi giá cho UI: "150.000đ" hoặc "4 kg Khô Gà".
static func price_text(id: StringName) -> String:
	var item: Dictionary = get_item(id)
	if StringName(item.get("currency", &"money")) == &"kho_ga":
		return "%s kg Khô Gà" % String.num(float(item.get("price", 0.0)), 2).trim_suffix(".00").replace(".", ",")
	var digits: String = str(int(item.get("price", 0)))
	var out: String = ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return digits + out + "đ"
