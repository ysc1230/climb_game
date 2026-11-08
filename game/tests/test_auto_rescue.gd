extends RefCounted
## 자동 도움(AutoRescue, 2026-11-09): 위험 게이지를 누르면 손 하나·발 하나까지 옮겨 버틸 수 있는 자세로.
## 정상(goal) 홀드는 절대 고르지 않는다.

var runner
const ROUTES := ["res://data/routes/general/G_V0_01.json", "res://data/routes/general/G_V3_01.json", "res://data/routes/general/G_V4_01.json", "res://data/routes/general/G_V4_02.json"]
const DROPS := [[&"LH", &"LF"], [&"RF", &"RH"], [&"LH", &"RH", &"LF"], [&"RH"]]


func _danger_session(path: String, drop: Array) -> ClimbSession:
	var s := ClimbSession.new(RouteDef.load_json(path))
	for i in 20:
		s.step()
	var pose := s.current_pose()
	for l in drop:
		pose.slots.erase(l)
	s.reset_to(pose)
	s.step()
	return s


func test_plans_are_safe_and_limited() -> void:
	var planned := 0
	for path in ROUTES:
		for drop in DROPS:
			var s := _danger_session(path, drop)
			var p := AutoRescue.plan(s)
			if p.is_empty():
				continue
			planned += 1
			var hands := 0
			var feet := 0
			for m in p.moves:
				if PoseSolver.is_hand(m.limb):
					hands += 1
				else:
					feet += 1
				runner.check(not s.route.goal_slots.has(m.key), "정상 홀드는 고르지 않음: %s" % m.key)
			runner.check(hands <= 1 and feet <= 1, "팔·다리 최대 한 번씩: %s" % [p.moves])
			# 계획대로 옮긴 뒤 1초 동안 떨어지지 않는다
			var pose := {"pelvis": [p.pelvis.x, p.pelvis.y], "angle": p.angle, "slots": p.slots, "stamina": s.rules.stamina.duplicate()}
			s.reset_to(pose)
			var fell := false
			for i in 60:
				if s.step().begins_with("fall:"):
					fell = true
			runner.check(not fell and s.rules.phase in [ClimbRules.Phase.STABLE, ClimbRules.Phase.STRAINED], "%s %s: 도운 뒤 안정(phase %d)" % [path.get_file(), drop, s.rules.phase])
	runner.check(planned >= 12, "대부분의 위험 상황에서 계획을 찾음: %d/16" % planned)


func test_goal_hold_never_offered() -> void:
	for path in ROUTES:
		var s := ClimbSession.new(RouteDef.load_json(path))
		var goal := s.route.slot_pos(s.route.goal_slots[0])
		s.body.pos = goal - Vector2(0, 0.55)  # 정상 바로 아래
		var opts := AutoRescue.options(s, {})
		var near_goal := false
		for o in opts:
			runner.check(not s.route.goal_slots.has(o.key), "%s: 정상 홀드 후보 없음" % path.get_file())
			if PoseSolver.is_hand(o.limb):
				near_goal = true
		runner.check(near_goal or opts.is_empty(), "정상 아래에서도 다른 손 홀드 후보는 있음")


func test_progress_prefers_higher_hand() -> void:
	var s := _danger_session(ROUTES[0], [&"RH"])
	var base := {&"LH": s.limbs[&"LH"].key}
	var low := AutoRescue.progress(s, base, [{"limb": &"RH", "key": s.limbs[&"LH"].key}])
	var opts := AutoRescue.options(s, base)
	var best := 0.0
	for o in opts:
		best = maxf(best, AutoRescue.progress(s, base, [o]))
	runner.check(low == 0.0 and best > 0.0, "더 높은 홀드로 가면 가산점")
