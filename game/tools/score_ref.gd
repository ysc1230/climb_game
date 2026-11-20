extends SceneTree
## 점수 기준값·관문 측정(docs/superpowers/specs/2026-11-19-3-score-design.md §3.1).
## 사용: godot --headless --path game --script res://tools/score_ref.gd -- [--write] [route_id ...]
## 정답 순서(intended_moves)를 검사 봇으로 재생해 1m당 쓴 손 힘·잡기 수를 재고, crux_steps에서 관문을 옮겨 적는다.
## --write면 SCORE_JSON 줄을 내보낸다 → tools/score_ref_write.py가 문제 JSON에 score_ref·score_gates를 쓴다.


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var write := args.has("--write")
	args.erase("--write")
	var routes: Array = []
	if args.is_empty():
		var idx := ContentIndex.load_all()
		for r in idx.all_routes():
			if r.mode == "general":
				routes.append(r)
	else:
		for id in args:
			routes.append(RouteDef.load_json(ContentIndex.route_path(id)))
	var ok := true
	for r in routes:
		ok = _measure(r, write) and ok
	quit(0 if ok else 1)


static func measure(route: RouteDef) -> Dictionary:
	var rec := ScoreRecorder.new()
	var bot := SessionBot.run(route, route.intended_moves, {}, rec)
	var d := rec.to_dict()
	var h := maxf(ScoreCalc.top_y(route) - float(d.start_y), 0.5)
	var grab_ev: Array = d.events.filter(func(e): return e.type == "grab")
	var q := 0.0
	for e in grab_ev:
		q += float(e.get("quality", 1.0))
	q = q / grab_ev.size() if not grab_ev.is_empty() else 1.0
	return {"ok": bot.ok(), "failure": bot.failure, "ref": {"spent_per_m": snappedf(float(d.spent) / h, 0.01), "grabs": grab_ev.size(), "quality": snappedf(q, 0.001)}, "gates": gates(route), "record": d}


## crux_steps의 단계에서 기술로 잡는·딛는 슬롯.
static func gates(route: RouteDef) -> Array:
	var out := []
	for tech in route.crux_steps:
		var m: Array = route.intended_moves[int(route.crux_steps[tech])]
		var slot := str(m[2]) if m.size() == 3 else (str(m[1]) if m.size() == 2 and route.slots.has(str(m[1])) else "")
		if slot != "":
			out.append({"technique": str(tech), "slot": slot})
	return out


func _measure(route: RouteDef, write: bool) -> bool:
	var m := measure(route)
	print("== %s %s: %s ref=%s gates=%s" % [route.route_id, route.grade, "통과" if m.ok else "실패 " + m.failure, m.ref, m.gates])
	if not m.ok:
		return false
	route.score_ref = m.ref
	route.score_gates = []
	for g in m.gates:
		route.score_gates.append({"technique": StringName(g.technique), "slot": g.slot})
	var s := ScoreCalc.score(m.record, route)
	print("   봇 점수 %s %s" % [ScoreCalc.format(s.total), s.parts])
	if write:  # 문제 JSON은 tools/score_ref_write.py가 원래 키 순서·숫자 표기를 지켜 고친다
		print("SCORE_JSON %s %s" % [ContentIndex.route_path(route.route_id), JSON.stringify({"score_ref": m.ref, "score_gates": m.gates})])
	return true
