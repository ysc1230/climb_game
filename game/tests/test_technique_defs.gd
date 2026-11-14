extends RefCounted
## docs/27 §5·§7.3·§9.2 기술 정의 데이터 검사.

var runner
const KNOWN_REASONS: Array[StringName] = [&"WRONG_PHASE", &"LIMB_STATE", &"SUPPORT_NEEDED", &"NO_HOLD", &"JOINT_LIMIT",
	&"BODY_ORIENTATION_LIMIT", &"NEED_WEIGHT_SHIFT", &"SUPPORT_OVERLOAD", &"BARN_DOOR", &"PIVOT_NOT_ALLOWED",
	&"GRIP_TOO_POOR", &"TOO_TIRED", &"MOVE_NOT_SUPPORTED"]


## docs/42 §3.1: 이 게임에서 되는 기술 16개. 힐훅·토훅·스미어링·다리 내리기는 지웠고(§3.3) 몸통 옮기기·합발·문 열림 대처를 더했다.
func test_all_16_present() -> void:
	var defs := TechniqueDefs.load_all()
	runner.check(defs.size() == 16, "16개: %d" % defs.size())
	for id in defs:
		runner.check(defs[id].phase == 1 and defs[id].real_ko != "", "%s 1차 · 실제 설명 있음" % id)
		runner.check(not defs[id].ready or (defs[id].seen_ko != "" and defs[id].cond_ko != ""), "%s 사전 카드 문구" % id)
	runner.check(TechniqueDefs.button_ids() == ([&"T_OUTSIDE_EDGE", &"T_DROP_KNEE"] as Array[StringName]), "버튼 기술 둘")
	runner.check(TechniqueDefs.absent().size() == 4, "없는 기술 안내 4줄")
	for id in [&"T_INSIDE_EDGE", &"T_OUTSIDE_EDGE", &"T_DROP_KNEE", &"T_HIGH_STEP", &"T_FLAG", &"T_LOCK_OFF", &"T_REST", &"T_CROSS", &"T_MATCH", &"T_FOOT_SWAP", &"T_SIDEPULL", &"T_GASTON",
			&"T_UNDERCLING", &"T_BODY_SHIFT", &"T_FOOT_MATCH", &"T_BARN_DOOR"]:
		runner.check(defs.has(id), "%s 있음" % id)


func test_required_fields_non_empty() -> void:
	var defs := TechniqueDefs.load_all()
	for id in defs:
		var d: Dictionary = defs[id]
		for key in ["name_ko", "purpose_ko", "when_ko", "how_ko"]:
			runner.check(String(d[key]) != "", "%s.%s 비어 있지 않음" % [id, key])
		for key in ["body_parts", "sides", "flow", "group"]:
			runner.check(d[key] != &"", "%s.%s 비어 있지 않음" % [id, key])
		runner.check(d.group in [&"foot", &"hand", &"body"], "%s.group 값: %s" % [id, d.group])
		runner.check(d.purpose_tags.size() > 0, "%s.purpose_tags 있음" % id)
		runner.check(d.mistakes.size() > 0, "%s.mistakes 있음" % id)


func test_flow_matches_spec() -> void:
	var defs := TechniqueDefs.load_all()
	for id in defs:
		var d: Dictionary = defs[id]
		if id in [&"T_DROP_KNEE", &"T_FLAG", &"T_LOCK_OFF", &"T_REST"]:
			runner.check(d.flow == &"execute", "%s flow execute: %s" % [id, d.flow])
		elif d.phase == 1:
			runner.check(d.flow == &"hold_tap", "%s flow hold_tap: %s" % [id, d.flow])
		runner.check(d.sides == (&"none" if id == &"T_REST" else &"left_right"), "%s sides: %s" % [id, d.sides])


func test_mistake_reasons_known() -> void:
	var defs := TechniqueDefs.load_all()
	for id in defs:
		for m in defs[id].mistakes:
			runner.check(m.reason in KNOWN_REASONS, "%s mistake reason 알려진 ID: %s" % [id, m.reason])
			runner.check(String(m.text_ko) != "", "%s mistake text 있음" % id)


func test_body_parts_per_spec() -> void:
	var defs := TechniqueDefs.load_all()
	runner.check(not defs.has(&"T_DEADPOINT"), "T_DEADPOINT 없음(2026-11-05 제거)")
	for id in [&"T_OUTSIDE_EDGE", &"T_DROP_KNEE", &"T_HIGH_STEP"]:
		runner.check(defs[id].body_parts == &"foot+torso", "%s foot+torso: %s" % [id, defs[id].body_parts])
	for id in defs:
		runner.check(defs[id].body_parts in [&"hand", &"foot", &"hand+foot", &"torso", &"torso+hand", &"foot+torso"], "%s body_parts 값: %s" % [id, defs[id].body_parts])
