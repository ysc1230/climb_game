class_name LimbIK
extends RefCounted
## 3D 두 뼈 IK(docs/04 §8). 판정 계층이 관절 위치를 만들고 표현 계층은 읽기만 한다.
## 굽힘 면(pole)은 팔다리마다 고정된 바깥·벽 밖 방향을 쓰고, 투영이 작아지면 직전 굽힘 축을
## 다시 투영해 이어 쓴다(같은 반구 유지). 완전히 펴짐/접힘을 지나 관절이 반대로 뒤집히지 않는다.

const PRESENTATION_JOINT_SPEED_DEG := 180.0  # docs/04 §3


## 팔다리별 기본 pole. 손: 바깥·아래·벽 밖, 발: 바깥·약간 위·벽 밖.
static func default_pole(limb: StringName) -> Vector3:
	var s := PoseSolver.side_sign(limb)
	if PoseSolver.is_hand(limb):
		return Vector3(s * 0.6, -0.5, 0.8).normalized()
	return Vector3(s * 0.9, 0.2, 0.8).normalized()


## 반환: {mid: Vector3, bend: Vector3(단위, 다음 틱의 연속성용)}
## max_step_deg: 한 번 호출에서 굽힘 축이 돌 수 있는 최대 각(docs/04 presentation_joint_speed × dt).
## 직전 축(prev_bend)을 현재 팔다리 축에 다시 투영해 이어 쓰고, pole 쪽으로는 이 한도 안에서만 돌린다.
static func solve(root: Vector3, end: Vector3, a: float, b: float, pole: Vector3, prev_bend: Vector3 = Vector3.ZERO, max_step_deg: float = INF) -> Dictionary:
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
	return {"mid": root + dir * x + bend * h, "bend": bend}
