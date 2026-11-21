extends SceneTree
## 벽 기울기 실험(experiment/overhang): 일반 문제마다 봇이 정답 순서로 0·15·25·35·45°에서 완등하는지와 최저 손 힘.
## godot --headless --path game --script res://tools/overhang_check.gd

func _initialize() -> void:
	var idx := ContentIndex.load_all()
	for r: RouteDef in idx.all_routes():
		if r.mode != "general":
			continue
		var row := "%s %-4s %-10s" % [r.route_id, r.grade, r.name_ko]
		for deg in [0.0, 15.0, 25.0, 35.0, 45.0]:
			r.wall_deg = deg
			var bot := RouteBot.run(r)
			row += " | %2d° %s %3.0f" % [deg, "O" if bot.ok() else "X", bot.min_stamina]
		r.wall_deg = 0.0
		print(row)
	quit()
