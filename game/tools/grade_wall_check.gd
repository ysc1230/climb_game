extends SceneTree
## 등급 각도(GradeInfo.wall_deg)·홀드 수 상한으로 일반 문제 검사(오버행 실험 앱, 2026-11-22).
## 문제마다 콘텐츠 검사(의도 경로·필요 기술) 통과 여부, 손홀드/발 전용 홀드 수(상한), 최대 손 사용률·최저 손 힘·시간.
## godot --headless --path game --script res://tools/grade_wall_check.gd [-- 문제.json ...]   (인자가 없으면 모든 일반 문제)
## 환경 변수 LOG=1 이면 실패한 문제의 검사 줄을 모두 찍는다.

func _initialize() -> void:
	var routes: Array[RouteDef] = []
	var names: Array[String] = []
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		for r in ContentIndex.load_all().all_routes():
			if r.mode == "general":
				routes.append(r)
				names.append(r.route_id)
	else:
		for p in args:
			routes.append(RouteDef.load_json(p))
			names.append(p.get_file().get_basename())
	for i in routes.size():
		var r := routes[i]
		var m := PlacementMetrics.measure(r)
		var gap := HoldSpacing.violations(r)
		var res := ContentCheck.check(r)
		var mt: Dictionary = res.metrics
		var caps: bool = m.hand_holds <= GradeInfo.max_hands(r.grade) and m.foot_only <= GradeInfo.max_feet(r.grade)
		print("%s %-3s %2d° %-8s 검사 %s 간격 %s | 손 %d/%d 발 %d/%d %s | 손 사용률 %.2f 최저 손 힘 %.0f %.1f초" % [
			names[i], r.grade, int(r.wall_deg), r.name_ko, "O" if res.ok else "X", "O" if gap.is_empty() else "X%d" % gap.size(),
			m.hand_holds, GradeInfo.max_hands(r.grade), m.foot_only, GradeInfo.max_feet(r.grade), "" if caps else "(많음)",
			float(mt.get("max_hand_u", -1.0)), float(mt.get("min_stamina", -1.0)), float(mt.get("seconds", -1.0))])
		for v in gap:
			print("    간격 %s" % [v])
		if not res.ok:
			var lines: PackedStringArray = res.lines
			if OS.get_environment("LOG") != "":
				for l in lines:
					print("    " + l)
			else:
				for l in lines:
					if l.contains("실패") or l.contains("오류") or l.contains("필요 기술"):
						print("    " + l.strip_edges())
	quit()
