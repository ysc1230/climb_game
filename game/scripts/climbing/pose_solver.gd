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


static func can_reach(pelvis: Vector2, angle_deg: float, limb: StringName, slot: Vector2) -> bool:
	var d := limb_distance(pelvis, angle_deg, limb, slot)
	var r := reach_of(limb)
	return d >= r.x - Tuning.DISTANCE_EPSILON and d <= r.y + Tuning.DISTANCE_EPSILON


## 고정된 모든 접점의 길이·관절 조건과 몸통 회전 제한.
static func is_valid(pelvis: Vector2, angle_deg: float, attached: Dictionary) -> bool:
	if not (is_finite(pelvis.x) and is_finite(pelvis.y) and is_finite(angle_deg)):
		return false
	if absf(angle_deg) > Tuning.BODY_ANGLE_LIMIT_DEG + Tuning.DISTANCE_EPSILON:
		return false
	for limb in attached:
		if not can_reach(pelvis, angle_deg, limb, attached[limb]):
			return false
	return true


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


## 목표 자세 비용. feet는 이번 탐색 동안 고정한 지지 발 집합.
static func cost(pelvis: Vector2, angle_deg: float, attached: Dictionary, feet: Array) -> float:
	var total := 0.0
	var sum_x := 0.0
	for limb in attached:
		var slot: Vector2 = attached[limb]
		sum_x += slot.x
		var d := limb_distance(pelvis, angle_deg, limb, slot)
		if is_hand(limb):
			total += Tuning.W_HAND * pow((d - Tuning.PREF_ARM) / Tuning.ARM_REACH_NOMINAL.y, 2)
		elif feet.has(limb):
			total += Tuning.W_FOOT * pow((d - Tuning.PREF_LEG) / Tuning.LEG_REACH_NOMINAL.y, 2)
	total += Tuning.W_ANGLE * pow(angle_deg / Tuning.BODY_ANGLE_LIMIT_DEG, 2)
	if attached.size() > 0:
		total += Tuning.W_LATERAL * pow(pelvis.x - sum_x / attached.size(), 2)
	return total


## 27후보 근방 탐색. 반환값 Vector3(x, y, angle)은 목표 자세이며 즉시 이동 위치가 아니다.
static func find_target(pelvis: Vector2, angle_deg: float, attached: Dictionary, feet: Array) -> Vector3:
	var best := Vector3(pelvis.x, pelvis.y, angle_deg)
	if attached.is_empty():
		return best
	var best_cost := cost(pelvis, angle_deg, attached, feet) if is_valid(pelvis, angle_deg, attached) else INF
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
					if not is_valid(p, a, attached):
						continue
					var c := cost(p, a, attached, feet)
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


## 지지 중 한 틱의 골반 보정 운동. body는 {pos, vel, angle, ang_vel}을 갖는 BodyState.
## 제약을 깨는 이동은 1, 1/2 … 1/32, 0배로 줄여 고른다.
static func step_body(body: BodyState, attached: Dictionary, feet: Array, dt: float = Tuning.DT) -> void:
	var target := find_target(body.pos, body.angle, attached, feet)
	var accel := (Vector2(target.x, target.y) - body.pos) * Tuning.ROOT_POS_GAIN - body.vel * Tuning.ROOT_POS_DAMPING
	accel = accel.limit_length(Tuning.ROOT_ACCEL_LIMIT)
	var vel := (body.vel + accel * dt).limit_length(Tuning.ROOT_SPEED_LIMIT)
	var ang_accel := clampf((target.z - body.angle) * Tuning.ROOT_ANGLE_GAIN - body.ang_vel * Tuning.ROOT_ANGLE_DAMPING, -Tuning.ROOT_ANGULAR_ACCEL, Tuning.ROOT_ANGULAR_ACCEL)
	var ang_vel := clampf(body.ang_vel + ang_accel * dt, -Tuning.ROOT_ANGULAR_SPEED, Tuning.ROOT_ANGULAR_SPEED)
	var move := vel * dt
	var turn := ang_vel * dt
	var chosen := 0.0
	for scale in [1.0, 0.5, 0.25, 0.125, 0.0625, 0.03125]:
		if is_valid(body.pos + move * scale, body.angle + turn * scale, attached):
			chosen = scale
			break
	body.pos += move * chosen
	body.angle += turn * chosen
	body.vel = move * chosen / dt
	body.ang_vel = turn * chosen / dt
