extends SceneTree
## 루트 검증기. 사용: godot --headless --path game --script res://tools/route_check.gd -- R01
## 콘텐츠 불변 조건 검사 후, 의도 경로와 좌우 순서를 바꾼 경로를 자동 재생한다.


func _init() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = PackedStringArray(["R01"])
	var all_ok := true
	for id in ids:
		all_ok = _check(id) and all_ok
	quit(0 if all_ok else 1)


func _check(id: String) -> bool:
	var route := RouteDef.load_json("res://data/routes/%s.json" % id)
	print("== %s (content_version %d, tuning_version %d, %s)" % [id, route.content_version, Tuning.TUNING_VERSION, route.validation_status])
	if not route.errors.is_empty():
		for e in route.errors:
			print("  [저작 오류] ", e)
		return false
	var ok := true
	for variant in [["의도 경로", route.intended_moves], ["좌우 순서 교체", RouteBot.swapped_pairs(route.intended_moves)]]:
		var bot := RouteBot.run(route, variant[1])
		print("  -- %s: %s" % [variant[0], "통과" if bot.ok() else "실패"])
		for line in bot.log:
			print("     ", line)
		ok = ok and bot.ok()
	return ok
