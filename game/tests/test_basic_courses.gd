extends RefCounted
## 기본 과정 셋(docs/16 v0.7 "기본 과정 셋"): 쉬는 법 C_REST_T·몸 모양과 팔 힘 C_ARM_LOAD_T·일부러 떨어지기 C_FALL_T.
## 실제 세션에 패드 입력을 넣어 모든 단계가 "next"(마지막은 "done") 한 번씩으로 끝나는지,
## 팔 힘 목표가 적당한 시간(10초) 안에 차는지, 일부러 떨어진 뒤 시작 자세로 돌아오는지 확인한다.

var runner

const Driver := preload("res://tests/tutorial_driver.gd")
const STEP_MAX_TICKS := 900          # 행동 뒤 목표를 기다리는 최대 틱(15초)
const STAMINA_MAX_SECONDS := 10.0    # 팔 힘 목표 단계가 끝나야 하는 시간(단계 시작부터)

## 과정 → [튜토리얼, 단계 순서]
const COURSES := {
	"C_REST": ["C_REST_T", ["R1", "R2", "R3"]],
	"C_ARM_LOAD": ["C_ARM_LOAD_T", ["A1", "A2", "A3"]],
	"C_FALL": ["C_FALL_T", ["F1", "F2"]],
}

## 단계 규칙(16 표): [피로 감소, 시작 체력(-1이면 없음)]
const RULES := {
	"R1": [true, 40], "R2": [true, 40], "R3": [true, -1],
	"A1": [true, 100], "A2": [true, -1], "A3": [true, 60],
	"F1": [false, -1], "F2": [false, -1],
}


func _route(id: String) -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path(id))


func test_basic_courses_files() -> void:
	for cid in COURSES:
		var rid: String = COURSES[cid][0]
		var r := _route(rid)
		runner.check(r.errors.is_empty(), "%s 저작 오류 없음 %s" % [rid, r.errors])
		runner.check(r.route_id == rid and r.mode == "course" and r.course_id == cid and r.course_slot == "tutorial" and r.grade == "V0", "%s: %s 튜토리얼 V0" % [rid, cid])
		var ids := r.tutorial_steps.map(func(st): return str(st.step_id))
		runner.check(ids == COURSES[cid][1], "%s 단계 순서 %s" % [rid, ids])
		for st in r.tutorial_steps:
			var help: Array = st.get("help_ko", [])
			var rules: Dictionary = st.get("rules", {})
			var want: Array = RULES[str(st.step_id)]
			runner.check(str(st.get("text_ko", "")) != "" and help.size() == 2, "%s 안내·도움말 2단계" % st.step_id)
			runner.check(rules.get("techniques", null) == [], "%s 기술 버튼 없음" % st.step_id)
			runner.check(not (str(st.text_ko) + " ".join(help)).contains("버튼"), "%s 버튼 언급 없음" % st.step_id)
			runner.check(rules.get("fatigue_drain", null) == want[0], "%s 피로 감소 %s" % [st.step_id, want[0]])
			runner.check(float(rules.get("start_stamina", -1)) == float(want[1]), "%s 시작 체력 %s" % [st.step_id, want[1]])
		# 배치는 G_V0_01 사다리 시작 자세(16 기본 과정 셋)
		runner.check(r.start_pelvis.is_equal_approx(Vector2(0.0, 0.744)), "%s 시작 골반 (0, 0.744)" % rid)
		for limb in ["LH", "RH", "LF", "RF"]:
			var pos := r.slot_pos(r.start_slots[StringName(limb)])
			var want_pos: Vector2 = {"LH": Vector2(-0.45, 1.80), "RH": Vector2(0.45, 1.80), "LF": Vector2(-0.30, 0.10), "RF": Vector2(0.30, 0.10)}[limb]
			runner.check(pos.is_equal_approx(want_pos), "%s 시작 %s %s" % [rid, limb, pos])
		var res := ContentCheck.check(r)
		runner.check(res.ok, "%s 의도 경로 SessionBot 완등:\n      %s" % [rid, "\n      ".join(res.lines)])


## 쉬는 법: 두 발로 가만히 있으면 체력 40 → 70, 왼손을 놓고 기다리면 40 → 90, 다시 잡고 H03.
func test_rest_tutorial_reaches_done() -> void:
	var d := Driver.new(_route("C_REST_T"))
	_run(d, {
		"R1": [],
		"R2": [["air", "LH", Vector2(0.0, -0.35)]],
		"R3": [["drag", "LH", "C_REST_T/H03/hand_1"]],
	})


## 몸 모양과 팔 힘: 왼발을 떼면 한 발·두 손이라 체력이 줄고(100 → 85), 다시 딛고, 두 발로 쉬면 60 → 75.
func test_arm_load_tutorial_reaches_done() -> void:
	var d := Driver.new(_route("C_ARM_LOAD_T"))
	_run(d, {
		"A1": [["air", "LF", Vector2(-0.10, 0.25)]],
		"A2": [["drag", "LF", "C_ARM_LOAD_T/F01/foot_1"]],
		"A3": [],
	})


## 일부러 떨어지기: 두 손을 모두 놓으면 떨어지고(목표), 추락 연출 뒤 시작 자세에서 F2를 시작해 H03을 잡는다.
## F1은 벽 발판(F03·F04)에 선 자세에서 시작한다. 바닥 발판에 두 발로 서 있으면 플랫폼 지지라 떨어지지 않는다.
func test_fall_tutorial_reaches_done() -> void:
	var d := Driver.new(_route("C_FALL_T"))
	runner.check(not d.s.on_platform(d.s.attached()) and d.s.body.pos.y > 1.0, "F1 시작: 바닥 발판 밖(골반 %s)" % [d.s.body.pos])
	_run(d, {
		"F1": [["drop_hands"]],
		"F2": [["drag", "LH", "C_FALL_T/H03/hand_1"]],
	})
	runner.check(d.s.falls == 1, "일부러 한 번 떨어짐(낙하 %d)" % d.s.falls)


## 단계마다 조작을 넣고 결과를 기다린다. ["drag", limb, key] 끌어 놓기, ["air", limb, 지금 위치에서의 변위] 허공에 놓기,
## ["drop_hands"] 두 손을 함께 떼어 놓기, [] 아무것도 하지 않음. 팔 힘 목표는 STAMINA_MAX_SECONDS 안에 끝나야 한다.
func _run(d, script: Dictionary) -> void:
	for i in 30:
		d.tick()  # 시작 자세 안정
	runner.check(d.results.is_empty(), "%s 시작 대기 중 진행 없음 %s" % [d.t.route.route_id, d.results])
	var steps: Array = d.t.steps
	runner.check(steps.map(func(st): return str(st.step_id)) == script.keys(), "조작표가 단계와 같음")
	for n in steps.size():
		var st: Dictionary = steps[n]
		var id := str(st.step_id)
		var goal: Dictionary = st.goal_event
		runner.check(d.t.index == n, "%s 시작(index %d)" % [id, d.t.index])
		d.results.clear()
		var t0: int = d.ticks
		if id == "F2":
			var limbs: Dictionary = d.s.limbs
			var start_ok: bool = d.s.body.pos.distance_to(d.t.route.start_pelvis) < 0.05 and not d.s.falling
			for limb in d.t.route.start_slots:
				start_ok = start_ok and limbs[limb].state == "Attached" and limbs[limb].key == d.t.route.start_slots[limb]
			runner.check(start_ok, "F2: 떨어진 뒤 시작 자세로 돌아옴(골반 %s)" % [d.s.body.pos])
		for a in script[id]:
			match a[0]:
				"drag":
					runner.check(d.drag(StringName(a[1]), a[2]), "%s %s 끌어 놓기" % [id, a[1]])
				"air":
					var limb := StringName(a[1])
					runner.check(d.drag_to_air(limb, d.s.limbs[limb].pos + a[2]), "%s %s 허공에 놓기" % [id, a[1]])
					runner.check(not d.s.attached().has(limb) or not d.results.is_empty(), "%s %s 놓음(%s)" % [id, a[1], d.s.limbs[limb].state])
				"drop_hands":
					# 두 손 패드를 누른 채 끌어 홀드에서 뗀다(제자리에서 놓으면 같은 홀드를 다시 잡는다)
					d.s.apply_input([{"type": "detach", "limb": &"LH"}, {"type": "detach", "limb": &"RH"}])
			if not d.results.is_empty():
				break
		d.wait(STEP_MAX_TICKS)
		var secs: float = (d.ticks - t0) / float(Tuning.TICK_HZ)
		var want := "done" if n == steps.size() - 1 else "next"
		var st_now: Dictionary = d.s.rules.stamina
		runner.check(d.results == [want], "%s 완료 %s → %s(%.2f초, 낙하 %d, 체력 L%.0f R%.0f, 골반 %s)" % [id, want, d.results, secs, d.s.falls, st_now[PoseSolver.LH], st_now[PoseSolver.RH], d.s.body.pos])
		if str(goal.type) == "stamina":
			runner.check(secs <= STAMINA_MAX_SECONDS, "%s 팔 힘 목표 %.2f초 ≤ %.0f초" % [id, secs, STAMINA_MAX_SECONDS])
		if d.results != [want]:
			return
	runner.check(d.t.done and d.restarts == 0, "%s 완료, 재시작 없음(재시작 %d)" % [d.t.route.route_id, d.restarts])
