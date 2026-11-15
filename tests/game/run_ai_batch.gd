extends SceneTree

## Thống kê cân bằng AI-vs-AI có seed (không có cảnh điện ảnh, kết quả mô phỏng y hệt khi có).
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_ai_batch.gd [-- seeds=10]
## In: tỉ lệ thắng theo tier, độ dài hiệp/trận trung bình, số hiệp hết giờ, kiểm tra kẹt trận.

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


func _initialize() -> void:
	var seeds: int = 10
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("seeds="):
			seeds = int(String(arg).substr(6))
	_runner = Runner.new()
	root.add_child(_runner)
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


func _report(results: Array) -> void:
	var groups: Dictionary = {}
	for r in results:
		var key: String = String(r["label"])
		if not groups.has(key):
			groups[key] = []
		groups[key].append(r)
	var t3_wins: int = 0
	var t3_total: int = 0
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
		var n: int = maxi(1, list.size())
		print("%-24s P1 wins %d/%d · rounds %d · avg round %.1f s · timeouts %d · avg match %.1f s (fight-only %.1f s)" % [
			key, p_wins, list.size(), rounds, float(round_frames) / maxf(1.0, float(rounds)) / 60.0, timeouts,
			float(match_frames) / float(n) / 60.0, float(round_frames) / float(n) / 60.0])
	print("T3 vs T1 (both sides): T3 won %d/%d" % [t3_wins, t3_total])
	_check(stalemates == 0, "no stalemates (every match ends by KO or time)")
	_check(t3_total == 0 or t3_wins * 10 >= t3_total * 7, "T3 beats T1 in ≥ 70%% of seeded matches (%d/%d)" % [t3_wins, t3_total])
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
