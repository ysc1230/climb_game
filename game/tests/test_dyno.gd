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
	runner.check(pv.ready and is_equal_approx(pv.height, Tuning.DYNO_H_MAX) and is_equal_approx(pv.cost, Tuning.DYNO_COST_MAX), "끝까지 끌면 최대 %s" % [pv])
	runner.check(s.rules.body_goal.y < s.body.pos.y - 0.1, "준비하면 골반 목표가 내려감")
	s.apply_input([{"type": "dyno_cancel", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty() and not s.rules.body_goal.is_finite(), "취소")
	_charge(s, Tuning.DYNO_DRAG_MIN * 0.5)
	s.apply_input([{"type": "dyno_end", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty() and s.attached().size() == 4, "짧게 끌면 뛰지 않음")
	var lo := _session()
	_charge(lo, Tuning.DYNO_DRAG_MIN)
	var p2 := lo.dyno_preview()
	runner.check(is_equal_approx(p2.height, Tuning.DYNO_H_MIN) and is_equal_approx(p2.cost, Tuning.DYNO_COST_MIN), "최소 길이면 최소 %s" % [p2])


func test_launch_and_catch() -> void:
	var s := _session()
	_charge(s, Tuning.DYNO_DRAG_MAX)
	for i in 30:
		s.step()
	s.apply_input([{"type": "dyno_end", "limb": InputRouter.DYNO}])
	runner.check(s.dyno_flying() and s.attached().is_empty(), "뛰면 네 손발이 모두 떨어짐")
	runner.check(absf(s.rules.stamina[&"LH"] - (100.0 - Tuning.DYNO_COST_MAX)) < 1.0, "손 에너지 −40: %.1f" % s.rules.stamina[&"LH"])
	var target := s.route.slot_pos("G_V0_01/H05/hand_1")
	var caught := false
	for i in 120:
		s.step()
		if (s.limbs[&"LH"].pos as Vector2).distance_to(target) < Tuning.DYNO_CATCH_RADIUS * 0.8:
			s.apply_input([{"type": "detach", "limb": &"LH"}])
			caught = true
			break
	runner.check(caught and s.limbs[&"LH"].state == "Attached" and s.limbs[&"LH"].key == "G_V0_01/H05/hand_1", "가까울 때 손 패드를 누르면 H05를 잡음")
	runner.check(not s.dyno_flying() and s.limbs[&"LF"].state == "Free" and s.limbs[&"RF"].state == "Free", "잡으면 비행 끝, 두 발은 떨어진 채")
	var res := ""
	for i in Tuning.DYNO_HANG_TICKS - 5:
		res = s.step()
		if res != "":
			break
	runner.check(res == "", "잡은 뒤 1초는 버팀: '%s'" % res)
	s.apply_input([{"type": "detach", "limb": &"RH"}])
	runner.check(s.limbs[&"RH"].state == "Attached" and s.limbs[&"RH"].key != s.limbs[&"LH"].key, "그동안 다른 손 패드를 누르면 근처 홀드를 잡음: %s %s" % [s.limbs[&"RH"].state, s.limbs[&"RH"].key])
	for i in 60:
		res = s.step()
		if res != "":
			break
	runner.check(res == "", "두 손으로 매달리면 버팀(발 없이): '%s' %s" % [res, s.rules.phase_name()])


func test_miss_falls() -> void:
	var s := _session()
	_charge(s, Tuning.DYNO_DRAG_MIN)
	s.apply_input([{"type": "dyno_end", "limb": InputRouter.DYNO}])
	var result := ""
	for i in 200:
		result = s.step()
		if result.begins_with("fall:"):
			break
	runner.check(result == "fall:DYNO_MISS" and s.falling, "못 잡으면 추락: %s" % result)


func test_needs_hand_and_foot() -> void:
	var s := _session()
	s.apply_input([{"type": "detach", "limb": &"LF"}, {"type": "detach", "limb": &"RF"}])
	s.apply_input([{"type": "dyno_start", "limb": InputRouter.DYNO}])
	runner.check(s.dyno.is_empty(), "발이 하나도 안 붙어 있으면 시작 안 함")
