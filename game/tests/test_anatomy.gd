extends RefCounted
## 해부학 점검(docs/04 §8.4): 비틀림·굴곡 정의, 해부학 IK(LimbIK.solve_limb)·표현 자세(ClimberPose),
## 실제 세션 무작위 조작 스윕(AnatomySweep)에서 IK가 고를 수 있었는데 불가능한 자세를 보이지 않는지.

var runner

const F := Basis.IDENTITY  # 몸 기준 축 = 월드(기울기·yaw 0)


## 어깨: T자세에서 아래팔이 앞(벽 쪽, −Z)으로 굽으면 0°, 위로 굽으면 바깥돌림 +90°, 아래면 안돌림 −90°, 뒤면 ±180°.
func test_arm_twist_definition() -> void:
	var sh := Vector3(0.2, 1.5, 0.3)
	var el := sh + Vector3(0.4, 0, 0)
	runner.check(absf(Anatomy.limb_twist(&"RH", sh, el, el + Vector3(0, 0, -0.38), F)) < 1.0, "앞으로 굽음 0°")
	runner.check(absf(Anatomy.limb_twist(&"RH", sh, el, el + Vector3(0, 0.38, 0), F) - 90.0) < 1.0, "위로 굽음 +90°")
	runner.check(absf(Anatomy.limb_twist(&"RH", sh, el, el + Vector3(0, -0.38, 0), F) + 90.0) < 1.0, "아래로 굽음 −90°")
	runner.check(absf(absf(Anatomy.limb_twist(&"RH", sh, el, el + Vector3(0, 0, 0.38), F)) - 180.0) < 1.0, "뒤로 굽음 ±180°")
	var shl := Vector3(-0.2, 1.5, 0.3)
	var ell := shl + Vector3(-0.4, 0, 0)
	runner.check(absf(Anatomy.limb_twist(&"LH", shl, ell, ell + Vector3(0, 0.38, 0), F) - 90.0) < 1.0, "왼팔도 위로 굽음 +90°(좌우 대칭)")


## 고관절: 선 자세에서 정강이가 뒤로 굽으면 0°, 무릎이 뒤(카메라 쪽)로 접히면 ±180°(불가능).
## 무릎을 앞(벽 쪽)으로 들고 정강이가 아래로 내려오면(하이스텝) 0° 근처, 굴곡 90°.
func test_hip_twist_and_flexion_definition() -> void:
	var hip := Vector3(0.14, 1.0, 0.3)
	var down_knee := hip + Vector3(0, -0.52, 0)
	runner.check(absf(Anatomy.limb_twist(&"RF", hip, down_knee, down_knee + Vector3(0, 0, 0.48), F)) < 1.0, "선 자세 뒤로 굽음 0°")
	runner.check(not Anatomy.twist_ok(&"RF", Anatomy.limb_twist(&"RF", hip, down_knee, down_knee + Vector3(0, 0, -0.48), F)), "무릎이 뒤로 접힘은 불가능")
	var up_knee := hip + Vector3(0, 0, -0.52)
	runner.check(absf(Anatomy.limb_twist(&"RF", hip, up_knee, up_knee + Vector3(0, -0.48, 0), F)) < 1.0, "하이스텝(무릎 앞, 정강이 아래) 0°")
	runner.check(absf(Anatomy.hip_flexion_deg(Vector3(0, 0, -1), F) - 90.0) < 0.5, "허벅지가 앞이면 굴곡 90°")
	runner.check(Anatomy.hip_flexion_deg(Vector3(0, 0.98, 0.2).normalized(), F) < Anatomy.HIP_FLEXION.x, "허벅지가 위·뒤면 범위 밖")
	var frog_knee := hip + Vector3(0.45, 0, -0.26)
	var frog := Anatomy.limb_twist(&"RF", hip, frog_knee, frog_knee + Vector3(0, -0.48, 0), F)
	runner.check(Anatomy.twist_ok(&"RF", frog), "개구리 자세(무릎 바깥·앞, 정강이 아래) 가능: %.0f°" % frog)


## 해부학 IK: 발이 아래 벽에 있고 골반이 벽에서 떨어진 기본 자세에서 무릎은 벽 쪽(−Z)·바깥으로 굽는다(뒤로 접히지 않음).
func test_knee_bends_toward_wall() -> void:
	var pelvis := Vector3(0, 1.0, 0.28)
	for side in [-1.0, 1.0]:
		var limb := &"RF" if side > 0 else &"LF"
		var hip := Vector3(0.14 * side, 1.0, 0.28)
		var r := LimbIK.solve_limb(limb, hip, Vector3(0.3 * side, 0.25, Tuning.CONTACT_DEPTH), F, pelvis, Vector3.UP, Vector3.ZERO, INF)
		var knee: Vector3 = r.mid
		var axis := (Vector3(0.3 * side, 0.25, Tuning.CONTACT_DEPTH) - hip).normalized()
		var off := knee - hip - axis * (knee - hip).dot(axis)
		runner.check(off.x * side > 0.0, "%s 무릎 바깥 %.3f" % [limb, off.x])
		runner.check(Anatomy.twist_ok(limb, Anatomy.limb_twist(limb, hip, knee, Vector3(0.3 * side, 0.25, Tuning.CONTACT_DEPTH), F)), "%s 비틀림 범위 안" % limb)


## 머리 바로 위 홀드: 아래팔이 머리를 뚫지 않는 굽힘을 고른다.
func test_arm_avoids_head() -> void:
	var pelvis := Vector3(0, 1.0, 0.30)
	var sh := Vector3(0.2, 1.55, 0.30)
	var hold := Vector3(-0.05, 2.05, Tuning.CONTACT_DEPTH)
	var r := LimbIK.solve_limb(&"RH", sh, hold, F, pelvis, Vector3.UP, Vector3.ZERO, INF)
	var hd := Anatomy.arm_head_distance(sh, r.mid, hold, pelvis + Vector3.UP * Anatomy.HEAD_CENTER_UP)
	runner.check(hd >= Anatomy.HEAD_CLEARANCE, "팔과 머리 거리 %.3f" % hd)


## 발 방향: 정강이와의 발목 각이 범위 안.
func test_foot_direction_ankle_range() -> void:
	for shin in [Vector3(0, -1, 0), Vector3(0, -0.3, -1), Vector3(0, 0.2, -1), Vector3(0.5, -0.5, 0.7)]:
		var knee := Vector3(0, 1, 0.3)
		var ankle := knee + (shin as Vector3).normalized() * 0.48
		var f := Anatomy.foot_direction(knee, ankle, F)
		var a := rad_to_deg((ankle - knee).angle_to(f))
		runner.check(a >= Anatomy.ANKLE_RANGE.x and a <= Anatomy.ANKLE_RANGE.y, "정강이 %s 발목 %.0f°" % [shin, a])


## 루트마다 시작 자세는 위반이 없다.
func test_start_poses_clean() -> void:
	for r in ContentIndex.load_all().all_routes():
		var s := ClimbSession.new(r)
		var pose := ClimberPose.new()
		var t := {}
		for i in 30:
			s.step()
			t = pose.compute(s, Tuning.DT)
		var v := Anatomy.check(t, s.body.angle, s.body.yaw)
		runner.check(v.is_empty(), "%s 시작 자세 위반 %s" % [r.route_id, v])


## 무작위 패드 조작 스윕: 관절이 한 틱에 뒤집히지 않고(굽힘 방향 변화 FLIP_DEG 이하), 불가능한 자세는 드물다.
## IK가 고를 수 있었는데 위반한 경우는 반대쪽 가능한 자세로 연속해 돌아가는 짧은 구간뿐이다(5% 이하).
func test_sweep_regression() -> void:
	var poses := 0
	var all := 0
	var forced := 0
	var flips := 0
	for id in ["C_ARM_LOAD_T", "C_CROSS_1", "G_V3_01"]:
		var sw := AnatomySweep.run(RouteDef.load_json(ContentIndex.route_path(id)), 600, 11)
		poses += sw.poses
		all += sw.total()
		for k in sw.forced:
			forced += sw.forced[k]
		for l in sw.flips:
			flips += sw.flips[l]
	runner.check(poses > 1500, "점검한 자세 %d" % poses)
	runner.check(flips == 0, "관절 뒤집힘 %d" % flips)
	runner.check(all - forced <= poses * 5 / 100, "IK가 놓친 위반 %d / %d" % [all - forced, poses])
	# 강제된 위반 = 판정이 허용한 손발 위치에서 어떤 굽힘도 범위 안에 들지 않는 경우(크로스 루트에 많다).
	# 2026-11-08 기준 이 세 루트 8.6%, 전체 22개 루트 4.5%(발을 옮길 때 무릎 처짐 금지 규칙을 넣은 뒤). 회귀 감시용 상한.
	runner.check(forced <= poses * 12 / 100, "강제된 위반 %d / %d" % [forced, poses])


## 사용자 보고(2026-11-08): 다리를 낮은 곳에서 높은 곳으로 올릴 때 관절이 갑자기 반대로 꺾였다(0.9.5에서 6만 6천 자세 중 319번).
## 양발을 여러 가로 위치에서 엉덩이 높이까지 올려도 관절이 한 틱에 뒤집히지 않는다.
func test_leg_lift_never_flips() -> void:
	for id in ["G_V0_01", "C_HIGH_STEP_T", "C_DROP_FOOT_T"]:
		var r := RouteDef.load_json(ContentIndex.route_path(id))
		for foot in [&"LF", &"RF"]:
			for ox in [-0.3, 0.0, 0.3]:
				for rise in [-0.25, 0.0]:
					var sw := AnatomySweep.run_lift(r, foot, ox, rise, 1.2)
					var f := 0
					for l in sw.flips:
						f += sw.flips[l]
					runner.check(f == 0, "%s %s 가로 %.2f 높이 %.2f 뒤집힘 %d %s" % [id, foot, ox, rise, f, sw.flip_examples])


## 사용자 보고(2026-11-08): 발을 들어 옮길 때 무릎이 발보다 아래로 처지는 드롭니 모양이 나왔다.
## 드롭니는 발이 붙은 채 몸을 움직일 때만 생기고, 발을 옮기는 동안에는 무릎이 들리고 정강이는 무릎에서 발로 내려간다.
## 발을 뗀 직후 바로잡히는 몇 틱만 허용한다.
func test_free_leg_no_drop_knee() -> void:
	for id in ["G_V4_01", "G_V0_01"]:
		var r := RouteDef.load_json(ContentIndex.route_path(id))
		for foot in [&"LF", &"RF"]:
			for ox in [0.3, 0.0]:
				for rise in [-0.25, 0.0]:
					var sw := AnatomySweep.run_lift(r, foot, ox, rise, 1.0)
					var n: int = sw.counts.get("free_drop_knee/%s" % foot, 0)
					runner.check(n <= 15, "%s %s 가로 %.2f 높이 %.2f 무릎 처짐 %d틱" % [id, foot, ox, rise, n])
