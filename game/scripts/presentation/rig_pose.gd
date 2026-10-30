class_name RigPose
extends RefCounted
## 확정 관절 위치 → 뼈 전역 프레임(docs/04 §8). 노드에 의존하지 않아 헤드리스로 검사할 수 있다.
## - 몸통 뼈: 휴지 프레임에 몸통 roll만 적용
## - 위팔/허벅지(SWING): 부모 프레임의 고정 기준축(위팔 -Z=벽 쪽, 허벅지 -Y=아래)에서의 최단 회전.
##   기준축이 swing 원뿔의 중심이므로 정반대 방향(특이점)은 허용 영역 밖이다.
## - 전완/정강이/손/발(CHILD): 부모 뼈의 현재 길이축에서의 최단 회전 × 부모 회전.
## 매 프레임 확정 위치에서 다시 계산하며 이전 회전을 누적하지 않는다(누적 twist·360° 회전 없음).
## 기준축은 휴지 프레임과 정반대가 될 수 없게 설계되어 있다. 그래도 정반대에 가까우면 직전 프레임을 유지한다.

enum Mode { BODY, SWING, CHILD }

## [뼈, 부모 뼈, 시작 관절, 끝 관절, 모드, 기준축(SWING만)]. 부모가 먼저.
const BONES := [
	["pelvis", "", "pelvis", "spine", Mode.BODY, Vector3.ZERO],
	["spine", "pelvis", "spine", "chest", Mode.BODY, Vector3.ZERO],
	["chest", "spine", "chest", "neck", Mode.BODY, Vector3.ZERO],
	["neck", "chest", "neck", "head", Mode.BODY, Vector3.ZERO],
	["head", "neck", "head", "head_top", Mode.BODY, Vector3.ZERO],
	["upperarm_L", "chest", "shoulder_L", "elbow_L", Mode.SWING, Vector3.FORWARD],
	["forearm_L", "upperarm_L", "elbow_L", "wrist_L", Mode.CHILD, Vector3.ZERO],
	["hand_L", "forearm_L", "wrist_L", "hand_L", Mode.CHILD, Vector3.ZERO],
	["upperarm_R", "chest", "shoulder_R", "elbow_R", Mode.SWING, Vector3.FORWARD],
	["forearm_R", "upperarm_R", "elbow_R", "wrist_R", Mode.CHILD, Vector3.ZERO],
	["hand_R", "forearm_R", "wrist_R", "hand_R", Mode.CHILD, Vector3.ZERO],
	["thigh_L", "pelvis", "hip_L", "knee_L", Mode.SWING, Vector3.DOWN],
	["shin_L", "thigh_L", "knee_L", "ankle_L", Mode.CHILD, Vector3.ZERO],
	["foot_L", "shin_L", "ankle_L", "toe_L", Mode.CHILD, Vector3.ZERO],
	["thigh_R", "pelvis", "hip_R", "knee_R", Mode.SWING, Vector3.DOWN],
	["shin_R", "thigh_R", "knee_R", "ankle_R", Mode.CHILD, Vector3.ZERO],
	["foot_R", "shin_R", "ankle_R", "toe_R", Mode.CHILD, Vector3.ZERO],
]
const ANTIPARALLEL_DOT := -0.995

var rest_basis := {}   # 뼈 -> Basis (휴지 전역)
var rest_dir := {}     # 뼈 -> Vector3 (휴지 길이축, 단위)
var _last := {}        # 뼈 -> Basis (직전 결과, 퇴화 시 유지용)


## rest_poses: 뼈 -> Transform3D(휴지 전역). rest_joints: 관절 키 -> 휴지 위치.
## 끝 관절이 rest_joints에 없으면(말단) 뼈의 Y축을 길이축으로 쓴다.
func setup(rest_poses: Dictionary, rest_joints: Dictionary) -> void:
	for entry in BONES:
		var name: String = entry[0]
		if not rest_poses.has(name):
			continue
		var t: Transform3D = rest_poses[name]
		rest_basis[name] = t.basis.orthonormalized()
		var to_key: String = entry[3]
		var dir: Vector3 = (rest_joints[to_key] - t.origin) if rest_joints.has(to_key) else t.basis.y
		rest_dir[name] = dir.normalized()


## 단위 벡터 a를 b로 돌리는 최단 회전. 정반대이면 null 대신 항등을 반환하고 ok=false.
static func arc(a: Vector3, b: Vector3) -> Dictionary:
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if dot < ANTIPARALLEL_DOT:
		return {"q": Quaternion.IDENTITY, "ok": false}
	if dot > 0.999999:
		return {"q": Quaternion.IDENTITY, "ok": true}
	return {"q": Quaternion(a, b).normalized(), "ok": true}


## joints: 관절 키 -> 위치(같은 좌표계), roll_deg: 몸통 벽면 roll.
## 반환: 뼈 -> Transform3D(그 좌표계의 전역 프레임).
func solve(joints: Dictionary, roll_deg: float) -> Dictionary:
	var out := {}
	var roll := Basis(Vector3.BACK, deg_to_rad(roll_deg))
	for entry in BONES:
		var name: String = entry[0]
		if not rest_basis.has(name):
			continue
		var parent: String = entry[1]
		var from_p: Vector3 = joints[entry[2]]
		var dir: Vector3 = (joints[entry[3]] - from_p)
		dir = dir.normalized() if dir.length() > 0.00001 else rest_dir[name]
		var basis: Basis
		match entry[4]:
			Mode.BODY:
				basis = roll * rest_basis[name]
			Mode.SWING:
				# 휴지 길이축을 부모 기준축으로 옮긴 프레임 → 현재 방향으로 최단 회전
				var ref_local: Vector3 = entry[5]
				var to_ref := arc(rest_dir[name], ref_local)
				var ref_world := roll * ref_local
				var to_dir := arc(ref_world, dir)
				if not to_dir.ok:
					basis = _last.get(name, roll * rest_basis[name])
				else:
					basis = Basis(to_dir.q) * roll * Basis(to_ref.q) * rest_basis[name]
			Mode.CHILD:
				var parent_basis: Basis = out[parent].basis if out.has(parent) else rest_basis[parent]
				var parent_rest: Basis = rest_basis[parent]
				var parent_delta: Basis = parent_basis * parent_rest.inverse()
				var parent_rest_dir: Vector3 = rest_dir[parent]
				var parent_dir_now: Vector3 = (parent_delta * parent_rest_dir).normalized()
				var align_rest := arc(rest_dir[name], rest_dir[parent])
				var to_dir := arc(parent_dir_now, dir)
				if not (align_rest.ok and to_dir.ok):
					basis = _last.get(name, parent_delta * rest_basis[name])
				else:
					basis = Basis(to_dir.q) * parent_delta * Basis(align_rest.q) * rest_basis[name]
		basis = basis.orthonormalized()
		_last[name] = basis
		out[name] = Transform3D(basis, from_p)
	return out
