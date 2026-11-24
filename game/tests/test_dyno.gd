extends RefCounted
## 다이노(docs/45): 몸을 두 번 빠르게 누르고(Tuning.DYNO_DOUBLE_TAP) 끌어 준비(끈 반대 방향으로 뜀), 떼면 네 손발을 떼고 뛴다.
## 준비 중 닿는 손홀드 표시, 날아가는 동안 팔이 닿은 홀드를 손 패드로 잡음, 발판 딛기, 손 힘 10~20, 잡은 뒤 2초 손 힘 절반만 빠짐.

var runner


func _router() -> InputRouter:
	var r := InputRouter.new()
	r.set_pad(&"LH", Vector2(100, 200), 160)
	r.set_pad(&"RH", Vector2(1500, 200), 160)
	r.body_area = Rect2(Vector2(200, 120), Vector2(1200, 600))
	return r


func test_router_double_tap() -> void:
	var r := _router()
	r.touch_down(0, Vector2(800, 400), false, 1.0)
	r.touch_up(0, 1.05)
	var down := r.touch_down(1, Vector2(800, 400), false, 1.05 + Tuning.DYNO_DOUBLE_TAP - 0.01)
	runner.check(down.size() == 1 and down[0].type == "dyno_start", "빨리 다시 누르면 dyno_start: %s" % [down])
	var mv := r.touch_drag(1, Vector2(800, 500), 1.2)
	runner.check(not mv.is_empty() and mv.back().type == "dyno_move" and (mv.back().delta as Vector2).y < 0.0, "아래로 끌면 dyno_move −y: %s" % [mv])
	runner.check(r.touch_up(1, 1.3) == [{"type": "dyno_end", "limb": InputRouter.DYNO}], "떼면 dyno_end")
	var rc := _router()
	rc.touch_down(0, Vector2(800, 400), false, 1.0)
	rc.touch_up(0, 1.05)
	rc.touch_down(1, Vector2(800, 400), false, 1.1)
	rc.touch_drag(1, Vector2(800, 520), 1.2)
	runner.check(not rc.dyno_touch().inside, "멀리 끌면 취소 원 밖")
	rc.touch_drag(1, Vector2(810, 410), 1.3)
	runner.check(rc.dyno_touch().inside, "처음 자리로 돌아오면 취소 원 안")
	runner.check(rc.touch_up(1, 1.4) == [{"type": "dyno_cancel", "limb": InputRouter.DYNO}], "취소 원 안에서 떼면 취소")
	var r2 := _router()
	r2.touch_down(0, Vector2(800, 400), false, 1.0)
	r2.touch_up(0, 1.05)
	var slow := r2.touch_down(1, Vector2(800, 400), false, 1.05 + Tuning.DYNO_DOUBLE_TAP + 0.05)
	runner.check(slow.size() == 1 and slow[0].type == "body_start", "늦게 누르면 보통 몸통 끌기: %s" % [slow])


func _session() -> ClimbSession:
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/G_V0_01.json"))
	for i in 60:
		s.step()
	return s


func _charge(s: ClimbSession, drag: float, dir := Vector2(0, -1)) -> void:
	s.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	s.apply_input([{"type": "dyno_move", "limb": InputRouter.DYNO, "delta": dir.normalized() * drag}])


func test_charge_preview_and_short_cancel() -> void:
	var s := _session()
	_charge(s, Tuning.DYNO_DRAG_MAX * 2.0)
	var pv := s.dyno_preview()
	runner.check(pv.ready and is_equal_approx(pv.cost, Tuning.DYNO_COST_MAX) and not pv.reach.is_empty(), "끝까지 끌면 힘 20, 닿는 홀드 표시 %s" % [pv])
	runner.check(s.rules.body_goal.y < s.body.pos.y - 0.1, "아래로 끌면 골반 목표가 내려감")
	s.apply_input([{"type": "dyno_cancel", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty() and not s.rules.body_goal.is_finite(), "취소")
	_charge(s, Tuning.DYNO_DRAG_MIN * 0.5)
	runner.check(s.dyno_preview().reach.is_empty(), "짧으면 표시 없음")
	s.apply_input([{"type": "dyno_end", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty() and s.attached().size() == 4, "짧게 끌면 뛰지 않음")
	var lo := _session()
	_charge(lo, Tuning.DYNO_DRAG_MIN)
	runner.check(is_equal_approx(lo.dyno_preview().cost, Tuning.DYNO_COST_MIN), "최소 길이면 힘 10")


## 길게 끌수록 더 높은 홀드까지 닿고, 좋은 홀드에서 끝까지 끌면 다리를 쭉 편 높이보다 높이 뛴다. 나쁜 홀드는 덜 뛴다.
func test_reach_by_length_and_quality() -> void:
	var s := _session()
	s._dyno_banned = {}  # 정상·마지막 홀드 막기(test_no_dyno_to_top_or_last_holds)와 상관없이 뛰는 높이만 본다
	_charge(s, Tuning.DYNO_DRAG_MIN + 0.01)
	var short_reach: Array = s.dyno_preview().reach
	var short_top := s.route.slot_pos(short_reach[0]).y if not short_reach.is_empty() else 0.0
	s.apply_input([{"type": "dyno_move", "limb": InputRouter.DYNO, "delta": Vector2(0, -1)}])
	var long_top := s.route.slot_pos(s.dyno_preview().reach[0]).y
	runner.check(long_top > short_top, "길게 끌면 더 높은 홀드 %.2f > %.2f" % [long_top, short_top])
	var feet: float = ((s.limbs[&"LF"].grab as Vector2).y + (s.limbs[&"RF"].grab as Vector2).y) / 2.0
	var straight_pelvis := feet + PoseSolver.reach_of(&"LF").y
	var v := s._dyno_velocity()
	var apex := s.body.pos.y + v.y * v.y / (2.0 * 9.8)
	runner.check(s.dyno_quality() > 0.9 and apex > straight_pelvis + 0.3, "좋은 홀드: 꼭대기 골반 %.2f > 쭉 편 %.2f + 0.3" % [apex, straight_pelvis])
	var bad := _session()
	for limb in bad.attached():
		var slot: Dictionary = bad.route.slots[bad.limbs[limb].key]
		if slot.has("hand_area"):
			slot.hand_area.half_width = 0.03
		else:
			slot["foot_area"] = {"half_width": 0.02}
	_charge(bad, Tuning.DYNO_DRAG_MAX)
	var vb := bad._dyno_velocity()
	runner.check(vb.y < v.y - 0.5, "나쁜 홀드는 덜 뜀 %.2f < %.2f" % [vb.y, v.y])


## 끈 반대 방향으로 뛴다: 오른쪽 아래로 끌면 왼쪽 위로.
func test_direction_follows_drag() -> void:
	var s := _session()
	_charge(s, Tuning.DYNO_DRAG_MAX, Vector2(1, -1))
	var v := s._dyno_velocity()
	runner.check(v.x < -0.5 and v.y > 0.5, "오른쪽 아래로 끌면 왼쪽 위로 %s" % v)
	var u := _session()
	_charge(u, Tuning.DYNO_DRAG_MAX, Vector2(1, 0.2))
	var vu := u._dyno_velocity()
	runner.check(rad_to_deg(absf(Vector2(0, 1).angle_to(vu))) <= Tuning.DYNO_MAX_ANGLE + 0.1, "옆으로 끌어도 위에서 %.0f° 안" % Tuning.DYNO_MAX_ANGLE)


func _launch(s: ClimbSession, drag: float, dir := Vector2(0, -1)) -> void:
	_charge(s, drag, dir)
	for i in 30:
		s.step()
	s.apply_input([{"type": "dyno_end", "limb": InputRouter.DYNO}])


func test_flight_arms_slow_and_catch() -> void:
	var s := _session()
	_launch(s, Tuning.DYNO_DRAG_MAX)
	runner.check(s.dyno_flying() and s.attached().is_empty(), "뛰면 네 손발이 모두 떨어짐")
	runner.check(absf(s.rules.stamina[&"LH"] - (100.0 - Tuning.DYNO_COST_MAX)) < 1.0, "손 힘 −20: %.1f" % s.rules.stamina[&"LH"])
	var top: String = s.dyno.reach[0]
	var hand: StringName = &""
	for i in 120:
		s.step()
		var aim := s.dyno_aim()
		for h in aim:
			if aim[h] == top:
				hand = h
		if hand != &"":
			break
	runner.check(hand != &"", "팔이 가장 높은 표시 홀드에 닿음")
	var key: String = s.dyno_aim()[hand]
	runner.check((s.limbs[hand].pos as Vector2).distance_to(s.route.slot_pos(key)) < 0.001, "팔을 그 홀드로 뻗음")
	runner.check(s.dyno_slow_left() > 0.0, "가장 높은 홀드에 닿으면 느린 화면")
	var hw: float = s.route.slots[key].hand_area.half_width if s.route.slots[key].has("hand_area") else 0.13
	var want := lerpf(Tuning.DYNO_WINDOW_MIN, Tuning.DYNO_WINDOW_MAX, clampf((hw - 0.03) / 0.10, 0.0, 1.0))
	runner.check(absi(int(s.dyno.window_ticks) - roundi(want * Tuning.TICK_HZ)) <= 1, "느린 화면 %.2f초(홀드 크기)" % want)
	s.apply_input([{"type": "detach", "limb": hand}])
	runner.check(s.limbs[hand].state == "Attached" and s.limbs[hand].key == key, "그 손 패드를 누르면 잡음")
	var feet := [&"LF", &"RF"].filter(func(f): return s.limbs[f].state == "Attached").size()
	runner.check(feet >= 1, "닿는 발판을 딛음 %d" % feet)
	s.step()
	runner.check(is_equal_approx(s.rules.drain_scale, Tuning.DYNO_RELIEF_SCALE), "잡은 뒤 손 힘 절반만 빠짐")
	var res := ""
	for i in Tuning.DYNO_RELIEF_TICKS:
		res = s.step()
		if res != "":
			break
	runner.check(res == "" or res == "clear", "잡은 뒤 버팀: '%s'" % res)
	if res == "":
		runner.check(is_equal_approx(s.rules.drain_scale, 1.0), "2초 뒤 원래대로")


func test_window_expires_then_miss() -> void:
	var s := _session()
	_launch(s, Tuning.DYNO_DRAG_MIN)
	var result := ""
	for i in 400:
		result = s.step()
		if result.begins_with("fall:"):
			break
	runner.check(result == "fall:DYNO_MISS" and s.falling, "안 누르면 추락: %s" % result)


func test_needs_hand_and_foot() -> void:
	var s := _session()
	s.apply_input([{"type": "detach", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
	s.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty(), "발이 하나도 안 붙어 있으면 시작 안 함")


## 누른 손이 잡고(왼손도), 잡으면 날던 방향으로 몸이 흔들리다 멈춘다(2026-11-18 사용자).
func test_pressed_hand_catches_and_sways() -> void:
	var s := _session()
	_launch(s, Tuning.DYNO_DRAG_MAX, Vector2(-0.3, -1))  # 오른쪽 위로
	var caught := false
	for i in 200:
		if not str(s.dyno_aim().get(&"LH", "")).is_empty():
			s.apply_input([{"type": "detach", "limb": &"LH"}])
			caught = s.limbs[&"LH"].state == "Attached"
			break
		s.step()
	runner.check(caught and s.limbs[&"RH"].state != "Attached", "왼손 패드를 누르면 왼손이 잡음")
	var xs := []
	for i in 50:
		s.step()
		xs.append(s.rules.body_goal.x)
	var lo: float = xs.min()
	var hi: float = xs.max()
	runner.check(hi - lo > 0.05, "잡은 뒤 골반 목표가 흔들림 %.3f" % (hi - lo))
	for i in Tuning.DYNO_HANG_TICKS:
		s.step()
	runner.check(not s.rules.body_goal.is_finite() or s.dyno.is_empty(), "흔들림은 버티는 시간 뒤 멈춤")


## 2026-11-25 사용자: "다이노는 한 판에 한 번만 가능하게". 판 = 시작(또는 다시 시작)부터 추락·완등까지.
func test_dyno_once_per_attempt() -> void:
	var s := _session()
	_launch(s, Tuning.DYNO_DRAG_MAX, Vector2(-0.3, -1))
	var caught := false
	for i in 200:
		if not str(s.dyno_aim().get(&"LH", "")).is_empty():
			s.apply_input([{"type": "detach", "limb": &"LH"}])
			caught = s.limbs[&"LH"].state == "Attached"
			break
		s.step()
	for i in Tuning.DYNO_HANG_TICKS + 5:
		s.step()
	runner.check(caught and s.dyno.is_empty() and not s.falling, "다이노로 잡고 버팀이 끝남")
	s.messages.clear()
	s.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty() and s.messages.has("다이노는 한 판에 한 번만 할 수 있어요"), "같은 판에 두 번째 다이노는 안 됨: %s" % [s.messages])
	s.reset()
	s.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.get("phase", "") == "charge", "다시 시작하면 또 할 수 있음")
	var c := _session()
	_charge(c, Tuning.DYNO_DRAG_MAX)
	c.apply_input([{"type": "dyno_cancel", "limb": InputRouter.DYNO}])
	c.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	runner.check(c.dyno.get("phase", "") == "charge", "취소한 준비는 횟수에 들지 않음")


## 2026-11-25 사용자: "탑 홀드와 탑 전 홀드는 다이노가 불가능하게". 탑 전 홀드 = 정답 순서에서 두 손이 정상 직전에 각각 잡는 홀드.
## 일반·만든 문제만(다이노 수업 코스는 정상으로 뛰는 것이 수업이라 그대로).
func test_no_dyno_to_top_or_last_holds() -> void:
	var s := _session()
	var banned: Dictionary = s.dyno_banned_holds()
	runner.check(banned.size() == 3 and banned.has("G_V0_01/G01") and banned.has("G_V0_01/H05") and banned.has("G_V0_01/H06"), "정상·두 손의 마지막 홀드 %s" % [banned])
	var h3 := s.route.slot_pos("G_V0_01/H03/hand_1")
	var h4 := s.route.slot_pos("G_V0_01/H04/hand_1")
	s.reset_to({"pelvis": [(h3.x + h4.x) / 2.0, (h3.y + h4.y) / 2.0 - 0.6], "slots": {"LH": "G_V0_01/H03/hand_1", "RH": "G_V0_01/H04/hand_1", "LF": "G_V0_01/F03/foot_1", "RF": "G_V0_01/F04/foot_1"}})
	for i in 30:
		s.step()
	_charge(s, Tuning.DYNO_DRAG_MAX)
	var reach: Array = s.dyno_preview().reach
	runner.check(reach.all(func(k): return not banned.has(String(k).get_base_dir())), "닿는 표시에 정상·마지막 홀드 없음 %s" % [reach])
	var plain := _session()
	plain.reset_to({"pelvis": [(h3.x + h4.x) / 2.0, (h3.y + h4.y) / 2.0 - 0.6], "slots": {"LH": "G_V0_01/H03/hand_1", "RH": "G_V0_01/H04/hand_1", "LF": "G_V0_01/F03/foot_1", "RF": "G_V0_01/F04/foot_1"}})
	plain.route.mode = "course"
	plain._dyno_banned = {}
	for i in 30:
		plain.step()
	_charge(plain, Tuning.DYNO_DRAG_MAX)
	runner.check(plain.dyno_preview().reach.any(func(k): return banned.has(String(k).get_base_dir())), "막지 않으면 이 자리에서 닿음(검사가 의미 있음)")
	var lesson := ClimbSession.new(RouteDef.load_json("res://data/routes/course/C_DYNO_T.json"))
	runner.check(lesson.dyno_banned_holds().is_empty(), "다이노 수업은 막지 않음")
