extends RefCounted
## docs/28 §5.3·§6·§7.2·§9: 진행 기록·해금 계산·저장. MG01~MG06·MG14·MG15.

var runner
const FIX := "user://test_progress_fixture"
const SAVE := "user://test_save.json"
const G_PATH := "res://data/routes/general/G_V0_01.json"


func _base() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(G_PATH))


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _general(id: String, grade: String, order: int, techs := []) -> void:
	var d := _base()
	d.route_id = id
	d.grade = grade
	d.order = order
	d.required_techniques = techs
	_write("%s/routes/general/%s.json" % [FIX, id], d)


func _course_route(id: String, slot: String) -> void:
	var d := _base()
	d.route_id = id
	d.mode = "course"
	d.course_id = id.substr(0, id.rfind("_"))
	d.course_slot = slot
	d.erase("grade")
	d.erase("order")
	d.required_techniques = []
	if slot == "tutorial":
		d.tutorial_steps = [{"step_id": "S1", "text_ko": "해 보세요.", "goal_event": {"type": "technique", "id": "T_DROP_KNEE"}, "help_ko": ["a", "b"]}]
	_write("%s/routes/course/%s.json" % [FIX, id], d)


func _index() -> ContentIndex:
	for i in 4:
		_general("G_V0_0%d" % (i + 1), "V0", i + 1)
	for i in 2:
		_general("G_V1_0%d" % (i + 1), "V1", i + 1, ["T_DROP_KNEE"] if i == 0 else [])
	_course_route("C_BASIC_T", "tutorial")
	_course_route("C_DROP_KNEE_T", "tutorial")
	_course_route("C_DROP_KNEE_1", "easy")
	_course_route("C_DROP_KNEE_2", "normal")
	_course_route("C_DROP_KNEE_3", "hard")
	_write(FIX + "/courses.json", {"courses": [
		{"course_id": "C_BASIC", "order": 0, "name_ko": "기본 조작", "kind": "pad", "techniques": [], "tutorial": "C_BASIC_T", "problems": [], "phase": 1},
		{"course_id": "C_DROP_KNEE", "order": 1, "name_ko": "드롭니", "kind": "button", "techniques": ["T_DROP_KNEE"], "tutorial": "C_DROP_KNEE_T",
			"problems": ["C_DROP_KNEE_1", "C_DROP_KNEE_2", "C_DROP_KNEE_3"], "phase": 1}]})
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


func test_particle() -> void:
	runner.check(Progress.object_particle("드롭니") == "를", "드롭니 -> 를")
	runner.check(Progress.object_particle("아웃사이드 엣지") == "를", "엣지 -> 를")
	runner.check(Progress.object_particle("하이스텝") == "을", "하이스텝 -> 을")
	runner.check(Progress.object_particle("크로스") == "를", "크로스 -> 를")
	runner.check(Progress.object_particle("플래그") == "를", "플래그 -> 를")


func test_first_run_and_skip() -> void:
	var idx := _index()
	var p := Progress.new()
	runner.check(p.is_first_run() and not p.grade_unlocked("V0", idx), "MG01 첫 실행: V0 잠김")
	runner.check(p.route_lock_text(idx.route("C_BASIC_T"), idx) == "", "첫 실행에도 기본 조작은 열림")
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_T"), idx) != "", "첫 실행: 다른 과정 잠김")
	p.record_tutorial("C_BASIC_T")
	runner.check(not p.is_first_run() and p.grade_unlocked("V0", idx), "기본 조작 완료 후 V0 열림")
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_T"), idx) == "", "과정 튜토리얼 열림")
	var q := Progress.new()
	q.skip_basic()
	runner.check(not q.is_first_run() and q.grade_unlocked("V0", idx), "MG02 건너뛰기: V0 열림")
	runner.check(q.route_lock_text(idx.route("C_DROP_KNEE_T"), idx) == "", "건너뛰기: 과정 열림")
	_cleanup()


func test_grade_unlock_two_of_four() -> void:
	var idx := _index()
	var p := Progress.new()
	p.skip_basic()
	p.record_clear(idx.route("G_V0_01"), 30.0, 0)
	runner.check(not p.grade_unlocked("V1", idx), "MG03 1개: V1 잠김")
	runner.check(p.grade_lock_text("V1", idx) == "V0에서 1개 더 완등하면 열려요", "MG03 문구: %s" % p.grade_lock_text("V1", idx))
	p.record_clear(idx.route("G_V0_02"), 30.0, 1)
	runner.check(p.grade_unlocked("V1", idx) and p.grade_lock_text("V1", idx) == "", "MG04 2개: V1 열림")
	runner.check(p.grade_lock_text("V0", idx) == "", "열린 등급 문구 없음")
	_cleanup()


func test_unlocked_buttons_after_tutorial() -> void:
	var idx := _index()
	var p := Progress.new()
	runner.check(p.unlocked_buttons(idx).is_empty(), "MG07 처음엔 버튼 없음")
	p.record_tutorial("C_BASIC_T")
	runner.check(p.unlocked_buttons(idx).is_empty(), "기본 조작은 버튼 해금 없음")
	p.record_tutorial("C_DROP_KNEE_T")
	runner.check(p.unlocked_buttons(idx) == ([&"T_DROP_KNEE"] as Array[StringName]), "MG06 드롭니만: %s" % [p.unlocked_buttons(idx)])
	_cleanup()


func test_route_locked_by_button_technique() -> void:
	var idx := _index()
	var p := Progress.new()
	p.skip_basic()
	for id in ["G_V0_01", "G_V0_02"]:
		p.record_clear(idx.route(id), 30.0, 0)
	var r := idx.route("G_V1_01")
	runner.check(p.route_lock_text(r, idx) == "드롭니를 배우면 열려요", "MG05 문구: %s" % p.route_lock_text(r, idx))
	runner.check(p.route_lock_text(idx.route("G_V1_02"), idx) == "", "기술 없는 문제는 열림")
	p.record_tutorial("C_DROP_KNEE_T")
	runner.check(p.route_lock_text(r, idx) == "", "튜토리얼 후 열림")
	var q := Progress.new()
	q.skip_basic()
	runner.check(q.route_lock_text(r, idx) == "V0에서 2개 더 완등하면 열려요", "등급 잠금이 먼저: %s" % q.route_lock_text(r, idx))
	_cleanup()


func test_course_slot_order() -> void:
	var idx := _index()
	var p := Progress.new()
	p.skip_basic()
	var msg := "앞 단계를 먼저 깨 주세요"
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_T"), idx) == "", "튜토리얼 열림")
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_1"), idx) == msg, "easy 잠김")
	p.record_tutorial("C_DROP_KNEE_T")
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_1"), idx) == "", "튜토리얼 후 easy 열림")
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_2"), idx) == msg, "normal 잠김")
	p.record_clear(idx.route("C_DROP_KNEE_1"), 20.0, 0)
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_2"), idx) == "", "easy 후 normal 열림")
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_3"), idx) == msg, "hard 잠김")
	p.record_clear(idx.route("C_DROP_KNEE_2"), 20.0, 0)
	runner.check(p.route_lock_text(idx.route("C_DROP_KNEE_3"), idx) == "", "normal 후 hard 열림")
	_cleanup()


func test_record_keeps_best() -> void:
	var r := RouteDef.from_dict(_base())
	r.time_medal_seconds = 40.0
	var p := Progress.new()
	p.record_clear(r, 50.0, 0)
	runner.check(p.cleared.G_V0_01.no_fall and not p.cleared.G_V0_01.time, "무낙하 O, 시간 X")
	p.record_clear(r, 35.0, 2)
	var c: Dictionary = p.cleared.G_V0_01
	runner.check(c.no_fall and c.time, "메달 유지·추가")
	runner.check(is_equal_approx(c.best_seconds, 35.0), "최고 시간 갱신 %s" % c.best_seconds)
	p.record_clear(r, 60.0, 0)
	runner.check(is_equal_approx(p.cleared.G_V0_01.best_seconds, 35.0), "느린 기록은 갱신 안 함")
	var r2 := RouteDef.from_dict(_base())
	r2.time_medal_seconds = 0.0
	var q := Progress.new()
	q.record_clear(r2, 1.0, 1)
	runner.check(not q.cleared.G_V0_01.time and not q.cleared.G_V0_01.no_fall, "시간 기준 없으면 시간 메달 없음")


func test_save_roundtrip() -> void:
	_cleanup()
	var idx := _index()
	var p := Progress.new()
	p.skip_basic()
	p.record_clear(idx.route("G_V0_01"), 33.5, 0)
	p.record_tutorial("C_DROP_KNEE_T")
	p.last_tab = "technique"
	runner.check(SaveStore.save(p, SAVE), "저장 성공")
	runner.check(not FileAccess.file_exists(SAVE + ".tmp"), "임시 파일 남지 않음")
	var q := SaveStore.load(SAVE)
	runner.check(q.seq == 1 and q.basic_skipped and q.last_tab == "technique", "MG14 필드 복원")
	runner.check(q.is_cleared("G_V0_01") and is_equal_approx(q.cleared.G_V0_01.best_seconds, 33.5) and q.cleared.G_V0_01.no_fall, "완등·메달 복원")
	runner.check(q.tutorial_done("C_DROP_KNEE_T") and q.unlocked_buttons(idx) == ([&"T_DROP_KNEE"] as Array[StringName]), "해금 복원")
	SaveStore.save(q, SAVE)
	runner.check(SaveStore.load(SAVE).seq == 2, "저장마다 seq+1")
	_cleanup()


func test_load_corrupt_file_starts_fresh() -> void:
	_cleanup()
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var p := SaveStore.load(SAVE)
	runner.check(p.is_first_run() and p.cleared.is_empty() and p.seq == 0, "파손 파일 → 새 기록")
	_write(SAVE, {"schema_version": 99, "basic_skipped": true})
	runner.check(SaveStore.load(SAVE).is_first_run(), "schema 불일치 → 새 기록")
	_cleanup()
	runner.check(SaveStore.load(SAVE).is_first_run(), "파일 없음 → 새 기록")


func test_tmp_left_behind_keeps_previous() -> void:
	_cleanup()
	var p := Progress.new()
	p.skip_basic()
	SaveStore.save(p, SAVE)
	var f := FileAccess.open(SAVE + ".tmp", FileAccess.WRITE)
	f.store_string('{"schema_version":1,"seq":9,"basic_skip')   # 쓰다 만 임시 파일
	f.close()
	var q := SaveStore.load(SAVE)
	runner.check(q.basic_skipped and q.seq == 1, "MG15 본 파일 유지")
	runner.check(SaveStore.save(q, SAVE) and SaveStore.load(SAVE).seq == 2, "임시 파일이 있어도 다음 저장 성공")
	_cleanup()
