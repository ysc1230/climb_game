extends RefCounted
## 기술 선택 중 시간 정지(docs/27 §6, 15 v0.6 TechniqueSelect): TA13·TA14.

var runner


func _session() -> ClimbSession:
	var s := ClimbSession.new(RouteDef.load_json("res://data/routes/R01.json"))
	for i in 30:
		s.step()
	return s


func test_select_freezes_time() -> void:
	var s := _session()
	var pos := s.body.pos
	var ang := s.body.angle
	var vel := s.body.vel
	var stamina := s.rules.stamina.duplicate()
	var ticks := s.tick_count
	var phase: int = s.rules.phase
	runner.check(s.open_select() and s.selecting, "열린다")
	for i in 600:
		runner.check(s.step() == "", "선택 중 step은 빈 문자열")
	runner.check(s.body.pos == pos and s.body.angle == ang and s.body.vel == vel, "몸통 불변")
	runner.check(s.rules.stamina == stamina, "피로 불변")
	runner.check(s.tick_count == ticks, "경과 틱 불변")
	runner.check(s.rules.phase == phase and s.rules.unsupported_ticks == 0 and s.rules.imbalance_ticks == 0, "카운터 불변")
	s.close_select()
	s.step()
	runner.check(s.tick_count == ticks + 1, "닫으면 시간이 다시 흐른다")


func test_select_freezes_grace_counter() -> void:
	var s := _session()
	s.apply_input([{"type": "detach", "limb": &"LF"}])
	s.step()
	s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"}])
	var n := 0
	var result := ""
	for i in 2:  # 허공으로 벌린다(무지지 카운터가 이미 오르는 중)
		s.apply_input([{"type": "move", "limb": &"LH", "delta": Vector2(-1, 0) * 2.5 * Tuning.DT},
			{"type": "move", "limb": &"RH", "delta": Vector2(1, 0) * 2.5 * Tuning.DT}])
		s.step()
	# 허공에서 모두 놓아 Free로 만든다(Dragging이면 열 수 없음)
	s.apply_input([{"type": "cancel", "limb": &"LH"}, {"type": "cancel", "limb": &"RH"}, {"type": "cancel", "limb": &"LF"}])  # Dragging → Free
	while s.rules.unsupported_ticks < 4 and n < 20:
		result = s.step()
		n += 1
	runner.check(s.rules.unsupported_ticks == 4 and result == "", "전제: 무지지 4틱 (%d, %s)" % [s.rules.unsupported_ticks, result])
	runner.check(s.open_select(), "무지지 중에도 열린다(드래그 아님)")
	for i in 600:
		s.step()
	runner.check(s.rules.unsupported_ticks == 4 and not s.falling, "600틱 뒤에도 4틱")
	s.close_select()
	for i in 4:
		result = s.step()
		runner.check(result == "", "유예 안 %d" % i)
	result = s.step()
	runner.check(result == "fall:NO_SUPPORT", "9번째 틱에 추락 (%s)" % result)


func test_cannot_open_while_dragging() -> void:
	var s := _session()
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	runner.check(not s.open_select() and not s.selecting, "LH Dragging이면 열 수 없다")


func test_select_clears_armed_without_release() -> void:
	var s := _session()
	var rt := InputRouter.new()
	rt.set_pad(&"LH", Vector2(100, 200), 160)
	rt.deadzone_px = 20
	var key: String = s.limbs[&"LH"].key
	var grab: Vector2 = s.limbs[&"LH"].grab
	s.apply_input(rt.touch_down(1, Vector2(100, 200), true))
	runner.check(s.limbs[&"LH"].state == "Armed", "전제: Armed")
	runner.check(s.open_select(), "열기")
	rt.cancel_all()
	runner.check(s.limbs[&"LH"].state == "Attached", "Attached로")
	runner.check(rt.touch_drag(1, Vector2(300, 200)).is_empty(), "옛 터치 drag는 빈 배열")
	runner.check(rt.touch_up(1).is_empty(), "옛 터치 up은 빈 배열")
	runner.check(s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == key and s.limbs[&"LH"].grab == grab and s.limbs[&"LH"].contact != null, "상태·접점 그대로")


func test_choose_resumes_immediately() -> void:
	var s := _session()
	var key := "R01/F03/foot_1"
	runner.check(s.open_select(), "열기")
	var ticks := s.tick_count
	s.step()
	runner.check(s.tick_count == ticks, "선택 중 정지")
	runner.check(s.choose(&"T_HIGH_STEP", &"left", key, s.route.slot_pos(key)) == &"", "choose 성공")
	runner.check(not s.selecting, "선택 해제")
	s.step()
	runner.check(s.tick_count == ticks + 1 and not s.runner.active.is_empty(), "같은 틱부터 진행")


func test_choose_failure_keeps_selecting() -> void:
	var s := _session()
	s.open_select()
	var r := s.choose(&"T_HIGH_STEP", &"left", "")
	runner.check(r == TechniqueJudge.NO_HOLD and s.selecting, "홀드 없으면 이유와 선택 유지: %s" % r)
