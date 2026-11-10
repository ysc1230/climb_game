extends RefCounted
## ClimbRules: 지지 상태·불균형 예산·무지지 유예·하중 발·회복(docs/04 §4·§7, docs/15). 헤드리스.

var runner
const START := {&"LH": Vector2(-0.45, 1.80), &"RH": Vector2(0.45, 1.80), &"LF": Vector2(-0.30, 0.10), &"RF": Vector2(0.30, 0.10)}


func _run(rules: ClimbRules, body: BodyState, attached: Dictionary, ticks: int, endpoints := {}) -> String:
	for i in ticks:
		var out := rules.tick(body, attached, endpoints, false, false)
		if not out.is_empty():
			return "%s@%d" % [out, i + 1]
	return ""


func test_four_point_start_is_stable_and_recovers_after_confirm() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(Vector2(0, 0.83))
	rules.reset(body, START, {}, false)
	rules.stamina[&"LH"] = 50.0
	runner.check(_run(rules, body, START, 120).is_empty(), "네 점은 실패 없음")
	runner.check(rules.phase == ClimbRules.Phase.STABLE, "Stable, 실제 %s" % rules.phase_name())
	runner.check(rules.loaded_feet.size() == 2, "두 발 Loaded")
	runner.check(rules.stamina[&"LH"] > 50.0, "안정 정지 후 회복")


func test_offset_single_hand_loses_balance_after_budget() -> void:
	# 손 하나가 옆으로 크게 벗어나 있고 발 없음 → Rebalancing, 18틱 안에 못 맞추면 BALANCE_LOST
	var rules := ClimbRules.new()
	var hand := {&"LH": Vector2(-1.0, 1.85)}
	var body := BodyState.new(Vector2(0.0, 1.0))
	rules.reset(body, hand, {}, false)
	var out := _run(rules, body, hand, 40)
	runner.check(out == "BALANCE_LOST@18", "18번째 틱에 균형 상실, 실제 %s" % out)


func test_small_offset_single_hand_rebalances_in_time() -> void:
	# 04 초깃값(18틱 예산, 골반 gain 40/damping 12, 잔차 0.02)에서는 무게중심이 손 아래에서
	# 약 5cm 이내로 어긋난 경우만 몸 정렬로 회복한다(측정값, docs/23). 그보다 크면 재잡기가 필요.
	for case in [[0.05, true], [0.20, false]]:
		var rules := ClimbRules.new()
		var hand := {&"LH": Vector2(-0.35, 1.85)}
		var body := BodyState.new(Vector2(-0.35, 1.20))
		var com := SupportSolver.com_proxy(body.pos, 0, hand)
		body.pos.x += (-0.35 + case[0]) - com.x
		rules.reset(body, hand, {}, false)
		var out := _run(rules, body, hand, 60)
		if case[1]:
			runner.check(out.is_empty(), "COM %.2fm 어긋남은 회복, 실제 %s" % [case[0], out])
		else:
			runner.check(out == "BALANCE_LOST@18", "COM %.2fm 어긋남은 18틱 후 균형 상실, 실제 %s" % [case[0], out])


func test_grace_nine_ticks_without_hands() -> void:
	var rules := ClimbRules.new()
	var feet := {&"LF": START[&"LF"], &"RF": START[&"RF"]}
	var body := BodyState.new(Vector2(0, 0.83))
	rules.reset(body, START, {}, false)
	var out := _run(rules, body, feet, 30)
	runner.check(out == "NO_SUPPORT@9", "무지지 9틱 후 실패, 실제 %s" % out)


func test_mc07_high_foot_attached_but_not_loaded() -> void:
	# 발을 고관절보다 높이 올림: Attached지만 Loaded 아님(피로 발 수에 안 셈)
	var rules := ClimbRules.new()
	var att := START.duplicate()
	att[&"LF"] = Vector2(-0.35, 1.0)
	var body := BodyState.new(Vector2(0, 0.83))
	rules.reset(body, att, {}, false)
	_run(rules, body, att, 30)
	runner.check(not rules.loaded_feet.has(&"LF"), "높은 발은 Unloaded, loaded=%s" % [rules.loaded_feet])


func test_mc14_regrab_on_last_grace_tick_counts() -> void:
	# 무지지 8틱 뒤 9번째 틱에 손을 잡으면 같은 틱에 지지가 먼저 성립 → 무지지 실패 없음
	var rules := ClimbRules.new()
	var body := BodyState.new(Vector2(0, 0.83))
	rules.reset(body, START, {}, false)
	var feet := {&"LF": START[&"LF"], &"RF": START[&"RF"]}
	runner.check(_run(rules, body, feet, 8).is_empty(), "8틱까지는 유예")
	var out := rules.tick(body, START, {}, false, false)
	runner.check(out.is_empty(), "9번째 틱 재잡기로 지지 회복, 실제 %s" % out)
	runner.check(rules.unsupported_ticks == 0, "무지지 카운트 0")
	# 2026-11-10: 지지 없음(GRACE) 동안에는 불균형 예산을 쓰지 않는다(두 손을 놓으면 1.5초 뒤 떨어진다는 사용자 규칙과 맞춤)
	runner.check(rules.imbalance_ticks == 0, "무지지 동안 불균형 예산은 쓰지 않음 (%d)" % rules.imbalance_ticks)
	_run(rules, body, START, 6)
	runner.check(rules.imbalance_ticks == 0 and rules.balance_confirmed(), "6틱 확인 후 균형 확인")


func test_slipped_hand_is_reported() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(Vector2(0, 0.83))
	rules.reset(body, START, {}, false)
	rules.stamina[&"LH"] = 0.01
	rules.tick(body, {&"LH": START[&"LH"]}, {}, false, false)  # 한 손만: 무거운 하중으로 소진
	runner.check(rules.slipped.has(&"LH"), "피로 0 손은 slipped")


func _meta(q: float, mode: StringName = &"pull") -> ContactInfo:
	return ContactInfo.make("k", Vector2.ZERO, q, mode, &"")


func test_low_quality_tires_faster() -> void:
	var drops := []
	for q in [1.0, 0.25]:
		var rules := ClimbRules.new()
		var body := BodyState.new(Vector2(0, 0.83))
		rules.contact_meta = {&"LH": _meta(q)}
		rules.reset(body, START, {}, false)
		rules.stamina[&"LH"] = 50.0
		rules.tick(body, START, {}, false, false)
		drops.append(50.0 - rules.stamina[&"LH"])
	runner.check(drops[0] > 0.0, "q=1 손은 감소 %.4f" % drops[0])
	var ratio: float = drops[1] / drops[0]
	runner.check(absf(ratio - (1.0 + 0.5 * 0.75)) < 0.014, "q=0.25 감소 비율 %.3f ≈ 1.375" % ratio)


func test_undercling_below_shoulder_eligible_with_loaded_foot() -> void:
	var rules := ClimbRules.new()
	var shoulder := PoseSolver.joint_position(Vector2(0, 0.83), 0, PoseSolver.LH)
	var att := {&"LH": shoulder + Vector2(0.0, -0.3), &"LF": Vector2(-0.2, 0.1)}
	rules.contact_meta = {&"LH": _meta(1.0, &"undercling")}
	var feet: Array = [&"LF"]
	rules.loaded_feet = [&"LF"]
	var with_foot := rules.contacts_for(Vector2(0, 0.83), 0, att, feet)
	runner.check(with_foot.any(func(c): return c.limb == &"LH"), "하중 발 1개면 언더클링 손 포함")
	rules.loaded_feet = []
	var without := rules.contacts_for(Vector2(0, 0.83), 0, att, feet)
	runner.check(not without.any(func(c): return c.limb == &"LH"), "하중 발 0이면 제외")
	rules.contact_meta = {}
	rules.loaded_feet = [&"LF"]
	runner.check(not rules.contacts_for(Vector2(0, 0.83), 0, att, feet).any(func(c): return c.limb == &"LH"), "pull이면 어깨 아래 손은 제외")
