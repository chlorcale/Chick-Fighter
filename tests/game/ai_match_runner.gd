extends Node

## Chạy lần lượt nhiều trận AI-vs-AI (cả hai bên do EnemyAI điều khiển) và ghi kết quả.
## Dùng cho run_ai_batch.gd (thống kê cân bằng) và run_game_smoke.gd (kiểm tra tier, không kẹt trận).
## Mỗi job: {p: side, o: side, p_ai: cấu hình AI cho P1, mode, seed, cinematics, label}.

signal all_done(results: Array)

## Giới hạn khung hình mỗi trận: 3 hiệp × (99 s + 15 s hiệp phụ) + trình diễn – vượt là "kẹt trận".
const FRAME_LIMIT: int = 3 * (99 + 15) * 60 + 6000

var jobs: Array = []
var results: Array = []
var _director: BattleDirector
var _job: Dictionary = {}
var _frames: int = 0
var _result: Dictionary = {}


func _physics_process(_delta: float) -> void:
	if _director == null:
		if jobs.is_empty():
			set_physics_process(false)
			all_done.emit(results)
			return
		_start(jobs.pop_front())
		return
	_frames += 1
	if not _result.is_empty() or _frames > FRAME_LIMIT:
		var r: Dictionary = _result.duplicate()
		r["label"] = String(_job.get("label", ""))
		r["seed"] = int(_job.get("seed", 0))
		r["frames"] = _frames
		r["stalemate"] = _result.is_empty()
		r["hits"] = _director.hit_log.size()
		r["log"] = _director.hit_log.duplicate(true)
		r["p_tier"] = int(_job["p_ai"].get("tier", 0))
		r["o_tier"] = int(_job["o"].get("tier", 0))
		var specials: Array = [0, 0]
		for f in _director.fighters:
			specials[f.index] = int(f.track["specials"])
		r["specials"] = specials
		results.append(r)
		_director.queue_free()
		_director = null


func _start(job: Dictionary) -> void:
	_job = job
	_frames = 0
	_result = {}
	_director = BattleDirector.new()
	_director.setup({"player": job["p"], "opponent": job["o"], "mode": String(job.get("mode", "normal")),
		"seed": int(job.get("seed", 1)), "cinematics": bool(job.get("cinematics", false)), "title": "TEST"})
	add_child(_director)
	_director.finished.connect(func(r: Dictionary) -> void: _result = r)
	var c: BattleDirector.Fighter = _director.fighters[0]
	c.source.configure({})
	c.ai = EnemyAI.new()
	var cfg: Dictionary = (job["p_ai"] as Dictionary).duplicate()
	cfg["kit"] = c.kit
	c.ai.configure(cfg, int(job.get("seed", 1)) * 31 + 7)
	if job.has("o_mode"):
		_director.fighters[1].ai.script_mode = int(job["o_mode"])
