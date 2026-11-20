extends RefCounted
## 100점 점수(docs/superpowers/specs/2026-11-19-3-score-design.md §3.1).

var runner


func _route(gates := true) -> RouteDef:
	var r := RouteDef.load_json("res://data/routes/general/G_V3_03.json")
	r.score_ref = {"spent_per_m": 10.0, "grabs": 18}
	r.score_gates = [{"technique": &"T_HIGH_STEP", "slot": "G_V3_03/F07/foot_1"}] if gates else []
	return r


## 기준과 같은 깨끗한 완등 기록. 오른 높이 h는 탑 y − start_y.
func _rec(r: RouteDef) -> Dictionary:
	var h := 2.0
	var ev := []
	for i in 18:
		ev.append({"type": "grab", "tick": 10 * i + 5, "key": "x%d" % i})
	return {"ticks": 600, "stable_ticks": 600, "danger_entries": 0, "barn_doors": 0, "spent": 10.0 * h,
		"start_y": ScoreCalc.top_y(r) - h, "events": ev, "finish": {"feet_on": true, "stable": true}, "helped": false}


func test_clean_run_full_marks_except_gates() -> void:
	var r := _route()
	var s := ScoreCalc.score(_rec(r), r)
	runner.check(s.parts.energy == 30 and s.parts.stable == 25 and s.parts.precise == 20 and s.parts.finish == 10, "기준대로면 만점 %s" % [s])
	runner.check(s.parts.technique == 0 and s.total == 85, "관문을 못 맞추면 기술 0 %s" % [s])


func test_energy_uses_spent_only() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.spent = 10.0 * 2.0 * 1.75  # 기준의 1.75배 → 30 × (2.5 − 1.75) / 1.5 = 15
	runner.check(ScoreCalc.score(rec, r).parts.energy == 15, "1.75배 쓰면 15 %s" % [ScoreCalc.score(rec, r).parts])
	rec.spent = 10.0 * 2.0 * 3.0
	runner.check(ScoreCalc.score(rec, r).parts.energy == 0, "2.5배 넘으면 0")
	var rest := _rec(r)
	rest.ticks = 6000  # 오래 쉬어도(틱만 늘고 쓴 힘은 그대로)
	rest.stable_ticks = 6000
	runner.check(ScoreCalc.score(rest, r).parts.energy == 30, "쉬기만 길게 해도 힘 점수 그대로")


func test_stable_and_penalties() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.stable_ticks = 426  # f = 0.71 → 25 × 0.525 = 13.125
	rec.danger_entries = 1
	rec.barn_doors = 1
	runner.check(ScoreCalc.score(rec, r).parts.stable == 6, "13.1 − 4 − 3 → 6 %s" % [ScoreCalc.score(rec, r).parts])
	rec.danger_entries = 9
	runner.check(ScoreCalc.score(rec, r).parts.stable == 0, "최소 0")


func test_precise_misses_and_extra_grabs() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.events.append({"type": "miss", "tick": 500})
	rec.events.append({"type": "grab", "tick": 510, "key": "y"})
	rec.events.append({"type": "grab", "tick": 520, "key": "z"})
	runner.check(ScoreCalc.score(rec, r).parts.precise == 20 - 2 - 2, "헛놓기 −2, 잡기 둘 초과 −2 %s" % [ScoreCalc.score(rec, r).parts])


func test_gates_once_and_only_on_slot() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.events.append({"type": "move", "tick": 300, "label": &"HighStep"})
	rec.events.append({"type": "grab", "tick": 305, "key": "G_V3_03/F07/foot_1"})
	rec.events.append({"type": "move", "tick": 400, "label": &"HighStep"})
	rec.events.append({"type": "grab", "tick": 405, "key": "G_V3_03/F07/foot_1"})
	var s := ScoreCalc.score(rec, r)
	runner.check(s.parts.technique == 15, "관문 슬롯에서 하이스텝 → 15(두 번 해도 한 번) %s" % [s.parts])
	var off := _rec(r)
	off.events.append({"type": "move", "tick": 300, "label": &"HighStep"})
	off.events.append({"type": "grab", "tick": 305, "key": "elsewhere"})
	runner.check(ScoreCalc.score(off, r).parts.technique == 0, "관문 밖 기술은 0")
	var btn := _rec(r)
	btn.events.append({"type": "succeeded", "tick": 300, "id": &"T_HIGH_STEP", "key": "G_V3_03/F07/foot_1"})
	runner.check(ScoreCalc.score(btn, r).parts.technique == 15, "버튼 기술은 기록의 슬롯으로")


func test_no_gates_scales_to_100() -> void:
	var r := _route(false)
	var s := ScoreCalc.score(_rec(r), r)
	runner.check(s.total == 100 and s.parts.technique < 0, "관문 없으면 85 → 100, 기술 항목 없음(−1) %s" % [s])
	var rec := _rec(r)
	rec.finish = {"feet_on": false, "stable": false}
	runner.check(ScoreCalc.score(rec, r).parts.finish == 4, "두 손만 탑이면 마무리 4")


func test_helped_flag() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.helped = true
	runner.check(ScoreCalc.score(rec, r).helped, "도움 표시")


## 실제 세션을 읽는 기록기: 손 힘 감소만 더하고 회복은 빼지 않는다.
func test_recorder_counts_spent_not_recovery() -> void:
	var s := ClimbSession.new(RouteDef.load_json("res://data/routes/general/G_V3_03.json"))
	var rec := ScoreRecorder.new()
	rec.tick(s, "")
	s.rules.stamina[&"LH"] = float(s.rules.stamina[&"LH"]) - 5.0
	rec.tick(s, "")
	s.rules.stamina[&"LH"] = float(s.rules.stamina[&"LH"]) + 5.0
	rec.tick(s, "")
	runner.check(absf(rec.to_dict().spent - 5.0) < 0.5, "감소 5만 셈(회복 무시) %s" % rec.to_dict().spent)
	runner.check(rec.to_dict().ticks == 3, "틱 수")
