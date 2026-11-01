extends RefCounted
## 크로스 과정 C_CROSS(docs/28 §6·§6.1·§6.2): 튜토리얼을 실제 세션에 패드 입력을 넣어 "done"까지 보내고,
## 써먹기 홀드가 크로스 없이는(직접·손 바꿔 옮기기) 닿지 않는지, 문제 3개의 등급·필요 기술 기록과
## 크로스하지 않는 다른 순서가 실패하는지 확인한다.

var runner

const Driver := preload("res://tests/tutorial_driver.gd")
const STEP_MAX_TICKS := 600  # 행동 뒤 목표를 기다리는 최대 틱
const P := "C_CROSS_T/"

## 단계별 패드 조작: [limb, hold] 끌어 놓기.
const SCRIPT := {
	"CR-A": [["LH", "H03/hand_1"]],
	"CR-B": [["RH", "H04/hand_1"]],
}

## 문제별 크로스 없는 대안 순서: [막혀야 할 단계, 이동 목록]. 막히는 곳은 크로스 뒤에 잡아야 하는 먼 홀드다.
const _PRE2 := [["LH", "H03/hand_1"], ["RH", "H04/hand_1"], ["RF", "F03/foot_1"], ["LF", "F04/foot_1"], ["LH", "H05/hand_1"], ["RH", "H06/hand_1"]]
const UNCROSSED := {
	"C_CROSS_1": [
		[2, [["LH", "H03/hand_1"], ["RH", "H02/hand_1"], ["LH", "H04/hand_1"]]],
		[0, [["LH", "H04/hand_1"]]],
	],
	"C_CROSS_2": [
		[2, [["RH", "H03/hand_1"], ["LH", "H02/hand_1"], ["RH", "H04/hand_1"]]],
		[8, _PRE2 + [["LH", "H07/hand_1"], ["RH", "H05/hand_1"], ["LH", "H08/hand_1"]]],
		[6, _PRE2 + [["LH", "H08/hand_1"]]],
	],
	"C_CROSS_3": [
		[2, [["RH", "H03/hand_1"], ["LH", "H02/hand_1"], ["RH", "H04/hand_1"]]],
		[0, [["RH", "H04/hand_1"]]],
	],
}


func _route(id := "C_CROSS_T") -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path(id))


## 홀드 상대 키 목록 → SessionBot 단계([limb, "<id>/<hold>/<slot>"]).
static func _steps(id: String, moves: Array) -> Array:
	return moves.map(func(m): return [StringName(m[0]), id + "/" + m[1]])


func test_cross_tutorial_file() -> void:
	var r := _route()
	runner.check(r.errors.is_empty(), "저작 오류 없음 %s" % [r.errors])
	runner.check(r.mode == "course" and r.course_id == "C_CROSS" and r.course_slot == "tutorial", "C_CROSS 튜토리얼")
	var ids := r.tutorial_steps.map(func(st): return str(st.step_id))
	runner.check(ids == SCRIPT.keys(), "단계 순서 %s" % [ids])
	for st in r.tutorial_steps:
		var help: Array = st.get("help_ko", [])
		runner.check(str(st.get("text_ko", "")) != "" and help.size() == 2, "%s 안내 한 문장·도움말 2단계" % st.step_id)
		runner.check(st.get("rules", {}).get("techniques", null) == [], "%s 기술 버튼 없음(패드 과정)" % st.step_id)
		runner.check(not (str(st.text_ko) + " ".join(help)).contains("버튼"), "%s 버튼 언급 없음" % st.step_id)
	runner.check(ContentCheck.check(r).ok, "튜토리얼 의도 경로 완등")


## 해 보기 홀드는 오른손 너머(왼손 크로스)이고, 써먹기 홀드는 왼손이 건너가 버틸 때만 닿는다:
## 시작 자세에서 오른손으로 직접, 손을 바꿔 옮기는 순서(오른손 H03 → 왼손 H02 → 오른손 H04)로는 닿지 않는다.
func test_cross_tutorial_needs_cross() -> void:
	var r := _route()
	var h03: Dictionary = r.slots[P + "H03/hand_1"]
	runner.check(r.slot_pos(P + "H03/hand_1").x - float(h03.hand_area.half_width) > r.slot_pos(P + "H02/hand_1").x,
		"H03 가장자리까지 시작 오른손 홀드 H02보다 오른쪽")
	var crossed := SessionBot.run(r, [[&"LH", P + "H03/hand_1"], [&"RH", P + "H04/hand_1"]])
	runner.check(crossed.failed_step == -1 and crossed.session.falls == 0, "크로스 두 단계 성공: %s" % crossed.failure)
	var rh := SessionBot.run(r, [[&"RH", P + "H04/hand_1"]])
	runner.check(rh.failed_step == 0, "시작 자세에서 오른손이 H04에 닿지 않음: %s" % rh.failure)
	var shuffle := SessionBot.run(r, [[&"RH", P + "H03/hand_1"], [&"LH", P + "H02/hand_1"], [&"RH", P + "H04/hand_1"]])
	runner.check(shuffle.failed_step == 2, "크로스 없이 손 바꿔 옮기면 H04(#2)에서 막힘: #%d %s" % [shuffle.failed_step, shuffle.failure])
	var no_cross := SessionBot.run(r, r.intended_moves, {&"cross": true})
	runner.check(no_cross.failed_step == 0, "크로스를 금지하면 첫 이동에서 막힘: %s" % no_cross.failure)


## 패드 입력만으로 두 단계를 완료한다. 해 보기에서 손 교차(CrossReach) 이벤트가 나고, 실패·재시작이 없어야 한다.
func test_cross_tutorial_reaches_done() -> void:
	var d := Driver.new(_route())
	for i in 30:
		d.tick()
	runner.check(d.results.is_empty(), "시작 대기 중 진행 없음 %s" % [d.results])
	var steps: Array = d.t.steps
	for n in steps.size():
		var id := str(steps[n].step_id)
		runner.check(d.t.index == n, "%s 시작(index %d)" % [id, d.t.index])
		d.results.clear()
		d.labels.clear()
		for a in SCRIPT[id]:
			runner.check(d.drag(StringName(a[0]), P + a[1]), "%s %s 끌어 놓기" % [id, a[0]])
		for k in STEP_MAX_TICKS:
			if not d.results.is_empty():
				break
			d.tick()
		if id == "CR-A":
			runner.check(d.labels.has(MoveClassifier.CROSS_REACH), "CR-A에서 CrossReach 이벤트 %s" % [d.labels])
		var want := "done" if n == steps.size() - 1 else "next"
		runner.check(d.results == [want], "%s 완료 %s → %s(낙하 %d, 골반 %s)" % [id, want, d.results, d.s.falls, d.s.body.pos])
		if d.results != [want]:
			return
	runner.check(d.t.done, "튜토리얼 완료")


## 문제 3개(28 §6.2): 등급·칸·필요 기술·crux 기록, ContentCheck 통과, 등급 경고 없음, 쉬움 이동 6~10.
func test_cross_problems_check() -> void:
	var want := {
		"C_CROSS_1": ["easy", "V1", [&"T_CROSS"]],
		"C_CROSS_2": ["normal", "V1", [&"T_CROSS"]],
		"C_CROSS_3": ["hard", "V2", [&"T_CROSS", &"T_HIGH_STEP"]],
	}
	for id in want:
		var r := _route(id)
		var w: Array = want[id]
		runner.check(r.course_id == "C_CROSS" and r.course_slot == w[0] and r.grade == w[1], "%s 칸·등급 %s %s" % [id, r.course_slot, r.grade])
		runner.check(Array(r.required_techniques) == w[2], "%s 필요 기술 %s" % [id, r.required_techniques])
		for t in r.required_techniques:
			runner.check(r.crux_steps.has(t), "%s crux %s" % [id, t])
		var res := ContentCheck.check(r)
		runner.check(res.ok, "%s 검사 통과:\n      %s" % [id, "\n      ".join(res.lines)])
		var warns := Array(res.lines).filter(func(l): return l.begins_with("경고:"))
		runner.check(warns.is_empty(), "%s 등급 경고 없음 %s" % [id, warns])
		if w[0] == "easy" and not res.metrics.is_empty():
			runner.check(res.metrics.moves >= 6 and res.metrics.moves <= 10, "%s 이동 6~10 (%d)" % [id, res.metrics.moves])


## crux 크로스 단계는 목표가 반대 손 홀드 X 너머다. 보통은 왼손·오른손 크로스가 한 번씩 있다(좌우 교대).
func test_cross_crux_steps_are_crosses() -> void:
	for id in ["C_CROSS_1", "C_CROSS_2", "C_CROSS_3"]:
		var r := _route(id)
		var crosses := _cross_steps(r)
		runner.check(crosses.has(int(r.crux_steps.get(&"T_CROSS", -1))), "%s crux #%d가 크로스 %s" % [id, r.crux_steps.get(&"T_CROSS", -1), crosses])
	var n := _route("C_CROSS_2")
	var limbs := _cross_steps(n).map(func(i): return n.intended_moves[i][0])
	runner.check(limbs.size() >= 2 and limbs.has(PoseSolver.LH) and limbs.has(PoseSolver.RH), "보통: 크로스 2회 이상·양손 %s" % [limbs])


## 의도 경로에서 손 목표가 그때 잡고 있는 반대 손 홀드 X를 넘는 단계 인덱스.
func _cross_steps(r: RouteDef) -> Array:
	var out := []
	if not r.errors.is_empty():
		return out
	var held := {PoseSolver.LH: r.start_slots[PoseSolver.LH], PoseSolver.RH: r.start_slots[PoseSolver.RH]}
	for i in r.intended_moves.size():
		var m: Array = r.intended_moves[i]
		var limb := StringName(m[0])
		if not PoseSolver.is_hand(limb):
			continue
		var key := str(m[1])
		var other := PoseSolver.RH if limb == PoseSolver.LH else PoseSolver.LH
		var ox := r.slot_pos(held[other]).x
		var x := r.slot_pos(key).x
		if (limb == PoseSolver.LH and x > ox) or (limb == PoseSolver.RH and x < ox):
			out.append(i)
		held[limb] = key
	return out


## 크로스하지 않는 다른 순서(먼저 반대 손을 옮기고 빈 홀드를 이어 잡기, 또는 먼 홀드를 바로 잡기)는 크로스 뒤 먼 홀드에서 막힌다.
func test_cross_uncrossed_alternatives_fail() -> void:
	for id in UNCROSSED:
		var r := _route(id)
		for alt in UNCROSSED[id]:
			var bot := SessionBot.run(r, _steps(id, alt[1]))
			runner.check(bot.failed_step == alt[0], "%s 크로스 없는 순서가 #%d에서 막힘: #%d %s" % [id, alt[0], bot.failed_step, bot.failure])
