extends RefCounted
## docs/28 §5.3·§6·§7.2·§9: 진행 기록·해금 계산·저장. MG01~MG06·MG14·MG15.

var runner
const FIX := "user://test_progress_fixture"
const SAVE := "user://test_save.json"
const G_PATH := "res://tests/fixtures/G_V0_01.json"


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


## 문제가 없는 등급은 건너뛴다: V1이 비면 V2는 V0 완등으로 열리고, 앞 등급 문제가 2개보다 적으면 전부 완등해야 한다.
func test_grade_unlock_skips_empty_grade() -> void:
	_general("G_V0_01", "V0", 1)
	_general("G_V2_01", "V2", 1)
	_general("G_V3_01", "V3", 1)
	_general("G_V3_02", "V3", 2)
	_general("G_V3_03", "V3", 3)
	_write(FIX + "/courses.json", {"courses": []})
	var idx := ContentIndex.load_all(FIX)
	var p := Progress.new()
	p.skip_basic()
	runner.check(p.prerequisite_grade("V2", idx) == "V0", "V2의 앞 등급은 V0(V1 비어 있음): %s" % p.prerequisite_grade("V2", idx))
	runner.check(not p.grade_unlocked("V2", idx), "V0 완등 0개: V2 잠김")
	runner.check(p.grade_lock_text("V2", idx) == "V0에서 1개 더 완등하면 열려요", "V0 문제 1개면 1개 필요: %s" % p.grade_lock_text("V2", idx))
	p.record_clear(idx.route("G_V0_01"), 30.0, 0)
	runner.check(p.grade_unlocked("V2", idx) and p.grade_lock_text("V2", idx) == "", "V0 1개 전부 완등: V2 열림")
	runner.check(not p.grade_unlocked("V3", idx), "V2 0개: V3 잠김")
	runner.check(p.grade_lock_text("V3", idx) == "V2에서 1개 더 완등하면 열려요", "V3 문구: %s" % p.grade_lock_text("V3", idx))
	p.record_clear(idx.route("G_V2_01"), 30.0, 0)
	runner.check(p.grade_unlocked("V3", idx), "V2 1개 전부 완등: V3 열림")
	runner.check(not p.grade_unlocked("V4", idx) and p.grade_lock_text("V4", idx) == "V3에서 2개 더 완등하면 열려요", "V3 문제 3개면 2개 필요: %s" % p.grade_lock_text("V4", idx))
	p.record_clear(idx.route("G_V3_02"), 30.0, 0)
	p.record_clear(idx.route("G_V3_03"), 30.0, 0)
	runner.check(p.grade_unlocked("V4", idx), "V3 2개: V4 열림")
	var q := Progress.new()
	# 2026-11-11: 기본 조작 튜토리얼이 없으면(이 색인은 과정 없음) 첫 실행이어도 V0을 잠그지 않는다(Progress.first_run_locked).
	runner.check(q.grade_unlocked("V0", idx) and q.grade_lock_text("V2", idx) == "V0에서 1개 더 완등하면 열려요", "튜토리얼 없는 첫 실행: V0 열림, V2 문구는 V0 기준")
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


## 화면 표시 설정(docs/49): 기본값, 켜고 끄기, 저장·불러오기, 모르는 키는 버림.
func test_display_settings() -> void:
	var p := Progress.new()
	runner.check(p.display_on("balance") and p.display_on("balance_hint") and not p.display_on("loads"), "기본: 무게중심·안내 켜짐, 힘 분포 꺼짐")
	p.display["loads"] = true
	p.display["balance"] = false
	var q := Progress.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	runner.check(q.display_on("loads") and not q.display_on("balance") and q.display_on("balance_hint"), "저장 뒤에도 그대로")
	var r := Progress.from_dict({"display": {"nope": true, "loads": true}})
	runner.check(not r.display.has("nope") and r.display_on("loads"), "모르는 키는 버림")


## 몸 옮기기 설정(작업 2): 기본은 가운데 끌기·민감도 3·반응 3°·함께 쓰기 켜짐, 범위 밖 값은 고침, 저장·불러오기.
func test_control_settings() -> void:
	var p := Progress.new()
	runner.check(p.control_get("body") == "drag" and int(p.control_get("tilt_sens")) == 3 and is_equal_approx(float(p.control_get("tilt_dead")), 3.0) and bool(p.control_get("tilt_with_drag")), "기본값 %s" % [p.control])
	p.set_control("body", "tilt")
	p.set_control("tilt_sens", 9)
	p.set_control("tilt_dead", -2)
	runner.check(p.control_get("body") == "tilt" and int(p.control_get("tilt_sens")) == 5 and is_equal_approx(float(p.control_get("tilt_dead")), 0.0), "범위로 자름 %s" % [p.control])
	var q := Progress.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	runner.check(q.control_get("body") == "tilt" and int(q.control_get("tilt_sens")) == 5, "저장 뒤에도 그대로 %s" % [q.control])
	var r := Progress.from_dict({"control": {"body": "nope", "x": 1, "tilt_dead": 20}})
	runner.check(r.control_get("body") == "drag" and not r.control.has("x") and is_equal_approx(float(r.control_get("tilt_dead")), 10.0), "모르는 값·키는 버리고 범위로 %s" % [r.control])


## 작업 3 저장(판 2): 시도 통계·플래시·최고 점수·도움·문제 판 바뀜·기록 지우기.
func _v(id := "G_V3_03") -> RouteDef:
	return RouteDef.load_json(ContentIndex.route_path(id))


func test_flash_and_best_score() -> void:
	var p := Progress.new()
	var r := _v()
	runner.check(p.start_attempt(r) == 1, "첫 시도")
	var res := p.record_clear(r, 80.0, 0, {"score": 70, "parts": {"energy": 20}})
	runner.check(res.flash and res.new_best_score and p.cleared[r.route_id].flash and p.cleared[r.route_id].best_score == 70, "첫 시도 완등은 플래시 %s" % [p.cleared[r.route_id]])
	p.start_attempt(r)
	res = p.record_clear(r, 60.0, 0, {"score": 65})
	runner.check(not res.flash and not res.new_best_score and res.new_best_time and p.cleared[r.route_id].best_score == 70 and p.cleared[r.route_id].flash, "점수는 최고 유지, 시간은 새 최고 %s" % [res])


func test_helped_clear_counts_but_no_records() -> void:
	var p := Progress.new()
	var r := _v()
	p.start_attempt(r)
	var res := p.record_clear(r, 50.0, 0, {"score": 90, "helped": true, "ghost": {"t": [0]}})
	var c: Dictionary = p.cleared[r.route_id]
	runner.check(p.is_cleared(r.route_id) and not res.flash and not c.has("best_score") and not c.has("best_seconds") and not c.has("ghost"), "도움 완등: 완등은 인정, 기록은 안 남김 %s" % [c])


func test_stats_and_falls() -> void:
	var p := Progress.new()
	var r := _v()
	p.start_attempt(r)
	for h in [1.2, 1.3, 2.0]:
		p.record_fall(r, h)
	runner.check(p.fall_count(r.route_id) == 3 and p.stats[r.route_id].fall_heights == [1.2, 1.3, 2.0], "추락 수·높이 %s" % [p.stats[r.route_id]])
	for i in 30:
		p.record_fall(r, 0.5)
	runner.check(p.stats[r.route_id].fall_heights.size() == 20, "높이는 최근 20개")
	runner.check(not p.is_cleared(r.route_id), "통계만 있으면 완등 아님(해금에 안 셈)")


func test_content_version_change() -> void:
	var p := Progress.new()
	var r := _v()
	p.start_attempt(r)
	p.record_fall(r, 1.0)
	p.record_clear(r, 50.0, 0, {"score": 80, "ghost": {"t": [0]}})
	r.content_version += 1
	runner.check(p.start_attempt(r) == 1 and p.fall_count(r.route_id) == 0, "판이 바뀌면 통계는 0부터")
	var res := p.record_clear(r, 70.0, 1, {"score": 60})
	var c: Dictionary = p.cleared[r.route_id]
	runner.check(c.best_score == 60 and c.prev.best_score == 80 and is_equal_approx(c.prev.best_seconds, 50.0) and not c.has("ghost"), "이전 판 기록으로 옮김 %s" % [c])
	runner.check(res.flash, "새 판의 첫 시도 완등은 플래시")


func test_wipe_route() -> void:
	var p := Progress.new()
	var r := _v()
	p.start_attempt(r)
	p.record_fall(r, 1.0)
	p.record_clear(r, 50.0, 0, {"score": 80})
	p.wipe_route(r.route_id)
	runner.check(not p.is_cleared(r.route_id) and p.fall_count(r.route_id) == 0 and not p.stats.has(r.route_id), "기록 지우기")


func test_schema_1_save_loads() -> void:
	var old := {"schema_version": 1, "seq": 3, "cleared": {"G_V0_02": {"content_version": 1, "no_fall": true, "time": false, "best_seconds": 42.0}}, "tutorials": {}, "level": "beginner"}
	var path := "user://test_schema1.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var p := SaveStore.load(path)
	runner.check(p.is_cleared("G_V0_02") and p.level == "beginner" and p.stats.is_empty(), "판 1 저장을 읽음 %s" % [p.to_dict()])
	runner.check(int(p.to_dict().schema_version) == Progress.SCHEMA_VERSION and Progress.SCHEMA_VERSION == 2, "다시 저장하면 판 2")
	DirAccess.remove_absolute(path)
