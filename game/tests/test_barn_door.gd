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


const FREE := {PoseSolver.RF: Vector2(0.20, 0.30), PoseSolver.RH: Vector2(0.20, 1.60)}


func _excess(rules: ClimbRules) -> float:
	return rules.last.barn.tau - rules.last.barn.capacity


## 안정 자세에서 barn door를 만드는 후보는 _accept가 거부하고, 틱을 돌려도 barn door가 생기지 않는다.
func test_accept_rejects_move_creating_barn_door() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(Vector2(-0.30, 1.0))
	rules.reset(body, LINE, FREE, false)
	for i in 30:
		rules.tick(body, LINE, FREE, false, false)
	runner.check(rules.phase == ClimbRules.Phase.STABLE and rules.imbalance_cause == &"", "전제: 안정 %s/%s" % [rules.phase_name(), rules.imbalance_cause])
	runner.check(not rules.last.barn.exceeded, "전제: barn door 아님")
	runner.check(rules._ctx_prev_feasible and not rules._ctx_prev_barn, "전제: 직전 안정")
	runner.check(not rules._accept(Vector2(0.20, 1.0), 0.0), "barn door를 만드는 후보 거부")
	runner.check(rules._accept(body.pos, body.angle), "현재 자세는 허용")
	var start_x := body.pos.x
	for i in 20:
		rules.tick(body, LINE, FREE, false, false)
		runner.check(rules.imbalance_cause != &"BARN_DOOR", "틱 %d barn door 없음" % i)
	runner.check(absf(body.pos.x - start_x) < 0.15, "몸이 선에서 멀어지지 않음: %.3f → %.3f" % [start_x, body.pos.x])


## barn door 재균형: 초과분이 늘지 않고, 몸이 선 쪽으로 가서 용량 안이 되면 원인이 비워진다.
func test_barn_rebalance_recovers_and_clears_cause() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(Vector2(-0.30, 1.0))
	rules.reset(body, LINE, FREE, false)
	runner.check(rules.imbalance_cause == &"BARN_DOOR", "시작 원인 BARN_DOOR")
	var prev := _excess(rules)
	for i in 30:
		var out := rules.tick(body, LINE, FREE, false, false)
		runner.check(out.is_empty(), "틱 %d 실패 없음: %s" % [i, out])
		var ex := _excess(rules)
		runner.check(ex <= prev + ClimbRules.ACCEPT_EPSILON + 1e-6, "틱 %d 초과분 비증가 %.4f ≤ %.4f" % [i, ex, prev])
		prev = ex
	runner.check(rules.phase == ClimbRules.Phase.STABLE and rules.imbalance_cause == &"", "회복 뒤 안정·원인 비움: %s/%s" % [rules.phase_name(), rules.imbalance_cause])


## 18틱 안에 고치지 못하면 BALANCE_LOST이고 원인은 BARN_DOOR로 남는다.
func test_barn_unrecoverable_balance_lost() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(PELVIS)
	rules.reset(body, LINE, FREE, false)
	var prev := _excess(rules)
	var lost := ""
	var ticks := 0
	while lost.is_empty() and ticks < 40:
		lost = rules.tick(body, LINE, FREE, false, false)
		ticks += 1
		var ex := _excess(rules)
		runner.check(ex <= prev + ClimbRules.ACCEPT_EPSILON + 1e-6, "틱 %d 초과분 비증가" % ticks)
		prev = ex
	runner.check(lost == "BALANCE_LOST" and ticks == ClimbRules.IMBALANCE_BUDGET_TICKS, "%d틱에 %s" % [ticks, lost])
	runner.check(rules.imbalance_cause == &"BARN_DOOR", "원인 BARN_DOOR: %s" % rules.imbalance_cause)


func test_cause_cleared_on_grace() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(PELVIS)
	rules.reset(body, LINE, FREE, false)
	runner.check(rules.imbalance_cause == &"BARN_DOOR", "전제: BARN_DOOR")
	var feet_only := {PoseSolver.LF: LINE[PoseSolver.LF]}
	rules.tick(body, feet_only, FREE, false, false)
	runner.check(rules.phase == ClimbRules.Phase.GRACE, "손 없으면 Grace: %s" % rules.phase_name())
	runner.check(rules.imbalance_cause == &"", "Grace 진입 시 원인 비움: %s" % rules.imbalance_cause)
