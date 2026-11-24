extends SceneTree

## Smoke test luồng cốt truyện: tiêu đề → tên → hồi ức → Chú Tư → trận hướng dẫn → Tèo → thưởng.
## Tự bấm qua hội thoại; các trận được kết thúc thắng ngay khi bắt đầu đánh.
## Chạy: godot --headless --path . --fixed-fps 60 -s res://tests/game/run_flow_smoke.gd

var _main: Node
var _frames: int = 0
var _failures: int = 0
var _checked_tutorial: bool = false


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1


func _initialize() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _find(type_check: Callable) -> Node:
	for child in _main.get_children():
		if type_check.call(child):
			return child
	return null


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames % 6 != 0:
		return false
	var dialog: DialogBox = _main.dialog
	var title: Node = _find(func(n: Node) -> bool: return n is TitleScreen)
	var cut: Node = _find(func(n: Node) -> bool: return n is Cutscene)
	var pre: Node = _find(func(n: Node) -> bool: return n is PreBattle)
	var result: Node = _find(func(n: Node) -> bool: return n is ResultScreen)
	var director: BattleDirector = _find(func(n: Node) -> bool: return n is BattleDirector) as BattleDirector

	if title != null:
		title._picked.emit("new")
	elif dialog._mode == 3:
		dialog._named.emit("")
	elif cut != null:
		cut._next.emit()
	elif dialog._mode == 1:
		dialog._text.visible_ratio = 1.0
		dialog._advanced.emit()
	elif dialog._mode == 2:
		dialog._chosen.emit(0)
	elif pre != null:
		pre._done.emit(true)
	elif director != null:
		if director.phase == BattleDirector.Phase.FIGHT:
			if director.mode == &"tutorial" and not _checked_tutorial:
				_checked_tutorial = true
				_check(director.objectives.size() == 2, "tutorial shows Light/Heavy objectives")
			director._finish(0, "TEST")
	elif result != null:
		result._remaining = 0.0
		result._closed.emit()
	elif _main.world != null and _main.world.player.can_move and not _main._busy:
		match GameState.stage:
			GameState.Stage.GO_CHU_TU:
				_check(GameState.player_name == "Tư Gà", "default player name is Tư Gà")
				_main._on_interact(&"chu_tu")
			GameState.Stage.FRIENDLY:
				_check(GameState.chicken_name == "Ô Mun", "default chicken name is Ô Mun")
				_check(GameState.cards.size() == 2, "tutorial grants Cuồng Nộ + Mai Rùa")
				_check(GameState.xp == 40, "tutorial grants 40 EXP (got %d)" % GameState.xp)
				_main._on_interact(&"teo")
			GameState.Stage.PREPARE:
				_check(GameState.cards.has(&"gio_song"), "friendly win grants Gió Sông")
				_check(GameState.money == 250000, "friendly win pays 50.000đ (money %d)" % GameState.money)
				_check(_main.world.marker_target == &"co_ba", "objective marker points to the shop")
				print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL"))
				quit(1 if _failures > 0 else 0)
				return true
	if _frames > 60 * 120:
		print("RESULT: FAIL (timeout at stage %d)" % GameState.stage)
		quit(1)
		return true
	return false
