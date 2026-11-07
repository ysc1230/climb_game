class_name Anatomy
extends RefCounted
## 표현용 관절 위치의 해부학 점검(docs/04 §8.4). "아주 유연한 사람도 못 하는 자세"를 숫자로 정의한다.
## 몸 기준 축: 오른쪽 R = B·X, 위 U = B·Y, 앞(벽 쪽) A = B·(−Z), B = roll(Z축) × yaw(Y축)(RigPose와 같은 합성).
##
## 비틀림(어깨·고관절 회전): 휴지 기준 굽힘 방향을 지금 위팔/허벅지 방향으로 옮긴 기준과 실제 굽힘 방향 사이 각.
## +는 바깥돌림(외회전), −는 안돌림(내회전).
## - 어깨: 옆으로 든 T자세(아래팔이 앞으로 굽음)에서 최단 회전(스윙-트위스트)으로 옮긴다.
## - 고관절: 선 자세(정강이가 뒤로 굽음)에서 굴곡(앞으로 들기) → 벌림/모음 순서로 옮긴다(ISB 관절 좌표계와 같은 순서).
##   최단 회전으로 재면 무릎을 높이 든 자세(하이스텝·드롭니)에서 회전각이 부풀려진다(Codman 역설).

const FOOT_LENGTH := 0.158

## 비틀림 허용 범위(도). 유연한 사람 기준의 바깥 한계로, 이를 넘으면 해부학적으로 불가능한 자세로 본다.
const ARM_TWIST := Vector2(-100.0, 110.0)    # 어깨 안돌림 100°, 바깥돌림 110°
const LEG_TWIST := Vector2(-70.0, 90.0)      # 고관절 안돌림 70°(드롭니), 바깥돌림 90°(개구리 자세)
## 고관절 굴곡각(허벅지-몸통 사이) 범위: 뒤로 젖힘 30°, 앞으로 들기 160°. 몸통이 한 덩어리라 골반 뒤 기울기(20~30°)가
## 따로 없으므로, 유연한 사람의 고관절 굴곡 135~145°에 골반 기울기를 더한 값으로 잡는다(무릎을 가슴까지 올리는 락오버).
const HIP_FLEXION := Vector2(-30.0, 160.0)
const SHOULDER_EXTENSION_MAX := 0.60         # 위팔의 뒤쪽 성분(sin 37°)
const HIP_EXTENSION_MAX := 0.50              # 허벅지의 뒤쪽 성분(sin 30°)
const ANKLE_RANGE := Vector2(40.0, 130.0)    # 정강이(무릎→발목)와 발(발목→발끝) 사이 각
const WALL_CLEARANCE := 0.01                 # 팔꿈치·무릎은 벽면(z = 0)보다 이만큼 앞
const TORSO_CLEARANCE := 0.15                # 팔꿈치·무릎이 몸통 축(골반+0.05 ~ +0.50)에 이보다 가까우면 몸을 뚫음
const FREE_LEG_SHIN_UP_MAX := 0.25           # 발을 들어 옮길 때 정강이(무릎→발)의 위쪽 성분 한계(무릎이 발보다 아래로 처지지 않음)
const HEAD_CENTER_UP := 0.84                 # 머리 중심: 골반 + 위 × 0.84
const HEAD_CLEARANCE := 0.15                 # 팔 뼈(위팔·아래팔)가 머리 중심에 이보다 가까우면 머리를 뚫음(머리 0.12 + 팔 0.035)
const STRAIGHT_EPS := 0.06                   # 굽힘(아래 뼈의 수직 성분 비)이 이보다 작으면(약 3°, 거의 펴짐) 비틀림을 재지 않음


static func body_basis(angle_deg: float, yaw_deg: float) -> Basis:
	return Basis(Vector3.BACK, deg_to_rad(angle_deg)) * Basis(Vector3.UP, deg_to_rad(yaw_deg))


## 근위 뼈 방향 p, 원위 끝까지 방향 q(중간 관절 → 끝). p0·f0: 휴지 방향과 그때의 굽힘 방향. 굽힘이 거의 없으면 NAN.
static func twist_deg(p: Vector3, q: Vector3, p0: Vector3, f0: Vector3, side: float) -> float:
	var act := q - p * q.dot(p)
	if act.length() < STRAIGHT_EPS * q.length():
		return NAN
	if p.dot(p0) < -0.995:
		return NAN  # 스윙이 정해지지 않음(정반대 방향)
	var swing := Quaternion(p0, p) if p.dot(p0) < 0.99999 else Quaternion.IDENTITY
	var ref: Vector3 = swing * f0
	ref = (ref - p * ref.dot(p)).normalized()
	return rad_to_deg(ref.signed_angle_to(act.normalized(), p)) * side


## 팔다리 하나의 비틀림. root 어깨/고관절, mid 팔꿈치/무릎, end 손목/발목.
static func limb_twist(limb: StringName, root: Vector3, mid: Vector3, end: Vector3, frame: Basis) -> float:
	var s := PoseSolver.side_sign(limb)
	var p := (mid - root).normalized()
	var q := end - mid
	if PoseSolver.is_hand(limb):
		return twist_deg(p, q, frame * Vector3(s, 0, 0), frame * Vector3.FORWARD, s)
	return hip_twist_deg(p, q, frame, s)


## 고관절 굴곡각(도): 허벅지를 몸 옆에서 본 시상면 각. 0 = 아래, 90 = 앞(벽 쪽), 180 = 위.
static func hip_flexion_deg(p: Vector3, frame: Basis) -> float:
	var down := -p.dot(frame * Vector3.UP)
	var ant := -p.dot(frame * Vector3.BACK)
	if Vector2(down, ant).length() < 0.2:
		return 0.0  # 허벅지가 거의 옆으로: 굴곡이 정해지지 않음
	return rad_to_deg(atan2(ant, down))


static func hip_twist_deg(p: Vector3, q: Vector3, frame: Basis, side: float) -> float:
	var act := q - p * q.dot(p)
	if act.length() < STRAIGHT_EPS * q.length():
		return NAN
	var x := frame * Vector3.RIGHT
	var flex := deg_to_rad(hip_flexion_deg(p, frame))
	var r1 := Basis(x, flex)
	var v1: Vector3 = r1 * (frame * Vector3.DOWN)
	var r2 := Quaternion.IDENTITY if v1.dot(p) > 0.99999 or v1.dot(p) < -0.995 else Quaternion(v1, p)
	var ref: Vector3 = r2 * (r1 * (frame * Vector3.BACK))
	ref = (ref - p * ref.dot(p)).normalized()
	return rad_to_deg(ref.signed_angle_to(act.normalized(), p)) * side


static func twist_ok(limb: StringName, twist: float) -> bool:
	if is_nan(twist):
		return true
	var r := ARM_TWIST if PoseSolver.is_hand(limb) else LEG_TWIST
	return twist >= r.x and twist <= r.y


## 발 방향: 발끝은 벽 쪽(−Z)·약간 아래를 향하되, 정강이와의 각이 발목 범위 안이 되도록 정강이 쪽 평면에서 돌린다.
const FOOT_WANT := Vector3(0, -0.32, -0.95)   # 발끝: 벽 쪽·약간 아래
const FOOT_ANKLE_SOLVE := Vector2(55.0, 115.0)  # 발 방향을 고를 때 쓰는 발목 각 범위(점검 범위보다 안쪽)


static func foot_direction(knee: Vector3, ankle: Vector3, frame: Basis) -> Vector3:
	var shin := (ankle - knee).normalized()
	var f := FOOT_WANT.normalized()
	var ang := rad_to_deg(shin.angle_to(f))
	var lo := FOOT_ANKLE_SOLVE.x
	var hi := FOOT_ANKLE_SOLVE.y
	if ang >= lo and ang <= hi:
		return f
	var axis := shin.cross(f)
	if axis.length() < 0.0001:
		axis = shin.cross(frame * Vector3.RIGHT)
	axis = axis.normalized()
	# shin을 axis로 goal°만큼 돌린 방향 = 발목 각이 goal인 발 방향(f와 같은 평면)
	return shin.rotated(axis, deg_to_rad(clampf(ang, lo, hi))).normalized()


## 팔 두 뼈(root→mid, mid→end)와 머리 중심 사이 최소 거리.
static func arm_head_distance(root: Vector3, mid: Vector3, end: Vector3, head: Vector3) -> float:
	return minf(_seg_dist(head, root, mid), _seg_dist(head, mid, end))


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## 자세 하나 점검. t: ClimberPose.compute 결과. 반환: 위반 목록 [{kind, limb, value}].
## free: limb → 끌거나 떠 있는가(발이면 FREE_LEG 규칙도 점검).
static func check(t: Dictionary, angle_deg: float, yaw_deg: float, free := {}) -> Array:
	var out: Array = []
	var frame := body_basis(angle_deg, yaw_deg)
	var post := frame * Vector3.BACK
	var up: Vector3 = t.up
	var torso_a: Vector3 = t.pelvis + up * 0.05
	var torso_b: Vector3 = t.pelvis + up * 0.50
	for limb in PoseSolver.LIMBS:
		var hand := PoseSolver.is_hand(limb)
		var s := "L" if PoseSolver.side_sign(limb) < 0 else "R"
		var root: Vector3 = t[("shoulder_" if hand else "hip_") + s]
		var mid: Vector3 = t[("elbow_" if hand else "knee_") + s]
		var end: Vector3 = t[("wrist_" if hand else "ankle_") + s]
		var tw := limb_twist(limb, root, mid, end, frame)
		if not twist_ok(limb, tw):
			out.append({"kind": "twist", "limb": limb, "value": tw})
		if mid.z < WALL_CLEARANCE:
			out.append({"kind": "in_wall", "limb": limb, "value": mid.z})
		if _seg_dist(mid, torso_a, torso_b) < TORSO_CLEARANCE:
			out.append({"kind": "in_torso", "limb": limb, "value": _seg_dist(mid, torso_a, torso_b)})
		if hand:
			var hd := arm_head_distance(root, mid, end, t.pelvis + up * HEAD_CENTER_UP)
			if hd < HEAD_CLEARANCE:
				out.append({"kind": "in_head", "limb": limb, "value": hd})
		var back := (mid - root).normalized().dot(post)
		if back > (SHOULDER_EXTENSION_MAX if hand else HIP_EXTENSION_MAX):
			out.append({"kind": "extension", "limb": limb, "value": back})
		if not hand and free.get(limb, false):
			var shin_up := (end - mid).normalized().dot(frame * Vector3.UP)
			if shin_up > FREE_LEG_SHIN_UP_MAX:
				out.append({"kind": "free_drop_knee", "limb": limb, "value": shin_up})
		if not hand:
			var flex := hip_flexion_deg((mid - root).normalized(), frame)
			if flex < HIP_FLEXION.x or flex > HIP_FLEXION.y:
				out.append({"kind": "flexion", "limb": limb, "value": flex})
		if not hand:
			var toe: Vector3 = t["toe_" + s]
			var ankle_deg := rad_to_deg((end - mid).angle_to(toe - end))
			if ankle_deg < ANKLE_RANGE.x or ankle_deg > ANKLE_RANGE.y:
				out.append({"kind": "ankle", "limb": limb, "value": ankle_deg})
	return out
