extends RefCounted
## docs/28 §5: 홈·플레이 연결(PlayFlow). 모드별 기술 버튼, 패널 숨김 판정, 완등 기록·저장.

var runner
const PlayOverlay := preload("res://scenes/play_overlay.gd")
const FIX := "user://test_play_flow_fixture"
const SAVE := "user://test_play_flow_save.json"
const G_PATH := "res://tests/fixtures/G_V0_01.json"
const PlayTest := preload("res://scenes/play_test.gd")


func _base() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(G_PATH))


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _general(id: String, grade: String, order: int) -> void:
	var d := _base()
	d.route_id = id
	d.grade = grade
	d.order = order
	d.required_techniques = []
	_write("%s/routes/general/%s.json" % [FIX, id], d)


func _course_route(id: String, slot: String, step_rules := {}) -> void:
	var d := _base()
	d.route_id = id
	d.mode = "course"
	d.course_id = id.substr(0, id.rfind("_"))
	d.course_slot = slot
	d.erase("grade")
	d.erase("order")
	d.required_techniques = []
	if slot == "tutorial":
		var step := {"step_id": "S1", "text_ko": "해 보세요.", "goal_event": {"type": "clear"}, "help_ko": ["a", "b"]}
		if not step_rules.is_empty():
			step.rules = step_rules
		d.tutorial_steps = [step]
	_write("%s/routes/course/%s.json" % [FIX, id], d)


func _index() -> ContentIndex:
	_general("G_V0_01", "V0", 1)
	_general("G_V0_02", "V0", 2)
	_course_route("C_BASIC_T", "tutorial")
	_course_route("C_DROP_KNEE_T", "tutorial")
	_course_route("C_OUTSIDE_EDGE_T", "tutorial", {"techniques": ["T_OUTSIDE_EDGE"], "fatigue_drain": false})
	_course_route("C_OUTSIDE_EDGE_1", "easy")
	_write(FIX + "/courses.json", {"courses": [
		{"course_id": "C_BASIC", "order": 0, "name_ko": "기본 조작", "kind": "pad", "techniques": [], "tutorial": "C_BASIC_T", "problems": [], "phase": 1},
		{"course_id": "C_OUTSIDE_EDGE", "order": 1, "name_ko": "아웃사이드 엣지", "kind": "button", "techniques": ["T_OUTSIDE_EDGE"], "tutorial": "C_OUTSIDE_EDGE_T",
			"problems": ["C_OUTSIDE_EDGE_1"], "phase": 1},
		{"course_id": "C_DROP_KNEE", "order": 2, "name_ko": "드롭니", "kind": "button", "techniques": ["T_DROP_KNEE"], "tutorial": "C_DROP_KNEE_T",
			"problems": [], "phase": 1}]})
	return ContentIndex.load_all(FIX)


func _cleanup() -> void:
	for dir in [FIX + "/routes/general", FIX + "/routes/course", FIX + "/routes", FIX]:
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir + "/" + f)
	for dir in [FIX + "/routes/general", FIX + "/routes/course", FIX + "/routes", FIX]:
		DirAccess.remove_absolute(dir)
	for p in [SAVE, SAVE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _flow() -> PlayFlow:
	_cleanup()
	var flow := PlayFlow.new(_index(), Progress.new(), SAVE)
	flow.progress.skip_basic()
	return flow


func test_allowed_buttons_for_modes() -> void:
	var flow := _flow()
	var idx := flow.index
	var none: Array[StringName] = []
	runner.check(flow.allowed_buttons_for(idx.route("G_V0_01")) == none, "일반: 해금 없으면 버튼 없음")
	flow.progress.record_tutorial("C_DROP_KNEE_T")
	runner.check(flow.allowed_buttons_for(idx.route("G_V0_01")) == ([&"T_DROP_KNEE"] as Array[StringName]), "일반: 해금된 버튼만")
	runner.check(flow.allowed_buttons_for(idx.route("C_BASIC_T")) == none, "기본 조작 튜토리얼: 버튼 없음")
	var t := idx.route("C_OUTSIDE_EDGE_T")
	runner.check(flow.allowed_buttons_for(t) == ([&"T_OUTSIDE_EDGE"] as Array[StringName]), "과정 튜토리얼: 그 과정 기술만(해금된 드롭니 없음)")
	var p := idx.route("C_OUTSIDE_EDGE_1")
	runner.check(flow.allowed_buttons_for(p) == ([&"T_OUTSIDE_EDGE", &"T_DROP_KNEE"] as Array[StringName]), "과정 문제: 과정 기술 ∪ 해금: %s" % [flow.allowed_buttons_for(p)])
	# 튜토리얼 단계 규칙(rules.techniques)이 있으면 그것이 우선
	var tr := TutorialRunner.new(idx.route("C_DROP_KNEE_T"))
	runner.check(flow.allowed_buttons_for(idx.route("C_DROP_KNEE_T"), tr) == ([&"T_DROP_KNEE"] as Array[StringName]), "단계 규칙 없음: 과정 기술")
	var tr2 := TutorialRunner.new(t)
	tr2.steps = [{"step_id": "S1", "text_ko": "x", "goal_event": {"type": "clear"}, "help_ko": ["a", "b"], "rules": {"techniques": []}}]
	runner.check(flow.allowed_buttons_for(t, tr2) == none, "단계 규칙 techniques=[] 이면 버튼 없음")
	_cleanup()


func test_no_unlocked_buttons_hides_panel() -> void:
	var defs := TechniqueJudge.defs()
	var none: Array[StringName] = []
	runner.check(PlayTest.panel_techs_for(none, defs).is_empty(), "허용 버튼 없음 → 패널 항목 없음")
	runner.check(not PlayTest.shows_tech_button(none, defs), "허용 버튼 없음 → 기술 버튼 숨김")
	var some: Array[StringName] = [&"T_DROP_KNEE", &"T_HIGH_STEP"]
	runner.check(PlayTest.panel_techs_for(some, defs) == [&"T_DROP_KNEE"], "패드 기술은 패널에 넣지 않음")
	runner.check(PlayTest.shows_tech_button(some, defs), "버튼 기술이 하나라도 있으면 보임")
	var pad_only: Array[StringName] = [&"T_HIGH_STEP"]
	runner.check(not PlayTest.shows_tech_button(pad_only, defs), "패드 기술만 → 숨김")


func test_finish_clear_records_and_saves() -> void:
	var flow := _flow()
	flow.current_route_id = "G_V0_01"
	var r := flow.current_route()
	r.time_medal_seconds = 40.0
	var res := flow.finish_clear(30.0, 0)
	runner.check(res.get("no_fall", false) and res.get("time", false), "이번 시도 메달: %s" % [res])
	runner.check(flow.progress.is_cleared("G_V0_01"), "진행에 기록")
	var loaded := SaveStore.load(SAVE)
	runner.check(loaded.is_cleared("G_V0_01") and loaded.basic_skipped, "저장 파일에 기록")
	var res2 := flow.finish_clear(50.0, 2)
	runner.check(not res2.no_fall and not res2.time, "느리고 떨어진 시도: 이번 메달 없음")
	runner.check(SaveStore.load(SAVE).cleared.G_V0_01.no_fall, "누적 메달은 유지")
	# 튜토리얼은 완등 기록 대신 튜토리얼 완료로 남는다
	flow.current_route_id = "C_DROP_KNEE_T"
	flow.finish_clear(10.0, 0)
	runner.check(not flow.progress.is_cleared("C_DROP_KNEE_T"), "튜토리얼은 완등 기록 없음")
	flow.finish_tutorial()
	runner.check(SaveStore.load(SAVE).tutorial_done("C_DROP_KNEE_T"), "튜토리얼 완료 저장")
	runner.check(SaveStore.load(SAVE).unlocked_buttons(flow.index) == ([&"T_DROP_KNEE"] as Array[StringName]), "버튼 해금 반영")
	_cleanup()


func test_next_route_and_list_target() -> void:
	var flow := _flow()
	runner.check(flow.next_route_id("G_V0_01") == "G_V0_02", "같은 등급 다음 문제")
	runner.check(flow.next_route_id("G_V0_02") == "", "마지막 문제: 다음 없음")
	runner.check(flow.next_route_id("C_OUTSIDE_EDGE_T") == "C_OUTSIDE_EDGE_1", "튜토리얼 다음은 쉬움")
	runner.check(flow.next_route_id("C_OUTSIDE_EDGE_1") == "", "다음 슬롯 파일 없음: 다음 없음")
	runner.check(flow.list_target("G_V0_02") == {"tab": "general", "grade": "V0"}, "일반 목록 위치")
	runner.check(flow.list_target("C_OUTSIDE_EDGE_1") == {"tab": "technique", "course": "C_OUTSIDE_EDGE"}, "과정 화면 위치")
	_cleanup()


func test_skip_basic_and_tab_saved() -> void:
	_cleanup()
	var flow := PlayFlow.new(_index(), Progress.new(), SAVE)
	runner.check(flow.progress.is_first_run(), "처음엔 첫 실행")
	flow.skip_basic()
	flow.set_last_tab("technique")
	var loaded := SaveStore.load(SAVE)
	runner.check(not loaded.is_first_run() and loaded.last_tab == "technique", "건너뛰기·마지막 탭 저장")
	_cleanup()


func test_attempt_resets_on_respawn_and_retry() -> void:
	var a := PlayAttempt.new()
	a.start(0)
	a.tick(0.5, false)
	runner.check(is_equal_approx(a.seconds, 0.5), "시간이 흐름")
	a.on_result("fall:NO_SUPPORT", 1)
	runner.check(a.falls(1) == 1 and is_equal_approx(a.seconds, 0.5), "추락 직후는 같은 시도")
	a.on_result("respawn", 1)
	runner.check(a.seconds == 0.0 and a.falls(1) == 0, "자동 재시작은 새 시도")
	a.tick(1.0, false)
	a.start(3)  # [다시]
	runner.check(a.seconds == 0.0 and a.falls(3) == 0, "[다시]는 새 시도")


func test_attempt_time_stops_while_selecting() -> void:
	var a := PlayAttempt.new()
	a.start(0)
	runner.check(a.tick(0.5, true) == 0.0 and a.seconds == 0.0, "고르는 중: 시간·observe dt 0")
	runner.check(is_equal_approx(a.tick(0.25, false), 0.25), "고르기 끝나면 흐름")


## 튜토리얼은 멈춤 없이 시작한다(사용자 결정 2026-11-04): 시도 시간은 바로 흐르고, 목표 홀드 키는 계속 반짝여 표시한다.
func test_tutorial_goal_mark_no_pause() -> void:
	var a := PlayAttempt.new()
	a.start(0)
	runner.check(is_equal_approx(a.tick(0.5, false), 0.5) and is_equal_approx(a.seconds, 0.5), "멈춤 없음: 바로 시간이 흐름")
	var r := RouteDef.load_json(G_PATH)
	var key: String = r.slots.keys()[0]
	runner.check(PlayAttempt.goal_slot({"goal_event": {"type": "grab", "slot": key}}, r) == key, "목표 홀드 표시")
	runner.check(PlayAttempt.goal_slot({"goal_event": {"type": "clear"}}, r) == "", "홀드 없는 목표")
	runner.check(PlayAttempt.goal_slot({"goal_event": {"type": "grab", "slot": "없음"}}, r) == "", "없는 홀드")


## 반짝임은 0~1 사이를 계속 오가고, 안내 줄은 목표 홀드가 화면 위쪽이면 아래로 내려간다.
func test_overlay_pulse_and_band_placement() -> void:
	var lo := 1.0
	var hi := 0.0
	for i in 100:
		var p: float = PlayOverlay.pulse(i * 0.01)
		lo = minf(lo, p)
		hi = maxf(hi, p)
	runner.check(lo >= 0.0 and hi <= 1.0 and hi - lo > 0.9, "반짝임 범위 %.2f~%.2f" % [lo, hi])
	runner.check(PlayOverlay.band_on_top(-1.0, 1000.0), "목표 홀드 없음 → 위")
	runner.check(not PlayOverlay.band_on_top(200.0, 1000.0), "목표가 위쪽 → 안내 줄은 아래")
	runner.check(PlayOverlay.band_on_top(700.0, 1000.0), "목표가 아래쪽 → 안내 줄은 위")
