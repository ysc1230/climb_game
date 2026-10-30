class_name GripCheck
extends RefCounted
## 잡기 후보와 거부 사유(docs/03 후보 선택, docs/25 거부 피드백). 노드 의존 없음.
## 사유 우선순위(25): 종류·점유 → 거리 → 관절/몸통 → 접촉 방향 → 하중/체중 이동.

const NO_TARGET := &"NO_TARGET"
const TYPE_MISMATCH := &"TYPE_MISMATCH"
const OCCUPIED := &"OCCUPIED"
const NOT_ARRIVED := &"NOT_ARRIVED"
const OUT_OF_REACH := &"OUT_OF_REACH"
const JOINT_LIMIT := &"JOINT_LIMIT"
const NEED_WEIGHT_SHIFT := &"NEED_WEIGHT_SHIFT"
const POSE_CONFLICT := &"POSE_CONFLICT"

## 사용자 문구(05/25). NO_TARGET은 과도한 실패 안내를 하지 않는다(빈 문자열).
const MESSAGES := {
	NO_TARGET: "",
	TYPE_MISMATCH: "",  # 손/발에 따라 아래 함수에서 채움
	OCCUPIED: "이미 사용 중이에요",
	NOT_ARRIVED: "손발이 홀드에 닿은 뒤 놓으세요",
	OUT_OF_REACH: "몸을 더 가까이 옮겨보세요",
	JOINT_LIMIT: "팔·다리 각도 한계예요",
	NEED_WEIGHT_SHIFT: "먼저 체중을 옮겨야 해요",
	POSE_CONFLICT: "지금 자세로는 함께 잡을 수 없어요",
}
const AIM_RADIUS := 0.25


static func radius_of(limb: StringName) -> float:
	return Tuning.HAND_CANDIDATE_RADIUS if PoseSolver.is_hand(limb) else Tuning.FOOT_CANDIDATE_RADIUS


## 실제 말단 기준 잡기 후보. occupied: 슬롯 키 → 점유 limb. previous: 직전에 보여준 후보(히스테리시스 0.03m).
static func candidate(slots: Dictionary, limb: StringName, endpoint: Vector2, pelvis: Vector2, angle_deg: float, attached: Dictionary, occupied: Dictionary, previous: String = "") -> String:
	var radius := radius_of(limb)
	var best := ""
	var best_d := INF
	var prev_d := INF
	for key in slots:
		if not slots[key].allowed.has(limb) or (occupied.has(key) and occupied[key] != limb):
			continue
		var sp: Vector2 = slots[key].pos
		var d := endpoint.distance_to(sp)
		if d > radius:
			continue
		var with_new := attached.duplicate()
		with_new[limb] = sp
		if not PoseSolver.is_valid(pelvis, angle_deg, with_new):
			continue
		if key == previous:
			prev_d = d
		if d < best_d:
			best = key
			best_d = d
	if prev_d < INF and best != previous and best_d > prev_d - Tuning.CANDIDATE_HYSTERESIS:
		return previous
	return best


## 요청 목표 근처에서 노린 슬롯(종류 무관, 가장 가까운 것).
static func aimed_slot(slots: Dictionary, requested: Vector2) -> String:
	var best := ""
	var best_d := AIM_RADIUS
	for key in slots:
		var d := requested.distance_to(slots[key].pos)
		if d < best_d:
			best = key
			best_d = d
	return best


## 잡기 거부 사유. 잡을 수 있으면 &"".
static func reject_reason(slots: Dictionary, limb: StringName, endpoint: Vector2, requested: Vector2, pelvis: Vector2, angle_deg: float, attached: Dictionary, occupied: Dictionary, feet: Array) -> StringName:
	var key := aimed_slot(slots, requested)
	if key.is_empty():
		key = aimed_slot(slots, endpoint)
	if key.is_empty():
		return NO_TARGET
	if not slots[key].allowed.has(limb):
		return TYPE_MISMATCH
	if occupied.has(key) and occupied[key] != limb:
		return OCCUPIED
	var sp: Vector2 = slots[key].pos
	var with_new := attached.duplicate()
	with_new[limb] = sp
	if not PoseSolver.direction_ok(pelvis, angle_deg, limb, sp):
		return JOINT_LIMIT
	if not PoseSolver.can_reach(pelvis, angle_deg, limb, sp):
		# 남은 접점을 유지한 채 몸통을 옮기면 닿는가(점선 영역, 25)
		var t := PoseSolver.find_target(pelvis, angle_deg, attached, feet, {}, {limb: sp})
		var tp := Vector2(t.x, t.y)
		if PoseSolver.can_reach(tp, t.z, limb, sp) and PoseSolver.is_valid(tp, t.z, with_new):
			return NEED_WEIGHT_SHIFT
		return OUT_OF_REACH
	if not PoseSolver.is_valid(pelvis, angle_deg, with_new):
		return POSE_CONFLICT
	if endpoint.distance_to(sp) > radius_of(limb):
		return NOT_ARRIVED
	return &""


static func message(reason: StringName, limb: StringName) -> String:
	if reason == TYPE_MISMATCH:
		return "손으로 잡는 홀드가 아니에요" if PoseSolver.is_hand(limb) else "발로 딛는 홀드가 아니에요"
	return MESSAGES.get(reason, "")
