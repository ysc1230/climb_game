extends RefCounted
## 튜토리얼 개편(docs/33, 2026-11-09): 몸통 옮기기 C_BODY_T, 위험 신호와 도움 C_DANGER_T, 새 목표(body·caution·
## danger_end·safe_again·quality_min), 난이도별 단계(only_level), 단계별 자동 도움(rules.rescue), 문구 규칙,
## 처음 한 번 안내 저장, 완료 화면 다음 과정.

var runner

const Driver := preload("res://tests/tutorial_driver.gd")
const BANNED := ["반짝이는", "위쪽 게이지", "넓은 홀드", "표시된"]


func _route(id: String) -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path(id))


func _settle(d) -> void:
	for i in 30:
		d.tick()


func _expect(d, want: String, label: String, max_ticks := 900) -> void:
	d.results.clear()
	d.wait(max_ticks)
	runner.check(d.results == [want], "%s → %s (결과 %s, 골반 %s, 낙하 %d)" % [label, want, d.results, d.s.body.pos, d.s.falls])


func test_new_tutorial_files() -> void:
	for id in ["C_BODY_T", "C_DANGER_T"]:
		var r := _route(id)
		runner.check(r.errors.is_empty(), "%s 저작 오류 없음 %s" % [id, r.errors])
		var res := ContentCheck.check(r)
		runner.check(res.ok, "%s 의도 경로 SessionBot 완등:\n      %s" % [id, "\n      ".join(res.lines)])
		for st in r.tutorial_steps:
			runner.check(st.get("help_ko", []).size() == 2 and str(st.get("text_ko", "")) != "", "%s %s 안내·도움말 2단계" % [id, st.step_id])
	runner.check(ContentIndex.route_path("C_FALL_T") == "" or not FileAccess.file_exists(ContentIndex.route_path("C_FALL_T")), "일부러 떨어지기 튜토리얼 없앰")


## 몸통 옮기기: 가운데를 끌어 몸을 오른쪽으로(BD1), 가운데를 누른 채 오른손을 먼 홀드로(BD2).
func test_body_tutorial_reaches_done() -> void:
	var d = Driver.new(_route("C_BODY_T"))
	_settle(d)
	d.body_drag(Vector2(0.45, 0))
	_expect(d, "next", "BD1 몸통 끌기")
	runner.check(d.drag(&"RH", "C_BODY_T/H07/hand_1"), "BD2 오른손 끌어 놓기")
	_expect(d, "done", "BD2 먼 홀드")
	runner.check(d.restarts == 0, "재시작 없음")


## 금지 재생: 몸통을 끌지 않으면 BD2의 먼 홀드에 닿지 않는다.
func test_body_far_hold_needs_body_drag() -> void:
	var d = Driver.new(_route("C_BODY_T"))
	_settle(d)
	d.t.index = 1
	d.t.begin_step(d.s)
	var ok: bool = d.drag(&"RH", "C_BODY_T/H07/hand_1")
	d.wait(120)
	runner.check(not ok and d.s.limbs[&"RH"].key != "C_BODY_T/H07/hand_1", "몸통 끌기 없이는 먼 홀드에 안 닿음")


## 위험 신호와 도움(초급): 주의(D1) → 왼손 먼저(D2) → 두 손 놓아 위험을 겪음(D3) → 자동 도움(D4).
func test_danger_tutorial_beginner() -> void:
	var d = Driver.new(_route("C_DANGER_T"), "beginner")
	_settle(d)
	runner.check(d.results.is_empty() and d.t.index == 0, "D1 시작 자세는 안정")
	d.arm(&"RH")
	_expect(d, "next", "D1 오른손 패드 누르기 → 주의", 60)
	d.s.apply_input([{"type": "disarm", "limb": &"RH"}])
	runner.check(d.drag(&"LH", "C_DANGER_T/H03/hand_1"), "D2 왼손 끌어 놓기")
	_expect(d, "next", "D2 왼손 먼저")
	_settle(d)
	runner.check(not d.t.rescue_allowed(), "D3에서는 자동 도움 꺼짐")
	d.s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"}])
	_expect(d, "next", "D3 두 손 놓기 → 위험이 끝남(초급은 1.5초 뒤 떨어짐)", 400)
	runner.check(d.s.falls == 1, "D3에서 한 번 떨어짐(%d)" % d.s.falls)
	runner.check(str(d.t.current().step_id) == "D4" and d.t.rescue_allowed(), "D4(초급만)에서 자동 도움 켜짐")
	_settle(d)
	d.s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"}])
	for i in 20:
		d.tick()
	runner.check(d.fb.danger, "D4 두 손을 놓으면 위험")
	runner.check(d.rescue(), "자동 도움 계획 있음")
	_expect(d, "done", "D4 자동 도움 → 다시 안전", 10)
	runner.check(d.visited == ["D1", "D2", "D3", "D4"], "초급 단계 %s" % [d.visited])


## 위험 신호와 도움(중급): D4(자동 도움)를 건너뛰고 D3에서 끝난다.
func test_danger_tutorial_intermediate() -> void:
	var d = Driver.new(_route("C_DANGER_T"), "intermediate")
	_settle(d)
	d.arm(&"RH")
	_expect(d, "next", "D1 주의", 60)
	d.s.apply_input([{"type": "disarm", "limb": &"RH"}])
	d.drag(&"LH", "C_DANGER_T/H03/hand_1")
	_expect(d, "next", "D2")
	_settle(d)
	d.s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"}])
	_expect(d, "done", "D3 → 끝(중급은 0.15초 만에 떨어짐)", 120)
	runner.check(d.visited == ["D1", "D2", "D3"] and d.t.done, "중급 단계 %s" % [d.visited])


## 금지 재생: D2 뒤(두 손)에는 오른손 패드를 눌러도 주의가 뜨지 않는다.
func test_no_caution_with_two_hands() -> void:
	var d = Driver.new(_route("C_DANGER_T"))
	_settle(d)
	d.drag(&"LH", "C_DANGER_T/H03/hand_1")
	_settle(d)
	runner.check(d.s.release_risk(&"RH") == &"", "두 손이면 오른손을 떼도 버팀")


func test_runner_new_goals() -> void:
	var r := _route("C_DANGER_T")
	var t := TutorialRunner.new(r)
	t.set_level("intermediate")
	runner.check(t.steps.filter(func(st): return st.get("only_level", "") == "beginner").size() == 1, "초급만 단계 하나")
	var s := ClimbSession.new(r)
	t.begin_step(s)
	t.note({"type": "caution", "limb": &"LH"})
	runner.check(t.observe(s, "", Tuning.DT) == "", "다른 손 주의는 목표 아님")
	t.note({"type": "caution", "limb": &"RH"})
	runner.check(t.observe(s, "", Tuning.DT) == "next", "오른손 주의 → 다음")
	runner.check(TutorialRunner.matches({"type": "grab", "limb": "LH", "quality_min": 0.85}, {"type": "grab", "limb": &"LH", "key": "x", "quality": 0.9}), "품질 하한 통과")
	runner.check(not TutorialRunner.matches({"type": "grab", "limb": "LH", "quality_min": 0.85}, {"type": "grab", "limb": &"LH", "key": "x", "quality": 0.5}), "품질 하한 미달")


## 튜토리얼 데이터에 옛 문구가 남지 않는다(docs/33 §3.2).
func test_tutorial_wording() -> void:
	var texts: Array[String] = []
	var dir := DirAccess.open("res://data/routes/course")
	for f in dir.get_files():
		if not f.ends_with("_T.json"):
			continue
		var r := RouteDef.load_json("res://data/routes/course/" + f)
		for st in r.tutorial_steps:
			texts.append("%s %s: %s %s" % [f, st.step_id, st.get("text_ko", ""), " ".join(st.get("help_ko", []))])
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/courses.json"))
	for c in data.courses:
		if int(c.phase) == 1:
			texts.append("%s: %s" % [c.course_id, JSON.stringify(c.get("text_ko", {}))])
	for line in texts:
		for w in BANNED:
			runner.check(not line.contains(w), "옛 문구 '%s' 없음: %s" % [w, line])


func test_next_basic_tutorial_and_tips() -> void:
	var p := Progress.new()
	var flow := PlayFlow.new(ContentIndex.load_all(), p, "user://test_tips_save.json")
	runner.check(flow.next_basic_tutorial("C_BASIC_T") == {"route_id": "C_BODY_T", "name": "몸통 옮기기"}, "기본 조작 다음은 몸통 옮기기")
	runner.check(flow.next_basic_tutorial("C_BODY_T").route_id == "C_DANGER_T", "몸통 옮기기 다음은 위험 신호와 도움")
	runner.check(flow.next_basic_tutorial("C_ARM_LOAD_T").is_empty(), "마지막 기본 과정 뒤는 없음")
	runner.check(flow.next_basic_tutorial("C_CROSS_T").is_empty(), "기술 과정은 다음 기본 과정 없음")
	flow.mark_tip("caution")
	flow.mark_tip("caution")
	runner.check(p.seen_tips == ["caution"], "안내는 한 번만 기록")
	runner.check(SaveStore.load("user://test_tips_save.json").seen_tips == ["caution"], "안내 기록 저장·불러오기")
	for f in ["user://test_tips_save.json", "user://test_tips_save.json.tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
