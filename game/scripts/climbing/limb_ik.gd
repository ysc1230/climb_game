class_name LimbIK
extends RefCounted
## 3D 두 뼈 IK(docs/04 §8). 판정 계층이 관절 위치를 만들고 표현 계층은 읽기만 한다.
## 굽힘 면(pole)은 팔다리마다 고정된 바깥·벽 밖 방향을 쓰고, 투영이 작아지면 직전 굽힘 축을
## 다시 투영해 이어 쓴다(같은 반구 유지). 완전히 펴짐/접힘을 지나 관절이 반대로 뒤집히지 않는다.

const PRESENTATION_JOINT_SPEED_DEG := 180.0  # docs/04 §3
const ELBOW_FRONT_MARGIN := 0.03  # 팔꿈치는 어깨 평면보다 이만큼 벽 쪽(몸통 앞)에 둔다


## 팔다리별 기본 pole. 손: 바깥·아래·벽 밖, 발: 바깥·약간 위·벽 밖.
static func default_pole(limb: StringName) -> Vector3:
	var s := PoseSolver.side_sign(limb)
	if PoseSolver.is_hand(limb):
		return Vector3(s * 0.6, -0.5, 0.8).normalized()
	return Vector3(s * 0.9, 0.2, 0.8).normalized()


## 반환: {mid: Vector3, bend: Vector3(단위, 다음 틱의 연속성용)}
## max_step_deg: 한 번 호출에서 굽힘 축이 돌 수 있는 최대 각(docs/04 presentation_joint_speed × dt).
## 직전 축(prev_bend)을 현재 팔다리 축에 다시 투영해 이어 쓰고, pole 쪽으로는 이 한도 안에서만 돌린다.
## max_mid_z: 중간 관절(팔꿈치) Z 상한. 넘으면 굽힘 축을 벽 쪽(-Z)으로 최소한만 돌린다(몸통 뒤로 넘어가지 않게).
static func solve(root: Vector3, end: Vector3, a: float, b: float, pole: Vector3, prev_bend: Vector3 = Vector3.ZERO, max_step_deg: float = INF, max_mid_z: float = INF) -> Dictionary:
	var v := end - root
	var length := v.length()
	var dir := v / length if length > 0.0001 else Vector3.DOWN
	var d := clampf(length, absf(a - b) + 0.0005, a + b - 0.0005)
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var desired := pole - dir * pole.dot(dir)
	var carried := prev_bend - dir * prev_bend.dot(dir)
	var bend: Vector3
	if carried.length() < 0.0001:
		bend = desired if desired.length() > 0.0001 else Vector3.BACK - dir * dir.z
	elif desired.length() < 0.05:
		bend = carried  # pole이 팔다리 축과 거의 평행: 직전 축 유지
	else:
		carried = carried.normalized()
		var want := desired.normalized()
		var ang := carried.angle_to(want)
		var step := minf(ang, deg_to_rad(max_step_deg))
		var axis := carried.cross(want)
		axis = axis.normalized() if axis.length() > 0.0001 else dir
		bend = carried.rotated(axis, step) if step > 0.0 else carried
		bend = bend - dir * bend.dot(dir)
	bend = bend.normalized()
	var center := root + dir * x
	if h > 0.0001 and center.z + bend.z * h > max_mid_z:
		bend = _limit_bend_z(bend, dir, (max_mid_z - center.z) / h)
	return {"mid": center + bend * h, "bend": bend}


## dir에 수직인 단위 굽힘 축 bend를 bend.z ≤ max_bz가 되도록 그 평면 안에서 최소 회전한다.
## 불가능하면 가장 벽 쪽(-Z) 축을 쓴다.
static func _limit_bend_z(bend: Vector3, dir: Vector3, max_bz: float) -> Vector3:
	var n := Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)  # 평면 안에서 가장 -Z 쪽
	if n.length() < 0.0001:
		return bend  # 팔다리 축이 Z와 평행: 어느 축이든 z 같음
	n = n.normalized()
	var t := dir.cross(n).normalized()
	var k := -n.z  # > 0
	var alpha := clampf(-max_bz / k, -1.0, 1.0)
	var beta := bend.dot(t)
	var sgn := 1.0 if beta >= 0.0 else -1.0
	return (n * alpha + t * sgn * sqrt(maxf(1.0 - alpha * alpha, 0.0))).normalized()
