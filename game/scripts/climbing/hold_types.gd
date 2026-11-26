class_name HoldTypes
extends RefCounted
## 홀드 종류·크기·방향(작업 4 §4.1). 수치는 res://data/hold_types.json. 노드 없음.
## 슬롯의 hold_type·size·rot_deg에서 hand_area·foot_area·grip_modes와 종류 효과(fatigue_mult, foot_share, window)를 만든다.

const PATH := "res://data/hold_types.json"
const SIZES := ["S", "M", "L"]
static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


static func types() -> Dictionary:
	return data().types


static func has(type: String) -> bool:
	return types().has(type)


static func is_foot(type: String) -> bool:
	return has(type) and types()[type].limb == "foot"


## 그 크기에서 두 손이 같이 잡을 수 있는 종류인가(hold_types.json match_sizes, 2026-11-26 사용자: 저그 모두, 슬로퍼 보통·큰, 크림프·핀치·포켓 큰).
static func can_match(type: String, size: String) -> bool:
	return has(type) and (types()[type].get("match_sizes", []) as Array).has(size)


static func name_ko(type: String) -> String:
	return str(types().get(type, {}).get("name_ko", type))


## rot(°, 시계 방향 +)만큼 v를 돌린다. y 위 좌표라 시계 방향은 각도를 빼는 쪽.
static func rotate(v: Vector2, rot_deg: float) -> Vector2:
	return v.rotated(-deg_to_rad(rot_deg))


## 힘 방향 각도(0 = 위, 시계 방향 +)의 그립 방식 이름: 가장 가까운 0 pull · 90/270 sidepull · 180 undercling.
static func mode_for(deg: float) -> StringName:
	var d := fposmod(deg, 360.0)
	var near := fposmod(roundf(d / 90.0) * 90.0, 360.0)
	if is_equal_approx(near, 0.0):
		return &"pull"
	if is_equal_approx(near, 180.0):
		return &"undercling"
	return &"sidepull"


## 슬롯 JSON의 새 필드 오류(없으면 빈 문자열). hand: 손 허용 슬롯인가.
static func field_error(s: Dictionary, hand: bool) -> String:
	var type := str(s.hold_type)
	if not has(type):
		return "모르는 hold_type %s" % type
	if not SIZES.has(str(s.get("size", "M"))):
		return "size는 S/M/L: %s" % s.get("size")
	var rot = s.get("rot_deg", 0)
	if not (rot is float or rot is int) or int(rot) != rot or int(rot) % 5 != 0 or rot < 0 or rot > 355:
		return "rot_deg는 0~355, 5의 배수: %s" % rot
	if hand and is_foot(type):
		return "%s는 발 홀드" % type
	return ""


## 슬롯 사전에 종류 필드와 그에서 만든 영역·그립 방식을 채운다. s: 슬롯 JSON(이미 field_error 통과).
## hand: 손 칸인가. 손홀드 종류를 발 칸(발로만 딛는 홀드)에 놓으면 그 반폭의 발 영역이 된다.
static func fill(slot: Dictionary, s: Dictionary, hand := true) -> void:
	var type := str(s.hold_type)
	var t: Dictionary = types()[type]
	var size := str(s.get("size", "M"))
	var i := SIZES.find(size)
	var rot := float(s.get("rot_deg", 0))
	slot.hold_type = StringName(type)
	slot.size = size
	slot.rot_deg = int(rot)
	slot.fatigue_mult = float(t.get("fatigue", 1.0))
	slot.foot_share = float(t.get("foot_share", 1.0))
	slot.window = t.get("window", [])
	if t.limb == "foot" or not hand:
		var hh := float(t.half_height[i]) if t.has("half_height") else clampf(float(t.half_width[i]) * 0.6, 0.03, 0.08)
		slot.foot_area = {"up": rotate(Vector2(0, 1), rot), "half_height": hh, "half_width": float(t.half_width[i])}
		slot.grip_modes = [{"mode": &"pull", "axis": Vector2(0, 1), "half_angle": 65.0}]
		return
	var hw := float(t.half_width[i])
	var ha: Dictionary = s.get("hand_area", {})
	slot.hand_area = {"dir": rotate(Vector2(1, 0), rot), "half_width": hw, "matchable": bool(ha.get("matchable", false)) and can_match(type, size)}
	var half := float(t.half_angle) + (0.0 if t.get("fixed_size", false) else float(data().size_half_angle[size]))
	var modes: Array = []
	for m in t.modes:
		var deg := rot + float(m)
		modes.append({"mode": mode_for(deg), "axis": rotate(Vector2(0, 1), deg), "half_angle": half})
	slot.grip_modes = modes
