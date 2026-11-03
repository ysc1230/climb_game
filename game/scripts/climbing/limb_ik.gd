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
## max_mid_z: 중간 관절(팔꿈치) Z 상한(몸통 뒤로 넘어가지 않게). 상한이 걸리면 굽힘 축은 허용 호(벽 쪽을 지나는 호)
## 안에서만 pole 쪽으로 돈다. 등 뒤 영역을 가로질러 돌다 걸려 반대쪽(몸 안쪽)에 갇히지 않는다.
static func solve(root: Vector3, end: Vector3, a: float, b: float, pole: Vector3, prev_bend: Vector3 = Vector3.ZERO, max_step_deg: float = INF, max_mid_z: float = INF) -> Dictionary:
	var v := end - root
	var length := v.length()
	var dir := v / length if length > 0.0001 else Vector3.DOWN
	var d := clampf(length, absf(a - b) + 0.0005, a + b - 0.0005)
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var desired := pole - dir * pole.dot(dir)
	var carried := prev_bend - dir * prev_bend.dot(dir)
	var center := root + dir * x
	if h > 0.0001 and max_mid_z < INF:
		var limited := _solve_limited(dir, center, h, desired, carried, max_step_deg, max_mid_z)
		if not limited.is_empty():
			return limited
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
	return {"mid": center + bend * h, "bend": bend}


## Z 상한이 있을 때의 굽힘 축. 축이 놓이는 원(dir에 수직)을 벽 쪽 축 n과 옆 축 t의 각 θ로 보면
## bend = n·cosθ + t·sinθ, 팔꿈치 Z = center.z − h·k·cosθ (k = −n.z)라서 허용 범위는 n을 가운데 둔 |θ| ≤ θmax 한 구간이다.
## 직전 축과 pole을 그 구간으로 자른 뒤 구간 안에서만(벽 쪽을 지나) 한 번에 max_step_deg까지 돈다.
## 상한이 걸리지 않는 자세(구간이 원 전체)면 {}를 돌려 일반 경로를 쓴다.
static func _solve_limited(dir: Vector3, center: Vector3, h: float, desired: Vector3, carried: Vector3, max_step_deg: float, max_mid_z: float) -> Dictionary:
	var n := Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)  # 원 위에서 가장 벽 쪽(−Z)
	if n.length() < 0.0001:
		return {}  # 팔다리 축이 Z와 평행: 어느 축이든 팔꿈치 Z가 같다
	n = n.normalized()
	var t := dir.cross(n).normalized()
	var k := -n.z
	var c_min := (center.z - max_mid_z) / (h * k)  # cosθ ≥ c_min이면 허용
	if c_min <= -1.0:
		return {}
	var theta_max := acos(minf(c_min, 1.0))  # c_min ≥ 1이면 0: 가장 벽 쪽 축 하나만 허용
	var theta_want := NAN
	if desired.length() >= 0.05:
		theta_want = clampf(atan2(desired.dot(t), desired.dot(n)), -theta_max, theta_max)
	var theta: float
	if carried.length() < 0.0001:
		theta = theta_want if not is_nan(theta_want) else 0.0
	else:
		theta = clampf(atan2(carried.dot(t), carried.dot(n)), -theta_max, theta_max)
		if not is_nan(theta_want):
			var step := deg_to_rad(max_step_deg)
			theta += clampf(theta_want - theta, -step, step)
	var bend := (n * cos(theta) + t * sin(theta)).normalized()
	return {"mid": center + bend * h, "bend": bend}
