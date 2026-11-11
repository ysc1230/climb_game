extends RefCounted
## 떨어지기 전 경고 3단계(DangerFeedback)·떼기 예고(ClimbSession.release_risk)·초급 버틸 시간·되돌리기 자세·난이도 저장.
## 2026-11-09 사용자: "느려지면 조작도 느려져 도움이 안 된다, 경고라는 느낌이 없다".

var runner
const DT := 1.0 / 60.0
const ROUTE := "res://tests/fixtures/G_V0_01.json"
const SAVE := "user://test_level_save.json"
const PLAY_3D := preload("res://scenes/play_3d.gd")


func _state(danger: bool, extra := {}) -> Dictionary:
	var s := {"danger": danger, "kind": &"FORCE", "frac": 0.5, "ticks_left": 9, "falling": false,
		"states": {&"LH": "Attached", &"RH": "Attached"}, "keys": {&"LH": "A", &"RH": "B"}, "risks": {}, "hands_on": 2}
	s.merge(extra, true)
	return s


func _session(slots: Dictionary) -> ClimbSession:
	var s := ClimbSession.new(RouteDef.load_json(ROUTE))
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTE))
	var pose: Dictionary = d.start_pose.duplicate(true)
	var keep := {}
	for limb in slots:
		keep[limb] = pose.slots[limb]
	pose.slots = keep
	s.reset_to(pose)
	return s


func test_enter_hitstop_heartbeat_recover() -> void:
	var f := DangerFeedback.new()
	f.update(DT, _state(false))
	runner.check(f.events.is_empty() and not f.danger, "안정: 사건 없음")
	f.update(DT, _state(true))
	runner.check(f.events.has(&"enter") and f.hitstop_left > 0.1, "위험 진입: enter + 멈칫")
	var beats := 0
	var beat2 := 0
	for i in 120:
		f.update(DT, _state(true))
		beats += f.events.count(&"beat")
		beat2 += f.events.count(&"beat2")
	runner.check(beats >= 3 and beats <= 4, "2초 동안 심장 박동 3~4번: %d" % beats)
	runner.check(beat2 >= beats, "박동마다 두 번째 두근: %d" % beat2)
	runner.check(f.hitstop_left == 0.0, "멈칫은 잠깐")
	f.update(DT, _state(false))
	runner.check(f.events.has(&"recover") and f.recover_left > 0.0 and not f.danger, "되찾으면 회복 사건")


func test_fall_is_not_recover() -> void:
	var f := DangerFeedback.new()
	f.update(DT, _state(true, {"kind": &"BARN_DOOR"}))
	f.update(DT, _state(true, {"falling": true}))
	runner.check(f.events.has(&"fall") and not f.events.has(&"recover"), "떨어지면 회복이 아니라 fall")
	runner.check(f.kind == &"BARN_DOOR", "떨어진 뒤에도 원인 종류를 기억")


func test_caution_only_when_new_risk() -> void:
	var f := DangerFeedback.new()
	f.update(DT, _state(false, {"risks": {&"LH": &""}}))
	runner.check(f.caution.is_empty() and f.events.is_empty(), "떼도 괜찮으면 주의 없음")
	f.update(DT, _state(false, {"risks": {&"LH": &"GRACE"}}))
	runner.check(f.caution.has(&"LH") and f.events.has(&"caution"), "떼면 위험한 손을 누르면 주의")
	f.update(DT, _state(false, {"risks": {&"LH": &"GRACE"}}))
	runner.check(not f.events.has(&"caution"), "주의 소리는 한 번만")
	f.update(DT, _state(false))
	runner.check(f.caution.is_empty(), "손을 놓으면 주의 끝")


func test_release_tracking_and_cause() -> void:
	var f := DangerFeedback.new()
	f.update(DT, _state(false))
	f.update(DT, _state(true, {"states": {&"LH": "Dragging", &"RH": "Attached"}, "hands_on": 1}))
	runner.check(f.recent_limb() == &"LH" and not f.last_release.slip and f.last_release.key == "A", "끌기 시작한 손 기억")
	runner.check(f.fall_cause("BALANCE_LOST").begins_with("왼손을 뗀 뒤 몸이"), "원인: %s" % f.fall_cause("BALANCE_LOST"))
	runner.check(f.fall_cause("NO_SUPPORT").contains("어깨보다 낮아"), "손이 붙어 있는데 지지 없음 = 손이 낮음")
	var h := DangerFeedback.new()
	h.update(DT, _state(false, {"states": {&"LH": "Attached", &"RH": "Attached", &"LF": "Attached"}, "keys": {&"LH": "A", &"RH": "B", &"LF": "F"}}))
	h.update(DT, _state(false, {"states": {&"LH": "Dragging", &"RH": "Attached", &"LF": "Attached"}, "keys": {&"LH": "A", &"RH": "B", &"LF": "F"}}))
	h.update(DT, _state(true, {"kind": &"GRACE", "states": {&"LH": "Dragging", &"RH": "Attached", &"LF": "Dragging"}, "keys": {&"LH": "A", &"RH": "B", &"LF": "F"}}))
	var free := {&"LH": true, &"LF": true}
	runner.check(h.rescue_release(free).get("limb") == &"LH", "버틸 손이 없으면 발보다 손을 다시 잡게 안내")
	runner.check(h.fall_cause("NO_SUPPORT").begins_with("왼손을 뗀 뒤"), "손이 없어 떨어지면 원인은 마지막에 뗀 손: %s" % h.fall_cause("NO_SUPPORT"))
	var g := DangerFeedback.new()
	g.update(DT, _state(false))
	g.update(DT, _state(false, {"states": {&"LH": "Attached", &"RH": "Free"}}))
	runner.check(g.last_release.slip and g.fall_cause("NO_SUPPORT").contains("미끄러졌어요"), "바로 Free = 미끄러짐")
	for i in 200:
		g.update(DT, _state(false, {"states": {&"LH": "Attached", &"RH": "Free"}}))
	runner.check(g.recent_limb() == &"", "오래전 일은 원인에 안 씀")


func test_release_risk_predicts_no_support() -> void:
	var s := _session({&"LH": 1, &"LF": 1})
	runner.check(s.release_risk(&"LH") == &"GRACE", "손 하나·발 하나: 손을 떼면 버틸 손 없음")
	runner.check(s.release_risk(&"RH") == &"", "붙지 않은 손은 위험 없음")
	var full := _session({&"LH": 1, &"RH": 1, &"LF": 1, &"RF": 1})
	runner.check(full.release_risk(&"LF") == &"", "네 손발 시작 자세에서 발 하나 떼기는 안전")


func _ticks_to_fall(s: ClimbSession) -> int:
	for i in 400:
		if s.step().begins_with("fall:"):
			return i + 1
	return -1


func test_beginner_budget_ten_times() -> void:
	for lv in ["beginner", "intermediate", "advanced"]:
		var s := _session({&"LF": 1})
		ClimbRules.apply_level(s.rules, lv)
		var n := _ticks_to_fall(s)
		runner.check(n == (9 if lv == "advanced" else 90), "%s: 손이 없으면 %d틱에 떨어짐(%d)" % [lv, 9 if lv == "advanced" else 90, n])
		runner.check(s.rules.imbalance_budget == (180 if lv == "beginner" else 18), "%s 균형 잃음 예산" % lv)


func test_current_pose_round_trip() -> void:
	var s := _session({&"LH": 1, &"RH": 1, &"LF": 1, &"RF": 1})
	for i in 30:
		s.step()
	var pose := s.current_pose()
	var before := s.attached().keys()
	s.reset_to(pose)
	runner.check(s.attached().keys() == before and s.body.pos.is_equal_approx(Vector2(pose.pelvis[0], pose.pelvis[1])), "되돌리기 자세 그대로 복원")


func test_level_saved_and_beginner_assist() -> void:
	var p := Progress.new()
	runner.check(p.level == "", "처음엔 난이도 안 고름")
	var flow := PlayFlow.new(ContentIndex.new(), p, SAVE)
	flow.set_level("beginner")
	runner.check(flow.beginner_assist(), "초급: 도움 켬")
	runner.check(SaveStore.load(SAVE).level == "beginner", "난이도 저장·불러오기")
	flow.set_level("intermediate")
	runner.check(not flow.beginner_assist(), "중급: 도움 끔")
	flow.set_level("expert")
	runner.check(p.level == "intermediate", "모르는 값 무시")
	runner.check(Progress.from_dict({"level": "zzz"}).level == "", "저장 파일의 모르는 값은 안 고름으로")
	for f in [SAVE, SAVE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_scared_face_in_danger() -> void:
	runner.check(PLAY_3D.expression_for(false, false, 90.0, true, true) == "scared", "떨어지기 직전 겁먹은 표정")
	runner.check(PLAY_3D.expression_for(false, true, 90.0, true, true) == "happy", "정상에서는 기쁨 우선")


## 바닥 발판(플랫폼)에 두 발로 서 있어도 손이 하나도 없으면 떨어진다(2026-11-10 사용자 보고).
func test_platform_needs_a_hand() -> void:
	var s := _session({&"LH": 1, &"RH": 1, &"LF": 1, &"RF": 1})
	for i in 20:
		s.step()
	runner.check(s.on_platform(s.attached()), "시작 자세는 바닥 발판")
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	for i in 30:
		runner.check(not s.step().begins_with("fall:"), "한 손 + 바닥 발판은 버팀")
	s.apply_input([{"type": "detach", "limb": &"RH"}])
	runner.check(_ticks_to_fall(s) == s.rules.grace_budget, "두 손을 모두 놓으면 바닥 발판 위에서도 떨어짐")
