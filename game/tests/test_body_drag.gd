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
	var s := ClimbSession.new(RouteDef.load_json(ContentIndex.route_path("G_V0_01")))
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
