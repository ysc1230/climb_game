extends RefCounted
## docs/28 §8: 문제 파일 필드·검증, 과정 목록, ContentIndex 정렬·조회.

var runner
const G_PATH := "res://data/routes/general/G_V0_01.json"
const FIXTURE := "user://test_content_index"


func _base() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(G_PATH))


## 과정 튜토리얼 형태의 최소 문제 데이터(G_V0_01 벽을 그대로 쓴다).
func _course_dict(slot := "tutorial") -> Dictionary:
	var d := _base()
	d.mode = "course"
	d.course_id = "C_DROP_KNEE"
	d.course_slot = slot
	d.required_techniques = ["T_DROP_KNEE"]
	if slot == "tutorial":
		d.tutorial_steps = [{"step_id": "S1", "text_ko": "드롭니를 해 보세요.", "goal_event": {"type": "technique", "id": "T_DROP_KNEE"}, "help_ko": ["왼발", "드롭니 버튼"]}]
	return d


func _errors_of(d: Dictionary) -> PackedStringArray:
	return RouteDef.from_dict(d).errors


func _has_error(errs: PackedStringArray, part: String) -> bool:
	for e in errs:
		if e.contains(part):
			return true
	return false


# --- RouteDef 필드 ---

func test_g_v0_01_fields() -> void:
	var r := RouteDef.load_json(G_PATH)
	runner.check(r.errors.is_empty(), "저작 오류: %s" % [r.errors])
	runner.check(r.route_id == "G_V0_01" and r.content_version == 5, "id·버전 %s %d" % [r.route_id, r.content_version])
	runner.check(r.mode == "general" and r.grade == "V0" and r.order == 1, "mode·grade·order %s %s %d" % [r.mode, r.grade, r.order])
	runner.check(r.name_ko == "첫 번째 벽", "name_ko %s" % r.name_ko)
	runner.check(r.required_techniques.is_empty() and r.check_swapped, "기술 없음·좌우 교체 검사")
	runner.check(r.course_id == "" and r.course_slot == "" and r.tutorial_steps.is_empty() and r.crux_steps.is_empty(), "과정 필드 비어 있음")
	runner.check(r.steps_raw.size() == 10 and r.steps_raw[0] == ["LH", "G_V0_01/H03/hand_1"], "steps_raw 원본 %s" % [r.steps_raw.slice(0, 1)])
	runner.check(r.intended_moves[0] == [&"LH", "G_V0_01/H03/hand_1"] and r.intended_moves[0][0] is StringName, "intended_moves는 지금처럼")


func test_course_fields_read() -> void:
	var d := _course_dict("easy")
	d.grade = "V2"
	d.order = 2
	d.check_swapped = false
	d.intended_moves.insert(0, ["LF", "T_DROP_KNEE"])
	d.crux_steps = {"T_DROP_KNEE": 0}
	var r := RouteDef.from_dict(d)
	runner.check(r.errors.is_empty(), "오류 없음: %s" % [r.errors])
	runner.check(r.mode == "course" and r.course_id == "C_DROP_KNEE" and r.course_slot == "easy", "과정 필드")
	runner.check(r.required_techniques == ([&"T_DROP_KNEE"] as Array[StringName]), "required_techniques %s" % [r.required_techniques])
	runner.check(r.crux_steps.get(&"T_DROP_KNEE", -1) == 0, "crux_steps %s" % [r.crux_steps])
	runner.check(not r.check_swapped, "check_swapped false")
	runner.check(r.steps_raw[0] == ["LF", "T_DROP_KNEE"] and r.intended_moves.size() == 11, "기술 단계도 같은 인덱스로 보관")


func test_check_swapped_default_false() -> void:
	var d := _base()
	d.erase("check_swapped")
	runner.check(not RouteDef.from_dict(d).check_swapped, "기본 false")


# --- 검증 ---

func test_rejects_bad_mode_and_grade() -> void:
	var d := _base()
	d.mode = "free"
	runner.check(_has_error(_errors_of(d), "mode"), "mode 오류")
	for g in ["v0", "V", "VX", "0", ""]:
		d = _base()
		d.grade = g
		runner.check(_has_error(_errors_of(d), "grade"), "grade %s 오류" % g)
	d = _base()
	d.grade = "V12"
	runner.check(_errors_of(d).is_empty(), "V12 허용")


func test_course_requires_course_id_and_slot() -> void:
	var d := _course_dict("easy")
	d.erase("course_id")
	runner.check(_has_error(_errors_of(d), "course_id"), "course_id 필수")
	d = _course_dict("easy")
	d.course_slot = "extreme"
	runner.check(_has_error(_errors_of(d), "course_slot"), "course_slot 값 오류")
	d = _course_dict("easy")
	d.erase("course_slot")
	runner.check(_has_error(_errors_of(d), "course_slot"), "course_slot 필수")
	d = _base()
	d.course_id = "C_CROSS"
	runner.check(_has_error(_errors_of(d), "course_id"), "일반 문제에는 course_id 없음")


func test_required_techniques_must_exist() -> void:
	var d := _base()
	d.required_techniques = ["T_NOPE"]
	runner.check(_has_error(_errors_of(d), "T_NOPE"), "없는 기술 오류")


func test_crux_steps_subset_and_range() -> void:
	var d := _course_dict("easy")
	d.crux_steps = {"T_CROSS": 0}
	runner.check(_has_error(_errors_of(d), "crux_steps"), "required_techniques 밖 키")
	d = _course_dict("easy")
	d.crux_steps = {"T_DROP_KNEE": 10}
	runner.check(_has_error(_errors_of(d), "crux_steps"), "인덱스 범위 밖(10단계)")
	d = _course_dict("easy")
	d.crux_steps = {"T_DROP_KNEE": -1}
	runner.check(_has_error(_errors_of(d), "crux_steps"), "음수 인덱스")
	d = _course_dict("easy")
	d.crux_steps = {"T_DROP_KNEE": 9}
	runner.check(_errors_of(d).is_empty(), "마지막 인덱스 허용: %s" % [_errors_of(d)])


func test_tutorial_steps_only_for_tutorial() -> void:
	var d := _course_dict("tutorial")
	runner.check(_errors_of(d).is_empty(), "튜토리얼 정상: %s" % [_errors_of(d)])
	d.tutorial_steps = []
	runner.check(_has_error(_errors_of(d), "tutorial_steps"), "튜토리얼은 단계 필수")
	d = _course_dict("easy")
	d.tutorial_steps = [{"step_id": "S1"}]
	runner.check(_has_error(_errors_of(d), "tutorial_steps"), "튜토리얼 아닌 문제에 단계 금지")
	d = _base()
	d.tutorial_steps = [{"step_id": "S1"}]
	runner.check(_has_error(_errors_of(d), "tutorial_steps"), "일반 문제에 단계 금지")


func test_step_formats_valid() -> void:
	var d := _base()
	d.intended_moves = [
		["LF", "T_DROP_KNEE"],
		["RF", "T_OUTSIDE_EDGE", "G_V0_01/F04/foot_1"],
		["RH", "G_V0_01/H04/hand_1", "deadpoint"],
		["LF", "flag", [-0.4, 0.5]],
		["LH", "G_V0_01/H03/hand_1"],
	]
	var r := RouteDef.from_dict(d)
	runner.check(r.errors.is_empty(), "다섯 형식 모두 허용: %s" % [r.errors])
	runner.check(r.steps_raw.size() == 5 and r.steps_raw[3] == ["LF", "flag", [-0.4, 0.5]], "원본 보관")


func test_step_formats_invalid() -> void:
	var bad := {
		"없는 기술": ["LF", "T_NOPE"],
		"홀드로 옮기는 없는 기술": ["LF", "T_NOPE", "G_V0_01/F04/foot_1"],
		"기술 대상 슬롯 없음": ["RF", "T_OUTSIDE_EDGE", "G_V0_01/F99/foot_1"],
		"기술 대상 슬롯 팔다리 비허용": ["RF", "T_OUTSIDE_EDGE", "G_V0_01/H04/hand_1"],
		"데드포인트는 손만": ["RF", "G_V0_01/F04/foot_1", "deadpoint"],
		"데드포인트 슬롯 없음": ["RH", "G_V0_01/H99/hand_1", "deadpoint"],
		"플래그는 발만": ["LH", "flag", [0.0, 1.0]],
		"플래그 좌표 형식": ["LF", "flag", [0.0]],
		"플래그 좌표 숫자 아님": ["LF", "flag", ["a", 1.0]],
		"모르는 팔다리": ["XX", "G_V0_01/H03/hand_1"],
		"짧은 단계": ["LH"],
		"알 수 없는 3항목": ["LH", "G_V0_01/H03/hand_1", "dyno"],
		"패드 이동 비허용": ["LF", "G_V0_01/H01/hand_1"],
		"너무 긴 단계": ["LF", "T_OUTSIDE_EDGE", "G_V0_01/F04/foot_1", 1],
	}
	for label in bad:
		var d := _base()
		d.intended_moves = [bad[label]]
		var errs := _errors_of(d)
		runner.check(errs.size() > 0, "%s: 오류여야 함" % label)


# --- 과정 목록 ---

func test_courses_json_content() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/courses.json"))
	var list: Array = data.courses
	var ids := list.map(func(c): return c.course_id)
	runner.check(ids == ["C_BASIC", "C_HIGH_STEP", "C_CROSS", "C_FLAG", "C_OUTSIDE_EDGE", "C_DROP_KNEE", "C_MATCH", "C_FOOT_SWAP", "C_LOCK_OFF", "C_DIRECTION", "C_DEADPOINT"], "순서 %s" % [ids])
	var defs := TechniqueDefs.load_all()
	for c in list:
		for t in c.techniques:
			runner.check(defs.has(StringName(t)), "%s 기술 %s 있음" % [c.course_id, t])
		if int(c.phase) == 1 and c.course_id != "C_BASIC":
			runner.check(c.tutorial == c.course_id + "_T" and c.problems == [c.course_id + "_1", c.course_id + "_2", c.course_id + "_3"], "%s 경로 id" % c.course_id)
	var by := {}
	for c in list:
		by[c.course_id] = c
	runner.check(by.C_BASIC.kind == "pad" and by.C_BASIC.techniques.is_empty() and by.C_BASIC.problems.is_empty() and by.C_BASIC.tutorial == "C_BASIC_T", "C_BASIC")
	runner.check(by.C_OUTSIDE_EDGE.kind == "button" and by.C_DROP_KNEE.kind == "button" and by.C_FLAG.kind == "pad", "종류")
	runner.check(by.C_DIRECTION.techniques == ["T_SIDEPULL", "T_GASTON", "T_UNDERCLING"], "방향 홀드 기술")
	for id in ["C_BASIC", "C_DIRECTION"]:
		var t: Dictionary = by[id].get("text_ko", {})
		runner.check(t.get("purpose", "") != "" and t.get("when", "") != "" and t.get("how", "") != "", "%s 자체 문구" % id)
	for id in ["C_MATCH", "C_FOOT_SWAP", "C_LOCK_OFF", "C_DIRECTION", "C_DEADPOINT"]:
		runner.check(int(by[id].phase) == 2 and by[id].tutorial == "" and by[id].problems.is_empty(), "%s 2차 빈 항목" % id)


# --- ContentIndex ---

func test_index_real_data() -> void:
	var idx := ContentIndex.load_all()
	runner.check(idx.grades() == (["V0"] as Array[String]), "등급 %s" % [idx.grades()])
	var g := idx.general("V0")
	runner.check(g.size() == 1 and g[0].route_id == "G_V0_01", "V0 문제")
	runner.check(idx.route("G_V0_01") == g[0], "route 조회")
	runner.check(idx.route("NOPE") == null, "없는 route null")
	runner.check(idx.general("V9").is_empty(), "없는 등급 빈 배열")
	var ids := idx.courses().map(func(c): return c.course_id)
	runner.check(ids == ["C_BASIC", "C_HIGH_STEP", "C_CROSS", "C_FLAG", "C_OUTSIDE_EDGE", "C_DROP_KNEE"], "2차 숨김 %s" % [ids])
	runner.check(idx.course("C_DROP_KNEE").kind == "button", "course 조회")
	runner.check(idx.course("C_MATCH").phase == 2, "숨긴 과정도 id로는 조회")
	runner.check(idx.course("C_NOPE").is_empty(), "없는 과정 빈 사전")


## 과정 문제 파일은 Task 9~10에서 만든다. 그전까지 없는 파일은 errors에 남기고 멈추지 않는다.
func test_index_tolerates_missing_course_routes() -> void:
	var idx := ContentIndex.load_all()
	runner.check(_has_error(idx.errors, "C_DROP_KNEE_T") and _has_error(idx.errors, "C_HIGH_STEP_3"), "없는 문제 파일 기록: %s" % [idx.errors.slice(0, 3)])
	runner.check(not _has_error(idx.errors, "C_MATCH"), "2차 빈 항목은 오류 아님")
	runner.check(not _has_error(idx.errors, "G_V0_01"), "G_V0_01 오류 없음")


func test_route_path() -> void:
	runner.check(ContentIndex.route_path("G_V0_01") == "res://data/routes/general/G_V0_01.json", "일반")
	runner.check(ContentIndex.route_path("C_DROP_KNEE_T") == "res://data/routes/course/C_DROP_KNEE_T.json", "과정")
	runner.check(ContentIndex.route_path("TX_TECH") == "res://data/routes/TX_TECH.json", "시험용")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _general_copy(id: String, grade: String, order: int) -> String:
	var d := _base()
	d.grade = grade
	d.order = order
	return JSON.stringify(d).replace("G_V0_01", id)


func test_index_sorting_and_bad_files() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURE + "/routes/general")
	DirAccess.make_dir_recursive_absolute(FIXTURE + "/routes/course")
	for f in DirAccess.get_files_at(FIXTURE + "/routes/general"):
		DirAccess.remove_absolute(FIXTURE + "/routes/general/" + f)
	_write(FIXTURE + "/routes/general/G_V1_02.json", _general_copy("G_V1_02", "V1", 2))
	_write(FIXTURE + "/routes/general/G_V1_01.json", _general_copy("G_V1_01", "V1", 1))
	_write(FIXTURE + "/routes/general/G_V10_01.json", _general_copy("G_V10_01", "V10", 1))
	_write(FIXTURE + "/routes/general/G_V0_01.json", _general_copy("G_V0_01", "V0", 1))
	_write(FIXTURE + "/routes/general/G_BAD.json", "{ not json")
	var c := _course_dict("tutorial")
	c.route_id = "C_X_T"
	c.course_id = "C_X"
	c.grade = "V2"
	_write(FIXTURE + "/routes/course/C_X_T.json", JSON.stringify(c).replace("G_V0_01/", "C_X_T/"))
	_write(FIXTURE + "/courses.json", JSON.stringify({"courses": [
		{"course_id": "C_X", "order": 0, "name_ko": "엑스", "kind": "button", "techniques": ["T_DROP_KNEE"], "tutorial": "C_X_T", "problems": ["C_X_1"], "phase": 1},
		{"course_id": "C_Y", "order": 1, "name_ko": "와이", "kind": "pad", "techniques": [], "tutorial": "", "problems": [], "phase": 2}]}))
	var idx := ContentIndex.load_all(FIXTURE)
	runner.check(idx.grades() == (["V0", "V1", "V10"] as Array[String]), "등급 숫자 순 %s" % [idx.grades()])
	var v1 := idx.general("V1").map(func(r): return r.route_id)
	runner.check(v1 == ["G_V1_01", "G_V1_02"], "order 순 %s" % [v1])
	runner.check(_has_error(idx.errors, "G_BAD"), "파싱 실패 기록")
	runner.check(_has_error(idx.errors, "C_X_1") and not _has_error(idx.errors, "C_X_T"), "없는 문제만 기록: %s" % [idx.errors])
	runner.check(idx.route("C_X_T") != null and idx.route("C_X_T").course_slot == "tutorial", "과정 문제 조회")
	runner.check(idx.courses().size() == 1 and idx.course("C_Y").phase == 2, "phase 2 숨김")
	runner.check(idx.general("V1").all(func(r): return r.mode == "general"), "general은 일반만")


func test_index_missing_root_does_not_crash() -> void:
	var idx := ContentIndex.load_all("user://no_such_content_root")
	runner.check(idx.grades().is_empty() and idx.courses().is_empty() and idx.errors.size() > 0, "빈 목록 + 오류")
