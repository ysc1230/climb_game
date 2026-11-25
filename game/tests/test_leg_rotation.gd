extends RefCounted
## 발 방향(2026-11-25 사용자 "어딜 밟아도 발의 모양은 항상 위에서 밟는 것처럼 신발이 정직하게 위치해 있어. 심각한 문제야"):
## 발끝은 늘 벽 쪽·약간 아래(FOOT_WANT) 하나였다. 이제 무릎이 향하는 쪽을 따른다 — 무릎이 바깥(개구리 자세)이면 발끝도 바깥(안쪽 날로 딛기),
## 드롭니(무릎 안쪽)면 발끝이 안쪽(바깥 날), 무릎이 벽 쪽이면 벽 쪽. 발목 각은 범위 안, 발끝은 벽에서 멀어지지 않는다.

var runner
const F := Basis()


func _toe(hip: Vector3, knee: Vector3, ankle: Vector3) -> Vector3:
	return Anatomy.foot_direction(knee, ankle, F, hip)


func test_foot_follows_knee() -> void:
	var hip := Vector3(0.1, 0.75, 0.3)
	var ankle := hip + Vector3(0.05, -0.55, -0.2)
	var mid := (hip + ankle) * 0.5
	var into_wall := _toe(hip, mid + Vector3(0, 0, -0.25), ankle)
	runner.check(into_wall.z < -0.7, "무릎이 벽 쪽이면 발끝도 벽 쪽 %s" % into_wall)
	var out := _toe(hip, mid + Vector3(0.28, 0.02, 0.05), ankle)
	runner.check(out.x > 0.5 and out.z <= -0.15, "무릎이 바깥이면 발끝도 바깥(벽에서 멀어지지는 않음) %s" % out)
	var drop := _toe(hip, mid + Vector3(-0.25, -0.05, -0.05), ankle)
	runner.check(drop.x < -0.3, "드롭니(무릎 안쪽)면 발끝이 안쪽 %s" % drop)
	for k in [mid + Vector3(0, 0, -0.25), mid + Vector3(0.28, 0.02, 0.05), mid + Vector3(-0.25, -0.05, -0.05), mid + Vector3(0.1, 0.25, -0.1)]:
		var a := rad_to_deg((ankle - k).angle_to(_toe(hip, k, ankle)))
		runner.check(a >= Anatomy.ANKLE_RANGE.x and a <= Anatomy.ANKLE_RANGE.y, "발목 각 범위 안 %.0f°" % a)
	var straight := _toe(hip, hip + (ankle - hip) * 0.5, ankle)
	runner.check(straight.is_equal_approx(Anatomy.foot_direction(hip + (ankle - hip) * 0.5, ankle, F)), "다리가 펴졌으면 예전 방향")


## 엉덩이 높이 옆 홀드를 딛은 발: 실제 자세에서 발끝이 정면(벽 쪽)만이 아니라 무릎 쪽으로 돌고, 발끝은 홀드 윗면에 그대로 있다.
func test_stuck_foot_turns_with_knee() -> void:
	var d := RouteDraft.new()
	d.route_id = "U_FOOT"
	var f1 := d.place("foot_chip", -0.15, 0.1)
	var f2 := d.place("foot_big", 0.40, 0.70)
	var h1 := d.place("jug", -0.34, 1.5)
	var h2 := d.place("jug", 0.34, 1.5)
	d.place("goal", 0.0, 2.6)
	d.set_start(&"LH", h1); d.set_start(&"RH", h2); d.set_start(&"LF", f1); d.set_start(&"RF", f2)
	var p := d.start_pose()
	var s := ClimbSession.new(d.build(p.pelvis, p.angle))
	var pose := ClimberPose.new()
	var key: String = s.limbs[&"RF"].key
	pose.surface_depth[key] = 0.06
	pose.surface_top[key] = 0.03
	var t := {}
	for i in 90:
		s.step()
		t = pose.compute(s, Tuning.DT)
	var toe_dir: Vector3 = (t.toe_R - t.ankle_R).normalized()
	var turned := rad_to_deg(toe_dir.angle_to(Anatomy.FOOT_WANT.normalized()))
	runner.check(turned > 10.0, "예전 고정 방향(정면·약간 아래)에서 돎 %.0f° %s" % [turned, toe_dir])
	var hold: Vector2 = s.route.slot_pos(key)
	runner.check((t.toe_R as Vector3).distance_to(Vector3(hold.x, hold.y + 0.03, 0.06 * ClimberPose.TOE_IN_HOLD)) < 0.001, "발끝은 홀드 윗면 그대로 %s" % t.toe_R)


## 쪼그린 시작 자세(징검다리): 무릎이 바깥으로 벌어진 발은 발끝도 바깥(예전에는 두 발 모두 벽 정면).
func test_squat_feet_turn_out() -> void:
	var s := ClimbSession.new(RouteDef.load_json("res://data/routes/general/G_V0_02.json"))
	var pose := ClimberPose.new()
	var t := {}
	for i in 90:
		s.step()
		t = pose.compute(s, Tuning.DT)
	var l: Vector3 = (t.toe_L - t.ankle_L).normalized()
	runner.check(l.x < -0.3, "왼발 발끝이 왼쪽(바깥)으로 %s" % l)


## 팔꿈치·무릎을 옮길 때 어깨·고관절 돌림 한계를 넘어 한 바퀴(±180°) 돌지 않는다. 2026-11-25 사용자(V6-2 화면 두 장): "팔꿈치 방향이
## 밑에서 오른쪽 위쪽 순서로 움직여. 이런 외회전은 불가능", "발도 내회전 외회전 둘 다 불가능한지 확인". 손이 어깨 옆·아래면 팔꿈치가
## 아래(바깥돌림 +118°)에서 위로 바깥돌림 한계 너머(+118° → ±180° → −101°)로 넘어갔다.
func _twists(limb: StringName, root: Vector3, end: Vector3, start: Vector3, pelvis: Vector3) -> Array:
	var c := LimbIK.circle(limb, root, end, F, pelvis, Vector3.UP, 36, false)
	var bend := (start - (c.dir as Vector3) * start.dot(c.dir)).normalized()
	var out := []
	for i in 40:
		var r := LimbIK.solve_circle(c, bend, 3.0)
		bend = r.bend
		out.append(Anatomy.limb_twist(limb, root, r.mid, end, F))
	return out


func test_elbow_does_not_wrap_past_rotation_limit() -> void:
	var pelvis := Vector3(0.22, 1.07, 0.25)
	var sh := pelvis + Vector3(-0.175, 0.49, 0)
	for hand_off in [Vector3(-0.35, -0.30, 0.05), Vector3(-0.30, -0.05, 0.10)]:
		var tw := _twists(&"LH", sh, sh + hand_off, Vector3(0, -1, 0), pelvis)
		runner.check(tw.all(func(v): return is_nan(v) or v > 0.0), "팔꿈치가 아래(바깥돌림)에서 위(안쪽돌림)로 한 바퀴 넘어가지 않음 %s" % [tw.slice(0, 6)])
		runner.check(Anatomy.twist_ok(&"LH", tw[-1]), "어깨 돌림 한계 안에 머묾 %.0f°" % tw[-1])


func test_knee_returns_inside_rotation_limit() -> void:
	var pelvis := Vector3(0.22, 1.07, 0.25)
	var hip := pelvis + Vector3(0.095, 0, 0)
	for start in [Vector3(0, -1, 0), Vector3(-1, 0, 0)]:
		var tw := _twists(&"RF", hip, hip + Vector3(0.05, -0.60, -0.25), start, pelvis)
		runner.check(Anatomy.twist_ok(&"RF", tw[-1]), "고관절 안쪽돌림 한계 밖(−70° 넘음)에서 시작해도 한계 안으로 %.0f°" % tw[-1])
		var wrapped := false
		for i in range(1, tw.size()):
			if not is_nan(tw[i]) and not is_nan(tw[i - 1]) and absf(tw[i] - tw[i - 1]) > 180.0:
				wrapped = true
		runner.check(not wrapped, "±180°를 건너 반대쪽으로 넘어가지 않음 %s" % [tw.slice(0, 6)])


## 발(발목 아래)은 정강이 축 둘레로 다리 평면(허벅지를 정강이에 수직으로 한 방향)에서 FOOT_TWIST_MAX까지만 돈다(2026-11-25 사용자
## "발도 내회전 외회전 둘 다 불가능한지 확인"). 무릎이 옆·뒤를 볼 때 벽 쪽 섞기로 발이 정강이 둘레 147°까지 비틀렸다.
func test_foot_twist_within_limit() -> void:
	var hip := Vector3(0.1, 0.75, 0.3)
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 4000:
		var ankle := hip + Vector3(rng.randf_range(-0.4, 0.6), rng.randf_range(-0.75, 0.2), rng.randf_range(-0.35, -0.05))
		var d := hip.distance_to(ankle)
		if d > 0.8 or d < 0.2:
			continue
		var axis := (ankle - hip).normalized()
		var perp := axis.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		var x := (0.41 * 0.41 - 0.40 * 0.40 + d * d) / (2.0 * d)
		var knee := hip + axis * x + perp * sqrt(maxf(0.41 * 0.41 - x * x, 0.0))
		var shin := (ankle - knee).normalized()
		var thigh := (knee - hip).normalized()
		var side := thigh - shin * thigh.dot(shin)
		if side.length() < 0.1:
			continue
		var f := _toe(hip, knee, ankle)
		var fp := f - shin * f.dot(shin)
		if fp.length() < 0.05:
			continue
		worst = maxf(worst, absf(rad_to_deg(side.normalized().signed_angle_to(fp.normalized(), shin))))
	runner.check(worst <= Anatomy.FOOT_TWIST_MAX + 1.0, "발 돌림 최대 %.0f° ≤ %.0f°" % [worst, Anatomy.FOOT_TWIST_MAX])


## 딛은 발 다리는 몸이 내려가도 사람이 할 수 있는 무릎 자리가 남는다. 2026-11-26 사용자(V0-2 화면): "무릎이 불가능한 각도야. 그리고
## 발도 문제가 있어". 엉덩이 높이 오른발(F06)을 딛은 채 몸을 왼쪽 아래로 옮기면 발끝 기준으로 놓은 발목(발 길이만큼 벽 밖·위)이
## 엉덩이에 0.24m까지 다가와 무릎 자리가 하나도 없었고(가장 나은 굽힘도 위반 1.7), 무릎이 안돌림 한계 너머 −86°로 접혔다.
## 판정 다리 길이(엉덩이→홀드 접점, 최소 0.24)는 발 길이를 뺀 발목 자리를 모른다. 발끝은 홀드에 둔 채 뒤꿈치를 돌려 다리가 접힐 자리를 낸다.
func test_stuck_foot_leg_possible_when_hips_sink() -> void:
	var r := RouteDef.load_json("res://data/routes/general/G_V0_03.json")
	var s: ClimbSession = SessionBot.run(r, r.steps_raw.slice(0, 4)).session
	var pose := ClimberPose.new()
	for key in r.slots:
		pose.surface_depth[key] = 0.07
		pose.surface_top[key] = 0.05
	var moves := [[Vector2(-0.007879, 0.002713), 64], [Vector2(-0.00146, -0.008204), 70], [Vector2(-0.007655, -0.003293), 80]]
	var worst := 0.0
	var worst_v := 0.0
	for m in moves:
		s.apply_input([{"type": "body_start"}])
		for i in int(m[1]):
			s.apply_input([{"type": "body_move", "delta": m[0]}])
			s.step()
			var t := pose.compute(s, Tuning.DT)
			var fr := Anatomy.body_basis(s.body.angle, float(t.yaw))
			for side in ["L", "R"]:
				var limb := StringName(side + "F")
				var tw := Anatomy.limb_twist(limb, t["hip_" + side], t["knee_" + side], t["ankle_" + side], fr)
				if not is_nan(tw):
					worst = maxf(worst, maxf(Anatomy.LEG_TWIST.x - tw, tw - Anatomy.LEG_TWIST.y))
				worst_v = maxf(worst_v, LimbIK.min_violation(limb, t["hip_" + side], t["ankle_" + side], fr, t.pelvis, t.up))
		s.apply_input([{"type": "body_end"}])
	runner.check(worst <= 5.0, "무릎 돌림이 한계를 넘지 않음(넘은 최대 %.0f°)" % worst)
	runner.check(worst_v <= 0.1, "무릎 자리가 늘 있음(가장 나은 굽힘의 위반 최대 %.2f)" % worst_v)
