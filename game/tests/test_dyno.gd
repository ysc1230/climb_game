extends RefCounted
## 다이노(2026-11-15 사용자): 몸을 두 번 빠르게 누르고(Tuning.DYNO_DOUBLE_TAP) 아래로 끌어 준비, 떼면 두 손발을 떼고
## 손이 높이(0.2~0.6m)만큼 뛴다. 손 에너지 20~40. 날아가는 동안 손 패드를 누르면 가까운 손홀드를 잡는다. 못 잡으면 추락.

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


func _charge(s: ClimbSession, drag: float) -> void:
	s.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	s.apply_input([{"type": "dyno_move", "limb": InputRouter.DYNO, "delta": Vector2(0, -drag)}])


func test_charge_preview_and_short_cancel() -> void:
	var s := _session()
	_charge(s, Tuning.DYNO_DRAG_MAX * 2.0)
	var pv := s.dyno_preview()
	runner.check(pv.ready and is_equal_approx(pv.cost, Tuning.DYNO_COST_MAX) and pv.rise > 0.3, "끝까지 끌면 힘 최대, 손이 더 오름 %s" % [pv])
	runner.check(s.rules.body_goal.y < s.body.pos.y - 0.1, "준비하면 골반 목표가 내려감")
	s.apply_input([{"type": "dyno_cancel", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty() and not s.rules.body_goal.is_finite(), "취소")
	_charge(s, Tuning.DYNO_DRAG_MIN * 0.5)
	s.apply_input([{"type": "dyno_end", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty() and s.attached().size() == 4, "짧게 끌면 뛰지 않음")
	var lo := _session()
	_charge(lo, Tuning.DYNO_DRAG_MIN)
	runner.check(is_equal_approx(lo.dyno_preview().cost, Tuning.DYNO_COST_MIN), "최소 길이면 힘 20")


## 좋은 홀드에서 끝까지 끌면 손이 "다리·팔을 쭉 편 높이"보다 높이 오른다. 홀드가 나쁘면 덜 오른다.
func test_height_and_hold_quality() -> void:
	var s := _session()
	var feet: float = ((s.limbs[&"LF"].grab as Vector2).y + (s.limbs[&"RF"].grab as Vector2).y) / 2.0
	var straight := feet + PoseSolver.reach_of(&"LF").y + Tuning.SHOULDER_OFFSET.y + PoseSolver.reach_of(&"LH").y
	_charge(s, Tuning.DYNO_DRAG_MAX)
	var good := s.dyno_preview()
	runner.check(good.quality > 0.9 and good.apex_hand > straight + 0.3, "좋은 홀드: 손 %.2f > 쭉 편 높이 %.2f + 0.3 (품질 %.2f)" % [good.apex_hand, straight, good.quality])
	var bad := _session()
	for limb in bad.attached():
		var slot: Dictionary = bad.route.slots[bad.limbs[limb].key]
		if slot.has("hand_area"):
			slot.hand_area.half_width = 0.03
		else:
			slot["foot_area"] = {"half_width": 0.02}
	_charge(bad, Tuning.DYNO_DRAG_MAX)
	var pb := bad.dyno_preview()
	runner.check(pb.quality < 0.45 and pb.apex_hand < good.apex_hand - 0.3, "나쁜 홀드는 덜 뜀: %.2f vs %.2f (품질 %.2f)" % [pb.apex_hand, good.apex_hand, pb.quality])


func _launch(s: ClimbSession, drag: float) -> void:
	_charge(s, drag)
	for i in 30:
		s.step()
	s.apply_input([{"type": "dyno_end", "limb": InputRouter.DYNO}])


func test_launch_aims_arms() -> void:
	var s := _session()
	_launch(s, Tuning.DYNO_DRAG_MAX * 0.5)
	runner.check(s.dyno_flying() and s.attached().is_empty(), "뛰면 네 손발이 모두 떨어짐")
	runner.check(absf(s.rules.stamina[&"LH"] - (100.0 - lerpf(Tuning.DYNO_COST_MIN, Tuning.DYNO_COST_MAX, 0.5 * Tuning.DYNO_DRAG_MAX / (Tuning.DYNO_DRAG_MAX - Tuning.DYNO_DRAG_MIN) - Tuning.DYNO_DRAG_MIN / (Tuning.DYNO_DRAG_MAX - Tuning.DYNO_DRAG_MIN)))) < 1.0, "손 에너지 소모 %.1f" % s.rules.stamina[&"LH"])
	var target: String = s.dyno.target
	runner.check(not target.is_empty(), "목표 홀드를 고름")
	var hand: StringName = s.dyno.catcher
	var sh := PoseSolver.joint_position(s.body.pos, s.body.angle, hand, s.body.yaw)
	var to_hand := (s.limbs[hand].pos as Vector2) - sh
	var to_target := s.route.slot_pos(target) - sh
	runner.check(to_hand.normalized().dot(to_target.normalized()) > 0.99, "팔이 목표 홀드 쪽")
	runner.check(to_hand.length() > PoseSolver.reach_of(hand).y * 0.95 or to_hand.distance_to(to_target) < 0.01, "팔을 쭉 폄 %.2f" % to_hand.length())


func test_window_and_assist() -> void:
	var s := _session()
	_launch(s, Tuning.DYNO_DRAG_MAX)
	var target: String = s.dyno.target
	var hw: float = s.route.slots[target].hand_area.half_width if s.route.slots[target].has("hand_area") else 0.13
	var want := lerpf(Tuning.DYNO_WINDOW_MIN, Tuning.DYNO_WINDOW_MAX, clampf((hw - 0.03) / 0.10, 0.0, 1.0)) if not s.route.goal_slots.has(target) else Tuning.DYNO_WINDOW_MAX
	runner.check(absi(int(s.dyno.window_ticks) - roundi(want * Tuning.TICK_HZ)) <= 1, "잡기 시간은 홀드에 따라 %.2f초" % want)
	var opened := false
	for i in 120:
		s.step()
		if not s.dyno_window().is_empty():
			opened = true
			break
	runner.check(opened, "목표에 가까워지면 잡기 버튼")
	var y0 := s.body.pos.y
	s.step()
	runner.check(absf(s.body.pos.y - y0) < 0.02, "느린 화면 %.3f" % absf(s.body.pos.y - y0))
	runner.check(s.dyno_assist(), "버튼 누르면 잡기")
	var hand: StringName = s.limbs.keys().filter(func(l): return s.limbs[l].key == target and s.limbs[l].state == "Attached").front()
	runner.check(PoseSolver.is_hand(hand), "목표 홀드를 손이 잡음")
	var feet := [&"LF", &"RF"].filter(func(f): return s.limbs[f].state == "Attached").size()
	runner.check(feet >= 1, "발도 딛음 %d" % feet)
	var res := ""
	for i in Tuning.DYNO_HANG_TICKS - 5:
		res = s.step()
		if res != "":
			break
	runner.check(res == "" or res == "clear", "잡은 뒤 1초는 버팀(정상이면 완등): '%s'" % res)


func test_window_expires_then_miss() -> void:
	var s := _session()
	_launch(s, Tuning.DYNO_DRAG_MIN)
	var result := ""
	for i in 400:
		result = s.step()
		if result.begins_with("fall:"):
			break
	runner.check(result == "fall:DYNO_MISS" and s.falling, "안 누르면 추락: %s" % result)


func test_pad_catch() -> void:
	var s := _session()
	_launch(s, Tuning.DYNO_DRAG_MAX)
	var caught := false
	for i in 200:
		s.step()
		for hand in [&"LH", &"RH"]:
			for key in s.route.slots:
				if s.route.slots[key].has("hand_area") and (s.limbs[hand].pos as Vector2).distance_to(s.route.slot_pos(key)) < Tuning.DYNO_CATCH_RADIUS * 0.8 and (s.route.slot_pos(key)).y > 1.9:
					s.apply_input([{"type": "detach", "limb": hand}])
					caught = s.limbs[hand].state == "Attached"
			if caught:
				break
		if caught:
			break
	runner.check(caught and not s.dyno_flying(), "손 패드를 누르면 가까운 홀드를 직접 잡음")


func test_needs_hand_and_foot() -> void:
	var s := _session()
	s.apply_input([{"type": "detach", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
	s.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty(), "발이 하나도 안 붙어 있으면 시작 안 함")
