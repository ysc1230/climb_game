extends RefCounted
## 기술 탭 튜토리얼(docs/16 v0.7 "기술 탭 튜토리얼(재구성)"): 다리 내리기 + 먼 손 뻗기 C_DROP_FOOT_T, 핸드매치 C_MATCH_T,
## 크로스 C_CROSS_T 문구. 실제 세션에 패드 입력을 넣어 모든 단계가 "next"(마지막은 "done") 한 번씩으로
## 끝나는지, 써먹기 홀드가 그 기술 없이는 닿지 않고 기술을 쓰면 닿는지(SessionBot) 확인한다.

var runner

const Driver := preload("res://tests/tutorial_driver.gd")
const STEP_MAX_TICKS := 600  # 행동 뒤 목표를 기다리는 최대 틱
const WAIT := 60  # 발을 내린 뒤 먼 손을 뻗기 전 기다리는 틱(1초). 몸이 옮겨 가는 데 0.7~0.8초 걸린다(40틱이면 아직 못 닿음, 50틱이면 닿음)

## 과정 → [튜토리얼, 단계 순서]
const COURSES := {
	"C_DROP_FOOT": ["C_DROP_FOOT_T", ["DF1", "DF2", "DF3", "DF4"]],
	"C_MATCH": ["C_MATCH_T", ["M1", "M2", "M3", "M4"]],
}

## 단계별 패드 조작: ["drag", limb, hold] 끌어 놓기,
## ["wait", ticks] 아무것도 하지 않고 기다리기(안내를 읽는 동안 몸이 자리 잡음).
const SCRIPTS := {
	"C_DROP_FOOT_T": {
		"DF1": [["drag", "LF", "F03/foot_1"]],
		"DF2": [["wait", WAIT], ["drag", "RH", "H03/hand_1"]],
		"DF3": [["drag", "RF", "F06/foot_1"]],
		"DF4": [["wait", WAIT], ["drag", "LH", "H04/hand_1"]],
	},
	"C_MATCH_T": {
		"M1": [["drag", "RH", "W01/hand_1"]],
		"M2": [["drag", "LH", "H02/hand_1"]],
		"M3": [["drag", "LH", "W01/hand_1"]],
		"M4": [["drag", "RH", "H04/hand_1"]],
	},
}


func _route(id: String) -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path(id))


## 단계의 start_pose를 문제 시작 자세로 삼은 루트(거울 단계의 SessionBot 재생용).
func _from_step(id: String, step_id: String) -> RouteDef:
	var r := _route(id)
	for st in r.tutorial_steps:
		if str(st.step_id) == step_id:
			var sp: Dictionary = st.start_pose
			r.start_pelvis = Vector2(sp.pelvis[0], sp.pelvis[1])
			r.start_angle = float(sp.angle)
			r.start_slots = {}
			for limb in sp.slots:
				r.start_slots[StringName(limb)] = sp.slots[limb]
	return r


## 홀드 상대 키 목록 → SessionBot 단계. [limb, hold].
static func _steps(id: String, moves: Array) -> Array:
	return moves.map(func(m): return [StringName(m[0]), id + "/" + m[1]] + m.slice(2))


func test_tech_tutorial_files() -> void:
	for cid in COURSES:
		var rid: String = COURSES[cid][0]
		var r := _route(rid)
		runner.check(r.errors.is_empty(), "%s 저작 오류 없음 %s" % [rid, r.errors])
		runner.check(r.route_id == rid and r.mode == "course" and r.course_id == cid and r.course_slot == "tutorial" and r.grade == "V0", "%s: %s 튜토리얼 V0" % [rid, cid])
		var ids := r.tutorial_steps.map(func(st): return str(st.step_id))
		runner.check(ids == COURSES[cid][1], "%s 단계 순서 %s" % [rid, ids])
		for st in r.tutorial_steps:
			var help: Array = st.get("help_ko", [])
			runner.check(str(st.get("text_ko", "")) != "" and help.size() == 2, "%s 안내·도움말 2단계" % st.step_id)
			runner.check(st.get("rules", {}).get("techniques", null) == [], "%s 기술 버튼 없음(패드 과정)" % st.step_id)
			runner.check(st.get("rules", {}).get("fatigue_drain", null) == false, "%s 피로 감소 끔" % st.step_id)
			runner.check(not (str(st.text_ko) + " ".join(help)).contains("버튼"), "%s 버튼 언급 없음" % st.step_id)
			runner.check(PlayAttempt.goal_slot(st, r) != "", "%s 반짝일 홀드 있음" % st.step_id)
		var res := ContentCheck.check(r)
		runner.check(res.ok, "%s 의도 경로 SessionBot 완등:\n      %s" % [rid, "\n      ".join(res.lines)])


## 핸드매치 넓은 홀드는 반폭 0.16 이상(두 손이 넉넉히 들어감, 16 C_MATCH_T).
func test_match_wide_hold() -> void:
	var r := _route("C_MATCH_T")
	runner.check(float(r.slots["C_MATCH_T/W01/hand_1"].hand_area.half_width) >= 0.16, "W01 반폭 ≥ 0.16")


## 크로스 튜토리얼은 배치를 그대로 두고 안내 문구만 16 v0.7 말투로 바꿨다.
func test_cross_tutorial_texts() -> void:
	var r := _route("C_CROSS_T")
	var texts := {}
	for st in r.tutorial_steps:
		texts[str(st.step_id)] = str(st.text_ko)
	runner.check(texts == {"CR-A": "왼손을 오른손 너머 홀드로 교차해 잡아요.", "CR-B": "오른손을 오른쪽 먼 홀드로 옮겨요."}, "크로스 문구 %s" % [texts])


## 다리 내리기: 높은 발을 내리지 않으면 먼 손이 닿지 않고(DF2·DF4 #0에서 막힘), 내리면 닿는다.
## 반대쪽 낮지 않은 발판(F05·F02, 0.20만 낮음)이나 반대 발을 내리는 것으로는 닿지 않는다.
func test_drop_foot_needed() -> void:
	var cases := [
		[_route("C_DROP_FOOT_T"), [["LF", "F03/foot_1"], ["RH", "H03/hand_1"]], [["RH", "H03/hand_1"]], [["LF", "F05/foot_1"], ["RH", "H03/hand_1"]], "DF2"],
		[_from_step("C_DROP_FOOT_T", "DF3"), [["RF", "F06/foot_1"], ["LH", "H04/hand_1"]], [["LH", "H04/hand_1"]], [["RF", "F02/foot_1"], ["LH", "H04/hand_1"]], "DF4"],
	]
	for c in cases:
		var r: RouteDef = c[0]
		var lowered := SessionBot.run(r, _steps("C_DROP_FOOT_T", c[1]))
		runner.check(lowered.failed_step == -1 and lowered.session.falls == 0, "%s: 발을 내리면 먼 홀드에 닿음 %s" % [c[4], lowered.failure])
		var high := SessionBot.run(r, _steps("C_DROP_FOOT_T", c[2]))
		runner.check(high.failed_step == 0, "%s: 발을 내리지 않으면 #0에서 막힘 #%d %s" % [c[4], high.failed_step, high.failure])
		var mid := SessionBot.run(r, _steps("C_DROP_FOOT_T", c[3]))
		runner.check(mid.failed_step == 1, "%s: 조금만 내린 발판으로는 #1에서 막힘 #%d %s" % [c[4], mid.failed_step, mid.failure])


## 핸드매치: 손을 모으지 않으면 먼 홀드에 닿지 않고(직접·다른 손홀드 거쳐 가기), 모으면 닿는다. 매치를 금지하면 모으기에서 막힌다.
func test_match_needed() -> void:
	var cases := [
		[_route("C_MATCH_T"), [["RH", "W01/hand_1"], ["LH", "H02/hand_1"]], [["LH", "H02/hand_1"]], [["LH", "H03/hand_1"], ["LH", "H02/hand_1"]], "M2"],
		[_from_step("C_MATCH_T", "M3"), [["LH", "W01/hand_1"], ["RH", "H04/hand_1"]], [["RH", "H04/hand_1"]], [["RH", "H01/hand_1"], ["RH", "H04/hand_1"]], "M4"],
	]
	for c in cases:
		var r: RouteDef = c[0]
		var matched := SessionBot.run(r, _steps("C_MATCH_T", c[1]))
		runner.check(matched.failed_step == -1 and matched.session.falls == 0, "%s: 손을 모으면 먼 홀드에 닿음 %s" % [c[4], matched.failure])
		var direct := SessionBot.run(r, _steps("C_MATCH_T", c[2]))
		runner.check(direct.failed_step == 0, "%s: 모으지 않으면 #0에서 막힘 #%d %s" % [c[4], direct.failed_step, direct.failure])
		var via := SessionBot.run(r, _steps("C_MATCH_T", c[3]))
		runner.check(via.failed_step == 1, "%s: 다른 손홀드를 거쳐도 #1에서 막힘 #%d %s" % [c[4], via.failed_step, via.failure])
		var no_match := SessionBot.run(r, _steps("C_MATCH_T", c[1]), {&"match": true})
		runner.check(no_match.failed_step == 0, "%s: 매치를 금지하면 모으기(#0)에서 막힘 #%d %s" % [c[4], no_match.failed_step, no_match.failure])


func test_drop_foot_tutorial_reaches_done() -> void:
	_drive("C_DROP_FOOT_T")


func test_match_tutorial_reaches_done() -> void:
	_drive("C_MATCH_T")


## 패드 입력만으로 모든 단계를 끝낸다. 단계마다 결과가 "next"(마지막 "done") 하나이고 재시작이 없어야 한다.
func _drive(rid: String):
	var d := Driver.new(_route(rid))
	for i in 30:
		d.tick()
	runner.check(d.results.is_empty(), "%s 시작 대기 중 진행 없음 %s" % [rid, d.results])
	var script: Dictionary = SCRIPTS[rid]
	var steps: Array = d.t.steps
	runner.check(steps.map(func(st): return str(st.step_id)) == script.keys(), "%s 조작표가 단계와 같음" % rid)
	for n in steps.size():
		var id := str(steps[n].step_id)
		runner.check(d.t.index == n, "%s 시작(index %d)" % [id, d.t.index])
		d.results.clear()
		for a in script[id]:
			if a[0] == "wait":
				for k in int(a[1]):
					d.tick()
				continue
			var limb := StringName(a[1])
			var key: String = rid + "/" + a[2]
			var ok: bool = d.drag(limb, key)
			runner.check(ok, "%s %s %s %s" % [id, a[0], a[1], a[2]])
			if not d.results.is_empty():
				break
		for k in STEP_MAX_TICKS:
			if not d.results.is_empty():
				break
			d.tick()
		var want := "done" if n == steps.size() - 1 else "next"
		runner.check(d.results == [want], "%s 완료 %s → %s(낙하 %d, 골반 %s)" % [id, want, d.results, d.s.falls, d.s.body.pos])
		if d.results != [want]:
			return null
	runner.check(d.t.done and d.restarts == 0, "%s 완료, 재시작 없음(재시작 %d)" % [rid, d.restarts])
	return d
