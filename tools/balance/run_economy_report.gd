extends SceneTree

## In bảng kinh tế theo tuần cho người chơi điển hình (xem economy_sim.gd).
## Chạy: godot --headless --path . -s res://tools/balance/run_economy_report.gd

const EconomySim := preload("res://tools/balance/economy_sim.gd")


func _initialize() -> void:
	var result: Dictionary = EconomySim.simulate(84)
	for line in EconomySim.report_lines(result):
		print(line)
	GameState.reset()
	quit()
