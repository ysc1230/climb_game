extends RefCounted
## 기술 판단기(docs/27 §7, §10, §11): 7단계 순서·이유, 홀드 후보, 스냅숏 독립성, 비용. 버튼 기술(아웃사이드 엣지·드롭니)만 판단한다(docs/28 §4).

var runner

const PHASE1_SIDES := [&"left", &"right"]


func _g_v0_01() -> RouteDef:
	return RouteDef.load_json("res://data/routes/general/G_V0_01.json")


func _tx() -> RouteDef:
	return RouteDef.load_json("res://data/routes/TX_TECH.json")


func _session(r: RouteDef, settle: int = 30) -> ClimbSession:
	var s := ClimbSession.new(r)
	for i in settle:
		s.step()
	return s


func _button_ids() -> Array:
	return Array(TechniqueDefs.button_ids())


## limb을 key까지 패드로 끌어 놓는다(test_session과 같은 방식).
func _drag_to(s: ClimbSession, limb: StringName, key: String, budget: int = 300) -> bool:
	var target := s.route.slot_pos(key)
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in budget:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(2.5 * Tuning.DT)}])
		if s.step().begins_with("fall"):
			return false
		if s.limbs[limb].cand.get("key", "") == key:
			s.apply_input([{"type": "release", "limb": limb}])
			return s.limbs[limb].state == "Attached" and s.limbs[limb].key == key
	return false


func test_wrong_phase_when_falling() -> void:
	var s := _session(_g_v0_01())
	s.falling = true
	var snap := ClimbSnapshot.from_session(s)
	var bad := []
	for id in _button_ids():
		var j := TechniqueJudge.judge(snap, id)
		for side in j:
			if j[side].available or j[side].reason != TechniqueJudge.WRONG_PHASE:
				bad.append("%s/%s" % [id, side])
	runner.check(bad.is_empty(), "낙하 중에는 모든 쪽 WRONG_PHASE: %s" % [bad])


func test_unsupported_techniques_marked() -> void:
	var snap := ClimbSnapshot.from_session(_session(_g_v0_01()))
	for id in [&"T_HEEL_HOOK", &"T_SMEAR", &"T_HIGH_STEP", &"T_CROSS"]:
		var j := TechniqueJudge.judge(snap, id)
		runner.check(not j.left.available and j.left.reason == TechniqueJudge.MOVE_NOT_SUPPORTED, "%s 미지원 표시 %s" % [id, j.left])


## 아웃사이드 엣지 후보는 pivot 가능한 발판만, 손홀드 탭은 TYPE_MISMATCH, 이미 딛은 발판도 후보가 된다.
func test_outside_edge_hold_checks() -> void:
	var r := _g_v0_01()
	r.slots["G_V0_01/F04/foot_1"].pivot_allowed = false
	var s := _session(r)
	var snap := ClimbSnapshot.from_session(s)
	var keys: Array = TechniqueJudge.hold_targets(snap, &"T_OUTSIDE_EDGE", &"right").map(func(t): return t.key)
	runner.check(keys.has("G_V0_01/F02/foot_1") and not keys.has("G_V0_01/F04/foot_1"), "pivot 불가 F04 제외: %s" % [keys])
	var c := TechniqueJudge.check_hold(snap, &"T_OUTSIDE_EDGE", &"right", "G_V0_01/F04/foot_1", Vector2.INF)
	runner.check(not c.ok and c.reason == TechniqueJudge.PIVOT_NOT_ALLOWED, "pivot 불가 탭 거부: %s" % [c])
	var h := TechniqueJudge.check_hold(snap, &"T_OUTSIDE_EDGE", &"right", "G_V0_01/H01/hand_1", Vector2.INF)
	runner.check(not h.ok and h.reason == GripCheck.TYPE_MISMATCH, "손홀드 탭 거부: %s" % [h])


## TA11: 패드로 만든 자세와 세션 필드를 직접 설정한 같은 자세의 판단이 같다(이력에 의존하지 않음).
func test_same_snapshot_same_result() -> void:
	var a := _session(_g_v0_01())
	runner.check(_drag_to(a, &"LF", "G_V0_01/F03/foot_1"), "전제: 패드로 LF를 F03으로")
	for i in 90:
		a.step()
	var b := ClimbSession.new(_g_v0_01())
	b.body.pos = a.body.pos
	b.body.angle = a.body.angle
	b.body.yaw = a.body.yaw
	for limb in a.limbs:
		var la: Dictionary = a.limbs[limb]
		var lb: Dictionary = b.limbs[limb]
		lb.state = la.state
		lb.key = la.key
		lb.grab = la.grab
		lb.pos = la.pos
		lb.req = la.pos
		lb.contact = GripCheck.contact_for(la.key, b.route.slots, limb, la.grab) if la.contact != null else null
	b.rules.contact_meta = b._contact_meta()
	b.rules.reset(b.body, b.attached(), {}, b.on_platform(b.attached()))
	var sa := ClimbSnapshot.from_session(a)
	var sb := ClimbSnapshot.from_session(b)
	var diff := []
	for id in _button_ids():
		var ja := TechniqueJudge.judge(sa, id)
		var jb := TechniqueJudge.judge(sb, id)
		for side in ja:
			if ja[side].available != jb[side].available or ja[side].reasons != jb[side].reasons:
				diff.append("%s/%s %s vs %s" % [id, side, ja[side].reasons, jb[side].reasons])
	runner.check(diff.is_empty(), "같은 판단: %s" % [diff])
	for side in PHASE1_SIDES:
		var ta := TechniqueJudge.hold_targets(sa, &"T_OUTSIDE_EDGE", side).map(func(t): return t.key)
		var tb := TechniqueJudge.hold_targets(sb, &"T_OUTSIDE_EDGE", side).map(func(t): return t.key)
		runner.check(ta == tb, "같은 홀드 후보 %s: %s vs %s" % [side, ta, tb])


## 판정 7: 사이드풀의 힘 축은 몸→홀드(바깥), 개스턴은 홀드→몸(안쪽). 시작 골반 기준으로 부호 확인.
func test_tx_tech_axes_match_modes() -> void:
	var r := _tx()
	var px := r.start_pelvis.x
	var seen := {}
	for key in r.slots:
		var slot: Dictionary = r.slots[key]
		var dx: float = slot.pos.x - px
		for gm in slot.grip_modes:
			if gm.mode == &"sidepull":
				seen[gm.mode] = true
				runner.check(signf(gm.axis.x) == signf(dx), "%s 사이드풀 축 %s는 바깥(홀드 x−골반 x %.2f)" % [key, gm.axis, dx])
			elif gm.mode == &"gaston":
				seen[gm.mode] = true
				runner.check(signf(gm.axis.x) == -signf(dx), "%s 개스턴 축 %s는 안쪽(홀드 x−골반 x %.2f)" % [key, gm.axis, dx])
	runner.check(seen.has(&"sidepull") and seen.has(&"gaston"), "두 방식 모두 검사됨")


## 27 §7.1 비용: 기술 버튼 1회(쪽별 판단) 평균 ≤ 30ms, 쪽 선택 뒤 hold_targets ≤ 30ms.
func test_judge_cost() -> void:
	var snap := ClimbSnapshot.from_session(_session(_tx()))
	var supported := _button_ids()
	runner.check(supported.all(func(id): return TechniqueJudge.SUPPORTED.has(id)), "버튼 기술은 모두 판단 대상: %s" % [supported])
	var t0 := Time.get_ticks_usec()
	for id in supported:
		TechniqueJudge.judge(snap, id)
	var total := (Time.get_ticks_usec() - t0) / 1000.0
	var avg := total / supported.size()
	print("    판단 비용: 지원 기술 %d개 총 %.2fms, 평균 %.2fms" % [supported.size(), total, avg])
	runner.check(avg <= 30.0, "평균 ≤ 30ms (%.2f)" % avg)
	for id in TechniqueJudge.MOVE_TECHS:
		for side in PHASE1_SIDES:
			var t1 := Time.get_ticks_usec()
			var n := TechniqueJudge.hold_targets(snap, id, side).size()
			var ms := (Time.get_ticks_usec() - t1) / 1000.0
			print("    hold_targets %s/%s: %.2fms (후보 %d)" % [id, side, ms, n])
			runner.check(ms <= 30.0, "hold_targets %s/%s ≤ 30ms (%.2f)" % [id, side, ms])
