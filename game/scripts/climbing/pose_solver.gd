class_name PoseSolver
extends RefCounted
## docs/04 "자세 계산의 구현 계약"의 엔진 독립 구현.
## 좌표는 벽면 월드 m(X 오른쪽, Y 위), 각도는 도. 노드·싱글턴에 의존하지 않는다.
## 미구현: 몸통 캡슐·머리와 벽 장애물·바닥 충돌(MVP 평면 벽에 장애물이 생기면 추가).

const LH := &"LH"
const RH := &"RH"
const LF := &"LF"
const RF := &"RF"
const LIMBS: Array[StringName] = [LH, RH, LF, RF]

static var _arm := Tuning.arm_range()
static var _leg := Tuning.leg_range()


static func is_hand(limb: StringName) -> bool:
	return limb == LH or limb == RH


static func joint_offset(limb: StringName) -> Vector2:
	var side := -1.0 if (limb == LH or limb == LF) else 1.0
	var base := Tuning.SHOULDER_OFFSET if is_hand(limb) else Tuning.HIP_OFFSET
	return Vector2(base.x * side, base.y)


## 골반 위치·회전에서 어깨/고관절의 월드 위치.
static func joint_position(pelvis: Vector2, angle_deg: float, limb: StringName) -> Vector2:
	return pelvis + joint_offset(limb).rotated(deg_to_rad(angle_deg))


static func reach_of(limb: StringName) -> Vector2:
	return _arm if is_hand(limb) else _leg


static func limb_distance(pelvis: Vector2, angle_deg: float, limb: StringName, slot: Vector2) -> float:
	return joint_position(pelvis, angle_deg, limb).distance_to(slot)


static func side_sign(limb: StringName) -> float:
	return -1.0 if (limb == LH or limb == LF) else 1.0


## 몸통 roll을 제거한 관절→말단 방향각(도). 0 = 손은 위, 발은 아래. 양수 = 몸 바깥쪽.
static func limb_angle(pelvis: Vector2, angle_deg: float, limb: StringName, point: Vector2) -> float:
	var v := (point - joint_position(pelvis, angle_deg, limb)).rotated(-deg_to_rad(angle_deg))
	var s := side_sign(limb)
	if is_hand(limb):
		return rad_to_deg(atan2(s * v.x, v.y))
	return rad_to_deg(atan2(s * v.x, -v.y))


static func dir_range(limb: StringName) -> Vector2:
	return Tuning.HAND_DIR_RANGE_DEG if is_hand(limb) else Tuning.FOOT_DIR_RANGE_DEG


static func direction_ok(pelvis: Vector2, angle_deg: float, limb: StringName, point: Vector2) -> bool:
	var a := limb_angle(pelvis, angle_deg, limb, point)
	var r := dir_range(limb)
	return a >= r.x - 0.001 and a <= r.y + 0.001


## 깊이 차(골반 Z − 말단 Z)가 dz일 때의 벽면 2D 거리 범위.
static func planar_range(limb: StringName, dz_min: float, dz_max: float) -> Vector2:
	var r := reach_of(limb)
	var far := sqrt(maxf(r.y * r.y - dz_min * dz_min, 0.0))
	var near := sqrt(maxf(r.x * r.x - dz_max * dz_max, 0.0))
	return Vector2(near, far)


## 접점 말단의 깊이 차 범위(골반 깊이 범위 − 접촉면 깊이).
static func contact_dz_range() -> Vector2:
	return Tuning.PELVIS_DEPTH_RANGE - Vector2.ONE * Tuning.CONTACT_DEPTH


## 한 접점 슬롯이 현재 골반·회전에서 방향·3D 거리 조건을 만족하는지(골반 깊이 범위 중 어딘가에서).
static func can_reach(pelvis: Vector2, angle_deg: float, limb: StringName, slot: Vector2) -> bool:
	if not direction_ok(pelvis, angle_deg, limb, slot):
		return false
	var dz := contact_dz_range()
	var pr := planar_range(limb, dz.x, dz.y)
	var d := limb_distance(pelvis, angle_deg, limb, slot)
	return d >= pr.x - Tuning.DISTANCE_EPSILON and d <= pr.y + Tuning.DISTANCE_EPSILON


## 고정된 모든 접점이 함께 만족하는 골반 깊이(Z). 없으면 NAN.
## 선호 깊이에 가장 가까운 값을 고른다. 판정과 표현이 같은 값을 쓴다.
static func body_depth(pelvis: Vector2, angle_deg: float, attached: Dictionary) -> float:
	var lo := Tuning.PELVIS_DEPTH_RANGE.x
	var hi := Tuning.PELVIS_DEPTH_RANGE.y
	for limb in attached:
		var d := limb_distance(pelvis, angle_deg, limb, attached[limb])
		var r := reach_of(limb)
		if d > r.y + Tuning.DISTANCE_EPSILON:
			return NAN
		hi = minf(hi, Tuning.CONTACT_DEPTH + sqrt(maxf(r.y * r.y - d * d, 0.0)))
		lo = maxf(lo, Tuning.CONTACT_DEPTH + sqrt(maxf(r.x * r.x - d * d, 0.0)))
	if lo > hi + Tuning.DISTANCE_EPSILON:
		return NAN
	return clampf(Tuning.PELVIS_DEPTH_PREFERRED, lo, hi)


## 고정된 모든 접점의 방향·3D 길이·관절 조건과 몸통 회전 제한(H01~H04 중 구현분).
static func is_valid(pelvis: Vector2, angle_deg: float, attached: Dictionary) -> bool:
	if not (is_finite(pelvis.x) and is_finite(pelvis.y) and is_finite(angle_deg)):
		return false
	if absf(angle_deg) > Tuning.BODY_ANGLE_LIMIT_DEG + Tuning.DISTANCE_EPSILON:
		return false
	for limb in attached:
		if not direction_ok(pelvis, angle_deg, limb, attached[limb]):
			return false
	return not is_nan(body_depth(pelvis, angle_deg, attached))


## 자유·드래그 말단 제한(H02/H03/H06). 요청 위치를 허용 부채꼴 안으로 연속적으로 제한한다.
## 각도는 직전 위치에서 이어서 풀어(unwrap) 금지 영역을 가로질러 반대편 경계로 점프하지 않는다.
static func clamp_endpoint(pelvis: Vector2, angle_deg: float, limb: StringName, previous: Vector2, requested: Vector2) -> Vector2:
	var joint := joint_position(pelvis, angle_deg, limb)
	var rng := dir_range(limb)
	var prev_a := clampf(limb_angle(pelvis, angle_deg, limb, previous), rng.x, rng.y)
	var v := requested - joint
	var target_a := prev_a
	if v.length() > 0.001:
		target_a = clampf(prev_a + wrapf(limb_angle(pelvis, angle_deg, limb, requested) - prev_a, -180.0, 180.0), rng.x, rng.y)
	var lift := Tuning.CONTACT_DEPTH + Tuning.FREE_ENDPOINT_LIFT
	var pr := planar_range(limb, Tuning.PELVIS_DEPTH_PREFERRED - lift, Tuning.PELVIS_DEPTH_PREFERRED - lift)
	var r := clampf(v.length(), maxf(pr.x, 0.02), pr.y)
	var s := side_sign(limb)
	var a := deg_to_rad(target_a)
	var local := Vector2(s * sin(a), cos(a)) if is_hand(limb) else Vector2(s * sin(a), -cos(a))
	return joint + (local * r).rotated(deg_to_rad(angle_deg))


## 손 접점의 하중 자격: 일반 pull 슬롯이 어깨보다 0.10m 넘게 낮으면 자격 없음.
static func hand_load_eligible(pelvis: Vector2, angle_deg: float, limb: StringName, slot: Vector2) -> bool:
	return slot.y >= joint_position(pelvis, angle_deg, limb).y - Tuning.HAND_LOAD_MAX_BELOW_SHOULDER


## 하중 자격이 있는 붙은 손의 수.
static func eligible_hands(pelvis: Vector2, angle_deg: float, attached: Dictionary) -> int:
	var n := 0
	for limb in [LH, RH]:
		if attached.has(limb) and hand_load_eligible(pelvis, angle_deg, limb, attached[limb]):
			n += 1
	return n


## 발 지지 판정. was_supporting이면 종료 히스테리시스를 적용한다.
static func is_foot_supporting(pelvis: Vector2, angle_deg: float, limb: StringName, slot: Vector2, was_supporting: bool = false) -> bool:
	if not can_reach(pelvis, angle_deg, limb, slot):
		return false
	var to_hip := joint_position(pelvis, angle_deg, limb) - slot
	var length := to_hip.length()
	if length <= 0.0:
		return false
	var half := Tuning.FOOT_SUPPORT_HALF_ANGLE + (Tuning.SUPPORT_EXIT_ANGLE if was_supporting else 0.0)
	var min_h := Tuning.FOOT_SUPPORT_MIN_HEIGHT - (Tuning.SUPPORT_EXIT_HEIGHT if was_supporting else 0.0)
	if to_hip.dot(Tuning.FOOT_SUPPORT_DIR) < min_h:
		return false
	return to_hip.normalized().dot(Tuning.FOOT_SUPPORT_DIR) >= cos(deg_to_rad(half)) - Tuning.DISTANCE_EPSILON


## 현재 자세에서 지지 중인 발 집합(이전 집합으로 히스테리시스 적용).
static func supporting_feet(pelvis: Vector2, angle_deg: float, attached: Dictionary, previous: Array = []) -> Array[StringName]:
	var result: Array[StringName] = []
	for limb in [LF, RF]:
		if attached.has(limb) and is_foot_supporting(pelvis, angle_deg, limb, attached[limb], previous.has(limb)):
			result.append(limb)
	return result


## v0.5 목표 자세 비용(docs/04 §5). profile: limb → 선호 거리(무브별), intents: limb → 활성 말단의 요청 목표,
## start: 직전 확정 자세 Vector3(x, y, angle). 무효 자세는 INF. lateral_target은 Rebalancing 전용 보조 항(구현 확장).
## 손 하중 u² 항은 후보마다 힘 계산이 필요해 미적용(docs/23).
static func cost(pelvis: Vector2, angle_deg: float, attached: Dictionary, feet: Array, profile: Dictionary = {}, intents: Dictionary = {}, start: Vector3 = Vector3(NAN, NAN, NAN), lateral_target: float = NAN, lateral_weight: float = 0.0) -> float:
	var st := start if not is_nan(start.x) else Vector3(pelvis.x, pelvis.y, angle_deg)
	return _candidate_cost(pelvis, angle_deg, _search_context(attached, feet, profile, intents, st, lateral_target, lateral_weight))


## 무브 프로필이 없을 때의 기본 선호 거리(Rest: 팔 0.70, 다리 0.86).
static func default_pref(limb: StringName) -> float:
	return Tuning.PREF_ARM_REST if is_hand(limb) else Tuning.PREF_LEG_STAND


## 27후보 근방 탐색. 반환값 Vector3(x, y, angle)은 목표 자세이며 즉시 이동 위치가 아니다.
static func find_target(pelvis: Vector2, angle_deg: float, attached: Dictionary, feet: Array, profile: Dictionary = {}, intents: Dictionary = {}, lateral_target: float = NAN, lateral_weight: float = 0.0) -> Vector3:
	var best := Vector3(pelvis.x, pelvis.y, angle_deg)
	if attached.is_empty():
		return best
	var ctx := _search_context(attached, feet, profile, intents, best, lateral_target, lateral_weight)
	var best_cost := _candidate_cost(pelvis, angle_deg, ctx)
	var pos_step := Tuning.SEARCH_POS_STEP
	var ang_step := Tuning.SEARCH_ANGLE_STEP
	for _round in Tuning.SEARCH_ROUNDS:
		var center := best
		var improved := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for da in [-1, 0, 1]:
					var p := Vector2(center.x + dx * pos_step, center.y + dy * pos_step)
					var a: float = center.z + da * ang_step
					if p.distance_to(pelvis) > Tuning.SEARCH_POS_EXTENT or absf(a - angle_deg) > Tuning.SEARCH_ANGLE_EXTENT:
						continue
					var c := _candidate_cost(p, a, ctx)
					if c == INF:
						continue
					var current := Vector2(best.x, best.y)
					if c < best_cost - Tuning.COST_EPSILON or (absf(c - best_cost) <= Tuning.COST_EPSILON and p.distance_to(pelvis) < current.distance_to(pelvis)):
						if c < best_cost - Tuning.COST_EPSILON:
							improved = true
						best = Vector3(p.x, p.y, a)
						best_cost = minf(best_cost, c)
		if not improved:
			pos_step *= 0.5
			ang_step *= 0.5
	return best


## 탐색 동안 고정되는 접점·의도 정보(사전 계산). _candidate_cost는 is_valid 실패 시 INF.
static func _search_context(attached: Dictionary, feet: Array, profile: Dictionary, intents: Dictionary, start: Vector3, lateral_target: float, lateral_weight: float) -> Dictionary:
	var offsets: Array[Vector2] = []
	var slots: Array[Vector2] = []
	var kinds: Array[int] = []  # 0 손, 1 지지 발, 2 비지지 발
	var signs: Array[float] = []
	var prefs: Array[float] = []
	var maxes: Array[float] = []
	for limb in attached:
		offsets.append(joint_offset(limb))
		slots.append(attached[limb])
		kinds.append(0 if is_hand(limb) else (1 if feet.has(limb) else 2))
		signs.append(side_sign(limb))
		prefs.append(float(profile.get(limb, default_pref(limb))))
		maxes.append(reach_of(limb).y)
	# 활성 말단 의도: 관절에서 요청 목표까지가 현재 3D 도달 가능 2D 범위를 벗어난 만큼을 오차로
	var i_offsets: Array[Vector2] = []
	var i_targets: Array[Vector2] = []
	var i_ranges: Array[Vector2] = []
	var i_lengths: Array[float] = []
	for limb in intents:
		i_offsets.append(joint_offset(limb))
		i_targets.append(intents[limb])
		var dz := Tuning.PELVIS_DEPTH_PREFERRED - Tuning.CONTACT_DEPTH
		i_ranges.append(planar_range(limb, dz, dz))
		i_lengths.append(reach_of(limb).y)
	# 하중 대체 항의 지지 X 범위: StandUp이면 올린 발, 아니면 지지 발들의 X 범위
	var load_lo := INF
	var load_hi := -INF
	var stand_x: float = profile.get(&"_stand_x", NAN)
	if not is_nan(stand_x):
		load_lo = stand_x
		load_hi = stand_x
	else:
		for i in slots.size():
			if kinds[i] == 1:
				load_lo = minf(load_lo, slots[i].x - Tuning.LOAD_PROXY_MARGIN)
				load_hi = maxf(load_hi, slots[i].x + Tuning.LOAD_PROXY_MARGIN)
	return {"offsets": offsets, "slots": slots, "kinds": kinds, "signs": signs, "prefs": prefs, "maxes": maxes,
		"i_offsets": i_offsets, "i_targets": i_targets, "i_ranges": i_ranges, "i_lengths": i_lengths,
		"load_lo": load_lo, "load_hi": load_hi,
		"start": start, "lat": lateral_target, "lat_w": lateral_weight}


## 후보 자세의 비용. 무효면 INF. 관절 위치를 한 번만 계산한다.
static func _candidate_cost(p: Vector2, a: float, ctx: Dictionary) -> float:
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(a)) or absf(a) > Tuning.BODY_ANGLE_LIMIT_DEG + Tuning.DISTANCE_EPSILON:
		return INF
	var rad := deg_to_rad(a)
	var cs := cos(rad)
	var sn := sin(rad)
	var lo := Tuning.PELVIS_DEPTH_RANGE.x
	var hi := Tuning.PELVIS_DEPTH_RANGE.y
	var pref_cost := 0.0
	var offsets: Array[Vector2] = ctx.offsets
	var slots: Array[Vector2] = ctx.slots
	var kinds: Array[int] = ctx.kinds
	var signs: Array[float] = ctx.signs
	var prefs: Array[float] = ctx.prefs
	var maxes: Array[float] = ctx.maxes
	for i in offsets.size():
		var o := offsets[i]
		var joint := p + Vector2(o.x * cs - o.y * sn, o.x * sn + o.y * cs)
		var w := slots[i] - joint
		var d := w.length()
		var v := Vector2(w.x * cs + w.y * sn, -w.x * sn + w.y * cs)  # roll 제거
		var hand := kinds[i] == 0
		var ang := rad_to_deg(atan2(signs[i] * v.x, v.y if hand else -v.y))
		var rng := Tuning.HAND_DIR_RANGE_DEG if hand else Tuning.FOOT_DIR_RANGE_DEG
		if ang < rng.x - 0.001 or ang > rng.y + 0.001:
			return INF
		var r := _arm if hand else _leg
		if d > r.y + Tuning.DISTANCE_EPSILON:
			return INF
		hi = minf(hi, Tuning.CONTACT_DEPTH + sqrt(maxf(r.y * r.y - d * d, 0.0)))
		lo = maxf(lo, Tuning.CONTACT_DEPTH + sqrt(maxf(r.x * r.x - d * d, 0.0)))
		# 선호 자세는 붙은 모든 팔다리에 적용한다. 지지에서 빠진 높은 발도 포함해야
		# 고관절을 발 아래로 내려 다리 비용을 없애는 거짓 해(골반 하강)가 생기지 않는다(docs/23).
		var e := (d - prefs[i]) / maxes[i]
		pref_cost += e * e
	if lo > hi + Tuning.DISTANCE_EPSILON:
		return INF
	var intent_cost := 0.0
	var i_offsets: Array[Vector2] = ctx.i_offsets
	var i_targets: Array[Vector2] = ctx.i_targets
	var i_ranges: Array[Vector2] = ctx.i_ranges
	var i_lengths: Array[float] = ctx.i_lengths
	var ilo := lo
	var ihi := hi
	for i in i_offsets.size():
		var o := i_offsets[i]
		var joint := p + Vector2(o.x * cs - o.y * sn, o.x * sn + o.y * cs)
		var d := (i_targets[i] - joint).length()
		var miss := maxf(d - i_ranges[i].y, i_ranges[i].x - d)
		if miss > 0.0:
			var e := miss / i_lengths[i]
			intent_cost += e * e
		# 요청 목표를 접점으로 더했을 때 필요한 골반 깊이(공통 깊이 충돌 유도)
		var lr := i_lengths[i]
		var rmin := (_arm if i_lengths[i] < 0.9 else _leg).x
		ihi = minf(ihi, Tuning.CONTACT_DEPTH + sqrt(maxf(lr * lr - d * d, 0.0)))
		ilo = maxf(ilo, Tuning.CONTACT_DEPTH + sqrt(maxf(rmin * rmin - d * d, 0.0)))
	if ilo > ihi:
		var c := (ilo - ihi) / Tuning.CHANGE_POS_SCALE
		intent_cost += c * c
	var load_cost := 0.0
	if float(ctx.load_lo) <= float(ctx.load_hi):
		var gap := maxf(float(ctx.load_lo) - p.x, p.x - float(ctx.load_hi))
		if gap > 0.0:
			load_cost = pow(gap / Tuning.LOAD_PROXY_SCALE, 2)
	var start: Vector3 = ctx.start
	var dp := Vector2(p.x - start.x, p.y - start.y).length() / Tuning.CHANGE_POS_SCALE
	var da := (a - start.z) / Tuning.CHANGE_ANGLE_SCALE
	var total := Tuning.W_INTENT * intent_cost + Tuning.W_PREF_V05 * pref_cost + Tuning.W_LOAD_PROXY * load_cost
	total += Tuning.W_ANGLE_V05 * pow(a / Tuning.BODY_ANGLE_LIMIT_DEG, 2)
	total += Tuning.W_CHANGE * (dp * dp + da * da)
	if not is_nan(float(ctx.lat)) and float(ctx.lat_w) > 0.0:
		total += float(ctx.lat_w) * pow(p.x - float(ctx.lat), 2)
	return total


## 지지 중 한 틱의 골반 보정 운동. body는 {pos, vel, angle, ang_vel}을 갖는 BodyState.
## 제약을 깨는 이동은 1, 1/2 … 1/32, 0배로 줄여 고른다.
## accept(pos, angle) -> bool이 주어지면 그 검사(예: 힘 균형)도 통과한 첫 배율을 쓴다. 0배(정지)는 항상 허용.
static func step_body(body: BodyState, attached: Dictionary, feet: Array, dt: float = Tuning.DT, accept: Callable = Callable(), profile: Dictionary = {}, intents: Dictionary = {}) -> void:
	move_body(body, find_target(body.pos, body.angle, attached, feet, profile, intents), attached, dt, accept)


## 주어진 목표 자세로 한 틱 이동(속도·가속도 제한, 제약 위반 시 배율 축소).
static func move_body(body: BodyState, target: Vector3, attached: Dictionary, dt: float = Tuning.DT, accept: Callable = Callable()) -> void:
	var accel := (Vector2(target.x, target.y) - body.pos) * Tuning.ROOT_POS_GAIN - body.vel * Tuning.ROOT_POS_DAMPING
	accel = accel.limit_length(Tuning.ROOT_ACCEL_LIMIT)
	var vel := (body.vel + accel * dt).limit_length(Tuning.ROOT_SPEED_LIMIT)
	var ang_accel := clampf((target.z - body.angle) * Tuning.ROOT_ANGLE_GAIN - body.ang_vel * Tuning.ROOT_ANGLE_DAMPING, -Tuning.ROOT_ANGULAR_ACCEL, Tuning.ROOT_ANGULAR_ACCEL)
	var ang_vel := clampf(body.ang_vel + ang_accel * dt, -Tuning.ROOT_ANGULAR_SPEED, Tuning.ROOT_ANGULAR_SPEED)
	var move := vel * dt
	var turn := ang_vel * dt
	var chosen := 0.0
	for scale in [1.0, 0.5, 0.25, 0.125, 0.0625, 0.03125]:
		var p: Vector2 = body.pos + move * scale
		var a: float = body.angle + turn * scale
		if is_valid(p, a, attached) and (not accept.is_valid() or accept.call(p, a)):
			chosen = scale
			break
	body.pos += move * chosen
	body.angle += turn * chosen
	body.vel = move * chosen / dt
	body.ang_vel = turn * chosen / dt
