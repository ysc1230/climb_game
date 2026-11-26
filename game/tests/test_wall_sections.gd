extends RefCounted
## 꺾이는 벽(docs/57, 2026-11-24 사용자 "하나의 문제에 여러 각도"): 문제 JSON wall_sections → 높이마다 벽 각도,
## 그 각도로 벽면을 접는 WallProfile(화면), 세션 틱의 힘 계산 각도.

var runner


func _route(sections: Array, grade := "V5") -> RouteDef:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/routes/general/G_V5_01.json"))
	d.grade = grade
	if sections.is_empty():
		d.erase("wall_sections")
	else:
		d["wall_sections"] = sections
	return RouteDef.from_dict(d)


func test_angle_at_sections_and_blend() -> void:
	var r := _route([{"from_y": 0.0, "deg": 30}, {"from_y": 1.2, "deg": 60}])
	runner.check(is_equal_approx(r.angle_at(0.5), 30.0) and is_equal_approx(r.angle_at(-0.4), 30.0), "아래 구간 30°(매트 쪽까지)")
	runner.check(is_equal_approx(r.angle_at(1.6), 60.0) and is_equal_approx(r.angle_at(5.0), 60.0), "위 구간 60°")
	runner.check(is_equal_approx(r.angle_at(1.2), 45.0), "경계 가운데는 반반 %.1f" % r.angle_at(1.2))
	var prev := 0.0
	for i in 31:
		var a := r.angle_at(1.2 - RouteDef.WALL_BLEND + i * RouteDef.WALL_BLEND * 2.0 / 30.0)
		runner.check(a >= prev - 1e-6, "경계에서 부드럽게 늘어남 %.2f" % a)
		prev = a
	runner.check(is_equal_approx(r.wall_deg, 60.0) and r.wall_desc() == "150° → 120°", "가장 큰 각도 %.0f, 설명 %s" % [r.wall_deg, r.wall_desc()])
	var three := _route([{"from_y": 0.0, "deg": 50}, {"from_y": 0.8, "deg": 60}, {"from_y": 1.6, "deg": 30}])
	runner.check(is_equal_approx(three.angle_at(0.4), 50.0) and is_equal_approx(three.angle_at(1.2), 60.0) and is_equal_approx(three.angle_at(2.2), 30.0), "세 구간 50·60·30")
	runner.check(three.wall_desc() == "130° → 120° → 150°", "세 구간 설명 %s" % three.wall_desc())


func test_no_sections_uses_grade_angle() -> void:
	var r := _route([], "V5")
	runner.check(is_equal_approx(r.angle_at(0.3), GradeInfo.wall_deg("V5")) and is_equal_approx(r.angle_at(3.0), GradeInfo.wall_deg("V5")), "구간 없으면 등급 각도 하나")
	runner.check(r.wall_desc() == "%d°" % (180 - roundi(GradeInfo.wall_deg("V5"))), "설명 %s" % r.wall_desc())
	runner.check(r.wall_sections.is_empty(), "구간 없음")


func test_session_uses_angle_at_pelvis() -> void:
	var r := _route([{"from_y": 0.0, "deg": 30}, {"from_y": 1.2, "deg": 60}])
	var s := ClimbSession.new(r)
	s.step()
	runner.check(is_equal_approx(ClimbRules.wall_deg, r.angle_at(s.body.pos.y)), "틱 각도 = 골반 높이 각도 %.1f" % ClimbRules.wall_deg)
	s.body.pos.y = 1.8
	s.step()
	runner.check(is_equal_approx(ClimbRules.wall_deg, 60.0), "골반이 위 구간이면 60°")


func test_profile_single_section_matches_old_rotation() -> void:
	var r := _route([], "V5")
	var wp := WallProfile.new(r, -1.0, 4.0)
	var rot := Basis(Vector3.RIGHT, deg_to_rad(r.wall_deg))
	for p in [Vector3(0, 0, 0), Vector3(0.4, 1.3, 0.1), Vector3(-0.7, 2.5, -0.05), Vector3(0.2, -0.3, 0.3)]:
		runner.check(wp.point(p).distance_to(rot * p) < 0.002, "한 구간 = 예전 벽 회전 %s" % [p])


func test_profile_folds_continuously() -> void:
	var r := _route([{"from_y": 0.0, "deg": 30}, {"from_y": 1.2, "deg": 60}])
	var wp := WallProfile.new(r, -1.0, 4.0)
	var prev := wp.point(Vector3(0, 0.6, 0.05))
	for i in range(1, 121):
		var q := wp.point(Vector3(0, 0.6 + i * 0.01, 0.05))
		runner.check(q.distance_to(prev) < 0.012, "벽면을 따라 1cm씩 연속 %d" % i)
		prev = q
	# 면을 따라 잰 길이는 펼친 높이와 같다(접어도 길이 유지)
	var a := wp.point(Vector3(0, 0.0, 0))
	var b := wp.point(Vector3(0, 2.0, 0))
	runner.check(b.distance_to(a) < 2.0 and b.distance_to(a) > 1.8, "꺾여 곧은 거리는 2m보다 짧음 %.3f" % b.distance_to(a))
	var up := wp.basis_at(2.0) * Vector3.UP
	runner.check(absf(rad_to_deg(atan2(up.z, up.y)) - 60.0) < 0.5, "위 구간 면 방향 60°")
	var n := wp.basis_at(0.5) * Vector3.BACK
	runner.check(absf(n.dot(wp.basis_at(0.5) * Vector3.UP)) < 1e-5 and is_equal_approx(n.length(), 1.0), "틀은 직교")
	# 월드 높이 → 벽면 높이(카메라·추락용)
	for s in [0.3, 1.0, 1.7, 2.6]:
		var wy := wp.point(Vector3(0, s, 0)).y
		runner.check(absf(wp.s_at_world_y(wy) - s) < 0.01, "월드 높이 %.2f → 벽면 %.2f" % [wy, wp.s_at_world_y(wy)])
	var prof := wp.world_profile(0.02)
	runner.check(prof.size() > 10 and prof[0].x < prof[-1].x, "추락용 단면(월드 y 오름차순)")


## 시점 카메라가 벽을 뚫지 않게(2026-11-24 사용자 "화면이 벽을 뚫는다거나 벽 안의 빈 공간을 보게 돼"):
## 그 높이의 벽면에서 gap보다 가까우면(또는 벽 뒤면) 벽면 법선으로 밀어낸다. 충분히 앞이면 그대로.
func test_push_in_front_of_wall() -> void:
	var r := _route([{"from_y": 0.0, "deg": 30}, {"from_y": 1.2, "deg": 60}])
	var wp := WallProfile.new(r, -1.0, 4.0)
	var behind := wp.point(Vector3(0.5, 2.0, -0.4))  # 60° 구간 벽 뒤
	var q := wp.push_in_front(behind, 0.6)
	var s := wp.s_at_world_y(q.y)
	var lz := (wp.frame(s).affine_inverse() * q).z
	runner.check(lz >= 0.59, "벽 뒤 카메라를 벽면 앞 0.6m로 %.3f" % lz)
	var front := wp.point(Vector3(0.2, 1.0, 3.0))
	runner.check(wp.push_in_front(front, 0.6).distance_to(front) < 1e-4, "충분히 앞이면 그대로")


## 시점이 벽 면을 거의 옆·위에서 보면 벽이 종이처럼 얇고 볼륨·뒤가 비쳐 보인다(2026-11-25 사용자 "벽이 통과해서 보여"):
## 어느 구간이든 면에서 CAM_MIN_VIEW 이상 떨어진 방향으로만 돌린다. 처음 시점부터 비스듬한 구간은 처음 시점보다 나빠지지만 않게.
func test_camera_never_grazes_wall() -> void:
	var PT := load("res://scenes/play_test.gd")
	var r := _route([{"from_y": 0.0, "deg": 30}, {"from_y": 1.5, "deg": 60}])
	runner.check(PT.cam_view_ok(r, 0.0, 0.0, 1.0), "처음 시점은 됨")
	runner.check(PT.cam_view_ok(r, deg_to_rad(40.0), 0.0, 1.0), "옆으로 40°는 됨")
	runner.check(PT.cam_view_ok(r, 0.0, deg_to_rad(30.0), 1.0), "아래에서 올려다보기는 됨")
	runner.check(not PT.cam_view_ok(r, deg_to_rad(85.0), 0.0, 1.0), "옆 85°(벽이 종이처럼)는 안 됨")
	runner.check(not PT.cam_view_ok(r, 0.0, deg_to_rad(-35.0), 1.0), "60° 구간을 위에서 내려다보기는 안 됨")
	var ceil := _route([{"from_y": 0.0, "deg": 30}, {"from_y": 1.5, "deg": 90}])
	runner.check(PT.cam_view_ok(ceil, 0.0, 0.0, 1.0), "90° 천장이 있어도 처음 시점은 됨")
