class_name RigCheck
extends RefCounted
## 뼈 프레임 점검(docs/59 §4): RigPose가 만든 뼈 전역 프레임이 사람이 할 수 없는 관절 움직임인지 잰다.
## Anatomy는 관절 위치만 본다. 여기서는 뼈가 길이축으로 도는 것(비틀림)을 본다.
## - 경첩: 팔꿈치·무릎이 모델이 접히는 방향(휴지 T자에서 팔꿈치는 앞, 무릎은 정강이가 뒤)과 다르게 굽으면 옆·뒤로 꺾여 보인다.
## - 아래팔 비틀림: 위팔 기준 아래팔이 길이축으로 돈 각(손바닥 엎침·뒤침).
## - 회전 속도: 뼈가 한 프레임에 길이축으로 도는 각. 위팔·허벅지는 몸(공간) 기준, 아래팔·손·정강이는 바로 윗마디 기준
##   (고관절·어깨가 실제로 돌 때 아랫마디가 함께 도는 것은 사람이 할 수 있는 움직임이라 세지 않는다).

const HINGE_MAX := 30.0         # 도, 굽힘 HINGE_MIN_BEND 이상일 때 접히는 방향과 굽는 방향 차이 한계
const HINGE_MIN_BEND := 20.0    # 도, 이보다 덜 굽으면 경첩을 재지 않음(거의 펴짐)
const ELBOW_BEND_MAX := 145.0   # 도, 팔꿈치 굽힘 한계(위팔·아래팔 살이 닿음)
const FOREARM_TWIST_MAX := 90.0 # 도, 위팔 기준 아래팔 비틀림 한계
const SPIN_MAX := 8.0           # 도/프레임(60fps에서 480°/s), 뼈 길이축 회전 속도 한계
const SPIN_BONES := ["upperarm_", "forearm_", "hand_", "thigh_", "shin_"]
const SPIN_PARENT := {"forearm_": "upperarm_", "hand_": "forearm_", "shin_": "thigh_"}
## 관절 → [위 뼈, 아래 뼈, 끝 뼈, 휴지 때 아래 뼈가 접히는 방향]
const HINGES := {
	"elbow_L": ["upperarm_L", "forearm_L", "hand_L", Vector3.FORWARD], "elbow_R": ["upperarm_R", "forearm_R", "hand_R", Vector3.FORWARD],
	"knee_L": ["thigh_L", "shin_L", "foot_L", Vector3.BACK], "knee_R": ["thigh_R", "shin_R", "foot_R", Vector3.BACK],
}

var _prev := {}   # 뼈 → 직전 프레임 Basis


## 길이축 둘레 비틀림 각(도, −180~180): 회전 q의 axis 둘레 성분(스윙-트위스트 분해).
static func twist_about(q: Quaternion, axis: Vector3) -> float:
	var v := Vector3(q.x, q.y, q.z)
	return rad_to_deg(wrapf(2.0 * atan2(v.dot(axis.normalized()), q.w), -PI, PI))


static func bone_dir(rig: RigPose, frames: Dictionary, name: String) -> Vector3:
	return ((frames[name] as Transform3D).basis * rig.rest_basis[name].inverse() * rig.rest_dir[name]).normalized()


## 관절 굽힘(도). 위 뼈·아래 뼈 시작점과 끝 뼈 시작점(관절 위치)으로 잰다.
static func bend_deg(frames: Dictionary, joint: String) -> float:
	var h: Array = HINGES[joint]
	var a: Vector3 = frames[h[0]].origin
	var b: Vector3 = frames[h[1]].origin
	var c: Vector3 = frames[h[2]].origin
	return rad_to_deg((b - a).angle_to(c - b))


## 모델이 접히는 방향과 실제 굽는 방향의 차이(도). 0 정상, 90 옆으로, 180 뒤로 꺾임. 거의 펴졌으면 NAN.
static func hinge_mismatch(rig: RigPose, frames: Dictionary, joint: String) -> float:
	if bend_deg(frames, joint) < HINGE_MIN_BEND:
		return NAN
	var h: Array = HINGES[joint]
	var up: String = h[0]
	var a: Vector3 = frames[up].origin
	var b: Vector3 = frames[h[1]].origin
	var c: Vector3 = frames[h[2]].origin
	var local: Vector3 = rig.rest_basis[up].inverse() * rig.rest_dir[up].cross(h[3]).normalized()
	var now: Vector3 = ((frames[up] as Transform3D).basis * local).normalized()
	return rad_to_deg(now.angle_to((b - a).cross(c - b).normalized()))


## 위팔 기준 아래팔 비틀림(도, 휴지 0).
static func forearm_twist(rig: RigPose, frames: Dictionary, side: String) -> float:
	var up := "upperarm_" + side
	var fo := "forearm_" + side
	var du: Basis = (frames[up] as Transform3D).basis * rig.rest_basis[up].inverse()
	var df: Basis = (frames[fo] as Transform3D).basis * rig.rest_basis[fo].inverse()
	return twist_about(Quaternion((du.inverse() * df).orthonormalized()), rig.rest_dir[fo])


## 한 프레임 점검. 반환: 위반 목록 [{kind, key, value}]. 회전 속도는 직전 호출과 비교한다(첫 호출은 재지 않음).
func check(rig: RigPose, frames: Dictionary) -> Array:
	var out := []
	for joint in HINGES:
		if not frames.has(HINGES[joint][2]):
			continue
		var mm := hinge_mismatch(rig, frames, joint)
		if not is_nan(mm) and mm > HINGE_MAX:
			out.append({"kind": "hinge", "key": joint, "value": mm})
		if joint.begins_with("elbow") and bend_deg(frames, joint) > ELBOW_BEND_MAX:
			out.append({"kind": "elbow_bend", "key": joint, "value": bend_deg(frames, joint)})
	for side in ["L", "R"]:
		var tw := forearm_twist(rig, frames, side)
		if absf(tw) > FOREARM_TWIST_MAX:
			out.append({"kind": "forearm_twist", "key": "forearm_" + side, "value": tw})
		for b in SPIN_BONES:
			var name: String = b + side
			var basis: Basis = (frames[name] as Transform3D).basis
			var axis := bone_dir(rig, frames, name)
			if SPIN_PARENT.has(b):  # 윗마디 기준
				var parent: Basis = (frames[SPIN_PARENT[b] + side] as Transform3D).basis
				basis = parent.inverse() * basis
				axis = parent.inverse() * axis
			if _prev.has(name):
				var spin := absf(twist_about(Quaternion((basis * (_prev[name] as Basis).inverse()).orthonormalized()), axis))
				if spin > SPIN_MAX + 0.01:
					out.append({"kind": "spin", "key": name, "value": spin})
			_prev[name] = basis
	return out
