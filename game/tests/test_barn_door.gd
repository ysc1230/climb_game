extends RefCounted
## 04 §10.4 barn door 근사: 한 수직선에 몰린 접점, flag 효과, 바깥 엣지 용량, 넓은 접점 비적용.

var runner
const START := {&"LH": Vector2(-0.45, 1.80), &"RH": Vector2(0.45, 1.80), &"LF": Vector2(-0.30, 0.10), &"RF": Vector2(0.30, 0.10)}
const LINE := {&"LH": Vector2(-0.40, 1.75), &"LF": Vector2(-0.38, 0.35)}
const PELVIS := Vector2(0.20, 1.0)  # 힘 해가 FEASIBLE인 높이(이 테스트가 확인)


func _eval(rules: ClimbRules, eps: Dictionary, pelvis: Vector2 = PELVIS) -> Dictionary:
	rules.feet_eligible = [PoseSolver.LF]
	rules.loaded_feet = [PoseSolver.LF]
	return rules.evaluate(pelvis, 0.0, LINE, eps, false, rules.feet_eligible)


func test_vertical_line_contacts_barn_door() -> void:
	var rules := ClimbRules.new()
	var r := _eval(rules, {PoseSolver.RF: Vector2(0.20, 0.30), PoseSolver.RH: Vector2(0.20, 1.60)})
	runner.check(r.status == SupportSolver.Status.FEASIBLE, "힘 해 있음(barn door만 분리): status %d residual %.4f" % [r.status, r.residual])
	runner.check(r.barn.applies and r.barn.exceeded, "applies·exceeded: %s" % [r.barn])
	rules._apply_phase(r)
	runner.check(rules.phase == ClimbRules.Phase.REBALANCING, "phase == REBALANCING")
	runner.check(rules.imbalance_cause == &"BARN_DOOR", "cause == BARN_DOOR: %s" % rules.imbalance_cause)


func test_flag_reduces_tau() -> void:
	var rules := ClimbRules.new()
	# 골반을 선 가까이(x=-0.30)로 옮긴 같은 자세: flag(자유 발을 왼쪽으로)가 τ를 용량 아래로 내린다
	var near := Vector2(-0.30, 1.0)
	var base := _eval(rules, {PoseSolver.RF: Vector2(0.20, 0.30), PoseSolver.RH: Vector2(-0.30, 1.60)}, near)
	var flag := _eval(rules, {PoseSolver.RF: Vector2(-0.6, 0.5), PoseSolver.RH: Vector2(-0.30, 1.60)}, near)
	runner.check(base.barn.exceeded, "flag 전에는 exceeded: %s" % [base.barn])
	runner.check(flag.barn.applies and flag.barn.tau < base.barn.tau, "flag τ %.3f < %.3f" % [flag.barn.tau, base.barn.tau])
	runner.check(flag.status == SupportSolver.Status.FEASIBLE and not flag.barn.exceeded, "flag 후 exceeded 아님: %s" % [flag.barn])


func test_outside_edge_raises_capacity() -> void:
	var rules := ClimbRules.new()
	rules.contact_meta = {
		PoseSolver.LH: ContactInfo.make("h", LINE[PoseSolver.LH], 1.0, &"pull", &""),
		PoseSolver.LF: ContactInfo.make("f", LINE[PoseSolver.LF], 1.0, &"foot", &"outside"),
	}
	var r := _eval(rules, {PoseSolver.RF: Vector2(0.20, 0.30), PoseSolver.RH: Vector2(0.20, 1.60)})
	runner.check(r.barn.applies, "applies")
	runner.check(absf(r.barn.capacity - 0.15) < 1e-6, "capacity 0.10 + 0.05 = %.4f" % r.barn.capacity)
	rules.contact_meta[PoseSolver.LF].edge = &"toe"
	var r2 := _eval(rules, {PoseSolver.RF: Vector2(0.20, 0.30), PoseSolver.RH: Vector2(0.20, 1.60)})
	runner.check(absf(r2.barn.capacity - 0.09) < 1e-6, "toe는 0.04 + 0.05 = %.4f" % r2.barn.capacity)


func test_wide_contacts_no_barn_door() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(Vector2(0, 0.83))
	rules.reset(body, START, {}, false)
	runner.check(not rules.last.barn.applies, "R01 시작 자세는 적용 안 됨")
	runner.check(rules.imbalance_cause == &"", "cause 비어 있음")
