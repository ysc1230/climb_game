extends RefCounted
## docs/25 MC 시나리오 중 구현된 제약의 검사. 헤드리스 시뮬레이션이며 기기 검증이 아니다.

var runner
const PELVIS := Vector2(0, 1.0)


## MC01: 자유 손 목표를 원으로 10바퀴 요청해도 허용 방향 밖으로 돌지 않고 누적 회전이 없다.
func test_mc01_circular_drag_stays_in_direction_range() -> void:
	for limb in [PoseSolver.LH, PoseSolver.RH, PoseSolver.LF, PoseSolver.RF]:
		var joint := PoseSolver.joint_position(PELVIS, 0, limb)
		var rng := PoseSolver.dir_range(limb)
		var start := joint + (Vector2(0, 0.5) if PoseSolver.is_hand(limb) else Vector2(0, -0.6))
		var p := start
		var max_jump := 0.0
		for i in 10 * 72:  # 손가락이 반지름 0.3m 원을 10바퀴, 5°씩(게임처럼 이동량을 누적·초과분 버림)
			var a0 := deg_to_rad(i * 5.0)
			var a1 := deg_to_rad((i + 1) * 5.0)
			var delta := (Vector2(sin(a1), cos(a1)) - Vector2(sin(a0), cos(a0))) * 0.3
			var q := PoseSolver.clamp_endpoint(PELVIS, 0, limb, p, p + delta)
			max_jump = maxf(max_jump, q.distance_to(p))
			p = q
			var ang := PoseSolver.limb_angle(PELVIS, 0, limb, p)
			runner.check(ang >= rng.x - 0.01 and ang <= rng.y + 0.01, "%s 각도 %.1f 범위 밖" % [limb, ang])
		runner.check(max_jump < 0.03, "%s 한 스텝 최대 이동 %.3fm(금지 영역 가로지르기 점프)" % [limb, max_jump])


## MC02: 손을 관절 중심으로 끌어당겨도 최소 거리를 지키고 관절 원점을 통과하지 않는다.
func test_mc02_free_hand_keeps_min_distance() -> void:
	var limb := PoseSolver.LH
	var joint := PoseSolver.joint_position(PELVIS, 0, limb)
	var p := joint + Vector2(-0.3, 0.4)
	for i in 60:
		p = PoseSolver.clamp_endpoint(PELVIS, 0, limb, p, p.lerp(joint, 0.5))
	runner.check(p.distance_to(joint) >= 0.019, "관절 중심까지 %.3fm" % p.distance_to(joint))


## 금지 쐐기(손이 몸 안쪽 아래)로 곧장 요청하면 가까운 경계에서 멈춘다.
func test_forbidden_wedge_request_clamps_to_near_boundary() -> void:
	var limb := PoseSolver.LH
	var joint := PoseSolver.joint_position(PELVIS, 0, limb)
	var prev := joint + Vector2(0.1, -0.5)  # 안쪽·아래(경계 근처, 약 -169°는 금지 → 경계로 제한)
	var q := PoseSolver.clamp_endpoint(PELVIS, 0, limb, prev, joint + Vector2(0.4, -0.3))
	var ang := PoseSolver.limb_angle(PELVIS, 0, limb, q)
	runner.check(ang >= -100.01 and ang <= 170.01, "각도 %.1f" % ang)


## MC07 성격: 어깨보다 0.10m 넘게 낮은 손은 붙어 있어도 하중 자격이 없다.
func test_low_hand_not_load_eligible() -> void:
	var shoulder := PoseSolver.joint_position(PELVIS, 0, PoseSolver.LH)
	runner.check(PoseSolver.hand_load_eligible(PELVIS, 0, PoseSolver.LH, shoulder + Vector2(-0.3, 0.2)), "위 손은 자격 있음")
	runner.check(not PoseSolver.hand_load_eligible(PELVIS, 0, PoseSolver.LH, shoulder + Vector2(-0.3, -0.2)), "낮은 손은 자격 없음")


## MC05: 팔꿈치가 거의 펴지는 경계를 왕복해도 굽힘 방향(branch)이 뒤집히지 않는다.
func test_mc05_ik_branch_continuous_near_straight() -> void:
	var root := Vector3(-0.2, 1.55, 0.28)
	var pole := LimbIK.default_pole(PoseSolver.LH)
	var prev := Vector3.ZERO
	var first := Vector3.ZERO
	for i in 200:
		var t := 0.5 + 0.5 * sin(i * 0.1)
		var end := root + Vector3(-0.1, 1.0, -0.21).normalized() * lerpf(0.5, 0.778, t)
		var r := LimbIK.solve(root, end, 0.40, 0.38, pole, prev)
		if prev != Vector3.ZERO:
			runner.check(r.bend.dot(prev) > 0.9, "틱 %d 굽힘 축 급변 %.2f" % [i, r.bend.dot(prev)])
		else:
			first = r.bend
		var upper: float = (r.mid - root).length()
		var lower: float = (end - r.mid).length()
		runner.check(absf(upper - 0.40) < 0.001 and absf(lower - 0.38) < 0.002, "뼈 길이 변화")
		prev = r.bend
	runner.check(first.z > 0.0, "팔꿈치는 벽 바깥(+Z)으로")


## MC04·MC01(리그): 원 궤도를 10바퀴 돌고 제자리로 오면 뼈 프레임이 처음과 같다(누적 twist 없음),
## 프레임은 직교·양의 행렬식, 한 스텝 회전은 작다(180° 대체 점프 없음).
func test_rig_frames_no_accumulation_or_flip() -> void:
	var rig := RigPose.new()
	var rest := {}
	var joints0 := _rest_joints()
	for entry in RigPose.BONES:
		rest[entry[0]] = Transform3D(Basis.IDENTITY, joints0[entry[2]])
	rig.setup(rest, joints0)
	var first := {}
	var prev := {}
	var bend := Vector3.ZERO
	var laps_end := 10 * 72
	for i in laps_end + 121:  # 10바퀴 후 같은 목표를 2초(120틱) 유지
		var a := deg_to_rad(mini(i, laps_end) * 5.0)
		var j := joints0.duplicate()
		var sh: Vector3 = j.shoulder_L
		var hand_target := sh + Vector3(-0.35 * cos(a) - 0.1, 0.35 * sin(a) + 0.15, -0.21)
		var ik := LimbIK.solve(sh, hand_target, 0.40, 0.38, LimbIK.default_pole(PoseSolver.LH), bend, LimbIK.PRESENTATION_JOINT_SPEED_DEG / 60.0)
		bend = ik.bend
		j.elbow_L = ik.mid
		j.wrist_L = hand_target
		j.hand_L = hand_target + (hand_target - ik.mid).normalized() * 0.09
		var f := rig.solve(j, 0.0)
		for name in ["upperarm_L", "forearm_L", "hand_L"]:
			var b: Basis = f[name].basis
			runner.check(b.determinant() > 0.99 and b.determinant() < 1.01, "%s 행렬식" % name)
			if prev.has(name):
				var step := rad_to_deg(Quaternion(prev[name]).angle_to(Quaternion(b)))
				runner.check(step < 25.0, "%s 틱 %d 회전 %.1f°" % [name, i, step])
			prev[name] = b
		if i == 0:
			first = f
		elif i == laps_end + 120:
			# 지연(속도 제한)은 허용, 정지 후에도 남는 차이는 누적 회전으로 본다
			for name in ["upperarm_L", "forearm_L", "hand_L"]:
				var diff := rad_to_deg(Quaternion(first[name].basis).angle_to(Quaternion(f[name].basis)))
				runner.check(diff < 0.5, "%s 10바퀴 후 정지 2초 뒤 차이 %.2f°" % [name, diff])


func _rest_joints() -> Dictionary:
	var j := {"pelvis": Vector3(0, 1, 0.28), "spine": Vector3(0, 1.22, 0.28), "chest": Vector3(0, 1.44, 0.28),
		"neck": Vector3(0, 1.63, 0.28), "head": Vector3(0, 1.80, 0.28), "head_top": Vector3(0, 1.94, 0.28)}
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var d := Vector3(sx * cos(deg_to_rad(25)), -sin(deg_to_rad(25)), 0)
		j["shoulder_" + s] = Vector3(sx * 0.20, 1.55, 0.28)
		j["elbow_" + s] = j["shoulder_" + s] + d * 0.40
		j["wrist_" + s] = j["elbow_" + s] + d * 0.38
		j["hand_" + s] = j["wrist_" + s] + d * 0.09
		j["hip_" + s] = Vector3(sx * 0.14, 1.0, 0.28)
		j["knee_" + s] = j["hip_" + s] + Vector3(0, -0.52, 0)
		j["ankle_" + s] = j["knee_" + s] + Vector3(0, -0.48, 0)
		j["toe_" + s] = j["ankle_" + s] + Vector3(0, -0.05, -0.15)
	return j
