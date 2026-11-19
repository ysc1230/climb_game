extends RefCounted
## docs/03 v0.9 몸통 끌기: 네 패드 사이 가운데 영역을 끌면 골반 목표가 그 방향으로 옮겨 가고(판정은 그대로),
## 손을 떼도 그 자리에 머물며, 다른 팔다리를 움직이기 시작하면 자동 자세로 돌아간다.

var runner


func _router() -> InputRouter:
	var r := InputRouter.new()
	r.set_pad(&"LH", Vector2(100, 200), 160)
	r.set_pad(&"RH", Vector2(1500, 200), 160)
	r.body_area = Rect2(Vector2(200, 120), Vector2(1200, 600))
	return r


func test_router_body_commands() -> void:
	var r := _router()
	var down := r.touch_down(0, Vector2(800, 400), false)
	runner.check(down.size() == 1 and down[0].type == "body_start", "가운데 누르면 body_start: %s" % [down])
	var mv := r.touch_drag(0, Vector2(880, 400), 0.0)
	runner.check(not mv.is_empty() and mv.back().type == "body_move" and (mv.back().delta as Vector2).x > 0.0, "오른쪽으로 끌면 body_move +x: %s" % [mv])
	var up := r.touch_up(0, 0.1)
	runner.check(up.size() == 1 and up[0].type == "body_end", "떼면 body_end")
	runner.check(r.touch_down(1, Vector2(1590, 850), false).is_empty(), "영역 밖·패드 밖은 그대로 무시")
	var r2 := InputRouter.new()
	runner.check(r2.touch_down(0, Vector2(800, 400), false).is_empty(), "영역을 정하지 않으면 예전처럼 무시")


func _session() -> ClimbSession:
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/G_V0_01.json"))
	for i in 60:
		s.step()
	return s


func test_body_goal_moves_pelvis() -> void:
	var s := _session()
	var x0 := s.body.pos.x
	s.apply_input([{"type": "body_start", "limb": &"BODY"}])
	s.apply_input([{"type": "body_move", "limb": &"BODY", "delta": Vector2(0.2, 0.0)}])
	for i in 60:
		s.step()
	runner.check(s.body.pos.x > x0 + 0.08, "골반이 오른쪽으로 옮겨 감: %.3f → %.3f" % [x0, s.body.pos.x])
	runner.check(PoseSolver.is_valid(s.body.pos, s.body.angle, s.attached(), s.body.yaw), "자세는 계속 성립(판정 그대로)")
	s.apply_input([{"type": "body_end", "limb": &"BODY"}])
	var held := s.body.pos.x
	for i in 60:
		s.step()
	runner.check(absf(s.body.pos.x - held) < 0.03, "손을 떼도 그 자리에 머묾: %.3f vs %.3f" % [s.body.pos.x, held])
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	runner.check(not s.rules.body_goal.is_finite(), "다른 팔다리를 움직이면 자동 자세로")


func test_body_goal_limited() -> void:
	var s := _session()
	s.apply_input([{"type": "body_start", "limb": &"BODY"}])
	var anchor := s.body.pos
	s.apply_input([{"type": "body_move", "limb": &"BODY", "delta": Vector2(3.0, 0.0)}])
	runner.check(is_equal_approx(s.rules.body_goal.distance_to(anchor), Tuning.BODY_GOAL_MAX), "목표는 최대 %.2fm" % Tuning.BODY_GOAL_MAX)
	for i in 90:
		s.step()
	runner.check(PoseSolver.is_valid(s.body.pos, s.body.angle, s.attached(), s.body.yaw), "멀리 끌어도 성립하지 않는 자세로는 가지 않음")


## 균형 보기(docs/49): 시작 자세(두 발)는 발 둘, 상태는 손 힘 규칙과 같고, 한 발을 떼면 발이 하나·편하지 않다.
func test_balance_view() -> void:
	var s := _session()
	for i in 60:
		s.step()
	var v := s.balance_view()
	runner.check(v.feet.size() == 2 and (v.com as Vector2).is_finite(), "두 발·무게중심 %s" % [v])
	var ok_rule := s.rules.foot_support >= Tuning.REST_FOOT_SUPPORT - 0.0001 and s.rules.phase == ClimbRules.Phase.STABLE
	runner.check((v.state == "ok") == ok_rule, "상태가 손 힘 규칙과 같음 %s" % v.state)
	s.apply_input([{"type": "detach", "limb": &"LF"}])
	for i in 30:
		s.step()
	var v2 := s.balance_view()
	runner.check(v2.feet.size() == 1 and v2.state != "ok", "한 발이면 편하지 않음 %s" % v2.state)
	var ld := s.limb_loads()
	runner.check(ld[&"LF"] == 0.0 and ld[&"RF"] > 0.0, "뗀 발은 몫 0 %s" % [ld])
	var sum := 0.0
	for l in ld:
		sum += ld[l]
	runner.check(absf(sum - 1.0) < 0.001, "몫의 합 = 100%% (%.3f)" % sum)


## 휴대폰 기울이기(docs/superpowers/specs/2026-11-19-2-tilt-design.md): 기울인 동안만 목표, 돌아오면 자동 자세.
func _tilt(s: ClimbSession, off: Vector2, active := true) -> void:
	s.apply_input([{"type": "body_tilt", "limb": &"BODY", "offset": off, "active": active}])


func test_body_tilt_moves_and_clears() -> void:
	var s := _session()
	var anchor := s.body.pos
	_tilt(s, Vector2(0.2, 0.0))
	runner.check(s.rules.body_goal.is_equal_approx(anchor + Vector2(0.2, 0.0)), "기울이기 시작 순간 골반 + offset %s" % s.rules.body_goal)
	for i in 60:
		_tilt(s, Vector2(0.2, 0.0))
		s.step()
	runner.check(s.body.pos.x > anchor.x + 0.08, "골반이 오른쪽으로 %.3f → %.3f" % [anchor.x, s.body.pos.x])
	_tilt(s, Vector2(0.25, 0.0))
	runner.check(s.rules.body_goal.is_equal_approx(anchor + Vector2(0.25, 0.0)), "기준점은 처음 그대로(위치 방식)")
	s.apply_input([{"type": "detach", "limb": &"LH"}])
	runner.check(s.rules.body_goal.is_finite(), "기울인 동안은 다른 팔다리를 움직여도 목표 유지")
	_tilt(s, Vector2.ZERO, false)
	runner.check(not s.rules.body_goal.is_finite(), "반응 범위로 돌아오면 목표를 지움")


func test_body_drag_wins_over_tilt() -> void:
	var s := _session()
	_tilt(s, Vector2(0.2, 0.0))
	s.apply_input([{"type": "body_start", "limb": &"BODY"}])
	var drag_anchor := s.body.pos
	_tilt(s, Vector2(0.3, 0.0))
	runner.check(s.rules.body_goal.is_equal_approx(drag_anchor), "가운데를 끄는 동안은 끌기가 이김 %s" % s.rules.body_goal)
	for i in 30:
		s.step()
	s.apply_input([{"type": "body_end", "limb": &"BODY"}])
	var p := s.body.pos
	_tilt(s, Vector2(0.1, 0.0))
	runner.check(s.rules.body_goal.is_equal_approx(p + Vector2(0.1, 0.0)), "손을 떼면 그 순간 골반이 새 기준점")


func test_body_tilt_limited_and_reset() -> void:
	var s := _session()
	var anchor := s.body.pos
	_tilt(s, Vector2(0.45, 0.45))
	runner.check(is_equal_approx(s.rules.body_goal.distance_to(anchor), Tuning.BODY_GOAL_MAX), "목표는 최대 %.2fm" % Tuning.BODY_GOAL_MAX)
	s.reset()
	_tilt(s, Vector2.ZERO, false)
	runner.check(not s.rules.body_goal.is_finite(), "다시 시작하면 기울이기 상태도 처음")
