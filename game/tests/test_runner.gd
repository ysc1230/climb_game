extends RefCounted
## 기술 실행기(docs/27 §6, §10, §11): 위치형 기술 실행, 홀드 자동 선택 없음, 패드 취소, 휴식·록오프 프로필.

var runner

const FAR := Vector2(3.0, 3.8)  # 시험에서 쓰지 않는 홀드를 치워 둘 곳


func _r01() -> RouteDef:
	return RouteDef.load_json("res://data/routes/R01.json")


func _tx() -> RouteDef:
	return RouteDef.load_json("res://data/routes/TX_TECH.json")


func _session(r: RouteDef, settle: int = 30) -> ClimbSession:
	var s := ClimbSession.new(r)
	for i in settle:
		s.step()
	return s


## 실행이 끝날 때까지(최대 budget틱) 진행. 추락 결과가 있으면 그 문자열.
func _run(s: ClimbSession, budget: int = 240) -> String:
	for i in budget:
		var r := s.step()
		if r.begins_with("fall"):
			return r
		if s.runner.active.is_empty():
			return ""
	return "timeout"


func _last_event(s: ClimbSession) -> Dictionary:
	return s.technique_log.back() if not s.technique_log.is_empty() else {}


func test_high_step_places_foot_then_rises() -> void:
	var s := _session(_r01())
	var y0 := s.body.pos.y
	var key := "R01/F03/foot_1"
	runner.check(s.runner.start(s, &"T_HIGH_STEP", &"left", key, s.route.slot_pos(key)) == &"", "하이스텝 시작")
	var r := _run(s)
	runner.check(r == "", "실행 완료 (%s)" % r)
	var lf: Dictionary = s.limbs[&"LF"]
	runner.check(lf.state == "Attached" and lf.key == key, "LF가 F03에 Attached: %s %s" % [lf.state, lf.key])
	runner.check(lf.contact != null and lf.contact.edge == &"inside", "edge inside")
	runner.check(s.body.pos.y - y0 >= 0.10, "골반 상승 ≥ 0.10 (%.3f)" % (s.body.pos.y - y0))
	var types: Array = s.technique_log.map(func(e): return e.type)
	runner.check(types == [TechniqueRunner.STARTED, TechniqueRunner.SUCCEEDED], "이벤트 started→succeeded: %s" % [types])
	runner.check(s.rules.profile_override.is_empty(), "끝나면 override 해제")


func test_cross_reaches_over() -> void:
	var s := _session(_r01())
	var f04 := "R01/F04/foot_1"
	runner.check(s.runner.start(s, &"T_HIGH_STEP", &"right", f04, s.route.slot_pos(f04)) == &"", "전제: 오른발 하이스텝")
	runner.check(_run(s) == "", "전제: 하이스텝 완료")
	for i in 60:
		s.step()
	var snap := ClimbSnapshot.from_session(s)
	var targets := TechniqueJudge.hold_targets(snap, &"T_CROSS", &"left")
	runner.check(not targets.is_empty(), "크로스 후보 있음")
	if targets.is_empty():
		return
	var rh_key: String = s.limbs[&"RH"].key
	var rh_x: float = s.limbs[&"RH"].grab.x
	var t: Dictionary = targets[0]
	runner.check(s.route.slot_pos(t.key).x > rh_x, "후보는 RH 오른쪽: %s" % t.key)
	runner.check(s.runner.start(s, &"T_CROSS", &"left", t.key, t.area_center) == &"", "크로스 시작")
	var r := _run(s)
	runner.check(r == "", "실행 완료 (%s)" % r)
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == t.key, "LH가 %s에 붙음: %s %s" % [t.key, s.limbs[&"LH"].state, s.limbs[&"LH"].key])
	runner.check(s.limbs[&"LH"].grab.x > s.limbs[&"RH"].grab.x, "LH가 RH보다 오른쪽")
	runner.check(s.limbs[&"RH"].key == rh_key and s.limbs[&"RH"].state == "Attached", "RH는 그대로(ID 유지)")


## TA12: 홀드를 고르지 않은 hold_tap 기술은 시작하지 않고 아무것도 움직이지 않는다.
func test_no_auto_hold() -> void:
	var s := _session(_r01())
	var before := {}
	for limb in s.limbs:
		before[limb] = [s.limbs[limb].state, s.limbs[limb].key, s.limbs[limb].grab]
	var why := s.runner.start(s, &"T_HIGH_STEP", &"left", "")
	runner.check(why == TechniqueJudge.NO_HOLD, "NO_HOLD (%s)" % why)
	runner.check(s.runner.active.is_empty(), "실행 없음")
	for i in 30:
		s.step()
	for limb in s.limbs:
		runner.check([s.limbs[limb].state, s.limbs[limb].key, s.limbs[limb].grab] == before[limb], "%s 그대로" % limb)
	runner.check(s.technique_log.is_empty(), "이벤트 없음")


## TA09: 실행 중 그 팔다리 패드를 누르면 취소되고 패드 조작으로 넘어간다.
func test_pad_touch_cancels() -> void:
	var s := _session(_r01())
	runner.check(s.runner.start(s, &"T_LOCK_OFF", &"left") == &"", "록오프 시작")
	for i in 5:
		s.step()
	runner.check(s.rules.profile_override.get(&"LH", 0.0) == TechniqueJudge.LOCK_OFF_PREF, "전제: 실행 중")
	var busy: Dictionary = TechniqueJudge.judge(ClimbSnapshot.from_session(s), &"T_CROSS").right
	runner.check(busy.reason == TechniqueJudge.WRONG_PHASE, "실행 중 다른 기술은 WRONG_PHASE: %s" % [busy])
	s.apply_input([{"type": "arm", "limb": &"LH"}])
	runner.check(s.runner.active.is_empty(), "arm으로 active 비움")
	runner.check(s.rules.profile_override.is_empty() and s.rules.fatigue_multiplier.is_empty(), "override 해제")
	s.step()
	var ev := _last_event(s)
	runner.check(ev.get("type") == TechniqueRunner.CANCELLED and ev.get("id") == &"T_LOCK_OFF", "cancelled 이벤트: %s" % [ev])
	runner.check(s.limbs[&"LH"].state == "Armed", "패드 조작으로 전환(Armed)")

	var m := _session(_r01())
	var key := "R01/F03/foot_1"
	runner.check(m.runner.start(m, &"T_HIGH_STEP", &"left", key, m.route.slot_pos(key)) == &"", "하이스텝 시작")
	for i in 4:
		m.step()
	runner.check(m.limbs[&"LF"].state == "Dragging", "전제: 발 이동 중")
	m.apply_input([{"type": "arm", "limb": &"RF"}])  # 다른 팔다리 패드는 취소하지 않음
	runner.check(not m.runner.active.is_empty(), "다른 발 패드는 유지")
	m.apply_input([{"type": "disarm", "limb": &"RF"}, {"type": "detach", "limb": &"LF"}])
	runner.check(m.runner.active.is_empty(), "그 발 detach로 취소")
	m.step()
	runner.check(_last_event(m).get("type") == TechniqueRunner.CANCELLED, "cancelled 이벤트")


func test_rest_and_lock_off_profiles() -> void:
	var s := _session(_r01())
	runner.check(s.runner.start(s, &"T_REST", &"none") == &"", "휴식 시작")
	s.step()
	var p := s.rules.effective_profile()
	runner.check(p[&"LH"] == 0.70 and p[&"RH"] == 0.70 and p[&"LF"] == 0.86 and p[&"RF"] == 0.86, "휴식 프로필: %s" % [p])
	s.apply_input([{"type": "arm", "limb": &"RF"}])
	runner.check(s.runner.active.is_empty() and s.rules.profile_override.is_empty(), "패드 조작으로 휴식 끝")
	s.step()
	runner.check(_last_event(s).get("type") == TechniqueRunner.SUCCEEDED, "휴식 끝은 succeeded: %s" % [_last_event(s)])
	s.apply_input([{"type": "disarm", "limb": &"RF"}])

	runner.check(s.runner.start(s, &"T_LOCK_OFF", &"right") == &"", "록오프 시작")
	s.step()
	runner.check(s.rules.effective_profile()[&"RH"] == 0.42, "그 손 0.42: %s" % [s.rules.effective_profile()])
	runner.check(s.rules.fatigue_multiplier == {&"RH": 1.5}, "그 손 피로 ×1.5: %s" % [s.rules.fatigue_multiplier])
	# 반대 손이 떨어졌다가 다시 잡으면 끝
	var key: String = s.limbs[&"LH"].key
	var grab: Vector2 = s.limbs[&"LH"].grab
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	s.step()
	runner.check(not s.runner.active.is_empty(), "반대 손 패드는 록오프 유지")
	s.grab(&"LH", key, grab, GripCheck.contact_for(key, s.route.slots, &"LH", grab))
	s.step()
	runner.check(s.runner.active.is_empty() and _last_event(s).get("type") == TechniqueRunner.SUCCEEDED, "반대 손이 잡으면 끝: %s" % [_last_event(s)])


## 피로 배율: 같은 틱에서 음수 변화율만 ×배율.
func test_fatigue_multiplier_scales_drain() -> void:
	var att := {&"LH": Vector2(-0.45, 1.80), &"RH": Vector2(0.45, 1.80), &"LF": Vector2(-0.30, 0.40), &"RF": Vector2(0.30, 0.40)}
	var drops := []
	for mult in [1.0, 1.5]:
		var rules := ClimbRules.new()
		var body := BodyState.new(Vector2(0, 0.95))
		rules.reset(body, att, {}, false)
		rules.fatigue_multiplier = {&"RH": mult}
		rules.tick(body, att, {}, false, true)
		drops.append(100.0 - rules.stamina[&"RH"])
	runner.check(drops[0] > 0.0 and absf(drops[1] - 1.5 * drops[0]) < 1e-6, "감소 ×1.5: %s" % [drops])


## 27 §10: 사이드풀·개스턴·언더클링은 기하 조건이 맞는 쪽만 가능, 실행 후 접점 방식이 그 방식.
func test_sidepull_gaston_undercling_conditions() -> void:
	var cases := [
		[&"T_SIDEPULL", "TX_TECH/S01/hand_1", &"LH", Vector2(-0.35, 0.40), &"sidepull"],
		[&"T_GASTON", "TX_TECH/K01/hand_1", &"LH", Vector2(-0.30, 0.05), &"gaston"],
	]
	for c in cases:
		var r := _tx()
		for k in ["TX_TECH/S01/hand_1", "TX_TECH/S02/hand_1", "TX_TECH/K01/hand_1", "TX_TECH/U01/hand_1"]:
			r.slots[k].pos = FAR
		var s := _session(r)
		var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, c[2], s.body.yaw)
		r.slots[c[1]].pos = sh + c[3]
		var j := TechniqueJudge.judge(ClimbSnapshot.from_session(s), c[0])
		runner.check(j.left.available, "%s 왼쪽 가능: %s" % [c[0], j.left])
		runner.check(not j.right.available and j.right.reason == TechniqueJudge.NO_HOLD, "%s 오른쪽 NO_HOLD: %s" % [c[0], j.right])
		runner.check(s.runner.start(s, c[0], &"left", c[1], r.slots[c[1]].pos) == &"", "%s 시작" % c[0])
		var out := _run(s)
		var lh: Dictionary = s.limbs[&"LH"]
		runner.check(out == "" and lh.state == "Attached" and lh.key == c[1], "%s 붙음 (%s %s %s)" % [c[0], out, lh.state, lh.key])
		runner.check(s.rules.contact_meta.has(&"LH") and s.rules.contact_meta[&"LH"].mode == c[4], "contact_meta 방식 %s" % c[4])
	# 언더클링: 하중 받는 발이 높아야 한다. 하이스텝 전에는 불가, 후에는 가능.
	var r2 := _tx()
	for k in ["TX_TECH/S01/hand_1", "TX_TECH/S02/hand_1", "TX_TECH/K01/hand_1"]:
		r2.slots[k].pos = FAR
	var u := "TX_TECH/U01/hand_1"
	var s2 := _session(r2)
	var place := func() -> void:
		var shr := PoseSolver.joint_position(s2.body.pos, s2.body.angle, &"RH", s2.body.yaw)
		r2.slots[u].pos = shr + Vector2(0.20, -0.15)
	place.call()
	var before: Dictionary = TechniqueJudge.judge(ClimbSnapshot.from_session(s2), &"T_UNDERCLING").right
	runner.check(not before.available and before.reason == TechniqueJudge.NO_HOLD, "발이 낮으면 불가: %s" % [before])
	r2.slots[u].pos = FAR
	var f04 := "TX_TECH/F04/foot_1"
	runner.check(s2.runner.start(s2, &"T_HIGH_STEP", &"right", f04, r2.slot_pos(f04)) == &"", "전제: 오른발 하이스텝")
	runner.check(_run(s2) == "", "전제: 하이스텝 완료")
	for i in 60:
		s2.step()
	place.call()
	var after: Dictionary = TechniqueJudge.judge(ClimbSnapshot.from_session(s2), &"T_UNDERCLING").right
	runner.check(after.available, "높은 하중 발이면 가능: %s" % [after])
	runner.check(s2.runner.start(s2, &"T_UNDERCLING", &"right", u, r2.slot_pos(u)) == &"", "언더클링 시작")
	var out2 := _run(s2)
	runner.check(out2 == "" and s2.limbs[&"RH"].key == u and s2.limbs[&"RH"].state == "Attached", "언더클링 붙음 (%s %s)" % [out2, s2.limbs[&"RH"].key])
	runner.check(s2.rules.contact_meta.has(&"RH") and s2.rules.contact_meta[&"RH"].mode == &"undercling", "contact_meta 방식 undercling")


func test_foot_swap() -> void:
	var s := _session(_r01())
	var key := "R01/F01/foot_1"
	runner.check(s.runner.start(s, &"T_FOOT_SWAP", &"right", key, s.route.slot_pos(key)) == &"", "풋스왑 시작")
	var same_tick := false
	var seen := false
	for i in 200:
		var r := s.step()
		runner.check(not r.begins_with("fall"), "추락 없음")
		if not seen and s.limbs[&"RF"].state == "Attached" and s.limbs[&"RF"].key == key:
			seen = true
			same_tick = s.limbs[&"LF"].state == "Free"
		if s.runner.active.is_empty():
			break
	runner.check(seen and same_tick, "RF가 F01에 붙는 틱에 LF 해제 (seen %s, same %s)" % [seen, same_tick])
	runner.check(_last_event(s).get("type") == TechniqueRunner.SUCCEEDED, "성공: %s" % [_last_event(s)])
	var bad := ""
	for i in 120:
		var r := s.step()
		if r != "":
			bad = r
			break
	runner.check(bad == "" and s.rules.phase in [ClimbRules.Phase.STABLE, ClimbRules.Phase.STRAINED], "균형 유지 (%s, %s)" % [bad, s.rules.phase_name()])


## 체중 이동 후 도달(27 §11): 지금 자세로는 닿지 않는 홀드도 Shift로 90틱 안에 붙는다.
func test_needs_shift_succeeds() -> void:
	var s := _session(_r01())
	var key := "R01/H02/hand_1"
	var c := TechniqueJudge.check_hold(ClimbSnapshot.from_session(s), &"T_MATCH", &"left", key, s.route.slot_pos(key))
	runner.check(c.ok and c.needs_shift, "전제: 체중 이동 후 도달 %s" % [c])
	var p0 := s.body.pos
	var a0 := s.body.angle
	runner.check(s.runner.start(s, &"T_MATCH", &"left", key, s.route.slot_pos(key)) == &"", "시작")
	var ticks := 0
	while not s.runner.active.is_empty() and ticks < 200:
		s.step()
		ticks += 1
	runner.check(ticks <= TechniqueRunner.MOVE_BUDGET_TICKS + 1, "90틱 안에 끝 (%d)" % ticks)
	runner.check(_last_event(s).get("type") == TechniqueRunner.SUCCEEDED, "성공: %s" % [_last_event(s)])
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == key, "LH 붙음")
	var moved := s.body.pos.distance_to(p0) > 0.01 or absf(s.body.angle - a0) > 1.0
	runner.check(moved, "몸통이 옮겨짐 (Δpos %s, Δangle %.2f)" % [s.body.pos - p0, s.body.angle - a0])
	runner.check(not PoseSolver.can_reach(p0, a0, &"LH", s.limbs[&"LH"].grab, 0.0) or not PoseSolver.is_valid(p0, a0, s.attached(), 0.0), "시작 자세로는 그 접점 불가(체중 이동이 필요했음)")


## 닿지 않는 채로 90틱이 지나면 failed NEED_WEIGHT_SHIFT, 손발은 Free, override 해제.
## 판단 뒤 상태가 달라진 경우를 만들려고 실행이 시작된 뒤 목표점을 닿지 않는 곳으로 바꾼다.
func test_needs_shift_unreachable_fails() -> void:
	var s := _session(_r01())
	var key := "R01/H02/hand_1"
	runner.check(s.runner.start(s, &"T_MATCH", &"left", key, s.route.slot_pos(key)) == &"", "시작")
	s.step()
	runner.check(_last_event(s).get("type") == TechniqueRunner.STARTED and s.runner.active.needs_shift, "전제: started, needs_shift")
	s.runner.active.point = Vector2(1.6, 2.9)  # 몸을 옮겨도 닿지 않는 지점
	s.rules.fatigue_multiplier = {&"RH": 1.5}    # 끝날 때 해제되는지 보려는 표시
	var ticks := 0
	var fell := ""
	while not s.runner.active.is_empty() and ticks < 200:
		var r := s.step()
		if r.begins_with("fall"):
			fell = r
			break
		ticks += 1
	var ev := _last_event(s)
	runner.check(fell == "", "추락 없음 (%s)" % fell)
	runner.check(ev.get("type") == TechniqueRunner.FAILED and ev.get("reason") == TechniqueJudge.NEED_WEIGHT_SHIFT, "failed NEED_WEIGHT_SHIFT: %s" % [ev])
	runner.check(ticks <= TechniqueRunner.MOVE_BUDGET_TICKS + 1, "90틱 예산 (%d)" % ticks)
	runner.check(s.limbs[&"LH"].state == "Free", "LH Free (%s)" % s.limbs[&"LH"].state)
	runner.check(s.rules.profile_override.is_empty() and s.rules.fatigue_multiplier.is_empty(), "override·피로 배율 해제")
	runner.check(s.messages.has("먼저 체중을 옮겨야 해요"), "이유 문구 안내")


## 방식이 여럿인 홀드(M01: pull, sidepull)에서 T_SIDEPULL은 첫 방식이 아니라 sidepull로 잡는다.
func test_sidepull_uses_mode_not_first() -> void:
	var r := _tx()
	var key := "TX_TECH/M01/hand_1"
	runner.check(r.slots[key].grip_modes[0].mode == &"pull", "전제: 첫 방식 pull")
	for k in ["TX_TECH/S01/hand_1", "TX_TECH/S02/hand_1", "TX_TECH/K01/hand_1", "TX_TECH/U01/hand_1"]:
		r.slots[k].pos = FAR
	var s := _session(r)
	var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, &"LH", s.body.yaw)
	r.slots[key].pos = sh + Vector2(-0.35, 0.40)
	runner.check(s.runner.start(s, &"T_SIDEPULL", &"left", key, r.slots[key].pos) == &"", "사이드풀 시작")
	var out := _run(s)
	runner.check(out == "" and s.limbs[&"LH"].key == key and s.limbs[&"LH"].state == "Attached", "붙음 (%s %s)" % [out, s.limbs[&"LH"].key])
	var ci: ContactInfo = s.rules.contact_meta.get(&"LH")
	runner.check(ci != null and ci.mode == &"sidepull" and ci.axis == Vector2(-1, 0), "방식 sidepull·축 (%s)" % [[ci.mode, ci.axis] if ci else null])


# ---------- 8b: yaw형 기술(드롭니·아웃사이드 엣지) ----------

## 같은 쪽 손의 벽면 최대 도달 거리(04 §10.1: 엉덩이가 벽 쪽이면 늘어남).
func _far_reach(limb: StringName, yaw: float) -> float:
	var dz := PoseSolver.contact_dz_range() + Vector2.ONE * PoseSolver.joint_depth_offset(limb, yaw)
	return PoseSolver.planar_range(limb, dz.x, dz.y).y


func _run_ticks(s: ClimbSession, n: int) -> String:
	for i in n:
		var r := s.step()
		if r.begins_with("fall"):
			return r
	return ""


## TA01: 두 손·두 발, 왼발 발판 pivot true·오른발 false → 왼쪽만 가능.
func test_drop_knee_left_only() -> void:
	var r := _r01()
	r.slots["R01/F02/foot_1"].pivot_allowed = false
	var s := _session(r)
	var j := TechniqueJudge.judge(ClimbSnapshot.from_session(s), &"T_DROP_KNEE")
	runner.check(j[&"left"].available, "왼쪽 가능: %s" % [j[&"left"]])
	runner.check(not j[&"right"].available and j[&"right"].reason == TechniqueJudge.PIVOT_NOT_ALLOWED, "오른쪽 PIVOT_NOT_ALLOWED: %s" % [j[&"right"]])
	runner.check(j[&"right"].text == "이 발판에서는 발을 돌릴 수 없어요", "문구")


func test_drop_knee_turns_hip() -> void:
	var s := _session(_r01())
	var reach0 := _far_reach(&"LH", 0.0)
	runner.check(s.runner.start(s, &"T_DROP_KNEE", &"left") == &"", "시작")
	var fell := _run_ticks(s, 90)
	runner.check(fell == "", "추락 없음 (%s)" % fell)
	runner.check(absf(s.body.yaw + 35.0) <= 1.0, "yaw → -35 (%.2f)" % s.body.yaw)
	runner.check(s.rules.contact_meta[&"LF"].edge == &"drop_knee", "LF edge drop_knee")
	runner.check(s.limbs[&"LF"].state == "Attached" and not s.runner.active.is_empty(), "발 유지·기술 유지")
	runner.check(_far_reach(&"LH", s.body.yaw) > reach0 + 0.003, "같은 쪽 LH 도달 증가 (%.4f → %.4f)" % [reach0, _far_reach(&"LH", s.body.yaw)])
	runner.check(PoseSolver.is_valid(s.body.pos, s.body.angle, s.attached(), s.body.yaw), "자세 유효")
	runner.check(s.rules.phase == ClimbRules.Phase.STABLE, "안정 (%s)" % s.rules.phase)


func test_outside_edge_sets_yaw() -> void:
	var s := _session(_r01())
	var key := "R01/F04/foot_1"
	var c := TechniqueJudge.check_hold(ClimbSnapshot.from_session(s), &"T_OUTSIDE_EDGE", &"right", key, s.route.slot_pos(key))
	runner.check(c.ok, "전제: 후보 가능 %s" % [c])
	runner.check(s.runner.start(s, &"T_OUTSIDE_EDGE", &"right", key, s.route.slot_pos(key)) == &"", "시작")
	var out := _run_ticks(s, 150)
	runner.check(out == "", "추락 없음 (%s)" % out)
	runner.check(s.limbs[&"RF"].state == "Attached" and s.limbs[&"RF"].key == key, "RF 붙음")
	runner.check(absf(s.body.yaw - 30.0) <= 1.0, "yaw → +30 (%.2f)" % s.body.yaw)
	runner.check(s.rules.contact_meta[&"RF"].edge == &"outside", "RF edge outside")
	# pivot 불가 발판은 PIVOT_NOT_ALLOWED
	var r := _r01()
	r.slots[key].pivot_allowed = false
	var s2 := _session(r)
	runner.check(s2.runner.start(s2, &"T_OUTSIDE_EDGE", &"right", key, r.slot_pos(key)) == TechniqueJudge.PIVOT_NOT_ALLOWED, "pivot 불가 → PIVOT_NOT_ALLOWED")


## Review Focus 3: 드롭니 중 다른 패드를 써도 유지, 그 발 패드를 누르면 취소·복귀.
func test_drop_knee_survives_other_pad_moves() -> void:
	var s := _session(_r01())
	runner.check(s.runner.start(s, &"T_DROP_KNEE", &"left") == &"", "시작")
	_run_ticks(s, 90)
	runner.check(absf(s.body.yaw + 35.0) <= 1.0, "전제: yaw -35")
	# LH를 떼서 다른 홀드(H03)로 옮겨 잡는다
	s.apply_input([{"type": "arm", "limb": &"LH"}, {"type": "detach", "limb": &"LH"}])
	var target := s.route.slot_pos("R01/H03/hand_1")
	for i in 120:
		var d: Vector2 = target - s.limbs[&"LH"].req
		s.apply_input([{"type": "move", "limb": &"LH", "delta": d.limit_length(0.02)}])
		var r := s.step()
		runner.check(not r.begins_with("fall"), "추락 없음 (%d %s)" % [i, r])
		runner.check(PoseSolver.is_valid(s.body.pos, s.body.angle, s.attached(), s.body.yaw), "is_valid 유지 (%d)" % i)
		if r.begins_with("fall"):
			return
		if d.length() < 0.02:
			break
	# 체중 이동이 필요한 거리라 끄는 채로 기다린다(의도 비용으로 몸이 따라 움직임). 그동안에도 yaw·유효성 유지
	for i in 90:
		var r := s.step()
		runner.check(not r.begins_with("fall") and PoseSolver.is_valid(s.body.pos, s.body.angle, s.attached(), s.body.yaw), "기다리는 중 유효 (%d %s)" % [i, r])
		if r.begins_with("fall"):
			return
	s.apply_input([{"type": "release", "limb": &"LH"}])
	_run_ticks(s, 30)
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == "R01/H03/hand_1", "LH가 H03에 붙음 (%s %s)" % [s.limbs[&"LH"].state, s.limbs[&"LH"].key])
	runner.check(not s.runner.active.is_empty(), "드롭니 유지")
	runner.check(absf(s.body.yaw + 35.0) <= 1.5, "yaw 유지 (%.2f)" % s.body.yaw)
	s.apply_input([{"type": "arm", "limb": &"LF"}])
	s.step()
	runner.check(_last_event(s).get("type") == TechniqueRunner.CANCELLED, "cancelled: %s" % [_last_event(s)])
	runner.check(s.runner.active.is_empty() and is_nan(s.rules.yaw_target), "active 비움·yaw_target NAN")
	s.apply_input([{"type": "disarm", "limb": &"LF"}])
	_run_ticks(s, 60)
	runner.check(absf(s.body.yaw) < 0.5, "0으로 복귀 (%.2f)" % s.body.yaw)


## evaluate가 yaw > 10°에서 INFEASIBLE을 돌려주는 시험용 규칙(힘 균형 게이트 확인용).
class GatedRules extends ClimbRules:
	var barn_over := false

	func evaluate(pelvis: Vector2, angle_deg: float, attached: Dictionary, endpoints: Dictionary, platform: bool, feet: Array = feet_eligible, yaw_deg: float = 0.0) -> Dictionary:
		var r := super.evaluate(pelvis, angle_deg, attached, endpoints, platform, feet, yaw_deg)
		if absf(yaw_deg) > 10.0:
			if barn_over:
				r.barn = {"exceeded": true, "tau": 1.0, "capacity": 0.0}
			else:
				r.status = SupportSolver.Status.INFEASIBLE
		return r


## 힘 균형 게이트(Task 5 리뷰): yaw 기술 중 다음 yaw가 FEASIBLE이 아니거나 barn door 초과면 yaw 진행을 멈춘다.
## 복귀(|yaw| 감소)는 막지 않고, 가드가 꺼져 있으면 기존 동작.
func test_yaw_guard_stops_when_support_infeasible() -> void:
	var s := _session(_r01())
	for barn in [false, true]:
		var rules := GatedRules.new()
		rules.barn_over = barn
		var body := BodyState.new(s.body.pos, s.body.angle)
		var att := s.attached()
		var eps := {}
		rules.yaw_target = 35.0
		rules.yaw_guard = true
		for i in 120:
			rules._step_yaw(body, att, eps, false)
		runner.check(body.yaw > 5.0 and body.yaw <= 10.0 + 1.0, "barn=%s 가드가 10° 근처에서 멈춤 (%.2f)" % [barn, body.yaw])
		runner.check(body.yaw_vel == 0.0, "yaw 속도 0")
		rules.yaw_target = NAN
		for i in 120:
			rules._step_yaw(body, att, eps, false)
		runner.check(absf(body.yaw) < 0.001, "복귀는 막지 않음 (%.3f)" % body.yaw)
		rules.yaw_guard = false
		rules.yaw_target = 35.0
		for i in 120:
			rules._step_yaw(body, att, eps, false)
		runner.check(absf(body.yaw - 35.0) < 0.001, "가드 꺼지면 목표까지 (%.3f)" % body.yaw)


# ---------- 플래그 3종 (8c) ----------

const BARN_LINE := {&"LH": Vector2(-0.40, 1.75), &"LF": Vector2(-0.38, 0.35)}
const BARN_FREE := {&"RF": Vector2(0.20, 0.30), &"RH": Vector2(0.20, 1.60)}


## Task 6 barn door 자세(test_barn_door.gd): 세로선 LH+LF, 골반 x=-0.30, RH·RF 자유.
func _barn_session() -> ClimbSession:
	var s := ClimbSession.new(_r01())
	for limb in BARN_LINE:
		var l: Dictionary = s.limbs[limb]
		l.grab = BARN_LINE[limb]
		l.pos = BARN_LINE[limb]
		l.contact.point = BARN_LINE[limb]
	for limb in BARN_FREE:
		var l: Dictionary = s.limbs[limb]
		l.state = "Free"
		l.contact = null
		l.pos = BARN_FREE[limb]
		l.req = BARN_FREE[limb]
	s.body.pos = Vector2(-0.30, 1.0)
	s.body.angle = 0.0
	s.rules.contact_meta = s._contact_meta()
	s.rules.reset(s.body, s.attached(), BARN_FREE, false)
	return s


func test_flag_needed_and_fixes_barn_door() -> void:
	var s := _barn_session()
	runner.check(s.rules.imbalance_cause == &"BARN_DOOR", "전제: barn door 자세 (%s)" % s.rules.imbalance_cause)
	var snap := ClimbSnapshot.from_session(s)
	var j := TechniqueJudge.judge(snap, TechniqueJudge.T_FLAG_INSIDE)
	runner.check(j[&"right"].available, "인사이드 플래그 right 가능: %s" % [j[&"right"]])
	runner.check(s.runner.start(s, &"T_FLAG_INSIDE", &"right") == &"", "시작")
	var r := _run(s)
	runner.check(r == "", "실행 완료 (%s)" % r)
	var rf: Dictionary = s.limbs[&"RF"]
	runner.check(rf.state == "Flag", "RF state Flag: %s" % rf.state)
	runner.check(not s.rules.last.barn.exceeded, "barn door 해소: %s" % [s.rules.last.barn])
	var types: Array = s.technique_log.map(func(e): return e.type)
	runner.check(types == [TechniqueRunner.STARTED, TechniqueRunner.SUCCEEDED], "이벤트: %s" % [types])


func test_flag_unavailable_when_no_gain() -> void:
	var s := _session(_r01())
	var snap := ClimbSnapshot.from_session(s)
	for id in [&"T_FLAG", &"T_FLAG_INSIDE", &"T_FLAG_OUTSIDE"]:
		var j := TechniqueJudge.judge(snap, id)
		for side in [&"left", &"right"]:
			runner.check(not j[side].available, "%s %s 불가" % [id, side])
			runner.check(j[side].text == TechniqueJudge.FLAG_NO_GAIN_TEXT, "%s %s 이유 문구: %s" % [id, side, j[side].text])


## R01 시작에서 RH·RF를 떼고 골반을 LF 쪽으로 치우친 자세: 같은 쪽 플래그(오른발 바깥)가 이득.
func _same_side_session() -> ClimbSession:
	var s := ClimbSession.new(_r01())
	var fr := {}
	for limb in [&"RH", &"RF"]:
		var l: Dictionary = s.limbs[limb]
		l.state = "Free"
		l.contact = null
		l.pos = Vector2(0.3, 0.1) if limb == &"RF" else Vector2(0.4, 1.6)
		l.req = l.pos
		fr[limb] = l.pos
	s.body.pos = Vector2(-0.45, 0.8)
	s.rules.contact_meta = s._contact_meta()
	s.rules.reset(s.body, s.attached(), fr, false)
	return s


func test_flag_variants_positions() -> void:
	# 같은 쪽: 지지발(LF) 바깥(오른쪽)으로, 인사이드·아웃사이드 위치는 이 자세에서 불가
	var s1 := _same_side_session()
	var snap1 := ClimbSnapshot.from_session(s1)
	var sup_x: float = s1.limbs[&"LF"].grab.x
	var p1 := TechniqueJudge.flag_plan(snap1, &"T_FLAG", &"RF")
	runner.check(not p1.is_empty() and p1.point.x > sup_x and p1.point.y < s1.body.pos.y, "같은 쪽은 지지발 바깥·아래: %s" % [p1])
	runner.check(s1.runner.start(s1, &"T_FLAG", &"right") == &"" and _run(s1) == "", "같은 쪽 실행")
	runner.check(s1.limbs[&"RF"].state == "Flag" and s1.limbs[&"RF"].flag_depth == 0.0, "같은 쪽 Flag, 깊이 0")
	# 교차 변형: 지지발(LF) 너머. 같은 쪽 영역 판정과 구분된다
	var s2 := _barn_session()
	var snap2 := ClimbSnapshot.from_session(s2)
	var sup2: float = BARN_LINE[&"LF"].x
	for id in [&"T_FLAG_INSIDE", &"T_FLAG_OUTSIDE"]:
		var plan := TechniqueJudge.flag_plan(snap2, id, &"RF")
		runner.check(not plan.is_empty() and plan.point.x < sup2, "%s는 지지발 너머로 교차: %s" % [id, plan])
	runner.check(TechniqueJudge.flag_plan(snap2, &"T_FLAG", &"RF").is_empty(), "barn door 자세에서 같은 쪽은 이득 없음")
	var d_in := TechniqueJudge.flag_depth(&"T_FLAG_INSIDE")
	var d_same := TechniqueJudge.flag_depth(&"T_FLAG")
	var d_out := TechniqueJudge.flag_depth(&"T_FLAG_OUTSIDE")
	runner.check(d_in < d_same and d_same < d_out, "깊이 안 < 같은 쪽 < 뒤")
	for id in [&"T_FLAG_INSIDE", &"T_FLAG_OUTSIDE"]:
		var s3 := _barn_session()
		runner.check(s3.runner.start(s3, id, &"right") == &"" and _run(s3) == "", "%s 실행" % id)
		runner.check(is_equal_approx(s3.limbs[&"RF"].flag_depth, TechniqueJudge.flag_depth(id)), "%s limb.flag_depth 기록" % id)
