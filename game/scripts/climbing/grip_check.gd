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
## v7(2026-11-05): 홀드는 선분(손 잡기 영역·발 디딤 면)이 아니라 두께가 있는 몸체다. 선분에서 수직으로
## 이만큼 안의 점도 그 홀드를 잡은 것으로 본다. 화면의 홀드 모양도 이 크기로 그린다(play_3d).
const HAND_HOLD_THICKNESS := 0.04
const FOOT_HOLD_HALF_WIDTH := 0.06
const REACH_SAMPLES := 8  # 투영점이 닿지 않으면 영역 위 점을 이만큼 나눠 닿는 점을 찾는다
const GRIP_TIE_MARGIN := 0.02  # 28 §4.3: 방식 간 균형 비용 차이가 이 미만이면 grip_modes 앞쪽(떨림 방지)


static func radius_of(limb: StringName) -> float:
	return Tuning.HAND_CANDIDATE_RADIUS if PoseSolver.is_hand(limb) else Tuning.FOOT_CANDIDATE_RADIUS


## 이 홀드의 잡기 반경(v8, 2026-11-05 사용자: "잡기 힘들 정도로 작은 홀드도 좋다, 크기가 여러 개여야").
## 작은 홀드일수록 손끝을 더 가까이 가져가야 잡힌다: 손 0.06 + 0.9·반폭(최대 0.17), 발 0.05 + 1.5·발 반폭(최대 0.14).
static func radius_for(limb: StringName, slot: Dictionary) -> float:
	if PoseSolver.is_hand(limb):
		if not slot.has("hand_area"):
			return Tuning.HAND_CANDIDATE_RADIUS
		return minf(Tuning.HAND_CANDIDATE_RADIUS, 0.06 + 0.9 * float(slot.hand_area.half_width))
	return minf(Tuning.FOOT_CANDIDATE_RADIUS, 0.05 + 1.5 * foot_half_width(slot))


## 손홀드 몸체 두께(선분 수직 반폭): 0.01 + 0.3·반폭, 최대 0.04. 아주 작은 홀드는 얇다.
static func hand_thickness(slot: Dictionary) -> float:
	if not slot.has("hand_area"):
		return HAND_HOLD_THICKNESS
	return minf(HAND_HOLD_THICKNESS, 0.01 + 0.3 * float(slot.hand_area.half_width))


## 발판 좌우 반폭: foot_area.half_width(없으면 0.06).
static func foot_half_width(slot: Dictionary) -> float:
	return float(slot.get("foot_area", {}).get("half_width", FOOT_HOLD_HALF_WIDTH))


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


## 홀드 몸체 안에서 말단에 가장 가까우면서 valid(점)가 참인 접점(v7). 먼저 투영점(contact_point)을 몸체 두께만큼
## 말단 쪽으로 옮겨 보고, 안 되면 영역 위를 REACH_SAMPLES로 나눈 점들(빈 구간만)을 같은 식으로 본다.
## 손이 팔 길이 끝에서 홀드 가장자리에 닿아 보이는데 가운데 선 점은 닿지 않아 못 잡던 문제(사용자 보고)를 없앤다.
## 반환 {point, quality} 또는 {}.
static func reachable_contact(slot: Dictionary, limb: StringName, endpoint: Vector2, entries: Array, max_dist: float, valid: Callable) -> Dictionary:
	var hand := PoseSolver.is_hand(limb)
	var tries: Array = []
	var base := contact_point(slot, limb, endpoint, entries, INF)
	if not base.is_empty():
		tries.append(base)
	if hand:
		var hw: float = slot.hand_area.half_width
		for i in REACH_SAMPLES + 1:
			var s := lerpf(-hw, hw, float(i) / REACH_SAMPLES)
			if _hand_free(s, limb, entries):
				var t := absf(s) / hw
				tries.append({"point": slot.pos + slot.hand_area.dir * s, "quality": 1.0 - t * t})
	else:
		var occupied_by_other := entries.any(func(e): return e.limb != limb)
		if not occupied_by_other:
			var hh: float = slot.foot_area.half_height
			for i in 5:
				var pf := HoldArea.project_foot(slot, slot.pos + slot.foot_area.up * lerpf(-hh, hh, i / 4.0))
				tries.append(pf)
	var best := {}
	var best_d := INF
	for c in tries:
		var p := _thicken(slot, hand, c.point, endpoint)
		var d := endpoint.distance_to(p)
		if d > max_dist or d >= best_d or not valid.call(p):
			continue
		best = {"point": p, "quality": c.quality}
		best_d = d
	return best


## 영역 위 점 p를 몸체 두께 안에서 말단 쪽(영역에 수직)으로 옮긴다.
static func _thicken(slot: Dictionary, hand: bool, p: Vector2, endpoint: Vector2) -> Vector2:
	var along: Vector2 = slot.hand_area.dir if hand else slot.foot_area.up
	var n := along.orthogonal()
	var lim := hand_thickness(slot) if hand else foot_half_width(slot)
	return p + n * clampf((endpoint - p).dot(n), -lim, lim)


static func _hand_free(s: float, limb: StringName, entries: Array) -> bool:
	var iv := Vector2(s - HoldArea.HAND_INTERVAL_HALF, s + HoldArea.HAND_INTERVAL_HALF)
	for e in entries:
		if e.limb != limb and overlaps(iv, e.interval):
			return false
	return true


## 실제 말단 기준 잡기 후보. occupied: 슬롯 키 → [{limb, interval}] (발 interval은 ZERO).
## previous: 직전에 보여준 후보 키(히스테리시스 0.03m). 반환 {key, point, quality} 또는 {}.
## reject: (key, point) → true면 그 목표를 후보에서 뺀다(검증기 금지 플래그, 28 §7.4). 비면 쓰지 않는다.
static func candidate(slots: Dictionary, limb: StringName, endpoint: Vector2, pelvis: Vector2, angle_deg: float, attached: Dictionary, occupied: Dictionary, previous: String = "", yaw_deg: float = 0.0, reject: Callable = Callable()) -> Dictionary:
	var best := {}
	var best_d := INF
	var prev := {}
	var prev_d := INF
	for key in slots:
		var slot: Dictionary = slots[key]
		if not slot.allowed.has(limb):
			continue
		var ok := func(p: Vector2) -> bool:
			if reject.is_valid() and reject.call(key, p):
				return false
			var with_new := attached.duplicate()
			with_new[limb] = p
			return PoseSolver.is_valid(pelvis, angle_deg, with_new, yaw_deg)
		var c := reachable_contact(slot, limb, endpoint, occupied.get(key, []), radius_for(limb, slot), ok)
		if c.is_empty():
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
		return _hand_contact(slot_key, point, HoldArea.project_hand(slot, point).quality, slot.grip_modes[0])
	var qf: float = HoldArea.project_foot(slot, point).quality
	return ContactInfo.make(slot_key, point, qf, &"foot", &"inside")


static func _hand_contact(slot_key: String, point: Vector2, q: float, gm: Dictionary) -> ContactInfo:
	var ci := ContactInfo.make(slot_key, point, q, gm.mode, &"")
	ci.axis = gm.axis
	ci.half_angle = gm.half_angle
	return ci


## 패드 잡기 방향 자동 선택(docs/28 §4.3). 손은 홀드의 grip_modes마다 접점을 만들어 지금 자세에서 힘 계산을 하고,
## 성립하는(힘 해 FEASIBLE·barn door 아님·하중 자격 손 ≥ 1·방식 자세 조건 통과) 방식 중 균형 비용(ClimbRules.flag_cost)이
## 가장 작은 것을 쓴다. 최소와의 차이가 GRIP_TIE_MARGIN 미만이면 목록 앞쪽. 성립하는 방식이 없거나 forbid_auto면 grip_modes[0].
## 발은 contact_for와 같다. attached: 지금 붙은 접점(이 limb 제외 가능), meta: limb → ContactInfo, endpoints: 말단 위치.
## 하중 받는 발은 이 방식으로 잡은 자세의 힘 해에서 정한다(언더클링 자격·높은 발 조건).
static func contact_for_pose(slot_key: String, slots: Dictionary, limb: StringName, point: Vector2, pelvis: Vector2, angle: float, yaw: float, attached: Dictionary, meta: Dictionary, endpoints: Dictionary, forbid_auto := false) -> ContactInfo:
	var slot: Dictionary = slots[slot_key]
	var modes: Array = slot.grip_modes
	if not PoseSolver.is_hand(limb) or forbid_auto or modes.size() < 2:
		return contact_for(slot_key, slots, limb, point)
	var q: float = HoldArea.project_hand(slot, point).quality
	var with_new := attached.duplicate()
	with_new[limb] = point
	var eps := {}
	for l in endpoints:
		if not with_new.has(l):
			eps[l] = endpoints[l]
	var feet := PoseSolver.supporting_feet(pelvis, angle, with_new, [], yaw)
	var costs: Array[float] = []
	var best := INF
	for gm in modes:
		var m := meta.duplicate()
		m[limb] = _hand_contact(slot_key, point, q, gm)
		var r := ClimbRules.evaluate_pose(pelvis, angle, yaw, with_new, eps, m, feet, feet)
		var loaded := ClimbRules.loaded_from(r, [])
		var ok: bool = r.status == SupportSolver.Status.FEASIBLE and not ClimbRules.barn_exceeded(r) \
			and PoseSolver.eligible_hands(pelvis, angle, with_new, m, loaded, yaw) >= 1 \
			and TechniqueJudge.grip_mode_ok(gm.mode, limb, slot.pos, q, pelvis, angle, yaw, with_new, loaded)
		var c := ClimbRules.flag_cost(r) if ok else INF
		costs.append(c)
		best = minf(best, c)
	var pick := 0
	if best < INF:
		for i in costs.size():
			if costs[i] < best + GRIP_TIE_MARGIN:
				pick = i
				break
	return _hand_contact(slot_key, point, q, modes[pick])


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
	if endpoint.distance_to(sp) > radius_for(limb, slots[key]):
		return NOT_ARRIVED
	return &""


static func message(reason: StringName, limb: StringName) -> String:
	if reason == TYPE_MISMATCH:
		return "손으로 잡는 홀드가 아니에요" if PoseSolver.is_hand(limb) else "발로 딛는 홀드가 아니에요"
	return MESSAGES.get(reason, "")
