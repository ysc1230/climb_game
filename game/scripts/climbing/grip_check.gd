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


## 구간 겹침(맞닿음은 겹침이 아님).
static func overlaps(a: Vector2, b: Vector2) -> bool:
	return a.x < b.y - 0.0001 and b.x < a.y - 0.0001


## 이 슬롯에서 limb이 쓸 수 있는 접점. 영역에 투영하고, 손은 점유 구간과 겹치면 가장 가까운 빈 구간으로 옮긴다.
## 반환 {point, quality} 또는 {}(빈 자리 없음). max_dist: 말단에서 접점까지 허용 거리(INF면 제한 없음).
static func contact_point(slot: Dictionary, limb: StringName, endpoint: Vector2, entries: Array, max_dist: float) -> Dictionary:
	if not PoseSolver.is_hand(limb):
		for e in entries:
			if e.limb != limb:
				return {}
		var pf := HoldArea.project_foot(slot, endpoint)
		if endpoint.distance_to(pf.point) > max_dist:
			return {}
		return {"point": pf.point, "quality": pf.quality}
	var area: Dictionary = slot.hand_area
	var hw: float = area.half_width
	var base := HoldArea.project_hand(slot, endpoint)
	var s0: float = (base.point - slot.pos).dot(area.dir)
	var others: Array = []
	for e in entries:
		if e.limb != limb:
			others.append(e.interval)
	var options: Array = [s0]
	for iv in others:
		options.append(iv.y + HoldArea.HAND_INTERVAL_HALF)
		options.append(iv.x - HoldArea.HAND_INTERVAL_HALF)
	var best := {}
	var best_d := INF
	for s in options:
		if absf(s) > hw + 0.0001:
			continue
		var iv := Vector2(s - HoldArea.HAND_INTERVAL_HALF, s + HoldArea.HAND_INTERVAL_HALF)
		var free := true
		for o in others:
			if overlaps(iv, o):
				free = false
				break
		if not free:
			continue
		var p: Vector2 = slot.pos + area.dir * s
		var d := endpoint.distance_to(p)
		if d > max_dist or d >= best_d:
			continue
		var t := absf(s) / hw
		best_d = d
		best = {"point": p, "quality": 1.0 - t * t}
	return best


## 실제 말단 기준 잡기 후보. occupied: 슬롯 키 → [{limb, interval}] (발 interval은 ZERO).
## previous: 직전에 보여준 후보 키(히스테리시스 0.03m). 반환 {key, point, quality} 또는 {}.
static func candidate(slots: Dictionary, limb: StringName, endpoint: Vector2, pelvis: Vector2, angle_deg: float, attached: Dictionary, occupied: Dictionary, previous: String = "", yaw_deg: float = 0.0) -> Dictionary:
	var radius := radius_of(limb)
	var best := {}
	var best_d := INF
	var prev := {}
	var prev_d := INF
	for key in slots:
		var slot: Dictionary = slots[key]
		if not slot.allowed.has(limb):
			continue
		var c := contact_point(slot, limb, endpoint, occupied.get(key, []), radius)
		if c.is_empty():
			continue
		var with_new := attached.duplicate()
		with_new[limb] = c.point
		if not PoseSolver.is_valid(pelvis, angle_deg, with_new, yaw_deg):
			continue
		var d := endpoint.distance_to(c.point)
		var found := {"key": key, "point": c.point, "quality": c.quality}
		if key == previous:
			prev = found
			prev_d = d
		if d < best_d:
			best = found
			best_d = d
	if prev_d < INF and best.key != previous and best_d > prev_d - Tuning.CANDIDATE_HYSTERESIS:
		return prev
	return best


## 접점 정보(품질·그립 방식). 손은 grip_modes[0], 발은 foot/inside.
static func contact_for(slot_key: String, slots: Dictionary, limb: StringName, point: Vector2) -> ContactInfo:
	var slot: Dictionary = slots[slot_key]
	if PoseSolver.is_hand(limb):
		var q: float = HoldArea.project_hand(slot, point).quality
		var gm: Dictionary = slot.grip_modes[0]
		var ci := ContactInfo.make(slot_key, point, q, gm.mode, &"")
		ci.axis = gm.axis
		ci.half_angle = gm.half_angle
		return ci
	var qf: float = HoldArea.project_foot(slot, point).quality
	return ContactInfo.make(slot_key, point, qf, &"foot", &"inside")


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
static func reject_reason(slots: Dictionary, limb: StringName, endpoint: Vector2, requested: Vector2, pelvis: Vector2, angle_deg: float, attached: Dictionary, occupied: Dictionary, feet: Array, yaw_deg: float = 0.0) -> StringName:
	var key := aimed_slot(slots, requested)
	if key.is_empty():
		key = aimed_slot(slots, endpoint)
	if key.is_empty():
		return NO_TARGET
	if not slots[key].allowed.has(limb):
		return TYPE_MISMATCH
	var found := contact_point(slots[key], limb, endpoint, occupied.get(key, []), INF)
	if found.is_empty():
		return OCCUPIED
	var sp: Vector2 = found.point
	var with_new := attached.duplicate()
	with_new[limb] = sp
	if not PoseSolver.direction_ok(pelvis, angle_deg, limb, sp, yaw_deg):
		return JOINT_LIMIT
	if not PoseSolver.can_reach(pelvis, angle_deg, limb, sp, yaw_deg):
		# 남은 접점을 유지한 채 몸통을 옮기면 닿는가(점선 영역, 25)
		var t := PoseSolver.find_target(pelvis, angle_deg, attached, feet, {}, {limb: sp}, NAN, 0.0, yaw_deg)
		var tp := Vector2(t.x, t.y)
		if PoseSolver.can_reach(tp, t.z, limb, sp, yaw_deg) and PoseSolver.is_valid(tp, t.z, with_new, yaw_deg):
			return NEED_WEIGHT_SHIFT
		return OUT_OF_REACH
	if not PoseSolver.is_valid(pelvis, angle_deg, with_new, yaw_deg):
		return POSE_CONFLICT
	if endpoint.distance_to(sp) > radius_of(limb):
		return NOT_ARRIVED
	return &""


static func message(reason: StringName, limb: StringName) -> String:
	if reason == TYPE_MISMATCH:
		return "손으로 잡는 홀드가 아니에요" if PoseSolver.is_hand(limb) else "발로 딛는 홀드가 아니에요"
	return MESSAGES.get(reason, "")
