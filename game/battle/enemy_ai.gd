class_name EnemyAI
extends RefCounted

## Enemy AI theo GDD 4.10 (Approach / Poke / Punish / Defend / Space / Zone), mở rộng thành AI đối kháng
## theo Tier 1–4 (T4 – Olympic/Hell Mode: phản xạ ~180–250 ms, đỡ ≥ 65%, trừng phạt tối ưu, xoay thẻ đúng lúc, học
## thói quen nhanh gấp đôi). Biết dùng vũ khí: Quạt lông (Heavy K bắn gió giữ khoảng cách), Nón bảo hiểm (Húc Nón có giáp
## xuyên đòn), Dao chân (chuỗi L-L-L-M); Cánh Tiến Hóa (nhảy lần hai). Chế độ báo công an: `relentless` dồn ép liên tục. AI CHỈ xuất bitmask input logic (InputBits) mỗi tick; trận xử lý y như phím người chơi.
## Nút: LIGHT = J (L), HEAVY = K (M), SPECIAL = L (H), ACTION_H = H (S).
##
## Nhận thức có độ trễ: mọi thông tin về hành động của đối thủ lấy từ ảnh chụp `view` cách đây
## `reaction_ticks` tick (không đọc input của đối thủ). Khoảng cách/vị trí bản thân dùng hiện tại.
## Tầm đánh lấy từ bảng chiêu của kit (Moves.get_move()["reach"/"startup"/"recovery"]).
##
## PLACEHOLDER: mọi hệ số theo tier/skill bên dưới (tốc độ phản xạ, tỉ lệ đỡ đúng tầng, chống nhảy,
## trừng phạt, độ dài combo, do dự) – chỉnh bằng các trận AI-vs-AI có seed (tests/game/run_ai_batch.gd).

enum State { APPROACH, POKE, PUNISH, DEFEND, SPACE, ZONE, OKI }

## Kịch bản riêng cho trận hướng dẫn (GDD 8.4).
enum Mode { NONE, PASSIVE, SLOW_ATTACK, IDLE }

const L := InputBits.LIGHT
const M := InputBits.HEAVY
const H := InputBits.SPECIAL
const S := InputBits.ACTION_H
const LEFT := InputBits.MOVE_LEFT
const RIGHT := InputBits.MOVE_RIGHT
const UP := InputBits.JUMP
const DOWN := InputBits.CROUCH

## Vai trò → [nút, hướng] theo kit. Hướng: "" | "fwd" | "back" | "down" | "motion_super".
const ROLES: Dictionary = {
	&"rooster": {
		"jab": [L, ""], "mid": [M, ""], "heavy": [H, ""], "low": [L, "down"], "sweep": [M, "down"],
		"anti_air": [H, "down"], "rush": [S, ""], "projectile": [S, "down"], "super": [S, "back"],
	},
	&"dongtao": {
		"jab": [L, ""], "mid": [M, ""], "heavy": [H, ""], "low": [M, ""], "sweep": [S, "down"],
		"anti_air": [H, ""], "rush": [S, ""], "quake": [S, "down"], "counter": [S, "back"],
		"super": [S, "motion_super"],
	},
}
## Vai trò → id đòn trong bảng chiêu (để đọc tầm/khởi động/hồi).
const ROLE_MOVES: Dictionary = {
	&"rooster": {"jab": &"mo_nhanh", "mid": &"tat_canh", "heavy": &"da_cua_bay", "low": &"mo_thap",
		"sweep": &"quet_canh", "anti_air": &"cua_hat", "rush": &"mo_lien_hoan", "projectile": &"phun_long",
		"super": &"loc_xoay_canh"},
	&"dongtao": {"jab": &"huc_dau", "mid": &"dam_chan", "heavy": &"da_tru", "low": &"dam_chan",
		"sweep": &"dia_chan", "anti_air": &"da_tru", "rush": &"huc_trau", "quake": &"dia_chan",
		"counter": &"phan_don", "super": &"thai_son"},
}
## Combo theo kit: [các vai trò], số vạch cần, tier tối thiểu. Mọi bước đều là cancel có trong bảng chiêu.
const ROUTES: Dictionary = {
	&"rooster": [
		[["jab", "jab", "mid", "heavy"], 0, 2], [["jab", "mid", "heavy"], 0, 1], [["jab", "mid", "rush"], 1, 2],
		[["jab", "mid", "super"], 2, 2], [["mid", "heavy"], 0, 1], [["low", "jab", "mid"], 0, 2],
		[["mid", "rush"], 1, 1], [["jab", "jab"], 0, 1], [["low", "sweep"], 0, 2],
		[["jab", "jab", "jab", "mid"], 0, 2, "dao"],
	],
	&"dongtao": [
		[["jab", "mid", "heavy"], 0, 1], [["jab", "mid", "super"], 2, 2], [["mid", "quake"], 0, 2],
		[["jab", "heavy"], 0, 1], [["mid", "heavy"], 0, 1], [["jab", "jab", "mid", "heavy"], 0, 3],
		[["jab", "jab", "jab", "mid"], 0, 2, "dao"],
	],
}

var tier: int = 1
var skill: float = 0.2
var reaction_ticks: int = 30      # T1 ≈ 0,45 s, T3 ≈ 0,22 s
var block_rate: float = 0.1
var aggression: float = 0.5
var jumpiness: float = 0.0
var uses_mai_rua: bool = false
var script_mode: int = Mode.NONE
var kit: StringName = &"rooster"
## Báo công an: dồn ép, không lùi giữ khoảng cách.
var relentless: bool = false
## Vũ khí (từ cờ hành vi của bên đấu).
var gust_weapon: bool = false
var armor_rush: bool = false
var extra_light: int = 0

var state: int = State.APPROACH
## Thói quen đối thủ đã ghi nhận (giảm dần theo thời gian) – AI đổi lựa chọn theo đó.
var habits: Dictionary = {"jumps": 0.0, "lows": 0.0, "blocks": 0.0, "specials": 0.0, "whiffs": 0.0, "hits": 0.0}

var _rng := RandomNumberGenerator.new()
var _tick: int = 0
var _think_timer: int = 0
var _state_ticks: int = 0
var _pause_ticks: int = 0
var _cooldown: int = 0
var _route: Array = []
var _route_index: int = 0
var _route_blocked_stop: bool = false
var _script_timer: int = 0
var _queue: Array[int] = []
var _history: Array[Dictionary] = []
var _prev_seen: Dictionary = {}
var _defend_ticks: int = 0
var _guard_low: bool = false
var _reacted_serial: int = -1
var _punished_serial: int = -1
var _aa_serial: int = -1
var _recent: Array[String] = []
var _passive_ticks: int = 0
var _jump_attack: bool = false
var _info: Dictionary = {}
var _proj_tick: int = -1000
var _routes: Array = []

# Hệ số theo skill (PLACEHOLDER).
var _block_skill: float = 0.2     # đỡ đúng khi thấy đòn
var _height_skill: float = 0.5    # đoán đúng tầng (cao/thấp)
var _anti_air: float = 0.1
var _punish: float = 0.3
var _whiff_punish: float = 0.1
var _combo_skill: float = 0.2
var _hesitate: float = 0.3
var _meter_smart: float = 0.2
var _habit_k: float = 3.0         # ngưỡng "đã thấy thói quen" (T4 học nhanh hơn)
var _habit_decay: float = 0.5
var _card_tick: int = -1000


func configure(config: Dictionary, rng_seed: int) -> void:
	tier = clampi(int(config.get("tier", 1)), 1, 4)
	skill = clampf(float(config.get("skill", [0.0, 0.2, 0.6, 0.9, 1.0][tier])), 0.0, 1.0)
	var flags: Dictionary = config.get("flags", {})
	gust_weapon = bool(flags.get("heavy_gust", false))
	armor_rush = bool(flags.get("heavy_rush", false))
	extra_light = int(flags.get("light_combo_extra", 0))
	relentless = bool(config.get("relentless", false))
	kit = StringName(config.get("kit", Moves.kit_for_side(config)))
	if not ROLES.has(kit):
		kit = &"rooster"
	reaction_ticks = int(round(30.0 - 17.0 * skill))
	block_rate = float(config.get("block", 0.1 if tier <= 1 else 0.3))
	aggression = float(config.get("aggr", 0.5))
	jumpiness = float(config.get("jumpy", 0.0)) if bool(Moves.kit(kit)["can_jump"]) else 0.0
	uses_mai_rua = (config.get("cards", []) as Array).has(&"mai_rua")
	_block_skill = 0.12 + 0.75 * skill
	_height_skill = 0.45 + 0.5 * skill
	_anti_air = 0.05 + 0.85 * skill
	_punish = 0.15 + 0.8 * skill
	_whiff_punish = maxf(0.0, skill - 0.25) * 1.2
	_combo_skill = skill
	_hesitate = 0.35 * (1.0 - skill) + 0.04
	_meter_smart = skill
	if tier >= 4:
		# T4 (GDD 4.10: phản xạ 180 ms, đỡ 65%, đầy đủ, đọc nhảy, thẻ + Special tối ưu) – vẫn chỉ xuất bit input.
		reaction_ticks = int(round(10.0 + 4.0 * (1.0 - skill)))
		block_rate = maxf(block_rate, 0.65)
		_block_skill = maxf(_block_skill, 0.85)
		_height_skill = maxf(_height_skill, 0.92)
		_anti_air = maxf(_anti_air, 0.85)
		_punish = maxf(_punish, 0.95)
		_whiff_punish = maxf(_whiff_punish, 0.8)
		_combo_skill = 1.0
		_hesitate = 0.03
		_meter_smart = 1.0
		_habit_k = 1.5
		_habit_decay = 0.75
		_anti_air = maxf(_anti_air, 0.95)
		_punish = 1.0
		_whiff_punish = maxf(_whiff_punish, 0.95)
		jumpiness *= 0.5 # không nhảy bừa vào đòn chống nhảy
	if relentless:
		aggression = 1.0
		_hesitate *= 0.3
	_rng.seed = rng_seed
	for role in ROLE_MOVES[kit].keys():
		_info[role] = Moves.weapon_move(ROLE_MOVES[kit][role], kit, flags)
	# Chỉ giữ các combo mà mọi bước nối đều có trong danh sách cancel của bảng chiêu (đã áp vũ khí).
	_routes = []
	for route in ROUTES[kit]:
		if route.size() > 3 and String(route[3]) == "dao" and extra_light <= 0:
			continue
		if _route_valid(route[0]):
			_routes.append(route)


func _route_valid(roles: Array) -> bool:
	for i in range(1, roles.size()):
		var prev: Dictionary = _info[String(roles[i - 1])]
		var next: Dictionary = _info[String(roles[i])]
		if not (prev["cancel"] as Array).has(String(next["cat"])):
			return false
	return true


func reach(role: String) -> float:
	return float(_info[role]["reach"]) if _info.has(role) else 0.0


func think(view: Dictionary) -> int:
	_tick += 1
	_history.append(view)
	if _history.size() > 48:
		_history.pop_front()
	var seen: Dictionary = _history[maxi(0, _history.size() - 1 - reaction_ticks)]
	var dx: float = float(view["dx"])
	var distance: float = float(view["distance"])
	var toward: int = RIGHT if dx > 0.0 else LEFT
	var away: int = LEFT if dx > 0.0 else RIGHT
	if _cooldown > 0:
		_cooldown -= 1
	_learn(seen)

	match script_mode:
		Mode.IDLE:
			return 0
		Mode.PASSIVE:
			_script_timer += 1
			if distance > 230.0 and (_script_timer / 40) % 2 == 0:
				return _bit(toward)
			return 0
		Mode.SLOW_ATTACK:
			_script_timer += 1
			if bool(view["my_locked"]) or bool(view["my_busy"]):
				return 0
			if distance > 150.0:
				return _bit(toward)
			return _bit(L) if _script_timer % 75 == 0 else 0

	# Đối đầu rush / kéo dài rush: bấm S liên tục.
	if bool(view["rush_clash"]) or bool(view["my_rush_loop"]):
		var rate: int = 8 if tier <= 1 else 5
		return _bit(S) if (_tick % rate) < rate / 2 else 0
	if not _queue.is_empty():
		return _queue.pop_front()
	if bool(view["my_locked"]):
		_route = []
		return 0
	# Cánh Tiến Hóa: nhảy lần hai ở gần đỉnh (né đòn chống nhảy / thoát góc).
	if bool(view["my_airborne"]) and bool(view.get("my_can_air_jump", false)) and tier >= 2 and not bool(view["my_busy"]) \
			and absf(float(view.get("my_vy", 999.0))) < 140.0 and _rng.randf() < 0.1 + 0.25 * skill:
		_note("air_jump")
		return _bit(UP) | (_bit(away) if bool(view["my_at_wall"]) else _bit(toward))

	# Thẻ: Mai Rùa khi HP < 50% (Bảng 4.9), Cuồng Nộ khi sắp ép đòn.
	var card_out: int = _cards(view, distance)
	if card_out != 0:
		return card_out

	# Đang ra đòn: nối combo khi đòn trước vừa chạm.
	if bool(view["my_busy"]):
		return _continue_route(view, toward, away)

	var lead: float = float(view["my_hp_ratio"]) - float(view["opp_hp_ratio"])
	var desperate: bool = int(view.get("opp_rounds", 0)) >= int(view.get("rounds_needed", 2)) - 1 \
		and int(view.get("opp_rounds", 0)) > int(view.get("my_rounds", 0))

	# ---- phản ứng tức thời (với nhận thức trễ) ----
	var react: int = _react(view, seen, distance, toward, away, lead)
	if react >= 0:
		return react

	# Đang giữ thủ.
	if _defend_ticks > 0:
		_defend_ticks -= 1
		var guard_bits: int = _bit(away)
		if _guard_low and bool(Moves.kit(kit)["can_crouch"]):
			guard_bits |= _bit(DOWN)
		return guard_bits

	# ---- trung lập ----
	_think_timer -= 1
	_state_ticks += 1
	if _think_timer <= 0:
		_think_timer = maxi(4, reaction_ticks / 2 + _rng.randi_range(-3, 6))
		_decide(view, seen, distance, lead, desperate)

	var held: int = 0
	match state:
		State.APPROACH:
			held |= _bit(toward)
			if _jump_attack and not bool(view["my_airborne"]) and distance < 330.0:
				_jump_attack = false
				_note("jump")
				held |= _bit(UP)
		State.SPACE:
			if not bool(view["my_at_wall"]) and _state_ticks == 1 and distance < 150.0 					and bool(Moves.kit(kit)["can_dash"]) and _rng.randf() < 0.15 + 0.35 * skill:
				_queue = [0, _bit(away)] # lướt lùi (bấm đúp lùi)
				_note("backdash")
				held |= _bit(away)
			elif not bool(view["my_at_wall"]):
				held |= _bit(away)
			elif distance < 200.0:
				held |= _start_route(view, distance)
		State.ZONE:
			if _cooldown == 0 and gust_weapon and not bool(view.get("my_gust_out", false)) and distance > 150.0:
				held |= _press("mid", toward, away) # Quạt lông: tát cánh hụt → bắn luồng gió
				_note("gust")
			elif _cooldown == 0 and _info.has("projectile") and not bool(view["my_projectile"]):
				held |= _press("projectile", toward, away)
				_note("zone")
			state = State.SPACE if not relentless else State.APPROACH
		State.DEFEND:
			held |= _bit(away)
			if _guard_low and bool(Moves.kit(kit)["can_crouch"]):
				held |= _bit(DOWN)
			if _state_ticks > 24 + int(30.0 * block_rate) and not bool(seen["opp_attacking"]):
				state = State.POKE
		State.OKI:
			held |= _okizeme(view, seen, distance, toward, away)
		State.PUNISH:
			if _cooldown == 0:
				held |= _start_route(view, distance)
			state = State.POKE
		State.POKE:
			if bool(view["my_airborne"]):
				if _cooldown == 0 and distance < 170.0:
					held |= _tap(M if _rng.randf() < 0.5 else L)
			elif _pause_ticks > 0:
				_pause_ticks -= 1
				if distance > reach("jab") + 20.0:
					held |= _bit(toward)
			elif distance > reach("jab") + 4.0:
				held |= _bit(toward)
			elif _cooldown == 0:
				held |= _start_route(view, distance)
				_pause_ticks = int(_rng.randf_range(10.0, 40.0) * (1.5 - aggression) * (1.3 - skill * 0.6) * (0.5 if tier >= 4 else 1.0))
	return held


# =================================================================== phản ứng

## Trả về bitmask khi có phản ứng (≥ 0), -1 khi không.
func _react(view: Dictionary, seen: Dictionary, distance: float, toward: int, away: int, lead: float) -> int:
	if bool(view["my_airborne"]):
		return -1
	var serial: int = int(seen["opp_move_serial"])
	var est_active: int = int(seen["opp_ticks_to_active"]) - reaction_ticks
	var opp_reach: float = float(seen["opp_reach"])

	# Siêu chiêu/sóng chấn mặt đất không đỡ được (Thái Sơn, Địa Chấn): nhảy đúng lúc nếu kit nhảy được.
	if bool(seen["opp_attacking"]) and bool(seen["opp_ground_only"]) and bool(Moves.kit(kit)["can_jump"]) \
			and serial != _reacted_serial and distance < opp_reach + 60.0 + (2000.0 if bool(seen["opp_unblockable"]) else 0.0):
		if est_active <= 12 and est_active >= -2:
			_reacted_serial = serial
			if _rng.randf() < 0.25 + 0.7 * skill:
				_note("dodge")
				return _bit(UP)

	# Siêu chiêu hút (Lốc Xoáy Cánh): không đỡ được – lùi xa hết mức.
	if String(seen["opp_move_cat"]) == "SUPER" and bool(seen["opp_unblockable"]) and not bool(seen["opp_ground_only"]) 			and _rng.randf() < 0.3 + 0.6 * skill:
		return _bit(away)

	# Đòn đang tới gần: đỡ (đúng tầng theo kỹ năng), phản đòn (Đông Tảo), hoặc lướt lùi.
	if bool(seen["opp_attacking"]) and serial != _reacted_serial and distance < opp_reach + 70.0 \
			and not bool(seen["opp_unblockable"]):
		_reacted_serial = serial
		var p_block: float = clampf(block_rate * 0.6 + _block_skill * 0.7 + (0.15 if lead > 0.2 else 0.0)
			+ (0.1 if float(habits["specials"]) > _habit_k and String(seen["opp_move_cat"]) in ["SP", "SUPER"] else 0.0), 0.05, 0.95)
		if _info.has("counter") and est_active >= 2 and est_active <= 7 and _rng.randf() < 0.15 + 0.35 * skill:
			_note("counter")
			return _press("counter", toward, away)
		# Nón bảo hiểm: húc xuyên đòn bằng giáp (giáp có từ frame đầu) khi đòn đối thủ còn chưa ra.
		if armor_rush and est_active >= 3 and distance < reach("mid") + 90.0 and not _repetitive("helmet") \
				and _rng.randf() < 0.15 + 0.35 * skill:
			_note("helmet")
			return _press("mid", toward, away)
		if _rng.randf() < p_block:
			var low: bool = int(seen["opp_level"]) == Moves.Level.LOW
			_guard_low = low if _rng.randf() < _height_skill else not low
			if habits["lows"] > _habit_k and skill > 0.4:
				_guard_low = low or _rng.randf() < 0.3
			_defend_ticks = maxi(10, int(seen["opp_ticks_left"]) - reaction_ticks + 4)
			state = State.DEFEND
			_state_ticks = 0
			_note("block")
			var bits: int = _bit(away)
			if _guard_low and bool(Moves.kit(kit)["can_crouch"]):
				bits |= _bit(DOWN)
			return bits

	# Đạn: nhảy qua, đỡ, hoặc (Đông Tảo) húc xuyên bằng giáp – mỗi viên chỉ quyết định một lần.
	if bool(seen["opp_projectile_near"]) and _tick - _proj_tick > 40:
		_proj_tick = _tick
		var roll: float = _rng.randf()
		if bool(Moves.kit(kit)["can_jump"]) and distance > 170.0 and roll < 0.2 + 0.4 * skill * (0.5 + jumpiness):
			_note("jump")
			return _bit(UP) | _bit(toward)
		if kit == &"dongtao" and distance < 360.0 and roll < 0.15 + 0.35 * skill:
			_note("rush")
			return _press("rush", toward, away)
		if roll < 0.35 + 0.5 * skill:
			_defend_ticks = 24
			_guard_low = false
			return _bit(away)

	# Chống nhảy.
	if bool(seen["opp_airborne"]) and not bool(seen["opp_juggle"]) and serial != _aa_serial and _cooldown == 0:
		var approaching: bool = float(seen["opp_vx_toward"]) > 20.0 or distance < 140.0
		if approaching and distance < 190.0:
			_aa_serial = int(seen["opp_jump_serial"])
			if _rng.randf() < _anti_air + (0.15 if habits["jumps"] > _habit_k else 0.0):
				_note("anti_air")
				if _info.has("counter") and _rng.randf() < 0.45:
					return _press("counter", toward, away)
				return _press("anti_air", toward, away)
			if _rng.randf() < 0.4 * block_rate + 0.2 * skill:
				_defend_ticks = 20
				_guard_low = false
				return _bit(away)

	# Trừng phạt: đối thủ đánh hụt hoặc bị đỡ và còn hồi lâu.
	var opp_left: int = int(view["opp_ticks_left"])
	if bool(seen["opp_recovering"]) and int(seen["opp_move_serial"]) != _punished_serial and _cooldown == 0:
		var starter: String = _best_starter(distance)
		if starter != "" and opp_left > int(_info[starter]["startup"]) - 1:
			_punished_serial = int(seen["opp_move_serial"])
			var chance: float = _punish if bool(seen["opp_was_blocked"]) else _whiff_punish + 0.1
			if _rng.randf() < chance:
				_note("punish")
				return _start_route(view, distance, true)
	return -1


# =================================================================== trung lập

func _decide(view: Dictionary, seen: Dictionary, distance: float, lead: float, desperate: bool) -> void:
	var previous: int = state
	var aggr: float = aggression
	if lead < -0.25 or desperate:
		aggr = minf(1.0, aggr + 0.25)
	elif lead > 0.3:
		aggr = maxf(0.1, aggr - 0.15 * skill)
	var clock: int = int(view.get("clock_ticks", 99 * 60))
	if clock < 15 * 60 and lead > 0.05 and skill > 0.5:
		aggr *= 0.5 # đang dẫn máu cuối hiệp: chơi giữ
	# Không rùa mãi: quá lâu không đánh thì ép lên.
	if _passive_ticks > 150 + int(120.0 * (1.0 - aggr)):
		aggr = 1.0

	# Do dự: người thật đôi khi đứng nhìn.
	if _rng.randf() < _hesitate * 0.35:
		_pause_ticks = _rng.randi_range(6, 18)
		state = State.POKE if distance < reach("jab") + 30.0 else State.APPROACH
		if _rng.randf() < 0.5:
			state = State.SPACE
		_finish_decide(previous)
		return

	if bool(seen["opp_down"]) and not bool(view["opp_juggle"]):
		state = State.OKI
	elif bool(seen["opp_counter"]) and skill > 0.4:
		state = State.SPACE # thấy thế Phản Đòn thì không đánh vào
	elif distance > 330.0 and _info.has("projectile") and _rng.randf() < 0.15 + 0.35 * skill * (1.0 - aggr * 0.5) \
			and not _repetitive("zone"):
		state = State.ZONE
	elif gust_weapon and distance > 170.0 and distance < 560.0 and not bool(view.get("my_gust_out", false)) \
			and _rng.randf() < (0.25 + 0.35 * skill) * (0.6 if relentless else 1.0) and not _repetitive("gust"):
		state = State.ZONE # Quạt lông giữ khoảng cách, đẩy đối thủ vào góc
	elif armor_rush and distance > 120.0 and distance < 260.0 and _cooldown == 0 \
			and _rng.randf() < (0.1 + 0.15 * aggr) * (0.5 if _repetitive("helmet") else 1.0):
		state = State.POKE # Nón bảo hiểm: lao có giáp từ tầm trung
		_route = []
		var hdx: float = float(view["dx"])
		_queue.append(_press("mid", RIGHT if hdx > 0.0 else LEFT, LEFT if hdx > 0.0 else RIGHT))
		_note("helmet")
		_passive_ticks = 0
	elif distance > reach("jab") + 10.0:
		var footsie: float = 0.2 + 0.4 * skill + (0.25 if tier >= 4 else 0.0) # T4: đứng ngoài tầm, chờ đối thủ hụt
		if kit == &"dongtao" and distance < 340.0 and distance > 150.0 and _cooldown == 0 \
				and _rng.randf() < (0.08 + 0.12 * aggr) * (0.5 if _repetitive("rush") else 1.0):
			state = State.POKE # Húc Trâu xuyên đòn từ tầm trung
			_route = []
			var dx: float = float(view["dx"])
			_queue.append(_press("rush", RIGHT if dx > 0.0 else LEFT, LEFT if dx > 0.0 else RIGHT))
			_note("rush")
			_passive_ticks = 0
		elif distance < float(view["opp_max_reach"]) + 50.0 and _rng.randf() < footsie * (1.0 - aggr) and not _repetitive("space"):
			state = State.SPACE # đứng ngay ngoài tầm đối thủ, chờ nó đánh hụt
			_note("space")
		else:
			state = State.APPROACH
			var jump_ok: bool = jumpiness > 0.0 and distance > 150.0 and distance < 320.0 and not _repetitive("jump")
			if habits["hits"] > 0.0 and _rng.randf() < 0.3 * skill:
				jump_ok = false
			_jump_attack = jump_ok and _rng.randf() < jumpiness * (0.7 if skill > 0.6 else 1.0)
	else:
		if _rng.randf() < 0.35 + aggr * 0.6:
			state = State.POKE
			_passive_ticks = 0
		else:
			state = State.SPACE
			_note("space")
	if relentless and state == State.SPACE:
		state = State.APPROACH if distance > reach("jab") + 10.0 else State.POKE
	if state in [State.SPACE, State.DEFEND]:
		_passive_ticks += _think_timer
	_finish_decide(previous)


func _finish_decide(previous: int) -> void:
	if state != previous:
		_state_ticks = 0


func _okizeme(view: Dictionary, seen: Dictionary, distance: float, toward: int, away: int) -> int:
	var wake_left: int = int(view["opp_wake_left"])
	if not bool(view["opp_down"]):
		state = State.POKE
		return 0
	# Thị uy khi đối thủ còn nằm xa (nạp nộ).
	if distance > 220.0 and wake_left > 40 and _cooldown == 0 and _rng.randf() < 0.02 + 0.03 * skill:
		_note("taunt")
		return _tap(S) | _bit(H)
	if distance > reach("jab") - 6.0:
		return _bit(toward)
	# Đòn "meaty": ra đòn sao cho nhịp active trùng lúc đứng dậy (tier cao).
	if skill > 0.55 and wake_left > 0 and wake_left <= int(_info["jab"]["startup"]) + 1 and _cooldown == 0:
		_note("meaty")
		state = State.POKE
		return _start_route(view, distance)
	if skill <= 0.55 and _rng.randf() < 0.03:
		state = State.SPACE
	return 0


# =================================================================== combo

func _best_starter(distance: float) -> String:
	var best: String = ""
	var best_startup: int = 999
	for role in ["jab", "mid", "low", "heavy"]:
		if _info.has(role) and reach(role) + 4.0 >= distance and int(_info[role]["startup"]) < best_startup:
			best = role
			best_startup = int(_info[role]["startup"])
	return best


func _start_route(view: Dictionary, distance: float, punish: bool = false) -> int:
	var bars: int = int(view["my_special_bars"])
	var dx: float = float(view["dx"])
	var toward: int = RIGHT if dx > 0.0 else LEFT
	var away: int = LEFT if dx > 0.0 else RIGHT
	_passive_ticks = 0
	# Siêu chiêu thẳng khi đối thủ đang hồi đòn dài hoặc máu thấp (tier cao).
	if bars >= 2 and _info.has("super") and _rng.randf() < 0.05 + 0.25 * _meter_smart * (1.5 if punish else 1.0) \
			and (float(view["opp_hp_ratio"]) < 0.35 or punish) and not _repetitive("super"):
		_route = []
		_note("super")
		return _press("super", toward, away)
	var candidates: Array = []
	for route in _routes:
		var roles: Array = route[0]
		if int(route[1]) > bars or int(route[2]) > tier:
			continue
		if reach(String(roles[0])) + 4.0 < distance:
			continue
		candidates.append(route)
	if candidates.is_empty():
		_route = []
		return _press("jab", toward, away) if distance <= reach("jab") + 30.0 else _bit(toward)
	# Chọn: tier cao ưu tiên sát thương / dùng nộ đúng lúc, tier thấp ngẫu nhiên và cắt ngắn.
	var pick: Array = candidates[_rng.randi_range(0, candidates.size() - 1)]
	if _rng.randf() < _combo_skill:
		var best_score: float = -1.0
		for route in candidates:
			var score: float = float((route[0] as Array).size()) + float(route[1]) * (1.5 if float(view["opp_hp_ratio"]) < 0.4 else 0.4)
			if habits["blocks"] > _habit_k and (route[0] as Array).has("low"):
				score += 1.5 # đối thủ đỡ nhiều: trộn đòn thấp
			if _repetitive("route_%s" % str(route[0])):
				score -= 2.0
			score += _rng.randf() * 0.8
			if score > best_score:
				best_score = score
				pick = route
	_route = (pick[0] as Array).duplicate()
	_note("route_%s" % str(pick[0]))
	# Tier thấp bỏ dở combo.
	if _rng.randf() > 0.35 + 0.65 * _combo_skill and _route.size() > 2:
		_route.resize(2)
	_route_blocked_stop = _rng.randf() < 0.2 + 0.8 * skill
	_route_index = 1
	var first: String = String(_route[0])
	if first == "low" and kit == &"rooster" and habits["lows"] < 1.0 and _rng.randf() < 0.3 * (1.0 - skill):
		first = "jab"
	return _press(first, toward, away)


func _continue_route(view: Dictionary, toward: int, away: int) -> int:
	if not bool(view["my_connected"]) or _cooldown > 0 or _route_index >= _route.size():
		return 0
	if bool(view["my_blocked"]) and _route_blocked_stop:
		_route = []
		return 0 # đòn bị đỡ: dừng chuỗi để không bị phạt
	var role: String = String(_route[_route_index])
	_route_index += 1
	if role == "super" and int(view["my_special_bars"]) < 2:
		return 0
	if role == "rush" and int(view["my_special_bars"]) < 1 and kit == &"rooster":
		return 0
	return _press(role, toward, away)


## Bấm một vai trò của kit (kèm hướng); siêu chiêu Đông Tảo dùng lệnh vẽ ↓↘→↓↘→ qua hàng đợi input.
func _press(role: String, toward: int, away: int) -> int:
	if not ROLES[kit].has(role):
		role = "jab"
	var spec: Array = ROLES[kit][role]
	var button: int = int(spec[0])
	var dir: String = String(spec[1])
	match dir:
		"fwd":
			return _tap(button) | _bit(toward)
		"back":
			return _tap(button) | _bit(away)
		"down":
			return _tap(button) | _bit(DOWN)
		"motion_super":
			var d: int = _bit(DOWN)
			var df: int = _bit(DOWN) | _bit(toward)
			var f: int = _bit(toward)
			_queue = [df, f, d, df, f | _bit(button)]
			_cooldown = 9
			return d
	return _tap(button)


# =================================================================== thẻ, học thói quen

func _cards(view: Dictionary, distance: float) -> int:
	if int(view["my_card_gauge"]) <= 0 or _cooldown > 0 or bool(view["my_busy"]):
		return 0
	var selected: StringName = StringName(view.get("my_card_selected", &""))
	var cost: int = int(view.get("my_card_cost", 9))
	if tier >= 4:
		return _smart_cards(view, distance, selected, cost)
	if int(view["my_card_gauge"]) < cost:
		return 0
	match selected:
		&"mai_rua":
			if float(view["my_hp_ratio"]) < 0.5 and not bool(view["mai_rua_active"]):
				return _tap(InputBits.CARD_USE)
		&"cuong_no":
			if skill > 0.3 and distance < 170.0 and _rng.randf() < 0.02 + 0.04 * skill:
				return _tap(InputBits.CARD_USE)
		&"gio_song":
			if skill > 0.3 and distance < 150.0 and _rng.randf() < 0.01 + 0.03 * skill:
				return _tap(InputBits.CARD_USE)
	return 0


## T4: chọn thẻ theo tình huống rồi xoay tay bài tới thẻ đó – Mai Rùa khi bị dồn/máu thấp, Cuồng Nộ trước khi
## ép đòn ở cự ly gần, Gió Sông khi đối thủ sát góc. Mỗi lần bấm cách nhau ≥ 10 tick.
func _smart_cards(view: Dictionary, distance: float, selected: StringName, cost: int) -> int:
	if _tick - _card_tick < 10:
		return 0
	var hand: Array = view.get("my_hand", [])
	var gauge: int = int(view["my_card_gauge"])
	var want: StringName = &""
	if hand.has(&"mai_rua") and not bool(view["mai_rua_active"]) and float(view["my_hp_ratio"]) < 0.55 \
			and (distance < 170.0 or bool(view["me_hit"])) and gauge >= 1:
		want = &"mai_rua"
	elif hand.has(&"cuong_no") and not bool(view.get("cuong_no_active", false)) and distance < 160.0 and gauge >= 2 \
			and (bool(view["opp_recovering"]) or bool(view["opp_down"]) or float(view["opp_hp_ratio"]) < 0.5):
		want = &"cuong_no"
	elif hand.has(&"gio_song") and not bool(view.get("gio_song_active", false)) and bool(view.get("opp_at_wall", false)) \
			and distance < 220.0 and gauge >= 2:
		want = &"gio_song"
	if want == &"":
		return 0
	_card_tick = _tick
	if selected == want:
		if gauge >= cost:
			_note("card")
			return _tap(InputBits.CARD_USE)
		return 0
	return _tap(InputBits.CARD_NEXT)


func _learn(seen: Dictionary) -> void:
	if _tick % 600 == 0:
		for key in habits.keys():
			habits[key] = float(habits[key]) * _habit_decay
	if not _prev_seen.is_empty():
		if bool(seen["opp_airborne"]) and not bool(_prev_seen["opp_airborne"]) and not bool(seen["opp_juggle"]):
			habits["jumps"] = float(habits["jumps"]) + 1.0
		if int(seen["opp_move_serial"]) != int(_prev_seen["opp_move_serial"]) and bool(seen["opp_attacking"]):
			if int(seen["opp_level"]) == Moves.Level.LOW:
				habits["lows"] = float(habits["lows"]) + 1.0
			if String(seen["opp_move_cat"]) in ["SP", "SUPER"]:
				habits["specials"] = float(habits["specials"]) + 1.0
		if bool(seen["my_blocked"]) and not bool(_prev_seen["my_blocked"]):
			habits["blocks"] = float(habits["blocks"]) + 1.0
		if bool(seen["opp_recovering"]) and not bool(_prev_seen["opp_recovering"]) and not bool(seen["opp_was_blocked"]):
			habits["whiffs"] = float(habits["whiffs"]) + 1.0
		if bool(seen["me_hit"]) and not bool(_prev_seen["me_hit"]):
			habits["hits"] = float(habits["hits"]) + 1.0
	_prev_seen = seen


## Ghi lại hành động trung lập gần đây để phá vòng lặp dễ đoán.
func _note(action: String) -> void:
	_recent.append(action)
	if _recent.size() > 8:
		_recent.pop_front()


func _repetitive(action: String) -> bool:
	var count: int = 0
	for a in _recent:
		if a == action:
			count += 1
	return count >= 3


func _bit(bit: int) -> int:
	return 1 << bit


func _tap(bit: int) -> int:
	_cooldown = 7
	return 1 << bit
