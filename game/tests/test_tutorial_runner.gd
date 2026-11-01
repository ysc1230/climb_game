extends RefCounted
## 튜토리얼 실행기(docs/28 §6.1·§8.1, 16 T01~T03 목표 형식).

var runner

const H01 := "G_V0_01/H01/hand_1"
const H02 := "G_V0_01/H02/hand_1"
const H03 := "G_V0_01/H03/hand_1"
const F01 := "G_V0_01/F01/foot_1"
const F02 := "G_V0_01/F02/foot_1"
const DT := Tuning.DT


func _route(steps: Array) -> RouteDef:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/routes/general/G_V0_01.json"))
	d.tutorial_steps = steps
	return RouteDef.from_dict(d)


func _step(goal: Dictionary, extra := {}) -> Dictionary:
	var s := {"step_id": "S", "text_ko": "해 보세요.", "goal_event": goal, "help_ko": ["팔다리", "버튼"]}
	s.merge(extra)
	return s


func _settle(s: ClimbSession, n := 30) -> void:
	for i in n:
		s.step()


## limb을 key까지 끌어 놓는다(test_pad_events와 같은 방식). 틱마다 observe를 부르고 결과들을 돌려준다.
func _drag_observe(s: ClimbSession, t: TutorialRunner, limb: StringName, key: String) -> Array:
	var out := []
	var target := s.route.slot_pos(key)
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in 300:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(2.5 * DT)}])
		if s.limbs[limb].cand.get("key", "") == key:
			s.apply_input([{"type": "release", "limb": limb}])
			out.append(t.observe(s, s.step(), DT))
			return out
		out.append(t.observe(s, s.step(), DT))
	return out


func test_matches() -> void:
	var grab := {"type": "grab", "limb": &"LH", "key": H03, "quality": 0.8, "tick": 3, "seq": 9}
	runner.check(TutorialRunner.matches({"type": "grab", "limb": "LH", "slot": H03}, grab), "grab: slot은 key와, 문자열은 StringName과 비교")
	runner.check(TutorialRunner.matches({"type": "grab", "limb": "LH"}, grab), "조건 일부만 있어도 일치")
	runner.check(not TutorialRunner.matches({"type": "grab", "limb": "RH"}, grab), "다른 팔다리는 불일치")
	runner.check(not TutorialRunner.matches({"type": "grab", "slot": H01}, grab), "다른 슬롯은 불일치")
	runner.check(not TutorialRunner.matches({"type": "pad_grip", "limb": "LH"}, grab), "type이 다르면 불일치(이중 계산 없음)")
	runner.check(not TutorialRunner.matches({"type": "grab", "mode": "crimp"}, grab), "이벤트에 없는 키는 불일치")
	runner.check(TutorialRunner.matches({"type": "move", "label": "HighStep"}, {"type": "move", "label": MoveClassifier.HIGH_STEP}), "move 라벨")
	runner.check(not TutorialRunner.matches({"type": "move", "label": "HighStep"}, {"type": "move", "label": MoveClassifier.STAND_UP}), "다른 라벨")
	var ok := {"type": TechniqueRunner.SUCCEEDED, "id": TechniqueJudge.T_DROP_KNEE, "side": &"LF", "key": "", "quality": 1.0, "reason": &""}
	runner.check(TutorialRunner.matches({"type": "technique", "id": "T_DROP_KNEE"}, ok), "technique는 기술 성공 이벤트")
	var started := ok.duplicate()
	started.type = TechniqueRunner.STARTED
	runner.check(not TutorialRunner.matches({"type": "technique", "id": "T_DROP_KNEE"}, started), "시작만으로는 불일치")
	runner.check(not TutorialRunner.matches({"type": "technique", "id": "T_OUTSIDE_EDGE"}, ok), "다른 기술")
	runner.check(TutorialRunner.matches({"type": "fall"}, {"type": "fall", "reason": "NO_SUPPORT"}), "fall")
	runner.check(TutorialRunner.matches({"type": "pad_deadpoint", "ok": true}, {"type": "pad_deadpoint", "limb": &"RH", "key": H03, "ok": true}), "bool 값")
	runner.check(not TutorialRunner.matches({"type": "pad_deadpoint", "ok": true}, {"type": "pad_deadpoint", "ok": false}), "bool 값 불일치")


func test_goal_advances() -> void:
	var r := _route([_step({"type": "grab", "limb": "LH", "slot": H03}), _step({"type": "move", "label": "StandUp"})])
	var s := ClimbSession.new(r)
	_settle(s)
	s._log_event({"type": "grab", "limb": &"LH", "key": H03, "quality": 1.0})  # 단계 시작 전 이벤트는 세지 않는다
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	runner.check(t.observe(s, s.step(), DT) == "", "시작 전 이벤트 무시")
	var res := _drag_observe(s, t, &"LH", H03)
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == H03, "LH가 H03에 붙음")
	runner.check(res.count("next") == 1 and res.back() == "next", "잡는 틱에 next: %s" % [res.slice(-3)])
	runner.check(t.index == 1 and not t.done, "다음 단계로")
	t.begin_step(s)
	runner.check(s.limbs[&"LH"].key == H03, "start_pose 없는 단계는 지금 자세를 잇는다")
	s._log_event({"type": "move", "label": MoveClassifier.HIGH_STEP})
	runner.check(t.observe(s, "", DT) == "", "다른 라벨은 진행 안 함")
	s._log_event({"type": "move", "label": MoveClassifier.STAND_UP})
	runner.check(t.observe(s, "", DT) == "done", "마지막 단계 완료")


func test_fall_restarts_step() -> void:
	var pose := {"pelvis": [0.0, 0.744], "angle": 0.0, "slots": {"LH": H01, "RH": H02, "LF": F01, "RF": F02}}
	var r := _route([_step({"type": "grab", "limb": "LH", "slot": H03}, {"start_pose": pose})])
	var s := ClimbSession.new(r)
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	for limb in s.limbs:
		s.limbs[limb].state = "Free"  # 모든 접점을 잃으면 지지 없음으로 떨어진다
	var res := ""
	for i in 300:
		var out := s.step()
		res = t.observe(s, out, DT)
		if out.begins_with("fall:"):
			break
	runner.check(res == "restart", "목표가 추락이 아니면 restart: %s" % res)
	runner.check(t.index == 0 and not t.done, "같은 단계")
	t.begin_step(s)
	runner.check(not s.falling, "추락 상태 해제")
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == H01 and s.limbs[&"RH"].key == H02, "단계 시작 자세로")
	runner.check(t.observe(s, s.step(), DT) == "", "추락 이벤트는 다시 세지 않음")

	# start_pose 없는 단계: 그 단계를 시작한 자세로 돌아간다
	var r2 := _route([_step({"type": "grab", "limb": "RH"}), _step({"type": "grab", "limb": "LH", "slot": H03})])
	var s2 := ClimbSession.new(r2)
	var t2 := TutorialRunner.new(r2)
	t2.begin_step(s2)
	s2.reset_to({"pelvis": [0.0, 0.744], "slots": {"LH": H01, "RH": H03, "LF": F01, "RF": F02}})
	s2._log_event({"type": "grab", "limb": &"RH", "key": H03, "quality": 1.0})
	runner.check(t2.observe(s2, "", DT) == "next", "1단계 완료")
	t2.begin_step(s2)
	s2.limbs[&"RH"].state = "Free"
	s2._start_fall("NO_SUPPORT")
	runner.check(t2.observe(s2, "fall:NO_SUPPORT", DT) == "restart", "restart")
	t2.begin_step(s2)
	runner.check(s2.limbs[&"RH"].state == "Attached" and s2.limbs[&"RH"].key == H03, "그 단계 시작 자세(RH=H03)로")


func test_fall_goal_completes_step() -> void:
	var pose2 := {"pelvis": [0.0, 0.744], "angle": 0.0, "slots": {"LH": H01, "RH": H02, "LF": F01, "RF": F02}, "stamina": {"LH": 55.0, "RH": 66.0}}
	var r := _route([_step({"type": "fall"}), _step({"type": "grab"}, {"start_pose": pose2}), _step({"type": "fall"}), _step({"type": "grab"})])
	var s := ClimbSession.new(r)
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	for limb in s.limbs:
		s.limbs[limb].state = "Free"  # 모든 접점을 잃으면 지지 없음으로 떨어진다
	var res := ""
	for i in 300:
		var out := s.step()
		res = t.observe(s, out, DT)
		if out.begins_with("fall:"):
			break
	runner.check(res == "next", "추락이 목표면 next: %s" % res)
	runner.check(t.index == 1, "다음 단계")
	t.begin_step(s)
	runner.check(not s.falling and s.limbs[&"LH"].key == H01, "다음 단계 시작 자세")
	runner.check(is_equal_approx(s.rules.stamina[&"LH"], 55.0) and is_equal_approx(s.rules.stamina[&"RH"], 66.0), "시작 자세의 체력")
	s._log_event({"type": "grab", "limb": &"LH", "key": H03, "quality": 1.0})
	runner.check(t.observe(s, "", DT) == "next", "2단계 완료")
	t.begin_step(s)
	s.limbs[&"LH"].state = "Free"
	s.limbs[&"RH"].state = "Free"
	s._start_fall("NO_SUPPORT")
	runner.check(t.observe(s, "fall:NO_SUPPORT", DT) == "next", "3단계(추락) 완료")
	t.begin_step(s)
	runner.check(not s.falling, "추락 해제")
	for limb in r.start_slots:
		runner.check(s.limbs[limb].state == "Attached" and s.limbs[limb].key == r.start_slots[limb], "start_pose 없으면 문제 시작 자세: %s" % limb)


func test_rules_applied() -> void:
	var r := _route([
		_step({"type": "fall"}, {"rules": {"fatigue_drain": false, "start_stamina": 40, "techniques": ["T_DROP_KNEE", "T_OUTSIDE_EDGE"]}}),
		_step({"type": "fall"})])
	var s := ClimbSession.new(r)
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	runner.check(s.rules.fatigue_disabled, "피로 감소 끔")
	runner.check(is_equal_approx(s.rules.stamina[&"LH"], 40.0) and is_equal_approx(s.rules.stamina[&"RH"], 40.0), "시작 체력 양손")
	var b := t.allowed_buttons()
	runner.check(b == [&"T_DROP_KNEE", &"T_OUTSIDE_EDGE"] and typeof(b[0]) == TYPE_STRING_NAME, "버튼 목록: %s" % [b])
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	for i in 60:
		s.step()
	runner.check(is_equal_approx(s.rules.stamina[&"RH"], 40.0), "피로가 줄지 않음")
	runner.check(t.observe(s, "fall:NO_SUPPORT", DT) == "next", "다음")
	t.begin_step(s)
	runner.check(not s.rules.fatigue_disabled, "규칙 없으면 피로 감소 켬")
	runner.check(t.allowed_buttons().is_empty(), "규칙 없으면 버튼 없음")


func test_help_levels() -> void:
	var r := _route([_step({"type": "grab", "limb": "LH", "slot": H03}), _step({"type": "fall"})])
	var s := ClimbSession.new(r)
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	runner.check(t.help_level() == 0 and t.help_text() == "", "처음 0")
	for i in 11:
		t.observe(s, "", 1.0)
	runner.check(t.help_level() == 0, "11초는 0")
	t.observe(s, "", 1.0)
	runner.check(t.help_level() == 1 and t.help_text() == "팔다리", "12초 → 1")
	for i in 2:
		runner.check(t.observe(s, "fall:NO_SUPPORT", DT) == "restart", "실패")
		t.begin_step(s)
	runner.check(t.help_level() == 1, "실패 2회는 그대로")
	t.observe(s, "fall:NO_SUPPORT", DT)
	t.begin_step(s)
	runner.check(t.help_level() == 2 and t.help_text() == "버튼", "그 상태에서 실패 3회 → 2")
	for i in 30:
		t.observe(s, "", 1.0)
	runner.check(t.help_level() == 2, "2가 최대")
	s._log_event({"type": "grab", "limb": &"LH", "key": H03, "quality": 1.0})
	runner.check(t.observe(s, "", DT) == "next", "진행")
	runner.check(t.help_level() == 0, "진행하면 0")
	# 실패 3회로 먼저 1, 그 뒤 12초로 2
	var t2 := TutorialRunner.new(r)
	t2.begin_step(s)
	for i in 3:
		t2.observe(s, "fall:NO_SUPPORT", DT)
		t2.begin_step(s)
	runner.check(t2.help_level() == 1, "실패 3회 → 1")
	for i in 12:
		t2.observe(s, "", 1.0)
	runner.check(t2.help_level() == 2, "다시 12초 → 2")


func test_last_step_done() -> void:
	var r := _route([_step({"type": "clear"})])
	var s := ClimbSession.new(r)
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	runner.check(t.observe(s, "", DT) == "", "clear 아님")
	runner.check(t.observe(s, "respawn", DT) == "", "respawn은 clear 아님")
	runner.check(t.observe(s, "clear", DT) == "done" and t.done, "clear → done")
	runner.check(t.observe(s, "clear", DT) == "" and t.index == 1, "끝난 뒤에는 아무것도 안 함")
	var empty := TutorialRunner.new(_route([]))
	runner.check(empty.done, "단계 없으면 바로 done")


func test_hold_still() -> void:
	var r := _route([_step({"type": "hold_still", "seconds": 1.0})])
	var s := ClimbSession.new(r)
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	var res := ""
	for i in 40:
		res = t.observe(s, s.step(), DT)
	runner.check(res == "", "0.67초는 아직")
	s.apply_input([{"type": "arm", "limb": &"LF"}])
	res = t.observe(s, s.step(), DT)
	runner.check(res == "", "눌러 두면 타이머 다시")
	s.apply_input([{"type": "disarm", "limb": &"LF"}])
	var n := 0
	while res == "" and n < 200:
		res = t.observe(s, s.step(), DT)
		n += 1
	runner.check(res == "done" and n >= 59 and n <= 61, "다시 1초 뒤 완료: %d틱 %s" % [n, res])


func test_together() -> void:
	var goal := {"type": "together", "limbs": ["LH", "RF"], "ticks": 6}
	var r := _route([_step(goal), _step(goal)])
	var s := ClimbSession.new(r)
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	# 5틱만 함께 끌기 → 놓고 잡아도 불충분
	s.limbs[&"LH"].state = "Dragging"
	s.limbs[&"RF"].state = "Dragging"
	for i in 5:
		runner.check(t.observe(s, "", DT) == "", "끄는 중")
	s.limbs[&"LH"].state = "Attached"
	s._log_event({"type": "grab", "limb": &"LH", "key": H01, "quality": 1.0})
	s.limbs[&"RF"].state = "Attached"
	s._log_event({"type": "grab", "limb": &"RF", "key": F02, "quality": 1.0})
	runner.check(t.observe(s, "", DT) == "", "5틱은 부족")
	# 6틱 함께 끈 뒤 LH 먼저 잡고 RF는 1.5초 뒤 잡기 → 완료
	s.limbs[&"LH"].state = "Dragging"
	s.limbs[&"RF"].state = "Dragging"
	for i in 6:
		t.observe(s, "", DT)
	s.limbs[&"LH"].state = "Attached"
	s._log_event({"type": "grab", "limb": &"LH", "key": H01, "quality": 1.0})
	s._log_event({"type": "pad_grip", "limb": &"LH", "key": H01, "mode": &"crimp"})
	var res := ""
	for i in 90:
		res = t.observe(s, "", DT)
	runner.check(res == "", "RF 아직")
	s.limbs[&"RF"].state = "Attached"
	s._log_event({"type": "grab", "limb": &"RF", "key": F02, "quality": 1.0})
	runner.check(t.observe(s, "", DT) == "next", "2초 안에 둘 다 잡으면 완료")
	# 2단계: 첫 놓기 뒤 2초가 넘으면 실패(restart)
	t.begin_step(s)
	s.limbs[&"LH"].state = "Dragging"
	s.limbs[&"RF"].state = "Dragging"
	for i in 6:
		t.observe(s, "", DT)
	s.limbs[&"RF"].state = "Attached"
	s._log_event({"type": "grab", "limb": &"RF", "key": F02, "quality": 1.0})
	s.limbs[&"LH"].state = "Free"
	res = ""
	var n := 0
	while res == "" and n < 300:
		res = t.observe(s, "", DT)
		n += 1
	runner.check(res == "restart" and n >= 120 and n <= 122, "2초 넘으면 restart: %d틱 %s" % [n, res])
	runner.check(t.index == 1, "같은 단계")


## technique 목표: 실제 기술 선택(session.choose)으로 드롭니가 유지 자세에 들어서면 완료.
func test_technique_goal_drop_knee() -> void:
	var r := _route([_step({"type": "technique", "id": "T_DROP_KNEE"}, {"rules": {"techniques": ["T_DROP_KNEE"]}})])
	var s := ClimbSession.new(r)
	var t := TutorialRunner.new(r)
	t.begin_step(s)
	_settle(s)
	runner.check(t.observe(s, "", DT) == "", "아직")
	runner.check(s.open_select(), "선택 열기")
	runner.check(s.choose(&"T_DROP_KNEE", &"left") == &"", "드롭니 선택")
	var res := ""
	var n := 0
	while res == "" and n < 120:
		res = t.observe(s, s.step(), DT)
		n += 1
	runner.check(res == "done" and t.done, "드롭니 성공으로 완료: %s (%d틱)" % [res, n])
	runner.check(s.runner.active.get("step") == &"yaw", "기술은 유지 중")
