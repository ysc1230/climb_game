extends RefCounted
## 기본 조작 튜토리얼 C_BASIC_T(docs/28 §6·§6.1, 16 T01~T03): 실제 세션에 패드 입력을 넣어
## 모든 단계 목표가 차례로 달성되어 "done"까지 가는지 확인한다(의도 경로 재생이 아니라 단계 목표 자체).

var runner

const DT := Tuning.DT
const DRAG_SPEED := 2.5
const STEP_MAX_TICKS := 600  # 행동 뒤 목표를 기다리는 최대 틱
const P := "C_BASIC_T/"


func _route() -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path("C_BASIC_T"))


## 단계별 패드 조작(16 T01~T03 순서). ["drag", limb, hold] 끌어 놓기, ["together", [[limb, hold], ...]] 함께 끌기,
## ["drop_hands"] 두 손 떼기, [] 아무것도 하지 않음(가만히 기다림).
const SCRIPT := {
	"T01-A": [["drag", "LH", "H03/hand_1"]],
	"T01-B": [["drag", "RH", "H04/hand_1"]],
	"T01-C": [],
	"T02-A": [["drag", "LF", "F03/foot_1"]],
	"T02-B": [["drag", "RF", "F04/foot_1"]],
	"T02-D": [],
	"T02-E": [["drag", "LH", "H05/hand_1"]],
	"T03-A": [["together", [["LH", "H06/hand_1"], ["RF", "F05/foot_1"]]]],
	"T03-B": [["together", [["RH", "H07/hand_1"], ["LF", "F06/foot_1"]]]],
	"T03-C": [["drop_hands"]],
	"T03-D": [["drag", "LF", "F07/foot_1"], ["drag", "RF", "F08/foot_1"], ["drag", "LH", "H08/hand_1"]],
	"T03-E": [["drag", "RH", "G01/goal_right"], ["drag", "LH", "G01/goal_left"]],
}


class Driver:
	var s: ClimbSession
	var t: TutorialRunner
	var results: Array = []  # 이번 단계에서 observe가 돌려준 빈 문자열 아닌 값
	var restarts := 0
	var min_stamina_d := 100.0  # T02-D 확인용: 단계 끝 체력

	func _init(route: RouteDef) -> void:
		s = ClimbSession.new(route)
		t = TutorialRunner.new(route)
		t.begin_step(s)

	## 한 틱 + 튜토리얼 관찰(play_test._tutorial_tick과 같은 흐름: 추락 목표면 respawn까지 기다렸다 다음 단계).
	func tick() -> String:
		var r := s.step()
		var act := t.observe(s, r, DT)
		if act == "":
			return ""
		results.append(act)
		if act == "restart":
			restarts += 1
		if act in ["next", "restart"]:
			if r.begins_with("fall:"):
				for i in 120:
					if s.step() == "respawn":
						break
			t.begin_step(s)
		return act

	func move(limb: StringName, target: Vector2) -> void:
		var req: Vector2 = s.limbs[limb].req
		s.apply_input([{"type": "move", "limb": limb, "delta": (target - req).limit_length(DRAG_SPEED * DT)}])

	## 여러 팔다리를 함께 떼어 끌고, 각자 후보가 그 키가 되면 놓는다. 단계가 바뀌면(결과가 나오면) 멈춘다.
	func drag(pairs: Array) -> bool:
		var left := {}
		for p in pairs:
			left[StringName(p[0])] = str(p[1])
		s.apply_input(left.keys().map(func(l): return {"type": "detach", "limb": l}))
		for i in 300:
			for limb in left.keys():
				move(limb, s.route.slot_pos(left[limb]))
			var act := tick()
			for limb in left.keys():
				if s.limbs[limb].cand.get("key", "") == left[limb]:
					s.apply_input([{"type": "release", "limb": limb, "speed": 0.0}])
					left.erase(limb)
			if act != "" or left.is_empty():
				return true
		return false


func test_basic_tutorial_file() -> void:
	var r := _route()
	runner.check(r.errors.is_empty(), "저작 오류 없음 %s" % [r.errors])
	runner.check(r.mode == "course" and r.course_id == "C_BASIC" and r.course_slot == "tutorial", "C_BASIC 튜토리얼")
	var ids := r.tutorial_steps.map(func(st): return str(st.step_id))
	runner.check(ids == SCRIPT.keys(), "16 T01~T03 단계 순서 %s" % [ids])
	for st in r.tutorial_steps:
		var help: Array = st.get("help_ko", [])
		runner.check(str(st.get("text_ko", "")) != "" and help.size() == 2, "%s 안내 한 문장·도움말 2단계" % st.step_id)
		runner.check(st.get("rules", {}).get("techniques", null) == [], "%s 기술 버튼 없음" % st.step_id)
		runner.check(not (str(st.text_ko) + " ".join(help)).contains("버튼"), "%s 버튼 언급 없음(패드 전용)" % st.step_id)
	for key in r.slots:
		var pos: Vector2 = r.slots[key].pos
		runner.check(pos.x >= -1.5 and pos.x <= 1.5 and pos.y >= 0.0 and pos.y <= 4.5, "벽 안 %s %s" % [key, pos])


## 단계 규칙(16): T01·T02 피로 감소 끔, T02-D 시작 체력 70, T03 A/B/C 끔 D/E 켬, T03-A·D 시작 100.
func test_basic_tutorial_rules() -> void:
	var r := _route()
	var by := {}
	for st in r.tutorial_steps:
		by[str(st.step_id)] = st.get("rules", {})
	for id in ["T01-A", "T01-B", "T01-C", "T02-A", "T02-B", "T02-D", "T02-E", "T03-A", "T03-B", "T03-C"]:
		runner.check(by[id].get("fatigue_drain", true) == false, "%s 피로 감소 끔" % id)
	for id in ["T03-D", "T03-E"]:
		runner.check(by[id].get("fatigue_drain", false) == true, "%s 피로 감소 켬" % id)
	runner.check(is_equal_approx(float(by["T02-D"].get("start_stamina", -1)), 70.0), "T02-D 시작 체력 70")
	runner.check(is_equal_approx(float(by["T03-A"].get("start_stamina", -1)), 100.0), "T03-A 시작 체력 100")
	runner.check(is_equal_approx(float(by["T03-D"].get("start_stamina", -1)), 100.0), "T03-D 시작 체력 100")


## 패드 입력만으로 모든 단계를 완료한다. 단계마다 정확히 한 번 진행하고, 실패·재시작이 없어야 한다.
func test_basic_tutorial_reaches_done() -> void:
	var d := Driver.new(_route())
	for i in 30:
		d.tick()  # 시작 자세 안정
	runner.check(d.results.is_empty(), "시작 대기 중 진행 없음 %s" % [d.results])
	var steps: Array = d.t.steps
	for n in steps.size():
		var id := str(steps[n].step_id)
		runner.check(d.t.index == n, "%s 시작(index %d)" % [id, d.t.index])
		d.results.clear()
		for a in SCRIPT[id]:
			match a[0]:
				"drag":
					runner.check(d.drag([[a[1], P + a[2]]]), "%s %s 끌어 놓기" % [id, a[1]])
				"together":
					runner.check(d.drag(a[1].map(func(p): return [p[0], P + p[1]])), "%s 함께 끌기" % id)
				"drop_hands":
					d.s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"}])
			if not d.results.is_empty():
				break
		for k in STEP_MAX_TICKS:
			if not d.results.is_empty():
				break
			d.tick()
		if id == "T02-D":
			var st: Dictionary = d.s.rules.stamina
			runner.check(st[PoseSolver.LH] >= 80.0 and st[PoseSolver.RH] >= 80.0, "T02-D 쉬어서 체력 80 이상 %s" % [st])
		var want := "done" if n == steps.size() - 1 else "next"
		runner.check(d.results == [want], "%s 완료 %s → %s(낙하 %d, 골반 %s)" % [id, want, d.results, d.s.falls, d.s.body.pos])
		if d.results != [want]:
			return
	runner.check(d.t.done and d.restarts == 0, "튜토리얼 완료, 재시작 없음")
