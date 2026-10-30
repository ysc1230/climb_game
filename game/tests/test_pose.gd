extends RefCounted
## docs/04·19의 수치 계약과 자세 계산 성질.

var runner


func _near(a: float, b: float, eps: float = 0.0005) -> bool:
	return absf(a - b) <= eps


func test_reach_ranges_follow_joint_limits() -> void:
	var leg := Tuning.leg_range()
	var arm := Tuning.arm_range()
	runner.check(_near(leg.x, 0.303), "다리 최소 %.4f, 04는 약 0.303" % leg.x)
	runner.check(_near(arm.y, 0.779), "팔 최대 %.4f" % arm.y)
	runner.check(_near(arm.x, 0.20), "팔 최소는 명목값 0.20")


func test_doc19_start_pose_arithmetic() -> void:
	var p := Vector2(0, 0.83)
	runner.check(_near(PoseSolver.limb_distance(p, 0, PoseSolver.LH, Vector2(-0.45, 1.80)), 0.488774, 0.000001), "어깨→손 0.488774")
	runner.check(_near(PoseSolver.limb_distance(p, 0, PoseSolver.LF, Vector2(-0.30, 0.10)), 0.747329, 0.000001), "고관절→발 0.747329")
	runner.check(PoseSolver.is_foot_supporting(p, 0, PoseSolver.LF, Vector2(-0.30, 0.10)), "시작 발은 지지 발")


func test_dt16_leg_shorter_than_knee_limit_rejected() -> void:
	# 고관절 (-0.14,0)에서 0.28m 아래 발: 명목 최소 0.25는 넘지만 무릎 145° 제한으로 거부
	var attached := {PoseSolver.LF: Vector2(-0.14, -0.28)}
	runner.check(not PoseSolver.is_valid(Vector2.ZERO, 0, attached), "0.28m 다리는 무효여야 함")


func test_foot_above_hip_is_not_support() -> void:
	runner.check(not PoseSolver.is_foot_supporting(Vector2(0, 1.0), 0, PoseSolver.LF, Vector2(-0.3, 1.2)), "골반보다 높은 발은 지지 아님")


func test_fixed_contacts_converge_without_drift() -> void:
	# PH02 성격: 접점 고정 30초 동안 몸통이 수렴하고 계속 상승하지 않는다.
	var attached := {PoseSolver.LH: Vector2(-0.45, 1.80), PoseSolver.RH: Vector2(0.45, 1.80), PoseSolver.LF: Vector2(-0.30, 0.10), PoseSolver.RF: Vector2(0.30, 0.10)}
	var body := BodyState.new(Vector2(0, 0.95))
	var feet := PoseSolver.supporting_feet(body.pos, body.angle, attached)
	var y_at_5s := 0.0
	for i in 30 * Tuning.TICK_HZ:
		PoseSolver.step_body(body, attached, feet)
		feet = PoseSolver.supporting_feet(body.pos, body.angle, attached, feet)
		runner.check(PoseSolver.is_valid(body.pos, body.angle, attached), "틱 %d 제약 위반" % i)
		if i == 5 * Tuning.TICK_HZ:
			y_at_5s = body.pos.y
	runner.check(absf(body.pos.y - y_at_5s) < 0.001, "5초 이후 상하 이동 %.4f" % (body.pos.y - y_at_5s))
	runner.check(body.vel.length() < 0.001, "30초 뒤 속도 %.4f" % body.vel.length())


func test_body_speed_limit() -> void:
	var attached := {PoseSolver.LH: Vector2(-0.45, 1.80), PoseSolver.RH: Vector2(0.45, 1.80), PoseSolver.LF: Vector2(-0.30, 0.10), PoseSolver.RF: Vector2(0.30, 0.10)}
	var body := BodyState.new(Vector2(0, 1.05))
	for i in 60:
		PoseSolver.step_body(body, attached, [PoseSolver.LF, PoseSolver.RF])
		runner.check(body.vel.length() <= Tuning.ROOT_SPEED_LIMIT + 0.0001, "속도 상한 초과")


func test_fatigue_table() -> void:
	runner.check(Fatigue.attached_hand_rate(false, 0, 1, 0) == -30.0, "발0 손1 = -30")
	runner.check(Fatigue.attached_hand_rate(false, 2, 2, 0.05) == 10.0, "발2 정지 = +10")
	runner.check(Fatigue.attached_hand_rate(false, 2, 2, 0.5) == -2.0, "발2 이동 = -2")
	runner.check(Fatigue.apply(50, -30, 1.0, true) == 50.0, "피로 끄기는 감소만 0")
