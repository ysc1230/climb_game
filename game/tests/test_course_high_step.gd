extends RefCounted
## 하이스텝 과정 C_HIGH_STEP(docs/28 §6·§6.1·§6.2): 튜토리얼을 실제 세션에 패드 입력을 넣어 "done"까지 보내고,
## 써먹기 홀드가 하이스텝 없이는 닿지 않는지, 문제 3개의 등급·필요 기술 기록을 확인한다.

var runner

const Driver := preload("res://tests/tutorial_driver.gd")
const STEP_MAX_TICKS := 600  # 행동 뒤 목표를 기다리는 최대 틱
const STAND_TICKS := 120     # 높은 발을 딛은 뒤 그 발 위로 일어서기를 기다리는 틱(안내 "기다리면 일어서요")
const P := "C_HIGH_STEP_T/"

## 단계별 패드 조작: [limb, hold] 끌어 놓기.
const SCRIPT := {
	"HS-A": [["RF", "F03/foot_1"]],
	"HS-B": [["LH", "H03/hand_1"]],
}


func _route(id := "C_HIGH_STEP_T") -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path(id))


func test_high_step_tutorial_file() -> void:
	var r := _route()
	runner.check(r.errors.is_empty(), "저작 오류 없음 %s" % [r.errors])
	runner.check(r.mode == "course" and r.course_id == "C_HIGH_STEP" and r.course_slot == "tutorial", "C_HIGH_STEP 튜토리얼")
	var ids := r.tutorial_steps.map(func(st): return str(st.step_id))
	runner.check(ids == SCRIPT.keys(), "단계 순서 %s" % [ids])
	for st in r.tutorial_steps:
		var help: Array = st.get("help_ko", [])
		runner.check(str(st.get("text_ko", "")) != "" and help.size() == 2, "%s 안내 한 문장·도움말 2단계" % st.step_id)
		runner.check(st.get("rules", {}).get("techniques", null) == [], "%s 기술 버튼 없음(패드 과정)" % st.step_id)
		runner.check(not (str(st.text_ko) + " ".join(help)).contains("버튼"), "%s 버튼 언급 없음" % st.step_id)


## 해 보기의 높은 발판은 시작 자세에서 고관절−0.20m 위(하이스텝)이고, 써먹기 홀드는 하이스텝 없이 닿지 않는다.
func test_high_step_tutorial_needs_high_step() -> void:
	var r := _route()
	var f03 := r.slot_pos(P + "F03/foot_1")
	var hip := PoseSolver.joint_position(r.start_pelvis, r.start_angle, PoseSolver.RF)
	runner.check(f03.y >= hip.y - Tuning.HIGH_STEP_BELOW_HIP, "F03이 하이스텝 높이 (%.3f, 고관절 %.3f)" % [f03.y, hip.y])
	var direct := SessionBot.run(r, [[&"LH", P + "H03/hand_1"]])
	runner.check(direct.failed_step == 0, "시작 자세에서 왼손이 H03에 닿지 않음: %s" % direct.failure)
	var no_hs := SessionBot.run(r, r.intended_moves, {&"high_step": true})
	runner.check(no_hs.failed_step == 0, "하이스텝을 금지하면 첫 이동에서 막힘: %s" % no_hs.failure)


## 패드 입력만으로 두 단계를 완료한다. 높은 발을 딛은 뒤 그 발 위로 일어서고, 실패·재시작이 없어야 한다.
func test_high_step_tutorial_reaches_done() -> void:
	var d := Driver.new(_route())
	for i in 30:
		d.tick()
	runner.check(d.results.is_empty(), "시작 대기 중 진행 없음 %s" % [d.results])
	var start_y: float = d.s.body.pos.y
	var steps: Array = d.t.steps
	for n in steps.size():
		var id := str(steps[n].step_id)
		runner.check(d.t.index == n, "%s 시작(index %d)" % [id, d.t.index])
		d.results.clear()
		d.labels.clear()
		if id == "HS-B":
			var y0: float = d.s.body.pos.y
			for i in STAND_TICKS:
				d.tick()
			runner.check(d.results.is_empty(), "일어서는 동안 진행 없음 %s" % [d.results])
			runner.check(d.s.body.pos.y > start_y + 0.10, "높은 발 위로 일어섬(골반 %.3f → %.3f, 시작 %.3f)" % [y0, d.s.body.pos.y, start_y])
		for a in SCRIPT[id]:
			runner.check(d.drag(StringName(a[0]), P + a[1]), "%s %s 끌어 놓기" % [id, a[0]])
		for k in STEP_MAX_TICKS:
			if not d.results.is_empty():
				break
			d.tick()
		if id == "HS-A":
			# 봇 끌기는 빨라 HighStep 라벨이 확정(6틱)되기 전에 놓으므로, 딛은 뒤 일어서기(StandUp)를 본다
			runner.check(d.labels.has(MoveClassifier.STAND_UP), "HS-A 뒤 StandUp 이벤트 %s" % [d.labels])
		var want := "done" if n == steps.size() - 1 else "next"
		runner.check(d.results == [want], "%s 완료 %s → %s(낙하 %d, 골반 %s)" % [id, want, d.results, d.s.falls, d.s.body.pos])
		if d.results != [want]:
			return
	runner.check(d.t.done, "튜토리얼 완료")


## 문제 3개(28 §6.2): 등급·칸·필요 기술·crux 기록, ContentCheck 통과, 등급 경고 없음, 쉬움 이동 6~10.
func test_high_step_problems_check() -> void:
	var want := {
		"C_HIGH_STEP_1": ["easy", "V1", [&"T_HIGH_STEP"]],
		"C_HIGH_STEP_2": ["normal", "V1", [&"T_HIGH_STEP"]],
		"C_HIGH_STEP_3": ["hard", "V2", [&"T_HIGH_STEP", &"T_CROSS"]],
	}
	for id in want:
		var r := _route(id)
		var w: Array = want[id]
		runner.check(r.course_id == "C_HIGH_STEP" and r.course_slot == w[0] and r.grade == w[1], "%s 칸·등급 %s %s" % [id, r.course_slot, r.grade])
		runner.check(Array(r.required_techniques) == w[2], "%s 필요 기술 %s" % [id, r.required_techniques])
		for t in r.required_techniques:
			runner.check(r.crux_steps.has(t), "%s crux %s" % [id, t])
		var res := ContentCheck.check(r)
		runner.check(res.ok, "%s 검사 통과:\n      %s" % [id, "\n      ".join(res.lines)])
		var warns := Array(res.lines).filter(func(l): return l.begins_with("경고:"))
		runner.check(warns.is_empty(), "%s 등급 경고 없음 %s" % [id, warns])
		if w[0] == "easy":
			runner.check(res.metrics.moves >= 6 and res.metrics.moves <= 10, "%s 이동 6~10 (%d)" % [id, res.metrics.moves])


## 보통: 오른발(#0)과 왼발(#4) 두 번, 각자 그 단계 직전 자세에서 목표가 고관절−0.20m 위다(좌우 교대 하이스텝).
func test_high_step_normal_twice_alternating() -> void:
	var r := _route("C_HIGH_STEP_2")
	runner.check(r.intended_moves[0][0] == PoseSolver.RF and r.intended_moves[4][0] == PoseSolver.LF, "#0 오른발, #4 왼발")
	for i in [0, 4]:
		var bot := SessionBot.run(r, r.intended_moves.slice(0, i))
		var b := bot.session.body
		var m: Array = r.intended_moves[i]
		var hip := PoseSolver.joint_position(b.pos, b.angle, m[0], b.yaw)
		var target := r.slot_pos(m[1])
		runner.check(target.y >= hip.y - Tuning.HIGH_STEP_BELOW_HIP, "#%d %s 목표 %.3f ≥ 고관절 %.3f − 0.20" % [i, m[0], target.y, hip.y])
