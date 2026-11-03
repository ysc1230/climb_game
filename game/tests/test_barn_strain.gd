extends RefCounted
## docs/30 §4.1 문 열림 부담: τ/용량 비율 r이 0.5를 넘으면 하중 받는 손의 피로(감소량)가 늘고(r=1에서 ×4),
## 그 자세에서는 쉬어 회복하지 못한다. 넘으면(r>1) 지금처럼 REBALANCING이다.

var runner


func _barn(tau: float, capacity: float) -> Dictionary:
	return {"applies": true, "tau": tau, "capacity": capacity, "exceeded": tau > capacity}


func test_strain_multiplier_curve() -> void:
	runner.check(is_equal_approx(ClimbRules.barn_strain({"barn": SupportSolver.barn_door_none()}), 1.0), "적용 안 되면 1")
	runner.check(is_equal_approx(ClimbRules.barn_strain({"barn": _barn(0.045, 0.09)}), 1.0), "r=0.5면 1")
	runner.check(is_equal_approx(ClimbRules.barn_strain({"barn": _barn(0.0675, 0.09)}), 2.5), "r=0.75면 2.5")
	runner.check(is_equal_approx(ClimbRules.barn_strain({"barn": _barn(0.09, 0.09)}), Tuning.BARN_STRAIN_MAX_MULT), "r=1이면 최대 4")
	runner.check(is_equal_approx(ClimbRules.barn_strain({"barn": _barn(0.12, 0.09)}), 1.0), "초과(r>1)는 REBALANCING이 맡으므로 1")


func test_barn_door_reports_ratio() -> void:
	var c := [SupportSolver.contact(PoseSolver.LH, Vector2(-0.40, 1.75)), SupportSolver.contact(PoseSolver.LF, Vector2(-0.38, 0.35))]
	var b := SupportSolver.barn_door(c, {PoseSolver.LH: 0.5, PoseSolver.LF: 0.5}, Vector2(-0.33, 1.0), {})
	runner.check(b.applies and is_equal_approx(b.ratio, b.tau / b.capacity), "ratio = τ/용량: %s" % [b])


## 같은 결과에서 τ만 다르게 줬을 때 하중 받는 손의 체력 감소가 배율만큼 커진다.
func test_strained_hand_drains_faster() -> void:
	var calm := _drain(_barn(0.03, 0.09))
	var strained := _drain(_barn(0.0675, 0.09))
	runner.check(calm > 0.0, "기준 감소 있음 %.4f" % calm)
	runner.check(absf(strained - calm * 2.5) < 1e-4, "r=0.75면 2.5배: %.4f vs %.4f" % [strained, calm])


## 아웃사이드 엣지(용량 0.15)면 같은 τ에서 부담이 줄어 덜 지친다.
func test_outside_edge_capacity_lowers_strain() -> void:
	var inside := _drain(_barn(0.08, 0.09))
	var outside := _drain(_barn(0.08, 0.15))
	runner.check(outside < inside, "아웃사이드 %.4f < 보통 %.4f" % [outside, inside])


## 두 발 하중·손 하중 낮음·정지라도 부담 중(r>0.5)이면 쉬어 회복하지 못한다.
func test_no_rest_while_strained() -> void:
	var rules := _rules()
	var res := _result(_barn(0.0675, 0.09), 0.2)
	rules.loaded_feet = [PoseSolver.LF, PoseSolver.RF]
	for i in ClimbRules.REST_CONFIRM_TICKS + 30:
		rules._apply_fatigue(res, _attached(), false, false, 0.0)
	runner.check(rules.stamina[PoseSolver.LH] < 80.0, "부담 중에는 회복 없음: %.2f" % rules.stamina[PoseSolver.LH])
	var rules2 := _rules()
	rules2.loaded_feet = [PoseSolver.LF, PoseSolver.RF]
	var calm := _result(_barn(0.02, 0.09), 0.2)
	for i in ClimbRules.REST_CONFIRM_TICKS + 30:
		rules2._apply_fatigue(calm, _attached(), false, false, 0.0)
	runner.check(rules2.stamina[PoseSolver.LH] > 80.0, "부담 없으면 회복: %.2f" % rules2.stamina[PoseSolver.LH])


func _attached() -> Dictionary:
	return {PoseSolver.LH: Vector2(-0.40, 1.75), PoseSolver.LF: Vector2(-0.38, 0.35)}


func _rules() -> ClimbRules:
	var rules := ClimbRules.new()
	rules.phase = ClimbRules.Phase.STABLE
	rules.stamina = {PoseSolver.LH: 80.0, PoseSolver.RH: 80.0}
	return rules


func _result(barn: Dictionary, u: float) -> Dictionary:
	return {"status": SupportSolver.Status.FEASIBLE, "u": {PoseSolver.LH: u}, "loads": {PoseSolver.LH: 0.5, PoseSolver.LF: 0.5}, "barn": barn}


## 한 손(LH)·한 발 하중 자세에서 1초 동안 LH 체력 감소량.
func _drain(barn: Dictionary) -> float:
	var rules := _rules()
	rules.loaded_feet = [PoseSolver.LF]
	var res := _result(barn, 0.6)
	for i in Tuning.TICK_HZ:
		rules._apply_fatigue(res, _attached(), false, true, 0.0)
	return 80.0 - rules.stamina[PoseSolver.LH]
