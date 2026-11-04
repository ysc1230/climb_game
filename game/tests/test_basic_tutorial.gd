extends RefCounted
## 기본 조작 튜토리얼 C_BASIC_T(docs/16 v0.7 B1~B9, 28 §6·§6.1): 실제 세션에 패드 입력을 넣어
## 모든 단계 목표가 차례로 달성되어 "done"까지 가는지 확인한다(의도 경로 재생이 아니라 단계 목표 자체).

var runner

const Driver := preload("res://tests/tutorial_driver.gd")
const STEP_MAX_TICKS := 600  # 행동 뒤 목표를 기다리는 최대 틱
const P := "C_BASIC_T/"

## 단계별 패드 조작(16 v0.7 표 순서): [limb, hold] 끌어 놓기.
const SCRIPT := {
	"B1": [["LH", "H03/hand_1"]],
	"B2": [["RH", "H04/hand_1"]],
	"B3": [["LF", "F03/foot_1"]],
	"B4": [["RF", "F04/foot_1"]],
	"B5": [["LH", "H05/hand_1"]],
	"B6": [["RH", "H06/hand_1"]],
	"B7": [["LF", "F05/foot_1"]],
	"B8": [["RF", "F06/foot_1"]],
	"B9": [["LH", "G01/goal_left"], ["RH", "G01/goal_right"]],
}


func _route(id := "C_BASIC_T") -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path(id))


func test_basic_tutorial_file() -> void:
	var r := _route()
	runner.check(r.errors.is_empty(), "저작 오류 없음 %s" % [r.errors])
	runner.check(r.mode == "course" and r.course_id == "C_BASIC" and r.course_slot == "tutorial" and r.grade == "V0", "C_BASIC 튜토리얼 V0")
	var ids := r.tutorial_steps.map(func(st): return str(st.step_id))
	runner.check(ids == SCRIPT.keys(), "16 v0.7 B1~B9 단계 순서 %s" % [ids])
	for st in r.tutorial_steps:
		var help: Array = st.get("help_ko", [])
		runner.check(str(st.get("text_ko", "")) != "" and help.size() == 2, "%s 안내 한 문장·도움말 2단계" % st.step_id)
		runner.check(st.get("rules", {}).get("techniques", null) == [], "%s 기술 버튼 없음" % st.step_id)
		runner.check(st.get("rules", {}).get("fatigue_drain", true) == false, "%s 피로 감소 끔" % st.step_id)
		runner.check(not (str(st.text_ko) + " ".join(help)).contains("버튼"), "%s 버튼 언급 없음(패드 전용)" % st.step_id)
	var res := ContentCheck.check(r)
	runner.check(res.ok, "의도 경로 SessionBot 완등:\n      %s" % "\n      ".join(res.lines))


## 배치는 G_V0_01 사다리 그대로다(홀드 ID 앞머리만 다름): 슬롯·좌표·시작 자세·정상·의도 경로가 같다.
func test_basic_tutorial_uses_g_v0_01_layout() -> void:
	var r := _route()
	var g := _route("G_V0_01")
	runner.check(r.slots.size() == g.slots.size(), "슬롯 수 같음 %d / %d" % [r.slots.size(), g.slots.size()])
	for key in g.slots:
		var mine := String(key).replace("G_V0_01/", P)
		runner.check(r.slots.has(mine) and r.slots[mine].pos.is_equal_approx(g.slots[key].pos), "%s 좌표 같음" % mine)
	runner.check(r.start_pelvis.is_equal_approx(g.start_pelvis), "시작 골반 같음 %s" % [r.start_pelvis])
	for limb in g.start_slots:
		runner.check(r.start_slots.get(limb, "") == String(g.start_slots[limb]).replace("G_V0_01/", P), "시작 %s 같음" % limb)
	var flat := func(moves: Array) -> String:
		return " ".join(moves.map(func(m): return "%s>%s" % [m[0], String(m[1]).replace("G_V0_01/", P)]))
	runner.check(flat.call(r.intended_moves) == flat.call(g.intended_moves), "의도 경로 같음 %s" % [r.intended_moves])


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
			runner.check(d.drag(StringName(a[0]), P + a[1]), "%s %s 끌어 놓기" % [id, a[0]])
			if not d.results.is_empty():
				break
		d.wait(STEP_MAX_TICKS)
		var want := "done" if n == steps.size() - 1 else "next"
		runner.check(d.results == [want], "%s 완료 %s → %s(낙하 %d, 골반 %s)" % [id, want, d.results, d.s.falls, d.s.body.pos])
		if d.results != [want]:
			return
	runner.check(d.t.done and d.restarts == 0 and d.s.falls == 0, "튜토리얼 완료, 재시작·낙하 없음")
