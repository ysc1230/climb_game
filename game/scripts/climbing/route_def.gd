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
var intended_moves: Array = []  # [[limb, slot key], ...]
var errors: PackedStringArray = []


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
		intended_moves.append([StringName(m[0]), m[1]])


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
	for m in intended_moves:
		_check_slot_for(m[0], m[1], "의도 경로")
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


func _check_slot_for(limb: StringName, key: String, where: String) -> void:
	if not slots.has(key):
		errors.append("%s: 없는 슬롯 %s" % [where, key])
	elif not slots[key].allowed.has(limb):
		errors.append("%s: %s는 %s 비허용" % [where, key, limb])


func slot_pos(key: String) -> Vector2:
	return slots[key].pos
