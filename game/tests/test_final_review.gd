extends RefCounted
## 최종 리뷰 수정: 이동 중 취소, 접점 edge 캐시, 풀기 버튼, 데드포인트 중 선택 금지, 점유 재검사, 가벼운 판단, 패드 풋스왑.

var runner

const FAR := Vector2(3.0, 3.8)


func _g_v0_01() -> RouteDef:
	return RouteDef.load_json("res://data/routes/general/G_V0_01.json")


func _session(r: RouteDef, settle: int = 30) -> ClimbSession:
	var s := ClimbSession.new(r)
	for i in settle:
		s.step()
	return s


func _run_ticks(s: ClimbSession, n: int) -> String:
	for i in n:
		var r := s.step()
		if r.begins_with("fall"):
			return r
	return ""


## 기술 실행기 이벤트(id가 있는 것) 중 마지막. 패드 기술 이벤트(move·grab 등)는 건너뛴다.
func _last_event(s: ClimbSession) -> Dictionary:
	var evs := s.technique_log.filter(func(e): return e.has("id"))
	return evs.back() if not evs.is_empty() else {}


## 1: 아웃사이드 엣지 이동 중 "풀기"로 취소하면 움직이던 발은 Free(터치 없는 Dragging 금지).
func test_move_cancel_frees_moving_limb() -> void:
	var s := _session(_g_v0_01())
	var key := "G_V0_01/F04/foot_1"
	runner.check(s.runner.start(s, &"T_OUTSIDE_EDGE", &"right", key, s.route.slot_pos(key)) == &"", "아웃사이드 엣지 시작")
	for i in 4:
		s.step()
	runner.check(s.limbs[&"RF"].state == "Dragging", "전제: RF 이동 중")
	runner.check(s.cancel_technique(), "취소 true")
	runner.check(s.runner.active.is_empty(), "취소됨")
	runner.check(s.limbs[&"RF"].state == "Free", "RF Free (%s)" % s.limbs[&"RF"].state)
	runner.check(not s.is_dragging(), "is_dragging false")
	s.step()
	runner.check(_last_event(s).get("type") == TechniqueRunner.CANCELLED, "cancelled 이벤트")
	var j := TechniqueJudge.judge(ClimbSnapshot.from_session(s), &"T_DROP_KNEE")
	runner.check(j.left.reason != TechniqueJudge.WRONG_PHASE, "WRONG_PHASE 아님 (%s)" % j.left.reason)


## 2: 접점 edge가 제자리에서 바뀌면 평가 캐시가 무효화되어 barn door 용량이 바뀐다.
func test_edge_change_invalidates_eval_cache() -> void:
	var rules := ClimbRules.new()
	var line := {PoseSolver.LH: Vector2(-0.40, 1.75), PoseSolver.LF: Vector2(-0.38, 0.35)}
	rules.contact_meta = {
		PoseSolver.LH: ContactInfo.make("h", line[PoseSolver.LH], 1.0, &"pull", &""),
		PoseSolver.LF: ContactInfo.make("f", line[PoseSolver.LF], 1.0, &"foot", &"inside"),
	}
	rules.feet_eligible = [PoseSolver.LF]
	rules.loaded_feet = [PoseSolver.LF]
	rules._ctx_attached = line
	rules._ctx_endpoints = {PoseSolver.RF: Vector2(0.20, 0.30), PoseSolver.RH: Vector2(0.20, 1.60)}
	rules._ctx_platform = false
	rules._ctx_yaw = 0.0
	var a := rules._evaluate_cached(Vector2(0.20, 1.0), 0.0)
	var cap_inside: float = a.barn.capacity
	rules.contact_meta[PoseSolver.LF].edge = &"drop_knee"
	var b := rules._evaluate_cached(Vector2(0.20, 1.0), 0.0)
	runner.check(absf(b.barn.capacity - cap_inside) > 1e-6, "용량 변화 (%.4f → %.4f)" % [cap_inside, b.barn.capacity])


## 3: 실행 중 버튼 "풀기" = cancel_technique. 드롭니 → 취소 → ψ 목표 NAN, edge inside.
func test_cancel_technique_releases_drop_knee() -> void:
	var s := _session(_g_v0_01())
	runner.check(not s.cancel_technique(), "실행 없으면 false")
	runner.check(s.runner.start(s, &"T_DROP_KNEE", &"left") == &"", "드롭니 시작")
	_run_ticks(s, 90)
	runner.check(not is_nan(s.rules.yaw_target) and s.rules.contact_meta[&"LF"].edge == &"drop_knee", "전제: 드롭니 유지")
	# Ruling 9: 실행 중 다른 기술은 WRONG_PHASE
	var j := TechniqueJudge.judge(ClimbSnapshot.from_session(s), &"T_OUTSIDE_EDGE")
	runner.check(j.left.reason == TechniqueJudge.WRONG_PHASE and j.right.reason == TechniqueJudge.WRONG_PHASE, "아웃사이드 엣지 WRONG_PHASE")
	runner.check(s.cancel_technique(), "취소 true")
	runner.check(s.runner.active.is_empty() and is_nan(s.rules.yaw_target), "active 비움·yaw_target NAN")
	runner.check(s.limbs[&"LF"].contact.edge == &"inside", "edge inside")
	s.step()
	runner.check(_last_event(s).get("type") == TechniqueRunner.CANCELLED, "cancelled 이벤트")


## 4: 데드포인트 비행 중에는 선택을 열 수 없고 판단은 WRONG_PHASE.
func test_no_select_during_deadpoint_flight() -> void:
	var s := _session(_g_v0_01())
	var key := "G_V0_01/H02/hand_1"
	s.start_deadpoint(&"LH", key, s.route.slot_pos(key), 0.1)
	runner.check(not s.open_select() and not s.selecting, "선택 열리지 않음")
	var j := TechniqueJudge.judge(ClimbSnapshot.from_session(s), &"T_DROP_KNEE")
	runner.check(j.left.reason == TechniqueJudge.WRONG_PHASE, "WRONG_PHASE (%s)" % j.left.reason)


## 5: 이동 중 다른 팔다리가 목표 자리를 차지하면 OCCUPIED로 실패하고 그 발은 Free.
func test_runner_respects_occupancy_during_move() -> void:
	var s := _session(_g_v0_01())
	var key := "G_V0_01/F04/foot_1"
	runner.check(s.runner.start(s, &"T_OUTSIDE_EDGE", &"right", key, s.route.slot_pos(key)) == &"", "아웃사이드 엣지 시작")
	for i in 4:
		s.step()
	runner.check(s.limbs[&"RF"].state == "Dragging", "전제: RF 이동 중")
	var p := s.route.slot_pos(key)
	var lf: Dictionary = s.limbs[&"LF"]  # 패드가 다른 발을 그 자리에 놓은 상황
	lf.state = "Attached"
	lf.key = key
	lf.grab = p
	lf.pos = p
	lf.contact = GripCheck.contact_for(key, s.route.slots, &"LF", p)
	s.step()
	var ev := _last_event(s)
	runner.check(ev.get("type") == TechniqueRunner.FAILED and ev.get("reason") == GripCheck.OCCUPIED, "failed OCCUPIED: %s" % [ev])
	runner.check(s.limbs[&"RF"].state == "Free" and s.runner.active.is_empty(), "RF Free·active 비움")
	runner.check(s.limbs[&"LF"].key == key, "LF 그대로")


## 6: light_judge는 같은 모양이고 힘 계산이 필요한 이유(드롭니 ψ 자세의 힘 균형)는 보지 않는다.
func test_light_judge_shape_and_cheaper() -> void:
	var s := _session(_g_v0_01())
	var snap := ClimbSnapshot.from_session(s)
	for id in TechniqueJudge.defs():
		var h := TechniqueJudge.judge(snap, id)
		var l := TechniqueJudge.light_judge(snap, id)
		runner.check(h.keys() == l.keys(), "%s 쪽 구성 같음" % id)
		for side in l:
			runner.check(l[side].has_all(["available", "reason", "reasons", "text"]), "%s 모양" % id)
			runner.check(l[side].available or not h[side].available, "%s: 가벼운 판단은 무거운 판단보다 엄격하지 않다" % id)
	var t0 := Time.get_ticks_usec()
	for id in TechniqueJudge.defs():
		TechniqueJudge.light_judge(snap, id)
	var light_ms := (Time.get_ticks_usec() - t0) / 1000.0
	runner.check(light_ms < 30.0, "가벼운 판단 전체 %.1fms" % light_ms)


## 7: 패드로 끈 발을 반대 발이 딛은 발판에 놓으면 풋스왑(들어온 발 붙음, 반대 발 같은 틱에 풀림).
func test_pad_foot_swap() -> void:
	var s := _session(_g_v0_01())
	var key := "G_V0_01/F01/foot_1"
	runner.check(s.limbs[&"LF"].key == key, "전제: LF가 F01")
	var target := s.route.slot_pos(key)
	s.apply_input([{"type": "arm", "limb": &"RF"}, {"type": "detach", "limb": &"RF"}])
	var reached := false
	for i in 200:
		var req: Vector2 = s.limbs[&"RF"].req
		s.apply_input([{"type": "move", "limb": &"RF", "delta": (target - req).limit_length(2.5 * Tuning.DT)}])
		var r := s.step()
		runner.check(not r.begins_with("fall"), "추락 없음")
		if (s.limbs[&"RF"].pos as Vector2).distance_to(target) < 0.02:
			reached = true
			break
	runner.check(reached, "RF가 F01 근처에 도달")
	s.apply_input([{"type": "release", "limb": &"RF"}])
	runner.check(s.limbs[&"RF"].state == "Attached" and s.limbs[&"RF"].key == key, "RF가 F01에 붙음 (%s %s)" % [s.limbs[&"RF"].state, s.limbs[&"RF"].key])
	runner.check(s.limbs[&"LF"].state == "Free", "LF 해제 (%s)" % s.limbs[&"LF"].state)
	var out := _run_ticks(s, 90)
	runner.check(out == "", "균형 유지 (%s)" % out)
