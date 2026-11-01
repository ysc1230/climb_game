extends RefCounted
## 패드 잡기 방향 자동 선택(docs/28 §4.3, MG09·MG10). 시험 루트 TX_GRIP.

var runner

const S01 := "TX_GRIP/S01/hand_1"  # sidepull만
const M01 := "TX_GRIP/M01/hand_1"  # pull, sidepull
const M02 := "TX_GRIP/M02/hand_1"  # sidepull, pull (세로 영역 반폭 0.12)
const U01 := "TX_GRIP/U01/hand_1"  # undercling, pull (어깨 아래)
const LF0 := Vector2(-0.30, 0.10)
const RF0 := Vector2(0.30, 0.10)
const RF_HIGH := Vector2(0.30, 0.55)
const LH0 := Vector2(-0.45, 1.80)
const RH0 := Vector2(0.45, 1.80)


func _route() -> RouteDef:
	return RouteDef.load_json("res://data/routes/TX_GRIP.json")


## 붙은 손발의 접점 정보(손은 첫 방식, 발은 inside). 위치로 슬롯을 찾는다.
func _meta(r: RouteDef, att: Dictionary) -> Dictionary:
	var meta := {}
	for limb in att:
		for key in r.slots:
			if (r.slots[key].pos as Vector2).distance_to(att[limb]) < 0.01:
				meta[limb] = GripCheck.contact_for(key, r.slots, limb, att[limb])
	return meta


func _pick(r: RouteDef, key: String, limb: StringName, point: Vector2, pelvis: Vector2, att: Dictionary, forbid := false) -> StringName:
	return GripCheck.contact_for_pose(key, r.slots, limb, point, pelvis, 0.0, 0.0, att, _meta(r, att), {}, forbid).mode


## 방식 하나의 {ok(힘 해 FEASIBLE·barn door 아님), cost(flag_cost)}. 테스트 자세가 의도대로인지 확인용.
func _mode_cost(r: RouteDef, key: String, limb: StringName, point: Vector2, pelvis: Vector2, att: Dictionary, index: int) -> Dictionary:
	var slot: Dictionary = r.slots[key]
	var gm: Dictionary = slot.grip_modes[index]
	var with_new := att.duplicate()
	with_new[limb] = point
	var m := _meta(r, att)
	var ci := ContactInfo.make(key, point, HoldArea.project_hand(slot, point).quality, gm.mode, &"")
	ci.axis = gm.axis
	ci.half_angle = gm.half_angle
	m[limb] = ci
	var feet := PoseSolver.supporting_feet(pelvis, 0.0, with_new, [], 0.0)
	var res := ClimbRules.evaluate_pose(pelvis, 0.0, 0.0, with_new, {}, m, feet, feet)
	return {"ok": res.status == SupportSolver.Status.FEASIBLE and not ClimbRules.barn_exceeded(res), "cost": ClimbRules.flag_cost(res)}


## limb을 key까지 끌어 후보가 되면 놓는다(test_session과 같은 방식). 붙으면 true.
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


func test_route_loads() -> void:
	var r := _route()
	runner.check(r.errors.is_empty(), "TX_GRIP 오류 없음 %s" % [r.errors])


## MG09: 사이드풀만 있는 홀드를 패드로 잡으면 sidepull, 기술 로그에 pad_grip.
func test_sidepull_only_hold_by_pad() -> void:
	var s := ClimbSession.new(_route())
	for i in 30:
		s.step()
	var ok := _drag_to(s, &"LH", S01)
	runner.check(ok, "LH가 S01에 붙음")
	if not ok:
		return
	runner.check(s.limbs[&"LH"].contact.mode == &"sidepull", "접점 mode sidepull (%s)" % s.limbs[&"LH"].contact.mode)
	var ev: Dictionary = s.technique_log.back() if not s.technique_log.is_empty() else {}
	runner.check(ev.get("type", "") == "pad_grip", "마지막 로그 pad_grip (%s)" % [ev])
	runner.check(ev.get("limb", &"") == &"LH" and ev.get("key", "") == S01 and ev.get("mode", &"") == &"sidepull", "pad_grip 로그 내용 limb·key·mode (%s)" % [ev])
	runner.check(ev.get("tick", -1) == s.tick_count, "pad_grip 로그에 tick")


## 발을 패드로 디디면 pad_grip을 남기지 않는다(손 방식 선택만 기록).
func test_foot_grab_no_pad_grip_log() -> void:
	var s := ClimbSession.new(_route())
	for i in 30:
		s.step()
	var ok := _drag_to(s, &"RF", "TX_GRIP/F03/foot_1")
	runner.check(ok, "RF가 F03에 붙음")
	runner.check(s.technique_log.filter(func(e): return e.type == "pad_grip").is_empty(), "발 잡기는 pad_grip 없음")


## MG10: pull·sidepull 홀드 바로 아래 자세 → pull. 목록 순서와 무관하게 비용이 정한다.
func test_pull_preferred_below_hold() -> void:
	var r := _route()
	var att := {&"RF": RF0, &"RH": RH0}
	var pelvis := Vector2(-0.30, 0.90)
	var p := r.slot_pos(M01)
	var pull := _mode_cost(r, M01, &"LH", p, pelvis, att, 0)
	var side := _mode_cost(r, M01, &"LH", p, pelvis, att, 1)
	runner.check(pull.ok and side.ok and pull.cost < side.cost - GripCheck.GRIP_TIE_MARGIN, "M01 아래 자세: pull 비용이 확실히 작음 (%.3f, %.3f)" % [pull.cost, side.cost])
	runner.check(_pick(r, M01, &"LH", p, pelvis, att) == &"pull", "M01 → pull")
	# 순서가 [sidepull, pull]인 M02도 아래 자세면 pull
	var pelvis2 := Vector2(-0.40, 0.90)
	runner.check(_pick(r, M02, &"LH", r.slot_pos(M02), pelvis2, att) == &"pull", "M02(sidepull 먼저)도 pull")


## 몸이 홀드 반대쪽이면 사이드풀이 더 좋다(같은 홀드, 다른 자세).
func test_sidepull_preferred_body_opposite() -> void:
	var r := _route()
	var att := {&"LF": LF0, &"RH": RH0}
	var pelvis := Vector2(-0.20, 0.744)
	var p := r.slot_pos(M02)
	var side := _mode_cost(r, M02, &"LH", p, pelvis, att, 0)
	var pull := _mode_cost(r, M02, &"LH", p, pelvis, att, 1)
	runner.check(side.cost < pull.cost - GripCheck.GRIP_TIE_MARGIN, "사이드풀 비용이 확실히 작음 (%.3f, %.3f)" % [side.cost, pull.cost])
	runner.check(_pick(r, M02, &"LH", p, pelvis, att) == &"sidepull", "M02 → sidepull")


## 비용 차 < 0.02면 grip_modes[0].
func test_grip_tie_prefers_first_mode() -> void:
	var r := _route()
	var att := {&"LF": LF0, &"RF": RF0, &"RH": RH0}
	var pelvis := Vector2(-0.30, 0.90)
	var p := r.slot_pos(M01)
	var pull := _mode_cost(r, M01, &"LH", p, pelvis, att, 0)
	var side := _mode_cost(r, M01, &"LH", p, pelvis, att, 1)
	runner.check(side.cost < pull.cost and pull.cost - side.cost < GripCheck.GRIP_TIE_MARGIN, "뒤 방식이 조금(< 0.02) 더 쌈 (%.3f, %.3f)" % [pull.cost, side.cost])
	runner.check(_pick(r, M01, &"LH", p, pelvis, att) == &"pull", "차이 < 0.02 → 앞 방식 pull")


## 어느 방식도 힘 균형이 안 풀리면 grip_modes[0](비용이 더 작은 방식이 있어도).
func test_no_mode_solves_falls_back_first() -> void:
	var r := _route()
	var att := {}
	var pelvis := Vector2(0.30, 0.90)
	var p := r.slot_pos(M02)
	var side := _mode_cost(r, M02, &"LH", p, pelvis, att, 0)
	var pull := _mode_cost(r, M02, &"LH", p, pelvis, att, 1)
	runner.check(not side.ok and not pull.ok, "두 방식 모두 불성립")
	runner.check(pull.cost < side.cost, "pull의 불균형 비용이 더 작음 (%.3f, %.3f)" % [side.cost, pull.cost])
	runner.check(_pick(r, M02, &"LH", p, pelvis, att) == &"sidepull", "성립 없음 → grip_modes[0] sidepull")


## 끝(q < 0.5)을 잡으면 sidepull·gaston 후보 제외.
func test_low_quality_excludes_sidepull() -> void:
	var r := _route()
	var att := {&"LF": LF0, &"RH": RH0}
	var pelvis := Vector2(-0.20, 0.744)
	var end := Vector2(-0.80, 1.72)  # 세로 영역 끝: q = 0
	runner.check(HoldArea.project_hand(r.slots[M02], end).quality < 0.5, "끝 q < 0.5")
	var side := _mode_cost(r, M02, &"LH", end, pelvis, att, 0)
	var pull := _mode_cost(r, M02, &"LH", end, pelvis, att, 1)
	runner.check(side.ok and side.cost < pull.cost - GripCheck.GRIP_TIE_MARGIN, "힘만 보면 sidepull이 나음 (%.3f, %.3f)" % [side.cost, pull.cost])
	runner.check(_pick(r, M02, &"LH", end, pelvis, att) == &"pull", "q < 0.5 → sidepull 제외, pull")
	var sh := PoseSolver.joint_position(pelvis, 0.0, &"LH", 0.0)
	var gaston_hold := Vector2(-0.60, sh.y)
	runner.check(TechniqueJudge.grip_mode_ok(&"gaston", &"LH", gaston_hold, 0.8, pelvis, 0.0, 0.0, att, []), "개스턴: q 0.8, 같은 쪽 어깨 높이 → 성립")
	runner.check(not TechniqueJudge.grip_mode_ok(&"gaston", &"LH", gaston_hold, 0.4, pelvis, 0.0, 0.0, att, []), "개스턴: q 0.4 → 불가")
	runner.check(not TechniqueJudge.grip_mode_ok(&"sidepull", &"LH", gaston_hold, 0.4, pelvis, 0.0, 0.0, att, []), "사이드풀: q 0.4 → 불가")


## 개스턴 자세 조건(27 §10): 그 손 쪽, 어깨 높이 ±0.30.
func test_gaston_shoulder_band() -> void:
	var pelvis := Vector2(0.0, 0.744)
	var sh := PoseSolver.joint_position(pelvis, 0.0, &"LH", 0.0)
	runner.check(TechniqueJudge.grip_mode_ok(&"gaston", &"LH", Vector2(-0.5, sh.y + 0.29), 1.0, pelvis, 0.0, 0.0, {}, []), "어깨 +0.29 성립")
	runner.check(not TechniqueJudge.grip_mode_ok(&"gaston", &"LH", Vector2(-0.5, sh.y + 0.31), 1.0, pelvis, 0.0, 0.0, {}, []), "어깨 +0.31 불가")
	runner.check(not TechniqueJudge.grip_mode_ok(&"gaston", &"LH", Vector2(0.3, sh.y), 1.0, pelvis, 0.0, 0.0, {}, []), "반대쪽 홀드 불가")


## 언더클링(27 §10): 어깨 아래이고 하중 받는 발이 높을 때만 후보.
func test_undercling_needs_high_loaded_foot() -> void:
	var r := _route()
	var pelvis := Vector2(0.0, 0.744)
	var p := r.slot_pos(U01)
	var low := {&"LF": LF0, &"RF": RF0, &"LH": LH0}
	var high := {&"LF": LF0, &"RF": RF_HIGH, &"LH": LH0}
	runner.check(_pick(r, U01, &"RH", p, pelvis, low) == &"pull", "발이 낮으면 언더클링 제외 → pull")
	runner.check(_pick(r, U01, &"RH", p, pelvis, high) == &"undercling", "높은 하중 발 → undercling")
	runner.check(not TechniqueJudge.grip_mode_ok(&"undercling", &"RH", p, 1.0, pelvis, 0.0, 0.0, high, []), "하중 발 없음 → 불가")
	runner.check(not TechniqueJudge.grip_mode_ok(&"undercling", &"RH", Vector2(0.4, 1.40), 1.0, pelvis, 0.0, 0.0, high, [&"RF"]), "어깨 위 홀드 → 불가")


## forbid_auto(검증기 전용)면 항상 grip_modes[0].
func test_forbid_auto_uses_first() -> void:
	var r := _route()
	var att := {&"RF": RF0, &"RH": RH0}
	var pelvis := Vector2(-0.40, 0.90)
	var p := r.slot_pos(M02)
	runner.check(_pick(r, M02, &"LH", p, pelvis, att) == &"pull", "자동이면 pull")
	runner.check(_pick(r, M02, &"LH", p, pelvis, att, true) == &"sidepull", "forbid_auto → grip_modes[0] sidepull")


## 기존 기술 이벤트는 기존 키를 유지한다(_log_event 확장).
func test_log_event_keeps_extra_keys() -> void:
	var s := ClimbSession.new(_route())
	s._log_event({"type": "pad_grip", "limb": &"LH", "key": S01, "mode": &"sidepull"})
	var ev: Dictionary = s.technique_log.back()
	runner.check(ev.has("tick") and ev.mode == &"sidepull" and ev.limb == &"LH" and ev.key == S01, "자유 키 이벤트 저장 (%s)" % [ev])
	s._log_event({"type": TechniqueRunner.SUCCEEDED, "id": &"T_DROP_KNEE", "side": &"left", "key": "", "quality": 1.0, "reason": &""})
	var e2: Dictionary = s.technique_log.back()
	for k in ["tick", "type", "id", "side", "key", "quality", "reason"]:
		runner.check(e2.has(k), "기술 이벤트 키 %s 유지" % k)
