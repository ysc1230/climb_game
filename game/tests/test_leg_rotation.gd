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
