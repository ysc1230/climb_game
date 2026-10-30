extends RefCounted
## docs/25 무브·피드백(MC06/MC08/MC10/MC11, T02-C, 거부 사유). 헤드리스 시뮬레이션.

var runner
const START := {&"LH": Vector2(-0.45, 1.80), &"RH": Vector2(0.45, 1.80), &"LF": Vector2(-0.30, 0.10), &"RF": Vector2(0.30, 0.10)}


func _settle(rules: ClimbRules, body: BodyState, att: Dictionary, ticks: int, intents := {}, endpoints := {}, hints := {}, probe := []) -> String:
	for i in ticks:
		var out := rules.tick(body, att, endpoints, false, not intents.is_empty(), intents, hints, probe)
		if not out.is_empty():
			return out
	return ""


func _route() -> RouteDef:
	return RouteDef.load_json("res://data/routes/R01.json")


## MC06·T02-C: 발이 낮으면 먼 손홀드(H05)에 닿지 않는다 → 두 발을 높이고 체중을 실으면 골반이 오르고 닿는다
func test_mc06_high_step_then_stand_up_enables_reach() -> void:
	var r := _route()
	var rules := ClimbRules.new()
	var body := BodyState.new(r.start_pelvis)
	var att := START.duplicate()
	rules.reset(body, att, {}, false)
	_settle(rules, body, att, 120)
	var h05 := r.slot_pos("R01/H05/hand_1")
	var before := body.pos.y
	runner.check(not PoseSolver.can_reach(body.pos, body.angle, &"LH", h05), "발이 낮을 때 H05 불가")
	var rest := att.duplicate()
	rest.erase(&"LH")
	var reason := GripCheck.reject_reason(r.slots, &"LH", att[&"LH"], h05, body.pos, body.angle, rest, {}, rules.feet_eligible)
	runner.check(reason in [GripCheck.OUT_OF_REACH, GripCheck.NEED_WEIGHT_SHIFT], "거부 사유 %s" % reason)
	# 두 발을 차례로 높은 발판(F03/F04)으로: 드래그 중 HighStep, 놓은 뒤 체중을 실어 일어섬
	for foot in [&"LF", &"RF"]:
		var key := "R01/F03/foot_1" if foot == &"LF" else "R01/F04/foot_1"
		var target := r.slot_pos(key)
		var less := att.duplicate()
		less.erase(foot)
		var with_new := less.duplicate()
		with_new[foot] = target
		var ok := false
		var label: StringName = &""
		for i in 180:  # 플레이어처럼 몸이 옮겨가 발이 닿을 때까지 드래그 유지(25 Shift → Reach)
			rules.tick(body, less, {foot: target}, false, true, {foot: target})
			if label == &"":
				label = rules.moves.limb_labels.get(foot, &"")
			if PoseSolver.can_reach(body.pos, body.angle, foot, target) and PoseSolver.is_valid(body.pos, body.angle, with_new):
				ok = true
				break
		# 첫 발은 HighStep. 일어선 뒤 두 번째 발은 고관절이 올라가 문턱(고관절−0.20) 아래면 Reach가 맞다
		runner.check(label == MoveClassifier.HIGH_STEP or (foot == &"RF" and label == MoveClassifier.REACH), "%s 라벨 %s" % [foot, label])
		runner.check(ok, "%s 높은 발판 접촉 가능" % foot)
		att = with_new
		_settle(rules, body, att, 180)
	runner.check(body.pos.y - before >= 0.15, "골반 상승 %.3fm ≥ 0.15(T02-C tutorial_body_rise)" % (body.pos.y - before))
	# 의도 목표를 주면 몸이 옮겨가며 닿는다(Shift → Reach)
	var no_lh := att.duplicate()
	no_lh.erase(&"LH")
	var reached := false
	for i in 240:
		rules.tick(body, no_lh, {&"LH": att[&"LH"]}, false, true, {&"LH": h05})
		if PoseSolver.can_reach(body.pos, body.angle, &"LH", h05):
			reached = true
			break
	runner.check(reached, "발을 높인 뒤 H05 도달, 골반 (%.2f, %.2f)" % [body.pos.x, body.pos.y])


## 활성 말단의 의도 목표가 몸통을 그쪽으로 옮긴다(docs/04 §5 조작 목표 오차)
func test_intent_shifts_body_toward_target() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(Vector2(0, 0.744))
	rules.reset(body, START, {}, false)
	_settle(rules, body, START, 120)
	var x0 := body.pos.x
	var three := START.duplicate()
	three.erase(&"RH")
	_settle(rules, body, three, 60, {&"RH": Vector2(0.95, 1.9)}, {&"RH": START[&"RH"]})
	runner.check(body.pos.x - x0 > 0.05, "오른쪽 목표로 골반 이동 %.3fm" % (body.pos.x - x0))


## MC10·MC11·라벨: 교차, 양손 모으기, 발 바꾸기
func test_labels_cross_match_swap() -> void:
	var c := MoveClassifier.new()
	var p := Vector2(0, 0.9)
	var att := {&"RH": START[&"RH"], &"LF": START[&"LF"], &"RF": START[&"RF"]}
	c.update(p, 0, att, {&"LH": Vector2(0.6, 1.9)}, {&"LH": START[&"LH"]}, {})
	runner.check(c.label == MoveClassifier.CROSS_REACH, "왼손이 오른손 X를 넘으면 CrossReach, 실제 %s" % c.label)
	var c2 := MoveClassifier.new()
	c2.update(p, 0, att, {&"LH": Vector2(0.3, 1.8)}, {&"LH": START[&"LH"]}, {&"LH": MoveClassifier.HAND_MATCH})
	runner.check(c2.label == MoveClassifier.HAND_MATCH, "HandMatch 단서 우선, 실제 %s" % c2.label)
	var c3 := MoveClassifier.new()
	var att3 := {&"LH": START[&"LH"], &"RH": START[&"RH"], &"RF": START[&"RF"]}
	c3.update(p, 0, att3, {&"LF": START[&"RF"]}, {&"LF": START[&"LF"]}, {&"LF": MoveClassifier.FOOT_SWAP})
	runner.check(c3.label == MoveClassifier.FOOT_SWAP, "FootSwap, 실제 %s" % c3.label)


## 같은 구성에서 라벨이 바뀌면 6틱 확인 후 전환
func test_label_switch_needs_confirm_ticks() -> void:
	var c := MoveClassifier.new()
	var p := Vector2(0, 0.9)
	var att := {&"RH": START[&"RH"], &"LF": START[&"LF"], &"RF": START[&"RF"]}
	c.update(p, 0, att, {&"LH": Vector2(-0.5, 2.0)}, {&"LH": START[&"LH"]}, {})
	var first := c.label
	for i in 5:
		c.update(p, 0, att, {&"LH": Vector2(0.6, 1.9)}, {}, {})
	runner.check(c.label == first, "5틱까지 유지 %s" % c.label)
	c.update(p, 0, att, {&"LH": Vector2(0.6, 1.9)}, {}, {})
	runner.check(c.label == MoveClassifier.CROSS_REACH, "6틱째 전환, 실제 %s" % c.label)


## MC08: 같은 쪽 손·발(왼손+왼발)만 지지하고 몸이 그 오른쪽으로 벗어나 있으면, 자유 오른발을 지지선 쪽(왼쪽)으로
## 두는 것이 무게중심을 지지 위로 옮겨 손 하중을 줄인다 → Flag 후보. 반대(오른쪽 멀리)는 후보가 아니다.
## 이 게임의 지지 계산은 벽면 내 근사라 벽 밖 회전(barn door)을 막는 flag 효과는 모델에 없다(docs/04 §1).
func test_mc08_flag_improves_balance() -> void:
	var att := {&"LH": Vector2(-0.40, 1.75), &"LF": Vector2(-0.35, 0.35)}
	var body := BodyState.new(Vector2(0.25, 1.00))  # 몸이 왼쪽 지지선에서 오른쪽으로 벗어남
	var free_rh := body.pos + Vector2(0.35, 0.18)
	var results := {}
	for name in ["inside", "outside"]:
		var rules := ClimbRules.new()
		var b := BodyState.new(body.pos)
		var foot := b.pos + (Vector2(-0.60, -0.50) if name == "inside" else Vector2(0.70, -0.50))
		rules.reset(b, att, {&"RH": free_rh, &"RF": foot}, false)
		rules.tick(b, att, {&"RH": free_rh, &"RF": foot}, false, true, {&"RF": foot}, {}, [&"RF"])
		results[name] = [rules.flag_ready.has(&"RF"), rules.moves.limb_labels.get(&"RF", &"")]
	runner.check(results.inside[0], "지지선 쪽 자유 발은 균형 발 후보 %s" % [results.inside])
	runner.check(results.inside[1] == MoveClassifier.FLAG, "라벨 Flag, 실제 %s" % results.inside[1])
	runner.check(not results.outside[0], "반대쪽 멀리 둔 발은 후보 아님 %s" % [results.outside])


## 거부 사유: 종류 불일치, 점유, 관절 방향 한계
func test_reject_reasons() -> void:
	var r := _route()
	var body := BodyState.new(r.start_pelvis)
	var att := START.duplicate()
	att.erase(&"LH")
	var occ := {"R01/H02/hand_1": &"RH", "R01/F01/foot_1": &"LF", "R01/F02/foot_1": &"RF"}
	var f01 := r.slot_pos("R01/F01/foot_1")
	runner.check(GripCheck.reject_reason(r.slots, &"LH", f01, f01, body.pos, 0, att, occ, [&"LF", &"RF"]) == GripCheck.TYPE_MISMATCH, "손이 발판을 노림")
	var h02 := r.slot_pos("R01/H02/hand_1")
	runner.check(GripCheck.reject_reason(r.slots, &"LH", h02, h02, body.pos, 0, att, occ, [&"LF", &"RF"]) == GripCheck.OCCUPIED, "오른손 점유 슬롯")
	runner.check(GripCheck.message(GripCheck.TYPE_MISMATCH, &"LH") == "손으로 잡는 홀드가 아니에요", "문구")
