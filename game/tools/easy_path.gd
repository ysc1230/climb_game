extends SceneTree
## 쉬운 길 탐색(docs/41 §5 도구 B). 사용: godot --headless --path game --script res://tools/easy_path.gd -- G_V3_03
## 인자가 없으면 모든 문제. 찾은 길, 재생 측정값, 그 길에서 금지하면 막히는 기술을 출력한다.

const FORBIDS := {&"cross": "크로스", &"match": "매치", &"high_step": "하이스텝"}


func _init() -> void:
	var ids := OS.get_cmdline_user_args()
	var routes: Array = []
	if ids.is_empty():
		routes = ContentIndex.load_all().all_routes()
	else:
		for id in ids:
			routes.append(RouteDef.load_json(ContentIndex.route_path(id)))
	var all_ok := true
	for r in routes:
		all_ok = _report(r) and all_ok
	quit(0 if all_ok else 1)


func _report(route: RouteDef) -> bool:
	print("== %s %s %s" % [route.route_id, route.grade, route.name_ko])
	var t0 := Time.get_ticks_msec()
	var res := PathExplorer.explore(route)
	for l in res.log:
		print("  ", l)
	print("  탐색 시간 %.1f초" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if not res.ok:
		return false
	var bot: SessionBot = res.bot
	var line := ""
	for s in res.steps:
		line += "%s %s, " % [s[0], String(s[1]).trim_prefix(route.route_id + "/")]
	print("  쉬운 길: ", line.trim_suffix(", "))
	var lf := PlacementMetrics.low_feet_moves(bot.log)
	print("  쉬운 길 측정값: 이동 %d, %.1f초, 도달 여유 최소 %.3fm, 최대 손 사용률 %.2f, 최저 손 피로 %.0f, 한 발·무발 이동 %d/%d(%.0f%%)" % [
		bot.metrics.moves, bot.metrics.seconds, bot.metrics.min_reach_margin, bot.metrics.max_hand_u, bot.metrics.min_stamina, lf[0], lf[1], 100.0 * lf[0] / maxi(lf[1], 1)])
	var need: PackedStringArray = []
	var used: Array = []
	for f in FORBIDS:
		var b := SessionBot.run(route, res.steps, {f: true})
		# 매치 금지는 정상의 두 손도 막는다(같은 홀드). 마지막 정상 잡기에서만 막히면 쓰지 않은 것으로 본다.
		var goal_only: bool = f == &"match" and b.failed_step >= res.steps.size() - 2
		if not b.ok() and not goal_only:
			used.append(f)
			need.append("%s(#%d)" % [FORBIDS[f], b.failed_step + 1])
	print("  쉬운 길이 쓰는 기술(금지하면 이 길이 막힘): ", ", ".join(need) if not need.is_empty() else "없음")
	for f in used:
		if f == &"match":
			print("  매치 없이 가는 길: 확인 못 함(매치 금지가 정상 잡기도 막아 탐색에 쓸 수 없다)")
			continue
		var alt := PathExplorer.explore(route, {f: true})
		if alt.ok:
			print("  %s 없이 가는 길 있음(필수 아님): 이동 %d, 최저 손 피로 %.0f, 탐색 %d번" % [FORBIDS[f], alt.steps.size(), alt.bot.metrics.min_stamina, alt.tries])
		else:
			print("  %s 없이 가는 길을 찾지 못함(탐색 %d번) → 이 탐색 범위에서는 필수" % [FORBIDS[f], alt.tries])
	return true
