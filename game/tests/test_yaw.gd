extends RefCounted
## 04 §10.1 골반 yaw: 관절 깊이·좌우 간격, 상한·속도 제한, 제약에서 멈춤, 리그 직교성.

var runner
const START := {&"LH": Vector2(-0.45, 1.80), &"RH": Vector2(0.45, 1.80), &"LF": Vector2(-0.30, 0.10), &"RF": Vector2(0.30, 0.10)}


## TA08: 오른쪽 엉덩이를 벽 쪽으로(ψ>0) 틀면 오른손 최대 벽면 도달이 늘고 왼손은 줄어든다.
func test_right_hip_in_extends_right_reach() -> void:
	var dz := PoseSolver.contact_dz_range()
	var far := {}
	for yaw in [0.0, 30.0]:
		for limb in [PoseSolver.RH, PoseSolver.LH]:
			var off := PoseSolver.joint_depth_offset(limb, yaw)
			far[[limb, yaw]] = PoseSolver.planar_range(limb, dz.x + off, dz.y + off).y
	runner.check(far[[PoseSolver.RH, 30.0]] > far[[PoseSolver.RH, 0.0]], "ψ=30 RH 도달 %.4f > %.4f" % [far[[PoseSolver.RH, 30.0]], far[[PoseSolver.RH, 0.0]]])
	runner.check(far[[PoseSolver.LH, 30.0]] < far[[PoseSolver.LH, 0.0]], "ψ=30 LH 도달 %.4f < %.4f" % [far[[PoseSolver.LH, 30.0]], far[[PoseSolver.LH, 0.0]]])
	# can_reach도 같은 방향: yaw 30°의 오른 어깨 바로 위, ψ=0 최대와 ψ=30 최대의 가운데 거리(몸 치수에서 계산, 2026-11-11)
	var mid_d: float = (far[[PoseSolver.RH, 0.0]] + far[[PoseSolver.RH, 30.0]]) * 0.5
	var pelvis := Vector2(0, 1.0)
	var rj := PoseSolver.joint_position(pelvis, 0.0, PoseSolver.RH, 30.0)
	var slot := rj + Vector2(0, mid_d)
	runner.check(PoseSolver.can_reach(pelvis, 0.0, PoseSolver.RH, slot, 30.0), "ψ=30에서 RH 닿음")
	runner.check(not PoseSolver.can_reach(pelvis, 0.0, PoseSolver.RH, slot, 0.0), "ψ=0에서는 RH 닿지 않음")
	var lj := PoseSolver.joint_position(pelvis, 0.0, PoseSolver.LH, 30.0)
	runner.check(not PoseSolver.can_reach(pelvis, 0.0, PoseSolver.LH, lj + Vector2(0, mid_d), 30.0), "ψ=30에서 LH는 같은 거리에 닿지 않음")


func test_joint_spacing_and_depth_signs() -> void:
	runner.check(absf(PoseSolver.joint_offset(PoseSolver.RH, 30.0).x - Tuning.SHOULDER_OFFSET.x * cos(deg_to_rad(30.0))) < 1e-6, "어깨 X × cos ψ")
	runner.check(absf(PoseSolver.joint_offset(PoseSolver.LF, 0.0).x + Tuning.HIP_OFFSET.x) < 1e-6, "yaw 0이면 기존 오프셋")
	runner.check(PoseSolver.joint_depth_offset(PoseSolver.RH, 30.0) < 0.0 and PoseSolver.joint_depth_offset(PoseSolver.LH, 30.0) > 0.0, "ψ>0 오른쪽 어깨가 벽 쪽")
	runner.check(absf(PoseSolver.joint_depth_offset(PoseSolver.LF, 30.0) - Tuning.HIP_YAW_DEPTH * 0.5) < 1e-6, "왼 고관절 +깊이 계수·sin30")


func test_yaw_clamped_and_rate_limited() -> void:
	var rules := ClimbRules.new()
	var body := BodyState.new(Vector2(0, 0.83))
	rules.reset(body, START, {}, false)
	rules.yaw_target = 80.0
	var worst := 0.0
	for i in 60:
		var before := body.yaw
		var out := rules.tick(body, START, {}, false, false)
		runner.check(out.is_empty(), "틱 %d 실패 없음: %s" % [i, out])
		worst = maxf(worst, absf(body.yaw - before))
	runner.check(worst <= 1.5 + 0.0001, "1틱 변화 최대 %.4f° ≤ 1.5°" % worst)
	runner.check(absf(body.yaw - 40.0) < 0.0001, "60틱 뒤 yaw == 40, 실제 %.4f" % body.yaw)
	# NAN 목표는 0으로 복귀
	rules.yaw_target = NAN
	for i in 90:
		rules.tick(body, START, {}, false, false)
	runner.check(absf(body.yaw) < 0.0001, "목표 NAN이면 0 복귀, 실제 %.4f" % body.yaw)


func test_yaw_stops_at_constraint() -> void:
	# LH가 어깨 바로 위 도달 끝(ψ=0 최대 − 0.01)에 있다. 왼쪽 어깨가 벽에서 멀어지는 ψ>0에서 도달 한계를 넘으면 멈춘다.
	var body := BodyState.new(Vector2(0, 1.0))
	var dz := PoseSolver.contact_dz_range()
	var off := PoseSolver.joint_depth_offset(PoseSolver.LH, 0.0)
	var reach0 := PoseSolver.planar_range(PoseSolver.LH, dz.x + off, dz.y + off).y
	var attached := {PoseSolver.LH: PoseSolver.joint_position(body.pos, 0.0, PoseSolver.LH) + Vector2(0, reach0 - 0.01)}
	runner.check(PoseSolver.is_valid(body.pos, 0.0, attached, 0.0), "ψ=0 시작은 유효")
	runner.check(not PoseSolver.is_valid(body.pos, 0.0, attached, 30.0), "ψ=30은 무효(전제)")
	for i in 90:
		PoseSolver.step_yaw(body, 30.0, attached)
	runner.check(body.yaw > 0.0 and body.yaw < 30.0, "무효 직전에서 멈춤, 실제 %.3f" % body.yaw)
	runner.check(PoseSolver.is_valid(body.pos, 0.0, attached, body.yaw), "멈춘 yaw는 유효")
	runner.check(not PoseSolver.is_valid(body.pos, 0.0, attached, body.yaw + 1.5), "한 틱 더 가면 무효")
	runner.check(body.yaw_vel == 0.0, "yaw 속도 0")


## 같은 후보를 fused 탐색 비용과 is_valid가 yaw에서도 일치시킨다.
func test_search_cost_matches_is_valid_with_yaw() -> void:
	var attached := {PoseSolver.LH: Vector2(-0.2, 1.80), PoseSolver.RF: Vector2(0.3, 0.10)}
	for yaw in [-30.0, 0.0, 25.0]:
		for dy in [0.0, 0.1, 0.25]:
			var p := Vector2(0, 0.83 + dy)
			var valid := PoseSolver.is_valid(p, 0.0, attached, yaw)
			var c := PoseSolver.cost(p, 0.0, attached, [PoseSolver.RF], {}, {}, Vector3(NAN, NAN, NAN), NAN, 0.0, yaw)
			runner.check(valid == (c != INF), "yaw %.0f dy %.2f is_valid=%s cost=%s" % [yaw, dy, valid, c])


func test_rig_yaw_frames_orthonormal() -> void:
	var rig := RigPose.new()
	var j := _rest_joints()
	var rest := {}
	for entry in RigPose.BONES:
		rest[entry[0]] = Transform3D(Basis.IDENTITY, j[entry[2]])
	rig.setup(rest, j)
	var f := rig.solve(j, 0.0, 30.0)
	for name in f:
		var b: Basis = f[name].basis
		runner.check(absf(b.determinant() - 1.0) <= 0.01, "%s 행렬식 %.4f" % [name, b.determinant()])
	var f0 := rig.solve(j, 0.0, 0.0)
	var pelvis: Basis = f["pelvis"].basis
	runner.check(rad_to_deg(Quaternion(f0["pelvis"].basis).angle_to(Quaternion(pelvis))) > 29.0, "몸통 뼈가 yaw만큼 회전")


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
