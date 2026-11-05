class_name RouteDef
extends RefCounted
## docs/09 RouteDefinition의 MVP 부분집합. JSON에서 읽고 docs/09 "로드 전 불변 조건"을 검사한다.

var route_id := ""
var content_version := 0
var validation_status := "Draft"
var slots := {}          # 전체 슬롯 키 -> {pos, allowed, hand_area?, foot_area?, grip_modes, pivot_allowed, hook}
var platforms := []      # {platform_id, x_range: Vector2, foot_slot_keys: Array}
var start_pelvis := Vector2.ZERO
var start_angle := 0.0
var start_slots := {}    # limb -> slot key
var goal_slots: Array = []
var time_medal_seconds := 0.0
var fail_line_y := -0.5  # 이 아래로 떨어지면 추락 연출 종료
var intended_moves: Array = []  # [[limb, slot key], ...] — 기술 단계는 [limb, ...나머지 원본 항목] 그대로(steps_raw와 같은 인덱스)
var steps_raw: Array = []  # JSON intended_moves 원본(docs/28 §7.4 단계 형식, Task 5 검증기용)
## docs/28 §8.1 문제 필드. mode가 빈 문자열이면 시험 전용 루트(TX_*)다.
var mode := ""  # "general" / "course"
var grade := ""  # "V0" ~
var order := 0
var name_ko := ""
var required_techniques: Array[StringName] = []
var course_id := ""
var course_slot := ""  # "tutorial" / "easy" / "normal" / "hard"
var tutorial_steps: Array = []
var crux_steps := {}  # 기술 ID(StringName) -> intended_moves 인덱스
var check_swapped := false  # 좌우 손 순서를 바꾼 재생도 검증할지
var errors: PackedStringArray = []

const MODES := ["general", "course"]
const COURSE_SLOTS := ["tutorial", "easy", "normal", "hard"]
static var _technique_ids := {}  # 기술 ID -> true (techniques.json, 처음 쓸 때 읽음)


static func load_json(path: String) -> RouteDef:
	var route := RouteDef.new()
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		route.errors.append("JSON 파싱 실패: %s" % path)
		return route
	route._read(data)
	route._validate()
	return route


## 이미 파싱한 사전에서 읽고 검사한다(테스트·도구용).
static func from_dict(data: Dictionary) -> RouteDef:
	var route := RouteDef.new()
	route._read(data)
	route._validate()
	return route


func _read(d: Dictionary) -> void:
	route_id = d.get("route_id", "")
	content_version = int(d.get("content_version", 0))
	validation_status = d.get("validation_status", "Draft")
	for hold in d.get("holds", []):
		for s in hold.get("slots", []):
			var key := "%s/%s/%s" % [route_id, hold.hold_id, s.slot_id]
			if slots.has(key):
				errors.append("중복 슬롯 키 %s" % key)
			var allowed: Array[StringName] = []
			for l in s.get("allowed", []):
				allowed.append(StringName(l))
			slots[key] = _read_slot(s, allowed)
	for p in d.get("platforms", []):
		platforms.append({"platform_id": p.platform_id, "x_range": Vector2(p.x_range[0], p.x_range[1]), "foot_slot_keys": p.foot_slot_keys})
	var sp: Dictionary = d.get("start_pose", {})
	start_pelvis = Vector2(sp.pelvis[0], sp.pelvis[1]) if sp.has("pelvis") else Vector2.ZERO
	start_angle = float(sp.get("angle", 0.0))
	for limb in sp.get("slots", {}):
		start_slots[StringName(limb)] = sp.slots[limb]
	goal_slots = d.get("goal_slots", [])
	time_medal_seconds = float(d.get("time_medal_seconds", 0.0))
	fail_line_y = float(d.get("fail_line_y", -0.5))
	for m in d.get("intended_moves", []):
		steps_raw.append(m)
		if m is Array and not m.is_empty():
			intended_moves.append([StringName(str(m[0]))] + m.slice(1))
		else:
			intended_moves.append([])
	mode = str(d.get("mode", ""))
	grade = str(d.get("grade", ""))
	order = int(d.get("order", 0))
	name_ko = str(d.get("name_ko", ""))
	for t in d.get("required_techniques", []):
		required_techniques.append(StringName(t))
	course_id = str(d.get("course_id", ""))
	course_slot = str(d.get("course_slot", ""))
	var ts = d.get("tutorial_steps", [])
	if ts is Array:
		tutorial_steps = ts
	else:
		errors.append("tutorial_steps는 배열이어야 함")
	var crux = d.get("crux_steps", {})
	if crux is Dictionary:
		for t in crux:
			crux_steps[StringName(t)] = crux[t]
	else:
		errors.append("crux_steps는 사전이어야 함")
	check_swapped = bool(d.get("check_swapped", false))


static func _vec(a, fallback: Vector2) -> Vector2:
	if a is Array and a.size() == 2:
		return Vector2(a[0], a[1])
	return fallback


## 슬롯 JSON을 읽고 영역·그립 방식 기본값(docs/19 v0.6)을 채운다. 손 허용 슬롯만 hand_area, 발 허용 슬롯만 foot_area.
func _read_slot(s: Dictionary, allowed: Array[StringName]) -> Dictionary:
	var slot := {"pos": Vector2(s.pos[0], s.pos[1]), "allowed": allowed}
	if allowed.any(func(l): return PoseSolver.is_hand(l)):
		var ha: Dictionary = s.get("hand_area", {})
		slot.hand_area = {"dir": _vec(ha.get("dir"), Vector2(1, 0)).normalized(), "half_width": float(ha.get("half_width", 0.08))}
	if allowed.any(func(l): return not PoseSolver.is_hand(l)):
		var fa: Dictionary = s.get("foot_area", {})
		slot.foot_area = {"up": _vec(fa.get("up"), Vector2(0, 1)).normalized(), "half_height": float(fa.get("half_height", 0.04))}
	var modes: Array = []
	for g in s.get("grip_modes", [{"mode": "pull", "axis": [0, 1], "half_angle": 65}]):
		modes.append({"mode": StringName(g.get("mode", "")), "axis": _vec(g.get("axis"), Vector2(0, 1)).normalized(), "half_angle": float(g.get("half_angle", 65))})
	slot.grip_modes = modes
	slot.pivot_allowed = bool(s.get("pivot_allowed", true))
	slot.hook = bool(s.get("hook", false))
	return slot


func _validate() -> void:
	for limb in PoseSolver.LIMBS:
		if not start_slots.has(limb):
			errors.append("시작 자세에 %s 슬롯 없음" % limb)
	var used := {}
	for limb in start_slots:
		var key: String = start_slots[limb]
		_check_slot_for(limb, key, "시작 자세")
		if used.has(key):
			errors.append("시작 자세 슬롯 중복 %s" % key)
		used[key] = true
	if goal_slots.size() != 2 or goal_slots[0] == goal_slots[1]:
		errors.append("정상 슬롯은 서로 다른 2개여야 함")
	for key in goal_slots:
		if not slots.has(key) or not (slots[key].allowed.has(PoseSolver.LH) and slots[key].allowed.has(PoseSolver.RH)):
			errors.append("정상 슬롯 %s 없음 또는 양손 비허용" % key)
	for p in platforms:
		if p.foot_slot_keys.size() != 2 or p.foot_slot_keys[0] == p.foot_slot_keys[1]:
			errors.append("플랫폼 %s 발 슬롯은 서로 다른 2개여야 함" % p.platform_id)
		for key in p.foot_slot_keys:
			if not slots.has(key):
				errors.append("플랫폼 %s 참조 슬롯 없음 %s" % [p.platform_id, key])
	for i in intended_moves.size():
		_check_step(i, intended_moves[i])
	_validate_meta()
	for key in slots:
		var pos: Vector2 = slots[key].pos
		if not (is_finite(pos.x) and is_finite(pos.y)):
			errors.append("유한하지 않은 좌표 %s" % key)
		var slot: Dictionary = slots[key]
		if slot.has("hand_area") and not (slot.hand_area.half_width > 0.0 and slot.hand_area.dir.length() > 0.0):
			errors.append("손 영역 반폭/방향 오류 %s" % key)
		if slot.has("foot_area") and not (slot.foot_area.half_height > 0.0 and slot.foot_area.up.length() > 0.0):
			errors.append("발 영역 반높이/방향 오류 %s" % key)
		if slot.grip_modes.is_empty():
			errors.append("grip_modes 비어 있음 %s" % key)
		for g in slot.grip_modes:
			if g.mode == &"" or g.axis.length() == 0.0 or not (g.half_angle > 0.0 and g.half_angle <= 180.0):
				errors.append("그립 방식 오류 %s" % key)


## docs/28 §8.1 문제 필드 검사. mode가 없으면(시험 전용 루트) 과정·등급 필드만 형식 검사한다.
func _validate_meta() -> void:
	if mode != "" and not MODES.has(mode):
		errors.append("mode는 general/course: %s" % mode)
	var grade_re := RegEx.create_from_string("^V\\d+$")
	if (mode != "" or grade != "") and grade_re.search(grade) == null:
		errors.append("grade 형식 오류(V0, V1, …): '%s'" % grade)
	if mode != "" and name_ko == "":
		errors.append("name_ko 비어 있음")
	if mode == "course":
		if course_id == "":
			errors.append("과정 문제는 course_id 필수")
		if not COURSE_SLOTS.has(course_slot):
			errors.append("과정 문제 course_slot은 tutorial/easy/normal/hard: '%s'" % course_slot)
	elif course_id != "" or course_slot != "":
		errors.append("과정 문제가 아니면 course_id·course_slot 없음")
	for t in required_techniques:
		if not _technique_exists(t):
			errors.append("required_techniques에 없는 기술 %s" % t)
	for t in crux_steps:
		if not required_techniques.has(t):
			errors.append("crux_steps 키 %s가 required_techniques에 없음" % t)
		var idx = crux_steps[t]
		if not (idx is int or idx is float) or int(idx) != idx or idx < 0 or idx >= intended_moves.size():
			errors.append("crux_steps %s 인덱스 범위 밖: %s" % [t, idx])
		else:
			crux_steps[t] = int(idx)
	if course_slot == "tutorial":
		if tutorial_steps.is_empty():
			errors.append("튜토리얼은 tutorial_steps 필수")
	elif not tutorial_steps.is_empty():
		errors.append("튜토리얼이 아니면 tutorial_steps 없음")


## docs/28 §7.4 단계 형식: [limb, slot], [limb, T_ID], [limb, T_ID, slot], [foot, "flag", [x, y]].
func _check_step(i: int, m) -> void:
	var where := "의도 경로 #%d" % i
	if not (m is Array) or m.size() < 2 or m.size() > 3 or not (m[0] is String or m[0] is StringName) or not (m[1] is String):
		errors.append("%s: 단계 형식 오류 %s" % [where, m])
		return
	var limb := StringName(m[0])
	if not PoseSolver.LIMBS.has(limb):
		errors.append("%s: 모르는 팔다리 %s" % [where, limb])
		return
	var second: String = m[1]
	if m.size() == 2:
		if second.begins_with("T_"):
			_check_technique(second, where)
		else:
			_check_slot_for(limb, second, where)
		return
	var third = m[2]
	if second == "flag":
		if PoseSolver.is_hand(limb):
			errors.append("%s: 플래그는 발만 %s" % [where, limb])
		if not (third is Array and third.size() == 2 and third.all(func(v): return (v is float or v is int) and is_finite(v))):
			errors.append("%s: 플래그 위치는 [x, y] %s" % [where, third])
	elif second.begins_with("T_") and third is String:
		_check_technique(second, where)
		_check_slot_for(limb, third, where)
	else:
		errors.append("%s: 단계 형식 오류 %s" % [where, m])


func _check_technique(id: String, where: String) -> void:
	if not _technique_exists(StringName(id)):
		errors.append("%s: 없는 기술 %s" % [where, id])


static func _technique_exists(id: StringName) -> bool:
	if _technique_ids.is_empty():
		for t in TechniqueDefs.load_all():
			_technique_ids[t] = true
	return _technique_ids.has(id)


func _check_slot_for(limb: StringName, key: String, where: String) -> void:
	if not slots.has(key):
		errors.append("%s: 없는 슬롯 %s" % [where, key])
	elif not slots[key].allowed.has(limb):
		errors.append("%s: %s는 %s 비허용" % [where, key, limb])


func slot_pos(key: String) -> Vector2:
	return slots[key].pos
