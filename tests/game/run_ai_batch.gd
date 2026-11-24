extends SceneTree

## Thống kê cân bằng AI-vs-AI có seed (không có cảnh điện ảnh, kết quả mô phỏng y hệt khi có).
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_ai_batch.gd [-- seeds=10 suite=all|base|wave2]
## In: tỉ lệ thắng theo tier, độ dài hiệp/trận trung bình, số hiệp hết giờ, kiểm tra kẹt trận.
## suite=wave2 (bản dựng đầy đủ qua GameState.side_from_raw / opponent_side): gương cùng bản dựng (công bằng),
## gà vô địch Ao Làng mới ra lò vs Liên tỉnh vòng 1, bản nâng cấp (Lv6 + đủ đồ tiệm Cô Ba) vs Liên tỉnh vòng 1,
## T4 vs T3, gà người chơi kiểu Act 1 vs chung kết Ao Làng (Tèo bản dựng).

const Runner = preload("res://tests/game/ai_match_runner.gd")

var _runner: Node
var _failures: int = 0


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


static func rooster(tier: int, skill: float, aggr: float = 0.55, block: float = 0.3, jumpy: float = 0.2, breed: int = 0) -> Dictionary:
	return {"owner": "AI", "name": "T%d" % tier, "breed": breed, "lv": 3, "tier": tier, "skill": skill,
		"aggr": aggr, "block": block, "jumpy": jumpy}


## Bản dựng người chơi điển hình (AI T2 đứng thay người chơi – GameState.TIER_POWER coi người chơi ≈ T2).
static func player_build(lv: int, weapon: StringName, gear: Dictionary, breed: int = 0) -> Dictionary:
	return GameState.side_from_raw({"owner": "Người chơi", "name": "Ô Mun", "breed": breed, "lv": lv, "tier": 2,
		"skill": 0.6, "aggr": 0.55, "block": 0.3, "jumpy": 0.2, "weapon": weapon, "gear": gear,
		"cards": [&"cuong_no", &"mai_rua", &"gio_song"]})


static func champion_build() -> Dictionary:
	return player_build(3, &"dao_chan", {&"head": &"mao_sat"})


static func upgraded_build() -> Dictionary:
	return player_build(6, &"dao_chan", {&"head": &"mao_sat", &"armor": &"giap_tre", &"wing": &"canh_lua",
		&"spur": &"cua_sat", &"comb": &"mao_cat"})


func _initialize() -> void:
	var seeds: int = 10
	var suite: String = "all"
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("seeds="):
			seeds = int(String(arg).substr(6))
		elif String(arg).begins_with("suite="):
			suite = String(arg).substr(6)
	_runner = Runner.new()
	root.add_child(_runner)
	if suite in ["all", "wave2"]:
		_wave2_jobs(seeds)
	if suite == "t4":
		for s in range(seeds):
			var t4: Dictionary = rooster(4, 0.9, 0.6, 0.35)
			var t3: Dictionary = rooster(3, 0.9, 0.6, 0.35)
			if s % 2 == 0:
				_runner.jobs.append({"label": "W2 T4 vs T3", "p": t4, "p_ai": t4, "o": t3, "seed": 900 + s})
			else:
				_runner.jobs.append({"label": "W2 T3 vs T4", "p": t3, "p_ai": t3, "o": t4, "seed": 900 + s})
			var careless: Dictionary = player_build(3, &"dao_chan", {&"head": &"mao_sat"})
			careless["tier"] = 1
			careless["skill"] = 0.3
			careless["block"] = 0.1
			_runner.jobs.append({"label": "W2 careless act1 vs teo_2 build", "p": careless, "p_ai": careless,
				"o": GameState.opponent_side("teo_2"), "seed": 1100 + s})
	if suite in ["wave2", "t4"]:
		_runner.all_done.connect(_report)
		return
	var mid: Dictionary = rooster(2, 0.6)
	for s in range(seeds):
		_runner.jobs.append({"label": "T2 vs T2", "p": mid, "p_ai": mid, "o": mid, "seed": 100 + s})
	for s in range(seeds):
		var t3: Dictionary = rooster(3, 0.9, 0.6, 0.35)
		var t1: Dictionary = rooster(1, 0.2, 0.5, 0.1, 0.1)
		# Đổi bên xen kẽ để không lệch do vị trí P1/P2.
		if s % 2 == 0:
			_runner.jobs.append({"label": "T3 vs T1", "p": t3, "p_ai": t3, "o": t1, "seed": 200 + s})
		else:
			_runner.jobs.append({"label": "T1 vs T3", "p": t1, "p_ai": t1, "o": t3, "seed": 200 + s})
	for s in range(seeds):
		_runner.jobs.append({"label": "T2 vs T1", "p": rooster(2, 0.6), "p_ai": rooster(2, 0.6), "o": rooster(1, 0.2, 0.5, 0.1, 0.1), "seed": 300 + s})
		_runner.jobs.append({"label": "T3 vs T2", "p": rooster(3, 0.9), "p_ai": rooster(3, 0.9), "o": rooster(2, 0.6), "seed": 400 + s})
	var dt: Dictionary = GameState.OPPONENTS["bay_ghe"].duplicate(true)
	for s in range(seeds):
		_runner.jobs.append({"label": "T2 rooster vs bay_ghe", "p": mid, "p_ai": mid, "o": dt, "seed": 500 + s})
	_runner.all_done.connect(_report)


func _wave2_jobs(seeds: int) -> void:
	var lt1: Dictionary = GameState.opponent_side("lt_hai_ben_tre")
	var teo: Dictionary = GameState.opponent_side("teo_2")
	var mirror: Dictionary = GameState.side_from_raw({"owner": "AI", "name": "Gương", "breed": 0, "lv": 8, "tier": 3,
		"skill": 0.8, "aggr": 0.55, "block": 0.35, "jumpy": 0.2, "weapon": &"quat_long",
		"gear": {&"head": &"mu_dong", &"armor": &"giap_dong", &"spur": &"cua_dong"}, "cards": [&"cuong_no", &"mai_rua", &"gio_song"]})
	for s in range(seeds):
		_runner.jobs.append({"label": "W2 mirror build", "p": mirror, "p_ai": mirror, "o": mirror, "seed": 600 + s})
		var champ: Dictionary = champion_build()
		_runner.jobs.append({"label": "W2 champion vs LT1", "p": champ, "p_ai": champ, "o": lt1, "seed": 700 + s})
		var up: Dictionary = upgraded_build()
		_runner.jobs.append({"label": "W2 upgraded vs LT1", "p": up, "p_ai": up, "o": lt1, "seed": 800 + s})
		var t4: Dictionary = rooster(4, 0.9, 0.6, 0.35)
		var t3: Dictionary = rooster(3, 0.9, 0.6, 0.35)
		if s % 2 == 0:
			_runner.jobs.append({"label": "W2 T4 vs T3", "p": t4, "p_ai": t4, "o": t3, "seed": 900 + s})
		else:
			_runner.jobs.append({"label": "W2 T3 vs T4", "p": t3, "p_ai": t3, "o": t4, "seed": 900 + s})
		var act1: Dictionary = player_build(3, &"dao_chan", {&"head": &"mao_sat"})
		_runner.jobs.append({"label": "W2 act1 player vs teo_2 build", "p": act1, "p_ai": act1, "o": teo, "seed": 1000 + s})


func _report(results: Array) -> void:
	var groups: Dictionary = {}
	for r in results:
		var key: String = String(r["label"])
		if not groups.has(key):
			groups[key] = []
		groups[key].append(r)
	var t3_wins: int = 0
	var t3_total: int = 0
	var t4_wins: int = 0
	var t4_total: int = 0
	var stalemates: int = 0
	for key in groups.keys():
		var list: Array = groups[key]
		var p_wins: int = 0
		var rounds: int = 0
		var round_frames: int = 0
		var timeouts: int = 0
		var match_frames: int = 0
		for r in list:
			if bool(r.get("stalemate", false)):
				stalemates += 1
				continue
			if bool(r["won"]):
				p_wins += 1
			for i in range((r["round_frames"] as Array).size()):
				rounds += 1
				round_frames += int(r["round_frames"][i])
				if String(r["round_reasons"][i]) != "KO":
					timeouts += 1
			match_frames += int(r["frames"])
			if key == "T3 vs T1":
				t3_total += 1
				t3_wins += 1 if bool(r["won"]) else 0
			elif key == "T1 vs T3":
				t3_total += 1
				t3_wins += 0 if bool(r["won"]) else 1
			elif key == "W2 T4 vs T3":
				t4_total += 1
				t4_wins += 1 if bool(r["won"]) else 0
			elif key == "W2 T3 vs T4":
				t4_total += 1
				t4_wins += 0 if bool(r["won"]) else 1
		var n: int = maxi(1, list.size())
		print("%-24s P1 wins %d/%d · rounds %d · avg round %.1f s · timeouts %d · avg match %.1f s (fight-only %.1f s)" % [
			key, p_wins, list.size(), rounds, float(round_frames) / maxf(1.0, float(rounds)) / 60.0, timeouts,
			float(match_frames) / float(n) / 60.0, float(round_frames) / float(n) / 60.0])
	print("T3 vs T1 (both sides): T3 won %d/%d" % [t3_wins, t3_total])
	print("T4 vs T3 (both sides): T4 won %d/%d" % [t4_wins, t4_total])
	if t4_total > 0:
		_check(t4_wins * 10 >= t4_total * 7, "T4 beats T3 in ≥ 70%% of seeded matches (%d/%d)" % [t4_wins, t4_total])
	_check(stalemates == 0, "no stalemates (every match ends by KO or time)")
	_check(t3_total == 0 or t3_wins * 10 >= t3_total * 7, "T3 beats T1 in ≥ 70%% of seeded matches (%d/%d)" % [t3_wins, t3_total])
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
