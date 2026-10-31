extends RefCounted
## docs/04 §4 지지 계산의 대표 상황. 헤드리스.

var runner


func _c(limb: StringName, x: float, y: float) -> Dictionary:
	return SupportSolver.contact(limb, Vector2(x, y))


func test_four_point_is_stable() -> void:
	var r := SupportSolver.solve([_c(&"LH", -0.45, 1.80), _c(&"RH", 0.45, 1.80), _c(&"LF", -0.30, 0.10), _c(&"RF", 0.30, 0.10)], Vector2(0, 1.0))
	runner.check(r.status == SupportSolver.Status.FEASIBLE, "네 점 지지 가능, 잔차 %.4f" % r.residual)
	runner.check(SupportSolver.max_u(r) <= SupportSolver.STABLE_LOAD_RATIO, "최대 사용률 %.2f ≤ 0.80" % SupportSolver.max_u(r))
	var sum := 0.0
	for l in r.loads:
		sum += r.loads[l]
	runner.check(sum > 0.99, "하중 합 ≥ 체중")


func test_single_hand_above_com_is_strained() -> void:
	var r := SupportSolver.solve([_c(&"LH", 0.0, 2.0)], Vector2(0, 1.0))
	runner.check(r.status == SupportSolver.Status.FEASIBLE, "손 바로 아래 매달림 가능")
	runner.check(absf(r.u[&"LH"] - 1.0 / SupportSolver.HAND_MAX_LOAD) < 0.02, "u ≈ 1/1.10, 실제 %.3f" % r.u[&"LH"])
	runner.check(SupportSolver.max_u(r) > SupportSolver.STABLE_LOAD_RATIO, "Strained 영역")


func test_single_hand_offset_is_infeasible() -> void:
	# 한 손이 옆으로 0.6m 떨어져 있고 다른 접점 없음 → 모멘트 균형 불가(몸이 손 아래로 정렬되어야 함)
	var r := SupportSolver.solve([_c(&"LH", -0.6, 1.8)], Vector2(0, 1.0))
	runner.check(r.status == SupportSolver.Status.INFEASIBLE, "옆으로 벗어난 한 손은 균형 불가, 상태 %d" % r.status)
	runner.check(r.moment_residual > SupportSolver.MOMENT_TOLERANCE, "모멘트 잔차 %.3f" % r.moment_residual)


func test_same_side_hand_and_foot_feasible() -> void:
	# 같은 쪽 손·발도 일괄 금지하지 않는다(docs/25)
	var r := SupportSolver.solve([_c(&"LH", -0.45, 1.8), _c(&"LF", -0.30, 0.1)], Vector2(0, 1.0))
	runner.check(r.status == SupportSolver.Status.FEASIBLE, "같은 쪽 손·발 지지 가능, 잔차 %.4f" % r.residual)


func test_feet_cannot_pull() -> void:
	# 발만 위쪽에 있고 무게중심이 아래: 발은 밀기만 하므로 위로 끌어올리는 해 없음 → 힘 방향은 위지만 접점이 COM 위
	# 두 발이 COM보다 아래 양옆이면 가능(서기)
	var stand := SupportSolver.solve([_c(&"LF", -0.3, 0.1), _c(&"RF", 0.3, 0.1)], Vector2(0, 1.0))
	runner.check(stand.status == SupportSolver.Status.FEASIBLE, "양발 서기 가능(플랫폼)")
	var one_far := SupportSolver.solve([_c(&"LF", -0.8, 0.1)], Vector2(0, 1.0))
	runner.check(one_far.status == SupportSolver.Status.INFEASIBLE, "멀리 한 발로는 불가")


func test_deterministic() -> void:
	var cs := [_c(&"LH", -0.45, 1.80), _c(&"RH", 0.45, 1.80), _c(&"LF", -0.30, 0.10)]
	var a := SupportSolver.solve(cs, Vector2(0.05, 1.0))
	var b := SupportSolver.solve(cs, Vector2(0.05, 1.0))
	for l in a.loads:
		runner.check(a.loads[l] == b.loads[l], "같은 입력 같은 해")


func test_solver_speed() -> void:
	var cs := [_c(&"LH", -0.45, 1.80), _c(&"RH", 0.45, 1.80), _c(&"LF", -0.30, 0.10), _c(&"RF", 0.30, 0.10)]
	var t0 := Time.get_ticks_usec()
	for i in 100:
		SupportSolver.solve(cs, Vector2(0.01 * i, 1.0))
	var per := (Time.get_ticks_usec() - t0) / 100.0
	print("    SupportSolver 1회 평균 %.0fµs (맥, 헤드리스)" % per)
	runner.check(per < 3000.0, "1회 %.0fµs" % per)


func test_quality_scales_capacity() -> void:
	# 한 손 바로 아래 매달림: q=1(최대 1.10)은 가능, q=0(최대 0.55)은 불가
	var good := SupportSolver.contact_with(&"LH", Vector2(0, 2.0), Vector2(0, 1), 65.0, SupportSolver.HAND_MAX_LOAD)
	var bad := SupportSolver.contact_with(&"LH", Vector2(0, 2.0), Vector2(0, 1), 65.0 * 0.6, SupportSolver.HAND_MAX_LOAD * 0.5)
	runner.check(SupportSolver.solve([good], Vector2(0, 1.0)).status == SupportSolver.Status.FEASIBLE, "q=1 가능")
	runner.check(SupportSolver.solve([bad], Vector2(0, 1.0)).status == SupportSolver.Status.INFEASIBLE, "q=0 불가")


func test_sidepull_axis_horizontal() -> void:
	var hand := SupportSolver.contact_with(&"LH", Vector2(-0.4, 1.4), Vector2(-1, 0), 50.0, SupportSolver.HAND_MAX_LOAD)
	# 발이 멀리 왼쪽에 있어 발만으로는 모멘트가 안 맞고, 사이드풀 손이 왼쪽으로 당겨야 한다
	var feet := [_c(&"LF", -2.0, 0.1), _c(&"RF", -1.8, 0.1)]
	var r := SupportSolver.solve([hand] + feet, Vector2(0, 1.0))
	runner.check(r.status == SupportSolver.Status.FEASIBLE, "사이드풀 해 있음, 잔차 %.4f" % r.residual)
	runner.check(r.loads[&"LH"] > 0.05, "사이드풀 손이 하중을 받음 %.3f" % r.loads[&"LH"])
	# 힘은 축 (-1,0) ±50° 안의 조합이라 하중이 있으면 X 성분이 음수(cos50°·load 만큼)
	var fx: float = r.loads[&"LH"] * -1.0 * cos(deg_to_rad(50.0))
	runner.check(fx < 0.0 and (hand.axis as Vector2).x < 0.0, "손 힘 X 성분 음수 %.3f" % fx)
