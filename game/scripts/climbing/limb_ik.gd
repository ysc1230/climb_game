class_name LimbIK
extends RefCounted
## 3D 두 뼈 IK(docs/04 §8). 판정 계층이 관절 위치를 만들고 표현 계층은 읽기만 한다.
## 굽힘 면(pole)은 팔다리마다 고정된 바깥·벽 밖 방향을 쓰고, 투영이 작아지면 직전 굽힘 축을
## 다시 투영해 이어 쓴다(같은 반구 유지). 완전히 펴짐/접힘을 지나 관절이 반대로 뒤집히지 않는다.

const PRESENTATION_JOINT_SPEED_DEG := 180.0  # docs/04 §3
## 화면 다리 회전 중심(docs/37 §7, 2026-11-12 사용자 참고 그림): Tripo 모델은 엉덩이 관절이 판정 고관절보다
## HIP_RAISE 위(뒷주머니 가운데)에 있다. 화면 다리는 판정 고관절에서 몸 위쪽으로 HIP_RAISE 올린 점에서 시작하고
## 허벅지를 그만큼 길게 그린다. 발끝(판정 접점)은 그대로라 홀드 위치는 같다. 판정 고관절이 닿는 범위(허벅지+정강이)
## 안의 발은 올린 점에서도 항상 닿는다(삼각부등식).
## 캐릭터마다 다르다(2026-11-12 여성 추가): 화면이 모델을 불러올 때 뼈대에서 읽어 set_leg_shape로 바꾼다.
## 허벅지+정강이 = 판정 다리(LEG_UPPER+LEG_LOWER) + hip_raise. 기본값은 남성 모델.
const HIP_RAISE := 0.10
const LEG_UPPER_SHOWN := Tuning.LEG_UPPER + HIP_RAISE
static var hip_raise := HIP_RAISE
static var leg_upper_shown := LEG_UPPER_SHOWN
static var leg_lower_shown := Tuning.LEG_LOWER


static func set_leg_shape(raise: float, upper: float, lower: float) -> void:
	hip_raise = raise
	leg_upper_shown = upper
	leg_lower_shown = lower


static func reset_leg_shape() -> void:
	set_leg_shape(HIP_RAISE, LEG_UPPER_SHOWN, Tuning.LEG_LOWER)
const ELBOW_FRONT_MARGIN := 0.03  # 팔꿈치는 어깨 평면보다 이만큼 벽 쪽(몸통 앞)에 둔다


## 팔다리별 기본 pole. 손: 바깥·아래·벽 밖, 발: 바깥·약간 위·벽 밖.
static func default_pole(limb: StringName) -> Vector3:
	var s := PoseSolver.side_sign(limb)
	if PoseSolver.is_hand(limb):
		return Vector3(s * 0.6, -0.5, 0.8).normalized()
	return Vector3(s * 0.9, 0.2, 0.8).normalized()


## 해부학 IK(docs/04 §8.4): 몸 기준 선호 방향(BODY_POLE)을 따르되, 굽힘 축이 놓일 수 있는 원을 BEND_SAMPLES개로 나눠
## 해부학 제약(Anatomy: 어깨·고관절 비틀림, 벽·몸통 관통, 뒤로 젖힘, 팔꿈치는 어깨 평면 앞)을 어기는 정도가 가장 작은 쪽을 고른다.
## 직전 축에서 목표까지는 위반이 적은 길로 연속해서만 돈다(관절이 반대로 건너뛰지 않음, MID_SPEED 참고).
const BEND_SAMPLES := 36
const SEARCH_SAMPLES := 12    # 깊이를 고를 때(가능한 자세가 있는가)만 보는 거친 후보 수
const MID_SPEED := 4.0        # m/s, 팔꿈치·무릎이 굽힘 방향을 바꾸며 움직이는 최대 속도(관절 뒤집힘 방지)
const MAX_TICK_DEG := 20.0   # 한 틱에 굽힘 방향이 도는 최대 각(뒤집혀 보이지 않게)
const TARGET_MARGIN_DEG := 2.0  # 목표 굽힘 방향을 가능한 구간 경계에서 이만큼 안쪽에 둔다
const SWITCH_H := 0.12        # 굽힘 반지름이 이보다 작으면(거의 펴짐) 반대쪽으로 바꿔도 보이지 않는다
const ARM_POLE_HIGH := Vector3(0.45, -0.85, -0.25)  # 손이 어깨 위: 팔꿈치 아래·약간 바깥·벽 쪽
const ARM_POLE_LOW := Vector3(0.55, -0.15, 0.80)    # 손이 어깨 아래·옆: 팔꿈치 뒤·바깥
const BODY_POLE := {  # 몸 기준(X 오른쪽, Y 위, +Z 등 쪽). s는 오른쪽 +1·왼쪽 −1로 곱한다.
	&"hand": Vector3(0.6, -0.55, 0.45),   # 팔꿈치: 바깥·아래·약간 뒤(벽 반대)
	&"foot": Vector3(0.8, 0.1, -0.6),     # 무릎: 바깥·벽 쪽(앞). 무릎은 뒤로 접히지 않는다
	&"free_foot": Vector3(0.6, 0.6, -0.5), # 발을 들어 옮길 때 무릎: 바깥·위·벽 쪽(들어 올림)
}
const LEG_POLE_HIGH := Vector3(0.7, 0.6, -0.3)  # 발이 엉덩이 높이 근처(하이스텝): 무릎 바깥·위
const LEG_POLE_HIGH_FROM := -0.40  # 발 높이(엉덩이 기준, m)가 이보다 높으면 바깥·위로 섞기 시작
const LEG_POLE_HIGH_FULL := -0.10  # 이 높이부터는 바깥·위만
const WALL_MIN_Z := 0.05      # 팔꿈치·무릎 중심의 최소 Z(벽면 z=0 + 관절 반지름)
const TORSO_MIN_DIST := 0.18  # 몸통 축(골반+0.05 ~ +0.50)에서 팔꿈치·무릎 중심까지 최소 거리
const HEAD_MIN_DIST := 0.17   # 팔 뼈(위팔·아래팔)에서 머리 중심까지 최소 거리
const POLE_WEIGHT := 0.02     # 선호 방향과의 각(라디안)당 비용. 제약 위반(미터·도 환산)보다 훨씬 작다


## free: 끌거나 떠 있는 발(FREE_LEG 규칙 적용).
static func solve_limb(limb: StringName, root: Vector3, end: Vector3, frame: Basis, pelvis: Vector3, up: Vector3, prev_bend: Vector3, max_step_deg: float, free := false) -> Dictionary:
	return solve_circle(_circle(limb, root, end, frame, pelvis, up, BEND_SAMPLES, free), prev_bend, max_step_deg)


## 미리 구한 굽힘 원(circle)으로 굽힘 축을 고른다(ClimberPose가 같은 프레임의 원을 다시 쓸 때).
static func solve_circle(c: Dictionary, prev_bend: Vector3, max_step_deg: float) -> Dictionary:
	var bad: Array[float] = c.bad
	var target: float = c.target
	var th_new := target
	var dir: Vector3 = c.dir
	var n: Vector3 = c.n
	var t: Vector3 = c.t
	var carried := prev_bend - dir * prev_bend.dot(dir)
	if carried.length() > 0.0001 and float(c.h) > 0.0001:
		var th_prev := atan2(carried.dot(t), carried.dot(n))
		# 관절은 연속으로만 움직인다(한 틱에 반대쪽으로 건너뛰지 않음). 한 틱 회전 한도는 각속도 한도와
		# 중간 관절 이동 속도 한도(MID_SPEED / 굽힘 반지름) 중 큰 쪽: 많이 굽었으면 천천히, 거의 펴졌으면 빨리 방향을 바꾼다.
		var dt := max_step_deg / PRESENTATION_JOINT_SPEED_DEG
		var step := minf(maxf(deg_to_rad(max_step_deg), MID_SPEED * dt / maxf(float(c.h), 0.001)), deg_to_rad(MAX_TICK_DEG))
		var at: Callable = c.at
		if at.call(th_prev) <= 0.0:
			# 지금 축이 가능: 목표 쪽(짧은 길, 거친 후보로 막혔고 반대 길이 열렸으면 반대 길)으로 이번 틱 이동분만
			# 1°씩 정확히 확인하며 가고, 불가능해지기 직전에서 멈춘다(경계에서 오락가락하지 않음).
			var ccw := fposmod(target - th_prev, TAU)
			var dirn := 1.0 if ccw <= TAU - ccw else -1.0
			var dist := minf(ccw, TAU - ccw)
			if _path_viol(bad, th_prev, dirn * dist) > 0.0 and _path_viol(bad, th_prev, -dirn * (TAU - dist)) <= 0.0:
				dirn = -dirn
				dist = TAU - dist
			var move := minf(dist, step)
			var done := 0.0
			while done < move - 0.00001:
				var d := minf(deg_to_rad(1.0), move - done)
				if at.call(th_prev + dirn * (done + d)) > 0.0:
					break
				done += d
			th_new = th_prev + dirn * done
		else:
			# 지금 축이 불가능: 이번 틱 이동분 안에서 1°씩 양쪽으로 정확히 보고 가장 가까운 가능한 곳으로.
			# 없으면 거친 후보로 정한 탈출 방향으로 이동분만큼(경계에서 표본 간격만큼 오락가락하지 않음).
			var found := NAN
			var a := 0.0
			while a < step - 0.00001 and is_nan(found):
				a = minf(a + deg_to_rad(1.0), step)
				if at.call(th_prev + a) <= 0.0:
					found = th_prev + a
				elif at.call(th_prev - a) <= 0.0:
					found = th_prev - a
			th_new = found if not is_nan(found) else th_prev + clampf(float(_escape(bad, th_prev).span), -step, step)
	var bend := (n * cos(th_new) + t * sin(th_new)).normalized()
	return {"mid": (c.center as Vector3) + bend * float(c.h), "bend": bend}


## 직전 축에서 움직일 각(부호 = 방향). 연속성 우선:
## - 지금 축이 가능하면 가능한 구간 안에서만 선호 목표(best) 쪽으로 간다(길이 막히면 머문다).
## - 지금 축이 불가능하면 가장 가까운 가능한 후보로 간다(없으면 위반이 가장 작은 가장 가까운 후보).
static func _local_span(bad: Array[float], th_prev: float, target: float, h: float) -> float:
	if _viol_at(bad, th_prev) <= 0.0:
		var ccw := fposmod(target - th_prev, TAU)
		var cw := TAU - ccw
		var ok_ccw := _path_viol(bad, th_prev, ccw) <= 0.0
		var ok_cw := _path_viol(bad, th_prev, -cw) <= 0.0
		if ok_ccw and (not ok_cw or ccw <= cw):
			return ccw
		if ok_cw:
			return -cw
		return 0.0
	return _escape(bad, th_prev).span


## 지금 축이 불가능할 때 갈 곳: 가능한 후보 중 가는 길의 최대 위반이 가장 작고(벽·뒤로 꺾임을 덜 지나는 길),
## 같으면 가까운 곳. 가능한 후보가 없으면 위반이 가장 작은 후보. 반환 {span(부호 = 방향), cost(길의 최대 위반)}.
static func _escape(bad: Array[float], th_prev: float) -> Dictionary:
	var unit := TAU / bad.size()
	var lo: float = bad.min()
	var best := {"span": 0.0, "cost": INF}
	var best_d := INF
	for k in bad.size():
		if bad[k] > lo + 0.0001:
			continue
		for dirn in [1.0, -1.0]:
			var span: float = fposmod((unit * k - th_prev) * dirn, TAU) * dirn
			var cost := _path_viol(bad, th_prev, span)
			if cost < float(best.cost) - 0.0001 or (absf(cost - float(best.cost)) <= 0.0001 and absf(span) < best_d):
				best = {"span": span, "cost": cost}
				best_d = absf(span)
	return best


## 깊이를 고를 때의 팔다리 점수: 지금 축이 가능하면 0, 아니면 가능한 곳까지 가는 길의 최대 위반(연속으로 옮겨 갈 수 있는가).
## 직전 축이 없거나 거의 펴졌으면 전체 최소 위반.
static func local_violation(c: Dictionary, prev_bend: Vector3) -> float:
	var bad: Array[float] = c.bad
	var dir: Vector3 = c.dir
	var carried := prev_bend - dir * prev_bend.dot(dir)
	if carried.length() < 0.0001 or float(c.h) < SWITCH_H:
		return bad.min()
	var th_prev := atan2(carried.dot(c.t), carried.dot(c.n))
	if (c.at as Callable).call(th_prev) <= 0.0:
		return 0.0
	return 0.2 * float(_escape(bad, th_prev).cost) + 10.0 * bad.min()  # 가능한 자세가 있는 깊이를 먼저, 그다음 옮겨 가는 길


## 이 말단 위치에서 고를 수 있는 가장 작은 위반량(0이면 해부학적으로 가능한 굽힘이 있다). 점검 도구용.
static func min_violation(limb: StringName, root: Vector3, end: Vector3, frame: Basis, pelvis: Vector3, up: Vector3, free := false) -> float:
	return circle_min(circle(limb, root, end, frame, pelvis, up, BEND_SAMPLES, free))


static func circle_min(c: Dictionary) -> float:
	return (c.bad as Array[float]).min()


## samples: 후보 수(깊이를 고를 때는 SEARCH_SAMPLES로 거칠게, 표시할 때는 BEND_SAMPLES).
static func circle(limb: StringName, root: Vector3, end: Vector3, frame: Basis, pelvis: Vector3, up: Vector3, samples := BEND_SAMPLES, free := false) -> Dictionary:
	return _circle(limb, root, end, frame, pelvis, up, samples, free)


## 팔꿈치 선호 방향(몸 기준, 오른팔 기준 X+ = 바깥). 손 방향(어깨→손, 몸 기준)에 따라 바꾼다(2026-11-08 사용자:
## "팔 움직임이 부자연스럽고 기괴하게 꺾인다"). 손이 어깨 위면 팔꿈치는 아래·약간 벽 쪽(머리 위 홀드에서 팔꿈치가
## 옆으로 벌어지는 '닭 날개'를 피함), 어깨 높이·아래면 뒤·바깥(옆·아래로 뻗을 때 팔꿈치가 아래로 꺾여 V·L자가 되지 않음).
static func arm_pole(hand_dir_body: Vector3) -> Vector3:
	var up := clampf(hand_dir_body.y, -1.0, 1.0)
	var high := ARM_POLE_HIGH
	var low := ARM_POLE_LOW
	return low.lerp(high, smoothstep(-0.3, 0.6, up)).normalized()


## 무릎 선호 방향(몸 기준, 오른다리 기준 X+ = 바깥). foot_body: 엉덩이→발(몸 기준, m). 발이 엉덩이 높이 근처면
## 붙은 발도 무릎을 바깥·위로 든다(docs/37: 벽 쪽 선호만 쓰면 무릎이 발보다 아래로 처졌다).
static func leg_pole(foot_body: Vector3, free: bool) -> Vector3:
	var low: Vector3 = BODY_POLE[&"free_foot" if free else &"foot"]
	return low.lerp(LEG_POLE_HIGH, smoothstep(LEG_POLE_HIGH_FROM, LEG_POLE_HIGH_FULL, foot_body.y)).normalized()


## 굽힘 원: 중심·반지름 h·기준 축 n, t와 BEND_SAMPLES개 후보의 위반량(bad), 가장 좋은 후보(best).
static func _circle(limb: StringName, root: Vector3, end: Vector3, frame: Basis, pelvis: Vector3, up: Vector3, samples := BEND_SAMPLES, free := false) -> Dictionary:
	var hand := PoseSolver.is_hand(limb)
	var a := Tuning.ARM_UPPER if hand else leg_upper_shown
	var b := Tuning.ARM_LOWER if hand else leg_lower_shown
	var sgn := PoseSolver.side_sign(limb)
	var v := end - root
	var length := v.length()
	var dir := v / length if length > 0.0001 else (frame * Vector3.DOWN)
	var d := clampf(length, absf(a - b) + 0.0005, a + b - 0.0005)
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var center := root + dir * x
	var n := frame * Vector3.BACK
	n = n - dir * n.dot(dir)
	if n.length() < 0.01:
		n = (frame * Vector3.UP) - dir * (frame * Vector3.UP).dot(dir)
	n = n.normalized()
	var t := dir.cross(n).normalized()
	var pl: Vector3 = arm_pole(frame.inverse() * dir) if hand else leg_pole(frame.inverse() * v, free)
	var free_leg := free and not hand
	var pole := frame * Vector3(pl.x * sgn, pl.y, pl.z)
	var pole_th := atan2(pole.dot(t), pole.dot(n))
	var torso_a := pelvis + up * 0.05
	var torso_b := pelvis + up * 0.50
	var head := pelvis + up * Anatomy.HEAD_CENTER_UP
	var bad: Array[float] = []
	var best := 0
	var best_cost := INF
	for k in samples:
		var th := TAU * k / samples
		var mid := center + (n * cos(th) + t * sin(th)) * h
		var viol := _violation(limb, hand, root, mid, end, frame, torso_a, torso_b, head, free_leg)
		bad.append(viol)
		var cost := viol + POLE_WEIGHT * absf(angle_difference(th, pole_th))
		if cost < best_cost:
			best = k
			best_cost = cost
	# 연속 목표각: 선호 방향이 가능하면 그 방향, 아니면 가장 좋은 후보에서 선호 방향 쪽으로 가능한 구간의 경계(이분법).
	# 후보 간격(10°)으로 목표가 계단처럼 뛰면 팔꿈치·무릎이 따라 뛰어 떨려 보인다(2026-11-08 사용자 보고).
	var at := func(th: float) -> float:
		return _violation(limb, hand, root, center + (n * cos(th) + t * sin(th)) * h, end, frame, torso_a, torso_b, head, free_leg)
	var target := TAU * best / samples
	if at.call(pole_th) <= 0.0:
		target = pole_th
	elif bad[best] <= 0.0:
		var span := angle_difference(target, pole_th)
		var lo := 0.0
		var hi := 1.0
		for i in 6:
			var mid_f := (lo + hi) * 0.5
			if at.call(target + span * mid_f) <= 0.0:
				lo = mid_f
			else:
				hi = mid_f
		# 경계에서 TARGET_MARGIN만큼 안쪽(손이 조금 움직여 경계가 옮겨 가도 바로 불가능해지지 않게)
		target += signf(span) * maxf(0.0, absf(span) * lo - deg_to_rad(TARGET_MARGIN_DEG))
	return {"dir": dir, "n": n, "t": t, "center": center, "h": h, "bad": bad, "best": best, "target": target, "at": at}


## 굽힘 후보 하나의 제약 위반량(0이면 해부학적으로 가능).
static func _violation(limb: StringName, hand: bool, root: Vector3, mid: Vector3, end: Vector3, frame: Basis, torso_a: Vector3, torso_b: Vector3, head: Vector3, free_leg := false) -> float:
	var viol := 0.0
	if free_leg:
		viol += _free_leg_violation(limb, root, mid, end, frame)
	if not hand:
		viol += maxf(0.0, Anatomy.knee_back(root, mid, end, frame) - (Anatomy.KNEE_BACK_MAX - 0.1)) * 3.0
	else:
		viol += maxf(0.0, Anatomy.elbow_up(root, mid, end, frame) - (Anatomy.ELBOW_UP_MAX - 0.1)) * 3.0
	if true:
		var tw := Anatomy.limb_twist(limb, root, mid, end, frame)  # 거의 펴졌으면 NAN(점검과 같은 기준)
		if not is_nan(tw):
			var r := Anatomy.ARM_TWIST if hand else Anatomy.LEG_TWIST
			var margin := 10.0
			viol += maxf(0.0, (r.x + margin) - tw) / 90.0 + maxf(0.0, tw - (r.y - margin)) / 90.0
	viol += maxf(0.0, WALL_MIN_Z - mid.z) * 10.0
	if hand:
		viol += maxf(0.0, mid.z - (root.z - ELBOW_FRONT_MARGIN)) * 10.0
		viol += maxf(0.0, HEAD_MIN_DIST - Anatomy.arm_head_distance(root, mid, end, head)) * 10.0
	var td := Anatomy._seg_dist(mid, torso_a, torso_b)
	viol += maxf(0.0, TORSO_MIN_DIST - td) * 10.0
	var back := (mid - root).normalized().dot(frame * Vector3.BACK)
	var lim := Anatomy.SHOULDER_EXTENSION_MAX if hand else Anatomy.HIP_EXTENSION_MAX
	viol += maxf(0.0, back - (lim - 0.1))
	if not hand:
		viol += Anatomy.hip_lift_excess((mid - root).normalized(), frame, 10.0) / 90.0
	return viol


## 발을 들어 옮기는 중(끌기·떠 있음)의 다리(2026-11-08 사용자): 무릎은 위·바깥으로 들리고 정강이는 무릎에서 발로 내려간다.
## 무릎이 발보다 아래로 처지는 드롭니 모양은 발이 붙은 채 몸을 움직일 때만 생긴다(고관절 회전은 일반 한계를 따른다).
static func _free_leg_violation(limb: StringName, root: Vector3, mid: Vector3, end: Vector3, frame: Basis) -> float:
	var v := 0.0
	var shin_up := (end - mid).normalized().dot(frame * Vector3.UP)
	v += maxf(0.0, shin_up - (Anatomy.FREE_LEG_SHIN_UP_MAX - 0.1))
	return v


static func _viol_at(bad: Array[float], th: float) -> float:
	var n := bad.size()
	return bad[int(round(fposmod(th, TAU) / TAU * n)) % n]


## th0에서 span(부호 = 방향)만큼 도는 길 위 최대 위반.
static func _path_viol(bad: Array[float], th0: float, span: float) -> float:
	var steps := maxi(1, int(ceil(absf(span) / (TAU / bad.size()))))
	var m := 0.0
	for i in steps + 1:
		m = maxf(m, _viol_at(bad, th0 + span * i / steps))
	return m


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
