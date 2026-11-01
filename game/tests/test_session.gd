extends RefCounted
## ClimbSession: play_test에서 분리한 등반 상태·고정 틱 (동작 변화 없음).

var runner


func _route() -> RouteDef:
	return RouteDef.load_json("res://data/routes/general/G_V0_01.json")


## limb을 target 쪽으로 끌어(요청 목표 이동) 후보가 key가 되면 놓는다. 성공하면 true.
func _drag_to(s: ClimbSession, limb: StringName, key: String, budget: int = 300) -> bool:
	var target := s.route.slot_pos(key)
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in budget:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(2.5 * Tuning.DT)}])
		var r := s.step()
		if r.begins_with("fall"):
			return false
		if s.limbs[limb].cand.get("key", "") == key:
			s.apply_input([{"type": "release", "limb": limb}])
			return s.limbs[limb].state == "Attached" and s.limbs[limb].key == key
	return false


## limb을 뗀 뒤 바깥쪽 허공(후보 없음)으로 끌어 둔다.
func _drag_into_air(s: ClimbSession, limb: StringName, dir: Vector2) -> void:
	s.apply_input([{"type": "detach", "limb": limb}])
	for i in 40:
		s.apply_input([{"type": "move", "limb": limb, "delta": dir * 2.5 * Tuning.DT}])
		s.step()


func _settle(s: ClimbSession, ticks: int = 60) -> String:
	for i in ticks:
		var r := s.step()
		if r != "":
			return r
	return ""


func test_reset_start_pose_stable() -> void:
	var s := ClimbSession.new(_route())
	var bad := 0
	for i in 120:
		if s.step() != "":
			bad += 1
	runner.check(bad == 0, "시작 자세 120틱 동안 결과 없음 (이상 %d)" % bad)
	runner.check(s.rules.phase == ClimbRules.Phase.STABLE, "시작 자세는 STABLE")


func test_drag_release_grabs_candidate() -> void:
	var s := ClimbSession.new(_route())
	var ok := _drag_to(s, &"LH", "G_V0_01/H03/hand_1")
	runner.check(ok, "LH를 H03까지 끌어 놓으면 붙는다")
	runner.check(s.limbs[&"LH"].state == "Attached", "LH Attached")
	runner.check(s.limbs[&"LH"].key == "G_V0_01/H03/hand_1", "LH 슬롯 키")


func test_release_without_candidate_frees() -> void:
	var s := ClimbSession.new(_route())
	_drag_into_air(s, &"LF", Vector2(-1, 0))
	runner.check(s.limbs[&"LF"].cand.is_empty(), "허공에는 후보 없음")
	s.apply_input([{"type": "release", "limb": &"LF"}])
	runner.check(s.limbs[&"LF"].state == "Free", "허공에서 놓으면 Free (%s)" % s.limbs[&"LF"].state)


func test_all_hands_off_falls() -> void:
	var s := ClimbSession.new(_route())
	# 시작 자세는 두 발이 발판 위라 손을 놓아도 서 있다. 한 발을 들어 발판 지지를 없앤다.
	s.apply_input([{"type": "detach", "limb": &"LF"}])
	s.step()
	s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"}])
	var result := ""
	var n := 0
	while result == "" and n < 20:
		s.apply_input([{"type": "move", "limb": &"LH", "delta": Vector2(-1, 0) * 2.5 * Tuning.DT},
			{"type": "move", "limb": &"RH", "delta": Vector2(1, 0) * 2.5 * Tuning.DT}])
		result = s.step()
		n += 1
		if n == 7:  # 허공에서 두 손 모두 놓기
			s.apply_input([{"type": "release", "limb": &"LH"}, {"type": "release", "limb": &"RH"}])
	runner.check(result == "fall:NO_SUPPORT", "두 손을 떼면 NO_SUPPORT 추락 (%s, %d틱)" % [result, n])
	runner.check(n <= Tuning.UNSUPPORTED_GRACE_TICKS, "마지막 지지 손이 떠난 뒤 유예 %d틱 이내 추락 (%d틱)" % [Tuning.UNSUPPORTED_GRACE_TICKS, n])
	runner.check(s.falling and s.falls == 1, "falling 상태와 falls 증가")


func test_grab_validates_reach() -> void:
	var s := ClimbSession.new(_route())
	var key: String = s.limbs[&"LH"].key  # 시작 슬롯: 도달 가능
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	var far := "G_V0_01/G01/goal_left"
	var contact := GripCheck.contact_for(key, s.route.slots, &"LH", s.route.slot_pos(key))
	runner.check(not s.grab(&"LH", far, s.route.slot_pos(far), contact), "닿지 않는 슬롯은 false")
	runner.check(s.limbs[&"LH"].state == "Dragging", "실패하면 상태 유지")
	runner.check(s.grab(&"LH", key, s.route.slot_pos(key), contact), "닿는 슬롯은 true")
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == key, "붙고 키 갱신")


func test_goal_clears() -> void:
	var s := ClimbSession.new(_route())
	var cleared := false
	var failure := ""
	for m in s.route.intended_moves:
		if not _drag_to(s, m[0], m[1]):
			failure = "%s→%s 실패" % [m[0], m[1]]
			break
		var r: String = _settle(s, 120)
		if r == "clear":
			cleared = true
			break
		if r != "":
			failure = "%s 후 %s" % [m[1], r]
			break
	if not cleared and failure.is_empty():
		for i in 600:
			var r: String = s.step()
			if r == "clear":
				cleared = true
				break
			if r != "":
				failure = r
				break
	runner.check(cleared, "의도 경로 재생이 완등 (%s)" % failure)
	runner.check(s.clears == 1, "clears == 1")
