extends SceneTree
## 루트 검증기(docs/28 §7.4). 사용: godot --headless --path game --script res://tools/route_check.gd -- G_V0_01
## 인자가 없으면 ContentIndex의 모든 문제를 검사한다. 문제마다 ContentCheck(저작 오류 → 의도 경로 → 좌우 교체 →
## 기술 없이 재생 → 측정값·등급 경고)를 실제 세션(SessionBot)으로 돌려 출력한다.


func _init() -> void:
	var ids := OS.get_cmdline_user_args()
	var all_ok := true
	if ids.is_empty():
		var idx := ContentIndex.load_all()
		for e in idx.errors:
			print("[목록 오류] ", e)
		for r in idx.all_routes():
			all_ok = _report(r) and all_ok
	else:
		for id in ids:
			all_ok = _report(RouteDef.load_json(ContentIndex.route_path(id))) and all_ok
	quit(0 if all_ok else 1)


func _report(route: RouteDef) -> bool:
	print("== %s %s %s (content_version %d, tuning_version %d, %s)" % [route.route_id, route.grade, route.name_ko, route.content_version, Tuning.TUNING_VERSION, route.validation_status])
	var res := ContentCheck.check(route)
	for line in res.lines:
		print("  ", line)
	print("  => %s" % ("통과" if res.ok else "실패"))
	return res.ok
