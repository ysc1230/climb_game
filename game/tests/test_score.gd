extends RefCounted
## 100점 점수(docs/superpowers/specs/2026-11-19-3-score-design.md §3.1).

var runner


func _route(gates := true) -> RouteDef:
	var r := RouteDef.load_json("res://tests/fixtures/G_V3_03.json")
	r.score_ref = {"spent_per_m": 10.0, "grabs": 18, "quality": 0.8}
	r.score_gates = [{"technique": &"T_HIGH_STEP", "slot": "G_V3_03/F07/foot_1"}] if gates else []
	return r


## 기준과 같은 깨끗한 완등 기록. 오른 높이 h는 탑 y − start_y.
func _rec(r: RouteDef) -> Dictionary:
	var h := 2.0
	var ev := []
	for i in 18:
		ev.append({"type": "grab", "tick": 10 * i + 5, "key": "x%d" % i})
	return {"ticks": 600, "stable_ticks": 600, "strained_ticks": 0, "danger_entries": 0, "danger_ticks": 0, "barn_doors": 0, "barn_ticks": 0,
		"spent": 10.0 * h, "start_y": ScoreCalc.top_y(r) - h, "events": ev, "finish": {"feet": 2, "phase": "STABLE"}, "helped": false}


func _near(a, b) -> bool:
	return absf(float(a) - float(b)) < 0.006


func test_clean_run_full_marks_except_gates() -> void:
	var r := _route()
	var s := ScoreCalc.score(_rec(r), r)
	runner.check(_near(s.parts.energy, 30) and _near(s.parts.stable, 25) and _near(s.parts.precise, 20) and _near(s.parts.finish, 10), "기준대로면 만점 %s" % [s])
	runner.check(_near(s.parts.technique, 0) and _near(s.total, 85), "관문을 못 맞추면 기술 0 %s" % [s])


## 점수는 소수 둘째 자리까지(2026-11-20 사용자). 항목·총점 모두 0.01 단위.
func test_two_decimals() -> void:
	var r := _route(false)
	var rec := _rec(r)
	rec.spent = 10.0 * 2.0 * 1.234  # 30 × (2.5 − 1.234) / 1.5 = 25.32
	var s := ScoreCalc.score(rec, r)
	runner.check(_near(s.parts.energy, 25.32), "힘 아끼기 25.32 %s" % [s.parts])
	runner.check(is_equal_approx(s.total, snappedf(s.total, 0.01)) and _near(s.total, (25.32 + 25 + 20 + 10) * 100.0 / 85.0), "총점 0.01 단위 %s" % s.total)
	runner.check(ScoreCalc.format(94.5) == "94.50" and ScoreCalc.format(100) == "100.00", "표시는 둘째 자리까지")


func test_energy_uses_spent_only() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.spent = 10.0 * 2.0 * 1.75  # 기준의 1.75배 → 30 × (2.5 − 1.75) / 1.5 = 15
	runner.check(_near(ScoreCalc.score(rec, r).parts.energy, 15), "1.75배 쓰면 15 %s" % [ScoreCalc.score(rec, r).parts])
	rec.spent = 10.0 * 2.0 * 3.0
	runner.check(_near(ScoreCalc.score(rec, r).parts.energy, 0), "2.5배 넘으면 0")
	var rest := _rec(r)
	rest.ticks = 6000  # 오래 쉬어도(틱만 늘고 쓴 힘은 그대로)
	rest.stable_ticks = 6000
	runner.check(_near(ScoreCalc.score(rest, r).parts.energy, 30), "쉬기만 길게 해도 힘 점수 그대로")


func test_stable_and_penalties() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.stable_ticks = 432  # f = 0.72 → 25 × 0.55 = 13.75
	rec.danger_entries = 1
	rec.danger_ticks = 30   # 0.5초 → 2 + 6 × 0.5 = 5
	rec.barn_doors = 1
	rec.barn_ticks = 15     # 0.25초 → 1.5 + 4 × 0.25 = 2.5
	runner.check(_near(ScoreCalc.score(rec, r).parts.stable, 6.25), "13.75 − 5 − 2.5 → 6.25 %s" % [ScoreCalc.score(rec, r).parts])
	rec.danger_entries = 9
	runner.check(_near(ScoreCalc.score(rec, r).parts.stable, 0), "최소 0")
	var half := _rec(r)
	half.stable_ticks = 300
	half.strained_ticks = 300  # 버티기 힘든 틱은 절반만 → f = 0.75 → 15.625
	runner.check(_near(ScoreCalc.score(half, r).parts.stable, 15.63), "버티기 힘든 자세는 절반 %s" % [ScoreCalc.score(half, r).parts])


func test_precise_misses_and_extra_grabs() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.events.append({"type": "miss", "tick": 500})
	rec.events.append({"type": "grab", "tick": 510, "key": "y"})
	rec.events.append({"type": "grab", "tick": 520, "key": "z"})
	runner.check(_near(ScoreCalc.score(rec, r).parts.precise, 20 - 2 - 2), "헛놓기 −2, 잡기 둘 초과 −2 %s" % [ScoreCalc.score(rec, r).parts])


## 잡은 자리의 품질(홀드를 얼마나 좋은 곳에 잡았나) 평균이 기준보다 낮으면 6점 중 그 비율만.
func test_precise_grab_quality() -> void:
	var r := _route()
	var rec := _rec(r)
	for e in rec.events:
		e["quality"] = 0.6  # 기준 0.8의 0.75배 → 6 × 0.75 = 4.5 → 14 + 4.5
	runner.check(_near(ScoreCalc.score(rec, r).parts.precise, 18.5), "품질 0.75배 → 18.5 %s" % [ScoreCalc.score(rec, r).parts])
	for e in rec.events:
		e["quality"] = 0.95
	runner.check(_near(ScoreCalc.score(rec, r).parts.precise, 20), "기준보다 좋으면 만점(넘지 않음)")


func test_gates_once_and_only_on_slot() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.events.append({"type": "grab", "tick": 305, "key": "G_V3_03/F07/foot_1", "tech": ["T_HIGH_STEP"]})
	rec.events.append({"type": "grab", "tick": 405, "key": "G_V3_03/F07/foot_1", "tech": ["T_HIGH_STEP"]})
	var s := ScoreCalc.score(rec, r)
	runner.check(_near(s.parts.technique, 15), "관문 슬롯에서 하이스텝 → 15(두 번 해도 한 번) %s" % [s])
	var off := _rec(r)
	off.events.append({"type": "grab", "tick": 305, "key": "elsewhere", "tech": ["T_HIGH_STEP"]})
	var plain := _rec(r)
	plain.events.append({"type": "grab", "tick": 305, "key": "G_V3_03/F07/foot_1", "tech": []})
	runner.check(_near(ScoreCalc.score(plain, r).parts.technique, 0), "관문 슬롯이라도 기술 없이 잡으면 0")
	runner.check(_near(ScoreCalc.score(off, r).parts.technique, 0), "관문 밖 기술은 0")
	var btn := _rec(r)
	btn.events.append({"type": "succeeded", "tick": 300, "id": &"T_HIGH_STEP", "key": "G_V3_03/F07/foot_1"})
	runner.check(_near(ScoreCalc.score(btn, r).parts.technique, 15), "버튼 기술은 기록의 슬롯으로")


## 패드 기술은 얼마나 잘했나(tq 0~1)로 0.6 + 0.4 × tq만큼. 두 번 하면 더 잘한 쪽.
func test_gate_quality_partial() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.events.append({"type": "grab", "tick": 305, "key": "G_V3_03/F07/foot_1", "tech": ["T_HIGH_STEP"], "tq": {"T_HIGH_STEP": 0.5}})
	runner.check(_near(ScoreCalc.score(rec, r).parts.technique, 12), "tq 0.5 → 15 × 0.8 = 12 %s" % [ScoreCalc.score(rec, r).parts])
	rec.events.append({"type": "grab", "tick": 405, "key": "G_V3_03/F07/foot_1", "tech": ["T_HIGH_STEP"], "tq": {"T_HIGH_STEP": 1.0}})
	runner.check(_near(ScoreCalc.score(rec, r).parts.technique, 15), "더 잘한 쪽으로 15")


func test_no_gates_scales_to_100() -> void:
	var r := _route(false)
	var s := ScoreCalc.score(_rec(r), r)
	runner.check(_near(s.total, 100) and s.parts.technique < 0, "관문 없으면 85 → 100, 기술 항목 없음(−1) %s" % [s])
	var rec := _rec(r)
	rec.finish = {"feet": 0, "phase": "REBALANCING"}
	runner.check(_near(ScoreCalc.score(rec, r).parts.finish, 4), "두 손만 탑이면 마무리 4")
	rec.finish = {"feet": 1, "phase": "STRAINED"}
	runner.check(_near(ScoreCalc.score(rec, r).parts.finish, 7), "발 하나 +2, 버티기 힘든 자세 +1 → 7")


func test_helped_flag() -> void:
	var r := _route()
	var rec := _rec(r)
	rec.helped = true
	runner.check(ScoreCalc.score(rec, r).helped, "도움 표시")


## 실제 세션을 읽는 기록기: 손 힘 감소만 더하고 회복은 빼지 않는다.
func test_recorder_counts_spent_not_recovery() -> void:
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/G_V3_03.json"))
	var rec := ScoreRecorder.new()
	rec.tick(s, "")
	s.rules.stamina[&"LH"] = float(s.rules.stamina[&"LH"]) - 5.0
	rec.tick(s, "")
	s.rules.stamina[&"LH"] = float(s.rules.stamina[&"LH"]) + 5.0
	rec.tick(s, "")
	runner.check(absf(rec.to_dict().spent - 5.0) < 0.5, "감소 5만 셈(회복 무시) %s" % rec.to_dict().spent)
	runner.check(rec.to_dict().has("strained_ticks") and rec.to_dict().has("danger_ticks") and rec.to_dict().has("barn_ticks"), "자세별 틱 수")
	runner.check(rec.to_dict().ticks == 3, "틱 수")


## 실제 봇: 정답 순서로 오르면 관문을 맞춘다(V3 세 문제).
func test_bot_hits_gates() -> void:
	for id in ["G_V3_02", "G_V3_03", "G_V3_04"]:
		var r := RouteDef.load_json("res://tests/fixtures/%s.json" % id)  # 옛 일반 문제(시험용)
		var rec := ScoreRecorder.new()
		var bot := SessionBot.run(r, r.intended_moves, {}, rec)
		var gates: Array = load("res://tools/score_ref.gd").gates(r)
		var gl := []
		for g in gates:
			gl.append({"technique": StringName(g.technique), "slot": g.slot})
		runner.check(bot.ok() and ScoreCalc.gates_hit(rec.to_dict().events, gl) == gl.size(), "%s 관문 %s" % [id, gl])


## 문제에 적어 둔 기준값이 지금 정답 순서 재생과 맞는다(문제·조정값을 고치면 tools/score_ref.gd로 다시 잼).
func test_stored_refs_match_bot() -> void:
	var idx := ContentIndex.load_all()
	for r in idx.all_routes():
		if r.mode != "general":
			continue
		var m: Dictionary = load("res://tools/score_ref.gd").measure(r)
		var ok: bool = not r.score_ref.is_empty() and absf(float(r.score_ref.spent_per_m) - float(m.ref.spent_per_m)) < 0.05 and int(r.score_ref.grabs) == int(m.ref.grabs) \
			and absf(float(r.score_ref.get("quality", -1.0)) - float(m.ref.quality)) < 0.005 and r.score_gates.size() == m.gates.size()
		runner.check(ok, "%s 기준값 %s ↔ 잰 값 %s" % [r.route_id, r.score_ref, m.ref])
