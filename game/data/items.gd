class_name ItemCatalog
extends RefCounted

## Danh mục vật phẩm: trang bị 6 ô (GDD 5.3), vũ khí (GDD 5.2), thức ăn, trứng, đồ độc quyền của Lão Gà Khô (GDD 7.1).
## GameState.ITEMS = ITEMS (hợp đồng API v2). Dùng: const Items := preload("res://game/data/items.gd").
##
## Mỗi món (khóa hợp đồng): name, slot (&"weapon"|&"head"|&"armor"|&"wing"|&"spur"|&"comb"|&"food"|&"egg"|&"misc"),
##  price (đ, hoặc kg Khô Gà khi currency = &"kho_ga"), text (một dòng hiệu ứng), stats, shop (&"co_ba" Tiệm tạp hóa
##  Cô Ba | &"cho" Chợ | &"meo" Lão Gà Khô – xe khô gà, id cũ giữ nguyên | &""), act (Act tối thiểu để bày bán/dùng).
## Khóa thêm: currency, flags (passive cho code trận – FLAG_DOCS), power (hệ số power_rating, mặc định 1.0),
##  layer + order (sprite chồng lên thân gà, GDD 5.3).
##  stats – cộng phẳng: hp, atk, def, spd, weight, crit; phần trăm: hp_pct, atk_pct, spd_pct.
##  Thức ăn: effect {meal: bool (bữa chính: Thể trạng về 100 + fed_today), condition, exp}.
##  Trứng: breed (−1 = ngẫu nhiên), incubate_days, biotech_min, rarity (&"common"|&"rare").
## Giá GDD (CONFIRMED trong GDD 7.2): Mào sắt 150k, Dao chân 200k, Lúa 15k, Cám tăng lực 40k. Mọi giá/chỉ số khác:
## PLACEHOLDER (tầng rẻ Act 1 ở Cô Ba, tầng mạnh Act 2–3 ở Chợ – xem đường cong trong GameState.CURVE).

const SLOTS: Array[StringName] = [&"head", &"armor", &"wing", &"spur", &"comb", &"weapon"]
## Ô trang bị (không gồm vũ khí – vũ khí nằm ở khóa "weapon" của con gà).
const GEAR_SLOTS: Array[StringName] = [&"head", &"armor", &"wing", &"spur", &"comb"]
const SLOT_NAMES: Dictionary = {
	&"head": "Đầu", &"armor": "Giáp", &"wing": "Cánh", &"spur": "Cựa", &"comb": "Mào", &"weapon": "Vũ khí",
	&"food": "Thức ăn", &"egg": "Trứng", &"misc": "Khác",
}
## Thứ tự vẽ lớp sprite (nhỏ vẽ trước). GDD 5.3: Thân → Đầu → Mào → Giáp → Cánh → Vũ khí.
## PLACEHOLDER: GDD không xếp ô Cựa; đặt ngay sau Thân (cựa nằm ở chân, bị thân/cánh che bớt).
const LAYER_ORDER: Dictionary = {
	&"body": 0, &"spur": 5, &"head": 10, &"comb": 20, &"armor": 30, &"wing": 40, &"weapon": 50,
}
const SHOP_NAMES: Dictionary = {&"co_ba": "Tiệm tạp hóa Cô Ba", &"cho": "Chợ", &"meo": "Lão Gà Khô"}
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
	&"mao_sat": {"name": "Mào sắt", "slot": &"head", "price": 150000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {"def": 2.0}, "flags": {"high_hit_kb_taken_mult": 0.8}, "power": 1.0,
		"text": "+2 DEF · trúng đòn cao bị đẩy lùi −20%", "layer": &"head_mao_sat", "order": 10},
	&"khan_ran": {"name": "Khăn rằn", "slot": &"head", "price": 120000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {"def": 1.0, "crit": 0.02}, "flags": {"hitstun_taken_mult": 0.95}, "power": 1.0,
		"text": "+1 DEF, +2% CRIT · lì đòn: hitstun nhận −5%", "layer": &"head_khan_ran", "order": 10},
	&"mu_dong": {"name": "Mũ đồng", "slot": &"head", "price": 650000, "currency": &"money", "shop": &"cho", "act": 2,
		"stats": {"def": 3.0, "hp": 10.0}, "flags": {"high_hit_kb_taken_mult": 0.7}, "power": 1.0,
		"text": "+3 DEF, +10 HP · trúng đòn cao bị đẩy lùi −30%", "layer": &"head_mu_dong", "order": 10},
	&"mu_thep": {"name": "Mũ thép", "slot": &"head", "price": 1800000, "currency": &"money", "shop": &"cho", "act": 3,
		"stats": {"def": 5.0, "hp": 20.0, "spd": -5.0}, "flags": {"high_hit_kb_taken_mult": 0.6}, "power": 1.0,
		"text": "+5 DEF, +20 HP, −5 SPD · trúng đòn cao bị đẩy lùi −40%", "layer": &"head_mu_thep", "order": 10},
	&"khan_meo": {"name": "Khăn choàng Mèo Mun", "slot": &"head", "price": 1.5, "currency": &"kho_ga", "shop": &"meo",
		"act": 2, "stats": {}, "flags": {"cosmetic": true}, "power": 1.0,
		"text": "Đồ độc quyền Lão Gà Khô – chỉ để làm đẹp", "layer": &"head_khan_meo", "order": 10},
	# ---------------------------------------------------------------- Giáp
	&"giap_tre": {"name": "Giáp tre", "slot": &"armor", "price": 180000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {"def": 2.0, "hp": 10.0}, "flags": {"chip_taken_mult": 0.8}, "power": 1.0,
		"text": "+2 DEF, +10 HP · sát thương xuyên đỡ nhận −20%", "layer": &"armor_giap_tre", "order": 30},
	&"giap_dong": {"name": "Giáp đồng", "slot": &"armor", "price": 800000, "currency": &"money", "shop": &"cho", "act": 2,
		"stats": {"def": 4.0, "hp": 20.0, "spd": -10.0, "weight": 0.5}, "flags": {"low_hit_kb_taken_mult": 0.8},
		"power": 1.0, "text": "+4 DEF, +20 HP, −10 SPD · trúng đòn thấp bị đẩy lùi −20%",
		"layer": &"armor_giap_dong", "order": 30},
	&"giap_thep": {"name": "Giáp thép mạ", "slot": &"armor", "price": 2500000, "currency": &"money", "shop": &"cho",
		"act": 3, "stats": {"def": 7.0, "hp": 35.0, "spd": -15.0, "weight": 1.0}, "flags": {"dmg_taken_mult": 0.95},
		"power": 1.0, "text": "+7 DEF, +35 HP, −15 SPD · mọi sát thương nhận −5%", "layer": &"armor_giap_thep", "order": 30},
	# ---------------------------------------------------------------- Cánh
	&"canh_lua": {"name": "Cánh lụa", "slot": &"wing", "price": 150000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {"spd": 10.0}, "flags": {"dash_recovery_mult": 0.9}, "power": 1.0,
		"text": "+10 SPD · dash hồi nhanh 10%", "layer": &"wing_canh_lua", "order": 40},
	&"canh_gio": {"name": "Cánh gió", "slot": &"wing", "price": 700000, "currency": &"money", "shop": &"cho", "act": 2,
		"stats": {"spd": 20.0, "crit": 0.02}, "flags": {"dash_recovery_mult": 0.85}, "power": 1.0,
		"text": "+20 SPD, +2% CRIT · dash hồi nhanh 15%", "layer": &"wing_canh_gio", "order": 40},
	&"canh_sat": {"name": "Cánh sắt", "slot": &"wing", "price": 2000000, "currency": &"money", "shop": &"cho", "act": 3,
		"stats": {"def": 3.0, "hp": 15.0, "spd": -5.0}, "flags": {"block_drain_mult": 0.85}, "power": 1.0,
		"text": "+3 DEF, +15 HP, −5 SPD · đỡ đòn hao Block Gauge −15%", "layer": &"wing_canh_sat", "order": 40},
	&"canh_meo": {"name": "Cánh Mèo Mun", "slot": &"wing", "price": 6.0, "currency": &"kho_ga", "shop": &"meo", "act": 2,
		"stats": {"spd": 15.0, "crit": 0.03}, "flags": {"dash_recovery_mult": 0.85}, "power": 1.0,
		"text": "Độc quyền Lão Gà Khô: +15 SPD, +3% CRIT · dash hồi nhanh 15%", "layer": &"wing_canh_meo", "order": 40},
	# ---------------------------------------------------------------- Cựa
	&"cua_tre": {"name": "Cựa tre", "slot": &"spur", "price": 60000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {"atk": 0.5}, "flags": {"light_dmg_mult": 1.05}, "power": 1.0,
		"text": "+0,5 ATK · Light +5% sát thương", "layer": &"spur_cua_tre", "order": 5},
	&"cua_sat": {"name": "Cựa sắt", "slot": &"spur", "price": 250000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {"atk": 1.5}, "flags": {"heavy_dmg_mult": 1.05}, "power": 1.0,
		"text": "+1,5 ATK · Heavy +5% sát thương", "layer": &"spur_cua_sat", "order": 5},
	&"cua_dong": {"name": "Cựa đồng", "slot": &"spur", "price": 900000, "currency": &"money", "shop": &"cho", "act": 2,
		"stats": {"atk": 2.5, "crit": 0.03}, "flags": {"crit_dmg_add": 0.1}, "power": 1.0,
		"text": "+2,5 ATK, +3% CRIT · chí mạng ×1,6 thay vì ×1,5", "layer": &"spur_cua_dong", "order": 5},
	&"cua_bac": {"name": "Cựa bạc", "slot": &"spur", "price": 3000000, "currency": &"money", "shop": &"cho", "act": 3,
		"stats": {"atk": 4.0, "crit": 0.04}, "flags": {"block_damage_mult": 1.2, "crit_dmg_add": 0.1}, "power": 1.0,
		"text": "+4 ATK, +4% CRIT · đánh vào thế đỡ hao Block Gauge +20%", "layer": &"spur_cua_bac", "order": 5},
	# ---------------------------------------------------------------- Mào
	&"mao_cat": {"name": "Mào cắt gọn", "slot": &"comb", "price": 100000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {"def": 1.0, "crit": 0.01}, "flags": {"high_hit_dmg_taken_mult": 0.9}, "power": 1.0,
		"text": "+1 DEF, +1% CRIT · sát thương nhận từ đòn cao −10%", "layer": &"comb_mao_cat", "order": 20},
	&"mao_dong": {"name": "Mào đồng", "slot": &"comb", "price": 700000, "currency": &"money", "shop": &"cho", "act": 2,
		"stats": {"def": 2.0, "hp": 10.0}, "flags": {"special_gain_mult": 1.1}, "power": 1.0,
		"text": "+2 DEF, +10 HP · Special Gauge tích nhanh 10%", "layer": &"comb_mao_dong", "order": 20},
	&"mao_vang_meo": {"name": "Mào vàng Lão Gà Khô", "slot": &"comb", "price": 4.0, "currency": &"kho_ga", "shop": &"meo",
		"act": 2, "stats": {"def": 2.0, "crit": 0.03}, "flags": {"special_gain_mult": 1.15}, "power": 1.0,
		"text": "Độc quyền Lão Gà Khô: +2 DEF, +3% CRIT · Special Gauge tích nhanh 15%",
		"layer": &"comb_mao_vang_meo", "order": 20},
	# ---------------------------------------------------------------- Vũ khí (GDD 5.2 – hành vi và đánh đổi đúng bảng)
	&"dao_chan": {"name": "Dao chân", "slot": &"weapon", "price": 200000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {}, "flags": {"light_startup": 3, "light_combo_extra": 1, "heavy_kb_mult": 0.9}, "power": 1.08,
		"text": "Light ra đòn nhanh (startup 3), combo thêm 1 Light · đánh đổi: Heavy −10% đẩy lùi",
		"layer": &"weapon_dao_chan", "order": 50},
	&"quat_long": {"name": "Quạt lông", "slot": &"weapon", "price": 350000, "currency": &"money", "shop": &"co_ba",
		"act": 2, "stats": {}, "flags": {"heavy_gust": true, "melee_dmg_mult": 0.8}, "power": 1.05,
		"text": "Heavy bắn luồng gió đẩy lùi, giữ khoảng cách · đánh đổi: cận chiến −20% sát thương",
		"layer": &"weapon_quat_long", "order": 50},
	&"non_bao_hiem": {"name": "Nón bảo hiểm", "slot": &"weapon", "price": 500000, "currency": &"money", "shop": &"co_ba",
		"act": 2, "stats": {}, "flags": {"heavy_rush": true, "heavy_armor_hits": 1, "heavy_startup_add": 6},
		"power": 1.06, "text": "Heavy thành cú húc lao tới, chịu được 1 đòn · đánh đổi: Heavy ra chậm hơn 6 frame",
		"layer": &"weapon_non_bao_hiem", "order": 50},
	# ---------------------------------------------------------------- Thức ăn
	&"lua": {"name": "Lúa", "slot": &"food", "price": 15000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {}, "effect": {"meal": true}, "text": "Bữa chính: Thể trạng về 100%, đêm nay hổng bị đói (GDD 6.1)"},
	&"cam": {"name": "Cám tăng lực", "slot": &"food", "price": 40000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {}, "effect": {"meal": false, "exp": 20}, "text": "+20 EXP (GDD 7.2) · hổng thay bữa chính"},
	&"thuoc_bo": {"name": "Thuốc bổ gà", "slot": &"food", "price": 50000, "currency": &"money", "shop": &"co_ba", "act": 1,
		"stats": {}, "effect": {"meal": false, "condition": 30}, "text": "+30% Thể trạng liền"},
	&"cam_cao_dam": {"name": "Cám cao đạm", "slot": &"food", "price": 150000, "currency": &"money", "shop": &"cho",
		"act": 2, "stats": {}, "effect": {"meal": false, "exp": 100}, "text": "+100 EXP · hổng thay bữa chính"},
	&"pate_meo": {"name": "Pate Lão Gà Khô", "slot": &"food", "price": 0.8, "currency": &"kho_ga", "shop": &"meo", "act": 2,
		"stats": {}, "effect": {"meal": true, "exp": 30}, "text": "Bữa chính hảo hạng: Thể trạng 100% + 30 EXP"},
	# ---------------------------------------------------------------- Trứng (ấp ở nhà + Biotech; rẻ hơn gà trưởng thành)
	&"trung_ga_tre": {"name": "Trứng gà tre", "slot": &"egg", "price": 150000, "currency": &"money", "shop": &"cho",
		"act": 2, "stats": {}, "breed": 1, "incubate_days": 2, "biotech_min": 1, "rarity": &"common",
		"text": "Ấp 2 ngày, tốn ít nhất 1 Biotech → Gà tre Lv1"},
	&"trung_ga_noi": {"name": "Trứng gà nòi", "slot": &"egg", "price": 250000, "currency": &"money", "shop": &"cho",
		"act": 2, "stats": {}, "breed": 0, "incubate_days": 2, "biotech_min": 1, "rarity": &"common",
		"text": "Ấp 2 ngày, tốn ít nhất 1 Biotech → Gà nòi Lv1"},
	&"trung_dong_tao": {"name": "Trứng Đông Tảo", "slot": &"egg", "price": 400000, "currency": &"money", "shop": &"cho",
		"act": 2, "stats": {}, "breed": 2, "incubate_days": 3, "biotech_min": 2, "rarity": &"rare",
		"text": "Giống hiếm. Ấp 3 ngày, tốn ít nhất 2 Biotech → Gà Đông Tảo Lv1"},
	&"trung_la": {"name": "Trứng lạ", "slot": &"egg", "price": 300000, "currency": &"money", "shop": &"cho", "act": 2,
		"stats": {}, "breed": -1, "incubate_days": 3, "biotech_min": 2, "rarity": &"rare",
		"text": "Hổng rõ giống. Bỏ nhiều Biotech dễ ra Đông Tảo và đột biến. Ấp 3 ngày"},
}


static func has(id: StringName) -> bool:
	return ITEMS.has(StringName(id))


static func get_item(id: StringName) -> Dictionary:
	return ITEMS.get(StringName(id), {})


static func display_name(id: StringName) -> String:
	return String(get_item(id).get("name", String(id)))


static func slot_of(id: StringName) -> StringName:
	return StringName(get_item(id).get("slot", &""))


## Món gắn được lên gà (vũ khí hoặc 5 ô trang bị).
static func is_equipment(id: StringName) -> bool:
	return SLOTS.has(slot_of(id))


static func is_food(id: StringName) -> bool:
	return slot_of(id) == &"food"


static func is_egg(id: StringName) -> bool:
	return slot_of(id) == &"egg"


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
