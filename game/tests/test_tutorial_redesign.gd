extends RefCounted
## 튜토리얼 엔진 기능(docs/33): 화면 사건 목표(caution·danger_end·safe_again·rescue), 몸통 위치 목표(body),
## 잡은 품질 하한(quality_min), 난이도별 단계(only_level), 단계별 자동 도움(rules.rescue), 문구 규칙, 처음 한 번 안내 저장,
## 다른 손발이 쓰는 홀드에 놓기(slot_swap).
## 2026-11-11: 튜토리얼 파일을 모두 지웠으므로(사용자 결정) 테스트용 판(tests/fixtures/G_V0_01.json)에 단계를 붙여 시험한다.

var runner

const Driver := preload("res://tests/tutorial_driver.gd")
const FIXTURE := "res://tests/fixtures/G_V0_01.json"
const BANNED := ["반짝이는", "위쪽 게이지", "넓은 홀드", "표시된"]
const RULES := {"fatigue_drain": false, "techniques": []}


func _route(steps: Array) -> RouteDef:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	d.mode = "course"
	d.course_id = "C_TEST"
	d.course_slot = "tutorial"
	d.erase("grade")
	d.erase("order")
	d.tutorial_steps = steps
	return RouteDef.from_dict(d)


func _step(id: String, goal: Dictionary, extra := {}) -> Dictionary:
	var s := {"step_id": id, "text_ko": "해 보세요.", "goal_event": goal, "help_ko": ["a", "b"], "rules": RULES.duplicate()}
	s.merge(extra, true)
	return s


func _settle(d) -> void:
	for i in 30:
		d.tick()


func test_runner_new_goals() -> void:
	var r := _route([_step("A", {"type": "caution", "limb": "RH"}), _step("B", {"type": "danger_end"}),
		_step("C", {"type": "rescue"}, {"only_level": "beginner"}), _step("D", {"type": "safe_again"})])
	var t := TutorialRunner.new(r)
	t.set_level("intermediate")
	var s := ClimbSession.new(r)
	t.begin_step(s)
	t.note({"type": "caution", "limb": &"LH"})
	runner.check(t.observe(s, "", Tuning.DT) == "", "다른 손 주의는 목표 아님")
	t.note({"type": "caution", "limb": &"RH"})
	runner.check(t.observe(s, "", Tuning.DT) == "next", "오른손 주의 → 다음")
	t.begin_step(s)
	t.note({"type": "danger_end"})
	runner.check(t.observe(s, "", Tuning.DT) == "next" and str(t.current().step_id) == "D", "중급은 초급 전용 C를 건너뜀")
	t.begin_step(s)
	t.note({"type": "rescue"})
	runner.check(t.observe(s, "", Tuning.DT) == "done", "safe_again은 자동 도움으로도 채워짐")
	runner.check(TutorialRunner.matches({"type": "grab", "limb": "LH", "quality_min": 0.85}, {"type": "grab", "limb": &"LH", "key": "x", "quality": 0.9}), "품질 하한 통과")
	runner.check(not TutorialRunner.matches({"type": "grab", "limb": "LH", "quality_min": 0.85}, {"type": "grab", "limb": &"LH", "key": "x", "quality": 0.5}), "품질 하한 미달")


## rescue 목표: 패드로 다시 잡아 회복하면 성공이 아니라 그 단계를 다시(2026-11-10 사용자).
func test_rescue_goal_rejects_pad_recover() -> void:
	var r := _route([_step("R", {"type": "rescue"}, {"rules": {"fatigue_drain": false, "techniques": [], "rescue": true, "danger_seconds": 6}})])
	var d = Driver.new(r, "beginner")
	runner.check(d.t.rescue_allowed(), "rules.rescue 단계는 자동 도움 허용")
	runner.check(d.s.rules.grace_budget == 360, "danger_seconds 6 → 360틱 (%d)" % d.s.rules.grace_budget)
	for i in 5:
		d.tick()
	d.t.note({"type": "recover"})
	runner.check(d.tick() == "restart", "패드로 회복 → 다시")
	d.t.note({"type": "rescue"})
	runner.check(d.tick() == "done", "고리(자동 도움) → 완료")


func test_body_goal_needs_body_drag() -> void:
	var r := _route([_step("B", {"type": "body", "dx_min": 0.15, "seconds": 0.5})])
	var d = Driver.new(r)
	_settle(d)
	runner.check(d.results.is_empty(), "가만히 있으면 몸통 목표 안 채워짐")
	d.body_drag(Vector2(0.4, 0))
	d.results.clear()
	d.wait(200)
	runner.check(d.results == ["done"], "가운데를 끌어 몸을 옮기면 완료 %s (골반 %s)" % [d.results, d.s.body.pos])


## 두 손 + 바닥 발판이면 한 손을 떼도 버틴다(주의 없음). 한 손만 남았는데 떼면 GRACE.
func test_release_risk_on_fixture() -> void:
	var d = Driver.new(_route([_step("X", {"type": "clear"})]))
	_settle(d)
	runner.check(d.s.release_risk(&"RH") == &"", "두 손이면 오른손을 떼도 버팀")
	d.s.apply_input([{"type": "detach", "limb": &"LH"}])
	d.tick()
	runner.check(d.s.release_risk(&"RH") == &"GRACE", "남은 한 손을 떼면 버틸 손 없음")


## 튜토리얼 데이터에 옛 문구가 남지 않는다(docs/33 §3.2). 지금은 튜토리얼 파일이 없어도 통과한다.
func test_tutorial_wording() -> void:
	var texts: Array[String] = []
	var dir := DirAccess.open("res://data/routes/course")
	if dir != null:
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
	runner.check(flow.next_basic_tutorial("C_BASIC_T").is_empty(), "튜토리얼이 없으면 다음 과정 없음")
	runner.check(not p.first_run_locked(flow.index), "기본 조작 튜토리얼이 없으면 첫 실행 잠금 없음")
	flow.mark_tip("caution")
	flow.mark_tip("caution")
	runner.check(p.seen_tips == ["caution"], "안내는 한 번만 기록")
	runner.check(SaveStore.load("user://test_tips_save.json").seen_tips == ["caution"], "안내 기록 저장·불러오기")
	for f in ["user://test_tips_save.json", "user://test_tips_save.json.tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


## 다른 손발이 밟고 있는 홀드에 발을 놓으면 그 발을 떼고 허공(균형이 가장 좋은 곳)에 둔다(2026-11-10 사용자).
func test_slot_swap_frees_occupant() -> void:
	var r := _route([_step("X", {"type": "clear"})])
	var d = Driver.new(r)
	_settle(d)
	var key: String = d.s.limbs[&"RF"].key
	d.s.apply_input([{"type": "detach", "limb": &"LF"}])
	for i in 120:
		var req: Vector2 = d.s.limbs[&"LF"].req
		d.s.apply_input([{"type": "move", "limb": &"LF", "delta": (r.slot_pos(key) - req).limit_length(2.5 * Tuning.DT)}])
		d.tick()
	d.s.apply_input([{"type": "release", "limb": &"LF", "speed": 0.0}])
	d.tick()
	runner.check(d.s.limbs[&"LF"].state == "Attached" and d.s.limbs[&"LF"].key == key, "왼발이 오른발 자리를 잡음(%s %s)" % [d.s.limbs[&"LF"].state, d.s.limbs[&"LF"].key])
	runner.check(d.s.limbs[&"RF"].state == "Flag", "오른발은 떼어 허공에(%s)" % d.s.limbs[&"RF"].state)
	for i in 60:
		d.tick()
	runner.check(d.s.falls == 0, "떨어지지 않음")
