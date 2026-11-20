extends SceneTree
func _init():
	var T = load("res://tools/score_ref.gd")
	for id in ["G_V3_03", "G_V3_02", "G_V3_04"]:
		var r := RouteDef.load_json(ContentIndex.route_path(id))
		var rec := ScoreRecorder.new()
		SessionBot.run(r, r.intended_moves, {}, rec)
		print("== ", id)
		for e in rec.events:
			if e.type != "grab" or true:
				print("  ", e)
	quit()
