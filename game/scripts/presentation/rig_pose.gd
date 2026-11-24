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
## 엉덩이 보조 뼈(docs/37 4단계): 골반과 허벅지 회전의 HELPER_SHARE 지점(구면 보간)으로 돈다. 모델이 골반↔허벅지
## 사이 정점을 이 뼈로 이어(build_tripo_rig.py), 다리를 크게 들어도 엉덩이·가랑이가 안으로 접히지 않는다.
## 보조 뼈 → [부모 쪽 뼈, 자식 쪽 뼈]. 모델에 없으면 건너뛴다.
const HELPERS := {"hiphelp_L": ["pelvis", "thigh_L"], "hiphelp_R": ["pelvis", "thigh_R"]}
const HELPER_SHARE := 0.5
## 골반 기울기(docs/37 2단계): 허벅지가 옆으로 PELVIS_TILT_FROM° 넘게 벌어지면 골반 뼈가 그 다리 쪽을 들어 올린다
## (PELVIS_TILT_FULL°에서 최대 PELVIS_TILT_MAX°). 허리·허벅지 뼈는 관절 위치를 그대로 따르므로 가슴과 관절은 안 바뀐다.
const PELVIS_TILT_FROM := 45.0
const PELVIS_TILT_FULL := 90.0
const PELVIS_TILT_MAX := 15.0
## 뼈 비틀림(docs/37 3단계). 허벅지: 무릎 앞면(휴지 때 벽 쪽)이 실제 굽는 방향을 본다. 굽힘이 TWIST_BEND_MIN보다
## 작으면(거의 펴짐) 돌리지 않고 TWIST_BEND_FULL까지 서서히 켠다. 발: 발등이 정강이 반대쪽·몸 위쪽을 본다
## (붙은 발은 위쪽 비중이 커서 발바닥이 아래, 뗀 발은 정강이를 따라 늘어뜨림).
const TWIST_BEND_MIN := 0.02
const TWIST_BEND_FULL := 0.08
const FOOT_UP_WEIGHT_STUCK := 2.0
const FOOT_UP_WEIGHT_FREE := 0.5

var rest_basis := {}   # 뼈 -> Basis (휴지 전역)
var rest_dir := {}     # 뼈 -> Vector3 (휴지 길이축, 단위)
var _last := {}        # 뼈 -> Basis (직전 결과, 퇴화 시 유지용)


## rest_poses: 뼈 -> Transform3D(휴지 전역). rest_joints: 관절 키 -> 휴지 위치.
## 끝 관절이 rest_joints에 없으면(말단) 뼈의 Y축을 길이축으로 쓴다.
func setup(rest_poses: Dictionary, rest_joints: Dictionary) -> void:
	for name in HELPERS:
		if rest_poses.has(name):
			rest_basis[name] = (rest_poses[name] as Transform3D).basis.orthonormalized()
	for entry in BONES:
		var name: String = entry[0]
		if not rest_poses.has(name):
			continue
		var t: Transform3D = rest_poses[name]
		rest_basis[name] = t.basis.orthonormalized()
		var to_key: String = entry[3]
		var dir: Vector3 = (rest_joints[to_key] - t.origin) if rest_joints.has(to_key) else t.basis.y
		rest_dir[name] = dir.normalized()


## 관절 키 -> 그 관절에서 시작하는 뼈(휴지 위치 조회용)
const JOINT_BONE := {"pelvis": "pelvis", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head",
	"shoulder_L": "upperarm_L", "elbow_L": "forearm_L", "wrist_L": "hand_L",
	"shoulder_R": "upperarm_R", "elbow_R": "forearm_R", "wrist_R": "hand_R",
	"hip_L": "thigh_L", "knee_L": "shin_L", "ankle_L": "foot_L",
	"hip_R": "thigh_R", "knee_R": "shin_R", "ankle_R": "foot_R"}


## 스켈레톤 휴지 자세로 setup. 휴지 관절 위치는 관절 키로 명시한다(자식 뼈 열거 순서에 의존하지 않음, docs/04 §8.2).
func setup_from_skeleton(skeleton: Skeleton3D) -> void:
	var rest_poses := {}
	var rest_joints := {}
	for name in bone_names():
		var idx := skeleton.find_bone(name)
		if idx >= 0:
			rest_poses[name] = skeleton.get_bone_global_rest(idx)
	for key in JOINT_BONE:
		if rest_poses.has(JOINT_BONE[key]):
			rest_joints[key] = (rest_poses[JOINT_BONE[key]] as Transform3D).origin
	rest_joints["head_top"] = rest_joints["head"] + Vector3(0, 0.14, 0)
	for s in ["L", "R"]:
		rest_joints["hand_" + s] = rest_joints["wrist_" + s] + (rest_joints["wrist_" + s] - rest_joints["elbow_" + s]).normalized() * Anatomy.HAND_LENGTH
		rest_joints["toe_" + s] = rest_joints["ankle_" + s] + Vector3(0, -0.05, -0.15)
	setup(rest_poses, rest_joints)


## 게임이 자세를 주는 뼈 전부(BONES 순서, 그다음 보조 뼈). 부모가 자식보다 먼저 온다.
static func bone_names() -> Array:
	var names := RigPose.BONES.map(func(e): return e[0])
	names.append_array(HELPERS.keys())
	return names


## 단위 벡터 a를 b로 돌리는 최단 회전. 정반대이면 null 대신 항등을 반환하고 ok=false.
static func arc(a: Vector3, b: Vector3) -> Dictionary:
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if dot < ANTIPARALLEL_DOT:
		return {"q": Quaternion.IDENTITY, "ok": false}
	if dot > 0.999999:
		return {"q": Quaternion.IDENTITY, "ok": true}
	return {"q": Quaternion(a, b).normalized(), "ok": true}


## joints: 관절 키 -> 위치(같은 좌표계), roll_deg: 몸통 벽면 roll, yaw_deg: 골반 yaw(Y축, ψ>0 = 오른쪽이 벽 쪽).
## 합성 순서는 벽 기준 yaw → roll(04 §3)이라 몸통 기준 프레임은 roll × yaw이다.
## free_feet: "L"/"R" → 발이 떠 있는가(발바닥 방향용, 없으면 붙은 발).
## grip: "L"/"R" → 쥔 정도 0~1. 쥔 만큼 아래팔·손을 길이축으로 돌려 손바닥(휴지 T자에서 아래)이 벽(−Z)을 보게 한다(docs/36).
## 반환: 뼈 -> Transform3D(그 좌표계의 전역 프레임).
const PALM_REST := Vector3.DOWN


func solve(joints: Dictionary, roll_deg: float, yaw_deg: float = 0.0, free_feet := {}, grip := {}) -> Dictionary:
	var out := {}
	var roll := Basis(Vector3.BACK, deg_to_rad(roll_deg)) * Basis(Vector3.UP, deg_to_rad(yaw_deg))
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
				if name == "pelvis":
					basis = Basis(roll * Vector3.BACK, deg_to_rad(pelvis_tilt_deg(joints, roll))) * basis
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
		if name.begins_with("thigh_"):
			var side := name.right(1)
			var bend: Vector3 = joints["knee_" + side] - (from_p + joints["ankle_" + side]) * 0.5
			basis = _hinge_twist(basis, name, dir, HINGE_FACE["thigh_"], bend)
		elif name.begins_with("upperarm_") and joints.has("wrist_" + name.right(1)):
			var side := name.right(1)
			var bend: Vector3 = joints["elbow_" + side] - (from_p + joints["wrist_" + side]) * 0.5
			basis = _hinge_twist(basis, name, dir, HINGE_FACE["upperarm_"], bend)
		elif name.begins_with("foot_"):
			var side := name.right(1)
			var shin: Vector3 = (from_p - joints["knee_" + side]).normalized()
			var w := FOOT_UP_WEIGHT_FREE if free_feet.get(side, false) else FOOT_UP_WEIGHT_STUCK
			basis = _twist(basis, name, dir, Vector3.UP, roll * Vector3.UP * w - shin, 1.0)
		elif name.begins_with("forearm_"):
			basis = _palm_twist(basis, name, dir, float(grip.get(name.right(1), 0.0)))
		basis = basis.orthonormalized()
		_last[name] = basis
		out[name] = Transform3D(basis, from_p)
	for name in HELPERS:
		var pair: Array = HELPERS[name]
		if rest_basis.has(name) and out.has(pair[0]) and out.has(pair[1]):
			# 골반 회전 + (골반 기준 휴지 허벅지 방향 → 지금 허벅지 방향) 최단 회전의 HELPER_SHARE. 허벅지 길이축 비틀림은
			# 따르지 않는다(비틀림까지 절반 받으면 다리를 앞·옆·위로 크게 들 때 엉덩이 아랫부분이 아래로 돌아 처진다).
			var a := Quaternion((out[pair[0]].basis * rest_basis[pair[0]].inverse()).orthonormalized())
			var d0: Vector3 = (a * rest_dir[pair[1]]).normalized()
			var d1: Vector3 = (out[pair[1]].basis * rest_basis[pair[1]].inverse() * rest_dir[pair[1]]).normalized()
			var sw: Dictionary = arc(d0, d1)
			var half: Quaternion = Quaternion.IDENTITY.slerp(sw.q, HELPER_SHARE) if sw.ok else Quaternion.IDENTITY
			out[name] = Transform3D(Basis(half * a) * rest_basis[name], out[pair[1]].origin)
	return out


## 위팔·허벅지 비틀림(docs/59 §5 3·4단계): 팔꿈치·무릎이 모델이 접히는 방향으로 굽도록 뼈를 길이축으로 돌린다.
## 허벅지는 무릎 앞면(휴지 때 벽 쪽 FORWARD)이, 위팔은 팔꿈치 뒤(휴지 T자에서 BACK, 아래팔이 앞으로 접힘)가 굽힘 쪽
## (중간 관절 − 양 끝 가운데)을 본다. 2026-11-25 사용자: "머리 위 홀드를 못 잡고 팔이 떨어질 때 이상한 각도로 돌아간다,
## 무릎도". 위팔은 비틀기가 없어 팔꿈치가 모델과 170° 넘게 어긋나(뒤로 꺾임) 보였고, 허벅지는 기준축 최단 회전이 다리를
## 높이 든 자세에서 한 프레임 25° 넘게 돌아 8°씩만 따라가던 비틀기가 늦었다.
## - 직전 프레임 면을 지금 방향으로 평행 이동한 각(base)에서 시작한다(기준축 최단 회전의 빠른 돎을 따라가지 않음).
## - 굽었으면 굽힘 쪽으로 한 프레임 TWIST_STEP_BENT_DEG까지, 거의 펴졌으면 비틀지 않은 각(0)으로 TWIST_STEP_STRAIGHT_DEG까지 간다.
##   굽힘 비중 w(TWIST_BEND_MIN~FULL)로 한도를 섞는다. 그래서 뼈가 길이축으로 한 프레임에 이보다 빨리 돌지 않는다.
const TWIST_STEP_BENT_DEG := 8.0
const TWIST_STEP_STRAIGHT_DEG := 2.0
const HINGE_FACE := {"upperarm_": Vector3.BACK, "thigh_": Vector3.FORWARD}
var _twist_state := {}   # 뼈 → {dir, face}(직전 프레임 길이축과 비튼 뒤 면 방향)


func _hinge_twist(basis: Basis, name: String, dir: Vector3, rest_face: Vector3, bend: Vector3) -> Basis:
	var face0: Vector3 = basis * rest_basis[name].inverse() * rest_face
	face0 -= dir * face0.dot(dir)
	if face0.length() < 0.01:
		return basis
	face0 = face0.normalized()
	var want := bend - dir * bend.dot(dir)
	var w := smoothstep(TWIST_BEND_MIN, TWIST_BEND_FULL, want.length())
	var goal := face0.signed_angle_to(want.normalized(), dir) if want.length() >= 0.001 else 0.0
	var base := goal * w
	if _twist_state.has(name):
		var st: Dictionary = _twist_state[name]
		var pd: Vector3 = st.dir
		var carried: Vector3 = (Quaternion(pd, dir) if pd.dot(dir) > ANTIPARALLEL_DOT and pd.dot(dir) < 0.999999 else Quaternion.IDENTITY) * (st.face as Vector3)
		carried -= dir * carried.dot(dir)
		if carried.length() > 0.01:
			base = face0.signed_angle_to(carried.normalized(), dir)
	var target := goal if w > 0.0 else 0.0
	var step := deg_to_rad(lerpf(TWIST_STEP_STRAIGHT_DEG, TWIST_STEP_BENT_DEG, w))
	var ang := base + clampf(angle_difference(base, target), -step, step)
	_twist_state[name] = {"dir": dir, "face": face0.rotated(dir, ang)}
	return Basis(dir, ang) * basis


## 손바닥 돌리기(쥔 손, docs/36): 아래팔을 길이축으로 돌려 손바닥이 벽(−Z)을 보게 한다(손은 아래팔을 따른다).
## 위팔 기준 아래팔 비틀림은 PALM_TWIST_MAX(엎침·뒤침 한계 안), 한 프레임 TWIST_STEP_BENT_DEG까지(놓을 때 휙 풀리지 않게).
const PALM_TWIST_MAX := 85.0
var _palm_deg := {}   # 아래팔 → 직전에 돌린 각(도)


func _palm_twist(basis: Basis, name: String, dir: Vector3, amount: float) -> Basis:
	var now: Vector3 = basis * rest_basis[name].inverse() * PALM_REST
	now -= dir * now.dot(dir)
	var want := Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
	var goal := 0.0
	if now.length() >= 0.01 and want.length() >= 0.001:
		goal = clampf(rad_to_deg(now.normalized().signed_angle_to(want.normalized(), dir)) * clampf(amount, 0.0, 1.0), -PALM_TWIST_MAX, PALM_TWIST_MAX)
	var prev: float = _palm_deg.get(name, goal)
	var ang := prev + clampf(goal - prev, -TWIST_STEP_BENT_DEG, TWIST_STEP_BENT_DEG)
	_palm_deg[name] = ang
	return basis if absf(ang) < 0.001 else Basis(dir, deg_to_rad(ang)) * basis


## 뼈를 길이축(dir) 둘레로 돌려, 휴지 때 rest_ref(휴지 좌표)를 보던 면이 want 쪽을 보게 한다. amount 0~1.
func _twist(basis: Basis, name: String, dir: Vector3, rest_ref: Vector3, want: Vector3, amount: float) -> Basis:
	var now: Vector3 = basis * rest_basis[name].inverse() * rest_ref
	now -= dir * now.dot(dir)
	want -= dir * want.dot(dir)
	if amount <= 0.0 or now.length() < 0.01 or want.length() < 0.001:
		return basis
	return Basis(dir, now.normalized().signed_angle_to(want.normalized(), dir) * amount) * basis


## 골반 기울기(도, 몸 기준 뒤쪽 축 둘레: +면 오른쪽이 올라감). 벌어진 각 = 허벅지가 아래에서 벗어난 각 × 바깥쪽 비중.
static func pelvis_tilt_deg(joints: Dictionary, frame: Basis) -> float:
	var tilt := 0.0
	for side in ["L", "R"]:
		if not (joints.has("hip_" + side) and joints.has("knee_" + side)):
			continue
		var sgn := -1.0 if side == "L" else 1.0
		var p: Vector3 = frame.inverse() * (joints["knee_" + side] - joints["hip_" + side]).normalized()
		var flat := Vector2(p.x, p.z).length()
		if flat < 0.001:
			continue
		var abd := rad_to_deg(acos(clampf(-p.y, -1.0, 1.0))) * maxf(p.x * sgn, 0.0) / flat
		tilt += sgn * PELVIS_TILT_MAX * smoothstep(PELVIS_TILT_FROM, PELVIS_TILT_FULL, abd)
	return tilt
