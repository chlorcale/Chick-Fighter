class_name Moves
extends RefCounted

## Bảng chiêu của chiến kê – theo D:/GameArt/rooster_fight_movelist.md và file
## rooster_fight_combo.aseprite (153 frame, 21 tag). Thời lượng mỗi frame lấy đúng từ file Aseprite
## (ms → tick 60 Hz), nên hoạt ảnh và frame data luôn khớp nhau.
##
## Nút (vẫn A S W D H J K L U I O):  J = L (nhẹ) · K = M (vừa) · L = H (mạnh) · H = S (đặc biệt)
## Hộp va chạm tính bằng pixel thế giới khi gà nhìn sang PHẢI, gốc ở chân; y âm là hướng lên.
## Sprite 128×112 phóng ×2, gốc chân ở (56, 105) trong ảnh.

enum Level { MID, HIGH, LOW }

const META_PATH: String = "res://game/art/rooster.json"
const HURT_STAND := Rect2(-44, -116, 86, 116)
const HURT_CROUCH := Rect2(-46, -74, 92, 74)
const HURT_AIR := Rect2(-40, -108, 80, 96)
const PUSH_HALF_WIDTH: float = 32.0

## Bộ chiêu (kit). Mỗi giống/chiến kê dùng một kit; gà nòi và gà tre dùng chung kit "rooster".
const KIT_ROOSTER: StringName = &"rooster"
const KIT_DONGTAO: StringName = &"dongtao"
const DongTaoKit = preload("res://game/battle/kit_dongtao.gd")

## Phản ứng của bên trúng đòn → tag hoạt ảnh + thời gian khóa (tick).
## Hitstun dài hơn hoạt ảnh một chút để các combo trong bảng chiêu nối được.
const REACTIONS: Dictionary = {
	&"nhe": {"tag": "HIT_Nhe", "stun": 20},
	&"nang": {"tag": "HIT_Nang", "stun": 34},
	&"te": {"tag": "TE_NgaNgua", "stun": 32},
	&"vang": {"tag": "VANG_RaXa", "stun": 46},
}
const DOWN_TICKS: int = 30          # NAM_Dat sau khi té / văng
const BLOCKSTUN: Dictionary = {"L": 16, "M": 18, "H": 22, "SP": 10, "SUPER": 0, "PROJ": 8}
const CANCEL_WINDOW_TICKS: int = 8  # cửa sổ nối đòn kể từ lúc chạm (trúng hoặc bị đỡ)

## Một đòn:
##  tag      tag Aseprite; frames lấy theo tag
##  cat      L | M | H | SP | SUPER | TAUNT – dùng cho luật cancel
##  hits     [{frames: [chỉ số frame trong tag], dmg, react, level, kb, hitstop, box, launch?}]
##  cancel   các nhóm được nối sang khi đòn đã chạm (JUMP = nhảy hủy)
##  loop     [từ, đến, số vòng tối đa] – đòn rush bấm S liên tục để lặp
##  cost     vạch Special Gauge
const TABLE: Dictionary = {
	&"mo_nhanh": {"name": "Mổ Nhanh", "tag": "L_MoNhanh", "cat": "L",
		"hits": [{"frames": [2], "dmg": 5, "react": &"nhe", "level": Level.MID, "kb": 8.0, "hitstop": 4,
			"box": Rect2(40, -98, 76, 44)}],
		"cancel": ["L", "M", "SP", "SUPER"]},
	&"da_nhe": {"name": "Đá Nhẹ", "tag": "light_kick", "cat": "L",
		"hits": [{"frames": [2], "dmg": 6, "react": &"nhe", "level": Level.MID, "kb": 10.0, "hitstop": 4,
			"box": Rect2(36, -72, 82, 58)}],
		"cancel": ["L", "M", "SP", "SUPER"]},
	&"tat_canh": {"name": "Tát Cánh", "tag": "M_TatCanh", "cat": "M",
		"hits": [{"frames": [2, 3], "dmg": 8, "react": &"nang", "level": Level.MID, "kb": 18.0, "hitstop": 6,
			"box": Rect2(28, -116, 106, 76)}],
		"cancel": ["H", "SP", "SUPER"]},
	&"cua_hat": {"name": "Cựa Hất", "tag": "H_CuaHat", "cat": "H",
		"hits": [{"frames": [2, 3], "dmg": 11, "react": &"vang", "level": Level.MID, "kb": 70.0, "hitstop": 8,
			"launch": 640.0, "box": Rect2(18, -170, 92, 136)}],
		"cancel": ["JUMP", "SP"]},
	&"da_cua_bay": {"name": "Đá Cựa Bay", "tag": "heavy_kick", "cat": "H",
		"hits": [{"frames": [5, 6], "dmg": 16, "react": &"te", "level": Level.MID, "kb": 90.0, "hitstop": 9,
			"box": Rect2(40, -112, 124, 84)}],
		"cancel": []},
	&"mo_thap": {"name": "Mổ Thấp", "tag": "L_MoNhanh", "cat": "L", "crouch": true, "squash": 0.82,
		"hits": [{"frames": [2], "dmg": 4, "react": &"nhe", "level": Level.LOW, "kb": 12.0, "hitstop": 4,
			"box": Rect2(36, -48, 80, 48)}],
		"cancel": ["L", "M"]},
	&"quet_canh": {"name": "Quét Cánh", "tag": "M_TatCanh", "cat": "M", "crouch": true, "squash": 0.78,
		"hits": [{"frames": [2, 3], "dmg": 7, "react": &"te", "level": Level.LOW, "kb": 30.0, "hitstop": 6,
			"box": Rect2(26, -44, 104, 44)}],
		"cancel": []},
	&"air_j": {"name": "Đá Nhẹ trên không", "tag": "light_kick", "cat": "L", "air": true,
		"hits": [{"frames": [2, 3], "dmg": 5, "react": &"nhe", "level": Level.HIGH, "kb": 16.0, "hitstop": 4,
			"box": Rect2(14, -76, 100, 84)}],
		"cancel": []},
	&"air_k": {"name": "Tát Cánh trên không", "tag": "M_TatCanh", "cat": "M", "air": true,
		"hits": [{"frames": [2, 3], "dmg": 7, "react": &"nang", "level": Level.HIGH, "kb": 40.0, "hitstop": 6,
			"box": Rect2(14, -104, 110, 100)}],
		"cancel": []},
	&"air_l": {"name": "Đá Cựa trên không", "tag": "heavy_kick", "cat": "H", "air": true,
		"hits": [{"frames": [5, 6], "dmg": 10, "react": &"te", "level": Level.HIGH, "kb": 70.0, "hitstop": 8,
			"box": Rect2(24, -90, 120, 100)}],
		"cancel": []},
	&"mo_lien_hoan": {"name": "Mổ Liên Hoàn", "tag": "SP_MoLienHoan", "cat": "SP", "cost": 1,
		"freeze_text": "MỔ LIÊN HOÀN!", "loop": [2, 7, 3],
		"hits": [
			{"frames": [2], "dmg": 2, "react": &"nhe", "level": Level.MID, "kb": 4.0, "hitstop": 2, "box": Rect2(36, -104, 112, 58), "loop": true},
			{"frames": [3], "dmg": 2, "react": &"nhe", "level": Level.MID, "kb": 4.0, "hitstop": 2, "box": Rect2(36, -104, 112, 58), "loop": true},
			{"frames": [4], "dmg": 2, "react": &"nhe", "level": Level.MID, "kb": 4.0, "hitstop": 2, "box": Rect2(36, -104, 112, 58), "loop": true},
			{"frames": [5], "dmg": 2, "react": &"nhe", "level": Level.MID, "kb": 4.0, "hitstop": 2, "box": Rect2(36, -104, 112, 58), "loop": true},
			{"frames": [6], "dmg": 2, "react": &"nhe", "level": Level.MID, "kb": 4.0, "hitstop": 2, "box": Rect2(36, -104, 112, 58), "loop": true},
			{"frames": [7], "dmg": 2, "react": &"nhe", "level": Level.MID, "kb": 4.0, "hitstop": 2, "box": Rect2(36, -104, 112, 58), "loop": true},
			{"frames": [8], "dmg": 8, "react": &"vang", "level": Level.MID, "kb": 130.0, "hitstop": 10, "launch": 520.0,
				"box": Rect2(36, -108, 116, 66)},
		],
		"cancel": []},
	&"phun_long": {"name": "Phun Lông", "tag": "SP_PhunLong", "cat": "SP", "spawn": 2, "hits": [], "cancel": []},
	&"loc_xoay_canh": {"name": "Lốc Xoáy Cánh", "tag": "SUP_LocXoayCanh", "cat": "SUPER", "cost": 2,
		"unblockable": true, "pull": [2, 8], "freeze_text": "LỐC XOÁY CÁNH!",
		"hits": [
			{"frames": [3], "dmg": 3, "react": &"nang", "level": Level.MID, "kb": 0.0, "hitstop": 2, "box": Rect2(-160, -190, 320, 190)},
			{"frames": [4], "dmg": 3, "react": &"nang", "level": Level.MID, "kb": 0.0, "hitstop": 2, "box": Rect2(-160, -190, 320, 190)},
			{"frames": [5], "dmg": 3, "react": &"nang", "level": Level.MID, "kb": 0.0, "hitstop": 2, "box": Rect2(-160, -190, 320, 190)},
			{"frames": [6], "dmg": 3, "react": &"nang", "level": Level.MID, "kb": 0.0, "hitstop": 2, "box": Rect2(-160, -190, 320, 190)},
			{"frames": [7], "dmg": 3, "react": &"nang", "level": Level.MID, "kb": 0.0, "hitstop": 2, "box": Rect2(-160, -190, 320, 190)},
			{"frames": [8], "dmg": 3, "react": &"nang", "level": Level.MID, "kb": 0.0, "hitstop": 2, "box": Rect2(-160, -190, 320, 190)},
			{"frames": [9], "dmg": 12, "react": &"vang", "level": Level.MID, "kb": 220.0, "hitstop": 14, "launch": 760.0,
				"box": Rect2(-170, -210, 340, 210)},
		],
		"cancel": []},
	&"gay_thi_uy": {"name": "Gáy Thị Uy", "tag": "TAUNT_GayThiUy", "cat": "TAUNT", "gain_frame": 6, "hits": [], "cancel": []},
}

## Danh sách hiển thị trong menu tạm dừng.
const MOVE_LIST: Array = [
	["Mổ Nhanh", "J"], ["Đá Nhẹ", "→ + J  (hoặc J thứ hai trong chuỗi)"], ["Tát Cánh", "K"],
	["Đá Cựa Bay (đánh ngã)", "L"], ["Cựa Hất (hất tung, chống nhảy)", "↓ + L"],
	["Mổ Thấp / Quét Cánh (đòn thấp)", "↓ + J / ↓ + K"], ["Đòn trên không", "J / K / L khi nhảy"],
	["Mổ Liên Hoàn – 1 vạch (bấm H liên tục)", "H   hoặc  → ↓ ↘ + H"],
	["Phun Lông (bắn lông)", "↓ + H   hoặc  ↓ ↘ → + H"],
	["LỐC XOÁY CÁNH – 2 vạch, không đỡ được", "← + H   hoặc  ↓ ↘ → ↓ ↘ → + H"],
	["Gáy Thị Uy (+25% thanh nộ)", "H + L cùng lúc"],
	["Đỡ bằng cánh (cúi + lùi: đỡ đòn thấp)", "giữ lùi (ngược hướng đối thủ)"],
	["Lướt", "bấm đúp ← hoặc →"],
]

const COMBOS: String = "Combo: J J K L · K ↓L nhảy J · J K H (bấm H liên tục) · J K ←H"

const ANIMS: Dictionary = {
	"idle": "idle", "walk_f": "run_right", "walk_b": "run_left", "guard": "GUARD_DoCanh",
	"guard_hit": "GUARD_DoCanh", "nhe": "HIT_Nhe", "nang": "HIT_Nang", "te": "TE_NgaNgua",
	"nam": "NAM_Dat", "vang": "VANG_RaXa", "dung": "DUNG_Day", "taunt": "TAUNT_GayThiUy",
}

static var _meta: Dictionary = {}
static var _cache: Dictionary = {}
static var _kits: Dictionary = {}


## Thông số của một kit (hình, gốc chân, hộp thân, luật riêng). Kết quả được lưu đệm.
##  te_ticks/wake_ticks/wake_invuln/wake_armor: thời lượng té, đứng dậy, bất tử và giáp khi dậy (tick)
##  vang_fly_last / vang_land: frame cuối lúc bay và các frame tiếp đất trong tag VANG_RaXa (0-based)
##  guard_all_heights: đỡ được mọi tầng đòn; guard_cost_mult: hệ số tốn Block Gauge; guard_push: hệ số bị đẩy khi đỡ
##  ai: lệnh cho AI – [nút, hướng] với hướng "" | "fwd" | "back" | "down" | "H" (bấm kèm nút H)
static func kit(kit_id: StringName) -> Dictionary:
	if _kits.has(kit_id):
		return _kits[kit_id]
	var k: Dictionary
	match kit_id:
		KIT_DONGTAO:
			k = {
				"id": KIT_DONGTAO, "meta": "res://game/art/dongtao.json",
				"sheet": load("res://game/art/dongtao_sheet.png"), "mask": load("res://game/art/dongtao_mask.png"),
				"foot": Vector2(57, 105), "x_comp": 10.0, "table": DongTaoKit.TABLE, "move_list": DongTaoKit.MOVE_LIST,
				"combos": DongTaoKit.COMBOS, "anims": DongTaoKit.ANIMS,
				"hurt_stand": Rect2(-50, -124, 100, 124), "hurt_crouch": Rect2(-50, -124, 100, 124),
				"hurt_air": Rect2(-48, -116, 96, 104), "push_half": 38.0,
				"can_jump": false, "can_crouch": false, "can_dash": false,
				"te_ticks": 43, "wake_ticks": 62, "wake_invuln": 37, "wake_armor": 1,
				"vang_fly_last": 6, "vang_land": [7, 11], "vang_land_ticks": 28,
				"guard_all_heights": true, "guard_cost_mult": 1.5, "guard_push": 0.15,
				"taunt": &"dam_nguc", "portrait": Rect2(60, 40, 40, 40),
				"ai": {"rush": [&"S", ""], "quake": [&"S", "down"], "counter": [&"S", "back"],
					"super": [&"S", "fwd"], "taunt": [&"S", "H"]},
			}
		_:
			k = {
				"id": KIT_ROOSTER, "meta": META_PATH,
				"sheet": load("res://game/art/rooster_sheet.png"), "mask": load("res://game/art/rooster_mask.png"),
				"foot": Vector2(56, 105), "x_comp": 12.0, "table": TABLE, "move_list": MOVE_LIST,
				"combos": COMBOS, "anims": ANIMS,
				"hurt_stand": HURT_STAND, "hurt_crouch": HURT_CROUCH, "hurt_air": HURT_AIR, "push_half": PUSH_HALF_WIDTH,
				"can_jump": true, "can_crouch": true, "can_dash": true,
				"te_ticks": int(REACTIONS[&"te"]["stun"]), "wake_ticks": 41, "wake_invuln": 35, "wake_armor": 0,
				"vang_fly_last": 7, "vang_land": [8, 10], "vang_land_ticks": 15,
				"guard_all_heights": false, "guard_cost_mult": 1.0, "guard_push": 1.0,
				"taunt": &"gay_thi_uy", "portrait": Rect2(50, 36, 40, 40),
				"ai": {"rush": [&"S", ""], "projectile": [&"S", "down"], "super": [&"S", "back"], "taunt": [&"S", "H"],
					"launcher": [&"H", "down"], "sweep": [&"M", "down"], "low": [&"L", "down"]},
			}
	_kits[kit_id] = k
	return k


## Kit của một bên đấu: khóa "kit" nếu có, không thì theo giống (Gà Đông Tảo → dongtao).
static func kit_for_side(side: Dictionary) -> StringName:
	if side.has("kit"):
		return StringName(side["kit"])
	if int(side.get("breed", 0)) == MovementConfig.Breed.GA_DONG_TAO:
		return KIT_DONGTAO
	return KIT_ROOSTER


static func move_list(kit_id: StringName = KIT_ROOSTER) -> Array:
	return kit(kit_id)["move_list"]


static func meta(kit_id: StringName = KIT_ROOSTER) -> Dictionary:
	if kit_id == KIT_ROOSTER:
		if _meta.is_empty():
			_meta = JSON.parse_string(FileAccess.open(META_PATH, FileAccess.READ).get_as_text())
		return _meta
	var k: Dictionary = kit(kit_id)
	if not k.has("_meta"):
		k["_meta"] = JSON.parse_string(FileAccess.open(String(k["meta"]), FileAccess.READ).get_as_text())
	return k["_meta"]


## Số tick 60 Hz của một frame trong sheet (1-based).
static func frame_ticks(frame: int, kit_id: StringName = KIT_ROOSTER) -> int:
	var ms: float = float(meta(kit_id)["durations"][frame - 1])
	return maxi(1, int(round(ms * 0.06)))


## Các frame (1-based) của một tag.
static func tag_frames(tag: String, kit_id: StringName = KIT_ROOSTER) -> Array[int]:
	var range_pair: Array = meta(kit_id)["tags"][tag]
	var out: Array[int] = []
	for f in range(int(range_pair[0]), int(range_pair[1]) + 1):
		out.append(f)
	return out


static func tag_ticks(tag: String, kit_id: StringName = KIT_ROOSTER) -> int:
	var total: int = 0
	for f in tag_frames(tag, kit_id):
		total += frame_ticks(f, kit_id)
	return total


static func has_move(move_id: StringName, kit_id: StringName = KIT_ROOSTER) -> bool:
	return (kit(kit_id)["table"] as Dictionary).has(move_id)


## Mọi id đòn của một kit.
static func move_ids(kit_id: StringName = KIT_ROOSTER) -> Array:
	return (kit(kit_id)["table"] as Dictionary).keys()


## Trả về đòn kèm frames, ticks từng frame và AttackData cho từng nhịp đánh, cùng số liệu suy ra
## (startup, total, reach = tầm xa nhất phía trước, recovery = số tick sau nhịp cuối) cho AI.
static func get_move(move_id: StringName, kit_id: StringName = KIT_ROOSTER) -> Dictionary:
	var key: String = String(kit_id) + ":" + String(move_id)
	if _cache.has(key):
		return _cache[key]
	var move: Dictionary = (kit(kit_id)["table"][move_id] as Dictionary).duplicate(true)
	move["id"] = move_id
	move["kit"] = kit_id
	move["frames"] = tag_frames(String(move["tag"]), kit_id)
	var ticks: Array[int] = []
	for f in move["frames"]:
		ticks.append(frame_ticks(f, kit_id))
	move["ticks"] = ticks
	var first_active: int = 999
	var last_active: int = -1
	var reach: float = 0.0
	for hit in move["hits"]:
		first_active = mini(first_active, int(hit["frames"][0]))
		last_active = maxi(last_active, int(hit["frames"][-1]))
		reach = maxf(reach, (hit["box"] as Rect2).end.x)
		var heavy: bool = String(move["cat"]) != "L"
		var data: AttackData = AttackCatalog.get_attack(&"heavy" if heavy else &"light")
		data.hit_level = [AttackData.HitLevel.MID, AttackData.HitLevel.HIGH, AttackData.HitLevel.LOW][int(hit["level"])]
		data.base_knockback_px = float(hit["kb"])
		data.hitstop_ticks = int(hit["hitstop"])
		hit["data"] = data
	var startup: int = 0
	for i in range(mini(first_active, ticks.size())):
		startup += ticks[i]
	move["startup"] = startup
	var total: int = 0
	for t in ticks:
		total += t
	move["total"] = total
	move["reach"] = reach
	var recovery: int = 0
	if last_active >= 0:
		for i in range(last_active + 1, ticks.size()):
			recovery += ticks[i]
	move["recovery"] = recovery
	_cache[key] = move
	return move


static func world_rect(local: Rect2, origin: Vector2, facing: int) -> Rect2:
	if facing >= 0:
		return Rect2(origin + local.position, local.size)
	return Rect2(Vector2(origin.x - local.position.x - local.size.x, origin.y + local.position.y), local.size)
