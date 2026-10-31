extends RefCounted
## 기술 판단기(docs/27 §7, §10, §11): 7단계 순서·이유, 홀드 후보, 스냅숏 독립성, 비용.

var runner

const PHASE1_SIDES := [&"left", &"right"]


func _r01() -> RouteDef:
	return RouteDef.load_json("res://data/routes/R01.json")


func _tx() -> RouteDef:
	return RouteDef.load_json("res://data/routes/TX_TECH.json")


func _session(r: RouteDef, settle: int = 30) -> ClimbSession:
	var s := ClimbSession.new(r)
	for i in settle:
		s.step()
	return s


func _phase1_ids() -> Array:
	var out := []
	var defs := TechniqueJudge.defs()
	for id in defs:
		if defs[id].phase == 1:
			out.append(id)
	return out


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


func _drag_into_air(s: ClimbSession, limb: StringName, dir: Vector2) -> void:
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in 40:
		s.apply_input([{"type": "move", "limb": limb, "delta": dir * 2.5 * Tuning.DT}])
		s.step()
	s.apply_input([{"type": "release", "limb": limb}])


func test_wrong_phase_when_falling() -> void:
	var s := _session(_r01())
	s.falling = true
	var snap := ClimbSnapshot.from_session(s)
	var bad := []
	for id in _phase1_ids():
		var j := TechniqueJudge.judge(snap, id)
		for side in j:
			if j[side].available or j[side].reason != TechniqueJudge.WRONG_PHASE:
				bad.append("%s/%s" % [id, side])
	runner.check(bad.is_empty(), "낙하 중에는 모든 쪽 WRONG_PHASE: %s" % [bad])
	var rest := TechniqueJudge.judge(snap, &"T_REST")
	runner.check(rest.keys() == [&"none"], "좌우 없는 기술은 none 하나: %s" % [rest.keys()])


func test_unsupported_techniques_marked() -> void:
	var snap := ClimbSnapshot.from_session(_session(_r01()))
	for id in [&"T_OUTSIDE_EDGE", &"T_DROP_KNEE", &"T_FLAG", &"T_FLAG_INSIDE", &"T_FLAG_OUTSIDE", &"T_DEADPOINT", &"T_HEEL_HOOK", &"T_SMEAR"]:
		var j := TechniqueJudge.judge(snap, id)
		runner.check(not j.left.available and j.left.reason == TechniqueJudge.MOVE_NOT_SUPPORTED, "%s 미지원 표시 %s" % [id, j.left])


## TA02: 왼손 하나와 두 발(플랫폼 아님)에서 왼손을 떼는 크로스는 SUPPORT_NEEDED.
func test_support_needed_when_last_hand() -> void:
	var s := _session(_r01())
	runner.check(_drag_to(s, &"LF", "R01/F03/foot_1"), "전제: LF를 F03으로")
	for i in 60:
		s.step()
	_drag_into_air(s, &"RH", Vector2(1, 0))
	for i in 30:
		s.step()
	runner.check(not s.falling and s.limbs[&"RH"].state == "Free", "전제: RH 자유, 버팀 (%s)" % s.limbs[&"RH"].state)
	var snap := ClimbSnapshot.from_session(s)
	runner.check(not snap.platform, "전제: 플랫폼 지지 아님")
	var j: Dictionary = TechniqueJudge.judge(snap, &"T_CROSS").left
	runner.check(not j.available and j.reason == TechniqueJudge.SUPPORT_NEEDED, "T_CROSS left SUPPORT_NEEDED: %s" % [j])
	runner.check(j.text == "이 손발을 떼면 버틸 수 없어요", "문구: %s" % j.text)


## TA03: 하이스텝 후보는 Y ≥ 고관절 Y − 0.20인 발판만.
func test_high_step_targets_only_high_holds() -> void:
	var s := _session(_r01())
	var snap := ClimbSnapshot.from_session(s)
	var hip_y := PoseSolver.joint_position(snap.body.pos, snap.body.angle, &"LF", snap.body.yaw).y
	var targets := TechniqueJudge.hold_targets(snap, &"T_HIGH_STEP", &"left")
	var keys := []
	for t in targets:
		keys.append(t.key)
		runner.check(s.route.slot_pos(t.key).y >= hip_y - 0.20, "%s는 고관절−0.20 이상" % t.key)
	runner.check(keys.has("R01/F03/foot_1"), "F03 후보: %s" % [keys])
	runner.check(not keys.has("R01/F01/foot_1"), "낮은 F01 제외: %s" % [keys])
	var c := TechniqueJudge.check_hold(snap, &"T_HIGH_STEP", &"left", "R01/F01/foot_1", Vector2.INF)
	runner.check(not c.ok and c.reason == TechniqueJudge.NO_HOLD, "강조 안 된 홀드 탭 거부: %s" % [c])
	var h := TechniqueJudge.check_hold(snap, &"T_HIGH_STEP", &"left", "R01/H01/hand_1", Vector2.INF)
	runner.check(not h.ok and h.reason == GripCheck.TYPE_MISMATCH, "손홀드 탭 거부: %s" % [h])


## TA10: 좁은 홀드(반폭 0.04)는 매치 불가, R01 큰 홀드(반폭 0.12)는 매치 후 두 손 품질 ≥ 0.85.
func test_match_needs_room() -> void:
	var tx := _tx()
	var narrow := "TX_TECH/N01/hand_1"
	tx.slots[narrow].pos = tx.slot_pos("TX_TECH/H01/hand_1")  # 왼손이 좁은 홀드를 잡은 시작 자세
	tx.start_slots[&"LH"] = narrow
	var s := _session(tx)
	var snap := ClimbSnapshot.from_session(s)
	var j: Dictionary = TechniqueJudge.judge(snap, &"T_MATCH").right
	var c := TechniqueJudge.check_hold(snap, &"T_MATCH", &"right", narrow, tx.slot_pos(narrow))
	runner.check((not j.available and j.reason == TechniqueJudge.NO_HOLD) or (not c.ok and c.reason == GripCheck.OCCUPIED), "좁은 홀드 매치 불가: %s / %s" % [j, c])
	runner.check(not c.ok, "좁은 홀드 탭 거부: %s" % [c])

	var r := _session(_r01())
	var key := "R01/H02/hand_1"
	var jr: Dictionary = TechniqueJudge.judge(ClimbSnapshot.from_session(r), &"T_MATCH").left
	runner.check(jr.available, "R01 매치 왼쪽 가능: %s" % [jr])
	var why := r.runner.start(r, &"T_MATCH", &"left", key, r.route.slot_pos(key))
	runner.check(why == &"", "매치 시작: %s" % why)
	for i in 150:
		r.step()
		if r.runner.active.is_empty():
			break
	runner.check(r.limbs[&"LH"].state == "Attached" and r.limbs[&"LH"].key == key and r.limbs[&"RH"].key == key, "두 손 같은 홀드: LH %s %s, RH %s" % [r.limbs[&"LH"].state, r.limbs[&"LH"].key, r.limbs[&"RH"].key])
	var lq: float = r.limbs[&"LH"].contact.quality if r.limbs[&"LH"].contact else 0.0
	var rq: float = r.limbs[&"RH"].contact.quality if r.limbs[&"RH"].contact else 0.0
	runner.check(lq >= 0.85 and rq >= 0.85, "두 손 품질 ≥ 0.85: LH %.3f RH %.3f" % [lq, rq])
	var iv_l := HoldArea.hand_interval(r.route.slots[key], r.limbs[&"LH"].grab)
	var iv_r := HoldArea.hand_interval(r.route.slots[key], r.limbs[&"RH"].grab)
	runner.check(not GripCheck.overlaps(iv_l, iv_r), "구간 안 겹침 %s %s" % [iv_l, iv_r])
	runner.check(r.technique_log.any(func(e): return e.type == TechniqueRunner.SUCCEEDED and e.id == &"T_MATCH"), "성공 기록: %s" % [r.technique_log])
	var again := TechniqueJudge.hold_targets(ClimbSnapshot.from_session(r), &"T_MATCH", &"left").map(func(t): return t.key)
	runner.check(not again.has(key), "이미 같은 홀드면 매치 후보 아님: %s" % [again])
	var cr := TechniqueJudge.check_hold(ClimbSnapshot.from_session(r), &"T_MATCH", &"left", key, r.route.slot_pos(key))
	runner.check(not cr.ok and cr.reason == TechniqueJudge.NO_HOLD, "이미 있는 홀드 탭 거부: %s" % [cr])


## TA05: 홀드 끝(t = 0.9, q = 0.19)을 잡은 손은 록오프 불가 GRIP_TOO_POOR.
func test_lock_off_blocked_by_edge_grip() -> void:
	var s := _session(_r01())
	var key: String = s.limbs[&"LH"].key
	var slot: Dictionary = s.route.slots[key]
	var p: Vector2 = slot.pos + slot.hand_area.dir * (0.9 * slot.hand_area.half_width)
	s.limbs[&"LH"].grab = p
	s.limbs[&"LH"].pos = p
	s.limbs[&"LH"].contact = GripCheck.contact_for(key, s.route.slots, &"LH", p)
	s.step()
	runner.check(absf(s.limbs[&"LH"].contact.quality - 0.19) < 0.001, "전제: q = 0.19 (%.3f)" % s.limbs[&"LH"].contact.quality)
	var j := TechniqueJudge.judge(ClimbSnapshot.from_session(s), &"T_LOCK_OFF")
	runner.check(not j.left.available and j.left.reason == TechniqueJudge.GRIP_TOO_POOR, "왼쪽 GRIP_TOO_POOR: %s" % [j.left])
	runner.check(j.left.text == "홀드를 너무 끝에 잡았어요", "문구 %s" % j.left.text)
	runner.check(j.right.available, "오른손(q=1)은 가능: %s" % [j.right])


## TA11: 패드로 만든 자세와 세션 필드를 직접 설정한 같은 자세의 판단이 같다(이력에 의존하지 않음).
func test_same_snapshot_same_result() -> void:
	var a := _session(_r01())
	runner.check(_drag_to(a, &"LF", "R01/F03/foot_1"), "전제: 패드로 LF를 F03으로")
	for i in 90:
		a.step()
	var b := ClimbSession.new(_r01())
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
	for id in _phase1_ids():
		var ja := TechniqueJudge.judge(sa, id)
		var jb := TechniqueJudge.judge(sb, id)
		for side in ja:
			if ja[side].available != jb[side].available or ja[side].reasons != jb[side].reasons:
				diff.append("%s/%s %s vs %s" % [id, side, ja[side].reasons, jb[side].reasons])
	runner.check(diff.is_empty(), "같은 판단: %s" % [diff])
	for side in PHASE1_SIDES:
		var ta := TechniqueJudge.hold_targets(sa, &"T_HIGH_STEP", side).map(func(t): return t.key)
		var tb := TechniqueJudge.hold_targets(sb, &"T_HIGH_STEP", side).map(func(t): return t.key)
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


## 27 §7.1 비용: 기술 버튼 1회(쪽별 판단) 평균 ≤ 30ms(지원 기술만), 쪽 선택 뒤 hold_targets ≤ 30ms.
func test_judge_cost() -> void:
	var snap := ClimbSnapshot.from_session(_session(_tx()))
	var ids := _phase1_ids()
	runner.check(ids.size() == 16, "1차 기술 16개 (%d)" % ids.size())
	var supported := ids.filter(func(id): return TechniqueJudge.SUPPORTED.has(id))
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
