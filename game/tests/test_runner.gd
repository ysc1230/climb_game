extends RefCounted
## 기술 실행기(docs/27 §6, §10, §11): 버튼 기술(아웃사이드 엣지·드롭니) 실행, 홀드 자동 선택 없음, 패드 취소, 이동 예산.
## 버튼에서 빠진 균형 발(플래그)은 패드 경로로 같은 균형 비용(flag_cost)을 쓰는지 본다(docs/28 §4.2).

var runner

func _r01() -> RouteDef:
	return RouteDef.load_json("res://data/routes/R01.json")


func _session(r: RouteDef, settle: int = 30) -> ClimbSession:
	var s := ClimbSession.new(r)
	for i in settle:
		s.step()
	return s


func _last_event(s: ClimbSession) -> Dictionary:
	return s.technique_log.back() if not s.technique_log.is_empty() else {}


## TA12: 홀드를 고르지 않은 hold_tap 기술은 시작하지 않고 아무것도 움직이지 않는다.
func test_no_auto_hold() -> void:
	var s := _session(_r01())
	var before := {}
	for limb in s.limbs:
		before[limb] = [s.limbs[limb].state, s.limbs[limb].key, s.limbs[limb].grab]
	var why := s.runner.start(s, &"T_OUTSIDE_EDGE", &"right", "")
	runner.check(why == TechniqueJudge.NO_HOLD, "NO_HOLD (%s)" % why)
	runner.check(s.runner.active.is_empty(), "실행 없음")
	for i in 30:
		s.step()
	for limb in s.limbs:
		runner.check([s.limbs[limb].state, s.limbs[limb].key, s.limbs[limb].grab] == before[limb], "%s 그대로" % limb)
	runner.check(s.technique_log.is_empty(), "이벤트 없음")


## TA09: 실행 중 그 발 패드를 누르면 취소되고 패드 조작으로 넘어간다. 다른 팔다리 패드는 취소하지 않는다.
func test_pad_touch_cancels() -> void:
	var s := _session(_r01())
	runner.check(s.runner.start(s, &"T_DROP_KNEE", &"left") == &"", "드롭니 시작")
	for i in 5:
		s.step()
	runner.check(not s.runner.active.is_empty() and not is_nan(s.rules.yaw_target), "전제: 실행 중")
	var busy: Dictionary = TechniqueJudge.judge(ClimbSnapshot.from_session(s), &"T_OUTSIDE_EDGE").right
	runner.check(busy.reason == TechniqueJudge.WRONG_PHASE, "실행 중 다른 기술은 WRONG_PHASE: %s" % [busy])
	s.apply_input([{"type": "arm", "limb": &"LF"}])
	runner.check(s.runner.active.is_empty(), "arm으로 active 비움")
	runner.check(is_nan(s.rules.yaw_target) and not s.rules.yaw_guard, "ψ 목표 해제")
	s.step()
	var ev := _last_event(s)
	runner.check(ev.get("type") == TechniqueRunner.CANCELLED and ev.get("id") == &"T_DROP_KNEE", "cancelled 이벤트: %s" % [ev])
	runner.check(s.limbs[&"LF"].state == "Armed", "패드 조작으로 전환(Armed)")

	var m := _session(_r01())
	var key := "R01/F04/foot_1"
	runner.check(m.runner.start(m, &"T_OUTSIDE_EDGE", &"right", key, m.route.slot_pos(key)) == &"", "아웃사이드 엣지 시작")
	for i in 4:
		m.step()
	runner.check(m.limbs[&"RF"].state == "Dragging", "전제: 발 이동 중")
	m.apply_input([{"type": "arm", "limb": &"LF"}])  # 다른 팔다리 패드는 취소하지 않음
	runner.check(not m.runner.active.is_empty(), "다른 발 패드는 유지")
	m.apply_input([{"type": "disarm", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
	runner.check(m.runner.active.is_empty(), "그 발 detach로 취소")
	m.step()
	runner.check(_last_event(m).get("type") == TechniqueRunner.CANCELLED, "cancelled 이벤트")


## 닿지 않는 채로 90틱이 지나면 failed(체중 이동이 필요 없던 목표면 JOINT_LIMIT), 발은 Free, ψ 목표 해제.
## 판단 뒤 상태가 달라진 경우를 만들려고 실행이 시작된 뒤 목표점을 닿지 않는 곳으로 바꾼다.
func test_move_budget_fails() -> void:
	var s := _session(_r01())
	var key := "R01/F04/foot_1"
	runner.check(s.runner.start(s, &"T_OUTSIDE_EDGE", &"right", key, s.route.slot_pos(key)) == &"", "시작")
	s.step()
	runner.check(_last_event(s).get("type") == TechniqueRunner.STARTED and not s.runner.active.needs_shift, "전제: started, 체중 이동 불필요")
	var far := Vector2(1.6, -0.5)  # 몸을 옮겨도 닿지 않는 지점. 발판째 옮겨 점유 검사(같은 자리)는 통과시킨다
	s.route.slots[key].pos = far
	s.runner.active.point = far
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
	runner.check(ev.get("type") == TechniqueRunner.FAILED and ev.get("reason") == TechniqueJudge.JOINT_LIMIT, "failed JOINT_LIMIT: %s" % [ev])
	runner.check(ticks <= TechniqueRunner.MOVE_BUDGET_TICKS + 1, "90틱 예산 (%d)" % ticks)
	runner.check(s.limbs[&"RF"].state == "Free", "RF Free (%s)" % s.limbs[&"RF"].state)
	runner.check(is_nan(s.rules.yaw_target) and not s.rules.yaw_guard, "ψ 목표 해제")


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


# ---------- 균형 발(패드 플래그, 25 MV06) ----------

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


## 플래그 버튼 대신 패드: barn door 자세에서 자유 발을 지지선 너머(균형 비용이 크게 주는 자리)로 끌면
## 놓기 전부터 "놓으면 균형 발" 예고(flag_ready)가 켜지고, 놓으면 Flag 상태로 남아 barn door가 풀린다.
func test_pad_balance_foot_fixes_barn_door() -> void:
	var s := _barn_session()
	runner.check(s.rules.imbalance_cause == &"BARN_DOOR", "전제: barn door 자세 (%s)" % s.rules.imbalance_cause)
	var spot := Vector2(-0.96, 0.5)  # 지지발(LF) 너머 교차 자리
	var l: Dictionary = s.limbs[&"RF"]
	l.state = "Dragging"
	l.pos = spot
	l.req = spot
	s.rules.contact_meta = s._contact_meta()
	s.rules.tick(s.body, s.attached(), {&"RH": s.limbs[&"RH"].pos, &"RF": spot}, false, true, {&"RF": spot}, {}, [&"RF"])
	runner.check(s.rules.flag_ready.has(&"RF"), "패드 예고 켜짐")
	s.apply_input([{"type": "release", "limb": &"RF"}])
	runner.check(l.state == "Flag" and l.flag == spot, "놓으면 Flag로 그 자리 유지 (%s %s)" % [l.state, l.flag])
	runner.check(s.messages.has("균형 발로 두었어요"), "안내 문구")
	s.step()
	runner.check(not s.rules.last.barn.exceeded, "barn door 해소: %s" % [s.rules.last.barn])


## 이득이 없는 자세(R01 시작)에서는 균형 발 예고가 켜지지 않는다.
func test_pad_balance_foot_needs_gain() -> void:
	var s := _session(_r01(), 0)
	var l: Dictionary = s.limbs[&"RF"]
	l.state = "Dragging"
	l.contact = null
	l.req = l.pos
	s.step()
	runner.check(not s.rules.flag_ready.has(&"RF"), "R01 시작: 패드 예고 꺼짐")
