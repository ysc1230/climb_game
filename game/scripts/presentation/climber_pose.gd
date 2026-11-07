class_name ClimberPose
extends RefCounted
## 판정 상태 → 표현용 3D 관절 위치(docs/04 §8). play_3d와 해부학 점검(Anatomy, AnatomySweep)이 같이 쓴다.
## 판정은 2D(벽 평면)라서 골반 깊이(Z)와 떠 있는 손발의 깊이는 표현이 정한다.
## - 골반 깊이: 붙은 접점이 허용하는 구간(PoseSolver.body_depth_range) 안에서, 선호 깊이에 가까우면서
##   네 팔다리 모두 해부학적으로 가능한 굽힘이 있는 깊이를 고른다(발을 엉덩이 높이로 들면 엉덩이를 벽에서 뗀다).
## - 끌거나 떠 있는 손발 끝: 기본 깊이(접촉면 + 띄움)에서 안 되면 벽에서 더 떨어진 깊이를 쓴다.
## - 팔다리 굽힘은 LimbIK.solve_limb가 해부학 범위 안에서 고른다. 깊이는 DEPTH_SPEED로 부드럽게 따라간다.

const DEPTH_STEP := 0.03       # 골반 깊이 후보 간격
const DEPTH_SPEED := 1.0       # m/s, 표현 골반 깊이가 목표로 따라가는 빠르기
const LIFT_SPEED := 2.5        # m/s, 떠 있는 손발 끝 깊이가 목표로 따라가는 빠르기
const FREE_END_DEPTHS := [0.0, 0.12, 0.25]  # 떠 있는 말단의 추가 깊이 후보(기본 띄움에 더함)
## 떠 있는 말단이 어느 깊이에서도 불가능하면 벽 평면에서 이만큼까지 비켜 보인다(표현만, 판정 위치는 그대로).
const FREE_END_SHIFTS := [0.08, 0.16]
const SHIFT_DIRS := 6
const SHIFT_LIFT := 0.12       # 비켜 볼 때 쓰는 추가 깊이
const SEARCH_BUDGET := 32      # 프레임당 굽힘 원 계산 상한(불가능한 자세에서 탐색이 길어지지 않게)

var bends := {}        # limb -> 직전 굽힘 축(연속성)
var depth := NAN       # 표현 골반 깊이(부드럽게 따라감)
var free_lift := {}    # limb -> 떠 있는 말단의 추가 깊이(부드럽게 따라감)
var free_shift := {}   # limb -> 떠 있는 말단을 벽 평면에서 비켜 보이는 양(부드럽게 따라감)
var _cache := {}       # 이번 프레임에 구한 굽힘 원(limb·관절·끝 → circle)
var _last_lift := {}   # limb -> 지난 프레임에 고른 떠 있는 말단 추가 깊이·비킴(1단계에서 그대로 시도)
var _last_shift := {}
var _budget := 0


## session: ClimbSession(또는 같은 필드를 가진 것). delta: 프레임 시간.
func compute(session, delta: float) -> Dictionary:
	var body = session.body
	var attached: Dictionary = session.attached()
	var frame := Anatomy.body_basis(body.angle, body.yaw)
	var ang := deg_to_rad(body.angle)
	var up := Vector3(-sin(ang), cos(ang), 0)
	_cache.clear()
	_budget = SEARCH_BUDGET
	var want := _choose(session, body, attached, frame, up)
	var target_depth: float = want.depth
	if is_nan(depth):
		depth = target_depth
	else:
		depth = move_toward(depth, target_depth, DEPTH_SPEED * delta)
	var pelvis := Vector3(body.pos.x, body.pos.y, depth)
	var t := {"pelvis": pelvis, "spine": pelvis + up * 0.22, "chest": pelvis + up * 0.44,
		"neck": pelvis + up * 0.63, "head": pelvis + up * 0.80, "head_top": pelvis + up * 0.94, "up": up}
	var max_step := LimbIK.PRESENTATION_JOINT_SPEED_DEG * delta
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var lift_now: float = free_lift.get(limb, 0.0)
		free_lift[limb] = move_toward(lift_now, float(want.lift[limb]), LIFT_SPEED * delta)
		var shift_now: Vector2 = free_shift.get(limb, Vector2.ZERO)
		free_shift[limb] = shift_now.move_toward(want.shift[limb], LIFT_SPEED * delta)
		var root := _root(body, limb, depth)
		var end := _end(session, limb, float(free_lift[limb]), free_shift[limb])
		var ik := LimbIK.solve_circle(_circle(limb, root, end, frame, pelvis, up, true, _free(session, limb)), bends.get(limb, Vector3.ZERO), max_step)
		bends[limb] = ik.bend
		var mid: Vector3 = ik.mid
		var s := "L" if PoseSolver.side_sign(limb) < 0 else "R"
		if hand:
			t["shoulder_" + s] = root
			t["elbow_" + s] = mid
			t["wrist_" + s] = end
			t["hand_" + s] = end + (end - mid).normalized() * 0.09
		else:
			t["hip_" + s] = root
			t["knee_" + s] = mid
			t["ankle_" + s] = end
			t["toe_" + s] = end + Anatomy.foot_direction(mid, end, frame) * Anatomy.FOOT_LENGTH
	return t


## 끌거나 떠 있는 손발인가(붙음·준비가 아님).
static func _free(session, limb: StringName) -> bool:
	return not (session.limbs[limb].state in ["Attached", "Armed"])


static func _root(body, limb: StringName, pelvis_depth: float) -> Vector3:
	var j2 := PoseSolver.joint_position(body.pos, body.angle, limb, body.yaw)
	return Vector3(j2.x, j2.y, pelvis_depth + PoseSolver.joint_depth_offset(limb, body.yaw))


static func _end(session, limb: StringName, lift: float, shift := Vector2.ZERO) -> Vector3:
	var e2: Vector2 = session.limbs[limb].pos + shift
	var stuck: bool = session.limbs[limb].state in ["Attached", "Armed"]
	var z := Tuning.CONTACT_DEPTH if stuck else Tuning.CONTACT_DEPTH + Tuning.FREE_ENDPOINT_LIFT + lift
	return Vector3(e2.x, e2.y, z)


## 목표 골반 깊이와 떠 있는 말단의 [추가 깊이, 비킴]. 점수는 팔다리마다 LimbIK.local_violation(지금 굽힘 쪽에서
## 가능한 자세가 있는가, 없으면 옮겨 가는 길이 얼마나 막혔나)의 합.
## 1단계: 떠 있는 말단은 지금 옵션 그대로 두고 골반 깊이 후보(지금 → 선호 → 바깥쪽)를 모두 본다.
## 2단계: 0인 깊이가 없으면 1단계에서 가장 좋은 깊이와 지금 깊이에서 떠 있는 말단 옵션을 모두 본다.
## 마지막으로 떠 있는 말단이 제자리(옵션 없음)로도 되면 되돌린다.
func _choose(session, body, attached: Dictionary, frame: Basis, up: Vector3) -> Dictionary:
	var r := PoseSolver.body_depth_range(body.pos, body.angle, attached, body.yaw)
	if not r.is_finite():
		r = Vector2(Tuning.PELVIS_DEPTH_PREFERRED, Tuning.PELVIS_DEPTH_PREFERRED)
	var start := clampf(Tuning.PELVIS_DEPTH_PREFERRED, r.x, r.y)
	var cands: Array[float] = [start]
	var now := clampf(depth, r.x, r.y) if not is_nan(depth) else start
	if absf(now - start) > 0.001:
		cands.push_front(now)
	var k := 1
	while start + k * DEPTH_STEP <= r.y + 0.0001 or start - k * DEPTH_STEP >= r.x - 0.0001:
		if start + k * DEPTH_STEP <= r.y + 0.0001:
			cands.append(start + k * DEPTH_STEP)
		if start - k * DEPTH_STEP >= r.x - 0.0001:
			cands.append(start - k * DEPTH_STEP)
		k += 1
	var cur_opt := {}
	for limb in PoseSolver.LIMBS:
		cur_opt[limb] = [_last_lift.get(limb, 0.0), _last_shift.get(limb, Vector2.ZERO)]
	var best := {}
	var best_v := INF
	for dpt in cands:
		var res := _score_depth(session, body, frame, up, dpt, cur_opt, best_v)
		if res.total < best_v:
			best_v = res.total
			best = res
		if best_v <= 0.0 or _budget <= 0:
			break
	if best_v > 0.0 and _budget > 0:
		for dpt in [float(best.get("depth", now)), now]:
			var res := _score_depth(session, body, frame, up, dpt, {}, best_v)
			if res.total < best_v:
				best_v = res.total
				best = res
			if best_v <= 0.0 or _budget <= 0:
				break
	if best.is_empty():  # 예산이 다 된 경우: 지금 값 유지
		best = {"depth": now, "lift": {}, "shift": {}}
		for limb in PoseSolver.LIMBS:
			best.lift[limb] = cur_opt[limb][0]
			best.shift[limb] = cur_opt[limb][1]
	# 떠 있는 말단은 제자리로 돼도 되면 되돌린다(올린 채로 남지 않게)
	var pelvis := Vector3(body.pos.x, body.pos.y, best.depth)
	for limb in PoseSolver.LIMBS:
		if session.limbs[limb].state in ["Attached", "Armed"]:
			continue
		if float(best.lift[limb]) == 0.0 and best.shift[limb] == Vector2.ZERO:
			continue
		var c := _circle(limb, _root(body, limb, best.depth), _end(session, limb, 0.0), frame, pelvis, up, false, true)
		if not c.is_empty() and LimbIK.local_violation(c, bends.get(limb, Vector3.ZERO)) <= 0.0:
			best.lift[limb] = 0.0
			best.shift[limb] = Vector2.ZERO
	for limb in PoseSolver.LIMBS:
		_last_lift[limb] = best.lift[limb]
		_last_shift[limb] = best.shift[limb]
	return best


## 골반 깊이 하나의 점수. opts: limb → [추가 깊이, 비킴](떠 있는 말단에 이것만 씀). 비면 떠 있는 말단 옵션을 모두 본다.
func _score_depth(session, body, frame: Basis, up: Vector3, dpt: float, opts: Dictionary, bound: float) -> Dictionary:
	var pelvis := Vector3(body.pos.x, body.pos.y, dpt)
	var total := 0.0
	var lift := {}
	var shift := {}
	for limb in PoseSolver.LIMBS:
		var root := _root(body, limb, dpt)
		var stuck: bool = session.limbs[limb].state in ["Attached", "Armed"]
		var options: Array = [[0.0, Vector2.ZERO]] if stuck else ([opts[limb]] if opts.has(limb) else _free_options())
		var lv := INF
		for opt in options:
			var c := _circle(limb, root, _end(session, limb, opt[0], opt[1]), frame, pelvis, up, false, not stuck)
			if c.is_empty():
				break
			var v := LimbIK.local_violation(c, bends.get(limb, Vector3.ZERO))
			if v < lv:
				lv = v
				lift[limb] = opt[0]
				shift[limb] = opt[1]
			if v <= 0.0:
				break
		total += lv
		if total >= bound or lv == INF:
			return {"total": INF}
	return {"total": total, "depth": dpt, "lift": lift, "shift": shift}


## 같은 프레임 안 굽힘 원 캐시. 고르기용은 거친 후보(SEARCH_SAMPLES)·예산 안, force(실제 표시용)는 정밀 후보·예산 무관. 예산이 다 되면 {}.
func _circle(limb: StringName, root: Vector3, end: Vector3, frame: Basis, pelvis: Vector3, up: Vector3, force := false, free := false) -> Dictionary:
	var key := [limb, root, end, pelvis, force, free]
	if _cache.has(key):
		return _cache[key]
	if not force:
		if _budget <= 0:
			return {}
		_budget -= 1
	var c := LimbIK.circle(limb, root, end, frame, pelvis, up, LimbIK.BEND_SAMPLES if force else LimbIK.SEARCH_SAMPLES, free)
	_cache[key] = c
	return c


## 떠 있는 말단의 후보 [추가 깊이, 비킴]: 제자리에서 깊이만 바꾸기, 그다음 가까운 거리부터 SHIFT_DIRS 방향으로 비키기.
static func _free_options() -> Array:
	var out: Array = []
	for extra in FREE_END_DEPTHS:
		out.append([extra, Vector2.ZERO])
	for r in FREE_END_SHIFTS:
		for k in SHIFT_DIRS:
			out.append([SHIFT_LIFT, Vector2.from_angle(TAU * k / SHIFT_DIRS) * r])
	return out
