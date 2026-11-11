class_name ClimberPose
extends RefCounted
## 판정 상태 → 표현용 3D 관절 위치(docs/04 §8). play_3d와 해부학 점검(Anatomy, AnatomySweep)이 같이 쓴다.
## 판정은 2D(벽 평면)라서 골반 깊이(Z)와 떠 있는 손발의 깊이는 표현이 정한다.
## - 골반 깊이: 붙은 접점이 허용하는 구간(PoseSolver.body_depth_range) 안에서, 선호 깊이에 가까우면서
##   네 팔다리 모두 해부학적으로 가능한 굽힘이 있는 깊이를 고른다(발을 엉덩이 높이로 들면 엉덩이를 벽에서 뗀다).
## - 끌거나 떠 있는 손발 끝: 기본 깊이(접촉면 + 띄움)에서 안 되면 벽에서 더 떨어진 깊이를 쓴다.
## - 팔다리 굽힘은 LimbIK.solve_limb가 해부학 범위 안에서 고른다. 깊이는 DEPTH_SPEED로 부드럽게 따라간다.

## 몸통·머리 관절 높이(골반 기준, 위 방향). 2026-11-11 B안(docs/35 §6): 몸통이 길고 머리 1.4배. 이전 0.22/0.44/0.63/0.80/0.94.
const SPINE_UP := 0.27
const CHEST_UP := 0.54
const NECK_UP := 0.76
const HEAD_UP := 0.84
const HEAD_TOP_UP := 1.16
const DEPTH_STEP := 0.03       # 골반 깊이 후보 간격
const DEPTH_SPEED := 1.0       # m/s, 표현 골반 깊이가 목표로 따라가는 빠르기
const LIFT_SPEED := 2.5        # m/s, 떠 있는 손발 끝 깊이가 목표로 따라가는 빠르기
const FREE_END_DEPTHS := [0.0, 0.12, 0.25]  # 떠 있는 발 끝의 추가 깊이 후보(기본 띄움에 더함). 벽 평면 위치는 판정 그대로
const FREE_HAND_DEPTHS := [0.0, -0.06, -0.12]  # 떠 있는 손 끝: 벽 쪽으로 붙이기(−0.12면 접촉면 깊이)
const LIFT_HOLD_TICKS := 20   # 떠 있는 발의 추가 깊이를 한 번 바꾸면 이만큼은 유지(오락가락 방지)
const HYSTERESIS := 0.02       # 새 깊이 후보는 지금 목표보다 점수가 이만큼 이상 나을 때만 바꾼다
const SEARCH_BUDGET := 32      # 프레임당 굽힘 원 계산 상한(불가능한 자세에서 탐색이 길어지지 않게)

var bends := {}        # limb -> 직전 굽힘 축(연속성)
var depth := NAN       # 표현 골반 깊이(부드럽게 따라감)
var free_lift := {}    # limb -> 떠 있는 말단의 추가 깊이(부드럽게 따라감)
var _cache := {}       # 이번 프레임에 구한 굽힘 원(limb·관절·끝 → circle)
var _target := {}      # 목표 {depth, lift: limb → 추가 깊이}. 가능하면 유지한다
var _lift_hold := {}   # limb → 떠 있는 발 추가 깊이를 바꾼 뒤 남은 유지 틱
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
	for limb in _lift_hold.keys():
		_lift_hold[limb] = maxi(0, int(_lift_hold[limb]) - 1)
	var want := _choose(session, body, attached, frame, up)
	var target_depth: float = want.depth
	if is_nan(depth):
		depth = target_depth
	else:
		depth = move_toward(depth, target_depth, DEPTH_SPEED * delta)
	var pelvis := Vector3(body.pos.x, body.pos.y, depth)
	var t := {"pelvis": pelvis, "spine": pelvis + up * SPINE_UP, "chest": pelvis + up * CHEST_UP,
		"neck": pelvis + up * NECK_UP, "head": pelvis + up * HEAD_UP, "head_top": pelvis + up * HEAD_TOP_UP, "up": up}
	var max_step := LimbIK.PRESENTATION_JOINT_SPEED_DEG * delta
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var lift_now: float = free_lift.get(limb, 0.0)
		free_lift[limb] = move_toward(lift_now, float(want.lift[limb]), LIFT_SPEED * delta)
		var root := _root(body, limb, depth)
		var end := _end(session, limb, float(free_lift[limb]))
		var ik := LimbIK.solve_circle(_circle(limb, root, end, frame, pelvis, up, true, _free(session, limb)), bends.get(limb, Vector3.ZERO), max_step)
		bends[limb] = ik.bend
		var mid: Vector3 = ik.mid
		var s := "L" if PoseSolver.side_sign(limb) < 0 else "R"
		if hand:
			t["shoulder_" + s] = root
			t["elbow_" + s] = mid
			t["wrist_" + s] = end
			t["hand_" + s] = end + (end - mid).normalized() * Anatomy.HAND_LENGTH
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


static func _end(session, limb: StringName, lift: float) -> Vector3:
	var e2: Vector2 = session.limbs[limb].pos
	var stuck: bool = session.limbs[limb].state in ["Attached", "Armed"]
	var z := Tuning.CONTACT_DEPTH if stuck else Tuning.CONTACT_DEPTH + Tuning.FREE_ENDPOINT_LIFT + lift
	return Vector3(e2.x, e2.y, z)


## 목표 골반 깊이와 떠 있는 말단의 추가 깊이. 지금 목표가 그대로 가능하면 유지한다(떨림 방지, 2026-11-08 사용자 보고:
## "움직일 때 팔이 심각하게 떨린다" — 손을 띄우고 비키는 선택이 매 틱 켜졌다 꺼졌다 했다).
## 지금 목표가 불가능할 때만 다시 찾는다: 1단계 골반 깊이 후보 모두(떠 있는 말단은 지금 깊이 그대로),
## 2단계 떠 있는 말단의 추가 깊이 후보. 새 후보는 지금보다 확실히 나을 때만(HYSTERESIS) 바꾼다.
## 점수는 팔다리마다 LimbIK.local_violation(지금 굽힘 쪽에서 가능한 자세가 있는가)의 합.
func _choose(session, body, attached: Dictionary, frame: Basis, up: Vector3) -> Dictionary:
	var r := PoseSolver.body_depth_range(body.pos, body.angle, attached, body.yaw)
	if not r.is_finite():
		r = Vector2(Tuning.PELVIS_DEPTH_PREFERRED, Tuning.PELVIS_DEPTH_PREFERRED)
	var start := clampf(Tuning.PELVIS_DEPTH_PREFERRED, r.x, r.y)
	if _target.is_empty():
		_target = {"depth": start, "lift": {}}
	_target.depth = clampf(float(_target.depth), r.x, r.y)
	for limb in PoseSolver.LIMBS:
		if not _free(session, limb) or not _target.lift.has(limb):
			_target.lift[limb] = 0.0  # 붙은 손발은 띄우지 않는다. 다시 떼면 0부터
	var cur := _score_depth(session, body, frame, up, _target.depth, _target.lift, true)
	if cur.total <= 0.0:
		return _target
	var cands: Array[float] = [float(_target.depth)]
	if absf(start - float(_target.depth)) > 0.001:
		cands.append(start)
	var k := 1
	while start + k * DEPTH_STEP <= r.y + 0.0001 or start - k * DEPTH_STEP >= r.x - 0.0001:
		if start + k * DEPTH_STEP <= r.y + 0.0001:
			cands.append(start + k * DEPTH_STEP)
		if start - k * DEPTH_STEP >= r.x - 0.0001:
			cands.append(start - k * DEPTH_STEP)
		k += 1
	var best := {}
	var best_v := INF
	for dpt in cands:
		var res := _score_depth(session, body, frame, up, dpt, _target.lift, false)
		if res.total < best_v:
			best_v = res.total
			best = res
		if best_v <= 0.0 or _budget <= 0:
			break
	if best_v > 0.0 and _budget > 0:
		for dpt in [float(best.get("depth", _target.depth)), float(_target.depth)]:
			var res := _score_depth(session, body, frame, up, dpt, {}, false)
			if res.total < best_v:
				best_v = res.total
				best = res
			if best_v <= 0.0 or _budget <= 0:
				break
	if not best.is_empty() and best_v < float(cur.total) - HYSTERESIS:
		for limb in PoseSolver.LIMBS:
			if float(best.lift.get(limb, 0.0)) != float(_target.lift.get(limb, 0.0)):
				_lift_hold[limb] = LIFT_HOLD_TICKS
		_target = {"depth": best.depth, "lift": best.lift}
	return _target


## 골반 깊이 하나의 점수. lifts: limb → 떠 있는 말단 추가 깊이(이것만 씀). 비면 FREE_END_DEPTHS를 모두 본다.
## fine이면 정밀 후보(표시와 같은 원)로, 아니면 거친 후보로 예산 안에서 본다.
func _score_depth(session, body, frame: Basis, up: Vector3, dpt: float, lifts: Dictionary, fine: bool) -> Dictionary:
	var pelvis := Vector3(body.pos.x, body.pos.y, dpt)
	var total := 0.0
	var lift := {}
	for limb in PoseSolver.LIMBS:
		var root := _root(body, limb, dpt)
		var free := _free(session, limb)
		# 떠 있는 손발 끝의 깊이 후보: 발은 벽에서 더 띄우기(무릎 공간), 손은 벽 쪽으로 붙이기(얼굴 앞을 지날 때 머리 공간).
		# 벽 평면 위치는 판정 그대로. 한 번 바꾸면 LIFT_HOLD_TICKS 동안 유지(손을 띄우고 비키는 선택이 매 틱 바뀌어 떨렸다, 2026-11-08).
		var options: Array = [0.0]
		if free:
			if lifts.has(limb):
				options = [lifts[limb]]
			elif int(_lift_hold.get(limb, 0)) > 0:
				options = [_target.lift.get(limb, 0.0)]
			else:
				options = FREE_HAND_DEPTHS if PoseSolver.is_hand(limb) else FREE_END_DEPTHS
		var lv := INF
		for extra in options:
			var c := _circle(limb, root, _end(session, limb, extra), frame, pelvis, up, fine, free)
			if c.is_empty():
				break
			var v := LimbIK.local_violation(c, bends.get(limb, Vector3.ZERO))
			if v < lv:
				lv = v
				lift[limb] = extra
			if v <= 0.0:
				break
		if lv == INF:
			return {"total": INF}
		total += lv
	return {"total": total, "depth": dpt, "lift": lift}


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
