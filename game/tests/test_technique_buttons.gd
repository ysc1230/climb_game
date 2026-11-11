extends RefCounted
## docs/28 §4: 기술 버튼은 아웃사이드 엣지·드롭니 2개만 남고, 나머지는 패드 기술로 설명만 남는다.

var runner

const REMOVED: Array[StringName] = [&"T_HIGH_STEP", &"T_LOCK_OFF", &"T_REST", &"T_CROSS", &"T_MATCH", &"T_FOOT_SWAP",
	&"T_INSIDE_EDGE", &"T_SIDEPULL", &"T_GASTON", &"T_UNDERCLING", &"T_FLAG"]


func test_button_ids() -> void:
	var ids := TechniqueDefs.button_ids()
	runner.check(ids == [&"T_OUTSIDE_EDGE", &"T_DROP_KNEE"], "버튼 기술 2개: %s" % [ids])


func test_every_entry_has_input() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(TechniqueDefs.PATH))
	runner.check(typeof(data) == TYPE_DICTIONARY, "JSON 파싱")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var ids := []
	for d in data.techniques:
		ids.append(d.id)
		runner.check(d.get("input", "") in ["button", "pad"], "%s input: %s" % [d.id, d.get("input", "")])
	runner.check(not ids.has("T_FLAG_INSIDE") and not ids.has("T_FLAG_OUTSIDE"), "인사이드·아웃사이드 플래그 항목 없음: %s" % [ids])
	var defs := TechniqueDefs.load_all()
	runner.check(defs[&"T_DROP_KNEE"].input == &"button" and defs[&"T_HIGH_STEP"].input == &"pad", "load_all이 input을 읽음")


func test_removed_buttons_rejected() -> void:
	var s := ClimbSession.new(RouteDef.load_json("res://tests/fixtures/G_V0_01.json"))
	for id in REMOVED:
		var why := s.runner.start(s, id, &"left")
		runner.check(why == &"NOT_BUTTON", "%s → NOT_BUTTON (%s)" % [id, why])
		runner.check(s.runner.active.is_empty(), "%s 실행 없음" % id)
